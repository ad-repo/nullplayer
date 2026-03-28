import Foundation

struct HueReactiveOutput {
    let brightness: Double
    let mirek: Int
    let xy: (x: Double, y: Double)
    let beatConfidence: Double
}

final class HueReactiveEngine {
    private let consumerID = "hueReactive"
    private var observer: NSObjectProtocol?
    private weak var audioEngine: AudioEngine?
    private var onOutput: ((HueReactiveOutput) -> Void)?

    private var previousBassBands = Array(repeating: Float(0), count: 10)
    private var rollingFlux = Array(repeating: Double(0), count: 24)
    private var rollingFluxIndex = 0
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

        audioEngine.addSpectrumConsumer(consumerID)
        observer = NotificationCenter.default.addObserver(
            forName: .audioSpectrumDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSpectrum(notification)
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        if let audioEngine {
            audioEngine.removeSpectrumConsumer(consumerID)
        }
        audioEngine = nil
        onOutput = nil
        beatActive = false
        previousBassBands = Array(repeating: Float(0), count: 10)
        rollingFlux = Array(repeating: Double(0), count: 24)
        rollingFluxIndex = 0
    }

    func updateSettings(_ settings: HueReactiveSettings) {
        self.settings = settings
    }

    private func handleSpectrum(_ notification: Notification) {
        guard settings.mode == .groupFallback else { return }
        guard let spectrum = notification.userInfo?["spectrum"] as? [Float], spectrum.count >= 75 else { return }

        let now = Date()
        let maxRate = 4.0 + (settings.speed * 4.0)
        let minInterval = 1.0 / maxRate
        if now.timeIntervalSince(lastDispatch) < minInterval {
            return
        }

        let bassBands = Array(spectrum[0...9])
        let midBands = spectrum[10...29]
        let highBands = spectrum[30...74]

        let bass = Double(bassBands.reduce(0, +)) / 10.0
        let mid = Double(midBands.reduce(0, +)) / 20.0
        let high = Double(highBands.reduce(0, +)) / 45.0

        let flux = zip(bassBands, previousBassBands).reduce(Double(0)) { partial, pair in
            let diff = Double(pair.0 - pair.1)
            return partial + max(0, diff)
        }
        previousBassBands = bassBands

        rollingFlux[rollingFluxIndex] = flux
        rollingFluxIndex = (rollingFluxIndex + 1) % rollingFlux.count
        let rollingMean = rollingFlux.reduce(0, +) / Double(rollingFlux.count)
        let threshold = rollingMean * 1.5
        let beatConfidence = threshold > 0 ? min(1, flux / threshold) : 0

        emaBass = alpha * bass + (1 - alpha) * emaBass
        emaMid = alpha * mid + (1 - alpha) * emaMid
        emaHigh = alpha * high + (1 - alpha) * emaHigh

        let candidateBeatActive = beatConfidence > 1.0
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
