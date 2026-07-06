import AppKit

final class PeppyMeterWindowController: NSWindowController, PeppyMeterWindowProviding {
    private var meterView: PeppyMeterView!
    let presenter = PeppyMeterPresenter()
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var localKeyDownMonitor: Any?

    private var isCustomFullscreen = false
    private var preFullscreenFrame: NSRect?
    private var preFullscreenLevel: NSWindow.Level = .normal

    convenience init() {
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: SkinElements.PeppyMeterWindow.windowSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        setupWindow()
        setupView()
        setupKeyDownMonitor()
        installLifecycleObservers()
    }

    deinit {
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
        }
        tearDown()
    }

    private func setupWindow() {
        guard let window else { return }
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = SkinElements.PeppyMeterWindow.minSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.title = "NullPlayer PeppyMeter"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("PeppyMeterWindow")
        window.setAccessibilityLabel("NullPlayer PeppyMeter Window")
    }

    private func setupView() {
        meterView = PeppyMeterView(frame: NSRect(origin: .zero, size: SkinElements.PeppyMeterWindow.windowSize))
        meterView.controller = self
        meterView.autoresizingMask = [.width, .height]
        presenter.onNeedsDisplay = { [weak self] in self?.meterView.needsDisplay = true }
        window?.contentView = meterView
    }

    private func setupKeyDownMonitor() {
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            switch event.keyCode {
            case 53 where self.isCustomFullscreen:
                self.toggleFullscreen()
                return nil
            case 3:
                self.toggleFullscreen()
                return nil
            case 124, 125:
                self.presenter.selectNextMeter()
                return nil
            case 123, 126:
                self.presenter.selectPreviousMeter()
                return nil
            default:
                return event
            }
        }
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

    func toggleFullscreen() {
        guard window != nil else { return }
        if isCustomFullscreen {
            exitCustomFullscreen()
        } else {
            enterCustomFullscreen()
        }
    }

    private func enterCustomFullscreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        preFullscreenFrame = window.frame
        preFullscreenLevel = window.level
        meterView.setFullscreen(true)
        isCustomFullscreen = true
        window.level = .screenSaver
        window.setFrame(screen.frame, display: true, animate: true)
        NSCursor.setHiddenUntilMouseMoves(true)
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        NSLog("PeppyMeterWindowController: Entered custom fullscreen")
    }

    private func exitCustomFullscreen() {
        guard let window else { return }
        isCustomFullscreen = false
        window.level = preFullscreenLevel
        NSApp.presentationOptions = []
        meterView.setFullscreen(false)
        if let frame = preFullscreenFrame {
            window.setFrame(frame, display: true, animate: true)
        }
        preFullscreenFrame = nil
        NSLog("PeppyMeterWindowController: Exited custom fullscreen")
    }

    var isFullscreen: Bool {
        isCustomFullscreen
    }

    func resetToDefaultFrame() {
        guard let window, let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        let scale = WindowManager.shared.classicScaleMultiplier
        let height = SkinElements.PeppyMeterWindow.windowSize.height * scale
        window.minSize = NSSize(
            width: SkinElements.PeppyMeterWindow.minSize.width * scale,
            height: SkinElements.PeppyMeterWindow.minSize.height * scale
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
        if isCustomFullscreen { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidResize(_ notification: Notification) {
        meterView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        meterView.needsDisplay = true
        if !isCustomFullscreen {
            WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        meterView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        if isCustomFullscreen {
            exitCustomFullscreen()
        }
        if let window {
            WindowManager.shared.handleCenterStackWindowWillClose(window)
        }
        tearDown()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
