import AppKit

final class PeppyMeterWindowController: NSWindowController, PeppyMeterWindowProviding {
    private var meterView: PeppyMeterView!
    let presenter = PeppyMeterPresenter()
    private var lifecycleObservers: [NSObjectProtocol] = []

    convenience init() {
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
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
        window.minSize = SkinElements.SpectrumWindow.minSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.title = "NullPlayer PeppyMeter"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("PeppyMeterWindow")
        window.setAccessibilityLabel("NullPlayer PeppyMeter Window")
    }

    private func setupView() {
        meterView = PeppyMeterView(frame: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize))
        meterView.controller = self
        meterView.autoresizingMask = [.width, .height]
        presenter.onNeedsDisplay = { [weak self] in self?.meterView.needsDisplay = true }
        window?.contentView = meterView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
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

    func resetToDefaultFrame() {
        guard let window, let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        let scale = WindowManager.shared.classicScaleMultiplier
        let height = SkinElements.SpectrumWindow.windowSize.height * scale
        window.minSize = NSSize(
            width: SkinElements.SpectrumWindow.minSize.width * scale,
            height: SkinElements.SpectrumWindow.minSize.height * scale
        )
        window.setFrame(
            NSRect(x: mainWindow.frame.minX, y: mainWindow.frame.minY - height,
                   width: mainWindow.frame.width, height: height),
            display: false
        )
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

extension PeppyMeterWindowController: NSWindowDelegate {
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
