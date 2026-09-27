import Foundation

/// Only copied decoder facts cross into JScript. No player, drawable, or media credentials do.
struct WMPVideoSnapshot: Hashable, Codable {
    var width: Double = 0
    var height: Double = 0
    var fullScreen = false
    var hasVideo: Bool { width.isFinite && height.isFinite && width > 0 && height > 0 }
}

/// Keeps WMP's media edge state stable while VLC briefly drops its drawable output during a
/// same-media vout rebuild. The live snapshot remains separate so a hosted child window can still
/// detach and release mouse capture during that gap.
struct WMPVideoEventLatch {
    private var mediaIdentity: String?
    private var lastValidSnapshot = WMPVideoSnapshot()

    mutating func reset() {
        mediaIdentity = nil
        lastValidSnapshot = WMPVideoSnapshot()
    }

    mutating func update(mediaIdentity: String, current: WMPVideoSnapshot,
                         didReachEnd: Bool) -> WMPVideoSnapshot {
        if self.mediaIdentity != mediaIdentity {
            self.mediaIdentity = mediaIdentity
            lastValidSnapshot = WMPVideoSnapshot()
        }
        if didReachEnd {
            lastValidSnapshot = WMPVideoSnapshot()
        } else if current.hasVideo {
            lastValidSnapshot = current
        }
        return lastValidSnapshot
    }
}

/// VIDEO's fit flags apply independently to shrinking and enlarging. They do not mean crop/fill.
///
/// **`shrinkToFit` defaults to true and `stretchToFit` to false**, which is the asymmetry the
/// corpus is authored against: 77 of the 97 sized `<VIDEO>` elements declare no `shrinkToFit` at
/// all and 73 of those are boxes under 640x480 — a 200x150 hole for a picture no 2000s clip was
/// ever smaller than. Defaulting it false drew every one of them at native pixel size, centred and
/// clipped to the middle sliver of the frame. **Not one archive authors `shrinkToFit="false"`**,
/// so nothing in the corpus asks to be cropped, while 19 author `stretchToFit="true"` and one
/// `"false"` — a flag skins do set both ways, and therefore one with a default worth honouring.
struct WMPVideoPresentation: Hashable, Codable {
    var shrinkToFit = true
    var stretchToFit = false
    var maintainAspectRatio = true
    var alpha: Double = 1

