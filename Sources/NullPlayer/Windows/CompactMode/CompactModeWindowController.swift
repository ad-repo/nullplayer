import AppKit

private protocol CompactModeBrowserSurface: AnyObject {
    var window: NSWindow? { get }
    var minimumCompactContentWidth: CGFloat { get }

    func setCompactMode(_ enabled: Bool)
    func updateCompactBarTime(current: TimeInterval, duration: TimeInterval)
    func updateCompactBarTrack(_ track: Track?)
    func updateCompactBarPlaybackState()
    func skinDidChange()
    func prepareForUITeardown()
}

extension PlexBrowserWindowController: CompactModeBrowserSurface {}
extension ModernLibraryBrowserWindowController: CompactModeBrowserSurface {}

final class CompactModeWindowController: NSWindowController {

    private let browserController: CompactModeBrowserSurface
    private var needsInitialSizing = true
    private var isFloatingMode = false
    private var hasAppliedFloatingFrame = false

    /// Observer for status-item window move notifications (initial reveal + display-reconfig).
    private var statusButtonWindowMoveObserver: NSObjectProtocol?
    /// Observer for status-item window resize notifications (initial reveal + display-reconfig).
    private var statusButtonWindowResizeObserver: NSObjectProtocol?
    /// Whether the compact window has already been revealed at the anchored position.
    private var hasRevealed = false
    /// Observer for display-configuration changes (added/removed screens, resolution changes).
    private var displayConfigObserver: NSObjectProtocol?
    /// The status-item button the window is anchored to. Held weakly so a display-reconfig
    /// can re-anchor without WindowManager threading the button back through. Cleared on hide().
    private weak var anchorButton: NSStatusBarButton?

    /// DEBUG timer to detect if the anchor never resolves. Fires a loud diagnostic in dev builds.
    private var anchorDiagnosticTimer: Timer?

    private let statusAnchorReadyThreshold: CGFloat = 40 // menu bar ≈ 24–28pt + jitter
    /// How far inside a screen horizontal edge the status item must sit to count as laid out.
    /// A mid-flight item is reported flush at a corner; a settled one sits well inside.
    private let statusItemEdgeInset: CGFloat = 8

    // Render the compact window ~1/5 narrower than the browser's label-fit minimum.
    private let compactWidthFactor: CGFloat = 0.8

    private var compactBaseWidth: CGFloat {
        browserController.minimumCompactContentWidth * compactWidthFactor
    }

    private static let floatingFrameKey = "compactWindowFrame"

    init(modernUI: Bool) {
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
        let modernUI = WindowManager.shared.isRunningModernUI
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
        NotificationCenter.default.removeObserver(self)
        persistFloatingFrameIfNeeded()
        stopObservingStatusButtonFrame()
        stopObservingDisplayConfig()
        anchorDiagnosticTimer?.invalidate()
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

        // The compact window floats at `.statusBar` level (above `.modalPanel`), so dialogs
        // such as the Add Folder / Add YouTube Channel panels would open *behind* it. Drop
        // below modal level whenever one of our own windows takes key focus, and restore the
        // floating level when the compact window itself regains key. Keyed-by-our-windows
        // only, so switching to another app doesn't sink the window.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    @objc private func handleWindowDidBecomeKey(_ note: Notification) {
        guard !isFloatingMode else { return }
        guard let window, window.isVisible else { return }
        guard let keyWindow = note.object as? NSWindow else { return }
        // A dialog/panel from our app took key — let it sit above the floating compact window.
        window.level = (keyWindow === window) ? .statusBar : .normal
    }

    /// Drop the compact window below normal window level so a just-shown video player window
    /// (which floats at `.normal`/`.floating`, lower than the compact window's `.statusBar`)
    /// can sit in front of it. Ordering a window front never crosses level bands, so without
    /// this the video would launch *behind* the floating mini-player. The compact window
    /// returns to its floating level the next time it becomes key (see handleWindowDidBecomeKey).
    func yieldFrontForVideoPlayer() {
        guard !isFloatingMode else { return }
        window?.level = .normal
    }

