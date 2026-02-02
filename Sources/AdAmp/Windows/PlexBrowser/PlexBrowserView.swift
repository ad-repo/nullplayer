import AppKit
import AVFoundation

/// Source for browsing content
enum BrowserSource: Equatable, Codable {
    case local
    case plex(serverId: String)
    case subsonic(serverId: String)
    case radio
    
    /// Display name for the source
    var displayName: String {
        switch self {
        case .local:
            return "LOCAL FILES"
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
        case .radio:
            return "INTERNET RADIO"
        }
    }
    
    /// Short name for compact display
    var shortName: String {
        switch self {
        case .local:
            return "Local Files"
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
        case .radio:
            return "Radio"
        }
    }
    
    /// Whether this is a Subsonic source
    var isSubsonic: Bool {
        if case .subsonic = self { return true }
        return false
    }
    
    /// Whether this is a Plex source
    var isPlex: Bool {
        if case .plex = self { return true }
        return false
    }
    
    /// Whether this is a radio source
    var isRadio: Bool {
        if case .radio = self { return true }
        return false
    }
    
    /// Whether this is a remote source (Plex or Subsonic)
    var isRemote: Bool {
        switch self {
        case .local, .radio:
            return false
        case .plex, .subsonic:
            return true
        }
    }
    
    /// Persistence key
    private static let userDefaultsKey = "BrowserSource"
    
    /// Save to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
    
    /// Load from UserDefaults
    static func load() -> BrowserSource? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let source = try? JSONDecoder().decode(BrowserSource.self, from: data) else {
            return nil
        }
        return source
    }
}

/// Browse mode for the Plex browser
enum PlexBrowseMode: Int, CaseIterable {
    case artists = 0
    case albums = 1
    case tracks = 2
    case plists = 3
    case movies = 4
    case shows = 5
    case search = 6
    case radio = 7
    
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
    
    var isVideoMode: Bool {
        self == .movies || self == .shows
    }
    
    var isMusicMode: Bool {
        self == .artists || self == .albums || self == .tracks || self == .plists
    }
    
    var isRadioMode: Bool {
        self == .radio
    }
}

/// Sort options for browser content
enum BrowserSortOption: String, CaseIterable, Codable {
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
    
    /// Persistence key
    private static let userDefaultsKey = "BrowserSortOption"
    
    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }
    
    static func load() -> BrowserSortOption {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let option = BrowserSortOption(rawValue: raw) else {
            return .nameAsc
        }
        return option
    }
}

// =============================================================================
// PLEX BROWSER VIEW - Skinned Plex browser with playlist sprite support
// =============================================================================
// Follows the same pattern as PlaylistView for:
// - Coordinate transformation (Winamp top-down system)
// - Button hit testing and visual feedback
// - Scaling support for resizable windows
// =============================================================================

/// Plex browser view with Winamp-style skin support
class PlexBrowserView: NSView {
    
    // MARK: - Properties
    
    weak var controller: PlexBrowserWindowController?
    
    /// Current browse source (local files or Plex server)
    private var currentSource: BrowserSource = .local {
        didSet {
            currentSource.save()
            onSourceChanged()
        }
    }
    
    /// Pending source to restore after servers connect
    private var pendingSourceRestore: BrowserSource?
    
    /// Current browse mode
    private var browseMode: PlexBrowseMode = .artists
    
    /// Current sort option
    private var currentSort: BrowserSortOption = .nameAsc {
        didSet {
            currentSort.save()
            rebuildCurrentModeItems()
            needsDisplay = true
        }
    }
    
    /// Search query
    private var searchQuery: String = ""
    
    /// Selected item indices
    private var selectedIndices: Set<Int> = []
    
    /// Scroll offset
    private var scrollOffset: CGFloat = 0
    
    /// Horizontal scroll offset for column headers
    private var horizontalScrollOffset: CGFloat = 0
    
    /// Item height
    private let itemHeight: CGFloat = 18
    
    /// Height of column headers
    private let columnHeaderHeight: CGFloat = 18
    
    /// Stored column widths (persisted)
    private var columnWidths: [String: CGFloat] = [:] {
        didSet { saveColumnWidths() }
    }
    
    /// Column being resized (id) and resize state
    private var resizingColumnId: String?
    private var resizeStartX: CGFloat = 0
    private var resizeStartWidth: CGFloat = 0
    
    /// Column sort state (overrides currentSort when set)
    private var columnSortId: String? {
        didSet {
            saveColumnSort()
            applyColumnSort(collapseExpanded: true)
        }
    }
    private var columnSortAscending: Bool = true {
        didSet {
            saveColumnSort()
            applyColumnSort(collapseExpanded: true)
        }
    }
    
    /// Save column sort to UserDefaults
    private func saveColumnSort() {
        if let id = columnSortId {
            UserDefaults.standard.set(id, forKey: "BrowserColumnSortId")
            UserDefaults.standard.set(columnSortAscending, forKey: "BrowserColumnSortAscending")
        } else {
            UserDefaults.standard.removeObject(forKey: "BrowserColumnSortId")
        }
    }
    
    /// Load column sort from UserDefaults
    private func loadColumnSort() {
        columnSortId = UserDefaults.standard.string(forKey: "BrowserColumnSortId")
        columnSortAscending = UserDefaults.standard.bool(forKey: "BrowserColumnSortAscending")
        // Default to true if not set
        if UserDefaults.standard.object(forKey: "BrowserColumnSortAscending") == nil {
            columnSortAscending = true
        }
    }
    
    /// Whether any content uses columns (for showing headers)
    private var hasColumnContent: Bool {
        displayItems.contains { item in
            columnsForItem(item) != nil
        }
    }
    
    /// Get columns for a specific item (nil = use simple list rendering)
    private func columnsForItem(_ item: PlexDisplayItem) -> [BrowserColumn]? {
        switch item.type {
        case .track, .subsonicTrack, .localTrack:
            return BrowserColumn.trackColumns
        case .album, .subsonicAlbum, .localAlbum:
            return BrowserColumn.albumColumns
        case .artist, .subsonicArtist, .localArtist:
            // Only show columns for top-level artists (not nested under search results)
            if item.indentLevel == 0 {
                return BrowserColumn.artistColumns
            }
            return nil
        default:
            return nil
        }
    }
    
    /// Get width for a column (uses stored width or default)
    private func widthForColumn(_ column: BrowserColumn, availableWidth: CGFloat, columns: [BrowserColumn]) -> CGFloat {
        if column.id == "title" {
            // Title column gets remaining space
            let fixedWidth = columns.filter { $0.id != "title" }.reduce(0) { 
                $0 + (columnWidths[$1.id] ?? $1.minWidth)
            }
            return max(column.minWidth, availableWidth - fixedWidth - 8)
        }
        return columnWidths[column.id] ?? column.minWidth
    }
    
    /// Calculate total width needed for all columns
    private func totalColumnsWidth(columns: [BrowserColumn]) -> CGFloat {
        var total: CGFloat = 8  // Initial padding
        for column in columns {
            if column.id == "title" {
                total += column.minWidth  // Title uses minWidth for total calculation
            } else {
                total += columnWidths[column.id] ?? column.minWidth
            }
        }
        return total
    }
    
    /// Save column widths to UserDefaults
    private func saveColumnWidths() {
        UserDefaults.standard.set(columnWidths, forKey: "BrowserColumnWidths")
    }
    
    /// Load column widths from UserDefaults
    private func loadColumnWidths() {
        if let saved = UserDefaults.standard.dictionary(forKey: "BrowserColumnWidths") as? [String: CGFloat] {
            columnWidths = saved
        }
    }
    
    /// Apply column sort to display items
    /// - Parameter collapseExpanded: If true, collapse all expanded items before sorting (used when sort changes)
    private func applyColumnSort(collapseExpanded: Bool = false) {
        guard let sortColumnId = columnSortId, !displayItems.isEmpty else {
            needsDisplay = true
            return
        }
        
        // Collapse all expanded items before sorting to avoid orphaned children
        // (expanded albums would otherwise stay in place while parents move)
        // Only do this when the sort is actively changed, not on every rebuild
        if collapseExpanded {
            let hadExpanded = !expandedArtists.isEmpty || !expandedAlbums.isEmpty ||
                              !expandedArtistNames.isEmpty ||
                              !expandedLocalArtists.isEmpty || !expandedLocalAlbums.isEmpty ||
                              !expandedSubsonicArtists.isEmpty || !expandedSubsonicAlbums.isEmpty ||
                              !expandedSubsonicPlaylists.isEmpty || !expandedPlexPlaylists.isEmpty ||
                              !expandedShows.isEmpty || !expandedSeasons.isEmpty
            if hadExpanded {
                expandedArtists.removeAll()
                expandedAlbums.removeAll()
                expandedArtistNames.removeAll()
                expandedLocalArtists.removeAll()
                expandedLocalAlbums.removeAll()
                expandedSubsonicArtists.removeAll()
                expandedSubsonicAlbums.removeAll()
                expandedSubsonicPlaylists.removeAll()
                expandedPlexPlaylists.removeAll()
                expandedShows.removeAll()
                expandedSeasons.removeAll()
                // Remove nested items from displayItems (they have indentLevel > 0)
                displayItems = displayItems.filter { $0.indentLevel == 0 }
            }
        }
        
        // Find the column definition
        let column: BrowserColumn?
        if let c = BrowserColumn.trackColumns.first(where: { $0.id == sortColumnId }) {
            column = c
        } else if let c = BrowserColumn.albumColumns.first(where: { $0.id == sortColumnId }) {
            column = c
        } else if let c = BrowserColumn.artistColumns.first(where: { $0.id == sortColumnId }) {
            column = c
        } else {
            column = nil
        }
        
        guard let sortColumn = column else {
            needsDisplay = true
            return
        }
        
        // If there are any nested/expanded items (indentLevel > 0), skip column sorting
        // to avoid orphaning children from their parents. The build functions already
        // handle proper ordering of hierarchical items.
        let hasNestedItems = displayItems.contains { $0.indentLevel > 0 }
        if hasNestedItems {
            needsDisplay = true
            return
        }
        
        // Sort top-level items only (flat list with no expanded children)
        var sortableIndices: [Int] = []
        var sortableItems: [PlexDisplayItem] = []
        
        for (index, item) in displayItems.enumerated() {
            if columnsForItem(item) != nil && item.indentLevel == 0 {
                sortableIndices.append(index)
                sortableItems.append(item)
            }
        }
        
        guard !sortableItems.isEmpty else {
            needsDisplay = true
            return
        }
        
        // Sort the sortable items
        let ascending = columnSortAscending
        sortableItems.sort { a, b in
            let aVal = a.columnValue(for: sortColumn)
            let bVal = b.columnValue(for: sortColumn)
            
            // Try numeric comparison for numeric columns
            if sortColumn.id == "trackNum" || sortColumn.id == "year" || sortColumn.id == "plays" || sortColumn.id == "albums" {
                let aNum = Int(aVal.components(separatedBy: "-").last ?? aVal) ?? 0
                let bNum = Int(bVal.components(separatedBy: "-").last ?? bVal) ?? 0
                return ascending ? aNum < bNum : aNum > bNum
            }
            
            // Duration comparison (convert to seconds)
            if sortColumn.id == "duration" {
                let aSeconds = parseDuration(aVal)
                let bSeconds = parseDuration(bVal)
                return ascending ? aSeconds < bSeconds : aSeconds > bSeconds
            }
            
            // Bitrate comparison
            if sortColumn.id == "bitrate" {
                let aKbps = Int(aVal.replacingOccurrences(of: "k", with: "")) ?? 0
                let bKbps = Int(bVal.replacingOccurrences(of: "k", with: "")) ?? 0
                return ascending ? aKbps < bKbps : aKbps > bKbps
            }
            
            // Size comparison
            if sortColumn.id == "size" {
                let aSize = parseSize(aVal)
                let bSize = parseSize(bVal)
                return ascending ? aSize < bSize : aSize > bSize
            }
            
            // Rating comparison (star count)
            if sortColumn.id == "rating" {
                let aStars = aVal.filter { $0 == "★" }.count
                let bStars = bVal.filter { $0 == "★" }.count
                return ascending ? aStars < bStars : aStars > bStars
            }
            
            // Default string comparison
            let result = aVal.localizedCaseInsensitiveCompare(bVal)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        
        // Put sorted items back at their original indices
        for (sortedIndex, originalIndex) in sortableIndices.enumerated() {
            displayItems[originalIndex] = sortableItems[sortedIndex]
        }
        
        needsDisplay = true
    }
    
    /// Parse duration string (e.g., "3:45" or "1:23:45") to seconds
    private func parseDuration(_ str: String) -> Int {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }
    
    /// Parse size string (e.g., "12.5M" or "1.2G") to bytes
    private func parseSize(_ str: String) -> Int64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("G") {
            let num = Double(trimmed.dropLast()) ?? 0
            return Int64(num * 1024 * 1024 * 1024)
        } else if trimmed.hasSuffix("M") {
            let num = Double(trimmed.dropLast()) ?? 0
            return Int64(num * 1024 * 1024)
        }
        return Int64(trimmed) ?? 0
    }
    
    /// Current display items
    private var displayItems: [PlexDisplayItem] = []
    
    /// Expanded artists for hierarchical view (by ID)
    private var expandedArtists: Set<String> = []
    
    /// Expanded albums (for showing tracks, by ID)
    private var expandedAlbums: Set<String> = []
    
    /// Expanded artists by name (for search results where IDs can vary)
    private var expandedArtistNames: Set<String> = []
    
    /// Albums fetched by artist name (for search results)
    private var artistAlbumsByName: [String: [PlexAlbum]] = [:]
    
    /// Loading state
    private var isLoading: Bool = false
    
    /// Error message
    private var errorMessage: String?
    
    /// Cached data - Music (Plex)
    private var cachedArtists: [PlexArtist] = []
    private var cachedAlbums: [PlexAlbum] = []
    private var cachedTracks: [PlexTrack] = []
    private var artistAlbums: [String: [PlexAlbum]] = [:]
    private var albumTracks: [String: [PlexTrack]] = [:]
    private var artistAlbumCounts: [String: Int] = [:]  // Album count per artist (from parentKey)
    
    /// Cached data - Music (Local)
    private var cachedLocalArtists: [Artist] = []
    private var cachedLocalAlbums: [Album] = []
    private var cachedLocalTracks: [LibraryTrack] = []
    private var expandedLocalArtists: Set<String> = []
    private var expandedLocalAlbums: Set<String> = []
    
    /// Cached data - Music (Subsonic)
    private var cachedSubsonicArtists: [SubsonicArtist] = []
    private var cachedSubsonicAlbums: [SubsonicAlbum] = []
    private var cachedSubsonicPlaylists: [SubsonicPlaylist] = []
    private var expandedSubsonicArtists: Set<String> = []
    private var expandedSubsonicAlbums: Set<String> = []
    private var expandedSubsonicPlaylists: Set<String> = []
    private var subsonicArtistAlbums: [String: [SubsonicAlbum]] = [:]
    private var subsonicPlaylistTracks: [String: [SubsonicSong]] = [:]
    private var subsonicAlbumSongs: [String: [SubsonicSong]] = [:]
    private var subsonicLoadTask: Task<Void, Never>?
    private var subsonicExpandTask: Task<Void, Never>?
    
    /// Cached data - Radio Stations
    private var cachedRadioStations: [RadioStation] = []
    
    /// Strong reference to prevent deallocation while dialog is open
    private var activeRadioStationSheet: AddRadioStationSheet?
    
    /// Cached data - Video
    private var cachedMovies: [PlexMovie] = []
    private var cachedShows: [PlexShow] = []
    private var showSeasons: [String: [PlexSeason]] = [:]
    private var seasonEpisodes: [String: [PlexEpisode]] = [:]
    
    /// Cached data - Playlists (Plex)
    private var cachedPlexPlaylists: [PlexPlaylist] = []
    private var expandedPlexPlaylists: Set<String> = []
    private var plexPlaylistTracks: [String: [PlexTrack]] = [:]
    
    /// Expanded shows (showing seasons)
    private var expandedShows: Set<String> = []
    
    /// Expanded seasons (showing episodes)
    private var expandedSeasons: Set<String> = []
    
    private var searchResults: PlexSearchResults?
    
    /// Loading animation
    private var loadingAnimationTimer: Timer?
    private var loadingAnimationFrame: Int = 0
    
    /// Server name scrolling animation
    private var serverNameScrollOffset: CGFloat = 0
    private var libraryNameScrollOffset: CGFloat = 0
    private var serverScrollTimer: Timer?
    private var lastServerName: String = ""
    private var lastLibraryName: String = ""
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Art-only mode - hides tabs and list, shows just album art (session only, not persisted)
    private var isArtOnlyMode: Bool = false {
        didSet {
            needsDisplay = true
            if isArtOnlyMode {
                // Fetch current track rating when entering art mode
                fetchCurrentTrackRating()
                // Load all artwork for cycling
                loadAllArtworkForCurrentTrack()
            } else {
                // Stop visualization when exiting art-only mode
                isVisualizingArt = false
                // Clear cycling state
                artworkImages = []
                artworkIndex = 0
            }
        }
    }
    
    /// Visualization mode - applies audio-reactive effects to album art
    private var isVisualizingArt: Bool = false {
        didSet {
            if isVisualizingArt {
                startVisualizerTimer()
            } else {
                stopVisualizerTimer()
            }
            needsDisplay = true
        }
    }
    
    /// Whether the rating overlay is visible
    private var isRatingOverlayVisible: Bool = false
    
    /// Current user rating for the playing Plex track (0-10, nil if unrated)
    private var currentTrackRating: Int? = nil
    
    /// Hit rect for the RATE button
    private var rateButtonRect: NSRect = .zero
    
    /// Task for debounced rating submission (cancels previous if rapid selection)
    private var ratingSubmitTask: Task<Void, Never>?
    
    /// All artwork images for the current track (for cycling in art mode)
    private var artworkImages: [NSImage] = []
    
    /// Current index in artworkImages array
    private var artworkIndex: Int = 0
    
    /// Current visualization effect (30 effects - all transform the image)
    enum VisEffect: String, CaseIterable {
        // Rotation & Scaling
        case psychedelic = "Psychedelic"
        case kaleidoscope = "Kaleidoscope"
        case vortex = "Vortex"
        case spin = "Endless Spin"
        case fractal = "Fractal Zoom"
        case tunnel = "Time Tunnel"
        // Distortion
        case melt = "Acid Melt"
        case wave = "Ocean Wave"
        case glitch = "Glitch"
        case rgbSplit = "RGB Split"
        case twist = "Twist"
        case fisheye = "Fisheye"
        case shatter = "Shatter"
        case stretch = "Rubber Band"
        // Motion
        case zoom = "Zoom Pulse"
        case shake = "Earthquake"
        case bounce = "Bounce"
        case feedback = "Feedback Loop"
        case strobe = "Strobe"
        case jitter = "Jitter"
        // Copies & Mirrors
        case mirror = "Infinite Mirror"
        case tile = "Tile Grid"
        case prism = "Prism Split"
        case doubleVision = "Double Vision"
        case flipbook = "Flipbook"
        case mosaic = "Mosaic"
        // Pixel effects
        case pixelate = "Pixelate"
        case scanlines = "Scanlines"
        case datamosh = "Datamosh"
        case blocky = "Blocky"
    }
    
    /// Visualization mode
    enum VisMode {
        case single      // Single selected effect
        case random      // Random effect each beat
        case cycle       // Cycle through all effects
    }
    
    /// Current effect selection
    private var currentVisEffect: VisEffect = .psychedelic
    
    /// Current visualization mode
    private var visMode: VisMode = .single
    
    /// Timer for cycle mode
    private var cycleTimer: Timer?
    
    /// Cycle interval in seconds
    private var cycleInterval: TimeInterval = 10.0
    
    /// Last beat time for random mode
    private var lastBeatTime: TimeInterval = 0
    
    /// Effect intensity (0.5 to 2.0)
    private var visEffectIntensity: CGFloat = 1.0
    
    /// Timer for visualization animation
    private var visualizerTimer: Timer?
    
    /// Current visualization time
    private var visualizerTime: TimeInterval = 0
    
    /// Whether audio is currently active (for stopping effects when silent)
    private var lastAudioLevel: Float = 0
    private var silenceFrames: Int = 0
    
    /// Core Image context for GPU-accelerated effects
    private lazy var ciContext: CIContext = {
        if let mtlDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: mtlDevice, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: SkinRenderer.PlexBrowserButtonType?
    
    /// Active tags panel (strong reference to prevent premature deallocation)
    private var activeTagsPanel: TagsPanel?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Scrollbar dragging state
    private var isDraggingScrollbar = false
    private var scrollbarDragStartY: CGFloat = 0
    private var scrollbarDragStartOffset: CGFloat = 0
    
    /// Alphabet index for quick navigation
    private let alphabetLetters = ["#"] + (65...90).map { String(UnicodeScalar($0)) } // # A-Z
    
    // MARK: - Artwork Background State
    
    /// Current artwork image for background display
    private var currentArtwork: NSImage?
    
    /// Track ID for the currently displayed artwork (to avoid reloading)
    private var artworkTrackId: UUID?
    
    /// Async task for loading artwork (can be cancelled)
    private var artworkLoadTask: Task<Void, Never>?
    
    /// Async task for loading all artwork images for cycling (can be cancelled)
    private var artworkCyclingTask: Task<Void, Never>?
    
    /// Static image cache shared across all browser instances
    private static let artworkCache = NSCache<NSString, NSImage>()
    
    // MARK: - Layout Constants (reference to SkinElements)
    
    private var Layout: SkinElements.PlexBrowser.Layout.Type {
        SkinElements.PlexBrowser.Layout.self
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        
        // Load saved column widths and sort
        loadColumnWidths()
        loadColumnSort()
        
        // Load saved source
        if let savedSource = BrowserSource.load() {
            // Validate saved source
            switch savedSource {
            case .local:
                currentSource = .local
            case .plex(let serverId):
                // Only restore Plex source if server still exists and user is linked
                if PlexManager.shared.isLinked {
                    if PlexManager.shared.servers.contains(where: { $0.id == serverId }) {
                        currentSource = savedSource
                    } else if PlexManager.shared.servers.isEmpty {
                        // Servers not loaded yet - defer restoration
                        pendingSourceRestore = savedSource
                        currentSource = .local  // Temporary
                    } else if let firstServer = PlexManager.shared.servers.first {
                        currentSource = .plex(serverId: firstServer.id)
                    } else {
                        currentSource = .local
                    }
                } else {
                    currentSource = .local
                }
            case .subsonic(let serverId):
                // Only restore Subsonic source if server still exists
                if SubsonicManager.shared.servers.contains(where: { $0.id == serverId }) {
                    currentSource = savedSource
                } else if SubsonicManager.shared.servers.isEmpty {
                    // Servers not loaded yet - defer restoration
                    pendingSourceRestore = savedSource
                    currentSource = .local  // Temporary
                } else if let firstServer = SubsonicManager.shared.servers.first {
                    currentSource = .subsonic(serverId: firstServer.id)
                } else {
                    currentSource = .local
                }
            case .radio:
                currentSource = .radio
            }
        } else {
            // Default: local if not linked to Plex, otherwise first Plex server
            if PlexManager.shared.isLinked, let firstServer = PlexManager.shared.servers.first {
                currentSource = .plex(serverId: firstServer.id)
            } else {
                currentSource = .local
            }
        }
        
        // Load saved sort option
        currentSort = BrowserSortOption.load()
        
        // Art-only mode always starts disabled (don't persist across sessions)
        isArtOnlyMode = false
        
        // Load saved visualizer preferences
        if let savedEffect = UserDefaults.standard.string(forKey: "browserVisEffect"),
           let effect = VisEffect(rawValue: savedEffect) {
            currentVisEffect = effect
        }
        if UserDefaults.standard.object(forKey: "browserVisIntensity") != nil {
            visEffectIntensity = CGFloat(UserDefaults.standard.double(forKey: "browserVisIntensity"))
        }
        
        // Observe Plex manager changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(plexStateDidChange),
            name: PlexManager.accountDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(plexStateDidChange),
            name: PlexManager.libraryDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(plexStateDidChange),
            name: PlexManager.connectionStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(plexServerDidChange),
            name: PlexManager.serversDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(plexContentDidPreload),
            name: PlexManager.libraryContentDidPreloadNotification,
            object: nil
        )
        
        // Observe MediaLibrary changes for local source
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mediaLibraryDidChange),
            name: MediaLibrary.libraryDidChangeNotification,
            object: nil
        )
        
        // Observe RadioManager changes for radio source
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(radioStationsDidChange),
            name: RadioManager.stationsDidChangeNotification,
            object: nil
        )
        
        // Observe track changes for artwork background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trackDidChange),
            name: .audioTrackDidChange,
            object: nil
        )
        
        // Register for drag and drop (local files)
        registerForDraggedTypes([.fileURL])
        
        // Initial data load
        reloadData()
        
        // Start server name scroll animation
        startServerNameScroll()
        
        // Load artwork for currently playing track (if any)
        if WindowManager.shared.showBrowserArtworkBackground {
            loadArtwork(for: WindowManager.shared.audioEngine.currentTrack)
        }
        
        // Set up accessibility identifiers for UI testing
        setupAccessibility()
    }
    
    // MARK: - Accessibility
    
    /// Set up accessibility identifiers for UI testing
    private func setupAccessibility() {
        setAccessibilityIdentifier("plexBrowserView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Plex Browser")
    }
    
    // MARK: - Visualizer Animation
    
    /// Start the visualizer animation timer
    private func startVisualizerTimer() {
        visualizerTime = 0
        silenceFrames = 0
        visualizerTimer?.invalidate()
        // 60fps for smooth trippy effects
        // Use .common run loop mode so timer continues during context menu display
        let timer = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.visualizerTime += 1.0/60.0
            
            // Check audio level - only animate when music is playing
            let spectrumData = WindowManager.shared.audioEngine.spectrumData
            let currentLevel = spectrumData.reduce(0, +) / Float(spectrumData.count)
            
            // Detect silence (very low audio level)
            if currentLevel < 0.001 {
                self.silenceFrames += 1
                // After ~0.5 seconds of silence, stop animating
                if self.silenceFrames > 30 {
                    return // Don't redraw during silence
                }
            } else {
                self.silenceFrames = 0
                
                // Handle random mode - change on beats
                if self.visMode == .random {
                    let bass = spectrumData.prefix(10).reduce(0, +) / 10.0
                    if bass > 0.5 && self.visualizerTime - self.lastBeatTime > 0.3 {
                        self.lastBeatTime = self.visualizerTime
                        // Random chance to change effect on beat
                        if Double.random(in: 0...1) < 0.3 {
                            let effects = VisEffect.allCases
                            self.currentVisEffect = effects.randomElement() ?? .psychedelic
                        }
                    }
                }
            }
            
            self.lastAudioLevel = currentLevel
            
            // Only redraw the visualization content area, not the entire view
            // This prevents menu items (title bar, server bar) from shimmering on non-Retina displays
            let contentY = self.Layout.titleBarHeight + self.Layout.serverBarHeight
            let contentHeight = self.bounds.height - contentY - self.Layout.statusBarHeight
            // Convert from Winamp top-down coordinates to macOS bottom-up coordinates
            let nativeY = self.Layout.statusBarHeight
            let contentRect = NSRect(x: 0, y: nativeY, width: self.bounds.width, height: contentHeight)
            self.setNeedsDisplay(contentRect)
        }
        RunLoop.main.add(timer, forMode: .common)
        visualizerTimer = timer
        
        // Start cycle timer if in cycle mode
        if visMode == .cycle {
            startCycleTimer()
        }
    }
    
    /// Stop the visualizer animation timer
    private func stopVisualizerTimer() {
        visualizerTimer?.invalidate()
        visualizerTimer = nil
        cycleTimer?.invalidate()
        cycleTimer = nil
    }
    
    /// Start cycle mode timer
    private func startCycleTimer() {
        cycleTimer?.invalidate()
        // Use .common run loop mode so timer continues during context menu display
        let timer = Timer(timeInterval: cycleInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.visMode == .cycle else { return }
            let effects = VisEffect.allCases
            if let currentIndex = effects.firstIndex(of: self.currentVisEffect) {
                let nextIndex = (currentIndex + 1) % effects.count
                self.currentVisEffect = effects[nextIndex]
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cycleTimer = timer
    }
    
    /// Toggle visualization mode
    func toggleVisualization() {
        guard isArtOnlyMode && currentArtwork != nil else { return }
        isVisualizingArt.toggle()
    }
    
    // MARK: - Rating Overlay
    
    /// Lazy rating overlay view
    private lazy var ratingOverlay: RatingOverlayView = {
        let overlay = RatingOverlayView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        overlay.onRatingSelected = { [weak self] rating in
            self?.submitRating(rating)
        }
        overlay.onDismiss = { [weak self] in
            self?.hideRatingOverlay()
        }
        addSubview(overlay)
        return overlay
    }()
    
    /// Show the rating overlay
    private func showRatingOverlay() {
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack,
              currentTrack.plexRatingKey != nil else { return }
        
        ratingOverlay.frame = bounds
        ratingOverlay.setRating(currentTrackRating ?? 0)
        ratingOverlay.isHidden = false
        isRatingOverlayVisible = true
        needsDisplay = true
    }
    
    /// Hide the rating overlay
    private func hideRatingOverlay() {
        ratingOverlay.isHidden = true
        isRatingOverlayVisible = false
        ratingSubmitTask?.cancel()  // Cancel any pending submission
        ratingSubmitTask = nil
        needsDisplay = true
    }
    
    /// Submit rating to Plex (debounced to prevent rapid API calls)
    private func submitRating(_ rating: Int) {
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack,
              let ratingKey = currentTrack.plexRatingKey else { return }
        
        // Update UI immediately for responsiveness
        currentTrackRating = rating
        needsDisplay = true
        
        // Cancel any pending submission
        ratingSubmitTask?.cancel()
        
        // Debounce: wait 500ms before submitting to allow rapid selection changes
        ratingSubmitTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s debounce
                
                // Check if cancelled during debounce
                try Task.checkCancellation()
                
                try await PlexManager.shared.serverClient?.rateItem(ratingKey: ratingKey, rating: rating)
                NSLog("PlexBrowser: Rated track %@ with %d stars", ratingKey, rating / 2)
                
                // Dismiss after short delay to show the selection
                try await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
                await MainActor.run {
                    hideRatingOverlay()
                }
            } catch is CancellationError {
                // Cancelled by newer selection - ignore
            } catch {
                NSLog("PlexBrowser: Failed to rate track: %@", error.localizedDescription)
            }
        }
    }
    
    /// Fetch current track's rating from Plex
    private func fetchCurrentTrackRating() {
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack,
              let ratingKey = currentTrack.plexRatingKey else {
            currentTrackRating = nil
            return
        }
        
        Task {
            do {
                if let trackDetails = try await PlexManager.shared.serverClient?.fetchTrackDetails(trackID: ratingKey) {
                    await MainActor.run {
                        if let userRating = trackDetails.userRating {
                            currentTrackRating = Int(userRating)
                            NSLog("PlexBrowser: Fetched rating %d for track %@", Int(userRating), ratingKey)
                        } else {
                            currentTrackRating = nil
                        }
                        needsDisplay = true
                    }
                }
            } catch {
                NSLog("PlexBrowser: Failed to fetch track rating: %@", error.localizedDescription)
            }
        }
    }
    
    /// Called when source changes
    private func onSourceChanged() {
        // Clear all cached data for both sources
        clearAllCachedData()
        clearLocalCachedData()
        
        // Clear display items to avoid showing stale data
        displayItems.removeAll()
        
        // Reset UI state
        selectedIndices.removeAll()
        scrollOffset = 0
        errorMessage = nil
        isLoading = false
        stopLoadingAnimation()
        
        // Sync browse mode with radio source
        if case .radio = currentSource {
            // When switching to Internet Radio source, automatically switch to radio tab
            browseMode = .radio
        } else if browseMode == .radio, case .local = currentSource {
            // When switching to Local source from radio tab, switch to artists tab
            // (Plex and Subsonic modes support radio tab for Plex Radio)
            browseMode = .artists
        } else if browseMode == .radio, case .subsonic = currentSource {
            // Subsonic doesn't support radio tab, switch to artists tab
            browseMode = .artists
        }
        
        // Reload data for new source
        reloadData()
    }
    
    /// Clear local cached data
    private func clearLocalCachedData() {
        cachedLocalArtists = []
        cachedLocalAlbums = []
        cachedLocalTracks = []
        expandedLocalArtists = []
        expandedLocalAlbums = []
    }
    
    @objc private func mediaLibraryDidChange() {
        // Only reload if we're showing local content (not on radio tab)
        guard case .local = currentSource else { return }
        guard browseMode != .radio else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.browseMode != .radio else { return }
            self.loadLocalData()
            self.needsDisplay = true
        }
    }
    
    @objc private func plexContentDidPreload() {
        // When PlexManager finishes preloading content, reload our data
        reloadData()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopLoadingAnimation()
        stopServerNameScroll()
    }
    
    // MARK: - Scaling Support
    
    /// Get the original window size for drawing and hit testing
    /// Normal mode uses actual bounds (no scaling), shade mode uses fixed reference size
    private var originalWindowSize: NSSize {
        if isShadeMode {
            // Shade mode: uses fixed reference size for scaling
            return NSSize(width: SkinElements.PlexBrowser.minSize.width, height: SkinElements.PlexBrowser.shadeHeight)
        } else {
            // Normal mode: use actual bounds, no scaling
            return bounds.size
        }
    }
    
    /// Calculate scale factor based on current bounds vs original (base) size
    /// Normal mode has no scaling (1.0), shade mode scales uniformly
    private var scaleFactor: CGFloat {
        if isShadeMode {
            // Shade mode scales uniformly based on width
            return bounds.width / SkinElements.PlexBrowser.minSize.width
        } else {
            // Normal mode: no scaling, UI stays at fixed pixel size
            return 1.0
        }
    }
    
    /// Convert a point from view coordinates to Winamp coordinates (top-left origin)
    private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
        if isShadeMode {
            // Shade mode uses uniform scaling with centering
            let scale = scaleFactor
            let originalSize = originalWindowSize
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            let offsetY = (bounds.height - scaledHeight) / 2
            
            let x = (point.x - offsetX) / scale
            let y = originalSize.height - ((point.y - offsetY) / scale)
            return NSPoint(x: x, y: y)
        } else {
            // Normal mode: no scaling, just flip Y coordinate (macOS bottom-left to Winamp top-left)
            return NSPoint(x: point.x, y: bounds.height - point.y)
        }
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        // Capture artwork reference to prevent release during draw cycle.
        // An async Task may replace currentArtwork mid-draw, causing the old
        // image to be deallocated while Core Animation still references it.
        let capturedArtwork = currentArtwork
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let originalSize = originalWindowSize
        let scale = scaleFactor
        
        // Use default skin if locked, otherwise use current skin
        let skin: Skin
        if WindowManager.shared.lockBrowserMilkdropSkin {
            skin = SkinLoader.shared.loadDefault()
        } else {
            skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        }
        let renderer = SkinRenderer(skin: skin)
        let isActive = window?.isKeyWindow ?? true
        
        // Flip coordinate system to match Winamp's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // Use low interpolation for cleaner scaling of skin sprites (none can cause artifacts)
        context.interpolationQuality = .low
        
        // Apply scaling for resized window (only shade mode uses scaling)
        if isShadeMode && scale != 1.0 {
            // Shade mode uses uniform scaling, centered
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            let offsetY = (bounds.height - scaledHeight) / 2
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)
        }
        // Normal mode: no transform needed, scale is always 1.0
        
        // Use original bounds for drawing (scaling is applied via transform)
        let drawBounds = NSRect(origin: .zero, size: originalSize)
        
        if isShadeMode {
            renderer.drawPlexBrowserShade(in: context, bounds: drawBounds, isActive: isActive,
                                          pressedButton: pressedButton)
        } else {
            // Calculate scroll position for scrollbar (0-1)
            let scrollPosition = calculateScrollPosition()
            
            // Draw window frame using skin sprites
            renderer.drawPlexBrowserWindow(in: context, bounds: drawBounds, isActive: isActive,
                                           pressedButton: pressedButton, scrollPosition: scrollPosition)
            
            
            // Get skin colors for content areas
            let colors = skin.playlistColors
            
            // Draw server/library selector bar
            drawServerBar(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
            
            if isArtOnlyMode {
                // Art-only mode: skip tabs and list, draw album art large
                drawArtOnlyArea(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer, artwork: capturedArtwork)
            } else {
                // Normal mode: draw tabs, search, and list
                
                // Draw tab bar
                drawTabBar(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
                
                // Draw search bar (only in search mode)
                if browseMode == .search {
                    drawSearchBar(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
                }
                
                // Draw list area or connection status
                // Only check Plex link status if using Plex source
                let needsPlexLink = currentSource.isPlex && !PlexManager.shared.isLinked
                if needsPlexLink {
                    drawNotLinkedState(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
                } else if isLoading {
                    drawLoadingState(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
                } else if let error = errorMessage {
                    drawErrorState(in: context, drawBounds: drawBounds, message: error, colors: colors, renderer: renderer)
                } else {
                    drawListArea(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer, artwork: capturedArtwork)
                }
                
                // Draw status bar text
                drawStatusBarText(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
            }
        }
        
        context.restoreGState()
    }
    
    /// Calculate scroll position as 0-1 value
    private func calculateScrollPosition() -> CGFloat {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
        let totalContentHeight = CGFloat(displayItems.count) * itemHeight
        
        guard totalContentHeight > listHeight else { return 0 }
        
        let scrollRange = totalContentHeight - listHeight
        return min(1, max(0, scrollOffset / scrollRange))
    }
    
    // MARK: - Content Drawing (in Winamp coordinates, using skin text font)
    
    /// Helper to draw scaled skin text (green)
    private func drawScaledSkinText(_ text: String, at position: NSPoint, scale: CGFloat, renderer: SkinRenderer, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: position.x, y: position.y)
        context.scaleBy(x: scale, y: scale)
        renderer.drawSkinText(text, at: NSPoint(x: 0, y: 0), in: context)
        context.restoreGState()
    }
    
    /// Helper to draw scaled white skin text
    private func drawScaledWhiteSkinText(_ text: String, at position: NSPoint, scale: CGFloat, renderer: SkinRenderer, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: position.x, y: position.y)
        context.scaleBy(x: scale, y: scale)
        renderer.drawSkinTextWhite(text, at: NSPoint(x: 0, y: 0), in: context)
        context.restoreGState()
    }
    
    /// Helper to draw scaled white skin text centered in a rect
    private func drawScaledWhiteSkinTextCentered(_ text: String, in rect: NSRect, scale: CGFloat, renderer: SkinRenderer, in context: CGContext) {
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let textWidth = CGFloat(text.count) * charWidth * scale
        let textHeight = charHeight * scale
        let rawX = rect.midX - textWidth / 2
        let rawY = rect.midY - textHeight / 2
        // Round coordinates on non-Retina to prevent shimmering
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let x = backingScale < 1.5 ? round(rawX) : rawX
        let y = backingScale < 1.5 ? round(rawY) : rawY
        drawScaledWhiteSkinText(text, at: NSPoint(x: x, y: y), scale: scale, renderer: renderer, in: context)
    }
    
    /// Draw a low-res pixel-art star for server bar rating display
    /// Uses a bitmap pattern for authentic retro look
    private func drawPixelStar(in rect: NSRect, color: NSColor, context: CGContext) {
        // 9x9 pixel art star pattern (1 = filled, 0 = empty)
        // Classic chunky star shape (top-down for flipped Winamp context)
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
                    let y = rect.minY + CGFloat(row) * pixelH
                    context.fill(CGRect(x: x, y: y, width: ceil(pixelW), height: ceil(pixelH)))
                }
            }
        }
    }
    
    private func drawServerBar(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        let barY = Layout.titleBarHeight
        let barRect = NSRect(x: Layout.leftBorder, y: barY,
                            width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                            height: Layout.serverBarHeight)
        
        // Background - use fully opaque on non-Retina to prevent compositing artifacts
        let backingScaleForBg = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScaleForBg < 1.5 {
            colors.normalBackground.setFill()
        } else {
            colors.normalBackground.withAlphaComponent(0.6).setFill()
        }
        context.fill(barRect)
        
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        let scaledCharHeight = charHeight * textScale
        // Round textY to prevent shimmering on non-Retina displays
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let rawTextY = barRect.minY + (barRect.height - scaledCharHeight) / 2
        let textY = backingScale < 1.5 ? round(rawTextY) : rawTextY
        
        // Common prefix for all sources
        let prefix = "Source: "
        drawScaledSkinText(prefix, at: NSPoint(x: barRect.minX + 4, y: textY), scale: textScale, renderer: renderer, in: context)
        let prefixWidth = CGFloat(prefix.count) * scaledCharWidth
        let sourceNameStartX = barRect.minX + 4 + prefixWidth
        
        switch currentSource {
        case .local:
            // LOCAL FILES mode
            let sourceText = "Local Files"
            drawScaledWhiteSkinText(sourceText, at: NSPoint(x: sourceNameStartX, y: textY), scale: textScale, renderer: renderer, in: context)
            let sourceTextWidth = CGFloat(sourceText.count) * scaledCharWidth
            
            // +ADD button after source name with balanced spacing (green text)
            let addText = "+ADD"
            let addX = sourceNameStartX + sourceTextWidth + 28
            drawScaledSkinText(addText, at: NSPoint(x: addX, y: textY), scale: textScale, renderer: renderer, in: context)
            
            // Right side: F5 refresh label
            let refreshText = "F5"
            let refreshX = barRect.maxX - (CGFloat(refreshText.count) * scaledCharWidth) - 8
            drawScaledSkinText(refreshText, at: NSPoint(x: refreshX, y: textY), scale: textScale, renderer: renderer, in: context)
            
            // In art-only mode, use tighter spacing for right side items
            let artModeSpacing: CGFloat = isArtOnlyMode ? 12 : 24
            let artModeVisSpacing: CGFloat = isArtOnlyMode ? 8 : 16
            
            // ART toggle button (before F5) - only show if artwork available
            let artText = "ART"
            let artWidth = CGFloat(artText.count) * scaledCharWidth
            var artX = refreshX - artWidth - artModeSpacing
            
            // VIS button - only show in art-only mode
            let visText = "VIS"
            let visWidth = CGFloat(visText.count) * scaledCharWidth
            var visX = artX - visWidth - artModeVisSpacing
            
            if currentArtwork != nil {
                if isArtOnlyMode {
                    drawScaledWhiteSkinText(artText, at: NSPoint(x: artX, y: textY), scale: textScale, renderer: renderer, in: context)
                    // Show VIS button in art-only mode (white when active, green when inactive)
                    if isVisualizingArt {
                        drawScaledWhiteSkinText(visText, at: NSPoint(x: visX, y: textY), scale: textScale, renderer: renderer, in: context)
                    } else {
                        drawScaledSkinText(visText, at: NSPoint(x: visX, y: textY), scale: textScale, renderer: renderer, in: context)
                    }
                } else {
                    drawScaledSkinText(artText, at: NSPoint(x: artX, y: textY), scale: textScale, renderer: renderer, in: context)
                    visX = artX  // No VIS button, shift items
                }
            } else {
                // No artwork - shift items over to where ART would be
                artX = refreshX
                visX = artX  // No VIS button
            }
            
            // Item count (before VIS or before ART if no art-only mode)
            let countNumber = "\(displayItems.count)"
            let countLabel = " items"
            let countWidth = CGFloat(countNumber.count + countLabel.count) * scaledCharWidth
            let countX = visX - countWidth - 24
            drawScaledWhiteSkinText(countNumber, at: NSPoint(x: countX, y: textY), scale: textScale, renderer: renderer, in: context)
            let labelX = countX + CGFloat(countNumber.count) * scaledCharWidth
            drawScaledWhiteSkinText(countLabel, at: NSPoint(x: labelX, y: textY), scale: textScale, renderer: renderer, in: context)
            
        case .plex(let serverId):
            let manager = PlexManager.shared
            
            // Check if we have a server configured (even if offline)
            let configuredServer = manager.servers.first(where: { $0.id == serverId })
            let hasConfiguredServer = configuredServer != nil || manager.isLinked
            
            if hasConfiguredServer {
                // Max widths for server and library names (in characters)
                let maxServerChars = 12
                let maxLibraryChars = 10
                let maxServerWidth = CGFloat(maxServerChars) * scaledCharWidth
                let maxLibraryWidth = CGFloat(maxLibraryChars) * scaledCharWidth
                
                // Server name right after "Source:" - with clipping to prevent artifacts
                let serverName = configuredServer?.name ?? "Select Server"
                let serverTextWidth = CGFloat(serverName.count) * scaledCharWidth
                
                context.saveGState()
                let serverClipRect = NSRect(x: sourceNameStartX, y: textY, width: maxServerWidth, height: scaledCharHeight)
                context.clip(to: serverClipRect)
                if serverTextWidth <= maxServerWidth {
                    drawScaledWhiteSkinText(serverName, at: NSPoint(x: sourceNameStartX, y: textY), scale: textScale, renderer: renderer, in: context)
                } else {
                    drawScrollingText(serverName, startX: sourceNameStartX, textY: textY,
                                     availableWidth: maxServerWidth, scale: textScale,
                                     scrollOffset: serverNameScrollOffset,
                                     renderer: renderer, in: context)
                }
                context.restoreGState()
                
                // Library label and name after server name
                let libLabel = "Lib:"
                let libraryLabelX = sourceNameStartX + maxServerWidth + 16
                drawScaledSkinText(libLabel, at: NSPoint(x: libraryLabelX, y: textY), scale: textScale, renderer: renderer, in: context)
                
                let libraryX = libraryLabelX + CGFloat(libLabel.count) * scaledCharWidth + 4
                let libraryText = manager.currentLibrary?.title ?? "Select"
                let libraryTextWidth = CGFloat(libraryText.count) * scaledCharWidth
                
                // Library name with clipping to prevent artifacts
                context.saveGState()
                let libraryClipRect = NSRect(x: libraryX, y: textY, width: maxLibraryWidth, height: scaledCharHeight)
                context.clip(to: libraryClipRect)
                if libraryTextWidth <= maxLibraryWidth {
                    drawScaledWhiteSkinText(libraryText, at: NSPoint(x: libraryX, y: textY), scale: textScale, renderer: renderer, in: context)
                } else {
                    drawScrollingText(libraryText, startX: libraryX, textY: textY,
                                     availableWidth: maxLibraryWidth, scale: textScale,
                                     scrollOffset: libraryNameScrollOffset,
                                     renderer: renderer, in: context)
                }
                context.restoreGState()
                
                // Right side: F5 refresh label
                let refreshText = "F5"
                let refreshX = barRect.maxX - (CGFloat(refreshText.count) * scaledCharWidth) - 8
                drawScaledSkinText(refreshText, at: NSPoint(x: refreshX, y: textY), scale: textScale, renderer: renderer, in: context)
                
                // In art-only mode, use tighter spacing for right side items
                let artModeSpacing: CGFloat = isArtOnlyMode ? 12 : 24
                let artModeVisSpacing: CGFloat = isArtOnlyMode ? 8 : 16
                
                // ART toggle button (before F5) - only show if artwork available
                let artText = "ART"
                let artWidth = CGFloat(artText.count) * scaledCharWidth
                var artX = refreshX - artWidth - artModeSpacing
                
                // VIS button - only show in art-only mode
                let visText = "VIS"
                let visWidth = CGFloat(visText.count) * scaledCharWidth
                var visX = artX - visWidth - artModeVisSpacing
                
                if currentArtwork != nil {
                    if isArtOnlyMode {
                        drawScaledWhiteSkinText(artText, at: NSPoint(x: artX, y: textY), scale: textScale, renderer: renderer, in: context)
                        // Show VIS button in art-only mode (white when active, green when inactive)
                        if isVisualizingArt {
                            drawScaledWhiteSkinText(visText, at: NSPoint(x: visX, y: textY), scale: textScale, renderer: renderer, in: context)
                        } else {
                            drawScaledSkinText(visText, at: NSPoint(x: visX, y: textY), scale: textScale, renderer: renderer, in: context)
                        }
                    } else {
                        drawScaledSkinText(artText, at: NSPoint(x: artX, y: textY), scale: textScale, renderer: renderer, in: context)
                        visX = artX  // No VIS button, shift items
                    }
                } else {
                    // No artwork - shift items over to where ART would be
                    artX = refreshX
                    visX = artX  // No VIS button
                }
                
                // Item count or RATE button (positioned from right side)
                // In art-only mode with Plex track playing, show RATE instead of item count
                let countSpacing: CGFloat = isArtOnlyMode ? 12 : 24
                
                if isArtOnlyMode,
                   let currentTrack = WindowManager.shared.audioEngine.currentTrack,
                   currentTrack.plexRatingKey != nil {
                    // Draw star rating in server bar - larger green stars
                    let starSize: CGFloat = 12
                    let starSpacing: CGFloat = 2
                    let totalStars = 5
                    let starsWidth = CGFloat(totalStars) * starSize + CGFloat(totalStars - 1) * starSpacing
                    let starsX = visX - starsWidth - countSpacing
                    let starY = barRect.minY + (barRect.height - starSize) / 2
                    
                    // Get current rating (0-10 scale -> 0-5 filled stars)
                    let rating = currentTrackRating ?? 0
                    let filledCount = rating / 2
                    
                    // Use skin's actual text.bmp color for stars (sampled from font bitmap)
                    let greenColor = renderer.skinTextColor()
                    let dimGreen = NSColor(red: greenColor.redComponent * 0.4,
                                          green: greenColor.greenComponent * 0.4,
                                          blue: greenColor.blueComponent * 0.4,
                                          alpha: 0.6)
                    
                    // Draw 5 stars
                    for i in 0..<totalStars {
                        let x = starsX + CGFloat(i) * (starSize + starSpacing)
                        let starRect = NSRect(x: x, y: starY, width: starSize, height: starSize)
                        let isFilled = i < filledCount
                        drawPixelStar(in: starRect, color: isFilled ? greenColor : dimGreen, context: context)
                    }
                    
                    // Store hit rect for click detection (covers all stars)
                    rateButtonRect = NSRect(x: starsX, y: barRect.minY, width: starsWidth, height: barRect.height)
                } else {
                    // Normal item count display
                    rateButtonRect = .zero
                    
                    // Show top-level item count (artists/albums/tracks), not expanded tree count
                    let itemCount: Int
                    if manager.currentLibrary?.type == "artist" {
                        itemCount = cachedArtists.count
                    } else if manager.currentLibrary?.type == "album" {
                        itemCount = cachedAlbums.count
                    } else if manager.currentLibrary?.type == "track" {
                        itemCount = cachedTracks.count
                    } else if manager.currentLibrary?.type == "movie" {
                        itemCount = cachedMovies.count
                    } else if manager.currentLibrary?.type == "show" {
                        itemCount = cachedShows.count
                    } else {
                        itemCount = displayItems.count
                    }
                    let countNumber = "\(itemCount)"
                    let countLabel = " ITEMS"
                    let countWidth = CGFloat(countNumber.count + countLabel.count) * scaledCharWidth
                    let countX = visX - countWidth - countSpacing
                    drawScaledWhiteSkinText(countNumber, at: NSPoint(x: countX, y: textY), scale: textScale, renderer: renderer, in: context)
                    let labelX = countX + CGFloat(countNumber.count) * scaledCharWidth
                    drawScaledWhiteSkinText(countLabel, at: NSPoint(x: labelX, y: textY), scale: textScale, renderer: renderer, in: context)
                }
            } else {
                // Plex not linked and no servers - show link message
                let linkText = "Click to link your Plex account"
                let linkWidth = CGFloat(linkText.count) * scaledCharWidth
                let linkX = barRect.midX - linkWidth / 2
                drawScaledSkinText(linkText, at: NSPoint(x: linkX, y: textY), scale: textScale, renderer: renderer, in: context)
            }
            
        case .subsonic(let serverId):
            let manager = SubsonicManager.shared
            
            // Check if we have a server configured (even if offline)
            let configuredServer = manager.servers.first(where: { $0.id == serverId })
            
            if configuredServer != nil {
                // Max width for server name (in characters)
                let maxServerChars = 20
                let maxServerWidth = CGFloat(maxServerChars) * scaledCharWidth
                
                // Server name right after "Source:"
                let serverName = configuredServer?.name ?? "Select Server"
                let serverTextWidth = CGFloat(serverName.count) * scaledCharWidth
                
                if serverTextWidth <= maxServerWidth {
                    drawScaledWhiteSkinText(serverName, at: NSPoint(x: sourceNameStartX, y: textY), scale: textScale, renderer: renderer, in: context)
                } else {
                    drawScrollingText(serverName, startX: sourceNameStartX, textY: textY,
                                     availableWidth: maxServerWidth, scale: textScale,
                                     scrollOffset: serverNameScrollOffset,
                                     renderer: renderer, in: context)
                }
                
                // Right side: F5 refresh label
                let refreshText = "F5"
                let refreshX = barRect.maxX - (CGFloat(refreshText.count) * scaledCharWidth) - 8
                drawScaledSkinText(refreshText, at: NSPoint(x: refreshX, y: textY), scale: textScale, renderer: renderer, in: context)
                
                // ART toggle button (before F5) - only show if artwork available
                let artText = "ART"
                let artWidth = CGFloat(artText.count) * scaledCharWidth
                var artX = refreshX - artWidth - 24
                
                // VIS button - only show in art-only mode
                let visText = "VIS"
                let visWidth = CGFloat(visText.count) * scaledCharWidth
                var visX = artX - visWidth - 16
                
                if currentArtwork != nil {
                    if isArtOnlyMode {
                        drawScaledWhiteSkinText(artText, at: NSPoint(x: artX, y: textY), scale: textScale, renderer: renderer, in: context)
                        if isVisualizingArt {
                            drawScaledWhiteSkinText(visText, at: NSPoint(x: visX, y: textY), scale: textScale, renderer: renderer, in: context)
                        } else {
                            drawScaledSkinText(visText, at: NSPoint(x: visX, y: textY), scale: textScale, renderer: renderer, in: context)
                        }
                    } else {
                        drawScaledSkinText(artText, at: NSPoint(x: artX, y: textY), scale: textScale, renderer: renderer, in: context)
                        visX = artX
                    }
                } else {
                    artX = refreshX
                    visX = artX
                }
                
                // Item count
                let countNumber = "\(displayItems.count)"
                let countLabel = " items"
                let countWidth = CGFloat(countNumber.count + countLabel.count) * scaledCharWidth
                let countX = visX - countWidth - 24
                drawScaledWhiteSkinText(countNumber, at: NSPoint(x: countX, y: textY), scale: textScale, renderer: renderer, in: context)
                let labelX = countX + CGFloat(countNumber.count) * scaledCharWidth
                drawScaledWhiteSkinText(countLabel, at: NSPoint(x: labelX, y: textY), scale: textScale, renderer: renderer, in: context)
            } else {
                // No Subsonic server configured - show add server message
                let linkText = "Click to add a Subsonic server"
                let linkWidth = CGFloat(linkText.count) * scaledCharWidth
                let linkX = barRect.midX - linkWidth / 2
                drawScaledSkinText(linkText, at: NSPoint(x: linkX, y: textY), scale: textScale, renderer: renderer, in: context)
            }
        
        case .radio:
            // INTERNET RADIO mode
            let sourceText = "Internet Radio"
            drawScaledWhiteSkinText(sourceText, at: NSPoint(x: sourceNameStartX, y: textY), scale: textScale, renderer: renderer, in: context)
            let sourceTextWidth = CGFloat(sourceText.count) * scaledCharWidth
            
            // +ADD button after source name (green text)
            let addText = "+ADD"
            let addX = sourceNameStartX + sourceTextWidth + 28
            drawScaledSkinText(addText, at: NSPoint(x: addX, y: textY), scale: textScale, renderer: renderer, in: context)
            
            // Right side: F5 refresh label
            let refreshText = "F5"
            let refreshX = barRect.maxX - (CGFloat(refreshText.count) * scaledCharWidth) - 8
            drawScaledSkinText(refreshText, at: NSPoint(x: refreshX, y: textY), scale: textScale, renderer: renderer, in: context)
            
            // Item count
            let countNumber = "\(displayItems.count)"
            let countLabel = " stations"
            let countWidth = CGFloat(countNumber.count + countLabel.count) * scaledCharWidth
            let countX = refreshX - countWidth - 24
            drawScaledWhiteSkinText(countNumber, at: NSPoint(x: countX, y: textY), scale: textScale, renderer: renderer, in: context)
            let labelX = countX + CGFloat(countNumber.count) * scaledCharWidth
            drawScaledWhiteSkinText(countLabel, at: NSPoint(x: labelX, y: textY), scale: textScale, renderer: renderer, in: context)
        }
    }
    
    /// Draw text with circular scrolling when it's too long
    private func drawScrollingText(_ text: String, startX: CGFloat, textY: CGFloat,
                                   availableWidth: CGFloat, scale: CGFloat,
                                   scrollOffset: CGFloat,
                                   renderer: SkinRenderer, in context: CGContext) {
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let scaledCharWidth = charWidth * scale
        let scaledCharHeight = charHeight * scale
        
        let textWidth = CGFloat(text.count) * scaledCharWidth
        let separator = "   "  // Separator for seamless wrap
        let separatorWidth = CGFloat(separator.count) * scaledCharWidth
        let totalCycleWidth = textWidth + separatorWidth
        
        // Clip to the available area
        context.saveGState()
        let clipRect = NSRect(x: startX, y: textY, width: availableWidth, height: scaledCharHeight)
        context.clip(to: clipRect)
        
        // Draw two copies of "text + separator" for seamless circular scrolling
        let fullText = text + separator
        
        for pass in 0..<2 {
            let baseX = startX - scrollOffset + (CGFloat(pass) * totalCycleWidth)
            
            // Check if this pass could be visible
            if baseX + totalCycleWidth < startX || baseX > startX + availableWidth {
                continue
            }
            
            // Draw text at calculated position using scaled white skin text
            context.saveGState()
            context.translateBy(x: baseX, y: textY)
            context.scaleBy(x: scale, y: scale)
            renderer.drawSkinTextWhite(fullText, at: NSPoint(x: 0, y: 0), in: context)
            context.restoreGState()
        }
        
        context.restoreGState()
    }
    
    private func drawTabBar(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        let tabBarY = Layout.titleBarHeight + Layout.serverBarHeight
        let tabBarRect = NSRect(x: Layout.leftBorder, y: tabBarY,
                               width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                               height: Layout.tabBarHeight)
        
        // Background - use fully opaque on non-Retina to prevent compositing artifacts
        let backingScaleForTabBg = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScaleForTabBg < 1.5 {
            colors.normalBackground.setFill()
        } else {
            colors.normalBackground.withAlphaComponent(0.4).setFill()
        }
        context.fill(tabBarRect)
        
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        let scaledCharHeight = charHeight * textScale
        
        // Round Y coordinates on non-Retina to prevent shimmering
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let shouldRound = backingScale < 1.5
        
        // Calculate sort indicator width (on the right)
        let sortText = "Sort"
        let sortWidth = CGFloat(sortText.count) * scaledCharWidth + 8
        
        // Draw tabs (leave room for sort indicator)
        let tabsWidth = tabBarRect.width - sortWidth
        let tabWidth = tabsWidth / CGFloat(PlexBrowseMode.allCases.count)
        
        for (index, mode) in PlexBrowseMode.allCases.enumerated() {
            let tabRect = NSRect(x: tabBarRect.minX + CGFloat(index) * tabWidth, y: tabBarY,
                                width: tabWidth, height: Layout.tabBarHeight)
            
            let isSelected = mode == browseMode
            
            if isSelected {
                // Selected tab in WHITE skin text
                drawScaledWhiteSkinTextCentered(mode.title, in: tabRect, scale: textScale, renderer: renderer, in: context)
            } else {
                // Unselected tabs in green skin text
                let titleWidth = CGFloat(mode.title.count) * scaledCharWidth
                let rawTextX = tabRect.midX - titleWidth / 2
                let rawTextY = tabRect.minY + (tabRect.height - scaledCharHeight) / 2
                let textX = shouldRound ? round(rawTextX) : rawTextX
                let textY = shouldRound ? round(rawTextY) : rawTextY
                drawScaledSkinText(mode.title, at: NSPoint(x: textX, y: textY), scale: textScale, renderer: renderer, in: context)
            }
        }
        
        // Draw sort indicator on the right
        let rawSortX = tabBarRect.maxX - sortWidth + 4
        let rawSortY = tabBarY + (Layout.tabBarHeight - scaledCharHeight) / 2
        let sortX = shouldRound ? round(rawSortX) : rawSortX
        let sortY = shouldRound ? round(rawSortY) : rawSortY
        drawScaledSkinText(sortText, at: NSPoint(x: sortX, y: sortY), scale: textScale, renderer: renderer, in: context)
    }
    
    private func drawSearchBar(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        let searchY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        let searchRect = NSRect(x: Layout.leftBorder + Layout.padding, y: searchY + 3,
                               width: drawBounds.width - Layout.leftBorder - Layout.rightBorder - Layout.padding * 2,
                               height: Layout.searchBarHeight - 6)
        
        // Search field background
        let isFocused = window?.firstResponder === self
        let bgColor = isFocused
            ? colors.selectedBackground.withAlphaComponent(0.5)
            : colors.normalBackground.withAlphaComponent(0.3)
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: searchRect, xRadius: 3, yRadius: 3)
        path.fill()
        
        // Focus border
        if isFocused {
            colors.currentText.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let textY = searchRect.minY + (searchRect.height - charHeight) / 2
        
        // Search text or placeholder using skin font
        let displayText = searchQuery.isEmpty ? "Type to search..." : searchQuery
        renderer.drawSkinText(displayText, at: NSPoint(x: searchRect.minX + 6, y: textY), in: context)
        
        // Draw cursor if focused
        if isFocused && !searchQuery.isEmpty {
            let cursorX = searchRect.minX + 6 + CGFloat(searchQuery.count) * charWidth + 1
            colors.normalText.setFill()
            context.fill(CGRect(x: cursorX, y: textY, width: 1, height: charHeight))
        }
    }
    
    private func drawNotLinkedState(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = drawBounds.height - listY - Layout.statusBarHeight
        let listRect = NSRect(x: Layout.leftBorder, y: listY,
                             width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                             height: listHeight)
        
        // Counter-flip for text
        context.saveGState()
        let centerY = listRect.midY
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        let message = "Link your Plex account to browse your music library"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: colors.normalText.withAlphaComponent(0.6),
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2),
                    withAttributes: attrs)
        
        // Link button hint
        let hint = "Click the server bar above to link"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(calibratedRed: 0.9, green: 0.6, blue: 0.1, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        hint.draw(at: NSPoint(x: listRect.midX - hintSize.width / 2, y: listRect.midY - size.height / 2 - 20),
                 withAttributes: hintAttrs)
        
        context.restoreGState()
    }
    
    private func drawLoadingState(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = drawBounds.height - listY - Layout.statusBarHeight
        let listRect = NSRect(x: Layout.leftBorder, y: listY,
                             width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                             height: listHeight)
        
        let centerY = listRect.midY
        let centerX = listRect.midX
        
        // Draw animated spinner
        let innerRadius: CGFloat = 5
        let outerRadius: CGFloat = 12
        let numSegments = 8
        let segmentAngle = CGFloat.pi * 2 / CGFloat(numSegments)
        
        for i in 0..<numSegments {
            let angle = CGFloat(i) * segmentAngle - CGFloat.pi / 2 + CGFloat(loadingAnimationFrame) * segmentAngle
            let alpha = CGFloat(i + 1) / CGFloat(numSegments)
            
            colors.normalText.withAlphaComponent(alpha).setStroke()
            context.setLineWidth(2.5)
            
            let startX = centerX + cos(angle) * innerRadius
            let startY = centerY + sin(angle) * innerRadius
            let endX = centerX + cos(angle) * outerRadius
            let endY = centerY + sin(angle) * outerRadius
            
            context.move(to: CGPoint(x: startX, y: startY))
            context.addLine(to: CGPoint(x: endX, y: endY))
            context.strokePath()
        }
        
        // Start animation timer if not running
        startLoadingAnimation()
    }
    
    private func drawErrorState(in context: CGContext, drawBounds: NSRect, message: String, colors: PlaylistColors, renderer: SkinRenderer) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = drawBounds.height - listY - Layout.statusBarHeight
        let listRect = NSRect(x: Layout.leftBorder, y: listY,
                             width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                             height: listHeight)
        
        // Counter-flip for text
        context.saveGState()
        let centerY = listRect.midY
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: colors.normalText.withAlphaComponent(0.6),
            .font: NSFont.systemFont(ofSize: 11)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2),
                    withAttributes: attrs)
        
        context.restoreGState()
    }
    
    private func drawEmptyState(in context: CGContext, listRect: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        // Determine empty message based on mode and library type
        let library = PlexManager.shared.currentLibrary
        let message: String
        
        switch browseMode {
        case .artists, .albums, .tracks:
            if library?.isMusicLibrary == true {
                message = "No \(browseMode.title.lowercased()) found"
            } else {
                message = "This library doesn't contain music"
            }
        case .movies:
            if library?.isMovieLibrary == true {
                message = "No movies found"
            } else {
                message = "This library doesn't contain movies"
            }
        case .shows:
            if library?.isShowLibrary == true {
                message = "No TV shows found"
            } else {
                message = "This library doesn't contain TV shows"
            }
        case .plists:
            message = "No playlists found"
        case .search:
            message = searchQuery.isEmpty ? "Type to search" : "No results found"
        case .radio:
            message = "No radio stations found"
        }
        
        // Draw using green skin text, centered
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        let scaledCharHeight = charHeight * textScale
        let textWidth = CGFloat(message.count) * scaledCharWidth
        let textX = listRect.midX - textWidth / 2
        let textY = listRect.midY - scaledCharHeight / 2
        
        drawScaledSkinText(message, at: NSPoint(x: textX, y: textY), scale: textScale, renderer: renderer, in: context)
    }
    
    private func drawListArea(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer, artwork: NSImage?) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = drawBounds.height - listY - Layout.statusBarHeight
        
        // Account for alphabet index on the right
        let alphabetWidth = Layout.alphabetWidth
        let fullListRect = NSRect(x: Layout.leftBorder, y: listY,
                                  width: drawBounds.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth - alphabetWidth,
                                  height: listHeight)
        
        // Show empty state message if no items
        if displayItems.isEmpty {
            drawEmptyState(in: context, listRect: fullListRect, colors: colors, renderer: renderer)
            return
        }
        
        // Determine which columns to show in header (priority: tracks > albums > artists)
        let headerColumns: [BrowserColumn]?
        if displayItems.contains(where: { 
            switch $0.type { 
            case .track, .subsonicTrack, .localTrack: return true 
            default: return false 
            }
        }) {
            headerColumns = BrowserColumn.trackColumns
        } else if displayItems.contains(where: {
            switch $0.type {
            case .album, .subsonicAlbum, .localAlbum: return true
            default: return false
            }
        }) {
            headerColumns = BrowserColumn.albumColumns
        } else if displayItems.contains(where: {
            switch $0.type {
            case .artist, .subsonicArtist, .localArtist: return true
            default: return false
            }
        }) {
            headerColumns = BrowserColumn.artistColumns
        } else {
            headerColumns = nil
        }
        
        // Draw column headers BEFORE clipping (so they stay fixed)
        var contentListY = listY
        if let columns = headerColumns {
            let headerRect = NSRect(x: fullListRect.minX, y: listY,
                                    width: fullListRect.width, height: columnHeaderHeight)
            drawColumnHeaders(in: context, rect: headerRect, columns: columns, colors: colors)
            contentListY += columnHeaderHeight
        }
        
        // Calculate content area (excluding headers)
        let contentHeight = listHeight - (headerColumns != nil ? columnHeaderHeight : 0)
        let listRect = NSRect(x: fullListRect.minX, y: contentListY,
                              width: fullListRect.width, height: contentHeight)
        
        // Clip to content area (below headers)
        context.saveGState()
        context.clip(to: listRect)
        
        // On non-Retina displays, fill the entire list area with background color first
        // to prevent any gaps/lines showing through between items
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScale < 1.5 {
            colors.normalBackground.setFill()
            context.fill(listRect)
        }
        
        // Draw album art background if enabled and available
        if WindowManager.shared.showBrowserArtworkBackground, let artworkImage = artwork,
           let cgImage = artworkImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.saveGState()
            
            // Calculate centered fill rect (scale to fill, center, maintain aspect ratio)
            let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
            let artworkRect = calculateCenterFillRect(imageSize: imageSize, in: listRect)
            
            // Set low opacity for subtle background
            context.setAlpha(0.12)
            
            // Draw the image - CGContext draws with origin at bottom-left, but we're in flipped Winamp coords
            // So we need to flip just for this image
            context.saveGState()
            context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
            context.restoreGState()
            
            context.restoreGState()
        }
        
        // Draw items
        // Round scroll offset to integer pixels to prevent text shimmering on non-Retina displays
        let roundedScrollOffset = backingScale < 1.5 ? round(scrollOffset) : scrollOffset
        
        let visibleStart = max(0, Int(scrollOffset / itemHeight))
        let visibleEnd = min(displayItems.count, visibleStart + Int(contentHeight / itemHeight) + 2)
        
        // Guard against invalid range during window resize/shade animation
        guard visibleStart < visibleEnd else {
            context.restoreGState()
            // Still draw alphabet index
            let alphabetRect = NSRect(x: drawBounds.width - Layout.rightBorder - Layout.scrollbarWidth - alphabetWidth,
                                     y: listY, width: alphabetWidth, height: listHeight)
            drawAlphabetIndex(in: context, rect: alphabetRect, colors: colors, renderer: renderer)
            return
        }
        
        for index in visibleStart..<visibleEnd {
            let y = contentListY + CGFloat(index) * itemHeight - roundedScrollOffset
            
            if y + itemHeight < contentListY || y > contentListY + contentHeight {
                continue
            }
            
            let itemRect = NSRect(x: listRect.minX, y: y, width: listRect.width, height: itemHeight)
            let item = displayItems[index]
            let isSelected = selectedIndices.contains(index)
            
            // On non-Retina displays, fill item background to prevent gaps/lines
            // BUT skip this when artwork background is showing (it already provides a continuous background)
            // On Retina, only fill background for selected items
            let hasArtworkBackground = WindowManager.shared.showBrowserArtworkBackground && artwork != nil
            if backingScale < 1.5 && !hasArtworkBackground {
                // Fill with normal or selected background (only when no artwork)
                let bgColor = isSelected ? colors.selectedBackground : colors.normalBackground
                bgColor.setFill()
                context.fill(itemRect)
            } else if isSelected {
                colors.selectedBackground.setFill()
                context.fill(itemRect)
            }
            
            // Check if this item type should use column rendering
            if let itemColumns = columnsForItem(item) {
                // Column-based rendering for tracks/albums
                let indent = CGFloat(item.indentLevel) * 16
                drawColumnRow(item: item, columns: itemColumns, in: context, rect: itemRect, 
                             isSelected: isSelected, colors: colors, indent: indent)
            } else {
                // Original rendering for artists, playlists, headers, etc.
                let indent = CGFloat(item.indentLevel) * 16
                let textX = itemRect.minX + indent + 4
                
                // Expand/collapse indicator for hierarchical items
                if item.hasChildren {
                    let expanded = isExpanded(item)
                    let indicator = expanded ? "▼" : "▶"
                    
                    // Counter-flip for indicator
                    context.saveGState()
                    let indicatorY = itemRect.midY
                    context.translateBy(x: 0, y: indicatorY)
                    context.scaleBy(x: 1, y: -1)
                    context.translateBy(x: 0, y: -indicatorY)
                    
                    let indicatorAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: colors.normalText.withAlphaComponent(0.6),
                        .font: NSFont.systemFont(ofSize: 8)
                    ]
                    indicator.draw(at: NSPoint(x: textX - 12, y: itemRect.midY - 5), withAttributes: indicatorAttrs)
                    
                    context.restoreGState()
                }
                
                // Main text (counter-flip)
                context.saveGState()
                let textCenterY = itemRect.midY
                context.translateBy(x: 0, y: textCenterY)
                context.scaleBy(x: 1, y: -1)
                context.translateBy(x: 0, y: -textCenterY)
                
                let textColor = isSelected ? colors.currentText : colors.normalText
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: textColor,
                    .font: NSFont.systemFont(ofSize: 10)
                ]
                
                let textRect = NSRect(x: textX, y: itemRect.minY + 2,
                                     width: itemRect.width - indent - 60, height: itemHeight - 4)
                item.title.draw(in: textRect, withAttributes: attrs)
                
                // Secondary info (only for non-column view)
                if let info = item.info {
                    let infoColor = isSelected ? colors.currentText : colors.normalText.withAlphaComponent(0.6)
                    let infoAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: infoColor,
                        .font: NSFont.systemFont(ofSize: 9)
                    ]
                    let infoSize = info.size(withAttributes: infoAttrs)
                    info.draw(at: NSPoint(x: itemRect.maxX - infoSize.width - 4, y: itemRect.midY - infoSize.height / 2),
                             withAttributes: infoAttrs)
                }
                
                context.restoreGState()
            }
        }
        
        context.restoreGState()
        
        // Draw alphabet index
        let alphabetRect = NSRect(x: drawBounds.width - Layout.rightBorder - Layout.scrollbarWidth - alphabetWidth,
                                 y: listY, width: alphabetWidth, height: listHeight)
        drawAlphabetIndex(in: context, rect: alphabetRect, colors: colors, renderer: renderer)
    }
    
    /// Draw column headers with separator line and resize handles
    private func drawColumnHeaders(in context: CGContext, rect: NSRect, columns: [BrowserColumn], colors: PlaylistColors) {
        // Clip to the header rect to prevent drawing over scrollbar/alphabet index
        context.saveGState()
        context.clip(to: rect)
        
        let totalWidth = rect.width
        
        // Calculate total columns width to determine if horizontal scroll is needed
        let columnsWidth = totalColumnsWidth(columns: columns)
        let maxHorizontalScroll = max(0, columnsWidth - totalWidth)
        
        // Clamp horizontal scroll offset
        if horizontalScrollOffset > maxHorizontalScroll {
            horizontalScrollOffset = maxHorizontalScroll
        }
        
        // Header background (slightly darker)
        colors.normalBackground.withAlphaComponent(0.9).setFill()
        context.fill(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: columnHeaderHeight))
        
        // Counter-flip for text drawing
        context.saveGState()
        let textCenterY = rect.minY + columnHeaderHeight / 2
        context.translateBy(x: 0, y: textCenterY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -textCenterY)
        
        let headerFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let headerColor = colors.normalText.withAlphaComponent(0.7)
        let sortedHeaderColor = colors.normalText.withAlphaComponent(0.9)
        let separatorColor = colors.normalText.withAlphaComponent(0.2)
        
        var x = rect.minX + 4 - horizontalScrollOffset
        for (index, column) in columns.enumerated() {
            let width = widthForColumn(column, availableWidth: totalWidth, columns: columns)
            
            // Check if this column is the sort column
            let isSortColumn = columnSortId == column.id
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: isSortColumn ? sortedHeaderColor : headerColor
            ]
            
            let textSize = column.title.size(withAttributes: attrs)
            let textY = rect.minY + (columnHeaderHeight - textSize.height) / 2
            
            // Left aligned
            let textX = x + 4
            column.title.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
            
            // Draw sort indicator if this is the sorted column
            if isSortColumn {
                let indicator = columnSortAscending ? "▲" : "▼"
                let indicatorAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 7),
                    .foregroundColor: sortedHeaderColor
                ]
                let indicatorX = textX + textSize.width + 3
                indicator.draw(at: NSPoint(x: indicatorX, y: textY + 1), withAttributes: indicatorAttrs)
            }
            
            // Draw column separator (except for last column)
            if index < columns.count - 1 {
                context.saveGState()
                context.setStrokeColor(separatorColor.cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: x + width - 1, y: rect.minY + 3))
                context.addLine(to: CGPoint(x: x + width - 1, y: rect.minY + columnHeaderHeight - 3))
                context.strokePath()
                context.restoreGState()
            }
            
            x += width
        }
        
        context.restoreGState()
        
        // Bottom separator line
        context.setStrokeColor(colors.normalText.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: rect.minX, y: rect.minY + columnHeaderHeight))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + columnHeaderHeight))
        context.strokePath()
        
        // Restore clipping context
        context.restoreGState()
    }
    
    /// Draw a single row with columns
    private func drawColumnRow(item: PlexDisplayItem, columns: [BrowserColumn], in context: CGContext,
                               rect: NSRect, isSelected: Bool, colors: PlaylistColors, indent: CGFloat = 0) {
        let totalWidth = rect.width - indent
        
        // Counter-flip for text drawing
        context.saveGState()
        let textCenterY = rect.midY
        context.translateBy(x: 0, y: textCenterY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -textCenterY)
        
        let textColor = isSelected ? colors.currentText : colors.normalText
        let dimColor = isSelected ? colors.currentText : colors.normalText.withAlphaComponent(0.65)
        let font = NSFont.systemFont(ofSize: 10)
        let smallFont = NSFont.systemFont(ofSize: 9)
        
        var x = rect.minX + indent + 4 - horizontalScrollOffset
        for column in columns {
            let width = widthForColumn(column, availableWidth: totalWidth, columns: columns)
            let value = item.columnValue(for: column)
            
            // Title column uses normal color/font, others use dim color/smaller font
            let color = column.id == "title" ? textColor : dimColor
            let useFont = column.id == "title" ? font : smallFont
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: useFont,
                .foregroundColor: color
            ]
            
            let textSize = value.size(withAttributes: attrs)
            let textY = rect.minY + (rect.height - textSize.height) / 2
            
            // All left aligned with padding
            let textX = x + 4
            let maxTextWidth = width - 8  // Padding on both sides
            
            // Draw with truncation if needed
            let drawRect = NSRect(x: textX, y: textY, width: maxTextWidth, height: textSize.height)
            value.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            
            x += width
        }
        
        context.restoreGState()
    }
    
    /// Draw art-only mode: full album art without tabs and list
    private func drawArtOnlyArea(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer, artwork: NSImage?) {
        // Content area starts below server bar
        let contentY = Layout.titleBarHeight + Layout.serverBarHeight
        let contentHeight = drawBounds.height - contentY - Layout.statusBarHeight
        let contentRect = NSRect(x: Layout.leftBorder, y: contentY,
                                 width: drawBounds.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth,
                                 height: contentHeight)
        
        // Fill background
        if isVisualizingArt {
            NSColor.black.setFill()
        } else {
            colors.normalBackground.setFill()
        }
        context.fill(contentRect)
        
        // Draw album art if available
        if let artworkImage = artwork,
           let cgImage = artworkImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.saveGState()
            context.clip(to: contentRect)
            
            // Calculate centered fit rect
            let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
            let artworkRect = calculateCenterFillRect(imageSize: imageSize, in: contentRect)
            
            // Apply visualization effects if enabled
            if isVisualizingArt {
                drawVisualizationEffect(context: context, cgImage: cgImage, artworkRect: artworkRect, contentRect: contentRect)
            } else {
                // Draw with full opacity in art-only mode (no effects)
                context.saveGState()
                context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
                context.restoreGState()
            }
            
            context.restoreGState()
        } else {
            // No artwork - show placeholder text
            let message = "No album art"
            let charWidth = SkinElements.TextFont.charWidth
            let charHeight = SkinElements.TextFont.charHeight
            let textScale: CGFloat = 2.0
            let scaledCharWidth = charWidth * textScale
            let scaledCharHeight = charHeight * textScale
            let textWidth = CGFloat(message.count) * scaledCharWidth
            let textX = contentRect.midX - textWidth / 2
            let textY = contentRect.midY - scaledCharHeight / 2
            
            drawScaledSkinText(message, at: NSPoint(x: textX, y: textY), scale: textScale, renderer: renderer, in: context)
        }
    }
    
    /// Draw visualization effect using GPU-accelerated Core Image filters
    private func drawVisualizationEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect) {
        // Get audio levels for effects
        let spectrumData = WindowManager.shared.audioEngine.spectrumData
        let bass = CGFloat(spectrumData.prefix(10).reduce(0, +) / 10.0)
        let mid = CGFloat(spectrumData.dropFirst(10).prefix(30).reduce(0, +) / 30.0)
        let treble = CGFloat(spectrumData.dropFirst(40).prefix(35).reduce(0, +) / 35.0)
        let level = (bass + mid + treble) / 3.0
        let t = CGFloat(visualizerTime)
        let intensity = visEffectIntensity
        
        // Create CIImage from CGImage
        var ciImage = CIImage(cgImage: cgImage)
        let imageSize = ciImage.extent.size
        let center = CIVector(x: imageSize.width / 2, y: imageSize.height / 2)
        
        // Apply GPU filter based on effect
        switch currentVisEffect {
        case .psychedelic:
            // Twirl + hue rotation + bloom
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
            // Zoom blur + rotation
            let zoomBlur = CIFilter(name: "CIZoomBlur")!
            zoomBlur.setValue(ciImage, forKey: kCIInputImageKey)
            zoomBlur.setValue(center, forKey: kCIInputCenterKey)
            zoomBlur.setValue(bass * 20 * intensity, forKey: kCIInputAmountKey)
            ciImage = zoomBlur.outputImage ?? ciImage
            
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
            affine = affine.rotated(by: t * 2 * intensity)
            affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
        case .fractal:
            // Multiple zoom levels
            let scale = 1.0 + sin(t * intensity) * 0.3 * bass
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
            affine = affine.scaledBy(x: scale, y: scale)
            affine = affine.rotated(by: t * 0.2 * intensity)
            affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(20 * bass * intensity, forKey: kCIInputRadiusKey)
            bloom.setValue(0.5 + level, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
            
        case .tunnel:
            let hole = CIFilter(name: "CIHoleDistortion")!
            hole.setValue(ciImage, forKey: kCIInputImageKey)
            hole.setValue(center, forKey: kCIInputCenterKey)
            hole.setValue(50 + bass * 100 * intensity * abs(sin(t)), forKey: kCIInputRadiusKey)
            ciImage = hole.outputImage ?? ciImage
            
        case .melt:
            // Glass distortion for melting effect
            let glass = CIFilter(name: "CIGlassDistortion")!
            glass.setValue(ciImage, forKey: kCIInputImageKey)
            // Create a simple texture
            let noiseFilter = CIFilter(name: "CIRandomGenerator")!
            if let noise = noiseFilter.outputImage?.cropped(to: ciImage.extent) {
                glass.setValue(noise, forKey: "inputTexture")
                glass.setValue(center, forKey: kCIInputCenterKey)
                glass.setValue(50 * bass * intensity, forKey: kCIInputScaleKey)
                ciImage = glass.outputImage ?? ciImage
            }
            
        case .wave:
            // Bump distortion moving across
            let bump = CIFilter(name: "CIBumpDistortion")!
            let waveX = imageSize.width * (0.5 + 0.4 * sin(t * 2))
            let waveY = imageSize.height * (0.5 + 0.3 * cos(t * 1.5))
            bump.setValue(ciImage, forKey: kCIInputImageKey)
            bump.setValue(CIVector(x: waveX, y: waveY), forKey: kCIInputCenterKey)
            bump.setValue(min(imageSize.width, imageSize.height) * 0.4, forKey: kCIInputRadiusKey)
            bump.setValue(bass * 2 * intensity * sin(t * 3), forKey: kCIInputScaleKey)
            ciImage = bump.outputImage ?? ciImage
            
        case .glitch:
            // RGB offset + posterize
            if bass > 0.3 {
                let offset = bass * 30 * intensity
                
                // Separate and offset RGB channels
                let rOffset = CIFilter(name: "CIAffineTransform")!
                rOffset.setValue(ciImage, forKey: kCIInputImageKey)
                rOffset.setValue(CGAffineTransform(translationX: offset, y: 0), forKey: kCIInputTransformKey)
                
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
            
            // Create offset versions
            let rFilter = CIFilter(name: "CIColorMatrix")!
            rFilter.setValue(ciImage, forKey: kCIInputImageKey)
            rFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            rFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            rFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            let rImage = rFilter.outputImage ?? ciImage
            
            let gFilter = CIFilter(name: "CIColorMatrix")!
            gFilter.setValue(ciImage, forKey: kCIInputImageKey)
            gFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            gFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            gFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            let gImage = gFilter.outputImage ?? ciImage
            
            let bFilter = CIFilter(name: "CIColorMatrix")!
            bFilter.setValue(ciImage, forKey: kCIInputImageKey)
            bFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            bFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            bFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            let bImage = bFilter.outputImage ?? ciImage
            
            // Offset red
            let rTransform = CIFilter(name: "CIAffineTransform")!
            rTransform.setValue(rImage, forKey: kCIInputImageKey)
            rTransform.setValue(CGAffineTransform(translationX: -offset, y: 0), forKey: kCIInputTransformKey)
            let rOffset = rTransform.outputImage ?? rImage
            
            // Offset blue
            let bTransform = CIFilter(name: "CIAffineTransform")!
            bTransform.setValue(bImage, forKey: kCIInputImageKey)
            bTransform.setValue(CGAffineTransform(translationX: offset, y: 0), forKey: kCIInputTransformKey)
            let bOffset = bTransform.outputImage ?? bImage
            
            // Combine
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
            // Triangular tile + displacement
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
            let offset = bass * 30 * intensity
            let shakeX = sin(t * 30) * offset
            let shakeY = cos(t * 25) * offset * 0.7
            
            let transform = CIFilter(name: "CIAffineTransform")!
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(CGAffineTransform(translationX: shakeX, y: shakeY), forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
            let motionBlur = CIFilter(name: "CIMotionBlur")!
            motionBlur.setValue(ciImage, forKey: kCIInputImageKey)
            motionBlur.setValue(bass * 20 * intensity, forKey: kCIInputRadiusKey)
            motionBlur.setValue(t * 10, forKey: kCIInputAngleKey)
            ciImage = motionBlur.outputImage ?? ciImage
            
        case .bounce:
            let bounceY = abs(sin(t * 3 * intensity)) * 50 * bass
            let scaleY = 1.0 - (1 - abs(sin(t * 3 * intensity))) * bass * 0.2 * intensity
            
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: 0, y: bounceY)
            affine = affine.concatenating(CGAffineTransform(scaleX: 1.0 / scaleY, y: scaleY))
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
        case .feedback:
            // Multiple scaled copies
            for i in 1..<5 {
                let scale = 1.0 - CGFloat(i) * 0.1
                let alpha = 0.5 / CGFloat(i)
                
                let scaleTransform = CIFilter(name: "CIAffineTransform")!
                var affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
                affine = affine.scaledBy(x: scale, y: scale)
                affine = affine.rotated(by: CGFloat(i) * 0.05 * bass * intensity)
                affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
                scaleTransform.setValue(CIImage(cgImage: cgImage), forKey: kCIInputImageKey)
                scaleTransform.setValue(affine, forKey: kCIInputTransformKey)
                
                if let layerImage = scaleTransform.outputImage {
                    let blend = CIFilter(name: "CISourceOverCompositing")!
                    blend.setValue(layerImage.applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                    ]), forKey: kCIInputImageKey)
                    blend.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
                    ciImage = blend.outputImage ?? ciImage
                }
            }
            
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(15 * level * intensity, forKey: kCIInputRadiusKey)
            bloom.setValue(0.5 + bass, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
            
        case .strobe:
            let strobeOn = Int(t * 10 * intensity) % 2 == 0 || bass > 0.6
            if strobeOn {
                let exposure = CIFilter(name: "CIExposureAdjust")!
                exposure.setValue(ciImage, forKey: kCIInputImageKey)
                exposure.setValue(bass * 2 * intensity, forKey: kCIInputEVKey)
                ciImage = exposure.outputImage ?? ciImage
            } else {
                let exposure = CIFilter(name: "CIExposureAdjust")!
                exposure.setValue(ciImage, forKey: kCIInputImageKey)
                exposure.setValue(-1.0, forKey: kCIInputEVKey)
                ciImage = exposure.outputImage ?? ciImage
            }
            
        case .jitter:
            let jitterX = CGFloat.random(in: -1...1) * bass * 20 * intensity
            let jitterY = CGFloat.random(in: -1...1) * bass * 20 * intensity
            let jitterScale = 1.0 + CGFloat.random(in: -0.05...0.05) * bass * intensity
            
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: jitterX, y: jitterY)
            affine = affine.scaledBy(x: jitterScale, y: jitterScale)
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
        case .mirror:
            // 4-way mirror
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
            // Triangular kaleidoscope
            let triangle = CIFilter(name: "CITriangleKaleidoscope")!
            triangle.setValue(ciImage, forKey: kCIInputImageKey)
            triangle.setValue(CIVector(x: imageSize.width * 0.5, y: imageSize.height * 0.5), forKey: "inputPoint")
            triangle.setValue(imageSize.width * (0.3 + bass * 0.2), forKey: "inputSize")
            triangle.setValue(t * 0.5 * intensity, forKey: "inputRotation")
            triangle.setValue(0.1, forKey: "inputDecay")
            ciImage = triangle.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
            
        case .doubleVision:
            let offset = 20 + bass * 50 * intensity
            
            let transform1 = CIFilter(name: "CIAffineTransform")!
            transform1.setValue(ciImage, forKey: kCIInputImageKey)
            transform1.setValue(CGAffineTransform(translationX: -offset, y: 0), forKey: kCIInputTransformKey)
            let img1 = transform1.outputImage ?? ciImage
            
            let transform2 = CIFilter(name: "CIAffineTransform")!
            transform2.setValue(ciImage, forKey: kCIInputImageKey)
            transform2.setValue(CGAffineTransform(translationX: offset, y: 0), forKey: kCIInputTransformKey)
            let img2 = transform2.outputImage ?? ciImage
            
            let blend = CIFilter(name: "CIAdditionCompositing")!
            blend.setValue(img1.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5)]), forKey: kCIInputImageKey)
            blend.setValue(img2.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5)]), forKey: kCIInputBackgroundImageKey)
            ciImage = blend.outputImage ?? ciImage
            
        case .flipbook:
            // Rapid flip between normal and transformed
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
            // CRT scanline effect
            let lines = CIFilter(name: "CILineScreen")!
            lines.setValue(ciImage, forKey: kCIInputImageKey)
            lines.setValue(center, forKey: kCIInputCenterKey)
            lines.setValue(t * 0.5, forKey: kCIInputAngleKey)
            lines.setValue(3 + bass * 5 * intensity, forKey: kCIInputWidthKey)
            lines.setValue(0.7 + bass * 0.3, forKey: kCIInputSharpnessKey)
            ciImage = lines.outputImage ?? ciImage
            
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(5 * level, forKey: kCIInputRadiusKey)
            bloom.setValue(0.3, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
            
        case .datamosh:
            // Simulate datamosh with edge work + color shift
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
            // Large pixelation with color boost
            let pixellate = CIFilter(name: "CIPixellate")!
            pixellate.setValue(ciImage, forKey: kCIInputImageKey)
            pixellate.setValue(center, forKey: kCIInputCenterKey)
            pixellate.setValue(20 + bass * 60 * intensity, forKey: kCIInputScaleKey)
            ciImage = pixellate.outputImage ?? ciImage
            
            let vibrance = CIFilter(name: "CIVibrance")!
            vibrance.setValue(ciImage, forKey: kCIInputImageKey)
            vibrance.setValue(0.5 + bass * intensity, forKey: "inputAmount")
            ciImage = vibrance.outputImage ?? ciImage
        }
        
        // Render the processed image
        let outputExtent = ciImage.extent
        if let outputCGImage = ciContext.createCGImage(ciImage, from: outputExtent) {
            context.saveGState()
            context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(outputCGImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
            context.restoreGState()
        }
    }
    
    // MARK: - Visualization Effects
    
    private func drawSubtleEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Gentle pulse
        let pulse = 1.0 + bass * 0.1 * intensity * (0.5 + 0.5 * sin(t * 4))
        let scaledRect = artworkRect.insetBy(dx: artworkRect.width * (1 - pulse) / 2, dy: artworkRect.height * (1 - pulse) / 2)
        
        context.saveGState()
        context.translateBy(x: scaledRect.minX, y: scaledRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledRect.width, height: scaledRect.height))
        context.restoreGState()
        
        // Soft glow
        let glowAlpha = level * 0.3 * intensity
        let hue = fmod(t * 0.05, 1.0)
        context.saveGState()
        context.setBlendMode(.screen)
        context.setFillColor(NSColor(hue: hue, saturation: 0.5, brightness: 1.0, alpha: glowAlpha).cgColor)
        context.fill(contentRect)
        context.restoreGState()
    }
    
    private func drawPsychedelicEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                       bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Rotating hue shift with pulsing
        let pulse = 1.0 + bass * 0.25 * intensity
        let rotation = t * 0.5 * intensity + bass * 0.3
        
        let centerX = contentRect.midX
        let centerY = contentRect.midY
        
        // Draw multiple rotated/scaled copies for trippy effect
        for i in 0..<3 {
            let layerIntensity = CGFloat(3 - i) / 3.0
            let layerScale = pulse * (1.0 + CGFloat(i) * 0.05 * mid * intensity)
            let layerRotation = rotation + CGFloat(i) * 0.1 * treble
            
            let scaledWidth = artworkRect.width * layerScale
            let scaledHeight = artworkRect.height * layerScale
            
            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: layerRotation)
            context.translateBy(x: -scaledWidth / 2, y: scaledHeight / 2)
            context.scaleBy(x: 1, y: -1)
            
            if i > 0 {
                context.setAlpha(0.4 * layerIntensity)
                context.setBlendMode(.plusLighter)
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
            context.restoreGState()
        }
        
        // Intense color cycling overlay
        let hue1 = fmod(t * 0.2 + bass, 1.0)
        let hue2 = fmod(t * 0.15 + treble + 0.33, 1.0)
        
        context.saveGState()
        context.setBlendMode(.overlay)
        context.setFillColor(NSColor(hue: hue1, saturation: 0.8 * intensity, brightness: 1.0, alpha: 0.4 * level * intensity).cgColor)
        context.fill(contentRect)
        context.restoreGState()
        
        context.saveGState()
        context.setBlendMode(.colorDodge)
        context.setFillColor(NSColor(hue: hue2, saturation: 1.0, brightness: 1.0, alpha: 0.2 * mid * intensity).cgColor)
        context.fill(contentRect)
        context.restoreGState()
    }
    
    private func drawKaleidoscopeEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                        bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        let segments = 6 + Int(bass * 4 * intensity)
        let angleStep = CGFloat.pi * 2 / CGFloat(segments)
        let rotation = t * 0.3 * intensity
        let pulse = 1.0 + bass * 0.15 * intensity
        
        let centerX = contentRect.midX
        let centerY = contentRect.midY
        let scaledWidth = artworkRect.width * pulse * 0.5
        let scaledHeight = artworkRect.height * pulse * 0.5
        
        for i in 0..<segments {
            let angle = CGFloat(i) * angleStep + rotation
            let flip = i % 2 == 0 ? 1.0 : -1.0
            
            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: angle)
            context.scaleBy(x: CGFloat(flip), y: 1)
            context.translateBy(x: -scaledWidth / 2, y: scaledHeight / 2)
            context.scaleBy(x: 1, y: -1)
            context.setAlpha(0.8)
            context.setBlendMode(i % 2 == 0 ? .normal : .screen)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
            context.restoreGState()
        }
        
        // Trippy color wheel
        let hue = fmod(t * 0.1, 1.0)
        context.saveGState()
        context.setBlendMode(.hue)
        context.setFillColor(NSColor(hue: hue, saturation: 0.6 * intensity, brightness: 1.0, alpha: 0.3 * mid).cgColor)
        context.fill(contentRect)
        context.restoreGState()
    }
    
    private func drawMeltEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base image stretched/melted
        let meltAmount = bass * 0.3 * intensity
        let waveFreq = 3.0 + treble * 5.0
        let wavePhase = t * 2.0
        
        // Draw with vertical wave distortion simulation using multiple strips
        let strips = 20
        let stripWidth = artworkRect.width / CGFloat(strips)
        
        for i in 0..<strips {
            let x = artworkRect.minX + CGFloat(i) * stripWidth
            let waveOffset = sin(CGFloat(i) / CGFloat(strips) * waveFreq + wavePhase) * meltAmount * artworkRect.height
            let stretchFactor = 1.0 + cos(CGFloat(i) / CGFloat(strips) * waveFreq * 0.5 + wavePhase * 0.7) * meltAmount * 0.3
            
            let srcRect = CGRect(x: CGFloat(i) / CGFloat(strips) * CGFloat(cgImage.width),
                                y: 0,
                                width: CGFloat(cgImage.width) / CGFloat(strips),
                                height: CGFloat(cgImage.height))
            
            if let stripImage = cgImage.cropping(to: srcRect) {
                let destHeight = artworkRect.height * stretchFactor
                let destRect = NSRect(x: x, y: artworkRect.minY + waveOffset + (artworkRect.height - destHeight) / 2,
                                     width: stripWidth + 1, height: destHeight)
                
                context.saveGState()
                context.translateBy(x: destRect.minX, y: destRect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(stripImage, in: CGRect(x: 0, y: 0, width: destRect.width, height: destRect.height))
                context.restoreGState()
            }
        }
        
        // Acid color wash
        let hue = fmod(t * 0.08, 1.0)
        context.saveGState()
        context.setBlendMode(.color)
        context.setFillColor(NSColor(hue: hue, saturation: 0.7 * intensity, brightness: 1.0, alpha: 0.25 * level * intensity).cgColor)
        context.fill(contentRect)
        context.restoreGState()
    }
    
    private func drawStrobeEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Fast strobe on bass hits
        let strobeFreq = 8.0 + bass * 20.0 * intensity
        let strobe = sin(t * strobeFreq) > 0.3 ? 1.0 : 0.3
        
        // Invert colors on beat
        let invert = bass > 0.6 && sin(t * 15.0) > 0
        
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.setAlpha(strobe)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        if invert {
            context.saveGState()
            context.setBlendMode(.difference)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(artworkRect)
            context.restoreGState()
        }
        
        // Flash overlay
        let flashIntensity = bass > 0.5 ? bass * intensity : 0
        if flashIntensity > 0.1 {
            let flashHue = fmod(t * 0.5, 1.0)
            context.saveGState()
            context.setBlendMode(.screen)
            context.setFillColor(NSColor(hue: flashHue, saturation: 1.0, brightness: 1.0, alpha: flashIntensity * 0.6).cgColor)
            context.fill(contentRect)
            context.restoreGState()
        }
    }
    
    private func drawRGBSplitEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                    bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Chromatic aberration / RGB split
        let splitAmount = (10 + bass * 30) * intensity
        let angle = t * 0.5
        
        let redOffset = CGPoint(x: cos(angle) * splitAmount, y: sin(angle) * splitAmount)
        let greenOffset = CGPoint.zero
        let blueOffset = CGPoint(x: cos(angle + CGFloat.pi) * splitAmount, y: sin(angle + CGFloat.pi) * splitAmount)
        
        // Red channel
        context.saveGState()
        context.translateBy(x: artworkRect.minX + redOffset.x, y: artworkRect.maxY + redOffset.y)
        context.scaleBy(x: 1, y: -1)
        context.setBlendMode(.screen)
        context.clip(to: CGRect(origin: .zero, size: artworkRect.size), mask: cgImage)
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Green channel
        context.saveGState()
        context.translateBy(x: artworkRect.minX + greenOffset.x, y: artworkRect.maxY + greenOffset.y)
        context.scaleBy(x: 1, y: -1)
        context.setBlendMode(.screen)
        context.clip(to: CGRect(origin: .zero, size: artworkRect.size), mask: cgImage)
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Blue channel
        context.saveGState()
        context.translateBy(x: artworkRect.minX + blueOffset.x, y: artworkRect.maxY + blueOffset.y)
        context.scaleBy(x: 1, y: -1)
        context.setBlendMode(.screen)
        context.clip(to: CGRect(origin: .zero, size: artworkRect.size), mask: cgImage)
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Scanlines
        context.saveGState()
        context.setBlendMode(.multiply)
        for y in stride(from: contentRect.minY, to: contentRect.maxY, by: 4) {
            context.setFillColor(NSColor(white: 0.8, alpha: 0.3 * intensity).cgColor)
            context.fill(NSRect(x: contentRect.minX, y: y, width: contentRect.width, height: 2))
        }
        context.restoreGState()
    }
    
    private func drawMirrorEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Infinite mirror tunnel effect
        let layers = 5 + Int(bass * 5 * intensity)
        let baseScale: CGFloat = 0.85
        let rotation = t * 0.2 * intensity
        
        let centerX = contentRect.midX
        let centerY = contentRect.midY
        
        for i in (0..<layers).reversed() {
            let layerScale = pow(baseScale, CGFloat(i)) * (1.0 + bass * 0.1 * intensity)
            let layerRotation = rotation * CGFloat(i) * 0.3
            let alpha = 1.0 - CGFloat(i) * 0.15
            
            let scaledWidth = artworkRect.width * layerScale
            let scaledHeight = artworkRect.height * layerScale
            
            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: layerRotation)
            if i % 2 == 1 {
                context.scaleBy(x: -1, y: 1)  // Mirror alternate layers
            }
            context.translateBy(x: -scaledWidth / 2, y: scaledHeight / 2)
            context.scaleBy(x: 1, y: -1)
            context.setAlpha(alpha)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
            context.restoreGState()
        }
        
        // Vignette
        let vignetteColors = [NSColor.clear.cgColor, NSColor(white: 0, alpha: 0.7 * intensity).cgColor]
        let locations: [CGFloat] = [0.3, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: vignetteColors as CFArray, locations: locations) {
            context.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: centerX, y: centerY),
                                       startRadius: 0,
                                       endCenter: CGPoint(x: centerX, y: centerY),
                                       endRadius: contentRect.width * 0.7,
                                       options: [])
        }
    }
    
    private func drawVortexEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Spinning vortex
        let baseRotation = t * 1.5 * intensity
        let spiralTightness = 0.1 + bass * 0.2 * intensity
        let layers = 8
        
        let centerX = contentRect.midX
        let centerY = contentRect.midY
        
        for i in 0..<layers {
            let progress = CGFloat(i) / CGFloat(layers)
            let layerScale = 1.0 - progress * 0.8
            let layerRotation = baseRotation + progress * CGFloat.pi * 4 * spiralTightness
            let alpha = (1.0 - progress) * 0.7
            
            let scaledWidth = artworkRect.width * layerScale
            let scaledHeight = artworkRect.height * layerScale
            
            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: layerRotation)
            context.translateBy(x: -scaledWidth / 2, y: scaledHeight / 2)
            context.scaleBy(x: 1, y: -1)
            context.setAlpha(alpha)
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
            context.restoreGState()
        }
        
        // Trippy radial color
        let hue = fmod(t * 0.1 + level, 1.0)
        context.saveGState()
        context.setBlendMode(.softLight)
        context.setFillColor(NSColor(hue: hue, saturation: 0.8 * intensity, brightness: 1.0, alpha: 0.4 * level).cgColor)
        context.fill(contentRect)
        context.restoreGState()
    }
    
    private func drawGlitchEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Random glitch displacement
        let glitchIntensity = bass * intensity
        let shouldGlitch = bass > 0.4 && Int(t * 10) % 3 == 0
        
        // Base image
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        if shouldGlitch {
            // Random horizontal slice displacement
            let slices = Int.random(in: 3...8)
            let sliceHeight = artworkRect.height / CGFloat(slices)
            
            for i in 0..<slices {
                if Double.random(in: 0...1) < Double(glitchIntensity) {
                    let offset = CGFloat.random(in: -50...50) * glitchIntensity
                    let y = artworkRect.minY + CGFloat(i) * sliceHeight
                    
                    let srcY = CGFloat(cgImage.height) * CGFloat(i) / CGFloat(slices)
                    let srcRect = CGRect(x: 0, y: srcY, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height) / CGFloat(slices))
                    
                    if let sliceImage = cgImage.cropping(to: srcRect) {
                        context.saveGState()
                        context.translateBy(x: artworkRect.minX + offset, y: y + sliceHeight)
                        context.scaleBy(x: 1, y: -1)
                        context.setBlendMode(.normal)
                        context.draw(sliceImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: sliceHeight))
                        context.restoreGState()
                    }
                }
            }
            
            // Color corruption
            let corruptHue = CGFloat.random(in: 0...1)
            context.saveGState()
            context.setBlendMode(.exclusion)
            context.setFillColor(NSColor(hue: corruptHue, saturation: 1.0, brightness: 1.0, alpha: glitchIntensity * 0.5).cgColor)
            
            // Random corrupt rectangles
            for _ in 0..<Int(glitchIntensity * 10) {
                let glitchRect = NSRect(
                    x: artworkRect.minX + CGFloat.random(in: 0...artworkRect.width),
                    y: artworkRect.minY + CGFloat.random(in: 0...artworkRect.height),
                    width: CGFloat.random(in: 20...100),
                    height: CGFloat.random(in: 5...30)
                )
                context.fill(glitchRect)
            }
            context.restoreGState()
        }
        
        // Persistent noise overlay
        context.saveGState()
        context.setBlendMode(.overlay)
        for _ in 0..<Int(50 * intensity) {
            let noiseRect = NSRect(
                x: artworkRect.minX + CGFloat.random(in: 0...artworkRect.width),
                y: artworkRect.minY + CGFloat.random(in: 0...artworkRect.height),
                width: CGFloat.random(in: 1...3),
                height: CGFloat.random(in: 1...3)
            )
            context.setFillColor(NSColor(white: CGFloat.random(in: 0...1), alpha: 0.3).cgColor)
            context.fill(noiseRect)
        }
        context.restoreGState()
    }
    
    // MARK: - Geometric Effects
    
    private func drawFractalEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                   bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Recursive zoom fractal effect
        let layers = 5 + Int(bass * 3 * intensity)
        let zoomSpeed = 0.3 * intensity
        let rotation = t * 0.2 * intensity
        
        for i in (0..<layers).reversed() {
            let progress = CGFloat(i) / CGFloat(layers)
            let scale = 1.0 + progress * (1.0 + sin(t * zoomSpeed) * 0.5) * intensity
            let layerRotation = rotation * progress * 2
            let alpha = 1.0 - progress * 0.7
            
            let centerX = contentRect.midX
            let centerY = contentRect.midY
            let scaledWidth = artworkRect.width / scale
            let scaledHeight = artworkRect.height / scale
            
            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: layerRotation)
            context.translateBy(x: -scaledWidth / 2, y: scaledHeight / 2)
            context.scaleBy(x: 1, y: -1)
            context.setAlpha(alpha)
            context.setBlendMode(i % 2 == 0 ? .normal : .plusLighter)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
            context.restoreGState()
        }
    }
    
    private func drawHexGridEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                   bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base image
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Hexagonal grid overlay
        let hexSize: CGFloat = 30 + bass * 20 * intensity
        let rows = Int(contentRect.height / (hexSize * 0.866)) + 1
        let cols = Int(contentRect.width / hexSize) + 1
        
        for row in 0..<rows {
            for col in 0..<cols {
                let offset = row % 2 == 0 ? 0 : hexSize * 0.5
                let x = contentRect.minX + CGFloat(col) * hexSize + offset
                let y = contentRect.minY + CGFloat(row) * hexSize * 0.866
                
                let pulsePhase = sin(t * 3 + CGFloat(row + col) * 0.5) * 0.5 + 0.5
                let hue = fmod(t * 0.1 + CGFloat(row + col) * 0.05, 1.0)
                let alpha = level * pulsePhase * 0.5 * intensity
                
                context.saveGState()
                context.setBlendMode(.overlay)
                context.setFillColor(NSColor(hue: hue, saturation: 0.8, brightness: 1.0, alpha: alpha).cgColor)
                
                // Draw hexagon
                let path = CGMutablePath()
                for i in 0..<6 {
                    let angle = CGFloat(i) * CGFloat.pi / 3 - CGFloat.pi / 6
                    let px = x + cos(angle) * hexSize * 0.4
                    let py = y + sin(angle) * hexSize * 0.4
                    if i == 0 {
                        path.move(to: CGPoint(x: px, y: py))
                    } else {
                        path.addLine(to: CGPoint(x: px, y: py))
                    }
                }
                path.closeSubpath()
                context.addPath(path)
                context.fillPath()
                context.restoreGState()
            }
        }
    }
    
    private func drawTrianglesEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                     bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Exploding triangles
        let triCount = Int(10 + bass * 30 * intensity)
        for i in 0..<triCount {
            let angle = CGFloat(i) / CGFloat(triCount) * CGFloat.pi * 2 + t * 0.5
            let distance = (50 + level * 100 * intensity) * (1 + sin(t * 2 + CGFloat(i)) * 0.3)
            let size: CGFloat = 20 + mid * 30
            
            let x = contentRect.midX + cos(angle) * distance
            let y = contentRect.midY + sin(angle) * distance
            
            let hue = fmod(CGFloat(i) / CGFloat(triCount) + t * 0.1, 1.0)
            
            context.saveGState()
            context.translateBy(x: x, y: y)
            context.rotate(by: angle + t)
            context.setBlendMode(.plusLighter)
            context.setFillColor(NSColor(hue: hue, saturation: 0.9, brightness: 1.0, alpha: 0.6 * intensity).cgColor)
            
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -size/2))
            path.addLine(to: CGPoint(x: size/2, y: size/2))
            path.addLine(to: CGPoint(x: -size/2, y: size/2))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
    }
    
    private func drawRippleEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Concentric ripples
        let rippleCount = 5 + Int(bass * 5)
        let maxRadius = max(contentRect.width, contentRect.height) * 0.7
        
        for i in 0..<rippleCount {
            let phase = fmod(t * 0.5 + CGFloat(i) * 0.2, 1.0)
            let radius = phase * maxRadius
            let alpha = (1 - phase) * level * 0.6 * intensity
            let lineWidth = 2 + bass * 5 * intensity
            
            let hue = fmod(phase + t * 0.1, 1.0)
            
            context.saveGState()
            context.setBlendMode(.screen)
            context.setStrokeColor(NSColor(hue: hue, saturation: 0.7, brightness: 1.0, alpha: alpha).cgColor)
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: NSRect(x: contentRect.midX - radius, y: contentRect.midY - radius,
                                            width: radius * 2, height: radius * 2))
            context.restoreGState()
        }
    }
    
    private func drawPixelateEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                    bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Variable pixelation based on audio
        let pixelSize = max(4, Int(8 + (1 - level) * 40 * intensity))
        
        // Create pixelated version by drawing small tiles
        let cols = Int(artworkRect.width) / pixelSize + 1
        let rows = Int(artworkRect.height) / pixelSize + 1
        
        for row in 0..<rows {
            for col in 0..<cols {
                let srcX = CGFloat(col * pixelSize) / artworkRect.width * CGFloat(cgImage.width)
                let srcY = CGFloat(row * pixelSize) / artworkRect.height * CGFloat(cgImage.height)
                let srcRect = CGRect(x: srcX, y: srcY, width: CGFloat(pixelSize), height: CGFloat(pixelSize))
                
                if let pixel = cgImage.cropping(to: srcRect) {
                    let destX = artworkRect.minX + CGFloat(col * pixelSize)
                    let destY = artworkRect.minY + CGFloat(row * pixelSize)
                    
                    context.saveGState()
                    context.translateBy(x: destX, y: destY + CGFloat(pixelSize))
                    context.scaleBy(x: 1, y: -1)
                    context.draw(pixel, in: CGRect(x: 0, y: 0, width: CGFloat(pixelSize), height: CGFloat(pixelSize)))
                    context.restoreGState()
                }
            }
        }
        
        // Color overlay on beats
        if bass > 0.5 {
            let hue = fmod(t * 0.2, 1.0)
            context.saveGState()
            context.setBlendMode(.overlay)
            context.setFillColor(NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: bass * 0.4 * intensity).cgColor)
            context.fill(artworkRect)
            context.restoreGState()
        }
    }
    
    // MARK: - Color Effects
    
    private func drawNeonEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw darkened base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.setAlpha(0.3)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Neon glow layers
        let glowColors: [NSColor] = [
            NSColor(red: 1, green: 0, blue: 0.5, alpha: 1),    // Pink
            NSColor(red: 0, green: 1, blue: 1, alpha: 1),      // Cyan
            NSColor(red: 1, green: 1, blue: 0, alpha: 1),      // Yellow
            NSColor(red: 0.5, green: 0, blue: 1, alpha: 1)     // Purple
        ]
        
        let colorIndex = Int(fmod(t * 0.5, CGFloat(glowColors.count)))
        let nextIndex = (colorIndex + 1) % glowColors.count
        let blend = fmod(t * 0.5, 1.0)
        
        // Multiple glow passes
        for pass in 0..<3 {
            let glowSize = CGFloat(pass + 1) * 3 * intensity * (1 + bass * 0.5)
            let alpha = 0.3 / CGFloat(pass + 1) * level * intensity
            
            context.saveGState()
            context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.setBlendMode(.plusLighter)
            context.setShadow(offset: .zero, blur: glowSize, color: glowColors[colorIndex].withAlphaComponent(alpha).cgColor)
            context.setAlpha(alpha)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
            context.restoreGState()
        }
        
        // Pulsing border glow
        let borderGlow = bass * 20 * intensity
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setStrokeColor(glowColors[nextIndex].withAlphaComponent(level * 0.8).cgColor)
        context.setLineWidth(borderGlow)
        context.stroke(artworkRect.insetBy(dx: -borderGlow/2, dy: -borderGlow/2))
        context.restoreGState()
    }
    
    private func drawThermalEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                   bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Thermal color mapping overlay
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [NSColor.blue.cgColor, NSColor.cyan.cgColor, NSColor.green.cgColor,
                                          NSColor.yellow.cgColor, NSColor.orange.cgColor, NSColor.red.cgColor,
                                          NSColor.white.cgColor] as CFArray,
                                  locations: [0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0])!
        
        // Animated thermal threshold
        let threshold = 0.3 + sin(t * 2) * 0.2 * intensity
        
        context.saveGState()
        context.setBlendMode(.color)
        context.setAlpha(0.7 * intensity)
        context.clip(to: artworkRect)
        
        // Draw gradient based on audio
        let startPoint = CGPoint(x: artworkRect.minX, y: artworkRect.minY + artworkRect.height * threshold)
        let endPoint = CGPoint(x: artworkRect.minX, y: artworkRect.maxY)
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        context.restoreGState()
        
        // Heat pulse on bass
        if bass > 0.5 {
            context.saveGState()
            context.setBlendMode(.screen)
            context.setFillColor(NSColor.red.withAlphaComponent(bass * 0.4 * intensity).cgColor)
            context.fill(artworkRect)
            context.restoreGState()
        }
    }
    
    private func drawPosterizeEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                     bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Posterize overlay with shifting colors
        let hueShift = fmod(t * 0.1, 1.0)
        let satBoost = 1.0 + bass * 0.5 * intensity
        
        // High contrast overlay
        context.saveGState()
        context.setBlendMode(.hardLight)
        context.setAlpha(0.4 * intensity)
        
        let hue1 = fmod(hueShift, 1.0)
        let hue2 = fmod(hueShift + 0.33, 1.0)
        let hue3 = fmod(hueShift + 0.66, 1.0)
        
        // Color bands
        let bandHeight = artworkRect.height / 3
        context.setFillColor(NSColor(hue: hue1, saturation: satBoost, brightness: 1.0, alpha: 1).cgColor)
        context.fill(NSRect(x: artworkRect.minX, y: artworkRect.minY, width: artworkRect.width, height: bandHeight))
        context.setFillColor(NSColor(hue: hue2, saturation: satBoost, brightness: 1.0, alpha: 1).cgColor)
        context.fill(NSRect(x: artworkRect.minX, y: artworkRect.minY + bandHeight, width: artworkRect.width, height: bandHeight))
        context.setFillColor(NSColor(hue: hue3, saturation: satBoost, brightness: 1.0, alpha: 1).cgColor)
        context.fill(NSRect(x: artworkRect.minX, y: artworkRect.minY + bandHeight * 2, width: artworkRect.width, height: bandHeight))
        context.restoreGState()
    }
    
    private func drawInvertEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Animated inversion based on audio
        let invertAmount = (sin(t * 4 * intensity) * 0.5 + 0.5) * bass
        
        if invertAmount > 0.3 {
            context.saveGState()
            context.setBlendMode(.difference)
            context.setFillColor(NSColor.white.withAlphaComponent(invertAmount * intensity).cgColor)
            context.fill(artworkRect)
            context.restoreGState()
        }
        
        // Hue rotation
        let hue = fmod(t * 0.15, 1.0)
        context.saveGState()
        context.setBlendMode(.hue)
        context.setFillColor(NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 0.3 * level * intensity).cgColor)
        context.fill(artworkRect)
        context.restoreGState()
    }
    
    private func drawSepiaEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                 bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Sepia overlay
        let sepiaStrength = 0.5 + sin(t * 0.5) * 0.3 * intensity
        context.saveGState()
        context.setBlendMode(.color)
        context.setFillColor(NSColor(red: 0.9, green: 0.7, blue: 0.4, alpha: sepiaStrength).cgColor)
        context.fill(artworkRect)
        context.restoreGState()
        
        // Vignette
        let vignetteRadius = artworkRect.width * 0.8 * (1 + bass * 0.2 * intensity)
        let vignetteColors = [NSColor.clear.cgColor, NSColor(white: 0, alpha: 0.6 * intensity).cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: vignetteColors as CFArray, locations: [0.3, 1.0]) {
            context.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: artworkRect.midX, y: artworkRect.midY), startRadius: 0,
                                       endCenter: CGPoint(x: artworkRect.midX, y: artworkRect.midY), endRadius: vignetteRadius,
                                       options: [])
        }
        
        // Film grain
        for _ in 0..<Int(100 * intensity) {
            let x = artworkRect.minX + CGFloat.random(in: 0...artworkRect.width)
            let y = artworkRect.minY + CGFloat.random(in: 0...artworkRect.height)
            context.setFillColor(NSColor(white: CGFloat.random(in: 0.3...0.7), alpha: 0.1).cgColor)
            context.fill(NSRect(x: x, y: y, width: 1, height: 1))
        }
    }
    
    // MARK: - Motion Effects
    
    private func drawZoomEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Breathing zoom
        let zoomCycle = sin(t * 2 * intensity) * 0.5 + 0.5
        let scale = 1.0 + zoomCycle * bass * 0.3 * intensity
        
        let centerX = contentRect.midX
        let centerY = contentRect.midY
        let scaledWidth = artworkRect.width * scale
        let scaledHeight = artworkRect.height * scale
        
        context.saveGState()
        context.translateBy(x: centerX - scaledWidth / 2, y: centerY + scaledHeight / 2)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        context.restoreGState()
        
        // Motion blur simulation
        let blurLayers = 3
        for i in 1...blurLayers {
            let blurScale = scale - CGFloat(i) * 0.02 * intensity
            let blurAlpha = 0.2 / CGFloat(i)
            let blurWidth = artworkRect.width * blurScale
            let blurHeight = artworkRect.height * blurScale
            
            context.saveGState()
            context.translateBy(x: centerX - blurWidth / 2, y: centerY + blurHeight / 2)
            context.scaleBy(x: 1, y: -1)
            context.setAlpha(blurAlpha)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: blurWidth, height: blurHeight))
            context.restoreGState()
        }
    }
    
    private func drawShakeEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                 bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Earthquake shake
        let shakeX = sin(t * 30 * intensity) * bass * 15 * intensity
        let shakeY = cos(t * 25 * intensity) * bass * 10 * intensity
        let rotation = sin(t * 20) * bass * 0.05 * intensity
        
        let centerX = contentRect.midX
        let centerY = contentRect.midY
        
        context.saveGState()
        context.translateBy(x: centerX + shakeX, y: centerY + shakeY)
        context.rotate(by: rotation)
        context.translateBy(x: -artworkRect.width / 2, y: artworkRect.height / 2)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Crack lines on heavy bass
        if bass > 0.7 {
            context.saveGState()
            context.setStrokeColor(NSColor.white.withAlphaComponent(bass * 0.5).cgColor)
            context.setLineWidth(2)
            for _ in 0..<Int(bass * 5) {
                let startX = contentRect.minX + CGFloat.random(in: 0...contentRect.width)
                let startY = contentRect.minY + CGFloat.random(in: 0...contentRect.height)
                context.move(to: CGPoint(x: startX, y: startY))
                context.addLine(to: CGPoint(x: startX + CGFloat.random(in: -50...50),
                                           y: startY + CGFloat.random(in: -50...50)))
                context.strokePath()
            }
            context.restoreGState()
        }
    }
    
    private func drawSpinEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Continuous rotation with speed based on audio
        let rotationSpeed = 0.5 + level * 2 * intensity
        let rotation = t * rotationSpeed
        let pulse = 1.0 + bass * 0.1 * intensity
        
        let centerX = contentRect.midX
        let centerY = contentRect.midY
        let scaledWidth = artworkRect.width * pulse
        let scaledHeight = artworkRect.height * pulse
        
        context.saveGState()
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: rotation)
        context.translateBy(x: -scaledWidth / 2, y: scaledHeight / 2)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        context.restoreGState()
        
        // Trail effect
        for i in 1..<4 {
            let trailRotation = rotation - CGFloat(i) * 0.1
            let trailAlpha = 0.3 / CGFloat(i)
            
            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: trailRotation)
            context.translateBy(x: -scaledWidth / 2, y: scaledHeight / 2)
            context.scaleBy(x: 1, y: -1)
            context.setAlpha(trailAlpha)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
            context.restoreGState()
        }
    }
    
    private func drawBounceEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Bouncing with squash and stretch
        let bouncePhase = abs(sin(t * 3 * intensity))
        let squash = 1.0 + (1 - bouncePhase) * bass * 0.2 * intensity
        let stretch = 1.0 - (1 - bouncePhase) * bass * 0.15 * intensity
        
        let offsetY = bouncePhase * 30 * intensity
        
        let scaledWidth = artworkRect.width * squash
        let scaledHeight = artworkRect.height * stretch
        let centerX = contentRect.midX
        let centerY = contentRect.midY - offsetY
        
        context.saveGState()
        context.translateBy(x: centerX - scaledWidth / 2, y: centerY + scaledHeight / 2)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        context.restoreGState()
        
        // Shadow
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.3 * (1 - bouncePhase)).cgColor)
        let shadowWidth = scaledWidth * (0.8 + bouncePhase * 0.2)
        let shadowHeight: CGFloat = 10 * (1 - bouncePhase * 0.5)
        context.fillEllipse(in: NSRect(x: centerX - shadowWidth / 2, y: contentRect.midY + artworkRect.height / 2 - 5,
                                      width: shadowWidth, height: shadowHeight))
        context.restoreGState()
    }
    
    private func drawWaveEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Ocean wave distortion using strips
        let strips = 30
        let stripWidth = artworkRect.width / CGFloat(strips)
        let waveAmp = 20 * bass * intensity
        let waveFreq: CGFloat = 3
        
        for i in 0..<strips {
            let x = artworkRect.minX + CGFloat(i) * stripWidth
            let waveOffset = sin(CGFloat(i) / CGFloat(strips) * waveFreq * CGFloat.pi * 2 + t * 3) * waveAmp
            
            let srcX = CGFloat(i) / CGFloat(strips) * CGFloat(cgImage.width)
            let srcRect = CGRect(x: srcX, y: 0, width: CGFloat(cgImage.width) / CGFloat(strips), height: CGFloat(cgImage.height))
            
            if let stripImage = cgImage.cropping(to: srcRect) {
                context.saveGState()
                context.translateBy(x: x, y: artworkRect.maxY + waveOffset)
                context.scaleBy(x: 1, y: -1)
                context.draw(stripImage, in: CGRect(x: 0, y: 0, width: stripWidth + 1, height: artworkRect.height))
                context.restoreGState()
            }
        }
        
        // Water reflection
        context.saveGState()
        context.setBlendMode(.overlay)
        context.setFillColor(NSColor.cyan.withAlphaComponent(0.15 * intensity * level).cgColor)
        context.fill(artworkRect)
        context.restoreGState()
    }
    
    // MARK: - Trippy Effects
    
    private func drawPlasmaEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Plasma overlay
        let gridSize: CGFloat = 20
        let cols = Int(contentRect.width / gridSize)
        let rows = Int(contentRect.height / gridSize)
        
        context.saveGState()
        context.setBlendMode(.screen)
        
        for row in 0..<rows {
            for col in 0..<cols {
                let x = contentRect.minX + CGFloat(col) * gridSize
                let y = contentRect.minY + CGFloat(row) * gridSize
                
                // Plasma calculation
                let v1 = sin(CGFloat(col) * 0.1 + t)
                let v2 = sin(CGFloat(row) * 0.1 + t * 1.1)
                let v3 = sin((CGFloat(col) + CGFloat(row)) * 0.1 + t * 0.7)
                let v4 = sin(sqrt(pow(CGFloat(col) - CGFloat(cols)/2, 2) + pow(CGFloat(row) - CGFloat(rows)/2, 2)) * 0.1 + t)
                let plasma = (v1 + v2 + v3 + v4) / 4
                
                let hue = fmod(plasma + 0.5 + t * 0.1, 1.0)
                let alpha = 0.3 * level * intensity
                
                context.setFillColor(NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: alpha).cgColor)
                context.fill(NSRect(x: x, y: y, width: gridSize, height: gridSize))
            }
        }
        context.restoreGState()
    }
    
    private func drawTunnelEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Time tunnel with zooming layers
        let layers = 8
        let zoomSpeed = t * 0.5 * intensity
        
        for i in (0..<layers).reversed() {
            let progress = (CGFloat(i) / CGFloat(layers) + fmod(zoomSpeed, 1.0))
            let scale = 0.2 + progress * 0.8
            let rotation = progress * CGFloat.pi * 0.5 * intensity
            let alpha = 1.0 - progress * 0.8
            
            let centerX = contentRect.midX
            let centerY = contentRect.midY
            let scaledWidth = artworkRect.width * scale
            let scaledHeight = artworkRect.height * scale
            
            context.saveGState()
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: rotation)
            context.translateBy(x: -scaledWidth / 2, y: scaledHeight / 2)
            context.scaleBy(x: 1, y: -1)
            context.setAlpha(alpha)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
            context.restoreGState()
        }
        
        // Center glow
        let glowColors = [NSColor.white.withAlphaComponent(level * 0.6 * intensity).cgColor, NSColor.clear.cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors as CFArray, locations: [0, 1.0]) {
            context.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: contentRect.midX, y: contentRect.midY), startRadius: 0,
                                       endCenter: CGPoint(x: contentRect.midX, y: contentRect.midY), endRadius: 50 + bass * 50,
                                       options: [])
        }
    }
    
    private func drawWarpEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Space warp with stretching
        let warpStrength = bass * 0.3 * intensity
        let warpAngle = t * 0.5
        
        // Draw warped strips radiating from center
        let strips = 24
        let angleStep = CGFloat.pi * 2 / CGFloat(strips)
        
        for i in 0..<strips {
            let angle = CGFloat(i) * angleStep + warpAngle
            let warp = 1.0 + sin(angle * 3 + t * 2) * warpStrength
            
            let startX = contentRect.midX
            let startY = contentRect.midY
            let endX = startX + cos(angle) * artworkRect.width * warp
            let endY = startY + sin(angle) * artworkRect.height * warp
            
            // Sample color from image center area for this angle
            let hue = fmod(CGFloat(i) / CGFloat(strips) + t * 0.1, 1.0)
            
            context.saveGState()
            context.setBlendMode(.screen)
            context.setStrokeColor(NSColor(hue: hue, saturation: 0.8, brightness: 1.0, alpha: 0.4 * level * intensity).cgColor)
            context.setLineWidth(artworkRect.width / CGFloat(strips) * 1.5)
            context.move(to: CGPoint(x: startX, y: startY))
            context.addLine(to: CGPoint(x: endX, y: endY))
            context.strokePath()
            context.restoreGState()
        }
        
        // Center image
        let centerScale = 0.4 + bass * 0.2
        let centerWidth = artworkRect.width * centerScale
        let centerHeight = artworkRect.height * centerScale
        
        context.saveGState()
        context.translateBy(x: contentRect.midX - centerWidth / 2, y: contentRect.midY + centerHeight / 2)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: centerWidth, height: centerHeight))
        context.restoreGState()
    }
    
    private func drawMatrixEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                  bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw darkened base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.setAlpha(0.5)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Green tint
        context.saveGState()
        context.setBlendMode(.color)
        context.setFillColor(NSColor.green.withAlphaComponent(0.4 * intensity).cgColor)
        context.fill(artworkRect)
        context.restoreGState()
        
        // Matrix rain
        let columns = 30
        let charWidth = artworkRect.width / CGFloat(columns)
        let matrixChars = "01アイウエオカキクケコ"
        
        context.saveGState()
        context.setBlendMode(.plusLighter)
        
        for col in 0..<columns {
            let x = artworkRect.minX + CGFloat(col) * charWidth
            let speed = 100 + CGFloat(col % 5) * 30
            let offset = fmod(t * speed + CGFloat(col * 50), artworkRect.height + 200) - 100
            
            // Draw falling characters
            for row in 0..<15 {
                let y = artworkRect.minY + offset - CGFloat(row) * 15
                if y < artworkRect.minY || y > artworkRect.maxY { continue }
                
                let charIndex = (col + row + Int(t * 10)) % matrixChars.count
                let char = String(matrixChars[matrixChars.index(matrixChars.startIndex, offsetBy: charIndex)])
                let alpha = 1.0 - CGFloat(row) / 15.0
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.green.withAlphaComponent(alpha * level * intensity),
                    .font: NSFont(name: "Menlo", size: 12) ?? NSFont.systemFont(ofSize: 12)
                ]
                
                context.saveGState()
                context.translateBy(x: 0, y: y + 12)
                context.scaleBy(x: 1, y: -1)
                context.translateBy(x: 0, y: -y)
                char.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                context.restoreGState()
            }
        }
        context.restoreGState()
    }
    
    private func drawFireEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Fire overlay from bottom
        let fireHeight = artworkRect.height * (0.3 + bass * 0.4) * intensity
        let flames = 40
        
        context.saveGState()
        context.setBlendMode(.plusLighter)
        
        for i in 0..<flames {
            let x = artworkRect.minX + CGFloat(i) / CGFloat(flames) * artworkRect.width
            let flameHeight = fireHeight * (0.5 + CGFloat.random(in: 0...0.5))
            let flameWidth: CGFloat = artworkRect.width / CGFloat(flames) * 2
            let waveOffset = sin(t * 5 + CGFloat(i) * 0.5) * 10
            
            // Flame gradient
            let flameColors = [
                NSColor(red: 1, green: 1, blue: 0.3, alpha: 0.8 * level).cgColor,  // Yellow core
                NSColor(red: 1, green: 0.5, blue: 0, alpha: 0.6 * level).cgColor,  // Orange
                NSColor(red: 1, green: 0, blue: 0, alpha: 0.3 * level).cgColor,    // Red
                NSColor.clear.cgColor
            ]
            
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: flameColors as CFArray,
                                        locations: [0, 0.3, 0.6, 1.0]) {
                let startPoint = CGPoint(x: x + waveOffset, y: artworkRect.maxY)
                let endPoint = CGPoint(x: x + waveOffset, y: artworkRect.maxY - flameHeight)
                
                context.saveGState()
                context.clip(to: NSRect(x: x - flameWidth/2, y: artworkRect.maxY - flameHeight,
                                       width: flameWidth, height: flameHeight))
                context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
                context.restoreGState()
            }
        }
        context.restoreGState()
        
        // Heat distortion tint
        context.saveGState()
        context.setBlendMode(.overlay)
        context.setFillColor(NSColor.orange.withAlphaComponent(0.2 * bass * intensity).cgColor)
        context.fill(artworkRect)
        context.restoreGState()
    }
    
    private func drawElectricEffect(context: CGContext, cgImage: CGImage, artworkRect: NSRect, contentRect: NSRect,
                                    bass: CGFloat, mid: CGFloat, treble: CGFloat, level: CGFloat, t: CGFloat, intensity: CGFloat) {
        // Draw base
        context.saveGState()
        context.translateBy(x: artworkRect.minX, y: artworkRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: artworkRect.width, height: artworkRect.height))
        context.restoreGState()
        
        // Electric bolts on beats
        if bass > 0.4 {
            let boltCount = Int(bass * 5 * intensity)
            
            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.setStrokeColor(NSColor.cyan.withAlphaComponent(0.8 * bass).cgColor)
            context.setLineWidth(2)
            
            for _ in 0..<boltCount {
                var x = CGFloat.random(in: artworkRect.minX...artworkRect.maxX)
                var y = artworkRect.minY
                
                context.move(to: CGPoint(x: x, y: y))
                
                while y < artworkRect.maxY {
                    x += CGFloat.random(in: -20...20) * intensity
                    y += CGFloat.random(in: 10...30)
                    context.addLine(to: CGPoint(x: x, y: y))
                }
                context.strokePath()
            }
            context.restoreGState()
            
            // Glow
            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.3 * bass).cgColor)
            context.setLineWidth(6)
            
            for _ in 0..<boltCount / 2 {
                var x = CGFloat.random(in: artworkRect.minX...artworkRect.maxX)
                var y = artworkRect.minY
                
                context.move(to: CGPoint(x: x, y: y))
                
                while y < artworkRect.maxY {
                    x += CGFloat.random(in: -20...20) * intensity
                    y += CGFloat.random(in: 10...30)
                    context.addLine(to: CGPoint(x: x, y: y))
                }
                context.strokePath()
            }
            context.restoreGState()
        }
        
        // Electric tint
        let tintAlpha = 0.15 * level * intensity
        context.saveGState()
        context.setBlendMode(.screen)
        context.setFillColor(NSColor.cyan.withAlphaComponent(tintAlpha).cgColor)
        context.fill(artworkRect)
        context.restoreGState()
    }
    
    private func drawAlphabetIndex(in context: CGContext, rect: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        // Background
        colors.normalBackground.withAlphaComponent(0.3).setFill()
        context.fill(rect)
        
        // Calculate letter height based on available space
        let letterCount = CGFloat(alphabetLetters.count)
        let letterHeight = rect.height / letterCount
        let fontSize = min(9, letterHeight * 0.8)
        
        // Build set of sort letters that exist in current items
        // Uses sortLetter() to match how items are actually sorted (strips "The ", "A ", etc.)
        var availableLetters = Set<String>()
        for item in displayItems {
            availableLetters.insert(sortLetter(for: item.title))
        }
        
        for (index, letter) in alphabetLetters.enumerated() {
            let y = rect.minY + CGFloat(index) * letterHeight
            let letterRect = NSRect(x: rect.minX, y: y, width: rect.width, height: letterHeight)
            
            // Highlight if this letter has items
            let hasItems = availableLetters.contains(letter)
            let color = hasItems ? colors.currentText : colors.normalText.withAlphaComponent(0.3)
            
            // Counter-flip for text
            context.saveGState()
            let centerY = letterRect.midY
            context.translateBy(x: 0, y: centerY)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -centerY)
            
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
            
            context.restoreGState()
        }
    }
    
    private func drawStatusBarText(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        // Status info is now shown in the top server bar
        // This function is kept for potential future use but draws nothing
    }
    
    // MARK: - Loading Animation
    
    private func startLoadingAnimation() {
        guard loadingAnimationTimer == nil else { return }
        // Use .common run loop mode so timer continues during context menu display
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadingAnimationFrame += 1
            if self.isLoading {
                // Only redraw the list area where the loading spinner is displayed
                // This prevents menu items from shimmering on non-Retina displays
                var listY = self.Layout.titleBarHeight + self.Layout.serverBarHeight + self.Layout.tabBarHeight
                if self.browseMode == .search {
                    listY += self.Layout.searchBarHeight
                }
                let listHeight = self.bounds.height - listY - self.Layout.statusBarHeight
                // Convert from Winamp top-down coordinates to macOS bottom-up coordinates
                let nativeY = self.Layout.statusBarHeight
                let listRect = NSRect(x: 0, y: nativeY, width: self.bounds.width, height: listHeight)
                self.setNeedsDisplay(listRect)
            } else {
                self.stopLoadingAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        loadingAnimationTimer = timer
    }
    
    private func stopLoadingAnimation() {
        loadingAnimationTimer?.invalidate()
        loadingAnimationTimer = nil
        loadingAnimationFrame = 0
    }
    
    // MARK: - Server Name Scroll Animation
    
    private func startServerNameScroll() {
        guard serverScrollTimer == nil else { return }
        serverScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateServerNameScroll()
        }
    }
    
    private func stopServerNameScroll() {
        serverScrollTimer?.invalidate()
        serverScrollTimer = nil
        serverNameScrollOffset = 0
        libraryNameScrollOffset = 0
    }
    
    private func updateServerNameScroll() {
        let manager = PlexManager.shared
        guard manager.isLinked else {
            if serverNameScrollOffset != 0 || libraryNameScrollOffset != 0 {
                serverNameScrollOffset = 0
                libraryNameScrollOffset = 0
                needsDisplay = true
            }
            return
        }
        
        let charWidth = SkinElements.TextFont.charWidth
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        
        // Max widths for server and library names (matching drawServerBar)
        let maxServerChars = 12
        let maxLibraryChars = 10
        let maxServerWidth = CGFloat(maxServerChars) * scaledCharWidth
        let maxLibraryWidth = CGFloat(maxLibraryChars) * scaledCharWidth
        
        let serverName = manager.currentServer?.name ?? "Select Server"
        let libraryName = manager.currentLibrary?.title ?? "Select Library"
        
        // Reset scroll if names changed
        if serverName != lastServerName {
            lastServerName = serverName
            serverNameScrollOffset = 0
        }
        if libraryName != lastLibraryName {
            lastLibraryName = libraryName
            libraryNameScrollOffset = 0
        }
        
        let serverTextWidth = CGFloat(serverName.count) * scaledCharWidth
        let libraryTextWidth = CGFloat(libraryName.count) * scaledCharWidth
        
        var needsRedraw = false
        
        // Handle server name scrolling
        if serverTextWidth > maxServerWidth {
            let separator = "   "
            let separatorWidth = CGFloat(separator.count) * scaledCharWidth
            let totalCycleWidth = serverTextWidth + separatorWidth
            
            serverNameScrollOffset += 1
            if serverNameScrollOffset >= totalCycleWidth {
                serverNameScrollOffset = 0
            }
            needsRedraw = true
        } else if serverNameScrollOffset != 0 {
            serverNameScrollOffset = 0
            needsRedraw = true
        }
        
        // Handle library name scrolling
        if libraryTextWidth > maxLibraryWidth {
            let separator = "   "
            let separatorWidth = CGFloat(separator.count) * scaledCharWidth
            let totalCycleWidth = libraryTextWidth + separatorWidth
            
            libraryNameScrollOffset += 1
            if libraryNameScrollOffset >= totalCycleWidth {
                libraryNameScrollOffset = 0
            }
            needsRedraw = true
        } else if libraryNameScrollOffset != 0 {
            libraryNameScrollOffset = 0
            needsRedraw = true
        }
        
        if needsRedraw {
            let serverBarArea = NSRect(x: 0, y: bounds.height - Layout.titleBarHeight - Layout.serverBarHeight,
                                       width: bounds.width, height: Layout.serverBarHeight)
            setNeedsDisplay(serverBarArea)
        }
    }
    
    // MARK: - Public Methods
    
    func reloadData() {
        // Radio source - only radio tab has content (Internet Radio stations)
        if case .radio = currentSource {
            if browseMode == .radio {
                loadRadioStations()
            } else {
                displayItems = []
            }
            needsDisplay = true
            return
        }
        
        // Non-radio sources: radio tab shows Plex Radio options (for Plex) or empty
        if browseMode == .radio {
            if case .plex = currentSource, PlexManager.shared.isLinked {
                // Show Plex Radio options in the RADIO tab when in Plex mode
                loadPlexRadioStations()
            } else {
                displayItems = []
            }
            needsDisplay = true
            return
        }
        
        // For local source, we don't need Plex to be linked
        if case .local = currentSource {
            loadLocalData()
            needsDisplay = true
            return
        }
        
        // For Subsonic source
        if case .subsonic(let serverId) = currentSource {
            loadSubsonicData(serverId: serverId)
            return
        }
        
        // For Plex source, check if linked
        guard PlexManager.shared.isLinked else {
            displayItems = []
            stopLoadingAnimation()
            needsDisplay = true
            return
        }
        
        // If we're still connecting to a server, show loading state
        if case .connecting = PlexManager.shared.connectionState {
            isLoading = true
            errorMessage = nil
            startLoadingAnimation()
            needsDisplay = true
            return
        }
        
        // If no server client yet, show loading and try to connect
        if PlexManager.shared.serverClient == nil {
            isLoading = true
            errorMessage = nil
            startLoadingAnimation()
            needsDisplay = true
            
            // Try to connect to current server if we have one
            if let server = PlexManager.shared.currentServer {
                Task { @MainActor in
                    do {
                        try await PlexManager.shared.connect(to: server)
                        loadDataForCurrentMode()
                    } catch {
                        isLoading = false
                        stopLoadingAnimation()
                        errorMessage = error.localizedDescription
                        needsDisplay = true
                    }
                }
            } else if !PlexManager.shared.servers.isEmpty {
                Task { @MainActor in
                    do {
                        try await PlexManager.shared.refreshServers()
                        loadDataForCurrentMode()
                    } catch {
                        isLoading = false
                        stopLoadingAnimation()
                        errorMessage = error.localizedDescription
                        needsDisplay = true
                    }
                }
            } else {
                Task { @MainActor in
                    do {
                        try await PlexManager.shared.refreshServers()
                        if PlexManager.shared.currentServer != nil {
                            loadDataForCurrentMode()
                        } else {
                            isLoading = false
                            stopLoadingAnimation()
                            errorMessage = "No Plex servers found"
                            needsDisplay = true
                        }
                    } catch {
                        isLoading = false
                        stopLoadingAnimation()
                        errorMessage = error.localizedDescription
                        needsDisplay = true
                    }
                }
            }
            return
        }
        
        loadDataForCurrentMode()
    }
    
    /// Refresh all data - clears cache and reloads from server
    func refreshData() {
        guard PlexManager.shared.isLinked else { return }
        
        // Clear all cached data
        cachedArtists = []
        cachedAlbums = []
        cachedTracks = []
        artistAlbums = [:]
        albumTracks = [:]
        artistAlbumCounts = [:]
        cachedMovies = []
        cachedShows = []
        showSeasons = [:]
        seasonEpisodes = [:]
        cachedPlexPlaylists = []
        plexPlaylistTracks = [:]
        searchResults = nil
        
        // Reset expanded states
        expandedArtists = []
        expandedAlbums = []
        expandedShows = []
        expandedSeasons = []
        expandedPlexPlaylists = []
        
        // Reset selection and scroll
        selectedIndices = []
        scrollOffset = 0
        
        // Show loading state
        isLoading = true
        errorMessage = nil
        displayItems = []
        startLoadingAnimation()
        needsDisplay = true
        
        // Also clear PlexManager's cached content to ensure fresh fetch
        PlexManager.shared.clearCachedContent()
        
        NSLog("PlexBrowserView: Refreshing data...")
        
        // Reload data for current mode
        loadDataForCurrentMode()
    }
    
    func skinDidChange() {
        needsDisplay = true
    }
    
    /// Set shade mode externally (e.g., from controller)
    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        needsDisplay = true
    }
    
    /// Toggle shade mode
    private func toggleShadeMode() {
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    @objc private func plexStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            if case .connecting = PlexManager.shared.connectionState {
                self?.isLoading = true
                self?.errorMessage = nil
                self?.needsDisplay = true
                return
            }
            self?.reloadData()
        }
    }
    
    @objc private func plexServerDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if case .connecting = PlexManager.shared.connectionState {
                NSLog("PlexBrowserView: Server list changed, but still connecting - just updating display")
                self.needsDisplay = true
                return
            }
            
            // Check if we have a pending source to restore now that servers are loaded
            if let pending = self.pendingSourceRestore {
                self.pendingSourceRestore = nil
                
                switch pending {
                case .plex(let serverId):
                    if PlexManager.shared.servers.contains(where: { $0.id == serverId }) {
                        NSLog("PlexBrowserView: Restoring pending Plex source: %@", serverId)
                        self.currentSource = pending
                        return
                    } else if let firstServer = PlexManager.shared.servers.first {
                        NSLog("PlexBrowserView: Pending server not found, using first server")
                        self.currentSource = .plex(serverId: firstServer.id)
                        return
                    }
                case .subsonic(let serverId):
                    if SubsonicManager.shared.servers.contains(where: { $0.id == serverId }) {
                        NSLog("PlexBrowserView: Restoring pending Subsonic source: %@", serverId)
                        self.currentSource = pending
                        return
                    } else if let firstServer = SubsonicManager.shared.servers.first {
                        NSLog("PlexBrowserView: Pending Subsonic server not found, using first server")
                        self.currentSource = .subsonic(serverId: firstServer.id)
                        return
                    }
                case .local:
                    break
                case .radio:
                    self.currentSource = .radio
                    return
                }
            }
            
            NSLog("PlexBrowserView: Server changed, clearing cache and reloading")
            self.clearAllCachedData()
            self.reloadData()
        }
    }
    
    private func clearAllCachedData() {
        cachedArtists = []
        cachedAlbums = []
        cachedTracks = []
        artistAlbums = [:]
        albumTracks = [:]
        artistAlbumCounts = [:]
        expandedArtists = []
        expandedAlbums = []
        
        cachedMovies = []
        cachedShows = []
        showSeasons = [:]
        seasonEpisodes = [:]
        expandedShows = []
        expandedSeasons = []
        
        searchResults = nil
    }
    
    // MARK: - Artwork Background
    
    @objc private func trackDidChange(_ notification: Notification) {
        // Fetch new track's rating and reload artwork when in art mode
        if isArtOnlyMode {
            fetchCurrentTrackRating()
            loadAllArtworkForCurrentTrack()
        }
        
        guard WindowManager.shared.showBrowserArtworkBackground else {
            // Clear artwork if feature is disabled
            if currentArtwork != nil {
                currentArtwork = nil
                artworkTrackId = nil
                needsDisplay = true
            }
            return
        }
        
        let track = notification.userInfo?["track"] as? Track
        loadArtwork(for: track)
    }
    
    /// Load artwork for a track (Plex or local)
    private func loadArtwork(for track: Track?) {
        // Cancel any pending load
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        
        guard let track = track else {
            // No track playing - keep selection artwork (if any), just clear track ID
            // This allows Plex Radio selection artwork to persist when nothing is playing
            artworkTrackId = nil
            return
        }
        
        // Skip if same track
        guard track.id != artworkTrackId else { return }
        
        // Don't clear artwork immediately - wait until new image is ready
        // This prevents the "flash and disappear" when switching from selection artwork to track artwork
        
        artworkLoadTask = Task { [weak self] in
            guard let self = self else { return }
            
            var image: NSImage?
            
            if let plexRatingKey = track.plexRatingKey {
                // Plex track - load from server
                image = await self.loadPlexArtwork(ratingKey: plexRatingKey, albumName: track.album)
                
                // Fallback to TMDb for video tracks when Plex artwork fails
                if image == nil && track.mediaType == .video {
                    // Parse year from title if present (e.g., "Movie Name (2023)")
                    var movieTitle = track.title
                    var movieYear: Int?
                    if let range = movieTitle.range(of: #"\s*\(\d{4}\)\s*$"#, options: .regularExpression) {
                        let yearString = String(movieTitle[range]).trimmingCharacters(in: .whitespaces)
                        movieYear = Int(yearString.trimmingCharacters(in: CharacterSet(charactersIn: "()")))
                        movieTitle = String(movieTitle[..<range.lowerBound])
                    }
                    image = await self.loadMovieWebArtwork(title: movieTitle, year: movieYear)
                }
            } else if let subsonicId = track.subsonicId {
                // Subsonic track - load from server
                image = await self.loadSubsonicArtwork(songId: subsonicId, albumName: track.album)
            } else if track.url.isFileURL {
                // Local file - extract embedded artwork
                image = await self.loadLocalArtwork(url: track.url)
                
                // If no embedded artwork, try fetching from web
                if image == nil {
                    if track.mediaType == .video {
                        // Video file - try TMDb
                        image = await self.loadMovieWebArtwork(title: track.title, year: nil)
                    } else {
                        // Audio file - try iTunes
                        image = await self.loadWebArtwork(artist: track.artist, album: track.album, title: track.title)
                    }
                }
            }
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.currentArtwork = image
                self.artworkTrackId = track.id
                self.needsDisplay = true
            }
        }
    }
    
    /// Load artwork from web using iTunes Search API
    private func loadWebArtwork(artist: String?, album: String?, title: String?) async -> NSImage? {
        // Build search query - prefer album search, fall back to track
        var searchTerm: String
        if let artist = artist, !artist.isEmpty, let album = album, !album.isEmpty {
            searchTerm = "\(artist) \(album)"
        } else if let artist = artist, !artist.isEmpty, let title = title, !title.isEmpty {
            searchTerm = "\(artist) \(title)"
        } else if let album = album, !album.isEmpty {
            searchTerm = album
        } else {
            return nil
        }
        
        // Check cache first
        let cacheKey = NSString(string: "web:\(searchTerm)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) {
            return cached
        }
        
        // URL encode the search term
        guard let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Use iTunes Search API
        let urlString = "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=album&limit=1"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Parse JSON response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let firstResult = results.first,
               let artworkUrlString = firstResult["artworkUrl100"] as? String {
                
                // Get higher resolution artwork (600x600 instead of 100x100)
                let highResUrl = artworkUrlString.replacingOccurrences(of: "100x100", with: "600x600")
                
                if let artworkUrl = URL(string: highResUrl) {
                    let (imageData, _) = try await URLSession.shared.data(from: artworkUrl)
                    if let image = NSImage(data: imageData) {
                        // Cache the result
                        Self.artworkCache.setObject(image, forKey: cacheKey)
                        NSLog("PlexBrowserView: Loaded web artwork for: %@", searchTerm)
                        return image
                    }
                }
            }
        } catch {
            NSLog("PlexBrowserView: Failed to load web artwork: %@", error.localizedDescription)
        }
        
        return nil
    }
    
    /// Load artwork for a Plex track using its rating key
    private func loadPlexArtwork(ratingKey: String, albumName: String? = nil) async -> NSImage? {
        // Check cache first
        let cacheKey = NSString(string: "plex:\(ratingKey)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Find the thumb path from cached data
        var thumbPath: String?
        
        // Check cached tracks
        if let plexTrack = cachedTracks.first(where: { $0.id == ratingKey }) {
            thumbPath = plexTrack.thumb
        }
        
        // Check album tracks cache
        if thumbPath == nil {
            for (_, tracks) in albumTracks {
                if let plexTrack = tracks.first(where: { $0.id == ratingKey }) {
                    thumbPath = plexTrack.thumb
                    break
                }
            }
        }
        
        // Check cached albums by ID
        if thumbPath == nil {
            if let album = cachedAlbums.first(where: { $0.id == ratingKey }) {
                thumbPath = album.thumb
            }
        }
        
        // Try to find album by name (fallback when track not in cache)
        if thumbPath == nil, let albumName = albumName, !albumName.isEmpty {
            if let album = cachedAlbums.first(where: { $0.title.lowercased() == albumName.lowercased() }) {
                thumbPath = album.thumb
                NSLog("PlexBrowserView: Found album art by name match: %@", albumName)
            }
        }
        
        // If still not found, construct the thumb path directly from the rating key
        // Plex allows fetching artwork using /library/metadata/{ratingKey}/thumb
        if thumbPath == nil {
            thumbPath = "/library/metadata/\(ratingKey)/thumb"
            NSLog("PlexBrowserView: Using direct rating key path for artwork: %@", ratingKey)
        }
        
        guard let thumb = thumbPath,
              let artworkURL = PlexManager.shared.artworkURL(thumb: thumb, size: 400) else {
            NSLog("PlexBrowserView: Could not construct artwork URL for rating key: %@", ratingKey)
            return nil
        }
        
        NSLog("PlexBrowserView: Loading artwork from: %@", artworkURL.absoluteString)
        
        // Download the image
        do {
            var request = URLRequest(url: artworkURL)
            // Add Plex headers if needed
            if let headers = PlexManager.shared.streamingHeaders {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("PlexBrowserView: Non-HTTP response for artwork")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                NSLog("PlexBrowserView: Artwork request failed with status: %d", httpResponse.statusCode)
                return nil
            }
            
            guard let image = NSImage(data: data) else {
                NSLog("PlexBrowserView: Could not create image from data (%d bytes)", data.count)
                return nil
            }
            
            // Cache the image
            Self.artworkCache.setObject(image, forKey: cacheKey)
            NSLog("PlexBrowserView: Successfully loaded artwork for rating key: %@", ratingKey)
            
            return image
        } catch {
            NSLog("PlexBrowserView: Failed to load Plex artwork: %@", error.localizedDescription)
            return nil
        }
    }
    
    /// Load cover art from a Subsonic server
    private func loadSubsonicArtwork(songId: String, albumName: String? = nil) async -> NSImage? {
        // Check cache first
        let cacheKey = NSString(string: "subsonic:\(songId)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Find the cover art ID from cached data
        var coverArtId: String?
        
        // Check cached albums for this song
        for (_, songs) in subsonicAlbumSongs {
            if let song = songs.first(where: { $0.id == songId }) {
                coverArtId = song.coverArt
                break
            }
        }
        
        // Check cached albums by name
        if coverArtId == nil, let albumName = albumName {
            if let album = cachedSubsonicAlbums.first(where: { $0.name == albumName }) {
                coverArtId = album.coverArt
            }
        }
        
        // Try using the song ID as cover art ID (some servers support this)
        if coverArtId == nil {
            coverArtId = songId
        }
        
        guard let artworkURL = SubsonicManager.shared.coverArtURL(coverArtId: coverArtId, size: 400) else {
            NSLog("PlexBrowserView: Could not construct Subsonic artwork URL for song: %@", songId)
            return nil
        }
        
        NSLog("PlexBrowserView: Loading Subsonic artwork from: %@", artworkURL.absoluteString)
        
        // Download the image
        do {
            let (data, response) = try await URLSession.shared.data(from: artworkURL)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("PlexBrowserView: Non-HTTP response for Subsonic artwork")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                NSLog("PlexBrowserView: HTTP %d for Subsonic artwork", httpResponse.statusCode)
                return nil
            }
            
            guard let image = NSImage(data: data) else {
                NSLog("PlexBrowserView: Could not create image from Subsonic artwork data")
                return nil
            }
            
            // Cache the image
            Self.artworkCache.setObject(image, forKey: cacheKey)
            
            return image
        } catch {
            NSLog("PlexBrowserView: Failed to load Subsonic artwork: %@", error.localizedDescription)
            return nil
        }
    }
    
    /// Load embedded artwork from a local audio file
    private func loadLocalArtwork(url: URL) async -> NSImage? {
        // Check cache first
        let cacheKey = NSString(string: "local:\(url.path)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Extract artwork using AVFoundation
        let asset = AVURLAsset(url: url)
        
        do {
            let metadata = try await asset.load(.metadata)
            
            for item in metadata {
                // Check for artwork in common metadata
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        // Cache the image
                        Self.artworkCache.setObject(image, forKey: cacheKey)
                        return image
                    }
                }
            }
            
            // Also check ID3 metadata format
            let id3Metadata = try await asset.loadMetadata(for: .id3Metadata)
            for item in id3Metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        Self.artworkCache.setObject(image, forKey: cacheKey)
                        return image
                    }
                }
            }
            
            // Check iTunes metadata format
            let itunesMetadata = try await asset.loadMetadata(for: .iTunesMetadata)
            for item in itunesMetadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        Self.artworkCache.setObject(image, forKey: cacheKey)
                        return image
                    }
                }
            }
        } catch {
            NSLog("PlexBrowserView: Failed to load local artwork: %@", error.localizedDescription)
        }
        
        return nil
    }
    
    /// Extract all embedded artwork images from a local audio file
    /// Returns array of images (deduped across different metadata formats)
    private func loadAllLocalArtwork(url: URL) async -> [NSImage] {
        var images: [NSImage] = []
        var seenData: Set<Int> = []  // Track seen images by data hash
        
        let asset = AVURLAsset(url: url)
        
        do {
            // Check common metadata
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        let hash = data.hashValue
                        if !seenData.contains(hash) {
                            seenData.insert(hash)
                            images.append(image)
                        }
                    }
                }
            }
            
            // Check ID3 metadata (MP3 files - may have multiple APIC frames)
            let id3Metadata = try await asset.loadMetadata(for: .id3Metadata)
            for item in id3Metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        let hash = data.hashValue
                        if !seenData.contains(hash) {
                            seenData.insert(hash)
                            images.append(image)
                        }
                    }
                }
            }
            
            // Check iTunes metadata (M4A/AAC files)
            let itunesMetadata = try await asset.loadMetadata(for: .iTunesMetadata)
            for item in itunesMetadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        let hash = data.hashValue
                        if !seenData.contains(hash) {
                            seenData.insert(hash)
                            images.append(image)
                        }
                    }
                }
            }
        } catch {
            NSLog("PlexBrowserView: Failed to load all local artwork: %@", error.localizedDescription)
        }
        
        return images
    }
    
    /// Cycle to the next artwork image in art-only mode
    private func cycleToNextArtwork() {
        guard artworkImages.count > 1 else {
            // Only one image (or none) - nothing to cycle
            return
        }
        
        artworkIndex = (artworkIndex + 1) % artworkImages.count
        currentArtwork = artworkImages[artworkIndex]
        needsDisplay = true
    }
    
    /// Load all available artwork for the currently playing track
    private func loadAllArtworkForCurrentTrack() {
        // Cancel any pending artwork cycling task
        artworkCyclingTask?.cancel()
        artworkCyclingTask = nil
        
        guard let currentTrack = WindowManager.shared.audioEngine.currentTrack else {
            artworkImages = []
            artworkIndex = 0
            return
        }
        
        // Clear cycling array immediately to prevent cycling through stale images
        // Note: Don't clear currentArtwork here - loadArtwork(for:) handles the main display
        artworkImages = []
        artworkIndex = 0
        
        artworkCyclingTask = Task { [weak self] in
            guard let self = self else { return }
            
            var images: [NSImage] = []
            
            if currentTrack.url.isFileURL {
                // Local file - extract all embedded artwork
                images = await self.loadAllLocalArtwork(url: currentTrack.url)
            } else if let plexRatingKey = currentTrack.plexRatingKey {
                // Plex track - load track artwork using existing method
                if let image = await self.loadPlexArtwork(ratingKey: plexRatingKey, albumName: currentTrack.album) {
                    images.append(image)
                }
            } else if let subsonicId = currentTrack.subsonicId {
                // Subsonic track - load cover art using existing method
                if let image = await self.loadSubsonicArtwork(songId: subsonicId, albumName: currentTrack.album) {
                    images.append(image)
                }
            }
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.artworkImages = images
                self.artworkIndex = 0
                if let first = images.first {
                    self.currentArtwork = first
                    self.needsDisplay = true
                }
            }
        }
    }
    
    /// Load artwork based on the currently selected item in the browser
    /// Called when selection changes to show artwork for browsed items (not just playing items)
    private func loadArtworkForSelection() {
        guard WindowManager.shared.showBrowserArtworkBackground else { return }
        guard let index = selectedIndices.first, index < displayItems.count else { return }
        
        let item = displayItems[index]
        
        // Cancel any pending load
        artworkLoadTask?.cancel()
        
        artworkLoadTask = Task { [weak self] in
            guard let self = self else { return }
            
            var image: NSImage?
            
            switch item.type {
            case .movie(let movie):
                if let thumb = movie.thumb {
                    image = await self.loadPlexArtworkByThumb(thumb: thumb, cacheKey: "plex:\(movie.id)")
                }
                // Fallback to TMDb if Plex artwork not available
                if image == nil {
                    image = await self.loadMovieWebArtwork(title: movie.title, year: movie.year)
                }
                
            case .episode(let episode):
                if let thumb = episode.thumb {
                    image = await self.loadPlexArtworkByThumb(thumb: thumb, cacheKey: "plex:\(episode.id)")
                }
                
            case .album(let album):
                if let thumb = album.thumb {
                    image = await self.loadPlexArtworkByThumb(thumb: thumb, cacheKey: "plex:\(album.id)")
                }
                
            case .artist(let artist):
                if let thumb = artist.thumb {
                    image = await self.loadPlexArtworkByThumb(thumb: thumb, cacheKey: "plex:\(artist.id)")
                }
                
            case .show(let show):
                if let thumb = show.thumb {
                    image = await self.loadPlexArtworkByThumb(thumb: thumb, cacheKey: "plex:\(show.id)")
                }
                
            case .season(let season):
                if let thumb = season.thumb {
                    image = await self.loadPlexArtworkByThumb(thumb: thumb, cacheKey: "plex:\(season.id)")
                }
                
            case .track(let track):
                if let thumb = track.thumb {
                    image = await self.loadPlexArtworkByThumb(thumb: thumb, cacheKey: "plex:\(track.id)")
                }
                
            case .localTrack(let track):
                image = await self.loadLocalArtwork(url: track.url)
                if image == nil {
                    image = await self.loadWebArtwork(artist: track.artist, album: track.album, title: track.title)
                }
                
            case .localAlbum(let album):
                if let track = album.tracks.first {
                    image = await self.loadLocalArtwork(url: track.url)
                }
                
            case .subsonicAlbum(let album):
                if let coverArt = album.coverArt {
                    image = await self.loadSubsonicArtworkByCoverId(coverArt: coverArt, cacheKey: "subsonic:\(album.id)")
                }
                
            case .subsonicTrack(let song):
                if let coverArt = song.coverArt {
                    image = await self.loadSubsonicArtworkByCoverId(coverArt: coverArt, cacheKey: "subsonic:\(song.id)")
                }
                
            case .localArtist(let artist):
                // Load artwork from first track by this artist
                let artistTracks = self.cachedLocalTracks.filter { $0.artist == artist.name }
                if let firstTrack = artistTracks.first {
                    image = await self.loadLocalArtwork(url: firstTrack.url)
                    if image == nil {
                        image = await self.loadWebArtwork(artist: firstTrack.artist, album: firstTrack.album, title: firstTrack.title)
                    }
                }
                
            case .subsonicArtist(let artist):
                // Load artist image if available
                if let coverArt = artist.coverArt {
                    image = await self.loadSubsonicArtworkByCoverId(coverArt: coverArt, cacheKey: "subsonic:\(artist.id)")
                }
                
            case .subsonicPlaylist(let playlist):
                if let coverArt = playlist.coverArt {
                    image = await self.loadSubsonicArtworkByCoverId(coverArt: coverArt, cacheKey: "subsonic:playlist:\(playlist.id)")
                }
                
            case .plexPlaylist(let playlist):
                if let thumb = playlist.thumb {
                    image = await self.loadPlexArtworkByThumb(thumb: thumb, cacheKey: "plex:playlist:\(playlist.id)")
                }
                
            case .plexRadioStation, .radioStation, .header:
                // Radio stations load artwork when playing, not on selection
                break
            }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if image != nil {
                    self.currentArtwork = image
                    self.artworkTrackId = nil  // Clear track ID since this is from selection
                    self.needsDisplay = true
                }
            }
        }
    }
    
    /// Load artwork from Plex using a thumb path directly
    private func loadPlexArtworkByThumb(thumb: String, cacheKey: String) async -> NSImage? {
        // Check cache first
        let cacheNSKey = NSString(string: cacheKey)
        if let cached = Self.artworkCache.object(forKey: cacheNSKey) {
            return cached
        }
        
        guard let artworkURL = PlexManager.shared.artworkURL(thumb: thumb, size: 400) else {
            return nil
        }
        
        do {
            var request = URLRequest(url: artworkURL)
            if let headers = PlexManager.shared.streamingHeaders {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = NSImage(data: data) else {
                return nil
            }
            
            Self.artworkCache.setObject(image, forKey: cacheNSKey)
            return image
        } catch {
            return nil
        }
    }
    
    /// Load artwork from Subsonic using a cover art ID directly
    private func loadSubsonicArtworkByCoverId(coverArt: String, cacheKey: String) async -> NSImage? {
        // Check cache first
        let cacheNSKey = NSString(string: cacheKey)
        if let cached = Self.artworkCache.object(forKey: cacheNSKey) {
            return cached
        }
        
        guard let artworkURL = SubsonicManager.shared.coverArtURL(coverArtId: coverArt, size: 400) else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: artworkURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = NSImage(data: data) else {
                return nil
            }
            
            Self.artworkCache.setObject(image, forKey: cacheNSKey)
            return image
        } catch {
            return nil
        }
    }
    
    /// Load movie poster from TMDb (The Movie Database) as fallback
    private func loadMovieWebArtwork(title: String, year: Int?) async -> NSImage? {
        // Build search query
        var searchTerm = title
        if let year = year {
            searchTerm += " \(year)"
        }
        
        // Check cache first
        let cacheKey = NSString(string: "tmdb:\(searchTerm)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) {
            return cached
        }
        
        // URL encode the search term
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Use TMDb Search API
        // Note: This uses the public search endpoint which works without authentication for basic queries
        var urlString = "https://api.themoviedb.org/3/search/movie?query=\(encoded)"
        if let year = year {
            urlString += "&year=\(year)"
        }
        
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            var request = URLRequest(url: url)
            // TMDb requires an API key - use the read-only public key for search
            // This is a standard read-only key that allows basic search functionality
            request.setValue("Bearer eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJlNjUyZmJjMjE3NTcxYTZjNzU4NmYwNzE1MWQ4ZmRjOCIsInN1YiI6IjY1YjUyYTc3MGYyZmJkMDE3YzQ0OGU1OSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.tWcXq_3A4N4gP4Jz5MJNqVWfHBNZdEbwLZZGpZU9hTw", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Parse JSON response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let firstResult = results.first,
               let posterPath = firstResult["poster_path"] as? String {
                
                // Fetch poster image (w500 is a good size for display)
                let posterUrlString = "https://image.tmdb.org/t/p/w500\(posterPath)"
                
                if let posterUrl = URL(string: posterUrlString) {
                    let (imageData, _) = try await URLSession.shared.data(from: posterUrl)
                    if let image = NSImage(data: imageData) {
                        // Cache the result
                        Self.artworkCache.setObject(image, forKey: cacheKey)
                        NSLog("PlexBrowserView: Loaded TMDb poster for: %@", title)
                        return image
                    }
                }
            }
        } catch {
            NSLog("PlexBrowserView: Failed to load TMDb poster: %@", error.localizedDescription)
        }
        
        return nil
    }
    
    /// Calculate a centered fit rect for artwork - scales to fit entirely within bounds, centered
    private func calculateCenterFillRect(imageSize: NSSize, in targetRect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return targetRect }
        
        let imageAspect = imageSize.width / imageSize.height
        let targetAspect = targetRect.width / targetRect.height
        
        var width: CGFloat
        var height: CGFloat
        
        if imageAspect > targetAspect {
            // Image is wider than target - fit to width, scale height proportionally
            width = targetRect.width
            height = width / imageAspect
        } else {
            // Image is taller than target - fit to height, scale width proportionally
            height = targetRect.height
            width = height * imageAspect
        }
        
        // Center the rect within the target
        let x = targetRect.minX + (targetRect.width - width) / 2
        let y = targetRect.minY + (targetRect.height - height) / 2
        
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Hit Testing
    
    /// Check if point hits title bar (for dragging)
    private func hitTestTitleBar(at winampPoint: NSPoint) -> Bool {
        let originalSize = originalWindowSize
        return winampPoint.y < Layout.titleBarHeight &&
               winampPoint.x < originalSize.width - 30  // Leave room for window buttons
    }
    
    /// Check if point hits close button
    /// Uses LibraryWindow offsets to match where SkinRenderer draws the buttons
    private func hitTestCloseButton(at winampPoint: NSPoint) -> Bool {
        let originalSize = originalWindowSize
        let closeRect = NSRect(x: originalSize.width - SkinElements.LibraryWindow.TitleBarButtons.closeOffset - 9,
                               y: 4, width: 9, height: 9)
        return closeRect.contains(winampPoint)
    }
    
    /// Check if point hits shade button
    /// Uses LibraryWindow offsets to match where SkinRenderer draws the buttons
    private func hitTestShadeButton(at winampPoint: NSPoint) -> Bool {
        let originalSize = originalWindowSize
        let shadeRect = NSRect(x: originalSize.width - SkinElements.LibraryWindow.TitleBarButtons.shadeOffset - 9,
                               y: 4, width: 9, height: 9)
        return shadeRect.contains(winampPoint)
    }
    
    /// Check if point is in server bar
    private func hitTestServerBar(at winampPoint: NSPoint) -> Bool {
        let serverBarY = Layout.titleBarHeight
        return winampPoint.y >= serverBarY && winampPoint.y < serverBarY + Layout.serverBarHeight
    }
    
    /// Check if point is in tab bar and return tab index
    private func hitTestTabBar(at winampPoint: NSPoint) -> Int? {
        let tabY = Layout.titleBarHeight + Layout.serverBarHeight
        guard winampPoint.y >= tabY && winampPoint.y < tabY + Layout.tabBarHeight else { return nil }
        
        // Calculate sort indicator width (same as in drawTabBar)
        let charWidth = SkinElements.TextFont.charWidth
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        let sortText = "Sort"
        let sortWidth = CGFloat(sortText.count) * scaledCharWidth + 8
        
        // Tabs area excludes sort indicator
        let tabsWidth = originalWindowSize.width - Layout.leftBorder - Layout.rightBorder - sortWidth
        let tabWidth = tabsWidth / CGFloat(PlexBrowseMode.allCases.count)
        let relativeX = winampPoint.x - Layout.leftBorder
        
        if relativeX >= 0 && relativeX < tabsWidth {
            return Int(relativeX / tabWidth)
        }
        return nil
    }
    
    /// Check if point is in sort indicator area
    private func hitTestSortIndicator(at winampPoint: NSPoint) -> Bool {
        let tabY = Layout.titleBarHeight + Layout.serverBarHeight
        guard winampPoint.y >= tabY && winampPoint.y < tabY + Layout.tabBarHeight else { return false }
        
        // Calculate sort indicator width
        let charWidth = SkinElements.TextFont.charWidth
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        let sortText = "Sort:\(currentSort.shortName)"
        let sortWidth = CGFloat(sortText.count) * scaledCharWidth + 8
        
        let sortX = originalWindowSize.width - Layout.rightBorder - sortWidth
        return winampPoint.x >= sortX && winampPoint.x < originalWindowSize.width - Layout.rightBorder
    }
    
    /// Check if point is in search bar
    private func hitTestSearchBar(at winampPoint: NSPoint) -> Bool {
        guard browseMode == .search else { return false }
        let searchY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        return winampPoint.y >= searchY && winampPoint.y < searchY + Layout.searchBarHeight
    }
    
    /// Check if point is in alphabet index
    private func hitTestAlphabetIndex(at winampPoint: NSPoint) -> Bool {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
        let alphabetX = originalWindowSize.width - Layout.rightBorder - Layout.scrollbarWidth - Layout.alphabetWidth
        
        return winampPoint.x >= alphabetX && winampPoint.x < alphabetX + Layout.alphabetWidth &&
               winampPoint.y >= listY && winampPoint.y < listY + listHeight
    }
    
    /// Check if point is in list area and return item index
    private func hitTestListArea(at winampPoint: NSPoint) -> Int? {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        
        // Check if columns are shown (affects content start position)
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        var contentY = listY
        if hasColumns {
            contentY += columnHeaderHeight
        }
        
        let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
        let contentHeight = listHeight - (hasColumns ? columnHeaderHeight : 0)
        
        let listRect = NSRect(
            x: Layout.leftBorder,
            y: contentY,
            width: originalWindowSize.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth - Layout.alphabetWidth,
            height: contentHeight
        )
        
        guard listRect.contains(winampPoint) else { return nil }
        
        let relativeY = winampPoint.y - contentY + scrollOffset
        let clickedIndex = Int(relativeY / itemHeight)
        
        if clickedIndex >= 0 && clickedIndex < displayItems.count {
            return clickedIndex
        }
        
        return nil
    }
    
    /// Check if point hits a column resize handle (returns column id to resize)
    private func hitTestColumnResize(at winampPoint: NSPoint) -> String? {
        // Only applies when columns are shown
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        guard hasColumns else { return nil }
        
        // Check if in header area (account for search bar when in search mode)
        var headerY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            headerY += Layout.searchBarHeight
        }
        let headerRect = NSRect(x: Layout.leftBorder, y: headerY,
                               width: originalWindowSize.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth - Layout.alphabetWidth,
                               height: columnHeaderHeight)
        
        guard headerRect.contains(winampPoint) else { return nil }
        
        // Determine which columns to check (priority: tracks > albums > artists)
        let columns: [BrowserColumn]
        if displayItems.contains(where: {
            switch $0.type { case .track, .subsonicTrack, .localTrack: return true; default: return false }
        }) {
            columns = BrowserColumn.trackColumns
        } else if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum: return true; default: return false }
        }) {
            columns = BrowserColumn.albumColumns
        } else {
            columns = BrowserColumn.artistColumns
        }
        
        // Check if near a column separator (within 4 pixels)
        var x = headerRect.minX + 4
        let hitMargin: CGFloat = 4
        
        for (index, column) in columns.enumerated() {
            let width = widthForColumn(column, availableWidth: headerRect.width, columns: columns)
            let separatorX = x + width
            
            // Check if click is near the separator (except for last column)
            if index < columns.count - 1 && column.id != "title" {
                if abs(winampPoint.x - separatorX) < hitMargin {
                    return column.id
                }
            }
            x += width
        }
        
        return nil
    }
    
    /// Check if point hits a column header (returns column id for sorting)
    private func hitTestColumnHeader(at winampPoint: NSPoint) -> String? {
        // Only applies when columns are shown
        let hasColumns = displayItems.contains { columnsForItem($0) != nil }
        guard hasColumns else { return nil }
        
        // Check if in header area
        var headerY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            headerY += Layout.searchBarHeight
        }
        let headerRect = NSRect(x: Layout.leftBorder, y: headerY,
                               width: originalWindowSize.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth - Layout.alphabetWidth,
                               height: columnHeaderHeight)
        
        guard headerRect.contains(winampPoint) else { return nil }
        
        // Check if on a resize handle first (don't trigger sort)
        if hitTestColumnResize(at: winampPoint) != nil {
            return nil
        }
        
        // Determine which columns to check (priority: tracks > albums > artists)
        let columns: [BrowserColumn]
        if displayItems.contains(where: {
            switch $0.type { case .track, .subsonicTrack, .localTrack: return true; default: return false }
        }) {
            columns = BrowserColumn.trackColumns
        } else if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum: return true; default: return false }
        }) {
            columns = BrowserColumn.albumColumns
        } else {
            columns = BrowserColumn.artistColumns
        }
        
        // Find which column was clicked
        var x = headerRect.minX + 4
        
        for column in columns {
            let width = widthForColumn(column, availableWidth: headerRect.width, columns: columns)
            if winampPoint.x >= x && winampPoint.x < x + width {
                return column.id
            }
            x += width
        }
        
        return nil
    }
    
    /// Check if point hits the scrollbar
    private func hitTestScrollbar(at winampPoint: NSPoint) -> Bool {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
        
        // Scrollbar hit area: scrollbar (10px) + right border (6px) = 16px
        // Must not overlap with alphabet index area (which is to the left of scrollbar)
        let scrollbarRect = NSRect(
            x: originalWindowSize.width - Layout.rightBorder - Layout.scrollbarWidth,
            y: listY,
            width: Layout.rightBorder + Layout.scrollbarWidth,
            height: listHeight
        )
        
        return scrollbarRect.contains(winampPoint)
    }
    
    // MARK: - Cursor Tracking
    
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
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = convertToWinampCoordinates(point)
        
        // Show resize cursor when over column resize handles
        if hitTestColumnResize(at: winampPoint) != nil {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
    
    // MARK: - Mouse Events
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = convertToWinampCoordinates(point)
        
        // Show visualizer menu if in art-only mode with visualization
        if isArtOnlyMode && isVisualizingArt && hitTestContentArea(at: winampPoint) {
            showVisualizerMenu(at: event)
            return
        }
        
        // Show art context menu if in art-only mode without visualization
        if isArtOnlyMode && !isVisualizingArt && hitTestContentArea(at: winampPoint) {
            showArtContextMenu(at: event)
            return
        }
        
        // Check list area for item context menu
        if !isArtOnlyMode, let clickedIndex = hitTestListArea(at: winampPoint) {
            // Select the clicked item if not already selected
            if !selectedIndices.contains(clickedIndex) {
                selectedIndices = [clickedIndex]
                needsDisplay = true
            }
            
            let item = displayItems[clickedIndex]
            
            // Show context menu - uses search URLs as fallback for external links
            // Direct IMDB/TMDB links will be used if IDs are already available
            showContextMenu(for: item, at: event)
            return
        }
        
        // Default right-click behavior
        super.rightMouseDown(with: event)
    }
    
    /// Show the visualizer effect selection menu
    private func showVisualizerMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Visualizer")
        
        // Current effect + navigation at top
        let currentItem = NSMenuItem(title: "▶ \(currentVisEffect.rawValue)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        
        let nextItem = NSMenuItem(title: "Next Effect →", action: #selector(menuNextEffect), keyEquivalent: "")
        nextItem.target = self
        menu.addItem(nextItem)
        
        let prevItem = NSMenuItem(title: "← Previous Effect", action: #selector(menuPrevEffect), keyEquivalent: "")
        prevItem.target = self
        menu.addItem(prevItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Mode selection (flat, not submenu)
        let randomItem = NSMenuItem(title: "Random Mode", action: #selector(toggleRandomMode), keyEquivalent: "")
        randomItem.target = self
        randomItem.state = visMode == .random ? .on : .off
        menu.addItem(randomItem)
        
        let cycleItem = NSMenuItem(title: "Auto-Cycle Mode", action: #selector(toggleCycleMode), keyEquivalent: "")
        cycleItem.target = self
        cycleItem.state = visMode == .cycle ? .on : .off
        menu.addItem(cycleItem)
        
        // Cycle interval submenu
        let intervalMenu = NSMenu()
        for (name, seconds) in [("5 seconds", 5.0), ("10 seconds", 10.0), ("20 seconds", 20.0), ("30 seconds", 30.0)] {
            let item = NSMenuItem(title: name, action: #selector(selectCycleSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(seconds)
            item.state = abs(cycleInterval - seconds) < 0.5 ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalMenuItem = NSMenuItem(title: "Cycle Interval", action: nil, keyEquivalent: "")
        intervalMenuItem.submenu = intervalMenu
        menu.addItem(intervalMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Effects submenu (organized by category)
        let effectsItem = NSMenuItem(title: "All Effects", action: nil, keyEquivalent: "")
        let effectsMenu = NSMenu()
        
        for effect in VisEffect.allCases {
            addEffectItem(effect, to: effectsMenu)
        }
        
        effectsItem.submenu = effectsMenu
        menu.addItem(effectsItem)
        
        // Intensity submenu
        let intensityItem = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
        let intensityMenu = NSMenu()
        
        let intensityLevels: [(String, CGFloat)] = [
            ("Low", 0.5),
            ("Medium", 0.75),
            ("Normal", 1.0),
            ("High", 1.5),
            ("Extreme", 2.0)
        ]
        
        for (name, value) in intensityLevels {
            let item = NSMenuItem(title: name, action: #selector(selectVisIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(value * 100)
            item.state = abs(visEffectIntensity - value) < 0.1 ? .on : .off
            intensityMenu.addItem(item)
        }
        intensityItem.submenu = intensityMenu
        menu.addItem(intensityItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quick hint
        let hintItem = NSMenuItem(title: "Click: next • R: random • C: cycle • F: fullscreen", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Fullscreen
        let isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
        let fullscreenItem = NSMenuItem(title: isFullscreen ? "Exit Fullscreen" : "Fullscreen", action: #selector(toggleVisFullscreen), keyEquivalent: "")
        fullscreenItem.target = self
        menu.addItem(fullscreenItem)
        
        // Turn off visualization
        let offItem = NSMenuItem(title: "Turn Off", action: #selector(turnOffVisualization), keyEquivalent: "")
        offItem.target = self
        menu.addItem(offItem)
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    /// Show context menu for art-only mode (when visualization is off)
    private func showArtContextMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Art")
        
        // Enable visualization
        let visItem = NSMenuItem(title: "Enable Visualization", action: #selector(enableArtVisualization), keyEquivalent: "")
        visItem.target = self
        menu.addItem(visItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Exit art view
        let exitItem = NSMenuItem(title: "Exit Art View", action: #selector(exitArtView), keyEquivalent: "")
        exitItem.target = self
        menu.addItem(exitItem)
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    @objc private func enableArtVisualization() {
        isVisualizingArt = true
    }
    
    @objc private func exitArtView() {
        isArtOnlyMode = false
    }
    
    @objc private func menuNextEffect() {
        nextVisEffect()
    }
    
    @objc private func menuPrevEffect() {
        prevVisEffect()
    }
    
    @objc private func toggleRandomMode() {
        visMode = visMode == .random ? .single : .random
    }
    
    @objc private func toggleCycleMode() {
        if visMode == .cycle {
            visMode = .single
            cycleTimer?.invalidate()
        } else {
            visMode = .cycle
            startCycleTimer()
        }
    }
    
    @objc private func toggleVisFullscreen() {
        window?.toggleFullScreen(nil)
    }
    
    private func addEffectItem(_ effect: VisEffect, to menu: NSMenu) {
        let item = NSMenuItem(title: effect.rawValue, action: #selector(selectVisEffect(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = effect
        item.state = currentVisEffect == effect ? .on : .off
        menu.addItem(item)
    }
    
    @objc private func selectVisEffect(_ sender: NSMenuItem) {
        if let effect = sender.representedObject as? VisEffect {
            currentVisEffect = effect
            visMode = .single  // Switch to single mode when selecting an effect
            UserDefaults.standard.set(effect.rawValue, forKey: "browserVisEffect")
        }
    }
    
    @objc private func selectVisMode(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: visMode = .single
        case 1: visMode = .random
        case 2:
            visMode = .cycle
            startCycleTimer()
        default: break
        }
    }
    
    @objc private func selectCycleSpeed(_ sender: NSMenuItem) {
        cycleInterval = TimeInterval(sender.tag)
        if visMode == .cycle {
            startCycleTimer()
        }
    }
    
    @objc private func selectVisIntensity(_ sender: NSMenuItem) {
        visEffectIntensity = CGFloat(sender.tag) / 100.0
        UserDefaults.standard.set(visEffectIntensity, forKey: "browserVisIntensity")
    }
    
    @objc private func turnOffVisualization() {
        isVisualizingArt = false
    }
    
    /// Cycle to next effect
    private func nextVisEffect() {
        visMode = .single
        let effects = VisEffect.allCases
        if let currentIndex = effects.firstIndex(of: currentVisEffect) {
            let nextIndex = (currentIndex + 1) % effects.count
            currentVisEffect = effects[nextIndex]
        }
    }
    
    /// Cycle to previous effect
    private func prevVisEffect() {
        visMode = .single
        let effects = VisEffect.allCases
        if let currentIndex = effects.firstIndex(of: currentVisEffect) {
            let prevIndex = (currentIndex - 1 + effects.count) % effects.count
            currentVisEffect = effects[prevIndex]
        }
    }
    
    /// Check if point is in content area
    private func hitTestContentArea(at point: NSPoint) -> Bool {
        let contentY = Layout.titleBarHeight + Layout.serverBarHeight
        let contentHeight = originalWindowSize.height - contentY - Layout.statusBarHeight
        let contentRect = NSRect(x: Layout.leftBorder, y: contentY,
                                 width: originalWindowSize.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth,
                                 height: contentHeight)
        return contentRect.contains(point)
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = convertToWinampCoordinates(point)
        
        // In visualization mode, click anywhere in content to cycle effects
        if isArtOnlyMode && isVisualizingArt && hitTestContentArea(at: winampPoint) {
            nextVisEffect()
            return
        }
        
        // In art-only mode without visualization, cycle through artwork images
        if isArtOnlyMode && !isVisualizingArt && hitTestContentArea(at: winampPoint) {
            cycleToNextArtwork()
            return
        }
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 && hitTestTitleBar(at: winampPoint) {
            toggleShadeMode()
            return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: winampPoint, event: event)
            return
        }
        
        // Check scrollbar FIRST (priority over column operations)
        if hitTestScrollbar(at: winampPoint) {
            isDraggingScrollbar = true
            scrollbarDragStartY = winampPoint.y
            scrollbarDragStartOffset = scrollOffset
            return
        }
        
        // Check for column resize
        if let columnId = hitTestColumnResize(at: winampPoint) {
            resizingColumnId = columnId
            resizeStartX = winampPoint.x
            resizeStartWidth = columnWidths[columnId] ?? BrowserColumn.findColumn(id: columnId)?.minWidth ?? 50
            NSCursor.resizeLeftRight.push()
            return
        }
        
        // Check for column header click (for sorting)
        if let columnId = hitTestColumnHeader(at: winampPoint) {
            if columnSortId == columnId {
                // Same column - toggle direction
                columnSortAscending.toggle()
            } else {
                // New column - sort ascending
                columnSortId = columnId
                columnSortAscending = true
            }
            return
        }
        
        // Check window control buttons
        if hitTestCloseButton(at: winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if hitTestShadeButton(at: winampPoint) {
            pressedButton = .shade
            needsDisplay = true
            return
        }
        
        // Check server bar
        if hitTestServerBar(at: winampPoint) {
            // For local files, radio, or subsonic - always handle the click
            // For Plex - check if linked first
            if case .plex = currentSource, !PlexManager.shared.isLinked {
                controller?.showLinkSheet()
            } else {
                handleServerBarClick(at: winampPoint, event: event)
            }
            return
        }
        
        // Check sort indicator (in tab bar area, on the right)
        if hitTestSortIndicator(at: winampPoint) {
            showSortMenu(at: event.locationInWindow)
            return
        }
        
        // Check tab bar
        if let tabIndex = hitTestTabBar(at: winampPoint) {
            if let newMode = PlexBrowseMode(rawValue: tabIndex) {
                browseMode = newMode
                selectedIndices.removeAll()
                scrollOffset = 0
                loadDataForCurrentMode()
                window?.makeFirstResponder(self)
            }
            return
        }
        
        // Check search bar
        if hitTestSearchBar(at: winampPoint) {
            window?.makeFirstResponder(self)
            return
        }
        
        // Check alphabet index
        if hitTestAlphabetIndex(at: winampPoint) {
            handleAlphabetClick(at: winampPoint)
            return
        }
        
        // Check list area
        if let itemIndex = hitTestListArea(at: winampPoint) {
            handleListClick(at: itemIndex, event: event, winampPoint: winampPoint)
            return
        }
        
        // Title bar - start window drag (can undock)
        if hitTestTitleBar(at: winampPoint) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
        }
    }
    
    private func handleShadeMouseDown(at winampPoint: NSPoint, event: NSEvent) {
        let originalSize = originalWindowSize
        
        // Check window control buttons (relative to right edge)
        let closeRect = NSRect(x: originalSize.width + SkinElements.PlaylistShade.Positions.closeButton.minX,
                               y: SkinElements.PlaylistShade.Positions.closeButton.minY,
                               width: 9, height: 9)
        let shadeRect = NSRect(x: originalSize.width + SkinElements.PlaylistShade.Positions.shadeButton.minX,
                               y: SkinElements.PlaylistShade.Positions.shadeButton.minY,
                               width: 9, height: 9)
        
        if closeRect.contains(winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if shadeRect.contains(winampPoint) {
            pressedButton = .shade
            needsDisplay = true
            return
        }
        
        // Start window drag (shade mode is all title bar, so can undock)
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
        }
    }
    
    private func handleServerBarClick(at winampPoint: NSPoint, event: NSEvent) {
        let originalSize = originalWindowSize
        let barWidth = originalSize.width - Layout.leftBorder - Layout.rightBorder
        
        // Layout (right-aligned):
        // Normal: [Source: Local Files] [+ADD] ... [N items] [ART] [F5]
        // Art mode: [Source: Local Files] [+ADD] ... [N items] [VIS] [ART] [F5]
        // Plex:  [Source: ServerName] [LibraryName] ... [N items] [ART] [F5]
        
        let charWidth = SkinElements.TextFont.charWidth * 1.5  // scaled
        let relativeX = winampPoint.x - Layout.leftBorder
        
        // Use same spacing as drawing code - tighter in art-only mode
        let artModeSpacing: CGFloat = isArtOnlyMode ? 12 : 24
        let artModeVisSpacing: CGFloat = isArtOnlyMode ? 8 : 16
        
        // Right side zones (from right edge)
        let refreshZoneStart = barWidth - 30  // F5 + padding
        let artZoneEnd = refreshZoneStart - artModeSpacing
        let artZoneStart = artZoneEnd - (3 * charWidth)  // "ART" (3 chars)
        
        // VIS zone (only in art-only mode, before ART button)
        let visZoneEnd = artZoneStart - artModeVisSpacing
        let visZoneStart = visZoneEnd - (3 * charWidth)  // "VIS" (3 chars)
        
        // Calculate source zone width: "Source: " (8 chars)
        let sourcePrefix: CGFloat = 8 * charWidth + 4
        
        // Max widths for server and library names
        let maxServerWidth: CGFloat = 12 * charWidth
        let maxLibraryWidth: CGFloat = 10 * charWidth
        
        if relativeX >= refreshZoneStart {
            // Refresh icon click
            handleRefreshClick()
        } else if currentArtwork != nil && relativeX >= artZoneStart && relativeX <= artZoneEnd {
            // ART toggle click (only if artwork available)
            isArtOnlyMode.toggle()
        } else if isArtOnlyMode && currentArtwork != nil && relativeX >= visZoneStart && relativeX <= visZoneEnd {
            // VIS button click (only in art-only mode with artwork)
            toggleVisualization()
        } else if case .local = currentSource {
            // Local mode - Source and +ADD on left
            let localNameWidth: CGFloat = 11 * charWidth  // "Local Files"
            let sourceZoneEnd = sourcePrefix + localNameWidth
            let addZoneStart = sourceZoneEnd + 24
            let addZoneEnd = addZoneStart + 4 * charWidth + 8  // "+ADD" (4 chars)
            
            if relativeX >= addZoneStart && relativeX <= addZoneEnd {
                // +ADD button click
                showAddFilesMenu(at: event)
            } else if relativeX < sourceZoneEnd {
                // Source area = source dropdown
                showSourceMenu(at: event)
            }
        } else if case .plex = currentSource {
            // Plex mode - Server and Library on left with max widths
            let serverZoneEnd = sourcePrefix + maxServerWidth
            let libLabelWidth: CGFloat = 4 * charWidth + 4  // "Lib:" + spacing
            let libraryZoneStart = serverZoneEnd + 12  // includes "Lib:" label
            let libraryZoneEnd = libraryZoneStart + libLabelWidth + maxLibraryWidth
            
            // Check for RATE button click (in art-only mode with Plex track playing)
            if !rateButtonRect.isEmpty {
                let rateRelativeStart = rateButtonRect.minX - Layout.leftBorder
                let rateRelativeEnd = rateButtonRect.maxX - Layout.leftBorder
                if relativeX >= rateRelativeStart && relativeX <= rateRelativeEnd {
                    // RATE button click - show rating overlay
                    showRatingOverlay()
                    return
                }
            }
            
            if relativeX >= libraryZoneStart && relativeX <= libraryZoneEnd {
                // Library dropdown click (includes label)
                showLibraryMenu(at: event)
            } else if relativeX < serverZoneEnd {
                // Source/server area = source dropdown
                showSourceMenu(at: event)
            }
        } else if case .subsonic = currentSource {
            // Subsonic mode - Server name on left (no library selector)
            let maxSubsonicServerChars = 20
            let maxSubsonicServerWidth = CGFloat(maxSubsonicServerChars) * charWidth
            let serverZoneEnd = sourcePrefix + maxSubsonicServerWidth
            
            if relativeX < serverZoneEnd {
                // Source/server area = source dropdown
                showSourceMenu(at: event)
            }
        } else if case .radio = currentSource {
            // Radio mode - Source and +ADD on left
            let radioNameWidth: CGFloat = 14 * charWidth  // "Internet Radio"
            let sourceZoneEnd = sourcePrefix + radioNameWidth
            let addZoneStart = sourceZoneEnd + 24
            let addZoneEnd = addZoneStart + 4 * charWidth + 8  // "+ADD" (4 chars)
            
            if relativeX >= addZoneStart && relativeX <= addZoneEnd {
                // +ADD button click - show add menu
                showRadioAddMenu(at: event)
            } else if relativeX < sourceZoneEnd {
                // Source area = source dropdown
                showSourceMenu(at: event)
            }
        }
    }
    
    /// Handle refresh button click based on current source
    private func handleRefreshClick() {
        // Radio source (Internet Radio) - only radio tab has content to refresh
        if case .radio = currentSource {
            if browseMode == .radio {
                loadRadioStations()
            }
            // Non-radio tabs on radio source - nothing to refresh
            return
        }
        
        // Radio tab on Plex source - refresh Plex Radio stations
        if browseMode == .radio {
            if case .plex = currentSource {
                loadPlexRadioStations()
            }
            return
        }
        
        switch currentSource {
        case .local:
            // Rescan watch folders
            MediaLibrary.shared.rescanWatchFolders()
            // Also reload local data
            loadLocalData()
        case .plex:
            // Refresh Plex data
            refreshData()
        case .subsonic:
            // Refresh Subsonic data
            Task {
                await SubsonicManager.shared.preloadLibraryContent()
                await MainActor.run {
                    self.refreshData()
                }
            }
        case .radio:
            // Already handled above
            break
        }
    }
    
    /// Show the source selection dropdown menu
    private func showSourceMenu(at event: NSEvent) {
        let menu = NSMenu()
        
        // Local Files option
        let localItem = NSMenuItem(title: "Local Files", action: #selector(selectLocalSource), keyEquivalent: "")
        localItem.target = self
        if case .local = currentSource {
            localItem.state = .on
        }
        menu.addItem(localItem)
        
        // Internet Radio option
        let radioItem = NSMenuItem(title: "Internet Radio", action: #selector(selectRadioSource), keyEquivalent: "")
        radioItem.target = self
        if case .radio = currentSource {
            radioItem.state = .on
        }
        menu.addItem(radioItem)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Plex servers
        let plexServers = PlexManager.shared.servers
        if plexServers.isEmpty && !PlexManager.shared.isLinked {
            let linkItem = NSMenuItem(title: "Link Plex Account...", action: #selector(linkPlexAccount), keyEquivalent: "")
            linkItem.target = self
            menu.addItem(linkItem)
        } else {
            for server in plexServers {
                let serverItem = NSMenuItem(title: server.name, action: #selector(selectPlexServer(_:)), keyEquivalent: "")
                serverItem.target = self
                serverItem.representedObject = server.id
                if case .plex(let currentServerId) = currentSource, currentServerId == server.id {
                    serverItem.state = .on
                }
                menu.addItem(serverItem)
            }
        }
        
        // Subsonic/Navidrome servers
        let subsonicServers = SubsonicManager.shared.servers
        if !subsonicServers.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for server in subsonicServers {
                let serverItem = NSMenuItem(title: "🎵 \(server.name)", action: #selector(selectSubsonicServer(_:)), keyEquivalent: "")
                serverItem.target = self
                serverItem.representedObject = server.id
                if case .subsonic(let currentServerId) = currentSource, currentServerId == server.id {
                    serverItem.state = .on
                }
                menu.addItem(serverItem)
            }
        } else {
            menu.addItem(NSMenuItem.separator())
            let addItem = NSMenuItem(title: "Add Navidrome/Subsonic...", action: #selector(addSubsonicServer), keyEquivalent: "")
            addItem.target = self
            menu.addItem(addItem)
        }
        
        // Show menu
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    /// Show the add files/folder menu
    private func showAddFilesMenu(at event: NSEvent) {
        let menu = NSMenu()
        
        let addFilesItem = NSMenuItem(title: "Add Files...", action: #selector(addFiles), keyEquivalent: "")
        addFilesItem.target = self
        menu.addItem(addFilesItem)
        
        let addFolderItem = NSMenuItem(title: "Add Folder...", action: #selector(addWatchFolder), keyEquivalent: "")
        addFolderItem.target = self
        menu.addItem(addFolderItem)
        
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    /// Show the +ADD menu for radio mode
    private func showRadioAddMenu(at event: NSEvent) {
        let menu = NSMenu()
        
        let addStationItem = NSMenuItem(title: "Add Station...", action: #selector(showAddRadioStationDialog), keyEquivalent: "")
        addStationItem.target = self
        menu.addItem(addStationItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let addPlaylistItem = NSMenuItem(title: "Import Playlist URL...", action: #selector(showAddRadioPlaylistDialog), keyEquivalent: "")
        addPlaylistItem.target = self
        menu.addItem(addPlaylistItem)
        
        let importFileItem = NSMenuItem(title: "Import Playlist File...", action: #selector(importRadioPlaylistFile), keyEquivalent: "")
        importFileItem.target = self
        menu.addItem(importFileItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let addDefaultsItem = NSMenuItem(title: "Add Missing Defaults", action: #selector(addMissingRadioDefaults), keyEquivalent: "")
        addDefaultsItem.target = self
        menu.addItem(addDefaultsItem)
        
        let resetDefaultsItem = NSMenuItem(title: "Reset to Defaults", action: #selector(resetRadioToDefaults), keyEquivalent: "")
        resetDefaultsItem.target = self
        menu.addItem(resetDefaultsItem)
        
        let menuLocation = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    @objc private func showAddRadioPlaylistDialog() {
        // Show a simple dialog to enter a playlist URL (.m3u, .pls)
        let alert = NSAlert()
        alert.messageText = "Import Playlist URL"
        alert.informativeText = "Enter the URL of a .m3u or .pls playlist file containing radio streams:"
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "https://example.com/playlist.m3u"
        alert.accessoryView = textField
        
        if alert.runModal() == .alertFirstButtonReturn {
            let urlString = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlString.isEmpty, let url = URL(string: urlString) else {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Invalid URL"
                errorAlert.informativeText = "Please enter a valid URL."
                errorAlert.runModal()
                return
            }
            
            // Fetch and parse the playlist
            fetchAndParsePlaylist(from: url)
        }
    }
    
    @objc private func importRadioPlaylistFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .init(filenameExtension: "m3u")!,
            .init(filenameExtension: "m3u8")!,
            .init(filenameExtension: "pls")!
        ]
        panel.message = "Select playlist files containing radio streams"
        
        if panel.runModal() == .OK {
            var totalStations = 0
            
            for url in panel.urls {
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let stations = parsePlaylistContent(content, sourceURL: url)
                    
                    for station in stations {
                        RadioManager.shared.addStation(station)
                    }
                    totalStations += stations.count
                } catch {
                    NSLog("Failed to read playlist file %@: %@", url.path, error.localizedDescription)
                }
            }
            
            if totalStations > 0 {
                loadRadioStations()
                
                let successAlert = NSAlert()
                successAlert.messageText = "Playlist Imported"
                successAlert.informativeText = "Added \(totalStations) station\(totalStations == 1 ? "" : "s") from the playlist\(panel.urls.count == 1 ? "" : "s")."
                successAlert.runModal()
            } else {
                showPlaylistError("No valid radio streams found in the selected file(s)")
            }
        }
    }
    
    private func fetchAndParsePlaylist(from url: URL) {
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let content = String(data: data, encoding: .utf8) else {
                    showPlaylistError("Could not read playlist content")
                    return
                }
                
                let stations = parsePlaylistContent(content, sourceURL: url)
                if stations.isEmpty {
                    showPlaylistError("No valid streams found in playlist")
                    return
                }
                
                // Add all stations
                for station in stations {
                    RadioManager.shared.addStation(station)
                }
                
                // Reload and show success
                loadRadioStations()
                
                let successAlert = NSAlert()
                successAlert.messageText = "Playlist Added"
                successAlert.informativeText = "Added \(stations.count) station\(stations.count == 1 ? "" : "s") from the playlist."
                successAlert.runModal()
            } catch {
                showPlaylistError("Failed to fetch playlist: \(error.localizedDescription)")
            }
        }
    }
    
    private func parsePlaylistContent(_ content: String, sourceURL: URL) -> [RadioStation] {
        var stations: [RadioStation] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Detect format
        let isM3U = content.hasPrefix("#EXTM3U") || sourceURL.pathExtension.lowercased() == "m3u" || sourceURL.pathExtension.lowercased() == "m3u8"
        let isPLS = content.lowercased().contains("[playlist]") || sourceURL.pathExtension.lowercased() == "pls"
        
        if isM3U {
            // Parse M3U format
            var currentTitle: String?
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#EXTINF:") {
                    // Extract title from #EXTINF:-1,Station Name
                    if let commaIndex = trimmed.firstIndex(of: ",") {
                        currentTitle = String(trimmed[trimmed.index(after: commaIndex)...])
                    }
                } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    if let streamURL = URL(string: trimmed) {
                        let name = currentTitle ?? streamURL.lastPathComponent
                        stations.append(RadioStation(name: name, url: streamURL))
                    }
                    currentTitle = nil
                }
            }
        } else if isPLS {
            // Parse PLS format
            var files: [Int: String] = [:]
            var titles: [Int: String] = [:]
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("file") {
                    // File1=http://...
                    if let equalIndex = trimmed.firstIndex(of: "=") {
                        let numPart = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<equalIndex]
                        if let num = Int(numPart) {
                            files[num] = String(trimmed[trimmed.index(after: equalIndex)...])
                        }
                    }
                } else if trimmed.lowercased().hasPrefix("title") {
                    // Title1=Station Name
                    if let equalIndex = trimmed.firstIndex(of: "=") {
                        let numPart = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<equalIndex]
                        if let num = Int(numPart) {
                            titles[num] = String(trimmed[trimmed.index(after: equalIndex)...])
                        }
                    }
                }
            }
            
            for (num, urlString) in files {
                if let url = URL(string: urlString) {
                    let name = titles[num] ?? url.lastPathComponent
                    stations.append(RadioStation(name: name, url: url))
                }
            }
        } else {
            // Try to extract any http URLs
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    if let url = URL(string: trimmed) {
                        stations.append(RadioStation(name: url.lastPathComponent, url: url))
                    }
                }
            }
        }
        
        return stations
    }
    
    private func showPlaylistError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Playlist Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
    
    @objc private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        panel.message = "Select audio files to add to your library"
        
        if panel.runModal() == .OK {
            MediaLibrary.shared.addTracks(urls: panel.urls)
            
            // Switch to local source if not already
            if case .plex = currentSource {
                currentSource = .local
            }
        }
    }
    
    @objc private func selectLocalSource() {
        currentSource = .local
    }
    
    @objc private func selectRadioSource() {
        currentSource = .radio
    }
    
    @objc private func showAddRadioStationDialog() {
        activeRadioStationSheet = AddRadioStationSheet(station: nil)
        activeRadioStationSheet?.showDialog { [weak self] station in
            self?.activeRadioStationSheet = nil  // Release reference when done
            if let newStation = station {
                RadioManager.shared.addStation(newStation)
                // Switch to radio source if not already
                if case .radio = self?.currentSource {
                    self?.loadRadioStations()
                } else {
                    self?.currentSource = .radio
                }
            }
        }
    }
    
    @objc private func addMissingRadioDefaults() {
        RadioManager.shared.addMissingDefaults()
        if case .radio = currentSource {
            loadRadioStations()
        }
    }
    
    @objc private func resetRadioToDefaults() {
        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Reset to Defaults"
        alert.informativeText = "This will remove all your saved radio stations and replace them with the default stations. Are you sure?"
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            RadioManager.shared.resetToDefaults()
            if case .radio = currentSource {
                loadRadioStations()
            }
        }
    }
    
    @objc private func selectPlexServer(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        currentSource = .plex(serverId: serverId)
        
        // Connect to the selected server
        if let server = PlexManager.shared.servers.first(where: { $0.id == serverId }) {
            Task { @MainActor in
                do {
                    try await PlexManager.shared.connect(to: server)
                    reloadData()
                } catch {
                    errorMessage = error.localizedDescription
                    needsDisplay = true
                }
            }
        }
    }
    
    @objc private func linkPlexAccount() {
        controller?.showLinkSheet()
    }
    
    @objc private func selectSubsonicServer(_ sender: NSMenuItem) {
        guard let serverId = sender.representedObject as? String else { return }
        currentSource = .subsonic(serverId: serverId)
        
        // Connect to the selected server
        if let server = SubsonicManager.shared.servers.first(where: { $0.id == serverId }) {
            Task { @MainActor in
                do {
                    try await SubsonicManager.shared.connect(to: server)
                    reloadData()
                } catch {
                    errorMessage = error.localizedDescription
                    needsDisplay = true
                }
            }
        }
    }
    
    @objc private func addSubsonicServer() {
        WindowManager.shared.showSubsonicLinkSheet()
    }
    
    @objc private func addWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to add to your library"
        
        if panel.runModal() == .OK, let url = panel.url {
            MediaLibrary.shared.addWatchFolder(url)
            MediaLibrary.shared.scanFolder(url)
            
            // Switch to local source if not already
            if case .plex = currentSource {
                currentSource = .local
            }
        }
    }
    
    // MARK: - Sort Menu
    
    private func showSortMenu(at windowPoint: NSPoint) {
        let menu = NSMenu()
        
        for option in BrowserSortOption.allCases {
            let item = NSMenuItem(title: option.rawValue, action: #selector(selectSortOption(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            if option == currentSort {
                item.state = .on
            }
            menu.addItem(item)
        }
        
        let menuLocation = NSPoint(x: windowPoint.x, y: windowPoint.y - 5)
        menu.popUp(positioning: nil, at: menuLocation, in: window?.contentView)
    }
    
    @objc private func selectSortOption(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? BrowserSortOption else { return }
        currentSort = option
    }
    
    private func handleAlphabetClick(at winampPoint: NSPoint) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
        
        let relativeY = winampPoint.y - listY
        let letterCount = CGFloat(alphabetLetters.count)
        let letterHeight = listHeight / letterCount
        let letterIndex = Int(relativeY / letterHeight)
        
        guard letterIndex >= 0 && letterIndex < alphabetLetters.count else { return }
        
        let targetLetter = alphabetLetters[letterIndex]
        scrollToLetter(targetLetter)
    }
    
    /// Get the sort letter for a title, stripping common prefixes like "The ", "A ", "An "
    /// This matches how Plex sorts items (e.g., "The Beatles" sorts under "B")
    private func sortLetter(for title: String) -> String {
        let uppercased = title.uppercased()
        var sortTitle = uppercased
        
        // Strip common prefixes (in order of length to handle "The" before "A")
        let prefixes = ["THE ", "AN ", "A "]
        for prefix in prefixes {
            if sortTitle.hasPrefix(prefix) {
                sortTitle = String(sortTitle.dropFirst(prefix.count))
                break
            }
        }
        
        // Get first character
        guard let firstChar = sortTitle.first else { return "#" }
        
        if firstChar.isLetter {
            return String(firstChar)
        } else {
            return "#"
        }
    }
    
    private func scrollToLetter(_ letter: String) {
        for (index, item) in displayItems.enumerated() {
            let itemLetter = sortLetter(for: item.title)
            
            if itemLetter == letter {
                var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
                if browseMode == .search {
                    listY += Layout.searchBarHeight
                }
                let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
                let maxScroll = max(0, CGFloat(displayItems.count) * itemHeight - listHeight)
                
                scrollOffset = min(maxScroll, CGFloat(index) * itemHeight)
                selectedIndices = [index]
                needsDisplay = true
                return
            }
        }
    }
    
    private func handleListClick(at index: Int, event: NSEvent, winampPoint: NSPoint) {
        let item = displayItems[index]
        
        // Handle expand/collapse
        if item.hasChildren {
            let indent = CGFloat(item.indentLevel) * 16
            if winampPoint.x < Layout.leftBorder + indent + 20 {
                toggleExpand(item)
                return
            }
        }
        
        // Handle selection
        if event.modifierFlags.contains(.shift) {
            if let lastSelected = selectedIndices.max() {
                let start = min(lastSelected, index)
                let end = max(lastSelected, index)
                for i in start...end {
                    selectedIndices.insert(i)
                }
            } else {
                selectedIndices.insert(index)
            }
            // Load artwork for selection (shift-click multi-select)
            loadArtworkForSelection()
        } else if event.modifierFlags.contains(.command) {
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
            // Load artwork for selection (cmd-click multi-select)
            loadArtworkForSelection()
        } else {
            selectedIndices = [index]
            
            // Single-click on playable audio items plays them immediately
            // Video items (movies, episodes) require double-click to play
            switch item.type {
            case .track:
                playTrack(item)
            case .localTrack(let track):
                playLocalTrack(track)
            case .plexRadioStation, .radioStation:
                // Radio stations don't load artwork on single-click - only on play (double-click)
                break
            default:
                // For non-playable items and video items, just load artwork
                loadArtworkForSelection()
            }
        }
        
        // Double-click to play album/show or expand artist
        if event.clickCount == 2 {
            handleDoubleClick(on: item)
        }
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Handle column resize dragging
        if let columnId = resizingColumnId {
            let point = convert(event.locationInWindow, from: nil)
            let winampPoint = convertToWinampCoordinates(point)
            let deltaX = winampPoint.x - resizeStartX
            let minWidth = BrowserColumn.findColumn(id: columnId)?.minWidth ?? 30
            let newWidth = max(minWidth, resizeStartWidth + deltaX)
            columnWidths[columnId] = newWidth
            needsDisplay = true
            return
        }
        
        // Handle scrollbar dragging
        if isDraggingScrollbar {
            let point = convert(event.locationInWindow, from: nil)
            let winampPoint = convertToWinampCoordinates(point)
            
            let deltaY = winampPoint.y - scrollbarDragStartY
            var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
            if browseMode == .search {
                listY += Layout.searchBarHeight
            }
            let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
            let totalContentHeight = CGFloat(displayItems.count) * itemHeight
            
            if totalContentHeight > listHeight {
                let scrollRange = totalContentHeight - listHeight
                let trackRange = listHeight - 18  // Thumb height
                let scrollDelta = (deltaY / trackRange) * scrollRange
                scrollOffset = max(0, min(scrollRange, scrollbarDragStartOffset + scrollDelta))
                
                // Only redraw the list area and scrollbar, not the entire view
                let scale = bounds.width / originalWindowSize.width
                let scaledListY = bounds.height - (listY + listHeight) * scale
                let scaledListHeight = (listHeight + Layout.statusBarHeight) * scale
                let listRect = NSRect(x: 0, y: scaledListY,
                                     width: bounds.width, height: scaledListHeight)
                setNeedsDisplay(listRect)
            }
            return
        }
        
        // Handle window dragging - snaps to other windows but doesn't dock
        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y
            
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY
            
            // Apply snapping to other windows
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = convertToWinampCoordinates(point)
        
        // End column resizing
        if resizingColumnId != nil {
            resizingColumnId = nil
            NSCursor.pop()
        }
        
        // End window dragging
        if isDraggingWindow {
            isDraggingWindow = false
        }
        
        // End scrollbar dragging
        isDraggingScrollbar = false
        
        if isShadeMode {
            handleShadeMouseUp(at: winampPoint)
            return
        }
        
        // Handle button releases
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestCloseButton(at: winampPoint) {
                    window?.close()
                }
            case .shade:
                if hitTestShadeButton(at: winampPoint) {
                    toggleShadeMode()
                }
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    private func handleShadeMouseUp(at winampPoint: NSPoint) {
        let originalSize = originalWindowSize
        if let pressed = pressedButton {
            let closeRect = NSRect(x: originalSize.width + SkinElements.PlaylistShade.Positions.closeButton.minX,
                                   y: SkinElements.PlaylistShade.Positions.closeButton.minY,
                                   width: 9, height: 9)
            let shadeRect = NSRect(x: originalSize.width + SkinElements.PlaylistShade.Positions.shadeButton.minX,
                                   y: SkinElements.PlaylistShade.Positions.shadeButton.minY,
                                   width: 9, height: 9)
            
            switch pressed {
            case .close:
                if closeRect.contains(winampPoint) {
                    window?.close()
                }
            case .shade:
                if shadeRect.contains(winampPoint) {
                    toggleShadeMode()
                }
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
        let totalHeight = CGFloat(displayItems.count) * itemHeight
        
        // Determine which columns are active for horizontal scroll calculation
        let columns: [BrowserColumn]?
        if displayItems.contains(where: { 
            switch $0.type { case .track, .subsonicTrack, .localTrack: return true; default: return false }
        }) {
            columns = BrowserColumn.trackColumns
        } else if displayItems.contains(where: {
            switch $0.type { case .album, .subsonicAlbum, .localAlbum: return true; default: return false }
        }) {
            columns = BrowserColumn.albumColumns
        } else if displayItems.contains(where: {
            switch $0.type { case .artist, .subsonicArtist, .localArtist: return true; default: return false }
        }) {
            columns = BrowserColumn.artistColumns
        } else {
            columns = nil
        }
        
        var needsRedraw = false
        
        // Handle horizontal scrolling (shift+scroll or trackpad horizontal gesture)
        if let cols = columns, (event.modifierFlags.contains(.shift) || abs(event.deltaX) > abs(event.deltaY)) {
            let alphabetWidth = Layout.alphabetWidth
            let availableWidth = originalWindowSize.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth - alphabetWidth
            let columnsWidth = totalColumnsWidth(columns: cols)
            let maxHorizontalScroll = max(0, columnsWidth - availableWidth)
            
            if maxHorizontalScroll > 0 {
                let delta = event.modifierFlags.contains(.shift) ? event.deltaY : event.deltaX
                horizontalScrollOffset = max(0, min(maxHorizontalScroll, horizontalScrollOffset - delta * 3))
                needsRedraw = true
            }
        }
        
        // Handle vertical scrolling
        if totalHeight > listHeight && abs(event.deltaY) > 0 && !event.modifierFlags.contains(.shift) {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))
            needsRedraw = true
        }
        
        if needsRedraw {
            // Only redraw the list area and scrollbar, not the entire view
            // This prevents tabs and server bar from shimmering during scroll
            let scale = bounds.width / originalWindowSize.width
            let scaledListY = bounds.height - (listY + listHeight) * scale
            let scaledListHeight = (listHeight + Layout.statusBarHeight) * scale
            let listRect = NSRect(x: 0, y: scaledListY,
                                 width: bounds.width, height: scaledListHeight)
            setNeedsDisplay(listRect)
        }
    }
    
    // MARK: - Drag and Drop (Local Files and Playlists)
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return []
        }
        
        // Check if we have valid files to drop
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
        let playlistExtensions = ["m3u", "m3u8", "pls"]
        
        for url in items {
            let ext = url.pathExtension.lowercased()
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            
            // Accept audio files, directories, or playlist files
            if isDirectory.boolValue || audioExtensions.contains(ext) || playlistExtensions.contains(ext) {
                return .copy
            }
        }
        
        return []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        
        var fileURLs: [URL] = []
        var playlistURLs: [URL] = []
        var processedDirectories = false
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
        let playlistExtensions = ["m3u", "m3u8", "pls"]
        
        for url in items {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                let ext = url.pathExtension.lowercased()
                
                if isDirectory.boolValue {
                    // Add folder as watch folder and scan
                    MediaLibrary.shared.addWatchFolder(url)
                    MediaLibrary.shared.scanFolder(url)
                    processedDirectories = true
                } else if playlistExtensions.contains(ext) {
                    // Playlist file
                    playlistURLs.append(url)
                } else if audioExtensions.contains(ext) {
                    // Audio file
                    fileURLs.append(url)
                }
            }
        }
        
        // Handle playlist files - import as radio stations
        if !playlistURLs.isEmpty {
            var totalStations = 0
            for url in playlistURLs {
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let stations = parsePlaylistContent(content, sourceURL: url)
                    
                    for station in stations {
                        RadioManager.shared.addStation(station)
                    }
                    totalStations += stations.count
                } catch {
                    NSLog("Failed to read playlist file %@: %@", url.path, error.localizedDescription)
                }
            }
            
            if totalStations > 0 {
                // Switch to radio source to show added stations
                if case .radio = currentSource {
                    loadRadioStations()
                } else {
                    currentSource = .radio
                }
                
                let alert = NSAlert()
                alert.messageText = "Playlist Imported"
                alert.informativeText = "Added \(totalStations) station\(totalStations == 1 ? "" : "s") from the playlist\(playlistURLs.count == 1 ? "" : "s")."
                alert.runModal()
            }
        }
        
        // Handle audio files
        if !fileURLs.isEmpty {
            MediaLibrary.shared.addTracks(urls: fileURLs)
            
            // Switch to local source to show added content
            if case .plex = currentSource {
                currentSource = .local
            }
        }
        
        return !fileURLs.isEmpty || !playlistURLs.isEmpty || processedDirectories
    }
    
    // MARK: - Right-Click Context Menu (for list items)
    
    // Note: rightMouseDown is now defined in the Mouse Events section above
    // This section just contains the showContextMenu helper
    
    // MARK: Detailed Metadata Fetching for Context Menu
    
    /// Fetch detailed movie metadata (with IMDB/TMDB IDs) for context menu
    private func fetchMovieDetailsForMenu(_ movie: PlexMovie) async -> PlexMovie {
        // If we already have the IMDB ID, no need to fetch
        if movie.imdbId != nil {
            return movie
        }
        
        do {
            if let detailed = try await PlexManager.shared.fetchMovieDetails(movieID: movie.id) {
                NSLog("Fetched movie details for %@: imdbId=%@, tmdbId=%@", movie.title, detailed.imdbId ?? "nil", detailed.tmdbId ?? "nil")
                return detailed
            }
        } catch {
            NSLog("Failed to fetch movie details: %@", error.localizedDescription)
        }
        return movie
    }
    
    /// Fetch detailed show metadata (with IMDB/TMDB/TVDB IDs) for context menu
    private func fetchShowDetailsForMenu(_ show: PlexShow) async -> PlexShow {
        // If we already have the IMDB ID, no need to fetch
        if show.imdbId != nil {
            return show
        }
        
        do {
            if let detailed = try await PlexManager.shared.fetchShowDetails(showID: show.id) {
                NSLog("Fetched show details for %@: imdbId=%@, tmdbId=%@", show.title, detailed.imdbId ?? "nil", detailed.tmdbId ?? "nil")
                return detailed
            }
        } catch {
            NSLog("Failed to fetch show details: %@", error.localizedDescription)
        }
        return show
    }
    
    /// Fetch detailed episode metadata (with IMDB ID) for context menu
    private func fetchEpisodeDetailsForMenu(_ episode: PlexEpisode) async -> PlexEpisode {
        // If we already have the IMDB ID, no need to fetch
        if episode.imdbId != nil {
            return episode
        }
        
        do {
            if let detailed = try await PlexManager.shared.fetchEpisodeDetails(episodeID: episode.id) {
                NSLog("Fetched episode details for %@: imdbId=%@", episode.title, detailed.imdbId ?? "nil")
                return detailed
            }
        } catch {
            NSLog("Failed to fetch episode details: %@", error.localizedDescription)
        }
        return episode
    }
    
    /// Show context menu with a specific item type (used when we've fetched detailed metadata)
    private func showContextMenu(for itemType: PlexDisplayItem.ItemType, item: PlexDisplayItem, at event: NSEvent) {
        // Create a new display item with the detailed type
        let detailedItem = PlexDisplayItem(
            id: item.id,
            title: item.title,
            info: item.info,
            indentLevel: item.indentLevel,
            hasChildren: item.hasChildren,
            type: itemType
        )
        showContextMenu(for: detailedItem, at: event)
    }
    
    private func showContextMenu(for item: PlexDisplayItem, at event: NSEvent) {
        let menu = NSMenu()
        
        NSLog("showContextMenu: item.type = %@, title = %@", String(describing: item.type), item.title)
        
        switch item.type {
        case .track(let track):
            NSLog("showContextMenu: Matched .track case, track.id = %@", track.id)
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlay(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = item
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = track
            menu.addItem(addItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let radioItem = NSMenuItem(title: "Start Track Radio", action: #selector(contextMenuStartTrackRadio(_:)), keyEquivalent: "")
            radioItem.target = self
            radioItem.representedObject = track
            menu.addItem(radioItem)
            
        case .album(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayAlbum(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = album
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add Album to Playlist", action: #selector(contextMenuAddAlbumToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = album
            menu.addItem(addItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let radioItem = NSMenuItem(title: "Start Album Radio", action: #selector(contextMenuStartAlbumRadio(_:)), keyEquivalent: "")
            radioItem.target = self
            radioItem.representedObject = album
            menu.addItem(radioItem)
            
        case .artist(let artist):
            let playItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlayArtist(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = artist
            menu.addItem(playItem)
            
            let expandItem = NSMenuItem(title: expandedArtists.contains(artist.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let radioItem = NSMenuItem(title: "Start Artist Radio", action: #selector(contextMenuStartArtistRadio(_:)), keyEquivalent: "")
            radioItem.target = self
            radioItem.representedObject = artist
            menu.addItem(radioItem)
            
        case .movie(let movie):
            let playItem = NSMenuItem(title: "Play Movie", action: #selector(contextMenuPlayMovie(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = movie
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddMovieToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = movie
            menu.addItem(addItem)
            
            // Cast submenu (for video-capable devices)
            let videoDevices = CastManager.shared.videoCapableDevices
            if !videoDevices.isEmpty {
                menu.addItem(NSMenuItem.separator())
                
                let castItem = NSMenuItem(title: "Cast to...", action: nil, keyEquivalent: "")
                let castMenu = NSMenu()
                
                for device in videoDevices {
                    let deviceItem = NSMenuItem(title: device.name, action: #selector(contextMenuCastMovie(_:)), keyEquivalent: "")
                    deviceItem.target = self
                    deviceItem.representedObject = (movie, device)
                    castMenu.addItem(deviceItem)
                }
                
                castItem.submenu = castMenu
                menu.addItem(castItem)
            }
            
            // External links submenu
            menu.addItem(NSMenuItem.separator())
            
            let linksItem = NSMenuItem(title: "View Online", action: nil, keyEquivalent: "")
            let linksMenu = NSMenu()
            
            let imdbItem = NSMenuItem(title: "IMDB", action: #selector(contextMenuOpenIMDB(_:)), keyEquivalent: "")
            imdbItem.target = self
            imdbItem.representedObject = movie
            linksMenu.addItem(imdbItem)
            
            let tmdbItem = NSMenuItem(title: "TMDB", action: #selector(contextMenuOpenTMDB(_:)), keyEquivalent: "")
            tmdbItem.target = self
            tmdbItem.representedObject = movie
            linksMenu.addItem(tmdbItem)
            
            let rtItem = NSMenuItem(title: "Rotten Tomatoes", action: #selector(contextMenuOpenRottenTomatoes(_:)), keyEquivalent: "")
            rtItem.target = self
            rtItem.representedObject = movie
            linksMenu.addItem(rtItem)
            
            linksItem.submenu = linksMenu
            menu.addItem(linksItem)
            
        case .show(let show):
            let expandItem = NSMenuItem(title: expandedShows.contains(show.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
            let addItem = NSMenuItem(title: "Add All Episodes to Playlist", action: #selector(contextMenuAddShowToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = show
            menu.addItem(addItem)
            
            // External links submenu
            menu.addItem(NSMenuItem.separator())
            
            let linksItem = NSMenuItem(title: "View Online", action: nil, keyEquivalent: "")
            let linksMenu = NSMenu()
            
            let imdbItem = NSMenuItem(title: "IMDB", action: #selector(contextMenuOpenIMDBShow(_:)), keyEquivalent: "")
            imdbItem.target = self
            imdbItem.representedObject = show
            linksMenu.addItem(imdbItem)
            
            let tmdbItem = NSMenuItem(title: "TMDB", action: #selector(contextMenuOpenTMDBShow(_:)), keyEquivalent: "")
            tmdbItem.target = self
            tmdbItem.representedObject = show
            linksMenu.addItem(tmdbItem)
            
            let rtItem = NSMenuItem(title: "Rotten Tomatoes", action: #selector(contextMenuOpenRottenTomatoesShow(_:)), keyEquivalent: "")
            rtItem.target = self
            rtItem.representedObject = show
            linksMenu.addItem(rtItem)
            
            linksItem.submenu = linksMenu
            menu.addItem(linksItem)
            
        case .season(let season):
            let expandItem = NSMenuItem(title: expandedSeasons.contains(season.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
            let addItem = NSMenuItem(title: "Add Season to Playlist", action: #selector(contextMenuAddSeasonToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = season
            menu.addItem(addItem)
            
        case .episode(let episode):
            let playItem = NSMenuItem(title: "Play Episode", action: #selector(contextMenuPlayEpisode(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = episode
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddEpisodeToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = episode
            menu.addItem(addItem)
            
            // Cast submenu (for video-capable devices)
            let videoDevicesEpisode = CastManager.shared.videoCapableDevices
            if !videoDevicesEpisode.isEmpty {
                menu.addItem(NSMenuItem.separator())
                
                let castItem = NSMenuItem(title: "Cast to...", action: nil, keyEquivalent: "")
                let castMenu = NSMenu()
                
                for device in videoDevicesEpisode {
                    let deviceItem = NSMenuItem(title: device.name, action: #selector(contextMenuCastEpisode(_:)), keyEquivalent: "")
                    deviceItem.target = self
                    deviceItem.representedObject = (episode, device)
                    castMenu.addItem(deviceItem)
                }
                
                castItem.submenu = castMenu
                menu.addItem(castItem)
            }
            
            // External links submenu
            menu.addItem(NSMenuItem.separator())
            
            let linksItem = NSMenuItem(title: "View Online", action: nil, keyEquivalent: "")
            let linksMenu = NSMenu()
            
            let imdbItem = NSMenuItem(title: "IMDB", action: #selector(contextMenuOpenIMDBEpisode(_:)), keyEquivalent: "")
            imdbItem.target = self
            imdbItem.representedObject = episode
            linksMenu.addItem(imdbItem)
            
            let tmdbItem = NSMenuItem(title: "TMDB", action: #selector(contextMenuOpenTMDBEpisode(_:)), keyEquivalent: "")
            tmdbItem.target = self
            tmdbItem.representedObject = episode
            linksMenu.addItem(tmdbItem)
            
            let rtItem = NSMenuItem(title: "Rotten Tomatoes", action: #selector(contextMenuOpenRottenTomatoesEpisode(_:)), keyEquivalent: "")
            rtItem.target = self
            rtItem.representedObject = episode
            linksMenu.addItem(rtItem)
            
            linksItem.submenu = linksMenu
            menu.addItem(linksItem)
            
        case .localTrack(let track):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlayLocalTrack(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = track
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddLocalTrackToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = track
            menu.addItem(addItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let tagsItem = NSMenuItem(title: "See Tags", action: #selector(contextMenuShowTags(_:)), keyEquivalent: "")
            tagsItem.target = self
            tagsItem.representedObject = track
            menu.addItem(tagsItem)
            
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextMenuShowInFinder(_:)), keyEquivalent: "")
            finderItem.target = self
            finderItem.representedObject = track
            menu.addItem(finderItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let removeItem = NSMenuItem(title: "Remove from Library", action: #selector(contextMenuRemoveLocalTrack(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = track
            menu.addItem(removeItem)
            
            let deleteItem = NSMenuItem(title: "Delete File from Disk...", action: #selector(contextMenuDeleteLocalTrack(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = track
            menu.addItem(deleteItem)
            
        case .localAlbum(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayLocalAlbum(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = album
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add Album to Playlist", action: #selector(contextMenuAddLocalAlbumToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = album
            menu.addItem(addItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let removeItem = NSMenuItem(title: "Remove Album from Library", action: #selector(contextMenuRemoveLocalAlbum(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = album
            menu.addItem(removeItem)
            
            let deleteItem = NSMenuItem(title: "Delete Album from Disk...", action: #selector(contextMenuDeleteLocalAlbum(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = album
            menu.addItem(deleteItem)
            
        case .localArtist(let artist):
            let playItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlayLocalArtist(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = artist
            menu.addItem(playItem)
            
            let expandItem = NSMenuItem(title: expandedLocalArtists.contains(artist.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let removeItem = NSMenuItem(title: "Remove Artist from Library", action: #selector(contextMenuRemoveLocalArtist(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = artist
            menu.addItem(removeItem)
            
            let deleteItem = NSMenuItem(title: "Delete Artist from Disk...", action: #selector(contextMenuDeleteLocalArtist(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = artist
            menu.addItem(deleteItem)
            
        case .subsonicTrack(let song):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlaySubsonicSong(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = song
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddSubsonicSongToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = song
            menu.addItem(addItem)
            
        case .subsonicAlbum(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlaySubsonicAlbum(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = album
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add Album to Playlist", action: #selector(contextMenuAddSubsonicAlbumToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = album
            menu.addItem(addItem)
            
        case .subsonicArtist(let artist):
            let playItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlaySubsonicArtist(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = artist
            menu.addItem(playItem)
            
            let expandItem = NSMenuItem(title: expandedSubsonicArtists.contains(artist.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
        case .subsonicPlaylist(let playlist):
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlaySubsonicPlaylist(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = playlist
            menu.addItem(playItem)
            
            let expandItem = NSMenuItem(title: expandedSubsonicPlaylists.contains(playlist.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
        case .plexPlaylist(let playlist):
            let playItem = NSMenuItem(title: "Play Playlist", action: #selector(contextMenuPlayPlexPlaylist(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = playlist
            menu.addItem(playItem)
            
            let expandItem = NSMenuItem(title: expandedPlexPlaylists.contains(playlist.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
        case .radioStation(let station):
            let playItem = NSMenuItem(title: "Play Station", action: #selector(contextMenuPlayRadioStation(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = station
            menu.addItem(playItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let editItem = NSMenuItem(title: "Edit Station...", action: #selector(contextMenuEditRadioStation(_:)), keyEquivalent: "")
            editItem.target = self
            editItem.representedObject = station
            menu.addItem(editItem)
            
            let deleteItem = NSMenuItem(title: "Delete Station", action: #selector(contextMenuDeleteRadioStation(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = station
            menu.addItem(deleteItem)
            
        case .plexRadioStation(let radioType):
            let playItem = NSMenuItem(title: "Play \(radioType.displayName)", action: #selector(contextMenuPlayPlexRadioStation(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = item
            menu.addItem(playItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let viewArtItem = NSMenuItem(title: "View Art", action: #selector(contextMenuViewPlexRadioArt(_:)), keyEquivalent: "")
            viewArtItem.target = self
            viewArtItem.representedObject = item
            menu.addItem(viewArtItem)
            
        case .header:
            return
        }
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    @objc private func contextMenuPlay(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? PlexDisplayItem else { return }
        playTrack(item)
    }
    
    @objc private func contextMenuAddToPlaylist(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? PlexTrack,
              let convertedTrack = PlexManager.shared.convertToTrack(track) else { return }
        WindowManager.shared.audioEngine.loadTracks([convertedTrack])
    }
    
    @objc private func contextMenuPlayLocalTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        playLocalTrack(track)
    }
    
    @objc private func contextMenuAddLocalTrackToPlaylist(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        WindowManager.shared.audioEngine.loadTracks([track.toTrack()])
    }
    
    @objc private func contextMenuShowTags(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        // Close any existing tags panel first
        activeTagsPanel?.close()
        
        let tagsPanel = TagsPanel(track: track)
        tagsPanel.delegate = self
        activeTagsPanel = tagsPanel
        tagsPanel.show()
    }
    
    @objc private func contextMenuPlayLocalAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        playLocalAlbum(album)
    }
    
    @objc private func contextMenuAddLocalAlbumToPlaylist(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        let tracks = album.tracks.map { $0.toTrack() }
        WindowManager.shared.audioEngine.loadTracks(tracks)
    }
    
    @objc private func contextMenuPlayLocalArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        playLocalArtist(artist)
    }
    
    @objc private func contextMenuShowInFinder(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
    }
    
    @objc private func contextMenuRemoveLocalTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        MediaLibrary.shared.removeTrack(track)
    }
    
    @objc private func contextMenuDeleteLocalTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? LibraryTrack else { return }
        deleteTracksFromDisk([track])
    }
    
    @objc private func contextMenuRemoveLocalAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        
        let alert = NSAlert()
        alert.messageText = "Remove album from library?"
        alert.informativeText = "This will remove \(album.tracks.count) tracks from your library. The files will not be deleted from disk."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            for track in album.tracks {
                MediaLibrary.shared.removeTrack(track)
            }
        }
    }
    
    @objc private func contextMenuDeleteLocalAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? Album else { return }
        deleteTracksFromDisk(album.tracks)
    }
    
    @objc private func contextMenuRemoveLocalArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        
        var allTracks: [LibraryTrack] = []
        for album in artist.albums {
            allTracks.append(contentsOf: album.tracks)
        }
        
        let alert = NSAlert()
        alert.messageText = "Remove artist from library?"
        alert.informativeText = "This will remove \(allTracks.count) tracks from your library. The files will not be deleted from disk."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            for track in allTracks {
                MediaLibrary.shared.removeTrack(track)
            }
        }
    }
    
    // MARK: - Radio Station Context Menu Actions
    
    @objc private func contextMenuPlayRadioStation(_ sender: NSMenuItem) {
        guard let station = sender.representedObject as? RadioStation else { return }
        playRadioStation(station)
    }
    
    @objc private func contextMenuEditRadioStation(_ sender: NSMenuItem) {
        guard let station = sender.representedObject as? RadioStation else { return }
        
        activeRadioStationSheet = AddRadioStationSheet(station: station)
        activeRadioStationSheet?.showDialog { [weak self] updatedStation in
            self?.activeRadioStationSheet = nil  // Release reference when done
            if let updated = updatedStation {
                RadioManager.shared.updateStation(updated)
                self?.loadRadioStations()
            }
        }
    }
    
    @objc private func contextMenuDeleteRadioStation(_ sender: NSMenuItem) {
        guard let station = sender.representedObject as? RadioStation else { return }
        
        let alert = NSAlert()
        alert.messageText = "Delete radio station?"
        alert.informativeText = "Are you sure you want to delete '\(station.name)'?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            RadioManager.shared.removeStation(station)
            loadRadioStations()
        }
    }
    
    // MARK: - Plex Radio Station Context Menu Actions
    
    @objc private func contextMenuPlayPlexRadioStation(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? PlexDisplayItem,
              case .plexRadioStation(let radioType) = item.type else { return }
        playPlexRadioStation(radioType)
    }
    
    @objc private func contextMenuViewPlexRadioArt(_ sender: NSMenuItem) {
        // Enter art-only mode - will display the currently playing track's artwork
        if currentArtwork != nil {
            isArtOnlyMode = true
        }
    }
    
    @objc private func contextMenuDeleteLocalArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        
        var allTracks: [LibraryTrack] = []
        for album in artist.albums {
            allTracks.append(contentsOf: album.tracks)
        }
        deleteTracksFromDisk(allTracks)
    }
    
    /// Helper to delete tracks from disk with confirmation
    private func deleteTracksFromDisk(_ tracks: [LibraryTrack]) {
        guard !tracks.isEmpty else { return }
        
        let alert = NSAlert()
        alert.messageText = tracks.count == 1
            ? "Delete file from disk?"
            : "Delete \(tracks.count) files from disk?"
        alert.informativeText = "This will permanently delete the file(s) from your computer. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        let moveToTrashCheckbox = NSButton(checkboxWithTitle: "Move to Trash instead of deleting permanently", target: nil, action: nil)
        moveToTrashCheckbox.state = .on
        alert.accessoryView = moveToTrashCheckbox
        
        if alert.runModal() != .alertFirstButtonReturn {
            return
        }
        
        let useTrash = moveToTrashCheckbox.state == .on
        var failedFiles: [String] = []
        
        for track in tracks {
            do {
                if useTrash {
                    try FileManager.default.trashItem(at: track.url, resultingItemURL: nil)
                } else {
                    try FileManager.default.removeItem(at: track.url)
                }
                MediaLibrary.shared.removeTrack(track)
            } catch {
                failedFiles.append(track.url.lastPathComponent)
            }
        }
        
        if !failedFiles.isEmpty {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Some files could not be deleted"
            errorAlert.informativeText = "Failed to delete:\n" + failedFiles.prefix(5).joined(separator: "\n")
            if failedFiles.count > 5 {
                errorAlert.informativeText += "\n...and \(failedFiles.count - 5) more"
            }
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }
    
    // MARK: - Subsonic Context Menu Actions
    
    @objc private func contextMenuPlaySubsonicSong(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong else { return }
        playSubsonicSong(song)
    }
    
    @objc private func contextMenuAddSubsonicSongToPlaylist(_ sender: NSMenuItem) {
        guard let song = sender.representedObject as? SubsonicSong,
              let track = SubsonicManager.shared.convertToTrack(song) else { return }
        WindowManager.shared.audioEngine.loadTracks([track])
    }
    
    @objc private func contextMenuPlaySubsonicAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? SubsonicAlbum else { return }
        playSubsonicAlbum(album)
    }
    
    @objc private func contextMenuAddSubsonicAlbumToPlaylist(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? SubsonicAlbum else { return }
        Task { @MainActor in
            do {
                let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                let tracks = songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                WindowManager.shared.audioEngine.loadTracks(tracks)
            } catch {
                NSLog("Failed to add subsonic album to playlist: %@", error.localizedDescription)
            }
        }
    }
    
    @objc private func contextMenuPlaySubsonicArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? SubsonicArtist else { return }
        playSubsonicArtist(artist)
    }
    
    @objc private func contextMenuPlaySubsonicPlaylist(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? SubsonicPlaylist else { return }
        playSubsonicPlaylist(playlist)
    }
    
    @objc private func contextMenuPlayPlexPlaylist(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? PlexPlaylist else { return }
        playPlexPlaylist(playlist)
    }
    
    // MARK: - Plex Context Menu Actions
    
    @objc private func contextMenuPlayAlbum(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? PlexAlbum else { return }
        playAlbum(album)
    }
    
    @objc private func contextMenuAddAlbumToPlaylist(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? PlexAlbum else { return }
        Task { @MainActor in
            do {
                let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                let convertedTracks = PlexManager.shared.convertToTracks(tracks)
                WindowManager.shared.audioEngine.loadTracks(convertedTracks)
            } catch {
                NSLog("Failed to add album to playlist: %@", error.localizedDescription)
            }
        }
    }
    
    @objc private func contextMenuPlayArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? PlexArtist else { return }
        playArtist(artist)
    }
    
    // MARK: - Plex Video Context Menu Actions
    
    @objc private func contextMenuAddMovieToPlaylist(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? PlexMovie,
              let track = PlexManager.shared.convertToTrack(movie) else {
            NSLog("Failed to convert movie to track for playlist")
            return
        }
        WindowManager.shared.audioEngine.loadTracks([track])
        NSLog("Added movie to playlist: %@", movie.title)
    }
    
    @objc private func contextMenuAddEpisodeToPlaylist(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? PlexEpisode,
              let track = PlexManager.shared.convertToTrack(episode) else {
            NSLog("Failed to convert episode to track for playlist")
            return
        }
        WindowManager.shared.audioEngine.loadTracks([track])
        NSLog("Added episode to playlist: %@", episode.title)
    }
    
    @objc private func contextMenuAddSeasonToPlaylist(_ sender: NSMenuItem) {
        guard let season = sender.representedObject as? PlexSeason else { return }
        Task { @MainActor in
            do {
                let episodes = try await PlexManager.shared.fetchEpisodes(forSeason: season)
                let tracks = PlexManager.shared.convertToTracks(episodes)
                if !tracks.isEmpty {
                    WindowManager.shared.audioEngine.loadTracks(tracks)
                    NSLog("Added %d episodes from season to playlist: %@", tracks.count, season.title)
                }
            } catch {
                NSLog("Failed to add season to playlist: %@", error.localizedDescription)
            }
        }
    }
    
    @objc private func contextMenuAddShowToPlaylist(_ sender: NSMenuItem) {
        guard let show = sender.representedObject as? PlexShow else { return }
        Task { @MainActor in
            do {
                let seasons = try await PlexManager.shared.fetchSeasons(forShow: show)
                var allTracks: [Track] = []
                for season in seasons {
                    let episodes = try await PlexManager.shared.fetchEpisodes(forSeason: season)
                    let tracks = PlexManager.shared.convertToTracks(episodes)
                    allTracks.append(contentsOf: tracks)
                }
                if !allTracks.isEmpty {
                    WindowManager.shared.audioEngine.loadTracks(allTracks)
                    NSLog("Added %d episodes from show to playlist: %@", allTracks.count, show.title)
                }
            } catch {
                NSLog("Failed to add show to playlist: %@", error.localizedDescription)
            }
        }
    }
    
    // MARK: - Plex Radio Actions
    
    @objc private func contextMenuStartTrackRadio(_ sender: NSMenuItem) {
        NSLog("contextMenuStartTrackRadio called, representedObject type: %@", String(describing: type(of: sender.representedObject)))
        guard let track = sender.representedObject as? PlexTrack else {
            NSLog("contextMenuStartTrackRadio: representedObject is NOT a PlexTrack, it's: %@", String(describing: sender.representedObject))
            return
        }
        NSLog("contextMenuStartTrackRadio: Starting radio for track: %@", track.title)
        startTrackRadio(track)
    }
    
    @objc private func contextMenuStartAlbumRadio(_ sender: NSMenuItem) {
        guard let album = sender.representedObject as? PlexAlbum else { return }
        startAlbumRadio(album)
    }
    
    @objc private func contextMenuStartArtistRadio(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? PlexArtist else { return }
        startArtistRadio(artist)
    }
    
    /// Start a track radio - plays similar tracks based on the seed track
    private func startTrackRadio(_ track: PlexTrack) {
        NSLog("startTrackRadio called for: %@ (id: %@)", track.title, track.id)
        
        Task { @MainActor in
            NSLog("startTrackRadio: Creating radio playlist...")
            let tracks = await PlexManager.shared.createTrackRadio(from: track, limit: 100)
            
            NSLog("startTrackRadio: Got %d tracks from PlexManager", tracks.count)
            
            if tracks.isEmpty {
                NSLog("Track Radio: No similar tracks found for '%@'", track.title)
                // Could show an alert here if desired
                return
            }
            
            // Clear current playlist, load radio tracks, and start playing
            NSLog("startTrackRadio: Loading tracks into audio engine...")
            let audioEngine = WindowManager.shared.audioEngine
            audioEngine.clearPlaylist()
            audioEngine.loadTracks(tracks)
            audioEngine.play()
            NSLog("Track Radio started with %d tracks", tracks.count)
        }
    }
    
    /// Start an album radio - plays tracks similar to the album's content
    private func startAlbumRadio(_ album: PlexAlbum) {
        NSLog("Starting Album Radio for: %@", album.title)
        
        Task { @MainActor in
            let tracks = await PlexManager.shared.createAlbumRadio(from: album, limit: 100)
            
            if tracks.isEmpty {
                NSLog("Album Radio: No similar tracks found for '%@'", album.title)
                return
            }
            
            // Clear current playlist, load radio tracks, and start playing
            let audioEngine = WindowManager.shared.audioEngine
            audioEngine.clearPlaylist()
            audioEngine.loadTracks(tracks)
            audioEngine.play()
            NSLog("Album Radio started with %d tracks", tracks.count)
        }
    }
    
    /// Start an artist radio - plays tracks from similar artists
    private func startArtistRadio(_ artist: PlexArtist) {
        NSLog("Starting Artist Radio for: %@", artist.title)
        
        Task { @MainActor in
            let tracks = await PlexManager.shared.createArtistRadio(from: artist, limit: 100)
            
            if tracks.isEmpty {
                NSLog("Artist Radio: No similar tracks found for '%@'", artist.title)
                return
            }
            
            // Clear current playlist, load radio tracks, and start playing
            let audioEngine = WindowManager.shared.audioEngine
            audioEngine.clearPlaylist()
            audioEngine.loadTracks(tracks)
            audioEngine.play()
            NSLog("Artist Radio started with %d tracks", tracks.count)
        }
    }
    
    /// Start a library radio - plays random sonically diverse tracks from the library
    private func startLibraryRadio() {
        guard let library = PlexManager.shared.currentLibrary else { return }
        NSLog("Starting Library Radio for: %@", library.title)
        
        Task { @MainActor in
            let tracks = await PlexManager.shared.createLibraryRadio()
            if tracks.isEmpty {
                // Fallback to cached tracks if available
                if !cachedTracks.isEmpty {
                    let libraryTracks = cachedTracks.shuffled().prefix(100).compactMap { plexTrack -> Track? in
                        PlexManager.shared.convertToTrack(plexTrack)
                    }
                    if !libraryTracks.isEmpty {
                        let audioEngine = WindowManager.shared.audioEngine
                        audioEngine.clearPlaylist()
                        audioEngine.loadTracks(libraryTracks)
                        audioEngine.play()
                        NSLog("Library Radio started with %d random cached tracks", libraryTracks.count)
                    }
                }
                return
            }
            
            let audioEngine = WindowManager.shared.audioEngine
            audioEngine.clearPlaylist()
            audioEngine.loadTracks(tracks)
            audioEngine.play()
            NSLog("Library Radio started with %d tracks", tracks.count)
        }
    }
    
    @objc private func contextMenuToggleExpand(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? PlexDisplayItem else { return }
        toggleExpand(item)
    }
    
    @objc private func contextMenuPlayMovie(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? PlexMovie else { return }
        playMovie(movie)
    }
    
    @objc private func contextMenuPlayEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? PlexEpisode else { return }
        playEpisode(episode)
    }
    
    @objc private func contextMenuCastMovie(_ sender: NSMenuItem) {
        NSLog("PlexBrowserView: contextMenuCastMovie ENTER")
        guard let (movie, device) = sender.representedObject as? (PlexMovie, CastDevice) else {
            NSLog("PlexBrowserView: Failed to get movie/device from menu item")
            return
        }
        
        NSLog("PlexBrowserView: Casting movie '%@' to device '%@' (type: %@)", movie.title, device.name, device.type.rawValue)
        
        // Prevent dual casting - check if already casting
        if WindowManager.shared.isVideoCastingActive {
            NSLog("PlexBrowserView: Cannot cast - already casting")
            let alert = NSAlert()
            alert.messageText = "Already Casting"
            alert.informativeText = "Stop the current cast before starting a new one."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        Task { @MainActor in
            NSLog("PlexBrowserView: Starting cast Task")
            do {
                try await CastManager.shared.castPlexMovie(movie, to: device)
                NSLog("PlexBrowserView: Cast movie '%@' to %@ - SUCCESS", movie.title, device.name)
            } catch {
                NSLog("PlexBrowserView: Failed to cast movie: %@", error.localizedDescription)
                let alert = NSAlert()
                alert.messageText = "Cast Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        NSLog("PlexBrowserView: contextMenuCastMovie EXIT (Task launched)")
    }
    
    @objc private func contextMenuCastEpisode(_ sender: NSMenuItem) {
        guard let (episode, device) = sender.representedObject as? (PlexEpisode, CastDevice) else { return }
        
        // Prevent dual casting - check if already casting
        if WindowManager.shared.isVideoCastingActive {
            NSLog("PlexBrowserView: Cannot cast - already casting")
            let alert = NSAlert()
            alert.messageText = "Already Casting"
            alert.informativeText = "Stop the current cast before starting a new one."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        Task {
            do {
                try await CastManager.shared.castPlexEpisode(episode, to: device)
                NSLog("PlexBrowserView: Cast episode '%@' to %@", episode.title, device.name)
            } catch {
                NSLog("PlexBrowserView: Failed to cast episode: %@", error.localizedDescription)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Cast Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - External Links Context Menu Actions
    
    @objc private func contextMenuOpenIMDB(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? PlexMovie else { return }
        
        // If we already have the IMDB ID, open directly
        if let imdbId = movie.imdbId {
            if let url = URL(string: "https://www.imdb.com/title/\(imdbId)/") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        // Fetch detailed metadata to get IMDB ID
        Task { @MainActor in
            do {
                if let detailed = try await PlexManager.shared.fetchMovieDetails(movieID: movie.id),
                   let imdbId = detailed.imdbId,
                   let url = URL(string: "https://www.imdb.com/title/\(imdbId)/") {
                    NSWorkspace.shared.open(url)
                    return
                }
            } catch {
                NSLog("Failed to fetch movie details: %@", error.localizedDescription)
            }
            // Fallback to search if fetch fails
            if let url = movie.imdbURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func contextMenuOpenTMDB(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? PlexMovie else { return }
        
        if let tmdbId = movie.tmdbId {
            if let url = URL(string: "https://www.themoviedb.org/movie/\(tmdbId)") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        Task { @MainActor in
            do {
                if let detailed = try await PlexManager.shared.fetchMovieDetails(movieID: movie.id),
                   let tmdbId = detailed.tmdbId,
                   let url = URL(string: "https://www.themoviedb.org/movie/\(tmdbId)") {
                    NSWorkspace.shared.open(url)
                    return
                }
            } catch {
                NSLog("Failed to fetch movie details: %@", error.localizedDescription)
            }
            if let url = movie.tmdbURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func contextMenuOpenRottenTomatoes(_ sender: NSMenuItem) {
        guard let movie = sender.representedObject as? PlexMovie,
              let url = movie.rottenTomatoesSearchURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    @objc private func contextMenuOpenIMDBShow(_ sender: NSMenuItem) {
        guard let show = sender.representedObject as? PlexShow else { return }
        
        if let imdbId = show.imdbId {
            if let url = URL(string: "https://www.imdb.com/title/\(imdbId)/") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        Task { @MainActor in
            do {
                if let detailed = try await PlexManager.shared.fetchShowDetails(showID: show.id),
                   let imdbId = detailed.imdbId,
                   let url = URL(string: "https://www.imdb.com/title/\(imdbId)/") {
                    NSWorkspace.shared.open(url)
                    return
                }
            } catch {
                NSLog("Failed to fetch show details: %@", error.localizedDescription)
            }
            if let url = show.imdbURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func contextMenuOpenTMDBShow(_ sender: NSMenuItem) {
        guard let show = sender.representedObject as? PlexShow else { return }
        
        if let tmdbId = show.tmdbId {
            if let url = URL(string: "https://www.themoviedb.org/tv/\(tmdbId)") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        Task { @MainActor in
            do {
                if let detailed = try await PlexManager.shared.fetchShowDetails(showID: show.id),
                   let tmdbId = detailed.tmdbId,
                   let url = URL(string: "https://www.themoviedb.org/tv/\(tmdbId)") {
                    NSWorkspace.shared.open(url)
                    return
                }
            } catch {
                NSLog("Failed to fetch show details: %@", error.localizedDescription)
            }
            if let url = show.tmdbURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func contextMenuOpenRottenTomatoesShow(_ sender: NSMenuItem) {
        guard let show = sender.representedObject as? PlexShow,
              let url = show.rottenTomatoesSearchURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    @objc private func contextMenuOpenIMDBEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? PlexEpisode else { return }
        
        if let imdbId = episode.imdbId {
            if let url = URL(string: "https://www.imdb.com/title/\(imdbId)/") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        Task { @MainActor in
            do {
                if let detailed = try await PlexManager.shared.fetchEpisodeDetails(episodeID: episode.id),
                   let imdbId = detailed.imdbId,
                   let url = URL(string: "https://www.imdb.com/title/\(imdbId)/") {
                    NSWorkspace.shared.open(url)
                    return
                }
            } catch {
                NSLog("Failed to fetch episode details: %@", error.localizedDescription)
            }
            if let url = episode.imdbURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func contextMenuOpenTMDBEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? PlexEpisode else { return }
        
        // Episodes don't have individual TMDB IDs, use search
        if let url = episode.tmdbSearchURL {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func contextMenuOpenRottenTomatoesEpisode(_ sender: NSMenuItem) {
        guard let episode = sender.representedObject as? PlexEpisode,
              let url = episode.rottenTomatoesSearchURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Server/Library Selection Menus
    
    private func showServerMenu(at event: NSEvent) {
        let menu = NSMenu()
        
        let servers = PlexManager.shared.servers
        if servers.isEmpty {
            let noServers = NSMenuItem(title: "No servers available", action: nil, keyEquivalent: "")
            noServers.isEnabled = false
            menu.addItem(noServers)
        } else {
            for server in servers {
                let item = NSMenuItem(title: server.name, action: #selector(selectServer(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = server.id
                item.state = server.id == PlexManager.shared.currentServer?.id ? .on : .off
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Servers", action: #selector(refreshServers), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    private func showLibraryMenu(at event: NSEvent) {
        let menu = NSMenu()
        
        let libraries = PlexManager.shared.availableLibraries
        let currentLibraryId = PlexManager.shared.currentLibrary?.id
        
        if libraries.isEmpty {
            let noLibraries = NSMenuItem(title: "No libraries available", action: nil, keyEquivalent: "")
            noLibraries.isEnabled = false
            menu.addItem(noLibraries)
        } else {
            for library in libraries {
                // Show library type in parentheses
                let typeLabel: String
                if library.isMusicLibrary {
                    typeLabel = "Music"
                } else if library.isMovieLibrary {
                    typeLabel = "Movies"
                } else if library.isShowLibrary {
                    typeLabel = "TV Shows"
                } else {
                    typeLabel = library.type
                }
                
                let item = NSMenuItem(title: "\(library.title) (\(typeLabel))", action: #selector(selectLibrary(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = library
                item.state = library.id == currentLibraryId ? .on : .off
                menu.addItem(item)
            }
        }
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    @objc private func selectServer(_ sender: NSMenuItem) {
        guard let serverID = sender.representedObject as? String,
              let server = PlexManager.shared.servers.first(where: { $0.id == serverID }) else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        startLoadingAnimation()
        needsDisplay = true
        
        Task { @MainActor in
            do {
                try await PlexManager.shared.connect(to: server)
                clearAllCachedData()
                reloadData()
            } catch {
                NSLog("Failed to connect to server: %@", error.localizedDescription)
                isLoading = false
                stopLoadingAnimation()
                errorMessage = "Failed to connect to \(server.name): \(error.localizedDescription)"
                needsDisplay = true
            }
        }
    }
    
    @objc private func selectLibrary(_ sender: NSMenuItem) {
        guard let library = sender.representedObject as? PlexLibrary else {
            return
        }
        
        PlexManager.shared.selectLibrary(library)
        
        // Clear all cached data when switching libraries
        cachedArtists = []
        cachedAlbums = []
        cachedTracks = []
        artistAlbums = [:]
        albumTracks = [:]
        artistAlbumCounts = [:]
        expandedArtists = []
        expandedAlbums = []
        cachedMovies = []
        cachedShows = []
        showSeasons = [:]
        seasonEpisodes = [:]
        expandedShows = []
        expandedSeasons = []
        searchResults = nil
        
        reloadData()
    }
    
    @objc private func refreshServers() {
        Task { @MainActor in
            do {
                try await PlexManager.shared.refreshServers()
                needsDisplay = true
            } catch {
                NSLog("Failed to refresh servers: %@", error.localizedDescription)
            }
        }
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        // ESC key dismisses rating overlay
        if isRatingOverlayVisible && event.keyCode == 53 {
            hideRatingOverlay()
            return
        }
        
        // Number keys 1-5 set rating when overlay is visible
        if isRatingOverlayVisible {
            let keyCode = event.keyCode
            // 1-5 keys are keycodes 18-23 (1, 2, 3, 4, 5)
            if keyCode >= 18 && keyCode <= 22 {
                let starRating = Int(keyCode - 17)  // 1-5
                ratingOverlay.setRating(starRating * 2)
                submitRating(starRating * 2)
                return
            }
        }
        
        // Handle visualizer controls when in visualization mode
        if isVisualizingArt && isArtOnlyMode {
            switch event.keyCode {
            case 123: // Left arrow - previous effect
                visMode = .single
                let effects = VisEffect.allCases
                if let currentIndex = effects.firstIndex(of: currentVisEffect) {
                    let prevIndex = (currentIndex - 1 + effects.count) % effects.count
                    currentVisEffect = effects[prevIndex]
                }
                return
                
            case 124: // Right arrow - next effect
                visMode = .single
                let effects = VisEffect.allCases
                if let currentIndex = effects.firstIndex(of: currentVisEffect) {
                    let nextIndex = (currentIndex + 1) % effects.count
                    currentVisEffect = effects[nextIndex]
                }
                return
                
            case 126: // Up arrow - increase intensity
                visEffectIntensity = min(2.0, visEffectIntensity + 0.25)
                return
                
            case 125: // Down arrow - decrease intensity
                visEffectIntensity = max(0.5, visEffectIntensity - 0.25)
                return
                
            case 53: // Escape - turn off visualization
                isVisualizingArt = false
                return
                
            case 15: // R key - toggle random mode
                visMode = visMode == .random ? .single : .random
                return
                
            case 8: // C key - toggle cycle mode
                if visMode == .cycle {
                    visMode = .single
                    cycleTimer?.invalidate()
                } else {
                    visMode = .cycle
                    startCycleTimer()
                }
                return
                
            case 3: // F key - toggle fullscreen
                window?.toggleFullScreen(nil)
                return
                
            default:
                break
            }
        }
        
        // Handle Escape in art-only mode (without visualization)
        if isArtOnlyMode && !isVisualizingArt && event.keyCode == 53 {
            isArtOnlyMode = false
            return
        }
        
        switch event.keyCode {
        case 36: // Enter - play selected
            if let index = selectedIndices.first, index < displayItems.count {
                handleDoubleClick(on: displayItems[index])
            }
            
        case 125: // Down arrow
            if !isVisualizingArt {
                if let maxIndex = selectedIndices.max(), maxIndex < displayItems.count - 1 {
                    selectedIndices = [maxIndex + 1]
                    ensureVisible(index: maxIndex + 1)
                    loadArtworkForSelection()
                    needsDisplay = true
                }
            }
            
        case 126: // Up arrow
            if !isVisualizingArt {
                if let minIndex = selectedIndices.min(), minIndex > 0 {
                    selectedIndices = [minIndex - 1]
                    ensureVisible(index: minIndex - 1)
                    loadArtworkForSelection()
                    needsDisplay = true
                }
            }
            
        default:
            // Handle typing for search
            if browseMode == .search, let chars = event.characters, !chars.isEmpty {
                if event.keyCode == 51 { // Delete
                    if !searchQuery.isEmpty {
                        searchQuery.removeLast()
                        loadDataForCurrentMode()
                    }
                } else if chars.rangeOfCharacter(from: .alphanumerics) != nil ||
                          chars.rangeOfCharacter(from: .whitespaces) != nil {
                    searchQuery += chars
                    loadDataForCurrentMode()
                }
            }
        }
    }
    
    private func ensureVisible(index: Int) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
        
        let itemTop = CGFloat(index) * itemHeight
        let itemBottom = itemTop + itemHeight
        
        if itemTop < scrollOffset {
            scrollOffset = itemTop
        } else if itemBottom > scrollOffset + listHeight {
            scrollOffset = itemBottom - listHeight
        }
    }
    
    // MARK: - Data Management
    
    private func loadDataForCurrentMode() {
        // Radio source - only radio tab has content
        if case .radio = currentSource {
            if browseMode == .radio {
                loadRadioStations()
            } else {
                // Non-radio tabs show empty for radio source
                isLoading = false
                errorMessage = nil
                stopLoadingAnimation()
                displayItems = []
                needsDisplay = true
            }
            return
        }
        
        // Non-radio sources: radio tab shows Plex Radio options (for Plex) or empty
        if browseMode == .radio {
            if case .plex = currentSource, PlexManager.shared.isLinked {
                // Show Plex Radio options in the RADIO tab when in Plex mode
                loadPlexRadioStations()
            } else {
                isLoading = false
                errorMessage = nil
                stopLoadingAnimation()
                displayItems = []
                needsDisplay = true
            }
            return
        }
        
        // Check source first - local files don't need async loading
        if case .local = currentSource {
            loadLocalData()
            return
        }
        
        // Subsonic source - use Subsonic loading
        if case .subsonic(let serverId) = currentSource {
            loadSubsonicData(serverId: serverId)
            return
        }
        
        // Plex source - async loading
        isLoading = true
        errorMessage = nil
        startLoadingAnimation()
        needsDisplay = true
        
        Task { @MainActor in
            do {
                let plexManager = PlexManager.shared
                
                switch browseMode {
                case .artists:
                    if cachedArtists.isEmpty {
                        // Use preloaded data from PlexManager if available
                        if plexManager.isContentPreloaded && !plexManager.cachedArtists.isEmpty {
                            cachedArtists = plexManager.cachedArtists
                            cachedAlbums = plexManager.cachedAlbums
                            NSLog("PlexBrowserView: Using preloaded artists (%d) and albums (%d)", cachedArtists.count, cachedAlbums.count)
                        } else {
                            cachedArtists = try await plexManager.fetchArtists()
                            // Also fetch albums to get accurate counts per artist
                            if cachedAlbums.isEmpty {
                                cachedAlbums = try await plexManager.fetchAlbums(offset: 0, limit: 10000)
                            }
                        }
                        // Build artist album counts from the albums data
                        buildArtistAlbumCounts()
                    }
                    buildArtistItems()
                    
                case .albums:
                    if cachedAlbums.isEmpty {
                        // Use preloaded data from PlexManager if available
                        if plexManager.isContentPreloaded && !plexManager.cachedAlbums.isEmpty {
                            cachedAlbums = plexManager.cachedAlbums
                            NSLog("PlexBrowserView: Using preloaded albums (%d)", cachedAlbums.count)
                        } else {
                            cachedAlbums = try await plexManager.fetchAlbums(offset: 0, limit: 500)
                        }
                    }
                    buildAlbumItems()
                    
                case .tracks:
                    if cachedTracks.isEmpty {
                        cachedTracks = try await plexManager.fetchTracks(offset: 0, limit: 500)
                    }
                    buildTrackItems()
                    
                case .movies:
                    NSLog("PlexBrowserView: Loading movies...")
                    if cachedMovies.isEmpty {
                        // Use preloaded data from PlexManager if available
                        if plexManager.isContentPreloaded && !plexManager.cachedMovies.isEmpty {
                            cachedMovies = plexManager.cachedMovies
                            NSLog("PlexBrowserView: Using preloaded movies (%d)", cachedMovies.count)
                        } else {
                            cachedMovies = try await plexManager.fetchMovies(offset: 0, limit: 500)
                            NSLog("PlexBrowserView: Loaded %d movies", cachedMovies.count)
                        }
                    }
                    buildMovieItems()
                    NSLog("PlexBrowserView: Built %d movie items", displayItems.count)
                    
                case .shows:
                    NSLog("PlexBrowserView: Loading TV shows...")
                    if cachedShows.isEmpty {
                        // Use preloaded data from PlexManager if available
                        if plexManager.isContentPreloaded && !plexManager.cachedShows.isEmpty {
                            cachedShows = plexManager.cachedShows
                            NSLog("PlexBrowserView: Using preloaded shows (%d)", cachedShows.count)
                        } else {
                            cachedShows = try await plexManager.fetchShows(offset: 0, limit: 500)
                            NSLog("PlexBrowserView: Loaded %d shows", cachedShows.count)
                        }
                    }
                    buildShowItems()
                    NSLog("PlexBrowserView: Built %d show items", displayItems.count)
                    
                case .plists:
                    NSLog("PlexBrowserView: Loading Plex playlists...")
                    if cachedPlexPlaylists.isEmpty {
                        if !plexManager.cachedPlaylists.isEmpty {
                            cachedPlexPlaylists = plexManager.cachedPlaylists
                            NSLog("PlexBrowserView: Using cached playlists (%d)", cachedPlexPlaylists.count)
                        } else {
                            cachedPlexPlaylists = try await plexManager.fetchPlaylists()
                            NSLog("PlexBrowserView: Loaded %d playlists", cachedPlexPlaylists.count)
                        }
                    }
                    buildPlexPlaylistItems()
                    NSLog("PlexBrowserView: Built %d playlist items", displayItems.count)
                    
                case .search:
                    if !searchQuery.isEmpty {
                        // Search in the current library
                        searchResults = try await plexManager.search(query: searchQuery)
                        buildSearchItems()
                    } else {
                        displayItems = []
                    }
                    
                case .radio:
                    // Radio is handled at the start of loadDataForCurrentMode()
                    // This case should never be reached but is here for exhaustive switch
                    loadRadioStations()
                }
                
                isLoading = false
                stopLoadingAnimation()
                errorMessage = nil
            } catch {
                NSLog("PlexBrowserView: Error loading data for mode %d: %@", browseMode.rawValue, error.localizedDescription)
                isLoading = false
                stopLoadingAnimation()
                errorMessage = error.localizedDescription
            }
            needsDisplay = true
        }
    }
    
    /// Build album counts per artist from the cached albums
    private func buildArtistAlbumCounts() {
        artistAlbumCounts.removeAll()
        for album in cachedAlbums {
            // Albums have parentKey which is the artist's key (e.g., "/library/metadata/12345")
            // Extract the artist ID from parentKey
            if let parentKey = album.parentKey {
                let artistId = parentKey.replacingOccurrences(of: "/library/metadata/", with: "")
                artistAlbumCounts[artistId, default: 0] += 1
            }
        }
    }
    
    private func buildArtistItems() {
        displayItems.removeAll()
        
        // Sort artists
        let sortedArtists = sortPlexArtists(cachedArtists)
        
        for artist in sortedArtists {
            let isExpanded = expandedArtists.contains(artist.id)
            
            // Show album count - prefer counted from albums, then API count, then fetched albums
            let info: String?
            if let count = artistAlbumCounts[artist.id], count > 0 {
                // We have a count from the albums fetch
                info = "\(count) \(count == 1 ? "album" : "albums")"
            } else if let albums = artistAlbums[artist.id] {
                // We've expanded this artist - show actual count
                info = "\(albums.count) \(albums.count == 1 ? "album" : "albums")"
            } else if artist.albumCount > 0 {
                // API returned a count
                info = "\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums")"
            } else {
                // No count available - show nothing
                info = nil
            }
            
            displayItems.append(PlexDisplayItem(
                id: artist.id,
                title: artist.title,
                info: info,
                indentLevel: 0,
                hasChildren: true,
                type: .artist(artist)
            ))
            
            if isExpanded, let albums = artistAlbums[artist.id] {
                // Sort albums within artist
                let sortedAlbums = sortPlexAlbums(albums)
                for album in sortedAlbums {
                    displayItems.append(PlexDisplayItem(
                        id: album.id,
                        title: album.title,
                        info: album.year.map { String($0) },
                        indentLevel: 1,
                        hasChildren: true,
                        type: .album(album)
                    ))
                    
                    if expandedAlbums.contains(album.id), let tracks = albumTracks[album.id] {
                        // Tracks sorted by track number (Plex uses 'index' for track number)
                        let sortedTracks = tracks.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
                        for track in sortedTracks {
                            displayItems.append(PlexDisplayItem(
                                id: track.id,
                                title: track.title,
                                info: track.formattedDuration,
                                indentLevel: 2,
                                hasChildren: false,
                                type: .track(track)
                            ))
                        }
                    }
                }
            }
        }
    }
    
    private func buildAlbumItems() {
        let sortedAlbums = sortPlexAlbums(cachedAlbums)
        displayItems = sortedAlbums.map { album in
            PlexDisplayItem(
                id: album.id,
                title: "\(album.parentTitle ?? "Unknown") - \(album.title)",
                info: album.year.map { String($0) },
                indentLevel: 0,
                hasChildren: false,
                type: .album(album)
            )
        }
    }
    
    private func buildTrackItems() {
        let sortedTracks = sortPlexTracks(cachedTracks)
        displayItems = sortedTracks.map { track in
            PlexDisplayItem(
                id: track.id,
                title: "\(track.grandparentTitle ?? "Unknown") - \(track.title)",
                info: track.formattedDuration,
                indentLevel: 0,
                hasChildren: false,
                type: .track(track)
            )
        }
    }
    
    private func buildMovieItems() {
        displayItems = cachedMovies.map { movie in
            let info = [movie.year.map { String($0) }, movie.formattedDuration]
                .compactMap { $0 }
                .joined(separator: " • ")
            
            return PlexDisplayItem(
                id: movie.id,
                title: movie.title,
                info: info.isEmpty ? nil : info,
                indentLevel: 0,
                hasChildren: false,
                type: .movie(movie)
            )
        }
    }
    
    private func buildShowItems() {
        displayItems.removeAll()
        
        for show in cachedShows {
            let isExpanded = expandedShows.contains(show.id)
            let info = [show.year.map { String($0) }, "\(show.childCount) seasons"]
                .compactMap { $0 }
                .joined(separator: " • ")
            
            displayItems.append(PlexDisplayItem(
                id: show.id,
                title: show.title,
                info: info,
                indentLevel: 0,
                hasChildren: true,
                type: .show(show)
            ))
            
            if isExpanded, let seasons = showSeasons[show.id] {
                for season in seasons {
                    let seasonExpanded = expandedSeasons.contains(season.id)
                    
                    displayItems.append(PlexDisplayItem(
                        id: season.id,
                        title: season.title,
                        info: "\(season.leafCount) episodes",
                        indentLevel: 1,
                        hasChildren: true,
                        type: .season(season)
                    ))
                    
                    if seasonExpanded, let episodes = seasonEpisodes[season.id] {
                        for episode in episodes {
                            displayItems.append(PlexDisplayItem(
                                id: episode.id,
                                title: "\(episode.episodeIdentifier) - \(episode.title)",
                                info: episode.formattedDuration,
                                indentLevel: 2,
                                hasChildren: false,
                                type: .episode(episode)
                            ))
                        }
                    }
                }
            }
        }
    }
    
    private func buildPlexPlaylistItems() {
        displayItems.removeAll()
        
        // Filter to audio playlists only for now
        let audioPlaylists = cachedPlexPlaylists.filter { $0.isAudioPlaylist }
        
        // Deduplicate playlists by title (Plex API sometimes returns duplicates with different IDs)
        var seenTitles = Set<String>()
        let uniquePlaylists = audioPlaylists.filter { playlist in
            let normalizedTitle = playlist.title.lowercased()
            if seenTitles.contains(normalizedTitle) {
                return false
            }
            seenTitles.insert(normalizedTitle)
            return true
        }
        
        let sortedPlaylists = uniquePlaylists.sorted { 
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending 
        }
        
        for playlist in sortedPlaylists {
            let isExpanded = expandedPlexPlaylists.contains(playlist.id)
            let trackCount = playlist.leafCount
            let info = "\(trackCount) \(trackCount == 1 ? "track" : "tracks")"
            
            displayItems.append(PlexDisplayItem(
                id: playlist.id,
                title: playlist.title,
                info: info,
                indentLevel: 0,
                hasChildren: trackCount > 0,
                type: .plexPlaylist(playlist)
            ))
            
            // Show tracks if expanded
            if isExpanded, let tracks = plexPlaylistTracks[playlist.id] {
                for track in tracks {
                    displayItems.append(PlexDisplayItem(
                        id: "\(playlist.id)-\(track.id)",
                        title: track.title,
                        info: track.formattedDuration,
                        indentLevel: 1,
                        hasChildren: false,
                        type: .track(track)
                    ))
                }
            }
        }
    }
    
    private func buildSearchItems() {
        displayItems.removeAll()
        guard let results = searchResults else { return }
        
        if !results.artists.isEmpty {
            // Deduplicate artists by name, keeping the one with highest album count
            var artistsByName: [String: PlexArtist] = [:]
            for artist in results.artists {
                let normalizedName = artist.title.lowercased().trimmingCharacters(in: .whitespaces)
                if let existing = artistsByName[normalizedName] {
                    // Keep the one with more albums
                    if artist.albumCount > existing.albumCount {
                        artistsByName[normalizedName] = artist
                    }
                } else {
                    artistsByName[normalizedName] = artist
                }
            }
            let uniqueArtists = Array(artistsByName.values).sorted { $0.title.lowercased() < $1.title.lowercased() }
            
            displayItems.append(PlexDisplayItem(
                id: "header-artists",
                title: "Artists (\(uniqueArtists.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for artist in uniqueArtists {
                let normalizedName = artist.title.lowercased().trimmingCharacters(in: .whitespaces)
                let isExpanded = expandedArtistNames.contains(normalizedName)
                let info: String? = artist.albumCount > 0 
                    ? "\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums")" 
                    : nil
                displayItems.append(PlexDisplayItem(
                    id: artist.id,
                    title: artist.title,
                    info: info,
                    indentLevel: 1,
                    hasChildren: true,
                    type: .artist(artist)
                ))
                
                // Show albums if artist is expanded (use name-based lookup)
                if isExpanded, let albums = artistAlbumsByName[normalizedName] {
                    for album in albums {
                        let albumExpanded = expandedAlbums.contains(album.id)
                        displayItems.append(PlexDisplayItem(
                            id: album.id,
                            title: album.title,
                            info: album.year.map { String($0) },
                            indentLevel: 2,
                            hasChildren: true,
                            type: .album(album)
                        ))
                        
                        // Show tracks if album is expanded
                        if albumExpanded, let tracks = albumTracks[album.id] {
                            for track in tracks {
                                displayItems.append(PlexDisplayItem(
                                    id: track.id,
                                    title: track.title,
                                    info: track.formattedDuration,
                                    indentLevel: 3,
                                    hasChildren: false,
                                    type: .track(track)
                                ))
                            }
                        }
                    }
                }
            }
        }
        
        if !results.albums.isEmpty {
            // Deduplicate albums by ID
            var seenAlbumIds = Set<String>()
            var uniqueAlbums: [PlexAlbum] = []
            for album in results.albums {
                if !seenAlbumIds.contains(album.id) {
                    seenAlbumIds.insert(album.id)
                    uniqueAlbums.append(album)
                }
            }
            
            displayItems.append(PlexDisplayItem(
                id: "header-albums",
                title: "Albums (\(uniqueAlbums.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for album in uniqueAlbums {
                let isExpanded = expandedAlbums.contains(album.id)
                displayItems.append(PlexDisplayItem(
                    id: album.id,
                    title: "\(album.parentTitle ?? "") - \(album.title)",
                    info: album.year.map { String($0) },
                    indentLevel: 1,
                    hasChildren: true,
                    type: .album(album)
                ))
                
                // Show tracks if album is expanded
                if isExpanded, let tracks = albumTracks[album.id] {
                    for track in tracks {
                        displayItems.append(PlexDisplayItem(
                            id: track.id,
                            title: track.title,
                            info: track.formattedDuration,
                            indentLevel: 2,
                            hasChildren: false,
                            type: .track(track)
                        ))
                    }
                }
            }
        }
        
        if !results.tracks.isEmpty {
            // Deduplicate tracks by ID
            var seenTrackIds = Set<String>()
            var uniqueTracks: [PlexTrack] = []
            for track in results.tracks {
                if !seenTrackIds.contains(track.id) {
                    seenTrackIds.insert(track.id)
                    uniqueTracks.append(track)
                }
            }
            
            displayItems.append(PlexDisplayItem(
                id: "header-tracks",
                title: "Tracks (\(uniqueTracks.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for track in uniqueTracks {
                displayItems.append(PlexDisplayItem(
                    id: track.id,
                    title: "\(track.grandparentTitle ?? "") - \(track.title)",
                    info: track.formattedDuration,
                    indentLevel: 1,
                    hasChildren: false,
                    type: .track(track)
                ))
            }
        }
        
        if !results.movies.isEmpty {
            // Deduplicate movies by ID
            var seenMovieIds = Set<String>()
            var uniqueMovies: [PlexMovie] = []
            for movie in results.movies {
                if !seenMovieIds.contains(movie.id) {
                    seenMovieIds.insert(movie.id)
                    uniqueMovies.append(movie)
                }
            }
            
            displayItems.append(PlexDisplayItem(
                id: "header-movies",
                title: "Movies (\(uniqueMovies.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for movie in uniqueMovies {
                let info = [movie.year.map { String($0) }, movie.formattedDuration]
                    .compactMap { $0 }
                    .joined(separator: " • ")
                displayItems.append(PlexDisplayItem(
                    id: movie.id,
                    title: movie.title,
                    info: info.isEmpty ? nil : info,
                    indentLevel: 1,
                    hasChildren: false,
                    type: .movie(movie)
                ))
            }
        }
        
        if !results.shows.isEmpty {
            // Deduplicate shows by ID
            var seenShowIds = Set<String>()
            var uniqueShows: [PlexShow] = []
            for show in results.shows {
                if !seenShowIds.contains(show.id) {
                    seenShowIds.insert(show.id)
                    uniqueShows.append(show)
                }
            }
            
            displayItems.append(PlexDisplayItem(
                id: "header-shows",
                title: "TV Shows (\(uniqueShows.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for show in uniqueShows {
                let isExpanded = expandedShows.contains(show.id)
                displayItems.append(PlexDisplayItem(
                    id: show.id,
                    title: show.title,
                    info: "\(show.childCount) seasons",
                    indentLevel: 1,
                    hasChildren: true,
                    type: .show(show)
                ))
                
                // Show seasons if show is expanded
                if isExpanded, let seasons = showSeasons[show.id] {
                    for season in seasons {
                        let seasonExpanded = expandedSeasons.contains(season.id)
                        displayItems.append(PlexDisplayItem(
                            id: season.id,
                            title: season.title,
                            info: "\(season.leafCount) episodes",
                            indentLevel: 2,
                            hasChildren: true,
                            type: .season(season)
                        ))
                        
                        // Show episodes if season is expanded
                        if seasonExpanded, let episodes = seasonEpisodes[season.id] {
                            for episode in episodes {
                                displayItems.append(PlexDisplayItem(
                                    id: episode.id,
                                    title: "\(episode.episodeIdentifier) - \(episode.title)",
                                    info: episode.formattedDuration,
                                    indentLevel: 3,
                                    hasChildren: false,
                                    type: .episode(episode)
                                ))
                            }
                        }
                    }
                }
            }
        }
        
        if !results.episodes.isEmpty {
            // Deduplicate episodes by ID
            var seenEpisodeIds = Set<String>()
            var uniqueEpisodes: [PlexEpisode] = []
            for episode in results.episodes {
                if !seenEpisodeIds.contains(episode.id) {
                    seenEpisodeIds.insert(episode.id)
                    uniqueEpisodes.append(episode)
                }
            }
            
            displayItems.append(PlexDisplayItem(
                id: "header-episodes",
                title: "Episodes (\(uniqueEpisodes.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for episode in uniqueEpisodes {
                displayItems.append(PlexDisplayItem(
                    id: episode.id,
                    title: "\(episode.grandparentTitle ?? "") - \(episode.episodeIdentifier) - \(episode.title)",
                    info: episode.formattedDuration,
                    indentLevel: 1,
                    hasChildren: false,
                    type: .episode(episode)
                ))
            }
        }
    }
    
    // MARK: - Local Library Data Loading
    
    /// Load data from local MediaLibrary
    private func loadLocalData() {
        isLoading = false
        errorMessage = nil
        stopLoadingAnimation()
        
        let library = MediaLibrary.shared
        
        // Load cached data from MediaLibrary
        cachedLocalTracks = library.tracksSnapshot
        cachedLocalArtists = library.allArtists()
        cachedLocalAlbums = library.allAlbums()
        
        // Build display items for current mode
        switch browseMode {
        case .artists:
            buildLocalArtistItems()
        case .albums:
            buildLocalAlbumItems()
        case .tracks:
            buildLocalTrackItems()
        case .search:
            buildLocalSearchItems()
        case .plists:
            // TODO: Build local playlist items
            displayItems = []
        case .movies, .shows:
            // Video modes not supported for local content - show empty
            displayItems = []
        case .radio:
            // Radio is handled by loadRadioStations() in loadDataForCurrentMode()
            break
        }
        
        // Load artwork from browsed content
        loadLocalBrowseArtwork()
        
        needsDisplay = true
    }
    
    /// Load radio stations
    private func loadRadioStations() {
        isLoading = false
        errorMessage = nil
        stopLoadingAnimation()
        
        // Load stations from RadioManager
        cachedRadioStations = RadioManager.shared.stations
        
        // Build display items for radio stations
        buildRadioStationItems()
        
        needsDisplay = true
    }
    
    /// Build display items for radio stations
    private func buildRadioStationItems() {
        displayItems.removeAll()
        
        for station in cachedRadioStations {
            let item = PlexDisplayItem(
                id: station.id.uuidString,
                title: station.name,
                info: station.genre,
                indentLevel: 0,
                hasChildren: false,
                type: .radioStation(station)
            )
            displayItems.append(item)
        }
        
        // Sort by genre first, then by name within each genre
        displayItems.sort { a, b in
            let genreA = a.info ?? ""
            let genreB = b.info ?? ""
            if genreA != genreB {
                // Empty genre goes last
                if genreA.isEmpty { return false }
                if genreB.isEmpty { return true }
                return genreA.localizedCaseInsensitiveCompare(genreB) == .orderedAscending
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
    
    /// Load Plex Radio stations (dynamic playlists from Plex library)
    private func loadPlexRadioStations() {
        isLoading = true
        errorMessage = nil
        startLoadingAnimation()
        needsDisplay = true
        
        // Fetch genres async and build items
        Task { @MainActor in
            let genres = await PlexManager.shared.getGenres()
            buildPlexRadioStationItems(genres: genres)
            isLoading = false
            stopLoadingAnimation()
            needsDisplay = true
        }
    }
    
    /// Build display items for Plex Radio stations
    private func buildPlexRadioStationItems(genres: [String]) {
        displayItems.removeAll()
        
        // Library Radio
        displayItems.append(PlexDisplayItem(
            id: "plex-radio-library",
            title: "Library Radio",
            info: "Library",
            indentLevel: 0,
            hasChildren: false,
            type: .plexRadioStation(.libraryRadio)
        ))
        displayItems.append(PlexDisplayItem(
            id: "plex-radio-library-sonic",
            title: "Library Radio (Sonic)",
            info: "Library",
            indentLevel: 0,
            hasChildren: false,
            type: .plexRadioStation(.libraryRadioSonic)
        ))
        
        // Popularity - Only the Hits
        displayItems.append(PlexDisplayItem(
            id: "plex-radio-hits",
            title: "Only the Hits",
            info: "Popularity",
            indentLevel: 0,
            hasChildren: false,
            type: .plexRadioStation(.hitsRadio)
        ))
        displayItems.append(PlexDisplayItem(
            id: "plex-radio-hits-sonic",
            title: "Only the Hits (Sonic)",
            info: "Popularity",
            indentLevel: 0,
            hasChildren: false,
            type: .plexRadioStation(.hitsRadioSonic)
        ))
        
        // Popularity - Deep Cuts
        displayItems.append(PlexDisplayItem(
            id: "plex-radio-deepcuts",
            title: "Deep Cuts",
            info: "Popularity",
            indentLevel: 0,
            hasChildren: false,
            type: .plexRadioStation(.deepCutsRadio)
        ))
        displayItems.append(PlexDisplayItem(
            id: "plex-radio-deepcuts-sonic",
            title: "Deep Cuts (Sonic)",
            info: "Popularity",
            indentLevel: 0,
            hasChildren: false,
            type: .plexRadioStation(.deepCutsRadioSonic)
        ))
        
        // Rating stations
        for station in RadioConfig.ratingStations {
            displayItems.append(PlexDisplayItem(
                id: "plex-radio-rating-\(station.minRating)",
                title: "\(station.name) Radio",
                info: "My Ratings",
                indentLevel: 0,
                hasChildren: false,
                type: .plexRadioStation(.ratingRadio(minRating: station.minRating, name: station.name))
            ))
            displayItems.append(PlexDisplayItem(
                id: "plex-radio-rating-\(station.minRating)-sonic",
                title: "\(station.name) Radio (Sonic)",
                info: "My Ratings",
                indentLevel: 0,
                hasChildren: false,
                type: .plexRadioStation(.ratingRadioSonic(minRating: station.minRating, name: station.name))
            ))
        }
        
        // Genre stations (dynamically loaded)
        for genre in genres {
            displayItems.append(PlexDisplayItem(
                id: "plex-radio-genre-\(genre)",
                title: "\(genre) Radio",
                info: "Genre",
                indentLevel: 0,
                hasChildren: false,
                type: .plexRadioStation(.genreRadio(genre))
            ))
            displayItems.append(PlexDisplayItem(
                id: "plex-radio-genre-\(genre)-sonic",
                title: "\(genre) Radio (Sonic)",
                info: "Genre",
                indentLevel: 0,
                hasChildren: false,
                type: .plexRadioStation(.genreRadioSonic(genre))
            ))
        }
        
        // Decade stations
        for decade in RadioConfig.decades {
            displayItems.append(PlexDisplayItem(
                id: "plex-radio-decade-\(decade.name)",
                title: "\(decade.name) Radio",
                info: "Decade",
                indentLevel: 0,
                hasChildren: false,
                type: .plexRadioStation(.decadeRadio(start: decade.start, end: decade.end, name: decade.name))
            ))
            displayItems.append(PlexDisplayItem(
                id: "plex-radio-decade-\(decade.name)-sonic",
                title: "\(decade.name) Radio (Sonic)",
                info: "Decade",
                indentLevel: 0,
                hasChildren: false,
                type: .plexRadioStation(.decadeRadioSonic(start: decade.start, end: decade.end, name: decade.name))
            ))
        }
    }
    
    @objc private func radioStationsDidChange() {
        // Only reload if we're showing radio content
        guard case .radio = currentSource else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.loadRadioStations()
            self?.needsDisplay = true
        }
    }
    
    /// Load Subsonic data for the current mode
    private func loadSubsonicData(serverId: String) {
        isLoading = true
        errorMessage = nil
        startLoadingAnimation()
        needsDisplay = true
        
        let manager = SubsonicManager.shared
        
        // Check if we need to connect first
        if manager.currentServer?.id != serverId {
            if let server = manager.servers.first(where: { $0.id == serverId }) {
                Task { @MainActor in
                    do {
                        try await manager.connect(to: server)
                        loadSubsonicDataForCurrentMode()
                    } catch {
                        isLoading = false
                        stopLoadingAnimation()
                        errorMessage = error.localizedDescription
                        needsDisplay = true
                    }
                }
            } else {
                isLoading = false
                stopLoadingAnimation()
                errorMessage = "Server not found"
                needsDisplay = true
            }
            return
        }
        
        // Already connected to this server
        loadSubsonicDataForCurrentMode()
    }
    
    /// Load Subsonic content for the current browse mode
    private func loadSubsonicDataForCurrentMode() {
        let manager = SubsonicManager.shared
        
        // Cancel any pending load task
        subsonicLoadTask?.cancel()
        
        subsonicLoadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            do {
                // Check for cancellation before each major operation
                try Task.checkCancellation()
                
                switch browseMode {
                case .artists:
                    if cachedSubsonicArtists.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedArtists.isEmpty {
                            cachedSubsonicArtists = manager.cachedArtists
                            cachedSubsonicAlbums = manager.cachedAlbums
                        } else {
                            try Task.checkCancellation()
                            cachedSubsonicArtists = try await manager.fetchArtists()
                            try Task.checkCancellation()
                            cachedSubsonicAlbums = try await manager.fetchAlbums()
                        }
                    }
                    try Task.checkCancellation()
                    buildSubsonicArtistItems()
                    
                case .albums:
                    if cachedSubsonicAlbums.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedAlbums.isEmpty {
                            cachedSubsonicAlbums = manager.cachedAlbums
                        } else {
                            try Task.checkCancellation()
                            cachedSubsonicAlbums = try await manager.fetchAlbums()
                        }
                    }
                    try Task.checkCancellation()
                    buildSubsonicAlbumItems()
                    
                case .tracks:
                    // For Subsonic, show all albums' tracks - not typically used
                    buildSubsonicAlbumItems()
                    
                case .search:
                    // TODO: Implement Subsonic search
                    displayItems = []
                    
                case .plists:
                    NSLog("PlexBrowserView: Loading Subsonic playlists...")
                    if cachedSubsonicPlaylists.isEmpty {
                        if manager.isContentPreloaded && !manager.cachedPlaylists.isEmpty {
                            cachedSubsonicPlaylists = manager.cachedPlaylists
                        } else {
                            try Task.checkCancellation()
                            cachedSubsonicPlaylists = try await manager.fetchPlaylists()
                        }
                    }
                    try Task.checkCancellation()
                    buildSubsonicPlaylistItems()
                    NSLog("PlexBrowserView: Built %d playlist items", displayItems.count)
                    
                case .movies, .shows:
                    // Video modes not supported for Subsonic
                    displayItems = []
                    
                case .radio:
                    // Radio is handled by loadRadioStations() in loadDataForCurrentMode()
                    break
                }
                
                isLoading = false
                stopLoadingAnimation()
                needsDisplay = true
            } catch is CancellationError {
                // Task was cancelled, ignore
            } catch {
                isLoading = false
                stopLoadingAnimation()
                errorMessage = error.localizedDescription
                needsDisplay = true
            }
        }
    }
    
    /// Build display items for Subsonic artists
    private func buildSubsonicArtistItems() {
        displayItems.removeAll()
        
        let sortedArtists = cachedSubsonicArtists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        for artist in sortedArtists {
            let albumCount = artist.albumCount ?? 0
            let info = albumCount > 0 ? "\(albumCount) album\(albumCount == 1 ? "" : "s")" : nil
            let isExpanded = expandedSubsonicArtists.contains(artist.id)
            
            displayItems.append(PlexDisplayItem(
                id: artist.id,
                title: artist.name,
                info: info,
                indentLevel: 0,
                hasChildren: true,
                type: .subsonicArtist(artist)
            ))
            
            if isExpanded {
                // Show albums for this artist
                if let albums = subsonicArtistAlbums[artist.id] {
                    for album in albums {
                        let albumExpanded = expandedSubsonicAlbums.contains(album.id)
                        displayItems.append(PlexDisplayItem(
                            id: album.id,
                            title: album.name,
                            info: album.year.map { String($0) },
                            indentLevel: 1,
                            hasChildren: true,
                            type: .subsonicAlbum(album)
                        ))
                        
                        if albumExpanded, let songs = subsonicAlbumSongs[album.id] {
                            for song in songs {
                                displayItems.append(PlexDisplayItem(
                                    id: song.id,
                                    title: song.title,
                                    info: formatDuration(song.duration),
                                    indentLevel: 2,
                                    hasChildren: false,
                                    type: .subsonicTrack(song)
                                ))
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Build display items for Subsonic albums
    private func buildSubsonicAlbumItems() {
        displayItems = cachedSubsonicAlbums
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { album in
                PlexDisplayItem(
                    id: album.id,
                    title: "\(album.artist ?? "Unknown") - \(album.name)",
                    info: album.year.map { String($0) },
                    indentLevel: 0,
                    hasChildren: true,
                    type: .subsonicAlbum(album)
                )
            }
    }
    
    /// Build display items for Subsonic playlists
    private func buildSubsonicPlaylistItems() {
        displayItems.removeAll()
        
        let sortedPlaylists = cachedSubsonicPlaylists.sorted { 
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending 
        }
        
        for playlist in sortedPlaylists {
            let isExpanded = expandedSubsonicPlaylists.contains(playlist.id)
            let songCount = playlist.songCount
            let info = "\(songCount) \(songCount == 1 ? "track" : "tracks")"
            
            displayItems.append(PlexDisplayItem(
                id: playlist.id,
                title: playlist.name,
                info: info,
                indentLevel: 0,
                hasChildren: songCount > 0,
                type: .subsonicPlaylist(playlist)
            ))
            
            // Show tracks if expanded
            if isExpanded, let tracks = subsonicPlaylistTracks[playlist.id] {
                for track in tracks {
                    displayItems.append(PlexDisplayItem(
                        id: "\(playlist.id)-\(track.id)",
                        title: track.title,
                        info: formatDuration(track.duration),
                        indentLevel: 1,
                        hasChildren: false,
                        type: .subsonicTrack(track)
                    ))
                }
            }
        }
    }
    
    /// Format duration in seconds to mm:ss
    private func formatDuration(_ seconds: Int?) -> String? {
        guard let seconds = seconds else { return nil }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    /// Load artwork from browsed local content
    private func loadLocalBrowseArtwork() {
        guard case .local = currentSource else { return }
        guard WindowManager.shared.showBrowserArtworkBackground else { return }
        
        // If a track is playing, use its artwork
        if let currentTrack = WindowManager.shared.audioEngine.currentTrack {
            loadArtwork(for: currentTrack)
            return
        }
        
        // Capture current state for async task
        let items = displayItems
        let localTracks = cachedLocalTracks
        
        // Otherwise, try to find artwork from the current browse context
        artworkLoadTask?.cancel()
        artworkLoadTask = Task { [weak self] in
            guard let self = self else { return }
            
            var image: NSImage?
            
            // Try to get artwork from the first track we can find
            for item in items {
                switch item.type {
                case .localTrack(let track):
                    // Found a local track - use its URL
                    image = await self.loadLocalArtwork(url: track.url)
                    break
                case .localAlbum(let album):
                    // Found a local album - find first track from this album
                    let albumTracks = localTracks.filter { $0.album == album.name }
                    if let track = albumTracks.first {
                        image = await self.loadLocalArtwork(url: track.url)
                    }
                    break
                case .localArtist(let artist):
                    // Found a local artist - find first track from this artist
                    let artistTracks = localTracks.filter { $0.artist == artist.name }
                    if let track = artistTracks.first {
                        image = await self.loadLocalArtwork(url: track.url)
                    }
                    break
                default:
                    continue
                }
                if image != nil { break }
            }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if image != nil {
                    self.currentArtwork = image
                    self.needsDisplay = true
                }
            }
        }
    }
    
    private func buildLocalArtistItems() {
        displayItems.removeAll()
        
        // Sort artists
        let sortedArtists = sortArtists(cachedLocalArtists)
        
        for artist in sortedArtists {
            let isExpanded = expandedLocalArtists.contains(artist.id)
            let albumCount = artist.albums.count
            let info = "\(albumCount) \(albumCount == 1 ? "album" : "albums")"
            
            displayItems.append(PlexDisplayItem(
                id: "local-artist-\(artist.id)",
                title: artist.name,
                info: info,
                indentLevel: 0,
                hasChildren: true,
                type: .localArtist(artist)
            ))
            
            if isExpanded {
                // Sort albums within artist
                let sortedAlbums = sortAlbums(artist.albums)
                for album in sortedAlbums {
                    let albumId = album.id
                    let albumExpanded = expandedLocalAlbums.contains(albumId)
                    
                    displayItems.append(PlexDisplayItem(
                        id: "local-album-\(albumId)",
                        title: album.name,
                        info: album.year.map { String($0) },
                        indentLevel: 1,
                        hasChildren: true,
                        type: .localAlbum(album)
                    ))
                    
                    if albumExpanded {
                        // Tracks within album sorted by track number
                        let sortedTracks = album.tracks.sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
                        for track in sortedTracks {
                            displayItems.append(PlexDisplayItem(
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
        let sortedAlbums = sortAlbums(cachedLocalAlbums)
        displayItems = sortedAlbums.map { album in
            PlexDisplayItem(
                id: "local-album-\(album.id)",
                title: album.displayName,
                info: "\(album.tracks.count) tracks",
                indentLevel: 0,
                hasChildren: false,
                type: .localAlbum(album)
            )
        }
    }
    
    private func buildLocalTrackItems() {
        let sortedTracks = sortTracks(cachedLocalTracks)
        displayItems = sortedTracks.map { track in
            PlexDisplayItem(
                id: track.id.uuidString,
                title: track.displayTitle,
                info: track.formattedDuration,
                indentLevel: 0,
                hasChildren: false,
                type: .localTrack(track)
            )
        }
    }
    
    // MARK: - Sorting Helpers
    
    private func sortArtists(_ artists: [Artist]) -> [Artist] {
        switch currentSort {
        case .nameAsc:
            return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .dateAddedDesc, .dateAddedAsc:
            // Artists don't have date added, fall back to name
            return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .yearDesc, .yearAsc:
            // Artists don't have year, fall back to name
            return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    private func sortAlbums(_ albums: [Album]) -> [Album] {
        switch currentSort {
        case .nameAsc:
            return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .dateAddedDesc, .dateAddedAsc:
            // Albums don't have date added, fall back to name
            return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .yearDesc:
            return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc:
            return albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }
    
    private func sortTracks(_ tracks: [LibraryTrack]) -> [LibraryTrack] {
        switch currentSort {
        case .nameAsc:
            return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc:
            return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateAddedDesc:
            return tracks.sorted { $0.dateAdded > $1.dateAdded }
        case .dateAddedAsc:
            return tracks.sorted { $0.dateAdded < $1.dateAdded }
        case .yearDesc:
            return tracks.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc:
            return tracks.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }
    
    // Plex sorting helpers
    
    private func sortPlexArtists(_ artists: [PlexArtist]) -> [PlexArtist] {
        switch currentSort {
        case .nameAsc:
            return artists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc:
            return artists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateAddedDesc:
            return artists.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc:
            return artists.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        case .yearDesc, .yearAsc:
            // Artists don't have year, fall back to name
            return artists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    
    private func sortPlexAlbums(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        switch currentSort {
        case .nameAsc:
            return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc:
            return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateAddedDesc:
            return albums.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc:
            return albums.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        case .yearDesc:
            return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc:
            return albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }
    
    private func sortPlexTracks(_ tracks: [PlexTrack]) -> [PlexTrack] {
        switch currentSort {
        case .nameAsc:
            return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nameDesc:
            return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateAddedDesc:
            return tracks.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .dateAddedAsc:
            return tracks.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        case .yearDesc, .yearAsc:
            // Tracks don't have year directly, fall back to name
            return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    
    private func buildLocalSearchItems() {
        displayItems.removeAll()
        guard !searchQuery.isEmpty else { return }
        
        let query = searchQuery.lowercased()
        let library = MediaLibrary.shared
        
        // Search artists
        let matchingArtists = cachedLocalArtists.filter { $0.name.lowercased().contains(query) }
        if !matchingArtists.isEmpty {
            displayItems.append(PlexDisplayItem(
                id: "header-local-artists",
                title: "Artists (\(matchingArtists.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for artist in matchingArtists {
                displayItems.append(PlexDisplayItem(
                    id: "local-artist-\(artist.id)",
                    title: artist.name,
                    info: "\(artist.albums.count) albums",
                    indentLevel: 1,
                    hasChildren: true,
                    type: .localArtist(artist)
                ))
            }
        }
        
        // Search albums
        let matchingAlbums = cachedLocalAlbums.filter {
            $0.name.lowercased().contains(query) ||
            ($0.artist?.lowercased().contains(query) ?? false)
        }
        if !matchingAlbums.isEmpty {
            displayItems.append(PlexDisplayItem(
                id: "header-local-albums",
                title: "Albums (\(matchingAlbums.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for album in matchingAlbums {
                displayItems.append(PlexDisplayItem(
                    id: "local-album-\(album.id)",
                    title: album.displayName,
                    info: "\(album.tracks.count) tracks",
                    indentLevel: 1,
                    hasChildren: false,
                    type: .localAlbum(album)
                ))
            }
        }
        
        // Search tracks
        let matchingTracks = library.search(query: searchQuery)
        if !matchingTracks.isEmpty {
            displayItems.append(PlexDisplayItem(
                id: "header-local-tracks",
                title: "Tracks (\(matchingTracks.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for track in matchingTracks {
                displayItems.append(PlexDisplayItem(
                    id: track.id.uuidString,
                    title: track.displayTitle,
                    info: track.formattedDuration,
                    indentLevel: 1,
                    hasChildren: false,
                    type: .localTrack(track)
                ))
            }
        }
    }
    
    /// Rebuild display items for the current browse mode
    /// This ensures expand/collapse works correctly regardless of which tab we're on
    private func rebuildCurrentModeItems() {
        // Reset horizontal scroll when items change
        horizontalScrollOffset = 0
        
        // Radio source - only radio tab has content
        if case .radio = currentSource {
            if browseMode == .radio {
                buildRadioStationItems()
            } else {
                displayItems = []
            }
            needsDisplay = true
            return
        }
        
        // Non-radio sources: radio tab shows Plex Radio options (for Plex) or empty
        if browseMode == .radio {
            if case .plex = currentSource, PlexManager.shared.isLinked {
                // Plex Radio items are built async by loadPlexRadioStations()
                // Don't clear displayItems here - they're already populated
                needsDisplay = true
            } else {
                displayItems = []
                needsDisplay = true
            }
            return
        }
        
        // Check source type
        if case .local = currentSource {
            switch browseMode {
            case .artists:
                buildLocalArtistItems()
            case .albums:
                buildLocalAlbumItems()
            case .tracks:
                buildLocalTrackItems()
            case .search:
                buildLocalSearchItems()
            case .plists:
                // TODO: Build local playlist items
                displayItems = []
            case .movies, .shows:
                displayItems = []
            case .radio:
                // Handled above
                break
            }
        } else if case .subsonic = currentSource {
            switch browseMode {
            case .artists:
                buildSubsonicArtistItems()
            case .albums:
                buildSubsonicAlbumItems()
            case .tracks:
                buildSubsonicAlbumItems() // Show albums for tracks mode
            case .search:
                displayItems = [] // TODO: Implement Subsonic search
            case .plists:
                buildSubsonicPlaylistItems()
            case .movies, .shows:
                displayItems = []
            case .radio:
                // Handled above
                break
            }
        } else {
            switch browseMode {
            case .artists:
                buildArtistItems()
            case .albums:
                buildAlbumItems()
            case .tracks:
                buildTrackItems()
            case .movies:
                buildMovieItems()
            case .shows:
                buildShowItems()
            case .plists:
                buildPlexPlaylistItems()
            case .search:
                buildSearchItems()
            case .radio:
                // Handled above
                break
            }
        }
        
        // Apply column sort if set
        if columnSortId != nil {
            applyColumnSort()
        }
        
        // Ensure view updates
        needsDisplay = true
    }
    
    private func isExpanded(_ item: PlexDisplayItem) -> Bool {
        switch item.type {
        case .artist(let artist):
            // In search mode, use name-based tracking since IDs can vary after deduplication
            if browseMode == .search {
                let normalizedName = artist.title.lowercased().trimmingCharacters(in: .whitespaces)
                return expandedArtistNames.contains(normalizedName)
            }
            return expandedArtists.contains(item.id)
        case .album:
            return expandedAlbums.contains(item.id)
        case .show:
            return expandedShows.contains(item.id)
        case .season:
            return expandedSeasons.contains(item.id)
        case .localArtist(let artist):
            return expandedLocalArtists.contains(artist.id)
        case .localAlbum(let album):
            return expandedLocalAlbums.contains(album.id)
        case .subsonicArtist(let artist):
            return expandedSubsonicArtists.contains(artist.id)
        case .subsonicAlbum(let album):
            return expandedSubsonicAlbums.contains(album.id)
        case .subsonicPlaylist(let playlist):
            return expandedSubsonicPlaylists.contains(playlist.id)
        case .plexPlaylist(let playlist):
            return expandedPlexPlaylists.contains(playlist.id)
        default:
            return false
        }
    }
    
    private func toggleExpand(_ item: PlexDisplayItem) {
        switch item.type {
        case .artist(let artist):
            let normalizedName = artist.title.lowercased().trimmingCharacters(in: .whitespaces)
            
            // In search mode, track by name since IDs can vary after deduplication
            if browseMode == .search {
                if expandedArtistNames.contains(normalizedName) {
                    expandedArtistNames.remove(normalizedName)
                } else {
                    expandedArtistNames.insert(normalizedName)
                    if artistAlbumsByName[normalizedName] == nil {
                        Task { @MainActor in
                            do {
                                let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                                artistAlbumsByName[normalizedName] = albums
                                rebuildCurrentModeItems()
                                needsDisplay = true
                            } catch {
                                print("Failed to load albums: \(error)")
                            }
                        }
                        return
                    }
                }
            } else {
                // Normal mode - track by ID
                if expandedArtists.contains(artist.id) {
                    expandedArtists.remove(artist.id)
                } else {
                    expandedArtists.insert(artist.id)
                    if artistAlbums[artist.id] == nil {
                        Task { @MainActor in
                            do {
                                let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                                artistAlbums[artist.id] = albums
                                rebuildCurrentModeItems()
                                needsDisplay = true
                            } catch {
                                print("Failed to load albums: \(error)")
                            }
                        }
                        return
                    }
                }
            }
            rebuildCurrentModeItems()
            
        case .album(let album):
            if expandedAlbums.contains(album.id) {
                expandedAlbums.remove(album.id)
            } else {
                expandedAlbums.insert(album.id)
                if albumTracks[album.id] == nil {
                    Task { @MainActor in
                        do {
                            let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                            albumTracks[album.id] = tracks
                            rebuildCurrentModeItems()
                            needsDisplay = true
                        } catch {
                            print("Failed to load tracks: \(error)")
                        }
                    }
                    return
                }
            }
            rebuildCurrentModeItems()
            
        case .show(let show):
            if expandedShows.contains(show.id) {
                expandedShows.remove(show.id)
            } else {
                expandedShows.insert(show.id)
                if showSeasons[show.id] == nil {
                    Task { @MainActor in
                        do {
                            let seasons = try await PlexManager.shared.fetchSeasons(forShow: show)
                            showSeasons[show.id] = seasons
                            rebuildCurrentModeItems()
                            needsDisplay = true
                        } catch {
                            print("Failed to load seasons: \(error)")
                        }
                    }
                    return
                }
            }
            rebuildCurrentModeItems()
            
        case .season(let season):
            if expandedSeasons.contains(season.id) {
                expandedSeasons.remove(season.id)
            } else {
                expandedSeasons.insert(season.id)
                if seasonEpisodes[season.id] == nil {
                    Task { @MainActor in
                        do {
                            let episodes = try await PlexManager.shared.fetchEpisodes(forSeason: season)
                            seasonEpisodes[season.id] = episodes
                            rebuildCurrentModeItems()
                            needsDisplay = true
                        } catch {
                            print("Failed to load episodes: \(error)")
                        }
                    }
                    return
                }
            }
            rebuildCurrentModeItems()
            
        case .localArtist(let artist):
            if expandedLocalArtists.contains(artist.id) {
                expandedLocalArtists.remove(artist.id)
            } else {
                expandedLocalArtists.insert(artist.id)
            }
            rebuildCurrentModeItems()
            
        case .localAlbum(let album):
            if expandedLocalAlbums.contains(album.id) {
                expandedLocalAlbums.remove(album.id)
            } else {
                expandedLocalAlbums.insert(album.id)
            }
            rebuildCurrentModeItems()
            
        case .subsonicArtist(let artist):
            if expandedSubsonicArtists.contains(artist.id) {
                expandedSubsonicArtists.remove(artist.id)
            } else {
                expandedSubsonicArtists.insert(artist.id)
                // Load albums for this artist if not already loaded
                if subsonicArtistAlbums[artist.id] == nil {
                    let artistId = artist.id
                    subsonicExpandTask?.cancel()
                    subsonicExpandTask = Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do {
                            try Task.checkCancellation()
                            let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: artist)
                            try Task.checkCancellation()
                            subsonicArtistAlbums[artistId] = albums
                            rebuildCurrentModeItems()
                            needsDisplay = true
                        } catch is CancellationError {
                            // Cancelled, ignore
                        } catch {
                            NSLog("Failed to load albums for artist: \(error)")
                        }
                    }
                    return
                }
            }
            rebuildCurrentModeItems()
            
        case .subsonicAlbum(let album):
            if expandedSubsonicAlbums.contains(album.id) {
                expandedSubsonicAlbums.remove(album.id)
            } else {
                expandedSubsonicAlbums.insert(album.id)
                // Load songs for this album if not already loaded
                if subsonicAlbumSongs[album.id] == nil {
                    let albumId = album.id
                    subsonicExpandTask?.cancel()
                    subsonicExpandTask = Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do {
                            try Task.checkCancellation()
                            let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                            try Task.checkCancellation()
                            subsonicAlbumSongs[albumId] = songs
                            rebuildCurrentModeItems()
                            needsDisplay = true
                        } catch is CancellationError {
                            // Cancelled, ignore
                        } catch {
                            NSLog("Failed to load songs for album: \(error)")
                        }
                    }
                    return
                }
            }
            rebuildCurrentModeItems()
            
        case .subsonicPlaylist(let playlist):
            if expandedSubsonicPlaylists.contains(playlist.id) {
                expandedSubsonicPlaylists.remove(playlist.id)
            } else {
                expandedSubsonicPlaylists.insert(playlist.id)
                // Load tracks for this playlist if not already loaded
                if subsonicPlaylistTracks[playlist.id] == nil {
                    let playlistId = playlist.id
                    subsonicExpandTask?.cancel()
                    subsonicExpandTask = Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do {
                            try Task.checkCancellation()
                            let (_, tracks) = try await SubsonicManager.shared.serverClient?.fetchPlaylist(id: playlistId) ?? (playlist, [])
                            try Task.checkCancellation()
                            subsonicPlaylistTracks[playlistId] = tracks
                            rebuildCurrentModeItems()
                            needsDisplay = true
                        } catch is CancellationError {
                            // Cancelled, ignore
                        } catch {
                            NSLog("Failed to load tracks for playlist: \(error)")
                        }
                    }
                    return
                }
            }
            rebuildCurrentModeItems()
            
        case .plexPlaylist(let playlist):
            if expandedPlexPlaylists.contains(playlist.id) {
                expandedPlexPlaylists.remove(playlist.id)
            } else {
                expandedPlexPlaylists.insert(playlist.id)
                // Load tracks for this playlist if not already loaded
                if plexPlaylistTracks[playlist.id] == nil {
                    let playlistId = playlist.id
                    let smartContent = playlist.smart ? playlist.content : nil
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        do {
                            let tracks = try await PlexManager.shared.fetchPlaylistTracks(
                                playlistID: playlistId,
                                smartContent: smartContent
                            )
                            plexPlaylistTracks[playlistId] = tracks
                            rebuildCurrentModeItems()
                            needsDisplay = true
                        } catch {
                            NSLog("Failed to load tracks for Plex playlist: \(error)")
                        }
                    }
                    return
                }
            }
            rebuildCurrentModeItems()
            
        default:
            break
        }
        
        needsDisplay = true
    }
    
    // MARK: - Playback
    
    private func playTrack(_ item: PlexDisplayItem) {
        guard case .track(let track) = item.type else {
            NSLog("playTrack: item is not a track")
            return
        }
        
        NSLog("playTrack: %@", track.title)
        
        if let convertedTrack = PlexManager.shared.convertToTrack(track) {
            NSLog("  streamURL: %@", convertedTrack.url.absoluteString)
            WindowManager.shared.audioEngine.loadTracks([convertedTrack])
            NSLog("  Called loadTracks()")
        } else {
            NSLog("  ERROR: Failed to convert track - streamURL is nil")
        }
    }
    
    private func playAlbum(_ album: PlexAlbum) {
        Task { @MainActor in
            do {
                let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                let convertedTracks = PlexManager.shared.convertToTracks(tracks)
                NSLog("Playing album %@ with %d tracks", album.title, convertedTracks.count)
                WindowManager.shared.audioEngine.loadTracks(convertedTracks)
            } catch {
                NSLog("Failed to play album: %@", error.localizedDescription)
            }
        }
    }
    
    private func playArtist(_ artist: PlexArtist) {
        Task { @MainActor in
            do {
                let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [PlexTrack] = []
                for album in albums {
                    let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                    allTracks.append(contentsOf: tracks)
                }
                let convertedTracks = PlexManager.shared.convertToTracks(allTracks)
                NSLog("Playing artist %@ with %d tracks", artist.title, convertedTracks.count)
                WindowManager.shared.audioEngine.loadTracks(convertedTracks)
            } catch {
                NSLog("Failed to play artist: %@", error.localizedDescription)
            }
        }
    }
    
    private func playMovie(_ movie: PlexMovie) {
        NSLog("Playing movie: %@", movie.title)
        WindowManager.shared.playMovie(movie)
    }
    
    private func playEpisode(_ episode: PlexEpisode) {
        NSLog("Playing episode: %@ - %@", episode.episodeIdentifier, episode.title)
        WindowManager.shared.playEpisode(episode)
    }
    
    private func playPlexPlaylist(_ playlist: PlexPlaylist) {
        // Show loading screen while fetching playlist tracks
        isLoading = true
        errorMessage = nil
        startLoadingAnimation()
        needsDisplay = true
        
        Task { @MainActor in
            do {
                NSLog("playPlexPlaylist: Starting for '%@' (id=%@, key=%@, smart=%d, content=%@)", 
                      playlist.title, playlist.id, playlist.key, playlist.smart ? 1 : 0, playlist.content ?? "nil")
                // Pass the content URI for smart playlists as fallback
                let tracks = try await PlexManager.shared.fetchPlaylistTracks(
                    playlistID: playlist.id, 
                    smartContent: playlist.smart ? playlist.content : nil
                )
                let convertedTracks = PlexManager.shared.convertToTracks(tracks)
                NSLog("Playing Plex playlist %@ with %d tracks (fetched %d)", playlist.title, convertedTracks.count, tracks.count)
                
                isLoading = false
                stopLoadingAnimation()
                needsDisplay = true
                
                WindowManager.shared.audioEngine.loadTracks(convertedTracks)
            } catch {
                NSLog("Failed to play Plex playlist '%@' (id=%@): %@", playlist.title, playlist.id, error.localizedDescription)
                isLoading = false
                stopLoadingAnimation()
                errorMessage = "Failed to load playlist: \(error.localizedDescription)"
                needsDisplay = true
            }
        }
    }
    
    private func handleDoubleClick(on item: PlexDisplayItem) {
        switch item.type {
        case .track:
            playTrack(item)
            
        case .album(let album):
            playAlbum(album)
            
        case .artist:
            toggleExpand(item)
            
        case .movie(let movie):
            playMovie(movie)
            
        case .show:
            toggleExpand(item)
            
        case .season:
            toggleExpand(item)
            
        case .episode(let episode):
            playEpisode(episode)
            
        case .header:
            break
            
        case .localTrack(let track):
            playLocalTrack(track)
            
        case .localAlbum(let album):
            playLocalAlbum(album)
            
        case .localArtist:
            toggleExpand(item)
            
        case .subsonicTrack(let song):
            playSubsonicSong(song)
            
        case .subsonicAlbum(let album):
            playSubsonicAlbum(album)
            
        case .subsonicArtist:
            toggleExpand(item)
            
        case .subsonicPlaylist(let playlist):
            playSubsonicPlaylist(playlist)
            
        case .plexPlaylist(let playlist):
            playPlexPlaylist(playlist)
            
        case .radioStation(let station):
            playRadioStation(station)
            
        case .plexRadioStation(let radioType):
            playPlexRadioStation(radioType)
        }
    }
    
    // MARK: - Radio Playback
    
    private func playRadioStation(_ station: RadioStation) {
        NSLog("playRadioStation: %@", station.name)
        RadioManager.shared.play(station: station)
    }
    
    /// Play a Plex Radio station (dynamic playlist from Plex library)
    private func playPlexRadioStation(_ radioType: PlexRadioType) {
        NSLog("playPlexRadioStation: %@", radioType.displayName)
        
        Task { @MainActor in
            var tracks: [Track] = []
            
            switch radioType {
            case .libraryRadio:
                tracks = await PlexManager.shared.createLibraryRadio()
            case .libraryRadioSonic:
                tracks = await PlexManager.shared.createLibraryRadioSonic()
            case .hitsRadio:
                tracks = await PlexManager.shared.createHitsRadio()
            case .hitsRadioSonic:
                tracks = await PlexManager.shared.createHitsRadioSonic()
            case .deepCutsRadio:
                tracks = await PlexManager.shared.createDeepCutsRadio()
            case .deepCutsRadioSonic:
                tracks = await PlexManager.shared.createDeepCutsRadioSonic()
            case .genreRadio(let genre):
                tracks = await PlexManager.shared.createGenreRadio(genre: genre)
            case .genreRadioSonic(let genre):
                tracks = await PlexManager.shared.createGenreRadioSonic(genre: genre)
            case .decadeRadio(let start, let end, _):
                tracks = await PlexManager.shared.createDecadeRadio(startYear: start, endYear: end)
            case .decadeRadioSonic(let start, let end, _):
                tracks = await PlexManager.shared.createDecadeRadioSonic(startYear: start, endYear: end)
            case .ratingRadio(let minRating, _):
                tracks = await PlexManager.shared.createRatingRadio(minRating: minRating)
            case .ratingRadioSonic(let minRating, _):
                tracks = await PlexManager.shared.createRatingRadioSonic(minRating: minRating)
            }
            
            if !tracks.isEmpty {
                let audioEngine = WindowManager.shared.audioEngine
                audioEngine.clearPlaylist()
                audioEngine.loadTracks(tracks)
                audioEngine.play()
                NSLog("%@ started with %d tracks", radioType.displayName, tracks.count)
            } else {
                NSLog("%@: No tracks found", radioType.displayName)
            }
        }
    }
    
    // MARK: - Subsonic Playback
    
    private func playSubsonicSong(_ song: SubsonicSong) {
        NSLog("playSubsonicSong: %@", song.title)
        if let track = SubsonicManager.shared.convertToTrack(song) {
            WindowManager.shared.audioEngine.loadTracks([track])
        }
    }
    
    private func playSubsonicAlbum(_ album: SubsonicAlbum) {
        Task { @MainActor in
            do {
                let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                let tracks = songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                NSLog("Playing subsonic album %@ with %d tracks", album.name, tracks.count)
                WindowManager.shared.audioEngine.loadTracks(tracks)
            } catch {
                NSLog("Failed to play subsonic album: %@", error.localizedDescription)
            }
        }
    }
    
    private func playSubsonicArtist(_ artist: SubsonicArtist) {
        Task { @MainActor in
            do {
                let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [Track] = []
                for album in albums {
                    let songs = try await SubsonicManager.shared.fetchSongs(forAlbum: album)
                    let tracks = songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                    allTracks.append(contentsOf: tracks)
                }
                NSLog("Playing subsonic artist %@ with %d tracks", artist.name, allTracks.count)
                WindowManager.shared.audioEngine.loadTracks(allTracks)
            } catch {
                NSLog("Failed to play subsonic artist: %@", error.localizedDescription)
            }
        }
    }
    
    private func playSubsonicPlaylist(_ playlist: SubsonicPlaylist) {
        // Show loading screen while fetching playlist tracks
        isLoading = true
        errorMessage = nil
        startLoadingAnimation()
        needsDisplay = true
        
        Task { @MainActor in
            do {
                let (_, songs) = try await SubsonicManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
                let tracks = songs.compactMap { SubsonicManager.shared.convertToTrack($0) }
                NSLog("Playing subsonic playlist %@ with %d tracks", playlist.name, tracks.count)
                
                isLoading = false
                stopLoadingAnimation()
                needsDisplay = true
                
                WindowManager.shared.audioEngine.loadTracks(tracks)
            } catch {
                NSLog("Failed to play subsonic playlist: %@", error.localizedDescription)
                isLoading = false
                stopLoadingAnimation()
                errorMessage = "Failed to load playlist: \(error.localizedDescription)"
                needsDisplay = true
            }
        }
    }
    
    // MARK: - Local Playback
    
    private func playLocalTrack(_ track: LibraryTrack) {
        NSLog("playLocalTrack: %@", track.title)
        let playbackTrack = track.toTrack()
        WindowManager.shared.audioEngine.loadTracks([playbackTrack])
    }
    
    private func playLocalAlbum(_ album: Album) {
        NSLog("playLocalAlbum: %@ (%d tracks)", album.name, album.tracks.count)
        let tracks = album.tracks.map { $0.toTrack() }
        WindowManager.shared.audioEngine.loadTracks(tracks)
    }
    
    private func playLocalArtist(_ artist: Artist) {
        NSLog("playLocalArtist: %@", artist.name)
        var tracks: [Track] = []
        for album in artist.albums {
            tracks.append(contentsOf: album.tracks.map { $0.toTrack() })
        }
        WindowManager.shared.audioEngine.loadTracks(tracks)
    }
}

// MARK: - NSWindowDelegate

extension PlexBrowserView: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Clear the tags panel reference when it closes
        if let closingWindow = notification.object as? TagsPanel,
           closingWindow === activeTagsPanel {
            activeTagsPanel = nil
        }
    }
}

// MARK: - Rating Overlay

/// Semi-transparent glass-style star rating overlay for rating Plex tracks
class RatingOverlayView: NSView {
    
    var onRatingSelected: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    
    private var hoveredStar: Int = 0
    private var selectedRating: Int = 0
    private let starCount = 5
    private let starSize: CGFloat = 48
    private let starSpacing: CGFloat = 12
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        // Semi-transparent dark background for the full overlay
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
    }
    
    func setRating(_ rating: Int) {
        // rating is on Plex 0-10 scale, convert to 1-5 stars
        selectedRating = rating / 2
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Calculate centered position for star container
        let totalWidth = CGFloat(starCount) * starSize + CGFloat(starCount - 1) * starSpacing
        let containerWidth = totalWidth + 40  // padding
        let containerHeight = starSize + 40
        let containerX = (bounds.width - containerWidth) / 2
        let containerY = (bounds.height - containerHeight) / 2
        let containerRect = NSRect(x: containerX, y: containerY, width: containerWidth, height: containerHeight)
        
        // Draw frosted glass background for star container
        context.saveGState()
        let path = NSBezierPath(roundedRect: containerRect, xRadius: 16, yRadius: 16)
        NSColor(white: 1.0, alpha: 0.15).setFill()
        path.fill()
        
        // Draw subtle border
        NSColor(white: 1.0, alpha: 0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
        context.restoreGState()
        
        // Draw stars
        let startX = containerX + 20
        let starY = containerY + 20
        
        for i in 0..<starCount {
            let starX = startX + CGFloat(i) * (starSize + starSpacing)
            let starRect = NSRect(x: starX, y: starY, width: starSize, height: starSize)
            
            let starNumber = i + 1
            let isFilled = starNumber <= max(hoveredStar, selectedRating)
            let isHovered = starNumber <= hoveredStar && hoveredStar > 0
            
            drawStar(in: starRect, filled: isFilled, hovered: isHovered, context: context)
        }
    }
    
    private func drawStar(in rect: NSRect, filled: Bool, hovered: Bool, context: CGContext) {
        // Star path (5-pointed star)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerRadius = rect.width / 2
        let innerRadius = outerRadius * 0.4
        
        let path = NSBezierPath()
        for i in 0..<10 {
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let point = NSPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        
        // Glass effect colors
        if filled {
            // Filled star: white with subtle transparency
            NSColor(white: 1.0, alpha: hovered ? 0.95 : 0.85).setFill()
            path.fill()
        } else {
            // Empty star: outline only with glass effect
            NSColor(white: 1.0, alpha: 0.3).setFill()
            path.fill()
        }
        
        // Subtle outline
        NSColor(white: 1.0, alpha: 0.5).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
    
    // MARK: - Mouse Handling
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoveredStar = starAtPoint(point)
        needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedStar = starAtPoint(point)
        
        if clickedStar > 0 {
            selectedRating = clickedStar
            needsDisplay = true
            // Convert 1-5 stars to Plex 0-10 scale (each star = 2 points)
            onRatingSelected?(clickedStar * 2)
        } else {
            // Clicked outside stars - dismiss
            onDismiss?()
        }
    }
    
    private func starAtPoint(_ point: NSPoint) -> Int {
        let totalWidth = CGFloat(starCount) * starSize + CGFloat(starCount - 1) * starSpacing
        let containerWidth = totalWidth + 40
        let containerHeight = starSize + 40
        let containerX = (bounds.width - containerWidth) / 2
        let containerY = (bounds.height - containerHeight) / 2
        let startX = containerX + 20
        let starY = containerY + 20
        
        for i in 0..<starCount {
            let starX = startX + CGFloat(i) * (starSize + starSpacing)
            let starRect = NSRect(x: starX, y: starY, width: starSize, height: starSize)
            if starRect.contains(point) {
                return i + 1
            }
        }
        return 0
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }
}

// MARK: - Display Item

/// Represents an item to display in the Plex browser list
private struct PlexDisplayItem {
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
        // Local content types
        case localArtist(Artist)
        case localAlbum(Album)
        case localTrack(LibraryTrack)
        // Subsonic content types
        case subsonicArtist(SubsonicArtist)
        case subsonicAlbum(SubsonicAlbum)
        case subsonicTrack(SubsonicSong)
        case subsonicPlaylist(SubsonicPlaylist)
        // Plex playlist type
        case plexPlaylist(PlexPlaylist)
        // Radio station type (Internet Radio - Shoutcast/Icecast)
        case radioStation(RadioStation)
        // Plex Radio station type (dynamic playlists from Plex library)
        case plexRadioStation(PlexRadioType)
    }
}

/// Types of Plex Radio stations
enum PlexRadioType: Equatable, Hashable {
    case libraryRadio
    case libraryRadioSonic
    case hitsRadio
    case hitsRadioSonic
    case deepCutsRadio
    case deepCutsRadioSonic
    case genreRadio(String)
    case genreRadioSonic(String)
    case decadeRadio(start: Int, end: Int, name: String)
    case decadeRadioSonic(start: Int, end: Int, name: String)
    case ratingRadio(minRating: Double, name: String)
    case ratingRadioSonic(minRating: Double, name: String)
    
    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .libraryRadioSonic: return "Library Radio (Sonic)"
        case .hitsRadio: return "Only the Hits"
        case .hitsRadioSonic: return "Only the Hits (Sonic)"
        case .deepCutsRadio: return "Deep Cuts"
        case .deepCutsRadioSonic: return "Deep Cuts (Sonic)"
        case .genreRadio(let genre): return "\(genre) Radio"
        case .genreRadioSonic(let genre): return "\(genre) Radio (Sonic)"
        case .decadeRadio(_, _, let name): return "\(name) Radio"
        case .decadeRadioSonic(_, _, let name): return "\(name) Radio (Sonic)"
        case .ratingRadio(_, let name): return "\(name) Radio"
        case .ratingRadioSonic(_, let name): return "\(name) Radio (Sonic)"
        }
    }
    
    var category: String {
        switch self {
        case .libraryRadio, .libraryRadioSonic: return "Library"
        case .hitsRadio, .hitsRadioSonic: return "Popularity"
        case .deepCutsRadio, .deepCutsRadioSonic: return "Popularity"
        case .genreRadio, .genreRadioSonic: return "Genre"
        case .decadeRadio, .decadeRadioSonic: return "Decade"
        case .ratingRadio, .ratingRadioSonic: return "My Ratings"
        }
    }
    
    var isSonic: Bool {
        switch self {
        case .libraryRadioSonic, .hitsRadioSonic, .deepCutsRadioSonic, 
             .genreRadioSonic, .decadeRadioSonic, .ratingRadioSonic:
            return true
        default:
            return false
        }
    }
}

// MARK: - Column Configuration

/// Column definition for the library browser table view
private struct BrowserColumn {
    let id: String
    let title: String
    let minWidth: CGFloat
    
    // Track columns - all left aligned with intelligent spacing
    static let trackNumber = BrowserColumn(id: "trackNum", title: "#", minWidth: 30)
    static let title = BrowserColumn(id: "title", title: "Title", minWidth: 120)
    static let artist = BrowserColumn(id: "artist", title: "Artist", minWidth: 100)
    static let album = BrowserColumn(id: "album", title: "Album", minWidth: 100)
    static let year = BrowserColumn(id: "year", title: "Year", minWidth: 45)
    static let genre = BrowserColumn(id: "genre", title: "Genre", minWidth: 80)
    static let duration = BrowserColumn(id: "duration", title: "Time", minWidth: 50)
    static let bitrate = BrowserColumn(id: "bitrate", title: "Bitrate", minWidth: 55)
    static let size = BrowserColumn(id: "size", title: "Size", minWidth: 55)
    static let rating = BrowserColumn(id: "rating", title: "Rating", minWidth: 70)
    static let playCount = BrowserColumn(id: "plays", title: "Plays", minWidth: 45)
    
    /// Columns shown for track lists
    static let trackColumns: [BrowserColumn] = [
        .trackNumber, .title, .artist, .album, .year, .genre, .duration, .bitrate, .size, .rating, .playCount
    ]
    
    /// Columns shown for album lists  
    static let albumColumns: [BrowserColumn] = [
        .title, .year, .genre, .duration, .rating
    ]
    
    // Artist-specific columns
    static let albums = BrowserColumn(id: "albums", title: "Albums", minWidth: 55)
    
    /// Columns shown for artist lists
    static let artistColumns: [BrowserColumn] = [
        .title, .albums, .genre
    ]
    
    /// Find a column by ID across all column types
    static func findColumn(id: String) -> BrowserColumn? {
        if let c = trackColumns.first(where: { $0.id == id }) { return c }
        if let c = albumColumns.first(where: { $0.id == id }) { return c }
        if let c = artistColumns.first(where: { $0.id == id }) { return c }
        return nil
    }
}

// MARK: - Column Value Extraction

extension PlexDisplayItem {
    /// Get the display value for a specific column based on item type
    func columnValue(for column: BrowserColumn) -> String {
        // Title column always uses the display item's title (already set correctly on creation)
        if column.id == "title" {
            return title
        }
        
        switch type {
        case .track(let track):
            return plexTrackValue(track, for: column)
        case .subsonicTrack(let song):
            return subsonicTrackValue(song, for: column)
        case .localTrack(let track):
            return localTrackValue(track, for: column)
        case .album(let album):
            return plexAlbumValue(album, for: column)
        case .subsonicAlbum(let album):
            return subsonicAlbumValue(album, for: column)
        case .localAlbum(let album):
            return localAlbumValue(album, for: column)
        case .artist(let artist):
            return plexArtistValue(artist, for: column)
        case .subsonicArtist(let artist):
            return subsonicArtistValue(artist, for: column)
        case .localArtist(let artist):
            return localArtistValue(artist, for: column)
        default:
            return ""
        }
    }
    
    // MARK: - Plex Track Values
    
    private func plexTrackValue(_ track: PlexTrack, for column: BrowserColumn) -> String {
        switch column.id {
        case "trackNum":
            // Show disc-track for multi-disc albums (e.g., "2-5")
            if let disc = track.parentIndex, disc > 1, let num = track.index {
                return "\(disc)-\(num)"
            }
            return track.index.map { String($0) } ?? ""
        case "artist":
            return track.grandparentTitle ?? ""
        case "album":
            return track.parentTitle ?? ""
        case "year":
            return track.parentYear.map { String($0) } ?? ""
        case "genre":
            return track.genre ?? ""
        case "duration":
            return track.formattedDuration
        case "bitrate":
            return track.media.first?.bitrate.map { "\($0)k" } ?? ""
        case "size":
            return Self.formatFileSize(track.media.first?.parts.first?.size)
        case "rating":
            return Self.formatRating(track.userRating)
        case "plays":
            return track.ratingCount.map { String($0) } ?? ""
        default:
            return ""
        }
    }
    
    // MARK: - Subsonic Track Values
    
    private func subsonicTrackValue(_ song: SubsonicSong, for column: BrowserColumn) -> String {
        switch column.id {
        case "trackNum":
            if let disc = song.discNumber, disc > 1, let num = song.track {
                return "\(disc)-\(num)"
            }
            return song.track.map { String($0) } ?? ""
        case "artist":
            return song.artist ?? ""
        case "album":
            return song.album ?? ""
        case "year":
            return song.year.map { String($0) } ?? ""
        case "genre":
            return song.genre ?? ""
        case "duration":
            return song.formattedDuration
        case "bitrate":
            return song.bitRate.map { "\($0)k" } ?? ""
        case "size":
            return Self.formatFileSize(song.size)
        case "rating":
            // Subsonic uses starred (date) as favorite indicator
            return song.starred != nil ? "★★★★★" : ""
        case "plays":
            return song.playCount.map { String($0) } ?? ""
        default:
            return ""
        }
    }
    
    // MARK: - Local Track Values
    
    private func localTrackValue(_ track: LibraryTrack, for column: BrowserColumn) -> String {
        switch column.id {
        case "trackNum":
            if let disc = track.discNumber, disc > 1, let num = track.trackNumber {
                return "\(disc)-\(num)"
            }
            return track.trackNumber.map { String($0) } ?? ""
        case "artist":
            return track.artist ?? ""
        case "album":
            return track.album ?? ""
        case "year":
            return track.year.map { String($0) } ?? ""
        case "genre":
            return track.genre ?? ""
        case "duration":
            return track.formattedDuration
        case "bitrate":
            return track.bitrate.map { "\($0)k" } ?? ""
        case "size":
            return Self.formatFileSize(track.fileSize)
        case "rating":
            return ""  // Local files don't have ratings yet
        case "plays":
            return track.playCount > 0 ? String(track.playCount) : ""
        default:
            return ""
        }
    }
    
    // MARK: - Plex Album Values
    
    private func plexAlbumValue(_ album: PlexAlbum, for column: BrowserColumn) -> String {
        switch column.id {
        case "year":
            return album.year.map { String($0) } ?? ""
        case "genre":
            return album.genre ?? ""
        case "duration":
            return album.formattedDuration
        case "rating":
            return ""  // Albums don't have ratings in current model
        default:
            return ""
        }
    }
    
    // MARK: - Subsonic Album Values
    
    private func subsonicAlbumValue(_ album: SubsonicAlbum, for column: BrowserColumn) -> String {
        switch column.id {
        case "year":
            return album.year.map { String($0) } ?? ""
        case "genre":
            return album.genre ?? ""
        case "duration":
            return album.formattedDuration
        case "rating":
            return album.starred != nil ? "★★★★★" : ""
        default:
            return ""
        }
    }
    
    // MARK: - Local Album Values
    
    private func localAlbumValue(_ album: Album, for column: BrowserColumn) -> String {
        switch column.id {
        case "year":
            return album.year.map { String($0) } ?? ""
        case "genre":
            return ""  // Local Album doesn't have genre at album level
        case "duration":
            return album.formattedDuration
        case "rating":
            return ""
        default:
            return ""
        }
    }
    
    // MARK: - Plex Artist Values
    
    private func plexArtistValue(_ artist: PlexArtist, for column: BrowserColumn) -> String {
        switch column.id {
        case "albums":
            return String(artist.albumCount)
        case "genre":
            return artist.genre ?? ""
        default:
            return ""
        }
    }
    
    // MARK: - Subsonic Artist Values
    
    private func subsonicArtistValue(_ artist: SubsonicArtist, for column: BrowserColumn) -> String {
        switch column.id {
        case "albums":
            return String(artist.albumCount)
        case "genre":
            return ""  // Subsonic artists don't have genre
        default:
            return ""
        }
    }
    
    // MARK: - Local Artist Values
    
    private func localArtistValue(_ artist: Artist, for column: BrowserColumn) -> String {
        switch column.id {
        case "albums":
            return String(artist.albums.count)
        case "genre":
            return ""  // Local artists don't have genre at artist level
        default:
            return ""
        }
    }
    
    // MARK: - Formatting Helpers
    
    private static func formatFileSize(_ bytes: Int64?) -> String {
        guard let bytes = bytes, bytes > 0 else { return "" }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1000 {
            return String(format: "%.1fG", mb / 1024.0)
        }
        return String(format: "%.1fM", mb)
    }
    
    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        let hours = mins / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins % 60, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
    
    private static func formatRating(_ rating: Double?) -> String {
        guard let rating = rating, rating > 0 else { return "" }
        let stars = Int(rating / 2.0)  // Plex uses 0-10 scale, convert to 0-5 stars
        let empty = 5 - stars
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: empty)
    }
}
