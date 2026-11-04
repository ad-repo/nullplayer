import Foundation

extension AIMPSkinScript {
    // MARK: - FSXMLBIN

    /// `FSXMLBIN`, then nodes of `{ u16 + UTF-16LE tag, u16 + UTF-16LE attribute text, u32 child count }`.
    static func parse(_ data: Data) throws -> AIMPNode {
        let bytes = [UInt8](data)
        guard bytes.count > 8, bytes.prefix(8).elementsEqual("FSXMLBIN".utf8) else { throw Unsupported(what: "not FSXMLBIN") }
        var at = 8
        var nodes = 0
        func u16() throws -> Int {
            guard at + 2 <= bytes.count else { throw Unsupported(what: "truncated") }
            defer { at += 2 }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8
        }
        func wide() throws -> String {
            let n = try u16() * 2
            guard at + n <= bytes.count else { throw Unsupported(what: "truncated") }
            defer { at += n }
            return String(bytes: bytes[at..<(at + n)], encoding: .utf16LittleEndian) ?? ""
        }
        func node(_ depth: Int) throws -> AIMPNode {
            nodes += 1
            guard depth < AIMPSkinPolicy.xmlDepth, nodes < AIMPSkinPolicy.xmlNodes else { throw Unsupported(what: "too deep") }
            let tag = try wide()
            var attributes: [String: String] = [:]
            let text = try wide()
            var rest = Substring(text)
            // `name="value"` pairs; a value never holds a double quote.
            while let eq = rest.firstIndex(of: "=") {
                let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
                let afterQuote = rest.index(eq, offsetBy: 2, limitedBy: rest.endIndex) ?? rest.endIndex
                guard afterQuote <= rest.endIndex, let close = rest[afterQuote...].firstIndex(of: "\"") else { break }
                attributes[key] = decodeEntities(String(rest[afterQuote..<close]))
                rest = rest[rest.index(after: close)...]
            }
            guard at + 4 <= bytes.count else { throw Unsupported(what: "truncated") }
            let count = (0..<4).reduce(0) { $0 | Int(bytes[at + $1]) << (8 * $1) }
            at += 4
            var children: [AIMPNode] = []
            for _ in 0..<count { children.append(try node(depth + 1)) }
            return AIMPNode(tag: tag, attributes: attributes, children: children, text: nil)
        }
        return try node(0)
    }

    /// XML character references in attribute text (`&#60;&#62;` is `<>`).
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            guard let semi = rest[amp...].firstIndex(of: ";") else { break }
            let entity = rest[rest.index(after: amp)..<semi]
            switch entity {
            case "lt": out += "<"
            case "gt": out += ">"
            case "amp": out += "&"
            case "quot": out += "\""
            case "apos": out += "'"
            default:
                if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()), let scalar = UnicodeScalar(code) {
                    out.append(Character(scalar))
                } else {
                    out += rest[amp...semi]
                }
            }
            rest = rest[rest.index(after: semi)...]
        }
        return out + rest
    }
}
