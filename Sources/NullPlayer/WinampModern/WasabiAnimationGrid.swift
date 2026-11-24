import CoreGraphics

/// How an animated layer's sheet is cut into frames: one frame's size, how many there are, and how
/// many sit side by side. Shared by the frame the layer draws, the region it can be clicked on and
/// the length a script's `getLength()` reads.
struct WasabiAnimationGrid {
    let width: Int
    let height: Int
    let count: Int
    let columns: Int
    /// The box is larger than the whole sheet, so the sheet is the one frame, shown at its own
    /// size from the box's top left. ONYX V2's shade volume fill is an 89x12 image in an 89x24
    /// box: cut at the box's height it ran off the bitmap and nothing drew, and stretched it would
    /// spill out of its 13px track. Only this case: a sheet *larger* than its box (Lobe's 59x2006
    /// strips in 110x113 boxes) is still cut by the box, and a frame smaller than its box by
    /// `framewidth`/`frameheight` is still stretched (Nullsoft 2000 SP4 Lite's `frameheight="1"
    /// h="5"`).
    let isWholeSheet: Bool

    /// The one cut of a sheet, read by the renderer and by `getLength()` alike so the frame a
    /// script steps to is the frame drawn.
    init(sheetWidth: Int, sheetHeight: Int, attributes: [String: String]) {
        let boxWidth = max(1, Int(Double(attributes["framewidth"] ?? attributes["w"] ?? "") ?? Double(sheetWidth)))
        let boxHeight = max(1, Int(Double(attributes["frameheight"] ?? attributes["h"] ?? "") ?? Double(sheetHeight)))
        isWholeSheet = sheetWidth <= boxWidth && sheetHeight <= boxHeight
            && (sheetWidth < boxWidth || sheetHeight < boxHeight)
        // A box wider (or taller) than the sheet on one axis is a strip one frame across on that
        // axis: SUPER_BLACK's ClassicPro beat layer is 86 wide for its VU art, and the 43 px strips
        // of its other styles were cut 86 wide, ran off the sheet and drew nothing.
        width = max(1, isWholeSheet ? sheetWidth : min(boxWidth, sheetWidth))
        height = max(1, isWholeSheet ? sheetHeight : min(boxHeight, sheetHeight))
        columns = max(1, sheetWidth / width)
        let rows = max(1, sheetHeight / height)
        count = max(1, Int(Double(attributes["frames"] ?? "") ?? Double(columns * rows)))
    }

    /// Where the current frame is drawn, and where it is hit-tested, inside the layer's `frame`.
    func drawRect(in frame: CGRect) -> CGRect {
        guard isWholeSheet else { return frame }
        return CGRect(x: frame.minX, y: frame.minY,
                      width: min(frame.width, CGFloat(width)), height: min(frame.height, CGFloat(height)))
    }
}
