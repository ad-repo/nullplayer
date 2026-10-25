import CoreGraphics
import Foundation

/// What Sonique draws itself in the skin's colours: the navigation balls, small mode's drawer
/// icons, and the menu screen's boxed icons.
extension SoniqueSkinPainter {
    func balls() {
        let fill = colour(.blueBallsColor)
        for (ball, rect) in scene.ballRects {
            let r = rect.cgRect
            context.setFillColor(fill)
            context.fillEllipse(in: r)
            if scene.state.pressed == .ball(ball) {
                context.setFillColor(CGColor(gray: 0, alpha: 0.35))
                context.fillEllipse(in: r)
            }
            glyph(ball, in: r)
        }
    }

    /// The ball's mark in black, on a 9 px ball: arrows, a question mark, a bar, a cross.
    private func glyph(_ ball: SoniqueSkinControl.Ball, in r: CGRect) {
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(1.5)
        let cx = r.midX, top = r.minY + 1.5, bottom = r.maxY - 1.5
        func arrow(tipY: CGFloat, baseY: CGFloat) {
            context.move(to: CGPoint(x: cx - 2.5, y: baseY))
            context.addLine(to: CGPoint(x: cx + 2.5, y: baseY))
            context.addLine(to: CGPoint(x: cx, y: tipY))
            context.fillPath()
        }
        switch ball {
        case .back:
            context.fill(CGRect(x: cx - 1, y: r.midY - 0.75, width: 4, height: 1.5))
            context.move(to: CGPoint(x: r.minX + 1.5, y: r.midY))
            context.addLine(to: CGPoint(x: cx, y: r.midY - 2.5))
            context.addLine(to: CGPoint(x: cx, y: r.midY + 2.5))
            context.fillPath()
        case .modeDown, .modeUp:
            let down = ball == .modeDown
            context.fill(CGRect(x: cx - 0.75, y: top, width: 1.5, height: bottom - top - 1))
            down ? arrow(tipY: bottom, baseY: bottom - 3) : arrow(tipY: top, baseY: top + 3)
        case .modeDownTwice, .modeUpTwice:
            let down = ball == .modeDownTwice
            context.fill(CGRect(x: cx - 0.75, y: top, width: 1.5, height: bottom - top))
            for step in [0.0, 3.0] as [CGFloat] {
                down ? arrow(tipY: bottom - step, baseY: bottom - step - 2.5) : arrow(tipY: top + step, baseY: top + step + 2.5)
            }
        case .help:
            draw(SoniqueSkinText.lettering("?", size: 9, ink: SoniqueSkinRenderer.cgColor(0)),
                 x: Int(r.minX) + 2, baseline: Int(r.maxY) - 1, lettering: true)
        case .minimize:
            context.fill(CGRect(x: r.minX + 2, y: r.midY - 0.75, width: r.width - 4, height: 1.5))
        case .close:
            context.move(to: CGPoint(x: r.minX + 2.5, y: r.minY + 2.5))
            context.addLine(to: CGPoint(x: r.maxX - 2.5, y: r.maxY - 2.5))
            context.move(to: CGPoint(x: r.maxX - 2.5, y: r.minY + 2.5))
            context.addLine(to: CGPoint(x: r.minX + 2.5, y: r.maxY - 2.5))
            context.strokePath()
        }
        context.restoreGState()
    }

    /// Small mode's drawer icons: Sonique draws them as discs, open in `OpenFileColor`, the
    /// transport in `SystemColor_3`, each with its mark.
    func icon(_ control: SoniqueSkinControl, in rect: SoniqueSkinRegion.Rect, lit: Bool) {
        let r = rect.cgRect
        context.saveGState()
        context.setFillColor(colour(control == .eject ? .openFileColor : .systemColor3))
        context.fillEllipse(in: r)
        context.setFillColor(CGColor(gray: lit ? 1 : 0, alpha: 1))
        let cx = r.midX, cy = r.midY
        func triangle(pointing right: Bool, at x: CGFloat) {
            context.move(to: CGPoint(x: x, y: cy - 3))
            context.addLine(to: CGPoint(x: x, y: cy + 3))
            context.addLine(to: CGPoint(x: right ? x + 3.5 : x - 3.5, y: cy))
            context.fillPath()
        }
        switch control {
        case .eject:
            context.move(to: CGPoint(x: cx - 3, y: cy))
            context.addLine(to: CGPoint(x: cx + 3, y: cy))
            context.addLine(to: CGPoint(x: cx, y: cy - 3))
            context.fillPath()
            context.fill(CGRect(x: cx - 3, y: cy + 1.5, width: 6, height: 1.5))
        case .prev:
            context.fill(CGRect(x: cx - 3, y: cy - 3, width: 1.5, height: 6))
            triangle(pointing: false, at: cx + 2.5)
        case .next:
            context.fill(CGRect(x: cx + 1.5, y: cy - 3, width: 1.5, height: 6))
            triangle(pointing: true, at: cx - 2.5)
        case .play:
            if host.playState == .playing {
                context.fill(CGRect(x: cx - 2.5, y: cy - 2.5, width: 5, height: 5))
            } else {
                triangle(pointing: true, at: cx - 1.5)
            }
        case .pause:
            context.fill(CGRect(x: cx - 2.5, y: cy - 3, width: 1.75, height: 6))
            context.fill(CGRect(x: cx + 0.75, y: cy - 3, width: 1.75, height: 6))
        default:
            break
        }
        context.restoreGState()
    }

    /// A left-column icon: a box in `SystemColor_3`, as Sonique's, with NullPlayer's own plain mark.
    func menuIcon(_ item: SoniqueSkinMenu.Item, in r: CGRect) {
        context.saveGState()
        let ink = colour(.systemColor3)
        context.setStrokeColor(ink)
        context.setFillColor(ink)
        context.setLineWidth(1)
        context.stroke(r.insetBy(dx: 0.5, dy: 0.5))
        let inner = r.insetBy(dx: 4, dy: 4)
        switch item {
        case .visualMode:
            for (i, h) in [0.4, 0.9, 0.6, 1.0, 0.5].enumerated() {
                let bar = inner.height * h
                context.fill(CGRect(x: inner.minX + CGFloat(i) * 3, y: inner.maxY - bar, width: 2, height: bar))
            }
        case .playlist:
            for y in stride(from: inner.minY, to: inner.maxY, by: 3) {
                context.fill(CGRect(x: inner.minX, y: y, width: inner.width, height: 1))
            }
        case .library:
            let lens = CGRect(x: inner.minX, y: inner.minY, width: inner.width * 0.65, height: inner.height * 0.65)
            context.strokeEllipse(in: lens.insetBy(dx: 0.5, dy: 0.5))
            context.setLineWidth(2)
            context.move(to: CGPoint(x: lens.maxX - 1, y: lens.maxY - 1))
            context.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
            context.strokePath()
        case .setup:
            context.strokeEllipse(in: inner.insetBy(dx: 1.5, dy: 1.5))
            context.fillEllipse(in: inner.insetBy(dx: inner.width / 2 - 1.5, dy: inner.height / 2 - 1.5))
        case .audio:
            for (i, knob) in [0.3, 0.7, 0.45].enumerated() {
                let x = inner.minX + 1 + CGFloat(i) * 4
                context.fill(CGRect(x: x, y: inner.minY, width: 1, height: inner.height))
                context.fill(CGRect(x: x - 1, y: inner.minY + inner.height * knob - 1, width: 3, height: 2))
            }
        // The right column's links are words alone.
        case .spectrum, .peppyMeter, .art, .waveform, .skins, .history, .about:
            break
        }
        context.restoreGState()
    }
}
