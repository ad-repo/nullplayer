import Foundation

/// Reports playback state to Emby servers for scrobbling and "now playing"
class EmbyPlaybackReporter {

    // MARK: - Singleton

    static let shared = EmbyPlaybackReporter()

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

    /// Throttle interval for progress reports (matches Emby's timeline update interval)
    private let progressReportInterval: TimeInterval = 10.0
    private var lastProgressReportDate: Date?

    /// Last known playback position, updated each updatePlayback tick
    private var lastKnownPosition: TimeInterval = 0

    // MARK: - Initialization

    private init() {}

    // MARK: - Playback Reporting

    /// Called when a new track starts playing
    func trackStarted(trackId: String, serverId: String?, duration: TimeInterval) {
        let sid = serverId ?? ""
        // Reset state for new track
        currentTrackId = trackId
        currentServerId = sid
        trackStartTime = Date()
        trackDuration = duration
        hasReportedNowPlaying = false
        hasScrobbled = false
        lastProgressReportDate = nil
        lastKnownPosition = 0

        NSLog("EmbyPlaybackReporter: Track started - ID: %@, duration: %.0fs", trackId, duration)

        // Report "now playing" immediately
        reportNowPlaying()
    }

    /// Called when playback position changes (debounced)
    func updatePlayback(trackId: String, serverId: String?, position: TimeInterval, duration: TimeInterval) {
        let sid = serverId ?? ""
        // Only process if this is the current track
        guard trackId == currentTrackId, sid == currentServerId else {
            // New track detected, start fresh
            trackStarted(trackId: trackId, serverId: serverId, duration: duration)
            return
        }

        // Track position for pause/stop reporting
        lastKnownPosition = position

        // Throttle progress reports to every 10 seconds
        if lastProgressReportDate == nil ||
           Date().timeIntervalSince(lastProgressReportDate!) >= progressReportInterval {
            lastProgressReportDate = Date()
            reportProgress(position: position)
        }

        // Check if we should scrobble
        checkForScrobble(position: position)
    }

    /// Called when playback stops
    func trackStopped() {
        // Report stopped to server
        reportStopped()

        // Clear state
        currentTrackId = nil
        currentServerId = nil
        trackStartTime = nil
        trackDuration = 0
        hasReportedNowPlaying = false
        hasScrobbled = false
        lastProgressReportDate = nil
        lastKnownPosition = 0

        NSLog("EmbyPlaybackReporter: Track stopped")
    }

    /// Called when track is paused
    func trackPaused() {
        // Report pause to Emby
        if let trackId = currentTrackId,
           let serverId = currentServerId,
           let client = getClient(for: serverId) {
            Task {
                do {
                    // Report paused state (positionTicks with isPaused=true)
                    let ticks = Int64(self.lastKnownPosition * 10_000_000)
                    try await client.reportPlaybackProgress(itemId: trackId, positionTicks: ticks, isPaused: true)
                } catch {
                    NSLog("EmbyPlaybackReporter: Failed to report pause: %@", error.localizedDescription)
                }
            }
        }
        NSLog("EmbyPlaybackReporter: Track paused")
    }

    /// Called when track resumes from pause
    func trackResumed() {
        // Reset throttle so the next updatePlayback tick reports position immediately
        lastProgressReportDate = nil
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
                try await client.reportPlaybackStart(itemId: trackId)
                NSLog("EmbyPlaybackReporter: Reported 'now playing' for track %@", trackId)
            } catch {
                NSLog("EmbyPlaybackReporter: Failed to report 'now playing': %@", error.localizedDescription)
            }
        }
    }

    /// Report playback progress to the server
    private func reportProgress(position: TimeInterval) {
        guard let trackId = currentTrackId,
              let serverId = currentServerId,
              let client = getClient(for: serverId) else {
            return
        }

        let positionTicks = Int64(position * 10_000_000)

        Task {
            do {
                try await client.reportPlaybackProgress(itemId: trackId, positionTicks: positionTicks)
            } catch {
                // Silently ignore progress report failures
            }
        }
    }

    /// Report playback stopped to the server
    private func reportStopped() {
        guard let trackId = currentTrackId,
              let serverId = currentServerId,
              let client = getClient(for: serverId) else {
            return
        }

        let positionTicks = Int64(lastKnownPosition * 10_000_000)

        Task {
            do {
                try await client.reportPlaybackStopped(itemId: trackId, positionTicks: positionTicks)
            } catch {
                NSLog("EmbyPlaybackReporter: Failed to report stopped: %@", error.localizedDescription)
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
                try await client.scrobble(itemId: trackId)
                NSLog("EmbyPlaybackReporter: Scrobbled track %@", trackId)
            } catch {
                NSLog("EmbyPlaybackReporter: Failed to scrobble: %@", error.localizedDescription)
                // Reset flag so we can try again
                hasScrobbled = false
            }
        }
    }

    /// Get the client for a specific server
    private func getClient(for serverId: String) -> EmbyServerClient? {
        // Use the current server's client if it matches
        if EmbyManager.shared.currentServer?.id == serverId {
            return EmbyManager.shared.serverClient
        }

        // Otherwise, create a client for that specific server
        guard let credentials = KeychainHelper.shared.getEmbyServer(id: serverId) else {
            return nil
        }

        return EmbyServerClient(credentials: credentials)
    }
}
