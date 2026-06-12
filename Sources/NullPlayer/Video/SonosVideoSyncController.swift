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
            guard UserDefaults.standard.object(forKey: Self.userOffsetKey) != nil else {
                return Self.defaultSonosOutputOffset
            }
            return UserDefaults.standard.double(forKey: Self.userOffsetKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.userOffsetKey)
        }
    }

    /// Playback rate adjustment during fine-tuning. Keep this narrow: even muted video looks
    /// choppy when the rate visibly wobbles around coarse Sonos position updates.
    private var rateAdjustment: Float = 1.0

    /// Whether the one-time initial alignment seek has run (applies the persisted offset and
    /// compensates for the Sonos startup buffer instead of leaving the video pinned at 0).
    private var hasAlignedOnce = false

    /// When we last issued a seek. Seeking a network-streamed video forces a re-buffer, so we must
    /// not seek again until it has had time to recover — otherwise we spiral into a permanent stall.
    private var lastSeekAt: Date?

    /// Only seek for large desyncs, and never more often than the cooldown. Everything smaller is
    /// corrected with playback-rate trimming, which does not interrupt/re-buffer the stream.
    private let seekThreshold: TimeInterval = 2.75
    private let seekCooldown: TimeInterval = 6.0
    private let fineTrimDeadband: TimeInterval = 0.35
    private let maximumFineTrim: Float = 0.03
    private let driftSmoothingFactor = 0.35
    private var smoothedDrift: TimeInterval?

    private static let userOffsetKey = "youtubeSonosAVOffset"
    /// Sonos output is commonly around two seconds behind the reported transport position.
    /// Negative means "show an earlier video frame" so the picture waits for delayed audio.
    private static let defaultSonosOutputOffset: TimeInterval = -2.0

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
        smoothedDrift = nil

        NSLog("SonosVideoSyncController: Stopped sync")
    }

    // MARK: - Private Sync Logic

    private func performSync() {
        guard let videoController = videoController else { return }

        // Don't fight the user: while the local video is paused, leave it alone. It resyncs to
        // Sonos on resume.
        guard videoController.isPlaying else { return }

        // Until Sonos has actually started playing, do NOT sync. The cast session reports an
        // optimistic, ever-advancing startup position; chasing it makes us seek the video forward
        // every poll, which stutters and freezes playback. Let the muted video play naturally and
        // align once real Sonos playback begins.
        guard CastManager.shared.isSonosPlaybackConfirmed else { return }

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
            lastSeekAt = Date()
            lastSonosPosition = sonosPosition
            return
        }

        let drift = targetTime - currentVideoTime
        let filteredDrift: TimeInterval
        if let previous = smoothedDrift {
            filteredDrift = previous + (drift - previous) * driftSmoothingFactor
        } else {
            filteredDrift = drift
        }
        smoothedDrift = filteredDrift
        let absDrift = abs(filteredDrift)

        // Large desync: seek to realign — but only outside the cooldown window. Seeking a
        // network-streamed video re-buffers it; seeking again before it recovers stalls playback
        // permanently. Within the cooldown we fall through to rate trimming, which can't re-buffer.
        if absDrift >= seekThreshold {
            let now = Date()
            let coolingDown = lastSeekAt.map { now.timeIntervalSince($0) < seekCooldown } ?? false
            if !coolingDown {
                NSLog("SonosVideoSyncController: Large drift %.2fs, seeking video to %.1f", filteredDrift, targetTime)
                videoController.seek(to: max(0, targetTime))
                lastSeekAt = now
                lastSonosPosition = sonosPosition
                rateAdjustment = 1.0
                smoothedDrift = nil
                return
            }
        }

        // Everything else: nudge playback rate (no re-buffer). Sonos position is coarse, so ignore
        // sub-frame-ish drift and keep the rate band tight enough that 4K playback stays smooth.
        if absDrift > fineTrimDeadband {
            let rateDelta = Float(filteredDrift) * 0.015
            let minimumRate: Float = 1.0 - maximumFineTrim
            let maximumRate: Float = 1.0 + maximumFineTrim
            let targetRate = (1.0 + rateDelta).clamped(to: minimumRate...maximumRate)
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
