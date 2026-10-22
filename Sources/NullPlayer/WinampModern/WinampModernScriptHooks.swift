import CoreGraphics
import Foundation

/// What the window layer answers for the script runtime: every request a script makes of a window,
/// the player, the equalizer or the desktop. The player view and the window controller fill these
/// in; the headless harnesses fill only the ones their run needs, and a hook left `nil` is the
/// runtime's "no window" answer. Held as one value so that teardown clears every hook in one
/// assignment and a new one cannot be missed (B220).
struct WinampModernScriptHooks {
    /// A repaint, and nothing more — no re-layout, no surface reconciliation. Layer FX drives this
    /// 30 times a second per warped layer, and `graphDidMutate` is far too heavy for that path (it
    /// re-runs component-holder reconciliation, since a script may have built one). Falls back to
    /// `graphDidMutate` when a window has not supplied it.
    var repaintRequested: (() -> Void)?
    /// The same, for a repaint that is confined to **one object's rect**. A warped meter changes a
    /// few hundred pixels 30 times a second, and repainting the whole window for it costs three
    /// times as much per frame as repainting what moved (measured on Defix at Retina scale: 19.3 ms
    /// against 6.9 ms), which is the difference between a smooth reel and a rough one.
    var objectRepaintRequested: ((WasabiObject) -> Void)?
    /// A layout switch or resize, addressed to the *container* whose script asked for it. A `.wal`
    /// skin has one script runtime and several windows; without the container id every playlist
    /// script that resized itself at startup resized the player instead.
    var layoutSwitchRequested: ((WasabiObjectID, String) -> Bool)?
    var layoutResizeRequested: ((WasabiObjectID, CGSize) -> Void)?
    /// A script moving its own *window*, in Winamp's screen coordinates (top-left origin, the space
    /// `getViewportWidth`/`getViewportHeight` answer in). A container's `x`/`y` are the window's
    /// position on the desktop, not a box inside a scene, so unlike every other geometry write these
    /// two reach nothing the renderer draws — Big Bento's notifier parks itself at the bottom-right
    /// corner with `resize()` and a `setTargetX/Y` animation, and with this unwired the toast stayed
    /// wherever the host had first placed it (BB27).
    ///
    /// The third argument says the point is **pinned** to another window rather than chosen: it is
    /// the desktop origin of a window the script just read, so it must be honoured as-is. Placing a
    /// window is clamped to the visible frame; mirroring one is not, or a pair that the host has
    /// already let sit partly off-screen comes apart at the edge (B69).
    var containerMoveRequested: ((WasabiObjectID, CGPoint, Bool) -> Void)?
    /// `layout.setScale(f)` — the skin asking for the **whole UI** at a different size. Defix's
    /// configurator offers seven of them (100–300%) and every one of its five window scripts calls
    /// this on its own layout from the same stored `SCALING`, so it is one global request repeated,
    /// not five per-window scales. NullPlayer answers it with its own **UI Size**: a `.wal` scene is
    /// always laid out on the skin's pixel grid and the view scales at the drawing and input
    /// boundaries (Phase 10), so a second, layout-local scale would be a rival to that one and the
    /// two would fight over every window's size. `nil` in the harness, and while a skin is still
    /// loading the host defers the request rather than resizing windows that do not exist yet.
    var uiScaleRequested: ((CGFloat) -> Void)?
    /// The scale every window is drawn at — UI Size — which `layout.getScale()` answers. `nil` in the
    /// harness, which draws at 1.
    var uiScaleQuery: (() -> CGFloat)?
    /// The whole display containing the skin's player window, in logical screen points. MAKI's
    /// monitor methods are global (there is no GUI-object receiver from which to find a window), so
    /// the window layer supplies the screen explicitly. AppKit points are intentional: converting
    /// through `backingScaleFactor` would leak Retina pixels into script geometry, while every other
    /// desktop coordinate the runtime exchanges with the window layer is expressed in points.
    var monitorSizeRequested: (() -> CGSize?)?
    var actionRequested: ((String, String?) -> Void)?
    /// The object form of `navigateUrl`: only the addressed `<browser>` may navigate.
    var browserNavigationRequested: ((WasabiObjectID, String) -> Void)?
    /// `Browser.back()` (`false`) / `forward()` (`true`) on one `<browser>`.
    var browserHistoryRequested: ((WasabiObjectID, Bool) -> Void)?
    /// `System.showWindow("guid:pl", …)`: open a component's window, leaving an open one open.
    var componentShowRequested: ((WinampModernComponentKind) -> Void)?
    /// The **global** form, which names no object: `System.navigateUrl` (the user's browser) and
    /// `System.navigateUrlBrowser` (the player's own). Both are routed rather than executed here —
    /// the address is skin-authored, so the window layer resolves it against
    /// `WinampModernWebNavigationPolicy` and the external route is confirmation-gated (B40).
    var globalNavigationRequested: ((WinampModernWebNavigationTarget, String) -> Void)?
    /// A script showing or hiding a **container** is asking for its *window*, not just for an
    /// attribute on the graph. Defix's SUI is reachable only this way: its four round PL/EQ/ML/VD
    /// buttons send the skin's own `opentab` action, and `skin.xml`'s `onAction` answers it with
    /// `getContainer("SUI").show()` — there is no host action and no markup `TOGGLE` for the host to
    /// see, so without this the attribute flipped and no window ever appeared. Fired on every call,
    /// not only on a change, because the window can be closed while the attribute still says visible;
    /// the host is the one that knows, and ignores a request that asks for the state it is already in.
    var containerVisibilityRequested: ((String, Bool) -> Void)?
    var themeNamesRequested: (() -> [String])?
    var activeThemeRequested: (() -> String)?
    var themeSwitchRequested: ((String) -> Bool)?
    /// Cursor position in the *skin's own pixel space* (the window's canvas), in skin pixels.
    ///
    /// **Not** the space a mouse event's x/y are in — those are relative to the receiver's parent
    /// (see `WinampModernMainView.dispatch`). A rotary-knob script combines the two in one
    /// expression precisely because they differ: mmd3's `getMousePosX() - x + knob.getLeft()` is the
    /// parent's origin plus the knob's own offset, i.e. the knob in cursor space.
    var mousePositionRequested: (() -> CGPoint)?
    /// `setFocus()` on an object: the view gives the keyboard to the `<edit>` it resolves to.
    var focusRequested: ((WasabiObject) -> Void)?
    /// The same cursor position, but in the pixel space of the window that renders `object` — which is
    /// a *different* window from the one `mousePositionRequested` answers for whenever the receiver
    /// lives in an auxiliary container. `System.getMousePos*` has no receiver and cannot ask this;
    /// `isMouseOverRect` does, and Defix's SUI tabs are in the SUI window while the mouse hook is
    /// installed by the main view, so comparing against the main window's space put every tab's
    /// hit somewhere else entirely. `nil` when no window renders the object (the headless harness).
    var mousePositionInObjectSpaceRequested: ((WasabiObject) -> CGPoint?)?
    /// Whether the equalizer is on, for `System.getEQ()`.
    var equalizerEnabledRequested: (() -> Bool)?
    /// One EQ band, on MAKI's −127…127 scale (MMD3's bass/treble knobs read and write the bands).
    var equalizerBandRequested: ((Int) -> Int)?
    var equalizerBandSetterRequested: ((Int, Int) -> Void)?
    /// The EQ preamp, on the same MAKI −127…127 scale as a band.
    var equalizerPreampRequested: (() -> Int)?
    var equalizerPreampSetterRequested: ((Int) -> Void)?
    /// `System.setEq(onoff)` — the absolute form of the `EQ_TOGGLE` action.
    var equalizerEnabledSetterRequested: ((Bool) -> Void)?
    /// `System.restoreApplication()` (`true`: bring minimized windows back too) and
    /// `activateApplication()` (`false`): put the player in front.
    var applicationRaiseRequested: ((Bool) -> Void)?
    /// `System.isMinimized()` — the notifier's "only when minimized" modes gate on it.
    var applicationMinimizedRequested: (() -> Bool)?
    /// `System.windowMenu()` — Winamp's window list, at the pointer.
    var windowMenuRequested: (() -> Void)?
    /// `PlEdit.showTrack(n)` and `showCurrentlyPlayingTrack()` — scroll the drawn playlist so a row
    /// is on screen. The scroll offset lives in the renderer, which the runtime does not own, so the
    /// window supplies this the way it supplies the equalizer's setters.
    var playlistRevealRowRequested: ((Int) -> Void)?
    /// One object's resolved rect and the box it resolved against, in skin pixels — supplied by the
    /// window that renders the object's container, since only a scene knows where anything landed.
    /// `nil` before any window is wired, and for an object outside the active layout.
    var resolvedGeometryRequested: ((WasabiObject) -> (frame: CGRect, parent: CGRect)?)?
    /// The player window's size in logical points. Paired with `containerOriginQuery` rather than
    /// folded into it, because the origin needs a coordinate flip and the size does not.
    var playerWindowSizeRequested: (() -> CGSize?)?
}
