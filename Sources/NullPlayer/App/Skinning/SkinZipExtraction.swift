import Foundation
import ZIPFoundation

/// What a `.zip` of skins is held to before a byte of it is written: absolute bounds on entries and
/// expanded bytes, and a compression ratio that applies only above a size floor (`.wmz` Amendment 1).
/// Each family that imports zips sets its own values beside its policy.
struct SkinZipLimits {
    /// Every entry of the zip, taken or not.
    var entries: Int
    /// Everything taken from it.
    var totalBytes: UInt64
    /// One entry taken.
    var entryBytes: UInt64
    /// Past `ratioFloorBytes`, an entry that expands more than this many times is a bomb. Below the
    /// floor a ratio measures how plain a file is, not how hostile.
    var ratio: UInt64
    var ratioFloorBytes: UInt64
}

/// A skin `.zip` unpacked into a folder the caller owns, the entries it wants and nowhere else. Every
/// bound is checked from the central directory before a byte is inflated, and each entry is held to
/// its declared size and CRC as it is written. Off the main thread. A zip its central directory
/// rejects writes nothing; one that fails an entry part-way can leave files, which the caller discards.
/// A family maps `Rejection` to its own findings.
enum SkinZipExtraction {
    enum Rejection: Error {
        case tooManyEntries(limit: Int)
        case entryTooLarge(path: String, bytes: UInt64, limit: UInt64)
        case totalTooLarge(limit: UInt64)
        case compressionRatio(path: String, ratio: Int, limit: UInt64)
        case inflatesPastDeclaredSize(path: String)
        case failsCRCOrSize(path: String)
        /// Writing the entry failed for another reason (the file system, the archive).
        case unpackFailed(path: String, underlying: Error)
    }

    /// Unpacks every entry `target` gives a destination for (nil skips it; it may throw to refuse the
    /// zip) and returns those destinations in zip order. `target` sees each entry before its sizes are
    /// checked.
    static func extract(_ archive: Archive, limits: SkinZipLimits, target: (Entry) throws -> URL?) throws -> [URL] {
        var admitted: [(entry: Entry, target: URL)] = []
        var count = 0
        var total: UInt64 = 0
        for entry in archive {
            count += 1
            guard count <= limits.entries else { throw Rejection.tooManyEntries(limit: limits.entries) }
            guard let destination = try target(entry) else { continue }
            let size = entry.uncompressedSize
            guard size <= limits.entryBytes else {
                throw Rejection.entryTooLarge(path: entry.path, bytes: size, limit: limits.entryBytes)
            }
            guard size <= limits.totalBytes - total else { throw Rejection.totalTooLarge(limit: limits.totalBytes) }
            total += size
            let ratio = Double(size) / Double(max(entry.compressedSize, 1))
            if size > limits.ratioFloorBytes, ratio > Double(limits.ratio) {
                throw Rejection.compressionRatio(path: entry.path, ratio: Int(ratio), limit: limits.ratio)
            }
            admitted.append((entry, destination))
        }

        for (entry, destination) in admitted {
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }
                var written: UInt64 = 0
                let checksum = try archive.extract(entry) { chunk in
                    written += UInt64(chunk.count)
                    guard written <= entry.uncompressedSize else { throw Rejection.inflatesPastDeclaredSize(path: entry.path) }
                    try output.write(contentsOf: chunk)
                }
                guard checksum == entry.checksum, written == entry.uncompressedSize else {
                    throw Rejection.failsCRCOrSize(path: entry.path)
                }
            } catch let rejection as Rejection {
                throw rejection
            } catch {
                throw Rejection.unpackFailed(path: entry.path, underlying: error)
            }
        }
        return admitted.map(\.target)
    }
}
