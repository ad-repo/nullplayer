import AppKit

enum NetworkMonitorDrawing {
    static func drawContent(
        in rect: NSRect,
        snapshot: NetworkThroughputSnapshot?,
        isModern: Bool
    ) {
        guard rect.width > 20, rect.height > 20 else { return }

        NSColor.black.setFill()
        rect.fill()

        let primary = isModern
            ? NSColor(calibratedRed: 0.72, green: 0.95, blue: 0.78, alpha: 1.0)
            : NSColor(calibratedRed: 0.50, green: 1.0, blue: 0.34, alpha: 1.0)
        let secondary = isModern
            ? NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.48, alpha: 1.0)
            : NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.34, alpha: 1.0)
        let muted = NSColor.white.withAlphaComponent(isModern ? 0.52 : 0.46)
        let grid = NSColor.white.withAlphaComponent(isModern ? 0.12 : 0.10)

        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: max(12, min(17, rect.height * 0.15)), weight: .semibold)
        let smallFont = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
        let tinyFont = NSFont.monospacedSystemFont(ofSize: 7.5, weight: .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: muted]
        let tinyAttrs: [NSAttributedString.Key: Any] = [.font: tinyFont, .foregroundColor: muted]
        let downAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: primary]
        let upAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: secondary]

        let rawIn = snapshot?.downBytesPerSecond ?? 0
        let rawOut = snapshot?.upBytesPerSecond ?? 0
        let graphHistory = snapshot?.history ?? []

        let inset: CGFloat = 7
        let left = rect.minX + inset
        let right = rect.maxX - inset
        var y = rect.maxY - 12

        let interfaceName = snapshot?.interface?.displayName ?? "NO INTERFACE"
        drawText("IF \(interfaceName)", at: NSPoint(x: left, y: y), attrs: tinyAttrs)
        drawText("LIVE", at: NSPoint(x: right - 24, y: y), attrs: tinyAttrs)

        let ruleY = y - 4
        grid.setStroke()
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: left, y: ruleY))
        rule.line(to: NSPoint(x: right, y: ruleY))
        rule.lineWidth = 1
        rule.stroke()

        y -= 24
        let columnGap: CGFloat = 10
        let columnWidth = (rect.width - inset * 2 - columnGap) / 2
        drawText("NET IN", at: NSPoint(x: left, y: y + 15), attrs: labelAttrs)
        drawText(NetworkThroughputFormatting.bytesPerSecond(rawIn),
                 at: NSPoint(x: left, y: y), attrs: downAttrs)
        drawText("NET OUT", at: NSPoint(x: left + columnWidth + columnGap, y: y + 15), attrs: labelAttrs)
        drawText(NetworkThroughputFormatting.bytesPerSecond(rawOut),
                 at: NSPoint(x: left + columnWidth + columnGap, y: y), attrs: upAttrs)

        y -= 15
        let peakDown = NetworkThroughputFormatting.bytesPerSecond(snapshot?.sessionPeakDownBytesPerSecond ?? 0)
        let peakUp = NetworkThroughputFormatting.bytesPerSecond(snapshot?.sessionPeakUpBytesPerSecond ?? 0)
        drawText("PEAK \(peakDown) IN / \(peakUp) OUT", at: NSPoint(x: left, y: y), attrs: tinyAttrs)

        y -= 11
        let dailyDown = NetworkThroughputFormatting.bytes(snapshot?.dailyDownBytes ?? 0)
        let dailyUp = NetworkThroughputFormatting.bytes(snapshot?.dailyUpBytes ?? 0)
        drawText("TODAY \(dailyDown) IN / \(dailyUp) OUT", at: NSPoint(x: left, y: y), attrs: tinyAttrs)

        let graphRect = NSRect(
            x: left,
            y: rect.minY + inset,
            width: right - left,
            height: max(22, y - rect.minY - inset - 5)
        )
        drawFlowGraph(
            in: graphRect,
            currentDown: rawIn,
            currentUp: rawOut,
            history: graphHistory,
            downColor: primary,
            upColor: secondary,
            gridColor: grid,
            labelAttributes: tinyAttrs,
            topLabel: "IN",
            bottomLabel: "OUT"
        )
    }

    private static func drawFlowGraph(
        in rect: NSRect,
        currentDown: Double,
        currentUp: Double,
        history: [NetworkThroughputPoint],
        downColor: NSColor,
        upColor: NSColor,
        gridColor: NSColor,
        labelAttributes: [NSAttributedString.Key: Any],
        topLabel: String,
        bottomLabel: String
    ) {
        guard rect.width > 38, rect.height > 18 else { return }

        gridColor.setStroke()
        let baselineY = rect.midY.rounded(.down) + 0.5
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: rect.minX, y: baselineY))
        baseline.line(to: NSPoint(x: rect.maxX, y: baselineY))
        baseline.lineWidth = 1
        baseline.stroke()

        drawText(topLabel, at: NSPoint(x: rect.minX, y: rect.maxY - 8), attrs: labelAttributes)
        drawText(bottomLabel, at: NSPoint(x: rect.minX, y: rect.minY + 1), attrs: labelAttributes)

        guard !history.isEmpty else { return }
        let maxDown = max(1, history.map(\.downBytesPerSecond).max() ?? 1, currentDown)
        let maxUp = max(1, history.map(\.upBytesPerSecond).max() ?? 1, currentUp)
        let meterWidth: CGFloat = 4
        let labelInset: CGFloat = max(14, CGFloat(max(topLabel.count, bottomLabel.count)) * 5.5)
        let columnWidth: CGFloat = 2
        let gap: CGFloat = 1
        let stride = columnWidth + gap
        let historyRect = rect.insetBy(dx: labelInset, dy: 0)
        let capacity = max(1, Int((historyRect.width - meterWidth - 3) / stride))
        let visibleHistory = Array(history.suffix(capacity))
        let topHeight = max(1, rect.maxY - baselineY - 1)
        let bottomHeight = max(1, baselineY - rect.minY - 1)
        let startX = historyRect.maxX - meterWidth - 3 - CGFloat(visibleHistory.count) * stride

        for (index, sample) in visibleHistory.enumerated() {
            let x = floor(startX + CGFloat(index) * stride)
            let downHeight = scaledBarHeight(sample.downBytesPerSecond, maximum: maxDown, availableHeight: topHeight)
            let upHeight = scaledBarHeight(sample.upBytesPerSecond, maximum: maxUp, availableHeight: bottomHeight)

            downColor.withAlphaComponent(0.82).setFill()
            NSRect(x: x, y: baselineY + 1, width: columnWidth, height: downHeight).fill()

            upColor.withAlphaComponent(0.72).setFill()
            NSRect(x: x, y: baselineY - upHeight - 1, width: columnWidth, height: upHeight).fill()
        }

        let meterX = historyRect.maxX - meterWidth
        let currentDownHeight = scaledBarHeight(currentDown, maximum: maxDown, availableHeight: topHeight)
        let currentUpHeight = scaledBarHeight(currentUp, maximum: maxUp, availableHeight: bottomHeight)

        downColor.setFill()
        NSRect(x: meterX, y: baselineY + 1, width: meterWidth, height: currentDownHeight).fill()
        upColor.setFill()
        NSRect(x: meterX, y: baselineY - currentUpHeight - 1, width: meterWidth, height: currentUpHeight).fill()

        gridColor.setStroke()
        let meterRule = NSBezierPath()
        meterRule.move(to: NSPoint(x: meterX - 2.5, y: rect.minY))
        meterRule.line(to: NSPoint(x: meterX - 2.5, y: rect.maxY))
        meterRule.lineWidth = 1
        meterRule.stroke()
    }

    private static func scaledBarHeight(_ value: Double, maximum: Double, availableHeight: CGFloat) -> CGFloat {
        guard value > 0, maximum > 0 else { return 0 }
        let ratio = min(1, max(0, value / maximum))
        return max(1, availableHeight * CGFloat(ratio))
    }

    private static func drawText(_ text: String, at point: NSPoint, attrs: [NSAttributedString.Key: Any]) {
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}
