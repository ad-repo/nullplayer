import XCTest
@testable import NullPlayer

final class MediaLibraryArtistTests: XCTestCase {

    func testAllArtistsSplitsMultiArtist() {
        // Build two tracks sharing an album with albumArtist = "Drake feat. Future"
        var t1 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/ml_t1.mp3"), title: "Track1")
        t1.albumArtist = "Drake feat. Future"
        t1.album = "Take Care"
        // Populate artists as parseMetadata would
        t1.artists = ArtistSplitter.split("", isAlbumArtist: false)
        t1.artists.append(contentsOf: ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true))

        var t2 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/ml_t2.mp3"), title: "Track2")
        t2.albumArtist = "Adele"
        t2.album = "21"
        t2.artists = ArtistSplitter.split("", isAlbumArtist: false)
        t2.artists.append(contentsOf: ArtistSplitter.split("Adele", isAlbumArtist: true))

        let tracks = [t1, t2]
        let artists = tracksToArtists(tracks)

        let names = artists.map(\.name)
        XCTAssertTrue(names.contains("Drake"))
        XCTAssertTrue(names.contains("Future"))
        XCTAssertTrue(names.contains("Adele"))
        XCTAssertFalse(names.contains("Drake feat. Future"))
    }

    func testFilteredTracksMatchesSplitArtist() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/filter_t.mp3"), title: "T")
        track.albumArtist = "Drake feat. Future"
        track.artists = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)

        var filter = LibraryFilter()
        filter.artists = ["Drake"]

        let matches = trackPassesArtistFilter(track, filter: filter)
        XCTAssertTrue(matches, "Track with albumArtist containing Drake must pass filter for 'Drake'")

        var filter2 = LibraryFilter()
        filter2.artists = ["Future"]
        XCTAssertTrue(trackPassesArtistFilter(track, filter: filter2))

        var filter3 = LibraryFilter()
        filter3.artists = ["Adele"]
        XCTAssertFalse(trackPassesArtistFilter(track, filter: filter3))
    }

    func testCreateLocalArtistRadioMatchesSplitArtist() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/radio_t.mp3"), title: "T")
        track.albumArtist = "Drake feat. Future"
        track.artists = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)

        let matchesDrake = trackMatchesArtistRadio(track, artist: "Drake")
        XCTAssertTrue(matchesDrake)

        let matchesFuture = trackMatchesArtistRadio(track, artist: "Future")
        XCTAssertTrue(matchesFuture)

        let matchesAdele = trackMatchesArtistRadio(track, artist: "Adele")
        XCTAssertFalse(matchesAdele)
    }

    // MARK: - Helpers (extracted logic for testability)

    private func tracksToArtists(_ tracks: [LibraryTrack]) -> [Artist] {
        var artistDict: [String: [LibraryTrack]] = [:]
        for track in tracks {
            let albumArtistNames = track.artists
                .filter { $0.role == .albumArtist }
                .map { $0.name }
            let effectiveNames = albumArtistNames.isEmpty
                ? [track.albumArtist ?? track.artist ?? "Unknown Artist"]
                : albumArtistNames
            for name in effectiveNames {
                artistDict[name, default: []].append(track)
            }
        }
        return artistDict.map { name, _ in Artist(id: name, name: name, albums: []) }
    }

    private func trackPassesArtistFilter(_ track: LibraryTrack, filter: LibraryFilter) -> Bool {
        guard !filter.artists.isEmpty else { return true }
        let albumArtistNames = track.artists.filter { $0.role == .albumArtist }.map { $0.name }
        return albumArtistNames.contains { filter.artists.contains($0) }
    }

    private func trackMatchesArtistRadio(_ track: LibraryTrack, artist: String) -> Bool {
        track.artists.contains {
            $0.role == .albumArtist &&
            $0.name.localizedCaseInsensitiveCompare(artist) == .orderedSame
        }
    }
}
