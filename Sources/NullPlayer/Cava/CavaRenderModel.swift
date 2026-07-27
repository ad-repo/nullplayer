import AppKit
import NullPlayerCore

/// Drives Cava spectrum analyzer from the shared stereo audio tap.
///
/// Registers a full-stereo consumer while running (so the tap is idle when no window is open),
/// observes `.audioStereoPCMFullDataUpdated`, marshals to main thread, and maintains CavaCore
/// with current bar/channel data. A 60 Hz timer drives decay and redraw; redraws skip once bars
/// have settled (idle costs nothing).
final class CavaRenderModel {
    /// Called on the main thread whenever the view should repaint.
    var onNeedsDisplay: (() -> Void)?

    private let consumerId = "cava"
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var running = false

    private var cavaCore: CavaCore?
    private var currentBarArrays: [[Float]] = []

    // Most recent audio buffer from the tap. The FFT/gravity is driven from the 60 Hz timer
    // (not the audio callback) so decay is smooth and the display rate is independent of the
    // audio buffer cadence (~21 Hz), which otherwise makes the bars update in choppy bursts.
    private var latestLeft: [Float] = []
    private var latestRight: [Float] = []
    private var pendingSampleRate = 44100
    private var haveSamples = false
    private var receivedSamplesThisInterval = false
    private var idleTicks = 0

    private var lastEmittedSignature = -1  // Change detection for idle skip

    private var currentMode = CavaSettings.Mode.stereo
    private var currentBarCount = 32
    private var currentSampleRate = 44100
    private var currentNoiseReduction = CavaSettings.defaultNoiseReduction
    private var currentBassTilt = CavaSettings.defaultBassTilt

    func start() {
        guard !running else { return }
        running = true
        WindowManager.shared.audioEngine.addFullStereoConsumer(consumerId)

        // Receive on the posting thread and hop to main ourselves.
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name.audioStereoPCMFullDataUpdated, object: nil, queue: nil
        ) { note in
            let left = note.userInfo?["left"] as? [Float] ?? []
            let right = note.userInfo?["right"] as? [Float] ?? []
            let rate = note.userInfo?["sampleRate"] as? Double ?? 44100

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.latestLeft = left
                self.latestRight = right
                self.pendingSampleRate = Int(rate)
                self.haveSamples = true
                self.receivedSamplesThisInterval = true
            }
        }

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        currentMode = CavaSettings.mode
        currentBarCount = CavaSettings.barCount
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
        WindowManager.shared.audioEngine.removeFullStereoConsumer(consumerId)
        reset()
    }

    /// Current bar values for each channel (0…1 range).
    var barArrays: [[Float]] {
        currentBarArrays
    }

    /// Mono or stereo mode.
    var mode: CavaSettings.Mode {
        currentMode
    }

    /// Number of bars.
    var barCount: Int {
        currentBarCount
    }

    /// Runs at 60 Hz: re-runs the DSP on the most recent audio buffer (so gravity/smoothing
    /// advance at the display rate for a smooth result), then repaints unless the bars have settled.
    private func tick() {
        guard haveSamples else { return }

        // Between audio buffers (~21 Hz) we re-run the DSP on the last buffer so decay/smoothing
        // advance at 60 Hz. But once audio actually stops (pause), re-running a stale buffer
        // indefinitely lets autosens hunt and the display throb — so after a short gap, freeze the
        // last frame instead of re-running.
        if receivedSamplesThisInterval {
            receivedSamplesThisInterval = false
            idleTicks = 0
        } else {
            idleTicks += 1
            if idleTicks > 6 { return }
        }

        let mode = CavaSettings.mode
        let barCount = CavaSettings.barCount
        currentMode = mode

        // Always analyze both channels. Mono is derived by averaging the two channels' magnitude
        // spectra (below), NOT by summing L+R in the time domain — time-domain summing comb-filters
        // stereo material (phase differences create moving spectral notches) and reads as jitter.
        // So channel count never changes; only bar count / sample rate force a rebuild.
        // Higher noise reduction = more temporal smoothing, so bar motion is spread across the
        // 60 Hz redraw ticks instead of snapping at the ~21 Hz audio-buffer rate.
        let noiseReduction = CavaSettings.noiseReduction
        let bassTilt = CavaSettings.bassTilt
        if cavaCore == nil || currentBarCount != barCount || currentSampleRate != pendingSampleRate
            || currentNoiseReduction != noiseReduction || currentBassTilt != bassTilt {
            currentBarCount = barCount
            currentSampleRate = pendingSampleRate
            currentNoiseReduction = noiseReduction
            currentBassTilt = bassTilt
            cavaCore = CavaCore(numberOfBars: barCount, rate: currentSampleRate, channels: 2,
                                autosens: true, noiseReduction: noiseReduction,
                                bandExponent: Float(bassTilt))
        }

        guard let core = cavaCore else { return }

        let pairCount = min(latestLeft.count, latestRight.count)
        var interleaved: [Float] = []
        interleaved.reserveCapacity(pairCount * 2)
        for i in 0..<pairCount {
            interleaved.append(latestLeft[i])
            interleaved.append(latestRight[i])
        }
        let out = core.execute(interleaved)

        if mode == .mono, out.count >= 2 {
            // Average the per-channel magnitude spectra for a single, artifact-free mono row.
            let count = out[0].count
            var avg = [Float](repeating: 0, count: count)
            for i in 0..<count { avg[i] = (out[0][i] + out[1][i]) * 0.5 }
            currentBarArrays = [avg]
        } else {
            currentBarArrays = out
        }

        // Compute a simple signature to detect when bars have settled (idle skip).
        var sig = 0
        for channel in currentBarArrays {
            for bar in channel {
                sig = sig &+ Int(bar * 1000)
            }
        }

        if sig == lastEmittedSignature { return }  // Idle skip
        lastEmittedSignature = sig
        onNeedsDisplay?()
    }

    private func reset() {
        cavaCore?.reset()
        currentBarArrays = []
        latestLeft = []
        latestRight = []
        haveSamples = false
        receivedSamplesThisInterval = false
        idleTicks = 0
        lastEmittedSignature = -1
    }
}
