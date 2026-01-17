import AppKit

// MARK: - Notifications

extension Notification.Name {
    static let timeDisplayModeDidChange = Notification.Name("timeDisplayModeDidChange")
    static let doubleSizeDidChange = Notification.Name("doubleSizeDidChange")
}

// MARK: - Time Display Mode

enum TimeDisplayMode: String {
    case elapsed
    case remaining
}

/// Manages all application windows and their interactions
/// Handles window docking, snapping, and coordinated movement
class WindowManager {
    
    // MARK: - Singleton
    
    static let shared = WindowManager()
    
    // MARK: - Properties
    
    /// The audio engine instance
    let audioEngine = AudioEngine()
    
    /// The currently loaded skin
    private(set) var currentSkin: Skin?
    
    // MARK: - User Preferences
    
    /// Time display mode (elapsed vs remaining)
    var timeDisplayMode: TimeDisplayMode = .elapsed {
        didSet {
            UserDefaults.standard.set(timeDisplayMode.rawValue, forKey: "timeDisplayMode")
            NotificationCenter.default.post(name: .timeDisplayModeDidChange, object: nil)
        }
    }
    
    /// Double size mode (2x scaling)
    var isDoubleSize: Bool = false {
        didSet {
            UserDefaults.standard.set(isDoubleSize, forKey: "isDoubleSize")
            applyDoubleSize()
            NotificationCenter.default.post(name: .doubleSizeDidChange, object: nil)
        }
    }
    
    /// Main player window controller
    private(set) var mainWindowController: MainWindowController?
    
    /// Playlist window controller
    private(set) var playlistWindowController: PlaylistWindowController?
    
    /// Equalizer window controller
    private(set) var equalizerWindowController: EQWindowController?
    
    /// Media library window controller
    private var mediaLibraryWindowController: MediaLibraryWindowController?
    
    /// Snap threshold in pixels
    private let snapThreshold: CGFloat = 10
    
    /// Docking threshold - windows closer than this are considered docked
    /// Should be >= snapThreshold to ensure snapped windows are detected as docked
    private let dockThreshold: CGFloat = 12
    
    /// Track which window is currently being dragged
    private var draggingWindow: NSWindow?
    
    /// Track the last drag delta for grouped movement
    private var lastDragDelta: NSPoint = .zero
    
    /// Windows that should move together with the dragging window
    private var dockedWindowsToMove: [NSWindow] = []
    
    /// Flag to prevent feedback loop when moving docked windows programmatically
    private var isMovingDockedWindows = false
    
    // MARK: - Initialization
    
    private init() {
        // Register and load preferences
        registerPreferenceDefaults()
        loadPreferences()
        
        // Load default skin
        loadDefaultSkin()
    }
    
    /// Register default preference values
    private func registerPreferenceDefaults() {
        UserDefaults.standard.register(defaults: [
            "timeDisplayMode": TimeDisplayMode.elapsed.rawValue,
            "isDoubleSize": false
        ])
    }
    
    /// Load preferences from UserDefaults
    private func loadPreferences() {
        if let mode = UserDefaults.standard.string(forKey: "timeDisplayMode"),
           let displayMode = TimeDisplayMode(rawValue: mode) {
            timeDisplayMode = displayMode
        }
        isDoubleSize = UserDefaults.standard.bool(forKey: "isDoubleSize")
    }
    
    // MARK: - Window Management
    
