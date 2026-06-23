import AppKit

private protocol CompactModeBrowserSurface: AnyObject {
    var window: NSWindow? { get }
    var isShadeMode: Bool { get }
    var minimumCompactContentWidth: CGFloat { get }

    func setCompactMode(_ enabled: Bool)
    func updateCompactBarTime(current: TimeInterval, duration: TimeInterval)
    func updateCompactBarTrack(_ track: Track?)
    func updateCompactBarPlaybackState()
    func prepareForUITeardown()
}

extension PlexBrowserWindowController: CompactModeBrowserSurface {}
extension ModernLibraryBrowserWindowController: CompactModeBrowserSurface {}

final class CompactModeWindowController: NSWindowController {

    private let browserController: CompactModeBrowserSurface
    private let modernUI: Bool
    private var needsInitialSizing = true
    private var revealWorkItem: DispatchWorkItem?

    private let retryInterval: TimeInterval = 0.02       // ~1–2 AppKit layout passes per tick
    private let maxRetryAttempts = 15                    // ~0.3s budget for status-item layout
    private let statusAnchorReadyThreshold: CGFloat = 40 // menu bar ≈ 24–28pt + jitter

    private var compactBaseWidth: CGFloat {
        browserController.minimumCompactContentWidth
    }

    init(modernUI: Bool) {
        self.modernUI = modernUI
        if modernUI {
            browserController = ModernLibraryBrowserWindowController()
        } else {
            browserController = PlexBrowserWindowController()
        }
        super.init(window: browserController.window)
        setupWindow()
        browserController.setCompactMode(true)
        seedFromAudioEngine()
    }

    required init?(coder: NSCoder) {
        modernUI = WindowManager.shared.isRunningModernUI
        if modernUI {
            browserController = ModernLibraryBrowserWindowController()
        } else {
            browserController = PlexBrowserWindowController()
        }
        super.init(coder: coder)
        window = browserController.window
        setupWindow()
        browserController.setCompactMode(true)
        seedFromAudioEngine()
    }

    deinit {
        browserController.prepareForUITeardown()
    }

    private func setupWindow() {
        guard let window else { return }
        window.level = .statusBar
        window.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.hasShadow = true
        window.title = "Compact Mode"
        window.setAccessibilityIdentifier("CompactModeWindow")
        window.setAccessibilityLabel("Compact Mode")
        window.minSize = NSSize(width: compactBaseWidth, height: window.minSize.height)
        window.alphaValue = 0
        position(anchoredTo: nil, display: false)
        window.orderOut(nil)
    }

    func seedFromAudioEngine() {
        let engine = WindowManager.shared.audioEngine
        browserController.updateCompactBarTrack(engine.currentTrack)
        browserController.updateCompactBarTime(current: engine.currentTime, duration: engine.duration)
        browserController.updateCompactBarPlaybackState()
    }

    func show(anchoredTo button: NSStatusBarButton?) {
        guard let window else { return }
        revealWorkItem?.cancel()

        window.level = .statusBar
        window.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]

        let wasVisible = window.isVisible && window.alphaValue > 0
        if wasVisible {
            // Already on screen: reposition immediately and stay visible — no flash possible.
            position(anchoredTo: button, display: true)
            window.orderFrontRegardless()
            window.makeKey()
            window.hasShadow = true
            window.alphaValue = 1
            return
        }

