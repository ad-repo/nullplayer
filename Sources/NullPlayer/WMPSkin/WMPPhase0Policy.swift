import Foundation
import ZIPFoundation

enum WMPPhase0Limits {
    static let archiveEntries = 4_096
    static let entryUncompressedBytes: UInt64 = 32 * 1_024 * 1_024
    static let archiveUncompressedBytes: UInt64 = 128 * 1_024 * 1_024
    static let entryCompressionRatio = 200.0
    /// The ratio bound is only asked about entries that expand past this. A ratio is not the
    /// quantity a decompression bomb is dangerous in — absolute expanded bytes is, and
    /// `entryUncompressedBytes` and `archiveUncompressedBytes` already bound that. Below the floor
    /// the ratio measures how *boring* an image is: an uncompressed flat-colour BMP naturally
    /// squashes 240:1 to 850:1, and 13 of the 180 installed archives were rejected for a blank
    /// background. Every entry over 200:1 anywhere in that corpus is a `.bmp`, the largest expands
    /// to 842,636 bytes, and the worst archive holding one totals 5.3 MB. A real bomb is huge by
    /// definition and still meets the ratio gate above the floor, then the 32 MiB entry bound.
    static let entryCompressionRatioFloorBytes: UInt64 = 1 * 1_024 * 1_024
    /// An archive whose first four bytes are not a ZIP local file header signature is read into
    /// memory once so `WMPArchiveHeaderRepair` can check it against its own central directory. That
    /// is the only path that holds a whole archive at once, so it carries its own bound; it is a
    /// new ceiling on a case that previously could not load at all, never a relaxation. A `.wmz`
    /// is compressed artwork and markup — the largest in the 180-archive corpus is 5.2 MB — so
    /// 32 MiB is far above any real skin and far below a memory problem.
    static let repairableArchiveFileBytes: UInt64 = 32 * 1_024 * 1_024
    static let wrapperDirectories = 1
    static let xmlDepth = 256
    static let xmlNodes = 100_000
    /// A per-axis sanity ceiling, not the memory guard. `imagePixels` below is what bounds an
    /// allocation, and it binds first for anything square: a 32,768-wide image that also satisfies
    /// the 32 Mpx area bound is at most 976 tall. The axis bound exists to keep `bytesPerRow`
    /// arithmetic far from overflow (32,768 x 4 = 128 KiB per row) and to reject a declared
    /// dimension that is nonsense on its face.
    ///
    /// It was 8,192, which is a texture-size number and the wrong shape for this format: a WMP
    /// slider or progress bar is authored as one horizontal filmstrip of frames, so a legitimate
    /// skin resource is routinely thousands of pixels wide and a few dozen tall. Across the 180
    /// installed archives exactly four images exceed 8,192 on an axis and all four are filmstrips
    /// — `pharaoh/seek_steps.bmp` 15990x20, `Nautical/vol_slider.bmp` 9494x144 (a GIF named
    /// `.bmp`), `The_Doobie_Brothers/vol_anim.bmp` 9152x45 and `Ice/Vid-set.bmp` 9144x12. The
    /// largest is 412 Kpx, three orders of magnitude under the area bound, so the old value was
    /// costing three skins their whole load and a fourth its only view while protecting nothing.
    static let imageDimension = 32_768
    static let imagePixels: UInt64 = 32_000_000
    static let scriptBytes: UInt64 = 4 * 1_024 * 1_024
    static let expressionDependencyDepth = 128
    static let expressionPasses = 256
    static let activeTimers = 256
    static let minimumTimerPeriodMilliseconds = 8
    static let preferenceValueBytes = 64 * 1_024
    static let scriptMessageBytes = 1 * 1_024 * 1_024
    /// Wall-clock budget for one script transaction. It replaced the helper process's per-batch
    /// deadline when the runtime moved in-process (Amendment 2); the number is the same 0.25 s the
    /// helper was given, and it is enforced by JavaScriptCore's execution-time limit rather than by
    /// killing a process.
    static let scriptExecutionSeconds: TimeInterval = 0.25
    static let scriptInFlightBytes = 16 * 1_024 * 1_024
}

