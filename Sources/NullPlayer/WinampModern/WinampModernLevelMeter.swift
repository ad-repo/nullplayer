import Foundation
import NullPlayerCore

/// Program level per channel for a `.wal` skin's VU meters — what `System.getLeftVUMeter()` and
/// `getRightVUMeter()` answer with.
///
/// **Linear amplitude, unsmoothed**, which is Winamp's own scale. A Winamp skin does the perceptual
/// conversion and the ballistics itself: Defix maps the byte through `73.813 · x^¼ − 100` and then
/// applies its own attack/decay before it turns a needle. Handing it a value that is already
/// dB-mapped over a noise floor *and* already smoothed compresses the same signal twice, and the
/// needle then sits high and barely answers the music.
///
/// Deliberately **not** `PeppyMeterLevelModel`: that model exists to drive PeppyMeter's own artwork,
/// which is calibrated for its 0…100 perceptual scale with its own ballistics. The two surfaces want
/// different measurements of the same tap, and sharing one made the `.wal` skins wear PeppyMeter's
/// calibration (Phase 27.5 → Phase 28).
///
/// The measurement runs on the **posting thread**; only two numbers cross to the main thread.
final class WinampModernLevelMeter {
    /// Latest level per channel, 0…1 linear. Read on the main thread.
    private(set) var levels: (left: Double, right: Double) = (0, 0)

    private let consumerId: String
    private var observer: NSObjectProtocol?
    private var running = false

    init(consumerId: String) {
        self.consumerId = consumerId
    }

    func start() {
        guard !running else { return }
        running = true
        WindowManager.shared.audioEngine.addStereoConsumer(consumerId)
        // Received on the posting thread (`queue: nil`) and hopped to main here. Registering with
        // `queue: .main` makes NotificationCenter deliver synchronously, which blocks the real-time
        // audio tap on the main queue — see `PeppyMeterLevelModel` for the deadlock that caused.
        observer = NotificationCenter.default.addObserver(
            forName: .audioStereoPCMDataUpdated, object: nil, queue: nil
        ) { [weak self] note in
            let left = note.userInfo?["left"] as? [Float] ?? []
            let right = note.userInfo?["right"] as? [Float] ?? []
            let leftLevel = Self.amplitude(dbfs: Double(AudioAnalysisDSP.rmsDBFS(left)))
            let rightLevel = Self.amplitude(dbfs: Double(AudioAnalysisDSP.rmsDBFS(right)))
            DispatchQueue.main.async { self?.levels = (leftLevel, rightLevel) }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        WindowManager.shared.audioEngine.removeStereoConsumer(consumerId)
        levels = (0, 0)
    }

    /// dBFS back to linear amplitude, bounded to 0…1. A silent buffer measures as `-inf`.
    static func amplitude(dbfs: Double) -> Double {
        guard dbfs.isFinite else { return 0 }
        return min(1, max(0, pow(10, min(0, dbfs) / 20)))
    }

    deinit { stop() }
}
