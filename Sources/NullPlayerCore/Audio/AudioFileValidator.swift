import Foundation

/// Cross-platform file-type validation used by LocalFileDiscovery and lightweight URL checks.
public enum AudioFileValidator {
    /// Supported audio extensions.
    public static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "alac"]

    /// Supported video extensions.
    public static let supportedVideoExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "m4v", "wmv", "flv", "webm", "ts", "m2ts", "mpg", "mpeg"]

    /// Returns true if the URL extension maps to a supported video format.
    public static func isVideoFile(url: URL) -> Bool {
        supportedVideoExtensions.contains(url.pathExtension.lowercased())
    }

    /// Result of validating a batch of URLs.
    public struct ValidationResult: Sendable {
        public let validURLs: [URL]
        public let invalidFiles: [(url: URL, reason: String)]

        public var hasInvalidFiles: Bool { !invalidFiles.isEmpty }

        public init(validURLs: [URL], invalidFiles: [(url: URL, reason: String)]) {
            self.validURLs = validURLs
            self.invalidFiles = invalidFiles
        }
    }

    /// Quick validation for cross-platform callers: existence + extension only.
    public static func quickValidate(url: URL) -> String? {
        if url.scheme == "http" || url.scheme == "https" {
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return "File does not exist"
        }

        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) || supportedVideoExtensions.contains(ext) else {
            return "Unsupported format: .\(ext)"
        }

        return nil
    }

    public static func quickValidate(urls: [URL]) -> ValidationResult {
        var validURLs: [URL] = []
        var invalidFiles: [(url: URL, reason: String)] = []

        for url in urls {
            if let error = quickValidate(url: url) {
                invalidFiles.append((url: url, reason: error))
            } else {
                validURLs.append(url)
            }
        }

        return ValidationResult(validURLs: validURLs, invalidFiles: invalidFiles)
    }
}
