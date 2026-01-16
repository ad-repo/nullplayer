import AppKit

/// Playlist editor view with skin support
class PlaylistView: NSView {
    
    // MARK: - Properties
    
    weak var controller: PlaylistWindowController?
    
    /// Selected track indices
    private var selectedIndices: Set<Int> = []
    
    /// Scroll offset
    private var scrollOffset: CGFloat = 0
    
    /// Item height
    private let itemHeight: CGFloat = 13
    
    /// Dragging state
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    
    /// Region manager
    private let regionManager = RegionManager.shared
    
    // MARK: - Layout
    
    private struct Layout {
        static let titleBarHeight: CGFloat = 20
        static let buttonBarHeight: CGFloat = 29
        static let padding: CGFloat = 3
        static let scrollbarWidth: CGFloat = 12
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
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Flip coordinate system to match Winamp's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())
        
        // Draw playlist background (handles tiled rendering for resizable window)
        renderer.drawPlaylistBackground(in: context, bounds: bounds)
        
        // Draw title bar
        drawTitleBar(context: context)
        
        // Draw track list
        let colors = skin?.playlistColors ?? .default
        drawTrackList(context: context, colors: colors)
        
        // Draw button bar
        drawButtonBar(context: context)
        
        // Draw resize handle
        drawResizeHandle(context: context)
        
        context.restoreGState()
    }
    
