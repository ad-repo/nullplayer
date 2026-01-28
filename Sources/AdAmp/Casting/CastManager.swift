import Foundation
import AppKit

/// Unified manager for all casting functionality
/// Coordinates Chromecast, Sonos, and DLNA device discovery and playback
class CastManager {
    
    // MARK: - Singleton
    
    static let shared = CastManager()
    
    // MARK: - Notifications
    
    static let devicesDidChangeNotification = Notification.Name("CastDevicesDidChange")
    static let sessionDidChangeNotification = Notification.Name("CastSessionDidChange")
    static let playbackStateDidChangeNotification = Notification.Name("CastPlaybackStateDidChange")
    static let trackChangeLoadingNotification = Notification.Name("CastTrackChangeLoading")
    static let errorNotification = Notification.Name("CastError")
    
    // MARK: - Sub-managers
    
    private let chromecastManager = ChromecastManager.shared
    private let upnpManager = UPnPManager.shared
    
    // MARK: - Properties
    
    /// Rooms selected for Sonos casting (UDNs) - used before casting starts
    var selectedSonosRooms: Set<String> = []
    
    /// All discovered cast devices, grouped by type
    var discoveredDevices: [CastDevice] {
        var all: [CastDevice] = []
        all.append(contentsOf: chromecastManager.devices)
        all.append(contentsOf: upnpManager.devices)
        return all
    }
    
    /// Chromecast devices only
    var chromecastDevices: [CastDevice] {
        chromecastManager.devices
    }
    
    /// Sonos devices only
    var sonosDevices: [CastDevice] {
        upnpManager.devices.filter { $0.type == .sonos }
    }
    
    /// DLNA TV devices only
    var dlnaTVDevices: [CastDevice] {
        upnpManager.devices.filter { $0.type == .dlnaTV }
    }
    
    // MARK: - Sonos Grouping
    
    /// All individual Sonos zones (for grouping UI)
    var allSonosZones: [UPnPManager.SonosZoneSummary] {
        upnpManager.allSonosZones
    }
    
    /// Current Sonos group topology (for grouping UI)
    var sonosGroups: [UPnPManager.SonosGroupSummary] {
        upnpManager.sonosGroups
    }
    
    /// Get zone name by UDN
    func sonosZoneName(for udn: String) -> String? {
        upnpManager.zoneName(for: udn)
    }
    
    /// Unique Sonos rooms for simplified grouping UI
    var sonosRooms: [UPnPManager.SonosRoomSummary] {
        upnpManager.sonosRooms
    }
    
    /// Join a Sonos speaker to a group
    /// - Parameters:
    ///   - zoneUDN: The UDN of the zone to join
    ///   - coordinatorUDN: The UDN of the group coordinator
    func joinSonosToGroup(zoneUDN: String, coordinatorUDN: String) async throws {
        try await upnpManager.joinSonosZone(zoneUDN, toCoordinator: coordinatorUDN)
    }
    
    /// Make a Sonos speaker standalone (leave its group)
    /// - Parameter zoneUDN: The UDN of the zone to make standalone
    func unjoinSonos(zoneUDN: String) async throws {
        try await upnpManager.unjoinSonosZone(zoneUDN)
    }
    
    /// Refresh Sonos group topology
    func refreshSonosGroups() async {
        await upnpManager.refreshSonosGroupTopology()
    }
    
    /// Current active cast session (if any)
    var activeSession: CastSession? {
        if let session = chromecastManager.activeSession, session.state != .idle {
            return session
        }
        if let session = upnpManager.activeSession, session.state != .idle {
            return session
        }
        return nil
    }
    
    /// Whether casting is currently active
    var isCasting: Bool {
        activeSession?.state == .casting
    }
    
    /// Whether video casting is currently active (as opposed to audio casting)
    private(set) var isVideoCasting: Bool = false
    
    /// Title of the video being cast (for main window display when casting from menu)
    private(set) var videoCastTitle: String?
    
    /// Duration of the video being cast (for seek calculations)
    private(set) var videoCastDuration: TimeInterval = 0
    
    /// Video cast position tracking
    private var videoCastStartPosition: TimeInterval = 0
    private var videoCastStartDate: Date?
    
    /// Whether we've received the first status update from Chromecast (prevents UI flash before sync)
    private var videoCastHasReceivedStatus: Bool = false
    
