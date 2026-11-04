import Foundation

/// The container of an AIMP skin, from bytes to named entries. Three layouts share one header
/// (`reference/format.md` § *Containers*):
/// - `.acs5` (AIMP 5): the rest of the file XORed with a key stored in the header, then a flat list
///   of entries, each compressed on its own. Entries are decoded on demand.
/// - `.acs4` (AIMP 4): XORed with a 4-byte key that a scrambled `3SCA` in the header gives away,
///   then one zlib body holding a table of contents and a blob.
/// - `.acs3` (AIMP 3): the `.acs4` layout under four header variants.
/// - `.acs4proj` (the skin editor's project): the `.acs4` layout uncompressed and unscrambled.
/// - `.acs` (AIMP 2's `ACSP`): one zlib body of inline entries, Windows bitmaps and `main.ini`
///   (`AIMPSkinArchive+ACSP.swift`).
///
/// Every entry is named as `.acs4` names it, with an extension: `.acs5` names carry none, so one is
/// added from the entry's kind (`AIMPMainForm` → `AIMPMainForm.xml`).
struct AIMPSkinArchive: Sendable {
    enum Format: String, Sendable {
        case acs5, acs4, acs3, project, acsp
    }

    struct Entry: Sendable {
        let name: String
        fileprivate let location: Location
    }

    /// Where an entry's bytes are in `storage`, as offsets from its first byte.
    fileprivate enum Location: Sendable {
        /// Already plain.
        case plain(Range<Int>)
        /// Bytes of an `.acs5` file, still XORed; zlib with this inflated size when packed.
        case scrambled(Range<Int>, inflatedSize: Int?)
    }

    let format: Format
    private(set) var name: String
    private(set) var author: String
    private(set) var about: String
    /// The skin's own preview, a Windows BMP.
    private(set) var preview: Data?
    /// Keyed by lowercased name: AIMP resolves names case-insensitively.
    let entries: [String: Entry]
    /// An AIMP 3.0 or AIMP 2 skin's `main.ini`, read once: its credits, its pictures' layout and its
    /// form all come from it (`AIMPSkinLegacy`). Nil for a skin with form documents.
    private(set) var mainINI: AIMPSkinINI?

    private let storage: Data
    private let key: [UInt8]

    /// An AIMP 3.0 or AIMP 2 skin: no form documents; its form is read from `main.ini` (`AIMPSkinLegacy`).
    var isLegacy: Bool { mainINI != nil }

    func entry(_ name: String) -> Entry? { entries[name.lowercased()] }

    /// The entry's plain bytes. Safe from any thread: the archive is immutable.
    func payload(_ entry: Entry) throws -> Data {
        switch entry.location {
        case .plain(let range):
            return storage.subdata(in: (storage.startIndex + range.lowerBound)..<(storage.startIndex + range.upperBound))
        case .scrambled(let range, let inflatedSize):
            var bytes = storage.subdata(in: (storage.startIndex + range.lowerBound)..<(storage.startIndex + range.upperBound))
            bytes.withUnsafeMutableBytes { Self.xor($0, key: key, keyOffset: range.lowerBound) }
            guard let inflatedSize else { return bytes }
            return try AIMPSkinZlib.inflate(bytes, expected: inflatedSize, name: entry.name)
        }
    }

    /// `meta` nil for a container with no metadata block (AIMP 3.0's `.acs3`, AIMP 2's `.acs`): its
    /// credits are `main.ini`'s, its preview `preview.bmp`.
    private init(format: Format, meta: Meta?, entries: [String: Entry], storage: Data, key: [UInt8]) throws {
        self.format = format
        self.entries = entries
        self.storage = storage
        self.key = key
        (name, author, about, preview) = (meta?.name ?? "", meta?.author ?? "", meta?.about ?? "", meta?.preview)
        if entry("AIMPMainForm.xml") == nil, let ini = entry("main.ini") {
            do {
                mainINI = try AIMPSkinINI(utf16: payload(ini), name: ini.name)
            } catch let finding as AIMPSkinFinding {
                throw AIMPSkinFinding(.noMainForm, "No form: \(finding.message)")
            }
        }
        if meta == nil {
            (name, author) = (mainINI?["FILE", "SkinName"] ?? "", mainINI?["FILE", "Author"] ?? "")
            preview = try entry("preview.bmp").map(payload)
        }
    }

