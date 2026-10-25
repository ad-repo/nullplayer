import Foundation

/// The `.sgf` container: a `DAF\0` header and a table of named, uncompressed payloads
/// (`skills/sonique-skin-guide/reference/format.md` § *Container*). Bounds-checked as a whole before
/// any entry is read: `SQ0001` for the header and table, `SQ0003` for the count, `SQ0004` for a
/// payload outside the file.
enum SoniqueSkinArchive {
    struct Entry {
        /// As stored, case kept. The model keys entries by the lowercased name.
        let name: String
        let payload: Data
    }

    private static let countOffset = 0x68
    private static let tableOffset = 0x70
    private static let stride = 0x64
    private static let nameBytes = 0x54
    /// Name, offset and size. The last entry's remaining padding runs into the first payload, so
    /// only these bytes have to fit.
    private static let entryBytes = nameBytes + 8

    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count >= tableOffset, bytes[0..<4] == [0x44, 0x41, 0x46, 0x00] else {
            throw SoniqueSkinFinding(.notAnArchive, "Not a Sonique skin: no DAF header.")
        }
        let count = Int(uint32(bytes, countOffset))
        guard count <= SoniqueSkinPolicy.entries else {
            throw SoniqueSkinFinding(.tooManyEntries, "\(count) entries, more than \(SoniqueSkinPolicy.entries).")
        }
        guard count == 0 || tableOffset + (count - 1) * stride + entryBytes <= bytes.count else {
            throw SoniqueSkinFinding(.notAnArchive, "The entry table runs past the end of the file.")
        }
        return try (0..<count).map { index in
            let at = tableOffset + index * stride
            let field = bytes[at..<at + nameBytes]
            let name = String(bytes: field.prefix { $0 != 0 }, encoding: .isoLatin1) ?? ""
            let offset = Int(uint32(bytes, at + nameBytes)), size = Int(uint32(bytes, at + nameBytes + 4))
            guard offset <= bytes.count, size <= bytes.count - offset else {
                throw SoniqueSkinFinding(.entryOutOfBounds, "\(name) runs past the end of the file.")
            }
            return Entry(name: name, payload: Data(bytes[offset..<offset + size]))
        }
    }

    private static func uint32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        bytes[at..<at + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }
}
