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
}
