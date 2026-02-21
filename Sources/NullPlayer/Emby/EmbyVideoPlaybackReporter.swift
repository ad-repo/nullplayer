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

    /// Type of video content
    enum VideoType: String {
        case movie = "movie"
        case episode = "episode"
    }

    /// Emby item ID of the current video
    private var currentItemId: String?

    /// Server ID for routing to the correct client
    private var currentServerId: String?

    /// Type of video being played
    private var currentVideoType: VideoType = .movie

    /// Duration of the current video in seconds
    private var currentDurationSeconds: TimeInterval = 0

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

    /// Title of current video (for logging)
    private var currentTitle: String?

    // MARK: - Initialization

    private init() {
        NSLog("EmbyVideoPlaybackReporter: Initialized")
    }

    // MARK: - Public API

    /// Called when an Emby movie starts playing
    func movieDidStart(_ movie: EmbyMovie, at position: TimeInterval = 0) {
        let serverId = EmbyManager.shared.currentServer?.id ?? ""
        NSLog("EmbyVideoPlaybackReporter: Movie started - %@ (id: %@)", movie.title, movie.id)

        startTracking(
            itemId: movie.id,
            serverId: serverId,
            title: movie.title,
            durationSeconds: TimeInterval(movie.duration ?? 0),
            videoType: .movie,
            position: position
        )
    }

    /// Called when an Emby episode starts playing
    func episodeDidStart(_ episode: EmbyEpisode, at position: TimeInterval = 0) {
        let serverId = EmbyManager.shared.currentServer?.id ?? ""
        let title: String
        if let showName = episode.seriesName {
            title = "\(showName) - \(episode.episodeIdentifier) - \(episode.title)"
        } else {
            title = episode.title
        }
        NSLog("EmbyVideoPlaybackReporter: Episode started - %@ (id: %@)", title, episode.id)

        startTracking(
            itemId: episode.id,
            serverId: serverId,
            title: title,
            durationSeconds: TimeInterval(episode.duration ?? 0),
            videoType: .episode,
            position: position
        )
    }

    /// Called when playback is paused
    func videoDidPause(at position: TimeInterval) {
        guard currentItemId != nil else { return }

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
        guard currentItemId != nil else { return }

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
        guard let itemId = currentItemId else { return }

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
                scrobble(itemId: itemId)
            }
        }

        // Report stopped state
        reportStopped(position: position)

        // Clean up
        stopTracking()
    }

    /// Called periodically to update position
    func updatePosition(_ position: TimeInterval) {
        guard currentItemId != nil, !isPaused else { return }

        // Check if we should scrobble
        if !hasScrobbled && shouldScrobbleAtPosition(position) {
            var currentPlayTime = totalPlayTime
            if let startTime = playbackStartTime {
                currentPlayTime += Date().timeIntervalSince(startTime)
            }

            if currentPlayTime >= minimumPlayTime {
                if let itemId = currentItemId {
                    scrobble(itemId: itemId)
                }
            }
        }

        lastReportedPosition = position
    }

    /// Force stop tracking (e.g., when closing video player)
    func stopTracking() {
        stopTimelineTimer()
        currentItemId = nil
        currentServerId = nil
        currentTitle = nil
        currentDurationSeconds = 0
        hasScrobbled = false
        totalPlayTime = 0
        playbackStartTime = nil
        isPaused = false
        lastReportedPosition = 0
    }

    /// Check if currently tracking an Emby video
    var isTracking: Bool {
        currentItemId != nil
    }

    // MARK: - Private Methods

    private func startTracking(
        itemId: String,
        serverId: String,
        title: String,
        durationSeconds: TimeInterval,
        videoType: VideoType,
        position: TimeInterval
    ) {
        // Stop any existing tracking
        stopTracking()

        // Set up tracking
        currentItemId = itemId
        currentServerId = serverId
        currentTitle = title
        currentDurationSeconds = durationSeconds
        currentVideoType = videoType
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
        guard currentDurationSeconds > 0 else { return false }
        let progress = position / currentDurationSeconds
        return progress >= scrobbleThreshold
    }

    private func reportPlaybackStart(position: TimeInterval) {
        guard let itemId = currentItemId,
              let client = getClient() else { return }

        Task {
            do {
                try await client.reportPlaybackStart(itemId: itemId)
                NSLog("EmbyVideoPlaybackReporter: Reported playback start for %@", self.currentTitle ?? "unknown")
            } catch {
                NSLog("EmbyVideoPlaybackReporter: Failed to report start: %@", error.localizedDescription)
            }
        }
    }

    private func reportProgress(position: TimeInterval, paused: Bool) {
        guard let itemId = currentItemId,
              let client = getClient() else { return }

        let positionTicks = Int64(position * 10_000_000)

        Task {
            do {
                try await client.reportPlaybackProgress(itemId: itemId, positionTicks: positionTicks, isPaused: paused)
            } catch {
                // Silently ignore progress report failures
            }
        }
    }

    private func reportStopped(position: TimeInterval) {
        guard let itemId = currentItemId,
              let client = getClient() else { return }

        let positionTicks = Int64(position * 10_000_000)

        Task {
            do {
                try await client.reportPlaybackStopped(itemId: itemId, positionTicks: positionTicks)
                NSLog("EmbyVideoPlaybackReporter: Reported stopped for %@", self.currentTitle ?? "unknown")
            } catch {
                NSLog("EmbyVideoPlaybackReporter: Failed to report stopped: %@", error.localizedDescription)
            }
        }
    }

    private func scrobble(itemId: String) {
        guard !hasScrobbled else { return }
        hasScrobbled = true

        guard let client = getClient() else { return }

        Task {
            do {
                try await client.scrobble(itemId: itemId)
                NSLog("EmbyVideoPlaybackReporter: Scrobbled video (id: %@, title: %@)",
                      itemId, self.currentTitle ?? "unknown")
            } catch {
                NSLog("EmbyVideoPlaybackReporter: Failed to scrobble: %@", error.localizedDescription)
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
        guard let itemId = currentItemId,
              !isPaused,
              let client = getClient() else { return }

        let positionTicks = Int64(lastReportedPosition * 10_000_000)

        Task {
            do {
                try await client.reportPlaybackProgress(itemId: itemId, positionTicks: positionTicks)
            } catch {
                NSLog("EmbyVideoPlaybackReporter: Timeline update failed: %@", error.localizedDescription)
            }
        }
    }

    /// Get the client for the current server
    private func getClient() -> EmbyServerClient? {
        guard let serverId = currentServerId else { return nil }

        if EmbyManager.shared.currentServer?.id == serverId {
            return EmbyManager.shared.serverClient
        }

        guard let credentials = KeychainHelper.shared.getEmbyServer(id: serverId) else {
            return nil
        }

        return EmbyServerClient(credentials: credentials)
    }
}
