import XCTest
@testable import NullPlayer

final class VisualizationCycleSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VisualizationCycleSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsPerEngine() {
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .projectM, defaults: defaults), .off)
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .avs, defaults: defaults), .off)
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .tripex, defaults: defaults), .cycle)
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .geiss, defaults: defaults), .random)
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .goom, defaults: defaults), .random)
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .corona, defaults: defaults), .random)
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .smear, defaults: defaults), .random)
        XCTAssertEqual(VisualizationCycleSettings.interval(for: .geiss, defaults: defaults), 30.0, accuracy: 0.001)
    }

    func testPersistsPerEngineUnderTheExistingKeys() {
        VisualizationCycleSettings.save(mode: .random, for: .projectM, defaults: defaults)
        VisualizationCycleSettings.save(interval: 60, for: .projectM, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "projectM.cycleMode"), "random")
        XCTAssertEqual(defaults.double(forKey: "projectM.cycleInterval"), 60.0, accuracy: 0.001)
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .projectM, defaults: defaults), .random)
        XCTAssertEqual(VisualizationCycleSettings.mode(for: .avs, defaults: defaults), .off)
    }

    func testInvalidStoredValuesFallBackToDefaults() {
        defaults.set("shuffle", forKey: VisualizationCycleSettings.modeKey(for: .tripex))
        defaults.set(0.0, forKey: VisualizationCycleSettings.intervalKey(for: .tripex))

        XCTAssertEqual(VisualizationCycleSettings.mode(for: .tripex, defaults: defaults), .cycle)
        XCTAssertEqual(VisualizationCycleSettings.interval(for: .tripex, defaults: defaults), 30.0, accuracy: 0.001)
    }
}
