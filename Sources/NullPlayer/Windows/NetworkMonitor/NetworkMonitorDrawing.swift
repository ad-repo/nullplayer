import AppKit

final class NetworkMonitorRenderState {
    var displayDownBytesPerSecond: Double = 0
    var displayUpBytesPerSecond: Double = 0
    var downPulse: CGFloat = 0
    var upPulse: CGFloat = 0
    var lastPeakDownBytesPerSecond: Double = 0
    var lastPeakUpBytesPerSecond: Double = 0
    var lastUpdateAt: Date = Date()

    func advance(toward snapshot: NetworkThroughputSnapshot?, now: Date = Date()) {
        let elapsed = max(0, min(0.1, now.timeIntervalSince(lastUpdateAt)))
        lastUpdateAt = now

        let targetDown = snapshot?.downBytesPerSecond ?? 0
        let targetUp = snapshot?.upBytesPerSecond ?? 0
        let stiffness = 1 - pow(0.001, elapsed)
        displayDownBytesPerSecond += (targetDown - displayDownBytesPerSecond) * stiffness
        displayUpBytesPerSecond += (targetUp - displayUpBytesPerSecond) * stiffness

        if let snapshot {
            if snapshot.sessionPeakDownBytesPerSecond > lastPeakDownBytesPerSecond, lastPeakDownBytesPerSecond > 0 {
                downPulse = 1
            }
            if snapshot.sessionPeakUpBytesPerSecond > lastPeakUpBytesPerSecond, lastPeakUpBytesPerSecond > 0 {
                upPulse = 1
            }
            lastPeakDownBytesPerSecond = snapshot.sessionPeakDownBytesPerSecond
            lastPeakUpBytesPerSecond = snapshot.sessionPeakUpBytesPerSecond
        }

        downPulse = max(0, downPulse - CGFloat(elapsed * 2.8))
        upPulse = max(0, upPulse - CGFloat(elapsed * 2.8))
    }
}

enum NetworkMonitorDrawing {
    private enum ViewMode {
        case hero
        case compact
        case mini
        case tiny
    }

