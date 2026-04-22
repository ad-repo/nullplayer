import Foundation
import AppKit

/// Unified manager for all casting functionality
/// Coordinates Chromecast, Sonos, and DLNA device discovery and playback
class CastManager {

    static weak var cliAudioEngine: AudioEngine?

    private var resolvedAudioEngine: AudioEngine {
        if AudioEngine.isHeadless, let cliEngine = CastManager.cliAudioEngine {
            return cliEngine
        }
        return WindowManager.shared.audioEngine
    }

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

    /// Preferred Chromecast/DLNA device for video casting (device ID, persisted)
    var preferredVideoCastDeviceID: String? = UserDefaults.standard.string(forKey: "preferredVideoCastDeviceID")

    /// The preferred video cast device if it is currently discoverable and supports video.
    /// Falls back to the first available video-capable device if preferred is offline.
    var preferredVideoCastDevice: CastDevice? {
        let devices = discoveredDevices.filter { $0.supportsVideo }
        if let id = preferredVideoCastDeviceID, let match = devices.first(where: { $0.id == id }) {
            return match
        }
        return devices.first
    }

    /// Set the preferred video device. Ignores discovered devices that don't support video.
    /// Posts sessionDidChangeNotification so menus refresh.
    func setPreferredVideoCastDevice(_ deviceID: String?) {
        if let deviceID,
           let matchedDevice = discoveredDevices.first(where: { $0.id == deviceID }),
           !matchedDevice.supportsVideo {
            return
        }
        preferredVideoCastDeviceID = deviceID
        UserDefaults.standard.set(deviceID, forKey: "preferredVideoCastDeviceID")
        NotificationCenter.default.post(name: Self.sessionDidChangeNotification, object: nil)
    }

    #if DEBUG
    private var _debugDiscoveredDevices: [CastDevice]?
    #endif
    
    /// All discovered cast devices, grouped by type
    var discoveredDevices: [CastDevice] {
        #if DEBUG
        if let _debugDiscoveredDevices {
            return _debugDiscoveredDevices
        }
        #endif
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
    
    /// Get UDNs of all rooms currently in the active Sonos cast group.
    /// Returns empty array if not casting to Sonos.
    func getRoomsInActiveCastGroup() -> [String] {
        guard let targetUDN = activeSession?.device.id,
              activeSession?.device.type == .sonos else { return [] }
        let rooms = sonosRooms
        return rooms.filter { room in
            // Direct match: this room is the cast target (coordinator)
            room.id == targetUDN ||
            // This room's coordinator is the cast target
            room.groupCoordinatorUDN == targetUDN ||
            // This room IS a coordinator and the cast target is in its group
            (room.isGroupCoordinator && rooms.first(where: { $0.id == targetUDN })?.groupCoordinatorUDN == room.id)
        }.map { $0.id }
    }
    
    /// Transfer an active Sonos cast from the current coordinator to a different room.
    /// Called when the user unchecks the coordinator while other rooms remain in the group.
    /// There will be a brief (~1-2s) playback interruption during the transfer.
    ///
    /// - Parameters:
    ///   - oldCoordinatorUDN: UDN of the current coordinator being removed
    ///   - newCoordinatorUDN: UDN of the room to become the new coordinator
    ///   - otherRoomUDNs: UDNs of additional rooms to join to the new coordinator (may be empty)
    func transferSonosCast(fromCoordinator oldCoordinatorUDN: String, toRoom newCoordinatorUDN: String, otherRooms otherRoomUDNs: [String]) async throws {
        NSLog("CastManager: Transferring cast from %@ to %@ (other rooms: %@)",
              oldCoordinatorUDN, newCoordinatorUDN, otherRoomUDNs.joined(separator: ", "))
        
        // 1. Save session state before tearing anything down
        guard let session = upnpManager.activeSession,
              let savedURL = session.currentURL,
              let savedMetadata = session.metadata else {
            NSLog("CastManager: Transfer failed - no active session or missing URL/metadata")
            await stopCasting()
            throw CastError.sessionNotActive
        }
        
        // Get accurate position by polling Sonos directly (more reliable than local timer)
        var savedPosition: TimeInterval = 0
        if let pollResult = await upnpManager.pollSonosPlaybackState() {
            savedPosition = pollResult.position
        }
        NSLog("CastManager: Saved state - URL: %@, position: %.1f", savedURL.redacted, savedPosition)
        
        // 2. Stop polling and topology refresh to prevent interference during swap
        stopSonosPolling()
        stopTopologyRefresh()
        consecutiveFireAndForgetFailures = 0
        
        // 3. Make old coordinator standalone (leaves group, stops its playback)
        // This also stops playback on all grouped members since they were following the coordinator
        do {
            try await unjoinSonos(zoneUDN: oldCoordinatorUDN)
            NSLog("CastManager: Old coordinator %@ is now standalone", oldCoordinatorUDN)
        } catch {
            NSLog("CastManager: Failed to make old coordinator standalone: %@", error.localizedDescription)
            // Continue anyway - the cast to new coordinator may still work
        }
        
        // 4. Clear old session without sending Stop (old coordinator is already standalone)
        upnpManager.disconnectSession()
        
        // 5. Create CastDevice for new coordinator from zone info
        guard let newDevice = upnpManager.sonosCastDevice(forZoneUDN: newCoordinatorUDN) else {
            NSLog("CastManager: Transfer failed - could not find device for zone %@", newCoordinatorUDN)
            // Fall back to full stop - old coordinator already standalone, just clean up
            await stopCasting()
            throw CastError.playbackFailed("Could not find Sonos device for room")
        }
        NSLog("CastManager: New coordinator device: %@ (%@:%d)", newDevice.name, newDevice.address, newDevice.port)
        
        // 6. Cast to new coordinator
        // Since we cleared activeSession in step 4, cast(to:) won't call stopCasting()
        do {
            try await cast(to: newDevice, url: savedURL, metadata: savedMetadata, startPosition: savedPosition)
            NSLog("CastManager: Transfer successful - now casting to %@", newDevice.name)
        } catch {
            NSLog("CastManager: Transfer cast failed: %@", error.localizedDescription)
            // Clean up whatever partial state exists
            await stopCasting()
            throw error
        }
        
        // 7. Join other remaining rooms to the new coordinator
        if !otherRoomUDNs.isEmpty {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s for cast to establish
            for udn in otherRoomUDNs {
                do {
                    NSLog("CastManager: Joining room %@ to new coordinator %@", udn, newDevice.id)
                    try await joinSonosToGroup(zoneUDN: udn, coordinatorUDN: newDevice.id)
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s between joins
                } catch {
                    NSLog("CastManager: Failed to join room %@ to new group: %@", udn, error.localizedDescription)
                    // Non-fatal: continue with other rooms
                }
            }
        }
        
        // 8. Refresh topology to update group state
        await refreshSonosGroups()
        NSLog("CastManager: Transfer complete")
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

    /// True when the current cast target is a Sonos device.
    var isCastingToSonos: Bool {
        activeSession?.device.type == .sonos
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

    /// Discovery refresh timer (60s periodic device refresh while discovery is active)
    private var discoveryRefreshTimer: Timer?

    /// Idle timeout timer — stops discovery 5 minutes after last cast menu open (if not casting)
    private var discoveryIdleTimer: Timer?
    
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

    /// Prevents simultaneous cast attempts from racing on connect/cast sequences.
    @MainActor private var isCastingInProgress: Bool = false
    
    // MARK: - Initialization
    
    /// Timer for polling Sonos playback state during active casting
    private var sonosPollingTimer: Timer?
    
    /// Timer for periodic Sonos group topology refresh during casting
    private var topologyRefreshTimer: Timer?
    
    /// Consecutive fire-and-forget command failures (for error surfacing)
    private var consecutiveFireAndForgetFailures = 0
    private let maxConsecutiveFailures = 3
    
    private init() {
        // Subscribe to Chromecast status updates for position syncing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChromecastMediaStatusUpdate),
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil
        )
        
        // Subscribe to sleep/wake notifications (Fix 8)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    deinit {
        discoveryRefreshTimer?.invalidate()
        discoveryIdleTimer?.invalidate()
        sonosPollingTimer?.invalidate()
        topologyRefreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
                self.resolvedAudioEngine.updateCastPosition(
                    currentTime: status.currentTime,
                    isPlaying: isPlaying,
                    isBuffering: isBuffering
                )
            }
        }
    }
    
