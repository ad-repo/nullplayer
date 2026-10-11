import Accelerate
import AVFoundation
import os

/// The profile stage's filter design: 31 matched peaking sections at the ISO ⅓-octave centres, with
/// section gains solved so the cascade's response lands on every fader at every band centre.
///
/// - Sections are matched-response peaking filters (Vicanek 2016, closed form): impulse-invariant
///   poles, zeros solved for unity at DC and the exact gain, with a turning point, at the centre. A
///   bilinear (RBJ) section cramps toward Nyquist; this one keeps the 16 and 20 kHz bands' shape.
/// - Neighbouring sections overlap, so each fader's section gain is not the fader's value. The
///   accurate cascade graphic EQ (Välimäki & Liski 2017) inverts the band-interaction matrix once per
///   sample rate and maps fader dB to section dB with it; the refinement passes then correct against
///   the exact cascade response with the same inverse.
enum EQProfileDesign {
    static let frequencies: [Double] = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400,
                                        500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000,
                                        6300, 8000, 10000, 12500, 16000, 20000]
    static let bandCount = 31
    /// Section bandwidth: 0.4 octave, a little wider than the band spacing — 1.5 dB less dip between
    /// centres than a ⅓-octave section on a flat +12, while alternating ±12 dB still solves to the
    /// centres with section gains inside ±24 dB. ½ octave (the octave design's 1.5×) interacts too
    /// much: alternating ±12 misses by 3–4 dB. Measured offline, 44.1–192 kHz.
    static let q = pow(2, 0.2) / (pow(2, 0.4) - 1)
    static let prototypeGainDB = 12.0
    /// A section a solved gain may reach. Above this the curve asked for cannot be met by a cascade.
    static let sectionGainLimitDB = 24.0
    /// Sections whose solved gain is within this of 0 dB are not run.
    static let silentGainDB = 0.001

    struct Biquad: Equatable {
        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        static let identity = Biquad()
    }

    /// The bands that can be designed at `sampleRate`: centres below 0.45 fs. All 31 from 44.1 kHz up.
    static func usableBandCount(sampleRate: Double) -> Int {
        frequencies.firstIndex { $0 >= 0.45 * sampleRate } ?? bandCount
    }

    /// Matched peaking section (Vicanek 2016, §"peaking EQ"); RBJ's symmetric Q convention, so a cut
    /// mirrors a boost.
    static func peaking(frequency: Double, gainDB: Double, sampleRate: Double) -> Biquad {
        guard gainDB != 0 else { return .identity }
        let w0 = 2 * Double.pi * frequency / sampleRate
        let g = pow(10, gainDB / 20)
        let zeta = 1 / (2 * q * sqrt(g))
        let a1 = zeta <= 1
            ? -2 * exp(-zeta * w0) * cos(sqrt(1 - zeta * zeta) * w0)
            : -2 * exp(-zeta * w0) * cosh(sqrt(zeta * zeta - 1) * w0)
        let a2 = exp(-2 * zeta * w0)
        let A0 = (1 + a1 + a2) * (1 + a1 + a2), A1 = (1 - a1 + a2) * (1 - a1 + a2), A2 = -4 * a2
        let s = sin(w0 / 2)
        let phi1 = s * s, phi0 = 1 - phi1, phi2 = 4 * phi0 * phi1
        let R1 = (A0 * phi0 + A1 * phi1 + A2 * phi2) * g * g
        let R2 = (-A0 + A1 + 4 * (phi0 - phi1) * A2) * g * g
        let B0 = A0
        let B2 = (R1 - R2 * phi1 - B0) / (4 * phi1 * phi1)
        let B1 = max(0, R2 + B0 + 4 * (phi1 - phi0) * B2)
        let W = 0.5 * (sqrt(B0) + sqrt(B1))
        let b0 = 0.5 * (W + sqrt(max(0, W * W + B2)))
        return Biquad(b0: b0, b1: 0.5 * (sqrt(B0) - sqrt(B1)), b2: -B2 / (4 * b0), a1: a1, a2: a2)
    }

    static func magnitudeDB(_ s: Biquad, frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w)
        let nr = s.b0 + s.b1 * c1 + s.b2 * c2, ni = -(s.b1 * s1 + s.b2 * s2)
        let dr = 1 + s.a1 * c1 + s.a2 * c2, di = -(s.a1 * s1 + s.a2 * s2)
        return 10 * log10((nr * nr + ni * ni) / (dr * dr + di * di))
    }

    private static let inverses = OSAllocatedUnfairLock(initialState: [Double: [Double]]())

    /// The inverse of the n×n band-interaction matrix at `sampleRate` (row-major), built once per rate.
    /// Row k, column m of the matrix: section m at the prototype gain, in dB at centre k, ÷ that gain.
    static func inverseInteraction(sampleRate: Double) -> [Double] {
        if let cached = inverses.withLock({ $0[sampleRate] }) { return cached }
        let n = usableBandCount(sampleRate: sampleRate)
        var matrix = [Double](repeating: 0, count: n * n)
        for m in 0..<n {
            let section = peaking(frequency: frequencies[m], gainDB: prototypeGainDB, sampleRate: sampleRate)
            for k in 0..<n {
                matrix[k * n + m] = magnitudeDB(section, frequency: frequencies[k], sampleRate: sampleRate) / prototypeGainDB
            }
        }
        let inverse = invert(matrix, n: n)
        inverses.withLock { $0[sampleRate] = inverse }
        return inverse
    }

    /// Gauss–Jordan with partial pivoting. The interaction matrix is diagonally dominant, so it is
    /// well conditioned; this runs once per sample rate.
    private static func invert(_ matrix: [Double], n: Int) -> [Double] {
        var a = matrix
        var inv = [Double](repeating: 0, count: n * n)
        for i in 0..<n { inv[i * n + i] = 1 }
        for col in 0..<n {
            let pivot = (col..<n).max { abs(a[$0 * n + col]) < abs(a[$1 * n + col]) } ?? col
            if pivot != col {
                for j in 0..<n {
                    a.swapAt(col * n + j, pivot * n + j)
                    inv.swapAt(col * n + j, pivot * n + j)
                }
            }
            let p = a[col * n + col]
            for j in 0..<n { a[col * n + j] /= p; inv[col * n + j] /= p }
            for row in 0..<n where row != col {
                let f = a[row * n + col]
                guard f != 0 else { continue }
                for j in 0..<n {
                    a[row * n + j] -= f * a[col * n + j]
                    inv[row * n + j] -= f * inv[col * n + j]
                }
            }
        }
        return inv
    }

    /// The cascade's response in dB at `frequency`.
    static func responseDB(_ sections: [Biquad], frequency: Double, sampleRate: Double) -> Double {
        sections.reduce(0) { $0 + ($1 == .identity ? 0 : magnitudeDB($1, frequency: frequency, sampleRate: sampleRate)) }
    }

    private struct DesignKey: Hashable {
        let faders: [Float]
        let sampleRate: Double
    }

    /// Recent designs. One edit is designed for the Studio's display and again for every node at
    /// the same rate — the local graph, the primary and crossfade streams — and those are hits.
    /// ponytail: emptied whole at 16 entries; an LRU if a workload ever thrashes it.
    private static let designs = OSAllocatedUnfairLock(initialState: [DesignKey: [Biquad]]())

    /// The sections that put the cascade on `faders` (dB) at every band centre.
    static func sections(for faders: [Float], sampleRate: Double) -> [Biquad] {
        let key = DesignKey(faders: faders, sampleRate: sampleRate)
        if let cached = designs.withLock({ $0[key] }) { return cached }
        let result = solve(faders, sampleRate: sampleRate)
        designs.withLock { cache in
            if cache.count >= 16 { cache.removeAll() }
            cache[key] = result
        }
        return result
    }

    /// A refinement pass measures the exact response at the centres and corrects with the same
    /// static inverse; the passes stop once every centre is within 0.01 dB.
    private static func solve(_ faders: [Float], sampleRate: Double) -> [Biquad] {
        let n = usableBandCount(sampleRate: sampleRate)
        var result = [Biquad](repeating: .identity, count: bandCount)
        let target = (0..<n).map { Double(faders[$0]) }
        guard target.contains(where: { $0 != 0 }) else { return result }
        let inverse = inverseInteraction(sampleRate: sampleRate)
        func multiply(_ v: [Double]) -> [Double] {
            var out = [Double](repeating: 0, count: n)
            vDSP_mmulD(inverse, 1, v, 1, &out, 1, vDSP_Length(n), 1, vDSP_Length(n))
            return out
        }
        func design(_ gains: [Double]) {
            for m in 0..<n {
                result[m] = abs(gains[m]) < silentGainDB ? .identity
                    : peaking(frequency: frequencies[m], gainDB: gains[m], sampleRate: sampleRate)
            }
        }
        func limited(_ gains: [Double]) -> [Double] {
            gains.map { min(sectionGainLimitDB, max(-sectionGainLimitDB, $0)) }
        }
        var gains = limited(multiply(target))
        design(gains)
        for _ in 0..<12 {
            let error = (0..<n).map { target[$0] - responseDB(result, frequency: frequencies[$0], sampleRate: sampleRate) }
            guard error.contains(where: { abs($0) > 0.01 }) else { break }
            let step = multiply(error)
            gains = limited((0..<n).map { gains[$0] + step[$0] })
            design(gains)
        }
        return result
    }
}

