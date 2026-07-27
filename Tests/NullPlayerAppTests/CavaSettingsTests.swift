import AppKit
import XCTest
@testable import NullPlayer

final class CavaSettingsTests: XCTestCase {
    private let modeKey = "cavaMode"
    private var originalModeValue: Any?

    override func setUp() {
        super.setUp()
        originalModeValue = UserDefaults.standard.object(forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: modeKey)
    }

    override func tearDown() {
        if let originalModeValue {
            UserDefaults.standard.set(originalModeValue, forKey: modeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: modeKey)
        }
        super.tearDown()
    }

    func testModeDefaultsToStereoWhenPreferenceIsAbsent() {
        XCTAssertEqual(CavaSettings.mode, .stereo)
    }

    func testExplicitMonoPreferenceIsPreserved() {
        CavaSettings.mode = .mono
        XCTAssertEqual(CavaSettings.mode, .mono)
    }

    func testClassicStackRepairIncludesCavaAfterFlow() throws {
        let main = NSRect(x: 100, y: 500, width: 275, height: Skin.mainWindowSize.height)
        let rowHeight = SkinElements.SpectrumWindow.windowSize.height
        let flow = NSRect(
            x: 103,
            y: main.minY - rowHeight + 5,
            width: 300,
            height: rowHeight
        )
        let cava = NSRect(
            x: 104,
            y: flow.minY - rowHeight + 7,
            width: 310,
            height: rowHeight
        )

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: nil,
            playlistFrame: nil,
            spectrumFrame: nil,
            waveformFrame: nil,
            audioAnalysisFrame: nil,
            peppyMeterFrame: nil,
            networkMonitorFrame: flow,
            cavaFrame: cava,
            scale: 1
        )

        let repairedFlow = try XCTUnwrap(repaired.networkMonitorFrame)
        let repairedCava = try XCTUnwrap(repaired.cavaFrame)
        XCTAssertEqual(repairedFlow.maxY, repaired.mainFrame.minY, accuracy: 0.001)
        XCTAssertEqual(repairedCava.maxY, repairedFlow.minY, accuracy: 0.001)
        XCTAssertEqual(repairedCava.minX, repaired.mainFrame.minX, accuracy: 0.001)
        XCTAssertTrue(repaired.repaired)
    }
}
