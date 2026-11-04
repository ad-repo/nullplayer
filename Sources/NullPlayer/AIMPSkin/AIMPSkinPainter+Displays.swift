import CoreGraphics
import Foundation

/// What a skin shows of the player beyond its pictures: the equalizer curve, cover art, frosted
/// glass, the oscilloscope and the spectrum.
extension AIMPSkinPainter {
    /// An `EqualizerDisplay`: its panel, the preamp level as a line and the bands as a smooth
    /// curve, ±12 dB over the height, in the skin's `ColorPreamp` and `ColorCurve`.
    func drawEqualizer(preamp: UInt32?, curve: UInt32?, image: AIMPSkinImage?, in rect: CGRect) {
        paint(image, in: rect)
        let inner = rect.insetBy(dx: 2, dy: 2)
        func y(_ value: Double) -> CGFloat { inner.midY - CGFloat(value * 2 - 1) * inner.height / 2 }
        if let preamp {
            context.setStrokeColor(AIMPSkinText.color(preamp))
            context.setLineWidth(1)
            context.strokeLineSegments(between: [CGPoint(x: inner.minX, y: y(host.player.preamp)), CGPoint(x: inner.maxX, y: y(host.player.preamp))])
        }
        let gains = host.player.eqGains
        guard let curve, gains.count > 1 else { return }
        let points = gains.enumerated().map { i, gain in
            CGPoint(x: inner.minX + inner.width * CGFloat(i) / CGFloat(gains.count - 1), y: y(gain))
        }
        // Catmull–Rom through the bands, as a Bézier path.
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        context.saveGState()
        context.clip(to: rect)
        context.addPath(path)
        context.setStrokeColor(AIMPSkinText.color(curve))
        context.setLineWidth(1.5)
        context.strokePath()
        context.restoreGState()
    }

