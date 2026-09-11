import AppKit

/// One borderless `NSWindow` per `.wmz` view the skin has open, all drawing and taking input against
/// **one shared script runtime**.
///
/// Modelled directly on `WinampModernHostedWindowMaterializer`, which is the only one of the three
/// existing families whose recipe transfers: Classic's windows are a 275px grid with a rigid centre
/// stack, Original's geometry is ours to decide, and a `.wmz` view is neither — it is an arbitrary
/// authored canvas (Halo 2's panels are 406x209 against a 327x294 player). What that recipe is:
/// independent top-level windows rather than `addChildWindow` children, placed **once** by
/// `WindowManager.tiledOrigin(for:avoiding:)` with `rescuedOrigin` as the never-`nil` fallback so a
/// window the user moved is never yanked back, joining the app's magnetic docking through a
/// family-gated branch of `WindowManager.managedWindowRecords`.
///
/// **The first materialization binds to the controller's existing window.** The player has to keep
/// being `WindowManager.mainWindowController.window`: it is the `MainWindowProviding` anchor, the
/// frame-restoration anchor, the tiler's own anchor, and the host the app-authored unskinned view is
/// swapped back into. Only the second and subsequent views get a window of their own.
///
/// The one thing that stays a child window is the VLC video output, for the reasons in
/// `SKILL.md` § W102.
@MainActor
final class WMPViewWindowMaterializer: NSObject, NSWindowDelegate {
    private weak var controller: WMPMainWindowController?
    /// The window the controller created before any skin loaded. Bound by the first view presented.
    private let playerWindow: WMPSkinWindow
    /// Open presentations by folded view id. A view appears at most once: `show` on one already open
    /// is a raise, not a second window.
    private var presentations: [String: WMPViewPresentation] = [:]
    /// Insertion order, so "the player" and "the last one" are answerable and teardown is
    /// deterministic.
    private var order: [String] = []
    private var isTornDown = false

    init(controller: WMPMainWindowController, playerWindow: WMPSkinWindow) {
        self.controller = controller
        self.playerWindow = playerWindow
    }

    // MARK: Lookup

    func presentation(for viewID: String) -> WMPViewPresentation? {
        presentations[WMPPath.fold(viewID)]
    }

    func presentation(for window: NSWindow) -> WMPViewPresentation? {
        presentations.values.first { $0.window === window }
    }

    func isOpen(_ viewID: String) -> Bool { presentation(for: viewID) != nil }

    /// Every open presentation, in the order the skin opened them. The player, when there is one, is
    /// first — it is what binds the shared window.
    var openPresentations: [WMPViewPresentation] {
        order.compactMap { presentations[$0] }
    }

    var playerPresentation: WMPViewPresentation? {
        openPresentations.first { $0.isPlayer }
    }

    /// The auxiliary windows, for `WindowManager`'s docking branch.
    var auxiliaryWindows: [NSWindow] {
        openPresentations.compactMap { $0.isPlayer ? nil : $0.window }
    }

    var isEmpty: Bool { presentations.isEmpty }

    /// Whether any open window is showing this view — what a NullPlayer menu toggle asks before
    /// opening a window of its own.
    func anyOpenView(where predicate: (String) -> Bool) -> Bool {
        openPresentations.contains { predicate($0.viewID) }
    }

    // MARK: Materialization

