import Foundation

/// The whole-track waveform a `.wal` skin's seeker strip draws (BB18).
///
/// Not the oscilloscope. `WinampModernWaveformTap` carries 576 live PCM samples and knows nothing
/// about the track; this carries one envelope for the *whole file*, so the strip can show where in
/// the song the playhead is and what is coming. It is the same envelope the ModernWaveform window
/// draws, from the same cache — `WaveformCacheService` decodes a file once, persists the result, and
/// answers from disk on every later play — so a track already seen in that window costs nothing here.
///
/// **Nothing happens until a skin asks.** The decode is real work on a real file, and most skins
/// declare no seeker holder at all, so the model stays idle until `start()`. That mirrors
/// `setWaveformNeeded`/`setAnalyzerNeeded`: a capability a skin does not use must not cost anything.
///
/// **One load per track, and the answer is discarded if the track moved.** `loadSnapshot` is async
/// and a user skipping through a playlist can outrun it, so each load carries the id it was started
/// for and drops itself if that is no longer the playing track — the same rule
/// `WinampModernHost.albumArtwork` applies to a cover fetch in flight.
///
/// **Main thread only, and unsynchronized on purpose.** Every entry point is already on it — the
/// observer is registered with `queue: .main`, the load hands its result back through
/// `MainActor.run`, and the renderer reads `samples` from inside `draw`. That is the opposite of the
/// audio taps beside it, which are locked because they are written from the real-time thread; a lock
/// here would guard against a caller that does not exist.
final class WinampModernSeekerWaveform {
    /// The envelope, 0…65535 per bucket, or empty for "nothing to draw yet".
    private(set) var samples: [UInt16] = []
    /// Set when a decode is in flight for the current track and no envelope has arrived yet, so the
    /// strip can say *loading* rather than *silent* — an all-zero envelope and a pending one look
    /// identical otherwise, and a long file takes a visible moment.
    private(set) var isLoading = false

    /// Called on the main thread whenever `samples` changes, so the window can repaint. The strip
    /// has no clock of its own — it is drawn from the same repaint every other skin object is.
    var onChange: (() -> Void)?

    private var running = false
    private var loadedTrackID: UUID?
    private var observer: NSObjectProtocol?
    private let currentTrack: () -> Track?

    init(currentTrack: @escaping () -> Track?) {
        self.currentTrack = currentTrack
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        guard !running else { return }
        running = true
        // The same notification the ModernWaveform window listens to. `.main` is safe here, unlike
        // in the audio taps: this fires once per track change, not once per 576-sample chunk.
        observer = NotificationCenter.default.addObserver(
            forName: .audioTrackDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.trackDidChange() }
        trackDidChange()
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        loadedTrackID = nil
        samples = []
        isLoading = false
        onChange?()
    }

    private func trackDidChange() {
        guard running else { return }
        guard let track = currentTrack() else {
            guard !samples.isEmpty || isLoading else { return }
            loadedTrackID = nil
            samples = []
            isLoading = false
            onChange?()
            return
        }
        guard track.id != loadedTrackID else { return }
        loadedTrackID = track.id
        samples = []
        isLoading = true
        onChange?()
        Task { [weak self] in
            let snapshot = await WaveformCacheService.shared.loadSnapshot(for: track)
            await MainActor.run { [weak self] in
                guard let self, self.running, self.loadedTrackID == track.id else { return }
                self.samples = snapshot.samples
                self.isLoading = false
                self.onChange?()
            }
        }
    }
}
