import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B32 — `cfgattrib` toggles that show no state, and a crossfade that drives nothing.
///
/// The measured defect (mmd3, `WINAMP_MODERN_RENDER_PROBE=main/normal`): all three of its
/// Crossfade / Shuffle / Repeat buttons read `activated=0` and all six of the `ghost="1"` layers
/// that are their *only* on-screen indication read `alpha=0`, with the skin's script having run
/// clean. `playertools.m` sets those alphas from `getActivated()` at load and from
/// `<toggle>.onActivate(int)` thereafter, and neither could answer:
///
/// * `getActivated()` read the `activated` attribute, which `toggleConfigAttribute` deliberately
///   never writes — the stored preference *is* a bound button's state — so a config-bound button
///   reported off forever.
/// * `onActivate` had no dispatch site anywhere in the engine.
///
/// And shuffle/repeat were stored twice: in the skin's configuration namespace *and* on the host,
/// which an `xmlID` special case in the view toggled separately. The two drifted apart the moment
/// either side moved.
///
/// Corpus demand across the 30 installed skins: `Repeat` ×52, `Shuffle` ×50, `Enable crossfading`
/// ×32, `Crossfade time` ×12 — this is a capability, not one skin's quirk.
final class WinampModernConfigBridgeTests: XCTestCase {

    private final class TestHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var crossfadeEnabled = false
        var crossfadeSeconds = 5
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

    // MARK: - The setting is the state

    /// mmd3's whole indicator set is `alpha = 255 * getActivated()` evaluated once at load. A bound
    /// button that answers from its own `activated` attribute can only ever say "off".
    func testGetActivatedOnABoundButtonAnswersTheHostNotTheAttribute() throws {
        let (runtime, host, program) = try makeRuntime()
        let shuffle = try object(runtime, "Shuffle")
        host.shuffleEnabled = true

        let activated = try runtime.invoke(method: "getActivated", on: reference(shuffle),
                                           arguments: [], program: program)
        XCTAssertTrue(activated.truthy, "the stored preference is the button's state")
        XCTAssertNil(shuffle.attributes["activated"],
                     "and it is not copied onto the button, which is what let the two disagree")
    }

    /// The renderer's active-image decision reads the same value, so a bound button with distinct
    /// `activeimage` artwork lights up too.
    func testConfigValueFollowsTheHost() throws {
        let (runtime, host, _) = try makeRuntime()
        let repeatButton = try object(runtime, "Repeat")

        XCTAssertFalse(runtime.configValue(of: repeatButton))
        host.repeatEnabled = true
        XCTAssertTrue(runtime.configValue(of: repeatButton))
    }

    /// A number is not a lamp. mmd3's crossfade *slider* names `Crossfade time`, and reading its
    /// seconds as truthiness would light an `activeimage` for any non-zero duration.
    func testABoundSliderIsNeverALamp() throws {
        let (runtime, host, _) = try makeRuntime()
        host.crossfadeSeconds = 7
        XCTAssertFalse(runtime.configValue(of: try object(runtime, "sCrossfade")))
        XCTAssertEqual(runtime.configInteger(of: try object(runtime, "sCrossfade")), 7)
    }

    // MARK: - The toggle

    /// One click, one flip. Before the bridge the view also matched the button's `xmlID` and
    /// toggled the host a second time, so shuffle came back exactly where it started.
    func testTogglingABoundButtonMovesTheHostExactlyOnce() throws {
        let (runtime, host, _) = try makeRuntime()

        XCTAssertTrue(runtime.toggleConfigAttribute(of: try object(runtime, "Shuffle")))
        XCTAssertTrue(host.shuffleEnabled)
        XCTAssertTrue(runtime.toggleConfigAttribute(of: try object(runtime, "Shuffle")))
        XCTAssertFalse(host.shuffleEnabled, "and it comes back")
    }

