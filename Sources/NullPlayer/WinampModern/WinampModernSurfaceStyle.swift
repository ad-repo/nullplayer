import AppKit

/// How NullPlayer's *own* AppKit-drawn surfaces look inside a `.wal` skin.
///
/// `WasabiPalette` answers "what colour is a list row"; this answers "what does the whole surface
/// look like". The difference matters because the surfaces we draw ourselves — the library embedded
/// in a skin's holder, and the playlist / equalizer / library windows we open when a skin declares
/// none — used to be painted by the *classic* renderer: `.wsz` sprite sheets, the 5×6 bitmap font,
/// and `skin.playlistColors` from whatever classic skin happened to be selected. Inside a Winamp 5.x
/// modern skin that is a foreign UI coloured by a skin the user is not even looking at.
///
/// So this type does two jobs:
///
/// 1. **Widens the palette into a chrome.** Real skins declare a partial colour set — three roles is
///    common — so bars, borders, dividers, and pressed states are *derived* by blending the roles a
///    skin does declare, rather than invented. A skin that names nothing at all still lands on
///    Winamp's own green-on-black through `WasabiPalette.fallback`.
/// 2. **Replaces the bitmap font.** `font(scale:)` returns a monospaced system font whose advance is
///    pinned to the classic cell width. That is the load-bearing choice in this whole change: the
///    views measure their own layout as `text.count * SkinElements.TextFont.charWidth * scale`, in
///    77 places in the browser alone, so matching the advance exactly keeps every one of those
///    computations valid without touching a single layout line.
///
/// A style is only ever non-nil in `winampModern` mode. Everywhere else the views run their existing
/// classic paths unchanged.
struct WinampModernSurfaceStyle: Equatable {
    // Roles taken straight from the skin.
    let background: NSColor
    let text: NSColor
    let currentText: NSColor
    let selectionBackground: NSColor
    let selectionText: NSColor
    let treeText: NSColor
    let treeSelection: NSColor

    // Roles derived by blending, so a partial palette still produces a coherent surface.
    /// Toolbars, tab strips, status bars — a step away from the content background.
    let barBackground: NSColor
    /// Window edges and bar separators.
    let border: NSColor
    /// Hairlines between rows and columns.
    let divider: NSColor
    /// Secondary text: counts, hints, disabled labels.
    let dimText: NSColor
    /// A button's fill while it is held down.
    let pressedFill: NSColor

    // MARK: - Derivation

    init(palette: WasabiPalette) {
        background = palette.contentBackground
        text = palette.listText
        currentText = palette.currentText
        selectionBackground = palette.selectionBackground
        selectionText = palette.selectionText
        treeText = palette.treeText
        treeSelection = palette.treeSelection

        // Every derived role is background↔text blend, never a fixed grey: on a light skin the
        // chrome has to get *darker* than the content, on a dark one lighter, and only the skin's
        // own two ends know which way that is.
        barBackground = Self.blend(palette.contentBackground, toward: palette.listText, by: 0.10)
        border = Self.blend(palette.contentBackground, toward: palette.listText, by: 0.28)
        divider = Self.blend(palette.contentBackground, toward: palette.listText, by: 0.18)
        dimText = Self.blend(palette.listText, toward: palette.contentBackground, by: 0.40)
        pressedFill = Self.blend(palette.contentBackground, toward: palette.selectionBackground, by: 0.55)
    }

    /// The style a surface uses before any skin has been loaded, and in tests.
    static let fallback = WinampModernSurfaceStyle(palette: .fallback)

    /// Linear RGB blend. Both inputs come from a skin, so both are converted to a known colour space
    /// first — `getRed` on a pattern or catalog colour traps otherwise.
    static func blend(_ from: NSColor, toward to: NSColor, by fraction: CGFloat) -> NSColor {
        guard let a = from.usingColorSpace(.deviceRGB), let b = to.usingColorSpace(.deviceRGB) else {
            return from
        }
        let t = min(max(fraction, 0), 1)
        return NSColor(deviceRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t)
    }

