import AppKit

enum NetworkMonitorDirection: String {
    private static let defaultsKey = "NetworkMonitorDisplayDirection"

    case download
    case upload

    static func load() -> NetworkMonitorDirection {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let direction = NetworkMonitorDirection(rawValue: rawValue) else {
            return .download
        }
        return direction
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    var toggled: NetworkMonitorDirection {
        switch self {
        case .download: return .upload
        case .upload: return .download
        }
    }

    var toggleMenuTitle: String {
        switch self {
        case .download: return "Show Upload View"
        case .upload: return "Show Download View"
        }
    }
}

final class NetworkMonitorRenderState {
    var displayDownBytesPerSecond: Double = 0
    var displayUpBytesPerSecond: Double = 0
    var lastUpdateAt: Date = Date()
    private var lastTargetDown: Double = 0
    private var lastTargetUp: Double = 0

    /// Whether the render state still needs per-frame redraws (values still converging
    /// toward their target). When this is false the network is idle/steady and the
    /// driving view can skip its 30fps invalidation until the next data snapshot arrives.
    var hasActiveAnimation: Bool {
        let threshold = max(1, max(lastTargetDown, lastTargetUp) * 0.01)
        return abs(displayDownBytesPerSecond - lastTargetDown) > threshold
            || abs(displayUpBytesPerSecond - lastTargetUp) > threshold
    }

    func advance(toward snapshot: NetworkThroughputSnapshot?, now: Date = Date()) {
        let elapsed = max(0, min(0.1, now.timeIntervalSince(lastUpdateAt)))
        lastUpdateAt = now

        let targetDown = snapshot?.downBytesPerSecond ?? 0
        let targetUp = snapshot?.upBytesPerSecond ?? 0
        lastTargetDown = targetDown
        lastTargetUp = targetUp
        let stiffness = 1 - pow(0.001, elapsed)
        displayDownBytesPerSecond += (targetDown - displayDownBytesPerSecond) * stiffness
        displayUpBytesPerSecond += (targetUp - displayUpBytesPerSecond) * stiffness
    }

