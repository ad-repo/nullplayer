import Foundation

/// The Winamp AVS frontend's standard beat detector (upstream `vis_avs/main.cpp` `render()`,
/// BSD-3), on one 576-sample chunk of Winamp's 8-bit waveform data: a beat is a summed
/// amplitude 34/32 above a slowly decaying peak, and above a silence floor. The frontend's
/// "advanced" mode here is aubio's beat tracker instead (`BPMDetector`).
struct StandardBeatDetector {
    private var peak1 = 0
    private var peak2 = 0
    private var peak1Peak = 0

    mutating func isBeat(left: [UInt8], right: [UInt8]) -> Bool {
        let level = max(Self.amplitude(left), Self.amplitude(right))
        peak1 = (peak1 * 125 + peak2 * 3) / 128
        // Upstream also counts frames since the last beat, but tests the count right after
        // incrementing it, so it never vetoes one; it is left out.
        if level >= (peak1 * 34) / 32 && level > WaveformPlayout.sampleCount * 16 {
            peak1 = (level + peak1Peak) / 2
            peak1Peak = level
            return true
        }
        peak2 = level > peak2 ? level : (peak2 * 14) / 16
        return false
    }

    /// Unsigned 8-bit samples centred on 128, as `.audioWaveform576DataUpdated` carries them.
    private static func amplitude(_ samples: [UInt8]) -> Int {
        samples.reduce(0) { $0 + abs(Int($1) - 128) }
    }
}

/// Beats for consecutive slots of the music, released at the music's pace. The audio tap
/// delivers about 100 ms of slots at once; the render thread takes them as real time passes,
/// so a beat lands within a slot of its place in the music, about one tap buffer late.
/// Slots are either 576-sample chunks (`.audioWaveform576DataUpdated`), the window Winamp's
/// standard detector ran on, or aubio's hops (`.audioBeatsUpdated`), already decided.
/// Shared by AVS and NullPlayer-Fractal.
final class BeatFeed {
    /// Uptime in ms, the clock beats are released by.
    static func milliseconds() -> Int {
        Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    /// Two tap buffers of slots: more means the render clock fell behind, and the oldest go.
    private static let maxPendingMs = 200.0

    private let lock = NSLock()
    private var detector = StandardBeatDetector()
    private var pending: [Bool] = []  // one verdict per slot, oldest first
    private var slotMs = 576.0 * 1000 / 44100
    private var due = 0.0  // slots the render clock has run through but not yet taken
    private var lastTakeMs: Int?

    /// One 576-sample chunk for the standard detector, on the posting (audio) thread.
    func store(left: [UInt8], right: [UInt8], sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        let isBeat = detector.isBeat(left: left, right: right)
        appendLocked([isBeat], slotMs: sampleRate > 0 ? Double(left.count) * 1000 / sampleRate : slotMs)
    }

    /// Slots already decided (aubio's hops), on the posting (audio) thread.
    func store(beats: [Bool], slotMs: Double) {
        lock.lock()
        defer { lock.unlock() }
        appendLocked(beats, slotMs: slotMs)
    }

    private func appendLocked(_ beats: [Bool], slotMs: Double) {
        guard slotMs > 0 else { return }
        self.slotMs = slotMs
        pending.append(contentsOf: beats)
        let maxPending = Int(Self.maxPendingMs / slotMs)
        if pending.count > maxPending { pending.removeFirst(pending.count - maxPending) }
    }

    /// Whether a beat fell in the slots whose time has come by `nowMs`.
    func take(nowMs: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        due += Double(nowMs - (lastTakeMs ?? nowMs)) / slotMs
        lastTakeMs = nowMs
        let count = min(Int(due), pending.count)
        due = pending.count > count ? due - Double(count) : 0  // starved: bank no time
        let isBeat = pending.prefix(count).contains(true)
        pending.removeFirst(count)
        return isBeat
    }
}
