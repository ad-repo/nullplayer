import AppKit

/// Resolves the current track's artwork for WMP's two built-in album-art images. It is deliberately
/// WMP-owned: a skin sees pixels under two fixed names, never a file path, server token, or track.
enum WMPArtworkLoader {
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
