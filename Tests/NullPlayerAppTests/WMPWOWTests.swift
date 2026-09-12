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

    func testButterflyPreservesSideAndBoundsPeaks() {
        var kernel = WMPWOWKernel()
        let l = (0..<4096).map { Float(sin(Double($0) * 0.13)) }
        let r = (0..<4096).map { Float(cos(Double($0) * 0.21)) }
        let (outL, outR) = process(l, r, target: 0.8, kernel: &kernel)
        for i in l.indices {
            XCTAssertEqual(outL[i] - outR[i], l[i] - r[i], accuracy: 0.000001)
            XCTAssertLessThanOrEqual(abs(outL[i]), 1.000001)
            XCTAssertLessThanOrEqual(abs(outR[i]), 1.000001)
        }
        XCTAssertEqual(outL.last! + outR.last!, 0.2 * (l.last! + r.last!), accuracy: 0.000001)
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
    func testOfflineAudioUnitAndModeGate() throws {
        let controller = WMPWOWController(active: true)
        controller.setEnabled(true)
        controller.setLevel(100)
        controller.setBassLevel(0)
        let nodes = [controller.localNode, controller.makeStreamingNode(), controller.makeStreamingNode()]
        for node in nodes {
            for rate in [44100.0, 48000.0, 96000.0] {
                for channels: AVAudioChannelCount in [2] {
                    controller.setActive(true)
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
                    for channel in 0..<Int(channels) {
                        for i in 0..<Int(input.frameLength) {
                            input.floatChannelData![channel][i] = channel == 0 ? 0.75 : 0.25
                        }
                    }
                    player.scheduleBuffer(input)
                    try engine.start()
                    defer { engine.stop() }
                    player.play()
                    let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
                    XCTAssertEqual(try engine.renderOffline(4096, to: output), .success)
                    XCTAssertEqual(output.floatChannelData![0][4095], channels == 2 ? 0.35 : 0.75, accuracy: 0.00001)
                    if channels > 1 {
                        XCTAssertEqual(output.floatChannelData![1][4095], channels == 2 ? -0.15 : 0.25, accuracy: 0.00001)
                    }
                    controller.setActive(false)
                    XCTAssertEqual(try engine.renderOffline(4096, to: output), .success)
                    XCTAssertEqual(output.floatChannelData![0][4095], 0.75)
                    if channels > 1 { XCTAssertEqual(output.floatChannelData![1][4095], 0.25) }
                    engine.stop()
                    engine.detach(node)
                }
            }
        }
    }
}
