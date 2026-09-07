import Foundation

/// Read-only `WalResourceProvider` over an already-extracted directory tree (e.g. a ClassicPro
/// `engine/` folder the user extracted themselves). Enforces the same bounded-VFS limits as
/// `WalArchive`: entry count, per-entry and total uncompressed bytes, symlink rejection, and
/// case-insensitive collision detection. Files are read from disk on demand.
final class WalDirectoryResourceProvider: WalResourceProvider {
    let rootURL: URL
    let limits: WalArchiveLimits

    private let fileURLsByFoldedPath: [String: URL]
    private let canonicalPathsByFoldedPath: [String: String]
    private let sizesByFoldedPath: [String: UInt64]

    init(rootURL: URL, limits: WalArchiveLimits = .production, fileManager: FileManager = .default) throws {
        let standardizedRoot = rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Engine directory '\(rootURL.lastPathComponent)' does not exist."))
        }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: nil
        ) else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Unable to enumerate engine directory '\(rootURL.lastPathComponent)'."))
        }

        let rootComponents = standardizedRoot.pathComponents
        var byFolded: [String: URL] = [:]
        var canonical: [String: String] = [:]
        var sizes: [String: UInt64] = [:]
        var declaredTotal: UInt64 = 0
        var entryCount = 0

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(resourceKeys))
            if values.isSymbolicLink == true {
                throw WalFailure(WalDiagnostic(.symbolicLink, "Symbolic link '\(url.lastPathComponent)' is not allowed in an engine directory."))
            }
            guard values.isRegularFile == true else { continue }

            entryCount += 1
            guard entryCount <= limits.maximumEntryCount else {
                throw WalFailure(WalDiagnostic(.entryLimitExceeded, "Engine directory contains more than \(limits.maximumEntryCount) files."))
            }

            let size = UInt64(values.fileSize ?? 0)
            guard size <= limits.maximumEntrySize else {
                throw WalFailure(WalDiagnostic(.entryTooLarge, "Engine file '\(url.lastPathComponent)' is \(size) bytes; the limit is \(limits.maximumEntrySize)."))
            }
            let (newTotal, overflow) = declaredTotal.addingReportingOverflow(size)
            guard !overflow, newTotal <= limits.maximumTotalSize else {
                throw WalFailure(WalDiagnostic(.totalSizeExceeded, "Engine directory expands beyond the \(limits.maximumTotalSize)-byte total limit."))
            }
            declaredTotal = newTotal

            let relativeComponents = Array(url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count))
            let relative = relativeComponents.joined(separator: "/")
            guard !relative.isEmpty, !relativeComponents.contains(".."), !relativeComponents.contains(".") else {
                throw WalFailure(WalDiagnostic(.unsafePath, "Unsafe engine resource path '\(relative)'."))
            }
            let folded = Self.fold(relative)
            guard canonical[folded] == nil else {
                throw WalFailure(WalDiagnostic(.caseCollision, "Engine files '\(canonical[folded]!)' and '\(relative)' collide in case-insensitive lookup."))
            }
            canonical[folded] = relative
            byFolded[folded] = url
            sizes[folded] = size
        }

        self.rootURL = standardizedRoot
        self.limits = limits
        self.fileURLsByFoldedPath = byFolded
        self.canonicalPathsByFoldedPath = canonical
        self.sizesByFoldedPath = sizes
    }

    var resourcePaths: [String] {
        canonicalPathsByFoldedPath.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func canonicalPath(for path: String) -> String? {
        guard let normalized = try? Self.normalize(path) else { return nil }
        return canonicalPathsByFoldedPath[Self.fold(normalized)]
    }

    func data(for path: String) throws -> Data {
        guard let normalized = try? Self.normalize(path) else {
            throw WalFailure(WalDiagnostic(.unsafePath, "Unsafe engine resource path '\(path)'."))
        }
        let folded = Self.fold(normalized)
        guard let url = fileURLsByFoldedPath[folded], let expected = sizesByFoldedPath[folded] else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Engine resource '\(path)' does not exist."))
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard UInt64(data.count) <= limits.maximumEntrySize, UInt64(data.count) == expected else {
            throw WalFailure(WalDiagnostic(.entryTooLarge, "Engine resource '\(path)' changed size after validation."))
        }
        return data
    }

    private static func normalize(_ raw: String) throws -> String {
        let value = raw.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !value.isEmpty, !value.split(separator: "/").contains("..") else {
            throw WalFailure(WalDiagnostic(.unsafePath, "Unsafe engine resource path '\(raw)'."))
        }
        return value
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
