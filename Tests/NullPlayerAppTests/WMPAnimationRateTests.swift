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
        for centiseconds in [0, 1, 2] {
            let gif = WMPSkinTestSupport.animatedGIF(frameCount: 4, delayCentiseconds: centiseconds)
            let animation = try XCTUnwrap(store(gif).animation(for: "a.gif"))
            XCTAssertEqual(animation.delays, [WMPImageStore.animationFloor], count: 4,
                           "\(centiseconds) cs means 'as fast as possible' and takes the floor")
        }
    }

    /// The floor is a floor. An authored delay at or above it is the skin's own answer and is never
    /// rewritten — 1,112 of the corpus's multi-frame GIFs state 4 or 5 cs and mean it.
    func testAnAuthoredDelayIsNeverRewritten() throws {
        for centiseconds in [3, 4, 5, 7, 10, 100] {
            let gif = WMPSkinTestSupport.animatedGIF(frameCount: 3, delayCentiseconds: centiseconds)
            let animation = try XCTUnwrap(store(gif).animation(for: "a.gif"))
            XCTAssertEqual(animation.delays, [TimeInterval(centiseconds) / 100], count: 3,
                           "\(centiseconds) cs is what the skin asked for")
        }
    }

    /// **The boundary is between 2 and 3 cs, and the corpus is what put it there.**
    ///
    /// The Alienware family ships the same shutter animation authored twice —
    /// `AlienMorph`/`AlienwareTeleport` at 0 cs, `ALXMorph`/`ALXVortex` at 2 cs — so with the
    /// trigger at 1 cs one ran 9.8s and the other 3.9s, reported as "ALXMorph's animation runs so
    /// quickly, it is basically the same animation". Both spellings mean "every frame anything will
    /// draw": 2 cs is 50 fps. 3 cs is outside the rule on purpose — 62 corpus GIFs author it as a
    /// real rate — so this test pins both sides rather than the floored one alone.
    func testTheAsFastAsPossibleBoundarySitsBetweenTwoAndThreeCentiseconds() throws {
        let floored = WMPSkinTestSupport.animatedGIF(frameCount: 2, delayCentiseconds: 2)
        XCTAssertEqual(try XCTUnwrap(store(floored).animation(for: "a.gif")).delays[0],
                       WMPImageStore.animationFloor, accuracy: 0.0001,
                       "2 cs is 50 fps — the same request as 0, and it takes the floor")
        let authored = WMPSkinTestSupport.animatedGIF(frameCount: 2, delayCentiseconds: 3)
        XCTAssertEqual(try XCTUnwrap(store(authored).animation(for: "a.gif")).delays[0], 0.03,
                       accuracy: 0.0001, "3 cs is a rate 62 corpus GIFs state and mean")
    }

    /// The pair that set the boundary, at their real frame counts: the two files draw the same
    /// shutter and must now take the same time. Measured live at 9.80s and 10.05s of motion.
    func testTheAlienwareFamilysTwoShuttersRunAtTheSameRate() throws {
        let zeroAuthored = WMPSkinTestSupport.animatedGIF(frameCount: 119, delayCentiseconds: 0)
        let twoAuthored = WMPSkinTestSupport.animatedGIF(frameCount: 138, delayCentiseconds: 2)
        let a = try XCTUnwrap(store(zeroAuthored).animation(for: "a.gif")).duration
        let b = try XCTUnwrap(store(twoAuthored).animation(for: "a.gif")).duration
        XCTAssertEqual(a / Double(119), b / Double(138), accuracy: 0.0001,
                       "same per-frame rate; the files differ only in how they spell 'as fast as possible'")
    }

    /// The floor sets how long a **transition** takes — 679 of the 768 affected GIFs play once —
    /// so the number is worth stating as the duration a user sees, not just as a delay.
    func testTheFloorGivesAlienMorphsShutterItsMeasuredDuration() throws {
        let shutter = WMPSkinTestSupport.animatedGIF(frameCount: 119, delayCentiseconds: 0)
        let animation = try XCTUnwrap(store(shutter).animation(for: "a.gif"))
        XCTAssertEqual(animation.duration, 7.93, accuracy: 0.05,
                       "119 frames at the floor: 7.9s, against 11.9s at the browser clamp")
    }

    // MARK: - W182: the clock belongs to the slot, not to the view

    /// A scene built with two elements drawing different GIFs, so a slot can be addressed.
    private func twoSlotScene(_ first: Data, _ second: Data) async throws -> (WMPScene, WMPImageStore) {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20" backgroundColor="#000000">
              <SUBVIEW id="one" left="0" top="0" backgroundImage="a.gif"/>
              <SUBVIEW id="two" left="20" top="0" backgroundImage="b.gif"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("a.gif", data: first),
            WMPTestArchiveEntry("b.gif", data: second)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        return (try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main"),
                WMPImageStore(provider: skin.archive))
    }

    /// Each animated image in the scene is its own slot, keyed by the node **and** the resource.
    ///
    /// Both halves matter. Keyed by node alone, a script assigning a new GIF to an element it
    /// already drew would inherit the old clock, which is the defect. Keyed by resource alone, two
    /// elements drawing the same GIF would share one.
    func testEveryAnimatedImageIsItsOwnSlot() async throws {
        let (scene, store) = try await twoSlotScene(
            WMPSkinTestSupport.animatedGIF(frameCount: 4, delayCentiseconds: 4),
            WMPSkinTestSupport.animatedGIF(frameCount: 6, delayCentiseconds: 4))
        let slots = WMPRenderer(imageStore: store).animatedSlots(in: scene)
        XCTAssertEqual(slots.count, 2, "two animated elements are two clocks")
        XCTAssertEqual(Set(slots.keys.map(\.resourcePath)), ["a.gif", "b.gif"])
        XCTAssertEqual(Set(slots.keys.map(\.stableID)).count, 2, "two distinct nodes")
        XCTAssertEqual(slots.values.map(\.frameCount).sorted(), [4, 6])
    }

    /// **The defect, at the level the renderer can be asked about it.** A slot given its own clock
    /// draws the frame *that* clock names, and one the caller says nothing about falls back to the
    /// scene clock — which is what every render dump and `WMP_RENDER_CLOCK` relies on.
    ///
    /// `AlienMorph` is the case: its shutter GIF is assigned a second after the view loads, so
    /// under one clock for the whole view it was entered a second in, and a later toggle of the
    /// same shutter was entered past its own last frame and never moved at all.
    func testASlotClockSelectsTheFrameIndependentlyOfTheSceneClock() async throws {
        let gif = WMPSkinTestSupport.animatedGIF(frameCount: 10, delayCentiseconds: 10)
        let (scene, store) = try await scene(gif: gif)
        let renderer = WMPRenderer(imageStore: store)
        let slot = try XCTUnwrap(renderer.animatedSlots(in: scene).keys.first)
        let animation = try XCTUnwrap(store.animation(for: slot.resourcePath))

        // The scene clock says "0.75s in" — frame 7 — while the slot says it has just started.
        // The fixture alternates two colours per frame, so an odd frame is the one that differs
        // from frame zero; comparing against an even one would pass on identical pixels.
        XCTAssertEqual(animation.frameIndex(at: 0.75), 7)
        XCTAssertEqual(animation.frameIndex(at: 0), 0)
        let atSceneClock = try await renderer.render(scene: scene, clock: 0.75)
        let atSlotClock = try await renderer.render(scene: scene, clock: 0.75,
                                                    slotClocks: [slot: 0])
        let atZero = try await renderer.render(scene: scene, clock: 0)
        XCTAssertNotEqual(Self.pixels(atSceneClock.image), Self.pixels(atSlotClock.image),
                          "the slot's own clock must decide the frame, not the scene's")
        XCTAssertEqual(Self.pixels(atSlotClock.image), Self.pixels(atZero.image),
                       "a slot clocked at zero draws frame zero whatever the scene clock says")
    }

    /// The rendered pixels, for comparing two renders of the same scene.
    private static func pixels(_ image: CGImage) -> Data {
        (image.dataProvider?.data as Data?) ?? Data()
    }

    /// The fallback is the whole reason the harness is unaffected: name no slots and every image
    /// is drawn at the scene clock, exactly as before W182.
    func testAnEmptySlotTableRendersExactlyAsTheSceneClockAlone() async throws {
        let gif = WMPSkinTestSupport.animatedGIF(frameCount: 10, delayCentiseconds: 10)
        let (scene, store) = try await scene(gif: gif)
        let renderer = WMPRenderer(imageStore: store)
        for clock in [0.0, 0.25, 0.75] {
            let withTable = try await renderer.render(scene: scene, clock: clock, slotClocks: [:])
            let without = try await renderer.render(scene: scene, clock: clock)
            XCTAssertEqual(Self.pixels(withTable.image), Self.pixels(without.image),
                           "an empty slot table changes nothing at clock \(clock)")
        }
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
