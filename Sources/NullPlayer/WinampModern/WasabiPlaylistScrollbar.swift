import AppKit
import CoreGraphics

/// The embedded playlist's vertical scrollbar (B284).
///
/// Winamp draws the playlist component itself, scrollbar included, from the skin's
/// `wasabi.scrollbar.vertical.*` bitmaps; NEO's `screenshot.jpg` shows it at the list's right edge
/// over a long queue. It shows only while the queue overflows the panel, so a skin whose queue
/// fits draws exactly what it drew before. Width is the skin's thumb bitmap's; the thumb never
/// draws shorter than its own bitmap (or half the track, on a short panel). A skin with no
/// scrollbar bitmaps gets the `wasabi.scrollbar.background`/`foreground` colours, then the list's
/// own. No arrow buttons: the reference shows none on the playlist.
extension WasabiSceneRenderer {
    struct PlaylistScrollbar: Equatable {
        let track: CGRect
        let thumb: CGRect
    }

    private static let playlistScrollbarFallbackWidth: CGFloat = 10
    private static let playlistScrollbarMinimumThumb: CGFloat = 12

    /// The bar for a playlist holder's frame, or nil while every row fits.
    func playlistScrollbar(in frame: CGRect, rowCount: Int,
                           holder: WasabiObject? = nil) -> PlaylistScrollbar? {
        let visible = playlistVisibleRowCount(in: frame, holder: holder)
        guard visible > 0, rowCount > visible else { return nil }
        let thumbArt = resources.bitmap(identifier: "wasabi.scrollbar.vertical.button")
        let width = min(frame.width / 2, thumbArt.map { CGFloat($0.width) }
            ?? resources.bitmap(identifier: "wasabi.scrollbar.vertical.background").map { CGFloat($0.width) }
            ?? Self.playlistScrollbarFallbackWidth)
        let track = CGRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)
        // Never under half the track, or a short panel's thumb fills it and shows no position.
        let minimum = min(track.height / 2, thumbArt.map { CGFloat($0.height) } ?? Self.playlistScrollbarMinimumThumb)
        let height = min(track.height, max(minimum, track.height * CGFloat(visible) / CGFloat(rowCount)))
        let maxOffset = rowCount - visible
        let offset = max(0, min(maxOffset, playlistScrollOffset))
        let y = track.minY + (track.height - height) * CGFloat(offset) / CGFloat(maxOffset)
        return PlaylistScrollbar(track: track,
                                 thumb: CGRect(x: track.minX, y: y.rounded(), width: width, height: height))
    }

    /// Scroll so the thumb's top sits at `thumbTop` — the drag, and a press on the bare track.
    func dragPlaylistScrollbar(thumbTop: CGFloat, rowCount: Int, in frame: CGRect,
                               holder: WasabiObject? = nil) {
        guard let bar = playlistScrollbar(in: frame, rowCount: rowCount, holder: holder) else { return }
        let travel = bar.track.height - bar.thumb.height
        let maxOffset = rowCount - playlistVisibleRowCount(in: frame, holder: holder)
        let fraction = travel > 0 ? min(1, max(0, (thumbTop - bar.track.minY) / travel)) : 0
        let target = Int((fraction * CGFloat(maxOffset)).rounded())
        scrollPlaylist(byRows: target - playlistScrollOffset, rowCount: rowCount, in: frame, holder: holder)
    }

    func drawPlaylistScrollbar(_ bar: PlaylistScrollbar, context: WasabiDrawList) {
        let palette = rowPalette
        if let track = resources.bitmap(identifier: "wasabi.scrollbar.vertical.background") {
            drawTiled(track, in: bar.track, tileX: false, tileY: true, context: context)
        } else if let color = declaredScrollbarColor("wasabi.scrollbar.background") {
            context.setFillColor(color.cgColor)
            context.fill(bar.track)
        }
        if let thumb = resources.bitmap(identifier: "wasabi.scrollbar.vertical.button") {
            drawImage(thumb.image, in: bar.thumb, context: context)
        } else {
            let color = declaredScrollbarColor("wasabi.scrollbar.foreground")
                ?? palette.listText.withAlphaComponent(0.5)
            context.setFillColor(color.cgColor)
            context.fill(bar.thumb)
        }
        if let grip = resources.bitmap(identifier: "wasabi.scrollbar.vertical.grip"),
           CGFloat(grip.width) <= bar.thumb.width, CGFloat(grip.height) <= bar.thumb.height {
            let rect = CGRect(x: (bar.thumb.midX - CGFloat(grip.width) / 2).rounded(.down),
                              y: (bar.thumb.midY - CGFloat(grip.height) / 2).rounded(.down),
                              width: CGFloat(grip.width), height: CGFloat(grip.height))
            drawImage(grip.image, in: rect, context: context)
        }
    }

    private func declaredScrollbarColor(_ identifier: String) -> NSColor? {
        guard loadedSkin.runtime.resources.resolvedColorDefinition(identifier: identifier) != nil else { return nil }
        return resolvedColor(identifier)
    }
}
