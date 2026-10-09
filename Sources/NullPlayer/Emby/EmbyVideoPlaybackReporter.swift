import Foundation

/// Manages reporting video playback state and scrobbling to Emby
/// Handles periodic timeline updates and automatic scrobbling when videos finish
class EmbyVideoPlaybackReporter {

    // MARK: - Singleton

    static let shared = EmbyVideoPlaybackReporter()

    // MARK: - Configuration

    /// How often to send timeline updates (in seconds)
    private let timelineUpdateInterval: TimeInterval = 10.0

    /// Percentage of video that must be played to count as "watched" (0.0 - 1.0)
    /// Video uses 90% threshold (vs 50% for audio)
    private let scrobbleThreshold: Double = 0.90

    /// Minimum playback time (in seconds) before scrobbling is allowed
    /// Prevents accidental scrobbles from quick skips
    private let minimumPlayTime: TimeInterval = 60.0

    // MARK: - State

    /// The film being reported. A request captures it before its `Task`, so a film replaced while
    /// the request is in flight still reports as itself.
    private struct Playing: Equatable {
        let itemId: String
        /// Ties this play's start, progress and stop reports together on the server
        let playSessionId: String
        /// Routes requests to the film's own server
        let serverId: String
        let title: String
        let durationSeconds: TimeInterval
    }

    private var playing: Playing?

    /// Whether the current video has been scrobbled
    private var hasScrobbled: Bool = false

    /// Total time played for the current video (for scrobble threshold)
    private var totalPlayTime: TimeInterval = 0

    /// Timestamp when playback started/resumed (for tracking play time)
    private var playbackStartTime: Date?

    /// Whether playback is currently paused
    private var isPaused: Bool = false

    /// Timer for periodic timeline updates
    private var timelineTimer: Timer?

    /// Last reported position in seconds
    private var lastReportedPosition: TimeInterval = 0

    // MARK: - Initialization

    private init() {
        NSLog("EmbyVideoPlaybackReporter: Initialized")
    }

    // MARK: - Public API

    /// Called when a Emby film starts playing in the video window
    func videoTrackDidStart(itemId: String, title: String, durationSeconds: TimeInterval, isEpisode: Bool) {
        let serverId = EmbyManager.shared.currentServer?.id ?? ""
        NSLog("EmbyVideoPlaybackReporter: Video track started - %@ (id: %@)", title, itemId)

        startTracking(
            Playing(
                itemId: itemId,
                playSessionId: UUID().uuidString,
                serverId: serverId,
                title: title,
                durationSeconds: durationSeconds
            ),
            position: 0
        )
    }

    /// Called when playback is paused
    func videoDidPause(at position: TimeInterval) {
        guard playing != nil else { return }

        NSLog("EmbyVideoPlaybackReporter: Video paused at %.1fs", position)

        // Update total play time
        if let startTime = playbackStartTime {
            totalPlayTime += Date().timeIntervalSince(startTime)
        }
        playbackStartTime = nil
        isPaused = true

        // Report paused state
        reportProgress(position: position, paused: true)

        // Stop periodic updates while paused
        stopTimelineTimer()
    }

    /// Called when playback resumes
    func videoDidResume(at position: TimeInterval) {
        guard playing != nil else { return }

        NSLog("EmbyVideoPlaybackReporter: Video resumed at %.1fs", position)

        playbackStartTime = Date()
        isPaused = false

        // Report playing state
        reportProgress(position: position, paused: false)

        // Resume periodic updates
        startTimelineTimer()
    }

    /// Called when playback stops (manually or video ends)
    func videoDidStop(at position: TimeInterval, finished: Bool) {
        guard playing != nil else { return }

        NSLog("EmbyVideoPlaybackReporter: Video stopped at %.1fs (finished: %@)", position, finished ? "yes" : "no")

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
        reportStopped(position: position)

        // Clean up
        stopTracking()
    }

