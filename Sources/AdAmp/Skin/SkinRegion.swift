import AppKit

// MARK: - Player Actions

/// All possible actions from UI interactions
enum PlayerAction: Equatable {
    // Transport controls
    case previous
    case play
    case pause
    case stop
    case next
    case eject
    
    // Window controls
    case close
    case minimize
    case shade
    
    // Toggle controls
    case shuffle
    case `repeat`
    case toggleEQ
    case togglePlaylist
    
    // Sliders
    case seekPosition(CGFloat)  // 0.0 - 1.0
    case setVolume(CGFloat)     // 0.0 - 1.0
    case setBalance(CGFloat)    // -1.0 to 1.0
    
    // EQ controls
    case toggleEQOn
    case toggleEQAuto
    case openEQPresets
    case setEQBand(Int, CGFloat)  // band index (0-9), gain (-12 to +12)
    case setEQPreamp(CGFloat)     // gain (-12 to +12)
    
    // Playlist actions
    case playlistAdd
    case playlistAddDir
    case playlistAddFile
    case playlistRemove
    case playlistRemoveAll
    case playlistRemoveCrop
    case playlistSelectAll
    case playlistSelectNone
    case playlistSelectInvert
    case playlistSortByTitle
    case playlistSortByPath
    case playlistReverse
    case playlistRandomize
    
    // Generic slider interaction
    case sliderDrag(SliderType, CGFloat)
    
    // Menu actions
    case openMainMenu
    case openOptionsMenu
    
    // Plex
    case openPlexBrowser
    
    // Spectrum
    case toggleSpectrum
}

// MARK: - Clickable Region

/// Defines a clickable area with associated action
struct ClickableRegion {
    let rect: NSRect
    let action: PlayerAction
    let cursorType: CursorType
    
    init(rect: NSRect, action: PlayerAction, cursor: CursorType = .normal) {
        self.rect = rect
        self.action = action
        self.cursorType = cursor
    }
}

/// Cursor types for different regions
enum CursorType {
    case normal
    case pointer    // Hand cursor for buttons
    case hResize    // Horizontal resize for sliders
    case vResize    // Vertical resize for EQ sliders
    case move       // Move cursor for window dragging
}

// MARK: - Region Manager

/// Manages clickable regions for all windows
class RegionManager {
    
    // MARK: - Singleton
    
    static let shared = RegionManager()
    
    private init() {}
    
    // MARK: - Main Window Regions
    