    /// The host is the only home. A bridged attribute written to the skin's namespace as well
    /// would leave a shuffle toggled from the menu bar with the skin's lamp still dark.
    func testABridgedAttributeIsNotAlsoStoredInTheSkinsNamespace() throws {
        let (runtime, host, _) = try makeRuntime()
        host.shuffleEnabled = true

        let stored = runtime.loadedSkin.configuration.integer(
            section: WinampModernConfigBridge.Attribute.shuffle.section,
            key: WinampModernConfigBridge.Attribute.shuffle.key, default: -1)
        XCTAssertEqual(stored, -1, "nothing was written to the skin's own storage")
        XCTAssertTrue(runtime.configValue(of: try object(runtime, "Shuffle")),
                      "and the control still reads the setting")
    }

    /// An attribute the bridge does not name is the skin's own and keeps its namespaced storage —
    /// Defix's nine display switches, a notifier's corner, a songticker mode.
    func testAnUnbridgedAttributeStillUsesTheSkinsOwnStorage() throws {
        let (runtime, _, _) = try makeRuntime()
        let ownSwitch = try object(runtime, "own.switch")

        XCTAssertTrue(runtime.toggleConfigAttribute(of: ownSwitch))
        XCTAssertEqual(runtime.loadedSkin.configuration.integer(section: "{F1036C9C}", key: "Bg Chng"), 1)
        XCTAssertTrue(runtime.configValue(of: ownSwitch))
    }

    // MARK: - The bridge's edges

    func testTheBridgeMatchesGUIDsCaseInsensitively() {
        XCTAssertEqual(
            WinampModernConfigBridge.attribute(section: "{45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d}",
                                               key: "shuffle"),
            .shuffle, "skins ship these GUIDs in both hex cases")
        XCTAssertNil(WinampModernConfigBridge.attribute(section: "{F1036C9C}", key: "Bg Chng"))
    }

    /// `{0000000A-…};Random` is AVS preset randomisation, not playlist shuffle — 15 uses across the
    /// corpus, and bridging it to the host would randomise the wrong thing.
    func testAvsRandomIsNotBridgedToShuffle() {
        XCTAssertNil(WinampModernConfigBridge.attribute(
            section: "{0000000A-000C-0010-FF7B-01014263450C}", key: "Random"))
    }

    /// A skin is untrusted markup: mmd3's crossfade slider is cut `high="20"`, and its range is
    /// mapped into the one NullPlayer's own Fade Duration menu offers rather than accepted as given.
    func testCrossfadeSecondsAreClampedToTheEnginesRange() throws {
        let (runtime, host, _) = try makeRuntime()
        let slider = try object(runtime, "sCrossfade")

        runtime.setConfigAttribute(of: slider, normalized: 1)
        XCTAssertEqual(host.crossfadeSeconds,
                       Int(WinampModernConfigBridge.crossfadeSecondsRange.upperBound))
        runtime.setConfigAttribute(of: slider, normalized: 0)
        XCTAssertEqual(host.crossfadeSeconds,
                       Int(WinampModernConfigBridge.crossfadeSecondsRange.lowerBound))
    }

    /// The drag's unit is the slider's own `low…high`, not Winamp's 0…255 — mmd3 prints the
    /// position straight into its readout as seconds.
    func testABoundSliderDragsInItsOwnUnit() throws {
        let (runtime, host, _) = try makeRuntime()
        // `high="20"`, so half travel is 10 — which is also the top of the clamp.
        runtime.setConfigAttribute(of: try object(runtime, "sCrossfade"), normalized: 0.5)
        XCTAssertEqual(host.crossfadeSeconds, 10)
        runtime.setConfigAttribute(of: try object(runtime, "sCrossfade"), normalized: 0.25)
        XCTAssertEqual(host.crossfadeSeconds, 5)
    }

    /// mmd3 seeds its readout with `slidercb.onSetPosition(slidercb.getPosition())` at load, which
    /// read 0 whatever the stored duration was.
    func testGetPositionOnABoundSliderAnswersTheSetting() throws {
        let (runtime, host, program) = try makeRuntime()
        host.crossfadeSeconds = 8

        let position = try runtime.invoke(method: "getPosition",
                                          on: reference(try object(runtime, "sCrossfade")),
                                          arguments: [], program: program)
        XCTAssertEqual(position.integerValue, 8)
    }

