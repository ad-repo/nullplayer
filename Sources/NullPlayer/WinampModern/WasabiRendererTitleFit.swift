import CoreGraphics
import Foundation

/// A window wide enough to show its own title (B282).
extension WasabiSceneRenderer {
    /// `size` widened until the window's title draws whole inside what clips it.
    ///
    /// Silverskin_3's frame titles are a bitmap font with a 20px advance: `PLAYLIST EDITOR` is 300px
    /// in a playlist whose only stated width is its 275 minimum, and `SILVERSKIN3 HELP` 320px in a
    /// help window pinned at 250, so centred they read `AYLIST EDITO` and `VERSKIN HE`. The rule
    /// outranks the skin's `maximum_w` — it is a floor, and `userResizeLimits` keeps the maximum at
    /// or above every floor — because a window that cannot show its own name is not a size anybody
    /// meant.
    ///
    /// Measured on the resolved scene, never from the box alone: Aria_of_the_Soul's title box starts
    /// 29px into a group exactly as wide as itself, so the group cuts the string well before the box
    /// does, and a centred string there gains only half of each pixel the window grows. So the window
    /// is grown, resolved again, and stepped by the rate the gap actually closed at.
    ///
    /// Only a title whose **box** stretches with the window is fitted. One with an absolute width
    /// (JRS's 45px) cannot be helped, and one a script places (stock Winamp Modern's titlebar centres
    /// its own autowidth title between two streaks on `onResize`) sits wherever the script last put it
    /// on a hypothetical canvas the script never saw — winampmodern566's album art grew 40px for it.
    func titleFittedSize(_ size: CGSize) -> CGSize {
        guard var last = titleShortfall(atCanvas: size), last.shortfall >= 1 else { return size }
        var grown = size
        var step = last.shortfall
        for _ in 0..<4 {
            let previousWidth = grown.width
            grown.width = (grown.width + step).rounded(.up)
            // The stretch test: a box that did not widen with the window is fixed or script-placed.
            guard let next = titleShortfall(atCanvas: grown), next.box > last.box else { return size }
            if next.shortfall < 1 { return grown }
            let rate = (last.shortfall - next.shortfall) / (grown.width - previousWidth)
            guard rate > 0 else { return size }
            step = next.shortfall / rate
            last = next
        }
        return size
    }

    /// How many pixels of the window's title its clip cuts at `canvas`, the width of its box, and the
    /// title itself — `nil` when no title is drawn. Only the title with the most room counts: Prakrit
    /// keeps a 1px copy of each beside the visible one.
    func titleShortfall(atCanvas canvas: CGSize) -> (shortfall: CGFloat, box: CGFloat, text: String)? {
        let room = { (node: WasabiSceneNode) in node.frame.intersection(node.clip).width }
        guard let title = sceneNodes(canvas: canvas)
            .filter({ $0.object.tag.is(.text) && WasabiTextMetrics.showsWindowTitle($0.object, host: host) })
            .max(by: { room($0) < room($1) }) else { return nil }
        let text = WasabiTextMetrics.content(of: title.object, host: host)
        let width = resources.metrics.contentWidth(of: title.object, text: text)
        let frame = title.frame
        let start: CGFloat
        switch WasabiTextMetrics.horizontalAlignment(of: title.object) {
        case .center: start = frame.midX - width / 2
        case .right: start = frame.maxX - width
        default: start = frame.minX
        }
        return (max(0, title.clip.minX - start) + max(0, start + width - title.clip.maxX), frame.width, text)
    }
}
