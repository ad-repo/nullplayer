import Foundation

/// Manages reporting playback state and scrobbling to Plex
/// Handles periodic timeline updates and automatic scrobbling when tracks finish
class PlexPlaybackReporter {
    
    // MARK: - Singleton
    
    static let shared = PlexPlaybackReporter()
    
    // MARK: - Configuration
    
    /// How often to send timeline updates (in seconds)
    private let timelineUpdateInterval: TimeInterval = 10.0
    
    /// Percentage of track that must be played to count as "played" (0.0 - 1.0)
    /// Plex typically uses 90% or reaching the end
    private let scrobbleThreshold: Double = 0.90
    
    /// Minimum playback time (in seconds) before scrobbling is allowed
    /// Prevents accidental scrobbles from quick skips
    private let minimumPlayTime: TimeInterval = 30.0
    
    // MARK: - State
    
    /// Currently playing track (if it's a Plex track)
    private var currentTrack: Track?
    
    /// Rating key of the current Plex item
    private var currentRatingKey: String?
    
    /// Duration of the current track in milliseconds
    private var currentDurationMs: Int = 0
    
    /// Whether the current track has been scrobbled
    private var hasScrobbled: Bool = false
    
    /// Total time played for the current track (for scrobble threshold)
    private var totalPlayTime: TimeInterval = 0
    
    /// Timestamp when playback started/resumed (for tracking play time)
    private var playbackStartTime: Date?
    
    /// Current playback state
    private var currentState: PlaybackReportState = .stopped
    
    /// Timer for periodic timeline updates
    private var timelineTimer: Timer?
    
    /// Last reported position (to avoid duplicate reports)
    private var lastReportedPosition: Int = 0
    
    // MARK: - Initialization
    
    private init() {
        NSLog("PlexPlaybackReporter: Initialized")
    }
    
    // MARK: - Public API
    
    /// Called when a track starts playing
    /// - Parameters:
    ///   - track: The track that started playing
    ///   - position: Starting position in seconds (for resume)
    func trackDidStart(_ track: Track, at position: TimeInterval = 0) {
        // Only track Plex content
        guard let ratingKey = track.plexRatingKey else {
            stopTracking()
            return
        }
        
        NSLog("PlexPlaybackReporter: Track started - %@ (key: %@)", track.title, ratingKey)
        
        // Set up tracking for this track
        currentTrack = track
        currentRatingKey = ratingKey
        currentDurationMs = Int((track.duration ?? 0) * 1000)
        hasScrobbled = false
        totalPlayTime = position  // Start from resume position
        playbackStartTime = Date()
        currentState = .playing
        lastReportedPosition = Int(position * 1000)
        
        // Report initial playing state
        reportState(.playing, at: position)
        
        // Start periodic updates
        startTimelineTimer()
    }
    
    /// Called when playback is paused
    /// - Parameter position: Current position in seconds
    func trackDidPause(at position: TimeInterval) {
        guard currentRatingKey != nil else { return }
        
        NSLog("PlexPlaybackReporter: Track paused at %.1fs", position)
        
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
    func trackDidResume(at position: TimeInterval) {
        guard currentRatingKey != nil else { return }
        
        NSLog("PlexPlaybackReporter: Track resumed at %.1fs", position)
        
        playbackStartTime = Date()
        currentState = .playing
        
        // Report playing state
        reportState(.playing, at: position)
        
        // Resume periodic updates
        startTimelineTimer()
    }
    
    /// Called when playback stops (manually or track ends)
    /// - Parameters:
    ///   - position: Final position in seconds
    ///   - finished: Whether the track finished naturally (vs user stopped)
    func trackDidStop(at position: TimeInterval, finished: Bool) {
        guard let ratingKey = currentRatingKey else { return }
        
        NSLog("PlexPlaybackReporter: Track stopped at %.1fs (finished: %d)", position, finished)
        
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
    
    /// Called periodically to update timeline (call from AudioEngine's time update)
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
    
    /// Force stop tracking (e.g., when switching to non-Plex content)
    func stopTracking() {
        stopTimelineTimer()
        currentTrack = nil
        currentRatingKey = nil
        currentDurationMs = 0
        hasScrobbled = false
        totalPlayTime = 0
        playbackStartTime = nil
        currentState = .stopped
        lastReportedPosition = 0
    }
    
    // MARK: - Private Methods
    
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
        
        Task {
            do {
                try await client.reportPlaybackState(
                    ratingKey: ratingKey,
                    state: state,
                    time: positionMs,
                    duration: currentDurationMs,
                    type: "music"
                )
                NSLog("PlexPlaybackReporter: Reported state '%@' at %dms", state.rawValue, positionMs)
            } catch {
                NSLog("PlexPlaybackReporter: Failed to report state: %@", error.localizedDescription)
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
                NSLog("PlexPlaybackReporter: Scrobbled track (key: %@)", ratingKey)
            } catch {
                NSLog("PlexPlaybackReporter: Failed to scrobble: %@", error.localizedDescription)
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
        
        Task {
            do {
                try await client.reportPlaybackState(
                    ratingKey: ratingKey,
                    state: .playing,
                    time: positionMs,
                    duration: currentDurationMs,
                    type: "music"
                )
            } catch {
                // Silently fail timeline updates - they're not critical
                NSLog("PlexPlaybackReporter: Timeline update failed: %@", error.localizedDescription)
            }
        }
    }
}