    /// Restore the compact window's floating level after the video player goes away. Without this
    /// the mini-player stays sunk at `.normal` (and can be covered by other apps' windows) until the
    /// user happens to click it. Called when video playback stops/closes so always-on-top behavior
    /// returns automatically.
    func restoreFloatingLevelAfterVideoPlayer() {
        guard !isFloatingMode else { return }
        window?.level = .statusBar
    }

    func seedFromAudioEngine() {
        let engine = WindowManager.shared.audioEngine
        browserController.updateCompactBarTrack(engine.currentTrack)
        browserController.updateCompactBarTime(current: engine.currentTime, duration: engine.duration)
        browserController.updateCompactBarPlaybackState()
    }

    func skinDidChange() {
        browserController.skinDidChange()
        if let contentView = window?.contentView {
            contentView.markSubtreeForDisplayAndLayout()
            contentView.layoutSubtreeIfNeeded()
            contentView.displayIfNeeded()
        }
        window?.displayIfNeeded()
    }

    /// Order the compact window front on the *current* Space while still invisible (alpha 0),
    /// without revealing or repositioning it. Called at Compact-Mode entry **before** the regular
    /// windows are hidden and the app drops to `.accessory`, so NullPlayer always has a window on
    /// the user's current Space for the entry path's `NSApp.activate(ignoringOtherApps:)` to focus.
    /// Without this, re-activation after `.accessory` has no current-Space window to land on. The
    /// real fade-in/positioning still happens later in `show`.
    func establishPresenceOnActiveSpace() {
        guard let window else { return }
        isFloatingMode = false
        window.alphaValue = 0
        window.hasShadow = false
        window.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        window.orderFrontRegardless()
        window.makeKey()
    }

    func show(anchoredTo button: NSStatusBarButton?) {
        guard let window else { return }
        isFloatingMode = false
        stopObservingStatusButtonFrame()
        anchorDiagnosticTimer?.invalidate()

        window.level = .statusBar
        window.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        window.title = "Compact Mode"
        window.setAccessibilityLabel("Compact Mode")

        let wasVisible = window.isVisible && window.alphaValue > 0
        if wasVisible {
            // Already on screen: reposition immediately and stay visible — no flash possible.
            anchorButton = button
            position(anchoredTo: button, display: true)
            window.orderFrontRegardless()
            window.makeKey()
            window.hasShadow = true
            window.alphaValue = 1
            return
        }

        // Not yet visible: keep the window invisible (alpha 0) until the status-item anchor
        // has laid out, then position and reveal exactly once at the correct position under
        // the menubar icon. Ordering front at alpha 0 keeps it invisible while observers
        // detect the anchor readiness. Observers fire when the status-item window moves or
        // resizes (AppKit layout signals), or when display config changes.
        window.alphaValue = 0
        window.hasShadow = false
        window.orderFrontRegardless()

        // Reset reveal state and start observing. Register observers *before* the sync check
        // so we don't miss a move that happens between the check and registration.
        hasRevealed = false
        anchorButton = button
        startObservingStatusButtonFrame(button: button)
        startObservingDisplayConfig()
        startAnchorDiagnosticTimer()

        // Sync check: if the anchor is already ready by the time we run, reveal immediately.
        if isStatusAnchorReady(button) {
            revealNow(anchoredTo: button)
        }
    }

