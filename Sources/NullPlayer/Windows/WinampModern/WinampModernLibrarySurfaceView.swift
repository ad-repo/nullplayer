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

    /// The content scale the view layer last pushed, or nil before the first push — in which case the
    /// browser falls back to `contentScaleFallback`, the bridge's live skin scale. It is stored rather
    /// than computed because Text Size lives in the renderer, which this wrapper deliberately cannot
    /// see: the view layer resolves the number and hands it over.
    ///
    /// A box, not a plain property, because the browser is handed a closure reading it *while this
    /// object is still being initialized* — the fallback has to answer from the browser's very first
    /// layout, which happens inside `PlexBrowserView.init`.
    private final class ContentScaleBox { var value: CGFloat? }
    private let pushedContentScale = ContentScaleBox()

    /// `presentLinkSheet` is supplied by the host because there is no `PlexBrowserWindowController`
    /// here; `contentScaleFallback` is read live so a UI Size change needs no re-creation, and only
    /// answers until the view layer's first `applyContentScale(_:)`.
    init(frame: NSRect, contentScaleFallback: @escaping () -> CGFloat,
         presentLinkSheet: @escaping () -> Void) {
        let scale = pushedContentScale
        browser = PlexBrowserView(embeddedFrame: frame,
                                  skinScale: { scale.value ?? contentScaleFallback() },
                                  presentLinkSheet: presentLinkSheet)
        browser.autoresizingMask = [.width, .height]
        browser.wantsLayer = true
        browser.layer?.masksToBounds = true
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

    func applyContentScale(_ scale: CGFloat) {
        guard !isTornDown else { return }
        // The browser reads this through the closure it already holds, so storing it is the whole
        // change; the repaint only discards the geometry computed at the old number.
        pushedContentScale.value = max(0.1, scale)
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
