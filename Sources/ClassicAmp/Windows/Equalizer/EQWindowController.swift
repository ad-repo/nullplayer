import AppKit

/// Controller for the equalizer window
class EQWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var eqView: EQView!
    
    // MARK: - Initialization
    
    convenience init() {
        let window = NSWindow(
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
