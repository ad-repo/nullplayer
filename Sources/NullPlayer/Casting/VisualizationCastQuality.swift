import Foundation

/// The user's picture settings for a visualization cast, read by every part of it.
struct VisualizationCastQuality: Equatable {
    enum Resolution: String, CaseIterable {
        case hd = "720p", fullHD = "1080p", uhd = "4K"

        var width: Int {
            switch self {
            case .hd: return 1280
            case .fullHD: return 1920
            case .uhd: return 3840
            }
        }

        var height: Int {
            switch self {
            case .hd: return 720
            case .fullHD: return 1080
            case .uhd: return 2160
            }
        }

        /// Saturated colours block up first: H.264 keeps chroma at quarter resolution, and 8 Mbps at
        /// 1080p starved it. 60 fps gets no more: Goom at 1080p60 held 16–20 Mbps against an 18 Mbps
        /// target and a Chromecast buffered for 1:45 (measured).
        var videoBitRate: Int {
            switch self {
            case .hd: return 6_000_000
            case .fullHD: return 12_000_000
            case .uhd: return 25_000_000
            }
        }
    }

    static let frameRates = [30, 60]
    private static let resolutionKey = "visualizationCast.resolution"
    private static let frameRateKey = "visualizationCast.frameRate"

    var resolution: Resolution
    var frameRate: Int

    var width: Int { resolution.width }
    var height: Int { resolution.height }
    var videoBitRate: Int { resolution.videoBitRate }

    /// 4K casts at 30 fps: at 60 a Samsung QN90B played it with crackling sound, at 30 cleanly
    /// (H.264 4K tops out at 30 on TVs; a Chromecast Ultra rejects 4K H.264 outright).
    static func frameRateAllowed(_ rate: Int, at resolution: Resolution) -> Bool {
        resolution != .uhd || rate == 30
    }

    static var saved: VisualizationCastQuality {
        let defaults = UserDefaults.standard
        let resolution = defaults.string(forKey: resolutionKey).flatMap(Resolution.init) ?? .fullHD
        let rate = defaults.integer(forKey: frameRateKey)
        return VisualizationCastQuality(
            resolution: resolution,
            frameRate: frameRates.contains(rate) && frameRateAllowed(rate, at: resolution) ? rate : 30)
    }

    func save() {
        UserDefaults.standard.set(resolution.rawValue, forKey: Self.resolutionKey)
        UserDefaults.standard.set(frameRate, forKey: Self.frameRateKey)
    }
}
