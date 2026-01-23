import AppKit

// =============================================================================
// PLAYLIST VIEW - Playlist editor window with skin sprite support
// =============================================================================
// Follows the same pattern as EQView for:
// - Coordinate transformation (Winamp top-down system)
// - Button hit testing and visual feedback
// - Popup menus for button actions
// =============================================================================

/// Playlist editor view with full skin support
class PlaylistView: NSView {
    
    // MARK: - Properties
    
    weak var controller: PlaylistWindowController?
    
    /// Selected track indices
    private var selectedIndices: Set<Int> = []
    
    /// Scroll offset (in pixels)
    private var scrollOffset: CGFloat = 0
    
    /// Item height
    private let itemHeight: CGFloat = 13
    
    /// Region manager
    private let regionManager = RegionManager.shared
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: SkinRenderer.PlaylistButtonType?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Scrollbar dragging state
    private var isDraggingScrollbar = false
    private var scrollbarDragStartY: CGFloat = 0
    private var scrollbarDragStartOffset: CGFloat = 0
    
    /// Display update timer for playback time
    private var displayTimer: Timer?
    
    /// Marquee scroll offset for current track
    private var marqueeOffset: CGFloat = 0
    
    // MARK: - Layout Constants
    
    private struct Layout {
        static let titleBarHeight: CGFloat = 20
        static let bottomBarHeight: CGFloat = 38
        static let scrollbarWidth: CGFloat = 20
        static let leftBorder: CGFloat = 12
        static let rightBorder: CGFloat = 20
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
        
        // Start display timer for playback time updates and marquee scrolling
        // Use 30fps (0.033s) with 1px increments for smooth scrolling
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            self?.marqueeOffset += 1
            self?.needsDisplay = true
        }
        
