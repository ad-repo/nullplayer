import AppKit
import AVFoundation

/// Resolves the current track's artwork for WMP's two built-in album-art images. It is deliberately
/// WMP-owned: a skin sees pixels under two fixed names, never a file path, server token, or track.
enum WMPArtworkLoader {
    static func loadArtwork(for track: Track) async -> CGImage? {
        if track.url.isFileURL {
            return await localArtwork(at: track.url)
        }
        let remoteURL: URL?
        if track.plexRatingKey != nil, let thumb = track.artworkThumb {
            remoteURL = PlexManager.shared.artworkURL(thumb: thumb, size: 300)
        } else if track.subsonicId != nil, let coverArt = track.artworkThumb {
            remoteURL = SubsonicManager.shared.coverArtURL(coverArtId: coverArt, size: 300)
        } else if let id = track.jellyfinId {
            remoteURL = JellyfinManager.shared.imageURL(itemId: id, imageTag: track.artworkThumb, size: 300)
        } else if let id = track.embyId {
            remoteURL = EmbyManager.shared.imageURL(itemId: id, imageTag: track.artworkThumb, size: 300)
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

    private static func localArtwork(at url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        do {
            for format in [AVMetadataFormat.id3Metadata, .iTunesMetadata] {
                for item in try await asset.loadMetadata(for: format)
                where item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue), let image = NSImage(data: data) {
                        return cgImage(from: image)
                    }
                }
            }
            for item in try await asset.load(.metadata) where item.commonKey == .commonKeyArtwork {
                if let data = try await item.load(.dataValue), let image = NSImage(data: data) {
                    return cgImage(from: image)
                }
            }
        } catch { }
        return nil
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
