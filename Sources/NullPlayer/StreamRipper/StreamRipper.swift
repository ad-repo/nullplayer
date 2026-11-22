import Foundation
import AppKit

/// A cross-process exclusive lease on a rip's staging directory, held for the
/// directory's entire life — download, transcode, and the final copy to the
/// destination. The lease is an advisory `flock` taken on the directory's own
/// file descriptor, so there is no lock file for the recovery/move paths to
/// sweep into the user's folders, and the kernel releases it automatically if
/// the owning process crashes.
///
/// It exists because modification time alone cannot prove a rip is inactive:
/// copying a finished multi-gigabyte file to a slow NAS only *reads* the staged
/// file, so its mtime can age past the reaper's threshold while the transfer is
/// still running. While this lease is held, the launch-time reaper in another
/// NullPlayer instance cannot delete the tree out from under an active rip.
final class StagingLease: @unchecked Sendable {
    private let fd: Int32
    let directory: URL

    /// Opens `directory` and takes a non-blocking exclusive lock. Returns nil if
    /// the directory can't be opened or is already leased — for a freshly
    /// created UUID staging dir the latter never happens, so a nil result here
    /// simply means the rip proceeds without reaper protection.
    init?(_ directory: URL) {
        let handle = open(directory.path, O_RDONLY)
        guard handle >= 0 else { return nil }
        guard flock(handle, LOCK_EX | LOCK_NB) == 0 else {
            close(handle)
            return nil
        }
        self.fd = handle
        self.directory = directory
    }

    /// Releases the lease and closes the descriptor. Call once, after the
    /// staging directory has been removed or its contents recovered.
    func release() {
        flock(fd, LOCK_UN)
        close(fd)
    }
}

/// Rips a media URL to a local file using `yt-dlp` (with `ffmpeg` for audio
/// extraction / container merging). Audio mode extracts audio only; video mode
/// downloads the full video to a file.
///
/// This is intentionally self-contained: it shells out to a system-installed
/// `yt-dlp` rather than bundling helper binaries. If the tool is missing the
/// user is told how to install it.
@MainActor
enum StreamRipper {

    enum Mode: Codable, Sendable, Equatable, CustomStringConvertible {
        /// `kbps` is the requested rate of a lossy encode (`RipAudioFormat.takesBitrate`), else nil.
        case audio(RipAudioFormat, kbps: Int? = nil)
        /// Video transcodes to a playback-safe MP4 profile after download.
        case video(VideoProfile)

        var description: String {
            switch self {
            case .audio(let format, let kbps): "audio \(format.rawValue)" + (kbps.map { " \($0)k" } ?? "")
            case .video(let profile): profile.description
            }
        }

        var isVideo: Bool { if case .video = self { true } else { false } }

        /// Requested file extension (logging / diagnostics only — the real
        /// extension is decided by yt-dlp and read back after the rip).
        var fileExtension: String {
            switch self {
            case .audio(let format, _): return format.rawValue
            case .video: return "mp4"
            }
        }
    }

