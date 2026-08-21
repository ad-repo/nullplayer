import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 46 — `setScale`, and the one scale a `.wal` skin is allowed to have (B12).
///
/// Defix's configurator offers seven window-scaling buttons (100–300%). Each stores a percentage
/// with `System.setPrivateInt` and then calls `layout.setScale(factor)` — measured, from nine
/// `onDataChanged` handlers in five scripts, once per window the skin owns. The method was not in
/// the GUI table at all, so every one of them was refused and the buttons were inert.
///
/// The decision this phase closes: it drives **NullPlayer's own UI Size**, not a skin-local scale.
/// A `.wal` scene is laid out on the skin's pixel grid and `WinampModernMainView` applies UI Size
/// at its drawing and input boundaries (Phase 10) — a second, layout-local scale would be a rival
/// for the same pixels, and the two would fight over every window's size. `getScale()` therefore
/// stays 1: the layout's own scale really is 1, whatever size the windows are drawn at.
final class WinampModernPhase46Tests: XCTestCase {
    private final class TestHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var trackDisplayTitle = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 2
        var spectrumLevels: [Float] = []
        var isArtworkLoading = false
        var vuLevels: (left: Double, right: Double) = (0, 0)

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }

    // MARK: - The seven buttons land on seven levels

    /// The measured factors, straight off Defix's bytecode (`1`, `1.25`, `1.5`, `1.75`, `2`, `2.5`,
    /// `3`), each mapping to its own UI Size level. This is why 175/250/300 were added to
    /// `UIScaleLevel`: without them three of the seven buttons collapsed onto 200%.
    func testEveryConfiguratorFactorSnapsToItsOwnUISizeLevel() {
        let expected: [(CGFloat, UIScaleLevel)] = [
            (1, .p100), (1.25, .p125), (1.5, .p150), (1.75, .p175),
            (2, .p200), (2.5, .p250), (3, .p300)
        ]
        for (factor, level) in expected {
            XCTAssertEqual(UIScaleLevel.nearest(toScaleFactor: factor), level,
                           "setScale(\(factor)) is UI Size \(level.menuTitle)")
        }
        XCTAssertEqual(Set(expected.map(\.1)).count, expected.count,
                       "seven distinct buttons must not collapse onto fewer levels")
    }

    /// A factor that is not one of ours takes the nearest level rather than being dropped, and the
    /// ends clamp — a skin cannot drive the host past the ladder in either direction.
    func testAnOffLadderFactorTakesTheNearestLevelAndTheEndsClamp() {
        XCTAssertEqual(UIScaleLevel.nearest(toScaleFactor: 1.4), .p135)
        XCTAssertEqual(UIScaleLevel.nearest(toScaleFactor: 2.2), .p200)
        XCTAssertEqual(UIScaleLevel.nearest(toScaleFactor: 0.1), .p50, "below the ladder clamps")
        XCTAssertEqual(UIScaleLevel.nearest(toScaleFactor: 12), .p300, "above the ladder clamps")
        XCTAssertEqual(UIScaleLevel.nearest(toScaleFactor: 1.625), .p175,
                       "a tie goes to the larger level")
    }

    // MARK: - The method itself

    /// The receiver Defix, Ebonite and boom all use is a **layout**, and that is the only form the
    /// host acts on: a scale stamped on a child object would be a second scale for the same pixels.
    func testSetScaleOnALayoutAsksTheHostForThatUISize() throws {
        let (runtime, program) = try makeRuntime()
        var requested: [CGFloat] = []
        runtime.uiScaleRequested = { requested.append($0) }
        let layout = try reference(runtime, xmlID: "normal")

        _ = try runtime.invoke(method: "setScale", on: layout, arguments: [.double(1.75)],
                               program: program)

        XCTAssertEqual(requested, [1.75])
        XCTAssertEqual(requested.map(UIScaleLevel.nearest(toScaleFactor:)), [.p175])
    }

    /// Accepted and inert on anything else — *accepted*, because refusing a method aborts the whole
    /// handler that called it, which is how one unimplemented call takes a skin's entire
    /// `onScriptLoaded` with it (Phase 43's multipass finding).
    func testSetScaleOnANonLayoutIsAcceptedAndAsksForNothing() throws {
        let (runtime, program) = try makeRuntime()
        var requested: [CGFloat] = []
        runtime.uiScaleRequested = { requested.append($0) }
        let button = try reference(runtime, xmlID: "b")

        let result = try runtime.invoke(method: "setScale", on: button, arguments: [.double(2)],
                                        program: program)

        if case .null = result {} else { XCTFail("the call succeeds and answers null, got \(result)") }
        XCTAssertTrue(requested.isEmpty, "and asks the host for nothing")
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty,
                      "an accepted method must not be recorded as unsupported demand")
    }

    /// A garbage factor must not reach the host as a scale. Zero and NaN ask for nothing; a wild
    /// value is clamped before it is offered, so the level it snaps to is a level and not an
    /// accident of arithmetic.
    func testAnUnusableFactorIsNotOfferedToTheHost() throws {
        let (runtime, program) = try makeRuntime()
        var requested: [CGFloat] = []
        runtime.uiScaleRequested = { requested.append($0) }
        let layout = try reference(runtime, xmlID: "normal")

        for bad: Double in [0, -2, .nan, .infinity] {
            _ = try runtime.invoke(method: "setScale", on: layout, arguments: [.double(bad)],
                                   program: program)
        }
        XCTAssertTrue(requested.isEmpty, "nothing unusable is offered")

        _ = try runtime.invoke(method: "setScale", on: layout, arguments: [.double(99)],
                               program: program)
        XCTAssertEqual(requested, [4], "and a wild value arrives clamped")
    }

    /// The read half stays 1. ClassicPro multiplies its resize arithmetic by `getScale()`, and that
    /// arithmetic is in skin pixels — where the scale *is* 1 however large the window is drawn.
    func testGetScaleStillAnswersOneAfterASetScale() throws {
        let (runtime, program) = try makeRuntime()
        runtime.uiScaleRequested = { _ in }
        let layout = try reference(runtime, xmlID: "normal")

        _ = try runtime.invoke(method: "setScale", on: layout, arguments: [.double(3)],
                               program: program)
        let scale = try runtime.invoke(method: "getScale", on: layout, arguments: [], program: program)

        XCTAssertEqual(scale.doubleValue, 1)
    }

    /// Defix asks nine times for one click (five scripts, one holder per window). The host is what
    /// de-duplicates — `WindowManager.uiScaleLevel` ignores a write of the level it is already at —
    /// so the runtime must forward every one of them rather than trying to be clever about it.
    func testARepeatedRequestIsForwardedEveryTime() throws {
        let (runtime, program) = try makeRuntime()
        var requested: [CGFloat] = []
        runtime.uiScaleRequested = { requested.append($0) }
        let layout = try reference(runtime, xmlID: "normal")

        for _ in 0..<9 {
            _ = try runtime.invoke(method: "setScale", on: layout, arguments: [.double(3)],
                                   program: program)
        }
        XCTAssertEqual(requested.count, 9)
    }

    /// Teardown releases the hook with the rest of them: the runtime outlives nothing, but a stale
    /// closure onto a torn-down window controller is how a skin switch resizes the wrong windows.
    func testTeardownReleasesTheHook() throws {
        let (runtime, _) = try makeRuntime()
        runtime.uiScaleRequested = { _ in }
        runtime.teardown()
        XCTAssertNil(runtime.uiScaleRequested)
    }

    // MARK: - Helpers

    private func reference(_ runtime: WinampModernScriptRuntime,
                           xmlID: String) throws -> MakiObjectReference {
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: xmlID).first)
        return MakiObjectReference(.gui(object.stableID))
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="120" h="120">
              <button id="b" x="0" y="0" w="20" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, program)
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase46Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase46-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
