import Foundation

/// Minimal, bounded reader for NSIS-2 self-extracting installers using solid LZMA compression — the
/// format the ClassicPro engine ships in. It parses the installer entirely in memory (no external
/// tools, no temp files, no code execution): locate the firstheader, decompress the single solid
/// LZMA stream on demand via `LZMA1Decoder`, parse the header's string/entry tables, and replay only
/// the `SetOutPath`/`ExtractFile` instructions to reconstruct the file tree.
///
/// It deliberately supports only what ClassicPro uses (NSIS-2, solid LZMA). Any other layout
/// (non-solid, zlib/bzip2, non-NSIS `.exe`) fails with an actionable diagnostic rather than guessing.
/// Validated against the local ClassicPro installer with `7zz` as a reference oracle; no installer or
/// engine fixture is committed.
enum NSISArchive {
    private static let magic: [UInt8] = [0xEF, 0xBE, 0xAD, 0xDE] + Array("NullsoftInst".utf8)

    // NSIS-2 entry opcodes used here.
    private static let ewCreateDir = 11
    private static let ewExtractFile = 20
    private static let entrySize = 28 // which + 6 parms, each u32

    // NSIS-2 string-encoding control bytes.
    private static let nsSkip = 252
    private static let nsVar = 253
    private static let nsShell = 254
    private static let nsLang = 255