    /// The palette expressed as the `PlaylistColors` the classic views already take, so the recolour
    /// needs no new parameter threaded through drawing code that is 20k lines long in one case.
    var playlistColors: PlaylistColors {
        PlaylistColors(normalText: text,
                       currentText: currentText,
                       normalBackground: background,
                       selectedBackground: selectionBackground,
                       font: .systemFont(ofSize: 8))
    }

    /// True when the skin's content background is dark, which is what decides whether a hosted
    /// AppKit control (a text field, a menu) should use the dark or light system appearance.
    var prefersDarkAppearance: Bool {
        guard let rgb = background.usingColorSpace(.deviceRGB) else { return true }
        let brightness = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return brightness < 0.5
    }

    // MARK: - Text

    /// The classic bitmap cell the views lay themselves out against.
    static let classicCharWidth = SkinElements.TextFont.charWidth
    static let classicCharHeight = SkinElements.TextFont.charHeight

    /// A monospaced font whose advance is exactly `classicCharWidth * scale`.
    ///
    /// The point size is *solved for*, not guessed: the system's monospaced face is measured once and
    /// the size scaled by the ratio, then a `.kern` correction absorbs whatever rounding is left. So
    /// `attributes(...)`-drawn text is the same width the caller already computed for it, and a label
    /// that used to fit its box still fits it.
    static func font(scale: CGFloat) -> NSFont {
        // Memoized: a browser frame draws ~77 separate strings, and solving for the size measures a
        // glyph each time. Keyed on the rounded scale, of which a frame uses two or three.
        let key = (max(scale, 0.01) * 1000).rounded()
        if let cached = fontCache[key] { return cached }
        let target = classicCharWidth * max(scale, 0.01)
        let probeSize: CGFloat = 100
        let probe = NSFont.monospacedSystemFont(ofSize: probeSize, weight: .regular)
        let advance = Self.advance(of: probe)
        let font: NSFont
        if advance > 0 {
            font = NSFont.monospacedSystemFont(ofSize: min(max(probeSize * target / advance, 1), 256),
                                               weight: .regular)
        } else {
            font = NSFont.monospacedSystemFont(ofSize: target * 1.6, weight: .regular)
        }
        fontCache[key] = font
        return font
    }

    /// Main-thread only, like every other drawing path here.
    private static var fontCache: [CGFloat: NSFont] = [:]

    /// Drawing attributes for text that must occupy `count * classicCharWidth * scale` points.
    static func attributes(scale: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        let font = Self.font(scale: scale)
        let target = classicCharWidth * max(scale, 0.01)
        return [.font: font,
                .foregroundColor: color,
                .kern: target - Self.advance(of: font)]
    }

    /// Width of one character cell — the same number the callers compute, exposed so a test can
    /// assert the two agree.
    static func measuredWidth(_ text: String, scale: CGFloat) -> CGFloat {
        CGFloat(text.count) * classicCharWidth * max(scale, 0.01)
    }

    private static func advance(of font: NSFont) -> CGFloat {
        // Monospaced, so any character answers; "0" is present in every face.
        ("0" as NSString).size(withAttributes: [.font: font]).width
    }

    /// Draw a run of text inside a **flipped** (top-left origin) context, the way the classic bitmap
    /// font did.
    ///
    /// `position` is the top-left of the text cell, matching `SkinRenderer.drawSkinText`, and the run
    /// is counter-flipped about its own box so it does not come out mirrored. Returns the advance the
    /// caller should use, which is `measuredWidth`.
    @discardableResult
    static func drawText(_ text: String, at position: NSPoint, scale: CGFloat, color: NSColor,
                         in context: CGContext) -> CGFloat {
        let width = measuredWidth(text, scale: scale)
        guard !text.isEmpty else { return width }
        let cellHeight = classicCharHeight * max(scale, 0.01)
        let attributes = Self.attributes(scale: scale, color: color)
        let drawn = (text as NSString).size(withAttributes: attributes)

        context.saveGState()
        // Counter-flip about the cell's vertical centre, then centre the glyphs' own line height in
        // the cell — the system face is taller than the 6px bitmap it replaces.
        let centerY = position.y + cellHeight / 2
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        (text as NSString).draw(at: NSPoint(x: position.x, y: centerY - drawn.height / 2),
                                withAttributes: attributes)
        context.restoreGState()
        return width
    }
}
