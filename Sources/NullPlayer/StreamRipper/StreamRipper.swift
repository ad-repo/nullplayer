import Foundation
import AppKit

/// Rips a media URL to a local file using `yt-dlp` (with `ffmpeg` for audio
/// extraction / container merging). Audio mode extracts audio only; video mode
/// downloads the full video to a file.
///
/// This is intentionally self-contained: it shells out to a system-installed
/// `yt-dlp` rather than bundling helper binaries. If the tool is missing the
/// user is told how to install it.
@MainActor
final class StreamRipper {
    static let shared = StreamRipper()
    private init() {}

    /// Audio output formats. Both require a transcode from YouTube's native
    /// (lossy) source: FLAC losslessly wraps the decoded audio; MP3 re-encodes.
    enum AudioFormat: String, Sendable {
        case flac
        case mp3

        var displayName: String {
            switch self {
            case .flac: return "FLAC"
            case .mp3: return "MP3"
            }
        }
    }

    enum VideoProfile: Sendable, Equatable {
        case p720
        case p1080
        case p1080High
        case p1440
        case p4k
        case full

        var maxHeight: Int? {
            switch self {
            case .p720: return 720
            case .p1080, .p1080High: return 1080
            case .p1440: return 1440
            case .p4k: return 2160
            case .full: return nil
            }
        }

        var videoBitrate: String {
            switch self {
            case .p720: return "2500k"
            case .p1080: return "4M"
            case .p1080High: return "8M"
            case .p1440: return "16M"
            case .p4k: return "35M"
            case .full: return "50M"
            }
        }

        var maxVideoBitrate: String {
            switch self {
            case .p720: return "3M"
            case .p1080: return "5M"
            case .p1080High: return "10M"
            case .p1440: return "20M"
            case .p4k: return "45M"
            case .full: return "65M"
            }
        }

        var videoBufferSize: String {
            switch self {
            case .p720: return "5M"
            case .p1080: return "8M"
            case .p1080High: return "16M"
            case .p1440: return "32M"
            case .p4k: return "70M"
            case .full: return "100M"
            }
        }

        var audioBitrate: String {
            switch self {
            case .p720: return "128k"
            case .p1080: return "160k"
            case .p1080High, .p1440, .p4k: return "192k"
            case .full: return "256k"
            }
        }
    }

    enum Mode: Sendable {
        case audio(AudioFormat)
        /// Video transcodes to a playback-safe MP4 profile after download.
        case video(VideoProfile)

        /// Requested file extension (logging / diagnostics only — the real
        /// extension is decided by yt-dlp and read back after the rip).
        var fileExtension: String {
            switch self {
            case .audio(let format): return format.rawValue
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
    ///   - formatArgs: yt-dlp audio format arguments (e.g., `["--audio-format","flac","--audio-quality","0"]`)
    ///   - outputTemplate: yt-dlp output filename template (e.g., `"/path/to/downloads/%(id)s.%(ext)s"`)
    /// - Returns: A file:// URL to the downloaded audio file
    /// - Throws: If yt-dlp is not found, the download fails, or the output path cannot be resolved
    nonisolated static func downloadAudio(
        from sourceURL: URL,
        formatArgs: [String],
        outputTemplate: String
    ) async throws -> URL {
        guard let ytdlp = Self.resolveTool("yt-dlp") else {
            throw DownloadAudioError.toolNotFound("yt-dlp is not installed. Install via Homebrew: brew install yt-dlp")
        }

        let pathFile = NSTemporaryDirectory() + "nullplayer-yt-audio-\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: pathFile) }
        let errorFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-yt-audio-error-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)
        guard let errorHandle = try? FileHandle(forWritingTo: errorFile) else {
            throw DownloadAudioError.processStartFailed("Could not create temporary error output")
        }
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorFile)
        }

        var args = ["-f", "bestaudio/best", "-x"]
        args += formatArgs
        args += [
            "--no-playlist",
            "--embed-metadata",
            "--print-to-file", "after_move:filepath", pathFile,
            "-o", outputTemplate,
            sourceURL.absoluteString
        ]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (Self.searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ytdlp)
        task.arguments = args
        task.environment = env
        task.standardError = errorHandle
        task.standardOutput = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            throw DownloadAudioError.processStartFailed(error.localizedDescription)
        }

