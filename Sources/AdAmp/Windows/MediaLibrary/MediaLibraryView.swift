import AppKit

/// Browse mode for the library
enum LibraryBrowseMode: Int, CaseIterable {
    case tracks = 0
    case artists = 1
    case albums = 2
    case genres = 3
    
    var title: String {
        switch self {
        case .tracks: return "Tracks"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .genres: return "Genres"
        }
    }
}

/// Media library view with Winamp-style skin support
class MediaLibraryView: NSView {
    
    // MARK: - Properties
    
    weak var controller: MediaLibraryWindowController?
    
    /// Current browse mode
    private var browseMode: LibraryBrowseMode = .tracks
    
    /// Search query
    private var searchQuery: String = ""
    
    /// Selected item indices
    private var selectedIndices: Set<Int> = []
    
    /// Scroll offset
    private var scrollOffset: CGFloat = 0
    
    /// Item height
    private let itemHeight: CGFloat = 18
    
    /// Dragging state
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    
    /// Current display items
    private var displayItems: [LibraryDisplayItem] = []
    
    /// Expanded artists/albums for hierarchical view
    private var expandedItems: Set<String> = []
    
    // MARK: - Layout Constants
    
    private struct Layout {
        static let titleBarHeight: CGFloat = 20
        static let tabBarHeight: CGFloat = 24
        static let searchBarHeight: CGFloat = 26
        static let statusBarHeight: CGFloat = 20
        static let padding: CGFloat = 3
        static let scrollbarWidth: CGFloat = 14
    }
    
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
        static let scrollbar = NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.35, alpha: 1.0)
        static let scrollbarThumb = NSColor(calibratedRed: 0.4, green: 0.4, blue: 0.5, alpha: 1.0)
        static let border = NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.3, alpha: 1.0)
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
        
        // Register for drag and drop
        registerForDraggedTypes([.fileURL])
        
        // Observe library changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryDidChange),
            name: MediaLibrary.libraryDidChangeNotification,
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
        
        // Flip coordinate system
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // Draw background
        Colors.background.setFill()
        context.fill(bounds)
        
        // Draw title bar
        drawTitleBar(context: context)
        
        // Draw tab bar
        drawTabBar(context: context)
        
        // Draw search bar
        drawSearchBar(context: context)
        
        // Draw list area
        drawListArea(context: context)
        
        // Draw status bar
        drawStatusBar(context: context)
        
        // Draw border
        Colors.border.setStroke()
        context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
        
        context.restoreGState()
    }
    
    private func drawTitleBar(context: CGContext) {
        let titleRect = NSRect(x: 0, y: 0, width: bounds.width, height: Layout.titleBarHeight)
        
        // Gradient background
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.25, alpha: 1.0),
            Colors.titleBar
        ])
        gradient?.draw(in: titleRect, angle: 90)
        
        // Title text
        let title = "Media Library"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
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
    
    private func drawTabBar(context: CGContext) {
        let tabBarRect = NSRect(x: 0, y: Layout.titleBarHeight,
                                width: bounds.width, height: Layout.tabBarHeight)
        
        Colors.tabBackground.setFill()
        context.fill(tabBarRect)
        
        // Draw tabs
        let tabWidth = bounds.width / CGFloat(LibraryBrowseMode.allCases.count)
        
        for (index, mode) in LibraryBrowseMode.allCases.enumerated() {
            let tabRect = NSRect(x: CGFloat(index) * tabWidth, y: Layout.titleBarHeight,
                                width: tabWidth, height: Layout.tabBarHeight)
            
            if mode == browseMode {
                Colors.tabSelected.setFill()
                context.fill(tabRect)
                
                // Accent line at bottom
                Colors.accent.setFill()
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
        let searchY = Layout.titleBarHeight + Layout.tabBarHeight
        let searchRect = NSRect(x: Layout.padding, y: searchY + 3,
                               width: bounds.width - Layout.padding * 2, height: Layout.searchBarHeight - 6)
        
        // Search field background
        NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.2, alpha: 1.0).setFill()
        let path = NSBezierPath(roundedRect: searchRect, xRadius: 3, yRadius: 3)
        path.fill()
        
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
        let displayText = searchQuery.isEmpty ? "Search library..." : searchQuery
        displayText.draw(at: NSPoint(x: searchRect.minX + 24, y: searchRect.midY - 6), withAttributes: textAttrs)
    }
    
    private func drawListArea(context: CGContext) {
        let listY = Layout.titleBarHeight + Layout.tabBarHeight + Layout.searchBarHeight
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        let listRect = NSRect(x: Layout.padding, y: listY,
                             width: bounds.width - Layout.padding * 2 - Layout.scrollbarWidth,
                             height: listHeight)
        
        // List background
        Colors.listBackground.setFill()
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
                Colors.selectedBackground.setFill()
                context.fill(itemRect)
            }
            
            // Item content
            let indent = CGFloat(item.indentLevel) * 16
            let textX = itemRect.minX + indent + 4
            
            // Expand/collapse indicator for hierarchical items
            if item.hasChildren {
                let expanded = expandedItems.contains(item.id)
                let indicator = expanded ? "▼" : "▶"
                let indicatorAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: Colors.textDim,
                    .font: NSFont.systemFont(ofSize: 8)
                ]
                indicator.draw(at: NSPoint(x: textX - 12, y: itemRect.midY - 5), withAttributes: indicatorAttrs)
            }
            
            // Main text
            let textColor = selectedIndices.contains(index) ? Colors.textSelected : Colors.textNormal
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: NSFont.systemFont(ofSize: 10)
            ]
            
            let textRect = NSRect(x: textX, y: itemRect.minY + 2,
                                 width: itemRect.width - indent - 60, height: itemHeight - 4)
            item.title.draw(in: textRect, withAttributes: attrs)
            
            // Secondary info (duration, track count, etc.)
            if let info = item.info {
                let infoAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: Colors.textDim,
                    .font: NSFont.systemFont(ofSize: 9)
                ]
                let infoSize = info.size(withAttributes: infoAttrs)
                info.draw(at: NSPoint(x: itemRect.maxX - infoSize.width - 4, y: itemRect.midY - infoSize.height / 2),
                         withAttributes: infoAttrs)
            }
        }
        
        context.restoreGState()
        
        // Draw scrollbar
        let scrollbarRect = NSRect(x: bounds.width - Layout.padding - Layout.scrollbarWidth,
                                  y: listY, width: Layout.scrollbarWidth, height: listHeight)
        drawScrollbar(in: scrollbarRect, context: context, itemCount: displayItems.count, listHeight: listHeight)
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
        
        // Status text
        let library = MediaLibrary.shared
        let statusText: String
        
        if library.isScanning {
            statusText = String(format: "Scanning... %.0f%%", library.scanProgress * 100)
        } else {
            statusText = "\(library.tracksSnapshot.count) tracks in library"
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Colors.textDim,
            .font: NSFont.systemFont(ofSize: 9)
        ]
        statusText.draw(at: NSPoint(x: Layout.padding + 4, y: statusY + 5), withAttributes: attrs)
        
        // Add folder button
        let addText = "+ Add Folder"
        let addSize = addText.size(withAttributes: attrs)
        let addRect = NSRect(x: bounds.width - addSize.width - Layout.padding - 8,
                            y: statusY + 3, width: addSize.width + 8, height: 14)
        
        Colors.tabSelected.setFill()
        let addPath = NSBezierPath(roundedRect: addRect, xRadius: 2, yRadius: 2)
        addPath.fill()
        
        addText.draw(at: NSPoint(x: addRect.minX + 4, y: addRect.minY + 2), withAttributes: attrs)
    }
    
    // MARK: - Data Management
    
    func reloadData() {
        buildDisplayItems()
        selectedIndices.removeAll()
        scrollOffset = 0
        needsDisplay = true
    }
    
    func skinDidChange() {
        needsDisplay = true
    }
    
    @objc private func libraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadData()
        }
    }
    
    private func buildDisplayItems() {
        displayItems.removeAll()
        let library = MediaLibrary.shared
        
        // Apply search filter
        var filteredTracks = library.tracksSnapshot
        if !searchQuery.isEmpty {
            filteredTracks = library.search(query: searchQuery)
        }
        
        switch browseMode {
        case .tracks:
            displayItems = filteredTracks.map { track in
                LibraryDisplayItem(
                    id: track.id.uuidString,
                    title: track.displayTitle,
                    info: track.formattedDuration,
                    indentLevel: 0,
                    hasChildren: false,
                    type: .track(track)
                )
            }
            
        case .artists:
            let artists = library.allArtists()
            for artist in artists {
                // Filter by search
                if !searchQuery.isEmpty && !artist.name.lowercased().contains(searchQuery.lowercased()) {
                    continue
                }
                
                let isExpanded = expandedItems.contains(artist.id)
                displayItems.append(LibraryDisplayItem(
                    id: artist.id,
                    title: artist.name,
                    info: "\(artist.trackCount) tracks",
                    indentLevel: 0,
                    hasChildren: true,
                    type: .artist(artist)
                ))
                
                if isExpanded {
                    for album in artist.albums {
                        displayItems.append(LibraryDisplayItem(
                            id: album.id,
                            title: album.name,
                            info: album.formattedDuration,
                            indentLevel: 1,
                            hasChildren: false,
                            type: .album(album)
                        ))
                    }
                }
            }
            
        case .albums:
            let albums = library.allAlbums()
            for album in albums {
                if !searchQuery.isEmpty &&
                   !album.name.lowercased().contains(searchQuery.lowercased()) &&
                   !(album.artist?.lowercased().contains(searchQuery.lowercased()) ?? false) {
                    continue
                }
                
                displayItems.append(LibraryDisplayItem(
                    id: album.id,
                    title: album.displayName,
                    info: "\(album.tracks.count) tracks",
                    indentLevel: 0,
                    hasChildren: false,
                    type: .album(album)
                ))
            }
            
        case .genres:
            let genres = library.allGenres()
            for genre in genres {
                if !searchQuery.isEmpty && !genre.lowercased().contains(searchQuery.lowercased()) {
                    continue
                }
                
                let tracksInGenre = library.tracksSnapshot.filter { $0.genre == genre }
                displayItems.append(LibraryDisplayItem(
                    id: genre,
                    title: genre,
                    info: "\(tracksInGenre.count) tracks",
                    indentLevel: 0,
                    hasChildren: false,
                    type: .genre(genre)
                ))
            }
        }
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        
        // Check title bar for dragging
        if winampPoint.y < Layout.titleBarHeight && winampPoint.x < bounds.width - 20 {
            isDragging = true
            dragStartPoint = event.locationInWindow
            // Notify WindowManager that dragging is starting
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window)
            }
            return
        }
        
        // Check close button
        let closeRect = NSRect(x: bounds.width - 14, y: 5, width: 10, height: 10)
        if closeRect.contains(winampPoint) {
            window?.close()
            return
        }
        
        // Check tab bar
        let tabY = Layout.titleBarHeight
        if winampPoint.y >= tabY && winampPoint.y < tabY + Layout.tabBarHeight {
            let tabWidth = bounds.width / CGFloat(LibraryBrowseMode.allCases.count)
            let tabIndex = Int(winampPoint.x / tabWidth)
            if let newMode = LibraryBrowseMode(rawValue: tabIndex) {
                browseMode = newMode
                reloadData()
            }
            return
        }
        
        // Check add folder button
        let statusY = bounds.height - Layout.statusBarHeight
        if winampPoint.y >= statusY && winampPoint.x > bounds.width - 100 {
            addFolder()
            return
        }
        
        // Check list area
        let listY = Layout.titleBarHeight + Layout.tabBarHeight + Layout.searchBarHeight
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        
        if winampPoint.y >= listY && winampPoint.y < listY + listHeight {
            let relativeY = winampPoint.y - listY + scrollOffset
            let clickedIndex = Int(relativeY / itemHeight)
            
            if clickedIndex >= 0 && clickedIndex < displayItems.count {
                let item = displayItems[clickedIndex]
                
                // Handle expand/collapse
                if item.hasChildren && winampPoint.x < Layout.padding + CGFloat(item.indentLevel) * 16 + 20 {
                    if expandedItems.contains(item.id) {
                        expandedItems.remove(item.id)
                    } else {
                        expandedItems.insert(item.id)
                    }
                    buildDisplayItems()
                    needsDisplay = true
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
                }
                
                // Double-click to play/expand
                if event.clickCount == 2 {
                    handleDoubleClick(on: item)
                }
                
                needsDisplay = true
            }
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isDragging {
            guard let window = window else { return }
            let currentPoint = event.locationInWindow
            let delta = NSPoint(
                x: currentPoint.x - dragStartPoint.x,
                y: currentPoint.y - dragStartPoint.y
            )
            
            var newOrigin = window.frame.origin
            newOrigin.x += delta.x
            newOrigin.y += delta.y
            
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            // Notify WindowManager that dragging has ended
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
        isDragging = false
    }
    
    override func scrollWheel(with event: NSEvent) {
        let listY = Layout.titleBarHeight + Layout.tabBarHeight + Layout.searchBarHeight
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        let totalHeight = CGFloat(displayItems.count) * itemHeight
        
        if totalHeight > listHeight {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))
            needsDisplay = true
        }
    }
    
    // MARK: - Actions
    
    private func handleDoubleClick(on item: LibraryDisplayItem) {
        switch item.type {
        case .track(let track):
            // Add to playlist and play
            let playbackTrack = track.toTrack()
            WindowManager.shared.audioEngine.loadFiles([playbackTrack.url])
            WindowManager.shared.audioEngine.play()
            
        case .album(let album):
            // Add all album tracks to playlist
            let urls = album.tracks.map { $0.url }
            WindowManager.shared.audioEngine.loadFiles(urls)
            WindowManager.shared.audioEngine.play()
            
        case .artist(let artist):
            // Toggle expansion
            if expandedItems.contains(artist.id) {
                expandedItems.remove(artist.id)
            } else {
                expandedItems.insert(artist.id)
            }
            buildDisplayItems()
            needsDisplay = true
            
        case .genre(let genre):
            // Add all tracks of this genre
            let tracks = MediaLibrary.shared.tracksSnapshot.filter { $0.genre == genre }
            let urls = tracks.map { $0.url }
            WindowManager.shared.audioEngine.loadFiles(urls)
            WindowManager.shared.audioEngine.play()
        }
    }
    
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to add to your library"
        
        if panel.runModal() == .OK, let url = panel.url {
            MediaLibrary.shared.addWatchFolder(url)
            MediaLibrary.shared.scanFolder(url)
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
            if let chars = event.characters, !chars.isEmpty {
                if event.keyCode == 51 { // Delete
                    if !searchQuery.isEmpty {
                        searchQuery.removeLast()
                        reloadData()
                    }
                } else if chars.rangeOfCharacter(from: .alphanumerics) != nil ||
                          chars.rangeOfCharacter(from: .whitespaces) != nil {
                    searchQuery += chars
                    reloadData()
                }
            }
        }
    }
    
    private func ensureVisible(index: Int) {
        let listY = Layout.titleBarHeight + Layout.tabBarHeight + Layout.searchBarHeight
        let listHeight = bounds.height - listY - Layout.statusBarHeight
        
        let itemTop = CGFloat(index) * itemHeight
        let itemBottom = itemTop + itemHeight
        
        if itemTop < scrollOffset {
            scrollOffset = itemTop
        } else if itemBottom > scrollOffset + listHeight {
            scrollOffset = itemBottom - listHeight
        }
    }
    
    // MARK: - Drag and Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        
        var fileURLs: [URL] = []
        for url in items {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    MediaLibrary.shared.addWatchFolder(url)
                    MediaLibrary.shared.scanFolder(url)
                } else {
                    let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
                    if audioExtensions.contains(url.pathExtension.lowercased()) {
                        fileURLs.append(url)
                    }
                }
            }
        }
        
        if !fileURLs.isEmpty {
            MediaLibrary.shared.addTracks(urls: fileURLs)
        }
        
        return true
    }
}

// MARK: - Display Item

/// Represents an item to display in the library list
private struct LibraryDisplayItem {
    let id: String
    let title: String
    let info: String?
    let indentLevel: Int
    let hasChildren: Bool
    let type: ItemType
    
    enum ItemType {
        case track(LibraryTrack)
        case artist(Artist)
        case album(Album)
        case genre(String)
    }
}
