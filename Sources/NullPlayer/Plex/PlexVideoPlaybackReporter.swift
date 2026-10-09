import Foundation
import NullPlayerCore

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
    
    /// The film being reported. A request captures it before its `Task`, so a film replaced while
    /// the request is in flight still reports as itself.
    private struct Playing: Equatable {
        let ratingKey: String
        let title: String
        let durationMs: Int
        let videoType: VideoType
    }
    
    private var playing: Playing?
    
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
    
    // MARK: - Initialization
    
    private init() {
        NSLog("PlexVideoPlaybackReporter: Initialized")
    }
    
    // MARK: - Public API
    
    /// Called when a Plex film starts playing in the video window
    /// - Parameters:
    ///   - ratingKey: The Plex rating key
    ///   - title: Video title
    ///   - durationSeconds: Duration in seconds
    ///   - isEpisode: Report it as an episode rather than a movie
    func videoTrackDidStart(itemId ratingKey: String, title: String, durationSeconds: TimeInterval, isEpisode: Bool) {
        NSLog("PlexVideoPlaybackReporter: Video track started - %@ (key: %@)", title, ratingKey)
        
        startTracking(
            Playing(
                ratingKey: ratingKey,
                title: title,
                durationMs: Int(durationSeconds * 1000),
                videoType: isEpisode ? .episode : .movie
            ),
            position: 0
        )
    }
    
    /// Called when playback is paused
    /// - Parameter position: Current position in seconds
    func videoDidPause(at position: TimeInterval) {
        guard playing != nil else { return }
        
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
        guard playing != nil else { return }
        
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
        guard playing != nil else { return }
        
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
                scrobble()
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
        guard playing != nil, currentState == .playing else { return }
        
        let positionMs = Int(position * 1000)
        
        // Check if we should scrobble
        if !hasScrobbled && shouldScrobbleAtPosition(position) {
            // Calculate current total play time
            var currentPlayTime = totalPlayTime
            if let startTime = playbackStartTime {
                currentPlayTime += Date().timeIntervalSince(startTime)
            }
            
            if currentPlayTime >= minimumPlayTime {
                scrobble()
            }
        }
        
        // Timeline updates are handled by the timer, not every position update
        lastReportedPosition = positionMs
    }
    
    /// Force stop tracking (e.g., when closing video player)
    func stopTracking() {
        stopTimelineTimer()
        playing = nil
        hasScrobbled = false
        totalPlayTime = 0
        playbackStartTime = nil
        currentState = .stopped
        lastReportedPosition = 0
    }
    
    /// Check if currently tracking a Plex video
    var isTracking: Bool {
        playing != nil
    }
    
    // MARK: - Private Methods
    
    private func startTracking(_ film: Playing, position: TimeInterval) {
        // Stop any existing tracking
        stopTracking()
        
        // Set up tracking for this video
        playing = film
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
        guard let playing, playing.durationMs > 0 else { return false }
        let durationSeconds = Double(playing.durationMs) / 1000.0
        let progress = position / durationSeconds
        return progress >= scrobbleThreshold
    }
    
    private func reportState(_ state: PlaybackReportState, at position: TimeInterval) {
        guard let playing,
              let client = PlexManager.shared.serverClient else { return }
        
        let positionMs = Int(position * 1000)
        
        Task {
            do {
                try await client.reportPlaybackState(
                    ratingKey: playing.ratingKey,
                    state: state,
                    time: positionMs,
                    duration: playing.durationMs,
                    type: playing.videoType.rawValue
                )
                NSLog("PlexVideoPlaybackReporter: Reported state '%@' at %dms for %@", 
                      state.rawValue, positionMs, playing.title)
            } catch {
                NSLog("PlexVideoPlaybackReporter: Failed to report state: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }
    
    private func scrobble() {
        guard !hasScrobbled, let playing else { return }
        hasScrobbled = true
        
        guard let client = PlexManager.shared.serverClient else { return }
        
        Task { @MainActor in
            do {
                try await client.scrobble(ratingKey: playing.ratingKey)
                NSLog("PlexVideoPlaybackReporter: Scrobbled video (key: %@, title: %@)", 
                      playing.ratingKey, playing.title)
            } catch {
                NSLog("PlexVideoPlaybackReporter: Failed to scrobble: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
                // Try again on a later update, unless another film has started since
                if self.playing == playing { self.hasScrobbled = false }
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
        guard let playing,
              currentState == .playing,
              let client = PlexManager.shared.serverClient else { return }
        
        let positionMs = lastReportedPosition
        
        Task {
            do {
                try await client.reportPlaybackState(
                    ratingKey: playing.ratingKey,
                    state: .playing,
                    time: positionMs,
                    duration: playing.durationMs,
                    type: playing.videoType.rawValue
                )
            } catch {
                // Silently fail timeline updates - they're not critical
                NSLog("PlexVideoPlaybackReporter: Timeline update failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }
}