    /// Directories searched for `yt-dlp` / `ffmpeg` (Homebrew arm64, Homebrew
    /// x86, MacPorts, system). Made nonisolated for use in async/await contexts.
    nonisolated private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]

    /// Resolves a tool executable path from the known system locations, or nil.
    /// This is nonisolated since it doesn't depend on MainActor state.
    nonisolated static func resolveTool(_ name: String) -> String? {
        for dir in Self.searchPaths {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Resolves the `yt-dlp` executable path, or nil if it is not installed.
    /// This is nonisolated since it doesn't depend on MainActor state.
    nonisolated static func resolveYtDlp() -> String? { resolveTool("yt-dlp") }

    /// Download audio from a URL using yt-dlp, with specified format arguments and output template.
    /// This is a low-level, stateless function suitable for embedding in other tools (e.g., YouTube manager).
    /// It does not handle UI (spinners, alerts) — callers provide their own.
    /// This function is nonisolated and can be called from any actor context.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL to download audio from
    ///   - formatSelector: yt-dlp `-f` stream selector (e.g. `"bestaudio/best"`)
    ///   - formatArgs: yt-dlp audio format arguments (e.g., `["--audio-format","flac","--audio-quality","0"]`)
    ///     and any other extras (e.g. thumbnail embedding)
    ///   - outputTemplate: yt-dlp output filename template (e.g., `"/path/to/downloads/%(id)s.%(ext)s"`)
    /// - Returns: A file:// URL to the downloaded audio file
    /// - Throws: If yt-dlp is not found, the download fails, or the output path cannot be resolved
    nonisolated static func downloadAudio(
        from sourceURL: URL,
        formatSelector: String,
        formatArgs: [String],
        outputTemplate: String
    ) async throws -> URL {
        try await trackedDownload(of: sourceURL, summary: "youtube audio") { handle in
            try performDownloadAudio(from: sourceURL, formatSelector: formatSelector, formatArgs: formatArgs,
                                           outputTemplate: outputTemplate, handle: handle)
        }
    }

    /// Runs a YouTube download as a job in `RipJobCenter`, so the Rip window lists it with its
    /// progress and can cancel it. A cancel is thrown as `CancellationError`.
    nonisolated private static func trackedDownload(
        of sourceURL: URL, summary: String, _ body: (RipJobHandle) async throws -> URL
    ) async throws -> URL {
        let handle = await RipJobCenter.shared.beginExternal(source: .youtube, url: sourceURL, summary: summary)
        do {
            let fileURL = try await body(handle)
            let size = StreamRipper.fileSize(fileURL.path)
            await RipJobCenter.shared.finish(handle, outputPath: fileURL.path, sizeBytes: size, error: nil)
            return fileURL
        } catch {
            await RipJobCenter.shared.finish(handle, outputPath: nil, sizeBytes: nil, error: error.localizedDescription)
            throw handle.isCancelled ? CancellationError() : error
        }
    }

    nonisolated private static func performDownloadAudio(
        from sourceURL: URL,
        formatSelector: String,
        formatArgs: [String],
        outputTemplate: String,
        handle: RipJobHandle
    ) throws -> URL {
        let args = ["-f", formatSelector, "-x"] + formatArgs + ["--no-playlist", "--embed-metadata"]
        return try performDownload(sourceURL, args: args, outputTemplate: outputTemplate, isVideo: false, handle: handle)
    }

    /// A YouTube download: yt-dlp into local staging, then a move to the template's folder. A
    /// cancel keeps nothing; any other failure recovers the staging contents to ~/Downloads.
    nonisolated private static func performDownload(
        _ sourceURL: URL, args: [String], outputTemplate: String, isVideo: Bool, handle: RipJobHandle
    ) throws -> URL {
        guard let ytdlp = Self.resolveTool("yt-dlp") else {
            throw DownloadAudioError.toolNotFound("yt-dlp is not installed. Install via Homebrew: brew install yt-dlp")
        }
        guard let staging = Self.makeLocalStaging(for: outputTemplate) else {
            throw DownloadAudioError.processStartFailed("Could not create a temporary download folder")
        }
        // Declared first so it runs last: the lease outlives every cleanup and
        // recovery path, releasing only once the staging dir is gone/emptied.
        defer { staging.lease?.release() }
        var stagingHandled = false
        defer {
            if !stagingHandled {
                _ = Self.recoverStagingContents(from: staging.stagingDir)
            }
        }

        let run: YtDlpRun
        do {
            run = try runYtDlp(ytdlp, args + ["-o", staging.stagingTemplate, sourceURL.absoluteString],
                               isVideo: isVideo, handle: handle)
        } catch is CancellationError {
            run = YtDlpRun(status: -1, stderr: "", outputPath: nil)
        } catch {
            throw DownloadAudioError.processStartFailed(error.localizedDescription)
        }
        if handle.isCancelled {
            // A cancel keeps nothing, so nothing is recovered to ~/Downloads.
            try? FileManager.default.removeItem(at: staging.stagingDir)
            stagingHandled = true
            throw CancellationError()
        }
        guard run.status == 0, let finalPath = run.outputPath else {
            let fallback = run.outputPath == nil
                ? "yt-dlp did not report output path"
                : "yt-dlp exited with code \(run.status)"
            throw DownloadAudioError.downloadFailed(run.stderr.isEmpty ? fallback : run.stderr)
        }

        do {
            let destinationURL = try Self.moveDownloaded(
                stagedPath: finalPath,
                toDir: staging.destinationDir
            )
            try? FileManager.default.removeItem(at: staging.stagingDir)
            stagingHandled = true
            return destinationURL
        } catch {
            let recovery = Self.recoverStagingContents(from: staging.stagingDir)
            stagingHandled = true
            throw DownloadAudioError.downloadFailed(
                "Downloaded to a temporary folder but could not be moved to the destination: \(error.localizedDescription)\n\n"
                + recovery.message
            )
        }
    }

    /// What one yt-dlp run left behind.
    struct YtDlpRun {
        let status: Int32
        let stderr: String
        /// The path yt-dlp moved the finished file to, or nil when it reported none.
        let outputPath: String?
    }

    /// One yt-dlp run as `handle`'s process: progress lines feed the job, stderr is collected,
    /// and the final path is read back (its extension depends on the codec). Throws
    /// `CancellationError` when the job was cancelled before it could start.
    nonisolated private static func runYtDlp(
        _ ytdlp: String, _ args: [String], isVideo: Bool, handle: RipJobHandle
    ) throws -> YtDlpRun {
        let pathFile = NSTemporaryDirectory() + "nullplayer-rip-path-\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: pathFile) }
        // Ensure yt-dlp can find ffmpeg even when launched without a login PATH.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (Self.searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ytdlp)
        task.arguments = ["--print-to-file", "after_move:filepath", pathFile] + YtDlpProgressReader.args + args
        task.environment = env
        let errPipe = Pipe()
        task.standardError = errPipe
        // stdout carries the progress lines. It must be read as it arrives: an unread Pipe()
        // fills its ~64KB OS buffer mid-download and blocks the process forever.
        let progressPipe = Pipe()
        task.standardOutput = progressPipe
        let progress = YtDlpProgressReader(handle: handle, isVideo: isVideo)
        progressPipe.fileHandleForReading.readabilityHandler = { progress.consume($0.availableData) }
        defer { progressPipe.fileHandleForReading.readabilityHandler = nil }

        try handle.launch(task)
        log(handle.id, "yt-dlp started pid=\(task.processIdentifier)")
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        handle.processExited()
        let reported = (try? String(contentsOfFile: pathFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return YtDlpRun(status: task.terminationStatus,
                        stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                        outputPath: reported?.isEmpty == false ? reported : nil)
    }

    /// The tallest H.264 stream YouTube serves; anything taller is VP9 or AV1 only.
    nonisolated private static let youTubeH264MaxHeight = 1080

    /// Download video from a URL using yt-dlp, fetched as video + AAC audio remuxed to MP4. Up to
    /// 1080p the video is H.264 only (YouTube's H.264 stops there); above that it is whatever the
    /// highest resolution comes in (VP9 / AV1), still preferring H.264 when it ties.
    /// This is a low-level, stateless function suitable for embedding in other tools (e.g., YouTube manager).
    /// It does not handle UI (spinners, alerts) — callers provide their own.
    /// This function is nonisolated and can be called from any actor context.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL to download video from
    ///   - maxHeight: Maximum video height in pixels (e.g. 720, 2160); nil for no cap
    ///   - outputTemplate: yt-dlp output filename template (e.g., `"/path/to/downloads/%(id)s.%(ext)s"`)
    ///   - extraArgs: additional yt-dlp arguments (e.g. thumbnail embedding), inserted before the URL
    /// - Returns: A file:// URL to the downloaded video file
    /// - Throws: If yt-dlp is not found, the download fails, or the output path cannot be resolved
    nonisolated static func downloadVideo(
        from sourceURL: URL,
        maxHeight: Int?,
        outputTemplate: String,
        extraArgs: [String] = []
    ) async throws -> URL {
        try await trackedDownload(of: sourceURL, summary: "youtube video") { handle in
            try performDownloadVideo(from: sourceURL, maxHeight: maxHeight, outputTemplate: outputTemplate,
                                           extraArgs: extraArgs, handle: handle)
        }
    }

    nonisolated private static func performDownloadVideo(
        from sourceURL: URL,
        maxHeight: Int?,
        outputTemplate: String,
        extraArgs: [String],
        handle: RipJobHandle
    ) throws -> URL {
        let codecFilter = (maxHeight ?? .max) <= Self.youTubeH264MaxHeight ? "[vcodec^=avc1]" : ""
        let filter = codecFilter + (maxHeight.map { "[height<=\($0)]" } ?? "")
        let args = ["-f", "bv*\(filter)+ba[acodec^=mp4a]/b\(filter)", "-S", "res,fps,vcodec:h264",
                    "--merge-output-format", "mp4", "--no-playlist", "--embed-metadata"] + extraArgs
        return try performDownload(sourceURL, args: args, outputTemplate: outputTemplate, isVideo: true, handle: handle)
    }

    // MARK: - Local staging for the download helpers

    /// Rewrites an output template so yt-dlp downloads into a fresh local staging
    /// directory, returning the caller's original destination directory so the
    /// finished file can be moved there afterward. yt-dlp streams to a `.part`
    /// file, `fsync`s it, and renames it into place — patterns that fail on a
    /// network mount (NAS via SMB/AFP) with "Bad file descriptor" and similar
    /// errors, but work fine on a local volume. Returns nil if the staging
    /// directory can't be created.
    nonisolated private static func makeLocalStaging(for outputTemplate: String)
        -> (stagingDir: URL, stagingTemplate: String, destinationDir: String, lease: StagingLease?)? {
        let destinationDir: String
        let filenamePattern: String
        if let idx = outputTemplate.lastIndex(of: "/") {
            destinationDir = String(outputTemplate[..<idx])
            filenamePattern = String(outputTemplate[outputTemplate.index(after: idx)...])
        } else {
            destinationDir = FileManager.default.currentDirectoryPath
            filenamePattern = outputTemplate
        }
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-ytdl-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        // Lease the directory so the reaper (this or another instance) cannot
        // delete it while the download/transcode/transfer is still running.
        let lease = StagingLease(stagingDir)
        return (stagingDir, stagingDir.path + "/" + filenamePattern, destinationDir, lease)
    }

    /// Copy a staged download directly to a collision-free final filename.
    /// Existing downloads are preserved and no destination-side temporary file
    /// or rename is used. Returns the final URL.
    nonisolated private static func moveDownloaded(stagedPath: String, toDir destinationDir: String) throws -> URL {
        let desiredURL = URL(fileURLWithPath: destinationDir)
            .appendingPathComponent(URL(fileURLWithPath: stagedPath).lastPathComponent)
        return try transferStagedFile(
            from: URL(fileURLWithPath: stagedPath),
            to: desiredURL,
            replaceExisting: false
        )
    }

    /// Copy a completed local staging file directly to the destination. Normal
    /// media transfers choose a collision-free final filename, so existing files
    /// remain untouched and SMB/AFP sees one sequential copy with no destination
    /// rename. Replacement is reserved for the small CUE sidecar; its temporary
    /// sibling uses a normal visible filename for NAS compatibility.
    @discardableResult
    nonisolated static func transferStagedFile(
        from sourceURL: URL,
        to desiredURL: URL,
        replaceExisting: Bool
    ) throws -> URL {
        let fm = FileManager.default
        let destinationExists = fm.fileExists(atPath: desiredURL.path)
        let copyURL: URL
        let finalURL: URL

        if replaceExisting, destinationExists {
            copyURL = desiredURL.deletingLastPathComponent()
                .appendingPathComponent(
                    "\(desiredURL.lastPathComponent).nullplayer-transfer-\(UUID().uuidString)"
                )
            finalURL = desiredURL
        } else {
            let finalPath = replaceExisting
                ? desiredURL.path
                : availableFilePath(for: desiredURL.path)
            finalURL = URL(fileURLWithPath: finalPath)
            copyURL = finalURL
        }

        do {
            try fm.copyItem(at: sourceURL, to: copyURL)
            if copyURL != finalURL {
                _ = try fm.replaceItemAt(finalURL, withItemAt: copyURL)
            }

            // The destination copy is complete; staging can now be removed.
            try? fm.removeItem(at: sourceURL)
            return finalURL
        } catch {
            // Remove only the new partial/temporary copy. Existing destinations
            // are never used as the direct copy target.
            if copyURL != desiredURL || !destinationExists {
                try? fm.removeItem(at: copyURL)
            }
            throw error
        }
    }

    struct StagingRecoveryResult {
        let recoveryDirectory: URL
        let recoveredURLs: [URL]
        let remainingStagingURL: URL?

        var message: String {
            var parts: [String] = []
            if recoveredURLs.count == 1, let recovered = recoveredURLs.first {
                parts.append("The file was recovered to \(recovered.path).")
            } else if !recoveredURLs.isEmpty {
                parts.append(
                    "\(recoveredURLs.count) files were recovered to \(recoveryDirectory.path)."
                )
            }
            if let remainingStagingURL {
                parts.append(
                    "Some files could not be recovered and remain at \(remainingStagingURL.path)."
                )
            } else if recoveredURLs.isEmpty {
                parts.append("No recoverable files remained in local staging.")
            }
            return parts.joined(separator: "\n\n")
        }
    }

    /// Move every remaining staging item into the user's visible Downloads
    /// folder. Successful recovery removes the temporary `/var/folders` staging
    /// directory; if Downloads cannot be written, staging is left intact.
    @discardableResult
    nonisolated static func recoverStagingContents(
        from stagingDirectory: URL,
        to recoveryDirectoryOverride: URL? = nil
    ) -> StagingRecoveryResult {
        let fm = FileManager.default
        let recoveryDirectory = recoveryDirectoryOverride
            ?? fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        var recoveredURLs: [URL] = []

        do {
            try fm.createDirectory(
                at: recoveryDirectory,
                withIntermediateDirectories: true
            )
            let items = try fm.contentsOfDirectory(
                at: stagingDirectory,
                includingPropertiesForKeys: nil
            )
            for item in items {
                let desiredPath = recoveryDirectory
                    .appendingPathComponent(item.lastPathComponent)
                    .path
                let recoveredURL = URL(
                    fileURLWithPath: availableFilePath(for: desiredPath)
                )
                try fm.moveItem(at: item, to: recoveredURL)
                recoveredURLs.append(recoveredURL)
            }
            try? fm.removeItem(at: stagingDirectory)
            return StagingRecoveryResult(
                recoveryDirectory: recoveryDirectory,
                recoveredURLs: recoveredURLs,
                remainingStagingURL: nil
            )
        } catch {
            return StagingRecoveryResult(
                recoveryDirectory: recoveryDirectory,
                recoveredURLs: recoveredURLs,
                remainingStagingURL: stagingDirectory
            )
        }
    }

    /// Filename prefixes for disk-significant temporary artifacts created by
    /// interrupted rip, waveform-prerender, and skin-extraction operations.
    nonisolated static let tempItemPrefixes = [
        "nullplayer-rip-",
        "nullplayer-ytdl-",
        WaveformCacheService.prerenderTempPrefix,
        ModernSkinLoader.temporaryDirectoryPrefix,
        SkinLoader.temporaryDirectoryPrefix,
    ]

    /// Delete orphaned temporary artifacts left by interrupted operations.
    /// Meant to be called once at app launch, off the main thread. macOS only
    /// purges `/var/folders/.../T` after days of inactivity and usually only on
    /// reboot, so large downloads can sit there indefinitely.
    ///
    /// An item is deleted only when an exclusive lease can be acquired and it
    /// has not been modified for at least `minInactivity` seconds. Rip staging
    /// directories hold the same lease throughout active work; the inactivity
    /// guard protects waveform files and skin directories, whose producers are
    /// short-lived and do not hold a lease.
    nonisolated static func reapOrphanedTempItems(
        in tempDirectory: URL = FileManager.default.temporaryDirectory,
        minInactivity: TimeInterval = 600
    ) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-minInactivity)
        guard let entries = try? fm.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        var reclaimed = 0
        for entry in entries {
            let name = entry.lastPathComponent
            guard Self.tempItemPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            // Acquire the item's lease non-blocking. A live rip (in this or
            // another process) holds its directory lease, so failure means the
            // item may be active — leave it alone.
            guard let lease = StagingLease(entry) else { continue }
            defer { lease.release() }
            // Belt-and-braces under the held lease: skip anything modified
            // recently (covers staging left by an older build with no lease).
            if let newest = Self.newestModification(in: entry), newest > cutoff { continue }
            if (try? fm.removeItem(at: entry)) != nil {
                reclaimed += 1
            }
        }
        if reclaimed > 0 {
            NSLog("StreamRipper: reaped %d orphaned temporary item(s) from %@", reclaimed, tempDirectory.path)
        }
    }

    /// Newest content-modification date of `item` itself or any nested file.
    /// Used to distinguish an idle artifact from one still being written; a
    /// directory's own mtime does not change when an existing child is updated.
    private nonisolated static func newestModification(in item: URL) -> Date? {
        let key: URLResourceKey = .contentModificationDateKey
        var newest = (try? item.resourceValues(forKeys: [key]))?.contentModificationDate
        guard let enumerator = FileManager.default.enumerator(
            at: item,
            includingPropertiesForKeys: [key]
        ) else { return newest }
        for case let url as URL in enumerator {
            if let mtime = (try? url.resourceValues(forKeys: [key]))?.contentModificationDate,
               newest == nil || mtime > newest! {
                newest = mtime
            }
        }
        return newest
    }

    /// Error type for downloadAudio
    enum DownloadAudioError: LocalizedError {
        case toolNotFound(String)
        case processStartFailed(String)
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .toolNotFound(let msg): return msg
            case .processStartFailed(let msg): return "Failed to start yt-dlp: \(msg)"
            case .downloadFailed(let msg): return msg
            }
        }
    }

    // MARK: - Rip job

    /// yt-dlp and ffmpeg, or nil when either is missing (`missingToolsMessage`).
    nonisolated static func resolveRipTools() -> (ytdlp: String, ffmpeg: String)? {
        guard let ytdlp = resolveYtDlp(), let ffmpeg = resolveTool("ffmpeg") else { return nil }
        return (ytdlp, ffmpeg)
    }

    nonisolated static let missingToolsMessage =
        "Ripping requires yt-dlp and ffmpeg. Install them with: brew install yt-dlp ffmpeg"

    /// Runs one rip on a background queue (download, convert, save), reporting through `handle`,
    /// and ends its job with `RipJobCenter.finish`.
    nonisolated static func run(_ handle: RipJobHandle, mode: Mode, sourceURL: URL, folder: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = performRip(handle, mode: mode, sourceURL: sourceURL, folder: folder)
            let size = result.outputPath.flatMap(fileSize)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    RipJobCenter.shared.finish(handle, outputPath: result.outputPath, sizeBytes: size, error: result.error)
                }
            }
        }
    }

    /// The source's audio bitrate in kbit/s as yt-dlp reports it for `selector`, or nil.
    private nonisolated static func sourceAudioKbps(ytdlp: String, selector: String, url: URL, handle: RipJobHandle) -> Int? {
        guard let output = RipProcess.run(ytdlp, ["--quiet", "--no-warnings", "--no-playlist", "-f", selector,
                                                  "--print", "abr", url.absoluteString], handle: handle)
        else { return nil }
        let text = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(text).map { Int($0.rounded()) }
    }

    private nonisolated static func performRip(
        _ handle: RipJobHandle, mode: Mode, sourceURL: URL, folder: String
    ) -> (outputPath: String?, error: String?) {
        let ripID = handle.id
        let fm = FileManager.default
        guard let tools = resolveRipTools() else { return (nil, missingToolsMessage) }

        // Stage the whole rip on the local disk, then move the finished file(s)
        // to `folder` at the end. Downloading/transcoding straight onto a network
        // mount (NAS via SMB/AFP) fails: yt-dlp's `.part` rename + fsync and
        // ffmpeg's `+faststart` seek-back trigger "Bad file descriptor" and
        // similar errors that never happen on a local volume.
        let stagingFolder = fm.temporaryDirectory
            .appendingPathComponent("nullplayer-rip-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        } catch {
            return (nil, "Could not create a temporary download folder: \(error.localizedDescription)")
        }
        // Lease the staging dir so the reaper cannot delete it mid-rip. Declared first so it is
        // released last, after every cleanup and recovery path below.
        let stagingLease = StagingLease(stagingFolder)
        defer { stagingLease?.release() }

        // For audio rips, capture the source's chapter list so we can write a
        // .cue sheet when the video has timestamps (e.g. album/mix uploads).
        var chaptersFile: String?
        defer { if let chaptersFile { try? fm.removeItem(atPath: chaptersFile) } }

        let started = Date()
        /// A failure: remaining staging files go to ~/Downloads, and the message says where.
        func fail(_ message: String) -> (String?, String?) {
            log(ripID, "failed after \(elapsed(since: started)): \(message.suffix(2000))")
            return (nil, message + "\n\n" + recoverStagingContents(from: stagingFolder).message)
        }
        /// A cancel: nothing is kept, so nothing is recovered to ~/Downloads.
        func cancelled() -> (String?, String?) {
            try? fm.removeItem(at: stagingFolder)
            return (nil, nil)
        }

        // Embed source metadata (title/artist/album/date, etc.) into the file.
        var args: [String] = ["--no-playlist", "--embed-metadata"]
        let outputTemplate: String
        switch mode {
        case .audio(let format, let requested):
            var kbps = requested ?? RipAudioFormat.defaultKbps
            if format.takesBitrate {
                let source = sourceAudioKbps(ytdlp: tools.ytdlp, selector: format.formatSelector, url: sourceURL, handle: handle)
                if handle.isCancelled { return cancelled() }
                if let source, source < kbps {
                    log(ripID, "source audio is \(source)k, below the \(kbps)k requested; capping to \(source)k")
                    kbps = source
                } else if source == nil {
                    log(ripID, "source audio bitrate unknown; encoding at \(kbps)k")
                }
            }
            // Embed the thumbnail as cover art (converted to jpg for compatibility).
            args += format.ytdlpArgs(kbps: kbps) + ["--embed-thumbnail", "--convert-thumbnails", "jpg"]
            let cf = NSTemporaryDirectory() + "nullplayer-chapters-\(UUID().uuidString).json"
            chaptersFile = cf
            args += ["--print-to-file", "after_move:%(chapters)j", cf]
            // Name the file from the source metadata: "Artist - Title" when an artist
            // is available, otherwise just the title.
            outputTemplate = "\(stagingFolder.path)/%(artist|)s%(artist& - |)s%(title)s.%(ext)s"
        case .video(let profile):
            // Download the best source streams at the selected height cap, then
            // normalize with ffmpeg to a predictable MP4 (or copy into one; see `copiesSource`).
            args += ["-f", profile.ytdlpFormat, "-S", "res,fps,br", "--merge-output-format", "mkv"]
            outputTemplate = "\(stagingFolder.path)/%(artist|)s%(artist& - |)s%(title)s [source].%(ext)s"
        }
        args += ["-o", outputTemplate, sourceURL.absoluteString]

        let run: YtDlpRun
        do {
            run = try runYtDlp(tools.ytdlp, args, isVideo: mode.isVideo, handle: handle)
        } catch is CancellationError {
            return cancelled()
        } catch {
            return fail("yt-dlp could not start: \(error.localizedDescription)")
        }
        var outputPath = run.outputPath
        log(ripID, "yt-dlp exited status=\(run.status) after \(elapsed(since: started))"
            + " output=\(outputPath.map(fileSizeDescription) ?? "unreported")")
        if handle.isCancelled { return cancelled() }
        guard run.status == 0 else {
            return fail(run.stderr.isEmpty ? "yt-dlp exited with code \(run.status)." : run.stderr)
        }

        if case .video(let profile) = mode, let sourcePath = outputPath {
            switch transcodeVideoForPlayback(inputPath: sourcePath, profile: profile, ffmpeg: tools.ffmpeg, handle: handle) {
            case .success(let compatiblePath):
                outputPath = compatiblePath
            case .failure(let error):
                return handle.isCancelled ? cancelled() : fail(error.message)
            }
        }

        // Move the finished file off the local staging disk onto the
        // destination folder (which may be a NAS). A single sequential
        // copy is well supported over SMB/AFP, unlike the streaming write
        // the download itself performs.
        handle.report(.phase(.moving))
        if let staged = outputPath {
            switch moveRippedFile(from: staged, toFolder: folder) {
            case .success(let moved): outputPath = moved
            case .failure(let error): return fail(error.message)
            }
        } else {
            // yt-dlp succeeded but didn't report the exact path; move whatever landed in
            // staging so the file still reaches the destination.
            do {
                try moveAllContents(of: stagingFolder, toFolder: folder)
            } catch {
                return fail("The completed download could not be moved to the destination: " + error.localizedDescription)
            }
        }

        // Build the .cue locally, then transfer it through the same safe
        // destination-volume commit used by the media file.
        if let path = outputPath, let cf = chaptersFile {
            let chapters = readChapters(from: cf)
            if chapters.count >= 2 {
                do {
                    try writeCueFile(audioPath: path, chapters: chapters, stagingFolder: stagingFolder)
                } catch {
                    return fail("The media file was saved to \(path), but its .cue sheet could not be saved: "
                        + error.localizedDescription)
                }
            }
        }

        try? fm.removeItem(at: stagingFolder)
        return (outputPath, nil)
    }

    // MARK: - Staging → destination move

    /// Copy a single finished file from local staging directly to a
    /// collision-free final filename in `folder`.
    private nonisolated static func moveRippedFile(from stagingPath: String, toFolder folder: String) -> Result<String, TranscodeError> {
        let fileName = URL(fileURLWithPath: stagingPath).lastPathComponent
        let desiredURL = URL(fileURLWithPath: folder).appendingPathComponent(fileName)
        do {
            let finalURL = try transferStagedFile(
                from: URL(fileURLWithPath: stagingPath),
                to: desiredURL,
                replaceExisting: false
            )
            return .success(finalURL.path)
        } catch {
            return .failure(TranscodeError(message: "Downloaded to a temporary folder but could not be moved to the destination: \(error.localizedDescription)"))
        }
    }

    /// Best-effort move of every top-level item in the staging dir to `folder`.
    /// Used as a fallback when yt-dlp didn't report the exact output path.
    private nonisolated static func moveAllContents(of stagingFolder: URL, toFolder folder: String) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: stagingFolder, includingPropertiesForKeys: nil)
        guard !items.isEmpty else {
            throw TranscodeError(message: "yt-dlp did not report an output path and the staging folder is empty")
        }
        for item in items {
            let desiredURL = URL(fileURLWithPath: folder)
                .appendingPathComponent(item.lastPathComponent)
            try transferStagedFile(
                from: item,
                to: desiredURL,
                replaceExisting: false
            )
        }
    }

    // MARK: - Cue sheet

    private struct Chapter {
        let start: Double
        let title: String
    }

    /// Parse the chapter JSON array yt-dlp wrote (or an empty array if none).
    private nonisolated static func readChapters(from path: String) -> [Chapter] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "NA", trimmed != "null",
              let data = trimmed.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.enumerated().compactMap { index, entry in
            guard let start = entry["start_time"] as? Double else { return nil }
            let title = (entry["title"] as? String) ?? "Track \(index + 1)"
            return Chapter(start: start, title: title)
        }
    }

    /// Build a CUE sheet in local staging, then commit it next to the audio file.
    private nonisolated static func writeCueFile(
        audioPath: String,
        chapters: [Chapter],
        stagingFolder: URL
    ) throws {
        let audioURL = URL(fileURLWithPath: audioPath)
        let fileName = audioURL.lastPathComponent
        let base = audioURL.deletingPathExtension().lastPathComponent

        // Derive album/performer from the "Artist - Title" filename convention.
        var album = base
        var performer = ""
        if let range = base.range(of: " - ") {
            performer = String(base[..<range.lowerBound])
            album = String(base[range.upperBound...])
        }

        // CUE FILE type: MP3 for mp3, WAVE is widely accepted for lossless.
        let fileType = audioURL.pathExtension.lowercased() == "mp3" ? "MP3" : "WAVE"

        func quote(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "'") }

        var lines: [String] = []
        if !performer.isEmpty { lines.append("PERFORMER \"\(quote(performer))\"") }
        lines.append("TITLE \"\(quote(album))\"")
        lines.append("FILE \"\(quote(fileName))\" \(fileType)")
        for (index, chapter) in chapters.enumerated() {
            lines.append(String(format: "  TRACK %02d AUDIO", index + 1))
            lines.append("    TITLE \"\(quote(chapter.title))\"")
            if !performer.isEmpty { lines.append("    PERFORMER \"\(quote(performer))\"") }
            lines.append("    INDEX 01 \(cueTimestamp(chapter.start))")
        }

        let destinationCueURL = audioURL.deletingPathExtension().appendingPathExtension("cue")
        let stagedCueURL = stagingFolder
            .appendingPathComponent(destinationCueURL.lastPathComponent)
        try (lines.joined(separator: "\n") + "\n")
            .write(to: stagedCueURL, atomically: true, encoding: .utf8)

        try transferStagedFile(
            from: stagedCueURL,
            to: destinationCueURL,
            replaceExisting: true
        )
    }

    /// Format seconds as a CUE MM:SS:FF timestamp (75 frames per second).
    private nonisolated static func cueTimestamp(_ seconds: Double) -> String {
        let totalFrames = Int((seconds * 75).rounded())
        let frames = totalFrames % 75
        let totalSeconds = totalFrames / 75
        return String(format: "%02d:%02d:%02d", totalSeconds / 60, totalSeconds % 60, frames)
    }

    // MARK: - Video compatibility transcode

    private nonisolated static let videoSourceSuffix = " [source]"

    private struct TranscodeError: Error {
        let message: String
    }

    nonisolated static func compatibleVideoOutputPath(forIntermediatePath inputPath: String) -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let folderURL = inputURL.deletingLastPathComponent()
        var baseName = inputURL.deletingPathExtension().lastPathComponent
        if baseName.hasSuffix(videoSourceSuffix) {
            baseName.removeLast(videoSourceSuffix.count)
        }

        let desired = folderURL.appendingPathComponent(baseName).appendingPathExtension("mp4").path
        return availableFilePath(for: desired, excluding: inputPath)
    }

    private nonisolated static func availableFilePath(for desiredPath: String, excluding excludedPath: String? = nil) -> String {
        let fm = FileManager.default
        guard desiredPath != excludedPath, fm.fileExists(atPath: desiredPath) else {
            return desiredPath
        }

        let desiredURL = URL(fileURLWithPath: desiredPath)
        let folderURL = desiredURL.deletingLastPathComponent()
        let baseName = desiredURL.deletingPathExtension().lastPathComponent
        let ext = desiredURL.pathExtension

        for index in 1..<10_000 {
            let candidateURL = folderURL
                .appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension(ext)
            let candidate = candidateURL.path
            if candidate != excludedPath, !fm.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return folderURL
            .appendingPathComponent("\(baseName) \(UUID().uuidString)")
            .appendingPathExtension(ext)
            .path
    }

    private nonisolated static func transcodeVideoForPlayback(
        inputPath: String,
        profile: VideoProfile,
        ffmpeg: String,
        handle: RipJobHandle
    ) -> Result<String, TranscodeError> {
        let ripID = handle.id
        let fm = FileManager.default
        let finalPath = compatibleVideoOutputPath(forIntermediatePath: inputPath)
        let finalURL = URL(fileURLWithPath: finalPath)
        let stagingURL = finalURL
            .deletingLastPathComponent()
            .appendingPathComponent(".nullplayer-rip-\(UUID().uuidString)", isDirectory: true)
        let tempPath = stagingURL.appendingPathComponent("encoded").appendingPathExtension("mp4").path

        do {
            try fm.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        } catch {
            return .failure(TranscodeError(message: "Could not create a temporary video encode folder: \(error.localizedDescription)"))
        }

        let source = probeSource(at: inputPath, ffmpeg: ffmpeg)
        let sourceDescription = "\(source.videoCodec ?? "?") \(source.height.map { "\($0)p" } ?? "?")"
            + " \(source.audioCodec ?? "?") \(source.kbps.map { "\($0)k" } ?? "?")"
        var args = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", inputPath,
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-map_metadata", "0",
        ]
        let copies = profile.copiesSource(codec: source.videoCodec, height: source.height)
        if copies {
            log(ripID, "source \(sourceDescription) plays on a 4K Chromecast; copying it without re-encoding")
            // AVPlayer and Chromecasts want HEVC tagged `hvc1`; a copied `hev1` stream may not play.
            args += ["-c:v", "copy"] + (source.videoCodec == "hevc" ? ["-tag:v", "hvc1"] : [])
                + (source.audioCodec == "aac" ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", profile.audioBitrate])
        } else {
            if profile.format == .original {
                log(ripID, "source \(sourceDescription) is not castable as-is; encoding HEVC instead")
            }
            let rates = profile.cappedRates(sourceKbps: source.kbps)
            if rates.target < profile.videoKbps {
                log(ripID, "source is \(source.kbps ?? 0)k, below \(profile)'s \(profile.videoKbps)k target;"
                    + " capping to b:v=\(rates.target)k maxrate=\(rates.max)k bufsize=\(rates.buffer)k")
            }
            args += ["-vf", videoScaleFilter(maxHeight: profile.maxHeight)] + profile.videoCodecArgs + [
                "-pix_fmt", "yuv420p",
                "-b:v", "\(rates.target)k",
                "-maxrate", "\(rates.max)k",
                "-bufsize", "\(rates.buffer)k",
                "-c:a", "aac",
                "-b:a", profile.audioBitrate,
            ]
        }
        args += [
            "-movflags", "+faststart",
            // Machine-readable progress on stdout, read below; logged every 5 minutes.
            "-progress", "pipe:1",
            "-stats_period", "1",
            tempPath,
        ]

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = args

        let progressPipe = Pipe()
        task.standardOutput = progressPipe
        let progress = FFmpegProgressReader(handle: handle, duration: source.duration)
        progressPipe.fileHandleForReading.readabilityHandler = { progress.consume($0.availableData) }
        defer { progressPipe.fileHandleForReading.readabilityHandler = nil }

        let errPipe = Pipe()
        task.standardError = errPipe

        // A real encode waits for the one hardware encoder; a copy is disk-bound and runs at once.
        if !copies {
            handle.report(.phase(.queuedForEncode))
            guard RipEncodeQueue.acquire(for: handle) else {
                try? fm.removeItem(at: stagingURL)
                return .failure(TranscodeError(message: "cancelled"))
            }
        }
        defer { if !copies { RipEncodeQueue.release() } }
        handle.report(.phase(.converting))

        let encodeStart = Date()
        do {
            try handle.launch(task)
        } catch {
            log(ripID, "ffmpeg failed to start: \(error.localizedDescription)")
            try? fm.removeItem(at: stagingURL)
            return .failure(TranscodeError(message: "ffmpeg could not start: \(error.localizedDescription)"))
        }
        log(ripID, "ffmpeg started pid=\(task.processIdentifier) profile=\(profile)"
            + " source=\(fileSizeDescription(inputPath)) \(sourceDescription)")

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        handle.processExited()
        log(ripID, "ffmpeg exited status=\(task.terminationStatus) reason=\(task.terminationReason == .uncaughtSignal ? "signal" : "exit")"
            + " after \(elapsed(since: encodeStart)) output=\(fileSizeDescription(tempPath))")

        guard task.terminationStatus == 0 else {
            try? fm.removeItem(at: stagingURL)
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            log(ripID, "ffmpeg stderr: \(errText?.suffix(2000) ?? "")")
            return .failure(TranscodeError(message: errText.map { !$0.isEmpty } == true
                ? "ffmpeg failed while creating a playback-compatible MP4:\n\(errText ?? "")"
                : "ffmpeg failed while creating a playback-compatible MP4."))
        }

        do {
            if fm.fileExists(atPath: finalPath) {
                try fm.removeItem(atPath: finalPath)
            }
            try fm.moveItem(atPath: tempPath, toPath: finalPath)
            if inputPath != finalPath {
                try? fm.removeItem(atPath: inputPath)
            }
            try? fm.removeItem(at: stagingURL)
            return .success(finalPath)
        } catch {
            try? fm.removeItem(at: stagingURL)
            return .failure(TranscodeError(message: "The compatible MP4 was encoded but could not be saved: \(error.localizedDescription)"))
        }
    }

    /// What the downloaded source holds. A field ffprobe cannot read is nil: an unknown bitrate
    /// leaves the profile's rates uncapped, an unknown codec is never copied.
    private struct SourceInfo {
        var kbps: Int?
        var videoCodec: String?
        var height: Int?
        var audioCodec: String?
        var duration: Double?
    }

    /// Reads the source with the `ffprobe` beside `ffmpeg`.
    private nonisolated static func probeSource(at path: String, ffmpeg: String) -> SourceInfo {
        let ffprobe = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().appendingPathComponent("ffprobe").path
        guard let output = RipProcess.run(ffprobe, ["-v", "error", "-show_entries",
                                                    "format=bit_rate,duration:stream=codec_type,codec_name,height",
                                                    "-of", "json", path]),
              let json = (try? JSONSerialization.jsonObject(with: output.stdout)) as? [String: Any]
        else { return SourceInfo() }
        let streams = json["streams"] as? [[String: Any]] ?? []
        let video = streams.first { $0["codec_type"] as? String == "video" }
        let audio = streams.first { $0["codec_type"] as? String == "audio" }
        let format = json["format"] as? [String: Any]
        let bitRate = format?["bit_rate"] as? String
        return SourceInfo(
            kbps: bitRate.flatMap(Int.init).map { $0 / 1000 },
            videoCodec: video?["codec_name"] as? String,
            height: video?["height"] as? Int,
            audioCodec: audio?["codec_name"] as? String,
            duration: (format?["duration"] as? String).flatMap(Double.init)
        )
    }

    private nonisolated static func videoScaleFilter(maxHeight: Int?) -> String {
        if let maxHeight {
            return "scale=-2:trunc(min(\(maxHeight)\\,ih)/2)*2"
        }
        return "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    }

    // MARK: - Logging

    /// One rip's log line, tagged with its short id so a rip's phases can be followed. URLs and
    /// file paths are redacted: tool errors quote both, and they name what the user rips and
    /// where it is kept. The job row still shows the full error.
    nonisolated static func log(_ ripID: String, _ message: String) {
        NSLog("StreamRipper[%@]: %@", ripID, redacted(message))
    }

    nonisolated static func redacted(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://\S+"#, with: "<url>", options: .regularExpression)
            .replacingOccurrences(of: #"/(Users|Volumes|private|var|tmp)/[^\n:'"]*"#, with: "<path>",
                                  options: .regularExpression)
    }

    private nonisolated static func elapsed(since start: Date) -> String {
        formatDuration(Date().timeIntervalSince(start))
    }

    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%dh%02dm%02ds", s / 3600, s / 60 % 60, s % 60)
    }

    /// A file's size in bytes, or nil when it is missing.
    nonisolated static func fileSize(_ path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
    }

    /// A file's size for the log; never its path, which can name the user's folders.
    private nonisolated static func fileSizeDescription(_ path: String) -> String {
        fileSize(path).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "missing"
    }

    // MARK: - Playing a rip

    /// Play a ripped file: video opens in the video player window, audio loads into the player
    /// (same path as opening a file from Finder).
    static func play(path: String) {
        let url = URL(fileURLWithPath: path)
        if AudioFileValidator.isVideoFile(url: url) {
            WindowManager.shared.showVideoPlayer(url: url, title: Track(url: url).displayTitle)
        } else {
            let engine = WindowManager.shared.audioEngine
            engine.loadFiles([url])
            engine.play()
        }
    }
}
