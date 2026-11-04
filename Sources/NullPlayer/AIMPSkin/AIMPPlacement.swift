import CoreGraphics

/// Delphi's anchors, as AIMP places a control in its parent (`PlaceInfo`): anchored to both sides
/// of an axis, it stretches between the margins; to one, it keeps that margin; to neither, it keeps
/// the margins' proportion, or the middle when it has none (Mayak-232's reel hubs in their 118-px
/// panels). The renderer and AIMP 3.0's `main.ini` reader (`AIMPSkinLegacy`) both place this way.
enum AIMPPlacement {
    /// `anchors` and `margins` left, top, right, bottom; nil when either is not four numbers.
    static func rect(anchors: [Int], margins: [Int], size: CGSize, in parent: CGRect) -> CGRect? {
        guard anchors.count == 4, margins.count == 4 else { return nil }
        func axis(_ low: Int, _ high: Int, _ mLow: Int, _ mHigh: Int, _ size: CGFloat, _ total: CGFloat) -> (CGFloat, CGFloat) {
            switch (low != 0, high != 0) {
            case (true, true): return (CGFloat(mLow), total - CGFloat(mLow + mHigh))
            case (true, false): return (CGFloat(mLow), size)
            case (false, true): return (total - CGFloat(mHigh) - size, size)
            case (false, false):
                let span = mLow + mHigh
                return (span == 0 ? ((total - size) / 2).rounded() : (CGFloat(mLow) * (total - size) / CGFloat(span)).rounded(), size)
            }
        }
        let (x, w) = axis(anchors[0], anchors[2], margins[0], margins[2], size.width, parent.width)
        let (y, h) = axis(anchors[1], anchors[3], margins[1], margins[3], size.height, parent.height)
        return CGRect(x: parent.minX + x, y: parent.minY + y, width: w, height: h)
    }
}
