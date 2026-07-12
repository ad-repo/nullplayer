import AppKit
import NullPlayerCore

/// Pure mapping from a level in dBFS to PeppyMeter's 0…100 volume scale.
enum PeppyMeterLevels {
    /// Map `dbfs` (≤ 0) to 0…100 using a configurable noise `floor` (a negative dB value that maps to 0).
    static func volume(fromDBFS dbfs: Double, floor: Double) -> Double {
        guard floor < 0 else { return dbfs >= 0 ? 100 : 0 }
        let clamped = min(0.0, max(floor, dbfs))
        return (clamped - floor) / (0 - floor) * 100.0
    }
}

/// Drives PeppyMeter needle/bar levels from the shared stereo audio tap.
///
/// Registers a stereo consumer while running (so the tap is idle when no meter is open), stores the
/// latest per-channel target on each `.audioStereoPCMDataUpdated`, and applies VU-style ballistics
/// on a 60 Hz timer so the meter keeps falling toward zero on silence (when no notifications arrive).
final class PeppyMeterLevelModel {
    /// Called on the main thread with smoothed left/right volumes (0…100) whenever they change.
    var onLevels: ((Double, Double) -> Void)?

    /// Noise floor in dB that maps to volume 0.
    var floorDB: Double = -42

    private let attack = 0.55   // fast rise
    private let release = 0.18  // slow fall

    private let consumerId = "peppyMeter"
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var running = false

    private var targetLeft = 0.0
    private var targetRight = 0.0
    private var displayLeft = 0.0
    private var displayRight = 0.0
    private var lastEmittedLeft = -1.0
    private var lastEmittedRight = -1.0

    func start() {
        guard !running else { return }
        running = true
        WindowManager.shared.audioEngine.addStereoConsumer(consumerId)
        // Receive on the posting thread (`queue: nil`) and hop to main ourselves. Registering
        // with `queue: .main` makes NotificationCenter deliver synchronously (addOperation +
        // waitUntilFinished), which blocks the real-time audio tap thread on the main queue and
        // deadlocks against tap teardown (removeTap during rapid track loads).
        observer = NotificationCenter.default.addObserver(
            forName: .audioStereoPCMDataUpdated, object: nil, queue: nil
        ) { note in
            let left = note.userInfo?["left"] as? [Float] ?? []
            let right = note.userInfo?["right"] as? [Float] ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.targetLeft = PeppyMeterLevels.volume(fromDBFS: Double(AudioAnalysisDSP.rmsDBFS(left)), floor: self.floorDB)
                self.targetRight = PeppyMeterLevels.volume(fromDBFS: Double(AudioAnalysisDSP.rmsDBFS(right)), floor: self.floorDB)
            }
        }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
        WindowManager.shared.audioEngine.removeStereoConsumer(consumerId)
        targetLeft = 0; targetRight = 0
        displayLeft = 0; displayRight = 0
        lastEmittedLeft = -1; lastEmittedRight = -1
        onLevels?(0, 0)
    }

    private func tick() {
        displayLeft = ballistic(current: displayLeft, target: targetLeft)
        displayRight = ballistic(current: displayRight, target: targetRight)
        // Skip redraws once the needles have settled.
        if abs(displayLeft - lastEmittedLeft) < 0.05, abs(displayRight - lastEmittedRight) < 0.05 { return }
        lastEmittedLeft = displayLeft
        lastEmittedRight = displayRight
        onLevels?(displayLeft, displayRight)
    }

    private func ballistic(current: Double, target: Double) -> Double {
        let coeff = target > current ? attack : release
        return current + (target - current) * coeff
    }
}