    func imageRect(source: CGSize, bounds: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        func allowed(_ scale: CGFloat) -> CGFloat {
            if scale < 1 { return shrinkToFit ? scale : 1 }
            return stretchToFit ? scale : 1
        }
        let x = bounds.width / source.width, y = bounds.height / source.height
        let sx = allowed(maintainAspectRatio ? min(x, y) : x)
        let sy = maintainAspectRatio ? sx : allowed(y)
        let size = CGSize(width: source.width * sx, height: source.height * sy)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func events(previous: WMPVideoSnapshot?, current: WMPVideoSnapshot) -> [String] {
        let hadVideo = previous?.hasVideo == true
        guard hadVideo != current.hasVideo else { return [] }
        return [current.hasVideo ? "videostart" : "videoend"]
    }

    /// Returns whether a script sized the view from the **decoder** rather than from its own
    /// layout — the family of formulas a `.wmz` writes in `StartVideo()` / `SnapToVideo()`.
    ///
    /// NullPlayer hosts video in the authored box and fits the image there, so an assignment like
    /// this is refused outright: letting it reach the scene makes stretch-aligned parents grow
    /// while the computed `<WMPVIDEO>`/`<EFFECTS>` expressions still carry the previous box size,
    /// producing a tall narrow surface and oversized drawers. **And on modern media it is simply
    /// not a window any more**: `Combat_Flight_Simulator_3`'s `SnapToVideo()` asks for 2580x1532 on
    /// a 2560x1440 clip, which is off the edge of the display on every axis. Reported 2026-09-19 as
    /// "a massive window with no on-screen controls"; fitting it to the screen instead is not an
    /// answer either — the reporter's words for that were "it should not open full screen".
    ///
    /// Two shapes, and the corpus authors both:
    ///
    /// 1. **The shell formula**, `authored view + decoder − authored video box`. Corona and Classic.
    /// 2. **The zoom formula**, `decoder × zoom + shell`, where `zoom` is one of WMP's own
    ///    `mediacenter.videoZoom` steps (50/75/100/150/200 %) and `shell` is the chrome the skin
    ///    draws around the picture — `view.width = imageSourceWidth * (zoom/100) + 20` and
    ///    `+ 92` for the height in `Combat_Flight_Simulator_3`, which is 80-odd archives' shape.
    ///
    /// Both are recognised only as a **growth past the authored view**, which is what keeps a
    /// compact-mode *shrink* out of it: `Compact`'s `SwitchSmall()` assigns 475x373 into a 593x600
    /// view and is a layout decision that has nothing to do with the picture.
    static func isMediaDrivenViewSize(_ assigned: WMPSize,
                                      authoredViewSize: WMPSize,
                                      authoredVideoSize: WMPSize?,
                                      source: WMPVideoSnapshot) -> Bool {
        guard source.hasVideo,
              assigned.width.isFinite, assigned.height.isFinite,
              authoredViewSize.width.isFinite, authoredViewSize.height.isFinite,
              authoredViewSize.width > 0, authoredViewSize.height > 0 else { return false }

        let tolerance: CGFloat = 1
        // `authoredVideoSize` is nil wherever the `<VIDEO>` takes its size from a sibling rather
        // than from the view; only the shell formula needs it.
        if let box = authoredVideoSize, box.width.isFinite, box.height.isFinite,
           box.width > 0, box.height > 0 {
            let expected = WMPSize(width: authoredViewSize.width + CGFloat(source.width) - box.width,
                                   height: authoredViewSize.height + CGFloat(source.height) - box.height)
            if expected.width > authoredViewSize.width, expected.height > authoredViewSize.height,
               abs(assigned.width - expected.width) <= tolerance,
               abs(assigned.height - expected.height) <= tolerance {
                return true
            }
        }
        // The zoom formula. Only a *growth* qualifies, and the leftover on each axis has to look
        // like chrome: never negative, and never more than the window the skin authored — the two
        // bounds that keep an ordinary layout assignment from matching one of these five scales by
        // coincidence. Both axes must agree on the same zoom, because that is one expression
        // evaluated twice in the skin's own handler.
        guard assigned.width > authoredViewSize.width + tolerance,
              assigned.height > authoredViewSize.height + tolerance else { return false }
        return videoZoomSteps.contains { zoom in
            let pictureWidth = CGFloat(source.width) * zoom, pictureHeight = CGFloat(source.height) * zoom
            let shellWidth = assigned.width - pictureWidth, shellHeight = assigned.height - pictureHeight
            return shellWidth >= -tolerance && shellHeight >= -tolerance
                && shellWidth <= authoredViewSize.width && shellHeight <= authoredViewSize.height
                // **The picture has to be most of the window**, or this is not a window built
                // around a picture. Without it the rule reaches ordinary layout on small media: a
                // drawer growing 300x200 → 400x260 beside a 320x240 clip matches `zoom = 0.5` on
                // both axes with the shell absorbing the rest, and the skin's own drawer would
                // then be refused as a decoder resize. 50 % is far below anything the real shape
                // produces — `Combat_Flight_Simulator_3`'s picture is 99 % of its window's width.
                && pictureWidth >= assigned.width * 0.85 && pictureHeight >= assigned.height * 0.85
        }
    }

    /// `mediacenter.videoZoom`'s own steps, which is what the corpus's zoom buttons cycle through:
    /// `Combat_Flight_Simulator_3` walks 75 → 100 → 150 → 200 and back, and every sibling skin
    /// built from the same template walks the same four. 50 % is WMP's fifth and is authored by the
    /// "Half Size" menu item rather than by a button.
    static let videoZoomSteps: [CGFloat] = [0.5, 0.75, 1, 1.5, 2]
}
