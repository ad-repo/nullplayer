import XCTest
@testable import NullPlayer

/// B229 — skin config keys are stored folded to lowercase, and a store written under mixed spellings
/// is folded once at load: Anunaki's "Normal" and `normal` are one setting.
final class WinampModernB229Tests: XCTestCase {

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "WinampModernB229.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testEverySpellingNamesOneSetting() {
        let configuration = WinampModernConfiguration(namespace: "Anunaki", defaults: makeDefaults())
        configuration.setInteger(1, section: "Player", key: "Normal")
        XCTAssertEqual(configuration.integer(section: "player", key: "normal"), 1)
        configuration.setInteger(0, section: "player", key: "NORMAL")
        XCTAssertEqual(configuration.integer(section: "Player", key: "Normal"), 0)
    }

    func testAPreMigrationStoreKeepsTheSortedFirstSpelling() {
        let defaults = makeDefaults()
        let prefix = "winampModern.config.Anunaki.Player."
        defaults.set(1, forKey: prefix + "Normal")
        defaults.set(0, forKey: prefix + "normal")
        defaults.set("x", forKey: prefix + "Party")

        let configuration = WinampModernConfiguration(namespace: "Anunaki", defaults: defaults)
        XCTAssertEqual(configuration.integer(section: "Player", key: "normal"), 1, "\"Normal\" sorts before \"normal\"")
        XCTAssertEqual(configuration.string(section: "player", key: "party"), "x")
        let stored = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("winampModern.config.Anunaki.") }
        XCTAssertEqual(Set(stored), ["winampModern.config.Anunaki.player.normal", "winampModern.config.Anunaki.player.party"])
    }

    func testResetClearsASectionWhateverItsSpelling() {
        let configuration = WinampModernConfiguration(namespace: "Anunaki", defaults: makeDefaults())
        configuration.setInteger(1, section: "Player", key: "Normal")
        configuration.removeSection("PLAYER")
        XCTAssertEqual(configuration.integer(section: "Player", key: "Normal", default: -1), -1)
    }
}
