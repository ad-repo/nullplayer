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

    func contains(_ point: WMPPoint) -> Bool {
        point.x >= x && point.y >= y && point.x < maxX && point.y < maxY
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

/// The floor and ceiling a window showing a given scene is given, in the skin's own points.
///
/// **A window whose frame and whose scene disagree comes apart, and this is the one number that
/// predicts it (W213).** The artwork is rasterized at the *scene's* size, while the hosted surfaces
/// and `WMPMainView.skinPoint(from:sceneSize:)` — where every click is resolved — are derived from
/// `bounds / canvasSize`. Let the window be a size the scene is not and the two layers separate:
/// the visualization stretches while the skin stays put, and every control moves out from under the
/// pointer. It was reported as two unrelated complaints on `circle` and was one window state.
///
/// The app used to leave `minSize` at the unskinned player's 440x170 for every skin, so **any view
/// smaller than that in either axis was one edge drag away from it**. That is a property of the
/// scene alone, so it is checkable over the whole corpus with no window and no gesture — see
/// `WMP_RENDER_LIMITS` in `skills/wmp-skin-guide/reference/harness.md`. Derived here rather than in
/// the controller so the probe and the app cannot answer differently; a second copy of a rule is
/// how a harness comes to report work that is already done.
struct WMPWindowSizeLimits: Hashable {
    let minimum: WMPSize
    /// `nil` is unbounded, which is what a resizable view with no `maxWidth`/`maxHeight` gets.
    let maximum: WMPSize?

    /// **A view that is not resizable is pinned to its canvas at both ends.** It has one size, and a
    /// window that the user cannot resize should not be moved to another size by a pass that reads
    /// these — `minSize` is enforced by AppKit after every delegate has answered.
    static func forScene(_ scene: WMPScene) -> WMPWindowSizeLimits {
        guard scene.isResizable else {
            return WMPWindowSizeLimits(minimum: scene.canvasSize, maximum: scene.canvasSize)
        }
        return WMPWindowSizeLimits(minimum: scene.resizeLimits.minimum,
                                   maximum: scene.resizeLimits.maximum)
    }

    /// Why this window would be forced away from `canvas`, or `nil` when it would not be.
    enum Breakage: String { case belowFloor = "below-floor", aboveCeiling = "above-ceiling" }

    func breakage(for canvas: WMPSize) -> Breakage? {
        if canvas.width + 0.5 < minimum.width || canvas.height + 0.5 < minimum.height {
            return .belowFloor
        }
        if let maximum, canvas.width > maximum.width + 0.5 || canvas.height > maximum.height + 0.5 {
            return .aboveCeiling
        }
        return nil
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
