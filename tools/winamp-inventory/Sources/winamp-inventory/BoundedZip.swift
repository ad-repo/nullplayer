import Foundation
import Compression

/// Minimal, read-only ZIP reader with hard resource caps — the Phase-0B stand-in
/// for the production bounded `WalArchive` (Phase 2). It treats the archive as
/// untrusted: it refuses path traversal, absolute paths, and symlink entries, and
/// aborts if any of the declared limits are exceeded.
struct ZipLimits {
    var maxEntries = 5_000
    var maxEntryUncompressed = 64 * 1024 * 1024      // 64 MB per file
    var maxTotalUncompressed = 512 * 1024 * 1024     // 512 MB total
}

enum ZipError: Error, CustomStringConvertible {
    case notAZip
    case tooManyEntries(Int)
    case entryTooLarge(name: String, size: Int)
    case totalTooLarge(Int)
    case traversal(String)
    case corrupt(String)
    case inflateFailed(String)

    var description: String {
        switch self {
        case .notAZip: return "not a ZIP archive (no end-of-central-directory record found)"
        case .tooManyEntries(let n): return "archive declares \(n) entries, exceeding the cap"
        case .entryTooLarge(let name, let size): return "entry '\(name)' uncompressed size \(size) exceeds per-entry cap"
        case .totalTooLarge(let n): return "total uncompressed size \(n) exceeds cap"
        case .traversal(let p): return "unsafe entry path rejected: '\(p)'"
        case .corrupt(let m): return "corrupt archive: \(m)"
        case .inflateFailed(let n): return "inflate failed for '\(n)'"
        }
    }
}

struct ZipEntry {
    let name: String
    let compressedSize: Int
    let uncompressedSize: Int
    let method: UInt16      // 0 = stored, 8 = deflate
    let localHeaderOffset: Int
}

final class BoundedZip {
    private let data: Data
    let limits: ZipLimits
    private(set) var entries: [ZipEntry] = []

    init(url: URL, limits: ZipLimits = ZipLimits()) throws {
        self.data = try Data(contentsOf: url)
        self.limits = limits
        try readCentralDirectory()
    }

    private func u16(_ off: Int) -> UInt16 {
        UInt16(data[off]) | (UInt16(data[off + 1]) << 8)
    }
    private func u32(_ off: Int) -> UInt32 {
        UInt32(data[off]) | (UInt32(data[off + 1]) << 8) |
        (UInt32(data[off + 2]) << 16) | (UInt32(data[off + 3]) << 24)
    }

    private func readCentralDirectory() throws {
        // Locate the End Of Central Directory record (sig 0x06054b50) by scanning
        // backwards, allowing for a trailing comment.
        let sig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        var eocd = -1
        let minStart = max(0, data.count - 65_557)
        var i = data.count - 4
        while i >= minStart {
            if data[i] == sig[0] && data[i+1] == sig[1] && data[i+2] == sig[2] && data[i+3] == sig[3] {
                eocd = i; break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let totalEntries = Int(u16(eocd + 10))
        if totalEntries > limits.maxEntries { throw ZipError.tooManyEntries(totalEntries) }
        var cd = Int(u32(eocd + 16))

        var runningTotal = 0
        for _ in 0..<totalEntries {
            guard cd + 46 <= data.count, u32(cd) == 0x02014b50 else {
                throw ZipError.corrupt("bad central directory header")
            }
            let method = u16(cd + 10)
            let compSize = Int(u32(cd + 20))
            let uncompSize = Int(u32(cd + 24))
            let fnLen = Int(u16(cd + 28))
            let extraLen = Int(u16(cd + 30))
            let commentLen = Int(u16(cd + 32))
            let localOff = Int(u32(cd + 42))
            let nameData = data.subdata(in: (cd + 46)..<(cd + 46 + fnLen))
            let name = String(decoding: nameData, as: UTF8.self)

            if uncompSize > limits.maxEntryUncompressed {
                throw ZipError.entryTooLarge(name: name, size: uncompSize)
            }
            runningTotal += uncompSize
            if runningTotal > limits.maxTotalUncompressed {
                throw ZipError.totalTooLarge(runningTotal)
            }
            try rejectUnsafePath(name)

            // Skip directory entries (trailing slash).
            if !name.hasSuffix("/") {
                entries.append(ZipEntry(name: name, compressedSize: compSize,
                                        uncompressedSize: uncompSize, method: method,
                                        localHeaderOffset: localOff))
            }
            cd += 46 + fnLen + extraLen + commentLen
        }
    }

    private func rejectUnsafePath(_ name: String) throws {
        if name.hasPrefix("/") || name.hasPrefix("\\") || name.contains(":") {
            throw ZipError.traversal(name)
        }
        let norm = name.replacingOccurrences(of: "\\", with: "/")
        for comp in norm.split(separator: "/") where comp == ".." {
            throw ZipError.traversal(name)
        }
    }

    /// Read + inflate a single entry's bytes on demand, re-checking the size cap
    /// against what the local header/stream actually produces.
    func read(_ entry: ZipEntry) throws -> Data {
        var lo = entry.localHeaderOffset
        guard lo + 30 <= data.count, u32(lo) == 0x04034b50 else {
            throw ZipError.corrupt("bad local header for \(entry.name)")
        }
        let fnLen = Int(u16(lo + 26))
        let extraLen = Int(u16(lo + 28))
        lo += 30 + fnLen + extraLen
        let comp = data.subdata(in: lo..<(lo + entry.compressedSize))
        if entry.method == 0 { return comp }               // stored
        guard entry.method == 8 else {                     // only deflate supported
            throw ZipError.inflateFailed(entry.name + " (method \(entry.method))")
        }
        return try inflate(comp, expected: entry.uncompressedSize, name: entry.name)
    }

    private func inflate(_ input: Data, expected: Int, name: String) throws -> Data {
        let cap = max(expected, 64)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let produced = input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(dst, cap, base, input.count, nil, COMPRESSION_ZLIB)
        }
        guard produced > 0 else { throw ZipError.inflateFailed(name) }
        return Data(bytes: dst, count: produced)
    }
}
