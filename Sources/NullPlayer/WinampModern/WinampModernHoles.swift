import CoreGraphics

/// The see-through holes inside a `.wal` window's outline: alpha-0 pixels the window's edge cannot
/// reach through other alpha-0 pixels.
///
/// The window server hands a click on an alpha-0 pixel to whatever is behind the window, so a skin
/// whose art leaves a hole in its body (LiquidStar's star, 2026-11-10) sent a press there to the
/// desktop or another app. Outside the silhouette that is right — the window is its shape — but a
/// hole is part of the window to anyone aiming at it. The view backs each hole with a pixel of
/// alpha 1 (`backing`), which the eye cannot see and the window server delivers, and claims the press
/// in `hitTest` (`contains`).
///
/// ponytail: a Swift flood fill over the canvas, run only when a frame changed the outline. Fine at
/// the corpus's window sizes; an outline that animates every frame at a large size pays it per frame.
struct WinampModernHoles {
    let width: Int
    let height: Int
    /// 1 for a hole pixel, top row first; empty when the outline has no hole.
    private let mask: [UInt8]
    /// Black at alpha 1 over every hole, transparent elsewhere; nil when there is no hole.
    let backing: CGImage?

    var isEmpty: Bool { mask.isEmpty }
    /// How many canvas pixels are hole. This and `samplePixel` are read only by the intake smoke's
    /// `holes` row (`WinampModernDebugClickSweep`), once per window, never per frame.
    var pixelCount: Int { mask.reduce(0) { $0 + Int($1) } }
    /// A canvas pixel inside a hole, bottom-left origin: the intake smoke's report of where one is.
    var samplePixel: (x: Int, y: Int)? {
        mask.firstIndex(of: 1).map { (x: $0 % width, y: height - 1 - $0 / width) }
    }

    init(alpha: [UInt8], width: Int, height: Int) {
        self.width = width
        self.height = height
        let count = width * height
        guard width > 0, height > 0, alpha.count >= count else {
            mask = []; backing = nil; return
        }
        // 0 = transparent and not yet reached, 1 = opaque, 2 = transparent and reached from the edge.
        var state = [UInt8](repeating: 0, count: count)
        var stack: [Int] = []
        alpha.withUnsafeBufferPointer { alpha in
            state.withUnsafeMutableBufferPointer { state in
                for index in 0..<count where alpha[index] != 0 { state[index] = 1 }
                func seed(_ index: Int) {
                    guard state[index] == 0 else { return }
                    state[index] = 2
                    stack.append(index)
                }
                for x in 0..<width { seed(x); seed((height - 1) * width + x) }
                for y in 0..<height { seed(y * width); seed(y * width + width - 1) }
                while let index = stack.popLast() {
                    let x = index % width
                    if x > 0 { seed(index - 1) }
                    if x < width - 1 { seed(index + 1) }
                    if index >= width { seed(index - width) }
                    if index + width < count { seed(index + width) }
                }
            }
        }
        guard state.contains(0) else { mask = []; backing = nil; return }
        mask = state.map { $0 == 0 ? 1 : 0 }
        var pixels = [UInt8](repeating: 0, count: count * 4)
        for index in 0..<count where mask[index] == 1 { pixels[index * 4 + 3] = 1 }
        backing = pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// Whether canvas pixel (`x`, `y`), bottom-left origin, is in a hole.
    func contains(x: Int, y: Int) -> Bool {
        guard !mask.isEmpty, x >= 0, y >= 0, x < width, y < height else { return false }
        return mask[(height - 1 - y) * width + x] == 1
    }
}
