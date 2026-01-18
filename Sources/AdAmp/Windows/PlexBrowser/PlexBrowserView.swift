import AppKit

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
    
    /// Current browse mode
    private var browseMode: PlexBrowseMode = .artists
    
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
    
    /// Expanded artists for hierarchical view
    private var expandedArtists: Set<String> = []
    
    /// Expanded albums (for showing tracks)
    private var expandedAlbums: Set<String> = []
    
    /// Loading state
    private var isLoading: Bool = false
    
    /// Error message
    private var errorMessage: String?
    
    /// Cached data - Music
    private var cachedArtists: [PlexArtist] = []
    private var cachedAlbums: [PlexAlbum] = []
    private var cachedTracks: [PlexTrack] = []
    private var artistAlbums: [String: [PlexAlbum]] = [:]
    private var albumTracks: [String: [PlexTrack]] = [:]
    
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
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: SkinRenderer.PlexBrowserButtonType?
    
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
        
        // Initial data load
        reloadData()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopLoadingAnimation()
    }
    
    // MARK: - Scaling Support
    
    /// Get the original window size for drawing and hit testing
    private var originalWindowSize: NSSize {
        if isShadeMode {
            // Shade mode: width scales with window, height is fixed
            return NSSize(width: SkinElements.PlexBrowser.minSize.width, height: SkinElements.PlexBrowser.shadeHeight)
        } else {
            return SkinElements.PlexBrowser.minSize
        }
    }
    
    /// Calculate scale factor based on current bounds vs original (base) size
    private var scaleFactor: CGFloat {
        let originalSize = originalWindowSize
        let scaleX = bounds.width / originalSize.width
        let scaleY = bounds.height / originalSize.height
        return min(scaleX, scaleY)
    }
    
    /// Convert a point from view coordinates to original (unscaled) Winamp coordinates
    private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
        let scale = scaleFactor
        let originalSize = originalWindowSize
        
        // Calculate offset (centering) if scaled
        let scaledWidth = originalSize.width * scale
        let scaledHeight = originalSize.height * scale
        let offsetX = (bounds.width - scaledWidth) / 2
        let offsetY = (bounds.height - scaledHeight) / 2
        
        // Transform point back to original coordinates
        let x = (point.x - offsetX) / scale
        // Convert from macOS coords (origin bottom-left) to Winamp coords (origin top-left)
        let y = originalSize.height - ((point.y - offsetY) / scale)
        
        return NSPoint(x: x, y: y)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let originalSize = originalWindowSize
        let scale = scaleFactor
        
        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())
        let isActive = window?.isKeyWindow ?? true
        
        // Flip coordinate system to match Winamp's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // Apply scaling for resized window
        if scale != 1.0 {
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            let offsetY = (bounds.height - scaledHeight) / 2
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)
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
            let colors = skin?.playlistColors ?? .default
            
            // Draw server/library selector bar
            drawServerBar(in: context, drawBounds: drawBounds, colors: colors)
            
            // Draw tab bar
            drawTabBar(in: context, drawBounds: drawBounds, colors: colors)
            
            // Draw search bar (only in search mode)
            if browseMode == .search {
                drawSearchBar(in: context, drawBounds: drawBounds, colors: colors)
            }
            
            // Draw list area or connection status
            if !PlexManager.shared.isLinked {
                drawNotLinkedState(in: context, drawBounds: drawBounds, colors: colors)
            } else if isLoading {
                drawLoadingState(in: context, drawBounds: drawBounds, colors: colors)
            } else if let error = errorMessage {
                drawErrorState(in: context, drawBounds: drawBounds, message: error, colors: colors)
            } else {
                drawListArea(in: context, drawBounds: drawBounds, colors: colors)
            }
            
            // Draw status bar text
            drawStatusBarText(in: context, drawBounds: drawBounds, colors: colors)
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
    
    // MARK: - Content Drawing (in Winamp coordinates, with counter-flip for text)
    
    private func drawServerBar(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors) {
        let barY = Layout.titleBarHeight
        let barRect = NSRect(x: Layout.leftBorder, y: barY,
                            width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                            height: Layout.serverBarHeight)
        
        // Background
        colors.normalBackground.withAlphaComponent(0.6).setFill()
        context.fill(barRect)
        
        let manager = PlexManager.shared
        
        // Counter-flip for text rendering
        context.saveGState()
        let centerY = barRect.midY
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        if manager.isLinked {
            // Server dropdown
            let serverText = manager.currentServer?.name ?? "Select Server"
            let serverAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: colors.normalText,
                .font: NSFont.systemFont(ofSize: 10)
            ]
            let serverLabel = "Server: \(serverText) ▼"
            serverLabel.draw(at: NSPoint(x: barRect.minX + 4, y: barRect.minY + 6), withAttributes: serverAttrs)
            
            // Refresh button (center)
            let refreshLabel = "↻ Refresh"
            let refreshAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: colors.currentText,
                .font: NSFont.systemFont(ofSize: 10)
            ]
            let refreshSize = refreshLabel.size(withAttributes: refreshAttrs)
            let refreshX = barRect.midX - refreshSize.width / 2
            refreshLabel.draw(at: NSPoint(x: refreshX, y: barRect.minY + 6), withAttributes: refreshAttrs)
            
            // Library dropdown (right side)
            let libraryText: String
            if browseMode.isVideoMode {
                libraryText = manager.currentVideoLibrary?.title ?? "Select Video Library"
            } else {
                libraryText = manager.currentLibrary?.title ?? "Select Library"
            }
            let libraryLabel = "Library: \(libraryText) ▼"
            let librarySize = libraryLabel.size(withAttributes: serverAttrs)
            libraryLabel.draw(at: NSPoint(x: barRect.maxX - librarySize.width - 4, y: barRect.minY + 6),
                            withAttributes: serverAttrs)
        } else {
            // Not linked message
            let linkText = "Click to link your Plex account"
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(calibratedRed: 0.9, green: 0.6, blue: 0.1, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10)
            ]
            let linkSize = linkText.size(withAttributes: linkAttrs)
            linkText.draw(at: NSPoint(x: barRect.midX - linkSize.width / 2, y: barRect.minY + 6),
                         withAttributes: linkAttrs)
        }
        
        context.restoreGState()
    }
    
    private func drawTabBar(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors) {
        let tabBarY = Layout.titleBarHeight + Layout.serverBarHeight
        let tabBarRect = NSRect(x: Layout.leftBorder, y: tabBarY,
                               width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                               height: Layout.tabBarHeight)
        
        // Background
        colors.normalBackground.withAlphaComponent(0.4).setFill()
        context.fill(tabBarRect)
        
        // Draw tabs
        let tabWidth = tabBarRect.width / CGFloat(PlexBrowseMode.allCases.count)
        
        for (index, mode) in PlexBrowseMode.allCases.enumerated() {
            let tabRect = NSRect(x: tabBarRect.minX + CGFloat(index) * tabWidth, y: tabBarY,
                                width: tabWidth, height: Layout.tabBarHeight)
            
            // Selected tab indicated by white text only (no background fill)
            
            // Tab title (counter-flip for text)
            context.saveGState()
            let centerY = tabRect.midY
            context.translateBy(x: 0, y: centerY)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -centerY)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: mode == browseMode ? colors.currentText : colors.normalText.withAlphaComponent(0.6),
                .font: NSFont.systemFont(ofSize: 10, weight: mode == browseMode ? .semibold : .regular)
            ]
            let titleSize = mode.title.size(withAttributes: attrs)
            let titlePoint = NSPoint(x: tabRect.midX - titleSize.width / 2,
                                    y: tabRect.midY - titleSize.height / 2)
            mode.title.draw(at: titlePoint, withAttributes: attrs)
            
            context.restoreGState()
        }
    }
    
    private func drawSearchBar(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors) {
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
        
        // Counter-flip for text
        context.saveGState()
        let centerY = searchRect.midY
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        // Search icon
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: colors.normalText.withAlphaComponent(0.6),
            .font: NSFont.systemFont(ofSize: 10)
        ]
        "🔍".draw(at: NSPoint(x: searchRect.minX + 6, y: searchRect.midY - 6), withAttributes: iconAttrs)
        
        // Search text or placeholder
        let textAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: searchQuery.isEmpty ? colors.normalText.withAlphaComponent(0.5) : colors.normalText,
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let displayText = searchQuery.isEmpty ? "Type to search..." : searchQuery
        displayText.draw(at: NSPoint(x: searchRect.minX + 24, y: searchRect.midY - 6), withAttributes: textAttrs)
        
        // Draw cursor if focused
        if isFocused {
            let textSize = (searchQuery.isEmpty ? "" : searchQuery).size(withAttributes: textAttrs)
            let cursorX = searchRect.minX + 24 + textSize.width + 1
            colors.normalText.setFill()
            context.fill(CGRect(x: cursorX, y: searchRect.midY - 5, width: 1, height: 10))
        }
        
        context.restoreGState()
    }
    
    private func drawNotLinkedState(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors) {
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
    
    private func drawLoadingState(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors) {
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
    
    private func drawErrorState(in context: CGContext, drawBounds: NSRect, message: String, colors: PlaylistColors) {
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
            .foregroundColor: NSColor.systemRed,
            .font: NSFont.systemFont(ofSize: 11)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2),
                    withAttributes: attrs)
        
        context.restoreGState()
    }
    
    private func drawListArea(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors) {
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
                let infoAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: colors.normalText.withAlphaComponent(0.6),
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
        drawAlphabetIndex(in: context, rect: alphabetRect, colors: colors)
    }
    
    private func drawAlphabetIndex(in context: CGContext, rect: NSRect, colors: PlaylistColors) {
        // Background
        colors.normalBackground.withAlphaComponent(0.3).setFill()
        context.fill(rect)
        
        // Calculate letter height based on available space
        let letterCount = CGFloat(alphabetLetters.count)
        let letterHeight = rect.height / letterCount
        let fontSize = min(9, letterHeight * 0.8)
        
        // Build set of first letters that exist in current items
        var availableLetters = Set<String>()
        for item in displayItems {
            if let firstChar = item.title.uppercased().first {
                if firstChar.isLetter {
                    availableLetters.insert(String(firstChar))
                } else {
                    availableLetters.insert("#")
                }
            }
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
    
    private func drawStatusBarText(in context: CGContext, drawBounds: NSRect, colors: PlaylistColors) {
        let statusY = drawBounds.height - Layout.statusBarHeight
        let statusRect = NSRect(x: Layout.leftBorder, y: statusY,
                               width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
                               height: Layout.statusBarHeight)
        
        // Counter-flip for text
        context.saveGState()
        let centerY = statusRect.midY
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        let manager = PlexManager.shared
        let statusText: String
        
        if !manager.isLinked {
            statusText = "Not linked"
        } else if isLoading {
            statusText = "Loading..."
        } else {
            let serverName = manager.currentServer?.name ?? "Unknown"
            statusText = "Connected to: \(serverName) • \(displayItems.count) items"
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: colors.normalText.withAlphaComponent(0.6),
            .font: NSFont.systemFont(ofSize: 9)
        ]
        statusText.draw(at: NSPoint(x: statusRect.minX + 4, y: statusRect.midY - 5), withAttributes: attrs)
        
        context.restoreGState()
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
    
    // MARK: - Public Methods
    
    func reloadData() {
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
    private func hitTestCloseButton(at winampPoint: NSPoint) -> Bool {
        let originalSize = originalWindowSize
        let closeRect = NSRect(x: originalSize.width - SkinElements.PlexBrowser.TitleBarButtons.closeOffset - 9,
                               y: 3, width: 9, height: 9)
        return closeRect.contains(winampPoint)
    }
    
    /// Check if point hits shade button
    private func hitTestShadeButton(at winampPoint: NSPoint) -> Bool {
        let originalSize = originalWindowSize
        let shadeRect = NSRect(x: originalSize.width - SkinElements.PlexBrowser.TitleBarButtons.shadeOffset - 9,
                               y: 3, width: 9, height: 9)
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
        
        let tabWidth = (originalWindowSize.width - Layout.leftBorder - Layout.rightBorder) / CGFloat(PlexBrowseMode.allCases.count)
        let relativeX = winampPoint.x - Layout.leftBorder
        if relativeX >= 0 && relativeX < tabWidth * CGFloat(PlexBrowseMode.allCases.count) {
            return Int(relativeX / tabWidth)
        }
        return nil
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
        
        // Check for refresh button click (center area)
        let refreshLabel = "↻ Refresh"
        let refreshAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let refreshSize = refreshLabel.size(withAttributes: refreshAttrs)
        let refreshX = originalSize.width / 2 - refreshSize.width / 2
        let refreshEndX = refreshX + refreshSize.width
        
        if winampPoint.x >= refreshX - 10 && winampPoint.x < refreshEndX + 10 {
            refreshData()
        } else if winampPoint.x < originalSize.width / 3 {
            // Left third = server selection
            showServerMenu(at: event)
        } else if winampPoint.x > originalSize.width * 2 / 3 {
            // Right third = library selection
            showLibraryMenu(at: event)
        }
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
    
    private func scrollToLetter(_ letter: String) {
        for (index, item) in displayItems.enumerated() {
            let firstChar = item.title.uppercased().first.map(String.init) ?? ""
            
            let itemLetter: String
            if let char = firstChar.first, char.isLetter {
                itemLetter = firstChar
            } else {
                itemLetter = "#"
            }
            
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
        
        // Handle window dragging
        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y
            
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY
            
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
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
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
        
        let isVideoMode = browseMode.isVideoMode
        let libraries = isVideoMode
            ? PlexManager.shared.availableVideoLibraries
            : PlexManager.shared.availableLibraries
        let currentLibraryId = isVideoMode
            ? PlexManager.shared.currentVideoLibrary?.id
            : PlexManager.shared.currentLibrary?.id
        
        if libraries.isEmpty {
            let noLibraries = NSMenuItem(title: isVideoMode ? "No video libraries available" : "No music libraries available", action: nil, keyEquivalent: "")
            noLibraries.isEnabled = false
            menu.addItem(noLibraries)
        } else {
            for library in libraries {
                let item = NSMenuItem(title: library.title, action: #selector(selectLibrary(_:)), keyEquivalent: "")
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
        
        if library.isVideoLibrary {
            PlexManager.shared.selectVideoLibrary(library)
            cachedMovies = []
            cachedShows = []
            showSeasons = [:]
            seasonEpisodes = [:]
            expandedShows = []
            expandedSeasons = []
        } else {
            PlexManager.shared.selectLibrary(library)
            cachedArtists = []
            cachedAlbums = []
            cachedTracks = []
            artistAlbums = [:]
            albumTracks = [:]
            expandedArtists = []
            expandedAlbums = []
        }
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
        isLoading = true
        errorMessage = nil
        startLoadingAnimation()
        needsDisplay = true
        
        Task { @MainActor in
            do {
                switch browseMode {
                case .artists:
                    if cachedArtists.isEmpty {
                        cachedArtists = try await PlexManager.shared.fetchArtists()
                    }
                    buildArtistItems()
                    
                case .albums:
                    if cachedAlbums.isEmpty {
                        cachedAlbums = try await PlexManager.shared.fetchAlbums(offset: 0, limit: 500)
                    }
                    buildAlbumItems()
                    
                case .tracks:
                    if cachedTracks.isEmpty {
                        cachedTracks = try await PlexManager.shared.fetchTracks(offset: 0, limit: 500)
                    }
                    buildTrackItems()
                    
                case .movies:
                    NSLog("PlexBrowserView: Loading movies...")
                    if cachedMovies.isEmpty {
                        cachedMovies = try await PlexManager.shared.fetchMovies(offset: 0, limit: 500)
                        NSLog("PlexBrowserView: Loaded %d movies", cachedMovies.count)
                    }
                    buildMovieItems()
                    NSLog("PlexBrowserView: Built %d movie items", displayItems.count)
                    
                case .shows:
                    NSLog("PlexBrowserView: Loading shows...")
                    if cachedShows.isEmpty {
                        cachedShows = try await PlexManager.shared.fetchShows(offset: 0, limit: 500)
                        NSLog("PlexBrowserView: Loaded %d shows", cachedShows.count)
                    }
                    buildShowItems()
                    NSLog("PlexBrowserView: Built %d show items", displayItems.count)
                    
                case .search:
                    if !searchQuery.isEmpty {
                        searchResults = try await PlexManager.shared.search(query: searchQuery)
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
    
    private func buildArtistItems() {
        displayItems.removeAll()
        
        for artist in cachedArtists {
            let isExpanded = expandedArtists.contains(artist.id)
            
            displayItems.append(PlexDisplayItem(
                id: artist.id,
                title: artist.title,
                info: "\(artist.albumCount) albums",
                indentLevel: 0,
                hasChildren: true,
                type: .artist(artist)
            ))
            
            if isExpanded, let albums = artistAlbums[artist.id] {
                for album in albums {
                    displayItems.append(PlexDisplayItem(
                        id: album.id,
                        title: album.title,
                        info: album.year.map { String($0) },
                        indentLevel: 1,
                        hasChildren: true,
                        type: .album(album)
                    ))
                    
                    if expandedAlbums.contains(album.id), let tracks = albumTracks[album.id] {
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
        }
    }
    
    private func buildAlbumItems() {
        displayItems = cachedAlbums.map { album in
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
        displayItems = cachedTracks.map { track in
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
            displayItems.append(PlexDisplayItem(
                id: "header-artists",
                title: "Artists (\(results.artists.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for artist in results.artists {
                displayItems.append(PlexDisplayItem(
                    id: artist.id,
                    title: artist.title,
                    info: "\(artist.albumCount) albums",
                    indentLevel: 1,
                    hasChildren: false,
                    type: .artist(artist)
                ))
            }
        }
        
        if !results.albums.isEmpty {
            displayItems.append(PlexDisplayItem(
                id: "header-albums",
                title: "Albums (\(results.albums.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for album in results.albums {
                displayItems.append(PlexDisplayItem(
                    id: album.id,
                    title: "\(album.parentTitle ?? "") - \(album.title)",
                    info: album.year.map { String($0) },
                    indentLevel: 1,
                    hasChildren: false,
                    type: .album(album)
                ))
            }
        }
        
        if !results.tracks.isEmpty {
            displayItems.append(PlexDisplayItem(
                id: "header-tracks",
                title: "Tracks (\(results.tracks.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for track in results.tracks {
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
            displayItems.append(PlexDisplayItem(
                id: "header-movies",
                title: "Movies (\(results.movies.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for movie in results.movies {
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
            displayItems.append(PlexDisplayItem(
                id: "header-shows",
                title: "TV Shows (\(results.shows.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for show in results.shows {
                displayItems.append(PlexDisplayItem(
                    id: show.id,
                    title: show.title,
                    info: show.year.map { String($0) },
                    indentLevel: 1,
                    hasChildren: false,
                    type: .show(show)
                ))
            }
        }
        
        if !results.episodes.isEmpty {
            displayItems.append(PlexDisplayItem(
                id: "header-episodes",
                title: "Episodes (\(results.episodes.count))",
                info: nil,
                indentLevel: 0,
                hasChildren: false,
                type: .header
            ))
            for episode in results.episodes {
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
    
    private func isExpanded(_ item: PlexDisplayItem) -> Bool {
        switch item.type {
        case .artist:
            return expandedArtists.contains(item.id)
        case .album:
            return expandedAlbums.contains(item.id)
        case .show:
            return expandedShows.contains(item.id)
        case .season:
            return expandedSeasons.contains(item.id)
        default:
            return false
        }
    }
    
    private func toggleExpand(_ item: PlexDisplayItem) {
        switch item.type {
        case .artist(let artist):
            if expandedArtists.contains(artist.id) {
                expandedArtists.remove(artist.id)
            } else {
                expandedArtists.insert(artist.id)
                if artistAlbums[artist.id] == nil {
                    Task { @MainActor in
                        do {
                            let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                            artistAlbums[artist.id] = albums
                            buildArtistItems()
                            needsDisplay = true
                        } catch {
                            print("Failed to load albums: \(error)")
                        }
                    }
                    return
                }
            }
            buildArtistItems()
            
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
                            buildArtistItems()
                            needsDisplay = true
                        } catch {
                            print("Failed to load tracks: \(error)")
                        }
                    }
                    return
                }
            }
            buildArtistItems()
            
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
                            buildShowItems()
                            needsDisplay = true
                        } catch {
                            print("Failed to load seasons: \(error)")
                        }
                    }
                    return
                }
            }
            buildShowItems()
            
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
                            buildShowItems()
                            needsDisplay = true
                        } catch {
                            print("Failed to load episodes: \(error)")
                        }
                    }
                    return
                }
            }
            buildShowItems()
            
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
    }
}
