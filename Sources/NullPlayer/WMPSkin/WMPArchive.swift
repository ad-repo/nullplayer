import Foundation
import ZIPFoundation

struct WMPArchiveLimits: Equatable {
    var maximumEntryCount = WMPPhase0Limits.archiveEntries
    var maximumEntrySize = WMPPhase0Limits.entryUncompressedBytes
    var maximumTotalSize = WMPPhase0Limits.archiveUncompressedBytes
    var maximumCompressionRatio = UInt64(WMPPhase0Limits.entryCompressionRatio)
    var maximumImageDimension = WMPPhase0Limits.imageDimension
    var maximumImagePixels = WMPPhase0Limits.imagePixels
    var maximumScriptSize = WMPPhase0Limits.scriptBytes

    static let production = WMPArchiveLimits()
}

protocol WMPResourceProviding: AnyObject {
    var resourcePaths: [String] { get }
    func canonicalPath(for path: String) -> String?
    func data(for path: String) throws -> Data
}

extension WMPResourceProviding {
    /// Resolve like WMP: first relative to the declaring file, then from the skin root.
    func resolve(_ authoredPath: String, relativeTo declaringPath: String) throws -> String? {
        let value = authoredPath.replacingOccurrences(of: "\\", with: "/")
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains(":"), !value.utf8.contains(0) else {
            throw WMPFailure(WMPDiagnostic(.resourceEscapesProvider,
                "Resource path '\(authoredPath)' is absolute, drive-qualified, or invalid."))
        }

        let declaringDirectory = declaringPath.split(separator: "/").dropLast().map(String.init)
        if let relative = try WMPPath.normalize(value, base: declaringDirectory),
           let canonical = canonicalPath(for: relative) {
            return canonical
        }
        if let rooted = try WMPPath.normalize(value, base: []),
           let canonical = canonicalPath(for: rooted) {
            return canonical
        }
        return nil
    }
}

struct WMPArchiveEntryInfo: Hashable {
    let path: String
    let compressedSize: UInt64
    let uncompressedSize: UInt64
}

final class WMPArchive: WMPResourceProviding {
    let sourceURL: URL
    let limits: WMPArchiveLimits
    let rootPrefix: String?
    let entries: [WMPArchiveEntryInfo]
    let skinDefinitionPath: String

    private let archive: Archive
    private let archiveLock = NSLock()
    private let entriesByFoldedPath: [String: Entry]
    private let canonicalPathsByFoldedPath: [String: String]

