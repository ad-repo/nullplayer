import Foundation

extension JSONDecoder {
    /// `decode`, tolerating invalid UTF-8. Media servers can embed single Latin-1/Windows-1252
    /// bytes (e.g. a raw "M\u{F6}tley Cr\u{FC}e" tag) in otherwise UTF-8 JSON, which `decode`
    /// rejects wholesale. When the plain decode fails on such data, it is retried with each invalid
    /// byte replaced by "?" (bitmap skin fonts lack U+FFFD). Any genuine U+FFFD in that payload
    /// becomes "?" too. If the retry also fails, or the data was valid UTF-8, the original error
    /// is thrown.
    func decodeRepairingUTF8<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decode(type, from: data)
        } catch {
            guard String(data: data, encoding: .utf8) == nil else { throw error }
            let repaired = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{FFFD}", with: "?").utf8)
            guard let value = try? decode(type, from: repaired) else { throw error }
            NSLog("JSONDecoder: decoded after replacing invalid UTF-8 bytes with ?")
            return value
        }
    }
}
