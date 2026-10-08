import Foundation
import NullPlayerCore

/// What the album screen (`ArtAlbumView`) shows about an album beyond its title, artist, year and
/// track count: a line of facts and, where the source has one, its description.
struct LibraryAlbumInfo {
    /// Genre, record label, release date, total length — whichever the source knows.
    var facts: [String]
    var summary: String?
    /// A description the source only sends on request (Jellyfin, Emby), fetched when the screen opens.
    var loadSummary: (() async -> String?)?

    /// The info for an album row; nil for anything else.
    @MainActor
    init?(_ playable: LibraryPlayable) {
        switch playable {
        case .plexAlbum(let album):
            let released = album.originallyAvailableAt.map { Self.dateFormatter.string(from: $0) }
            facts = [album.genre, album.studio, released, album.duration.flatMap { Self.length(seconds: $0 / 1000) }]
                .compactMap { $0 }
            summary = album.summary
        case .localAlbum(let album):
            let length = album.totalDuration > 0 ? Self.length(seconds: Int(album.totalDuration)) : nil
            facts = [album.tracks.lazy.compactMap(\.genre).first, length].compactMap { $0 }
        case .subsonicAlbum(let album):
            facts = [album.genre, Self.length(seconds: album.duration)].compactMap { $0 }
        case .jellyfinAlbum(let album):
            facts = [album.genre, Self.length(seconds: album.duration)].compactMap { $0 }
            loadSummary = { try? await JellyfinManager.shared.serverClient?.fetchOverview(itemId: album.id) }
        case .embyAlbum(let album):
            facts = [album.genre, Self.length(seconds: album.duration)].compactMap { $0 }
            loadSummary = { try? await EmbyManager.shared.serverClient?.fetchOverview(itemId: album.id) }
        default:
            return nil
        }
        facts.removeAll { $0.isEmpty }
        if summary?.isEmpty == true { summary = nil }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    /// "42 min", "1 hr 5 min"; nil for an unknown (zero) length.
    static func length(seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        return formatter.string(from: TimeInterval(max(seconds, 60)))?.replacingOccurrences(of: ",", with: "")
    }
}
