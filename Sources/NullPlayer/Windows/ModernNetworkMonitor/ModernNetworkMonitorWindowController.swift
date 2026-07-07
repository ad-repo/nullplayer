import AppKit

final class ModernNetworkMonitorWindowController: NSWindowController, NetworkMonitorWindowProviding {
    private var monitorView: ModernNetworkMonitorView!
    private let monitor = NetworkThroughputMonitor()
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
        tearDownMonitoring()
    }

    private func setupWindow() {
        guard let window else { return }
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = ModernSkinElements.spectrumMinSize
        window.title = "flow"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("ModernNetworkMonitorWindow")
        window.setAccessibilityLabel("NullPlayer Network Monitor Window")
    }

    private func setupView() {
        monitorView = ModernNetworkMonitorView(frame: NSRect(origin: .zero, size: ModernSkinElements.spectrumWindowSize))
        monitorView.controller = self
        monitorView.autoresizingMask = [.width, .height]
        monitor.onUpdate = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.monitorView.snapshot = snapshot
            }
        }
        window?.contentView = monitorView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        monitorView.needsDisplay = true
        startMonitoringForShow()
    }

    func startMonitoringForShow() {
        monitor.start()
        monitorView.interfaces = monitor.availableInterfaces()
    }

    func stopMonitoringForHide() {
        monitor.stop()
    }

    func tearDownMonitoring() {
        stopMonitoringForHide()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
    }

    func skinDidChange() {
        monitorView.skinDidChange()
    }

    /// Refresh the interface list on demand (e.g. just before a context menu opens),
    /// so we avoid the per-tick `getifaddrs`/SCNetwork sweep on the main thread.
    func refreshInterfaces() {
        monitorView.interfaces = monitor.availableInterfaces()
    }

    func cycleInterface() {
        monitor.cycleInterface()
        monitorView.interfaces = monitor.availableInterfaces()
    }

    func selectInterface(named name: String) {
        monitor.setSelectedInterface(name)
        monitorView.interfaces = monitor.availableInterfaces()
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
                self?.syncMonitoringWithVisibility()
            }
        }
    }

    private func syncMonitoringWithVisibility() {
        guard let window else { return }
        if window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) {
            startMonitoringForShow()
        } else {
            stopMonitoringForHide()
        }
    }
}

extension ModernNetworkMonitorWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidResize(_ notification: Notification) {
        monitorView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        monitorView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) {
        monitorView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            WindowManager.shared.handleCenterStackWindowWillClose(window)
        }
        // The controller/window is reused (isReleasedWhenClosed == false), so only stop
        // monitoring here — keep the occlusion/miniaturize observers installed so visibility
        // sync still works after the window is reopened. Observers are torn down in deinit.
        stopMonitoringForHide()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