    /// Current video cast playback time (interpolated)
    var videoCastCurrentTime: TimeInterval {
        guard isVideoCasting else { return 0 }
        if let startDate = videoCastStartDate {
            let elapsed = Date().timeIntervalSince(startDate)
            let current = videoCastStartPosition + elapsed
            // Only clamp if we have a known duration (prevents returning 0 for unknown durations)
            if videoCastDuration > 0 {
                return min(current, videoCastDuration)
            }
            return current
        }
        return videoCastStartPosition
    }
    
    /// Whether video cast is playing (not paused)
    private(set) var isVideoCastPlaying: Bool = false
    
    /// Timer for updating main window with video cast progress
    private var videoCastUpdateTimer: Timer?
    
    /// Start the video cast update timer (updates main window with progress)
    /// Note: Timer only updates UI after first status received from Chromecast
    private func startVideoCastUpdateTimer() {
        videoCastUpdateTimer?.invalidate()
        videoCastUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isVideoCasting else { return }
            // Don't update UI until we've received first status from Chromecast
            // This prevents showing stale/incorrect time before sync
            guard self.videoCastHasReceivedStatus else { return }
            let current = self.videoCastCurrentTime
            let duration = self.videoCastDuration
            WindowManager.shared.videoDidUpdateTime(current: current, duration: duration)
        }
        // Don't fire immediately - wait for first Chromecast status update
    }
    
    /// Stop the video cast update timer
    private func stopVideoCastUpdateTimer() {
        videoCastUpdateTimer?.invalidate()
        videoCastUpdateTimer = nil
    }
    
    /// Discovery state
    private(set) var isDiscovering: Bool = false
    
    /// Discovery refresh timer
    private var discoveryRefreshTimer: Timer?
    
    /// Generation counter for track casting - incremented on each castNewTrack call
    /// Used to detect and discard stale operations when user rapidly changes tracks
    /// Access must be synchronized - use MainActor for safety
    @MainActor private var castTrackGeneration: Int = 0
    
    /// Whether a track cast operation is in progress (for UI loading state)
    /// This is used by AudioEngine to block rapid clicks during local file casting
    @MainActor var isCastingTrackChange: Bool = false
    
    /// The track currently being cast (for UI display during loading)
    @MainActor var pendingCastTrack: Track?
    
    /// Check if a local file cast is in progress (synchronous, must be called from main thread)
    /// Used by AudioEngine to block rapid clicks during local file casting
    func isLocalFileCastInProgress() -> Bool {
        // This must be called from main thread
        assert(Thread.isMainThread, "isLocalFileCastInProgress must be called from main thread")
        return MainActor.assumeIsolated { isCastingTrackChange }
    }
    
    /// Timestamp of last refresh (for UI feedback)
    private(set) var lastRefreshTime: Date?
    
    /// Whether a refresh is currently in progress
    private(set) var isRefreshing: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        // Start discovery automatically
        startDiscovery()
        
        // Refresh discovery periodically (every 60 seconds)
        discoveryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
        
        // Subscribe to Chromecast status updates for position syncing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChromecastMediaStatusUpdate),
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil
        )
    }
    
    deinit {
        discoveryRefreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Chromecast Status Updates
    
    /// Handle media status updates from Chromecast for position syncing
    @objc private func handleChromecastMediaStatusUpdate(_ notification: Notification) {
        guard let status = notification.userInfo?["status"] as? CastMediaStatus else { return }
        
        // Dispatch to main thread for thread safety - NotificationCenter may deliver off main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Only process if we're actively casting
            guard self.isCasting || self.isVideoCasting else { return }
            
            let isPlaying = status.playerState == .playing
            let isBuffering = status.playerState == .buffering
            
            // Update video cast tracking if video casting
            if self.isVideoCasting {
                // Mark that we've received status from Chromecast (enables UI updates)
                let isFirstStatus = !self.videoCastHasReceivedStatus
                self.videoCastHasReceivedStatus = true
                
                // Sync position from Chromecast
                self.videoCastStartPosition = status.currentTime
                
                if isBuffering {
                    // Pause interpolation during buffering
                    self.videoCastStartDate = nil
                    self.isVideoCastPlaying = false
                } else if isPlaying {
                    self.videoCastStartDate = Date()
                    self.isVideoCastPlaying = true
                } else {
                    // Paused or idle
                    self.videoCastStartDate = nil
                    self.isVideoCastPlaying = false
                }
                
                // Update duration if provided
                if let duration = status.duration, duration > 0 {
                    self.videoCastDuration = duration
                }
                
                // On first status, immediately update UI with correct position
                if isFirstStatus {
                    WindowManager.shared.videoDidUpdateTime(current: self.videoCastCurrentTime, duration: self.videoCastDuration)
                }
            } else if self.isCasting {
                // Audio casting - forward position sync to AudioEngine
                WindowManager.shared.audioEngine.updateCastPosition(
                    currentTime: status.currentTime,
                    isPlaying: isPlaying,
                    isBuffering: isBuffering
                )
            }
        }
    }
    
    // MARK: - Discovery
    
    /// Start discovering cast devices on the network
    func startDiscovery() {
        guard !isDiscovering else { return }
        
        NSLog("CastManager: Starting device discovery...")
        isDiscovering = true
        
        chromecastManager.startDiscovery()
        upnpManager.startDiscovery()
    }
    
    /// Stop discovering devices
    func stopDiscovery() {
        NSLog("CastManager: Stopping device discovery")
        isDiscovering = false
        
        chromecastManager.stopDiscovery()
        upnpManager.stopDiscovery()
    }
    
    /// Refresh device list (restart discovery)
    /// Keeps existing devices visible - doesn't clear until new devices are found
    func refreshDevices() {
        NSLog("CastManager: Refreshing devices...")
        
        isRefreshing = true
        lastRefreshTime = Date()
        
        // Stop discovery (closes sockets/browsers)
        // DON'T clear existing devices - keep them visible throughout refresh
        chromecastManager.stopDiscovery()
        upnpManager.stopDiscovery()
        isDiscovering = false
        
        // Reset only the internal discovery state (pending descriptions, etc.)
        // but keep the visible device lists intact
        upnpManager.resetDiscoveryState()
        
        // Wait 2s for clean socket shutdown before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            NSLog("CastManager: Restarting discovery after refresh delay")
            
            self.isDiscovering = true
            self.chromecastManager.startDiscovery()
            self.upnpManager.startDiscovery()
        }
        
        // Post-refresh discovery boosts
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self, self.isDiscovering else { return }
            NSLog("CastManager: Sending discovery boost at +10s")
            self.upnpManager.sendDiscoveryBoost()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            guard let self = self else { return }
            // Always clear refreshing flag, regardless of discovery state
            self.isRefreshing = false
            
            if self.isDiscovering {
                NSLog("CastManager: Sending discovery boost at +15s")
                self.upnpManager.sendDiscoveryBoost()
            }
            NSLog("CastManager: Refresh complete")
        }
    }
    
    /// Get the number of seconds since last refresh
    var secondsSinceLastRefresh: Int? {
        guard let lastRefresh = lastRefreshTime else { return nil }
        return Int(Date().timeIntervalSince(lastRefresh))
    }
    
    // MARK: - Casting
    
    /// Cast media to a device
    /// - Parameters:
    ///   - device: The target cast device
    ///   - url: The media URL to cast
    ///   - metadata: Metadata about the media
    ///   - startPosition: Optional position to start from (for resuming playback)
    func cast(to device: CastDevice, url: URL, metadata: CastMetadata, startPosition: TimeInterval = 0) async throws {
        NSLog("CastManager: Casting to %@ (%@), start position: %.1f", device.name, device.type.displayName, startPosition)
        
        // Disconnect from any existing session
        if activeSession != nil {
            await stopCasting()
        }
        
        // Pause local playback before casting
        await MainActor.run {
            pauseLocalPlayback()
        }
        
        // Connect and cast based on device type
        switch device.type {
        case .chromecast:
            NSLog("CastManager: Connecting to Chromecast...")
            do {
                try await chromecastManager.connect(to: device)
                NSLog("CastManager: Connected to Chromecast, now casting...")
                try await chromecastManager.cast(url: url, metadata: metadata)
                NSLog("CastManager: Cast started successfully")
            } catch {
                NSLog("CastManager: Chromecast error: %@", error.localizedDescription)
                throw error
            }
            
        case .sonos, .dlnaTV:
            try await upnpManager.connect(to: device)
            try await upnpManager.cast(url: url, metadata: metadata)
        }
        
        // If we have a start position, seek to it after playback starts
        if startPosition > 1.0 {
            // Small delay to let playback start before seeking
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            try? await seek(to: startPosition)
            NSLog("CastManager: Seeked cast device to %.1f seconds", startPosition)
        }
        
        // Track video casting state
        // Note: Don't start the timer immediately - wait for Chromecast to report PLAYING state
        // This prevents clock sync issues when buffering (especially for 4K on slow networks)
        let isVideo = metadata.mediaType == .video
        await MainActor.run {
            if isVideo {
                self.isVideoCasting = true
                self.videoCastTitle = metadata.title
                self.videoCastDuration = metadata.duration ?? 0
                self.videoCastStartPosition = startPosition
                
                if device.type == .chromecast {
                    // Chromecast: Wait for PLAYING status update before updating UI
                    // This prevents clock sync issues when buffering (especially for 4K on slow networks)
                    self.videoCastStartDate = nil
                    self.isVideoCastPlaying = false
                    self.videoCastHasReceivedStatus = false
                } else {
                    // DLNA/UPnP: No status updates, start timer immediately
                    self.videoCastStartDate = Date()
                    self.isVideoCastPlaying = true
                    self.videoCastHasReceivedStatus = true
                }
                self.startVideoCastUpdateTimer()
                
                // Update main window with video title (for casts from library browser menu)
                WindowManager.shared.mainWindowController?.updateVideoTrackInfo(title: metadata.title)
                
                NSLog("CastManager: Video cast state initialized - title='%@', duration=%.1f, startPosition=%.1f, hasReceivedStatus=%d", metadata.title, self.videoCastDuration, startPosition, self.videoCastHasReceivedStatus ? 1 : 0)
            } else {
                // Audio casting - use different tracking based on device type
                if device.type == .chromecast {
                    // Chromecast provides status updates - wait for PLAYING status to start timer
                    // This prevents clock sync issues when buffering on slow networks
                    WindowManager.shared.audioEngine.initializeCastPlayback(from: startPosition)
                } else {
                    // Sonos/DLNA don't provide status updates - start timer immediately
                    WindowManager.shared.audioEngine.startCastPlayback(from: startPosition)
                }
            }
            NotificationCenter.default.post(name: Self.sessionDidChangeNotification, object: nil)
            NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: nil)
        }
    }
    
    /// Pause local audio playback (called when casting starts)
    private func pauseLocalPlayback() {
        let engine = WindowManager.shared.audioEngine
        if engine.state == .playing && !engine.isCastingActive {
            // Directly pause local playback without triggering cast commands
            engine.pauseLocalOnly()
        }
    }
    
    /// Cast the currently playing track to a device
    func castCurrentTrack(to device: CastDevice) async throws {
        let engine = WindowManager.shared.audioEngine
        guard let track = engine.currentTrack else {
            throw CastError.noTrackPlaying
        }
        
        // Capture current position before casting
        let currentPosition = await MainActor.run { engine.currentTime }
        
        try await castTrack(track, to: device, startPosition: currentPosition)
    }
    
    /// Cast a specific track to a device
    func castTrack(_ track: Track, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        // Get castable URL (with token for Plex content)
        let castURL: URL
        if track.url.scheme == "http" || track.url.scheme == "https" {
            // For Plex/remote URLs, ensure token is included
            if let tokenizedURL = PlexManager.shared.getCastableStreamURL(for: track.url) {
                castURL = tokenizedURL
            } else {
                castURL = track.url
            }
        } else {
            // Local file - register with HTTP server
            // Ensure server is running
            if !LocalMediaServer.shared.isRunning {
                do {
                    try await LocalMediaServer.shared.start()
                } catch {
                    throw CastError.localServerError("Could not start local media server: \(error.localizedDescription)")
                }
            }
            
            guard let serverURL = LocalMediaServer.shared.registerFile(track.url) else {
                throw CastError.localServerError("Could not register file with local media server")
            }
            castURL = serverURL
        }
        
        // Get artwork URL if available
        var artworkURL: URL?
        if let plexTrack = findPlexTrack(matching: track) {
            artworkURL = PlexManager.shared.artworkURL(thumb: plexTrack.thumb)
        }
        
        let metadata = CastMetadata(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkURL: artworkURL,
            duration: track.duration,
            contentType: "audio/mpeg"
        )
        
        try await cast(to: device, url: castURL, metadata: metadata, startPosition: startPosition)
    }
    
    /// Cast a new track to the already connected device (for next/previous)
    func castNewTrack(_ track: Track) async throws {
        guard let session = activeSession else {
            throw CastError.sessionNotActive
        }
        
        // Check if this is a local file (needs loading state due to async registration)
        let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
        
        // Increment generation to invalidate any in-flight cast operations
        // This prevents race conditions when user rapidly clicks through tracks
        // Must be done on MainActor for thread safety
        let myGeneration = await MainActor.run {
            castTrackGeneration += 1
            
            // Set loading state for local files only (they have async registration)
            if isLocalFile {
                isCastingTrackChange = true
                pendingCastTrack = track
                NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": true, "track": track])
            }
            
            return castTrackGeneration
        }
        
        NSLog("CastManager: castNewTrack '%@' starting (generation %d, local=%d)", track.title, myGeneration, isLocalFile ? 1 : 0)
        
        // Helper to clear loading state and notify UI
        // Always posts notification to ensure loading overlay is cleared even for non-local failures
        @MainActor func clearLoadingState() {
            if myGeneration == castTrackGeneration {
                let wasLoading = isCastingTrackChange
                isCastingTrackChange = false
                pendingCastTrack = nil
                // Post notification so MainWindowView removes loading overlay
                // Always post if we were loading, to handle edge cases where non-local fails after local
                if wasLoading {
                    NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": false])
                }
            }
        }
        
        // Get castable URL (with token for Plex content)
        let castURL: URL
        if track.url.scheme == "http" || track.url.scheme == "https" {
            if let tokenizedURL = PlexManager.shared.getCastableStreamURL(for: track.url) {
                castURL = tokenizedURL
            } else {
                castURL = track.url
            }
        } else {
            // Local file - register with HTTP server
            guard let serverURL = LocalMediaServer.shared.registerFile(track.url) else {
                await clearLoadingState()
                throw CastError.localServerError("Could not register file with local media server")
            }
            castURL = serverURL
        }
        
        // Check if we've been superseded by a newer track change
        let currentGen1 = await MainActor.run { castTrackGeneration }
        guard myGeneration == currentGen1 else {
            NSLog("CastManager: castNewTrack '%@' abandoned - superseded by generation %d", track.title, currentGen1)
            // Clear loading state - the newer operation may be a streaming file that doesn't manage loading overlay
            await clearLoadingState()
            return
        }
        
        // Get artwork URL if available
        var artworkURL: URL?
        if let plexTrack = findPlexTrack(matching: track) {
            artworkURL = PlexManager.shared.artworkURL(thumb: plexTrack.thumb)
        }
        
        let metadata = CastMetadata(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkURL: artworkURL,
            duration: track.duration,
            contentType: "audio/mpeg"
        )
        
        NSLog("CastManager: Casting new track '%@' to %@ (generation %d)", track.title, session.device.name, myGeneration)
        
        // Cast to the existing connected device
        // Wrap in do/catch to ensure loading state is cleared on failure
        do {
            switch session.device.type {
            case .chromecast:
                try await chromecastManager.cast(url: castURL, metadata: metadata)
                
            case .sonos, .dlnaTV:
                try await upnpManager.cast(url: castURL, metadata: metadata)
            }
        } catch {
            NSLog("CastManager: castNewTrack '%@' failed: %@", track.title, error.localizedDescription)
            await clearLoadingState()
            throw error
        }
        
        // Check again after the network call - another track change may have started
        let currentGen2 = await MainActor.run { castTrackGeneration }
        guard myGeneration == currentGen2 else {
            NSLog("CastManager: castNewTrack '%@' post-cast abandoned - superseded by generation %d", track.title, currentGen2)
            // Clear loading state - the newer operation may be a streaming file that doesn't manage loading overlay
            await clearLoadingState()
            return
        }
        
        // Reset cast playback time tracking from position 0 for new track
        await MainActor.run {
            // Final check on main thread before updating UI
            guard myGeneration == self.castTrackGeneration else {
                NSLog("CastManager: castNewTrack '%@' UI update abandoned - superseded", track.title)
                // Clear loading state even when superseded - the newer operation may not be a local file
                // and won't clear the loading overlay we set
                if isLocalFile {
                    isCastingTrackChange = false
                    pendingCastTrack = nil
                    NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": false])
                }
                return
            }
            
            // Clear loading state - cast completed successfully
            isCastingTrackChange = false
            pendingCastTrack = nil
            NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": false])
            
            if session.device.type == .chromecast {
                // Chromecast provides status updates - wait for PLAYING status to start timer
                WindowManager.shared.audioEngine.initializeCastPlayback(from: 0)
            } else {
                // Sonos/DLNA don't provide status updates - start timer immediately
                WindowManager.shared.audioEngine.startCastPlayback(from: 0)
            }
            NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: nil)
        }
    }
    
    // MARK: - Video Casting
    
    /// Get video-capable cast devices (excludes Sonos which is audio-only)
    var videoCapableDevices: [CastDevice] {
        discoveredDevices.filter { $0.supportsVideo }
    }
    
    /// Cast a Plex movie to a video-capable device
    /// - Parameters:
    ///   - movie: The PlexMovie to cast
    ///   - device: Target cast device (must support video)
    ///   - startPosition: Optional position to resume from (seconds)
    func castPlexMovie(_ movie: PlexMovie, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        guard device.supportsVideo else {
            throw CastError.unsupportedDevice
        }
        
        guard let streamURL = PlexManager.shared.streamURL(for: movie) else {
            throw CastError.invalidURL
        }
        
        // Get castable URL with token embedded
        let castURL: URL
        if let tokenizedURL = PlexManager.shared.getCastableStreamURL(for: streamURL) {
            castURL = tokenizedURL
        } else {
            castURL = streamURL
        }
        
        // Get artwork URL
        let artworkURL = PlexManager.shared.artworkURL(thumb: movie.thumb)
        
        // Determine content type (Plex usually serves video/mp4)
        let contentType = "video/mp4"
        
        // Build resolution string if available
        var resolution: String?
        if let media = movie.primaryMedia, let width = media.width, let height = media.height {
            resolution = "\(width)x\(height)"
        }
        
        let metadata = CastMetadata(
            title: movie.title,
            artist: nil,
            album: nil,
            artworkURL: artworkURL,
            duration: movie.duration.map { Double($0) / 1000.0 },
            contentType: contentType,
            mediaType: .video,
            resolution: resolution,
            year: movie.year,
            summary: movie.summary
        )
        
        NSLog("CastManager: Casting Plex movie '%@' to %@ (type: %@)", movie.title, device.name, device.type.rawValue)
        NSLog("CastManager: Cast URL: %@", redactedURL(castURL))
        
        do {
            try await cast(to: device, url: castURL, metadata: metadata, startPosition: startPosition)
            NSLog("CastManager: Cast completed successfully")
        } catch {
            NSLog("CastManager: Cast failed with error: %@", error.localizedDescription)
            throw error
        }
    }
    
    /// Cast a Plex episode to a video-capable device
    /// - Parameters:
    ///   - episode: The PlexEpisode to cast
    ///   - device: Target cast device (must support video)
    ///   - startPosition: Optional position to resume from (seconds)
    func castPlexEpisode(_ episode: PlexEpisode, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        guard device.supportsVideo else {
            throw CastError.unsupportedDevice
        }
        
        guard let streamURL = PlexManager.shared.streamURL(for: episode) else {
            throw CastError.invalidURL
        }
        
        // Get castable URL with token embedded
        let castURL: URL
        if let tokenizedURL = PlexManager.shared.getCastableStreamURL(for: streamURL) {
            castURL = tokenizedURL
        } else {
            castURL = streamURL
        }
        
        // Get artwork URL
        let artworkURL = PlexManager.shared.artworkURL(thumb: episode.thumb)
        
        // Build title: "Show Name - S01E01 - Episode Title"
        let title: String
        if let showName = episode.grandparentTitle {
            title = "\(showName) - \(episode.episodeIdentifier) - \(episode.title)"
        } else {
            title = episode.title
        }
        
        let contentType = "video/mp4"
        
        let metadata = CastMetadata(
            title: title,
            artist: episode.grandparentTitle,  // Show name as "artist"
            album: episode.parentTitle,         // Season name as "album"
            artworkURL: artworkURL,
            duration: episode.duration.map { Double($0) / 1000.0 },
            contentType: contentType,
            mediaType: .video,
            resolution: nil,
            year: nil,
            summary: episode.summary
        )
        
        NSLog("CastManager: Casting Plex episode '%@' to %@", title, device.name)
        NSLog("CastManager: Cast URL: %@", redactedURL(castURL))
        try await cast(to: device, url: castURL, metadata: metadata, startPosition: startPosition)
    }
    
    /// Cast a local video file to a video-capable device
    /// - Parameters:
    ///   - url: Local file URL
    ///   - title: Display title
    ///   - device: Target cast device (must support video)
    ///   - startPosition: Optional position to resume from (seconds)
    func castLocalVideo(_ url: URL, title: String, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        guard device.supportsVideo else {
            throw CastError.unsupportedDevice
        }
        
        guard url.isFileURL else {
            throw CastError.invalidURL
        }
        
        // Ensure LocalMediaServer is running
        if !LocalMediaServer.shared.isRunning {
            try await LocalMediaServer.shared.start()
        }
        
        // Register file and get HTTP URL
        guard let serverURL = LocalMediaServer.shared.registerFile(url) else {
            throw CastError.localServerError("Could not register file with local media server")
        }
        
        // Detect content type
        let (contentType, mediaType) = detectContentType(for: url)
        
        let metadata = CastMetadata(
            title: title,
            artist: nil,
            album: nil,
            artworkURL: nil,
            duration: nil,  // Could extract with AVAsset if needed
            contentType: contentType,
            mediaType: mediaType
        )
        
        NSLog("CastManager: Casting local video '%@' to %@", title, device.name)
        try await cast(to: device, url: serverURL, metadata: metadata, startPosition: startPosition)
    }
    
    /// Stop casting and disconnect
    func stopCasting() async {
        NSLog("CastManager: Stopping casting")
        
        if chromecastManager.activeSession != nil {
            chromecastManager.stop()
            chromecastManager.disconnect()
        }
        
        if upnpManager.activeSession != nil {
            try? await upnpManager.stop()
            upnpManager.disconnect()
        }
        
        // Clear Sonos room selection
        selectedSonosRooms.removeAll()
        
        // Unregister all files from local media server
        LocalMediaServer.shared.unregisterAll()
        
        // Clear casting state
        await MainActor.run {
            // Stop video cast update timer
            self.stopVideoCastUpdateTimer()
            
            // Only clear video-specific state if we were video casting
            if self.isVideoCasting {
                // Clear video cast state
                self.isVideoCasting = false
                self.videoCastTitle = nil
                self.videoCastDuration = 0
                self.videoCastStartPosition = 0
                self.videoCastStartDate = nil
                self.isVideoCastPlaying = false
                self.videoCastHasReceivedStatus = false
                
                // Clear video title from main window
                WindowManager.shared.mainWindowController?.clearVideoTrackInfo()
            }
            
            WindowManager.shared.audioEngine.stopCastPlayback(resumeLocally: false)
            NotificationCenter.default.post(name: Self.sessionDidChangeNotification, object: nil)
            NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: nil)
        }
    }
    
    /// Synchronous stop for app termination - stops cast devices without MainActor work
    /// This avoids deadlock when called from applicationWillTerminate on the main thread
    func stopCastingSync() {
        NSLog("CastManager: Stopping casting (sync for termination)")
        
        // Stop Chromecast - these are synchronous
        if chromecastManager.activeSession != nil {
            chromecastManager.stop()
            chromecastManager.disconnect()
        }
        
        // Stop UPnP/Sonos - disconnect is synchronous, skip async stop()
        if upnpManager.activeSession != nil {
            upnpManager.disconnect()
        }
        
        // Clear Sonos room selection
        selectedSonosRooms.removeAll()
        
        // Unregister all files from local media server
        LocalMediaServer.shared.unregisterAll()
        
        // Skip MainActor state cleanup - app is terminating anyway
    }
    
    /// Handle stop button based on active device type
    /// - Sonos/DLNA: Stop keeps session active (can play another track)
    /// - Chromecast: Stop disconnects completely
    func handleStopForActiveDevice() async {
        if let session = activeSession {
            switch session.device.type {
            case .sonos, .dlnaTV:
                // Sonos/DLNA: Stop but keep session active
                try? await stopPlayback()
            case .chromecast:
                // Chromecast: Full disconnect on stop
                await stopCasting()
            }
        }
    }
    
    /// Stop playback on the cast device but keep the session active
    /// Used for Sonos/DLNA - allows playing another track without re-selecting device
    func stopPlayback() async throws {
        if chromecastManager.activeSession != nil {
            chromecastManager.stop()
        } else if upnpManager.activeSession != nil {
            try await upnpManager.stop()
        } else {
            throw CastError.sessionNotActive
        }
        
        // Reset time to 0 but keep cast session active
        await MainActor.run {
            if self.isVideoCasting {
                self.videoCastStartPosition = 0
                self.videoCastStartDate = nil
                self.isVideoCastPlaying = false
            } else {
                // Reset time to 0 but keep cast session active
                WindowManager.shared.audioEngine.resetCastTime()
            }
            NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: nil)
        }
    }
    
    /// Pause playback on the cast device
    func pause() async throws {
        if chromecastManager.activeSession != nil {
            chromecastManager.pause()
        } else if upnpManager.activeSession != nil {
            try await upnpManager.pause()
        } else {
            throw CastError.sessionNotActive
        }
        
        // Update local time tracking
        await MainActor.run {
            if self.isVideoCasting {
                // Save current position before pausing
                if let startDate = self.videoCastStartDate {
                    self.videoCastStartPosition += Date().timeIntervalSince(startDate)
                }
                self.videoCastStartDate = nil
                self.isVideoCastPlaying = false
            } else {
                WindowManager.shared.audioEngine.pauseCastPlayback()
            }
        }
    }
    
    /// Resume playback on the cast device
    func resume() async throws {
        if chromecastManager.activeSession != nil {
            chromecastManager.resume()
        } else if upnpManager.activeSession != nil {
            try await upnpManager.resume()
        } else {
            throw CastError.sessionNotActive
        }
        
        // Update local time tracking
        await MainActor.run {
            if self.isVideoCasting {
                self.videoCastStartDate = Date()
                self.isVideoCastPlaying = true
            } else {
                WindowManager.shared.audioEngine.resumeCastPlayback()
            }
        }
    }
    
    /// Seek to a position on the cast device
    func seek(to time: TimeInterval) async throws {
        if chromecastManager.activeSession != nil {
            chromecastManager.seek(to: time)
        } else if upnpManager.activeSession != nil {
            try await upnpManager.seek(to: time)
        } else {
            throw CastError.sessionNotActive
        }
        
        // Update video cast tracking
        await MainActor.run {
            if self.isVideoCasting {
                self.videoCastStartPosition = time
                if self.isVideoCastPlaying {
                    self.videoCastStartDate = Date()
                }
            }
        }
    }
    
    // MARK: - Volume Control
    
    /// Set volume on the cast device (0.0 - 1.0)
    func setVolume(_ volume: Float) async throws {
        let volumePercent = Int(volume * 100)
        
        if chromecastManager.activeSession != nil {
            chromecastManager.setVolume(volume)
        } else if upnpManager.activeSession != nil {
            try await upnpManager.setVolume(volumePercent)
        } else {
            throw CastError.sessionNotActive
        }
    }
    
    /// Get current volume from the cast device (0.0 - 1.0)
    func getVolume() async -> Float {
        if chromecastManager.activeSession != nil {
            return chromecastManager.getVolume()
        } else if upnpManager.activeSession != nil {
            if let volume = try? await upnpManager.getVolume() {
                return Float(volume) / 100.0
            }
        }
        return 0
    }
    
    /// Set mute state on the cast device
    func setMute(_ muted: Bool) async throws {
        if chromecastManager.activeSession != nil {
            chromecastManager.setMuted(muted)
        } else if upnpManager.activeSession != nil {
            try await upnpManager.setMute(muted)
        } else {
            throw CastError.sessionNotActive
        }
    }
    
    // MARK: - Error Handling
    
    /// Post an error notification for user feedback
    func postError(_ error: CastError) {
        let errorMessage = error.localizedDescription
        NSLog("CastManager: Error - %@", errorMessage)
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.errorNotification,
                object: nil,
                userInfo: ["error": error]
            )
            
            // Show alert to user
            let alert = NSAlert()
            alert.messageText = "Casting Error"
            alert.informativeText = errorMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Helpers
    
    /// Find a matching PlexTrack for metadata
    private func findPlexTrack(matching track: Track) -> PlexTrack? {
        // This is a simplified lookup - in production, you'd want to track this association
        return nil
    }
    
    /// Redact sensitive tokens from URL for safe logging
    private func redactedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid URL>"
        }
        components.queryItems?.removeAll { $0.name == "X-Plex-Token" }
        return components.url?.absoluteString ?? "<redacted>"
    }
}

// MARK: - PlexManager Extension for Casting

extension PlexManager {
    
    /// Get a castable stream URL with token embedded
    /// Cast devices can't send custom headers, so the token must be in the URL
    func getCastableStreamURL(for url: URL) -> URL? {
        guard let token = account?.authToken else { return url }
        
        // Check if this is a Plex URL
        guard url.absoluteString.contains("/library/") ||
              url.absoluteString.contains("/transcode/") else {
            return url
        }
        
        // Add token as query parameter if not already present
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        
        // Remove existing token if present
        queryItems.removeAll { $0.name == "X-Plex-Token" }
        
        // Add current token
        queryItems.append(URLQueryItem(name: "X-Plex-Token", value: token))
        
        components?.queryItems = queryItems
        return components?.url
    }
    
    /// Generate a cast-ready URL for a Plex track
    func getCastableStreamURL(for track: PlexTrack) -> URL? {
        guard let baseURL = streamURL(for: track) else { return nil }
        return getCastableStreamURL(for: baseURL)
    }
}
