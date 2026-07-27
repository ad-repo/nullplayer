import AppKit
import XCTest
@testable import NullPlayer

final class CavaSettingsTests: XCTestCase {
    private var originalValues: [String: Any] = [:]

    private var preferenceKeys: [String] {
        CavaSettings.Scope.allCases.flatMap { CavaSettings.preferenceKeys(for: $0) }
    }

    override func setUp() {
        super.setUp()
        originalValues = [:]
        for key in preferenceKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                originalValues[key] = value
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in preferenceKeys {
            if let value = originalValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
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

    func testMainWindowModeIsForcedMonoWithoutChangingWindowMode() {
        CavaSettings.mode = .stereo
        CavaSettings.setMode(.stereo, for: .mainWindow)

        XCTAssertEqual(CavaSettings.mode(for: .mainWindow), .mono)
        XCTAssertEqual(CavaSettings.mode, .stereo)
    }

    func testMainWindowTuningIsIndependentFromStandaloneWindow() {
        CavaSettings.barCount = 64
        CavaSettings.noiseReduction = 0.9
        CavaSettings.bassTilt = 0.7

        CavaSettings.setBarCount(19, for: .mainWindow)
        CavaSettings.setNoiseReduction(0.5, for: .mainWindow)
        CavaSettings.setBassTilt(0.15, for: .mainWindow)

        XCTAssertEqual(CavaSettings.barCount(for: .mainWindow), 19)
        XCTAssertEqual(CavaSettings.noiseReduction(for: .mainWindow), 0.5, accuracy: 0.001)
        XCTAssertEqual(CavaSettings.bassTilt(for: .mainWindow), 0.15, accuracy: 0.001)
        XCTAssertEqual(CavaSettings.barCount, 64)
        XCTAssertEqual(CavaSettings.noiseReduction, 0.9, accuracy: 0.001)
        XCTAssertEqual(CavaSettings.bassTilt, 0.7, accuracy: 0.001)
    }

    func testMainWindowResetTuningLeavesStandaloneWindowUntouched() {
        CavaSettings.barCount = 48
        CavaSettings.setBarCount(12, for: .mainWindow)

        CavaSettings.resetTuning(scope: .mainWindow)

        XCTAssertEqual(CavaSettings.barCount(for: .mainWindow), CavaSettings.defaultBarCount)
        XCTAssertEqual(CavaSettings.barCount, 48)
    }

    func testSkinChangeClearsCustomColorFlagsForBothScopesWithoutDeletingColors() throws {
        let fireIndex = try XCTUnwrap(CavaSettings.colorSchemes.firstIndex { $0.name == "Fire" })
        let iceIndex = try XCTUnwrap(CavaSettings.colorSchemes.firstIndex { $0.name == "Ice" })
        let fire = CavaSettings.colorSchemes[fireIndex]
        let ice = CavaSettings.colorSchemes[iceIndex]

        CavaSettings.setLowGradientColor(fire.low, for: .cavaWindow)
        CavaSettings.setHighGradientColor(fire.high, for: .cavaWindow)
        CavaSettings.setHasCustomColors(true, for: .cavaWindow)
        CavaSettings.setLowGradientColor(ice.low, for: .mainWindow)
        CavaSettings.setHighGradientColor(ice.high, for: .mainWindow)
        CavaSettings.setHasCustomColors(true, for: .mainWindow)

        CavaSettings.resetCustomColorsForSkinChange()

        XCTAssertFalse(CavaSettings.hasCustomColors(for: .cavaWindow))
        XCTAssertFalse(CavaSettings.hasCustomColors(for: .mainWindow))
        XCTAssertEqual(CavaSettings.currentColorSchemeIndex(for: .cavaWindow), fireIndex)
        XCTAssertEqual(CavaSettings.currentColorSchemeIndex(for: .mainWindow), iceIndex)
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
