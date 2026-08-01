import AppKit

/// Mode-neutral Cava spectrum analyzer CoreGraphics rendering.
/// Draws gradient bars (mono as single row, stereo as mirrored L vs R).
enum CavaDrawing {
    enum MonoLayout {
        case frequencySweep
        case mirrored
    }

    /// Draw cava bars in a given rect.
    ///
    /// - Parameters:
    ///   - rect: Bounds to fill with bars
    ///   - barArrays: Per-channel bar values (0…1)
    ///   - lowColor: Color for short/quiet bars
    ///   - highColor: Color for tall/loud bars
    ///   - mode: Mono or stereo mode (affects layout)
    static func draw(
        in rect: CGRect,
        barArrays: [[Float]],
        lowColor: NSColor,
        highColor: NSColor,
        mode: CavaSettings.Mode,
        monoLayout: MonoLayout = .frequencySweep
    ) {
        guard !rect.isEmpty, !barArrays.isEmpty else { return }

        switch mode {
        case .mono:
            drawMonoMode(
                in: rect,
                bars: barArrays[0],
                lowColor: lowColor,
                highColor: highColor,
                layout: monoLayout
            )
        case .stereo:
            drawStereoMode(in: rect, barArrays: barArrays, lowColor: lowColor, highColor: highColor)
        }
    }

    private static func drawMonoMode(
        in rect: CGRect,
        bars: [Float],
        lowColor: NSColor,
        highColor: NSColor,
        layout: MonoLayout
    ) {
        guard !bars.isEmpty else { return }

        for (barRect, value) in monoBarRects(in: rect, bars: bars, layout: layout) {
            drawGradientBar(in: barRect, intensity: CGFloat(value), lowColor: lowColor, highColor: highColor)
        }
    }

    /// Backdrop mono uses a center-out mirrored spectrum so one channel cannot occupy only one
    /// side of a wide surface. Standalone and inline Cava retain the left-to-right sweep.
    static func monoBarRects(
        in rect: CGRect,
        bars: [Float],
        layout: MonoLayout
    ) -> [(rect: CGRect, value: Float)] {
        guard !rect.isEmpty, !bars.isEmpty else { return [] }
        let barHeight = rect.height

        switch layout {
        case .frequencySweep:
            let barWidth = rect.width / CGFloat(bars.count)
            return bars.enumerated().map { index, value in
                (
                    CGRect(
                        x: rect.minX + CGFloat(index) * barWidth,
                        y: rect.minY,
                        width: barWidth,
                        height: barHeight * CGFloat(value)
                    ),
                    value
                )
            }
        case .mirrored:
            let barWidth = (rect.width / 2) / CGFloat(bars.count)
            return bars.enumerated().flatMap { index, value in
                let height = barHeight * CGFloat(value)
                let offset = CGFloat(index) * barWidth
                return [
                    (
                        CGRect(
                            x: rect.midX - offset - barWidth,
                            y: rect.minY,
                            width: barWidth,
                            height: height
                        ),
                        value
                    ),
                    (
                        CGRect(
                            x: rect.midX + offset,
                            y: rect.minY,
                            width: barWidth,
                            height: height
                        ),
                        value
                    ),
                ]
            }
        }
    }

    private static func drawStereoMode(
        in rect: CGRect,
        barArrays: [[Float]],
        lowColor: NSColor,
        highColor: NSColor
    ) {
        guard barArrays.count >= 2 else { return }
        guard !barArrays[0].isEmpty else { return }

        let midY = rect.midY
        let halfHeight = rect.height / 2.0
        let barCount = barArrays[0].count
        let barWidth = rect.width / CGFloat(barCount)

        // Left channel (top half, growing upward)
        for (i, value) in barArrays[0].enumerated() {
            let height = halfHeight * CGFloat(value)
            let barRect = CGRect(
                x: rect.minX + CGFloat(i) * barWidth,
                y: midY,
                width: barWidth,
                height: height
            )
            drawGradientBar(in: barRect, intensity: CGFloat(value), lowColor: lowColor, highColor: highColor)
        }

        // Right channel (bottom half, growing downward)
        let rightChannel = barArrays.count > 1 ? barArrays[1] : barArrays[0]
        for (i, value) in rightChannel.enumerated() {
            let height = halfHeight * CGFloat(value)
            let barRect = CGRect(
                x: rect.minX + CGFloat(i) * barWidth,
                y: midY - height,
                width: barWidth,
                height: height
            )
            drawGradientBar(in: barRect, intensity: CGFloat(value), lowColor: lowColor, highColor: highColor)
        }
    }

    /// Draw a single bar colored by its intensity between the low and high colors.
    private static func drawGradientBar(
        in rect: CGRect,
        intensity: CGFloat,
        lowColor: NSColor,
        highColor: NSColor
    ) {
        guard rect.height > 0, rect.width > 0 else { return }

        // Interpolate color by bar intensity (quiet/short → loud/tall).
        let color = interpolateColor(lowColor, to: highColor, intensity: intensity)

        // One path per bar: fill, then a subtle 0.5pt border for definition. (Setting lineWidth on a
        // separate throwaway path left the border at the default 1.0 and allocated 3 paths per bar.)
        let path = NSBezierPath(rect: rect)
        color.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.2).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    /// Linearly interpolate between two colors by intensity.
    private static func interpolateColor(_ low: NSColor, to high: NSColor, intensity: CGFloat) -> NSColor {
        let t = intensity
        let lowRGB = low.usingColorSpace(.sRGB) ?? low
        let highRGB = high.usingColorSpace(.sRGB) ?? high

        let r = lowRGB.redComponent + (highRGB.redComponent - lowRGB.redComponent) * t
        let g = lowRGB.greenComponent + (highRGB.greenComponent - lowRGB.greenComponent) * t
        let b = lowRGB.blueComponent + (highRGB.blueComponent - lowRGB.blueComponent) * t
        let a = lowRGB.alphaComponent + (highRGB.alphaComponent - lowRGB.alphaComponent) * t

        return NSColor(red: r, green: g, blue: b, alpha: a)
    }
}