    /// A presentation for `viewID`, creating its window if this is the first time it is shown.
    ///
    /// `offset` is `theme.openViewRelative`'s displacement in **skin pixels** from the opener's
    /// top-left; it replaces the tiler for this window's one and only placement. Nil takes the
    /// tiler, which is every other route.
    /// `storedTopLeft` is where the user last left this window, which wins over both the offset and
    /// the tiler — `.wal`'s rule that what the user last decided beats what the skin declares.
    func materialize(viewID: String, size: NSSize, opener: WMPViewPresentation?,
                     offset: CGPoint?, storedTopLeft: CGPoint? = nil) -> WMPViewPresentation? {
        guard !isTornDown else { return nil }
        let key = WMPPath.fold(viewID)
        if let existing = presentations[key] { return existing }

        let isPlayer = presentations.values.allSatisfy { !$0.isPlayer }
        let window: WMPSkinWindow
        if isPlayer {
            window = playerWindow
        } else {
            window = WMPSkinWindow(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.borderless, .resizable, .miniaturizable],
                                   backing: .buffered, defer: false)
            // The same recipe the player window gets in `configureWindow`, minus the shadow: a
            // `.wmz` window is genuinely shaped and AppKit caches a borderless window's shadow from
            // whatever content it last saw, which over a transparent region reads as a dark box.
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.title = "NullPlayer — \(viewID)"
            window.delegate = self
            window.setAccessibilityIdentifier("WMPSkinView_\(viewID)")
            window.setAccessibilityLabel("Windows Media Player \(viewID) Window")
        }
        let presentation = WMPViewPresentation(viewID: viewID, window: window,
                                               isPlayer: isPlayer, skinSpaceSize: size)
        // The player window is placed by the restore path and by the user; only an auxiliary window
        // is placed by this materializer, and only once.
        presentation.hasBeenPlaced = isPlayer
        presentations[key] = presentation
        order.append(key)
        if !isPlayer {
            place(presentation, size: size, opener: opener, offset: offset,
                  storedTopLeft: storedTopLeft)
        }
        return presentation
    }

    /// `theme.currentViewID` replaces the calling window's view in place: the window survives and
    /// its key changes.
    func rekey(_ presentation: WMPViewPresentation, to viewID: String) {
        let old = WMPPath.fold(presentation.viewID)
        let new = WMPPath.fold(viewID)
        guard old != new else { presentation.viewID = viewID; return }
        presentations.removeValue(forKey: old)
        presentation.viewID = viewID
        presentations[new] = presentation
        if let index = order.firstIndex(of: old) { order[index] = new } else { order.append(new) }
    }

    /// Bring an already-open window forward. `show` on a view that is open is a raise, never a
    /// second window — which is what keeps a dispatcher skin re-opening its own panels from its
    /// preferences at load from ending up with two of each.
    func raise(_ presentation: WMPViewPresentation) {
        presentation.window.orderFront(nil)
    }

    // MARK: Closing

    /// Drop one window's presentation.
    ///
    /// - Parameter closing: whether this is a **close** — `view.close()`, `theme.closeView`, or the
    ///   macOS close control — as opposed to a skin reload or a mode teardown. It decides one thing,
    ///   and only for the player: whether its window is ordered off screen.
    ///
    ///   **Ordering the player out is what a close means and nothing else.** The player's window is
    ///   the *app's* — it outlives every skin, hosts the unskinned view, and is the anchor the rest
    ///   of the app holds — so a reload that ordered it out took the main window off screen with
    ///   nothing anywhere to put it back. The launch path is what made that a defect rather than a
    ///   theory: `AppStateManager.restoreWindowFrames` calls `restoreFrame`, which reloads the skin
    ///   when one is already loaded, so every launch with a persisted `.wmz` and a saved frame lost
    ///   its main window. Reported as "main windows launch minimized".
    ///
    ///   An **auxiliary** window is ordered out either way: it belongs to the skin, and a skin that
    ///   is going away must not leave its panels behind.
    @discardableResult
    func remove(_ presentation: WMPViewPresentation, closing: Bool = false) -> WMPViewPresentation? {
        let key = WMPPath.fold(presentation.viewID)
        guard presentations.removeValue(forKey: key) != nil else { return nil }
        order.removeAll { $0 == key }
        presentation.teardown()
        if presentation.isPlayer {
            if closing { presentation.window.orderOut(nil) }
        } else {
            presentation.window.orderOut(nil)
            presentation.window.contentView = nil
            presentation.window.delegate = nil
        }
        return presentation
    }

    /// Release every window for a reload or a mode teardown. The player's window is kept where it
    /// is — the caller is about to put a new skin, or the unskinned view, into it.
    func teardown() {
        for presentation in openPresentations { remove(presentation) }
        presentations.removeAll()
        order.removeAll()
    }

    /// Marks this materializer dead. A reload builds a new one; nothing may materialize against a
    /// skin that has been torn down.
    func invalidate() {
        isTornDown = true
        teardown()
    }

    // MARK: Placement

    /// Where an auxiliary window lands the first time it is shown, and never again.
    ///
    /// `WINAMP_MODERN_PLACE_TRACE`'s `.wmz` counterpart is `WMP_PLACE_TRACE`; see
    /// `skills/wmp-skin-guide/reference/harness.md`.
    private func place(_ presentation: WMPViewPresentation, size: NSSize,
                       opener: WMPViewPresentation?, offset: CGPoint?,
                       storedTopLeft: CGPoint?) {
        guard !presentation.hasBeenPlaced else { return }
        presentation.hasBeenPlaced = true
        let manager = WindowManager.shared
        let scale = controller?.uiScale ?? 1
        var origin: NSPoint?
        if let storedTopLeft {
            origin = NSPoint(x: storedTopLeft.x, y: storedTopLeft.y - size.height * scale)
        } else if let offset, let openerFrame = opener?.window.frame {
            // `openViewRelative`'s offset is in the skin's own pixels from the opener's **top-left**,
            // and macOS measures a frame from its bottom-left — so y is flipped as well as scaled.
            // This is `WinampModernMainWindowController.arrangedOrigin(playerFrame:size:offset:scale:)`
            // applied to a `.wmz` view; `Revert` hangs its EQ under the player and its playlist
            // beside it entirely with this call (W50).
            let topLeft = NSPoint(x: openerFrame.minX + offset.x * scale,
                                  y: openerFrame.maxY - offset.y * scale)
            origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height * scale)
        }
        if origin == nil {
            origin = manager.tiledOrigin(for: presentation.window.frame.size,
                                         avoiding: manager.occupiedWindowFrames(
                                            excluding: presentation.window))
        }
        if let candidate = origin { presentation.window.setFrameOrigin(candidate) }
        // Never leave a window somewhere it cannot be reached — the whole reason `rescuedOrigin`
        // is the fallback rather than the first choice. A skin that opens five panels at load
        // (Halo 2's `onLoadSkin` opens four from preferences plus `mainView`) is exactly the case
        // that walks off the bottom of the tiler's column.
        if let rescued = manager.rescuedOrigin(for: presentation.window) {
            presentation.window.setFrameOrigin(rescued)
        }
        if ProcessInfo.processInfo.environment["WMP_PLACE_TRACE"] == "1" {
            NSLog("[wmp/place] %@ %@", presentation.viewID, NSStringFromRect(presentation.window.frame))
        }
    }

    // MARK: NSWindowDelegate — auxiliary windows only

    /// The player window keeps `WMPMainWindowController` as its delegate, so every callback here
    /// belongs to a panel.

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let presentation = presentation(for: sender) else { return true }
        controller?.closeViewWindow(presentation)
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              presentation(for: window) != nil else { return }
        // **Not while the user is dragging this window.** `WindowManager` has already put the drag
        // through `windowWillMove` and set the origin itself, so running it again from the delegate
        // applies the same delta to the whole docked group a second time, once per mouse event —
        // the defect `WinampModernHostedWindowMaterializer` carries the same guard for.
        if !WindowManager.shared.isWindowDragInProgress {
            let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
            WindowManager.shared.applySnappedPosition(window, to: origin)
        }
        WindowManager.shared.postWindowLayoutDidChange()
        controller?.persistViewFrame(for: window)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let presentation = presentation(for: sender),
              let limits = presentation.activeLimits else { return frameSize }
        let scale = controller?.uiScale ?? 1
        let clamped = limits.clamp(WMPSize(width: frameSize.width / scale,
                                           height: frameSize.height / scale))
        return NSSize(width: clamped.width * scale, height: clamped.height * scale)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let presentation = presentation(for: window) else { return }
        controller?.windowDidResize(presentation)
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let presentation = presentation(for: window) else { return }
        controller?.renderCurrentSize(presentation)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              presentation(for: window) != nil else { return }
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }
}
