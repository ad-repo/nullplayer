import AppKit

/// Controller for the main player window
class MainWindowController: NSWindowController, MainWindowProviding {
    
    // MARK: - Properties
    
    private var mainView: MainWindowView!
    
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
        window.title = "NullPlayer"
        
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
    
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {
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
    
    func setNeedsDisplay() {
        mainView.needsDisplay = true
    }
    
    var isWindowVisible: Bool {
        window?.isVisible == true
    }
    
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let wm = WindowManager.shared
        guard !wm.isRunningModernUI else { return frameSize }
        guard sender === window else { return frameSize }
        let hasAttachedChildren = !(sender.childWindows?.isEmpty ?? true)
        // Classic mode: while connected/docked, main window cannot be edge-resized.
        if hasAttachedChildren || wm.isWindowDocked(sender) {
            return sender.frame.size
        }
        return frameSize
    }

    func windowWillMove(_ notification: Notification) {
        // Handle window snapping via WindowManager
    }
    
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowWillMiniaturize(_ notification: Notification) {
        guard let window = window else { return }
        WindowManager.shared.attachDockedWindowsForMiniaturize(mainWindow: window)
    }
    
    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = window else { return }
        WindowManager.shared.detachDockedWindowsAfterDeminiaturize(mainWindow: window)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Bring all app windows to front when main window gets focus
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }
}
