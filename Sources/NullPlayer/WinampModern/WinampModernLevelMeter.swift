import Foundation
import NullPlayerCore

/// Program level per channel for a `.wal` skin's VU meters — what `System.getLeftVUMeter()` and
/// `getRightVUMeter()` answer with.
///
/// **Linear peak amplitude, unsmoothed**, which is Winamp's own scale. A Winamp skin does the
/// perceptual conversion and the ballistics itself: Defix maps the byte through `73.813 · x^¼ − 100`
/// and then applies its own attack/decay before it turns a needle. Handing it a value that is already
/// dB-mapped over a noise floor *and* already smoothed compresses the same signal twice, and the
/// needle then sits high and barely answers the music.
///
/// Three things have to be right, and each was wrong on its own:
///
/// 1. **Peak, not RMS** (Phase 29). Winamp's VU byte comes off the same waveform a skin reads with
///    `getVisData` — an excursion, not an energy average. Music that peaks at full scale measures
///    ~0.05–0.15 RMS, so an RMS-fed needle lives in the bottom sixth of its sweep: measured against
///    Defix's own artwork, 0.1 linear is 34% of the sweep and 0.3 is 60%.
///
/// 2. **A short window, played out in step with the audio** (Phase 29.5). Peak over a *whole* tap
///    buffer is nearly a constant on dense music — the buffer is ~50–100 ms and something in it is
///    always loud — so the needle sat high and still, which reads as "it doesn't respond to peaks and
///    valleys". Winamp measures a 576-sample vis block (~13 ms at 44.1 kHz), and that is where the
///    dynamics live. Each arriving buffer is therefore split into ~13 ms blocks and **handed out one
///    at a time as real time passes**, so a skin polling every 17 ms sees successive blocks instead
///    of the same number five times over. It costs one buffer of latency, which is what a VU looks
///    like anyway.
///
/// 3. **Silence has to reach the meter** (Phase 29.5). The tap simply stops posting when playback
///    stops, pauses, ends, or moves to a cast device — there is no "zero" notification — so the last
///    value stuck and the needles hung wherever the music left them. Running off the end of the
///    played-out blocks *is* the silence signal: the last block is held briefly to ride out normal
///    jitter between buffers, and after that the meter reads 0.
///
/// `WINAMP_MODERN_VU_LOG=1` prints, once a second, the peak and RMS of the arriving buffer, the block
/// spread within it, and the 0…255 byte the skin receives — the difference between 1 and 2 above is
/// visible as `peak` (one number for the buffer) against `blocks` (the range across it).
///
/// Deliberately **not** `PeppyMeterLevelModel`: that model exists to drive PeppyMeter's own artwork,
/// which is calibrated for its 0…100 perceptual scale with its own ballistics. The two surfaces want
/// different measurements of the same tap, and sharing one made the `.wal` skins wear PeppyMeter's
/// calibration (Phase 27.5 → Phase 28).
///
/// The measurement runs on the **posting thread**; the main thread only reads the played-out block.
final class WinampModernLevelMeter {
    private let consumerId: String
    private var observer: NSObjectProtocol?
    private var running = false

    /// The blocks of the most recent buffer, oldest first, and the clock they are played out against.
    /// Written on the posting thread, read on the main thread, both under `lock`.
    private var blocks: [Level] = []
    private var blockDuration: TimeInterval = 0
    private var playoutStart: TimeInterval = 0
    private var lastArrival: TimeInterval?
    private let lock = NSLock()

    struct Level: Equatable {
        var left: Double
        var right: Double
        static let silence = Level(left: 0, right: 0)
    }

    /// Winamp's own measurement window: 576 samples at 44.1 kHz. A VU's ~300 ms integration is the
    /// *skin's* job, not the host's — Defix applies its own attack and decay to whatever it is given.
    static let blockTarget: TimeInterval = 576.0 / 44_100.0
    /// How long the last block is held after the buffers stop before the meter reads silence. Long
    /// enough to ride out the jitter between two taps, short enough that a paused track drops the
    /// needle immediately.
    static let silenceTimeout: TimeInterval = 0.15
    /// Bounds on the inferred buffer cadence, so one late notification cannot stretch a block into a
    /// visible freeze or a burst of them collapse it to nothing.
    static let minimumInterval: TimeInterval = 0.01
    static let maximumInterval: TimeInterval = 0.25
    static let maximumBlocks = 32

    init(consumerId: String) {
        self.consumerId = consumerId
    }

    /// Latest level per channel, 0…1 linear. Read on the main thread, once per skin timer tick.
    var levels: (left: Double, right: Double) {
        let level = level(at: ProcessInfo.processInfo.systemUptime)
        return (level.left, level.right)
    }

    /// The block that is current at `now`, or silence once the tap has stopped feeding us.
    /// Separated from the clock so the playout can be tested without waiting for real time.
    func level(at now: TimeInterval) -> Level {
        lock.lock()
        defer { lock.unlock() }
        guard !blocks.isEmpty, blockDuration > 0 else { return .silence }
        let elapsed = now - playoutStart
        guard elapsed > 0 else { return blocks[0] }
        let index = Int(elapsed / blockDuration)
        if index < blocks.count { return blocks[index] }
        // Past the end of what we were given. Between buffers this is a few milliseconds of jitter
        // and the level should hold; any longer and the audio has actually stopped.
        let overrun = elapsed - Double(blocks.count) * blockDuration
        return overrun < Self.silenceTimeout ? blocks[blocks.count - 1] : .silence
    }

