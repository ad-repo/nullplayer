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
            ModernSkinEngine.shouldApplyProfileDefault(
                forKey: key,
                preservePersistedProfiles: true,
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
}
