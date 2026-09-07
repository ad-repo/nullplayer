import Foundation
import NullPlayerCore

/// The 576-sample waveform a `.wal` skin's `<vis mode="2">` oscilloscope draws — Winamp's own
/// `visdata` format, `UInt8` centred on 128, one array per channel.
///
/// The scope used to be drawn from the **spectrum** band levels, alternating each band above and
/// below the centre line, on the premise that the host publishes a spectrum and not raw PCM. That
/// premise was wrong: `AudioEngine` already posts exactly this array (`.audioWaveform576DataUpdated`,
/// `AudioEngine.swift:2022`), consumer-gated, and vis_classic and the waveform views have been
/// reading it all along. What came out before was a zigzag whose only relationship to the audio was
/// its envelope.
///
/// Shaped after `WinampModernLevelMeter`, and for the same reasons — read that file's doc comment
/// first; the rules below are the ones specific to this tap.
///
/// **The main thread is not in this path.** `AudioEngine.processAudioBuffer` calls
/// `enqueueWaveformSamplesAndPost` directly from `installTap`, and that posts in a `while` loop —
/// one notification per 576-sample chunk, so a single buffer can deliver several back to back,
/// synchronously, before the real-time tap returns. Hence:
///
/// - **Never `queue: .main`** on this observer, and never `DispatchQueue.main.sync` from inside it.
///   Both turn the chunk loop into a real-time-thread stall (see `PeppyMeterLevelModel`).
/// - The observer body is **copy under lock and return**: take the two arrays out of `userInfo`,
///   store them, note the arrival, unlock. No drawing, no `needsDisplay`, no scene work, no
///   `WindowManager` access, no logging.
/// - **No allocation beyond the two array retains.** The engine has already built them; reducing 576
///   samples to a box's width is the renderer's job, on the main thread, once per draw.
/// - The main thread only ever **reads** the latest pair under the same lock. It never waits for the
///   audio thread: with nothing yet received it gets the flat centre line rather than blocking.
///
/// **Silence has to reach the scope**, exactly as it does the VU meter: the tap simply stops posting
/// on pause, stop, end of track, or a move to a cast device, so the last waveform would otherwise
/// hang on screen. Past `silenceTimeout` the read decays to a flat 128. Getting that flat line
/// *painted* is a separate problem — the `<vis>` boxes have no clock of their own — and belongs to
/// `WinampModernLevelMeter.onSilence`, which is running for every skin rather than only for the ones
/// with a scope.
final class WinampModernWaveformTap {
    private let consumerId: String
    private var observer: NSObjectProtocol?
    private var running = false

    /// The chunks waiting to be shown, oldest first, and the clock they are played out against.
    /// Written on the posting thread, read on the main thread, both under `lock`.
    ///
    /// **A queue, not a latest-value.** `AudioEngine.processAudioBuffer` runs once per 2048-frame
    /// buffer — about every 46 ms — and posts every 576-sample chunk it can from inside that one
    /// call, so chunks arrive three or four at a time in a burst. Keeping only the newest threw three
    /// quarters of the audio away and left the survivors 46 ms apart, which is what a scope that
    /// "jumps" is: not a frame-rate problem, a discarded-data problem.
    private var chunks: [(left: [UInt8], right: [UInt8])] = []
    private var current: (left: [UInt8], right: [UInt8])?
    private var playoutStart: TimeInterval?
    private var chunkDuration: TimeInterval = TimeInterval(WinampModernWaveformTap.sampleCount) / 44_100
    private var lastArrival: TimeInterval?
    private let lock = NSLock()

    /// Winamp's vis block: 576 samples, 0…255, silence at 128.
    static let sampleCount = 576
    static let centre: UInt8 = 128
    /// How long the last chunk is held after the buffers stop before the scope reads silence — the
    /// same window the VU meter holds its last block for, and for the same reason: long enough to
    /// ride out the jitter between two taps, short enough that a paused track flattens immediately.
    static let silenceTimeout = WinampModernLevelMeter.silenceTimeout

    static let silence = [UInt8](repeating: WinampModernWaveformTap.centre,
                                 count: WinampModernWaveformTap.sampleCount)

