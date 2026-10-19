import AppKit

extension NSAppearance {
    /// Dark Aqua over a dark `background`, Aqua over a light one, for AppKit and SwiftUI content
    /// hosted on a skin's colour. A colour with no RGB form counts as dark.
    static func matching(background: NSColor) -> NSAppearance? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        background.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return NSAppearance(named: 0.299 * r + 0.587 * g + 0.114 * b < 0.5 ? .darkAqua : .aqua)
    }
}
