import AppKit
import NullPlayerCore

/// Manages saving and restoring the complete application state.
/// When "Remember State On Quit" is enabled (context menu toggle), saves app state
/// on quit and restores on launch.
///
/// ## Saved State (AppState struct, v2)
/// - **Window visibility**: playlist, EQ, browser, ProjectM, spectrum, waveform
/// - **Window frames**: main, playlist, EQ, browser, ProjectM, spectrum, waveform; ProjectM fullscreen
/// - **Audio**: volume, balance, shuffle, repeat, gapless, normalization
/// - **Sweet Fades**: enabled, duration
/// - **EQ**: enabled, auto, preamp, active-layout bands (10 classic / 21 modern)
/// - **Playlist**: all tracks (local, Plex, Subsonic, Jellyfin, radio) with metadata
/// - **Playback position**: current track index, position in seconds
/// - **Skins**: timeDisplayMode, isAlwaysOnTop, double size mode (modern UI)
/// - **Skin**: classic custom skin path, modern skin name
/// - **ProjectM**: preset index, fullscreen state
/// - **Audio output**: selected device UID
/// - **Browser**: browse mode (artists/albums/tracks/etc.)
/// - **UI mode**: which mode (modern/classic) the state was saved in
///
/// ## Restoration Flow
/// 1. `restoreSettingsState()` - called early in launch (skin, volume, EQ, windows, v2 fields)
/// 2. `restorePlaylistState()` - called after app is ready (tracks, current position)
///
/// Streaming tracks (Plex/Subsonic/Jellyfin) are initially loaded as placeholders with
/// saved metadata (title/artist/album/duration), then replaced asynchronously when the
/// real tracks are fetched from their servers.
///
/// When the UI mode changes between save and restore (e.g. modern -> classic), window
/// frames are NOT restored (they have incompatible sizes). Audio, playlist, and non-frame
/// settings are still restored normally.
///
/// ## Independent UserDefaults (persist regardless of Remember State)
/// Visualization modes, browser columns, radio stations, hide title bars, server credentials,
/// and other preferences are saved to UserDefaults on every change and are NOT part of AppState.
class AppStateManager {
    
    // MARK: - Singleton
    
