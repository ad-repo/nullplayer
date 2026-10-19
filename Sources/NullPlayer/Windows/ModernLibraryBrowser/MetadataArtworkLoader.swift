import AppKit

enum MetadataArtworkLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func loadArtwork(for track: LibraryTrack) async -> NSImage? {
        if let embedded = await LocalArtwork.embeddedImage(in: track.url) {
            return embedded
        }
        if let artworkURL = track.artworkURL,
           let remote = await loadRemoteArtwork(urlString: artworkURL, cacheNamespace: "metadata-editor") {
            return remote
        }
        return nil
    }

    static func loadArtwork(for tracks: [LibraryTrack]) async -> NSImage? {
        for track in tracks {
            if let image = await loadArtwork(for: track) {
                return image
            }
        }
        return nil
    }

    private static func loadRemoteArtwork(urlString: String, cacheNamespace: String) async -> NSImage? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let cacheKey = NSString(string: "\(cacheNamespace):\(trimmed)")
        if let cached = cache.object(forKey: cacheKey) { return cached }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = NSImage(data: data) else {
                return nil
            }
            cache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }
}
