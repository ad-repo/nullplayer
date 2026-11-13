import simd

/// Turns the music into NullPlayer-Fractal's shader inputs (the `fractal-vis` skill). Pure: no GL,
/// no clock of its own, so the render thread drives it with `advance` and tests drive it by hand.
///
/// - The beat clock (`beatTime`) runs at the tempo between beats and is pulled onto each detected
///   beat, so motion stays locked to the music without jumping backwards.
/// - Each scene's parameters ease on critically damped springs toward targets picked anew every
///   two bars from a seeded generator, settling over those two bars; the palette moves every
///   four bars, crossfading over two. Slow on purpose: faster read as frantic.
struct FractalDirector {
    typealias Palette = (a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, d: SIMD3<Float>)

    /// Inigo Quilez's cosine palettes: `a + b * cos(2π(c t + d))`.
    static let palettes: [Palette] = [
        (.init(0.5, 0.5, 0.5), .init(0.5, 0.5, 0.5), .init(1.0, 1.0, 1.0), .init(0.00, 0.33, 0.67)),
        (.init(0.5, 0.5, 0.5), .init(0.5, 0.5, 0.5), .init(1.0, 1.0, 1.0), .init(0.00, 0.10, 0.20)),
        (.init(0.5, 0.5, 0.5), .init(0.5, 0.5, 0.5), .init(1.0, 1.0, 1.0), .init(0.30, 0.20, 0.20)),
        (.init(0.5, 0.5, 0.5), .init(0.5, 0.5, 0.5), .init(1.0, 1.0, 0.5), .init(0.80, 0.90, 0.30)),
        (.init(0.5, 0.5, 0.5), .init(0.5, 0.5, 0.5), .init(1.0, 0.7, 0.4), .init(0.00, 0.15, 0.20)),
        (.init(0.5, 0.5, 0.5), .init(0.5, 0.5, 0.5), .init(2.0, 1.0, 0.0), .init(0.50, 0.20, 0.25)),
        (.init(0.8, 0.5, 0.4), .init(0.2, 0.4, 0.2), .init(2.0, 1.0, 1.0), .init(0.00, 0.25, 0.25)),
    ]

    static let beatsPerBar = 4
    /// Bars between parameter targets (also how long they take to settle) and between palettes.
    static let barsPerTarget = 2
    static let barsPerPalette = 4
    /// Before any tempo is known, and the bounds a measured beat interval is trusted within.
    static let defaultBeatInterval = 0.5
    static let beatIntervalRange = 0.25...1.5

    private(set) var time = 0.0
    /// 1 on a beat, decaying exponentially.
    private(set) var beatPulse: Float = 0
    private(set) var beatCount = 0
    /// Beats elapsed at the tempo, pulled onto detected beats; its fraction is the tempo phase.
    private(set) var beatTime = 0.0
    /// Bass, mid and treble, each normalised to its own recent peak: slow and fast smoothing.
    private(set) var bands = SIMD3<Float>(repeating: 0)
    private(set) var fastBands = SIMD3<Float>(repeating: 0)
    /// The scene's parameters (`u_p`), their spring velocities and targets.
    private(set) var params = SIMD4<Float>(repeating: 0)
    private(set) var targets = SIMD4<Float>(repeating: 0)
    /// The parameters integrated over `beatTime` (`u_pBeats`): an angle turning at a rate set by a
    /// parameter, which a retarget changes smoothly however many beats have passed.
    private(set) var paramBeats = SIMD4<Double>(repeating: 0)
    private var velocity = SIMD4<Float>(repeating: 0)
    private var ranges: [ClosedRange<Float>] = []

    private var rng: SplitMix64
    private var bpm = 0
    private var bandPeaks = SIMD3<Float>(repeating: 0.05)
    private var lastBeatTime: Double?
    private var measuredInterval = FractalDirector.defaultBeatInterval
    /// How far `beatTime` still has to be pulled to sit on the last beat.
    private var phaseError = 0.0
    private var paletteFrom: Palette
    private var paletteTo: Palette
    private var paletteIndex = 0
    private var paletteChangedAt = 0.0

