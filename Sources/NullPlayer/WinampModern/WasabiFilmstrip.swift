import CoreGraphics

/// The arithmetic behind `<images>` — which frame of a value-indexed filmstrip to show, and where it
/// sits on the sheet (B88).
///
/// Pure and separate from the renderer so it can be pinned without a skin, a bitmap or a host: the
/// whole defect class here is off-by-one and pitch-versus-height confusion, and neither is visible in
/// a rendered PNG until someone notices the volume bar is one cell short at the top of its range.
enum WasabiFilmstrip {
    /// Frames run **down** the sheet, so the count is the sheet's height over the pitch.
    static func frameCount(sheetHeight: Int, pitch: Int) -> Int {
        guard pitch > 0, sheetHeight >= pitch else { return 0 }
        return sheetHeight / pitch
    }

    /// `normalized` 0…1 across the frames, ends inclusive: 0 is the first frame and 1 the last, so a
    /// volume slider at either stop shows the artwork the skin drew for that stop. Rounding rather
    /// than truncating, so the middle of the range lands on the middle frame instead of biasing low.
    static func frameIndex(normalized: CGFloat, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let scaled = (normalized * CGFloat(count - 1)).rounded()
        return max(0, min(count - 1, Int(scaled)))
    }

    /// The sub-rectangle of the sheet for the frame at `normalized`, or nil when the declaration is
    /// not a filmstrip at all.
    ///
    /// `pitch` is the distance between frame *tops*; `frameHeight` is how much of each frame shows.
    /// ClassicPro's volume sheet is 16 and 15 — one blank row between frames — so conflating the two
    /// draws a row of gaps. A missing `frameHeight` falls back to the pitch, which is right for a
    /// sheet with no gap.
    static func crop(sheetWidth: Int, sheetHeight: Int, pitch: Int,
                     frameHeight: Int?, normalized: CGFloat) -> CGRect? {
        let count = frameCount(sheetHeight: sheetHeight, pitch: pitch)
        guard count > 0, sheetWidth > 0 else { return nil }
        let index = frameIndex(normalized: normalized, count: count)
        let top = index * pitch
        let height = min(frameHeight ?? pitch, sheetHeight - top)
        guard height > 0 else { return nil }
        return CGRect(x: 0, y: top, width: sheetWidth, height: height)
    }
}
