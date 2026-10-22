import AppKit

/// How a `.wal` window gets its pixels: recorded on the main thread, rasterized off it.
///
/// The scene walk reads the live object graph, so it stays on the main thread and records into a
/// `WasabiDrawList` (`record`). Rasterizing that list, which is most of a frame's cost, runs on the
/// window's own serial queue into its `WinampModernCanvas`, at device resolution. The finished picture
/// is the view's layer `contents` (`present`), so showing it costs the main thread nothing: no backing
/// store, no display-list replay, no colour match. The replay of a copied picture measured 15.7% of
/// cPro Bento's main thread in Device RGB, 8.8% in the window's own space.
///
/// - **Every invalidation asks for a frame.** `request(_:)` keeps the rect and schedules a pump for
///   the end of the runloop turn, so a burst of script writes is recorded once.
/// - **One frame in flight.** Dirt that arrives while a frame renders waits, and is recorded fresh
///   when that frame lands. A frame never renders from a stale recording, and frames never queue
///   up behind a slow one.
/// - **A new canvas is drawn on the main thread, whole.** A new `target` — a resize, a move to
///   another display, a UI Size change — renders synchronously, so the window never shows a picture
///   of the wrong size. A frame still in flight then lands behind it and is dropped: frames are
///   presented strictly in order. Steady-state repaints (meters, readouts, slides) take the queue.
final class WinampModernFrames {
    /// The canvas a frame is drawn for: the view's bounds in device pixels, in the window's space.
    struct Geometry: Equatable {
        let pixelWidth: Int
        let pixelHeight: Int
        /// Canvas pixels per view point.
        let scale: CGFloat
        let colorSpace: CGColorSpace

