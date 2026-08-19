import XCTest
import ZIPFoundation
@testable import NullPlayer
@testable import NullPlayerCore

/// Phases 28–29 — **Layer FX**, and the frame budget it has to run inside.
///
/// Phase 28 made every Defix display style move; Phase 29 made the motion smooth and the VU meters
/// answer the music. The two halves are tested together because they are one mechanism: a warp that
/// is evaluated correctly still looks broken if the frames carrying it arrive unevenly, and a level
/// that is scaled correctly still looks dead if it arrives late.
///
/// Everything here is a regression that was *invisible* to the suite when it happened — the unary
/// minus that gave Defix's needle two positions, the whole-window repaint at the audio clock's rate,
/// the RMS level that put the needle in the bottom sixth of its sweep.
final class WinampModernPhase28Tests: XCTestCase {
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

    // MARK: - The interpreter

    /// A handler's answer has to leave the interpreter: Layer FX *is* a return value — the skin is
    /// asked where to sample from and replies. Before this, `execute` discarded the stack at `return`
    /// and every `fx_onGetPixel*` answered nil, i.e. the identity warp.
    func testExecuteReturnsTheValueLeftAtReturn() throws {
        var code = Data()
        code.append(pushVariable(2))            // the integer 7
        code.append(Data([33]))                 // return
        let program = try MakiBytecodeParser().parse(makeScript(code: code),
                                                     source: WalSourceLocation(path: "/return.maki"))
        // The interpreter holds its dispatcher weakly, so it has to outlive the call.
        let dispatcher = NoOpDispatcher()
        let value = try MakiInterpreter(dispatcher: dispatcher).execute(program: program, at: 0)
        XCTAssertEqual(value.integerValue, 7)
    }

    /// **The Phase 28 needle bug.** Unary minus (opcode 76) negated through `integerValue`, so
    /// `-(0.29)` was `-0` and `-(1.4)` was `-1`. Defix's needle angle is `range * -(level/127)`, which
    /// left it with exactly two positions — rest, and full deflection — for every level in between.
    ///
    /// A double in, a double out, fraction intact. This is the assertion that was missing.
    func testUnaryMinusKeepsADoubleADouble() throws {
        var code = Data()
        code.append(pushVariable(5))            // the double 2.55
        code.append(Data([76]))                 // unary minus
        code.append(Data([33]))                 // return
        let program = try MakiBytecodeParser().parse(makeScript(code: code),
                                                     source: WalSourceLocation(path: "/negate.maki"))
        // The interpreter holds its dispatcher weakly, so it has to outlive the call.
        let dispatcher = NoOpDispatcher()
        let value = try MakiInterpreter(dispatcher: dispatcher).execute(program: program, at: 0)
        // The tolerance is the fixture's, not the opcode's: MAKI stores the constant at single
        // precision. What matters is that the fraction is still there at all — the bug turned it
        // into -2.
        XCTAssertEqual(value.doubleValue, -2.55, accuracy: 1e-6,
                       "negation must not truncate the operand to an integer")
    }

    /// Integers keep negating as integers — the fix is about preserving the operand's type, not about
    /// promoting everything to floating point.
    func testUnaryMinusKeepsAnIntegerAnInteger() throws {
        var code = Data()
        code.append(pushVariable(2))            // the integer 7
        code.append(Data([76]))
        code.append(Data([33]))
        let program = try MakiBytecodeParser().parse(makeScript(code: code),
                                                     source: WalSourceLocation(path: "/negate-int.maki"))
        // The interpreter holds its dispatcher weakly, so it has to outlive the call.
        let dispatcher = NoOpDispatcher()
        let value = try MakiInterpreter(dispatcher: dispatcher).execute(program: program, at: 0)
        XCTAssertEqual(value.integerValue, -7)
    }

    // MARK: - `fx_*` state

