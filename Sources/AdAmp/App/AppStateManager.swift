import AppKit

/// Manages saving and restoring the complete application state
/// When "Remember State" is enabled, saves app state on quit and restores on launch
class AppStateManager {
    
    // MARK: - Singleton
    
    static let shared = AppStateManager()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let rememberStateEnabled = "rememberStateEnabled"
        static let savedAppState = "savedAppState"
    }
    
    // MARK: - State Structure
    
    /// Complete application state that can be saved/restored
    struct AppState: Codable {
        // Window visibility
        var isPlaylistVisible: Bool
        var isEqualizerVisible: Bool
        var isPlexBrowserVisible: Bool
        var isMilkdropVisible: Bool
        
        // Window frames (as strings for NSRect compatibility)
        var mainWindowFrame: String?
        var playlistWindowFrame: String?
        var equalizerWindowFrame: String?
        var plexBrowserWindowFrame: String?
        var milkdropWindowFrame: String?
        
        // Audio settings
        var volume: Float
        var balance: Float
        var shuffleEnabled: Bool
        var repeatEnabled: Bool
        var gaplessPlaybackEnabled: Bool
        var volumeNormalizationEnabled: Bool
        
        // EQ settings
        var eqEnabled: Bool
        var eqPreamp: Float
        var eqBands: [Float]
        
        // Playback state
        var playlistURLs: [String]  // File URLs as strings
        var currentTrackIndex: Int
        var playbackPosition: Double  // Position in seconds
        var wasPlaying: Bool
        
        // UI preferences
        var timeDisplayMode: String
        var isAlwaysOnTop: Bool
        
        // Skin
        var customSkinPath: String?
        
        // Version for future compatibility
        var stateVersion: Int = 1
    }
    
    // MARK: - Properties
    
    /// Whether the "Remember State" feature is enabled
    var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: Keys.rememberStateEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.rememberStateEnabled)
            NSLog("AppStateManager: Remember State %@", newValue ? "enabled" : "disabled")
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Register default value (disabled by default)
        UserDefaults.standard.register(defaults: [
            Keys.rememberStateEnabled: false
        ])
    }
    
    // MARK: - Save State
    
    /// Save the current application state
    func saveState() {
        guard isEnabled else {
            NSLog("AppStateManager: Remember State disabled, skipping save")
            return
        }
        
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        
        // Capture window visibility
        let state = AppState(
            // Window visibility
            isPlaylistVisible: wm.isPlaylistVisible,
            isEqualizerVisible: wm.isEqualizerVisible,
            isPlexBrowserVisible: wm.isPlexBrowserVisible,
            isMilkdropVisible: wm.isMilkdropVisible,
            
            // Window frames
            mainWindowFrame: wm.mainWindowController?.window.map { NSStringFromRect($0.frame) },
            playlistWindowFrame: wm.playlistWindowController?.window.map { NSStringFromRect($0.frame) },
            equalizerWindowFrame: wm.equalizerWindowController?.window.map { NSStringFromRect($0.frame) },
            plexBrowserWindowFrame: wm.plexBrowserWindowFrame.map { NSStringFromRect($0) },
            milkdropWindowFrame: wm.isMilkdropVisible ? wm.milkdropWindowFrame.map { NSStringFromRect($0) } : nil,
            
            // Audio settings
            volume: engine.volume,
            balance: engine.balance,
            shuffleEnabled: engine.shuffleEnabled,
            repeatEnabled: engine.repeatEnabled,
            gaplessPlaybackEnabled: engine.gaplessPlaybackEnabled,
            volumeNormalizationEnabled: engine.volumeNormalizationEnabled,
            
            // EQ settings
            eqEnabled: engine.isEQEnabled(),
            eqPreamp: engine.getPreamp(),
            eqBands: (0..<10).map { engine.getEQBand($0) },
            
            // Playback state - only save local file URLs (not streaming)
            // Build filtered list and calculate correct index within it
            playlistURLs: {
                // Get only local file URLs
                let localURLs = engine.playlist.compactMap { track -> String? in
                    guard track.url.isFileURL else { return nil }
                    return track.url.absoluteString
                }
                return localURLs
            }(),
            currentTrackIndex: {
                // Calculate the index within the filtered local-only playlist
                // The saved index must correspond to the filtered playlistURLs, not the full playlist
                guard engine.currentIndex >= 0 && engine.currentIndex < engine.playlist.count else {
                    return -1
                }
                let currentTrack = engine.playlist[engine.currentIndex]
                guard currentTrack.url.isFileURL else {
                    // Current track is a streaming track, can't restore it
                    return -1
                }
                // Count how many local file tracks come before the current one
                var localIndex = 0
                for i in 0..<engine.currentIndex {
                    if engine.playlist[i].url.isFileURL {
                        localIndex += 1
                    }
                }
                return localIndex
            }(),
            playbackPosition: engine.currentTime,
            wasPlaying: engine.state == .playing,
            
            // UI preferences
            timeDisplayMode: wm.timeDisplayMode.rawValue,
            isAlwaysOnTop: wm.isAlwaysOnTop,
            
            // Skin - save path if using a custom skin
            customSkinPath: getCustomSkinPath()
        )
        
        // Encode and save
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: Keys.savedAppState)
            NSLog("AppStateManager: Saved state - playlist: %d tracks, position: %.1fs, volume: %.2f",
                  state.playlistURLs.count, state.playbackPosition, state.volume)
        } catch {
            NSLog("AppStateManager: Failed to save state: %@", error.localizedDescription)
        }
    }
    
    // MARK: - Restore State
    
    /// Restore the previously saved application state
    /// Call this after windows are created but before showing them
    /// - Returns: true if state was restored (has playlist), false otherwise
    @discardableResult
    func restoreState() -> Bool {
        guard isEnabled else {
            NSLog("AppStateManager: Remember State disabled, skipping restore")
            return false
        }
        
        guard let data = UserDefaults.standard.data(forKey: Keys.savedAppState) else {
            NSLog("AppStateManager: No saved state found")
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            let state = try decoder.decode(AppState.self, from: data)
            let hasPlaylist = !state.playlistURLs.isEmpty
            applyState(state)
            return hasPlaylist
        } catch {
            NSLog("AppStateManager: Failed to restore state: %@", error.localizedDescription)
            return false
        }
    }
    
    /// Apply the restored state to the app
    private func applyState(_ state: AppState) {
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        
        NSLog("AppStateManager: Restoring state - playlist: %d tracks, volume: %.2f",
              state.playlistURLs.count, state.volume)
        
        // Restore audio settings first (before loading playlist)
        engine.volume = state.volume
        engine.balance = state.balance
        engine.shuffleEnabled = state.shuffleEnabled
        engine.repeatEnabled = state.repeatEnabled
        engine.gaplessPlaybackEnabled = state.gaplessPlaybackEnabled
        engine.volumeNormalizationEnabled = state.volumeNormalizationEnabled
        
        // Restore EQ settings
        engine.setEQEnabled(state.eqEnabled)
        engine.setPreamp(state.eqPreamp)
        for (index, gain) in state.eqBands.enumerated() {
            engine.setEQBand(index, gain: gain)
        }
        
        // Restore UI preferences
        if let mode = TimeDisplayMode(rawValue: state.timeDisplayMode) {
            wm.timeDisplayMode = mode
        }
        wm.isAlwaysOnTop = state.isAlwaysOnTop
        
        // Restore custom skin if set
        if let skinPath = state.customSkinPath {
            let skinURL = URL(fileURLWithPath: skinPath)
            if FileManager.default.fileExists(atPath: skinPath) {
                wm.loadSkin(from: skinURL)
            }
        }
        
        // Restore window frames
        restoreWindowFrames(state)
        
        // Restore playlist
        if !state.playlistURLs.isEmpty {
            let urls = state.playlistURLs.compactMap { URL(string: $0) }
            let validURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            
            if !validURLs.isEmpty {
                // Calculate the correct index in the filtered playlist
                // The saved index was relative to the full saved list, but some files may have been deleted
                var newTrackIndex = -1
                if state.currentTrackIndex >= 0 && state.currentTrackIndex < urls.count {
                    let originalURL = urls[state.currentTrackIndex]
                    // Find where this URL ended up in the filtered list
                    if let validIndex = validURLs.firstIndex(of: originalURL) {
                        newTrackIndex = validIndex
                    }
                }
                
                engine.loadFiles(validURLs)
                
                // Restore track position after a short delay to let the playlist load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Set the current track index (use the recalculated index for the filtered playlist)
                    if newTrackIndex >= 0 && newTrackIndex < engine.playlist.count {
                        engine.playTrack(at: newTrackIndex)
                        
                        // Seek to the saved position
                        if state.playbackPosition > 0 {
                            engine.seek(to: state.playbackPosition)
                        }
                        
                        // Pause if it wasn't playing when saved
                        if !state.wasPlaying {
                            engine.pause()
                        }
                    }
                }
            }
        }
        
        // Restore window visibility (after a short delay to ensure proper positioning)
        // Parse frames before the closure to avoid capturing state
        let playlistFrame = state.playlistWindowFrame.flatMap { NSRectFromString($0) }
        let equalizerFrame = state.equalizerWindowFrame.flatMap { NSRectFromString($0) }
        let browserFrame = state.plexBrowserWindowFrame.flatMap { NSRectFromString($0) }
        let milkdropFrame = state.milkdropWindowFrame.flatMap { NSRectFromString($0) }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if state.isEqualizerVisible {
                wm.showEqualizer(at: equalizerFrame)
            }
            if state.isPlaylistVisible {
                wm.showPlaylist(at: playlistFrame)
            }
            if state.isPlexBrowserVisible {
                wm.showPlexBrowser(at: browserFrame)
            }
            if state.isMilkdropVisible {
                wm.showMilkdrop(at: milkdropFrame)
            }
        }
        
        NSLog("AppStateManager: State restored successfully")
    }
    
    /// Restore window frames from saved state
    /// Note: Only the main window frame is restored here since it exists at restore time.
    /// Playlist, EQ, Browser, and Milkdrop frames are passed to their show methods
    /// in applyState() since those windows are created lazily.
    private func restoreWindowFrames(_ state: AppState) {
        let wm = WindowManager.shared
        
        // Main window exists at this point, so we can restore its frame directly
        if let frameString = state.mainWindowFrame,
           let window = wm.mainWindowController?.window {
            let frame = NSRectFromString(frameString)
            if frame != .zero {
                window.setFrame(frame, display: true)
            }
        }
        
        // Note: Playlist, EQ, Browser, and Milkdrop frames are passed directly to their
        // show methods in applyState() since those windows are created lazily and don't
        // exist yet when this function is called.
    }
    
    // MARK: - Helpers
    
    /// Get the custom skin path if a non-default skin is loaded
    private func getCustomSkinPath() -> String? {
        // Return the currently loaded custom skin path tracked by WindowManager
        return WindowManager.shared.currentSkinPath
    }
    
    // MARK: - Clear State
    
    /// Clear the saved state
    func clearSavedState() {
        UserDefaults.standard.removeObject(forKey: Keys.savedAppState)
        NSLog("AppStateManager: Cleared saved state")
    }
}
