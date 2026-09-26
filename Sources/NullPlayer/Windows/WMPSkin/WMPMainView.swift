import AppKit

#if DEBUG
/// `WMP_SEEK_TRACE=1` — the value a dragged slider carries from the pointer to the host command.
///
/// Per *gesture*, not per frame, which is what makes it usable where the old `INPUT` trace was not:
/// three lines for a whole drag. It exists because every part of this chain is plausible in
/// isolation and only the sequence is wrong — see `reference/harness.md`.
///
/// **stderr, not `print`.** A redirected stdout is block-buffered, and the first capture of this
/// instrument produced an empty log while the app was working perfectly.
func wmpSeekTrace(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["WMP_SEEK_TRACE"] != nil else { return }
    FileHandle.standardError.write(Data(("[wmp/seek] " + message() + "\n").utf8))
}

/// `WMP_RESIZE_TRACE=1` — a window resize against the skin's own bracket around it (W225).
///
/// A `view.size(corner)` drag and the half of the handler it holds are not visible to any other
/// instrument: `WMP_RENDER_CLICK` raises `onClick` and every grip in the corpus is `onMouseDown`,
/// and a scene capture agrees with the skin either way because the builder takes its canvas from
/// the overrides. One line per press, per release and per replayed write, plus the alignment
/// freezes the bracket depends on.
func wmpResizeTrace(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["WMP_RESIZE_TRACE"] != nil else { return }
    FileHandle.standardError.write(Data(("[wmp/resize] " + message() + "\n").utf8))
}

/// `WMP_WIDGET_TRACE=1` — the lifetime of every hosted widget view against the presents that carry
/// it: one line per present naming the code path it came from and the widgets in the scene, a
/// `create`/`drop` per hosted view, and a line per playlist redraw.
///
/// It exists because a pane that opens and then closes itself is invisible to every other
/// instrument: `WMP_RENDER_CLICK` rebuilds one scene from one event, and nothing headless can see a
/// *second* present, from a different path, landing 11 ms later with the state the first replaced —
/// `claw`'s "it displays, then goes black, then displays" (W223). The `structure=` field is the
/// other half: it says whether a present carried a new scene structure or only a new picture
/// (W224). Full grammar and the captures to compare against are in `reference/harness.md`.
func wmpWidgetTrace(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["WMP_WIDGET_TRACE"] != nil else { return }
    let t = Date().timeIntervalSince1970
    FileHandle.standardError.write(Data((String(format: "[wmp/widget] %.3f ", t) + message() + "\n").utf8))
}
#endif

/// Which window edges a borderless-window resize drag is moving.
struct WMPWindowEdges: OptionSet {
    let rawValue: Int
    static let left = WMPWindowEdges(rawValue: 1 << 0)
    static let right = WMPWindowEdges(rawValue: 1 << 1)
    /// Named for the *window*: `.top` is the screen-upward edge, which in this flipped view is the
    /// one nearest `bounds.minY`.
    static let top = WMPWindowEdges(rawValue: 1 << 2)
    static let bottom = WMPWindowEdges(rawValue: 1 << 3)
}

/// `NSViewToolTipOwner` is not decoration. Without the conformance declared, AppKit finds no
/// `view(_:stringForToolTip:point:userData:)` on the owner and falls back to its `description`: the
/// tooltip over every pixel of every skin read `<NullPlayer.WMPMainView: 0x…>`, reported on
/// 2026-09-08. The method below was written and correct all along — nothing was calling it.
/// The skin artwork that composites **over** the effects surface: everything the scene's walk
/// emitted from the `<EFFECTS>` node onwards. It is a subview rather than a second blit in
/// `draw(_:)` because `draw(_:)` runs before AppKit composites subviews, so a blit there would sit
/// *below* the visualizer and defeat the whole point.
///
/// It takes no mouse events: the artwork over a visualizer is decoration, and the clicks belong to
/// whatever is underneath — 51 corpus skins wire an `onClick` on the `<EFFECTS>` node itself.
private final class WMPSkinOverlayView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}