/// One curve's coefficients as the render thread reads them: per channel, the linear preamp, then
/// per band `active, b0, b1, b2, a1, a2`. Built off the render thread; copied into the kernel.
enum EQProfileCoefficients {
    static let sectionStride = 6
    static let channelStride = 1 + EQProfileDesign.bandCount * sectionStride
    static let count = 2 * channelStride

    static func design(_ curve: EQCurve?, sampleRate: Double) -> [Double] {
        var values = [Double](repeating: 0, count: count)
        for channel in 0..<2 {
            let base = channel * channelStride
            values[base] = pow(10, Double(curve?[channel].preamp ?? 0) / 20)
            guard let curve else { continue }
            for (band, s) in EQProfileDesign.sections(for: curve[channel].bands, sampleRate: sampleRate).enumerated()
            where s != .identity {
                let o = base + 1 + band * sectionStride
                values[o] = 1
                values[o + 1] = s.b0; values[o + 2] = s.b1; values[o + 3] = s.b2
                values[o + 4] = s.a1; values[o + 5] = s.a2
            }
        }
        return values
    }
}

/// One set of coefficients and its Direct Form I state, in Double, on preallocated storage.
private final class EQProfileCascade {
    let coefficients = UnsafeMutablePointer<Double>.allocate(capacity: EQProfileCoefficients.count)
    /// Per channel, per band: x1, x2, y1, y2.
    let state = UnsafeMutablePointer<Double>.allocate(capacity: 2 * EQProfileDesign.bandCount * 4)
    private(set) var isIdentity = true

