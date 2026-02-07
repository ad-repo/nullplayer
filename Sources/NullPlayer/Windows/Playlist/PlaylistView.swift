import AppKit

// =============================================================================
// PLAYLIST VIEW - Playlist editor window with skin sprite support
// =============================================================================
// Follows the same pattern as EQView for:
// - Coordinate transformation (skin top-down system)
// - Button hit testing and visual feedback
// - Popup menus for button actions
// =============================================================================

/// Playlist editor view with full skin support
class PlaylistView: NSView {
    
    // MARK: - Properties
    
    weak var controller: PlaylistWindowController?
    
    /// Selected track indices
    private var selectedIndices: Set<Int> = []
    
    /// The anchor index for shift-selection (where shift-click range starts from)
    private var selectionAnchor: Int?
    
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
    
    /// Marquee offset for scrolling current track title (in pixels)
    private var marqueeOffset: CGFloat = 0
    
    /// Width of current track title text (for marquee wrapping)
    private var currentTrackTextWidth: CGFloat = 0
    
    /// Separator width for marquee (5 spaces)
    private let marqueeSeparatorWidth: CGFloat = 5 * SkinElements.TextFont.charWidth
    
    /// Last known current track index (for detecting track changes)
    private var lastCurrentIndex: Int = -1
    
    /// Cached CGImage of TEXT.BMP to avoid calling cgImage() during draw cycle
    /// This prevents cross-window interference from NSImage.cgImage() affecting graphics state
    private var cachedTextBitmapCGImage: CGImage?
    
    // MARK: - Layout Constants
    
    private struct Layout {
        static let titleBarHeight: CGFloat = 20
        static let bottomBarHeight: CGFloat = 3  // Thin decorative border (no control bar)
        static let scrollbarWidth: CGFloat = 0   // No scrollbar - users scroll with trackpad/wheel
        static let leftBorder: CGFloat = 12
        static let rightBorder: CGFloat = 2      // Minimal edge (scrollbar track removed)
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
        
        // Only redraw when explicitly requested via setNeedsDisplay
        // This allows macOS to cache the layer contents between updates
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // Register for drag and drop
        registerForDraggedTypes([.fileURL])
        
        // Start display timer for marquee scrolling and playback time updates
        startDisplayTimer()
        
        // Set up accessibility identifiers for UI testing
        setupAccessibility()
        
