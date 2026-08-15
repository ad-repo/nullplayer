import Foundation
import ZIPFoundation

struct WalArchiveLimits: Equatable {
    var maximumEntryCount = 4_096
    var maximumEntrySize: UInt64 = 32 * 1_024 * 1_024
    var maximumTotalSize: UInt64 = 128 * 1_024 * 1_024
    var maximumCompressionRatio: UInt64 = 200

    static let production = WalArchiveLimits()
}

/// Read-only resource surface used by archives, built-in defaults, and the future engine importer.
protocol WalResourceProvider: AnyObject {
    var resourcePaths: [String] { get }
    func canonicalPath(for path: String) -> String?
    func data(for path: String) throws -> Data
}

struct WalArchiveEntryInfo: Hashable {
    let path: String
    let compressedSize: UInt64
    let uncompressedSize: UInt64
}

/// A validated `.wal` (ZIP) archive. Resources remain in the archive and are inflated on demand.
/// Every path and declared size is validated before the instance becomes usable.
final class WalArchive: WalResourceProvider {
    let sourceURL: URL
    let limits: WalArchiveLimits
    let rootPrefix: String?
    let entries: [WalArchiveEntryInfo]
    let skinXMLPath: String

    private let archive: Archive
    private let archiveLock = NSLock()
    private let entriesByFoldedPath: [String: Entry]
    private let canonicalPathsByFoldedPath: [String: String]

    init(url: URL, limits: WalArchiveLimits = .production) throws {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Unable to open '\(url.lastPathComponent)' as a ZIP-based .wal archive: \(error.localizedDescription)"))
        }

        var fileEntries: [(entry: Entry, normalized: String)] = []
        var declaredTotal: UInt64 = 0
        var entryCount = 0

        for entry in archive {
            entryCount += 1
            guard entryCount <= limits.maximumEntryCount else {
                throw WalFailure(WalDiagnostic(.entryLimitExceeded, "Archive contains more than \(limits.maximumEntryCount) entries."))
            }

            let normalized = try Self.validateArchivePath(entry.path)
            if entry.type == .symlink {
                throw WalFailure(WalDiagnostic(.symbolicLink, "Symbolic link entry '\(entry.path)' is not allowed."))
            }
            guard entry.type == .file else { continue }

            guard entry.uncompressedSize <= limits.maximumEntrySize else {
                throw WalFailure(WalDiagnostic(.entryTooLarge, "Entry '\(entry.path)' declares \(entry.uncompressedSize) bytes; the limit is \(limits.maximumEntrySize)."))
            }
            let (newTotal, overflow) = declaredTotal.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, newTotal <= limits.maximumTotalSize else {
                throw WalFailure(WalDiagnostic(.totalSizeExceeded, "Archive expands beyond the \(limits.maximumTotalSize)-byte total limit."))
            }
            declaredTotal = newTotal

            if entry.uncompressedSize > 0 {
                guard entry.compressedSize > 0, limits.maximumCompressionRatio > 0 else {
                    throw WalFailure(WalDiagnostic(.compressionRatioExceeded, "Entry '\(entry.path)' exceeds the \(limits.maximumCompressionRatio):1 compression-ratio limit."))
                }
                let allowed = entry.compressedSize > UInt64.max / limits.maximumCompressionRatio
                    ? UInt64.max
                    : entry.compressedSize * limits.maximumCompressionRatio
                guard entry.uncompressedSize <= allowed else {
                    throw WalFailure(WalDiagnostic(.compressionRatioExceeded, "Entry '\(entry.path)' exceeds the \(limits.maximumCompressionRatio):1 compression-ratio limit."))
                }
            }
            fileEntries.append((entry, normalized))
        }

        let skinCandidates = fileEntries.filter {
            $0.normalized.split(separator: "/").last?.caseInsensitiveCompare("skin.xml") == .orderedSame
        }
        guard skinCandidates.count == 1 else {
            throw WalFailure(WalDiagnostic(.invalidRoot, skinCandidates.isEmpty
                ? "Archive must contain skin.xml at its root or inside one wrapper directory."
                : "Archive contains multiple case-insensitive skin.xml candidates."))
        }

        let skinComponents = skinCandidates[0].normalized.split(separator: "/")
        guard skinComponents.count == 1 || skinComponents.count == 2 else {
            throw WalFailure(WalDiagnostic(.invalidRoot, "skin.xml may be nested under at most one wrapper directory."))
        }
        let rootPrefix = skinComponents.count == 2 ? String(skinComponents[0]) : nil

