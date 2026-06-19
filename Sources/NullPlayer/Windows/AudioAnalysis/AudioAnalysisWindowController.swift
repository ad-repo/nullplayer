import AppKit

/// Controller for the shared Audio Analysis panes in classic UI mode.
final class AudioAnalysisWindowController: NSWindowController, AudioAnalysisWindowProviding {
    private var analysisView: AudioAnalysisView!
    private let consumerCoordinator = AudioAnalysisConsumerCoordinator()

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
    }

    private func setupWindow() {
        guard let window else { return }
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = SkinElements.SpectrumWindow.minSize
        window.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        window.title = "NullPlayer Audio Analysis"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("AudioAnalysisWindow")
        window.setAccessibilityLabel("NullPlayer Audio Analysis Window")
    }

    private func setupView() {
        analysisView = AudioAnalysisView(frame: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize))
        analysisView.controller = self
        analysisView.autoresizingMask = [.width, .height]
        window?.contentView = analysisView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        analysisView.setRenderingPaused(false)
        setVisiblePane(analysisView.selectedPane)
    }

    func stopRenderingForHide() {
        analysisView.setRenderingPaused(true)
        consumerCoordinator.deregisterAll()
    }

    func skinDidChange() {
        analysisView.skinDidChange()
    }

    func setVisiblePane(_ index: Int) {
        consumerCoordinator.setVisiblePane(index)
    }

    func resetToDefaultFrame() {
        guard let window, let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        let scale = WindowManager.shared.classicScaleMultiplier
        let height = SkinElements.SpectrumWindow.windowSize.height * scale
        window.minSize = NSSize(
            width: SkinElements.SpectrumWindow.minSize.width,
            height: SkinElements.SpectrumWindow.minSize.height * scale
        )
        window.setFrame(
            NSRect(x: mainWindow.frame.minX, y: mainWindow.frame.minY - height,
                   width: mainWindow.frame.width, height: height),
            display: false
        )
    }
}

extension AudioAnalysisWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidResize(_ notification: Notification) {
        analysisView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        analysisView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) {
        analysisView.needsDisplay = true
    }

    func windowDidMiniaturize(_ notification: Notification) {
        stopRenderingForHide()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        analysisView.setRenderingPaused(false)
        setVisiblePane(analysisView.selectedPane)
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            WindowManager.shared.handleCenterStackWindowWillClose(window)
        }
        stopRenderingForHide()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