    init() {
        coefficients.initialize(repeating: 0, count: EQProfileCoefficients.count)
        coefficients[0] = 1
        coefficients[EQProfileCoefficients.channelStride] = 1
        state.initialize(repeating: 0, count: 2 * EQProfileDesign.bandCount * 4)
    }

    deinit {
        coefficients.deallocate()
        state.deallocate()
    }

    private func isActive(_ channel: Int, _ band: Int) -> Bool {
        coefficients[channel * EQProfileCoefficients.channelStride + 1 + band * EQProfileCoefficients.sectionStride] != 0
    }

    func load(_ values: UnsafePointer<Double>) {
        coefficients.update(from: values, count: EQProfileCoefficients.count)
        isIdentity = (0..<2).allSatisfy { channel in
            coefficients[channel * EQProfileCoefficients.channelStride] == 1
                && (0..<EQProfileDesign.bandCount).allSatisfy { !isActive(channel, $0) }
        }
    }

    /// Carry the signal history of every section `other` was running; start the rest from rest.
    func takeState(from other: EQProfileCascade) {
        for channel in 0..<2 {
            for band in 0..<EQProfileDesign.bandCount {
                let o = (channel * EQProfileDesign.bandCount + band) * 4
                if other.isActive(channel, band) {
                    state.advanced(by: o).update(from: other.state.advanced(by: o), count: 4)
                } else {
                    state.advanced(by: o).update(repeating: 0, count: 4)
                }
            }
        }
    }

