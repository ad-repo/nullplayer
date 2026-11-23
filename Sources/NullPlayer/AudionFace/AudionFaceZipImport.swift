import Foundation
import ZIPFoundation

/// A `.zip` of one or more face folders — Panic's distribution format — unpacked into a folder the
/// caller owns, so each face then goes through `AudionFaceLoader` like any other. The bounds and the
/// CRC are `SkinZipExtraction`'s; which entries a face takes, and where, are Audion's.
enum AudionFaceZipImport {
    /// Unpacks `zip` into `destination` and returns every folder it unpacked an `index.json` into.
    /// Off the main thread, like the loader. A zip its central directory rejects writes nothing; one
    /// that fails a CRC can leave part of itself, so discard what it wrote on a throw.
    static func unpack(_ zip: URL, into destination: URL,
                       limits: SkinZipLimits = .audionFaces) throws -> [URL] {
        let archive: Archive
        do {
            archive = try Archive(url: zip, accessMode: .read)
        } catch {
            throw AudionFaceFinding(.unreadableZip, "'\(zip.lastPathComponent)' is not a readable zip.")
        }

        let written: [URL]
        do {
            written = try SkinZipExtraction.extract(archive, limits: limits) { entry in
                // Finder's AppleDouble shadow tree carries no face data; it is never written out.
                guard !entry.path.hasPrefix("__MACOSX/") else { return nil }
                guard entry.type != .symlink else {
                    throw AudionFaceFinding(.pathEscape, "'\(entry.path)' is a symbolic link.")
                }
                let components = try safeComponents(entry.path)
                guard entry.type == .file else { return nil }
                return components.reduce(destination) { $0.appendingPathComponent($1) }
            }
        } catch let rejection as SkinZipExtraction.Rejection {
            throw finding(rejection)
        }

        let faces = written.filter { $0.lastPathComponent.lowercased() == "index.json" }
        return Set(faces.map { $0.deletingLastPathComponent() }).sorted { $0.path < $1.path }
    }

    /// `AUD0010` for a bound, `AUD0014` for an entry that cannot be unpacked.
    private static func finding(_ rejection: SkinZipExtraction.Rejection) -> AudionFaceFinding {
        switch rejection {
        case let .tooManyEntries(limit):
            return AudionFaceFinding(.zipOverLimit, "More than \(limit) entries.")
        case let .entryTooLarge(path, bytes, _):
            return AudionFaceFinding(.zipOverLimit, "'\(path)' expands to \(bytes) bytes.")
        case let .totalTooLarge(limit):
            return AudionFaceFinding(.zipOverLimit, "The zip expands past \(limit) bytes.")
        case let .compressionRatio(path, ratio, limit):
            return AudionFaceFinding(.zipOverLimit, "'\(path)' expands \(ratio):1, past \(limit):1.")
        case let .inflatesPastDeclaredSize(path):
            return AudionFaceFinding(.zipOverLimit, "'\(path)' inflates past its declared size.")
        case let .failsCRCOrSize(path):
            return AudionFaceFinding(.unreadableZip, "'\(path)' fails its CRC or size check.")
        case let .unpackFailed(path, underlying):
            return AudionFaceFinding(.unreadableZip, "'\(path)' could not be unpacked: \(underlying.localizedDescription)")
        }
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
