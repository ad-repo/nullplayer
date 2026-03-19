import AppKit

/// Controller for the standalone Spectrum Analyzer visualization window (classic skin)
class SpectrumWindowController: NSWindowController, SpectrumWindowProviding {
    
    // MARK: - Properties
    
    private var spectrumView: SpectrumView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
    /// Custom fullscreen state (for borderless window)
    private var isCustomFullscreen = false
    private var preFullscreenFrame: NSRect?
    private var preFullscreenLevel: NSWindow.Level = .normal
    
    // MARK: - Initialization
    
    convenience init() {
        // Create borderless window with manual resize handling and fullscreen support
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Enable fullscreen support
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        
        self.init(window: window)
        
        setupWindow()
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // Disable automatic window dragging - we handle it manually in the view
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = SkinElements.SpectrumWindow.minSize
        window.title = "NullPlayer Analyzer"
        
        // Prevent window from being released when closed - we reuse the same controller
        window.isReleasedWhenClosed = false
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("SpectrumWindow")
        window.setAccessibilityLabel("NullPlayer Analyzer Window")
    }
    
    private func setupView() {
        spectrumView = SpectrumView(frame: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize))
        spectrumView.controller = self
        spectrumView.autoresizingMask = [.width, .height]
        window?.contentView = spectrumView
    }
    
    // MARK: - Window Display
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Note: Positioning is handled by WindowManager.positionSubWindow() before showWindow is called
        spectrumView.startRendering()
    }
    
    /// Stop rendering when window is hidden via orderOut() (not close)
    /// This saves CPU since orderOut() doesn't trigger windowWillClose
    func stopRenderingForHide() {
        spectrumView.stopRendering()
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        spectrumView.skinDidChange()
    }

    func resetToDefaultFrame() {
        guard let window, let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        let mainFrame = mainWindow.frame
        let scale = mainFrame.width / Skin.mainWindowSize.width
        let defaultHeight = SkinElements.SpectrumWindow.windowSize.height * scale
        let defaultWidth = mainFrame.width

        window.minSize = NSSize(
            width: SkinElements.SpectrumWindow.minSize.width,
            height: SkinElements.SpectrumWindow.minSize.height * scale
        )
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let newFrame = NSRect(
            x: mainFrame.minX,
            y: mainFrame.minY - defaultHeight,
            width: defaultWidth,
            height: defaultHeight
        )
        window.setFrame(newFrame, display: false)
    }
    
    // MARK: - Shade Mode
    
    /// Toggle shade mode on/off
    func setShadeMode(_ enabled: Bool) {
        guard let window = window else { return }
        
        isShadeMode = enabled
        
        if enabled {
            // Store current frame for restoration
            normalModeFrame = window.frame
            
            // Calculate new shade mode frame (keep width, reduce height)
            let shadeHeight = SkinElements.SpectrumWindow.shadeHeight
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeHeight,
                width: window.frame.width,
                height: shadeHeight
            )
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            spectrumView.frame = NSRect(origin: .zero, size: newFrame.size)
        } else {
            // Restore normal mode frame
            let newFrame: NSRect
            
            if let storedFrame = normalModeFrame {
                newFrame = storedFrame
            } else {
                let normalSize = SkinElements.SpectrumWindow.windowSize
                newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - normalSize.height,
                    width: window.frame.width,
                    height: normalSize.height
                )
            }
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            spectrumView.frame = NSRect(origin: .zero, size: newFrame.size)
            normalModeFrame = nil
        }
        
        spectrumView.setShadeMode(enabled)
    }
    
    // MARK: - Fullscreen
    
    /// Toggle fullscreen mode using custom fullscreen implementation for borderless windows.
    func toggleFullscreen() {
        guard window != nil else { return }
        
        if isCustomFullscreen {
            exitCustomFullscreen()
        } else {
            enterCustomFullscreen()
        }
    }
    
    private func enterCustomFullscreen() {
        guard let window = window else { return }
        
        if isShadeMode {
            setShadeMode(false)
        }
        
        guard let screen = window.screen ?? NSScreen.main else { return }
        
        preFullscreenFrame = window.frame
        preFullscreenLevel = window.level
        
        spectrumView.setFullscreen(true)
        
        isCustomFullscreen = true
        window.level = .screenSaver
        window.setFrame(screen.frame, display: true, animate: true)
        
        NSCursor.setHiddenUntilMouseMoves(true)
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
    }
    
    private func exitCustomFullscreen() {
        guard let window = window else { return }
        
        isCustomFullscreen = false
        window.level = preFullscreenLevel
        NSApp.presentationOptions = []
        
        spectrumView.setFullscreen(false)
        
        if let frame = preFullscreenFrame {
            window.setFrame(frame, display: true, animate: true)
        }
        
        preFullscreenFrame = nil
    }
    
    /// Whether the window is in custom fullscreen mode.
    var isFullscreen: Bool {
        isCustomFullscreen
    }
}

// MARK: - NSWindowDelegate

extension SpectrumWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        if isCustomFullscreen { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidResize(_ notification: Notification) {
        spectrumView.needsDisplay = true
        spectrumView.updateSpectrumFrame()
    }
    
    func windowWillClose(_ notification: Notification) {
        if isCustomFullscreen {
            exitCustomFullscreen()
        }
        
        // Stop rendering when window closes
        spectrumView.stopRendering()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        spectrumView.needsDisplay = true
        // Don't bring other windows above fullscreen visualization.
        if !isCustomFullscreen {
            WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
        }
    }
    
    func windowDidResignKey(_ notification: Notification) {
        spectrumView.needsDisplay = true
    }
    
    func windowDidMiniaturize(_ notification: Notification) {
        spectrumView.stopRendering()
    }
    
    func windowDidDeminiaturize(_ notification: Notification) {
        spectrumView.startRendering()
    }
}
