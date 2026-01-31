import AppKit
import MediaPlayer
import AVFoundation

/// Manages macOS Now Playing integration for Discord Music Presence and system media controls
/// Reports track metadata to MPNowPlayingInfoCenter and handles remote commands
class NowPlayingManager {
    
    // MARK: - Singleton
    
    static let shared = NowPlayingManager()
    
    // MARK: - Properties
    
    /// Current artwork being displayed (cached to avoid reloading)
    private var currentArtwork: NSImage?
    private var currentTrackId: UUID?
    
    /// Task for loading artwork asynchronously
    private var artworkLoadTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Setup
    
    /// Call this from AppDelegate.applicationDidFinishLaunching
    func setup() {
        setupNotificationObservers()
        setupRemoteCommandCenter()
        NSLog("NowPlayingManager: Setup complete")
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Track changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackDidChange(_:)),
            name: .audioTrackDidChange,
            object: nil
        )
        
        // Playback state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged(_:)),
            name: .audioPlaybackStateChanged,
            object: nil
        )
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleTrackDidChange(_ notification: Notification) {
        let track = notification.userInfo?["track"] as? Track
        updateNowPlayingInfo(for: track)
    }
    
    @objc private func handlePlaybackStateChanged(_ notification: Notification) {
        guard let state = notification.userInfo?["state"] as? PlaybackState else { return }
        updatePlaybackState(state)
        
        // Also update elapsed time when state changes
        updateElapsedTime()
    }
    
    // MARK: - Now Playing Info Updates
    
    private func updateNowPlayingInfo(for track: Track?) {
        guard let track = track else {
            clearNowPlayingInfo()
            return
        }
        
        // Build now playing info dictionary
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: 1.0),
            MPNowPlayingInfoPropertyDefaultPlaybackRate: NSNumber(value: 1.0)
        ]
        
        // Artist (optional)
        if let artist = track.artist, !artist.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        // Album (optional)
        if let album = track.album, !album.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        }
        
        // Duration
        if let duration = track.duration, duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: duration)
        }
        
        // Elapsed time
        let currentTime = WindowManager.shared.audioEngine.currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: currentTime)
        
        // Preserve existing artwork if we already have it for this track
        if track.id == currentTrackId, let artwork = currentArtwork {
            let artworkItem = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                return artwork
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artworkItem
        }
        
        // Apply info immediately (artwork loaded async if not cached)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        // Update playback state
        let state = WindowManager.shared.audioEngine.state
        updatePlaybackState(state)
        
        // Load artwork asynchronously (will skip if already cached for this track)
        loadArtwork(for: track)
        
        NSLog("NowPlayingManager: Updated now playing - %@ by %@", track.title, track.artist ?? "Unknown")
    }
    
    private func updatePlaybackState(_ state: PlaybackState) {
        // CRITICAL: On macOS, must explicitly set playbackState
        // This is required for Control Center integration
        switch state {
        case .playing:
            MPNowPlayingInfoCenter.default().playbackState = .playing
        case .paused:
            MPNowPlayingInfoCenter.default().playbackState = .paused
        case .stopped:
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        
        // Update playback rate in info dictionary
        if var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: state == .playing ? 1.0 : 0.0)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    private func updateElapsedTime() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        
        let currentTime = WindowManager.shared.audioEngine.currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: currentTime)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func clearNowPlayingInfo() {
        // Cancel any pending artwork load
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        currentArtwork = nil
        currentTrackId = nil
        
        // Clear now playing
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        
        NSLog("NowPlayingManager: Cleared now playing info")
    }
    
    // MARK: - Remote Command Center
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handlePlayCommand()
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handlePauseCommand()
            return .success
        }
        
        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleTogglePlayPauseCommand()
            return .success
        }
        
        // Next track
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.handleNextTrackCommand()
            return .success
        }
        
        // Previous track
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.handlePreviousTrackCommand()
            return .success
        }
        
        // Seek (scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.handleSeekCommand(to: positionEvent.positionTime)
            return .success
        }
        
        NSLog("NowPlayingManager: Remote command center configured")
    }
    
    // MARK: - Command Handlers
    
    private func handlePlayCommand() {
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.play()
        }
    }
    
    private func handlePauseCommand() {
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.pause()
        }
    }
    
    private func handleTogglePlayPauseCommand() {
        DispatchQueue.main.async {
            let engine = WindowManager.shared.audioEngine
            if engine.state == .playing {
                engine.pause()
            } else {
                engine.play()
            }
        }
    }
    
    private func handleNextTrackCommand() {
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.next()
        }
    }
    
    private func handlePreviousTrackCommand() {
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.previous()
        }
    }
    
    private func handleSeekCommand(to position: TimeInterval) {
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.seek(to: position)
        }
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork(for track: Track) {
        // Skip if same track (artwork already loaded)
        if track.id == currentTrackId && currentArtwork != nil {
            return
        }
        
        // Cancel previous load
        artworkLoadTask?.cancel()
        currentTrackId = track.id
        
        artworkLoadTask = Task { [weak self] in
            guard let self = self else { return }
            
            var image: NSImage?
            
            // Load based on track source
            if track.url.isFileURL {
                // Local file - extract embedded artwork
                image = await self.loadLocalArtwork(url: track.url)
            } else if track.plexRatingKey != nil {
                // Plex track - load from server
                if let thumb = track.artworkThumb {
                    NSLog("NowPlayingManager: Loading Plex artwork, thumb=%@", thumb)
                    image = await self.loadPlexArtwork(thumb: thumb)
                    if image == nil {
                        NSLog("NowPlayingManager: Plex artwork load returned nil")
                    }
                } else {
                    NSLog("NowPlayingManager: Plex track has no artworkThumb")
                }
            } else if track.subsonicId != nil {
                // Subsonic track - load cover art
                if let coverArt = track.artworkThumb {
                    image = await self.loadSubsonicArtwork(coverArt: coverArt)
                }
            }
            
            // Check if cancelled
            guard !Task.isCancelled else { return }
            
            // Capture image value for MainActor closure (Swift 6 compatibility)
            let loadedImage = image
            
            // Update Now Playing with artwork on main thread
            await MainActor.run {
                self.currentArtwork = loadedImage
                self.applyArtworkToNowPlaying(loadedImage)
            }
        }
    }
    
    private func applyArtworkToNowPlaying(_ image: NSImage?) {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        
        if let image = image {
            // Create MPMediaItemArtwork from NSImage
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                return image
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            NSLog("NowPlayingManager: Applied artwork (%.0fx%.0f)", image.size.width, image.size.height)
        } else {
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - Artwork Loading Helpers
    
    /// Load embedded artwork from local audio file
    private func loadLocalArtwork(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        
        do {
            let metadata = try await asset.load(.metadata)
            
            for item in metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        return image
                    }
                }
            }
            
            // Check ID3 metadata
            let id3Metadata = try await asset.loadMetadata(for: .id3Metadata)
            for item in id3Metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        return image
                    }
                }
            }
            
            // Check iTunes metadata
            let itunesMetadata = try await asset.loadMetadata(for: .iTunesMetadata)
            for item in itunesMetadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        return image
                    }
                }
            }
        } catch {
            NSLog("NowPlayingManager: Failed to load local artwork: %@", error.localizedDescription)
        }
        
        return nil
    }
    
    /// Load artwork from Plex server
    private func loadPlexArtwork(thumb: String) async -> NSImage? {
        guard let artworkURL = PlexManager.shared.artworkURL(thumb: thumb, size: 400) else {
            NSLog("NowPlayingManager: PlexManager.artworkURL returned nil for thumb=%@", thumb)
            return nil
        }
        
        NSLog("NowPlayingManager: Fetching Plex artwork from %@", artworkURL.absoluteString)
        
        do {
            var request = URLRequest(url: artworkURL)
            if let headers = PlexManager.shared.streamingHeaders {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("NowPlayingManager: Plex artwork response is not HTTP")
                return nil
            }
            
            NSLog("NowPlayingManager: Plex artwork HTTP status=%d, size=%d bytes", httpResponse.statusCode, data.count)
            
            guard httpResponse.statusCode == 200 else {
                return nil
            }
            
            let image = NSImage(data: data)
            if image == nil {
                NSLog("NowPlayingManager: Failed to create NSImage from Plex artwork data")
            }
            return image
        } catch {
            NSLog("NowPlayingManager: Failed to load Plex artwork: %@", error.localizedDescription)
            return nil
        }
    }
    
    /// Load cover art from Subsonic server
    private func loadSubsonicArtwork(coverArt: String) async -> NSImage? {
        guard let artworkURL = SubsonicManager.shared.coverArtURL(coverArtId: coverArt, size: 400) else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: artworkURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            return NSImage(data: data)
        } catch {
            NSLog("NowPlayingManager: Failed to load Subsonic artwork: %@", error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Periodic Time Update
    
    /// Call this periodically (e.g., every second) to keep elapsed time in sync
    /// Optional: Hook into existing time update timer in AudioEngine if more precision needed
    func periodicTimeUpdate() {
        updateElapsedTime()
    }
}
