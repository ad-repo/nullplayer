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
    
    /// Snap threshold in pixels
    private let snapThreshold: CGFloat = 10
    
    /// Currently docked window groups
    private var dockedGroups: [[NSWindow]] = []
    
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
    }
    
    // MARK: - Window Snapping
    
    /// Called when a window is being dragged
    func windowWillMove(_ window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        var snappedOrigin = newOrigin
        
        // Get all other windows
        let otherWindows = allWindows().filter { $0 !== window }
        
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
        
        return snappedOrigin
    }
    
    /// Get all managed windows
    private func allWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        if let w = mainWindowController?.window { windows.append(w) }
        if let w = playlistWindowController?.window { windows.append(w) }
        if let w = equalizerWindowController?.window { windows.append(w) }
        return windows
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
    }
}
