import XCTest
@testable import NullPlayer

final class PlayHistoryExportTests: XCTestCase {
    func testCSVIncludesEveryFieldAndEscapesQuotesAndNewlines() {
        let row = PlayHistoryExportRow(
            id: 42,
            trackID: "track-id",
            trackURL: "/Music/one,two.mp3",
            title: "A \"quoted\" title",
            artist: "Artist\nName",
            album: "Album",
            genre: "Rock",
            playedAt: Date(timeIntervalSince1970: 0),
            durationListened: 12.5,
            source: "local",
            skipped: true,
            contentType: "music",
            outputDevice: "Built-in Output"
        )

        let csv = PlayHistoryAgent.makeCSV(rows: [row])

        XCTAssertTrue(csv.hasPrefix("\"Event ID\",\"Track ID\",\"Track URL\""))
        XCTAssertTrue(csv.contains("\"/Music/one,two.mp3\""))
        XCTAssertTrue(csv.contains("\"A \"\"quoted\"\" title\""))
        XCTAssertTrue(csv.contains("\"Artist\nName\""))
        XCTAssertTrue(csv.contains("\"true\",\"music\",\"Built-in Output\""))
    }
}
