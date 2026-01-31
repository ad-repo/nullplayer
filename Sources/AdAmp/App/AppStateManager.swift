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
        
        // Sweet Fades (crossfade) settings
        // Default values ensure backward compatibility with saved states from older versions
        var sweetFadeEnabled: Bool = false
        var sweetFadeDuration: Double = 5.0
        
        // EQ settings
        var eqEnabled: Bool
        var eqAutoEnabled: Bool = false
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
        var baseSkinIndex: Int?  // 1, 2, or 3 for base skins; nil for custom skin
        
        // Milkdrop preset
        var milkdropPresetIndex: Int?
        
        // Version for future compatibility
        var stateVersion: Int = 1
        
        // MARK: - Custom Decoding for Backward Compatibility
        
        enum CodingKeys: String, CodingKey {
            case isPlaylistVisible, isEqualizerVisible, isPlexBrowserVisible, isMilkdropVisible
            case mainWindowFrame, playlistWindowFrame, equalizerWindowFrame, plexBrowserWindowFrame, milkdropWindowFrame
            case volume, balance, shuffleEnabled, repeatEnabled, gaplessPlaybackEnabled, volumeNormalizationEnabled
            case sweetFadeEnabled, sweetFadeDuration
            case eqEnabled, eqAutoEnabled, eqPreamp, eqBands
            case playlistURLs, currentTrackIndex, playbackPosition, wasPlaying
            case timeDisplayMode, isAlwaysOnTop
            case customSkinPath, baseSkinIndex
            case milkdropPresetIndex
            case stateVersion
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Window visibility
            isPlaylistVisible = try container.decode(Bool.self, forKey: .isPlaylistVisible)
            isEqualizerVisible = try container.decode(Bool.self, forKey: .isEqualizerVisible)
            isPlexBrowserVisible = try container.decode(Bool.self, forKey: .isPlexBrowserVisible)
            isMilkdropVisible = try container.decode(Bool.self, forKey: .isMilkdropVisible)
            
            // Window frames
            mainWindowFrame = try container.decodeIfPresent(String.self, forKey: .mainWindowFrame)
            playlistWindowFrame = try container.decodeIfPresent(String.self, forKey: .playlistWindowFrame)
            equalizerWindowFrame = try container.decodeIfPresent(String.self, forKey: .equalizerWindowFrame)
            plexBrowserWindowFrame = try container.decodeIfPresent(String.self, forKey: .plexBrowserWindowFrame)
            milkdropWindowFrame = try container.decodeIfPresent(String.self, forKey: .milkdropWindowFrame)
            
            // Audio settings
            volume = try container.decode(Float.self, forKey: .volume)
            balance = try container.decode(Float.self, forKey: .balance)
            shuffleEnabled = try container.decode(Bool.self, forKey: .shuffleEnabled)
            repeatEnabled = try container.decode(Bool.self, forKey: .repeatEnabled)
            gaplessPlaybackEnabled = try container.decode(Bool.self, forKey: .gaplessPlaybackEnabled)
            volumeNormalizationEnabled = try container.decode(Bool.self, forKey: .volumeNormalizationEnabled)
            
            // Sweet Fades - use defaults for backward compatibility with older saved states
            sweetFadeEnabled = try container.decodeIfPresent(Bool.self, forKey: .sweetFadeEnabled) ?? false
            sweetFadeDuration = try container.decodeIfPresent(Double.self, forKey: .sweetFadeDuration) ?? 5.0
            
            // EQ settings
            eqEnabled = try container.decode(Bool.self, forKey: .eqEnabled)
            eqAutoEnabled = try container.decodeIfPresent(Bool.self, forKey: .eqAutoEnabled) ?? false
            eqPreamp = try container.decode(Float.self, forKey: .eqPreamp)
            eqBands = try container.decode([Float].self, forKey: .eqBands)
            
            // Playback state
            playlistURLs = try container.decode([String].self, forKey: .playlistURLs)
            currentTrackIndex = try container.decode(Int.self, forKey: .currentTrackIndex)
            playbackPosition = try container.decode(Double.self, forKey: .playbackPosition)
            wasPlaying = try container.decode(Bool.self, forKey: .wasPlaying)
            
            // UI preferences
            timeDisplayMode = try container.decode(String.self, forKey: .timeDisplayMode)
            isAlwaysOnTop = try container.decode(Bool.self, forKey: .isAlwaysOnTop)
            
            // Skin
            customSkinPath = try container.decodeIfPresent(String.self, forKey: .customSkinPath)
            baseSkinIndex = try container.decodeIfPresent(Int.self, forKey: .baseSkinIndex)
            
            // Milkdrop preset - nil for backward compatibility with older saved states
            milkdropPresetIndex = try container.decodeIfPresent(Int.self, forKey: .milkdropPresetIndex)
            
            // Version
            stateVersion = try container.decodeIfPresent(Int.self, forKey: .stateVersion) ?? 1
        }
        
        // Standard memberwise initializer for saving state
        init(
            isPlaylistVisible: Bool,
            isEqualizerVisible: Bool,
            isPlexBrowserVisible: Bool,
            isMilkdropVisible: Bool,
            mainWindowFrame: String?,
            playlistWindowFrame: String?,
            equalizerWindowFrame: String?,
            plexBrowserWindowFrame: String?,
            milkdropWindowFrame: String?,
            volume: Float,
            balance: Float,
            shuffleEnabled: Bool,
            repeatEnabled: Bool,
            gaplessPlaybackEnabled: Bool,
            volumeNormalizationEnabled: Bool,
            sweetFadeEnabled: Bool,
            sweetFadeDuration: Double,
            eqEnabled: Bool,
            eqAutoEnabled: Bool,
            eqPreamp: Float,
            eqBands: [Float],
            playlistURLs: [String],
            currentTrackIndex: Int,
            playbackPosition: Double,
            wasPlaying: Bool,
            timeDisplayMode: String,
            isAlwaysOnTop: Bool,
            customSkinPath: String? = nil,
            baseSkinIndex: Int? = nil,
            milkdropPresetIndex: Int? = nil,
            stateVersion: Int = 1
        ) {
            self.isPlaylistVisible = isPlaylistVisible
            self.isEqualizerVisible = isEqualizerVisible
            self.isPlexBrowserVisible = isPlexBrowserVisible
            self.isMilkdropVisible = isMilkdropVisible
            self.mainWindowFrame = mainWindowFrame
            self.playlistWindowFrame = playlistWindowFrame
            self.equalizerWindowFrame = equalizerWindowFrame
            self.plexBrowserWindowFrame = plexBrowserWindowFrame
            self.milkdropWindowFrame = milkdropWindowFrame
            self.volume = volume
            self.balance = balance
            self.shuffleEnabled = shuffleEnabled
            self.repeatEnabled = repeatEnabled
            self.gaplessPlaybackEnabled = gaplessPlaybackEnabled
            self.volumeNormalizationEnabled = volumeNormalizationEnabled
            self.sweetFadeEnabled = sweetFadeEnabled
            self.sweetFadeDuration = sweetFadeDuration
            self.eqEnabled = eqEnabled
            self.eqAutoEnabled = eqAutoEnabled
            self.eqPreamp = eqPreamp
            self.eqBands = eqBands
            self.playlistURLs = playlistURLs
            self.currentTrackIndex = currentTrackIndex
            self.playbackPosition = playbackPosition
            self.wasPlaying = wasPlaying
            self.timeDisplayMode = timeDisplayMode
            self.isAlwaysOnTop = isAlwaysOnTop
            self.customSkinPath = customSkinPath
            self.baseSkinIndex = baseSkinIndex
            self.milkdropPresetIndex = milkdropPresetIndex
            self.stateVersion = stateVersion
        }
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
            
            // Sweet Fades settings
            sweetFadeEnabled: engine.sweetFadeEnabled,
            sweetFadeDuration: engine.sweetFadeDuration,
            
            // EQ settings
            eqEnabled: engine.isEQEnabled(),
            eqAutoEnabled: UserDefaults.standard.bool(forKey: "EQAutoEnabled"),
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
            
            // Skin - save path if using a custom skin, or base skin index
            customSkinPath: getCustomSkinPath(),
            baseSkinIndex: wm.currentBaseSkinIndex,
            
            // Milkdrop preset
            milkdropPresetIndex: wm.visualizationPresetIndex
        )
        
        // Encode and save
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: Keys.savedAppState)
            NSLog("AppStateManager: Saved state - playlist: %d tracks, position: %.1fs, volume: %.2f, alwaysOnTop: %d",
                  state.playlistURLs.count, state.playbackPosition, state.volume, state.isAlwaysOnTop ? 1 : 0)
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
    
    /// Restore only settings state (skin, volume, EQ, windows) - call before intro
    /// This allows the intro to play with the user's preferred settings
    func restoreSettingsState() {
        guard isEnabled else {
            NSLog("AppStateManager: Remember State disabled, skipping settings restore")
            return
        }
        
        guard let data = UserDefaults.standard.data(forKey: Keys.savedAppState) else {
            NSLog("AppStateManager: No saved state found for settings restore")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let state = try decoder.decode(AppState.self, from: data)
            applySettingsState(state)
        } catch {
            NSLog("AppStateManager: Failed to restore settings state: %@", error.localizedDescription)
        }
    }
    
    /// Restore only playlist state - call after intro finishes
    func restorePlaylistState() {
        guard isEnabled else {
            NSLog("AppStateManager: Remember State disabled, skipping playlist restore")
            return
        }
        
        guard let data = UserDefaults.standard.data(forKey: Keys.savedAppState) else {
            NSLog("AppStateManager: No saved state found for playlist restore")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let state = try decoder.decode(AppState.self, from: data)
            applyPlaylistState(state)
        } catch {
            NSLog("AppStateManager: Failed to restore playlist state: %@", error.localizedDescription)
        }
    }
    
    /// Apply settings state (skin, volume, EQ, windows) - no playlist
    private func applySettingsState(_ state: AppState) {
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        
        NSLog("AppStateManager: Restoring settings state - volume: %.2f", state.volume)
        
        // Restore audio settings
        engine.volume = state.volume
        engine.balance = state.balance
        engine.shuffleEnabled = state.shuffleEnabled
        engine.repeatEnabled = state.repeatEnabled
        engine.gaplessPlaybackEnabled = state.gaplessPlaybackEnabled
        engine.volumeNormalizationEnabled = state.volumeNormalizationEnabled
        
        // Restore Sweet Fades settings
        engine.sweetFadeEnabled = state.sweetFadeEnabled
        engine.sweetFadeDuration = state.sweetFadeDuration
        
        // Restore EQ settings
        engine.setEQEnabled(state.eqEnabled)
        UserDefaults.standard.set(state.eqAutoEnabled, forKey: "EQAutoEnabled")
        engine.setPreamp(state.eqPreamp)
        for (index, gain) in state.eqBands.enumerated() {
            engine.setEQBand(index, gain: gain)
        }
        
        // Restore UI preferences
        if let mode = TimeDisplayMode(rawValue: state.timeDisplayMode) {
            wm.timeDisplayMode = mode
        }
        NSLog("AppStateManager: Restoring isAlwaysOnTop = %d", state.isAlwaysOnTop ? 1 : 0)
        wm.isAlwaysOnTop = state.isAlwaysOnTop
        
        // Restore skin
        if let skinPath = state.customSkinPath {
            let skinURL = URL(fileURLWithPath: skinPath)
            if FileManager.default.fileExists(atPath: skinPath) {
                wm.loadSkin(from: skinURL)
            }
        } else if let baseSkinIndex = state.baseSkinIndex {
            switch baseSkinIndex {
            case 1: wm.loadBaseSkin()
            case 2: wm.loadBaseSkin2()
            case 3: wm.loadBaseSkin3()
            default: wm.loadBaseSkin()
            }
        }
        
        // Restore window frames
        restoreWindowFrames(state)
        
        // Restore window visibility (after a short delay to ensure proper positioning)
        // Parse frames before the closure to avoid capturing state
        let playlistFrame = state.playlistWindowFrame.flatMap { NSRectFromString($0) }
        let equalizerFrame = state.equalizerWindowFrame.flatMap { NSRectFromString($0) }
        let browserFrame = state.plexBrowserWindowFrame.flatMap { NSRectFromString($0) }
        let milkdropFrame = state.milkdropWindowFrame.flatMap { NSRectFromString($0) }
        let milkdropPresetIndex = state.milkdropPresetIndex
        
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
                
                // Restore Milkdrop preset after engine is initialized on render thread
                // The engine setup is deferred and takes ~200ms to complete
                if let presetIndex = milkdropPresetIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        wm.selectVisualizationPreset(at: presetIndex)
                        NSLog("AppStateManager: Restored Milkdrop preset index: %d", presetIndex)
                    }
                }
            }
        }
        
        NSLog("AppStateManager: Settings state restored (eqAutoEnabled: %d)", state.eqAutoEnabled ? 1 : 0)
    }
    
    /// Apply playlist state only
    /// Populates the playlist but does NOT load or play any track
    private func applyPlaylistState(_ state: AppState) {
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        
        guard !state.playlistURLs.isEmpty else {
            NSLog("AppStateManager: No playlist to restore")
            return
        }
        
        NSLog("AppStateManager: Restoring playlist state - %d tracks", state.playlistURLs.count)
        
        let urls = state.playlistURLs.compactMap { URL(string: $0) }
        
        // Use setPlaylistFiles which populates the playlist without auto-playing
        engine.setPlaylistFiles(urls)
        
        NSLog("AppStateManager: Playlist state restored")
    }
    
    /// Apply the restored state to the app (full restore - used by restoreState())
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
        
        // Restore Sweet Fades settings
        engine.sweetFadeEnabled = state.sweetFadeEnabled
        engine.sweetFadeDuration = state.sweetFadeDuration
        
        // Restore EQ settings
        engine.setEQEnabled(state.eqEnabled)
        UserDefaults.standard.set(state.eqAutoEnabled, forKey: "EQAutoEnabled")
        engine.setPreamp(state.eqPreamp)
        for (index, gain) in state.eqBands.enumerated() {
            engine.setEQBand(index, gain: gain)
        }
        
        // Restore UI preferences
        if let mode = TimeDisplayMode(rawValue: state.timeDisplayMode) {
            wm.timeDisplayMode = mode
        }
        NSLog("AppStateManager: Restoring isAlwaysOnTop = %d", state.isAlwaysOnTop ? 1 : 0)
        wm.isAlwaysOnTop = state.isAlwaysOnTop
        
        // Restore skin
        if let skinPath = state.customSkinPath {
            // Custom skin from file
            let skinURL = URL(fileURLWithPath: skinPath)
            if FileManager.default.fileExists(atPath: skinPath) {
                wm.loadSkin(from: skinURL)
            }
        } else if let baseSkinIndex = state.baseSkinIndex {
            // Base skin by index
            switch baseSkinIndex {
            case 1: wm.loadBaseSkin()
            case 2: wm.loadBaseSkin2()
            case 3: wm.loadBaseSkin3()
            default: wm.loadBaseSkin()
            }
        }
        
        // Restore window frames
        restoreWindowFrames(state)
        
        // Restore playlist (only populate, don't select or play any track)
        if !state.playlistURLs.isEmpty {
            let urls = state.playlistURLs.compactMap { URL(string: $0) }
            // Use setPlaylistFiles which populates the playlist without auto-playing
            engine.setPlaylistFiles(urls)
            NSLog("AppStateManager: Playlist restored")
        }
        
        // Restore window visibility (after a short delay to ensure proper positioning)
        // Parse frames before the closure to avoid capturing state
        let playlistFrame = state.playlistWindowFrame.flatMap { NSRectFromString($0) }
        let equalizerFrame = state.equalizerWindowFrame.flatMap { NSRectFromString($0) }
        let browserFrame = state.plexBrowserWindowFrame.flatMap { NSRectFromString($0) }
        let milkdropFrame = state.milkdropWindowFrame.flatMap { NSRectFromString($0) }
        let milkdropPresetIndex = state.milkdropPresetIndex
        
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
                
                // Restore Milkdrop preset after engine is initialized on render thread
                // The engine setup is deferred and takes ~200ms to complete
                if let presetIndex = milkdropPresetIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        wm.selectVisualizationPreset(at: presetIndex)
                        NSLog("AppStateManager: Restored Milkdrop preset index: %d", presetIndex)
                    }
                }
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
