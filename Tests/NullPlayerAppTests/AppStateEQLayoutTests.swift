import Foundation
import XCTest
@testable import NullPlayer
import NullPlayerCore

/// Each EQ layout keeps its own curve across a relaunch: Classic's 10 bands and Original's 21 are
/// saved side by side and restored exactly, never remapped from one another.
final class AppStateEQLayoutTests: XCTestCase {

    private let classic: [Float] = [12, 0, 12, 11.25, 0, -3, 0, 0, 4, 0]
    private let modern: [Float] = (0..<21).map { Float($0 % 7) - 3 }

    private func makeState(eqBands: [Float], eqBandsByLayout: [String: [Float]]) -> AppStateManager.AppState {
        AppStateManager.AppState(
            isPlaylistVisible: false,
            isEqualizerVisible: false,
            isPlexBrowserVisible: false,
            isProjectMVisible: false,
            mainWindowFrame: nil,
            playlistWindowFrame: nil,
            equalizerWindowFrame: nil,
            plexBrowserWindowFrame: nil,
            projectMWindowFrame: nil,
            volume: 0.5,
            balance: 0,
            shuffleEnabled: false,
            repeatEnabled: false,
            gaplessPlaybackEnabled: false,
            volumeNormalizationEnabled: false,
            sweetFadeEnabled: false,
            sweetFadeDuration: 5,
            eqEnabled: true,
            eqAutoEnabled: false,
            eqPreamp: 0,
            eqBands: eqBands,
            eqBandsByLayout: eqBandsByLayout,
            playlistTracks: [],
            currentTrackIndex: -1,
            playbackPosition: 0,
            wasPlaying: false,
            timeDisplayMode: "elapsed",
            isAlwaysOnTop: false
        )
    }

    func testBothLayoutsSurviveEncodeAndDecode() throws {
        let saved = ["classic10": classic, "modern21": modern]
        let data = try JSONEncoder().encode(makeState(eqBands: classic, eqBandsByLayout: saved))
        let decoded = try JSONDecoder().decode(AppStateManager.AppState.self, from: data)
        XCTAssertEqual(decoded.eqBandsByLayout, saved)
        XCTAssertEqual(decoded.eqBands, classic)
    }

    /// A state written before `eqBandsByLayout` existed carries only the active layout's bands.
    func testOlderStateIsUpgradedFromItsActiveBands() throws {
        for bands in [classic, modern] {
            let data = try JSONEncoder().encode(makeState(eqBands: bands, eqBandsByLayout: [:]))
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json.removeValue(forKey: "eqBandsByLayout")
            let legacy = try JSONSerialization.data(withJSONObject: json)

            let decoded = try JSONDecoder().decode(AppStateManager.AppState.self, from: legacy)
            let layout = try XCTUnwrap(EQConfiguration.persistedLayout(forBandCount: bands.count))
            XCTAssertEqual(decoded.eqBandsByLayout, [layout.name: bands])
        }
    }

    func testRestoreAppliesTheActiveLayoutAndKeepsTheOtherExact() {
        let engine = AudioEngine()
        let startedModern = engine.eqConfiguration == .modern21
        engine.restoreEQGains(["classic10": classic, "modern21": modern])

        XCTAssertEqual(engine.eqGainsByLayout(), ["classic10": classic, "modern21": modern])
        let active = startedModern ? modern : classic
        XCTAssertEqual((0..<active.count).map { engine.getEQBand($0) }, active)

        // A live switch to the other family lands on its own saved curve, not a remap.
        engine.applyEQLayout(forModernUI: !startedModern)
        let other = startedModern ? classic : modern
        XCTAssertEqual((0..<other.count).map { engine.getEQBand($0) }, other)
    }

    func testRestoreSeedsAnUnsavedActiveLayoutFromTheSavedOne() {
        let engine = AudioEngine()
        let active = engine.eqConfiguration
        let source: EQConfiguration = active == .modern21 ? .classic10 : .modern21
        let sourceGains = source == .classic10 ? classic : modern
        engine.restoreEQGains([source.name: sourceGains])

        let expected = EQBandRemapper.remap(gains: sourceGains, from: source, to: active)
        XCTAssertEqual((0..<active.bandCount).map { engine.getEQBand($0) }, expected)
        XCTAssertEqual(engine.eqGainsByLayout()[source.name], sourceGains)
    }
}
