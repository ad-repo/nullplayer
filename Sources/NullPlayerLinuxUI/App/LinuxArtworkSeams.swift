#if os(Linux)
import Foundation
import NullPlayerCore

struct LinuxArtworkImage: Sendable {
    let data: Data
    let sourceURL: URL
}

protocol LinuxArtworkLoading: AnyObject {
    func loadArtwork(for track: Track) -> LinuxArtworkImage?
    func clearCache()
}

final class LinuxArtworkLoader: LinuxArtworkLoading {
    private let cache = NSCache<NSString, NSData>()

    func loadArtwork(for track: Track) -> LinuxArtworkImage? {
        let key = track.url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return LinuxArtworkImage(data: Data(referencing: cached), sourceURL: track.url)
        }

        // Linux-safe default behavior for now: try sidecar image next to the media file.
        guard track.url.isFileURL else { return nil }
        guard let sidecar = sidecarArtworkURL(for: track.url),
              let data = try? Data(contentsOf: sidecar) else {
            return nil
        }

        cache.setObject(data as NSData, forKey: key)
        return LinuxArtworkImage(data: data, sourceURL: sidecar)
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    private func sidecarArtworkURL(for mediaURL: URL) -> URL? {
        let directory = mediaURL.deletingLastPathComponent()
        let basename = mediaURL.deletingPathExtension().lastPathComponent
        let candidates = ["\(basename).jpg", "\(basename).jpeg", "\(basename).png", "cover.jpg", "folder.jpg"]
        for candidate in candidates {
            let url = directory.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
#endif
