import AppKit
import XCTest
@testable import NullPlayer

final class CenterStackWindowTests: XCTestCase {
    private typealias Kind = WindowManager.CenterStackWindowKind

    /// Every feature window's visibility and frame survive a saved state, under the flat keys every
    /// earlier build wrote. A kind whose `AppState` fields are missing from `CodingKeys` or the
    /// decoder comes back closed with no frame, and fails here.
    func testEveryFeatureWindowSurvivesASavedStateUnderItsFlatKeys() throws {
        var state = AppStateManager.AppState.fixture()
        for (index, kind) in Kind.featureWindows.enumerated() {
            state[keyPath: kind.savedVisibility] = true
            state[keyPath: kind.savedFrame] = NSStringFromRect(NSRect(x: index, y: 20, width: 300, height: 100))
        }
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppStateManager.AppState.self, from: data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        for kind in Kind.featureWindows {
            XCTAssertTrue(decoded[keyPath: kind.savedVisibility], "\(kind)")
            XCTAssertEqual(decoded[keyPath: kind.savedFrame], state[keyPath: kind.savedFrame], "\(kind)")
            let name = kind.stateKey
            XCTAssertNotNil(json["is\(name.prefix(1).uppercased())\(name.dropFirst())Visible"], "\(kind)")
            XCTAssertNotNil(json["\(name)WindowFrame"], "\(kind)")
        }
    }

    /// The stack orders are permutations of the feature windows, so a new kind joins them by
    /// existing — the repair, the UI Size reflow and Snap To Default never skip it.
    func testStackOrdersCoverEveryKindOnce() {
        XCTAssertEqual(Set(Kind.stackOrder), Set(Kind.featureWindows))
        XCTAssertEqual(Kind.stackOrder.count, Kind.featureWindows.count)
        XCTAssertEqual(Kind.columnOrder.count, Kind.allCases.count)
        XCTAssertEqual(Set(Kind.columnOrder), Set(Kind.allCases))
        XCTAssertEqual(Array(Kind.stackOrder.prefix(2)), [.spectrum, .waveform])
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