        var pixelBounds: CGRect { CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight) }
    }

    /// Where the window's pixels come from.
    enum Target: Equatable {
        /// Nothing to draw on: the view has no area.
        case idle
        case canvas(Geometry)
        /// Too large for a canvas: the view draws itself (`drawDirectly`).
        case direct

        var geometry: Geometry? {
            if case .canvas(let geometry) = self { return geometry }
            return nil
        }
    }

    private let canvas = WinampModernCanvas()
    private let queue = DispatchQueue(label: "NullPlayer.WinampModernCanvas", qos: .userInteractive)
    /// The scene for `rects` (canvas pixels), recorded on the main thread.
    private let record: (Geometry, [CGRect]) -> WinampModernCanvas.Job
    /// Show a frame that landed, with the rects it redrew in view points.
    private let present: (WinampModernCanvas.Frame, [NSRect]) -> Void

    var target: Target = .idle {
        // A frame in flight across a change was drawn for a canvas the window has left.
        didSet { if target != oldValue { generation += 1 } }
    }
    var drawsDirectly: Bool { target == .direct }
    /// The newest outline a frame reported, for the drop shadow (`WinampModernMainView+Shadow`).
    private(set) var outline: CGImage?

    /// Whether anyone can see the window, from its occlusion (`WinampModernMainView`).
    ///
    /// A skin's hidden windows kept painting. Their scripts run whether or not anyone can see them —
    /// WMP11-BlueVU's never-opened *VU Meters Small* re-warped both needles ~100 times a second — and
    /// AppKit still displays an ordered-out window that has been invalidated. Measured on a release
    /// build with *VU Meters Large* open and music playing: main-thread busy **81.4% → 48.3%**, and
    /// `CGDisplayListDrawInContextDelegate` 19.0% → 0.0%.
    ///
    /// **Cached** from the occlusion notification rather than asked per call: this is read on every
    /// script notification, thousands of times a second, and a first draft that asked the window
    /// each time cost 40% of the main thread on its own — more than the paint it saved.
    var isOnScreen = false {
        didSet {
            guard !isOnScreen, !pendingDirty.isEmpty else { return }
            pendingDirty = []
            owesWholeFrame = true
        }
    }
    /// Repaints skipped while hidden: the window redraws whole the next time it shows.
    var owesWholeFrame = false

    /// Rects owed a new frame, in view points.
    private var pendingDirty: [NSRect] = []
    private var isScheduled = false
    private var isInFlight = false
    /// The geometry the canvas was last drawn whole at; any other needs a whole frame.
    private var drawnGeometry: Geometry?
    /// Counts the changes of `target`. A frame in flight across one is not presented.
    private var generation = 0

    /// `WINAMP_MODERN_SYNC_FRAMES=1`: render every frame on the main thread. The A/B switch for "did
    /// rendering off the main thread cause this?".
    static let rendersSynchronously = ProcessInfo.processInfo.environment["WINAMP_MODERN_SYNC_FRAMES"] == "1"

    init(record: @escaping (Geometry, [CGRect]) -> WinampModernCanvas.Job,
         present: @escaping (WinampModernCanvas.Frame, [NSRect]) -> Void) {
        self.record = record
        self.present = present
    }

    /// Ask for `rect` (view points) to be redrawn at the end of this runloop turn. A hidden window
    /// keeps no dirt — a script repainting 30 times a second would otherwise grow the list for as
    /// long as it hides — and owes a whole frame instead.
    func request(_ rect: NSRect) {
        guard isOnScreen else {
            owesWholeFrame = true
            return
        }
        pendingDirty.append(rect)
        guard !isScheduled else { return }
        isScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isScheduled = false
            self?.pump()
        }
    }

    /// `layout()`'s pump: a new target's whole frame, before AppKit displays, so it lands in the
    /// transaction that resizes the layer. Partial dirt keeps to the end of the turn.
    func pumpNewCanvas() {
        if target.geometry != drawnGeometry { pump() }
    }

    /// Record a frame for the pending dirt and render it: whole and on the spot for a new canvas,
    /// on the queue otherwise, unless a frame is already there.
    private func pump() {
        guard let geometry = target.geometry else {
            pendingDirty = []
            return
        }
        guard !pendingDirty.isEmpty else { return }
        let isWhole = geometry != drawnGeometry
        // Partial dirt waits for the frame in flight; a new canvas cannot, or the window shows a
        // picture of the wrong size until it lands.
        guard isWhole || !isInFlight else { return }
        let whole = geometry.pixelBounds
        // Snapped out to whole device pixels, so a partial repaint's edges land on the grid the
        // canvas is drawn on. A new canvas is drawn whole: only the dirty rects would be filled.
        let rects = isWhole
            ? [whole]
            : Self.coalesced(pendingDirty.map {
                $0.applying(CGAffineTransform(scaleX: geometry.scale, y: geometry.scale)).integral.intersection(whole)
            }.filter { !$0.isNull && !$0.isEmpty })
        pendingDirty = []
        guard !rects.isEmpty else { return }
        let job = record(geometry, rects)
        let viewRects = rects.map { $0.applying(CGAffineTransform(scaleX: 1 / geometry.scale, y: 1 / geometry.scale)) }
        if isWhole || Self.rendersSynchronously {
            let frame = queue.sync { canvas.render(job) }
            if frame != nil { drawnGeometry = geometry }
            land(frame, rects: viewRects)
            return
        }
        isInFlight = true
        let canvas = canvas, generation = generation
        queue.async { [weak self] in
            let frame = canvas.render(job)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isInFlight = false
                if generation == self.generation { self.land(frame, rects: viewRects) }
                self.pump()
            }
        }
    }

    private func land(_ frame: WinampModernCanvas.Frame?, rects: [NSRect]) {
        guard let frame else { return }
        if let outline = frame.outline { self.outline = outline }
        present(frame, rects)
    }

    /// A turn's dirt without the rects another one already covers: the same meter box invalidated
    /// by every script write in the turn is one rect to draw, not twenty. Past a handful the bounding
    /// box is cheaper than the list.
    static func coalesced(_ rects: [CGRect]) -> [CGRect] {
        var kept: [CGRect] = []
        for rect in rects.sorted(by: { $0.width * $0.height > $1.width * $1.height })
        where !kept.contains(where: { $0.contains(rect) }) {
            kept.append(rect)
        }
        guard kept.count > 8 else { return kept }
        return [kept.dropFirst().reduce(kept[0]) { $0.union($1) }]
    }
}

