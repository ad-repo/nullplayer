import AppKit

/// The host's video output, placed over a `.wal` skin's video box (B20).
///
/// Unlike the library surface this creates no player of its own. `VideoPlayerWindowController` owns
/// the one video view in the app — with it the VLC media player, the cast handover, the Plex /
/// Jellyfin / Emby progress reporting and the analytics session — and a second one would be a second
/// set of all of that.
///
/// It also does not *contain* the picture. The first shape of this surface moved `VideoPlayerView`
/// into the skin's view tree, the way the `.library` surface hosts a browser, and the video engine
/// would not have it: VLCKit installs its own output view under the player's host view and sizes
/// that view's ancestors, so on the first frame the skin window's content view ran away to tens of
/// thousands of pixels wide and the picture did not appear at all until something forced another
/// relayout. What this holds instead is a **black box the skin lays out**, and the controller's own
/// window is parked over that box as a child window. The decoder then has a layout tree of its own
/// that cannot reach the skin's, and `addChildWindow` keeps the two glued together.
///
/// That is also what makes the lifetime question answerable. The video window is mode-independent
/// and deliberately preserved across `reloadUI`; parking rather than owning means a layout switch, a
/// skin switch or a mode switch unparks the window — still playing — instead of tearing the player
/// down with the skin.
final class WinampModernVideoSurfaceView: WinampModernVideoSurface {
    private let container: VideoSurfaceBoxView
    private var isAttached = false

    var view: NSView { container }

    init(frame: NSRect) {
        container = VideoSurfaceBoxView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        // **No autoresizing mask.** `layoutHostedSubviews` gives this box its frame outright, from
        // the holder's own resolved geometry; a mask would let AppKit stretch it on every window
        // resize and leave the parked window sized to a box the skin never asked for — which is what
        // put the picture through the right-hand edge of the skin's chrome.
        container.autoresizingMask = []
        container.onGeometryChange = { [weak self] in self?.updateOutputPlacement() }
    }

    var showsCommandBar = true { didSet { applyCommandBarPolicy() } }

    /// The bar goes in when the holder asked for it **and** the box is wide enough to hold it. Its
    /// controls are laid out with a required constraint chain, so a bar in a box too narrow for it
    /// does not compress — it forces the window wider than the box and pushes the picture out
    /// through the skin's chrome. Five of the six corpus holders declare `noshowcmdbar="1"`; the
    /// sixth (mmd3) does not, and its box is 375pt against the bar's 395pt minimum, so it is the one
    /// this rule is actually deciding.
    private func applyCommandBarPolicy() {
        guard isAttached,
              let controller = WindowManager.shared.currentVideoPlayerController else { return }
        controller.showsVideoControlBar =
            showsCommandBar && container.bounds.width >= controller.videoControlBarMinimumWidth
    }

    var presentationSize: CGSize {
        guard isAttached else { return .zero }
        return WindowManager.shared.currentVideoPlayerController?.presentationSize ?? .zero
    }

    func attachVideoOutput() {
        guard let controller = WindowManager.shared.currentVideoPlayerController,
              container.window != nil else { return }
        controller.hostOutputWindow(over: container)
        isAttached = true
        applyCommandBarPolicy()
        // The bar leaving the hierarchy drops the window's derived minimum size; the frame it
        // refused before that has to be asked for again.
        controller.updateHostedOutputFrame(over: container)
    }

    /// Keep the parked window on the box. The skin moves this box on every layout pass, and a child
    /// window follows its parent's *moves* by itself but knows nothing about a resize of the box
    /// inside it.
    func updateOutputPlacement() {
        guard isAttached,
              let controller = WindowManager.shared.currentVideoPlayerController else { return }
        // Policy first: a box that has just been resized past the bar's minimum changes whether the
        // bar is allowed to be there, and the bar is what decides the smallest frame the window can
        // take.
        applyCommandBarPolicy()
        controller.updateHostedOutputFrame(over: container)
    }

    func detachVideoOutput() {
        // Reveal only if there is still something to watch: a box that goes away mid-film must not
        // leave the film playing into a window nobody can see, and one that goes away after the film
        // ended must not pop an empty black window open.
        unpark(revealing: WindowManager.shared.currentVideoPlayerController?.currentTitle != nil)
    }

    /// The deliberate opposite: unpark and stay hidden. An embedded surface has no window to order
    /// out, so this is what putting its picture away has to mean (B23).
    func hideVideoOutput() { unpark(revealing: false) }

    private func unpark(revealing reveal: Bool) {
        guard isAttached else { return }
        isAttached = false
        guard let controller = WindowManager.shared.currentVideoPlayerController else { return }
        controller.showsVideoControlBar = true
        controller.reclaimVideoOutput(reveal: reveal)
    }

    /// The video box is black in every skin that draws one — Winamp's own, and all six in the
    /// corpus. There is nothing here for a colour theme to recolour.
    func applyPalette(_ palette: WasabiPalette) {}

    /// The box is laid out at the scaled holder frame and the parked window is set from the box's
    /// own screen rect, so UI Size needs no arithmetic here.
    func applySkinScale(_ scale: CGFloat) { updateOutputPlacement() }

    /// Idempotent, and — unlike the library's — **not terminal**. The library surface cancels server
    /// tasks and can never come back; this one owns nothing, so a layout that removes the box and
    /// puts it back gets a working surface again rather than a dead one the bridge is still caching.
    func prepareForUITeardown() {
        detachVideoOutput()
        container.removeFromSuperview()
    }

    /// **A holder leaving is a tab switch, not the end of the film** (B63). It shares the teardown's
    /// safety — this surface owns nothing terminal, so the holder coming and going is fine either way
    /// — but not its *reveal*: unparking with `detachVideoOutput()` here popped NullPlayer's own
    /// video window out over the skin every time the user left cPro-Bento's Video tab, which reads as
    /// the player escaping rather than the picture being put away. The film keeps playing, unseen,
    /// and `reconcileHostedSurfaces` parks it back when the tab returns.
    ///
    /// The scene's own teardown still reveals: there is no tab to come back to.
    func unmountFromHolder() {
        hideVideoOutput()
        container.removeFromSuperview()
    }
}

/// The black box the skin lays out, and the single source of truth for where the parked window goes.
///
/// The placement used to be pushed from the layout pass alone, and every path that moved this box
/// without one — an autoresize, a window that came on screen after the last pass — left the picture
/// somewhere the box no longer was. Now the box reports its own geometry, so there is no ordering to
/// get right: whatever moves it, the window follows.
private final class VideoSurfaceBoxView: NSView {
    var onGeometryChange: (() -> Void)?

    override var isOpaque: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onGeometryChange?()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        onGeometryChange?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onGeometryChange?()
    }
}