        // Observe window visibility changes to pause/resume timer and marquee
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMiniaturize),
                                               name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidDeminiaturize),
                                               name: NSWindow.didDeminiaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeOcclusionState),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        
        // Observe playback state changes to restart timer when needed
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStateDidChange),
                                               name: .audioPlaybackStateChanged, object: nil)
        
        // Observe track changes to update selection highlight
        NotificationCenter.default.addObserver(self, selector: #selector(handleTrackDidChange),
                                               name: .audioTrackDidChange, object: nil)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Pre-cache TEXT.BMP CGImage when view is added to window
        cacheTextBitmapCGImage()
        updateCurrentTrackTextWidth()
        
        // Auto-select the currently playing track when playlist opens
        let engine = WindowManager.shared.audioEngine
        if selectedIndices.isEmpty && engine.currentIndex >= 0 {
            selectedIndices = [engine.currentIndex]
            selectionAnchor = engine.currentIndex
        }
    }
    
    /// Restart timer when playback starts or track changes
    @objc private func playbackStateDidChange(_ notification: Notification) {
        if WindowManager.shared.audioEngine.state == .playing {
            startDisplayTimer()
            marqueeOffset = 0
            updateCurrentTrackTextWidth()
            needsDisplay = true
        }
    }
    
    /// Update selection to follow the currently playing track
    @objc private func handleTrackDidChange(_ notification: Notification) {
        let engine = WindowManager.shared.audioEngine
        let currentIndex = engine.currentIndex
        
        // Update selection to highlight the current playing track
        guard currentIndex >= 0 && currentIndex < engine.playlist.count else { return }
        
        selectedIndices = [currentIndex]
        selectionAnchor = currentIndex
        
        // Scroll to keep the current track visible
        scrollToSelection()
        
        needsDisplay = true
    }
    
    // MARK: - Display Timer Management
    
    /// Start the display timer for marquee scrolling (8Hz - reduced for CPU efficiency)
    private func startDisplayTimer() {
        guard displayTimer == nil else { return }
        // Reduced to 8Hz (0.125s) for CPU efficiency
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
            self?.handleDisplayTimerTick()
        }
    }
    
    /// Stop the display timer to save CPU when window is not visible
    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
    
    /// Handle display timer tick - only update when needed
    private func handleDisplayTimerTick() {
        // Skip updates if window is not visible or occluded
        guard let window = window,
              window.isVisible,
              window.occlusionState.contains(.visible) else {
            return
        }
        
        let engine = WindowManager.shared.audioEngine
        let currentIndex = engine.currentIndex
        
        // Check if current track changed - reset marquee if so
        if currentIndex != lastCurrentIndex {
            lastCurrentIndex = currentIndex
            marqueeOffset = 0
            updateCurrentTrackTextWidth()
        }
        
        // Advance marquee offset if text needs scrolling
        // Scroll speed: ~24 pixels per second at 8Hz = 3 pixels per tick
        let cycleWidth = currentTrackTextWidth + marqueeSeparatorWidth
        if currentTrackTextWidth > 0 && cycleWidth > 0 {
            marqueeOffset += 3
            if marqueeOffset >= cycleWidth {
                marqueeOffset = 0
            }
            needsDisplay = true
        }
        
        // Redraw for time updates if playing, otherwise stop timer to save CPU
        if engine.state == .playing || WindowManager.shared.isVideoActivePlayback {
            needsDisplay = true
        } else if currentIndex < 0 || currentIndex >= engine.playlist.count {
            // No current track and not playing - stop the timer to save CPU
            stopDisplayTimer()
        }
    }
    
    /// Stop display timer when window is minimized to save CPU
    @objc private func windowDidMiniaturize(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        stopDisplayTimer()
    }
    
    /// Restart display timer when window is restored from minimized state
    @objc private func windowDidDeminiaturize(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        startDisplayTimer()
    }
    
    /// Handle window occlusion state changes to pause/resume display timer
    @objc private func windowDidChangeOcclusionState(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        if window?.occlusionState.contains(.visible) == true {
            startDisplayTimer()
        } else {
            stopDisplayTimer()
        }
    }
    
    // MARK: - Marquee Layer Management
    
    /// Calculate current track text width for marquee scrolling
    private func updateCurrentTrackTextWidth() {
        let engine = WindowManager.shared.audioEngine
        let currentIndex = engine.currentIndex
        
        guard currentIndex >= 0 && currentIndex < engine.playlist.count else {
            currentTrackTextWidth = 0
            return
        }
        
        let track = engine.playlist[currentIndex]
        let videoPrefix = track.mediaType == .video ? "[V] " : ""
        let titleText = "\(currentIndex + 1). \(videoPrefix)\(track.displayTitle)"
        
        // Calculate text width in skin coordinates
        let charWidth = SkinElements.TextFont.charWidth
        currentTrackTextWidth = CGFloat(titleText.count) * charWidth
    }
    
    /// No longer needed - marquee handled in draw cycle
    private func updateMarqueeLayerFrame() {
        // Marquee now handled in draw cycle with bitmap font
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
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Scaling Support
    
    /// Calculate scale factor based on WIDTH only (to match main window)
    /// This allows vertical expansion to show more tracks
    private var scaleFactor: CGFloat {
        let originalSize = originalWindowSize
        return bounds.width / originalSize.width
    }
    
    /// Get the original window size (unscaled base size)
    private var originalWindowSize: NSSize {
        if isShadeMode {
            return NSSize(width: SkinElements.Playlist.minSize.width, height: SkinElements.PlaylistShade.height)
        } else {
            return SkinElements.Playlist.minSize
        }
    }
    
    /// Get the effective window size for drawing (allows vertical expansion)
    /// Width matches original, height can be taller to show more tracks
    private var effectiveWindowSize: NSSize {
        let scale = scaleFactor
        let originalSize = originalWindowSize
        // Height in "original" coordinates based on actual window height
        let effectiveHeight = bounds.height / scale
        return NSSize(width: originalSize.width, height: max(originalSize.height, effectiveHeight))
    }
    
    /// Convert a point from view coordinates to original (unscaled) skin coordinates
    private func convertToSkinCoordinates(_ point: NSPoint) -> NSPoint {
        let scale = scaleFactor
        let effectiveSize = effectiveWindowSize
        
        // No horizontal centering needed (width-based scale)
        // Transform point back to original coordinates
        let x = point.x / scale
        // Convert from macOS coords (origin bottom-left) to skin coords (origin top-left)
        let y = effectiveSize.height - (point.y / scale)
        
        return NSPoint(x: x, y: y)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let scale = scaleFactor
        let effectiveSize = effectiveWindowSize
        
        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())
        let isActive = window?.isKeyWindow ?? true
        
        // Flip coordinate system to match skin's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // Apply width-based scaling (allows vertical expansion for more tracks)
        if scale != 1.0 {
            context.scaleBy(x: scale, y: scale)
        }
        
        // Use effective bounds for drawing (height can be taller than original for more tracks)
        let drawBounds = NSRect(origin: .zero, size: effectiveSize)
        
        if isShadeMode {
            let shadeSize = NSSize(width: effectiveSize.width, height: SkinElements.PlaylistShade.height)
            renderer.drawPlaylistShade(in: context, bounds: NSRect(origin: .zero, size: shadeSize), 
                                       isActive: isActive, pressedButton: mapToButtonType(pressedButton))
        } else {
            // Calculate scroll position for scrollbar (0-1)
            let scrollPosition = calculateScrollPosition()
            
            // Draw window frame using skin sprites (SkinRenderer tiles to fill the space)
            renderer.drawPlaylistWindow(in: context, bounds: drawBounds, isActive: isActive,
                                        pressedButton: pressedButton, scrollPosition: scrollPosition)
            
            // Draw track list in the content area
            let colors = skin?.playlistColors ?? .default
            drawTrackList(in: context, colors: colors, drawBounds: drawBounds)
            
            // Bottom bar removed - no track info or playback time rendering needed
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
        let effectiveSize = effectiveWindowSize
        let listHeight = effectiveSize.height - Layout.titleBarHeight - Layout.bottomBarHeight
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
        
        // Round scroll offset to integer pixels to prevent text shimmering on non-Retina displays
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let roundedScrollOffset = backingScale < 1.5 ? round(scrollOffset) : scrollOffset
        
        // Calculate visible range
        let visibleStart = Int(scrollOffset / itemHeight)
        let visibleEnd = min(tracks.count, visibleStart + Int(listRect.height / itemHeight) + 2)
        
        for index in visibleStart..<visibleEnd {
            // In skin coordinates, items go from top to bottom (y increases downward)
            let y = titleHeight + CGFloat(index) * itemHeight - roundedScrollOffset
            
            // Skip if outside visible area
            if y + itemHeight < titleHeight || y > drawBounds.height - bottomHeight {
                continue
            }
            
            let itemRect = NSRect(x: listRect.minX, y: y, width: listRect.width, height: itemHeight)
            
            // Draw track info
            let track = tracks[index]
            let isCurrentTrack = index == currentIndex
            let isSelected = selectedIndices.contains(index)
            let textColor = isCurrentTrack ? colors.currentText : colors.normalText
            
            // Draw track text with clipping and marquee for current track
            drawTrackText(in: context, track: track, index: index, rect: itemRect, color: textColor, font: colors.font, isCurrentTrack: isCurrentTrack, isSelected: isSelected)
        }
        
        context.restoreGState()
    }
    
    /// Draw track text using bitmap font (TEXT.BMP) - same font as main window
    /// Current track uses marquee scrolling for long titles
    /// Selected tracks are drawn in white
    private func drawTrackText(in context: CGContext, track: Track, index: Int, rect: NSRect, color: NSColor, font: NSFont, isCurrentTrack: Bool = false, isSelected: Bool = false) {
        let skin = WindowManager.shared.currentSkin
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        
        // Calculate dimensions
        let duration = track.duration ?? 0
        let durationStr = String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
        let durationWidth = CGFloat(durationStr.count) * charWidth
        let durationX = rect.maxX - durationWidth - 4
        let titleX = rect.minX + 2
        let titleMaxWidth = durationX - titleX - 6
        
        // Prepend [V] indicator for video tracks
        let videoPrefix = track.mediaType == .video ? "[V] " : ""
        let titleText = "\(index + 1). \(videoPrefix)\(track.displayTitle)"
        
        // Vertical centering
        let textY = rect.minY + (rect.height - charHeight) / 2
        
        // Draw duration (right-aligned) using bitmap font
        drawBitmapText(durationStr, at: NSPoint(x: durationX, y: textY), in: context, skin: skin, isSelected: isSelected)
        
        // Draw title (clipped to available width)
        context.saveGState()
        context.clip(to: NSRect(x: titleX, y: rect.minY, width: titleMaxWidth, height: rect.height))
        
        let titleWidth = CGFloat(titleText.count) * charWidth
        
        if isCurrentTrack && titleWidth > titleMaxWidth {
            // Current track with long title - draw with marquee scrolling
            let cycleWidth = titleWidth + marqueeSeparatorWidth
            
            // Draw first copy
            let xOffset1 = titleX - marqueeOffset
            drawBitmapText(titleText, at: NSPoint(x: xOffset1, y: textY), in: context, skin: skin, isSelected: isSelected)
            
            // Draw second copy for seamless loop
            let xOffset2 = xOffset1 + cycleWidth
            if xOffset2 < titleX + titleMaxWidth {
                drawBitmapText(titleText, at: NSPoint(x: xOffset2, y: textY), in: context, skin: skin, isSelected: isSelected)
            }
        } else {
            // Non-current track or short title - draw normally
            drawBitmapText(titleText, at: NSPoint(x: titleX, y: textY), in: context, skin: skin, isSelected: isSelected)
        }
        
        context.restoreGState()
    }
    
    /// Draw text using bitmap font from skin's TEXT.BMP
    /// Context is already flipped to skin coordinates (Y=0 at top)
    /// Pre-cache the CGImage for TEXT.BMP when skin changes
    /// MUST be called outside of draw cycle to avoid graphics state interference
    private func cacheTextBitmapCGImage() {
        cachedTextBitmapCGImage = nil
        
        guard let skin = WindowManager.shared.currentSkin,
              let textImage = skin.text else { return }
        
        // Get CGImage from NSImage - this is safe to call outside of draw cycle
        guard let sourceImage = textImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        // Cache it
        cachedTextBitmapCGImage = sourceImage
    }
    
    private func drawBitmapText(_ text: String, at position: NSPoint, in context: CGContext, skin: Skin?, isSelected: Bool = false) {
        // Use pre-cached CGImage - NEVER call cgImage() during draw cycle
        guard let cgImage = cachedTextBitmapCGImage else { return }
        
        let charWidth = Int(SkinElements.TextFont.charWidth)
        let charHeight = Int(SkinElements.TextFont.charHeight)
        var xPos = position.x
        
        for char in text.uppercased() {
            // Get source rect - SkinElements returns skin coords (Y=0 at top)
            // CGImage also uses Y=0 at top, so no flip needed for cropping
            let charRect = SkinElements.TextFont.character(char)
            let cropRect = CGRect(x: charRect.origin.x, y: charRect.origin.y,
                                  width: charRect.width, height: charRect.height)
            
            if let cropped = cgImage.cropping(to: cropRect) {
                // For selected tracks, convert green to white using pixel manipulation
                let imageToDraw: CGImage
                if isSelected {
                    imageToDraw = convertToWhite(cropped, charWidth: charWidth, charHeight: charHeight) ?? cropped
                } else {
                    imageToDraw = cropped
                }
                
                // Draw with flip - context is in skin coords, need to flip sprite
                context.saveGState()
                context.translateBy(x: xPos, y: position.y + CGFloat(charHeight))
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .none
                context.draw(imageToDraw, in: CGRect(x: 0, y: 0, width: charWidth, height: charHeight))
                context.restoreGState()
            }
            
            xPos += CGFloat(charWidth)
        }
    }
    
    /// Convert green text to white using pixel manipulation (same approach as SkinRenderer.drawSkinTextWhite)
    private func convertToWhite(_ charImage: CGImage, charWidth: Int, charHeight: Int) -> CGImage? {
        // Create offscreen buffer and draw character
        guard let offscreenContext = CGContext(
            data: nil,
            width: charWidth,
            height: charHeight,
            bitsPerComponent: 8,
            bytesPerRow: charWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        offscreenContext.draw(charImage, in: CGRect(x: 0, y: 0, width: charWidth, height: charHeight))
        
        // Direct pixel conversion: green (0, G, 0) -> white (G, G, G)
        guard let data = offscreenContext.data else { return nil }
        
        let pixels = data.bindMemory(to: UInt8.self, capacity: charWidth * charHeight * 4)
        for i in 0..<(charWidth * charHeight) {
            let offset = i * 4
            let r = pixels[offset]
            let g = pixels[offset + 1]
            let b = pixels[offset + 2]
            let a = pixels[offset + 3]
            
            // Skip fully transparent pixels
            if a == 0 { continue }
            
            // Check if it's magenta background (skip those)
            let isMagenta = r > 200 && g < 50 && b > 200
            if isMagenta {
                // Make magenta transparent
                pixels[offset + 3] = 0
            } else {
                // Convert green to white: use green value for all channels
                let brightness = g
                pixels[offset] = brightness     // R
                pixels[offset + 1] = brightness // G
                pixels[offset + 2] = brightness // B
            }
        }
        
        return offscreenContext.makeImage()
    }
    
    /// Draw time/info display at the bottom of the track list area (just above the bottom bar)
    /// Uses bitmap font to avoid cross-window font interference
    private func drawTimeDisplay(in context: CGContext, drawBounds: NSRect) {
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        let currentTime = engine.currentTime
        let duration = engine.duration
        let skin = WindowManager.shared.currentSkin
        
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        
        // Position just above the bottom bar, in the track list area
        let infoY = drawBounds.height - Layout.bottomBarHeight - 14
        
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
        
        // Show track count and total time on the right side using bitmap font
        let infoStr = "\(tracks.count) TRACKS / \(totalTimeStr)"
        let infoWidth = CGFloat(infoStr.count) * charWidth
        let infoX = drawBounds.width - Layout.rightBorder - infoWidth - 4
        drawBitmapText(infoStr, at: NSPoint(x: infoX, y: infoY), in: context, skin: skin)
        
        // Show current playback time on the left side if playing
        if engine.state == .playing || currentTime > 0 {
            let playTimeStr = String(format: "%d:%02d / %d:%02d",
                                    Int(currentTime) / 60, Int(currentTime) % 60,
                                    Int(duration) / 60, Int(duration) % 60)
            drawBitmapText(playTimeStr, at: NSPoint(x: Layout.leftBorder + 4, y: infoY), in: context, skin: skin)
        }
    }
    
    /// Draw track count and total time info in bottom bar using skin font
    /// Shows REMAINING tracks and countdown time
    private func drawBottomBarInfo(in context: CGContext, drawBounds: NSRect, renderer: SkinRenderer) {
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        let isVideoActive = WindowManager.shared.isVideoActivePlayback
        
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
        // Use video time if video is active, otherwise use audio engine
        let currentTime: TimeInterval
        let currentDuration: TimeInterval
        let isPlaying: Bool
        
        if isVideoActive {
            currentTime = WindowManager.shared.videoCurrentTime
            currentDuration = WindowManager.shared.videoDuration
            isPlaying = WindowManager.shared.isVideoPlaying
        } else {
            currentTime = engine.currentTime
            currentDuration = engine.duration
            isPlaying = engine.state == .playing
        }
        
        if isPlaying || currentTime > 0 {
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
        let trackCountStr = "\(remainingTracks)/"
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
        let isVideoActive = WindowManager.shared.isVideoActivePlayback
        
        // Get current time and playing state from video or audio engine
        let currentTime: TimeInterval
        let isPlaying: Bool
        
        if isVideoActive {
            currentTime = WindowManager.shared.videoCurrentTime
            isPlaying = WindowManager.shared.isVideoPlaying
        } else {
            currentTime = engine.currentTime
            isPlaying = engine.state == .playing
        }
        
        // Only draw if playing or has position
        guard isPlaying || currentTime > 0 else { return }
        
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
        selectionAnchor = nil
        scrollOffset = 0
        lastCurrentIndex = -1
        marqueeOffset = 0
        updateCurrentTrackTextWidth()
        needsDisplay = true
    }
    
    func skinDidChange() {
        // Pre-cache the TEXT.BMP CGImage for the new skin
        // This MUST happen outside of the draw cycle
        cacheTextBitmapCGImage()
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
    private func hitTestTitleBar(at skinPoint: NSPoint) -> Bool {
        let effectiveSize = effectiveWindowSize
        return skinPoint.y < Layout.titleBarHeight && 
               skinPoint.x < effectiveSize.width - 30  // Leave room for window buttons
    }
    
    /// Check if point hits close button (enlarged hit area extends to right edge and top)
    private func hitTestCloseButton(at skinPoint: NSPoint) -> Bool {
        let effectiveSize = effectiveWindowSize
        let closeRect = NSRect(x: effectiveSize.width - 20, y: 0, width: 20, height: 14)
        return closeRect.contains(skinPoint)
    }
    
    /// Check if point hits shade button (enlarged hit area, full title bar height)
    private func hitTestShadeButton(at skinPoint: NSPoint) -> Bool {
        let effectiveSize = effectiveWindowSize
        let shadeRect = NSRect(x: effectiveSize.width - 31, y: 0, width: 11, height: 14)
        return shadeRect.contains(skinPoint)
    }
    
    /// Check if point hits a bottom bar button, return which one
    private func hitTestBottomButton(at skinPoint: NSPoint) -> SkinRenderer.PlaylistButtonType? {
        let effectiveSize = effectiveWindowSize
        let bottomY = effectiveSize.height - Layout.bottomBarHeight
        
        // Check if in bottom bar area
        guard skinPoint.y >= bottomY && skinPoint.y < effectiveSize.height else { return nil }
        
        let relativeY = skinPoint.y - bottomY
        let x = skinPoint.x
        
        // Mini transport buttons - 6 buttons: prev, play, pause, stop, next, open
        // Based on edge clicks: Previous=134, Open=181, range=47px, spacing=9.4px
        // Buttons are in the lower portion of the bottom bar (y >= 12)
        if relativeY >= 12 && relativeY <= 38 && x >= 125 && x < 195 {
            // 6 buttons equally spaced from x=134 to x=181
            // Each button ~9.4px apart, using ~8px wide hit areas centered on each
            if x >= 130 && x < 139 { return .miniPrevious }
            if x >= 139 && x < 148 { return .miniPlay }
            if x >= 148 && x < 158 { return .miniPause }
            if x >= 158 && x < 167 { return .miniStop }
            if x >= 167 && x < 177 { return .miniNext }
            if x >= 177 && x < 195 { return .miniOpen }
        }
        
        // ADD/REM/SEL buttons in the upper-left area of the bottom bar (y=0-15)
        // These should NOT overlap with the transport buttons
        if relativeY >= 0 && relativeY < 15 {
            if x >= 11 && x < 40 { return .add }
            if x >= 40 && x < 69 { return .rem }
            if x >= 69 && x < 98 { return .sel }
        }
        
        // MISC/LIST buttons on the right side
        if x >= effectiveSize.width - 50 {
            if x >= effectiveSize.width - 44 && x < effectiveSize.width - 22 { return .misc }
            if x >= effectiveSize.width - 22 && x < effectiveSize.width { return .list }
        }
        
        return nil
    }
    
    /// Check if point hits the scrollbar (disabled - no scrollbar widget)
    private func hitTestScrollbar(at skinPoint: NSPoint) -> Bool {
        return false
    }
    
    /// Check if point hits the track list
    private func hitTestTrackList(at skinPoint: NSPoint) -> Int? {
        let effectiveSize = effectiveWindowSize
        let titleHeight = Layout.titleBarHeight
        let bottomHeight = Layout.bottomBarHeight
        
        let listRect = NSRect(
            x: Layout.leftBorder,
            y: titleHeight,
            width: effectiveSize.width - Layout.leftBorder - Layout.rightBorder,
            height: effectiveSize.height - titleHeight - bottomHeight
        )
        
        guard listRect.contains(skinPoint) else { return nil }
        
        let relativeY = skinPoint.y - titleHeight + scrollOffset
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
        let skinPoint = convertToSkinCoordinates(point)
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 && hitTestTitleBar(at: skinPoint) {
            toggleShadeMode()
            return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: skinPoint, event: event)
            return
        }
        
        // Check window control buttons
        if hitTestCloseButton(at: skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if hitTestShadeButton(at: skinPoint) {
            pressedButton = .shade
            needsDisplay = true
            return
        }
        
        // Check bottom bar buttons
        if let bottomButton = hitTestBottomButton(at: skinPoint) {
            pressedButton = bottomButton
            needsDisplay = true
            return
        }
        
        // Check scrollbar
        if hitTestScrollbar(at: skinPoint) {
            isDraggingScrollbar = true
            scrollbarDragStartY = skinPoint.y
            scrollbarDragStartOffset = scrollOffset
            return
        }
        
        // Check track list
        if let trackIndex = hitTestTrackList(at: skinPoint) {
            handleTrackClick(index: trackIndex, event: event)
            return
        }
        
        // Title bar - start window drag (can undock)
        if hitTestTitleBar(at: skinPoint) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
        }
    }
    
    /// Handle mouse down in shade mode
    private func handleShadeMouseDown(at skinPoint: NSPoint, event: NSEvent) {
        let effectiveSize = effectiveWindowSize
        // Check window control buttons - close first for priority (enlarged hit areas)
        let closeRect = NSRect(x: effectiveSize.width + SkinElements.PlaylistShade.HitPositions.closeButton.minX,
                               y: SkinElements.PlaylistShade.HitPositions.closeButton.minY,
                               width: SkinElements.PlaylistShade.HitPositions.closeButton.width,
                               height: SkinElements.PlaylistShade.HitPositions.closeButton.height)
        let shadeRect = NSRect(x: effectiveSize.width + SkinElements.PlaylistShade.HitPositions.shadeButton.minX,
                               y: SkinElements.PlaylistShade.HitPositions.shadeButton.minY,
                               width: SkinElements.PlaylistShade.HitPositions.shadeButton.width,
                               height: SkinElements.PlaylistShade.HitPositions.shadeButton.height)
        
        if closeRect.contains(skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if shadeRect.contains(skinPoint) {
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
            // Extend selection from anchor
            let anchor = selectionAnchor ?? selectedIndices.min() ?? index
            let start = min(anchor, index)
            let end = max(anchor, index)
            selectedIndices = Set(start...end)
            // Don't update anchor - shift-click extends from existing anchor
        } else if event.modifierFlags.contains(.command) {
            // Toggle selection
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
            // Set anchor to clicked item for future shift-clicks
            selectionAnchor = index
        } else {
            // Single selection - set new anchor
            selectedIndices = [index]
            selectionAnchor = index
        }
        
        // Double-click plays track
        if event.clickCount == 2 {
            WindowManager.shared.audioEngine.playTrack(at: index)
        }
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Handle scrollbar dragging
        if isDraggingScrollbar {
            let point = convert(event.locationInWindow, from: nil)
            let skinPoint = convertToSkinCoordinates(point)
            
            let deltaY = skinPoint.y - scrollbarDragStartY
            let tracks = WindowManager.shared.audioEngine.playlist
            let effectiveSize = effectiveWindowSize
            let listHeight = effectiveSize.height - Layout.titleBarHeight - Layout.bottomBarHeight
            let totalContentHeight = CGFloat(tracks.count) * itemHeight
            
            if totalContentHeight > listHeight {
                let scrollRange = totalContentHeight - listHeight
                let trackRange = listHeight - 18  // Thumb height
                let scrollDelta = (deltaY / trackRange) * scrollRange
                scrollOffset = max(0, min(scrollRange, scrollbarDragStartOffset + scrollDelta))
                updateMarqueeLayerFrame()  // Update marquee position after scroll
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
        let skinPoint = convertToSkinCoordinates(point)
        
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
            handleShadeMouseUp(at: skinPoint)
            return
        }
        
        // Handle button releases
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestCloseButton(at: skinPoint) {
                    window?.close()
                }
            case .shade:
                if hitTestShadeButton(at: skinPoint) {
                    toggleShadeMode()
                }
            case .add:
                if hitTestBottomButton(at: skinPoint) == .add {
                    showAddMenu(at: point)
                }
            case .rem:
                if hitTestBottomButton(at: skinPoint) == .rem {
                    showRemoveMenu(at: point)
                }
            case .sel:
                if hitTestBottomButton(at: skinPoint) == .sel {
                    showSelectMenu(at: point)
                }
            case .misc:
                if hitTestBottomButton(at: skinPoint) == .misc {
                    showMiscMenu(at: point)
                }
            case .list:
                if hitTestBottomButton(at: skinPoint) == .list {
                    showListMenu(at: point)
                }
            // Mini transport controls
            case .miniPrevious:
                if hitTestBottomButton(at: skinPoint) == .miniPrevious {
                    performMiniTransportAction(.miniPrevious)
                }
            case .miniPlay:
                if hitTestBottomButton(at: skinPoint) == .miniPlay {
                    performMiniTransportAction(.miniPlay)
                }
            case .miniPause:
                if hitTestBottomButton(at: skinPoint) == .miniPause {
                    performMiniTransportAction(.miniPause)
                }
            case .miniStop:
                if hitTestBottomButton(at: skinPoint) == .miniStop {
                    performMiniTransportAction(.miniStop)
                }
            case .miniNext:
                if hitTestBottomButton(at: skinPoint) == .miniNext {
                    performMiniTransportAction(.miniNext)
                }
            case .miniOpen:
                if hitTestBottomButton(at: skinPoint) == .miniOpen {
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
        
        switch button {
        case .miniPrevious:
            if isVideoActive {
                WindowManager.shared.skipVideoBackward(10)
            } else {
                engine.previous()
            }
        case .miniPlay:
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
            if isVideoActive {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                engine.pause()
            }
        case .miniStop:
            if isVideoActive {
                WindowManager.shared.stopVideo()
            } else {
                engine.stop()
            }
        case .miniNext:
            if isVideoActive {
                WindowManager.shared.skipVideoForward(10)
            } else {
                engine.next()
            }
        case .miniOpen:
            // Open file dialog to add files
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
    private func handleShadeMouseUp(at skinPoint: NSPoint) {
        let effectiveSize = effectiveWindowSize
        if let pressed = pressedButton {
            let closeRect = NSRect(x: effectiveSize.width + SkinElements.PlaylistShade.HitPositions.closeButton.minX,
                                   y: SkinElements.PlaylistShade.HitPositions.closeButton.minY,
                                   width: SkinElements.PlaylistShade.HitPositions.closeButton.width,
                                   height: SkinElements.PlaylistShade.HitPositions.closeButton.height)
            let shadeRect = NSRect(x: effectiveSize.width + SkinElements.PlaylistShade.HitPositions.shadeButton.minX,
                                   y: SkinElements.PlaylistShade.HitPositions.shadeButton.minY,
                                   width: SkinElements.PlaylistShade.HitPositions.shadeButton.width,
                                   height: SkinElements.PlaylistShade.HitPositions.shadeButton.height)
            
            switch pressed {
            case .close:
                if closeRect.contains(skinPoint) {
                    window?.close()
                }
            case .shade:
                if shadeRect.contains(skinPoint) {
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
        let effectiveSize = effectiveWindowSize
        let listHeight = effectiveSize.height - Layout.titleBarHeight - Layout.bottomBarHeight
        let totalHeight = CGFloat(tracks.count) * itemHeight
        
        if totalHeight > listHeight {
            scrollOffset = max(0, min(totalHeight - listHeight, scrollOffset - event.deltaY * 3))
            updateMarqueeLayerFrame()  // Update marquee position after scroll
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
        selectionAnchor = nil
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
        selectionAnchor = 0
        needsDisplay = true
    }
    
    @objc private func removeSelected(_ sender: Any?) {
        let engine = WindowManager.shared.audioEngine
        
        // Remove in reverse order to maintain indices
        for index in selectedIndices.sorted(by: >) {
            engine.removeTrack(at: index)
        }
        
        selectedIndices.removeAll()
        selectionAnchor = nil
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
        selectionAnchor = nil
        needsDisplay = true
    }
    
    @objc private func invertSelection(_ sender: Any?) {
        let tracks = WindowManager.shared.audioEngine.playlist
        let allIndices = Set(0..<tracks.count)
        selectedIndices = allIndices.subtracting(selectedIndices)
        selectionAnchor = selectedIndices.min()
        needsDisplay = true
    }
    
    @objc private func selectNone(_ sender: Any?) {
        selectedIndices.removeAll()
        selectionAnchor = nil
        needsDisplay = true
    }
    
    @objc override func selectAll(_ sender: Any?) {
        let tracks = WindowManager.shared.audioEngine.playlist
        selectedIndices = Set(0..<tracks.count)
        selectionAnchor = 0
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
        let tracks = engine.playlist
        let hasShift = event.modifierFlags.contains(.shift)
        
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
            
        case 126: // Up arrow - move selection up
            guard !tracks.isEmpty else { return }
            navigateSelection(direction: -1, extend: hasShift)
            
        case 125: // Down arrow - move selection down
            guard !tracks.isEmpty else { return }
            navigateSelection(direction: 1, extend: hasShift)
            
        case 115: // Home - go to first track
            guard !tracks.isEmpty else { return }
            if hasShift {
                extendSelectionTo(0)
            } else {
                selectedIndices = [0]
                selectionAnchor = 0
            }
            scrollToSelection()
            needsDisplay = true
            
        case 119: // End - go to last track
            guard !tracks.isEmpty else { return }
            let lastIndex = tracks.count - 1
            if hasShift {
                extendSelectionTo(lastIndex)
            } else {
                selectedIndices = [lastIndex]
                selectionAnchor = lastIndex
            }
            scrollToSelection()
            needsDisplay = true
            
        case 116: // Page Up - move selection up by visible page
            guard !tracks.isEmpty else { return }
            let visibleCount = visibleTrackCount
            navigateSelection(direction: -visibleCount, extend: hasShift)
            
        case 121: // Page Down - move selection down by visible page
            guard !tracks.isEmpty else { return }
            let visibleCount = visibleTrackCount
            navigateSelection(direction: visibleCount, extend: hasShift)
            
        default:
            super.keyDown(with: event)
        }
    }
    
    /// Number of tracks visible in the current view
    private var visibleTrackCount: Int {
        let effectiveSize = effectiveWindowSize
        let listHeight = effectiveSize.height - Layout.titleBarHeight - Layout.bottomBarHeight
        return max(1, Int(listHeight / itemHeight))
    }
    
    /// Navigate selection by a direction amount (-1 = up, 1 = down, or larger for page jumps)
    private func navigateSelection(direction: Int, extend: Bool) {
        let tracks = WindowManager.shared.audioEngine.playlist
        guard !tracks.isEmpty else { return }
        
        // Determine the current focus index (where we navigate from)
        let currentFocus: Int
        if let anchor = selectionAnchor, selectedIndices.contains(anchor) {
            // Use the selection anchor if it's still selected
            currentFocus = anchor
        } else if direction < 0 {
            // Moving up: start from the topmost selected item
            currentFocus = selectedIndices.min() ?? 0
        } else {
            // Moving down: start from the bottommost selected item
            currentFocus = selectedIndices.max() ?? 0
        }
        
        // Calculate new index, clamped to valid range
        let newIndex = max(0, min(tracks.count - 1, currentFocus + direction))
        
        if extend {
            extendSelectionTo(newIndex)
        } else {
            selectedIndices = [newIndex]
            selectionAnchor = newIndex
        }
        
        scrollToSelection()
        needsDisplay = true
    }
    
    /// Extend selection from anchor to the given index
    private func extendSelectionTo(_ targetIndex: Int) {
        let anchor = selectionAnchor ?? selectedIndices.min() ?? 0
        let start = min(anchor, targetIndex)
        let end = max(anchor, targetIndex)
        selectedIndices = Set(start...end)
        // Keep anchor unchanged so user can continue extending
    }
    
    /// Scroll to ensure the current selection is visible
    private func scrollToSelection() {
        guard let focusIndex = selectionAnchor ?? selectedIndices.min() else { return }
        
        let effectiveSize = effectiveWindowSize
        let listHeight = effectiveSize.height - Layout.titleBarHeight - Layout.bottomBarHeight
        let tracks = WindowManager.shared.audioEngine.playlist
        
        // Calculate the top and bottom of the selected item
        let itemTop = CGFloat(focusIndex) * itemHeight
        let itemBottom = itemTop + itemHeight
        
        // Calculate visible range
        let visibleTop = scrollOffset
        let visibleBottom = scrollOffset + listHeight
        
        // Scroll to keep selection visible
        if itemTop < visibleTop {
            // Item is above visible area - scroll up
            scrollOffset = itemTop
        } else if itemBottom > visibleBottom {
            // Item is below visible area - scroll down
            scrollOffset = itemBottom - listHeight
        }
        
        // Clamp scroll offset to valid range
        let totalContentHeight = CGFloat(tracks.count) * itemHeight
        let maxScroll = max(0, totalContentHeight - listHeight)
        scrollOffset = max(0, min(maxScroll, scrollOffset))
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
        var mediaURLs: [URL] = []
        
        for url in items {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Scan folder recursively for audio files
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                                mediaURLs.append(fileURL)
                            }
                        }
                    }
                } else {
                    // Add individual audio file
                    if audioExtensions.contains(url.pathExtension.lowercased()) {
                        mediaURLs.append(url)
                    }
                }
            }
        }
        
        // Sort files alphabetically
        mediaURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        if !mediaURLs.isEmpty {
            let audioEngine = WindowManager.shared.audioEngine
            let firstNewIndex = audioEngine.playlist.count  // Index where first new track will be
            audioEngine.appendFiles(mediaURLs)  // Append without replacing playlist
            audioEngine.playTrack(at: firstNewIndex)  // Start playing first dropped file
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
