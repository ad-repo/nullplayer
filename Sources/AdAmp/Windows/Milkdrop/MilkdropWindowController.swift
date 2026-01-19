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
        
        // Position to the right of the main window
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            let newFrame = NSRect(
                x: mainFrame.maxX + 10,
                y: mainFrame.minY,
                width: SkinElements.Milkdrop.defaultSize.width,
                height: SkinElements.Milkdrop.defaultSize.height
            )
            window.setFrame(newFrame, display: true)
        } else {
            window.center()
        }
        
        window.delegate = self
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
    
    // MARK: - Preset Navigation (for future projectM integration)
    
    /// Go to next preset
    func nextPreset() {
        guard presetCount > 0 else { return }
        currentPresetIndex = (currentPresetIndex + 1) % presetCount
        // Future: tell projectM to change preset
        NSLog("MilkdropWindowController: Next preset (%d/%d)", currentPresetIndex, presetCount)
    }
    
    /// Go to previous preset
    func previousPreset() {
        guard presetCount > 0 else { return }
        currentPresetIndex = (currentPresetIndex - 1 + presetCount) % presetCount
        // Future: tell projectM to change preset
        NSLog("MilkdropWindowController: Previous preset (%d/%d)", currentPresetIndex, presetCount)
    }
    
    /// Set specific preset by index
    func setPreset(_ index: Int) {
        guard index >= 0 && index < presetCount else { return }
        currentPresetIndex = index
        // Future: tell projectM to change preset
        NSLog("MilkdropWindowController: Set preset %d", index)
    }
    
    /// Load presets from bundle (for future projectM integration)
    func loadPresets() {
        // Future: enumerate .milk files from Bundle.module/Resources/Presets/
        // and load them into projectM
        presetCount = 0
        currentPresetIndex = 0
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
