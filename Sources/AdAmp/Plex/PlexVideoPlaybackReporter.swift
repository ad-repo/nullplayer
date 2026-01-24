import Foundation

/// Manages reporting video playback state and scrobbling to Plex
/// Handles periodic timeline updates and automatic scrobbling when videos finish
class PlexVideoPlaybackReporter {
    
    // MARK: - Singleton
    
    static let shared = PlexVideoPlaybackReporter()
    
    // MARK: - Configuration
    
    /// How often to send timeline updates (in seconds)
    private let timelineUpdateInterval: TimeInterval = 10.0
    
    /// Percentage of video that must be played to count as "watched" (0.0 - 1.0)
    /// Plex typically uses 90% or reaching the end for videos
    private let scrobbleThreshold: Double = 0.90
    
    /// Minimum playback time (in seconds) before scrobbling is allowed
    /// Prevents accidental scrobbles from quick skips
    private let minimumPlayTime: TimeInterval = 60.0
    
    // MARK: - State
    
    /// Type of video content
    enum VideoType: String {
        case movie = "movie"
        case episode = "episode"
    }
    
    /// Rating key of the current Plex item
    private var currentRatingKey: String?
    
    /// Type of video being played
    private var currentVideoType: VideoType = .movie
    
    /// Duration of the current video in milliseconds
    private var currentDurationMs: Int = 0
    
    /// Whether the current video has been scrobbled
    private var hasScrobbled: Bool = false
    
    /// Total time played for the current video (for scrobble threshold)
    private var totalPlayTime: TimeInterval = 0
    
    /// Timestamp when playback started/resumed (for tracking play time)
    private var playbackStartTime: Date?
    
    /// Current playback state
    private var currentState: PlaybackReportState = .stopped
    
    /// Timer for periodic timeline updates
    private var timelineTimer: Timer?
    
    /// Last reported position in milliseconds
    private var lastReportedPosition: Int = 0
    
    /// Title of current video (for logging)
    private var currentTitle: String?
    
    // MARK: - Initialization
    
    private init() {
        NSLog("PlexVideoPlaybackReporter: Initialized")
    }
    
    // MARK: - Public API
    
    /// Called when a Plex movie starts playing
    /// - Parameters:
    ///   - movie: The movie that started playing
    ///   - position: Starting position in seconds (for resume)
    func movieDidStart(_ movie: PlexMovie, at position: TimeInterval = 0) {
        NSLog("PlexVideoPlaybackReporter: Movie started - %@ (key: %@)", movie.title, movie.id)
        
        startTracking(
            ratingKey: movie.id,
            title: movie.title,
            durationMs: movie.duration ?? 0,
            videoType: .movie,
            position: position
        )
    }
    
    /// Called when a Plex episode starts playing
    /// - Parameters:
    ///   - episode: The episode that started playing
    ///   - position: Starting position in seconds (for resume)
    func episodeDidStart(_ episode: PlexEpisode, at position: TimeInterval = 0) {
        let title = "\(episode.grandparentTitle ?? "Unknown") - \(episode.episodeIdentifier) - \(episode.title)"
        NSLog("PlexVideoPlaybackReporter: Episode started - %@ (key: %@)", title, episode.id)
        
        startTracking(
            ratingKey: episode.id,
            title: title,
            durationMs: episode.duration ?? 0,
            videoType: .episode,
            position: position
        )
    }
    
    /// Called when a Plex video track from playlist starts playing
    /// Used when we have a Track with plexRatingKey but not the full PlexMovie/PlexEpisode object
    /// - Parameters:
    ///   - ratingKey: The Plex rating key
    ///   - title: Video title
    ///   - durationSeconds: Duration in seconds
    ///   - position: Starting position in seconds (for resume)
    func videoTrackDidStart(ratingKey: String, title: String, durationSeconds: TimeInterval, at position: TimeInterval = 0) {
        NSLog("PlexVideoPlaybackReporter: Video track started - %@ (key: %@)", title, ratingKey)
        
        startTracking(
            ratingKey: ratingKey,
            title: title,
            durationMs: Int(durationSeconds * 1000),
            videoType: .movie,  // Default to movie type for playlist tracks
            position: position
        )
    }
    
    /// Called when playback is paused
    /// - Parameter position: Current position in seconds
    func videoDidPause(at position: TimeInterval) {
        guard currentRatingKey != nil else { return }
        
        NSLog("PlexVideoPlaybackReporter: Video paused at %.1fs", position)
        
        // Update total play time
        if let startTime = playbackStartTime {
            totalPlayTime += Date().timeIntervalSince(startTime)
        }
        playbackStartTime = nil
        currentState = .paused
        
        // Report paused state
        reportState(.paused, at: position)
        
        // Stop periodic updates while paused
        stopTimelineTimer()
    }
    
    /// Called when playback resumes
    /// - Parameter position: Current position in seconds
    func videoDidResume(at position: TimeInterval) {
        guard currentRatingKey != nil else { return }
        
        NSLog("PlexVideoPlaybackReporter: Video resumed at %.1fs", position)
        
        playbackStartTime = Date()
        currentState = .playing
        
        // Report playing state
        reportState(.playing, at: position)
        
        // Resume periodic updates
        startTimelineTimer()
    }
    