        var byFolded: [String: Entry] = [:]
        var canonical: [String: String] = [:]
        var publicEntries: [WalArchiveEntryInfo] = []

        for item in fileEntries {
            let relative: String
            if let rootPrefix {
                let prefix = rootPrefix + "/"
                guard item.normalized.lowercased().hasPrefix(prefix.lowercased()) else {
                    throw WalFailure(WalDiagnostic(.invalidRoot, "Entry '\(item.entry.path)' sits outside the archive's single wrapper directory '\(rootPrefix)'."))
                }
                relative = String(item.normalized.dropFirst(prefix.count))
            } else {
                relative = item.normalized
            }
            guard !relative.isEmpty else { continue }
            let folded = Self.fold(relative)
            guard canonical[folded] == nil else {
                throw WalFailure(WalDiagnostic(.caseCollision, "Entries '\(canonical[folded]!)' and '\(relative)' collide in case-insensitive lookup."))
            }
            canonical[folded] = relative
            byFolded[folded] = item.entry
            publicEntries.append(WalArchiveEntryInfo(
                path: relative,
                compressedSize: item.entry.compressedSize,
                uncompressedSize: item.entry.uncompressedSize
            ))
        }

        guard let canonicalSkin = canonical[Self.fold("skin.xml")] else {
            throw WalFailure(WalDiagnostic(.invalidRoot, "Validated archive root does not contain skin.xml."))
        }

        self.sourceURL = url
        self.limits = limits
        self.rootPrefix = rootPrefix
        self.archive = archive
        self.entriesByFoldedPath = byFolded
        self.canonicalPathsByFoldedPath = canonical
        self.entries = publicEntries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        self.skinXMLPath = canonicalSkin
    }

    var resourcePaths: [String] { entries.map(\.path) }

    func canonicalPath(for path: String) -> String? {
        guard let normalized = try? Self.normalizeProviderPath(path) else { return nil }
        return canonicalPathsByFoldedPath[Self.fold(normalized)]
    }

    func data(for path: String) throws -> Data {
        guard let canonical = canonicalPath(for: path),
              let entry = entriesByFoldedPath[Self.fold(canonical)] else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Archive resource '\(path)' does not exist."))
        }

        var output = Data()
        output.reserveCapacity(Int(min(entry.uncompressedSize, UInt64(Int.max))))
        archiveLock.lock()
        defer { archiveLock.unlock() }
        do {
            _ = try archive.extract(entry) { chunk in
                guard UInt64(output.count) + UInt64(chunk.count) <= limits.maximumEntrySize,
                      UInt64(output.count) + UInt64(chunk.count) <= entry.uncompressedSize else {
                    throw WalFailure(WalDiagnostic(.entryTooLarge, "Inflated data for '\(canonical)' exceeded its validated size."))
                }
                output.append(chunk)
            }
        } catch let failure as WalFailure {
            throw failure
        } catch {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Failed to read '\(canonical)': \(error.localizedDescription)"))
        }
        guard UInt64(output.count) == entry.uncompressedSize else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Entry '\(canonical)' produced \(output.count) bytes, not its declared \(entry.uncompressedSize)."))
        }
        return output
    }

    private static func validateArchivePath(_ raw: String) throws -> String {
        guard !raw.isEmpty else {
            throw WalFailure(WalDiagnostic(.unsafePath, "Archive contains an empty entry path."))
        }
        if raw.hasPrefix("/") || raw.hasPrefix("\\") || raw.contains(":") || raw.utf8.contains(0) {
            throw WalFailure(WalDiagnostic(.unsafePath, "Unsafe absolute or drive-qualified entry path '\(raw)'."))
        }
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        var components: [Substring] = []
        for component in normalized.split(separator: "/", omittingEmptySubsequences: false) {
            if component.isEmpty || component == "." { continue }
            guard component != ".." else {
                throw WalFailure(WalDiagnostic(.unsafePath, "Traversal entry '\(raw)' is not allowed."))
            }
            components.append(component)
        }
        guard !components.isEmpty else {
            throw WalFailure(WalDiagnostic(.unsafePath, "Entry path '\(raw)' has no resource name."))
        }
        return components.joined(separator: "/")
    }

    private static func normalizeProviderPath(_ raw: String) throws -> String {
        let value = raw.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !value.isEmpty, !value.split(separator: "/").contains("..") else {
            throw WalFailure(WalDiagnostic(.unsafePath, "Unsafe provider path '\(raw)'."))
        }
        return value
    }

    private static func fold(_ path: String) -> String {
        path.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
