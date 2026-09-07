import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 41 (backlog B7) — `onEqBandChanged` / `onEqPreampChanged`.
///
/// Five skins handle these (multipass, mmd3, Rika, winampmodern566, Overdrive_2) and nothing ever
/// raised them, so an EQ readout followed the skin's own drag and no other route: a preset, the menu
/// bar, the classic equalizer window, a restored session. Winamp raises them whenever the equalizer
/// moves, *whoever* moved it, which is the shape `onVolumeChanged` already had.
///
/// The arities are measured, not assumed (`WINAMP_MODERN_RENDER_DISASM=@<xml>`): every one of the
/// five opens `onEqBandChanged` with two argument stores and `onEqPreampChanged` with one. The value
/// scale is measured too — Rika slices a region map at `128 - value`, so it is MAKI's −127…127, the
/// same scale `getEqBand` answers in.
final class WinampModernPhase41Tests: XCTestCase {

    // MARK: - The arities

    /// A wrong arity desynchronises the interpreter's stack, so these are read off the five skins'
    /// bytecode rather than guessed. They also have to be *callable*: a script may run its own handler
    /// to reuse it, and without a signature the interpreter fails closed on the call.
    func testTheEventsAreCallableWithTheArityTheSkinsDeclare() throws {
        let (runtime, _) = try makeRuntime()

        XCTAssertEqual(runtime.signature(for: "onEqBandChanged", classGUID: nil)?.argumentCount, 2)
        XCTAssertEqual(runtime.signature(for: "onEqPreampChanged", classGUID: nil)?.argumentCount, 1)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty)
    }

    // MARK: - What moved, and only what moved

    /// The opening state is an announcement, not silence: a skin whose readout is written from this
    /// handler and nowhere else has no other way to learn where the equalizer starts. Same rule
    /// `onTextChanged` follows for the first observation of real content.
    func testTheFirstObservationAnnouncesTheOpeningState() throws {
        let (runtime, equalizer) = try makeRuntime()
        equalizer.bands[3] = 64
        equalizer.preamp = -20
        runtime.recordsDispatchedEventsForTesting = true

        runtime.refreshEqualizerState()

        XCTAssertEqual(events(runtime, "oneqpreampchanged"), [[-20]])
        XCTAssertEqual(events(runtime, "oneqbandchanged").count, 10,
                       "every band's opening value, band index first")
        XCTAssertTrue(events(runtime, "oneqbandchanged").contains([3, 64]))
    }

    /// A change made outside the skin — a preset, the menu bar, the classic equalizer window, a
    /// restored session — is the whole point of the phase. Nothing calls back on those routes, so the
    /// funnel is a comparison against what the scripts were last told.
    func testAChangeMadeOutsideTheSkinIsAnnouncedWithItsBandAndValue() throws {
        let (runtime, equalizer) = try makeRuntime()
        runtime.refreshEqualizerState()
        runtime.recordsDispatchedEventsForTesting = true

        equalizer.bands[7] = -100

        runtime.refreshEqualizerState()

        XCTAssertEqual(events(runtime, "oneqbandchanged"), [[7, -100]],
                       "the band that moved, on MAKI's −127…127 scale, and no other")
        XCTAssertTrue(events(runtime, "oneqpreampchanged").isEmpty)
    }

    func testThePreampIsAnnouncedOnItsOwnEvent() throws {
        let (runtime, equalizer) = try makeRuntime()
        runtime.refreshEqualizerState()
        runtime.recordsDispatchedEventsForTesting = true

        equalizer.preamp = 127

        runtime.refreshEqualizerState()

        XCTAssertEqual(events(runtime, "oneqpreampchanged"), [[127]])
        XCTAssertTrue(events(runtime, "oneqbandchanged").isEmpty)
    }

    /// Cheap enough to poll only because it says nothing when nothing happened — the app runs this on
    /// a 1 Hz beat and from every playback-state hook.
    func testAnUnchangedEqualizerSaysNothing() throws {
        let (runtime, _) = try makeRuntime()
        runtime.refreshEqualizerState()
        runtime.recordsDispatchedEventsForTesting = true

        runtime.refreshEqualizerState()
        runtime.refreshEqualizerState()

        XCTAssertTrue(runtime.dispatchedSystemEventsForTesting.isEmpty)
    }

    /// A preset moves eleven things at once and the skin hears about all of them.
    func testAPresetAnnouncesEveryValueItMoved() throws {
        let (runtime, equalizer) = try makeRuntime()
        runtime.refreshEqualizerState()
        runtime.recordsDispatchedEventsForTesting = true

        equalizer.preamp = 30
        equalizer.bands = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

        runtime.refreshEqualizerState()

        XCTAssertEqual(events(runtime, "oneqpreampchanged"), [[30]])
        XCTAssertEqual(events(runtime, "oneqbandchanged").count, 10)
    }

    /// `System.setEqBand` announces itself, exactly as `setVolume` does — and the funnel's
    /// change-only rule is what keeps a handler that writes the band it was just told about from
    /// being told about its own write a second time.
    func testAScriptsOwnWriteIsAnnouncedOnce() throws {
        let (runtime, program) = try makeRuntimeAndProgram()
        runtime.refreshEqualizerState()
        runtime.recordsDispatchedEventsForTesting = true

        _ = try runtime.invoke(method: "setEqBand", on: MakiObjectReference(.system),
                               arguments: [.integer(2), .integer(88)], program: program)
        runtime.refreshEqualizerState()

        XCTAssertEqual(events(runtime, "oneqbandchanged"), [[2, 88]])
    }

    // MARK: - The sliders the skin reads instead of the event

    /// multipass's eleven `ledfillbar` bars do not read the event's value at all: each one re-reads
    /// its `parentslider`'s position from the handler. So the skin's own EQ sliders are put on the new
    /// value **before** the events go out, or every bar answers with the position it already had.
    func testTheSkinsOwnEqualizerSlidersFollowTheHostBeforeTheEventGoesOut() throws {
        let (runtime, equalizer) = try makeRuntime()
        runtime.refreshEqualizerState()
        let band = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "eq.band.1").first)
        let preamp = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "eq.preamp").first)

        // Full boost and full cut, at the two ends of the 0…255 position a slider reports.
        equalizer.bands[0] = 127
        equalizer.preamp = -127
        runtime.refreshEqualizerState()

        XCTAssertEqual(band.attributes["value"], "255")
        XCTAssertEqual(preamp.attributes["value"], "0")

        equalizer.bands[0] = 0
        runtime.refreshEqualizerState()
        XCTAssertEqual(band.attributes["value"], "128", "flat is the middle of the slider's travel")
    }

    /// The same rule the decoder has always had: an out-of-range parameter is not an equalizer
    /// control, so it must be inert rather than band 9.
    func testASliderWithAnUnusableBandParameterIsNotMoved() throws {
        let (runtime, equalizer) = try makeRuntime()
        let stranger = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "eq.band.99").first)
        let before = stranger.attributes["value"]

        equalizer.bands = equalizer.bands.map { _ in 60 }
        runtime.refreshEqualizerState()

        XCTAssertEqual(stranger.attributes["value"], before)
    }

    // MARK: - Fixture

    /// The 0…255 position an `EQ_BAND`/`EQ_PREAMP` slider reports, and what the events carry.
    private final class Equalizer {
        var bands = Array(repeating: 0, count: WinampModernEQAction.bandCount)
        var preamp = 0
    }

    private func events(_ runtime: WinampModernScriptRuntime, _ name: String) -> [[Int]] {
        runtime.dispatchedSystemEventsForTesting
            .filter { $0.event == name }
            .map { $0.arguments.map { Int($0.integerValue) } }
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, Equalizer) {
        let (runtime, equalizer, _) = try makeParts()
        return (runtime, equalizer)
    }

    private func makeRuntimeAndProgram() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let (runtime, _, program) = try makeParts()
        return (runtime, program)
    }

    private func makeParts() throws -> (WinampModernScriptRuntime, Equalizer, MakiProgram) {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="120">
              <slider id="eq.preamp" action="EQ_PREAMP" x="0" y="0" w="10" h="60" orientation="vertical"/>
              <slider id="eq.band.1" action="EQ_BAND" param="1" x="12" y="0" w="10" h="60" orientation="vertical"/>
              <slider id="eq.band.99" action="EQ_BAND" param="99" x="24" y="0" w="10" h="60" orientation="vertical"/>
              <slider id="volume" action="VOLUME" x="36" y="0" w="10" h="60" orientation="vertical"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let equalizer = Equalizer()
        runtime.equalizerBandRequested = { equalizer.bands.indices.contains($0) ? equalizer.bands[$0] : 0 }
        runtime.equalizerBandSetterRequested = { band, value in
            guard equalizer.bands.indices.contains(band) else { return }
            equalizer.bands[band] = value
        }
        runtime.equalizerPreampRequested = { equalizer.preamp }
        runtime.equalizerPreampSetterRequested = { equalizer.preamp = $0 }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, equalizer, program)
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase41Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase41-\(UUID().uuidString).wal")
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

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var balance: Double = 0
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

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
}
