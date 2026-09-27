import AVFoundation
import XCTest
@testable import NullPlayer

final class WMPWOWTests: XCTestCase {
    private func process(_ left: [Float], _ right: [Float], target: Float,
                         kernel: inout WMPWOWKernel) -> ([Float], [Float]) {
        var l = left, r = right
        let count = left.count
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                kernel.process(left: lp.baseAddress!, right: rp.baseAddress!, frames: count,
                               target: target, sampleRate: 48000)
            }
        }
        return (l, r)
    }

    /// Raising WOW must not turn the slider into a volume fader: the centre is what
    /// carries most of a mix's level, so the mid stays put and the side grows.
    /// Width is measured as energy over the block, not per sample — the addition is
    /// filtered, so an individual sample's difference may narrow in passing.
    private func widthRatio(frequency: Double, target: Float, amplitude: Float = 0.4) -> Double {
        var kernel = WMPWOWKernel()
        let rate = 48000.0
        let count = 8192
        let l = (0..<count).map { Float(Double(amplitude) * sin(2 * .pi * frequency * Double($0) / rate)) }
        let r: [Float] = l.map { -$0 } // pure side content at one frequency
        let (outL, outR) = process(l, r, target: target, kernel: &kernel)
        var dry: Double = 0, wet: Double = 0
        for i in (count / 2)..<count {
            let dryDifference = Double(l[i] - r[i])
            let wetDifference = Double(outL[i] - outR[i])
            dry += dryDifference * dryDifference
            wet += wetDifference * wetDifference
            XCTAssertEqual(outL[i] + outR[i], l[i] + r[i], accuracy: 0.000001)
        }
        return (wet / dry).squareRoot()
    }

    func testButterflyPreservesMidWidensSideAndBoundsPeaks() {
        // Above the cutoff the side reaches close to the full ceiling.
        let ceiling = 1 + Double(WMPWOWController.maximumWidening)
        XCTAssertEqual(widthRatio(frequency: 1000, target: WMPWOWController.maximumWidening),
                       ceiling, accuracy: 0.05)
        XCTAssertGreaterThan(widthRatio(frequency: 300, target: WMPWOWController.maximumWidening), 1.8)
        // Deep bass keeps its place in the image instead of spending the headroom.
        XCTAssertLessThan(widthRatio(frequency: 30, target: WMPWOWController.maximumWidening), 1.2)
        // Half travel is audibly narrower than full travel.
        XCTAssertLessThan(widthRatio(frequency: 1000, target: WMPWOWController.maximumWidening / 2),
                          widthRatio(frequency: 1000, target: WMPWOWController.maximumWidening) - 0.5)

        // Full-scale input cannot acquire a peak, and the mid still survives exactly.
        var kernel = WMPWOWKernel()
        let l = (0..<4096).map { Float(sin(Double($0) * 0.13)) }
        let r = (0..<4096).map { Float(cos(Double($0) * 0.21)) }
        let (outL, outR) = process(l, r, target: WMPWOWController.maximumWidening, kernel: &kernel)
        for i in l.indices {
            XCTAssertEqual(outL[i] + outR[i], l[i] + r[i], accuracy: 0.000001)
            XCTAssertLessThanOrEqual(abs(outL[i]), 1.000001)
            XCTAssertLessThanOrEqual(abs(outR[i]), 1.000001)
        }
        XCTAssertEqual(WMPWOWKernel.boundedWidening(0.5, left: 0.9, right: -0.8), 0.1, accuracy: 0.000001)
        XCTAssertEqual(WMPWOWKernel.boundedWidening(-0.5, left: -0.9, right: 0.8), -0.1, accuracy: 0.000001)
        XCTAssertEqual(WMPWOWKernel.boundedWidening(0.5, left: 1.4, right: 0), 0)
    }

    /// The defect this replaced: mono was attenuated by the full WOW amount while
    /// gaining no width at all, because there is no side signal to widen.
    func testMonoKeepsItsLevelAtEveryWOWLevel() {
        for target in [Float(0.2), 0.5, 0.8] {
            var kernel = WMPWOWKernel()
            let mono = (0..<4096).map { Float(0.8 * sin(Double($0) * 0.05)) }
            let (outL, outR) = process(mono, mono, target: target, kernel: &kernel)
            XCTAssertEqual(outL, mono)
            XCTAssertEqual(outR, mono)
        }
    }

    func testOffIsExactAndRampsBackToDry() {
        var kernel = WMPWOWKernel()
        let l = Array(repeating: Float(0.75), count: 2048)
        let r = Array(repeating: Float(0.25), count: 2048)
        XCTAssertEqual(process(l, r, target: 0, kernel: &kernel).0, l)
        let wet = process(l, r, target: 0.8, kernel: &kernel)
        XCTAssertLessThan(abs(wet.0[0] - l[0]), 0.001)
        let dry = process(l, r, target: 0, kernel: &kernel)
        XCTAssertEqual(Array(dry.0.suffix(1024)), Array(l.suffix(1024)))
    }

    func testHostRoundTripAndBoundActions() {
        let model = WMPObjectModel()
        model.set("eq", "enhancedAudio", .bool(true))
        model.set("eq", "wowLevel", .number(200))
        XCTAssertTrue(model.snapshot.equalizer.enhancedAudio)
        XCTAssertEqual(model.snapshot.equalizer.wowLevel, 100)
        XCTAssertEqual(model.hostCommands.map(\.action), ["setWOWEnabled", "setWOWLevel"])
        XCTAssertEqual(WMPTransportAction.boundAction(for: "eq.WOWLevel"), .setWOWLevel)
        XCTAssertEqual(WMPTransportAction.boundAction(for: "eq.enhancedAudio"), .setWOWEnabled)
    }

    func testTruBassRespondsToBassAndSpeakerProfilesAtMultipleRates() {
        for rate in [44100.0, 48000.0, 96000.0] {
            var small = WMPTruBassDSP(sampleRate: rate)
            var large = WMPTruBassDSP(sampleRate: rate)
            var dry = WMPTruBassDSP(sampleRate: rate)
            var energy: Double = 0, difference: Double = 0
            for i in 0..<Int(rate) {
                let t = Double(i) / rate
                let input = Float(0.2 * sin(2 * .pi * 50 * t) + 0.05 * sin(2 * .pi * 150 * t))
                let a = small.sample(mid: input, target: 1, speaker: 1)
                let b = large.sample(mid: input, target: 1, speaker: 2)
                XCTAssertTrue(a.isFinite && b.isFinite)
                XCTAssertEqual(dry.sample(mid: input, target: 0, speaker: 0), 0)
                if i > Int(rate / 2) { energy += Double(a * a); difference += Double((a - b) * (a - b)) }
            }
            XCTAssertGreaterThan(energy / (rate / 2), 0.0001)
            XCTAssertGreaterThan(difference / (rate / 2), 0.00001)
        }
        var silence = WMPTruBassDSP(sampleRate: 48000)
        for _ in 0..<48000 { XCTAssertEqual(silence.sample(mid: 0, target: 1, speaker: 0), 0) }
        XCTAssertEqual(WMPTruBassDSP.boundedAddition(0.5, left: 0.9, right: 0.8), 0.1, accuracy: 0.000001)
        XCTAssertEqual(WMPTruBassDSP.boundedAddition(-0.5, left: -0.9, right: -0.8), -0.1, accuracy: 0.000001)
    }

    /// TruBass distorted below half strength on loud material. Fitting the addition
    /// into the headroom by clamping each sample flat-tops the bass wherever the mix
    /// is loud, and over-range input dropped it to zero outright — switching the bass
    /// on and off sample by sample around a hot master's peaks. The gain moves instead.
    func testTruBassDoesNotDistortLoudOrOverRangeMaterial() {
        let rate = 48000.0
        func distortion(peak: Double, target: Float) -> Double {
            var dsp = WMPTruBassDSP(sampleRate: rate)
            var out: [Double] = []
            for i in 0..<Int(rate * 2) {
                let t = Double(i) / rate
                let raw = 0.55 * sin(2 * .pi * 50 * t) + 0.45 * sin(2 * .pi * 1000 * t)
                let mid = Float(raw * peak)
                let bass = dsp.sample(mid: mid, target: target, speaker: 1)
                let added = dsp.limitedAddition(bass, left: mid, right: mid)
                if peak <= 1 { XCTAssertLessThanOrEqual(abs(mid + added), 1.000001) }
                if i > Int(rate) { out.append(Double(mid + added)) }
            }
            func magnitude(_ frequency: Double) -> Double {
                let w = 2 * Double.pi * frequency / rate
                let c = 2 * cos(w)
                var s1 = 0.0, s2 = 0.0
                for v in out { let s = v + c * s1 - s2; s2 = s1; s1 = s }
                return (s1 * s1 + s2 * s2 - c * s1 * s2).squareRoot() / Double(out.count) * 2
            }
            var harmonics = 0.0
            for h in 2...8 { let v = magnitude(50 * Double(h)); harmonics += v * v }
            return harmonics.squareRoot() / magnitude(50) * 100
        }
        // Hard-clamping each sample measured 1.0% here, and 1.4%/2.6% over range.
        XCTAssertLessThan(distortion(peak: 0.99, target: 0.4), 0.6)
        XCTAssertLessThan(distortion(peak: 1.02, target: 0.4), 0.6)
        XCTAssertLessThan(distortion(peak: 1.15, target: 0.4), 0.6)
    }

    /// The limiter must duck and recover, not latch: a loud passage cannot leave the
    /// enhancement permanently turned down once the level drops again.
    func testTruBassLimiterRecoversAfterLoudPassage() {
        let rate = 48000.0
        var dsp = WMPTruBassDSP(sampleRate: rate)
        func run(peak: Float, seconds: Double) -> Float {
            var last: Float = 0
            for i in 0..<Int(rate * seconds) {
                let mid = peak * Float(sin(2 * .pi * 50 * Double(i) / rate))
                last = dsp.limitedAddition(dsp.sample(mid: mid, target: 0.4, speaker: 1),
                                           left: mid, right: mid)
            }
            return abs(last)
        }
        _ = run(peak: 0.3, seconds: 1)
        let quiet = run(peak: 0.3, seconds: 0.25)
        _ = run(peak: 1.2, seconds: 1)
        let recovered = run(peak: 0.3, seconds: 1)
        XCTAssertGreaterThan(recovered, quiet * 0.9)
    }

    func testAuthoredWOWScriptAndSpeakerWrap() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="100" height="100">
          <EQUALIZERSETTINGS id="eq"/>
          <BUTTON id="go" width="10" height="10"/>
        </VIEW></THEME>
        """.utf8))])
        let skin = try await WMPSkinLoader().load(from: archive)
        let suite = "WMPWOWTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(), defaults: defaults))
        var snapshot = WMPHostSnapshot()
        snapshot.equalizer.speakerSize = 2
        let output = await runtime.transact(skin: skin, viewID: "main", size: .init(width: 100, height: 100),
            snapshot: snapshot, event: .init(name: "click", targetID: "go", handlers: ["""
            eq.enhancedAudio = !eq.enhancedAudio;
            eq.wowLevel = 75; eq.truBassLevel = 65;
            if (eq.speakerSize == 2) eq.speakerSize = -1;
            eq.speakerSize++;
            """]))
        XCTAssertEqual(output.hostCommands.map(\.action), ["setWOWEnabled", "setWOWLevel", "setTruBassLevel", "setSpeakerSize"])
        XCTAssertEqual(output.hostCommands.last?.value, .number(0))
        XCTAssertFalse(output.calls.contains { $0.resolution != .live })
    }

    func testAudioUnitMonoAndMultichannelPassthroughWithOwnedBuffers() throws {
        for channels: AVAudioChannelCount in [1, 6] {
            let unit = try WMPWOWAudioUnit(componentDescription: WMPWOWAudioUnit.component)
            let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: channels == 1
                ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_MPEG_5_1_A))
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                                       interleaved: false, channelLayout: layout)
            try unit.inputBusses[0].setFormat(format)
            try unit.outputBusses[0].setFormat(format)
            unit.maximumFramesToRender = 2048
            try unit.allocateRenderResources()
            defer { unit.deallocateRenderResources() }
            unit.setAmount(0.8)
            let buffers = AudioBufferList.allocate(maximumBuffers: Int(channels))
            defer { free(buffers.unsafeMutablePointer) }
            for i in buffers.indices {
                buffers[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8192, mData: nil)
            }
            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            let result = unit.internalRenderBlock(&flags, &timestamp, 2048, 0,
                buffers.unsafeMutablePointer, nil, { _, _, frames, _, data in
                    for buffer in UnsafeMutableAudioBufferListPointer(data) {
                        guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { return kAudioUnitErr_NoConnection }
                        for i in 0..<Int(frames) { samples[i] = 0.75 }
                    }
                    return noErr
                })
            XCTAssertEqual(result, noErr)
            for buffer in buffers {
                let samples = try XCTUnwrap(buffer.mData?.assumingMemoryBound(to: Float.self))
                XCTAssertEqual(samples[2047], 0.75)
            }
        }
    }

    func testTruBassRendersAndClearsUpstreamSilenceFlagDuringDecay() throws {
        let unit = try WMPWOWAudioUnit(componentDescription: WMPWOWAudioUnit.component)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try unit.inputBusses[0].setFormat(format)
        try unit.outputBusses[0].setFormat(format)
        unit.maximumFramesToRender = 4096
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }
        unit.setAmount(0, bass: 1, speaker: 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        XCTAssertEqual(unit.internalRenderBlock(&flags, &timestamp, 4096, 0,
            buffer.mutableAudioBufferList, nil, { _, _, frames, _, data in
                for b in UnsafeMutableAudioBufferListPointer(data) {
                    let samples = b.mData!.assumingMemoryBound(to: Float.self)
                    for i in 0..<Int(frames) {
                        let t = Double(i) / 48000
                        samples[i] = Float(0.2 * sin(2 * .pi * 50 * t) + 0.05 * sin(2 * .pi * 150 * t))
                    }
                }
                return noErr
            }), noErr)
        let t = 4095.0 / 48000
        let dryLast = Float(0.2 * sin(2 * .pi * 50 * t) + 0.05 * sin(2 * .pi * 150 * t))
        XCTAssertGreaterThan(abs(buffer.floatChannelData![0][4095] - dryLast), 0.001)
        XCTAssertEqual(unit.internalRenderBlock(&flags, &timestamp, 4096, 0,
            buffer.mutableAudioBufferList, nil, { flags, _, frames, _, data in
                flags.pointee.insert(.unitRenderAction_OutputIsSilence)
                for b in UnsafeMutableAudioBufferListPointer(data) {
                    b.mData!.initializeMemory(as: UInt8.self, repeating: 0, count: Int(frames) * 4)
                }
                return noErr
            }), noErr)
        XCTAssertFalse(flags.contains(.unitRenderAction_OutputIsSilence))
        XCTAssertGreaterThan(abs(buffer.floatChannelData![0][0]), 0.00001)
    }

    /// Exercise the actual AU graph, including null output buffer ownership and
    /// graph format negotiation; a pure kernel test cannot catch a silent node.
    func testOfflineAudioUnitAndEnableGate() throws {
        let controller = WMPWOWController()
        controller.setEnabled(true)
        controller.setLevel(100)
        controller.setBassLevel(0)
        let nodes = [controller.localNode, controller.makeStreamingNode(), controller.makeStreamingNode()]
        for node in nodes {
            for rate in [44100.0, 48000.0, 96000.0] {
                for channels: AVAudioChannelCount in [2] {
                    controller.setEnabled(true)
                    let engine = AVAudioEngine()
                    let player = AVAudioPlayerNode()
                    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
                    engine.attach(player)
                    engine.attach(node)
                    engine.connect(player, to: node, format: format)
                    engine.connect(node, to: engine.mainMixerNode, format: format)
                    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
                    let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16384)!
                    input.frameLength = input.frameCapacity
                    // Above the widening cutoff: DC and deep bass are deliberately
                    // left centred, so a constant test signal would prove nothing.
                    for channel in 0..<Int(channels) {
                        for i in 0..<Int(input.frameLength) {
                            let phase = 2 * Double.pi * 1000 * Double(i) / rate
                            input.floatChannelData![channel][i] = Float(channel == 0
                                ? 0.5 * sin(phase) : 0.2 * sin(phase))
                        }
                    }
                    player.scheduleBuffer(input)
                    try engine.start()
                    defer { engine.stop() }
                    player.play()
                    let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
                    XCTAssertEqual(try engine.renderOffline(4096, to: output), .success)
                    // The node is in the graph and widening: the mid survives sample
                    // for sample while the side grows by close to the full ceiling.
                    var midError: Float = 0, dryWidth: Double = 0, wetWidth: Double = 0
                    for i in 2048..<4096 {
                        let l = output.floatChannelData![0][i], r = output.floatChannelData![1][i]
                        let phase = 2 * Double.pi * 1000 * Double(i) / rate
                        let dryL = Float(0.5 * sin(phase)), dryR = Float(0.2 * sin(phase))
                        midError = max(midError, abs((l + r) - (dryL + dryR)))
                        dryWidth += Double((dryL - dryR) * (dryL - dryR))
                        wetWidth += Double((l - r) * (l - r))
                        XCTAssertLessThanOrEqual(abs(l), 1.000001)
                    }
                    XCTAssertLessThan(midError, 0.0001)
                    let widening = (wetWidth / dryWidth).squareRoot()
                    XCTAssertGreaterThan(widening, 2.2)
                    XCTAssertLessThan(widening, 1 + Double(WMPWOWController.maximumWidening) + 0.01)
                    controller.setEnabled(false)
                    XCTAssertEqual(try engine.renderOffline(4096, to: output), .success)
                    let tail = 2 * Double.pi * 1000 * 8191 / rate
                    XCTAssertEqual(output.floatChannelData![0][4095], Float(0.5 * sin(tail)), accuracy: 0.00001)
                    XCTAssertEqual(output.floatChannelData![1][4095], Float(0.2 * sin(tail)), accuracy: 0.00001)
                    engine.stop()
                    engine.detach(node)
                }
            }
        }
    }

    /// Playback Options ▸ SRS: a level chosen from Off must not wake the other effect at a
    /// level the menu showed as Off, and clearing both turns SRS off.
    func testMenuLevelsShareOneEnableFlag() {
        let controller = WMPWOWController()
        XCTAssertFalse(controller.enabled)
        XCTAssertEqual(controller.bassLevel, 50)

        controller.setMenuLevel(75, wow: true)
        XCTAssertTrue(controller.enabled)
        XCTAssertEqual(controller.level, 75)
        XCTAssertEqual(controller.bassLevel, 0)

        controller.setMenuLevel(25, wow: false)
        XCTAssertEqual(controller.level, 75, "enabling is already done; the other level is kept")
        XCTAssertEqual(controller.bassLevel, 25)

        controller.setMenuLevel(0, wow: true)
        XCTAssertTrue(controller.enabled)
        controller.setMenuLevel(0, wow: false)
        XCTAssertFalse(controller.enabled)

        controller.setMenuLevel(.nan, wow: true)
        controller.setMenuLevel(250, wow: false)
        XCTAssertEqual(controller.level, 0)
        XCTAssertEqual(controller.bassLevel, 100)
        XCTAssertTrue(controller.enabled)
    }

    /// SRS is a global playback option, so a controller given defaults restores it on launch.
    func testSettingsPersistAcrossControllers() throws {
        let suite = "WMPWOWTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = WMPWOWController(defaults: defaults)
        XCTAssertFalse(fresh.enabled)
        XCTAssertEqual(fresh.level, 50)
        XCTAssertEqual(fresh.bassLevel, 50)
        XCTAssertEqual(fresh.speakerSize, 0)

        fresh.setEnabled(true)
        fresh.setLevel(30)
        fresh.setBassLevel(80)
        fresh.setSpeakerSize(2)

        let restored = WMPWOWController(defaults: defaults)
        XCTAssertTrue(restored.enabled)
        XCTAssertEqual(restored.level, 30)
        XCTAssertEqual(restored.bassLevel, 80)
        XCTAssertEqual(restored.speakerSize, 2)

        defaults.set(900.0, forKey: "srsWOWLevel")
        defaults.set(7, forKey: "srsSpeakerSize")
        let clamped = WMPWOWController(defaults: defaults)
        XCTAssertEqual(clamped.level, 100)
        XCTAssertEqual(clamped.speakerSize, 0, "an out-of-range speaker keeps the default")
    }
}
