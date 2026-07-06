import CoreGraphics
import Foundation

/// Composites a PeppyMeter meter (background → needle(s)/indicator(s) → foreground) into a
/// CoreGraphics context, faithfully porting PeppyMeter's `circular.py` / `linear.py` geometry.
///
/// Works entirely in CoreGraphics' native **bottom-left, y-up** space. PeppyMeter's config uses a
/// top-left, y-down space, so top-left points are converted with `y_bottomLeft = H - y_topLeft`.
enum PeppyMeterRenderer {

    /// Draw `template` scaled to fit `rect` (aspect preserved, centered), with the given per-channel
    /// volumes (0…100). `left`/`right` are used for stereo; `left` alone drives mono.
    static func draw(
        template: PeppyMeterTemplate,
        leftVolume: Double,
        rightVolume: Double,
        in rect: CGRect,
        context: CGContext,
        library: PeppyMeterLibrary = .shared
    ) {
        let native = library.nativeSize(for: template)
        guard native.width > 0, native.height > 0, rect.width > 0, rect.height > 0 else { return }

        let scale = min(rect.width / native.width, rect.height / native.height)
        let drawnW = native.width * scale
        let drawnH = native.height * scale
        let offsetX = rect.minX + (rect.width - drawnW) / 2
        let offsetY = rect.minY + (rect.height - drawnH) / 2

        context.saveGState()
        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high

        let ctx = MeterContext(context: context, template: template, height: native.height, library: library)

        // Background
        if let bgr = library.image(named: template.bgrFilename) {
            context.draw(bgr, in: CGRect(x: 0, y: 0, width: native.width, height: native.height))
        }

        // Needles / indicators
        switch template.type {
        case .circular:
            if template.channels == 2 {
                ctx.drawNeedle(volume: leftVolume, origin: template.leftOrigin,
                               startAngle: template.leftStartAngle, stopAngle: template.leftStopAngle)
                ctx.drawNeedle(volume: rightVolume, origin: template.rightOrigin,
                               startAngle: template.rightStartAngle, stopAngle: template.rightStopAngle)
            } else {
                ctx.drawNeedle(volume: leftVolume, origin: template.monoOrigin,
                               startAngle: template.leftStartAngle, stopAngle: template.leftStopAngle)
            }
        case .linear:
            if template.channels == 2 {
                ctx.drawLinear(volume: leftVolume, pos: template.leftPos, flip: template.flipLeftX, isLeft: true)
                ctx.drawLinear(volume: rightVolume, pos: template.rightPos, flip: template.flipRightX, isLeft: false)
            } else {
                ctx.drawLinear(volume: leftVolume, pos: template.leftPos, flip: template.flipLeftX, isLeft: true)
            }
        }

        // Foreground overlay
        if let fgrName = template.fgrFilename, let fgr = library.image(named: fgrName) {
            context.draw(fgr, in: CGRect(x: 0, y: 0, width: native.width, height: native.height))
        }

        context.restoreGState()
    }

    // MARK: - Per-meter drawing helpers

    private struct MeterContext {
        let context: CGContext
        let template: PeppyMeterTemplate
        let height: CGFloat
        let library: PeppyMeterLibrary

        /// Convert a PeppyMeter top-left point (plus the meter offset) to bottom-left space.
        func bl(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x + template.meterOffset.x,
                    y: height - (p.y + template.meterOffset.y))
        }

        // MARK: Circular

        func drawNeedle(volume: Double, origin: CGPoint, startAngle: Double, stopAngle: Double) {
            guard let needle = library.image(named: template.indicatorFilename) else { return }
            let v = min(100.0, max(0.0, volume))
            let angleDeg = startAngle + (v / 100.0) * (stopAngle - startAngle)
            let o = bl(origin)
            let w = CGFloat(needle.width)
            let h = CGFloat(needle.height)

            context.saveGState()
            context.translateBy(x: o.x, y: o.y)
            context.rotate(by: CGFloat(angleDeg) * .pi / 180.0)  // CCW-positive, matches PeppyMeter
            // Needle points up at angle 0; its pivot (w/2, h/2 + distance in image space) sits at the origin.
            context.draw(needle, in: CGRect(x: -w / 2, y: -h / 2 + template.distance, width: w, height: h))
            context.restoreGState()
        }