    static let shared = AppStateManager()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let rememberStateEnabled = "rememberStateEnabled"
        static let savedAppState = "savedAppState"
    }

    // MARK: - State Structure
    
    /// Represents a saved track that can be restored
    struct SavedTrack: Codable, Equatable {
        // For local files
        var localURL: String?
        
        // For Plex tracks
        var plexRatingKey: String?
        var plexServerId: String?
        
        // For Subsonic tracks
        var subsonicId: String?
        var subsonicServerId: String?
        
        // For Jellyfin tracks
        var jellyfinId: String?
        var jellyfinServerId: String?

        // For Emby tracks
        var embyId: String?
        var embyServerId: String?

        // For radio tracks (internet radio streams)
        var radioURL: String?
        var radioStationName: String?
        
        // Display metadata (shown while loading streaming tracks)
        var title: String
        var artist: String?
        var album: String?
        var duration: Double?
        
        // MIME content type hint for casting (e.g. "audio/flac")
        // Preserves content type across restarts so Sonos casting doesn't default to audio/mpeg
        var contentType: String?
        
        /// Create from a Track
        static func from(_ track: Track) -> SavedTrack {
            if track.url.isFileURL {
                return SavedTrack(
                    localURL: track.url.absoluteString,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration
                )
            } else if let plexKey = track.plexRatingKey {
                return SavedTrack(
                    plexRatingKey: plexKey,
                    plexServerId: track.plexServerId,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration
                )
            } else if let subId = track.subsonicId {
                return SavedTrack(
                    subsonicId: subId,
                    subsonicServerId: track.subsonicServerId,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration,
                    contentType: track.contentType
                )
            } else if let jfId = track.jellyfinId {
                return SavedTrack(
                    jellyfinId: jfId,
                    jellyfinServerId: track.jellyfinServerId,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration,
                    contentType: track.contentType
                )
            } else if let embyId = track.embyId {
                return SavedTrack(
                    embyId: embyId,
                    embyServerId: track.embyServerId,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration,
                    contentType: track.contentType
                )
            } else if !track.url.isFileURL {
                // Non-file URL without streaming service IDs = radio/internet stream
                // Match against known radio stations for station name
                let stationName = RadioManager.shared.stations.first(where: { $0.url == track.url })?.name
                return SavedTrack(
                    radioURL: track.url.absoluteString,
                    radioStationName: stationName ?? track.title,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration
                )
            } else {
                // Unknown source - save as local URL fallback
                return SavedTrack(
                    localURL: track.url.absoluteString,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration
                )
            }
        }
        
        /// Whether this is a local file
        var isLocal: Bool { localURL != nil }
        
        /// Whether this is a Plex track
        var isPlex: Bool { plexRatingKey != nil }
        
        /// Whether this is a Subsonic track
        var isSubsonic: Bool { subsonicId != nil }
        
        /// Whether this is a Jellyfin track
        var isJellyfin: Bool { jellyfinId != nil }

        /// Whether this is an Emby track
        var isEmby: Bool { embyId != nil }

        /// Whether this is a radio/internet stream track
        var isRadio: Bool { radioURL != nil }
    }
    
    /// Complete application state that can be saved/restored
    struct AppState: Codable {
        // Window visibility
        var isPlaylistVisible: Bool
        var isEqualizerVisible: Bool
        var isPlexBrowserVisible: Bool
        var isProjectMVisible: Bool
        var isSpectrumVisible: Bool = false
        var isWaveformVisible: Bool = false
        
        // Window frames (as strings for NSRect compatibility)
        var mainWindowFrame: String?
        var playlistWindowFrame: String?
        var equalizerWindowFrame: String?
        var plexBrowserWindowFrame: String?
        var projectMWindowFrame: String?
        var spectrumWindowFrame: String?
        var waveformWindowFrame: String?
        var isProjectMFullscreen: Bool = false
        
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
        var playlistTracks: [SavedTrack]  // All tracks including streaming
        var playlistURLs: [String]?  // Legacy - for backward compatibility reading old saved states
        var currentTrackIndex: Int
        var playbackPosition: Double  // Position in seconds
        var wasPlaying: Bool
        
        // UI preferences
        var timeDisplayMode: String
        var isAlwaysOnTop: Bool
        
        // Skin
        var customSkinPath: String?
        
        // ProjectM preset
        var projectMPresetIndex: Int?
        
        // -- v2 fields (added for comprehensive state restoration) --
        
        // Double size mode (both modes)
        var isDoubleSize: Bool = false
        
        // Modern skin name
        var modernSkinName: String?
        
        // Audio output device
        var selectedOutputDeviceUID: String?
        
        // Library browser state
        var browserBrowseMode: Int?  // Raw value of PlexBrowseMode / ModernBrowseMode
        
        // UI mode the state was saved in (used to skip frame restoration on mode mismatch)
        var savedInModernMode: Bool = false
        
        // Version for future compatibility
        var stateVersion: Int = 2
        
        // MARK: - Custom Decoding for Backward Compatibility
        
        enum CodingKeys: String, CodingKey {
            case isPlaylistVisible, isEqualizerVisible, isPlexBrowserVisible, isProjectMVisible, isSpectrumVisible, isWaveformVisible
            case mainWindowFrame, playlistWindowFrame, equalizerWindowFrame, plexBrowserWindowFrame, projectMWindowFrame, spectrumWindowFrame, waveformWindowFrame, isProjectMFullscreen
            case volume, balance, shuffleEnabled, repeatEnabled, gaplessPlaybackEnabled, volumeNormalizationEnabled
            case sweetFadeEnabled, sweetFadeDuration
            case eqEnabled, eqAutoEnabled, eqPreamp, eqBands
            case playlistTracks, playlistURLs, currentTrackIndex, playbackPosition, wasPlaying
            case timeDisplayMode, isAlwaysOnTop
            case customSkinPath
            case projectMPresetIndex
            // v2 fields
            case isDoubleSize, modernSkinName, selectedOutputDeviceUID
            case browserBrowseMode, savedInModernMode
            case stateVersion
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Window visibility
            isPlaylistVisible = try container.decode(Bool.self, forKey: .isPlaylistVisible)
            isEqualizerVisible = try container.decode(Bool.self, forKey: .isEqualizerVisible)
            isPlexBrowserVisible = try container.decode(Bool.self, forKey: .isPlexBrowserVisible)
            isProjectMVisible = try container.decode(Bool.self, forKey: .isProjectMVisible)
            isSpectrumVisible = try container.decodeIfPresent(Bool.self, forKey: .isSpectrumVisible) ?? false
            isWaveformVisible = try container.decodeIfPresent(Bool.self, forKey: .isWaveformVisible) ?? false
            
            // Window frames
            mainWindowFrame = try container.decodeIfPresent(String.self, forKey: .mainWindowFrame)
            playlistWindowFrame = try container.decodeIfPresent(String.self, forKey: .playlistWindowFrame)
            equalizerWindowFrame = try container.decodeIfPresent(String.self, forKey: .equalizerWindowFrame)
            plexBrowserWindowFrame = try container.decodeIfPresent(String.self, forKey: .plexBrowserWindowFrame)
            projectMWindowFrame = try container.decodeIfPresent(String.self, forKey: .projectMWindowFrame)
            spectrumWindowFrame = try container.decodeIfPresent(String.self, forKey: .spectrumWindowFrame)
            waveformWindowFrame = try container.decodeIfPresent(String.self, forKey: .waveformWindowFrame)
            isProjectMFullscreen = try container.decodeIfPresent(Bool.self, forKey: .isProjectMFullscreen) ?? false
            
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
            
            // Playback state - try new format first, fall back to legacy
            if let tracks = try container.decodeIfPresent([SavedTrack].self, forKey: .playlistTracks) {
                playlistTracks = tracks
            } else if let urls = try container.decodeIfPresent([String].self, forKey: .playlistURLs) {
                // Convert legacy URLs to SavedTrack
                playlistTracks = urls.map { url in
                    SavedTrack(localURL: url, title: URL(string: url)?.lastPathComponent ?? "Unknown")
                }
            } else {
                playlistTracks = []
            }
            playlistURLs = nil  // Legacy field, not used anymore
            currentTrackIndex = try container.decode(Int.self, forKey: .currentTrackIndex)
            playbackPosition = try container.decode(Double.self, forKey: .playbackPosition)
            wasPlaying = try container.decode(Bool.self, forKey: .wasPlaying)
            
            // UI preferences
            timeDisplayMode = try container.decode(String.self, forKey: .timeDisplayMode)
            isAlwaysOnTop = try container.decode(Bool.self, forKey: .isAlwaysOnTop)
            
            // Skin
            customSkinPath = try container.decodeIfPresent(String.self, forKey: .customSkinPath)
            // baseSkinIndex from older saved states is silently ignored (base skins no longer bundled)
            
            // ProjectM preset - nil for backward compatibility with older saved states
            projectMPresetIndex = try container.decodeIfPresent(Int.self, forKey: .projectMPresetIndex)
            
            // v2 fields - all use decodeIfPresent for backward compatibility
            isDoubleSize = try container.decodeIfPresent(Bool.self, forKey: .isDoubleSize) ?? false
            modernSkinName = try container.decodeIfPresent(String.self, forKey: .modernSkinName)
            selectedOutputDeviceUID = try container.decodeIfPresent(String.self, forKey: .selectedOutputDeviceUID)
            browserBrowseMode = try container.decodeIfPresent(Int.self, forKey: .browserBrowseMode)
            savedInModernMode = try container.decodeIfPresent(Bool.self, forKey: .savedInModernMode) ?? false
            
            // Version
            stateVersion = try container.decodeIfPresent(Int.self, forKey: .stateVersion) ?? 1
        }
        
        // Standard memberwise initializer for saving state
        init(
            isPlaylistVisible: Bool,
            isEqualizerVisible: Bool,
            isPlexBrowserVisible: Bool,
            isProjectMVisible: Bool,
            isSpectrumVisible: Bool = false,
            isWaveformVisible: Bool = false,
            mainWindowFrame: String?,
            playlistWindowFrame: String?,
            equalizerWindowFrame: String?,
            plexBrowserWindowFrame: String?,
            projectMWindowFrame: String?,
            spectrumWindowFrame: String? = nil,
            waveformWindowFrame: String? = nil,
            isProjectMFullscreen: Bool = false,
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
            playlistTracks: [SavedTrack],
            currentTrackIndex: Int,
            playbackPosition: Double,
            wasPlaying: Bool,
            timeDisplayMode: String,
            isAlwaysOnTop: Bool,
            customSkinPath: String? = nil,
            projectMPresetIndex: Int? = nil,
            isDoubleSize: Bool = false,
            modernSkinName: String? = nil,
            selectedOutputDeviceUID: String? = nil,
            browserBrowseMode: Int? = nil,
            savedInModernMode: Bool = false,
            stateVersion: Int = 2
        ) {
            self.isPlaylistVisible = isPlaylistVisible
            self.isEqualizerVisible = isEqualizerVisible
            self.isPlexBrowserVisible = isPlexBrowserVisible
            self.isProjectMVisible = isProjectMVisible
            self.isSpectrumVisible = isSpectrumVisible
            self.isWaveformVisible = isWaveformVisible
            self.mainWindowFrame = mainWindowFrame
            self.playlistWindowFrame = playlistWindowFrame
            self.equalizerWindowFrame = equalizerWindowFrame
            self.plexBrowserWindowFrame = plexBrowserWindowFrame
            self.projectMWindowFrame = projectMWindowFrame
            self.spectrumWindowFrame = spectrumWindowFrame
            self.waveformWindowFrame = waveformWindowFrame
            self.isProjectMFullscreen = isProjectMFullscreen
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
            self.playlistTracks = playlistTracks
            self.playlistURLs = nil  // Legacy, not used
            self.currentTrackIndex = currentTrackIndex
            self.playbackPosition = playbackPosition
            self.wasPlaying = wasPlaying
            self.timeDisplayMode = timeDisplayMode
            self.isAlwaysOnTop = isAlwaysOnTop
            self.customSkinPath = customSkinPath
            self.projectMPresetIndex = projectMPresetIndex
            self.isDoubleSize = isDoubleSize
            self.modernSkinName = modernSkinName
            self.selectedOutputDeviceUID = selectedOutputDeviceUID
            self.browserBrowseMode = browserBrowseMode
            self.savedInModernMode = savedInModernMode
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
        
        // Capture browser browse mode from the active browser window (if visible)
        var browserBrowseMode: Int? = nil
        if wm.isPlexBrowserVisible {
            browserBrowseMode = wm.plexBrowserBrowseMode
        }
        
        // Capture window visibility
        let state = AppState(
            // Window visibility
            isPlaylistVisible: wm.isPlaylistVisible,
            isEqualizerVisible: wm.isEqualizerVisible,
            isPlexBrowserVisible: wm.isPlexBrowserVisible,
            isProjectMVisible: wm.isProjectMVisible,
            isSpectrumVisible: wm.isSpectrumVisible,
            isWaveformVisible: wm.isWaveformVisible,
            
            // Window frames
            mainWindowFrame: wm.mainWindowController?.window.map { NSStringFromRect($0.frame) },
            playlistWindowFrame: wm.playlistWindowController?.window.map { NSStringFromRect($0.frame) },
            equalizerWindowFrame: wm.equalizerWindowController?.window.map { NSStringFromRect($0.frame) },
            plexBrowserWindowFrame: wm.plexBrowserWindowFrame.map { NSStringFromRect($0) },
            // Don't save frame when fullscreen (it would be screen bounds)
            projectMWindowFrame: wm.isProjectMVisible && !wm.isProjectMFullscreen ? wm.projectMWindowFrame.map { NSStringFromRect($0) } : nil,
            spectrumWindowFrame: wm.spectrumWindowFrame.map { NSStringFromRect($0) },
            waveformWindowFrame: nil,
            isProjectMFullscreen: wm.isProjectMFullscreen,
            
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
            eqBands: (0..<engine.eqConfiguration.bandCount).map { engine.getEQBand($0) },
            
            // Playback state - save all tracks with metadata for restoration
            playlistTracks: engine.playlist.map { track in
                SavedTrack.from(track)
            },
            currentTrackIndex: engine.currentIndex,
            playbackPosition: engine.currentTime,
            wasPlaying: engine.state == .playing,
            
            // UI preferences
            timeDisplayMode: wm.timeDisplayMode.rawValue,
            isAlwaysOnTop: wm.isAlwaysOnTop,
            
            // Skin - save path if using a custom skin
            customSkinPath: getCustomSkinPath(),
            
            // ProjectM preset
            projectMPresetIndex: wm.visualizationPresetIndex,
            
            // v2 fields
            isDoubleSize: wm.isDoubleSize,
            modernSkinName: UserDefaults.standard.string(forKey: "modernSkinName"),
            selectedOutputDeviceUID: UserDefaults.standard.string(forKey: "selectedOutputDeviceUID"),
            browserBrowseMode: browserBrowseMode,
            savedInModernMode: wm.isRunningModernUI
        )
        
        // Encode and save
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: Keys.savedAppState)
            NSLog("AppStateManager: Saved state - playlist: %d tracks, trackIndex: %d, position: %.1fs, volume: %.2f, doubleSize: %d",
                  state.playlistTracks.count, state.currentTrackIndex, state.playbackPosition, state.volume, state.isDoubleSize ? 1 : 0)
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
            let hasPlaylist = !state.playlistTracks.isEmpty
            applyState(state)
            return hasPlaylist
        } catch {
            NSLog("AppStateManager: Failed to restore state: %@", error.localizedDescription)
            return false
        }
    }
    
    /// Restore only settings state (skin, volume, EQ, windows)
    /// Called early in launch before playlist state is restored
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
    
    /// Restore only playlist state (tracks, position, playback)
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

    private func remappedEQBands(_ savedBands: [Float], for targetLayout: EQConfiguration) -> [Float] {
        guard !savedBands.isEmpty else {
            return Array(repeating: 0, count: targetLayout.bandCount)
        }

        guard let sourceLayout = EQConfiguration.persistedLayout(forBandCount: savedBands.count) else {
            let normalized = Array(savedBands.prefix(targetLayout.bandCount))
            return normalized + Array(repeating: 0, count: max(0, targetLayout.bandCount - normalized.count))
        }

        return targetLayout.gainValues(remapping: savedBands, from: sourceLayout)
    }
    
    /// Apply settings state (skin, volume, EQ, windows) - no playlist
    private func applySettingsState(_ state: AppState) {
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        let runningModernMode = wm.isRunningModernUI
        
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
        let restoredBands = remappedEQBands(state.eqBands, for: engine.eqConfiguration)
        for (index, gain) in restoredBands.enumerated() {
            engine.setEQBand(index, gain: gain)
        }
        
        // Restore UI preferences
        if let mode = TimeDisplayMode(rawValue: state.timeDisplayMode) {
            wm.timeDisplayMode = mode
        }
        NSLog("AppStateManager: Restoring isAlwaysOnTop = %d", state.isAlwaysOnTop ? 1 : 0)
        wm.isAlwaysOnTop = state.isAlwaysOnTop
        
        // Restore skin (custom skin path only; base skins no longer bundled)
        if let skinPath = state.customSkinPath {
            let skinURL = URL(fileURLWithPath: skinPath)
            if FileManager.default.fileExists(atPath: skinPath) {
                wm.loadSkin(from: skinURL)
            }
        }
        
        // Restore modern skin name (if saved and modern UI is active)
        if runningModernMode, let modernSkin = state.modernSkinName {
            UserDefaults.standard.set(modernSkin, forKey: "modernSkinName")
            // ModernSkinEngine.loadPreferredSkin() is called in AppDelegate before state restore,
            // but we set the UserDefaults value here so subsequent launches use it
        }
        
        // Restore audio output device
        if let deviceUID = state.selectedOutputDeviceUID {
            UserDefaults.standard.set(deviceUID, forKey: "selectedOutputDeviceUID")
        }
        
        // Check if the saved state's UI mode matches the current mode.
        // If mismatched (e.g. saved in modern, now running classic), skip window frame
        // restoration since the windows have different sizes and constraints.
        let modeMatches = state.savedInModernMode == runningModernMode
        if !modeMatches {
            NSLog("AppStateManager: UI mode changed (saved=%@, current=%@) - skipping window frame restoration",
                  state.savedInModernMode ? "modern" : "classic",
                  runningModernMode ? "modern" : "classic")
        }
        
        // Restore window frames (only if mode matches)
        if modeMatches {
            restoreWindowFrames(state)
        }
        
        // Restore window visibility (after a short delay to ensure proper positioning)
        // Parse frames before the closure to avoid capturing state
        // Only pass saved frames if the UI mode matches; otherwise use nil (default positions)
        let playlistFrame = modeMatches ? state.playlistWindowFrame.flatMap({ NSRectFromString($0) }) : nil
        let equalizerFrame = modeMatches ? state.equalizerWindowFrame.flatMap({ NSRectFromString($0) }) : nil
        let browserFrame = modeMatches ? state.plexBrowserWindowFrame.flatMap({ NSRectFromString($0) }) : nil
        let projectMFrame = modeMatches ? state.projectMWindowFrame.flatMap({ NSRectFromString($0) }) : nil
        let spectrumFrame = modeMatches ? state.spectrumWindowFrame.flatMap({ NSRectFromString($0) }) : nil
        let waveformFrame = modeMatches ? state.waveformWindowFrame.flatMap({ NSRectFromString($0) }) : nil
        let projectMPresetIndex = state.projectMPresetIndex
        let projectMFullscreen = state.isProjectMFullscreen
        let savedBrowseMode = state.browserBrowseMode
        let savedDoubleSize = state.isDoubleSize
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Restore double size BEFORE showing sub-windows so applyDoubleSize
            // doesn't re-scale frames that are already at their saved 1.5x sizes.
            // At this point only the main window is visible, so applyDoubleSize
            // correctly updates its minSize/frame without touching sub-window heights.
            if savedDoubleSize {
                wm.isDoubleSize = true
                NSLog("AppStateManager: Restored double size mode")
            }
            
            if state.isEqualizerVisible {
                wm.showEqualizer(at: equalizerFrame)
            }
            if state.isPlaylistVisible {
                wm.showPlaylist(at: playlistFrame)
            }
            if state.isSpectrumVisible {
                wm.showSpectrum(at: spectrumFrame)
            }
            if state.isWaveformVisible {
                wm.showWaveform(at: waveformFrame)
            }
            if state.isPlexBrowserVisible {
                wm.showPlexBrowser(at: browserFrame)
                
                // Restore browse mode after the browser window is shown and view is ready
                if let browseMode = savedBrowseMode {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        wm.plexBrowserBrowseMode = browseMode
                        NSLog("AppStateManager: Restored browser browse mode: %d", browseMode)
                    }
                }
            }
            if state.isProjectMVisible {
                wm.showProjectM(at: projectMFrame)
                
                // Restore fullscreen state BEFORE preset
                if projectMFullscreen {
                    wm.toggleProjectMFullscreen()
                }
                
                // Restore ProjectM preset after engine is initialized on render thread
                // The engine setup is deferred and takes ~200ms to complete
                if let presetIndex = projectMPresetIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        wm.selectVisualizationPreset(at: presetIndex)
                        NSLog("AppStateManager: Restored ProjectM preset index: %d", presetIndex)
                    }
                }
            }

            // One-time self-heal for classic sessions affected by cross-mode frame contamination.
            self.repairClassicDockedStackWidthsIfNeeded()
        }
        
        NSLog("AppStateManager: Settings state restored (eqAutoEnabled: %d, doubleSize: %d)", state.eqAutoEnabled ? 1 : 0, state.isDoubleSize ? 1 : 0)
    }
    
    /// Apply playlist state: populates the playlist preserving original order,
    /// selects the current track, and seeks to saved position.
    /// Streaming tracks start as placeholders (with saved metadata for display)
    /// and are replaced with real tracks as async fetches complete.
    private func applyPlaylistState(_ state: AppState) {
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        
        guard !state.playlistTracks.isEmpty else {
            NSLog("AppStateManager: No playlist to restore")
            return
        }
        
        NSLog("AppStateManager: Restoring playlist state - %d tracks, trackIndex: %d, position: %.1fs",
              state.playlistTracks.count, state.currentTrackIndex, state.playbackPosition)
        
        // Build the complete track list in original order.
        // Local and radio tracks are fully resolved immediately.
        // Streaming tracks get placeholder Track objects carrying service IDs,
        // then those placeholders are replaced as async fetches complete.
        var allTracks: [Track] = []
        var placeholderIndicesToResolve: [Int] = []
        var skippedIndices: Set<Int> = []
        
        for (index, savedTrack) in state.playlistTracks.enumerated() {
            if savedTrack.isRadio, let urlString = savedTrack.radioURL, let url = URL(string: urlString) {
                // Radio track - create from saved URL and metadata
                let track = Track(
                    url: url,
                    title: savedTrack.radioStationName ?? savedTrack.title,
                    artist: savedTrack.artist,
                    album: savedTrack.album,
                    duration: savedTrack.duration
                )
                allTracks.append(track)
            } else if let urlString = savedTrack.localURL, let url = URL(string: urlString) {
                // Local file - verify it still exists
                if FileManager.default.fileExists(atPath: url.path) {
                    // Use saved metadata to avoid synchronous file I/O on the main thread.
                    // Re-reading each file via AVAudioFile/AVAsset on NAS volumes blocks
                    // applicationDidFinishLaunching for minutes with large playlists.
                    allTracks.append(Track(
                        url: url,
                        title: savedTrack.title,
                        artist: savedTrack.artist,
                        album: savedTrack.album,
                        duration: savedTrack.duration,
                        contentType: savedTrack.contentType
                    ))
                } else {
                    // File no longer exists - add a placeholder that will display but won't play
                    NSLog("AppStateManager: Local file missing, skipping: %@", savedTrack.title)
                    skippedIndices.insert(index)
                    continue
                }
            } else if savedTrack.isPlex {
                // Plex track - create placeholder with saved metadata
                // Use about:blank as placeholder URL; will be replaced by async fetch
                let placeholder = Track(
                    url: URL(string: "about:blank")!,
                    title: savedTrack.title,
                    artist: savedTrack.artist,
                    album: savedTrack.album,
                    duration: savedTrack.duration,
                    plexRatingKey: savedTrack.plexRatingKey,
                    plexServerId: savedTrack.plexServerId,
                    contentType: savedTrack.contentType
                )
                placeholderIndicesToResolve.append(allTracks.count)
                allTracks.append(placeholder)
            } else if savedTrack.isSubsonic {
                let placeholder = Track(
                    url: URL(string: "about:blank")!,
                    title: savedTrack.title,
                    artist: savedTrack.artist,
                    album: savedTrack.album,
                    duration: savedTrack.duration,
                    subsonicId: savedTrack.subsonicId,
                    subsonicServerId: savedTrack.subsonicServerId,
                    contentType: savedTrack.contentType
                )
                placeholderIndicesToResolve.append(allTracks.count)
                allTracks.append(placeholder)
            } else if savedTrack.isJellyfin {
                let placeholder = Track(
                    url: URL(string: "about:blank")!,
                    title: savedTrack.title,
                    artist: savedTrack.artist,
                    album: savedTrack.album,
                    duration: savedTrack.duration,
                    jellyfinId: savedTrack.jellyfinId,
                    jellyfinServerId: savedTrack.jellyfinServerId,
                    contentType: savedTrack.contentType
                )
                placeholderIndicesToResolve.append(allTracks.count)
                allTracks.append(placeholder)
            } else if savedTrack.isEmby {
                let placeholder = Track(
                    url: URL(string: "about:blank")!,
                    title: savedTrack.title,
                    artist: savedTrack.artist,
                    album: savedTrack.album,
                    duration: savedTrack.duration,
                    embyId: savedTrack.embyId,
                    embyServerId: savedTrack.embyServerId,
                    contentType: savedTrack.contentType
                )
                placeholderIndicesToResolve.append(allTracks.count)
                allTracks.append(placeholder)
            } else {
                // Unknown type - skip
                skippedIndices.insert(index)
            }
        }
        
        // Set the full playlist at once, preserving original order
        engine.setPlaylistTracks(allTracks)
        NSLog("AppStateManager: Set playlist with %d tracks (%d skipped)", allTracks.count, skippedIndices.count)
        
        // Adjust current track index to account for any skipped tracks
        var adjustedIndex = state.currentTrackIndex
        if !skippedIndices.isEmpty {
            // Count how many tracks before the saved index were skipped
            let skippedBefore = skippedIndices.filter { $0 < state.currentTrackIndex }.count
            adjustedIndex -= skippedBefore
        }
        
        // Determine if the current track is a streaming placeholder (real URL not yet available)
        let currentIsPlaceholder = adjustedIndex >= 0
            && adjustedIndex < allTracks.count
            && allTracks[adjustedIndex].isStreamingPlaceholder
        // Select the current track for display without loading or playing
        if adjustedIndex >= 0 && adjustedIndex < allTracks.count {
            engine.selectTrackForDisplay(at: adjustedIndex)
            NSLog("AppStateManager: Selected track at index %d for display", adjustedIndex)
        }
        
        // Fetch streaming tracks asynchronously and replace placeholders
        if !placeholderIndicesToResolve.isEmpty {
            let savedCurrentIndex = adjustedIndex
            Task {
                var replacements: [(Track, Int)] = []  // (realTrack, playlistIndex)
                for playlistIndex in placeholderIndicesToResolve {
                    let placeholderTrack = allTracks[playlistIndex]
                    if let resolvedTrack = await StreamingTrackResolver.resolve(placeholderTrack) {
                        replacements.append((resolvedTrack, playlistIndex))
                    } else {
                        NSLog("AppStateManager: Failed to resolve placeholder track '%@'", placeholderTrack.title)
                    }
                }
                let resolvedReplacements = replacements

                // Replace placeholder tracks with real ones on the main thread
                await MainActor.run {
                    var replacedCurrentTrack = false
                    for (realTrack, playlistIndex) in resolvedReplacements {
                        engine.replaceTrack(at: playlistIndex, with: realTrack)
                        if playlistIndex == savedCurrentIndex {
                            replacedCurrentTrack = true
                        }
                    }
                    NSLog("AppStateManager: Replaced %d streaming track placeholders", resolvedReplacements.count)
                    
                    // If the current track was a streaming placeholder, update display now that we have the real URL
                    if replacedCurrentTrack && savedCurrentIndex >= 0 {
                        engine.selectTrackForDisplay(at: savedCurrentIndex)
                    }
                }
            }
        }
        
        NSLog("AppStateManager: Playlist state restoration initiated")
    }

    /// Apply the restored state to the app (full restore - used by restoreState())
    private func applyState(_ state: AppState) {
        // Apply settings first (skin, volume, EQ, windows, v2 fields)
        applySettingsState(state)
        
        // Then apply playlist state (tracks, position, current track)
        if !state.playlistTracks.isEmpty {
            applyPlaylistState(state)
        }
        
        NSLog("AppStateManager: State restored successfully")
    }
    
    /// Restore window frames from saved state
    /// Note: Only the main window frame is restored here since it exists at restore time.
    /// Playlist, EQ, Browser, and ProjectM frames are passed to their show methods
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

        // Modern HT sessions may contain stale full-height frames from older runs.
        // Normalize immediately so launch never reserves titlebar space in HT mode.
        if wm.isRunningModernUI {
            wm.normalizeModernMainWindowForHTIfNeeded()
        }
        
        // Note: Playlist, EQ, Browser, and ProjectM frames are passed directly to their
        // show methods in applyState() since those windows are created lazily and don't
        // exist yet when this function is called.
    }

    struct ClassicCenterStackRepairResult {
        let mainFrame: NSRect
        let equalizerFrame: NSRect?
        let playlistFrame: NSRect?
        let spectrumFrame: NSRect?
        let waveformFrame: NSRect?
        let repaired: Bool
    }

    /// Pure geometry helper for restoring classic center-stack windows
    /// (Main/EQ/Playlist/Spectrum/Waveform).
    /// Repairs near-docked gaps and snaps repaired windows flush below the current anchor
    /// in stack order. Width is preserved for windows that support horizontal stretching.
    static func repairClassicCenterStackFrames(
        mainFrame: NSRect,
        equalizerFrame: NSRect?,
        playlistFrame: NSRect?,
        spectrumFrame: NSRect?,
        waveformFrame: NSRect?,
        scale: CGFloat
    ) -> ClassicCenterStackRepairResult {
        let widthEpsilon: CGFloat = 0.5
        let minMainHeight = Skin.mainWindowSize.height * scale
        let nearDockTolerance = max(20.0, 24.0 * scale)

        var repaired = false
        var adjustedMain = mainFrame
        if adjustedMain.height + widthEpsilon < minMainHeight {
            let topY = adjustedMain.maxY
            adjustedMain.size.height = minMainHeight
            adjustedMain.origin.y = topY - minMainHeight
            repaired = true
        }

        var anchorFrame = adjustedMain

        func shouldRepairCandidate(_ candidate: NSRect, below anchor: NSRect) -> Bool {
            let verticalGap = abs(candidate.maxY - anchor.minY)
            let horizontalOverlap = candidate.minX < anchor.maxX && candidate.maxX > anchor.minX
            let leftAligned = abs(candidate.minX - anchor.minX) <= nearDockTolerance
            return verticalGap <= nearDockTolerance && horizontalOverlap && leftAligned
        }

        func normalizedFlushFrame(for candidate: NSRect, below anchor: NSRect, preserveWidth: Bool = false) -> NSRect {
            NSRect(
                x: adjustedMain.minX,
                y: anchor.minY - candidate.height,
                width: preserveWidth ? candidate.width : adjustedMain.width,
                height: candidate.height
            )
        }

        func frameChanged(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
            abs(lhs.minX - rhs.minX) > widthEpsilon ||
            abs(lhs.minY - rhs.minY) > widthEpsilon ||
            abs(lhs.width - rhs.width) > widthEpsilon
        }

        func repairCandidate(_ candidate: NSRect?, preserveWidth: Bool = false) -> NSRect? {
            guard let candidate else { return nil }
            guard shouldRepairCandidate(candidate, below: anchorFrame) else { return candidate }

            let repairedFrame = normalizedFlushFrame(for: candidate, below: anchorFrame, preserveWidth: preserveWidth)
            if frameChanged(candidate, repairedFrame) {
                repaired = true
            }
            anchorFrame = repairedFrame
            return repairedFrame
        }

        let adjustedEQ = repairCandidate(equalizerFrame)
        let adjustedPlaylist = repairCandidate(playlistFrame, preserveWidth: true)
        let adjustedSpectrum = repairCandidate(spectrumFrame, preserveWidth: true)
        let adjustedWaveform = repairCandidate(waveformFrame, preserveWidth: true)

        return ClassicCenterStackRepairResult(
            mainFrame: adjustedMain,
            equalizerFrame: adjustedEQ,
            playlistFrame: adjustedPlaylist,
            spectrumFrame: adjustedSpectrum,
            waveformFrame: adjustedWaveform,
            repaired: repaired
        )
    }

    /// Repair classic-mode docked stack geometry if corrupted by cross-mode frame restore.
    /// Applies only to near-docked center-stack windows directly below main.
    private func repairClassicDockedStackWidthsIfNeeded() {
        let wm = WindowManager.shared
        guard !wm.isRunningModernUI else { return }
        guard let mainWindow = wm.mainWindowController?.window else { return }

        let scale: CGFloat = wm.isDoubleSize ? 1.5 : 1.0
        let equalizerWindow = wm.equalizerWindowController?.window
        let playlistWindow = wm.playlistWindowController?.window
        let spectrumWindow = wm.spectrumWindow
        let waveformWindow = wm.waveformWindow

        let equalizerFrame: NSRect?
        if let equalizerWindow, equalizerWindow.isVisible {
            equalizerFrame = equalizerWindow.frame
        } else {
            equalizerFrame = nil
        }

        let playlistFrame: NSRect?
        if let playlistWindow, playlistWindow.isVisible {
            playlistFrame = playlistWindow.frame
        } else {
            playlistFrame = nil
        }

        let spectrumFrame: NSRect?
        if let spectrumWindow, spectrumWindow.isVisible {
            spectrumFrame = spectrumWindow.frame
        } else {
            spectrumFrame = nil
        }

        let waveformFrame: NSRect?
        if let waveformWindow, waveformWindow.isVisible {
            waveformFrame = waveformWindow.frame
        } else {
            waveformFrame = nil
        }

        let repairedFrames = Self.repairClassicCenterStackFrames(
            mainFrame: mainWindow.frame,
            equalizerFrame: equalizerFrame,
            playlistFrame: playlistFrame,
            spectrumFrame: spectrumFrame,
            waveformFrame: waveformFrame,
            scale: scale
        )

        if repairedFrames.mainFrame != mainWindow.frame {
            mainWindow.setFrame(repairedFrames.mainFrame, display: true)
        }
        if let equalizerWindow,
           equalizerWindow.isVisible,
           let repairedFrame = repairedFrames.equalizerFrame,
           repairedFrame != equalizerWindow.frame {
            equalizerWindow.setFrame(repairedFrame, display: true)
        }
        if let playlistWindow,
           playlistWindow.isVisible,
           let repairedFrame = repairedFrames.playlistFrame,
           repairedFrame != playlistWindow.frame {
            playlistWindow.setFrame(repairedFrame, display: true)
        }
        if let spectrumWindow,
           spectrumWindow.isVisible,
           let repairedFrame = repairedFrames.spectrumFrame,
           repairedFrame != spectrumWindow.frame {
            spectrumWindow.setFrame(repairedFrame, display: true)
        }
        if let waveformWindow,
           waveformWindow.isVisible,
           let repairedFrame = repairedFrames.waveformFrame,
           repairedFrame != waveformWindow.frame {
            waveformWindow.setFrame(repairedFrame, display: true)
        }

        if repairedFrames.repaired {
            NSLog("AppStateManager: Repaired classic docked stack geometry to remove near-docked gaps")
            wm.updateDockedChildWindows()
        }
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
