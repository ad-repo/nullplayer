import AppKit

/// The classic Library's tab: a rounded box, filled while selected, its label in the skin's text
/// font — the bitmap sheet (white while selected), or in a session that lends a surface style
/// (`.wal`, `.wmz`) that palette's matched system face. The Equalizer Studio draws its buttons with
/// it, so the two windows' tabs are the same.
///
/// Both draw into a top-left-origin CTM over an unflipped `NSGraphicsContext`, as the Library's
/// own drawing does; a flipped view's context is unflipped for the call.
enum ClassicLibraryTab {
    /// `rect` is the tab's slot: the box is inset from it, the label centred in it.
    static func draw(_ label: String, isSelected: Bool, in rect: NSRect, boxInsetX: CGFloat, textScale: CGFloat,
                     colors: PlaylistColors, renderer: SkinRenderer, style: SkinnedSurfaceStyle?, context: CGContext) {
        let boxPath = NSBezierPath(roundedRect: rect.insetBy(dx: boxInsetX, dy: 3), xRadius: 3, yRadius: 3)
        boxPath.lineWidth = 1
        if isSelected {
            colors.currentText.withAlphaComponent(0.12).setFill()
            boxPath.fill()
            colors.currentText.withAlphaComponent(0.8).setStroke()
        } else {
            colors.normalText.withAlphaComponent(0.4).setStroke()
        }
        boxPath.stroke()

        let textWidth = Self.textWidth(label, scale: textScale, style: style)
        let textHeight = SkinElements.TextFont.charHeight * textScale
        var origin = NSPoint(x: rect.midX - textWidth / 2, y: rect.minY + (rect.height - textHeight) / 2)
        // Round on non-Retina to prevent shimmering.
        if (NSScreen.main?.backingScaleFactor ?? 2.0) < 1.5 { origin = NSPoint(x: round(origin.x), y: round(origin.y)) }
        drawSkinText(label, at: origin, scale: textScale, white: isSelected, renderer: renderer, style: style,
                     context: context)
    }

    /// The colour a tab's label is drawn in, selected or not: the sheet's white or its own text
    /// colour, or a surface style's current-text and text roles.
    static func labelColor(isSelected: Bool, renderer: SkinRenderer, style: SkinnedSurfaceStyle?) -> NSColor {
        if let style { return isSelected ? style.currentText : style.text }
        return isSelected ? .white : renderer.skinTextColor()
    }

    /// How wide `drawSkinText` draws `text`: `count` bitmap cells, or a surface style's drawn run, which
    /// is narrower. What a centred or right-aligned label is placed by.
    static func textWidth(_ text: String, scale: CGFloat, style: SkinnedSurfaceStyle?) -> CGFloat {
        style == nil ? CGFloat(text.count) * SkinElements.TextFont.charWidth * scale
            : SkinnedSurfaceStyle.drawnWidth(text, scale: scale)
    }

    /// The skin's text at `scale`, top-left at `position`. `white` is the classic sheet's emphasis;
    /// a surface style draws it in its current-text role. `color` overrides a style's colour for
    /// text on something other than the content background; the bitmap sheet ignores it.
    static func drawSkinText(_ text: String, at position: NSPoint, scale: CGFloat, white: Bool = false,
                             color: NSColor? = nil, renderer: SkinRenderer, style: SkinnedSurfaceStyle?,
                             context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        if let style {
            SkinnedSurfaceStyle.drawText(text, at: position, scale: scale,
                                         color: color ?? labelColor(isSelected: white, renderer: renderer, style: style),
                                         in: context)
            return
        }
        context.saveGState()
        context.translateBy(x: position.x, y: position.y)
        context.scaleBy(x: scale, y: scale)
        if white {
            renderer.drawSkinTextWhite(text, at: .zero, in: context)
        } else {
            renderer.drawSkinText(text, at: .zero, in: context)
        }
        context.restoreGState()
    }
}
