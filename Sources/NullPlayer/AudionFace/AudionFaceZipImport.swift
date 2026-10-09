import Foundation
import ZIPFoundation

/// A `.zip` of one or more face folders — Panic's distribution format — unpacked into a folder the
/// caller owns, so each face then goes through `AudionFaceLoader` like any other. Every bound is
/// checked from the central directory before a byte is inflated, and inflation is held to each
/// entry's declared size and CRC. Shares nothing with `WMPArchive`; families stay isolated.
enum AudionFaceZipImport {
    /// Unpacks `zip` into `destination` and returns every folder it unpacked an `index.json` into.
    /// Off the main thread, like the loader. A zip its central directory rejects writes nothing; one
    /// that fails a CRC can leave part of itself, so discard what it wrote on a throw.
    static func unpack(_ zip: URL, into destination: URL,
                       limits: AudionFaceZipLimits = .production) throws -> [URL] {
        let archive: Archive
        do {
            archive = try Archive(url: zip, accessMode: .read)
        } catch {
            throw AudionFaceFinding(.unreadableZip, "'\(zip.lastPathComponent)' is not a readable zip.")
        }

        var admitted: [(entry: Entry, target: URL)] = []
        var count = 0
        var total: UInt64 = 0
        for entry in archive {
            count += 1
            guard count <= limits.entries else {
                throw AudionFaceFinding(.zipOverLimit, "More than \(limits.entries) entries.")
            }
            // Finder's AppleDouble shadow tree carries no face data; it is never written out.
            guard !entry.path.hasPrefix("__MACOSX/") else { continue }
            guard entry.type != .symlink else {
                throw AudionFaceFinding(.pathEscape, "'\(entry.path)' is a symbolic link.")
            }
            let components = try safeComponents(entry.path)
            guard entry.type == .file else { continue }
            let size = entry.uncompressedSize
            guard size <= limits.entryBytes else {
                throw AudionFaceFinding(.zipOverLimit, "'\(entry.path)' expands to \(size) bytes.")
            }
            guard size <= limits.totalBytes - total else {
                throw AudionFaceFinding(.zipOverLimit, "The zip expands past \(limits.totalBytes) bytes.")
            }
            total += size
            // Below the floor a ratio measures how plain a file is, not how hostile; above it the
            // ratio is the bomb test (`.wmz` Amendment 1).
            let ratio = Double(size) / Double(max(entry.compressedSize, 1))
            if size > limits.ratioFloorBytes, ratio > Double(limits.ratio) {
                throw AudionFaceFinding(.zipOverLimit, "'\(entry.path)' expands \(Int(ratio)):1, past \(limits.ratio):1.")
            }
            admitted.append((entry, components.reduce(destination) { $0.appendingPathComponent($1) }))
        }

        for (entry, target) in admitted {
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: target.path, contents: nil)
                let output = try FileHandle(forWritingTo: target)
                defer { try? output.close() }
                var written: UInt64 = 0
                let checksum = try archive.extract(entry) { chunk in
                    written += UInt64(chunk.count)
                    guard written <= entry.uncompressedSize else {
                        throw AudionFaceFinding(.zipOverLimit, "'\(entry.path)' inflates past its declared size.")
                    }
                    try output.write(contentsOf: chunk)
                }
                guard checksum == entry.checksum, written == entry.uncompressedSize else {
                    throw AudionFaceFinding(.unreadableZip, "'\(entry.path)' fails its CRC or size check.")
                }
            } catch let finding as AudionFaceFinding {
                throw finding
            } catch {
                throw AudionFaceFinding(.unreadableZip, "'\(entry.path)' could not be unpacked: \(error.localizedDescription)")
            }
        }

        let faces = admitted.map(\.target).filter { $0.lastPathComponent.lowercased() == "index.json" }
        return Set(faces.map { $0.deletingLastPathComponent() }).sorted { $0.path < $1.path }
    }

    /// An entry's path as components that stay inside the destination, or `AUD0006`.
    private static func safeComponents(_ path: String) throws -> [String] {
        let components = path.split(separator: "/").map(String.init)
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.utf8.contains(0),
              !components.contains(".."), !components.contains("."), !components.isEmpty else {
            throw AudionFaceFinding(.pathEscape, "'\(path)' would land outside the import folder.")
        }
        return components
    }
}
