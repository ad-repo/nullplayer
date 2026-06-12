import Foundation

/// Detects the helper binaries (yt-dlp, ffmpeg) required by the YouTube → Sonos feature.
///
/// Resolution order for each binary (first match wins):
///   1. Explicit env override — `NULLPLAYER_YTDLP_PATH` / `NULLPLAYER_FFMPEG_PATH`.
///   2. Bundled in the app — `Contents/MacOS`, then `Contents/Resources` (the DMG distribution).
///   3. A system install on `PATH` plus common Homebrew prefixes — lets developers and
///      direct-download users enable the feature with `brew install yt-dlp ffmpeg`.
///
/// In the sandboxed Mac App Store build none of these resolve (no bundled binaries, and the
/// sandbox blocks executing system binaries), so `isAvailable` is false and the feature stays
/// hidden — which is the intended MAS behavior.
enum HelperBinaries {

    /// URL to the yt-dlp binary, if available and executable.
    static var ytDlpURL: URL? {
        detectBinary(name: "yt-dlp", envVar: "NULLPLAYER_YTDLP_PATH")
    }

    /// URL to the ffmpeg binary, if available and executable.
    static var ffmpegURL: URL? {
        detectBinary(name: "ffmpeg", envVar: "NULLPLAYER_FFMPEG_PATH")
    }

    /// Whether both required binaries (yt-dlp and ffmpeg) are available.
    static var isAvailable: Bool {
        ytDlpURL != nil && ffmpegURL != nil
    }

    // MARK: - Private Helpers

    private static func detectBinary(name: String, envVar: String) -> URL? {
        let fm = FileManager.default
        func usable(_ path: String) -> URL? {
            fm.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }

        // 1. Explicit override
        if let override = ProcessInfo.processInfo.environment[envVar], let url = usable(override) {
            return url
        }

        // 2. Bundled in the app
        if let executableURL = Bundle.main.executableURL {
            let macosDir = executableURL.deletingLastPathComponent()
            if let url = usable(macosDir.appendingPathComponent(name).path) { return url }
            let resourcesDir = macosDir.deletingLastPathComponent().appendingPathComponent("Resources")
            if let url = usable(resourcesDir.appendingPathComponent(name).path) { return url }
        }

        // 3. System install (PATH + common Homebrew/system prefixes)
        for dir in systemSearchPaths() {
            if let url = usable((dir as NSString).appendingPathComponent(name)) { return url }
        }

        return nil
    }

    private static func systemSearchPaths() -> [String] {
        var paths: [String] = []
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: envPath.split(separator: ":").map(String.init))
        }
        paths.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"])
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
