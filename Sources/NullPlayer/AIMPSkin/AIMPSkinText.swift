import CoreGraphics
import CoreText
import Foundation

/// Text as AIMP sets it, for the painter that draws it and the layout that sizes displays by it.
enum AIMPSkinText {
    /// `text` broken into lines no wider than `width` (and at its own line breaks), as a display
    /// with `WordWrap` or a `MultiLine` layout shows it.
    static func lines(_ text: String, font: AIMPSkinFont, width: CGFloat) -> [CTLine] {
        text.components(separatedBy: .newlines).flatMap { paragraph -> [CTLine] in
            let styled = Self.styled(paragraph, font: font)
            guard styled.length > 0 else { return [CTLineCreateWithAttributedString(styled)] }
            let typesetter = CTTypesetterCreateWithAttributedString(styled)
            var lines: [CTLine] = [], start = 0
            while start < styled.length {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(max(1, width))))
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
                start += count
            }
            return lines
        }
    }

    /// One line's height in `font`.
    static func lineHeight(_ font: AIMPSkinFont) -> CGFloat {
        let ctFont = font.ctFont
        return (CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont)).rounded(.up)
    }

    /// How wide `text` draws in `font`.
    static func width(_ text: String, font: AIMPSkinFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(Self.styled(text, font: font))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// `text` in `font`, through the markup AIMP's templates allow (Dark v1.7's title line):
    /// `[COLOR=#rrggbb]` (or `rrggbb`: Telos's, Analogue's), `[B]`, `[I]`, `[U]` and their closing
    /// tags; `[URL=…]` and `[/URL]` leave their text plain (Kantaris-Teyp's web page line). An
    /// unknown tag stays text.
    static func styled(_ text: String, font: AIMPSkinFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var colors = [color(font.color)], bold = font.bold, italic = false, underline = false
        func append(_ run: Substring) {
            guard !run.isEmpty else { return }
            var face = font
            face.bold = bold
            var ctFont = face.ctFont
            if italic { ctFont = CTFontCreateCopyWithSymbolicTraits(ctFont, 0, nil, .traitItalic, .traitItalic) ?? ctFont }
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): colors.last!,
            ]
            if underline { attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = CTUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: String(run), attributes: attributes))
        }
        var rest = text[...]
        while let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]") {
            let tag = rest[rest.index(after: open)..<close].uppercased()
            let hex = tag.hasPrefix("COLOR=") ? tag.dropFirst(6).drop { $0 == "#" } : ""
            let rgb = hex.count == 6 ? UInt32(hex, radix: 16) : nil
            let link = tag.hasPrefix("URL=") || tag == "/URL"
            guard ["B", "/B", "I", "/I", "U", "/U", "/COLOR"].contains(tag) || rgb != nil || link else {
                append(rest[...close])
                rest = rest[rest.index(after: close)...]
                continue
            }
            append(rest[..<open])
            rest = rest[rest.index(after: close)...]
            switch tag {
            case "B", "/B": bold = tag == "B" || font.bold
            case "I", "/I": italic = tag == "I"
            case "U", "/U": underline = tag == "U"
            case "/COLOR": if colors.count > 1 { colors.removeLast() }
            default: if let rgb { colors.append(color(0xFF00_0000 | rgb)) }
            }
        }
        append(rest)
        return out
    }
    /// An ARGB colour.
    static func color(_ argb: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat(argb >> 16 & 0xFF) / 255, green: CGFloat(argb >> 8 & 0xFF) / 255,
                blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat(argb >> 24) / 255)
    }
}
