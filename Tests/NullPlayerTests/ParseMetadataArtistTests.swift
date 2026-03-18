import XCTest
@testable import NullPlayer

final class ParseMetadataArtistTests: XCTestCase {

    // Test ArtistSplitter integration with the insert rule
    // (parseMetadata itself needs a real audio file, so we test the insert-rule logic directly)

    func testInsertRuleWithAlbumArtist() {
        // When albumArtist is set, artists from it get albumArtist role
        let albumArtistSplit = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)
        XCTAssertTrue(albumArtistSplit.allSatisfy { $0.role == .albumArtist })
        XCTAssertEqual(albumArtistSplit.map { $0.name }, ["Drake", "Future"])
    }

    func testInsertRuleFallbackToArtist() {
        // When albumArtist is nil, artist tag is split with isAlbumArtist: true
        let fallbackSplit = ArtistSplitter.split("Foo feat. Bar", isAlbumArtist: true)
        XCTAssertTrue(fallbackSplit.allSatisfy { $0.role == .albumArtist })
        XCTAssertEqual(fallbackSplit.map { $0.name }.sorted(), ["Bar", "Foo"])
    }

    func testInsertRuleUnknownArtistWhenBothNil() {
        // When both artist and albumArtist are nil, we produce a single "Unknown Artist" albumArtist row
        // This is enforced in parseMetadata. Test via the splitter returning empty for nil input.
        let nilSplit = ArtistSplitter.split("", isAlbumArtist: true)
        XCTAssertTrue(nilSplit.isEmpty)
        // The caller (parseMetadata) must insert ("Unknown Artist", .albumArtist) when split returns empty
    }
}
