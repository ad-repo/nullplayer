import Foundation

/// Represents streams resolved from a YouTube URL
struct ResolvedStreams {
    let title: String
    let videoURL: URL
    let audioURL: URL
    let httpHeaders: [String: String]
    let expiresAt: Date?
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

        // Merge HTTP headers
        var allHeaders: [String: String] = [:]
        if let globalHeaders = ytdlpOutput.http_headers {
            allHeaders.merge(globalHeaders) { _, new in new }
        }
        if let videoHeaders = videoFormat.http_headers {
            allHeaders.merge(videoHeaders) { _, new in new }
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
            httpHeaders: allHeaders,
            expiresAt: expiresAt
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

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ResolverError.processFailed(exitCode: -1, stderr: error.localizedDescription)
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ResolverError.processFailed(exitCode: process.terminationStatus, stderr: stderrString)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return try selectStreams(fromYtDlpJSON: stdoutData)
    }

    // MARK: - Format Selection

    private static func selectBestVideoFormat(_ formats: [Format]?) -> Format? {
        guard let formats = formats else { return nil }

        let videoFormats = formats.filter { format in
            // Video codec must exist, audio must be "none"
            (format.vcodec != nil && format.vcodec != "none") &&
                (format.acodec == nil || format.acodec == "none")
        }

        // Prefer mp4 with h264
        if let best = videoFormats.first(where: { ($0.ext == "mp4" || $0.ext == "m4v") && $0.vcodec?.contains("h264") == true }) {
            return best
        }

        // Fallback: any video format with vcodec
        return videoFormats.max { a, b in
            let aRes = (a.height ?? 0) * (a.width ?? 0)
            let bRes = (b.height ?? 0) * (b.width ?? 0)
            return aRes > bRes
        }
    }

    private static func selectBestAudioFormat(_ formats: [Format]?) -> Format? {
        guard let formats = formats else { return nil }

        let audioFormats = formats.filter { format in
            // Audio codec must exist, video must be "none"
            (format.acodec != nil && format.acodec != "none") &&
                (format.vcodec == nil || format.vcodec == "none")
        }

        // Prefer m4a/aac
        if let best = audioFormats.first(where: { $0.ext == "m4a" || ($0.acodec?.contains("aac") == true) }) {
            return best
        }

        // Fallback: any audio format with acodec
        return audioFormats.first
    }
}

// MARK: - yt-dlp JSON Models

private struct YtDlpOutput: Codable {
    let title: String?
    let formats: [Format]?
    let http_headers: [String: String]?

    enum CodingKeys: String, CodingKey {
        case title
        case formats
        case http_headers
    }
}

private struct Format: Codable {
    let url: String
    let ext: String?
    let vcodec: String?
    let acodec: String?
    let width: Int?
    let height: Int?
    let http_headers: [String: String]?

    enum CodingKeys: String, CodingKey {
        case url
        case ext
        case vcodec
        case acodec
        case width
        case height
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
