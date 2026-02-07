import AppKit

/// Controller for the modern main player window.
/// Conforms to `MainWindowProviding` so WindowManager can use it interchangeably
/// with the classic `MainWindowController`.
///
/// This controller has ZERO dependencies on the classic skin system.
class ModernMainWindowController: NSWindowController, MainWindowProviding {
    
    // MARK: - Properties
    
    private var modernView: ModernMainWindowView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
    // MARK: - Initialization
    
    convenience init() {
        let windowSize = ModernSkinElements.mainWindowSize
        
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .miniaturizable],
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
        window.title = "NullPlayer"
        
        window.minSize = ModernSkinElements.mainWindowSize
        window.center()
        
        window.delegate = self
        
        window.setAccessibilityIdentifier("ModernMainWindow")
        window.setAccessibilityLabel("Main Window")
    }
    
    private func setupView() {
        modernView = ModernMainWindowView(frame: NSRect(origin: .zero, size: ModernSkinElements.mainWindowSize))
        modernView.controller = self
        window?.contentView = modernView
    }
    
    // MARK: - MainWindowProviding
    
    var isWindowVisible: Bool {
        window?.isVisible == true
    }
    
    func updatePlaybackState() {
        modernView.needsDisplay = true
    }
    
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        modernView.updateTime(current: current, duration: duration)
    }
    
    func updateTrackInfo(_ track: Track?) {
        modernView.updateTrackInfo(track)
    }
    
    func updateVideoTrackInfo(title: String) {
        modernView.updateVideoTrackInfo(title: title)
    }
    
    func clearVideoTrackInfo() {
        modernView.clearVideoTrackInfo()
    }
    
    func updateSpectrum(_ levels: [Float]) {
        modernView.updateSpectrum(levels)
    }
    
    func skinDidChange() {
        modernView.skinDidChange()
        modernView.needsDisplay = true
    }
    
    func windowVisibilityDidChange() {
        modernView.needsDisplay = true
    }
    
    func setNeedsDisplay() {
        modernView.needsDisplay = true
    }
    
    func toggleShadeMode() {
        setShadeMode(!isShadeMode)
    }
    
    // MARK: - Shade Mode
    
    /// Shade mode height: title bar (14) + seek (6) + transport row (28) + padding = ~18px base * scale
    static let shadeHeight: CGFloat = 18 * ModernSkinElements.scaleFactor
    
    func setShadeMode(_ enabled: Bool) {
        guard let window = window else { return }
        
        isShadeMode = enabled
        
        if enabled {
            normalModeFrame = window.frame
            
            let shadeSize = NSSize(width: ModernSkinElements.mainWindowSize.width,
                                   height: Self.shadeHeight)
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeSize.height,
                width: shadeSize.width,
                height: shadeSize.height
            )
            
            window.setFrame(newFrame, display: true, animate: true)
            modernView.frame = NSRect(origin: .zero, size: shadeSize)
        } else {
            let normalSize = ModernSkinElements.mainWindowSize
            let newFrame: NSRect
            
            if let storedFrame = normalModeFrame {
                newFrame = storedFrame
            } else {
                newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - normalSize.height,
                    width: normalSize.width,
                    height: normalSize.height
                )
            }
            
            window.setFrame(newFrame, display: true, animate: true)
            modernView.frame = NSRect(origin: .zero, size: normalSize)
            normalModeFrame = nil
        }
        
        modernView.isShadeMode = isShadeMode
        modernView.needsDisplay = true
    }
}

// MARK: - NSWindowDelegate

extension ModernMainWindowController: NSWindowDelegate {
    func windowWillMove(_ notification: Notification) {
    }
    
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        WindowManager.shared.bringAllWindowsToFront()
    }
}
