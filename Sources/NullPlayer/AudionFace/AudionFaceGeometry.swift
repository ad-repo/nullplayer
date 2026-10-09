import CoreGraphics

/// A rect in face pixels with a top-left origin, the space `index.json` and every sprite are
/// authored in. Width and height are positive; a zero or negative rect never becomes one.
struct AudionFaceRect: Hashable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

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
