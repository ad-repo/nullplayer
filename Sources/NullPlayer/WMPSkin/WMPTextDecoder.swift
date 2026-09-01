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
