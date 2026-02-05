import AppKit

/// Controller for the Milkdrop visualization window
class MilkdropWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var milkdropView: MilkdropView!
    
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
        // Create borderless window with manual resize handling
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: SkinElements.Milkdrop.defaultSize),
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
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = SkinElements.Milkdrop.minSize
        window.title = "Milkdrop"
        
        // Prevent window from being released when closed - we reuse the same controller
        window.isReleasedWhenClosed = false
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("MilkdropWindow")
        window.setAccessibilityLabel("Visualization Window")
    }
    
    // MARK: - Window Display
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Position after window is shown to ensure correct frame dimensions
        positionWindow()
        // Restart rendering (may have been stopped by windowWillClose or hide)
        milkdropView.startRendering()
    }
    
    /// Stop rendering when window is hidden via orderOut() (not close)
    /// This saves CPU since orderOut() doesn't trigger windowWillClose
    func stopRenderingForHide() {
        milkdropView.stopRendering()
    }
    
    /// Position the window to the LEFT of the main window
    /// Always positions relative to main window, ignoring saved positions
    private func positionWindow() {
        guard let window = window else { return }
        guard let mainWindow = WindowManager.shared.mainWindowController?.window else {
            window.center()
            return
        }
        
        let mainFrame = mainWindow.frame
        let mainScreen = mainWindow.screen ?? NSScreen.main
        
        // Always position relative to main window
        var newX = mainFrame.minX - window.frame.width  // LEFT of main
        let newY = mainFrame.maxY - window.frame.height // Top-aligned
        
        // Screen bounds check - don't go off left edge
        if let screen = mainScreen {
            if newX < screen.visibleFrame.minX {
                // Fall back to ABOVE the main window instead of right (Plex browser is on right)
                newX = mainFrame.minX
                let aboveY = mainFrame.maxY
                // Make sure it fits on screen
                if aboveY + window.frame.height <= screen.visibleFrame.maxY {
                    window.setFrameOrigin(NSPoint(x: newX, y: aboveY))
                    return
                }
                // If no room above, center on screen
                window.center()
                return
            }
        }
        
        window.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
    
    private func setupView() {
        milkdropView = MilkdropView(frame: NSRect(origin: .zero, size: SkinElements.Milkdrop.defaultSize))
        milkdropView.controller = self
        milkdropView.autoresizingMask = [.width, .height]
        window?.contentView = milkdropView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        milkdropView.skinDidChange()
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
            let shadeHeight = SkinElements.Milkdrop.shadeHeight
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeHeight,
                width: window.frame.width,
                height: shadeHeight
            )
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            milkdropView.frame = NSRect(origin: .zero, size: newFrame.size)
        } else {
            // Restore normal mode frame
            let newFrame: NSRect
            
            if let storedFrame = normalModeFrame {
                newFrame = storedFrame
            } else {
                let normalSize = SkinElements.Milkdrop.defaultSize
                newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - normalSize.height,
                    width: window.frame.width,
                    height: normalSize.height
                )
            }
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            milkdropView.frame = NSRect(origin: .zero, size: newFrame.size)
            normalModeFrame = nil
        }
        
        milkdropView.setShadeMode(enabled)
    }
    
    // MARK: - Fullscreen
    
    /// Toggle fullscreen mode
    /// Uses custom fullscreen implementation for borderless windows
    func toggleFullscreen() {
        guard window != nil else { return }
        
        if isCustomFullscreen {
            exitCustomFullscreen()
        } else {
            enterCustomFullscreen()
        }
    }
    
    /// Enter custom fullscreen mode (for borderless window)
    private func enterCustomFullscreen() {
        guard let window = window else { return }
        
        // Exit shade mode before going fullscreen
        if isShadeMode {
            setShadeMode(false)
        }
        
        // Get the screen containing the window (or main screen as fallback)
        guard let screen = window.screen ?? NSScreen.main else { return }
        
        // Store pre-fullscreen state
        preFullscreenFrame = window.frame
        preFullscreenLevel = window.level
        
        // Hide window chrome
        milkdropView.setFullscreen(true)
        
        // Set window to fullscreen
        isCustomFullscreen = true
        window.level = .screenSaver  // Above everything except system dialogs
        window.setFrame(screen.frame, display: true, animate: true)
        
        // Hide cursor after a short delay
        NSCursor.setHiddenUntilMouseMoves(true)
        
        // Hide menu bar and dock
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        
        NSLog("MilkdropWindowController: Entered custom fullscreen")
    }
    
    /// Exit custom fullscreen mode
    private func exitCustomFullscreen() {
        guard let window = window else { return }
        
        isCustomFullscreen = false
        
        // Restore window level
        window.level = preFullscreenLevel
        
        // Restore presentation options
        NSApp.presentationOptions = []
        
        // Show window chrome
        milkdropView.setFullscreen(false)
        
        // Restore pre-fullscreen frame
        if let frame = preFullscreenFrame {
            window.setFrame(frame, display: true, animate: true)
        }
        
        preFullscreenFrame = nil
        
        NSLog("MilkdropWindowController: Exited custom fullscreen")
    }
    
    /// Whether the window is in custom fullscreen mode
    var isFullscreen: Bool {
        return isCustomFullscreen
    }
    
    // MARK: - Preset Navigation
    
    /// Go to next preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func nextPreset(hardCut: Bool = false) {
        milkdropView.visualizationGLView?.nextPreset(hardCut: hardCut)
    }
    
    /// Go to previous preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func previousPreset(hardCut: Bool = false) {
        milkdropView.visualizationGLView?.previousPreset(hardCut: hardCut)
    }
    
    /// Select preset at specific index
    /// - Parameters:
    ///   - index: The preset index to select
    ///   - hardCut: If true, switch immediately without blending
    func selectPreset(at index: Int, hardCut: Bool = false) {
        milkdropView.visualizationGLView?.selectPreset(at: index, hardCut: hardCut)
    }
    
    /// Select a random preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func randomPreset(hardCut: Bool = false) {
        milkdropView.visualizationGLView?.randomPreset(hardCut: hardCut)
    }
    
    /// Set specific preset by index
    /// - Parameters:
    ///   - index: The preset index to select
    ///   - hardCut: If true, switch immediately without blending
    func setPreset(_ index: Int, hardCut: Bool = false) {
        milkdropView.visualizationGLView?.selectPreset(at: index, hardCut: hardCut)
    }
    
    /// Lock or unlock the current preset
    var isPresetLocked: Bool {
        get { milkdropView.visualizationGLView?.isPresetLocked ?? false }
        set { milkdropView.visualizationGLView?.isPresetLocked = newValue }
    }
    
    /// Whether projectM is available
    var isProjectMAvailable: Bool {
        return milkdropView.visualizationGLView?.isProjectMAvailable ?? false
    }
    
    /// Current preset name
    var currentPresetName: String {
        return milkdropView.visualizationGLView?.currentPresetName ?? ""
    }
    
    /// Current preset index
    var currentPresetIndex: Int {
        return milkdropView.visualizationGLView?.currentPresetIndex ?? 0
    }
    
    /// Total number of presets
    var presetCount: Int {
        return milkdropView.visualizationGLView?.presetCount ?? 0
    }
    
    /// Reload all presets from bundled and custom folders
    func reloadPresets() {
        milkdropView.visualizationGLView?.reloadPresets()
    }
    
    /// Get information about loaded presets
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        return milkdropView.visualizationGLView?.presetsInfo ?? (0, 0, nil)
    }
}

// MARK: - NSWindowDelegate

extension MilkdropWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidResize(_ notification: Notification) {
        milkdropView.needsDisplay = true
        milkdropView.updateVisualizationFrame()
    }
    
    func windowWillClose(_ notification: Notification) {
        // Exit fullscreen if needed before closing
        if isCustomFullscreen {
            exitCustomFullscreen()
        }
        
        // Stop rendering when window closes
        milkdropView.stopRendering()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        milkdropView.needsDisplay = true
        // Bring all app windows to front when this window gets focus
        WindowManager.shared.bringAllWindowsToFront()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        milkdropView.needsDisplay = true
    }
    
    func windowWillEnterFullScreen(_ notification: Notification) {
        // Hide window chrome in fullscreen
        milkdropView.needsDisplay = true
    }
    
    func windowDidExitFullScreen(_ notification: Notification) {
        // Restore window chrome after fullscreen
        milkdropView.needsDisplay = true
    }
    
    func windowDidMiniaturize(_ notification: Notification) {
        milkdropView.stopRendering()
    }
    
    func windowDidDeminiaturize(_ notification: Notification) {
        milkdropView.startRendering()
    }
}
