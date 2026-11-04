import XCTest
@testable import NullPlayer

/// The AIMP window layer's own pieces, without a window: what a click or the wheel does to a target,
/// and what the host maps from the player.
@MainActor
final class AIMPSkinWindowTests: XCTestCase {

    /// The level model's 0–100 above its floor as the host's 0–1, which AIMP's meters read on a
    /// linear 0–145 with 100 at 0 dB: RMS at −8 dBFS stands on that mark.
    func testMeterLevelPutsMinusEightDBFSOnTheZeroDBMark() {
        let floor = -42.0
        XCTAssertEqual(AIMPSkinAudioEngineHost.meterLevel(0, floor: floor), 0)
        let minusEight = (1 - 8 / 42.0) * 100
        XCTAssertEqual(AIMPSkinAudioEngineHost.meterLevel(minusEight, floor: floor), 100.0 / 145, accuracy: 0.01)
        XCTAssertEqual(AIMPSkinAudioEngineHost.meterLevel(100, floor: floor), 1, "full scale pins the needle")
    }

    /// A counter key's or tab selector's `Expression`, sorted once: whether the wheel steps it one
    /// position a notch, by its `ScrollDelta`, or not at all.
    func testAStepIsSortedByWhatTheWheelDoes() {
        for spelling in ["Value + 1", "value+1", "(value+1)mod 3", "(Value + 1) MOD 6"] {
            XCTAssertEqual(AIMPSkinStep(spelling).wheel, .next, spelling)
        }
        XCTAssertEqual(AIMPSkinStep("Value + ScrollDelta").wheel, .scrollDelta)
        XCTAssertEqual(AIMPSkinStep("Value XOR 1").wheel, .none)
        XCTAssertEqual(AIMPSkinStep("3").wheel, .none)
        XCTAssertEqual(AIMPSkinStep("3").position, 3, "a right-click's ContextMenu value")
        XCTAssertNil(AIMPSkinStep("Value + 1").position)
        XCTAssertEqual(AIMPSkinStep(nil).wheel, .none)
        XCTAssertNil(AIMPSkinStep(nil).next(from: 2), "no expression: the position stays")
    }

    /// `ScrollDelta` is the wheel's notches, one for a click: what the view used to splice into the
    /// expression's text.
    func testAStepEvaluatesScrollDeltaAsTheNotches() {
        XCTAssertEqual(AIMPSkinStep("Value + ScrollDelta").next(from: 4), 5)
        XCTAssertEqual(AIMPSkinStep("Value + ScrollDelta").next(from: 4, notches: -3), 1)
        XCTAssertEqual(AIMPSkinStep("Value-ScrollDelta").next(from: 4, notches: -2), 6)
        for notches in [-3, -1, 1, 2] {
            let spliced = AIMPSkinExpression.evaluate("Value-ScrollDelta".replacingOccurrences(of: "ScrollDelta", with: "(\(notches))"), value: 4)
            XCTAssertEqual(AIMPSkinStep("Value-ScrollDelta").next(from: 4, notches: notches), spliced)
        }
        XCTAssertEqual(AIMPSkinStep("(value+1) mod 3").next(from: 2), 0)
        XCTAssertEqual(AIMPSkinStep("(value+1) mod 3").next(from: 2, notches: 5), 0, "notches are ScrollDelta's alone")
    }

    func testDragsAreTheKindsOwn() {
        let draggable: [AIMPSkinTarget.Kind] = [.knob(provider: nil), .slider(provider: nil, vertical: false), .seek]
        let keys: [AIMPSkinTarget.Kind] = [.action(.playerPlay), .menu(nil), .maximize]
        let others: [AIMPSkinTarget.Kind] = [.handler("OnClick"), .toggle(item: "Meters"), .counter(name: "C", step: AIMPSkinStep("Value + 1")),
                                             .page(group: "G", step: AIMPSkinStep(nil)), .playlistScroll(maxTop: 3, thumb: 8)]
        for kind in draggable { XCTAssertTrue(kind.isDraggable, "\(kind)"); XCTAssertFalse(kind.passesDragsThrough, "\(kind)") }
        for kind in keys { XCTAssertFalse(kind.isDraggable, "\(kind)"); XCTAssertTrue(kind.passesDragsThrough, "\(kind)") }
        for kind in others { XCTAssertFalse(kind.isDraggable, "\(kind)"); XCTAssertFalse(kind.passesDragsThrough, "\(kind)") }
    }

