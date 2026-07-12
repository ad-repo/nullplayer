import XCTest
@testable import NullPlayer

final class ModernSkinVisualizationPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ModernSkinVisualizationPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPreferredSkinLaunchPreservesExistingScopedProfile() {
        let key = VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey
        defaults.set("Green", forKey: key)

        XCTAssertFalse(
            ModernSkinEngine.shouldApplyProfileDefault(
                forKey: key,
                preservePersistedProfiles: true,
                defaults: defaults
            )
        )
        XCTAssertEqual(defaults.string(forKey: key), "Green")
    }

    func testPreferredSkinLaunchAppliesProfileWhenNoSelectionExists() {
        let key = VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey

        XCTAssertTrue(
            ModernSkinEngine.shouldApplyDefault(
                forKey: key,
                preservePersistedPreferences: true,
                defaults: defaults
            )
        )
    }

    func testExplicitSkinChangeAppliesNewSkinProfile() {
        let key = VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey
        defaults.set("Green", forKey: key)

        XCTAssertTrue(
            ModernSkinEngine.shouldApplyProfileDefault(
                forKey: key,
                preservePersistedProfiles: false,
                defaults: defaults
            )
        )
    }

    func testPreferredSkinLaunchPreservesExistingMainWindowVisualizationSettings() {
        defaults.set(MainWindowVisMode.fire.rawValue, forKey: "mainWindowVisMode")
        defaults.set(MainWindowVisMode.fire.rawValue, forKey: "modernMainWindowVisMode")
        defaults.set(FlameIntensity.intense.rawValue, forKey: "mainWindowFlameIntensity")

        XCTAssertFalse(
            ModernSkinEngine.shouldApplyDefault(
                forKey: "mainWindowVisMode",
                preservePersistedPreferences: true,
                defaults: defaults
            )
        )
        XCTAssertFalse(
            ModernSkinEngine.shouldApplyDefault(
                forKey: "modernMainWindowVisMode",
                preservePersistedPreferences: true,
                defaults: defaults
            )
        )
        XCTAssertFalse(
            ModernSkinEngine.shouldApplyDefault(
                forKey: "mainWindowFlameIntensity",
                preservePersistedPreferences: true,
                defaults: defaults
            )
        )
    }

    func testExplicitSkinChangeAppliesMainWindowVisualizationDefaults() {
        defaults.set(MainWindowVisMode.fire.rawValue, forKey: "mainWindowVisMode")
        defaults.set(FlameIntensity.intense.rawValue, forKey: "mainWindowFlameIntensity")

        XCTAssertTrue(
            ModernSkinEngine.shouldApplyDefault(
                forKey: "mainWindowVisMode",
                preservePersistedPreferences: false,
                defaults: defaults
            )
        )
        XCTAssertTrue(
            ModernSkinEngine.shouldApplyDefault(
                forKey: "mainWindowFlameIntensity",
                preservePersistedPreferences: false,
                defaults: defaults
            )
        )
    }

    func testForcedProfileDefaultOverridesExistingSelectionOnPreservedLaunch() {
        let key = VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey
        defaults.set("Green", forKey: key)

        XCTAssertTrue(
            ModernSkinEngine.shouldApplyProfileDefault(
                forKey: key,
                preservePersistedProfiles: true,
                forceProfileDefaults: true,
                defaults: defaults
            )
        )
    }
}
