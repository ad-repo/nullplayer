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
/// hang on screen. Past `WaveformPlayout.silenceTimeout` the read decays to a flat 128. Getting that flat line
/// *painted* is a separate problem — the `<vis>` boxes have no clock of their own — and belongs to
/// `WinampModernLevelMeter.onSilence`, which is running for every skin rather than only for the ones
/// with a scope.
final class WinampModernWaveformTap {
    private let consumerId: String
    private var observer: NSObjectProtocol?
    private var running = false
    /// The chunks and their clock — see `WaveformPlayout` for why a queue and how it is played out.
    let playout = WaveformPlayout()

    init(consumerId: String) {
        self.consumerId = consumerId
    }

    /// The current waveform per channel, or a flat centre line once the audio has stopped.
    var samples: (left: [UInt8], right: [UInt8]) { playout.samples }

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
            self.playout.receive(left: left ?? WaveformPlayout.silence,
                                 right: right ?? WaveformPlayout.silence,
                                 sampleRate: note.userInfo?["sampleRate"] as? Double,
                                 at: ProcessInfo.processInfo.systemUptime)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        WindowManager.shared.audioEngine.removeWaveformConsumer(consumerId)
        playout.reset()
    }

    deinit { stop() }
}
