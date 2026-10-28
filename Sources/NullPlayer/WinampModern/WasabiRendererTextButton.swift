import AppKit
import CoreGraphics

extension WasabiSceneRenderer {
    /// A text button's art.
    ///
    /// The art such a button lacks is usually still the skin's: the conventional `wasabi.button.*`
    /// nine-slice, `.pressed.*` while held (B288). Halloween2003's screenshot shows its EQ's
    /// On/Auto/Learn/Presets drawn on it, and Quadelic's config buttons ship the same set. The border
    /// stands in only when no slice resolves. On the art the label takes the skin's button text colour,
    /// which its author chose for that art: Anexa's list white was unreadable on its light buttons.
    func drawTextButton(_ object: WasabiObject, frame: CGRect, context: WasabiDrawList,
                                pressed: Bool) {
        guard frame.width > 2, frame.height > 2 else { return }
        var color = palette.listText
        context.saveGState()
        let pressedArt = pressed ? textButtonSlices("wasabi.button.pressed.") : nil
        if let art = pressedArt ?? textButtonSlices("wasabi.button.") {
            drawNineSlice(art, in: frame, tile: false, context: context)
            color = declaredSkinColor("wasabi.button.text") ?? declaredSkinColor("studio.button.text") ?? color
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1)
            context.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
        }
        if pressed, pressedArt == nil {
            context.setFillColor(color.withAlphaComponent(0.25).cgColor)
            context.fill(frame.insetBy(dx: 1, dy: 1))
        }
        if let label = Self.ownLabel(of: object) {
            let inset = frame.insetBy(dx: 1, dy: max(0, (frame.height - 11) / 2))
            drawSurfaceText(label, in: inset, color: color, alignment: .center, pointSize: 9,
                            context: context)
        }
        context.restoreGState()
    }

    /// One `wasabi.button.*` set, row-major for `drawNineSlice`, or nil when none of it resolves. The
    /// centre is `.center` in most of the corpus and `.middle` in about 200 skins, Quadelic among them.
    func textButtonSlices(_ prefix: String) -> [WasabiBitmap?]? {
        func art(_ slice: String) -> WasabiBitmap? { resources.bitmap(identifier: prefix + slice) }
        let parts = [art("top.left"), art("top"), art("top.right"),
                     art("left"), art("center") ?? art("middle"), art("right"),
                     art("bottom.left"), art("bottom"), art("bottom.right")]
        return parts.contains { $0 != nil } ? parts : nil
    }
}
