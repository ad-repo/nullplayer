import Foundation

/// The playback transitions a skin hears: `onPlay`, `onResume`, `onPause`, `onStop`.
extension WinampModernScriptRuntime {
    /// Tell the scripts the host's playback state is now `state`. Safe to call on every tick and from
    /// every host path: only a *transition* from what the scripts were last told is reported.
    ///
    /// Winamp reports the transition, not the level, and a skin acts differently on each: ClassicPro's
    /// `beat.m` restarts its VU timer with a fresh running maximum on `onPlay` but resumes the existing
    /// one on `onResume`, and stops it on `onPause`. Sending `onPlay` for a resume rescaled the
    /// animation every time the user unpaused.
    ///
    /// **A stop from playing is reported only once it has held for `stopGracePeriod`.** A natural
    /// advance passes through `.stopped` for the ~15 ms the next track takes to load, and Winamp
    /// reports no stop between tracks: sent, GlassAMPfinal's notifier printed "Stopped" and showed
    /// twice more per track (B309). A stop that does not hold is no transition at all, so no `onPlay`
    /// follows it. A stop from paused is the user's and is reported at once: no track change passes
    /// through it.
    func playbackStateDidChange(to state: PlaybackState) {
        if state == .stopped, reportedPlaybackState == .playing {
            guard pendingStop == nil else { return }
            let stop = DispatchWorkItem { [weak self] in self?.reportPlayback(.stopped) }
            pendingStop = stop
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopGracePeriod, execute: stop)
            return
        }
        pendingStop?.cancel()
        pendingStop = nil
        guard state != reportedPlaybackState else { return }
        reportPlayback(state)
    }

    private func reportPlayback(_ state: PlaybackState) {
        pendingStop = nil
        // Recorded before dispatch: a handler that changes playback (an `onStop` that plays) re-enters
        // here, and its newer state must be the one left standing.
        let previous = reportedPlaybackState
        reportedPlaybackState = state
        switch (previous, state) {
        case (.paused, .playing): _ = try? dispatchSystem(event: "onresume")
        case (_, .playing): _ = try? dispatchSystem(event: "onplay")
        case (.playing, .paused): _ = try? dispatchSystem(event: "onpause")
        case (_, .stopped): _ = try? dispatchSystem(event: "onstop")
        default: break
        }
    }

    // ponytail: a fixed grace period; a load slower than it (a stream) still reports the stop. Key on
    // the engine's own "advancing" state if that ever matters.
    static let stopGracePeriod: TimeInterval = 0.25
}
