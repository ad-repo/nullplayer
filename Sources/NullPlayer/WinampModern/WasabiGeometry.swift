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

    init(attributes: [String: String]) {
        func number(_ key: String) -> Double? {
            guard let raw = attributes[key.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            return Double(raw)
        }
        func flag(_ key: String) -> Bool {
            guard let raw = attributes[key.lowercased()]?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
            if raw == "true" || raw == "yes" { return true }
            // Winamp reads these with `atoi`, so the test is **non-zero**, not "== 1". Skins ship
            // other numbers and mean nothing special by them: Big Bento Modern's dimmed album-art
            // backdrop is `relatw="2"`, Ebonite_2_1's warped images are `relatw="2"` (including a
            // `w="0" relatw="2"` group, which is the ordinary fill-the-parent idiom and the case that
            // rules out reading the number as a percentage), and The_Nokia_5220's two bars are
            // `relatw="5"`. Read as `== 1` all of those fell back to absolute geometry, which is how
            // an oversized backdrop came out as a small crisp second copy of the cover.
            //
            // A non-numeric value still reads false, which is also `atoi`'s answer and the one two
            // skins depend on: corneramp_redux and Shield_Amp ship a literal `relatw="%"`.
            return Self.leadingInteger(raw) != 0
        }
        x = number("x") ?? 0
        y = number("y") ?? 0
        width = number("w")
        height = number("h")
        relativeX = flag("relatx")
        relativeY = flag("relaty")
        relativeWidth = flag("relatw")
        relativeHeight = flag("relath")
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

    func resolve(in parent: WasabiRect, intrinsicSize: WasabiSize = .zero) -> WasabiRect {
        let resolvedX = parent.x + x + (relativeX ? parent.width : 0)
        let resolvedY = parent.y + y + (relativeY ? parent.height : 0)
        let rawWidth = width ?? intrinsicSize.width
        let rawHeight = height ?? intrinsicSize.height
        return WasabiRect(
            x: resolvedX,
            y: resolvedY,
            width: rawWidth + (relativeWidth ? parent.width : 0),
            height: rawHeight + (relativeHeight ? parent.height : 0)
        )
    }
}
