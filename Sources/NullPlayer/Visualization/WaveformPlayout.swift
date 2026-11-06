import Foundation

/// The 576-sample waveform chunks `AudioEngine` posts (`.audioWaveform576DataUpdated`), played out at
/// the audio's own rate — Winamp's `visdata` format, `UInt8` centred on 128, one array per channel.
///
/// **A queue, not a latest-value.** `AudioEngine.processAudioBuffer` runs once per mixer-tap buffer —
/// 4410 frames (100 ms) at 44.1 kHz, not the 2048 it requests (`WINAMP_MODERN_VIS_GAPS`) — and posts
/// every chunk of it from inside that one call, so chunks arrive seven or eight at a time. Keeping
/// only the newest showed one 13 ms slice per 100 ms: a scope that jumped, and a vis_classic analyzer
/// whose bars spiked on whatever that slice caught.
///
/// Thread rules: `receive` runs on the **posting thread** — the real-time audio tap — so it is a
/// lock, a few stores and an append; reads take the same lock and never wait on the audio thread.
/// Owned by `WinampModernWaveformTap` (the `.wal` scope and `.wmz` effects) and by
/// `SpectrumAnalyzerView` (vis_classic), each of which observes the notification itself.
final class WaveformPlayout {
    /// Winamp's vis block: 576 samples, 0…255, silence at 128.
    static let sampleCount = 576
    static let centre: UInt8 = 128
    static let silence = [UInt8](repeating: centre, count: sampleCount)
    /// How long the last chunk is held after the buffers stop before the read is silence — the
    /// same window the VU meter holds its last block for, and for the same reason: long enough to
    /// ride out the jitter between two taps, short enough that a paused track flattens immediately.
    static let silenceTimeout = WinampModernLevelMeter.silenceTimeout
    /// The most audio that may wait to be shown, so the most the picture can lag the sound: a little
    /// over one 100 ms tap buffer, at any sample rate (a count cut for 44.1 kHz dropped a chunk of
    /// every 48 kHz buffer). Past it the oldest go and the clock resynchronises: better a skipped
    /// chunk than a picture that drifts further behind every second.
    static let maximumQueuedDuration: TimeInterval = 0.12

    /// The chunks waiting to be shown, oldest first, and the clock they are played out against.
    private var chunks: [(left: [UInt8], right: [UInt8])] = []
    private var current: (left: [UInt8], right: [UInt8])?
    private var playoutStart: TimeInterval?
    private var rate: Double = 44_100
    private var chunkDuration: TimeInterval { TimeInterval(Self.sampleCount) / rate }
    private var lastArrival: TimeInterval?
    private let lock = NSLock()

    /// The chunk current now, or a flat centre line once the audio has stopped.
    var samples: (left: [UInt8], right: [UInt8]) {
        samples(at: ProcessInfo.processInfo.systemUptime)
    }

    /// The sample rate of the chunks arriving, for an analyzer that maps bins to frequencies.
    var sampleRate: Double {
        lock.lock()
        defer { lock.unlock() }
        return rate
    }

    /// The chunk that is current at `now`. Separated from the clock so the playout and the silence
    /// decay can be tested without waiting for real time.
    ///
    /// A chunk is exactly 576 samples, so at the buffer's own sample rate it is exactly that much
    /// sound, and showing one per that much elapsed real time is the audio's own rate. Reads are a
    /// pure function of `now`, so several boxes drawn in one frame (Big Bento's six) draw the *same*
    /// chunk, and a frame drawn twice draws the same thing.
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

    /// Queue one arriving chunk. Runs on the posting thread.
    func receive(left: [UInt8], right: [UInt8], sampleRate: Double?, at now: TimeInterval) {
        lock.lock()
        if let sampleRate, sampleRate > 0 {
            rate = sampleRate
        }
        chunks.append((left, right))
        let cap = Self.maximumQueuedChunks(chunkDuration: chunkDuration)
        if chunks.count > cap {
            chunks.removeFirst(chunks.count - cap)
            playoutStart = now
        }
        if playoutStart == nil { playoutStart = now }
        lastArrival = now
        lock.unlock()
    }

    /// Forget everything queued and shown: the next read is silence until a chunk arrives.
    func reset() {
        lock.lock()
        chunks = []
        current = nil
        playoutStart = nil
        lastArrival = nil
        lock.unlock()
    }

    /// `maximumQueuedDuration` in whole chunks at this rate.
    static func maximumQueuedChunks(chunkDuration: TimeInterval) -> Int {
        max(1, Int((maximumQueuedDuration / chunkDuration).rounded(.up)))
    }
}
