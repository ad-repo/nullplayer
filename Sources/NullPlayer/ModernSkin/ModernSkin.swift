import AppKit

/// A fully loaded modern skin with config, resolved images, and fallback rendering data.
/// This is the runtime representation of a skin, ready for rendering.
class ModernSkin {
    
    /// The parsed skin configuration
    let config: ModernSkinConfig
    
    /// Cached images for elements, keyed by "{elementId}_{state}"
    /// e.g., "btn_play_normal", "btn_play_pressed", "seek_thumb_normal"
    private(set) var images: [String: NSImage] = [:]
    
    /// The skin bundle directory (for resolving relative paths)
    let bundlePath: URL?
    
    /// Resolved primary font
    private(set) var primaryFont: NSFont?
    
    /// Resolved time display font
    private(set) var timeFont: NSFont?
    
    /// Resolved small label font
    private(set) var smallFont: NSFont?
    
    /// Background image (if specified in config)
    private(set) var backgroundImage: NSImage?
    
    // MARK: - Resolved Palette Colors (cached)
    
    let primaryColor: NSColor
    let secondaryColor: NSColor
    let accentColor: NSColor
    let highlightColor: NSColor
    let backgroundColor: NSColor
    let surfaceColor: NSColor
    let textColor: NSColor
    let textDimColor: NSColor
    let positiveColor: NSColor
    let negativeColor: NSColor
    let warningColor: NSColor
    let borderColor: NSColor
    let timeColor: NSColor
    let marqueeColor: NSColor
    let dataColor: NSColor
    let eqLowColor: NSColor
    let eqMidColor: NSColor
    let eqHighColor: NSColor
    
    /// Multiplier for element-level glow blur (from glow.elementBlur, defaults to 1.0)
    let elementGlowMultiplier: CGFloat
    
    // MARK: - Initialization
    
    init(config: ModernSkinConfig, bundlePath: URL?) {
        self.config = config
        self.bundlePath = bundlePath
        
        // Pre-resolve all palette colors
        self.primaryColor = config.palette.resolvedPrimary()
        self.secondaryColor = config.palette.resolvedSecondary()
        self.accentColor = config.palette.resolvedAccent()
        self.highlightColor = config.palette.resolvedHighlight()
        self.backgroundColor = config.palette.resolvedBackground()
        self.surfaceColor = config.palette.resolvedSurface()
        self.textColor = config.palette.resolvedText()
        self.textDimColor = config.palette.resolvedTextDim()
        self.positiveColor = config.palette.resolvedPositive()
        self.negativeColor = config.palette.resolvedNegative()
        self.warningColor = config.palette.resolvedWarning()
        self.borderColor = config.palette.resolvedBorder()
        self.timeColor = config.palette.resolvedTimeColor()
        self.marqueeColor = config.palette.resolvedMarqueeColor()
        self.dataColor = config.palette.resolvedDataColor()
        self.eqLowColor = config.palette.resolvedEqLow()
        self.eqMidColor = config.palette.resolvedEqMid()
        self.eqHighColor = config.palette.resolvedEqHigh()
        self.elementGlowMultiplier = config.glow.elementBlur ?? 1.0
    }
    
    // MARK: - Image Access
    
    /// Get the image for an element in a specific state.
    /// Returns nil if no image is available (renderer should use programmatic fallback).
    func image(for elementId: String, state: String = "normal") -> NSImage? {
        // Try element_state first
        if let img = images["\(elementId)_\(state)"] {
            return img
        }
        // Fall back to element without state (single image for all states)
        if let img = images[elementId] {
            return img
        }
        return nil
    }
    
    /// Store an image for an element+state combination
    func setImage(_ image: NSImage, for elementId: String, state: String? = nil) {
        if let state = state {
            images["\(elementId)_\(state)"] = image
        } else {
            images[elementId] = image
        }
    }
    
    /// Set the resolved fonts
    func setFonts(primary: NSFont?, time: NSFont?, small: NSFont?) {
        self.primaryFont = primary
        self.timeFont = time
        self.smallFont = small
    }
    
    /// Set the background image
    func setBackgroundImage(_ image: NSImage?) {
        self.backgroundImage = image
    }
    
    // MARK: - Element Config Helpers
    
    /// Get element-specific config override (if any)
    func elementConfig(for elementId: String) -> ElementConfig? {
        config.elements?[elementId]
    }
    
