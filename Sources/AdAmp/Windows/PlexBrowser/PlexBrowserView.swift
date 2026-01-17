import AppKit

/// Browse mode for the Plex browser
enum PlexBrowseMode: Int, CaseIterable {
    case artists = 0
    case albums = 1
    case tracks = 2
    case search = 3
    
    var title: String {
        switch self {
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .tracks: return "Tracks"
        case .search: return "Search"
        }
    }
}

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
    
    /// Cached data
    private var cachedArtists: [PlexArtist] = []
    private var cachedAlbums: [PlexAlbum] = []
    private var cachedTracks: [PlexTrack] = []
    private var artistAlbums: [String: [PlexAlbum]] = [:]
    private var albumTracks: [String: [PlexTrack]] = [:]
    private var searchResults: PlexSearchResults?
    
    // MARK: - Layout Constants
    
    private struct Layout {
        static let titleBarHeight: CGFloat = 20
        static let serverBarHeight: CGFloat = 24
        static let tabBarHeight: CGFloat = 24
        static let searchBarHeight: CGFloat = 26
        static let statusBarHeight: CGFloat = 20
        static let padding: CGFloat = 3
        static let scrollbarWidth: CGFloat = 14
        static let alphabetWidth: CGFloat = 16
    }
    
    /// Alphabet index for quick navigation
    private let alphabetLetters = ["#"] + (65...90).map { String(UnicodeScalar($0)) } // # A-Z
    
    // MARK: - Colors (Winamp-inspired dark theme)
    
    private struct Colors {
        static let background = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        static let titleBar = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)
        static let tabBackground = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        static let tabSelected = NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.35, alpha: 1.0)
        static let listBackground = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.1, alpha: 1.0)
        static let selectedBackground = NSColor(calibratedRed: 0.15, green: 0.25, blue: 0.4, alpha: 1.0)
        static let hoverBackground = NSColor(calibratedRed: 0.1, green: 0.15, blue: 0.25, alpha: 1.0)
        static let textNormal = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.0, alpha: 1.0)  // Classic green
        static let textSelected = NSColor.white
        static let textDim = NSColor(calibratedRed: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        static let accent = NSColor(calibratedRed: 0.3, green: 0.6, blue: 1.0, alpha: 1.0)
        static let plexOrange = NSColor(calibratedRed: 0.9, green: 0.6, blue: 0.1, alpha: 1.0)
        static let scrollbar = NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.35, alpha: 1.0)
        static let scrollbarThumb = NSColor(calibratedRed: 0.4, green: 0.4, blue: 0.5, alpha: 1.0)
        static let border = NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.3, alpha: 1.0)
    }
    
    // MARK: - Flipped Coordinates
    
    override var isFlipped: Bool { true }
    
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
        
        // Initial data load
        reloadData()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Get skin colors
        let skin = WindowManager.shared.currentSkin
        let bgColor = skin?.playlistColors.normalBackground ?? Colors.listBackground
        
        // Draw background
        bgColor.setFill()
        context.fill(bounds)
        
        // Draw title bar
        drawTitleBar(context: context)
        
        // Draw server/library selector bar
        drawServerBar(context: context)
        
        // Draw tab bar
        drawTabBar(context: context)
        
        // Draw search bar (only in search mode)
        if browseMode == .search {
            drawSearchBar(context: context)
        }
        
        // Draw list area or connection status
        if !PlexManager.shared.isLinked {
            drawNotLinkedState(context: context)
        } else if isLoading {
            drawLoadingState(context: context)
        } else if let error = errorMessage {
            drawErrorState(context: context, message: error)
        } else {
            drawListArea(context: context)
        }
        
        // Draw status bar
        drawStatusBar(context: context)
        
        // Draw border
        Colors.border.setStroke()
        context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    }
    
    private func drawTitleBar(context: CGContext) {
        let titleRect = NSRect(x: 0, y: 0, width: bounds.width, height: Layout.titleBarHeight)
        
        // Gradient background
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.15, green: 0.1, blue: 0.2, alpha: 1.0),
            Colors.titleBar
        ])
        gradient?.draw(in: titleRect, angle: 90)
        
        // Plex icon/title
        let title = "PLEX BROWSER"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Colors.plexOrange,
            .font: NSFont.boldSystemFont(ofSize: 10)
        ]
        let titleSize = title.size(withAttributes: attrs)
        let titlePoint = NSPoint(x: (bounds.width - titleSize.width) / 2,
                                 y: Layout.titleBarHeight / 2 - titleSize.height / 2 + 1)
        title.draw(at: titlePoint, withAttributes: attrs)
        
        // Close button
        let closeRect = NSRect(x: bounds.width - 14, y: 5, width: 10, height: 10)
        NSColor.red.withAlphaComponent(0.8).setFill()
        context.fillEllipse(in: closeRect)
    }
    
    private func drawServerBar(context: CGContext) {
        let barY = Layout.titleBarHeight
        let barRect = NSRect(x: 0, y: barY, width: bounds.width, height: Layout.serverBarHeight)
        
        Colors.tabBackground.setFill()
        context.fill(barRect)
        
        let manager = PlexManager.shared
        
        if manager.isLinked {
            // Server dropdown
            let serverText = manager.currentServer?.name ?? "Select Server"
            let serverAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: Colors.textNormal,
                .font: NSFont.systemFont(ofSize: 10)
            ]
            let serverLabel = "Server: \(serverText) ▼"
            serverLabel.draw(at: NSPoint(x: Layout.padding + 4, y: barY + 6), withAttributes: serverAttrs)
            
            // Library dropdown (right side)
            let libraryText = manager.currentLibrary?.title ?? "Select Library"
            let libraryLabel = "Library: \(libraryText) ▼"
            let librarySize = libraryLabel.size(withAttributes: serverAttrs)
            libraryLabel.draw(at: NSPoint(x: bounds.width - librarySize.width - Layout.padding - 4, y: barY + 6),
                            withAttributes: serverAttrs)
        } else {
            // Not linked message
            let linkText = "Click to link your Plex account"
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: Colors.plexOrange,
                .font: NSFont.systemFont(ofSize: 10)
            ]
            let linkSize = linkText.size(withAttributes: linkAttrs)
            linkText.draw(at: NSPoint(x: (bounds.width - linkSize.width) / 2, y: barY + 6),
                         withAttributes: linkAttrs)
        }
    }
    
    private func drawTabBar(context: CGContext) {
        let tabBarY = Layout.titleBarHeight + Layout.serverBarHeight
        let tabBarRect = NSRect(x: 0, y: tabBarY, width: bounds.width, height: Layout.tabBarHeight)
        
        Colors.tabBackground.setFill()
        context.fill(tabBarRect)
        
        // Draw tabs
        let tabWidth = bounds.width / CGFloat(PlexBrowseMode.allCases.count)
        
        for (index, mode) in PlexBrowseMode.allCases.enumerated() {
            let tabRect = NSRect(x: CGFloat(index) * tabWidth, y: tabBarY,
                                width: tabWidth, height: Layout.tabBarHeight)
            
            if mode == browseMode {
                Colors.tabSelected.setFill()
                context.fill(tabRect)
                
                // Accent line at bottom
                Colors.plexOrange.setFill()
                context.fill(NSRect(x: tabRect.minX + 2, y: tabRect.maxY - 2,
                                   width: tabRect.width - 4, height: 2))
            }
            
            // Tab title
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: mode == browseMode ? Colors.textSelected : Colors.textDim,
                .font: NSFont.systemFont(ofSize: 10, weight: mode == browseMode ? .semibold : .regular)
            ]
            let titleSize = mode.title.size(withAttributes: attrs)
            let titlePoint = NSPoint(x: tabRect.midX - titleSize.width / 2,
                                    y: tabRect.midY - titleSize.height / 2)
            mode.title.draw(at: titlePoint, withAttributes: attrs)
        }
    }
    
    private func drawSearchBar(context: CGContext) {
        let searchY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        let searchRect = NSRect(x: Layout.padding, y: searchY + 3,
                               width: bounds.width - Layout.padding * 2, height: Layout.searchBarHeight - 6)
        
        // Search field background - highlight if focused
        let isFocused = window?.firstResponder === self
        let bgColor = isFocused 
            ? NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.25, alpha: 1.0)
            : NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: searchRect, xRadius: 3, yRadius: 3)
        path.fill()
        
        // Focus border
        if isFocused {
            Colors.textSelected.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        
        // Search icon
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Colors.textDim,
            .font: NSFont.systemFont(ofSize: 10)
        ]
        "🔍".draw(at: NSPoint(x: searchRect.minX + 6, y: searchRect.midY - 6), withAttributes: iconAttrs)
        
        // Search text or placeholder
        let textAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: searchQuery.isEmpty ? Colors.textDim : Colors.textNormal,
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let displayText = searchQuery.isEmpty ? "Type to search..." : searchQuery
        let textPoint = NSPoint(x: searchRect.minX + 24, y: searchRect.midY - 6)
        displayText.draw(at: textPoint, withAttributes: textAttrs)
        
        // Draw cursor if focused and has text (or empty)
        if isFocused {
            let textSize = (searchQuery.isEmpty ? "" : searchQuery).size(withAttributes: textAttrs)
            let cursorX = searchRect.minX + 24 + textSize.width + 1
            Colors.textNormal.setFill()
            context.fill(CGRect(x: cursorX, y: searchRect.midY - 5, width: 1, height: 10))
        }
    }
    
    private func drawNotLinkedState(context: CGContext) {
        let listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        let listRect = NSRect(x: 0, y: listY, width: bounds.width, height: listHeight)
        
        Colors.listBackground.setFill()
        context.fill(listRect)
        
        // Center message
        let message = "Link your Plex account to browse your music library"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Colors.textDim,
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: listY + listHeight / 2 - size.height / 2),
                    withAttributes: attrs)
        
        // Link button hint
        let hint = "Click the server bar above to link"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Colors.plexOrange,
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        hint.draw(at: NSPoint(x: (bounds.width - hintSize.width) / 2, y: listY + listHeight / 2 - size.height / 2 - 20),
                 withAttributes: hintAttrs)
    }
    
    private func drawLoadingState(context: CGContext) {
        let listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        let listRect = NSRect(x: 0, y: listY, width: bounds.width, height: listHeight)
        
        Colors.listBackground.setFill()
        context.fill(listRect)
        
        let message = "Loading..."
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Colors.textNormal,
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: listY + listHeight / 2 - size.height / 2),
                    withAttributes: attrs)
    }
    
    private func drawErrorState(context: CGContext, message: String) {
        let listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        let listRect = NSRect(x: 0, y: listY, width: bounds.width, height: listHeight)
        
        Colors.listBackground.setFill()
        context.fill(listRect)
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.systemRed,
            .font: NSFont.systemFont(ofSize: 11)
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: listY + listHeight / 2 - size.height / 2),
                    withAttributes: attrs)
    }
    
    private func drawListArea(context: CGContext) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        
        // Account for alphabet index on the right
        let alphabetWidth = Layout.alphabetWidth
        let listRect = NSRect(x: Layout.padding, y: listY,
                             width: bounds.width - Layout.padding * 2 - Layout.scrollbarWidth - alphabetWidth,
                             height: listHeight)
        
        // Get skin colors
        let skin = WindowManager.shared.currentSkin
        let listBgColor = skin?.playlistColors.normalBackground ?? Colors.listBackground
        let normalTextColor = skin?.playlistColors.normalText ?? Colors.textNormal
        let selectedTextColor = skin?.playlistColors.currentText ?? Colors.textSelected
        let selectedBgColor = skin?.playlistColors.selectedBackground ?? Colors.selectedBackground
        
        // List background
        listBgColor.setFill()
        context.fill(listRect)
        
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
                selectedBgColor.setFill()
                context.fill(itemRect)
            }
            
            // Item content
            let indent = CGFloat(item.indentLevel) * 16
            let textX = itemRect.minX + indent + 4
            
            // Expand/collapse indicator for hierarchical items
            if item.hasChildren {
                let expanded = isExpanded(item)
                let indicator = expanded ? "▼" : "▶"
                let indicatorAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: normalTextColor.withAlphaComponent(0.6),
                    .font: NSFont.systemFont(ofSize: 8)
                ]
                indicator.draw(at: NSPoint(x: textX - 12, y: itemRect.midY - 5), withAttributes: indicatorAttrs)
            }
            
            // Main text
            let textColor = selectedIndices.contains(index) ? selectedTextColor : normalTextColor
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
                    .foregroundColor: normalTextColor.withAlphaComponent(0.6),
                    .font: NSFont.systemFont(ofSize: 9)
                ]
                let infoSize = info.size(withAttributes: infoAttrs)
                info.draw(at: NSPoint(x: itemRect.maxX - infoSize.width - 4, y: itemRect.midY - infoSize.height / 2),
                         withAttributes: infoAttrs)
            }
        }
        
        context.restoreGState()
        
        // Draw alphabet index
        let alphabetRect = NSRect(x: bounds.width - Layout.padding - Layout.scrollbarWidth - alphabetWidth,
                                 y: listY, width: alphabetWidth, height: listHeight)
        drawAlphabetIndex(in: alphabetRect, context: context)
        
        // Draw scrollbar
        let scrollbarRect = NSRect(x: bounds.width - Layout.padding - Layout.scrollbarWidth,
                                  y: listY, width: Layout.scrollbarWidth, height: listHeight)
        drawScrollbar(in: scrollbarRect, context: context, itemCount: displayItems.count, listHeight: listHeight)
    }
    
    private func drawAlphabetIndex(in rect: NSRect, context: CGContext) {
        let skin = WindowManager.shared.currentSkin
        let normalColor = skin?.playlistColors.normalText ?? Colors.textNormal
        let accentColor = skin?.playlistColors.currentText ?? Colors.textSelected
        
        // Background
        Colors.tabBackground.withAlphaComponent(0.5).setFill()
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
            let color = hasItems ? accentColor : normalColor.withAlphaComponent(0.3)
            
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
    
    private func drawScrollbar(in rect: NSRect, context: CGContext, itemCount: Int, listHeight: CGFloat) {
        Colors.scrollbar.setFill()
        context.fill(rect)
        
        let totalHeight = CGFloat(itemCount) * itemHeight
        if totalHeight <= listHeight { return }
        
        let thumbHeight = max(30, rect.height * (listHeight / totalHeight))
        let scrollRange = totalHeight - listHeight
        let scrollProgress = scrollOffset / scrollRange
        let thumbY = rect.minY + (rect.height - thumbHeight) * scrollProgress
        
        let thumbRect = NSRect(x: rect.minX + 2, y: thumbY, width: rect.width - 4, height: thumbHeight)
        Colors.scrollbarThumb.setFill()
        let thumbPath = NSBezierPath(roundedRect: thumbRect, xRadius: 3, yRadius: 3)
        thumbPath.fill()
    }
    
    private func drawStatusBar(context: CGContext) {
        let statusY = bounds.height - Layout.statusBarHeight
        let statusRect = NSRect(x: 0, y: statusY, width: bounds.width, height: Layout.statusBarHeight)
        
        Colors.tabBackground.setFill()
        context.fill(statusRect)
        
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
            .foregroundColor: Colors.textDim,
            .font: NSFont.systemFont(ofSize: 9)
        ]
        statusText.draw(at: NSPoint(x: Layout.padding + 4, y: statusY + 5), withAttributes: attrs)
    }
    
    // MARK: - Data Management
    
    func reloadData() {
        guard PlexManager.shared.isLinked else {
            displayItems = []
            needsDisplay = true
            return
        }
        
        loadDataForCurrentMode()
    }
    
    func skinDidChange() {
        needsDisplay = true
    }
    
    @objc private func plexStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadData()
        }
    }
    
    private func loadDataForCurrentMode() {
        isLoading = true
        errorMessage = nil
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
                        // Debug: Check if tracks have media info
                        for track in cachedTracks.prefix(3) {
                            print("Track: \(track.title), media count: \(track.media.count), partKey: \(track.partKey ?? "nil")")
                        }
                    }
                    buildTrackItems()
                    
                case .search:
                    if !searchQuery.isEmpty {
                        searchResults = try await PlexManager.shared.search(query: searchQuery)
                        buildSearchItems()
                    } else {
                        displayItems = []
                    }
                }
                
                isLoading = false
                errorMessage = nil
            } catch {
                isLoading = false
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
                    
                    // Show tracks if album is expanded
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
    
    private func buildSearchItems() {
        displayItems.removeAll()
        guard let results = searchResults else { return }
        
        // Artists
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
        
        // Albums
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
        
        // Tracks
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
    }
    
    private func isExpanded(_ item: PlexDisplayItem) -> Bool {
        switch item.type {
        case .artist:
            return expandedArtists.contains(item.id)
        case .album:
            return expandedAlbums.contains(item.id)
        default:
            return false
        }
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // With isFlipped=true, point is already in flipped coordinates
        let winampPoint = point
        
        // Check close button
        let closeRect = NSRect(x: bounds.width - 14, y: 5, width: 10, height: 10)
        if closeRect.contains(winampPoint) {
            window?.close()
            return
        }
        
        // Check server bar (for linking or server/library selection)
        let serverBarY = Layout.titleBarHeight
        if winampPoint.y >= serverBarY && winampPoint.y < serverBarY + Layout.serverBarHeight {
            if !PlexManager.shared.isLinked {
                controller?.showLinkSheet()
            } else {
                // Left half = server selection, right half = library selection
                if winampPoint.x < bounds.width / 2 {
                    showServerMenu(at: event)
                } else {
                    showLibraryMenu(at: event)
                }
            }
            return
        }
        
        // Check tab bar
        let tabY = Layout.titleBarHeight + Layout.serverBarHeight
        if winampPoint.y >= tabY && winampPoint.y < tabY + Layout.tabBarHeight {
            let tabWidth = bounds.width / CGFloat(PlexBrowseMode.allCases.count)
            let tabIndex = Int(winampPoint.x / tabWidth)
            if let newMode = PlexBrowseMode(rawValue: tabIndex) {
                browseMode = newMode
                selectedIndices.removeAll()
                scrollOffset = 0
                loadDataForCurrentMode()
                
                // Make view first responder for keyboard input (especially search)
                window?.makeFirstResponder(self)
            }
            return
        }
        
        // Check search bar click (make first responder for typing)
        if browseMode == .search {
            let searchY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
            if winampPoint.y >= searchY && winampPoint.y < searchY + Layout.searchBarHeight {
                window?.makeFirstResponder(self)
                return
            }
        }
        
        // Check list area
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        
        // Check alphabet index click
        let alphabetX = bounds.width - Layout.padding - Layout.scrollbarWidth - Layout.alphabetWidth
        if winampPoint.x >= alphabetX && winampPoint.x < alphabetX + Layout.alphabetWidth {
            if winampPoint.y >= listY && winampPoint.y < listY + listHeight {
                handleAlphabetClick(at: winampPoint, listY: listY, listHeight: listHeight)
                return
            }
        }
        
        if winampPoint.y >= listY && winampPoint.y < listY + listHeight {
            let relativeY = winampPoint.y - listY + scrollOffset
            let clickedIndex = Int(relativeY / itemHeight)
            
            if clickedIndex >= 0 && clickedIndex < displayItems.count {
                let item = displayItems[clickedIndex]
                
                // Handle expand/collapse
                if item.hasChildren && winampPoint.x < Layout.padding + CGFloat(item.indentLevel) * 16 + 20 {
                    toggleExpand(item)
                    return
                }
                
                // Handle selection
                if event.modifierFlags.contains(.shift) {
                    if let lastSelected = selectedIndices.max() {
                        let start = min(lastSelected, clickedIndex)
                        let end = max(lastSelected, clickedIndex)
                        for i in start...end {
                            selectedIndices.insert(i)
                        }
                    } else {
                        selectedIndices.insert(clickedIndex)
                    }
                } else if event.modifierFlags.contains(.command) {
                    if selectedIndices.contains(clickedIndex) {
                        selectedIndices.remove(clickedIndex)
                    } else {
                        selectedIndices.insert(clickedIndex)
                    }
                } else {
                    selectedIndices = [clickedIndex]
                    
                    // Single-click on track plays it immediately
                    NSLog("Single click on item: %@, type: %@", item.title, String(describing: item.type))
                    if case .track = item.type {
                        NSLog("Item is a track, calling playTrack")
                        playTrack(item)
                    }
                }
                
                // Double-click to play album or expand artist
                if event.clickCount == 2 {
                    handleDoubleClick(on: item)
                }
                
                needsDisplay = true
            }
        }
    }
    
    private func toggleExpand(_ item: PlexDisplayItem) {
        switch item.type {
        case .artist(let artist):
            if expandedArtists.contains(artist.id) {
                expandedArtists.remove(artist.id)
            } else {
                expandedArtists.insert(artist.id)
                // Load albums if not cached
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
            
        case .album(let album):
            if expandedAlbums.contains(album.id) {
                expandedAlbums.remove(album.id)
            } else {
                expandedAlbums.insert(album.id)
                // Load tracks if not cached
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
            
        default:
            break
        }
        
        buildArtistItems()
        needsDisplay = true
    }
    
    private func playTrack(_ item: PlexDisplayItem) {
        guard case .track(let track) = item.type else { 
            NSLog("playTrack: item is not a track")
            return 
        }
        
        NSLog("playTrack: %@", track.title)
        NSLog("  partKey: %@", track.partKey ?? "nil")
        NSLog("  serverClient: %@", PlexManager.shared.serverClient != nil ? "exists" : "nil")
        
        if let convertedTrack = PlexManager.shared.convertToTrack(track) {
            NSLog("  streamURL: %@", convertedTrack.url.absoluteString)
            NSLog("  title: %@, artist: %@", convertedTrack.title, convertedTrack.artist ?? "nil")
            // Clear playlist and add just this track with metadata
            WindowManager.shared.audioEngine.clearPlaylist()
            WindowManager.shared.audioEngine.loadTracks([convertedTrack])
            WindowManager.shared.audioEngine.play()
            NSLog("  Called play()")
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
                WindowManager.shared.audioEngine.clearPlaylist()
                WindowManager.shared.audioEngine.loadTracks(convertedTracks)
                WindowManager.shared.audioEngine.play()
            } catch {
                NSLog("Failed to play album: %@", error.localizedDescription)
            }
        }
    }
    
    private func playArtist(_ artist: PlexArtist) {
        Task { @MainActor in
            do {
                // Fetch all albums for artist, then all tracks
                let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                var allTracks: [PlexTrack] = []
                for album in albums {
                    let tracks = try await PlexManager.shared.fetchTracks(forAlbum: album)
                    allTracks.append(contentsOf: tracks)
                }
                let convertedTracks = PlexManager.shared.convertToTracks(allTracks)
                NSLog("Playing artist %@ with %d tracks", artist.title, convertedTracks.count)
                WindowManager.shared.audioEngine.clearPlaylist()
                WindowManager.shared.audioEngine.loadTracks(convertedTracks)
                WindowManager.shared.audioEngine.play()
            } catch {
                NSLog("Failed to play artist: %@", error.localizedDescription)
            }
        }
    }
    
    private func handleDoubleClick(on item: PlexDisplayItem) {
        switch item.type {
        case .track:
            // Single click already plays, double-click does same
            playTrack(item)
            
        case .album(let album):
            // Play all tracks in album
            playAlbum(album)
            
        case .artist:
            // Toggle expansion
            toggleExpand(item)
            
        case .header:
            break
        }
    }
    
    // MARK: - Right-Click Context Menu
    
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Check list area
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        
        if point.y >= listY && point.y < listY + listHeight {
            let relativeY = point.y - listY + scrollOffset
            let clickedIndex = Int(relativeY / itemHeight)
            
            if clickedIndex >= 0 && clickedIndex < displayItems.count {
                // Select the clicked item if not already selected
                if !selectedIndices.contains(clickedIndex) {
                    selectedIndices = [clickedIndex]
                    needsDisplay = true
                }
                
                let item = displayItems[clickedIndex]
                showContextMenu(for: item, at: event)
                return
            }
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
        if libraries.isEmpty {
            let noLibraries = NSMenuItem(title: "No libraries available", action: nil, keyEquivalent: "")
            noLibraries.isEnabled = false
            menu.addItem(noLibraries)
        } else {
            for library in libraries {
                let item = NSMenuItem(title: library.title, action: #selector(selectLibrary(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = library.id
                item.state = library.id == PlexManager.shared.currentLibrary?.id ? .on : .off
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
        
        Task { @MainActor in
            do {
                try await PlexManager.shared.connect(to: server)
                // Clear cached data and reload
                cachedArtists = []
                cachedAlbums = []
                cachedTracks = []
                artistAlbums = [:]
                albumTracks = [:]
                reloadData()
            } catch {
                NSLog("Failed to connect to server: %@", error.localizedDescription)
            }
        }
    }
    
    @objc private func selectLibrary(_ sender: NSMenuItem) {
        guard let libraryID = sender.representedObject as? String,
              let library = PlexManager.shared.availableLibraries.first(where: { $0.id == libraryID }) else {
            return
        }
        
        PlexManager.shared.selectLibrary(library)
        // Clear cached data and reload
        cachedArtists = []
        cachedAlbums = []
        cachedTracks = []
        artistAlbums = [:]
        albumTracks = [:]
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
    
    // MARK: - Alphabet Index Navigation
    
    private func handleAlphabetClick(at point: NSPoint, listY: CGFloat, listHeight: CGFloat) {
        let relativeY = point.y - listY
        let letterCount = CGFloat(alphabetLetters.count)
        let letterHeight = listHeight / letterCount
        let letterIndex = Int(relativeY / letterHeight)
        
        guard letterIndex >= 0 && letterIndex < alphabetLetters.count else { return }
        
        let targetLetter = alphabetLetters[letterIndex]
        scrollToLetter(targetLetter)
    }
    
    private func scrollToLetter(_ letter: String) {
        // Find first item starting with this letter
        for (index, item) in displayItems.enumerated() {
            let firstChar = item.title.uppercased().first.map(String.init) ?? ""
            
            let itemLetter: String
            if let char = firstChar.first, char.isLetter {
                itemLetter = firstChar
            } else {
                itemLetter = "#"
            }
            
            if itemLetter == letter {
                // Scroll to this item
                var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
                if browseMode == .search {
                    listY += Layout.searchBarHeight
                }
                let listHeight = bounds.height - listY - Layout.statusBarHeight
                let maxScroll = max(0, CGFloat(displayItems.count) * itemHeight - listHeight)
                
                scrollOffset = min(maxScroll, CGFloat(index) * itemHeight)
                selectedIndices = [index]
                needsDisplay = true
                return
            }
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        var listY = Layout.titleBarHeight + Layout.serverBarHeight + Layout.tabBarHeight
        if browseMode == .search {
            listY += Layout.searchBarHeight
        }
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        let totalHeight = CGFloat(displayItems.count) * itemHeight
        
        if totalHeight > listHeight {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))
            needsDisplay = true
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
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        
        let itemTop = CGFloat(index) * itemHeight
        let itemBottom = itemTop + itemHeight
        
        if itemTop < scrollOffset {
            scrollOffset = itemTop
        } else if itemBottom > scrollOffset + listHeight {
            scrollOffset = itemBottom - listHeight
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
        case header
    }
}
