import AppKit

final class ModernArtWindowController: NSWindowController, ArtWindowProviding {
    private var artWindowView: ModernArtWindowView!

    private var fullscreen = ArtWindowFullscreen()

    convenience init() {
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: ModernSkinElements.spectrumWindowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.allowedResizeEdges = [.bottom, .left, .right]
        window.titleBarHeight = ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        self.init(window: window)
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = ModernSkinElements.spectrumMinSize
        window.title = "NullPlayer Art"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("ModernArtWindow")
        window.setAccessibilityLabel("NullPlayer Art Window")

        artWindowView = ModernArtWindowView(frame: NSRect(origin: .zero, size: ModernSkinElements.spectrumWindowSize))
        artWindowView.controller = self
        artWindowView.autoresizingMask = [.width, .height]
        window.contentView = artWindowView
        window.initialFirstResponder = artWindowView.artView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(artWindowView.artView)
    }

    func tearDown() {
        artWindowView.artView.tearDown()
    }

    func skinDidChange() {
        artWindowView.skinDidChange()
    }

    var isFullscreen: Bool { fullscreen.isActive }

    func toggleFullscreen() {
        guard let window else { return }
        fullscreen.toggle(window) { artWindowView.setFullscreen($0) }
    }
}

extension ModernArtWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window, !isFullscreen else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidResize(_ notification: Notification) {
        artWindowView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        artWindowView.needsDisplay = true
        if !isFullscreen {
            WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        artWindowView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        if isFullscreen { toggleFullscreen() }
        if let window {
            WindowManager.shared.handleCenterStackWindowWillClose(window)
        }
        tearDown()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
