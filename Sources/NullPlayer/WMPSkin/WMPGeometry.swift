import CoreGraphics
import Foundation

/// WMP geometry is authored in a top-left coordinate system. These value types deliberately keep
/// that convention all the way through scene construction and rendering.
struct WMPPoint: Hashable, Codable {
    var x: CGFloat
    var y: CGFloat
}

struct WMPSize: Hashable, Codable {
    var width: CGFloat
    var height: CGFloat

    static let zero = WMPSize(width: 0, height: 0)
}

struct WMPRect: Hashable, Codable, CustomStringConvertible {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let zero = WMPRect(x: 0, y: 0, width: 0, height: 0)
    var maxX: CGFloat { x + width }
    var maxY: CGFloat { y + height }
    var isEmpty: Bool { width <= 0 || height <= 0 }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var description: String { "\(WMPNumber.format(x)),\(WMPNumber.format(y)) \(WMPNumber.format(width))x\(WMPNumber.format(height))" }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> WMPRect {
        WMPRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    func intersection(_ other: WMPRect) -> WMPRect? {
        let left = max(x, other.x), top = max(y, other.y)
        let right = min(maxX, other.maxX), bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return nil }
        return WMPRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    func union(_ other: WMPRect) -> WMPRect {
        guard !isEmpty else { return other }
        guard !other.isEmpty else { return self }
        let left = min(x, other.x), top = min(y, other.y)
        return WMPRect(x: left, y: top, width: max(maxX, other.maxX) - left,
                       height: max(maxY, other.maxY) - top)
    }
}

enum WMPAxisAlignment: String, Codable {
    case leading, center, trailing, stretch

    init(horizontal value: String?) {
        switch value?.lowercased() {
        case "center": self = .center
        case "right": self = .trailing
        case "stretch": self = .stretch
        default: self = .leading
        }
    }

    init(vertical value: String?) {
        switch value?.lowercased() {
        case "center": self = .center
        case "bottom": self = .trailing
        case "stretch": self = .stretch
        default: self = .leading
        }
    }
}

struct WMPResizeLimits: Hashable, Codable {
    var minimum: WMPSize
    var maximum: WMPSize?

    func clamp(_ size: WMPSize) -> WMPSize {
        WMPSize(width: min(maximum?.width ?? .greatestFiniteMagnitude, max(minimum.width, size.width)),
                height: min(maximum?.height ?? .greatestFiniteMagnitude, max(minimum.height, size.height)))
    }
}

struct WMPResolvedGeometry: Hashable, Codable {
    let localFrame: WMPRect
    let absoluteFrame: WMPRect
    let visibleFrame: WMPRect?
    let clipRect: WMPRect?
}

enum WMPNumber {
    static func literal(_ attribute: WMPAttribute?) -> CGFloat? {
        guard let attribute, case let .literal(raw) = attribute.value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return CGFloat(value)
    }

    static func format(_ value: CGFloat) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.3f", Double(value))
    }
}