        task.waitUntilExit()
        try? errorHandle.close()
        let status = task.terminationStatus

        let reported = (try? String(contentsOfFile: pathFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outputPath = (reported?.isEmpty == false) ? reported : nil

        if status != 0 || outputPath == nil {
            let stderr = (try? String(contentsOf: errorFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = outputPath == nil
                ? "yt-dlp did not report output path"
                : "yt-dlp exited with code \(status)"
            let errMsg = stderr.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            throw DownloadAudioError.downloadFailed(errMsg)
        }

        guard let finalPath = outputPath else {
            throw DownloadAudioError.downloadFailed("Output path is empty")
        }

        return URL(fileURLWithPath: finalPath)
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

    // MARK: - Entry point

    /// Format choices offered in the rip dialog, in display order.
    private static let formatChoices: [(title: String, mode: Mode)] = [
        ("Audio — FLAC (lossless)", .audio(.flac)),
        ("Audio — MP3", .audio(.mp3)),
        ("Video — 1080p / 4 Mbps (recommended)", .video(.p1080)),
        ("Video — 720p / 2.5 Mbps (smaller)", .video(.p720)),
        ("Video — 1080p / 8 Mbps (high quality)", .video(.p1080High)),
        ("Video — 1440p / 16 Mbps", .video(.p1440)),
        ("Video — 4K / 35 Mbps (largest)", .video(.p4k)),
        ("Video — Full / 50 Mbps (max)", .video(.full)),
    ]

    /// Prompt for a URL and output type, then a destination, then start the rip.
    func promptAndRip() {
        // Both tools are required: yt-dlp drives the download, ffmpeg handles
        // extraction, video compatibility encoding, metadata, and thumbnails.
        guard let ytdlp = Self.resolveYtDlp(), let ffmpeg = Self.resolveTool("ffmpeg") else {
            presentMissingToolAlert()
            return
        }
        guard let (sourceURL, mode) = promptForInput() else { return }
        guard let folder = promptForDestinationFolder() else { return }
        rip(mode: mode, sourceURL: sourceURL, folder: folder, ytdlp: ytdlp, ffmpeg: ffmpeg)
    }

    // MARK: - URL entry window

    private func promptForInput() -> (URL, Mode)? {
        let alert = NSAlert()
        alert.messageText = "Rip URL"
        alert.informativeText = "Enter a URL and choose the output type."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let width: CGFloat = 460
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 96))

        let urlLabel = NSTextField(labelWithString: "URL")
        urlLabel.font = .systemFont(ofSize: 11)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.frame = NSRect(x: 0, y: 76, width: width, height: 16)
        container.addSubview(urlLabel)

        let textField = NSTextField(frame: NSRect(x: 0, y: 50, width: width, height: 24))
        textField.placeholderString = "https://…"
        textField.lineBreakMode = .byTruncatingHead
        // Pre-fill from the clipboard when it holds a web URL.
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            let trimmed = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = URL(string: trimmed), parsed.scheme == "http" || parsed.scheme == "https" {
                textField.stringValue = trimmed
            }
        }
        container.addSubview(textField)

        let formatLabel = NSTextField(labelWithString: "Output")
        formatLabel.font = .systemFont(ofSize: 11)
        formatLabel.textColor = .secondaryLabelColor
        formatLabel.frame = NSRect(x: 0, y: 28, width: width, height: 16)
        container.addSubview(formatLabel)

        let formatPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        formatPopup.addItems(withTitles: Self.formatChoices.map(\.title))
        formatPopup.selectItem(at: 0)
        container.addSubview(formatPopup)

        alert.accessoryView = container
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let urlString = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else {
            presentInvalidURLAlert()
            return nil
        }

        let mode = Self.formatChoices[formatPopup.indexOfSelectedItem].mode
        return (url, mode)
    }

    // MARK: - Destination

    /// Returns the chosen destination folder (the filename is derived from the
    /// source's metadata title), or nil if cancelled.
    private func promptForDestinationFolder() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose Destination Folder"
        panel.prompt = "Save Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    // MARK: - Rip

    private func rip(mode: Mode, sourceURL: URL, folder: String, ytdlp: String, ffmpeg: String) {
        // yt-dlp writes the final on-disk path here so we can reveal the real
        // file (the extension depends on the native source codec/container).
        let pathFile = NSTemporaryDirectory() + "nullplayer-rip-\(UUID().uuidString).txt"

        // Embed source metadata (title/artist/album/date, etc.) into the file.
        var args: [String] = ["--no-playlist", "--embed-metadata"]

        // For audio rips, capture the source's chapter list so we can write a
        // .cue sheet when the video has timestamps (e.g. album/mix uploads).
        var chaptersFile: String?
        switch mode {
        case .audio(let format):
            // Grab the best audio-only source, then transcode to the requested
            // format. --audio-quality 0 = best (lossless for FLAC, top VBR for MP3).
            // Embed the thumbnail as cover art (converted to jpg for compatibility).
            args += ["-f", "bestaudio/best", "-x", "--audio-format", format.rawValue, "--audio-quality", "0",
                     "--embed-thumbnail", "--convert-thumbnails", "jpg"]
            let cf = NSTemporaryDirectory() + "nullplayer-chapters-\(UUID().uuidString).json"
            chaptersFile = cf
            args += ["--print-to-file", "after_move:%(chapters)j", cf]
        case .video(let profile):
            // Download the best source streams at the selected height cap, then
            // normalize with ffmpeg to a predictable H.264/AAC MP4 profile.
            let format: String
            if let h = profile.maxHeight {
                format = "bv*[height<=\(h)]+ba/b[height<=\(h)]/best[height<=\(h)]"
            } else {
                format = "bv*+ba/best"
            }
            args += ["-f", format, "-S", "res,fps,br", "--merge-output-format", "mkv"]
        }
        // Name the file from the source metadata: "Artist - Title" when an artist
        // is available, otherwise just the title.
        let outputTemplate: String
        switch mode {
        case .video:
            outputTemplate = "\(folder)/%(artist|)s%(artist& - |)s%(title)s [source].%(ext)s"
        case .audio:
            outputTemplate = "\(folder)/%(artist|)s%(artist& - |)s%(title)s.%(ext)s"
        }
        args += [
            "--print-to-file", "after_move:filepath", pathFile,
            "-o", outputTemplate,
            sourceURL.absoluteString,
        ]

        // Ensure yt-dlp can find ffmpeg even when launched without a login PATH.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (Self.searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")

        // Log only the host + format — avoid leaking full URLs (query tokens)
        // or local destination paths into the system log.
        NSLog("StreamRipper: ripping from %@ (%@)", sourceURL.host ?? "?", mode.fileExtension)

        // Show a spinner + message on the main window for the duration of the rip.
        WindowManager.shared.mainWindowController?.showActivity("Ripping… \(sourceURL.host ?? "downloading")")

        let errPipe = Pipe()

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: ytdlp)
            task.arguments = args
            task.environment = env
            task.standardError = errPipe
            // Discard stdout: yt-dlp streams progress here and we don't read it.
            // An unread Pipe() fills its ~64KB OS buffer mid-download and blocks
            // the process forever (stalls at the same spot every time).
            task.standardOutput = FileHandle.nullDevice

            do {
                try task.run()
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.endActivity()
                    self.presentFailure(message: message)
                }
                return
            }

            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            var status = task.terminationStatus
            var errText = String(data: errData, encoding: .utf8) ?? ""