    private struct Palette {
        let background = NSColor(calibratedRed: 0.018, green: 0.024, blue: 0.035, alpha: 1)
        let textDim = NSColor(calibratedRed: 0.39, green: 0.45, blue: 0.55, alpha: 1)
        let textMuted = NSColor(calibratedRed: 0.58, green: 0.64, blue: 0.72, alpha: 1)
        let textSoft = NSColor(calibratedRed: 0.80, green: 0.84, blue: 0.90, alpha: 1)
        let textBright = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1)
        let accent = NSColor(calibratedRed: 0.65, green: 0.71, blue: 0.99, alpha: 1)
        let downloadLow = NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)
        let downloadHigh = NSColor(calibratedRed: 0.00, green: 0.96, blue: 0.83, alpha: 1)
        let uploadLow = NSColor(calibratedRed: 0.06, green: 0.73, blue: 0.51, alpha: 1)
        let uploadHigh = NSColor(calibratedRed: 0.64, green: 0.90, blue: 0.21, alpha: 1)
    }

    static func drawContent(
        in rect: NSRect,
        snapshot: NetworkThroughputSnapshot?,
        isModern: Bool,
        renderState: NetworkMonitorRenderState
    ) {
        guard rect.width > 20, rect.height > 20 else { return }

        let palette = Palette()
        renderState.advance(toward: snapshot)

        palette.background.setFill()
        rect.fill()

        let mode = mode(for: rect)
        if mode == .tiny {
            drawTiny(in: rect, snapshot: snapshot, renderState: renderState, palette: palette)
            return
        }

        let content = rect.insetBy(dx: 8, dy: 7)
        var cursorY = content.maxY

        if mode == .hero {
            drawHeroTitle(in: NSRect(x: content.minX, y: cursorY - 25, width: content.width, height: 22), palette: palette)
            cursorY -= 31
        } else if mode == .compact {
            drawTitleRow(in: NSRect(x: content.minX, y: cursorY - 14, width: content.width, height: 14), palette: palette)
            cursorY -= 19
        }

        let footerHeight: CGFloat = mode == .mini ? 0 : min(24, max(0, content.height * 0.18))
        let availablePanelHeight = max(30, cursorY - content.minY - footerHeight - 5)
        let gap: CGFloat = 5
        let panelHeight = floor((availablePanelHeight - gap) / 2)
        let uploadRect = NSRect(x: content.minX, y: content.minY + footerHeight, width: content.width, height: panelHeight)
        let downloadRect = NSRect(x: content.minX, y: uploadRect.maxY + gap, width: content.width, height: panelHeight)

        drawPanel(
            title: "download",
            arrow: "↓",
            value: renderState.displayDownBytesPerSecond,
            peak: snapshot?.sessionPeakDownBytesPerSecond ?? 0,
            pulse: renderState.downPulse,
            samples: snapshot?.downloadHistory ?? [],
            rollingMax: snapshot?.rollingMaxDownBytesPerSecond ?? 1,
            rect: downloadRect,
            isDownload: true,
            compact: mode == .mini,
            palette: palette
        )
        drawPanel(
            title: "upload",
            arrow: "↑",
            value: renderState.displayUpBytesPerSecond,
            peak: snapshot?.sessionPeakUpBytesPerSecond ?? 0,
            pulse: renderState.upPulse,
            samples: snapshot?.uploadHistory ?? [],
            rollingMax: snapshot?.rollingMaxUpBytesPerSecond ?? 1,
            rect: uploadRect,
            isDownload: false,
            compact: mode == .mini,
            palette: palette
        )

        if footerHeight > 0 {
            drawFooter(
                in: NSRect(x: content.minX, y: content.minY, width: content.width, height: footerHeight),
                snapshot: snapshot,
                down: renderState.displayDownBytesPerSecond,
                up: renderState.displayUpBytesPerSecond,
                palette: palette
            )
        }
    }

    private static func mode(for rect: NSRect) -> ViewMode {
        if rect.height < 48 || rect.width < 150 { return .tiny }
        if rect.height < 88 { return .mini }
        if rect.height < 150 { return .compact }
        return .hero
    }

    private static func drawTiny(
        in rect: NSRect,
        snapshot: NetworkThroughputSnapshot?,
        renderState: NetworkMonitorRenderState,
        palette: Palette
    ) {
        let down = NetworkThroughputFormatting.bytesPerSecond(renderState.displayDownBytesPerSecond)
        let up = NetworkThroughputFormatting.bytesPerSecond(renderState.displayUpBytesPerSecond)
        let line = "↓ \(down)   ↑ \(up)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: palette.textBright
        ]
        drawText(line, centeredIn: rect, attributes: attrs)

        let iface = snapshot?.interface?.name ?? "auto"
        let smallAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular),
            .foregroundColor: palette.textMuted
        ]
        drawText(iface, centeredIn: NSRect(x: rect.minX, y: rect.minY + 4, width: rect.width, height: 9), attributes: smallAttrs)
    }

    private static func drawHeroTitle(in rect: NSRect, palette: Palette) {
        let dotRect = NSRect(x: rect.minX, y: rect.midY - 3, width: 6, height: 6)
        palette.accent.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        drawText(
            "flow",
            at: NSPoint(x: rect.minX + 12, y: rect.minY + 2),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold), .foregroundColor: palette.textBright]
        )
        drawText(
            "bandwidth monitor",
            at: NSPoint(x: rect.minX + 58, y: rect.minY + 5),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: palette.textMuted]
        )
    }

    private static func drawTitleRow(in rect: NSRect, palette: Palette) {
        let breathe = 0.5 + 0.5 * sin(Date().timeIntervalSince1970 * 2)
        colorBetween(palette.accent, .white, CGFloat(breathe * 0.35)).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX, y: rect.midY - 2.5, width: 5, height: 5)).fill()
        drawText(
            "flow",
            at: NSPoint(x: rect.minX + 10, y: rect.minY + 1),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: palette.textBright]
        )
        drawText(
            "bandwidth monitor",
            at: NSPoint(x: rect.minX + 45, y: rect.minY + 2),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular), .foregroundColor: palette.textMuted]
        )
    }

    private static func drawPanel(
        title: String,
        arrow: String,
        value: Double,
        peak: Double,
        pulse: CGFloat,
        samples: [Double],
        rollingMax: Double,
        rect: NSRect,
        isDownload: Bool,
        compact: Bool,
        palette: Palette
    ) {
        guard rect.width > 30, rect.height > 18 else { return }

        let ratio = speedRatio(value, rollingMax)
        let base = isDownload ? palette.downloadLow : palette.uploadLow
        let hot = isDownload ? palette.downloadHigh : palette.uploadHigh
        let strokeColor = colorBetween(base, hot, ratio)
        let fillColor = NSColor(calibratedRed: 0.035, green: 0.043, blue: 0.060, alpha: 0.95)

        fillColor.setFill()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        path.fill()
        strokeColor.withAlphaComponent(0.72 + pulse * 0.28).setStroke()
        path.lineWidth = 1.2 + pulse * 1.2
        path.stroke()

        let inner = rect.insetBy(dx: 8, dy: 5)
        drawText(
            title,
            at: NSPoint(x: inner.minX, y: inner.maxY - 9),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: compact ? 7.5 : 8.5, weight: .bold), .foregroundColor: palette.textMuted]
        )

        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: compact ? 10 : 13, weight: .bold),
            .foregroundColor: colorBetween(base, .white, ratio * 0.38)
        ]
        drawText(
            "\(arrow) \(NetworkThroughputFormatting.bytesPerSecond(value)) \(velocityGlyph(samples))",
            at: NSPoint(x: inner.minX, y: inner.maxY - (compact ? 21 : 24)),
            attributes: valueAttrs
        )

        let peakAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: compact ? 7.5 : 8.5, weight: .medium),
            .foregroundColor: colorBetween(palette.textMuted, .white, pulse)
        ]
        let peakText = "peak: \(NetworkThroughputFormatting.bytesPerSecond(peak))"
        drawText(
            peakText,
            at: NSPoint(x: max(inner.minX, inner.maxX - textSize(peakText, attributes: peakAttrs).width), y: inner.maxY - 9),
            attributes: peakAttrs
        )

        let graphRect = NSRect(
            x: inner.minX,
            y: inner.minY + 1,
            width: inner.width,
            height: max(6, inner.height - (compact ? 24 : 29))
        )
        drawWaveform(samples: samples, maxValue: max(rollingMax, value, 1), in: graphRect, color: strokeColor)
    }

    private static func drawWaveform(samples: [Double], maxValue: Double, in rect: NSRect, color: NSColor) {
        guard rect.width > 4, rect.height > 4 else { return }

        NSColor.white.withAlphaComponent(0.07).setStroke()
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: rect.minX, y: rect.minY + 0.5))
        baseline.line(to: NSPoint(x: rect.maxX, y: rect.minY + 0.5))
        baseline.lineWidth = 1
        baseline.stroke()

        guard !samples.isEmpty else { return }
        let columns = max(2, Int(rect.width / 2))
        let visible = resampled(samples, count: columns)
        let path = NSBezierPath()
        let fillPath = NSBezierPath()
        let step = rect.width / CGFloat(max(visible.count - 1, 1))

        for (index, sample) in visible.enumerated() {
            let ratio = easeOutQuad(CGFloat(min(1, max(0, sample / maxValue))))
            let point = NSPoint(x: rect.minX + CGFloat(index) * step, y: rect.minY + ratio * rect.height)
            if index == 0 {
                path.move(to: point)
                fillPath.move(to: NSPoint(x: point.x, y: rect.minY))
                fillPath.line(to: point)
            } else {
                path.line(to: point)
                fillPath.line(to: point)
            }
        }
        fillPath.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        fillPath.close()

        color.withAlphaComponent(0.16).setFill()
        fillPath.fill()
        color.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 1.4
        path.stroke()
    }

    private static func drawFooter(
        in rect: NSRect,
        snapshot: NetworkThroughputSnapshot?,
        down: Double,
        up: Double,
        palette: Palette
    ) {
        guard rect.height > 12 else { return }
        let iface = snapshot?.interface?.name ?? "auto"
        let status = "● \(iface)"
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium),
            .foregroundColor: palette.accent
        ]
        drawText(status, centeredIn: NSRect(x: rect.minX, y: rect.maxY - 11, width: rect.width, height: 10), attributes: statusAttrs)

        if rect.height >= 22 {
            let todayDown = NetworkThroughputFormatting.bytes(snapshot?.dailyDownBytes ?? 0)
            let todayUp = NetworkThroughputFormatting.bytes(snapshot?.dailyUpBytes ?? 0)
            let line = "today  ↓ \(todayDown)  ↑ \(todayUp)"
            drawText(
                line,
                centeredIn: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 10),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .regular), .foregroundColor: palette.textMuted]
            )
        } else {
            let line = "↓ \(NetworkThroughputFormatting.bytesPerSecond(down))   ↑ \(NetworkThroughputFormatting.bytesPerSecond(up))"
            drawText(
                line,
                centeredIn: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 10),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .regular), .foregroundColor: palette.textMuted]
            )
        }
    }

    private static func speedRatio(_ value: Double, _ maxValue: Double) -> CGFloat {
        guard maxValue > 0 else { return 0 }
        return CGFloat(min(1, max(0, value / maxValue)))
    }

    private static func easeOutQuad(_ value: CGFloat) -> CGFloat {
        value * (2 - value)
    }

    private static func resampled(_ samples: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
        if samples.count == 1 { return Array(repeating: samples[0], count: count) }

        let start = max(0, samples.count - count * 2)
        let source = Array(samples[start...])
        guard source.count > 1 else { return Array(repeating: source.first ?? 0, count: count) }

        return (0..<count).map { index in
            let position = Double(index) * Double(source.count - 1) / Double(max(count - 1, 1))
            let lower = Int(floor(position))
            let upper = min(source.count - 1, lower + 1)
            let fraction = position - Double(lower)
            return source[lower] * (1 - fraction) + source[upper] * fraction
        }
    }

    private static func velocityGlyph(_ samples: [Double]) -> String {
        guard samples.count >= 2, let current = samples.last, current >= 1 else { return "→" }
        let window = Array(samples.suffix(6))
        guard window.count >= 2 else { return "→" }
        let first = window.first ?? 0
        let last = window.last ?? 0
        let threshold = max(current * 0.05, 1)
        if last - first > threshold { return "↗" }
        if first - last > threshold { return "↘" }
        return "→"
    }

    private static func colorBetween(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let left = a.usingColorSpace(.deviceRGB) ?? a
        let right = b.usingColorSpace(.deviceRGB) ?? b
        let amount = min(1, max(0, t))
        return NSColor(
            calibratedRed: left.redComponent + (right.redComponent - left.redComponent) * amount,
            green: left.greenComponent + (right.greenComponent - left.greenComponent) * amount,
            blue: left.blueComponent + (right.blueComponent - left.blueComponent) * amount,
            alpha: left.alphaComponent + (right.alphaComponent - left.alphaComponent) * amount
        )
    }

    private static func drawText(_ text: String, at point: NSPoint, attributes: [NSAttributedString.Key: Any]) {
        (text as NSString).draw(at: point, withAttributes: attributes)
    }

    private static func drawText(_ text: String, centeredIn rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        let size = textSize(text, attributes: attributes)
        drawText(
            text,
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            attributes: attributes
        )
    }

    private static func textSize(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSSize {
        (text as NSString).size(withAttributes: attributes)
    }
}