    /// Every setter writes the layer's own state and every getter answers from it. A skin configures
    /// its warp once in `onScriptLoaded` and never asks again, so a setter that silently dropped its
    /// value would show up only as "the warp looks wrong", never as an error.
    func testLayerFXSettersAndGettersRoundTrip() throws {
        let (runtime, program, layer) = try makeFXRuntime()
        let reference = MakiObjectReference(.gui(layer.stableID))
        func call(_ method: String, _ arguments: [MakiValue] = []) throws -> MakiValue {
            try runtime.invoke(method: method, on: reference, arguments: arguments, program: program)
        }

        XCTAssertNil(runtime.layerFXState(of: layer), "a layer has no FX state until its script asks")
        _ = try call("fx_setEnabled", [.boolean(true)])
        _ = try call("fx_setRect", [.boolean(true)])
        _ = try call("fx_setWrap", [.boolean(true)])
        _ = try call("fx_setBilinear", [.boolean(false)])
        _ = try call("fx_setGridSize", [.integer(4), .integer(3)])

        let state = try XCTUnwrap(runtime.layerFXState(of: layer))
        XCTAssertTrue(state.enabled)
        XCTAssertTrue(state.rect)
        XCTAssertTrue(state.wrap)
        XCTAssertFalse(state.bilinear)
        // Winamp's grid counts *cells*; the mesh is one vertex larger on each axis.
        XCTAssertEqual(state.vertexColumns, 5)
        XCTAssertEqual(state.vertexRows, 4)

        XCTAssertTrue(try call("fx_getEnabled").truthy)
        XCTAssertTrue(try call("fx_getWrap").truthy)
        XCTAssertFalse(try call("fx_getBilinear").truthy)
        XCTAssertTrue(runtime.hasEnabledLayerFX)
    }

    /// A layer whose script answers nothing produces the identity mesh, and the renderer is handed
    /// `nil` for it rather than a warp that resamples the image onto itself — a pixel loop for no
    /// visible change, on the paint path, every frame.
    func testAnEnabledLayerWithNoCallbacksWarpsNothing() throws {
        let (runtime, program, layer) = try makeFXRuntime()
        _ = try runtime.invoke(method: "fx_setEnabled", on: MakiObjectReference(.gui(layer.stableID)),
                               arguments: [.boolean(true)], program: program)
        XCTAssertNil(runtime.layerFXMesh(for: layer))
    }

    /// **Phase 29.** Evaluating a mesh runs the skin's callbacks per grid vertex through the
    /// interpreter. Doing that lazily from the renderer put all of it inside `NSView.draw`; the
    /// window's animation clock now calls `refreshLayerFXMeshes()` first, so the paint finds the work
    /// already done. The observable contract is that a refreshed layer has nothing left pending.
    func testRefreshLayerFXMeshesClearsTheWorkBeforeThePaint() throws {
        let (runtime, program, layer) = try makeFXRuntime()
        _ = try runtime.invoke(method: "fx_setEnabled", on: MakiObjectReference(.gui(layer.stableID)),
                               arguments: [.boolean(true)], program: program)
        runtime.invalidateLayerFXMesh(for: layer)
        XCTAssertTrue(runtime.layerFXMeshIsPending(for: layer))
        runtime.refreshLayerFXMeshes()
        XCTAssertFalse(runtime.layerFXMeshIsPending(for: layer),
                       "the mesh must be built off the paint path, not when the frame is drawn")
    }

    // MARK: - The mesh and the resampler

    /// The coordinate conventions have to be each other's inverse, or the forward half (destination →
    /// polar) and the inverse half (polar → source) drift and the warp shears.
    func testPolarCoordinatesRoundTrip() {
        for (x, y) in [(0.0, 0.0), (1.0, 0.0), (0.5, 0.0), (0.25, 0.75), (1.0, 1.0)] {
            let angle = WasabiLayerFXCoordinates.angle(x: x, y: y)
            let distance = WasabiLayerFXCoordinates.distance(x: x, y: y)
            let point = WasabiLayerFXCoordinates.point(angle: angle, distance: distance)
            XCTAssertEqual(Double(point.x), x, accuracy: 1e-9)
            XCTAssertEqual(Double(point.y), y, accuracy: 1e-9)
        }
    }

    /// A mesh that samples every vertex from its own position is the identity, and one rotated off it
    /// is not. This is the test the renderer's "is this layer actually moving?" check rests on.
    func testIdentityMeshIsRecognised() {
        XCTAssertTrue(makeRotationMesh(radians: 0).isIdentity)
        XCTAssertFalse(makeRotationMesh(radians: .pi / 2).isIdentity)
    }

    /// A half-turn maps every pixel to its opposite corner. Built from the same polar helpers the
    /// skin's callbacks answer through, so this exercises the whole geometry — the forward mapping,
    /// the mesh interpolation and the inverse sample — against an answer that can be written down.
    func testResampleRotatesTheImageByHalfATurn() throws {
        let width = 8, height = 8
        var source = [UInt8](repeating: 0, count: width * height * 4)
        // One opaque red pixel in the top-left corner.
        source[0] = 255; source[3] = 255
        let rotated = try XCTUnwrap(makeRotationMesh(radians: .pi)
            .resample(source: source, width: width, height: height))
        let opposite = ((height - 1) * width + (width - 1)) * 4
        XCTAssertEqual(rotated[opposite], 255, "the marked pixel lands in the opposite corner")
        XCTAssertEqual(rotated[opposite + 3], 255)
        XCTAssertEqual(rotated[0], 0, "and nothing is left where it came from")
    }

