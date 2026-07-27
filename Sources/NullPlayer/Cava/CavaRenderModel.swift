import AppKit
import NullPlayerCore

/// Drives Cava spectrum analyzer from the shared stereo audio tap.
///
/// Registers a full-stereo consumer while running (so the tap is idle when no window is open),
/// observes `.audioStereoPCMFullDataUpdated`, marshals to main thread, and maintains CavaCore
/// with current bar/channel data. A 60 Hz timer drives decay and redraw; redraws skip once bars
/// have settled (idle costs nothing).
final class CavaRenderModel {
    private struct ProcessingConfiguration {
        let mode: CavaSettings.Mode
        let barCount: Int
        let sampleRate: Int
        let noiseReduction: Double
        let bassTilt: Double
    }

    private struct ProcessingResult {
        let barArrays: [[Float]]
        let mode: CavaSettings.Mode
        let barCount: Int
        let signature: Int
    }

    /// Called on the main thread whenever the view should repaint.
    var onNeedsDisplay: (() -> Void)?

    private let consumerId = "cava"
    private let processingQueue = DispatchQueue(
        label: "com.nullplayer.cava.processing",
        qos: .userInteractive
    )
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var running = false
    private var processingBusy = false
    private var processingGeneration = 0
    private var forceDisplayOnNextTick = false

    // Accessed only on processingQueue.
    private var cavaCore: CavaCore?
    private var processingBarCount = 32
    private var processingSampleRate = 44100
    private var processingNoiseReduction = CavaSettings.defaultNoiseReduction
    private var processingBassTilt = CavaSettings.defaultBassTilt
    private var processingMode = CavaSettings.Mode.stereo

    // Main-thread presentation state.
    private var currentBarArrays: [[Float]] = []
    private var latestLeft: [Float] = []
    private var latestRight: [Float] = []
    private var pendingSampleRate = 44100
    private var haveSamples = false
    private var receivedSamplesThisInterval = false
    private var idleTicks = 0

    private var lastEmittedSignature = -1  // Change detection for idle skip

    private var currentMode = CavaSettings.Mode.stereo
    private var currentBarCount = 32

    deinit {
        stop()
    }

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
        processingGeneration &+= 1
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
        WindowManager.shared.audioEngine.removeFullStereoConsumer(consumerId)
        resetPresentationState()
        processingQueue.async { [weak self] in
            self?.resetProcessingState()
        }
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

    /// Apply durable setting changes immediately, even when playback is paused and no new
    /// audio notification will arrive to drive the normal refresh path.
    func settingsDidChange() {
        currentMode = CavaSettings.mode
        currentBarCount = CavaSettings.barCount
        guard haveSamples else {
            onNeedsDisplay?()
            return
        }
        receivedSamplesThisInterval = true
        idleTicks = 0
        forceDisplayOnNextTick = true
        tick()
    }

    /// Runs at 60 Hz and schedules at most one operation on the serial DSP queue. New audio is
    /// coalesced while processing is busy, so Cava can never build an analysis backlog that blocks
    /// AppKit. Once audio stops (pause), the last frame is held after a short decay interval.
    private func tick() {
        guard haveSamples, !processingBusy else { return }

        let samples: (left: [Float], right: [Float])?
        if receivedSamplesThisInterval {
            receivedSamplesThisInterval = false
            idleTicks = 0
            samples = (latestLeft, latestRight)
        } else {
            idleTicks += 1
            if idleTicks > 6, !forceDisplayOnNextTick { return }
            samples = nil
        }

        let forceDisplay = forceDisplayOnNextTick
        forceDisplayOnNextTick = false
        let configuration: ProcessingConfiguration?
        if samples != nil || forceDisplay {
            configuration = ProcessingConfiguration(
                mode: CavaSettings.mode,
                barCount: CavaSettings.barCount,
                sampleRate: pendingSampleRate,
                noiseReduction: CavaSettings.noiseReduction,
                bassTilt: CavaSettings.bassTilt
            )
        } else {
            configuration = nil
        }
        let generation = processingGeneration
        processingBusy = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = self.process(samples: samples, configuration: configuration)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.processingGeneration == generation else { return }
                self.processingBusy = false
                guard let result else { return }
                self.currentMode = result.mode
                self.currentBarCount = result.barCount
                self.currentBarArrays = result.barArrays
                if forceDisplay || result.signature != self.lastEmittedSignature {
                    self.lastEmittedSignature = result.signature
                    self.onNeedsDisplay?()
                }
            }
        }
    }

    /// Perform every CavaCore access on the serial processing queue. Channel count remains 2;
    /// mono is derived by averaging the two magnitude rows, avoiding time-domain comb filtering.
    private func process(
        samples: (left: [Float], right: [Float])?,
        configuration: ProcessingConfiguration?
    ) -> ProcessingResult? {
        if let configuration {
            processingMode = configuration.mode
            if cavaCore == nil || processingBarCount != configuration.barCount
                || processingSampleRate != configuration.sampleRate
                || processingNoiseReduction != configuration.noiseReduction
                || processingBassTilt != configuration.bassTilt {
                processingBarCount = configuration.barCount
                processingSampleRate = configuration.sampleRate
                processingNoiseReduction = configuration.noiseReduction
                processingBassTilt = configuration.bassTilt
                cavaCore = CavaCore(
                    numberOfBars: configuration.barCount,
                    rate: configuration.sampleRate,
                    channels: 2,
                    autosens: true,
                    noiseReduction: configuration.noiseReduction,
                    bandExponent: Float(configuration.bassTilt)
                )
            }
        }

        guard let core = cavaCore else { return nil }
        if let samples {
            let pairCount = min(samples.left.count, samples.right.count)
            var interleaved: [Float] = []
            interleaved.reserveCapacity(pairCount * 2)
            for i in 0..<pairCount {
                interleaved.append(samples.left[i])
                interleaved.append(samples.right[i])
            }
            core.analyze(interleaved)
        }

        let rendered = core.render()
        let bars: [[Float]]
        if processingMode == .mono, rendered.count >= 2 {
            let count = rendered[0].count
            var average = [Float](repeating: 0, count: count)
            for i in 0..<count {
                average[i] = (rendered[0][i] + rendered[1][i]) * 0.5
            }
            bars = [average]
        } else {
            bars = rendered
        }

        // Hash ordered, quantized values so equal-energy frames with different distributions
        // still repaint.
        var signature = 17
        for channel in bars {
            signature = signature &* 31 &+ channel.count
            for bar in channel {
                signature = signature &* 31 &+ Int(bar * 1000)
            }
        }
        return ProcessingResult(
            barArrays: bars,
            mode: processingMode,
            barCount: processingBarCount,
            signature: signature
        )
    }

    private func resetPresentationState() {
        currentBarArrays = []
        latestLeft = []
        latestRight = []
        haveSamples = false
        receivedSamplesThisInterval = false
        idleTicks = 0
        processingBusy = false
        forceDisplayOnNextTick = false
        lastEmittedSignature = -1
    }

    private func resetProcessingState() {
        cavaCore = nil
        processingBarCount = CavaSettings.defaultBarCount
        processingSampleRate = 44100
        processingNoiseReduction = CavaSettings.defaultNoiseReduction
        processingBassTilt = CavaSettings.defaultBassTilt
        processingMode = .stereo
    }
}