    // MARK: - The view's collaborators

    func testSizingClampsToFourTimesTheNaturalSizeAndSizesFromItsEdges() {
        var sizing = AIMPSkinSizing(minimum: CGSize(width: 100, height: 50), edge: 4)
        XCTAssertEqual(sizing.clamped(CGSize(width: 20, height: 900)), CGSize(width: 100, height: 200))
        let bounds = NSRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertNil(sizing.edges(at: NSPoint(x: 100, y: 50), in: bounds, scale: 2), "the middle")
        XCTAssertEqual(sizing.edges(at: NSPoint(x: 195, y: 50), in: bounds, scale: 2)?.right, true, "8 view points of band at 2x")
        XCTAssertEqual(sizing.edges(at: NSPoint(x: 195, y: 95), in: bounds, scale: 2)?.bottom, true)
        XCTAssertNil(AIMPSkinSizing().edges(at: NSPoint(x: 359, y: 95), in: bounds, scale: 1), "a form of fixed size")

        sizing.drag = (NSPoint(x: 500, y: 500), sizing.canvas, true, true)
        // Screen points grow upward: down and right by 20 at 2x is 10 skin pixels each way.
        XCTAssertEqual(sizing.dragged(to: NSPoint(x: 520, y: 480), scale: 2), CGSize(width: 110, height: 60))
        XCTAssertNil(sizing.dragged(to: NSPoint(x: 400, y: 600), scale: 2), "already at its natural size")
    }

    func testMaximizeFillsTheScreenAndGoesBack() {
        var sizing = AIMPSkinSizing(minimum: CGSize(width: 100, height: 50), edge: 4)
        sizing.canvas = CGSize(width: 150, height: 60)
        sizing.toggleMaximized(screen: CGSize(width: 1001, height: 601), scale: 2)
        XCTAssertEqual(sizing.canvas, CGSize(width: 500, height: 300))
        XCTAssertEqual(sizing.unmaximized, CGSize(width: 150, height: 60))
        sizing.toggleMaximized(screen: CGSize(width: 1001, height: 601), scale: 2)
        XCTAssertEqual(sizing.canvas, CGSize(width: 150, height: 60))
        XCTAssertNil(sizing.unmaximized)
    }

    func testAPressHandsOverToTheKnobUnderItOnceThePointerMoves() {
        let press = AIMPSkinPress()
        let key = AIMPSkinTarget(control: .init(value: 1), name: "Mute", kind: .action(.playerVolumeMute), rect: .zero)
        let knob = AIMPSkinTarget(control: .init(value: 2), name: "Volume", kind: .knob(provider: .volume), rect: .zero)
        press.begin(key, under: (knob, NSPoint(x: 10, y: 10)))
        XCTAssertNil(press.handOver(at: NSPoint(x: 12, y: 11)), "within 3 points it stays the key's")
        XCTAssertEqual(press.target?.name, "Mute")
        XCTAssertEqual(press.handOver(at: NSPoint(x: 14, y: 10))?.target.name, "Volume")
        XCTAssertEqual(press.target?.name, "Volume")
        XCTAssertNil(press.handOver(at: NSPoint(x: 40, y: 40)), "once")
        press.knobStart = (NSPoint(x: 10, y: 10), 0.5)
        let ended = press.end()
        XCTAssertEqual(ended?.target.name, "Volume")
        XCTAssertEqual(ended?.holdFired, false)
        XCTAssertNil(press.knobStart)
        XCTAssertNil(press.end(), "nothing held")
    }