    private func drawTitleBar(context: CGContext) {
        let titleRect = NSRect(x: 0, y: 0,
                               width: bounds.width, height: Layout.titleBarHeight)
        
        if WindowManager.shared.currentSkin?.pledit == nil {
            // Dark gradient title bar (fallback when no skin image)
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.4, alpha: 1.0),
                NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.2, alpha: 1.0)
            ])
            gradient?.draw(in: titleRect, angle: 90)
        }
        
        // Title text
        let title = "Playlist Editor"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 9)
        ]
        let titleSize = title.size(withAttributes: attrs)
        let titlePoint = NSPoint(x: (bounds.width - titleSize.width) / 2,
                                 y: Layout.titleBarHeight / 2 - titleSize.height / 2 + 2)
        title.draw(at: titlePoint, withAttributes: attrs)
        
        // Close button
        let closeRect = NSRect(x: bounds.width - 12, y: 5, width: 9, height: 9)
        NSColor.red.withAlphaComponent(0.8).setFill()
        context.fillEllipse(in: closeRect)
    }
    
    private func drawTrackList(context: CGContext, colors: PlaylistColors) {
        // List area in Winamp coordinates (y=0 at top)
        let listRect = NSRect(
            x: Layout.padding,
            y: Layout.titleBarHeight + Layout.padding,
            width: bounds.width - Layout.padding * 2 - Layout.scrollbarWidth - 3,
            height: bounds.height - Layout.titleBarHeight - Layout.buttonBarHeight - Layout.padding * 2
        )
        
        // Background
        colors.normalBackground.setFill()
        context.fill(listRect)
        
        // Clip to list area
        context.saveGState()
        context.clip(to: listRect)
        
        let tracks = WindowManager.shared.audioEngine.playlist
        let currentIndex = WindowManager.shared.audioEngine.currentIndex
        
        // Calculate visible range
        let visibleStart = Int(scrollOffset / itemHeight)
        let visibleEnd = min(tracks.count, visibleStart + Int(listRect.height / itemHeight) + 2)
        
        for index in visibleStart..<visibleEnd {
            let y = listRect.minY + CGFloat(index) * itemHeight - scrollOffset
            
            // Skip if outside visible area
            if y + itemHeight < listRect.minY || y > listRect.maxY {
                continue
            }
            
            let itemRect = NSRect(x: listRect.minX, y: y, width: listRect.width, height: itemHeight)
            
            // Draw selection background
            if selectedIndices.contains(index) {
                colors.selectedBackground.setFill()
                context.fill(itemRect)
            }
            
            // Draw text
            let track = tracks[index]
            let textColor = index == currentIndex ? colors.currentText : colors.normalText
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: colors.font
            ]
            
            // Format: "1. Artist - Title"
            let displayText = "\(index + 1). \(track.displayTitle)"
            displayText.draw(in: itemRect.insetBy(dx: 2, dy: 1), withAttributes: attrs)
        }
        
        context.restoreGState()
        
        // Draw scrollbar
        let scrollbarRect = NSRect(
            x: bounds.width - Layout.padding - Layout.scrollbarWidth,
            y: listRect.minY,
            width: Layout.scrollbarWidth,
            height: listRect.height
        )
        drawScrollbar(in: scrollbarRect, context: context, trackCount: tracks.count, listHeight: listRect.height)
    }
    
    private func drawScrollbar(in rect: NSRect, context: CGContext, trackCount: Int, listHeight: CGFloat) {
        // Background
        NSColor(calibratedWhite: 0.2, alpha: 1.0).setFill()
        context.fill(rect)
        
        let totalHeight = CGFloat(trackCount) * itemHeight
        if totalHeight <= listHeight { return }
        
        // Calculate thumb size and position
        let thumbHeight = max(20, rect.height * (listHeight / totalHeight))
        let scrollRange = totalHeight - listHeight
        let scrollProgress = scrollOffset / scrollRange
        let thumbY = rect.minY + (rect.height - thumbHeight) * scrollProgress
        
        let thumbRect = NSRect(x: rect.minX + 1, y: thumbY, width: rect.width - 2, height: thumbHeight)
        NSColor(calibratedWhite: 0.5, alpha: 1.0).setFill()
        context.fill(thumbRect)
    }
    
    private func drawButtonBar(context: CGContext) {
        // Button bar at bottom in Winamp coordinates
        let barRect = NSRect(x: 0, y: bounds.height - Layout.buttonBarHeight,
                            width: bounds.width, height: Layout.buttonBarHeight)
        
        // Dark background
        NSColor(calibratedWhite: 0.15, alpha: 1.0).setFill()
        context.fill(barRect)
        
        // Draw buttons: Add, Remove, Select, Misc, List
        let buttonTitles = ["+ADD", "-REM", "SEL", "MISC", "LIST"]
        let buttonWidth: CGFloat = 40
        var x: CGFloat = 10
        let buttonY = barRect.minY + 7
        
        for title in buttonTitles {
            let buttonRect = NSRect(x: x, y: buttonY, width: buttonWidth, height: 15)
            
            // Button background
            NSColor(calibratedWhite: 0.25, alpha: 1.0).setFill()
            let path = NSBezierPath(roundedRect: buttonRect, xRadius: 2, yRadius: 2)
            path.fill()
            
            // Button text
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.lightGray,
                .font: NSFont.systemFont(ofSize: 8)
            ]
            let textSize = title.size(withAttributes: attrs)
            let textPoint = NSPoint(
                x: buttonRect.midX - textSize.width / 2,
                y: buttonRect.midY - textSize.height / 2
            )
            title.draw(at: textPoint, withAttributes: attrs)
            
            x += buttonWidth + 5
        }
        
        // Track count and total time
        let tracks = WindowManager.shared.audioEngine.playlist
        let infoText = "\(tracks.count) tracks"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.systemFont(ofSize: 8)
        ]
        let infoSize = infoText.size(withAttributes: attrs)
        infoText.draw(at: NSPoint(x: bounds.width - infoSize.width - 15, y: buttonY + 3), withAttributes: attrs)
    }
    
    private func drawResizeHandle(context: CGContext) {
        // Resize handle at bottom-right in Winamp coordinates
        let handleRect = NSRect(x: bounds.width - 20, y: bounds.height - 20, width: 20, height: 20)
        
        // Draw diagonal lines
        NSColor.gray.setStroke()
        for i in 0..<3 {
            let offset = CGFloat(i) * 4 + 4
            let path = NSBezierPath()
            path.move(to: NSPoint(x: handleRect.maxX - offset, y: handleRect.maxY))
            path.line(to: NSPoint(x: handleRect.maxX, y: handleRect.maxY - offset))
            path.lineWidth = 1
            path.stroke()
        }
    }
    
    // MARK: - Public Methods
    
    func reloadData() {
        selectedIndices.removeAll()
        scrollOffset = 0
        needsDisplay = true
    }
    
    func skinDidChange() {
        needsDisplay = true
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        
        // Check title bar for dragging
        if winampPoint.y < Layout.titleBarHeight && winampPoint.x < bounds.width - 15 {
            isDragging = true
            dragStartPoint = event.locationInWindow
            return
        }
        
        // Check close button
        let closeRect = NSRect(x: bounds.width - 12, y: 5, width: 9, height: 9)
        if closeRect.contains(winampPoint) {
            window?.close()
            return
        }
        
        // Check track list click
        let listRect = NSRect(
            x: Layout.padding,
            y: Layout.titleBarHeight + Layout.padding,
            width: bounds.width - Layout.padding * 2 - Layout.scrollbarWidth - 3,
            height: bounds.height - Layout.titleBarHeight - Layout.buttonBarHeight - Layout.padding * 2
        )
        
        if listRect.contains(winampPoint) {
            let relativeY = winampPoint.y - listRect.minY + scrollOffset
            let clickedIndex = Int(relativeY / itemHeight)
            
            let tracks = WindowManager.shared.audioEngine.playlist
            if clickedIndex >= 0 && clickedIndex < tracks.count {
                if event.modifierFlags.contains(.shift) {
                    // Extend selection
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
                    // Toggle selection
                    if selectedIndices.contains(clickedIndex) {
                        selectedIndices.remove(clickedIndex)
                    } else {
                        selectedIndices.insert(clickedIndex)
                    }
                } else {
                    // Single selection
                    selectedIndices = [clickedIndex]
                }
                
                // Double-click plays track
                if event.clickCount == 2 {
                    WindowManager.shared.audioEngine.playTrack(at: clickedIndex)
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
        isDragging = false
    }
    
    override func scrollWheel(with event: NSEvent) {
        let tracks = WindowManager.shared.audioEngine.playlist
        let listHeight = bounds.height - Layout.titleBarHeight - Layout.buttonBarHeight - Layout.padding * 2
        let totalHeight = CGFloat(tracks.count) * itemHeight
        
        if totalHeight > listHeight {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))
            needsDisplay = true
        }
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let engine = WindowManager.shared.audioEngine
        
        switch event.keyCode {
        case 51: // Delete - remove selected
            let sorted = selectedIndices.sorted(by: >)
            for index in sorted {
                engine.removeTrack(at: index)
            }
            selectedIndices.removeAll()
            needsDisplay = true
            
        case 36: // Enter - play selected
            if let index = selectedIndices.first {
                engine.playTrack(at: index)
            }
            
        case 0: // A - select all (with Cmd)
            if event.modifierFlags.contains(.command) {
                selectedIndices = Set(0..<engine.playlist.count)
                needsDisplay = true
            }
            
        default:
            super.keyDown(with: event)
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
        
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
        let audioURLs = items.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        
        if !audioURLs.isEmpty {
            WindowManager.shared.audioEngine.loadFiles(audioURLs)
            needsDisplay = true
            return true
        }
        
        return false
    }
}