    /// An archive of plain entries, each a range of `storage` (AIMP 2's `ACSP` body), credited by
    /// `header` when it names the skin, else by `main.ini`.
    init(acsp entries: [(name: String, range: Range<Int>)], header: (name: String, author: String), storage: Data) throws {
        var table: [String: Entry] = [:]
        for entry in entries { table[entry.name.lowercased()] = Entry(name: entry.name, location: .plain(entry.range)) }
        try self.init(format: .acsp, meta: nil, entries: table, storage: storage, key: [])
        if !header.name.isEmpty { (name, author) = header }
    }

    // MARK: - Reading

    static func read(_ data: Data) throws -> AIMPSkinArchive {
        guard data.count >= 16 else {
            throw AIMPSkinFinding(.notAnArchive, "The file is \(data.count) bytes.")
        }
        switch data.prefix(4) {
        case Data("ACS5".utf8): return try readACS5(data)
        case Data("ACS4".utf8): return try readZlibBody(data, format: .acs4)
        case Data("ACS3".utf8): return try readZlibBody(data, format: .acs3)
        case Data("ACSJ".utf8): return try readProject(data)
        case Data("ACSP".utf8): return try readACSP(data)
        case let magic where magic.prefix(3) == Data("ACS".utf8):
            throw AIMPSkinFinding(.unsupportedFormat, "'\(String(decoding: magic, as: UTF8.self))' skins are not supported.")
        default:
            throw AIMPSkinFinding(.notAnArchive, "No AIMP skin header.")
        }
    }

