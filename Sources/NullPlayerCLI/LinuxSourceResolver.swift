import Foundation
import NullPlayerCore

enum LinuxSourceResolverError: LocalizedError {
    case emptyInput
    case unsupportedInput(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "No input paths or URLs were provided."
        case let .unsupportedInput(value):
            return "Unsupported input '\(value)'. Use a local file path or an http/https URL."
        case let .fileNotFound(path):
            return "File not found: \(path)"
        }
    }
}

enum LinuxSourceResolver {
    static func resolveTracks(from arguments: [String]) throws -> [Track] {
        guard !arguments.isEmpty else {
            throw LinuxSourceResolverError.emptyInput
        }

        return try arguments.map { Track(url: try resolveURL(from: $0)) }
    }

    static func resolveURL(from rawInput: String) throws -> URL {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LinuxSourceResolverError.unsupportedInput(rawInput)
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        let expandedPath = (trimmed as NSString).expandingTildeInPath
        let fileURL: URL
        if expandedPath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: expandedPath)
        } else {
            fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expandedPath)
        }

        let standardized = fileURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            throw LinuxSourceResolverError.fileNotFound(standardized.path)
        }

        return standardized
    }
}
