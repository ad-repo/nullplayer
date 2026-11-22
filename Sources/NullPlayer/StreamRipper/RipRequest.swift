import Foundation

/// The video height cap a rip downloads at.
enum RipResolution: String, CaseIterable, Codable, Sendable {
    case p720, p1080, p1440, p2160, max

    var title: String {
        switch self {
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "1440p"
        case .p2160: "4K"
        case .max: "Max"
        }
    }

    var maxHeight: Int? {
        switch self {
        case .p720: 720
        case .p1080: 1080
        case .p1440: 1440
        case .p2160: 2160
        case .max: nil
        }
    }
}

/// What a video rip does after the download.
enum RipVideoFormat: String, CaseIterable, Codable, Sendable {
    /// The source's own streams copied into an MP4 when a 4K Chromecast plays them as they are;
    /// otherwise the HEVC encode.
    case original
    case hevc
    case h264

    var title: String {
        switch self {
        case .original: "Original (no re-encode)"
        case .hevc: "HEVC"
        case .h264: "H.264"
        }
    }

    /// Where the file plays, for the window's hint line.
    var hint: String {
        switch self {
        case .original: "Plays on 4K Chromecasts and in NullPlayer. Fastest, source quality."
        case .hevc: "Plays on 4K Chromecasts and Apple devices. Re-encoded."
        case .h264: "Plays everywhere. Re-encoded, largest file."
        }
    }
}

/// What an audio rip saves.
enum RipAudioFormat: String, CaseIterable, Codable, Sendable {
    /// The source's own Opus stream, without a re-encode. Raw value from when it was the only original.
    case originalOpus = "original"
    /// The source's own AAC stream (M4A), without a re-encode.
    case originalAAC
    case flac
    case mp3

    /// The bitrate choices for a lossy encode, in kbit/s; a rip never encodes above the source.
    static let bitrates = [320, 256, 192, 128]
    static let defaultKbps = 256

    var title: String {
        switch self {
        case .originalOpus: "Original (Opus)"
        case .originalAAC: "Original (AAC)"
        case .flac: "FLAC"
        case .mp3: "MP3"
        }
    }

    var hint: String {
        switch self {
        case .originalOpus: "YouTube's own Opus audio. Smallest, best quality."
        case .originalAAC: "YouTube's own AAC audio (M4A). Plays everywhere; YouTube's AAC is a little lower quality."
        case .flac: "Lossless copy of the decoded source. Large, no better than the source."
        case .mp3: "Re-encoded, never above the source's bitrate."
        }
    }

    var takesBitrate: Bool { self == .mp3 }

    /// A re-encoded AAC choice was retired for the AAC original, which is the same codec without
    /// a generation loss; a saved one reads as that, so the history still loads.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let format = RipAudioFormat(rawValue: raw == "aac" ? Self.originalAAC.rawValue : raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown audio format \(raw)"))
        }
        self = format
    }

    /// The YouTube source's format for this choice: it carries yt-dlp's per-codec quirks.
    private func youTubeFormat(kbps: Int) -> YouTubeAudioFormat {
        switch self {
        case .originalOpus: .originalOpus
        case .originalAAC: .originalAAC
        case .flac: .flac
        case .mp3: .mp3(kbps: kbps)
        }
    }

    /// yt-dlp's `-f` selector; the source bitrate probe uses the same one.
    var formatSelector: String { youTubeFormat(kbps: Self.defaultKbps).formatSelector }

    /// yt-dlp's selection and extraction arguments at `kbps`, already capped to the source.
    /// An original copies the stream when the site serves that codec, and converts it otherwise.
    func ytdlpArgs(kbps: Int) -> [String] {
        ["-f", formatSelector, "-x"] + youTubeFormat(kbps: kbps).ytdlpArgs
    }
}

extension StreamRipper {
    /// A video rip's resolution and format, and the encode settings that follow from them.
    struct VideoProfile: Codable, Sendable, Equatable, CustomStringConvertible {
        var resolution: RipResolution
        var format: RipVideoFormat

        var maxHeight: Int? { resolution.maxHeight }

        var description: String { "video \(resolution.title) \(format.rawValue)" }

        /// Target video rate in kbit/s, before `cappedRates(sourceKbps:)`. Original carries the
        /// HEVC rates, used when its source has to be encoded after all.
        var videoKbps: Int {
            switch (format, resolution) {
            case (.h264, .p720): 2500
            case (.h264, .p1080): 4000
            case (.h264, .p1440): 16000
            case (.h264, .p2160): 35000
            case (.h264, .max): 50000
            case (_, .p720): 2000
            case (_, .p1080): 6000
            case (_, .p1440): 12000
            case (_, .p2160): 20000
            case (_, .max): 30000
            }
        }

        var maxVideoKbps: Int { videoKbps * 5 / 4 }
        var videoBufferKbps: Int { videoKbps * 2 }

        var audioBitrate: String {
            switch resolution {
            case .p720: "128k"
            case .p1080: "160k"
            case .p1440, .p2160: "192k"
            case .max: "256k"
            }
        }

        /// The profile's rates, scaled down together so the target never exceeds the source's
        /// bitrate: re-encoding above it only makes a bigger file, never a better one.
        func cappedRates(sourceKbps: Int?) -> (target: Int, max: Int, buffer: Int) {
            let scale = min(1, Double(sourceKbps ?? .max) / Double(videoKbps))
            return (Int(Double(videoKbps) * scale), Int(Double(maxVideoKbps) * scale), Int(Double(videoBufferKbps) * scale))
        }

        /// The ffmpeg video encoder arguments. HEVC needs the `hvc1` tag for AVPlayer to play it.
        var videoCodecArgs: [String] {
            switch format {
            case .original, .hevc: ["-c:v", "hevc_videotoolbox", "-profile:v", "main", "-tag:v", "hvc1"]
            case .h264: ["-c:v", "libx264", "-preset", "medium", "-profile:v", "high"]
            }
        }

        /// The yt-dlp format selector: the best streams within the height cap. Original asks for
        /// VP9 + AAC first, the pair a 4K Chromecast plays straight from an MP4.
        var ytdlpFormat: String {
            let cap = maxHeight.map { "[height<=\($0)]" } ?? ""
            let capped = maxHeight == nil ? "bv*+ba/best" : "bv*\(cap)+ba/b\(cap)/best\(cap)"
            guard format == .original else { return capped }
            return "bv*\(cap)[vcodec^=vp09]+ba[acodec^=mp4a]/bv*\(cap)[vcodec^=vp09]+ba/" + capped
        }

        /// Whether a source in `codec` at `height` is copied rather than encoded: VP9 and HEVC
        /// are hardware-decoded at 4K on a 4K Chromecast; H.264 only to 1080p.
        func copiesSource(codec: String?, height: Int?) -> Bool {
            guard format == .original, let codec else { return false }
            return codec == "vp9" || codec == "hevc" || (codec == "h264" && (height ?? .max) <= 1080)
        }
    }
}
