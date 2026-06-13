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
    enum AudioFormat: String {
        case flac
        case mp3

        var displayName: String {
            switch self {
            case .flac: return "FLAC"
            case .mp3: return "MP3"
            }
        }
    }

    enum Mode {
        case audio(AudioFormat)
        /// Video with an optional max height cap (nil = best available, no cap).
        case video(maxHeight: Int?)

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
    /// x86, MacPorts, system).
    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]

    /// Resolves a tool executable path from the known system locations, or nil.
    static func resolveTool(_ name: String) -> String? {
        for dir in searchPaths {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Resolves the `yt-dlp` executable path, or nil if it is not installed.
    static func resolveYtDlp() -> String? { resolveTool("yt-dlp") }

    // MARK: - Entry point

    /// Format choices offered in the rip dialog, in display order.
    private static let formatChoices: [(title: String, mode: Mode)] = [
        ("Audio — FLAC (lossless)", .audio(.flac)),
        ("Audio — MP3", .audio(.mp3)),
        ("Video — 1080p (recommended)", .video(maxHeight: 1080)),
        ("Video — 720p (smaller)", .video(maxHeight: 720)),
        ("Video — 1440p", .video(maxHeight: 1440)),
        ("Video — 4K / best (largest)", .video(maxHeight: nil)),
    ]

    /// Prompt for a URL and output type, then a destination, then start the rip.
    func promptAndRip() {
        // Both tools are required: yt-dlp drives the download, ffmpeg does the
        // extraction / remux / metadata + thumbnail embedding.
        guard let ytdlp = Self.resolveYtDlp(), Self.resolveTool("ffmpeg") != nil else {
            presentMissingToolAlert()
            return
        }
        guard let (sourceURL, mode) = promptForInput() else { return }
        guard let folder = promptForDestinationFolder() else { return }
        rip(mode: mode, sourceURL: sourceURL, folder: folder, ytdlp: ytdlp)
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

    private func rip(mode: Mode, sourceURL: URL, folder: String, ytdlp: String) {
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
        case .video(let maxHeight):
            // Best video-only + best audio, merged, optionally capped at a max
            // height to avoid huge 4K/high-bitrate files. Prefer efficient codecs
            // (av1 > vp9 > h264) at a given resolution to shrink size further.
            // --remux-video only swaps the container (no quality-losing re-encode).
            let format: String
            if let h = maxHeight {
                format = "bv*[height<=\(h)]+ba/b[height<=\(h)]/bv*+ba"
            } else {
                format = "bv*+ba/b"
            }
            // Default vcodec ordering already prefers av1 > vp9 > h264 (more
            // efficient = smaller at the same resolution). vcodec is ranked
            // before br so an efficient codec wins over a fatter h264 stream.
            args += ["-f", format, "-S", "res,fps,vcodec,br,acodec", "--remux-video", "mp4"]
        }
        // Name the file from the source metadata: "Artist - Title" when an artist
        // is available, otherwise just the title.
        let outputTemplate = "\(folder)/%(artist|)s%(artist& - |)s%(title)s.%(ext)s"
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
            let status = task.terminationStatus
            let errText = String(data: errData, encoding: .utf8) ?? ""

            // The actual output path yt-dlp reported (nil if it couldn't be
            // resolved — we must not pretend the destination folder is the file).
            let reported = (try? String(contentsOfFile: pathFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(atPath: pathFile)
            let outputPath: String? = (reported?.isEmpty == false) ? reported : nil

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
            WindowManager.shared.playVideoTrack(track)
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
