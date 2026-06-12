import AppKit

/// Synchronizes local video playback with Sonos audio playback
@MainActor
final class SonosVideoSyncController {

    // MARK: - Properties

    /// Callback to retrieve current Sonos playback position from CastManager's
    /// existing session clock. The Sonos SOAP polling owner remains CastManager.
    private let positionProvider: () -> TimeInterval?

    /// Reference to the video window controller being synced
    private weak var videoController: VideoPlayerWindowController?

    /// Timer for periodic sync checks
    private var syncTimer: Timer?

    /// Last known Sonos position (for drift calculation)
    private var lastSonosPosition: TimeInterval = 0

    /// User-configured A/V offset in seconds (persisted to UserDefaults)
    var userOffset: TimeInterval {
        get {
            UserDefaults.standard.double(forKey: "youtubeSonosAVOffset")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "youtubeSonosAVOffset")
        }
    }

    /// Playback rate adjustment (0.97 to 1.03) during fine-tuning
    private var rateAdjustment: Float = 1.0

    /// Whether the one-time initial alignment seek has run (applies the persisted offset and
    /// compensates for the Sonos startup buffer instead of leaving the video pinned at 0).
    private var hasAlignedOnce = false

    // MARK: - Initialization

    init(
        positionProvider: @escaping @Sendable () -> TimeInterval?,
        videoController: VideoPlayerWindowController
    ) {
        self.positionProvider = positionProvider
        self.videoController = videoController
    }

    // MARK: - Control

    /// Start the sync controller with 1-2 second polling interval
    func start() {
        guard syncTimer == nil else { return }

        NSLog("SonosVideoSyncController: Starting sync (userOffset=%.1fs)", userOffset)

        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performSync()
            }
        }
    }

    /// Stop the sync controller and reset playback rate
    func stop() {
        syncTimer?.invalidate()
        syncTimer = nil

        // Reset playback rate to normal
        videoController?.playbackRate = 1.0
        rateAdjustment = 1.0

        NSLog("SonosVideoSyncController: Stopped sync")
    }

    // MARK: - Private Sync Logic

    private func performSync() {
        guard let videoController = videoController else { return }

        // Don't fight the user: while the local video is paused, leave it alone. It resyncs to
        // Sonos on resume.
        guard videoController.isPlaying else { return }

        // Retrieve current Sonos position from CastManager's interpolated session state.
        guard let sonosPosition = positionProvider() else {
            // Position provider unavailable; degraded mode (no sync adjustment)
            return
        }

        let currentVideoTime = videoController.currentTime
        let targetTime = sonosPosition + userOffset

        // First valid reading: align explicitly so the persisted offset + Sonos startup buffer
        // are honored from the start, rather than playing from 0.
        if !hasAlignedOnce {
            hasAlignedOnce = true
            NSLog("SonosVideoSyncController: Initial alignment, seeking video to %.1f", targetTime)
            videoController.seek(to: max(0, targetTime))
            lastSonosPosition = sonosPosition
            return
        }

        let drift = targetTime - currentVideoTime
        let absDrift = abs(drift)

        // Large drift (≥1.0s): seek
        if absDrift >= 1.0 {
            NSLog("SonosVideoSyncController: Large drift %.2fs, seeking video to %.1f", drift, targetTime)
            videoController.seek(to: targetTime)
            lastSonosPosition = sonosPosition
            rateAdjustment = 1.0
            return
        }

        // Small drift: adjust playback rate
        if absDrift > 0.05 {
            // Scale: ±1s drift -> ±0.03 rate adjustment
            let rateDelta = Float(drift) * 0.03
            let targetRate = (1.0 + rateDelta).clamped(to: 0.97...1.03)
            videoController.playbackRate = targetRate
            rateAdjustment = targetRate
        } else {
            // Aligned; reset to normal rate
            if rateAdjustment != 1.0 {
                videoController.playbackRate = 1.0
                rateAdjustment = 1.0
            }
        }

        lastSonosPosition = sonosPosition
    }
}

// MARK: - Float Extension

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