    /// Called when playback stops (manually or video ends)
    /// - Parameters:
    ///   - position: Final position in seconds
    ///   - finished: Whether the video finished naturally (vs user stopped)
    func videoDidStop(at position: TimeInterval, finished: Bool) {
        guard let ratingKey = currentRatingKey else { return }
        
        NSLog("PlexVideoPlaybackReporter: Video stopped at %.1fs (finished: %@)", position, finished ? "yes" : "no")
        
        // Update total play time
        if let startTime = playbackStartTime {
            totalPlayTime += Date().timeIntervalSince(startTime)
        }
        playbackStartTime = nil
        
        // Check if we should scrobble
        if !hasScrobbled {
            let shouldScrobble = finished || shouldScrobbleAtPosition(position)
            if shouldScrobble && totalPlayTime >= minimumPlayTime {
                scrobble(ratingKey: ratingKey)
            }
        }
        
        // Report stopped state
        reportState(.stopped, at: position)
        
        // Clean up
        stopTracking()
    }
    
    /// Called periodically to update timeline
    /// - Parameter position: Current position in seconds
    func updatePosition(_ position: TimeInterval) {
        guard currentRatingKey != nil, currentState == .playing else { return }
        
        let positionMs = Int(position * 1000)
        
        // Check if we should scrobble
        if !hasScrobbled && shouldScrobbleAtPosition(position) {
            // Calculate current total play time
            var currentPlayTime = totalPlayTime
            if let startTime = playbackStartTime {
                currentPlayTime += Date().timeIntervalSince(startTime)
            }
            
            if currentPlayTime >= minimumPlayTime {
                if let ratingKey = currentRatingKey {
                    scrobble(ratingKey: ratingKey)
                }
            }
        }
        
        // Timeline updates are handled by the timer, not every position update
        lastReportedPosition = positionMs
    }
    
    /// Force stop tracking (e.g., when closing video player)
    func stopTracking() {
        stopTimelineTimer()
        currentRatingKey = nil
        currentTitle = nil
        currentDurationMs = 0
        hasScrobbled = false
        totalPlayTime = 0
        playbackStartTime = nil
        currentState = .stopped
        lastReportedPosition = 0
    }
    
    /// Check if currently tracking a Plex video
    var isTracking: Bool {
        currentRatingKey != nil
    }
    
    // MARK: - Private Methods
    
    private func startTracking(
        ratingKey: String,
        title: String,
        durationMs: Int,
        videoType: VideoType,
        position: TimeInterval
    ) {
        // Stop any existing tracking
        stopTracking()
        
        // Set up tracking for this video
        currentRatingKey = ratingKey
        currentTitle = title
        currentDurationMs = durationMs
        currentVideoType = videoType
        hasScrobbled = false
        totalPlayTime = 0  // Track actual session playtime, not resume position
        playbackStartTime = Date()
        currentState = .playing
        lastReportedPosition = Int(position * 1000)
        
        // Report initial playing state
        reportState(.playing, at: position)
        
        // Start periodic updates
        startTimelineTimer()
    }
    
    private func shouldScrobbleAtPosition(_ position: TimeInterval) -> Bool {
        guard currentDurationMs > 0 else { return false }
        let durationSeconds = Double(currentDurationMs) / 1000.0
        let progress = position / durationSeconds
        return progress >= scrobbleThreshold
    }
    
    private func reportState(_ state: PlaybackReportState, at position: TimeInterval) {
        guard let ratingKey = currentRatingKey,
              let client = PlexManager.shared.serverClient else { return }
        
        let positionMs = Int(position * 1000)
        let videoType = currentVideoType.rawValue
        
        Task {
            do {
                try await client.reportPlaybackState(
                    ratingKey: ratingKey,
                    state: state,
                    time: positionMs,
                    duration: currentDurationMs,
                    type: videoType
                )
                NSLog("PlexVideoPlaybackReporter: Reported state '%@' at %dms for %@", 
                      state.rawValue, positionMs, self.currentTitle ?? "unknown")
            } catch {
                NSLog("PlexVideoPlaybackReporter: Failed to report state: %@", error.localizedDescription)
            }
        }
    }
    
    private func scrobble(ratingKey: String) {
        guard !hasScrobbled else { return }
        hasScrobbled = true
        
        guard let client = PlexManager.shared.serverClient else { return }
        
        Task {
            do {
                try await client.scrobble(ratingKey: ratingKey)
                NSLog("PlexVideoPlaybackReporter: Scrobbled video (key: %@, title: %@)", 
                      ratingKey, self.currentTitle ?? "unknown")
            } catch {
                NSLog("PlexVideoPlaybackReporter: Failed to scrobble: %@", error.localizedDescription)
                // Reset flag so we can try again
                hasScrobbled = false
            }
        }
    }
    
    private func startTimelineTimer() {
        stopTimelineTimer()
        
        let timer = Timer(timeInterval: timelineUpdateInterval, repeats: true) { [weak self] _ in
            self?.sendTimelineUpdate()
        }
        RunLoop.main.add(timer, forMode: .common)
        timelineTimer = timer
    }
    
    private func stopTimelineTimer() {
        timelineTimer?.invalidate()
        timelineTimer = nil
    }
    
    private func sendTimelineUpdate() {
        guard let ratingKey = currentRatingKey,
              currentState == .playing,
              let client = PlexManager.shared.serverClient else { return }
        
        let positionMs = lastReportedPosition
        let videoType = currentVideoType.rawValue
        
        Task {
            do {
                try await client.reportPlaybackState(
                    ratingKey: ratingKey,
                    state: .playing,
                    time: positionMs,
                    duration: currentDurationMs,
                    type: videoType
                )
            } catch {
                // Silently fail timeline updates - they're not critical
                NSLog("PlexVideoPlaybackReporter: Timeline update failed: %@", error.localizedDescription)
            }
        }
    }
}
