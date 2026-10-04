import Foundation
import NullPlayerCore

/// Parses `/hubs/search` responses.
///
/// `/hubs/search` ignores `sectionId`: every hub returns hits from every library section, so a
/// server with N sections returns N copies of each hit, each with a different (section-scoped)
/// `ratingKey`. Hits are deduped on content identity instead, and music hits can be kept to one
/// section by their `librarySectionID`.
enum PlexHubSearch {
    /// Hub types kept to `musicSectionID`; movie/show/episode hits always come from every section.
    private static let musicHubTypes: Set<String> = ["artist", "album", "track"]

    /// The deduped hits, plus every kept artist record — same-name records included, which
    /// `results.artists` collapses into one row.
    static func parse(_ data: Data, musicSectionID: String?) throws -> (results: PlexSearchResults, artistRecords: [PlexArtist]) {
        let response = try JSONDecoder().decode(Response.self, from: data)

        var results = PlexSearchResults()
        var artistRecords: [PlexArtist] = []
        var seen = Set<String>()
        for hub in response.MediaContainer.Hub ?? [] {
            let section = musicHubTypes.contains(hub.type) ? musicSectionID : nil
            for hit in hub.Metadata ?? [] where hit.isIn(section: section) {
                let item = hit.dto
                switch hub.type {
                case "artist":
                    let artist = item.toArtist()
                    artistRecords.append(artist)
                    if seen.insert("artist|" + PlexIdentity.normalizedName(artist.title)).inserted {
                        results.artists.append(artist)
                    }
                case "album":
                    let album = item.toAlbum()
                    if seen.insert("album|" + album.identityKey).inserted { results.albums.append(album) }
                case "track":
                    let track = item.toTrack()
                    if seen.insert("track|" + track.identityKey).inserted { results.tracks.append(track) }
                case "movie":
                    if seen.insert("movie|" + item.title.lowercased()).inserted { results.movies.append(item.toMovie()) }
                case "show":
                    if seen.insert("show|" + item.title.lowercased()).inserted { results.shows.append(item.toShow()) }
                case "episode":
                    let key = "episode|\(item.grandparentTitle?.lowercased() ?? "")|\(item.parentTitle?.lowercased() ?? "")|\(item.title.lowercased())|\(item.index ?? 0)"
                    if seen.insert(key).inserted { results.episodes.append(item.toEpisode()) }
                default:
                    break
                }
            }
        }
        return (results, artistRecords)
    }

    private struct Response: Decodable {
        let MediaContainer: Container
    }

    private struct Container: Decodable {
        let Hub: [Hub]?
    }

    private struct Hub: Decodable {
        let type: String
        let Metadata: [Hit]?
    }

    /// A hit's shared DTO plus its `librarySectionID`, decoded from the same object. The section
    /// is read leniently (Int or String, absent tolerated) so it can never fail the search.
    private struct Hit: Decodable {
        let dto: PlexMetadataDTO
        let sectionID: String?

        private enum CodingKeys: String, CodingKey { case librarySectionID }

        init(from decoder: Decoder) throws {
            dto = try PlexMetadataDTO(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sectionID = (try? container.decode(Int.self, forKey: .librarySectionID)).map(String.init)
                ?? (try? container.decode(String.self, forKey: .librarySectionID))
        }

        /// In `section`, or carrying no section; always when `section` is nil.
        func isIn(section: String?) -> Bool {
            section == nil || sectionID == nil || sectionID == section
        }
    }
}
