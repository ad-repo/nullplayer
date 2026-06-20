import AppKit

/// Controller for the standalone Audio Analysis window (modern skin).
/// Conforms to `AudioAnalysisWindowProviding` for WindowManager integration.
///
/// This controller has ZERO dependencies on the classic skin system.
class ModernAudioAnalysisWindowController: NSWindowController, AudioAnalysisWindowProviding {

    // MARK: - Properties

    private var analysisView: ModernAudioAnalysisView!

    private let consumerCoordinator = AudioAnalysisConsumerCoordinator()

    // MARK: - Initialization

    convenience init() {
        let scale = ModernSkinElements.scaleFactor
        // Match the center-stack windows (same width as the main window). WindowManager
        // normalizes the exact frame via applyDefaultCenterStackFrameForCurrentHT on show.
        let defaultSize = ModernSkinElements.spectrumWindowSize

        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.allowedResizeEdges = [.bottom, .left, .right]
        window.titleBarHeight = ModernSkinElements.titleBarBaseHeight * scale

        // Enable fullscreen support
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        self.init(window: window)

        setupWindow()
        setupView()
    }

    // MARK: - Setup

    private func setupWindow() {
        guard let window = window else { return }

        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        // Center-stack minimum; WindowManager.applyCenterStackSizingConstraints refines this on show.
        window.minSize = ModernSkinElements.spectrumMinSize
        window.title = "NullPlayer Audio Analyzer"

        // Prevent window from being released when closed - we reuse the same controller
        window.isReleasedWhenClosed = false

        window.center()
        window.delegate = self

        // Set accessibility identifier
        window.setAccessibilityIdentifier("ModernAudioAnalysisWindow")
        window.setAccessibilityLabel("NullPlayer Audio Analyzer Window")
    }

    private func setupView() {
        analysisView = ModernAudioAnalysisView(frame: NSRect(origin: .zero, size: ModernSkinElements.spectrumWindowSize))
        analysisView.controller = self
        analysisView.autoresizingMask = [.width, .height]
        window?.contentView = analysisView
    }

    // MARK: - Window Display

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        analysisView.needsDisplay = true
        analysisView.setRenderingPaused(false)
        setVisiblePane(analysisView.selectedPane)
        startRendering()
    }

    func stopRenderingForHide() {
        analysisView.setRenderingPaused(true)
        deregisterAllConsumers()
    }

    // MARK: - Public Methods

    func skinDidChange() {
        analysisView.skinDidChange()
    }

    /// Sets the visible pane index and updates consumers accordingly.
    /// Called by the SwiftUI view when the pane selection changes.
    func setVisiblePane(_ index: Int) {
        consumerCoordinator.setVisiblePane(index)
    }

    private func startRendering() {
        // The pane views handle their own rendering (CVDisplayLink, Metal, etc.)
        // This is a placeholder for future rendering coordination if needed
    }

    private func deregisterAllConsumers() {
        consumerCoordinator.deregisterAll()
    }
}

// MARK: - NSWindowDelegate

extension ModernAudioAnalysisWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
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
        setVisiblePane(analysisView.selectedPane)
        analysisView.setRenderingPaused(false)
        startRendering()
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            WindowManager.shared.handleCenterStackWindowWillClose(window)
        }
        stopRenderingForHide()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
