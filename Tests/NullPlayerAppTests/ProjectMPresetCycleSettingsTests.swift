import XCTest
@testable import NullPlayer

final class ProjectMPresetCycleSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ProjectMPresetCycleSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToManualModeAndThirtySecondInterval() {
        XCTAssertEqual(ProjectMPresetCycleSettings.loadMode(defaults: defaults), .off)
        XCTAssertEqual(ProjectMPresetCycleSettings.loadInterval(defaults: defaults), 30.0, accuracy: 0.001)
    }

    func testPersistsAutoRandomModeAndInterval() {
        ProjectMPresetCycleSettings.save(mode: .random, interval: 60.0, defaults: defaults)

        XCTAssertEqual(ProjectMPresetCycleSettings.loadMode(defaults: defaults), .random)
        XCTAssertEqual(ProjectMPresetCycleSettings.loadInterval(defaults: defaults), 60.0, accuracy: 0.001)
    }

    func testInvalidStoredModeFallsBackToManual() {
        defaults.set("shuffle", forKey: ProjectMPresetCycleSettings.DefaultsKey.cycleMode)

        XCTAssertEqual(ProjectMPresetCycleSettings.loadMode(defaults: defaults), .off)
    }

    func testInvalidStoredIntervalFallsBackToThirtySeconds() {
        defaults.set(0.0, forKey: ProjectMPresetCycleSettings.DefaultsKey.cycleInterval)

        XCTAssertEqual(ProjectMPresetCycleSettings.loadInterval(defaults: defaults), 30.0, accuracy: 0.001)
    }
}
