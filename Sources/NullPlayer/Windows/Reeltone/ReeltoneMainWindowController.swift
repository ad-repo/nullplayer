import AppKit

/// Main-window owner for both the fixed v1 deck and manifest-driven v2 surfaces.
final class ReeltoneMainWindowController: NSWindowController, MainWindowProviding, ReeltoneSurfaceProviding {
    private var fallbackContent: ModernMainWindowView?
    private var coordinator: ReeltoneSurfaceCoordinator?
    private var skinObserver: NSObjectProtocol?
    private var currentTrack: Track?
    private var currentTime: TimeInterval = 0
    private var currentDuration: TimeInterval = 0
    private var currentSpectrum: [Float] = []

    convenience init() {
        let scale = WindowManager.shared.uiScaleLevel.scaleFactor
        let size = Self.preferredSize(scale: scale)
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        configureWindow(size: size)
        configurePresentation(scale: scale, preservingTopLeft: false)
        skinObserver = NotificationCenter.default.addObserver(
            forName: .reeltoneSkinDidChange,
            object: ReeltoneSkinEngine.shared,
            queue: .main
        ) { [weak self] _ in
            self?.configurePresentation(
                scale: WindowManager.shared.uiScaleLevel.scaleFactor,
                preservingTopLeft: true
            )
        }
    }

    deinit {
        if let skinObserver { NotificationCenter.default.removeObserver(skinObserver) }
        coordinator?.prepareForTeardown()
    }

    private static func preferredSize(scale: CGFloat) -> NSSize {
        if let skin = ReeltoneSkinEngine.shared.currentSkin,
           let inventory = ReeltoneSurfaceInventory(manifest: skin.manifest) {
            return NSSize(width: inventory.main.authoredSize.width * scale, height: inventory.main.authoredSize.height * scale)
        }
        return ModernSkinElements.mainWindowSize
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
        window.maxSize = size
        window.center()
        window.delegate = self
        window.setAccessibilityIdentifier("ReeltoneMainWindow")
        window.setAccessibilityLabel("Reeltone Main Window")
    }

    private func configurePresentation(scale: CGFloat, preservingTopLeft: Bool) {
        guard let window else { return }
        coordinator?.prepareForTeardown()
        coordinator = nil
        fallbackContent?.removeFromSuperview()
        fallbackContent = nil

        if let skin = ReeltoneSkinEngine.shared.currentSkin,
           let inventory = ReeltoneSurfaceInventory(manifest: skin.manifest) {
            WindowManager.shared.reconcileReeltoneHostedFallbacks(with: inventory)
            resizeMain(
                to: NSSize(width: inventory.main.authoredSize.width * scale, height: inventory.main.authoredSize.height * scale),
                preservingTopLeft: preservingTopLeft
            )
            let identity = ReeltoneSkinEngine.shared.currentSkinIdentity ?? "manifest:\(skin.manifest.id)"
            let coordinator = ReeltoneSurfaceCoordinator(
                mainWindow: window,
                skin: skin,
                inventory: inventory,
                scale: scale,
                identity: identity
            )
            self.coordinator = coordinator
            coordinator.updateTrack(currentTrack)
            coordinator.updateTime(current: currentTime, duration: currentDuration)
            coordinator.updateSpectrum(currentSpectrum)
            coordinator.updatePlaybackState()
            if window.isVisible {
                coordinator.showInitialPanels()
                coordinator.mainVisibilityDidChange(true)
            }
        } else {
            let size = ModernSkinElements.mainWindowSize
            resizeMain(to: size, preservingTopLeft: preservingTopLeft)
            let content = ModernMainWindowView(
                frame: NSRect(origin: .zero, size: size),
                preferences: ReeltoneDefaults.shared
            )
            content.autoresizingMask = [.width, .height]
            window.contentView = content
            fallbackContent = content
        }
    }

    private func resizeMain(to size: NSSize, preservingTopLeft: Bool) {
        guard let window else { return }
        var frame = window.frame
        let top = frame.maxY
        frame.size = size
        if preservingTopLeft { frame.origin.y = top - size.height }
        window.minSize = size
        window.maxSize = size
        window.setFrame(frame, display: true)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        coordinator?.showInitialPanels()
        coordinator?.mainVisibilityDidChange(true)
    }

    func updatePlaybackState() {
        fallbackContent?.needsDisplay = true
        coordinator?.updatePlaybackState()
    }

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        currentTime = current
        currentDuration = duration
        fallbackContent?.updateTime(current: current, duration: duration)
        coordinator?.updateTime(current: current, duration: duration)
    }

    func updateTrackInfo(_ track: Track?) {
        currentTrack = track
        fallbackContent?.updateTrackInfo(track)
        coordinator?.updateTrack(track)
    }

    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {
        fallbackContent?.updateVideoTrackInfo(title: title, artworkTrack: artworkTrack)
        coordinator?.updateTrack(artworkTrack)
    }

    func clearVideoTrackInfo() {
        fallbackContent?.clearVideoTrackInfo()
        coordinator?.updateTrack(currentTrack)
    }

    func updateSpectrum(_ levels: [Float]) {
        currentSpectrum = levels
        fallbackContent?.updateSpectrum(levels)
        coordinator?.updateSpectrum(levels)
    }

    func skinDidChange() {
        fallbackContent?.skinDidChange()
        coordinator?.updateTheme()
    }

    func windowVisibilityDidChange() {
        fallbackContent?.windowVisibilityDidChange()
        coordinator?.mainVisibilityDidChange(window?.isVisible == true)
    }

    func setNeedsDisplay() {
        window?.contentView?.needsDisplay = true
        coordinator?.updateTheme()
    }

    func prepareForUITeardown() {
        coordinator?.prepareForTeardown()
    }

    var reeltoneWindows: [NSWindow] { coordinator?.allWindows ?? [window].compactMap { $0 } }
    var reeltonePanelMenuEntries: [ReeltonePanelMenuEntry] { coordinator?.panelMenuEntries ?? [] }
    func applyReeltoneScale(_ scale: CGFloat) { coordinator?.applyScale(scale) }
    func routeReeltoneComponent(_ component: ReeltoneComponent) -> Bool { coordinator?.route(component: component) ?? false }
    func setReeltoneAlwaysOnTop(_ enabled: Bool) { coordinator?.setAlwaysOnTop(enabled) }
    func toggleReeltonePanel(_ name: String) { coordinator?.togglePanel(name) }
    func captureReeltoneSurfaceLayout() -> ReeltoneSurfaceLayoutSnapshot? { coordinator?.captureLayout() }
    func restoreReeltoneSurfaceLayout(_ snapshot: ReeltoneSurfaceLayoutSnapshot) { coordinator?.restoreLayout(snapshot) }
}

extension ReeltoneMainWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
        coordinator?.mainWindowDidMove()
    }

    func windowWillMiniaturize(_ notification: Notification) {
        coordinator?.miniaturizeVisiblePanels()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        coordinator?.restoreVisiblePanelsAfterMiniaturize()
        refreshEffectiveVisibility()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { refreshEffectiveVisibility() }

    func windowDidBecomeKey(_ notification: Notification) {
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowWillClose(_ notification: Notification) { coordinator?.mainVisibilityDidChange(false) }

    private func refreshEffectiveVisibility() {
        guard let window else { coordinator?.mainVisibilityDidChange(false); return }
        coordinator?.mainVisibilityDidChange(
            window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        )
    }
}
