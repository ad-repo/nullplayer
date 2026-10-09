import Foundation

extension Track {
    /// The media server's URL for this track's cover, from `artworkThumb`; nil for a local file or
    /// a stream. For Jellyfin and Emby `artworkThumb` is the item whose Primary image is the cover
    /// (`JellyfinSong.artworkItemId`), fetched with no tag.
    func serverArtworkURL(size: Int = 300) -> URL? {
        guard let thumb = artworkThumb else { return nil }
        if plexRatingKey != nil { return PlexManager.shared.artworkURL(thumb: thumb, size: size) }
        if subsonicId != nil { return SubsonicManager.shared.coverArtURL(coverArtId: thumb, size: size) }
        if jellyfinId != nil { return JellyfinManager.shared.imageURL(itemId: thumb, imageTag: nil, size: size) }
        if embyId != nil { return EmbyManager.shared.imageURL(itemId: thumb, imageTag: nil, size: size) }
        return nil
    }
}