        // MARK: Linear

        func drawLinear(volume: Double, pos: CGPoint, flip: Bool, isLeft: Bool) {
            let filename = template.indicatorFilename
            guard let baseImage = flip ? library.flippedImage(named: filename) : library.image(named: filename) else { return }
            let iw = CGFloat(baseImage.width)
            let ih = CGFloat(baseImage.height)

            let masks = template.linearMasks
            guard masks.count > 1 else { return }
            let stepCount = masks.count - 1
            let v = min(100.0, max(0.0, volume))
            let idx = min(stepCount, max(0, Int((v / 100.0 * Double(stepCount)).rounded())))
            let reveal = masks[idx]
            guard reveal >= 1 else { return }  // nothing lit at zero volume

            // Top-left anchor of the indicator → bottom-left dest origin.
            let anchorTL = CGPoint(x: pos.x + template.meterOffset.x, y: pos.y + template.meterOffset.y)
            let destX = anchorTL.x
            let destY = height - anchorTL.y - ih  // bottom edge of indicator area (bottom-left space)

            let dir = effectiveDirection(isLeft: isLeft)

            if template.indicatorSingle {
                drawSingle(image: baseImage, iw: iw, ih: ih, destX: destX, destY: destY, reveal: reveal, dir: dir)
            } else {
                drawGrowing(image: baseImage, iw: iw, ih: ih, destX: destX, destY: destY, reveal: reveal, dir: dir)
            }
        }

        /// PeppyMeter's mask (growing bar) mode handles only the four cardinal directions; the
        /// symmetric center/edge modes are interpreted per channel (the flipped art mirrors one side).
        private func effectiveDirection(isLeft: Bool) -> PeppyMeterDirection {
            switch template.direction {
            case .centerEdges: return isLeft ? .rightLeft : .leftRight
            case .edgesCenter: return isLeft ? .leftRight : .rightLeft
            default: return template.direction
            }
        }

        private func drawGrowing(image: CGImage, iw: CGFloat, ih: CGFloat,
                                 destX: CGFloat, destY: CGFloat, reveal: CGFloat, dir: PeppyMeterDirection) {
            switch dir {
            case .leftRight, .centerEdges, .edgesCenter:
                let w = min(reveal, iw)
                blit(image, crop: CGRect(x: 0, y: 0, width: w, height: ih),
                     dest: CGRect(x: destX, y: destY, width: w, height: ih))
            case .rightLeft:
                let w = min(reveal, iw)
                blit(image, crop: CGRect(x: iw - w, y: 0, width: w, height: ih),
                     dest: CGRect(x: destX + (iw - w), y: destY, width: w, height: ih))
            case .bottomTop:
                let h = min(reveal, ih)
                blit(image, crop: CGRect(x: 0, y: ih - h, width: iw, height: h),
                     dest: CGRect(x: destX, y: destY, width: iw, height: h))
            case .topBottom:
                let h = min(reveal, ih)
                blit(image, crop: CGRect(x: 0, y: 0, width: iw, height: h),
                     dest: CGRect(x: destX, y: destY + (ih - h), width: iw, height: h))
            }
        }

        private func drawSingle(image: CGImage, iw: CGFloat, ih: CGFloat,
                                destX: CGFloat, destY: CGFloat, reveal: CGFloat, dir: PeppyMeterDirection) {
            var x = destX
            var y = destY
            switch dir {
            case .leftRight:  x = destX + reveal
            case .rightLeft:  x = destX - reveal
            case .bottomTop:  y = destY + reveal
            case .topBottom:  y = destY - reveal
            case .centerEdges: x = destX + reveal   // resolved per-channel before reaching here
            case .edgesCenter: x = destX - reveal
            }
            context.draw(image, in: CGRect(x: x, y: y, width: iw, height: ih))
        }

        private func blit(_ image: CGImage, crop: CGRect, dest: CGRect) {
            guard crop.width >= 1, crop.height >= 1, let cropped = image.cropping(to: crop) else { return }
            context.draw(cropped, in: dest)
        }
    }
}
