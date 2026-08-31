import Foundation

struct WasabiSize: Equatable, Codable {
    var width: Double
    var height: Double

    static let zero = WasabiSize(width: 0, height: 0)
}

struct WasabiRect: Equatable, Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let zero = WasabiRect(x: 0, y: 0, width: 0, height: 0)

    /// Useful for clipping/hit testing while retaining the signed Wasabi rectangle itself.
    var standardized: WasabiRect {
        WasabiRect(
            x: width < 0 ? x + width : x,
            y: height < 0 ? y + height : y,
            width: abs(width),
            height: abs(height)
        )
    }
}

/// Winamp's relative flags add the parent dimension to the corresponding signed value.
/// For example `x=-60 relatx=1` anchors 60 pixels from the right, while
/// `w=-120 relatw=1` means parent width minus 120 pixels.
///
/// The flags are read as `atoi(value) != 0`, not as `== 1` — see `flag(_:)`. Skins do ship other
/// numbers, and they mean nothing beyond "relative".
struct WasabiGeometrySpec: Equatable {
    var x: Double
    var y: Double
    var width: Double?
    var height: Double?
    var relativeX: Bool
    var relativeY: Bool
    var relativeWidth: Bool
    var relativeHeight: Bool
    /// `relat*="2"` — the value is a **percentage** of the parent dimension rather than an offset
    /// added to it. Kept beside `relativeX` rather than replacing it so that flag keeps meaning
    /// "relative at all", which is what `WasabiRenderer`'s title-box probe asks it.
    ///
    /// **This overturns Phase 56, whose evidence did not reach the question.** Phase 56 found
    /// `relat="2"` being read as `== 1` and so falling through to *absolute* geometry — Big Bento
    /// Modern's dimmed album-art backdrop came out as a literal 99×100 box, "a small crisp second
    /// copy of the cover" — and fixed it by making any non-zero value relative. That fixes the
    /// symptom, but so does this: 99% of a large parent is a large backdrop too. Absolute-vs-relative
    /// was measured; additive-vs-percent was not.
    ///
    /// What settles it is an object additive cannot place at **any** parent size. ClassicPro's Now
    /// Playing widget insets its cover in a jewel case with
    /// `<AlbumArt x="12" y="4" w="85" h="93" relatx="2" relaty="2" relatw="2" relath="2"/>`. Against
    /// its correctly-sized 80×74 case at (110, 211), additive resolves to (202, 289, 165×167) — the
    /// whole cover outside its own clip, drawn nowhere, reported as "an empty box". Percent gives
    /// (119.6, 214, 68×68.8): a cover inset in a case, which is the thing the markup describes.
    ///
    /// The corpus agrees. `relat*` is `1` 8197 times, `0` 360, and **`2` 89** — and every value those
    /// 89 carry is in 0…100 (155 of 157 numbers). Additive geometry here is overwhelmingly *negative*
    /// (`w="-14" relatw="1"`); a 0…100 distribution is a percentage's.
    var percentX: Bool
    var percentY: Bool
    var percentWidth: Bool
    var percentHeight: Bool