final class WMPMainView: NSView, NSViewToolTipOwner {
    var onInteractionChanged: ((WMPInteractionState, Set<Int>) -> Void)?
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?
    /// `(event, authored id, stable graph id)`. The stable id is what scopes the dispatch: a
/// `.wmz` is free to leave a control unnamed, and an authored id is therefore optional.
    var onScriptEvent: ((String, String?, Int?) -> Void)?
    /// A keystroke offered to the skin: `(event, authored id, stable graph id, keyCode)`, answering
    /// **whether the skin authored a handler for it** — which is the ordering rule this engine's
    /// keyboard is built on, and the whole of W53's design.
    ///
    /// The engine has its own keyboard behaviour for a focused control (the arrows step a slider,
    /// space and Return activate a button), and it exists because nothing used to raise the skin's
    /// own handlers. Now that they are raised, running both is one keypress acting twice — and
    /// worse than twice: `Age_of_Mythology_MP7` deliberately maps right/down to *quieter* on its
    /// volume slider, where the built-in step has right/up hardcoded to *louder*, so the two pull
    /// in opposite directions. **66 of 184 archives** author a key handler on a `SLIDER` or
    /// `CUSTOMSLIDER`, so this is the common case, not the corner.
    ///
    /// So the skin goes first and the built-in is the fallback: authored means handled, and the
    /// two-thirds of the corpus that authors nothing keeps the arrows and the activation it has.
    /// It is the same rule `handlerOwnsAction` already applies on the mouse path, asked of the
    /// markup rather than of the hit target — and it is answered *synchronously*, from the loaded
    /// skin's graph, because `keyDown` has to decide now whether to fall through, while the
    /// transaction it starts runs on the script actor.
    var onKeyEvent: ((String, String?, Int?, Int) -> Bool)?
    var onElementValueChanged: ((Int, String?, Double) -> Void)?
    /// A `<LISTBOX>` row the user picked: `(stableID, authored id, row)`. Its own callback rather
    /// than a `value` change, because WMP moves `selectedItem` and raises `selectedItem_onChange`
    /// (W136).
    var onListSelected: ((Int, String?, Int) -> Void)?
    var onListDoubleClicked: ((Int, String?, Int) -> Void)?
    /// A row of a library playlist a `<PLAYLIST>` is showing was played: `(the playlist, row)`.
    var onPlayLibraryTracks: ((WMPWidgetScriptState.PlaylistRows, Int) -> Void)?
    /// A slider the user has just let go of: its value, then `mouseup`/`dragend`, **in that order
    /// and in one transaction**. See W151. The fourth argument is the seek the gesture is asking
    /// for, held back from every intermediate mouse-move — see `pendingSeek` and W156.
    var onSliderRelease: ((Int, String?, Double, WMPHostValue?) -> Void)?
    /// Raised `true` when the pointer takes hold of a slider. **While it is held, the host must not
    /// write to that control** — see W151 and `WMPMainWindowController.sliderCaptureActive`.
    var onSliderCaptureChanged: ((Bool, Int) -> Void)?
    /// An `<EDITBOX>`'s text, which is a string rather than a number and so cannot go through
    /// `onElementValueChanged`. Nine of the corpus's ten edit boxes are a playlist search field
    /// whose script reads this back as `plSearchEdit.value`.
    var onElementTextChanged: ((Int, String?, String) -> Void)?
    /// Return in an `<EDITBOX>`: the text, then `onKeyUp` with `event.keyCode` 13 (W136).
    var onElementTextReturn: ((Int, String?, String) -> Void)?
    var onSpectrumDemandChanged: ((Bool) -> Void)?
    private var image: NSImage?
    /// Persistent, created once, never in `widgetViews` — it is not a widget. Everything hosted in
    /// the scene is ordered against it: effects surfaces below, interactive widgets above.
    private let overlayView = WMPSkinOverlayView(frame: .zero)
    private var scene: WMPScene?
    private var hitTester: WMPHitTester?
    private var interaction = WMPInteractionState()
    private var capturedTarget: WMPHitTarget?
    /// **The seek a drag is asking for, not yet asked (W156).** Every other slider action is
    /// continuous — a volume drag that only applied on release would be a control the user cannot
    /// hear — but a seek is a discontinuity in the audio: `AudioEngine.seek` stops the player node
    /// and reschedules the file from the new frame with no ramp, so committing one per mouse-move
    /// is 21 hard restarts across a 200 px drag, which is what "a harsh audio artifact at the time
    /// adjustment" was. Measured on `New Super Mario Bros` **and** on `corona`, whose bare
    /// `<SEEKSLIDER>` takes the same path through `target.action`: the two skins are identical
    /// here, 21 commits apiece, so the authored `onDragEnd` is not what separates them.
    ///
    /// The thumb still follows the pointer for the length of the gesture — `widgetValues` and
    /// `onElementValueChanged` are untouched, and W151's hold keeps the host from settling the
    /// implicit `player.controls.currentPosition` binding over it — so what is deferred is the
    /// audio, not the control.
    private var pendingSeek: WMPHostValue?
    /// The node the pointer is over, kept alongside `WMPInteractionState.hoveredNode` because the
    /// *exit* edge has to name the node the pointer just left — and by then the interaction state
    /// has already moved on. The authored id travels with it for the same reason.
    private var hoveredTarget: WMPHitTarget?
    private var tracking: NSTrackingArea?
    private var isDraggingWindow = false
    private var dragStart = NSPoint.zero
    /// Which window edges a drag is moving, the frame it started from, and where the pointer was.
    ///
    /// A `.wmz` window is `.borderless`, and a borderless window has no frame view — so AppKit
    /// draws and hit-tests no resize edge for it, `.resizable` in the style mask notwithstanding.
    /// Before this there was simply no way to resize a skin in WMP mode: `windowWillResize` clamped
    /// a drag that could never begin, and every expression-driven layout in the corpus was stuck at
    /// the size its markup opened with.
    private var resizeEdges: WMPWindowEdges = []
    /// Whether the drag in flight has a held handler tail to release on the mouse-up (W225).
    ///
    /// It used to mean "this drag came from `view.size(corner)`", which was the only way to get
    /// one. An edge-band drag now raises the view's own grip handler too (W227), so it carries a
    /// tail as well, and what this flag is actually asking is whether anything is held.
    private var isScriptResize = false
    /// Whether the drag in flight started on the window edge band rather than on the skin's grip.
    /// Read by `beginScriptResize`, which must adopt the drag the band already started rather than
    /// refuse the call that the band itself raised.
    private var isEdgeBandResize = false
    /// Raised when a `view.size(corner)` drag lets go — the moment WMP's own call returns.
    var onScriptResizeEnded: (() -> Void)?
    /// **How much of the window's top draws nothing, in points.** `Alpine`'s view is 517x412 and
    /// its artwork fills only the bottom ~150 — the top is where its drawers open — so a frame
    /// clamped at the screen top parked the faceplate a quarter-screen down. `WMPSkinWindow`
    /// lets this much of the frame go above the visible top. Read off the composite on a full or
    /// structural present, so a drawer that opens shrinks it.
    private(set) var transparentTopInset: CGFloat = 0
    /// **The grips this view authors for its own resize (W227).** Set by the controller from the
    /// skin's markup and scripts, because a grip is identified by the script its handler reaches
    /// and the scene carries no script. Empty for the 97 corpus archives that author none, and for
    /// every one of them the edge band behaves exactly as it did before.
    var resizeGrips: [WMPResizeGrip.Grip] = []
    /// **An invisible close in the top-right corner, for a skin that authors no close at all.**
    /// Set by the controller from `WMPCloseControl`; see there for why such skins exist. Nothing is
    /// drawn — the skin's artwork is untouched — and a control the skin draws in that corner keeps
    /// the press.
    var closeTargetEnabled = false
    var onCloseTarget: (() -> Void)?
    /// The target's side, in view points. It takes the corner from the edge band, whose top-right
    /// diagonal is the one resize no corpus skin asks for.
    private static let closeTargetSize: CGFloat = 16
    private var resizeStartFrame = NSRect.zero
    private var resizeStartMouse = NSPoint.zero
    private var widgetViews: [Int: NSView] = [:]
    private var widgetValues: [Int: Double] = [:]
    private var currentSnapshot = WMPHostSnapshot()
    /// Colours for native WMP-owned surfaces, derived from the active skin's own declarations.
    /// This is WMP-only state: no other skin mode reaches these overlays.
    var surfaceStyle: SkinnedSurfaceStyle? {
        didSet {
            guard let surfaceStyle else { return }
            widgetViews.values.compactMap { $0 as? WMPPlaylistSurfaceView }
                .forEach { $0.apply(style: surfaceStyle) }
        }
    }
    /// Resolves a widget's container shape to a mask image. The image store lives on the
    /// controller, so the view asks rather than decodes; nil is a skin that authored no shape.
    var regionMaskProvider: ((WMPWidgetRegionMask) -> CGImage?)?
    var videoSurface: WMPVideoSurface?
    /// `WMPRenderResult.silhouetteMask` for the scene on screen; it changes with every render, so
    /// it is applied on each present as well as each layout.
    private var silhouette: CGImage?
    var videoController: (() -> VideoPlayerWindowController?)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installOverlayView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installOverlayView()
    }

    private func installOverlayView() {
        overlayView.imageScaling = .scaleAxesIndependently
        overlayView.imageAlignment = .alignCenter
        overlayView.isEditable = false
        overlayView.autoresizingMask = [.width, .height]
        overlayView.frame = bounds
        addSubview(overlayView)
    }

    /// The AppKit surfaces hosted for widgets, and nothing else — the artwork overlay is not one
    /// of them. `WMP_RENDER_APPKIT` hides exactly these for its baseline pass: what a widget
    /// surface adds over the artwork is the question that probe asks, and the overlay *is* artwork.
    var hostedWidgetViews: [NSView] { Array(widgetViews.values) }

    /// The three layers, re-enforced on every pass. A plain `addSubview` always goes to absolute
    /// top, so a playlist that appears after the overlay would otherwise land on the wrong side of
    /// it and cover the artwork it is meant to sit under.
    private func enforceLayerOrder() {
        for (_, view) in widgetViews where view is WMPEffectsSurfaceView {
            addSubview(view, positioned: .below, relativeTo: overlayView)
        }
        for (_, view) in widgetViews where !(view is WMPEffectsSurfaceView) {
            addSubview(view, positioned: .above, relativeTo: overlayView)
        }
    }


    func present(_ cgImage: CGImage, overlay: CGImage? = nil, silhouette: CGImage? = nil,
                 scene: WMPScene, dirtyBounds: WMPRect? = nil, traceSource: String = "?") {
        let previous = self.scene
        self.silhouette = silhouette
        image = NSImage(cgImage: cgImage, size: bounds.size)
        overlayView.image = overlay.map { NSImage(cgImage: $0, size: bounds.size) }
        self.scene = scene
        // **A repaint of the same structure is a new picture and nothing else (W224).** The
        // animation loop re-renders `presentation.activeScene` — the *same* scene — for as long as
        // anything in it moves, and a scrolling `<TEXT>` is enough: `claw` with its playlist open
        // and no visualizer still presents 11.8x/s off its metadata line. Everything below derives
        // from the scene's own structure rather than from the picture, so when the hits and the
        // widgets are identical there is nothing for any of it to do, and doing it anyway cost a
        // hit-tester rebuild, a widget sync, a tooltip reset, a cursor-rect invalidation, an
        // accessibility reset **and a full redraw of every hosted surface** on every frame —
        // measured at 11.8 playlist redraws a second with the list unchanged.
        let structureUnchanged = previous.map {
            $0.widgets == scene.widgets && $0.hits == scene.hits
        } ?? false
        #if DEBUG
        wmpWidgetTrace("present src=\(traceSource) view=\(scene.viewID) widgets=[\(scene.widgets.map { "\($0.kind):\($0.stableID)" }.joined(separator: ","))] snapshotItems=\(currentSnapshot.playlistItems.count) structure=\(structureUnchanged ? "same" : "new")")
        #endif
        if !structureUnchanged {
            hitTester = WMPHitTester(hits: scene.hits)
            synchronizeWidgetViews(scene.widgets)
            // The AppKit overlays — playlist, equalizer, popup, effects, video — are positioned in
            // `layout()`, which AppKit will not run on its own just because a new scene arrived.
            // Without this an equalizer that the skin slid away stays on screen at its old frame.
            needsLayout = true
            removeAllToolTips(); _ = addToolTip(bounds, owner: self, userData: nil)
            window?.invalidateCursorRects(for: self)
        }
        if let dirtyBounds {
            // The union with everything the *previous* scene drew at a different frame. A dirty
            // rect derived from the new scene alone covers where a pane has arrived and never where
            // it left, so closing a drawer repainted the destination and abandoned the drawer's own
            // pixels on screen — reported during live QA as a leftover equaliser and a second copy
            // of the transport bar.
            var dirty = dirtyBounds
            let before = previous?.geometries ?? [:]
            for stableID in Set(before.keys).union(scene.geometries.keys) {
                let old = before[stableID]?.absoluteFrame
                let new = scene.geometries[stableID]?.absoluteFrame
                guard old != new else { continue }
                if let old { dirty = dirty.union(old) }
                if let new { dirty = dirty.union(new) }
            }
            let xScale = bounds.width / scene.canvasSize.width
            let yScale = bounds.height / scene.canvasSize.height
            setNeedsDisplay(NSRect(x: dirty.x * xScale, y: dirty.y * yScale,
                                   width: dirty.width * xScale, height: dirty.height * yScale))
        } else {
            needsDisplay = true
            // A `.wmz` window is shaped by its own artwork: Corona's player block occupies the
            // right 346 of a 596-wide view and the rest is transparent, because that is where its
            // playlist pane slides in. AppKit caches a borderless window's shadow from the content
            // it first drew — which here is the *opaque* unskinned player the controller shows
            // first — so without this the skin sits inside a full-rectangle drop shadow that reads
            // as a dark box around it. Only on a full present: a dirty-rect repaint (hover, a
            // moving slider) cannot change the silhouette, and invalidating per frame is expensive.
            window?.invalidateShadow()
        }
        // The children are built from the scene's hits and text widgets, so an unchanged structure
        // describes the same tree — and rebuilding it per frame is what an assistive client sees as
        // a window whose contents change 12 times a second.
        if !structureUnchanged { setAccessibilityChildren(nil) }
        if dirtyBounds == nil || !structureUnchanged { updateTransparentTopInset(cgImage) }
        applySilhouette()
    }

    /// The mask covers the whole canvas, so in each surface's bounds it sits at minus the
    /// surface's own origin, at this view's size.
    private func applySilhouette() {
        for (_, view) in widgetViews {
            guard let effects = view as? WMPEffectsSurfaceView else { continue }
            effects.applySilhouette(silhouette, rect: silhouette == nil ? .zero
                : NSRect(x: -view.frame.minX, y: -view.frame.minY,
                         width: bounds.width, height: bounds.height))
        }
    }

    private func updateTransparentTopInset(_ cgImage: CGImage) {
        let inset: CGFloat
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            inset = 0
        default:
            guard let plane = WMPAlphaPlane(cgImage), plane.height > 0 else { inset = 0; break }
            inset = CGFloat(plane.firstOpaqueRow ?? 0) * bounds.height / CGFloat(plane.height)
        }
        guard inset != transparentTopInset else { return }
        let shrank = inset < transparentTopInset
        transparentTopInset = inset
        // A drawer opening into the part above the screen top would open under the menu bar.
        guard shrank, let window else { return }
        let constrained = window.constrainFrameRect(window.frame, to: window.screen)
        if constrained != window.frame { window.setFrame(constrained, display: true) }
    }

    func refreshHostState(_ snapshot: WMPHostSnapshot) {
        currentSnapshot = snapshot
        guard let scene else { return }
        videoSurface?.update(in: self, scene: scene, video: snapshot.video,
                             controller: videoController?())
        var changed = Set<Int>()
        for hit in scene.hits {
            if let action = hit.action {
                changed.formUnion(interaction.setDisabled(!snapshot.isEnabled(action), node: hit.stableID))
                if hit.sticky { changed.formUnion(interaction.setStickyDown(Self.isDown(action, snapshot), node: hit.stableID)) }
            }
            for target in hit.mappingTargets {
                if let action = target.action {
                    changed.formUnion(interaction.setDisabled(!snapshot.isEnabled(action), node: target.stableID))
                    if target.sticky { changed.formUnion(interaction.setStickyDown(Self.isDown(action, snapshot), node: target.stableID)) }
                }
            }
        }
        notify(changed)
        setAccessibilityChildren(nil)
        for view in widgetViews.values {
            (view as? WMPPlaylistSurfaceView)?.update(snapshot)
            (view as? WMPDropdownPlaylistSurfaceView)?.update(snapshot)
            (view as? WMPEffectsSurfaceView)?.update(snapshot)
        }
    }

    /// The sticky latches a script transaction wrote, applied to the artwork's own state and
    /// returned so the caller's scene build sees them. No `notify`: the transaction that produced
    /// them is already rebuilding this view, and a second render of the same frame is the W158
    /// class. See `WMPScriptRuntime.setWidgetDown` (W206).
    func applyScriptedStickyLatches(_ latches: [Int: Bool]) -> WMPInteractionState {
        for (node, down) in latches { _ = interaction.setStickyDown(down, node: node) }
        return interaction
    }

    /// The last list items and widget state a transaction handed over, kept so a widget hosted
    /// *after* them starts with them (W274). The transaction path updates before it presents, and
    /// a present is where a widget is first created — `NVIDIA`'s chooser and search box appear in
    /// the very frame that sizes them, and were created empty, with nothing left to fill them.
    private var lastListItems: [Int: [String]] = [:]
    private var lastWidgetState = WMPWidgetScriptState.empty

    /// The items a `POPUP` or `LISTBOX` holds, from the last script transaction.
    func updateListItems(_ items: [Int: [String]]) {
        lastListItems = items
        for (stableID, view) in widgetViews {
            (view as? WMPPopupSurfaceView)?.update(items: items[stableID] ?? [])
            (view as? WMPListBoxSurfaceView)?.update(items: items[stableID] ?? [])
        }
    }

    /// What the last script transaction pointed the skin's own controls at (W136).
    func updateWidgetState(_ state: WMPWidgetScriptState) {
        lastWidgetState = state
        for (stableID, view) in widgetViews {
            (view as? WMPPlaylistSurfaceView)?.update(libraryRows: state.playlists[stableID])
            (view as? WMPListBoxSurfaceView)?.update(selection: state.listSelections[stableID])
            (view as? WMPEditBoxSurfaceView)?.update(scriptValue: state.editValues[stableID])
        }
    }

    /// Only the `<LISTBOX>` selections a transaction wrote, ahead of its scene (W300).
    func updateListSelections(_ selections: [Int: Int]) {
        for (stableID, index) in selections {
            (widgetViews[stableID] as? WMPListBoxSurfaceView)?.update(selection: index)
        }
    }

    func updateSpectrum(_ levels: [Float]) {
        widgetViews.values.compactMap { $0 as? WMPEffectsSurfaceView }.forEach { $0.updateSpectrum(levels) }
    }

    func cancelInputCapture() {
        if let capturedTarget, isSlider(capturedTarget) {
            onSliderCaptureChanged?(false, capturedTarget.stableID)
        }
        // A cancelled drag asks for no seek: the gesture never reached `mouseUp`, which is the only
        // place one is committed (W156).
        pendingSeek = nil
        notify(interaction.cancelCapture()); capturedTarget = nil; onAction?(.endScan, nil)
    }

    func prepareForUITeardown() {
        videoSurface?.detach(reveal: currentSnapshot.video.hasVideo)
        videoSurface = nil; videoController = nil
        cancelInputCapture()
        onSpectrumDemandChanged?(false)
        widgetViews.values.forEach { $0.removeFromSuperview() }; widgetViews.removeAll(); widgetValues.removeAll()
        image = nil; overlayView.image = nil; scene = nil; hitTester = nil; capturedTarget = nil; hoveredTarget = nil
        isDraggingWindow = false
        onInteractionChanged = nil; onAction = nil; onScriptEvent = nil; onKeyEvent = nil
        onElementValueChanged = nil; onElementTextChanged = nil; onSpectrumDemandChanged = nil
        onListSelected = nil; onListDoubleClicked = nil; onPlayLibraryTracks = nil
        onElementTextReturn = nil
    }

    func skinPoint(from event: NSEvent, sceneSize: WMPSize) -> WMPPoint {
        skinPoint(fromWindowPoint: event.locationInWindow, sceneSize: sceneSize)
    }

    func skinPoint(fromWindowPoint windowPoint: NSPoint, sceneSize: WMPSize) -> WMPPoint {
        let point = convert(windowPoint, from: nil)
        return WMPPoint(x: bounds.width > 0 ? point.x * sceneSize.width / bounds.width : 0,
                        y: bounds.height > 0 ? point.y * sceneSize.height / bounds.height : 0)
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }

    /// The tip for whatever is under the pointer: the control the hit tester lands on first, then
    /// the widget beneath it. Only widgets answered before 2026-09-08, so nearly every tip in the
    /// corpus was unreachable — a skin's controls are `<BUTTON>`s, and `upToolTip` is authored 4,789
    /// times across 176 of the 179 archives.
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let scene else { return "" }
        let skinPoint = WMPPoint(x: bounds.width > 0 ? point.x * scene.canvasSize.width / bounds.width : 0,
                                 y: bounds.height > 0 ? point.y * scene.canvasSize.height / bounds.height : 0)
        // The hit tester, not a frame scan: a mapping image gives four controls one frame and only
        // the pixel under the pointer says which of them the tip belongs to.
        if let target = hitTester?.hitTest(skinPoint) {
            if let tip = target.toolTip, !tip.isEmpty { return tip }
            if let tip = scene.hits.first(where: { $0.stableID == target.stableID })?.toolTip,
               !tip.isEmpty { return tip }
        }
        return scene.widgets.reversed().first { $0.frame.contains(skinPoint) }?.toolTip ?? ""
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill()
        image?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.low])
    }

    override func layout() {
        super.layout()
        overlayView.frame = bounds
        guard let scene else { return }
        let xScale = bounds.width / max(1, scene.canvasSize.width)
        let yScale = bounds.height / max(1, scene.canvasSize.height)
        #if DEBUG
        wmpWidgetTrace("layout bounds=\(WMPNumber.format(bounds.width))x\(WMPNumber.format(bounds.height)) "
            + "canvas=\(WMPNumber.format(scene.canvasSize.width))x\(WMPNumber.format(scene.canvasSize.height)) "
            + "scale=\(WMPNumber.format(xScale)),\(WMPNumber.format(yScale))")
        #endif
        for widget in scene.widgets {
            guard let view = widgetViews[widget.stableID] else { continue }
            // **The overlay goes where the scene painted the widget, not where it was authored
            // (W74).** A control authored past its container's edge is clipped by that container
            // in WMP, and `WMPSceneBuilder` already records the container's box as the widget's
            // `clipRect` — every painted command is confined to it. The `NSView` was placed from
            // the raw frame instead, so it drew wherever the markup reached. `Revert`'s
            // `ctrlPlaylist` is `3,14 250x257` inside a 260-tall view with `clip=3,14 250x242`:
            // the unclipped view covered the bottom four points of `pl_b.bmp` and the playlist
            // window lost the silver bevel closing its frame. `WMPVideoSurface.update` has always
            // done this — frame ∩ clip ∩ bounds — and this is the same arithmetic for the rest of
            // the widgets.
            //
            // **`?? widget.frame` is the trap here and is not what this reads like.** A widget with
            // no `clipRect` is unconfined and keeps its frame, but `WMPRect.intersection` also
            // answers `nil` for a clip that misses the frame *entirely* — and collapsing those two
            // onto one fallback hosts a fully clipped-away widget at full size, which is the defect
            // this fix exists to remove. The optional is unwrapped once, deliberately.
            let visible: WMPRect?
            if let clip = widget.clipRect {
                visible = widget.frame.intersection(clip)
            } else {
                visible = widget.frame
            }
            let placedFrame = visible.map {
                NSRect(x: $0.x * xScale, y: $0.y * yScale,
                       width: $0.width * xScale, height: $0.height * yScale).intersection(bounds)
            } ?? .zero
            view.frame = placedFrame.isNull ? .zero : placedFrame
            #if DEBUG
            wmpWidgetTrace("layout \(widget.kind):\(widget.stableID) scene=\(WMPNumber.format(widget.frame.x)),\(WMPNumber.format(widget.frame.y)) "
                + "\(WMPNumber.format(widget.frame.width))x\(WMPNumber.format(widget.frame.height)) "
                + "clipped=\(visible.map(String.init(describing:)) ?? "none") "
                + "view=\(WMPNumber.format(view.frame.width))x\(WMPNumber.format(view.frame.height))")
            #endif
            guard let effects = view as? WMPEffectsSurfaceView else { continue }
            // The mask image covers its container's frame, which is not always the widget's own —
            // so the rect is the offset between the two, in this surface's scaled bounds.
            func placed(_ mask: WMPWidgetRegionMask) -> (CGImage, NSRect)? {
                guard let image = regionMaskProvider?(mask) else { return nil }
                // Offset from the surface's own origin, which is the *placed* frame and no longer
                // the authored one (W74) — a clipped surface would otherwise wear a shifted mask.
                return (image, NSRect(x: mask.frame.x * xScale - view.frame.minX,
                                      y: mask.frame.y * yScale - view.frame.minY,
                                      width: mask.frame.width * xScale,
                                      height: mask.frame.height * yScale))
            }
            // Two independent confinements, and a skin can state either, both or neither: the
            // container's *shape* for its windowless child (`regionMask`) and the window's own
            // silhouette (`clippingShape`). Both are applied, so the surface is the intersection.
            let region = widget.regionMask.flatMap(placed)
            effects.applyRegionMask(region?.0, rect: region?.1 ?? .zero)
            let clip = widget.clippingShape.flatMap(placed)
            effects.applyClippingShape(clip?.0, rect: clip?.1 ?? .zero)
        }
        applySilhouette()
        videoSurface?.update(in: self, scene: scene, video: currentSnapshot.video,
                             controller: videoController?())
    }

    /// **A right-click on the skin's visualization or video rect opens that surface's own menu.**
    ///
    /// Both surfaces are click-through by design — 51 corpus skins wire an `onClick` on the
    /// `<EFFECTS>` node and 21 on `<VIDEO>`, and those handlers are the scene's, not the overlay's
    /// — so the event arrives here and the widget frames are what decide. **For video this is the
    /// only route to subtitles and audio-track selection**: the picture is parked in a window that
    /// takes no mouse events, and the command bar carrying those controls is switched off in a
    /// skin, so without this there is no way to turn a subtitle on. **Anywhere else the host's own
    /// menu**, which is the floor under a window the skin has put out of reach.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let video = videoSurface?.menu(at: point) { return video }
        for view in widgetViews.values {
            guard let effects = view as? WMPEffectsSurfaceView, effects.frame.contains(point) else { continue }
            return effects.buildMenu()
        }
        // **Everywhere else the host's own menu, so a `.wmz` window is never a dead end.** This
        // answered nil for four phases on the reasoning that a skin draws its own controls and its
        // own menus, and that holds right up until those controls are somewhere the pointer cannot
        // reach: a `.wmz` window is borderless and has no titlebar, so a skin that sized itself
        // off a 2560x1440 decoder put its close, zoom and resize art past the screen edge with
        // nothing left to recover the window with. Reported on `Combat_Flight_Simulator_3`
        // 2026-09-19 as "a massive window with no right click context controls" — the size half is
        // `WMPSize.fitted(within:)` and this is the floor under it. `Snap To Default` and `Exit`
        // are the two rows that matter here, and it is the same menu Classic's own main window
        // shows: `buildMenu` already suppresses the compact-mode rows for `.wmp`, whose skins own
        // their views. The skin still wins wherever it has something of its own to show.
        return ContextMenuBuilder.buildMenu(includeOutputDevices: false, includeRepeatShuffle: false)
    }

    override func mouseMoved(with event: NSEvent) {
        updateResizeCursor(convert(event.locationInWindow, from: nil))
        updateHover(event)
    }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { setHover(nil) }

    // Opening an auxiliary window must not consume the next skin control click just for focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let scene else { return }
        let point = skinPoint(from: event, sceneSize: scene.canvasSize)
        let target = interactiveTarget(at: point)
        #if DEBUG
        if ProcessInfo.processInfo.environment["WMP_CLICK_TRACE"] == "1" {
            let raw = hitTester?.hitTest(point)
            NSLog("[wmp/click] at %.0f,%.0f raw=%@#%@ state=%@ interactive=%@",
                  point.x, point.y, raw?.kind ?? "-", raw.map { $0.nodeID ?? "\($0.stableID)" } ?? "-",
                  raw.map { "\(interaction.visualState(for: $0.stableID))" } ?? "-",
                  target == nil ? "NO" : "yes")
        }
        #endif
        // **A control the host has greyed out is still a control, and the window does not move
        // under it (W154).** `interactiveTarget` answers nil for a disabled target exactly as it
        // does for bare artwork, and everything below reads that as "no control here" — so pressing
        // a greyed transport button dragged the whole player. Reported on `portals/mode1`, where a
        // press on play with an empty playlist moved the window from `680,279` to `374,509`;
        // `refreshHostState` disables every transport child while `player.controls.play` is
        // unavailable, which is most of the corpus's five-button `<BUTTONGROUP>`s on a cold start.
        // An `enabled="false"` authored in the markup is *not* this case and still drags: those
        // never reach the hit tester at all, which is what keeps `portals`' own 305x400
        // `main_button` backdrop draggable.
        // A control a binding has switched off is the same case, and is not in `hitTest` at all:
        // `KungFuChaos`' speaker button with SRS WOW off dragged the docked group and outlined it.
        if target == nil, hitTester?.hitTest(point) != nil
            || hitTester?.isGreyedOutControl(at: point) == true { return }
        // The edge band is consulted only where hit testing found no control, so a button sitting
        // against the window edge keeps every pixel it had. **The window claims this first**, and
        // for a real drag it is the only path that runs — see `WMPSkinWindow.sendEvent`. What is
        // left here is a press AppKit delivered to the view anyway, which is the same gesture.
        if target == nil, beginEdgeBandResize(at: event.locationInWindow) { return }
        guard let target else { beginWindowDrag(event); return }
        capturedTarget = target
        if isSlider(target) { onSliderCaptureChanged?(true, target.stableID) }
        notify(interaction.press(target))
        onScriptEvent?("mousedown", target.nodeID, target.stableID)
        window?.makeFirstResponder(self)
        if case .beginScan = target.action { onAction?(target.action!, nil) }
        if isSlider(target) { performSlider(target, event: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if !resizeEdges.isEmpty { dragWindowResize(); return }
        if isDraggingWindow { dragWindow(event); return }
        guard let capturedTarget else { return }
        if isSlider(capturedTarget) { performSlider(capturedTarget, event: event) }
        updateHover(event)
    }

    override func mouseUp(with event: NSEvent) {
        // **The bracket's tail is the last word on the release, not the first (W225).** It used to
        // be raised here, at the top — and the release then fell straight through into the ordinary
        // control path below, whose `mouseup`/`click` dispatch *cancels the transaction in flight*.
        // The unpin lost that race, so `playerView` stayed pinned `left`/`top` and both drawers
        // stayed pinned to the edges they had ridden, for the rest of the session: the body stopped
        // following the window while the drawers kept tracking its corner, which is a player drawn
        // small in the top-left with its two drawers stranded out at the far edges. Raised from a
        // `defer`, the resume is dispatched last and is the transaction that survives. The grip
        // authors no `onClick` (19 of the corpus's 235 `view.size` calls author anything at all),
        // so what it supersedes is a binding-only pass.
        var resumeScriptResize = false
        defer { if resumeScriptResize { onScriptResizeEnded?() } }
        if !resizeEdges.isEmpty {
            resumeScriptResize = endWindowResize()
            // **A grip the skin owns is still a control (W193).** An edge-band drag starts on bare
            // artwork and has nothing to release, but `view.size('bottomright')` is called from a
            // real element's `onMouseDown` — so the press is captured, and returning here would
            // leave that element drawn pressed for good and skip its `onMouseUp`/`onClick`. With a
            // target captured the release runs exactly as it does for any other control.
            if capturedTarget == nil { return }
        }
        if isDraggingWindow { finishWindowDrag(); return }
        guard let scene else { return }
        let releasePoint = skinPoint(from: event, sceneSize: scene.canvasSize)
        var target = interactiveTarget(at: releasePoint)
        // **A press changes the artwork the release is tested against (W306).** A control's hit area is
        // the sprite it is drawing, and the press swaps that sprite: `xsn_sports`' drawer tab is a
        // 19x13 `hoverImage` that is opaque edge to edge over a 13x7 `image`/`downImage` arrow, so a
        // press on the hover sprite's margin released over nothing and raised no `onClick` — the
        // drawer "sometimes" opened, depending on the pixel. A release inside the pressed control's
        // own rectangle, where no other control answers, is a release over it.
        if target == nil, let capturedTarget, capturedTarget.frame.contains(releasePoint),
           hitTester?.hitTest(releasePoint) == nil {
            target = capturedTarget
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["WMP_CLICK_TRACE"] == "1" {
            let p = releasePoint
            NSLog("[wmp/click] UP at %.0f,%.0f over=%@ captured=%@ dragging=%@",
                  p.x, p.y, target.map { $0.nodeID ?? "\($0.stableID)" } ?? "-",
                  capturedTarget.map { $0.nodeID ?? "\($0.stableID)" } ?? "-",
                  isDraggingWindow ? "YES" : "no")
        }
        #endif
        let result = interaction.release(over: target)
        notify(result.changed)
        defer { capturedTarget = nil; pendingSeek = nil }
        if let capturedTarget, isSlider(capturedTarget), let release = onSliderRelease {
            #if DEBUG
            wmpSeekTrace("release \(capturedTarget.nodeID ?? "-")#\(capturedTarget.stableID) "
                + "value=\(String(describing: widgetValues[capturedTarget.stableID])) "
                + "pendingSeek=\(String(describing: pendingSeek))")
            #endif
            release(capturedTarget.stableID, capturedTarget.nodeID,
                    widgetValues[capturedTarget.stableID] ?? 0, pendingSeek)
        } else {
            // No controller listening — a test, or a view being torn down. The gesture's seek has
            // nowhere to be arbitrated against the skin's own handlers, so send it plainly.
            if let pendingSeek { onAction?(.seek, pendingSeek) }
            onScriptEvent?("mouseup", capturedTarget?.nodeID, capturedTarget?.stableID)
        }
        guard let capturedTarget else { return }
        // **`onDragEnd` is the seek commit** (W55). It is authored only on `SLIDER` (125 uses) and
        // `CUSTOMSLIDER` (16), and 111 of those 141 sources are
        // `player.controls.currentPosition = value` — the skin scrubs the thumb during the drag and
        // commits the seek once, on release. Raised for a captured slider whether or not the
        // pointer moved, because a press and release on a slider track is a completed drag in WMP:
        // `performSlider` already ran on `mouseDown` and moved the value there.
        if isSlider(capturedTarget), onSliderRelease == nil {
            onScriptEvent?("dragend", capturedTarget.nodeID, capturedTarget.stableID)
        }
        if case .beginScan = capturedTarget.action { onAction?(.endScan, nil); return }
        guard result.activated == capturedTarget.stableID else { return }
        onScriptEvent?("click", capturedTarget.nodeID, capturedTarget.stableID)
        // The handler raised above already issues this element's own command where the skin spelled
        // it out, and posting it here as well is one press acting twice — a `<NEXTELEMENT>` that
        // skips two tracks. `WMPTransportAction.handlerOwnsAction` holds the rule and its reach.
        guard let action = capturedTarget.action, !capturedTarget.handlerOwnsAction,
              action != .seek, action != .volume, action != .balance else { return }
        onAction?(action, nil)
    }

    override func cancelOperation(_ sender: Any?) {
        cancelInputCapture()
    }

    /// The controls a keystroke can be aimed at, in tab order.
    ///
    /// `tabStop="false"` is authored 544 times against `"true"`'s 170: a skin marks most of its
    /// controls out of the keyboard ring and leaves a handful in, and a ring built from every
    /// enabled control tabs through all of them instead.
    private func keyboardTargets(_ scene: WMPScene) -> [WMPHitTarget] {
        scene.hits.filter(\.tabStop).flatMap { hit in hit.mappingTargets.isEmpty
            ? [WMPHitTarget(stableID: hit.stableID, nodeID: hit.nodeID, kind: hit.kind,
                frame: hit.frame, action: hit.action, sticky: hit.sticky, enabled: hit.enabled,
                handlerOwnsAction: hit.handlerOwnsAction)]
            : hit.mappingTargets }.filter(\.enabled)
    }

    /// Offer a keystroke to the skin, focused control first and then the view, and answer whether
    /// one of them authored a handler for it (W53).
    ///
    /// **The focused control or the view, never both.** A skin hangs its hotkeys on the `<VIEW>`
    /// (400 of the corpus's key handlers) and its stepping on the control (321 on a slider, 209 on
    /// a button); raising the same keystroke on both would run a global hotkey alongside the
    /// control's own handling of the same press, which is the double action this ordering exists to
    /// prevent. So the focused control is asked first and the view answers what it declines.
    private func skinHandled(_ event: NSEvent, named name: String, focused: WMPHitTarget?) -> Bool {
        let code = WMPVirtualKeyCode.keyDown(keyCode: event.keyCode,
                                             charactersIgnoringModifiers: event.charactersIgnoringModifiers)
        #if DEBUG
        if ProcessInfo.processInfo.environment["WMP_CLICK_TRACE"] == "1" {
            NSLog("[wmp/key] %@ mac=%d vk=%@ focused=%@ wired=%d", name, Int(event.keyCode),
                  code.map(String.init) ?? "-", focused?.nodeID ?? "-", onKeyEvent == nil ? 0 : 1)
        }
        #endif
        guard let onKeyEvent, let code else { return false }
        if let focused, onKeyEvent(name, focused.nodeID, focused.stableID, code) { return true }
        return onKeyEvent(name, "view", nil, code)
    }

    /// **Claim the keyboard for the window, so a skin's key handlers can be reached at all.**
    ///
    /// Until this, the view took first responder on `mouseDown` and nowhere else, so a window that
    /// had never been clicked received no key event and every one of the corpus's 1,052 key
    /// handlers was unreachable — the same hole `.wal` had until Phase 43, and it hides a working
    /// dispatch site completely: verifying W53 on `Age_of_Mythology_MP7` printed nothing at all
    /// until a click went in first.
    ///
    /// Safe to take on arrival because `keyDown` is a fall-through: menu equivalents go through
    /// `performKeyEquivalent` first, and a key neither the skin nor a focused control consumes is
    /// handed back to the responder chain, which is where it went when the view had no focus. It is
    /// only taken when nothing in this window holds it, so a hosted `<EDITBOX>` or playlist surface
    /// that has been clicked into keeps it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.firstResponder as? NSView == nil else { return }
        window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let scene else { return super.keyDown(with: event) }
        let targets = keyboardTargets(scene)
        // **Tab stays the engine's, ahead of the skin.** It is the focus ring rather than a key a
        // skin acts on, and no corpus handler compares `VK_TAB` at all — the codes they switch over
        // are the arrows, space, Return and the letter hotkeys. A skin swallowing Tab would strand
        // the keyboard on whichever control happened to hold focus.
        if event.keyCode == 48, !targets.isEmpty {
            let current = targets.firstIndex { $0.stableID == interaction.focusedNode } ?? -1
            let delta = event.modifierFlags.contains(.shift) ? -1 : 1
            let next = (current + delta + targets.count) % targets.count
            notify(interaction.focus(targets[next].stableID)); return
        }
        let focused = targets.first { $0.stableID == interaction.focusedNode }
        // **The skin before the built-ins.** See `onKeyEvent`: the arrow stepping and the space /
        // Return activation below exist because nothing used to raise the skin's own handlers, and
        // running both is one keypress acting twice.
        if skinHandled(event, named: "keydown", focused: focused) { return }
        guard let target = focused else {
            if visualizationHandled(event) { return }
            return super.keyDown(with: event)
        }
        if event.keyCode == 49 || event.keyCode == 36 {
            // Same rule as `mouseUp`: where the element's own handler issues its command, the
            // handler is the click and the action must not be posted alongside it.
            if let action = target.action, !target.handlerOwnsAction { onAction?(action, nil) }
            else { onScriptEvent?("click", target.nodeID, target.stableID) }
            return
        }
        if [123, 124, 125, 126].contains(event.keyCode), target.kind.lowercased().contains("slider") {
            let widget = scene.widgets.first { $0.stableID == target.stableID }
            let minimum = widget?.minimumValue ?? 0, maximum = widget?.maximumValue ?? 100
            let old = widgetValues[target.stableID] ?? minimum
            let step = max(1, (maximum - minimum) / 100)
            let value = max(minimum, min(maximum, old + ([124, 126].contains(event.keyCode) ? step : -step)))
            widgetValues[target.stableID] = value
            onElementValueChanged?(target.stableID, target.nodeID, value); return
        }
        if visualizationHandled(event) { return }
        super.keyDown(with: event)
    }

    /// The release half. **`onkeyup` had a dispatch site before it had a name** — `WMPMainView`
    /// already raised it for an `<EDITBOX>`'s text — and with the name absent from
    /// `WMPAttributeValue.handlerNames` every one of those handlers was classified `.literal` and
    /// never found. Authored 100 times across 33 archives, and every one of them compares `13`:
    /// it is the corpus's "the user pressed Return in the search box" edge.
    override func keyUp(with event: NSEvent) {
        guard let scene else { return super.keyUp(with: event) }
        let focused = keyboardTargets(scene).first { $0.stableID == interaction.focusedNode }
        if skinHandled(event, named: "keyup", focused: focused) { return }
        super.keyUp(with: event)
    }

    /// The skin has refused the key: offer it to a hosted `<EFFECTS>` surface, which answers the
    /// same visualization keys as NullPlayer's own window. A skin's focused control always goes
    /// first — a slider's arrows are the slider's.
    private func visualizationHandled(_ event: NSEvent) -> Bool {
        widgetViews.values.compactMap { $0 as? WMPEffectsSurfaceView }
            .contains { $0.handleKeyDown(event) }
    }

    override func accessibilityChildren() -> [Any]? {
        guard let scene else { return [] }
        return scene.hits.flatMap { hit -> [NSAccessibilityElement] in
            let targets = hit.mappingTargets.isEmpty
                ? [WMPHitTarget(stableID: hit.stableID, nodeID: hit.nodeID, kind: hit.kind,
                    frame: hit.frame, action: hit.action, sticky: hit.sticky, enabled: hit.enabled,
                    handlerOwnsAction: hit.handlerOwnsAction)]
                : hit.mappingTargets
            return targets.compactMap { target in
                let element = NSAccessibilityElement()
                element.setAccessibilityIdentifier("wmp.\(target.nodeID ?? String(target.stableID))")
                let widget = scene.widgets.first { $0.stableID == target.stableID }
                element.setAccessibilityLabel(widget?.label ?? target.action.map(Self.label(for:)) ?? target.kind)
                element.setAccessibilityRole(target.kind.lowercased().contains("slider") ? .slider : .button)
                element.setAccessibilityEnabled(target.enabled && interaction.visualState(for: target.stableID) != .disabled)
                element.setAccessibilityParent(self)
                element.setAccessibilityFrame(screenRect(for: target.frame))
                return element
            }
        } + scene.widgets.filter { $0.kind == .text }.map { widget in
            let element = NSAccessibilityElement()
            element.setAccessibilityIdentifier("wmp.\(widget.nodeID ?? String(widget.stableID))")
            element.setAccessibilityLabel(widget.label); element.setAccessibilityRole(.staticText)
            element.setAccessibilityParent(self); element.setAccessibilityFrame(screenRect(for: widget.frame))
            return element
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let scene, scene.canvasSize.width > 0, scene.canvasSize.height > 0 else { return }
        let xScale = bounds.width / scene.canvasSize.width
        let yScale = bounds.height / scene.canvasSize.height
        // Back to front, so a control on top wins the overlap — the same order hit testing walks,
        // read the other way. AppKit resolves the last rect added for a point.
        for hit in scene.hits {
            guard hit.enabled, let cursor = hit.cursor else { continue }
            // A clip that misses the frame is a fully hidden control, not an unconfined one.
            guard let visible = hit.clipRect.map({ hit.frame.intersection($0) }) ?? hit.frame,
                  !visible.isEmpty else { continue }
            addCursorRect(NSRect(x: visible.x * xScale, y: visible.y * yScale,
                                 width: visible.width * xScale, height: visible.height * yScale),
                          cursor: Self.cursor(for: cursor))
        }
    }

    private static func cursor(for cursor: WMPCursor) -> NSCursor {
        switch cursor {
        case .system: return .arrow
        case .hand: return .pointingHand
        case .sizeAll: return .openHand
        case .sizeWE: return .resizeLeftRight
        case .sizeNS: return .resizeUpDown
        // macOS ships no public diagonal resize cursor, so the nearest honest answer is the axis
        // the drag mostly runs along rather than an invented bitmap.
        case .sizeNWSE, .sizeNESW: return .crosshair
        }
    }

    private func updateHover(_ event: NSEvent) {
        guard let scene else { return }
        setHover(interactiveTarget(at: skinPoint(from: event, sceneSize: scene.canvasSize)))
    }

    /// Move the hover to `target`, repaint the artwork, and raise the two authored edges.
    ///
    /// `onmouseover`/`onmouseout` are edges, not states: a skin fades a readout in on entry and
    /// back out on exit (`alx_dl.wms` does exactly that with `volumeText` and `seekText`), so a
    /// pointer crossing from one control straight to another must raise the exit on the node it
    /// left *before* the entry on the node it reached. Nothing is raised while the pointer stays
    /// inside the same node — every mouse-moved event would otherwise be a script transaction.
    private func setHover(_ target: WMPHitTarget?) {
        guard hoveredTarget?.stableID != target?.stableID else { return }
        let previous = hoveredTarget
        hoveredTarget = target
        notify(interaction.move(over: target))
        if let previous { onScriptEvent?("mouseout", previous.nodeID, previous.stableID) }
        if let target { onScriptEvent?("mouseover", target.nodeID, target.stableID) }
    }

    private func interactiveTarget(at point: WMPPoint) -> WMPHitTarget? {
        guard let target = hitTester?.hitTest(point),
              interaction.visualState(for: target.stableID) != .disabled else { return nil }
        return target
    }

    private func performSlider(_ target: WMPHitTarget, event: NSEvent) {
        guard let scene else { return }
        let point = skinPoint(from: event, sceneSize: scene.canvasSize)
        let widget = scene.widgets.first { $0.stableID == target.stableID }
        let minimum = widget?.minimumValue ?? 0, maximum = widget?.maximumValue ?? 100
        // **The drag runs along the axis the skin authored.** `direction="vertical"` outnumbers
        // horizontal 1,312 to 664 in the corpus — every equaliser band is one — and measuring those
        // along `frame.width` gave a 9 px-wide bar's full range in nine pixels of sideways travel.
        // The same `WMPSliderMetrics` the scene placed the thumb with reads the pointer back, so
        // the thumb lands under the cursor instead of beside it.
        let metrics = WMPSliderMetrics(direction: widget?.direction ?? .horizontal,
            minimum: minimum, maximum: maximum, value: widget?.value ?? minimum,
            borderSize: widget?.borderSize ?? 0)
        // A `CUSTOMSLIDER` reads its value out of its own `positionImage` — the pixel under the
        // pointer *is* the fraction — which is the whole point of the element: its track need not
        // be a straight line. Everything else uses the linear metrics that placed its thumb.
        let map = scene.hits.first { $0.stableID == target.stableID }?.positionMap
        let mapped = map?.fraction(at: point, in: target.frame)
        let value = mapped.map { minimum + $0 * (maximum - minimum) }
            ?? metrics.value(at: point, in: target.frame, thumbSize: widget?.thumbSize ?? .zero)
        let span = maximum - minimum
        let fraction = span == 0 ? 0 : (value - minimum) / span
        // A skin that binds its slider's `value` to a host property has said where that control
        // writes; honour the binding it declared rather than requiring a semantic tag. 163 corpus
        // skins drive volume, seek and the ten equaliser bands entirely this way.
        if let action = target.action ?? widget?.valueBindingPath.flatMap(WMPTransportAction.boundAction) {
            switch action {
            case .balance: onAction?(action, .number(fraction * 2 - 1))
            // Held for the release rather than sent. `mouseUp` is the only place a `.seek` leaves
            // this view, and 89 corpus sliders reach it the same way whether they name themselves
            // `<SEEKSLIDER>` or bind `value` to `player.controls.currentPosition` (W156).
            case .seek: pendingSeek = .number(fraction)
            case .volume: onAction?(action, .number(fraction))
            default: onAction?(action, .number(value))
            }
        }
        if target.kind.lowercased().contains("slider") {
            widgetValues[target.stableID] = value
            #if DEBUG
            wmpSeekTrace("performSlider \(target.nodeID ?? "-") mapped=\(String(describing: mapped)) "
                + "min=\(minimum) max=\(maximum) value=\(value)")
            #endif
            onElementValueChanged?(target.stableID, target.nodeID, value)
        }
        onScriptEvent?("change", target.nodeID, target.stableID)
    }

    private func synchronizeWidgetViews(_ widgets: [WMPWidget]) {
        // **The skin draws its own controls; an overlay is for what the scene genuinely cannot
        // paint.** `.video` left this list because `WMPVideoPlaceholderView` filled its frame with
        // opaque black over the artwork of every skin that authors a `<VIDEO>` — 167 of 178 — and
        // an audio player has no video to put there instead (W9) — which stopped being true when
        // `Windows/VideoPlayer` landed, so W102 is conditional hosting rather than a placeholder.
        // `.equalizer` left it because `EQUALIZERSETTINGS` is no longer a widget at all: the skin's
        // own bound sliders are the equaliser.
        //
        // **`.effects` reaches the whole corpus now that `<EFFECTS>` is a kind (W101).** It used
        // to reach five archives: `WMPElementKind` mapped `wmpeffects` and not `effects`, so the
        // 166 of 177 that spell the tag the other way fell to `.unknown` and were never widgets.
        //
        // **A widget its container has faded out is not hosted at all.** `alphaBlend` inherits, and
        // the scene's paint commands have honoured that since they were filtered at `emit` — but a
        // hosted `NSView` is not a paint command, so `Plus! Bionic Dot`'s `<subview id="visMask"
        // alphaBlend="0">` correctly drew no artwork while the `<EFFECTS>` inside it put a 169x160
        // visualizer over the face. Dropping the view rather than setting `alphaValue = 0` is what
        // stops an invisible `WMPEffectsSurfaceView` from running a GL engine and a 30fps readback
        // for a pane the user has not opened; `toggleVis()` fades the mask back up, the scene is
        // rebuilt, and the surface is created again. Cerulean's `<effects>` has no `alphaBlend`
        // above it, reads 1, and is hosted exactly as before.
        let native = widgets.filter { [WMPWidgetKind.playlist, .dropdownPlaylist, .popup,
                                       .editBox, .listBox, .effects].contains($0.kind)
            && $0.alpha > 0 }
        let wanted = Set(native.map(\.stableID))
        let widgetIDs = Set(widgets.map(\.stableID))
        widgetValues = widgetValues.filter { widgetIDs.contains($0.key) }
        for (id, view) in widgetViews where !wanted.contains(id) {
            #if DEBUG
            wmpWidgetTrace("drop id=\(id) \(type(of: view))")
            #endif
            view.removeFromSuperview(); widgetViews[id] = nil }
        for widget in native where widgetViews[widget.stableID] == nil {
            let view: NSView
            switch widget.kind {
            case .playlist: view = WMPPlaylistSurfaceView()
            case .dropdownPlaylist: view = WMPDropdownPlaylistSurfaceView(frame: .zero, pullsDown: false)
            case .popup: view = WMPPopupSurfaceView(frame: .zero)
            case .editBox: view = WMPEditBoxSurfaceView()
            // A `<LISTBOX>` is a playlist chooser the skin fills from script, out of
            // `player.playlistCollection` — the library browser's selected source (W136).
            case .listBox: view = WMPListBoxSurfaceView()
            case .effects: view = WMPEffectsSurfaceView(frame: .zero)
            default: continue
            }
            view.toolTip = widget.toolTip
            view.setAccessibilityIdentifier("wmp.\(widget.nodeID ?? String(widget.stableID))")
            view.setAccessibilityLabel(widget.label)
            if let actionable = view as? WMPPlaylistSurfaceView {
                actionable.onAction = onAction
                actionable.onPlayLibrary = { [weak self] playlist, row in
                    self?.onPlayLibraryTracks?(playlist, row)
                }
            }
            if let playlist = view as? WMPPlaylistSurfaceView, let surfaceStyle {
                playlist.apply(style: surfaceStyle)
            }
            if let actionable = view as? WMPDropdownPlaylistSurfaceView { actionable.onAction = onAction }
            if let popup = view as? WMPPopupSurfaceView {
                let stableID = widget.stableID, nodeID = widget.nodeID
                popup.onSelect = { [weak self] index, title in
                    // The skin's handler reads `selectedItem`, so the element has to hold it before
                    // the event is raised — and the preset is applied through the host either way,
                    // because `selectedItem_onchange` is not yet a dispatched event (W51).
                    self?.onElementValueChanged?(stableID, nodeID, Double(index))
                    self?.onAction?(.setEQPreset(index), .string(title))
                    self?.onScriptEvent?("change", nodeID, stableID)
                }
            }
            if let edit = view as? WMPEditBoxSurfaceView {
                let stableID = widget.stableID, nodeID = widget.nodeID
                edit.onEdit = { [weak self] text in
                    self?.onElementTextChanged?(stableID, nodeID, text)
                    self?.onScriptEvent?("keyup", nodeID, stableID)
                }
                edit.onReturn = { [weak self] text in
                    self?.onElementTextReturn?(stableID, nodeID, text)
                }
                edit.onFocusChange = { [weak self] focused in
                    self?.onScriptEvent?(focused ? "focus" : "blur", nodeID, stableID)
                }
            }
            if let list = view as? WMPListBoxSurfaceView {
                let stableID = widget.stableID, nodeID = widget.nodeID
                list.onSelect = { [weak self] index in
                    self?.onListSelected?(stableID, nodeID, index)
                }
                list.onDoubleClick = { [weak self] index in
                    self?.onListDoubleClicked?(stableID, nodeID, index)
                }
            }
            #if DEBUG
            wmpWidgetTrace("create id=\(widget.stableID) kind=\(widget.kind) frame=\(widget.frame)")
            #endif
            widgetViews[widget.stableID] = view; addSubview(view)
            let stableID = widget.stableID
            (view as? WMPPopupSurfaceView)?.update(items: lastListItems[stableID] ?? [])
            (view as? WMPListBoxSurfaceView)?.update(items: lastListItems[stableID] ?? [])
            (view as? WMPPlaylistSurfaceView)?.update(libraryRows: lastWidgetState.playlists[stableID])
            (view as? WMPListBoxSurfaceView)?.update(selection: lastWidgetState.listSelections[stableID])
            (view as? WMPEditBoxSurfaceView)?.update(scriptValue: lastWidgetState.editValues[stableID])
        }
        // A partial fade is a real state in the corpus — `Plus! Plasma Ball` hangs its effects off
        // a `alphaBlend="110"` layer — so the surviving surfaces carry their inherited alpha, and
        // it is re-applied on every sync because a fade changes it without recreating the view.
        for widget in native { widgetViews[widget.stableID]?.alphaValue = widget.alpha }
        overlayView.frame = bounds
        enforceLayerOrder()
        onSpectrumDemandChanged?(native.contains { $0.kind == .effects })
        layoutSubtreeIfNeeded()
        refreshHostState(currentSnapshot)
    }

    private func notify(_ changed: Set<Int>) {
        guard !changed.isEmpty else { return }
        onInteractionChanged?(interaction, changed)
    }

    // MARK: Resizing a borderless skin window

    /// The band, in view points, that counts as an edge. Wide enough to hit on a shaped window and
    /// narrow enough that it is only ever reached where no control is.
    private static let resizeBandWidth: CGFloat = 6

    private func edges(at point: NSPoint) -> WMPWindowEdges {
        guard scene?.isResizable == true else { return [] }
        return marginEdges(at: point)
    }

    /// The margin as pure geometry: no permission asked, no skin state read.
    ///
    /// Separate from `edges(at:)` because the two have different jobs. That one decides whether a
    /// press *resizes*; this one decides whether AppKit may be allowed anywhere near the press at
    /// all, and the answer to that is never — a `.wmz` window's frame is this engine's, whatever
    /// the view happens to permit. See `WMPSkinWindow.sendEvent`.
    private func marginEdges(at point: NSPoint) -> WMPWindowEdges {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let band = Self.resizeBandWidth
        var edges: WMPWindowEdges = []
        if point.x <= band { edges.insert(.left) }
        if point.x >= bounds.maxX - band { edges.insert(.right) }
        // The view is flipped, so its y grows downward while the window's grows upward.
        if point.y <= band { edges.insert(.top) }
        if point.y >= bounds.maxY - band { edges.insert(.bottom) }
        return edges
    }

    /// **The resize a skin asks for itself (W193).** `view.size('bottomright')` is the corpus's
    /// standard grip — 235 calls in 88 of the 185 installed archives — and on a borderless `.wmz`
    /// window it is the only resize there is: the user has no OS frame to grab, so a dead call
    /// sends them to the macOS window edge, which skips whatever the skin wraps around its own
    /// resize (`Compact`'s `DoSize()` pins both drawers for the duration).
    ///
    /// It runs the same drag the edge band runs, rather than a loop of its own, so the clamp
    /// against the view's `minWidth`/`maxWidth`, the anchored edge and the relayout are one
    /// implementation. Two gates are the whole of what it adds:
    ///
    /// - `scene.isResizable`, the permission the edge band already asks for. All 88 archives
    ///   author `resizAble="true"`, so this costs the corpus nothing and stops a view with no
    ///   authored maximum from being dragged open without one.
    /// - **The button must still be down.** The call arrives from an asynchronous script
    ///   transaction, so a quick click's command can land after the release; arming the drag then
    ///   would resize the window on whatever the user pressed next.
    /// Answers whether a drag actually started. The caller needs to know: with `view.size` blocking
    /// in WMP, the rest of the handler is held until the release (W225), and a call that starts no
    /// drag has no release coming — so a `false` here is the signal to run that tail at once rather
    /// than strand the skin mid-bracket.
    @discardableResult
    func beginScriptResize(corner: String) -> Bool {
        // **The band's own call, arriving back (W227).** An edge-band press raises the grip's
        // handler, so this call is the one the band asked for and there is already a drag under the
        // pointer. Refusing it would answer `false`, and `false` is the caller's signal that no
        // release is coming — the held tail would run at once, mid-drag, against the size the
        // window started at, which is the stranded bracket W225 exists to prevent. The drag keeps
        // the edges the user is actually pulling rather than the corner the markup names: the grip
        // is not where the pointer is.
        if isEdgeBandResize, !resizeEdges.isEmpty {
            wmpResizeTrace("beginScriptResize ADOPTED corner=\(corner) edges=\(resizeEdges)")
            return true
        }
        guard resizeEdges.isEmpty, scene?.isResizable == true,
              NSEvent.pressedMouseButtons & 1 != 0 else {
            wmpResizeTrace("beginScriptResize REFUSED corner=\(corner) "
                + "inDrag=\(!resizeEdges.isEmpty) resizable=\(scene?.isResizable == true) "
                + "button=\(NSEvent.pressedMouseButtons & 1 != 0)")
            return false
        }
        let edges = Self.edges(forCorner: corner)
        guard !edges.isEmpty else { return false }
        beginWindowResize(edges)
        isScriptResize = true
        wmpResizeTrace("beginScriptResize corner=\(corner) edges=\(edges)")
        return true
    }

    /// The seven spellings the corpus authors, read as the substrings they are: `bottomright` (86
    /// archives), `topright` (4), `right` (3), and `bottom`/`bottomleft`/`left`/`topleft` (2 each).
    /// An edge word is matched rather than the whole string compared, so `bottomright` is both of
    /// its halves and a corner WMP defines that nothing here has seen still resolves.
    static func edges(forCorner corner: String) -> WMPWindowEdges {
        let corner = corner.lowercased()
        var edges: WMPWindowEdges = []
        if corner.contains("left") { edges.insert(.left) }
        if corner.contains("right") { edges.insert(.right) }
        if corner.contains("top") { edges.insert(.top) }
        if corner.contains("bottom") { edges.insert(.bottom) }
        return edges
    }

    /// Which of the view's grips an edge-band drag should raise.
    ///
    /// A view authors up to seven (`Revert` has the most), and they differ only in the corner they
    /// name — the statements after the call are the same handler, so any of them runs the bracket.
    /// The one whose corner shares an edge with the drag is preferred anyway, because a handler
    /// that reads its own corner reads the one nearest what the user is pulling; the frontmost is
    /// the fallback, which is what a drag on a plain left or top edge gets.
    private func grip(for edges: WMPWindowEdges) -> WMPResizeGrip.Grip? {
        resizeGrips.first { !Self.edges(forCorner: $0.corner).isDisjoint(with: edges) }
            ?? resizeGrips.first
    }

    /// **Claim a press on the window edge, and hand the skin its own bracket around it (W227).**
    ///
    /// Answers whether the press started a resize. The edge of a borderless `.wmz` window is an
    /// affordance this engine adds: WMP offers only the grip the skin draws in its corner, so no
    /// handler in the corpus anticipates a drag that starts anywhere else, and what a bare edge
    /// drag skipped is the *rest* of that grip handler. 69 of the 87 archives authoring
    /// `view.size` run something after the call, and in 68 of them it is one idiom —
    /// `saveVidSize()` / `onVidSetSize()` / `g_fUserHasSized = true`, persisting the size the user
    /// just dragged to. Pulled by the edge, the window resized and the skin forgot it the moment
    /// the view closed; `Compact`'s `DoSize()` is the other kind, and left both drawers behind.
    ///
    /// So the band raises the view's own grip handler exactly as a press on the grip does, W225's
    /// machinery holds the tail, and the release replays it against the size the window finished
    /// at. **Only the handler, not a press**: no target is captured and `interaction` is not told,
    /// so the grip is never drawn pressed by a drag that never touched it.
    @discardableResult
    func beginEdgeBandResize(at windowPoint: NSPoint) -> Bool {
        let edges = edges(at: convert(windowPoint, from: nil))
        guard !edges.isEmpty else { return false }
        beginWindowResize(edges)
        isEdgeBandResize = true
        if let grip = grip(for: edges) {
            wmpResizeTrace("edge-band press edges=\(edges) grip=\(grip.nodeID ?? "-")"
                + "#\(grip.stableID) corner=\(grip.corner)")
            isScriptResize = true
            onScriptEvent?("mousedown", grip.nodeID, grip.stableID)
        } else {
            wmpResizeTrace("edge-band press edges=\(edges) — the view authors no grip")
        }
        return true
    }

    /// **A new press means no earlier drag survives, and one that did cost the application (W235).**
    ///
    /// `beginScriptResize` arms a resize from a *script transaction*, which is asynchronous: the
    /// skin's grip calls `view.size('bottomright')` out of its `onMouseDown` and the call arrives
    /// back some milliseconds later. The `pressedMouseButtons` gate refuses an arm whose button has
    /// already come up, but it cannot refuse one that lands in the gap between that check and the
    /// release — and an arm with no release coming leaves `resizeEdges` set for the rest of the
    /// session. Everything downstream then reads as a drag in flight: `claimsEdgeBandResize`
    /// declines every later press on the window edge, which before the margin rule in
    /// `WMPSkinWindow.sendEvent` handed that press to AppKit's modal resize loop and wedged the
    /// whole application.
    ///
    /// AppKit cannot deliver two `mouseDown`s without a `mouseUp` between them, so a press is proof
    /// that nothing is in flight. Called before either band rule reads the state it would strand.
    func discardStaleResize() {
        guard !resizeEdges.isEmpty else { return }
        wmpResizeTrace("discarding stale resize edges=\(resizeEdges) script=\(isScriptResize) "
            + "band=\(isEdgeBandResize) — a press arrived with a drag still armed")
        resizeEdges = []
        isScriptResize = false
        isEdgeBandResize = false
    }

    /// Whether this window point is inside the resize margin at all, **whatever is drawn there**.
    ///
    /// The companion to `claimsEdgeBandResize`, and the two answer different questions on purpose:
    /// that one asks *should this press resize*, this one asks *would AppKit take this press if we
    /// let it through*. `WMPSkinWindow.sendEvent` needs both, because a press the band declines is
    /// still a press AppKit's frame will claim for its own modal resize loop (W235) — so the
    /// margin is taken whole and routed by us, rather than half-taken and half-surrendered.
    func isInsideResizeBand(at windowPoint: NSPoint) -> Bool {
        !marginEdges(at: convert(windowPoint, from: nil)).isEmpty
    }

    /// Whether a press at this window point is the band's rather than a control's. Asked by
    /// `WMPSkinWindow.sendEvent` before AppKit is given the event, because a control drawn against
    /// the window edge keeps every pixel it had.
    func claimsEdgeBandResize(at windowPoint: NSPoint) -> Bool {
        guard let scene, resizeEdges.isEmpty else { return false }
        let point = skinPoint(fromWindowPoint: windowPoint, sceneSize: scene.canvasSize)
        guard interactiveTarget(at: point) == nil, hitTester?.hitTest(point) == nil else { return false }
        return !edges(at: convert(windowPoint, from: nil)).isEmpty
    }

    /// Whether a press at this window point is the invisible close target's. Asked by
    /// `WMPSkinWindow.sendEvent` ahead of the edge band.
    func claimsCloseTarget(at windowPoint: NSPoint) -> Bool {
        guard closeTargetEnabled, let scene, resizeEdges.isEmpty else { return false }
        let local = convert(windowPoint, from: nil)
        guard local.x >= bounds.maxX - Self.closeTargetSize, local.x <= bounds.maxX,
              local.y >= bounds.minY, local.y <= bounds.minY + Self.closeTargetSize else { return false }
        let point = skinPoint(fromWindowPoint: windowPoint, sceneSize: scene.canvasSize)
        return interactiveTarget(at: point) == nil && hitTester?.hitTest(point) == nil
            && hitTester?.isGreyedOutControl(at: point) != true
    }

    /// One step of a resize in flight, from either path.
    func continueWindowResize() { dragWindowResize() }

    /// Ends a resize in flight and answers whether a held handler tail is waiting to be replayed.
    @discardableResult
    func endWindowResize() -> Bool {
        let held = isScriptResize
        wmpResizeTrace("release script=\(held) band=\(isEdgeBandResize) "
            + "size=\(window?.frame.size ?? .zero)")
        isScriptResize = false
        isEdgeBandResize = false
        resizeEdges = []
        return held
    }

    private func beginWindowResize(_ edges: WMPWindowEdges) {
        guard let window else { return }
        resizeEdges = edges
        resizeStartFrame = window.frame
        resizeStartMouse = NSEvent.mouseLocation
    }

    /// Tracked in screen coordinates on purpose: dragging a left or top edge moves the window's
    /// origin, which moves `locationInWindow` under a stationary pointer and makes the drag run
    /// away from the cursor.
    private func dragWindowResize() {
        guard let window, let limits = scene?.resizeLimits else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - resizeStartMouse.x, dy = mouse.y - resizeStartMouse.y
        var width = resizeStartFrame.width, height = resizeStartFrame.height
        if resizeEdges.contains(.right) { width += dx }
        if resizeEdges.contains(.left) { width -= dx }
        if resizeEdges.contains(.top) { height += dy }
        if resizeEdges.contains(.bottom) { height -= dy }
        let clamped = limits.clamp(WMPSize(width: width, height: height))
        // The anchored edge is the one not being dragged, so it must not move when the clamp bites.
        var frame = resizeStartFrame
        frame.size = NSSize(width: clamped.width, height: clamped.height)
        if resizeEdges.contains(.left) { frame.origin.x = resizeStartFrame.maxX - clamped.width }
        if resizeEdges.contains(.bottom) { frame.origin.y = resizeStartFrame.maxY - clamped.height }
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    private func updateResizeCursor(_ point: NSPoint) {
        let edges = edges(at: point)
        if edges.isEmpty {
            if scene != nil { NSCursor.arrow.set() }
            return
        }
        // AppKit publishes no diagonal resize cursor, so a corner takes the axis it is widest in.
        let horizontal = edges.contains(.left) || edges.contains(.right)
        (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
    }

    private func beginWindowDrag(_ event: NSEvent) {
        guard let window else { return }
        isDraggingWindow = true; dragStart = event.locationInWindow
        WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
    }

    private func dragWindow(_ event: NSEvent) {
        guard let window else { return }
        let current = event.locationInWindow
        var origin = window.frame.origin
        origin.x += current.x - dragStart.x; origin.y += current.y - dragStart.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    private func finishWindowDrag() {
        isDraggingWindow = false
        if let window { WindowManager.shared.windowDidFinishDragging(window) }
    }

    private func screenRect(for frame: WMPRect) -> NSRect {
        guard let scene, let window else { return .zero }
        let local = NSRect(x: frame.x * bounds.width / scene.canvasSize.width,
                           y: frame.y * bounds.height / scene.canvasSize.height,
                           width: frame.width * bounds.width / scene.canvasSize.width,
                           height: frame.height * bounds.height / scene.canvasSize.height)
        return window.convertToScreen(convert(local, to: nil))
    }

    private static func isSlider(_ action: WMPTransportAction) -> Bool { action == .seek || action == .volume || action == .balance }
    private func isSlider(_ target: WMPHitTarget) -> Bool {
        target.kind.lowercased().contains("slider") || target.action.map(Self.isSlider(_:)) == true
    }
    private static func isDown(_ action: WMPTransportAction, _ snapshot: WMPHostSnapshot) -> Bool {
        switch action {
        case .toggleMute: return snapshot.muted
        case .toggleShuffle: return snapshot.shuffle
        case .toggleRepeat: return snapshot.repeatMode
        default: return false
        }
    }
    private static func label(for action: WMPTransportAction) -> String {
        switch action {
        case .play: return "Play"; case .pause: return "Pause"; case .stop: return "Stop"
        case .previous: return "Previous"; case .next: return "Next"
        case .beginScan(.reverse): return "Rewind"; case .beginScan(.forward): return "Fast Forward"
        case .endScan: return "Stop Scanning"; case .seek: return "Seek"; case .volume: return "Volume"
        case .balance: return "Balance"; case .toggleMute: return "Mute"
        case .toggleShuffle: return "Shuffle"; case .toggleRepeat: return "Repeat"
        case .playPlaylistItem: return "Play playlist item"
        case .removePlaylistItem: return "Remove playlist item"
        case .movePlaylistItem: return "Move playlist item"
        case .setWOWEnabled: return "Enable WOW stereo widening"
        case .setTruBassLevel: return "TruBass strength"
        case .setSpeakerSize: return "Speaker size"
        case .setWOWLevel: return "WOW strength"
        case .setCrossFade: return "Crossfade between tracks"
        case .setCrossFadeWindow: return "Crossfade length"
        case .setNormalization: return "Level volume across tracks"
        case .setEQEnabled: return "Enable equalizer"
        case .setEQBand: return "Equalizer band"
        case .setEQPreset: return "Equalizer preset"
        case .setPreamp: return "Equalizer preamp"
        case .setEffectType, .nextEffect, .previousEffect: return "Visualization"
        case .setEffectPreset, .nextEffectPreset: return "Visualization preset"
        }
    }
}
