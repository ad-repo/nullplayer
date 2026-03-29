import Foundation

struct HueEntertainmentChannelFrame {
    let lightID: String
    let brightness: Double
    let xy: (x: Double, y: Double)
    let mirek: Int
}

struct HueLightshowFrame {
    let timestampNanos: UInt64
    let channels: [HueEntertainmentChannelFrame]
}

final class HueLightshowOrchestrator {
    private var preset: HueLightshowPreset = .auto
    private var intensity: Double = 0.6
    private var speed: Double = 0.5
    private var phase: Double = 0

    func setPreset(_ preset: HueLightshowPreset) {
        self.preset = preset
    }

    func setIntensity(_ intensity: Double) {
        self.intensity = max(0.1, min(1.0, intensity))
    }

    func setSpeed(_ speed: Double) {
        self.speed = max(0, min(1.0, speed))
    }

    func resetForTrackChange() {
        phase = 0
    }

    func update(feature: AudioFeatureFrame, lightIDs: [String]) -> HueLightshowFrame? {
        guard lightIDs.isEmpty == false else { return nil }

        let bass = Double(feature.bass)
        let mid = Double(feature.mid)
        let high = Double(feature.high)
        let onset = Double(feature.onset)

        let baseEnergy = (bass * 0.52) + (mid * 0.28) + (high * 0.20)
        let beatBoost = min(0.30, onset * 0.25)
        let energyCurve = pow(max(0.0, min(1.0, baseEnergy)), 0.70)
        let dynamicGain = 0.55 + (intensity * 0.75)
        let floor = 0.10 + (intensity * 0.22)
        let masterBrightness = max(0.08, min(1.0, floor + (energyCurve * dynamicGain) + beatBoost))

        phase += (0.02 + (speed * 0.06))
        if phase > .pi * 2 {
            phase -= .pi * 2
        }

        let channels: [HueEntertainmentChannelFrame] = lightIDs.enumerated().map { index, lightID in
            let lane = Double(index) / Double(max(1, lightIDs.count - 1))
            let wave = 0.5 + (0.5 * sin(phase + lane * .pi))
            let brightness: Double
            let x: Double
            let y: Double

            switch preset {
            case .pulse:
                brightness = max(0.08, min(1.0, masterBrightness * (0.65 + (0.35 * wave))))
                x = 0.23 + (0.30 * lane)
                y = 0.36 - (0.12 * lane)
            case .ambientWave:
                brightness = max(0.08, min(1.0, masterBrightness * (0.50 + (0.25 * wave))))
                x = 0.28 + (0.12 * wave)
                y = 0.34 - (0.08 * wave)
            case .strobeSafe:
                let strobe = onset > 0.85 ? 1.0 : 0.0
                brightness = max(0.08, min(1.0, masterBrightness * (0.45 + (0.35 * strobe))))
                x = 0.30 + (0.18 * lane)
                y = 0.30 + (0.10 * (1 - lane))
            case .auto:
                brightness = max(0.08, min(1.0, masterBrightness * (0.55 + (0.30 * wave))))
                let tilt = max(0, min(1, (high - bass + 1.0) * 0.5))
                x = 0.24 + (0.30 * tilt)
                y = 0.30 + (0.16 * (1 - tilt))
            }

            let warmness = max(0, min(1, bass - (high * 0.45) + 0.35))
            let mirek = Int((500.0 - (warmness * 347.0)).rounded())

            return HueEntertainmentChannelFrame(
                lightID: lightID,
                brightness: brightness,
                xy: (x: max(0.1, min(0.7, x)), y: max(0.1, min(0.7, y))),
                mirek: max(153, min(500, mirek))
            )
        }

        return HueLightshowFrame(timestampNanos: feature.timestampNanos, channels: channels)
    }
}