    init(attributes: [String: String]) {
        func number(_ key: String) -> Double? {
            guard let raw = attributes[key.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            return Double(raw)
        }
        func flag(_ key: String) -> Bool { Self.flag(attributes[key.lowercased()]) }
        x = number("x") ?? 0
        y = number("y") ?? 0
        width = number("w")
        height = number("h")
        relativeX = flag("relatx")
        relativeY = flag("relaty")
        relativeWidth = flag("relatw")
        relativeHeight = flag("relath")
        func isPercent(_ key: String) -> Bool { Self.percentFlag(attributes[key.lowercased()]) }
        percentX = isPercent("relatx")
        percentY = isPercent("relaty")
        percentWidth = isPercent("relatw")
        percentHeight = isPercent("relath")
    }

    /// How much wider than its source a group with `autowidthsource` has to be for the source to
    /// actually *reach* its own auto width (B68).
    ///
    /// The source's width is not the group's width — it is whatever the source's own geometry
    /// resolves to inside it, and every corpus source that names an offset keeps room on both
    /// sides. Two shapes, and both are just "solve the resolve for the group width":
    ///
    /// - A relative width (`w="-14" relatw="1"`) makes the source `groupWidth + w` wide, so the
    ///   group needs `sourceWidth - w`. impulse's `<text id="checkbox.text" x="13" w="-14"
    ///   relatw="1">` is this case: sized to the bare string, the label came out 14px short and
    ///   clipped about two characters off every *Skin Options* switch.
    /// - An absolute width does not depend on the group at all, so what matters is how far the
    ///   source reaches: `x + sourceWidth`.
    ///
    /// Zero for a source at `x="0"` that states no width of its own, which is every one of the
    /// 27 declarations that must not move — ClassicPro's and stock Winamp Modern's whole menu bar
    /// (`<layer id="File.txt" x="0" y="0"/>`), and the three `wasabi.titlebox.center.group`
    /// bodies at `x="0" w="0" relatw="1"`.
    static func autoWidthInset(of attributes: [String: String]) -> Double {
        let spec = WasabiGeometrySpec(attributes: attributes)
        let inset = spec.relativeWidth ? -(spec.width ?? 0) : spec.x
        return max(0, inset)
    }

    /// A Wasabi boolean attribute, read the way Winamp reads one.
    ///
    /// Winamp reads these with `atoi`, so the test is **non-zero**, not "== 1". Skins ship other
    /// numbers and mean nothing special by them: Big Bento Modern's dimmed album-art backdrop is
    /// `relatw="2"`, Ebonite_2_1's warped images are `relatw="2"` (including a `w="0" relatw="2"`
    /// group, which is the ordinary fill-the-parent idiom and the case that rules out reading the
    /// number as a percentage), and The_Nokia_5220's two bars are `relatw="5"`. Read as `== 1` all
    /// of those fell back to absolute geometry, which is how an oversized backdrop came out as a
    /// small crisp second copy of the cover.
    ///
    /// A non-numeric value still reads false, which is also `atoi`'s answer and the one two skins
    /// depend on: corneramp_redux and Shield_Amp ship a literal `relatw="%"`.
    ///
    /// Shared with the renderer's `fliph`/`flipv`, which are the same kind of flag on the same
    /// attribute table and must not grow a second, subtly different reading of "1".
    static func flag(_ value: String?) -> Bool {
        guard let raw = value?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        if raw == "true" || raw == "yes" { return true }
        return leadingInteger(raw) != 0
    }

    /// `atoi`'s number: the leading signed integer, or 0 when there is not one. Deliberately not
    /// `Int(_:)`, which answers nil for anything with a trailing character and would send a value
    /// like `"1px"` down the false branch that `atoi` sends down the true one.
    private static func leadingInteger(_ raw: String) -> Int {
        var digits = ""
        var index = raw.startIndex
        if index < raw.endIndex, raw[index] == "-" || raw[index] == "+" {
            digits.append(raw[index])
            index = raw.index(after: index)
        }
        while index < raw.endIndex, raw[index].isASCII, raw[index].isNumber {
            digits.append(raw[index])
            index = raw.index(after: index)
        }
        return Int(digits) ?? 0
    }

    /// `atoi == 2` — the percentage mode. Every other non-zero value stays additive, including the
    /// `5` two of The_Nokia_5220's bars carry: nothing measured suggests a third meaning, and the
    /// corpus holds no other value than 0, 1, 2, 5 and a non-numeric `%`.
    static func percentFlag(_ value: String?) -> Bool {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return leadingInteger(raw) == 2
    }

    func resolve(in parent: WasabiRect, intrinsicSize: WasabiSize = .zero) -> WasabiRect {
        func resolved(_ value: Double, percent: Bool, relative: Bool, span: Double) -> Double {
            if percent { return span * value / 100 }
            return value + (relative ? span : 0)
        }
        let rawWidth = width ?? intrinsicSize.width
        let rawHeight = height ?? intrinsicSize.height
        return WasabiRect(
            x: parent.x + resolved(x, percent: percentX, relative: relativeX, span: parent.width),
            y: parent.y + resolved(y, percent: percentY, relative: relativeY, span: parent.height),
            width: resolved(rawWidth, percent: percentWidth, relative: relativeWidth, span: parent.width),
            height: resolved(rawHeight, percent: percentHeight, relative: relativeHeight, span: parent.height)
        )
    }
}
