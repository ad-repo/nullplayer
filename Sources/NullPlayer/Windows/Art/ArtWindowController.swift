import AppKit

final class ArtWindowController: NSWindowController, ArtWindowProviding {
    private var artWindowView: ArtWindowView!

    private var fullscreen = ArtWindowFullscreen()

    convenience init() {
        let window = ResizableWindow(contentRect: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize))
        self.init(window: window)
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = SkinElements.SpectrumWindow.minSize
        window.title = "NullPlayer Art"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("ArtWindow")
        window.setAccessibilityLabel("NullPlayer Art Window")

        artWindowView = ArtWindowView(frame: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize))
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

    func resetToDefaultFrame() {
        guard let window, let mainWindow = WindowManager.shared.mainWindowController?.window,
              let size = WindowManager.shared.nativeWindowDefaultSize(for: window) else { return }
        let scale = WindowManager.shared.classicScaleMultiplier
        window.minSize = NSSize(width: SkinElements.SpectrumWindow.minSize.width * scale,
                                height: SkinElements.SpectrumWindow.minSize.height * scale)
        window.setFrame(NSRect(x: mainWindow.frame.minX, y: mainWindow.frame.minY - size.height,
                               width: size.width, height: size.height),
                        display: false)
    }
}

extension ArtWindowController: NSWindowDelegate {
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