    func showFloating(level: NSWindow.Level = .normal) {
        guard let window else { return }
        isFloatingMode = true
        hasRevealed = true
        anchorButton = nil
        stopObservingStatusButtonFrame()
        stopObservingDisplayConfig()
        anchorDiagnosticTimer?.invalidate()
        anchorDiagnosticTimer = nil

        window.level = level
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.title = "Compact Window"
        window.setAccessibilityLabel("Compact Window")

        if !hasAppliedFloatingFrame {
            let savedFrame = Self.savedFloatingFrame()
            var shouldCenter = savedFrame == nil
            var frame = savedFrame ?? window.frame
            if savedFrame == nil {
                frame.size.width = compactBaseWidth
            }
            frame.size.width = max(frame.width, compactBaseWidth)
            frame.size.height = max(frame.height, window.minSize.height)
            if savedFrame != nil {
                if let visibleFrame = Self.visibleFloatingFrame(for: frame) {
                    frame = visibleFrame
                } else {
                    shouldCenter = true
                }
            }
            window.setFrame(frame, display: false, animate: false)
            if shouldCenter {
                window.center()
            }
            hasAppliedFloatingFrame = true
        } else {
            var frame = window.frame
            frame.size.width = max(frame.width, compactBaseWidth)
            frame.size.height = max(frame.height, window.minSize.height)
            window.setFrame(frame, display: false, animate: false)
        }

        window.alphaValue = 1
        window.hasShadow = true
        window.orderFront(nil)
        window.makeKey()
    }

    /// Start observing the status-item window's move and resize notifications to detect
    /// when the anchor has laid out. These drive the initial reveal only; once revealed,
    /// handleStatusButtonWindowFrameChange ignores them so an incidental menu-bar relayout
    /// can't snap a user-moved window back under the icon. Re-anchoring after that point is
    /// handled exclusively by the display-config observer.
    private func startObservingStatusButtonFrame(button: NSStatusBarButton?) {
        guard let button, let buttonWindow = button.window else { return }
        stopObservingStatusButtonFrame()

        let nc = NotificationCenter.default
        statusButtonWindowMoveObserver = nc.addObserver(
            forName: NSWindow.didMoveNotification,
            object: buttonWindow,
            queue: .main
        ) { [weak self, weak button] _ in
            self?.handleStatusButtonWindowFrameChange(button: button)
        }

        statusButtonWindowResizeObserver = nc.addObserver(
            forName: NSWindow.didResizeNotification,
            object: buttonWindow,
            queue: .main
        ) { [weak self, weak button] _ in
            self?.handleStatusButtonWindowFrameChange(button: button)
        }
    }

    /// Stop observing the status-item window's frame changes.
    private func stopObservingStatusButtonFrame() {
        let nc = NotificationCenter.default
        if let observer = statusButtonWindowMoveObserver {
            nc.removeObserver(observer)
            statusButtonWindowMoveObserver = nil
        }
        if let observer = statusButtonWindowResizeObserver {
            nc.removeObserver(observer)
            statusButtonWindowResizeObserver = nil
        }
    }

    /// Handle a status-item window move or resize. Check if the anchor is ready and
    /// reveal if so (initial reveal only — after reveal, this does nothing).
    private func handleStatusButtonWindowFrameChange(button: NSStatusBarButton?) {
        guard !hasRevealed else { return }
        if isStatusAnchorReady(button) {
            revealNow(anchoredTo: button)
        }
    }

    /// Reveal the compact window at the anchored position, exactly once.
    private func revealNow(anchoredTo button: NSStatusBarButton?) {
        guard let window, !hasRevealed else { return }
        hasRevealed = true
        anchorDiagnosticTimer?.invalidate()
        anchorDiagnosticTimer = nil

        position(anchoredTo: button, display: false)
        window.displayIfNeeded()
        window.hasShadow = true
        window.alphaValue = 1
        window.makeKey()
    }

