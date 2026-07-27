import AppKit

final class ModernCavaWindowController: NSWindowController, CavaWindowProviding {
    private var cavaView: ModernCavaView!
    private var lifecycleObservers: [NSObjectProtocol] = []

    convenience init() {
        let scale = ModernSkinElements.scaleFactor
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: ModernSkinElements.spectrumWindowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.allowedResizeEdges = [.bottom, .left, .right]
        window.titleBarHeight = ModernSkinElements.titleBarBaseHeight * scale
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        self.init(window: window)
        setupWindow()
        setupView()
        installLifecycleObservers()
    }

    deinit {
        tearDown()
    }

    private func setupWindow() {
        guard let window else { return }
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = ModernSkinElements.spectrumMinSize
        window.title = "cava"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("ModernCavaWindow")
        window.setAccessibilityLabel("NullPlayer Cava Spectrum Analyzer")
    }

    private func setupView() {
        cavaView = ModernCavaView(frame: NSRect(origin: .zero, size: ModernSkinElements.spectrumWindowSize))
        cavaView.controller = self
        cavaView.autoresizingMask = [.width, .height]
        window?.contentView = cavaView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        cavaView.needsDisplay = true
        startRenderingForShow()
    }

    func startRenderingForShow() {
        cavaView.startRendering()
    }

    func stopRenderingForHide() {
        cavaView.stopRendering()
    }

    func skinDidChange() {
        cavaView.skinDidChange()
    }

    func tearDown() {
        stopRenderingForHide()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
    }

    private func installLifecycleObservers() {
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]
        lifecycleObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.syncRenderingWithVisibility()
            }
        }
    }

    private func syncRenderingWithVisibility() {
        guard let window else { return }
        if window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) {
            startRenderingForShow()
        } else {
            stopRenderingForHide()
        }
    }
}

extension ModernCavaWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidResize(_ notification: Notification) {
        cavaView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        cavaView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) {
        cavaView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            WindowManager.shared.handleCenterStackWindowWillClose(window)
        }
        stopRenderingForHide()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
