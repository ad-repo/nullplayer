import AppKit

final class ModernPeppyMeterWindowController: NSWindowController, PeppyMeterWindowProviding {
    private var meterView: ModernPeppyMeterView!
    let presenter = PeppyMeterPresenter()
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var localKeyDownMonitor: Any?

    private var isCustomFullscreen = false
    private var preFullscreenFrame: NSRect?
    private var preFullscreenLevel: NSWindow.Level = .normal

    convenience init() {
        let scale = ModernSkinElements.scaleFactor
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: ModernSkinElements.peppyMeterWindowSize),
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
        window.minSize = ModernSkinElements.peppyMeterMinSize
        window.title = "NullPlayer PeppyMeter"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("ModernPeppyMeterWindow")
        window.setAccessibilityLabel("NullPlayer PeppyMeter Window")
    }

    private func setupView() {
        meterView = ModernPeppyMeterView(frame: NSRect(origin: .zero, size: ModernSkinElements.peppyMeterWindowSize))
        meterView.controller = self
        meterView.autoresizingMask = [.width, .height]
        presenter.onNeedsDisplay = { [weak self] in self?.meterView.requestMeterRedraw() }
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
        WindowManager.shared.withProgrammaticWindowFrameChange(animationDuration: 0.45) {
            window.setFrame(screen.frame, display: true, animate: true)
        }
        NSCursor.setHiddenUntilMouseMoves(true)
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        NSLog("ModernPeppyMeterWindowController: Entered custom fullscreen")
    }

    private func exitCustomFullscreen() {
        guard let window else { return }
        isCustomFullscreen = false
        window.level = preFullscreenLevel
        NSApp.presentationOptions = []
        meterView.setFullscreen(false)
        if let frame = preFullscreenFrame {
            WindowManager.shared.withProgrammaticWindowFrameChange(animationDuration: 0.45) {
                window.setFrame(frame, display: true, animate: true)
            }
        }
        preFullscreenFrame = nil
        NSLog("ModernPeppyMeterWindowController: Exited custom fullscreen")
    }

    var isFullscreen: Bool {
        isCustomFullscreen
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
