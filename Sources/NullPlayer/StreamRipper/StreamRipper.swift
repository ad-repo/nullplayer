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
enum StreamRipper {

    /// Directories searched for `yt-dlp` / `ffmpeg` (Homebrew arm64, Homebrew
    /// x86, MacPorts, system).
    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]

    /// Resolves a tool executable path from the known system locations, or nil.
    static func resolveTool(_ name: String) -> String? {
        for dir in Self.searchPaths {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Resolves the `yt-dlp` executable path, or nil if it is not installed.
    static func resolveYtDlp() -> String? { resolveTool("yt-dlp") }

    /// Download audio from a URL using yt-dlp, with specified format arguments and output template.
    /// This is a low-level, stateless function suitable for embedding in other tools (e.g., YouTube manager).
    /// It does not handle UI (spinners, alerts) — callers provide their own.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL to download audio from
    ///   - formatSelector: yt-dlp `-f` stream selector (e.g. `"bestaudio/best"`)
    ///   - formatArgs: yt-dlp audio format arguments (e.g., `["--audio-format","flac","--audio-quality","0"]`)
    ///     and any other extras (e.g. thumbnail embedding)
    ///   - outputTemplate: yt-dlp output filename template (e.g., `"/path/to/downloads/%(id)s.%(ext)s"`)
    /// - Returns: A file:// URL to the downloaded audio file
    /// - Throws: If yt-dlp is not found, the download fails, or the output path cannot be resolved
    static func downloadAudio(
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
    private static func trackedDownload(
        of sourceURL: URL, summary: String, _ body: (RipJobHandle) async throws -> URL
    ) async throws -> URL {
        let handle = await RipJobCenter.shared.beginExternal(url: sourceURL, summary: summary)
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

    private static func performDownloadAudio(
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
    private static func performDownload(
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

        /// A cancel keeps nothing, so nothing is recovered to ~/Downloads.
        func discardCancelled() -> CancellationError {
            try? FileManager.default.removeItem(at: staging.stagingDir)
            stagingHandled = true
            return CancellationError()
        }

        let run: YtDlpRun
        do {
            run = try runYtDlp(ytdlp, args + ["-o", staging.stagingTemplate, sourceURL.absoluteString],
                               isVideo: isVideo, handle: handle)
        } catch is CancellationError {
            throw discardCancelled()
        } catch {
            throw DownloadAudioError.processStartFailed(error.localizedDescription)
        }
        if handle.isCancelled { throw discardCancelled() }
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
    static func runYtDlp(_ ytdlp: String, _ args: [String], isVideo: Bool, handle: RipJobHandle) throws -> YtDlpRun {
        let pathFile = NSTemporaryDirectory() + "nullplayer-rip-path-\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: pathFile) }
        // Ensure yt-dlp can find ffmpeg even when launched without a login PATH.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (Self.searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        let progress = YtDlpProgressReader(handle: handle, isVideo: isVideo)
        let output = try RipProcess.run(ytdlp, ["--print-to-file", "after_move:filepath", pathFile] + YtDlpProgressReader.args + args,
                                        environment: env, handle: handle, onStdout: { progress.consume($0) })
        let reported = (try? String(contentsOfFile: pathFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return YtDlpRun(status: output.status, stderr: output.stderr, outputPath: reported?.isEmpty == false ? reported : nil)
    }

    /// The tallest H.264 stream YouTube serves; anything taller is VP9 or AV1 only.
    private static let youTubeH264MaxHeight = 1080

    /// Download video from a URL using yt-dlp, fetched as video + AAC audio remuxed to MP4. Up to
    /// 1080p the video is H.264 only (YouTube's H.264 stops there); above that it is whatever the
    /// highest resolution comes in (VP9 / AV1), still preferring H.264 when it ties.
    /// This is a low-level, stateless function suitable for embedding in other tools (e.g., YouTube manager).
    /// It does not handle UI (spinners, alerts) — callers provide their own.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL to download video from
    ///   - maxHeight: Maximum video height in pixels (e.g. 720, 2160); nil for no cap
    ///   - outputTemplate: yt-dlp output filename template (e.g., `"/path/to/downloads/%(id)s.%(ext)s"`)
    ///   - extraArgs: additional yt-dlp arguments (e.g. thumbnail embedding), inserted before the URL
    /// - Returns: A file:// URL to the downloaded video file
    /// - Throws: If yt-dlp is not found, the download fails, or the output path cannot be resolved
    static func downloadVideo(
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

    private static func performDownloadVideo(
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
    private static func makeLocalStaging(for outputTemplate: String)
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
    private static func moveDownloaded(stagedPath: String, toDir destinationDir: String) throws -> URL {
        let desiredURL = URL(fileURLWithPath: destinationDir)
            .appendingPathComponent(URL(fileURLWithPath: stagedPath).lastPathComponent)
        return try transferStagedFile(from: URL(fileURLWithPath: stagedPath), to: desiredURL)
    }

    /// Copy a completed local staging file directly to a collision-free final
    /// filename at the destination, so existing files remain untouched and SMB/AFP
    /// sees one sequential copy with no destination rename.
    @discardableResult
    static func transferStagedFile(from sourceURL: URL, to desiredURL: URL) throws -> URL {
        try withTransferLock {
            let finalURL = URL(fileURLWithPath: availableFilePath(for: desiredURL.path))
            try commitStagedCopy(from: sourceURL, to: finalURL)
            return finalURL
        }
    }

    /// Transfers run one at a time: two jobs saving the same name must not both pick it. A caller
    /// committing several files under one name (a rip and its `.cue`) holds it across all of them.
    /// ponytail: one lock for every destination, so a slow NAS copy holds up a local one; lock
    /// per destination folder if that is ever felt.
    static func withTransferLock<T>(_ body: () throws -> T) rethrows -> T {
        try transferLock.withLock(body)
    }

    /// Copy a staged file to `destination`, then remove the staged copy. The destination is
    /// created here with `O_EXCL` or not at all, so a file anyone else put at that name — another
    /// process, past the transfer lock — is never written or removed; a failed copy removes only
    /// the partial file this call created.
    static func commitStagedCopy(from source: URL, to destination: URL) throws {
        func lastError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let input = open(source.path, O_RDONLY)
        guard input >= 0 else { throw lastError() }
        defer { close(input) }
        let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard output >= 0 else { throw lastError() }
        var copyError = fcopyfile(input, output, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 ? nil : lastError()
        // A network volume can report a failed write only here (`EIO` from `close`).
        if close(output) != 0, copyError == nil { copyError = lastError() }
        if let copyError {
            try? FileManager.default.removeItem(at: destination)
            throw copyError
        }
        try? FileManager.default.removeItem(at: source)
    }

    private static let transferLock = NSLock()

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
    static func recoverStagingContents(
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
    static let tempItemPrefixes = [
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
    static func reapOrphanedTempItems(
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
    private static func newestModification(in item: URL) -> Date? {
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

    static func availableFilePath(
        for desiredPath: String,
        excluding excludedPath: String? = nil,
        reservingSiblingExtension siblingExtension: String? = nil
    ) -> String {
        let fm = FileManager.default
        func isTaken(_ path: String) -> Bool {
            if fm.fileExists(atPath: path) { return true }
            guard let siblingExtension else { return false }
            let sibling = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension(siblingExtension)
            return fm.fileExists(atPath: sibling.path)
        }
        guard desiredPath != excludedPath, isTaken(desiredPath) else {
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
            if candidate != excludedPath, !isTaken(candidate) {
                return candidate
            }
        }

        return folderURL
            .appendingPathComponent("\(baseName) \(UUID().uuidString)")
            .appendingPathExtension(ext)
            .path
    }

    // MARK: - Logging

    /// One rip's log line, tagged with its short id so a rip's phases can be followed. URLs and
    /// file paths are redacted: tool errors quote both, and they name what the user rips and
    /// where it is kept. The job row still shows the full error.
    static func log(_ ripID: String, _ message: String) {
        NSLog("StreamRipper[%@]: %@", ripID, redacted(message))
    }

    static func redacted(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://\S+"#, with: "<url>", options: .regularExpression)
            .replacingOccurrences(of: #"/(Users|Volumes|private|var|tmp)/[^\n:'"]*"#, with: "<path>",
                                  options: .regularExpression)
    }

    static func elapsed(since start: Date) -> String {
        formatDuration(Date().timeIntervalSince(start))
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%dh%02dm%02ds", s / 3600, s / 60 % 60, s % 60)
    }

    /// A file's size in bytes, or nil when it is missing.
    static func fileSize(_ path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
    }

    /// A file's size for the log; never its path, which can name the user's folders.
    static func fileSizeDescription(_ path: String) -> String {
        fileSize(path).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "missing"
    }

    // MARK: - Playing a rip

    /// Play a ripped file: video opens in the video player window, audio loads into the player
    /// (same path as opening a file from Finder).
    @MainActor
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