    /// The crossfade enable is the same shape as shuffle, and it is what wires a skin's crossfade
    /// button to NullPlayer's Sweet Fades.
    func testTheCrossfadeSwitchDrivesTheHost() throws {
        let (runtime, host, _) = try makeRuntime()

        XCTAssertTrue(runtime.toggleConfigAttribute(of: try object(runtime, "Crossfade")))
        XCTAssertTrue(host.crossfadeEnabled)
        XCTAssertTrue(runtime.configValue(of: try object(runtime, "Crossfade")))
    }

    // MARK: - `onActivate`

    /// Wasabi raises `onActivate(int)` whenever a button's activation changes, and skins hang their
    /// *indicator* off it. It had no dispatch site at all, so no `.wal` skin could show a toggle's
    /// state; 8 of the 30 installed skins declare a handler for it.
    func testTogglingABoundButtonDispatchesOnActivate() throws {
        let (runtime, _, _) = try makeRuntime()
        runtime.recordsDispatchedEventsForTesting = true

        runtime.toggleConfigAttribute(of: try object(runtime, "Shuffle"))

        // A set: the graph walk is unordered, and no skin depends on which of its layouts hears
        // first — only that both do.
        let events = runtime.dispatchedEventsForTesting.filter { $0.event == "onactivate" }
        XCTAssertEqual(Set(events.map(\.object)), ["Shuffle", "Shuffle2"],
                       "every control bound to the attribute hears it — a skin declares the same "
                       + "switch once per layout, and mmd3's indicators are per-layout too")
    }

    /// An unbound togglebutton flips its own `activated` and must raise the event too — that is the
    /// plain Wasabi case, and boom's shuffle button is one.
    func testTogglingAnUnboundButtonDispatchesOnActivate() throws {
        let (runtime, _, _) = try makeRuntime()
        runtime.recordsDispatchedEventsForTesting = true

        XCTAssertTrue(runtime.toggleActivation(of: try object(runtime, "plain")))

        XCTAssertEqual(runtime.dispatchedEventsForTesting.filter { $0.event == "onactivate" }
                            .map(\.object), ["plain"])
    }

    /// `setActivated` from a script is a change like any other. `setActivatedNoCallback` is not —
    /// that is the whole difference between them, and a drawer that calls it from inside its own
    /// notification would otherwise re-enter.
    func testSetActivatedNotifiesAndNoCallbackDoesNot() throws {
        let (runtime, _, program) = try makeRuntime()
        let plain = reference(try object(runtime, "plain"))
        runtime.recordsDispatchedEventsForTesting = true

        _ = try runtime.invoke(method: "setActivated", on: plain, arguments: [.boolean(true)],
                               program: program)
        XCTAssertEqual(runtime.dispatchedEventsForTesting.filter { $0.event == "onactivate" }.count, 1)

        _ = try runtime.invoke(method: "setActivatedNoCallback", on: plain,
                               arguments: [.boolean(false)], program: program)
        XCTAssertEqual(runtime.dispatchedEventsForTesting.filter { $0.event == "onactivate" }.count, 1,
                       "the silent setter stays silent")
    }

    // MARK: - Changes made from outside the skin

    /// A `.wal` indicator is written once from `onActivate` and never polled, so a shuffle toggled
    /// in NullPlayer's own Playback menu left mmd3's lamp showing the previous state — the same
    /// drift two copies of the setting used to cause, arriving by a different road.
    func testAChangeMadeOutsideTheSkinReachesIt() throws {
        let (runtime, host, _) = try makeRuntime()
        runtime.refreshBridgedConfigState()   // seed
        runtime.recordsDispatchedEventsForTesting = true

        host.shuffleEnabled = true            // the menu bar's route
        runtime.refreshBridgedConfigState()

        XCTAssertEqual(Set(runtime.dispatchedEventsForTesting.filter { $0.event == "onactivate" }
                                  .map(\.object)), ["Shuffle", "Shuffle2"])
    }

