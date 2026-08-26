import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 73 — B51: the `<vis>` oscilloscope draws a real waveform, and the attributes a skin's own
/// visualization page writes stop being ignored.
///
/// The scope used to be drawn from the **spectrum band levels**, alternating each band above and
/// below the centre line — a zigzag whose only relationship to the audio was its envelope. The
/// premise was that the host publishes a spectrum and not raw PCM, and it was wrong: `AudioEngine`
/// has always posted Winamp's own `visdata` waveform (576 `UInt8` samples per channel, centred on
/// 128), consumer-gated, and vis_classic and the waveform views were already reading it.
///
/// Alongside it, every other `<vis>` attribute was ignored — `oscstyle`, `peaks`, `falloff`,
/// `peakfalloff`, `coloring`, and `colorosc2`…`colorosc5` — which is why the whole visualization
/// settings page of a skin that ships one (Big Bento Modern, Love is War Miku) did nothing.
///
/// **The falloff range is measured, not assumed.** `WINAMP_MODERN_RENDER_DISASM=@player-normal-group`
/// against Big Bento Modern: its menu checkmarks each of Slower / Slow / Moderate / Fast / Faster
/// with `value == 0` … `value == 4`, and the same listing shows `peaks` written as `"0"`/`"1"` and
/// `coloring` as the words `Normal` / `Fire` / `Line`. The values are written by MAKI at runtime, so
/// no markup in the corpus states them.
final class WinampModernPhase73Tests: XCTestCase {

    // MARK: - The attributes a skin's visualization menu writes

    /// Winamp's own spellings, as the skins' scripts write them.
    func testOscilloscopeStyleIsDecodedFromTheSkinsOwnSpelling() {
        XCTAssertEqual(style(["oscstyle": "Solid"]).oscStyle, .solid)
        XCTAssertEqual(style(["oscstyle": "Dots"]).oscStyle, .dots)
        XCTAssertEqual(style(["oscstyle": "Lines"]).oscStyle, .lines)
        // Winamp's default, and what an unknown value has to fall back to rather than drawing nothing.
        XCTAssertEqual(style([:]).oscStyle, .lines)
        XCTAssertEqual(style(["oscstyle": "wobbly"]).oscStyle, .lines)
    }

    func testColoringIsDecodedFromTheSkinsOwnSpelling() {
        XCTAssertEqual(style(["coloring": "Fire"]).coloring, .fire)
        XCTAssertEqual(style(["coloring": "Line"]).coloring, .line)
        XCTAssertEqual(style(["coloring": "Normal"]).coloring, .normal)
        XCTAssertEqual(style([:]).coloring, .normal)
    }

    /// `peaks="0"` is the only thing that turns the caps off; anything else — including the attribute
    /// being absent — leaves Winamp's default of caps on.
    func testPeaksIsOffOnlyForAnExplicitZero() {
        XCTAssertFalse(style(["peaks": "0"]).showsPeaks)
        XCTAssertTrue(style(["peaks": "1"]).showsPeaks)
        XCTAssertTrue(style([:]).showsPeaks)
    }

    /// The measured 0…4 scale, in order, with the slowest actually slower than the fastest — and a
    /// value outside the range clamped rather than trapping on an index.
    func testFalloffStepsRunSlowerToFasterAndClamp() {
        XCTAssertEqual(WasabiVisStyle.falloffStep("0"), 0)
        XCTAssertEqual(WasabiVisStyle.falloffStep("4"), 4)
        // Absent means Moderate, the middle of the skin's own menu.
        XCTAssertEqual(WasabiVisStyle.falloffStep(nil), 2)
        XCTAssertEqual(WasabiVisStyle.falloffStep("nonsense"), 2)
        XCTAssertEqual(WasabiVisStyle.falloffStep("-3"), 0, "clamped, not negative-indexed")
        XCTAssertEqual(WasabiVisStyle.falloffStep("99"), 4, "clamped, not out of bounds")

        XCTAssertLessThan(style(["falloff": "0"]).barFalloff, style(["falloff": "4"]).barFalloff)
        XCTAssertLessThan(style(["peakfalloff": "0"]).peakFalloff,
                          style(["peakfalloff": "4"]).peakFalloff)
        XCTAssertEqual(style(["falloff": "2"]).barFalloff, WasabiVisStyle.barFalloffSteps[2])
    }

