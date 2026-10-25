import CoreGraphics
import CoreText
import Foundation

/// One line of Sonique's lettering: its left at `x`, on `baseline`, `spacing` extra points between
/// letters (the menu's right column is letter-spaced), in `font` (Verdana Bold unless a screen
/// measured otherwise), shaped by `matrix` (NullPlayer's wordmark leans and widens).
struct SoniqueSkinText: Equatable {
    var string: String, x: Int, baseline: Int, size: CGFloat, colour: SoniqueColour
    var spacing: CGFloat = 0
    var font = "Verdana-Bold"
    var matrix = CGAffineTransform.identity

    var width: Double {
        CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed(ink: SoniqueSkinRenderer.cgColor(0))),
                                   nil, nil, nil)
    }

    func offset(_ dx: Int, _ dy: Int) -> SoniqueSkinText {
        var text = self
        text.x += dx
        text.baseline += dy
        return text
    }

    /// Centred on `centreX`, but starting no further left than its `x`: a long title keeps its start.
    func centred(on centreX: Int) -> SoniqueSkinText {
        var text = self
        text.x = max(x, centreX - Int((width / 2).rounded()))
        return text
    }

    func attributed(ink: CGColor, outline: CGColor? = nil) -> NSAttributedString {
        Self.lettering(string, size: size, spacing: spacing, font: font, matrix: matrix, ink: ink, outline: outline)
    }

    static func lettering(_ string: String, size: CGFloat, spacing: CGFloat = 0, font: String = "Verdana-Bold",
                          matrix: CGAffineTransform = .identity, ink: CGColor,
                          outline: CGColor? = nil) -> NSAttributedString {
        var matrix = matrix
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, &matrix),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
            NSAttributedString.Key(kCTKernAttributeName as String): spacing,
        ]
        if let outline {
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = outline
            // Negative: fill and stroke, the stroke 4 % of the size (about Sonique's 1 px on its logo).
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -4
        }
        return NSAttributedString(string: string, attributes: attributes)
    }
}

extension SoniqueSkinPainter {
    /// `t` in its skin colour.
    func text(_ t: SoniqueSkinText) {
        draw(t.attributed(ink: colour(t.colour)), x: t.x, baseline: t.baseline, lettering: true)
    }

    /// Sonique's own `lettering`: Verdana Bold on the skin pixel grid, grey-smoothed as Sonique drew
    /// it in the navigator and mid mode and unsmoothed in small mode's tiny bar (the oracle sweep,
    /// 2026-10-18: smoothing made 2,826 navigator and 8,605 mid pixels right, and 34,405 small ones
    /// wrong). Otherwise artwork, such as NullPlayer's wordmark, and drawn smooth.
    func draw(_ string: NSAttributedString, x: Int, baseline: Int, lettering: Bool) {
        context.saveGState()
        if lettering {
            context.setShouldAntialias(scene.state.mode != .small)
            context.setShouldSmoothFonts(false)
        }
        // Text draws upright in an unflipped space: undo the flip around the baseline.
        context.textMatrix = .identity
        context.translateBy(x: CGFloat(x), y: CGFloat(baseline))
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
        context.restoreGState()
    }

    /// The playing title scrolling from `idle.x` to `right` (`marquee`), or with none `idle` centred
    /// on `centreX`.
    func titleLine(_ idle: SoniqueSkinText, centreX: Int, right: Int) {
        guard !host.title.isEmpty else { return text(idle.centred(on: centreX)) }
        var title = idle
        title.string = host.title
        marquee(title, right: right)
    }

    /// `t` from its `x` to `right`, always scrolling: `scene.state.marqueeOffset` px left, coming round
    /// again after a gap (or after the whole span, for a title shorter than it), cut to the span.
    /// Always, not only when too long: a skin's own art can cover any part of the line (the sonique
    /// skin's rocker hides the status line's right end), so "fits" cannot be measured.
    func marquee(_ t: SoniqueSkinText, right: Int) {
        let left = t.x
        let period = max(Int(t.width.rounded(.up)) + SoniqueSkinScene.marqueeGap, right - left)
        var shown = t
        shown.x = left - scene.state.marqueeOffset % period
        context.saveGState()
        context.clip(to: CGRect(x: left, y: t.baseline - Int(t.size * 2), width: right - left, height: Int(t.size * 3)))
        text(shown)
        shown.x += period
        text(shown)
        context.restoreGState()
    }

    /// `t`'s string broken into lines no wider than `width`, at word breaks where it can and anywhere
    /// where it cannot (a file name is often one long word).
    func wrapped(_ t: SoniqueSkinText, width: CGFloat) -> [String] {
        let typesetter = CTTypesetterCreateWithAttributedString(t.attributed(ink: SoniqueSkinRenderer.cgColor(0)))
        let text = t.string as NSString
        var lines: [String] = [], start = 0
        while start < text.length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if count <= 0 { count = max(1, CTTypesetterSuggestClusterBreak(typesetter, start, Double(width))) }
            lines.append(text.substring(with: NSRange(location: start, length: count)).trimmingCharacters(in: .whitespaces))
            start += count
        }
        return lines
    }
}
