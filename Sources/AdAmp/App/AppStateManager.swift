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
            milkdropWindowFrame: wm.isMilkdropVisible ? getMilkdropFrame().map { NSStringFromRect($0) } : nil,
            
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
            playlistURLs: engine.playlist.compactMap { track -> String? in
                // Only save local file URLs, not streaming URLs
                guard track.url.isFileURL else { return nil }
                return track.url.absoluteString
            },
            currentTrackIndex: engine.currentIndex,
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
                engine.loadFiles(validURLs)
                
                // Restore track position after a short delay to let the playlist load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Set the current track index
                    if state.currentTrackIndex >= 0 && state.currentTrackIndex < engine.playlist.count {
                        engine.playTrack(at: state.currentTrackIndex)
                        
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if state.isEqualizerVisible {
                wm.showEqualizer()
            }
            if state.isPlaylistVisible {
                wm.showPlaylist()
            }
            if state.isPlexBrowserVisible {
                wm.showPlexBrowser()
            }
            if state.isMilkdropVisible {
                wm.showMilkdrop()
            }
        }
        
        NSLog("AppStateManager: State restored successfully")
    }
    
    /// Restore window frames from saved state
    private func restoreWindowFrames(_ state: AppState) {
        let wm = WindowManager.shared
        
        if let frameString = state.mainWindowFrame,
           let window = wm.mainWindowController?.window {
            let frame = NSRectFromString(frameString)
            if frame != .zero {
                window.setFrame(frame, display: true)
            }
        }
        
        if let frameString = state.playlistWindowFrame,
           let window = wm.playlistWindowController?.window {
            let frame = NSRectFromString(frameString)
            if frame != .zero {
                window.setFrame(frame, display: true)
            }
        }
        
        if let frameString = state.equalizerWindowFrame,
           let window = wm.equalizerWindowController?.window {
            let frame = NSRectFromString(frameString)
            if frame != .zero {
                window.setFrame(frame, display: true)
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Get the custom skin path if a non-default skin is loaded
    private func getCustomSkinPath() -> String? {
        // Return the currently loaded custom skin path tracked by WindowManager
        return WindowManager.shared.currentSkinPath
    }
    
    /// Get the Milkdrop window frame
    private func getMilkdropFrame() -> NSRect? {
        // Access via window manager's internal method or property
        // Since we can't directly access milkdropWindowController, 
        // we rely on the saved frame in UserDefaults
        if let frameString = UserDefaults.standard.string(forKey: "MilkdropWindowFrame") {
            return NSRectFromString(frameString)
        }
        return nil
    }
    
    // MARK: - Clear State
    
    /// Clear the saved state
    func clearSavedState() {
        UserDefaults.standard.removeObject(forKey: Keys.savedAppState)
        NSLog("AppStateManager: Cleared saved state")
    }
}