    /// Called periodically to update position
    func updatePosition(_ position: TimeInterval) {
        guard playing != nil, !isPaused else { return }

        // Check if we should scrobble
        if !hasScrobbled && shouldScrobbleAtPosition(position) {
            var currentPlayTime = totalPlayTime
            if let startTime = playbackStartTime {
                currentPlayTime += Date().timeIntervalSince(startTime)
            }

            if currentPlayTime >= minimumPlayTime {
                scrobble()
            }
        }

        lastReportedPosition = position
    }

    /// Force stop tracking (e.g., when closing video player)
    func stopTracking() {
        stopTimelineTimer()
        playing = nil
        hasScrobbled = false
        totalPlayTime = 0
        playbackStartTime = nil
        isPaused = false
        lastReportedPosition = 0
    }

    /// Check if currently tracking an Emby video
    var isTracking: Bool {
        playing != nil
    }

    // MARK: - Private Methods

    private func startTracking(_ film: Playing, position: TimeInterval) {
        // Stop any existing tracking
        stopTracking()

        // Set up tracking
        playing = film
        hasScrobbled = false
        totalPlayTime = 0
        playbackStartTime = Date()
        isPaused = false
        lastReportedPosition = position

        // Report playback start
        reportPlaybackStart(position: position)

        // Start periodic updates
        startTimelineTimer()
    }

    private func shouldScrobbleAtPosition(_ position: TimeInterval) -> Bool {
        guard let playing, playing.durationSeconds > 0 else { return false }
        let progress = position / playing.durationSeconds
        return progress >= scrobbleThreshold
    }

    private func reportPlaybackStart(position: TimeInterval) {
        guard let playing,
              let client = getClient() else { return }

        Task {
            do {
                try await client.reportPlaybackStart(itemId: playing.itemId, playSessionId: playing.playSessionId)
                NSLog("EmbyVideoPlaybackReporter: Reported playback start for %@", playing.title)
            } catch {
                NSLog("EmbyVideoPlaybackReporter: Failed to report start: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }

    private func reportProgress(position: TimeInterval, paused: Bool) {
        guard let playing,
              let client = getClient() else { return }

        let positionTicks = Int64(position * 10_000_000)

        Task {
            do {
                try await client.reportPlaybackProgress(itemId: playing.itemId, playSessionId: playing.playSessionId, positionTicks: positionTicks, isPaused: paused)
            } catch {
                // Silently ignore progress report failures
            }
        }
    }

    private func reportStopped(position: TimeInterval) {
        guard let playing,
              let client = getClient() else { return }

        let positionTicks = Int64(position * 10_000_000)

        Task {
            do {
                try await client.reportPlaybackStopped(itemId: playing.itemId, playSessionId: playing.playSessionId, positionTicks: positionTicks)
                NSLog("EmbyVideoPlaybackReporter: Reported stopped for %@", playing.title)
            } catch {
                NSLog("EmbyVideoPlaybackReporter: Failed to report stopped: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }

    private func scrobble() {
        guard !hasScrobbled, let playing else { return }
        hasScrobbled = true

        guard let client = getClient() else { return }

        Task { @MainActor in
            do {
                try await client.scrobble(itemId: playing.itemId)
                NSLog("EmbyVideoPlaybackReporter: Scrobbled video (id: %@, title: %@)",
                      playing.itemId, playing.title)
            } catch {
                NSLog("EmbyVideoPlaybackReporter: Failed to scrobble: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
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
              !isPaused,
              let client = getClient() else { return }

        let positionTicks = Int64(lastReportedPosition * 10_000_000)

        Task {
            do {
                try await client.reportPlaybackProgress(itemId: playing.itemId, playSessionId: playing.playSessionId, positionTicks: positionTicks)
            } catch {
                NSLog("EmbyVideoPlaybackReporter: Timeline update failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }

    /// Get the client for the current server
    private func getClient() -> EmbyServerClient? {
        guard let serverId = playing?.serverId else { return nil }

        if EmbyManager.shared.currentServer?.id == serverId {
            return EmbyManager.shared.serverClient
        }

        guard let credentials = KeychainHelper.shared.getEmbyServer(id: serverId) else {
            return nil
        }

        return EmbyServerClient(credentials: credentials)
    }
}