    /// A mesh that does not describe a grid at all cannot resample, and says so rather than
    /// half-filling the destination.
    func testResampleRejectsAMalformedMesh() {
        let mesh = WasabiLayerFXMesh(columns: 2, rows: 2, sources: [.zero], wrap: false, bilinear: true)
        XCTAssertNil(mesh.resample(source: [UInt8](repeating: 0, count: 16), width: 2, height: 2))
    }

    // MARK: - `onSetVisible`

    /// **What switches the reels on.** A skin starts its animation from `onSetVisible`, and
    /// `orderFront` is an AppKit call the graph never hears about. Dispatched once per *change*: a
    /// window told it is visible twice must not restart the animation the second time.
    func testContainerVisibilityIsAnnouncedOncePerChange() throws {
        let (runtime, _, _) = try makeFXRuntime()
        var mutations = 0
        runtime.graphDidMutate = { mutations += 1 }
        let container = try XCTUnwrap(runtime.loadedSkin.runtime.graph.roots.first {
            $0.typeName.caseInsensitiveCompare("container") == .orderedSame
        })
        runtime.notifyContainerVisibility(containerID: container.stableID, visible: true)
        XCTAssertEqual(mutations, 1)
        runtime.notifyContainerVisibility(containerID: container.stableID, visible: true)
        XCTAssertEqual(mutations, 1, "an unchanged visibility is not an event")
        runtime.notifyContainerVisibility(containerID: container.stableID, visible: false)
        XCTAssertEqual(mutations, 2)
    }

    // MARK: - The frame budget (Phase 29)

