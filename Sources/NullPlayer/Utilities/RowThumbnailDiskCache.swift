import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Both renditions of each library row image on disk, named by a hash of the source key:
/// `<hash>.png` (thumbnail) and `<hash>.jpg` (preview). An entry older than `maxAge` is a miss, so
/// art changed on a server or in a file's tags is picked up within that window; `prune` keeps the
/// folder under `maxBytes`, oldest first. Every method does file I/O: call it off the main thread.
struct RowThumbnailDiskCache: Sendable {
    static let standard = RowThumbnailDiskCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NullPlayer/RowThumbnails", isDirectory: true))

    let directory: URL
    var maxAge: TimeInterval = 30 * 24 * 60 * 60
    var maxBytes = 300 * 1024 * 1024
    var pruneTargetBytes = 200 * 1024 * 1024

    func read(_ key: String) -> LibraryRowThumbnails.Renditions? {
        let files = files(for: key)
        guard isFresh(files.thumbnail), let thumbnail = decode(files.thumbnail),
              let preview = decode(files.preview) else { return nil }
        return LibraryRowThumbnails.Renditions(thumbnail: thumbnail, preview: preview)
    }

    func readPreview(_ key: String) -> CGImage? {
        let file = files(for: key).preview
        return isFresh(file) ? decode(file) : nil
    }

    func write(_ renditions: LibraryRowThumbnails.Renditions, key: String) {
        let files = files(for: key)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        encode(renditions.preview, to: files.preview, type: .jpeg, quality: 0.85)
        encode(renditions.thumbnail, to: files.thumbnail, type: .png, quality: nil)
    }

    func prune() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return
        }
        let entries = urls.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) where total > pruneTargetBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private func files(for key: String) -> (thumbnail: URL, preview: URL) {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return (directory.appendingPathComponent("\(name).png"), directory.appendingPathComponent("\(name).jpg"))
    }

    private func isFresh(_ url: URL) -> Bool {
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return false
        }
        return Date().timeIntervalSince(date) < maxAge
    }

    private func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func encode(_ image: CGImage, to url: URL, type: UTType, quality: CGFloat?) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary })
        CGImageDestinationFinalize(destination)
    }
}