    func testAHeldKeyActsAfterAPauseThenRepeatsAndItsReleaseDoesNotClick() {
        let press = AIMPSkinPress()
        press.begin(AIMPSkinTarget(control: .init(value: 1), name: "Next", kind: .action(.playerNextTrack), rect: .zero), under: nil)
        var fired = 0
        press.hold(repeats: true) { fired += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(fired, 0, "not before 0.4 s")
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        XCTAssertGreaterThanOrEqual(fired, 2, "once, then every 0.1 s")
        XCTAssertEqual(press.end()?.holdFired, true)
        let after = fired
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(fired, after, "let go, it stops")
    }

    func testGaugesEaseAtTheirSpeedsWhilePlaying() {
        var gauges = AIMPSkinGauges()
        let vu = AIMPSkinControl.ID(value: 7)
        gauges.ease([vu: (value: 40, up: 5, down: 2)], playing: true, clock: 10)
        XCTAssertEqual(gauges.levels[vu], 40, "a first frame shows the value")
        gauges.ease([vu: (value: 100, up: 5, down: 2)], playing: true, clock: 10 + 2.0 / 30)
        XCTAssertEqual(gauges.levels[vu] ?? 0, 50, accuracy: 1e-9, "two thirtieths at 5 up")
        gauges.ease([vu: (value: 0, up: 5, down: 2)], playing: true, clock: 10 + 3.0 / 30)
        XCTAssertEqual(gauges.levels[vu] ?? 0, 48, accuracy: 1e-9, "one at 2 down")
        gauges.ease([vu: (value: 0, up: 5, down: 2)], playing: false, clock: 11)
        XCTAssertEqual(gauges.levels, [:], "stopped, they read their values")
    }

    /// The probe draws as it asks, at its own clock; a window draws off the main thread, one frame at
    /// a time, and requests made meanwhile wait as one: the latest, measuring if any of them asked to.
    func testFramesDrawAtOnceForTheProbeAndOneAtATimeForAWindow() throws {
        let skin = try AIMPSkinLoader.load(data: AIMPSkinOwnWindowsTests.skinWithOwnPlaylist())
        func input(measures: Bool, content: Int = 0) -> AIMPSkinFrameScheduler.RenderInput {
            AIMPSkinFrameScheduler.RenderInput(skin: skin, size: CGSize(width: 40, height: 20), form: nil, host: AIMPSkinHostState(player: .probe),
                                               state: AIMPSkinState(), interaction: .init(), measures: measures,
                                               generation: .init(skin: 1, content: content))
        }
        let probe = AIMPSkinFrameScheduler()
        probe.timing = .probe(clock: 42)
        XCTAssertEqual(probe.now, 42)
        var shown = 0
        probe.draw(input(measures: true)) { _ in shown += 1 }
        XCTAssertEqual(shown, 1, "drawn before draw returns")

        let window = AIMPSkinFrameScheduler()
        XCTAssertNil(window.probeClock)
        var outputs: [AIMPSkinFrameScheduler.RenderOutput] = []
        window.draw(input(measures: false)) { outputs.append($0) }
        // A layout change lands while the first frame draws; a later request does not lose it.
        window.draw(input(measures: true, content: 1)) { outputs.append($0) }
        window.draw(input(measures: false, content: 2)) { outputs.append($0) }
        XCTAssertTrue(outputs.isEmpty, "drawn off the main thread")
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in outputs.count == 2 }, object: nil)
        wait(for: [landed], timeout: 5)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(outputs.count, 2, "the two requests made while drawing drew once")
        XCTAssertNil(outputs[0].measured)
        XCTAssertEqual(outputs[1].generation.content, 2, "the latest")
        XCTAssertNotNil(outputs[1].measured, "measured, as one of the requests it stands for asked")
    }

    func testTheSearchFieldTypesIntoTheListsSearchAndEscapeClearsIt() throws {
        let view = AIMPSkinMainView(frame: CGRect(x: 0, y: 0, width: 360, height: 96))
        view.runtime = AIMPSkinRuntime(skin: try AIMPSkinLoader.load(data: AIMPSkinOwnWindowsTests.skinWithOwnPlaylist()), player: .probe)
        XCTAssertFalse(view.search.isTyping(at: NSPoint(x: 20, y: 10)))
        view.search.begin(.playlist, in: CGRect(x: 0, y: 0, width: 100, height: 20))
        XCTAssertEqual(view.skinState.lists.searchEditing, .playlist)
        XCTAssertTrue(view.search.isTyping(at: NSPoint(x: 20, y: 10)))
        view.skinState.lists.setSearch(.playlist, "abc")
        let editor = NSTextView()
        XCTAssertTrue(view.search.control(NSTextField(), textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(view.skinState.lists.search(.playlist), "")
        XCTAssertNil(view.skinState.lists.searchEditing)
        XCTAssertFalse(view.search.isTyping(at: NSPoint(x: 20, y: 10)))
    }
}
