import XCTest
@testable import NullPlayer

final class VisualizationPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VisualizationPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMainWindowResetRemovesOnlyMainWindowVisualizationKeys() {
        seed(.mainWindow)
        seed(.spectrumWindow)
        defaults.set(64, forKey: "cavaBarCount")
        defaults.set("keep", forKey: "unrelatedPreference")

        VisualizationPreferences.reset(
            .mainWindow,
            defaults: defaults,
            applySkinDefaults: false,
            postNotifications: false
        )

        XCTAssertNil(defaults.object(forKey: "mainWindowVisMode"))
        XCTAssertNil(defaults.object(forKey: "cava.mainWindow.barCount"))
        XCTAssertNil(defaults.object(forKey: VisClassicBridge.PreferenceScope.mainWindow.lastProfileNameKey))
        XCTAssertNotNil(defaults.object(forKey: "spectrumQualityMode"))
        XCTAssertNotNil(defaults.object(forKey: VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey))
        XCTAssertEqual(defaults.integer(forKey: "cavaBarCount"), 64)
        XCTAssertEqual(defaults.string(forKey: "unrelatedPreference"), "keep")
    }

    func testSpectrumResetIncludesCurrentAndLegacyDecayKeys() {
        defaults.set("smooth", forKey: "spectrumDecayMode")
        defaults.set("smooth", forKey: "decayMode")

        VisualizationPreferences.reset(
            .spectrumWindow,
            defaults: defaults,
            applySkinDefaults: false,
            postNotifications: false
        )

        XCTAssertNil(defaults.object(forKey: "spectrumDecayMode"))
        XCTAssertNil(defaults.object(forKey: "decayMode"))
    }

    func testAllVisualizationResetPreservesNonVisualizationPreferences() {
        seed(.all)
        defaults.set("keep-folder", forKey: "customPresetsFolder")
        defaults.set(true, forKey: "rememberStateEnabled")
        defaults.set("keep", forKey: "BrowserVisibleTrackColumns")

        VisualizationPreferences.reset(
            .all,
            defaults: defaults,
            applySkinDefaults: false,
            postNotifications: false
        )

        for key in VisualizationPreferences.keys(for: .all) {
            XCTAssertNil(defaults.object(forKey: key), "Expected \(key) to be reset")
        }
        XCTAssertEqual(defaults.string(forKey: "customPresetsFolder"), "keep-folder")
        XCTAssertTrue(defaults.bool(forKey: "rememberStateEnabled"))
        XCTAssertEqual(defaults.string(forKey: "BrowserVisibleTrackColumns"), "keep")
    }

    func testAllVisualizationResetIncludesBrowserWindowCavaKeys() {
        let keys = VisualizationPreferences.keys(for: .all)

        XCTAssertTrue(keys.contains("cava.compactWindow.barCount"))
        XCTAssertTrue(keys.contains("cava.compactWindow.colorsCustomized"))
        XCTAssertFalse(keys.contains("cava.compactWindow.transparentBackground"))
        XCTAssertTrue(keys.contains("cava.libraryWindow.barCount"))
        XCTAssertTrue(keys.contains("cava.libraryWindow.colorsCustomized"))
        XCTAssertFalse(keys.contains("cava.libraryWindow.transparentBackground"))
    }

    func testBrowserBackdropModesSeparateCavaAndLegacyArtwork() {
        XCTAssertFalse(BrowserBackdropMode.off.showsCava)
        XCTAssertFalse(BrowserBackdropMode.off.showsArt)
        XCTAssertTrue(BrowserBackdropMode.cava.showsCava)
        XCTAssertFalse(BrowserBackdropMode.cava.showsArt)
        XCTAssertFalse(BrowserBackdropMode.art.showsCava)
        XCTAssertTrue(BrowserBackdropMode.art.showsArt)
        XCTAssertTrue(BrowserBackdropMode.cavaAndArt.showsCava)
        XCTAssertTrue(BrowserBackdropMode.cavaAndArt.showsArt)

        // Preserve the raw values already shipped on this branch: Album Art was 1 and Cava was 2.
        XCTAssertEqual(BrowserBackdropMode.art.rawValue, 1)
        XCTAssertEqual(BrowserBackdropMode.cava.rawValue, 2)
    }

    func testProjectMDisplayNamePreservesLegacyPreferenceValue() {
        XCTAssertEqual(VisualizationType.projectM.rawValue, "ProjectM (ProjectM)")
        XCTAssertEqual(VisualizationType.projectM.displayName, "ProjectM")
    }

    private func seed(_ scope: VisualizationPreferenceResetScope) {
        for key in VisualizationPreferences.keys(for: scope) {
            defaults.set("value", forKey: key)
        }
    }
}
