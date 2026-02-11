import AppKit
import AVFoundation

// =============================================================================
// MODERN PLAYLIST VIEW - Playlist editor with modern skin chrome
// =============================================================================
// Renders track list with NSFont, modern skin window chrome, popup menus,
// selection, scrolling, marquee, keyboard navigation, and drag-and-drop.
//
// Has ZERO dependencies on the classic skin system (Skin/, SkinElements, SkinRenderer, etc.).
// =============================================================================

/// Modern playlist view with full modern skin support
class ModernPlaylistView: NSView {
    
    // MARK: - Properties
    
    weak var controller: ModernPlaylistWindowController?
    
    /// The skin renderer
    private var renderer: ModernSkinRenderer!
    
    
    /// Selected track indices
    private var selectedIndices: Set<Int> = []
    
    /// The anchor index for shift-selection
    private var selectionAnchor: Int?
    
    /// Scroll offset (in pixels)
    private var scrollOffset: CGFloat = 0
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: String?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Display update timer for marquee scrolling and playback time updates
    private var displayTimer: Timer?
    
    /// Marquee offset for scrolling current track title
    private var marqueeOffset: CGFloat = 0
    
    /// Width of current track title text (for marquee wrapping)
    private var currentTrackTextWidth: CGFloat = 0
    
    /// Last known current track index (for detecting track changes)
    private var lastCurrentIndex: Int = -1
    
    // MARK: - Artwork Background State
    
    /// Current artwork image for background display
    private var currentArtwork: NSImage?
    
    /// Track ID for the currently displayed artwork (to avoid reloading)
    private var artworkTrackId: UUID?
    
    /// Async task for loading artwork (can be cancelled)
    private var artworkLoadTask: Task<Void, Never>?
    
    /// Static image cache shared across playlist instances
    private static let artworkCache = NSCache<NSString, NSImage>()
    
    // MARK: - Layout Constants
    
    private var titleBarHeight: CGFloat { WindowManager.shared.hideTitleBars ? borderWidth : ModernSkinElements.playlistTitleBarHeight }
    private var bottomBarHeight: CGFloat { ModernSkinElements.playlistBottomBarHeight }
    private var borderWidth: CGFloat { ModernSkinElements.playlistBorderWidth }
    private var itemHeight: CGFloat { ModernSkinElements.playlistItemHeight }
    
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
        
        // Initialize with current skin
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        
        
        // Register for drag and drop
        registerForDraggedTypes([.fileURL])
        
        // Start display timer
        startDisplayTimer()
        