    /// Both scales are **per second**, not per draw. Draws are not a clock — `updateSpectrum` drops
    /// frames when a scene is expensive — so a per-draw constant would make "Slower…Faster" mean
    /// different things on different skins and window widths.
    func testFalloffIsAppliedPerSecondSoTheRateIsIndependentOfTheFrameRate() {
        let fast = WasabiVisStyle.peakFalloffSteps[4]
        let slow = WasabiVisStyle.peakFalloffSteps[0]
        // A cap falling at "Faster" clears a full box in well under a second; at "Slower" it does not.
        XCTAssertGreaterThan(fast * 1.0, 1.0, "Faster empties the box within a second")
        XCTAssertLessThan(slow * 1.0, 1.0, "Slower does not")
    }

    // MARK: - Colours

    /// Winamp bands the scope by **excursion** into five colour steps, which is why a skin declares
    /// five. Only `colorosc1` was ever read, so Big Bento's four scopes drew one flat line where the
    /// skin asked for a gradient.
    func testOscilloscopeColourStepsByExcursion() {
        let decoded = style(["colorosc1": "10,0,0", "colorosc2": "20,0,0", "colorosc3": "30,0,0",
                             "colorosc4": "40,0,0", "colorosc5": "50,0,0"])
        XCTAssertEqual(decoded.oscColors.count, 5)
        XCTAssertEqual(red(decoded.oscColor(excursion: 0)), 10)
        XCTAssertEqual(red(decoded.oscColor(excursion: 0.5)), 30)
        XCTAssertEqual(red(decoded.oscColor(excursion: 1)), 50, "full excursion takes the last step")
        XCTAssertEqual(red(decoded.oscColor(excursion: 4)), 50, "and cannot run off the end")
    }

    /// `colorallbands` stands in for every band **and** every scope colour a skin does not declare —
    /// Rika asks for `colorallbands="0,0,0"` and nothing else.
    func testColorAllBandsStandsInForBothFamilies() {
        let decoded = style(["colorallbands": "7,0,0"])
        XCTAssertEqual(red(decoded.barColor(index: 3, count: 16, level: 0.5)), 7)
        XCTAssertEqual(red(decoded.oscColor(excursion: 0.2)), 7)
    }

    /// The three `coloring` modes have to be visibly different, which is the whole reason the menu
    /// item exists: by band index, by the bar's own height, or one colour throughout.
    func testColoringPicksTheBandByIndexByHeightOrNotAtAll() {
        var attributes: [String: String] = [:]
        for band in 1...16 { attributes["colorband\(band)"] = "\(band),0,0" }

        let normal = style(attributes)
        XCTAssertEqual(red(normal.barColor(index: 0, count: 16, level: 1)), 1)
        XCTAssertEqual(red(normal.barColor(index: 15, count: 16, level: 0)), 16,
                       "by band, whatever the height")

        attributes["coloring"] = "Fire"
        let fire = style(attributes)
        XCTAssertEqual(red(fire.barColor(index: 0, count: 16, level: 0)), 1)
        XCTAssertEqual(red(fire.barColor(index: 0, count: 16, level: 0.99)), 16,
                       "by height, whatever the band")

        attributes["coloring"] = "Line"
        let line = style(attributes)
        XCTAssertEqual(red(line.barColor(index: 0, count: 16, level: 0)), 1)
        XCTAssertEqual(red(line.barColor(index: 15, count: 16, level: 1)), 1, "one colour throughout")
    }

    // MARK: - The waveform tap

    /// **Chunks are queued and played out, not overwritten.** `AudioEngine.processAudioBuffer` runs
    /// once per 2048-frame buffer — about every 46 ms — and posts every 576-sample chunk it can from
    /// inside that one call, so they arrive three or four at a time. Keeping only the newest threw
    /// three quarters of the audio away and left the survivors 46 ms apart, which is what a scope
    /// that jumps actually is.
    func testBurstedChunksArePlayedOutInOrderRatherThanOverwritingEachOther() {
        let tap = WinampModernWaveformTap(consumerId: "test")
        // A burst, as the audio tap delivers it: three chunks at the same instant.
        for value in [10, 20, 30] as [UInt8] {
            tap.receive(left: chunk(value), right: chunk(value), sampleRate: 44_100, at: 100)
        }
        let step = 576.0 / 44_100
        XCTAssertEqual(tap.samples(at: 100).left.first, 10, "the first is current immediately")
        XCTAssertEqual(tap.samples(at: 100 + step * 1.5).left.first, 20)
        XCTAssertEqual(tap.samples(at: 100 + step * 2.5).left.first, 30)
    }