    func graphPhase(for snapshot: NetworkThroughputSnapshot?, now: Date = Date()) -> CGFloat {
        guard let snapshot, snapshot.sampleInterval > 0 else { return 0 }
        return CGFloat(min(1, max(0, now.timeIntervalSince(snapshot.updatedAt) / snapshot.sampleInterval)))
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
        direction: NetworkMonitorDirection,
        isModern: Bool,
        renderState: NetworkMonitorRenderState
    ) {
        guard rect.width > 20, rect.height > 20 else { return }

        let palette = Palette()
        let now = Date()
        renderState.advance(toward: snapshot, now: now)
        let graphPhase = renderState.graphPhase(for: snapshot, now: now)

        palette.background.setFill()
        rect.fill()

        let mode = mode(for: rect)
        if mode == .tiny {
            drawTiny(in: rect, direction: direction, renderState: renderState, palette: palette)
            return
        }

        // Keep all panel/footer drawing inside the content area so nothing bleeds onto
        // the surrounding skin chrome.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).setClip()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let panelInsetX: CGFloat = isModern ? 5 : 2
        let panelInsetY: CGFloat = isModern ? 4 : 0
        let contentInsetY: CGFloat = isModern ? 4 : 1
        let content = rect.insetBy(dx: panelInsetX, dy: panelInsetY)
        let panelRect = NSRect(x: content.minX, y: content.minY, width: content.width, height: max(30, content.height))
        switch direction {
        case .download:
            drawPanel(
                title: "download",
                arrow: "↓",
                value: renderState.displayDownBytesPerSecond,
                peak: snapshot?.sessionPeakDownBytesPerSecond ?? 0,
                samples: snapshot?.downloadHistory ?? [],
                rollingMax: snapshot?.rollingMaxDownBytesPerSecond ?? 1,
                graphPhase: graphPhase,
                rect: panelRect,
                isDownload: true,
                compact: mode == .mini,
                contentInsetY: contentInsetY,
                palette: palette
            )
        case .upload:
            drawPanel(
                title: "upload",
                arrow: "↑",
                value: renderState.displayUpBytesPerSecond,
                peak: snapshot?.sessionPeakUpBytesPerSecond ?? 0,
                samples: snapshot?.uploadHistory ?? [],
                rollingMax: snapshot?.rollingMaxUpBytesPerSecond ?? 1,
                graphPhase: graphPhase,
                rect: panelRect,
                isDownload: false,
                compact: mode == .mini,
                contentInsetY: contentInsetY,
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
        direction: NetworkMonitorDirection,
        renderState: NetworkMonitorRenderState,
        palette: Palette
    ) {
        let line: String
        switch direction {
        case .download:
            line = "↓ \(NetworkThroughputFormatting.bytesPerSecond(renderState.displayDownBytesPerSecond))"
        case .upload:
            line = "↑ \(NetworkThroughputFormatting.bytesPerSecond(renderState.displayUpBytesPerSecond))"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: monoDigitFont(ofSize: 11, weight: .semibold),
            .foregroundColor: palette.textBright
        ]
        drawText(line, centeredIn: rect, attributes: attrs)

    }

    private static func drawPanel(
        title: String,
        arrow: String,
        value: Double,
        peak: Double,
        samples: [Double],
        rollingMax: Double,
        graphPhase: CGFloat,
        rect: NSRect,
        isDownload: Bool,
        compact: Bool,
        contentInsetY: CGFloat,
        palette: Palette
    ) {
        guard rect.width > 30, rect.height > 18 else { return }

        let ratio = speedRatio(value, rollingMax)
        let base = isDownload ? palette.downloadLow : palette.uploadLow
        let hot = isDownload ? palette.downloadHigh : palette.uploadHigh
        let strokeColor = colorBetween(base, hot, ratio)
        // Clip inner content to the flow content area so text and waveform stay inside
        // the outer window chrome without drawing a second inner panel border.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).setClip()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let inner = rect.insetBy(dx: 6, dy: contentInsetY)
        drawText(
            title,
            at: NSPoint(x: inner.minX, y: inner.maxY - 9),
            attributes: [.font: monoFont(ofSize: compact ? 7.5 : 8.5, weight: .bold), .foregroundColor: palette.textMuted]
        )

        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: monoDigitFont(ofSize: compact ? 10 : 13, weight: .bold),
            .foregroundColor: colorBetween(base, .white, ratio * 0.38)
        ]
        drawText(
            "\(arrow) \(NetworkThroughputFormatting.bytesPerSecond(value)) \(velocityGlyph(samples))",
            at: NSPoint(x: inner.minX, y: inner.maxY - (compact ? 21 : 24)),
            attributes: valueAttrs
        )

        let peakAttrs: [NSAttributedString.Key: Any] = [
            .font: monoDigitFont(ofSize: compact ? 7.5 : 8.5, weight: .medium),
            .foregroundColor: palette.textMuted
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
        drawWaveform(samples: samples, maxValue: max(rollingMax, value, 1), phase: graphPhase, in: graphRect, color: strokeColor)
    }

    private static func drawWaveform(samples: [Double], maxValue: Double, phase: CGFloat, in rect: NSRect, color: NSColor) {
        guard rect.width > 4, rect.height > 4 else { return }

        NSColor.white.withAlphaComponent(0.07).setStroke()
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: rect.minX, y: rect.minY + 0.5))
        baseline.line(to: NSPoint(x: rect.maxX, y: rect.minY + 0.5))
        baseline.lineWidth = 1
        baseline.stroke()

        guard !samples.isEmpty else { return }
        let sampleSpacing: CGFloat = 2
        let maxVisibleSamples = max(2, Int(ceil(rect.width / sampleSpacing)) + 2)
        let visible = Array(samples.suffix(maxVisibleSamples))
        let path = NSBezierPath()
        let fillPath = NSBezierPath()
        let clampedPhase = min(1, max(0, phase))

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).setClip()
        defer { NSGraphicsContext.restoreGraphicsState() }

        for (index, sample) in visible.enumerated() {
            let age = CGFloat(visible.count - index - 1)
            let ratio = easeOutQuad(CGFloat(min(1, max(0, sample / maxValue))))
            let point = NSPoint(x: rect.maxX - (age + clampedPhase) * sampleSpacing, y: rect.minY + ratio * rect.height)
            if index == 0 {
                path.move(to: point)
                fillPath.move(to: NSPoint(x: point.x, y: rect.minY))
                fillPath.line(to: point)
            } else {
                path.line(to: point)
                fillPath.line(to: point)
            }
        }
        if let last = visible.last {
            let ratio = easeOutQuad(CGFloat(min(1, max(0, last / maxValue))))
            let point = NSPoint(x: rect.maxX, y: rect.minY + ratio * rect.height)
            path.line(to: point)
            fillPath.line(to: point)
        }
        fillPath.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        fillPath.close()

        color.withAlphaComponent(0.16).setFill()
        fillPath.fill()
        color.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 1.4
        path.stroke()
    }

    private static func speedRatio(_ value: Double, _ maxValue: Double) -> CGFloat {
        guard maxValue > 0 else { return 0 }
        return CGFloat(min(1, max(0, value / maxValue)))
    }

    private static func easeOutQuad(_ value: CGFloat) -> CGFloat {
        value * (2 - value)
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

    // `NSFont.monospaced(Digit)SystemFont` is imported as non-optional but can return
    // nil for some size/weight combinations on some systems. A nil font pointer flowing
    // into a text-attributes dictionary crashes CoreText ("attempt to insert nil object")
    // when the string is drawn, so route every font through a guaranteed non-nil fallback.
    private static func monoFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let font: NSFont? = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        return font ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func monoDigitFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let font: NSFont? = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return font ?? NSFont.systemFont(ofSize: size, weight: weight)
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
