import AppKit

final class NetworkMonitorWindowController: NSWindowController, NetworkMonitorWindowProviding {
    private var monitorView: NetworkMonitorView!
    private let monitor = NetworkThroughputMonitor()
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
        tearDownMonitoring()
    }

    private func setupWindow() {
        guard let window else { return }
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = SkinElements.SpectrumWindow.minSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.title = "NullPlayer Network Monitor"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("NetworkMonitorWindow")
        window.setAccessibilityLabel("NullPlayer Network Monitor Window")
    }

    private func setupView() {
        monitorView = NetworkMonitorView(frame: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize))
        monitorView.controller = self
        monitorView.autoresizingMask = [.width, .height]
        monitor.onUpdate = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.monitorView.snapshot = snapshot
                self?.monitorView.interfaces = self?.monitor.availableInterfaces() ?? []
            }
        }
        window?.contentView = monitorView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
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

    func cycleInterface() {
        monitor.cycleInterface()
        monitorView.interfaces = monitor.availableInterfaces()
    }

    func selectInterface(named name: String) {
        monitor.setSelectedInterface(name)
        monitorView.interfaces = monitor.availableInterfaces()
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

extension NetworkMonitorWindowController: NSWindowDelegate {
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
        tearDownMonitoring()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
