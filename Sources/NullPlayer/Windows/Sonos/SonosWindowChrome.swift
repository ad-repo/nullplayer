import AppKit

/// Selects the existing auxiliary-window renderer; room controls own no skin assets.
struct SonosWindowChrome {
    let window: NSWindow?
    private var modern: Bool { WindowManager.shared.isModernUIEnabled }
    /// A `.wmz` session: the skin's palette, and its borrowed frame wherever it lends one.
    private var wmp: Bool { WindowManager.shared.isRunningWMPUI }
    private var classicScale: CGFloat { WindowManager.shared.playlistChromeScale }
    private var wmpMetrics: SkinnedSurfaceChrome.Metrics {
        SkinnedSurfaceChrome.metrics(for: CGRect(origin: .zero, size: window?.frame.size ?? .zero),
                                     fallback: .spectrumFamily)
    }
    var titleHeight: CGFloat {
        if modern {
            return WindowManager.shared.effectiveHideTitleBars(for: window)
                ? ModernSkinElements.auxiliaryWindowBorderWidth
                : ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        }
        if wmp { return WindowManager.shared.hideTitleBars ? 0 : wmpMetrics.titleHeight }
        return WindowManager.shared.hideTitleBars ? 0 : SkinElements.SpectrumWindow.Layout.titleBarHeight
    }
    var textColor: NSColor {
        if modern { return ModernSkinEngine.shared.currentSkin?.textColor ?? .labelColor }
        if wmp, let style = WindowManager.shared.hostedSurfaceStyle { return style.text }
        if let style = WindowManager.shared.winampModernSurfaceStyle { return style.text }
        return WindowManager.shared.currentSkin?.playlistColors.normalText ?? .green
    }
    var backgroundColor: NSColor {
        if modern { return ModernSkinEngine.shared.currentSkin?.backgroundColor ?? .black }
        if wmp, let style = WindowManager.shared.hostedSurfaceStyle { return style.background }
        if let style = WindowManager.shared.winampModernSurfaceStyle { return style.background }
        return WindowManager.shared.currentSkin?.playlistColors.normalBackground ?? .black
    }
    func contentRect(_ bounds: NSRect) -> NSRect {
        if wmp {
            let metrics = wmpMetrics
            return NSRect(x: metrics.leftBorder, y: metrics.bottomBorder,
                          width: max(0, bounds.width - metrics.leftBorder - metrics.rightBorder),
                          height: max(0, bounds.height - titleHeight - metrics.bottomBorder))
        }
        let border = modern ? ModernSkinElements.auxiliaryWindowBorderWidth : SkinElements.SpectrumWindow.Layout.leftBorder
        let bottom = modern ? border : SkinElements.SpectrumWindow.Layout.bottomBorder
        return NSRect(x: border, y: bottom, width: max(0, bounds.width - 2 * border),
                      height: max(0, bounds.height - titleHeight - bottom))
    }
    func closeRect(_ bounds: NSRect) -> NSRect {
        guard titleHeight > 4 else { return .zero }
        if wmp {
            // Stated top-left, like the chrome that draws it; flipped into the view's space.
            let rect = SkinnedSurfaceChrome.closeButtonRect(in: bounds, captionHeight: titleHeight)
            return NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        }
        let size: CGFloat = modern ? 14 * ModernSkinElements.scaleFactor : 9 * classicScale
        return NSRect(x: bounds.maxX - size - (modern ? 5 : 3) * (modern ? ModernSkinElements.scaleFactor : classicScale),
                      y: bounds.maxY - titleHeight + (titleHeight - size) / 2, width: size, height: size)
    }
    func draw(_ bounds: NSRect, closePressed: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if modern {
            ModernSonosChrome.draw(in: bounds, window: window, closePressed: closePressed,
                                   titleHeight: titleHeight, closeRect: closeRect(bounds), context: context)
            return
        }
        if wmp, let style = WindowManager.shared.hostedSurfaceStyle {
            drawWMP(bounds, style: style, closePressed: closePressed, context: context)
            return
        }
        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        (WindowManager.shared.winampModernSurfaceStyle?.background ?? skin.playlistColors.normalBackground).setFill()
        bounds.fill()
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if WindowManager.shared.hideTitleBars {
            context.translateBy(x: 0, y: -SkinElements.SpectrumWindow.Layout.titleBarHeight)
        }
        if let style = WindowManager.shared.winampModernSurfaceStyle {
            WinampModernChrome(style: style).drawSpectrumFamilyWindow(
                in: context, bounds: bounds, metrics: .spectrumFamily,
                isActive: window?.isKeyWindow ?? false, isClosePressed: closePressed,
                controlScale: classicScale, title: "SONOS", fillBackground: false)
        } else {
            SkinRenderer(skin: skin).drawSpectrumAnalyzerWindowChromeOverlay(
                in: context, bounds: bounds, isActive: window?.isKeyWindow ?? false,
                pressedButton: closePressed ? .close : nil, controlScale: classicScale, title: "SONOS")
        }
        context.restoreGState()
    }

    /// The hosted-window contract (`wmp-skin-guide/reference/windows.md` § *Adding a NullPlayer-native window in WMP
    /// mode*): ground only in the hole, then the borrowed frame over it.
    private func drawWMP(_ bounds: NSRect, style: SkinnedSurfaceStyle, closePressed: Bool, context: CGContext) {
        style.background.setFill()
        SkinnedSurfaceChrome.hostedGroundRect(in: bounds).fill()
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if WindowManager.shared.hideTitleBars {
            context.translateBy(x: 0, y: -wmpMetrics.titleHeight)
        }
        SkinnedSurfaceChrome(style: style, artwork: WindowManager.shared.hostedSurfaceFrameArtwork(for: bounds.size))
            .drawSpectrumFamilyWindow(
                in: context, bounds: bounds, metrics: .spectrumFamily,
                isActive: window?.isKeyWindow ?? true, isClosePressed: closePressed,
                controlScale: classicScale, title: "SONOS", fillBackground: false)
        context.restoreGState()
    }
}
