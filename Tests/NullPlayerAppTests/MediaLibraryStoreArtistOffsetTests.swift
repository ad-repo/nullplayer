import XCTest
@testable import NullPlayer

final class MediaLibraryStoreArtistOffsetTests: XCTestCase {
    private var store: MediaLibraryStore!
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = MediaLibraryStore.makeForTesting()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaLibraryStoreArtistOffsetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        store?.close()
        store = nil
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
            self.tempDirectoryURL = nil
        }
        try super.tearDownWithError()
    }

    func testArtistOffsetMatchesArtistNamesOrdering() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("library-artist-offset.sqlite")
        store.open(at: dbURL)

        let artistNames: [String] = ["Zebra", "Alpha", "Delta", "Bravo", "Charlie"]
        let tracks = artistNames.enumerated().map { index, artist in
            LibraryTrack(
                url: URL(fileURLWithPath: "/tmp/\(artist).mp3"),
                title: "Track \(index)",
                artist: artist,
                album: "Album \(index)",
                albumArtist: artist,
                dateAdded: Date(timeIntervalSince1970: Double(index + 1))
            )
        }
        store.upsertTracks(tracks.map { (track: $0, sig: nil) })

        let orderedNames = store.artistNames(limit: 10, offset: 0, sort: .nameAsc)
        XCTAssertEqual(orderedNames, ["Alpha", "Bravo", "Charlie", "Delta", "Zebra"])
        XCTAssertEqual(store.artistOffset(named: "Charlie", sort: .nameAsc), 2)
        XCTAssertEqual(store.artistOffset(named: "charlie", sort: .nameAsc), 2)
        XCTAssertNil(store.artistOffset(named: "Missing", sort: .nameAsc))
    }
}
