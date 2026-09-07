import AppKit

/// Palette-derived chrome for app-owned fallback windows shown beside a `.wal` skin.
///
/// The caller continues to own its window geometry and hit testing. This painter only replaces the
/// classic `.wsz` artwork when `WindowManager.winampModernSurfaceStyle` is available; a surface
/// mounted in a Wasabi holder never calls it.
struct WinampModernChrome {
    struct Metrics: Equatable {
        let titleHeight: CGFloat
        let leftBorder: CGFloat
        let rightBorder: CGFloat
        let bottomBorder: CGFloat

        static var spectrumFamily: Metrics {
            Metrics(
                titleHeight: SkinElements.SpectrumWindow.Layout.titleBarHeight,
                leftBorder: SkinElements.SpectrumWindow.Layout.leftBorder,
                rightBorder: SkinElements.SpectrumWindow.Layout.rightBorder,
                bottomBorder: SkinElements.SpectrumWindow.Layout.bottomBorder
            )
        }

        static var waveform: Metrics {
            Metrics(
                titleHeight: SkinElements.WaveformWindow.Layout.titleBarHeight,
                leftBorder: SkinElements.WaveformWindow.Layout.leftBorder,
                rightBorder: SkinElements.WaveformWindow.Layout.rightBorder,
                bottomBorder: SkinElements.WaveformWindow.Layout.bottomBorder
            )
        }
    }

    let style: WinampModernSurfaceStyle

    /// Draws spectrum-family chrome in the same flipped, top-left coordinate system used by
    /// `SkinRenderer`. `fillBackground` distinguishes the old full-window and overlay entry points.
    func drawSpectrumFamilyWindow(
        in context: CGContext,
        bounds: CGRect,
        metrics: Metrics,
        isActive: Bool,
        isClosePressed: Bool,
        controlScale: CGFloat,
        title: String,
        fillBackground: Bool
    ) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        context.saveGState()
        context.setShouldAntialias(false)

        if fillBackground {
            context.setFillColor(style.background.cgColor)
            context.fill(bounds)
        }

        let titleHeight = min(max(metrics.titleHeight, 0), bounds.height)
        let bottomHeight = min(max(metrics.bottomBorder, 0), max(0, bounds.height - titleHeight))
        let sideHeight = max(0, bounds.height - titleHeight - bottomHeight)
        let leftWidth = min(max(metrics.leftBorder, 0), bounds.width)
        let rightWidth = min(max(metrics.rightBorder, 0), max(0, bounds.width - leftWidth))

        let titleColor = isActive ? style.barBackground : style.background
        let edgeColor = isActive ? style.border : style.divider
        // The title bar is a *derived* colour and the title a declared one, so nothing so far has
        // guaranteed they can be seen together — five skins in the corpus drew a title that was
        // literally invisible, and `dimText` (the inactive title) was the worse half nearly
        // everywhere. Guard against the strip this label actually lands on (B48).
        let labelColor = isActive ? style.legibleText(style.text, on: titleColor)
                                  : style.legibleDimText(on: titleColor)

        context.setFillColor(titleColor.cgColor)
        context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: titleHeight))

        context.setFillColor(style.barBackground.cgColor)
        context.fill(CGRect(x: bounds.minX, y: bounds.minY + titleHeight,
                            width: leftWidth, height: sideHeight))
        context.fill(CGRect(x: bounds.maxX - rightWidth, y: bounds.minY + titleHeight,
                            width: rightWidth, height: sideHeight))
        context.fill(CGRect(x: bounds.minX, y: bounds.maxY - bottomHeight,
                            width: bounds.width, height: bottomHeight))

        // One-pixel palette-derived seams make the frame legible on both very dark and very light
        // themes without importing any fixed classic-skin colours.
        context.setFillColor(edgeColor.cgColor)
        context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1))
        context.fill(CGRect(x: bounds.minX, y: bounds.minY + max(0, titleHeight - 1),
                            width: bounds.width, height: min(1, titleHeight)))
        context.fill(CGRect(x: bounds.minX, y: bounds.minY + titleHeight, width: min(1, leftWidth),
                            height: sideHeight))
        context.fill(CGRect(x: bounds.maxX - min(1, rightWidth), y: bounds.minY + titleHeight,
                            width: min(1, rightWidth), height: sideHeight))
        context.fill(CGRect(x: bounds.minX, y: bounds.maxY - min(1, bottomHeight),
                            width: bounds.width, height: min(1, bottomHeight)))

        let scale = max(controlScale, 0.01)
        let titleWidth = WinampModernSurfaceStyle.measuredWidth(title, scale: scale)
        let closeRegionWidth = min(25, bounds.width)
        let labelLimit = max(bounds.minX, bounds.maxX - closeRegionWidth)
        let labelX = max(bounds.minX + leftWidth,
                         min(labelLimit - titleWidth,
                             bounds.midX - titleWidth / 2))
        let labelY = bounds.minY + max(0, (titleHeight - WinampModernSurfaceStyle.classicCharHeight * scale) / 2)
        WinampModernSurfaceStyle.drawText(title, at: NSPoint(x: labelX, y: labelY),
                                          scale: scale, color: labelColor, in: context)

        drawCloseButton(in: context,
                        rect: CGRect(x: bounds.maxX - closeRegionWidth, y: bounds.minY,
                                     width: closeRegionWidth, height: titleHeight),
                        pressed: isClosePressed,
                        color: labelColor)
        context.restoreGState()
    }

    private func drawCloseButton(in context: CGContext, rect: CGRect, pressed: Bool, color: NSColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        if pressed {
            context.setFillColor(style.pressedFill.cgColor)
            context.fill(rect)
        }

        let size = min(7, max(3, floor(min(rect.width, rect.height) - 6)))
        let originX = floor(rect.midX - size / 2)
        let originY = floor(rect.midY - size / 2)
        context.setFillColor(color.cgColor)
        for offset in 0..<Int(size) {
            let d = CGFloat(offset)
            context.fill(CGRect(x: originX + d, y: originY + d, width: 1, height: 1))
            context.fill(CGRect(x: originX + size - 1 - d, y: originY + d, width: 1, height: 1))
        }
    }
}
