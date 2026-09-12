import Foundation

/// Independent approximation of the controlled filter-bank embodiment in SRS's
/// US6285767B1 (figures 12–15), not the proprietary WMP implementation.
/// Existing mid-bass harmonics are reinforced in proportion to sub-bass energy.
struct WMPTruBassDSP {
    private struct Filter {
        let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var z1: Double = 0, z2: Double = 0
        init(frequency: Double, rate: Double, lowpass: Bool = false) {
            let w = 2 * Double.pi * min(frequency, rate * 0.4) / rate
            let c = cos(w), alpha = sin(w) / (2 * (lowpass ? 0.707 : 1.0))
            let a0 = 1 + alpha
            b0 = (lowpass ? (1 - c) / 2 : alpha) / a0
            b1 = (lowpass ? 1 - c : 0) / a0
            b2 = (lowpass ? (1 - c) / 2 : -alpha) / a0
            a1 = -2 * c / a0; a2 = (1 - alpha) / a0
        }
        mutating func tick(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            if abs(z1) < 1e-20 { z1 = 0 }
            if abs(z2) < 1e-20 { z2 = 0 }
            return y
        }
    }
    private var sub: Filter
    private var bands: [Filter]
    private var envelopes = [Double](repeating: 0, count: 5)
    private var subEnvelope: Double = 0
    private var lowerWeight: Double = 0
    private var level: Double = 0
    private let attack: Double, release: Double, step: Double

    init(sampleRate: Double) {
        sub = Filter(frequency: 100, rate: sampleRate, lowpass: true)
        bands = [60.0, 100, 150, 200, 250].map { Filter(frequency: $0, rate: sampleRate) }
        attack = 1 - exp(-1 / (0.01 * sampleRate))
        release = 1 - exp(-1 / (0.1 * sampleRate))
        step = 1 / (0.02 * sampleRate)
    }

    var isDry: Bool { level == 0 }
    mutating func reset() {
        sub.z1 = 0; sub.z2 = 0; subEnvelope = 0
        for i in bands.indices { bands[i].z1 = 0; bands[i].z2 = 0; envelopes[i] = 0 }
    }

    mutating func sample(mid: Float, target: Float, speaker: Int) -> Float {
        level += max(-step, min(step, Double(target) - level))
        // WMP: 0 headphones, 1 normal speakers, 2 large speakers.
        // Headphones interpolate the two published filter-bank choices.
        let desiredWeight = speaker == 2 ? 1.0 : (speaker == 0 ? 0.5 : 0.0)
        lowerWeight += max(-step, min(step, desiredWeight - lowerWeight))
        let low = abs(sub.tick(Double(mid)))
        subEnvelope += (low > subEnvelope ? attack : release) * (low - subEnvelope)
        var sum: Double = 0
        for i in bands.indices {
            let band = bands[i].tick(Double(mid))
            let magnitude = abs(band)
            envelopes[i] += (magnitude > envelopes[i] ? attack : release) * (magnitude - envelopes[i])
            // Bounded, regularized envelope matching avoids gain explosions in silence.
            let gain = min(3, subEnvelope / max(0.001, envelopes[i]))
            let weight = i == 0 ? lowerWeight : (i == 4 ? 1 - lowerWeight : 1)
            sum += band * gain * weight * 0.25
        }
        return Float(sum * level)
    }

    /// Reserve headroom for the added centre signal without clipping the dry path
    /// or changing the L-R image. Already over-range input receives no extra boost.
    static func boundedAddition(_ bass: Float, left: Float, right: Float) -> Float {
        guard abs(left) <= 1, abs(right) <= 1 else { return 0 }
        return max(-1 - min(left, right), min(1 - max(left, right), bass))
    }
}