    func reset() { state.update(repeating: 0, count: 2 * EQProfileDesign.bandCount * 4) }

    func process(channel: Int, _ buffer: UnsafeMutablePointer<Double>, frames: Int) {
        let base = coefficients + channel * EQProfileCoefficients.channelStride
        for band in 0..<EQProfileDesign.bandCount {
            let c = base + 1 + band * EQProfileCoefficients.sectionStride
            guard c[0] != 0 else { continue }
            let b0 = c[1], b1 = c[2], b2 = c[3], a1 = c[4], a2 = c[5]
            let s = state + (channel * EQProfileDesign.bandCount + band) * 4
            var x1 = s[0], x2 = s[1], y1 = s[2], y2 = s[3]
            for i in 0..<frames {
                let x = buffer[i]
                let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x; y2 = y1; y1 = y
                buffer[i] = y
            }
            s[0] = x1; s[1] = x2; s[2] = y1; s[3] = y2
        }
        var preamp = base[0]
        if preamp != 1 { vDSP_vsmulD(buffer, 1, &preamp, buffer, 1, vDSP_Length(frames)) }
    }
}

/// The render side: the running cascade, and while a new set fades in, the incoming one beside it.
/// A new set crossfades over 10 ms (the two outputs are correlated, so linearly); a set that arrives
/// mid-fade waits, and only the latest is kept. An identity set with no fade leaves the samples alone.
final class EQProfileKernel {
    private var active = EQProfileCascade()
    private var incoming = EQProfileCascade()
    private let scratchA: UnsafeMutablePointer<Double>
    private let scratchB: UnsafeMutablePointer<Double>
    private let capacity: Int
    private var fadePosition = 0
    private let fadeLength: Int
    private(set) var isFading = false

    init(maximumFrames: Int, sampleRate: Double) {
        capacity = maximumFrames
        scratchA = .allocate(capacity: maximumFrames)
        scratchB = .allocate(capacity: maximumFrames)
        fadeLength = max(1, Int(0.01 * sampleRate))
    }

    deinit {
        scratchA.deallocate()
        scratchB.deallocate()
    }

    var isBypassed: Bool { active.isIdentity && !isFading }

    /// Install without a fade: at allocation, where there is no signal to click.
    func reset(with values: UnsafePointer<Double>) {
        active.load(values)
        active.reset()
        isFading = false
    }

    func stage(_ values: UnsafePointer<Double>) {
        incoming.load(values)
        if incoming.isIdentity && active.isIdentity {
            swap(&active, &incoming)
            return
        }
        incoming.takeState(from: active)
        fadePosition = 0
        isFading = true
    }

