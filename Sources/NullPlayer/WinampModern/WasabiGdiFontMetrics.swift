import AppKit
import Foundation

/// Sizing and placing a face the way Windows GDI does, which is what a skin's `fontsize` and box
/// were authored against: the em fitted to the face's OS/2 win cell, the line laid out in that cell
/// rather than CoreText's hhea one, and a missing Windows face's stand-in sized as the named face
/// would have been.
extension WasabiTextMetrics {
    /// `font` rescaled so its em is the one GDI draws for the same `fontsize`.
    ///
    /// GDI fits a face's whole cell — its OS/2 `usWinAscent + usWinDescent` — into the height it is
    /// handed, so a face with a tall cell draws a smaller em. `pixelHeightToPointSize` was measured
    /// on Arial (a 1.117 em cell); a face with a **taller** cell is scaled down by its cell against
    /// Arial's. Impact's cell is 1.22 em, and TOX Milla's `fontsize="24"` timer draws 14px digits in
    /// its own screenshot — a 17.6 em, not 19.2 — where the unscaled face overflowed its 15px box.
    ///
    /// **Never up.** A face whose cell is *shorter* than Arial's is a pixel font, and Winamp does not
    /// grow it: Cell's Visitor TT2 has a 0.7 em cell, and scaled by it the timer's digits drew 10px
    /// tall against the 6–7 its own `sc.png` shows, overfilling the brackets drawn for them (#581).
    static func gdiSized(_ font: NSFont) -> NSFont {
        guard !gdiDrawsAsArial(font) else { return font }
        let cell = winMetricsPerEm(of: font).map { $0.ascent + $0.descent }
            ?? (font.ascender - font.descender) / font.pointSize
        let scale = gdiScale(cellPerEm: cell)
        guard scale != 1 else { return font }
        // Bridged through `NSFont?` for the same reason as `resolvedFont`'s constructor: a CoreText
        // constructor imported as non-optional can still hand back null.
        let sized: NSFont? = CTFontCreateCopyWithAttributes(font, font.pointSize * scale, nil, nil) as NSFont
        return sized ?? font
    }

    /// How GDI scales a face's em against Arial's at the same `fontsize`: down by a cell taller than
    /// Arial's, and **never up** (see `gdiSized`).
    static func gdiScale(cellPerEm cell: CGFloat) -> CGFloat {
        cell > arialCellPerEm + 0.01 && cell < 3 ? arialCellPerEm / cell : 1
    }

    /// Windows has no Helvetica — GDI's FontSubstitutes draws Arial for it, and here it is MS Sans
    /// Serif's stand-in — so its cell is Arial's, not its own, and Arial's two cells agree.
    static func gdiDrawsAsArial(_ font: NSFont) -> Bool { font.familyName == "Helvetica" }

    /// A face's OS/2 `usWinAscent`/`usWinDescent` per em — the cell GDI lays a line out in — or
    /// `nil` when it has no OS/2 table.
    static func winMetricsPerEm(of font: NSFont) -> (ascent: CGFloat, descent: CGFloat)? {
        let unitsPerEm = CGFloat(CTFontGetUnitsPerEm(font))
        guard unitsPerEm > 0,
              let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
              table.count >= 78 else { return nil }
        func uint16(_ offset: Int) -> CGFloat {
            CGFloat(UInt16(table[table.startIndex + offset]) << 8
                    | UInt16(table[table.startIndex + offset + 1]))
        }
        return (uint16(74) / unitsPerEm, uint16(76) / unitsPerEm)
    }

    /// Where GDI puts a line that TextKit would put elsewhere: its cell, and how much lower its
    /// baseline sits than the face's `ascender` puts it.
    ///
    /// GDI lays a line out in the OS/2 win cell; CoreText in the hhea one. Most faces make the two
    /// agree and this answers the face's own line and 0. A face that does not is drawn too high:
    /// CPro Winamp for Mac's Helvetica Neue LT Com has an hhea ascender of 0.714 em — its cap height,
    /// with a 0.2 line gap above — against a win ascent of 0.952, so its `fontsize="44"` clock rose
    /// 4px out of its 28px box and lost the tops of its digits. Helvetica keeps its own line
    /// (`gdiDrawsAsArial`).
    static func gdiLine(of font: NSFont) -> (cell: CGFloat, baselineDrop: CGFloat) {
        let own = font.ascender - font.descender
        guard !gdiDrawsAsArial(font), let win = winMetricsPerEm(of: font) else { return (own, 0) }
        let ascent = win.ascent * font.pointSize
        return ((win.ascent + win.descent) * font.pointSize, ascent - font.ascender)
    }

    /// Arial's GDI cell per em, `(1854 + 434) / 2048` — the face `pixelHeightToPointSize` was measured on.
    static let arialCellPerEm: CGFloat = 2288.0 / 2048.0

    /// How much smaller GDI draws a missing Windows face's em than Arial's at the same `fontsize`,
    /// so the stand-in takes the size the named face would have had — `gdiSized`'s rule, with the
    /// cell read from a table because the face is not here to read it from.
    ///
    /// Segoe UI's win cell is `(2210 + 514) / 2048` = 1.33 em. cPro2 minimal styles its elapsed clock
    /// `font="Segoe UI" fontsize="40"` in a 31px box; drawn at Arial's em the digits ran 3px taller
    /// and lower than its `screenshot.png` and sat on the track length beneath them.
    static func substituteScale(forMissing name: String) -> CGFloat {
        let stem = windowsFontFileStem(of: name).lowercased()
        let family = windowsFontFileFamilies[stem] ?? name
        return missingFaceCellPerEm[family.lowercased()].map(gdiScale) ?? 1
    }

    private static let missingFaceCellPerEm: [String: CGFloat] = ["segoe ui": 2724.0 / 2048.0]
}
