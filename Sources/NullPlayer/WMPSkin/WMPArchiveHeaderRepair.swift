import Foundation

/// Repairs the one thing four of the 180 corpus archives get wrong about being ZIPs.
///
/// `bruteforce`, `Need_for_Speed_Underground`, `QuantumRedshiftWMPSkin` and `SplinterCellWMPSkin`
/// are ordinary deflate ZIPs — valid end-of-central-directory record, valid central directory,
/// every stream intact — except that the four signature bytes of the local file header sitting at
/// file offset 0 read `01 00 01 00` instead of `PK\03\04`. Everything after that signature, in
/// that same header, agrees with the central directory. It is a marker written over the front of
/// the file so it is not recognised as a ZIP by anything that sniffs magic bytes; Windows Media
/// Player reads these skins, and so does `unzip`, because both work from the central directory.
///
/// `ZIPFoundation` does not: its iterator reads each entry's local header through a serialiser
/// that validates the signature, and a `nil` there ends the iteration rather than skipping the
/// entry. Every one of these archives has the damaged header on its *first* central-directory
/// record, so enumeration yielded **zero** entries and the loader reported `WMP0021` — "no `.wms`
/// at the root" — for archives whose `.wms` is at the root. This is not a wrapper-layout rule that
/// is too narrow; it is the archive reader never seeing a single file.
///
/// The repair is deliberately the smallest one that can be honest: walk the central directory,
/// and rewrite a local header's signature **only** when the header at that offset already agrees
/// with the central directory record that points at it — same file-name length, same file-name
/// bytes. A run of arbitrary data can never be promoted into an entry that way, and an archive
/// that needs no repair is handed straight back to the file-backed reader untouched.
enum WMPArchiveHeaderRepair {
    private static let localFileHeaderSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
    private static let centralDirectorySignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
    private static let endOfCentralDirectorySignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
    private static let centralDirectoryRecordSize = 46
    private static let localFileHeaderSize = 30
    private static let endOfCentralDirectoryRecordSize = 22
    private static let maximumArchiveComment = 65_535

    /// Repaired archive bytes, or `nil` when the file is already readable as it stands — which is
    /// every archive whose first four bytes are a local file header signature, so the common case
    /// pays one 4-byte read and never loads the file.
    static func repairedArchiveData(at url: URL, limits: WMPArchiveLimits) throws -> Data? {
        guard try leadsWithSomethingOtherThanALocalHeader(at: url) else { return nil }

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? nil
        if let size, size > limits.maximumRepairableArchiveSize {
            throw WMPFailure(WMPDiagnostic(.invalidArchive,
                "'\(url.lastPathComponent)' does not begin with a ZIP local file header and is too "
                + "large (\(size) bytes) to inspect within the \(limits.maximumRepairableArchiveSize)-byte bound."))
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw WMPFailure(WMPDiagnostic(.invalidArchive,
                "Unable to read '\(url.lastPathComponent)': \(error.localizedDescription)"))
        }

        guard let directory = locateCentralDirectory(in: data) else { return nil }
        let damaged = damagedLocalHeaderOffsets(in: data, directory: directory)
        guard !damaged.isEmpty else { return nil }

        var repaired = data
        for offset in damaged {
            let start = repaired.startIndex + offset
            repaired.replaceSubrange(start ..< (start + 4), with: localFileHeaderSignature)
        }
        return repaired
    }

    // MARK: - Reading

    private static func leadsWithSomethingOtherThanALocalHeader(at url: URL) throws -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        guard head.count == 4 else { return false }
        return Array(head) != localFileHeaderSignature
    }

    private struct CentralDirectory {
        let offset: Int
        let entryCount: Int
    }

    /// The end-of-central-directory record, then the central directory it points at. Anything that
    /// does not check out — no record, a ZIP64 archive, a directory that is not where the record
    /// says it is — returns `nil` so the file takes the ordinary path and fails, or loads, on its
    /// own terms.
    private static func locateCentralDirectory(in data: Data) -> CentralDirectory? {
        let count = data.count
        guard count >= endOfCentralDirectoryRecordSize else { return nil }
        let earliest = max(0, count - endOfCentralDirectoryRecordSize - maximumArchiveComment)
        var record: Int?
        var scan = count - endOfCentralDirectoryRecordSize
        while scan >= earliest {
            if signature(in: data, at: scan) == endOfCentralDirectorySignature {
                record = scan
                break
            }
            scan -= 1
        }
        guard let record else { return nil }

        let entryCount = u16(data, record + 10)
        let directoryOffset = u32(data, record + 16)
        // ZIP64 parks its real values elsewhere; leave those archives entirely alone.
        guard entryCount != 0xFFFF, directoryOffset != 0xFFFF_FFFF else { return nil }
        let offset = Int(directoryOffset)
        guard offset >= 0, offset + centralDirectoryRecordSize <= count,
              signature(in: data, at: offset) == centralDirectorySignature else { return nil }
        return CentralDirectory(offset: offset, entryCount: entryCount)
    }

    /// Offsets of local file headers whose signature is wrong but whose file name still matches the
    /// central directory record pointing at them. That agreement is the whole warrant for writing.
    private static func damagedLocalHeaderOffsets(in data: Data, directory: CentralDirectory) -> [Int] {
        var offsets: [Int] = []
        var cursor = directory.offset
        let count = data.count
        for _ in 0 ..< directory.entryCount {
            guard cursor + centralDirectoryRecordSize <= count,
                  signature(in: data, at: cursor) == centralDirectorySignature else { break }
            let nameLength = u16(data, cursor + 28)
            let extraLength = u16(data, cursor + 30)
            let commentLength = u16(data, cursor + 32)
            let localOffset = Int(u32(data, cursor + 42))
            let nameStart = cursor + centralDirectoryRecordSize
            guard nameStart + nameLength <= count else { break }
            let name = bytes(in: data, at: nameStart, count: nameLength)

            if localOffset >= 0, localOffset + localFileHeaderSize + nameLength <= count,
               signature(in: data, at: localOffset) != localFileHeaderSignature,
               u16(data, localOffset + 26) == nameLength,
               bytes(in: data, at: localOffset + localFileHeaderSize, count: nameLength) == name {
                offsets.append(localOffset)
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return offsets
    }

    // MARK: - Little-endian reads

    /// Every read is expressed against `startIndex`; slicing `Data` preserves the original indices.
    private static func byte(_ data: Data, _ offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }

    private static func signature(in data: Data, at offset: Int) -> [UInt8] {
        guard offset >= 0, offset + 4 <= data.count else { return [] }
        return bytes(in: data, at: offset, count: 4)
    }

    private static func bytes(in data: Data, at offset: Int, count: Int) -> [UInt8] {
        let start = data.startIndex + offset
        return Array(data[start ..< (start + count)])
    }

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        guard offset >= 0, offset + 2 <= data.count else { return -1 }
        return Int(byte(data, offset)) | Int(byte(data, offset + 1)) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return .max }
        return UInt32(byte(data, offset))
            | UInt32(byte(data, offset + 1)) << 8
            | UInt32(byte(data, offset + 2)) << 16
            | UInt32(byte(data, offset + 3)) << 24
    }
}