extension WinampModernMainView {
    /// This view's frames. Unowned: they are the view's alone and never outlive it.
    func makeFrames() -> WinampModernFrames {
        WinampModernFrames(record: { [unowned self] geometry, rects in canvasJob(geometry, rects: rects) },
                           present: { [unowned self] frame, rects in present(frame, rects: rects) })
    }

    /// Size the canvas to the bounds and the window's backing. Every resize, display move and UI
    /// Size change comes through here; the whole frame it asks for is pumped by `layout()`
    /// (`pumpNewCanvas`), after the turn's other changes and before AppKit displays.
    func canvasGeometryDidChange() {
        guard !isTornDown else { return }
        let scale = window?.backingScaleFactor ?? 1
        let pixelWidth = Int((bounds.width * scale).rounded(.up)), pixelHeight = Int((bounds.height * scale).rounded(.up))
        let target: WinampModernFrames.Target
        if !WasabiSceneRenderer.fitsCanvas(pixelWidth: pixelWidth, pixelHeight: pixelHeight) {
            target = .direct
        } else if pixelWidth > 0, pixelHeight > 0 {
            target = .canvas(.init(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale,
                                   colorSpace: WinampModernCanvas.colorSpace(matching: window?.colorSpace?.cgColorSpace)))
        } else {
            target = .idle
        }
        if (target == .direct) != frames.drawsDirectly {
            if target == .direct { Self.logOversizedCanvasOnce(pixelWidth: pixelWidth, pixelHeight: pixelHeight) }
            layer?.contents = nil
            super.setNeedsDisplay(bounds)
        }
        frames.target = target
        needsLayout = true
        needsDisplay = true
    }

    private func present(_ frame: WinampModernCanvas.Frame, rects: [NSRect]) {
        guard let layer else { return }
        if frame.outline != nil { windowShadow.invalidateShape("draw") }
        if Self.paintRateProbe { recordPaint(rects) }
        // The picture is whole device pixels, so it can overhang the bounds by a fraction of one at
        // the top; pinned to the bottom-left it is never stretched.
        let scale = window?.backingScaleFactor ?? 1
        if layer.contentsScale != scale { layer.contentsScale = scale }
        if layer.contentsGravity != .bottomLeft { layer.contentsGravity = .bottomLeft }
        layer.contents = frame.picture
    }

    /// The scene recorded for `rects` (canvas pixels).
    private func canvasJob(_ geometry: WinampModernFrames.Geometry, rects: [CGRect]) -> WinampModernCanvas.Job {
        // Which of `activealpha`/`inactivealpha` every object paints at. Read here rather than
        // cached on the notification: a window can lose key without either notification reaching us
        // (the app deactivating, a sheet), and the read is one Boolean.
        renderer.isWindowActive = window?.isKeyWindow ?? true
        return renderer.canvasJob(pixelWidth: geometry.pixelWidth, pixelHeight: geometry.pixelHeight,
                                  scale: geometry.scale, rects: rects, colorSpace: geometry.colorSpace,
                                  skinScale: skinScale,
                                  pressed: pressedObject?.stableID, hovered: hoveredObject?.stableID,
                                  chrome: hostChrome)
    }

    /// A window too large for a canvas draws straight into AppKit's context, as a translucent layout
    /// once did. Its shadow keeps its last shape.
    func drawDirectly(in context: CGContext) {
        renderer.isWindowActive = window?.isKeyWindow ?? true
        // A display-list context arrives at CTM 1.0 and is replayed at the backing scale, a bitmap
        // one already carries it (B80).
        let contextScale = abs(context.ctm.a)
        let pixelsPerUnit = contextScale > 0 ? max(1, (window?.backingScaleFactor ?? 1) / contextScale) : 1
        renderer.drawDirectly(in: context, pressed: pressedObject?.stableID, hovered: hoveredObject?.stableID,
                              skinScale: skinScale, devicePixelsPerUnit: pixelsPerUnit,
                              chrome: hostChrome)
    }

    private static var oversizedCanvasLogged = false

    private static func logOversizedCanvasOnce(pixelWidth: Int, pixelHeight: Int) {
        guard !oversizedCanvasLogged else { return }
        oversizedCanvasLogged = true
        NSLog("[wal] canvas %dx%d is over the pixel limit; drawing the window directly", pixelWidth, pixelHeight)
    }
}