    init(url: URL, limits: WMPArchiveLimits = .production) throws {
        let opened: Archive
        do {
            opened = try Archive(url: url, accessMode: .read)
        } catch {
            throw WMPFailure(WMPDiagnostic(.invalidArchive,
                "Unable to open '\(url.lastPathComponent)' as a ZIP-based .wmz archive: \(error.localizedDescription)"))
        }

        var files: [(Entry, String)] = []
        var total: UInt64 = 0
        var count = 0
        var admittedPaths = Set<String>()
        for entry in opened {
            count += 1
            guard count <= limits.maximumEntryCount else {
                throw WMPFailure(WMPDiagnostic(.entryLimitExceeded,
                    "Archive contains more than \(limits.maximumEntryCount) entries."))
            }
            let normalized = try WMPPath.validateArchivePath(entry.path)
            guard admittedPaths.insert(WMPPath.fold(normalized)).inserted else {
                throw WMPFailure(WMPDiagnostic(.caseCollision,
                    "Archive path '\(entry.path)' collides in case-insensitive normalized lookup."))
            }
            guard entry.type != .symlink else {
                throw WMPFailure(WMPDiagnostic(.symbolicLink,
                    "Symbolic link entry '\(entry.path)' is not allowed."))
            }
            guard entry.type == .file else { continue }
            if normalized.lowercased().hasSuffix(".js"), entry.uncompressedSize > limits.maximumScriptSize {
                throw WMPFailure(WMPDiagnostic(.oversizedScript,
                    "Script '\(entry.path)' exceeds the \(limits.maximumScriptSize)-byte script limit."))
            }
            guard entry.uncompressedSize <= limits.maximumEntrySize else {
                throw WMPFailure(WMPDiagnostic(.entryTooLarge,
                    "Entry '\(entry.path)' exceeds the \(limits.maximumEntrySize)-byte limit."))
            }
            let (nextTotal, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, nextTotal <= limits.maximumTotalSize else {
                throw WMPFailure(WMPDiagnostic(.totalSizeExceeded,
                    "Archive expands beyond the \(limits.maximumTotalSize)-byte total limit."))
            }
            total = nextTotal
            if entry.uncompressedSize > 0 {
                guard entry.compressedSize > 0, limits.maximumCompressionRatio > 0 else {
                    throw WMPFailure(WMPDiagnostic(.compressionRatioExceeded,
                        "Entry '\(entry.path)' exceeds the compression-ratio limit."))
                }
                let allowed = entry.compressedSize > UInt64.max / limits.maximumCompressionRatio
                    ? UInt64.max : entry.compressedSize * limits.maximumCompressionRatio
                guard entry.uncompressedSize <= allowed else {
                    throw WMPFailure(WMPDiagnostic(.compressionRatioExceeded,
                        "Entry '\(entry.path)' exceeds the \(limits.maximumCompressionRatio):1 compression-ratio limit."))
                }
            }
            files.append((entry, normalized))
        }

        let candidates = files.filter { $0.1.lowercased().hasSuffix(".wms") }
        guard !candidates.isEmpty else {
            throw WMPFailure(WMPDiagnostic(.invalidRoot,
                "Archive must contain one .wms file at its root or inside one wrapper directory."))
        }
        guard candidates.count == 1 else {
            throw WMPFailure(WMPDiagnostic(.ambiguousSkinDefinition,
                "Archive contains multiple .wms skin definitions; no deterministic WMP selection rule applies."))
        }
        let components = candidates[0].1.split(separator: "/")
        guard components.count == 1 || components.count == 2 else {
            throw WMPFailure(WMPDiagnostic(.wrapperDepthExceeded,
                "The .wms file may be nested beneath at most one wrapper directory."))
        }
        let prefix = components.count == 2 ? String(components[0]) : nil

        var byFolded: [String: Entry] = [:]
        var canonical: [String: String] = [:]
        var publicEntries: [WMPArchiveEntryInfo] = []
        for (entry, normalized) in files {
            let relative: String
            if let prefix {
                let expected = prefix + "/"
                guard normalized.lowercased().hasPrefix(expected.lowercased()) else {
                    throw WMPFailure(WMPDiagnostic(.wrapperDepthExceeded,
                        "Entry '\(entry.path)' sits outside wrapper directory '\(prefix)'."))
                }
                relative = String(normalized.dropFirst(expected.count))
            } else {
                relative = normalized
            }
            guard !relative.isEmpty else { continue }
            let folded = WMPPath.fold(relative)
            guard canonical[folded] == nil else {
                throw WMPFailure(WMPDiagnostic(.caseCollision,
                    "Entries '\(canonical[folded]!)' and '\(relative)' collide in case-insensitive lookup."))
            }
            canonical[folded] = relative
            byFolded[folded] = entry
            publicEntries.append(WMPArchiveEntryInfo(path: relative,
                compressedSize: entry.compressedSize, uncompressedSize: entry.uncompressedSize))
        }

        let relativeWMS = prefix == nil ? candidates[0].1
            : String(candidates[0].1.dropFirst(prefix!.count + 1))

        // Validate every stream and CRC before exposing even a read-only provider.
        for (entry, normalized) in files {
            var inflated: UInt64 = 0
            var header = Data()
            do {
                let checksum = try opened.extract(entry) { chunk in
                    let (next, overflow) = inflated.addingReportingOverflow(UInt64(chunk.count))
                    guard !overflow, next <= entry.uncompressedSize, next <= limits.maximumEntrySize else {
                        throw WMPFailure(WMPDiagnostic(.entryTooLarge,
                            "Inflated data for '\(normalized)' exceeded its declared bounds."))
                    }
                    inflated = next
                    if header.count < 1_048_576 {
                        header.append(chunk.prefix(1_048_576 - header.count))
                    }
                }
                guard checksum == entry.checksum else {
                    throw WMPFailure(WMPDiagnostic(.crcMismatch,
                        "CRC validation failed for '\(normalized)'."))
                }
            } catch let failure as WMPFailure {
                throw failure
            } catch {
                throw WMPFailure(WMPDiagnostic(.crcMismatch,
                    "CRC or stream validation failed for '\(normalized)': \(error.localizedDescription)"))
            }
            guard inflated == entry.uncompressedSize else {
                throw WMPFailure(WMPDiagnostic(.invalidArchive,
                    "Entry '\(normalized)' produced \(inflated) bytes, not its declared \(entry.uncompressedSize)."))
            }
            try Self.validateImageHeader(header, path: normalized, limits: limits)
        }

        sourceURL = url
        self.limits = limits
        rootPrefix = prefix
        archive = opened
        entriesByFoldedPath = byFolded
        canonicalPathsByFoldedPath = canonical
        entries = publicEntries.sorted { WMPPath.less($0.path, $1.path) }
        skinDefinitionPath = canonical[WMPPath.fold(relativeWMS)] ?? relativeWMS
    }

    private static func validateImageHeader(_ data: Data, path: String, limits: WMPArchiveLimits) throws {
        guard path.lowercased().hasSuffix(".bmp"), data.count >= 26,
              data[0] == 0x42, data[1] == 0x4D else { return }
        func int32(at offset: Int) -> Int32 {
            let value = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            return Int32(bitPattern: value)
        }
        let width = abs(Int(int32(at: 18)))
        let height = abs(Int(int32(at: 22)))
        let pixels = UInt64(width).multipliedReportingOverflow(by: UInt64(height))
        guard width <= limits.maximumImageDimension, height <= limits.maximumImageDimension,
              !pixels.overflow, pixels.partialValue <= limits.maximumImagePixels else {
            throw WMPFailure(WMPDiagnostic(.oversizedImage,
                "Image '\(path)' declares dimensions \(width)x\(height), beyond the production limit."))
        }
    }

    var resourcePaths: [String] { entries.map(\.path) }

    func entryInfo(for path: String) -> WMPArchiveEntryInfo? {
        guard let canonical = canonicalPath(for: path) else { return nil }
        return entries.first { WMPPath.fold($0.path) == WMPPath.fold(canonical) }
    }

    func canonicalPath(for path: String) -> String? {
        guard let normalized = try? WMPPath.normalize(path, base: []) else { return nil }
        return canonicalPathsByFoldedPath[WMPPath.fold(normalized)]
    }

    func data(for path: String) throws -> Data {
        guard let canonical = canonicalPath(for: path),
              let entry = entriesByFoldedPath[WMPPath.fold(canonical)] else {
            throw WMPFailure(WMPDiagnostic(.resourceMissing,
                "Archive resource '\(path)' does not exist."))
        }
        var output = Data()
        output.reserveCapacity(Int(min(entry.uncompressedSize, UInt64(Int.max))))
        archiveLock.lock()
        defer { archiveLock.unlock() }
        do {
            _ = try archive.extract(entry) { chunk in
                let next = UInt64(output.count) + UInt64(chunk.count)
                guard next <= entry.uncompressedSize, next <= limits.maximumEntrySize else {
                    throw WMPFailure(WMPDiagnostic(.entryTooLarge,
                        "Inflated data for '\(canonical)' exceeded its validated size."))
                }
                output.append(chunk)
            }
        } catch let failure as WMPFailure {
            throw failure
        } catch {
            throw WMPFailure(WMPDiagnostic(.invalidArchive,
                "Failed to read '\(canonical)': \(error.localizedDescription)"))
        }
        guard UInt64(output.count) == entry.uncompressedSize else {
            throw WMPFailure(WMPDiagnostic(.invalidArchive,
                "Entry '\(canonical)' did not produce its declared byte count."))
        }
        return output
    }
}

enum WMPPath {
    static func validateArchivePath(_ raw: String) throws -> String {
        guard !raw.isEmpty, !raw.utf8.contains(0) else {
            throw WMPFailure(WMPDiagnostic(.pathTraversal, "Invalid archive path '\(raw)'."))
        }
        guard !raw.hasPrefix("/"), !raw.hasPrefix("\\") else {
            throw WMPFailure(WMPDiagnostic(.absolutePath, "Absolute archive path '\(raw)' is not allowed."))
        }
        let value = raw.replacingOccurrences(of: "\\", with: "/")
        let scalars = Array(value.unicodeScalars)
        if scalars.count >= 2, CharacterSet.letters.contains(scalars[0]), scalars[1] == ":" {
            throw WMPFailure(WMPDiagnostic(.drivePath, "Drive-qualified archive path '\(raw)' is not allowed."))
        }
        guard !value.contains(":") else {
            throw WMPFailure(WMPDiagnostic(.pathTraversal, "Invalid archive path '\(raw)'."))
        }
        var result: [Substring] = []
        for component in value.split(separator: "/", omittingEmptySubsequences: false) {
            if component.isEmpty || component == "." { continue }
            guard component != ".." else {
                throw WMPFailure(WMPDiagnostic(.pathTraversal, "Traversal archive path '\(raw)' is not allowed."))
            }
            result.append(component)
        }
        guard !result.isEmpty else {
            throw WMPFailure(WMPDiagnostic(.pathTraversal, "Archive path '\(raw)' has no resource name."))
        }
        return result.joined(separator: "/")
    }

    static func normalize(_ raw: String, base: [String]) throws -> String? {
        let value = raw.replacingOccurrences(of: "\\", with: "/")
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains(":"), !value.utf8.contains(0) else {
            throw WMPFailure(WMPDiagnostic(.resourceEscapesProvider, "Unsafe resource path '\(raw)'."))
        }
        var components = base
        for component in value.split(separator: "/", omittingEmptySubsequences: false) {
            if component.isEmpty || component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else {
                    throw WMPFailure(WMPDiagnostic(.resourceEscapesProvider,
                        "Resource path '\(raw)' escapes the skin provider."))
                }
                components.removeLast()
            } else {
                components.append(String(component))
            }
        }
        return components.isEmpty ? nil : components.joined(separator: "/")
    }

    static func fold(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func less(_ lhs: String, _ rhs: String) -> Bool {
        let left = fold(lhs), right = fold(rhs)
        return left == right ? lhs < rhs : left < right
    }
}
