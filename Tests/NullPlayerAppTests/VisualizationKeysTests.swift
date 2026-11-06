import AppKit
import XCTest
@testable import NullPlayer

/// The standard visualization keys (`VisualizationKey`): ⌘↓/⌘↑ step the engine, ⌘→/⌘← the preset,
/// and a ⌘-arrow is never seek or volume.
@MainActor
final class VisualizationKeysTests: XCTestCase {
    private let protectedKeys = ["mainWindowFlameStyle", "mainWindowLightningStyle", "mainWindowMatrixColorScheme",
                                 "mainWindowEKGStyle"] + CavaSettings.preferenceKeys(for: .mainWindow)
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        saved = [:]
        for key in protectedKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in protectedKeys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                         keyCode: code)!
    }

    func testCommandArrowsAreTheStandardKeys() {
        guard case .engine(1)? = VisualizationKey(key(125, .command)) else { return XCTFail("⌘↓") }
        guard case .engine(-1)? = VisualizationKey(key(126, .command)) else { return XCTFail("⌘↑") }
        guard case .preset(1)? = VisualizationKey(key(124, .command)) else { return XCTFail("⌘→") }
        guard case .preset(-1)? = VisualizationKey(key(123, .command)) else { return XCTFail("⌘←") }
        guard case .preset(1)? = VisualizationKey(key(124, [.command, .shift])) else { return XCTFail("⌘⇧→") }
    }

    func testPlainArrowsAndOtherCommandKeysAreNotVisualizationKeys() {
        for code: UInt16 in [123, 124, 125, 126] { XCTAssertNil(VisualizationKey(key(code))) }
        XCTAssertNil(VisualizationKey(key(124, .shift)))
        XCTAssertNil(VisualizationKey(key(40, .command)))   // ⌘K
    }

    func testCommandArrowIsNeverSeekOrVolume() {
        for code: UInt16 in [123, 124, 125, 126] {
            XCTAssertFalse(MainWindowKeys.performArrow(key(code, .command)))
        }
    }

    func testSteppingWrapsBothWays() {
        let list = [1, 2, 3]
        XCTAssertEqual(list.stepping(from: 3, by: 1), 1)
        XCTAssertEqual(list.stepping(from: 1, by: -1), 3)
        XCTAssertEqual(list.stepping(from: 2, by: 4), 3)
        XCTAssertEqual(list.stepping(from: 9, by: 1), 2, "an element not in the list steps from the first")
    }

    func testEngineStepsFollowTheMenuOrder() {
        let all = VisualizationType.allCases
        XCTAssertEqual(all.last?.advanced(by: 1), all.first)
        XCTAssertEqual(all.first?.advanced(by: -1), all.last)
        XCTAssertEqual(VisualizationType.projectM.advanced(by: 1), all[1])
    }

    func testMainWindowModeStepsBothWaysAndOffStepsToClassic() {
        XCTAssertEqual(MainWindowVisMode.none.advanced(by: 1), .spectrum)
        XCTAssertEqual(MainWindowVisMode.none.advanced(by: -1), .spectrum)
        for mode in MainWindowVisMode.visualizationOrder {
            XCTAssertEqual(mode.advanced(by: 1).advanced(by: -1), mode, "\(mode)")
        }
    }

    func testSpectrumModeStepsBothWays() {
        for mode in SpectrumQualityMode.visualizationOrder {
            XCTAssertEqual(mode.advanced(by: -1).advanced(by: 1), mode, "\(mode)")
        }
    }

    func testArtGroupStepsToTheNextGroupsFirstEffect() {
        let groups = ArtVisEffect.groups
        for (index, group) in groups.enumerated() {
            let next = groups[(index + 1) % groups.count].effects[0]
            let previous = groups[(index - 1 + groups.count) % groups.count].effects[0]
            for effect in group.effects {
                XCTAssertEqual(effect.advancedGroup(by: 1), next, "\(effect)")
                XCTAssertEqual(effect.advancedGroup(by: -1), previous, "\(effect)")
            }
        }
    }

    func testMainWindowStyleStepsTheModesOwnList() {
        XCTAssertTrue(MainWindowVisStyle.step(.fire, by: 1, overlay: nil))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mainWindowFlameStyle"), FlameStyle.allCases[1].rawValue)
        XCTAssertTrue(MainWindowVisStyle.step(.fire, by: -2, overlay: nil))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mainWindowFlameStyle"), FlameStyle.allCases.last?.rawValue)

        XCTAssertTrue(MainWindowVisStyle.step(.ekg, by: 1, overlay: nil))
        XCTAssertNotNil(UserDefaults.standard.string(forKey: "mainWindowEKGStyle"))
    }

    func testModesWithoutAListRefuseTheStyleKeys() {
        for mode: MainWindowVisMode in [.none, .spectrum, .enhanced, .ultra, .cosmic, .snow, .visClassicExact] {
            XCTAssertFalse(MainWindowVisStyle.step(mode, by: 1, overlay: nil), "\(mode)")
        }
    }

    func testCavaStepsFromTheSkinsColoursThroughThePresetsAndBack() {
        XCTAssertEqual(CavaSettings.colorSchemeChoice(for: .mainWindow), -1)
        XCTAssertTrue(MainWindowVisStyle.step(.cava, by: 1, overlay: nil))
        XCTAssertEqual(CavaSettings.colorSchemeChoice(for: .mainWindow), 0)
        XCTAssertTrue(CavaSettings.hasCustomColors(for: .mainWindow))
        XCTAssertTrue(MainWindowVisStyle.step(.cava, by: -1, overlay: nil))
        XCTAssertEqual(CavaSettings.colorSchemeChoice(for: .mainWindow), -1)
        XCTAssertFalse(CavaSettings.hasCustomColors(for: .mainWindow))
        XCTAssertTrue(MainWindowVisStyle.step(.cava, by: -1, overlay: nil))
        XCTAssertEqual(CavaSettings.colorSchemeChoice(for: .mainWindow), CavaSettings.colorSchemes.count - 1)
    }
}