    /// A `CoverArtDisplay`: the playing track's artwork filling its rect, inside the skin's mask
    /// frame (`MaskFrame`: SL-1200's round record label), with the skin's own picture over it: its
    /// `CoverFrame` where it names one (RealPlayer 11's gloss; its frame 0 is "no cover"), else frame 0.
    /// Without artwork the skin's label shows, or the "no cover" frame of a skin that names a `CoverFrame`.
    func drawCoverArt(_ cover: AIMPControlClass.Cover, mask maskFrame: Int?, image: AIMPSkinImage?, in rect: CGRect) {
        guard let artwork = host.player.coverArt else {
            if cover.coverFrame != nil { paint(image, in: rect, frame: 0) }
            return
        }
        context.saveGState()
        if let maskFrame, let image, let mask = AIMPSkinCanvas.mask(image, frame: maskFrame) {
            canvas.clip(to: rect, mask: mask)
        }
        // `BlurLevel` blurs it (Soot's backdrop behind its player pane), once per cover and level.
        let art = cover.blur.flatMap { level in
            flow.skin.blurredCovers.image(artwork, level: level) { AIMPSkinCanvas.blurred(artwork, level: level) }
        } ?? artwork
        // Fill: the shorter side fits, the longer is cropped.
        let scale = max(rect.width / CGFloat(art.width), rect.height / CGFloat(art.height))
        let size = CGSize(width: CGFloat(art.width) * scale, height: CGFloat(art.height) * scale)
        let drawn = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        // Cropped to its box: W10's 136×604 strip behind its icon bar spilled a 604-px cover over the page.
        context.clip(to: rect)
        context.translateBy(x: 0, y: drawn.minY * 2 + drawn.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(art, in: drawn)
        context.restoreGState()
        if let coverFrame = cover.coverFrame {
            paint(image, in: rect, frame: coverFrame)
        } else if let maskFrame, maskFrame != 0 {
            paint(image, in: rect, frame: 0)
        }
    }

    /// A `BlurredGlass`: what is drawn under it so far, blurred by `BlurLevel` (0–100), inside its
    /// skin's mask frame (`MaskFrame`: Soot's round 50-px key backs), tinted by its `Color`.
    func drawBlurredGlass(blur: Double?, tint: AIMPSkinColor?, mask maskFrame: Int?, image: AIMPSkinImage?, in rect: CGRect) {
        let pixels = rect.intersection(CGRect(x: 0, y: 0, width: context.width, height: context.height)).integral
        guard pixels.width > 1, pixels.height > 1, let backdrop = canvas.drawnSoFar(in: pixels) else { return }
        let glass = AIMPSkinCanvas.blurred(backdrop, level: blur ?? 50) ?? backdrop
        // The mask frame names where the glass is; a picture without one is the shape itself.
        context.saveGState()
        context.clip(to: image.map { AIMPSkinCanvas.drawnRect($0, in: rect) } ?? rect)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        canvas.drawUpright(glass, in: pixels)
        if let image, image.hasPixels {
            context.setBlendMode(.destinationIn)
            paint(image, in: rect, frame: maskFrame ?? 0)
        }
        if let tint = argb(tint), tint >> 24 != 0 {
            context.setBlendMode(.sourceAtop)
            canvas.fill(rect, argb: tint)
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The spectrum's bands as waves, as loud as the output, on the channel the trace names.
    func drawWaveForm(_ trace: AIMPControlClass.Trace, image: AIMPSkinImage?, in rect: CGRect) {
        paint(image, in: rect)
        let inner = rect.insetBy(dx: 2, dy: 2)
        let spectrum = host.feedback.spectrum
        guard inner.width > 2, !spectrum.isEmpty, host.player.playState == .playing else { return }
        let channel = trace.channel == "ssRight" ? host.feedback.levelR : trace.channel == "ssLeft" ? host.feedback.levelL
            : max(host.feedback.levelL, host.feedback.levelR)
        let bands = 12
        let amplitudes = (0..<bands).map { band -> Double in
            let from = band * spectrum.count / bands, to = max(from + 1, (band + 1) * spectrum.count / bands)
            return spectrum[from..<min(to, spectrum.count)].max() ?? 0
        }
        let total = max(0.001, amplitudes.reduce(0, +))
        let path = CGMutablePath()
        for step in 0...Int(inner.width) {
            let x = Double(step) / Double(inner.width)
            var y = 0.0
            for (band, amplitude) in amplitudes.enumerated() {
                let frequency = Double(band + 1) * 3
                y += amplitude * sin(2 * .pi * frequency * x + host.feedback.clock * Double(band + 2) * 2.3)
            }
            let point = CGPoint(x: inner.minX + CGFloat(step), y: inner.midY - CGFloat(y / total * min(1, channel * 1.4)) * inner.height / 2)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        context.saveGState()
        context.clip(to: inner)
        context.setStrokeColor(AIMPSkinText.color(trace.color ?? 0xFF80_E0FF))
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    /// `ColumnsCount` bars across the rect, `ColumnsIndent` apart, each as tall as its share of the
    /// spectrum, in the control's `Color` (a light default when it names none).
    func drawSpectrum(_ spectrum: AIMPControlClass.Spectrum, in rect: CGRect) {
        let levels = host.feedback.spectrum
        guard !levels.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let columns = spectrum.columns, indent = spectrum.indent
        let width = (rect.width - indent * CGFloat(columns - 1)) / CGFloat(columns)
        guard width > 0 else { return }
        context.setFillColor(AIMPSkinText.color(argb(spectrum.color) ?? 0xD0E0_E8F0))
        // A `PeakColumns` picture is the display fully lit (Sony TC-RX80's LED ladders): each column
        // reveals it up to its level, in whole `PeakColumnsSegmentation`-px segments.
        let lit = image(spectrum.peakColumns)?.frame(0)
        let segment = spectrum.peakSegment
        for i in 0..<columns {
            let from = i * levels.count / columns, to = max(from + 1, (i + 1) * levels.count / columns)
            let level = levels[from..<min(to, levels.count)].max() ?? 0
            var height = (rect.height * CGFloat(min(1, max(0, level)))).rounded()
            let column = CGRect(x: rect.minX + CGFloat(i) * (width + indent), y: rect.maxY - height, width: width, height: height)
            guard let lit else {
                context.fill(column)
                continue
            }
            height = (height / segment).rounded(.down) * segment
            context.saveGState()
            context.clip(to: CGRect(x: column.minX, y: rect.maxY - height, width: column.width, height: height))
            canvas.drawUpright(lit, in: rect)
            context.restoreGState()
        }
    }
}
