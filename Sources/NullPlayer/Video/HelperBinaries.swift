import Foundation

/// Detects and manages presence of required helper binaries (yt-dlp, ffmpeg)
enum HelperBinaries {

    /// URL to the bundled yt-dlp binary, if available and executable
    static var ytDlpURL: URL? {
        detectBinary(names: ["yt-dlp"])
    }

    /// URL to the bundled ffmpeg binary, if available and executable
    static var ffmpegURL: URL? {
        detectBinary(names: ["ffmpeg"])
    }

    /// Whether both required binaries (yt-dlp and ffmpeg) are available
    static var isAvailable: Bool {
        ytDlpURL != nil && ffmpegURL != nil
    }

    // MARK: - Private Helpers

    /// Detect a binary by checking standard locations
    /// Tries: Contents/MacOS, Contents/Resources
    private static func detectBinary(names: [String]) -> URL? {
        guard let executableURL = Bundle.main.executableURL else {
            return nil
        }

        let macosDir = executableURL.deletingLastPathComponent()
        let resourcesDir = macosDir.deletingLastPathComponent().appendingPathComponent("Resources")

        for name in names {
            // Try Contents/MacOS first
            let macosPath = macosDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: macosPath.path),
               FileManager.default.isExecutableFile(atPath: macosPath.path) {
                return macosPath
            }

            // Try Contents/Resources
            let resourcesPath = resourcesDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: resourcesPath.path),
               FileManager.default.isExecutableFile(atPath: resourcesPath.path) {
                return resourcesPath
            }
        }

        return nil
    }
}