enum WMPPhase0DiagnosticCode: String, Codable, CaseIterable {
    case archiveUnreadable = "WMP0001"
    case tooManyEntries = "WMP0002"
    case entryTooLarge = "WMP0003"
    case archiveTooLarge = "WMP0004"
    case compressionRatioExceeded = "WMP0005"
    case absolutePath = "WMP0006"
    case drivePath = "WMP0007"
    case pathTraversal = "WMP0008"
    case symbolicLink = "WMP0009"
    case caseCollision = "WMP0010"
    case wrapperDepthExceeded = "WMP0011"
    case crcMismatch = "WMP0012"
    case xmlDepthExceeded = "WMP0013"
    case xmlNodeLimitExceeded = "WMP0014"
    case oversizedImage = "WMP0015"
    case oversizedScript = "WMP0016"
    case scriptMessageTooLarge = "WMP0017"
    case scriptTimedOut = "WMP0018"
    case scriptCrashed = "WMP0019"
    case scriptProtocolViolation = "WMP0020"
}

struct WMPPhase0Diagnostic: Error, Equatable, Codable, CustomStringConvertible {
    let code: WMPPhase0DiagnosticCode
    let path: String?
    let detail: String

    var description: String {
        [code.rawValue, path, detail].compactMap { $0 }.joined(separator: ": ")
    }
}

/// Read-only, no-extraction audit used by Phase 0 to lock the hostile-container contract.
/// Phase 1 replaces this proof with the production resource provider while retaining its codes.
enum WMPPhase0ArchiveAuditor {
    static func audit(url: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw WMPPhase0Diagnostic(code: .archiveUnreadable, path: nil, detail: error.localizedDescription)
        }

        var entryCount = 0
        var totalBytes: UInt64 = 0
        var normalizedPaths = Set<String>()
        var wmsPaths: [[Substring]] = []
        var admittedEntries: [(entry: Entry, path: String)] = []

        for entry in archive {
            entryCount += 1
            guard entryCount <= WMPPhase0Limits.archiveEntries else {
                throw diagnostic(.tooManyEntries, entry.path, "limit \(WMPPhase0Limits.archiveEntries)")
            }

            let normalized = try normalizedPath(entry.path)
            let collisionKey = normalized.precomposedStringWithCanonicalMapping.lowercased()
            guard normalizedPaths.insert(collisionKey).inserted else {
                throw diagnostic(.caseCollision, entry.path, "case-insensitive normalized path already exists")
            }
            guard entry.type != .symlink else {
                throw diagnostic(.symbolicLink, entry.path, "symbolic links are not resources")
            }

            if entry.type == .file {
                if normalized.lowercased().hasSuffix(".js"), entry.uncompressedSize > WMPPhase0Limits.scriptBytes {
                    throw diagnostic(.oversizedScript, entry.path, "\(entry.uncompressedSize) bytes")
                }
                guard entry.uncompressedSize <= WMPPhase0Limits.entryUncompressedBytes else {
                    throw diagnostic(.entryTooLarge, entry.path, "\(entry.uncompressedSize) bytes")
                }
                let sum = totalBytes.addingReportingOverflow(entry.uncompressedSize)
                guard !sum.overflow, sum.partialValue <= WMPPhase0Limits.archiveUncompressedBytes else {
                    throw diagnostic(.archiveTooLarge, entry.path, "archive uncompressed bytes exceed limit")
                }
                totalBytes = sum.partialValue
                if entry.uncompressedSize > WMPPhase0Limits.entryCompressionRatioFloorBytes {
                    let ratio = Double(entry.uncompressedSize) / Double(max(entry.compressedSize, 1))
                    guard ratio <= WMPPhase0Limits.entryCompressionRatio else {
                        throw diagnostic(.compressionRatioExceeded, entry.path, String(format: "%.2f:1", ratio))
                    }
                }
                if normalized.lowercased().hasSuffix(".wms") {
                    wmsPaths.append(normalized.split(separator: "/"))
                }
                admittedEntries.append((entry, normalized))
            }
        }

