import AppKit
import AVFoundation

/// A local file's cover, resolved one way for every view that shows one: the file's embedded art,
/// else the first embedded art among its album's tracks in the library, else a cover image in its
/// folder (`cover.jpg`, `folder.jpg`, `front.jpg`, `album.jpg`). Results, misses included, are
/// cached per file and per album until the library next changes (a scan, a tag edit).
enum LocalArtwork {
    private final class Box {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        NotificationCenter.default.addObserver(forName: MediaLibrary.libraryDidChangeNotification,
                                               object: nil, queue: nil) { _ in cache.removeAllObjects() }
        return cache
    }()
    private static let folderImageNames: Set<String> = ["cover", "folder", "front", "album"]
    private static let folderImageExtensions: Set<String> = ["jpg", "jpeg", "png"]

    /// A file's cover: its own, its album's, or its folder's.
    static func image(for url: URL) async -> NSImage? {
        await cached("file:\(url.path)") {
            if let image = await embeddedImage(in: url) { return image }
            if let albumId = MediaLibraryStore.shared.albumId(containing: url),
               let image = await image(forAlbum: albumId) {
                return image
            }
            return folderImage(in: url.deletingLastPathComponent())
        }
    }

    /// An album's cover: the first of its tracks with embedded art, else a cover image in one of
    /// its tracks' folders. `albumId` is the library's `"albumArtist|album"` key.
    static func image(forAlbum albumId: String) async -> NSImage? {
        await cached("album:\(albumId)") {
            let tracks = MediaLibraryStore.shared.tracksForAlbum(albumId)
            for track in tracks {
                if let image = await embeddedImage(in: track.url) { return image }
            }
            for folder in Set(tracks.map { $0.url.deletingLastPathComponent() }) {
                if let image = folderImage(in: folder) { return image }
            }
            return nil
        }
    }

    /// An artist's cover: the first of the albums they are album artist of that has one.
    static func image(forArtist name: String) async -> NSImage? {
        for album in MediaLibraryStore.shared.albumsForArtist(name) {
            if let image = await image(forAlbum: album.id) { return image }
        }
        return nil
    }

    /// The first picture embedded in a file.
    static func embeddedImage(in url: URL) async -> NSImage? {
        await embeddedImages(in: url).first
    }

    /// Every picture embedded in a file, de-duplicated across the metadata formats that repeat
    /// them: the common metadata, then the ID3 and iTunes atoms.
    static func embeddedImages(in url: URL) async -> [NSImage] {
        guard url.isFileURL else { return [] }
        let asset = AVURLAsset(url: url)
        var items = (try? await asset.load(.metadata)) ?? []
        for format in [AVMetadataFormat.id3Metadata, .iTunesMetadata] {
            items += (try? await asset.loadMetadata(for: format)) ?? []
        }
        var seen = Set<Data>()
        var images: [NSImage] = []
        for item in items where item.commonKey == .commonKeyArtwork {
            guard let data = try? await item.load(.dataValue), seen.insert(data).inserted,
                  let image = NSImage(data: data) else { continue }
            images.append(image)
        }
        return images
    }

    private static func folderImage(in folder: URL) -> NSImage? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        for name in names.sorted() {
            let file = name as NSString
            guard folderImageNames.contains(file.deletingPathExtension.lowercased()),
                  folderImageExtensions.contains(file.pathExtension.lowercased()),
                  let image = NSImage(contentsOf: folder.appendingPathComponent(name)) else { continue }
            return image
        }
        return nil
    }

    private static func cached(_ key: String, _ resolve: () async -> NSImage?) async -> NSImage? {
        let key = key as NSString
        if let box = cache.object(forKey: key) { return box.image }
        let image = await resolve()
        cache.setObject(Box(image), forKey: key)
        return image
    }
}
