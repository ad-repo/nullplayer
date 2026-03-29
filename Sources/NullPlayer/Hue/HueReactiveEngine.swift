import Foundation

struct HueReactiveOutput {
    let brightness: Double
    let mirek: Int
    let xy: (x: Double, y: Double)
    let beatConfidence: Double
}

final class HueReactiveEngine {
    private let consumerID = "hueReactive"
    private weak var audioEngine: AudioEngine?
    private var onOutput: ((HueReactiveOutput) -> Void)?

    private var emaBass: Double = 0
    private var emaMid: Double = 0
    private var emaHigh: Double = 0
    private var beatActive = false
    private var lastBeatTransition = Date.distantPast
    private var lastDispatch = Date.distantPast

    private var settings = HueReactiveSettings(mode: .off, intensity: 0.6, speed: 0.5)
    private let alpha = 0.3

    func start(audioEngine: AudioEngine, settings: HueReactiveSettings, onOutput: @escaping (HueReactiveOutput) -> Void) {
        stop()
        self.audioEngine = audioEngine
        self.settings = settings
        self.onOutput = onOutput

        audioEngine.addFeatureConsumer(consumerID) { [weak self] frame in
            self?.handleFeatureFrame(frame)
        }
    }

    func stop() {
        if let audioEngine {
            audioEngine.removeFeatureConsumer(consumerID)
        }
        audioEngine = nil
        onOutput = nil
        beatActive = false
        emaBass = 0
        emaMid = 0
        emaHigh = 0
    }

    func updateSettings(_ settings: HueReactiveSettings) {
        self.settings = settings
    }

    private func handleFeatureFrame(_ frame: AudioFeatureFrame) {
        let now = Date()
        let maxRate = 4.0 + (settings.speed * 4.0)
        let minInterval = 1.0 / maxRate
        if now.timeIntervalSince(lastDispatch) < minInterval {
            return
        }

        let bass = Double(frame.bass)
        let mid = Double(frame.mid)
        let high = Double(frame.high)
        let beatConfidence = Double(frame.onset)

        emaBass = alpha * bass + (1 - alpha) * emaBass
        emaMid = alpha * mid + (1 - alpha) * emaMid
        emaHigh = alpha * high + (1 - alpha) * emaHigh

        let candidateBeatActive = beatConfidence > 0.8
        if candidateBeatActive != beatActive {
            if now.timeIntervalSince(lastBeatTransition) >= 0.08 {
                beatActive = candidateBeatActive
                lastBeatTransition = now
            }
        }

        let intensity = max(0.1, min(1.0, settings.intensity))
        let base = (emaBass * 0.55) + (emaMid * 0.25) + (emaHigh * 0.2)
        let beatBoost = beatActive ? min(0.35, beatConfidence * 0.25) : 0
        let brightness = max(0.02, min(1.0, base * intensity + beatBoost))

        // Move warmer with bass, cooler with highs.
        let warmness = max(0, min(1, emaBass - (emaHigh * 0.5) + 0.35))
        let mirek = Int((500.0 - (warmness * 347.0)).rounded()) // 153...500

        // Map low-to-high spectral tilt into a stable XY color lane.
        let tilt = max(0, min(1, (emaHigh - emaBass + 1.0) * 0.5))
        let x = max(0.1, min(0.7, 0.25 + (0.35 * tilt)))
        let y = max(0.1, min(0.7, 0.32 + (0.2 * (1 - tilt))))

        lastDispatch = now
        onOutput?(HueReactiveOutput(
            brightness: brightness,
            mirek: mirek,
            xy: (x: x, y: y),
            beatConfidence: beatConfidence
        ))
    }
}
