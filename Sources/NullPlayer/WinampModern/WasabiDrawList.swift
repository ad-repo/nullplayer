import AppKit
import CoreGraphics
import CoreText

/// What the scene renderer draws into: every call recorded, with the values it was handed, and
/// replayed into a real context later.
///
/// **This is what lets a `.wal` frame rasterize off the main thread.** The renderer reads the live
/// object graph, the host and its own caches on every draw, and scripts mutate all of them on the
/// main thread, so the *walk* has to stay there. The pixels do not: the walk records here, and
/// `WinampModernCanvas` replays the list into the window's bitmap on its own queue. The harness's
/// `draw(in:)` replays synchronously, which is what makes the corpus sweep a check of this class —
/// a byte-identical sweep means every op replays exactly as it drew.
///
/// **An op captures values, never references to mutable state.** `CGImage`, `CGColor`, `CTLine`,
/// rects and copied paths are immutable; a closure that captured the renderer or a `WasabiObject`
/// would race the next script tick on the replaying thread.
///
/// The method names are `CGContext`'s, so the renderer's drawing code reads as it always did. The
/// state the renderer reads *back* — the CTM for pixel snapping and prescale sizes, the clip's bounds
/// for text, the interpolation quality — is tracked here, and answers what the replay context would
/// answer at the same point.
final class WasabiDrawList {
    typealias Op = (CGContext) -> Void
    /// Swaps a bitmap for one already in the replay context's colour space.
    typealias ImageMatcher = (CGImage) -> CGImage

    /// Each op with the replay's matcher passed in, so nothing replay-scoped lives on the list.
    private var steps: [(CGContext, ImageMatcher) -> Void] = []

    private struct State {
        var ctm: CGAffineTransform
        /// Device space, like `CGContext`'s own clip.
        var clip: CGRect
        var interpolationQuality: CGInterpolationQuality
    }

    private var state: State
    private var saved: [State] = []
    private let initialClip: CGRect
    /// The current path's bounds in device space, for `clip()` — `CGContext` transforms a path's
    /// points by the CTM as they are added, so this does too.
    private var pathBounds = CGRect.null

    /// How many real device pixels one unit of the replay context's device space is (B80). A bitmap
    /// context's device space *is* its pixels, so this is 1 there — the canvas, the harness. A
    /// layer-backed view records `draw` into a display list at CTM 1.0 and has it replayed at the
    /// backing scale, so a list replayed there carries the backing factor, or the pixel grid
    /// `snappedToPixelGrid` aims at is a point, not a pixel.
    let devicePixelsPerUnit: CGFloat

    /// `ctm` and `clip` (device space) are the replay context's own at the moment the replay starts.
    init(ctm: CGAffineTransform, clip: CGRect,
         interpolationQuality: CGInterpolationQuality = .default, devicePixelsPerUnit: CGFloat = 1) {
        state = State(ctm: ctm, clip: clip, interpolationQuality: interpolationQuality)
        initialClip = clip
        self.devicePixelsPerUnit = devicePixelsPerUnit
    }

    /// `matchImage`, when given, swaps each bitmap for one already in the replay context's colour
    /// space (`WinampModernCanvas.matched`).
    func replay(into context: CGContext, matchImage: @escaping ImageMatcher = { $0 }) {
        for step in steps { step(context, matchImage) }
    }

    /// For a draw that needs a real context: run on the replaying thread, with the replay context.
    /// The closure must capture only immutable values.
    func record(_ op: @escaping Op) { append(op) }

    /// An op that never touches a bitmap.
    private func append(_ op: @escaping Op) { steps.append { context, _ in op(context) } }

    // MARK: State the renderer reads back

    var ctm: CGAffineTransform { state.ctm }
    /// Real device pixels per user-space unit along x, here in the walk.
    var deviceScale: CGFloat { abs(state.ctm.a) * devicePixelsPerUnit }

    var boundingBoxOfClipPath: CGRect {
        state.clip.isNull ? .null : state.clip.applying(state.ctm.inverted())
    }

    var interpolationQuality: CGInterpolationQuality {
        get { state.interpolationQuality }
        set {
            state.interpolationQuality = newValue
            append { $0.interpolationQuality = newValue }
        }
    }

    // MARK: Graphics state

    func saveGState() {
        saved.append(state)
        append { $0.saveGState() }
    }

    func restoreGState() {
        if let last = saved.popLast() { state = last }
        append { $0.restoreGState() }
    }

    func translateBy(x: CGFloat, y: CGFloat) {
        state.ctm = state.ctm.translatedBy(x: x, y: y)
        append { $0.translateBy(x: x, y: y) }
    }

    func scaleBy(x: CGFloat, y: CGFloat) {
        state.ctm = state.ctm.scaledBy(x: x, y: y)
        append { $0.scaleBy(x: x, y: y) }
    }