    /// A bound slider hears it as `onSetPosition`, in its own unit — that is where mmd3 prints its
    /// crossfade readout, so a duration changed from the Fade Duration menu has to reach it.
    func testACrossfadeLengthChangedOutsideTheSkinReachesItsSlider() throws {
        let (runtime, host, _) = try makeRuntime()
        runtime.refreshBridgedConfigState()
        runtime.recordsDispatchedEventsForTesting = true

        host.crossfadeSeconds = 9
        runtime.refreshBridgedConfigState()

        XCTAssertEqual(runtime.dispatchedEventsForTesting.filter { $0.event == "onsetposition" }
                            .map(\.object), ["sCrossfade"])
    }

    /// A setting that did not move says nothing. An `onActivate` for a change that never happened
    /// would be a lie about what the person just did.
    func testAnUnchangedSettingIsNotAnnounced() throws {
        let (runtime, _, _) = try makeRuntime()
        runtime.refreshBridgedConfigState()
        runtime.recordsDispatchedEventsForTesting = true

        runtime.refreshBridgedConfigState()
        XCTAssertTrue(runtime.dispatchedEventsForTesting.isEmpty)
    }

    /// The skin's own click already raised the event, and the engine then posts its options-changed
    /// notification for that very write. One click must still be one `onActivate`.
    func testTheSkinsOwnClickIsNotAnnouncedTwice() throws {
        let (runtime, _, _) = try makeRuntime()
        runtime.refreshBridgedConfigState()
        runtime.recordsDispatchedEventsForTesting = true

        runtime.toggleConfigAttribute(of: try object(runtime, "Shuffle"))
        let afterClick = runtime.dispatchedEventsForTesting.filter { $0.event == "onactivate" }.count
        runtime.refreshBridgedConfigState()   // what the notification triggers

        XCTAssertEqual(runtime.dispatchedEventsForTesting.filter { $0.event == "onactivate" }.count,
                       afterClick, "the settled value was recorded, so there is no news to repeat")
    }

    // MARK: - What actually lands on the pixels

    /// The structural assertions above cannot see a rendering bug. This is the whole defect in one
    /// picture: a bound button whose `activeimage` must follow the host, drawn twice.
    func testABoundButtonsActiveArtworkFollowsTheHost() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="off" file="off.png" w="8" h="8"/>
            <bitmap id="on" file="on.png" w="8" h="8"/>
          </elements>
          <container id="main">
            <layout id="normal" w="8" h="8">
              <togglebutton id="Shuffle" image="off" activeImage="on" fitparent="1"
                            cfgattrib="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Shuffle"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try load(files: [("skin.xml", Data(xml.utf8)),
                                      ("off.png", try makeSolidPNG(size: 8, blue: 10)),
                                      ("on.png", try makeSolidPNG(size: 8, blue: 200))])
        let host = TestHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        renderer.configStateProvider = { runtime.configValue(of: $0) }

