import AppKit

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
    
    /// Main player window controller
    private(set) var mainWindowController: MainWindowController?
    
    /// Playlist window controller
    private var playlistWindowController: PlaylistWindowController?
    
    /// Equalizer window controller
    private var equalizerWindowController: EQWindowController?
    
    /// Media library window controller
    private var mediaLibraryWindowController: MediaLibraryWindowController?
    
    /// Snap threshold in pixels
    private let snapThreshold: CGFloat = 10
    
    /// Docking threshold - windows closer than this are considered docked
    private let dockThreshold: CGFloat = 2
    
    /// Track which window is currently being dragged
    private var draggingWindow: NSWindow?
    
    /// Track the last drag delta for grouped movement
    private var lastDragDelta: NSPoint = .zero
    
    /// Windows that should move together with the dragging window
    private var dockedWindowsToMove: [NSWindow] = []
    
    // MARK: - Initialization
    
    private init() {
        // Load default skin
        loadDefaultSkin()
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
    
    private func notifySkinChanged() {
        // Notify all windows to redraw with new skin
        mainWindowController?.skinDidChange()
        playlistWindowController?.skinDidChange()
        equalizerWindowController?.skinDidChange()
        mediaLibraryWindowController?.skinDidChange()
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
    
    /// Called when a window is being dragged - handles snapping and grouped movement
    func windowWillMove(_ window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        var snappedOrigin = newOrigin
        
        // Get all other windows (excluding docked ones that will move together)
        let otherWindows = allWindows().filter { $0 !== window && !dockedWindowsToMove.contains($0) }
        
        // Check for snapping to other windows
        for otherWindow in otherWindows {
            let otherFrame = otherWindow.frame
            let windowFrame = NSRect(origin: newOrigin, size: window.frame.size)
            
            // Snap right edge to left edge
            if abs(windowFrame.maxX - otherFrame.minX) < snapThreshold {
                snappedOrigin.x = otherFrame.minX - window.frame.width
            }
            // Snap left edge to right edge
            if abs(windowFrame.minX - otherFrame.maxX) < snapThreshold {
                snappedOrigin.x = otherFrame.maxX
            }
            // Snap bottom edge to top edge
            if abs(windowFrame.minY - otherFrame.maxY) < snapThreshold {
                snappedOrigin.y = otherFrame.maxY
            }
            // Snap top edge to bottom edge
            if abs(windowFrame.maxY - otherFrame.minY) < snapThreshold {
                snappedOrigin.y = otherFrame.minY - window.frame.height
            }
            
            // Align tops
            if abs(windowFrame.maxY - otherFrame.maxY) < snapThreshold {
                snappedOrigin.y = otherFrame.maxY - window.frame.height
            }
            // Align bottoms
            if abs(windowFrame.minY - otherFrame.minY) < snapThreshold {
                snappedOrigin.y = otherFrame.minY
            }
        }
        
        // Snap to screen edges
        if let screen = window.screen {
            let visibleFrame = screen.visibleFrame
            
            if abs(snappedOrigin.x - visibleFrame.minX) < snapThreshold {
                snappedOrigin.x = visibleFrame.minX
            }
            if abs(snappedOrigin.x + window.frame.width - visibleFrame.maxX) < snapThreshold {
                snappedOrigin.x = visibleFrame.maxX - window.frame.width
            }
            if abs(snappedOrigin.y - visibleFrame.minY) < snapThreshold {
                snappedOrigin.y = visibleFrame.minY
            }
            if abs(snappedOrigin.y + window.frame.height - visibleFrame.maxY) < snapThreshold {
                snappedOrigin.y = visibleFrame.maxY - window.frame.height
            }
        }
        
        // Move docked windows together
        let finalDelta = NSPoint(
            x: snappedOrigin.x - window.frame.origin.x,
            y: snappedOrigin.y - window.frame.origin.y
        )
        
        for dockedWindow in dockedWindowsToMove {
            let newDockedOrigin = NSPoint(
                x: dockedWindow.frame.origin.x + finalDelta.x,
                y: dockedWindow.frame.origin.y + finalDelta.y
            )
            dockedWindow.setFrameOrigin(newDockedOrigin)
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
        let touchingHorizontally = horizontallyAligned && (
            abs(frame1.maxX - frame2.minX) <= dockThreshold ||  // window1 left of window2
            abs(frame1.minX - frame2.maxX) <= dockThreshold     // window1 right of window2
        )
        
        // Check if windows are touching vertically (stacked)
        let verticallyAligned = (frame1.minX < frame2.maxX && frame1.maxX > frame2.minX)
        let touchingVertically = verticallyAligned && (
            abs(frame1.maxY - frame2.minY) <= dockThreshold ||  // window1 below window2
            abs(frame1.minY - frame2.maxY) <= dockThreshold     // window1 above window2
        )
        
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