import AppKit

/// A classic-skin footer pinned across the bottom of the library browser in Compact Mode
/// (classic UI). Renders a two-segment "Library | Playlist" toggle that switches the compact
/// window's content region between the library browser and the embedded play queue.
///
/// This is the classic-UI analogue of the modern library window's compact footer toggle. It
/// draws with authentic classic skin colors and the classic bitmap font (via `SkinRenderer`),
/// mirroring the browser's own tab-bar styling, and has ZERO dependency on the modern skin
/// system.
///
/// Coordinate note: like `ClassicCompactPlayerBarView`, everything is laid out in classic
/// *native* pixel units (top-left origin, y grows downward) and a single uniform scale
/// transform fills the on-screen frame. Hit-testing converts mouse points back into that space.
final class ClassicCompactFooterView: NSView {

    /// Native design height — matches the classic browser tab-bar row.
    private let designHeight: CGFloat = SkinElements.PlexBrowser.Layout.tabBarHeight
    /// Small margin from the window edge; the two segments fill the rest edge-to-edge so they
    /// take up the whole footer width (matching the modern library window's toggle).
    private let sideInset: CGFloat = 2

    /// Whether the Playlist segment is the active one (else Library).
    var showingPlaylist = false {
        didSet { if showingPlaylist != oldValue { needsDisplay = true } }
    }

    /// Invoked when the user picks a segment; `true` = Playlist, `false` = Library.
    var onSelect: ((_ showPlaylist: Bool) -> Void)?

    /// Suggested on-screen footer height. Matches the compact player bar's scale convention so
    /// the bitmap chrome is not resampled at a footer-only scale.
    static func preferredHeight() -> CGFloat {
        SkinElements.PlexBrowser.Layout.tabBarHeight * Skin.scaleFactor
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func skinDidChange() { needsDisplay = true }

    // MARK: - Coordinate helpers

    /// Uniform scale from native units → view points.
    private var nativeScale: CGFloat {
        guard designHeight > 0 else { return 1 }
        return bounds.height / designHeight
    }

    /// Footer width in native units.
    private var designWidth: CGFloat {
        let s = nativeScale
        return s > 0 ? bounds.width / s : bounds.width
    }

    private func currentSkin() -> Skin {
        WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
    }

    /// The two segment rects in native units (top-left origin) — (.library, .playlist).
    private func segmentRects() -> (library: NSRect, playlist: NSRect) {
        let barRect = NSRect(x: sideInset, y: 0,
                             width: max(0, designWidth - sideInset * 2),
                             height: designHeight)
        let half = (barRect.width / 2).rounded()
        let library = NSRect(x: barRect.minX, y: 0, width: half, height: designHeight)
        let playlist = NSRect(x: barRect.minX + half, y: 0,
                              width: barRect.width - half, height: designHeight)
        return (library, playlist)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let skin = currentSkin()
        let renderer = SkinRenderer(skin: skin)
        let colors = skin.playlistColors
        let scale = nativeScale

        // Flip to top-left origin, then scale into native units (matches the player bar).
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scale, y: scale)

        // Band background — same treatment as the browser's tab bar row.
        colors.normalBackground.setFill()
        context.fill(NSRect(x: 0, y: 0, width: designWidth, height: designHeight))

        let segments = segmentRects()
        drawSegment("Library", rect: segments.library, isActive: !showingPlaylist,
                    colors: colors, renderer: renderer, context: context)
        drawSegment("Playlist", rect: segments.playlist, isActive: showingPlaylist,
                    colors: colors, renderer: renderer, context: context)

        context.restoreGState()
    }

    private func drawSegment(_ label: String, rect: NSRect, isActive: Bool,
                             colors: PlaylistColors, renderer: SkinRenderer, context: CGContext) {
        // Boxed toggle outline, mirroring the classic browser's tabs (drawTabBar).
        let boxRect = rect.insetBy(dx: 2, dy: 3)
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)
        boxPath.lineWidth = 1
        if isActive {
            colors.currentText.withAlphaComponent(0.12).setFill()
            boxPath.fill()
            colors.currentText.withAlphaComponent(0.8).setStroke()
        } else {
            colors.normalText.withAlphaComponent(0.4).setStroke()
        }
        boxPath.stroke()

        // Centered classic bitmap text — white when active, green otherwise.
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let textWidth = CGFloat(label.count) * charWidth
        let textX = (rect.midX - textWidth / 2).rounded()
        let textY = (rect.midY - charHeight / 2).rounded()
        if isActive {
            _ = renderer.drawSkinTextWhite(label, at: NSPoint(x: textX, y: textY), in: context)
        } else {
            _ = renderer.drawSkinText(label, at: NSPoint(x: textX, y: textY), in: context)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let scale = nativeScale
        guard scale > 0 else { return }
        // View point (bottom-left origin) → native units (top-left origin).
        let nativeX = point.x / scale
        let segments = segmentRects()
        // Split at the divider so the entire footer width is clickable (incl. the thin margins).
        onSelect?(nativeX >= segments.playlist.minX)
    }
}
