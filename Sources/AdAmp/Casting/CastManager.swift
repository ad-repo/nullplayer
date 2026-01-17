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
    static let errorNotification = Notification.Name("CastError")
    
    // MARK: - Sub-managers
    
    private let chromecastManager = ChromecastManager.shared
    private let upnpManager = UPnPManager.shared
    
    // MARK: - Properties
    
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
    
    /// Discovery state
    private(set) var isDiscovering: Bool = false
    
    /// Discovery refresh timer
    private var discoveryRefreshTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        // Start discovery automatically
        startDiscovery()
        
        // Refresh discovery periodically (every 60 seconds)
        discoveryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }
    
    deinit {
        discoveryRefreshTimer?.invalidate()
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
    func refreshDevices() {
        NSLog("CastManager: Refreshing devices...")
        
        // Clear existing devices
        chromecastManager.clearDevices()
        upnpManager.clearDevices()
        
        // Restart discovery
        chromecastManager.stopDiscovery()
        upnpManager.stopDiscovery()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.chromecastManager.startDiscovery()
            self?.upnpManager.startDiscovery()
        }
        
        NotificationCenter.default.post(name: Self.devicesDidChangeNotification, object: nil)
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
            try await chromecastManager.connect(to: device)
            try await chromecastManager.cast(url: url, metadata: metadata)
            
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
        
        // Start cast playback time tracking from the start position
        await MainActor.run {
            WindowManager.shared.audioEngine.startCastPlayback(from: startPosition)
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
            throw CastError.invalidURL
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
            // Local files can't be cast (no HTTP server)
            throw CastError.invalidURL
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
        
        // Get castable URL (with token for Plex content)
        let castURL: URL
        if track.url.scheme == "http" || track.url.scheme == "https" {
            if let tokenizedURL = PlexManager.shared.getCastableStreamURL(for: track.url) {
                castURL = tokenizedURL
            } else {
                castURL = track.url
            }
        } else {
            throw CastError.invalidURL
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
        
        NSLog("CastManager: Casting new track '%@' to %@", track.title, session.device.name)
        
        // Cast to the existing connected device
        switch session.device.type {
        case .chromecast:
            try await chromecastManager.cast(url: castURL, metadata: metadata)
            
        case .sonos, .dlnaTV:
            try await upnpManager.cast(url: castURL, metadata: metadata)
        }
        
        // Reset cast playback time tracking from position 0 for new track
        await MainActor.run {
            WindowManager.shared.audioEngine.startCastPlayback(from: 0)
            NotificationCenter.default.post(name: Self.playbackStateDidChangeNotification, object: nil)
        }
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
        
        // Reset cast time tracking
        await MainActor.run {
            WindowManager.shared.audioEngine.stopCastPlayback()
            NotificationCenter.default.post(name: Self.sessionDidChangeNotification, object: nil)
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
            WindowManager.shared.audioEngine.pauseCastPlayback()
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
            WindowManager.shared.audioEngine.resumeCastPlayback()
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
