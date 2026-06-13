import Foundation

/// Represents streams resolved from a YouTube URL
struct ResolvedStreams {
    let title: String
    let videoURL: URL
    let audioURL: URL
    /// Backward-compatible alias for the headers needed by the local video URL.
    let httpHeaders: [String: String]
    let videoHeaders: [String: String]
    let audioHeaders: [String: String]
    let audioCodec: String?
    let audioExtension: String?
    let expiresAt: Date?
    /// Total media duration in seconds (from yt-dlp), used for the cast track's DIDL metadata.
    let duration: TimeInterval?
}

/// Errors that can occur during stream resolution
enum ResolverError: Error, LocalizedError {
    case ytDlpNotFound
    case invalidInput(String)
    case processFailed(exitCode: Int32, stderr: String)
    case missingVideoFormat
    case missingAudioFormat
    case invalidJSON(Error)
    case missingTitle
    case invalidURL(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .ytDlpNotFound:
            return "yt-dlp binary not found. YouTube streaming requires helper binaries."
        case .invalidInput(let msg):
            return "Invalid input: \(msg)"
        case .processFailed(let code, let stderr):
            return "yt-dlp failed (exit \(code)): \(stderr.prefix(200))"
        case .missingVideoFormat:
            return "No suitable video stream found (video codec + h264/mp4)"
        case .missingAudioFormat:
            return "No suitable audio stream found (audio codec only)"
        case .invalidJSON(let err):
            return "Failed to parse yt-dlp output: \(err.localizedDescription)"
        case .missingTitle:
            return "Video title not found in stream metadata"
        case .invalidURL(let msg):
            return "Invalid URL: \(msg)"
        case .timedOut:
            return "yt-dlp timed out while resolving the stream"
        }
    }
}

/// Static resolver for YouTube streams using yt-dlp
enum YouTubeStreamResolver {

    /// Parse yt-dlp JSON output and select the best video and audio formats
    /// - Parameter data: Raw JSON output from `yt-dlp -j <url>`
    /// - Returns: Resolved streams with video, audio, and metadata
    static func selectStreams(fromYtDlpJSON data: Data) throws -> ResolvedStreams {
        let decoder = JSONDecoder()
        let ytdlpOutput: YtDlpOutput
        do {
            ytdlpOutput = try decoder.decode(YtDlpOutput.self, from: data)
        } catch {
            throw ResolverError.invalidJSON(error)
        }

        // Extract title
        guard let title = ytdlpOutput.title, !title.isEmpty else {
            throw ResolverError.missingTitle
        }

        // Select best video format (vcodec != none, acodec == none)
        guard let videoFormat = selectBestVideoFormat(ytdlpOutput.formats) else {
            throw ResolverError.missingVideoFormat
        }

        // Select best audio format (acodec != none, vcodec == none)
        guard let audioFormat = selectBestAudioFormat(ytdlpOutput.formats) else {
            throw ResolverError.missingAudioFormat
        }

        guard let videoURL = URL(string: videoFormat.url) else {
            throw ResolverError.invalidURL(videoFormat.url)
        }

        guard let audioURL = URL(string: audioFormat.url) else {
            throw ResolverError.invalidURL(audioFormat.url)
        }

        // Merge HTTP headers per selected stream. yt-dlp can attach different
        // headers to video and audio URLs, so keep them separate.
        var videoHeaders: [String: String] = [:]
        var audioHeaders: [String: String] = [:]
        if let globalHeaders = ytdlpOutput.http_headers {
            videoHeaders.merge(globalHeaders) { _, new in new }
            audioHeaders.merge(globalHeaders) { _, new in new }
        }
        if let videoFormatHeaders = videoFormat.http_headers {
            merge(videoFormatHeaders, into: &videoHeaders)
        }
        if let audioFormatHeaders = audioFormat.http_headers {
            audioHeaders.merge(audioFormatHeaders) { _, new in new }
        }

        // Best-effort expiration from URL query parameter
        var expiresAt: Date? = nil
        if let expireParam = videoURL.queryParameter("expire"),
           let expireSeconds = TimeInterval(expireParam) {
            expiresAt = Date(timeIntervalSince1970: expireSeconds)
        }

        return ResolvedStreams(
            title: title,
            videoURL: videoURL,
            audioURL: audioURL,
            httpHeaders: videoHeaders,
            videoHeaders: videoHeaders,
            audioHeaders: audioHeaders,
            audioCodec: audioFormat.acodec,
            audioExtension: audioFormat.ext,
            expiresAt: expiresAt,
            duration: ytdlpOutput.duration
        )
    }