    /// How many chunks may wait to be shown. Each is ~13 ms of audio, so this is the most latency the
    /// scope can be behind the sound — a little over one tap buffer, enough to ride out the burst
    /// without the trace visibly lagging the music. Past it the oldest are dropped and the clock
    /// resynchronises: better a skipped chunk than a scope that drifts further behind every second.
    static let maximumQueuedChunks = 6

    init(consumerId: String) {
        self.consumerId = consumerId
    }

    /// The latest waveform per channel, or a flat centre line once the audio has stopped.
    var samples: (left: [UInt8], right: [UInt8]) {
        samples(at: ProcessInfo.processInfo.systemUptime)
    }

    /// The chunk that is current at `now`. Separated from the clock so the playout and the silence
    /// decay can be tested without waiting for real time.
    ///
    /// **Played out in step with the audio**, the way `WinampModernLevelMeter` hands out its blocks
    /// and for the same reason. Here the rate is not inferred at all: a chunk is exactly 576 samples,
    /// so at the buffer's own sample rate it is exactly 13.06 ms of sound, and showing one per that
    /// much elapsed real time is the audio's own rate. Reads are a pure function of `now`, so the six
    /// boxes of a skin like Big Bento all draw the *same* chunk in a frame, and a frame drawn twice
    /// draws the same thing.
    func samples(at now: TimeInterval) -> (left: [UInt8], right: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        guard let lastArrival, now - lastArrival < Self.silenceTimeout else {
            return (Self.silence, Self.silence)
        }
        if let playoutStart, chunkDuration > 0, !chunks.isEmpty {
            // `playoutStart` is the moment the **head** of the queue becomes current, so at exactly
            // that instant one chunk is already due — a chunk that has just arrived is shown now,
            // not one chunk-duration later. Everything whose moment has passed is consumed and the
            // last of them is what to show; the clock moves with it, so two reads at the same
            // instant answer the same thing.
            let due = max(0, Int(((now - playoutStart) / chunkDuration).rounded(.down)) + 1)
            let advance = min(due, chunks.count)
            if advance > 0 {
                current = chunks[advance - 1]
                chunks.removeFirst(advance)
                self.playoutStart = playoutStart + Double(advance) * chunkDuration
            }
        }
        guard let current else { return (Self.silence, Self.silence) }
        return (current.left.isEmpty ? Self.silence : current.left,
                current.right.isEmpty ? Self.silence : current.right)
    }

    func start() {
        guard !running else { return }
        running = true
        WindowManager.shared.audioEngine.addWaveformConsumer(consumerId)
        // `queue: nil` — received and stored on the posting thread. See the class comment: this
        // observer runs on the real-time audio tap, several times per buffer.
        observer = NotificationCenter.default.addObserver(
            forName: .audioWaveform576DataUpdated, object: nil, queue: nil
        ) { [weak self] note in
            guard let self else { return }
            let left = note.userInfo?["left"] as? [UInt8]
            let right = note.userInfo?["right"] as? [UInt8]
            guard left != nil || right != nil else { return }
            self.receive(left: left ?? Self.silence, right: right ?? Self.silence,
                         sampleRate: note.userInfo?["sampleRate"] as? Double,
                         at: ProcessInfo.processInfo.systemUptime)
        }
    }

    /// Queue one arriving chunk. Runs on the **posting thread** — the real-time audio tap — so it is
    /// a lock, four stores and an append, and nothing else. Separated from the observer so the
    /// playout can be tested without an audio engine.
    func receive(left: [UInt8], right: [UInt8], sampleRate: Double?, at now: TimeInterval) {
        lock.lock()
        if let sampleRate, sampleRate > 0 {
            chunkDuration = TimeInterval(Self.sampleCount) / sampleRate
        }
        chunks.append((left, right))
        // The scope must not fall further behind the music every buffer: past the cap the oldest
        // chunks go and the clock restarts from now.
        if chunks.count > Self.maximumQueuedChunks {
            chunks.removeFirst(chunks.count - Self.maximumQueuedChunks)
            playoutStart = now
        }
        if playoutStart == nil { playoutStart = now }
        lastArrival = now
        lock.unlock()
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        WindowManager.shared.audioEngine.removeWaveformConsumer(consumerId)
        lock.lock()
        chunks = []
        current = nil
        playoutStart = nil
        lastArrival = nil
        lock.unlock()
    }

    deinit { stop() }
}
