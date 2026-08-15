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
            guard let raw = attributes[key.lowercased()]?.lowercased() else { return false }
            return raw == "1" || raw == "true" || raw == "yes"
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
