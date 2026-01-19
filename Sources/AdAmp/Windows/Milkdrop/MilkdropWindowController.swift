import AppKit

/// Controller for the Milkdrop visualization window
class MilkdropWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var milkdropView: MilkdropView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
    /// Current preset index (for future projectM integration)
    private var currentPresetIndex: Int = 0
    private var presetCount: Int = 0
    
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
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
    }
    
    // MARK: - Window Display
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Position after window is shown to ensure correct frame dimensions
        positionWindow()
    }
    
    /// Position the window to the LEFT of the main window
    private func positionWindow() {
        guard let window = window,
              let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        
        let mainFrame = mainWindow.frame
        var newX = mainFrame.minX - window.frame.width  // LEFT of main
        let newY = mainFrame.maxY - window.frame.height // Top-aligned
        
        // Screen bounds check - don't go off left edge
        if let screen = mainWindow.screen ?? NSScreen.main {
            if newX < screen.visibleFrame.minX {
                // Fall back to right side if no room on left
                newX = mainFrame.maxX
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
    func toggleFullscreen() {
        guard let window = window else { return }
        
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            // Exit shade mode before going fullscreen
            if isShadeMode {
                setShadeMode(false)
            }
            window.toggleFullScreen(nil)
        }
    }
    
    // MARK: - Preset Navigation
    
    /// Go to next preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func nextPreset(hardCut: Bool = false) {
        milkdropView.visualizationGLView?.nextPreset(hardCut: hardCut)
        updatePresetInfo()
    }
    
    /// Go to previous preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func previousPreset(hardCut: Bool = false) {
        milkdropView.visualizationGLView?.previousPreset(hardCut: hardCut)
        updatePresetInfo()
    }
    
    /// Select a random preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func randomPreset(hardCut: Bool = false) {
        milkdropView.visualizationGLView?.randomPreset(hardCut: hardCut)
        updatePresetInfo()
    }
    
    /// Set specific preset by index
    /// - Parameters:
    ///   - index: The preset index to select
    ///   - hardCut: If true, switch immediately without blending
    func setPreset(_ index: Int, hardCut: Bool = false) {
        milkdropView.visualizationGLView?.selectPreset(at: index, hardCut: hardCut)
        updatePresetInfo()
    }
    
    /// Update internal preset tracking from visualization view
    private func updatePresetInfo() {
        if let vis = milkdropView.visualizationGLView {
            currentPresetIndex = vis.currentPresetIndex
            presetCount = vis.presetCount
        }
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
    
    // MARK: - Visualization Control
    
    /// Set visualization mode
    func setVisualizationMode(_ mode: VisualizationGLView.VisualizationMode) {
        milkdropView.setVisualizationMode(mode)
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
        // Stop rendering when window closes
        milkdropView.stopRendering()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        milkdropView.needsDisplay = true
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
