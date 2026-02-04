import AppKit

/// Controller for the standalone Spectrum Analyzer visualization window
class SpectrumWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var spectrumView: SpectrumView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
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
        window.title = "Spectrum Analyzer"
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("SpectrumWindow")
        window.setAccessibilityLabel("Spectrum Analyzer Window")
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
}

// MARK: - NSWindowDelegate

extension SpectrumWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidResize(_ notification: Notification) {
        spectrumView.needsDisplay = true
        spectrumView.updateSpectrumFrame()
    }
    
    func windowWillClose(_ notification: Notification) {
        // Stop rendering when window closes
        spectrumView.stopRendering()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        spectrumView.needsDisplay = true
        // Bring all app windows to front when this window gets focus
        WindowManager.shared.bringAllWindowsToFront()
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
