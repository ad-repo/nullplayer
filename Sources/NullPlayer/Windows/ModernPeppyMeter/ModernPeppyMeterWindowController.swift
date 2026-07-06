import AppKit

final class ModernPeppyMeterWindowController: NSWindowController, PeppyMeterWindowProviding {
    private var meterView: ModernPeppyMeterView!
    let presenter = PeppyMeterPresenter()
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
        window.title = "NullPlayer PeppyMeter"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("ModernPeppyMeterWindow")
        window.setAccessibilityLabel("NullPlayer PeppyMeter Window")
    }

    private func setupView() {
        meterView = ModernPeppyMeterView(frame: NSRect(origin: .zero, size: ModernSkinElements.spectrumWindowSize))
        meterView.controller = self
        meterView.autoresizingMask = [.width, .height]
        presenter.onNeedsDisplay = { [weak self] in self?.meterView.needsDisplay = true }
        window?.contentView = meterView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        meterView.needsDisplay = true
        startRenderingForShow()
    }

    func startRenderingForShow() {
        presenter.start()
        meterView.needsDisplay = true
    }

    func stopRenderingForHide() {
        presenter.stop()
    }

    func tearDown() {
        stopRenderingForHide()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
    }

    func skinDidChange() {
        meterView.skinDidChange()
    }

    private func installLifecycleObservers() {
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]
        lifecycleObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
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

extension ModernPeppyMeterWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidResize(_ notification: Notification) {
        meterView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        meterView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) {
        meterView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            WindowManager.shared.handleCenterStackWindowWillClose(window)
        }
        tearDown()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
