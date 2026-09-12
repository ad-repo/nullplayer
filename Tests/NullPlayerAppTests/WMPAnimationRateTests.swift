import CoreGraphics
import XCTest
@testable import NullPlayer

/// **W142 — "the animation fps is low in general", reported live against `AlienMorph`.**
///
/// Two independent defects wearing one symptom, and neither is visible to a render dump: a dump is
/// a still, and both of these are about *when* a frame is drawn rather than what is in it. They
/// were separated by `WMP_ANIM_TRACE=1` (see `reference/harness.md`), which reported
/// `want=25.0fps got=20.0fps frames=21 restarts=10 sleep=42.3ms render=4.5ms` — the shortfall and
/// its cause on one line.
///
/// The half of that defect that lives in the AppKit loop — the restart, the deadline schedule — is
/// pinned by `WMPAnimationCadence` identity here rather than by driving a window, because the loop
/// keys off exactly that: a rebuild whose cadence compares equal must not restart it. The rate it
/// then achieves was verified live and is not a thing a unit test can observe.
final class WMPAnimationRateTests: XCTestCase {

    // MARK: - The frame-delay floor (768 of 2,166 corpus GIFs author 0 or 1 cs)

    private func store(_ gif: Data) -> WMPImageStore {
        WMPImageStore(provider: WMPMemoryResourceProvider(["a.gif": gif]))
    }

    /// A GIF authored "as fast as possible" is floored, not clamped to the browser's 10 fps.
    ///
    /// This is the one that made the corpus look slow: `AlienMorph`'s shutter is 119 frames and
    /// 108 of them author 0, so at 0.1s it took 11.9 seconds to open.
    func testZeroAndOneCentisecondDelaysUseTheEngineFloorRatherThanTheBrowsers100ms() throws {
        for centiseconds in [0, 1] {
            let gif = WMPSkinTestSupport.animatedGIF(frameCount: 4, delayCentiseconds: centiseconds)
            let animation = try XCTUnwrap(store(gif).animation(for: "a.gif"))
            XCTAssertEqual(animation.delays, [WMPImageStore.animationFloor], count: 4,
                           "\(centiseconds) cs means 'as fast as possible' and takes the floor")
        }
    }

    /// The floor is a floor. An authored delay at or above it is the skin's own answer and is never
    /// rewritten — 1,112 of the corpus's multi-frame GIFs state 4 or 5 cs and mean it.
    func testAnAuthoredDelayIsNeverRewritten() throws {
        for centiseconds in [2, 4, 5, 7, 10, 100] {
            let gif = WMPSkinTestSupport.animatedGIF(frameCount: 3, delayCentiseconds: centiseconds)
            let animation = try XCTUnwrap(store(gif).animation(for: "a.gif"))
            XCTAssertEqual(animation.delays, [TimeInterval(centiseconds) / 100], count: 3,
                           "\(centiseconds) cs is what the skin asked for")
        }
    }

    /// The floor is only ever applied downward-bounded: 2 cs is *faster* than the floor and stays
    /// 2 cs. Reading the rule as "nothing runs faster than the floor" would slow those down, which
    /// is a different change and not this one.
    func testTheFloorDoesNotSlowDownAnAuthoredDelayBelowIt() throws {
        let gif = WMPSkinTestSupport.animatedGIF(frameCount: 2, delayCentiseconds: 2)
        let animation = try XCTUnwrap(store(gif).animation(for: "a.gif"))
        XCTAssertLessThan(animation.delays[0], WMPImageStore.animationFloor)
    }

    /// The floor sets how long a **transition** takes — 679 of the 768 affected GIFs play once —
    /// so the number is worth stating as the duration a user sees, not just as a delay.
    func testTheFloorGivesAlienMorphsShutterItsMeasuredDuration() throws {
        let shutter = WMPSkinTestSupport.animatedGIF(frameCount: 119, delayCentiseconds: 0)
        let animation = try XCTUnwrap(store(shutter).animation(for: "a.gif"))
        XCTAssertEqual(animation.duration, 7.93, accuracy: 0.05,
                       "119 frames at the floor: 7.9s, against 11.9s at the browser clamp")
    }

    // MARK: - The cadence is the loop's identity (a rebuild must not restart it)

    private func scene(gif: Data) async throws -> (WMPScene, WMPImageStore) {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20" backgroundColor="#000000">
              <SUBVIEW id="anim" left="4" top="2" backgroundImage="a.gif"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("a.gif", data: gif)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        return (scene, WMPImageStore(provider: skin.archive))
    }