    /// Extract every regular file the installer would write, keyed by a normalized, forward-slashed
    /// path with `$INSTDIR` treated as the root. Files whose resolved path still contains an
    /// unresolved installer variable (`$SHELL…`, `$LANG…`, `$VAR…`) are skipped — they target
    /// external shell folders, not the payload tree.
    static func extract(data: Data, limits: WalArchiveLimits = .production) throws -> [String: Data] {
        let file = [UInt8](data)
        guard let sig = findMagic(in: file) else {
            throw WalFailure(WalDiagnostic(.unsupportedContainer,
                "Not a recognized NSIS installer (missing the Nullsoft signature)."))
        }
        guard sig + 24 <= file.count else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Truncated NSIS firstheader."))
        }
        let headerSize = readU32(file, sig + 16)
        guard headerSize > 4, UInt64(headerSize) <= limits.maximumTotalSize else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Implausible NSIS header size \(headerSize)."))
        }
        let streamStart = sig + 24
        guard streamStart + 10 <= file.count else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "NSIS payload is too short."))
        }

        var decoderLimits = LZMA1Decoder.Limits()
        decoderLimits.maximumOutputBytes = limits.maximumTotalSize
        let decoder = try LZMA1Decoder(stream: data.subdata(in: streamStart..<file.count), limits: decoderLimits)

        // The header block is length-prefixed inside the solid stream: [u32 size][header bytes].
        try decoder.decode(untilOutputCount: 4 + headerSize)
        let sizePrefix = readU32(decoder.output, 0) & 0x7FFF_FFFF
        guard sizePrefix == headerSize else {
            throw WalFailure(WalDiagnostic(.unsupportedContainer,
                "Unsupported NSIS layout (expected NSIS-2 with solid LZMA compression)."))
        }
        let header = Array(decoder.output[4..<(4 + headerSize)])
        let dataSectionStart = 4 + headerSize

        // Block table: flags(u32) then 8 × {offset, num}. Index 2 = entries, 3 = strings.
        guard header.count >= 4 + 8 * 8 else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "NSIS header is too short for a block table."))
        }
        let entriesOffset = readU32(header, 4 + 2 * 8)
        let entriesNum = readU32(header, 4 + 2 * 8 + 4)
        let stringsOffset = readU32(header, 4 + 3 * 8)
        guard entriesNum <= limits.maximumEntryCount * 8 else {
            throw WalFailure(WalDiagnostic(.entryLimitExceeded, "NSIS installer declares \(entriesNum) instructions."))
        }

        var result: [String: Data] = [:]
        var declaredTotal: UInt64 = 0
        var currentOutDir = ""

        for index in 0..<entriesNum {
            let base = entriesOffset + index * entrySize
            guard base + entrySize <= header.count else { break }
            let which = readU32(header, base)
            let p0 = readU32(header, base + 4)
            let p1 = readU32(header, base + 8)
            let p2 = readU32(header, base + 12)

            switch which {
            case ewCreateDir where p1 != 0: // SetOutPath
                currentOutDir = decodeString(header, stringsOffset: stringsOffset, reference: p0)
            case ewExtractFile:
                let name = decodeString(header, stringsOffset: stringsOffset, reference: p1)
                guard let path = normalize(outDir: currentOutDir, name: name) else { continue }
                guard result[path] == nil else { continue }
                guard result.count < limits.maximumEntryCount else {
                    throw WalFailure(WalDiagnostic(.entryLimitExceeded,
                        "NSIS installer expands beyond \(limits.maximumEntryCount) files."))
                }
                let bytes = try readFile(decoder, dataSectionStart: dataSectionStart, position: p2, limits: limits)
                guard UInt64(bytes.count) <= limits.maximumEntrySize else {
                    throw WalFailure(WalDiagnostic(.entryTooLarge, "NSIS file '\(path)' exceeds the per-file limit."))
                }
                let (newTotal, overflow) = declaredTotal.addingReportingOverflow(UInt64(bytes.count))
                guard !overflow, newTotal <= limits.maximumTotalSize else {
                    throw WalFailure(WalDiagnostic(.totalSizeExceeded, "NSIS installer expands beyond the total limit."))
                }
                declaredTotal = newTotal
                result[path] = Data(bytes)
            default:
                continue
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func findMagic(in file: [UInt8]) -> Int? {
        guard file.count >= magic.count else { return nil }
        let first = magic[0]
        var i = 0
        let limit = file.count - magic.count
        while i <= limit {
            if file[i] == first, Array(file[i..<i + magic.count]) == magic { return i }
            i += 1
        }
        return nil
    }

    private static func readU32(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
    }

    private static func readFile(_ decoder: LZMA1Decoder, dataSectionStart: Int, position: Int,
                                 limits: WalArchiveLimits) throws -> [UInt8] {
        guard position >= 0 else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Negative NSIS data position."))
        }
        let at = dataSectionStart + position
        try decoder.decode(untilOutputCount: at + 4)
        guard at + 4 <= decoder.output.count else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "NSIS data position \(position) is out of range."))
        }
        let size = readU32(decoder.output, at) & 0x7FFF_FFFF
        guard UInt64(size) <= limits.maximumEntrySize else {
            throw WalFailure(WalDiagnostic(.entryTooLarge, "NSIS file declares \(size) bytes."))
        }
        try decoder.decode(untilOutputCount: at + 4 + size)
        guard at + 4 + size <= decoder.output.count else {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Truncated NSIS file data."))
        }
        return Array(decoder.output[(at + 4)..<(at + 4 + size)])
    }

    /// Decode an NSIS-2 string: literal bytes plus `$INSTDIR`/`$OUTDIR`/… variable markers. Shell and
    /// language references become recognizable `$SHELL…`/`$LANG…`/`$VAR…` tokens so callers can skip
    /// any path that escapes the payload tree.
    private static func decodeString(_ header: [UInt8], stringsOffset: Int, reference: Int) -> String {
        var i = stringsOffset + reference
        guard i >= 0, i < header.count else { return "" }
        var out = ""
        while i < header.count {
            let b = Int(header[i])
            if b == 0 { break }
            if b >= nsSkip {
                if b == nsSkip {
                    i += 1
                    if i < header.count { out.append(Character(UnicodeScalar(header[i]))) }
                    i += 1
                } else {
                    guard i + 2 < header.count else { break }
                    let value = (Int(header[i + 1]) & 0x7F) | ((Int(header[i + 2]) & 0x7F) << 7)
                    i += 3
                    switch b {
                    case nsVar:
                        switch value {
                        case 21: out += "$INSTDIR"
                        case 22: out += "$OUTDIR"
                        case 23: out += "$EXEDIR"
                        default: out += "$VAR\(value)"
                        }
                    case nsShell: out += "$SHELL\(value)"
                    default: out += "$LANG\(value)"
                    }
                }
            } else {
                out.append(Character(UnicodeScalar(UInt8(b))))
                i += 1
            }
        }
        return out
    }

    /// Join `$OUTDIR`/name, strip `$INSTDIR`, normalize separators, and reject paths that escape the
    /// payload tree or still contain an unresolved installer variable.
    private static func normalize(outDir: String, name: String) -> String? {
        var full = outDir.isEmpty ? name : outDir + "\\" + name
        full = full.replacingOccurrences(of: "$INSTDIR", with: "")
            .replacingOccurrences(of: "\\", with: "/")
        while full.hasPrefix("/") { full.removeFirst() }
        guard !full.isEmpty, !full.contains("$") else { return nil }
        let components = full.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(".."), !components.contains(".") else { return nil }
        return components.joined(separator: "/")
    }
}
