import AppKit
import AVFoundation

/// Loads artwork for a track from the appropriate source, returning an NSImage.
/// Reuses the same artwork resolution patterns as NowPlayingManager.
enum CLIArtwork {

    static func loadArtwork(for track: Track) async -> NSImage? {
        NSLog("[CLIArt] loadArtwork — isFileURL=%d plexRatingKey=%@ subsonicId=%@ artworkThumb=%@",
              track.url.isFileURL ? 1 : 0,
              track.plexRatingKey ?? "nil",
              track.subsonicId ?? "nil",
              track.artworkThumb ?? "nil")
        if track.url.isFileURL {
            return await loadLocalArtwork(url: track.url)
        } else if track.plexRatingKey != nil, let thumb = track.artworkThumb {
            return await loadRemoteImage(url: PlexManager.shared.artworkURL(thumb: thumb, size: 300))
        } else if track.subsonicId != nil, let coverArt = track.artworkThumb {
            return await loadRemoteImage(url: SubsonicManager.shared.coverArtURL(coverArtId: coverArt, size: 300))
        } else if track.jellyfinId != nil, let imageTag = track.artworkThumb {
            return await loadRemoteImage(url: JellyfinManager.shared.imageURL(itemId: track.jellyfinId!, imageTag: imageTag, size: 300))
        } else if track.embyId != nil, let imageTag = track.artworkThumb {
            return await loadRemoteImage(url: EmbyManager.shared.imageURL(itemId: track.embyId!, imageTag: imageTag, size: 300))
        }
        return nil
    }

    private static func loadLocalArtwork(url: URL) async -> NSImage? {
        NSLog("[CLIArt] loadLocalArtwork: %@", url.lastPathComponent)
        let asset = AVURLAsset(url: url)
        do {
            for format in [AVMetadataFormat.id3Metadata, .iTunesMetadata] {
                let metadata = try await asset.loadMetadata(for: format)
                NSLog("[CLIArt] format %@ — %d metadata items", format.rawValue, metadata.count)
                for item in metadata {
                    NSLog("[CLIArt]   item commonKey=%@ identifier=%@", item.commonKey?.rawValue ?? "nil", item.identifier?.rawValue ?? "nil")
                    if item.commonKey == .commonKeyArtwork,
                       let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        NSLog("[CLIArt] found artwork via format %@, data=%d bytes", format.rawValue, data.count)
                        return image
                    }
                }
            }
            // Fallback: common metadata
            let metadata = try await asset.load(.metadata)
            NSLog("[CLIArt] .metadata fallback — %d items", metadata.count)
            for item in metadata {
                if item.commonKey == .commonKeyArtwork,
                   let data = try await item.load(.dataValue),
                   let image = NSImage(data: data) {
                    NSLog("[CLIArt] found artwork via .metadata fallback, data=%d bytes", data.count)
                    return image
                }
            }
            NSLog("[CLIArt] no artwork found in any metadata")
        } catch {
            NSLog("[CLIArt] loadLocalArtwork error: %@", error.localizedDescription)
        }
        return nil
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
