import XCTest
@testable import NullPlayer

final class ArtistSplitterTests: XCTestCase {

    // MARK: - ArtistRole

    func testArtistRoleRawValues() {
        XCTAssertEqual(ArtistRole.primary.rawValue, "primary")
        XCTAssertEqual(ArtistRole.featured.rawValue, "featured")
        XCTAssertEqual(ArtistRole.albumArtist.rawValue, "album_artist")
    }

    // MARK: - Single artist passthrough

    func testSingleArtist() {
        let result = ArtistSplitter.split("Adele", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Adele")
        XCTAssertEqual(result[0].role, .primary)
    }

    func testSingleAlbumArtist() {
        let result = ArtistSplitter.split("Adele", isAlbumArtist: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Adele")
        XCTAssertEqual(result[0].role, .albumArtist)
    }

    func testEmptyString() {
        XCTAssertTrue(ArtistSplitter.split("", isAlbumArtist: false).isEmpty)
    }

    func testWhitespaceOnly() {
        XCTAssertTrue(ArtistSplitter.split("   ", isAlbumArtist: false).isEmpty)
    }

    // MARK: - feat. splitting

    func testFeatDot() {
        let result = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[0].role, .primary)
        XCTAssertEqual(result[1].name, "Future")
        XCTAssertEqual(result[1].role, .featured)
    }

    func testFeatNoDot() {
        let result = ArtistSplitter.split("Drake feat Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[1].name, "Future")
        XCTAssertEqual(result[1].role, .featured)
    }

    func testFtDot() {
        let result = ArtistSplitter.split("Drake ft. Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].name, "Future")
        XCTAssertEqual(result[1].role, .featured)
    }

    func testFtNoDot() {
        let result = ArtistSplitter.split("Drake ft Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].name, "Future")
    }

    func testFeatCaseInsensitive() {
        let result = ArtistSplitter.split("Drake FEAT. Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].name, "Future")
    }

    func testFeatWithParens() {
        let result = ArtistSplitter.split("Drake (feat. Future)", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[1].name, "Future")
    }

    // MARK: - Word boundary: must NOT split "defeat", "often", etc.

    func testNoFalsePositiveOnDefeat() {
        let result = ArtistSplitter.split("Band of defeat", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Band of defeat")
    }

    func testNoFalsePositiveOnOften() {
        // "Often feat-like": the pattern looks for "feat" preceded by space or "(" and followed by
        // space or end-of-string. Since "-like" follows "feat", the lookhead (?=[ ]|$) fails.
        // Therefore, no split occurs and the entire string is treated as a single primary artist.
        let result = ArtistSplitter.split("Often feat-like", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Often feat-like")
        XCTAssertEqual(result[0].role, .primary)
    }

    func testNoFalsePositiveDefeatWordBoundary() {
        // "defeat" — "feat" appears but is not at a word boundary (no space or ( before it)
        let result = ArtistSplitter.split("Great defeat", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Great defeat")
    }

    // MARK: - Semicolon splitting

    func testSemicolon() {
        let result = ArtistSplitter.split("Foo; Bar", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Foo")
        XCTAssertEqual(result[0].role, .primary)
        XCTAssertEqual(result[1].name, "Bar")
        XCTAssertEqual(result[1].role, .primary)
    }

    func testSemicolonAlbumArtist() {
        let result = ArtistSplitter.split("Foo; Bar", isAlbumArtist: true)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].role, .albumArtist)
        XCTAssertEqual(result[1].role, .albumArtist)
    }

    // MARK: - Slash splitting

    func testSlashNotAlbumArtist() {
        let result = ArtistSplitter.split("Foo / Bar", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Foo")
        XCTAssertEqual(result[0].role, .primary)
        XCTAssertEqual(result[1].name, "Bar")
        XCTAssertEqual(result[1].role, .primary)
    }

    func testSlashAlbumArtist() {
        let result = ArtistSplitter.split("Foo / Bar", isAlbumArtist: true)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].role, .albumArtist)
        XCTAssertEqual(result[1].role, .albumArtist)
    }

    // MARK: - Combined patterns

    func testSemicolonWithFeat() {
        // "A; B feat. C" → A (primary), B (primary), C (featured)
        let result = ArtistSplitter.split("A; B feat. C", isAlbumArtist: false)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].name, "A")
        XCTAssertEqual(result[0].role, .primary)
        XCTAssertEqual(result[1].name, "B")
        XCTAssertEqual(result[1].role, .primary)
        XCTAssertEqual(result[2].name, "C")
        XCTAssertEqual(result[2].role, .featured)
    }

    func testSlashWithFeat() {
        let result = ArtistSplitter.split("A / B feat. C", isAlbumArtist: false)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].name, "A")
        XCTAssertEqual(result[1].name, "B")
        XCTAssertEqual(result[2].name, "C")
        XCTAssertEqual(result[2].role, .featured)
    }

    // MARK: - albumArtist=true: feat. produces albumArtist for both sides

    func testFeatAlbumArtist() {
        let result = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[0].role, .albumArtist)
        XCTAssertEqual(result[1].name, "Future")
        XCTAssertEqual(result[1].role, .albumArtist)
    }

    // MARK: - No split on ambiguous separators

    func testAmpersandNotSplit() {
        let result = ArtistSplitter.split("Simon & Garfunkel", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Simon & Garfunkel")
    }

    func testVariousArtists() {
        let result = ArtistSplitter.split("Various Artists", isAlbumArtist: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Various Artists")
        XCTAssertEqual(result[0].role, .albumArtist)
    }

    // MARK: - Whitespace trimming

    func testWhitespaceTrimming() {
        let result = ArtistSplitter.split("  Drake  feat.  Future  ", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[1].name, "Future")
    }

    func testEmptySegmentsDiscarded() {
        // Double semicolon produces empty segment
        let result = ArtistSplitter.split("Foo;; Bar", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Foo")
        XCTAssertEqual(result[1].name, "Bar")
    }

    // MARK: - Multiple feat limitation

    func testMultipleFeatOnlyFirstSplit() {
        // Only the first feat. token is split; the second remains verbatim in the featured name.
        // This is a documented limitation — see NOTE in splitOnFeat.
        let result = ArtistSplitter.split("A feat. B feat. C", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "A")
        XCTAssertEqual(result[1].name, "B feat. C")
        XCTAssertEqual(result[1].role, .featured)
    }
}

final class LibraryTrackCodableTests: XCTestCase {

    func testArtistsFieldExcludedFromCodable() throws {
        var track = LibraryTrack(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Test",
            artist: "Drake feat. Future"
        )
        track.artists = [(name: "Drake", role: .primary), (name: "Future", role: .featured)]

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(LibraryTrack.self, from: data)

        // artists must be empty after decode — it is transient
        XCTAssertTrue(decoded.artists.isEmpty)
        // All other fields must survive the round-trip
        XCTAssertEqual(decoded.title, "Test")
        XCTAssertEqual(decoded.artist, "Drake feat. Future")
    }

    func testAllStoredFieldsRoundTrip() throws {
        let original = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/song.flac"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            albumArtist: "Album Artist",
            genre: "Rock",
            year: 2024,
            trackNumber: 3,
            discNumber: 1,
            duration: 240.5,
            bitrate: 320,
            sampleRate: 44100,
            channels: 2,
            fileSize: 12345678,
            dateAdded: Date(timeIntervalSince1970: 1000),
            lastPlayed: Date(timeIntervalSince1970: 2000),
            playCount: 7,
            rating: 8
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LibraryTrack.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.artist, original.artist)
        XCTAssertEqual(decoded.albumArtist, original.albumArtist)
        XCTAssertEqual(decoded.rating, original.rating)
        XCTAssertEqual(decoded.playCount, original.playCount)
    }
}
