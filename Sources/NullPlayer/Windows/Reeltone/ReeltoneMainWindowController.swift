import AppKit

/// Phase-1 Reeltone main-window shell.
///
/// Reeltone owns a distinct controller from the first phase, while temporarily hosting the
/// standard Original main content until manifest-driven surfaces arrive.
final class ReeltoneMainWindowController: NSWindowController, MainWindowProviding {
    private var content: ModernMainWindowView!

    convenience init() {
        ReeltonePlaceholderRuntime.prepare()

        let size = ModernSkinElements.mainWindowSize
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        configureWindow(size: size)
        configureContent(size: size)
    }

    private func configureWindow(size: NSSize) {
        guard let window else { return }
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .normal
        window.title = "NullPlayer — Reeltone"
        window.minSize = size
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("ReeltoneMainWindow")
        window.setAccessibilityLabel("Reeltone Main Window")
    }

    private func configureContent(size: NSSize) {
        content = ModernMainWindowView(frame: NSRect(origin: .zero, size: size))
        window?.contentView = content
    }

    func updatePlaybackState() { content.needsDisplay = true }
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        content.updateTime(current: current, duration: duration)
    }
    func updateTrackInfo(_ track: Track?) { content.updateTrackInfo(track) }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {
        content.updateVideoTrackInfo(title: title, artworkTrack: artworkTrack)
    }
    func clearVideoTrackInfo() { content.clearVideoTrackInfo() }
    func updateSpectrum(_ levels: [Float]) { content.updateSpectrum(levels) }
    func skinDidChange() {
        content.skinDidChange()
        content.needsDisplay = true
    }
    func windowVisibilityDidChange() { content.windowVisibilityDidChange() }
    func setNeedsDisplay() { content.needsDisplay = true }
}

extension ReeltoneMainWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }

    func windowWillMiniaturize(_ notification: Notification) {
        guard let window else { return }
        WindowManager.shared.attachDockedWindowsForMiniaturize(mainWindow: window)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window else { return }
        WindowManager.shared.detachDockedWindowsAfterDeminiaturize(mainWindow: window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }
}
