import AppKit

/// Controller for the main player window
class MainWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var mainView: MainWindowView!
    
    // MARK: - Initialization
    
    convenience init() {
        // Create borderless window with exact Winamp dimensions
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Skin.mainWindowSize),
            styleMask: [.borderless],
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
        
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .normal
        window.title = "ClassicAmp"
        
        // Center on screen initially
        window.center()
        
        // Set up window delegate for movement handling
        window.delegate = self
    }
    
    private func setupView() {
        mainView = MainWindowView(frame: NSRect(origin: .zero, size: Skin.mainWindowSize))
        mainView.controller = self
        window?.contentView = mainView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
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

    func windowVisibilityDidChange() {
        mainView.needsDisplay = true
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
        if newOrigin != window.frame.origin {
            window.setFrameOrigin(newOrigin)
        }
    }
}
