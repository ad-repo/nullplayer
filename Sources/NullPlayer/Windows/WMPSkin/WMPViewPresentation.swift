import AppKit

/// One `.wmz` view on screen, and everything that belongs to *it* rather than to the skin session.
///
/// **`theme.openView` opens an additional window in Windows Media Player and leaves the opener
/// alone**; only `theme.currentViewID` replaces a view. This engine had exactly one WMP window for
/// four phases, so every field below lived on `WMPMainWindowController` as a singleton and the
/// second window was *simulated* — the opened view was presented in the one window and the view it
/// covered was remembered on an `openedViewStack` so `closeView` could put it back. That simulation
/// was the direct cause of W90 ("closing an interior window closes the whole UI"), W96 ("the skin is
/// empty and shows no player") and W127 (the macOS close control stranding the user), and the reason
/// `theme.openViewRelative`'s offset was meaningless (W50). Making the second window real is what
/// deletes all four, and this type is the seam that makes it possible: the controller keeps the skin
/// *session* (the loaded skin, the image store, the script runtime, the dispatcher, the host) and
/// hands one of these to every method that used to read the singleton.
///
/// **A drawer is not one of these.** Corona's sliding playlist and equaliser, and NVIDIA's embedded
/// playlist and video modes, are `<SUBVIEW>`s inside the presented view's own canvas. They never
/// reach `theme.openView` and never get a presentation of their own; they are drawn by the scene
/// like any other node and must keep behaving exactly as they do.
@MainActor
final class WMPViewPresentation {
    /// The view this window is currently showing. **Mutable**, because `theme.currentViewID`
    /// replaces the calling window's view in place — the window survives, the view id does not.
    var viewID: String
    let window: WMPSkinWindow
    /// Whether this presentation is bound to `WMPMainWindowController.window`, the window the app
    /// created before any skin loaded.
    ///
    /// It is the player in every sense the rest of the app cares about: `MainWindowProviding`'s
    /// anchor, the frame-restoration anchor, the tiler's anchor, and the host for the app-authored
    /// unskinned view. The first view a skin presents binds to it, so none of those move when a
    /// skin opens panels of its own. It is also the only presentation that writes
    /// `wmpSkinViewID` (W96) and the only one `WMPSurfacePalette` samples, because NullPlayer's own
    /// windows must not be recoloured by whichever panel happened to open last.
    let isPlayer: Bool

    var mainView: WMPMainView?
    var activeScene: WMPScene?
    var sceneOverrides = WMPSceneOverrides.empty
    var activeLimits: WMPResizeLimits?
    /// The window's size in the skin's own pixels — the size the scene is built and clamped at.
    /// UI Size never enters it; only the window frame and the rasterization scale carry that.
    var skinSpaceSize: NSSize
    /// The size the skin's own script last assigned this view, held until a user resize replaces it.
    /// See `WMPMainWindowController`'s note on W113: it is the script's output, not the drawing's.
    var scriptViewSize: WMPSize?
    /// The pointer/keyboard state this window last reported, so a script transaction can rebuild its
    /// scene with it rather than erasing the hover artwork the input just painted.
    var interactionState = WMPInteractionState()

    /// This view's own `timerInterval`, and the period it is currently running at.
    var viewTimerTask: Task<Void, Never>?
    var viewTimerMilliseconds = 0
    /// The animation repaint loop and the instant its clock is measured from. Separate from the view
    /// timer: that one dispatches `onTimer` and rebuilds the scene, and an animation must do
    /// neither — it re-renders the scene that already exists.
    var animationTask: Task<Void, Never>?
    var animationEpoch = Date()
    /// The view the animation clock belongs to. A window outlives the view inside it, so this is
    /// still needed even though a presentation has one `viewID` at a time.
    var animationEpochViewID: String?
    /// What the running loop is pacing to. A rebuild that produces the same cadence leaves the loop
    /// alone; only a change to it — or a view change, or teardown — restarts one.
    var animationCadence: WMPRenderer.WMPAnimationCadence?
    /// `WMP_ANIM_TRACE` only: what the repaint loop actually achieved, summarised once a second
    /// rather than once a frame. A line per frame is what made the old `INPUT` trace unusable.
    var animationTraceWindowStart = Date()
    var animationTraceFrames = 0
    var animationTraceRestarts = 0
    var animationTraceRenderSeconds: TimeInterval = 0
    var animationTracePresentSeconds: TimeInterval = 0
    var animationTraceSleepSeconds: TimeInterval = 0
    /// The script's own `setTimeout`/`setInterval` tasks, by token. Per view because the tokens are
    /// per view: two open panels each run their own chain.
    var scriptTimerTasks: [Int: Task<Void, Never>] = [:]
    var scriptTask: Task<Void, Never>?
    var loadTask: Task<Void, Never>?
    /// Host events a refresh has decided on for **this** view but not yet dispatched.
    var pendingHostEvents: [String] = []

    /// Whether this window has been placed once. Placement happens on the first show and never
    /// again, so a window the user dragged somewhere is never yanked back — the same rule
    /// `WinampModernHostedWindowMaterializer` follows for a `.wal` container.
    var hasBeenPlaced = false
    /// Set while this controller is driving the window's frame, so `windowDidResize` can tell a
    /// scene-driven size from one the user dragged out.
    var isApplyingSceneSize = false

    init(viewID: String, window: WMPSkinWindow, isPlayer: Bool, skinSpaceSize: NSSize) {
        self.viewID = viewID
        self.window = window
        self.isPlayer = isPlayer
        self.skinSpaceSize = skinSpaceSize
    }

    /// Seconds of animation elapsed for `viewID`, or zero when the clock belongs to another view.
    ///
    /// **Every render of a view that is already animating has to pass this.** Preserving the epoch
    /// alone does not stop the flicker: a rebuilt scene renders at `clock: 0` by default, so a
    /// transaction paints frame zero and the loop only catches up a frame later.
    func animationClock(for viewID: String?) -> TimeInterval {
        guard let viewID, animationEpochViewID == viewID else { return 0 }
        return Date().timeIntervalSince(animationEpoch)
    }

    /// The script's timers — what a handler asked for with `setTimeout`/`setInterval` — and nothing
    /// else. The view timer and the animation loop are stopped by `stopAllTimers`.
    func cancelScriptTimers() {
        scriptTimerTasks.values.forEach { $0.cancel() }
        scriptTimerTasks.removeAll()
    }

    /// Everything in this presentation with a clock. The session's background dispatcher is
    /// deliberately not here: it belongs to the skin rather than to a view, and a view switch is
    /// exactly when it is most needed.
    func stopAllTimers() {
        cancelScriptTimers()
        viewTimerTask?.cancel()
        viewTimerTask = nil
        viewTimerMilliseconds = 0
        stopAnimation()
        animationEpochViewID = nil
    }

    /// Stop the repaint loop and forget the cadence it was pacing to, so the next `startAnimation`
    /// starts one rather than recognising its own.
    func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        animationCadence = nil
    }

    /// Stop everything and release the drawing. The window itself is the materializer's to order out
    /// or, for the player, to hand back to the unskinned view.
    func teardown() {
        loadTask?.cancel(); loadTask = nil
        scriptTask?.cancel(); scriptTask = nil
        stopAllTimers()
        mainView?.prepareForUITeardown()
        mainView = nil
        activeScene = nil
        sceneOverrides = .empty
        activeLimits = nil
        scriptViewSize = nil
        pendingHostEvents.removeAll()
    }
}
