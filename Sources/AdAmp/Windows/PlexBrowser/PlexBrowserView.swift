import AppKit

/// Source for browsing content
enum BrowserSource: Equatable, Codable {
    case local
    case plex(serverId: String)
    
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
    case movies = 3
    case shows = 4
    case search = 5
    
    var title: String {
        switch self {
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .tracks: return "Tracks"
        case .movies: return "Movies"
        case .shows: return "Shows"
        case .search: return "Search"
        }
    }
    
    var isVideoMode: Bool {
        self == .movies || self == .shows
    }
    
    var isMusicMode: Bool {
        self == .artists || self == .albums || self == .tracks
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
    
    /// Item height
    private let itemHeight: CGFloat = 18
    
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
    
    /// Cached data - Video
    private var cachedMovies: [PlexMovie] = []
    private var cachedShows: [PlexShow] = []
    private var showSeasons: [String: [PlexSeason]] = [:]
    private var seasonEpisodes: [String: [PlexEpisode]] = [:]
    
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
    private var serverScrollTimer: Timer?
    private var lastServerName: String = ""
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
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
        
        // Load saved source
        if let savedSource = BrowserSource.load() {
            // Validate saved source
            switch savedSource {
            case .local:
                currentSource = .local
            case .plex(let serverId):
                // Only restore Plex source if server still exists and user is linked
                if PlexManager.shared.isLinked,
                   PlexManager.shared.servers.contains(where: { $0.id == serverId }) {
                    currentSource = savedSource
                } else if PlexManager.shared.isLinked, let firstServer = PlexManager.shared.servers.first {
                    currentSource = .plex(serverId: firstServer.id)
                } else {
                    currentSource = .local
                }
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
        
        // Register for drag and drop (local files)
        registerForDraggedTypes([.fileURL])
        
        // Initial data load
        reloadData()
        
        // Start server name scroll animation
        startServerNameScroll()
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
        // Only reload if we're showing local content
        guard case .local = currentSource else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.loadLocalData()
            self?.needsDisplay = true
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
    /// For vertical resizing, we use the actual bounds height to allow the content area to expand
    private var originalWindowSize: NSSize {
        if isShadeMode {
            // Shade mode: width scales with window, height is fixed
            return NSSize(width: SkinElements.PlexBrowser.minSize.width, height: SkinElements.PlexBrowser.shadeHeight)
        } else {
            // Use minimum width but actual height to allow vertical expansion
            return NSSize(width: SkinElements.PlexBrowser.minSize.width, height: bounds.height)
        }
    }
    
    /// Calculate scale factor based on current bounds vs original (base) size
    /// Only scale horizontally - vertical content area expands with window
    private var scaleFactor: CGFloat {
        if isShadeMode {
            let originalSize = originalWindowSize
            let scaleX = bounds.width / originalSize.width
            return scaleX
        } else {
            // Scale based on width only - height expands naturally
            return bounds.width / SkinElements.PlexBrowser.minSize.width
        }
    }
    
    /// Convert a point from view coordinates to original (unscaled) Winamp coordinates
    private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
        let scale = scaleFactor
        let originalSize = originalWindowSize
        
        if isShadeMode {
            // Shade mode uses uniform scaling
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            let offsetY = (bounds.height - scaledHeight) / 2
            
            let x = (point.x - offsetX) / scale
            let y = originalSize.height - ((point.y - offsetY) / scale)
            return NSPoint(x: x, y: y)
        } else {
            // Normal mode: horizontal scaling only, height is 1:1
            let scaledWidth = SkinElements.PlexBrowser.minSize.width * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            
            let x = (point.x - offsetX) / scale
            // Vertical is not scaled - just flip coordinates
            let y = bounds.height - point.y
            
            return NSPoint(x: x, y: y)
        }
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
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
        
        // Apply scaling for resized window
        if isShadeMode {
            // Shade mode uses uniform scaling
            if scale != 1.0 {
                let scaledWidth = originalSize.width * scale
                let scaledHeight = originalSize.height * scale
                let offsetX = (bounds.width - scaledWidth) / 2
                let offsetY = (bounds.height - scaledHeight) / 2
                context.translateBy(x: offsetX, y: offsetY)
                context.scaleBy(x: scale, y: scale)
            }
        } else {
            // Normal mode: horizontal scaling only, vertical is 1:1
            if scale != 1.0 {
                let scaledWidth = SkinElements.PlexBrowser.minSize.width * scale
                let offsetX = (bounds.width - scaledWidth) / 2
                context.translateBy(x: offsetX, y: 0)
                context.scaleBy(x: scale, y: 1)  // Only scale horizontally
            }
        }
        
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
            
            // Draw tab bar
            drawTabBar(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
            
            // Draw search bar (only in search mode)
            if browseMode == .search {
                drawSearchBar(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
            }
            
            // Draw list area or connection status
            if !PlexManager.shared.isLinked {
                drawNotLinkedState(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
            } else if isLoading {
                drawLoadingState(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
            } else if let error = errorMessage {
                drawErrorState(in: context, drawBounds: drawBounds, message: error, colors: colors, renderer: renderer)
            } else {
                drawListArea(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
            }
            
            // Draw status bar text
            drawStatusBarText(in: context, drawBounds: drawBounds, colors: colors, renderer: renderer)
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
        let x = rect.midX - textWidth / 2
        let y = rect.midY - textHeight / 2
        drawScaledWhiteSkinText(text, at: NSPoint(x: x, y: y), scale: scale, renderer: renderer, in: context)
    }
    
    private func drawServerBar(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        let barY = Layout.titleBarHeight
        let barRect = NSRect(x: Layout.leftBorder, y: barY,
                            width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                            height: Layout.serverBarHeight)
        
        // Background
        colors.normalBackground.withAlphaComponent(0.6).setFill()
        context.fill(barRect)
        
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        let scaledCharHeight = charHeight * textScale
        let textY = barRect.minY + (barRect.height - scaledCharHeight) / 2
        
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
            
            // Right side: Refresh icon
            let refreshX = barRect.maxX - scaledCharWidth - 4
            drawScaledSkinText("O", at: NSPoint(x: refreshX, y: textY), scale: textScale, renderer: renderer, in: context)
            
            // +ADD button (to the left of refresh)
            let addText = "+ADD"
            let addWidth = CGFloat(addText.count) * scaledCharWidth
            let addX = refreshX - addWidth - 12
            drawScaledWhiteSkinText(addText, at: NSPoint(x: addX, y: textY), scale: textScale, renderer: renderer, in: context)
            
            // Item count (center)
            let countNumber = "\(displayItems.count)"
            let countLabel = " items"
            let countTotalWidth = CGFloat(countNumber.count + countLabel.count) * scaledCharWidth
            let countX = barRect.midX - countTotalWidth / 2
            drawScaledWhiteSkinText(countNumber, at: NSPoint(x: countX, y: textY), scale: textScale, renderer: renderer, in: context)
            let labelX = countX + CGFloat(countNumber.count) * scaledCharWidth
            drawScaledSkinText(countLabel, at: NSPoint(x: labelX, y: textY), scale: textScale, renderer: renderer, in: context)
            
        case .plex(let serverId):
            let manager = PlexManager.shared
            
            if manager.isLinked {
                let serverNameStartX = sourceNameStartX
                
                // Right side: Refresh icon in green skin text
                let refreshX = barRect.maxX - scaledCharWidth - 4
                drawScaledSkinText("O", at: NSPoint(x: refreshX, y: textY), scale: textScale, renderer: renderer, in: context)
                
                // Library name in WHITE skin text (only for Plex)
                let libraryText = manager.currentLibrary?.title ?? "Select Library"
                let libraryWidth = CGFloat(libraryText.count) * scaledCharWidth
                let libraryX = refreshX - libraryWidth - 8
                drawScaledWhiteSkinText(libraryText, at: NSPoint(x: libraryX, y: textY), scale: textScale, renderer: renderer, in: context)
                
                // Item count (center)
                let countNumber = "\(displayItems.count)"
                let countLabel = " items"
                let countTotalWidth = CGFloat(countNumber.count + countLabel.count) * scaledCharWidth
                let countX = barRect.midX - countTotalWidth / 2
                drawScaledWhiteSkinText(countNumber, at: NSPoint(x: countX, y: textY), scale: textScale, renderer: renderer, in: context)
                let labelX = countX + CGFloat(countNumber.count) * scaledCharWidth
                drawScaledSkinText(countLabel, at: NSPoint(x: labelX, y: textY), scale: textScale, renderer: renderer, in: context)
                
                // Server name
                let serverName = manager.servers.first(where: { $0.id == serverId })?.name ?? "Select Server"
                let serverTextWidth = CGFloat(serverName.count) * scaledCharWidth
                
                // Available width for server name
                let availableWidth = countX - serverNameStartX - 16
                
                if serverTextWidth <= availableWidth || availableWidth <= 0 {
                    drawScaledWhiteSkinText(serverName, at: NSPoint(x: serverNameStartX, y: textY), scale: textScale, renderer: renderer, in: context)
                } else {
                    // Text too long - draw with circular scrolling
                    drawScrollingServerName(serverName, startX: serverNameStartX, textY: textY,
                                           availableWidth: availableWidth, scale: textScale,
                                           renderer: renderer, in: context)
                }
            } else {
                // Plex not linked - show link message
                let linkText = "Click to link your Plex account"
                let linkWidth = CGFloat(linkText.count) * scaledCharWidth
                let linkX = barRect.midX - linkWidth / 2
                drawScaledSkinText(linkText, at: NSPoint(x: linkX, y: textY), scale: textScale, renderer: renderer, in: context)
            }
        }
    }
    
    /// Draw server name with circular scrolling when it's too long
    private func drawScrollingServerName(_ text: String, startX: CGFloat, textY: CGFloat,
                                         availableWidth: CGFloat, scale: CGFloat,
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
            let baseX = startX - serverNameScrollOffset + (CGFloat(pass) * totalCycleWidth)
            
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
        
        // Background
        colors.normalBackground.withAlphaComponent(0.4).setFill()
        context.fill(tabBarRect)
        
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        let scaledCharHeight = charHeight * textScale
        
        // Calculate sort indicator width (on the right)
        let sortText = "Sort:\(currentSort.shortName)"
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
                let textX = tabRect.midX - titleWidth / 2
                let textY = tabRect.minY + (tabRect.height - scaledCharHeight) / 2
                drawScaledSkinText(mode.title, at: NSPoint(x: textX, y: textY), scale: textScale, renderer: renderer, in: context)
            }
        }
        
        // Draw sort indicator on the right
        let sortX = tabBarRect.maxX - sortWidth + 4
        let sortY = tabBarY + (Layout.tabBarHeight - scaledCharHeight) / 2
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
        case .search:
            message = searchQuery.isEmpty ? "Type to search" : "No results found"
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
    
    private func drawListArea(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors, renderer: SkinRenderer) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = drawBounds.height - listY - Layout.statusBarHeight
        
        // Account for alphabet index on the right
        let alphabetWidth = Layout.alphabetWidth
        let listRect = NSRect(x: Layout.leftBorder, y: listY,
                             width: drawBounds.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth - alphabetWidth,
                             height: listHeight)
        
        // Show empty state message if no items
        if displayItems.isEmpty {
            drawEmptyState(in: context, listRect: listRect, colors: colors, renderer: renderer)
            return
        }
        
        // Clip to list area
        context.saveGState()
        context.clip(to: listRect)
        
        // Draw items
        let visibleStart = Int(scrollOffset / itemHeight)
        let visibleEnd = min(displayItems.count, visibleStart + Int(listHeight / itemHeight) + 2)
        
        for index in visibleStart..<visibleEnd {
            let y = listY + CGFloat(index) * itemHeight - scrollOffset
            
            if y + itemHeight < listY || y > listY + listHeight {
                continue
            }
            
            let itemRect = NSRect(x: listRect.minX, y: y, width: listRect.width, height: itemHeight)
            let item = displayItems[index]
            
            // Selection background
            if selectedIndices.contains(index) {
                colors.selectedBackground.setFill()
                context.fill(itemRect)
            }
            
            // Item content
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
            
            let textColor = selectedIndices.contains(index) ? colors.currentText : colors.normalText
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: NSFont.systemFont(ofSize: 10)
            ]
            
            let textRect = NSRect(x: textX, y: itemRect.minY + 2,
                                 width: itemRect.width - indent - 60, height: itemHeight - 4)
            item.title.draw(in: textRect, withAttributes: attrs)
            
            // Secondary info
            if let info = item.info {
                let infoColor = selectedIndices.contains(index) ? colors.currentText : colors.normalText.withAlphaComponent(0.6)
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
        
        context.restoreGState()
        
        // Draw alphabet index
        let alphabetRect = NSRect(x: drawBounds.width - Layout.rightBorder - Layout.scrollbarWidth - alphabetWidth,
                                 y: listY, width: alphabetWidth, height: listHeight)
        drawAlphabetIndex(in: context, rect: alphabetRect, colors: colors, renderer: renderer)
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
        loadingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadingAnimationFrame += 1
            if self.isLoading {
                self.needsDisplay = true
            } else {
                self.stopLoadingAnimation()
            }
        }
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
    }
    
    private func updateServerNameScroll() {
        let manager = PlexManager.shared
        guard manager.isLinked else {
            if serverNameScrollOffset != 0 {
                serverNameScrollOffset = 0
                needsDisplay = true
            }
            return
        }
        
        let serverName = manager.currentServer?.name ?? "Select Server"
        
        // Reset scroll if server name changed
        if serverName != lastServerName {
            lastServerName = serverName
            serverNameScrollOffset = 0
        }
        
        let charWidth = SkinElements.TextFont.charWidth
        let textScale: CGFloat = 1.5
        let scaledCharWidth = charWidth * textScale
        
        // Calculate available width for server name
        let drawBounds = bounds
        let barRect = NSRect(x: Layout.leftBorder, y: Layout.titleBarHeight,
                            width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                            height: Layout.serverBarHeight)
        
        let prefix = "Plex Server: "
        let prefixWidth = CGFloat(prefix.count) * scaledCharWidth
        let serverNameStartX = barRect.minX + 4 + prefixWidth
        
        // Center elements: item count
        let countNumber = "\(displayItems.count)"
        let countLabel = " items"
        let countTotalWidth = CGFloat(countNumber.count + countLabel.count) * scaledCharWidth
        let countCenterX = barRect.midX
        let countStartX = countCenterX - countTotalWidth / 2
        
        // Available width for server name (from after prefix to before count, with padding)
        let availableWidth = countStartX - serverNameStartX - 16  // 16px padding
        
        let serverTextWidth = CGFloat(serverName.count) * scaledCharWidth
        
        if serverTextWidth > availableWidth && availableWidth > 0 {
            // Text is too long, scroll it
            let separator = "   "  // Separator for circular scroll
            let separatorWidth = CGFloat(separator.count) * scaledCharWidth
            let totalCycleWidth = serverTextWidth + separatorWidth
            
            serverNameScrollOffset += 1
            // Reset when one full cycle completes
            if serverNameScrollOffset >= totalCycleWidth {
                serverNameScrollOffset = 0
            }
            
            // Only redraw the server bar area
            let serverBarArea = NSRect(x: 0, y: bounds.height - Layout.titleBarHeight - Layout.serverBarHeight,
                                       width: bounds.width, height: Layout.serverBarHeight)
            setNeedsDisplay(serverBarArea)
        } else {
            // Text fits - no scrolling needed
            if serverNameScrollOffset != 0 {
                serverNameScrollOffset = 0
                let serverBarArea = NSRect(x: 0, y: bounds.height - Layout.titleBarHeight - Layout.serverBarHeight,
                                           width: bounds.width, height: Layout.serverBarHeight)
                setNeedsDisplay(serverBarArea)
            }
        }
    }
    
    // MARK: - Public Methods
    
    func reloadData() {
        // For local source, we don't need Plex to be linked
        if case .local = currentSource {
            loadLocalData()
            needsDisplay = true
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
        searchResults = nil
        
        // Reset expanded states
        expandedArtists = []
        expandedAlbums = []
        expandedShows = []
        expandedSeasons = []
        
        // Reset selection and scroll
        selectedIndices = []
        scrollOffset = 0
        
        // Show loading state
        isLoading = true
        errorMessage = nil
        displayItems = []
        startLoadingAnimation()
        needsDisplay = true
        
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
            if case .connecting = PlexManager.shared.connectionState {
                NSLog("PlexBrowserView: Server list changed, but still connecting - just updating display")
                self?.needsDisplay = true
                return
            }
            NSLog("PlexBrowserView: Server changed, clearing cache and reloading")
            self?.clearAllCachedData()
            self?.reloadData()
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
        let sortText = "Sort:\(currentSort.shortName)"
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
        let listHeight = originalWindowSize.height - listY - Layout.statusBarHeight
        
        let listRect = NSRect(
            x: Layout.leftBorder,
            y: listY,
            width: originalWindowSize.width - Layout.leftBorder - Layout.rightBorder - Layout.scrollbarWidth - Layout.alphabetWidth,
            height: listHeight
        )
        
        guard listRect.contains(winampPoint) else { return nil }
        
        let relativeY = winampPoint.y - listY + scrollOffset
        let clickedIndex = Int(relativeY / itemHeight)
        
        if clickedIndex >= 0 && clickedIndex < displayItems.count {
            return clickedIndex
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
        
        let scrollbarRect = NSRect(
            x: originalWindowSize.width - Layout.rightBorder,
            y: listY,
            width: Layout.scrollbarWidth,
            height: listHeight
        )
        
        return scrollbarRect.contains(winampPoint)
    }
    
    // MARK: - Mouse Events
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = convertToWinampCoordinates(point)
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 && hitTestTitleBar(at: winampPoint) {
            toggleShadeMode()
            return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: winampPoint, event: event)
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
            if !PlexManager.shared.isLinked {
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
        
        // Check scrollbar
        if hitTestScrollbar(at: winampPoint) {
            isDraggingScrollbar = true
            scrollbarDragStartY = winampPoint.y
            scrollbarDragStartOffset = scrollOffset
            return
        }
        
        // Check list area
        if let itemIndex = hitTestListArea(at: winampPoint) {
            handleListClick(at: itemIndex, event: event, winampPoint: winampPoint)
            return
        }
        
        // Title bar - start window drag
        if hitTestTitleBar(at: winampPoint) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
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
        
        // Start window drag
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
    }
    
    private func handleServerBarClick(at winampPoint: NSPoint, event: NSEvent) {
        let originalSize = originalWindowSize
        let barWidth = originalSize.width - Layout.leftBorder - Layout.rightBorder
        
        // Layout depends on source:
        // Local: [Local Files ▼] ... [item count] ... [+ADD] [↻]
        // Plex:  [Plex: Server ▼] ... [item count] ... [Library ▼] [↻]
        
        let refreshZone: CGFloat = 25  // Far right area for refresh
        let addZone: CGFloat = 70  // +ADD button area (to the left of refresh)
        let relativeX = winampPoint.x - Layout.leftBorder
        
        if relativeX > barWidth - refreshZone {
            // Refresh icon click
            handleRefreshClick()
        } else if case .local = currentSource {
            // Local mode - check for +ADD button
            if relativeX > barWidth - addZone {
                // +ADD button click
                showAddFilesMenu(at: event)
            } else if relativeX < barWidth / 2 {
                // Left half = source dropdown
                showSourceMenu(at: event)
            }
        } else if case .plex = currentSource {
            // Plex mode has library dropdown on right side
            let libraryZone: CGFloat = 120
            if relativeX > barWidth - libraryZone {
                showLibraryMenu(at: event)
            } else if relativeX < barWidth / 2 {
                // Left half = source dropdown
                showSourceMenu(at: event)
            }
        }
    }
    
    /// Handle refresh button click based on current source
    private func handleRefreshClick() {
        switch currentSource {
        case .local:
            // Rescan watch folders
            MediaLibrary.shared.rescanWatchFolders()
            // Also reload local data
            loadLocalData()
        case .plex:
            // Refresh Plex data
            refreshData()
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
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Plex servers
        let servers = PlexManager.shared.servers
        if servers.isEmpty && !PlexManager.shared.isLinked {
            let linkItem = NSMenuItem(title: "Link Plex Account...", action: #selector(linkPlexAccount), keyEquivalent: "")
            linkItem.target = self
            menu.addItem(linkItem)
        } else {
            for server in servers {
                let serverItem = NSMenuItem(title: server.name, action: #selector(selectPlexServer(_:)), keyEquivalent: "")
                serverItem.target = self
                serverItem.representedObject = server.id
                if case .plex(let currentServerId) = currentSource, currentServerId == server.id {
                    serverItem.state = .on
                }
                menu.addItem(serverItem)
            }
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
        } else if event.modifierFlags.contains(.command) {
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
        } else {
            selectedIndices = [index]
            
            // Single-click on playable items plays them immediately
            switch item.type {
            case .track:
                playTrack(item)
            case .movie(let movie):
                playMovie(movie)
            case .episode(let episode):
                playEpisode(episode)
            case .localTrack(let track):
                playLocalTrack(track)
            default:
                break
            }
        }
        
        // Double-click to play album/show or expand artist
        if event.clickCount == 2 {
            handleDoubleClick(on: item)
        }
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
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
                needsDisplay = true
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
        
        if totalHeight > listHeight {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))
            needsDisplay = true
        }
    }
    
    // MARK: - Drag and Drop (Local Files)
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        
        var fileURLs: [URL] = []
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
        
        for url in items {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Add folder as watch folder and scan
                    MediaLibrary.shared.addWatchFolder(url)
                    MediaLibrary.shared.scanFolder(url)
                } else {
                    // Add individual audio file
                    if audioExtensions.contains(url.pathExtension.lowercased()) {
                        fileURLs.append(url)
                    }
                }
            }
        }
        
        if !fileURLs.isEmpty {
            MediaLibrary.shared.addTracks(urls: fileURLs)
        }
        
        // Switch to local source to show added content
        if case .plex = currentSource {
            currentSource = .local
        }
        
        return true
    }
    
    // MARK: - Right-Click Context Menu
    
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = convertToWinampCoordinates(point)
        
        // Check list area
        if let clickedIndex = hitTestListArea(at: winampPoint) {
            // Select the clicked item if not already selected
            if !selectedIndices.contains(clickedIndex) {
                selectedIndices = [clickedIndex]
                needsDisplay = true
            }
            
            let item = displayItems[clickedIndex]
            showContextMenu(for: item, at: event)
            return
        }
        
        // Default context menu
        super.rightMouseDown(with: event)
    }
    
    private func showContextMenu(for item: PlexDisplayItem, at event: NSEvent) {
        let menu = NSMenu()
        
        switch item.type {
        case .track(let track):
            let playItem = NSMenuItem(title: "Play", action: #selector(contextMenuPlay(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = item
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add to Playlist", action: #selector(contextMenuAddToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = track
            menu.addItem(addItem)
            
        case .album(let album):
            let playItem = NSMenuItem(title: "Play Album", action: #selector(contextMenuPlayAlbum(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = album
            menu.addItem(playItem)
            
            let addItem = NSMenuItem(title: "Add Album to Playlist", action: #selector(contextMenuAddAlbumToPlaylist(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = album
            menu.addItem(addItem)
            
        case .artist(let artist):
            let playItem = NSMenuItem(title: "Play All by Artist", action: #selector(contextMenuPlayArtist(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = artist
            menu.addItem(playItem)
            
            let expandItem = NSMenuItem(title: expandedArtists.contains(artist.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
        case .movie(let movie):
            let playItem = NSMenuItem(title: "Play Movie", action: #selector(contextMenuPlayMovie(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = movie
            menu.addItem(playItem)
            
        case .show(let show):
            let expandItem = NSMenuItem(title: expandedShows.contains(show.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
        case .season(let season):
            let expandItem = NSMenuItem(title: expandedSeasons.contains(season.id) ? "Collapse" : "Expand", action: #selector(contextMenuToggleExpand(_:)), keyEquivalent: "")
            expandItem.target = self
            expandItem.representedObject = item
            menu.addItem(expandItem)
            
        case .episode(let episode):
            let playItem = NSMenuItem(title: "Play Episode", action: #selector(contextMenuPlayEpisode(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = episode
            menu.addItem(playItem)
            
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
        switch event.keyCode {
        case 36: // Enter - play selected
            if let index = selectedIndices.first, index < displayItems.count {
                handleDoubleClick(on: displayItems[index])
            }
            
        case 125: // Down arrow
            if let maxIndex = selectedIndices.max(), maxIndex < displayItems.count - 1 {
                selectedIndices = [maxIndex + 1]
                ensureVisible(index: maxIndex + 1)
                needsDisplay = true
            }
            
        case 126: // Up arrow
            if let minIndex = selectedIndices.min(), minIndex > 0 {
                selectedIndices = [minIndex - 1]
                ensureVisible(index: minIndex - 1)
                needsDisplay = true
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
        // Check source first - local files don't need async loading
        if case .local = currentSource {
            loadLocalData()
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
                    NSLog("PlexBrowserView: Loading shows...")
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
                    
                case .search:
                    if !searchQuery.isEmpty {
                        // Search in the current library
                        searchResults = try await plexManager.search(query: searchQuery)
                        buildSearchItems()
                    } else {
                        displayItems = []
                    }
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
        case .movies, .shows:
            // Video modes not supported for local content - show empty
            displayItems = []
        }
        
        needsDisplay = true
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
            case .movies, .shows:
                displayItems = []
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
            case .search:
                buildSearchItems()
            }
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
    }
}
