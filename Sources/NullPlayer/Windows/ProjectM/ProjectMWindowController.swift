import AppKit

/// Controller for the ProjectM visualization window
class ProjectMWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var projectMView: ProjectMView!
    
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
            contentRect: NSRect(origin: .zero, size: SkinElements.ProjectM.defaultSize),
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
        window.minSize = SkinElements.ProjectM.minSize
        window.title = "ProjectM"
        
        // Prevent window from being released when closed - we reuse the same controller
        window.isReleasedWhenClosed = false
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("ProjectMWindow")
        window.setAccessibilityLabel("Visualization Window")
    }
    
    // MARK: - Window Display
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Position after window is shown to ensure correct frame dimensions
        positionWindow()
        // Restart rendering (may have been stopped by windowWillClose or hide)
        projectMView.startRendering()
    }
    
    /// Stop rendering when window is hidden via orderOut() (not close)
    /// This saves CPU since orderOut() doesn't trigger windowWillClose
    func stopRenderingForHide() {
        projectMView.stopRendering()
    }
    
    /// Position the window to the LEFT of the main window
    /// Always positions on the left side, even if partially offscreen
    private func positionWindow() {
        guard let window = window else { return }
        guard let mainWindow = WindowManager.shared.mainWindowController?.window else {
            window.center()
            return
        }
        
        let mainFrame = mainWindow.frame
        let newX = mainFrame.minX - window.frame.width  // Always LEFT of main
        let newY = mainFrame.maxY - window.frame.height  // Top-aligned
        
        window.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
    
    private func setupView() {
        projectMView = ProjectMView(frame: NSRect(origin: .zero, size: SkinElements.ProjectM.defaultSize))
        projectMView.controller = self
        projectMView.autoresizingMask = [.width, .height]
        window?.contentView = projectMView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        projectMView.skinDidChange()
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
            let shadeHeight = SkinElements.ProjectM.shadeHeight
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeHeight,
                width: window.frame.width,
                height: shadeHeight
            )
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            projectMView.frame = NSRect(origin: .zero, size: newFrame.size)
        } else {
            // Restore normal mode frame
            let newFrame: NSRect
            
            if let storedFrame = normalModeFrame {
                newFrame = storedFrame
            } else {
                let normalSize = SkinElements.ProjectM.defaultSize
                newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - normalSize.height,
                    width: window.frame.width,
                    height: normalSize.height
                )
            }
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            projectMView.frame = NSRect(origin: .zero, size: newFrame.size)
            normalModeFrame = nil
        }
        
        projectMView.setShadeMode(enabled)
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
        projectMView.setFullscreen(true)
        
        // Set window to fullscreen
        isCustomFullscreen = true
        window.level = .screenSaver  // Above everything except system dialogs
        window.setFrame(screen.frame, display: true, animate: true)
        
        // Hide cursor after a short delay
        NSCursor.setHiddenUntilMouseMoves(true)
        
        // Hide menu bar and dock
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        
        NSLog("ProjectMWindowController: Entered custom fullscreen")
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
        projectMView.setFullscreen(false)
        
        // Restore pre-fullscreen frame
        if let frame = preFullscreenFrame {
            window.setFrame(frame, display: true, animate: true)
        }
        
        preFullscreenFrame = nil
        
        NSLog("ProjectMWindowController: Exited custom fullscreen")
    }
    
    /// Whether the window is in custom fullscreen mode
    var isFullscreen: Bool {
        return isCustomFullscreen
    }
    
    // MARK: - Preset Navigation
    
    /// Go to next preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func nextPreset(hardCut: Bool = false) {
        projectMView.visualizationGLView?.nextPreset(hardCut: hardCut)
    }
    
    /// Go to previous preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func previousPreset(hardCut: Bool = false) {
        projectMView.visualizationGLView?.previousPreset(hardCut: hardCut)
    }
    
    /// Select preset at specific index
    /// - Parameters:
    ///   - index: The preset index to select
    ///   - hardCut: If true, switch immediately without blending
    func selectPreset(at index: Int, hardCut: Bool = false) {
        projectMView.visualizationGLView?.selectPreset(at: index, hardCut: hardCut)
    }
    
    /// Select a random preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func randomPreset(hardCut: Bool = false) {
        projectMView.visualizationGLView?.randomPreset(hardCut: hardCut)
    }
    
    /// Set specific preset by index
    /// - Parameters:
    ///   - index: The preset index to select
    ///   - hardCut: If true, switch immediately without blending
    func setPreset(_ index: Int, hardCut: Bool = false) {
        projectMView.visualizationGLView?.selectPreset(at: index, hardCut: hardCut)
    }
    
    /// Lock or unlock the current preset
    var isPresetLocked: Bool {
        get { projectMView.visualizationGLView?.isPresetLocked ?? false }
        set { projectMView.visualizationGLView?.isPresetLocked = newValue }
    }
    
    /// Whether projectM is available
    var isProjectMAvailable: Bool {
        return projectMView.visualizationGLView?.isProjectMAvailable ?? false
    }
    
    /// Current preset name
    var currentPresetName: String {
        return projectMView.visualizationGLView?.currentPresetName ?? ""
    }
    
    /// Current preset index
    var currentPresetIndex: Int {
        return projectMView.visualizationGLView?.currentPresetIndex ?? 0
    }
    
    /// Total number of presets
    var presetCount: Int {
        return projectMView.visualizationGLView?.presetCount ?? 0
    }
    
    /// Reload all presets from bundled and custom folders
    func reloadPresets() {
        projectMView.visualizationGLView?.reloadPresets()
    }
    
    /// Get information about loaded presets
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        return projectMView.visualizationGLView?.presetsInfo ?? (0, 0, nil)
    }
}

// MARK: - NSWindowDelegate

extension ProjectMWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidResize(_ notification: Notification) {
        projectMView.needsDisplay = true
        projectMView.updateVisualizationFrame()
    }
    
    func windowWillClose(_ notification: Notification) {
        // Exit fullscreen if needed before closing
        if isCustomFullscreen {
            exitCustomFullscreen()
        }
        
        // Stop rendering when window closes
        projectMView.stopRendering()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        projectMView.needsDisplay = true
        // Bring all app windows to front when this window gets focus
        WindowManager.shared.bringAllWindowsToFront()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        projectMView.needsDisplay = true
    }
    
    func windowWillEnterFullScreen(_ notification: Notification) {
        // Hide window chrome in fullscreen
        projectMView.needsDisplay = true
    }
    
    func windowDidExitFullScreen(_ notification: Notification) {
        // Restore window chrome after fullscreen
        projectMView.needsDisplay = true
    }
    
    func windowDidMiniaturize(_ notification: Notification) {
        projectMView.stopRendering()
    }
    
    func windowDidDeminiaturize(_ notification: Notification) {
        projectMView.startRendering()
    }
}
