import AppKit
import XCTest
@testable import NullPlayer

final class WindowRestoreGeometryTests: XCTestCase {
    func testModernRestorePreservesSideDockedEqualizerPosition() {
        let savedEQFrame = NSRect(x: 375, y: 500, width: 275, height: 116)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedEQFrame,
            kind: .equalizer,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.minX, savedEQFrame.minX, accuracy: 0.001)
        XCTAssertEqual(restored.width, 275, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedEQFrame.maxY, accuracy: 0.001)
    }

    func testModernRestorePreservesStretchablePlaylistWidthAndPosition() {
        let savedPlaylistFrame = NSRect(x: 100, y: 384, width: 550, height: 116)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedPlaylistFrame,
            kind: .playlist,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.minX, savedPlaylistFrame.minX, accuracy: 0.001)
        XCTAssertEqual(restored.width, savedPlaylistFrame.width, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedPlaylistFrame.maxY, accuracy: 0.001)
    }

    func testModernRestorePreservesStretchableSpectrumWidth() {
        let savedSpectrumFrame = NSRect(x: 100, y: 268, width: 550, height: 140)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedSpectrumFrame,
            kind: .spectrum,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.width, savedSpectrumFrame.width, accuracy: 0.001)
        XCTAssertEqual(restored.height, savedSpectrumFrame.height, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedSpectrumFrame.maxY, accuracy: 0.001)
    }

    func testModernRestorePreservesStretchableNetworkMonitorHeight() {
        let savedNetworkMonitorFrame = NSRect(x: 100, y: 252, width: 275, height: 132)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedNetworkMonitorFrame,
            kind: .networkMonitor,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.height, savedNetworkMonitorFrame.height, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedNetworkMonitorFrame.maxY, accuracy: 0.001)
    }

    func testModernRestoreClampsShortNetworkMonitorHeightToBaseline() {
        let savedNetworkMonitorFrame = NSRect(x: 100, y: 280, width: 275, height: 90)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedNetworkMonitorFrame,
            kind: .networkMonitor,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.height, 116, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedNetworkMonitorFrame.maxY, accuracy: 0.001)
    }

    func testClassicRestorePreservesStretchableNetworkMonitorHeight() {
        let savedNetworkMonitorFrame = NSRect(x: 650, y: 420, width: 275, height: 132)

        let restored = WindowManager.normalizedClassicNetworkMonitorRestoredFrame(
            savedNetworkMonitorFrame,
            minimumHeight: 116
        )

        XCTAssertEqual(restored.height, savedNetworkMonitorFrame.height, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedNetworkMonitorFrame.maxY, accuracy: 0.001)
    }

    func testClassicRestoreClampsShortNetworkMonitorHeightToMinimum() {
        let savedNetworkMonitorFrame = NSRect(x: 650, y: 440, width: 275, height: 90)

        let restored = WindowManager.normalizedClassicNetworkMonitorRestoredFrame(
            savedNetworkMonitorFrame,
            minimumHeight: 116
        )

        XCTAssertEqual(restored.height, 116, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedNetworkMonitorFrame.maxY, accuracy: 0.001)
    }
}
