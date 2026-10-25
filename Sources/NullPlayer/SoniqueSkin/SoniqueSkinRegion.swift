import Foundation

/// A `/rgn/…` entry: a window shape or hit shape Skinmaker rasterised from the author's mask into
/// rectangles. Top-left origin, skin pixels. `right` and `bottom` are exclusive, Win32's `RECT`
/// convention, measured against real Sonique's window outlines (`reference/format.md` § *Container*).
struct SoniqueSkinRegion: Equatable {
    struct Rect: Equatable {
        var left, top, right, bottom: Int
    }

    var bounds: Rect
    var rects: [Rect]

    /// u16 rectangle count, u16 bounds, then `count` u16 rectangles. Nil unless the length is exactly
    /// `10 + 8 × count`, so no rectangle is read past the payload.
    init?(_ payload: Data) {
        let bytes = [UInt8](payload)
        guard bytes.count >= 10 else { return nil }
        func word(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func rect(_ at: Int) -> Rect { Rect(left: word(at), top: word(at + 2), right: word(at + 4), bottom: word(at + 6)) }
        let count = word(0)
        guard bytes.count == 10 + 8 * count else { return nil }
        bounds = rect(2)
        rects = (0..<count).map { rect(10 + 8 * $0) }
    }

    /// Every rectangle cut to `width` × `height`, dropping any left empty (`SQ0010`).
    func clipped(width: Int, height: Int) -> SoniqueSkinRegion {
        var region = self
        func clip(_ r: Rect) -> Rect {
            Rect(left: min(r.left, width), top: min(r.top, height), right: min(r.right, width), bottom: min(r.bottom, height))
        }
        region.bounds = clip(bounds)
        region.rects = rects.map(clip).filter { $0.right > $0.left && $0.bottom > $0.top }
        return region
    }

    init(rect: Rect) {
        bounds = rect
        rects = [rect]
    }

    func contains(_ x: Int, _ y: Int) -> Bool { bounds.contains(x, y) && rects.contains { $0.contains(x, y) } }

    func offset(_ dx: Int, _ dy: Int) -> SoniqueSkinRegion {
        var moved = self
        moved.bounds = bounds.offset(dx, dy)
        moved.rects = rects.map { $0.offset(dx, dy) }
        return moved
    }
}

extension SoniqueSkinRegion.Rect {
    func contains(_ x: Int, _ y: Int) -> Bool { x >= left && x < right && y >= top && y < bottom }
    func offset(_ dx: Int, _ dy: Int) -> Self { .init(left: left + dx, top: top + dy, right: right + dx, bottom: bottom + dy) }
    func union(_ o: Self) -> Self {
        .init(left: min(left, o.left), top: min(top, o.top), right: max(right, o.right), bottom: max(bottom, o.bottom))
    }
}
