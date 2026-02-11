import AppKit
import AVFoundation

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
    case radio
    
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
        case .radio: return "INTERNET RADIO"
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
        case .radio: return "Radio"
        }
    }
    
    var isSubsonic: Bool { if case .subsonic = self { return true }; return false }
    var isPlex: Bool { if case .plex = self { return true }; return false }
    var isRadio: Bool { if case .radio = self { return true }; return false }
    var isRemote: Bool {
        switch self { case .local, .radio: return false; case .plex, .subsonic: return true }
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
    case artists = 0, albums = 1, tracks = 2, plists = 3
    case movies = 4, shows = 5, search = 6, radio = 7
    
    var title: String {
        switch self {
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .tracks: return "Tracks"
        case .plists: return "Plists"
        case .movies: return "Movies"
        case .shows: return "Shows"
        case .search: return "Search"
        case .radio: return "Radio"
        }
    }
    var isVideoMode: Bool { self == .movies || self == .shows }
    var isMusicMode: Bool { self == .artists || self == .albums || self == .tracks || self == .plists }
    var isRadioMode: Bool { self == .radio }
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
    
    // Browse state
    private var currentSource: ModernBrowserSource = .local {
        didSet { currentSource.save(); onSourceChanged() }
    }
    private var pendingSourceRestore: ModernBrowserSource?
    private var browseMode: ModernBrowseMode = .artists
    private var currentSort: ModernBrowserSortOption = .nameAsc {
        didSet { currentSort.save(); rebuildCurrentModeItems(); needsDisplay = true }
    }
    private var searchQuery: String = ""
    private var selectedIndices: Set<Int> = []
    private var scrollOffset: CGFloat = 0
    private var horizontalScrollOffset: CGFloat = 0
    
    private var itemHeight: CGFloat { 18 * ModernSkinElements.sizeMultiplier }
    private var columnHeaderHeight: CGFloat { 18 * ModernSkinElements.sizeMultiplier }
    
    // Column state
    private var columnWidths: [String: CGFloat] = [:] { didSet { saveColumnWidths() } }
    private var resizingColumnId: String?
    private var resizeStartX: CGFloat = 0
    private var resizeStartWidth: CGFloat = 0
    private var columnSortId: String? { didSet { saveColumnSort(); applyColumnSort(collapseExpanded: true) } }
    private var columnSortAscending: Bool = true { didSet { saveColumnSort(); applyColumnSort(collapseExpanded: true) } }
    
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
    private var artistAlbumsByName: [String: [PlexAlbum]] = [:]
    
    // Cached data - Local
    private var cachedLocalArtists: [Artist] = []
    private var cachedLocalAlbums: [Album] = []
    private var cachedLocalTracks: [LibraryTrack] = []
    
    // Cached data - Subsonic
    private var cachedSubsonicArtists: [SubsonicArtist] = []
    private var cachedSubsonicAlbums: [SubsonicAlbum] = []
    private var cachedSubsonicPlaylists: [SubsonicPlaylist] = []
    private var subsonicArtistAlbums: [String: [SubsonicAlbum]] = [:]
    private var subsonicPlaylistTracks: [String: [SubsonicSong]] = [:]
    private var subsonicAlbumSongs: [String: [SubsonicSong]] = [:]
    private var subsonicLoadTask: Task<Void, Never>?
    private var subsonicExpandTask: Task<Void, Never>?
    
    // Cached data - Radio
    private var cachedRadioStations: [RadioStation] = []
    private var activeRadioStationSheet: AddRadioStationSheet?
    
    // Cached data - Video
    private var cachedMovies: [PlexMovie] = []
    private var cachedShows: [PlexShow] = []
    private var showSeasons: [String: [PlexSeason]] = [:]
    private var seasonEpisodes: [String: [PlexEpisode]] = [:]
    
    // Cached data - Playlists (Plex)
    private var cachedPlexPlaylists: [PlexPlaylist] = []
    private var plexPlaylistTracks: [String: [PlexTrack]] = [:]
    
    // Search
    private var searchResults: PlexSearchResults?
    
    // Animation
    private var loadingAnimationTimer: Timer?
    private var loadingAnimationFrame: Int = 0
    private var serverNameScrollOffset: CGFloat = 0
    private var libraryNameScrollOffset: CGFloat = 0
    private var serverScrollTimer: Timer?
    private var lastServerName: String = ""
    private var lastLibraryName: String = ""
    
    // Shade mode
    private(set) var isShadeMode = false
    
    // Art-only mode
    private var isArtOnlyMode: Bool = false {
        didSet {
            needsDisplay = true
            if isArtOnlyMode { fetchCurrentTrackRating(); loadAllArtworkForCurrentTrack() }
            else { isVisualizingArt = false; artworkImages = []; artworkIndex = 0 }
        }
    }
    private var isVisualizingArt: Bool = false {
        didSet {
            if isVisualizingArt { startVisualizerTimer() } else { stopVisualizerTimer() }
            needsDisplay = true
        }
    }
    
    // Rating overlay
    private var isRatingOverlayVisible: Bool = false
    private var currentTrackRating: Int? = nil
    private var rateButtonRect: NSRect = .zero
    private var ratingSubmitTask: Task<Void, Never>?
    
    // Artwork
    private var currentArtwork: NSImage?
    private var artworkTrackId: UUID?
    private var artworkLoadTask: Task<Void, Never>?
    private var artworkCyclingTask: Task<Void, Never>?
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
    }
    enum VisMode { case single, random, cycle }
    private var currentVisEffect: VisEffect = .psychedelic
    private var visMode: VisMode = .single
    private var cycleTimer: Timer?
    private var cycleInterval: TimeInterval = 10.0
    private var lastBeatTime: TimeInterval = 0
    private var visEffectIntensity: CGFloat = 1.0
    private var visualizerTimer: Timer?
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
    
    // Button/drag state
    private var pressedButton: LibraryBrowserButtonType?
    private var activeTagsPanel: TagsPanel?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var isDraggingScrollbar = false
    private var scrollbarDragStartY: CGFloat = 0
    private var scrollbarDragStartOffset: CGFloat = 0
    private let alphabetLetters = ["#"] + (65...90).map { String(UnicodeScalar($0)) }
    
    // MARK: - Layout Constants (independent of classic skin)
    
    private struct Layout {
        static var titleBarHeight: CGFloat { WindowManager.shared.hideTitleBars ? borderWidth : ModernSkinElements.libraryTitleBarHeight }
        static var tabBarHeight: CGFloat { 24 * ModernSkinElements.sizeMultiplier }
        static var serverBarHeight: CGFloat { 24 * ModernSkinElements.sizeMultiplier }
        static var searchBarHeight: CGFloat { 26 * ModernSkinElements.sizeMultiplier }
        static var statusBarHeight: CGFloat { 6 * ModernSkinElements.sizeMultiplier }
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
        
        // Load skin (respecting lock)
        let skin: ModernSkin
        if WindowManager.shared.lockBrowserProjectMSkin {
            skin = ModernSkinLoader.shared.loadDefault()
        } else {
            skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        }
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
            case .radio:
                currentSource = .radio
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
        
        // Load saved visualizer preferences
        if let savedEffect = UserDefaults.standard.string(forKey: "browserVisEffect"),
           let effect = VisEffect(rawValue: savedEffect) {
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
        NotificationCenter.default.addObserver(self, selector: #selector(trackDidChange),
                                               name: .audioTrackDidChange, object: nil)
        
        // Window visibility notifications
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMiniaturize),
                                               name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidDeminiaturize),
                                               name: NSWindow.didDeminiaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeOcclusionState),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        
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
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopLoadingAnimation()
        stopServerNameScroll()
        stopVisualizerTimer()
    }
    
    // MARK: - Current Skin Helper
    
    private func currentSkin() -> ModernSkin {
        if WindowManager.shared.lockBrowserProjectMSkin {
            return ModernSkinLoader.shared.loadDefault()
        }
        return ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        let capturedArtwork = currentArtwork
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let skin = currentSkin()
        let renderer = ModernSkinRenderer(skin: skin)
        
        if isShadeMode {
            // Draw shade mode
            renderer.drawWindowBackground(in: bounds, context: context)
            renderer.drawWindowBorder(in: bounds, context: context)
            
            // Draw title text centered
            let font = skin.primaryFont?.withSize(10) ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: skin.textColor]
            let title = "NULLPLAYER LIBRARY"
            let titleSize = title.size(withAttributes: attrs)
            let titleOrigin = NSPoint(x: bounds.midX - titleSize.width / 2,
                                       y: bounds.midY - titleSize.height / 2)
            title.draw(at: titleOrigin, withAttributes: attrs)
            
            // Draw close and shade buttons (base space for renderer scaling)
            let shadeScale = ModernSkinElements.scaleFactor
            let shadeBaseW = bounds.width / shadeScale
            let shadeBaseH = bounds.height / shadeScale
            let closeBtnRect = NSRect(x: shadeBaseW - 14, y: (shadeBaseH - 10) / 2, width: 10, height: 10)
            let shadeBtnRect = NSRect(x: shadeBaseW - 26, y: (shadeBaseH - 10) / 2, width: 10, height: 10)
            let closeState = pressedButton == .close ? "pressed" : "normal"
            let shadeState = pressedButton == .shade ? "pressed" : "normal"
            renderer.drawWindowControlButton("library_btn_close", state: closeState, in: closeBtnRect, context: context)
            renderer.drawWindowControlButton("library_btn_shade", state: shadeState, in: shadeBtnRect, context: context)
            return
        }
        
        // Normal mode - bottom-left origin (no coordinate flipping)
        renderer.drawWindowBackground(in: bounds, context: context)
        renderer.drawWindowBorder(in: bounds, context: context)
        
        // Title bar, close, shade buttons use base (unscaled) coordinates
        // because the renderer's scaledRect() multiplies by scaleFactor
        let scale = ModernSkinElements.scaleFactor
        let baseWidth = bounds.width / scale
        let baseHeight = bounds.height / scale
        
        // Draw title bar (unless hidden)
        if !WindowManager.shared.hideTitleBars {
            // Title bar at TOP in base space
            let titleBarRect = NSRect(x: 0, y: baseHeight - 14, width: baseWidth, height: 14)
            renderer.drawTitleBar(in: titleBarRect, title: "NULLPLAYER LIBRARY", context: context)
            
            // Close and shade buttons in title bar (base space)
            let closeBtnRect = NSRect(x: baseWidth - 14, y: baseHeight - 12, width: 10, height: 10)
            let shadeBtnRect = NSRect(x: baseWidth - 26, y: baseHeight - 12, width: 10, height: 10)
            let closeState = pressedButton == .close ? "pressed" : "normal"
            let shadeState = pressedButton == .shade ? "pressed" : "normal"
            renderer.drawWindowControlButton("library_btn_close", state: closeState, in: closeBtnRect, context: context)
            renderer.drawWindowControlButton("library_btn_shade", state: shadeState, in: shadeBtnRect, context: context)
        }
        
        // Server bar (below title bar in screen coords)
        let serverBarY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight
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
        
        // List area (between content top and status bar bottom)
        let listAreaY = statusBarHeight
        let listAreaHeight = contentTopY - statusBarHeight
        let listRect = NSRect(x: Layout.borderWidth, y: listAreaY,
                              width: bounds.width - Layout.borderWidth * 2, height: listAreaHeight)
        
        if isArtOnlyMode {
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
    }
    
    // MARK: - Tab Bar Drawing (Modern Boxed Toggle Style)
    
    private func drawTabBar(in context: CGContext, tabBarY: CGFloat, skin: ModernSkin) {
        let tabBarRect = NSRect(x: Layout.borderWidth, y: tabBarY,
                                width: bounds.width - Layout.borderWidth * 2, height: Layout.tabBarHeight)
        
        // Background
        skin.surfaceColor.withAlphaComponent(0.4).setFill()
        context.fill(tabBarRect)
        
        let font = skin.sideWindowFont(size: 11)
        
        // Sort indicator width on right
        let sortText = "Sort"
        let sortAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: skin.textDimColor]
        let sortSize = sortText.size(withAttributes: sortAttrs)
        let sortWidth = sortSize.width + 16
        
        let tabsWidth = tabBarRect.width - sortWidth
        let tabWidth = tabsWidth / CGFloat(ModernBrowseMode.allCases.count)
        
        for (index, mode) in ModernBrowseMode.allCases.enumerated() {
            let tabRect = NSRect(x: tabBarRect.minX + CGFloat(index) * tabWidth, y: tabBarY,
                                 width: tabWidth, height: Layout.tabBarHeight)
            let isSelected = mode == browseMode
            drawToggleTab(label: mode.title, isActive: isSelected, rect: tabRect.insetBy(dx: 2, dy: 2),
                          font: font, skin: skin, context: context)
        }
        
        // Sort indicator
        let sortRect = NSRect(x: tabBarRect.maxX - sortWidth, y: tabBarY,
                              width: sortWidth, height: Layout.tabBarHeight)
        drawToggleTab(label: sortText, isActive: false, rect: sortRect.insetBy(dx: 2, dy: 2),
                      font: font, skin: skin, context: context)
    }
    
    /// Draw a modern boxed toggle button
    private func drawToggleTab(label: String, isActive: Bool, rect: NSRect,
                               font: NSFont, skin: ModernSkin, context: CGContext) {
        let color = isActive ? skin.accentColor : skin.textDimColor
        
        context.saveGState()
        
        if isActive {
            context.setFillColor(skin.accentColor.withAlphaComponent(0.12).cgColor)
            context.fill(rect)
            
            context.setShadow(offset: .zero, blur: 6, color: skin.accentColor.withAlphaComponent(0.6).cgColor)
            context.setStrokeColor(skin.accentColor.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(1.0)
            context.stroke(rect)
            context.restoreGState()
            
            context.saveGState()
            context.setStrokeColor(skin.accentColor.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1.0)
            context.stroke(rect)
        } else {
            context.setStrokeColor(skin.textDimColor.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(0.5)
            context.stroke(rect)
        }
        
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = label.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: rect.midX - textSize.width / 2,
                                  y: rect.midY - textSize.height / 2)
        label.draw(at: textOrigin, withAttributes: attrs)
        
        context.restoreGState()
    }
    
    // MARK: - Server Bar Drawing
    
    private func drawServerBar(in context: CGContext, serverBarY: CGFloat, skin: ModernSkin) {
        let barRect = NSRect(x: Layout.borderWidth, y: serverBarY,
                            width: bounds.width - Layout.borderWidth * 2,
                            height: Layout.serverBarHeight)
        
        skin.surfaceColor.withAlphaComponent(0.4).setFill()
        context.fill(barRect)
        
        let font = skin.sideWindowFont(size: 11)
        let textColor = skin.textColor
        let dimColor = skin.textDimColor
        let accentColor = skin.accentColor
        
        let m = ModernSkinElements.sizeMultiplier
        let textY = barRect.minY + (barRect.height - font.pointSize - 2 * m) / 2
        
        // Common prefix
        let prefixAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dimColor]
        let prefix = "Source: "
        prefix.draw(at: NSPoint(x: barRect.minX + 4 * m, y: textY), withAttributes: prefixAttrs)
        let prefixWidth = prefix.size(withAttributes: prefixAttrs).width
        let sourceNameStartX = barRect.minX + 4 * m + prefixWidth
        
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let activeAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: accentColor]
        
        // Right side: F5 refresh label
        let refreshText = "F5"
        let refreshWidth = refreshText.size(withAttributes: prefixAttrs).width
        let refreshX = barRect.maxX - refreshWidth - 8 * m
        refreshText.draw(at: NSPoint(x: refreshX, y: textY), withAttributes: prefixAttrs)
        
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
           currentTrack.plexRatingKey != nil || currentTrack.subsonicId != nil || currentTrack.url.isFileURL {
            let starSize: CGFloat = 14 * m
            let starSpacing: CGFloat = 4 * m
            let totalStars = 5
            let starsWidth = CGFloat(totalStars) * starSize + CGFloat(totalStars - 1) * starSpacing
            let starsX = visEndX - starsWidth - 16 * m
            let starY = barRect.minY + (barRect.height - starSize) / 2
            
            // Get current rating (0-10 scale -> 0-5 filled stars)
            let rating = currentTrackRating ?? 0
            let filledCount = rating / 2
            
            let filledColor = accentColor
            let emptyColor = dimColor.withAlphaComponent(0.3)
            
            for i in 0..<totalStars {
                let x = starsX + CGFloat(i) * (starSize + starSpacing)
                let starRect = NSRect(x: x, y: starY, width: starSize, height: starSize)
                let isFilled = i < filledCount
                drawPixelStar(in: starRect, color: isFilled ? filledColor : emptyColor, context: context)
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
            sourceText.draw(at: NSPoint(x: sourceNameStartX, y: textY), withAttributes: nameAttrs)
            let sourceTextWidth = sourceText.size(withAttributes: nameAttrs).width
            
            let addText = "+ADD"
            let addX = sourceNameStartX + sourceTextWidth + 28 * m
            addText.draw(at: NSPoint(x: addX, y: textY), withAttributes: activeAttrs)
            
            // Item count (only in list mode, not art-only)
            if !isArtOnlyMode {
                let countText = "\(displayItems.count) items"
                let countWidth = countText.size(withAttributes: prefixAttrs).width
                let countX = visEndX - countWidth - 24 * m
                countText.draw(at: NSPoint(x: countX, y: textY), withAttributes: nameAttrs)
            }
            
        case .plex(let serverId):
            let manager = PlexManager.shared
            let configuredServer = manager.servers.first(where: { $0.id == serverId })
            
            if configuredServer != nil || manager.isLinked {
                let serverName = configuredServer?.name ?? "Select Server"
                let maxServerWidth: CGFloat = 100 * m
                
                context.saveGState()
                let clipRect = NSRect(x: sourceNameStartX, y: textY, width: maxServerWidth, height: font.pointSize + 4 * m)
                context.clip(to: clipRect)
                serverName.draw(at: NSPoint(x: sourceNameStartX, y: textY), withAttributes: nameAttrs)
                context.restoreGState()
                
                let libLabel = "Lib:"
                let libraryLabelX = sourceNameStartX + maxServerWidth + 16 * m
                libLabel.draw(at: NSPoint(x: libraryLabelX, y: textY), withAttributes: prefixAttrs)
                
                let libLabelWidth = libLabel.size(withAttributes: prefixAttrs).width
                let libraryX = libraryLabelX + libLabelWidth + 4 * m
                let libraryText = manager.currentLibrary?.title ?? "Select"
                let maxLibraryWidth: CGFloat = 80 * m
                
                context.saveGState()
                let libClipRect = NSRect(x: libraryX, y: textY, width: maxLibraryWidth, height: font.pointSize + 4 * m)
                context.clip(to: libClipRect)
                libraryText.draw(at: NSPoint(x: libraryX, y: textY), withAttributes: nameAttrs)
                context.restoreGState()
                
                // Item count (only in list mode, not art-only)
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
                    let countWidth = countText.size(withAttributes: prefixAttrs).width
                    let countX = visEndX - countWidth - 24 * m
                    countText.draw(at: NSPoint(x: countX, y: textY), withAttributes: nameAttrs)
                }
            } else {
                let linkText = "Click to link your Plex account"
                let linkWidth = linkText.size(withAttributes: prefixAttrs).width
                let linkX = barRect.midX - linkWidth / 2
                linkText.draw(at: NSPoint(x: linkX, y: textY), withAttributes: prefixAttrs)
            }
            
        case .subsonic(let serverId):
            let configuredServer = SubsonicManager.shared.servers.first(where: { $0.id == serverId })
            if configuredServer != nil {
                let serverName = configuredServer?.name ?? "Select Server"
                serverName.draw(at: NSPoint(x: sourceNameStartX, y: textY), withAttributes: nameAttrs)
                
                // Item count (only in list mode, not art-only)
                if !isArtOnlyMode {
                    let countText = "\(displayItems.count) items"
                    let countWidth = countText.size(withAttributes: prefixAttrs).width
                    let countX = visEndX - countWidth - 24 * m
                    countText.draw(at: NSPoint(x: countX, y: textY), withAttributes: nameAttrs)
                }
            } else {
                let linkText = "Click to add a Subsonic server"
                let linkWidth = linkText.size(withAttributes: prefixAttrs).width
                let linkX = barRect.midX - linkWidth / 2
                linkText.draw(at: NSPoint(x: linkX, y: textY), withAttributes: prefixAttrs)
            }
            
        case .radio:
            let sourceText = "Internet Radio"
            sourceText.draw(at: NSPoint(x: sourceNameStartX, y: textY), withAttributes: nameAttrs)
            let sourceTextWidth = sourceText.size(withAttributes: nameAttrs).width
            
            let addText = "+ADD"
            let addX = sourceNameStartX + sourceTextWidth + 28 * m
            addText.draw(at: NSPoint(x: addX, y: textY), withAttributes: activeAttrs)
            
            // Item count (only in list mode, not art-only)
            if !isArtOnlyMode {
                let countText = "\(displayItems.count) stations"
                let countWidth = countText.size(withAttributes: prefixAttrs).width
                let countX = visEndX - countWidth - 24 * m
                countText.draw(at: NSPoint(x: countX, y: textY), withAttributes: nameAttrs)
            }
        }
    }
    
    /// Draw a low-res pixel-art star for server bar rating display
    /// Pattern is top-down but macOS Y goes up, so we draw rows from maxY downward
    private func drawPixelStar(in rect: NSRect, color: NSColor, context: CGContext) {
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
        
        context.setFillColor(color.cgColor)
        
        for row in 0..<patternSize {
            for col in 0..<patternSize {
                if pattern[row][col] == 1 {
                    let x = rect.minX + CGFloat(col) * pixelW
                    // Flip Y: row 0 (top of star) draws at maxY, row 8 at minY
                    let y = rect.maxY - CGFloat(row + 1) * pixelH
                    context.fill(CGRect(x: x, y: y, width: ceil(pixelW), height: ceil(pixelH)))
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
        let bgColor = isFocused
            ? skin.accentColor.withAlphaComponent(0.15)
            : skin.surfaceColor.withAlphaComponent(0.3)
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: searchRect, xRadius: 3, yRadius: 3)
        path.fill()
        
        if isFocused {
            skin.accentColor.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        
        let font = skin.smallFont?.withSize(9) ?? NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let displayText = searchQuery.isEmpty ? "Type to search..." : searchQuery
        let textColor = searchQuery.isEmpty ? skin.textDimColor : skin.textColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = displayText.size(withAttributes: attrs)
        let textY = searchRect.minY + (searchRect.height - textSize.height) / 2
        displayText.draw(at: NSPoint(x: searchRect.minX + 6, y: textY), withAttributes: attrs)
        
        // Draw cursor
        if isFocused && !searchQuery.isEmpty {
            let cursorX = searchRect.minX + 6 + searchQuery.size(withAttributes: attrs).width + 1
            skin.textColor.setFill()
            context.fill(CGRect(x: cursorX, y: textY, width: 1, height: textSize.height))
        }
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
        
        // Determine header columns
        let headerColumns: [ModernBrowserColumn]?
        if displayItems.contains(where: {
            switch $0.type { case .track, .subsonicTrack, .localTrack: return true; default: return false }
        }) {
            headerColumns = ModernBrowserColumn.trackColumns
        } else if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum: return true; default: return false }
        }) {
            headerColumns = ModernBrowserColumn.albumColumns
        } else if displayItems.contains(where: {
            switch $0.type { case .artist, .subsonicArtist, .localArtist: return true; default: return false }
        }) {
            headerColumns = ModernBrowserColumn.artistColumns
        } else {
            headerColumns = nil
        }
        
        // Draw column headers
        var contentListY = listAreaY
        if let columns = headerColumns {
            let headerY = listAreaY + listAreaHeight - columnHeaderHeight
            let headerRect = NSRect(x: fullListRect.minX, y: headerY,
                                    width: fullListRect.width, height: columnHeaderHeight)
            drawColumnHeaders(in: context, rect: headerRect, columns: columns, skin: skin)
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
        
        // Draw album art background if enabled
        if WindowManager.shared.showBrowserArtworkBackground, let artworkImage = artwork,
           let cgImage = artworkImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.saveGState()
            let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
            let artworkRect = calculateCenterFillRect(imageSize: imageSize, in: listRect)
            context.setAlpha(0.12)
            context.draw(cgImage, in: artworkRect)
            context.restoreGState()
        }
        
        // Draw items (bottom-left origin: item 0 at top of list, so we draw from top down)
        let visibleStart = max(0, Int(scrollOffset / itemHeight))
        let visibleEnd = min(displayItems.count, visibleStart + Int(contentHeight / itemHeight) + 2)
        
        guard visibleStart < visibleEnd else {
            context.restoreGState()
            let alphabetRect = NSRect(x: bounds.width - Layout.borderWidth - Layout.scrollbarWidth - alphabetWidth,
                                     y: listAreaY, width: alphabetWidth, height: listAreaHeight)
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
            
            // Selection background - subtle to keep accent text readable
            if isSelected {
                skin.primaryColor.withAlphaComponent(0.06).setFill()
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
                
                // Expand/collapse indicator
                if item.hasChildren {
                    let expanded = isExpanded(item)
                    let indicator = expanded ? "▼" : "▶"
                    let indicatorAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: skin.textDimColor,
                        .font: skin.scaledSystemFont(size: 6.4)
                    ]
                    indicator.draw(at: NSPoint(x: textX - 12, y: itemRect.midY - 5), withAttributes: indicatorAttrs)
                }
                
                // Main text
                let textColor = isSelected ? skin.accentColor : skin.textColor
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: textColor,
                    .font: font
                ]
                let textRect = NSRect(x: textX, y: itemRect.minY + 2,
                                     width: itemRect.width - indent - 60, height: itemHeight - 4)
                item.title.draw(in: textRect, withAttributes: attrs)
                
                // Secondary info
                if let info = item.info {
                    let infoColor = isSelected ? skin.accentColor : skin.textDimColor
                    let infoAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: infoColor,
                        .font: smallFont
                    ]
                    let infoSize = info.size(withAttributes: infoAttrs)
                    info.draw(at: NSPoint(x: itemRect.maxX - infoSize.width - 4, y: itemRect.midY - infoSize.height / 2),
                             withAttributes: infoAttrs)
                }
            }
        }
        
        context.restoreGState()
        
        // Draw alphabet index
        let alphabetRect = NSRect(x: bounds.width - Layout.borderWidth - Layout.scrollbarWidth - alphabetWidth,
                                 y: listAreaY, width: alphabetWidth, height: listAreaHeight)
        drawAlphabetIndex(in: context, rect: alphabetRect, skin: skin)
    }
    
    // MARK: - Column Headers
    
    private func drawColumnHeaders(in context: CGContext, rect: NSRect, columns: [ModernBrowserColumn], skin: ModernSkin) {
        context.saveGState()
        context.clip(to: rect)
        
        skin.surfaceColor.withAlphaComponent(0.9).setFill()
        context.fill(rect)
        
        let headerFont = skin.scaledSystemFont(size: 7.2, weight: .medium)
        let headerColor = skin.textDimColor.withAlphaComponent(0.7)
        let sortedHeaderColor = skin.textColor.withAlphaComponent(0.9)
        let separatorColor = skin.textDimColor.withAlphaComponent(0.2)
        
        var x = rect.minX + 4 - horizontalScrollOffset
        for (index, column) in columns.enumerated() {
            let width = widthForColumn(column, availableWidth: rect.width, columns: columns)
            let isSortColumn = columnSortId == column.id
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: isSortColumn ? sortedHeaderColor : headerColor
            ]
            
            let textSize = column.title.size(withAttributes: attrs)
            let textY = rect.minY + (columnHeaderHeight - textSize.height) / 2
            let textX = x + 4
            column.title.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
            
            if isSortColumn {
                let indicator = columnSortAscending ? "▲" : "▼"
                let indicatorAttrs: [NSAttributedString.Key: Any] = [
                    .font: skin.scaledSystemFont(size: 5.6),
                    .foregroundColor: sortedHeaderColor
                ]
                indicator.draw(at: NSPoint(x: textX + textSize.width + 3, y: textY + 1), withAttributes: indicatorAttrs)
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
        let textColor = isSelected ? skin.accentColor : skin.textColor
        let dimColor = isSelected ? skin.accentColor : skin.textDimColor
        let font = skin.scaledSystemFont(size: 8)
        let smallFont = skin.scaledSystemFont(size: 7.2)
        
        var x = rect.minX + indent + 4 - horizontalScrollOffset
        for column in columns {
            let width = widthForColumn(column, availableWidth: totalWidth, columns: columns)
            let value = item.columnValue(for: column)
            
            let color = column.id == "title" ? textColor : dimColor
            let useFont = column.id == "title" ? font : smallFont
            
            let attrs: [NSAttributedString.Key: Any] = [.font: useFont, .foregroundColor: color]
            let textSize = value.size(withAttributes: attrs)
            let textY = rect.minY + (rect.height - textSize.height) / 2
            let textX = x + 4
            let maxTextWidth = width - 8
            
            let drawRect = NSRect(x: textX, y: textY, width: maxTextWidth, height: textSize.height)
            value.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            
            x += width
        }
    }
    
    // MARK: - State Drawing Methods
    
    private func drawNotLinkedState(in context: CGContext, listRect: NSRect, skin: ModernSkin) {
        let message = "Link your Plex account to browse your music library"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.textDimColor,
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2),
                    withAttributes: attrs)
        
        let hint = "Click the server bar above to link"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.warningColor,
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        hint.draw(at: NSPoint(x: listRect.midX - hintSize.width / 2, y: listRect.midY - size.height / 2 - 20),
                 withAttributes: hintAttrs)
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
    
    private func drawErrorState(in context: CGContext, message: String, listRect: NSRect, skin: ModernSkin) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.textDimColor,
            .font: NSFont.systemFont(ofSize: 11)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2),
                    withAttributes: attrs)
    }
    
    private func drawEmptyState(in context: CGContext, listRect: NSRect, skin: ModernSkin) {
        let library = PlexManager.shared.currentLibrary
        let message: String
        switch browseMode {
        case .artists, .albums, .tracks:
            if currentSource.isPlex && library?.isMusicLibrary == true {
                message = "No \(browseMode.title.lowercased()) found"
            } else if currentSource.isSubsonic || (currentSource.isPlex && library?.isMusicLibrary != true) {
                message = "No \(browseMode.title.lowercased()) found"
            } else {
                message = "No \(browseMode.title.lowercased()) found"
            }
        case .movies: message = "No movies found"
        case .shows: message = "No TV shows found"
        case .plists: message = "No playlists found"
        case .search: message = searchQuery.isEmpty ? "Type to search" : "No results found"
        case .radio: message = "No radio stations found"
        }
        
        let font = skin.primaryFont?.withSize(10) ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: skin.textDimColor]
        let textSize = message.size(withAttributes: attrs)
        let textX = listRect.midX - textSize.width / 2
        let textY = listRect.midY - textSize.height / 2
        message.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }
    
    // MARK: - Art Only Area
    
    private func drawArtOnlyArea(in context: CGContext, contentRect: NSRect, skin: ModernSkin, artwork: NSImage?) {
        if isVisualizingArt {
            NSColor.black.setFill()
        } else {
            skin.surfaceColor.setFill()
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
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: skin.textDimColor]
            let textSize = message.size(withAttributes: attrs)
            message.draw(at: NSPoint(x: contentRect.midX - textSize.width / 2,
                                      y: contentRect.midY - textSize.height / 2), withAttributes: attrs)
        }
    }
    
    // MARK: - Alphabet Index
    
    private func drawAlphabetIndex(in context: CGContext, rect: NSRect, skin: ModernSkin) {
        skin.surfaceColor.withAlphaComponent(0.3).setFill()
        context.fill(rect)
        
        let letterCount = CGFloat(alphabetLetters.count)
        let letterHeight = rect.height / letterCount
        let fontSize = min(9 * ModernSkinElements.sizeMultiplier, letterHeight * 0.8)
        
        var availableLetters = Set<String>()
        for item in displayItems {
            availableLetters.insert(sortLetter(for: item.title))
        }
        
        for (index, letter) in alphabetLetters.enumerated() {
            // Bottom-left origin: # at top, Z at bottom
            let y = rect.maxY - CGFloat(index + 1) * letterHeight
            let letterRect = NSRect(x: rect.minX, y: y, width: rect.width, height: letterHeight)
            
            let hasItems = availableLetters.contains(letter)
            let color = hasItems ? skin.accentColor : skin.textDimColor.withAlphaComponent(0.3)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.boldSystemFont(ofSize: fontSize)
            ]
            let letterSize = letter.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: letterRect.midX - letterSize.width / 2,
                y: letterRect.midY - letterSize.height / 2
            )
            letter.draw(at: drawPoint, withAttributes: attrs)
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
    
    private func columnsForItem(_ item: ModernDisplayItem) -> [ModernBrowserColumn]? {
        switch item.type {
        case .track, .subsonicTrack, .localTrack:
            let visible = visibleTrackColumnIds
            return ModernBrowserColumn.allTrackColumns
                .filter { visible.contains($0.id) }
                .sorted { visible.firstIndex(of: $0.id)! < visible.firstIndex(of: $1.id)! }
        case .album, .subsonicAlbum, .localAlbum:
            let visible = visibleAlbumColumnIds
            return ModernBrowserColumn.allAlbumColumns
                .filter { visible.contains($0.id) }
                .sorted { visible.firstIndex(of: $0.id)! < visible.firstIndex(of: $1.id)! }
        case .artist, .subsonicArtist, .localArtist:
            if item.indentLevel == 0 {
                let visible = visibleArtistColumnIds
                return ModernBrowserColumn.allArtistColumns
                    .filter { visible.contains($0.id) }
                    .sorted { visible.firstIndex(of: $0.id)! < visible.firstIndex(of: $1.id)! }
            }
            return nil
        default:
            return nil
        }
    }
    
    private func widthForColumn(_ column: ModernBrowserColumn, availableWidth: CGFloat, columns: [ModernBrowserColumn]) -> CGFloat {
        if column.id == "title" {
            // If a stored width exists for the title column (set when user resizes any column), use it
            if let storedWidth = columnWidths["title"] {
                return max(column.minWidth, storedWidth)
            }
            // Otherwise, title is flexible and fills remaining space
            let fixedWidth = columns.filter { $0.id != "title" }.reduce(0) {
                $0 + (columnWidths[$1.id] ?? $1.minWidth)
            }
            return max(column.minWidth, availableWidth - fixedWidth - 8)
        }
        return columnWidths[column.id] ?? column.minWidth
    }
    
    private func totalColumnsWidth(columns: [ModernBrowserColumn]) -> CGFloat {
        var total: CGFloat = 8
        for column in columns {
            total += column.id == "title" ? column.minWidth : (columnWidths[column.id] ?? column.minWidth)
        }
        return total
    }
    
    private func saveColumnWidths() {
        UserDefaults.standard.set(columnWidths, forKey: "BrowserColumnWidths")
    }
    
    private func loadColumnWidths() {
        if let saved = UserDefaults.standard.dictionary(forKey: "BrowserColumnWidths") as? [String: CGFloat] {
            columnWidths = saved
        }
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
            visibleTrackColumnIds = saved
        }
        if let saved = UserDefaults.standard.stringArray(forKey: "BrowserVisibleAlbumColumns") {
            visibleAlbumColumnIds = saved
        }
        if let saved = UserDefaults.standard.stringArray(forKey: "BrowserVisibleArtistColumns") {
            visibleArtistColumnIds = saved
        }
    }
    
    /// Returns the currently visible columns based on what type of items are displayed
    private func currentVisibleColumns() -> [ModernBrowserColumn] {
        if displayItems.contains(where: {
            switch $0.type { case .track, .subsonicTrack, .localTrack: return true; default: return false }
        }) {
            return ModernBrowserColumn.allTrackColumns.filter { visibleTrackColumnIds.contains($0.id) }
                .sorted { visibleTrackColumnIds.firstIndex(of: $0.id)! < visibleTrackColumnIds.firstIndex(of: $1.id)! }
        }
        if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum: return true; default: return false }
        }) {
            return ModernBrowserColumn.allAlbumColumns.filter { visibleAlbumColumnIds.contains($0.id) }
                .sorted { visibleAlbumColumnIds.firstIndex(of: $0.id)! < visibleAlbumColumnIds.firstIndex(of: $1.id)! }
        }
        return ModernBrowserColumn.allArtistColumns.filter { visibleArtistColumnIds.contains($0.id) }
            .sorted { visibleArtistColumnIds.firstIndex(of: $0.id)! < visibleArtistColumnIds.firstIndex(of: $1.id)! }
    }
    
    /// Returns all possible columns for the given column category (for the right-click menu)
    private func allColumnsForCurrentView() -> [ModernBrowserColumn] {
        if displayItems.contains(where: {
            switch $0.type { case .track, .subsonicTrack, .localTrack: return true; default: return false }
        }) { return ModernBrowserColumn.allTrackColumns }
        if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum: return true; default: return false }
        }) { return ModernBrowserColumn.allAlbumColumns }
        return ModernBrowserColumn.allArtistColumns
    }
    
    private func applyColumnSort(collapseExpanded: Bool = false) {
        guard let sortColumnId = columnSortId, !displayItems.isEmpty else {
            needsDisplay = true
            return
        }
        
        if collapseExpanded {
            let hadExpanded = !expandedArtists.isEmpty || !expandedAlbums.isEmpty ||
                              !expandedArtistNames.isEmpty ||
                              !expandedLocalArtists.isEmpty || !expandedLocalAlbums.isEmpty ||
                              !expandedSubsonicArtists.isEmpty || !expandedSubsonicAlbums.isEmpty ||
                              !expandedSubsonicPlaylists.isEmpty || !expandedPlexPlaylists.isEmpty ||
                              !expandedShows.isEmpty || !expandedSeasons.isEmpty
            if hadExpanded {
                expandedArtists.removeAll(); expandedAlbums.removeAll(); expandedArtistNames.removeAll()
                expandedLocalArtists.removeAll(); expandedLocalAlbums.removeAll()
                expandedSubsonicArtists.removeAll(); expandedSubsonicAlbums.removeAll()
                expandedSubsonicPlaylists.removeAll(); expandedPlexPlaylists.removeAll()
                expandedShows.removeAll(); expandedSeasons.removeAll()
                displayItems = displayItems.filter { $0.indentLevel == 0 }
            }
        }
        
        guard let sortColumn = ModernBrowserColumn.findColumn(id: sortColumnId) else {
            needsDisplay = true; return
        }
        
        let hasNestedItems = displayItems.contains { $0.indentLevel > 0 }
        if hasNestedItems { needsDisplay = true; return }
        
        var sortableIndices: [Int] = []
        var sortableItems: [ModernDisplayItem] = []
        
        for (index, item) in displayItems.enumerated() {
            if columnsForItem(item) != nil && item.indentLevel == 0 {
                sortableIndices.append(index)
                sortableItems.append(item)
            }
        }
        
        guard !sortableItems.isEmpty else { needsDisplay = true; return }
        
        let ascending = columnSortAscending
        sortableItems.sort { a, b in
            // Date columns: sort by raw date, not formatted string
            if sortColumn.id == "dateAdded" || sortColumn.id == "lastPlayed" {
                let aDate = a.columnDateValue(for: sortColumn) ?? .distantPast
                let bDate = b.columnDateValue(for: sortColumn) ?? .distantPast
                return ascending ? aDate < bDate : aDate > bDate
            }
            
            let aVal = a.columnValue(for: sortColumn)
            let bVal = b.columnValue(for: sortColumn)
            
            if sortColumn.id == "trackNum" || sortColumn.id == "year" || sortColumn.id == "plays" ||
               sortColumn.id == "albums" || sortColumn.id == "discNum" || sortColumn.id == "channels" {
                let aNum = Int(aVal.components(separatedBy: "-").last ?? aVal) ?? 0
                let bNum = Int(bVal.components(separatedBy: "-").last ?? bVal) ?? 0
                return ascending ? aNum < bNum : aNum > bNum
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
            let result = aVal.localizedCaseInsensitiveCompare(bVal)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        
        for (sortedIndex, originalIndex) in sortableIndices.enumerated() {
            displayItems[originalIndex] = sortableItems[sortedIndex]
        }
        needsDisplay = true
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
        if WindowManager.shared.hideTitleBars {
            return point.y >= bounds.height - 6 * m  // invisible drag zone
        }
        return point.y > bounds.height - Layout.titleBarHeight &&
               point.x < bounds.width - 30 * m
    }
    
    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        let m = ModernSkinElements.sizeMultiplier
        if WindowManager.shared.hideTitleBars { return false }
        let closeRect = NSRect(x: bounds.width - 20 * m, y: bounds.height - Layout.titleBarHeight, width: 20 * m, height: Layout.titleBarHeight)
        return closeRect.contains(point)
    }
    
    private func hitTestShadeButton(at point: NSPoint) -> Bool {
        let m = ModernSkinElements.sizeMultiplier
        if WindowManager.shared.hideTitleBars { return false }
        let shadeRect = NSRect(x: bounds.width - 31 * m, y: bounds.height - Layout.titleBarHeight, width: 11 * m, height: Layout.titleBarHeight)
        return shadeRect.contains(point)
    }
    
    private func hitTestServerBar(at point: NSPoint) -> Bool {
        let serverBarY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight
        return point.y >= serverBarY && point.y < bounds.height - Layout.titleBarHeight
    }
    
    private func hitTestTabBar(at point: NSPoint) -> Int? {
        let tabBarTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight
        let tabBarBottomY = tabBarTopY - Layout.tabBarHeight
        guard point.y >= tabBarBottomY && point.y < tabBarTopY else { return nil }
        
        let skin = currentSkin()
        let font = skin.sideWindowFont(size: 11)
        let sortText = "Sort"
        let sortAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let sortWidth = sortText.size(withAttributes: sortAttrs).width + 16 * ModernSkinElements.sizeMultiplier
        
        let tabsWidth = bounds.width - Layout.borderWidth * 2 - sortWidth
        let tabWidth = tabsWidth / CGFloat(ModernBrowseMode.allCases.count)
        let relativeX = point.x - Layout.borderWidth
        
        if relativeX >= 0 && relativeX < tabsWidth {
            return Int(relativeX / tabWidth)
        }
        return nil
    }
    
    private func hitTestSortIndicator(at point: NSPoint) -> Bool {
        let tabBarTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight
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
        let tabBarBottomY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
        let searchBarBottomY = tabBarBottomY - Layout.searchBarHeight
        return point.y >= searchBarBottomY && point.y < tabBarBottomY
    }
    
    private func hitTestListArea(at point: NSPoint) -> Int? {
        var contentTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
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
    
    private func hitTestAlphabetIndex(at point: NSPoint) -> Bool {
        var contentTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let listHeight = contentTopY - Layout.statusBarHeight
        let alphabetX = bounds.width - Layout.borderWidth - Layout.scrollbarWidth - Layout.alphabetWidth
        return point.x >= alphabetX && point.x < alphabetX + Layout.alphabetWidth &&
               point.y >= Layout.statusBarHeight && point.y < Layout.statusBarHeight + listHeight
    }
    
    private func hitTestContentArea(at point: NSPoint) -> Bool {
        let contentTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight
        let contentBottomY = Layout.statusBarHeight
        let contentRect = NSRect(x: Layout.borderWidth, y: contentBottomY,
                                 width: bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth,
                                 height: contentTopY - contentBottomY)
        return contentRect.contains(point)
    }
    
    private func hitTestColumnResize(at point: NSPoint) -> String? {
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        guard hasColumns else { return nil }
        
        var headerTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { headerTopY -= Layout.searchBarHeight }
        let headerBottomY = headerTopY - columnHeaderHeight
        
        guard point.y >= headerBottomY && point.y < headerTopY else { return nil }
        
        let columns = currentVisibleColumns()
        guard columns.count > 1 else { return nil }
        
        let headerWidth = bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - Layout.alphabetWidth
        let threshold: CGFloat = 4 * ModernSkinElements.sizeMultiplier
        var x = Layout.borderWidth + 4 - horizontalScrollOffset
        
        for (index, column) in columns.enumerated() {
            let width = widthForColumn(column, availableWidth: headerWidth, columns: columns)
            let edgeX = x + width
            
            // Don't allow resizing the last column (it fills remaining space or is fixed-end)
            // Allow resizing any column except title (title is flexible)
            if index < columns.count - 1 && column.id != "title" {
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
        
        var headerTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { headerTopY -= Layout.searchBarHeight }
        let headerBottomY = headerTopY - columnHeaderHeight
        
        guard point.y >= headerBottomY && point.y < headerTopY else { return nil }
        
        let columns = currentVisibleColumns()
        
        let headerWidth = bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - Layout.alphabetWidth
        var x = Layout.borderWidth + 4 - horizontalScrollOffset
        for column in columns {
            let width = widthForColumn(column, availableWidth: headerWidth, columns: columns)
            if point.x >= x && point.x < x + width { return column.id }
            x += width
        }
        return nil
    }
    
    /// Returns true if the point is within the column header area (for right-click detection)
    private func hitTestColumnHeaderArea(at point: NSPoint) -> Bool {
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        guard hasColumns else { return false }
        
        var headerTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
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
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Double-click title bar for shade
        if event.clickCount == 2 && hitTestTitleBar(at: point) {
            toggleShadeMode(); return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: point, event: event); return
        }
        
        // Window buttons (always check first)
        if hitTestCloseButton(at: point) { pressedButton = .close; needsDisplay = true; return }
        if hitTestShadeButton(at: point) { pressedButton = .shade; needsDisplay = true; return }
        
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
        if let tabIndex = hitTestTabBar(at: point) {
            if let newMode = ModernBrowseMode(rawValue: tabIndex) {
                browseMode = newMode; selectedIndices.removeAll(); scrollOffset = 0
                loadDataForCurrentMode(); window?.makeFirstResponder(self)
            }
            return
        }
        
        // Search bar
        if hitTestSearchBar(at: point) { window?.makeFirstResponder(self); return }
        
        // Art-only mode: visualization click cycles effects, normal click cycles artwork
        // (checked AFTER server bar, tabs, and search bar so those still work)
        if isArtOnlyMode && isVisualizingArt && hitTestContentArea(at: point) {
            nextVisEffect(); return
        }
        if isArtOnlyMode && !isVisualizingArt && hitTestContentArea(at: point) {
            cycleToNextArtwork(); return
        }
        
        // Column resize (check before sort so edge-drag doesn't trigger sort)
        if let columnId = hitTestColumnResize(at: point) {
            resizingColumnId = columnId
            resizeStartX = point.x
            let columns = currentVisibleColumns()
            let headerWidth = bounds.width - Layout.borderWidth * 2 - Layout.scrollbarWidth - Layout.alphabetWidth
            resizeStartWidth = widthForColumn(ModernBrowserColumn.findColumn(id: columnId)!, availableWidth: headerWidth, columns: columns)
            // Freeze the title column's current width so it doesn't flex during resize
            if columnWidths["title"] == nil {
                let titleWidth = widthForColumn(.title, availableWidth: headerWidth, columns: columns)
                columnWidths["title"] = titleWidth
            }
            NSCursor.resizeLeftRight.push()
            return
        }
        
        // Column header click for sorting
        if let columnId = hitTestColumnHeader(at: point) {
            if columnSortId == columnId { columnSortAscending.toggle() }
            else { columnSortId = columnId; columnSortAscending = true }
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
        if let columnId = resizingColumnId {
            let point = convert(event.locationInWindow, from: nil)
            let deltaX = point.x - resizeStartX
            let minWidth = ModernBrowserColumn.findColumn(id: columnId)?.minWidth ?? 30
            columnWidths[columnId] = max(minWidth, resizeStartWidth + deltaX)
            needsDisplay = true; return
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
        
        if resizingColumnId != nil { resizingColumnId = nil; NSCursor.pop() }
        if isDraggingWindow { isDraggingWindow = false }
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
        } else {
            NSCursor.arrow.set()
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
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
        super.rightMouseDown(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        var contentTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let listHeight = contentTopY - Layout.statusBarHeight
        let totalHeight = CGFloat(displayItems.count) * itemHeight
        
        if totalHeight > listHeight && abs(event.deltaY) > 0 {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))
            
            let listRect = NSRect(x: 0, y: Layout.statusBarHeight, width: bounds.width, height: listHeight)
            setNeedsDisplay(listRect)
        }
    }
    
    // MARK: - Keyboard Events
    
    override func keyDown(with event: NSEvent) {
        // Rating overlay: ESC to dismiss, 1-5 to set stars
        if isRatingOverlayVisible {
            if event.keyCode == 53 { hideRatingOverlay(); return }
            // Keys 1-5 (keycodes 18-22)
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
            if event.modifierFlags.contains(.shift) {
                playNextSelected()
            } else if event.modifierFlags.contains(.option) {
                addSelectedToQueue()
            } else {
                if let index = selectedIndices.first, index < displayItems.count { handleDoubleClick(on: displayItems[index]) }
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
                    if !searchQuery.isEmpty { searchQuery.removeLast(); loadDataForCurrentMode() }
                } else if chars.rangeOfCharacter(from: .alphanumerics) != nil ||
                          chars.rangeOfCharacter(from: .whitespaces) != nil {
                    searchQuery += chars; loadDataForCurrentMode()
                }
            }
        }
    }
    
    private func ensureVisible(index: Int) {
        var contentTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let listHeight = contentTopY - Layout.statusBarHeight
        
        let itemTop = CGFloat(index) * itemHeight
        let itemBottom = itemTop + itemHeight
        
        if itemTop < scrollOffset { scrollOffset = itemTop }
        else if itemBottom > scrollOffset + listHeight { scrollOffset = itemBottom - listHeight }
    }
    
    // MARK: - Drag and Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return [] }
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
        let playlistExtensions = ["m3u", "m3u8", "pls"]
        for url in items {
            let ext = url.pathExtension.lowercased()
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue || audioExtensions.contains(ext) || playlistExtensions.contains(ext) { return .copy }
        }
        return []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return false }
        var fileURLs: [URL] = []
        var processedDirectories = false
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
        for url in items {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    MediaLibrary.shared.addWatchFolder(url); MediaLibrary.shared.scanFolder(url); processedDirectories = true
                } else if audioExtensions.contains(url.pathExtension.lowercased()) {
                    fileURLs.append(url)
                }
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
        let barRect = NSRect(x: Layout.borderWidth, y: bounds.height - Layout.titleBarHeight - Layout.serverBarHeight,
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
            if relativeX < barWidth * 0.5 { showSourceMenu(at: event) }
        case .radio:
            let radioNameWidth = "Internet Radio".size(withAttributes: fontAttrs).width
            let sourcePrefix = "Source: ".size(withAttributes: fontAttrs).width + 4 * m
            let sourceZoneEnd = sourcePrefix + radioNameWidth
            let addZoneStart = sourceZoneEnd + 28 * m
            let addZoneEnd = addZoneStart + 50 * m
            if relativeX >= addZoneStart && relativeX <= addZoneEnd { showRadioAddMenu(at: event) }
            else if relativeX < sourceZoneEnd { showSourceMenu(at: event) }
        }
    }
    
    private func handleRefreshClick() {
        if case .radio = currentSource { if browseMode == .radio { loadRadioStations() }; return }
        if browseMode == .radio { if case .plex = currentSource { loadPlexRadioStations() }; return }
        switch currentSource {
        case .local: MediaLibrary.shared.rescanWatchFolders(); loadLocalData()
        case .plex: refreshData()
        case .subsonic:
            Task { await SubsonicManager.shared.preloadLibraryContent(); await MainActor.run { self.refreshData() } }
        case .radio: break
        }
    }
    
    // MARK: - Alphabet Click
    
    private func handleAlphabetClick(at point: NSPoint) {
        var contentTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
        if browseMode == .search { contentTopY -= Layout.searchBarHeight }
        let listHeight = contentTopY - Layout.statusBarHeight
        
        // Bottom-left: # at top, Z at bottom
        let relativeFromTop = contentTopY - point.y
        let letterCount = CGFloat(alphabetLetters.count)
        let letterHeight = listHeight / letterCount
        let letterIndex = Int(relativeFromTop / letterHeight)
        
        guard letterIndex >= 0 && letterIndex < alphabetLetters.count else { return }
        scrollToLetter(alphabetLetters[letterIndex])
    }
    
    private func sortLetter(for title: String) -> String {
        var sortTitle = title.uppercased()
        for prefix in ["THE ", "AN ", "A "] {
            if sortTitle.hasPrefix(prefix) { sortTitle = String(sortTitle.dropFirst(prefix.count)); break }
        }
        guard let firstChar = sortTitle.first else { return "#" }
        return firstChar.isLetter ? String(firstChar) : "#"
    }
    
    private func scrollToLetter(_ letter: String) {
        for (index, item) in displayItems.enumerated() {
            if sortLetter(for: item.title) == letter {
                var contentTopY = bounds.height - Layout.titleBarHeight - Layout.serverBarHeight - Layout.tabBarHeight
                if browseMode == .search { contentTopY -= Layout.searchBarHeight }
                let listHeight = contentTopY - Layout.statusBarHeight
                let maxScroll = max(0, CGFloat(displayItems.count) * itemHeight - listHeight)
                scrollOffset = min(maxScroll, CGFloat(index) * itemHeight)
                selectedIndices = [index]; needsDisplay = true; return
            }
        }
    }
    
    // MARK: - List Click
    
    private func handleListClick(at index: Int, event: NSEvent, point: NSPoint) {
        let item = displayItems[index]
        
        if item.hasChildren {
            let indent = CGFloat(item.indentLevel) * 16
            if point.x < Layout.borderWidth + indent + 20 { toggleExpand(item); return }
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
            loadArtworkForSelection()
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
        let radioItem = NSMenuItem(title: "Internet Radio", action: #selector(selectRadioSource), keyEquivalent: "")
        radioItem.target = self; if case .radio = currentSource { radioItem.state = .on }
        menu.addItem(radioItem)
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
        let addFolderItem = NSMenuItem(title: "Add Folder...", action: #selector(addWatchFolder), keyEquivalent: "")
        addFolderItem.target = self; menu.addItem(addFolderItem)
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    private func showRadioAddMenu(at event: NSEvent) {
        let menu = NSMenu()
        let addItem = NSMenuItem(title: "Add Station...", action: #selector(showAddRadioStationDialog), keyEquivalent: "")
        addItem.target = self; menu.addItem(addItem)
        menu.addItem(NSMenuItem.separator())
        let addDefaultsItem = NSMenuItem(title: "Add Missing Defaults", action: #selector(addMissingRadioDefaults), keyEquivalent: "")
        addDefaultsItem.target = self; menu.addItem(addDefaultsItem)
        let resetItem = NSMenuItem(title: "Reset to Defaults", action: #selector(resetRadioToDefaults), keyEquivalent: "")
        resetItem.target = self; menu.addItem(resetItem)
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    private func showVisualizerMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Visualizer")
        let currentItem = NSMenuItem(title: "▶ \(currentVisEffect.rawValue)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false; menu.addItem(currentItem)
        let nextItem = NSMenuItem(title: "Next Effect →", action: #selector(menuNextEffect), keyEquivalent: "")
        nextItem.target = self; menu.addItem(nextItem)
        menu.addItem(NSMenuItem.separator())
        let offItem = NSMenuItem(title: "Turn Off", action: #selector(turnOffVisualization), keyEquivalent: "")
        offItem.target = self; menu.addItem(offItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func showArtContextMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Art")
        let visItem = NSMenuItem(title: "Enable Visualization", action: #selector(enableArtVisualization), keyEquivalent: "")
        visItem.target = self; menu.addItem(visItem)
        
        // Rate submenu (when a rateable track is playing)
        if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
           currentTrack.plexRatingKey != nil || currentTrack.subsonicId != nil || currentTrack.url.isFileURL {
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
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        let allColumns = allColumnsForCurrentView()
        let visibleIds = currentVisibleColumnIds()
        
        for column in allColumns {
            let item = NSMenuItem(title: column.title, action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.id
            item.state = visibleIds.contains(column.id) ? .on : .off
            // Title column is always visible
            if column.id == "title" { item.isEnabled = false }
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        let resetItem = NSMenuItem(title: "Reset to Default", action: #selector(resetColumnsToDefault), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func currentVisibleColumnIds() -> [String] {
        if displayItems.contains(where: {
            switch $0.type { case .track, .subsonicTrack, .localTrack: return true; default: return false }
        }) { return visibleTrackColumnIds }
        if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum: return true; default: return false }
        }) { return visibleAlbumColumnIds }
        return visibleArtistColumnIds
    }
    
    @objc private func toggleColumnVisibility(_ sender: NSMenuItem) {
        guard let columnId = sender.representedObject as? String else { return }
        
        // Determine which column ID list to modify
        if displayItems.contains(where: {
            switch $0.type { case .track, .subsonicTrack, .localTrack: return true; default: return false }
        }) {
            if let index = visibleTrackColumnIds.firstIndex(of: columnId) {
                visibleTrackColumnIds.remove(at: index)
                // Clear sort if hiding the sorted column
                if columnSortId == columnId { columnSortId = nil }
            } else {
                visibleTrackColumnIds.append(columnId)
            }
        } else if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum: return true; default: return false }
        }) {
            if let index = visibleAlbumColumnIds.firstIndex(of: columnId) {
                visibleAlbumColumnIds.remove(at: index)
                if columnSortId == columnId { columnSortId = nil }
            } else {
                visibleAlbumColumnIds.append(columnId)
            }
        } else {
            if let index = visibleArtistColumnIds.firstIndex(of: columnId) {
                visibleArtistColumnIds.remove(at: index)
                if columnSortId == columnId { columnSortId = nil }
            } else {
                visibleArtistColumnIds.append(columnId)
            }
        }
        needsDisplay = true
    }
    
    @objc private func resetColumnsToDefault() {
        visibleTrackColumnIds = ModernBrowserColumn.defaultTrackColumnIds
        visibleAlbumColumnIds = ModernBrowserColumn.defaultAlbumColumnIds
        visibleArtistColumnIds = ModernBrowserColumn.defaultArtistColumnIds
        columnWidths.removeAll()
        needsDisplay = true
    }
    
    private func showContextMenu(for item: ModernDisplayItem, at event: NSEvent) {
        let menu = NSMenu()
        switch item.type {
        case .track(let track):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlay(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = item; menu.addItem(playItem)
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
            let playNextItem = NSMenuItem(title: "Play Artist Next", action: #selector(contextMenuPlayArtistNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = artist; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Artist to Queue", action: #selector(contextMenuAddArtistToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = artist; menu.addItem(queueItem)
            let expandItem = NSMenuItem(title: expandedArtists.contains(artist.id) ? "Collapse" : "Expand",
                                         action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self; expandItem.representedObject = item; menu.addItem(expandItem)
        case .localTrack(let track):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayLocalTrack(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = track; menu.addItem(playItem)
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
            let tagsItem = NSMenuItem(title: "See Tags", action: #selector(contextMenuShowTags(_:)), keyEquivalent: "")
            tagsItem.target = self; tagsItem.representedObject = track; menu.addItem(tagsItem)
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextMenuShowInFinder(_:)), keyEquivalent: "")
            finderItem.target = self; finderItem.representedObject = track; menu.addItem(finderItem)
        case .localAlbum(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayLocalAlbum(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = album; menu.addItem(playItem)
            let playNextItem = NSMenuItem(title: "Play Album Next", action: #selector(contextMenuPlayLocalAlbumNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = album; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Album to Queue", action: #selector(contextMenuAddLocalAlbumToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = album; menu.addItem(queueItem)
        case .localArtist(let artist):
            let playItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlayLocalArtist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = artist; menu.addItem(playItem)
            let playNextItem = NSMenuItem(title: "Play Artist Next", action: #selector(contextMenuPlayLocalArtistNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = artist; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Artist to Queue", action: #selector(contextMenuAddLocalArtistToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = artist; menu.addItem(queueItem)
        case .subsonicTrack(let song):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlaySubsonicSong(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = song; menu.addItem(playItem)
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
            let playNextItem = NSMenuItem(title: "Play Artist Next", action: #selector(contextMenuPlaySubsonicArtistNext(_:)), keyEquivalent: "")
            playNextItem.target = self; playNextItem.representedObject = artist; menu.addItem(playNextItem)
            let queueItem = NSMenuItem(title: "Add Artist to Queue", action: #selector(contextMenuAddSubsonicArtistToQueue(_:)), keyEquivalent: "")
            queueItem.target = self; queueItem.representedObject = artist; menu.addItem(queueItem)
        case .radioStation(let station):
            let playItem = NSMenuItem(title: "Play Station", action: #selector(contextMenuPlayRadioStation(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = station; menu.addItem(playItem)
            menu.addItem(NSMenuItem.separator())
            let editItem = NSMenuItem(title: "Edit Station...", action: #selector(contextMenuEditRadioStation(_:)), keyEquivalent: "")
            editItem.target = self; editItem.representedObject = station; menu.addItem(editItem)
            let deleteItem = NSMenuItem(title: "Delete Station", action: #selector(contextMenuDeleteRadioStation(_:)), keyEquivalent: "")
            deleteItem.target = self; deleteItem.representedObject = station; menu.addItem(deleteItem)
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
        case .subsonicPlaylist(let playlist):
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlaySubsonicPlaylist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = playlist; menu.addItem(playItem)
        case .plexPlaylist(let playlist):
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlayPlexPlaylist(_:)), keyEquivalent: "")
            playItem.target = self; playItem.representedObject = playlist; menu.addItem(playItem)
        case .header: return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    // MARK: - @objc Menu Actions
    
    @objc private func selectLocalSource() { currentSource = .local }
    @objc private func selectRadioSource() { currentSource = .radio }
    @objc private func selectPlexServer(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        currentSource = .plex(serverId: serverId)
        if let server = PlexManager.shared.servers.first(where: { $0.id == serverId }) {
            Task { @MainActor in
                do { try await PlexManager.shared.connect(to: server); reloadData() }
                catch { errorMessage = error.localizedDescription; needsDisplay = true }
            }
        }
    }
    @objc private func selectSubsonicServer(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        currentSource = .subsonic(serverId: serverId)
        if let server = SubsonicManager.shared.servers.first(where: { $0.id == serverId }) {
            Task { @MainActor in
                do { try await SubsonicManager.shared.connect(to: server); reloadData() }
                catch { errorMessage = error.localizedDescription; needsDisplay = true }
            }
        }
    }
    @objc private func linkPlexAccount() { controller?.showLinkSheet() }
    @objc private func selectSortOption(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? ModernBrowserSortOption else { return }
        currentSort = option
    }
    @objc private func selectLibrary(_ sender: NSMenuItem) {
        guard let library = sender.representedObject as? PlexLibrary else { return }
        PlexManager.shared.selectLibrary(library); clearAllCachedData(); reloadData()
    }
    @objc private func addFiles() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]; panel.message = "Select audio files"
        if panel.runModal() == .OK { MediaLibrary.shared.addTracks(urls: panel.urls) }
    }
    @objc private func addWatchFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Select a folder to add to your library"
        if panel.runModal() == .OK, let url = panel.url {
            MediaLibrary.shared.addWatchFolder(url); MediaLibrary.shared.scanFolder(url)
        }
    }
    @objc private func showAddRadioStationDialog() {
        activeRadioStationSheet = AddRadioStationSheet(station: nil)
        activeRadioStationSheet?.showDialog { [weak self] station in
            self?.activeRadioStationSheet = nil
            if let newStation = station {
                RadioManager.shared.addStation(newStation)
                if case .radio = self?.currentSource { self?.loadRadioStations() }
                else { self?.currentSource = .radio }
            }
        }
    }
    @objc private func addMissingRadioDefaults() { RadioManager.shared.addMissingDefaults(); if case .radio = currentSource { loadRadioStations() } }
    @objc private func resetRadioToDefaults() {
        let alert = NSAlert(); alert.messageText = "Reset to Defaults"; alert.informativeText = "Replace all stations with defaults?"
        alert.addButton(withTitle: "Reset"); alert.addButton(withTitle: "Cancel"); alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { RadioManager.shared.resetToDefaults(); if case .radio = currentSource { loadRadioStations() } }
    }
    @objc private func menuNextEffect() { nextVisEffect() }
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
    @objc private func contextMenuShowInFinder(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
    }
    @objc private func contextMenuPlayLocalAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }; playLocalAlbum(album)
    }
    @objc private func contextMenuPlayLocalArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }; playLocalArtist(artist)
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
            if let u = updated { RadioManager.shared.updateStation(u); self?.loadRadioStations() }
        }
    }
    @objc private func contextMenuDeleteRadioStation(_ sender: NSMenuItem) {
        guard let station = sender.representedObject as? RadioStation else { return }
        let alert = NSAlert(); alert.messageText = "Delete '\(station.name)'?"; alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { RadioManager.shared.removeStation(station); loadRadioStations() }
    }
    @objc private func contextMenuPlayPlexRadioStation(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ModernDisplayItem,
              case .plexRadioStation(let radioType) = item.type else { return }
        playPlexRadioStation(radioType)
    }
    @objc private func contextMenuPlayMovie(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? PlexMovie else { return }; playMovie(movie)
    }
    @objc private func contextMenuPlayEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? PlexEpisode else { return }; playEpisode(episode)
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
        let tracks = album.tracks.map { $0.toTrack() }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent(tracks)
    }
    @objc private func contextMenuAddLocalAlbumToQueue(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        let tracks = album.tracks.map { $0.toTrack() }
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
                let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [PlexTrack] = []
                for album in albums {
                    let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                    allTracks.append(contentsOf: tracks)
                }
                let converted = PlexManager.shared.convertToTracks(allTracks)
                WindowManager.shared.audioEngine.insertTracksAfterCurrent(converted)
            } catch { NSLog("Failed to play artist next: %@", error.localizedDescription) }
        }
    }
    @objc private func contextMenuAddArtistToQueue(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? PlexArtist else { return }
        Task { @MainActor in
            do {
                let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [PlexTrack] = []
                for album in albums {
                    let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                    allTracks.append(contentsOf: tracks)
                }
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
        for album in artist.albums {
            allTracks.append(contentsOf: album.tracks.map { $0.toTrack() })
        }
        WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks)
    }
    @objc private func contextMenuAddLocalArtistToQueue(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        var allTracks: [Track] = []
        for album in artist.albums {
            allTracks.append(contentsOf: album.tracks.map { $0.toTrack() })
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
    
    // MARK: - Keyboard Shortcut Helpers
    
    private func playNextSelected() {
        guard let index = selectedIndices.first, index < displayItems.count else { return }
        let item = displayItems[index]
        switch item.type {
        case .track(let track):
            if let t = PlexManager.shared.convertToTrack(track) {
                WindowManager.shared.audioEngine.insertTracksAfterCurrent([t])
            }
        case .localTrack(let track):
            WindowManager.shared.audioEngine.insertTracksAfterCurrent([track.toTrack()])
        case .subsonicTrack(let song):
            if let track = SubsonicManager.shared.convertToTrack(song) {
                WindowManager.shared.audioEngine.insertTracksAfterCurrent([track])
            }
        case .album(let album):
            Task { @MainActor in
                if let tracks = try? await PlexManager.shared.fetchTracks(forAlbum: album) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(PlexManager.shared.convertToTracks(tracks))
                }
            }
        case .localAlbum(let album):
            WindowManager.shared.audioEngine.insertTracksAfterCurrent(album.tracks.map { $0.toTrack() })
        case .subsonicAlbum(let album):
            Task { @MainActor in
                if let songs = try? await SubsonicManager.shared.fetchSongs(forAlbum: album) {
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                }
            }
        case .artist(let artist):
            Task { @MainActor in
                if let albums = try? await PlexManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [PlexTrack] = []
                    for album in albums {
                        if let tracks = try? await PlexManager.shared.fetchTracks(forAlbum: album) {
                            allTracks.append(contentsOf: tracks)
                        }
                    }
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(PlexManager.shared.convertToTracks(allTracks))
                }
            }
        case .localArtist(let artist):
            var allTracks: [Track] = []
            for album in artist.albums { allTracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
            WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks)
        case .subsonicArtist(let artist):
            Task { @MainActor in
                if let albums = try? await SubsonicManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [Track] = []
                    for album in albums {
                        if let songs = try? await SubsonicManager.shared.fetchSongs(forAlbum: album) {
                            allTracks.append(contentsOf: songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                        }
                    }
                    WindowManager.shared.audioEngine.insertTracksAfterCurrent(allTracks)
                }
            }
        default: break
        }
    }
    
    private func addSelectedToQueue() {
        guard let index = selectedIndices.first, index < displayItems.count else { return }
        let item = displayItems[index]
        let engine = WindowManager.shared.audioEngine
        let wasEmpty = engine.playlist.isEmpty
        
        switch item.type {
        case .track(let track):
            if let t = PlexManager.shared.convertToTrack(track) {
                engine.appendTracks([t])
                if wasEmpty { engine.playTrack(at: 0) }
            }
        case .localTrack(let track):
            engine.appendTracks([track.toTrack()])
            if wasEmpty { engine.playTrack(at: 0) }
        case .subsonicTrack(let song):
            if let track = SubsonicManager.shared.convertToTrack(song) {
                engine.appendTracks([track])
                if wasEmpty { engine.playTrack(at: 0) }
            }
        case .album(let album):
            Task { @MainActor in
                if let tracks = try? await PlexManager.shared.fetchTracks(forAlbum: album) {
                    let converted = PlexManager.shared.convertToTracks(tracks)
                    let wasEmpty = engine.playlist.isEmpty
                    engine.appendTracks(converted)
                    if wasEmpty { engine.playTrack(at: 0) }
                }
            }
        case .localAlbum(let album):
            let tracks = album.tracks.map { $0.toTrack() }
            engine.appendTracks(tracks)
            if wasEmpty { engine.playTrack(at: 0) }
        case .subsonicAlbum(let album):
            Task { @MainActor in
                if let songs = try? await SubsonicManager.shared.fetchSongs(forAlbum: album) {
                    let tracks = songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                    let wasEmpty = engine.playlist.isEmpty
                    engine.appendTracks(tracks)
                    if wasEmpty { engine.playTrack(at: 0) }
                }
            }
        case .artist(let artist):
            Task { @MainActor in
                if let albums = try? await PlexManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [PlexTrack] = []
                    for album in albums {
                        if let tracks = try? await PlexManager.shared.fetchTracks(forAlbum: album) {
                            allTracks.append(contentsOf: tracks)
                        }
                    }
                    let converted = PlexManager.shared.convertToTracks(allTracks)
                    let wasEmpty = engine.playlist.isEmpty
                    engine.appendTracks(converted)
                    if wasEmpty { engine.playTrack(at: 0) }
                }
            }
        case .localArtist(let artist):
            var allTracks: [Track] = []
            for album in artist.albums { allTracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
            engine.appendTracks(allTracks)
            if wasEmpty { engine.playTrack(at: 0) }
        case .subsonicArtist(let artist):
            Task { @MainActor in
                if let albums = try? await SubsonicManager.shared.fetchAlbums(forArtist: artist) {
                    var allTracks: [Track] = []
                    for album in albums {
                        if let songs = try? await SubsonicManager.shared.fetchSongs(forAlbum: album) {
                            allTracks.append(contentsOf: songs.compactMap { SubsonicManager.shared.convertToTrack($0) })
                        }
                    }
                    let wasEmpty = engine.playlist.isEmpty
                    engine.appendTracks(allTracks)
                    if wasEmpty { engine.playTrack(at: 0) }
                }
            }
        default: break
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func modernSkinDidChange() {
        let skin = currentSkin()
        renderer = ModernSkinRenderer(skin: skin)
        needsDisplay = true
    }
    
    @objc private func doubleSizeChanged() {
        modernSkinDidChange()
    }
    
    func skinDidChange() { modernSkinDidChange() }
    
    func setShadeMode(_ enabled: Bool) { isShadeMode = enabled; needsDisplay = true }
    
    private func toggleShadeMode() { isShadeMode.toggle(); controller?.setShadeMode(isShadeMode) }
    
    @objc private func plexStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            if case .connecting = PlexManager.shared.connectionState {
                self?.isLoading = true; self?.errorMessage = nil; self?.needsDisplay = true; return
            }
            self?.reloadData()
        }
    }
    
    @objc private func plexServerDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if case .connecting = PlexManager.shared.connectionState { self.needsDisplay = true; return }
            
            if let pending = self.pendingSourceRestore {
                self.pendingSourceRestore = nil
                switch pending {
                case .plex(let serverId):
                    if PlexManager.shared.servers.contains(where: { $0.id == serverId }) { self.currentSource = pending; return }
                    else if let first = PlexManager.shared.servers.first { self.currentSource = .plex(serverId: first.id); return }
                case .subsonic(let serverId):
                    if SubsonicManager.shared.servers.contains(where: { $0.id == serverId }) { self.currentSource = pending; return }
                    else if let first = SubsonicManager.shared.servers.first { self.currentSource = .subsonic(serverId: first.id); return }
                case .local: break
                case .radio: self.currentSource = .radio; return
                }
            }
            self.clearAllCachedData(); self.reloadData()
        }
    }
    
    @objc private func plexContentDidPreload() { reloadData() }
    
    @objc private func mediaLibraryDidChange() {
        guard case .local = currentSource, browseMode != .radio else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.browseMode != .radio else { return }
            self.loadLocalData(); self.needsDisplay = true
        }
    }
    
    @objc private func radioStationsDidChange() {
        guard case .radio = currentSource else { return }
        DispatchQueue.main.async { [weak self] in self?.loadRadioStations(); self?.needsDisplay = true }
    }
    
    @objc private func trackDidChange(_ notification: Notification) {
        if isArtOnlyMode {
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
        let track = notification.userInfo?["track"] as? Track
        loadArtwork(for: track)
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
    
    private func onSourceChanged() {
        clearAllCachedData(); clearLocalCachedData()
        displayItems.removeAll(); selectedIndices.removeAll()
        scrollOffset = 0; errorMessage = nil; isLoading = false; stopLoadingAnimation()
        if case .radio = currentSource { browseMode = .radio }
        else if browseMode == .radio && !currentSource.isPlex { browseMode = .artists }
        reloadData()
    }
    
    private func clearLocalCachedData() {
        cachedLocalArtists = []; cachedLocalAlbums = []; cachedLocalTracks = []
        expandedLocalArtists = []; expandedLocalAlbums = []
    }
    
    private func clearAllCachedData() {
        cachedArtists = []; cachedAlbums = []; cachedTracks = []
        artistAlbums = [:]; albumTracks = [:]; artistAlbumCounts = [:]
        expandedArtists = []; expandedAlbums = []
        cachedMovies = []; cachedShows = []; showSeasons = [:]; seasonEpisodes = [:]
        expandedShows = []; expandedSeasons = []
        cachedPlexPlaylists = []; plexPlaylistTracks = [:]; expandedPlexPlaylists = []
        searchResults = nil
    }
    
    // MARK: - Loading Animation
    
    private func startLoadingAnimation() {
        guard loadingAnimationTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadingAnimationFrame += 1
            if self.isLoading { self.needsDisplay = true } else { self.stopLoadingAnimation() }
        }
        RunLoop.main.add(timer, forMode: .common); loadingAnimationTimer = timer
    }
    
    private func stopLoadingAnimation() {
        loadingAnimationTimer?.invalidate(); loadingAnimationTimer = nil; loadingAnimationFrame = 0
    }
    
    // MARK: - Server Name Scroll
    
    private func startServerNameScroll() {
        guard serverScrollTimer == nil else { return }
        serverScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.067, repeats: true) { [weak self] _ in
            // Scrolling handled in draw
        }
    }
    
    private func stopServerNameScroll() {
        serverScrollTimer?.invalidate(); serverScrollTimer = nil
        serverNameScrollOffset = 0; libraryNameScrollOffset = 0
    }
    
    // MARK: - Visualizer Timer
    
    private func startVisualizerTimer() {
        visualizerTime = 0; silenceFrames = 0; visualizerTimer?.invalidate()
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
              currentTrack.plexRatingKey != nil || currentTrack.subsonicId != nil || currentTrack.url.isFileURL else { return }
        ratingOverlay.frame = bounds; ratingOverlay.setRating(currentTrackRating ?? 0)
        ratingOverlay.isHidden = false; isRatingOverlayVisible = true; needsDisplay = true
    }
    
    private func hideRatingOverlay() {
        ratingOverlay.isHidden = true; isRatingOverlayVisible = false
        ratingSubmitTask?.cancel(); ratingSubmitTask = nil; needsDisplay = true
    }
    
    private func submitRating(_ rating: Int) {
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack else { return }
        currentTrackRating = rating; needsDisplay = true; ratingSubmitTask?.cancel()
        ratingSubmitTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
                
                if let ratingKey = currentTrack.plexRatingKey {
                    // Plex: rating is already 0-10 scale
                    try await PlexManager.shared.serverClient?.rateItem(ratingKey: ratingKey, rating: rating)
                } else if let subsonicId = currentTrack.subsonicId {
                    // Subsonic: convert 0-10 to 0-5
                    let subsonicRating = rating / 2
                    try await SubsonicManager.shared.setRating(songId: subsonicId, rating: subsonicRating)
                } else if currentTrack.url.isFileURL {
                    // Local file: store 0-10 scale
                    if let libraryTrack = MediaLibrary.shared.findTrack(byURL: currentTrack.url) {
                        MediaLibrary.shared.setRating(for: libraryTrack.id, rating: rating > 0 ? rating : nil)
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
    
    /// Build rate submenu for the currently playing track (art mode overlay)
    private func buildRateSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Rate")
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = NSMenuItem(title: label, action: #selector(contextMenuRateCurrentTrack(_:)), keyEquivalent: "")
            item.target = self; item.tag = stars * 2  // 0-10 scale
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
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Rating", action: #selector(contextMenuRateSubsonic(_:)), keyEquivalent: "")
        clearItem.target = self; clearItem.tag = 0; clearItem.representedObject = songId
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
        needsDisplay = true
    }
    
    /// Update cached SubsonicSong rating in displayItems after a rating change
    private func updateCachedSubsonicRating(songId: String, rating: Int) {
        for (index, item) in displayItems.enumerated() {
            if case .subsonicTrack(let song) = item.type, song.id == songId {
                let updatedSong = SubsonicSong(
                    id: song.id, parent: song.parent, title: song.title,
                    album: song.album, artist: song.artist, albumId: song.albumId,
                    artistId: song.artistId, track: song.track, year: song.year,
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
    
    // MARK: - Artwork Loading
    
    private func loadArtwork(for track: Track?) {
        artworkLoadTask?.cancel(); artworkLoadTask = nil
        guard let track = track else { artworkTrackId = nil; return }
        guard track.id != artworkTrackId else { return }
        artworkLoadTask = Task { [weak self] in
            guard let self = self else { return }
            var image: NSImage?
            if let plexRatingKey = track.plexRatingKey {
                image = await self.loadPlexArtwork(ratingKey: plexRatingKey, thumbPath: track.artworkThumb)
            } else if let subsonicId = track.subsonicId {
                image = await self.loadSubsonicArtwork(songId: subsonicId)
            } else if track.url.isFileURL {
                image = await self.loadLocalArtwork(url: track.url)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { self.currentArtwork = image; self.artworkTrackId = track.id; self.needsDisplay = true }
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
    
    private func loadAllArtworkForCurrentTrack() {
        artworkCyclingTask?.cancel(); artworkCyclingTask = nil
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack else { artworkImages = []; artworkIndex = 0; return }
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
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.artworkImages = images; self.artworkIndex = 0
                if let first = images.first { self.currentArtwork = first; self.needsDisplay = true }
            }
        }
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
                if let track = album.tracks.first {
                    image = await self.loadLocalArtwork(url: track.url)
                }
            case .localArtist(let artist):
                let artistTracks = self.cachedLocalTracks.filter { $0.artist == artist.name }
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
        if case .radio = currentSource {
            if browseMode == .radio { loadRadioStations() } else { displayItems = [] }
            needsDisplay = true; return
        }
        if browseMode == .radio {
            if case .plex = currentSource, PlexManager.shared.isLinked { loadPlexRadioStations() }
            else { displayItems = [] }
            needsDisplay = true; return
        }
        if case .local = currentSource { loadLocalData(); needsDisplay = true; return }
        if case .subsonic(let serverId) = currentSource { loadSubsonicData(serverId: serverId); return }
        guard PlexManager.shared.isLinked else { displayItems = []; stopLoadingAnimation(); needsDisplay = true; return }
        if PlexManager.shared.serverClient == nil {
            isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
            if let server = PlexManager.shared.currentServer {
                Task { @MainActor in
                    do { try await PlexManager.shared.connect(to: server); loadDataForCurrentMode() }
                    catch { isLoading = false; stopLoadingAnimation(); errorMessage = error.localizedDescription; needsDisplay = true }
                }
            }
            return
        }
        loadDataForCurrentMode()
    }
    
    func refreshData() {
        cachedArtists = []; cachedAlbums = []; cachedTracks = []; artistAlbums = [:]; albumTracks = [:]; artistAlbumCounts = [:]
        cachedMovies = []; cachedShows = []; showSeasons = [:]; seasonEpisodes = [:]
        cachedPlexPlaylists = []; plexPlaylistTracks = [:]; searchResults = nil
        expandedArtists = []; expandedAlbums = []; expandedShows = []; expandedSeasons = []; expandedPlexPlaylists = []
        selectedIndices = []; scrollOffset = 0
        isLoading = true; errorMessage = nil; displayItems = []; startLoadingAnimation(); needsDisplay = true
        PlexManager.shared.clearCachedContent()
        loadDataForCurrentMode()
    }
    
    // MARK: - Data Loading
    
    private func loadDataForCurrentMode() {
        if case .radio = currentSource { if browseMode == .radio { loadRadioStations() } else { displayItems = []; isLoading = false; needsDisplay = true }; return }
        if browseMode == .radio {
            if case .plex = currentSource, PlexManager.shared.isLinked { loadPlexRadioStations() }
            else { displayItems = []; isLoading = false; needsDisplay = true }
            return
        }
        if case .local = currentSource { loadLocalData(); return }
        if case .subsonic(let serverId) = currentSource { loadSubsonicData(serverId: serverId); return }
        
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        Task { @MainActor in
            do {
                let pm = PlexManager.shared
                switch browseMode {
                case .artists:
                    if cachedArtists.isEmpty {
                        if pm.isContentPreloaded && !pm.cachedArtists.isEmpty {
                            cachedArtists = pm.cachedArtists; cachedAlbums = pm.cachedAlbums
                        } else {
                            cachedArtists = try await pm.fetchArtists()
                            if cachedAlbums.isEmpty { cachedAlbums = try await pm.fetchAlbums(offset: 0, limit: 10000) }
                        }
                        buildArtistAlbumCounts()
                    }
                    buildArtistItems()
                case .albums:
                    if cachedAlbums.isEmpty {
                        if pm.isContentPreloaded && !pm.cachedAlbums.isEmpty { cachedAlbums = pm.cachedAlbums }
                        else { cachedAlbums = try await pm.fetchAlbums(offset: 0, limit: 500) }
                    }
                    buildAlbumItems()
                case .tracks:
                    if cachedTracks.isEmpty { cachedTracks = try await pm.fetchTracks(offset: 0, limit: 500) }
                    buildTrackItems()
                case .movies:
                    if cachedMovies.isEmpty {
                        if pm.isContentPreloaded && !pm.cachedMovies.isEmpty { cachedMovies = pm.cachedMovies }
                        else { cachedMovies = try await pm.fetchMovies(offset: 0, limit: 500) }
                    }
                    buildMovieItems()
                case .shows:
                    if cachedShows.isEmpty {
                        if pm.isContentPreloaded && !pm.cachedShows.isEmpty { cachedShows = pm.cachedShows }
                        else { cachedShows = try await pm.fetchShows(offset: 0, limit: 500) }
                    }
                    buildShowItems()
                case .plists:
                    if cachedPlexPlaylists.isEmpty {
                        if !pm.cachedPlaylists.isEmpty { cachedPlexPlaylists = pm.cachedPlaylists }
                        else { cachedPlexPlaylists = try await pm.fetchPlaylists() }
                    }
                    buildPlexPlaylistItems()
                case .search:
                    if !searchQuery.isEmpty { searchResults = try await pm.search(query: searchQuery); buildSearchItems() }
                    else { displayItems = [] }
                case .radio: loadRadioStations()
                }
                isLoading = false; stopLoadingAnimation(); errorMessage = nil
            } catch {
                isLoading = false; stopLoadingAnimation(); errorMessage = error.localizedDescription
            }
            needsDisplay = true
        }
    }
    
    // MARK: - Local Data Loading
    
    private func loadLocalData() {
        isLoading = false; errorMessage = nil; stopLoadingAnimation()
        let library = MediaLibrary.shared
        cachedLocalTracks = library.tracksSnapshot; cachedLocalArtists = library.allArtists(); cachedLocalAlbums = library.allAlbums()
        switch browseMode {
        case .artists: buildLocalArtistItems()
        case .albums: buildLocalAlbumItems()
        case .tracks: buildLocalTrackItems()
        case .search: buildLocalSearchItems()
        case .plists: displayItems = []
        case .movies, .shows: displayItems = []
        case .radio: break
        }
        needsDisplay = true
    }
    
    // MARK: - Radio Data Loading
    
    private func loadRadioStations() {
        isLoading = false; errorMessage = nil; stopLoadingAnimation()
        cachedRadioStations = RadioManager.shared.stations; buildRadioStationItems(); needsDisplay = true
    }
    
    private func loadPlexRadioStations() {
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        Task { @MainActor in
            let genres = await PlexManager.shared.getGenres()
            buildPlexRadioStationItems(genres: genres)
            isLoading = false; stopLoadingAnimation(); needsDisplay = true
        }
    }
    
    // MARK: - Subsonic Data Loading
    
    private func loadSubsonicData(serverId: String) {
        isLoading = true; errorMessage = nil; startLoadingAnimation(); needsDisplay = true
        let manager = SubsonicManager.shared
        if manager.currentServer?.id != serverId {
            if let server = manager.servers.first(where: { $0.id == serverId }) {
                Task { @MainActor in
                    do { try await manager.connect(to: server); loadSubsonicDataForCurrentMode() }
                    catch { isLoading = false; stopLoadingAnimation(); errorMessage = error.localizedDescription; needsDisplay = true }
                }
            } else { isLoading = false; stopLoadingAnimation(); errorMessage = "Server not found"; needsDisplay = true }
            return
        }
        loadSubsonicDataForCurrentMode()
    }
    
    private func loadSubsonicDataForCurrentMode() {
        let manager = SubsonicManager.shared
        subsonicLoadTask?.cancel()
        subsonicLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try Task.checkCancellation()
                switch browseMode {
                case .artists:
                    if cachedSubsonicArtists.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedArtists.isEmpty {
                            cachedSubsonicArtists = manager.cachedArtists; cachedSubsonicAlbums = manager.cachedAlbums
                        } else {
                            cachedSubsonicArtists = try await manager.fetchArtists()
                            cachedSubsonicAlbums = try await manager.fetchAlbums()
                        }
                    }
                    buildSubsonicArtistItems()
                case .albums:
                    if cachedSubsonicAlbums.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedAlbums.isEmpty { cachedSubsonicAlbums = manager.cachedAlbums }
                        else { cachedSubsonicAlbums = try await manager.fetchAlbums() }
                    }
                    buildSubsonicAlbumItems()
                case .tracks: buildSubsonicTrackItems()
                case .plists:
                    if cachedSubsonicPlaylists.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedPlaylists.isEmpty { cachedSubsonicPlaylists = manager.cachedPlaylists }
                        else { cachedSubsonicPlaylists = try await manager.fetchPlaylists() }
                    }
                    buildSubsonicPlaylistItems()
                case .search: displayItems = []
                case .movies, .shows: displayItems = []
                case .radio: break
                }
                isLoading = false; stopLoadingAnimation(); needsDisplay = true
            } catch is CancellationError { }
            catch { isLoading = false; stopLoadingAnimation(); errorMessage = error.localizedDescription; needsDisplay = true }
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
        for album in cachedAlbums {
            if let parentKey = album.parentKey, let artistId = extractArtistId(from: parentKey) {
                artistAlbumCounts[artistId, default: 0] += 1
            }
        }
    }
    
    private func buildArtistItems() {
        displayItems.removeAll()
        let sorted = sortPlexArtists(cachedArtists)
        for artist in sorted {
            let expanded = expandedArtists.contains(artist.id)
            let info: String?
            if let count = artistAlbumCounts[artist.id], count > 0 { info = "\(count) album\(count == 1 ? "" : "s")" }
            else if let albums = artistAlbums[artist.id] { info = "\(albums.count) album\(albums.count == 1 ? "" : "s")" }
            else if artist.albumCount > 0 { info = "\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")" }
            else { info = nil }
            displayItems.append(ModernDisplayItem(id: artist.id, title: artist.title, info: info, indentLevel: 0, hasChildren: true, type: .artist(artist)))
            if expanded, let albums = artistAlbums[artist.id] {
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
        displayItems = sortPlexAlbums(cachedAlbums).map {
            ModernDisplayItem(id: $0.id, title: "\($0.parentTitle ?? "Unknown") - \($0.title)", info: $0.year.map { String($0) }, indentLevel: 0, hasChildren: false, type: .album($0))
        }
    }
    
    private func buildTrackItems() {
        displayItems = sortPlexTracks(cachedTracks).map {
            ModernDisplayItem(id: $0.id, title: "\($0.grandparentTitle ?? "Unknown") - \($0.title)", info: $0.formattedDuration, indentLevel: 0, hasChildren: false, type: .track($0))
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
    
    private func buildPlexPlaylistItems() {
        displayItems.removeAll()
        let audio = cachedPlexPlaylists.filter { $0.isAudioPlaylist }
        var seen = Set<String>()
        let unique = audio.filter { let n = $0.title.lowercased(); if seen.contains(n) { return false }; seen.insert(n); return true }
        for playlist in unique.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
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
        if !results.artists.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-artists", title: "Artists (\(results.artists.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for artist in results.artists { displayItems.append(ModernDisplayItem(id: artist.id, title: artist.title, info: nil, indentLevel: 1, hasChildren: true, type: .artist(artist))) }
        }
        if !results.albums.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-albums", title: "Albums (\(results.albums.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for album in results.albums { displayItems.append(ModernDisplayItem(id: album.id, title: "\(album.parentTitle ?? "") - \(album.title)", info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .album(album))) }
        }
        if !results.tracks.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-tracks", title: "Tracks (\(results.tracks.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for track in results.tracks { displayItems.append(ModernDisplayItem(id: track.id, title: "\(track.grandparentTitle ?? "") - \(track.title)", info: track.formattedDuration, indentLevel: 1, hasChildren: false, type: .track(track))) }
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
    
    private func buildRadioStationItems() {
        displayItems = cachedRadioStations.map {
            ModernDisplayItem(id: $0.id.uuidString, title: $0.name, info: $0.genre, indentLevel: 0, hasChildren: false, type: .radioStation($0))
        }
        displayItems.sort { a, b in
            let ga = a.info ?? "", gb = b.info ?? ""
            if ga != gb { if ga.isEmpty { return false }; if gb.isEmpty { return true }; return ga.localizedCaseInsensitiveCompare(gb) == .orderedAscending }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
    
    private func buildPlexRadioStationItems(genres: [String]) {
        displayItems.removeAll()
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
        for artist in sortArtists(cachedLocalArtists) {
            let expanded = expandedLocalArtists.contains(artist.id)
            displayItems.append(ModernDisplayItem(id: "local-artist-\(artist.id)", title: artist.name, info: "\(artist.albums.count) albums", indentLevel: 0, hasChildren: true, type: .localArtist(artist)))
            if expanded {
                for album in sortAlbums(artist.albums) {
                    let albumExpanded = expandedLocalAlbums.contains(album.id)
                    displayItems.append(ModernDisplayItem(id: "local-album-\(album.id)", title: album.name, info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .localAlbum(album)))
                    if albumExpanded {
                        let sorted = album.tracks.sorted { let d0 = $0.discNumber ?? 1; let d1 = $1.discNumber ?? 1; if d0 != d1 { return d0 < d1 }; return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
                        for track in sorted { displayItems.append(ModernDisplayItem(id: track.id.uuidString, title: track.title, info: track.formattedDuration, indentLevel: 2, hasChildren: false, type: .localTrack(track))) }
                    }
                }
            }
        }
    }
    
    private func buildLocalAlbumItems() {
        displayItems = sortAlbums(cachedLocalAlbums).map { ModernDisplayItem(id: "local-album-\($0.id)", title: $0.displayName, info: "\($0.tracks.count) tracks", indentLevel: 0, hasChildren: false, type: .localAlbum($0)) }
    }
    
    private func buildLocalTrackItems() {
        displayItems = sortTracks(cachedLocalTracks).map { ModernDisplayItem(id: $0.id.uuidString, title: $0.displayTitle, info: $0.formattedDuration, indentLevel: 0, hasChildren: false, type: .localTrack($0)) }
    }
    
    private func buildLocalSearchItems() {
        displayItems.removeAll()
        guard !searchQuery.isEmpty else { return }
        let query = searchQuery.lowercased()
        let matchingArtists = cachedLocalArtists.filter { $0.name.lowercased().contains(query) }
        if !matchingArtists.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-local-artists", title: "Artists (\(matchingArtists.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for a in matchingArtists { displayItems.append(ModernDisplayItem(id: "local-artist-\(a.id)", title: a.name, info: "\(a.albums.count) albums", indentLevel: 1, hasChildren: true, type: .localArtist(a))) }
        }
        let matchingAlbums = cachedLocalAlbums.filter { $0.name.lowercased().contains(query) || ($0.artist?.lowercased().contains(query) ?? false) }
        if !matchingAlbums.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-local-albums", title: "Albums (\(matchingAlbums.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for a in matchingAlbums { displayItems.append(ModernDisplayItem(id: "local-album-\(a.id)", title: a.displayName, info: "\(a.tracks.count) tracks", indentLevel: 1, hasChildren: false, type: .localAlbum(a))) }
        }
        let matchingTracks = MediaLibrary.shared.search(query: searchQuery)
        if !matchingTracks.isEmpty {
            displayItems.append(ModernDisplayItem(id: "header-local-tracks", title: "Tracks (\(matchingTracks.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            for t in matchingTracks { displayItems.append(ModernDisplayItem(id: t.id.uuidString, title: t.displayTitle, info: t.formattedDuration, indentLevel: 1, hasChildren: false, type: .localTrack(t))) }
        }
    }
    
    // Subsonic items
    private func buildSubsonicArtistItems() {
        displayItems.removeAll()
        for artist in cachedSubsonicArtists.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let info = artist.albumCount > 0 ? "\(artist.albumCount) albums" : nil
            let expanded = expandedSubsonicArtists.contains(artist.id)
            displayItems.append(ModernDisplayItem(id: artist.id, title: artist.name, info: info, indentLevel: 0, hasChildren: true, type: .subsonicArtist(artist)))
            if expanded, let albums = subsonicArtistAlbums[artist.id] {
                for album in albums {
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
        displayItems = cachedSubsonicAlbums.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }).map {
            ModernDisplayItem(id: $0.id, title: "\($0.artist ?? "Unknown") - \($0.name)", info: $0.year.map { String($0) }, indentLevel: 0, hasChildren: true, type: .subsonicAlbum($0))
        }
    }
    
    private func buildSubsonicTrackItems() {
        Task { @MainActor in
            do {
                let results = try await SubsonicManager.shared.serverClient?.search(query: "", artistCount: 0, albumCount: 0, songCount: 500) ?? SubsonicSearchResults()
                let songs = results.songs
                displayItems = songs.sorted(by: {
                    let artist1 = $0.artist ?? ""
                    let artist2 = $1.artist ?? ""
                    if artist1 != artist2 { return artist1.localizedCaseInsensitiveCompare(artist2) == .orderedAscending }
                    let album1 = $0.album ?? ""
                    let album2 = $1.album ?? ""
                    if album1 != album2 { return album1.localizedCaseInsensitiveCompare(album2) == .orderedAscending }
                    return ($0.track ?? 0) < ($1.track ?? 0)
                }).map {
                    ModernDisplayItem(
                        id: $0.id,
                        title: "\($0.artist ?? "Unknown") - \($0.title)",
                        info: $0.formattedDuration,
                        indentLevel: 0,
                        hasChildren: false,
                        type: .subsonicTrack($0)
                    )
                }
                applyColumnSort()
                needsDisplay = true
            } catch {
                NSLog("Failed to fetch Subsonic tracks: %@", error.localizedDescription)
                displayItems = []
                needsDisplay = true
            }
        }
    }
    
    private func buildSubsonicPlaylistItems() {
        displayItems.removeAll()
        for playlist in cachedSubsonicPlaylists.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let expanded = expandedSubsonicPlaylists.contains(playlist.id)
            displayItems.append(ModernDisplayItem(id: playlist.id, title: playlist.name, info: "\(playlist.songCount) tracks", indentLevel: 0, hasChildren: playlist.songCount > 0, type: .subsonicPlaylist(playlist)))
            if expanded, let tracks = subsonicPlaylistTracks[playlist.id] {
                for t in tracks { displayItems.append(ModernDisplayItem(id: "\(playlist.id)-\(t.id)", title: t.title, info: formatDuration(t.duration), indentLevel: 1, hasChildren: false, type: .subsonicTrack(t))) }
            }
        }
    }
    
    private func formatDuration(_ seconds: Int?) -> String? {
        guard let s = seconds else { return nil }
        let mins = s / 60; let secs = s % 60; return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Sorting Helpers
    
    private func sortArtists(_ artists: [Artist]) -> [Artist] {
        switch currentSort {
        case .nameAsc: return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc: return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        default: return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    private func sortAlbums(_ albums: [Album]) -> [Album] {
        switch currentSort {
        case .nameAsc: return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc: return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .yearDesc: return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        default: return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    private func sortTracks(_ tracks: [LibraryTrack]) -> [LibraryTrack] {
        switch currentSort {
        case .nameAsc: return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc: return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateAddedDesc: return tracks.sorted { $0.dateAdded > $1.dateAdded }
        case .dateAddedAsc: return tracks.sorted { $0.dateAdded < $1.dateAdded }
        case .yearDesc: return tracks.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return tracks.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }
    
    private func sortPlexArtists(_ artists: [PlexArtist]) -> [PlexArtist] {
        switch currentSort {
        case .nameAsc: return artists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc: return artists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateAddedDesc: return artists.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc: return artists.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        default: return artists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    
    private func sortPlexAlbums(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        switch currentSort {
        case .nameAsc: return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc: return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateAddedDesc: return albums.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc: return albums.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        case .yearDesc: return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc: return albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }
    
    private func sortPlexTracks(_ tracks: [PlexTrack]) -> [PlexTrack] {
        switch currentSort {
        case .nameAsc: return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc: return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateAddedDesc: return tracks.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc: return tracks.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        default: return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    
    // MARK: - Rebuild Current Mode Items
    
    private func rebuildCurrentModeItems() {
        horizontalScrollOffset = 0
        if case .radio = currentSource { if browseMode == .radio { buildRadioStationItems() } else { displayItems = [] }; needsDisplay = true; return }
        if browseMode == .radio { needsDisplay = true; return }
        if case .local = currentSource {
            switch browseMode {
            case .artists: buildLocalArtistItems()
            case .albums: buildLocalAlbumItems()
            case .tracks: buildLocalTrackItems()
            case .search: buildLocalSearchItems()
            default: displayItems = []
            }
        } else if case .subsonic = currentSource {
            switch browseMode {
            case .artists: buildSubsonicArtistItems()
            case .albums: buildSubsonicAlbumItems()
            case .tracks: buildSubsonicTrackItems()
            case .plists: buildSubsonicPlaylistItems()
            default: displayItems = []
            }
        } else {
            switch browseMode {
            case .artists: buildArtistItems()
            case .albums: buildAlbumItems()
            case .tracks: buildTrackItems()
            case .movies: buildMovieItems()
            case .shows: buildShowItems()
            case .plists: buildPlexPlaylistItems()
            case .search: buildSearchItems()
            case .radio: break
            }
        }
        if columnSortId != nil { applyColumnSort() }
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
        case .subsonicArtist(let a): return expandedSubsonicArtists.contains(a.id)
        case .subsonicAlbum(let a): return expandedSubsonicAlbums.contains(a.id)
        case .subsonicPlaylist(let p): return expandedSubsonicPlaylists.contains(p.id)
        case .plexPlaylist(let p): return expandedPlexPlaylists.contains(p.id)
        default: return false
        }
    }
    
    private func toggleExpand(_ item: ModernDisplayItem) {
        switch item.type {
        case .artist(let artist):
            if expandedArtists.contains(artist.id) { expandedArtists.remove(artist.id) }
            else {
                expandedArtists.insert(artist.id)
                if artistAlbums[artist.id] == nil {
                    Task { @MainActor in
                        do {
                            NSLog("ModernLibraryBrowser: Fetching albums for artist '%@' (id=%@)", artist.title, artist.id)
                            let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                            if albums.isEmpty && artist.albumCount > 0 {
                                NSLog("ModernLibraryBrowser: Warning - API returned 0 albums for '%@' (id=%@) but albumCount=%d - allowing retry", artist.title, artist.id, artist.albumCount)
                                expandedArtists.remove(artist.id)
                            } else {
                                NSLog("ModernLibraryBrowser: Loaded %d albums for '%@' (id=%@)", albums.count, artist.title, artist.id)
                                artistAlbums[artist.id] = albums
                            }
                            rebuildCurrentModeItems()
                        } catch {
                            NSLog("ModernLibraryBrowser: Failed to load albums for '%@' (id=%@): %@", artist.title, artist.id, error.localizedDescription)
                            expandedArtists.remove(artist.id)
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
        case .subsonicArtist(let artist):
            if expandedSubsonicArtists.contains(artist.id) { expandedSubsonicArtists.remove(artist.id) }
            else {
                expandedSubsonicArtists.insert(artist.id)
                if subsonicArtistAlbums[artist.id] == nil {
                    let id = artist.id; subsonicExpandTask?.cancel()
                    subsonicExpandTask = Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: artist); subsonicArtistAlbums[id] = albums; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .subsonicAlbum(let album):
            if expandedSubsonicAlbums.contains(album.id) { expandedSubsonicAlbums.remove(album.id) }
            else {
                expandedSubsonicAlbums.insert(album.id)
                if subsonicAlbumSongs[album.id] == nil {
                    let id = album.id; subsonicExpandTask?.cancel()
                    subsonicExpandTask = Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album); subsonicAlbumSongs[id] = songs; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch { NSLog("Failed: \(error)") }
                    }; return
                }
            }
        case .subsonicPlaylist(let playlist):
            if expandedSubsonicPlaylists.contains(playlist.id) { expandedSubsonicPlaylists.remove(playlist.id) }
            else {
                expandedSubsonicPlaylists.insert(playlist.id)
                if subsonicPlaylistTracks[playlist.id] == nil {
                    let id = playlist.id; subsonicExpandTask?.cancel()
                    subsonicExpandTask = Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do { let (_, tracks) = try await SubsonicManager.shared.serverClient?.fetchPlaylist(id: id) ?? (playlist, []); subsonicPlaylistTracks[id] = tracks; rebuildCurrentModeItems() }
                        catch is CancellationError { } catch { NSLog("Failed: \(error)") }
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
                let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                var all: [PlexTrack] = []
                for album in albums { all.append(contentsOf: try await PlexManager.shared.fetchTracks(forAlbum: album)) }
                // Last-resort fallback: if no tracks found via albums, fetch tracks directly
                if all.isEmpty {
                    NSLog("ModernLibraryBrowser: No tracks found via albums for '%@', trying direct track fetch", artist.title)
                    all = try await PlexManager.shared.fetchTracks(forArtist: artist)
                }
                WindowManager.shared.audioEngine.playNow(PlexManager.shared.convertToTracks(all))
            } catch { NSLog("Failed: %@", error.localizedDescription) }
        }
    }
    private func playMovie(_ movie: PlexMovie) { WindowManager.shared.playMovie(movie) }
    private func playEpisode(_ episode: PlexEpisode) { WindowManager.shared.playEpisode(episode) }
    private func playLocalTrack(_ track: LibraryTrack) { WindowManager.shared.audioEngine.playNow([track.toTrack()]) }
    private func playLocalAlbum(_ album: Album) { WindowManager.shared.audioEngine.playNow(album.tracks.map { $0.toTrack() }) }
    private func playLocalArtist(_ artist: Artist) {
        var tracks: [Track] = []
        for album in artist.albums { tracks.append(contentsOf: album.tracks.map { $0.toTrack() }) }
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
        Task { @MainActor in
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
            if !tracks.isEmpty {
                let engine = WindowManager.shared.audioEngine; engine.clearPlaylist(); engine.loadTracks(tracks); engine.play()
            }
        }
    }
    
    private func handleDoubleClick(on item: ModernDisplayItem) {
        switch item.type {
        case .track: playTrack(item)
        case .album(let a): playAlbum(a)
        case .artist: toggleExpand(item)
        case .movie(let m): playMovie(m)
        case .show: toggleExpand(item)
        case .season: toggleExpand(item)
        case .episode(let e): playEpisode(e)
        case .header: break
        case .localTrack(let t): playLocalTrack(t)
        case .localAlbum(let a): playLocalAlbum(a)
        case .localArtist: toggleExpand(item)
        case .subsonicTrack(let s): playSubsonicSong(s)
        case .subsonicAlbum(let a): playSubsonicAlbum(a)
        case .subsonicArtist: toggleExpand(item)
        case .subsonicPlaylist(let p): playSubsonicPlaylist(p)
        case .plexPlaylist(let p): playPlexPlaylist(p)
        case .radioStation(let s): playRadioStation(s)
        case .plexRadioStation(let r): playPlexRadioStation(r)
        }
    }
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
        case subsonicArtist(SubsonicArtist)
        case subsonicAlbum(SubsonicAlbum)
        case subsonicTrack(SubsonicSong)
        case subsonicPlaylist(SubsonicPlaylist)
        case plexPlaylist(PlexPlaylist)
        case radioStation(RadioStation)
        case plexRadioStation(PlexRadioType)
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
    static let filePath = ModernBrowserColumn(id: "path", title: "Path", minWidth: 150)
    
    // All available columns (superset for each view type)
    static let allTrackColumns: [ModernBrowserColumn] = [
        .trackNumber, .title, .artist, .album, .albumArtist, .year, .genre, .duration,
        .bitrate, .sampleRate, .channels, .size, .rating, .playCount, .discNumber,
        .dateAdded, .lastPlayed, .filePath
    ]
    static let allAlbumColumns: [ModernBrowserColumn] = [.title, .year, .genre, .duration, .rating]
    static let allArtistColumns: [ModernBrowserColumn] = [.title, .albums, .genre]
    
    // Default visible column IDs (backwards-compatible with the original set)
    static let defaultTrackColumnIds: [String] = ["trackNum", "title", "artist", "album", "year", "genre", "duration", "bitrate", "size", "rating", "plays"]
    static let defaultAlbumColumnIds: [String] = ["title", "year", "genre", "duration", "rating"]
    static let defaultArtistColumnIds: [String] = ["title", "albums", "genre"]
    
    // Legacy arrays kept for backwards compatibility with sort lookup
    static let trackColumns: [ModernBrowserColumn] = [.trackNumber, .title, .artist, .album, .year, .genre, .duration, .bitrate, .size, .rating, .playCount]
    static let albumColumns: [ModernBrowserColumn] = [.title, .year, .genre, .duration, .rating]
    static let artistColumns: [ModernBrowserColumn] = [.title, .albums, .genre]
    
    static func findColumn(id: String) -> ModernBrowserColumn? {
        if let c = allTrackColumns.first(where: { $0.id == id }) { return c }
        if let c = allAlbumColumns.first(where: { $0.id == id }) { return c }
        if let c = allArtistColumns.first(where: { $0.id == id }) { return c }
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
        case .localTrack(let t): return localTrackValue(t, for: column)
        case .album(let a): return plexAlbumValue(a, for: column)
        case .subsonicAlbum(let a): return subsonicAlbumValue(a, for: column)
        case .localAlbum(let a): return localAlbumValue(a, for: column)
        case .artist(let a): return plexArtistValue(a, for: column)
        case .subsonicArtist(let a): return column.id == "albums" ? String(a.albumCount) : ""
        case .localArtist(let a): return column.id == "albums" ? String(a.albums.count) : ""
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
        case "sampleRate": return ""  // Not available in Plex API track model
        case "channels": return track.media.first?.audioChannels.map { Self.formatChannels($0) } ?? ""
        case "size": return Self.formatFileSize(track.media.first?.parts.first?.size)
        case "rating": return Self.formatRating(track.userRating)
        case "plays": return track.ratingCount.map { String($0) } ?? ""
        case "discNum": return track.parentIndex.map { String($0) } ?? ""
        case "dateAdded": return track.addedAt.map { Self.formatDate($0) } ?? ""
        case "lastPlayed": return ""  // Not available in Plex API
        case "path": return track.media.first?.parts.first?.file?.components(separatedBy: "/").last ?? ""
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
        case "albumArtist": return song.artist ?? ""  // Subsonic doesn't separate album artist
        case "year": return song.year.map { String($0) } ?? ""
        case "genre": return song.genre ?? ""
        case "duration": return song.formattedDuration
        case "bitrate": return song.bitRate.map { "\($0)k" } ?? ""
        case "sampleRate": return ""  // Not available in Subsonic API
        case "channels": return ""  // Not available in Subsonic API
        case "size": return Self.formatFileSize(song.size)
        case "rating":
            if let userRating = song.userRating, userRating > 0 {
                return Self.formatRating(Double(userRating) * 2.0)
            }
            return song.starred != nil ? "★" : ""
        case "plays": return song.playCount.map { String($0) } ?? ""
        case "discNum": return song.discNumber.map { String($0) } ?? ""
        case "dateAdded": return song.created.map { Self.formatDate($0) } ?? ""
        case "lastPlayed": return ""  // Not available in Subsonic API
        case "path": return song.path?.components(separatedBy: "/").last ?? ""
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
        case "path": return track.url.lastPathComponent
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
    
    private func localAlbumValue(_ album: Album, for column: ModernBrowserColumn) -> String {
        switch column.id {
        case "year": return album.year.map { String($0) } ?? ""
        case "duration": return album.formattedDuration
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
        guard let rating = rating, rating > 0 else { return "" }
        let stars = Int(rating / 2.0); let empty = 5 - stars
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: empty)
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
            default: return nil
            }
        case "lastPlayed":
            switch type {
            case .localTrack(let t): return t.lastPlayed
            default: return nil
            }
        default: return nil
        }
    }
}