            // The actual output path yt-dlp reported (nil if it couldn't be
            // resolved — we must not pretend the destination folder is the file).
            let reported = (try? String(contentsOfFile: pathFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(atPath: pathFile)
            var outputPath: String? = (reported?.isEmpty == false) ? reported : nil

            if status == 0, case .video(let profile) = mode, let sourcePath = outputPath {
                switch Self.transcodeVideoForPlayback(inputPath: sourcePath, profile: profile, ffmpeg: ffmpeg) {
                case .success(let compatiblePath):
                    outputPath = compatiblePath
                case .failure(let error):
                    status = 1
                    errText = error.message
                }
            }

            // Write a .cue sheet if the source had chapter timestamps.
            var cueTrackCount = 0
            if status == 0, let path = outputPath, let cf = chaptersFile {
                let chapters = Self.readChapters(from: cf)
                if chapters.count >= 2 {
                    Self.writeCueFile(audioPath: path, chapters: chapters)
                    cueTrackCount = chapters.count
                }
            }
            if let cf = chaptersFile { try? FileManager.default.removeItem(atPath: cf) }

            DispatchQueue.main.async {
                self.endActivity()
                if status == 0 {
                    self.presentSuccess(outputPath: outputPath, folder: folder, mode: mode, cueTrackCount: cueTrackCount)
                } else {
                    self.presentFailure(message: errText.isEmpty ? "yt-dlp exited with code \(status)." : errText)
                }
            }
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

    /// Write a CUE sheet next to the audio file, one TRACK per chapter.
    private nonisolated static func writeCueFile(audioPath: String, chapters: [Chapter]) {
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

        let cueURL = audioURL.deletingPathExtension().appendingPathExtension("cue")
        try? (lines.joined(separator: "\n") + "\n").write(to: cueURL, atomically: true, encoding: .utf8)
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
        ffmpeg: String
    ) -> Result<String, TranscodeError> {
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

        let args = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", inputPath,
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-map_metadata", "0",
            "-vf", videoScaleFilter(maxHeight: profile.maxHeight),
            "-c:v", "libx264",
            "-preset", "medium",
            "-profile:v", "high",
            "-pix_fmt", "yuv420p",
            "-b:v", profile.videoBitrate,
            "-maxrate", profile.maxVideoBitrate,
            "-bufsize", profile.videoBufferSize,
            "-c:a", "aac",
            "-b:a", profile.audioBitrate,
            "-movflags", "+faststart",
            tempPath,
        ]

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice

        let errPipe = Pipe()
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            try? fm.removeItem(at: stagingURL)
            return .failure(TranscodeError(message: "ffmpeg could not start: \(error.localizedDescription)"))
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            try? fm.removeItem(at: stagingURL)
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private nonisolated static func videoScaleFilter(maxHeight: Int?) -> String {
        if let maxHeight {
            return "scale=-2:trunc(min(\(maxHeight)\\,ih)/2)*2"
        }
        return "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    }

    private func endActivity() {
        WindowManager.shared.mainWindowController?.hideActivity()
    }

    // MARK: - Alerts

    private func presentMissingToolAlert() {
        let alert = NSAlert()
        alert.messageText = "yt-dlp Not Found"
        alert.informativeText = "Ripping requires yt-dlp (and ffmpeg). Install them, e.g.:\n\nbrew install yt-dlp ffmpeg"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentInvalidURLAlert() {
        let alert = NSAlert()
        alert.messageText = "Invalid URL"
        alert.informativeText = "Please enter a valid http(s) URL."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentSuccess(outputPath: String?, folder: String, mode: Mode, cueTrackCount: Int) {
        let alert = NSAlert()
        alert.messageText = "Rip Complete"
        alert.alertStyle = .informational

        guard let outputPath else {
            // yt-dlp succeeded but we couldn't resolve the exact file path, so we
            // can't offer Play Now / reveal-the-file — point at the folder instead.
            alert.informativeText = "Saved to \(folder)\n\nThe exact file couldn't be located automatically."
            alert.addButton(withTitle: "Reveal in Finder")
            alert.addButton(withTitle: "Done")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
            }
            return
        }

        var info = (outputPath as NSString).lastPathComponent
        if cueTrackCount > 0 {
            info += "\n\nWrote a \(cueTrackCount)-track .cue sheet from the chapter timestamps."
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Play Now")
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Done")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            playFile(at: outputPath, mode: mode)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
        default:
            break
        }
    }

    /// Play the ripped file: video opens in the video player window, audio loads
    /// into the player (same path as opening a file from Finder).
    private func playFile(at path: String, mode: Mode) {
        let url = URL(fileURLWithPath: path)
        switch mode {
        case .video:
            let track = Track(url: url)
            WindowManager.shared.showVideoPlayer(url: url, title: track.displayTitle, allowCasting: false)
        case .audio:
            let engine = WindowManager.shared.audioEngine
            engine.loadFiles([url])
            engine.play()
        }
    }

    private func presentFailure(message: String) {
        let alert = NSAlert()
        alert.messageText = "Rip Failed"
        // yt-dlp errors can be long; keep the tail which usually has the cause.
        alert.informativeText = String(message.suffix(600))
        alert.alertStyle = .warning
        alert.runModal()
    }
}
