import AppKit
import CoreGraphics

/// Winamp's **thinger**: the scrolling strip of installed-component icons a `<componentbucket>`
/// draws, the caption beside it (`<text display="componentbucket">`), and the `CB_*` buttons that
/// scroll it. Clicking an icon opens that component's window.
///
/// Winamp fills the strip from whatever components are *installed* — each plugin publishes its own
/// icon. NullPlayer has no plugins, so the set is the fixed one below: the components this engine can
/// actually show through `routeComponentToggle`. Everything here is deliberately pure and
/// view-independent, so the harness can measure a bucket without a window (B34).
///
/// Corpus demand, measured 2026-08-23 over all 40 `.wal`s: 14 skins declare a bucket — 12 as a
/// thinger (`CB_NEXT`/`CB_PREV`), 2 as config-drawer paging (`CB_*PAGE`). Every one of them drew an
/// empty box with a blank caption before this existed.
struct WinampModernBucketIcon: Equatable {
    let kind: WinampModernComponentKind
    /// What the bucket's caption reads while this icon has the focus — Winamp's own component names.
    let title: String
}

enum WinampModernComponentBucketCatalog {
    /// The published icon set, in Winamp's own thinger order: the player's own windows first, then
    /// the two plugin surfaces.
    ///
    /// `.other` is never in it — a bucket is a launcher, and an icon that opens nothing is worse than
    /// no icon. The equalizer is: Winamp defines no EQ component GUID (see
    /// `WinampModernComponentRegistry.canonicalGUID`), but `TOGGLE guid:eq` reaches a real window
    /// here, which is all an icon needs.
    static let icons: [WinampModernBucketIcon] = [
        WinampModernBucketIcon(kind: .playlist, title: "Playlist Editor"),
        WinampModernBucketIcon(kind: .equalizer, title: "Equalizer"),
        WinampModernBucketIcon(kind: .library, title: "Media Library"),
        WinampModernBucketIcon(kind: .visualization, title: "Visualization"),
        WinampModernBucketIcon(kind: .video, title: "Video"),
    ]

    /// Draw one icon's glyph, centred in its box.
    ///
    /// Vector, not artwork: no `.wal` ships thinger icons (in Winamp they come from the *components*,
    /// not the skin), so the alternative to drawing them is the empty strip this replaces. Stroke
    /// weight follows the box so a 12px thinger and a 32px one both read.
    static func draw(_ icon: WinampModernBucketIcon, in rect: CGRect, color: NSColor,
                     context: CGContext) {
        guard rect.width > 3, rect.height > 3 else { return }
        let box = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
        let line = max(1, (min(box.width, box.height) / 12).rounded())
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(line)
        context.setLineCap(.square)
        switch icon.kind {
        case .playlist: drawPlaylist(in: box, line: line, context: context)
        case .equalizer: drawEqualizer(in: box, line: line, context: context)
        case .library: drawLibrary(in: box, line: line, context: context)
        case .visualization: drawVisualization(in: box, context: context)
        case .video: drawVideo(in: box, line: line, context: context)
        // No bucket icon: the waveform seeker is a strip a skin places itself, never an entry in
        // a component bucket's picker.
        case .waveformSeeker, .other: break
        }
        context.restoreGState()
    }

    /// A framed list: the playlist editor.
    private static func drawPlaylist(in box: CGRect, line: CGFloat, context: CGContext) {
        context.stroke(box.insetBy(dx: line / 2, dy: line / 2))
        let inner = box.insetBy(dx: box.width * 0.22, dy: box.height * 0.25)
        for step in 0..<3 {
            let y = inner.minY + inner.height * CGFloat(step) / 2
            context.fill(CGRect(x: inner.minX, y: y, width: inner.width, height: line))
        }
    }

    /// Three sliders at different settings: the equalizer.
    private static func drawEqualizer(in box: CGRect, line: CGFloat, context: CGContext) {
        let positions: [CGFloat] = [0.65, 0.3, 0.5]
        for (index, position) in positions.enumerated() {
            let x = box.minX + box.width * (CGFloat(index) * 0.35 + 0.15)
            context.fill(CGRect(x: x - line / 2, y: box.minY, width: line, height: box.height))
            let knobY = box.minY + box.height * position
            context.fill(CGRect(x: x - box.width * 0.11, y: knobY - line,
                                width: box.width * 0.22, height: line * 2))
        }
    }

    /// A stack of spines: the media library.
    private static func drawLibrary(in box: CGRect, line: CGFloat, context: CGContext) {
        context.stroke(box.insetBy(dx: line / 2, dy: line / 2))
        for step in 1..<3 {
            let x = box.minX + box.width * CGFloat(step) / 3
            context.fill(CGRect(x: x - line / 2, y: box.minY, width: line, height: box.height))
        }
    }

    /// Analyzer bars: the visualization plugin.
    private static func drawVisualization(in box: CGRect, context: CGContext) {
        let heights: [CGFloat] = [0.45, 0.85, 0.6, 1.0]
        let step = box.width / CGFloat(heights.count)
        for (index, height) in heights.enumerated() {
            let width = max(1, step * 0.6)
            let barHeight = box.height * height
            context.fill(CGRect(x: box.minX + step * CGFloat(index) + (step - width) / 2,
                                y: box.maxY - barHeight, width: width, height: barHeight))
        }
    }

