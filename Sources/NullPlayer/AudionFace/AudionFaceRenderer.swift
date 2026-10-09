import CoreGraphics

/// An `AudionFaceScene` to pixels: integer scale, nearest-neighbour, alpha kept. The harness and
/// the face window both draw through this, so what the sweep measures is what the screen shows.
/// The compositing reproduces FaceKit `AudionFaceView`'s layer stack in one CGContext; see
/// `AudionFaceDrawOp.Layer`.
enum AudionFaceRenderer {
    /// The whole face, or only `region` (face pixels): an image of the region alone, pixel for pixel
    /// what the whole face shows there, because every op composites only within its own rect.
    /// `AudionFaceCanvas` redraws the face window through regions.
    static func render(_ scene: AudionFaceScene, region: AudionFaceRect? = nil) -> CGImage? {
        let scale = scene.scale
        func device(_ rect: AudionFaceRect) -> CGRect { rect.scaled(by: scale).flipped(inHeight: scene.height * scale) }
        let bounds = device(region ?? AudionFaceRect(x: 0, y: 0, width: scene.width, height: scene.height))
        /// A buffer the size of `bounds`, drawn into in the whole face's device coordinates.
        func buffer() -> CGContext? {
            let context = CGContext.audionFaceBitmap(width: Int(bounds.width), height: Int(bounds.height))
            context?.translateBy(x: -bounds.minX, y: -bounds.minY)
            return context
        }
        guard let canvas = buffer() else { return nil }

        for layer in AudionFaceDrawOp.Layer.allCases {
            let ops = scene.ops.filter { $0.element.layer == layer }
            switch layer {
            case .base:
                for op in ops { canvas.clear(device(op.rect)); canvas.draw(op.image, in: device(op.rect)) }
            case .buttons:
                for op in ops { canvas.draw(op.image, in: device(op.rect)) }
            case .readouts:
                guard !ops.isEmpty, let readouts = buffer() else { continue }
                for op in ops { readouts.clear(device(op.rect)); readouts.draw(op.image, in: device(op.rect)) }
                readouts.makeImage().map { canvas.draw($0, in: bounds) }
            case .labels:
                for op in ops {
                    guard case .label(_, let offset) = op.element else { continue }
                    let box = device(op.rect)
                    canvas.saveGState()
                    canvas.clip(to: box)
                    // Top-aligned at its own pixel size, as FaceKit's flipped label lays it out.
                    canvas.draw(op.image, in: CGRect(x: box.minX + CGFloat(offset),
                                                     y: box.maxY - CGFloat(op.image.height),
                                                     width: CGFloat(op.image.width), height: CGFloat(op.image.height)))
                    canvas.restoreGState()
                }
            case .mask:
                guard let op = ops.first, let content = canvas.makeImage(),
                      let masked = buffer() else { continue }
                masked.draw(op.image, in: device(op.rect))
                masked.setBlendMode(.sourceIn)
                masked.draw(content, in: bounds)
                return masked.makeImage()
            }
        }
        return canvas.makeImage()
    }
}