    /// Get the resolved color for an element (element override > palette text)
    func elementColor(for elementId: String) -> NSColor {
        if let colorHex = config.elements?[elementId]?.color {
            return NSColor.from(hex: colorHex)
        }
        return textColor
    }
    
    /// Get resolved rect for an element, applying any config overrides
    func resolvedRect(for element: ModernSkinElements.Element) -> NSRect {
        guard let override = config.elements?[element.id] else {
            return element.defaultRect
        }
        return NSRect(
            x: override.x ?? element.defaultRect.origin.x,
            y: override.y ?? element.defaultRect.origin.y,
            width: override.width ?? element.defaultRect.size.width,
            height: override.height ?? element.defaultRect.size.height
        )
    }
    
    // MARK: - Scaled Font Helpers
    
    /// Return the skin's primary font at an arbitrary base size, scaled by the current scale factor.
    /// Falls back to monospaced system font if no skin font is available.
    func scaledFont(size: CGFloat) -> NSFont {
        let scale = ModernSkinElements.scaleFactor
        return primaryFont?.withSize(size * scale)
            ?? NSFont.monospacedSystemFont(ofSize: size * scale, weight: .regular)
    }
    
    /// Return a proportional system font at scaled size. Used for data-dense views (library browser)
    /// where the skin's monospace font would waste space and hurt readability.
    /// Uses `baseScaleFactor * sizeMultiplier` so fonts scale with double-size mode.
    func scaledSystemFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return NSFont.systemFont(ofSize: size * ModernSkinElements.baseScaleFactor * ModernSkinElements.sizeMultiplier, weight: weight)
    }
    
    /// Return the skin's primary font at a fixed point size, scaled by `sizeMultiplier`.
    /// Used for side-window chrome (tabs, server bar) so they scale with double-size mode.
    func sideWindowFont(size: CGFloat) -> NSFont {
        let adjustedSize = size * ModernSkinElements.sizeMultiplier
        return primaryFont?.withSize(adjustedSize)
            ?? NSFont.monospacedSystemFont(ofSize: adjustedSize, weight: .regular)
    }
    
    /// Title bar text font (default base size 8)
    func titleBarFont() -> NSFont { scaledFont(size: config.fonts.titleSize ?? 8) }
    
    /// General body text font (default base size 9)
    func bodyFont() -> NSFont { scaledFont(size: config.fonts.bodySize ?? 9) }
    
    /// Small labels and toggle button text font (default base size 7)
    func smallLabelFont() -> NSFont { scaledFont(size: config.fonts.smallSize ?? 7) }
    
    /// Info labels font: bitrate, samplerate, BPM (default base size 6.5)
    func infoFont() -> NSFont { scaledFont(size: config.fonts.infoSize ?? 6.5) }
    
    /// EQ frequency label font (default base size 7)
    func eqLabelFont() -> NSFont { scaledFont(size: config.fonts.eqLabelSize ?? 7) }
    
    /// EQ dB value text font (default base size 6)
    func eqValueFont() -> NSFont { scaledFont(size: config.fonts.eqValueSize ?? 6) }
    
    /// Marquee/scrolling title text font (default base size 11.7)
    func marqueeFont() -> NSFont { scaledFont(size: config.fonts.marqueeSize ?? 11.7) }
    
    /// Playlist track list text font (default base size 8)
    func playlistFont() -> NSFont { scaledFont(size: config.fonts.playlistSize ?? 8) }
    
    // MARK: - Spectrum Colors
    
    /// Generate spectrum visualization colors from the skin palette.
    /// Returns an array of NSColors suitable for the SpectrumAnalyzerView.
    func spectrumColors() -> [NSColor] {
        var colors: [NSColor] = []
        // Generate a 24-color gradient from accent (bottom) to primary (top)
        for i in 0..<24 {
            let t = CGFloat(i) / 23.0
            colors.append(interpolateColor(from: accentColor, to: primaryColor, t: t))
        }
        return colors
    }
    
    /// Linear color interpolation
    private func interpolateColor(from: NSColor, to: NSColor, t: CGFloat) -> NSColor {
        let fromComponents = from.usingColorSpace(.sRGB) ?? from
        let toComponents = to.usingColorSpace(.sRGB) ?? to
        
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        
        fromComponents.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        toComponents.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        
        return NSColor(
            red: fr + (tr - fr) * t,
            green: fg + (tg - fg) * t,
            blue: fb + (tb - fb) * t,
            alpha: fa + (ta - fa) * t
        )
    }
}
