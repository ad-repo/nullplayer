import XCTest
@testable import NullPlayer

final class VisClassicBridgePersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VisClassicBridgePersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testReloadPersistedSettingsRehydratesAllIndependentCoreOptions() throws {
        let scope = VisClassicBridge.PreferenceScope.spectrumWindow
        defaults.set(true, forKey: scope.fitToWidthKey)
        defaults.set(false, forKey: scope.transparentBgKey)

        let bridge = try XCTUnwrap(
            VisClassicBridge(width: 320, height: 96, scope: scope, defaults: defaults)
        )
        let profiles = bridge.availableProfiles()
        let initialProfile = try XCTUnwrap(profiles.first)
        let targetProfile = profiles.dropFirst().first ?? initialProfile

        XCTAssertTrue(bridge.loadProfile(named: initialProfile.name))
        XCTAssertTrue(bridge.fitToWidthEnabled())
        XCTAssertFalse(bridge.transparentBackgroundEnabled())

        defaults.set(targetProfile.name, forKey: scope.lastProfileNameKey)
        defaults.set(false, forKey: scope.fitToWidthKey)
        defaults.set(true, forKey: scope.transparentBgKey)

        bridge.reloadPersistedSettings()

        XCTAssertEqual(bridge.currentProfileName, targetProfile.name)
        XCTAssertFalse(bridge.fitToWidthEnabled())
        XCTAssertTrue(bridge.transparentBackgroundEnabled())
    }
}
