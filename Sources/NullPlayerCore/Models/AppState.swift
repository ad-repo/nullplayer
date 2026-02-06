import Foundation

/// Complete application state that can be saved/restored
public struct AppState: Codable, Sendable {
    // Window visibility
    public var isPlaylistVisible: Bool
    public var isEqualizerVisible: Bool
    public var isPlexBrowserVisible: Bool
    public var isProjectMVisible: Bool
    
    // Window frames (as strings for NSRect compatibility)
    public var mainWindowFrame: String?
    public var playlistWindowFrame: String?
    public var equalizerWindowFrame: String?
    public var plexBrowserWindowFrame: String?
    public var projectMWindowFrame: String?
    
    // Audio settings
    public var volume: Float
    public var balance: Float
    public var shuffleEnabled: Bool
    public var repeatEnabled: Bool
    public var gaplessPlaybackEnabled: Bool
    public var volumeNormalizationEnabled: Bool
    
    // Sweet Fades (crossfade) settings
    // Default values ensure backward compatibility with saved states from older versions
    public var sweetFadeEnabled: Bool = false
    public var sweetFadeDuration: Double = 5.0
    
    // EQ settings
    public var eqEnabled: Bool
    public var eqPreamp: Float
    public var eqBands: [Float]
    
    // Playback state
    public var playlistURLs: [String]  // File URLs as strings
    public var currentTrackIndex: Int
    public var playbackPosition: Double  // Position in seconds
    public var wasPlaying: Bool
    
    // UI preferences
    public var timeDisplayMode: String
    public var isAlwaysOnTop: Bool
    
    // Skin
    public var customSkinPath: String?
    public var baseSkinIndex: Int?  // 1, 2, or 3 for base skins; nil for custom skin
    
    // Version for future compatibility
    public var stateVersion: Int = 1
    
    // MARK: - Custom Decoding for Backward Compatibility
    
    enum CodingKeys: String, CodingKey {
        case isPlaylistVisible, isEqualizerVisible, isPlexBrowserVisible, isProjectMVisible
        case mainWindowFrame, playlistWindowFrame, equalizerWindowFrame, plexBrowserWindowFrame, projectMWindowFrame
        case volume, balance, shuffleEnabled, repeatEnabled, gaplessPlaybackEnabled, volumeNormalizationEnabled
        case sweetFadeEnabled, sweetFadeDuration
        case eqEnabled, eqPreamp, eqBands
        case playlistURLs, currentTrackIndex, playbackPosition, wasPlaying
        case timeDisplayMode, isAlwaysOnTop
        case customSkinPath, baseSkinIndex
        case stateVersion
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Window visibility
        isPlaylistVisible = try container.decode(Bool.self, forKey: .isPlaylistVisible)
        isEqualizerVisible = try container.decode(Bool.self, forKey: .isEqualizerVisible)
        isPlexBrowserVisible = try container.decode(Bool.self, forKey: .isPlexBrowserVisible)
        isProjectMVisible = try container.decode(Bool.self, forKey: .isProjectMVisible)
        
        // Window frames
        mainWindowFrame = try container.decodeIfPresent(String.self, forKey: .mainWindowFrame)
        playlistWindowFrame = try container.decodeIfPresent(String.self, forKey: .playlistWindowFrame)
        equalizerWindowFrame = try container.decodeIfPresent(String.self, forKey: .equalizerWindowFrame)
        plexBrowserWindowFrame = try container.decodeIfPresent(String.self, forKey: .plexBrowserWindowFrame)
        projectMWindowFrame = try container.decodeIfPresent(String.self, forKey: .projectMWindowFrame)
        
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
        
        // Version
        stateVersion = try container.decodeIfPresent(Int.self, forKey: .stateVersion) ?? 1
    }
    
    // Standard memberwise initializer for saving state
    public init(
        isPlaylistVisible: Bool,
        isEqualizerVisible: Bool,
        isPlexBrowserVisible: Bool,
        isProjectMVisible: Bool,
        mainWindowFrame: String?,
        playlistWindowFrame: String?,
        equalizerWindowFrame: String?,
        plexBrowserWindowFrame: String?,
        projectMWindowFrame: String?,
        volume: Float,
        balance: Float,
        shuffleEnabled: Bool,
        repeatEnabled: Bool,
        gaplessPlaybackEnabled: Bool,
        volumeNormalizationEnabled: Bool,
        sweetFadeEnabled: Bool,
        sweetFadeDuration: Double,
        eqEnabled: Bool,
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
        stateVersion: Int = 1
    ) {
        self.isPlaylistVisible = isPlaylistVisible
        self.isEqualizerVisible = isEqualizerVisible
        self.isPlexBrowserVisible = isPlexBrowserVisible
        self.isProjectMVisible = isProjectMVisible
        self.mainWindowFrame = mainWindowFrame
        self.playlistWindowFrame = playlistWindowFrame
        self.equalizerWindowFrame = equalizerWindowFrame
        self.plexBrowserWindowFrame = plexBrowserWindowFrame
        self.projectMWindowFrame = projectMWindowFrame
        self.volume = volume
        self.balance = balance
        self.shuffleEnabled = shuffleEnabled
        self.repeatEnabled = repeatEnabled
        self.gaplessPlaybackEnabled = gaplessPlaybackEnabled
        self.volumeNormalizationEnabled = volumeNormalizationEnabled
        self.sweetFadeEnabled = sweetFadeEnabled
        self.sweetFadeDuration = sweetFadeDuration
        self.eqEnabled = eqEnabled
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
        self.stateVersion = stateVersion
    }
}
