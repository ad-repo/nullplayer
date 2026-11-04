import Foundation

/// AIMP 2's `ACSP` package (`.acs`, `reference/format.md` § *AIMP 2*): nothing scrambled.
/// - `ACSP`, a `u8` version (2 or 3), the name (32 bytes) and author (35 bytes) in the Windows code
///   page, NUL-padded, then a `u32` entry count at `0x48`, and from `0x4C` one zlib body.
/// - The body is the entries back to back, `{ name, u32 size, bytes }`: version 2 names are 32
///   NUL-padded bytes, version 3's a `u8` length and the name. Version 3 leaves the header's name and
///   author empty and credits them in `main.ini`'s `[FILE]`.
///
/// Entry names stay as the package spells them: version 2's pictures are `<Object>_skin.bmp`,
/// version 3's `<Object>.bmp` (`AIMPSkinLegacy` reads both).
extension AIMPSkinArchive {
    static func readACSP(_ data: Data) throws -> AIMPSkinArchive {
        guard data.count >= 0x4C else { throw AIMPSkinFinding(.notAnArchive, "The ACSP header is \(data.count) bytes.") }
        let head = AIMPSkinBytes(data, code: .notAnArchive)
        let version = try head.u8(at: 4)
        guard version == 2 || version == 3 else {
            throw AIMPSkinFinding(.unsupportedFormat, "ACSP version \(version) skins are not supported.")
        }
        let count = try entryCount(head.u32(at: 0x48))
        let body = try AIMPSkinZlib.inflate(data.dropFirst(0x4C), expected: nil, name: "the ACSP body", notZlib: .notAnArchive)
        var reader = AIMPSkinBytes(body, code: .entryOutOfBounds)
        var entries: [(name: String, range: Range<Int>)] = []
        for _ in 0..<count {
            let name = text(try reader.bytes(version == 2 ? 32 : Int(try reader.u8())))
            entries.append((name, try reader.skip(try reader.u32())))
        }
        return try AIMPSkinArchive(acsp: entries, header: (text(try head.bytes(at: 5..<0x25)), text(try head.bytes(at: 0x25..<0x48))),
                                   storage: body)
    }

    /// NUL-padded text in the Windows code page AIMP 2 wrote (Cyrillic, for most of the catalog).
    private static func text<Bytes: Collection>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        let used = bytes.prefix { $0 != 0 }
        return String(bytes: used, encoding: .windowsCP1251) ?? String(decoding: used, as: UTF8.self)
    }
}
