import AppKit

/// Controller for the main player window
class MainWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var mainView: MainWindowView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
    // MARK: - Initialization
    
    convenience init() {
        // Create borderless window with manual resize handling
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: Skin.mainWindowSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.init(window: window)
        
        setupWindow()
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // Disable automatic window dragging - we handle it manually in the view
        // to support moving docked windows together
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .normal
        window.title = "AdAmp"
        
        // Set minimum size for main window
        window.minSize = Skin.mainWindowSize
        
        // Center on screen initially
        window.center()
        
        // Set up window delegate
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("MainWindow")
        window.setAccessibilityLabel("Main Window")
    }
    
    private func setupView() {
        mainView = MainWindowView(frame: NSRect(origin: .zero, size: Skin.mainWindowSize))
        mainView.controller = self
        window?.contentView = mainView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        mainView.skinDidChange()  // Update marquee layer's skin image
        mainView.needsDisplay = true
    }
    
    func updatePlaybackState() {
        mainView.needsDisplay = true
    }
    
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        mainView.updateTime(current: current, duration: duration)
    }
    
    func updateTrackInfo(_ track: Track?) {
        mainView.updateTrackInfo(track)
    }
    
    func updateVideoTrackInfo(title: String) {
        mainView.updateVideoTrackInfo(title: title)
    }
    
    func clearVideoTrackInfo() {
        mainView.clearVideoTrackInfo()
    }
    
    func updateSpectrum(_ levels: [Float]) {
        mainView.updateSpectrum(levels)
    }

    func windowVisibilityDidChange() {
        mainView.needsDisplay = true
    }
    
    // MARK: - Shade Mode
    
    /// Toggle shade mode on/off
    func setShadeMode(_ enabled: Bool) {
        guard let window = window else { return }
        
        isShadeMode = enabled
        
        if enabled {
            // Store current frame for restoration
            normalModeFrame = window.frame
            
            // Calculate new shade mode frame (same origin, shorter height)
            let shadeSize = SkinElements.MainShade.windowSize
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeSize.height,
                width: shadeSize.width,
                height: shadeSize.height
            )
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            mainView.frame = NSRect(origin: .zero, size: shadeSize)
        } else {
            // Restore normal mode frame
            let normalSize = Skin.mainWindowSize
            let newFrame: NSRect
            
            if let storedFrame = normalModeFrame {
                newFrame = storedFrame
            } else {
                // Calculate frame from current position
                newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - normalSize.height,
                    width: normalSize.width,
                    height: normalSize.height
                )
            }
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            mainView.frame = NSRect(origin: .zero, size: normalSize)
            normalModeFrame = nil
        }
        
        mainView.setShadeMode(enabled)
    }
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    func windowWillMove(_ notification: Notification) {
        // Handle window snapping via WindowManager
    }
    
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Bring all app windows to front when main window gets focus
        WindowManager.shared.bringAllWindowsToFront()
    }
}