    func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        mainWindowController?.showWindow(nil)
    }
    
    func toggleMainWindow() {
        if let controller = mainWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showMainWindow()
        }
    }
    
    func showPlaylist() {
        if playlistWindowController == nil {
            playlistWindowController = PlaylistWindowController()
        }
        playlistWindowController?.showWindow(nil)
        notifyMainWindowVisibilityChanged()
    }

    var isPlaylistVisible: Bool {
        playlistWindowController?.window?.isVisible == true
    }
    
    func togglePlaylist() {
        if let controller = playlistWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showPlaylist()
        }
        notifyMainWindowVisibilityChanged()
    }
    
    func showEqualizer() {
        if equalizerWindowController == nil {
            equalizerWindowController = EQWindowController()
        }
        equalizerWindowController?.showWindow(nil)
        notifyMainWindowVisibilityChanged()
    }

    var isEqualizerVisible: Bool {
        equalizerWindowController?.window?.isVisible == true
    }
    
    func toggleEqualizer() {
        if let controller = equalizerWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showEqualizer()
        }
        notifyMainWindowVisibilityChanged()
    }
    
    func showMediaLibrary() {
        if mediaLibraryWindowController == nil {
            mediaLibraryWindowController = MediaLibraryWindowController()
        }
        mediaLibraryWindowController?.showWindow(nil)
    }
    
    var isMediaLibraryVisible: Bool {
        mediaLibraryWindowController?.window?.isVisible == true
    }
    
    func toggleMediaLibrary() {
        if let controller = mediaLibraryWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showMediaLibrary()
        }
    }

    func notifyMainWindowVisibilityChanged() {
        mainWindowController?.windowVisibilityDidChange()
    }
    
    // MARK: - Skin Management
    
    func loadSkin(from url: URL) {
        do {
            let skin = try SkinLoader.shared.load(from: url)
            currentSkin = skin
            notifySkinChanged()
        } catch {
            print("Failed to load skin: \(error)")
        }
    }
    
    private func loadDefaultSkin() {
        currentSkin = SkinLoader.shared.loadDefault()
    }
    
    /// Load the base/default skin
    func loadBaseSkin() {
        currentSkin = SkinLoader.shared.loadDefault()
        notifySkinChanged()
    }
    
    private func notifySkinChanged() {
        // Notify all windows to redraw with new skin
        mainWindowController?.skinDidChange()
        playlistWindowController?.skinDidChange()
        equalizerWindowController?.skinDidChange()
        mediaLibraryWindowController?.skinDidChange()
    }
    
    // MARK: - Skin Discovery
    
    /// Application Support directory for AdAmp
    var applicationSupportURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("AdAmp")
    }
    
    /// Skins directory
    var skinsDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("Skins")
    }
    
    /// Get list of available skins (name, URL)
    func availableSkins() -> [(name: String, url: URL)] {
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: skinsDirectoryURL, withIntermediateDirectories: true)
        
        guard let contents = try? FileManager.default.contentsOfDirectory(at: skinsDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return contents
            .filter { $0.pathExtension.lowercased() == "wsz" }
            .map { (name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Double Size
    
    /// Apply double size scaling to all windows
    private func applyDoubleSize() {
        let scale: CGFloat = isDoubleSize ? 2.0 : 1.0
        
        // Main window
        if let window = mainWindowController?.window {
            let targetSize = NSSize(width: Skin.mainWindowSize.width * scale,
                                    height: Skin.mainWindowSize.height * scale)
            var frame = window.frame
            let heightDiff = targetSize.height - frame.height
            frame.origin.y -= heightDiff  // Anchor top-left
            frame.size = targetSize
            window.setFrame(frame, display: true, animate: true)
        }
        
        // EQ window
        if let window = equalizerWindowController?.window {
            let targetSize = NSSize(width: Skin.eqWindowSize.width * scale,
                                    height: Skin.eqWindowSize.height * scale)
            var frame = window.frame
            let heightDiff = targetSize.height - frame.height
            frame.origin.y -= heightDiff
            frame.size = targetSize
            window.setFrame(frame, display: true, animate: true)
        }
        
        // Playlist - scale minimum size and current size proportionally
        if let window = playlistWindowController?.window {
            let minWidth: CGFloat = 275 * scale
            let minHeight: CGFloat = 116 * scale
            window.minSize = NSSize(width: minWidth, height: minHeight)
            
            // Scale current size
            var frame = window.frame
            let newWidth = max(minWidth, frame.width * (isDoubleSize ? 2.0 : 0.5))
            let newHeight = max(minHeight, frame.height * (isDoubleSize ? 2.0 : 0.5))
            let heightDiff = newHeight - frame.height
            frame.origin.y -= heightDiff
            frame.size = NSSize(width: newWidth, height: newHeight)
            window.setFrame(frame, display: true, animate: true)
        }
    }
    
    // MARK: - Window Snapping & Docking
    
    /// Called when a window drag begins
    func windowWillStartDragging(_ window: NSWindow) {
        draggingWindow = window
        // Find all windows that are docked to this window
        dockedWindowsToMove = findDockedWindows(to: window)
    }
    
    /// Called when a window drag ends
    func windowDidFinishDragging(_ window: NSWindow) {
        draggingWindow = nil
        dockedWindowsToMove.removeAll()
    }
    
    /// Called when a window is being dragged - handle snapping and move docked windows
    func windowWillMove(_ window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        // Ignore if this is a docked window being moved programmatically
        if isMovingDockedWindows && dockedWindowsToMove.contains(where: { $0 === window }) {
            return newOrigin
        }
        
        // Calculate delta from current position
        let currentOrigin = window.frame.origin
        
        // If this is a new drag, find docked windows
        if draggingWindow !== window {
            windowWillStartDragging(window)
        }
        
        // Apply snap to screen edges and other windows
        let snappedOrigin = applySnapping(for: window, to: newOrigin)
        
        // Move all docked windows by the same delta
        let actualDeltaX = snappedOrigin.x - currentOrigin.x
        let actualDeltaY = snappedOrigin.y - currentOrigin.y
        
        if !dockedWindowsToMove.isEmpty && (actualDeltaX != 0 || actualDeltaY != 0) {
            isMovingDockedWindows = true
            for dockedWindow in dockedWindowsToMove {
                var dockedOrigin = dockedWindow.frame.origin
                dockedOrigin.x += actualDeltaX
                dockedOrigin.y += actualDeltaY
                dockedWindow.setFrameOrigin(dockedOrigin)
            }
            isMovingDockedWindows = false
        }
        
        return snappedOrigin
    }
    
    /// Apply snapping to other windows and screen edges
    private func applySnapping(for window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        var snappedOrigin = newOrigin
        let frame = NSRect(origin: newOrigin, size: window.frame.size)
        
        // Snap to other visible windows
        for otherWindow in allWindows() {
            guard otherWindow != window else { continue }
            // Skip docked windows as they're moving with us
            guard !dockedWindowsToMove.contains(otherWindow) else { continue }
            
            let otherFrame = otherWindow.frame
            
            // Horizontal snapping - snap right edge to left edge
            if abs(frame.maxX - otherFrame.minX) < snapThreshold {
                snappedOrigin.x = otherFrame.minX - frame.width
            }
            // Snap left edge to right edge
            if abs(frame.minX - otherFrame.maxX) < snapThreshold {
                snappedOrigin.x = otherFrame.maxX
            }
            // Snap left edges together
            if abs(frame.minX - otherFrame.minX) < snapThreshold {
                snappedOrigin.x = otherFrame.minX
            }
            // Snap right edges together
            if abs(frame.maxX - otherFrame.maxX) < snapThreshold {
                snappedOrigin.x = otherFrame.maxX - frame.width
            }
            
            // Vertical snapping - snap top to bottom
            if abs(frame.maxY - otherFrame.minY) < snapThreshold {
                snappedOrigin.y = otherFrame.minY - frame.height
            }
            // Snap bottom to top
            if abs(frame.minY - otherFrame.maxY) < snapThreshold {
                snappedOrigin.y = otherFrame.maxY
            }
            // Snap tops together
            if abs(frame.maxY - otherFrame.maxY) < snapThreshold {
                snappedOrigin.y = otherFrame.maxY - frame.height
            }
            // Snap bottoms together
            if abs(frame.minY - otherFrame.minY) < snapThreshold {
                snappedOrigin.y = otherFrame.minY
            }
        }
        
        return snappedOrigin
    }
    
    /// Find all windows that are docked (touching) the given window
    private func findDockedWindows(to window: NSWindow) -> [NSWindow] {
        var dockedWindows: [NSWindow] = []
        var windowsToCheck: [NSWindow] = [window]
        var checkedWindows: Set<ObjectIdentifier> = [ObjectIdentifier(window)]
        
        // Use BFS to find all transitively docked windows
        while !windowsToCheck.isEmpty {
            let currentWindow = windowsToCheck.removeFirst()
            
            for otherWindow in allWindows() {
                let otherId = ObjectIdentifier(otherWindow)
                if checkedWindows.contains(otherId) { continue }
                
                if areWindowsDocked(currentWindow, otherWindow) {
                    dockedWindows.append(otherWindow)
                    windowsToCheck.append(otherWindow)
                    checkedWindows.insert(otherId)
                }
            }
        }
        
        return dockedWindows
    }
    
    /// Check if two windows are docked (touching edges)
    private func areWindowsDocked(_ window1: NSWindow, _ window2: NSWindow) -> Bool {
        let frame1 = window1.frame
        let frame2 = window2.frame
        
        // Check if windows are touching horizontally (side by side)
        let horizontallyAligned = (frame1.minY < frame2.maxY && frame1.maxY > frame2.minY)
        let hGap1 = abs(frame1.maxX - frame2.minX)
        let hGap2 = abs(frame1.minX - frame2.maxX)
        let touchingHorizontally = horizontallyAligned && (hGap1 <= dockThreshold || hGap2 <= dockThreshold)
        
        // Check if windows are touching vertically (stacked)
        let verticallyAligned = (frame1.minX < frame2.maxX && frame1.maxX > frame2.minX)
        let vGap1 = abs(frame1.maxY - frame2.minY)
        let vGap2 = abs(frame1.minY - frame2.maxY)
        let touchingVertically = verticallyAligned && (vGap1 <= dockThreshold || vGap2 <= dockThreshold)
        
        return touchingHorizontally || touchingVertically
    }
    
    /// Get all managed windows
    private func allWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        if let w = mainWindowController?.window, w.isVisible { windows.append(w) }
        if let w = playlistWindowController?.window, w.isVisible { windows.append(w) }
        if let w = equalizerWindowController?.window, w.isVisible { windows.append(w) }
        if let w = mediaLibraryWindowController?.window, w.isVisible { windows.append(w) }
        return windows
    }
    
    /// Get all visible windows
    func visibleWindows() -> [NSWindow] {
        return allWindows()
    }
    
    // MARK: - State Persistence
    
    func saveWindowPositions() {
        let defaults = UserDefaults.standard
        
        if let frame = mainWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "MainWindowFrame")
        }
        if let frame = playlistWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "PlaylistWindowFrame")
        }
        if let frame = equalizerWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "EqualizerWindowFrame")
        }
        if let frame = mediaLibraryWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "MediaLibraryWindowFrame")
        }
    }
    
    func restoreWindowPositions() {
        let defaults = UserDefaults.standard
        
        if let frameString = defaults.string(forKey: "MainWindowFrame"),
           let window = mainWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "PlaylistWindowFrame"),
           let window = playlistWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "EqualizerWindowFrame"),
           let window = equalizerWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "MediaLibraryWindowFrame"),
           let window = mediaLibraryWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
    }
}