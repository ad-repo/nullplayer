import AppKit

enum ModernSonosChrome {
    static func draw(in bounds: NSRect, window: NSWindow?, closePressed: Bool,
                     titleHeight: CGFloat, closeRect: NSRect, context: CGContext) {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        let renderer = ModernSkinRenderer(skin: skin)
        let edges = window.map { WindowManager.shared.computeAdjacentEdges(for: $0) } ?? []
        let corners = window.map { WindowManager.shared.computeSharpCorners(for: $0) } ?? []
        renderer.drawWindowBackground(in: bounds, context: context, adjacentEdges: edges, sharpCorners: corners)
        renderer.drawWindowBorder(in: bounds, context: context, adjacentEdges: edges, sharpCorners: corners,
                                  occlusionSegments: window.map { WindowManager.shared.computeEdgeOcclusionSegments(for: $0) } ?? .empty)
        guard !WindowManager.shared.effectiveHideTitleBars(for: window) else { return }
        let scale = ModernSkinElements.scaleFactor
        renderer.drawTitleBar(in: NSRect(x: 0, y: (bounds.height - titleHeight) / scale,
                                         width: bounds.width / scale, height: titleHeight / scale),
                              title: "SONOS", prefix: "spectrum_", context: context)
        renderer.drawWindowControlButton("spectrum_btn_close", state: closePressed ? "pressed" : "normal",
            in: NSRect(x: closeRect.minX / scale, y: closeRect.minY / scale,
                       width: closeRect.width / scale, height: closeRect.height / scale), context: context)
    }
}
