import Foundation

enum WMPTextEncoding: String, Codable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
    case windows1252
}

struct WMPDecodedText: Equatable {
    let string: String
    let encoding: WMPTextEncoding
}

enum WMPTextDecoder {
    static func decode(_ data: Data, path: String) throws -> WMPDecodedText {
        let bytes = [UInt8](data)
        let decoded: WMPDecodedText?
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            decoded = String(data: Data(bytes.dropFirst(3)), encoding: .utf8)
                .map { WMPDecodedText(string: $0, encoding: .utf8) }
        } else if bytes.starts(with: [0xFF, 0xFE]) {
            decoded = try decodeUTF16(Array(bytes.dropFirst(2)), littleEndian: true)
                .map { WMPDecodedText(string: $0, encoding: .utf16LittleEndian) }
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            decoded = try decodeUTF16(Array(bytes.dropFirst(2)), littleEndian: false)
                .map { WMPDecodedText(string: $0, encoding: .utf16BigEndian) }
        } else if let littleEndian = sniffBOMlessUTF16(bytes) {
            decoded = try decodeUTF16(bytes, littleEndian: littleEndian)
                .map { WMPDecodedText(string: $0,
                                      encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian) }
        } else {
            if let string = String(data: data, encoding: .utf8) {
                decoded = WMPDecodedText(string: string, encoding: .utf8)
            } else {
                // Legacy WMP 7-10 skins were commonly authored as system-ANSI text without an
                // encoding declaration. Windows-1252 is deterministic and single-byte, so this
                // compatibility fallback does not add heuristic code-page detection.
                decoded = String(data: data, encoding: .windowsCP1252)
                    .map { WMPDecodedText(string: $0, encoding: .windows1252) }
            }
        }
        guard let decoded else {
            throw WMPFailure(WMPDiagnostic(.invalidTextEncoding,
                "'\(path)' is not valid UTF-8, UTF-16LE, UTF-16BE, or Windows-1252 text.",
                location: WMPSourceLocation(path: path)))
        }
        guard !decoded.string.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw WMPFailure(WMPDiagnostic(.embeddedNUL,
                "'\(path)' contains an embedded NUL character.",
                location: WMPSourceLocation(path: path)))
        }
        return decoded
    }

    /// Is this BOM-less UTF-16, and if so which way round?
    ///
    /// **Nothing downstream can find this on its own.** Windows-1252 accepts every byte sequence, so
    /// a BOM-less UTF-16 file does not fall through to a *failure* — it decodes "successfully" into
    /// null-interleaved mojibake and the parser then sees a `<` that no `</` ever closes. The `.wal`
    /// engine paid for exactly this with `isoLatin1` (B93). The `WMP0026` embedded-NUL check catches
    /// the byte-level case, but it rejects the skin rather than reading it.
    ///
    /// The test is positional, not statistical: real UTF-16 text of a Latin-script markup file puts a
    /// NUL in every *odd* byte (little-endian) or every *even* byte (big-endian), and essentially
    /// never in the other. A `iconv`-style "is there a lot of zero" guess cannot tell the two apart
    /// and produced null-interleaved text where it guessed the wrong end. Requires a `<` as the first
    /// non-whitespace unit so an ordinary single-byte file that happens to carry NULs is not
    /// misread as text -- it stays a `WMP0026` rejection.
    private static func sniffBOMlessUTF16(_ bytes: [UInt8]) -> Bool? {
        guard bytes.count >= 4, bytes.count.isMultiple(of: 2) else { return nil }
        let sample = min(bytes.count, 4096)
        var evenNULs = 0, oddNULs = 0
        for index in 0..<sample where bytes[index] == 0 {
            if index.isMultiple(of: 2) { evenNULs += 1 } else { oddNULs += 1 }
        }
        let littleEndian: Bool
        if oddNULs > 0, evenNULs == 0 { littleEndian = true }
        else if evenNULs > 0, oddNULs == 0 { littleEndian = false }
        else { return nil }
        // Latin-script UTF-16 is close to half NULs; require a clear majority of the half-sample
        // rather than the handful a stray byte run could produce.
        guard (littleEndian ? oddNULs : evenNULs) * 5 >= sample * 2 else { return nil }
        let leadOffset = littleEndian ? 0 : 1
        var index = leadOffset
        while index < sample {
            let unit = bytes[index]
            if unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D {
                index += 2
                continue
            }
            return unit == 0x3C ? littleEndian : nil
        }
        return nil
    }

    private static func decodeUTF16(_ bytes: [UInt8], littleEndian: Bool) throws -> String? {
        guard bytes.count.isMultiple(of: 2) else { return nil }
        var scalars = String.UnicodeScalarView()
        var index = 0
        while index < bytes.count {
            let unit = littleEndian
                ? UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                : UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            index += 2
            let scalarValue: UInt32
            if (0xD800...0xDBFF).contains(unit) {
                guard index < bytes.count else { return nil }
                let trail = littleEndian
                    ? UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                    : UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
                guard (0xDC00...0xDFFF).contains(trail) else { return nil }
                index += 2
                scalarValue = 0x10000 + (UInt32(unit - 0xD800) << 10) + UInt32(trail - 0xDC00)
            } else {
                guard !(0xDC00...0xDFFF).contains(unit) else { return nil }
                scalarValue = UInt32(unit)
            }
            guard let scalar = UnicodeScalar(scalarValue) else { return nil }
            scalars.append(scalar)
        }
        return String(scalars)
    }
}