    /// `.acs5`: magic, u8, u32 engine version, u8, u8 key length, the key, then XORed: the
    /// metadata, a u32 entry count and the entries
    /// `{ name, u8 kind, u32 size, u8 packed, packed ? (u32 packed size, zlib) : bytes }`.
    private static func readACS5(_ data: Data) throws -> AIMPSkinArchive {
        let head = AIMPSkinBytes(data, code: .notAnArchive)
        let keyLength = Int(try head.u8(at: 10))
        guard keyLength > 0, data.count > 11 + keyLength else {
            throw AIMPSkinFinding(.notAnArchive, "The key is missing.")
        }
        let key = try head.bytes(at: 11..<(11 + keyLength))
        var reader = AIMPSkinBytes(data, code: .entryOutOfBounds, key: key, plainBefore: 11 + keyLength)
        reader.offset = 11 + keyLength
        let meta = try readMeta(&reader)
        let count = try entryCount(reader.u32())
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            let base = try reader.name()
            let kind = try reader.u8()
            let size = try reader.u32()
            let packed = try reader.u8() != 0
            let stored = packed ? try reader.u32() : size
            guard size <= AIMPSkinPolicy.inflatedBytes else {
                throw AIMPSkinFinding(.inflatedTooLarge, "\(base) declares \(size) bytes.")
            }
            let range = try reader.skip(stored)
            let name = base + extensionForACS5Kind(kind)
            entries[name.lowercased()] = Entry(name: name, location: .scrambled(range, inflatedSize: packed ? size : nil))
        }
        return try AIMPSkinArchive(format: .acs5, meta: meta, entries: entries, storage: data, key: key)
    }

    private static func extensionForACS5Kind(_ kind: UInt8) -> String {
        switch kind {
        case 1: return ".img"
        case 2: return ".imageset.xml"
        case 3: return ".xml"
        case 4: return ".ttf"
        case 6: return ".lng"
        case 7: return ".fsxml"
        default: return ".kind\(kind)"
        }
    }

    /// `.acs4` and `.acs3`: a header, then `3SCA` XORed with the 4-byte key (byte `i` of the file
    /// takes key byte `i % 4`), which gives the key away. Then, except in AIMP 3.0's `.acs3`, a plain
    /// u32 metadata length and the XORed metadata. Then the body: `.acs4` a plain u32 inflated size
    /// first; one XORed zlib stream `{ u32 count, count × { name, u32 offset, u32 size }, blob }`.
    ///
    /// The header is magic and a u8 kind: `.acs4` 0, a u32 engine version (450) and the marker at 9;
    /// `.acs3` 6 the same (350); `.acs3` 3 and 5 the marker at 5; `.acs3` 1 and 2 (AIMP 3.0) the marker
    /// at 5 with the body right after it, and the metadata in `main.ini` and `preview.bmp`.
    private static func readZlibBody(_ data: Data, format: Format) throws -> AIMPSkinArchive {
        let head = AIMPSkinBytes(data, code: .notAnArchive)
        let kind = try head.u8(at: 4)
        let marker: Int
        let hasMeta: Bool
        switch (format, kind) {
        case (.acs4, _), (.acs3, 6): (marker, hasMeta) = (9, true)
        case (.acs3, 3), (.acs3, 5): (marker, hasMeta) = (5, true)
        case (.acs3, 1), (.acs3, 2): (marker, hasMeta) = (5, false)
        default: throw AIMPSkinFinding(.unsupportedFormat, "An .\(format.rawValue) header of kind \(kind) is not supported.")
        }
        var key = [UInt8](repeating: 0, count: 4)
        for (i, c) in "3SCA".utf8.enumerated() {
            key[(marker + i) % 4] = try head.u8(at: marker + i) ^ c
        }
        var meta: Meta?
        var body = marker + 4
        var inflatedSize: Int?
        if hasMeta {
            var reader = AIMPSkinBytes(data, code: .entryOutOfBounds, key: key, plainBefore: body + 4)
            reader.offset = body
            meta = try readMeta(&reader)
            body = reader.offset
            if format == .acs4 {
                inflatedSize = try AIMPSkinBytes(data, code: .entryOutOfBounds).u32(at: body)
                body += 4
            }
        }
        guard body + 2 < data.count else {
            throw AIMPSkinFinding(.notAnArchive, "The .\(format.rawValue) body is missing.")
        }
        var zlib = data.subdata(in: (data.startIndex + body)..<data.endIndex)
        zlib.withUnsafeMutableBytes { xor($0, key: key, keyOffset: body) }
        let inflated = try AIMPSkinZlib.inflate(zlib, expected: inflatedSize, name: "the .\(format.rawValue) body", notZlib: .notAnArchive)
        return try archive(format, meta: meta, body: inflated)
    }

    /// XORs `bytes` with `key`, byte `i` taking key byte `(keyOffset + i) % key.count`. Eight bytes at
    /// a time against the key repeated to a whole number of words: skins run to hundreds of
    /// megabytes, and a byte at a time this was most of a load (and of the AIMP tests).
    static func xor(_ bytes: UnsafeMutableRawBufferPointer, key: [UInt8], keyOffset: Int) {
        guard !key.isEmpty, let base = bytes.baseAddress else { return }
        // The key from the first byte's phase, repeated to 8 × key.count bytes: whole words that
        // stay in phase from one word to the next.
        let phase = keyOffset % key.count
        var pattern = [UInt8](repeating: 0, count: key.count * 8)
        for i in pattern.indices { pattern[i] = key[(phase + i) % key.count] }
        let wordsInPattern = pattern.count / 8
        let words = pattern.withUnsafeBytes { raw in (0..<wordsInPattern).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self) } }
        let whole = bytes.count / 8
        var w = 0
        for i in 0..<whole {
            let at = base + i * 8
            at.storeBytes(of: at.loadUnaligned(as: UInt64.self) ^ words[w], as: UInt64.self)
            w += 1
            if w == wordsInPattern { w = 0 }
        }
        let tail = base.assumingMemoryBound(to: UInt8.self)
        for i in (whole * 8)..<bytes.count { tail[i] ^= pattern[i % pattern.count] }
    }

    /// The table of contents and blob of an `.acs4`/`.acs3` zlib body.
    private static func archive(_ format: Format, meta: Meta?, body: Data) throws -> AIMPSkinArchive {
        var toc = AIMPSkinBytes(body, code: .entryOutOfBounds)
        let count = try entryCount(toc.u32())
        var table: [(String, Int, Int)] = []
        for _ in 0..<count {
            let name = try toc.name()
            table.append((name, try toc.u32(), try toc.u32()))
        }
        let blob = toc.offset
        var entries: [String: Entry] = [:]
        for (name, offset, size) in table {
            let (start, overflow) = blob.addingReportingOverflow(offset)
            guard !overflow, start + size <= body.count else {
                throw AIMPSkinFinding(.entryOutOfBounds, "\(name) lies past the end of the body.")
            }
            entries[name.lowercased()] = Entry(name: name, location: .plain(start..<(start + size)))
        }
        return try AIMPSkinArchive(format: format, meta: meta, entries: entries, storage: body, key: [])
    }

    /// `.acs4proj`: the `.acs4` header (the marker unscrambled), the metadata, then a u32 count and
    /// the entries inline as `{ name, u32 size, bytes }`, nothing scrambled or compressed.
    private static func readProject(_ data: Data) throws -> AIMPSkinArchive {
        var reader = AIMPSkinBytes(data, code: .entryOutOfBounds)
        reader.offset = 13
        let meta = try readMeta(&reader)
        let count = try entryCount(reader.u32())
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            let name = try reader.name()
            let range = try reader.skip(try reader.u32())
            entries[name.lowercased()] = Entry(name: name, location: .plain(range))
        }
        return try AIMPSkinArchive(format: .project, meta: meta, entries: entries, storage: data, key: [])
    }

    /// An entry count, within `AIMPSkinPolicy.entries` (AM0003).
    static func entryCount(_ count: Int) throws -> Int {
        guard count <= AIMPSkinPolicy.entries else {
            throw AIMPSkinFinding(.tooManyEntries, "\(count) entries, more than \(AIMPSkinPolicy.entries).")
        }
        return count
    }

    private struct Meta {
        let name: String
        let author: String
        let about: String
        let preview: Data?
    }

    /// A u32 length, then that many bytes: three strings (name, author, description), a u8 preview
    /// flag and the preview bitmap. The bitmap's own file header can overstate its size (by about a
    /// kilobyte in many `.acs3`), so it ends where the block does. Leaves the reader after the block.
    private static func readMeta(_ reader: inout AIMPSkinBytes) throws -> Meta {
        let block = try reader.skip(try reader.u32())
        var meta = AIMPSkinBytes(reader.data, code: reader.code, key: reader.key, plainBefore: reader.plainBefore, end: block.upperBound)
        meta.offset = block.lowerBound
        let name = try meta.name()
        let author = try meta.name()
        let about = try meta.name()
        var preview: Data?
        if try meta.u8() != 0, try meta.peek(2) == [0x42, 0x4D] {
            let size = try meta.u32(at: meta.offset + 2)
            preview = Data(try meta.bytes(at: meta.offset..<min(meta.offset + size, block.upperBound)))
        }
        return Meta(name: name, author: author, about: about, preview: preview)
    }
}

private extension AIMPSkinBytes {
    /// An entry or credit name: a u16 character count and UTF-16LE text.
    mutating func name() throws -> String { try utf16(units: try u16()) }
}
