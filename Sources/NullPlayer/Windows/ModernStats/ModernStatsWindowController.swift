import AppKit

class ModernStatsWindowController: NSWindowController {
    private var statsView: ModernStatsView!

    convenience init() {
        let scale = ModernSkinElements.scaleFactor
        let defaultSize = NSSize(width: 900 * scale, height: 620 * scale)
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.allowedResizeEdges = [.left, .right, .top, .bottom]
        window.titleBarHeight = ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        self.init(window: window)
        setupWindow()
        setupView()
    }

    private func setupWindow() {
        guard let window = window else { return }
        let scale = ModernSkinElements.scaleFactor
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640 * scale, height: 440 * scale)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.delegate = self
    }

    private func setupView() {
        let initialSize = window?.contentLayoutRect.size
            ?? NSSize(width: 900 * ModernSkinElements.scaleFactor,
                      height: 620 * ModernSkinElements.scaleFactor)
        statsView = ModernStatsView(frame: NSRect(origin: .zero, size: initialSize))
        statsView.autoresizingMask = [.width, .height]
        window?.contentView = statsView
    }
}

// MARK: - NSWindowDelegate

extension ModernStatsWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        statsView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        statsView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) {
        statsView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
