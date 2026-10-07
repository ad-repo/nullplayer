import Foundation
import XCTest
@testable import NullPlayer
import NullPlayerCore

/// Each EQ layout keeps its own curve across a relaunch: Classic's 10 bands and Original's 21 are
/// saved side by side and restored exactly, never remapped from one another.
final class AppStateEQLayoutTests: XCTestCase {

    private let classic: [Float] = [12, 0, 12, 11.25, 0, -3, 0, 0, 4, 0]
    private let modern: [Float] = (0..<21).map { Float($0 % 7) - 3 }
    private var saved: [String: [Float]] { ["classic10": classic, "modern21": modern] }
    /// Each layout paired with the other one, so every engine test runs in both directions.
    private let directions: [(EQConfiguration, EQConfiguration)] = [(.classic10, .modern21), (.modern21, .classic10)]

    private func curve(_ layout: EQConfiguration) -> [Float] {
        layout == .classic10 ? classic : modern
    }

    /// An engine in `layout`, whatever UI mode the test host's defaults would start it in.
    private func makeEngine(in layout: EQConfiguration) -> AudioEngine {
        let engine = AudioEngine()
        engine.applyEQLayout(forModernUI: layout == .modern21)
        XCTAssertEqual(engine.eqConfiguration, layout)
        return engine
    }

    private func liveGains(_ engine: AudioEngine) -> [Float] {
        (0..<engine.eqConfiguration.bandCount).map { engine.getEQBand($0) }
    }

    func testBothLayoutsSurviveEncodeAndDecode() throws {
        var state = AppStateManager.AppState.fixture()
        state.eqBands = classic
        state.eqBandsByLayout = saved
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppStateManager.AppState.self, from: data)
        XCTAssertEqual(decoded.eqBandsByLayout, saved)
        XCTAssertEqual(decoded.eqBands, classic)
    }

    /// A state written before `eqBandsByLayout` existed carries only the active layout's bands.
    func testOlderStateIsUpgradedFromItsActiveBands() throws {
        for bands in [classic, modern] {
            var state = AppStateManager.AppState.fixture()
            state.eqBands = bands
            let data = try JSONEncoder().encode(state)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json.removeValue(forKey: "eqBandsByLayout")
            let legacy = try JSONSerialization.data(withJSONObject: json)

            let decoded = try JSONDecoder().decode(AppStateManager.AppState.self, from: legacy)
            let layout = try XCTUnwrap(EQConfiguration.persistedLayout(forBandCount: bands.count))
            XCTAssertEqual(decoded.eqBandsByLayout, [layout.name: bands])
        }
    }

    func testRestoreAppliesTheActiveLayoutAndKeepsTheOtherExact() {
        for (active, other) in directions {
            let engine = makeEngine(in: active)
            engine.restoreEQGains(saved)

            XCTAssertEqual(engine.canonicalGains, saved)
            XCTAssertEqual(liveGains(engine), curve(active))

            // A live switch to the other family lands on its own saved curve, not a remap.
            engine.applyEQLayout(forModernUI: other == .modern21)
            XCTAssertEqual(liveGains(engine), curve(other))
        }
    }

    func testRestoreSeedsAnUnsavedActiveLayoutFromTheSavedOne() {
        for (active, source) in directions {
            let engine = makeEngine(in: active)
            engine.restoreEQGains([source.name: curve(source)])

            let expected = EQBandRemapper.remap(gains: curve(source), from: source, to: active)
            XCTAssertEqual(liveGains(engine), expected)
            XCTAssertEqual(engine.canonicalGains, [source.name: curve(source), active.name: expected])
        }
    }

    /// `canonicalGains` is what gets saved, so it must always match what the node plays: the
    /// active layout has an entry from the start, and a band edit lands in it.
    func testCanonicalGainsFollowTheLiveNode() {
        for (layout, _) in directions {
            let engine = makeEngine(in: layout)
            XCTAssertEqual(engine.canonicalGains[layout.name], liveGains(engine))

            engine.setEQBand(2, gain: 7.5)
            engine.setEQBand(3, gain: 40)  // clamped to +12
            XCTAssertEqual(engine.canonicalGains[layout.name], liveGains(engine))
            XCTAssertEqual(engine.canonicalGains[layout.name]?[2], 7.5)
            XCTAssertEqual(engine.canonicalGains[layout.name]?[3], 12)
        }
    }
}
