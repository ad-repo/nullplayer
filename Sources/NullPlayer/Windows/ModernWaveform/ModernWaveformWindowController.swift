import AppKit

/// Controller for the standalone waveform window (modern skin).
class ModernWaveformWindowController: NSWindowController, WaveformWindowProviding {
    private var waveformView: ModernWaveformView!

    private(set) var isShadeMode = false

    convenience init() {
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: ModernSkinElements.waveformWindowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.allowedResizeEdges = [.bottom, .left, .right]
        window.titleBarHeight = ModernSkinElements.waveformTitleBarHeight
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
        window.minSize = ModernSkinElements.waveformMinSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.center()
        window.delegate = self
        window.acceptsMouseMovedEvents = true
        window.setAccessibilityIdentifier("ModernWaveformWindow")
        window.setAccessibilityLabel("Waveform Window")
    }

    private func setupView() {
        waveformView = ModernWaveformView(frame: NSRect(origin: .zero, size: ModernSkinElements.waveformWindowSize))
        waveformView.waveformController = self
        waveformView.autoresizingMask = [.width, .height]
        window?.contentView = waveformView
    }

    func skinDidChange() {
        waveformView.skinDidChange()
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
}

extension ModernWaveformWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }

    func windowDidResize(_ notification: Notification) {
        waveformView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowWillClose(_ notification: Notification) {
        stopLoadingForHide()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        waveformView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront()
    }

    func windowDidResignKey(_ notification: Notification) {
        waveformView.needsDisplay = true
    }
}
