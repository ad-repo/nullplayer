import Foundation

/// Reading and writing "how many stars does this track have", across every source NullPlayer plays
/// from.
///
/// **The scale is 0–10 everywhere inside the app, and 0–5 stars everywhere a user sees it** — a star
/// is two points, so a half-star is representable even though no surface currently offers one. Each
/// backend keeps its own unit (Plex 0–10, Subsonic 0–5, Jellyfin and Emby 0–100, the local library
/// 0–10) and the conversion belongs here rather than at each caller: the Art window's star rating
/// and a `.wal` skin's file-info panel are the same field and must never disagree
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

    /// Where a track's rating lives. Every read and write dispatches on this one answer, so a
    /// surface that asks "can this be rated?" can never disagree with what a write would do.
    private enum Source {
        case plex(ratingKey: String)
        case subsonic(id: String)
        case jellyfin(id: String)
        case emby(id: String)
        case library(LibraryTrack)
    }

    /// `nil` for a track with nowhere to keep a rating: a radio stream, a file outside every watch
    /// folder.
    private static func source(of track: Track) -> Source? {
        if let ratingKey = track.plexRatingKey { return .plex(ratingKey: ratingKey) }
        if let id = track.subsonicId { return .subsonic(id: id) }
        if let id = track.jellyfinId { return .jellyfin(id: id) }
        if let id = track.embyId { return .emby(id: id) }
        if track.url.isFileURL, let libraryTrack = MediaLibrary.shared.findTrack(byURL: track.url) {
            return .library(libraryTrack)
        }
        return nil
    }

    /// Whether `setRating` has somewhere to write this track's rating.
    static func isRateable(_ track: Track) -> Bool { source(of: track) != nil }

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
        switch Self.source(of: track) {
        case .plex(let ratingKey):
            // Plex already keeps the 0–10 scale, so this is the one source that needs no conversion.
            let details = try? await PlexManager.shared.serverClient?.fetchTrackDetails(trackID: ratingKey)
            return details?.userRating.map { Int($0) }
        case .subsonic(let id):
            let song = try? await SubsonicManager.shared.serverClient?.fetchSong(id: id)
            return song?.userRating.map { $0 * 2 }
        case .jellyfin(let id):
            let song = try? await JellyfinManager.shared.serverClient?.fetchSong(id: id)
            return song?.userRating.map { $0 / 10 }
        case .emby(let id):
            let song = try? await EmbyManager.shared.serverClient?.fetchSong(id: id)
            return song?.userRating.map { $0 / 10 }
        case .library(let libraryTrack):
            return libraryTrack.rating
        case nil:
            return nil
        }
    }

    /// Store a 0–10 rating on whichever source the track came from; `nil` clears it.
    ///
    /// A track that belongs to no source we can write to (`isRateable` is false) is a silent no-op
    /// rather than an error: the caller is a star widget, and there is nothing useful for it to say.
    func setRating(_ rating: Int?, for track: Track) async throws {
        let normalized = rating.map { max(0, min(10, $0)) }
        switch Self.source(of: track) {
        case .plex(let ratingKey):
            try await PlexManager.shared.serverClient?.rateItem(
                ratingKey: ratingKey, rating: (normalized ?? 0) > 0 ? normalized : nil)
        case .subsonic(let id):
            try await SubsonicManager.shared.setRating(songId: id, rating: (normalized ?? 0) / 2)
        case .jellyfin(let id):
            try await JellyfinManager.shared.setRating(itemId: id, rating: (normalized ?? 0) * 10)
        case .emby(let id):
            try await EmbyManager.shared.setRating(itemId: id, rating: (normalized ?? 0) * 10)
        case .library(let libraryTrack):
            MediaLibrary.shared.setRating(for: libraryTrack.id,
                                          rating: (normalized ?? 0) > 0 ? normalized : nil)
        case nil:
            break
        }
    }
}
