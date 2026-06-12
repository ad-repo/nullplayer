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

    /// Whether the one-time initial alignment seek has run (applies the persisted offset and
    /// compensates for the Sonos startup buffer instead of leaving the video pinned at 0).
    private var hasAlignedOnce = false

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

        NSLog("SonosVideoSyncController: Stopped sync")
    }

    // MARK: - Private Sync Logic

    private func performSync() {
        guard let videoController = videoController else { return }
        guard !hasAlignedOnce else {
            syncTimer?.invalidate()
            syncTimer = nil
            return
        }

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
        hasAlignedOnce = true
        NSLog("SonosVideoSyncController: Initial alignment from video %.1f to %.1f", currentVideoTime, targetTime)
        videoController.playbackRate = 1.0
        // seekLocalVideo bypasses the companion-forwarding branch in VideoPlayerWindowController.seek,
        // which (for the YouTube → Sonos companion) would recurse back through the coordinator.
        videoController.seekLocalVideo(to: max(0, targetTime))
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func realignToCurrentOffset() {
        guard hasAlignedOnce else { return }
        alignToCurrentSonosPosition(reason: "Manual")
    }

    private func alignToCurrentSonosPosition(reason: String) {
        guard let videoController = videoController else { return }
        guard videoController.isPlaying else { return }
        guard CastManager.shared.isSonosPlaybackConfirmed else { return }
        guard let sonosPosition = positionProvider() else { return }

        let targetTime = max(0, sonosPosition + userOffset)
        NSLog("SonosVideoSyncController: %@ alignment, seeking video to %.1f", reason, targetTime)
        videoController.playbackRate = 1.0
        videoController.seekLocalVideo(to: targetTime)
    }
}