        if wmsPaths.contains(where: { $0.count > WMPPhase0Limits.wrapperDirectories + 1 }) {
            throw diagnostic(.wrapperDepthExceeded, nil, "a .wms file may be at root or under one wrapper directory")
        }

        // Only touch compressed payloads after every central-directory limit has passed. This
        // prevents a rejected archive from spending decompression work or producing partial state.
        for admitted in admittedEntries {
            var data = Data()
            do {
                let checksum = try archive.extract(admitted.entry, bufferSize: 64 * 1_024) { chunk in
                    if data.count <= 1_048_576 { data.append(chunk) }
                }
                guard checksum == admitted.entry.checksum else {
                    throw diagnostic(.crcMismatch, admitted.entry.path,
                                     "expected \(admitted.entry.checksum), got \(checksum)")
                }
            } catch {
                if let diagnostic = error as? WMPPhase0Diagnostic { throw diagnostic }
                throw diagnostic(.crcMismatch, admitted.entry.path, error.localizedDescription)
            }
            try auditContent(data, path: admitted.path, declaredSize: admitted.entry.uncompressedSize)
        }
    }

    private static func normalizedPath(_ original: String) throws -> String {
        let path = original.replacingOccurrences(of: "\\", with: "/")
        guard !path.hasPrefix("/") else { throw diagnostic(.absolutePath, original, "absolute path") }
        let scalars = Array(path.unicodeScalars)
        if scalars.count >= 2, CharacterSet.letters.contains(scalars[0]), scalars[1] == ":" {
            throw diagnostic(.drivePath, original, "Windows drive prefix")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else { throw diagnostic(.pathTraversal, original, "parent traversal") }
        return components.filter { !$0.isEmpty && $0 != "." }.joined(separator: "/")
    }

    private static func auditContent(_ data: Data, path: String, declaredSize: UInt64) throws {
        let lower = path.lowercased()
        if lower.hasSuffix(".wms") {
            try WMPPhase0XMLCounter.audit(data: data, path: path)
        } else if lower.hasSuffix(".bmp"), data.count >= 26 {
            let width = abs(Int(readInt32LE(data, at: 18)))
            let height = abs(Int(readInt32LE(data, at: 22)))
            let pixels = UInt64(width).multipliedReportingOverflow(by: UInt64(height))
            if width > WMPPhase0Limits.imageDimension || height > WMPPhase0Limits.imageDimension
                || pixels.overflow || pixels.partialValue > WMPPhase0Limits.imagePixels {
                throw diagnostic(.oversizedImage, path, "\(width)x\(height)")
            }
        } else if lower.hasSuffix(".js"), declaredSize > WMPPhase0Limits.scriptBytes {
            throw diagnostic(.oversizedScript, path, "\(declaredSize) bytes")
        }
    }

    private static func readInt32LE(_ data: Data, at offset: Int) -> Int32 {
        let value = UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
        return Int32(bitPattern: value)
    }

    private static func diagnostic(_ code: WMPPhase0DiagnosticCode, _ path: String?, _ detail: String) -> WMPPhase0Diagnostic {
        WMPPhase0Diagnostic(code: code, path: path, detail: detail)
    }
}

private final class WMPPhase0XMLCounter: NSObject, XMLParserDelegate {
    private var depth = 0
    private var nodes = 0
    private var failure: WMPPhase0Diagnostic?
    private let path: String

    private init(path: String) { self.path = path }

    static func audit(data: Data, path: String) throws {
        let counter = WMPPhase0XMLCounter(path: path)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = counter
        _ = parser.parse()
        if let failure = counter.failure { throw failure }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        depth += 1
        nodes += 1
        if depth > WMPPhase0Limits.xmlDepth {
            failure = WMPPhase0Diagnostic(code: .xmlDepthExceeded, path: path, detail: "depth \(depth)")
            parser.abortParsing()
        } else if nodes > WMPPhase0Limits.xmlNodes {
            failure = WMPPhase0Diagnostic(code: .xmlNodeLimitExceeded, path: path, detail: "nodes \(nodes)")
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        depth -= 1
    }
}
