import CoreGraphics

/// A rect in face pixels with a top-left origin, the space `index.json` and every sprite are
/// authored in. Width and height are positive; a zero or negative rect never becomes one.
struct AudionFaceRect: Hashable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    func contains(x px: Int, y py: Int) -> Bool {
        (x..<x + width).contains(px) && (y..<y + height).contains(py)
    }

    /// The part of this rect inside `other`; nil when they do not overlap.
    func intersection(_ other: AudionFaceRect) -> AudionFaceRect? {
        let left = max(x, other.x), top = max(y, other.y)
        let right = min(x + width, other.x + other.width), bottom = min(y + height, other.y + other.height)
        return right > left && bottom > top ? AudionFaceRect(x: left, y: top, width: right - left, height: bottom - top) : nil
    }

    /// The same rect `scale` times larger, still top-left: face pixels to device pixels.
    func scaled(by scale: Int) -> AudionFaceRect {
        AudionFaceRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    /// The same rect in a bottom-left space `containerHeight` pixels tall, which is CoreGraphics'
    /// and AppKit's (FaceKit `flippedRect(from:height:)` before its scale). This is the family's
    /// one flip; never re-derive it at a call site.
    func flipped(inHeight containerHeight: Int) -> CGRect {
        CGRect(x: x, y: containerHeight - y - height, width: width, height: height)
    }
}

extension CGContext {
    /// A transparent 8-bit premultiplied RGBA bitmap that draws images nearest-neighbour: every
    /// buffer the face engine draws into.
    static func audionFaceBitmap(width: Int, height: Int) -> CGContext? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.interpolationQuality = .none
        return context
    }
}
