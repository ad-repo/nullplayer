import XCTest
@testable import NullPlayer

final class RadioDefaultStationCatalogTests: XCTestCase {

    private struct DefaultStationSeed: Decodable {
        let name: String
        let url: String
        let genre: String?
        let iconURL: String?
    }

    private func defaultStationsFileURL() -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("Sources/NullPlayer/Resources/Radio/default_stations.json")
    }

    private func loadSeeds() throws -> [DefaultStationSeed] {
        let data = try Data(contentsOf: defaultStationsFileURL())
        return try JSONDecoder().decode([DefaultStationSeed].self, from: data)
    }

    func testDefaultStationsCatalogDecodesAndHasRequiredFields() throws {
        let seeds = try loadSeeds()
        XCTAssertFalse(seeds.isEmpty)

        for seed in seeds {
            XCTAssertFalse(seed.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(seed.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertNotNil(URL(string: seed.url))
            XCTAssertFalse((seed.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let iconURL = seed.iconURL, !iconURL.isEmpty {
                XCTAssertNotNil(URL(string: iconURL))
            }
        }
    }

    func testDefaultStationsCatalogURLsAreUnique() throws {
        let seeds = try loadSeeds()
        let urls = seeds.map(\.url)
        XCTAssertEqual(Set(urls).count, urls.count)
    }

    func testDefaultStationsCatalogHasNoMojibakeNames() throws {
        let seeds = try loadSeeds()
        let mojibakePattern = try XCTUnwrap(NSRegularExpression(pattern: "Ã|Å|Ð|Ñ"))
        let offenders = seeds.filter { seed in
            let range = NSRange(location: 0, length: seed.name.utf16.count)
            return mojibakePattern.firstMatch(in: seed.name, options: [], range: range) != nil
        }
        XCTAssertTrue(offenders.isEmpty, "Found mojibake station names: \(offenders.map(\.name))")
    }

    func testNatureSoundsBucketRejectsOffGenreSignals() throws {
        let seeds = try loadSeeds().filter { $0.genre == "Nature Sounds" }
        let bannedSignals = [
            "rock",
            "metal",
            "wacken",
            "gothic",
            "punk",
            "hiphop",
            "news",
            "workout",
            "radiobob.de",
            "radioroks",
            "hitfm.ua",
            "radioplayer.ua/radionews"
        ]

        let offenders = seeds.filter { seed in
            let text = "\(seed.name) \(seed.url)".lowercased()
            return bannedSignals.contains(where: text.contains)
        }

        XCTAssertTrue(offenders.isEmpty, "Nature Sounds contains off-genre stations: \(offenders.map(\.name))")
    }

    func testDefaultGenreMigrationUpdatesOnlyKnownLegacyGenreForMatchingURL() {
        let stationURL = URL(string: "https://ice5.somafm.com/bossa-128-mp3")!

        XCTAssertEqual(
            RadioManager.correctedDefaultGenre(for: stationURL, currentGenre: "Classical"),
            "Bossa Nova"
        )
        XCTAssertNil(
            RadioManager.correctedDefaultGenre(for: stationURL, currentGenre: "Custom Genre")
        )
        XCTAssertNil(
            RadioManager.correctedDefaultGenre(
                for: URL(string: "https://example.com/not-in-defaults.mp3")!,
                currentGenre: "Classical"
            )
        )
    }

    func testApplyingDefaultGenreCorrectionsKeepsStationCountAndDoesNotDeleteRemovedDefaults() {
        let migratedStation = RadioStation(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "SomaFM Bossa Beyond",
            url: URL(string: "https://ice5.somafm.com/bossa-128-mp3")!,
            genre: "Classical"
        )
        let removedDefaultStation = RadioStation(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Radio Dreamland",
            url: URL(string: "https://dreamsiteradiocp3.com/proxy/dreamland?mp=/stream")!,
            genre: "Nature Sounds"
        )

        let input = [migratedStation, removedDefaultStation]
        let result = RadioManager.applyingDefaultGenreCorrections(to: input)

        XCTAssertEqual(result.stations.count, input.count)
        XCTAssertEqual(result.changedCount, 1)
        XCTAssertEqual(result.stations[0].genre, "Bossa Nova")
        XCTAssertEqual(result.stations[1], removedDefaultStation)
    }

    func testApplyingDefaultURLCorrectionsMigratesLegacyAudiophilePrimaryToCanonicalSecondary() {
        let legacyAudiophileStation = RadioStation(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Distorsion FM",
            url: URL(string: "https://radioemisoras.cl/distorsion.flac")!,
            genre: "Rock"
        )
        let alreadyCanonicalStation = RadioStation(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "Distorsion FM",
            url: URL(string: "https://radioemisoras.cl/distorsion.mp3")!,
            genre: "Rock"
        )
        let unrelatedNameWithLegacyURL = RadioStation(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "Custom Distorsion Clone",
            url: URL(string: "https://radioemisoras.cl/distorsion.flac")!,
            genre: "Rock"
        )

        let input = [legacyAudiophileStation, alreadyCanonicalStation, unrelatedNameWithLegacyURL]
        let result = RadioManager.applyingDefaultURLCorrections(to: input)

        XCTAssertEqual(result.stations.count, input.count)
        XCTAssertEqual(result.changedCount, 1)
        XCTAssertEqual(result.stations[0].url.absoluteString, "https://radioemisoras.cl/distorsion.mp3")
        XCTAssertEqual(result.stations[1], alreadyCanonicalStation)
        XCTAssertEqual(result.stations[2], unrelatedNameWithLegacyURL)
    }

    func testApplyingDefaultURLCorrectionsRemovesKnownBrokenDefaults() {
        let removedRockFlac = RadioStation(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            name: "Radio Paradise Rock Mix FLAC",
            url: URL(string: "https://stream.radioparadise.com/rock-flac")!,
            genre: "Rock"
        )
        let removedBluesFlac = RadioStation(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            name: "Radio Blues Flac",
            url: URL(string: "https://audio-edge-cmc51.fra.h.radiomast.io/radioblues-flac")!,
            genre: "Blues"
        )
        let keeper = RadioStation(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            name: "Example Keeper",
            url: URL(string: "https://example.com/stream.mp3")!,
            genre: "Eclectic"
        )

        let result = RadioManager.applyingDefaultURLCorrections(to: [removedRockFlac, removedBluesFlac, keeper])

        XCTAssertEqual(result.changedCount, 2)
        XCTAssertEqual(result.stations, [keeper])
    }
}