        // Not yet visible: keep the window invisible (alpha 0) at the best-known position
        // until the status-item anchor has laid out, then position and reveal exactly once
        // at the correct top-right corner. Ordering front at alpha 0 keeps it invisible while
        // letting the retry closure detect a mid-flight hide() via window.isVisible.
        window.alphaValue = 0
        window.hasShadow = false
        position(anchoredTo: button, display: false)
        window.orderFrontRegardless()
        scheduleReveal(anchoredTo: button, attempt: 0)
    }

    private func scheduleReveal(anchoredTo button: NSStatusBarButton?, attempt: Int) {
        let reveal = DispatchWorkItem { [weak self, weak button] in
            guard let self, let window = self.window, window.isVisible else { return }
            guard self.isStatusAnchorReady(button) || attempt >= self.maxRetryAttempts else {
                self.scheduleReveal(anchoredTo: button, attempt: attempt + 1)
                return
            }
            // Reveal unconditionally once the anchor is ready or the cap is hit. On cap
            // exhaustion position() degrades to the top-right fallback; never leave the
            // window stuck at alpha 0 — an invisible compact window is worse than a flash.
            self.position(anchoredTo: button, display: false)
            window.displayIfNeeded()
            window.hasShadow = true
            window.alphaValue = 1
            window.makeKey()
        }
        revealWorkItem = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + retryInterval, execute: reveal)
    }

    private func isStatusAnchorReady(_ button: NSStatusBarButton?) -> Bool {
        guard let button, let buttonWindow = button.window else { return false }
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let screen = buttonWindow.screen
            ?? NSScreen.screens.first { $0.frame.contains(buttonScreenRect.origin) }
            ?? NSScreen.main
        guard let screen else { return false }
        // The only reliable readiness signal is menu-bar proximity: NSStatusBar creates the
        // button's window eagerly (so button.window/.screen are non-nil before layout), but a
        // not-yet-laid-out item sits near the origin. Compare against screen.frame.maxY (the
        // menu-bar edge), not visibleFrame.maxY which excludes the menu bar.
        return abs(buttonScreenRect.maxY - screen.frame.maxY) < statusAnchorReadyThreshold
    }

    func hide() {
        revealWorkItem?.cancel()
        window?.alphaValue = 0
        window?.orderOut(nil)
    }

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        browserController.updateCompactBarTime(current: current, duration: duration)
    }

    func updateTrack(_ track: Track?) {
        browserController.updateCompactBarTrack(track)
    }

    func updatePlaybackState() {
        browserController.updateCompactBarPlaybackState()
    }

    private func position(anchoredTo button: NSStatusBarButton?, display: Bool = true) {
        guard let window else { return }

        let gap: CGFloat = 0
        let margin: CGFloat = 8
        let visibleFrame: NSRect
        let topY: CGFloat
        let centerX: CGFloat
        let hasStatusAnchor: Bool

        if let button, isStatusAnchorReady(button), let buttonWindow = button.window {
            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            let buttonScreenRect = buttonWindow.convertToScreen(buttonRectInWindow)
            let screen = buttonWindow.screen
                ?? NSScreen.screens.first { $0.frame.contains(buttonScreenRect.origin) }
                ?? NSScreen.main
            visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            topY = visibleFrame.maxY - gap
            centerX = buttonScreenRect.midX
            hasStatusAnchor = true
        } else {
            let screen = NSScreen.main
            visibleFrame = screen?.visibleFrame ?? .zero
            topY = visibleFrame.maxY - gap
            centerX = visibleFrame.midX
            hasStatusAnchor = false
        }
        guard visibleFrame != .zero else { return }

        let minimumWidth = compactBaseWidth
        let minimumHeight = window.minSize.height
        let availableHeight = max(minimumHeight, topY - visibleFrame.minY - margin)

        var frame = window.frame
        if needsInitialSizing {
            frame.size.width = min(minimumWidth, visibleFrame.width - margin * 2)
            frame.size.height = min(minimumHeight, availableHeight)
            needsInitialSizing = false
        } else {
            frame.size.width = max(frame.width, minimumWidth)
            frame.size.height = min(frame.height, availableHeight)
        }

        frame.origin.x = hasStatusAnchor ? centerX - frame.width / 2 : visibleFrame.maxX - frame.width - margin
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX + margin), visibleFrame.maxX - frame.width - margin)
        frame.origin.y = topY - frame.height
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + margin), visibleFrame.maxY - frame.height)

        window.setFrame(frame, display: display, animate: false)
    }
}
