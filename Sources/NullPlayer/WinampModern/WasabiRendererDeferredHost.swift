import AppKit
import CoreGraphics

/// The overlay pass for host components a skin's later layers must not cover.
extension WasabiSceneRenderer {
    static let drawsPlaylistInline =
        ProcessInfo.processInfo.environment["WINAMP_MODERN_INLINE_PLAYLIST"] == "1"

    /// Whether `drawComponent` collects this kind for `drawDeferredHostComponents` instead of
    /// drawing it where the walk meets it. The one place the deferral is decided.
    ///
    /// The library defers only in a window of its own: embedded in the player it shares the canvas with
    /// art the skin draws over it on purpose (Kepler's sun, shown while the tab is closed).
    func defersToOverlayPass(_ kind: WinampModernComponentKind) -> Bool {
        if kind == .waveformSeeker { return true }
        guard !Self.drawsPlaylistInline else { return false }
        switch kind {
        case .playlist: return true
        case .library: return container.xmlID?.caseInsensitiveCompare("main") != .orderedSame
        default: return false
        }
    }

    /// The library's plate; the browser view floats over it. Drawn again in the overlay pass
    /// (`defersToOverlayPass`) at the holder's own box, so a skin layer declared after the holder never
    /// covers it (KTENSION's `ml.frame.layout`, B462) while the border keeps the bleed's pixels.
    func drawLibraryComponent(frame: CGRect, context: WasabiDrawList) {
        context.setFillColor(palette.contentBackground.cgColor)
        context.fill(frame)
    }

    /// Host components the skin backs with its **own** artwork, drawn after the whole scene.
    ///
    /// Winamp gives a plugin-hosted surface a real child window, which floats above every layer the
    /// skin draws. Ours is painted inline at the holder's declared z-position, and for most
    /// components that is the same thing — nothing is declared over a playlist or a video box.
    ///
    /// The seeker is the exception, and it is the skin that makes it one. Big Bento backs its strip
    /// with `<layer id="waveseeker.rounder.bg" image="songticker.background.center2" … visible="0">`,
    /// declared *after* the holder and shown by the skin's own timer **because** the component was
    /// accepted. In Winamp that layer lands behind the plugin's window; here it landed on top, and a
    /// full-width dark panel over the strip is indistinguishable from a strip that never drew — which
    /// is exactly how BB18 presented, right down to the box measuring a uniform `rgb(40,42,48)`.
    ///
    /// So a claimed component is drawn last. The frames are collected during the walk (with the
    /// scene's transform already established) and replayed here inside the same `saveGState`, so the
    /// coordinates are the ones the walk computed.
    ///
    /// The playlist is the second (B292): Ryoko_Asakura declares its character art `pledit.char`
    /// after the list's holder, and Winamp's list window floats over it. Each node is replayed under
    /// its own clip and alpha, which the walk's `saveGState` no longer holds.
    /// `WINAMP_MODERN_INLINE_PLAYLIST=1` is the A/B switch back to the inline draw (the library's too).
    ///
    /// The library is the third (B462): KTENSION declares `ml.frame.layout background="wasabi.frame.basetexture"`
    /// over the whole window after the library's holder, which painted its teal texture over the plate
    /// and left the list's teal text on teal. Winamp's media library is a child window above it.
    func drawDeferredHostComponents(in context: WasabiDrawList) {
        let pending = deferredHostComponents
        deferredHostComponents.removeAll(keepingCapacity: true)
        for (kind, node) in pending {
            context.saveGState()
            node.clipping.apply(to: context)
            applyRegionClip(of: node.object, frame: node.frame, context: context)
            context.setAlpha(Self.hostComponentAlpha(of: node.object))
            switch kind {
            case .playlist: drawPlaylistComponent(node.object, frame: node.frame, context: context)
            case .library: drawLibraryComponent(frame: node.frame, context: context)
            default: drawWaveformSeeker(frame: node.frame, context: context)
            }
            context.restoreGState()
        }
    }
}