    /// A read is a pure function of the clock: the six boxes of a skin like Big Bento all draw the
    /// same chunk within one frame, and a frame drawn twice draws the same thing. (The renderer takes
    /// the waveform once per frame as well, so the two halves of a mirrored pair cannot straddle a
    /// chunk boundary — this is the property that makes that safe.)
    func testReadingTheSameInstantTwiceAnswersTheSameChunk() {
        let tap = WinampModernWaveformTap(consumerId: "test")
        for value in [10, 20] as [UInt8] {
            tap.receive(left: chunk(value), right: chunk(value), sampleRate: 44_100, at: 100)
        }
        let instant = 100 + (576.0 / 44_100) * 1.5
        XCTAssertEqual(tap.samples(at: instant).left.first, tap.samples(at: instant).left.first)
        XCTAssertEqual(tap.samples(at: instant).left.first, 20)
    }

    /// An underrun — the next buffer is late — holds the chunk on screen rather than blanking it.
    func testAnUnderrunHoldsTheLastChunkRatherThanBlanking() {
        let tap = WinampModernWaveformTap(consumerId: "test")
        tap.receive(left: chunk(42), right: chunk(42), sampleRate: 44_100, at: 100)
        XCTAssertEqual(tap.samples(at: 100 + 0.1).left.first, 42,
                       "still inside the silence timeout, so this is jitter, not silence")
    }

    /// **Silence has to reach the scope.** The tap simply stops posting on pause, stop, end of track
    /// or a move to a cast device — there is no "zero" notification — so without this the last
    /// waveform hangs on screen forever.
    func testTheScopeFlattensToTheCentreLineOnceTheAudioStops() {
        let tap = WinampModernWaveformTap(consumerId: "test")
        tap.receive(left: chunk(200), right: chunk(200), sampleRate: 44_100, at: 100)
        let quiet = tap.samples(at: 100 + WinampModernWaveformTap.silenceTimeout + 0.01)
        XCTAssertEqual(quiet.left, WinampModernWaveformTap.silence)
        XCTAssertEqual(quiet.right, WinampModernWaveformTap.silence)
        XCTAssertEqual(WinampModernWaveformTap.centre, 128, "Winamp's visdata centres on 128")
    }

    /// The queue is bounded, so a scope cannot drift further behind the music every buffer: past the
    /// cap the oldest chunks go and the clock resynchronises.
    func testTheQueueIsBoundedSoTheScopeCannotDriftBehindTheMusic() {
        let tap = WinampModernWaveformTap(consumerId: "test")
        for value in 1...20 {
            tap.receive(left: chunk(UInt8(value)), right: chunk(UInt8(value)),
                        sampleRate: 44_100, at: 100)
        }
        // The most recent chunks survive, not the oldest: what is on screen stays near the sound.
        let shown = tap.samples(at: 100).left.first
        XCTAssertNotNil(shown)
        XCTAssertGreaterThanOrEqual(Int(shown ?? 0), 20 - WinampModernWaveformTap.maximumQueuedChunks)
    }

    // MARK: - What the renderer asks the host for

    /// The tap is real-time audio work, so it stays off unless a skin actually declares a scope —
    /// and it comes on when one does, including when a script switches the mode at runtime.
    func testTheWaveformTapIsDemandedOnlyByABoxThatDrawsAWaveform() throws {
        let host = Host()
        let renderer = try makeRenderer(host: host, body: """
            <vis id="analyzer" x="0" y="0" w="30" h="20" mode="1"/>
            """)
        renderer.refreshWaveformDemand()
        XCTAssertEqual(host.waveformNeeded, false, "an analyzer reads the spectrum, not PCM")

        renderer.setVisualizationAttribute("mode", value: "2")
        renderer.refreshWaveformDemand()
        XCTAssertEqual(host.waveformNeeded, true)
        XCTAssertTrue(renderer.visualizationNeedsWaveform)
    }

    /// **Any** box, not all of them: one scope among five analyzers still needs PCM. Big Bento's
    /// header is exactly that shape.
    func testOneScopeAmongSeveralAnalyzersStillDemandsTheWaveform() throws {
        let host = Host()
        let renderer = try makeRenderer(host: host, body: """
            <vis id="a" x="0" y="0" w="10" h="10" mode="1"/>
            <vis id="b" x="10" y="0" w="10" h="10" mode="1"/>
            <vis id="c" x="20" y="0" w="10" h="10" mode="2"/>
            """)
        renderer.refreshWaveformDemand()
        XCTAssertEqual(host.waveformNeeded, true)
    }

