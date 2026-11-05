import Foundation

/// Parameters for the Classic/Enhanced/Ultra analyzer shaders (must match Metal
/// `AnalyzerParams` in SpectrumShaders.metal exactly). Total size: 32 bytes.
struct AnalyzerParams {
    var viewportSize: SIMD2<Float>  // offset 0
    var pointCount: Int32           // offset 8
    var barCount: Int32             // offset 12 - Classic bar count
    var time: Float                 // offset 16
    var brightnessBoost: Float      // offset 20
    var pixelScale: Float           // offset 24
    var padding: Float = 0          // offset 28
}

/// The smoothed curve that Classic, Enhanced and Ultra all draw. The shaders sample it with
/// Catmull-Rom, so its resolution is independent of any mode's bar count.
///
/// Attack eases in over a few frames and release follows the responsiveness mode, so heights
/// glide instead of stepping; peaks hold briefly, then fall under constant gravity.
struct AnalyzerCurve {
    static let pointCount = 128
    static let frameDuration: Float = 1.0 / 60.0

    private(set) var levels = [Float](repeating: 0, count: pointCount)
    private(set) var peaks = [Float](repeating: 0, count: pointCount)
    private var peakHold = [Float](repeating: 0, count: pointCount)      // seconds left
    private var peakVelocity = [Float](repeating: 0, count: pointCount)
    private var target = [Float](repeating: 0, count: pointCount)        // per-frame scratch

    private static let attack: Float = 0.6
    private static let peakHoldSeconds: Float = 0.35
    private static let peakGravity: Float = 1.6                           // heights per second²
    /// The deepest sub range gets no columns: the analyzers carry no frequency labels.
    private static let minFrequency: Float = 48

    /// Advances one frame toward `raw` (the engine's 20 Hz–20 kHz log bands; empty = silence).
    /// - Parameter decayFactor: `SpectrumDecayMode.decayFactor`, 0 (Instant) … 0.55 (Smooth).
    /// - Returns: true while any point or peak is still visible.
    mutating func advance(raw: [Float], decayFactor: Float, accurateNormalization: Bool) -> Bool {
        let n = Self.pointCount
        let dt = Self.frameDuration
        let release = 0.70 + 0.45 * decayFactor  // per frame: Instant 0.70 … Smooth 0.95
        let displayScale: Float = accurateNormalization ? 1.0 : 0.95

        if raw.isEmpty {
            for i in 0..<n { target[i] = 0 }
        } else {
            let inputCount = raw.count
            for i in 0..<n {
                let source = Self.sourceBandIndex(outputIndex: i, outputCount: n, inputCount: inputCount)
                let lower = Int(source)
                let upper = min(lower + 1, inputCount - 1)
                let fraction = source - Float(lower)
                let value = (raw[lower] * (1 - fraction) + raw[upper] * fraction) * displayScale
                target[i] = Self.shapedLevel(value, frequencyHz: Self.bandCenterFrequency(source, bandCount: inputCount))
            }
            // A 1-2-1 blur across neighbours removes comb jitter between adjacent points.
            var previous = target[0]
            for i in 0..<n {
                let current = target[i]
                target[i] = 0.25 * previous + 0.5 * current + 0.25 * target[min(i + 1, n - 1)]
                previous = current
            }
        }

        var hasData = false
        for i in 0..<n {
            let goal = target[i]
            var level = levels[i]
            level = goal > level ? level + (goal - level) * Self.attack : level * release + goal * (1 - release)
            if level < 0.002 { level = 0 }
            levels[i] = level

            if level >= peaks[i] {
                peaks[i] = level
                peakHold[i] = Self.peakHoldSeconds
                peakVelocity[i] = 0
            } else if peakHold[i] > 0 {
                peakHold[i] -= dt
            } else {
                peakVelocity[i] += Self.peakGravity * dt
                peaks[i] = max(level, peaks[i] - peakVelocity[i] * dt)
            }
            if peaks[i] > 0.01 { hasData = true }
        }
        return hasData
    }

    mutating func reset() {
        self = AnalyzerCurve()
    }

    // MARK: - Frequency mapping

    private static func sourceBandIndex(outputIndex: Int, outputCount: Int, inputCount: Int) -> Float {
        let sourceMinFreq: Float = 20
        let sourceMaxFreq: Float = 20_000
        let ratio = Float(outputIndex) / Float(max(1, outputCount - 1))
        let frequency = minFrequency * pow(sourceMaxFreq / minFrequency, ratio)
        let bandPosition = log(frequency / sourceMinFreq) / log(sourceMaxFreq / sourceMinFreq)
        let sourceIndex = bandPosition * Float(inputCount) - 0.5
        return min(max(sourceIndex, 0), Float(max(0, inputCount - 1)))
    }

    private static func bandCenterFrequency(_ bandIndex: Float, bandCount: Int) -> Float {
        let minFreq: Float = 20
        let maxFreq: Float = 20_000
        let clampedBand = min(max(bandIndex, 0), Float(max(0, bandCount - 1)))
        let ratio = (clampedBand + 0.5) / Float(max(1, bandCount))
        return minFreq * pow(maxFreq / minFreq, ratio)
    }

    /// Low-bass taper and a slight air lift, so sub energy doesn't swamp the curve.
    private static func shapedLevel(_ rawValue: Float, frequencyHz: Float) -> Float {
        let lowBassControl = 0.58 + 0.42 * smoothstep(42, 90, frequencyHz)
        let lowMidTaper = 0.90 + 0.10 * smoothstep(90, 240, frequencyHz)
        let airLift = 1.0 + 0.08 * smoothstep(6_000, 14_000, frequencyHz)
        let shaped = min(1.0, max(0.0, rawValue * lowBassControl * lowMidTaper * airLift))
        return pow(shaped, 1.08)
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let t = min(1.0, max(0.0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }
}
