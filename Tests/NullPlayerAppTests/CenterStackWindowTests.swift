import AppKit
import XCTest
@testable import NullPlayer

final class CenterStackWindowTests: XCTestCase {
    private typealias Kind = WindowManager.CenterStackWindowKind
    private typealias Feature = WindowManager.CenterStackFeature

    /// The keys every earlier build wrote. Spelled out: they are the on-disk contract, and must not
    /// follow a renamed case.
    private static let savedKeys: [Feature: (visible: String, frame: String)] = [
        .spectrum: ("isSpectrumVisible", "spectrumWindowFrame"),
        .audioAnalysis: ("isAudioAnalysisVisible", "audioAnalysisWindowFrame"),
        .peppyMeter: ("isPeppyMeterVisible", "peppyMeterWindowFrame"),
        .art: ("isArtVisible", "artWindowFrame"),
        .networkMonitor: ("isNetworkMonitorVisible", "networkMonitorWindowFrame"),
        .cava: ("isCavaVisible", "cavaWindowFrame"),
        .sonos: ("isSonosVisible", "sonosWindowFrame"),
        .waveform: ("isWaveformVisible", "waveformWindowFrame"),
    ]

    /// Every feature window's visibility and frame survive a saved state, under the flat keys every
    /// earlier build wrote. A feature whose `AppState` fields are missing from `CodingKeys` or the
    /// decoder comes back closed with no frame, and fails here.
    func testEveryFeatureWindowSurvivesASavedStateUnderItsFlatKeys() throws {
        var state = AppStateManager.AppState.fixture()
        for (index, feature) in Feature.allCases.enumerated() {
            state[keyPath: feature.savedVisibility] = true
            state[keyPath: feature.savedFrame] = NSStringFromRect(NSRect(x: index, y: 20, width: 300, height: 100))
        }
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppStateManager.AppState.self, from: data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        for feature in Feature.allCases {
            XCTAssertTrue(decoded[keyPath: feature.savedVisibility], "\(feature)")
            XCTAssertEqual(decoded[keyPath: feature.savedFrame], state[keyPath: feature.savedFrame], "\(feature)")
            let keys = try XCTUnwrap(Self.savedKeys[feature], "\(feature)")
            XCTAssertEqual(json[keys.visible] as? Bool, true, "\(feature)")
            XCTAssertEqual(json[keys.frame] as? String, state[keyPath: feature.savedFrame], "\(feature)")
        }
    }

    /// The stack orders are permutations, so a new feature joins them by existing — the repair, the
    /// UI Size reflow and Snap To Default never skip it.
    func testStackOrdersCoverEveryKindOnce() {
        XCTAssertEqual(Feature.stackOrder.count, Feature.allCases.count)
        XCTAssertEqual(Set(Feature.stackOrder), Set(Feature.allCases))
        XCTAssertEqual(Kind.columnOrder.count, Kind.allCases.count)
        XCTAssertEqual(Set(Kind.columnOrder), Set(Kind.allCases))
    }

    /// The repair walks the whole column: a window docked under each in `columnOrder` is pulled
    /// flush beneath the one above, whatever its kind.
    func testRepairPullsEveryKindFlushBelowTheOneAbove() throws {
        let main = NSRect(x: 100, y: 800, width: 275, height: Skin.mainWindowSize.height)
        // Each window sits 5 pt below where it docks: inside the repair's tolerance.
        var frames: [Kind: NSRect] = [:]
        for (index, kind) in Kind.columnOrder.enumerated() {
            let top = main.minY - CGFloat(index) * 100 - 5
            frames[kind] = NSRect(x: main.minX, y: top - 100, width: 275, height: 100)
        }
        let repaired = AppStateManager.repairClassicCenterStackFrames(mainFrame: main, frames: frames, scale: 1)

        XCTAssertTrue(repaired.repaired)
        var anchor = repaired.mainFrame
        for kind in Kind.columnOrder {
            let frame = try XCTUnwrap(repaired.frames[kind], "\(kind)")
            XCTAssertEqual(frame.maxY, anchor.minY, accuracy: 0.001, "\(kind)")
            anchor = frame
        }
    }
}