    init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
        paletteFrom = Self.palettes[0]
        paletteTo = Self.palettes[0]
    }

    var barCount: Int { beatCount / Self.beatsPerBar }
    var tempoPhase: Double { beatTime - beatTime.rounded(.down) }

    /// The palette crossfading from the last to the next over two bars.
    var palette: Palette {
        let t = Float(min(1, (time - paletteChangedAt) / (beatInterval(bpm: bpm) * Double(Self.beatsPerBar * 2))))
        let s = t * t * (3 - 2 * t)
        return (simd_mix(paletteFrom.a, paletteTo.a, .init(repeating: s)),
                simd_mix(paletteFrom.b, paletteTo.b, .init(repeating: s)),
                simd_mix(paletteFrom.c, paletteTo.c, .init(repeating: s)),
                simd_mix(paletteFrom.d, paletteTo.d, .init(repeating: s)))
    }

    /// A new scene's parameter ranges (at most four); its parameters start at fresh targets.
    mutating func setScene(ranges: [ClosedRange<Float>]) {
        self.ranges = Array(ranges.prefix(4))
        retarget()
        params = targets
        velocity = .zero
    }

    /// One frame: `dt` seconds, whether a beat landed, the tempo (0 when unknown) and the raw
    /// bass, mid and treble levels. A slow frame runs in steps of at most 0.1 s, so the springs
    /// stay stable and the clocks keep real time; a stall past a second is dropped.
    mutating func advance(dt rawDt: Double, beat: Bool, bpm: Int, bands raw: SIMD3<Float>) {
        var left = min(max(rawDt, 0), 1)
        repeat {
            let dt = min(left, 0.1)
            left -= dt
            step(dt: dt, beat: beat && left <= 0, bpm: bpm, bands: raw)
        } while left > 0
    }

    private mutating func step(dt: Double, beat: Bool, bpm: Int, bands raw: SIMD3<Float>) {
        time += dt
        self.bpm = bpm
        let interval = beatInterval(bpm: bpm)

        // The beat clock: tempo-rate, plus part of any error left by the last beat. It never runs
        // backwards, so a late beat slows it rather than rewinding the motion.
        let pull = phaseError * min(1, dt * 6)
        let step = max(dt / interval + pull, 0.1 * dt / interval)
        phaseError -= step - dt / interval
        beatTime += step
        paramBeats += SIMD4<Double>(params) * step

        beatPulse *= Float(exp(-dt * 6))
        if beat {
            if let last = lastBeatTime, Self.beatIntervalRange.contains(time - last) {
                measuredInterval += (time - last - measuredInterval) * 0.2
            }
            lastBeatTime = time
            beatPulse = 1
            beatCount += 1
            phaseError = beatTime.rounded() - beatTime
            if beatCount % Self.beatsPerBar == 0 { onBar() }
        }

        bandPeaks = simd_max(raw, bandPeaks * Float(exp(-dt * 0.5)))
        let normalized = simd_clamp(raw / simd_max(bandPeaks, .init(repeating: 0.05)), .zero, .one)
        bands += (normalized - bands) * Float(min(1, dt * 3))
        fastBands += (normalized - fastBands) * Float(min(1, dt * 18))

        // Critically damped: settles in about `barsPerTarget` bars.
        let omega = Float(4 / (interval * Double(Self.beatsPerBar * Self.barsPerTarget)))
        let fdt = Float(dt)
        velocity += (omega * omega * (targets - params) - 2 * omega * velocity) * fdt
        params += velocity * fdt
        for i in ranges.indices {
            params[i] = min(max(params[i], ranges[i].lowerBound), ranges[i].upperBound)
        }
    }

    /// Seconds per beat: the tempo when known, else the measured beat interval.
    func beatInterval(bpm: Int) -> Double {
        bpm > 0 ? 60 / Double(bpm) : measuredInterval
    }

    private mutating func onBar() {
        if barCount % Self.barsPerTarget == 0 { retarget() }
        guard barCount % Self.barsPerPalette == 0 else { return }
        paletteFrom = palette
        paletteIndex = (paletteIndex + 1 + Int(rng.next() % UInt64(Self.palettes.count - 1))) % Self.palettes.count
        paletteTo = Self.palettes[paletteIndex]
        paletteChangedAt = time
    }

    private mutating func retarget() {
        for (i, range) in ranges.enumerated() {
            targets[i] = range.lowerBound + Float(rng.unit()) * (range.upperBound - range.lowerBound)
        }
    }
}

/// A small seedable generator, so a director's choices are reproducible in tests.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
