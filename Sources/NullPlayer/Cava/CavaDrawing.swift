import AppKit

/// Mode-neutral Cava spectrum analyzer CoreGraphics rendering.
/// Draws gradient bars (mono as single row, stereo as mirrored L vs R).
enum CavaDrawing {
    /// Draw cava bars in a given rect.
    ///
    /// - Parameters:
    ///   - rect: Bounds to fill with bars
    ///   - barArrays: Per-channel bar values (0…1)
    ///   - lowColor: Color for low frequencies
    ///   - highColor: Color for high frequencies
    ///   - mode: Mono or stereo mode (affects layout)
    static func draw(
        in rect: CGRect,
        barArrays: [[Float]],
        lowColor: NSColor,
        highColor: NSColor,
        mode: CavaSettings.Mode
    ) {
        guard !rect.isEmpty, !barArrays.isEmpty else { return }

        switch mode {
        case .mono:
            drawMonoMode(in: rect, bars: barArrays[0], lowColor: lowColor, highColor: highColor)
        case .stereo:
            drawStereoMode(in: rect, barArrays: barArrays, lowColor: lowColor, highColor: highColor)
        }
    }

    private static func drawMonoMode(
        in rect: CGRect,
        bars: [Float],
        lowColor: NSColor,
        highColor: NSColor
    ) {
        guard !bars.isEmpty else { return }

        let barCount = bars.count
        let barWidth = rect.width / CGFloat(barCount)
        let barHeight = rect.height

        for (i, value) in bars.enumerated() {
            let height = barHeight * CGFloat(value)
            // Views are non-flipped (origin bottom-left), so bars grow up from the bottom edge.
            let barRect = CGRect(
                x: rect.minX + CGFloat(i) * barWidth,
                y: rect.minY,
                width: barWidth,
                height: height
            )

            drawGradientBar(in: barRect, intensity: CGFloat(value), lowColor: lowColor, highColor: highColor)
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

    /// Draw a single gradient bar from low to high frequency color.
    private static func drawGradientBar(
        in rect: CGRect,
        intensity: CGFloat,
        lowColor: NSColor,
        highColor: NSColor
    ) {
        guard rect.height > 0, rect.width > 0 else { return }

        // Interpolate color by bar position (low at bottom, high at top).
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
