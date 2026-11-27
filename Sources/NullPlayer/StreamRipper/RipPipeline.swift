import Foundation

/// A Stream Ripper job's work, on a background queue: yt-dlp downloads into local staging,
/// ffmpeg makes a video playable, and the result (with a .cue from the chapters) moves to the
/// chosen folder. It reports through the job's `RipJobHandle` and ends with `RipJobCenter.finish`.
extension StreamRipper {
    /// yt-dlp and ffmpeg, or nil when either is missing (`missingToolsMessage`).
    static func resolveRipTools() -> (ytdlp: String, ffmpeg: String)? {
        guard let ytdlp = resolveYtDlp(), let ffmpeg = resolveTool("ffmpeg") else { return nil }
        return (ytdlp, ffmpeg)
    }

    static let missingToolsMessage =
        "Ripping requires yt-dlp and ffmpeg. Install them with: brew install yt-dlp ffmpeg"

    /// Runs one rip on a background queue (download, convert, save), reporting through `handle`,
    /// and ends its job with `RipJobCenter.finish`.
    static func run(_ handle: RipJobHandle, mode: Mode, sourceURL: URL, folder: String) {
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
    private static func sourceAudioKbps(ytdlp: String, selector: String, url: URL, handle: RipJobHandle) -> Int? {
        guard let output = try? RipProcess.run(ytdlp, ["--quiet", "--no-warnings", "--no-playlist", "-f", selector,
                                                       "--print", "abr", url.absoluteString], handle: handle)
        else { return nil }
        let text = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(text).map { Int($0.rounded()) }
    }

    private static func performRip(
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
        /// Every file this rip has put in `folder`, so a cancel removes those and nothing else.
        var saved: [URL] = []
        /// A cancel: nothing is kept, so nothing is recovered to ~/Downloads.
        func cancelled() -> (String?, String?) {
            for file in saved { try? fm.removeItem(at: file) }
            try? fm.removeItem(at: stagingFolder)
            return (nil, nil)
        }

        // Embed source metadata (title/artist/album/date, etc.) into the file.
        var args: [String] = ["--no-playlist", "--embed-metadata"]
        let outputTemplate: String
        switch mode {
        case .audio(var format):
            if case .mp3(let requested) = format {
                let source = sourceAudioKbps(ytdlp: tools.ytdlp, selector: format.formatSelector, url: sourceURL, handle: handle)
                if handle.isCancelled { return cancelled() }
                if let source, source < requested {
                    log(ripID, "source audio is \(source)k, below the \(requested)k requested; capping to \(source)k")
                    format = .mp3(kbps: source)
                } else if source == nil {
                    log(ripID, "source audio bitrate unknown; encoding at \(requested)k")
                }
            }
            // Embed the thumbnail as cover art (converted to jpg for compatibility).
            args += ["-f", format.formatSelector, "-x"] + format.ytdlpArgs + ["--embed-thumbnail", "--convert-thumbnails", "jpg"]
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
            let chapters = chaptersFile.map { readChapters(from: $0) } ?? []
            switch commitRip(staged, toFolder: folder, chapters: chapters, stagingFolder: stagingFolder, saved: &saved) {
            case .success(let committed): outputPath = committed
            case .failure(let error): return handle.isCancelled ? cancelled() : fail(error.message)
            }
        } else {
            // yt-dlp succeeded but didn't report the exact path; move whatever landed in
            // staging so the file still reaches the destination.
            do {
                try moveAllContents(of: stagingFolder, toFolder: folder, saved: &saved)
            } catch {
                if handle.isCancelled { return cancelled() }
                return fail("The completed download could not be moved to the destination: " + error.localizedDescription)
            }
        }

        // A cancel during the copy wins: the rip keeps nothing at the destination. Past this check
        // the rip is done, and `RipJob.finish` keeps it done over a later cancel.
        if handle.isCancelled { return cancelled() }
        try? fm.removeItem(at: stagingFolder)
        return (outputPath, nil)
    }

    // MARK: - Staging → destination move

    /// Copy the finished file from local staging to a collision-free name in `folder` and, with at
    /// least two chapters, its `.cue` beside it under the same base name — the name every cue
    /// lookup uses (`CueSheet.siblingCue`, the tag editor, Add to Library). Both are committed in
    /// one transfer, so no other rip can take the cue's name between them (M93). Each file that
    /// arrives joins `saved`. Returns the audio file's path.
    static func commitRip(
        _ stagingPath: String, toFolder folder: String, chapters: [Chapter], stagingFolder: URL, saved: inout [URL]
    ) -> Result<String, TranscodeError> {
        let staged = URL(fileURLWithPath: stagingPath)
        let desired = URL(fileURLWithPath: folder).appendingPathComponent(staged.lastPathComponent)
        let writesCue = chapters.count >= 2
        return withTransferLock {
            let audio = URL(fileURLWithPath: availableFilePath(
                for: desired.path, reservingSiblingExtension: writesCue ? "cue" : nil))
            do {
                try commitStagedCopy(from: staged, to: audio)
            } catch {
                return .failure(TranscodeError(message: "Downloaded to a temporary folder but could not be moved to the destination: \(error.localizedDescription)"))
            }
            saved.append(audio)
            guard writesCue else { return .success(audio.path) }
            let cue = audio.deletingPathExtension().appendingPathExtension("cue")
            do {
                try commitStagedCopy(from: try stagedCueFile(for: audio, chapters: chapters, in: stagingFolder), to: cue)
            } catch {
                return .failure(TranscodeError(message: "The media file was saved to \(audio.path), but its .cue sheet could not be saved: " + error.localizedDescription))
            }
            saved.append(cue)
            return .success(audio.path)
        }
    }

    /// Best-effort move of every top-level item in the staging dir to `folder`.
    /// Used as a fallback when yt-dlp didn't report the exact output path. Each file that
    /// arrives joins `saved`.
    private static func moveAllContents(of stagingFolder: URL, toFolder folder: String, saved: inout [URL]) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: stagingFolder, includingPropertiesForKeys: nil)
        guard !items.isEmpty else {
            throw TranscodeError(message: "yt-dlp did not report an output path and the staging folder is empty")
        }
        for item in items {
            let desiredURL = URL(fileURLWithPath: folder)
                .appendingPathComponent(item.lastPathComponent)
            saved.append(try transferStagedFile(from: item, to: desiredURL))
        }
    }

    // MARK: - Cue sheet

    struct Chapter {
        let start: Double
        let title: String
    }

    /// Parse the chapter JSON array yt-dlp wrote (or an empty array if none).
    private static func readChapters(from path: String) -> [Chapter] {
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

    /// Write the CUE sheet for `audioURL`, the audio file's final destination, into local staging.
    private static func stagedCueFile(for audioURL: URL, chapters: [Chapter], in stagingFolder: URL) throws -> URL {
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

        let stagedCueURL = stagingFolder
            .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("cue")
        try (lines.joined(separator: "\n") + "\n")
            .write(to: stagedCueURL, atomically: true, encoding: .utf8)
        return stagedCueURL
    }

    /// Format seconds as a CUE MM:SS:FF timestamp (75 frames per second).
    private static func cueTimestamp(_ seconds: Double) -> String {
        let totalFrames = Int((seconds * 75).rounded())
        let frames = totalFrames % 75
        let totalSeconds = totalFrames / 75
        return String(format: "%02d:%02d:%02d", totalSeconds / 60, totalSeconds % 60, frames)
    }

    // MARK: - Video compatibility transcode

    private static let videoSourceSuffix = " [source]"

    struct TranscodeError: Error {
        let message: String
    }

    static func compatibleVideoOutputPath(forIntermediatePath inputPath: String) -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let folderURL = inputURL.deletingLastPathComponent()
        var baseName = inputURL.deletingPathExtension().lastPathComponent
        if baseName.hasSuffix(videoSourceSuffix) {
            baseName.removeLast(videoSourceSuffix.count)
        }

        let desired = folderURL.appendingPathComponent(baseName).appendingPathExtension("mp4").path
        return availableFilePath(for: desired, excluding: inputPath)
    }

    private static func transcodeVideoForPlayback(
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

        let source = probeSource(at: inputPath, ffmpeg: ffmpeg, handle: handle)
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

        // A real encode waits for the one hardware encoder; a copy is disk-bound and runs at once.
        if !copies {
            guard RipEncodeQueue.acquire(for: handle) else {
                try? fm.removeItem(at: stagingURL)
                return .failure(TranscodeError(message: "cancelled"))
            }
        }
        defer { if !copies { RipEncodeQueue.release() } }
        handle.report(.phase(.converting))

        log(ripID, "ffmpeg profile=\(profile) source=\(fileSizeDescription(inputPath)) \(sourceDescription)")
        let progress = FFmpegProgressReader(handle: handle, duration: source.duration)
        let encodeStart = Date()
        let result: RipProcess.Output
        do {
            result = try RipProcess.run(ffmpeg, args, handle: handle, onStdout: { progress.consume($0) })
        } catch {
            log(ripID, "ffmpeg failed to start: \(error.localizedDescription)")
            try? fm.removeItem(at: stagingURL)
            return .failure(TranscodeError(message: "ffmpeg could not start: \(error.localizedDescription)"))
        }
        log(ripID, "ffmpeg exited status=\(result.status) reason=\(result.terminationReason == .uncaughtSignal ? "signal" : "exit")"
            + " after \(elapsed(since: encodeStart)) output=\(fileSizeDescription(tempPath))")

        guard result.status == 0 else {
            try? fm.removeItem(at: stagingURL)
            log(ripID, "ffmpeg stderr: \(result.stderr.suffix(2000))")
            return .failure(TranscodeError(message: result.stderr.isEmpty
                ? "ffmpeg failed while creating a playback-compatible MP4."
                : "ffmpeg failed while creating a playback-compatible MP4:\n\(result.stderr)"))
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
    private static func probeSource(at path: String, ffmpeg: String, handle: RipJobHandle) -> SourceInfo {
        let ffprobe = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().appendingPathComponent("ffprobe").path
        guard let output = try? RipProcess.run(ffprobe, ["-v", "error", "-show_entries",
                                                         "format=bit_rate,duration:stream=codec_type,codec_name,height",
                                                         "-of", "json", path], handle: handle),
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

    private static func videoScaleFilter(maxHeight: Int?) -> String {
        if let maxHeight {
            return "scale=-2:trunc(min(\(maxHeight)\\,ih)/2)*2"
        }
        return "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    }
}