    /// All clickable regions for the main window (275x116)
    /// Note: Y coordinates are in Winamp's coordinate system (top-down)
    /// Convert to macOS coordinates (bottom-up) when using
    lazy var mainWindowRegions: [ClickableRegion] = {
        var regions: [ClickableRegion] = []
        
        // Window control buttons (top right)
        regions.append(ClickableRegion(
            rect: NSRect(x: 244, y: 3, width: 9, height: 9),
            action: .minimize,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 254, y: 3, width: 9, height: 9),
            action: .shade,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 264, y: 3, width: 9, height: 9),
            action: .close,
            cursor: .pointer
        ))
        
        // Menu button (top left)
        regions.append(ClickableRegion(
            rect: NSRect(x: 6, y: 3, width: 9, height: 9),
            action: .openMainMenu,
            cursor: .pointer
        ))
        
        // Transport buttons
        regions.append(ClickableRegion(
            rect: NSRect(x: 16, y: 88, width: 23, height: 18),
            action: .previous,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 39, y: 88, width: 23, height: 18),
            action: .play,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 62, y: 88, width: 23, height: 18),
            action: .pause,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 85, y: 88, width: 23, height: 18),
            action: .stop,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 108, y: 88, width: 22, height: 18),
            action: .next,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 136, y: 89, width: 22, height: 16),
            action: .eject,
            cursor: .pointer
        ))
        
        // Shuffle/Repeat buttons
        regions.append(ClickableRegion(
            rect: NSRect(x: 164, y: 89, width: 47, height: 15),
            action: .shuffle,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 211, y: 89, width: 28, height: 15),
            action: .repeat,
            cursor: .pointer
        ))
        
        // EQ/Playlist toggle buttons
        regions.append(ClickableRegion(
            rect: NSRect(x: 219, y: 58, width: 23, height: 12),
            action: .toggleEQ,
            cursor: .pointer
        ))
        regions.append(ClickableRegion(
            rect: NSRect(x: 242, y: 58, width: 23, height: 12),
            action: .togglePlaylist,
            cursor: .pointer
        ))
        
        // Note: Spectrum analyzer area uses double-click to open (handled in MainWindowView)
        
        // Position slider (seek bar)
        regions.append(ClickableRegion(
            rect: NSRect(x: 16, y: 72, width: 248, height: 10),
            action: .seekPosition(0),  // Actual value calculated during interaction
            cursor: .hResize
        ))
        
        // Volume slider
        regions.append(ClickableRegion(
            rect: NSRect(x: 107, y: 57, width: 68, height: 13),
            action: .setVolume(0),
            cursor: .hResize
        ))
        
        // Balance slider
        regions.append(ClickableRegion(
            rect: NSRect(x: 177, y: 57, width: 38, height: 13),
            action: .setBalance(0),
            cursor: .hResize
        ))
        
        // Winamp logo (bottom-right corner) - opens Plex browser
        regions.append(ClickableRegion(
            rect: NSRect(x: 248, y: 91, width: 20, height: 20),
            action: .openPlexBrowser,
            cursor: .pointer
        ))
        
        return regions
    }()
    
    // MARK: - Equalizer Window Regions
    
    /// All clickable regions for the equalizer window (275x116)
    lazy var equalizerRegions: [ClickableRegion] = {
        var regions: [ClickableRegion] = []
        
        // Window control buttons
        regions.append(ClickableRegion(
            rect: NSRect(x: 264, y: 3, width: 9, height: 9),
            action: .close,
            cursor: .pointer
        ))
        
        // ON button
        regions.append(ClickableRegion(
            rect: NSRect(x: 14, y: 18, width: 26, height: 12),
            action: .toggleEQOn,
            cursor: .pointer
        ))
        
        // AUTO button
        regions.append(ClickableRegion(
            rect: NSRect(x: 40, y: 18, width: 32, height: 12),
            action: .toggleEQAuto,
            cursor: .pointer
        ))
        
        // Presets button
        regions.append(ClickableRegion(
            rect: NSRect(x: 217, y: 18, width: 44, height: 12),
            action: .openEQPresets,
            cursor: .pointer
        ))
        
        // Preamp slider
        let preampX: CGFloat = 21
        regions.append(ClickableRegion(
            rect: NSRect(x: preampX, y: 38, width: 14, height: 63),
            action: .setEQPreamp(0),
            cursor: .vResize
        ))
        
        // 10 EQ band sliders
        let firstBandX: CGFloat = 78
        let bandSpacing: CGFloat = 18
        for i in 0..<10 {
            let x = firstBandX + CGFloat(i) * bandSpacing
            regions.append(ClickableRegion(
                rect: NSRect(x: x, y: 38, width: 14, height: 63),
                action: .setEQBand(i, 0),
                cursor: .vResize
            ))
        }
        
        return regions
    }()
    
    // MARK: - Playlist Window Regions
    
    /// Clickable regions for playlist window (dynamically sized)
    func playlistRegions(for bounds: NSRect) -> [ClickableRegion] {
        var regions: [ClickableRegion] = []
        
        // Close button (top right)
        regions.append(ClickableRegion(
            rect: NSRect(x: bounds.width - 11, y: 3, width: 9, height: 9),
            action: .close,
            cursor: .pointer
        ))
        
        // Bottom button bar (25 pixels from bottom)
        let buttonY: CGFloat = 4
        let buttonHeight: CGFloat = 18
        
        // Add buttons
        regions.append(ClickableRegion(
            rect: NSRect(x: 14, y: buttonY, width: 22, height: buttonHeight),
            action: .playlistAddFile,
            cursor: .pointer
        ))
        
        // Remove buttons
        regions.append(ClickableRegion(
            rect: NSRect(x: 54, y: buttonY, width: 22, height: buttonHeight),
            action: .playlistRemove,
            cursor: .pointer
        ))
        
        // Select buttons
        regions.append(ClickableRegion(
            rect: NSRect(x: 104, y: buttonY, width: 22, height: buttonHeight),
            action: .playlistSelectAll,
            cursor: .pointer
        ))
        
        return regions
    }
    
    // MARK: - Hit Testing
    
    /// Perform hit test on main window
    /// - Parameters:
    ///   - point: Point in window coordinates (macOS bottom-up)
    ///   - windowHeight: Height of the window for coordinate conversion
    /// - Returns: The action if a region was hit, nil otherwise
    func hitTest(point: NSPoint, in windowType: WindowType, windowSize: NSSize) -> PlayerAction? {
        let regions: [ClickableRegion]
        
        switch windowType {
        case .main:
            regions = mainWindowRegions
        case .equalizer:
            regions = equalizerRegions
        case .playlist:
            regions = playlistRegions(for: NSRect(origin: .zero, size: windowSize))
        case .mediaLibrary:
            return nil
        }
        
        // Convert macOS coordinates (origin bottom-left) to Winamp coordinates (origin top-left)
        let winampPoint = NSPoint(x: point.x, y: windowSize.height - point.y)
        
        for region in regions {
            if region.rect.contains(winampPoint) {
                // For sliders, calculate the actual value based on position
                return adjustedAction(for: region, at: winampPoint)
            }
        }
        
        return nil
    }
    
    /// Get the appropriate cursor for a point
    func cursor(for point: NSPoint, in windowType: WindowType, windowSize: NSSize) -> NSCursor {
        let regions: [ClickableRegion]
        
        switch windowType {
        case .main:
            regions = mainWindowRegions
        case .equalizer:
            regions = equalizerRegions
        case .playlist:
            regions = playlistRegions(for: NSRect(origin: .zero, size: windowSize))
        case .mediaLibrary:
            return .arrow
        }
        
        let winampPoint = NSPoint(x: point.x, y: windowSize.height - point.y)
        
        for region in regions {
            if region.rect.contains(winampPoint) {
                switch region.cursorType {
                case .normal:
                    return .arrow
                case .pointer:
                    return .pointingHand
                case .hResize:
                    return .resizeLeftRight
                case .vResize:
                    return .resizeUpDown
                case .move:
                    return .openHand
                }
            }
        }
        
        // Check if in title bar area (for window dragging)
        let titleBarRect = NSRect(x: 0, y: windowSize.height - SkinElements.titleBarHeight,
                                  width: windowSize.width - 30, height: SkinElements.titleBarHeight)
        if titleBarRect.contains(point) {
            return .openHand
        }
        
        return .arrow
    }
    
    /// Adjust action based on slider position
    private func adjustedAction(for region: ClickableRegion, at point: NSPoint) -> PlayerAction {
        switch region.action {
        case .seekPosition:
            let value = (point.x - region.rect.minX) / region.rect.width
            return .seekPosition(min(1.0, max(0.0, value)))
            
        case .setVolume:
            let value = (point.x - region.rect.minX) / region.rect.width
            return .setVolume(min(1.0, max(0.0, value)))
            
        case .setBalance:
            let normalized = (point.x - region.rect.minX) / region.rect.width
            let value = (normalized * 2.0) - 1.0  // Convert to -1...1
            return .setBalance(min(1.0, max(-1.0, value)))
            
        case .setEQBand(let band, _):
            // EQ sliders are vertical, value increases upward
            let normalized = 1.0 - (point.y - region.rect.minY) / region.rect.height
            let gain = (normalized * 24.0) - 12.0  // Convert to -12...+12
            return .setEQBand(band, min(12.0, max(-12.0, gain)))
            
        case .setEQPreamp:
            let normalized = 1.0 - (point.y - region.rect.minY) / region.rect.height
            let gain = (normalized * 24.0) - 12.0
            return .setEQPreamp(min(12.0, max(-12.0, gain)))
            
        default:
            return region.action
        }
    }
    
    // MARK: - Region Lookup by Action
    
    /// Get the hit rect for a specific action in the main window
    func hitRect(for action: PlayerAction) -> NSRect? {
        for region in mainWindowRegions {
            if actionsMatch(region.action, action) {
                return region.rect
            }
        }
        return nil
    }
    
    /// Check if two actions are the same type (ignoring associated values)
    private func actionsMatch(_ a: PlayerAction, _ b: PlayerAction) -> Bool {
        switch (a, b) {
        case (.previous, .previous),
             (.play, .play),
             (.pause, .pause),
             (.stop, .stop),
             (.next, .next),
             (.eject, .eject),
             (.close, .close),
             (.minimize, .minimize),
             (.shade, .shade),
             (.shuffle, .shuffle),
             (.repeat, .repeat),
             (.toggleEQ, .toggleEQ),
             (.togglePlaylist, .togglePlaylist):
            return true
        case (.seekPosition, .seekPosition),
             (.setVolume, .setVolume),
             (.setBalance, .setBalance):
            return true
        case (.setEQBand(let a, _), .setEQBand(let b, _)):
            return a == b
        default:
            return false
        }
    }
    
    // MARK: - Title Bar Detection
    
    /// Check if a point is in the draggable title bar area
    func isInTitleBar(_ point: NSPoint, windowType: WindowType, windowSize: NSSize) -> Bool {
        // Convert to Winamp coordinates
        let winampY = windowSize.height - point.y
        
        // Title bar is at the top, 14 pixels high, excluding buttons on the right
        return winampY < SkinElements.titleBarHeight && point.x < windowSize.width - 30
    }
    
    /// Check if double-click should toggle shade mode
    func shouldToggleShade(at point: NSPoint, windowType: WindowType, windowSize: NSSize) -> Bool {
        return isInTitleBar(point, windowType: windowType, windowSize: windowSize)
    }
}

