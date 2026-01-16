import AppKit

/// Controller for the equalizer window
class EQWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var eqView: EQView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
    // MARK: - Initialization
    
    convenience init() {
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: Skin.eqWindowSize),
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
        window.title = "Equalizer"
        
        // Set minimum size for EQ window
        window.minSize = Skin.eqWindowSize
        
        // Position below main window
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            window.setFrameOrigin(NSPoint(x: mainFrame.minX, y: mainFrame.minY - Skin.eqWindowSize.height))
        } else {
            window.center()
        }
        
        window.delegate = self
    }
    
    private func setupView() {
        eqView = EQView(frame: NSRect(origin: .zero, size: Skin.eqWindowSize))
        eqView.controller = self
        window?.contentView = eqView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        eqView.skinDidChange()
    }
    
    // MARK: - Shade Mode
    
    /// Toggle shade mode on/off
    func setShadeMode(_ enabled: Bool) {
        guard let window = window else { return }
        
        isShadeMode = enabled
        
        if enabled {
            // Store current frame for restoration
            normalModeFrame = window.frame
            
            // Calculate new shade mode frame
            let shadeSize = SkinElements.EQShade.windowSize
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeSize.height,
                width: shadeSize.width,
                height: shadeSize.height
            )
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            eqView.frame = NSRect(origin: .zero, size: shadeSize)
        } else {
            // Restore normal mode frame
            let normalSize = Skin.eqWindowSize
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
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            eqView.frame = NSRect(origin: .zero, size: normalSize)
            normalModeFrame = nil
        }
        
        eqView.setShadeMode(enabled)
    }
    
    // MARK: - Private Properties
    
    private var mainWindowController: MainWindowController? {
        return nil
    }
}

// MARK: - NSWindowDelegate

extension EQWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        if newOrigin != window.frame.origin {
            window.setFrameOrigin(newOrigin)
        }
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
