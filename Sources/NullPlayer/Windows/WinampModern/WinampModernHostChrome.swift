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
    func drawHostChrome(in context: WasabiDrawList) {
        let canvas = CGRect(origin: .zero, size: renderer.canvasSize)
        let style = renderer.surfaceStyle
        let isActive = window?.isKeyWindow ?? true
        context.saveGState()
        // The gloss frame is drawn top-left, lit from the top edge; this view is not flipped.
        context.translateBy(x: 0, y: canvas.height)
        context.scaleBy(x: 1, y: -1)
        context.record { context in
            SkinnedSurfaceChrome.drawGlossFrame(in: context, bounds: canvas, style: style,
                                                isActive: isActive, fillGround: true)
        }
        context.restoreGState()
    }

    /// `drawHostChrome` for the canvas builders, or nil when this window has no host chrome.
    var hostChrome: ((WasabiDrawList) -> Void)? {
        drawsHostChrome ? { [unowned self] in drawHostChrome(in: $0) } : nil
    }

    /// What a press at `viewPoint` (this view's own coordinates) means to the host's chrome, or nil
    /// for the contents: the fallback close corner of a scene with no close of its own, or the glass
    /// chrome's close and rim.
    func hostChromeHit(at viewPoint: NSPoint) -> HostChromeHit? {
        if FallbackCloseArea.contains(viewPoint, in: self), needsFallbackClose { return .close }
        guard drawsHostChrome else { return nil }
        let point = skinPoint(viewPoint)
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

    /// The base window rule's close corner (`FallbackCloseArea`) is this scene's, because it has no
    /// close of its own: no glass chrome, and nothing visible in it carries `action="CLOSE"`.
    /// Itemskin's standard frame is one, so the Equalizer Studio it frames could only be closed from
    /// the Windows menu.
    var needsFallbackClose: Bool {
        !drawsHostChrome && !renderer.sceneNodes().contains { node in
            guard renderer.isVisible(node.object), let action = node.object.attributes["action"] else { return false }
            return WasabiClickAction.split(action: action, parameter: nil).action
                .caseInsensitiveCompare("CLOSE") == .orderedSame
        }
    }

    /// Every close this view answers — the skin's `CLOSE` action, the glass chrome's corner, the
    /// fallback corner — goes to whoever owns the window layer. The fallback is for a view with no
    /// controller over it (tests): never `performClose`, which a borderless window ignores.
    func requestClose() {
        if let closeRequested { closeRequested() } else { window?.close() }
    }
}