        XCTAssertEqual(try render(renderer, size: 8)[2], 10, "shuffle is off")
        host.shuffleEnabled = true      // the menu bar's route, not the skin's
        XCTAssertEqual(try render(renderer, size: 8)[2], 200,
                       "the same renderer repaints with the active image — no reload, no click")
    }

    /// A bound **slider**'s thumb is drawn from the setting, in the slider's own `low…high`. Without
    /// `configValueProvider` it read the object's `value=` attribute, which a bound slider never
    /// has, so every crossfade thumb in the corpus sat pinned at its left end.
    func testABoundSlidersThumbIsDrawnFromTheSetting() throws {
        let xml = """
        <WasabiXML>
          <elements><bitmap id="grip" file="grip.png" w="4" h="8"/></elements>
          <container id="main">
            <layout id="normal" w="24" h="8">
              <slider id="sCrossfade" x="0" y="0" w="24" h="8" low="0" high="20" thumb="grip"
                      cfgattrib="{F1239F09-8CC6-4081-8519-C2AE99FCB14C};Crossfade time"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try load(files: [("skin.xml", Data(xml.utf8)),
                                      ("grip.png", try makeSolidPNG(size: 4, blue: 200))])
        let host = TestHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        renderer.configValueProvider = { runtime.configInteger(of: $0) }

        host.crossfadeSeconds = 0
        let atRest = try thumbColumn(renderer, width: 24, height: 8)
        host.crossfadeSeconds = 10      // half of high="20"
        let atHalf = try thumbColumn(renderer, width: 24, height: 8)

        XCTAssertNotNil(atRest)
        XCTAssertNotNil(atHalf)
        XCTAssertGreaterThan(try XCTUnwrap(atHalf), try XCTUnwrap(atRest),
                             "a longer crossfade puts the thumb further right")
    }

    // MARK: - Helpers

    /// The leftmost column the thumb was painted in, or nil if it was never drawn.
    private func thumbColumn(_ renderer: WasabiSceneRenderer, width: Int, height: Int) throws -> Int? {
        let pixels = try render(renderer, width: width, height: height)
        for x in 0..<width where pixels[((height / 2) * width + x) * 4 + 2] > 100 { return x }
        return nil
    }

    private func render(_ renderer: WasabiSceneRenderer, size: Int) throws -> [UInt8] {
        try render(renderer, width: size, height: size)
    }

    private func render(_ renderer: WasabiSceneRenderer, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: context)
        }
        return pixels
    }

    private func makeSolidPNG(size: Int, blue: UInt8) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset + 2] = blue
            pixels[offset + 3] = 255
        }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private func load(files: [(String, Data)]) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernConfigBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B32-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func object(_ runtime: WinampModernScriptRuntime, _ id: String) throws -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: id).first)
    }

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, TestHost, MakiProgram) {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <togglebutton id="Shuffle" x="0" y="0" w="20" h="20"
                            cfgattrib="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Shuffle"/>
              <togglebutton id="Repeat" x="20" y="0" w="20" h="20"
                            cfgattrib="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Repeat"/>
              <togglebutton id="Crossfade" x="40" y="0" w="20" h="20"
                            cfgattrib="{FC3EAF78-C66E-4ED2-A0AA-1494DFCC13FF};Enable crossfading"/>
              <slider id="sCrossfade" x="0" y="40" w="80" h="10" high="20"
                      cfgattrib="{F1239F09-8CC6-4081-8519-C2AE99FCB14C};Crossfade time"/>
              <togglebutton id="own.switch" x="60" y="0" w="20" h="20" cfgattrib="{F1036C9C};Bg Chng"/>
              <togglebutton id="plain" x="80" y="0" w="20" h="20"/>
            </layout>
            <layout id="shade" w="200" h="20">
              <togglebutton id="Shuffle2" x="0" y="0" w="20" h="20"
                            cfgattrib="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Shuffle"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, host, program)
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        try load(files: [("skin.xml", Data(xml.utf8))])
    }
}

/// The trap the B32 render sweep found. MAKI's `/` is IEEE division with no zero check, so a skin
/// dividing by a value that happens to be zero produces an infinity — and `integerValue`'s
/// `Int32(clamping: Int64(value))` guarded the Int32 step but not the `Int64(_:)` inside it, which
/// traps. multipass reached it as soon as its crossfade slider started reporting a real position.
/// A trap on skin input violates the engine's security model, which says failures are typed.
final class MakiValueNumericConversionTests: XCTestCase {
    func testNonFiniteValuesConvertInsteadOfTrapping() {
        XCTAssertEqual(MakiValue.double(.infinity).integerValue, Int32.max)
        XCTAssertEqual(MakiValue.double(-.infinity).integerValue, Int32.min)
        XCTAssertEqual(MakiValue.double(.nan).integerValue, 0)
    }

    /// A finite 1e300 traps `Int64(_:)` exactly as an infinity does, so the range check has to
    /// happen in the wider type.
    func testOutOfRangeFiniteValuesSaturate() {
        XCTAssertEqual(MakiValue.double(1e300).integerValue, Int32.max)
        XCTAssertEqual(MakiValue.double(-1e300).integerValue, Int32.min)
        XCTAssertEqual(MakiValue.float(3e9).integerValue, Int32.max)
    }

    /// And the ordinary case is unchanged: truncation toward zero, which is what the interpreter
    /// did before and what every existing coercion expects.
    func testOrdinaryValuesStillTruncateTowardZero() {
        XCTAssertEqual(MakiValue.double(7.9).integerValue, 7)
        XCTAssertEqual(MakiValue.double(-7.9).integerValue, -7)
        XCTAssertEqual(MakiValue.double(0).integerValue, 0)
    }
}
