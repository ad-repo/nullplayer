import Foundation

/// Reading and writing "how many stars does this track have", across every source NullPlayer plays
/// from.
///
/// **The scale is 0–10 everywhere inside the app, and 0–5 stars everywhere a user sees it** — a star
/// is two points, so a half-star is representable even though no surface currently offers one. Each
/// backend keeps its own unit (Plex 0–10, Subsonic 0–5, Jellyfin and Emby 0–100, the local library
/// 0–10) and the conversion belongs here rather than at each caller: the star row in the Library
/// Browser's ART mode and a `.wal` skin's file-info panel are the same field and must never disagree
/// about what three stars means.
///
/// `nil` is "unrated", which is not the same as zero — a surface draws no stars for it rather than
/// five empty ones, and writing `nil` clears the rating on the server instead of storing a 0.
final class TrackRatingService {
    static let shared = TrackRatingService()

    private init() {}

    /// Stars (0–5) for an internal 0–10 rating, and back. The two live together so a rounding change
    /// cannot be made on one side only.
    static func stars(fromRating rating: Int) -> Int { max(0, min(5, Int((Double(rating) / 2).rounded()))) }
    static func rating(fromStars stars: Int) -> Int { max(0, min(5, stars)) * 2 }

    /// The rating a *local* track already has, without going to a server — a dictionary hit in the
    /// library. This is the only synchronous answer available: every other source has to be asked
    /// over the network, which is what `rating(for:)` is for.
    func localRating(for track: Track) -> Int? {
        guard track.url.isFileURL else { return nil }
        return MediaLibrary.shared.findTrack(byURL: track.url)?.rating
    }

    /// The track's rating on its own source, 0–10, or `nil` when it is unrated or the source cannot
    /// be reached. A radio stream has no rating and answers `nil` without a request.
    func rating(for track: Track) async -> Int? {
        if let ratingKey = track.plexRatingKey {
            // Plex already keeps the 0–10 scale, so this is the one source that needs no conversion.
            let details = try? await PlexManager.shared.serverClient?.fetchTrackDetails(trackID: ratingKey)
            return details?.userRating.map { Int($0) }
        }
        if let subsonicId = track.subsonicId {
            let song = try? await SubsonicManager.shared.serverClient?.fetchSong(id: subsonicId)
            return song?.userRating.map { $0 * 2 }
        }
        if let jellyfinId = track.jellyfinId {
            let song = try? await JellyfinManager.shared.serverClient?.fetchSong(id: jellyfinId)
            return song?.userRating.map { $0 / 10 }
        }
        if let embyId = track.embyId {
            let song = try? await EmbyManager.shared.serverClient?.fetchSong(id: embyId)
            return song?.userRating.map { $0 / 10 }
        }
        return localRating(for: track)
    }

    /// Store a 0–10 rating on whichever source the track came from; `nil` clears it.
    ///
    /// A track that belongs to no source we can write to — a radio stream, a file outside every watch
    /// folder — is a silent no-op rather than an error: the caller is a star widget, and there is
    /// nothing useful for it to say.
    func setRating(_ rating: Int?, for track: Track) async throws {
        let normalized = rating.map { max(0, min(10, $0)) }
        if let ratingKey = track.plexRatingKey {
            try await PlexManager.shared.serverClient?.rateItem(
                ratingKey: ratingKey, rating: (normalized ?? 0) > 0 ? normalized : nil)
        } else if let subsonicId = track.subsonicId {
            try await SubsonicManager.shared.setRating(songId: subsonicId, rating: (normalized ?? 0) / 2)
        } else if let jellyfinId = track.jellyfinId {
            try await JellyfinManager.shared.setRating(itemId: jellyfinId, rating: (normalized ?? 0) * 10)
        } else if let embyId = track.embyId {
            try await EmbyManager.shared.setRating(itemId: embyId, rating: (normalized ?? 0) * 10)
        } else if track.url.isFileURL, let libraryTrack = MediaLibrary.shared.findTrack(byURL: track.url) {
            MediaLibrary.shared.setRating(for: libraryTrack.id,
                                          rating: (normalized ?? 0) > 0 ? normalized : nil)
        }
    }
}
