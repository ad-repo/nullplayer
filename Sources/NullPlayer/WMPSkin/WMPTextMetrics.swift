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

    /// Typographic width of `value` in the authored face, in skin pixels.
    static func width(of value: String, fontName base: String, fontSize: CGFloat,
                      bold: Bool, italic: Bool) -> CGFloat {
        guard !value.isEmpty else { return 0 }
        let font = font(base, size: fontSize, bold: bold, italic: italic)
        let line = line(value, font: font, color: CGColor(gray: 0, alpha: 1), underline: false)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
