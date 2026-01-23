import Foundation

/// Reports playback state to Subsonic servers for scrobbling and "now playing"
class SubsonicPlaybackReporter {
    
    // MARK: - Singleton
    
    static let shared = SubsonicPlaybackReporter()
    
    // MARK: - Properties
    
    /// Currently playing track info (for scrobbling)
    private var currentTrackId: String?
    private var currentServerId: String?
    private var trackStartTime: Date?
    private var trackDuration: TimeInterval = 0
    
    /// Whether we've reported "now playing" for the current track
    private var hasReportedNowPlaying: Bool = false
    
    /// Whether we've scrobbled the current track
    private var hasScrobbled: Bool = false
    
    /// Minimum play time before scrobbling (in seconds)
    /// Standard scrobbling rules: 50% of track or 4 minutes, whichever comes first
    private let minimumPlayPercentage: Double = 0.50
    private let maximumPlayTimeForScrobble: TimeInterval = 240  // 4 minutes
    
    /// Debounce timer for position updates
    private var updateTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Playback Reporting
    
    /// Called when a new track starts playing
    func trackStarted(trackId: String, serverId: String, duration: TimeInterval) {
        // Reset state for new track
        currentTrackId = trackId
        currentServerId = serverId
        trackStartTime = Date()
        trackDuration = duration
        hasReportedNowPlaying = false
        hasScrobbled = false
        
        NSLog("SubsonicPlaybackReporter: Track started - ID: %@, duration: %.0fs", trackId, duration)
        
        // Report "now playing" immediately
        reportNowPlaying()
    }
    
    /// Called when playback position changes (debounced)
    func updatePlayback(trackId: String, serverId: String, position: TimeInterval, duration: TimeInterval) {
        // Only process if this is the current track
        guard trackId == currentTrackId, serverId == currentServerId else {
            // New track detected, start fresh
            trackStarted(trackId: trackId, serverId: serverId, duration: duration)
            return
        }
        
        // Check if we should scrobble
        checkForScrobble(position: position)
    }
    
    /// Called when playback stops
    func trackStopped() {
        // Clear state
        currentTrackId = nil
        currentServerId = nil
        trackStartTime = nil
        trackDuration = 0
        hasReportedNowPlaying = false
        hasScrobbled = false
        
        updateTimer?.invalidate()
        updateTimer = nil
        
        NSLog("SubsonicPlaybackReporter: Track stopped")
    }
    
    /// Called when track is paused
    func trackPaused() {
        // We don't need to report pause to Subsonic
        NSLog("SubsonicPlaybackReporter: Track paused")
    }
    
    /// Called when track resumes from pause
    func trackResumed() {
        // Report now playing again after resume
        if !hasScrobbled {
            reportNowPlaying()
        }
    }
    
    // MARK: - Private Methods
    
    /// Report "now playing" to the server
    private func reportNowPlaying() {
        guard let trackId = currentTrackId,
              let serverId = currentServerId,
              let client = getClient(for: serverId) else {
            return
        }
        
        guard !hasReportedNowPlaying else { return }
        
        hasReportedNowPlaying = true
        
        Task {
            do {
                try await client.scrobble(id: trackId, submission: false)
                NSLog("SubsonicPlaybackReporter: Reported 'now playing' for track %@", trackId)
            } catch {
                NSLog("SubsonicPlaybackReporter: Failed to report 'now playing': %@", error.localizedDescription)
            }
        }
    }
    
    /// Check if we should scrobble based on current position
    private func checkForScrobble(position: TimeInterval) {
        guard !hasScrobbled else { return }
        guard trackDuration > 0 else { return }
        
        // Calculate play percentage
        let playPercentage = position / trackDuration
        
        // Scrobble if played 50% or 4 minutes, whichever comes first
        let shouldScrobble = (playPercentage >= minimumPlayPercentage) ||
                            (position >= maximumPlayTimeForScrobble && trackDuration > maximumPlayTimeForScrobble)
        
        if shouldScrobble {
            scrobbleCurrentTrack()
        }
    }
    
    /// Scrobble the current track
    private func scrobbleCurrentTrack() {
        guard let trackId = currentTrackId,
              let serverId = currentServerId,
              let client = getClient(for: serverId) else {
            return
        }
        
        guard !hasScrobbled else { return }
        
        hasScrobbled = true
        
        Task {
            do {
                try await client.scrobble(id: trackId, submission: true)
                NSLog("SubsonicPlaybackReporter: Scrobbled track %@", trackId)
            } catch {
                NSLog("SubsonicPlaybackReporter: Failed to scrobble: %@", error.localizedDescription)
                // Reset flag so we can try again
                hasScrobbled = false
            }
        }
    }
    
    /// Get the client for a specific server
    private func getClient(for serverId: String) -> SubsonicServerClient? {
        // Use the current server's client if it matches
        if SubsonicManager.shared.currentServer?.id == serverId {
            return SubsonicManager.shared.serverClient
        }
        
        // Otherwise, create a client for that specific server
        guard let credentials = KeychainHelper.shared.getSubsonicServer(id: serverId) else {
            return nil
        }
        
        return SubsonicServerClient(credentials: credentials)
    }
}
