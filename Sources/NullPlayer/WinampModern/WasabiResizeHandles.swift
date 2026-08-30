import Foundation

/// Which window edges a `resize="…"` handle drags.
///
/// Wasabi's resize model is **markup-driven, not chrome-driven**: a window has no frame the window
/// server would resize it by, so the skin nominates the handles itself by hanging `resize=` on the
/// layers that draw its border. The shared `standardframe` include — which 32 of the 37 installed
/// skins use — declares nine of them (`topleft`…`bottomright`, plus two corner grips), so the whole
/// 30-odd-pixel border of a playlist or library window is a grab strip, and a bare
/// `<layer id="window.resize.disabler">` is laid over the interior to keep the strip off the
/// buttons. Without this the only thing left was AppKit's own borderless edge band, about a pixel of
/// it, which is what made Shield_Amp's playlist window feel impossible to stretch.
struct WasabiResizeEdges: OptionSet {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let left = WasabiResizeEdges(rawValue: 1 << 0)
    static let right = WasabiResizeEdges(rawValue: 1 << 1)
    static let top = WasabiResizeEdges(rawValue: 1 << 2)
    static let bottom = WasabiResizeEdges(rawValue: 1 << 3)

    /// The attribute's vocabulary. `resize="0"`/`"1"` is a different attribute of the same name —
    /// `<sendparams>` and `<groupdef>` use it as a flag — and neither names an edge, so both parse to
    /// nothing rather than to a handle that would resize the window from the middle of a group.
    init?(attribute: String?) {
        switch attribute?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left": self = .left
        case "right": self = .right
        case "top": self = .top
        case "bottom": self = .bottom
        case "topleft": self = [.top, .left]
        case "topright": self = [.top, .right]
        case "bottomleft": self = [.bottom, .left]
        case "bottomright": self = [.bottom, .right]
        default: return nil
        }
    }

    var isHorizontal: Bool { contains(.left) || contains(.right) }
    var isVertical: Bool { contains(.top) || contains(.bottom) }
}

extension WasabiSceneRenderer {
    /// The window edges a press at this point drags, or `nil` when the point is not on a handle.
    ///
    /// Topmost wins, with no special pleading: that is exactly how a skin expresses the exceptions.
    /// The interior is covered by a plain `window.resize.disabler` layer declared *after* the border
    /// layers, the corner grips are declared after that again, and a close button sitting on the top
    /// strip is above it too — so the ordinary hit test already answers "button", "disabler" or
    /// "grip" without this code knowing any of their names.
    ///
    /// A layout the skin gave no resize range is fixed and has no handles at all, whatever its
    /// borders declare — the same rule `userResizeLimits` applies to the window's own limits.
    func resizeEdges(at point: CGPoint) -> WasabiResizeEdges? {
        guard layoutIsUserResizable, let object = object(at: point) else { return nil }
        return WasabiResizeEdges(attribute: object.attributes["resize"])
    }
}
