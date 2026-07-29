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

    func testExplicitSkinChangeResetsOmittedVisClassicAppearanceToOpaqueDefaults() {
        let mainScope = VisClassicBridge.PreferenceScope.mainWindow
        let spectrumScope = VisClassicBridge.PreferenceScope.spectrumWindow
        defaults.set(true, forKey: mainScope.transparentBgKey)
        defaults.set(true, forKey: spectrumScope.transparentBgKey)
        defaults.set(0.9, forKey: mainScope.opacityKey)
        defaults.set(0.9, forKey: spectrumScope.opacityKey)

        let applied = ModernSkinEngine.applyVisClassicAppearanceDefaults(
            from: emptyVisClassicConfig(),
            windowSpectrumTransparentBackground: nil,
            preservePersistedPreferences: false,
            defaults: defaults
        )

        XCTAssertFalse(defaults.bool(forKey: mainScope.transparentBgKey))
        XCTAssertFalse(defaults.bool(forKey: spectrumScope.transparentBgKey))
        XCTAssertEqual(defaults.double(forKey: mainScope.opacityKey), 1.0)
        XCTAssertEqual(defaults.double(forKey: spectrumScope.opacityKey), 1.0)
        XCTAssertEqual(applied.mainTransparentBackground, false)
        XCTAssertEqual(applied.spectrumTransparentBackground, false)
        XCTAssertEqual(applied.mainOpacity, 1.0)
        XCTAssertEqual(applied.spectrumOpacity, 1.0)
    }

    func testLaunchPreservesAppearanceWhenIncomingSkinOmitsIt() {
        let mainScope = VisClassicBridge.PreferenceScope.mainWindow
        let spectrumScope = VisClassicBridge.PreferenceScope.spectrumWindow
        defaults.set(true, forKey: mainScope.transparentBgKey)
        defaults.set(true, forKey: spectrumScope.transparentBgKey)
        defaults.set(0.9, forKey: mainScope.opacityKey)
        defaults.set(0.9, forKey: spectrumScope.opacityKey)

        let applied = ModernSkinEngine.applyVisClassicAppearanceDefaults(
            from: emptyVisClassicConfig(),
            windowSpectrumTransparentBackground: nil,
            preservePersistedPreferences: true,
            defaults: defaults
        )

        XCTAssertTrue(defaults.bool(forKey: mainScope.transparentBgKey))
        XCTAssertTrue(defaults.bool(forKey: spectrumScope.transparentBgKey))
        XCTAssertEqual(defaults.double(forKey: mainScope.opacityKey), 0.9)
        XCTAssertEqual(defaults.double(forKey: spectrumScope.opacityKey), 0.9)
        XCTAssertEqual(
            applied,
            ModernSkinEngine.AppliedVisClassicAppearanceDefaults(
                mainTransparentBackground: nil,
                spectrumTransparentBackground: nil,
                mainOpacity: nil,
                spectrumOpacity: nil,
                mainChanged: false,
                spectrumChanged: false
            )
        )
    }

    func testVisualizationConfigTransparencyOverridesWindowLevelSeed() {
        let config = VisClassicVisualizationConfig(
            mainWindowProfile: nil,
            spectrumWindowProfile: nil,
            mainWindowFitToWidth: nil,
            spectrumWindowFitToWidth: nil,
            mainWindowTransparentBackground: true,
            spectrumWindowTransparentBackground: false,
            mainWindowOpacity: 0.4,
            spectrumWindowOpacity: 0.6
        )

        let applied = ModernSkinEngine.applyVisClassicAppearanceDefaults(
            from: config,
            windowSpectrumTransparentBackground: true,
            preservePersistedPreferences: false,
            defaults: defaults
        )

        XCTAssertEqual(applied.mainTransparentBackground, true)
        XCTAssertEqual(applied.spectrumTransparentBackground, false)
        XCTAssertEqual(applied.mainOpacity, 0.4)
        XCTAssertEqual(applied.spectrumOpacity, 0.6)
    }

    private func emptyVisClassicConfig() -> VisClassicVisualizationConfig {
        VisClassicVisualizationConfig(
            mainWindowProfile: nil,
            spectrumWindowProfile: nil,
            mainWindowFitToWidth: nil,
            spectrumWindowFitToWidth: nil,
            mainWindowTransparentBackground: nil,
            spectrumWindowTransparentBackground: nil,
            mainWindowOpacity: nil,
            spectrumWindowOpacity: nil
        )
    }
}