    /// Start observing display-configuration changes (added/removed screens, resolution changes).
    /// Used for re-anchoring after screen geometry changes.
    private func startObservingDisplayConfig() {
        stopObservingDisplayConfig()
        let nc = NotificationCenter.default
        displayConfigObserver = nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayConfigChange()
        }
    }

    /// Stop observing display-configuration changes.
    private func stopObservingDisplayConfig() {
        if let observer = displayConfigObserver {
            NotificationCenter.default.removeObserver(observer)
            displayConfigObserver = nil
        }
    }

    /// Handle a display-configuration change. Re-anchor a revealed window back under the
    /// status-item icon — display reconfig (screens added/removed, resolution change) can
    /// otherwise leave the window off-screen or against a stale screen edge. This is one of
    /// the two sanctioned re-anchor triggers (the other being the initial reveal); incidental
    /// status-button moves after reveal are deliberately ignored (see handleStatusButtonWindowFrameChange).
    private func handleDisplayConfigChange() {
        guard let window, window.isVisible, window.alphaValue > 0 else { return }
        guard let button = anchorButton, isStatusAnchorReady(button) else { return }
        position(anchoredTo: button, display: true)
    }

    /// Start a diagnostic timer to detect if the anchor never resolves. After a generous
    /// deadline (~2–3s) with no successful reveal, log loudly in *all* builds and additionally
    /// assert in DEBUG.
    ///
    /// This is the only release-safe trigger for the rare dead-end where the window stays at
    /// alpha 0 forever: if `button`/`button.window` is nil at `show()` time (status-item
    /// creation/layout churn), the frame observers never attach and `isStatusAnchorReady` can
    /// never become true, so nothing else would ever reveal — or report — the stuck window.
    /// We deliberately do **not** reveal at a guessed position here: "no fallback placement" is
    /// the design (a guessed spot is what jammed the window against the right edge through PRs
    /// #306/#307 — see the ui-guide skill). The log makes the rare case visible in release logs
    /// instead of silently stranding the app in an invisible compact window.
    private func startAnchorDiagnosticTimer() {
        anchorDiagnosticTimer?.invalidate()
        anchorDiagnosticTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self, !self.hasRevealed else { return }
            NSLog("CompactMode: anchor never resolved after 2.5s — status-item may not have posted a move/resize notification (or button.window was nil at show()); compact window stays invisible.")
            #if DEBUG
            assertionFailure(
                "Compact window anchor never resolved after 2.5s. Status-item may not have posted move/resize notification. Check logs."
            )
            #endif
        }
    }

    private func isStatusAnchorReady(_ button: NSStatusBarButton?) -> Bool {
        guard let button, let buttonWindow = button.window else { return false }
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let screen = buttonWindow.screen
            ?? NSScreen.screens.first { $0.frame.contains(buttonScreenRect.origin) }
            ?? NSScreen.main
        guard let screen else { return false }
        // NSStatusBar creates the button's window eagerly (so button.window/.screen are non-nil
        // before layout), but a not-yet-laid-out item is reported at a transient position before
        // AppKit slides it into its real slot. Two signals must both hold before the anchor is
        // trustworthy:
        //   (1) Menu-bar proximity (Y): the laid-out item sits at the top edge. Compare against
        //       screen.frame.maxY (the menu-bar edge), not visibleFrame.maxY which excludes it.
        let nearMenuBar = abs(buttonScreenRect.maxY - screen.frame.maxY) < statusAnchorReadyThreshold
        //   (2) Settled horizontally (X): during the .accessory entry churn the item is briefly
        //       reported flush against a screen edge — at the right corner (right edge == screen
        //       maxX) or near the left origin — before it lands in its real slot. A real status
        //       item never sits flush in a corner (system items like Control Center are always to
        //       its right), so treat a flush-edge X as not-yet-laid-out and keep waiting for the
        //       next move notification. Revealing under the transient corner X is exactly what
        //       jammed the window against the right screen edge.
        let settledX = buttonScreenRect.minX > screen.frame.minX + statusItemEdgeInset
            && buttonScreenRect.maxX < screen.frame.maxX - statusItemEdgeInset
        return nearMenuBar && settledX
    }

    func hide() {
        persistFloatingFrameIfNeeded()
        stopObservingStatusButtonFrame()
        stopObservingDisplayConfig()
        anchorDiagnosticTimer?.invalidate()
        anchorDiagnosticTimer = nil
        anchorButton = nil
        window?.alphaValue = 0
        window?.orderOut(nil)
    }

    private func persistFloatingFrameIfNeeded() {
        guard isFloatingMode, let window, window.frame != .zero else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.floatingFrameKey)
    }

    func persistFloatingFrameForStateSaving() {
        persistFloatingFrameIfNeeded()
    }

    private static func savedFloatingFrame() -> NSRect? {
        guard let string = UserDefaults.standard.string(forKey: floatingFrameKey), !string.isEmpty else {
            return nil
        }
        let frame = NSRectFromString(string)
        return frame == .zero ? nil : frame
    }

    private static func visibleFloatingFrame(for frame: NSRect) -> NSRect? {
        guard !NSScreen.screens.isEmpty else { return frame }

        let bestScreen = NSScreen.screens
            .map { screen -> (screen: NSScreen, area: CGFloat) in
                let intersection = frame.intersection(screen.visibleFrame)
                let area = intersection.isNull || intersection.isEmpty
                    ? 0
                    : intersection.width * intersection.height
                return (screen, area)
            }
            .max { $0.area < $1.area }

        guard let bestScreen, bestScreen.area > 0 else { return nil }

        let visibleFrame = bestScreen.screen.visibleFrame
        var adjusted = frame
        adjusted.size.width = min(adjusted.width, visibleFrame.width)
        adjusted.size.height = min(adjusted.height, visibleFrame.height)
        adjusted.origin.x = min(max(adjusted.origin.x, visibleFrame.minX),
                                visibleFrame.maxX - adjusted.width)
        adjusted.origin.y = min(max(adjusted.origin.y, visibleFrame.minY),
                                visibleFrame.maxY - adjusted.height)
        return adjusted
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

        let margin: CGFloat = 8

        // Resolve the target screen and (when anchoring) the icon's center X. A ready anchor
        // gives the icon's screen and center; a nil button is the setup-time sizing call, which
        // uses the main screen and leaves the origin untouched. A button that isn't laid out yet
        // is left alone entirely — the reveal waits for the next move notification.
        let screen: NSScreen?
        let centerX: CGFloat?
        if let button, isStatusAnchorReady(button), let buttonWindow = button.window {
            let buttonScreenRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            screen = buttonWindow.screen
                ?? NSScreen.screens.first { $0.frame.contains(buttonScreenRect.origin) }
                ?? NSScreen.main
            centerX = buttonScreenRect.midX
        } else if button == nil {
            // Setup-time sizing call. Once the initial size is set, a nil-anchor call has nothing
            // to do — never resize an already-sized window when there's no anchor to position to.
            guard needsInitialSizing else { return }
            screen = NSScreen.main
            centerX = nil
        } else {
            return
        }

        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        guard visibleFrame != .zero else { return }
        let topY = visibleFrame.maxY

        let minimumHeight = window.minSize.height
        let availableHeight = max(minimumHeight, topY - visibleFrame.minY - margin)
        var frame = window.frame
        if needsInitialSizing {
            frame.size.width = min(compactBaseWidth, visibleFrame.width - margin * 2)
            frame.size.height = min(minimumHeight, availableHeight)
            needsInitialSizing = false
        } else {
            frame.size.width = max(frame.width, compactBaseWidth)
            frame.size.height = min(frame.height, availableHeight)
        }

        // Center the window horizontally under the status-item icon and pin its top to the menu
        // bar. No clamping: the window sits exactly centered under the icon, even when the icon is
        // near a screen edge. Clamping the origin back onto the screen is what jammed the window
        // against the right edge — it is not wanted. A nil-anchor setup call only sizes.
        if let centerX {
            frame.origin.x = centerX - frame.width / 2
            frame.origin.y = topY - frame.height
        }

        window.setFrame(frame, display: display, animate: false)
    }
}