// MARK: - Custom Window Region Support

extension RegionManager {
    
    /// Apply custom region from skin's region.txt
    func applyCustomRegion(_ points: [NSPoint]?, to window: NSWindow) {
        guard let points = points, !points.isEmpty else { return }
        
        // Create a path from the points
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.close()
        
        // Note: NSWindow doesn't directly support non-rectangular shapes
        // This would need to be implemented using a transparent window with
        // custom hit testing, or by setting the window's shape mask
    }
}

// MARK: - Drag Region Tracker

/// Tracks slider dragging state
class SliderDragTracker {
    
    var isDragging = false
    var sliderType: SliderType?
    var startValue: CGFloat = 0
    var startPoint: NSPoint = .zero
    
    func beginDrag(slider: SliderType, at point: NSPoint, currentValue: CGFloat) {
        isDragging = true
        sliderType = slider
        startValue = currentValue
        startPoint = point
    }
    
    func updateDrag(to point: NSPoint, in rect: NSRect) -> CGFloat {
        guard isDragging, let slider = sliderType else { return startValue }
        
        switch slider {
        case .position, .volume:
            // Horizontal slider
            let delta = point.x - startPoint.x
            let range = rect.width
            let valueDelta = delta / range
            return min(1.0, max(0.0, startValue + valueDelta))
            
        case .balance:
            // Horizontal slider, -1 to 1
            let delta = point.x - startPoint.x
            let range = rect.width
            let valueDelta = (delta / range) * 2.0
            return min(1.0, max(-1.0, startValue + valueDelta))
            
        case .eqBand, .eqPreamp:
            // Vertical slider, inverted (up = higher value)
            let delta = startPoint.y - point.y
            let range = rect.height
            let valueDelta = (delta / range) * 24.0
            return min(12.0, max(-12.0, startValue + valueDelta))
        }
    }
    
    func endDrag() {
        isDragging = false
        sliderType = nil
    }
}
