import AppKit

/// The real library browser, embedded in a skin's own window rather than in one of its own.
///
/// This is a lifecycle wrapper, not a second browser: it hosts the same `ClassicLibraryBrowserView`
/// the classic window does, in its embedded mode (no window chrome, injected scale and link sheet), so
/// servers, tabs, search, CoverFlow, and history behave identically. What it adds is the handle a skin
/// family needs — style, scale, backdrop, reload, link, and a teardown that actually reaches the browser before
/// its view is removed. A family subclasses it to add its own conformance (`.wal`'s
/// `WinampModernLibrarySurfaceView`). Main-thread only, like the view it holds.
@MainActor
class EmbeddedLibraryBrowserSurface {
    private let browser: ClassicLibraryBrowserView
    private var isTornDown = false

    var view: NSView { browser }

    /// The content scale the host last pushed, or nil before the first push — in which case the
    /// browser falls back to `contentScaleFallback`, the host's live skin scale. It is stored rather
    /// than computed because the host may fold settings into it that this wrapper deliberately cannot
    /// see (`.wal`'s Text Size lives in its renderer): the host resolves the number and hands it over.
    ///
    /// A box, not a plain property, because the browser is handed a closure reading it *while this
    /// object is still being initialized* — the fallback has to answer from the browser's very first
    /// layout, which happens inside `ClassicLibraryBrowserView.init`.
    private final class ContentScaleBox { var value: CGFloat? }
    private let pushedContentScale = ContentScaleBox()

    /// `presentLinkSheet` is supplied by the host because there is no `ClassicLibraryBrowserWindowController`
    /// here; `contentScaleFallback` is read live so a UI Size change needs no re-creation, and only
    /// answers until the host's first `applyContentScale(_:)`.
    init(frame: NSRect, contentScaleFallback: @escaping () -> CGFloat,
         presentLinkSheet: @escaping () -> Void) {
        let scale = pushedContentScale
        browser = ClassicLibraryBrowserView(embeddedFrame: frame,
                                  skinScale: { scale.value ?? contentScaleFallback() },
                                  presentLinkSheet: presentLinkSheet)
        browser.autoresizingMask = [.width, .height]
        browser.wantsLayer = true
        browser.layer?.masksToBounds = true
    }

    var browseModeRawValue: Int {
        get { browser.model.browseMode.rawValue }
        set { browser.model.restoreBrowseMode(rawValue: newValue) }
    }

    func reloadData() {
        guard !isTornDown else { return }
        browser.needsDisplay = true
    }

    func showLinkSheet() {
        guard !isTornDown else { return }
        browser.showLinkSheetFromHost()
    }

    /// Colours the browser from the skin around it rather than from the classic skin's.
    func applyStyle(_ style: SkinnedSurfaceStyle) {
        guard !isTornDown else { return }
        browser.applyStyle(style)
    }

    func applyContentScale(_ scale: CGFloat) {
        guard !isTornDown else { return }
        // The browser reads this through the closure it already holds, so storing it is the whole
        // change; the repaint only discards the geometry computed at the old number.
        pushedContentScale.value = max(0.1, scale)
        browser.needsDisplay = true
    }

    /// The Library Window backdrop the browser draws, for a host that shows one (`LibraryBackdropHosting`).
    var libraryBackdropPresenter: CavaPresenter? { browser.backdropPresenter }

    func refreshLibraryBackdrop() {
        guard !isTornDown else { return }
        browser.refreshBackdrop()
    }

    /// The holder went away — a tab switched, a layout changed. The browser leaves the screen and
    /// nothing else happens to it: the host owns one browser per skin and hands this same instance
    /// back when the holder returns, so cancelling its server work here would return a dead browser
    /// to the next visit.
    func unmountFromHolder() {
        browser.removeFromSuperview()
    }

    /// Idempotent and terminal: the host calls this when the *scene* is torn down, and the controller
    /// may tear the whole skin down after that. Holder removal takes `unmountFromHolder()` instead —
    /// routing it here latched `isTornDown` on a cached browser, after which the next call returned
    /// early and left the view sitting on top of every other tab.
    func prepareForUITeardown() {
        guard !isTornDown else { return }
        isTornDown = true
        browser.prepareForUITeardown()
        browser.removeFromSuperview()
    }

    // Its owners (the skin's holders) are main-actor objects, so the last release, and this, run on
    // the main thread.
    deinit { MainActor.assumeIsolated { prepareForUITeardown() } }
}
