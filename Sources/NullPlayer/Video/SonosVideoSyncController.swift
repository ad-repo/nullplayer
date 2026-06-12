import AppKit

/// Synchronizes local video playback with Sonos audio playback
@MainActor
final class SonosVideoSyncController {

    // MARK: - Properties

    /// Callback to retrieve current Sonos playback position
    /// Returns TimeInterval or nil if position unavailable
    private let positionProvider: () async -> TimeInterval?

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

    // MARK: - Initialization

    init(
        positionProvider: @escaping @Sendable () async -> TimeInterval?,
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
            Task {
                await self?.performSync()
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

    private func performSync() async {
        guard let videoController = videoController else { return }

        // Retrieve current Sonos position
        guard let sonosPosition = await positionProvider() else {
            // Position provider unavailable; degraded mode (no sync adjustment)
            return
        }

        let currentVideoTime = videoController.currentTime
        let targetTime = sonosPosition + userOffset

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