    // MARK: - Discovery
    
    /// Start discovering cast devices on the network (lazy — called on demand when cast menu opens)
    func startDiscovery() {
        guard !isDiscovering else {
            // Already discovering — reset idle timeout so discovery stays alive
            resetDiscoveryIdleTimer()
            return
        }

        NSLog("CastManager: Starting device discovery...")
        isDiscovering = true

        chromecastManager.startDiscovery()
        upnpManager.startDiscovery()

        // Start periodic refresh if not already running
        if discoveryRefreshTimer == nil {
            discoveryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                // Avoid discovery restart bursts during local playback, which can
                // compete with high-throughput SMB/NAS reads on weaker WiFi links.
                let engine = self.resolvedAudioEngine
                if engine.state == .playing && !engine.isCastingActive {
                    NSLog("CastManager: Skipping discovery refresh - local audio is playing")
                    return
                }
                self.refreshDevices()
            }
        }

        // Schedule idle timeout — stop discovery after 5 minutes if not casting
        resetDiscoveryIdleTimer()
    }

    /// Stop discovering devices
    func stopDiscovery() {
        guard isDiscovering, !isCasting else { return }
        NSLog("CastManager: Stopping device discovery (idle)")
        isDiscovering = false

        chromecastManager.stopDiscovery()
        upnpManager.stopDiscovery()

        discoveryRefreshTimer?.invalidate()
        discoveryRefreshTimer = nil
        discoveryIdleTimer?.invalidate()
        discoveryIdleTimer = nil
    }

    private func resetDiscoveryIdleTimer() {
        discoveryIdleTimer?.invalidate()
        discoveryIdleTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.stopDiscovery()
        }
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

        let alreadyInProgress = await MainActor.run {
            if self.isCastingInProgress { return true }
            self.isCastingInProgress = true
            return false
        }
        guard !alreadyInProgress else {
            NSLog("CastManager: cast() called while already in progress - ignoring")
            return
        }
        defer {
            Task { @MainActor in self.isCastingInProgress = false }
        }

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
            NSLog("CastManager: Connecting to %@...", device.type.displayName)
            do {
                try await upnpManager.connect(to: device)
                NSLog("CastManager: Connected to %@, now casting...", device.type.displayName)
                try await upnpManager.cast(url: url, metadata: metadata)
                NSLog("CastManager: Cast started successfully")
            } catch {
                NSLog("CastManager: %@ error: %@", device.type.displayName, error.localizedDescription)
                // Clean up partial session state - connect() may have succeeded before cast() failed
                await upnpManager.disconnect()
                throw error
            }
        }
        
        // If we have a start position, seek to it after playback starts
        // Skip seeking for radio streams (no duration) since they don't support seeking
        if startPosition > 1.0 && metadata.duration != nil {
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
                
                // Notify RadioManager if this was a radio cast (local playback never starts for cast)
                if RadioManager.shared.isActive {
                    RadioManager.shared.castDidConnect()
                }
                
                // For radio streams (no duration), always start time from 0 since they're live
                let trackingPosition = metadata.duration != nil ? startPosition : 0
                
                if device.type == .chromecast {
                    // Chromecast provides status updates - wait for PLAYING status to start timer
                    // This prevents clock sync issues when buffering on slow networks
                    resolvedAudioEngine.initializeCastPlayback(from: trackingPosition)
                } else {
                    // Sonos/DLNA don't provide status updates - start timer immediately
                    resolvedAudioEngine.startCastPlayback(from: trackingPosition)
                }
                
                // For Sonos, start status polling and topology refresh (Fix 1 & 9)
                if device.type == .sonos {
                    self.startSonosPolling()
                    self.startTopologyRefresh()
                }
            }
            NotificationCenter.default.post(name: Self.sessionDidChangeNotification, object: nil)
            NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: nil)
        }
    }
    
    /// Stop local audio playback (called when casting starts)
    /// Must fully stop (not just pause) streaming playback to release the connection
    /// This is especially important for Subsonic/Navidrome which limits concurrent streams per user
    private func pauseLocalPlayback() {
        let engine = resolvedAudioEngine
        if engine.state == .playing && !engine.isCastingActive {
            // Stop local playback completely to release any streaming connections
            // This prevents conflicts with Subsonic/Navidrome which limits concurrent streams
            engine.stopLocalForCasting()
        }
    }
    
    /// Cast the currently playing track to a device
    func castCurrentTrack(to device: CastDevice) async throws {
        let engine = resolvedAudioEngine
        guard let track = engine.currentTrack else {
            throw CastError.noTrackPlaying
        }

        // Capture current position before casting
        var currentPosition = await MainActor.run { engine.currentTime }

        // For Sonos, advance past incompatible tracks using a fetch-and-verify loop
        var trackToUse = track
        if device.type == .sonos {
            var fetchedSR: Int? = nil
            if trackToUse.sampleRate == nil, let rk = trackToUse.plexRatingKey {
                let ext = trackToUse.url.pathExtension.lowercased()
                if Self.sonosLosslessExtensions.contains(ext) {
                    fetchedSR = await PlexManager.shared.fetchSampleRate(for: rk)
                    NSLog("CastManager: castCurrentTrack fetched sample rate for '%@': %@",
                          trackToUse.title, fetchedSR.map { "\($0) Hz" } ?? "nil")
                }
            }
            while !Self.isSonosCompatible(trackToUse, sampleRateOverride: fetchedSR) {
                let next = await MainActor.run { engine.advanceToFirstSonosCompatibleTrack() }
                guard let next else {
                    throw CastError.playbackFailed("No tracks in the playlist are supported by Sonos")
                }
                trackToUse = next
                currentPosition = 0
                fetchedSR = nil
                if trackToUse.sampleRate == nil, let rk = trackToUse.plexRatingKey {
                    let ext = trackToUse.url.pathExtension.lowercased()
                    if Self.sonosLosslessExtensions.contains(ext) {
                        fetchedSR = await PlexManager.shared.fetchSampleRate(for: rk)
                        NSLog("CastManager: castCurrentTrack fetched sample rate for '%@': %@",
                              trackToUse.title, fetchedSR.map { "\($0) Hz" } ?? "nil")
                    }
                }
            }
        }

        try await castTrack(trackToUse, to: device, startPosition: currentPosition)
    }
    
    /// Cast a specific track to a device
    func castTrack(_ track: Track, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        NSLog("CastManager: castTrack called for '%@' - track.url: %@", track.title, track.url.redacted)
        NSLog("CastManager: track.subsonicId=%@, track.jellyfinId=%@, track.embyId=%@, track.plexRatingKey=%@",
              track.subsonicId ?? "nil", track.jellyfinId ?? "nil", track.embyId ?? "nil", track.plexRatingKey ?? "nil")

        // Get castable URL and effective content type
        let castURL: URL
        var effectiveContentType: String? = track.contentType

        // Check if this is a Subsonic/Jellyfin/Emby track casting to Sonos - needs proxy due to query string issues
        let needsSubsonicProxy = track.subsonicId != nil && device.type == .sonos
        let needsJellyfinProxy = track.jellyfinId != nil && device.type == .sonos
        let needsEmbyProxy = track.embyId != nil && device.type == .sonos

        if track.url.scheme == "http" || track.url.scheme == "https" {
            if needsSubsonicProxy || needsJellyfinProxy || needsEmbyProxy {
                // Subsonic/Jellyfin/Emby to Sonos: Use proxy with HEAD-based content type detection
                let result = try await prepareProxyURL(for: track, device: device)
                castURL = result.url
                effectiveContentType = result.contentType
                NSLog("CastManager: Using proxy for Subsonic/Jellyfin/Emby->Sonos: %@", castURL.redacted)
            } else {
                // For Plex/remote URLs, ensure token is included
                if let tokenizedURL = PlexManager.shared.getCastableStreamURL(for: track.url) {
                    castURL = rewriteLocalhostForCasting(tokenizedURL)
                } else {
                    castURL = rewriteLocalhostForCasting(track.url)
                }
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
        } else if track.subsonicId != nil, let coverArtId = track.artworkThumb {
            // Subsonic/Navidrome tracks have artwork via coverArt ID
            if let subsonicArtwork = SubsonicManager.shared.coverArtURL(coverArtId: coverArtId) {
                artworkURL = rewriteLocalhostForCasting(subsonicArtwork)
            }
        } else if track.jellyfinId != nil, let imageTag = track.artworkThumb {
            // Jellyfin track - use server's image URL
            if let jellyfinArtwork = JellyfinManager.shared.imageURL(itemId: track.jellyfinId!, imageTag: imageTag, size: 300) {
                artworkURL = rewriteLocalhostForCasting(jellyfinArtwork)
            }
        } else if track.embyId != nil, let imageTag = track.artworkThumb {
            // Emby track - use server's image URL
            if let embyArtwork = EmbyManager.shared.imageURL(itemId: track.embyId!, imageTag: imageTag, size: 300) {
                artworkURL = rewriteLocalhostForCasting(embyArtwork)
            }
        }

        // Use effective content type (from track or upstream HEAD detection),
        // otherwise fall back to URL extension detection (works for Plex and local files)
        let contentType = effectiveContentType ?? Self.detectAudioContentType(for: track.url)

        // For radio streams cast to Sonos, use x-rincon-mp3radio:// scheme (Fix 10)
        let finalCastURL = sonosRadioURL(for: castURL, device: device)

        let metadata = CastMetadata(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkURL: artworkURL,
            duration: track.duration,
            contentType: contentType
        )
        
        NSLog("CastManager: castTrack URL: %@, contentType: %@", finalCastURL.redacted, contentType)
        
        try await cast(to: device, url: finalCastURL, metadata: metadata, startPosition: startPosition)
    }
    
    /// Cast a new track to the already connected device (for next/previous)
    func castNewTrack(_ track: Track) async throws {
        guard let session = activeSession else {
            throw CastError.sessionNotActive
        }

        // For Sonos: if format is unsupported, advance to the next compatible track
        if session.device.type == .sonos {
            // Fetch missing sample rate for lossless Plex tracks (Plex API may omit Stream details)
            var fetchedSampleRate: Int? = nil
            if track.sampleRate == nil, let ratingKey = track.plexRatingKey {
                let ext = track.url.pathExtension.lowercased()
                if Self.sonosLosslessExtensions.contains(ext) {
                    fetchedSampleRate = await PlexManager.shared.fetchSampleRate(for: ratingKey)
                    NSLog("CastManager: castNewTrack fetched sample rate for '%@': %@",
                          track.title, fetchedSampleRate.map { "\($0) Hz" } ?? "nil")
                }
            }
            if !Self.isSonosCompatible(track, sampleRateOverride: fetchedSampleRate) {
                let engine = WindowManager.shared.audioEngine
                NSLog("CastManager: castNewTrack '%@' (%@) not supported by Sonos — finding next compatible track",
                      track.title, track.url.pathExtension)
                let compatible = await MainActor.run { engine.advanceToFirstSonosCompatibleTrack() }
                guard let compatible else {
                    await stopCasting()
                    return
                }
                try await castNewTrack(compatible)
                return
            }
        }

        // Check if this is a local file (needs loading state due to async registration)
        let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
        
        // Check if Subsonic/Jellyfin/Emby track to Sonos - also needs loading state since we use proxy
        let needsSubsonicProxy = track.subsonicId != nil && session.device.type == .sonos
        let needsJellyfinProxy = track.jellyfinId != nil && session.device.type == .sonos
        let needsEmbyProxy = track.embyId != nil && session.device.type == .sonos

        // Check if this is a radio station to Sonos - needs loading state for click guarding
        let isRadioToSonos = RadioManager.shared.isActive && session.device.type == .sonos

        let needsLoadingState = isLocalFile || needsSubsonicProxy || needsJellyfinProxy || needsEmbyProxy || isRadioToSonos
        
        // Increment generation to invalidate any in-flight cast operations
        // This prevents race conditions when user rapidly clicks through tracks
        // Must be done on MainActor for thread safety
        let myGeneration = await MainActor.run {
            castTrackGeneration += 1
            
            // Set loading state for local files and Subsonic->Sonos proxy (they have async registration)
            if needsLoadingState {
                isCastingTrackChange = true
                pendingCastTrack = track
                NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": true, "track": track])
            }
            
            return castTrackGeneration
        }
        
        NSLog("CastManager: castNewTrack '%@' starting (generation %d)", track.title, myGeneration)
        
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
        
        // Get castable URL and effective content type
        let castURL: URL
        var effectiveContentType: String? = track.contentType
        if track.url.scheme == "http" || track.url.scheme == "https" {
            if needsSubsonicProxy || needsJellyfinProxy || needsEmbyProxy {
                // Subsonic/Jellyfin/Emby to Sonos: Use proxy with HEAD-based content type detection
                do {
                    let result = try await prepareProxyURL(for: track, device: session.device)
                    castURL = result.url
                    effectiveContentType = result.contentType
                    NSLog("CastManager: castNewTrack using proxy for Subsonic/Jellyfin/Emby->Sonos: %@", castURL.redacted)
                } catch {
                    await clearLoadingState()
                    throw error
                }
            } else if let tokenizedURL = PlexManager.shared.getCastableStreamURL(for: track.url) {
                castURL = rewriteLocalhostForCasting(tokenizedURL)
            } else {
                castURL = rewriteLocalhostForCasting(track.url)
            }
        } else {
            // Local file - register with HTTP server
            // Ensure server is running before registering
            if !LocalMediaServer.shared.isRunning {
                do {
                    try await LocalMediaServer.shared.start()
                } catch {
                    await clearLoadingState()
                    throw CastError.localServerError("Could not start local media server: \(error.localizedDescription)")
                }
            }
            
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
            // Only clear loading state if we OWN it (pendingCastTrack still matches our track)
            // If another track with loading state superseded us, it set its own pendingCastTrack and we shouldn't clear
            await MainActor.run {
                if needsLoadingState && pendingCastTrack?.id == track.id {
                    isCastingTrackChange = false
                    pendingCastTrack = nil
                    NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": false])
                }
            }
            return
        }
        
        // Get artwork URL if available
        var artworkURL: URL?
        if let plexTrack = findPlexTrack(matching: track) {
            artworkURL = PlexManager.shared.artworkURL(thumb: plexTrack.thumb)
        } else if track.subsonicId != nil, let coverArtId = track.artworkThumb {
            // Subsonic/Navidrome tracks have artwork via coverArt ID
            if let subsonicArtwork = SubsonicManager.shared.coverArtURL(coverArtId: coverArtId) {
                artworkURL = rewriteLocalhostForCasting(subsonicArtwork)
            }
        } else if track.jellyfinId != nil, let imageTag = track.artworkThumb {
            // Jellyfin track - use server's image URL
            if let jellyfinArtwork = JellyfinManager.shared.imageURL(itemId: track.jellyfinId!, imageTag: imageTag, size: 300) {
                artworkURL = rewriteLocalhostForCasting(jellyfinArtwork)
            }
        } else if track.embyId != nil, let imageTag = track.artworkThumb {
            // Emby track - use server's image URL
            if let embyArtwork = EmbyManager.shared.imageURL(itemId: track.embyId!, imageTag: imageTag, size: 300) {
                artworkURL = rewriteLocalhostForCasting(embyArtwork)
            }
        }

        // Use effective content type (from track or upstream HEAD detection),
        // otherwise fall back to URL extension detection (works for Plex and local files)
        let contentType = effectiveContentType ?? Self.detectAudioContentType(for: track.url)

        // For radio streams cast to Sonos, use x-rincon-mp3radio:// scheme (Fix 10)
        let finalCastURL = sonosRadioURL(for: castURL, device: session.device)
        
        let metadata = CastMetadata(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkURL: artworkURL,
            duration: track.duration,
            contentType: contentType
        )
        
        NSLog("CastManager: Casting new track '%@' to %@, contentType: %@", track.title, session.device.name, contentType)
        
        // Cast to the existing connected device
        // Wrap in do/catch to ensure loading state is cleared on failure
        do {
            switch session.device.type {
            case .chromecast:
                try await chromecastManager.cast(url: finalCastURL, metadata: metadata)
                
            case .sonos, .dlnaTV:
                try await upnpManager.cast(url: finalCastURL, metadata: metadata)
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
            // Only clear loading state if we OWN it (pendingCastTrack still matches our track)
            // If another track with loading state superseded us, it set its own pendingCastTrack and we shouldn't clear
            await MainActor.run {
                if needsLoadingState && pendingCastTrack?.id == track.id {
                    isCastingTrackChange = false
                    pendingCastTrack = nil
                    NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": false])
                }
            }
            return
        }
        
        // Reset cast playback time tracking from position 0 for new track
        await MainActor.run {
            // Final check on main thread before updating UI
            guard myGeneration == self.castTrackGeneration else {
                NSLog("CastManager: castNewTrack '%@' UI update abandoned - superseded", track.title)
                // Only clear loading state if we OWN it (pendingCastTrack still matches our track)
                // If another track with loading state superseded us, it set its own pendingCastTrack and we shouldn't clear
                if needsLoadingState && self.pendingCastTrack?.id == track.id {
                    self.isCastingTrackChange = false
                    self.pendingCastTrack = nil
                    NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": false])
                }
                return
            }
            
            // Clear loading state - cast completed successfully
            isCastingTrackChange = false
            pendingCastTrack = nil
            NotificationCenter.default.post(name: Self.trackChangeLoadingNotification, object: nil, userInfo: ["isLoading": false])
            
            // Notify RadioManager if this was a radio cast (local playback never starts for cast)
            if RadioManager.shared.isActive {
                RadioManager.shared.castDidConnect()
            }
            
            if session.device.type == .chromecast {
                // Chromecast provides status updates - wait for PLAYING status to start timer
                resolvedAudioEngine.initializeCastPlayback(from: 0)
            } else {
                // Sonos/DLNA don't provide status updates - start timer immediately
                resolvedAudioEngine.startCastPlayback(from: 0)
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
    
    /// Cast a Jellyfin movie to a video-capable device
    /// - Parameters:
    ///   - movie: The JellyfinMovie to cast
    ///   - device: Target cast device (must support video)
    ///   - startPosition: Optional position to resume from (seconds)
    func castJellyfinMovie(_ movie: JellyfinMovie, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        guard device.supportsVideo else {
            throw CastError.unsupportedDevice
        }
        
        guard let streamURL = JellyfinManager.shared.videoStreamURL(for: movie) else {
            throw CastError.invalidURL
        }
        
        // Get artwork URL
        let artworkURL = JellyfinManager.shared.imageURL(itemId: movie.id, imageTag: movie.imageTag, size: 600)
        
        let contentType = "video/mp4"
        
        let metadata = CastMetadata(
            title: movie.title,
            artist: nil,
            album: nil,
            artworkURL: artworkURL,
            duration: movie.duration.map { Double($0) },
            contentType: contentType,
            mediaType: .video,
            resolution: nil,
            year: movie.year,
            summary: movie.overview
        )
        
        NSLog("CastManager: Casting Jellyfin movie '%@' to %@", movie.title, device.name)
        NSLog("CastManager: Cast URL: %@", redactedURL(streamURL))
        try await cast(to: device, url: streamURL, metadata: metadata, startPosition: startPosition)
    }
    
    /// Cast a Jellyfin episode to a video-capable device
    /// - Parameters:
    ///   - episode: The JellyfinEpisode to cast
    ///   - device: Target cast device (must support video)
    ///   - startPosition: Optional position to resume from (seconds)
    func castJellyfinEpisode(_ episode: JellyfinEpisode, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        guard device.supportsVideo else {
            throw CastError.unsupportedDevice
        }
        
        guard let streamURL = JellyfinManager.shared.videoStreamURL(for: episode) else {
            throw CastError.invalidURL
        }
        
        // Get artwork URL
        let artworkURL = JellyfinManager.shared.imageURL(itemId: episode.id, imageTag: episode.imageTag, size: 600)
        
        // Build title: "Show Name - S01E01 - Episode Title"
        let title: String
        if let showName = episode.seriesName {
            title = "\(showName) - \(episode.episodeIdentifier) - \(episode.title)"
        } else {
            title = episode.title
        }
        
        let contentType = "video/mp4"
        
        let metadata = CastMetadata(
            title: title,
            artist: episode.seriesName,
            album: episode.seasonName,
            artworkURL: artworkURL,
            duration: episode.duration.map { Double($0) },
            contentType: contentType,
            mediaType: .video,
            resolution: nil,
            year: nil,
            summary: episode.overview
        )
        
        NSLog("CastManager: Casting Jellyfin episode '%@' to %@", title, device.name)
        NSLog("CastManager: Cast URL: %@", redactedURL(streamURL))
        try await cast(to: device, url: streamURL, metadata: metadata, startPosition: startPosition)
    }
    
    /// Cast an Emby movie to a video-capable device
    /// - Parameters:
    ///   - movie: The EmbyMovie to cast
    ///   - device: Target cast device (must support video)
    ///   - startPosition: Optional position to resume from (seconds)
    func castEmbyMovie(_ movie: EmbyMovie, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        guard device.supportsVideo else {
            throw CastError.unsupportedDevice
        }

        guard let streamURL = EmbyManager.shared.videoStreamURL(for: movie) else {
            throw CastError.invalidURL
        }

        // Get artwork URL
        let artworkURL = EmbyManager.shared.imageURL(itemId: movie.id, imageTag: movie.imageTag, size: 600)

        let contentType = "video/mp4"

        let metadata = CastMetadata(
            title: movie.title,
            artist: nil,
            album: nil,
            artworkURL: artworkURL,
            duration: movie.duration.map { Double($0) },
            contentType: contentType,
            mediaType: .video,
            resolution: nil,
            year: movie.year,
            summary: movie.overview
        )

        NSLog("CastManager: Casting Emby movie '%@' to %@", movie.title, device.name)
        NSLog("CastManager: Cast URL: %@", redactedURL(streamURL))
        try await cast(to: device, url: streamURL, metadata: metadata, startPosition: startPosition)
    }

    /// Cast an Emby episode to a video-capable device
    /// - Parameters:
    ///   - episode: The EmbyEpisode to cast
    ///   - device: Target cast device (must support video)
    ///   - startPosition: Optional position to resume from (seconds)
    func castEmbyEpisode(_ episode: EmbyEpisode, to device: CastDevice, startPosition: TimeInterval = 0) async throws {
        guard device.supportsVideo else {
            throw CastError.unsupportedDevice
        }

        guard let streamURL = EmbyManager.shared.videoStreamURL(for: episode) else {
            throw CastError.invalidURL
        }

        // Get artwork URL
        let artworkURL = EmbyManager.shared.imageURL(itemId: episode.id, imageTag: episode.imageTag, size: 600)

        // Build title: "Show Name - S01E01 - Episode Title"
        let title: String
        if let showName = episode.seriesName {
            title = "\(showName) - \(episode.episodeIdentifier) - \(episode.title)"
        } else {
            title = episode.title
        }

        let contentType = "video/mp4"

        let metadata = CastMetadata(
            title: title,
            artist: episode.seriesName,
            album: episode.seasonName,
            artworkURL: artworkURL,
            duration: episode.duration.map { Double($0) },
            contentType: contentType,
            mediaType: .video,
            resolution: nil,
            year: nil,
            summary: episode.overview
        )

        NSLog("CastManager: Casting Emby episode '%@' to %@", title, device.name)
        NSLog("CastManager: Cast URL: %@", redactedURL(streamURL))
        try await cast(to: device, url: streamURL, metadata: metadata, startPosition: startPosition)
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
        
        // Stop Sonos polling and topology refresh
        stopSonosPolling()
        stopTopologyRefresh()
        consecutiveFireAndForgetFailures = 0
        
        // Ungroup all Sonos member rooms before stopping the coordinator.
        // This prevents stale group topology that causes SOAP errors on subsequent casts.
        if upnpManager.activeSession?.device.type == .sonos {
            let groupRoomUDNs = getRoomsInActiveCastGroup()
            let coordinatorUDN = upnpManager.activeSession?.device.id
            for udn in groupRoomUDNs where udn != coordinatorUDN {
                NSLog("CastManager: Ungrouping room %@ before stop", udn)
                try? await unjoinSonos(zoneUDN: udn)
            }
            if groupRoomUDNs.count > 1 {
                // Brief delay for Sonos to process ungrouping
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        
        if chromecastManager.activeSession != nil {
            chromecastManager.stop()
            chromecastManager.disconnect()
        }
        
        if upnpManager.activeSession != nil {
            try? await upnpManager.stop()
            await upnpManager.disconnect()
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
        
        // Stop Sonos polling and topology refresh
        stopSonosPolling()
        stopTopologyRefresh()
        consecutiveFireAndForgetFailures = 0
        
        // Stop Chromecast - these are synchronous
        if chromecastManager.activeSession != nil {
            chromecastManager.stop()
            chromecastManager.disconnect()
        }
        
        // Stop UPnP/Sonos - use sync disconnect to avoid blocking on async stop()
        if upnpManager.activeSession != nil {
            upnpManager.disconnectSync()
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
    
    // MARK: - Sonos Playback State Polling (Fix 1)
    
    /// Start polling Sonos for playback state and position
    private func startSonosPolling() {
        stopSonosPolling()
        DispatchQueue.main.async {
            self.sonosPollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.pollSonosState()
            }
            RunLoop.main.add(self.sonosPollingTimer!, forMode: .common)
        }
    }
    
    /// Stop Sonos playback state polling
    private func stopSonosPolling() {
        sonosPollingTimer?.invalidate()
        sonosPollingTimer = nil
    }
    
    /// Poll Sonos transport state and sync position with AudioEngine
    private func pollSonosState() {
        Task {
            guard let result = await upnpManager.pollSonosPlaybackState() else { return }
            
            await MainActor.run {
                let engine = WindowManager.shared.audioEngine
                guard engine.isCastingActive else { return }
                
                switch result.state {
                case "PLAYING":
                    // Sync position with actual Sonos position to prevent drift
                    engine.updateCastPosition(
                        currentTime: result.position,
                        isPlaying: true,
                        isBuffering: false
                    )
                case "PAUSED_PLAYBACK":
                    if engine.state == .playing {
                        engine.pauseCastPlayback()
                        NSLog("CastManager: Sonos reported PAUSED (external pause detected)")
                    }
                case "STOPPED", "NO_MEDIA_PRESENT":
                    NSLog("CastManager: Sonos reported %@ - playback ended externally", result.state)
                    // Don't auto-disconnect, just update state so UI reflects reality
                    engine.pauseCastPlayback()
                    NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: nil)
                case "TRANSITIONING":
                    // Sonos is loading/buffering - don't change state, just wait
                    break
                default:
                    NSLog("CastManager: Unknown Sonos state: %@", result.state)
                }
            }
        }
    }
    
    // MARK: - Mac Sleep/Wake Handling (Fix 8)
    
    @objc private func handleWillSleep() {
        NSLog("CastManager: Mac going to sleep, casting will be interrupted")
        // Nothing to do proactively -- Sonos will stop on its own when it can't reach the server
    }
    
    @objc private func handleDidWake() {
        NSLog("CastManager: Mac woke up, checking cast state")
        guard isCasting else { return }
        
        Task {
            // Wait a moment for network to reconnect
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Check if LocalMediaServer IP changed
            if let oldIP = LocalMediaServer.shared.localIPAddress,
               let newIP = LocalMediaServer.shared.refreshIPAddress(),
               oldIP != newIP {
                NSLog("CastManager: IP changed after wake (%@ -> %@)", oldIP, newIP)
            }
            
            // Poll Sonos to see if it's still playing
            if let result = await upnpManager.pollSonosPlaybackState() {
                NSLog("CastManager: Post-wake Sonos state: %@, position: %.1f", result.state, result.position)
                if result.state == "STOPPED" || result.state == "NO_MEDIA_PRESENT" {
                    NSLog("CastManager: Sonos stopped during sleep")
                    await MainActor.run {
                        WindowManager.shared.audioEngine.pauseCastPlayback()
                        NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: nil)
                    }
                }
            }
        }
    }
    
    // MARK: - Sonos Group Topology Refresh (Fix 9)
    
    /// Start periodic group topology refresh during Sonos casting
    private func startTopologyRefresh() {
        stopTopologyRefresh()
        DispatchQueue.main.async {
            self.topologyRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                Task {
                    await self?.refreshSonosGroups()
                }
            }
        }
    }
    
    /// Stop periodic group topology refresh
    private func stopTopologyRefresh() {
        topologyRefreshTimer?.invalidate()
        topologyRefreshTimer = nil
    }
    
    // MARK: - Proxy URL Preparation
    
    /// Prepare a proxy URL for casting a Subsonic/Jellyfin track to Sonos.
    /// Starts LocalMediaServer if needed, rewrites localhost URLs, detects content type
    /// via upstream HEAD request when track.contentType is nil, and registers the proxy.
    /// Returns the proxy URL and the effective content type for DIDL-Lite metadata.
    private func prepareProxyURL(for track: Track, device: CastDevice) async throws -> (url: URL, contentType: String?) {
        if !LocalMediaServer.shared.isRunning {
            do {
                try await LocalMediaServer.shared.start()
            } catch {
                throw CastError.localServerError("Could not start local media server: \(error.localizedDescription)")
            }
        }
        
        let rewrittenURL = rewriteLocalhostForCasting(track.url)
        
        // Detect content type from upstream if track doesn't have it
        var effectiveContentType = track.contentType
        if effectiveContentType == nil {
            effectiveContentType = await detectUpstreamContentType(rewrittenURL)
            NSLog("CastManager: Detected upstream content type: %@", effectiveContentType ?? "nil")
        }
        
        guard let proxyURL = LocalMediaServer.shared.registerStreamURL(rewrittenURL, contentType: effectiveContentType) else {
            throw CastError.localServerError("Could not register stream with local media server")
        }
        
        return (proxyURL, effectiveContentType)
    }
    
    /// Send a HEAD request to an upstream URL to detect its Content-Type.
    /// Returns the MIME type if it starts with "audio/", nil otherwise.
    private func detectUpstreamContentType(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let ct = http.value(forHTTPHeaderField: "Content-Type"),
              ct.hasPrefix("audio/") else {
            NSLog("CastManager: HEAD content type detection failed or returned non-audio for %@", url.host ?? "unknown")
            return nil
        }
        NSLog("CastManager: HEAD response Content-Type: %@", ct)
        return ct
    }
    
    // MARK: - Content Type Detection (Fix 2)
    
    /// Detect audio content type from a file extension string (e.g. "flac" -> "audio/flac")
    static func detectAudioContentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp3":                   return "audio/mpeg"
        case "flac":                  return "audio/flac"
        case "m4a", "aac":            return "audio/mp4"
        case "wav":                   return "audio/wav"
        case "aiff", "aif":          return "audio/aiff"
        case "ogg":                   return "audio/ogg"
        case "opus":                  return "audio/opus"
        case "wma":                   return "audio/x-ms-wma"
        case "alac":                  return "audio/mp4"
        default:                      return "audio/mpeg"  // Safe default
        }
    }
    
    /// Detect audio content type from URL path extension
    static func detectAudioContentType(for url: URL) -> String {
        detectAudioContentType(forExtension: url.pathExtension)
    }

    // MARK: - Sonos Format Compatibility

    /// Extensions that Sonos hardware cannot decode regardless of resolution.
    /// ALAC: decoder absent on S1 devices. AIFF: not in Sonos's UPnP supported-format list.
    /// WavPack (.wv): unsupported codec on all Sonos hardware.
    /// Monkey's Audio (.ape): proprietary codec, not supported by Sonos.
    static let sonosUnsupportedExtensions: Set<String> = ["alac", "aiff", "aif", "wv", "ape"]

    /// Sonos S1 fails above 48 kHz PCM; use as conservative safe limit.
    static let sonosMaxSampleRate: Int = 48000

    /// Lossless extensions that require the sample-rate check.
    private static let sonosLosslessExtensions: Set<String> = ["flac", "wav"]

    /// Map common audio MIME types to their extension equivalent for format checking.
    private static func contentTypeToExtension(_ ct: String) -> String {
        switch ct {
        case "audio/x-aiff", "audio/aiff":  return "aiff"
        case "audio/alac", "audio/x-alac":  return "alac"
        case "audio/flac", "audio/x-flac":  return "flac"
        case "audio/wav", "audio/x-wav":    return "wav"
        default:                            return ""
        }
    }

    /// Returns false if the track format is known to be unsupported by Sonos.
    /// Falls back to `track.contentType` when the URL has no file extension
    /// (e.g. server-streamed tracks from Subsonic/Jellyfin/Emby/Plex).
    static func isSonosCompatible(_ track: Track, sampleRateOverride: Int? = nil,
                                   allowUnknownSampleRate: Bool = false) -> Bool {
        var ext = track.url.pathExtension.lowercased()

        if ext.isEmpty, let ct = track.contentType {
            ext = contentTypeToExtension(ct)
        }

        if sonosUnsupportedExtensions.contains(ext) { return false }

        if sonosLosslessExtensions.contains(ext) {
            let effectiveSampleRate = sampleRateOverride ?? track.sampleRate
            if let sr = effectiveSampleRate {
                if sr > sonosMaxSampleRate { return false }
            } else if !allowUnknownSampleRate {
                return false  // nil SR in strict mode → block
            }
            // nil SR + allowUnknownSampleRate → pass through (let caller fetch and verify)
        }

        return true
    }

    // MARK: - Sonos Radio URI (Fix 10)
    
    /// Convert HTTP radio stream URL to Sonos x-rincon-mp3radio:// scheme for better buffering
    private func sonosRadioURL(for url: URL, device: CastDevice) -> URL {
        // Only for Sonos devices, only for http:// streams, only for radio
        guard device.type == .sonos,
              url.scheme == "http" || url.scheme == "https",
              RadioManager.shared.isActive else {
            return url
        }
        // Replace http:// with x-rincon-mp3radio://
        var urlString = url.absoluteString
        if urlString.hasPrefix("http://") {
            urlString = "x-rincon-mp3radio://" + urlString.dropFirst(7)
        } else if urlString.hasPrefix("https://") {
            urlString = "x-rincon-mp3radio://" + urlString.dropFirst(8)
        }
        return URL(string: urlString) ?? url
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
        url.redacted
    }
    
    /// Replace localhost/127.0.0.1 with the Mac's actual network IP for casting
    /// Cast devices (Sonos, Chromecast) can't reach localhost - they need the real IP
    private func rewriteLocalhostForCasting(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        
        // Check if host is localhost or loopback
        let host = components.host?.lowercased() ?? ""
        guard host == "localhost" || host == "127.0.0.1" || host == "::1" else {
            return url  // Not localhost, return unchanged
        }
        
        // Get the Mac's local network IP
        guard let localIP = LocalMediaServer.shared.localIPAddress else {
            NSLog("CastManager: WARNING - Cannot rewrite localhost URL, no local IP found")
            return url
        }
        
        NSLog("CastManager: Rewriting localhost to %@ for casting", localIP)
        components.host = localIP
        
        return components.url ?? url
    }
}

#if DEBUG
extension CastManager {
    var debugDiscoveredDevices: [CastDevice]? {
        get { _debugDiscoveredDevices }
        set { _debugDiscoveredDevices = newValue }
    }

    func debugSetVideoCastingStateForTesting(_ isVideoCasting: Bool) {
        self.isVideoCasting = isVideoCasting
    }
}
#endif

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
