import XCTest
import CAvsCore
@testable import NullPlayer

/// libavs (`CAvsCore`) on this machine's architecture, against every bundled preset: loads,
/// survives a legacy save round-trip unchanged, and renders something that moves. Plus the
/// EEL2 JIT (SuperScope) and the `AvsCore` lock under a concurrent editor.
final class AvsCoreSmokeTests: XCTestCase {

    private static let presetsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/NullPlayer/Resources/AVSPresets")

    private static var presets: [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: presetsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "avs" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Presets with a component libavs has no implementation for, which loads as Unknown
    /// Effect and draws nothing. FyrewurX is a third-party APE with no portable source.
    private static let unknownEffectPresets: Set<String> = [
        "justin - fireworks kaliadascope mk 2.avs",
        "justin - steve likes it.avs",
    ]

    private let width = 320
    private let height = 240

    func testBundlesAllUpstreamPresets() {
        XCTAssertEqual(Self.presets.count, 35)
    }

    /// The engine finds them through the built bundle, not the source tree.
    func testEngineListsBundledPresets() {
        XCTAssertEqual(AvsPresets.all().filter { $0.path.hasPrefix(AvsPresets.bundledFolder?.path ?? "/nonexistent") }.count, 35)
    }

    func testEveryPresetLoadsAndLegacyRoundTripIsIdempotent() throws {
        for url in Self.presets {
            let core = try XCTUnwrap(AvsCore())
            XCTAssertTrue(core.loadPreset(at: url), "\(url.lastPathComponent): \(core.lastError)")
            let first = core.withHandle { legacyBytes($0) }
            let second: [UInt8]? = core.withHandle { handle in
                guard let first else { return nil }
                guard avs_preset_set_legacy(handle, first, first.count) else { return nil }
                return legacyBytes(handle)
            }
            XCTAssertNotNil(first, "\(url.lastPathComponent): legacy save failed")
            if let first, let second, first != second {
                let at = zip(first, second).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                    ?? min(first.count, second.count)
                XCTFail("\(url.lastPathComponent): legacy save is not stable — \(first.count) vs "
                        + "\(second.count) bytes, first difference at \(at); "
                        + "effects: \(core.withHandle(effectNames))")
            }
        }
    }

    func testEveryPresetRendersMovingPixels() throws {
        for url in Self.presets {
            let core = try XCTUnwrap(AvsCore())
            XCTAssertTrue(core.loadPreset(at: url), url.lastPathComponent)
            if !renderFrames(core, count: 60).moved {
                XCTFail("\(url.lastPathComponent): black and static for 60 frames; "
                        + "effects: \(core.withHandle(effectNames))")
            }
        }
    }

    /// The 'Winamp Starfield v1' and 'Winamp Mosaic v1' APEs load as the built-in Starfield
    /// and Mosaic, so only the FyrewurX presets keep an Unknown Effect.
    func testOnlyUnimplementedEffectsLoadAsUnknown() throws {
        for url in Self.presets {
            let core = try XCTUnwrap(AvsCore())
            XCTAssertTrue(core.loadPreset(at: url), url.lastPathComponent)
            let tree = core.withHandle(effectNames)
            XCTAssertEqual(tree.contains("Unknown Effect"),
                           Self.unknownEffectPresets.contains(url.lastPathComponent),
                           "\(url.lastPathComponent): \(tree)")
        }
    }

    /// SuperScope positions every point by running EEL code, which on arm64 is JIT-compiled
    /// into MAP_JIT pages; a broken JIT crashes or draws nothing.
    func testSuperScopePresetRunsEELCode() throws {
        let core = try XCTUnwrap(AvsCore())
        let url = Self.presetsDirectory.appendingPathComponent("justin - superscope love.avs")
        XCTAssertTrue(core.loadPreset(at: url), core.lastError)
        XCTAssertTrue(renderFrames(core, count: 30).last.contains { $0 & 0x00FF_FFFF != 0 },
                      "SuperScope drew nothing")
    }

    /// The editor writes parameters (and recompiles EEL) from main while frames render on
    /// another thread; `AvsCore.withHandle` must serialise them.
    func testEditorWritesDuringRenderingAreSerialised() throws {
        let core = try XCTUnwrap(AvsCore())
        let url = Self.presetsDirectory.appendingPathComponent("justin - superscope love.avs")
        XCTAssertTrue(core.loadPreset(at: url), core.lastError)

        let rendering = expectation(description: "render thread finished")
        Thread.detachNewThread { [width, height] in
            var pixels = [UInt32](repeating: 0, count: width * height)
            for _ in 0..<200 {
                core.audio.store(Self.pulsedTone(frame: 0))
                pixels.withUnsafeMutableBufferPointer {
                    core.renderFrame(into: $0.baseAddress!, width: width, height: height)
                }
            }
            rendering.fulfill()
        }

        var writes = 0
        for step in 0..<200 {
            core.withHandle { handle in
                var count: UInt32 = 0
                guard let children = avs_component_children(handle, avs_component_root(handle), &count),
                      count > 0 else { return }
                for component in UnsafeBufferPointer(start: children, count: Int(count)) {
                    writes += setFirstStringParameter(handle, component, step) ? 1 : 0
                }
            }
        }
        wait(for: [rendering], timeout: 60)
        XCTAssertGreaterThan(writes, 0, "no string parameter was written")
    }

    /// Beats land on the pulses of the pulsed tone and not on a steady one.
    func testBeatDetectorFiresOnPulsesOnly() {
        var detector = StandardBeatDetector()
        let pulsed = (0..<60).map { frame -> Bool in
            let chunk = Self.waveformChunk(Self.pulsedTone(frame: frame).left)
            return detector.isBeat(left: chunk, right: chunk)
        }
        XCTAssertTrue(pulsed.enumerated().contains { $0.element && $0.offset % 10 < 2 })
        XCTAssertFalse(pulsed.enumerated().contains { $0.element && $0.offset % 10 >= 2 })

        var steadyDetector = StandardBeatDetector()
        let steady = Self.waveformChunk(Self.pulsedTone(frame: 0).left)
        let steadyBeats = (0..<60).filter { _ in
            steadyDetector.isBeat(left: steady, right: steady)
        }
        // The onset fires while the peaks warm up (frames 0–1), then never again.
        XCTAssertTrue(steadyBeats.allSatisfy { $0 < 2 }, "steady tone beat at \(steadyBeats)")
    }

    /// A tap buffer's chunks arrive together; the beat in the fourth is released one frame per
    /// chunk later, at its place in the music, not with the burst.
    func testBeatFeedReleasesABurstAtTheMusicsPace() {
        let feed = BeatFeed()
        let quiet = Self.waveformChunk((0..<576).map { sinf(Float($0) * 0.07) * 0.05 })
        let loud = Self.waveformChunk((0..<576).map { sinf(Float($0) * 0.07) * 0.9 })
        for _ in 0..<20 { feed.store(left: quiet, right: quiet, sampleRate: 44_100) }
        _ = feed.take(nowMs: 0)
        XCTAssertFalse(feed.take(nowMs: 10_000), "the warm-up drains without a beat")

        for chunk in [quiet, quiet, quiet, loud, quiet, quiet, quiet, quiet] {
            feed.store(left: chunk, right: chunk, sampleRate: 44_100)
        }
        // 14 ms a frame is just over a 13.06 ms chunk, so each frame takes one chunk.
        let beats = (1...8).map { feed.take(nowMs: 10_000 + $0 * 14) }
        XCTAssertEqual(beats, [false, false, false, true, false, false, false, false])
    }

    /// The editor's inspector builds its controls from libavs's parameter metadata, so building it
    /// for every component of every bundled preset walks every parameter type those effects use,
    /// lists included.
    @MainActor
    func testInspectorBuildsForEveryComponentOfEveryPreset() throws {
        for url in Self.presets {
            let core = try XCTUnwrap(AvsCore())
            XCTAssertTrue(core.loadPreset(at: url), url.lastPathComponent)
            let inspector = AvsParameterInspector(core: core)
            for component in core.withHandle(allComponents) {
                inspector.show(component)
                XCTAssertFalse(inspector.subviews.first?.subviews.isEmpty ?? true,
                               "\(url.lastPathComponent): component \(component) built no controls")
            }
        }
    }

    // MARK: - Helpers

    private func allComponents(_ handle: AVS_Handle) -> [AVS_Component_Handle] {
        func walk(_ component: AVS_Component_Handle) -> [AVS_Component_Handle] {
            var count: UInt32 = 0
            guard let children = avs_component_children(handle, component, &count), count > 0 else { return [component] }
            return [component] + Array(UnsafeBufferPointer(start: children, count: Int(count))).flatMap(walk)
        }
        return walk(avs_component_root(handle))
    }

    /// The newest 576 samples as `.audioWaveform576DataUpdated` carries them.
    private static func waveformChunk(_ samples: [Float]) -> [UInt8] {
        samples.suffix(576).map { UInt8(clamping: Int($0 * 127 + 128)) }
    }

    /// One 1024-frame buffer of a tone that is loud for 2 frames in every 10: many presets
    /// only colour or move on a beat, which AVS's detector finds in energy jumps.
    private static func pulsedTone(frame: Int) -> AvsAudioSlot.Buffer {
        let amplitude: Float = frame % 10 < 2 ? 0.9 : 0.05
        let samples = (0..<1024).map { sinf(Float($0 + frame * 1024) * 0.07) * amplitude }
        return AvsAudioSlot.Buffer(left: samples, right: samples, sampleRate: 44_100)
    }

    /// Renders `count` frames of the pulsed tone. `moved`: some frame was lit or differed from
    /// the first (a preset may clear to black on a beat, so the last frame alone proves nothing).
    private func renderFrames(_ core: AvsCore, count: Int) -> (last: [UInt32], moved: Bool) {
        var pixels = [UInt32](repeating: 0, count: width * height)
        var first: [UInt32] = []
        var moved = false
        for frame in 0..<count {
            let tone = Self.pulsedTone(frame: frame)
            core.audio.store(tone)
            let chunk = Self.waveformChunk(tone.left)
            core.beats.store(left: chunk, right: chunk, sampleRate: 44_100)
            pixels.withUnsafeMutableBufferPointer {
                // One chunk's time per frame, so each frame takes the chunk just stored.
                XCTAssertTrue(core.renderFrame(into: $0.baseAddress!, width: width, height: height,
                                               nowMs: frame * 14),
                              core.lastError)
            }
            if frame == 0 { first = pixels }
            moved = moved || pixels != first || pixels.contains { $0 & 0x00FF_FFFF != 0 }
        }
        return (pixels, moved)
    }

    /// The preset's component tree as "Effect(Child, …)", for failure messages.
    private func effectNames(_ handle: AVS_Handle) -> String {
        func describe(_ component: AVS_Component_Handle) -> String {
            var info = AVS_Effect_Info()
            let name = avs_effect_info(handle, avs_component_effect(handle, component), &info)
                ? String(cString: info.name) : "?"
            var properties = AVS_Component_Properties()
            let disabled = avs_component_properties_get(handle, component, &properties)
                && !properties.enabled
            var count: UInt32 = 0
            guard let children = avs_component_children(handle, component, &count), count > 0 else {
                return disabled ? "~\(name)" : name
            }
            let inner = UnsafeBufferPointer(start: children, count: Int(count)).map(describe)
            return "\(disabled ? "~" : "")\(name)(\(inner.joined(separator: ", ")))"
        }
        return describe(avs_component_root(handle))
    }

    private func legacyBytes(_ handle: AVS_Handle) -> [UInt8]? {
        var length = 0
        guard let bytes = avs_preset_get_legacy(handle, &length) else { return nil }
        return Array(UnsafeBufferPointer(start: bytes, count: length))
    }

    /// Writes a fresh value to the component's first string parameter (SuperScope's is EEL
    /// code, so this recompiles); false when it has none.
    private func setFirstStringParameter(_ handle: AVS_Handle, _ component: AVS_Component_Handle,
                                         _ step: Int) -> Bool {
        let effect = avs_component_effect(handle, component)
        var info = AVS_Effect_Info()
        guard avs_effect_info(handle, effect, &info), let parameters = info.parameters else {
            return false
        }
        for parameter in UnsafeBufferPointer(start: parameters, count: Int(info.parameters_length)) {
            var parameterInfo = AVS_Parameter_Info()
            guard avs_parameter_info(handle, effect, parameter, &parameterInfo),
                  parameterInfo.type == AVS_PARAM_STRING else { continue }
            return avs_parameter_set_string(handle, component, parameter, "n=\(step % 50 + 10);",
                                            0, nil)
        }
        return false
    }
}
