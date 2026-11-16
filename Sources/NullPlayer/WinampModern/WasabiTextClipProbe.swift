import AppKit

/// Text a draw cut vertically: its glyphs are taller than the rect they were scissored to. Read by
/// the render dump's `TEXT-CLIP` lines, so an intake finds a clipped clock or display text without
/// anyone having to spot it (EI B441, Two Towers B455). Armed only under `WINAMP_MODERN_RENDER_DUMP`;
/// everywhere else `record` returns at its first line.
enum WasabiTextClipProbe {
    static let isArmed = ProcessInfo.processInfo.environment["WINAMP_MODERN_RENDER_DUMP"] != nil
    typealias Cut = (object: WasabiObject, glyph: CGFloat, box: CGFloat)
    /// Per object: what it needed and what it got, in skin pixels. Keyed by identity, so a redraw
    /// overwrites rather than repeats. Locked: a window's text draws on its canvas queue (off main).
    private static var store: [ObjectIdentifier: Cut] = [:]
    private static let lock = NSLock()
    static var cuts: [ObjectIdentifier: Cut] { lock.withLock { store } }

    /// A TrueType string, measured by its glyphs' ink, not the font's line box: a title with no
    /// descender in an exactly-sized box is not cut.
    static func record(_ object: WasabiObject, text: String, font: NSFont, box: CGFloat) {
        guard isArmed, !text.isEmpty else { return }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        record(object, glyph: CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).height, box: box)
    }

    /// A bitmap run: its cell bottom against the scissor's, both measured from the scissor's top.
    static func record(_ object: WasabiObject, glyph: CGFloat, box: CGFloat) {
        guard isArmed else { return }
        lock.withLock { store[ObjectIdentifier(object)] = glyph > box + 1 ? (object, glyph, box) : nil }
    }

    static func reset() { lock.withLock { store = [:] } }
}
