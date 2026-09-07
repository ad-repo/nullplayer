import Foundation

/// Which of a skin's `{0000000A-000C-0010-FF7B-01014263450C}` holders gets the host's real
/// visualization engine, and which draw the analyzer instead (BB9).
///
/// `{0000000A}` is Winamp's visualization **plugin host**, not "MilkDrop's box". What renders in it
/// is whichever visualization plugin is selected, and Winamp's own default there is its built-in
/// spectrum analyzer; MilkDrop/AVS appears only when the user has picked it. We mounted the host's
/// engine over *every* such holder unconditionally, and `VisualizationEngineType` has no analyzer in
/// it — so an analyzer in that slot was unreachable by construction rather than a setting nobody had
/// found.
///
/// Two rules, both keyed on the **box** rather than on any skin's object ids:
///
/// 1. A letterbox strip is an analyzer's shape. Big Bento Modern's stretched pane is 1074×147 and
///    its screenshots show an analyzer there; a preset visualizer in a 7:1 slot is not what anyone
///    draws.
/// 2. Only one holder can hold the engine. `makeVisualizationSurface()` deliberately vends **one**
///    surface per skin — two OpenGL contexts, two display links and two spectrum consumers against
///    the same audio is what that cache exists to prevent — so a second holder asking for it got the
///    same view moved out from under the first, which is why "the tab works and the mini doesn't".
///    The engine goes to the largest eligible box, and every other holder draws the analyzer instead
///    of sitting black.
enum WinampModernVisualizationHolder {

    /// At or above this width-to-height ratio a holder is a letterbox strip, and never takes the
    /// engine. Big Bento's three placements measure 7.3 (stretched), 1.0 (mini) and about 2.5 (the
    /// Visualization tab), so the boundary is nowhere near any of them.
    static let analyzerAspectRatio: CGFloat = 3

    static func prefersAnalyzer(frame: CGRect) -> Bool {
        frame.height > 0 && frame.width / frame.height >= analyzerAspectRatio
    }

    /// The same question for a live holder, which can answer from more than its current box.
    ///
    /// Big Bento Modern's stretched pane is declared full-holder-width — a 7:1 strip — and is narrow
    /// only because the side-by-side Multi Content View layout narrowed it (BB9). Measuring the box
    /// it ended up with would take it under the ratio and hand it the engine, so it answers from the
    /// shape its markup declares. Every other holder is still routed on the box alone.
    static func prefersAnalyzer(holder: WinampModernComponentHolder) -> Bool {
        if WinampModernBentoMultiContentView.isStretchedVisualizationPane(holder.object) { return true }
        return prefersAnalyzer(frame: holder.frame)
    }

    /// The one holder the engine mounts in, or `nil` when every live holder is a letterbox strip.
    ///
    /// Ties keep the earliest holder in scene order rather than resolving arbitrarily: a layout pass
    /// that reported the same two boxes in a different order must not move the picture.
    static func engineHolder(among holders: [WinampModernComponentHolder]) -> WasabiObjectID? {
        var best: WinampModernComponentHolder?
        for holder in holders where holder.kind == .visualization && !prefersAnalyzer(holder: holder) {
            guard let current = best else { best = holder; continue }
            let area = holder.frame.width * holder.frame.height
            if area > current.frame.width * current.frame.height { best = holder }
        }
        return best?.object.stableID
    }
}
