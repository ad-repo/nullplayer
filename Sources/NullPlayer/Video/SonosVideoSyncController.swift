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

    /// Timer for waiting until Sonos has confirmed playback.
    private var syncTimer: Timer?

    /// User-configured A/V offset in seconds for the current YouTube → Sonos session.
    var userOffset: TimeInterval = 0 {
        didSet {
            applyCurrentOffset()
        }
    }

    /// Whether Sonos playback has been confirmed for this session.
    private var hasConfirmedPlayback = false

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
        guard !hasConfirmedPlayback else {
            syncTimer?.invalidate()
            syncTimer = nil
            return
        }

        // Don't fight the user: while the local video is paused, leave it alone.
        guard videoController.isPlaying else { return }

        // Until Sonos has actually started playing, do NOT sync. The cast session reports an
        // optimistic, ever-advancing startup position; chasing it makes us adjust the video based
        // on bad data. Let the muted video play naturally until real Sonos playback begins.
        guard CastManager.shared.isSonosPlaybackConfirmed else { return }

        // Sonos is now really playing. Stop the startup poll without seeking the YouTube video:
        // a network video seek a few seconds after launch causes a large rebuffer stall, which
        // makes manual A/V alignment worse instead of better.
        hasConfirmedPlayback = true
        NSLog("SonosVideoSyncController: Sonos playback confirmed; leaving local video clock untouched")
        videoController.playbackRate = 1.0
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func noteSonosPlaybackConfirmed() {
        hasConfirmedPlayback = true
        syncTimer?.invalidate()
        syncTimer = nil
        videoController?.playbackRate = 1.0
    }

    private func applyCurrentOffset() {
        guard hasConfirmedPlayback else { return }
        guard let videoController = videoController,
              videoController.isPlaying,
              CastManager.shared.isSonosPlaybackConfirmed,
              let sonosPosition = positionProvider()
        else { return }

        let targetTime = max(0, sonosPosition + userOffset)
        NSLog("SonosVideoSyncController: Applying user offset %.1fs, seeking video to %.1f", userOffset, targetTime)
        videoController.playbackRate = 1.0
        videoController.seekLocalVideo(to: targetTime)
    }
}
