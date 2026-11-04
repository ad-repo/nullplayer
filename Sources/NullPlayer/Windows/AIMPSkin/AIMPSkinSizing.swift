import AppKit

/// A form's size in skin pixels and how the user sizes it: the natural size it is never drawn
/// below, the band along its right and bottom edges a drag sizes it from, a sizing drag under way,
/// and the size maximize goes back to. The view applies it (`AIMPSkinMainView+Sizing`).
struct AIMPSkinSizing {
    /// The form's size in skin pixels.
    var canvas: CGSize
    /// The form's natural size, the smallest it is drawn at.
    private(set) var minimum: CGSize
    /// How near the right and bottom edges a drag sizes the form, in skin pixels; nil for a form
    /// of fixed size.
    private(set) var edge: CGFloat?
    /// A drag sizing the window: where it started on screen, the size then, the edges it moves.
    var drag: (start: NSPoint, size: CGSize, right: Bool, bottom: Bool)?
    /// The size to go back to from maximized; nil while not maximized.
    private(set) var unmaximized: CGSize?

    /// A form `minimum` at its natural size, sizable from a band `edge` wide (nil: fixed); `load`
    /// sizes a skin's.
    init(minimum: CGSize = AIMPSkinMainView.unskinnedSize, edge: CGFloat? = nil) {
        self.minimum = minimum
        self.edge = edge
        canvas = minimum
    }

    /// Sizes the form `formName` (nil: the main form) of `skin`, or the unskinned panel: its natural
    /// size, else for a form the user may size the size they last gave it, else the skin's own.
    mutating func load(_ skin: AIMPSkin?, form formName: String?) {
        minimum = skin?.naturalSize(form: formName) ?? AIMPSkinMainView.unskinnedSize
        edge = skin?.index.sizing[formName ?? ""]?.edge
        let initial = skin.flatMap { AIMPSkinRenderer.initialSize($0, form: formName, natural: minimum) }
        let saved = skin.flatMap { Self.savedSize(skin: $0, form: formName) }
        canvas = edge == nil ? minimum : saved.map(clamped) ?? initial.map(clamped) ?? minimum
    }

    /// At least the natural size, at most four times it.
    func clamped(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, minimum.width), minimum.width * 4).rounded(),
               height: min(max(size.height, minimum.height), minimum.height * 4).rounded())
    }

    /// The edges a press at `point` sizes, for a form the user may size; `bounds` and `point` in
    /// view points, `scale` view points per skin pixel.
    func edges(at point: NSPoint, in bounds: NSRect, scale: CGFloat) -> (right: Bool, bottom: Bool)? {
        guard let edge = edge.map({ $0 * scale }), bounds.contains(point) else { return nil }
        let right = point.x >= bounds.maxX - edge, bottom = point.y >= bounds.maxY - edge
        return right || bottom ? (right, bottom) : nil
    }

    /// The canvas the sizing drag asks for with the pointer at `pointer` (screen points): grown
    /// from the top-left corner, clamped; nil while no drag is under way or it asks for no change.
    func dragged(to pointer: NSPoint, scale: CGFloat) -> CGSize? {
        guard let drag else { return nil }
        var size = drag.size
        if drag.right { size.width += (pointer.x - drag.start.x) / scale }
        if drag.bottom { size.height -= (pointer.y - drag.start.y) / scale }
        size = clamped(size)
        return size == canvas ? nil : size
    }

    /// Fills `screen` (points) at `scale`, or goes back to the size before.
    mutating func toggleMaximized(screen: CGSize, scale: CGFloat) {
        if let restore = unmaximized {
            unmaximized = nil
            canvas = clamped(restore)
        } else {
            unmaximized = canvas
            canvas = CGSize(width: max(minimum.width, (screen.width / scale).rounded(.down)),
                            height: max(minimum.height, (screen.height / scale).rounded(.down)))
        }
    }

    /// The size the user last gave `skin`'s form, kept by its name.
    private static func savedSize(skin: AIMPSkin, form formName: String?) -> CGSize? {
        UserDefaults.standard.string(forKey: key(skin: skin, form: formName)).map { NSSizeFromString($0) }
            .flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
    }

    static func save(_ size: CGSize, skin: AIMPSkin, form formName: String?) {
        UserDefaults.standard.set(NSStringFromSize(size), forKey: key(skin: skin, form: formName))
    }

    private static func key(skin: AIMPSkin, form formName: String?) -> String {
        "AIMPSkinSize." + skin.name + (formName.map { "." + $0 } ?? "")
    }
}
