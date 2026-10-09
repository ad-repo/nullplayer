import CoreGraphics

/// An `AudionFaceScene` to pixels: integer scale, nearest-neighbour, alpha kept. The harness and
/// the face window both draw through this, so what the sweep measures is what the screen shows.
/// The compositing reproduces FaceKit `AudionFaceView`'s layer stack in one CGContext; see
/// `AudionFaceDrawOp.Layer`.
enum AudionFaceRenderer {
    static func render(_ scene: AudionFaceScene) -> CGImage? {
        let scale = scene.scale
        let width = scene.width * scale, height = scene.height * scale
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        guard let canvas = CGContext.audionFaceBitmap(width: width, height: height) else { return nil }
        func device(_ rect: AudionFaceRect) -> CGRect {
            let flipped = rect.flipped(inHeight: scene.height)
            return CGRect(x: flipped.minX * CGFloat(scale), y: flipped.minY * CGFloat(scale),
                          width: flipped.width * CGFloat(scale), height: flipped.height * CGFloat(scale))
        }

        for layer in AudionFaceDrawOp.Layer.allCases {
            let ops = scene.ops.filter { $0.element.layer == layer }
            switch layer {
            case .base:
                for op in ops { canvas.clear(device(op.rect)); canvas.draw(op.image, in: device(op.rect)) }
            case .buttons:
                for op in ops { canvas.draw(op.image, in: device(op.rect)) }
            case .readouts:
                guard !ops.isEmpty, let readouts = CGContext.audionFaceBitmap(width: width, height: height)
                else { continue }
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
                      let masked = CGContext.audionFaceBitmap(width: width, height: height) else { continue }
                masked.draw(op.image, in: device(op.rect))
                masked.setBlendMode(.sourceIn)
                masked.draw(content, in: bounds)
                return masked.makeImage()
            }
        }
        return canvas.makeImage()
    }
}
