import AppKit

enum WaveformDrawing {
    static func draw(
        snapshot: WaveformSnapshot,
        columnAmplitudes: [UInt16],
        cuePoints: [WaveformCuePoint],
        showCuePoints: Bool,
        currentTime: TimeInterval,
        dragTime: TimeInterval?,
        in rect: NSRect,
        colors: WaveformRenderColors,
        context: CGContext
    ) {
        context.saveGState()
        context.setFillColor(colors.background.cgColor)
        context.fill(rect)

        switch snapshot.state {
        case .ready:
            drawWaveform(
                snapshot: snapshot,
                columnAmplitudes: columnAmplitudes,
                cuePoints: cuePoints,
                showCuePoints: showCuePoints,
                currentTime: currentTime,
                dragTime: dragTime,
                in: rect,
                colors: colors,
                context: context
            )
        case .loading, .unsupported, .failed:
            drawMessage(snapshot.message ?? "", in: rect, color: colors.text)
        }

        context.restoreGState()
    }

    private static func drawWaveform(
        snapshot: WaveformSnapshot,
        columnAmplitudes: [UInt16],
        cuePoints: [WaveformCuePoint],
        showCuePoints: Bool,
        currentTime: TimeInterval,
        dragTime: TimeInterval?,
        in rect: NSRect,
        colors: WaveformRenderColors,
        context: CGContext
    ) {
        guard !snapshot.samples.isEmpty else {
            drawMessage("Waveform unavailable", in: rect, color: colors.text)
            return
        }

        let effectiveTime = dragTime ?? currentTime
        let showsPlaybackProgress = snapshot.allowsSeeking && snapshot.duration > 0
        let playedFraction = showsPlaybackProgress ? min(max(effectiveTime / snapshot.duration, 0), 1) : 0
        let midY = rect.midY
        let drawableHeight = max(2, rect.height - 4)
        let pixelWidth = max(1, Int(rect.width))
        let amplitudes = columnAmplitudes.isEmpty ? makeColumnAmplitudes(samples: snapshot.samples, pixelWidth: pixelWidth) : columnAmplitudes

        for xPixel in 0..<pixelWidth {
            let amplitude = amplitudes[min(xPixel, amplitudes.count - 1)]
            let scaledHeight = max(1, Int((CGFloat(amplitude) / 32767.0) * drawableHeight))
            let lineX = rect.minX + CGFloat(xPixel)
            let y = midY - CGFloat(scaledHeight) / 2
            let isPlayed = showsPlaybackProgress && CGFloat(xPixel) < rect.width * CGFloat(playedFraction)
            context.setStrokeColor((isPlayed ? colors.playedWaveform : colors.waveform).cgColor)
            context.strokeLineSegments(between: [
                NSPoint(x: lineX, y: y),
                NSPoint(x: lineX, y: y + CGFloat(scaledHeight))
            ])
        }

        if showCuePoints, snapshot.duration > 0 {
            context.setStrokeColor(colors.cuePoint.cgColor)
            for cuePoint in cuePoints {
                let fraction = min(max(CGFloat(Double(cuePoint.milliseconds) / (snapshot.duration * 1000.0)), 0), 1)
                let x = rect.minX + (rect.width * fraction)
                context.strokeLineSegments(between: [
                    NSPoint(x: x, y: rect.minY + 1),
                    NSPoint(x: x, y: rect.maxY - 1)
                ])
            }
        }

        if showsPlaybackProgress {
            let playheadX = rect.minX + rect.width * CGFloat(playedFraction)
            context.setStrokeColor(colors.playhead.cgColor)
            context.strokeLineSegments(between: [
                NSPoint(x: playheadX, y: rect.minY),
                NSPoint(x: playheadX, y: rect.maxY)
            ])
        }
    }

    static func makeColumnAmplitudes(samples: [UInt16], pixelWidth: Int) -> [UInt16] {
        guard !samples.isEmpty, pixelWidth > 0 else { return [] }
        let sampleCount = samples.count
        var columns = Array(repeating: UInt16(0), count: pixelWidth)

        for xPixel in 0..<pixelWidth {
            let startIndex = (xPixel * sampleCount) / pixelWidth
            let endIndex = min(sampleCount, ((xPixel + 1) * sampleCount) / pixelWidth)
            let rangeEnd = max(startIndex + 1, endIndex)
            var amplitude: UInt16 = 0
            for index in startIndex..<rangeEnd {
                amplitude = max(amplitude, samples[index])
            }
            columns[xPixel] = amplitude
        }

        return columns
    }

    private static func drawMessage(_ message: String, in rect: NSRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let inset = rect.insetBy(dx: 8, dy: 8)
        message.draw(with: inset, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    static func tooltipText(
        at fraction: CGFloat,
        snapshot: WaveformSnapshot,
        cuePoints: [WaveformCuePoint]
    ) -> String? {
        if snapshot.isStreaming && !snapshot.allowsSeeking {
            return "Live stream waveform"
        }
        guard snapshot.duration > 0 else { return nil }
        let clampedFraction = min(max(fraction, 0), 1)
        let milliseconds = Int((snapshot.duration * 1000.0) * Double(clampedFraction))
        let seconds = milliseconds / 1000
        let totalSeconds = Int(snapshot.duration)
        let cuePoint = cuePoints.last(where: { $0.milliseconds <= milliseconds })

        if let cuePoint {
            if let performer = cuePoint.performer, !performer.isEmpty {
                return "\(performer) - \(cuePoint.title) [\(format(seconds))/\(format(totalSeconds))]"
            }
            return "\(cuePoint.title) [\(format(seconds))/\(format(totalSeconds))]"
        }

        return "\(format(seconds))/\(format(totalSeconds))"
    }

    private static func format(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
