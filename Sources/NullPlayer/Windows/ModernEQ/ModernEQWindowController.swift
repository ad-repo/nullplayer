import AppKit

/// Controller for the equalizer window (modern skin).
/// Conforms to `EQWindowProviding` so WindowManager can use it interchangeably
/// with the classic `EQWindowController`.
///
/// This controller has ZERO dependencies on the classic skin system.
class ModernEQWindowController: NSWindowController, EQWindowProviding {
    
    // MARK: - Properties
    
    private var eqView: ModernEQView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
    // MARK: - Initialization
    
    convenience init() {
        let windowSize = ModernSkinElements.eqWindowSize
        
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
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
        
        // Disable automatic window dragging - we handle it manually in the view
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.title = "Equalizer"
        
        // Prevent window from being released when closed - we reuse the same controller
        window.isReleasedWhenClosed = false
        
        // Fixed size window (matches main window width for docking)
        window.minSize = ModernSkinElements.eqMinSize
        window.maxSize = ModernSkinElements.eqMinSize
        
        // Initial center position - will be repositioned by WindowManager
        window.center()
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("ModernEqualizerWindow")
        window.setAccessibilityLabel("Equalizer Window")
    }
    
    private func setupView() {
        eqView = ModernEQView(frame: NSRect(origin: .zero, size: ModernSkinElements.eqWindowSize))
        eqView.controller = self
        eqView.autoresizingMask = [.width, .height]
        window?.contentView = eqView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        eqView.skinDidChange()
    }
    
    // MARK: - Shade Mode
    
    func setShadeMode(_ enabled: Bool) {
        guard let window = window else { return }
        
        isShadeMode = enabled
        
        if enabled {
            // Store current frame for restoration
            normalModeFrame = window.frame
            
            // Calculate new shade mode frame (keep width, reduce height)
            let shadeHeight = ModernSkinElements.eqShadeHeight
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeHeight,
                width: window.frame.width,
                height: shadeHeight
            )
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            eqView.frame = NSRect(origin: .zero, size: newFrame.size)
        } else {
            // Restore normal mode frame
            let newFrame: NSRect
            
            if let storedFrame = normalModeFrame {
                newFrame = storedFrame
            } else {
                let normalSize = ModernSkinElements.eqWindowSize
                newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - normalSize.height,
                    width: normalSize.width,
                    height: normalSize.height
                )
            }
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            eqView.frame = NSRect(origin: .zero, size: newFrame.size)
            normalModeFrame = nil
        }
        
        eqView.setShadeMode(enabled)
    }
}

// MARK: - NSWindowDelegate

extension ModernEQWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }

    func windowDidResize(_ notification: Notification) {
        eqView.needsDisplay = true
        NotificationCenter.default.post(name: .windowLayoutDidChange, object: nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        eqView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        eqView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
