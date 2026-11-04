import AppKit

/// The playing track's cover as pixels, for the skin's cover-art displays: the file's own artwork
/// (`LocalArtwork`), else its server's, else an http(s) `artworkThumb`. The skin sees the pixels,
/// never a file path, server token or track. AIMP's own copy of `WMPArtworkLoader` (the AIMP guide
/// § *Shared code*).
enum AIMPSkinArtworkLoader {
    static func loadArtwork(for track: Track) async -> CGImage? {
        if track.url.isFileURL {
            return await LocalArtwork.image(for: track.url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        let thumb = track.artworkThumb.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased()) ? $0 : nil }
        guard let remoteURL = track.serverArtworkURL(size: 300) ?? thumb,
              let (data, response) = try? await URLSession.shared.data(from: remoteURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
