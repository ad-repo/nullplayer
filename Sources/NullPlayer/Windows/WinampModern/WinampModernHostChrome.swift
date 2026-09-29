import AppKit

/// NullPlayer's own glass chrome around a skin container that has no frame of its own to wear.
///
/// A container marked `WinampModernContainerTopology.hostChromeAttribute` — the About page of a
/// skin with no usable standard frame, or a window the skin framed in tooltip art — holds only its
/// content group, inset by the rim. The rim itself is drawn here with the same
/// `SkinnedSurfaceChrome.drawGlossFrame` every fallback window wears, in the skin's palette, and its
/// top-right corner is the same close target. The rest of the rim moves the window.
extension WinampModernMainView {

    enum HostChromeHit {
        case close
        case drag
    }

    /// The rim, drawn under the scene in skin pixels. `context` is already scaled to skin pixels.
    func drawHostChrome(in context: CGContext) {
        let canvas = CGRect(origin: .zero, size: renderer.canvasSize)
        context.saveGState()
        // The gloss frame is drawn top-left, lit from the top edge; this view is not flipped.
        context.translateBy(x: 0, y: canvas.height)
        context.scaleBy(x: 1, y: -1)
        SkinnedSurfaceChrome.drawGlossFrame(in: context, bounds: canvas, style: renderer.surfaceStyle,
                                            isActive: window?.isKeyWindow ?? true, fillGround: true)
        context.restoreGState()
    }

    /// What a press at `point` (top-left skin pixels) means to the chrome, or nil for the contents.
    func hostChromeHit(at point: CGPoint) -> HostChromeHit? {
        let canvas = CGRect(origin: .zero, size: renderer.canvasSize)
        // The full corner target whatever `hidesPaletteTitleBar` says: this chrome is drawn either
        // way, so its close must not shrink to the classic title-bar strip before a palette loads.
        let close = SkinnedSurfaceChrome.closeButtonRect(
            in: canvas, captionHeight: SkinnedSurfaceFrameArtwork.closeHitHeight,
            width: SkinnedSurfaceFrameArtwork.closeHitWidth, artwork: nil)
        if close.contains(point) { return .close }
        let rim = SkinnedSurfaceChrome.glossBorder
        return canvas.insetBy(dx: rim, dy: rim).contains(point) ? nil : .drag
    }
}
