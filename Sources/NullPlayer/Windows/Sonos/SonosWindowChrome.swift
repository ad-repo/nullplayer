import AppKit

/// Selects the existing auxiliary-window renderer; room controls own no skin assets.
struct SonosWindowChrome {
    let window: NSWindow?
    private var modern: Bool { WindowManager.shared.isModernUIEnabled }
    private var classicScale: CGFloat { WindowManager.shared.playlistChromeScale }
    var titleHeight: CGFloat {
        if modern {
            return WindowManager.shared.effectiveHideTitleBars(for: window)
                ? ModernSkinElements.auxiliaryWindowBorderWidth
                : ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        }
        return WindowManager.shared.hideTitleBars ? 0 : SkinElements.SpectrumWindow.Layout.titleBarHeight
    }
    var textColor: NSColor {
        if modern { return ModernSkinEngine.shared.currentSkin?.textColor ?? .labelColor }
        if let style = WindowManager.shared.winampModernSurfaceStyle { return style.text }
        return WindowManager.shared.currentSkin?.playlistColors.normalText ?? .green
    }
    var backgroundColor: NSColor {
        if modern { return ModernSkinEngine.shared.currentSkin?.backgroundColor ?? .black }
        if let style = WindowManager.shared.winampModernSurfaceStyle { return style.background }
        return WindowManager.shared.currentSkin?.playlistColors.normalBackground ?? .black
    }
    func contentRect(_ bounds: NSRect) -> NSRect {
        let border = modern ? ModernSkinElements.auxiliaryWindowBorderWidth : SkinElements.SpectrumWindow.Layout.leftBorder
        let bottom = modern ? border : SkinElements.SpectrumWindow.Layout.bottomBorder
        return NSRect(x: border, y: bottom, width: max(0, bounds.width - 2 * border),
                      height: max(0, bounds.height - titleHeight - bottom))
    }
    func closeRect(_ bounds: NSRect) -> NSRect {
        guard titleHeight > 4 else { return .zero }
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
}
