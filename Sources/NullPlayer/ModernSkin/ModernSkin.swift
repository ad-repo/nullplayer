import AppKit

enum ModernOpacityArea: CaseIterable {
    case mainWindow
    case timeDisplay
    case trackDisplay
    case volumeArea
    case spectrumArea
    case waveformArea
    case eqFaderBackground
    case curveBackground
}

struct ResolvedAreaOpacityStyle: Equatable {
    let background: CGFloat
    let border: CGFloat
    let content: CGFloat
}

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

    /// Get the resolved color for an element with a custom fallback color
    func elementColor(for elementId: String, fallback: NSColor) -> NSColor {
        if let colorHex = config.elements?[elementId]?.color {
            return NSColor.from(hex: colorHex)
        }
        return fallback
    }

    // MARK: - Opacity Resolution

    /// Resolve area-specific opacity channels from `window.areaOpacity`,
    /// treating per-area channels as multipliers of `window.opacity`.
    /// Missing areas/channels default to multiplier `1.0`.
    func resolvedOpacity(for area: ModernOpacityArea) -> ResolvedAreaOpacityStyle {
        let baseOpacity = clampedOpacity(config.window.opacity)
        let areaStyle = areaOpacityStyle(for: area)
        return ResolvedAreaOpacityStyle(
            background: resolvedChannelOpacity(multiplier: areaStyle?.background, baseOpacity: baseOpacity),
            border: resolvedChannelOpacity(multiplier: areaStyle?.border, baseOpacity: baseOpacity),
            content: resolvedChannelOpacity(multiplier: areaStyle?.content, baseOpacity: baseOpacity)
        )
    }

    private func areaOpacityStyle(for area: ModernOpacityArea) -> AreaOpacityStyle? {
        let areaOpacity = config.window.areaOpacity
        switch area {
        case .mainWindow:
            return areaOpacity?.mainWindow
        case .timeDisplay:
            return areaOpacity?.timeDisplay
        case .trackDisplay:
            return areaOpacity?.trackDisplay
        case .volumeArea:
            return areaOpacity?.volumeArea
        case .spectrumArea:
            return areaOpacity?.spectrumArea
        case .waveformArea:
            return areaOpacity?.waveformArea
        case .eqFaderBackground:
            return areaOpacity?.eqFaderBackground
        case .curveBackground:
            return areaOpacity?.curveBackground
        }
    }

    private func clampedOpacity(_ value: CGFloat) -> CGFloat {
        min(1.0, max(0.0, value))
    }

    private func resolvedChannelOpacity(multiplier: CGFloat?, baseOpacity: CGFloat) -> CGFloat {
        let m = clampedOpacity(multiplier ?? 1.0)
        return clampedOpacity(baseOpacity * m)
    }

    /// Global text opacity multiplier for modern string rendering.
    /// Defaults to 1.0 when `window.textOpacity` is omitted.
    var textOpacityMultiplier: CGFloat {
        clampedOpacity(config.window.textOpacity ?? 1.0)
    }

    /// Apply global text opacity to a color used for string drawing.
    func applyTextOpacity(to color: NSColor) -> NSColor {
        let alpha = clampedOpacity(color.alphaComponent * textOpacityMultiplier)
        return color.withAlphaComponent(alpha)
    }

    /// Optional main-window spectrum opacity override for the mini analyzer panel and bars.
    /// When nil, spectrum opacity follows legacy resolved area/window channels.
    var mainSpectrumOpacityOverride: CGFloat? {
        guard let value = config.window.mainSpectrumOpacity else { return nil }
        return clampedOpacity(value)
    }

    /// Apply main-window spectrum opacity override when present; otherwise return clamped input.
    func applyMainSpectrumOpacity(to opacity: CGFloat) -> CGFloat {
        mainSpectrumOpacityOverride ?? clampedOpacity(opacity)
    }

    /// Background opacity for the standalone spectrum window.
    /// Uses `window.opacity` — transparency is handled by the vis_classic transparent background
    /// mechanism, not the window fill. See `window.spectrumTransparentBackground`.
    var spectrumWindowBackgroundOpacity: CGFloat {
        clampedOpacity(config.window.opacity)
    }

    /// Background opacity for the waveform window.
    /// Falls back to `window.opacity` when `window.waveformWindowOpacity` is omitted.
    var waveformWindowBackgroundOpacity: CGFloat {
        clampedOpacity(config.window.waveformWindowOpacity ?? config.window.opacity)
    }

    var waveformTransparentBackgroundStyle: WaveformTransparentBackgroundStyle {
        config.waveform?.transparentBackgroundStyle ?? .glass
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
    
    /// Marquee/scrolling title text font (default base size 12.7)
    func marqueeFont() -> NSFont { scaledFont(size: config.fonts.marqueeSize ?? 12.7) }
    
    /// Playlist track list text font (default base size 8)
    func playlistFont() -> NSFont { scaledFont(size: config.fonts.playlistSize ?? 8) }

    /// Time display font (default base size 20)
    func timeDisplayFont() -> NSFont {
        let size = config.fonts.timeSize ?? ModernSkinFont.defaultTimeSize
        return timeFont?.withSize(size * ModernSkinElements.scaleFactor)
            ?? NSFont.monospacedSystemFont(ofSize: size * ModernSkinElements.scaleFactor, weight: .regular)
    }
    
    // MARK: - Title Character Sprites
    
    /// Cache for tinted character sprite images, keyed by "{imageKey}_{colorHex}".
    /// Invalidated on skin change (new ModernSkin instance created).
    private var tintedImageCache: [String: NSImage] = [:]
    
    /// Get a title character sprite image for the given character.
    ///
    /// Image key mapping (filesystem-safe -- avoids case collisions on macOS APFS):
    /// - Uppercase `A-Z` -> `title_upper_A` ... `title_upper_Z`
    /// - Lowercase `a-z` -> `title_lower_a` ... `title_lower_z` (falls back to uppercase)
    /// - Digits `0-9` -> `title_char_0` ... `title_char_9`
    /// - Space -> `title_char_space`
    /// - Punctuation: `-` -> `title_char_dash`, `.` -> `title_char_dot`, etc.
    ///
    /// Returns nil if no sprite is available (caller should fall back to font for this character).
    func titleCharImage(for character: Character) -> NSImage? {
        let key = titleCharImageKey(for: character)
        guard let key = key else { return nil }
        
        // Try exact key first
        if let img = images[key] {
            return img
        }
        
        // Lowercase fallback: try uppercase version
        if character.isLowercase, let upper = character.uppercased().first {
            let upperKey = titleCharImageKey(for: upper)
            if let upperKey = upperKey, let img = images[upperKey] {
                return img
            }
        }
        
        return nil
    }
    
    /// Debug-only: expose key mapping for logging
    func titleCharImageKey_debug(for character: Character) -> String? {
        return titleCharImageKey(for: character)
    }
    
    /// Map a character to its image key string.
    /// Uses `title_upper_` / `title_lower_` prefixes for letters to avoid case collisions
    /// on macOS's case-insensitive filesystem (APFS default).
    private func titleCharImageKey(for character: Character) -> String? {
        switch character {
        case "A"..."Z":
            return "title_upper_\(character)"
        case "a"..."z":
            return "title_lower_\(character)"
        case "0"..."9":
            return "title_char_\(character)"
        case " ":
            return "title_char_space"
        case "-":
            return "title_char_dash"
        case ".":
            return "title_char_dot"
        case "_":
            return "title_char_underscore"
        case ":":
            return "title_char_colon"
        case "(":
            return "title_char_lparen"
        case ")":
            return "title_char_rparen"
        case "[":
            return "title_char_lbracket"
        case "]":
            return "title_char_rbracket"
        case "&":
            return "title_char_amp"
        case "'":
            return "title_char_apos"
        case "+":
            return "title_char_plus"
        case "#":
            return "title_char_hash"
        case "/":
            return "title_char_slash"
        default:
            return nil
        }
    }
    
    /// Return a tinted copy of an image, using sourceAtop compositing on grayscale sprites.
    /// Results are cached by "{imageKey}_{colorHex}" to avoid per-frame compositing.
    /// Returns the original image if tintColor is nil.
    func tintedImage(_ image: NSImage, key: String, color: NSColor?) -> NSImage {
        guard let color = color else { return image }
        
        // Build cache key from image key + color hex
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (color.usingColorSpace(.sRGB) ?? color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let colorHex = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        let cacheKey = "\(key)_\(colorHex)"
        
        if let cached = tintedImageCache[cacheKey] {
            return cached
        }
        
        // Create tinted copy
        let size = image.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        
        tintedImageCache[cacheKey] = tinted
        return tinted
    }
    
    /// Check if this skin has any title character sprites loaded.
    /// Quick check to avoid sprite compositing attempts when no sprites exist.
    var hasTitleCharSprites: Bool {
        images.keys.contains { $0.hasPrefix("title_upper_") || $0.hasPrefix("title_lower_") || $0.hasPrefix("title_char_") }
    }
    
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