    /// **The restart defect.** `startAnimation` runs on every rebuild, and a `.wmz` rebuilds
    /// constantly — AlienMorph's 100 ms view timer alone restarted the loop ten times a second,
    /// and each cancel discarded a partly-elapsed sleep. The loop now compares the cadence it is
    /// driving against the new one, so this equality *is* the fix: rebuilding the same scene must
    /// produce a cadence that compares equal, or the loop restarts exactly as it used to.
    func testRebuildingTheSameSceneProducesAnEqualCadence() async throws {
        let gif = WMPSkinTestSupport.animatedGIF(frameCount: 5, delayCentiseconds: 4)
        let (first, store) = try await scene(gif: gif)
        let (second, _) = try await scene(gif: gif)
        let renderer = WMPRenderer(imageStore: store)
        let before = try XCTUnwrap(renderer.animationCadence(for: first))
        let after = try XCTUnwrap(renderer.animationCadence(for: second))
        XCTAssertEqual(before, after, "an unchanged animation must not restart the repaint loop")
    }

    /// And the other direction, which is what keeps the equality honest: a scene whose animation
    /// actually changed must compare unequal, or the loop would keep pacing to the old delay.
    func testAChangedAnimationProducesADifferentCadence() async throws {
        let (slow, store) = try await scene(
            gif: WMPSkinTestSupport.animatedGIF(frameCount: 5, delayCentiseconds: 10))
        let (fast, fastStore) = try await scene(
            gif: WMPSkinTestSupport.animatedGIF(frameCount: 5, delayCentiseconds: 4))
        let slowCadence = try XCTUnwrap(WMPRenderer(imageStore: store).animationCadence(for: slow))
        let fastCadence = try XCTUnwrap(WMPRenderer(imageStore: fastStore).animationCadence(for: fast))
        XCTAssertNotEqual(slowCadence, fastCadence)
        XCTAssertEqual(slowCadence.shortestDelay, 0.1, accuracy: 0.0001)
        XCTAssertEqual(fastCadence.shortestDelay, 0.04, accuracy: 0.0001)
    }

    /// `endsAt` is what lets the loop stop, and the floor moves it: a one-shot scene stops
    /// repainting when its last frame lands, so raising the rate also shortens how long the loop
    /// runs at all. 679 of the 768 GIFs the floor touches are one-shot.
    func testAOneShotEndsAtItsLastFrameAndAnEndlessOneNeverDoes() async throws {
        let once = WMPSkinTestSupport.animatedGIF(frameCount: 5, delayCentiseconds: 0)
        let (onceScene, onceStore) = try await scene(gif: once)
        let onceCadence = try XCTUnwrap(WMPRenderer(imageStore: onceStore).animationCadence(for: onceScene))
        XCTAssertEqual(try XCTUnwrap(onceCadence.endsAt),
                       5 * WMPImageStore.animationFloor, accuracy: 0.0001,
                       "no NETSCAPE2.0 extension is the GIF grammar's play-once")

        let endless = WMPSkinTestSupport.animatedGIF(frameCount: 5, delayCentiseconds: 0, loops: 0)
        let (endlessScene, endlessStore) = try await scene(gif: endless)
        let endlessCadence = try XCTUnwrap(
            WMPRenderer(imageStore: endlessStore).animationCadence(for: endlessScene))
        XCTAssertNil(endlessCadence.endsAt, "an endless GIF keeps the repaint loop alive")
    }

    /// A scene with no animation has no cadence, so the loop is stopped rather than restarted at
    /// some default — the other half of the corpus and every static view.
    func testAStillSceneHasNoCadence() async throws {
        let still = try WMPSkinTestSupport.encodedImage(
            width: 2, height: 1, rgba: [255, 0, 0, 255, 0, 255, 0, 255], type: .gif)
        let (scene, store) = try await scene(gif: still)
        XCTAssertNil(WMPRenderer(imageStore: store).animationCadence(for: scene))
    }
}

private func XCTAssertEqual(_ delays: [TimeInterval], _ expected: [TimeInterval], count: Int,
                            _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(delays.count, count, message, file: file, line: line)
    for delay in delays {
        XCTAssertEqual(delay, expected[0], accuracy: 0.0001, message, file: file, line: line)
    }
}
