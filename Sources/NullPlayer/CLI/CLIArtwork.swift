import AppKit

/// Loads artwork for a track from the appropriate source, returning an NSImage.
/// Reuses the same artwork resolution patterns as NowPlayingManager.
enum CLIArtwork {

    static func loadArtwork(for track: Track) async -> NSImage? {
        NSLog("[CLIArt] loadArtwork — isFileURL=%d plexRatingKey=%@ subsonicId=%@ artworkThumb=%@",
              track.url.isFileURL ? 1 : 0,
              track.plexRatingKey ?? "nil",
              track.subsonicId ?? "nil",
              track.artworkThumb?.redactingSensitiveURLQueryItems ?? "nil")
        if track.url.isFileURL {
            return await LocalArtwork.image(for: track.url)
        }
        return await loadRemoteImage(url: track.serverArtworkURL(size: 300))
    }

    private static func loadRemoteImage(url: URL?) async -> NSImage? {
        guard let url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}
