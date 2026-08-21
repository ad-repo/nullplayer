import AppKit

/// The real library browser, embedded in a `.wal` skin's holder.
///
/// This is a thin lifecycle wrapper, not a second browser: it hosts the same `PlexBrowserView` the
/// classic window does, in its embedded mode (no window chrome, injected scale and link sheet), so
/// servers, tabs, search, CoverFlow, and history behave identically. What the wrapper adds is the
/// typed handle the skin engine needs — palette, scale, reload, link, and a teardown that actually
/// reaches the browser before its view is removed.
final class WinampModernLibrarySurfaceView: WinampModernLibrarySurface {
    private let browser: PlexBrowserView
    private var isTornDown = false

    var view: NSView { browser }

    /// `presentLinkSheet` is supplied by the host because there is no `PlexBrowserWindowController`
    /// here; `skinScale` is read live so a UI Size change needs no re-creation.
    init(frame: NSRect, skinScale: @escaping () -> CGFloat, presentLinkSheet: @escaping () -> Void) {
        browser = PlexBrowserView(embeddedFrame: frame, skinScale: skinScale,
                                  presentLinkSheet: presentLinkSheet)
        browser.autoresizingMask = [.width, .height]
    }

    var browseModeRawValue: Int {
        get { browser.browseModeRawValue }
        set { browser.browseModeRawValue = newValue }
    }

    func reloadData() {
        guard !isTornDown else { return }
        browser.needsDisplay = true
    }

    func showLinkSheet() {
        guard !isTornDown else { return }
        browser.showLinkSheetFromHost()
    }

    func applyPalette(_ palette: WasabiPalette) {
        guard !isTornDown else { return }
        // The browser used to paint with the classic skin's colours and bitmap font, which inside a
        // `.wal` window is a foreign UI coloured by a skin the user is not even looking at. It now
        // draws from the loaded skin's own palette instead (Phase 16).
        browser.applyWinampModernStyle(WinampModernSurfaceStyle(palette: palette))
    }

    func applySkinScale(_ scale: CGFloat) {
        guard !isTornDown else { return }
        // The scale is read through the closure the browser already holds, so this only has to
        // invalidate the geometry that was computed at the old one.
        browser.needsDisplay = true
    }

    /// The holder went away — a tab switched, a layout changed. The browser leaves the screen and
    /// nothing else happens to it: the bridge owns one browser per skin and hands this same instance
    /// back when the holder returns, so cancelling its server work here would return a dead browser
    /// to the next visit.
    func unmountFromHolder() {
        browser.removeFromSuperview()
    }

    /// Idempotent and terminal: the view layer calls this when the *scene* is torn down, and the
    /// controller may tear the whole skin down after that. Holder removal takes `unmountFromHolder()`
    /// instead — routing it here latched `isTornDown` on the bridge's cached browser, after which the
    /// next call returned early and left the view sitting on top of every other tab.
    func prepareForUITeardown() {
        guard !isTornDown else { return }
        isTornDown = true
        browser.prepareForUITeardown()
        browser.removeFromSuperview()
    }

    deinit { prepareForUITeardown() }
}
