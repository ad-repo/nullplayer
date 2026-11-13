import Foundation

extension Data {
    /// Media servers can embed single Latin-1/Windows-1252 bytes (e.g. a raw "M\u{F6}tley Cr\u{FC}e"
    /// tag) in otherwise UTF-8 JSON, which `JSONDecoder` rejects wholesale. Returns the data with
    /// each invalid byte replaced by "?" (bitmap skin fonts lack U+FFFD), or nil when already valid.
    var utf8Repaired: Data? {
        guard String(data: self, encoding: .utf8) == nil else { return nil }
        return Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: "\u{FFFD}", with: "?").utf8)
    }
}
