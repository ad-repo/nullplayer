import CoreGraphics
import CoreText
import Foundation

/// One place that turns a `<TEXT>`'s authored face into a CoreText line, so the renderer and the
/// object model agree about how wide a string is.
///
/// They have to agree because a skin decides whether to marquee by comparing the two itself:
/// `WoW`'s `metadata.scrolling = (metadata.textWidth > metadata.width)` is the idiom, and 92 of the
/// 180 corpus archives write `textWidth`. A measurement the script could not reach answered 0, so
/// every one of those skins concluded its text fits and turned scrolling off.
enum WMPTextMetrics {
    /// **The face a node is drawn in, from its authored candidates in order — and the fallback is
    /// this engine's own default rather than CoreText's.**
    ///
    /// `CTFontCreateWithName` never fails: a name it cannot match silently becomes Helvetica. So a
    /// face that is empty, or that is a `res://wmploc.dll/RT_STRING/#<id>` this player cannot
    /// resolve, does *not* land on the `"Arial"` every unstated readout in the corpus is drawn in —
    /// it lands on Helvetica, a different face at a different height, with nothing in the markup
    /// asking for it. `netgen.wms` (`Revert`, `Revert (1)`) authors
    /// `fontFace="res://-/RT_STRING/#1888"` on all three metadata readouts (W236): `wmploc.dll`
    /// holds the shipping language's font family, which is how one markup file serves an RTL
    /// locale, and there is no honest family to invent for it here. **An unusable face is therefore
    /// an unstated one** — the same reading `W240`/`W241` gave an unreadable and an empty geometry
    /// attribute — so those three readouts take the default face instead of a substituted one.
    ///
    /// A resource URL is put through `WMPResourceStrings` rather than rejected outright, so that a
    /// future table row naming a real family is used the moment it is earned.
    static func face(_ candidates: String?...) -> String {
        for candidate in candidates {
            guard let resolved = WMPResourceStrings.resolved(candidate) else { continue }
            let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return defaultFace
    }

    /// The face a `<TEXT>` is drawn in when its markup and its script both leave one unstated.
    static let defaultFace = "Arial"

    /// The face name CoreText is asked for. `fontStyle` is a set — the corpus writes
    /// "bold underline" and "UNDERLINE, bold" — and only bold/italic are a face request.
    static func fontName(_ base: String, bold: Bool, italic: Bool) -> String {
        var name = base
        if bold { name += " Bold" }
        if italic { name += " Italic" }
        return name
    }

    static func font(_ base: String, size: CGFloat, bold: Bool, italic: Bool) -> CTFont {
        CTFontCreateWithName(fontName(base, bold: bold, italic: italic) as CFString,
                             max(1, size), nil)
    }

    static func line(_ value: String, font: CTFont, color: CGColor,
                     underline: Bool) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        if underline {
            attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] =
                CTUnderlineStyle.single.rawValue
        }
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: value, attributes: attributes))
    }

    /// The height of one line in the authored face, in skin pixels.
    ///
    /// A `<TEXT>` that authors no `height` is sized by its own glyphs, the way every other node is
    /// sized by its own artwork — the face's ascent, descent and leading are the box. It is rounded
    /// up because the renderer's baseline is derived from `fontSize` rather than from these
    /// metrics, and a box a fraction of a pixel short of the face clips the descenders of the row
    /// of links it was measured for.
    static func lineHeight(fontName base: String, fontSize: CGFloat,
                           bold: Bool, italic: Bool) -> CGFloat {
        let font = font(base, size: fontSize, bold: bold, italic: italic)
        let height = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        return max(fontSize, height.rounded(.up))
    }

    /// Typographic width of `value` in the authored face, in skin pixels.
    static func width(of value: String, fontName base: String, fontSize: CGFloat,
                      bold: Bool, italic: Bool) -> CGFloat {
        guard !value.isEmpty else { return 0 }
        let font = font(base, size: fontSize, bold: bold, italic: italic)
        let line = line(value, font: font, color: CGColor(gray: 0, alpha: 1), underline: false)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
