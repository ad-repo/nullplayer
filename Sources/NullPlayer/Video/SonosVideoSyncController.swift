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

        NSLog("SonosVideoSyncController: Starting sync")

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

    // MARK: - Manual A/V Nudge

    /// Apply a one-shot, *relative* A/V correction by seeking the local video's playhead by
    /// `delta` seconds relative to where it is now. There is no persistent offset state: a nudge
    /// is a momentary push, after which the video free-runs again. Positive advances the picture
    /// (use when the video is behind the audio); negative delays it (use when the video is ahead).
    ///
    /// A relative seek (the same mechanism as the ±10s skip buttons) is used rather than a
    /// playback-rate excursion: a rate excursion of only a fraction of a second is too brief for
    /// the player to act on, so it under-corrects. A seek moves the playhead by exactly `delta`,
    /// immediately and fully. It is relative to the video's *own* clock — never the noisy Sonos
    /// clock — so the correction is deterministic and convergeable.
    func nudge(by delta: TimeInterval) {
        guard abs(delta) > 0.0001 else { return }
        NSLog("SonosVideoSyncController: Nudging video by %.2fs", delta)
        videoController?.nudgeLocalVideo(by: delta)
    }
}