        // Observe skin changes
        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                                name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        
        // Observe double size changes
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                                name: .doubleSizeDidChange, object: nil)
        
        // Observe window visibility for timer management
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMiniaturize),
                                               name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidDeminiaturize),
                                               name: NSWindow.didDeminiaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeOcclusionState),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        
        // Observe playback state and track changes
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStateDidChange),
                                               name: .audioPlaybackStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTrackDidChange),
                                               name: .audioTrackDidChange, object: nil)
        
        // Set accessibility
        setAccessibilityIdentifier("modernPlaylistView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Playlist")
        
        // Load artwork for currently playing track (if any)
        loadArtwork(for: WindowManager.shared.audioEngine.currentTrack)
    }
    
    deinit {
        displayTimer?.invalidate()
        artworkLoadTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    
    
    // MARK: - Display Timer
    
    private func startDisplayTimer() {
        displayTimer?.invalidate()
        // 30Hz for smooth marquee scrolling (matching main window smoothness)
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
    }
    
    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
    
    private func timerTick() {
        let engine = WindowManager.shared.audioEngine
        let currentIndex = engine.currentIndex
        
        // Check for track change
        if currentIndex != lastCurrentIndex {
            lastCurrentIndex = currentIndex
            marqueeOffset = 0
            updateCurrentTrackTextWidth()
            // Auto-select and scroll to current track
            if currentIndex >= 0 {
                selectedIndices = [currentIndex]
                selectionAnchor = currentIndex
                scrollToSelection()
            }
        }
        
        // Advance marquee for current track
        let separatorWidth: CGFloat = 30
        if currentTrackTextWidth > 0 {
            let listWidth = bounds.width - borderWidth * 2 - 8
            if currentTrackTextWidth > listWidth * 0.7 {
                marqueeOffset += 0.8  // ~24px/sec at 30Hz -- smooth sub-pixel scrolling
                let cycleWidth = currentTrackTextWidth + separatorWidth
                if marqueeOffset >= cycleWidth {
                    marqueeOffset -= cycleWidth
                }
            }
        }
        
        // Redraw for time display updates and marquee
        if engine.state == .playing || marqueeOffset > 0 {
            needsDisplay = true
        }
    }
    
    private func updateCurrentTrackTextWidth() {
        let engine = WindowManager.shared.audioEngine
        guard engine.currentIndex >= 0 && engine.currentIndex < engine.playlist.count else {
            currentTrackTextWidth = 0
            return
        }
        let track = engine.playlist[engine.currentIndex]
        let videoPrefix = track.mediaType == .video ? "[V] " : ""
        let titleText = "\(engine.currentIndex + 1). \(videoPrefix)\(track.displayTitle)"
        
        let font = renderer.skin.smallLabelFont()
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = NSAttributedString(string: titleText, attributes: attrs).size()
        currentTrackTextWidth = size.width
    }
    
    // MARK: - Notification Handlers
    
    @objc private func modernSkinDidChange() {
        skinDidChange()
    }
    
    @objc private func doubleSizeChanged() {
        skinDidChange()
    }
    
    @objc private func windowDidMiniaturize(_ note: Notification) {
        stopDisplayTimer()
    }
    
    @objc private func windowDidDeminiaturize(_ note: Notification) {
        startDisplayTimer()
    }
    
    @objc private func windowDidChangeOcclusionState(_ note: Notification) {
        guard let window = window else { return }
        if window.occlusionState.contains(.visible) {
            if displayTimer == nil { startDisplayTimer() }
        } else {
            stopDisplayTimer()
        }
    }
    
    @objc private func playbackStateDidChange(_ note: Notification) {
        if WindowManager.shared.audioEngine.state == .playing {
            if displayTimer == nil { startDisplayTimer() }
        }
        needsDisplay = true
    }
    
    @objc private func handleTrackDidChange(_ note: Notification) {
        loadArtwork(for: WindowManager.shared.audioEngine.currentTrack)
        needsDisplay = true
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw window background
        renderer.drawWindowBackground(in: bounds, context: context)
        
        // Draw window border with glow
        renderer.drawWindowBorder(in: bounds, context: context)
        
        // Draw title bar (unless hidden)
        if !WindowManager.shared.hideTitleBars {
            renderer.drawTitleBar(in: titleBarBaseRect, title: "NULLPLAYER PLAYLIST", context: context)
            
            // Draw close button
            let closeState = (pressedButton == "playlist_btn_close") ? "pressed" : "normal"
            renderer.drawWindowControlButton("playlist_btn_close", state: closeState,
                                             in: closeBtnBaseRect, context: context)
            
            // Draw shade button
            let shadeState = (pressedButton == "playlist_btn_shade") ? "pressed" : "normal"
            renderer.drawWindowControlButton("playlist_btn_shade", state: shadeState,
                                             in: shadeBtnBaseRect, context: context)
        }
        
        if isShadeMode {
            return
        }
        
        // Draw track list
        drawTrackList(in: context)
    }
    
    /// Base rects in the 275x116 coordinate space (renderer scales them)
    private var titleBarBaseRect: NSRect {
        // Title bar is at top; we calculate in unscaled base space
        let scale = ModernSkinElements.scaleFactor
        return NSRect(x: 0, y: (bounds.height / scale) - 14, width: 275, height: 14)
    }
    
    private var closeBtnBaseRect: NSRect {
        let scale = ModernSkinElements.scaleFactor
        return NSRect(x: 261, y: (bounds.height / scale) - 12, width: 10, height: 10)
    }
    
    private var shadeBtnBaseRect: NSRect {
        let scale = ModernSkinElements.scaleFactor
        return NSRect(x: 249, y: (bounds.height / scale) - 12, width: 10, height: 10)
    }
    
    // MARK: - Track List Drawing
    
    private func drawTrackList(in context: CGContext) {
        let listRect = calculateListArea()
        
        // During window resize animations (e.g. double-size toggle, monitor disconnect),
        // bounds can temporarily be smaller than titleBar + border, producing a negative
        // listRect height. Bail out to avoid Range precondition failure in visible range calc.
        guard listRect.width > 0, listRect.height > 0 else { return }
        
        context.saveGState()
        context.clip(to: listRect)
        
        // Draw album art background behind tracks
        drawArtworkBackground(in: listRect, context: context)
        
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        let currentIndex = engine.currentIndex
        let skin = renderer.skin
        
        let scale = ModernSkinElements.scaleFactor
        let font = skin.playlistFont()
        
        guard !tracks.isEmpty else {
            // Draw empty playlist message
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: skin.textDimColor.withAlphaComponent(0.5)
            ]
            let msg = NSAttributedString(string: "Drop files here", attributes: attrs)
            let size = msg.size()
            msg.draw(at: NSPoint(x: listRect.midX - size.width / 2,
                                  y: listRect.midY - size.height / 2))
            context.restoreGState()
            return
        }
        
        // Calculate visible range
        let visibleStart = max(0, Int(scrollOffset / itemHeight))
        let visibleEnd = max(visibleStart, min(tracks.count, visibleStart + Int(listRect.height / itemHeight) + 2))
        
        for index in visibleStart..<visibleEnd {
            let y = listRect.maxY - CGFloat(index + 1) * itemHeight + scrollOffset
            
            // Skip if outside visible area
            if y + itemHeight < listRect.minY || y > listRect.maxY { continue }
            
            let itemRect = NSRect(x: listRect.minX, y: y, width: listRect.width, height: itemHeight)
            
            let track = tracks[index]
            let isCurrent = index == currentIndex
            let isSelected = selectedIndices.contains(index)
            
            // Text color -- current track uses accent (magenta), selected uses primary text
            let textColor: NSColor
            if isCurrent {
                textColor = skin.accentColor
            } else if isSelected {
                textColor = skin.textColor
            } else {
                textColor = skin.textDimColor
            }
            
            // Build track text
            let videoPrefix = track.mediaType == .video ? "[V] " : ""
            let titleText = "\(index + 1). \(videoPrefix)\(track.displayTitle)"
            let duration = track.duration ?? 0
            let durationStr = String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
            
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            
            // Draw duration right-aligned
            let durationAttr = NSAttributedString(string: durationStr, attributes: textAttrs)
            let durationSize = durationAttr.size()
            let durationX = itemRect.maxX - durationSize.width - 6
            let textY = itemRect.minY + (itemRect.height - durationSize.height) / 2
            durationAttr.draw(at: NSPoint(x: durationX, y: textY))
            
            // Draw title with clipping (and marquee for current track)
            let titleX = itemRect.minX + 4
            let titleMaxWidth = durationX - titleX - 8
            
            context.saveGState()
            context.clip(to: NSRect(x: titleX, y: itemRect.minY, width: titleMaxWidth, height: itemRect.height))
            
            let titleAttr = NSAttributedString(string: titleText, attributes: textAttrs)
            let titleSize = titleAttr.size()
            
            if isCurrent && titleSize.width > titleMaxWidth {
                // Marquee scrolling for current track
                let separatorWidth: CGFloat = 30
                let separator = NSAttributedString(string: "     ", attributes: textAttrs)
                
                // Draw two copies for seamless wrapping
                let drawX1 = titleX - marqueeOffset
                let drawX2 = drawX1 + titleSize.width + separatorWidth
                
                titleAttr.draw(at: NSPoint(x: drawX1, y: textY))
                separator.draw(at: NSPoint(x: drawX1 + titleSize.width, y: textY))
                titleAttr.draw(at: NSPoint(x: drawX2, y: textY))
            } else {
                titleAttr.draw(at: NSPoint(x: titleX, y: textY))
            }
            
            context.restoreGState()
        }
        
        context.restoreGState()
    }
    
    /// Draw info bar showing track count and remaining time
    private func drawInfoBar(in context: CGContext) {
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        guard !tracks.isEmpty else { return }
        
        let font = renderer.skin.smallLabelFont()
        let color = renderer.skin.textDimColor
        
        // Calculate remaining tracks and time
        let currentIndex = max(0, engine.currentIndex)
        let remainingTracks = max(0, tracks.count - currentIndex)
        
        var remainingSeconds = 0
        if engine.state == .playing || engine.currentTime > 0 {
            remainingSeconds += max(0, Int(engine.duration - engine.currentTime))
        } else if currentIndex < tracks.count {
            remainingSeconds += Int(tracks[currentIndex].duration ?? 0)
        }
        for i in (currentIndex + 1)..<tracks.count {
            remainingSeconds += Int(tracks[i].duration ?? 0)
        }
        
        let mins = remainingSeconds / 60
        let hrs = mins / 60
        let timeStr = hrs > 0
            ? String(format: "%d:%02d:%02d", hrs, mins % 60, remainingSeconds % 60)
            : String(format: "%d:%02d", mins, remainingSeconds % 60)
        
        let infoStr = "\(remainingTracks)/\(timeStr)"
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let attrStr = NSAttributedString(string: infoStr, attributes: attrs)
        let size = attrStr.size()
        
        // Position centered at bottom of window
        let y: CGFloat = 2
        let x = bounds.midX - size.width / 2
        attrStr.draw(at: NSPoint(x: x, y: y))
    }
    
    private func calculateListArea() -> NSRect {
        // Track list area between title bar and bottom border
        return NSRect(
            x: borderWidth,
            y: borderWidth,
            width: bounds.width - borderWidth * 2,
            height: bounds.height - titleBarHeight - borderWidth
        )
    }
    
    // MARK: - Artwork Background
    
    /// Draw the current artwork behind the track list at low opacity
    private func drawArtworkBackground(in listRect: NSRect, context: CGContext) {
        guard let artworkImage = currentArtwork,
              let cgImage = artworkImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        context.saveGState()
        context.clip(to: listRect)
        
        // Calculate centered fill rect (scale to fill, maintain aspect ratio)
        let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
        let artworkRect = calculateCenterFillRect(imageSize: imageSize, in: listRect)
        
        // Set low opacity for subtle background
        context.setAlpha(0.12)
        
        // Draw the image (macOS bottom-left origin, no flip needed)
        context.draw(cgImage, in: artworkRect)
        
        context.restoreGState()
    }
    
    /// Calculate a centered fit rect for artwork - scales to fit entirely within bounds, centered
    private func calculateCenterFillRect(imageSize: NSSize, in targetRect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return targetRect }
        
        let imageAspect = imageSize.width / imageSize.height
        let targetAspect = targetRect.width / targetRect.height
        
        var width: CGFloat
        var height: CGFloat
        
        if imageAspect > targetAspect {
            // Image is wider than target - fit to width
            width = targetRect.width
            height = width / imageAspect
        } else {
            // Image is taller than target - fit to height
            height = targetRect.height
            width = height * imageAspect
        }
        
        let x = targetRect.minX + (targetRect.width - width) / 2
        let y = targetRect.minY + (targetRect.height - height) / 2
        
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    /// Load artwork for a track (local embedded, Plex, or Subsonic)
    private func loadArtwork(for track: Track?) {
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        
        guard let track = track else {
            currentArtwork = nil
            artworkTrackId = nil
            needsDisplay = true
            return
        }
        
        // Skip if same track
        guard track.id != artworkTrackId else { return }
        
        artworkLoadTask = Task { [weak self] in
            guard let self = self else { return }
            
            var image: NSImage?
            
            if let plexRatingKey = track.plexRatingKey {
                // Plex track - load from server
                image = await self.loadPlexArtwork(ratingKey: plexRatingKey, thumbPath: track.artworkThumb)
            } else if let subsonicId = track.subsonicId {
                // Subsonic track - load cover art
                image = await self.loadSubsonicArtwork(songId: subsonicId)
            } else if track.url.isFileURL {
                // Local file - extract embedded artwork
                image = await self.loadLocalArtwork(url: track.url)
            }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.currentArtwork = image
                self.artworkTrackId = track.id
                self.needsDisplay = true
            }
        }
    }
    
    /// Load artwork from Plex server
    private func loadPlexArtwork(ratingKey: String, thumbPath: String?) async -> NSImage? {
        let cacheKey = NSString(string: "playlist_plex:\(ratingKey)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) {
            return cached
        }
        
        let path = thumbPath ?? "/library/metadata/\(ratingKey)/thumb"
        guard let url = PlexManager.shared.artworkURL(thumb: path, size: 400) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = NSImage(data: data) else { return nil }
            Self.artworkCache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }
    
    /// Load artwork from Subsonic server
    private func loadSubsonicArtwork(songId: String) async -> NSImage? {
        let cacheKey = NSString(string: "playlist_subsonic:\(songId)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Try using the song ID as cover art ID (most servers support this)
        guard let artworkURL = SubsonicManager.shared.coverArtURL(coverArtId: songId, size: 400) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: artworkURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = NSImage(data: data) else { return nil }
            Self.artworkCache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }
    
    /// Load embedded artwork from a local audio file
    private func loadLocalArtwork(url: URL) async -> NSImage? {
        let cacheKey = NSString(string: "playlist_local:\(url.path)")
        if let cached = Self.artworkCache.object(forKey: cacheKey) {
            return cached
        }
        
        let asset = AVURLAsset(url: url)
        
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        Self.artworkCache.setObject(image, forKey: cacheKey)
                        return image
                    }
                }
            }
            
            // Check ID3 metadata (MP3 files)
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
            
            // Check iTunes metadata (M4A/AAC files)
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
            NSLog("ModernPlaylistView: Failed to load local artwork: %@", error.localizedDescription)
        }
        
        return nil
    }
    
    // MARK: - Skin Change
    
    func skinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        updateCurrentTrackTextWidth()
        needsDisplay = true
    }
    
    // MARK: - Public Methods
    
    func reloadData() {
        selectedIndices.removeAll()
        selectionAnchor = nil
        scrollOffset = 0
        marqueeOffset = 0
        lastCurrentIndex = -1
        updateCurrentTrackTextWidth()
        needsDisplay = true
    }
    
    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        needsDisplay = true
    }
    
    // MARK: - Hit Testing
    
    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars {
            return point.y >= bounds.height - 6  // invisible drag zone
        }
        let closeWidth: CGFloat = 28 * ModernSkinElements.scaleFactor
        return point.y >= bounds.height - titleBarHeight &&
               point.x < bounds.width - closeWidth
    }
    
    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars { return false }
        let scale = ModernSkinElements.scaleFactor
        let closeRect = NSRect(x: bounds.width - 16 * scale, y: bounds.height - titleBarHeight + 2 * scale,
                               width: 14 * scale, height: 12 * scale)
        return closeRect.contains(point)
    }
    
    private func hitTestShadeButton(at point: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars { return false }
        let scale = ModernSkinElements.scaleFactor
        let shadeRect = NSRect(x: bounds.width - 28 * scale, y: bounds.height - titleBarHeight + 2 * scale,
                               width: 12 * scale, height: 12 * scale)
        return shadeRect.contains(point)
    }
    
    private func hitTestBottomBar(at point: NSPoint) -> String? {
        guard point.y < bottomBarHeight else { return nil }
        let scale = ModernSkinElements.scaleFactor
        
        // Match button layout from drawPlaylistBottomBar
        let buttons: [(String, CGFloat, CGFloat)] = [
            ("playlist_btn_add", 4 * scale, 30 * scale),
            ("playlist_btn_rem", 36 * scale, 30 * scale),
            ("playlist_btn_sel", 68 * scale, 30 * scale),
            ("playlist_btn_misc", bounds.width - 64 * scale, 30 * scale),
            ("playlist_btn_list", bounds.width - 32 * scale, 30 * scale),
        ]
        
        for (id, x, width) in buttons {
            let buttonRect = NSRect(x: x, y: 2 * scale, width: width, height: bottomBarHeight - 4 * scale)
            if buttonRect.contains(point) {
                return id
            }
        }
        
        return nil
    }
    
    private func hitTestTrackList(at point: NSPoint) -> Int? {
        let listRect = calculateListArea()
        guard listRect.contains(point) else { return nil }
        
        // Convert from macOS coords (bottom-up) to track index (top-down)
        let relativeY = listRect.maxY - point.y + scrollOffset
        let clickedIndex = Int(relativeY / itemHeight)
        
        let tracks = WindowManager.shared.audioEngine.playlist
        if clickedIndex >= 0 && clickedIndex < tracks.count {
            return clickedIndex
        }
        
        return nil
    }
    
    // MARK: - Mouse Events
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Double-click title bar → shade mode
        if event.clickCount == 2 && hitTestTitleBar(at: point) {
            toggleShadeMode()
            return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: point, event: event)
            return
        }
        
        // Close button
        if hitTestCloseButton(at: point) {
            pressedButton = "playlist_btn_close"
            needsDisplay = true
            return
        }
        
        // Shade button
        if hitTestShadeButton(at: point) {
            pressedButton = "playlist_btn_shade"
            needsDisplay = true
            return
        }
        
        // Track list
        if let trackIndex = hitTestTrackList(at: point) {
            handleTrackClick(index: trackIndex, event: event)
            return
        }
        
        // Title bar → window drag
        if hitTestTitleBar(at: point) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
        }
    }
    
    private func handleShadeMouseDown(at point: NSPoint, event: NSEvent) {
        if hitTestCloseButton(at: point) {
            pressedButton = "playlist_btn_close"
            needsDisplay = true
            return
        }
        if hitTestShadeButton(at: point) {
            pressedButton = "playlist_btn_shade"
            needsDisplay = true
            return
        }
        
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
        }
    }
    
    private func handleTrackClick(index: Int, event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            let anchor = selectionAnchor ?? selectedIndices.min() ?? index
            let start = min(anchor, index)
            let end = max(anchor, index)
            selectedIndices = Set(start...end)
        } else if event.modifierFlags.contains(.command) {
            if selectedIndices.contains(index) {
                selectedIndices.remove(index)
            } else {
                selectedIndices.insert(index)
            }
            selectionAnchor = index
        } else {
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
        
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
        
        if isShadeMode {
            handleShadeMouseUp(at: point)
            return
        }
        
        if let pressed = pressedButton {
            switch pressed {
            case "playlist_btn_close":
                if hitTestCloseButton(at: point) { window?.close() }
            case "playlist_btn_shade":
                if hitTestShadeButton(at: point) { toggleShadeMode() }
            default:
                break
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    private func handleShadeMouseUp(at point: NSPoint) {
        if let pressed = pressedButton {
            switch pressed {
            case "playlist_btn_close":
                if hitTestCloseButton(at: point) { window?.close() }
            case "playlist_btn_shade":
                if hitTestShadeButton(at: point) { toggleShadeMode() }
            default:
                break
            }
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    private func toggleShadeMode() {
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    override func scrollWheel(with event: NSEvent) {
        let tracks = WindowManager.shared.audioEngine.playlist
        let listRect = calculateListArea()
        let totalHeight = CGFloat(tracks.count) * itemHeight
        
        if totalHeight > listRect.height {
            scrollOffset = max(0, min(totalHeight - listRect.height, scrollOffset - event.deltaY * 3))
            needsDisplay = true
        }
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        let hasShift = event.modifierFlags.contains(.shift)
        
        switch event.keyCode {
        case 51: // Delete
            removeSelected(nil)
        case 36: // Enter
            if let index = selectedIndices.first {
                engine.playTrack(at: index)
            }
        case 0: // A + Cmd
            if event.modifierFlags.contains(.command) {
                selectAll(nil)
            }
        case 126: // Up arrow
            guard !tracks.isEmpty else { return }
            navigateSelection(direction: -1, extend: hasShift)
        case 125: // Down arrow
            guard !tracks.isEmpty else { return }
            navigateSelection(direction: 1, extend: hasShift)
        case 115: // Home
            guard !tracks.isEmpty else { return }
            if hasShift { extendSelectionTo(0) }
            else { selectedIndices = [0]; selectionAnchor = 0 }
            scrollToSelection(); needsDisplay = true
        case 119: // End
            guard !tracks.isEmpty else { return }
            let last = tracks.count - 1
            if hasShift { extendSelectionTo(last) }
            else { selectedIndices = [last]; selectionAnchor = last }
            scrollToSelection(); needsDisplay = true
        case 116: // Page Up
            guard !tracks.isEmpty else { return }
            navigateSelection(direction: -visibleTrackCount, extend: hasShift)
        case 121: // Page Down
            guard !tracks.isEmpty else { return }
            navigateSelection(direction: visibleTrackCount, extend: hasShift)
        default:
            super.keyDown(with: event)
        }
    }
    
    private var visibleTrackCount: Int {
        let listRect = calculateListArea()
        return max(1, Int(listRect.height / itemHeight))
    }
    
    private func navigateSelection(direction: Int, extend: Bool) {
        let tracks = WindowManager.shared.audioEngine.playlist
        guard !tracks.isEmpty else { return }
        
        let currentFocus: Int
        if let anchor = selectionAnchor, selectedIndices.contains(anchor) {
            currentFocus = anchor
        } else if direction < 0 {
            currentFocus = selectedIndices.min() ?? 0
        } else {
            currentFocus = selectedIndices.max() ?? 0
        }
        
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
    
    private func extendSelectionTo(_ targetIndex: Int) {
        let anchor = selectionAnchor ?? selectedIndices.min() ?? 0
        let start = min(anchor, targetIndex)
        let end = max(anchor, targetIndex)
        selectedIndices = Set(start...end)
    }
    
    private func scrollToSelection() {
        guard let focusIndex = selectionAnchor ?? selectedIndices.min() else { return }
        
        let listRect = calculateListArea()
        let tracks = WindowManager.shared.audioEngine.playlist
        
        let itemTop = CGFloat(focusIndex) * itemHeight
        let itemBottom = itemTop + itemHeight
        let visibleTop = scrollOffset
        let visibleBottom = scrollOffset + listRect.height
        
        if itemTop < visibleTop {
            scrollOffset = itemTop
        } else if itemBottom > visibleBottom {
            scrollOffset = itemBottom - listRect.height
        }
        
        let totalContentHeight = CGFloat(tracks.count) * itemHeight
        let maxScroll = max(0, totalContentHeight - listRect.height)
        scrollOffset = max(0, min(maxScroll, scrollOffset))
    }
    
    // MARK: - Button Popup Menus
    
    private func showAddMenu(at point: NSPoint) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Add URL...", action: #selector(addURL(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Add Directory...", action: #selector(addDirectory(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Add Files...", action: #selector(addFiles(_:)), keyEquivalent: "")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    private func showRemoveMenu(at point: NSPoint) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Remove All", action: #selector(removeAll(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Crop Selection", action: #selector(cropSelection(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Remove Selected", action: #selector(removeSelected(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Remove Dead Files", action: #selector(removeDeadFiles(_:)), keyEquivalent: "")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    private func showSelectMenu(at point: NSPoint) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Invert Selection", action: #selector(invertSelection(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select None", action: #selector(selectNone(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    private func showMiscMenu(at point: NSPoint) {
        let menu = NSMenu()
        
        let sortMenu = NSMenu()
        sortMenu.addItem(withTitle: "Sort by Title", action: #selector(sortByTitle(_:)), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Sort by Filename", action: #selector(sortByFilename(_:)), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Sort by Path", action: #selector(sortByPath(_:)), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Randomize", action: #selector(randomize(_:)), keyEquivalent: "")
        sortMenu.addItem(withTitle: "Reverse", action: #selector(reverse(_:)), keyEquivalent: "")
        for item in sortMenu.items { item.target = self }
        
        let sortItem = NSMenuItem(title: "Sort", action: nil, keyEquivalent: "")
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)
        
        menu.addItem(withTitle: "File Info...", action: #selector(showFileInfo(_:)), keyEquivalent: "")
        for item in menu.items { if item.action != nil { item.target = self } }
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    private func showListMenu(at point: NSPoint) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Playlist", action: #selector(newPlaylist(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Save Playlist...", action: #selector(savePlaylist(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Load Playlist...", action: #selector(loadPlaylist(_:)), keyEquivalent: "")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    // MARK: - Menu Actions
    
    @objc private func addURL(_ sender: Any?) {
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
            let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
            var audioURLs: [URL] = []
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
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
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        let indicesToRemove = Set(0..<tracks.count).subtracting(selectedIndices)
        for index in indicesToRemove.sorted(by: >) {
            engine.removeTrack(at: index)
        }
        selectedIndices = Set(0..<engine.playlist.count)
        selectionAnchor = 0
        needsDisplay = true
    }
    
    @objc private func removeSelected(_ sender: Any?) {
        let engine = WindowManager.shared.audioEngine
        for index in selectedIndices.sorted(by: >) {
            engine.removeTrack(at: index)
        }
        selectedIndices.removeAll()
        selectionAnchor = nil
        needsDisplay = true
    }
    
    @objc private func removeDeadFiles(_ sender: Any?) {
        let engine = WindowManager.shared.audioEngine
        var indicesToRemove: [Int] = []
        for (index, track) in engine.playlist.enumerated() {
            if !track.url.isFileURL || !FileManager.default.fileExists(atPath: track.url.path) {
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
        selectedIndices = Set(0..<tracks.count).subtracting(selectedIndices)
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
    
    @objc private func sortByArtist(_ sender: Any?) {
        WindowManager.shared.audioEngine.sortPlaylist(by: .artist)
        needsDisplay = true
    }
    
    @objc private func sortByAlbum(_ sender: Any?) {
        WindowManager.shared.audioEngine.sortPlaylist(by: .album)
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
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                                mediaURLs.append(fileURL)
                            }
                        }
                    }
                } else {
                    if audioExtensions.contains(url.pathExtension.lowercased()) {
                        mediaURLs.append(url)
                    }
                }
            }
        }
        
        mediaURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        if !mediaURLs.isEmpty {
            let audioEngine = WindowManager.shared.audioEngine
            let firstNewIndex = audioEngine.playlist.count
            audioEngine.appendFiles(mediaURLs)
            audioEngine.playTrack(at: firstNewIndex)
            needsDisplay = true
            return true
        }
        
        return false
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let engine = WindowManager.shared.audioEngine
        let tracks = engine.playlist
        let hasSelection = !selectedIndices.isEmpty
        let hasTracks = !tracks.isEmpty
        
        // Play selected
        let playItem = NSMenuItem(title: "Play", action: #selector(playSelected(_:)), keyEquivalent: "")
        playItem.target = self
        playItem.isEnabled = hasSelection
        menu.addItem(playItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Remove selected
        let removeItem = NSMenuItem(title: "Remove Selected", action: #selector(removeSelected(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.isEnabled = hasSelection
        menu.addItem(removeItem)
        
        // Clear playlist
        let clearItem = NSMenuItem(title: "Clear Playlist", action: #selector(removeAll(_:)), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = hasTracks
        menu.addItem(clearItem)
        
        // Remove dead files
        let deadItem = NSMenuItem(title: "Remove Dead Files", action: #selector(removeDeadFiles(_:)), keyEquivalent: "")
        deadItem.target = self
        deadItem.isEnabled = hasTracks
        menu.addItem(deadItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Selection submenu
        let selectionMenu = NSMenu()
        
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        selectAllItem.target = self
        selectAllItem.isEnabled = hasTracks
        selectionMenu.addItem(selectAllItem)
        
        let selectNoneItem = NSMenuItem(title: "Select None", action: #selector(selectNone(_:)), keyEquivalent: "")
        selectNoneItem.target = self
        selectNoneItem.isEnabled = hasSelection
        selectionMenu.addItem(selectNoneItem)
        
        let invertItem = NSMenuItem(title: "Invert Selection", action: #selector(invertSelection(_:)), keyEquivalent: "")
        invertItem.target = self
        invertItem.isEnabled = hasTracks
        selectionMenu.addItem(invertItem)
        
        let cropItem = NSMenuItem(title: "Crop Selection", action: #selector(cropSelection(_:)), keyEquivalent: "")
        cropItem.target = self
        cropItem.isEnabled = hasSelection
        selectionMenu.addItem(cropItem)
        
        let selectionMenuItem = NSMenuItem(title: "Selection", action: nil, keyEquivalent: "")
        selectionMenuItem.submenu = selectionMenu
        menu.addItem(selectionMenuItem)
        
        // Sort submenu
        let sortMenu = NSMenu()
        
        let sortTitleItem = NSMenuItem(title: "Sort by Title", action: #selector(sortByTitle(_:)), keyEquivalent: "")
        sortTitleItem.target = self
        sortTitleItem.isEnabled = hasTracks
        sortMenu.addItem(sortTitleItem)
        
        let sortArtistItem = NSMenuItem(title: "Sort by Artist", action: #selector(sortByArtist(_:)), keyEquivalent: "")
        sortArtistItem.target = self
        sortArtistItem.isEnabled = hasTracks
        sortMenu.addItem(sortArtistItem)
        
        let sortAlbumItem = NSMenuItem(title: "Sort by Album", action: #selector(sortByAlbum(_:)), keyEquivalent: "")
        sortAlbumItem.target = self
        sortAlbumItem.isEnabled = hasTracks
        sortMenu.addItem(sortAlbumItem)
        
        let sortFilenameItem = NSMenuItem(title: "Sort by Filename", action: #selector(sortByFilename(_:)), keyEquivalent: "")
        sortFilenameItem.target = self
        sortFilenameItem.isEnabled = hasTracks
        sortMenu.addItem(sortFilenameItem)
        
        let sortPathItem = NSMenuItem(title: "Sort by Path", action: #selector(sortByPath(_:)), keyEquivalent: "")
        sortPathItem.target = self
        sortPathItem.isEnabled = hasTracks
        sortMenu.addItem(sortPathItem)
        
        sortMenu.addItem(NSMenuItem.separator())
        
        let reverseItem = NSMenuItem(title: "Reverse", action: #selector(reverse(_:)), keyEquivalent: "")
        reverseItem.target = self
        reverseItem.isEnabled = hasTracks
        sortMenu.addItem(reverseItem)
        
        let randomizeItem = NSMenuItem(title: "Randomize", action: #selector(randomize(_:)), keyEquivalent: "")
        randomizeItem.target = self
        randomizeItem.isEnabled = hasTracks
        sortMenu.addItem(randomizeItem)
        
        let sortMenuItem = NSMenuItem(title: "Sort", action: nil, keyEquivalent: "")
        sortMenuItem.submenu = sortMenu
        menu.addItem(sortMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // File info
        let infoItem = NSMenuItem(title: "File Info...", action: #selector(showFileInfo(_:)), keyEquivalent: "")
        infoItem.target = self
        infoItem.isEnabled = selectedIndices.count == 1
        menu.addItem(infoItem)
        
        return menu
    }
    
    @objc private func playSelected(_ sender: Any?) {
        guard let index = selectedIndices.first else { return }
        WindowManager.shared.audioEngine.playTrack(at: index)
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
    }
}