        // Set up accessibility identifiers for UI testing
        setupAccessibility()
    }
    
    // MARK: - Accessibility
    
    /// Set up accessibility identifiers for UI testing
    private func setupAccessibility() {
        setAccessibilityIdentifier("playlistView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Playlist")
    }
    
    deinit {
        displayTimer?.invalidate()
    }
    
    // MARK: - Scaling Support
    
    /// Calculate scale factor based on current bounds vs original (base) size
    private var scaleFactor: CGFloat {
        let originalSize = originalWindowSize
        let scaleX = bounds.width / originalSize.width
        let scaleY = bounds.height / originalSize.height
        return min(scaleX, scaleY)
    }
    
    /// Get the original window size for drawing and hit testing
    private var originalWindowSize: NSSize {
        if isShadeMode {
            // Shade mode: width scales with window, height is fixed
            return NSSize(width: SkinElements.Playlist.minSize.width, height: SkinElements.PlaylistShade.height)
        } else {
            return SkinElements.Playlist.minSize
        }
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
        
        // Apply scaling for resized window (like MainWindowView and EQView)
        if scale != 1.0 {
            // Center the scaled content
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
            renderer.drawPlaylistShade(in: context, bounds: drawBounds, isActive: isActive, 
                                       pressedButton: mapToButtonType(pressedButton))
        } else {
            // Calculate scroll position for scrollbar (0-1)
            let scrollPosition = calculateScrollPosition()
            
            // Draw window frame using skin sprites
            renderer.drawPlaylistWindow(in: context, bounds: drawBounds, isActive: isActive,
                                        pressedButton: pressedButton, scrollPosition: scrollPosition)
            
            // Draw track list in the content area
            let colors = skin?.playlistColors ?? .default
            drawTrackList(in: context, colors: colors, drawBounds: drawBounds)
            
            // Draw time/track info in bottom bar middle section using skin font
            drawBottomBarInfo(in: context, drawBounds: drawBounds, renderer: renderer)
            
            // Draw playback time in the colon area using skin font
            drawPlaybackTime(in: context, drawBounds: drawBounds, renderer: renderer)
        }
        
        context.restoreGState()
    }
    
    /// Map PlaylistButtonType to ButtonType for shade mode
    private func mapToButtonType(_ plButton: SkinRenderer.PlaylistButtonType?) -> ButtonType? {
        guard let btn = plButton else { return nil }
        switch btn {
        case .close: return .close
        case .shade: return .unshade
        default: return nil
        }
    }
    
    /// Calculate scroll position as 0-1 value
    private func calculateScrollPosition() -> CGFloat {
        let tracks = WindowManager.shared.audioEngine.playlist
        let originalSize = originalWindowSize
        let listHeight = originalSize.height - Layout.titleBarHeight - Layout.bottomBarHeight
        let totalContentHeight = CGFloat(tracks.count) * itemHeight
        
        guard totalContentHeight > listHeight else { return 0 }
        
        let scrollRange = totalContentHeight - listHeight
        return min(1, max(0, scrollOffset / scrollRange))
    }
    
    /// Draw the track list
    private func drawTrackList(in context: CGContext, colors: PlaylistColors, drawBounds: NSRect) {
        let titleHeight = Layout.titleBarHeight
        let bottomHeight = Layout.bottomBarHeight
        
        // List area - leave room for scrollbar on right (using drawBounds for scaled coordinates)
        let listRect = NSRect(
            x: Layout.leftBorder,
            y: titleHeight,
            width: drawBounds.width - Layout.leftBorder - Layout.rightBorder,
            height: drawBounds.height - titleHeight - bottomHeight
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
            // In Winamp coordinates, items go from top to bottom (y increases downward)
            let y = titleHeight + CGFloat(index) * itemHeight - scrollOffset
            
            // Skip if outside visible area
            if y + itemHeight < titleHeight || y > drawBounds.height - bottomHeight {
                continue
            }
            
            let itemRect = NSRect(x: listRect.minX, y: y, width: listRect.width, height: itemHeight)
            
            // Draw selection background
            if selectedIndices.contains(index) {
                colors.selectedBackground.setFill()
                context.fill(itemRect)
            }
            
            // Draw track info
            let track = tracks[index]
            let isCurrentTrack = index == currentIndex
            let textColor = isCurrentTrack ? colors.currentText : colors.normalText
            
            // Draw track text with clipping and marquee for current track
            drawTrackText(in: context, track: track, index: index, rect: itemRect, color: textColor, font: colors.font, isCurrentTrack: isCurrentTrack)
        }
        
        context.restoreGState()
    }
    
    /// Draw track text (handles coordinate flip for proper text rendering)
    private func drawTrackText(in context: CGContext, track: Track, index: Int, rect: NSRect, color: NSColor, font: NSFont, isCurrentTrack: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font
        ]
        
        // Calculate dimensions
        let centerY = rect.midY
        let duration = track.duration ?? 0
        let durationStr = String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
        let durationSize = durationStr.size(withAttributes: attrs)
        let durationX = rect.maxX - durationSize.width - 4
        let titleX = rect.minX + 2
        let titleMaxWidth = durationX - titleX - 6
        let titleText = "\(index + 1). \(track.displayTitle)"
        let textWidth = titleText.size(withAttributes: attrs).width
        
        // Draw duration (right-aligned)
        context.saveGState()
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        durationStr.draw(at: NSPoint(x: durationX, y: rect.minY + 1), withAttributes: attrs)
        context.restoreGState()
        
        // Draw title with clipping
        context.saveGState()
        context.clip(to: NSRect(x: titleX, y: rect.minY, width: titleMaxWidth, height: rect.height))
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        // Marquee scroll for current track if text is too long
        if isCurrentTrack && textWidth > titleMaxWidth {
            let separator = "     "  // Simple spacing between repeats
            let fullText = titleText + separator
            let cycleWidth = fullText.size(withAttributes: attrs).width
            let offset = marqueeOffset.truncatingRemainder(dividingBy: cycleWidth)
            
            fullText.draw(at: NSPoint(x: titleX - offset, y: rect.minY + 1), withAttributes: attrs)
            fullText.draw(at: NSPoint(x: titleX - offset + cycleWidth, y: rect.minY + 1), withAttributes: attrs)
        } else {
            titleText.draw(at: NSPoint(x: titleX, y: rect.minY + 1), withAttributes: attrs)
        }
        context.restoreGState()
    }
    
    /// Draw time/info display at the bottom of the track list area (just above the bottom bar)
    private func drawTimeDisplay(in context: CGContext, drawBounds: NSRect) {
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        let currentTime = engine.currentTime
        let duration = engine.duration
        
        // Position just above the bottom bar, in the track list area
        let infoY = drawBounds.height - Layout.bottomBarHeight - 14
        
        context.saveGState()
        
        // Flip for text rendering
        let centerY = infoY + 6
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        // Calculate total playlist duration
        var totalSeconds = 0
        for track in tracks {
            totalSeconds += Int(track.duration ?? 0)
        }
        let totalMinutes = totalSeconds / 60
        let totalHours = totalMinutes / 60
        
        // Format total time
        let totalTimeStr: String
        if totalHours > 0 {
            totalTimeStr = String(format: "%d:%02d:%02d", totalHours, totalMinutes % 60, totalSeconds % 60)
        } else {
            totalTimeStr = String(format: "%d:%02d", totalMinutes, totalSeconds % 60)
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        ]
        
        // Show track count and total time on the right side
        let infoStr = "\(tracks.count) tracks / \(totalTimeStr)"
        let infoSize = infoStr.size(withAttributes: attrs)
        let infoX = drawBounds.width - Layout.rightBorder - infoSize.width - 4
        infoStr.draw(at: NSPoint(x: infoX, y: infoY), withAttributes: attrs)
        
        // Show current playback time on the left side if playing
        if engine.state == .playing || currentTime > 0 {
            let playTimeStr = String(format: "%d:%02d / %d:%02d",
                                    Int(currentTime) / 60, Int(currentTime) % 60,
                                    Int(duration) / 60, Int(duration) % 60)
            playTimeStr.draw(at: NSPoint(x: Layout.leftBorder + 4, y: infoY), withAttributes: attrs)
        }
        
        context.restoreGState()
    }
    
    /// Draw track count and total time info in bottom bar using skin font
    /// Shows REMAINING tracks and countdown time
    private func drawBottomBarInfo(in context: CGContext, drawBounds: NSRect, renderer: SkinRenderer) {
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        
        // Don't draw if no tracks
        guard !tracks.isEmpty else { return }
        
        // Get current track index (0-based), -1 means no track loaded
        let currentIndex = max(0, engine.currentIndex)
        
        // Calculate remaining tracks (including current track)
        let remainingTracks = max(0, tracks.count - currentIndex)
        
        // Calculate remaining time:
        // - Time left in current track
        // - Plus duration of all tracks after current
        var remainingSeconds = 0
        
        // Add remaining time in current track
        if engine.state == .playing || engine.currentTime > 0 {
            let currentDuration = engine.duration
            let currentTime = engine.currentTime
            remainingSeconds += max(0, Int(currentDuration - currentTime))
        } else if currentIndex < tracks.count {
            // Not playing yet, add full duration of current track
            remainingSeconds += Int(tracks[currentIndex].duration ?? 0)
        }
        
        // Add duration of all tracks after current
        for i in (currentIndex + 1)..<tracks.count {
            remainingSeconds += Int(tracks[i].duration ?? 0)
        }
        
        let remainingMinutes = remainingSeconds / 60
        let remainingHours = remainingMinutes / 60
        
        // Build the info string for skin font
        let trackCountStr = "\(remainingTracks) TRACKS/"
        let remainingTimeStr: String
        if remainingHours > 0 {
            remainingTimeStr = String(format: "%d:%02d:%02d", remainingHours, remainingMinutes % 60, remainingSeconds % 60)
        } else {
            remainingTimeStr = String(format: "%d:%02d", remainingMinutes, remainingSeconds % 60)
        }
        
        // Calculate width using skin font dimensions (5px per char for text)
        let charWidth = SkinElements.TextFont.charWidth  // 5px
        let textWidth = CGFloat(trackCountStr.count) * charWidth + CGFloat(remainingTimeStr.count) * charWidth
        
        // Position INSIDE the bottom bar area, centered horizontally
        let bottomBarTop = drawBounds.height - Layout.bottomBarHeight
        let leftEdge: CGFloat = 125
        let rightEdge = drawBounds.width - 150
        let centerX = leftEdge + (rightEdge - leftEdge - textWidth) / 2
        let textX = max(leftEdge + 5, centerX)
        let textY = bottomBarTop + 10  // Centered vertically in info area
        
        // Draw using skin font (no coordinate flip needed for sprites)
        var xPos = textX
        xPos += renderer.drawSkinText(trackCountStr, at: NSPoint(x: xPos, y: textY), in: context)
        renderer.drawSkinText(remainingTimeStr, at: NSPoint(x: xPos, y: textY), in: context)
    }
    
    /// Draw current playback time in the colon area of the bottom bar using skin font
    private func drawPlaybackTime(in context: CGContext, drawBounds: NSRect, renderer: SkinRenderer) {
        let engine = WindowManager.shared.audioEngine
        
        // Only draw if playing or has position
        guard engine.state == .playing || engine.currentTime > 0 else { return }
        
        let currentTime = engine.currentTime
        let minutes = Int(currentTime) / 60
        let seconds = Int(currentTime) % 60
        
        // Use skin text font (5x6 pixels per character)
        let charWidth = SkinElements.TextFont.charWidth
        let minutesStr = String(minutes)
        let minWidth = CGFloat(minutesStr.count) * charWidth
        
        // Position relative to the right edge
        // The colon in the skin is to the left of the LIST button
        let colonX: CGFloat = drawBounds.width - 68
        let bottomBarTop = drawBounds.height - Layout.bottomBarHeight
        let textY = bottomBarTop + 22  // Lowered for skin font
        
        // Draw minutes to the left of the colon
        let minX = colonX - minWidth - 1
        renderer.drawSkinText(minutesStr, at: NSPoint(x: minX, y: textY), in: context)
        
        // Draw seconds to the right of the colon  
        let secX = colonX + 4
        let secondsStr = String(format: "%02d", seconds)
        renderer.drawSkinText(secondsStr, at: NSPoint(x: secX, y: textY), in: context)
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
        let closeRect = NSRect(x: originalSize.width - SkinElements.Playlist.TitleBarButtons.closeOffset - 9,
                               y: 3, width: 9, height: 9)
        return closeRect.contains(winampPoint)
    }
    
    /// Check if point hits shade button
    private func hitTestShadeButton(at winampPoint: NSPoint) -> Bool {
        let originalSize = originalWindowSize
        let shadeRect = NSRect(x: originalSize.width - SkinElements.Playlist.TitleBarButtons.shadeOffset - 9,
                               y: 3, width: 9, height: 9)
        return shadeRect.contains(winampPoint)
    }
    
    /// Check if point hits a bottom bar button, return which one
    private func hitTestBottomButton(at winampPoint: NSPoint) -> SkinRenderer.PlaylistButtonType? {
        let originalSize = originalWindowSize
        let bottomY = originalSize.height - Layout.bottomBarHeight
        
        // Check if in bottom bar area
        guard winampPoint.y >= bottomY && winampPoint.y < originalSize.height else { return nil }
        
        let relativeY = winampPoint.y - bottomY
        let x = winampPoint.x
        
        // DEBUG: Log click position in bottom bar
        NSLog("PlaylistView: Bottom bar click x=%.0f, relativeY=%.0f", x, relativeY)
        
        // Mini transport buttons - 6 buttons: prev, play, pause, stop, next, open
        // Based on edge clicks: Previous=134, Open=181, range=47px, spacing=9.4px
        // Buttons are in the lower portion of the bottom bar (y >= 12)
        if relativeY >= 12 && relativeY <= 38 && x >= 125 && x < 195 {
            NSLog("PlaylistView: Transport area click at x=%.0f", x)
            // 6 buttons equally spaced from x=134 to x=181
            // Each button ~9.4px apart, using ~8px wide hit areas centered on each
            if x >= 130 && x < 139 {  // center=134
                NSLog("PlaylistView: HIT miniPrevious")
                return .miniPrevious 
            }
            if x >= 139 && x < 148 {  // center=143.4
                NSLog("PlaylistView: HIT miniPlay")
                return .miniPlay 
            }
            if x >= 148 && x < 158 {  // center=152.8
                NSLog("PlaylistView: HIT miniPause")
                return .miniPause 
            }
            if x >= 158 && x < 167 {  // center=162.2
                NSLog("PlaylistView: HIT miniStop")
                return .miniStop 
            }
            if x >= 167 && x < 177 {  // center=171.6
                NSLog("PlaylistView: HIT miniNext")
                return .miniNext 
            }
            if x >= 177 && x < 195 {  // center=181
                NSLog("PlaylistView: HIT miniOpen")
                return .miniOpen 
            }
        }
        
        // ADD/REM/SEL buttons in the upper-left area of the bottom bar (y=0-15)
        // These should NOT overlap with the transport buttons
        if relativeY >= 0 && relativeY < 15 {
            if x >= 11 && x < 40 { return .add }
            if x >= 40 && x < 69 { return .rem }
            if x >= 69 && x < 98 { return .sel }
        }
        
        // MISC/LIST buttons on the right side
        if x >= originalSize.width - 50 {
            if x >= originalSize.width - 44 && x < originalSize.width - 22 { return .misc }
            if x >= originalSize.width - 22 && x < originalSize.width { return .list }
        }
        
        return nil
    }
    
    /// Check if point hits the scrollbar
    private func hitTestScrollbar(at winampPoint: NSPoint) -> Bool {
        let originalSize = originalWindowSize
        let titleHeight = Layout.titleBarHeight
        let bottomHeight = Layout.bottomBarHeight
        
        let scrollbarRect = NSRect(
            x: originalSize.width - Layout.rightBorder,
            y: titleHeight,
            width: Layout.rightBorder,
            height: originalSize.height - titleHeight - bottomHeight
        )
        
        return scrollbarRect.contains(winampPoint)
    }
    
    /// Check if point hits the track list
    private func hitTestTrackList(at winampPoint: NSPoint) -> Int? {
        let originalSize = originalWindowSize
        let titleHeight = Layout.titleBarHeight
        let bottomHeight = Layout.bottomBarHeight
        
        let listRect = NSRect(
            x: Layout.leftBorder,
            y: titleHeight,
            width: originalSize.width - Layout.leftBorder - Layout.rightBorder,
            height: originalSize.height - titleHeight - bottomHeight
        )
        
        guard listRect.contains(winampPoint) else { return nil }
        
        let relativeY = winampPoint.y - titleHeight + scrollOffset
        let clickedIndex = Int(relativeY / itemHeight)
        
        let tracks = WindowManager.shared.audioEngine.playlist
        if clickedIndex >= 0 && clickedIndex < tracks.count {
            return clickedIndex
        }
        
        return nil
    }
    
    // MARK: - Mouse Events
    
    /// Allow clicking even when window is not active
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
        
        // Check bottom bar buttons
        if let bottomButton = hitTestBottomButton(at: winampPoint) {
            pressedButton = bottomButton
            needsDisplay = true
            return
        }
        
        // Check scrollbar
        if hitTestScrollbar(at: winampPoint) {
            isDraggingScrollbar = true
            scrollbarDragStartY = winampPoint.y
            scrollbarDragStartOffset = scrollOffset
            return
        }
        
        // Check track list
        if let trackIndex = hitTestTrackList(at: winampPoint) {
            handleTrackClick(index: trackIndex, event: event)
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
    
    /// Handle mouse down in shade mode
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
    
    /// Handle track click (selection)
    private func handleTrackClick(index: Int, event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            // Extend selection
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
            // Toggle selection
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
        } else {
            // Single selection
            selectedIndices = [index]
        }
        
        // Double-click plays track
        if event.clickCount == 2 {
            NSLog("PlaylistView: Double-click on track %d, calling playTrack", index)
            WindowManager.shared.audioEngine.playTrack(at: index)
        }
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Handle scrollbar dragging
        if isDraggingScrollbar {
            let point = convert(event.locationInWindow, from: nil)
            let winampPoint = convertToWinampCoordinates(point)
            
            let deltaY = winampPoint.y - scrollbarDragStartY
            let tracks = WindowManager.shared.audioEngine.playlist
            let originalSize = originalWindowSize
            let listHeight = originalSize.height - Layout.titleBarHeight - Layout.bottomBarHeight
            let totalContentHeight = CGFloat(tracks.count) * itemHeight
            
            if totalContentHeight > listHeight {
                let scrollRange = totalContentHeight - listHeight
                let trackRange = listHeight - 18  // Thumb height
                let scrollDelta = (deltaY / trackRange) * scrollRange
                scrollOffset = max(0, min(scrollRange, scrollbarDragStartOffset + scrollDelta))
                needsDisplay = true
            }
            return
        }
        
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
            case .add:
                if hitTestBottomButton(at: winampPoint) == .add {
                    showAddMenu(at: point)
                }
            case .rem:
                if hitTestBottomButton(at: winampPoint) == .rem {
                    showRemoveMenu(at: point)
                }
            case .sel:
                if hitTestBottomButton(at: winampPoint) == .sel {
                    showSelectMenu(at: point)
                }
            case .misc:
                if hitTestBottomButton(at: winampPoint) == .misc {
                    showMiscMenu(at: point)
                }
            case .list:
                if hitTestBottomButton(at: winampPoint) == .list {
                    showListMenu(at: point)
                }
            // Mini transport controls
            case .miniPrevious:
                if hitTestBottomButton(at: winampPoint) == .miniPrevious {
                    performMiniTransportAction(.miniPrevious)
                }
            case .miniPlay:
                if hitTestBottomButton(at: winampPoint) == .miniPlay {
                    performMiniTransportAction(.miniPlay)
                }
            case .miniPause:
                if hitTestBottomButton(at: winampPoint) == .miniPause {
                    performMiniTransportAction(.miniPause)
                }
            case .miniStop:
                if hitTestBottomButton(at: winampPoint) == .miniStop {
                    performMiniTransportAction(.miniStop)
                }
            case .miniNext:
                if hitTestBottomButton(at: winampPoint) == .miniNext {
                    performMiniTransportAction(.miniNext)
                }
            case .miniOpen:
                if hitTestBottomButton(at: winampPoint) == .miniOpen {
                    performMiniTransportAction(.miniOpen)
                }
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    /// Perform mini transport button action
    private func performMiniTransportAction(_ button: SkinRenderer.PlaylistButtonType) {
        let engine = WindowManager.shared.audioEngine
        let isVideoActive = WindowManager.shared.isVideoActivePlayback
        
        NSLog("PlaylistView: performMiniTransportAction called for \(button), isVideoActive=\(isVideoActive)")
        
        switch button {
        case .miniPrevious:
            NSLog("PlaylistView: Executing PREVIOUS")
            if isVideoActive {
                WindowManager.shared.skipVideoBackward(10)
            } else {
                engine.previous()
            }
        case .miniPlay:
            NSLog("PlaylistView: Executing PLAY/TOGGLE, state=%@, playlist count=%d, currentTrack=%@", 
                  "\(engine.state)", engine.playlist.count, engine.currentTrack?.title ?? "nil")
            if isVideoActive {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                // Toggle play/pause for better UX
                if engine.state == .playing {
                    engine.pause()
                } else {
                    engine.play()
                }
            }
        case .miniPause:
            NSLog("PlaylistView: Executing PAUSE")
            if isVideoActive {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                engine.pause()
            }
        case .miniStop:
            print(">>> STOP BUTTON PRESSED <<<")
            NSLog("PlaylistView: Executing STOP")
            if isVideoActive {
                WindowManager.shared.stopVideo()
            } else {
                print(">>> Calling engine.stop() <<<")
                engine.stop()
            }
        case .miniNext:
            NSLog("PlaylistView: Executing NEXT")
            if isVideoActive {
                WindowManager.shared.skipVideoForward(10)
            } else {
                engine.next()
            }
        case .miniOpen:
            NSLog("PlaylistView: Executing OPEN")
            // Open file dialog to add files - same as addFiles action
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = [.audio, .movie]
            
            if panel.runModal() == .OK {
                WindowManager.shared.audioEngine.loadFiles(panel.urls)
                needsDisplay = true
            }
        default:
            break
        }
    }
    
    /// Handle mouse up in shade mode
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
            default:
                break
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        let tracks = WindowManager.shared.audioEngine.playlist
        let originalSize = originalWindowSize
        let listHeight = originalSize.height - Layout.titleBarHeight - Layout.bottomBarHeight
        let totalHeight = CGFloat(tracks.count) * itemHeight
        
        if totalHeight > listHeight {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))
            needsDisplay = true
        }
    }
    
    // MARK: - Button Popup Menus
    
    /// Show ADD button popup menu
    private func showAddMenu(at point: NSPoint) {
        let menu = NSMenu()
        
        menu.addItem(withTitle: "Add URL...", action: #selector(addURL(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Add Directory...", action: #selector(addDirectory(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Add Files...", action: #selector(addFiles(_:)), keyEquivalent: "")
        
        for item in menu.items {
            item.target = self
        }
        
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    /// Show REM button popup menu
    private func showRemoveMenu(at point: NSPoint) {
        let menu = NSMenu()
        
        menu.addItem(withTitle: "Remove All", action: #selector(removeAll(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Crop Selection", action: #selector(cropSelection(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Remove Selected", action: #selector(removeSelected(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Remove Dead Files", action: #selector(removeDeadFiles(_:)), keyEquivalent: "")
        
        for item in menu.items {
            item.target = self
        }
        
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    /// Show SEL button popup menu
    private func showSelectMenu(at point: NSPoint) {
        let menu = NSMenu()
        
        menu.addItem(withTitle: "Invert Selection", action: #selector(invertSelection(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select None", action: #selector(selectNone(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a")
        
        for item in menu.items {
            item.target = self
        }
        
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    /// Show MISC button popup menu
    private func showMiscMenu(at point: NSPoint) {
        let menu = NSMenu()
        
        let sortMenu = NSMenu()
        sortMenu.addItem(withTitle: "Sort by Title", action: #selector(sortByTitle(_:)), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Sort by Filename", action: #selector(sortByFilename(_:)), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Sort by Path", action: #selector(sortByPath(_:)), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Randomize", action: #selector(randomize(_:)), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Reverse", action: #selector(reverse(_:)), keyEquivalent: "")
        
        for item in sortMenu.items {
            item.target = self
        }
        
        let sortItem = NSMenuItem(title: "Sort", action: nil, keyEquivalent: "")
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)
        
        menu.addItem(withTitle: "File Info...", action: #selector(showFileInfo(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Playlist Options...", action: #selector(showOptions(_:)), keyEquivalent: "")
        
        for item in menu.items {
            if item.action != nil { item.target = self }
        }
        
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    /// Show LIST button popup menu
    private func showListMenu(at point: NSPoint) {
        let menu = NSMenu()
        
        menu.addItem(withTitle: "New Playlist", action: #selector(newPlaylist(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Save Playlist...", action: #selector(savePlaylist(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Load Playlist...", action: #selector(loadPlaylist(_:)), keyEquivalent: "")
        
        for item in menu.items {
            item.target = self
        }
        
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    // MARK: - Menu Actions
    
    @objc private func addURL(_ sender: Any?) {
        // Show URL input dialog
        let alert = NSAlert()
        alert.messageText = "Add URL"
        alert.informativeText = "Enter the URL of the media file:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "https://example.com/audio.mp3"
        alert.accessoryView = input
        
        if alert.runModal() == .alertFirstButtonReturn {
            let urlString = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: urlString) {
                WindowManager.shared.audioEngine.loadFiles([url])
                needsDisplay = true
            }
        }
    }
    
    @objc private func addDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            // Recursively find all audio files
            let fileManager = FileManager.default
            let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
            var audioURLs: [URL] = []
            
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                        audioURLs.append(fileURL)
                    }
                }
            }
            
            if !audioURLs.isEmpty {
                WindowManager.shared.audioEngine.loadFiles(audioURLs)
                needsDisplay = true
            }
        }
    }
    
    @objc private func addFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        
        if panel.runModal() == .OK {
            WindowManager.shared.audioEngine.loadFiles(panel.urls)
            needsDisplay = true
        }
    }
    
    @objc private func removeAll(_ sender: Any?) {
        WindowManager.shared.audioEngine.clearPlaylist()
        selectedIndices.removeAll()
        scrollOffset = 0
        needsDisplay = true
    }
    
    @objc private func cropSelection(_ sender: Any?) {
        // Keep only selected tracks
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        let indicesToRemove = Set(0..<tracks.count).subtracting(selectedIndices)
        
        // Remove in reverse order to maintain indices
        for index in indicesToRemove.sorted(by: >) {
            engine.removeTrack(at: index)
        }
        
        // Update selection indices
        selectedIndices = Set(0..<engine.playlist.count)
        needsDisplay = true
    }
    
    @objc private func removeSelected(_ sender: Any?) {
        let engine = WindowManager.shared.audioEngine
        
        // Remove in reverse order to maintain indices
        for index in selectedIndices.sorted(by: >) {
            engine.removeTrack(at: index)
        }
        
        selectedIndices.removeAll()
        needsDisplay = true
    }
    
    @objc private func removeDeadFiles(_ sender: Any?) {
        // Remove files that no longer exist
        let engine = WindowManager.shared.audioEngine
        let fileManager = FileManager.default
        
        var indicesToRemove: [Int] = []
        for (index, track) in engine.playlist.enumerated() {
            if !track.url.isFileURL || !fileManager.fileExists(atPath: track.url.path) {
                indicesToRemove.append(index)
            }
        }
        
        for index in indicesToRemove.reversed() {
            engine.removeTrack(at: index)
        }
        
        selectedIndices.removeAll()
        needsDisplay = true
    }
    
    @objc private func invertSelection(_ sender: Any?) {
        let tracks = WindowManager.shared.audioEngine.playlist
        let allIndices = Set(0..<tracks.count)
        selectedIndices = allIndices.subtracting(selectedIndices)
        needsDisplay = true
    }
    
    @objc private func selectNone(_ sender: Any?) {
        selectedIndices.removeAll()
        needsDisplay = true
    }
    
    @objc override func selectAll(_ sender: Any?) {
        let tracks = WindowManager.shared.audioEngine.playlist
        selectedIndices = Set(0..<tracks.count)
        needsDisplay = true
    }
    
    @objc private func sortByTitle(_ sender: Any?) {
        WindowManager.shared.audioEngine.sortPlaylist(by: .title)
        needsDisplay = true
    }
    
    @objc private func sortByFilename(_ sender: Any?) {
        WindowManager.shared.audioEngine.sortPlaylist(by: .filename)
        needsDisplay = true
    }
    
    @objc private func sortByPath(_ sender: Any?) {
        WindowManager.shared.audioEngine.sortPlaylist(by: .path)
        needsDisplay = true
    }
    
    @objc private func randomize(_ sender: Any?) {
        WindowManager.shared.audioEngine.shufflePlaylist()
        needsDisplay = true
    }
    
    @objc private func reverse(_ sender: Any?) {
        WindowManager.shared.audioEngine.reversePlaylist()
        needsDisplay = true
    }
    
    @objc private func showFileInfo(_ sender: Any?) {
        // Show info for selected track
        guard let index = selectedIndices.first else { return }
        let tracks = WindowManager.shared.audioEngine.playlist
        guard index < tracks.count else { return }
        
        let track = tracks[index]
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        alert.informativeText = """
        Artist: \(track.artist ?? "Unknown")
        Album: \(track.album ?? "Unknown")
        Duration: \(String(format: "%d:%02d", Int(track.duration ?? 0) / 60, Int(track.duration ?? 0) % 60))
        Path: \(track.url.path)
        """
        alert.runModal()
    }
    
    @objc private func showOptions(_ sender: Any?) {
        // Placeholder for options dialog
    }
    
    @objc private func newPlaylist(_ sender: Any?) {
        removeAll(sender)
    }
    
    @objc private func savePlaylist(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!]
        panel.nameFieldStringValue = "playlist.m3u"
        
        if panel.runModal() == .OK, let url = panel.url {
            let tracks = WindowManager.shared.audioEngine.playlist
            var content = "#EXTM3U\n"
            
            for track in tracks {
                let duration = Int(track.duration ?? 0)
                content += "#EXTINF:\(duration),\(track.displayTitle)\n"
                content += "\(track.url.path)\n"
            }
            
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    @objc private func loadPlaylist(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!, .init(filenameExtension: "m3u8")!]
        
        if panel.runModal() == .OK, let url = panel.url {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                var urls: [URL] = []
                
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                    
                    if let fileURL = URL(string: trimmed) {
                        urls.append(fileURL)
                    } else {
                        // Might be a relative path
                        let fileURL = url.deletingLastPathComponent().appendingPathComponent(trimmed)
                        urls.append(fileURL)
                    }
                }
                
                if !urls.isEmpty {
                    WindowManager.shared.audioEngine.clearPlaylist()
                    WindowManager.shared.audioEngine.loadFiles(urls)
                    needsDisplay = true
                }
            }
        }
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let engine = WindowManager.shared.audioEngine
        
        switch event.keyCode {
        case 51: // Delete - remove selected
            removeSelected(nil)
            
        case 36: // Enter - play selected
            if let index = selectedIndices.first {
                engine.playTrack(at: index)
            }
            
        case 0: // A - select all (with Cmd)
            if event.modifierFlags.contains(.command) {
                selectAll(nil)
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
        
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac", "mp4", "mkv", "avi", "mov"]
        let mediaURLs = items.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        
        if !mediaURLs.isEmpty {
            WindowManager.shared.audioEngine.loadFiles(mediaURLs)
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