    func concatenate(_ transform: CGAffineTransform) {
        state.ctm = transform.concatenating(state.ctm)
        append { $0.concatenate(transform) }
    }

    func setAlpha(_ alpha: CGFloat) { append { $0.setAlpha(alpha) } }
    func setBlendMode(_ mode: CGBlendMode) { append { $0.setBlendMode(mode) } }
    func setShouldAntialias(_ value: Bool) { append { $0.setShouldAntialias(value) } }
    func setLineWidth(_ width: CGFloat) { append { $0.setLineWidth(width) } }
    func setLineCap(_ cap: CGLineCap) { append { $0.setLineCap(cap) } }

    func setFillColor(_ color: CGColor) { append { $0.setFillColor(color) } }
    func setFillColor(gray: CGFloat, alpha: CGFloat) { append { $0.setFillColor(gray: gray, alpha: alpha) } }
    func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        append { $0.setFillColor(red: red, green: green, blue: blue, alpha: alpha) }
    }
    func setStrokeColor(_ color: CGColor) { append { $0.setStrokeColor(color) } }

    // MARK: Clipping

    func clip(to rect: CGRect) {
        narrowClip(to: rect.applying(state.ctm))
        append { $0.clip(to: rect) }
    }

    func clip(to rects: [CGRect]) {
        narrowClip(to: rects.reduce(CGRect.null) { $0.union($1.applying(state.ctm)) })
        append { $0.clip(to: rects) }
    }

    func clip(to rect: CGRect, mask: CGImage) {
        narrowClip(to: rect.applying(state.ctm))
        append { $0.clip(to: rect, mask: mask) }
    }

    /// Clips to the current path, which it consumes.
    func clip(using rule: CGPathFillRule = .winding) {
        narrowClip(to: pathBounds)
        pathBounds = .null
        append { $0.clip(using: rule) }
    }

    func resetClip() {
        state.clip = initialClip
        append { $0.resetClip() }
    }

    private func narrowClip(to rect: CGRect) {
        state.clip = state.clip.intersection(rect)
    }

    // MARK: Paths

    func beginPath() {
        pathBounds = .null
        append { $0.beginPath() }
    }

    func move(to point: CGPoint) {
        addToPath(point)
        append { $0.move(to: point) }
    }

    func addLine(to point: CGPoint) {
        addToPath(point)
        append { $0.addLine(to: point) }
    }

    func addRect(_ rect: CGRect) {
        pathBounds = pathBounds.union(rect.applying(state.ctm))
        append { $0.addRect(rect) }
    }

    func addPath(_ path: CGPath) {
        let path = path.copy() ?? path
        pathBounds = pathBounds.union(path.boundingBoxOfPath.applying(state.ctm))
        append { $0.addPath(path) }
    }

    func closePath() { append { $0.closePath() } }

    func fillPath(using rule: CGPathFillRule = .winding) {
        pathBounds = .null
        append { $0.fillPath(using: rule) }
    }

    func strokePath() {
        pathBounds = .null
        append { $0.strokePath() }
    }

    private func addToPath(_ point: CGPoint) {
        pathBounds = pathBounds.union(CGRect(origin: point.applying(state.ctm), size: .zero))
    }

    // MARK: Drawing

    func fill(_ rect: CGRect) { append { $0.fill(rect) } }
    func fill(_ rects: [CGRect]) { append { $0.fill(rects) } }
    func fillEllipse(in rect: CGRect) { append { $0.fillEllipse(in: rect) } }
    func stroke(_ rect: CGRect) { append { $0.stroke(rect) } }
    func stroke(_ rect: CGRect, width: CGFloat) { append { $0.stroke(rect, width: width) } }
    func strokeEllipse(in rect: CGRect) { append { $0.strokeEllipse(in: rect) } }
    func clear(_ rect: CGRect) { append { $0.clear(rect) } }

    func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
        steps.append { context, match in context.draw(match(image), in: rect, byTiling: byTiling) }
    }

    func drawLinearGradient(_ gradient: CGGradient, start: CGPoint, end: CGPoint,
                            options: CGGradientDrawingOptions) {
        append { $0.drawLinearGradient(gradient, start: start, end: end, options: options) }
    }

    /// `CTLineDraw` at `position`, which is where it leaves the text position.
    func draw(line: CTLine, at position: CGPoint) {
        append { context in
            context.textPosition = position
            CTLineDraw(line, context)
        }
    }

    /// A draw that goes through AppKit — `NSString.draw`, `NSBezierPath` — which takes its
    /// destination from `NSGraphicsContext.current`, never from a context it is handed. On replay that
    /// is bound to the replay context, on the replaying thread (`current` is per thread), for the
    /// length of `body`. `body` must capture only immutable values.
    func drawWithAppKit(_ body: @escaping () -> Void) {
        append { context in
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            body()
            NSGraphicsContext.current = previous
        }
    }
}