    /// Resolve a YouTube URL to audio/video streams
    /// - Parameter youtubeURL: The YouTube URL to resolve
    /// - Returns: Resolved streams
    static func resolve(_ youtubeURL: URL) async throws -> ResolvedStreams {
        guard let ytDlpURL = HelperBinaries.ytDlpURL else {
            throw ResolverError.ytDlpNotFound
        }

        let process = Process()
        process.executableURL = ytDlpURL
        process.arguments = [
            "-j",
            youtubeURL.absoluteString
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutData = try await runProcess(process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        return try selectStreams(fromYtDlpJSON: stdoutData)
    }

    private static func runProcess(_ process: Process, stdoutPipe: Pipe, stderrPipe: Pipe) async throws -> Data {
        let task = Task.detached(priority: .utility) { () throws -> Data in
            let stdoutTask = Task.detached(priority: .utility) {
                stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            }
            let stderrTask = Task.detached(priority: .utility) {
                stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw ResolverError.processFailed(exitCode: -1, stderr: error.localizedDescription)
            }

            let stdoutData = await stdoutTask.value
            let stderrData = await stderrTask.value
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw ResolverError.processFailed(exitCode: process.terminationStatus, stderr: stderrString)
            }
            return stdoutData
        }

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await task.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                if process.isRunning {
                    process.terminate()
                }
                throw ResolverError.timedOut
            }

            do {
                guard let result = try await group.next() else {
                    throw ResolverError.processFailed(exitCode: -1, stderr: "yt-dlp produced no result")
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                task.cancel()
                if process.isRunning {
                    process.terminate()
                }
                throw error
            }
        }
    }

    // MARK: - Format Selection

    private static func selectBestVideoFormat(_ formats: [Format]?) -> Format? {
        guard let formats = formats else { return nil }

        let videoFormats = formats.filter { format in
            // Video codec must exist, audio must be "none"
            (format.vcodec != nil && format.vcodec != "none") &&
                (format.acodec == nil || format.acodec == "none")
        }

        // Prefer mp4/h264 (the video window handles these reliably); else any video-only format.
        let h264Formats = videoFormats.filter { ($0.ext == "mp4" || $0.ext == "m4v") && $0.vcodec?.contains("h264") == true }
        let pool = h264Formats.isEmpty ? videoFormats : h264Formats

        // Cap at 1080p: the window is small/muted, so 4K just wastes decode. Pick the highest
        // resolution at or below 1080p; if every format is above 1080p, take the smallest.
        let within1080 = pool.filter { ($0.height ?? 0) <= 1080 }
        if let best = within1080.max(by: resolutionAscending) {
            return best
        }
        return pool.min(by: resolutionAscending)
    }

    private static func selectBestAudioFormat(_ formats: [Format]?) -> Format? {
        guard let formats = formats else { return nil }

        let audioFormats = formats.filter { format in
            // Audio codec must exist, video must be "none"
            (format.acodec != nil && format.acodec != "none") &&
                (format.vcodec == nil || format.vcodec == "none")
        }

        // Prefer the HIGHEST-bitrate AAC/m4a (yt-dlp lists formats worst-first, so picking the
        // first match would grab the lowest quality). Fall back to the highest-bitrate of any
        // audio-only codec (e.g. opus), which the coordinator transcodes to AAC for Sonos.
        let aacFormats = audioFormats.filter {
            $0.ext == "m4a" || ($0.acodec?.contains("aac") == true) || ($0.acodec?.contains("mp4a") == true)
        }
        if let best = aacFormats.max(by: bitrateAscending) {
            return best
        }
        return audioFormats.max(by: bitrateAscending) ?? audioFormats.first
    }

    private static func bitrateAscending(_ a: Format, _ b: Format) -> Bool {
        (a.abr ?? a.tbr ?? 0) < (b.abr ?? b.tbr ?? 0)
    }

    private static func resolutionAscending(_ a: Format, _ b: Format) -> Bool {
        let aRes = (a.height ?? 0) * (a.width ?? 0)
        let bRes = (b.height ?? 0) * (b.width ?? 0)
        return aRes < bRes
    }

    private static func merge(_ source: [String: String], into destination: inout [String: String]) {
        destination.merge(source) { _, new in new }
    }
}

// MARK: - yt-dlp JSON Models

private struct YtDlpOutput: Codable {
    let title: String?
    let formats: [Format]?
    let http_headers: [String: String]?
    let duration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case title
        case formats
        case http_headers
        case duration
    }
}

private struct Format: Codable {
    let url: String
    let ext: String?
    let vcodec: String?
    let acodec: String?
    let width: Int?
    let height: Int?
    /// Audio bitrate (kbps); total bitrate is the fallback for ranking audio quality.
    let abr: Double?
    let tbr: Double?
    let http_headers: [String: String]?

    enum CodingKeys: String, CodingKey {
        case url
        case ext
        case vcodec
        case acodec
        case width
        case height
        case abr
        case tbr
        case http_headers
    }
}

// MARK: - URL Helpers

private extension URL {
    func queryParameter(_ name: String) -> String? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }
}