    /// Non-interleaved Float buffers; a mono buffer (no `right`) takes the left curve.
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int) {
        guard frames <= capacity else { return }
        process(channel: 0, left, frames: frames)
        if let right { process(channel: 1, right, frames: frames) }
        guard isFading else { return }
        fadePosition += frames
        if fadePosition >= fadeLength {
            swap(&active, &incoming)
            isFading = false
            if active.isIdentity { active.reset() }
        }
    }

    private func process(channel: Int, _ samples: UnsafeMutablePointer<Float>, frames: Int) {
        vDSP_vspdp(samples, 1, scratchA, 1, vDSP_Length(frames))
        if isFading { scratchB.update(from: scratchA, count: frames) }
        active.process(channel: channel, scratchA, frames: frames)
        if isFading {
            incoming.process(channel: channel, scratchB, frames: frames)
            let length = Double(fadeLength)
            for i in 0..<frames {
                let w = min(1, Double(fadePosition + i) / length)
                scratchA[i] += (scratchB[i] - scratchA[i]) * w
            }
        }
        vDSP_vdpsp(scratchA, 1, samples, 1, vDSP_Length(frames))
    }
}

/// One instance per graph. Control writes take a lock; rendering only tries it, and takes a new set
/// only between fades, never waiting on the UI thread.
final class EQProfileAudioUnit: AUAudioUnit, @unchecked Sendable {
    static let component = AudioComponentDescription(componentType: kAudioUnitType_Effect,
        componentSubType: 0x6e717066, componentManufacturer: 0x4e756c6c,
        componentFlags: 0, componentFlagsMask: 0)
    private static let registration: Void = {
        AUAudioUnit.registerSubclass(EQProfileAudioUnit.self, as: component,
                                     name: "NullPlayer: EQ Profile", version: 1)
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

    private struct Control {
        var curve: EQCurve?
        var sampleRate: Double = 44100
        var coefficients = EQProfileCoefficients.design(nil, sampleRate: 44100)
        var generation: UInt64 = 0
    }
    private let control = OSAllocatedUnfairLock(initialState: Control())
    private var kernel: EQProfileKernel?
    private var renderedGeneration: UInt64 = 0

    /// The curve last set; nil when flat or none.
    var curve: EQCurve? { control.withLock { $0.curve } }

    /// Designs at the node's current rate on the caller's thread. nil or flat: the node passes
    /// its input through untouched.
    func setCurve(_ curve: EQCurve?) {
        let curve = curve?.isFlat == true ? nil : curve
        let rate = control.withLock { state -> Double in
            state.curve = curve
            return state.sampleRate
        }
        let values = EQProfileCoefficients.design(curve, sampleRate: rate)
        control.withLock { state in
            // A rate change in between has already designed the stored curve at the new rate.
            guard state.sampleRate == rate, state.curve == curve else { return }
            state.coefficients = values
            state.generation &+= 1
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
        let rate = input.format.sampleRate
        let curve = control.withLock { state -> EQCurve? in
            state.sampleRate = rate
            return state.curve
        }
        let values = EQProfileCoefficients.design(curve, sampleRate: rate)
        let kernel = EQProfileKernel(maximumFrames: Int(maximumFramesToRender), sampleRate: rate)
        renderedGeneration = control.withLock { state in
            if state.curve == curve { state.coefficients = values }
            state.generation &+= 1
            state.coefficients.withUnsafeBufferPointer { kernel.reset(with: $0.baseAddress!) }
            return state.generation
        }
        self.kernel = kernel
        try super.allocateRenderResources()
    }

    override func deallocateRenderResources() {
        super.deallocateRenderResources()
        scratch = nil
        kernel = nil
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        { [self] flags, timestamp, frames, _, data, _, pull in
            guard let pull, let scratch, let kernel, frames <= scratch.frameCapacity else {
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
            if !kernel.isFading {
                control.withLockIfAvailable { state in
                    guard state.generation != renderedGeneration else { return }
                    renderedGeneration = state.generation
                    state.coefficients.withUnsafeBufferPointer { kernel.stage($0.baseAddress!) }
                }
            }
            guard !kernel.isBypassed, (1...2).contains(buffers.count),
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count == 2 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            // Filter decay may produce audio after the upstream source goes silent.
            flags.pointee.remove(.unitRenderAction_OutputIsSilence)
            kernel.process(left: left, right: right, frames: Int(frames))
            return noErr
        }
    }
}
