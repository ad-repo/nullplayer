import AppKit

/// Controller for the standalone waveform window (classic skin).
class WaveformWindowController: NSWindowController, WaveformWindowProviding {
    private var waveformView: WaveformView!

    private(set) var isShadeMode = false

    convenience init() {
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: SkinElements.WaveformWindow.windowSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        setupWindow()
        setupView()
    }

    private func setupWindow() {
        guard let window else { return }
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.title = "NullPlayer Waveform"
        window.isReleasedWhenClosed = false
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            let scale = mainFrame.width / Skin.mainWindowSize.width
            let waveformHeight = SkinElements.WaveformWindow.minSize.height * scale
            window.minSize = NSSize(width: SkinElements.WaveformWindow.minSize.width, height: waveformHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            let newFrame = NSRect(
                x: mainFrame.minX,
                y: mainFrame.minY - waveformHeight,
                width: mainFrame.width,
                height: waveformHeight
            )
            window.setFrame(newFrame, display: true)
        } else {
            window.minSize = SkinElements.WaveformWindow.minSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.center()
        }
        window.delegate = self
        window.setAccessibilityIdentifier("WaveformWindow")
        window.setAccessibilityLabel("Waveform Window")
    }

    private func setupView() {
        waveformView = WaveformView(frame: NSRect(origin: .zero, size: SkinElements.WaveformWindow.windowSize))
        waveformView.waveformController = self
        waveformView.autoresizingMask = [.width, .height]
        window?.contentView = waveformView
    }

    func skinDidChange() {
        waveformView.needsDisplay = true
    }

    func setShadeMode(_ enabled: Bool) {
        isShadeMode = false
    }

    func updateTrack(_ track: Track?) {
        waveformView.updateTrack(track)
    }

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        waveformView.updateTime(current: current, duration: duration)
    }

    func reloadWaveform(force: Bool) {
        waveformView.reloadWaveform(force: force)
    }

    func stopLoadingForHide() {
        waveformView.stopLoadingForHide()
    }

    func resetToDefaultFrame() {
        guard let window, let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        let mainFrame = mainWindow.frame
        let scale = mainFrame.width / Skin.mainWindowSize.width
        let waveformHeight = SkinElements.WaveformWindow.minSize.height * scale
        window.minSize = NSSize(width: SkinElements.WaveformWindow.minSize.width, height: waveformHeight)
        let newFrame = NSRect(x: mainFrame.minX, y: mainFrame.minY - waveformHeight,
                              width: mainFrame.width, height: waveformHeight)
        window.setFrame(newFrame, display: false)
    }
}

extension WaveformWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }

    func windowDidResize(_ notification: Notification) {
        waveformView.needsDisplay = true
        NotificationCenter.default.post(name: .windowLayoutDidChange, object: nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopLoadingForHide()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        waveformView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) {
        waveformView.needsDisplay = true
    }
}
