import AppKit
import AVFoundation
import SwiftUI
import NullPlayerCore

// =============================================================================
// MODERN LIBRARY BROWSER VIEW - Library browser with modern skin chrome
// =============================================================================
// Comprehensive port of PlexBrowserView.swift to use the modern skin engine.
//
// Key differences from classic PlexBrowserView:
// 1. ZERO dependencies on classic skin system (Skin/, SkinRenderer, SkinLoader, SkinElements)
// 2. Uses ModernSkinRenderer for window chrome (title bar, borders, control buttons)
// 3. Uses ModernSkinEngine for skin loading and change notifications
// 4. Uses NSFont for text (not skin bitmap font)
// 5. Uses bottom-left origin coordinates (macOS native - NO coordinate flipping)
// 6. Uses modern skin palette colors (primaryColor, accentColor, textColor, etc.)
// 7. Tabs and selections use modern boxed toggle style
// 8. Re-defines all data models independently
// =============================================================================

// MARK: - Browser Source

/// Source for browsing content (re-defined independently for modern view)
enum ModernBrowserSource: Equatable, Codable {
    case local
    case plex(serverId: String)
    case subsonic(serverId: String)
    case jellyfin(serverId: String)
    case emby(serverId: String)
    case radio
    case youtube

    var displayName: String {
        switch self {
        case .local: return "LOCAL FILES"
        case .plex(let serverId):
            if let server = PlexManager.shared.servers.first(where: { $0.id == serverId }) {
                return "PLEX: \(server.name)"
            }
            return "PLEX"
        case .subsonic(let serverId):
            if let server = SubsonicManager.shared.servers.first(where: { $0.id == serverId }) {
                return "SUBSONIC: \(server.name)"
            }
            return "SUBSONIC"
        case .jellyfin(let serverId):
            if let server = JellyfinManager.shared.servers.first(where: { $0.id == serverId }) {
                return "JELLYFIN: \(server.name)"
            }
            return "JELLYFIN"
        case .emby(let serverId):
            if let server = EmbyManager.shared.servers.first(where: { $0.id == serverId }) {
                return "EMBY: \(server.name)"
            }
            return "EMBY"
        case .radio: return "INTERNET RADIO"
        case .youtube: return "YOUTUBE"
        }
    }

    var shortName: String {
        switch self {
        case .local: return "Local Files"
        case .plex(let serverId):
            if let server = PlexManager.shared.servers.first(where: { $0.id == serverId }) {
                return server.name
            }
            return "Plex"
        case .subsonic(let serverId):
            if let server = SubsonicManager.shared.servers.first(where: { $0.id == serverId }) {
                return server.name
            }
            return "Subsonic"
        case .jellyfin(let serverId):
            if let server = JellyfinManager.shared.servers.first(where: { $0.id == serverId }) {
                return server.name
            }
            return "Jellyfin"
        case .emby(let serverId):
            if let server = EmbyManager.shared.servers.first(where: { $0.id == serverId }) {
                return server.name
            }
            return "Emby"
        case .radio: return "Radio"
        case .youtube: return "YouTube"
        }
    }

    var isSubsonic: Bool { if case .subsonic = self { return true }; return false }
    var isJellyfin: Bool { if case .jellyfin = self { return true }; return false }
    var isEmby: Bool { if case .emby = self { return true }; return false }
    var isPlex: Bool { if case .plex = self { return true }; return false }
    var isRadio: Bool { if case .radio = self { return true }; return false }
    var isYouTube: Bool { if case .youtube = self { return true }; return false }
    /// YouTube reuses the Internet Radio tab's UI to list its channels/videos.
    var usesRadioTab: Bool { isRadio || isYouTube }
    var isRemote: Bool {
        switch self { case .local, .radio, .youtube: return false; case .plex, .subsonic, .jellyfin, .emby: return true }
    }

    private static let userDefaultsKey = "BrowserSource"
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
    static func load() -> ModernBrowserSource? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let source = try? JSONDecoder().decode(ModernBrowserSource.self, from: data) else { return nil }
        return source
    }
}

// MARK: - Browse Mode

enum ModernBrowseMode: Int, CaseIterable {
    case artists = 0, albums = 1, plists = 3
    case movies = 4, shows = 5, search = 6, radio = 7, history = 8
    case folders = 9

    var title: String {
        switch self {
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .folders: return "Folders"
        case .plists: return "Plists"
        case .movies: return "Movies"
        case .shows: return "TV"
        case .search: return "Search"
        case .radio: return "Radio"
        case .history: return "Data"
        }
    }
    var isVideoMode: Bool { self == .movies || self == .shows }
    var isMusicMode: Bool { self == .artists || self == .albums || self == .plists || self == .folders }
    var isRadioMode: Bool { self == .radio }
    var isHistoryMode: Bool { self == .history }

    static var allCases: [ModernBrowseMode] {
        [.artists, .albums, .plists, .movies, .shows, .radio, .search, .history]
    }
}

// MARK: - Sort Option

enum ModernBrowserSortOption: String, CaseIterable, Codable {
    case nameAsc = "Name A-Z"
    case nameDesc = "Name Z-A"
    case dateAddedDesc = "Recently Added"
    case dateAddedAsc = "Oldest First"
    case yearDesc = "Year (Newest)"
    case yearAsc = "Year (Oldest)"
    
    var shortName: String {
        switch self {
        case .nameAsc: return "A-Z"
        case .nameDesc: return "Z-A"
        case .dateAddedDesc: return "New"
        case .dateAddedAsc: return "Old"
        case .yearDesc: return "Year"
        case .yearAsc: return "Year"
        }
    }
    
    private static let userDefaultsKey = "BrowserSortOption"
    func save() { UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey) }
    static func load() -> ModernBrowserSortOption {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let option = ModernBrowserSortOption(rawValue: raw) else { return .nameAsc }
        return option
    }
}

// MARK: - Button Type

enum LibraryBrowserButtonType {
    case close
    case shade
}

// MARK: - Modern Library Browser View

class ModernLibraryBrowserView: NSView {
    
    // MARK: - Properties
    
    weak var controller: ModernLibraryBrowserWindowController?

    private var renderer: ModernSkinRenderer!

    /// Compact Mode: when true, a stripped-down player bar is embedded across the top
    /// (just below the title bar) and all content below shifts down to make room.
    /// The window itself is never resized -- only the list/content region shrinks.
    var compactMode: Bool = false {
        didSet {
            guard compactMode != oldValue else { return }
            needsLayout = true
            needsDisplay = true
        }
    }
    private var compactPlayerBar: CompactPlayerBarView?

    /// Height of the embedded compact player bar (0 when not in compact mode).
    private var compactPlayerBarHeight: CGFloat {
        compactMode ? CompactPlayerBarView.preferredHeight(for: ModernSkinElements.sizeMultiplier) : 0
    }

    /// Y coordinate of the bottom of the top chrome (title bar + optional compact player bar).
    /// All content below the title bar measures down from here, so inserting the player bar
    /// shifts the server bar / tabs / search / list down without resizing the window.
    private var topChromeBottomY: CGFloat {
        bounds.height - Layout.titleBarHeight - compactPlayerBarHeight
    }
    
    // Browse state
    private var currentSource: ModernBrowserSource = .local {
        didSet { currentSource.save(); onSourceChanged() }
    }
    private var pendingSourceRestore: ModernBrowserSource?
    private var browseMode: ModernBrowseMode = .artists {
        didSet {
            guard browseMode != oldValue else { return }
            // Switching tabs always exits Art view.
            isArtOnlyMode = false
            if oldValue == .folders, browseMode != .folders {
                cancelLocalFolderBuild()
            }
            if browseMode.isHistoryMode {
                if isRatingOverlayVisible {
                    hideRatingOverlay()
                }
                historyAgent.scheduleRefresh()
            }
            updateHistoryHostingVisibility()
        }
    }
    
    /// Expose browse mode for state save/restore
    var browseModeRawValue: Int {
        get { browseMode.rawValue }
        set {
            if let mode = ModernBrowseMode(rawValue: newValue) {
                // If restoring .folders mode while non-local source, fall back to .plists
                var actualMode = mode
                if mode == .folders {
                    if case .local = currentSource {
                        actualMode = mode
                    } else {
                        actualMode = .plists
                    }
                }
                browseMode = actualMode
                selectedIndices.removeAll()
                scrollOffset = 0
                loadDataForCurrentMode()
                needsDisplay = true
            }
        }
    }
    
    private var currentSort: ModernBrowserSortOption = .nameAsc {
        didSet {
            currentSort.save()
            localArtistPageOffset = 0; localAlbumPageOffset = 0
            localArtistLetterOffsets = [:]; localAlbumLetterOffsets = [:]
            rebuildCurrentModeItems()
            needsDisplay = true
        }
    }
    private var searchQuery: String = ""
    private var typeAheadQuery: String = ""
    private var typeAheadTimer: Timer?

    private var selectedIndices: Set<Int> = []
    private var scrollOffset: CGFloat = 0
    private var horizontalScrollOffset: CGFloat = 0
    private let historyAgent = PlayHistoryAgent()
    private var historyHostingView: NSHostingView<StatsContentView>?
    
    private var itemHeight: CGFloat { 18 * ModernSkinElements.sizeMultiplier }
    private var columnHeaderHeight: CGFloat { 18 * ModernSkinElements.sizeMultiplier }
    
    // Column state
    private var columnWidths: [String: CGFloat] = [:] { didSet { saveColumnWidths() } }
    private var resizingColumnId: String?
    private var resizingColumnGroup: LibraryColumnVisibilityGroup?
    private var resizeStartX: CGFloat = 0
    private var resizeStartWidth: CGFloat = 0
    private var columnSortId: String? { didSet { saveColumnSort(); applyColumnSort(collapseExpanded: true) } }
    private var columnSortAscending: Bool = true { didSet { saveColumnSort(); applyColumnSort(collapseExpanded: true) } }

    // YouTube channels keep their own sort state (session-only, default = none → date
    // order as returned by yt-dlp). This keeps the persisted library column sort from
    // leaking in and re-ordering videos to A–Z on every rebuild (e.g. after a download).
    // Only an explicit header click in the YouTube tab sets this.
    private var youtubeColumnSortId: String? = nil
    private var youtubeColumnSortAscending: Bool = true

    /// Column sort that applies to the current source. YouTube uses its own session
    /// state (default date order) instead of the persisted library sort.
    private var activeColumnSortId: String? {
        currentSource.isYouTube ? youtubeColumnSortId : columnSortId
    }
    private var activeColumnSortAscending: Bool {
        currentSource.isYouTube ? youtubeColumnSortAscending : columnSortAscending
    }
    
    // Visible columns (ordered lists of column IDs; persisted to UserDefaults)
    private var visibleTrackColumnIds: [String] = ModernBrowserColumn.defaultTrackColumnIds { didSet { saveVisibleColumns() } }
    private var visibleAlbumColumnIds: [String] = ModernBrowserColumn.defaultAlbumColumnIds { didSet { saveVisibleColumns() } }
    private var visibleArtistColumnIds: [String] = ModernBrowserColumn.defaultArtistColumnIds { didSet { saveVisibleColumns() } }

    // Display items
    private var displayItems: [ModernDisplayItem] = []
    
    // Expanded state
    private var expandedArtists: Set<String> = []
    private var expandedAlbums: Set<String> = []
    private var expandedArtistNames: Set<String> = []
    private var expandedLocalArtists: Set<String> = []
    private var expandedLocalAlbums: Set<String> = []
    private var expandedLocalShows: Set<String> = []
    private var expandedLocalSeasons: Set<String> = []
    private var expandedLocalFolders: Set<String> = []
    /// Bumped on each Folders rebuild; an in-flight off-actor walk discards its result if stale.
    private var localFolderBuildGeneration = 0
    /// The in-flight Folders walk, cancelled when a newer rebuild starts (fast-click protection).
    private var localFolderBuildTask: Task<Void, Never>?
    private var expandedSubsonicArtists: Set<String> = []
    private var expandedSubsonicAlbums: Set<String> = []
    private var expandedSubsonicPlaylists: Set<String> = []
    private var expandedPlexPlaylists: Set<String> = []
    private var expandedShows: Set<String> = []
    private var expandedSeasons: Set<String> = []
    
    // Loading state
    private var isLoading: Bool = false
    private var errorMessage: String?
    
    // Cached data - Plex
    private var cachedArtists: [PlexArtist] = []
    private var cachedAlbums: [PlexAlbum] = []
    private var cachedTracks: [PlexTrack] = []
    private var artistAlbums: [String: [PlexAlbum]] = [:]
    private var albumTracks: [String: [PlexTrack]] = [:]
    private var artistAlbumCounts: [String: Int] = [:]
    private var plexArtistGroupsByName: [String: [PlexArtist]] = [:]
    private var plexAlbumsByArtistGroupKey: [String: [PlexAlbum]] = [:]
    private var plexAlbumCountsByArtistGroupKey: [String: Int] = [:]
    private var artistAlbumsByName: [String: [PlexAlbum]] = [:]
    
    // Cached data - Local
    // Paginated local data state (replaces full in-memory caches)
    private var localArtistPageOffset = 0
    private var localAlbumPageOffset = 0
    private let localPageSize = 200
    private var localArtistTotal = 0
    private var localAlbumTotal = 0
    private var localArtistLetterOffsets: [String: Int] = [:]
    private var localAlbumLetterOffsets: [String: Int] = [:]
    private var cachedLocalMovies: [LocalVideo] = []
    private var cachedLocalShows: [LocalShow] = []
    private var localLibraryReloadWorkItem: DispatchWorkItem?

    // Offline volume state (populated by loadLocalData)
    private var offlineWatchFolders: [WatchFolderSummary] = []
    private var offlineVolumePrefixes: Set<String> = []

    // Local Plists slot toggle state (switch between Plists and Folders)
    private var localPlistsSlotShowsFolders: Bool {
        get { UserDefaults.standard.object(forKey: "LocalPlistsSlotShowsFolders") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "LocalPlistsSlotShowsFolders") }
    }

    private var effectivePlistsSlotMode: ModernBrowseMode {
        if case .local = currentSource, localPlistsSlotShowsFolders {
            return .folders
        }
        return .plists
    }

    /// The Radio tab slot toggles between Internet Radio stations and YouTube
    /// channels (YouTube source only), mirroring the Plists/Folders toggle.
    /// Defaults to showing channels so the YouTube source opens on "Channels".
    private var radioSlotShowsChannels: Bool {
        get { UserDefaults.standard.object(forKey: "RadioSlotShowsChannels") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "RadioSlotShowsChannels") }
    }
    /// Whether the Radio tab slot is currently displaying YouTube channels.
    private var radioSlotShowingChannels: Bool {
        currentSource.isYouTube && radioSlotShowsChannels
    }

    private var isLocalSource: Bool {
        if case .local = currentSource { return true }
        return false
    }

    private func cancelLocalFolderBuild() {
        localFolderBuildGeneration &+= 1
        localFolderBuildTask?.cancel()
        localFolderBuildTask = nil
    }

    // Cached data - Local Playlists
    private var expandedLocalPlaylists: Set<String> = []
    private var localPlaylistTracks: [String: [Track]] = [:]
    private var cachedLocalPlaylists: [LocalPlaylist] = []

    // Cached data - Subsonic
    private var cachedSubsonicArtists: [SubsonicArtist] = []
    private var cachedSubsonicAlbums: [SubsonicAlbum] = []
    private var cachedSubsonicPlaylists: [SubsonicPlaylist] = []
    private var subsonicArtistAlbums: [String: [SubsonicAlbum]] = [:]
    private var subsonicPlaylistTracks: [String: [SubsonicSong]] = [:]
    private var subsonicAlbumSongs: [String: [SubsonicSong]] = [:]
    private var subsonicLoadTask: Task<Void, Never>?
    private var subsonicExpandTask: Task<Void, Never>?
    private var plexLoadTask: Task<Void, Never>?
    private var sourceConnectTask: Task<Void, Never>?
    
    // Cached data - Jellyfin
    private var cachedJellyfinArtists: [JellyfinArtist] = []
    private var cachedJellyfinAlbums: [JellyfinAlbum] = []
    private var cachedJellyfinPlaylists: [JellyfinPlaylist] = []
    private var jellyfinArtistAlbums: [String: [JellyfinAlbum]] = [:]
    private var jellyfinPlaylistTracks: [String: [JellyfinSong]] = [:]
    private var jellyfinAlbumSongs: [String: [JellyfinSong]] = [:]
    private var jellyfinLoadTask: Task<Void, Never>?
    private var jellyfinAlbumWarmTask: Task<Void, Never>?
    private var jellyfinExpandTask: Task<Void, Never>?
    private var expandedJellyfinArtists: Set<String> = []
    private var expandedJellyfinAlbums: Set<String> = []
    private var expandedJellyfinPlaylists: Set<String> = []
    
    // Cached data - Radio
    private var cachedRadioStations: [RadioStation] = []
    private var cachedRadioFolders: [RadioFolderDescriptor] = []
    private var expandedRadioFolders: Set<String> = []
    private var activeRadioStationSheet: AddRadioStationSheet?
    private var activeYouTubeChannelSheet: AddYouTubeChannelSheet?

    // Cached data - YouTube
    private var expandedYouTubeChannels: Set<String> = []
    private var youtubeChannelVideos: [String: [YouTubeVideo]] = [:]
    private var youtubeExpandTask: Task<Void, Never>?
    private var youtubeDownloadTask: Task<Void, Never>?
    /// Video IDs currently downloading — drives a per-row spinner on the video entry.
    private var downloadingVideoIds: Set<String> = []
    /// Channel IDs whose uploads are currently being fetched — drives a per-row spinner on the channel entry.
    private var loadingChannelIds: Set<String> = []

    // Cached data - Video (Plex)
    private var cachedMovies: [PlexMovie] = []
    private var cachedShows: [PlexShow] = []
    private var showSeasons: [String: [PlexSeason]] = [:]
    private var seasonEpisodes: [String: [PlexEpisode]] = [:]
    
    // Cached data - Video (Jellyfin)
    private var cachedJellyfinMovies: [JellyfinMovie] = []
    private var cachedJellyfinShows: [JellyfinShow] = []
    private var jellyfinShowSeasons: [String: [JellyfinSeason]] = [:]
    private var jellyfinSeasonEpisodes: [String: [JellyfinEpisode]] = [:]
    private var expandedJellyfinShows: Set<String> = []
    private var expandedJellyfinSeasons: Set<String> = []

    // Cached data - Emby
    private var cachedEmbyArtists: [EmbyArtist] = []
    private var cachedEmbyAlbums: [EmbyAlbum] = []
    private var cachedEmbyPlaylists: [EmbyPlaylist] = []
    private var embyArtistAlbums: [String: [EmbyAlbum]] = [:]
    private var embyPlaylistTracks: [String: [EmbySong]] = [:]
    private var embyAlbumSongs: [String: [EmbySong]] = [:]
    private var embyLoadTask: Task<Void, Never>?
    private var embyExpandTask: Task<Void, Never>?
    private var expandedEmbyArtists: Set<String> = []
    private var expandedEmbyAlbums: Set<String> = []
    private var expandedEmbyPlaylists: Set<String> = []

    // Cached data - Video (Emby)
    private var cachedEmbyMovies: [EmbyMovie] = []
    private var cachedEmbyShows: [EmbyShow] = []
    private var embyShowSeasons: [String: [EmbySeason]] = [:]
    private var embySeasonEpisodes: [String: [EmbyEpisode]] = [:]
    private var expandedEmbyShows: Set<String> = []
    private var expandedEmbySeasons: Set<String> = []

    // Cached data - Playlists (Plex)
    private var cachedPlexPlaylists: [PlexPlaylist] = []
    private var plexPlaylistTracks: [String: [PlexTrack]] = [:]
    
    // Search
    private var searchResults: PlexSearchResults?
    private var jellyfinSearchResults: JellyfinSearchResults?
    private var subsonicSearchResults: SubsonicSearchResults?
    private var embySearchResults: EmbySearchResults?
    private var pendingScrollToArtistId: String?
    private var pendingScrollToArtistName: String?
    private var pendingScrollAttempts = 0
    private var pendingArtistLoadUnfiltered = false

    // Animation
    private var loadingAnimationTimer: Timer?
    private var loadingAnimationFrame: Int = 0
    /// Local library scan animation (server bar spinner)
    private var isLibraryScanning = false
    private var serverNameScrollOffset: CGFloat = 0
    private var libraryNameScrollOffset: CGFloat = 0
    private var serverScrollTimer: Timer?
    private var lastServerName: String = ""
    private var lastLibraryName: String = ""

    /// Cached server bar font and attribute dictionaries — invalidated when skin changes
    private var cachedServerBarFont: NSFont?
    private var cachedServerBarFontSkinName: String?
    private var cachedServerBarFontScale: CGFloat?
    private var cachedServerBarIsMetal: Bool?
    private var cachedPrefixAttrs: [NSAttributedString.Key: Any]?
    private var cachedDataAttrs: [NSAttributedString.Key: Any]?
    private var cachedActiveAttrs: [NSAttributedString.Key: Any]?
    private var serverNameTextWidth: CGFloat = 0
    private var libraryNameTextWidth: CGFloat = 0
    private var serverNameMaxWidth: CGFloat = 0
    private var libraryNameMaxWidth: CGFloat = 0
    
    // Shade mode
    private(set) var isShadeMode = false

    /// Highlight state for drag-mode visual feedback
    private var isHighlighted = false
    
    // Art-only mode
    private var isArtOnlyMode: Bool = false {
        didSet {
            artModeLifecycleGeneration &+= 1
            needsDisplay = true
            if isArtOnlyMode { fetchCurrentTrackRating(); loadAllArtworkForCurrentTrack() }
            else {
                isVisualizingArt = false
                artworkCyclingTask?.cancel()
                artworkCyclingTask = nil
                artworkImages = []
                artworkIndex = 0
            }
        }
    }
    private var artModeLifecycleGeneration = 0
    private var isVisualizingArt: Bool = false {
        didSet {
            if isVisualizingArt { startVisualizerTimer() } else { stopVisualizerTimer() }
            needsDisplay = true
        }
    }
    
    // Rating overlay
    private var isRatingOverlayVisible: Bool = false
    // Delayed to differentiate single-click (rate) vs double-click (cycle artwork) in art mode.
    private var pendingArtSingleClickWorkItem: DispatchWorkItem?
    private var currentTrackRating: Int? = nil
    private var rateButtonRect: NSRect = .zero
    private var ratingSubmitTask: Task<Void, Never>?
    
    // Artwork
    private var currentArtwork: NSImage?
    private var artworkTrackId: UUID?
    private var artworkLoadTask: Task<Void, Never>?
    private var artworkCyclingTask: Task<Void, Never>?
    private var radioLoadTask: Task<Void, Never>?
    private var radioPlayTask: Task<Void, Never>?
    private var loadGeneration: Int = 0
    private static let artworkCache = NSCache<NSString, NSImage>()
    private var artworkImages: [NSImage] = []
    private var artworkIndex: Int = 0
    
    // Visualization
    enum VisEffect: String, CaseIterable {
        case psychedelic = "Psychedelic", kaleidoscope = "Kaleidoscope", vortex = "Vortex", spin = "Endless Spin"
        case fractal = "Fractal Zoom", tunnel = "Time Tunnel", melt = "Acid Melt", wave = "Ocean Wave"
        case glitch = "Glitch", rgbSplit = "RGB Split", twist = "Twist", fisheye = "Fisheye"
        case shatter = "Shatter", stretch = "Rubber Band", zoom = "Zoom Pulse", shake = "Earthquake"
        case bounce = "Bounce", feedback = "Feedback Loop", strobe = "Strobe", jitter = "Jitter"
        case mirror = "Infinite Mirror", tile = "Tile Grid", prism = "Prism Split", doubleVision = "Double Vision"
        case flipbook = "Flipbook", mosaic = "Mosaic", pixelate = "Pixelate", scanlines = "Scanlines"
        case datamosh = "Datamosh", blocky = "Blocky"
        static let groups: [(title: String, effects: [VisEffect])] = [
            ("Rotation & Scaling", [.psychedelic, .kaleidoscope, .vortex, .spin, .fractal, .tunnel]),
            ("Distortion",         [.melt, .wave, .glitch, .rgbSplit, .twist, .fisheye, .shatter, .stretch]),
            ("Motion",             [.zoom, .shake, .bounce, .feedback, .strobe, .jitter]),
            ("Copies & Mirrors",   [.mirror, .tile, .prism, .doubleVision, .flipbook, .mosaic]),
            ("Pixel Effects",      [.pixelate, .scanlines, .datamosh, .blocky]),
        ]
    }
    enum VisMode { case single, random, cycle }
    private var currentVisEffect: VisEffect = .psychedelic
    private var visMode: VisMode = .single
    private var cycleTimer: Timer?
    private var cycleInterval: TimeInterval = 10.0
    private var lastBeatTime: TimeInterval = 0
    private var visEffectIntensity: CGFloat = 1.0
    private var visualizerTimer: Timer?
    private var isVisualizerConsumerRegistered = false
    private var visualizerTime: TimeInterval = 0
    private var lastAudioLevel: Float = 0
    private var silenceFrames: Int = 0
    private var visualizerWasActiveBeforeHide: Bool = false
    private lazy var ciContext: CIContext = {
        if let mtlDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: mtlDevice, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()
    
    /// Which edges are adjacent to another docked window (for seamless border rendering)
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty
    
    // Button/drag state
    private var pressedButton: LibraryBrowserButtonType?
    private var activeTagsPanel: TagsPanel?
    private var activeEditTagsPanel: EditTagsPanel?
    private var activeEditAlbumTagsPanel: EditAlbumTagsPanel?
    private var activeEditVideoTagsPanel: EditVideoTagsPanel?
    private struct SeasonRef { let season: LocalSeason; let showTitle: String }
    private struct RadioFolderMembershipAction {
        let station: RadioStation
        let folderID: UUID
    }
    private struct RadioSmartGenreAction {
        let station: RadioStation
        let genre: String?
    }
    private struct RadioSmartRegionAction {
        let station: RadioStation
        let region: String?
    }
    private struct RadioFolderRenameAction { let folderID: UUID }
    private struct RadioFolderDeleteAction { let folderID: UUID }
    private struct RadioFolderStationAction { let station: RadioStation }
    private var isDraggingWindow = false
    /// True when hide-title-bars mode primed drag hold timing on mouseDown.
    private var didPrimeWindowDragHold = false
    private var windowDragStartPoint: NSPoint = .zero
    private var isDraggingScrollbar = false
    private var scrollbarDragStartY: CGFloat = 0
    private var scrollbarDragStartOffset: CGFloat = 0
    private let alphabetLetters = ["#"] + (65...90).map { String(UnicodeScalar($0)) }
    
    // MARK: - Layout Constants (independent of classic skin)
    
    private struct Layout {
        static var titleBarHeight: CGFloat {
            WindowManager.shared.hideTitleBars ? Layout.borderWidth : ModernSkinElements.libraryTitleBarHeight
        }
        static var tabBarHeight: CGFloat { 24 * ModernSkinElements.sizeMultiplier }
        static var serverBarHeight: CGFloat { 24 * ModernSkinElements.sizeMultiplier }
        static var searchBarHeight: CGFloat { 26 * ModernSkinElements.sizeMultiplier }
        static var statusBarHeight: CGFloat { 6 * ModernSkinElements.sizeMultiplier }
        static var offlineBannerHeight: CGFloat { 18 * ModernSkinElements.sizeMultiplier }
        static let scrollbarWidth: CGFloat = 0
        static var alphabetWidth: CGFloat { 16 * ModernSkinElements.sizeMultiplier }
        static var borderWidth: CGFloat { ModernSkinElements.libraryBorderWidth }
        static var padding: CGFloat { 3 * ModernSkinElements.sizeMultiplier }
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // Load skin
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        
        // Load saved column widths, visibility, and sort
        loadColumnWidths()
        loadVisibleColumns()
        loadColumnSort()
        
        // Load saved source
        if let savedSource = ModernBrowserSource.load() {
            switch savedSource {
            case .local:
                currentSource = .local
            case .plex(let serverId):
                if PlexManager.shared.isLinked {
                    if PlexManager.shared.servers.contains(where: { $0.id == serverId }) {
                        currentSource = savedSource
                    } else if PlexManager.shared.servers.isEmpty {
                        pendingSourceRestore = savedSource
                        currentSource = .local
                    } else if let firstServer = PlexManager.shared.servers.first {
                        currentSource = .plex(serverId: firstServer.id)
                    } else {
                        currentSource = .local
                    }
                } else {
                    currentSource = .local
                }
            case .subsonic(let serverId):
                if SubsonicManager.shared.servers.contains(where: { $0.id == serverId }) {
                    currentSource = savedSource
                } else if SubsonicManager.shared.servers.isEmpty {
                    pendingSourceRestore = savedSource
                    currentSource = .local
                } else if let firstServer = SubsonicManager.shared.servers.first {
                    currentSource = .subsonic(serverId: firstServer.id)
                } else {
                    currentSource = .local
                }
            case .jellyfin(let serverId):
                if JellyfinManager.shared.servers.contains(where: { $0.id == serverId }) {
                    currentSource = savedSource
                } else if JellyfinManager.shared.servers.isEmpty {
                    pendingSourceRestore = savedSource
                    currentSource = .local
                } else if let firstServer = JellyfinManager.shared.servers.first {
                    currentSource = .jellyfin(serverId: firstServer.id)
                } else {
                    currentSource = .local
                }
            case .emby(let serverId):
                if EmbyManager.shared.servers.contains(where: { $0.id == serverId }) {
                    currentSource = savedSource
                } else if EmbyManager.shared.servers.isEmpty {
                    pendingSourceRestore = savedSource
                    currentSource = .local
                } else if let firstServer = EmbyManager.shared.servers.first {
                    currentSource = .emby(serverId: firstServer.id)
                } else {
                    currentSource = .local
                }
            case .radio:
                currentSource = .radio
            case .youtube:
                currentSource = .youtube
            }
        } else {
            if PlexManager.shared.isLinked, let firstServer = PlexManager.shared.servers.first {
                currentSource = .plex(serverId: firstServer.id)
            } else {
                currentSource = .local
            }
        }
        
        // Load saved sort option
        currentSort = ModernBrowserSortOption.load()
        
        // Art-only mode always starts disabled
        isArtOnlyMode = false
        
        // Load saved visualizer preferences — default effect takes priority over last-used
        let defaultEffectKey = UserDefaults.standard.string(forKey: "browserVisDefaultEffect")
        let lastUsedKey = UserDefaults.standard.string(forKey: "browserVisEffect")
        if let raw = defaultEffectKey ?? lastUsedKey, let effect = VisEffect(rawValue: raw) {
            currentVisEffect = effect
        }
        if UserDefaults.standard.object(forKey: "browserVisIntensity") != nil {
            visEffectIntensity = CGFloat(UserDefaults.standard.double(forKey: "browserVisIntensity"))
        }
        
        // Register notifications
        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                               name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                               name: .doubleSizeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowLayoutDidChange),
                                               name: .windowLayoutDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(plexStateDidChange),
                                               name: PlexManager.accountDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(plexStateDidChange),
                                               name: PlexManager.libraryDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(plexStateDidChange),
                                               name: PlexManager.connectionStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(plexServerDidChange),
                                               name: PlexManager.serversDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(plexContentDidPreload),
                                               name: PlexManager.libraryContentDidPreloadNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mediaLibraryDidChange),
                                               name: MediaLibrary.libraryDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(radioStationsDidChange),
                                               name: RadioManager.stationsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(youtubeChannelsDidChange),
                                               name: YouTubeManager.youtubeChannelsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(youtubeVideoLimitDidChange),
                                               name: YouTubeManager.youtubeVideoLimitDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(trackDidChange),
                                               name: .audioTrackDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playHistoryDidChange),
                                               name: MediaLibraryStore.playHistoryDidChangeNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(jellyfinMusicLibraryDidChange),
                                               name: JellyfinManager.musicLibraryDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(jellyfinVideoLibraryDidChange),
                                               name: JellyfinManager.videoLibraryDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(embyMusicLibraryDidChange),
                                               name: EmbyManager.musicLibraryDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(embyVideoLibraryDidChange),
                                               name: EmbyManager.videoLibraryDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(embyLibraryContentDidPreload),
                                               name: EmbyManager.libraryContentDidPreloadNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(embyConnectionStateDidChange),
                                               name: EmbyManager.connectionStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(subsonicMusicFolderDidChange),
                                               name: SubsonicManager.musicFolderDidChangeNotification, object: nil)
        
        // External source selection (e.g. Subsonic/Jellyfin menu > Show in Library Browser)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSetBrowserSource(_:)),
                                               name: NSNotification.Name("SetBrowserSource"), object: nil)
        
        // Window visibility notifications
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMiniaturize),
                                               name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidDeminiaturize),
                                               name: NSWindow.didDeminiaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeOcclusionState),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryScanProgressChanged),
                                               name: MediaLibrary.scanProgressNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                               name: .connectedWindowHighlightDidChange, object: nil)

        // Register for drag and drop
        registerForDraggedTypes([.fileURL])
        
        // Initial data load
        reloadData()
        
        // Start server name scroll animation
        startServerNameScroll()
        
        // Load artwork for current track
        if WindowManager.shared.showBrowserArtworkBackground {
            loadArtwork(for: WindowManager.shared.audioEngine.currentTrack)
        }
        
        // Set accessibility
        setAccessibilityIdentifier("modernLibraryBrowserView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Library Browser")
        updateCornerMask()
        updateHistoryHostingVisibility()
    }
    
    deinit {
        cancelPendingArtSingleClickAction()
        localLibraryReloadWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        stopLoadingAnimation(force: true)
        stopServerNameScroll()
        stopVisualizerTimer()
    }

    /// Synchronously cancel every in-flight task, work item, and timer this view owns so it can
    /// be deallocated immediately when the controller is torn down for a UI reload — rather than
    /// being pinned alive (and mutating dead UI state) by a detached `@MainActor` expand/load task
    /// or a self-retaining repeating timer. `deinit` is deferred by AppKit's autorelease pool, so
    /// `WindowManager.teardownModeDependentWindows()` calls this *before* closing the window.
    func prepareForUITeardown() {
        // Async tasks — the detached @MainActor expand/load tasks don't inherit cancellation and
        // strongly capture self, so an in-flight one would survive teardown without this.
        for task in [localFolderBuildTask,
                     subsonicLoadTask, subsonicExpandTask,
                     plexLoadTask, sourceConnectTask,
                     jellyfinLoadTask, jellyfinAlbumWarmTask, jellyfinExpandTask,
                     youtubeExpandTask, youtubeDownloadTask,
                     embyLoadTask, embyExpandTask,
                     ratingSubmitTask, artworkLoadTask, artworkCyclingTask,
                     radioLoadTask, radioPlayTask] {
            task?.cancel()
        }
        localFolderBuildTask = nil
        subsonicLoadTask = nil; subsonicExpandTask = nil
        plexLoadTask = nil; sourceConnectTask = nil
        jellyfinLoadTask = nil; jellyfinAlbumWarmTask = nil; jellyfinExpandTask = nil
        youtubeExpandTask = nil; youtubeDownloadTask = nil
        embyLoadTask = nil; embyExpandTask = nil
        ratingSubmitTask = nil; artworkLoadTask = nil; artworkCyclingTask = nil
        radioLoadTask = nil; radioPlayTask = nil

        // Work items + timers (timers with a target/captured self can also pin the view alive).
        cancelPendingArtSingleClickAction()
        localLibraryReloadWorkItem?.cancel(); localLibraryReloadWorkItem = nil
        typeAheadTimer?.invalidate(); typeAheadTimer = nil
        stopLoadingAnimation(force: true)
        stopServerNameScroll()
        stopVisualizerTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        updateCornerMask()
        updateEmbeddedSubviewFrames()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        startServerNameScroll()
        updateEmbeddedSubviewFrames()
    }

    override func layout() {
        super.layout()
        updateEmbeddedSubviewFrames()
    }

    // MARK: - Current Skin Helper
    
    private func currentSkin() -> ModernSkin {
        return ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
    }

    private func updateCornerMask() {
        guard let layer = self.layer else { return }
        let cornerRadius = currentSkin().config.window.cornerRadius ?? 0
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
        guard cornerRadius > 0 else { return }
        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                         .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = allCorners.subtracting(sharpCorners)
    }

    private func skinAppearance(for skin: ModernSkin) -> NSAppearance? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        skin.backgroundColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let brightness = 0.299 * r + 0.587 * g + 0.114 * b
        return NSAppearance(named: brightness < 0.5 ? .darkAqua : .aqua)
    }

    private func makeHistoryHostingView() -> NSHostingView<StatsContentView> {
        let skin = currentSkin()
        let rootView = StatsContentView(agent: historyAgent,
                                        skinTextColor: Color(skin.textColor),
                                        headerTitle: "Library Data")
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = skin.backgroundColor.withAlphaComponent(1.0).cgColor
        hostingView.layer?.isOpaque = true
        hostingView.appearance = skinAppearance(for: skin)
        hostingView.setAccessibilityIdentifier("modernLibraryBrowser.data")
        hostingView.setAccessibilityLabel("Library Data")
        return hostingView
    }

    private func ensureHistoryHostingView() {
        guard historyHostingView == nil else { return }
        let hostingView = makeHistoryHostingView()
        addSubview(hostingView)
        historyHostingView = hostingView
        updateEmbeddedSubviewFrames()
    }

    private func updateHistoryHostingVisibility() {
        if browseMode.isHistoryMode {
            ensureHistoryHostingView()
        }
        let isVisible = browseMode.isHistoryMode && !isShadeMode && !isArtOnlyMode
        historyHostingView?.isHidden = !isVisible
        updateEmbeddedSubviewFrames()
    }

    private func embeddedHistoryContentRect() -> NSRect {
        guard !isShadeMode else { return .zero }
        var contentTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let statusBarHeight = Layout.statusBarHeight
        return NSRect(
            x: Layout.borderWidth,
            y: statusBarHeight,
            width: bounds.width - Layout.borderWidth * 2,
            height: max(0, contentTopY - statusBarHeight)
        )
    }

    private func updateEmbeddedSubviewFrames() {
        historyHostingView?.frame = embeddedHistoryContentRect()
        if !isRatingOverlayVisible {
            ratingOverlay.frame = bounds
        }
        updateCompactPlayerBarFrame()
    }

    /// Create/position/remove the embedded compact player bar to match the current mode.
    private func updateCompactPlayerBarFrame() {
        guard compactMode && !isShadeMode else {
            compactPlayerBar?.removeFromSuperview()
            compactPlayerBar = nil
            return
        }
        let bar: CompactPlayerBarView
        if let existing = compactPlayerBar {
            bar = existing
        } else {
            bar = CompactPlayerBarView(frame: .zero)
            addSubview(bar)
            compactPlayerBar = bar
            seedCompactPlayerBar(bar)
        }
        bar.frame = NSRect(x: Layout.borderWidth, y: topChromeBottomY,
                           width: bounds.width - Layout.borderWidth * 2,
                           height: compactPlayerBarHeight)
    }

    /// Seed the bar with the engine's current state so it isn't blank until the next update tick.
    private func seedCompactPlayerBar(_ bar: CompactPlayerBarView) {
        let engine = WindowManager.shared.audioEngine
        bar.updateTrackInfo(engine.currentTrack)
        bar.updateTime(current: engine.currentTime, duration: engine.duration)
        bar.updatePlaybackState()
    }

    // MARK: - Compact Player Bar Forwarding

    func compactBarUpdateTime(current: TimeInterval, duration: TimeInterval) {
        compactPlayerBar?.updateTime(current: current, duration: duration)
    }

    func compactBarUpdateTrack(_ track: Track?) {
        compactPlayerBar?.updateTrackInfo(track)
    }

    func compactBarUpdatePlaybackState() {
        compactPlayerBar?.updatePlaybackState()
    }

    private var isMetalRenderStyle: Bool {
        // Read from the skin we actually draw with (currentSkin()), not the engine's global
        // currentRenderStyle. The two can momentarily disagree across a skin swap, which let
        // the modern darkened top-chrome band paint over the metal brushed surface.
        currentSkin().renderStyle == .metal
    }

    /// Active metal finish (falls back to Brushed Steel). The control colors below are
    /// derived from its per-finish EQ control palette so they adapt to dark finishes:
    /// on Anodized Black / Gunmetal the band fills go dark and the strokes go light, so
    /// the tab/control boxes stay visible instead of washing out against the chrome.
    private var metalMaterial: MetalMaterial {
        ModernSkinEngine.shared.currentSkin?.metalMaterial ?? .brushedSteel
    }

    // Header/alphabet band — the strip wrapping the top and the right-side alphabet index.
    // In metal mode the top chrome and alphabet index blend into the brushed-metal panel
    // (no darker overlay) so the whole window reads as a single continuous surface.
    private var metalControlBandFill: NSColor {
        .clear
    }

    private var metalControlFill: NSColor {
        metalMaterial.eqControlFill
    }

    private var metalControlActiveFill: NSColor {
        metalMaterial.eqActiveFill
    }

    private var metalControlStroke: NSColor {
        metalMaterial.eqStroke
    }

    private var metalRatingColor: NSColor {
        NSColor(calibratedRed: 0.34, green: 0.28, blue: 0.13, alpha: 1.0)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        let capturedArtwork = currentArtwork
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let skin = currentSkin()
        let mainOpacity = skin.resolvedOpacity(for: .mainWindow)
        
        if isShadeMode {
            // Draw shade mode
            renderer.drawWindowBackground(
                in: bounds,
                context: context,
                adjacentEdges: adjacentEdges,
                sharpCorners: sharpCorners,
                backgroundOpacity: mainOpacity.background
            )
            renderer.drawWindowBorder(
                in: bounds,
                context: context,
                adjacentEdges: adjacentEdges,
                sharpCorners: sharpCorners,
                occlusionSegments: edgeOcclusionSegments,
                borderOpacity: mainOpacity.border
            )
            
            context.saveGState()
            context.setAlpha(mainOpacity.content)
            // Draw title text centered (using renderer for image text support)
            let shadeScale = ModernSkinElements.scaleFactor
            let titleRect = NSRect(x: 0, y: 0, width: bounds.width / shadeScale, height: bounds.height / shadeScale)
            renderer.drawTitleBar(in: titleRect, title: "NULLPLAYER LIBRARY", prefix: "library_", context: context)
            
            // Draw close and shade buttons (base space for renderer scaling)
            let shadeBaseW = bounds.width / shadeScale
            let shadeBaseH = bounds.height / shadeScale
            let closeBtnRect = NSRect(x: shadeBaseW - 14, y: (shadeBaseH - 10) / 2, width: 10, height: 10)
            let shadeBtnRect = NSRect(x: shadeBaseW - 26, y: (shadeBaseH - 10) / 2, width: 10, height: 10)
            let closeState = pressedButton == .close ? "pressed" : "normal"
            let shadeState = pressedButton == .shade ? "pressed" : "normal"
            renderer.drawWindowControlButton("library_btn_close", state: closeState, in: closeBtnRect, context: context)
            renderer.drawWindowControlButton("library_btn_shade", state: shadeState, in: shadeBtnRect, context: context)
            context.restoreGState()
            if isHighlighted {
                NSColor.white.withAlphaComponent(0.15).setFill()
                bounds.fill()
            }
            return
        }

        // Fast path: scroll timer marks only server bar dirty — skip full window redraw.
        // Always fill the full background first (copy blend mode) so the layer is never
        // left partially transparent from accumulated alpha on repeated scroll-tick draws.
        let serverBarY = topChromeBottomY - Layout.serverBarHeight
        let sbRect = NSRect(x: 0, y: serverBarY, width: bounds.width, height: Layout.serverBarHeight)
        if sbRect.contains(dirtyRect) {
            // Build the renderer from the current skin (not the cached instance) so the
            // background can't lag a skin swap and render the wrong surface under the bands.
            let renderer = ModernSkinRenderer(skin: skin)
            renderer.drawWindowBackground(
                in: bounds,
                context: context,
                adjacentEdges: adjacentEdges,
                sharpCorners: sharpCorners,
                backgroundOpacity: mainOpacity.background,
                drawMetalAccentStrip: false
            )
            context.saveGState()
            context.setAlpha(mainOpacity.content)
            drawServerBar(in: context, serverBarY: serverBarY, skin: skin)
            context.restoreGState()
            return
        }

        // Normal mode - bottom-left origin (no coordinate flipping)
        let renderer = ModernSkinRenderer(skin: skin)
        renderer.drawWindowBackground(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            backgroundOpacity: mainOpacity.background,
            drawMetalAccentStrip: false
        )
        renderer.drawWindowBorder(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            occlusionSegments: edgeOcclusionSegments,
            borderOpacity: mainOpacity.border
        )

        context.saveGState()
        context.setAlpha(mainOpacity.content)
        
        // Title bar, close, shade buttons use base (unscaled) coordinates
        // because the renderer's scaledRect() multiplies by scaleFactor
        let scale = ModernSkinElements.scaleFactor
        let baseWidth = bounds.width / scale
        let baseHeight = bounds.height / scale
        
        // Draw title bar
        if !WindowManager.shared.hideTitleBars {
            // Title bar at TOP in base space
            let tbh = ModernSkinElements.titleBarBaseHeight
            let titleBarRect = NSRect(x: 0, y: baseHeight - tbh, width: baseWidth, height: tbh)
            renderer.drawTitleBar(in: titleBarRect, title: "NULLPLAYER LIBRARY", prefix: "library_", context: context)

            // Close and shade buttons in title bar (base space)
            let closeBtnRect = NSRect(x: baseWidth - 14, y: baseHeight - tbh / 2 - 5, width: 10, height: 10)
            let shadeBtnRect = NSRect(x: baseWidth - 26, y: baseHeight - tbh / 2 - 5, width: 10, height: 10)
            let closeState = pressedButton == .close ? "pressed" : "normal"
            let shadeState = pressedButton == .shade ? "pressed" : "normal"
            renderer.drawWindowControlButton("library_btn_close", state: closeState, in: closeBtnRect, context: context)
            renderer.drawWindowControlButton("library_btn_shade", state: shadeState, in: shadeBtnRect, context: context)
        }
        
        // Server bar (below title bar in screen coords)
        drawServerBar(in: context, serverBarY: serverBarY, skin: skin)
        
        // Tab bar (below server bar)
        let tabBarY = serverBarY - Layout.tabBarHeight
        drawTabBar(in: context, tabBarY: tabBarY, skin: skin)
        
        // Search bar (below tab bar, only in search mode)
        var contentTopY = tabBarY
        if browseMode == .search {
            contentTopY -= Layout.searchBarHeight
            drawSearchBar(in: context, searchBarY: contentTopY, skin: skin)
        }
        
        // Status bar at bottom
        let statusBarHeight = Layout.statusBarHeight

        // Offline volume banner (local source only, above list content)
        let showOfflineBanner = isLocalSource && !offlineWatchFolders.isEmpty
        let bannerHeight = showOfflineBanner ? Layout.offlineBannerHeight : 0

        // List area (between content top and status bar bottom)
        let listAreaY = statusBarHeight + bannerHeight
        let listAreaHeight = contentTopY - statusBarHeight - bannerHeight
        let listRect = NSRect(x: Layout.borderWidth, y: listAreaY,
                              width: bounds.width - Layout.borderWidth * 2, height: listAreaHeight)

        updateHistoryHostingVisibility()

        if showOfflineBanner {
            let bannerRect = NSRect(x: Layout.borderWidth, y: statusBarHeight,
                                   width: bounds.width - Layout.borderWidth * 2, height: bannerHeight)
            drawOfflineBanner(in: context, rect: bannerRect, skin: skin)
        }

        if browseMode.isHistoryMode {
            drawArtworkBackground(in: context, listRect: listRect, artwork: capturedArtwork)
            // SwiftUI-hosted history content is rendered via an embedded subview.
        } else if isArtOnlyMode {
            // Art-only mode takes precedence over loading/error states (matches PlexBrowserView)
            // so that visualization continues uninterrupted during data refreshes
            drawArtOnlyArea(in: context, contentRect: listRect, skin: skin, artwork: capturedArtwork)
        } else if currentSource.isPlex && !PlexManager.shared.isLinked {
            drawNotLinkedState(in: context, listRect: listRect, skin: skin)
        } else if isLoading {
            drawLoadingState(in: context, listRect: listRect, skin: skin)
        } else if let error = errorMessage {
            drawErrorState(in: context, message: error, listRect: listRect, skin: skin)
        } else {
            drawListArea(in: context, listAreaY: listAreaY, listAreaHeight: listAreaHeight, skin: skin, artwork: capturedArtwork)
        }
        
        // Status bar text
        drawStatusBarText(in: context, skin: skin)
        context.restoreGState()

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    // MARK: - Tab Bar Drawing (Modern Boxed Toggle Style)
    
    /// The label shown in each tab slot (some slots are dynamic), in `allCases` order.
    private func currentTabLabels() -> [String] {
        ModernBrowseMode.allCases.map { mode in
            // plists slot shows "Folders" when toggled on a local source.
            if mode == .plists, localPlistsSlotShowsFolders, case .local = currentSource {
                return "Folders"
            }
            // radio slot shows "Channels" when the YouTube source is displaying channels.
            if mode == .radio, radioSlotShowingChannels {
                return "Channels"
            }
            return mode.title
        }
    }

    /// Per-tab widths across the tab bar. Content-aware: each tab is sized to its own label
    /// plus padding, then any leftover space is shared equally so every tab gets some
    /// breathing room and short labels (e.g. "TV", "Data") don't hog equal width.
    private func tabBarWidths(totalWidth: CGFloat, labels: [String], font: NSFont) -> [CGFloat] {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let padding = 18 * ModernSkinElements.sizeMultiplier
        let natural = labels.map { $0.size(withAttributes: attrs).width + padding }
        let naturalSum = natural.reduce(0, +)
        if naturalSum > totalWidth {
            let scale = totalWidth / naturalSum
            return natural.map { $0 * scale }
        }
        let extra = (totalWidth - naturalSum) / CGFloat(labels.count)
        return natural.map { $0 + extra }
    }

    /// Smallest window width at which every tab label still fits inside its outline.
    /// Mirrors the layout math in `drawTabBar`: tabs share `bounds.width - borders - sortWidth`
    /// equally, so the narrowest label-fit is driven by the widest label ("Channels" in the
    /// YouTube radio slot). Used to floor the Compact Mode window so labels never spill out.
    var minimumCompactContentWidth: CGFloat {
        let skin = currentSkin()
        let m = ModernSkinElements.sizeMultiplier
        let font = skin.sideWindowFont(size: 11)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        // Widest possible tab label across all sources (includes the YouTube "Channels" slot).
        var labels = ModernBrowseMode.allCases.map { $0.title }
        labels.append("Channels")
        labels.append("Folders")
        let maxLabelWidth = labels.map { $0.size(withAttributes: attrs).width }.max() ?? 0

        let sortWidth = "Sort".size(withAttributes: attrs).width + 16 * m
        // Per-tab outline keeps a 2pt inset each side; add a little breathing room.
        let perTab = maxLabelWidth + 12 * m
        let tabsWidth = perTab * CGFloat(ModernBrowseMode.allCases.count)
        return ceil(tabsWidth + sortWidth + Layout.borderWidth * 2)
    }

    private func drawTabBar(in context: CGContext, tabBarY: CGFloat, skin: ModernSkin) {
        let tabBarRect = NSRect(x: Layout.borderWidth, y: tabBarY,
                                width: bounds.width - Layout.borderWidth * 2, height: Layout.tabBarHeight)
        
        // Background
        (isMetalRenderStyle ? metalControlBandFill : skin.surfaceColor.withAlphaComponent(0.4)).setFill()
        context.fill(tabBarRect)
        
        let font = skin.sideWindowFont(size: 11)
        
        // Sort indicator width on right
        let sortText = "Sort"
        let sortAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor)
        ]
        let sortSize = sortText.size(withAttributes: sortAttrs)
        let sortWidth = sortSize.width + 16 * ModernSkinElements.sizeMultiplier
        
        let tabsWidth = tabBarRect.width - sortWidth

        let modes = ModernBrowseMode.allCases
        // Resolved (possibly dynamic) labels + content-aware widths, shared with hit-testing.
        let labels = currentTabLabels()
        let widths = tabBarWidths(totalWidth: tabsWidth, labels: labels, font: font)
        var tabX = tabBarRect.minX

        for (index, mode) in modes.enumerated() {
            let tabWidth = widths[index]
            let tabRect = NSRect(x: tabX, y: tabBarY,
                                 width: tabWidth, height: Layout.tabBarHeight)
            tabX += tabWidth

            let label = labels[index]
            var isSelected = mode == browseMode
            // Highlight the plists slot when browseMode is .folders (local source only).
            if mode == .plists, browseMode == .folders, case .local = currentSource {
                isSelected = true
            }
            let tabInset = 2 * ModernSkinElements.sizeMultiplier
            drawToggleTab(label: label, isActive: isSelected,
                          rect: tabRect.insetBy(dx: tabInset, dy: tabInset),
                          font: font, skin: skin, context: context)
        }
        
        // Sort indicator
        let sortRect = NSRect(x: tabBarRect.maxX - sortWidth, y: tabBarY,
                              width: sortWidth, height: Layout.tabBarHeight)
        drawInlineTabBarLabel(label: sortText, rect: sortRect,
                              font: font, skin: skin, context: context)
    }
    
    /// Draw a modern boxed toggle button
    private func drawToggleTab(label: String, isActive: Bool, rect: NSRect,
                               font: NSFont, skin: ModernSkin, context: CGContext) {
        let scale = ModernSkinElements.scaleFactor
        let outlineColor = isMetalRenderStyle ? metalControlStroke : skin.elementColor(for: "tab_outline", fallback: skin.accentColor)
        let activeTextColor = isMetalRenderStyle ? skin.textColor : skin.elementColor(for: "tab_text", fallback: skin.accentColor)
        let color = isActive ? activeTextColor : skin.textDimColor
        let strokeRect = rect.insetBy(dx: scale, dy: scale)
        let cornerRadius = 2 * scale
        let strokePath = CGPath(roundedRect: strokeRect,
                                cornerWidth: cornerRadius,
                                cornerHeight: cornerRadius,
                                transform: nil)
        let lineWidth = max(0.5, 0.8 * scale)

        context.saveGState()

        if isActive {
            context.setFillColor((isMetalRenderStyle ? metalControlActiveFill : outlineColor.withAlphaComponent(0.12)).cgColor)
            context.addPath(strokePath)
            context.fillPath()

            if !isMetalRenderStyle {
                context.setShadow(offset: .zero, blur: 6, color: outlineColor.withAlphaComponent(0.6).cgColor)
            }
            context.setStrokeColor(outlineColor.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(lineWidth)
            context.addPath(strokePath)
            context.strokePath()
            context.restoreGState()

            context.saveGState()
            context.setStrokeColor(outlineColor.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(lineWidth)
            context.addPath(strokePath)
            context.strokePath()
        } else {
            context.setStrokeColor((isMetalRenderStyle ? metalControlStroke : skin.textDimColor.withAlphaComponent(0.4)).cgColor)
            context.setLineWidth(lineWidth)
            context.addPath(strokePath)
            context.strokePath()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: color)
        ]
        let textSize = label.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: rect.midX - textSize.width / 2,
                                  y: rect.midY - textSize.height / 2)
        drawText(label, at: textOrigin, withAttributes: attrs, context: context)
        
        context.restoreGState()
    }

    private func drawInlineTabBarLabel(label: String, rect: NSRect,
                                       font: NSFont, skin: ModernSkin, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor)
        ]
        let textSize = label.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: rect.midX - textSize.width / 2,
                                 y: rect.midY - textSize.height / 2)
        drawText(label, at: textOrigin, withAttributes: attrs, context: context)
    }
    
    // MARK: - Server Bar Drawing
    
    private func drawServerBar(in context: CGContext, serverBarY: CGFloat, skin: ModernSkin) {
        let barRect = NSRect(x: Layout.borderWidth, y: serverBarY,
                            width: bounds.width - Layout.borderWidth * 2,
                            height: Layout.serverBarHeight)
        
        (isMetalRenderStyle ? metalControlBandFill : skin.surfaceColor.withAlphaComponent(0.4)).setFill()
        context.fill(barRect)

        let dimColor = skin.textDimColor
        let dataColor = skin.dataColor
        let accentColor = skin.accentColor

        let skinName = ModernSkinEngine.shared.currentSkinName ?? "default"
        let currentScale = ModernSkinElements.sizeMultiplier
        let isMetal = isMetalRenderStyle
        if cachedServerBarFont == nil ||
            cachedServerBarFontSkinName != skinName ||
            cachedServerBarFontScale != currentScale ||
            cachedServerBarIsMetal != isMetal {
            let font = skin.sideWindowFont(size: 11)
            cachedServerBarFont = font
            cachedServerBarFontSkinName = skinName
            cachedServerBarFontScale = currentScale
            cachedServerBarIsMetal = isMetal
            cachedPrefixAttrs = [.font: font, .foregroundColor: skin.applyTextOpacity(to: dimColor)]
            cachedDataAttrs   = [.font: font, .foregroundColor: skin.applyTextOpacity(to: dataColor)]
            cachedActiveAttrs = [.font: font, .foregroundColor: skin.applyTextOpacity(to: isMetal ? skin.textColor : accentColor)]
        }
        let font = cachedServerBarFont!
        let prefixAttrs = cachedPrefixAttrs!
        let dataAttrs   = cachedDataAttrs!
        let activeAttrs = cachedActiveAttrs!

        let m = ModernSkinElements.sizeMultiplier
        let textY = barRect.minY + (barRect.height - font.pointSize - 2 * m) / 2

        // Common prefix
        let prefix = "Source: "
        drawText(prefix, at: NSPoint(x: barRect.minX + 4 * m, y: textY), withAttributes: prefixAttrs, context: context)
        let prefixWidth = prefix.size(withAttributes: prefixAttrs).width
        let sourceNameStartX = barRect.minX + 4 * m + prefixWidth
        
        // Right side: F5 refresh label
        let refreshText = "F5"
        let refreshWidth = refreshText.size(withAttributes: prefixAttrs).width
        let refreshX = barRect.maxX - refreshWidth - 8 * m
        drawText(refreshText, at: NSPoint(x: refreshX, y: textY), withAttributes: prefixAttrs, context: context)
        
        // ART toggle button (modern boxed toggle style)
        let artText = "ART"
        let artTextWidth = artText.size(withAttributes: prefixAttrs).width
        let artBtnWidth = artTextWidth + 16 * m  // padding inside button
        let artBtnHeight: CGFloat = Layout.serverBarHeight - 6 * m
        var artX = refreshX - artBtnWidth - 12 * m
        
        if currentArtwork != nil {
            let artBtnRect = NSRect(x: artX, y: barRect.minY + 3 * m, width: artBtnWidth, height: artBtnHeight)
            drawToggleTab(label: artText, isActive: isArtOnlyMode, rect: artBtnRect,
                          font: font, skin: skin, context: context)
        } else {
            artX = refreshX
        }
        
        // VIS button (only in art-only mode, modern boxed toggle style)
        var visEndX = artX
        if isArtOnlyMode && currentArtwork != nil {
            let visText = "VIS"
            let visTextWidth = visText.size(withAttributes: prefixAttrs).width
            let visBtnWidth = visTextWidth + 16 * m
            let visX = artX - visBtnWidth - 8 * m
            let visBtnRect = NSRect(x: visX, y: barRect.minY + 3 * m, width: visBtnWidth, height: artBtnHeight)
            drawToggleTab(label: visText, isActive: isVisualizingArt, rect: visBtnRect,
                          font: font, skin: skin, context: context)
            visEndX = visX
        }
        
        // Star rating (art-only mode with a track playing)
        if isArtOnlyMode,
           let currentTrack = WindowManager.shared.audioEngine.currentTrack,
           currentTrack.plexRatingKey != nil || currentTrack.subsonicId != nil || currentTrack.jellyfinId != nil || currentTrack.embyId != nil || currentTrack.url.isFileURL {
            let starSize: CGFloat = (compactMode ? 11 : 14) * m
            let starSpacing: CGFloat = (compactMode ? 2 : 4) * m
            let starButtonGap: CGFloat = (compactMode ? 10 : 16) * m
            let totalStars = 5
            let starsWidth = CGFloat(totalStars) * starSize + CGFloat(totalStars - 1) * starSpacing
            let starsX = visEndX - starsWidth - starButtonGap
            let starY = barRect.minY + (barRect.height - starSize) / 2
            
            // Get current rating (0-10 scale -> 0-5 filled stars)
            let rating = currentTrackRating ?? 0
            let filledCount = rating / 2
            
            let filledColor = isMetalRenderStyle
                ? metalRatingColor
                : NSColor(srgbRed: 0.98, green: 0.78, blue: 0.20, alpha: 1.0)
            let emptyColor = dimColor.withAlphaComponent(0.3)
            
            for i in 0..<totalStars {
                let x = starsX + CGFloat(i) * (starSize + starSpacing)
                let starRect = NSRect(x: x, y: starY, width: starSize, height: starSize)
                let isFilled = i < filledCount
                drawPixelStar(in: starRect, color: isFilled ? filledColor : emptyColor)
            }
            
            // Store hit rect for click detection
            rateButtonRect = NSRect(x: starsX, y: barRect.minY, width: starsWidth, height: barRect.height)
        } else {
            rateButtonRect = .zero
        }
        
        // Source-specific content
        switch currentSource {
        case .local:
            let sourceText = "Local Files"
            drawText(sourceText, at: NSPoint(x: sourceNameStartX, y: textY), withAttributes: dataAttrs, context: context)
            let sourceTextWidth = sourceText.size(withAttributes: dataAttrs).width

            let addText = "+ADD"
            let addX = sourceNameStartX + sourceTextWidth + 28 * m
            drawText(addText, at: NSPoint(x: addX, y: textY), withAttributes: activeAttrs, context: context)

            // Item count (only in list mode)
            if !isArtOnlyMode {
                let totalCount: Int
                if browseMode == .artists {
                    totalCount = localArtistTotal > 0 ? localArtistTotal : displayItems.count
                } else if browseMode == .albums {
                    totalCount = localAlbumTotal > 0 ? localAlbumTotal : displayItems.count
                } else {
                    totalCount = displayItems.count
                }
                let countText = "\(totalCount) items"
                let countWidth = countText.size(withAttributes: dataAttrs).width
                let countX = visEndX - countWidth - 24 * m
                drawText(countText, at: NSPoint(x: countX, y: textY), withAttributes: dataAttrs, context: context)
            }

            // Scan animation: small spinner at center of bar while library is scanning
            if isLibraryScanning {
                let cx = barRect.midX
                let cy = barRect.midY
                let innerR: CGFloat = 3 * m
                let outerR: CGFloat = 8 * m
                let n = 8
                let step = CGFloat.pi * 2 / CGFloat(n)
                for i in 0..<n {
                    let angle = CGFloat(i) * step - CGFloat.pi / 2 + CGFloat(loadingAnimationFrame) * step
                    let spinnerColor = isMetalRenderStyle ? skin.textColor : skin.accentColor
                    spinnerColor.withAlphaComponent(CGFloat(i + 1) / CGFloat(n) * 0.9).setStroke()
                    context.setLineWidth(1.5 * m)
                    context.move(to: CGPoint(x: cx + cos(angle) * innerR, y: cy + sin(angle) * innerR))
                    context.addLine(to: CGPoint(x: cx + cos(angle) * outerR, y: cy + sin(angle) * outerR))
                    context.strokePath()
                }
                let scanText = "SCANNING"
                let scanTextX = cx + outerR + 6 * m
                drawText(scanText, at: NSPoint(x: scanTextX, y: textY), withAttributes: prefixAttrs, context: context)
            }

        case .plex(let serverId):
            let manager = PlexManager.shared
            let configuredServer = manager.servers.first(where: { $0.id == serverId })
            
            if configuredServer != nil || manager.isLinked {
                let serverName = configuredServer?.name ?? "Select Server"
                let maxServerWidth: CGFloat = 100 * m
                let textH = font.pointSize + 4 * m

                serverNameMaxWidth = maxServerWidth
                serverNameTextWidth = (serverName as NSString).size(withAttributes: dataAttrs).width

                drawScrollingText(serverName, startX: sourceNameStartX, textY: textY,
                                  availableWidth: maxServerWidth, scrollOffset: serverNameScrollOffset,
                                  textHeight: textH, attributes: dataAttrs, in: context)

                let libLabel = "Lib:"
                let libraryLabelX = sourceNameStartX + maxServerWidth + 16 * m
                drawText(libLabel, at: NSPoint(x: libraryLabelX, y: textY), withAttributes: prefixAttrs, context: context)
                
                let libLabelWidth = libLabel.size(withAttributes: prefixAttrs).width
                let libraryX = libraryLabelX + libLabelWidth + 4 * m
                let libraryText = manager.currentLibrary?.title ?? "Select"
                let maxLibraryWidth: CGFloat = 80 * m

                // Store widths for scroll logic
                libraryNameMaxWidth = maxLibraryWidth
                libraryNameTextWidth = (libraryText as NSString).size(withAttributes: dataAttrs).width

                drawScrollingText(libraryText, startX: libraryX, textY: textY,
                                  availableWidth: maxLibraryWidth, scrollOffset: libraryNameScrollOffset,
                                  textHeight: textH, attributes: dataAttrs, in: context)
                
                // Item count (only in list mode)
                if !isArtOnlyMode {
                    let itemCount: Int
                    if manager.currentLibrary?.type == "artist" {
                        itemCount = cachedArtists.count
                    } else if manager.currentLibrary?.type == "movie" {
                        itemCount = cachedMovies.count
                    } else {
                        itemCount = displayItems.count
                    }
                    let countText = "\(itemCount) ITEMS"
                    let countWidth = countText.size(withAttributes: dataAttrs).width
                    let countX = visEndX - countWidth - 24 * m
                    drawText(countText, at: NSPoint(x: countX, y: textY), withAttributes: dataAttrs, context: context)
                }
            } else {
                let linkText = "Click to link your Plex account"
                let linkWidth = linkText.size(withAttributes: prefixAttrs).width
                let linkX = barRect.midX - linkWidth / 2
                drawText(linkText, at: NSPoint(x: linkX, y: textY), withAttributes: prefixAttrs, context: context)
            }
            
        case .subsonic(let serverId):
            let configuredServer = SubsonicManager.shared.servers.first(where: { $0.id == serverId })
            if configuredServer != nil {
                let serverName = configuredServer?.name ?? "Select Server"
                let maxServerWidth: CGFloat = 100 * m
                let textH = font.pointSize + 4 * m

                serverNameMaxWidth = maxServerWidth
                serverNameTextWidth = (serverName as NSString).size(withAttributes: dataAttrs).width

                drawScrollingText(serverName, startX: sourceNameStartX, textY: textY,
                                  availableWidth: maxServerWidth, scrollOffset: serverNameScrollOffset,
                                  textHeight: textH, attributes: dataAttrs, in: context)

                let libLabel = "Lib:"
                let libraryLabelX = sourceNameStartX + maxServerWidth + 16 * m
                drawText(libLabel, at: NSPoint(x: libraryLabelX, y: textY), withAttributes: prefixAttrs, context: context)

                let libLabelWidth = libLabel.size(withAttributes: prefixAttrs).width
                let libraryX = libraryLabelX + libLabelWidth + 4 * m
                let folderText = SubsonicManager.shared.currentMusicFolder?.name ?? "All"
                let maxLibraryWidth: CGFloat = 80 * m

                libraryNameMaxWidth = maxLibraryWidth
                libraryNameTextWidth = (folderText as NSString).size(withAttributes: dataAttrs).width

                drawScrollingText(folderText, startX: libraryX, textY: textY,
                                  availableWidth: maxLibraryWidth, scrollOffset: libraryNameScrollOffset,
                                  textHeight: textH, attributes: dataAttrs, in: context)

                // Item count (only in list mode)
                if !isArtOnlyMode {
                    let countText = "\(displayItems.count) items"
                    let countWidth = countText.size(withAttributes: dataAttrs).width
                    let countX = visEndX - countWidth - 24 * m
                    drawText(countText, at: NSPoint(x: countX, y: textY), withAttributes: dataAttrs, context: context)
                }
            } else {
                let linkText = "Click to add a Subsonic server"
                let linkWidth = linkText.size(withAttributes: prefixAttrs).width
                let linkX = barRect.midX - linkWidth / 2
                drawText(linkText, at: NSPoint(x: linkX, y: textY), withAttributes: prefixAttrs, context: context)
            }
            
        case .jellyfin(let serverId):
            let configuredServer = JellyfinManager.shared.servers.first(where: { $0.id == serverId })
            if configuredServer != nil {
                let serverName = configuredServer?.name ?? "Select Server"
                let maxServerWidth: CGFloat = 100 * m
                let textH = font.pointSize + 4 * m

                serverNameMaxWidth = maxServerWidth
                serverNameTextWidth = (serverName as NSString).size(withAttributes: dataAttrs).width

                drawScrollingText(serverName, startX: sourceNameStartX, textY: textY,
                                  availableWidth: maxServerWidth, scrollOffset: serverNameScrollOffset,
                                  textHeight: textH, attributes: dataAttrs, in: context)

                let libLabel = "Lib:"
                let libraryLabelX = sourceNameStartX + maxServerWidth + 16 * m
                drawText(libLabel, at: NSPoint(x: libraryLabelX, y: textY), withAttributes: prefixAttrs, context: context)

                let libLabelWidth = libLabel.size(withAttributes: prefixAttrs).width
                let libraryX = libraryLabelX + libLabelWidth + 4 * m
                let libraryText = jellyfinCurrentLibraryName
                let maxLibraryWidth: CGFloat = 80 * m

                libraryNameMaxWidth = maxLibraryWidth
                libraryNameTextWidth = (libraryText as NSString).size(withAttributes: dataAttrs).width

                drawScrollingText(libraryText, startX: libraryX, textY: textY,
                                  availableWidth: maxLibraryWidth, scrollOffset: libraryNameScrollOffset,
                                  textHeight: textH, attributes: dataAttrs, in: context)

                // Item count (only in list mode)
                if !isArtOnlyMode {
                    let countText = "\(displayItems.count) items"
                    let countWidth = countText.size(withAttributes: dataAttrs).width
                    let countX = visEndX - countWidth - 24 * m
                    drawText(countText, at: NSPoint(x: countX, y: textY), withAttributes: dataAttrs, context: context)
                }
            } else {
                let linkText = "Click to add a Jellyfin server"
                let linkWidth = linkText.size(withAttributes: prefixAttrs).width
                let linkX = barRect.midX - linkWidth / 2
                drawText(linkText, at: NSPoint(x: linkX, y: textY), withAttributes: prefixAttrs, context: context)
            }

        case .emby(let serverId):
            let configuredServer = EmbyManager.shared.servers.first(where: { $0.id == serverId })
            if configuredServer != nil {
                let serverName = configuredServer?.name ?? "Select Server"
                let maxServerWidth: CGFloat = 100 * m
                let textH = font.pointSize + 4 * m

                serverNameMaxWidth = maxServerWidth
                serverNameTextWidth = (serverName as NSString).size(withAttributes: dataAttrs).width

                drawScrollingText(serverName, startX: sourceNameStartX, textY: textY,
                                  availableWidth: maxServerWidth, scrollOffset: serverNameScrollOffset,
                                  textHeight: textH, attributes: dataAttrs, in: context)

                let libLabel = "Lib:"
                let libraryLabelX = sourceNameStartX + maxServerWidth + 16 * m
                drawText(libLabel, at: NSPoint(x: libraryLabelX, y: textY), withAttributes: prefixAttrs, context: context)

                let libLabelWidth = libLabel.size(withAttributes: prefixAttrs).width
                let libraryX = libraryLabelX + libLabelWidth + 4 * m
                let libraryText = embyCurrentLibraryName
                let maxLibraryWidth: CGFloat = 80 * m

                libraryNameMaxWidth = maxLibraryWidth
                libraryNameTextWidth = (libraryText as NSString).size(withAttributes: dataAttrs).width

                drawScrollingText(libraryText, startX: libraryX, textY: textY,
                                  availableWidth: maxLibraryWidth, scrollOffset: libraryNameScrollOffset,
                                  textHeight: textH, attributes: dataAttrs, in: context)

                // Item count (only in list mode)
                if !isArtOnlyMode {
                    let countText = "\(displayItems.count) items"
                    let countWidth = countText.size(withAttributes: dataAttrs).width
                    let countX = visEndX - countWidth - 24 * m
                    drawText(countText, at: NSPoint(x: countX, y: textY), withAttributes: dataAttrs, context: context)
                }
            } else {
                let linkText = "Click to add an Emby server"
                let linkWidth = linkText.size(withAttributes: prefixAttrs).width
                let linkX = barRect.midX - linkWidth / 2
                drawText(linkText, at: NSPoint(x: linkX, y: textY), withAttributes: prefixAttrs, context: context)
            }

        case .radio:
            let sourceText = "Internet Radio"
            drawText(sourceText, at: NSPoint(x: sourceNameStartX, y: textY), withAttributes: dataAttrs, context: context)
            let sourceTextWidth = sourceText.size(withAttributes: dataAttrs).width

            let addText = "+ADD"
            let addX = sourceNameStartX + sourceTextWidth + 28 * m
            drawText(addText, at: NSPoint(x: addX, y: textY), withAttributes: activeAttrs, context: context)

            // Item count (only in list mode)
            if !isArtOnlyMode {
                let countText = "\(displayItems.count) stations"
                let countWidth = countText.size(withAttributes: dataAttrs).width
                let countX = visEndX - countWidth - 24 * m
                drawText(countText, at: NSPoint(x: countX, y: textY), withAttributes: dataAttrs, context: context)
            }

        case .youtube:
            let sourceText = "YouTube"
            drawText(sourceText, at: NSPoint(x: sourceNameStartX, y: textY), withAttributes: dataAttrs, context: context)
            let sourceTextWidth = sourceText.size(withAttributes: dataAttrs).width

            let addText = "+ADD"
            let addX = sourceNameStartX + sourceTextWidth + 28 * m
            drawText(addText, at: NSPoint(x: addX, y: textY), withAttributes: activeAttrs, context: context)

            // Item count (only in list mode)
            if !isArtOnlyMode {
                let countText = "\(displayItems.count) items"
                let countWidth = countText.size(withAttributes: dataAttrs).width
                let countX = visEndX - countWidth - 24 * m
                drawText(countText, at: NSPoint(x: countX, y: textY), withAttributes: dataAttrs, context: context)
            }
        }
    }
    
    /// Draw text with circular scrolling when it overflows the available width.
    /// Uses NSAttributedString drawing (system font) rather than bitmap sprites.
    private func drawScrollingText(_ text: String,
                                   startX: CGFloat, textY: CGFloat,
                                   availableWidth: CGFloat,
                                   scrollOffset: CGFloat,
                                   textHeight: CGFloat,
                                   attributes: [NSAttributedString.Key: Any],
                                   in context: CGContext) {
        let textWidth = (text as NSString).size(withAttributes: attributes).width

        // Text fits — draw once with a simple clip, no scrolling artifacts.
        guard textWidth > availableWidth else {
            context.saveGState()
            context.clip(to: NSRect(x: startX, y: textY, width: availableWidth, height: textHeight))
            drawText(text, at: NSPoint(x: startX, y: textY), withAttributes: attributes, context: context)
            context.restoreGState()
            return
        }

        let separatorWidth = textWidth * 0.3  // 30% gap before repeat
        let totalCycleWidth = textWidth + separatorWidth

        context.saveGState()
        context.clip(to: NSRect(x: startX, y: textY, width: availableWidth, height: textHeight))

        // Two passes for seamless circular wrap
        for pass in 0..<2 {
            let baseX = startX - scrollOffset + CGFloat(pass) * totalCycleWidth
            if baseX + totalCycleWidth < startX || baseX > startX + availableWidth { continue }
            drawText(text, at: NSPoint(x: baseX, y: textY), withAttributes: attributes, context: context)
        }

        context.restoreGState()
    }

    /// Draw string text without inheriting parent content alpha attenuation.
    private func drawText(_ text: String, at point: NSPoint,
                          withAttributes attributes: [NSAttributedString.Key: Any],
                          context: CGContext) {
        context.saveGState()
        context.setAlpha(1.0)
        text.draw(at: point, withAttributes: attributes)
        context.restoreGState()
    }

    /// Draw wrapped/truncated string text without inheriting parent content alpha attenuation.
    private func drawText(_ text: String, in rect: NSRect,
                          withAttributes attributes: [NSAttributedString.Key: Any],
                          context: CGContext) {
        context.saveGState()
        context.setAlpha(1.0)
        text.draw(in: rect, withAttributes: attributes)
        context.restoreGState()
    }

    /// Draw wrapped/truncated text without inheriting parent content alpha attenuation.
    private func drawText(_ text: String, in rect: NSRect,
                          options: NSString.DrawingOptions,
                          withAttributes attributes: [NSAttributedString.Key: Any],
                          context: CGContext) {
        context.saveGState()
        context.setAlpha(1.0)
        text.draw(with: rect, options: options, attributes: attributes)
        context.restoreGState()
    }

    /// Draw a low-res pixel-art star for server bar rating display
    /// Pattern is top-down but macOS Y goes up, so we draw rows from maxY downward
    private func drawPixelStar(in rect: NSRect, color: NSColor) {
        let pattern: [[Int]] = [
            [0, 0, 0, 0, 1, 0, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 0, 0, 0],
            [1, 1, 1, 1, 1, 1, 1, 1, 1],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 1, 1, 0, 1, 1, 0, 0],
            [0, 1, 1, 0, 0, 0, 1, 1, 0],
            [1, 1, 0, 0, 0, 0, 0, 1, 1],
        ]
        
        let patternSize = 9
        let pixelW = rect.width / CGFloat(patternSize)
        let pixelH = rect.height / CGFloat(patternSize)
        
        color.setFill()

        for row in 0..<patternSize {
            for col in 0..<patternSize {
                if pattern[row][col] == 1 {
                    let x = rect.minX + CGFloat(col) * pixelW
                    // Flip Y: row 0 (top of star) draws at maxY, row 8 at minY
                    let y = rect.maxY - CGFloat(row + 1) * pixelH
                    NSBezierPath.fill(NSRect(x: x, y: y, width: ceil(pixelW), height: ceil(pixelH)))
                }
            }
        }
    }
    
    // MARK: - Search Bar Drawing
    
    private func drawSearchBar(in context: CGContext, searchBarY: CGFloat, skin: ModernSkin) {
        let searchRect = NSRect(x: Layout.borderWidth + Layout.padding, y: searchBarY + 3,
                               width: bounds.width - Layout.borderWidth * 2 - Layout.padding * 2,
                               height: Layout.searchBarHeight - 6)
        
        let isFocused = window?.firstResponder === self
        let bgColor: NSColor
        if isMetalRenderStyle {
            bgColor = isFocused ? metalControlActiveFill : metalControlFill
        } else {
            bgColor = isFocused
                ? skin.accentColor.withAlphaComponent(0.15)
                : skin.surfaceColor.withAlphaComponent(0.3)
        }
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: searchRect, xRadius: 3, yRadius: 3)
        path.fill()
        
        if isFocused {
            (isMetalRenderStyle ? metalControlStroke : skin.accentColor.withAlphaComponent(0.5)).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        
        let font = skin.smallFont?.withSize(9) ?? NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let displayText = searchQuery.isEmpty ? "Type and press ↵ to search..." : searchQuery
        let textColor = searchQuery.isEmpty ? skin.textDimColor : skin.textColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: textColor)
        ]
        let textSize = displayText.size(withAttributes: attrs)
        let textY = searchRect.minY + (searchRect.height - textSize.height) / 2
        drawText(displayText, at: NSPoint(x: searchRect.minX + 6, y: textY), withAttributes: attrs, context: context)
        
        // Draw cursor
        if isFocused && !searchQuery.isEmpty {
            let cursorX = searchRect.minX + 6 + searchQuery.size(withAttributes: attrs).width + 1
            skin.textColor.setFill()
            context.fill(CGRect(x: cursorX, y: textY, width: 1, height: textSize.height))
        }
    }
    
    // MARK: - Offline Volume Banner

    private func drawOfflineBanner(in context: CGContext, rect: NSRect, skin: ModernSkin) {
        // Background — amber tint
        NSColor.systemOrange.withAlphaComponent(0.18).setFill()
        context.fill(rect)

        let offlineCount = offlineWatchFolders.reduce(0) { $0 + $1.totalCount }
        let names = offlineWatchFolders.map { $0.url.lastPathComponent }.joined(separator: ", ")
        let label = "⚠  \"\(names)\" offline — \(offlineCount) track\(offlineCount == 1 ? "" : "s") unavailable"

        let font = skin.scaledSystemFont(size: 7.5)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: skin.textColor)
        ]
        let textSize = label.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: rect.minX + 6, y: rect.midY - textSize.height / 2)
        drawText(label, at: textOrigin, withAttributes: attrs, context: context)
    }

    // MARK: - List Area Drawing

    private func drawListArea(in context: CGContext, listAreaY: CGFloat, listAreaHeight: CGFloat, skin: ModernSkin, artwork: NSImage?) {
        let alphabetWidth = Layout.alphabetWidth
        let fullListRect = NSRect(x: Layout.borderWidth, y: listAreaY,
                                  width: bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - alphabetWidth,
                                  height: listAreaHeight)
        
        if displayItems.isEmpty {
            drawEmptyState(in: context, listRect: fullListRect, skin: skin)
            return
        }
        
        let headerColumns = headerColumnsForCurrentContent()
        
        // Draw column headers
        var contentListY = listAreaY
        if let columns = headerColumns {
            let headerY = listAreaY + listAreaHeight - columnHeaderHeight
            let headerRect = NSRect(x: fullListRect.minX, y: headerY,
                                    width: fullListRect.width, height: columnHeaderHeight)
            drawColumnHeaders(in: context, rect: headerRect, columns: columns, skin: skin)
            // Fill the header-row gap above the alphabet index (and scrollbar) so it
            // matches the column-header band instead of showing the panel background.
            let gapRect = NSRect(x: headerRect.maxX, y: headerY,
                                 width: bounds.width - Layout.borderWidth - headerRect.maxX,
                                 height: columnHeaderHeight)
            (isMetalRenderStyle ? metalControlBandFill : skin.surfaceColor.withAlphaComponent(0.4)).setFill()
            context.fill(gapRect)
            contentListY = listAreaY
        }
        
        // Content area
        let contentHeight = listAreaHeight - (headerColumns != nil ? columnHeaderHeight : 0)
        let contentTopY = headerColumns != nil ? (listAreaY + listAreaHeight - columnHeaderHeight) : (listAreaY + listAreaHeight)
        let listRect = NSRect(x: fullListRect.minX, y: listAreaY,
                              width: fullListRect.width, height: contentHeight)
        
        // Clip to content area
        context.saveGState()
        context.clip(to: listRect)
        
        drawArtworkBackground(in: context, listRect: listRect, artwork: artwork)
        
        // Draw items (bottom-left origin: item 0 at top of list, so we draw from top down)
        let visibleStart = max(0, Int(scrollOffset / itemHeight))
        let visibleEnd = min(displayItems.count, visibleStart + Int(contentHeight / itemHeight) + 2)
        
        guard visibleStart < visibleEnd else {
            context.restoreGState()
            let alphabetHeight = listAreaHeight - (headerColumns != nil ? columnHeaderHeight : 0)
            let alphabetRect = NSRect(x: bounds.width - Layout.borderWidth - Layout.scrollbarWidth - alphabetWidth,
                                     y: listAreaY, width: alphabetWidth, height: alphabetHeight)
            drawAlphabetIndex(in: context, rect: alphabetRect, skin: skin)
            return
        }
        
        let font = skin.scaledSystemFont(size: 8)
        let smallFont = skin.scaledSystemFont(size: 7.2)
        
        for index in visibleStart..<visibleEnd {
            // In bottom-left coords: item 0 is at top, so y decreases as index increases
            let itemTopY = listRect.maxY - CGFloat(index) * itemHeight + scrollOffset
            let y = itemTopY - itemHeight
            
            if y + itemHeight < listRect.minY || y > listRect.maxY { continue }
            
            let itemRect = NSRect(x: listRect.minX, y: y, width: listRect.width, height: itemHeight)
            let item = displayItems[index]
            let isSelected = selectedIndices.contains(index)

            // Dim tracks/episodes whose file lives on an offline volume
            let isOffline: Bool
            switch item.type {
            case .localTrack(let track):
                isOffline = offlineVolumePrefixes.contains { track.url.path.hasPrefix($0) }
            case .localEpisode(let ep):
                isOffline = offlineVolumePrefixes.contains { ep.url.path.hasPrefix($0) }
            default:
                isOffline = false
            }
            if isOffline { context.saveGState(); context.setAlpha(0.35) }

            // Selection background - subtle to keep accent text readable
            if isSelected {
                (isMetalRenderStyle ? metalControlActiveFill : skin.primaryColor.withAlphaComponent(0.06)).setFill()
                context.fill(itemRect)
            }

            // Check for column rendering
            if let itemColumns = columnsForItem(item) {
                let indent = CGFloat(item.indentLevel) * 16
                drawColumnRow(item: item, columns: itemColumns, in: context, rect: itemRect,
                             isSelected: isSelected, skin: skin, indent: indent)
            } else {
                // Simple list rendering
                let indent = CGFloat(item.indentLevel) * 16
                let textX = itemRect.minX + indent + 4

                // Expand/collapse indicator — or an inline spinner while a YouTube channel's uploads load.
                let isLoadingChannel: Bool = {
                    if case .youtubeChannel(let channel) = item.type { return loadingChannelIds.contains(channel.id) }
                    return false
                }()
                var titleSpinnerInset: CGFloat = 0
                if isLoadingChannel {
                    let spinnerRadius = min(itemHeight * 0.3, 6)
                    drawRowSpinner(in: context, center: CGPoint(x: textX + spinnerRadius, y: itemRect.midY),
                                   radius: spinnerRadius, skin: skin)
                    titleSpinnerInset = spinnerRadius * 2 + 4
                } else if item.hasChildren {
                    let expanded = isExpanded(item)
                    let indicator = expanded ? "▼" : "▶"
                    let indicatorAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor),
                        .font: skin.scaledSystemFont(size: 6.4)
                    ]
                    drawText(indicator, at: NSPoint(x: textX - 12, y: itemRect.midY - 5), withAttributes: indicatorAttrs, context: context)
                }

                // Main text
                let textColor = isSelected ? (isMetalRenderStyle ? skin.textColor : skin.accentColor) : skin.textColor
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: skin.applyTextOpacity(to: textColor),
                    .font: font
                ]
                let textRect = NSRect(x: textX + titleSpinnerInset, y: itemRect.minY + 2,
                                     width: itemRect.width - indent - 60 - titleSpinnerInset, height: itemHeight - 4)
                drawText(item.title, in: textRect, withAttributes: attrs, context: context)

                // Secondary info
                if let info = item.info {
                    let infoColor = isSelected ? (isMetalRenderStyle ? skin.textColor : skin.accentColor) : skin.textDimColor
                    let infoAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: skin.applyTextOpacity(to: infoColor),
                        .font: smallFont
                    ]
                    let infoSize = info.size(withAttributes: infoAttrs)
                    let infoX = browseMode == .radio
                        ? (itemRect.midX - infoSize.width / 2)
                        : (itemRect.maxX - infoSize.width - 4)
                    drawText(info, at: NSPoint(x: infoX, y: itemRect.midY - infoSize.height / 2), withAttributes: infoAttrs, context: context)
                }
            }

            if isOffline { context.restoreGState() }
        }
        
        context.restoreGState()
        
        // Draw alphabet index (exclude column header zone so # appears below column headers)
        let alphabetHeight = listAreaHeight - (headerColumns != nil ? columnHeaderHeight : 0)
        let alphabetRect = NSRect(x: bounds.width - Layout.borderWidth - Layout.scrollbarWidth - alphabetWidth,
                                 y: listAreaY, width: alphabetWidth, height: alphabetHeight)
        drawAlphabetIndex(in: context, rect: alphabetRect, skin: skin)
    }

    private func drawArtworkBackground(in context: CGContext, listRect: NSRect, artwork: NSImage?) {
        guard WindowManager.shared.showBrowserArtworkBackground,
              let artworkImage = artwork,
              let cgImage = artworkImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        context.saveGState()
        context.clip(to: listRect)
        let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
        let artworkRect = calculateCenterFillRect(imageSize: imageSize, in: listRect)
        context.setAlpha(0.12)
        context.draw(cgImage, in: artworkRect)
        context.restoreGState()
    }
    
    // MARK: - Column Headers
    
    private func drawColumnHeaders(in context: CGContext, rect: NSRect, columns: [ModernBrowserColumn], skin: ModernSkin) {
        context.saveGState()
        context.clip(to: rect)
        
        (isMetalRenderStyle ? metalControlBandFill : skin.surfaceColor.withAlphaComponent(0.4)).setFill()
        context.fill(rect)

        let headerFont = skin.scaledSystemFont(size: 7.2, weight: .medium)
        let headerColor = skin.textDimColor.withAlphaComponent(0.7)
        let sortedHeaderColor = skin.textColor.withAlphaComponent(0.9)
        let separatorColor = skin.textDimColor.withAlphaComponent(0.2)
        
        var x = rect.minX + 4 - horizontalScrollOffset
        let group = currentColumnGroup()
        for (index, column) in columns.enumerated() {
            let width = widthForColumn(column, availableWidth: rect.width, columns: columns, group: group)
            let isSortColumn = activeColumnSortId == column.id
            let isCenteredRadioColumn = (browseMode == .radio && column.id == "genre") ||
                (hasInternetRadioColumns && column.id == "rating")
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: skin.applyTextOpacity(to: isSortColumn ? sortedHeaderColor : headerColor)
            ]
            
            let textSize = column.title.size(withAttributes: attrs)
            let textY = rect.minY + (columnHeaderHeight - textSize.height) / 2
            let textX = isCenteredRadioColumn ? (x + (width - textSize.width) / 2) : (x + 4)
            drawText(column.title, at: NSPoint(x: textX, y: textY), withAttributes: attrs, context: context)
            
            if isSortColumn {
                let indicator = activeColumnSortAscending ? "▲" : "▼"
                let indicatorAttrs: [NSAttributedString.Key: Any] = [
                    .font: skin.scaledSystemFont(size: 5.6),
                    .foregroundColor: skin.applyTextOpacity(to: sortedHeaderColor)
                ]
                drawText(indicator, at: NSPoint(x: textX + textSize.width + 3, y: textY + 1), withAttributes: indicatorAttrs, context: context)
            }
            
            if index < columns.count - 1 {
                context.setStrokeColor(separatorColor.cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: x + width - 1, y: rect.minY + 3))
                context.addLine(to: CGPoint(x: x + width - 1, y: rect.maxY - 3))
                context.strokePath()
            }
            
            x += width
        }
        
        // Bottom separator
        context.setStrokeColor(skin.textDimColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        context.strokePath()
        
        context.restoreGState()
    }
    
    // MARK: - Column Row Drawing
    
    private func drawColumnRow(item: ModernDisplayItem, columns: [ModernBrowserColumn], in context: CGContext,
                               rect: NSRect, isSelected: Bool, skin: ModernSkin, indent: CGFloat = 0) {
        let totalWidth = rect.width - indent
        let textColor = isSelected ? (isMetalRenderStyle ? skin.textColor : skin.accentColor) : skin.textColor
        let dimColor = isSelected ? (isMetalRenderStyle ? skin.textColor : skin.accentColor) : skin.textDimColor
        let font = skin.scaledSystemFont(size: 8)
        let smallFont = skin.scaledSystemFont(size: 7.2)
        
        var x = rect.minX + indent + 4 - horizontalScrollOffset
        let group = columnGroup(for: item)
        for column in columns {
            let width = widthForColumn(column, availableWidth: totalWidth, columns: columns, group: group)
            let value = item.columnValue(for: column)
            let isCenteredRadioColumn = (browseMode == .radio && column.id == "genre") ||
                (isInternetRadioItem(item) && column.id == "rating")
            
            let color = column.id == "title" ? textColor : dimColor
            let useFont = column.id == "title" ? font : smallFont

            let attrs: [NSAttributedString.Key: Any] = [
                .font: useFont,
                .foregroundColor: skin.applyTextOpacity(to: color)
            ]
            // Per-row download spinner on the title column of a downloading YouTube video.
            var titleSpinnerInset: CGFloat = 0
            if column.id == "title", case .youtubeVideo(let video) = item.type,
               downloadingVideoIds.contains(video.videoId) {
                let spinnerRadius = min(rect.height * 0.3, 6)
                let cx = x + 4 + spinnerRadius
                drawRowSpinner(in: context, center: CGPoint(x: cx, y: rect.midY), radius: spinnerRadius, skin: skin)
                titleSpinnerInset = spinnerRadius * 2 + 4
            }

            let textSize = value.size(withAttributes: attrs)
            let textY = rect.minY + (rect.height - textSize.height) / 2
            let textX = isCenteredRadioColumn ? (x + (width - textSize.width) / 2) : (x + 4 + titleSpinnerInset)
            let maxTextWidth = width - 8 - titleSpinnerInset

            let drawRect = NSRect(x: textX, y: textY, width: maxTextWidth, height: textSize.height)
            if column.id == "rating" && !isSelected && value.contains("★") {
                let goldColor = isMetalRenderStyle
                    ? metalRatingColor
                    : NSColor(srgbRed: 0.98, green: 0.78, blue: 0.20, alpha: 1.0)
                let emptyColor = skin.applyTextOpacity(to: dimColor).withAlphaComponent(0.4)
                let astr = NSMutableAttributedString(string: value, attributes: attrs)
                for (i, ch) in value.enumerated() {
                    let range = NSRange(location: i, length: 1)
                    astr.addAttribute(.foregroundColor, value: ch == "★" ? goldColor : emptyColor, range: range)
                }
                context.saveGState()
                context.setAlpha(1.0)
                astr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                context.restoreGState()
            } else {
                drawText(
                    value,
                    in: drawRect,
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    withAttributes: attrs,
                    context: context
                )
            }
            
            x += width
        }
    }
    
    // MARK: - State Drawing Methods
    
    private func drawNotLinkedState(in context: CGContext, listRect: NSRect, skin: ModernSkin) {
        let message = "Link your Plex account to browse your music library"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor),
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let size = message.size(withAttributes: attrs)
        drawText(message, at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2), withAttributes: attrs, context: context)
        
        let hint = "Click the server bar above to link"
        let hintColor = isMetalRenderStyle ? metalRatingColor : skin.warningColor
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.applyTextOpacity(to: hintColor),
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        drawText(hint, at: NSPoint(x: listRect.midX - hintSize.width / 2, y: listRect.midY - size.height / 2 - 20), withAttributes: hintAttrs, context: context)
    }
    
    private func drawLoadingState(in context: CGContext, listRect: NSRect, skin: ModernSkin) {
        let centerY = listRect.midY
        let centerX = listRect.midX
        
        let innerRadius: CGFloat = 5
        let outerRadius: CGFloat = 12
        let numSegments = 8
        let segmentAngle = CGFloat.pi * 2 / CGFloat(numSegments)
        
        for i in 0..<numSegments {
            let angle = CGFloat(i) * segmentAngle - CGFloat.pi / 2 + CGFloat(loadingAnimationFrame) * segmentAngle
            let alpha = CGFloat(i + 1) / CGFloat(numSegments)
            
            skin.textColor.withAlphaComponent(alpha).setStroke()
            context.setLineWidth(2.5)
            
            let startX = centerX + cos(angle) * innerRadius
            let startY = centerY + sin(angle) * innerRadius
            let endX = centerX + cos(angle) * outerRadius
            let endY = centerY + sin(angle) * outerRadius
            
            context.move(to: CGPoint(x: startX, y: startY))
            context.addLine(to: CGPoint(x: endX, y: endY))
            context.strokePath()
        }
        
        startLoadingAnimation()
    }

    /// Small inline spinner used on a downloading YouTube video row.
    private func drawRowSpinner(in context: CGContext, center: CGPoint, radius: CGFloat, skin: ModernSkin) {
        let innerRadius = radius * 0.45
        let outerRadius = radius
        let numSegments = 8
        let segmentAngle = CGFloat.pi * 2 / CGFloat(numSegments)
        context.saveGState()
        for i in 0..<numSegments {
            let angle = CGFloat(i) * segmentAngle - CGFloat.pi / 2 + CGFloat(loadingAnimationFrame) * segmentAngle
            let alpha = CGFloat(i + 1) / CGFloat(numSegments)
            skin.applyTextOpacity(to: skin.textColor).withAlphaComponent(alpha).setStroke()
            context.setLineWidth(1.5)
            context.move(to: CGPoint(x: center.x + cos(angle) * innerRadius, y: center.y + sin(angle) * innerRadius))
            context.addLine(to: CGPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawErrorState(in context: CGContext, message: String, listRect: NSRect, skin: ModernSkin) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor),
            .font: NSFont.systemFont(ofSize: 11)
        ]
        let size = message.size(withAttributes: attrs)
        drawText(message, at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2), withAttributes: attrs, context: context)
    }
    
    private func drawEmptyState(in context: CGContext, listRect: NSRect, skin: ModernSkin) {
        let library = PlexManager.shared.currentLibrary
        let message: String
        switch browseMode {
        case .artists, .albums:
            if currentSource.isPlex && library?.isMusicLibrary == true {
                message = "No \(browseMode.title.lowercased()) found"
            } else if currentSource.isSubsonic || currentSource.isJellyfin || currentSource.isEmby || (currentSource.isPlex && library?.isMusicLibrary != true) {
                message = "No \(browseMode.title.lowercased()) found"
            } else {
                message = "No \(browseMode.title.lowercased()) found"
            }
        case .movies: message = "No movies found"
        case .shows: message = "No TV shows found"
        case .folders: message = "No folders found"
        case .plists: message = "No playlists found"
        case .search: message = searchQuery.isEmpty ? "Type and press ↵ to search" : "No results found"
        case .radio: message = "No radio stations found"
        case .history: message = "No play history recorded yet"
        }
        
        let font = skin.primaryFont?.withSize(10) ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor)
        ]
        let textSize = message.size(withAttributes: attrs)
        let textX = listRect.midX - textSize.width / 2
        let textY = listRect.midY - textSize.height / 2
        drawText(message, at: NSPoint(x: textX, y: textY), withAttributes: attrs, context: context)
    }
    
    // MARK: - Art Only Area
    
    private func drawArtOnlyArea(in context: CGContext, contentRect: NSRect, skin: ModernSkin, artwork: NSImage?) {
        if isVisualizingArt {
            (isMetalRenderStyle ? NSColor(calibratedRed: 0.34, green: 0.38, blue: 0.40, alpha: 1.0) : NSColor.black).setFill()
        } else {
            (isMetalRenderStyle ? metalControlFill : skin.surfaceColor).setFill()
        }
        context.fill(contentRect)
        
        if let artworkImage = artwork,
           let cgImage = artworkImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.saveGState()
            context.clip(to: contentRect)
            
            let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
            let artworkRect = calculateCenterFillRect(imageSize: imageSize, in: contentRect)
            
            if isVisualizingArt {
                drawVisualizationEffect(context: context, cgImage: cgImage, artworkRect: artworkRect, contentRect: contentRect)
            } else {
                context.draw(cgImage, in: artworkRect)
            }
            
            context.restoreGState()
        } else {
            let message = "No album art"
            let font = skin.primaryFont?.withSize(14) ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor)
            ]
            let textSize = message.size(withAttributes: attrs)
            drawText(message, at: NSPoint(x: contentRect.midX - textSize.width / 2,
                                      y: contentRect.midY - textSize.height / 2), withAttributes: attrs, context: context)
        }
    }
    
    // MARK: - Alphabet Index
    
    private func drawAlphabetIndex(in context: CGContext, rect: NSRect, skin: ModernSkin) {
        // Metal: let the brushed-metal panel show through so the index reads as part of
        // the single continuous surface rather than a darker inset strip.
        (isMetalRenderStyle ? NSColor.clear : skin.surfaceColor.withAlphaComponent(0.3)).setFill()
        context.fill(rect)
        
        let letterCount = CGFloat(alphabetLetters.count)
        let letterHeight = rect.height / letterCount
        let fontSize = min(9 * ModernSkinElements.sizeMultiplier, letterHeight * 0.8)
        
        var availableLetters = Set<String>()
        if case .local = currentSource, browseMode == .artists {
            availableLetters = Set(localArtistLetterOffsets.keys)
        } else if case .local = currentSource, browseMode == .albums {
            availableLetters = Set(localAlbumLetterOffsets.keys)
        } else {
            for item in displayItems {
                availableLetters.insert(effectiveSortLetter(for: item))
            }
        }

        for (index, letter) in alphabetLetters.enumerated() {
            // Bottom-left origin: # at top, Z at bottom
            let y = rect.maxY - CGFloat(index + 1) * letterHeight
            let letterRect = NSRect(x: rect.minX, y: y, width: rect.width, height: letterHeight)
            
            let hasItems = availableLetters.contains(letter)
            let color = hasItems ? (isMetalRenderStyle ? skin.textColor : skin.accentColor) : skin.textDimColor.withAlphaComponent(0.3)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: skin.applyTextOpacity(to: color),
                .font: NSFont.boldSystemFont(ofSize: fontSize)
            ]
            let letterSize = letter.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: letterRect.midX - letterSize.width / 2,
                y: letterRect.midY - letterSize.height / 2
            )
            drawText(letter, at: drawPoint, withAttributes: attrs, context: context)
        }
    }
    
    private func drawStatusBarText(in context: CGContext, skin: ModernSkin) {
        // Status info shown in server bar; this is kept for future use
    }
    
    // MARK: - Visualization Effect Drawing
    
    private func drawVisualizationEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect) {
        let spectrumData = WindowManager.shared.audioEngine.spectrumData
        let bass = CGFloat(spectrumData.prefix(10).reduce(0, +) / 10.0)
        let mid = CGFloat(spectrumData.dropFirst(10).prefix(30).reduce(0, +) / 30.0)
        let treble = CGFloat(spectrumData.dropFirst(40).prefix(35).reduce(0, +) / 35.0)
        let level = (bass + mid + treble) / 3.0
        let t = CGFloat(visualizerTime)
        let intensity = visEffectIntensity
        
        var ciImage = CIImage(cgImage: cgImage)
        let imageSize = ciImage.extent.size
        let center = CIVector(x: imageSize.width / 2, y: imageSize.height / 2)
        
        switch currentVisEffect {
        case .psychedelic:
            let twirl = CIFilter(name: "CITwirlDistortion")!
            twirl.setValue(ciImage, forKey: kCIInputImageKey)
            twirl.setValue(center, forKey: kCIInputCenterKey)
            twirl.setValue(min(imageSize.width, imageSize.height) * 0.4, forKey: kCIInputRadiusKey)
            twirl.setValue(bass * 3 * intensity * sin(t * 2), forKey: kCIInputAngleKey)
            ciImage = twirl.outputImage ?? ciImage
            let hue = CIFilter(name: "CIHueAdjust")!
            hue.setValue(ciImage, forKey: kCIInputImageKey)
            hue.setValue(t * 0.5 + bass, forKey: kCIInputAngleKey)
            ciImage = hue.outputImage ?? ciImage
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(10 * level * intensity, forKey: kCIInputRadiusKey)
            bloom.setValue(1.0 + bass * intensity, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
        case .kaleidoscope:
            let kaleido = CIFilter(name: "CIKaleidoscope")!
            kaleido.setValue(ciImage, forKey: kCIInputImageKey)
            kaleido.setValue(center, forKey: kCIInputCenterKey)
            kaleido.setValue(Int(6 + bass * 6 * intensity), forKey: "inputCount")
            kaleido.setValue(t * 0.3 * intensity, forKey: kCIInputAngleKey)
            ciImage = kaleido.outputImage ?? ciImage
        case .vortex:
            let vortex = CIFilter(name: "CIVortexDistortion")!
            vortex.setValue(ciImage, forKey: kCIInputImageKey)
            vortex.setValue(center, forKey: kCIInputCenterKey)
            vortex.setValue(min(imageSize.width, imageSize.height) * 0.5, forKey: kCIInputRadiusKey)
            vortex.setValue(bass * 10 * intensity * sin(t), forKey: kCIInputAngleKey)
            ciImage = vortex.outputImage ?? ciImage
        case .spin:
            let zoomBlur = CIFilter(name: "CIZoomBlur")!
            zoomBlur.setValue(ciImage, forKey: kCIInputImageKey)
            zoomBlur.setValue(center, forKey: kCIInputCenterKey)
            zoomBlur.setValue(bass * 20 * intensity, forKey: kCIInputAmountKey)
            ciImage = zoomBlur.outputImage ?? ciImage
        case .fractal:
            let scale = 1.0 + sin(t * intensity) * 0.3 * bass
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
            affine = affine.scaledBy(x: scale, y: scale)
            affine = affine.rotated(by: t * 0.2 * intensity)
            affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
        case .tunnel:
            let hole = CIFilter(name: "CIHoleDistortion")!
            hole.setValue(ciImage, forKey: kCIInputImageKey)
            hole.setValue(center, forKey: kCIInputCenterKey)
            hole.setValue(50 + bass * 100 * intensity * abs(sin(t)), forKey: kCIInputRadiusKey)
            ciImage = hole.outputImage ?? ciImage
        case .melt:
            let glass = CIFilter(name: "CIGlassDistortion")!
            glass.setValue(ciImage, forKey: kCIInputImageKey)
            let noiseFilter = CIFilter(name: "CIRandomGenerator")!
            if let noise = noiseFilter.outputImage?.cropped(to: ciImage.extent) {
                glass.setValue(noise, forKey: "inputTexture")
                glass.setValue(center, forKey: kCIInputCenterKey)
                glass.setValue(50 * bass * intensity, forKey: kCIInputScaleKey)
                ciImage = glass.outputImage ?? ciImage
            }
        case .wave:
            let bump = CIFilter(name: "CIBumpDistortion")!
            let waveX = imageSize.width * (0.5 + 0.4 * sin(t * 2))
            let waveY = imageSize.height * (0.5 + 0.3 * cos(t * 1.5))
            bump.setValue(ciImage, forKey: kCIInputImageKey)
            bump.setValue(CIVector(x: waveX, y: waveY), forKey: kCIInputCenterKey)
            bump.setValue(min(imageSize.width, imageSize.height) * 0.4, forKey: kCIInputRadiusKey)
            bump.setValue(bass * 2 * intensity * sin(t * 3), forKey: kCIInputScaleKey)
            ciImage = bump.outputImage ?? ciImage
        case .glitch:
            if bass > 0.3 {
                let colorMatrix = CIFilter(name: "CIColorMatrix")!
                colorMatrix.setValue(ciImage, forKey: kCIInputImageKey)
                colorMatrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
                colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
                ciImage = colorMatrix.outputImage ?? ciImage
            }
            let posterize = CIFilter(name: "CIColorPosterize")!
            posterize.setValue(ciImage, forKey: kCIInputImageKey)
            posterize.setValue(4 + (1 - bass) * 10, forKey: "inputLevels")
            ciImage = posterize.outputImage ?? ciImage
        case .rgbSplit:
            let offset = (10 + bass * 40) * intensity
            let rFilter = CIFilter(name: "CIColorMatrix")!
            rFilter.setValue(ciImage, forKey: kCIInputImageKey)
            rFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            rFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            rFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            let rImage = rFilter.outputImage ?? ciImage
            let rTransform = CIFilter(name: "CIAffineTransform")!
            rTransform.setValue(rImage, forKey: kCIInputImageKey)
            rTransform.setValue(CGAffineTransform(translationX: -offset, y: 0), forKey: kCIInputTransformKey)
            let rOffset = rTransform.outputImage ?? rImage
            let bFilter = CIFilter(name: "CIColorMatrix")!
            bFilter.setValue(ciImage, forKey: kCIInputImageKey)
            bFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            bFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            bFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            let bImage = bFilter.outputImage ?? ciImage
            let bTransform = CIFilter(name: "CIAffineTransform")!
            bTransform.setValue(bImage, forKey: kCIInputImageKey)
            bTransform.setValue(CGAffineTransform(translationX: offset, y: 0), forKey: kCIInputTransformKey)
            let bOffset = bTransform.outputImage ?? bImage
            let gFilter = CIFilter(name: "CIColorMatrix")!
            gFilter.setValue(ciImage, forKey: kCIInputImageKey)
            gFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            gFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            gFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            let gImage = gFilter.outputImage ?? ciImage
            let addR = CIFilter(name: "CIAdditionCompositing")!
            addR.setValue(rOffset, forKey: kCIInputImageKey)
            addR.setValue(gImage, forKey: kCIInputBackgroundImageKey)
            let rg = addR.outputImage ?? ciImage
            let addB = CIFilter(name: "CIAdditionCompositing")!
            addB.setValue(bOffset, forKey: kCIInputImageKey)
            addB.setValue(rg, forKey: kCIInputBackgroundImageKey)
            ciImage = addB.outputImage ?? ciImage
        case .twist:
            let twirl = CIFilter(name: "CITwirlDistortion")!
            twirl.setValue(ciImage, forKey: kCIInputImageKey)
            twirl.setValue(center, forKey: kCIInputCenterKey)
            twirl.setValue(min(imageSize.width, imageSize.height) * 0.6, forKey: kCIInputRadiusKey)
            twirl.setValue(t * 2 * intensity + bass * 5, forKey: kCIInputAngleKey)
            ciImage = twirl.outputImage ?? ciImage
        case .fisheye:
            let bump = CIFilter(name: "CIBumpDistortion")!
            bump.setValue(ciImage, forKey: kCIInputImageKey)
            bump.setValue(center, forKey: kCIInputCenterKey)
            bump.setValue(min(imageSize.width, imageSize.height) * 0.8, forKey: kCIInputRadiusKey)
            bump.setValue(-1.5 * intensity * (1 + bass * 0.5), forKey: kCIInputScaleKey)
            ciImage = bump.outputImage ?? ciImage
        case .shatter:
            let triangle = CIFilter(name: "CITriangleTile")!
            triangle.setValue(ciImage, forKey: kCIInputImageKey)
            triangle.setValue(center, forKey: kCIInputCenterKey)
            triangle.setValue(t * 0.5 * intensity, forKey: kCIInputAngleKey)
            triangle.setValue(50 + bass * 100 * intensity, forKey: kCIInputWidthKey)
            ciImage = triangle.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
        case .stretch:
            let pinch = CIFilter(name: "CIPinchDistortion")!
            pinch.setValue(ciImage, forKey: kCIInputImageKey)
            pinch.setValue(center, forKey: kCIInputCenterKey)
            pinch.setValue(min(imageSize.width, imageSize.height) * 0.7, forKey: kCIInputRadiusKey)
            pinch.setValue(bass * intensity * sin(t * 2), forKey: kCIInputScaleKey)
            ciImage = pinch.outputImage ?? ciImage
        case .zoom:
            let zoomBlur = CIFilter(name: "CIZoomBlur")!
            zoomBlur.setValue(ciImage, forKey: kCIInputImageKey)
            zoomBlur.setValue(center, forKey: kCIInputCenterKey)
            zoomBlur.setValue(bass * 50 * intensity, forKey: kCIInputAmountKey)
            ciImage = zoomBlur.outputImage ?? ciImage
        case .shake:
            let shakeOffset = bass * 30 * intensity
            let shakeX = sin(t * 30) * shakeOffset
            let shakeY = cos(t * 25) * shakeOffset * 0.7
            let transform = CIFilter(name: "CIAffineTransform")!
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(CGAffineTransform(translationX: shakeX, y: shakeY), forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
        case .bounce:
            let bounceY = abs(sin(t * 3 * intensity)) * 50 * bass
            let transform = CIFilter(name: "CIAffineTransform")!
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(CGAffineTransform(translationX: 0, y: bounceY), forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
        case .feedback:
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(15 * level * intensity, forKey: kCIInputRadiusKey)
            bloom.setValue(0.5 + bass, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
        case .strobe:
            let strobeOn = Int(t * 10 * intensity) % 2 == 0 || bass > 0.6
            let exposure = CIFilter(name: "CIExposureAdjust")!
            exposure.setValue(ciImage, forKey: kCIInputImageKey)
            exposure.setValue(strobeOn ? bass * 2 * intensity : -1.0, forKey: kCIInputEVKey)
            ciImage = exposure.outputImage ?? ciImage
        case .jitter:
            let jitterX = CGFloat.random(in: -1...1) * bass * 20 * intensity
            let jitterY = CGFloat.random(in: -1...1) * bass * 20 * intensity
            let transform = CIFilter(name: "CIAffineTransform")!
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(CGAffineTransform(translationX: jitterX, y: jitterY), forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
        case .mirror:
            let fourFold = CIFilter(name: "CIFourfoldReflectedTile")!
            fourFold.setValue(ciImage, forKey: kCIInputImageKey)
            fourFold.setValue(center, forKey: kCIInputCenterKey)
            fourFold.setValue(t * 0.2 * intensity, forKey: kCIInputAngleKey)
            fourFold.setValue(imageSize.width * (0.3 + bass * 0.2 * intensity), forKey: kCIInputWidthKey)
            ciImage = fourFold.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
        case .tile:
            let op = CIFilter(name: "CIOpTile")!
            op.setValue(ciImage, forKey: kCIInputImageKey)
            op.setValue(center, forKey: kCIInputCenterKey)
            op.setValue(t * intensity, forKey: kCIInputAngleKey)
            op.setValue(1.5 + bass * intensity, forKey: kCIInputScaleKey)
            op.setValue(imageSize.width * 0.3, forKey: kCIInputWidthKey)
            ciImage = op.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
        case .prism:
            let triangle = CIFilter(name: "CITriangleKaleidoscope")!
            triangle.setValue(ciImage, forKey: kCIInputImageKey)
            triangle.setValue(CIVector(x: imageSize.width * 0.5, y: imageSize.height * 0.5), forKey: "inputPoint")
            triangle.setValue(imageSize.width * (0.3 + bass * 0.2), forKey: "inputSize")
            triangle.setValue(t * 0.5 * intensity, forKey: "inputRotation")
            triangle.setValue(0.1, forKey: "inputDecay")
            ciImage = triangle.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
        case .doubleVision:
            let dvOffset = 20 + bass * 50 * intensity
            let t1 = CIFilter(name: "CIAffineTransform")!
            t1.setValue(ciImage, forKey: kCIInputImageKey)
            t1.setValue(CGAffineTransform(translationX: -dvOffset, y: 0), forKey: kCIInputTransformKey)
            let img1 = t1.outputImage ?? ciImage
            let t2 = CIFilter(name: "CIAffineTransform")!
            t2.setValue(ciImage, forKey: kCIInputImageKey)
            t2.setValue(CGAffineTransform(translationX: dvOffset, y: 0), forKey: kCIInputTransformKey)
            let img2 = t2.outputImage ?? ciImage
            let blend = CIFilter(name: "CIAdditionCompositing")!
            blend.setValue(img1.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5)]), forKey: kCIInputImageKey)
            blend.setValue(img2.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5)]), forKey: kCIInputBackgroundImageKey)
            ciImage = blend.outputImage ?? ciImage
        case .flipbook:
            let flipPhase = Int(t * 8 * intensity) % 4
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform.identity
            switch flipPhase {
            case 0: affine = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -imageSize.width, y: 0)
            case 1: affine = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -imageSize.height)
            case 2:
                affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
                affine = affine.rotated(by: .pi)
                affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
            default: break
            }
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
        case .mosaic:
            let hexagonal = CIFilter(name: "CIHexagonalPixellate")!
            hexagonal.setValue(ciImage, forKey: kCIInputImageKey)
            hexagonal.setValue(center, forKey: kCIInputCenterKey)
            hexagonal.setValue(10 + (1 - level) * 30 * intensity, forKey: kCIInputScaleKey)
            ciImage = hexagonal.outputImage ?? ciImage
        case .pixelate:
            let pixellate = CIFilter(name: "CIPixellate")!
            pixellate.setValue(ciImage, forKey: kCIInputImageKey)
            pixellate.setValue(center, forKey: kCIInputCenterKey)
            pixellate.setValue(5 + (1 - level) * 40 * intensity, forKey: kCIInputScaleKey)
            ciImage = pixellate.outputImage ?? ciImage
        case .scanlines:
            let lines = CIFilter(name: "CILineScreen")!
            lines.setValue(ciImage, forKey: kCIInputImageKey)
            lines.setValue(center, forKey: kCIInputCenterKey)
            lines.setValue(t * 0.5, forKey: kCIInputAngleKey)
            lines.setValue(3 + bass * 5 * intensity, forKey: kCIInputWidthKey)
            lines.setValue(0.7 + bass * 0.3, forKey: kCIInputSharpnessKey)
            ciImage = lines.outputImage ?? ciImage
        case .datamosh:
            let edges = CIFilter(name: "CIEdgeWork")!
            edges.setValue(ciImage, forKey: kCIInputImageKey)
            edges.setValue(3 + bass * 10 * intensity, forKey: kCIInputRadiusKey)
            let edgeImage = edges.outputImage ?? ciImage
            let blend = CIFilter(name: "CIMultiplyBlendMode")!
            blend.setValue(edgeImage, forKey: kCIInputImageKey)
            blend.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
            ciImage = blend.outputImage ?? ciImage
            let hue = CIFilter(name: "CIHueAdjust")!
            hue.setValue(ciImage, forKey: kCIInputImageKey)
            hue.setValue(bass * 3 * intensity, forKey: kCIInputAngleKey)
            ciImage = hue.outputImage ?? ciImage
        case .blocky:
            let pixellate = CIFilter(name: "CIPixellate")!
            pixellate.setValue(ciImage, forKey: kCIInputImageKey)
            pixellate.setValue(center, forKey: kCIInputCenterKey)
            pixellate.setValue(20 + bass * 60 * intensity, forKey: kCIInputScaleKey)
            ciImage = pixellate.outputImage ?? ciImage
        }
        
        let outputExtent = ciImage.extent
        if let outputCGImage = ciContext.createCGImage(ciImage, from: outputExtent) {
            context.draw(outputCGImage, in: artworkRect)
        }
    }
    
    // MARK: - Column Support
    
    private var hasColumnContent: Bool {
        displayItems.contains { columnsForItem($0) != nil }
    }

    private var hasInternetRadioColumns: Bool {
        guard case .radio = currentSource else { return false }
        return displayItems.contains {
            if case .radioStation = $0.type { return true }
            return false
        }
    }

    private func isInternetRadioItem(_ item: ModernDisplayItem) -> Bool {
        guard case .radio = currentSource else { return false }
        if case .radioStation = item.type { return true }
        return false
    }

    /// YouTube channel uploads render through the resizable column path (title + time),
    /// gated on the "Channels" view actually containing video rows.
    private var hasYouTubeColumns: Bool {
        guard radioSlotShowingChannels else { return false }
        return displayItems.contains {
            if case .youtubeVideo = $0.type { return true }
            return false
        }
    }

    private func headerColumnsForCurrentContent() -> [ModernBrowserColumn]? {
        if hasInternetRadioColumns {
            return ModernBrowserColumn.internetRadioColumns
        }
        if hasYouTubeColumns {
            return ModernBrowserColumn.youtubeColumns
        }
        let columns = currentVisibleColumns()
        guard !columns.isEmpty else { return nil }
        return columns
    }

    private func visibleColumns(allColumns: [ModernBrowserColumn], visibleIds: [String]) -> [ModernBrowserColumn] {
        LibraryColumnVisibility.visibleColumns(allColumns: allColumns, visibleIds: visibleIds) { $0.id }
    }

    private func normalizedColumnIds(_ ids: [String], allColumns: [ModernBrowserColumn]) -> [String] {
        LibraryColumnVisibility.normalizedIds(ids, allIds: allColumns.map { $0.id })
    }

    private func hasTrackRows() -> Bool {
        if displayItems.contains(where: {
            switch $0.type { case .track, .subsonicTrack, .localTrack, .jellyfinTrack, .embyTrack: return true; default: return false }
        }) {
            return true
        }
        return false
    }

    private func hasAlbumRows() -> Bool {
        if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum, .jellyfinAlbum, .embyAlbum: return true; default: return false }
        }) {
            return true
        }
        return false
    }

    private func hasArtistRows() -> Bool {
        if displayItems.contains(where: {
            guard $0.indentLevel == 0 else { return false }
            switch $0.type { case .artist, .subsonicArtist, .localArtist, .jellyfinArtist, .embyArtist: return true; default: return false }
        }) {
            return true
        }
        return false
    }

    private func columnGroup(for item: ModernDisplayItem) -> LibraryColumnVisibilityGroup? {
        switch item.type {
        case .track, .subsonicTrack, .localTrack, .jellyfinTrack, .embyTrack:
            return .track
        case .album, .subsonicAlbum, .localAlbum, .jellyfinAlbum, .embyAlbum:
            return .album
        case .artist, .subsonicArtist, .localArtist, .jellyfinArtist, .embyArtist:
            return item.indentLevel == 0 ? .artist : nil
        case .youtubeVideo:
            return .youtube
        default:
            return nil
        }
    }

    private func currentColumnGroup() -> LibraryColumnVisibilityGroup? {
        if hasYouTubeColumns { return .youtube }
        if hasTrackRows() { return .track }
        if hasAlbumRows() { return .album }
        if hasArtistRows() { return .artist }
        return nil
    }

    private func columnsForItem(_ item: ModernDisplayItem) -> [ModernBrowserColumn]? {
        switch columnGroup(for: item) {
        case .track:
            return visibleColumns(allColumns: ModernBrowserColumn.allTrackColumns, visibleIds: visibleTrackColumnIds)
        case .album:
            return visibleColumns(allColumns: ModernBrowserColumn.allAlbumColumns, visibleIds: visibleAlbumColumnIds)
        case .artist:
            return visibleColumns(allColumns: ModernBrowserColumn.allArtistColumns, visibleIds: visibleArtistColumnIds)
        case .youtube:
            return ModernBrowserColumn.youtubeColumns
        case nil:
            break
        }

        switch item.type {
        case .radioStation:
            if isInternetRadioItem(item) {
                return ModernBrowserColumn.internetRadioColumns
            }
            return nil
        default:
            return nil
        }
    }
    
    private func columnWidthKey(_ columnId: String, group: LibraryColumnVisibilityGroup) -> String {
        "\(group.rawValue):\(columnId)"
    }

    private func storedColumnWidth(for column: ModernBrowserColumn, group: LibraryColumnVisibilityGroup?) -> CGFloat? {
        guard let group else { return columnWidths[column.id] }
        return columnWidths[columnWidthKey(column.id, group: group)]
    }

    private func setColumnWidth(_ width: CGFloat, for columnId: String, group: LibraryColumnVisibilityGroup) {
        columnWidths[columnWidthKey(columnId, group: group)] = width
    }

    private func widthForColumn(
        _ column: ModernBrowserColumn,
        availableWidth: CGFloat,
        columns: [ModernBrowserColumn],
        group: LibraryColumnVisibilityGroup?
    ) -> CGFloat {
        if column.id == "title" {
            // If a stored width exists for the title column (set when user resizes any column), use it
            if let storedWidth = storedColumnWidth(for: column, group: group) {
                return max(column.minWidth, storedWidth)
            }
            // Otherwise, title is flexible and fills remaining space
            let fixedWidth = columns.filter { $0.id != "title" }.reduce(0) {
                $0 + (storedColumnWidth(for: $1, group: group) ?? $1.minWidth)
            }
            return max(column.minWidth, availableWidth - fixedWidth - 8)
        }
        return storedColumnWidth(for: column, group: group) ?? column.minWidth
    }
    
    private func totalColumnsWidth(
        columns: [ModernBrowserColumn],
        availableWidth: CGFloat,
        group: LibraryColumnVisibilityGroup?
    ) -> CGFloat {
        8 + columns.reduce(0) { total, column in
            total + widthForColumn(column, availableWidth: availableWidth, columns: columns, group: group)
        }
    }

    private func clampHorizontalScrollOffset() {
        let columns = currentVisibleColumns()
        let group = currentColumnGroup()
        let availableWidth = bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - Layout.alphabetWidth
        let maxOffset = max(0, totalColumnsWidth(columns: columns, availableWidth: availableWidth, group: group) - availableWidth)
        horizontalScrollOffset = max(0, min(horizontalScrollOffset, maxOffset))
    }
    
    private func saveColumnWidths() {
        UserDefaults.standard.set(columnWidths, forKey: "BrowserColumnWidths")
    }
    
    private func loadColumnWidths() {
        if let saved = UserDefaults.standard.dictionary(forKey: "BrowserColumnWidths") as? [String: CGFloat] {
            columnWidths = migrateColumnWidths(saved)
        }
    }

    private func migrateColumnWidths(_ saved: [String: CGFloat]) -> [String: CGFloat] {
        var migrated: [String: CGFloat] = [:]
        for (key, width) in saved {
            if key.contains(":") {
                migrated[key] = width
                continue
            }
            for group in LibraryColumnVisibilityGroup.allCases where allColumns(for: group).contains(where: { $0.id == key }) {
                migrated[columnWidthKey(key, group: group)] = width
            }
        }
        return migrated
    }
    
    private func saveColumnSort() {
        if let id = columnSortId {
            UserDefaults.standard.set(id, forKey: "BrowserColumnSortId")
            UserDefaults.standard.set(columnSortAscending, forKey: "BrowserColumnSortAscending")
        } else {
            UserDefaults.standard.removeObject(forKey: "BrowserColumnSortId")
        }
    }
    
    private func loadColumnSort() {
        columnSortId = UserDefaults.standard.string(forKey: "BrowserColumnSortId")
        columnSortAscending = UserDefaults.standard.bool(forKey: "BrowserColumnSortAscending")
        if UserDefaults.standard.object(forKey: "BrowserColumnSortAscending") == nil {
            columnSortAscending = true
        }
    }
    
    private func saveVisibleColumns() {
        UserDefaults.standard.set(visibleTrackColumnIds, forKey: "BrowserVisibleTrackColumns")
        UserDefaults.standard.set(visibleAlbumColumnIds, forKey: "BrowserVisibleAlbumColumns")
        UserDefaults.standard.set(visibleArtistColumnIds, forKey: "BrowserVisibleArtistColumns")
    }
    
    private func loadVisibleColumns() {
        if let saved = UserDefaults.standard.stringArray(forKey: "BrowserVisibleTrackColumns") {
            visibleTrackColumnIds = normalizedColumnIds(saved, allColumns: ModernBrowserColumn.allTrackColumns)
        }
        if let saved = UserDefaults.standard.stringArray(forKey: "BrowserVisibleAlbumColumns") {
            visibleAlbumColumnIds = normalizedColumnIds(saved, allColumns: ModernBrowserColumn.allAlbumColumns)
        }
        if let saved = UserDefaults.standard.stringArray(forKey: "BrowserVisibleArtistColumns") {
            visibleArtistColumnIds = normalizedColumnIds(saved, allColumns: ModernBrowserColumn.allArtistColumns)
        }
    }
    
    /// Returns the currently visible columns based on what type of items are displayed
    private func currentVisibleColumns() -> [ModernBrowserColumn] {
        if hasInternetRadioColumns {
            return ModernBrowserColumn.internetRadioColumns
        }
        if hasYouTubeColumns {
            return ModernBrowserColumn.youtubeColumns
        }
        if hasTrackRows() {
            return visibleColumns(allColumns: ModernBrowserColumn.allTrackColumns, visibleIds: visibleTrackColumnIds)
        }
        if hasAlbumRows() {
            return visibleColumns(allColumns: ModernBrowserColumn.allAlbumColumns, visibleIds: visibleAlbumColumnIds)
        }
        if hasArtistRows() {
            return visibleColumns(allColumns: ModernBrowserColumn.allArtistColumns, visibleIds: visibleArtistColumnIds)
        }
        return []
    }
    
    private func applyColumnSort(collapseExpanded: Bool = false) {
        guard let sortColumnId = activeColumnSortId, !displayItems.isEmpty else {
            needsDisplay = true
            return
        }
        
        if collapseExpanded {
            let hadExpanded = !expandedArtists.isEmpty || !expandedAlbums.isEmpty ||
                              !expandedArtistNames.isEmpty ||
                              !expandedLocalArtists.isEmpty || !expandedLocalAlbums.isEmpty ||
                              !expandedLocalShows.isEmpty || !expandedLocalSeasons.isEmpty ||
                              !expandedSubsonicArtists.isEmpty || !expandedSubsonicAlbums.isEmpty ||
                              !expandedSubsonicPlaylists.isEmpty || !expandedPlexPlaylists.isEmpty ||
                              !expandedShows.isEmpty || !expandedSeasons.isEmpty
            if hadExpanded {
                expandedArtists.removeAll(); expandedAlbums.removeAll(); expandedArtistNames.removeAll()
                expandedLocalArtists.removeAll(); expandedLocalAlbums.removeAll()
                expandedLocalShows.removeAll(); expandedLocalSeasons.removeAll()
                expandedSubsonicArtists.removeAll(); expandedSubsonicAlbums.removeAll()
                expandedSubsonicPlaylists.removeAll(); expandedPlexPlaylists.removeAll()
                expandedShows.removeAll(); expandedSeasons.removeAll()
                displayItems = displayItems.filter { $0.indentLevel == 0 }
            }
        }
        
        guard let sortColumn = ModernBrowserColumn.findColumn(id: sortColumnId) else {
            needsDisplay = true; return
        }

        if applyInternetRadioColumnSort(sortColumn: sortColumn, ascending: activeColumnSortAscending) {
            needsDisplay = true; return
        }

        if applyYouTubeColumnSort(sortColumn: sortColumn) {
            needsDisplay = true; return
        }

        // When rows are expanded, the build order comes from the store (SQLite BINARY
        // collation), which diverges from the in-memory column sort (LibraryTextSorter:
        // diacritic-insensitive, numeric, article-stripping) precisely around special
        // characters / case / leading articles. Re-sort the top-level groups — each level-0
        // leader plus its contiguous descendants — so expanding a row keeps the same
        // top-level order instead of snapping back to the raw store order.
        let hasNestedItems = displayItems.contains { $0.indentLevel > 0 }
        if hasNestedItems {
            sortNestedGroupsByColumn(sortColumn: sortColumn)
            return
        }

        var sortableIndices: [Int] = []
        var sortableItems: [ModernDisplayItem] = []
        
        for (index, item) in displayItems.enumerated() {
            if columnsForItem(item) != nil && item.indentLevel == 0 {
                sortableIndices.append(index)
                sortableItems.append(item)
            }
        }
        
        guard !sortableItems.isEmpty else { needsDisplay = true; return }
        
        sortableItems = stableColumnSortedItems(sortableItems, sortColumn: sortColumn)

        for (sortedIndex, originalIndex) in sortableIndices.enumerated() {
            displayItems[originalIndex] = sortableItems[sortedIndex]
        }
        needsDisplay = true
    }

    /// Reorders the top-level groups in `displayItems` (a level-0 leader plus its contiguous
    /// descendants) by the active column, keeping each group's internal order intact. Bails
    /// to the build order if any top-level row is not sortable (e.g. a section header) or if a
    /// nested row appears before any leader, since grouping would be ambiguous there.
    private func sortNestedGroupsByColumn(sortColumn: ModernBrowserColumn) {
        var groups: [[ModernDisplayItem]] = []
        for item in displayItems {
            if item.indentLevel == 0 {
                guard columnsForItem(item) != nil else { needsDisplay = true; return }
                groups.append([item])
            } else if !groups.isEmpty {
                groups[groups.count - 1].append(item)
            } else {
                needsDisplay = true
                return
            }
        }

        groups = stableColumnSortedGroups(groups, sortColumn: sortColumn)
        displayItems = groups.flatMap { $0 }
        needsDisplay = true
    }

    /// Sorts column-capable rows while preserving their current order for equal keys.
    private func stableColumnSortedItems(_ items: [ModernDisplayItem], sortColumn: ModernBrowserColumn) -> [ModernDisplayItem] {
        items.enumerated().sorted { lhs, rhs in
            if columnSortAreInOrder(lhs.element, rhs.element, sortColumn: sortColumn, ascending: activeColumnSortAscending) {
                return true
            }
            if columnSortAreInOrder(rhs.element, lhs.element, sortColumn: sortColumn, ascending: activeColumnSortAscending) {
                return false
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Sorts expanded row groups by leader while preserving current group order for equal keys.
    private func stableColumnSortedGroups(_ groups: [[ModernDisplayItem]], sortColumn: ModernBrowserColumn) -> [[ModernDisplayItem]] {
        groups.enumerated().sorted { lhs, rhs in
            let leftLeader = lhs.element[0]
            let rightLeader = rhs.element[0]
            if columnSortAreInOrder(leftLeader, rightLeader, sortColumn: sortColumn, ascending: activeColumnSortAscending) {
                return true
            }
            if columnSortAreInOrder(rightLeader, leftLeader, sortColumn: sortColumn, ascending: activeColumnSortAscending) {
                return false
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Ordering predicate shared by the flat and nested column-sort paths so both produce
    /// an identical top-level order. `a` and `b` are level-0 rows.
    private func columnSortAreInOrder(_ a: ModernDisplayItem, _ b: ModernDisplayItem, sortColumn: ModernBrowserColumn, ascending: Bool) -> Bool {
        // Date columns: sort by raw date, not formatted string
        if sortColumn.id == "dateAdded" || sortColumn.id == "lastPlayed" || sortColumn.id == "youtubeDate" {
            let aDate = a.columnDateValue(for: sortColumn) ?? .distantPast
            let bDate = b.columnDateValue(for: sortColumn) ?? .distantPast
            return ascending ? aDate < bDate : aDate > bDate
        }

        let aVal = a.columnValue(for: sortColumn)
        let bVal = b.columnValue(for: sortColumn)

        if sortColumn.id == "trackNum" || sortColumn.id == "year" || sortColumn.id == "plays" ||
           sortColumn.id == "albums" || sortColumn.id == "discNum" {
            let aNum = Int(aVal.components(separatedBy: "-").last ?? aVal) ?? 0
            let bNum = Int(bVal.components(separatedBy: "-").last ?? bVal) ?? 0
            return ascending ? aNum < bNum : aNum > bNum
        }
        if sortColumn.id == "channels" {
            let aChannels = LibraryColumnVisibility.channelSortValue(aVal)
            let bChannels = LibraryColumnVisibility.channelSortValue(bVal)
            return ascending ? aChannels < bChannels : aChannels > bChannels
        }
        if sortColumn.id == "duration" {
            let aSeconds = parseDuration(aVal)
            let bSeconds = parseDuration(bVal)
            return ascending ? aSeconds < bSeconds : aSeconds > bSeconds
        }
        if sortColumn.id == "bitrate" || sortColumn.id == "sampleRate" {
            let cleaned = { (s: String) -> Double in
                let num = s.replacingOccurrences(of: "k", with: "")
                return Double(num) ?? 0
            }
            return ascending ? cleaned(aVal) < cleaned(bVal) : cleaned(aVal) > cleaned(bVal)
        }
        if sortColumn.id == "size" {
            let aSize = parseSize(aVal)
            let bSize = parseSize(bVal)
            return ascending ? aSize < bSize : aSize > bSize
        }
        if sortColumn.id == "rating" {
            let aStars = aVal.filter { $0 == "★" }.count
            let bStars = bVal.filter { $0 == "★" }.count
            return ascending ? aStars < bStars : aStars > bStars
        }
        return compareNameStrings(aVal, bVal, ascending: ascending)
    }

    private func applyInternetRadioColumnSort(sortColumn: ModernBrowserColumn, ascending: Bool) -> Bool {
        guard case .radio = currentSource,
              ModernBrowserColumn.internetRadioColumns.contains(where: { $0.id == sortColumn.id }),
              displayItems.contains(where: isInternetRadioItem) else {
            return false
        }

        var index = 0
        var didSort = false
        while index < displayItems.count {
            guard isInternetRadioItem(displayItems[index]) else {
                index += 1
                continue
            }

            let start = index
            while index < displayItems.count, isInternetRadioItem(displayItems[index]) {
                index += 1
            }

            let sorted = sortedInternetRadioItems(Array(displayItems[start..<index]), sortColumn: sortColumn, ascending: ascending)
            displayItems.replaceSubrange(start..<index, with: sorted)
            didSort = true
        }
        return didSort
    }

    /// Sorts the videos within each expanded YouTube channel (contiguous runs of video rows)
    /// by the clicked column, leaving the channel leaders in place. Mirrors the internet-radio
    /// in-place run sort so the "Channels" view supports sortable column headers like other tabs.
    private func applyYouTubeColumnSort(sortColumn: ModernBrowserColumn) -> Bool {
        guard radioSlotShowingChannels,
              ModernBrowserColumn.youtubeColumns.contains(where: { $0.id == sortColumn.id }),
              displayItems.contains(where: { if case .youtubeVideo = $0.type { return true }; return false }) else {
            return false
        }

        var index = 0
        while index < displayItems.count {
            guard case .youtubeVideo = displayItems[index].type else { index += 1; continue }
            let start = index
            while index < displayItems.count, case .youtubeVideo = displayItems[index].type {
                index += 1
            }
            let sorted = stableColumnSortedItems(Array(displayItems[start..<index]), sortColumn: sortColumn)
            displayItems.replaceSubrange(start..<index, with: sorted)
        }
        return true
    }

    private func sortedInternetRadioItems(_ items: [ModernDisplayItem], sortColumn: ModernBrowserColumn, ascending: Bool) -> [ModernDisplayItem] {
        let ratingsByItemId = Dictionary(uniqueKeysWithValues: items.map { item in
            (item.id, internetRadioRating(for: item))
        })

        return items.enumerated().sorted { lhs, rhs in
            let comparison = compareInternetRadioItems(lhs.element, rhs.element, sortColumn: sortColumn, ratingsByItemId: ratingsByItemId)
            if comparison == .orderedSame { return lhs.offset < rhs.offset }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }.map(\.element)
    }

    private func compareInternetRadioItems(
        _ lhs: ModernDisplayItem,
        _ rhs: ModernDisplayItem,
        sortColumn: ModernBrowserColumn,
        ratingsByItemId: [String: Int]
    ) -> ComparisonResult {
        switch sortColumn.id {
        case "rating":
            let lhsRating = internetRadioRating(for: lhs, ratingsByItemId: ratingsByItemId)
            let rhsRating = internetRadioRating(for: rhs, ratingsByItemId: ratingsByItemId)
            if lhsRating != rhsRating {
                return lhsRating < rhsRating ? .orderedAscending : .orderedDescending
            }
            return LibraryTextSorter.compare(lhs.title, rhs.title, ignoreLeadingArticles: true)
        case "genre":
            let genreComparison = LibraryTextSorter.compare(lhs.columnValue(for: sortColumn), rhs.columnValue(for: sortColumn), ignoreLeadingArticles: true)
            if genreComparison != .orderedSame { return genreComparison }
            return LibraryTextSorter.compare(lhs.title, rhs.title, ignoreLeadingArticles: true)
        default:
            return LibraryTextSorter.compare(lhs.columnValue(for: sortColumn), rhs.columnValue(for: sortColumn), ignoreLeadingArticles: true)
        }
    }

    private func internetRadioRating(for item: ModernDisplayItem) -> Int {
        guard case .radioStation(let station) = item.type else { return 0 }
        return RadioManager.shared.rating(for: station)
    }

    private func internetRadioRating(for item: ModernDisplayItem, ratingsByItemId: [String: Int]) -> Int {
        ratingsByItemId[item.id] ?? 0
    }
    
    private func parseDuration(_ str: String) -> Int {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }
    
    private func parseSize(_ str: String) -> Int64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("G") { return Int64((Double(trimmed.dropLast()) ?? 0) * 1024 * 1024 * 1024) }
        if trimmed.hasSuffix("M") { return Int64((Double(trimmed.dropLast()) ?? 0) * 1024 * 1024) }
        return Int64(trimmed) ?? 0
    }
    
    // MARK: - Utility
    
    private func calculateCenterFillRect(imageSize: NSSize, in targetRect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return targetRect }
        let imageAspect = imageSize.width / imageSize.height
        let targetAspect = targetRect.width / targetRect.height
        var width: CGFloat
        var height: CGFloat
        if imageAspect > targetAspect {
            width = targetRect.width
            height = width / imageAspect
        } else {
            height = targetRect.height
            width = height * imageAspect
        }
        let x = targetRect.minX + (targetRect.width - width) / 2
        let y = targetRect.minY + (targetRect.height - height) / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Hit Testing (Bottom-Left Origin)
    
    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        let m = ModernSkinElements.sizeMultiplier
        return point.y > bounds.height - Layout.titleBarHeight &&
               point.x < bounds.width - 30 * m
    }
    
    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        let m = ModernSkinElements.sizeMultiplier
        let closeRect = NSRect(x: bounds.width - 20 * m, y: bounds.height - Layout.titleBarHeight, width: 20 * m, height: Layout.titleBarHeight)
        return closeRect.contains(point)
    }
    
    private func hitTestShadeButton(at point: NSPoint) -> Bool {
        let m = ModernSkinElements.sizeMultiplier
        let shadeRect = NSRect(x: bounds.width - 31 * m, y: bounds.height - Layout.titleBarHeight, width: 11 * m, height: Layout.titleBarHeight)
        return shadeRect.contains(point)
    }
    
    private func hitTestServerBar(at point: NSPoint) -> Bool {
        let serverBarY = topChromeBottomY - Layout.serverBarHeight
        return point.y >= serverBarY && point.y < topChromeBottomY
    }
    
    private func hitTestTabBar(at point: NSPoint) -> ModernBrowseMode? {
        let tabBarTopY = topChromeBottomY - Layout.serverBarHeight
        let tabBarBottomY = tabBarTopY - Layout.tabBarHeight
        guard point.y >= tabBarBottomY && point.y < tabBarTopY else { return nil }

        let skin = currentSkin()
        let font = skin.sideWindowFont(size: 11)
        let sortText = "Sort"
        let sortAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let sortWidth = sortText.size(withAttributes: sortAttrs).width + 16 * ModernSkinElements.sizeMultiplier

        let tabsWidth = bounds.width - Layout.borderWidth * 2 - sortWidth
        let widths = tabBarWidths(totalWidth: tabsWidth, labels: currentTabLabels(), font: font)
        let relativeX = point.x - Layout.borderWidth

        if relativeX >= 0 && relativeX < tabsWidth {
            var x: CGFloat = 0
            for (index, width) in widths.enumerated() {
                if relativeX < x + width {
                    return ModernBrowseMode.allCases[index]
                }
                x += width
            }
        }
        return nil
    }
    
    private func hitTestSortIndicator(at point: NSPoint) -> Bool {
        let tabBarTopY = topChromeBottomY - Layout.serverBarHeight
        let tabBarBottomY = tabBarTopY - Layout.tabBarHeight
        guard point.y >= tabBarBottomY && point.y < tabBarTopY else { return false }
        
        let skin = currentSkin()
        let font = skin.sideWindowFont(size: 11)
        let sortText = "Sort"
        let sortAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let sortWidth = sortText.size(withAttributes: sortAttrs).width + 16 * ModernSkinElements.sizeMultiplier
        
        let sortX = bounds.width - Layout.borderWidth - sortWidth
        return point.x >= sortX && point.x < bounds.width - Layout.borderWidth
    }
    
    private func hitTestSearchBar(at point: NSPoint) -> Bool {
        guard browseMode == .search else { return false }
        let tabBarBottomY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        let searchBarBottomY = tabBarBottomY - Layout.searchBarHeight
        return point.y >= searchBarBottomY && point.y < tabBarBottomY
    }
    
    private func hitTestListArea(at point: NSPoint) -> Int? {
        var contentTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        if hasColumns { contentTopY -= columnHeaderHeight }
        
        let contentBottomY = Layout.statusBarHeight
        let contentHeight = contentTopY - contentBottomY
        
        let alphabetWidth = Layout.alphabetWidth
        let listRect = NSRect(x: Layout.borderWidth, y: contentBottomY,
                              width: bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - alphabetWidth,
                              height: contentHeight)
        
        guard listRect.contains(point) else { return nil }
        
        // In bottom-left origin, items are rendered from top down
        let relativeFromTop = contentTopY - point.y + scrollOffset
        let clickedIndex = Int(relativeFromTop / itemHeight)
        
        if clickedIndex >= 0 && clickedIndex < displayItems.count {
            return clickedIndex
        }
        return nil
    }

    private func hitTestInternetRadioRating(at point: NSPoint, itemIndex: Int) -> Int? {
        guard hasInternetRadioColumns, itemIndex >= 0, itemIndex < displayItems.count else { return nil }
        let item = displayItems[itemIndex]
        guard case .radioStation = item.type, let columns = columnsForItem(item) else { return nil }

        var contentTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        if hasColumns { contentTopY -= columnHeaderHeight }

        let contentBottomY = Layout.statusBarHeight
        let alphabetWidth = Layout.alphabetWidth
        let listRect = NSRect(
            x: Layout.borderWidth,
            y: contentBottomY,
            width: bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - alphabetWidth,
            height: contentTopY - contentBottomY
        )

        let itemTopY = listRect.maxY - CGFloat(itemIndex) * itemHeight + scrollOffset
        let rowRect = NSRect(x: listRect.minX, y: itemTopY - itemHeight, width: listRect.width, height: itemHeight)
        guard rowRect.contains(point) else { return nil }

        let indent = CGFloat(item.indentLevel) * 16
        let availableWidth = rowRect.width - indent
        var x = rowRect.minX + indent + 4 - horizontalScrollOffset
        let group = columnGroup(for: item)
        for column in columns {
            let width = widthForColumn(column, availableWidth: availableWidth, columns: columns, group: group)
            if column.id == "rating" {
                let cellRect = NSRect(x: x, y: rowRect.minY, width: width, height: rowRect.height)
                guard cellRect.contains(point) else { return nil }
                let innerWidth = max(1, cellRect.width - 8)
                let clampedX = min(max(point.x, cellRect.minX + 4), cellRect.maxX - 4)
                let normalized = (clampedX - (cellRect.minX + 4)) / innerWidth
                let star = min(5, max(1, Int(normalized * 5.0) + 1))
                return star
            }
            x += width
        }
        return nil
    }
    
    private func hitTestAlphabetIndex(at point: NSPoint) -> Bool {
        var contentTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let listHeight = contentTopY - Layout.statusBarHeight
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        let effectiveHeight = listHeight - (hasColumns ? columnHeaderHeight : 0)
        let alphabetX = bounds.width - Layout.borderWidth - Layout.scrollbarWidth - Layout.alphabetWidth
        return point.x >= alphabetX && point.x < alphabetX + Layout.alphabetWidth &&
               point.y >= Layout.statusBarHeight && point.y < Layout.statusBarHeight + effectiveHeight
    }
    
    private func hitTestContentArea(at point: NSPoint) -> Bool {
        let contentTopY = topChromeBottomY - Layout.serverBarHeight
        let contentBottomY = Layout.statusBarHeight
        let contentRect = NSRect(x: Layout.borderWidth, y: contentBottomY,
                                 width: bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth,
                                 height: contentTopY - contentBottomY)
        return contentRect.contains(point)
    }
    
    private func hitTestColumnResize(at point: NSPoint) -> String? {
        if hasInternetRadioColumns { return nil }
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        guard hasColumns else { return nil }
        
        var headerTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { headerTopY -= Layout.searchBarHeight }
        let headerBottomY = headerTopY - columnHeaderHeight
        
        guard point.y >= headerBottomY && point.y < headerTopY else { return nil }
        
        let columns = currentVisibleColumns()
        let group = currentColumnGroup()
        guard columns.count > 1 else { return nil }
        
        let headerWidth = bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - Layout.alphabetWidth
        let threshold: CGFloat = 4 * ModernSkinElements.sizeMultiplier
        var x = Layout.borderWidth + 4 - horizontalScrollOffset
        
        for (index, column) in columns.enumerated() {
            let width = widthForColumn(column, availableWidth: headerWidth, columns: columns, group: group)
            let edgeX = x + width
            
            // Allow resizing any non-last column by dragging its right edge
            if index < columns.count - 1 {
                if abs(point.x - edgeX) < threshold {
                    return column.id
                }
            }
            // Allow resizing column to the left of title (drag left edge of title = resize previous column)
            if index > 0 && column.id == "title" {
                if abs(point.x - x) < threshold {
                    return columns[index - 1].id
                }
            }
            x += width
        }
        return nil
    }
    
    private func hitTestColumnHeader(at point: NSPoint) -> String? {
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        guard hasColumns else { return nil }
        
        var headerTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { headerTopY -= Layout.searchBarHeight }
        let headerBottomY = headerTopY - columnHeaderHeight
        
        guard point.y >= headerBottomY && point.y < headerTopY else { return nil }
        
        let columns = currentVisibleColumns()
        let group = currentColumnGroup()
        
        let headerWidth = bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - Layout.alphabetWidth
        var x = Layout.borderWidth + 4 - horizontalScrollOffset
        for column in columns {
            let width = widthForColumn(column, availableWidth: headerWidth, columns: columns, group: group)
            if point.x >= x && point.x < x + width { return column.id }
            x += width
        }
        return nil
    }
    
    /// Returns true if the point is within the column header area (for right-click detection)
    private func hitTestColumnHeaderArea(at point: NSPoint) -> Bool {
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        guard hasColumns else { return false }
        
        var headerTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { headerTopY -= Layout.searchBarHeight }
        let headerBottomY = headerTopY - columnHeaderHeight
        
        return point.y >= headerBottomY && point.y < headerTopY
    }
    
    // MARK: - Mouse Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }
    
    private func cancelPendingArtSingleClickAction() {
        pendingArtSingleClickWorkItem?.cancel()
        pendingArtSingleClickWorkItem = nil
    }
    
    private func scheduleArtSingleClickRatingOverlay() {
        cancelPendingArtSingleClickAction()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingArtSingleClickWorkItem = nil
            guard self.isArtOnlyMode, !self.isVisualizingArt else { return }
            self.showRatingOverlay()
        }
        
        pendingArtSingleClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
    }
    
    private func handleArtOnlyContentClick(_ event: NSEvent) {
        if event.clickCount >= 2 {
            cancelPendingArtSingleClickAction()
            cycleToNextArtwork()
            return
        }
        
        scheduleArtSingleClickRatingOverlay()
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Any new click should clear a pending single-click action unless this click
        // re-schedules/handles the art-only interaction.
        cancelPendingArtSingleClickAction()

        // When HT is on, record drag start point early so mouseDragged can move the window
        // from anywhere (title bar is hidden so there's no dedicated drag handle)
        if WindowManager.shared.hideTitleBars && !isShadeMode {
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillPrimeDragging(window)
                didPrimeWindowDragHold = true
            }
        }

        // Double-click title bar for shade (only when titlebar is visible)
        if event.clickCount == 2 && hitTestTitleBar(at: point) && !WindowManager.shared.hideTitleBars {
            toggleShadeMode(); return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: point, event: event); return
        }
        
        // Window buttons (only when titlebar is visible)
        if !WindowManager.shared.hideTitleBars {
            if hitTestCloseButton(at: point) { pressedButton = .close; needsDisplay = true; return }
            if hitTestShadeButton(at: point) { pressedButton = .shade; needsDisplay = true; return }
        }
        
        // Server bar (check before content area so ART/VIS/source buttons work)
        if hitTestServerBar(at: point) {
            if case .plex = currentSource, !PlexManager.shared.isLinked {
                controller?.showLinkSheet()
            } else {
                handleServerBarClick(at: point, event: event)
            }
            return
        }
        
        // Sort indicator
        if hitTestSortIndicator(at: point) { showSortMenu(at: event.locationInWindow); return }
        
        // Tab bar (check before content area so tabs work in art-only/viz mode)
        if let tabMode = hitTestTabBar(at: point) {
            // Special handling: double-click .plists slot while local source toggles Folders
            if event.clickCount == 2 && tabMode == .plists {
                if case .local = currentSource {
                    localPlistsSlotShowsFolders.toggle()
                    browseMode = effectivePlistsSlotMode
                    selectedIndices.removeAll(); scrollOffset = 0
                    loadDataForCurrentMode(); window?.makeFirstResponder(self)
                    return
                }
            }
            // Double-click the radio slot while the YouTube source toggles Radio/Channels.
            if event.clickCount == 2 && tabMode == .radio && currentSource.isYouTube {
                radioSlotShowsChannels.toggle()
                browseMode = .radio
                selectedIndices.removeAll(); scrollOffset = 0
                loadDataForCurrentMode(); window?.makeFirstResponder(self)
                return
            }
            // Single-click selects whatever the slot currently shows (Plists or Folders)
            browseMode = (tabMode == .plists) ? effectivePlistsSlotMode : tabMode
            selectedIndices.removeAll(); scrollOffset = 0
            loadDataForCurrentMode(); window?.makeFirstResponder(self)
            return
        }
        
        // Search bar
        if hitTestSearchBar(at: point) { window?.makeFirstResponder(self); return }
        
        // Art-only mode: visualization click cycles effects.
        // In non-visualizer art mode, single-click rates and double-click cycles artwork.
        // (checked AFTER server bar, tabs, and search bar so those still work)
        if isArtOnlyMode && isVisualizingArt && hitTestContentArea(at: point) {
            nextVisEffect(); return
        }
        if isArtOnlyMode && !isVisualizingArt && hitTestContentArea(at: point) {
            handleArtOnlyContentClick(event); return
        }
        
        // Column resize (check before sort so edge-drag doesn't trigger sort)
        if let columnId = hitTestColumnResize(at: point) {
            resizingColumnId = columnId
            resizingColumnGroup = currentColumnGroup()
            resizeStartX = point.x
            let columns = currentVisibleColumns()
            let group = resizingColumnGroup
            let headerWidth = bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - Layout.alphabetWidth
            resizeStartWidth = widthForColumn(ModernBrowserColumn.findColumn(id: columnId)!, availableWidth: headerWidth, columns: columns, group: group)
            // Freeze the title column's current width so it doesn't flex during resize
            if let group, storedColumnWidth(for: .title, group: group) == nil {
                let titleWidth = widthForColumn(.title, availableWidth: headerWidth, columns: columns, group: group)
                setColumnWidth(titleWidth, for: "title", group: group)
            }
            NSCursor.resizeLeftRight.push()
            return
        }
        
        // Column header click for sorting
        if let columnId = hitTestColumnHeader(at: point) {
            if currentSource.isYouTube {
                // YouTube uses its own session sort (not persisted to the library sort).
                if youtubeColumnSortId == columnId { youtubeColumnSortAscending.toggle() }
                else { youtubeColumnSortId = columnId; youtubeColumnSortAscending = true }
                applyColumnSort(collapseExpanded: true)
            } else if columnSortId == columnId {
                columnSortAscending.toggle()
            } else {
                columnSortId = columnId; columnSortAscending = true
            }
            return
        }
        
        // Alphabet index
        if hitTestAlphabetIndex(at: point) { handleAlphabetClick(at: point); return }
        
        // List area
        if let itemIndex = hitTestListArea(at: point) {
            handleListClick(at: itemIndex, event: event, point: point); return
        }
        
        // Title bar drag
        if hitTestTitleBar(at: point) {
            isDraggingWindow = true; windowDragStartPoint = event.locationInWindow
            if let window = window { WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true) }
        }
    }
    
    private func handleShadeMouseDown(at point: NSPoint, event: NSEvent) {
        if hitTestCloseButton(at: point) { pressedButton = .close; needsDisplay = true; return }
        if hitTestShadeButton(at: point) { pressedButton = .shade; needsDisplay = true; return }
        isDraggingWindow = true; windowDragStartPoint = event.locationInWindow
        if let window = window { WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true) }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if let columnId = resizingColumnId, let group = resizingColumnGroup {
            let point = convert(event.locationInWindow, from: nil)
            let deltaX = point.x - resizeStartX
            let minWidth = ModernBrowserColumn.findColumn(id: columnId)?.minWidth ?? 30
            setColumnWidth(max(minWidth, resizeStartWidth + deltaX), for: columnId, group: group)
            needsDisplay = true; return
        }

        // When HT is on, lazily start window drag on first mouseDragged (handles content-area drags)
        if !isDraggingWindow && WindowManager.shared.hideTitleBars && !isShadeMode {
            isDraggingWindow = true
            if let window = window { WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true) }
        }

        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX; newOrigin.y += deltaY
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        if resizingColumnId != nil { resizingColumnId = nil; resizingColumnGroup = nil; NSCursor.pop() }
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window { WindowManager.shared.windowDidFinishDragging(window) }
            didPrimeWindowDragHold = false
        } else if didPrimeWindowDragHold {
            if let window = window { WindowManager.shared.windowDidCancelDragPrime(window) }
            didPrimeWindowDragHold = false
        }
        isDraggingScrollbar = false
        
        if isShadeMode { handleShadeMouseUp(at: point); return }
        
        if let pressed = pressedButton {
            switch pressed {
            case .close: if hitTestCloseButton(at: point) { window?.close() }
            case .shade: if hitTestShadeButton(at: point) { toggleShadeMode() }
            }
            pressedButton = nil; needsDisplay = true
        }
    }
    
    private func handleShadeMouseUp(at point: NSPoint) {
        if let pressed = pressedButton {
            switch pressed {
            case .close: if hitTestCloseButton(at: point) { window?.close() }
            case .shade: if hitTestShadeButton(at: point) { toggleShadeMode() }
            }
            pressedButton = nil; needsDisplay = true
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hitTestColumnResize(at: point) != nil {
            NSCursor.resizeLeftRight.set()
        } else if hitTestAlphabetIndex(at: point) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        cancelPendingArtSingleClickAction()
        
        let point = convert(event.locationInWindow, from: nil)
        
        // Right-click on column header: show column visibility menu
        if hitTestColumnHeaderArea(at: point) {
            showColumnConfigMenu(at: event); return
        }
        
        if isArtOnlyMode && isVisualizingArt && hitTestContentArea(at: point) {
            showVisualizerMenu(at: event); return
        }
        if isArtOnlyMode && !isVisualizingArt && hitTestContentArea(at: point) {
            showArtContextMenu(at: event); return
        }
        
        if !isArtOnlyMode, let clickedIndex = hitTestListArea(at: point) {
            if !selectedIndices.contains(clickedIndex) { selectedIndices = [clickedIndex]; needsDisplay = true }
            let item = displayItems[clickedIndex]
            showContextMenu(for: item, at: event); return
        }
        if case .local = currentSource {
            let menu = NSMenu()
            let manageFoldersItem = NSMenuItem(title: "Manage Folders...", action: #selector(manageWatchFolders), keyEquivalent: "")
            manageFoldersItem.target = self; menu.addItem(manageFoldersItem)
            NSMenu.popUpContextMenu(menu, with: event, for: self); return
        }
        super.rightMouseDown(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        if browseMode.isHistoryMode {
            super.scrollWheel(with: event)
            return
        }
        var contentTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let listHeight = contentTopY - Layout.statusBarHeight
        let totalHeight = CGFloat(displayItems.count) * itemHeight

        if totalHeight > listHeight && abs(event.deltaY) > 0 {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))

            let listRect = NSRect(x: 0, y: Layout.statusBarHeight, width: bounds.width, height: listHeight)
            setNeedsDisplay(listRect)
        }

        if abs(event.deltaX) > 0 {
            let columns = currentVisibleColumns()
            let group = currentColumnGroup()
            let availableWidth = bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - Layout.alphabetWidth
            let totalWidth = totalColumnsWidth(columns: columns, availableWidth: availableWidth, group: group)
            let maxOffset = max(0, totalWidth - availableWidth)
            if maxOffset > 0 {
                horizontalScrollOffset = max(0, min(maxOffset, horizontalScrollOffset - event.deltaX * 3))
                let listRect = NSRect(x: 0, y: Layout.statusBarHeight, width: bounds.width, height: listHeight)
                setNeedsDisplay(listRect)
            }
        }

        // Trigger next-page load when scrolled near the bottom of a local paginated list
        if case .local = currentSource { loadNextLocalPageIfNeeded(listHeight: listHeight) }
    }

    private func loadNextLocalPageIfNeeded(listHeight: CGFloat) {
        let threshold = itemHeight * 10   // start loading 10 rows from bottom
        let loadedHeight = CGFloat(displayItems.count) * itemHeight
        guard scrollOffset + listHeight + threshold >= loadedHeight else { return }
        switch browseMode {
        case .artists:
            let nextOffset = localArtistPageOffset + localPageSize
            guard nextOffset < localArtistTotal else { return }
            localArtistPageOffset = nextOffset
            let store = MediaLibraryStore.shared
            let names = store.artistNames(limit: localPageSize, offset: localArtistPageOffset, sort: currentSort)
            let albumsByArtist = store.albumsForArtistsBatch(names)
            for name in names {
                let albumSummaries = albumsByArtist[name] ?? []
                let stubArtist = Artist(id: name, name: name, albums: [])
                displayItems.append(ModernDisplayItem(
                    id: "local-artist-\(name)",
                    title: name,
                    info: "\(albumSummaries.count) albums",
                    indentLevel: 0,
                    hasChildren: !albumSummaries.isEmpty,
                    type: .localArtist(stubArtist)
                ))
            }
            needsDisplay = true
        case .albums:
            let nextOffset = localAlbumPageOffset + localPageSize
            guard nextOffset < localAlbumTotal else { return }
            localAlbumPageOffset = nextOffset
            let store = MediaLibraryStore.shared
            let summaries = store.albumSummaries(limit: localPageSize, offset: localAlbumPageOffset, sort: currentSort)
            for summary in summaries {
                let album = Album(id: summary.id, name: summary.name, artist: summary.artist, year: summary.year, tracks: [])
                let displayName: String
                if let artist = summary.artist, !artist.isEmpty {
                    displayName = "\(artist) - \(summary.name)"
                } else {
                    displayName = summary.name
                }
                displayItems.append(ModernDisplayItem(
                    id: "local-album-\(album.id)",
                    title: displayName,
                    info: "\(summary.trackCount) tracks",
                    indentLevel: 0,
                    hasChildren: summary.trackCount > 0,
                    type: .localAlbum(album)
                ))
            }
            needsDisplay = true
        case .folders, .plists, .movies, .shows, .search, .radio, .history:
            break
        }
    }

    // MARK: - Keyboard Events
    
    override func keyDown(with event: NSEvent) {
        // Rating overlay shortcuts:
        // - Escape dismisses
        // - Delete/Backspace clears rating
        // - Number keys 1-5 set stars
        if isRatingOverlayVisible {
            if event.keyCode == 53 { hideRatingOverlay(); return }
            if event.keyCode == 51 || event.keyCode == 117 {
                ratingOverlay.setRating(0)
                submitRating(0)
                return
            }
            if event.keyCode >= 18 && event.keyCode <= 22 {
                let starRating = Int(event.keyCode - 17)  // 1-5
                ratingOverlay.setRating(starRating * 2)
                submitRating(starRating * 2)
                return
            }
        }
        
        if isVisualizingArt && isArtOnlyMode {
            switch event.keyCode {
            case 123: prevVisEffect(); return
            case 124: nextVisEffect(); return
            case 126: visEffectIntensity = min(2.0, visEffectIntensity + 0.25); return
            case 125: visEffectIntensity = max(0.5, visEffectIntensity - 0.25); return
            case 53: isVisualizingArt = false; return
            case 15: visMode = visMode == .random ? .single : .random; return
            case 8:
                if visMode == .cycle { visMode = .single; cycleTimer?.invalidate() }
                else { visMode = .cycle; startCycleTimer() }
                return
            case 3: window?.toggleFullScreen(nil); return
            default: break
            }
        }
        
        if isArtOnlyMode && !isVisualizingArt && event.keyCode == 53 { isArtOnlyMode = false; return }
        
        switch event.keyCode {
        case 36: // Enter
            if browseMode == .search && !searchQuery.isEmpty {
                loadDataForCurrentMode()
            } else if event.modifierFlags.contains(.shift) {
                playNextSelected()
            } else if event.modifierFlags.contains(.option) {
                addSelectedToQueue()
            } else {
                if let index = selectedIndices.first, index < displayItems.count { handleDoubleClick(on: displayItems[index]) }
            }
        case 124: // Right Arrow — expand or move into first child
            if let index = selectedIndices.first, index < displayItems.count {
                let item = displayItems[index]
                if item.hasChildren {
                    if isExpanded(item) {
                        // Move to first child
                        let nextIdx = index + 1
                        if nextIdx < displayItems.count {
                            selectedIndices = [nextIdx]; ensureVisible(index: nextIdx); loadArtworkForSelection(); needsDisplay = true
                        }
                    } else {
                        toggleExpand(item); needsDisplay = true
                    }
                }
            }
        case 123: // Left Arrow — collapse or jump to parent
            if let index = selectedIndices.first, index < displayItems.count {
                let item = displayItems[index]
                if isExpanded(item) {
                    toggleExpand(item); needsDisplay = true
                } else if item.indentLevel > 0 {
                    // Scan backward for parent (first item with indentLevel == current - 1, skipping .header)
                    let parentLevel = item.indentLevel - 1
                    var parentIdx: Int? = nil
                    for i in stride(from: index - 1, through: 0, by: -1) {
                        let candidate = displayItems[i]
                        if case .header = candidate.type { continue }
                        if candidate.indentLevel == parentLevel { parentIdx = i; break }
                    }
                    if let p = parentIdx {
                        selectedIndices = [p]; ensureVisible(index: p); loadArtworkForSelection(); needsDisplay = true
                    }
                }
            }
        case 48: // Tab — cycle browse tabs
            let allModes = ModernBrowseMode.allCases
            // Treat .folders as .plists for tab cycling (they occupy the same slot)
            let effectiveMode = browseMode == .folders ? .plists : browseMode
            if let currentIdx = allModes.firstIndex(of: effectiveMode) {
                let shift = event.modifierFlags.contains(.shift)
                let nextIdx = shift
                    ? (currentIdx - 1 + allModes.count) % allModes.count
                    : (currentIdx + 1) % allModes.count
                let nextMode = allModes[nextIdx]
                browseMode = nextMode == .plists ? effectivePlistsSlotMode : nextMode
                selectedIndices.removeAll(); scrollOffset = 0
                loadDataForCurrentMode()
            }
        case 49: // Space — search input when searching, otherwise play/pause
            if browseMode == .search {
                if let chars = event.characters, !chars.isEmpty {
                    searchQuery += chars; needsDisplay = true
                }
            } else if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.toggleVideoPlayPause()
            } else if WindowManager.shared.audioEngine.state == .playing {
                WindowManager.shared.audioEngine.pause()
            } else {
                WindowManager.shared.audioEngine.play()
            }
        case 125: // Down
            if let maxIndex = selectedIndices.max(), maxIndex < displayItems.count - 1 {
                selectedIndices = [maxIndex + 1]; ensureVisible(index: maxIndex + 1); loadArtworkForSelection(); needsDisplay = true
            }
        case 126: // Up
            if let minIndex = selectedIndices.min(), minIndex > 0 {
                selectedIndices = [minIndex - 1]; ensureVisible(index: minIndex - 1); loadArtworkForSelection(); needsDisplay = true
            }
        default:
            if browseMode == .search, let chars = event.characters, !chars.isEmpty {
                if event.keyCode == 51 {
                    if !searchQuery.isEmpty { searchQuery.removeLast(); needsDisplay = true }
                } else if chars.rangeOfCharacter(from: .alphanumerics) != nil ||
                          chars.rangeOfCharacter(from: .whitespaces) != nil {
                    searchQuery += chars; needsDisplay = true
                }
            } else if browseMode != .search, let chars = event.characters, !chars.isEmpty {
                if event.keyCode == 53 { // Escape — clear type-ahead
                    typeAheadQuery = ""; typeAheadTimer?.invalidate(); typeAheadTimer = nil; needsDisplay = true
                } else if event.keyCode == 51 { // Backspace
                    if !typeAheadQuery.isEmpty {
                        typeAheadQuery.removeLast()
                        jumpToTypeAhead()
                    }
                } else if chars.rangeOfCharacter(from: .alphanumerics) != nil ||
                          chars.rangeOfCharacter(from: .whitespaces) != nil {
                    typeAheadQuery += chars
                    jumpToTypeAhead()
                }
            }
        }
    }
    
    private func ensureVisible(index: Int) {
        var contentTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let listHeight = contentTopY - Layout.statusBarHeight
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        let effectiveHeight = listHeight - (hasColumns ? columnHeaderHeight : 0)

        let itemTop = CGFloat(index) * itemHeight
        let itemBottom = itemTop + itemHeight

        if itemTop < scrollOffset { scrollOffset = itemTop }
        else if itemBottom > scrollOffset + effectiveHeight { scrollOffset = itemBottom - effectiveHeight }
    }

    /// Returns true if title matches the typeahead query, checking both the display form
    /// and the canonical form for "Surname, Article" style names (e.g. "Atlas Moth, The" → "The Atlas Moth").
    private func titleMatchesTypeAhead(_ title: String, query: String) -> Bool {
        if title.lowercased().hasPrefix(query) { return true }
        // Also match after stripping leading articles so "The Beatles" matches "beat".
        let normalized = LibraryTextSorter.normalized(title, ignoreLeadingArticles: true).lowercased()
        if normalized.hasPrefix(query) { return true }
        return false
    }

    private func jumpToTypeAhead() {
        let query = typeAheadQuery.lowercased()
        guard !query.isEmpty else { return }
        if let idx = displayItems.firstIndex(where: { titleMatchesTypeAhead($0.title, query: query) }) {
            selectedIndices = [idx]; ensureVisible(index: idx); loadArtworkForSelection(); needsDisplay = true
        }
        typeAheadTimer?.invalidate()
        typeAheadTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.typeAheadQuery = ""
        }
    }

    private func applyPendingArtistScroll() {
        guard let artistId = pendingScrollToArtistId else { return }
        let name = pendingScrollToArtistName ?? ""
        pendingScrollAttempts += 1
        let idx = pendingArtistIndex(artistId: artistId, name: name)
        if let idx = idx {
            selectedIndices = [idx]
            ensureVisible(index: idx)
            pendingScrollToArtistId = nil
            pendingScrollToArtistName = nil
            pendingScrollAttempts = 0
            pendingArtistLoadUnfiltered = false
            needsDisplay = true
        } else {
            if pendingScrollAttempts >= 3 {
                pendingScrollToArtistId = nil
                pendingScrollToArtistName = nil
                pendingScrollAttempts = 0
                pendingArtistLoadUnfiltered = false
            }
        }
    }

    private func pendingArtistIndex(artistId: String, name: String) -> Int? {
        let titleMatch = !name.isEmpty ? displayItems.firstIndex { item in
            isArtistRow(item) && item.title.caseInsensitiveCompare(name) == .orderedSame
        } : nil
        return titleMatch ?? displayItems.firstIndex { item in
            isArtistRow(item) && item.id == artistId
        }
    }

    private func isArtistRow(_ item: ModernDisplayItem) -> Bool {
        switch item.type {
        case .artist, .localArtist, .subsonicArtist, .jellyfinArtist, .embyArtist:
            return true
        default:
            return false
        }
    }

    // MARK: - Drag and Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return [] }
        return LocalFileDiscovery.hasSupportedDropContent(items, includeVideo: false, includePlaylists: true) ? .copy : []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return false }
        var fileURLs: [URL] = []
        var processedDirectories = false
        for url in items {
            if LocalFileDiscovery.isDirectory(url) {
                MediaLibrary.shared.addWatchFolder(url)
                MediaLibrary.shared.scanFolder(url)
                processedDirectories = true
            } else if LocalFileDiscovery.isSupportedAudioFile(url) {
                fileURLs.append(url)
            }
        }
        if !fileURLs.isEmpty {
            MediaLibrary.shared.addTracks(urls: fileURLs)
            if case .plex = currentSource { currentSource = .local }
        }
        return !fileURLs.isEmpty || processedDirectories
    }
    
    // MARK: - Server Bar Click Handling
    
    private func handleServerBarClick(at point: NSPoint, event: NSEvent) {
        let m = ModernSkinElements.sizeMultiplier
        let barRect = NSRect(x: Layout.borderWidth, y: topChromeBottomY - Layout.serverBarHeight,
                            width: bounds.width - Layout.borderWidth * 2, height: Layout.serverBarHeight)
        let relativeX = point.x - barRect.minX
        let barWidth = barRect.width
        
        let refreshZoneStart = barWidth - 30 * m
        if relativeX >= refreshZoneStart { handleRefreshClick(); return }
        
        // ART toggle - match drawn button positions
        let skin = currentSkin()
        let font = skin.sideWindowFont(size: 11)
        let fontAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let artTextWidth = "ART".size(withAttributes: fontAttrs).width
        let artBtnWidth = artTextWidth + 16 * m
        let artZoneStart = refreshZoneStart - 12 * m - artBtnWidth
        let artZoneEnd = artZoneStart + artBtnWidth
        if currentArtwork != nil && relativeX >= artZoneStart && relativeX <= artZoneEnd {
            isArtOnlyMode.toggle(); return
        }
        
        // VIS button - match drawn button positions
        if isArtOnlyMode && currentArtwork != nil {
            let visTextWidth = "VIS".size(withAttributes: fontAttrs).width
            let visBtnWidth = visTextWidth + 16 * m
            let visZoneStart = artZoneStart - 8 * m - visBtnWidth
            let visZoneEnd = visZoneStart + visBtnWidth
            if relativeX >= visZoneStart && relativeX <= visZoneEnd { toggleVisualization(); return }
        }
        
        // RATE button click (star area in art-only mode)
        if !rateButtonRect.isEmpty {
            let rateRelativeStart = rateButtonRect.minX - barRect.minX
            let rateRelativeEnd = rateButtonRect.maxX - barRect.minX
            if relativeX >= rateRelativeStart && relativeX <= rateRelativeEnd {
                showRatingOverlay(); return
            }
        }
        
        switch currentSource {
        case .local:
            let localNameWidth = "Local Files".size(withAttributes: fontAttrs).width
            let sourcePrefix = "Source: ".size(withAttributes: fontAttrs).width + 4 * m
            let sourceZoneEnd = sourcePrefix + localNameWidth
            let addZoneStart = sourceZoneEnd + 28 * m
            let addZoneEnd = addZoneStart + 50 * m
            if relativeX >= addZoneStart && relativeX <= addZoneEnd { showAddFilesMenu(at: event) }
            else if relativeX < sourceZoneEnd { showSourceMenu(at: event) }
        case .plex:
            let sourcePrefix = "Source: ".size(withAttributes: fontAttrs).width + 4 * m
            let maxServerWidth: CGFloat = 100 * m
            let serverZoneEnd = sourcePrefix + maxServerWidth
            let libLabelWidth = "Lib:".size(withAttributes: fontAttrs).width + 4 * m
            let libraryZoneStart = serverZoneEnd + 12 * m
            let maxLibraryWidth: CGFloat = 80 * m
            let libraryZoneEnd = libraryZoneStart + libLabelWidth + maxLibraryWidth
            if relativeX >= libraryZoneStart && relativeX <= libraryZoneEnd { showLibraryMenu(at: event) }
            else if relativeX < serverZoneEnd { showSourceMenu(at: event) }
        case .subsonic:
            let sourcePrefix = "Source: ".size(withAttributes: fontAttrs).width + 4 * m
            let maxServerWidth: CGFloat = 100 * m
            let serverZoneEnd = sourcePrefix + maxServerWidth
            let libLabelWidth = "Lib:".size(withAttributes: fontAttrs).width + 4 * m
            let libraryZoneStart = serverZoneEnd + 12 * m
            let maxLibraryWidth: CGFloat = 80 * m
            let libraryZoneEnd = libraryZoneStart + libLabelWidth + maxLibraryWidth
            if relativeX >= libraryZoneStart && relativeX <= libraryZoneEnd { showSubsonicFolderMenu(at: event) }
            else if relativeX < serverZoneEnd { showSourceMenu(at: event) }
        case .jellyfin:
            let sourcePrefix = "Source: ".size(withAttributes: fontAttrs).width + 4 * m
            let maxServerWidth: CGFloat = 100 * m
            let serverZoneEnd = sourcePrefix + maxServerWidth
            let libLabelWidth = "Lib:".size(withAttributes: fontAttrs).width + 4 * m
            let libraryZoneStart = serverZoneEnd + 12 * m
            let maxLibraryWidth: CGFloat = 80 * m
            let libraryZoneEnd = libraryZoneStart + libLabelWidth + maxLibraryWidth
            if relativeX >= libraryZoneStart && relativeX <= libraryZoneEnd {
                if browseMode.isVideoMode { showJellyfinVideoLibraryMenu(at: event) }
                else { showJellyfinLibraryMenu(at: event) }
            } else if relativeX < serverZoneEnd { showSourceMenu(at: event) }
        case .emby:
            let sourcePrefix = "Source: ".size(withAttributes: fontAttrs).width + 4 * m
            let maxServerWidth: CGFloat = 100 * m
            let serverZoneEnd = sourcePrefix + maxServerWidth
            let libLabelWidth = "Lib:".size(withAttributes: fontAttrs).width + 4 * m
            let libraryZoneStart = serverZoneEnd + 12 * m
            let maxLibraryWidth: CGFloat = 80 * m
            let libraryZoneEnd = libraryZoneStart + libLabelWidth + maxLibraryWidth
            if relativeX >= libraryZoneStart && relativeX <= libraryZoneEnd {
                if browseMode.isVideoMode { showEmbyVideoLibraryMenu(at: event) }
                else { showEmbyLibraryMenu(at: event) }
            } else if relativeX < serverZoneEnd { showSourceMenu(at: event) }
        case .radio:
            let radioNameWidth = "Internet Radio".size(withAttributes: fontAttrs).width
            let sourcePrefix = "Source: ".size(withAttributes: fontAttrs).width + 4 * m
            let sourceZoneEnd = sourcePrefix + radioNameWidth
            let addZoneStart = sourceZoneEnd + 28 * m
            let addZoneEnd = addZoneStart + 50 * m
            if relativeX >= addZoneStart && relativeX <= addZoneEnd { showRadioAddMenu(at: event) }
            else if relativeX < sourceZoneEnd { showSourceMenu(at: event) }
        case .youtube:
            let ytNameWidth = "YouTube".size(withAttributes: fontAttrs).width
            let sourcePrefix = "Source: ".size(withAttributes: fontAttrs).width + 4 * m
            let sourceZoneEnd = sourcePrefix + ytNameWidth
            let addZoneStart = sourceZoneEnd + 28 * m
            let addZoneEnd = addZoneStart + 50 * m
            if relativeX >= addZoneStart && relativeX <= addZoneEnd { showYouTubeAddMenu(at: event) }
            else if relativeX < sourceZoneEnd { showSourceMenu(at: event) }
        }
    }

    private func handleRefreshClick() {
        if browseMode.isHistoryMode {
            historyAgent.scheduleRefresh()
            return
        }
        if case .youtube = currentSource {
            switch browseMode {
            case .radio:
                if radioSlotShowsChannels { loadYouTubeChannels() }
                else { loadRadioStations() }
            case .search:
                loadRadioSearchResults()
            default:
                isLoading = false
                errorMessage = nil
                stopLoadingAnimation()
                displayItems = []
                needsDisplay = true
            }
            return
        }
        if case .radio = currentSource {
            switch browseMode {
            case .radio:
                loadRadioStations()
            case .search:
                loadRadioSearchResults()
            case .history:
                break
            default:
                break
            }
            return
        }
        if browseMode == .radio {
            if case .plex = currentSource { loadPlexRadioStations() }
            else if case .subsonic = currentSource { loadSubsonicRadioStations() }
            else if case .jellyfin = currentSource { loadJellyfinRadioStations() }
            else if case .emby = currentSource { loadEmbyRadioStations() }
            else if case .local = currentSource { loadLocalRadioStations() }
            return
        }
        switch currentSource {
        case .local: MediaLibrary.shared.rescanWatchFolders(); loadLocalData()
        case .plex: refreshData()
        case .subsonic:
            // Cancel any in-flight load task first to prevent race conditions
            subsonicLoadTask?.cancel()
            subsonicLoadTask = nil
            SubsonicManager.shared.clearCachedContent()
            // Show loading state immediately, then preload in parallel and refresh
            isLoading = true; errorMessage = nil; displayItems = []; startLoadingAnimation(); needsDisplay = true
            Task { @MainActor [weak self] in
                await SubsonicManager.shared.preloadLibraryContent()
                guard let self = self, case .subsonic = self.currentSource else { return }
                self.refreshData()
            }
        case .jellyfin:
            // Cancel any in-flight load task first to prevent race conditions
            jellyfinLoadTask?.cancel()
            jellyfinLoadTask = nil
            jellyfinAlbumWarmTask?.cancel()
            jellyfinAlbumWarmTask = nil
            JellyfinManager.shared.clearCachedContent()
            // Show loading state immediately, then preload in parallel and refresh
            isLoading = true; errorMessage = nil; displayItems = []; startLoadingAnimation(); needsDisplay = true
            Task { @MainActor [weak self] in
                await JellyfinManager.shared.preloadLibraryContent()
                guard let self = self, case .jellyfin = self.currentSource else { return }
                self.refreshData()
            }
        case .emby:
            // Cancel any in-flight load task first to prevent race conditions
            embyExpandTask?.cancel()
            embyExpandTask = nil
            EmbyManager.shared.clearCachedContent()
            // Show loading state immediately, then preload in parallel and refresh
            isLoading = true; errorMessage = nil; displayItems = []; startLoadingAnimation(); needsDisplay = true
            Task { @MainActor [weak self] in
                await EmbyManager.shared.preloadLibraryContent()
                guard let self = self, case .emby = self.currentSource else { return }
                self.refreshData()
            }
        case .radio: break
        case .youtube: loadYouTubeChannels()
        }
    }
    
    // MARK: - Alphabet Click
    
    private func handleAlphabetClick(at point: NSPoint) {
        var contentTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let listHeight = contentTopY - Layout.statusBarHeight
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        let effectiveHeight = listHeight - (hasColumns ? columnHeaderHeight : 0)
        let alphabetTopY = Layout.statusBarHeight + effectiveHeight

        // Bottom-left: # at top, Z at bottom
        let relativeFromTop = alphabetTopY - point.y
        let letterCount = CGFloat(alphabetLetters.count)
        let letterHeight = effectiveHeight / letterCount
        let letterIndex = Int(relativeFromTop / letterHeight)

        guard letterIndex >= 0 && letterIndex < alphabetLetters.count else { return }
        scrollToLetter(alphabetLetters[letterIndex])
    }
    
    private func sortLetter(for title: String) -> String {
        let sortTitle = LibraryTextSorter.normalized(title, ignoreLeadingArticles: true).uppercased()
        guard let firstChar = sortTitle.first else { return "#" }
        return firstChar.isLetter ? String(firstChar) : "#"
    }

    /// Returns the sort letter for a display item, using the server's index letter for Subsonic artists.
    private func effectiveSortLetter(for item: ModernDisplayItem) -> String {
        if case .subsonicArtist(let artist) = item.type,
           let raw = artist.indexLetter,
           let first = raw.trimmingCharacters(in: .whitespaces).first {
            return String(first).uppercased()
        }
        return sortLetter(for: item.title)
    }

    private func scrollToLetter(_ letter: String) {
        if case .local = currentSource {
            switch browseMode {
            case .artists:
                if let dbOffset = localArtistLetterOffsets[letter] {
                    localArtistPageOffset = dbOffset
                    buildLocalArtistItems()
                    scrollOffset = 0
                    needsDisplay = true
                }
                return
            case .albums:
                if let dbOffset = localAlbumLetterOffsets[letter] {
                    localAlbumPageOffset = dbOffset
                    buildLocalAlbumItems()
                    scrollOffset = 0
                    needsDisplay = true
                }
                return
            default:
                break
            }
        }
        for (index, item) in displayItems.enumerated() {
            if effectiveSortLetter(for: item) == letter {
                var contentTopY = topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
                if browseMode == .search { contentTopY -= Layout.searchBarHeight }
                let listHeight = contentTopY - Layout.statusBarHeight
                let hasColumns = displayItems.contains { columnsForItem($0) != nil }
                let effectiveHeight = listHeight - (hasColumns ? columnHeaderHeight : 0)
                let maxScroll = max(0, CGFloat(displayItems.count) * itemHeight - effectiveHeight)
                scrollOffset = min(maxScroll, CGFloat(index) * itemHeight)
                selectedIndices = [index]; needsDisplay = true; return
            }
        }
    }
    
    // MARK: - List Click
    
    private func handleListClick(at index: Int, event: NSEvent, point: NSPoint) {
        let item = displayItems[index]

        // In search mode, clicking an artist navigates to the Artists tab
        if browseMode == .search {
            switch item.type {
            case .artist(let artist):
                navigateToArtistFromSearch(id: artist.id, name: artist.title)
                return
            case .subsonicArtist(let artist):
                navigateToArtistFromSearch(id: artist.id, name: artist.name)
                return
            case .jellyfinArtist(let artist):
                navigateToArtistFromSearch(id: artist.id, name: artist.name)
                return
            case .embyArtist(let artist):
                navigateToArtistFromSearch(id: artist.id, name: artist.name)
                return
            case .localArtist(let artist):
                navigateToArtistFromSearch(id: item.id, name: artist.name)
                return
            default: break
            }
        }

        if case .radioFolder(let folder) = item.type {
            let indent = CGFloat(item.indentLevel) * 16
            let inExpandZone = point.x < Layout.borderWidth + indent + 20

            if folder.hasChildren && inExpandZone {
                toggleExpand(item)
                return
            }

            if folder.hasChildren && event.clickCount == 2 {
                toggleExpand(item)
                return
            }

            if let updatedIndex = displayItems.firstIndex(where: { $0.id == folder.id }) {
                selectedIndices = [updatedIndex]
            } else {
                selectedIndices = [index]
            }
            needsDisplay = true
            return
        }

        if let clickedStar = hitTestInternetRadioRating(at: point, itemIndex: index),
           case .radioStation(let station) = item.type {
            let currentRating = RadioManager.shared.rating(for: station)
            let targetRating = currentRating == clickedStar ? 0 : clickedStar
            RadioManager.shared.setRating(targetRating, for: station)
            selectedIndices = [index]
            needsDisplay = true
            return
        }

        if item.hasChildren {
            let indent = CGFloat(item.indentLevel) * 16
            let inExpandZone = point.x < Layout.borderWidth + indent + 20
            if item.type.isAlbumItem {
                if event.clickCount == 1 { toggleExpand(item) }
                // Fall through to selection
            } else if inExpandZone {
                toggleExpand(item); return
            }
        }

        if event.modifierFlags.contains(.shift) {
            if let lastSelected = selectedIndices.max() {
                for i in min(lastSelected, index)...max(lastSelected, index) { selectedIndices.insert(i) }
            } else { selectedIndices.insert(index) }
        } else if event.modifierFlags.contains(.command) {
            if selectedIndices.contains(index) { selectedIndices.remove(index) }
            else { selectedIndices.insert(index) }
        } else {
            selectedIndices = [index]
            if browseMode == .search,
               case .radioStation(let station) = item.type,
               event.clickCount == 1 {
                playRadioStation(station)
            } else {
                loadArtworkForSelection()
            }
        }
        
        if event.clickCount == 2 { handleDoubleClick(on: item) }
        needsDisplay = true
    }
    
    // MARK: - Menus
    
    private func showSourceMenu(at event: NSEvent) {
        let menu = NSMenu()
        let localItem = NSMenuItem(title: "Local Files", action: #selector(selectLocalSource), keyEquivalent: "")
        localItem.target = self; if case .local = currentSource { localItem.state = .on }
        menu.addItem(localItem)
        menu.addItem(NSMenuItem.separator())
        let radioItem = NSMenuItem(title: "Internet Radio", action: #selector(selectRadioSource), keyEquivalent: "")
        radioItem.target = self; if case .radio = currentSource { radioItem.state = .on }
        menu.addItem(radioItem)
        menu.addItem(NSMenuItem.separator())
        let youtubeItem = NSMenuItem(title: "YouTube", action: #selector(selectYouTubeSource), keyEquivalent: "")
        youtubeItem.target = self; if case .youtube = currentSource { youtubeItem.state = .on }
        menu.addItem(youtubeItem)

        if case .local = currentSource {
            let store = MediaLibraryStore.shared
            let trackCount = store.trackCount()
            let movieCount = store.movieCount()
            let episodeCount = store.episodeCount()
            let totalLocalItems = trackCount + movieCount + episodeCount
            menu.addItem(NSMenuItem.separator())
            let manageFoldersItem = NSMenuItem(title: "Manage Folders...", action: #selector(manageWatchFolders), keyEquivalent: "")
            manageFoldersItem.target = self; menu.addItem(manageFoldersItem)
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear Local Library", action: nil, keyEquivalent: "")
            let clearSubmenu = NSMenu()

            let clearMusicItem = NSMenuItem(title: "Clear Music...", action: #selector(clearLocalMusicFromSourceMenu), keyEquivalent: "")
            clearMusicItem.target = self
            clearMusicItem.isEnabled = trackCount > 0
            clearSubmenu.addItem(clearMusicItem)

            let clearMoviesItem = NSMenuItem(title: "Clear Movies...", action: #selector(clearLocalMoviesFromSourceMenu), keyEquivalent: "")
            clearMoviesItem.target = self
            clearMoviesItem.isEnabled = movieCount > 0
            clearSubmenu.addItem(clearMoviesItem)

            let clearTVItem = NSMenuItem(title: "Clear TV...", action: #selector(clearLocalTVFromSourceMenu), keyEquivalent: "")
            clearTVItem.target = self
            clearTVItem.isEnabled = episodeCount > 0
            clearSubmenu.addItem(clearTVItem)

            clearSubmenu.addItem(NSMenuItem.separator())

            let clearAllItem = NSMenuItem(title: "Clear Everything...", action: #selector(clearLocalLibraryFromSourceMenu), keyEquivalent: "")
            clearAllItem.target = self
            clearAllItem.isEnabled = totalLocalItems > 0
            clearSubmenu.addItem(clearAllItem)

            clearItem.submenu = clearSubmenu
            menu.addItem(clearItem)
        }

        menu.addItem(NSMenuItem.separator())
        for server in PlexManager.shared.servers {
            let item = NSMenuItem(title: server.name, action: #selector(selectPlexServer(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = server.id
            if case .plex(let id) = currentSource, id == server.id { item.state = .on }
            menu.addItem(item)
        }
        if PlexManager.shared.servers.isEmpty && !PlexManager.shared.isLinked {
            let linkItem = NSMenuItem(title: "Link Plex Account...", action: #selector(linkPlexAccount), keyEquivalent: "")
            linkItem.target = self; menu.addItem(linkItem)
        }
        if !SubsonicManager.shared.servers.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for server in SubsonicManager.shared.servers {
                let item = NSMenuItem(title: "🎵 \(server.name)", action: #selector(selectSubsonicServer(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = server.id
                if case .subsonic(let id) = currentSource, id == server.id { item.state = .on }
                menu.addItem(item)
            }
        }
        if !JellyfinManager.shared.servers.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for server in JellyfinManager.shared.servers {
                let item = NSMenuItem(title: "🟣 \(server.name)", action: #selector(selectJellyfinServer(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = server.id
                if case .jellyfin(let id) = currentSource, id == server.id { item.state = .on }
                menu.addItem(item)
            }
        }
        if !EmbyManager.shared.servers.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for server in EmbyManager.shared.servers {
                let item = NSMenuItem(title: "🔵 \(server.name)", action: #selector(selectEmbyServer(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = server.id
                if case .emby(let id) = currentSource, id == server.id { item.state = .on }
                menu.addItem(item)
            }
        }
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    private func showLibraryMenu(at event: NSEvent) {
        let menu = NSMenu()
        let libraries = PlexManager.shared.availableLibraries
        let currentLibraryId = PlexManager.shared.currentLibrary?.id
        for library in libraries {
            let typeLabel: String
            if library.isMusicLibrary { typeLabel = "Music" }
            else if library.isMovieLibrary { typeLabel = "Movies" }
            else if library.isShowLibrary { typeLabel = "TV Shows" }
            else { typeLabel = library.type }
            let item = NSMenuItem(title: "\(library.title) (\(typeLabel))", action: #selector(selectLibrary(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = library
            item.state = library.id == currentLibraryId ? .on : .off
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func showJellyfinLibraryMenu(at event: NSEvent) {
        let menu = NSMenu()
        let libraries = JellyfinManager.shared.musicLibraries
        let currentId = JellyfinManager.shared.currentMusicLibrary?.id
        let allItem = NSMenuItem(title: "All Libraries", action: #selector(selectJellyfinMusicLibrary(_:)), keyEquivalent: "")
        allItem.target = self; allItem.representedObject = Optional<JellyfinMusicLibrary>.none as Any
        allItem.state = currentId == nil ? .on : .off
        menu.addItem(allItem)
        if !libraries.isEmpty { menu.addItem(NSMenuItem.separator()) }
        for library in libraries {
            let item = NSMenuItem(title: "\(library.name) (Music)", action: #selector(selectJellyfinMusicLibrary(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = library
            item.state = library.id == currentId ? .on : .off
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func showJellyfinVideoLibraryMenu(at event: NSEvent) {
        let menu = NSMenu()
        let libraries = JellyfinManager.shared.videoLibraries
        let currentMovieId = JellyfinManager.shared.currentMovieLibrary?.id
        let currentShowId = JellyfinManager.shared.currentShowLibrary?.id
        let activeId = browseMode == .shows ? currentShowId : currentMovieId
        let allItem = NSMenuItem(title: "All Libraries", action: #selector(selectJellyfinVideoLibraryFromBrowser(_:)), keyEquivalent: "")
        allItem.target = self; allItem.representedObject = Optional<JellyfinMusicLibrary>.none as Any
        allItem.state = activeId == nil ? .on : .off
        menu.addItem(allItem)
        if !libraries.isEmpty { menu.addItem(NSMenuItem.separator()) }
        for library in libraries {
            let typeLabel = library.collectionType == "tvshows" ? "TV Shows" : "Movies"
            let item = NSMenuItem(title: "\(library.name) (\(typeLabel))", action: #selector(selectJellyfinVideoLibraryFromBrowser(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = library
            item.state = library.id == activeId ? .on : .off
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func showEmbyLibraryMenu(at event: NSEvent) {
        let menu = NSMenu()
        let libraries = EmbyManager.shared.musicLibraries
        let currentId = EmbyManager.shared.currentMusicLibrary?.id
        let allItem = NSMenuItem(title: "All Libraries", action: #selector(selectEmbyMusicLibraryFromBrowser(_:)), keyEquivalent: "")
        allItem.target = self; allItem.representedObject = Optional<EmbyMusicLibrary>.none as Any
        allItem.state = currentId == nil ? .on : .off
        menu.addItem(allItem)
        if !libraries.isEmpty { menu.addItem(NSMenuItem.separator()) }
        for library in libraries {
            let item = NSMenuItem(title: "\(library.name) (Music)", action: #selector(selectEmbyMusicLibraryFromBrowser(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = library
            item.state = library.id == currentId ? .on : .off
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func showEmbyVideoLibraryMenu(at event: NSEvent) {
        let menu = NSMenu()
        let libraries = EmbyManager.shared.videoLibraries
        let currentMovieId = EmbyManager.shared.currentMovieLibrary?.id
        let currentShowId = EmbyManager.shared.currentShowLibrary?.id
        let activeId = browseMode == .shows ? currentShowId : currentMovieId
        let allItem = NSMenuItem(title: "All Libraries", action: #selector(selectEmbyVideoLibraryFromBrowser(_:)), keyEquivalent: "")
        allItem.target = self; allItem.representedObject = Optional<EmbyMusicLibrary>.none as Any
        allItem.state = activeId == nil ? .on : .off
        menu.addItem(allItem)
        if !libraries.isEmpty { menu.addItem(NSMenuItem.separator()) }
        for library in libraries {
            let typeLabel = library.collectionType == "tvshows" ? "TV Shows" : "Movies"
            let item = NSMenuItem(title: "\(library.name) (\(typeLabel))", action: #selector(selectEmbyVideoLibraryFromBrowser(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = library
            item.state = library.id == activeId ? .on : .off
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func showSubsonicFolderMenu(at event: NSEvent) {
        let menu = NSMenu()
        let folders = SubsonicManager.shared.musicFolders
        let currentId = SubsonicManager.shared.currentMusicFolder?.id
        let allItem = NSMenuItem(title: "All Folders", action: #selector(selectSubsonicMusicFolder(_:)), keyEquivalent: "")
        allItem.target = self; allItem.representedObject = Optional<SubsonicMusicFolder>.none as Any
        allItem.state = currentId == nil ? .on : .off
        menu.addItem(allItem)
        if !folders.isEmpty { menu.addItem(NSMenuItem.separator()) }
        for folder in folders {
            let item = NSMenuItem(title: folder.name, action: #selector(selectSubsonicMusicFolder(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = folder
            item.state = folder.id == currentId ? .on : .off
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func showSortMenu(at windowPoint: NSPoint) {
        let menu = NSMenu()
        for option in ModernBrowserSortOption.allCases {
            let item = NSMenuItem(title: option.rawValue, action: #selector(selectSortOption(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = option
            if option == currentSort { item.state = .on }
            menu.addItem(item)
        }
        let menuLocation = NSPoint(x: windowPoint.x, y: windowPoint.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    private func showAddFilesMenu(at event: NSEvent) {
        let menu = NSMenu()
        let addFilesItem = NSMenuItem(title: "Add Files...", action: #selector(addFiles), keyEquivalent: "")
        addFilesItem.target = self; menu.addItem(addFilesItem)
        let addVideoFilesItem = NSMenuItem(title: "Add Video Files...", action: #selector(addVideoFiles), keyEquivalent: "")
        addVideoFilesItem.target = self; menu.addItem(addVideoFilesItem)
        let addFolderItem = NSMenuItem(title: "Add Folder...", action: #selector(addWatchFolder), keyEquivalent: "")
        addFolderItem.target = self; menu.addItem(addFolderItem)
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    private func showRadioAddMenu(at event: NSEvent) {
        let menu = NSMenu()
        let addItem = NSMenuItem(title: "Add Station...", action: #selector(showAddRadioStationDialog), keyEquivalent: "")
        addItem.target = self; menu.addItem(addItem)
        let addFolderItem = NSMenuItem(title: "New Folder...", action: #selector(showCreateRadioFolderDialog), keyEquivalent: "")
        addFolderItem.target = self; menu.addItem(addFolderItem)
        menu.addItem(NSMenuItem.separator())
        let addDefaultsItem = NSMenuItem(title: "Add Missing Defaults", action: #selector(addMissingRadioDefaults), keyEquivalent: "")
        addDefaultsItem.target = self; menu.addItem(addDefaultsItem)
        let resetItem = NSMenuItem(title: "Reset to Defaults", action: #selector(resetRadioToDefaults), keyEquivalent: "")
        resetItem.target = self; menu.addItem(resetItem)
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }

    private func promptForRadioFolderName(
        title: String,
        message: String,
        confirmTitle: String,
        defaultValue: String = ""
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.stringValue = defaultValue
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func buildRadioStationFoldersSubmenu(for station: RadioStation) -> NSMenu {
        let submenu = NSMenu()
        let folders = RadioManager.shared.userRadioFolders()
        if folders.isEmpty {
            let emptyItem = NSMenuItem(title: "No Folders", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for folder in folders {
                let item = NSMenuItem(
                    title: folder.name,
                    action: #selector(contextMenuToggleStationFolderMembership(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = RadioFolderMembershipAction(station: station, folderID: folder.id)
                item.state = RadioManager.shared.isStation(station, inUserFolderID: folder.id) ? .on : .off
                submenu.addItem(item)
            }
        }

        submenu.addItem(NSMenuItem.separator())
        let newFolderItem = NSMenuItem(
            title: "New Folder...",
            action: #selector(contextMenuCreateRadioFolderAndAddStation(_:)),
            keyEquivalent: ""
        )
        newFolderItem.target = self
        newFolderItem.representedObject = RadioFolderStationAction(station: station)
        submenu.addItem(newFolderItem)
        return submenu
    }

    private func buildRadioStationSmartFoldersSubmenu(for station: RadioStation) -> NSMenu {
        let submenu = NSMenu()

        let genreItem = NSMenuItem(title: "By Genre", action: nil, keyEquivalent: "")
        genreItem.submenu = buildRadioStationSmartGenreSubmenu(for: station)
        submenu.addItem(genreItem)

        let regionItem = NSMenuItem(title: "By Region", action: nil, keyEquivalent: "")
        regionItem.submenu = buildRadioStationSmartRegionSubmenu(for: station)
        submenu.addItem(regionItem)

        return submenu
    }

    private func buildRadioStationSmartGenreSubmenu(for station: RadioStation) -> NSMenu {
        let submenu = NSMenu()
        let manager = RadioManager.shared
        let baseGenre = (station.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Unknown"
            : (station.genre ?? "Unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        let overrideGenre = manager.smartGenreOverride(for: station)
        let effectiveGenre = manager.normalizedGenre(for: station)

        let autoItem = NSMenuItem(
            title: "Use Station Genre (\(baseGenre))",
            action: #selector(contextMenuAssignStationSmartGenre(_:)),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.representedObject = RadioSmartGenreAction(station: station, genre: nil)
        autoItem.state = overrideGenre == nil ? .on : .off
        submenu.addItem(autoItem)
        submenu.addItem(NSMenuItem.separator())

        for genre in manager.smartGenreOptions(including: station) {
            let item = NSMenuItem(
                title: genre,
                action: #selector(contextMenuAssignStationSmartGenre(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = RadioSmartGenreAction(station: station, genre: genre)
            item.state = effectiveGenre.localizedCaseInsensitiveCompare(genre) == .orderedSame ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func buildRadioStationSmartRegionSubmenu(for station: RadioStation) -> NSMenu {
        let submenu = NSMenu()
        let manager = RadioManager.shared
        let baseRegion = manager.autoRegion(for: station)
        let overrideRegion = manager.smartRegionOverride(for: station)
        let effectiveRegion = manager.effectiveRegion(for: station)

        let autoItem = NSMenuItem(
            title: "Use Auto Region (\(baseRegion))",
            action: #selector(contextMenuAssignStationSmartRegion(_:)),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.representedObject = RadioSmartRegionAction(station: station, region: nil)
        autoItem.state = overrideRegion == nil ? .on : .off
        submenu.addItem(autoItem)
        submenu.addItem(NSMenuItem.separator())

        for region in manager.smartRegionOptions(including: station) {
            let item = NSMenuItem(
                title: region,
                action: #selector(contextMenuAssignStationSmartRegion(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = RadioSmartRegionAction(station: station, region: region)
            item.state = effectiveRegion.localizedCaseInsensitiveCompare(region) == .orderedSame ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }
    
    /// Appends grouped effect submenus to `menu`. Each item is checked when it
    /// matches `currentVisEffect`; bullet-marked when it matches the saved default.
    private func buildVisEffectGroupSubmenus(into menu: NSMenu) {
        let savedDefault = UserDefaults.standard.string(forKey: "browserVisDefaultEffect")
        for group in VisEffect.groups {
            let groupItem = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: group.title)
            for effect in group.effects {
                let item = NSMenuItem(title: effect.rawValue,
                                      action: #selector(menuSelectEffect(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = effect.rawValue
                if effect == currentVisEffect {
                    item.state = .on
                } else if effect.rawValue == savedDefault {
                    item.state = .mixed
                }
                sub.addItem(item)
            }
            groupItem.submenu = sub
            menu.addItem(groupItem)
        }
    }

    private func showVisualizerMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Visualizer")
        let currentItem = NSMenuItem(title: "▶ \(currentVisEffect.rawValue)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false; menu.addItem(currentItem)
        menu.addItem(NSMenuItem.separator())
        buildVisEffectGroupSubmenus(into: menu)
        menu.addItem(NSMenuItem.separator())
        let defaultItem = NSMenuItem(title: "Set Current as Default",
                                     action: #selector(menuSetDefaultEffect),
                                     keyEquivalent: "")
        defaultItem.target = self; menu.addItem(defaultItem)
        menu.addItem(NSMenuItem.separator())
        let offItem = NSMenuItem(title: "Turn Off", action: #selector(turnOffVisualization), keyEquivalent: "")
        offItem.target = self; menu.addItem(offItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func showArtContextMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Art")
        let visItem = NSMenuItem(title: "Enable Visualization", action: #selector(enableArtVisualization), keyEquivalent: "")
        visItem.target = self; menu.addItem(visItem)

        // Visualization submenu — effect picker + set default
        let visMenuContainer = NSMenuItem(title: "Visualization", action: nil, keyEquivalent: "")
        let visSub = NSMenu(title: "Visualization")
        buildVisEffectGroupSubmenus(into: visSub)
        visSub.addItem(NSMenuItem.separator())
        let defaultItem = NSMenuItem(title: "Set Current as Default",
                                     action: #selector(menuSetDefaultEffect),
                                     keyEquivalent: "")
        defaultItem.target = self; visSub.addItem(defaultItem)
        visMenuContainer.submenu = visSub
        menu.addItem(visMenuContainer)

        // Rate submenu (when a rateable track is playing)
        if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
           currentTrack.plexRatingKey != nil || currentTrack.subsonicId != nil || currentTrack.jellyfinId != nil || currentTrack.embyId != nil || currentTrack.url.isFileURL {
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenu()
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu
            menu.addItem(rateItem)
        }

        menu.addItem(NSMenuItem.separator())
        let exitItem = NSMenuItem(title: "Exit Art View", action: #selector(exitArtView), keyEquivalent: "")
        exitItem.target = self; menu.addItem(exitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func showColumnConfigMenu(at event: NSEvent) {
        if hasInternetRadioColumns { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        for group in columnGroupsForCurrentMenu() {
            addColumnVisibilityGroup(group, to: menu)
        }
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func columnGroupsForCurrentMenu() -> [LibraryColumnVisibilityGroup] {
        if hasYouTubeColumns {
            return [.youtube]
        }
        return LibraryColumnVisibility.menuGroups(
            isArtistsMode: browseMode == .artists,
            isAlbumsMode: browseMode == .albums,
            hasTrackRows: hasTrackRows(),
            hasAlbumRows: hasAlbumRows(),
            hasArtistRows: hasArtistRows()
        )
    }

    private func addColumnVisibilityGroup(_ group: LibraryColumnVisibilityGroup, to menu: NSMenu) {
        if !menu.items.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        let header = NSMenuItem(title: group.headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let visibleIds = Set(visibleColumnIds(for: group))
        for column in allColumns(for: group) {
            let item = NSMenuItem()
            item.view = ColumnVisibilityCheckboxView(
                title: column.title,
                isChecked: column.id == "title" || visibleIds.contains(column.id),
                isEnabled: group != .youtube && column.id != "title"
            ) { [weak self] isVisible in
                self?.toggleColumnVisibility(group: group, columnId: column.id, visible: isVisible)
            }
            menu.addItem(item)
        }

        let resetItem = NSMenuItem(title: group.resetTitle, action: #selector(resetColumnGroup(_:)), keyEquivalent: "")
        resetItem.target = self
        resetItem.representedObject = group.rawValue
        menu.addItem(resetItem)
    }

    private func allColumns(for group: LibraryColumnVisibilityGroup) -> [ModernBrowserColumn] {
        switch group {
        case .artist: return ModernBrowserColumn.allArtistColumns
        case .album: return ModernBrowserColumn.allAlbumColumns
        case .track: return ModernBrowserColumn.allTrackColumns
        case .youtube: return ModernBrowserColumn.youtubeColumns
        }
    }

    private func defaultColumnIds(for group: LibraryColumnVisibilityGroup) -> [String] {
        switch group {
        case .artist: return ModernBrowserColumn.defaultArtistColumnIds
        case .album: return ModernBrowserColumn.defaultAlbumColumnIds
        case .track: return ModernBrowserColumn.defaultTrackColumnIds
        case .youtube: return ModernBrowserColumn.defaultYouTubeColumnIds
        }
    }

    private func visibleColumnIds(for group: LibraryColumnVisibilityGroup) -> [String] {
        switch group {
        case .artist: return normalizedColumnIds(visibleArtistColumnIds, allColumns: ModernBrowserColumn.allArtistColumns)
        case .album: return normalizedColumnIds(visibleAlbumColumnIds, allColumns: ModernBrowserColumn.allAlbumColumns)
        case .track: return normalizedColumnIds(visibleTrackColumnIds, allColumns: ModernBrowserColumn.allTrackColumns)
        // YouTube columns are fixed (not user-hideable); always the full set.
        case .youtube: return ModernBrowserColumn.defaultYouTubeColumnIds
        }
    }

    private func setVisibleColumnIds(_ ids: [String], for group: LibraryColumnVisibilityGroup) {
        switch group {
        case .artist:
            visibleArtistColumnIds = normalizedColumnIds(ids, allColumns: ModernBrowserColumn.allArtistColumns)
        case .album:
            visibleAlbumColumnIds = normalizedColumnIds(ids, allColumns: ModernBrowserColumn.allAlbumColumns)
        case .track:
            visibleTrackColumnIds = normalizedColumnIds(ids, allColumns: ModernBrowserColumn.allTrackColumns)
        case .youtube:
            break  // fixed column set, nothing to persist
        }
    }

    private func toggleColumnVisibility(group: LibraryColumnVisibilityGroup, columnId: String, visible: Bool) {
        guard columnId != "title" else { return }

        var ids = visibleColumnIds(for: group)
        if visible {
            if !ids.contains(columnId) {
                ids.append(columnId)
            }
        } else {
            ids.removeAll { $0 == columnId }
            if columnSortId == columnId { columnSortId = nil }
        }

        setVisibleColumnIds(ids, for: group)
        clampHorizontalScrollOffset()
        needsDisplay = true
    }
    
    @objc private func resetColumnGroup(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let group = LibraryColumnVisibilityGroup(rawValue: rawValue) else { return }

        setVisibleColumnIds(defaultColumnIds(for: group), for: group)
        let prefix = "\(group.rawValue):"
        columnWidths = columnWidths.filter { !$0.key.hasPrefix(prefix) }
        clampHorizontalScrollOffset()
        needsDisplay = true
    }
    
    private func showContextMenu(for item: ModernDisplayItem, at event: NSEvent) {
        let menu = NSMenu()
        switch item.type {
        case .track(let track):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlay(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play and Replace Queue", action: #selector(contextMenuPlayAndReplaceTrack(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = item; menu.addItem(playReplaceItem)
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self; addItem.representedObject = track; menu.addItem(addItem)
            let playNextItem = NSMenuItem(title: "Play Next", action: #selector(contextMenuPlayNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = track; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(contextMenuAddToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = track; menu.addItem(queueItem)
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenuForPlex(ratingKey: track.id)
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu; menu.addItem(rateItem)
        case .album(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayAlbum(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = album; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Album and Replace Queue", action: #selector(contextMenuPlayAlbumAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = album; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Album Next", action: #selector(contextMenuPlayAlbumNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = album; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Album to Queue", action: #selector(contextMenuAddAlbumToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = album; menu.addItem(queueItem)
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenuForPlex(ratingKey: album.id)
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu; menu.addItem(rateItem)
        case .artist(let artist):
            let playItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlayArtist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = artist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Artist and Replace Queue", action: #selector(contextMenuPlayArtistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = artist; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Artist Next", action: #selector(contextMenuPlayArtistNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = artist; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Artist to Queue", action: #selector(contextMenuAddArtistToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = artist; menu.addItem(queueItem)
            let expandItem = NSMenuItem(title: expandedArtists.contains(item.id) ? "Collapse" : "Expand",
                                         action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
        case .localTrack(let track):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayLocalTrack(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = track; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play and Replace Queue", action: #selector(contextMenuPlayLocalTrackAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = track; menu.addItem(playReplaceItem)
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddLocalTrackToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self; addItem.representedObject = track; menu.addItem(addItem)
            let playNextItem = NSMenuItem(title: "Play Next", action: #selector(contextMenuPlayLocalTrackNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = track; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(contextMenuAddLocalTrackToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = track; menu.addItem(queueItem)
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenuForLocal(trackId: track.id)
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu; menu.addItem(rateItem)
            menu.addItem(NSMenuItem.separator())
            let tagsItem = NSMenuItem(title: "Edit Tags", action: #selector(contextMenuEditTags(_:)), keyEquivalent: "")
            tagsItem.target = self; tagsItem.representedObject = track; menu.addItem(tagsItem)
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextMenuShowInFinder(_:)), keyEquivalent: "")
            finderItem.target = self; finderItem.representedObject = track; menu.addItem(finderItem)
            menu.addItem(NSMenuItem.separator())
            let removeTrackItem = NSMenuItem(title: "Remove from Library", action: #selector(contextMenuRemoveLocalTrack(_:)), keyEquivalent: "")
            removeTrackItem.target = self; removeTrackItem.representedObject = track; menu.addItem(removeTrackItem)
        case .localFolder(let url, _):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayLocalFolder(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play and Replace Queue", action: #selector(contextMenuPlayLocalFolderAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = item; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Next", action: #selector(contextMenuPlayLocalFolderNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = item; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(contextMenuAddLocalFolderToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = item; menu.addItem(queueItem)
            menu.addItem(NSMenuItem.separator())
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextMenuRevealLocalFolderInFinder(_:)), keyEquivalent: "")
            finderItem.target = self; finderItem.representedObject = url; menu.addItem(finderItem)
        case .localAlbum(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayLocalAlbum(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = album; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Album and Replace Queue", action: #selector(contextMenuPlayLocalAlbumAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = album; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Album Next", action: #selector(contextMenuPlayLocalAlbumNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = album; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Album to Queue", action: #selector(contextMenuAddLocalAlbumToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = album; menu.addItem(queueItem)
            menu.addItem(NSMenuItem.separator())
            let rateAlbumItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateAlbumItem.submenu = buildRateSubmenuForLocalAlbum(albumId: album.id); menu.addItem(rateAlbumItem)
            let editAlbumItem = NSMenuItem(title: "Edit Album Tags", action: #selector(contextMenuEditAlbumTags(_:)), keyEquivalent: "")
            editAlbumItem.target = self; editAlbumItem.representedObject = album; menu.addItem(editAlbumItem)
            let removeAlbumItem = NSMenuItem(title: "Remove Album from Library", action: #selector(contextMenuRemoveLocalAlbum(_:)), keyEquivalent: "")
            removeAlbumItem.target = self; removeAlbumItem.representedObject = album; menu.addItem(removeAlbumItem)
        case .localArtist(let artist):
            let playItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlayLocalArtist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = artist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Artist and Replace Queue", action: #selector(contextMenuPlayLocalArtistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = artist; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Artist Next", action: #selector(contextMenuPlayLocalArtistNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = artist; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Artist to Queue", action: #selector(contextMenuAddLocalArtistToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = artist; menu.addItem(queueItem)
            menu.addItem(NSMenuItem.separator())
            let rateArtistItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateArtistItem.submenu = buildRateSubmenuForLocalArtist(artistId: artist.id); menu.addItem(rateArtistItem)
            let removeArtistItem = NSMenuItem(title: "Remove Artist from Library", action: #selector(contextMenuRemoveLocalArtist(_:)), keyEquivalent: "")
            removeArtistItem.target = self; removeArtistItem.representedObject = artist; menu.addItem(removeArtistItem)
        case .subsonicTrack(let song):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlaySubsonicSong(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = song; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play and Replace Queue", action: #selector(contextMenuPlaySubsonicSongAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = song; menu.addItem(playReplaceItem)
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddSubsonicSongToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self; addItem.representedObject = song; menu.addItem(addItem)
            let playNextItem = NSMenuItem(title: "Play Next", action: #selector(contextMenuPlaySubsonicSongNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = song; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(contextMenuAddSubsonicSongToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = song; menu.addItem(queueItem)
            menu.addItem(NSMenuItem.separator())
            if song.albumId != nil {
                let albumItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlaySubsonicSongAlbum(_:)), keyEquivalent: "")
                albumItem.target = self; albumItem.representedObject = song; menu.addItem(albumItem)
            }
            if song.artistId != nil {
                let artistItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlaySubsonicSongArtist(_:)), keyEquivalent: "")
                artistItem.target = self; artistItem.representedObject = song; menu.addItem(artistItem)
            }
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenuForSubsonic(songId: song.id)
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu; menu.addItem(rateItem)
        case .subsonicAlbum(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlaySubsonicAlbum(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = album; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Album and Replace Queue", action: #selector(contextMenuPlaySubsonicAlbumAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = album; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Album Next", action: #selector(contextMenuPlaySubsonicAlbumNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = album; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Album to Queue", action: #selector(contextMenuAddSubsonicAlbumToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = album; menu.addItem(queueItem)
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenuForSubsonic(songId: album.id)
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu; menu.addItem(rateItem)
        case .subsonicArtist(let artist):
            let playItem = NSMenuItem(title: "Play All", action: #selector(contextMenuPlaySubsonicArtist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = artist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Artist and Replace Queue", action: #selector(contextMenuPlaySubsonicArtistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = artist; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Artist Next", action: #selector(contextMenuPlaySubsonicArtistNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = artist; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Artist to Queue", action: #selector(contextMenuAddSubsonicArtistToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = artist; menu.addItem(queueItem)
        case .jellyfinTrack(let song):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayJellyfinSong(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = song; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play and Replace Queue", action: #selector(contextMenuPlayJellyfinSongAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = song; menu.addItem(playReplaceItem)
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddJellyfinSongToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self; addItem.representedObject = song; menu.addItem(addItem)
            let playNextItem = NSMenuItem(title: "Play Next", action: #selector(contextMenuPlayJellyfinSongNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = song; menu.addItem(playNextItem)
            let queueItem2 = NSMenuItem(title: "Add to Queue", action: #selector(contextMenuAddJellyfinSongToQueue(_:)), keyEquivalent: "")
            queueItem2.target = self; queueItem2.representedObject = song; menu.addItem(queueItem2)
            if song.albumId != nil {
                menu.addItem(NSMenuItem.separator())
                let albumItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayJellyfinSongAlbum(_:)), keyEquivalent: "")
                albumItem.target = self; albumItem.representedObject = song; menu.addItem(albumItem)
            }
            if song.artistId != nil {
                let artistItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlayJellyfinSongArtist(_:)), keyEquivalent: "")
                artistItem.target = self; artistItem.representedObject = song; menu.addItem(artistItem)
            }
            menu.addItem(NSMenuItem.separator())
            let rateMenu2 = buildRateSubmenuForJellyfin(itemId: song.id)
            let rateItem2 = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem2.submenu = rateMenu2; menu.addItem(rateItem2)
        case .jellyfinAlbum(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayJellyfinAlbum(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = album; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Album and Replace Queue", action: #selector(contextMenuPlayJellyfinAlbumAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = album; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Album Next", action: #selector(contextMenuPlayJellyfinAlbumNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = album; menu.addItem(playNextItem)
            let queueItem3 = NSMenuItem(title: "Add Album to Queue", action: #selector(contextMenuAddJellyfinAlbumToQueue(_:)), keyEquivalent: "")
            queueItem3.target = self; queueItem3.representedObject = album; menu.addItem(queueItem3)
        case .jellyfinArtist(let artist):
            let playItem = NSMenuItem(title: "Play All", action: #selector(contextMenuPlayJellyfinArtist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = artist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Artist and Replace Queue", action: #selector(contextMenuPlayJellyfinArtistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = artist; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Artist Next", action: #selector(contextMenuPlayJellyfinArtistNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = artist; menu.addItem(playNextItem)
            let queueItem4 = NSMenuItem(title: "Add Artist to Queue", action: #selector(contextMenuAddJellyfinArtistToQueue(_:)), keyEquivalent: "")
            queueItem4.target = self; queueItem4.representedObject = artist; menu.addItem(queueItem4)
        case .jellyfinPlaylist(let playlist):
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlayJellyfinPlaylist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = playlist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Playlist and Replace Queue", action: #selector(contextMenuPlayJellyfinPlaylistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = playlist; menu.addItem(playReplaceItem)
        case .radioStation(let station):
            let playItem = NSMenuItem(title: "Play Station", action: #selector(contextMenuPlayRadioStation(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = station; menu.addItem(playItem)
            menu.addItem(NSMenuItem.separator())
            let foldersItem = NSMenuItem(title: "Folders", action: nil, keyEquivalent: "")
            foldersItem.submenu = buildRadioStationFoldersSubmenu(for: station)
            menu.addItem(foldersItem)
            let smartFoldersItem = NSMenuItem(title: "Smart Folders", action: nil, keyEquivalent: "")
            smartFoldersItem.submenu = buildRadioStationSmartFoldersSubmenu(for: station)
            menu.addItem(smartFoldersItem)
            menu.addItem(NSMenuItem.separator())
            let editItem = NSMenuItem(title: "Edit Station...", action: #selector(contextMenuEditRadioStation(_:)), keyEquivalent: "")
            editItem.target = self; editItem.representedObject = station; menu.addItem(editItem)
            let deleteItem = NSMenuItem(title: "Delete Station", action: #selector(contextMenuDeleteRadioStation(_:)), keyEquivalent: "")
            deleteItem.target = self; deleteItem.representedObject = station; menu.addItem(deleteItem)
        case .radioFolder(let folder):
            if folder.hasChildren {
                let expandItem = NSMenuItem(
                    title: expandedRadioFolders.contains(folder.id) ? "Collapse" : "Expand",
                    action: #selector(contextMenuToggleExpand(_:)),
                    keyEquivalent: ""
                )
                expandItem.target = self
                expandItem.representedObject = item
                menu.addItem(expandItem)
            }
            switch folder.kind {
            case .manual(let folderID):
                if !menu.items.isEmpty { menu.addItem(NSMenuItem.separator()) }
                let renameItem = NSMenuItem(title: "Rename Folder...", action: #selector(contextMenuRenameRadioFolder(_:)), keyEquivalent: "")
                renameItem.target = self
                renameItem.representedObject = RadioFolderRenameAction(folderID: folderID)
                menu.addItem(renameItem)

                let deleteItem = NSMenuItem(title: "Delete Folder", action: #selector(contextMenuDeleteRadioFolder(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.representedObject = RadioFolderDeleteAction(folderID: folderID)
                menu.addItem(deleteItem)
            case .userFoldersRoot:
                if !menu.items.isEmpty { menu.addItem(NSMenuItem.separator()) }
                let newFolderItem = NSMenuItem(title: "New Folder...", action: #selector(showCreateRadioFolderDialog), keyEquivalent: "")
                newFolderItem.target = self
                menu.addItem(newFolderItem)
            default:
                break
            }
            if menu.items.isEmpty { return }
        case .youtubeChannel(let channel):
            let expandTitle = expandedYouTubeChannels.contains(channel.id) ? "Collapse" : "Expand"
            let expandItem = NSMenuItem(title: expandTitle, action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
            menu.addItem(NSMenuItem.separator())
            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(contextMenuRefreshYouTubeChannel(_:)), keyEquivalent: "")
            refreshItem.target = self; refreshItem.representedObject = channel; menu.addItem(refreshItem)
            let removeItem = NSMenuItem(title: "Remove Channel", action: #selector(contextMenuRemoveYouTubeChannel(_:)), keyEquivalent: "")
            removeItem.target = self; removeItem.representedObject = channel; menu.addItem(removeItem)
        case .youtubeVideo(let video):
            let isDownloaded = YouTubeManager.shared.isDownloaded(video.videoId)
            let actionTitle = isDownloaded ? "Play" : "Download & Play"
            let actionItem = NSMenuItem(title: actionTitle, action: #selector(contextMenuPlayYouTubeVideo(_:)), keyEquivalent: "")
            actionItem.target = self; actionItem.representedObject = video; menu.addItem(actionItem)
            if isDownloaded {
                menu.addItem(NSMenuItem.separator())
                let removeDownloadItem = NSMenuItem(title: "Remove Download", action: #selector(contextMenuRemoveYouTubeDownload(_:)), keyEquivalent: "")
                removeDownloadItem.target = self; removeDownloadItem.representedObject = video; menu.addItem(removeDownloadItem)
            }
        case .plexRadioStation:
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayPlexRadioStation(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
        case .movie(let movie):
            let playItem = NSMenuItem(title: "Play Movie", action: #selector(contextMenuPlayMovie(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = movie; menu.addItem(playItem)
        case .show:
            let expandItem = NSMenuItem(title: "Expand/Collapse", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
        case .season:
            let expandItem = NSMenuItem(title: "Expand/Collapse", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
        case .episode(let episode):
            let playItem = NSMenuItem(title: "Play Episode", action: #selector(contextMenuPlayEpisode(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = episode; menu.addItem(playItem)
        case .jellyfinMovie(let movie):
            let playItem = NSMenuItem(title: "Play Movie", action: #selector(contextMenuPlayJellyfinMovie(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = movie; menu.addItem(playItem)
        case .jellyfinShow:
            let expandItem = NSMenuItem(title: "Expand/Collapse", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
        case .jellyfinSeason:
            let expandItem = NSMenuItem(title: "Expand/Collapse", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
        case .jellyfinEpisode(let episode):
            let playItem = NSMenuItem(title: "Play Episode", action: #selector(contextMenuPlayJellyfinEpisode(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = episode; menu.addItem(playItem)
        case .embyTrack(let song):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayEmbySong(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = song; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play and Replace Queue", action: #selector(contextMenuPlayEmbySongAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = song; menu.addItem(playReplaceItem)
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddEmbySongToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self; addItem.representedObject = song; menu.addItem(addItem)
            let playNextItem = NSMenuItem(title: "Play Next", action: #selector(contextMenuPlayEmbySongNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = song; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(contextMenuAddEmbySongToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = song; menu.addItem(queueItem)
            if song.albumId != nil {
                menu.addItem(NSMenuItem.separator())
                let albumItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayEmbySongAlbum(_:)), keyEquivalent: "")
                albumItem.target = self; albumItem.representedObject = song; menu.addItem(albumItem)
            }
            if song.artistId != nil {
                let artistItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlayEmbySongArtist(_:)), keyEquivalent: "")
                artistItem.target = self; artistItem.representedObject = song; menu.addItem(artistItem)
            }
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenuForEmby(itemId: song.id)
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu; menu.addItem(rateItem)
        case .embyAlbum(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayEmbyAlbum(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = album; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Album and Replace Queue", action: #selector(contextMenuPlayEmbyAlbumAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = album; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Album Next", action: #selector(contextMenuPlayEmbyAlbumNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = album; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Album to Queue", action: #selector(contextMenuAddEmbyAlbumToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = album; menu.addItem(queueItem)
        case .embyArtist(let artist):
            let playItem = NSMenuItem(title: "Play All", action: #selector(contextMenuPlayEmbyArtist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = artist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Artist and Replace Queue", action: #selector(contextMenuPlayEmbyArtistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = artist; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Artist Next", action: #selector(contextMenuPlayEmbyArtistNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = artist; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Artist to Queue", action: #selector(contextMenuAddEmbyArtistToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = artist; menu.addItem(queueItem)
        case .embyPlaylist(let playlist):
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlayEmbyPlaylist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = playlist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Playlist and Replace Queue", action: #selector(contextMenuPlayEmbyPlaylistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = playlist; menu.addItem(playReplaceItem)
        case .embyMovie(let movie):
            let playItem = NSMenuItem(title: "Play Movie", action: #selector(contextMenuPlayEmbyMovie(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = movie; menu.addItem(playItem)
        case .embyShow:
            let expandItem = NSMenuItem(title: "Expand/Collapse", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
        case .embySeason:
            let expandItem = NSMenuItem(title: "Expand/Collapse", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
        case .embyEpisode(let episode):
            let playItem = NSMenuItem(title: "Play Episode", action: #selector(contextMenuPlayEmbyEpisode(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = episode; menu.addItem(playItem)
        case .subsonicPlaylist(let playlist):
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlaySubsonicPlaylist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = playlist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Playlist and Replace Queue", action: #selector(contextMenuPlaySubsonicPlaylistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = playlist; menu.addItem(playReplaceItem)
        case .plexPlaylist(let playlist):
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlayPlexPlaylist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = playlist; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play Playlist and Replace Queue", action: #selector(contextMenuPlayPlexPlaylistAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = playlist; menu.addItem(playReplaceItem)
        case .localMovie(let movie):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayLocalMovie(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = movie; menu.addItem(playItem)
            let videoDevices = CastManager.shared.videoCapableDevices
            if !videoDevices.isEmpty {
                menu.addItem(NSMenuItem.separator())
                let castItem = NSMenuItem(title: "Cast to...", action: nil, keyEquivalent: "")
                let castMenu = NSMenu()
                for device in videoDevices {
                    let deviceItem = NSMenuItem(title: device.name, action: #selector(contextMenuCastLocalVideo(_:)), keyEquivalent: "")
                    deviceItem.target = self
                    deviceItem.representedObject = (movie.url, movie.title, device) as (URL, String, CastDevice)
                    castMenu.addItem(deviceItem)
                }
                castItem.submenu = castMenu
                menu.addItem(castItem)
            }
            menu.addItem(NSMenuItem.separator())
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextMenuShowLocalVideoInFinder(_:)), keyEquivalent: "")
            finderItem.target = self; finderItem.representedObject = movie.url as NSURL; menu.addItem(finderItem)
            menu.addItem(NSMenuItem.separator())
            let editMovieItem = NSMenuItem(title: "Edit Tags", action: #selector(contextMenuEditVideoTags(_:)), keyEquivalent: "")
            editMovieItem.target = self; editMovieItem.representedObject = movie; menu.addItem(editMovieItem)
            let removeMovieItem = NSMenuItem(title: "Remove from Library", action: #selector(contextMenuRemoveLocalMovie(_:)), keyEquivalent: "")
            removeMovieItem.target = self; removeMovieItem.representedObject = movie; menu.addItem(removeMovieItem)
        case .localShow(let show):
            let expandItem = NSMenuItem(title: "Expand/Collapse", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
            menu.addItem(NSMenuItem.separator())
            let removeShowItem = NSMenuItem(title: "Remove Show from Library", action: #selector(contextMenuRemoveLocalShow(_:)), keyEquivalent: "")
            removeShowItem.target = self; removeShowItem.representedObject = show; menu.addItem(removeShowItem)
        case .localSeason(let season, let showTitle):
            let expandItem = NSMenuItem(title: "Expand/Collapse", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
            menu.addItem(NSMenuItem.separator())
            let removeSeasonItem = NSMenuItem(title: "Remove Season from Library", action: #selector(contextMenuRemoveLocalSeason(_:)), keyEquivalent: "")
            removeSeasonItem.target = self; removeSeasonItem.representedObject = SeasonRef(season: season, showTitle: showTitle); menu.addItem(removeSeasonItem)
        case .localEpisode(let episode):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayLocalEpisode(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = episode; menu.addItem(playItem)
            let videoDevices = CastManager.shared.videoCapableDevices
            if !videoDevices.isEmpty {
                menu.addItem(NSMenuItem.separator())
                let castItem = NSMenuItem(title: "Cast to...", action: nil, keyEquivalent: "")
                let castMenu = NSMenu()
                for device in videoDevices {
                    let deviceItem = NSMenuItem(title: device.name, action: #selector(contextMenuCastLocalVideo(_:)), keyEquivalent: "")
                    deviceItem.target = self
                    deviceItem.representedObject = (episode.url, episode.title, device) as (URL, String, CastDevice)
                    castMenu.addItem(deviceItem)
                }
                castItem.submenu = castMenu
                menu.addItem(castItem)
            }
            menu.addItem(NSMenuItem.separator())
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextMenuShowLocalVideoInFinder(_:)), keyEquivalent: "")
            finderItem.target = self; finderItem.representedObject = episode.url as NSURL; menu.addItem(finderItem)
            menu.addItem(NSMenuItem.separator())
            let editEpItem = NSMenuItem(title: "Edit Tags", action: #selector(contextMenuEditVideoTags(_:)), keyEquivalent: "")
            editEpItem.target = self; editEpItem.representedObject = episode; menu.addItem(editEpItem)
            let removeEpItem = NSMenuItem(title: "Remove from Library", action: #selector(contextMenuRemoveLocalEpisode(_:)), keyEquivalent: "")
            removeEpItem.target = self; removeEpItem.representedObject = episode; menu.addItem(removeEpItem)
        case .subsonicRadioStation:
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlaySubsonicRadioStation(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
        case .jellyfinRadioStation:
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayJellyfinRadioStation(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
        case .embyRadioStation:
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayEmbyRadioStation(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
        case .localRadioStation:
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayLocalRadioStation(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
        case .localPlaylist:
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlayLocalPlaylist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
        case .localPlaylistTrack(let track):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayPlaylistTrack(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = track; menu.addItem(playItem)
            let playReplaceItem = NSMenuItem(title: "Play and Replace Queue", action: #selector(contextMenuPlayPlaylistTrackAndReplace(_:)), keyEquivalent: "")
            playReplaceItem.target = self; playReplaceItem.representedObject = track; menu.addItem(playReplaceItem)
            let playNextItem = NSMenuItem(title: "Play Next", action: #selector(contextMenuPlayPlaylistTrackNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = track; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(contextMenuAddPlaylistTrackToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = track; menu.addItem(queueItem)
        case .header: return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - @objc Menu Actions
    
    @objc private func selectLocalSource() { currentSource = .local }
    @objc private func selectRadioSource() { currentSource = .radio }
    @objc private func selectYouTubeSource() { currentSource = .youtube }

    private func showYouTubeAddMenu(at event: NSEvent) {
        let menu = NSMenu()
        let addItem = NSMenuItem(title: "Add Channel...", action: #selector(showAddYouTubeChannelDialog), keyEquivalent: "")
        addItem.target = self; menu.addItem(addItem)
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    @objc private func clearLocalMusicFromSourceMenu() {
        MenuActions.shared.clearLocalMusic()
        if case .local = currentSource { loadLocalData() }
    }
    @objc private func clearLocalMoviesFromSourceMenu() {
        MenuActions.shared.clearLocalMovies()
        if case .local = currentSource { loadLocalData() }
    }
    @objc private func clearLocalTVFromSourceMenu() {
        MenuActions.shared.clearLocalTV()
        if case .local = currentSource { loadLocalData() }
    }
    @objc private func clearLocalLibraryFromSourceMenu() {
        MenuActions.shared.clearLibrary()
        if case .local = currentSource {
            loadLocalData()
        }
    }
    @objc private func selectPlexServer(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        currentSource = .plex(serverId: serverId)
    }
    @objc private func selectSubsonicServer(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        currentSource = .subsonic(serverId: serverId)
    }
    @objc private func selectJellyfinServer(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        currentSource = .jellyfin(serverId: serverId)
    }
    @objc private func selectEmbyServer(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        currentSource = .emby(serverId: serverId)
    }
    @objc private func linkPlexAccount() { controller?.showLinkSheet() }
    @objc private func selectSortOption(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? ModernBrowserSortOption else { return }
        // The Sort menu and column-header sorts are two routes to the same ordering, and a
        // lingering column sort (which overrides currentSort) would silently re-order the list
        // on the next rebuild — e.g. snapping a date-sorted tab back to name order the moment a
        // row is expanded, leaving the selection on the wrong item. Picking from the menu makes
        // it the sole sort, so drop any active column sort first.
        if columnSortId != nil { columnSortId = nil }
        currentSort = option
    }
    @objc private func selectLibrary(_ sender: NSMenuItem) {
        guard let library = sender.representedObject as? PlexLibrary else { return }
        PlexManager.shared.selectLibrary(library); clearAllCachedData()
        // Switch browse mode to match the selected library type
        if library.isMusicLibrary {
            if browseMode.isVideoMode {
                browseMode = .artists
            }
        } else if library.isMovieLibrary {
            browseMode = .movies
        } else if library.isShowLibrary {
            browseMode = .shows
        }
        selectedIndices.removeAll(); scrollOffset = 0
        reloadData()
    }
    @objc private func selectJellyfinMusicLibrary(_ sender: NSMenuItem) {
        let library = sender.representedObject as? JellyfinMusicLibrary
        if let library = library {
            JellyfinManager.shared.selectMusicLibrary(library)
        } else {
            JellyfinManager.shared.clearMusicLibrarySelection()
        }
        clearAllCachedData(); reloadData()
    }
    @objc private func selectJellyfinVideoLibraryFromBrowser(_ sender: NSMenuItem) {
        let library = sender.representedObject as? JellyfinMusicLibrary
        if let library = library {
            JellyfinManager.shared.selectMovieLibrary(library)
            JellyfinManager.shared.selectShowLibrary(library)
        } else {
            JellyfinManager.shared.selectMovieLibrary(nil)
            JellyfinManager.shared.selectShowLibrary(nil)
        }
        cachedJellyfinMovies = []; cachedJellyfinShows = []
        reloadData()
    }
    @objc private func selectEmbyMusicLibraryFromBrowser(_ sender: NSMenuItem) {
        let library = sender.representedObject as? EmbyMusicLibrary
        if let library = library {
            EmbyManager.shared.selectMusicLibrary(library)
        } else {
            EmbyManager.shared.clearMusicLibrarySelection()
        }
        clearAllCachedData(); reloadData()
    }
    @objc private func selectEmbyVideoLibraryFromBrowser(_ sender: NSMenuItem) {
        let library = sender.representedObject as? EmbyMusicLibrary
        if let library = library {
            EmbyManager.shared.selectMovieLibrary(library)
            EmbyManager.shared.selectShowLibrary(library)
        } else {
            EmbyManager.shared.selectMovieLibrary(nil)
            EmbyManager.shared.selectShowLibrary(nil)
        }
        cachedEmbyMovies = []; cachedEmbyShows = []
        reloadData()
    }
    @objc private func selectSubsonicMusicFolder(_ sender: NSMenuItem) {
        let folder = sender.representedObject as? SubsonicMusicFolder
        if let folder = folder {
            SubsonicManager.shared.selectMusicFolder(folder)
        } else {
            SubsonicManager.shared.clearMusicFolderSelection()
        }
        clearAllCachedData(); reloadData()
    }
    @objc private func addFiles() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]; panel.message = "Select audio files"
        if panel.runModal() == .OK { MediaLibrary.shared.addTracks(urls: panel.urls) }
    }
    @objc private func addVideoFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Select video files to add to your library"
        if panel.runModal() == .OK {
            MediaLibrary.shared.addVideoFiles(urls: panel.urls)
            loadLocalData()
        }
    }
    @objc private func addWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to add to your library"

        let folderDelegate = TopLevelFolderPickerDelegate()
        panel.delegate = folderDelegate

        withExtendedLifetime(folderDelegate) {
            if panel.runModal() == .OK, let url = panel.url {
                MediaLibrary.shared.addWatchFolder(url)
                MediaLibrary.shared.scanFolder(url)
            }
        }
    }

    @objc private func manageWatchFolders() {
        WatchFolderManagerDialog.present { [weak self] in
            guard let self = self else { return }
            if case .local = self.currentSource {
                self.loadLocalData()
            }
        }
    }
    @objc private func showAddRadioStationDialog() {
        activeRadioStationSheet = AddRadioStationSheet(station: nil)
        activeRadioStationSheet?.showDialog { [weak self] station in
            self?.activeRadioStationSheet = nil
            if let newStation = station {
                RadioManager.shared.addStation(newStation)
                if case .radio = self?.currentSource { self?.reloadInternetRadioForCurrentMode() }
                else { self?.currentSource = .radio }
            }
        }
    }
    @objc private func showCreateRadioFolderDialog() {
        guard let name = promptForRadioFolderName(
            title: "New Folder",
            message: "Enter a folder name for Internet Radio:",
            confirmTitle: "Create"
        ) else { return }
        guard RadioManager.shared.createUserFolder(named: name) != nil else {
            let alert = NSAlert()
            alert.messageText = "Unable to Create Folder"
            alert.informativeText = "Use a unique, non-empty folder name."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        reloadInternetRadioForCurrentMode()
    }

    @objc private func showAddYouTubeChannelDialog() {
        activeYouTubeChannelSheet = AddYouTubeChannelSheet()
        activeYouTubeChannelSheet?.showDialog { [weak self] channel in
            self?.activeYouTubeChannelSheet = nil
            guard let self = self else { return }
            if channel != nil {
                if case .youtube = self.currentSource {
                    self.rebuildCurrentModeItems()
                } else {
                    self.currentSource = .youtube
                }
            }
        }
    }
    @objc private func addMissingRadioDefaults() { RadioManager.shared.addMissingDefaults(); if case .radio = currentSource { reloadInternetRadioForCurrentMode() } }
    @objc private func resetRadioToDefaults() {
        let alert = NSAlert(); alert.messageText = "Reset to Defaults"; alert.informativeText = "Replace all stations with defaults?"
        alert.addButton(withTitle: "Reset"); alert.addButton(withTitle: "Cancel"); alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { RadioManager.shared.resetToDefaults(); if case .radio = currentSource { reloadInternetRadioForCurrentMode() } }
    }
    @objc private func menuNextEffect() { nextVisEffect() }

    @objc private func menuSelectEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let effect = VisEffect(rawValue: raw) else { return }
        visMode = .single
        currentVisEffect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: "browserVisEffect")
    }

    @objc private func menuSetDefaultEffect() {
        UserDefaults.standard.set(currentVisEffect.rawValue, forKey: "browserVisDefaultEffect")
    }
    @objc private func enableArtVisualization() { isVisualizingArt = true }
    @objc private func exitArtView() { isArtOnlyMode = false }
    @objc private func turnOffVisualization() { isVisualizingArt = false }
    
    @objc private func contextMenuPlay(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem else { return }; playTrack(item)
    }
    @objc private func contextMenuAddToPlaylist(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? PlexTrack,
              let t = PlexManager.shared.convertToTrack(track) else { return }
        WindowManager.shared.audioEngine.appendTracks([t])
    }
    @objc private func contextMenuPlayAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? PlexAlbum else { return }; playAlbum(album)
    }
    @objc private func contextMenuPlayArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? PlexArtist else { return }; playArtist(artist)
    }
    @objc private func contextMenuToggleExpand(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem else { return }; toggleExpand(item)
    }
    @objc private func contextMenuPlayLocalTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }; playLocalTrack(track)
    }
    @objc private func contextMenuShowTags(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        activeTagsPanel?.close()
        let tagsPanel = TagsPanel(track: track); activeTagsPanel = tagsPanel; tagsPanel.show()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: tagsPanel, queue: .main) { [weak self] _ in
            self?.activeTagsPanel = nil
        }
    }
    @objc private func contextMenuEditTags(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        activeEditTagsPanel?.close()
        let panel = EditTagsPanel(track: track)
        panel.onSave = { [weak self] in self?.reloadLocalBrowserAfterMetadataEdit() }
        activeEditTagsPanel = panel; panel.show()
    }
    @objc private func contextMenuEditAlbumTags(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        activeEditAlbumTagsPanel?.close()
        let panel = EditAlbumTagsPanel(album: album)
        panel.onSave = { [weak self] in self?.reloadLocalBrowserAfterMetadataEdit() }
        activeEditAlbumTagsPanel = panel; panel.show()
    }
    @objc private func contextMenuEditVideoTags(_ sender: NSMenuItem) {
        let videoItem: EditVideoTagsPanel.VideoItem
        if let movie = sender.representedObject as? LocalVideo { videoItem = .movie(movie) }
        else if let ep = sender.representedObject as? LocalEpisode { videoItem = .episode(ep) }
        else { return }
        activeEditVideoTagsPanel?.close()
        let panel = EditVideoTagsPanel(item: videoItem)
        panel.onSave = { [weak self] in self?.reloadLocalBrowserAfterMetadataEdit() }
        activeEditVideoTagsPanel = panel; panel.show()
    }
    @objc private func contextMenuRemoveLocalTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        let tracksToRemove = selectedLocalTracksForContextAction(fallback: track)
        if tracksToRemove.count == 1 {
            MediaLibrary.shared.removeTrack(track)
        } else {
            MediaLibrary.shared.removeTracks(urls: tracksToRemove.map { $0.url })
        }
        loadLocalData()
    }
    @objc private func contextMenuRemoveLocalAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        let tracks = resolvedTracksForLocalAlbum(album)
        let count = tracks.count
        let alert = NSAlert()
        alert.messageText = "Remove \"\(album.name)\" from Library?"
        alert.informativeText = "This will remove \(count) track\(count == 1 ? "" : "s"). Files will not be deleted."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        MediaLibrary.shared.removeTracks(urls: tracks.map { $0.url }); loadLocalData()
    }
    @objc private func contextMenuRemoveLocalArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        let artistsToRemove = selectedLocalArtistsForContextAction(fallback: artist)
        let store = MediaLibraryStore.shared
        let trackURLs: [URL] = artistsToRemove.flatMap { a -> [URL] in
            if a.albums.isEmpty {
                // Paginated stub — load tracks from store
                let summaries = store.albumsForArtist(a.name)
                return summaries.flatMap { store.tracksForAlbum($0.id) }.map { $0.url }
            } else {
                return a.albums.flatMap { $0.tracks }.map { $0.url }
            }
        }
        let dedupedTrackURLs = dedupeURLsPreservingOrder(trackURLs)
        let count = dedupedTrackURLs.count

        let alert = NSAlert()
        if artistsToRemove.count == 1 {
            alert.messageText = "Remove \"\(artist.name)\" from Library?"
        } else {
            alert.messageText = "Remove \(artistsToRemove.count) Artists from Library?"
        }
        alert.informativeText = "This will remove \(count) track\(count == 1 ? "" : "s"). Files will not be deleted."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        MediaLibrary.shared.removeTracks(urls: dedupedTrackURLs); loadLocalData()
    }
    @objc private func contextMenuRemoveLocalMovie(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? LocalVideo else { return }
        let moviesToRemove = selectedLocalMoviesForContextAction(fallback: movie)
        if moviesToRemove.count == 1 {
            MediaLibrary.shared.removeMovie(movie)
        } else {
            MediaLibrary.shared.removeMovies(urls: moviesToRemove.map { $0.url })
        }
        loadLocalData()
    }
    @objc private func contextMenuRemoveLocalEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? LocalEpisode else { return }
        MediaLibrary.shared.removeEpisode(episode); loadLocalData()
    }
    @objc private func contextMenuRemoveLocalShow(_ sender: NSMenuItem) {
        guard let show = sender.representedObject as? LocalShow else { return }
        let count = show.episodeCount
        let alert = NSAlert()
        alert.messageText = "Remove \"\(show.title)\" from Library?"
        alert.informativeText = "This will remove \(count) episode\(count == 1 ? "" : "s"). Files will not be deleted."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        MediaLibrary.shared.removeShow(title: show.title); loadLocalData()
    }
    @objc private func contextMenuRemoveLocalSeason(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? SeasonRef else { return }
        let count = ref.season.episodes.count
        let alert = NSAlert()
        alert.messageText = "Remove Season \(ref.season.number) of \"\(ref.showTitle)\" from Library?"
        alert.informativeText = "This will remove \(count) episode\(count == 1 ? "" : "s"). Files will not be deleted."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        MediaLibrary.shared.removeSeason(showTitle: ref.showTitle, seasonNumber: ref.season.number); loadLocalData()
    }
    @objc private func contextMenuShowInFinder(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
    }

    /// For local-track context actions, prefer current multi-selection when the
    /// clicked track is part of it; otherwise fall back to the clicked track.
    private func selectedLocalTracksForContextAction(fallback track: LibraryTrack) -> [LibraryTrack] {
        let selectedTracks = selectedIndices
            .filter { $0 >= 0 && $0 < displayItems.count }
            .sorted()
            .compactMap { index -> LibraryTrack? in
                guard case .localTrack(let selectedTrack) = displayItems[index].type else { return nil }
                return selectedTrack
            }

        guard selectedTracks.count > 1,
              selectedTracks.contains(where: { $0.url == track.url }) else {
            return [track]
        }

        // De-duplicate by file URL while preserving visual selection order.
        return dedupeByURL(selectedTracks, keyPath: \.url)
    }

    /// For local-artist context actions, prefer current multi-selection when the
    /// clicked artist is part of it; otherwise fall back to the clicked artist.
    private func selectedLocalArtistsForContextAction(fallback artist: Artist) -> [Artist] {
        let selectedArtists = selectedIndices
            .filter { $0 >= 0 && $0 < displayItems.count }
            .sorted()
            .compactMap { index -> Artist? in
                guard case .localArtist(let selectedArtist) = displayItems[index].type else { return nil }
                return selectedArtist
            }

        guard selectedArtists.count > 1,
              selectedArtists.contains(where: { $0.id == artist.id }) else {
            return [artist]
        }

        var seen = Set<String>()
        return selectedArtists.filter { seen.insert($0.id).inserted }
    }

    /// For local-movie context actions, prefer current multi-selection when the
    /// clicked movie is part of it; otherwise fall back to the clicked movie.
    private func selectedLocalMoviesForContextAction(fallback movie: LocalVideo) -> [LocalVideo] {
        let selectedMovies = selectedIndices
            .filter { $0 >= 0 && $0 < displayItems.count }
            .sorted()
            .compactMap { index -> LocalVideo? in
                guard case .localMovie(let selectedMovie) = displayItems[index].type else { return nil }
                return selectedMovie
            }

        guard selectedMovies.count > 1,
              selectedMovies.contains(where: { $0.id == movie.id }) else {
            return [movie]
        }

        var seen = Set<UUID>()
        return selectedMovies.filter { seen.insert($0.id).inserted }
    }

    private func dedupeURLsPreservingOrder(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func dedupeByURL<T>(_ items: [T], keyPath: KeyPath<T, URL>) -> [T] {
        var seen = Set<URL>()
        return items.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
    @objc private func contextMenuPlayLocalMovie(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? LocalVideo else { return }
        WindowManager.shared.showVideoPlayer(url: movie.url, title: movie.title)
    }
    @objc private func contextMenuPlayLocalEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? LocalEpisode else { return }
        WindowManager.shared.showVideoPlayer(url: episode.url, title: episode.title)
    }
    @objc private func contextMenuShowLocalVideoInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? NSURL as URL? else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc private func contextMenuCastLocalVideo(_ sender: NSMenuItem) {
        guard let (url, title, device) = sender.representedObject as? (URL, String, CastDevice) else { return }
        if WindowManager.shared.isVideoCastingActive {
            let alert = NSAlert()
            alert.messageText = "Already Casting"
            alert.informativeText = "Stop the current cast before starting a new one."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        Task { @MainActor in
            do {
                try await CastManager.shared.castLocalVideo(url, title: title, to: device)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Cast Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
    @objc private func contextMenuPlayLocalAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }; playLocalAlbum(album)
    }
    @objc private func contextMenuPlayLocalArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }; playLocalArtist(artist)
    }
    @objc private func contextMenuPlayLocalPlaylist(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .localPlaylist(let p) = item.type else { return }
        playLocalPlaylist(p.url)
    }
    @objc private func contextMenuPlayPlaylistTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        WindowManager.shared.audioEngine.playNow([track])
    }
    @objc private func contextMenuAddLocalTrackToPlaylist(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        WindowManager.shared.audioEngine.appendTracks([track.toTrack()])
    }
    @objc private func contextMenuPlaySubsonicSong(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong else { return }; playSubsonicSong(song)
    }
    @objc private func contextMenuPlaySubsonicAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? SubsonicAlbum else { return }; playSubsonicAlbum(album)
    }
    @objc private func contextMenuPlaySubsonicArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? SubsonicArtist else { return }; playSubsonicArtist(artist)
    }
    @objc private func contextMenuPlaySubsonicPlaylist(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? SubsonicPlaylist else { return }; playSubsonicPlaylist(playlist)
    }
    @objc private func contextMenuAddSubsonicSongToPlaylist(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong,
              let track = SubsonicManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.appendTracks([track])
    }
    @objc private func contextMenuPlaySubsonicSongAlbum(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong,
              let albumId = song.albumId else { return }
        Task { @MainActor in
            if let album = cachedSubsonicAlbums.first(where: { $0.id == albumId }) {
                playSubsonicAlbum(album)
            } else {
                do {
                    let (_, songs) = try await SubsonicManager.shared.serverClient?.fetchAlbum(id: albumId) ?? (nil, [])
                    let tracks = songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                    if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
                } catch { NSLog("Failed to fetch album: %@", error.localizedDescription) }
            }
        }
    }
    @objc private func contextMenuPlaySubsonicSongArtist(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong,
              let artistId = song.artistId else { return }
        Task { @MainActor in
            if let artist = cachedSubsonicArtists.first(where: { $0.id == artistId }) {
                playSubsonicArtist(artist)
            } else {
                do {
                    let results = try await SubsonicManager.shared.search(query: song.artist ?? "")
                    let tracks = results.songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                    if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
                } catch { NSLog("Failed to fetch artist songs: %@", error.localizedDescription) }
            }
        }
    }
    @objc private func contextMenuPlayJellyfinSong(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? JellyfinSong else { return }; playJellyfinSong(song)
    }
    @objc private func contextMenuPlayJellyfinAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? JellyfinAlbum else { return }; playJellyfinAlbum(album)
    }
    @objc private func contextMenuPlayJellyfinArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? JellyfinArtist else { return }; playJellyfinArtist(artist)
    }
    @objc private func contextMenuPlayJellyfinPlaylist(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? JellyfinPlaylist else { return }; playJellyfinPlaylist(playlist)
    }
    @objc private func contextMenuAddJellyfinSongToPlaylist(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? JellyfinSong,
              let track = JellyfinManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.appendTracks([track])
    }
    @objc private func contextMenuPlayJellyfinSongAlbum(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? JellyfinSong,
              let albumId = song.albumId else { return }
        Task { @MainActor in
            if let album = cachedJellyfinAlbums.first(where: { $0.id == albumId }) {
                playJellyfinAlbum(album)
            } else {
                do {
                    let (_, songs) = try await JellyfinManager.shared.serverClient?.fetchAlbum(id: albumId) ?? (nil, [])
                    let tracks = JellyfinManager.shared.convertToTracks(songs)
                    if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
                } catch { NSLog("Failed to fetch album: %@", error.localizedDescription) }
            }
        }
    }
    @objc private func contextMenuPlayJellyfinSongArtist(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? JellyfinSong,
              let artistId = song.artistId else { return }
        Task { @MainActor in
            if let artist = cachedJellyfinArtists.first(where: { $0.id == artistId }) {
                playJellyfinArtist(artist)
            } else {
                do {
                    let results = try await JellyfinManager.shared.search(query: song.artist ?? "")
                    let tracks = JellyfinManager.shared.convertToTracks(results.songs)
                    if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
                } catch { NSLog("Failed to fetch artist songs: %@", error.localizedDescription) }
            }
        }
    }
    @objc private func contextMenuPlayPlexPlaylist(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? PlexPlaylist else { return }; playPlexPlaylist(playlist)
    }
    @objc private func contextMenuPlayRadioStation(_ sender: NSMenuItem) {
        guard let station = sender.representedObject as? RadioStation else { return }; playRadioStation(station)
    }
    @objc private func contextMenuEditRadioStation(_ sender: NSMenuItem) {
        guard let station = sender.representedObject as? RadioStation else { return }
        activeRadioStationSheet = AddRadioStationSheet(station: station)
        activeRadioStationSheet?.showDialog { [weak self] updated in
            self?.activeRadioStationSheet = nil
            if let u = updated { RadioManager.shared.updateStation(u); self?.reloadInternetRadioForCurrentMode() }
        }
    }
    @objc private func contextMenuDeleteRadioStation(_ sender: NSMenuItem) {
        guard let station = sender.representedObject as? RadioStation else { return }
        let alert = NSAlert(); alert.messageText = "Delete '\(station.name)'?"; alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { RadioManager.shared.removeStation(station); reloadInternetRadioForCurrentMode() }
    }
    @objc private func contextMenuRenameRadioFolder(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? RadioFolderRenameAction else { return }
        guard let existing = RadioManager.shared.userRadioFolders().first(where: { $0.id == action.folderID }) else { return }
        guard let name = promptForRadioFolderName(
            title: "Rename Folder",
            message: "Enter a new name:",
            confirmTitle: "Rename",
            defaultValue: existing.name
        ) else { return }
        guard RadioManager.shared.renameUserFolder(id: action.folderID, to: name) else {
            let alert = NSAlert()
            alert.messageText = "Unable to Rename Folder"
            alert.informativeText = "Use a unique, non-empty folder name."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        reloadInternetRadioForCurrentMode()
    }
    @objc private func contextMenuDeleteRadioFolder(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? RadioFolderDeleteAction else { return }
        guard let existing = RadioManager.shared.userRadioFolders().first(where: { $0.id == action.folderID }) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Folder?"
        alert.informativeText = "Delete '\(existing.name)' and its station memberships?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = RadioManager.shared.deleteUserFolder(id: action.folderID)
        reloadInternetRadioForCurrentMode()
    }
    @objc private func contextMenuRefreshYouTubeChannel(_ sender: NSMenuItem) {
        guard let channel = sender.representedObject as? YouTubeChannel else { return }
        youtubeChannelVideos.removeValue(forKey: channel.id)
        expandedYouTubeChannels.insert(channel.id)
        youtubeExpandTask?.cancel()
        loadingChannelIds.insert(channel.id); startLoadingAnimation()
        youtubeExpandTask = Task.detached { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.loadingChannelIds.remove(channel.id); self.stopLoadingAnimation(); self.needsDisplay = true }
            do {
                let videos = try await YouTubeManager.shared.videos(forChannel: channel)
                youtubeChannelVideos[channel.id] = videos
                rebuildCurrentModeItems()
            } catch is CancellationError { }
            catch where Task.isCancelled { }
            catch {
                NSLog("Failed to refresh YouTube channel '%@': %@", channel.title, error.localizedDescription)
            }
        }
        rebuildCurrentModeItems(); needsDisplay = true
    }

    @objc private func contextMenuRemoveYouTubeChannel(_ sender: NSMenuItem) {
        guard let channel = sender.representedObject as? YouTubeChannel else { return }
        YouTubeManager.shared.removeChannel(channel)
        expandedYouTubeChannels.remove(channel.id)
        youtubeChannelVideos.removeValue(forKey: channel.id)
        rebuildCurrentModeItems()
    }

    @objc private func contextMenuPlayYouTubeVideo(_ sender: NSMenuItem) {
        guard let video = sender.representedObject as? YouTubeVideo else { return }
        if YouTubeManager.shared.isDownloaded(video.videoId) {
            if let url = YouTubeManager.shared.downloadedFileURL(for: video.videoId) {
                let track = Track(url: url, isYouTubeOrigin: true)
                WindowManager.shared.audioEngine.playNow([track])
            }
        } else {
            downloadingVideoIds.insert(video.videoId)
            startLoadingAnimation()
            needsDisplay = true
            youtubeDownloadTask?.cancel()
            youtubeDownloadTask = Task.detached { @MainActor [weak self] in
                guard let self = self else { return }
                defer { self.downloadingVideoIds.remove(video.videoId); self.stopLoadingAnimation(); self.needsDisplay = true }
                do {
                    let downloadedURL = try await YouTubeManager.shared.download(video: video)
                    // A newer download may have superseded this one; don't auto-play a stale result.
                    try Task.checkCancellation()
                    let track = Track(url: downloadedURL, isYouTubeOrigin: true)
                    WindowManager.shared.audioEngine.playNow([track])
                    rebuildCurrentModeItems()
                } catch is CancellationError {
                    // Superseded by a newer download request; skip side effects.
                } catch {
                    NSLog("Failed to download YouTube video: %@", error.localizedDescription)
                }
            }
        }
    }

    @objc private func contextMenuRemoveYouTubeDownload(_ sender: NSMenuItem) {
        guard let video = sender.representedObject as? YouTubeVideo else { return }
        YouTubeManager.shared.removeDownload(videoId: video.videoId)
        rebuildCurrentModeItems()
    }

    @objc private func contextMenuToggleStationFolderMembership(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? RadioFolderMembershipAction else { return }
        if RadioManager.shared.isStation(action.station, inUserFolderID: action.folderID) {
            _ = RadioManager.shared.removeStation(action.station, fromUserFolderID: action.folderID)
        } else {
            _ = RadioManager.shared.addStation(action.station, toUserFolderID: action.folderID)
        }
        reloadInternetRadioForCurrentMode()
    }
    @objc private func contextMenuAssignStationSmartGenre(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? RadioSmartGenreAction else { return }
        _ = RadioManager.shared.setSmartGenreOverride(action.genre, for: action.station)
        reloadInternetRadioForCurrentMode()
    }
    @objc private func contextMenuAssignStationSmartRegion(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? RadioSmartRegionAction else { return }
        _ = RadioManager.shared.setSmartRegionOverride(action.region, for: action.station)
        reloadInternetRadioForCurrentMode()
    }
    @objc private func contextMenuCreateRadioFolderAndAddStation(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? RadioFolderStationAction else { return }
        guard let name = promptForRadioFolderName(
            title: "New Folder",
            message: "Create a folder and add '\(action.station.name)' to it:",
            confirmTitle: "Create"
        ) else { return }
        guard let folder = RadioManager.shared.createUserFolder(named: name) else {
            let alert = NSAlert()
            alert.messageText = "Unable to Create Folder"
            alert.informativeText = "Use a unique, non-empty folder name."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        _ = RadioManager.shared.addStation(action.station, toUserFolderID: folder.id)
        reloadInternetRadioForCurrentMode()
    }
    @objc private func contextMenuPlayPlexRadioStation(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .plexRadioStation(let radioType) = item.type else { return }
        playPlexRadioStation(radioType)
    }
    @objc private func contextMenuPlaySubsonicRadioStation(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .subsonicRadioStation(let radioType) = item.type else { return }
        playSubsonicRadioStation(radioType)
    }
    @objc private func contextMenuPlayJellyfinRadioStation(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .jellyfinRadioStation(let radioType) = item.type else { return }
        playJellyfinRadioStation(radioType)
    }
    @objc private func contextMenuPlayEmbyRadioStation(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .embyRadioStation(let radioType) = item.type else { return }
        playEmbyRadioStation(radioType)
    }
    @objc private func contextMenuPlayLocalRadioStation(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .localRadioStation(let radioType) = item.type else { return }
        playLocalRadioStation(radioType)
    }
    @objc private func contextMenuPlayMovie(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? PlexMovie else { return }; playMovie(movie)
    }
    @objc private func contextMenuPlayEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? PlexEpisode else { return }; playEpisode(episode)
    }
    @objc private func contextMenuPlayJellyfinMovie(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? JellyfinMovie else { return }; playJellyfinMovie(movie)
    }
    @objc private func contextMenuPlayJellyfinEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? JellyfinEpisode else { return }; playJellyfinEpisode(episode)
    }
    @objc private func contextMenuPlayEmbySong(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? EmbySong else { return }; playEmbySong(song)
    }
    @objc private func contextMenuPlayEmbyAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? EmbyAlbum else { return }; playEmbyAlbum(album)
    }
    @objc private func contextMenuPlayEmbyArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? EmbyArtist else { return }; playEmbyArtist(artist)
    }
    @objc private func contextMenuPlayEmbyPlaylist(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? EmbyPlaylist else { return }; playEmbyPlaylist(playlist)
    }
    @objc private func contextMenuAddEmbySongToPlaylist(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? EmbySong,
              let track = EmbyManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.appendTracks([track])
    }
    @objc private func contextMenuPlayEmbySongAlbum(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? EmbySong,
              let albumId = song.albumId else { return }
        Task { @MainActor in
            if let album = cachedEmbyAlbums.first(where: { $0.id == albumId }) {
                playEmbyAlbum(album)
            } else {
                do {
                    let (_, songs) = try await EmbyManager.shared.serverClient?.fetchAlbum(id: albumId) ?? (nil, [])
                    let tracks = EmbyManager.shared.convertToTracks(songs)
                    if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
                } catch { NSLog("Failed to fetch album: %@", error.localizedDescription) }
            }
        }
    }
    @objc private func contextMenuPlayEmbySongArtist(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? EmbySong,
              let artistId = song.artistId else { return }
        Task { @MainActor in
            if let artist = cachedEmbyArtists.first(where: { $0.id == artistId }) {
                playEmbyArtist(artist)
            } else {
                do {
                    let results = try await EmbyManager.shared.search(query: song.artist ?? "")
                    let tracks = EmbyManager.shared.convertToTracks(results.songs)
                    if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
                } catch { NSLog("Failed to fetch artist songs: %@", error.localizedDescription) }
            }
        }
    }
    @objc private func contextMenuPlayEmbyMovie(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? EmbyMovie else { return }; playEmbyMovie(movie)
    }
    @objc private func contextMenuPlayEmbyEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? EmbyEpisode else { return }; playEmbyEpisode(episode)
    }

    // MARK: - Play and Replace Queue Handlers
    
    @objc private func contextMenuPlayAndReplaceTrack(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .track(let track) = item.type,
              let t = PlexManager.shared.convertToTrack(track) else { return }
        WindowManager.shared.audioEngine.loadTracks([t])
    }
    @objc private func contextMenuPlayAlbumAndReplace(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? PlexAlbum else { return }
        Task { @MainActor in
            do {
                let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                WindowManager.shared.audioEngine.loadTracks(PlexManager.shared.convertToTracks(tracks))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayArtistAndReplace(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? PlexArtist else { return }
        Task { @MainActor in
            do {
                let all = try await self.fetchTracksForPlexArtistGroup(artist)
                WindowManager.shared.audioEngine.loadTracks(PlexManager.shared.convertToTracks(all))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayLocalTrackAndReplace(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        WindowManager.shared.audioEngine.loadTracks([track.toTrack()])
    }
    @objc private func contextMenuPlayPlaylistTrackAndReplace(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        WindowManager.shared.audioEngine.loadTracks([track])
    }
    @objc private func contextMenuPlayLocalAlbumAndReplace(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        WindowManager.shared.audioEngine.loadTracks(resolvedTracksForLocalAlbum(album).map { $0.toTrack() })
    }
    @objc private func contextMenuPlayLocalArtistAndReplace(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        var tracks: [Track] = []
        if artist.albums.isEmpty {
            let store = MediaLibraryStore.shared
            let summaries = store.albumsForArtist(artist.name)
            for summary in summaries { tracks.append(contentsOf: store.tracksForAlbum(summary.id).map { $0.toTrack() }) }
        } else {
            for album in artist.albums { tracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
        }
        WindowManager.shared.audioEngine.loadTracks(tracks)
    }
    @objc private func contextMenuPlaySubsonicSongAndReplace(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong,
              let t = SubsonicManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.loadTracks([t])
    }
    @objc private func contextMenuPlaySubsonicAlbumAndReplace(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? SubsonicAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                WindowManager.shared.audioEngine.loadTracks(songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlaySubsonicArtistAndReplace(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? SubsonicArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: artist)
                var all: [Track] = []
                for album in albums {
                    let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                    all.append(contentsOf: songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                }
                WindowManager.shared.audioEngine.loadTracks(all)
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlaySubsonicPlaylistAndReplace(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? SubsonicPlaylist else { return }
        Task { @MainActor in
            do {
                let (_, songs) = try await SubsonicManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
                WindowManager.shared.audioEngine.loadTracks(songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayJellyfinSongAndReplace(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? JellyfinSong,
              let t = JellyfinManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.loadTracks([t])
    }
    @objc private func contextMenuPlayJellyfinAlbumAndReplace(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? JellyfinAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album)
                WindowManager.shared.audioEngine.loadTracks(JellyfinManager.shared.convertToTracks(songs))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayJellyfinArtistAndReplace(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? JellyfinArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await JellyfinManager.shared.fetchAlbums(forArtist: artist)
                var all: [Track] = []
                for album in albums {
                    let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album)
                    all.append(contentsOf: JellyfinManager.shared.convertToTracks(songs))
                }
                WindowManager.shared.audioEngine.loadTracks(all)
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayJellyfinPlaylistAndReplace(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? JellyfinPlaylist else { return }
        Task { @MainActor in
            do {
                let (_, songs) = try await JellyfinManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
                WindowManager.shared.audioEngine.loadTracks(JellyfinManager.shared.convertToTracks(songs))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayEmbySongAndReplace(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? EmbySong,
              let t = EmbyManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.loadTracks([t])
    }
    @objc private func contextMenuPlayEmbyAlbumAndReplace(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? EmbyAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album)
                WindowManager.shared.audioEngine.loadTracks(EmbyManager.shared.convertToTracks(songs))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayEmbyArtistAndReplace(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? EmbyArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await EmbyManager.shared.fetchAlbums(forArtist: artist)
                var all: [Track] = []
                for album in albums {
                    let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album)
                    all.append(contentsOf: EmbyManager.shared.convertToTracks(songs))
                }
                WindowManager.shared.audioEngine.loadTracks(all)
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayEmbyPlaylistAndReplace(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? EmbyPlaylist else { return }
        Task { @MainActor in
            do {
                let (_, songs) = try await EmbyManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
                WindowManager.shared.audioEngine.loadTracks(EmbyManager.shared.convertToTracks(songs))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayPlexPlaylistAndReplace(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? PlexPlaylist else { return }
        Task { @MainActor in
            do {
                let tracks = try await PlexManager.shared.fetchPlaylistTracks(playlistID: playlist.id, smartContent: playlist.smart ? playlist.content : nil)
                WindowManager.shared.audioEngine.loadTracks(PlexManager.shared.convertToTracks(tracks))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    
    // MARK: - Play Next / Add to Queue Handlers
    
    @objc private func contextMenuPlayNext(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? PlexTrack,
              let t = PlexManager.shared.convertToTrack(track) else { return }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent([t])
    }
    @objc private func contextMenuAddToQueue(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? PlexTrack,
              let t = PlexManager.shared.convertToTrack(track) else { return }
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        engine.appendTracks([t])
        if wasEmpty { engine.playTrack(at: 0) }
    }
    @objc private func contextMenuPlayLocalTrackNext(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent([track.toTrack()])
    }
    @objc private func contextMenuAddLocalTrackToQueue(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        engine.appendTracks([track.toTrack()])
        if wasEmpty { engine.playTrack(at: 0) }
    }
    @objc private func contextMenuPlayPlaylistTrackNext(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent([track])
    }
    @objc private func contextMenuAddPlaylistTrackToQueue(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        engine.appendTracks([track])
        if wasEmpty { engine.playTrack(at: 0) }
    }

    @objc private func contextMenuPlayLocalFolder(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .localFolder(let url, _) = item.type else { return }
        collectTracksFromFolder(url) { tracks in
            WindowManager.shared.audioEngine.playNow(tracks)
        }
    }

    @objc private func contextMenuPlayLocalFolderAndReplace(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .localFolder(let url, _) = item.type else { return }
        collectTracksFromFolder(url) { tracks in
            WindowManager.shared.audioEngine.loadTracks(tracks)
        }
    }

    @objc private func contextMenuPlayLocalFolderNext(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .localFolder(let url, _) = item.type else { return }
        collectTracksFromFolder(url) { tracks in
            WindowManager.shared.audioEngine.insertTracksAfterCurrent(tracks, startPlaybackIfEmpty: false)
        }
    }

    @objc private func contextMenuAddLocalFolderToQueue(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .localFolder(let url, _) = item.type else { return }
        collectTracksFromFolder(url) { tracks in
            let engine = WindowManager.shared.audioEngine
            let wasEmpty = engine.playlist.isEmpty
            engine.appendTracks(tracks)
            if wasEmpty { engine.playTrack(at: 0) }
        }
    }

    @objc private func contextMenuRevealLocalFolderInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func contextMenuPlaySubsonicSongNext(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong,
              let track = SubsonicManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent([track])
    }
    @objc private func contextMenuAddSubsonicSongToQueue(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong,
              let track = SubsonicManager.shared.convertToTrack(song) else { return }
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        engine.appendTracks([track])
        if wasEmpty { engine.playTrack(at: 0) }
    }
    @objc private func contextMenuPlayAlbumNext(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? PlexAlbum else { return }
        Task { @MainActor in
            do {
                let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                let converted = PlexManager.shared.convertToTracks(tracks)
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(converted)
            } catch { NSLog("Failed to play album next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddAlbumToQueue(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? PlexAlbum else { return }
        Task { @MainActor in
            do {
                let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                let converted = PlexManager.shared.convertToTracks(tracks)
                let engine = WindowManager.shared.audioEngine
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(converted)
                if wasEmpty { engine.playTrack(at: 0) }
            } catch { NSLog("Failed to add album to queue: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayLocalAlbumNext(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        let tracks = resolvedTracksForLocalAlbum(album).map { $0.toTrack() }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent(tracks)
    }
    @objc private func contextMenuAddLocalAlbumToQueue(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        let tracks = resolvedTracksForLocalAlbum(album).map { $0.toTrack() }
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        engine.appendTracks(tracks)
        if wasEmpty { engine.playTrack(at: 0) }
    }
    @objc private func contextMenuPlaySubsonicAlbumNext(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? SubsonicAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                let tracks = songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(tracks)
            } catch { NSLog("Failed to play subsonic album next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddSubsonicAlbumToQueue(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? SubsonicAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                let tracks = songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                let engine = WindowManager.shared.audioEngine
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(tracks)
                if wasEmpty { engine.playTrack(at: 0) }
            } catch { NSLog("Failed to add subsonic album to queue: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayArtistNext(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? PlexArtist else { return }
        Task { @MainActor in
            do {
                let allTracks = try await self.fetchTracksForPlexArtistGroup(artist)
                let converted = PlexManager.shared.convertToTracks(allTracks)
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(converted)
            } catch { NSLog("Failed to play artist next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddArtistToQueue(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? PlexArtist else { return }
        Task { @MainActor in
            do {
                let allTracks = try await self.fetchTracksForPlexArtistGroup(artist)
                let converted = PlexManager.shared.convertToTracks(allTracks)
                let engine = WindowManager.shared.audioEngine
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(converted)
                if wasEmpty { engine.playTrack(at: 0) }
            } catch { NSLog("Failed to add artist to queue: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayLocalArtistNext(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        var allTracks: [Track] = []
        if artist.albums.isEmpty {
            let store = MediaLibraryStore.shared
            let summaries = store.albumsForArtist(artist.name)
            for summary in summaries { allTracks.append(contentsOf: store.tracksForAlbum(summary.id).map { $0.toTrack() }) }
        } else {
            for album in artist.albums { allTracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
        }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks)
    }
    @objc private func contextMenuAddLocalArtistToQueue(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        var allTracks: [Track] = []
        if artist.albums.isEmpty {
            let store = MediaLibraryStore.shared
            let summaries = store.albumsForArtist(artist.name)
            for summary in summaries { allTracks.append(contentsOf: store.tracksForAlbum(summary.id).map { $0.toTrack() }) }
        } else {
            for album in artist.albums { allTracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
        }
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        engine.appendTracks(allTracks)
        if wasEmpty { engine.playTrack(at: 0) }
    }
    @objc private func contextMenuPlaySubsonicArtistNext(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? SubsonicArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [Track] = []
                for album in albums {
                    let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                    allTracks.append(contentsOf: songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                }
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks)
            } catch { NSLog("Failed to play subsonic artist next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddSubsonicArtistToQueue(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? SubsonicArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [Track] = []
                for album in albums {
                    let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                    allTracks.append(contentsOf: songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                }
                let engine = WindowManager.shared.audioEngine
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(allTracks)
                if wasEmpty { engine.playTrack(at: 0) }
            } catch { NSLog("Failed to add subsonic artist to queue: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayJellyfinSongNext(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? JellyfinSong,
              let track = JellyfinManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent([track])
    }
    @objc private func contextMenuAddJellyfinSongToQueue(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? JellyfinSong,
              let track = JellyfinManager.shared.convertToTrack(song) else { return }
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        engine.appendTracks([track])
        if wasEmpty { engine.playTrack(at: 0) }
    }
    @objc private func contextMenuPlayJellyfinAlbumNext(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? JellyfinAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album)
                let tracks = JellyfinManager.shared.convertToTracks(songs)
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(tracks)
            } catch { NSLog("Failed to play jellyfin album next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddJellyfinAlbumToQueue(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? JellyfinAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album)
                let tracks = JellyfinManager.shared.convertToTracks(songs)
                let engine = WindowManager.shared.audioEngine
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(tracks)
                if wasEmpty { engine.playTrack(at: 0) }
            } catch { NSLog("Failed to add jellyfin album to queue: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayJellyfinArtistNext(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? JellyfinArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await JellyfinManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [Track] = []
                for album in albums {
                    let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album)
                    allTracks.append(contentsOf: JellyfinManager.shared.convertToTracks(songs))
                }
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks)
            } catch { NSLog("Failed to play jellyfin artist next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddJellyfinArtistToQueue(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? JellyfinArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await JellyfinManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [Track] = []
                for album in albums {
                    let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album)
                    allTracks.append(contentsOf: JellyfinManager.shared.convertToTracks(songs))
                }
                let engine = WindowManager.shared.audioEngine
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(allTracks)
                if wasEmpty { engine.playTrack(at: 0) }
            } catch { NSLog("Failed to add jellyfin artist to queue: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayEmbySongNext(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? EmbySong,
              let track = EmbyManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent([track])
    }
    @objc private func contextMenuAddEmbySongToQueue(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? EmbySong,
              let track = EmbyManager.shared.convertToTrack(song) else { return }
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        engine.appendTracks([track])
        if wasEmpty { engine.playTrack(at: 0) }
    }
    @objc private func contextMenuPlayEmbyAlbumNext(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? EmbyAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album)
                let tracks = EmbyManager.shared.convertToTracks(songs)
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(tracks)
            } catch { NSLog("Failed to play emby album next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddEmbyAlbumToQueue(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? EmbyAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album)
                let tracks = EmbyManager.shared.convertToTracks(songs)
                let engine = WindowManager.shared.audioEngine
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(tracks)
                if wasEmpty { engine.playTrack(at: 0) }
            } catch { NSLog("Failed to add emby album to queue: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuPlayEmbyArtistNext(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? EmbyArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await EmbyManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [Track] = []
                for album in albums {
                    let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album)
                    allTracks.append(contentsOf: EmbyManager.shared.convertToTracks(songs))
                }
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks)
            } catch { NSLog("Failed to play emby artist next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddEmbyArtistToQueue(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? EmbyArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await EmbyManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [Track] = []
                for album in albums {
                    let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album)
                    allTracks.append(contentsOf: EmbyManager.shared.convertToTracks(songs))
                }
                let engine = WindowManager.shared.audioEngine
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(allTracks)
                if wasEmpty { engine.playTrack(at: 0) }
            } catch { NSLog("Failed to add emby artist to queue: %@", error.localizedDescription) }
        }
    }

    // MARK: - Keyboard Shortcut Helpers
    
    private func playNextSelected() {
        guard let index = selectedIndices.first, index < displayItems.count else { return }
        let item = displayItems[index]
        switch item.type {
        case .track(let track):
            if let t = PlexManager.shared.convertToTrack(track) {
                WindowManager.shared.audioEngine.insertTracksAfterCurrent([t], startPlaybackIfEmpty: false)
            }
        case .localTrack(let track):
            WindowManager.shared.audioEngine.insertTracksAfterCurrent([track.toTrack()], startPlaybackIfEmpty: false)
        case .subsonicTrack(let song):
            if let track = SubsonicManager.shared.convertToTrack(song) {
                WindowManager.shared.audioEngine.insertTracksAfterCurrent([track], startPlaybackIfEmpty: false)
            }
        case .album(let album):
            Task { @MainActor in
                if let tracks = try? await PlexManager.shared.fetchTracks(forAlbum: album) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(PlexManager.shared.convertToTracks(tracks), startPlaybackIfEmpty: false)
                }
            }
        case .localAlbum(let album):
            WindowManager.shared.audioEngine.insertTracksAfterCurrent(resolvedTracksForLocalAlbum(album).map { $0.toTrack() }, startPlaybackIfEmpty: false)
        case .localFolder(let url, _):
            collectTracksFromFolder(url) { tracks in
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(tracks, startPlaybackIfEmpty: false)
            }
        case .subsonicAlbum(let album):
            Task { @MainActor in
                if let songs = try? await SubsonicManager.shared.fetchSongs(forAlbum: album) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(songs.compactMap { SubsonicManager.shared.convertToTrack($0) }, startPlaybackIfEmpty: false)
                }
            }
        case .artist(let artist):
            Task { @MainActor in
                if let allTracks = try? await self.fetchTracksForPlexArtistGroup(artist) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(PlexManager.shared.convertToTracks(allTracks), startPlaybackIfEmpty: false)
                }
            }
        case .localArtist(let artist):
            var allTracks: [Track] = []
            if artist.albums.isEmpty {
                let store = MediaLibraryStore.shared
                let summaries = store.albumsForArtist(artist.name).sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) })
                for summary in summaries { allTracks.append(contentsOf: store.tracksForAlbum(summary.id).map { $0.toTrack() }) }
            } else {
                for album in artist.albums.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) { allTracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
            }
            WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks, startPlaybackIfEmpty: false)
        case .subsonicArtist(let artist):
            Task { @MainActor in
                if let albums = try? await SubsonicManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [Track] = []
                    for album in albums.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                        if let songs = try? await SubsonicManager.shared.fetchSongs(forAlbum: album) {
                            allTracks.append(contentsOf: songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                        }
                    }
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks, startPlaybackIfEmpty: false)
                }
            }
        case .jellyfinTrack(let song):
            if let track = JellyfinManager.shared.convertToTrack(song) {
                WindowManager.shared.audioEngine.insertTracksAfterCurrent([track], startPlaybackIfEmpty: false)
            }
        case .jellyfinAlbum(let album):
            Task { @MainActor in
                if let songs = try? await JellyfinManager.shared.fetchSongs(forAlbum: album) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(JellyfinManager.shared.convertToTracks(songs), startPlaybackIfEmpty: false)
                }
            }
        case .jellyfinArtist(let artist):
            Task { @MainActor in
                if let albums = try? await JellyfinManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [Track] = []
                    for album in albums.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                        if let songs = try? await JellyfinManager.shared.fetchSongs(forAlbum: album) {
                            allTracks.append(contentsOf: JellyfinManager.shared.convertToTracks(songs))
                        }
                    }
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks, startPlaybackIfEmpty: false)
                }
            }
        case .embyTrack(let song):
            if let track = EmbyManager.shared.convertToTrack(song) {
                WindowManager.shared.audioEngine.insertTracksAfterCurrent([track], startPlaybackIfEmpty: false)
            }
        case .embyAlbum(let album):
            Task { @MainActor in
                if let songs = try? await EmbyManager.shared.fetchSongs(forAlbum: album) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(EmbyManager.shared.convertToTracks(songs), startPlaybackIfEmpty: false)
                }
            }
        case .embyArtist(let artist):
            Task { @MainActor in
                if let albums = try? await EmbyManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [Track] = []
                    for album in albums.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                        if let songs = try? await EmbyManager.shared.fetchSongs(forAlbum: album) {
                            allTracks.append(contentsOf: EmbyManager.shared.convertToTracks(songs))
                        }
                    }
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks, startPlaybackIfEmpty: false)
                }
            }
        case .subsonicPlaylist(let playlist):
            Task { @MainActor in
                if let (_, songs) = try? await SubsonicManager.shared.serverClient?.fetchPlaylist(id: playlist.id) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(songs.compactMap { SubsonicManager.shared.convertToTrack($0) }, startPlaybackIfEmpty: false)
                }
            }
        case .jellyfinPlaylist(let playlist):
            Task { @MainActor in
                if let (_, songs) = try? await JellyfinManager.shared.serverClient?.fetchPlaylist(id: playlist.id) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(JellyfinManager.shared.convertToTracks(songs), startPlaybackIfEmpty: false)
                }
            }
        case .embyPlaylist(let playlist):
            Task { @MainActor in
                if let (_, songs) = try? await EmbyManager.shared.serverClient?.fetchPlaylist(id: playlist.id) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(EmbyManager.shared.convertToTracks(songs), startPlaybackIfEmpty: false)
                }
            }
        case .plexPlaylist(let playlist):
            Task { @MainActor in
                if let tracks = try? await PlexManager.shared.fetchPlaylistTracks(playlistID: playlist.id, smartContent: playlist.smart ? playlist.content : nil) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(PlexManager.shared.convertToTracks(tracks), startPlaybackIfEmpty: false)
                }
            }
        default: break
        }
    }

    private func addSelectedToQueue() {
        guard let index = selectedIndices.first, index < displayItems.count else { return }
        let item = displayItems[index]
        let engine = WindowManager.shared.audioEngine

        switch item.type {
        case .track(let track):
            if let t = PlexManager.shared.convertToTrack(track) { engine.appendTracks([t]) }
        case .localTrack(let track):
            engine.appendTracks([track.toTrack()])
        case .subsonicTrack(let song):
            if let track = SubsonicManager.shared.convertToTrack(song) { engine.appendTracks([track]) }
        case .album(let album):
            Task { @MainActor in
                if let tracks = try? await PlexManager.shared.fetchTracks(forAlbum: album) {
                    engine.appendTracks(PlexManager.shared.convertToTracks(tracks))
                }
            }
        case .localAlbum(let album):
            engine.appendTracks(resolvedTracksForLocalAlbum(album).map { $0.toTrack() })
        case .localFolder(let url, _):
            collectTracksFromFolder(url) { tracks in
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks(tracks)
                if wasEmpty { engine.playTrack(at: 0) }
            }
        case .subsonicAlbum(let album):
            Task { @MainActor in
                if let songs = try? await SubsonicManager.shared.fetchSongs(forAlbum: album) {
                    engine.appendTracks(songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                }
            }
        case .artist(let artist):
            Task { @MainActor in
                if let allTracks = try? await self.fetchTracksForPlexArtistGroup(artist) {
                    engine.appendTracks(PlexManager.shared.convertToTracks(allTracks))
                }
            }
        case .localArtist(let artist):
            var allTracks: [Track] = []
            if artist.albums.isEmpty {
                let store = MediaLibraryStore.shared
                let summaries = store.albumsForArtist(artist.name).sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) })
                for summary in summaries { allTracks.append(contentsOf: store.tracksForAlbum(summary.id).map { $0.toTrack() }) }
            } else {
                for album in artist.albums.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) { allTracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
            }
            engine.appendTracks(allTracks)
        case .subsonicArtist(let artist):
            Task { @MainActor in
                if let albums = try? await SubsonicManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [Track] = []
                    for album in albums.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                        if let songs = try? await SubsonicManager.shared.fetchSongs(forAlbum: album) {
                            allTracks.append(contentsOf: songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                        }
                    }
                    engine.appendTracks(allTracks)
                }
            }
        case .jellyfinTrack(let song):
            if let track = JellyfinManager.shared.convertToTrack(song) { engine.appendTracks([track]) }
        case .jellyfinAlbum(let album):
            Task { @MainActor in
                if let songs = try? await JellyfinManager.shared.fetchSongs(forAlbum: album) {
                    engine.appendTracks(JellyfinManager.shared.convertToTracks(songs))
                }
            }
        case .jellyfinArtist(let artist):
            Task { @MainActor in
                if let albums = try? await JellyfinManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [Track] = []
                    for album in albums.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                        if let songs = try? await JellyfinManager.shared.fetchSongs(forAlbum: album) {
                            allTracks.append(contentsOf: JellyfinManager.shared.convertToTracks(songs))
                        }
                    }
                    engine.appendTracks(allTracks)
                }
            }
        case .embyTrack(let song):
            if let track = EmbyManager.shared.convertToTrack(song) { engine.appendTracks([track]) }
        case .embyAlbum(let album):
            Task { @MainActor in
                if let songs = try? await EmbyManager.shared.fetchSongs(forAlbum: album) {
                    engine.appendTracks(EmbyManager.shared.convertToTracks(songs))
                }
            }
        case .embyArtist(let artist):
            Task { @MainActor in
                if let albums = try? await EmbyManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [Track] = []
                    for album in albums.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                        if let songs = try? await EmbyManager.shared.fetchSongs(forAlbum: album) {
                            allTracks.append(contentsOf: EmbyManager.shared.convertToTracks(songs))
                        }
                    }
                    engine.appendTracks(allTracks)
                }
            }
        case .subsonicPlaylist(let playlist):
            Task { @MainActor in
                if let (_, songs) = try? await SubsonicManager.shared.serverClient?.fetchPlaylist(id: playlist.id) {
                    engine.appendTracks(songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                }
            }
        case .jellyfinPlaylist(let playlist):
            Task { @MainActor in
                if let (_, songs) = try? await JellyfinManager.shared.serverClient?.fetchPlaylist(id: playlist.id) {
                    engine.appendTracks(JellyfinManager.shared.convertToTracks(songs))
                }
            }
        case .embyPlaylist(let playlist):
            Task { @MainActor in
                if let (_, songs) = try? await EmbyManager.shared.serverClient?.fetchPlaylist(id: playlist.id) {
                    engine.appendTracks(EmbyManager.shared.convertToTracks(songs))
                }
            }
        case .plexPlaylist(let playlist):
            Task { @MainActor in
                if let tracks = try? await PlexManager.shared.fetchPlaylistTracks(playlistID: playlist.id, smartContent: playlist.smart ? playlist.content : nil) {
                    engine.appendTracks(PlexManager.shared.convertToTracks(tracks))
                }
            }
        default: break
        }
    }

    // MARK: - Notification Handlers
    
    private func invalidateServerBarFontCache() {
        cachedServerBarFont = nil
        cachedServerBarFontSkinName = nil
        cachedServerBarFontScale = nil
        cachedServerBarIsMetal = nil
        cachedPrefixAttrs = nil
        cachedDataAttrs = nil
        cachedActiveAttrs = nil
    }

    @objc private func modernSkinDidChange() {
        let skin = currentSkin()
        renderer = ModernSkinRenderer(skin: skin)
        historyHostingView?.rootView = StatsContentView(agent: historyAgent,
                                                        skinTextColor: Color(skin.textColor),
                                                        headerTitle: "Library Data")
        historyHostingView?.appearance = skinAppearance(for: skin)
        historyHostingView?.layer?.backgroundColor = skin.backgroundColor.withAlphaComponent(1.0).cgColor
        invalidateServerBarFontCache()
        updateCornerMask()
        updateEmbeddedSubviewFrames()
        compactPlayerBar?.skinDidChange()
        needsDisplay = true
    }
    
    @objc private func doubleSizeChanged() {
        modernSkinDidChange()
    }

    @objc private func playHistoryDidChange() {
        Task { @MainActor [weak self] in
            guard let self, self.browseMode.isHistoryMode else { return }
            self.historyAgent.scheduleRefresh()
        }
    }
    
    @objc private func windowLayoutDidChange() {
        guard let window = window else { return }
        let newEdges = WindowManager.shared.computeAdjacentEdges(for: window)
        let newSharp = WindowManager.shared.computeSharpCorners(for: window)
        let newSegments = WindowManager.shared.computeEdgeOcclusionSegments(for: window)
        let seamless = min(1.0, max(0.0, ModernSkinEngine.shared.currentSkin?.config.window.seamlessDocking ?? 0))
        let shouldHaveShadow = !(seamless > 0 && !newEdges.isEmpty)
        if window.hasShadow != shouldHaveShadow {
            window.hasShadow = shouldHaveShadow
            window.invalidateShadow()
        }
        if newEdges != adjacentEdges || newSharp != sharpCorners || newSegments != edgeOcclusionSegments {
            adjacentEdges = newEdges
            sharpCorners = newSharp
            edgeOcclusionSegments = newSegments
            needsDisplay = true
        }
        updateEmbeddedSubviewFrames()
    }

    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if isHighlighted != newValue {
            isHighlighted = newValue
            needsDisplay = true
        }
    }

    func skinDidChange() { modernSkinDidChange() }

    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        updateHistoryHostingVisibility()
        needsDisplay = true
    }
    
    private func toggleShadeMode() {
        guard !compactMode else { return }
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    @objc private func plexStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, case .plex = self.currentSource else { return }
            if case .connecting = PlexManager.shared.connectionState {
                self.isLoading = true; self.errorMessage = nil; self.needsDisplay = true; return
            }
            self.reloadData()
        }
    }
    
    @objc private func plexServerDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if case .connecting = PlexManager.shared.connectionState { self.needsDisplay = true; return }
            if !self.currentSource.isPlex && self.pendingSourceRestore == nil { return }
            
            if let pending = self.pendingSourceRestore {
                self.pendingSourceRestore = nil
                switch pending {
                case .plex(let serverId):
                    if PlexManager.shared.servers.contains(where: { $0.id == serverId }) { self.currentSource = pending; return }
                    else if let first = PlexManager.shared.servers.first { self.currentSource = .plex(serverId: first.id); return }
                case .subsonic(let serverId):
                    if SubsonicManager.shared.servers.contains(where: { $0.id == serverId }) { self.currentSource = pending; return }
                    else if let first = SubsonicManager.shared.servers.first { self.currentSource = .subsonic(serverId: first.id); return }
                case .jellyfin(let serverId):
                    if JellyfinManager.shared.servers.contains(where: { $0.id == serverId }) { self.currentSource = pending; return }
                    else if let first = JellyfinManager.shared.servers.first { self.currentSource = .jellyfin(serverId: first.id); return }
                case .emby(let serverId):
                    if EmbyManager.shared.servers.contains(where: { $0.id == serverId }) { self.currentSource = pending; return }
                    else if let first = EmbyManager.shared.servers.first { self.currentSource = .emby(serverId: first.id); return }
                case .local: break
                case .radio: self.currentSource = .radio; return
                case .youtube: self.currentSource = .youtube; return
                }
            }
            self.clearAllCachedData(); self.reloadData()
        }
    }
    
    @objc private func plexContentDidPreload() {
        guard case .plex = currentSource else { return }
        reloadData()
    }
    
    @objc private func jellyfinMusicLibraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, case .jellyfin = self.currentSource else { return }
            self.clearAllCachedData(); self.reloadData()
        }
    }
    
    @objc private func jellyfinVideoLibraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, case .jellyfin = self.currentSource, self.browseMode.isVideoMode else { return }
            self.cachedJellyfinMovies = []; self.cachedJellyfinShows = []
            self.reloadData()
        }
    }

    @objc private func embyMusicLibraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, case .emby = self.currentSource else { return }
            self.clearAllCachedData(); self.reloadData()
        }
    }

    @objc private func embyVideoLibraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, case .emby = self.currentSource, self.browseMode.isVideoMode else { return }
            self.cachedEmbyMovies = []; self.cachedEmbyShows = []
            self.reloadData()
        }
    }

    @objc private func embyLibraryContentDidPreload() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, case .emby = self.currentSource else { return }
            self.reloadData()
        }
    }

    @objc private func embyConnectionStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, case .emby = self.currentSource else { return }
            self.reloadData()
        }
    }
    
    @objc private func subsonicMusicFolderDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, case .subsonic = self.currentSource else { return }
            self.clearAllCachedData(); self.reloadData()
        }
    }
    
    @objc private func mediaLibraryDidChange() {
        guard case .local = currentSource, !browseMode.isRadioMode, !browseMode.isHistoryMode else { return }
        localLibraryReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self,
                  case .local = self.currentSource,
                  !self.browseMode.isRadioMode,
                  !self.browseMode.isHistoryMode else { return }
            self.loadLocalData()
            self.needsDisplay = true
        }
        localLibraryReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: workItem)
    }
    
    private var isShowingInternetRadioContent: Bool {
        currentSource.isRadio ||
            (currentSource.isYouTube &&
             (browseMode == .search || (browseMode == .radio && !radioSlotShowsChannels)))
    }

    @objc private func radioStationsDidChange() {
        guard isShowingInternetRadioContent else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch self.browseMode {
            case .radio:
                self.loadRadioStations()
            case .search:
                self.loadRadioSearchResults()
            default:
                break
            }
            self.needsDisplay = true
        }
    }

    @objc private func youtubeChannelsDidChange() {
        guard case .youtube = currentSource else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rebuildCurrentModeItems()
        }
    }

    @objc private func youtubeVideoLimitDidChange() {
        // Drop cached video lists so the new limit applies. Re-fetch the channels that are
        // currently expanded; otherwise just collapse them so a later expand fetches fresh.
        youtubeChannelVideos.removeAll()
        if case .youtube = currentSource {
            reloadExpandedYouTubeChannels()
        } else {
            expandedYouTubeChannels.removeAll()
        }
    }

    /// Re-fetch the uploads for every currently-expanded YouTube channel (sequentially, in
    /// one task) and rebuild as each arrives. Used when the per-channel video limit changes.
    private func reloadExpandedYouTubeChannels() {
        let channels = YouTubeManager.shared.channels.filter { expandedYouTubeChannels.contains($0.id) }
        guard !channels.isEmpty else { rebuildCurrentModeItems(); return }
        youtubeExpandTask?.cancel()
        loadingChannelIds.formUnion(channels.map { $0.id }); startLoadingAnimation()
        youtubeExpandTask = Task.detached { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
                for ch in channels { self.loadingChannelIds.remove(ch.id) }
                self.stopLoadingAnimation(); self.needsDisplay = true
            }
            for ch in channels {
                do {
                    let videos = try await YouTubeManager.shared.videos(forChannel: ch)
                    youtubeChannelVideos[ch.id] = videos
                    loadingChannelIds.remove(ch.id)
                    rebuildCurrentModeItems()
                } catch is CancellationError { return }
                catch where Task.isCancelled { return }
                catch {
                    loadingChannelIds.remove(ch.id)
                    NSLog("Failed to reload YouTube videos for channel '%@': %@", ch.title, error.localizedDescription)
                }
            }
        }
        rebuildCurrentModeItems(); needsDisplay = true
    }

    @objc private func trackDidChange(_ notification: Notification) {
        artModeLifecycleGeneration &+= 1
        let generation = artModeLifecycleGeneration
        let track = notification.userInfo?["track"] as? Track

        if isArtOnlyMode {
            guard track != nil else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          self.artModeLifecycleGeneration == generation,
                          self.isArtOnlyMode,
                          WindowManager.shared.audioEngine.currentTrack == nil else { return }
                    self.exitArtOnlyModeForMissingArtwork()
                }
                return
            }

            // Art-only mode uses loadAllArtworkForCurrentTrack exclusively.
            // Don't also call loadArtwork(for:) to avoid a race where loadArtwork
            // finishes last with nil and overwrites valid artwork.
            fetchCurrentTrackRating()
            loadAllArtworkForCurrentTrack()
            return
        }
        guard WindowManager.shared.showBrowserArtworkBackground else {
            if currentArtwork != nil { currentArtwork = nil; artworkTrackId = nil; needsDisplay = true }; return
        }
        loadArtwork(for: track)
    }
    
    @objc private func handleSetBrowserSource(_ notification: Notification) {
        // Map from classic BrowserSource (posted by ContextMenuBuilder) to ModernBrowserSource
        guard let source = notification.object as? BrowserSource else { return }
        switch source {
        case .local: currentSource = .local
        case .plex(let serverId): currentSource = .plex(serverId: serverId)
        case .subsonic(let serverId): currentSource = .subsonic(serverId: serverId)
        case .jellyfin(let serverId): currentSource = .jellyfin(serverId: serverId)
        case .emby(let serverId): currentSource = .emby(serverId: serverId)
        case .radio: currentSource = .radio
        case .youtube: currentSource = .youtube
        }
    }

    @objc private func windowDidMiniaturize(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        stopServerNameScroll()
        if isVisualizingArt { visualizerWasActiveBeforeHide = true; stopVisualizerTimer() }
    }
    
    @objc private func windowDidDeminiaturize(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        startServerNameScroll()
        if visualizerWasActiveBeforeHide && isVisualizingArt { startVisualizerTimer() }
        visualizerWasActiveBeforeHide = false
    }
    
    @objc private func windowDidChangeOcclusionState(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        if window?.occlusionState.contains(.visible) == true {
            startServerNameScroll()
            if isVisualizingArt && visualizerTimer == nil { startVisualizerTimer() }
        } else {
            stopServerNameScroll()
            if visualizerTimer != nil { visualizerWasActiveBeforeHide = isVisualizingArt; stopVisualizerTimer() }
        }
    }
    
    // MARK: - Source Changed
    
    @discardableResult
    private func invalidateActiveLoads() -> Int {
        loadGeneration &+= 1
        sourceConnectTask?.cancel(); sourceConnectTask = nil
        plexLoadTask?.cancel(); plexLoadTask = nil
        subsonicLoadTask?.cancel(); subsonicLoadTask = nil
        jellyfinLoadTask?.cancel(); jellyfinLoadTask = nil
        embyLoadTask?.cancel(); embyLoadTask = nil
        radioLoadTask?.cancel(); radioLoadTask = nil
        jellyfinAlbumWarmTask?.cancel(); jellyfinAlbumWarmTask = nil
        subsonicExpandTask?.cancel(); subsonicExpandTask = nil
        jellyfinExpandTask?.cancel(); jellyfinExpandTask = nil
        embyExpandTask?.cancel(); embyExpandTask = nil
        return loadGeneration
    }
    
    private func isLoadContextActive(_ generation: Int, source expectedSource: ModernBrowserSource) -> Bool {
        generation == loadGeneration && currentSource == expectedSource
    }
    
    private func setLoadErrorIfActive(_ message: String, generation: Int, source expectedSource: ModernBrowserSource) {
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        isLoading = false
        stopLoadingAnimation()
        errorMessage = message
        needsDisplay = true
    }
    
    private func finishLoadIfActive(generation: Int, source expectedSource: ModernBrowserSource) {
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        isLoading = false
        stopLoadingAnimation()
        errorMessage = nil
        // Apply any active column-header sort so a fresh server load matches what an
        // expand-driven rebuild produces — otherwise expanding a row would re-order the
        // list. (Mirrors rebuildCurrentModeItems.)
        if columnSortId != nil { applyColumnSort() }
        applyPendingArtistScroll()
        needsDisplay = true
    }
    
    private func onSourceChanged() {
        // Changing source always exits Art view.
        isArtOnlyMode = false
        invalidateActiveLoads()
        if browseMode == .folders && !isLocalSource {
            browseMode = .plists
        }
        clearAllCachedData(); clearLocalCachedData()
        displayItems.removeAll(); selectedIndices.removeAll()
        scrollOffset = 0; errorMessage = nil; isLoading = false; stopLoadingAnimation()
        // Internet Radio only has radio/search content, but every library
        // source supports the Radio tab. Preserve Radio across source changes.
        // YouTube reuses the Radio tab to list its channels, so force it too.
        if !browseMode.isHistoryMode, currentSource.usesRadioTab {
            browseMode = .radio
        }
        reloadData()
        startServerNameScroll()
    }
    
    private func clearLocalCachedData() {
        localArtistPageOffset = 0; localAlbumPageOffset = 0
        localArtistTotal = 0; localAlbumTotal = 0
        cachedLocalMovies = []; cachedLocalShows = []
        expandedLocalArtists = []; expandedLocalAlbums = []
        expandedLocalShows = []; expandedLocalSeasons = []
        expandedLocalFolders = []
    }
    
    private func clearAllCachedData() {
        jellyfinAlbumWarmTask?.cancel()
        jellyfinAlbumWarmTask = nil
        cachedArtists = []; cachedAlbums = []; cachedTracks = []
        artistAlbums = [:]; albumTracks = [:]; artistAlbumCounts = [:]
        expandedArtists = []; expandedAlbums = []
        cachedMovies = []; cachedShows = []; showSeasons = [:]; seasonEpisodes = [:]
        expandedShows = []; expandedSeasons = []
        cachedPlexPlaylists = []; plexPlaylistTracks = [:]; expandedPlexPlaylists = []
        cachedJellyfinArtists = []; cachedJellyfinAlbums = []; cachedJellyfinPlaylists = []
        jellyfinArtistAlbums = [:]; jellyfinAlbumSongs = [:]; jellyfinPlaylistTracks = [:]
        expandedJellyfinArtists = []; expandedJellyfinAlbums = []; expandedJellyfinPlaylists = []
        cachedJellyfinMovies = []; cachedJellyfinShows = []
        jellyfinShowSeasons = [:]; jellyfinSeasonEpisodes = [:]
        expandedJellyfinShows = []; expandedJellyfinSeasons = []
        cachedEmbyArtists = []; cachedEmbyAlbums = []; cachedEmbyPlaylists = []
        embyArtistAlbums = [:]; embyAlbumSongs = [:]; embyPlaylistTracks = [:]
        expandedEmbyArtists = []; expandedEmbyAlbums = []; expandedEmbyPlaylists = []
        cachedEmbyMovies = []; cachedEmbyShows = []
        embyShowSeasons = [:]; embySeasonEpisodes = [:]
        expandedEmbyShows = []; expandedEmbySeasons = []
        cachedRadioStations = []
        cachedRadioFolders = []
        searchResults = nil
    }
    
    // MARK: - Loading Animation
    
    private func startLoadingAnimation() {
        guard loadingAnimationTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadingAnimationFrame += 1
            if self.isLoading {
                self.needsDisplay = true
            } else if !self.downloadingVideoIds.isEmpty || !self.loadingChannelIds.isEmpty {
                // Redraw the list area for the per-row download/channel-load spinner(s)
                self.needsDisplay = true
            } else if self.isLibraryScanning {
                // Redraw server bar only for the scan spinner
                let serverBarY = self.topChromeBottomY - Layout.serverBarHeight
                self.setNeedsDisplay(NSRect(x: 0, y: serverBarY, width: self.bounds.width, height: Layout.serverBarHeight))
            } else {
                self.stopLoadingAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common); loadingAnimationTimer = timer
    }

    private func stopLoadingAnimation(force: Bool = false) {
        guard force || (!isLibraryScanning && downloadingVideoIds.isEmpty && loadingChannelIds.isEmpty) else { return }
        loadingAnimationTimer?.invalidate(); loadingAnimationTimer = nil; loadingAnimationFrame = 0
    }

    @objc private func libraryScanProgressChanged() {
        let scanning = MediaLibrary.shared.isScanning
        guard scanning != isLibraryScanning else { return }
        isLibraryScanning = scanning
        if scanning {
            startLoadingAnimation()
        } else {
            if !isLoading { stopLoadingAnimation() }
            needsDisplay = true
        }
    }
    
    /// Returns the display name of the currently relevant Jellyfin library based on browse mode.
    private var jellyfinCurrentLibraryName: String {
        let mgr = JellyfinManager.shared
        switch browseMode {
        case .movies: return mgr.currentMovieLibrary?.name ?? "All"
        case .shows:  return mgr.currentShowLibrary?.name ?? "All"
        default:      return mgr.currentMusicLibrary?.name ?? "All"
        }
    }

    /// Returns the display name of the currently relevant Emby library based on browse mode.
    private var embyCurrentLibraryName: String {
        let mgr = EmbyManager.shared
        switch browseMode {
        case .movies: return mgr.currentMovieLibrary?.name ?? "All"
        case .shows:  return mgr.currentShowLibrary?.name ?? "All"
        default:      return mgr.currentMusicLibrary?.name ?? "All"
        }
    }

    // MARK: - Server Name Scroll
    
    private func startServerNameScroll() {
        guard serverScrollTimer == nil else { return }
        serverScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.067, repeats: true) { [weak self] _ in
            self?.handleServerNameScrollTick()
        }
    }

    private func stopServerNameScroll() {
        serverScrollTimer?.invalidate(); serverScrollTimer = nil
        serverNameScrollOffset = 0; libraryNameScrollOffset = 0
    }

    private func handleServerNameScrollTick() {
        guard let window = window,
              window.isVisible,
              window.occlusionState.contains(.visible) else { return }
        updateServerNameScroll()
    }

    private func updateServerNameScroll() {
        // serverNameMaxWidth / serverNameTextWidth are written by drawServerBar each draw cycle.
        // If nothing has been drawn yet (both zero) there is nothing to scroll.
        guard serverNameMaxWidth > 0 else { stopServerNameScroll(); return }

        // Local and Radio sources have fixed short labels — no scrolling needed.
        switch currentSource {
        case .local, .radio:
            let hadOffset = serverNameScrollOffset != 0 || libraryNameScrollOffset != 0
            stopServerNameScroll()
            if hadOffset { setNeedsDisplay(serverBarRect()) }
            return
        default: break
        }

        let currentServerName: String
        let currentLibraryName: String
        switch currentSource {
        case .plex(let id):
            let mgr = PlexManager.shared
            let server = mgr.servers.first(where: { $0.id == id })
            currentServerName = server?.name ?? "Select Server"
            currentLibraryName = mgr.currentLibrary?.title ?? "Select"
        case .subsonic(let id):
            let server = SubsonicManager.shared.servers.first(where: { $0.id == id })
            currentServerName = server?.name ?? "Select Server"
            currentLibraryName = SubsonicManager.shared.currentMusicFolder?.name ?? "All"
        case .jellyfin(let id):
            let server = JellyfinManager.shared.servers.first(where: { $0.id == id })
            currentServerName = server?.name ?? "Select Server"
            currentLibraryName = jellyfinCurrentLibraryName
        case .emby(let id):
            let server = EmbyManager.shared.servers.first(where: { $0.id == id })
            currentServerName = server?.name ?? "Select Server"
            currentLibraryName = embyCurrentLibraryName
        default:
            stopServerNameScroll()
            return
        }

        // Reset offsets when names change.
        if currentServerName != lastServerName {
            lastServerName = currentServerName
            serverNameScrollOffset = 0
        }
        if currentLibraryName != lastLibraryName {
            lastLibraryName = currentLibraryName
            libraryNameScrollOffset = 0
        }

        let serverNeedsScroll = serverNameTextWidth > serverNameMaxWidth
        let libraryNeedsScroll = libraryNameMaxWidth > 0 && libraryNameTextWidth > libraryNameMaxWidth

        if !serverNeedsScroll && !libraryNeedsScroll {
            let hadOffset = serverNameScrollOffset != 0 || libraryNameScrollOffset != 0
            stopServerNameScroll()
            if hadOffset { setNeedsDisplay(serverBarRect()) }
            return
        }

        var needsRedraw = false

        if serverNeedsScroll {
            let separator: CGFloat = serverNameTextWidth * 0.3  // ~30% gap
            let totalCycle = serverNameTextWidth + separator
            serverNameScrollOffset += 1
            if serverNameScrollOffset >= totalCycle { serverNameScrollOffset = 0 }
            needsRedraw = true
        } else if serverNameScrollOffset != 0 {
            serverNameScrollOffset = 0; needsRedraw = true
        }

        if libraryNeedsScroll {
            let separator: CGFloat = libraryNameTextWidth * 0.3
            let totalCycle = libraryNameTextWidth + separator
            libraryNameScrollOffset += 1
            if libraryNameScrollOffset >= totalCycle { libraryNameScrollOffset = 0 }
            needsRedraw = true
        } else if libraryNameScrollOffset != 0 {
            libraryNameScrollOffset = 0; needsRedraw = true
        }

        if needsRedraw { setNeedsDisplay(serverBarRect()) }
    }

    /// Returns the rect of the server bar for targeted redraws.
    private func serverBarRect() -> NSRect {
        let barY = topChromeBottomY - Layout.serverBarHeight
        return NSRect(x: 0, y: barY, width: bounds.width, height: Layout.serverBarHeight)
    }

    // MARK: - Visualizer Timer
    
    private func startVisualizerTimer() {
        visualizerTime = 0; silenceFrames = 0; visualizerTimer?.invalidate()
        setVisualizerConsumerRegistered(true)
        let timer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in self?.handleVisualizerTimerTick() }
        RunLoop.main.add(timer, forMode: .common); visualizerTimer = timer
        if visMode == .cycle { startCycleTimer() }
    }
    
    private func handleVisualizerTimerTick() {
        guard let window = window, window.isVisible, window.occlusionState.contains(.visible) else { return }
        visualizerTime += 1.0/30.0
        let spectrumData = WindowManager.shared.audioEngine.spectrumData
        let currentLevel = spectrumData.reduce(0, +) / Float(spectrumData.count)
        let isPlaying = WindowManager.shared.audioEngine.state == .playing
        if currentLevel < 0.001 {
            silenceFrames += 1
            // Only skip redraws during silence when audio is NOT playing.
            // When playing, streaming audio may still be buffering (no spectrum data yet)
            // so we keep redrawing to show time-based effects on the artwork.
            if silenceFrames > 15 && !isPlaying { return }
        } else {
            silenceFrames = 0
            if visMode == .random {
                let bass = spectrumData.prefix(10).reduce(0, +) / 10.0
                if bass > 0.5 && visualizerTime - lastBeatTime > 0.3 {
                    lastBeatTime = visualizerTime
                    if Double.random(in: 0...1) < 0.3 { currentVisEffect = VisEffect.allCases.randomElement() ?? .psychedelic }
                }
            }
        }
        lastAudioLevel = currentLevel
        needsDisplay = true
    }
    
    private func stopVisualizerTimer() {
        visualizerTimer?.invalidate(); visualizerTimer = nil
        cycleTimer?.invalidate(); cycleTimer = nil
        setVisualizerConsumerRegistered(false)
    }

    private func setVisualizerConsumerRegistered(_ registered: Bool) {
        guard registered != isVisualizerConsumerRegistered else { return }
        isVisualizerConsumerRegistered = registered
        if registered {
            WindowManager.shared.audioEngine.addSpectrumConsumer("modernLibraryBrowserVisualizer")
        } else {
            WindowManager.shared.audioEngine.removeSpectrumConsumer("modernLibraryBrowserVisualizer")
        }
    }
    
    private func startCycleTimer() {
        cycleTimer?.invalidate()
        let timer = Timer(timeInterval: cycleInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.visMode == .cycle else { return }
            let effects = VisEffect.allCases
            if let idx = effects.firstIndex(of: self.currentVisEffect) {
                self.currentVisEffect = effects[(idx + 1) % effects.count]
            }
        }
        RunLoop.main.add(timer, forMode: .common); cycleTimer = timer
    }
    
    func toggleVisualization() {
        guard isArtOnlyMode && currentArtwork != nil else { return }
        isVisualizingArt.toggle()
    }
    
    private func nextVisEffect() {
        visMode = .single
        let effects = VisEffect.allCases
        if let idx = effects.firstIndex(of: currentVisEffect) { currentVisEffect = effects[(idx + 1) % effects.count] }
    }
    
    private func prevVisEffect() {
        visMode = .single
        let effects = VisEffect.allCases
        if let idx = effects.firstIndex(of: currentVisEffect) { currentVisEffect = effects[(idx - 1 + effects.count) % effects.count] }
    }
    
    // MARK: - Rating
    
    private lazy var ratingOverlay: RatingOverlayView = {
        let overlay = RatingOverlayView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]; overlay.isHidden = true
        overlay.onRatingSelected = { [weak self] rating in self?.submitRating(rating) }
        overlay.onDismiss = { [weak self] in self?.hideRatingOverlay() }
        addSubview(overlay); return overlay
    }()
    
    private func showRatingOverlay() {
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack,
              currentTrack.plexRatingKey != nil || currentTrack.subsonicId != nil || currentTrack.jellyfinId != nil || currentTrack.url.isFileURL else { return }
        if let historyHostingView {
            addSubview(ratingOverlay, positioned: .above, relativeTo: historyHostingView)
        }
        ratingOverlay.frame = bounds; ratingOverlay.setRating(currentTrackRating ?? 0)
        ratingOverlay.isHidden = false; isRatingOverlayVisible = true; needsDisplay = true
    }
    
    private func hideRatingOverlay() {
        ratingOverlay.isHidden = true; isRatingOverlayVisible = false
        ratingSubmitTask?.cancel(); ratingSubmitTask = nil; needsDisplay = true
    }
    
    private func submitRating(_ rating: Int) {
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack else { return }
        let normalizedRating = rating > 0 ? min(10, rating) : 0
        currentTrackRating = normalizedRating; needsDisplay = true; ratingSubmitTask?.cancel()
        ratingSubmitTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
                
                if let ratingKey = currentTrack.plexRatingKey {
                    // Plex: rating is already 0-10 scale
                    try await PlexManager.shared.serverClient?.rateItem(
                        ratingKey: ratingKey,
                        rating: normalizedRating > 0 ? normalizedRating : nil
                    )
                } else if let subsonicId = currentTrack.subsonicId {
                    // Subsonic: convert 0-10 to 0-5
                    let subsonicRating = normalizedRating / 2
                    try await SubsonicManager.shared.setRating(songId: subsonicId, rating: subsonicRating)
                } else if let jellyfinId = currentTrack.jellyfinId {
                    // Jellyfin: convert 0-10 to 0-100
                    let jellyfinRating = normalizedRating * 10
                    try await JellyfinManager.shared.setRating(itemId: jellyfinId, rating: jellyfinRating)
                } else if currentTrack.url.isFileURL {
                    // Local file: store 0-10 scale
                    if let libraryTrack = MediaLibrary.shared.findTrack(byURL: currentTrack.url) {
                        MediaLibrary.shared.setRating(
                            for: libraryTrack.id,
                            rating: normalizedRating > 0 ? normalizedRating : nil
                        )
                    }
                }
                
                try await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { hideRatingOverlay() }
            } catch is CancellationError { } catch { NSLog("Rating failed: %@", error.localizedDescription) }
        }
    }
    
    private func fetchCurrentTrackRating() {
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack else {
            currentTrackRating = nil; return
        }
        
        if let ratingKey = currentTrack.plexRatingKey {
            // Plex: fetch from server (0-10 scale)
            Task {
                do {
                    if let details = try await PlexManager.shared.serverClient?.fetchTrackDetails(trackID: ratingKey) {
                        await MainActor.run {
                            currentTrackRating = details.userRating.map { Int($0) }; needsDisplay = true
                        }
                    }
                } catch { }
            }
        } else if let subsonicId = currentTrack.subsonicId {
            // Subsonic: fetch from server (1-5 scale, convert to 0-10)
            Task {
                do {
                    if let song = try await SubsonicManager.shared.serverClient?.fetchSong(id: subsonicId) {
                        await MainActor.run {
                            currentTrackRating = song.userRating.map { $0 * 2 }; needsDisplay = true
                        }
                    }
                } catch { }
            }
        } else if let jellyfinId = currentTrack.jellyfinId {
            // Jellyfin: fetch from server (0-100 scale, convert to 0-10)
            Task {
                do {
                    if let song = try await JellyfinManager.shared.serverClient?.fetchSong(id: jellyfinId) {
                        await MainActor.run {
                            currentTrackRating = song.userRating.map { $0 / 10 }; needsDisplay = true
                        }
                    }
                } catch { }
            }
        } else if let embyId = currentTrack.embyId {
            // Emby: fetch from server (0-100 scale, convert to 0-10)
            Task {
                do {
                    if let song = try await EmbyManager.shared.serverClient?.fetchSong(id: embyId) {
                        await MainActor.run {
                            currentTrackRating = song.userRating.map { $0 / 10 }; needsDisplay = true
                        }
                    }
                } catch { }
            }
        } else if currentTrack.url.isFileURL {
            // Local file: read from library (already 0-10 scale)
            if let libraryTrack = MediaLibrary.shared.findTrack(byURL: currentTrack.url) {
                currentTrackRating = libraryTrack.rating
            } else {
                currentTrackRating = nil
            }
            needsDisplay = true
        } else {
            currentTrackRating = nil
        }
    }
    
    // MARK: - Rate Submenus

    private static func goldStarAttributedTitle(_ label: String) -> NSAttributedString {
        let goldColor = ModernSkinEngine.shared.currentRenderStyle == .metal
            ? NSColor(calibratedRed: 0.34, green: 0.28, blue: 0.13, alpha: 1.0)
            : NSColor(srgbRed: 0.98, green: 0.78, blue: 0.20, alpha: 1.0)
        let emptyColor = NSColor.secondaryLabelColor
        let font = NSFont.menuFont(ofSize: 0)
        let astr = NSMutableAttributedString(string: label,
                                             attributes: [.font: font,
                                                          .foregroundColor: emptyColor])
        for (i, ch) in label.enumerated() where ch == "★" {
            astr.addAttribute(.foregroundColor, value: goldColor,
                              range: NSRange(location: i, length: 1))
        }
        return astr
    }

    /// Build rate submenu for the currently playing track (art mode overlay)
    private func buildRateSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Rate")
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRateCurrentTrack(_:)), keyEquivalent: "")
            item.target = self; item.tag = stars * 2  // 0-10 scale
            item.attributedTitle = ModernLibraryBrowserView.goldStarAttributedTitle(label)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRateCurrentTrack(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = 0
        menu.addItem(clearItem)
        return menu
    }
    
    /// Build rate submenu for a Plex track
    private func buildRateSubmenuForPlex(ratingKey: String) -> NSMenu {
        let menu = NSMenu(title: "Rate")
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRatePlex(_:)), keyEquivalent: "")
            item.target = self; item.tag = stars * 2; item.representedObject = ratingKey
            item.attributedTitle = ModernLibraryBrowserView.goldStarAttributedTitle(label)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRatePlex(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = 0; clearItem.representedObject = ratingKey
        menu.addItem(clearItem)
        return menu
    }
    
    /// Build rate submenu for a Subsonic track
    private func buildRateSubmenuForSubsonic(songId: String) -> NSMenu {
        let menu = NSMenu(title: "Rate")
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRateSubsonic(_:)), keyEquivalent: "")
            item.target = self; item.tag = stars; item.representedObject = songId  // tag is 1-5 for Subsonic
            item.attributedTitle = ModernLibraryBrowserView.goldStarAttributedTitle(label)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRateSubsonic(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = 0; clearItem.representedObject = songId
        menu.addItem(clearItem)
        return menu
    }
    
    private func buildRateSubmenuForJellyfin(itemId: String) -> NSMenu {
        let menu = NSMenu(title: "Rate")
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRateJellyfin(_:)), keyEquivalent: "")
            item.target = self; item.tag = stars * 20; item.representedObject = itemId  // Jellyfin uses 0-100 scale
            item.attributedTitle = ModernLibraryBrowserView.goldStarAttributedTitle(label)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRateJellyfin(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = 0; clearItem.representedObject = itemId
        menu.addItem(clearItem)
        return menu
    }

    private func buildRateSubmenuForEmby(itemId: String) -> NSMenu {
        let menu = NSMenu(title: "Rate")
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRateEmby(_:)), keyEquivalent: "")
            item.target = self; item.tag = stars * 20; item.representedObject = itemId  // Emby uses 0-100 scale
            item.attributedTitle = ModernLibraryBrowserView.goldStarAttributedTitle(label)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRateEmby(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = 0; clearItem.representedObject = itemId
        menu.addItem(clearItem)
        return menu
    }

    private func buildRateSubmenuForLocalAlbum(albumId: String) -> NSMenu {
        let menu = NSMenu(title: "Rate")
        let current = MediaLibrary.shared.albumRating(for: albumId)
        for stars in 1...5 {
            let rating = stars * 2
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRateLocalAlbum(_:)), keyEquivalent: "")
            item.target = self; item.tag = rating; item.representedObject = albumId
            item.attributedTitle = ModernLibraryBrowserView.goldStarAttributedTitle(label)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRateLocalAlbum(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = -1; clearItem.representedObject = albumId
        menu.addItem(clearItem)
        return menu
    }

    private func buildRateSubmenuForLocalArtist(artistId: String) -> NSMenu {
        let menu = NSMenu(title: "Rate")
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRateLocalArtist(_:)), keyEquivalent: "")
            item.target = self; item.tag = stars * 2; item.representedObject = artistId
            item.attributedTitle = ModernLibraryBrowserView.goldStarAttributedTitle(label)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRateLocalArtist(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = -1; clearItem.representedObject = artistId
        menu.addItem(clearItem)
        return menu
    }

    /// Build rate submenu for a local track
    private func buildRateSubmenuForLocal(trackId: UUID) -> NSMenu {
        let menu = NSMenu(title: "Rate")
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRateLocal(_:)), keyEquivalent: "")
            item.target = self; item.tag = stars * 2; item.representedObject = trackId  // 0-10 scale
            item.attributedTitle = ModernLibraryBrowserView.goldStarAttributedTitle(label)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRateLocal(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = -1; clearItem.representedObject = trackId  // -1 = clear
        menu.addItem(clearItem)
        return menu
    }
    
    @objc private func contextMenuRateCurrentTrack(_ sender: NSMenuItem) {
        let rating = sender.tag  // 0-10 scale, 0 = clear
        submitRating(rating)
    }
    
    @objc private func contextMenuRatePlex(_ sender: NSMenuItem) {
        guard let ratingKey = sender.representedObject as? String else { return }
        let rating = sender.tag  // 0-10 scale
        Task {
            do {
                try await PlexManager.shared.serverClient?.rateItem(ratingKey: ratingKey, rating: rating > 0 ? rating : nil)
                await MainActor.run {
                    // Update art mode rating if this is the current track
                    if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
                       currentTrack.plexRatingKey == ratingKey {
                        currentTrackRating = rating > 0 ? rating : nil; needsDisplay = true
                    }
                    updateCachedPlexRating(ratingKey: ratingKey, rating: rating)
                }
            } catch { NSLog("Plex rating failed: %@", error.localizedDescription) }
        }
    }
    
    @objc private func contextMenuRateSubsonic(_ sender: NSMenuItem) {
        guard let songId = sender.representedObject as? String else { return }
        let subsonicRating = sender.tag  // 0-5 scale for Subsonic
        Task {
            do {
                try await SubsonicManager.shared.setRating(songId: songId, rating: subsonicRating)
                await MainActor.run {
                    // Update art mode rating if this is the current track
                    if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
                       currentTrack.subsonicId == songId {
                        currentTrackRating = subsonicRating > 0 ? subsonicRating * 2 : nil; needsDisplay = true
                    }
                    // Update the cached song in displayItems
                    updateCachedSubsonicRating(songId: songId, rating: subsonicRating)
                }
            } catch { NSLog("Subsonic rating failed: %@", error.localizedDescription) }
        }
    }
    
    @objc private func contextMenuRateJellyfin(_ sender: NSMenuItem) {
        guard let itemId = sender.representedObject as? String else { return }
        let rating = sender.tag  // 0-100 scale (0 = clear, 20/40/60/80/100 for 1-5 stars)
        Task {
            do {
                try await JellyfinManager.shared.setRating(itemId: itemId, rating: rating)
                await MainActor.run {
                    // Update art mode rating if this is the current track
                    if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
                       currentTrack.jellyfinId == itemId {
                        currentTrackRating = rating > 0 ? rating / 10 : nil; needsDisplay = true
                    }
                    updateCachedJellyfinRating(itemId: itemId, rating: rating)
                }
            } catch { NSLog("Jellyfin rating failed: %@", error.localizedDescription) }
        }
    }

    @objc private func contextMenuRateEmby(_ sender: NSMenuItem) {
        guard let itemId = sender.representedObject as? String else { return }
        let rating = sender.tag  // 0-100 scale (0 = clear, 20/40/60/80/100 for 1-5 stars)
        Task {
            do {
                try await EmbyManager.shared.setRating(itemId: itemId, rating: rating)
                await MainActor.run {
                    // Update art mode rating if this is the current track
                    if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
                       currentTrack.embyId == itemId {
                        currentTrackRating = rating > 0 ? rating / 10 : nil; needsDisplay = true
                    }
                    updateCachedEmbyRating(itemId: itemId, rating: rating)
                }
            } catch { NSLog("Emby rating failed: %@", error.localizedDescription) }
        }
    }

    @objc private func contextMenuRateLocal(_ sender: NSMenuItem) {
        guard let trackId = sender.representedObject as? UUID else { return }
        let rating = sender.tag  // 0-10, or -1 for clear
        MediaLibrary.shared.setRating(for: trackId, rating: rating >= 0 ? rating : nil)
        // Update art mode rating if this is the current track
        if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
           let libraryTrack = MediaLibrary.shared.findTrack(byURL: currentTrack.url),
           libraryTrack.id == trackId {
            currentTrackRating = rating >= 0 ? rating : nil; needsDisplay = true
        }
        updateCachedLocalTrackRating(trackId: trackId, rating: rating)
        needsDisplay = true
    }

    @objc private func contextMenuRateLocalAlbum(_ sender: NSMenuItem) {
        guard let albumId = sender.representedObject as? String else { return }
        let rating = sender.tag
        MediaLibrary.shared.setAlbumRating(albumId: albumId, rating: rating >= 0 ? rating : nil)
        needsDisplay = true
    }

    @objc private func contextMenuRateLocalArtist(_ sender: NSMenuItem) {
        guard let artistId = sender.representedObject as? String else { return }
        let rating = sender.tag
        MediaLibrary.shared.setArtistRating(artistId: artistId, rating: rating >= 0 ? rating : nil)
        needsDisplay = true
    }
    
    /// Update cached SubsonicSong rating in displayItems after a rating change
    private func updateCachedSubsonicRating(songId: String, rating: Int) {
        for (index, item) in displayItems.enumerated() {
            if case .subsonicTrack(let song) = item.type, song.id == songId {
                let updatedSong = SubsonicSong(
                    id: song.id, parent: song.parent, title: song.title,
                    album: song.album, artist: song.artist, albumArtist: song.albumArtist,
                    albumId: song.albumId, artistId: song.artistId, track: song.track, year: song.year,
                    genre: song.genre, coverArt: song.coverArt, size: song.size,
                    contentType: song.contentType, suffix: song.suffix,
                    duration: song.duration, bitRate: song.bitRate,
                    samplingRate: song.samplingRate, path: song.path,
                    discNumber: song.discNumber, created: song.created,
                    starred: song.starred, playCount: song.playCount,
                    userRating: rating > 0 ? rating : nil
                )
                displayItems[index] = ModernDisplayItem(
                    id: item.id, title: item.title, info: item.info,
                    indentLevel: item.indentLevel, hasChildren: item.hasChildren,
                    type: .subsonicTrack(updatedSong)
                )
                break
            }
        }
    }

    private func updateCachedPlexRating(ratingKey: String, rating: Int) {
        for (index, item) in displayItems.enumerated() {
            if case .track(let track) = item.type, track.id == ratingKey {
                let updatedTrack = PlexTrack(
                    id: track.id, key: track.key, title: track.title,
                    parentTitle: track.parentTitle, grandparentTitle: track.grandparentTitle,
                    parentKey: track.parentKey, grandparentKey: track.grandparentKey,
                    summary: track.summary, duration: track.duration,
                    index: track.index, parentIndex: track.parentIndex,
                    thumb: track.thumb, media: track.media,
                    addedAt: track.addedAt, updatedAt: track.updatedAt,
                    genre: track.genre, parentYear: track.parentYear,
                    ratingCount: track.ratingCount,
                    userRating: rating > 0 ? Double(rating) : nil
                )
                displayItems[index] = ModernDisplayItem(
                    id: item.id, title: item.title, info: item.info,
                    indentLevel: item.indentLevel, hasChildren: item.hasChildren,
                    type: .track(updatedTrack)
                )
                break
            }
        }
    }

    private func updateCachedJellyfinRating(itemId: String, rating: Int) {
        for (index, item) in displayItems.enumerated() {
            if case .jellyfinTrack(let song) = item.type, song.id == itemId {
                let updatedSong = JellyfinSong(
                    id: song.id, title: song.title, album: song.album,
                    artist: song.artist, albumArtist: song.albumArtist,
                    albumId: song.albumId, artistId: song.artistId,
                    track: song.track, year: song.year, genre: song.genre,
                    imageTag: song.imageTag, size: song.size, contentType: song.contentType,
                    duration: song.duration, bitRate: song.bitRate,
                    sampleRate: song.sampleRate, channels: song.channels,
                    path: song.path, discNumber: song.discNumber, created: song.created,
                    isFavorite: song.isFavorite, playCount: song.playCount,
                    userRating: rating > 0 ? rating : nil
                )
                displayItems[index] = ModernDisplayItem(
                    id: item.id, title: item.title, info: item.info,
                    indentLevel: item.indentLevel, hasChildren: item.hasChildren,
                    type: .jellyfinTrack(updatedSong)
                )
                break
            }
        }
    }

    private func updateCachedEmbyRating(itemId: String, rating: Int) {
        for (index, item) in displayItems.enumerated() {
            if case .embyTrack(let song) = item.type, song.id == itemId {
                let updatedSong = EmbySong(
                    id: song.id, title: song.title, album: song.album,
                    artist: song.artist, albumArtist: song.albumArtist,
                    albumId: song.albumId, artistId: song.artistId,
                    track: song.track, year: song.year, genre: song.genre,
                    imageTag: song.imageTag, size: song.size, contentType: song.contentType,
                    duration: song.duration, bitRate: song.bitRate,
                    sampleRate: song.sampleRate, channels: song.channels,
                    path: song.path, discNumber: song.discNumber, created: song.created,
                    isFavorite: song.isFavorite, playCount: song.playCount,
                    userRating: rating > 0 ? rating : nil
                )
                displayItems[index] = ModernDisplayItem(
                    id: item.id, title: item.title, info: item.info,
                    indentLevel: item.indentLevel, hasChildren: item.hasChildren,
                    type: .embyTrack(updatedSong)
                )
                break
            }
        }
    }

    private func updateCachedLocalTrackRating(trackId: UUID, rating: Int) {
        for (index, item) in displayItems.enumerated() {
            if case .localTrack(var track) = item.type, track.id == trackId {
                track.rating = rating >= 0 ? rating : nil
                displayItems[index] = ModernDisplayItem(
                    id: item.id, title: item.title, info: item.info,
                    indentLevel: item.indentLevel, hasChildren: item.hasChildren,
                    type: .localTrack(track)
                )
                break
            }
        }
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork(for track: Track?) {
        artworkLoadTask?.cancel(); artworkLoadTask = nil
        guard let track = track else { currentArtwork = nil; artworkTrackId = nil; needsDisplay = true; return }
        guard track.id != artworkTrackId else { return }
        artworkLoadTask = Task { [weak self] in
            guard let self = self else { return }
            var image: NSImage?
            if let plexRatingKey = track.plexRatingKey {
                image = await self.loadPlexArtwork(ratingKey: plexRatingKey, thumbPath: track.artworkThumb)
            } else if let subsonicId = track.subsonicId {
                image = await self.loadSubsonicArtwork(songId: subsonicId)
            } else if let jellyfinId = track.jellyfinId {
                image = await self.loadJellyfinArtwork(itemId: jellyfinId, imageTag: track.artworkThumb)
            } else if let embyId = track.embyId {
                image = await self.loadEmbyArtwork(itemId: embyId, imageTag: track.artworkThumb)
            } else if track.url.isFileURL {
                image = await self.loadLocalArtwork(url: track.url)
            } else if RadioManager.shared.isActive {
                image = await self.loadRadioArtwork(for: track)
            } else if let thumb = track.artworkThumb {
                image = await self.loadRemoteArtwork(urlString: thumb, cacheNamespace: "generic")
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard WindowManager.shared.audioEngine.currentTrack?.id == track.id else { return }
                self.currentArtwork = image
                self.artworkTrackId = track.id
                self.needsDisplay = true
            }
        }
    }

    private func loadPlexArtwork(ratingKey: String, thumbPath: String? = nil) async -> NSImage? {
        let cacheKey = NSString(string: "plex:\(ratingKey)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) { return cached }
        let thumb = thumbPath ?? "/library/metadata/\(ratingKey)/thumb"
        guard let url = PlexManager.shared.artworkURL(thumb: thumb, size: 400) else { return nil }
        do {
            var request = URLRequest(url: url)
            if let headers = PlexManager.shared.streamingHeaders {
                for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = NSImage(data: data) else { return nil }
            Self.artworkCache.setObject(image, forKey: cacheKey); return image
        } catch { return nil }
    }
    
    private func loadSubsonicArtwork(songId: String) async -> NSImage? {
        let cacheKey = NSString(string: "subsonic:\(songId)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) { return cached }
        guard let url = SubsonicManager.shared.coverArtURL(coverArtId: songId, size: 400) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = NSImage(data: data) else { return nil }
            Self.artworkCache.setObject(image, forKey: cacheKey); return image
        } catch { return nil }
    }
    
    private func loadJellyfinArtwork(itemId: String, imageTag: String?) async -> NSImage? {
        let cacheKey = NSString(string: "jellyfin:\(itemId)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) { return cached }
        guard let url = JellyfinManager.shared.imageURL(itemId: itemId, imageTag: imageTag, size: 400) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = NSImage(data: data) else { return nil }
            Self.artworkCache.setObject(image, forKey: cacheKey); return image
        } catch { return nil }
    }

    private func loadEmbyArtwork(itemId: String, imageTag: String?) async -> NSImage? {
        let cacheKey = NSString(string: "emby:\(itemId)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) { return cached }
        guard let url = EmbyManager.shared.imageURL(itemId: itemId, imageTag: imageTag, size: 400) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = NSImage(data: data) else { return nil }
            Self.artworkCache.setObject(image, forKey: cacheKey); return image
        } catch { return nil }
    }

    private func loadLocalArtwork(url: URL) async -> NSImage? {
        let cacheKey = NSString(string: "local:\(url.path)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) { return cached }
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue), let image = NSImage(data: data) {
                        Self.artworkCache.setObject(image, forKey: cacheKey); return image
                    }
                }
            }
        } catch { }
        return nil
    }

    private func loadRemoteArtwork(urlString: String, cacheNamespace: String) async -> NSImage? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        let cacheKey = NSString(string: "\(cacheNamespace):\(trimmed)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) { return cached }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let looksLikeIcon = url.path.lowercased().hasSuffix(".ico") || mime.contains("icon")
            guard mime.contains("image") || looksLikeIcon else { return nil }
            guard let image = NSImage(data: data) else { return nil }
            Self.artworkCache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }

    private func loadRadioArtwork(for track: Track, station: RadioStation? = nil) async -> NSImage? {
        if let thumb = track.artworkThumb,
           let image = await loadRemoteArtwork(urlString: thumb, cacheNamespace: "radio") {
            return image
        }

        let activeStation = station ?? RadioManager.shared.currentStation
        if let iconURL = activeStation?.iconURL?.absoluteString,
           let image = await loadRemoteArtwork(urlString: iconURL, cacheNamespace: "radio") {
            return image
        }

        var hosts = Set<String>()
        if let host = track.url.host, !host.isEmpty { hosts.insert(host) }
        if let host = activeStation?.url.host, !host.isEmpty { hosts.insert(host) }

        var candidates: [String] = []
        for host in hosts {
            candidates.append("https://\(host)/favicon.ico")
            if !host.lowercased().hasPrefix("www.") {
                candidates.append("https://www.\(host)/favicon.ico")
            }
            candidates.append("http://\(host)/favicon.ico")
        }

        for candidate in candidates {
            if let image = await loadRemoteArtwork(urlString: candidate, cacheNamespace: "radio-favicon") {
                return image
            }
        }

        return nil
    }
    
    private func loadAllArtworkForCurrentTrack() {
        artworkLoadTask?.cancel(); artworkLoadTask = nil
        artworkCyclingTask?.cancel(); artworkCyclingTask = nil
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack else {
            exitArtOnlyModeForMissingArtwork()
            return
        }
        artworkImages = []; artworkIndex = 0
        artworkCyclingTask = Task { [weak self] in
            guard let self = self else { return }
            var images: [NSImage] = []
            if currentTrack.url.isFileURL {
                if let img = await self.loadLocalArtwork(url: currentTrack.url) { images.append(img) }
            } else if let plexKey = currentTrack.plexRatingKey {
                if let img = await self.loadPlexArtwork(ratingKey: plexKey, thumbPath: currentTrack.artworkThumb) { images.append(img) }
            } else if let subId = currentTrack.subsonicId {
                if let img = await self.loadSubsonicArtwork(songId: subId) { images.append(img) }
            } else if let jellyfinId = currentTrack.jellyfinId {
                if let img = await self.loadJellyfinArtwork(itemId: jellyfinId, imageTag: currentTrack.artworkThumb) { images.append(img) }
            } else if let embyId = currentTrack.embyId {
                if let img = await self.loadEmbyArtwork(itemId: embyId, imageTag: currentTrack.artworkThumb) { images.append(img) }
            } else if RadioManager.shared.isActive {
                if let img = await self.loadRadioArtwork(for: currentTrack) { images.append(img) }
            } else if let thumb = currentTrack.artworkThumb {
                if let img = await self.loadRemoteArtwork(urlString: thumb, cacheNamespace: "generic") { images.append(img) }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.isArtOnlyMode,
                      WindowManager.shared.audioEngine.currentTrack?.id == currentTrack.id else { return }
                guard !images.isEmpty else {
                    self.exitArtOnlyModeForMissingArtwork()
                    return
                }

                self.artworkImages = images; self.artworkIndex = 0
                self.currentArtwork = images.first
                self.artworkTrackId = currentTrack.id
                self.needsDisplay = true
            }
        }
    }

    private func exitArtOnlyModeForMissingArtwork() {
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        artworkCyclingTask?.cancel()
        artworkCyclingTask = nil
        artworkImages = []
        artworkIndex = 0
        currentArtwork = nil
        artworkTrackId = nil
        isArtOnlyMode = false
        needsDisplay = true
    }
    
    private func cycleToNextArtwork() {
        guard artworkImages.count > 1 else { return }
        artworkIndex = (artworkIndex + 1) % artworkImages.count
        currentArtwork = artworkImages[artworkIndex]; needsDisplay = true
    }
    
    private func loadArtworkForSelection() {
        guard WindowManager.shared.showBrowserArtworkBackground else { return }
        guard let index = selectedIndices.first, index < displayItems.count else { return }
        
        let item = displayItems[index]
        artworkLoadTask?.cancel()
        
        artworkLoadTask = Task { [weak self] in
            guard let self = self else { return }
            var image: NSImage?
            
            switch item.type {
            case .track(let track):
                if let thumb = track.thumb {
                    image = await self.loadPlexArtwork(ratingKey: track.id, thumbPath: thumb)
                }
            case .album(let album):
                if let thumb = album.thumb {
                    image = await self.loadPlexArtwork(ratingKey: album.id, thumbPath: thumb)
                }
            case .artist(let artist):
                if let thumb = artist.thumb {
                    image = await self.loadPlexArtwork(ratingKey: artist.id, thumbPath: thumb)
                }
            case .movie(let movie):
                if let thumb = movie.thumb {
                    image = await self.loadPlexArtwork(ratingKey: movie.id, thumbPath: thumb)
                }
            case .episode(let episode):
                if let thumb = episode.thumb {
                    image = await self.loadPlexArtwork(ratingKey: episode.id, thumbPath: thumb)
                }
            case .show(let show):
                if let thumb = show.thumb {
                    image = await self.loadPlexArtwork(ratingKey: show.id, thumbPath: thumb)
                }
            case .season(let season):
                if let thumb = season.thumb {
                    image = await self.loadPlexArtwork(ratingKey: season.id, thumbPath: thumb)
                }
            case .localTrack(let track):
                image = await self.loadLocalArtwork(url: track.url)
            case .localAlbum(let album):
                let albumTrackForArt = album.tracks.first ?? MediaLibraryStore.shared.tracksForAlbum(album.id).first
                if let track = albumTrackForArt {
                    image = await self.loadLocalArtwork(url: track.url)
                }
            case .localArtist(let artist):
                let artistTracks = MediaLibraryStore.shared.searchTracks(query: artist.name, limit: 1, offset: 0)
                if let track = artistTracks.first {
                    image = await self.loadLocalArtwork(url: track.url)
                }
            case .subsonicTrack(let song):
                if let coverArt = song.coverArt {
                    image = await self.loadSubsonicArtwork(songId: coverArt)
                }
            case .subsonicAlbum(let album):
                if let coverArt = album.coverArt {
                    image = await self.loadSubsonicArtwork(songId: coverArt)
                }
            case .subsonicArtist(let artist):
                if let coverArt = artist.coverArt {
                    image = await self.loadSubsonicArtwork(songId: coverArt)
                }
            case .jellyfinTrack(let song):
                image = await self.loadJellyfinArtwork(itemId: song.albumId ?? song.id, imageTag: song.imageTag)
            case .jellyfinAlbum(let album):
                image = await self.loadJellyfinArtwork(itemId: album.id, imageTag: album.imageTag)
            case .jellyfinArtist(let artist):
                image = await self.loadJellyfinArtwork(itemId: artist.id, imageTag: artist.imageTag)
            case .jellyfinMovie(let movie):
                image = await self.loadJellyfinArtwork(itemId: movie.id, imageTag: movie.imageTag)
            case .jellyfinShow(let show):
                image = await self.loadJellyfinArtwork(itemId: show.id, imageTag: show.imageTag)
            case .jellyfinSeason(let season):
                image = await self.loadJellyfinArtwork(itemId: season.id, imageTag: season.imageTag)
            case .jellyfinEpisode(let episode):
                image = await self.loadJellyfinArtwork(itemId: episode.id, imageTag: episode.imageTag)
            case .embyTrack(let song):
                image = await self.loadEmbyArtwork(itemId: song.albumId ?? song.id, imageTag: song.imageTag)
            case .embyAlbum(let album):
                image = await self.loadEmbyArtwork(itemId: album.id, imageTag: album.imageTag)
            case .embyArtist(let artist):
                image = await self.loadEmbyArtwork(itemId: artist.id, imageTag: artist.imageTag)
            case .embyMovie(let movie):
                image = await self.loadEmbyArtwork(itemId: movie.id, imageTag: movie.imageTag)
            case .embyShow(let show):
                image = await self.loadEmbyArtwork(itemId: show.id, imageTag: show.imageTag)
            case .embySeason(let season):
                image = await self.loadEmbyArtwork(itemId: season.id, imageTag: season.imageTag)
            case .embyEpisode(let episode):
                image = await self.loadEmbyArtwork(itemId: episode.id, imageTag: episode.imageTag)
            case .radioStation(let station):
                let radioTrack = station.toTrack()
                image = await self.loadRadioArtwork(for: radioTrack, station: station)
            default:
                break
            }
            
            guard !Task.isCancelled else { return }
            if let image = image {
                await MainActor.run {
                    self.currentArtwork = image
                    self.needsDisplay = true
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    func reloadData() {
        let generation = invalidateActiveLoads()
        loadDataForCurrentMode(generation: generation)
    }
    
    func refreshData() {
        let generation = invalidateActiveLoads()
        // Plex caches
        cachedArtists = []; cachedAlbums = []; cachedTracks = []; artistAlbums = [:]; albumTracks = [:]; artistAlbumCounts = [:]
        cachedMovies = []; cachedShows = []; showSeasons = [:]; seasonEpisodes = [:]
        cachedPlexPlaylists = []; plexPlaylistTracks = [:]; searchResults = nil
        expandedArtists = []; expandedAlbums = []; expandedShows = []; expandedSeasons = []; expandedPlexPlaylists = []
        // Subsonic caches
        cachedSubsonicArtists = []; cachedSubsonicAlbums = []; cachedSubsonicPlaylists = []
        subsonicArtistAlbums = [:]; subsonicPlaylistTracks = [:]; subsonicAlbumSongs = [:]
        expandedSubsonicArtists = []; expandedSubsonicAlbums = []; expandedSubsonicPlaylists = []
        // Jellyfin caches
        cachedJellyfinArtists = []; cachedJellyfinAlbums = []; cachedJellyfinPlaylists = []
        jellyfinArtistAlbums = [:]; jellyfinPlaylistTracks = [:]; jellyfinAlbumSongs = [:]
        expandedJellyfinArtists = []; expandedJellyfinAlbums = []; expandedJellyfinPlaylists = []
        cachedJellyfinMovies = []; cachedJellyfinShows = []
        jellyfinShowSeasons = [:]; jellyfinSeasonEpisodes = [:]
        expandedJellyfinShows = []; expandedJellyfinSeasons = []
        // Common state
        selectedIndices = []; scrollOffset = 0
        isLoading = true; errorMessage = nil; displayItems = []; startLoadingAnimation(); needsDisplay = true
        PlexManager.shared.clearCachedContent()
        loadDataForCurrentMode(generation: generation)
    }
    
    // MARK: - Data Loading

    private func loadDataForCurrentMode(generation: Int? = nil) {
        let generation = generation ?? loadGeneration

        if browseMode.isHistoryMode {
            invalidateActiveLoads()
            displayItems = []
            isLoading = false
            errorMessage = nil
            stopLoadingAnimation()
            historyAgent.scheduleRefresh()
            updateHistoryHostingVisibility()
            needsDisplay = true
            return
        }
        
        if case .youtube = currentSource {
            // YouTube content lives only in the Radio tab slot. The slot toggles
            // between YouTube channels and Internet Radio stations; other tabs are
            // empty (matching how the Internet Radio source treats its tabs).
            switch browseMode {
            case .radio:
                if radioSlotShowsChannels {
                    loadYouTubeChannels()
                } else {
                    loadRadioStations()
                }
            case .search:
                loadRadioSearchResults()
            default:
                displayItems = []
                isLoading = false
                needsDisplay = true
            }
            return
        }

        if case .radio = currentSource {
            switch browseMode {
            case .radio:
                loadRadioStations()
            case .search:
                loadRadioSearchResults()
            case .history:
                break
            default:
                displayItems = []
                isLoading = false
                needsDisplay = true
            }
            return
        }

        if browseMode == .radio {
            switch currentSource {
            case .plex:
                loadPlexRadioStations(generation: generation)
            case .subsonic:
                loadSubsonicRadioStations(generation: generation)
            case .jellyfin:
                loadJellyfinRadioStations(generation: generation)
            case .emby:
                loadEmbyRadioStations(generation: generation)
            case .local:
                loadLocalRadioStations()
            case .radio:
                displayItems = []
            case .youtube:
                displayItems = []
            }
            needsDisplay = true
            return
        }

        switch currentSource {
        case .local:
            loadLocalData()
        case .plex(let serverId):
            loadPlexData(serverId: serverId, generation: generation)
        case .subsonic(let serverId):
            loadSubsonicData(serverId: serverId, generation: generation)
        case .jellyfin(let serverId):
            loadJellyfinData(serverId: serverId, generation: generation)
        case .emby(let serverId):
            loadEmbyData(serverId: serverId, generation: generation)
        case .radio:
            break
        case .youtube:
            break
        }
    }
    
    // MARK: - Local Data Loading
    
    private func loadLocalData() {
        isLoading = false; errorMessage = nil; stopLoadingAnimation()

        // Check which watch folders are on unavailable volumes
        let summaries = MediaLibrary.shared.watchFolderSummaries()
        offlineWatchFolders = summaries.filter { !$0.isAvailable }
        offlineVolumePrefixes = Set(offlineWatchFolders.map { $0.url.path })

        let library = MediaLibrary.shared
        let store = MediaLibraryStore.shared
        switch browseMode {
        case .artists:
            if !pendingArtistLoadUnfiltered {
                localArtistPageOffset = 0
            }
            localArtistTotal = store.artistCount()
            buildLocalArtistItems()
        case .albums:
            localAlbumPageOffset = 0
            localAlbumTotal = store.albumCount()
            buildLocalAlbumItems()
        case .folders:
            buildLocalFolderItems()
        case .search:
            buildLocalSearchItems()
        case .plists:
            refreshCachedLocalPlaylists()
            buildLocalPlaylistItems()
        case .movies:
            cachedLocalMovies = library.moviesSnapshot
            buildLocalMovieItems()
        case .shows:
            cachedLocalShows = library.allShows()
            buildLocalShowItems()
        case .radio: loadLocalRadioStations()
        case .history: break
        }
        // Apply any active column-header sort so a fresh load matches what an expand-driven
        // rebuild produces — otherwise expanding a row would re-order the list. (Mirrors
        // rebuildCurrentModeItems.)
        if columnSortId != nil { applyColumnSort() }
        applyPendingArtistScroll()
        needsDisplay = true
    }

    private func reloadLocalBrowserAfterMetadataEdit() {
        guard case .local = currentSource else { return }

        clearLocalCachedData()
        displayItems.removeAll()
        selectedIndices.removeAll()
        scrollOffset = 0
        loadLocalData()
    }

    // MARK: - Radio Data Loading
    
    private func loadRadioStations() {
        isLoading = false
        errorMessage = nil
        stopLoadingAnimation()
        cachedRadioStations = RadioManager.shared.stations
        cachedRadioFolders = RadioManager.shared.internetRadioFolderDescriptors()
        buildRadioStationItems()
        if columnSortId != nil { applyColumnSort() }
        needsDisplay = true
    }

    private func loadRadioSearchResults() {
        isLoading = false
        errorMessage = nil
        stopLoadingAnimation()
        cachedRadioStations = RadioManager.shared.stations
        buildRadioSearchItems()
        if columnSortId != nil { applyColumnSort() }
        needsDisplay = true
    }

    private func reloadInternetRadioForCurrentMode() {
        guard isShowingInternetRadioContent else { return }
        switch browseMode {
        case .radio:
            loadRadioStations()
        case .search:
            loadRadioSearchResults()
        default:
            isLoading = false
            errorMessage = nil
            stopLoadingAnimation()
            displayItems = []
            needsDisplay = true
        }
    }
    
    private func loadPlexRadioStations(generation: Int? = nil) {
        let generation = generation ?? loadGeneration
        guard case .plex = currentSource else { return }
        let expectedSource = currentSource
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        radioLoadTask?.cancel()
        radioLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let genres = await PlexManager.shared.getGenres()
            guard !Task.isCancelled,
                  self.isLoadContextActive(generation, source: expectedSource),
                  self.browseMode == .radio else { return }
            self.buildPlexRadioStationItems(genres: genres)
            self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
            self.radioLoadTask = nil
        }
    }
    
    private func loadPlexData(serverId: String, generation: Int? = nil) {
        let generation = generation ?? loadGeneration
        let expectedSource = ModernBrowserSource.plex(serverId: serverId)
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        guard PlexManager.shared.isLinked else {
            displayItems = []; stopLoadingAnimation(); needsDisplay = true
            return
        }
        
        let manager = PlexManager.shared
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        
        if manager.currentServer?.id != serverId || manager.serverClient == nil {
            guard let server = manager.servers.first(where: { $0.id == serverId }) else {
                setLoadErrorIfActive("Server not found", generation: generation, source: expectedSource)
                return
            }
            sourceConnectTask?.cancel()
            sourceConnectTask = Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                do {
                    try await manager.connect(to: server)
                    guard self.isLoadContextActive(generation, source: expectedSource),
                          manager.currentServer?.id == serverId else { return }
                    self.loadPlexDataForCurrentMode(serverId: serverId, generation: generation, expectedSource: expectedSource)
                } catch {
                    self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
                }
            }
            return
        }
        
        loadPlexDataForCurrentMode(serverId: serverId, generation: generation, expectedSource: expectedSource)
    }
    
    private func loadPlexDataForCurrentMode(serverId: String, generation: Int, expectedSource: ModernBrowserSource) {
        let pm = PlexManager.shared
        plexLoadTask?.cancel()
        plexLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                guard self.isLoadContextActive(generation, source: expectedSource),
                      pm.currentServer?.id == serverId else { return }
                
                switch self.browseMode {
                case .artists:
                    if self.cachedArtists.isEmpty {
                        if self.pendingArtistLoadUnfiltered {
                            self.cachedArtists = try await pm.fetchArtists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                            if self.cachedAlbums.isEmpty {
                                self.cachedAlbums = try await pm.fetchAlbums(offset: 0, limit: 10000)
                                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                            }
                        } else if pm.isContentPreloaded && !pm.cachedArtists.isEmpty {
                            self.cachedArtists = pm.cachedArtists; self.cachedAlbums = pm.cachedAlbums
                        } else {
                            self.cachedArtists = try await pm.fetchArtists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                            if self.cachedAlbums.isEmpty {
                                self.cachedAlbums = try await pm.fetchAlbums(offset: 0, limit: 10000)
                                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                            }
                        }
                        self.buildArtistAlbumCounts()
                    }
                    self.pendingArtistLoadUnfiltered = false
                    self.buildArtistItems()
                case .albums:
                    if self.cachedAlbums.isEmpty {
                        if pm.isContentPreloaded && !pm.cachedAlbums.isEmpty { self.cachedAlbums = pm.cachedAlbums }
                        else {
                            self.cachedAlbums = try await pm.fetchAlbums(offset: 0, limit: 500)
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildAlbumItems()
                case .movies:
                    if self.cachedMovies.isEmpty {
                        if pm.isContentPreloaded && !pm.cachedMovies.isEmpty { self.cachedMovies = pm.cachedMovies }
                        else {
                            self.cachedMovies = try await pm.fetchMovies(offset: 0, limit: 500)
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildMovieItems()
                case .shows:
                    if self.cachedShows.isEmpty {
                        if pm.isContentPreloaded && !pm.cachedShows.isEmpty { self.cachedShows = pm.cachedShows }
                        else {
                            self.cachedShows = try await pm.fetchShows(offset: 0, limit: 500)
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildShowItems()
                case .plists, .folders:
                    if self.cachedPlexPlaylists.isEmpty {
                        if !pm.cachedPlaylists.isEmpty { self.cachedPlexPlaylists = pm.cachedPlaylists }
                        else {
                            self.cachedPlexPlaylists = try await pm.fetchPlaylists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildPlexPlaylistItems()
                case .search:
                    if !self.searchQuery.isEmpty {
                        self.searchResults = try await pm.search(query: self.searchQuery)
                        guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        self.buildSearchItems()
                    } else {
                        self.displayItems = []
                    }
                case .radio:
                    self.loadPlexRadioStations(generation: generation)
                    return
                case .history:
                    self.displayItems = []
                }
                
                self.finishLoadIfActive(generation: generation, source: expectedSource)
            } catch is CancellationError {
            } catch where Task.isCancelled {
            } catch {
                self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
            }
        }
    }
    
    // MARK: - Subsonic Data Loading
    
    private func loadSubsonicData(serverId: String, generation: Int? = nil) {
        let generation = generation ?? loadGeneration
        let expectedSource = ModernBrowserSource.subsonic(serverId: serverId)
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        
        let manager = SubsonicManager.shared
        if manager.currentServer?.id != serverId {
            guard let server = manager.servers.first(where: { $0.id == serverId }) else {
                setLoadErrorIfActive("Server not found", generation: generation, source: expectedSource)
                return
            }
            sourceConnectTask?.cancel()
            sourceConnectTask = Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                do {
                    try await manager.connect(to: server)
                    guard self.isLoadContextActive(generation, source: expectedSource),
                          manager.currentServer?.id == serverId else { return }
                    self.loadSubsonicDataForCurrentMode(generation: generation, expectedSource: expectedSource)
                } catch {
                    self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
                }
            }
            return
        }
        
        loadSubsonicDataForCurrentMode(generation: generation, expectedSource: expectedSource)
    }
    
    private func loadSubsonicDataForCurrentMode(generation: Int, expectedSource: ModernBrowserSource) {
        let manager = SubsonicManager.shared
        subsonicLoadTask?.cancel()
        subsonicLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                if manager.isPreloading {
                    while manager.isPreloading {
                        try Task.checkCancellation()
                        guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }
                }
                
                switch self.browseMode {
                case .artists:
                    if self.cachedSubsonicArtists.isEmpty {
                        if self.pendingArtistLoadUnfiltered {
                            self.cachedSubsonicArtists = try await manager.fetchArtistsUnfiltered()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        } else if manager.isContentPreloaded && !manager.cachedArtists.isEmpty {
                            self.cachedSubsonicArtists = manager.cachedArtists
                            self.cachedSubsonicAlbums = manager.cachedAlbums
                        } else {
                            self.cachedSubsonicArtists = try await manager.fetchArtists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                            self.cachedSubsonicAlbums = try await manager.fetchAlbums()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.pendingArtistLoadUnfiltered = false
                    self.buildSubsonicArtistItems()
                case .albums:
                    if self.cachedSubsonicAlbums.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedAlbums.isEmpty { self.cachedSubsonicAlbums = manager.cachedAlbums }
                        else {
                            self.cachedSubsonicAlbums = try await manager.fetchAlbums()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildSubsonicAlbumItems()
                case .plists, .folders:
                    if self.cachedSubsonicPlaylists.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedPlaylists.isEmpty { self.cachedSubsonicPlaylists = manager.cachedPlaylists }
                        else {
                            self.cachedSubsonicPlaylists = try await manager.fetchPlaylists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildSubsonicPlaylistItems()
                case .search:
                    if !self.searchQuery.isEmpty {
                        self.subsonicSearchResults = try await manager.search(query: self.searchQuery)
                        guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        self.buildSubsonicSearchItems()
                    } else { self.displayItems = [] }
                case .movies, .shows:
                    self.displayItems = []
                case .radio:
                    self.loadSubsonicRadioStations(generation: generation)
                    return
                case .history:
                    self.displayItems = []
                }
                
                self.finishLoadIfActive(generation: generation, source: expectedSource)
            } catch is CancellationError {
            } catch where Task.isCancelled {
            } catch {
                self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
            }
        }
    }

    // MARK: - Jellyfin Data Loading
    
    private func loadJellyfinData(serverId: String, generation: Int? = nil) {
        let generation = generation ?? loadGeneration
        let expectedSource = ModernBrowserSource.jellyfin(serverId: serverId)
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        
        let manager = JellyfinManager.shared
        if manager.currentServer?.id != serverId {
            guard let server = manager.servers.first(where: { $0.id == serverId }) else {
                setLoadErrorIfActive("Server not found", generation: generation, source: expectedSource)
                return
            }
            sourceConnectTask?.cancel()
            sourceConnectTask = Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                do {
                    try await manager.connect(to: server)
                    guard self.isLoadContextActive(generation, source: expectedSource),
                          manager.currentServer?.id == serverId else { return }
                    self.loadJellyfinDataForCurrentMode(generation: generation, expectedSource: expectedSource)
                } catch {
                    self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
                }
            }
            return
        }
        
        loadJellyfinDataForCurrentMode(generation: generation, expectedSource: expectedSource)
    }
    
    private func loadJellyfinDataForCurrentMode(generation: Int, expectedSource: ModernBrowserSource) {
        let manager = JellyfinManager.shared
        jellyfinLoadTask?.cancel()
        jellyfinLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                if manager.isPreloading {
                    let preloadWaitDeadline = Date().addingTimeInterval(2)
                    while manager.isPreloading {
                        try Task.checkCancellation()
                        guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        if Date() >= preloadWaitDeadline { break }
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }
                }
                
                switch self.browseMode {
                case .artists:
                    if self.cachedJellyfinArtists.isEmpty {
                        if self.pendingArtistLoadUnfiltered {
                            self.cachedJellyfinArtists = try await manager.fetchArtistsUnfiltered()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        } else if manager.isContentPreloaded && !manager.cachedArtists.isEmpty {
                            self.cachedJellyfinArtists = manager.cachedArtists
                            self.cachedJellyfinAlbums = manager.cachedAlbums
                        } else {
                            self.cachedJellyfinArtists = try await manager.fetchArtists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                            if let server = manager.currentServer {
                                self.warmJellyfinAlbumsCache(forServerId: server.id)
                            }
                        }
                    }
                    self.pendingArtistLoadUnfiltered = false
                    self.buildJellyfinArtistItems()
                case .albums:
                    if self.cachedJellyfinAlbums.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedAlbums.isEmpty { self.cachedJellyfinAlbums = manager.cachedAlbums }
                        else {
                            self.cachedJellyfinAlbums = try await manager.fetchAlbums()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildJellyfinAlbumItems()
                case .plists, .folders:
                    if self.cachedJellyfinPlaylists.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedPlaylists.isEmpty { self.cachedJellyfinPlaylists = manager.cachedPlaylists }
                        else {
                            self.cachedJellyfinPlaylists = try await manager.fetchPlaylists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildJellyfinPlaylistItems()
                case .search:
                    if !self.searchQuery.isEmpty {
                        self.jellyfinSearchResults = try await manager.search(query: self.searchQuery)
                        guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        self.buildJellyfinSearchItems()
                    } else { self.displayItems = [] }
                case .movies:
                    if self.cachedJellyfinMovies.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedMovies.isEmpty { self.cachedJellyfinMovies = manager.cachedMovies }
                        else {
                            self.cachedJellyfinMovies = try await manager.fetchMovies()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildJellyfinMovieItems()
                case .shows:
                    if self.cachedJellyfinShows.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedShows.isEmpty { self.cachedJellyfinShows = manager.cachedShows }
                        else {
                            self.cachedJellyfinShows = try await manager.fetchShows()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildJellyfinShowItems()
                case .radio:
                    self.loadJellyfinRadioStations(generation: generation)
                    return
                case .history:
                    self.displayItems = []
                }
                
                self.finishLoadIfActive(generation: generation, source: expectedSource)
            } catch is CancellationError {
            } catch where Task.isCancelled {
            } catch {
                self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
            }
        }
    }

    private func warmJellyfinAlbumsCache(forServerId serverId: String) {
        guard jellyfinAlbumWarmTask == nil else { return }

        jellyfinAlbumWarmTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let albums = try await JellyfinManager.shared.fetchAlbums()
                await MainActor.run {
                    defer { self.jellyfinAlbumWarmTask = nil }
                    guard case .jellyfin(let activeServerId) = self.currentSource, activeServerId == serverId else { return }
                    guard self.cachedJellyfinAlbums.isEmpty else { return }
                    self.cachedJellyfinAlbums = albums
                    if self.browseMode == .artists {
                        self.buildJellyfinArtistItems()
                        self.needsDisplay = true
                    }
                }
            } catch is CancellationError {
                await MainActor.run { self.jellyfinAlbumWarmTask = nil }
            } catch {
                await MainActor.run { self.jellyfinAlbumWarmTask = nil }
                NSLog("ModernLibraryBrowser: Jellyfin album cache warm failed: %@", error.localizedDescription)
            }
        }
    }

    private func loadEmbyData(serverId: String, generation: Int? = nil) {
        let generation = generation ?? loadGeneration
        let expectedSource = ModernBrowserSource.emby(serverId: serverId)
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        
        let manager = EmbyManager.shared
        if manager.currentServer?.id != serverId {
            guard let server = manager.servers.first(where: { $0.id == serverId }) else {
                setLoadErrorIfActive("Server not found", generation: generation, source: expectedSource)
                return
            }
            sourceConnectTask?.cancel()
            sourceConnectTask = Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                do {
                    try await manager.connect(to: server)
                    guard self.isLoadContextActive(generation, source: expectedSource),
                          manager.currentServer?.id == serverId else { return }
                    self.loadEmbyDataForCurrentMode(generation: generation, expectedSource: expectedSource)
                } catch {
                    self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
                }
            }
            return
        }
        
        loadEmbyDataForCurrentMode(generation: generation, expectedSource: expectedSource)
    }

    private func loadEmbyDataForCurrentMode(generation: Int, expectedSource: ModernBrowserSource) {
        let manager = EmbyManager.shared
        embyLoadTask?.cancel()
        embyLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                if manager.isPreloading {
                    while manager.isPreloading {
                        try Task.checkCancellation()
                        guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                switch self.browseMode {
                case .artists:
                    if self.cachedEmbyArtists.isEmpty {
                        if self.pendingArtistLoadUnfiltered {
                            self.cachedEmbyArtists = try await manager.fetchArtistsUnfiltered()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        } else if manager.isContentPreloaded && !manager.cachedArtists.isEmpty {
                            self.cachedEmbyArtists = manager.cachedArtists; self.cachedEmbyAlbums = manager.cachedAlbums
                        } else {
                            self.cachedEmbyArtists = try await manager.fetchArtists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                            self.cachedEmbyAlbums = try await manager.fetchAlbums()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.pendingArtistLoadUnfiltered = false
                    self.buildEmbyArtistItems()
                case .albums:
                    if self.cachedEmbyAlbums.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedAlbums.isEmpty { self.cachedEmbyAlbums = manager.cachedAlbums }
                        else {
                            self.cachedEmbyAlbums = try await manager.fetchAlbums()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildEmbyAlbumItems()
                case .plists, .folders:
                    if self.cachedEmbyPlaylists.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedPlaylists.isEmpty { self.cachedEmbyPlaylists = manager.cachedPlaylists }
                        else {
                            self.cachedEmbyPlaylists = try await manager.fetchPlaylists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildEmbyPlaylistItems()
                case .search:
                    if !self.searchQuery.isEmpty {
                        self.embySearchResults = try await manager.search(query: self.searchQuery)
                        guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        self.buildEmbySearchItems()
                    } else { self.displayItems = [] }
                case .movies:
                    if self.cachedEmbyMovies.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedMovies.isEmpty { self.cachedEmbyMovies = manager.cachedMovies }
                        else {
                            self.cachedEmbyMovies = try await manager.fetchMovies()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildEmbyMovieItems()
                case .shows:
                    if self.cachedEmbyShows.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedShows.isEmpty { self.cachedEmbyShows = manager.cachedShows }
                        else {
                            self.cachedEmbyShows = try await manager.fetchShows()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                    }
                    self.buildEmbyShowItems()
                case .radio:
                    self.loadEmbyRadioStations(generation: generation)
                    return
                case .history:
                    self.displayItems = []
                }
                self.finishLoadIfActive(generation: generation, source: expectedSource)
            } catch is CancellationError {
            } catch where Task.isCancelled {
            } catch {
                self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
            }
        }
    }

    // MARK: - Build Display Items
    
    /// Extract an artist ID from a parentKey path, handling various Plex server formats:
    /// - "/library/metadata/12345" → "12345"
    /// - "/library/metadata/12345/children" → "12345"
    /// - "12345" (bare ID) → "12345"
    private func extractArtistId(from parentKey: String) -> String? {
        if parentKey.contains("/library/metadata/") {
            let stripped = parentKey.replacingOccurrences(of: "/library/metadata/", with: "")
            let components = stripped.split(separator: "/")
            if let first = components.first { return String(first) }
            return nil
        }
        let trimmed = parentKey.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber }) { return trimmed }
        NSLog("ModernLibraryBrowser: Warning - unrecognized parentKey format: %@", parentKey)
        return nil
    }
    
    private func buildArtistAlbumCounts() {
        artistAlbumCounts.removeAll()
        plexArtistGroupsByName = Dictionary(grouping: cachedArtists, by: { normalizedPlexArtistName($0.title) })
        plexAlbumsByArtistGroupKey.removeAll()
        plexAlbumCountsByArtistGroupKey.removeAll()

        var artistsById: [String: PlexArtist] = [:]
        for artist in cachedArtists {
            artistsById[artist.id] = artist
        }
        for album in cachedAlbums {
            if let parentKey = album.parentKey, let artistId = extractArtistId(from: parentKey) {
                artistAlbumCounts[artistId, default: 0] += 1
                if let artist = artistsById[artistId] {
                    plexAlbumsByArtistGroupKey[plexArtistGroupKey(for: artist), default: []].append(album)
                }
            }
        }

        for (groupKey, albums) in plexAlbumsByArtistGroupKey {
            let deduplicated = deduplicatedPlexAlbums(albums)
            plexAlbumsByArtistGroupKey[groupKey] = deduplicated
            plexAlbumCountsByArtistGroupKey[groupKey] = deduplicated.count
        }
    }
    
    private func buildArtistItems() {
        displayItems.removeAll()
        let sorted = sortPlexArtists(uniquePlexArtistsByName(cachedArtists))
        for artist in sorted {
            let groupKey = plexArtistGroupKey(for: artist)
            let expanded = expandedArtists.contains(groupKey)
            let info: String?
            if let albums = artistAlbums[groupKey] { info = "\(albums.count) album\(albums.count == 1 ? "" : "s")" }
            else if let count = plexArtistAlbumCount(for: artist), count > 0 { info = "\(count) album\(count == 1 ? "" : "s")" }
            else { info = nil }
            displayItems.append(ModernDisplayItem(id: groupKey, title: artist.title, info: info, indentLevel: 0, hasChildren: true, type: .artist(artist)))
            if expanded, let albums = artistAlbums[groupKey] {
                for album in sortPlexAlbums(albums) {
                    displayItems.append(ModernDisplayItem(id: album.id, title: album.title, info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .album(album)))
                    if expandedAlbums.contains(album.id), let tracks = albumTracks[album.id] {
                        let sorted = tracks.sorted { let d0 = $0.parentIndex ?? 1; let d1 = $1.parentIndex ?? 1; if d0 != d1 { return d0 < d1 }; return ($0.index ?? 0) < ($1.index ?? 0) }
                        for track in sorted { displayItems.append(ModernDisplayItem(id: track.id, title: track.title, info: track.formattedDuration, indentLevel: 2, hasChildren: false, type: .track(track))) }
                    }
                }
            }
        }
    }

    private func buildAlbumItems() {
        displayItems.removeAll()
        for album in sortPlexAlbums(cachedAlbums) {
            let expanded = expandedAlbums.contains(album.id)
            displayItems.append(ModernDisplayItem(id: album.id, title: "\(album.parentTitle ?? "Unknown") - \(album.title)", info: album.year.map { String($0) }, indentLevel: 0, hasChildren: true, type: .album(album)))
            if expanded, let tracks = albumTracks[album.id] {
                for t in tracks { displayItems.append(ModernDisplayItem(id: t.id, title: t.title, info: t.formattedDuration, indentLevel: 1, hasChildren: false, type: .track(t))) }
            }
        }
    }
    
    private func buildMovieItems() {
        displayItems = cachedMovies.map { movie in
            let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
            return ModernDisplayItem(id: movie.id, title: movie.title, info: info.isEmpty ? nil : info, indentLevel: 0, hasChildren: false, type: .movie(movie))
        }
    }
    
    private func buildShowItems() {
        displayItems.removeAll()
        for show in cachedShows {
            let expanded = expandedShows.contains(show.id)
            let info = [show.year.map { String($0) }, "\(show.childCount) seasons"].compactMap { $0 }.joined(separator: " • ")
            displayItems.append(ModernDisplayItem(id: show.id, title: show.title, info: info, indentLevel: 0, hasChildren: true, type: .show(show)))
            if expanded, let seasons = showSeasons[show.id] {
                for season in seasons {
                    displayItems.append(ModernDisplayItem(id: season.id, title: season.title, info: "\(season.leafCount) episodes", indentLevel: 1, hasChildren: true, type: .season(season)))
                    if expandedSeasons.contains(season.id), let episodes = seasonEpisodes[season.id] {
                        for ep in episodes { displayItems.append(ModernDisplayItem(id: ep.id, title: "\(ep.episodeIdentifier) - \(ep.title)", info: ep.formattedDuration, indentLevel: 2, hasChildren: false, type: .episode(ep))) }
                    }
                }
            }
        }
    }
    
    private func buildJellyfinMovieItems() {
        displayItems = cachedJellyfinMovies.map { movie in
            let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
            return ModernDisplayItem(id: movie.id, title: movie.title, info: info.isEmpty ? nil : info, indentLevel: 0, hasChildren: false, type: .jellyfinMovie(movie))
        }
    }
    
    private func buildJellyfinShowItems() {
        displayItems.removeAll()
        for show in cachedJellyfinShows {
            let expanded = expandedJellyfinShows.contains(show.id)
            let info = [show.year.map { String($0) }, "\(show.childCount) seasons"].compactMap { $0 }.joined(separator: " • ")
            displayItems.append(ModernDisplayItem(id: show.id, title: show.title, info: info, indentLevel: 0, hasChildren: true, type: .jellyfinShow(show)))
            if expanded, let seasons = jellyfinShowSeasons[show.id] {
                for season in seasons {
                    displayItems.append(ModernDisplayItem(id: season.id, title: season.title, info: "\(season.childCount) episodes", indentLevel: 1, hasChildren: true, type: .jellyfinSeason(season)))
                    if expandedJellyfinSeasons.contains(season.id), let episodes = jellyfinSeasonEpisodes[season.id] {
                        for ep in episodes { displayItems.append(ModernDisplayItem(id: ep.id, title: "\(ep.episodeIdentifier) - \(ep.title)", info: ep.formattedDuration, indentLevel: 2, hasChildren: false, type: .jellyfinEpisode(ep))) }
                    }
                }
            }
        }
    }
    
    private func buildPlexPlaylistItems() {
        displayItems.removeAll()
        let audio = cachedPlexPlaylists.filter { $0.isAudioPlaylist }
        var seen = Set<String>()
        let unique = audio.filter { let n = $0.title.lowercased(); if seen.contains(n) { return false }; seen.insert(n); return true }
        for playlist in sortPlexPlaylists(unique) {
            let expanded = expandedPlexPlaylists.contains(playlist.id)
            displayItems.append(ModernDisplayItem(id: playlist.id, title: playlist.title, info: "\(playlist.leafCount) tracks", indentLevel: 0, hasChildren: playlist.leafCount > 0, type: .plexPlaylist(playlist)))
            if expanded, let tracks = plexPlaylistTracks[playlist.id] {
                for track in tracks { displayItems.append(ModernDisplayItem(id: "\(playlist.id)-\(track.id)", title: track.title, info: track.formattedDuration, indentLevel: 1, hasChildren: false, type: .track(track))) }
            }
        }
    }
    
    private func buildSearchItems() {
        displayItems.removeAll()
        guard let results = searchResults else { return }
        let sortedArtists = sortPlexArtists(results.artists)
        if !sortedArtists.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-artists", title: "Artists (\(sortedArtists.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for artist in sortedArtists { displayItems.append(ModernDisplayItem(id: artist.id, title: artist.title, info: nil, indentLevel: 1, hasChildren: true, type: .artist(artist))) }
        }
        let sortedAlbums = sortPlexAlbums(results.albums)
        if !sortedAlbums.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-albums", title: "Albums (\(sortedAlbums.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for album in sortedAlbums { displayItems.append(ModernDisplayItem(id: album.id, title: "\(album.parentTitle ?? "") - \(album.title)", info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .album(album))) }
        }
        let sortedTracks = sortPlexTracks(results.tracks)
        if !sortedTracks.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-tracks", title: "Tracks (\(sortedTracks.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for track in sortedTracks { displayItems.append(ModernDisplayItem(id: track.id, title: "\(track.grandparentTitle ?? "") - \(track.title)", info: track.formattedDuration, indentLevel: 1, hasChildren: false, type: .track(track))) }
        }
        if !results.movies.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-movies", title: "Movies (\(results.movies.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for movie in results.movies {
                let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
                displayItems.append(ModernDisplayItem(id: movie.id, title: movie.title, info: info.isEmpty ? nil : info, indentLevel: 1, hasChildren: false, type: .movie(movie)))
            }
        }
        if !results.shows.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-shows", title: "TV Shows (\(results.shows.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for show in results.shows { displayItems.append(ModernDisplayItem(id: show.id, title: show.title, info: "\(show.childCount) seasons", indentLevel: 1, hasChildren: true, type: .show(show))) }
        }
    }
    
    private func buildSubsonicSearchItems() {
        displayItems.removeAll()
        guard let results = subsonicSearchResults else { return }
        let sortedArtists = sortSubsonicArtists(results.artists)
        if !sortedArtists.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-artists", title: "Artists (\(sortedArtists.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for artist in sortedArtists {
                displayItems.append(ModernDisplayItem(id: artist.id, title: artist.name, info: artist.albumCount > 0 ? "\(artist.albumCount) albums" : nil, indentLevel: 1, hasChildren: true, type: .subsonicArtist(artist)))
            }
        }
        let sortedAlbums = sortSubsonicAlbums(results.albums)
        if !sortedAlbums.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-albums", title: "Albums (\(sortedAlbums.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for album in sortedAlbums {
                displayItems.append(ModernDisplayItem(id: album.id, title: album.name, info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .subsonicAlbum(album)))
            }
        }
        let sortedSongs = sortSubsonicTracks(results.songs)
        if !sortedSongs.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-tracks", title: "Tracks (\(sortedSongs.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for song in sortedSongs {
                displayItems.append(ModernDisplayItem(id: song.id, title: song.title, info: formatDuration(song.duration), indentLevel: 1, hasChildren: false, type: .subsonicTrack(song)))
            }
        }
    }

    private func buildJellyfinSearchItems() {
        displayItems.removeAll()
        guard let results = jellyfinSearchResults else { return }
        let sortedArtists = sortJellyfinArtists(results.artists)
        if !sortedArtists.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-artists", title: "Artists (\(sortedArtists.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for artist in sortedArtists {
                displayItems.append(ModernDisplayItem(id: artist.id, title: artist.name, info: artist.albumCount > 0 ? "\(artist.albumCount) albums" : nil, indentLevel: 1, hasChildren: true, type: .jellyfinArtist(artist)))
            }
        }
        let sortedAlbums = sortJellyfinAlbums(results.albums)
        if !sortedAlbums.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-albums", title: "Albums (\(sortedAlbums.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for album in sortedAlbums {
                displayItems.append(ModernDisplayItem(id: album.id, title: album.name, info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .jellyfinAlbum(album)))
            }
        }
        let sortedSongs = sortJellyfinTracks(results.songs)
        if !sortedSongs.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-tracks", title: "Tracks (\(sortedSongs.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for song in sortedSongs {
                displayItems.append(ModernDisplayItem(id: song.id, title: song.title, info: formatDuration(song.duration), indentLevel: 1, hasChildren: false, type: .jellyfinTrack(song)))
            }
        }
        if !results.movies.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-movies", title: "Movies (\(results.movies.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for movie in results.movies {
                let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
                displayItems.append(ModernDisplayItem(id: movie.id, title: movie.title, info: info.isEmpty ? nil : info, indentLevel: 1, hasChildren: false, type: .jellyfinMovie(movie)))
            }
        }
        if !results.shows.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-shows", title: "TV Shows (\(results.shows.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for show in results.shows {
                let info = [show.year.map { String($0) }, "\(show.childCount) seasons"].compactMap { $0 }.joined(separator: " • ")
                displayItems.append(ModernDisplayItem(id: show.id, title: show.title, info: info, indentLevel: 1, hasChildren: true, type: .jellyfinShow(show)))
            }
        }
    }

    private func buildEmbySearchItems() {
        displayItems.removeAll()
        guard let results = embySearchResults else { return }
        let sortedArtists = sortEmbyArtists(results.artists)
        if !sortedArtists.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-artists", title: "Artists (\(sortedArtists.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for artist in sortedArtists {
                displayItems.append(ModernDisplayItem(id: artist.id, title: artist.name, info: artist.albumCount > 0 ? "\(artist.albumCount) albums" : nil, indentLevel: 1, hasChildren: true, type: .embyArtist(artist)))
            }
        }
        let sortedAlbums = sortEmbyAlbums(results.albums)
        if !sortedAlbums.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-albums", title: "Albums (\(sortedAlbums.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for album in sortedAlbums {
                displayItems.append(ModernDisplayItem(id: album.id, title: album.name, info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .embyAlbum(album)))
            }
        }
        let sortedSongs = sortEmbyTracks(results.songs)
        if !sortedSongs.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-tracks", title: "Tracks (\(sortedSongs.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for song in sortedSongs {
                displayItems.append(ModernDisplayItem(id: song.id, title: song.title, info: formatDuration(song.duration), indentLevel: 1, hasChildren: false, type: .embyTrack(song)))
            }
        }
        if !results.movies.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-movies", title: "Movies (\(results.movies.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for movie in results.movies {
                let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
                displayItems.append(ModernDisplayItem(id: movie.id, title: movie.title, info: info.isEmpty ? nil : info, indentLevel: 1, hasChildren: false, type: .embyMovie(movie)))
            }
        }
        if !results.shows.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-shows", title: "TV Shows (\(results.shows.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for show in results.shows {
                let info = [show.year.map { String($0) }, "\(show.childCount) seasons"].compactMap { $0 }.joined(separator: " • ")
                displayItems.append(ModernDisplayItem(id: show.id, title: show.title, info: info, indentLevel: 1, hasChildren: true, type: .embyShow(show)))
            }
        }
    }

    private func buildRadioStationItems() {
        displayItems.removeAll()
        cachedRadioFolders = RadioManager.shared.internetRadioFolderDescriptors()

        let childrenByParent = Dictionary(grouping: cachedRadioFolders.filter { $0.parentID != nil }) { $0.parentID! }
        let roots = cachedRadioFolders
            .filter { $0.parentID == nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        for root in roots {
            appendRadioFolderRow(root, level: 0, childrenByParent: childrenByParent)
        }
    }

    // MARK: - YouTube (shares the Radio tab UI as its own source)

    private func loadYouTubeChannels() {
        isLoading = false
        errorMessage = nil
        stopLoadingAnimation()
        buildYouTubeChannelItems()
        needsDisplay = true
    }

    private func buildYouTubeChannelItems() {
        displayItems.removeAll()
        for channel in YouTubeManager.shared.channels {
            displayItems.append(
                ModernDisplayItem(
                    id: "youtube-channel-\(channel.id)",
                    title: channel.title,
                    info: nil,
                    indentLevel: 0,
                    hasChildren: true,
                    type: .youtubeChannel(channel)
                )
            )
            guard expandedYouTubeChannels.contains(channel.id), let videos = youtubeChannelVideos[channel.id] else { continue }
            for video in videos {
                let isDownloaded = YouTubeManager.shared.isDownloaded(video.videoId)
                let marker = isDownloaded ? "⬇ " : ""
                displayItems.append(
                    ModernDisplayItem(
                        id: "youtube-video-\(video.videoId)",
                        title: marker + video.title,
                        info: video.formattedDuration,
                        indentLevel: 1,
                        hasChildren: false,
                        type: .youtubeVideo(video)
                    )
                )
            }
        }
    }

    private func buildRadioSearchItems() {
        displayItems.removeAll()
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let matches = RadioManager.shared.searchStations(query: searchQuery)
        for station in matches {
            displayItems.append(
                ModernDisplayItem(
                    id: "radio-search-\(station.id.uuidString)",
                    title: station.name,
                    info: RadioManager.shared.normalizedGenre(for: station),
                    indentLevel: 0,
                    hasChildren: false,
                    type: .radioStation(station)
                )
            )
        }
    }

    private func appendRadioFolderRow(
        _ folder: RadioFolderDescriptor,
        level: Int,
        childrenByParent: [String: [RadioFolderDescriptor]]
    ) {
        displayItems.append(
            ModernDisplayItem(
                id: folder.id,
                title: folder.title,
                info: nil,
                indentLevel: level,
                hasChildren: folder.hasChildren,
                type: .radioFolder(folder)
            )
        )

        guard folder.hasChildren, expandedRadioFolders.contains(folder.id) else { return }
        if folder.kind.isStationContainer {
            let stations = RadioManager.shared.stations(inFolder: folder.kind)
            for station in stations {
                displayItems.append(
                    ModernDisplayItem(
                        id: "radio-station-\(folder.id)-\(station.id.uuidString)",
                        title: station.name,
                        info: RadioManager.shared.normalizedGenre(for: station),
                        indentLevel: level + 1,
                        hasChildren: false,
                        type: .radioStation(station)
                    )
                )
            }
            return
        }
        let children = (childrenByParent[folder.id] ?? []).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        for child in children {
            appendRadioFolderRow(child, level: level + 1, childrenByParent: childrenByParent)
        }
    }
    
    private func loadSubsonicRadioStations(generation: Int? = nil) {
        let generation = generation ?? loadGeneration
        guard case .subsonic = currentSource else { return }
        let expectedSource = currentSource
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        radioLoadTask?.cancel()
        radioLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let genres = await SubsonicManager.shared.getGenres()
            guard !Task.isCancelled,
                  self.isLoadContextActive(generation, source: expectedSource),
                  self.browseMode == .radio,
                  case .subsonic = self.currentSource else { return }
            self.buildSubsonicRadioStationItems(genres: genres)
            self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
            self.radioLoadTask = nil
        }
    }

    private func loadJellyfinRadioStations(generation: Int? = nil) {
        let generation = generation ?? loadGeneration
        guard case .jellyfin = currentSource else { return }
        let expectedSource = currentSource
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        radioLoadTask?.cancel()
        radioLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let genres = await JellyfinManager.shared.getMusicGenres()
            guard !Task.isCancelled,
                  self.isLoadContextActive(generation, source: expectedSource),
                  self.browseMode == .radio,
                  case .jellyfin = self.currentSource else { return }
            self.buildJellyfinRadioStationItems(genres: genres)
            self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
            self.radioLoadTask = nil
        }
    }

    private func loadEmbyRadioStations(generation: Int? = nil) {
        let generation = generation ?? loadGeneration
        guard case .emby = currentSource else { return }
        let expectedSource = currentSource
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        radioLoadTask?.cancel()
        radioLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let genres = await EmbyManager.shared.getMusicGenres()
            guard !Task.isCancelled,
                  self.isLoadContextActive(generation, source: expectedSource),
                  self.browseMode == .radio,
                  case .emby = self.currentSource else { return }
            self.buildEmbyRadioStationItems(genres: genres)
            self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
            self.radioLoadTask = nil
        }
    }

    private func loadLocalRadioStations() {
        isLoading = false; errorMessage = nil; stopLoadingAnimation()
        let genres = MediaLibrary.shared.allGenres()
        buildLocalRadioStationItems(genres: genres)
        needsDisplay = true
    }

    private func buildSubsonicRadioStationItems(genres: [String]) {
        displayItems.removeAll()
        displayItems.append(ModernDisplayItem(id: "sub-radio-library", title: "Library Radio", info: "Library", indentLevel: 0, hasChildren: false, type: .subsonicRadioStation(.libraryRadio)))
        displayItems.append(ModernDisplayItem(id: "sub-radio-library-sim", title: "Library Radio (Similar)", info: "Library", indentLevel: 0, hasChildren: false, type: .subsonicRadioStation(.librarySimilar)))
        displayItems.append(ModernDisplayItem(id: "sub-radio-starred", title: "Starred Radio", info: "Starred", indentLevel: 0, hasChildren: false, type: .subsonicRadioStation(.starredRadio)))
        displayItems.append(ModernDisplayItem(id: "sub-radio-starred-sim", title: "Starred Radio (Similar)", info: "Starred", indentLevel: 0, hasChildren: false, type: .subsonicRadioStation(.starredSimilar)))
        for genre in genres {
            displayItems.append(ModernDisplayItem(id: "sub-radio-genre-\(genre)", title: "\(genre) Radio", info: "Genre", indentLevel: 0, hasChildren: false, type: .subsonicRadioStation(.genreRadio(genre))))
            displayItems.append(ModernDisplayItem(id: "sub-radio-genre-\(genre)-sim", title: "\(genre) Radio (Similar)", info: "Genre", indentLevel: 0, hasChildren: false, type: .subsonicRadioStation(.genreSimilar(genre))))
        }
        for decade in RadioConfig.decades {
            displayItems.append(ModernDisplayItem(id: "sub-radio-decade-\(decade.name)", title: "\(decade.name) Radio", info: "Decade", indentLevel: 0, hasChildren: false, type: .subsonicRadioStation(.decadeRadio(start: decade.start, end: decade.end, name: decade.name))))
            displayItems.append(ModernDisplayItem(id: "sub-radio-decade-\(decade.name)-sim", title: "\(decade.name) Radio (Similar)", info: "Decade", indentLevel: 0, hasChildren: false, type: .subsonicRadioStation(.decadeSimilar(start: decade.start, end: decade.end, name: decade.name))))
        }
    }

    private func buildJellyfinRadioStationItems(genres: [String]) {
        displayItems.removeAll()
        displayItems.append(ModernDisplayItem(id: "jf-radio-library", title: "Library Radio", info: "Library", indentLevel: 0, hasChildren: false, type: .jellyfinRadioStation(.libraryRadio)))
        displayItems.append(ModernDisplayItem(id: "jf-radio-library-mix", title: "Library Radio (Instant Mix)", info: "Library", indentLevel: 0, hasChildren: false, type: .jellyfinRadioStation(.libraryInstantMix)))
        displayItems.append(ModernDisplayItem(id: "jf-radio-fav", title: "Favorites Radio", info: "Favorites", indentLevel: 0, hasChildren: false, type: .jellyfinRadioStation(.favoritesRadio)))
        displayItems.append(ModernDisplayItem(id: "jf-radio-fav-mix", title: "Favorites Radio (Instant Mix)", info: "Favorites", indentLevel: 0, hasChildren: false, type: .jellyfinRadioStation(.favoritesInstantMix)))
        for genre in genres {
            displayItems.append(ModernDisplayItem(id: "jf-radio-genre-\(genre)", title: "\(genre) Radio", info: "Genre", indentLevel: 0, hasChildren: false, type: .jellyfinRadioStation(.genreRadio(genre))))
            displayItems.append(ModernDisplayItem(id: "jf-radio-genre-\(genre)-mix", title: "\(genre) Radio (Instant Mix)", info: "Genre", indentLevel: 0, hasChildren: false, type: .jellyfinRadioStation(.genreInstantMix(genre))))
        }
        for decade in RadioConfig.decades {
            displayItems.append(ModernDisplayItem(id: "jf-radio-decade-\(decade.name)", title: "\(decade.name) Radio", info: "Decade", indentLevel: 0, hasChildren: false, type: .jellyfinRadioStation(.decadeRadio(start: decade.start, end: decade.end, name: decade.name))))
            displayItems.append(ModernDisplayItem(id: "jf-radio-decade-\(decade.name)-mix", title: "\(decade.name) Radio (Instant Mix)", info: "Decade", indentLevel: 0, hasChildren: false, type: .jellyfinRadioStation(.decadeInstantMix(start: decade.start, end: decade.end, name: decade.name))))
        }
    }

    private func buildEmbyRadioStationItems(genres: [String]) {
        displayItems.removeAll()
        displayItems.append(ModernDisplayItem(id: "emby-radio-library", title: "Library Radio", info: "Library", indentLevel: 0, hasChildren: false, type: .embyRadioStation(.libraryRadio)))
        displayItems.append(ModernDisplayItem(id: "emby-radio-library-mix", title: "Library Radio (Instant Mix)", info: "Library", indentLevel: 0, hasChildren: false, type: .embyRadioStation(.libraryInstantMix)))
        displayItems.append(ModernDisplayItem(id: "emby-radio-fav", title: "Favorites Radio", info: "Favorites", indentLevel: 0, hasChildren: false, type: .embyRadioStation(.favoritesRadio)))
        displayItems.append(ModernDisplayItem(id: "emby-radio-fav-mix", title: "Favorites Radio (Instant Mix)", info: "Favorites", indentLevel: 0, hasChildren: false, type: .embyRadioStation(.favoritesInstantMix)))
        for genre in genres {
            displayItems.append(ModernDisplayItem(id: "emby-radio-genre-\(genre)", title: "\(genre) Radio", info: "Genre", indentLevel: 0, hasChildren: false, type: .embyRadioStation(.genreRadio(genre))))
            displayItems.append(ModernDisplayItem(id: "emby-radio-genre-\(genre)-mix", title: "\(genre) Radio (Instant Mix)", info: "Genre", indentLevel: 0, hasChildren: false, type: .embyRadioStation(.genreInstantMix(genre))))
        }
        for decade in RadioConfig.decades {
            displayItems.append(ModernDisplayItem(id: "emby-radio-decade-\(decade.name)", title: "\(decade.name) Radio", info: "Decade", indentLevel: 0, hasChildren: false, type: .embyRadioStation(.decadeRadio(start: decade.start, end: decade.end, name: decade.name))))
            displayItems.append(ModernDisplayItem(id: "emby-radio-decade-\(decade.name)-mix", title: "\(decade.name) Radio (Instant Mix)", info: "Decade", indentLevel: 0, hasChildren: false, type: .embyRadioStation(.decadeInstantMix(start: decade.start, end: decade.end, name: decade.name))))
        }
    }

    private func buildLocalRadioStationItems(genres: [String]) {
        displayItems.removeAll()
        displayItems.append(ModernDisplayItem(id: "local-radio-library", title: "Library Radio", info: "Library", indentLevel: 0, hasChildren: false, type: .localRadioStation(.libraryRadio)))
        for genre in genres {
            displayItems.append(ModernDisplayItem(id: "local-radio-genre-\(genre)", title: "\(genre) Radio", info: "Genre", indentLevel: 0, hasChildren: false, type: .localRadioStation(.genreRadio(genre))))
        }
        for decade in RadioConfig.decades {
            displayItems.append(ModernDisplayItem(id: "local-radio-decade-\(decade.name)", title: "\(decade.name) Radio", info: "Decade", indentLevel: 0, hasChildren: false, type: .localRadioStation(.decadeRadio(start: decade.start, end: decade.end, name: decade.name))))
        }
    }

    private func buildPlexRadioStationItems(genres: [String]) {
        displayItems.removeAll()
        NSLog("ModernLibraryBrowserView: Building Plex radio station list with %d genres", genres.count)
#if DEBUG
        let hasJazz = genres.contains { $0.localizedCaseInsensitiveCompare("Jazz") == .orderedSame }
        NSLog("ModernLibraryBrowserView: Plex radio station genres contain Jazz=%@; genres=%@",
              hasJazz ? "yes" : "no", genres.joined(separator: ", "))
#endif
        // Library Radio
        displayItems.append(ModernDisplayItem(id: "plex-radio-library", title: "Library Radio", info: "Library", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.libraryRadio)))
        displayItems.append(ModernDisplayItem(id: "plex-radio-library-sonic", title: "Library Radio (Sonic)", info: "Library", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.libraryRadioSonic)))
        // Popularity
        displayItems.append(ModernDisplayItem(id: "plex-radio-hits", title: "Only the Hits", info: "Popularity", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.hitsRadio)))
        displayItems.append(ModernDisplayItem(id: "plex-radio-hits-sonic", title: "Only the Hits (Sonic)", info: "Popularity", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.hitsRadioSonic)))
        displayItems.append(ModernDisplayItem(id: "plex-radio-deepcuts", title: "Deep Cuts", info: "Popularity", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.deepCutsRadio)))
        displayItems.append(ModernDisplayItem(id: "plex-radio-deepcuts-sonic", title: "Deep Cuts (Sonic)", info: "Popularity", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.deepCutsRadioSonic)))
        // Rating stations
        for station in RadioConfig.ratingStations {
            displayItems.append(ModernDisplayItem(id: "plex-radio-rating-\(station.minRating)", title: "\(station.name) Radio", info: "My Ratings", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.ratingRadio(minRating: station.minRating, name: station.name))))
            displayItems.append(ModernDisplayItem(id: "plex-radio-rating-\(station.minRating)-sonic", title: "\(station.name) Radio (Sonic)", info: "My Ratings", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.ratingRadioSonic(minRating: station.minRating, name: station.name))))
        }
        // Genre stations
        for genre in genres {
            displayItems.append(ModernDisplayItem(id: "plex-radio-genre-\(genre)", title: "\(genre) Radio", info: "Genre", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.genreRadio(genre))))
            displayItems.append(ModernDisplayItem(id: "plex-radio-genre-\(genre)-sonic", title: "\(genre) Radio (Sonic)", info: "Genre", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.genreRadioSonic(genre))))
        }
        // Decade stations
        for decade in RadioConfig.decades {
            displayItems.append(ModernDisplayItem(id: "plex-radio-decade-\(decade.name)", title: "\(decade.name) Radio", info: "Decade", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.decadeRadio(start: decade.start, end: decade.end, name: decade.name))))
            displayItems.append(ModernDisplayItem(id: "plex-radio-decade-\(decade.name)-sonic", title: "\(decade.name) Radio (Sonic)", info: "Decade", indentLevel: 0, hasChildren: false, type: .plexRadioStation(.decadeRadioSonic(start: decade.start, end: decade.end, name: decade.name))))
        }
    }
    
    // Local items
    private func buildLocalArtistItems() {
        displayItems.removeAll()
        let store = MediaLibraryStore.shared
        if localArtistPageOffset == 0 {
            localArtistLetterOffsets = store.artistLetterOffsets(sort: currentSort)
        }
        let names = store.artistNames(limit: localPageSize, offset: localArtistPageOffset, sort: currentSort)
        let albumsByArtist = store.albumsForArtistsBatch(names)
        for name in names {
            let albumSummaries = albumsByArtist[name] ?? []
            let albumCount = albumSummaries.count
            // Build a minimal Artist stub — albums are populated lazily when expanded
            let stubArtist = Artist(id: name, name: name, albums: [])
            let expanded = expandedLocalArtists.contains(name)
            displayItems.append(ModernDisplayItem(
                id: "local-artist-\(name)",
                title: name,
                info: "\(albumCount) albums",
                indentLevel: 0,
                hasChildren: albumCount > 0,
                type: .localArtist(stubArtist)
            ))
            if expanded {
                for summary in albumSummaries {
                    let albumExpanded = expandedLocalAlbums.contains(summary.id)
                    let tracks: [LibraryTrack] = albumExpanded ? store.tracksForAlbum(summary.id) : []
                    let album = Album(
                        id: summary.id,
                        name: summary.name,
                        artist: summary.artist,
                        year: summary.year,
                        tracks: tracks
                    )
                    displayItems.append(ModernDisplayItem(
                        id: "local-album-\(album.id)",
                        title: album.name,
                        info: summary.year.map { String($0) },
                        indentLevel: 1,
                        hasChildren: summary.trackCount > 0,
                        type: .localAlbum(album)
                    ))
                    if albumExpanded {
                        for track in tracks {
                            displayItems.append(ModernDisplayItem(
                                id: track.id.uuidString,
                                title: track.title,
                                info: track.formattedDuration,
                                indentLevel: 2,
                                hasChildren: false,
                                type: .localTrack(track)
                            ))
                        }
                    }
                }
            }
        }
    }
    
    private func buildLocalAlbumItems() {
        displayItems.removeAll()
        let store = MediaLibraryStore.shared
        if localAlbumPageOffset == 0 {
            localAlbumLetterOffsets = store.albumLetterOffsets(sort: currentSort)
        }
        let summaries = store.albumSummaries(limit: localPageSize, offset: localAlbumPageOffset, sort: currentSort)
        for summary in summaries {
            let expanded = expandedLocalAlbums.contains(summary.id)
            let tracks: [LibraryTrack] = expanded ? store.tracksForAlbum(summary.id) : []
            let album = Album(id: summary.id, name: summary.name, artist: summary.artist, year: summary.year, tracks: tracks)
            let displayName: String
            if let artist = summary.artist, !artist.isEmpty {
                displayName = "\(artist) - \(summary.name)"
            } else {
                displayName = summary.name
            }
            displayItems.append(ModernDisplayItem(
                id: "local-album-\(album.id)",
                title: displayName,
                info: "\(summary.trackCount) tracks",
                indentLevel: 0,
                hasChildren: summary.trackCount > 0,
                type: .localAlbum(album)
            ))
            if expanded {
                for t in tracks {
                    displayItems.append(ModernDisplayItem(
                        id: t.id.uuidString,
                        title: t.title,
                        info: t.formattedDuration,
                        indentLevel: 1,
                        hasChildren: false,
                        type: .localTrack(t)
                    ))
                }
            }
        }
    }

    /// Build the Folders view: one off-actor depth-first walk of every *expanded* directory,
    /// then a single hop back to the main actor to assign `displayItems`. The generation guard
    /// discards a walk whose result arrives after a newer rebuild (or a mode switch) started.
    private func buildLocalFolderItems() {
        localFolderBuildGeneration &+= 1
        let gen = localFolderBuildGeneration

        // Snapshot main-actor state before going off-actor (value types are Sendable)
        let expandedSnapshot = expandedLocalFolders

        // Show the loading spinner (not the empty "No folders found" state) while the
        // off-actor walk runs — matters for slow network/NAS watch folders.
        displayItems.removeAll()
        isLoading = true
        errorMessage = nil
        startLoadingAnimation()
        needsDisplay = true

        // Cancel any walk still running from a previous (faster) click
        localFolderBuildTask?.cancel()
        localFolderBuildTask = Task.detached { [weak self] in
            // Build the ordered item list entirely off the main actor (FS enumeration + DB query).
            // watchFolderSummaries() blocks on dataQueue.sync (four full-array snapshots), which a
            // running import scan can hold for seconds — compute it here, not on the main actor.
            let availableFolderURLs = MediaLibrary.shared.watchFolderSummaries()
                .filter { $0.isAvailable }
                .map { $0.url }
            var items: [ModernDisplayItem] = []

            func walk(_ url: URL, indent: Int) {
                if Task.isCancelled { return }
                var subdirectories: [(url: URL, name: String)] = []
                var audioFiles: [URL] = []
                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                    for item in contents {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                // Skip symlinked dirs to prevent infinite recursion
                                if item.resolvingSymlinksInPath().path == item.path {
                                    subdirectories.append((url: item, name: item.lastPathComponent))
                                }
                            } else if LocalFileDiscovery.isSupportedAudioFile(item) {
                                audioFiles.append(item)
                            }
                        }
                    }
                }
                // Directories first, then files; both case-insensitive by name
                subdirectories.sort { $0.name.lowercased() < $1.name.lowercased() }
                audioFiles.sort { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }

                for (subURL, subName) in subdirectories {
                    items.append(ModernDisplayItem(
                        id: subURL.path, title: subName, info: nil,
                        indentLevel: indent, hasChildren: true,
                        type: .localFolder(url: subURL, name: subName)))
                    // Recurse in place so a child's contents follow it directly (correct tree order)
                    if expandedSnapshot.contains(subURL.path) {
                        walk(subURL, indent: indent + 1)
                    }
                }

                let urlToTrackMap = MediaLibraryStore.shared.tracks(forURLs: audioFiles)
                for fileURL in audioFiles {
                    let track = urlToTrackMap[fileURL] ?? LibraryTrack(url: fileURL)
                    items.append(ModernDisplayItem(
                        id: track.id.uuidString, title: track.title,
                        info: track.formattedDuration, indentLevel: indent, hasChildren: false,
                        type: .localTrack(track)))
                }
            }

            if availableFolderURLs.count > 1 {
                // Multiple watch folders: each is a top-level node
                for folderURL in availableFolderURLs {
                    items.append(ModernDisplayItem(
                        id: folderURL.path, title: folderURL.lastPathComponent, info: nil,
                        indentLevel: 0, hasChildren: true,
                        type: .localFolder(url: folderURL, name: folderURL.lastPathComponent)))
                    if expandedSnapshot.contains(folderURL.path) {
                        walk(folderURL, indent: 1)
                    }
                }
            } else if let only = availableFolderURLs.first {
                // Single watch folder: show its contents directly
                walk(only, indent: 0)
            }

            if Task.isCancelled { return }
            let builtItems = items
            await MainActor.run { [weak self] in
                guard let self = self,
                      self.localFolderBuildGeneration == gen,
                      self.isLocalSource,
                      self.browseMode == .folders else { return }
                self.isLoading = false
                self.stopLoadingAnimation()
                self.displayItems = builtItems
                self.needsDisplay = true
                self.localFolderBuildTask = nil
            }
        }
    }

    private func buildLocalSearchItems() {
        displayItems.removeAll()
        guard !searchQuery.isEmpty else { return }
        let store = MediaLibraryStore.shared
        let matchingArtistNames = store.searchArtistNames(query: searchQuery)
        if !matchingArtistNames.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-local-artists", title: "Artists (\(matchingArtistNames.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for name in matchingArtistNames {
                let stub = Artist(id: name, name: name, albums: [])
                displayItems.append(ModernDisplayItem(id: "local-artist-\(name)", title: name, info: nil, indentLevel: 1, hasChildren: true, type: .localArtist(stub)))
            }
        }
        let matchingAlbums = store.searchAlbumSummaries(query: searchQuery)
        if !matchingAlbums.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-local-albums", title: "Albums (\(matchingAlbums.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for summary in matchingAlbums {
                let displayName: String
                if let artist = summary.artist, !artist.isEmpty {
                    displayName = "\(artist) - \(summary.name)"
                } else {
                    displayName = summary.name
                }
                let album = Album(id: summary.id, name: summary.name, artist: summary.artist, year: summary.year, tracks: [])
                displayItems.append(ModernDisplayItem(id: "local-album-\(album.id)", title: displayName, info: "\(summary.trackCount) tracks", indentLevel: 1, hasChildren: false, type: .localAlbum(album)))
            }
        }
        let matchingTracks = store.searchTracks(query: searchQuery, limit: 200, offset: 0)
        if !matchingTracks.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-local-tracks", title: "Tracks (\(matchingTracks.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for t in matchingTracks { displayItems.append(ModernDisplayItem(id: t.id.uuidString, title: t.displayTitle, info: t.formattedDuration, indentLevel: 1, hasChildren: false, type: .localTrack(t))) }
        }
    }
    
    private func buildLocalMovieItems() {
        displayItems = cachedLocalMovies
            .sorted { compareNameStrings($0.title, $1.title, ascending: true) }
            .map { ModernDisplayItem(id: $0.id.uuidString, title: $0.title, info: $0.year.map { String($0) }, indentLevel: 0, hasChildren: false, type: .localMovie($0)) }
    }

    private func buildLocalShowItems() {
        displayItems.removeAll()
        for show in cachedLocalShows.sorted(by: { compareNameStrings($0.title, $1.title, ascending: true) }) {
            let expanded = expandedLocalShows.contains(show.id)
            displayItems.append(ModernDisplayItem(id: "local-show-\(show.id)", title: show.title, info: "\(show.episodeCount) episodes", indentLevel: 0, hasChildren: true, type: .localShow(show)))
            if expanded {
                for season in show.seasons.sorted(by: { $0.number < $1.number }) {
                    let seasonKey = "\(show.title)|\(season.number)"
                    let seasonExpanded = expandedLocalSeasons.contains(seasonKey)
                    displayItems.append(ModernDisplayItem(id: "local-season-\(seasonKey)", title: "Season \(season.number)", info: "\(season.episodes.count) episodes", indentLevel: 1, hasChildren: true, type: .localSeason(season, showTitle: show.title)))
                    if seasonExpanded {
                        for episode in season.episodes.sorted(by: { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }) {
                            let epTitle = episode.episodeNumber.map { "E\($0): \(episode.title)" } ?? episode.title
                            displayItems.append(ModernDisplayItem(id: episode.id.uuidString, title: epTitle, info: episode.formattedDuration, indentLevel: 2, hasChildren: false, type: .localEpisode(episode)))
                        }
                    }
                }
            }
        }
    }

    // Subsonic items
    private func buildSubsonicArtistItems() {
        displayItems.removeAll()
        for artist in sortSubsonicArtists(cachedSubsonicArtists) {
            let info = artist.albumCount > 0 ? "\(artist.albumCount) albums" : nil
            let expanded = expandedSubsonicArtists.contains(artist.id)
            displayItems.append(ModernDisplayItem(id: artist.id, title: artist.name, info: info, indentLevel: 0, hasChildren: true, type: .subsonicArtist(artist)))
            if expanded, let albums = subsonicArtistAlbums[artist.id] {
                for album in sortSubsonicAlbums(albums) {
                    let albumExpanded = expandedSubsonicAlbums.contains(album.id)
                    displayItems.append(ModernDisplayItem(id: album.id, title: album.name, info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .subsonicAlbum(album)))
                    if albumExpanded, let songs = subsonicAlbumSongs[album.id] {
                        let sorted = songs.sorted { let d0 = $0.discNumber ?? 1; let d1 = $1.discNumber ?? 1; if d0 != d1 { return d0 < d1 }; return ($0.track ?? 0) < ($1.track ?? 0) }
                        for song in sorted { displayItems.append(ModernDisplayItem(id: song.id, title: song.title, info: formatDuration(song.duration), indentLevel: 2, hasChildren: false, type: .subsonicTrack(song))) }
                    }
                }
            }
        }
    }

    private func buildSubsonicAlbumItems() {
        displayItems.removeAll()
        for album in sortSubsonicAlbums(cachedSubsonicAlbums) {
            let expanded = expandedSubsonicAlbums.contains(album.id)
            displayItems.append(ModernDisplayItem(id: album.id, title: "\(album.artist ?? "Unknown") - \(album.name)", info: album.year.map { String($0) }, indentLevel: 0, hasChildren: true, type: .subsonicAlbum(album)))
            if expanded, let songs = subsonicAlbumSongs[album.id] {
                let sorted = songs.sorted { ($0.track ?? 0) < ($1.track ?? 0) }
                for s in sorted { displayItems.append(ModernDisplayItem(id: s.id, title: s.title, info: formatDuration(s.duration), indentLevel: 1, hasChildren: false, type: .subsonicTrack(s))) }
            }
        }
    }
    
    private func buildSubsonicPlaylistItems() {
        displayItems.removeAll()
        for playlist in sortSubsonicPlaylists(cachedSubsonicPlaylists) {
            let expanded = expandedSubsonicPlaylists.contains(playlist.id)
            displayItems.append(ModernDisplayItem(id: playlist.id, title: playlist.name, info: "\(playlist.songCount) tracks", indentLevel: 0, hasChildren: playlist.songCount > 0, type: .subsonicPlaylist(playlist)))
            if expanded, let tracks = subsonicPlaylistTracks[playlist.id] {
                for t in tracks { displayItems.append(ModernDisplayItem(id: "\(playlist.id)-\(t.id)", title: t.title, info: formatDuration(t.duration), indentLevel: 1, hasChildren: false, type: .subsonicTrack(t))) }
            }
        }
    }

    private func buildLocalPlaylistItems() {
        displayItems.removeAll()
        for playlist in cachedLocalPlaylists.sorted(by: { $0.title.lowercased() < $1.title.lowercased() }) {
            let key = playlist.url.path
            let expanded = expandedLocalPlaylists.contains(key)
            let info = localPlaylistTracks[key].map { "\($0.count) tracks" }
            displayItems.append(ModernDisplayItem(id: key, title: playlist.title, info: info, indentLevel: 0, hasChildren: true, type: .localPlaylist(playlist)))
            if expanded, let tracks = localPlaylistTracks[key] {
                for t in tracks {
                    let duration = t.duration.map { Int($0) }
                    let title = t.title ?? "Unknown"
                    displayItems.append(ModernDisplayItem(id: "\(key)-\(t.url.absoluteString)", title: title, info: formatDuration(duration), indentLevel: 1, hasChildren: false, type: .localPlaylistTrack(t)))
                }
            }
        }
    }

    private func refreshCachedLocalPlaylists() {
        cachedLocalPlaylists = MediaLibrary.shared.playlistsSnapshot
        let validKeys = Set(cachedLocalPlaylists.map { $0.url.path })
        localPlaylistTracks = localPlaylistTracks.filter { validKeys.contains($0.key) }
        expandedLocalPlaylists.formIntersection(validKeys)
    }

    private func playLocalPlaylist(_ url: URL) {
        Task.detached {
            let tracks = parseModernLocalPlaylistTracks(at: url)
            await MainActor.run {
                WindowManager.shared.audioEngine.playNow(tracks)
            }
        }
    }

    // MARK: - Build Jellyfin Display Items
    
    private func buildJellyfinArtistItems() {
        displayItems.removeAll()
        for artist in sortJellyfinArtists(cachedJellyfinArtists) {
            let info = artist.albumCount > 0 ? "\(artist.albumCount) albums" : nil
            let expanded = expandedJellyfinArtists.contains(artist.id)
            displayItems.append(ModernDisplayItem(id: artist.id, title: artist.name, info: info, indentLevel: 0, hasChildren: true, type: .jellyfinArtist(artist)))
            if expanded, let albums = jellyfinArtistAlbums[artist.id] {
                for album in sortJellyfinAlbums(albums) {
                    let albumExpanded = expandedJellyfinAlbums.contains(album.id)
                    displayItems.append(ModernDisplayItem(id: album.id, title: album.name, info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .jellyfinAlbum(album)))
                    if albumExpanded, let songs = jellyfinAlbumSongs[album.id] {
                        let sorted = songs.sorted { let d0 = $0.discNumber ?? 1; let d1 = $1.discNumber ?? 1; if d0 != d1 { return d0 < d1 }; return ($0.track ?? 0) < ($1.track ?? 0) }
                        for song in sorted { displayItems.append(ModernDisplayItem(id: song.id, title: song.title, info: formatDuration(song.duration), indentLevel: 2, hasChildren: false, type: .jellyfinTrack(song))) }
                    }
                }
            }
        }
    }

    private func buildJellyfinAlbumItems() {
        displayItems.removeAll()
        for album in sortJellyfinAlbums(cachedJellyfinAlbums) {
            let expanded = expandedJellyfinAlbums.contains(album.id)
            displayItems.append(ModernDisplayItem(id: album.id, title: "\(album.artist ?? "Unknown") - \(album.name)", info: album.year.map { String($0) }, indentLevel: 0, hasChildren: true, type: .jellyfinAlbum(album)))
            if expanded, let songs = jellyfinAlbumSongs[album.id] {
                let sorted = songs.sorted { let d0 = $0.discNumber ?? 1; let d1 = $1.discNumber ?? 1; if d0 != d1 { return d0 < d1 }; return ($0.track ?? 0) < ($1.track ?? 0) }
                for s in sorted { displayItems.append(ModernDisplayItem(id: s.id, title: s.title, info: formatDuration(s.duration), indentLevel: 1, hasChildren: false, type: .jellyfinTrack(s))) }
            }
        }
    }
    
    private func buildJellyfinPlaylistItems() {
        displayItems.removeAll()
        for playlist in sortJellyfinPlaylists(cachedJellyfinPlaylists) {
            let expanded = expandedJellyfinPlaylists.contains(playlist.id)
            displayItems.append(ModernDisplayItem(id: playlist.id, title: playlist.name, info: "\(playlist.songCount) tracks", indentLevel: 0, hasChildren: playlist.songCount > 0, type: .jellyfinPlaylist(playlist)))
            if expanded, let tracks = jellyfinPlaylistTracks[playlist.id] {
                for t in tracks { displayItems.append(ModernDisplayItem(id: "\(playlist.id)-\(t.id)", title: t.title, info: formatDuration(t.duration), indentLevel: 1, hasChildren: false, type: .jellyfinTrack(t))) }
            }
        }
    }

    // MARK: - Build Emby Display Items

    private func buildEmbyArtistItems() {
        displayItems.removeAll()
        for artist in sortEmbyArtists(cachedEmbyArtists) {
            let info = artist.albumCount > 0 ? "\(artist.albumCount) albums" : nil
            let expanded = expandedEmbyArtists.contains(artist.id)
            displayItems.append(ModernDisplayItem(id: artist.id, title: artist.name, info: info, indentLevel: 0, hasChildren: true, type: .embyArtist(artist)))
            if expanded, let albums = embyArtistAlbums[artist.id] {
                for album in sortEmbyAlbums(albums) {
                    let albumExpanded = expandedEmbyAlbums.contains(album.id)
                    displayItems.append(ModernDisplayItem(id: album.id, title: album.name, info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .embyAlbum(album)))
                    if albumExpanded, let songs = embyAlbumSongs[album.id] {
                        let sorted = songs.sorted { let d0 = $0.discNumber ?? 1; let d1 = $1.discNumber ?? 1; if d0 != d1 { return d0 < d1 }; return ($0.track ?? 0) < ($1.track ?? 0) }
                        for song in sorted { displayItems.append(ModernDisplayItem(id: song.id, title: song.title, info: formatDuration(song.duration), indentLevel: 2, hasChildren: false, type: .embyTrack(song))) }
                    }
                }
            }
        }
    }

    private func buildEmbyAlbumItems() {
        displayItems.removeAll()
        for album in sortEmbyAlbums(cachedEmbyAlbums) {
            let expanded = expandedEmbyAlbums.contains(album.id)
            displayItems.append(ModernDisplayItem(id: album.id, title: "\(album.artist ?? "Unknown") - \(album.name)", info: album.year.map { String($0) }, indentLevel: 0, hasChildren: true, type: .embyAlbum(album)))
            if expanded, let songs = embyAlbumSongs[album.id] {
                let sorted = songs.sorted { let d0 = $0.discNumber ?? 1; let d1 = $1.discNumber ?? 1; if d0 != d1 { return d0 < d1 }; return ($0.track ?? 0) < ($1.track ?? 0) }
                for s in sorted { displayItems.append(ModernDisplayItem(id: s.id, title: s.title, info: formatDuration(s.duration), indentLevel: 1, hasChildren: false, type: .embyTrack(s))) }
            }
        }
    }

    private func buildEmbyPlaylistItems() {
        displayItems.removeAll()
        for playlist in sortEmbyPlaylists(cachedEmbyPlaylists) {
            let expanded = expandedEmbyPlaylists.contains(playlist.id)
            displayItems.append(ModernDisplayItem(id: playlist.id, title: playlist.name, info: "\(playlist.songCount) tracks", indentLevel: 0, hasChildren: playlist.songCount > 0, type: .embyPlaylist(playlist)))
            if expanded, let tracks = embyPlaylistTracks[playlist.id] {
                for t in tracks { displayItems.append(ModernDisplayItem(id: "\(playlist.id)-\(t.id)", title: t.title, info: formatDuration(t.duration), indentLevel: 1, hasChildren: false, type: .embyTrack(t))) }
            }
        }
    }

    private func buildEmbyMovieItems() {
        displayItems = cachedEmbyMovies.map { movie in
            let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
            return ModernDisplayItem(id: movie.id, title: movie.title, info: info.isEmpty ? nil : info, indentLevel: 0, hasChildren: false, type: .embyMovie(movie))
        }
    }

    private func buildEmbyShowItems() {
        displayItems.removeAll()
        for show in cachedEmbyShows {
            let expanded = expandedEmbyShows.contains(show.id)
            let info = [show.year.map { String($0) }, "\(show.childCount) seasons"].compactMap { $0 }.joined(separator: " • ")
            displayItems.append(ModernDisplayItem(id: show.id, title: show.title, info: info, indentLevel: 0, hasChildren: true, type: .embyShow(show)))
            if expanded, let seasons = embyShowSeasons[show.id] {
                for season in seasons {
                    displayItems.append(ModernDisplayItem(id: season.id, title: season.title, info: "\(season.childCount) episodes", indentLevel: 1, hasChildren: true, type: .embySeason(season)))
                    if expandedEmbySeasons.contains(season.id), let episodes = embySeasonEpisodes[season.id] {
                        for ep in episodes { displayItems.append(ModernDisplayItem(id: ep.id, title: "\(ep.episodeIdentifier) - \(ep.title)", info: ep.formattedDuration, indentLevel: 2, hasChildren: false, type: .embyEpisode(ep))) }
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int?) -> String? {
        guard let s = seconds else { return nil }
        let mins = s / 60; let secs = s % 60; return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Sorting Helpers

    private func compareNameStrings(_ lhs: String, _ rhs: String, ascending: Bool) -> Bool {
        LibraryTextSorter.areInOrder(lhs, rhs, ascending: ascending, ignoreLeadingArticles: true)
    }
    
    private func sortPlexArtists(_ artists: [PlexArtist]) -> [PlexArtist] {
        switch currentSort {
        case .nameAsc: return artists.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        case .nameDesc: return artists.sorted { compareNameStrings($0.title, $1.title, ascending: false) }
        case .dateAddedDesc: return artists.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc: return artists.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        default: return artists.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        }
    }

    private func normalizedPlexArtistName(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func plexArtistGroupKey(for artist: PlexArtist) -> String {
        "plex-artist-\(normalizedPlexArtistName(artist.title))"
    }

    private func uniquePlexArtistsByName(_ artists: [PlexArtist]) -> [PlexArtist] {
        var groups = Dictionary(grouping: artists, by: { normalizedPlexArtistName($0.title) })
        if artists.count == cachedArtists.count && !plexArtistGroupsByName.isEmpty {
            groups = plexArtistGroupsByName
        }
        let representatives = groups.values.compactMap { group in
            group.max { lhs, rhs in lhs.albumCount < rhs.albumCount }
        }
        return representatives
    }

    private func plexArtistGroup(for artist: PlexArtist) -> [PlexArtist] {
        guard browseMode != .search else { return [artist] }
        let key = normalizedPlexArtistName(artist.title)
        let matches = plexArtistGroupsByName[key] ?? cachedArtists.filter { normalizedPlexArtistName($0.title) == key }
        return matches.isEmpty ? [artist] : matches
    }

    private func plexArtistAlbumCount(for artist: PlexArtist) -> Int? {
        let groupKey = plexArtistGroupKey(for: artist)
        if let count = plexAlbumCountsByArtistGroupKey[groupKey], count > 0 {
            return count
        }

        let group = plexArtistGroup(for: artist)
        let memberIds = Set(group.map { $0.id })
        let cachedGroupAlbums = cachedAlbums.filter { album in
            guard let parentKey = album.parentKey,
                  let artistId = extractArtistId(from: parentKey) else { return false }
            return memberIds.contains(artistId)
        }
        if !cachedGroupAlbums.isEmpty {
            return deduplicatedPlexAlbums(cachedGroupAlbums).count
        }

        var count = 0
        var foundCount = false
        for member in group {
            if let cached = artistAlbumCounts[member.id], cached > 0 {
                count += cached
                foundCount = true
            } else if member.albumCount > 0 {
                count += member.albumCount
                foundCount = true
            }
        }
        return foundCount ? count : nil
    }

    private func deduplicatedPlexAlbums(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        var seen = Set<String>()
        var result: [PlexAlbum] = []
        for album in albums {
            let key = "\(normalizedPlexArtistName(album.parentTitle ?? ""))|\(normalizedPlexArtistName(album.title))|\(album.year.map { String($0) } ?? "")"
            if seen.insert(key).inserted {
                result.append(album)
            }
        }
        return result
    }

    private func deduplicatedPlexTracks(_ tracks: [PlexTrack]) -> [PlexTrack] {
        var seen = Set<String>()
        var result: [PlexTrack] = []
        for track in tracks {
            let key = "\(normalizedPlexArtistName(track.grandparentTitle ?? ""))|\(normalizedPlexArtistName(track.parentTitle ?? ""))|\(normalizedPlexArtistName(track.title))|\(track.parentIndex ?? 1)|\(track.index ?? 0)"
            if seen.insert(key).inserted {
                result.append(track)
            }
        }
        return result
    }

    private func fetchAlbumsForPlexArtistGroup(_ artist: PlexArtist) async throws -> [PlexAlbum] {
        let groupKey = plexArtistGroupKey(for: artist)
        if let cached = plexAlbumsByArtistGroupKey[groupKey], !cached.isEmpty {
            return cached
        }

        var albums: [PlexAlbum] = []
        for member in plexArtistGroup(for: artist) {
            albums.append(contentsOf: try await PlexManager.shared.fetchAlbums(forArtist: member))
        }
        return deduplicatedPlexAlbums(albums)
    }

    private func fetchTracksForPlexArtistGroup(_ artist: PlexArtist) async throws -> [PlexTrack] {
        let albums = try await fetchAlbumsForPlexArtistGroup(artist)
        var tracks: [PlexTrack] = []
        for album in albums {
            tracks.append(contentsOf: try await PlexManager.shared.fetchTracks(forAlbum: album))
        }
        if tracks.isEmpty {
            for member in plexArtistGroup(for: artist) {
                tracks.append(contentsOf: try await PlexManager.shared.fetchTracks(forArtist: member))
            }
        }
        return deduplicatedPlexTracks(tracks)
    }
    
    private func sortPlexAlbums(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        switch currentSort {
        case .nameAsc: return albums.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        case .nameDesc: return albums.sorted { compareNameStrings($0.title, $1.title, ascending: false) }
        case .dateAddedDesc: return albums.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc: return albums.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        case .yearDesc: return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }
    
    private func sortPlexTracks(_ tracks: [PlexTrack]) -> [PlexTrack] {
        switch currentSort {
        case .nameAsc: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        case .nameDesc: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: false) }
        case .dateAddedDesc: return tracks.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc: return tracks.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        default: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        }
    }

    private func sortPlexPlaylists(_ playlists: [PlexPlaylist]) -> [PlexPlaylist] {
        switch currentSort {
        case .nameAsc: return playlists.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        case .nameDesc: return playlists.sorted { compareNameStrings($0.title, $1.title, ascending: false) }
        case .dateAddedDesc: return playlists.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc: return playlists.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        default: return playlists.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        }
    }

    private func subsonicArtistKey(id: String?, name: String?) -> String? {
        if let id = id, !id.isEmpty { return "id:\(id)" }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return "name:\(name.lowercased())"
    }

    private func jellyfinArtistKey(id: String?, name: String?) -> String? {
        if let id = id, !id.isEmpty { return "id:\(id)" }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return "name:\(name.lowercased())"
    }

    private func embyArtistKey(id: String?, name: String?) -> String? {
        if let id = id, !id.isEmpty { return "id:\(id)" }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return "name:\(name.lowercased())"
    }

    private func sortSubsonicArtists(_ artists: [SubsonicArtist]) -> [SubsonicArtist] {
        var newestAddedByArtist: [String: Date] = [:]
        var oldestAddedByArtist: [String: Date] = [:]
        var newestYearByArtist: [String: Int] = [:]
        var oldestYearByArtist: [String: Int] = [:]

        for album in cachedSubsonicAlbums {
            guard let key = subsonicArtistKey(id: album.artistId, name: album.artist) else { continue }
            if let created = album.created {
                let newestExisting = newestAddedByArtist[key] ?? .distantPast
                if created > newestExisting { newestAddedByArtist[key] = created }

                let oldestExisting = oldestAddedByArtist[key] ?? .distantFuture
                if created < oldestExisting { oldestAddedByArtist[key] = created }
            }
            if let year = album.year {
                let newestExisting = newestYearByArtist[key] ?? Int.min
                if year > newestExisting { newestYearByArtist[key] = year }

                let oldestExisting = oldestYearByArtist[key] ?? Int.max
                if year < oldestExisting { oldestYearByArtist[key] = year }
            }
        }

        switch currentSort {
        case .nameAsc: return artists.sorted {
            // Use the server's index letter to match Navidrome's grouping (e.g. "The Atlas Moth" → T)
            let l0 = $0.indexLetter ?? sortLetter(for: $0.name)
            let l1 = $1.indexLetter ?? sortLetter(for: $1.name)
            if l0 != l1 { return l0 < l1 }
            return compareNameStrings($0.name, $1.name, ascending: true)
        }
        case .nameDesc: return artists.sorted {
            let l0 = $0.indexLetter ?? sortLetter(for: $0.name)
            let l1 = $1.indexLetter ?? sortLetter(for: $1.name)
            if l0 != l1 { return l0 > l1 }
            return compareNameStrings($0.name, $1.name, ascending: false)
        }
        case .dateAddedDesc:
            return artists.sorted {
                let key0 = subsonicArtistKey(id: $0.id, name: $0.name)
                let key1 = subsonicArtistKey(id: $1.id, name: $1.name)
                let d0 = key0.flatMap { newestAddedByArtist[$0] } ?? .distantPast
                let d1 = key1.flatMap { newestAddedByArtist[$0] } ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .dateAddedAsc:
            return artists.sorted {
                let key0 = subsonicArtistKey(id: $0.id, name: $0.name)
                let key1 = subsonicArtistKey(id: $1.id, name: $1.name)
                let d0 = key0.flatMap { oldestAddedByArtist[$0] } ?? .distantPast
                let d1 = key1.flatMap { oldestAddedByArtist[$0] } ?? .distantPast
                if d0 != d1 { return d0 < d1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .yearDesc:
            return artists.sorted {
                let key0 = subsonicArtistKey(id: $0.id, name: $0.name)
                let key1 = subsonicArtistKey(id: $1.id, name: $1.name)
                let y0 = key0.flatMap { newestYearByArtist[$0] } ?? 0
                let y1 = key1.flatMap { newestYearByArtist[$0] } ?? 0
                if y0 != y1 { return y0 > y1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .yearAsc:
            return artists.sorted {
                let key0 = subsonicArtistKey(id: $0.id, name: $0.name)
                let key1 = subsonicArtistKey(id: $1.id, name: $1.name)
                let y0 = key0.flatMap { oldestYearByArtist[$0] } ?? 0
                let y1 = key1.flatMap { oldestYearByArtist[$0] } ?? 0
                if y0 != y1 { return y0 < y1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        }
    }

    private func sortSubsonicAlbums(_ albums: [SubsonicAlbum]) -> [SubsonicAlbum] {
        switch currentSort {
        case .nameAsc: return albums.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        case .nameDesc: return albums.sorted { compareNameStrings($0.name, $1.name, ascending: false) }
        case .dateAddedDesc: return albums.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .dateAddedAsc: return albums.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
        case .yearDesc: return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }

    private func sortSubsonicPlaylists(_ playlists: [SubsonicPlaylist]) -> [SubsonicPlaylist] {
        switch currentSort {
        case .nameAsc: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        case .nameDesc: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: false) }
        case .dateAddedDesc:
            return playlists.sorted { ($0.changed ?? $0.created ?? .distantPast) > ($1.changed ?? $1.created ?? .distantPast) }
        case .dateAddedAsc:
            return playlists.sorted { ($0.changed ?? $0.created ?? .distantPast) < ($1.changed ?? $1.created ?? .distantPast) }
        default: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        }
    }

    private func sortSubsonicTracks(_ tracks: [SubsonicSong]) -> [SubsonicSong] {
        switch currentSort {
        case .nameAsc: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        case .nameDesc: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: false) }
        case .dateAddedDesc: return tracks.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .dateAddedAsc: return tracks.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
        case .yearDesc: return tracks.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return tracks.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }

    private func sortJellyfinArtists(_ artists: [JellyfinArtist]) -> [JellyfinArtist] {
        var newestAddedByArtist: [String: Date] = [:]
        var oldestAddedByArtist: [String: Date] = [:]
        var newestYearByArtist: [String: Int] = [:]
        var oldestYearByArtist: [String: Int] = [:]

        for album in cachedJellyfinAlbums {
            guard let key = jellyfinArtistKey(id: album.artistId, name: album.artist) else { continue }
            if let created = album.created {
                let newestExisting = newestAddedByArtist[key] ?? .distantPast
                if created > newestExisting { newestAddedByArtist[key] = created }

                let oldestExisting = oldestAddedByArtist[key] ?? .distantFuture
                if created < oldestExisting { oldestAddedByArtist[key] = created }
            }
            if let year = album.year {
                let newestExisting = newestYearByArtist[key] ?? Int.min
                if year > newestExisting { newestYearByArtist[key] = year }

                let oldestExisting = oldestYearByArtist[key] ?? Int.max
                if year < oldestExisting { oldestYearByArtist[key] = year }
            }
        }

        switch currentSort {
        case .nameAsc: return artists.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        case .nameDesc: return artists.sorted { compareNameStrings($0.name, $1.name, ascending: false) }
        case .dateAddedDesc:
            return artists.sorted {
                let key0 = jellyfinArtistKey(id: $0.id, name: $0.name)
                let key1 = jellyfinArtistKey(id: $1.id, name: $1.name)
                let d0 = key0.flatMap { newestAddedByArtist[$0] } ?? .distantPast
                let d1 = key1.flatMap { newestAddedByArtist[$0] } ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .dateAddedAsc:
            return artists.sorted {
                let key0 = jellyfinArtistKey(id: $0.id, name: $0.name)
                let key1 = jellyfinArtistKey(id: $1.id, name: $1.name)
                let d0 = key0.flatMap { oldestAddedByArtist[$0] } ?? .distantPast
                let d1 = key1.flatMap { oldestAddedByArtist[$0] } ?? .distantPast
                if d0 != d1 { return d0 < d1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .yearDesc:
            return artists.sorted {
                let key0 = jellyfinArtistKey(id: $0.id, name: $0.name)
                let key1 = jellyfinArtistKey(id: $1.id, name: $1.name)
                let y0 = key0.flatMap { newestYearByArtist[$0] } ?? 0
                let y1 = key1.flatMap { newestYearByArtist[$0] } ?? 0
                if y0 != y1 { return y0 > y1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .yearAsc:
            return artists.sorted {
                let key0 = jellyfinArtistKey(id: $0.id, name: $0.name)
                let key1 = jellyfinArtistKey(id: $1.id, name: $1.name)
                let y0 = key0.flatMap { oldestYearByArtist[$0] } ?? 0
                let y1 = key1.flatMap { oldestYearByArtist[$0] } ?? 0
                if y0 != y1 { return y0 < y1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        }
    }

    private func sortJellyfinAlbums(_ albums: [JellyfinAlbum]) -> [JellyfinAlbum] {
        switch currentSort {
        case .nameAsc: return albums.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        case .nameDesc: return albums.sorted { compareNameStrings($0.name, $1.name, ascending: false) }
        case .dateAddedDesc: return albums.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .dateAddedAsc: return albums.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
        case .yearDesc: return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }

    private func sortJellyfinPlaylists(_ playlists: [JellyfinPlaylist]) -> [JellyfinPlaylist] {
        switch currentSort {
        case .nameAsc: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        case .nameDesc: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: false) }
        default: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        }
    }

    private func sortJellyfinTracks(_ tracks: [JellyfinSong]) -> [JellyfinSong] {
        switch currentSort {
        case .nameAsc: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        case .nameDesc: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: false) }
        case .dateAddedDesc: return tracks.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .dateAddedAsc: return tracks.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
        case .yearDesc: return tracks.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return tracks.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }

    private func sortEmbyArtists(_ artists: [EmbyArtist]) -> [EmbyArtist] {
        var newestAddedByArtist: [String: Date] = [:]
        var oldestAddedByArtist: [String: Date] = [:]
        var newestYearByArtist: [String: Int] = [:]
        var oldestYearByArtist: [String: Int] = [:]

        for album in cachedEmbyAlbums {
            guard let key = embyArtistKey(id: album.artistId, name: album.artist) else { continue }
            if let created = album.created {
                let newestExisting = newestAddedByArtist[key] ?? .distantPast
                if created > newestExisting { newestAddedByArtist[key] = created }

                let oldestExisting = oldestAddedByArtist[key] ?? .distantFuture
                if created < oldestExisting { oldestAddedByArtist[key] = created }
            }
            if let year = album.year {
                let newestExisting = newestYearByArtist[key] ?? Int.min
                if year > newestExisting { newestYearByArtist[key] = year }

                let oldestExisting = oldestYearByArtist[key] ?? Int.max
                if year < oldestExisting { oldestYearByArtist[key] = year }
            }
        }

        switch currentSort {
        case .nameAsc: return artists.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        case .nameDesc: return artists.sorted { compareNameStrings($0.name, $1.name, ascending: false) }
        case .dateAddedDesc:
            return artists.sorted {
                let key0 = embyArtistKey(id: $0.id, name: $0.name)
                let key1 = embyArtistKey(id: $1.id, name: $1.name)
                let d0 = key0.flatMap { newestAddedByArtist[$0] } ?? .distantPast
                let d1 = key1.flatMap { newestAddedByArtist[$0] } ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .dateAddedAsc:
            return artists.sorted {
                let key0 = embyArtistKey(id: $0.id, name: $0.name)
                let key1 = embyArtistKey(id: $1.id, name: $1.name)
                let d0 = key0.flatMap { oldestAddedByArtist[$0] } ?? .distantPast
                let d1 = key1.flatMap { oldestAddedByArtist[$0] } ?? .distantPast
                if d0 != d1 { return d0 < d1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .yearDesc:
            return artists.sorted {
                let key0 = embyArtistKey(id: $0.id, name: $0.name)
                let key1 = embyArtistKey(id: $1.id, name: $1.name)
                let y0 = key0.flatMap { newestYearByArtist[$0] } ?? 0
                let y1 = key1.flatMap { newestYearByArtist[$0] } ?? 0
                if y0 != y1 { return y0 > y1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        case .yearAsc:
            return artists.sorted {
                let key0 = embyArtistKey(id: $0.id, name: $0.name)
                let key1 = embyArtistKey(id: $1.id, name: $1.name)
                let y0 = key0.flatMap { oldestYearByArtist[$0] } ?? 0
                let y1 = key1.flatMap { oldestYearByArtist[$0] } ?? 0
                if y0 != y1 { return y0 < y1 }
                return compareNameStrings($0.name, $1.name, ascending: true)
            }
        }
    }

    private func sortEmbyAlbums(_ albums: [EmbyAlbum]) -> [EmbyAlbum] {
        switch currentSort {
        case .nameAsc: return albums.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        case .nameDesc: return albums.sorted { compareNameStrings($0.name, $1.name, ascending: false) }
        case .dateAddedDesc: return albums.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .dateAddedAsc: return albums.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
        case .yearDesc: return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }

    private func sortEmbyPlaylists(_ playlists: [EmbyPlaylist]) -> [EmbyPlaylist] {
        switch currentSort {
        case .nameAsc: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        case .nameDesc: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: false) }
        default: return playlists.sorted { compareNameStrings($0.name, $1.name, ascending: true) }
        }
    }

    private func sortEmbyTracks(_ tracks: [EmbySong]) -> [EmbySong] {
        switch currentSort {
        case .nameAsc: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: true) }
        case .nameDesc: return tracks.sorted { compareNameStrings($0.title, $1.title, ascending: false) }
        case .dateAddedDesc: return tracks.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .dateAddedAsc: return tracks.sorted { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }
        case .yearDesc: return tracks.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return tracks.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }
    
    // MARK: - Rebuild Current Mode Items
    
    private func rebuildCurrentModeItems() {
        horizontalScrollOffset = 0
        if case .youtube = currentSource {
            switch browseMode {
            case .radio:
                if radioSlotShowsChannels { buildYouTubeChannelItems() }
                else { buildRadioStationItems() }
            case .search:
                buildRadioSearchItems()
            default:
                displayItems = []
            }
            if activeColumnSortId != nil { applyColumnSort() }
            needsDisplay = true
            return
        }
        if case .radio = currentSource {
            switch browseMode {
            case .radio:
                buildRadioStationItems()
            case .search:
                buildRadioSearchItems()
            default:
                displayItems = []
            }
            if columnSortId != nil { applyColumnSort() }
            needsDisplay = true
            return
        }
        if browseMode == .radio { needsDisplay = true; return }
        if case .local = currentSource {
            switch browseMode {
            case .artists: buildLocalArtistItems()
            case .albums: buildLocalAlbumItems()
            case .folders: buildLocalFolderItems()
            case .search: buildLocalSearchItems()
            case .movies: buildLocalMovieItems()
            case .shows: buildLocalShowItems()
            case .plists:
                refreshCachedLocalPlaylists()
                buildLocalPlaylistItems()
            case .radio, .history: displayItems = []
            }
        } else if case .subsonic = currentSource {
            switch browseMode {
            case .artists: buildSubsonicArtistItems()
            case .albums: buildSubsonicAlbumItems()
            case .plists: buildSubsonicPlaylistItems()
            case .search: buildSubsonicSearchItems()
            default: displayItems = []
            }
        } else if case .jellyfin = currentSource {
            switch browseMode {
            case .artists: buildJellyfinArtistItems()
            case .albums: buildJellyfinAlbumItems()
            case .plists: buildJellyfinPlaylistItems()
            case .movies: buildJellyfinMovieItems()
            case .shows: buildJellyfinShowItems()
            case .search: buildJellyfinSearchItems()
            default: displayItems = []
            }
        } else if case .emby = currentSource {
            switch browseMode {
            case .artists: buildEmbyArtistItems()
            case .albums: buildEmbyAlbumItems()
            case .plists: buildEmbyPlaylistItems()
            case .movies: buildEmbyMovieItems()
            case .shows: buildEmbyShowItems()
            case .search: buildEmbySearchItems()
            default: displayItems = []
            }
        } else {
            switch browseMode {
            case .artists: buildArtistItems()
            case .albums: buildAlbumItems()
            case .folders: displayItems = []
            case .movies: buildMovieItems()
            case .shows: buildShowItems()
            case .plists: buildPlexPlaylistItems()
            case .search: buildSearchItems()
            case .radio: break
            case .history: break
            }
        }
        if columnSortId != nil { applyColumnSort() }
        applyPendingArtistScroll()
        needsDisplay = true
    }
    
    // MARK: - Expand/Collapse
    
    private func isExpanded(_ item: ModernDisplayItem) -> Bool {
        switch item.type {
        case .artist(let a): return browseMode == .search ? expandedArtistNames.contains(a.title.lowercased()) : expandedArtists.contains(item.id)
        case .album: return expandedAlbums.contains(item.id)
        case .show: return expandedShows.contains(item.id)
        case .season: return expandedSeasons.contains(item.id)
        case .localArtist(let a): return expandedLocalArtists.contains(a.id)
        case .localAlbum(let a): return expandedLocalAlbums.contains(a.id)
        case .localFolder(let url, _): return expandedLocalFolders.contains(url.path)
        case .localShow(let s): return expandedLocalShows.contains(s.id)
        case .localSeason(let s, let showTitle): return expandedLocalSeasons.contains("\(showTitle)|\(s.number)")
        case .subsonicArtist(let a): return expandedSubsonicArtists.contains(a.id)
        case .subsonicAlbum(let a): return expandedSubsonicAlbums.contains(a.id)
        case .subsonicPlaylist(let p): return expandedSubsonicPlaylists.contains(p.id)
        case .jellyfinArtist(let a): return expandedJellyfinArtists.contains(a.id)
        case .jellyfinAlbum(let a): return expandedJellyfinAlbums.contains(a.id)
        case .jellyfinPlaylist(let p): return expandedJellyfinPlaylists.contains(p.id)
        case .jellyfinShow(let s): return expandedJellyfinShows.contains(s.id)
        case .jellyfinSeason(let s): return expandedJellyfinSeasons.contains(s.id)
        case .embyArtist(let a): return expandedEmbyArtists.contains(a.id)
        case .embyAlbum(let a): return expandedEmbyAlbums.contains(a.id)
        case .embyPlaylist(let p): return expandedEmbyPlaylists.contains(p.id)
        case .embyShow(let s): return expandedEmbyShows.contains(s.id)
        case .embySeason(let s): return expandedEmbySeasons.contains(s.id)
        case .plexPlaylist(let p): return expandedPlexPlaylists.contains(p.id)
        case .radioFolder(let folder): return expandedRadioFolders.contains(folder.id)
        case .youtubeChannel(let ch): return expandedYouTubeChannels.contains(ch.id)
        case .localPlaylist(let p): return expandedLocalPlaylists.contains(p.url.path)
        default: return false
        }
    }
    
    private func toggleExpand(_ item: ModernDisplayItem) {
        switch item.type {
        case .artist(let artist):
            let groupKey = item.id
            if expandedArtists.contains(groupKey) { expandedArtists.remove(groupKey) }
            else {
                expandedArtists.insert(groupKey)
                if artistAlbums[groupKey] == nil {
                    Task { @MainActor in
                        do {
                            NSLog("ModernLibraryBrowser: Fetching albums for artist group '%@' (key=%@)", artist.title, groupKey)
                            let albums = try await self.fetchAlbumsForPlexArtistGroup(artist)
                            if albums.isEmpty && (self.plexArtistAlbumCount(for: artist) ?? 0) > 0 {
                                NSLog("ModernLibraryBrowser: Warning - API returned 0 albums for artist group '%@' (key=%@) - allowing retry", artist.title, groupKey)
                                expandedArtists.remove(groupKey)
                            } else {
                                NSLog("ModernLibraryBrowser: Loaded %d albums for artist group '%@' (key=%@)", albums.count, artist.title, groupKey)
                                artistAlbums[groupKey] = albums
                            }
                            rebuildCurrentModeItems()
                        } catch {
                            NSLog("ModernLibraryBrowser: Failed to load albums for artist group '%@' (key=%@): %@", artist.title, groupKey, error.localizedDescription)
                            expandedArtists.remove(groupKey)
                            rebuildCurrentModeItems()
                        }
                    }; return
                }
            }
        case .album(let album):
            if expandedAlbums.contains(album.id) { expandedAlbums.remove(album.id) }
            else {
                expandedAlbums.insert(album.id)
                if albumTracks[album.id] == nil {
                    Task { @MainActor in
                        do { let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album); albumTracks[album.id] = tracks; rebuildCurrentModeItems() }
                        catch {
                            NSLog("ModernLibraryBrowser: Failed to load tracks for album '%@' (id=%@): %@", album.title, album.id, error.localizedDescription)
                            expandedAlbums.remove(album.id)
                            rebuildCurrentModeItems()
                        }
                    }; return
                }
            }
        case .show(let show):
            if expandedShows.contains(show.id) { expandedShows.remove(show.id) }
            else {
                expandedShows.insert(show.id)
                if showSeasons[show.id] == nil {
                    Task { @MainActor in
                        do { let seasons = try await PlexManager.shared.fetchSeasons(forShow: show); showSeasons[show.id] = seasons; rebuildCurrentModeItems() }
                        catch {
                            NSLog("ModernLibraryBrowser: Failed to load seasons for show '%@' (id=%@): %@", show.title, show.id, error.localizedDescription)
                            expandedShows.remove(show.id)
                            rebuildCurrentModeItems()
                        }
                    }; return
                }
            }
        case .season(let season):
            if expandedSeasons.contains(season.id) { expandedSeasons.remove(season.id) }
            else {
                expandedSeasons.insert(season.id)
                if seasonEpisodes[season.id] == nil {
                    Task { @MainActor in
                        do { let episodes = try await PlexManager.shared.fetchEpisodes(forSeason: season); seasonEpisodes[season.id] = episodes; rebuildCurrentModeItems() }
                        catch {
                            NSLog("ModernLibraryBrowser: Failed to load episodes for season '%@' (id=%@): %@", season.title, season.id, error.localizedDescription)
                            expandedSeasons.remove(season.id)
                            rebuildCurrentModeItems()
                        }
                    }; return
                }
            }
        case .localArtist(let a):
            if expandedLocalArtists.contains(a.id) { expandedLocalArtists.remove(a.id) } else { expandedLocalArtists.insert(a.id) }
        case .localAlbum(let a):
            if expandedLocalAlbums.contains(a.id) { expandedLocalAlbums.remove(a.id) } else { expandedLocalAlbums.insert(a.id) }
        case .localFolder(let url, _):
            let path = url.path
            if expandedLocalFolders.contains(path) { expandedLocalFolders.remove(path) } else { expandedLocalFolders.insert(path) }
        case .localShow(let s):
            if expandedLocalShows.contains(s.id) { expandedLocalShows.remove(s.id) } else { expandedLocalShows.insert(s.id) }
        case .localSeason(let s, let showTitle):
            let key = "\(showTitle)|\(s.number)"
            if expandedLocalSeasons.contains(key) { expandedLocalSeasons.remove(key) } else { expandedLocalSeasons.insert(key) }
        case .subsonicArtist(let artist):
            if expandedSubsonicArtists.contains(artist.id) { expandedSubsonicArtists.remove(artist.id) }
            else {
                expandedSubsonicArtists.insert(artist.id)
                if subsonicArtistAlbums[artist.id] == nil {
                    // Try cached albums first (instant) before falling back to network
                    let cached = cachedSubsonicAlbums.filter { $0.artistId == artist.id }
                    if !cached.isEmpty {
                        subsonicArtistAlbums[artist.id] = cached
                    } else {
                        let id = artist.id; subsonicExpandTask?.cancel()
                        subsonicExpandTask = Task.detached { @MainActor [weak self] in
                            guard let self = self else { return }
                            do { let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: artist); subsonicArtistAlbums[id] = albums; rebuildCurrentModeItems() }
                            catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                        }; return
                    }
                }
            }
        case .subsonicAlbum(let album):
            if expandedSubsonicAlbums.contains(album.id) { expandedSubsonicAlbums.remove(album.id) }
            else {
                expandedSubsonicAlbums.insert(album.id)
                if subsonicAlbumSongs[album.id] == nil {
                    let id = album.id; subsonicExpandTask?.cancel()
                    subsonicExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album); subsonicAlbumSongs[id] = songs; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .subsonicPlaylist(let playlist):
            if expandedSubsonicPlaylists.contains(playlist.id) { expandedSubsonicPlaylists.remove(playlist.id) }
            else {
                expandedSubsonicPlaylists.insert(playlist.id)
                if subsonicPlaylistTracks[playlist.id] == nil {
                    let id = playlist.id; subsonicExpandTask?.cancel()
                    subsonicExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let (_, tracks) = try await SubsonicManager.shared.serverClient?.fetchPlaylist(id: id) ?? (playlist, []); subsonicPlaylistTracks[id] = tracks; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .jellyfinArtist(let artist):
            if expandedJellyfinArtists.contains(artist.id) { expandedJellyfinArtists.remove(artist.id) }
            else {
                expandedJellyfinArtists.insert(artist.id)
                if jellyfinArtistAlbums[artist.id] == nil {
                    // Try cached albums first (instant) before falling back to network
                    let cached = cachedJellyfinAlbums.filter { $0.artistId == artist.id }
                    if !cached.isEmpty {
                        jellyfinArtistAlbums[artist.id] = cached
                    } else {
                        let id = artist.id; jellyfinExpandTask?.cancel()
                        jellyfinExpandTask = Task.detached { @MainActor [weak self] in
                            guard let self = self else { return }
                            do { let albums = try await JellyfinManager.shared.fetchAlbums(forArtist: artist); jellyfinArtistAlbums[id] = albums; rebuildCurrentModeItems() }
                            catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                        }; return
                    }
                }
            }
        case .jellyfinAlbum(let album):
            if expandedJellyfinAlbums.contains(album.id) { expandedJellyfinAlbums.remove(album.id) }
            else {
                expandedJellyfinAlbums.insert(album.id)
                if jellyfinAlbumSongs[album.id] == nil {
                    let id = album.id; jellyfinExpandTask?.cancel()
                    jellyfinExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album); jellyfinAlbumSongs[id] = songs; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .jellyfinPlaylist(let playlist):
            if expandedJellyfinPlaylists.contains(playlist.id) { expandedJellyfinPlaylists.remove(playlist.id) }
            else {
                expandedJellyfinPlaylists.insert(playlist.id)
                if jellyfinPlaylistTracks[playlist.id] == nil {
                    let id = playlist.id; jellyfinExpandTask?.cancel()
                    jellyfinExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let (_, tracks) = try await JellyfinManager.shared.serverClient?.fetchPlaylist(id: id) ?? (playlist, []); jellyfinPlaylistTracks[id] = tracks; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .jellyfinShow(let show):
            if expandedJellyfinShows.contains(show.id) { expandedJellyfinShows.remove(show.id) }
            else {
                expandedJellyfinShows.insert(show.id)
                if jellyfinShowSeasons[show.id] == nil {
                    let id = show.id; jellyfinExpandTask?.cancel()
                    jellyfinExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let seasons = try await JellyfinManager.shared.fetchSeasons(forShow: show); jellyfinShowSeasons[id] = seasons; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { expandedJellyfinShows.remove(id); rebuildCurrentModeItems(); NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .jellyfinSeason(let season):
            if expandedJellyfinSeasons.contains(season.id) { expandedJellyfinSeasons.remove(season.id) }
            else {
                expandedJellyfinSeasons.insert(season.id)
                if jellyfinSeasonEpisodes[season.id] == nil {
                    let id = season.id; jellyfinExpandTask?.cancel()
                    jellyfinExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let episodes = try await JellyfinManager.shared.fetchEpisodes(forSeason: season); jellyfinSeasonEpisodes[id] = episodes; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { expandedJellyfinSeasons.remove(id); rebuildCurrentModeItems(); NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .embyArtist(let artist):
            if expandedEmbyArtists.contains(artist.id) { expandedEmbyArtists.remove(artist.id) }
            else {
                expandedEmbyArtists.insert(artist.id)
                if embyArtistAlbums[artist.id] == nil {
                    let cached = cachedEmbyAlbums.filter { $0.artistId == artist.id }
                    if !cached.isEmpty {
                        embyArtistAlbums[artist.id] = cached
                    } else {
                        let id = artist.id; embyExpandTask?.cancel()
                        embyExpandTask = Task.detached { @MainActor [weak self] in
                            guard let self = self else { return }
                            do { let albums = try await EmbyManager.shared.fetchAlbums(forArtist: artist); embyArtistAlbums[id] = albums; rebuildCurrentModeItems() }
                            catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                        }; return
                    }
                }
            }
        case .embyAlbum(let album):
            if expandedEmbyAlbums.contains(album.id) { expandedEmbyAlbums.remove(album.id) }
            else {
                expandedEmbyAlbums.insert(album.id)
                if embyAlbumSongs[album.id] == nil {
                    let id = album.id; embyExpandTask?.cancel()
                    embyExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album); embyAlbumSongs[id] = songs; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .embyPlaylist(let playlist):
            if expandedEmbyPlaylists.contains(playlist.id) { expandedEmbyPlaylists.remove(playlist.id) }
            else {
                expandedEmbyPlaylists.insert(playlist.id)
                if embyPlaylistTracks[playlist.id] == nil {
                    let id = playlist.id; embyExpandTask?.cancel()
                    embyExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let (_, tracks) = try await EmbyManager.shared.serverClient?.fetchPlaylist(id: id) ?? (playlist, []); embyPlaylistTracks[id] = tracks; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .embyShow(let show):
            if expandedEmbyShows.contains(show.id) { expandedEmbyShows.remove(show.id) }
            else {
                expandedEmbyShows.insert(show.id)
                if embyShowSeasons[show.id] == nil {
                    let id = show.id; embyExpandTask?.cancel()
                    embyExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let seasons = try await EmbyManager.shared.fetchSeasons(forShow: show); embyShowSeasons[id] = seasons; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { expandedEmbyShows.remove(id); rebuildCurrentModeItems(); NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .embySeason(let season):
            if expandedEmbySeasons.contains(season.id) { expandedEmbySeasons.remove(season.id) }
            else {
                expandedEmbySeasons.insert(season.id)
                if embySeasonEpisodes[season.id] == nil {
                    let id = season.id; embyExpandTask?.cancel()
                    embyExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let episodes = try await EmbyManager.shared.fetchEpisodes(forSeason: season); embySeasonEpisodes[id] = episodes; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch where Task.isCancelled { } catch { expandedEmbySeasons.remove(id); rebuildCurrentModeItems(); NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .plexPlaylist(let playlist):
            if expandedPlexPlaylists.contains(playlist.id) { expandedPlexPlaylists.remove(playlist.id) }
            else {
                expandedPlexPlaylists.insert(playlist.id)
                if plexPlaylistTracks[playlist.id] == nil {
                    let id = playlist.id; let smartContent = playlist.smart ? playlist.content : nil
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let tracks = try await PlexManager.shared.fetchPlaylistTracks(playlistID: id, smartContent: smartContent); plexPlaylistTracks[id] = tracks; rebuildCurrentModeItems() }
                        catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .radioFolder(let folder):
            if folder.hasChildren {
                if expandedRadioFolders.contains(folder.id) {
                    expandedRadioFolders.remove(folder.id)
                } else {
                    expandedRadioFolders.insert(folder.id)
                }
            }
        case .localPlaylist(let p):
            let key = p.url.path
            if expandedLocalPlaylists.contains(key) {
                expandedLocalPlaylists.remove(key)
                rebuildCurrentModeItems()
            } else {
                expandedLocalPlaylists.insert(key)
                if localPlaylistTracks[key] == nil {
                    let url = p.url
                    Task.detached { [weak self] in
                        let tracks = parseModernLocalPlaylistTracks(at: url)
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            self.localPlaylistTracks[key] = tracks
                            self.rebuildCurrentModeItems()
                        }
                    }
                    return
                }
                rebuildCurrentModeItems()
            }
        case .youtubeChannel(let ch):
            if expandedYouTubeChannels.contains(ch.id) {
                expandedYouTubeChannels.remove(ch.id)
            } else {
                expandedYouTubeChannels.insert(ch.id)
                if youtubeChannelVideos[ch.id] == nil {
                    let id = ch.id; youtubeExpandTask?.cancel()
                    loadingChannelIds.insert(id); startLoadingAnimation()
                    youtubeExpandTask = Task.detached { @MainActor [weak self] in
                        guard let self = self else { return }
                        defer { self.loadingChannelIds.remove(id); self.stopLoadingAnimation(); self.needsDisplay = true }
                        do {
                            let videos = try await YouTubeManager.shared.videos(forChannel: ch)
                            youtubeChannelVideos[id] = videos
                            rebuildCurrentModeItems()
                        } catch is CancellationError { }
                        catch where Task.isCancelled { }
                        catch {
                            NSLog("Failed to load YouTube videos for channel '%@': %@", ch.title, error.localizedDescription)
                        }
                    }; rebuildCurrentModeItems(); needsDisplay = true; return
                }
            }
        default: break
        }
        rebuildCurrentModeItems(); needsDisplay = true
    }
    
    // MARK: - Playback
    
    private func playTrack(_ item: ModernDisplayItem) {
        guard case .track(let track) = item.type else { return }
        if let t = PlexManager.shared.convertToTrack(track) { WindowManager.shared.audioEngine.playNow([t]) }
    }
    private func playAlbum(_ album: PlexAlbum) {
        Task { @MainActor in
            do { let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album); WindowManager.shared.audioEngine.playNow(PlexManager.shared.convertToTracks(tracks)) }
            catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playArtist(_ artist: PlexArtist) {
        Task { @MainActor in
            do {
                let all = try await fetchTracksForPlexArtistGroup(artist)
                WindowManager.shared.audioEngine.playNow(PlexManager.shared.convertToTracks(all))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playMovie(_ movie: PlexMovie) { WindowManager.shared.playMovie(movie) }
    private func playEpisode(_ episode: PlexEpisode) { WindowManager.shared.playEpisode(episode) }
    private func playJellyfinMovie(_ movie: JellyfinMovie) { WindowManager.shared.playJellyfinMovie(movie) }
    private func playJellyfinEpisode(_ episode: JellyfinEpisode) { WindowManager.shared.playJellyfinEpisode(episode) }
    private func playEmbySong(_ song: EmbySong) {
        if let t = EmbyManager.shared.convertToTrack(song) { WindowManager.shared.audioEngine.playNow([t]) }
    }
    private func playEmbyAlbum(_ album: EmbyAlbum) {
        Task { @MainActor in
            do { let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album); WindowManager.shared.audioEngine.playNow(EmbyManager.shared.convertToTracks(songs)) }
            catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playEmbyArtist(_ artist: EmbyArtist) {
        Task { @MainActor in
            do {
                let albums = try await EmbyManager.shared.fetchAlbums(forArtist: artist)
                var all: [Track] = []
                for album in albums { let songs = try await EmbyManager.shared.fetchSongs(forAlbum: album); all.append(contentsOf: EmbyManager.shared.convertToTracks(songs)) }
                WindowManager.shared.audioEngine.playNow(all)
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playEmbyPlaylist(_ playlist: EmbyPlaylist) {
        Task { @MainActor in
            do {
                let (_, songs) = try await EmbyManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
                WindowManager.shared.audioEngine.playNow(EmbyManager.shared.convertToTracks(songs))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playEmbyMovie(_ movie: EmbyMovie) { WindowManager.shared.playEmbyMovie(movie) }
    private func playEmbyEpisode(_ episode: EmbyEpisode) { WindowManager.shared.playEmbyEpisode(episode) }
    private func playLocalTrack(_ track: LibraryTrack) {
        // Expand .cue files or audio files with a sibling .cue. tracksForCueOrSibling owns
        // the eligibility check, so don't gate on a hard-coded extension list.
        if let cueExpanded = AudioEngine.tracksForCueOrSibling(url: track.url), !cueExpanded.isEmpty {
            WindowManager.shared.audioEngine.playNow(cueExpanded)
            return
        }
        WindowManager.shared.audioEngine.playNow([track.toTrack()])
    }

    /// Returns tracks for a local album, fetching from the store if the album was built as a stub (empty tracks).
    private func resolvedTracksForLocalAlbum(_ album: Album) -> [LibraryTrack] {
        if !album.tracks.isEmpty { return album.tracks }
        return MediaLibraryStore.shared.tracksForAlbum(album.id)
    }

    /// Recursively collect audio files from a directory and enrich with library metadata.
    /// Runs entirely off the main actor, then invokes `completion` on the main actor.
    private func collectTracksFromFolder(_ folderURL: URL, completion: @escaping ([Track]) -> Void) {
        Task.detached {
            var audioFileURLs: [URL] = []
            var visitedPaths: Set<String> = []

            func walkDirectory(_ url: URL, depth: Int = 0) {
                guard depth < 100 else { return } // Prevent infinite recursion
                let resolvedPath = url.resolvingSymlinksInPath().path
                guard !visitedPaths.contains(resolvedPath) else { return }
                visitedPaths.insert(resolvedPath)

                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                    var subdirectories: [URL] = []
                    var audioFiles: [URL] = []
                    for item in contents {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                if item.resolvingSymlinksInPath().path == item.path {
                                    subdirectories.append(item)
                                }
                            } else if LocalFileDiscovery.isSupportedAudioFile(item) {
                                audioFiles.append(item)
                            }
                        }
                    }
                    subdirectories.sort { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
                    audioFiles.sort { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
                    for subdirectory in subdirectories {
                        walkDirectory(subdirectory, depth: depth + 1)
                    }
                    audioFileURLs.append(contentsOf: audioFiles)
                }
            }

            walkDirectory(folderURL)

            // Batch query library metadata for all audio files
            let urlToTrackMap = MediaLibraryStore.shared.tracks(forURLs: audioFileURLs)

            var tracks: [Track] = []
            for url in audioFileURLs {
                if let libraryTrack = urlToTrackMap[url] {
                    tracks.append(libraryTrack.toTrack())
                } else {
                    // Create minimal synthesized track for files not in library
                    tracks.append(LibraryTrack(url: url).toTrack())
                }
            }

            let collectedTracks = tracks
            await MainActor.run { completion(collectedTracks) }
        }
    }

    private func playLocalAlbum(_ album: Album) { WindowManager.shared.audioEngine.playNow(resolvedTracksForLocalAlbum(album).map { $0.toTrack() }) }
    private func playLocalArtist(_ artist: Artist) {
        // If albums are empty (stub from paginated view), load tracks from store
        var tracks: [Track] = []
        if artist.albums.isEmpty {
            let store = MediaLibraryStore.shared
            let albumSummaries = store.albumsForArtist(artist.name)
            for summary in albumSummaries.sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                tracks.append(contentsOf: store.tracksForAlbum(summary.id).map { $0.toTrack() })
            }
        } else {
            for album in artist.albums { tracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
        }
        WindowManager.shared.audioEngine.playNow(tracks)
    }
    private func playSubsonicSong(_ song: SubsonicSong) {
        if let t = SubsonicManager.shared.convertToTrack(song) { WindowManager.shared.audioEngine.playNow([t]) }
    }
    private func playSubsonicAlbum(_ album: SubsonicAlbum) {
        Task { @MainActor in
            do { let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album); WindowManager.shared.audioEngine.playNow(songs.compactMap { SubsonicManager.shared.convertToTrack($0) }) }
            catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playSubsonicArtist(_ artist: SubsonicArtist) {
        Task { @MainActor in
            do {
                let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: artist)
                var all: [Track] = []
                for album in albums { let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album); all.append(contentsOf: songs.compactMap { SubsonicManager.shared.convertToTrack($0) }) }
                WindowManager.shared.audioEngine.playNow(all)
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playSubsonicPlaylist(_ playlist: SubsonicPlaylist) {
        Task { @MainActor in
            do {
                let (_, songs) = try await SubsonicManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
                WindowManager.shared.audioEngine.playNow(songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playJellyfinSong(_ song: JellyfinSong) {
        if let t = JellyfinManager.shared.convertToTrack(song) { WindowManager.shared.audioEngine.playNow([t]) }
    }
    private func playJellyfinAlbum(_ album: JellyfinAlbum) {
        Task { @MainActor in
            do { let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album); WindowManager.shared.audioEngine.playNow(JellyfinManager.shared.convertToTracks(songs)) }
            catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playJellyfinArtist(_ artist: JellyfinArtist) {
        Task { @MainActor in
            do {
                let albums = try await JellyfinManager.shared.fetchAlbums(forArtist: artist)
                var all: [Track] = []
                for album in albums { let songs = try await JellyfinManager.shared.fetchSongs(forAlbum: album); all.append(contentsOf: JellyfinManager.shared.convertToTracks(songs)) }
                WindowManager.shared.audioEngine.playNow(all)
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playJellyfinPlaylist(_ playlist: JellyfinPlaylist) {
        Task { @MainActor in
            do {
                let (_, songs) = try await JellyfinManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
                WindowManager.shared.audioEngine.playNow(JellyfinManager.shared.convertToTracks(songs))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playPlexPlaylist(_ playlist: PlexPlaylist) {
        Task { @MainActor in
            do {
                let tracks = try await PlexManager.shared.fetchPlaylistTracks(playlistID: playlist.id, smartContent: playlist.smart ? playlist.content : nil)
                WindowManager.shared.audioEngine.playNow(PlexManager.shared.convertToTracks(tracks))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playRadioStation(_ station: RadioStation) { RadioManager.shared.play(station: station) }
    private func playPlexRadioStation(_ radioType: PlexRadioType) {
        radioPlayTask?.cancel()
        isLoading = true; startLoadingAnimation(); needsDisplay = true
        radioPlayTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var tracks: [Track] = []
            switch radioType {
            case .libraryRadio: tracks = await PlexManager.shared.createLibraryRadio()
            case .libraryRadioSonic: tracks = await PlexManager.shared.createLibraryRadioSonic()
            case .hitsRadio: tracks = await PlexManager.shared.createHitsRadio()
            case .hitsRadioSonic: tracks = await PlexManager.shared.createHitsRadioSonic()
            case .deepCutsRadio: tracks = await PlexManager.shared.createDeepCutsRadio()
            case .deepCutsRadioSonic: tracks = await PlexManager.shared.createDeepCutsRadioSonic()
            case .genreRadio(let g): tracks = await PlexManager.shared.createGenreRadio(genre: g)
            case .genreRadioSonic(let g): tracks = await PlexManager.shared.createGenreRadioSonic(genre: g)
            case .decadeRadio(let s, let e, _): tracks = await PlexManager.shared.createDecadeRadio(startYear: s, endYear: e)
            case .decadeRadioSonic(let s, let e, _): tracks = await PlexManager.shared.createDecadeRadioSonic(startYear: s, endYear: e)
            case .ratingRadio(let r, _): tracks = await PlexManager.shared.createRatingRadio(minRating: r)
            case .ratingRadioSonic(let r, _): tracks = await PlexManager.shared.createRatingRadioSonic(minRating: r)
            }
            guard !Task.isCancelled else { return }
            guard !tracks.isEmpty else {
                self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
                return
            }
            WindowManager.shared.audioEngine.loadTracks(tracks)
            self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
            self.radioPlayTask = nil
        }
    }
    
    private func playSubsonicRadioStation(_ radioType: SubsonicRadioType) {
        radioPlayTask?.cancel()
        isLoading = true; startLoadingAnimation(); needsDisplay = true
        radioPlayTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var tracks: [Track] = []
            switch radioType {
            case .libraryRadio: tracks = await SubsonicManager.shared.createLibraryRadio()
            case .librarySimilar: tracks = await SubsonicManager.shared.createLibraryRadioSimilar()
            case .genreRadio(let g): tracks = await SubsonicManager.shared.createGenreRadio(genre: g)
            case .genreSimilar(let g): tracks = await SubsonicManager.shared.createGenreRadioSimilar(genre: g)
            case .decadeRadio(let s, let e, _): tracks = await SubsonicManager.shared.createDecadeRadio(start: s, end: e)
            case .decadeSimilar(let s, let e, _): tracks = await SubsonicManager.shared.createDecadeRadioSimilar(start: s, end: e)
            case .starredRadio: tracks = await SubsonicManager.shared.createRatingRadio()
            case .starredSimilar: tracks = await SubsonicManager.shared.createRatingRadioSimilar()
            }
            guard !Task.isCancelled else { return }
            guard !tracks.isEmpty else {
                self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
                return
            }
            WindowManager.shared.audioEngine.loadTracks(tracks)
            self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
            self.radioPlayTask = nil
        }
    }

    private func playJellyfinRadioStation(_ radioType: JellyfinRadioType) {
        radioPlayTask?.cancel()
        isLoading = true; startLoadingAnimation(); needsDisplay = true
        radioPlayTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var tracks: [Track] = []
            switch radioType {
            case .libraryRadio: tracks = await JellyfinManager.shared.createLibraryRadio()
            case .libraryInstantMix: tracks = await JellyfinManager.shared.createLibraryRadioInstantMix()
            case .genreRadio(let g): tracks = await JellyfinManager.shared.createGenreRadio(genre: g)
            case .genreInstantMix(let g): tracks = await JellyfinManager.shared.createGenreRadioInstantMix(genre: g)
            case .decadeRadio(let s, let e, _): tracks = await JellyfinManager.shared.createDecadeRadio(start: s, end: e)
            case .decadeInstantMix(let s, let e, _): tracks = await JellyfinManager.shared.createDecadeRadioInstantMix(start: s, end: e)
            case .favoritesRadio: tracks = await JellyfinManager.shared.createFavoritesRadio()
            case .favoritesInstantMix: tracks = await JellyfinManager.shared.createFavoritesRadioInstantMix()
            }
            guard !Task.isCancelled else { return }
            guard !tracks.isEmpty else {
                self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
                return
            }
            WindowManager.shared.audioEngine.loadTracks(tracks)
            self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
            self.radioPlayTask = nil
        }
    }

    private func playEmbyRadioStation(_ radioType: EmbyRadioType) {
        radioPlayTask?.cancel()
        isLoading = true; startLoadingAnimation(); needsDisplay = true
        radioPlayTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var tracks: [Track] = []
            switch radioType {
            case .libraryRadio: tracks = await EmbyManager.shared.createLibraryRadio()
            case .libraryInstantMix: tracks = await EmbyManager.shared.createLibraryRadioInstantMix()
            case .genreRadio(let g): tracks = await EmbyManager.shared.createGenreRadio(genre: g)
            case .genreInstantMix(let g): tracks = await EmbyManager.shared.createGenreRadioInstantMix(genre: g)
            case .decadeRadio(let s, let e, _): tracks = await EmbyManager.shared.createDecadeRadio(start: s, end: e)
            case .decadeInstantMix(let s, let e, _): tracks = await EmbyManager.shared.createDecadeRadioInstantMix(start: s, end: e)
            case .favoritesRadio: tracks = await EmbyManager.shared.createFavoritesRadio()
            case .favoritesInstantMix: tracks = await EmbyManager.shared.createFavoritesRadioInstantMix()
            }
            guard !Task.isCancelled else { return }
            guard !tracks.isEmpty else {
                self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
                return
            }
            WindowManager.shared.audioEngine.loadTracks(tracks)
            self.isLoading = false; self.stopLoadingAnimation(); self.needsDisplay = true
            self.radioPlayTask = nil
        }
    }

    private func playLocalRadioStation(_ radioType: LocalRadioType) {
        let tracks: [Track]
        switch radioType {
        case .libraryRadio: tracks = MediaLibrary.shared.createLocalLibraryRadio()
        case .genreRadio(let g): tracks = MediaLibrary.shared.createLocalGenreRadio(genre: g)
        case .decadeRadio(let s, let e, _): tracks = MediaLibrary.shared.createLocalDecadeRadio(start: s, end: e)
        }
        if !tracks.isEmpty {
            WindowManager.shared.audioEngine.loadTracks(tracks)
        }
    }

    private func navigateToArtistFromSearch(id: String, name: String = "") {
        let artistName = name.isEmpty ? id.replacingOccurrences(of: "local-artist-", with: "") : name
        pendingScrollToArtistId = id
        pendingScrollToArtistName = artistName
        pendingScrollAttempts = 0
        pendingArtistLoadUnfiltered = true
        // Clear view-level artist caches to force a fresh fetch that bypasses
        // folder/library filters (so an artist found via unfiltered search is findable).
        cachedArtists.removeAll()
        cachedSubsonicArtists.removeAll()
        cachedJellyfinArtists.removeAll()
        cachedEmbyArtists.removeAll()
        if case .local = currentSource,
           let artistOffset = MediaLibraryStore.shared.artistOffset(named: artistName, sort: currentSort) {
            localArtistPageOffset = (artistOffset / localPageSize) * localPageSize
        }
        browseMode = .artists
        selectedIndices.removeAll()
        scrollOffset = 0
        loadDataForCurrentMode()
        needsDisplay = true
    }

    private func handleDoubleClick(on item: ModernDisplayItem) {
        switch item.type {
        case .track: playTrack(item)
        case .album(let a): playAlbum(a)
        case .artist(let a): if browseMode == .search { navigateToArtistFromSearch(id: a.id, name: a.title) } else { toggleExpand(item) }
        case .movie(let m): playMovie(m)
        case .show: toggleExpand(item)
        case .season: toggleExpand(item)
        case .episode(let e): playEpisode(e)
        case .header: break
        case .localTrack(let t): playLocalTrack(t)
        case .localAlbum(let a): playLocalAlbum(a)
        case .localArtist(let a): if browseMode == .search { navigateToArtistFromSearch(id: item.id, name: a.name) } else { toggleExpand(item) }
        case .localFolder: toggleExpand(item)
        case .localMovie(let m): WindowManager.shared.showVideoPlayer(url: m.url, title: m.title)
        case .localShow: toggleExpand(item)
        case .localSeason: toggleExpand(item)
        case .localEpisode(let e): WindowManager.shared.showVideoPlayer(url: e.url, title: e.title)
        case .subsonicTrack(let s): playSubsonicSong(s)
        case .subsonicAlbum(let a): playSubsonicAlbum(a)
        case .subsonicArtist(let a): if browseMode == .search { navigateToArtistFromSearch(id: a.id, name: a.name) } else { toggleExpand(item) }
        case .subsonicPlaylist(let p): playSubsonicPlaylist(p)
        case .jellyfinTrack(let s): playJellyfinSong(s)
        case .jellyfinAlbum(let a): playJellyfinAlbum(a)
        case .jellyfinArtist(let a): if browseMode == .search { navigateToArtistFromSearch(id: a.id, name: a.name) } else { toggleExpand(item) }
        case .jellyfinPlaylist(let p): playJellyfinPlaylist(p)
        case .jellyfinMovie(let m): playJellyfinMovie(m)
        case .jellyfinShow: toggleExpand(item)
        case .jellyfinSeason: toggleExpand(item)
        case .jellyfinEpisode(let e): playJellyfinEpisode(e)
        case .embyTrack(let s): playEmbySong(s)
        case .embyAlbum(let a): playEmbyAlbum(a)
        case .embyArtist(let a): if browseMode == .search { navigateToArtistFromSearch(id: a.id, name: a.name) } else { toggleExpand(item) }
        case .embyPlaylist(let p): playEmbyPlaylist(p)
        case .embyMovie(let m): playEmbyMovie(m)
        case .embyShow: toggleExpand(item)
        case .embySeason: toggleExpand(item)
        case .embyEpisode(let e): playEmbyEpisode(e)
        case .plexPlaylist(let p): playPlexPlaylist(p)
        case .radioStation(let s): playRadioStation(s)
        case .radioFolder(let folder):
            if folder.hasChildren {
                toggleExpand(item)
            }
        case .youtubeChannel(let channel): toggleExpand(item)
        case .youtubeVideo(let video):
            if YouTubeManager.shared.isDownloaded(video.videoId) {
                if let url = YouTubeManager.shared.downloadedFileURL(for: video.videoId) {
                    let track = Track(url: url, isYouTubeOrigin: true)
                    WindowManager.shared.audioEngine.playNow([track])
                }
            } else {
                downloadingVideoIds.insert(video.videoId)
                startLoadingAnimation()
                needsDisplay = true
                youtubeDownloadTask?.cancel()
                youtubeDownloadTask = Task.detached { @MainActor [weak self] in
                    guard let self = self else { return }
                    defer { self.downloadingVideoIds.remove(video.videoId); self.stopLoadingAnimation(); self.needsDisplay = true }
                    do {
                        let downloadedURL = try await YouTubeManager.shared.download(video: video)
                        // A newer download may have superseded this one; don't auto-play a stale result.
                        try Task.checkCancellation()
                        let track = Track(url: downloadedURL, isYouTubeOrigin: true)
                        WindowManager.shared.audioEngine.playNow([track])
                        rebuildCurrentModeItems()
                    } catch is CancellationError {
                        // Superseded by a newer download request; skip side effects.
                    } catch {
                        NSLog("Failed to download YouTube video: %@", error.localizedDescription)
                    }
                }
            }
        case .plexRadioStation(let r): playPlexRadioStation(r)
        case .subsonicRadioStation(let r): playSubsonicRadioStation(r)
        case .jellyfinRadioStation(let r): playJellyfinRadioStation(r)
        case .embyRadioStation(let r): playEmbyRadioStation(r)
        case .localRadioStation(let r): playLocalRadioStation(r)
        case .localPlaylist(let p): playLocalPlaylist(p.url)
        case .localPlaylistTrack(let t): WindowManager.shared.audioEngine.playNow([t])
        }
    }
}

private func parseModernLocalPlaylistTracks(at url: URL) -> [Track] {
    var result: [Track] = []
    let ext = url.pathExtension.lowercased()

    let playlist: Playlist?
    if ext == "m3u" || ext == "m3u8" {
        playlist = try? Playlist.fromM3U(url: url)
    } else if ext == "pls" {
        playlist = try? Playlist.fromPLS(url: url)
    } else {
        return []
    }

    guard let playlist = playlist else { return [] }

    for trackURL in playlist.trackURLs {
        if let libTrack = MediaLibrary.shared.findTrack(byURL: trackURL) {
            result.append(libTrack.toTrack())
        } else {
            result.append(Track(lightweightURL: trackURL))
        }
    }

    return result
}

// MARK: - Tags Panel Cleanup

extension ModernLibraryBrowserView {
    func tagsPanelDidClose(_ panel: TagsPanel) {
        if panel === activeTagsPanel { activeTagsPanel = nil }
    }
}

// MARK: - Display Item

private struct ModernDisplayItem {
    let id: String
    let title: String
    let info: String?
    let indentLevel: Int
    let hasChildren: Bool
    let type: ItemType
    
    enum ItemType {
        case artist(PlexArtist)
        case album(PlexAlbum)
        case track(PlexTrack)
        case movie(PlexMovie)
        case show(PlexShow)
        case season(PlexSeason)
        case episode(PlexEpisode)
        case header
        case localArtist(Artist)
        case localAlbum(Album)
        case localTrack(LibraryTrack)
        case localFolder(url: URL, name: String)
        case localMovie(LocalVideo)
        case localShow(LocalShow)
        case localSeason(LocalSeason, showTitle: String)
        case localEpisode(LocalEpisode)
        case subsonicArtist(SubsonicArtist)
        case subsonicAlbum(SubsonicAlbum)
        case subsonicTrack(SubsonicSong)
        case subsonicPlaylist(SubsonicPlaylist)
        case jellyfinArtist(JellyfinArtist)
        case jellyfinAlbum(JellyfinAlbum)
        case jellyfinTrack(JellyfinSong)
        case jellyfinPlaylist(JellyfinPlaylist)
        case jellyfinMovie(JellyfinMovie)
        case jellyfinShow(JellyfinShow)
        case jellyfinSeason(JellyfinSeason)
        case jellyfinEpisode(JellyfinEpisode)
        case embyArtist(EmbyArtist)
        case embyAlbum(EmbyAlbum)
        case embyTrack(EmbySong)
        case embyPlaylist(EmbyPlaylist)
        case embyMovie(EmbyMovie)
        case embyShow(EmbyShow)
        case embySeason(EmbySeason)
        case embyEpisode(EmbyEpisode)
        case plexPlaylist(PlexPlaylist)
        case radioStation(RadioStation)
        case radioFolder(RadioFolderDescriptor)
        case youtubeChannel(YouTubeChannel)
        case youtubeVideo(YouTubeVideo)
        case plexRadioStation(PlexRadioType)
        case subsonicRadioStation(SubsonicRadioType)
        case jellyfinRadioStation(JellyfinRadioType)
        case embyRadioStation(EmbyRadioType)
        case localRadioStation(LocalRadioType)
        case localPlaylist(LocalPlaylist)
        case localPlaylistTrack(Track)

        var isAlbumItem: Bool {
            switch self {
            case .album, .localAlbum, .subsonicAlbum, .jellyfinAlbum, .embyAlbum: return true
            default: return false
            }
        }
    }
}

// MARK: - Radio Type Enums

enum SubsonicRadioType: Equatable, Hashable {
    case libraryRadio
    case librarySimilar
    case genreRadio(String)
    case genreSimilar(String)
    case decadeRadio(start: Int, end: Int, name: String)
    case decadeSimilar(start: Int, end: Int, name: String)
    case starredRadio
    case starredSimilar

    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .librarySimilar: return "Library Radio (Similar)"
        case .genreRadio(let g): return "\(g) Radio"
        case .genreSimilar(let g): return "\(g) Radio (Similar)"
        case .decadeRadio(_, _, let n): return "\(n) Radio"
        case .decadeSimilar(_, _, let n): return "\(n) Radio (Similar)"
        case .starredRadio: return "Starred Radio"
        case .starredSimilar: return "Starred Radio (Similar)"
        }
    }
    var category: String {
        switch self {
        case .libraryRadio, .librarySimilar: return "Library"
        case .genreRadio, .genreSimilar: return "Genre"
        case .decadeRadio, .decadeSimilar: return "Decade"
        case .starredRadio, .starredSimilar: return "Starred"
        }
    }
}

enum JellyfinRadioType: Equatable, Hashable {
    case libraryRadio
    case libraryInstantMix
    case genreRadio(String)
    case genreInstantMix(String)
    case decadeRadio(start: Int, end: Int, name: String)
    case decadeInstantMix(start: Int, end: Int, name: String)
    case favoritesRadio
    case favoritesInstantMix

    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .libraryInstantMix: return "Library Radio (Instant Mix)"
        case .genreRadio(let g): return "\(g) Radio"
        case .genreInstantMix(let g): return "\(g) Radio (Instant Mix)"
        case .decadeRadio(_, _, let n): return "\(n) Radio"
        case .decadeInstantMix(_, _, let n): return "\(n) Radio (Instant Mix)"
        case .favoritesRadio: return "Favorites Radio"
        case .favoritesInstantMix: return "Favorites Radio (Instant Mix)"
        }
    }
    var category: String {
        switch self {
        case .libraryRadio, .libraryInstantMix: return "Library"
        case .genreRadio, .genreInstantMix: return "Genre"
        case .decadeRadio, .decadeInstantMix: return "Decade"
        case .favoritesRadio, .favoritesInstantMix: return "Favorites"
        }
    }
}

enum EmbyRadioType: Equatable, Hashable {
    case libraryRadio
    case libraryInstantMix
    case genreRadio(String)
    case genreInstantMix(String)
    case decadeRadio(start: Int, end: Int, name: String)
    case decadeInstantMix(start: Int, end: Int, name: String)
    case favoritesRadio
    case favoritesInstantMix

    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .libraryInstantMix: return "Library Radio (Instant Mix)"
        case .genreRadio(let g): return "\(g) Radio"
        case .genreInstantMix(let g): return "\(g) Radio (Instant Mix)"
        case .decadeRadio(_, _, let n): return "\(n) Radio"
        case .decadeInstantMix(_, _, let n): return "\(n) Radio (Instant Mix)"
        case .favoritesRadio: return "Favorites Radio"
        case .favoritesInstantMix: return "Favorites Radio (Instant Mix)"
        }
    }
    var category: String {
        switch self {
        case .libraryRadio, .libraryInstantMix: return "Library"
        case .genreRadio, .genreInstantMix: return "Genre"
        case .decadeRadio, .decadeInstantMix: return "Decade"
        case .favoritesRadio, .favoritesInstantMix: return "Favorites"
        }
    }
}

enum LocalRadioType: Equatable, Hashable {
    case libraryRadio
    case genreRadio(String)
    case decadeRadio(start: Int, end: Int, name: String)

    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .genreRadio(let g): return "\(g) Radio"
        case .decadeRadio(_, _, let n): return "\(n) Radio"
        }
    }
    var category: String {
        switch self {
        case .libraryRadio: return "Library"
        case .genreRadio: return "Genre"
        case .decadeRadio: return "Decade"
        }
    }
}

// MARK: - Column Configuration

private struct ModernBrowserColumn {
    let id: String
    let title: String
    let minWidth: CGFloat
    
    // Original columns
    static let trackNumber = ModernBrowserColumn(id: "trackNum", title: "#", minWidth: 30)
    static let title = ModernBrowserColumn(id: "title", title: "Title", minWidth: 120)
    static let artist = ModernBrowserColumn(id: "artist", title: "Artist", minWidth: 100)
    static let album = ModernBrowserColumn(id: "album", title: "Album", minWidth: 100)
    static let year = ModernBrowserColumn(id: "year", title: "Year", minWidth: 45)
    static let genre = ModernBrowserColumn(id: "genre", title: "Genre", minWidth: 80)
    static let duration = ModernBrowserColumn(id: "duration", title: "Time", minWidth: 50)
    static let bitrate = ModernBrowserColumn(id: "bitrate", title: "Bitrate", minWidth: 55)
    static let size = ModernBrowserColumn(id: "size", title: "Size", minWidth: 55)
    static let rating = ModernBrowserColumn(id: "rating", title: "Rating", minWidth: 70)
    static let playCount = ModernBrowserColumn(id: "plays", title: "Plays", minWidth: 45)
    static let albums = ModernBrowserColumn(id: "albums", title: "Albums", minWidth: 55)
    
    // Additional columns (hidden by default)
    static let discNumber = ModernBrowserColumn(id: "discNum", title: "Disc", minWidth: 35)
    static let albumArtist = ModernBrowserColumn(id: "albumArtist", title: "Album Artist", minWidth: 100)
    static let sampleRate = ModernBrowserColumn(id: "sampleRate", title: "Sample Rate", minWidth: 60)
    static let channels = ModernBrowserColumn(id: "channels", title: "Channels", minWidth: 50)
    static let dateAdded = ModernBrowserColumn(id: "dateAdded", title: "Date Added", minWidth: 80)
    static let lastPlayed = ModernBrowserColumn(id: "lastPlayed", title: "Last Played", minWidth: 80)
    static let youtubeDate = ModernBrowserColumn(id: "youtubeDate", title: "Date", minWidth: 70)
    static let filePath = ModernBrowserColumn(id: "path", title: "Path", minWidth: 150)
    
    // All available columns (superset for each view type)
    static let allTrackColumns: [ModernBrowserColumn] = [
        .trackNumber, .title, .artist, .album, .albumArtist, .year, .genre, .duration,
        .bitrate, .sampleRate, .channels, .size, .rating, .playCount, .discNumber,
        .dateAdded, .lastPlayed, .filePath
    ]
    static let allAlbumColumns: [ModernBrowserColumn] = [.title, .year, .genre, .duration, .rating]
    static let allArtistColumns: [ModernBrowserColumn] = [.title, .rating, .albums, .genre]
    
    // Default visible column IDs (backwards-compatible with the original set)
    static let defaultTrackColumnIds: [String] = ["trackNum", "title", "artist", "album", "rating", "year", "genre", "duration", "bitrate", "size", "plays"]
    static let defaultAlbumColumnIds: [String] = ["title", "year", "genre", "duration", "rating"]
    static let defaultArtistColumnIds: [String] = ["title", "rating", "albums", "genre"]
    static let internetRadioColumns: [ModernBrowserColumn] = [.title, .genre, .rating]
    // YouTube channel uploads (Radio tab "Channels" view): title + (approximate) date + resizable time.
    static let youtubeColumns: [ModernBrowserColumn] = [.title, .youtubeDate, .duration]
    static let defaultYouTubeColumnIds: [String] = ["title", "youtubeDate", "duration"]
    
    // Legacy arrays kept for backwards compatibility with sort lookup
    static let trackColumns: [ModernBrowserColumn] = [.trackNumber, .title, .artist, .album, .rating, .year, .genre, .duration, .bitrate, .size, .playCount]
    static let albumColumns: [ModernBrowserColumn] = [.title, .year, .genre, .duration, .rating]
    static let artistColumns: [ModernBrowserColumn] = [.title, .rating, .albums, .genre]
    
    static func findColumn(id: String) -> ModernBrowserColumn? {
        if let c = allTrackColumns.first(where: { $0.id == id }) { return c }
        if let c = allAlbumColumns.first(where: { $0.id == id }) { return c }
        if let c = allArtistColumns.first(where: { $0.id == id }) { return c }
        if let c = internetRadioColumns.first(where: { $0.id == id }) { return c }
        if let c = youtubeColumns.first(where: { $0.id == id }) { return c }
        return nil
    }
}

// MARK: - Column Value Extraction

extension ModernDisplayItem {
    func columnValue(for column: ModernBrowserColumn) -> String {
        if column.id == "title" { return title }
        switch type {
        case .track(let t): return plexTrackValue(t, for: column)
        case .subsonicTrack(let s): return subsonicTrackValue(s, for: column)
        case .jellyfinTrack(let s): return jellyfinTrackValue(s, for: column)
        case .embyTrack(let s): return embyTrackValue(s, for: column)
        case .localTrack(let t): return localTrackValue(t, for: column)
        case .album(let a): return plexAlbumValue(a, for: column)
        case .subsonicAlbum(let a): return subsonicAlbumValue(a, for: column)
        case .jellyfinAlbum(let a): return jellyfinAlbumValue(a, for: column)
        case .embyAlbum(let a): return embyAlbumValue(a, for: column)
        case .localAlbum(let a): return localAlbumValue(a, for: column)
        case .artist(let a):
            if column.id == "albums",
               let info,
               let first = info.split(separator: " ").first,
               let count = Int(first) {
                return String(count)
            }
            return plexArtistValue(a, for: column)
        case .subsonicArtist(let a):
            if column.id == "albums" { return String(a.albumCount) }
            if column.id == "rating" { return a.starred != nil ? "★★★★★" : "" }
            return ""
        case .jellyfinArtist(let a):
            if column.id == "albums" { return String(a.albumCount) }
            if column.id == "rating" { return a.isFavorite ? "★★★★★" : "" }
            return ""
        case .embyArtist(let a):
            if column.id == "albums" { return String(a.albumCount) }
            if column.id == "rating" { return a.isFavorite ? "★★★★★" : "" }
            return ""
        case .localArtist(let a):
            if column.id == "albums" {
                if !a.albums.isEmpty { return String(a.albums.count) }
                if let info,
                   let first = info.split(separator: " ").first,
                   let count = Int(first) { return String(count) }
                return ""
            }
            if column.id == "rating" {
                guard let r = MediaLibrary.shared.artistRating(for: a.id), r > 0 else { return "" }
                let stars = r / 2; return String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            }
            return ""
        case .radioStation(let station):
            switch column.id {
            case "genre":
                return RadioManager.shared.normalizedGenre(for: station)
            case "rating":
                return Self.formatStarRating(RadioManager.shared.rating(for: station))
            default:
                return ""
            }
        case .youtubeVideo(let video):
            if column.id == "duration" {
                return video.formattedDuration ?? ""
            }
            if column.id == "youtubeDate" {
                return video.formattedDate ?? ""
            }
            return ""
        default: return ""
        }
    }

    private func plexTrackValue(_ track: PlexTrack, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "trackNum":
            if let disc = track.parentIndex, disc > 1, let num = track.index { return "\(disc)-\(num)" }
            return track.index.map { String($0) } ?? ""
        case "artist": return track.grandparentTitle ?? ""
        case "album": return track.parentTitle ?? ""
        case "albumArtist": return track.grandparentTitle ?? ""
        case "year": return track.parentYear.map { String($0) } ?? ""
        case "genre": return track.genre ?? ""
        case "duration": return track.formattedDuration
        case "bitrate": return track.media.first?.bitrate.map { "\($0)k" } ?? ""
        case "sampleRate": return track.media.first?.audioSampleRate.map { Self.formatSampleRate($0) } ?? ""
        case "channels": return track.media.first?.audioChannels.map { Self.formatChannels($0) } ?? ""
        case "size": return Self.formatFileSize(track.media.first?.parts.first?.size)
        case "rating": return Self.formatRating(track.userRating)
        case "plays": return track.ratingCount.map { String($0) } ?? ""
        case "discNum": return track.parentIndex.map { String($0) } ?? ""
        case "dateAdded": return track.addedAt.map { Self.formatDate($0) } ?? ""
        case "lastPlayed": return ""  // Not available in Plex API
        case "path": return track.media.first?.parts.first?.file ?? ""
        default: return ""
        }
    }
    
    private func subsonicTrackValue(_ song: SubsonicSong, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "trackNum":
            if let disc = song.discNumber, disc > 1, let num = song.track { return "\(disc)-\(num)" }
            return song.track.map { String($0) } ?? ""
        case "artist": return song.artist ?? ""
        case "album": return song.album ?? ""
        case "albumArtist": return song.albumArtist ?? song.artist ?? ""
        case "year": return song.year.map { String($0) } ?? ""
        case "genre": return song.genre ?? ""
        case "duration": return song.formattedDuration
        case "bitrate": return song.bitRate.map { "\($0)k" } ?? ""
        case "sampleRate": return song.samplingRate.map { Self.formatSampleRate($0) } ?? ""
        case "channels": return ""  // Not available in Subsonic API
        case "size": return Self.formatFileSize(song.size)
        case "rating":
            if let userRating = song.userRating, userRating > 0 {
                return Self.formatRating(Double(userRating) * 2.0)
            }
            return song.starred != nil ? "★★★★★" : Self.formatRating(nil)
        case "plays": return song.playCount.map { String($0) } ?? ""
        case "discNum": return song.discNumber.map { String($0) } ?? ""
        case "dateAdded": return song.created.map { Self.formatDate($0) } ?? ""
        case "lastPlayed": return ""  // Not available in Subsonic API
        case "path": return song.path ?? ""
        default: return ""
        }
    }
    
    private func localTrackValue(_ track: LibraryTrack, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "trackNum":
            if let disc = track.discNumber, disc > 1, let num = track.trackNumber { return "\(disc)-\(num)" }
            return track.trackNumber.map { String($0) } ?? ""
        case "artist": return track.artist ?? ""
        case "album": return track.album ?? ""
        case "albumArtist": return track.albumArtist ?? track.artist ?? ""
        case "year": return track.year.map { String($0) } ?? ""
        case "genre": return track.genre ?? ""
        case "duration": return track.formattedDuration
        case "bitrate": return track.bitrate.map { "\($0)k" } ?? ""
        case "sampleRate": return track.sampleRate.map { Self.formatSampleRate($0) } ?? ""
        case "channels": return track.channels.map { Self.formatChannels($0) } ?? ""
        case "size": return Self.formatFileSize(track.fileSize)
        case "rating": return Self.formatRating(track.rating.map { Double($0) })
        case "plays": return track.playCount > 0 ? String(track.playCount) : ""
        case "discNum": return track.discNumber.map { String($0) } ?? ""
        case "dateAdded": return Self.formatDate(track.dateAdded)
        case "lastPlayed": return track.lastPlayed.map { Self.formatDate($0) } ?? ""
        case "path": return track.url.path
        default: return ""
        }
    }
    
    private func plexAlbumValue(_ album: PlexAlbum, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "year": return album.year.map { String($0) } ?? ""
        case "genre": return album.genre ?? ""
        case "duration": return album.formattedDuration
        default: return ""
        }
    }
    
    private func subsonicAlbumValue(_ album: SubsonicAlbum, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "year": return album.year.map { String($0) } ?? ""
        case "genre": return album.genre ?? ""
        case "duration": return album.formattedDuration
        case "rating": return album.starred != nil ? "★★★★★" : ""
        default: return ""
        }
    }
    
    private func jellyfinTrackValue(_ song: JellyfinSong, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "trackNum":
            if let disc = song.discNumber, disc > 1, let num = song.track { return "\(disc)-\(num)" }
            return song.track.map { String($0) } ?? ""
        case "artist": return song.artist ?? ""
        case "album": return song.album ?? ""
        case "albumArtist": return song.albumArtist ?? song.artist ?? ""
        case "year": return song.year.map { String($0) } ?? ""
        case "genre": return song.genre ?? ""
        case "duration": return song.formattedDuration
        case "bitrate": return song.bitRate.map { "\($0)k" } ?? ""
        case "sampleRate": return song.sampleRate.map { Self.formatSampleRate($0) } ?? ""
        case "channels": return song.channels.map { Self.formatChannels($0) } ?? ""
        case "size": return Self.formatFileSize(song.size)
        case "rating":
            if let userRating = song.userRating, userRating > 0 {
                let stars = userRating / 20
                let empty = 5 - stars
                return String(repeating: "★", count: max(0, stars)) + String(repeating: "☆", count: max(0, empty))
            }
            return song.isFavorite ? "★" : ""
        case "plays": return song.playCount.map { String($0) } ?? ""
        case "discNum": return song.discNumber.map { String($0) } ?? ""
        case "dateAdded": return song.created.map { Self.formatDate($0) } ?? ""
        case "lastPlayed": return ""
        case "path": return song.path ?? ""
        default: return ""
        }
    }
    
    private func jellyfinAlbumValue(_ album: JellyfinAlbum, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "year": return album.year.map { String($0) } ?? ""
        case "genre": return album.genre ?? ""
        case "duration": return album.formattedDuration
        case "rating": return album.isFavorite ? "★★★★★" : ""
        default: return ""
        }
    }

    private func embyTrackValue(_ song: EmbySong, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "trackNum":
            if let disc = song.discNumber, disc > 1, let num = song.track { return "\(disc)-\(num)" }
            return song.track.map { String($0) } ?? ""
        case "artist": return song.artist ?? ""
        case "album": return song.album ?? ""
        case "albumArtist": return song.albumArtist ?? song.artist ?? ""
        case "year": return song.year.map { String($0) } ?? ""
        case "genre": return song.genre ?? ""
        case "duration": return song.formattedDuration
        case "bitrate": return song.bitRate.map { "\($0)k" } ?? ""
        case "sampleRate": return song.sampleRate.map { Self.formatSampleRate($0) } ?? ""
        case "channels": return song.channels.map { Self.formatChannels($0) } ?? ""
        case "size": return Self.formatFileSize(song.size)
        case "rating":
            if let userRating = song.userRating, userRating > 0 {
                let stars = userRating / 20
                let empty = 5 - stars
                return String(repeating: "★", count: max(0, stars)) + String(repeating: "☆", count: max(0, empty))
            }
            return song.isFavorite ? "★" : ""
        case "plays": return song.playCount.map { String($0) } ?? ""
        case "discNum": return song.discNumber.map { String($0) } ?? ""
        case "dateAdded": return song.created.map { Self.formatDate($0) } ?? ""
        case "lastPlayed": return ""
        case "path": return song.path ?? ""
        default: return ""
        }
    }

    private func embyAlbumValue(_ album: EmbyAlbum, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "year": return album.year.map { String($0) } ?? ""
        case "genre": return album.genre ?? ""
        case "duration": return album.formattedDuration
        case "rating": return album.isFavorite ? "★★★★★" : ""
        default: return ""
        }
    }

    private func localAlbumValue(_ album: Album, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "year": return album.year.map { String($0) } ?? ""
        case "duration": return album.formattedDuration
        case "rating":
            guard let r = MediaLibrary.shared.albumRating(for: album.id), r > 0 else { return "" }
            let stars = r / 2; return String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
        default: return ""
        }
    }
    
    private func plexArtistValue(_ artist: PlexArtist, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "albums": return String(artist.albumCount)
        case "genre": return artist.genre ?? ""
        default: return ""
        }
    }
    
    static func formatFileSize(_ bytes: Int64?) -> String {
        guard let bytes = bytes, bytes > 0 else { return "" }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1000 { return String(format: "%.1fG", mb / 1024.0) }
        return String(format: "%.1fM", mb)
    }
    
    private static func formatRating(_ rating: Double?) -> String {
        let stars = rating.map { max(0, Int($0 / 2.0)) } ?? 0
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
    }

    private static func formatStarRating(_ rating: Int) -> String {
        let clamped = min(5, max(0, rating))
        return String(repeating: "★", count: clamped) + String(repeating: "☆", count: 5 - clamped)
    }
    
    static func formatSampleRate(_ hz: Int) -> String {
        let khz = Double(hz) / 1000.0
        if khz == Double(Int(khz)) { return "\(Int(khz))k" }
        return String(format: "%.1fk", khz)
    }
    
    static func formatChannels(_ count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(count)ch"
        }
    }
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    
    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
    
    /// Returns the raw sortable date for a column, if applicable
    func columnDateValue(for column: ModernBrowserColumn) -> Date? {
        switch column.id {
        case "dateAdded":
            switch type {
            case .localTrack(let t): return t.dateAdded
            case .track(let t): return t.addedAt
            case .subsonicTrack(let s): return s.created
            case .jellyfinTrack(let s): return s.created
            case .embyTrack(let s): return s.created
            default: return nil
            }
        case "lastPlayed":
            switch type {
            case .localTrack(let t): return t.lastPlayed
            default: return nil
            }
        case "youtubeDate":
            if case .youtubeVideo(let video) = type { return video.publishedAt }
            return nil
        default: return nil
        }
    }
}
