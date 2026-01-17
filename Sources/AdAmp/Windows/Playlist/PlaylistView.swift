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
    
    /// Region manager
    private let regionManager = RegionManager.shared
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Button being pressed
    private var pressedButton: ButtonType?
    
    // MARK: - Layout
    
    private struct Layout {
        // Skin-based layout
        static let titleBarHeight: CGFloat = 20
        static let bottomBarHeight: CGFloat = 38
        static let leftBorder: CGFloat = 4   // Small padding for content
        static let rightBorder: CGFloat = 4  // Small padding for content
        static let scrollbarWidth: CGFloat = 8
        
        // Fallback layout (when no skin)
        static let fallbackButtonBarHeight: CGFloat = 29
        static let fallbackPadding: CGFloat = 3
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
        
        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())
        
        if isShadeMode {
            // Draw shade mode with flipped coordinates for skin sprites
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            
            let isActive = window?.isKeyWindow ?? true
            renderer.drawPlaylistShade(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
            
            context.restoreGState()
        } else {
            // Draw normal mode - use standard macOS coordinates for text
            // Only flip context when drawing skin sprites
            drawNormalMode(renderer: renderer, context: context, skin: skin)
        }
    }
    
    /// Draw normal (non-shade) mode
    private func drawNormalMode(renderer: SkinRenderer, context: CGContext, skin: Skin?) {
        // Draw everything in standard macOS coordinates (no flipping)
        // This avoids coordinate confusion between skin sprites and programmatic drawing
        
        let colors = skin?.playlistColors ?? .default
        
        // Fill entire background with playlist color first
        colors.normalBackground.setFill()
        context.fill(bounds)
        
        // Draw title bar at top
        drawPlaylistTitleBar(context: context)
        
        // Draw track list in the middle
        drawTrackList(context: context, colors: colors)
        
        // Draw scrollbar
        drawPlaylistScrollbar(context: context)
        
        // Draw bottom bar with buttons
        drawPlaylistBottomBar(context: context)
    }
    
    /// Draw Winamp-style playlist title bar
    private func drawPlaylistTitleBar(context: CGContext) {
        let titleRect = NSRect(x: 0, y: bounds.height - Layout.titleBarHeight,
                               width: bounds.width, height: Layout.titleBarHeight)
        
        // Dark blue gradient background
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.25, alpha: 1.0),
            NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)
        ])
        gradient?.draw(in: titleRect, angle: 90)
        
        // Left decorative bar
        NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.3, alpha: 1.0).setFill()
        context.fill(NSRect(x: 4, y: bounds.height - 14, width: 8, height: 8))
        
        // Title text
        let title = "WINAMP PLAYLIST"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 9)
        ]
        let titleSize = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: 16, y: bounds.height - Layout.titleBarHeight / 2 - titleSize.height / 2), 
                   withAttributes: attrs)
        
        // Decorative pattern after title
        let patternStart = 16 + titleSize.width + 4
        NSColor(calibratedRed: 0.3, green: 0.3, blue: 0.4, alpha: 1.0).setFill()
        var x = patternStart
        while x < bounds.width - 30 {
            context.fill(NSRect(x: x, y: bounds.height - 12, width: 2, height: 4))
            x += 4
        }
        
        // Window control buttons (shade, close)
        // Shade button
        NSColor(calibratedWhite: 0.4, alpha: 1.0).setFill()
        context.fill(NSRect(x: bounds.width - 22, y: bounds.height - 14, width: 9, height: 9))
        // Close button
        NSColor(calibratedWhite: 0.4, alpha: 1.0).setFill()
        context.fill(NSRect(x: bounds.width - 11, y: bounds.height - 14, width: 9, height: 9))
    }
    
    /// Draw Winamp-style scrollbar
    private func drawPlaylistScrollbar(context: CGContext) {
        let scrollbarWidth: CGFloat = 20
        let titleHeight = Layout.titleBarHeight
        let bottomHeight = Layout.bottomBarHeight
        
        let scrollRect = NSRect(
            x: bounds.width - scrollbarWidth,
            y: bottomHeight,
            width: scrollbarWidth,
            height: bounds.height - titleHeight - bottomHeight
        )
        
        // Scrollbar background
        NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.2, alpha: 1.0).setFill()
        context.fill(scrollRect)
        
        // Scrollbar thumb (golden/tan color like Winamp)
        let tracks = WindowManager.shared.audioEngine.playlist
        let listHeight = scrollRect.height
        let totalContentHeight = CGFloat(tracks.count) * itemHeight
        
        if totalContentHeight > 0 {
            let thumbHeight = max(20, listHeight * min(1, listHeight / max(1, totalContentHeight)))
            let scrollRange = totalContentHeight - listHeight
            let thumbY: CGFloat
            if scrollRange > 0 {
                let progress = scrollOffset / scrollRange
                thumbY = scrollRect.minY + (scrollRect.height - thumbHeight) * (1 - progress)
            } else {
                thumbY = scrollRect.minY
            }
            
            // Draw thumb with Winamp golden color
            NSColor(calibratedRed: 0.6, green: 0.55, blue: 0.35, alpha: 1.0).setFill()
            let thumbRect = NSRect(x: scrollRect.minX + 2, y: thumbY, 
                                   width: scrollRect.width - 4, height: thumbHeight)
            context.fill(thumbRect)
            
            // Thumb highlight
            NSColor(calibratedRed: 0.7, green: 0.65, blue: 0.45, alpha: 1.0).setFill()
            context.fill(NSRect(x: thumbRect.minX, y: thumbRect.maxY - 2, 
                                width: thumbRect.width, height: 2))
        }
    }
    
    /// Draw Winamp-style bottom bar with buttons
    private func drawPlaylistBottomBar(context: CGContext) {
        let barRect = NSRect(x: 0, y: 0, width: bounds.width, height: Layout.bottomBarHeight)
        
        // Background
        NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.2, alpha: 1.0).setFill()
        context.fill(barRect)
        
        // Top border line
        NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.35, alpha: 1.0).setFill()
        context.fill(NSRect(x: 0, y: Layout.bottomBarHeight - 1, width: bounds.width, height: 1))
        
        // Draw buttons: ADD, REM, SEL, MISC
        let buttonY: CGFloat = 4
        let buttonHeight: CGFloat = 18
        let buttonColor = NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.3, alpha: 1.0)
        let buttonHighlight = NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.4, alpha: 1.0)
        let buttonShadow = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        
        let buttons = ["ADD", "REM", "SEL", "MISC"]
        var x: CGFloat = 4
        
        for title in buttons {
            let buttonWidth: CGFloat = 40
            let buttonRect = NSRect(x: x, y: buttonY, width: buttonWidth, height: buttonHeight)
            
            // Button face
            buttonColor.setFill()
            context.fill(buttonRect)
            
            // Highlight (top and left)
            buttonHighlight.setFill()
            context.fill(NSRect(x: buttonRect.minX, y: buttonRect.maxY - 1, width: buttonRect.width, height: 1))
            context.fill(NSRect(x: buttonRect.minX, y: buttonRect.minY, width: 1, height: buttonRect.height))
            
            // Shadow (bottom and right)
            buttonShadow.setFill()
            context.fill(NSRect(x: buttonRect.minX, y: buttonRect.minY, width: buttonRect.width, height: 1))
            context.fill(NSRect(x: buttonRect.maxX - 1, y: buttonRect.minY, width: 1, height: buttonRect.height))
            
            // Button text
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 8)
            ]
            let textSize = title.size(withAttributes: attrs)
            let textPoint = NSPoint(
                x: buttonRect.midX - textSize.width / 2,
                y: buttonRect.midY - textSize.height / 2
            )
            title.draw(at: textPoint, withAttributes: attrs)
            
            x += buttonWidth + 2
        }
        
        // Time display in center
        let tracks = WindowManager.shared.audioEngine.playlist
        let engine = WindowManager.shared.audioEngine
        let currentTime = engine.currentTime
        let duration = engine.duration
        let timeStr = String(format: "%d:%02d/%d:%02d", 
                            Int(currentTime) / 60, Int(currentTime) % 60,
                            Int(duration) / 60, Int(duration) % 60)
        
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        ]
        let timeSize = timeStr.size(withAttributes: timeAttrs)
        let timeX = bounds.width / 2 - timeSize.width / 2
        timeStr.draw(at: NSPoint(x: timeX, y: 8), withAttributes: timeAttrs)
        
        // LIST OPTS button on right
        let listOptsRect = NSRect(x: bounds.width - 50, y: buttonY, width: 46, height: buttonHeight)
        buttonColor.setFill()
        context.fill(listOptsRect)
        buttonHighlight.setFill()
        context.fill(NSRect(x: listOptsRect.minX, y: listOptsRect.maxY - 1, width: listOptsRect.width, height: 1))
        buttonShadow.setFill()
        context.fill(NSRect(x: listOptsRect.minX, y: listOptsRect.minY, width: listOptsRect.width, height: 1))
        
        let listAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 7)
        ]
        "LIST".draw(at: NSPoint(x: listOptsRect.midX - 10, y: listOptsRect.midY + 2), withAttributes: listAttrs)
        "OPTS".draw(at: NSPoint(x: listOptsRect.midX - 10, y: listOptsRect.midY - 6), withAttributes: listAttrs)
        
        // Track count
        let countStr = "\(tracks.count) tracks"
        let countAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.systemFont(ofSize: 8)
        ]
        let countSize = countStr.size(withAttributes: countAttrs)
        countStr.draw(at: NSPoint(x: bounds.width - 55 - countSize.width, y: 24), withAttributes: countAttrs)
    }
    
    private func drawTrackList(context: CGContext, colors: PlaylistColors) {
        let titleHeight = Layout.titleBarHeight
        let bottomHeight = Layout.bottomBarHeight
        let scrollbarWidth: CGFloat = 20
        
        // List area - leave room for scrollbar on right
        let listRect = NSRect(
            x: 2,
            y: bottomHeight,
            width: bounds.width - 4 - scrollbarWidth,
            height: bounds.height - titleHeight - bottomHeight
        )
        
        // Clip to list area
        context.saveGState()
        context.clip(to: listRect)
        
        let tracks = WindowManager.shared.audioEngine.playlist
        let currentIndex = WindowManager.shared.audioEngine.currentIndex
        
        // Calculate visible range
        let visibleStart = Int(scrollOffset / itemHeight)
        let visibleEnd = min(tracks.count, visibleStart + Int(listRect.height / itemHeight) + 2)
        
        for index in visibleStart..<visibleEnd {
            // In macOS coords, items go from top to bottom
            let y = listRect.maxY - CGFloat(index + 1) * itemHeight + scrollOffset
            
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
            
            // Draw track info like Winamp: "1. Title                    0:00"
            let track = tracks[index]
            let isCurrentTrack = index == currentIndex
            let textColor = isCurrentTrack ? colors.currentText : colors.normalText
            
            // Track number and title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: colors.font
            ]
            let titleText = "\(index + 1). \(track.displayTitle)"
            titleText.draw(at: NSPoint(x: itemRect.minX + 2, y: itemRect.minY + 1), withAttributes: titleAttrs)
            
            // Duration (right-aligned)
            let duration = track.duration ?? 0
            let durationStr = String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
            let durationAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: colors.font
            ]
            let durationSize = durationStr.size(withAttributes: durationAttrs)
            durationStr.draw(at: NSPoint(x: itemRect.maxX - durationSize.width - 4, y: itemRect.minY + 1), 
                            withAttributes: durationAttrs)
        }
        
        context.restoreGState()
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
    
    // MARK: - Mouse Events
    
    /// Track if we're dragging the window
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Allow clicking even when window is not active
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hasSkin = WindowManager.shared.currentSkin?.pledit != nil
        
        // Check for double-click on title bar to toggle shade mode
        // Title bar is at TOP of window in macOS coords
        if event.clickCount == 2 {
            if point.y > bounds.height - Layout.titleBarHeight && point.x < bounds.width - 30 {
                toggleShadeMode()
                return
            }
        }
        
        if isShadeMode {
            // For shade mode, convert to Winamp coordinates
            let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
            handleShadeMouseDown(at: winampPoint, event: event)
            return
        }
        
        // Window dragging is handled by macOS via isMovableByWindowBackground
        
        // Check close button (top right in macOS coords) - only for fallback rendering
        if !hasSkin {
            let closeRect = NSRect(x: bounds.width - 12, y: bounds.height - 14, width: 9, height: 9)
            if closeRect.contains(point) {
                window?.close()
                return
            }
        }
        
        // Calculate list area based on skin/fallback layout
        let bottomHeight = hasSkin ? Layout.bottomBarHeight : Layout.fallbackButtonBarHeight
        let leftPadding = hasSkin ? Layout.leftBorder : Layout.fallbackPadding
        let rightPadding = hasSkin ? Layout.rightBorder : Layout.fallbackPadding
        
        let listHeight = bounds.height - Layout.titleBarHeight - bottomHeight
        let listRect = NSRect(
            x: leftPadding,
            y: bottomHeight,
            width: bounds.width - leftPadding - rightPadding - Layout.scrollbarWidth,
            height: listHeight
        )
        
        if listRect.contains(point) {
            // Calculate which track was clicked
            let relativeY = listRect.maxY - point.y + scrollOffset
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
                return
            }
        }
        
        // No control hit - start window drag
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
    }
    
    /// Handle mouse down in shade mode
    private func handleShadeMouseDown(at winampPoint: NSPoint, event: NSEvent) {
        // Check window control buttons (relative to right edge)
        let closeRect = NSRect(x: bounds.width + SkinElements.PlaylistShade.Positions.closeButton.minX,
                               y: SkinElements.PlaylistShade.Positions.closeButton.minY,
                               width: 9, height: 9)
        let shadeRect = NSRect(x: bounds.width + SkinElements.PlaylistShade.Positions.shadeButton.minX,
                               y: SkinElements.PlaylistShade.Positions.shadeButton.minY,
                               width: 9, height: 9)
        
        if closeRect.contains(winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if shadeRect.contains(winampPoint) {
            pressedButton = .unshade
            needsDisplay = true
            return
        }
        
        // No button hit - start window drag
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Handle window dragging (moves docked windows too)
        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y
            
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY
            
            // Use WindowManager for snapping and moving docked windows
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        
        // End window dragging
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
        
        if isShadeMode {
            // Handle shade mode button release
            if let pressed = pressedButton {
                // Check window control buttons (relative to right edge)
                let closeRect = NSRect(x: bounds.width + SkinElements.PlaylistShade.Positions.closeButton.minX,
                                       y: SkinElements.PlaylistShade.Positions.closeButton.minY,
                                       width: 9, height: 9)
                let shadeRect = NSRect(x: bounds.width + SkinElements.PlaylistShade.Positions.shadeButton.minX,
                                       y: SkinElements.PlaylistShade.Positions.shadeButton.minY,
                                       width: 9, height: 9)
                
                switch pressed {
                case .close:
                    if closeRect.contains(winampPoint) {
                        window?.close()
                    }
                case .unshade:
                    if shadeRect.contains(winampPoint) {
                        toggleShadeMode()
                    }
                default:
                    break
                }
                
                pressedButton = nil
                needsDisplay = true
            }
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        let hasSkin = WindowManager.shared.currentSkin?.pledit != nil
        let bottomHeight = hasSkin ? Layout.bottomBarHeight : Layout.fallbackButtonBarHeight
        
        let tracks = WindowManager.shared.audioEngine.playlist
        let listHeight = bounds.height - Layout.titleBarHeight - bottomHeight
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
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return ContextMenuBuilder.buildMenu()
    }
}
