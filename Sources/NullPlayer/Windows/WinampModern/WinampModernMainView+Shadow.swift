import AppKit

/// The `.wal` window drop shadow: `SkinWindowShadow` fed with the frame the window drew.
///
/// The canvas keeps the alpha of every frame it renders (`WinampModernCanvas`), so the outline is
/// the picture on screen, not a second render made for the shadow. It is handed over only when a
/// frame changed it, and a frame that only drew inside the outline — a readout tick, a meter —
/// costs a row compare over its own dirty rects and nothing more. So the shadow follows an animating
/// outline, Anunaki's sliding EQ drawer for one, frame by frame, and the main thread does no
/// shadow-specific rendering at all: the blur and fingerprint run on `SkinWindowShadow`'s worker.
///
/// Hosted surfaces — library, browser, video, vis — are AppKit subviews the renderer leaves as holes,
/// so each visible one's frame is added as solid. Built per pull rather than cached in `layout()`:
/// a subview's `isHidden` or `alphaValue` can change without a layout pass.
extension WinampModernMainView {
    var shadowTraceName: String {
        "wal:" + (renderer.container.attributes["id"] ?? renderer.container.stableID.description)
    }

    func attachWindowShadow(to window: NSWindow) {
        windowShadow.attach(to: window, name: shadowTraceName) { [weak self] in
            self?.shadowOutline() ?? []
        }
    }

    private func shadowOutline() -> [CGImage] {
        guard !isTornDown, let outline = frames.outline else { return [] }
        return [outline] + (hostedSurfaceMask().map { [$0] } ?? [])
    }

    /// Every visible hosted surface's frame, solid, at one pixel per point; nil when there is none.
    private func hostedSurfaceMask() -> CGImage? {
        let surfaces = subviews.filter { !$0.isHidden && $0.alphaValue > 0 }
        let width = Int(bounds.width.rounded()), height = Int(bounds.height.rounded())
        guard !surfaces.isEmpty, width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for surface in surfaces { context.fill(surface.frame) }
        return context.makeImage()
    }
}