    /// The renderer memoizes its scene walk against the graph's mutation counter. Correctness first:
    /// the cached answer has to change the moment the graph does, or a script that moves a control
    /// would move nothing on screen.
    func testSceneMemoFollowsTheGraph() throws {
        let renderer = try makeRenderer()
        func frame(_ id: String) -> CGRect? {
            renderer.sceneNodes().first { $0.object.xmlID == id }?.frame
        }
        XCTAssertEqual(frame("moving")?.minX, 10)
        let moving = try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "moving" }?.object)
        _ = moving.setAttribute("x", value: "60")
        XCTAssertEqual(frame("moving")?.minX, 60, "the memo must not survive the change it describes")
    }

    /// Drawing the same unchanged scene twice must produce the same pixels. The pre-scaled artwork
    /// cache is the reason a Defix frame costs 3.5 ms at Retina scale instead of 18.3, and it is only
    /// legitimate because the second frame is *identical* to the first — the same `.high` resample,
    /// kept rather than repeated.
    func testWarmCachesDrawTheSamePixels() throws {
        let renderer = try makeRenderer()
        let first = try XCTUnwrap(drawToPixels(renderer, scale: 2))
        let second = try XCTUnwrap(drawToPixels(renderer, scale: 2))
        XCTAssertEqual(first, second, "a warm cache must be a faster frame, not a different one")
    }

    // MARK: - What repaints when the clock ticks

    /// **The measured cause of the choppy cassette.** `updateTime` runs ten times a second and used
    /// to invalidate the whole window, which is 18 ms of Retina bitmap drawing per tick on the same
    /// main thread the skin's 30 Hz animation needs. Only what the renderer actually draws from
    /// `host.currentTime` is invalidated now: an elapsed-time readout, a seek slider, a seek bar.
    @MainActor
    func testOnlyClockDrivenObjectsAreInvalidatedByTheTimeTick() throws {
        let view = try makeView()
        let rects = view.timeDependentRects()
        XCTAssertEqual(rects.count, 3, "the clock readout, the seek slider and the seek bar — no more")
        // The volume slider and the song title are on the same layout and must not be in the set:
        // one follows the volume, the other the track, and neither moves ten times a second. The
        // slider sits at skin y 80…90, which in the view's bottom-left space is y 30…40.
        let volume = NSRect(x: 0, y: 30, width: 20, height: 10)
        XCTAssertFalse(rects.contains { $0.intersects(volume.insetBy(dx: 1, dy: 1)) },
                       "the volume slider is not clock-driven")
    }

    // MARK: - The VU scale

    /// **Peak, not RMS** (Phase 29). The skin does its own perceptual mapping and its own ballistics;
    /// the host's job is to hand it the excursion Winamp hands it. A signal that peaks at full scale
    /// but sits low in energy — which is all music — must not arrive as a level near zero.
    func testPeakAndRMSDisagreeExactlyWhereTheNeedleDid() {
        // A sparse transient: one full-scale sample in a quiet buffer.
        var samples = [Float](repeating: 0.02, count: 512)
        samples[100] = 1.0
        let peak = WinampModernLevelMeter.amplitude(dbfs: Double(AudioAnalysisDSP.peakDBFS(samples)))
        let rms = WinampModernLevelMeter.amplitude(dbfs: Double(AudioAnalysisDSP.rmsDBFS(samples)))
        XCTAssertEqual(peak, 1.0, accuracy: 1e-6)
        XCTAssertLessThan(rms, 0.06, "the RMS of the same buffer is what pinned the needle to its rest")
    }

    /// **The dynamics live inside the buffer.** Peak over a *whole* tap buffer is nearly constant on
    /// dense music — the buffer is 50–100 ms and something in it is always loud — which is why the
    /// needle sat high and still. Split into Winamp-sized blocks, the same buffer has a quiet half
    /// and a loud half, and that difference is what the needle is supposed to show.
    func testBlockPeaksSeeWhatTheWholeBufferPeakHides() {
        var samples = [Float](repeating: 0.02, count: 512)
        for index in 256..<512 { samples[index] = 0.8 }
        let whole = WinampModernLevelMeter.amplitude(dbfs: Double(AudioAnalysisDSP.peakDBFS(samples)))
        let blocks = WinampModernLevelMeter.blockPeaks(samples, count: 4)

        XCTAssertEqual(whole, 0.8, accuracy: 1e-3, "one number for the buffer, and it is the loud half")
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0], 0.02, accuracy: 1e-3)
        XCTAssertEqual(blocks[3], 0.8, accuracy: 1e-3)
    }

    /// An arriving buffer is handed out one block at a time as real time passes, so a skin polling
    /// every 17 ms sees successive blocks instead of the same number five times over.
    func testBlocksArePlayedOutInStepWithTheAudio() {
        let meter = WinampModernLevelMeter(consumerId: "test.playout")
        var samples = [Float](repeating: 0, count: 400)
        for index in 200..<400 { samples[index] = 1.0 }
        // Two arrivals 40 ms apart: the second one is the buffer whose cadence is measurable.
        meter.receive(left: samples, right: samples, at: 100)
        meter.receive(left: samples, right: samples, at: 100.04)

        XCTAssertEqual(meter.level(at: 100.041).left, 0, accuracy: 1e-6,
                       "the quiet first half plays first")
        XCTAssertEqual(meter.level(at: 100.075).left, 1, accuracy: 1e-6,
                       "and the loud second half follows it, in time")
    }

    /// **Silence has to reach the meter.** The tap stops posting when playback stops, pauses, ends or
    /// moves to a cast device — there is no "zero" notification — so the last value used to stick and
    /// the needles hung wherever the music left them. Running off the end of the played-out blocks is
    /// the silence signal, after a short hold for the jitter between two taps.
    func testTheMeterFallsToSilenceWhenTheTapStops() {
        let meter = WinampModernLevelMeter(consumerId: "test.silence")
        let loud = [Float](repeating: 1, count: 256)
        meter.receive(left: loud, right: loud, at: 200)
        meter.receive(left: loud, right: loud, at: 200.04)

        XCTAssertEqual(meter.level(at: 200.05).left, 1, accuracy: 1e-6)
        XCTAssertEqual(meter.level(at: 200.09).left, 1, accuracy: 1e-6,
                       "a late buffer is jitter, not a stop — the level holds")
        XCTAssertEqual(meter.level(at: 200.5), .silence,
                       "but audio that has actually stopped reads zero")
    }

    /// Silence is zero and nothing is ever out of range, whatever the measurement answers — a `-inf`
    /// dBFS for a digitally silent buffer used to come through as a `nan` level.
    func testAmplitudeIsBoundedAndSilenceIsZero() {
        XCTAssertEqual(WinampModernLevelMeter.amplitude(dbfs: -.infinity), 0)
        XCTAssertEqual(WinampModernLevelMeter.amplitude(dbfs: .nan), 0)
        XCTAssertEqual(WinampModernLevelMeter.amplitude(dbfs: 0), 1)
        XCTAssertEqual(WinampModernLevelMeter.amplitude(dbfs: 12), 1, "no headroom above full scale")
        XCTAssertEqual(WinampModernLevelMeter.amplitude(dbfs: -6), 0.501, accuracy: 0.001)
    }

    // MARK: - Fixtures

    /// A rotation as a Layer FX mesh, built the way `evaluateLayerFXMesh` builds one: each vertex
    /// asks where to sample from, and a rotation answers "at my own angle, plus this much".
    private func makeRotationMesh(radians: Double) -> WasabiLayerFXMesh {
        let columns = 9, rows = 9
        var sources = [CGPoint](repeating: .zero, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = CGFloat(column) / CGFloat(columns - 1)
                let y = CGFloat(row) / CGFloat(rows - 1)
                let angle = WasabiLayerFXCoordinates.angle(x: x, y: y) + CGFloat(radians)
                let distance = WasabiLayerFXCoordinates.distance(x: x, y: y)
                sources[row * columns + column] = WasabiLayerFXCoordinates.point(angle: angle,
                                                                                 distance: distance)
            }
        }
        return WasabiLayerFXMesh(columns: columns, rows: rows, sources: sources,
                                 wrap: false, bilinear: false)
    }

    private func drawToPixels(_ renderer: WasabiSceneRenderer, scale: CGFloat) -> Data? {
        let width = Int(renderer.canvasSize.width * scale)
        let height = Int(renderer.canvasSize.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        renderer.draw(in: context)
        guard let data = context.data else { return nil }
        return Data(bytes: data, count: width * height * 4)
    }

    private static let sceneXML = """
    <WasabiXML>
      <bitmap id="panel" file="$solid" color="40,40,40" w="120" h="120"/>
      <bitmap id="thumb" file="$solid" color="255,255,255" w="6" h="6"/>
      <container id="main">
        <layout id="normal" w="120" h="120" background="panel">
          <text id="clock" display="time" x="0" y="0" w="40" h="10"/>
          <text id="title" display="songname" x="0" y="10" w="120" h="10"/>
          <slider id="seeker" action="seek" thumb="thumb" x="0" y="40" w="120" h="10"/>
          <progressgrid id="seekbar" action="seek" middle="thumb" x="0" y="60" w="120" h="6"/>
          <slider id="vol" action="volume" thumb="thumb" x="0" y="80" w="20" h="10"/>
          <layer id="moving" image="thumb" x="10" y="100" w="20" h="10"/>
        </layout>
      </container>
    </WasabiXML>
    """

    private func makeRenderer() throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: Self.sceneXML)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    @MainActor
    private func makeView() throws -> WinampModernMainView {
        let loaded = try makeSkin(xml: Self.sceneXML)
        let host = TestHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        let view = WinampModernMainView(renderer: renderer, scripts: runtime, host: host)
        addTeardownBlock { view.teardown() }
        return view
    }

    /// A runtime over one plain layer, which is all a warp needs: `fx_*` is addressed to an object.
    private func makeFXRuntime() throws -> (WinampModernScriptRuntime, MakiProgram, WasabiObject) {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="120" h="120">
              <layer id="reel" x="0" y="0" w="60" h="60"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let layer = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "reel").first)
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, program, layer)
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase28Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase28-\(UUID().uuidString).wal")
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

    private final class NoOpDispatcher: MakiMethodDispatching {
        func signature(for method: String, classGUID: String?) -> MakiMethodSignature? { nil }
        func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                    program: MakiProgram) throws -> MakiValue { .null }
        func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
            MakiObjectReference(.system)
        }
    }

    // MARK: - Bytecode fixtures

    private func pushVariable(_ index: UInt32) -> Data {
        var data = Data([1])
        appendUInt32(index, to: &data)
        return data
    }

    /// One class, one `onscriptloaded` method, and the variables the tests above push:
    /// v2 the integer 7, v5 the double 2.55 (stored as MAKI stores one — low mantissa half, then
    /// exponent plus high half).
    private func makeScript(code: Data) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)

        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))

        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString("onscriptloaded", to: &data)

        appendUInt32(6, to: &data)                                  // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, initial: 7, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.double.rawValue, initial: 13107,
                       initial2: 16419, to: &data)

        appendUInt32(0, to: &data)                                  // constants
        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                initial: UInt16 = 0, initial2: UInt16 = 0, to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)          // subclass
        appendUInt16(initial, to: &data)
        appendUInt16(initial2, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)                      // global
        data.append(system ? 1 : 0)
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(bytes)
    }
}