    /// Pushed only when the answer **moves**. The demand is recomputed against the graph's mutation
    /// counter — the key `sceneNodes()` already uses, and the one thing both writers of `mode` move
    /// (`setVisualizationAttribute` and MAKI's `setMode`/`setXmlParam`, which write the object
    /// directly; Big Bento's own visualization menu is entirely the second kind).
    func testTheDemandIsPushedOnAChangeAndNotOnEveryFrame() throws {
        let host = Host()
        let renderer = try makeRenderer(host: host, body: """
            <vis id="scope" x="0" y="0" w="30" h="20" mode="2"/>
            """)
        renderer.refreshWaveformDemand()
        XCTAssertEqual(host.waveformNeededWrites, 1)
        for _ in 0..<10 { renderer.refreshWaveformDemand() }
        XCTAssertEqual(host.waveformNeededWrites, 1, "a graph that did not move costs nothing")

        renderer.setVisualizationAttribute("mode", value: "1")
        renderer.refreshWaveformDemand()
        XCTAssertEqual(host.waveformNeededWrites, 2)
        XCTAssertEqual(host.waveformNeeded, false)
    }

    /// **The spectrum guard belonged to the analyzer, not to the box.** It used to open
    /// `drawVisualization`, so with nothing playing — `endVisualizationConsumption` clears the levels,
    /// and they are empty before the first tap after a skin load — a scope could not even paint its
    /// flat centre line, which is half of what the silence decay exists to make visible.
    func testAScopePaintsWithNoSpectrumAtAllWhileAnAnalyzerDoesNot() throws {
        let scope = try render(body: """
            <vis id="scope" x="0" y="0" w="32" h="32" mode="2" colorallbands="255,255,255"/>
            """)
        XCTAssertTrue(scope.contains { $0 != 0 },
                      "a scope draws its centre line from PCM and never reads the spectrum")

        let analyzer = try render(body: """
            <vis id="analyzer" x="0" y="0" w="32" h="32" mode="1" colorallbands="255,255,255"/>
            """)
        XCTAssertFalse(analyzer.contains { $0 != 0 },
                       "an analyzer with no bands has nothing to draw")
    }

    /// `mode="3"` is MMD3's own animated display, and an unrecognised mode must stay silent rather
    /// than painting over the skin's artwork. Unchanged by this work, and the sweep's canary for it.
    func testAnUnknownModeStillPaintsNothing() throws {
        let pixels = try render(body: """
            <vis id="off" x="0" y="0" w="32" h="32" mode="3" colorallbands="255,255,255"/>
            """)
        XCTAssertFalse(pixels.contains { $0 != 0 })
    }

    // MARK: - Helpers

    private func style(_ attributes: [String: String]) -> WasabiVisStyle {
        WasabiVisStyle.decode(attributes: attributes) { raw in
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 3 else { return WasabiVisStyle.white }
            return CGColor(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: 1)
        }
    }

    /// The red channel back as the 0…255 the fixture declared, so a colour choice is readable.
    private func red(_ color: CGColor) -> Int {
        Int(((color.components?.first ?? 0) * 255).rounded())
    }

    private func chunk(_ value: UInt8) -> [UInt8] {
        [UInt8](repeating: value, count: WinampModernWaveformTap.sampleCount)
    }

    /// A host with no audio: the spectrum is empty and the waveform is the flat centre line, which is
    /// exactly the state a skin loads in.
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []
        var waveformNeeded: Bool?
        var waveformNeededWrites = 0

        func setWaveformNeeded(_ needed: Bool) {
            waveformNeeded = needed
            waveformNeededWrites += 1
        }

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

    private func makeRenderer(host: Host, body: String) throws -> WasabiSceneRenderer {
        let loaded = try load(xml: skin(size: 32, body: body))
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    /// The layout painted into a transparent 32×32 bitmap; a byte that is not zero is a pixel the
    /// skin drew.
    private func render(body: String) throws -> [UInt8] {
        let renderer = try makeRenderer(host: Host(), body: body)
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let context = try XCTUnwrap(pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        })
        renderer.draw(in: context)
        return pixels
    }

    private func skin(size: Int, body: String) -> String {
        """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="\(size)" h="\(size)">
        \(body)
            </layout>
          </container>
        </WasabiXML>
        """
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase73Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase73-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            payload.subdata(in: Int(position)..<Int(position) + size)
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
