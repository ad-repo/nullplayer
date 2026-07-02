import AppKit

/// Controller for the ProjectM visualization window (modern skin).
/// Conforms to `ProjectMWindowProviding` so WindowManager can use it interchangeably
/// with the classic `ProjectMWindowController`.
///
/// This controller has ZERO dependencies on the classic skin system.
class ModernProjectMWindowController: NSWindowController, ProjectMWindowProviding {
    
    // MARK: - Properties
    
    private var projectMView: ModernProjectMView!
    private var localKeyDownMonitor: Any?

    /// Custom fullscreen state (for borderless window)
    private var isCustomFullscreen = false
    private var preFullscreenFrame: NSRect?
    private var preFullscreenLevel: NSWindow.Level = .normal
    
    // MARK: - Initialization
    
    convenience init() {
        let windowSize = ModernSkinElements.projectMDefaultSize
        
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Enable multi-edge resizing (all edges + corners)
        window.allowedResizeEdges = [.left, .right, .top, .bottom]
        
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
        window.minSize = ModernSkinElements.projectMMinSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.title = "Visualizations"
        
        // Prevent window from being released when closed - we reuse the same controller
        window.isReleasedWhenClosed = false
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("ModernProjectMWindow")
        window.setAccessibilityLabel("Visualization Window")
    }
    
    private func setupView() {
        projectMView = ModernProjectMView(frame: NSRect(origin: .zero, size: ModernSkinElements.projectMDefaultSize))
        projectMView.controller = self
        projectMView.autoresizingMask = [.width, .height]
        window?.contentView = projectMView
        setupKeyDownMonitor()
    }

    private func setupKeyDownMonitor() {
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.projectMView.handleVisualizationKeyDown(event) else {
                return event
            }
            return nil
        }
    }

    deinit {
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
        }
    }
    
    // MARK: - Window Display
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Note: Positioning is handled by WindowManager before showWindow is called
        projectMView.startRendering()
    }
    
    /// Stop rendering when window is hidden via orderOut() (not close)
    /// This saves CPU since orderOut() doesn't trigger windowWillClose
    func stopRenderingForHide() {
        projectMView.stopRendering()
    }

    func resumeRenderingAfterWindowTransition() {
        projectMView.resumeRenderingAfterWindowTransition()
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        projectMView.skinDidChange()
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
        projectMView.resumeRenderingAfterWindowTransition()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.isCustomFullscreen else { return }
            self.projectMView.resumeRenderingAfterWindowTransition()
        }
        
        // Hide cursor after a short delay
        NSCursor.setHiddenUntilMouseMoves(true)
        
        // Hide menu bar and dock
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        
        NSLog("ModernProjectMWindowController: Entered custom fullscreen")
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
        projectMView.resumeRenderingAfterWindowTransition()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.isCustomFullscreen else { return }
            self.projectMView.resumeRenderingAfterWindowTransition()
        }
        
        preFullscreenFrame = nil
        
        NSLog("ModernProjectMWindowController: Exited custom fullscreen")
    }
    
    /// Whether the window is in custom fullscreen mode
    var isFullscreen: Bool {
        return isCustomFullscreen
    }
    
    // MARK: - Preset Navigation
    
    func nextPreset(hardCut: Bool = false) {
        projectMView.visualizationGLView?.nextPreset(hardCut: hardCut)
    }
    
    func previousPreset(hardCut: Bool = false) {
        projectMView.visualizationGLView?.previousPreset(hardCut: hardCut)
    }
    
    func selectPreset(at index: Int, hardCut: Bool = false) {
        projectMView.visualizationGLView?.selectPreset(at: index, hardCut: hardCut)
    }

    func restorePresetSelection(index: Int) {
        projectMView.visualizationGLView?.restorePresetSelection(index: index)
    }

    func randomPreset(hardCut: Bool = false) {
        projectMView.visualizationGLView?.randomPreset(hardCut: hardCut)
    }
    
    var isPresetLocked: Bool {
        get { projectMView.visualizationGLView?.isPresetLocked ?? false }
        set { projectMView.visualizationGLView?.isPresetLocked = newValue }
    }
    
    var isProjectMAvailable: Bool {
        return projectMView.visualizationGLView?.isProjectMAvailable ?? false
    }

    var currentEngineType: VisualizationType {
        return projectMView.visualizationGLView?.currentEngineType ?? .projectM
    }

    func switchEngine(to type: VisualizationType) {
        projectMView.visualizationGLView?.switchEngine(to: type)
    }
    
    var currentPresetName: String {
        return projectMView.visualizationGLView?.currentPresetName ?? ""
    }
    
    var currentPresetIndex: Int {
        return projectMView.visualizationGLView?.currentPresetIndex ?? 0
    }
    
    var presetCount: Int {
        return projectMView.visualizationGLView?.presetCount ?? 0
    }
    
    func reloadPresets() {
        projectMView.visualizationGLView?.reloadPresets()
    }
    
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        return projectMView.visualizationGLView?.presetsInfo ?? (0, 0, nil)
    }

    func buildVisualizationMenu() -> NSMenu {
        projectMView.buildVisualizationMenu()
    }
}

// MARK: - NSWindowDelegate

extension ModernProjectMWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        if isCustomFullscreen { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidResize(_ notification: Notification) {
        projectMView.needsDisplay = true
        projectMView.updateVisualizationFrame()
        WindowManager.shared.postWindowLayoutDidChange()
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
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        projectMView.needsDisplay = true
    }
    
    func windowDidMiniaturize(_ notification: Notification) {
        projectMView.stopRendering()
    }
    
    func windowDidDeminiaturize(_ notification: Notification) {
        projectMView.startRendering()
    }
}
