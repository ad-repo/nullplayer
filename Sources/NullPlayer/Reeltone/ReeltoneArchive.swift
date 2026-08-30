import Foundation
import ZIPFoundation

struct ReeltoneArchiveLimits: Equatable, Sendable {
    static let published = ReeltoneArchiveLimits(
        maximumEntryCount: 1_024,
        maximumUncompressedBytes: 64 * 1_024 * 1_024,
        maximumCompressionRatio: 1_000
    )

    let maximumEntryCount: Int
    let maximumUncompressedBytes: UInt64
    let maximumCompressionRatio: Double
}

enum ReeltoneResourcePath {
    static func validate(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !(path.count >= 2 && path[path.index(after: path.startIndex)] == ":" && path.first?.isLetter == true),
              !path.contains("\\"),
              !path.contains("\0") else {
            throw diagnostic(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw diagnostic(path)
        }
    }

    static func logicalPath(_ path: String, isDirectory: Bool = false) throws -> String {
        var candidate = path
        if isDirectory, candidate.hasSuffix("/") { candidate.removeLast() }
        try validate(candidate)
        return candidate.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func resolved(_ path: String, beneath root: URL) throws -> URL {
        try validate(path)
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let result = canonicalRoot.appendingPathComponent(path, isDirectory: false).standardizedFileURL
        let prefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard result.path.hasPrefix(prefix) else { throw diagnostic(path) }
        return result
    }

    private static func diagnostic(_ path: String) -> ReeltoneDiagnostic {
        ReeltoneDiagnostic(
            code: .invalidResourcePath,
            message: "Resource path must be a relative path contained by the skin",
            resourcePath: path
        )
    }
}

struct ReeltoneArchiveInspector {
    let limits: ReeltoneArchiveLimits

    init(limits: ReeltoneArchiveLimits = .published) {
        self.limits = limits
    }

    func extractArchive(at archiveURL: URL, to destinationRoot: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw ReeltoneDiagnostic(code: .unreadableArchive, message: "The Reeltone archive cannot be read")
        }

        let entries = Array(archive)
        guard entries.count <= limits.maximumEntryCount else {
            throw ReeltoneDiagnostic(code: .entryCountLimit, message: "Archive contains more than \(limits.maximumEntryCount) entries")
        }

        var totalUncompressed: UInt64 = 0
        var logicalPaths = Set<String>()
        var filePaths = Set<String>()
        var hasRootManifest = false

        for entry in entries {
            guard entry.type != .symlink else {
                throw ReeltoneDiagnostic(code: .symbolicLink, message: "Symbolic links are not allowed", resourcePath: entry.path)
            }
            let logical: String
            do {
                logical = try ReeltoneResourcePath.logicalPath(entry.path, isDirectory: entry.type == .directory)
            } catch {
                throw ReeltoneDiagnostic(code: .invalidArchivePath, message: "Archive contains an unsafe path", resourcePath: entry.path)
            }
            guard logicalPaths.insert(logical).inserted else {
                throw ReeltoneDiagnostic(code: .duplicatePath, message: "Archive contains duplicate logical paths", resourcePath: entry.path)
            }
            if entry.type == .file { filePaths.insert(logical) }
            if logical == "skin.json", entry.type == .file { hasRootManifest = true }

            let (sum, overflow) = totalUncompressed.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, sum <= limits.maximumUncompressedBytes else {
                throw ReeltoneDiagnostic(code: .uncompressedSizeLimit, message: "Archive exceeds the 64 MiB uncompressed limit")
            }
            totalUncompressed = sum

            if entry.type == .file, entry.uncompressedSize > 0 {
                guard entry.compressedSize > 0 else {
                    throw ReeltoneDiagnostic(code: .compressionRatioLimit, message: "Archive entry has an invalid compression ratio", resourcePath: entry.path)
                }
                let ratio = Double(entry.uncompressedSize) / Double(entry.compressedSize)
                guard ratio <= limits.maximumCompressionRatio else {
                    throw ReeltoneDiagnostic(code: .compressionRatioLimit, message: "Archive entry exceeds the compression-ratio limit", resourcePath: entry.path)
                }
            }
        }

        guard hasRootManifest else {
            throw ReeltoneDiagnostic(code: .unexpectedRootLayout, message: "skin.json must be a file at the archive root")
        }
        for file in filePaths {
            var components = file.split(separator: "/").map(String.init)
            while components.count > 1 {
                components.removeLast()
                if filePaths.contains(components.joined(separator: "/")) {
                    throw ReeltoneDiagnostic(code: .unexpectedRootLayout, message: "A file is also used as a parent directory", resourcePath: file)
                }
            }
        }

        do {
            try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            for entry in entries {
                let path = entry.type == .directory && entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                let destination = try ReeltoneResourcePath.resolved(path, beneath: destinationRoot)
                _ = try archive.extract(entry, to: destination)
            }
        } catch let diagnostic as ReeltoneDiagnostic {
            throw diagnostic
        } catch {
            throw ReeltoneDiagnostic(code: .unreadableArchive, message: "Archive extraction failed: \(error.localizedDescription)")
        }
    }
}
