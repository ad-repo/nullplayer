import AVFoundation
import os

/// WMP-only approximation of the forum's stereo butterfly, not licensed SRS DSP.
/// Adding an inverted mid signal reduces the centre relative to the sides.
/// Coefficients have absolute sum one, so bounded input cannot acquire new peaks.
struct WMPWOWKernel {
    private(set) var amount: Float = 0

    mutating func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                          frames: Int, target: Float, sampleRate: Double) {
        let step = Float(1 / (0.02 * sampleRate)) // 20 ms full-scale ramp
        for frame in 0..<frames {
            amount += max(-step, min(step, target - amount))
            if amount == 0 { continue } // exact dry samples after the ramp
            let l = left[frame], r = right[frame]
            let mid = (l * 0.5 + r * 0.5) * amount
            left[frame] = l - mid
            right[frame] = r - mid
        }
    }
}

/// One instance per graph. Control writes use a lock; rendering only tries it and
/// keeps its previous target on contention, never waiting on the UI thread.
final class WMPWOWAudioUnit: AUAudioUnit, @unchecked Sendable {
    static let component = AudioComponentDescription(componentType: kAudioUnitType_Effect,
        componentSubType: 0x6e77776f, componentManufacturer: 0x4e756c6c,
        componentFlags: 0, componentFlagsMask: 0)
    private static let registration: Void = {
        AUAudioUnit.registerSubclass(WMPWOWAudioUnit.self, as: component,
                                     name: "NullPlayer: WMP WOW", version: 1)
    }()

    static func makeNode() -> AVAudioUnitEffect {
        _ = registration
        return AVAudioUnitEffect(audioComponentDescription: component)
    }

    private var input: AUAudioUnitBus!
    private var output: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    private var scratch: AVAudioPCMBuffer?
    private struct Settings { var wow: Float = 0; var bass: Float = 0; var speaker: Int = 0 }
    private let control = OSAllocatedUnfairLock(initialState: Settings())
    private var renderTarget = Settings()
    private var bassDSP = WMPTruBassDSP(sampleRate: 44100)
    private var renderSampleRate: Double = 44100
    private var kernel = WMPWOWKernel()

    func setAmount(_ amount: Float, bass: Float = 0, speaker: Int = 0) {
        control.withLock {
            $0.wow = amount.isFinite ? max(0, min(0.8, amount)) : 0
            $0.bass = bass.isFinite ? max(0, min(1, bass)) : 0
            $0.speaker = max(0, min(2, speaker))
        }
    }

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        input = try AUAudioUnitBus(format: format)
        output = try AUAudioUnitBus(format: format)
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [input])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [output])
    }

    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }

    override func allocateRenderResources() throws {
        guard input.format == output.format,
              input.format.commonFormat == .pcmFormatFloat32, !input.format.isInterleaved,
              let buffer = AVAudioPCMBuffer(pcmFormat: input.format,
                                           frameCapacity: maximumFramesToRender) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        scratch = buffer
        kernel = WMPWOWKernel()
        renderTarget = Settings()
        renderSampleRate = input.format.sampleRate
        bassDSP = WMPTruBassDSP(sampleRate: renderSampleRate)
        try super.allocateRenderResources()
    }

    override func deallocateRenderResources() {
        super.deallocateRenderResources()
        scratch = nil
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        { [self] flags, timestamp, frames, _, data, _, pull in
            guard let pull, let scratch, frames <= scratch.frameCapacity else {
                return kAudioUnitErr_TooManyFramesToProcess
            }
            let buffers = UnsafeMutableAudioBufferListPointer(data)
            let backing = UnsafeMutableAudioBufferListPointer(scratch.mutableAudioBufferList)
            guard buffers.count == backing.count else { return kAudioUnitErr_FormatNotSupported }
            for index in buffers.indices {
                if buffers[index].mData == nil { buffers[index].mData = backing[index].mData }
                buffers[index].mDataByteSize = frames * UInt32(MemoryLayout<Float>.size)
            }
            let status = pull(flags, timestamp, frames, 0, data)
            guard status == noErr else { return status }
            if let value = control.withLockIfAvailable({ $0 }) { renderTarget = value }
            if renderTarget.wow == 0, renderTarget.bass == 0, kernel.amount == 0, bassDSP.isDry {
                bassDSP.reset()
                return noErr
            }
            if (1...2).contains(buffers.count), let leftData = buffers[0].mData {
                let left = leftData.assumingMemoryBound(to: Float.self)
                let right = buffers.count == 2 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
                for i in 0..<Int(frames) {
                    // Detect bass before widening so the two controls remain independent.
                    let mid = left[i] * 0.5 + (right?[i] ?? left[i]) * 0.5
                    let bass = bassDSP.sample(mid: mid, target: renderTarget.bass, speaker: renderTarget.speaker)
                    if let right {
                        kernel.process(left: left + i, right: right + i, frames: 1,
                                       target: renderTarget.wow, sampleRate: renderSampleRate)
                    }
                    let l = left[i], r = right?[i] ?? l
                    let addition = WMPTruBassDSP.boundedAddition(bass, left: l, right: r)
                    if addition != 0 {
                        // Filter decay may produce audio after the upstream source goes silent.
                        flags.pointee.remove(.unitRenderAction_OutputIsSilence)
                        left[i] = l + addition
                        right?[i] = r + addition
                    }
                }
            }
            return noErr
        }
    }
}

/// Mirrors PitchTuningController's ownership: independent nodes for primary and
/// crossfade streams, driven from one state, with no changes to the ordinary EQ.
final class WMPWOWController {
    let localNode = WMPWOWAudioUnit.makeNode()
    private class WeakNode {
        weak var node: AVAudioUnitEffect?
        init(_ node: AVAudioUnitEffect) { self.node = node }
    }
    private var streams: [WeakNode] = []
    private(set) var enabled = false
    private(set) var level: Double = 50
    private(set) var bassLevel: Double = 50
    private(set) var speakerSize: Int = 0
    private(set) var active: Bool

    init(active: Bool) { self.active = active }

    func setActive(_ value: Bool) { active = value; apply() }
    func setEnabled(_ value: Bool) { enabled = value; apply() }
    func setLevel(_ value: Double) {
        guard value.isFinite else { return }
        level = max(0, min(100, value)); apply()
    }
    func setBassLevel(_ value: Double) {
        guard value.isFinite else { return }
        bassLevel = max(0, min(100, value)); apply()
    }
    func setSpeakerSize(_ value: Int) {
        guard (0...2).contains(value) else { return }
        speakerSize = value; apply()
    }
    func makeStreamingNode() -> AVAudioUnitEffect {
        let node = WMPWOWAudioUnit.makeNode()
        streams.append(WeakNode(node)); configure(node)
        return node
    }
    private func configure(_ node: AVAudioUnitEffect) {
        (node.auAudioUnit as? WMPWOWAudioUnit)?.setAmount(
            active && enabled ? Float(level / 100 * 0.8) : 0,
            bass: active && enabled ? Float(bassLevel / 100) : 0, speaker: speakerSize)
    }
    private func apply() {
        configure(localNode)
        streams.removeAll { $0.node == nil }
        for entry in streams { if let node = entry.node { configure(node) } }
    }
}
