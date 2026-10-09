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
