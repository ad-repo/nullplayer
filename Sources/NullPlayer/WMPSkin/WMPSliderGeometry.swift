import CoreGraphics
import Foundation

enum WMPSliderDirection: String, Hashable, Codable {
    case horizontal, vertical

    /// `direction="vertical"` outnumbers `horizontal` 1,312 to 664 across the corpus, so the
    /// vertical case is the common one rather than the exception. Absent is horizontal, which is
    /// what WMP defaults to and what the seek bars that omit it rely on.
    init(authored: String?) {
        self = authored?.caseInsensitiveCompare("vertical") == .orderedSame ? .vertical : .horizontal
    }
}

/// Where a slider's thumb sits, and how much of its track is filled, for one resolved value.
///
/// Pure geometry with no resource or graph access, because every one of its rules is a claim about
/// WMP that a unit test can pin: a vertical slider's maximum is at the *top*, and `borderSize` is
/// dead track at both ends that the thumb never enters.
struct WMPSliderMetrics: Hashable {
    let direction: WMPSliderDirection
    let minimum: Double
    let maximum: Double
    let value: Double
    /// Dead track at each end. WMP's `borderSize` is authored by 172 of 178 corpus skins, and a
    /// seek bar whose thumb is drawn ignoring it overhangs its own artwork by up to ten pixels.
    let borderSize: CGFloat

    /// 0 at `minimum`, 1 at `maximum`. A degenerate range answers 0 rather than dividing by it.
    var fraction: Double {
        let span = maximum - minimum
        guard span.isFinite, span != 0, value.isFinite else { return 0 }
        return max(0, min(1, (value - minimum) / span))
    }

    /// The thumb's frame inside `track`, given the thumb artwork's own size.
    ///
    /// The thumb is centred across the track's short axis and travels along the long one between
    /// the two `borderSize` insets. A vertical slider runs bottom-to-top: `maximum` is at
    /// `track.y`, which is what puts an equaliser's +14 dB at the top of its bar.
    func thumbFrame(in track: WMPRect, thumbSize: WMPSize) -> WMPRect {
        switch direction {
        case .horizontal:
            let travel = max(0, track.width - 2 * borderSize - thumbSize.width)
            return WMPRect(x: track.x + borderSize + travel * CGFloat(fraction),
                           y: track.y + (track.height - thumbSize.height) / 2,
                           width: thumbSize.width, height: thumbSize.height)
        case .vertical:
            let travel = max(0, track.height - 2 * borderSize - thumbSize.height)
            return WMPRect(x: track.x + (track.width - thumbSize.width) / 2,
                           y: track.y + borderSize + travel * CGFloat(1 - fraction),
                           width: thumbSize.width, height: thumbSize.height)
        }
    }

    /// The filled portion of the track, for a slider that draws a `foregroundImage` progress bar.
    /// Horizontal fills from the left, vertical from the bottom — the same basis as the thumb.
    func progressRect(in track: WMPRect) -> WMPRect {
        switch direction {
        case .horizontal:
            return WMPRect(x: track.x, y: track.y,
                           width: track.width * CGFloat(fraction), height: track.height)
        case .vertical:
            let filled = track.height * CGFloat(fraction)
            return WMPRect(x: track.x, y: track.maxY - filled, width: track.width, height: filled)
        }
    }

    /// The value a pointer at `point` selects. The inverse of `thumbFrame`, so a press lands the
    /// thumb under the pointer rather than beside it, and the same `borderSize` is honoured.
    func value(at point: WMPPoint, in track: WMPRect, thumbSize: WMPSize) -> Double {
        let fraction: CGFloat
        switch direction {
        case .horizontal:
            let travel = max(0, track.width - 2 * borderSize - thumbSize.width)
            guard travel > 0 else { return minimum }
            fraction = (point.x - track.x - borderSize - thumbSize.width / 2) / travel
        case .vertical:
            let travel = max(0, track.height - 2 * borderSize - thumbSize.height)
            guard travel > 0 else { return minimum }
            fraction = 1 - (point.y - track.y - borderSize - thumbSize.height / 2) / travel
        }
        return minimum + Double(max(0, min(1, fraction))) * (maximum - minimum)
    }
}
