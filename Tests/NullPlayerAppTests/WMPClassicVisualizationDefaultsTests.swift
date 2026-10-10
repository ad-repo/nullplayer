import AppKit
import XCTest
@testable import NullPlayer

/// W214, site 3: `applyClassicVisualizationDefaults` wrote Classic's visualization defaults over a
/// running `.wmz` session.
///
/// The reachable route is Skins > Classic > *a skin name* while WMP is running: `selectClassicSkin`
/// calls `loadSkin`, which calls this. Measured live under `AlienMorph` with the Spectrum Analyzer
/// open and a track playing — one click rewrote all six keys below and posted the live
/// `.visClassicProfileCommand` reloads, flipping the analyzer from the Enhanced LED matrix to the
/// vis_classic "Purple Neon" analyzer while the WMP window itself never changed at all.
///
/// The gate is pure so both sides of it can be pinned here; the family-by-family verification is on
/// screen and is recorded in `skills/wmp-skin-guide/SKILL.md`.
final class WMPClassicVisualizationDefaultsTests: XCTestCase {

    // MARK: - The gate, family by family

    /// The defect. `isRunningModernUI` is `false` for `WMPMainWindowController` by construction,
    /// so the old `guard !isRunningModernUI` admitted a `.wmz` session.
    func testWMPSessionIsNotGivenClassicVisualizationDefaults() {
        XCTAssertFalse(
            WindowManager.appliesClassicVisualizationDefaults(family: .wmp),
            "a .wmz session keeps the visualization it was given"
        )
    }

    /// Classic is what the rule is for and is unchanged.
    func testClassicSessionStillGetsClassicVisualizationDefaults() {
        XCTAssertTrue(WindowManager.appliesClassicVisualizationDefaults(family: .classic))
    }

    /// Original (`.modern`/`.metal`) was already excluded and stays excluded.
    func testOriginalSessionIsStillExcluded() {
        XCTAssertFalse(WindowManager.appliesClassicVisualizationDefaults(family: .nullPlayerModern))
    }

    /// Winamp Modern used to reach this rule too — it answers false to both old predicates — and
    /// since the classic skin loads at every launch, every `.wal` launch reset the Spectrum window
    /// to "Purple Neon". `.wal` now matches a profile to the skin (`VisClassicProfileMatcher`).
    func testWinampModernSessionIsExcludedSoItsProfileFollowsTheSkin() {
        XCTAssertFalse(
            WindowManager.appliesClassicVisualizationDefaults(family: .winampModern),
            ".wal picks its vis_classic default from the skin, not Classic's Purple Neon"
        )
    }

    // MARK: - What the rule writes when it does run

    /// The six keys the `.wmz` session was losing, pinned so a change to Classic's defaults cannot
    /// quietly widen what a reset or a Classic entry overwrites. A skin load writes the same keys
    /// minus the two main-window modes (`includesMainWindowMode: false`).
    func testClassicDefaultsWriteTheSixScopedVisualizationKeys() throws {
        let suiteName = "WMPClassicVisualizationDefaultsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // The state a WMP session might legitimately be in.
        defaults.set("Matrix", forKey: "mainWindowVisMode")
        defaults.set("Matrix", forKey: "modernMainWindowVisMode")
        defaults.set("Fire", forKey: "spectrumQualityMode")
        defaults.set("Lavender Pink Tips", forKey: "visClassicLastProfileName.mainWindow")
        defaults.set("Lavender Pink Tips", forKey: "visClassicLastProfileName.spectrumWindow")
        defaults.set(false, forKey: "visClassicFitToWidth.mainWindow")

        WindowManager.shared.writeClassicVisualizationDefaultKeys(for: .all, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "mainWindowVisMode"), MainWindowVisMode.spectrum.rawValue)
        XCTAssertEqual(defaults.string(forKey: "modernMainWindowVisMode"), MainWindowVisMode.spectrum.rawValue)
        XCTAssertEqual(defaults.string(forKey: "spectrumQualityMode"), SpectrumQualityMode.visClassicExact.rawValue)
        XCTAssertEqual(
            defaults.string(forKey: "visClassicLastProfileName.mainWindow"),
            WindowManager.classicVisClassicProfileName
        )
        XCTAssertEqual(
            defaults.string(forKey: "visClassicLastProfileName.spectrumWindow"),
            WindowManager.classicVisClassicProfileName
        )
        XCTAssertTrue(defaults.bool(forKey: "visClassicFitToWidth.mainWindow"))
    }
}