    /// A screen with a play triangle: the video window.
    private static func drawVideo(in box: CGRect, line: CGFloat, context: CGContext) {
        let screen = CGRect(x: box.minX, y: box.minY + box.height * 0.12,
                            width: box.width, height: box.height * 0.76)
        context.stroke(screen.insetBy(dx: line / 2, dy: line / 2))
        let play = screen.insetBy(dx: screen.width * 0.3, dy: screen.height * 0.25)
        context.beginPath()
        context.move(to: CGPoint(x: play.minX, y: play.minY))
        context.addLine(to: CGPoint(x: play.maxX, y: play.midY))
        context.addLine(to: CGPoint(x: play.minX, y: play.maxY))
        context.closePath()
        context.fillPath()
    }
}

/// The box arithmetic of one `<componentbucket>`: where each icon sits and how many fit.
///
/// A value type with no reference to the graph, in the shape `WasabiColorThemeListState` uses — the
/// attributes are read once at construction and everything after that is geometry.
struct WinampModernComponentBucketLayout: Equatable {
    /// Winamp's thinger icons are 32×32. A bucket taller than that (Styx's is 35, Media_Whore's 33)
    /// centres them rather than stretching them into a shape no icon has.
    static let maximumIconExtent: CGFloat = 32

    let frame: CGRect
    let isVertical: Bool
    let spacing: CGFloat
    /// Both margins are along the **scroll axis**, which is what Winamp's `leftmargin`/`rightmargin`
    /// mean on a vertical bucket too (Lobe's switch layout is the measured one).
    let leadingMargin: CGFloat
    let trailingMargin: CGFloat

    init(object: WasabiObject, frame: CGRect) {
        self.frame = frame
        isVertical = ["1", "true", "yes"].contains(object.attributes["vertical"]?.lowercased() ?? "")
        spacing = Self.number(object.attributes["spacing"]) ?? 0
        // Negative margins are real and deliberate — mmd3's shade buckets use `leftmargin="-3"` to
        // pull the strip out past its box — so they are not clamped to zero.
        leadingMargin = Self.number(object.attributes["leftmargin"]) ?? 0
        trailingMargin = Self.number(object.attributes["rightmargin"]) ?? 0
    }

    private static func number(_ raw: String?) -> CGFloat? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), let value = Double(raw) else {
            return nil
        }
        return CGFloat(value)
    }

    /// The length of the strip along the scroll axis, margins removed.
    var axisLength: CGFloat {
        max(0, (isVertical ? frame.height : frame.width) - leadingMargin - trailingMargin)
    }

    /// Icons are square, sized by the box's *cross* axis.
    var iconExtent: CGFloat {
        let cross = isVertical ? frame.width : frame.height
        return max(0, min(cross, Self.maximumIconExtent))
    }

    /// How many icons the box shows at once. At least one whenever an icon fits at all: a 40×25
    /// thinger (Lobe) is narrower than one icon plus its margins, and showing nothing there would be
    /// the empty strip again.
    var visibleCount: Int {
        let extent = iconExtent
        guard extent > 0, axisLength > 0 else { return 0 }
        let stride = extent + spacing
        guard stride > 0 else { return 0 }
        return max(1, Int((axisLength + spacing) / stride))
    }

    /// The box of the `slot`-th icon currently on screen (0 is the leftmost/topmost).
    func iconRect(slot: Int) -> CGRect {
        let extent = iconExtent
        let offset = leadingMargin + CGFloat(slot) * (extent + spacing)
        if isVertical {
            return CGRect(x: frame.minX + (frame.width - extent) / 2, y: frame.minY + offset,
                          width: extent, height: extent)
        }
        return CGRect(x: frame.minX + offset, y: frame.minY + (frame.height - extent) / 2,
                      width: extent, height: extent)
    }

    /// Which visible slot a point falls in, or nil when it is outside the box or between icons.
    func slot(at point: CGPoint) -> Int? {
        guard frame.contains(point) else { return nil }
        for slot in 0..<visibleCount where iconRect(slot: slot).contains(point) { return slot }
        return nil
    }
}

/// Which icon the thinger is pointing at and how far the strip is scrolled.
///
/// **Skin-wide, not per object.** One skin has one thinger however many layouts draw it — Mini_Me_2
/// declares ten (`skin1thinger`…, one per variant) and mmd3 three (normal plus both shades), and a
/// user who scrolls to the Media Library in one shape expects to find it there in the next. It lives
/// on `WasabiSkinRuntime`, the one object every container of a loaded skin shares.
final class WinampModernComponentBucketState {
    let icons = WinampModernComponentBucketCatalog.icons
    /// Index of the first icon on screen.
    private(set) var offset = 0
    /// The icon whose name the caption reads — the one under the pointer, else the first on screen.
    private(set) var focusedIndex = 0

    var focusedTitle: String {
        icons.indices.contains(focusedIndex) ? icons[focusedIndex].title : ""
    }

    func clampedOffset(_ value: Int, visibleCount: Int) -> Int {
        max(0, min(max(0, icons.count - max(1, visibleCount)), value))
    }

    /// `CB_NEXT` / `CB_PREV` (`delta` ±1) and `CB_NEXTPAGE` / `CB_PREVPAGE` (a whole screenful).
    /// Returns whether anything moved, so a caller can skip the repaint at either end of the strip.
    @discardableResult
    func scroll(by delta: Int, visibleCount: Int) -> Bool {
        let next = clampedOffset(offset + delta, visibleCount: visibleCount)
        guard next != offset else { return false }
        offset = next
        // Scrolling with no pointer over the strip (a `CB_*` button) has to move the caption too, or
        // the name beside the thinger describes an icon that has scrolled away.
        focusedIndex = next
        return true
    }

    @discardableResult
    func focus(_ index: Int) -> Bool {
        guard icons.indices.contains(index), index != focusedIndex else { return false }
        focusedIndex = index
        return true
    }
}
