import AppKit
import NullPlayerCore

/// Window controller for video playback with VLCKit and skinned UI
class VideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    
    // MARK: - Properties
    
    private var videoPlayerView: VideoPlayerView!
    
    /// Local event monitor for keyboard shortcuts
    private var localEventMonitor: Any?
    
    /// Whether video is currently playing
    private(set) var isPlaying: Bool = false

    /// Flag to prevent recursive stop/close calls
    private var isClosing: Bool = false

    /// Timestamp when playback of the current item started (for analytics)
    private var playbackStartTime: Date?

    /// Sum of completed playback segments for the current item.
    private var accumulatedPlaybackDuration: TimeInterval = 0

    /// What is loaded: its source, title, artwork track and content type, set in one assignment.
    private(set) var loadedVideo: LoadedVideo?

    /// Current video title
    var currentTitle: String? { loadedVideo?.title }

    /// Lightweight video track used by the main window for artwork lookup.
    var currentArtworkTrack: Track? { loadedVideo?.track }

    /// True from the moment a film reaches its own end until something plays again. **Read by every
    /// mode**: `WindowManager.isVideoActivePlayback` and `.videoPlaybackState` answer from it, so a
    /// finished film stops being the transport's target and stops reading `.paused` forever in
    /// Classic and Original too, and the `.wal` host (`WinampModernAudioEngineHost.videoSession` /
    /// `.videoTransport`) keys its session on the same flag.
    ///
    /// The session itself is deliberately *not* cleared. `unloadVideo(reportingStopAt:)` belongs to the
    /// paths that also close the window; end of media leaves the picture up on its last frame with
    /// the film still loaded, so it can be seeked back and replayed. What ends is the session, not
    /// the content.
    ///
    /// **It cannot be driven from `.ended` alone.** Measured 2026-09-02 against the vendored VLCKit:
    /// a local `.mp4` running out reports `VLCMediaPlayerState.paused`, and no `.ended` ever arrives
    /// — the log goes `Playing` … `Paused` and stops. The view now reads that pause for what it is
    /// (`VideoPlayerView.isAtEndOfMedia`) and fires `onPlaybackFinished` from it, which is what
    /// restores finish-scrobbling and playlist advance. This flag additionally latches at the stop
    /// transition (`updatePlayingState`), which covers a film parked at its end by any other route.
    /// Latched rather than computed live: a film left parked at its end stops reporting a position
    /// after a while, and a live check then reads the corpse as a fresh session again.
    private(set) var didReachEndOfMedia = false

    /// Whether the film is sitting at its own end *right now*. Only ever read at the moment playback
    /// stops, while VLCKit's clock still answers. One rule, owned by the view, so the flag and the
    /// finished-callback can never disagree about where the end is.
    private var isParkedAtEndOfMedia: Bool { videoPlayerView.isAtEndOfMedia }

    /// The one place the flag goes true, so the readout is reset exactly once per film however the
    /// end was noticed — the end-of-film pause, a source that really does report `.ended`, or the
    /// stop-transition latch below.
    private func markReachedEndOfMedia() {
        guard !didReachEndOfMedia else { return }
        NSLog("VideoPlayerWindowController: reached end of media (t=%.2f dur=%.2f)", currentTime, duration)
        didReachEndOfMedia = true
        WindowManager.shared.videoPlaybackDidReachEndOfMedia()
    }

    /// Whether we're actively casting video from this player
    private(set) var isCastingVideo: Bool = false

    /// True only when THIS window initiated the current cast (not a library-menu cast)
    private var didInitiateCast: Bool = false

    /// Timer for updating main window with cast progress
    private var castUpdateTimer: Timer?

    /// Last video-cast position observed before CastManager replaces or clears its session.
    private var lastKnownVideoCastPosition: TimeInterval = 0

    /// Whether local playback should resume when this controller stops its video cast.
    private var shouldResumeLocalPlaybackAfterCast = false

    /// Suppresses session-change teardown while stopCasting() handles its own cleanup/resume flow.
    private var isStoppingOwnCast = false

    /// Duration of the video being cast (read from activeSession)
    var castDuration: TimeInterval {
        CastManager.shared.activeSession?.duration ?? 0
    }

    /// Current cast playback time (interpolated from start position)
    var castCurrentTime: TimeInterval {
        guard let session = CastManager.shared.activeSession,
              session.metadata?.mediaType == .video else {
            return lastKnownVideoCastPosition
        }
        if let startDate = session.playbackStartDate {
            let elapsed = Date().timeIntervalSince(startDate)
            let current = session.position + elapsed
            return session.duration > 0 ? min(current, session.duration) : current
        }
        return session.position
    }

    @discardableResult
    private func cacheLastKnownVideoCastPosition() -> TimeInterval {
        let position = castCurrentTime
        lastKnownVideoCastPosition = position
        return position
    }
    
    /// Start the cast update timer (updates main window with progress)
    /// Note: Timer only updates UI after first status received from Chromecast
    private func startCastUpdateTimer() {
        castUpdateTimer?.invalidate()
        castUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isCastingVideo else { return }
            // Don't update UI until we've received first status from Chromecast
            // This prevents showing stale/incorrect time before sync (especially for 4K on slow networks)
            guard CastManager.shared.activeSession?.state != .loaded else { return }
            let current = self.castCurrentTime
            self.lastKnownVideoCastPosition = current
            let duration = CastManager.shared.activeSession?.duration ?? 0
            WindowManager.shared.videoDidUpdateTime(current: current, duration: duration)
        }
        // Don't fire immediately - wait for first Chromecast status update
    }
    
    /// Stop the cast update timer
    private func stopCastUpdateTimer() {
        castUpdateTimer?.invalidate()
        castUpdateTimer = nil
    }
    
    /// Handle Chromecast media status updates for playback analytics
    @objc private func handleChromecastMediaStatusUpdate(_ notification: Notification) {
        guard isCastingVideo else { return }
        guard let status = notification.userInfo?["status"] as? CastMediaStatus else { return }

        let isPlaying = status.playerState == .playing
        let isBuffering = status.playerState == .buffering
        lastKnownVideoCastPosition = status.currentTime

        // CastManager handles all session state and first-status UI updates.
        // VPWC only drives playback analytics.
        if isBuffering {
            pausePlaybackAnalytics()
        } else if isPlaying {
            resumePlaybackAnalytics()
        } else {
            pausePlaybackAnalytics()
        }
    }
    
    /// Reset cast state when starting a new video
    /// This ensures the player doesn't think it's still casting from a previous session
    private func resetCastState() {
        guard isCastingVideo else { return }
        clearVideoCastState()
    }

    private func clearVideoCastState() {
        stopCastUpdateTimer()
        NotificationCenter.default.removeObserver(
            self,
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil
        )
        isCastingVideo = false
        didInitiateCast = false
        videoPlayerView.updateCastState(isPlaying: false, deviceName: nil)
    }

    /// Report the loaded film's end to its server and record its play. Every way a film ends goes
    /// through here: replaced by another, run out, stopped, or its window closed.
    private func reportVideoEnded(at position: TimeInterval, finished: Bool = false) {
        loadedVideo?.reporter?.videoDidStop(at: position, finished: finished)
        recordVideoPlayEvent()
    }

    /// Report the film stopped at `position`, stop local playback and forget what was loaded.
    private func unloadVideo(reportingStopAt position: TimeInterval) {
        reportVideoEnded(at: position)
        videoPlayerView.stop()
        isPlaying = false
        // A newly loaded film must never inherit the previous one's ended state.
        didReachEndOfMedia = false
        loadedVideo = nil
        WindowManager.shared.videoPlaybackDidStop()
    }

    /// Close the video player window when an audio cast supersedes an active video cast.
    /// Does NOT call CastManager.stopCasting() — the audio cast is already running.
    func closeForCastTransition() {
        NSLog("VideoPlayerWindowController: closeForCastTransition — closing video player (superseded by audio cast)")
        guard !isClosing else { return }
        isClosing = true

        let castPosition = cacheLastKnownVideoCastPosition()

        // Clear cast flags before close() so windowWillClose skips the cast-stop block
        stopCastUpdateTimer()
        isCastingVideo = false
        didInitiateCast = false

        unloadVideo(reportingStopAt: castPosition)
        close()
    }

    @objc private func handleCastSessionChange() {
        guard case .none = CastManager.shared.currentCast else { return }
        guard !isStoppingOwnCast else {
            NSLog("VideoPlayerWindowController: Ignoring cast session .none during local stopCasting() cleanup")
            return
        }
        if isCastingVideo || didInitiateCast {
            unloadVideo(reportingStopAt: cacheLastKnownVideoCastPosition())
        }
        clearVideoCastState()
    }
    
    /// How a queued film ended: played to its end, or never played (missing, unreadable, unreachable).
    enum VideoEnd { case finished, failed }

    /// Advances the playlist when the film ends. Set only by `WindowManager.playVideoTrack`, so
    /// non-nil exactly while the loaded film came from the playlist.
    var onQueuedVideoEnded: ((VideoEnd) -> Void)?

    /// Clears the callback before invoking it: it may load the next video, which sets a new one.
    private func endQueuedVideo(_ end: VideoEnd) {
        let callback = onQueuedVideoEnded
        onQueuedVideoEnded = nil
        callback?(end)
    }

    /// Current playback time
    var currentTime: TimeInterval {
        return videoPlayerView.currentPlaybackTime
    }
    
    /// Video duration
    var duration: TimeInterval {
        return videoPlayerView.totalPlaybackDuration
    }
    
    /// Volume level (0.0 - 1.0)
    var volume: Float {
        get { videoPlayerView.volume }
        set { videoPlayerView.volume = newValue }
    }
    
    // MARK: - Static Configuration
    
    /// Global one-time video-engine configuration hook (call once at app startup).
    ///
    /// VLCKit needs no global player-type / hardware-decode configuration — each
    /// `VLCMediaPlayer` is configured per-instance — so this is intentionally a
    /// no-op. Retained as a call site so startup wiring stays explicit.
    static func configureVideoEngine() {
        // No global VLCKit configuration required.
    }
    
    // MARK: - Initialization
    
    init() {
        // Create a borderless resizable window for video playback
        let contentRect = NSRect(x: 0, y: 0, width: 854, height: 480)
        let styleMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
        let window = VideoPlayerWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        window.title = "Video Player"
        window.minSize = NSSize(width: 480, height: 270)
        window.isReleasedWhenClosed = false
        window.center()
        
        // Dark appearance for video
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        
        // Allow window to be moved by dragging anywhere (though we handle title bar specifically)
        window.isMovableByWindowBackground = false
        
        // Allow resizing from edges
        window.isOpaque = true
        window.hasShadow = true
        
        // Enable fullscreen support for borderless window
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        
        super.init(window: window)
        
        setupVideoView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCastSessionChange),
            name: CastManager.sessionDidChangeNotification,
            object: nil
        )
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupVideoView() {
        // Ensure content view has black background to prevent any white pixels
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.backgroundColor = NSColor.black.cgColor
        
        videoPlayerView = VideoPlayerView(frame: window!.contentView!.bounds)
        videoPlayerView.autoresizingMask = [.width, .height]
        window?.contentView?.addSubview(videoPlayerView)
        
        // Set up callbacks for window controls
        videoPlayerView.onClose = { [weak self] in
            self?.close()
        }
        
        videoPlayerView.onMinimize = { [weak self] in
            self?.window?.miniaturize(nil)
        }
        
        // Track playback state changes
        videoPlayerView.onPlaybackStateChanged = { [weak self] playing in
            self?.updatePlayingState(playing)
        }
        
        // Track pause/resume for Plex/Jellyfin/Emby reporting
        videoPlayerView.onPlaybackPaused = { [weak self] position in
            guard let self = self else { return }
            self.pausePlaybackAnalytics()
            self.loadedVideo?.reporter?.videoDidPause(at: position)
        }

        videoPlayerView.onPlaybackResumed = { [weak self] position in
            guard let self = self else { return }
            self.resumePlaybackAnalytics()
            self.loadedVideo?.reporter?.videoDidResume(at: position)
        }

        videoPlayerView.onPositionUpdate = { [weak self] position in
            self?.loadedVideo?.reporter?.updatePosition(position)
        }

        // Track playback completion for Plex/Jellyfin/Emby scrobbling and playlist advancement
        videoPlayerView.onPlaybackFinished = { [weak self] position in
            guard let self = self else { return }
            // Report and record before advancing the playlist
            self.reportVideoEnded(at: position, finished: true)

            // A queued film's callback loads the next item and starts it, which clears the flag
            // through `updatePlayingState(true)` anyway, so only a film from outside the queue
            // marks its end.
            guard self.onQueuedVideoEnded != nil else {
                self.markReachedEndOfMedia()
                return
            }
            NSLog("VideoPlayer: Video finished from playlist, invoking callback")
            self.endQueuedVideo(.finished)
        }

        // A film that never played closes rather than leaving a black window over a paused engine;
        // a playlist film then goes to the engine as a failed load. Not while casting: the film is
        // on the device, and the local open failing does not end it.
        videoPlayerView.onPlaybackFailed = { [weak self] in
            guard let self, !self.isCastingVideo else { return }
            self.stop()
            self.endQueuedVideo(.failed)
        }
        
        // Cast button callback
        videoPlayerView.onCast = { [weak self] in
            self?.showCastMenu()
        }
        
        // Stop button callback
        videoPlayerView.onStop = { [weak self] in
            self?.stop()
        }
        
        // Control callbacks for casting intercept
        videoPlayerView.onPlayPauseToggled = { [weak self] in
            self?.togglePlayPause()
        }
        videoPlayerView.onSeekRequested = { [weak self] position in
            self?.handleSeekRequest(position)
        }
        videoPlayerView.onSkipForwardRequested = { [weak self] seconds in
            self?.skipForward(seconds)
        }
        videoPlayerView.onSkipBackwardRequested = { [weak self] seconds in
            self?.skipBackward(seconds)
        }
        
        // Set up local event monitor for keyboard shortcuts (especially Escape in fullscreen)
        setupKeyboardMonitor()
    }
    
    // MARK: - Playback Analytics

    private func beginPlaybackAnalyticsSession() {
        accumulatedPlaybackDuration = 0
        playbackStartTime = Date()
    }

    private func pausePlaybackAnalytics(at timestamp: Date = Date()) {
        guard let startTime = playbackStartTime else { return }
        accumulatedPlaybackDuration += timestamp.timeIntervalSince(startTime)
        playbackStartTime = nil
    }

    private func resumePlaybackAnalytics(at timestamp: Date = Date()) {
        guard playbackStartTime == nil else { return }
        playbackStartTime = timestamp
    }

    private func totalPlaybackDuration(at timestamp: Date) -> TimeInterval {
        accumulatedPlaybackDuration + (playbackStartTime.map { timestamp.timeIntervalSince($0) } ?? 0)
    }

    private func recordVideoPlayEvent() {
        let eventTimestamp = Date()
        let duration = totalPlaybackDuration(at: eventTimestamp)
        guard duration > 0 else { return }

        _ = MediaLibraryStore.shared.insertPlayEvent(
            trackId: nil,
            trackURL: nil,
            title: currentTitle,
            artist: nil,
            album: nil,
            genre: nil,
            playedAt: eventTimestamp,
            durationListened: duration,
            source: (loadedVideo?.playHistorySource ?? .local).rawValue,
            skipped: false,
            contentType: loadedVideo?.contentType ?? "video",
            outputDevice: CastManager.currentPlaybackDeviceName)

        playbackStartTime = nil
        accumulatedPlaybackDuration = 0
    }

    private func setupKeyboardMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let window = self.window else {
                return event
            }
            
            // Check if our window is the main window or is in fullscreen
            let isOurWindow = window.isKeyWindow || window.isMainWindow || window.styleMask.contains(.fullScreen)
            guard isOurWindow else {
                return event
            }
            return self.handleVideoKey(event) ? nil : event
        }
    }

    /// The video keys, answering whether one was handled. The free window's monitor above calls this;
    /// a parked window never becomes key, so the skin surface it is parked in offers it the keys the
    /// skin refused (M18).
    func handleVideoKey(_ event: NSEvent) -> Bool {
        guard let window else { return false }

        // Check for Cmd+S to open track selection panel
        if event.keyCode == 1 && event.modifierFlags.contains(.command) { // Cmd+S
            videoPlayerView.showTrackSelectionPanel()
            return true
        }

        switch event.keyCode {
        case 53: // Escape
            NSLog("VideoPlayer: Escape pressed, fullscreen=%d", window.styleMask.contains(.fullScreen) ? 1 : 0)
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                return true
            }
            // If track selection panel is visible, close it instead of the window
            if videoPlayerView.trackSelectionPanelVisible {
                videoPlayerView.hideTrackSelectionPanel()
                return true
            }
            // Consumed even when nothing is dismissed: a parked window still key from a fullscreen
            // round trip would otherwise pass Esc on to `VideoPlayerView`, which stops the film.
            dismissVideoOutput()
        case 49: // Space - toggle play/pause
            togglePlayPause()
        case 3: // F key - toggle fullscreen
            if isVideoOutputHosted { enterFullScreenReclaimingOutput() }
            else { window.toggleFullScreen(nil) }
        case 1: // S key - cycle subtitles
            videoPlayerView.cycleSubtitleTrack()
        case 0: // A key - cycle audio tracks
            videoPlayerView.cycleAudioTrack()
        case 123: // Left arrow - skip back
            skipBackward(10)
        case 124: // Right arrow - skip forward
            skipForward(10)
        default:
            return false
        }
        NSLog("VideoPlayer keyDown: keyCode=%d, isFullScreen=%d", event.keyCode, window.styleMask.contains(.fullScreen) ? 1 : 0)
        return true
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    // MARK: - Playback Control

    /// Where every `play(…)` starts: drop a cast left over from the previous video, report that
    /// video stopped to its server, and record its play.
    private func endPreviousVideo() {
        resetCastState()
        reportVideoEnded(at: videoPlayerView.currentPlaybackTime)
    }

    /// Load `video` from `url` and start it in the window. Only a Plex stream passes `plexHeaders`;
    /// the view reads them only for a Plex URL.
    private func startVideo(_ video: LoadedVideo, url: URL, plexHeaders: [String: String]? = nil) {
        loadedVideo = video
        window?.title = video.title
        revealVideoOutput()
        videoPlayerView.play(url: url, title: video.title, isPlexURL: plexHeaders != nil, plexHeaders: plexHeaders)
        isPlaying = true
        beginPlaybackAnalyticsSession()
        WindowManager.shared.videoPlaybackDidStart()
    }

    /// Play a video from URL with optional title
    /// If called from WindowManager.playVideoTrack, the onQueuedVideoEnded callback will be set
    func play(url: URL, title: String) {
        endPreviousVideo()
        startVideo(LoadedVideo(source: url.isFileURL ? .localFile(url) : .stream, title: title,
                               track: Track(url: url, title: title, mediaType: .video), contentType: "video"),
                   url: url)
    }

    /// Play a film from the playlist. A server film carries only its id on the track, which picks
    /// the server that hears its reports; any other plays as its URL.
    func play(track: Track) {
        guard let video = LoadedVideo(serverTrack: track) else {
            play(url: track.url, title: track.displayTitle)
            return
        }
        endPreviousVideo()
        let plexHeaders: [String: String]? = if case .plexItem = video.source { PlexManager.shared.streamingHeaders } else { nil }
        startVideo(video, url: track.url, plexHeaders: plexHeaders)
        video.reportStart()
    }

    /// Stop playback
    func stop() {
        NSLog("VideoPlayerWindowController: stop() — isCastingVideo=%d isClosing=%d", isCastingVideo ? 1 : 0, isClosing ? 1 : 0)
        guard !isClosing else { return }
        isClosing = true
        
        // Capture cast position before stopping (for Plex reporting)
        let wasCasting = isCastingVideo
        let castPosition = wasCasting ? cacheLastKnownVideoCastPosition() : 0
        
        // Stop casting if active (this will exit the movie on the TV)
        // Use semaphore to wait for cast stop to complete before closing
        if isCastingVideo {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await CastManager.shared.stopCasting()
                NSLog("VideoPlayerWindowController: Stopped video cast on TV")
                semaphore.signal()
            }
            // Wait up to 2 seconds for cast to stop
            _ = semaphore.wait(timeout: .now() + 2.0)

            stopCastUpdateTimer()
            isCastingVideo = false
            didInitiateCast = false
        }

        unloadVideo(reportingStopAt: wasCasting ? castPosition : videoPlayerView.currentPlaybackTime)
        // A parked picture lives over the skin's own video window, which declares `autoclose="1"`:
        // the component closing is what shuts that window. Unpark before closing, so no child window
        // is left hanging off a skin window that a skin or mode switch may take away next.
        if isVideoOutputHosted {
            _ = WindowManager.shared.hideWinampModernVideoSurface()
            WindowManager.shared.detachWinampModernVideoOutput()
        }
        close()
    }

    /// Toggle play/pause
    func togglePlayPause() {
        NSLog("VideoPlayerWindowController: togglePlayPause — isCastingVideo=%d", isCastingVideo ? 1 : 0)
        if isCastingVideo {
            toggleCastPlayPause()
        } else {
            videoPlayerView.togglePlayPause()
        }
    }

    /// Skip forward
    func skipForward(_ seconds: TimeInterval = 10) {
        NSLog("VideoPlayerWindowController: skipForward %.0fs — isCastingVideo=%d", seconds, isCastingVideo ? 1 : 0)
        if isCastingVideo {
            seekCastRelative(seconds)
        } else {
            videoPlayerView.skipForward(seconds)
        }
    }

    /// Skip backward
    func skipBackward(_ seconds: TimeInterval = 10) {
        NSLog("VideoPlayerWindowController: skipBackward %.0fs — isCastingVideo=%d", seconds, isCastingVideo ? 1 : 0)
        if isCastingVideo {
            seekCastRelative(-seconds)
        } else {
            videoPlayerView.skipBackward(seconds)
        }
    }
    
    /// Seek to specific time
    func seek(to time: TimeInterval) {
        NSLog("VideoPlayerWindowController.seek: time=%.1f, isCastingVideo=%d", time, isCastingVideo ? 1 : 0)
        if isCastingVideo {
            seekCast(to: time)
        } else {
            videoPlayerView.seek(to: time)
        }
    }
    
    /// Handle seek request from slider (normalized 0-1 position)
    private func handleSeekRequest(_ position: Double) {
        if isCastingVideo {
            // For casting, we need to convert position to time
            // Use duration from the original video
            let time = position * duration
            seekCast(to: time)
        } else {
            videoPlayerView.seekToPosition(position)
        }
    }
    
    // MARK: - Cast Playback Control
    
    /// Toggle play/pause on the cast device
    private func toggleCastPlayPause() {
        NSLog("VideoPlayerWindowController: toggleCastPlayPause — isPlaying=%d sessionState=%@",
              isPlaying ? 1 : 0,
              String(describing: CastManager.shared.activeSession?.state))
        Task {
            do {
                if CastManager.shared.activeSession?.state == .casting {
                    let receiverPlaying = CastManager.shared.activeSession?.isPlaying ?? isPlaying
                    if receiverPlaying {
                        NSLog("VideoPlayerWindowController: Sending cast pause")
                        try await CastManager.shared.pause()
                        await MainActor.run {
                            isPlaying = false
                            let device = CastManager.shared.activeSession?.device
                            videoPlayerView.updateCastState(isPlaying: false, deviceName: device?.name)
                        }
                    } else {
                        NSLog("VideoPlayerWindowController: Sending cast resume")
                        try await CastManager.shared.resume()
                        await MainActor.run {
                            isPlaying = true
                            let device = CastManager.shared.activeSession?.device
                            videoPlayerView.updateCastState(isPlaying: true, deviceName: device?.name)
                        }
                    }
                } else {
                    NSLog("VideoPlayerWindowController: toggleCastPlayPause skipped — sessionState=%@",
                          String(describing: CastManager.shared.activeSession?.state))
                }
            } catch {
                NSLog("VideoPlayerWindowController: Cast toggle failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }
    
    /// Seek relative on cast device (for skip forward/backward)
    private func seekCastRelative(_ seconds: TimeInterval) {
        Task {
            do {
                let duration = CastManager.shared.activeSession?.duration ?? 0
                let requestedPosition = max(0, castCurrentTime + seconds)
                let newPosition = duration > 0 ? min(requestedPosition, duration) : requestedPosition
                if duration <= 0 {
                    NSLog("VideoPlayerWindowController: Cast relative seek without known duration (requested %.1f)", requestedPosition)
                }
                try await CastManager.shared.seek(to: newPosition)
                // CastManager has updated activeSession with new position
                NSLog("VideoPlayerWindowController: Cast seek to %.1f (relative %.1f)", newPosition, seconds)
            } catch {
                NSLog("VideoPlayerWindowController: Cast seek failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }
    
    /// Seek to absolute position on cast device
    private func seekCast(to time: TimeInterval) {
        Task {
            do {
                let duration = CastManager.shared.activeSession?.duration ?? 0
                let requestedTime = max(0, time)
                let clampedTime = duration > 0 ? min(requestedTime, duration) : requestedTime
                if duration <= 0 {
                    NSLog("VideoPlayerWindowController: Cast seek without known duration (requested %.1f)", requestedTime)
                }
                try await CastManager.shared.seek(to: clampedTime)
                // CastManager has updated activeSession with new position
                NSLog("VideoPlayerWindowController: Cast seek to %.1f", clampedTime)
            } catch {
                NSLog("VideoPlayerWindowController: Cast seek failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }
    
    /// Update playing state (called from VideoPlayerView)
    func updatePlayingState(_ playing: Bool) {
        isPlaying = playing
        // The single funnel every playback transition goes through — which is what makes seeking an
        // ended film back and pressing play restore the session the `.wal` host reads, and what
        // catches the end of media that VLCKit reports as a plain pause.
        if playing {
            didReachEndOfMedia = false
        } else if isParkedAtEndOfMedia {
            markReachedEndOfMedia()
        }
        WindowManager.shared.videoDidChangePlaybackState(playing)
    }
    
    // MARK: - Video Casting
    
    /// Show cast device menu
    private func showCastMenu() {
        let menu = NSMenu()
        
        // If currently casting, show stop option first
        if isCastingVideo, let device = CastManager.shared.activeSession?.device {
            let castingItem = NSMenuItem(title: "Casting to \(device.name)", action: nil, keyEquivalent: "")
            castingItem.isEnabled = false
            menu.addItem(castingItem)
            
            let stopItem = NSMenuItem(title: "Stop Casting", action: #selector(stopCasting), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // Get video-capable devices
        let devices = CastManager.shared.videoCapableDevices
        
        if devices.isEmpty {
            let item = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            // Group by type
            let chromecasts = devices.filter { $0.type == .chromecast }
            let dlnaTVs = devices.filter { $0.type == .dlnaTV }
            let activeVideoId = CastManager.shared.currentCast == .video ? CastManager.shared.activeSession?.device.id : nil
            
            if !chromecasts.isEmpty {
                let headerItem = NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                for device in chromecasts {
                    let title = device.id == activeVideoId ? "  ✓ \(device.name)" : "  \(device.name)"
                    let item = NSMenuItem(title: title, action: #selector(castToDevice(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = device
                    // Disable if already casting to this device
                    item.isEnabled = device.id != activeVideoId
                    menu.addItem(item)
                }
            }
            
            if !dlnaTVs.isEmpty {
                if !chromecasts.isEmpty { menu.addItem(NSMenuItem.separator()) }
                let headerItem = NSMenuItem(title: "TVs", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                for device in dlnaTVs {
                    let title = device.id == activeVideoId ? "  ✓ \(device.name)" : "  \(device.name)"
                    let item = NSMenuItem(title: title, action: #selector(castToDevice(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = device
                    // Disable if already casting to this device
                    item.isEnabled = device.id != activeVideoId
                    menu.addItem(item)
                }
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh Devices", action: #selector(refreshCastDevices), keyEquivalent: ""))
        
        // Show menu at cast button location
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: videoPlayerView)
        }
    }
    
    @objc private func castToDevice(_ sender: NSMenuItem) {
        let selectedDevice = sender.representedObject as? CastDevice
        guard let device = selectedDevice ?? CastManager.shared.preferredVideoCastDevice else { return }

        // Prevent dual casting - check if already casting from context menu
        if case .video = CastManager.shared.currentCast, !isCastingVideo {
            NSLog("VideoPlayerWindowController: Cannot cast - already casting from context menu")
            let alert = NSAlert()
            alert.messageText = "Already Casting"
            alert.informativeText = "Stop the current cast before starting a new one."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let wasPlaying = videoPlayerView.isPlaying
        let startPosition = videoPlayerView.currentPlaybackTime
        Task {
            do {
                try await performCast(to: device, startPosition: startPosition, savePreference: selectedDevice != nil)
            } catch {
                NSLog("VideoPlayerWindowController: Video cast failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Cast Failed"
                    alert.informativeText = "Unable to start casting. Check that the device is available and try again."
                    alert.alertStyle = .warning
                    alert.runModal()
                    self.clearVideoCastState()
                    self.shouldResumeLocalPlaybackAfterCast = false
                    if wasPlaying && !self.videoPlayerView.isPlaying {
                        self.videoPlayerView.togglePlayPause()
                    }
                }
            }
        }
    }

    /// Core cast initiation logic shared by manual cast and auto-cast.
    /// pauseLocal: false when the caller has already stopped local playback (auto-cast path).
    private func performCast(to device: CastDevice, startPosition: TimeInterval, savePreference: Bool = false, pauseLocal: Bool = true) async throws {
        let videoDuration = await MainActor.run { videoPlayerView.totalPlaybackDuration }

        // Pause local playback before handing off to Chromecast.
        // Skip for auto-cast path: the caller already called stop() synchronously.
        if pauseLocal {
            await MainActor.run {
                self.shouldResumeLocalPlaybackAfterCast = videoPlayerView.isPlaying
                if self.shouldResumeLocalPlaybackAfterCast {
                    videoPlayerView.togglePlayPause()
                }
            }
        } else {
            await MainActor.run {
                self.shouldResumeLocalPlaybackAfterCast = false
            }
        }

        guard let track = await MainActor.run(body: { self.loadedVideo?.track }) else {
            throw CastError.playbackFailed("No castable content loaded")
        }
        try await CastManager.shared.castVideoTrack(
            track,
            to: device,
            startPosition: startPosition,
            duration: videoDuration > 0 ? videoDuration : track.duration
        )

        // Update casting state and time tracking
        await MainActor.run {
            self.isCastingVideo = true
            self.didInitiateCast = true
            self.isPlaying = true
            self.lastKnownVideoCastPosition = startPosition
            self.videoPlayerView.updateCastState(isPlaying: true, deviceName: device.name)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleChromecastMediaStatusUpdate),
                name: ChromecastManager.mediaStatusDidUpdateNotification,
                object: nil
            )

            self.startCastUpdateTimer()
        }

        if savePreference {
            CastManager.shared.setPreferredVideoCastDevice(device.id)
        }

        NSLog("VideoPlayerWindowController: Video cast started to %@ at %.1f / %.1f", device.name, startPosition, videoDuration)
    }

    @objc private func stopCasting() {
        Task {
            // Capture current cast position before stopping
            let resumePosition = await MainActor.run {
                self.isStoppingOwnCast = true
                return self.cacheLastKnownVideoCastPosition()
            }
            
            await CastManager.shared.stopCasting()
            
            await MainActor.run {
                let shouldResumeLocalPlayback = self.shouldResumeLocalPlaybackAfterCast
                self.clearVideoCastState()
                
                // Resume local playback from where casting left off
                if shouldResumeLocalPlayback {
                    NSLog("VideoPlayerWindowController: Resuming local playback at %.1f", resumePosition)
                    self.videoPlayerView.seek(to: resumePosition)
                    self.videoPlayerView.togglePlayPause()  // Start playback
                    self.isPlaying = true
                }
                self.shouldResumeLocalPlaybackAfterCast = false
                self.isStoppingOwnCast = false
            }
            
            NSLog("VideoPlayerWindowController: Video casting stopped")
        }
    }
    
    @objc private func refreshCastDevices() {
        CastManager.shared.refreshDevices()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Stop cast update timer
        stopCastUpdateTimer()
        // sessionDidChangeNotification is intentionally NOT removed here.
        // WindowManager reuses this controller, so removing it on close would leave
        // handleCastSessionChange() unregistered for subsequent cast sessions.
        // deinit removes it when the controller is finally deallocated.
        NSLog("VideoPlayerWindowController: windowWillClose — keeping sessionDidChangeNotification observer (controller reused)")
        NotificationCenter.default.removeObserver(
            self,
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil
        )
        
        // Only do cleanup if not already handled by stop()
        if !isClosing {
            // Stop casting only if this window initiated the cast.
            // Casts launched from a library context menu are owned by CastManager; closing an
            // unrelated player window must not interrupt them.
            if case .video = CastManager.shared.currentCast, didInitiateCast {
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    await CastManager.shared.stopCasting()
                    NSLog("VideoPlayerWindowController: Stopped video cast on TV (window closed)")
                    semaphore.signal()
                }
                // Wait up to 2 seconds for cast to stop
                _ = semaphore.wait(timeout: .now() + 2.0)

                isCastingVideo = false
                didInitiateCast = false
            }
            
            unloadVideo(reportingStopAt: videoPlayerView.currentPlaybackTime)
        }
        removeKeyboardMonitor()
        isClosing = false  // Reset for potential reuse
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: CastManager.sessionDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil
        )
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        videoPlayerView.updateActiveState(true)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        videoPlayerView.updateActiveState(false)
    }
    
    // MARK: - Keyboard Shortcuts
    
    @objc func toggleFullScreen(_ sender: Any?) {
        if isVideoOutputHosted { enterFullScreenReclaimingOutput() }
        else { window?.toggleFullScreen(sender) }
    }

    // MARK: - Hosting the picture in a `.wal` skin's video window (B20)

    /// True while this window is parked as a child of the skin's video window.
    private(set) var isVideoOutputHosted = false
    /// The free-floating frame to come back to, and the limits that go with it.
    private var frameBeforeHosting: NSRect?
    private var minSizeBeforeHosting: NSSize?

    /// Whether the picture is on screen. A hosted window is a *child* window, so it is visible
    /// exactly when the skin's video window it hangs off is.
    var isVideoOutputVisible: Bool { window?.isVisible == true }

    /// The stream's own pixel size, or `.zero` before the decoder knows it.
    var presentationSize: CGSize { videoPlayerView?.presentationSize ?? .zero }

    var hasVideoOutput: Bool { videoPlayerView?.hasVideoOutput == true }

    /// The picture's own context menu — Play/Pause, Audio, **Subtitles**, Track Settings, fullscreen.
    ///
    /// A `.wmz` holder shows this from the skin's video rect rather than from the picture, because
    /// the parked window takes no mouse events of its own (see `WMPVideoSurface`). It is the only
    /// route to subtitles while the picture is in a skin: the command bar is switched off there.
    var videoOutputMenu: NSMenu? { videoPlayerView?.menu }

    /// Whether the slide-out track panel — the only place carrying the subtitle *delay* — is up.
    var isTrackSelectionPanelVisible: Bool { videoPlayerView?.trackSelectionPanelVisible ?? false }

    /// WMP-only presentation state is restored before the output returns to any other family.
    func configureWMPVideoOutput(imageRect: CGRect?, maintainAspectRatio: Bool = true) {
        videoPlayerView?.wmpVideoRect = imageRect
        videoPlayerView?.setWMPVideoAspectRatio(maintainAspectRatio ? nil : imageRect?.size)
        videoPlayerView?.layer?.masksToBounds = imageRect != nil
        videoPlayerView?.layoutSubtreeIfNeeded()
    }

    var isVideoFullScreenTransition: Bool { shouldReturnOutputToSkinAfterFullScreen }

    /// Winamp's command bar over the picture, which a skin's holder can switch off.
    var showsVideoControlBar: Bool {
        get { videoPlayerView?.showsControlBar ?? true }
        set { videoPlayerView?.showsControlBar = newValue }
    }

    /// The narrowest window the command bar will allow. A box narrower than this cannot show the bar
    /// at all — its constraints are what the window's minimum size is derived from.
    var videoControlBarMinimumWidth: CGFloat { videoPlayerView?.controlBarMinimumWidth ?? 0 }

    /// Park this window over a `.wal` skin's video box, as a child of the skin's window.
    ///
    /// **Not** a reparent of the video view. Moving `videoPlayerView` into the skin's view tree was
    /// the obvious shape — it is what the `.library` surface does — and it does not survive contact
    /// with the video engine: VLCKit installs its own output view under `playerHostView` and sizes
    /// that view's ancestors, so the skin window's content view ran away by tens of thousands of
    /// pixels on the first frame, and the picture only appeared once something else forced a
    /// relayout. A child window is the isolation that fixes it by construction: AppKit gives it its
    /// own layout tree, so nothing the decoder does to its view can reach the skin's, while
    /// `addChildWindow` keeps it glued to the skin window as that window moves, hides and closes.
    func hostOutputWindow(over host: NSView) {
        guard let window, let parent = host.window else { return }
        if frameBeforeHosting == nil { frameBeforeHosting = window.frame }
        if minSizeBeforeHosting == nil { minSizeBeforeHosting = window.minSize }
        videoPlayerView?.isEmbeddedInSkin = true
        // A skin's video box is routinely smaller than the free window's 480×270 floor, and
        // `setFrame` is clamped by `minSize` — without this the picture would sit in a window too
        // big for the hole it is filling.
        window.minSize = NSSize(width: 1, height: 1)
        window.hasShadow = false
        if window.parent !== parent {
            window.parent?.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
        }
        isVideoOutputHosted = true
        updateHostedOutputFrame(over: host)
        window.orderFront(nil)
    }

    /// Keep the parked window on the box. Called whenever the skin lays its holder out again — a
    /// window resize, a layout switch, a UI Size change.
    func updateHostedOutputFrame(over host: NSView) {
        guard isVideoOutputHosted, let window, let parent = host.window else { return }
        let inParent = host.convert(host.bounds, to: nil)
        window.setFrame(parent.convertToScreen(inParent), display: true)
        #if DEBUG
        // The frame AppKit *granted*, not the one asked for. A window whose content carries required
        // Auto Layout constraints has a minimum size derived from them and silently refuses anything
        // smaller — which is the whole of this feature's hardest defect, and invisible without this.
        if abs(window.frame.width - inParent.width) > 1 || abs(window.frame.height - inParent.height) > 1 {
            NSLog("WinampModern video: box %@ refused, window took %@",
                  NSStringFromSize(inParent.size), NSStringFromSize(window.frame.size))
        }
        #endif
    }

    /// Unpark: back to a free-floating window of its own, at the frame and limits it had before.
    /// `reveal` shows it, which is what a still-playing video needs when the skin's box goes away.
    func reclaimVideoOutput(reveal: Bool) {
        guard let window else { return }
        if isVideoOutputHosted {
            window.parent?.removeChildWindow(window)
            window.hasShadow = true
            if let minSizeBeforeHosting { window.minSize = minSizeBeforeHosting }
            if let frameBeforeHosting { window.setFrame(frameBeforeHosting, display: false) }
            frameBeforeHosting = nil
            minSizeBeforeHosting = nil
        }
        videoPlayerView?.isEmbeddedInSkin = false
        isVideoOutputHosted = false
        if reveal {
            showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
        }
    }

    /// `VID_FS` with a parked picture. A child window cannot go fullscreen, so it is unparked first
    /// and this window goes fullscreen on its own — the same window `VID_FS` has always used.
    /// Leaving fullscreen parks it back over the skin's box.
    func enterFullScreenReclaimingOutput() {
        let wasHosted = isVideoOutputHosted
        reclaimVideoOutput(reveal: true)
        shouldReturnOutputToSkinAfterFullScreen = wasHosted
        window?.toggleFullScreen(nil)
    }

    /// Set while a parked picture is borrowed back for fullscreen, so exiting returns it.
    private var shouldReturnOutputToSkinAfterFullScreen = false

    func windowDidExitFullScreen(_ notification: Notification) {
        guard shouldReturnOutputToSkinAfterFullScreen else { return }
        shouldReturnOutputToSkinAfterFullScreen = false
        // One turn later: AppKit is still restoring this window's own frame and style as the
        // notification lands, and re-parenting inside that leaves it parked at the fullscreen size.
        DispatchQueue.main.async {
            let manager = WindowManager.shared
            if manager.uiMode.controllerFamily == .wmp {
                manager.mainWindowController?.updatePlaybackState()
            } else {
                manager.hostVideoOutputInWinampModernSkin()
            }
        }
    }

    /// Where a play call reveals the picture. Parked, that is the skin's own video window (the
    /// `autoopen="1"` every measured holder declares); otherwise this window, exactly as before.
    ///
    /// Key focus goes with the picture in every case, or it stays on the Library Browser that started
    /// the film, where Return replays the selected row from 0 (M5).
    private func revealVideoOutput() {
        if WindowManager.shared.hostVideoOutputInSkin() { return }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Escape. Hosted, that hides the skin's own video window (`autoclose="1"`) and leaves playback
    /// alone for the skin to reopen; in this controller's own window it closes, which is the stop it
    /// has always been. A `.wmz` box or a `.wal` video tab has no window of its own to hide, so there
    /// it does nothing: closing would stop the film, and unparking strands a black tab (M18).
    func dismissVideoOutput() {
        if isVideoOutputHosted { WindowManager.shared.closeWinampModernVideoWindow(); return }
        close()
    }

    /// The video view's own context menu — play/pause, skip, audio and subtitle tracks, settings.
    ///
    /// Exposed so a `.wal` skin's `VID_MISC` button opens the same menu the video window offers on
    /// right-click rather than a second, thinner imitation of it. Its items target the video view, so
    /// it works wherever it is popped up.
    var contextMenu: NSMenu? { videoPlayerView?.menu }
}

#if DEBUG
extension VideoPlayerWindowController {
    struct DebugCastStateSnapshot {
        let isCastingVideo: Bool
        let hasTargetDevice: Bool
        let castStartPosition: TimeInterval
        let hasPlaybackStartDate: Bool
        let castState: CastState
        let castDuration: TimeInterval
    }

    func debugSetCurrentTitleForTesting(_ title: String?) {
        loadedVideo = title.map { LoadedVideo(source: .stream, title: $0, track: Track(url: URL(string: "about:blank")!, title: $0, mediaType: .video), contentType: "video") }
    }

    func debugSetCastStateForTesting(device: CastDevice, startPosition: TimeInterval, duration: TimeInterval) {
        // For testing, set up the cast session in CastManager and mark this controller as casting
        CastManager.shared.debugSetActiveCastSessionForTesting(device: device, startPosition: startPosition, duration: duration)
        isCastingVideo = true
    }

    func debugSetDidInitiateCastForTesting(_ value: Bool) {
        didInitiateCast = value
    }

    var debugDidInitiateCast: Bool { didInitiateCast }

    func debugSetStoppingOwnCastForTesting(_ value: Bool) {
        isStoppingOwnCast = value
    }

    var debugCastStateSnapshot: DebugCastStateSnapshot {
        let session = CastManager.shared.activeSession
        return DebugCastStateSnapshot(
            isCastingVideo: isCastingVideo,
            hasTargetDevice: session?.device != nil,
            castStartPosition: session?.position ?? 0,
            hasPlaybackStartDate: session?.playbackStartDate != nil,
            castState: session?.state ?? .idle,
            castDuration: session?.duration ?? 0
        )
    }
}
#endif
