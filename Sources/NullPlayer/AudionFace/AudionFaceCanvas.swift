import CoreGraphics
import Foundation

/// The face window's pixels, kept between scenes so that a new scene redraws only the rects whose ops
/// changed: the marquee's label box, an animation frame, a digit, a hovered button. Each such rect is
/// rendered whole through `AudionFaceRenderer.render(_:region:)`, so the canvas holds, pixel for
/// pixel, what a full render of the latest scene would.
final class AudionFaceCanvas {
    struct Change {
        /// The rects redrawn, in face pixels; empty when the scene drew nothing new.
        let rects: [AudionFaceRect]
        /// A redrawn pixel changed its alpha, so the window's outline (and its shadow) moved.
        let outlineChanged: Bool
    }

    private(set) var image: CGImage?
    private var scene: AudionFaceScene?
    private var context: CGContext?
    /// The canvas's alpha, top row first, kept beside it: reading the image back would copy all of it.
    /// It decides `Change.outlineChanged` and the window's hit test.
    private var alpha = Data()

    /// Whether the device pixel at (x, y), top-left origin, is drawn at all.
    func isOpaque(x: Int, y: Int) -> Bool {
        guard let image, (0..<image.width).contains(x), (0..<image.height).contains(y) else { return false }
        return alpha[y * image.width + x] > 0
    }

    func draw(_ scene: AudionFaceScene) -> Change {
        let whole = AudionFaceRect(x: 0, y: 0, width: scene.width, height: scene.height)
        var rects = [whole]
        if let previous = self.scene, context != nil,
           (previous.width, previous.height, previous.scale) == (scene.width, scene.height, scene.scale) {
            rects = Self.changedRects(from: previous.ops, to: scene.ops, whole: whole)
        } else {
            context = CGContext.audionFaceBitmap(width: scene.width * scene.scale, height: scene.height * scene.scale)
            alpha = Data(count: scene.width * scene.scale * scene.height * scene.scale)
        }
        self.scene = scene
        guard let context, !rects.isEmpty else { return Change(rects: [], outlineChanged: false) }

        var outlineChanged = false
        context.setBlendMode(.copy)
        for rect in rects {
            guard let region = AudionFaceRenderer.render(scene, region: rect) else { continue }
            let device = rect.scaled(by: scene.scale)
            context.draw(region, in: device.flipped(inHeight: context.height))
            let fresh = Self.alpha(of: region), width = region.width
            for row in 0..<region.height {
                let line = fresh[row * width..<(row + 1) * width]
                let at = (device.y + row) * context.width + device.x
                guard alpha[at..<at + width] != line else { continue }
                outlineChanged = true
                alpha.replaceSubrange(at..<at + width, with: line)
            }
        }
        image = context.makeImage()
        return Change(rects: rects, outlineChanged: outlineChanged)
    }

    /// The rects of the ops one scene has and the other lacks, clipped to the face. An op is the same
    /// when its element, rect and image instance are (`AudionFaceText` hands back the same instance
    /// for the same line). A mask change redraws everything: the pixels outside a mask are cut too.
    /// Identity is only safe to compare because `scene` keeps the previous ops' images alive: a freed
    /// image's identifier can be reused, so storing signatures alone would miss changes.
    private static func changedRects(from old: [AudionFaceDrawOp], to new: [AudionFaceDrawOp],
                                     whole: AudionFaceRect) -> [AudionFaceRect] {
        let changed = Set(old.map(Signature.init)).symmetricDifference(new.map(Signature.init))
        if changed.contains(where: { $0.element == .mask }) { return [whole] }
        return Set(changed.compactMap { $0.rect.intersection(whole) }).sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    private struct Signature: Hashable {
        let element: AudionFaceDrawOp.Element
        let image: ObjectIdentifier
        let rect: AudionFaceRect

        init(_ op: AudionFaceDrawOp) {
            element = op.element
            image = ObjectIdentifier(op.image)
            rect = op.rect
        }
    }

    /// Every pixel's alpha, top row first.
    private static func alpha(of image: CGImage) -> Data {
        var alpha = Data(count: image.width * image.height)
        alpha.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                      bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)?
                .draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return alpha
    }
}
