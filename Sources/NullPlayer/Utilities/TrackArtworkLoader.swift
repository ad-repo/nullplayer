import AppKit

/// A track's cover as pixels, for a skin family that draws album art itself (WMP's two built-in
/// album-art images). One source is chosen by the track: a local file's own artwork
/// (`LocalArtwork`); for a remote track, its server's artwork if it has one, otherwise an http(s)
/// `artworkThumb`. If that source has none or its fetch fails, the result is nil; no other source
/// is tried. The skin sees the pixels, never a file path, server token or track.
enum TrackArtworkLoader {
    static func loadArtwork(for track: Track) async -> CGImage? {
        if track.url.isFileURL {
            return await LocalArtwork.image(for: track.url).flatMap(cgImage)
        }
        let remoteURL: URL?
        if let serverURL = track.serverArtworkURL(size: 300) {
            remoteURL = serverURL
        } else if let value = track.artworkThumb, let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased()) {
            remoteURL = url
        } else {
            remoteURL = nil
        }
        guard let remoteURL,
              let (data, response) = try? await URLSession.shared.data(from: remoteURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        return cgImage(from: image)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