    func start() {
        guard !running else { return }
        running = true
        WindowManager.shared.audioEngine.addStereoConsumer(consumerId)
        // Received on the posting thread (`queue: nil`) and measured there. Registering with
        // `queue: .main` makes NotificationCenter deliver synchronously, which blocks the real-time
        // audio tap on the main queue — see `PeppyMeterLevelModel` for the deadlock that caused.
        observer = NotificationCenter.default.addObserver(
            forName: .audioStereoPCMDataUpdated, object: nil, queue: nil
        ) { [weak self] note in
            let left = note.userInfo?["left"] as? [Float] ?? []
            let right = note.userInfo?["right"] as? [Float] ?? []
            self?.receive(left: left, right: right, at: ProcessInfo.processInfo.systemUptime)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        WindowManager.shared.audioEngine.removeStereoConsumer(consumerId)
        lock.lock()
        blocks = []
        lastArrival = nil
        lock.unlock()
    }

    /// Split one arriving buffer into blocks and schedule them.
    ///
    /// The buffer carries no duration of its own — the tap decimates to a fixed 512 samples and the
    /// streaming path posts a different length again — so the cadence is taken from the **interval
    /// between arrivals**, which is what it means for every source. Each buffer is played out over
    /// the time until the next one is expected, and a new arrival resets the clock, so the playout
    /// cannot drift away from the audio however wrong one estimate is.
    func receive(left: [Float], right: [Float], at now: TimeInterval) {
        guard !left.isEmpty || !right.isEmpty else { return }
        lock.lock()
        let previous = lastArrival
        lastArrival = now
        lock.unlock()

        let measured = previous.map { now - $0 } ?? Self.blockTarget * 4
        let interval = min(Self.maximumInterval, max(Self.minimumInterval, measured))
        let count = min(Self.maximumBlocks, max(1, Int((interval / Self.blockTarget).rounded())))
        let leftBlocks = Self.blockPeaks(left, count: count)
        let rightBlocks = Self.blockPeaks(right, count: count)
        let measuredBlocks = (0..<count).map {
            Level(left: leftBlocks[$0], right: rightBlocks[$0])
        }
        if Self.logsLevels {
            Self.log(left: left, right: right, blocks: measuredBlocks, interval: interval)
        }

        lock.lock()
        blocks = measuredBlocks
        blockDuration = interval / Double(count)
        playoutStart = now
        lock.unlock()
    }

    /// Peak absolute amplitude of each of `count` equal slices, 0…1. A slice with no samples in it
    /// inherits the one before rather than reading as a hole in the audio.
    static func blockPeaks(_ samples: [Float], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
        var peaks = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let start = index * samples.count / count
            let end = max(start + 1, (index + 1) * samples.count / count)
            guard start < samples.count else {
                peaks[index] = index > 0 ? peaks[index - 1] : 0
                continue
            }
            let slice = Array(samples[start..<min(samples.count, end)])
            peaks[index] = amplitude(dbfs: Double(AudioAnalysisDSP.peakDBFS(slice)))
        }
        return peaks
    }

    /// dBFS back to linear amplitude, bounded to 0…1. A silent buffer measures as `-inf`.
    static func amplitude(dbfs: Double) -> Double {
        guard dbfs.isFinite else { return 0 }
        return min(1, max(0, pow(10, min(0, dbfs) / 20)))
    }

    /// `WINAMP_MODERN_VU_LOG=1` — what the meter actually receives during playback, once a second.
    ///
    /// The question "is the needle scaled wrongly, or is the level arriving late?" cannot be answered
    /// by looking at the needle, and an injected level (`WINAMP_MODERN_RENDER_VU`) only exercises the
    /// half of the path above this class.
    private static let logsLevels = ProcessInfo.processInfo.environment["WINAMP_MODERN_VU_LOG"] != nil
    private static let logInterval: TimeInterval = 1
    private static var lastLogTime: TimeInterval = 0
    private static let logLock = NSLock()

    private static func log(left: [Float], right: [Float], blocks: [Level], interval: TimeInterval) {
        let now = Date().timeIntervalSinceReferenceDate
        logLock.lock()
        guard now - lastLogTime >= logInterval else { logLock.unlock(); return }
        lastLogTime = now
        logLock.unlock()
        let peak = amplitude(dbfs: Double(AudioAnalysisDSP.peakDBFS(left)))
        let rms = amplitude(dbfs: Double(AudioAnalysisDSP.rmsDBFS(left)))
        let lows = blocks.map(\.left).min() ?? 0
        let highs = blocks.map(\.left).max() ?? 0
        print(String(format: "WM-VU n=%d dt=%.0fms blocks=%d peak=%.3f rms=%.3f "
                     + "blockRange=%.3f…%.3f byte=%d…%d",
                     left.count, interval * 1000, blocks.count, peak, rms, lows, highs,
                     Int((lows * 255).rounded()), Int((highs * 255).rounded())))
        _ = right
    }

    deinit { stop() }
}
