import Compression
import Foundation

/// The one reader of AIMP's binary layouts: the containers, `SXML`/`BXML` documents, `ACLIMG32` and
/// `ASEIMG32` images and Windows bitmap headers (`reference/format.md`). Little-endian, every read
/// bounds-checked against `end`; a read past it throws `code`, the format's own finding.
///
/// Positions are offsets from the first byte, whatever the `Data`'s indices. With a `key`, bytes at
/// or past `plainBefore` are XORed with it, byte `i` taking key byte `i % key.count` (`.acs5` and
/// `.acs4` scrambling); the bytes stay as stored, so a scrambled file is never copied whole.
struct AIMPSkinBytes {
    let data: Data
    let code: AIMPSkinDiagnosticCode
    let key: [UInt8]
    let plainBefore: Int
    /// One past the last byte a read may reach.
    let end: Int
    var offset = 0

    init(_ data: Data, code: AIMPSkinDiagnosticCode, key: [UInt8] = [], plainBefore: Int = .max, end: Int? = nil) {
        self.data = data
        self.code = code
        self.key = key
        self.plainBefore = plainBefore
        self.end = min(end ?? data.count, data.count)
    }

    var remaining: Int { end - offset }

    /// `count` bytes from `at`, or the finding.
    func check(_ at: Int, _ count: Int) throws -> Range<Int> {
        let (stop, overflow) = at.addingReportingOverflow(count)
        guard at >= 0, count >= 0, !overflow, stop <= end else {
            throw AIMPSkinFinding(code, "\(count) bytes at \(at) run past \(end).")
        }
        return at..<stop
    }

    /// The byte at `at`, unscrambled. Unchecked: `at` comes from `check`.
    private func byte(_ at: Int) -> UInt8 {
        let raw = data[data.startIndex + at]
        return key.isEmpty || at < plainBefore ? raw : raw ^ key[at % key.count]
    }

    func bytes(at range: Range<Int>) throws -> [UInt8] {
        let range = try check(range.lowerBound, range.count)
        if key.isEmpty { return [UInt8](data[(data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)]) }
        return range.map(byte)
    }

    func u8(at: Int) throws -> UInt8 { byte(try check(at, 1).lowerBound) }

    func u16(at: Int) throws -> Int {
        let at = try check(at, 2).lowerBound
        return Int(byte(at)) | Int(byte(at + 1)) << 8
    }

    func u32(at: Int) throws -> Int {
        let at = try check(at, 4).lowerBound
        return Int(byte(at)) | Int(byte(at + 1)) << 8 | Int(byte(at + 2)) << 16 | Int(byte(at + 3)) << 24
    }

    /// The next `count` bytes' range, the cursor moved past them.
    mutating func skip(_ count: Int) throws -> Range<Int> {
        let range = try check(offset, count)
        offset = range.upperBound
        return range
    }

    func peek(_ count: Int) throws -> [UInt8] { try bytes(at: offset..<(offset + count)) }

    mutating func bytes(_ count: Int) throws -> [UInt8] { try bytes(at: try skip(count)) }

    mutating func u8() throws -> UInt8 { try u8(at: try skip(1).lowerBound) }

    mutating func u16() throws -> Int { try u16(at: try skip(2).lowerBound) }

    mutating func u32() throws -> Int { try u32(at: try skip(4).lowerBound) }

    /// A LEB128 varint (`SXML`).
    mutating func varint() throws -> Int {
        var value = 0
        var shift = 0
        while true {
            guard shift < 63 else { throw AIMPSkinFinding(code, "A varint at \(offset) runs on.") }
            let byte = try u8()
            value |= Int(byte & 0x7F) << shift
            shift += 7
            if byte < 0x80 { return value }
        }
    }

    /// `units` UTF-16LE code units.
    mutating func utf16(units: Int) throws -> String {
        guard units >= 0, units <= end else { throw AIMPSkinFinding(code, "\(units) characters at \(offset) run past \(end).") }
        return String(bytes: try bytes(units * 2), encoding: .utf16LittleEndian) ?? ""
    }

    /// `count` bytes as text (`BXML` names, `SXML`'s name table, `ACLIMG32` chunk tags).
    mutating func ascii(_ count: Int) throws -> String { String(decoding: try bytes(count), as: UTF8.self) }
}

/// A zlib stream (a 2-byte header, then raw DEFLATE) inflated, the one inflater of every compressed
/// thing an AIMP skin holds: `.acs5` entries, an `.acs4`/`.acs3` body, AIMP 2's `ACSP` body,
/// `ACLIMG32`'s `bitz` pixels.
enum AIMPSkinZlib {
    /// Inflated, at most `expected` bytes when the container declares a size (and exactly that many)
    /// and at most `AIMPSkinPolicy.inflatedBytes`. A header that is not zlib's throws `notZlib`;
    /// a stream that does not inflate, `AM0008`.
    static func inflate(_ zlib: Data, expected: Int?, name: String, notZlib: AIMPSkinDiagnosticCode = .entryUnreadable) throws -> Data {
        let header = [UInt8](zlib.prefix(2))
        guard header.count == 2, header[0] & 0x0F == 8, (Int(header[0]) << 8 | Int(header[1])) % 31 == 0 else {
            throw AIMPSkinFinding(notZlib, "\(name) is not a zlib stream.")
        }
        return try deflated(zlib.dropFirst(2), expected: expected, name: name)
    }

    private static func deflated(_ input: Data, expected: Int?, name: String) throws -> Data {
        let limit = min(expected ?? AIMPSkinPolicy.inflatedBytes, AIMPSkinPolicy.inflatedBytes)
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name): no inflater.")
        }
        defer { compression_stream_destroy(stream) }
        let chunk = 1 << 16
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var output = Data()
        output.reserveCapacity(expected.map { min($0, limit) } ?? chunk)
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw AIMPSkinFinding(.entryUnreadable, "\(name) is empty.")
            }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = raw.count
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = chunk
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunk - stream.pointee.dst_size
                guard output.count + produced <= limit else {
                    throw AIMPSkinFinding(.inflatedTooLarge, "\(name) inflates past \(limit) bytes.")
                }
                output.append(buffer, count: produced)
                switch status {
                case COMPRESSION_STATUS_END:
                    return
                case COMPRESSION_STATUS_OK where produced > 0 || stream.pointee.src_size > 0:
                    continue
                default:
                    throw AIMPSkinFinding(.entryUnreadable, "\(name) does not inflate.")
                }
            }
        }
        if let expected, output.count != expected {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) inflates to \(output.count) bytes, not \(expected).")
        }
        return output
    }
}
