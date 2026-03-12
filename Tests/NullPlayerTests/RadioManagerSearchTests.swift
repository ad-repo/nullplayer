import XCTest
@testable import NullPlayer

final class RadioManagerSearchTests: XCTestCase {

    private let manager = RadioManager.shared

    func testSearchStationsMatchesMetadataFields() {
        let bangkok = RadioStation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Bangkok Nights",
            url: URL(string: "https://radio.example.com/bangkok-nights.mp3")!,
            genre: "Thai Pop"
        )
        let france = RadioStation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "France Jazz Club",
            url: URL(string: "https://stream.parisjazz.fr/live.mp3")!,
            genre: "Jazz"
        )
        let stations = [bangkok, france]

        XCTAssertEqual(manager.searchStations(in: stations, query: "Bangkok"), [bangkok])
        XCTAssertEqual(manager.searchStations(in: stations, query: "thai"), [bangkok])
        XCTAssertEqual(manager.searchStations(in: stations, query: "asia"), [bangkok])
        XCTAssertEqual(manager.searchStations(in: stations, query: "parisjazz.fr"), [france])
        XCTAssertEqual(manager.searchStations(in: stations, query: "bangkok-nights.mp3"), [bangkok])
    }

    func testSearchStationsIsCaseInsensitiveAndRequiresAllTokens() {
        let station = RadioStation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "France Jazz Club",
            url: URL(string: "https://stream.parisjazz.fr/live.mp3")!,
            genre: "Jazz"
        )
        let stations = [station]

        XCTAssertEqual(manager.searchStations(in: stations, query: "FRANCE JAZZ"), [station])
        XCTAssertEqual(manager.searchStations(in: stations, query: "france classical"), [])
    }

    func testSearchStationsReturnsEmptyForBlankQuery() {
        let station = RadioStation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Anything FM",
            url: URL(string: "https://anything.example.com/live.mp3")!,
            genre: "Rock"
        )

        XCTAssertEqual(manager.searchStations(in: [station], query: ""), [])
        XCTAssertEqual(manager.searchStations(in: [station], query: "   "), [])
    }

    func testSearchStationsReturnsNameSortedResults() {
        let zulu = RadioStation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: "Zulu FM",
            url: URL(string: "https://zulu.example.com/live.mp3")!,
            genre: "Rock"
        )
        let alpha = RadioStation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            name: "Alpha FM",
            url: URL(string: "https://alpha.example.com/live.mp3")!,
            genre: "Rock"
        )

        XCTAssertEqual(
            manager.searchStations(in: [zulu, alpha], query: "example.com"),
            [alpha, zulu]
        )
    }
}
