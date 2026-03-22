import AppKit

// MARK: - Skin Configuration (JSON Model)

/// Complete skin configuration parsed from `skin.json`.
/// Defines every visual property a modern skin can customize.
struct ModernSkinConfig: Codable {
    /// Metadata about the skin
    let meta: SkinMeta
    
    /// Color palette
    let palette: ColorPalette
    
    /// Font configuration
    let fonts: FontConfig
    
    /// Background configuration
    let background: BackgroundConfig
    
    /// Glow/bloom post-processing configuration
    let glow: GlowConfig
    
    /// Window chrome configuration
    let window: WindowConfig

    /// Visualization defaults and mode-specific preset/profile mappings
    let visualization: VisualizationConfig?

    /// Waveform window appearance defaults
    let waveform: WaveformConfig?
    
    /// Marquee/scrolling text configuration
    let marquee: MarqueeConfig?
    
    /// Title text rendering configuration (image-based vs font)
    let titleText: TitleTextConfig?
    
    /// Per-element overrides (position, size, color, image path)
    let elements: [String: ElementConfig]?
    
    /// Named animation definitions
    let animations: [String: AnimationConfig]?
}

// MARK: - Sub-Configs

/// Per-skin visualization defaults.
/// Allows skins to set default modes and per-mode preset/profile mappings.
struct VisualizationConfig: Codable {
    /// Default visualization mode for main window (`MainWindowVisMode.rawValue`)
    let mainWindowMode: String?

    /// Default visualization mode for spectrum window (`SpectrumQualityMode.rawValue`)
    let spectrumWindowMode: String?

    /// vis_classic profile defaults (only applies when mode is `vis_classic`)
    let visClassic: VisClassicVisualizationConfig?

    /// Fire mode preset defaults
    let fire: FireVisualizationConfig?

    /// Lightning mode preset defaults
    let lightning: LightningVisualizationConfig?

    /// Matrix mode preset defaults
    let matrix: MatrixVisualizationConfig?
}

struct WaveformConfig: Codable {
    let transparentBackgroundStyle: WaveformTransparentBackgroundStyle?
}

struct VisClassicVisualizationConfig: Codable {
    let mainWindowProfile: String?
    let spectrumWindowProfile: String?
    let mainWindowFitToWidth: Bool?
    let spectrumWindowFitToWidth: Bool?
    let mainWindowTransparentBackground: Bool?
    let spectrumWindowTransparentBackground: Bool?
    let mainWindowOpacity: CGFloat?
    let spectrumWindowOpacity: CGFloat?
}

struct FireVisualizationConfig: Codable {
    let mainWindowStyle: String?
    let mainWindowIntensity: String?
    let spectrumWindowStyle: String?
    let spectrumWindowIntensity: String?
}

struct LightningVisualizationConfig: Codable {
    let mainWindowStyle: String?
    let spectrumWindowStyle: String?
}

struct MatrixVisualizationConfig: Codable {
    let mainWindowColorScheme: String?
    let mainWindowIntensity: String?
    let spectrumWindowColorScheme: String?
    let spectrumWindowIntensity: String?
}

struct SkinMeta: Codable {
    let name: String
    let author: String
    let version: String
    let description: String?
}

struct ColorPalette: Codable {
    let primary: String        // Main accent color (e.g., "#00ffcc")
    let secondary: String      // Secondary accent
    let accent: String         // Highlight accent (e.g., "#ff00aa")
    let highlight: String?     // Optional highlight color
    let background: String     // Window background
    let surface: String        // Panel/surface background
    let text: String           // Primary text color
    let textDim: String        // Dimmed/inactive text
    let positive: String?      // Positive indicator
    let negative: String?      // Negative indicator
    let warning: String?       // Warning indicator
    let border: String?        // Border color (defaults to primary)
    let timeColor: String?     // Time display digit color (defaults to "#d9d900" warm yellow)
    let marqueeColor: String?  // Marquee/title text color (defaults to "#d9d900" warm yellow)
    let dataColor: String?     // Data field values: playlist numbers, library info (defaults to "#d9d900" warm yellow)
    let eqLow: String?         // EQ color at -12dB (defaults to "#00d900" green)
    let eqMid: String?         // EQ color at 0dB (defaults to "#d9d900" yellow)
    let eqHigh: String?        // EQ color at +12dB (defaults to "#d92600" red)
    
    // MARK: - Color Resolution
    
    private static let defaultTimeColor = "#d9d900"  // Warm glowing yellow (0.85, 0.85, 0.0)
    
    func resolvedPrimary() -> NSColor { NSColor.from(hex: primary) }
    func resolvedSecondary() -> NSColor { NSColor.from(hex: secondary) }
    func resolvedAccent() -> NSColor { NSColor.from(hex: accent) }
    func resolvedHighlight() -> NSColor { NSColor.from(hex: highlight ?? primary) }
    func resolvedBackground() -> NSColor { NSColor.from(hex: background) }
    func resolvedSurface() -> NSColor { NSColor.from(hex: surface) }
    func resolvedText() -> NSColor { NSColor.from(hex: text) }
    func resolvedTextDim() -> NSColor { NSColor.from(hex: textDim) }
    func resolvedPositive() -> NSColor { NSColor.from(hex: positive ?? "#00ff00") }
    func resolvedNegative() -> NSColor { NSColor.from(hex: negative ?? "#ff0000") }
    func resolvedWarning() -> NSColor { NSColor.from(hex: warning ?? "#ffaa00") }
    func resolvedBorder() -> NSColor { NSColor.from(hex: border ?? primary) }
    func resolvedTimeColor() -> NSColor { NSColor.from(hex: timeColor ?? Self.defaultTimeColor) }
    func resolvedMarqueeColor() -> NSColor { NSColor.from(hex: marqueeColor ?? Self.defaultTimeColor) }
    func resolvedDataColor() -> NSColor { NSColor.from(hex: dataColor ?? Self.defaultTimeColor) }
    func resolvedEqLow() -> NSColor { NSColor.from(hex: eqLow ?? "#00d900") }
    func resolvedEqMid() -> NSColor { NSColor.from(hex: eqMid ?? "#d9d900") }
    func resolvedEqHigh() -> NSColor { NSColor.from(hex: eqHigh ?? "#d92600") }
}

struct FontConfig: Codable {
    /// Primary font name (e.g., "DepartureMono-Regular")
    let primaryName: String
    
    /// Fallback system font name if primary can't be loaded
    let fallbackName: String?
    
    /// Font sizes for different contexts (unscaled base sizes)
    let titleSize: CGFloat?      // Title bar text (default 8)
    let bodySize: CGFloat?       // General body text (default 9)
    let smallSize: CGFloat?      // Small labels, toggle buttons (default 7)
    let timeSize: CGFloat?       // Time display digits (default 20)
    let infoSize: CGFloat?       // Info labels: bitrate, samplerate, BPM (default 6.5)
    let eqLabelSize: CGFloat?    // EQ frequency labels (default 7)
    let eqValueSize: CGFloat?    // EQ dB value text (default 6)
    let marqueeSize: CGFloat?    // Marquee/scrolling title text (default 12.7)
    let playlistSize: CGFloat?   // Playlist track list text (default 8)
}

struct BackgroundConfig: Codable {
    /// Path to background image (relative to skin bundle)
    let image: String?
    
    /// Grid configuration (used if no image)
    let grid: GridConfig?
}

struct GridConfig: Codable {
    let color: String
    let spacing: CGFloat
    let angle: CGFloat
    let opacity: CGFloat
    let perspective: Bool?
}

struct GlowConfig: Codable {
    let enabled: Bool
    let radius: CGFloat?
    let intensity: CGFloat?
    let threshold: CGFloat?
    let color: String?
    let elementBlur: CGFloat?  // Multiplier for element-level glow blur (defaults to 1.0)
}

struct WindowConfig: Codable {
    let borderWidth: CGFloat?
    let borderColor: String?
    let cornerRadius: CGFloat?
    let scale: CGFloat?        // UI scale factor (defaults to 1.25)
    let opacity: CGFloat       // Window background opacity 0.0-1.0 (defaults to 1.0 for old skins)
    let textOpacity: CGFloat?  // Global text opacity multiplier 0.0-1.0 (defaults to 1.0)
    let mainSpectrumOpacity: CGFloat?          // Main-window spectrum opacity override 0.0-1.0 (optional)
    let spectrumTransparentBackground: Bool?   // Spectrum window: true = vis_classic transparent background (optional)
    let waveformWindowOpacity: CGFloat?        // Waveform window background opacity override 0.0-1.0 (optional)
    let seamlessDocking: CGFloat?  // 0.0 (full borders) to 1.0 (fully hidden on docked edges). Default 0.
    let areaOpacity: AreaOpacityConfig? // Optional per-area opacity overrides

    init(borderWidth: CGFloat?, borderColor: String?, cornerRadius: CGFloat?, scale: CGFloat?,
         opacity: CGFloat, textOpacity: CGFloat?, mainSpectrumOpacity: CGFloat?,
         spectrumTransparentBackground: Bool?, waveformWindowOpacity: CGFloat?,
         seamlessDocking: CGFloat?, areaOpacity: AreaOpacityConfig?) {
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.scale = scale
        self.opacity = opacity
        self.textOpacity = textOpacity
        self.mainSpectrumOpacity = mainSpectrumOpacity
        self.spectrumTransparentBackground = spectrumTransparentBackground
        self.waveformWindowOpacity = waveformWindowOpacity
        self.seamlessDocking = seamlessDocking
        self.areaOpacity = areaOpacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        borderWidth                    = try c.decodeIfPresent(CGFloat.self, forKey: .borderWidth)
        borderColor                    = try c.decodeIfPresent(String.self,  forKey: .borderColor)
        cornerRadius                   = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)
        scale                          = try c.decodeIfPresent(CGFloat.self, forKey: .scale)
        opacity                        = try c.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1.0
        textOpacity                    = try c.decodeIfPresent(CGFloat.self, forKey: .textOpacity)
        mainSpectrumOpacity            = try c.decodeIfPresent(CGFloat.self, forKey: .mainSpectrumOpacity)
        spectrumTransparentBackground  = try c.decodeIfPresent(Bool.self,    forKey: .spectrumTransparentBackground)
        waveformWindowOpacity          = try c.decodeIfPresent(CGFloat.self, forKey: .waveformWindowOpacity)
        seamlessDocking                = try c.decodeIfPresent(CGFloat.self, forKey: .seamlessDocking)
        areaOpacity                    = try c.decodeIfPresent(AreaOpacityConfig.self, forKey: .areaOpacity)
    }
}

/// Per-area opacity styles for Modern UI regions.
/// Channel values are multipliers (0..1) applied to `window.opacity`.
/// Missing areas/channels default to multiplier `1.0`.
struct AreaOpacityConfig: Codable, Equatable {
    let mainWindow: AreaOpacityStyle?
    let timeDisplay: AreaOpacityStyle?
    let trackDisplay: AreaOpacityStyle?
    let volumeArea: AreaOpacityStyle?
    let spectrumArea: AreaOpacityStyle?
    let waveformArea: AreaOpacityStyle?
    let eqFaderBackground: AreaOpacityStyle?
    let curveBackground: AreaOpacityStyle?
}

/// Opacity channels for a UI area.
/// - background: panel/background fills
/// - border: border strokes/glow around that area
/// - content: text/icons/bars/foreground content in that area
/// Values are multiplier factors applied to `window.opacity`.
struct AreaOpacityStyle: Codable, Equatable {
    let background: CGFloat?
    let border: CGFloat?
    let content: CGFloat?
}

struct MarqueeConfig: Codable {
    let scrollSpeed: CGFloat?  // Scroll speed in points per second (defaults to 30)
    let scrollGap: CGFloat?    // Gap between repeated text in points (defaults to 50)
}

/// Title text rendering configuration.
/// Controls whether title bar text uses image-based rendering (character sprites or full title images)
/// or the default system font rendering.
///
/// Three-tier fallback: full title image -> character sprites -> system font.
/// Character sprites use variable-width layout (each glyph's actual image width is measured).
struct TitleTextConfig: Codable {
    /// Rendering mode: "image" uses sprite/image-based rendering, "font" uses system font (default)
    let mode: TitleTextMode?
    
    /// Extra spacing between character sprites in base coordinates (default 1). Negative tightens.
    let charSpacing: CGFloat?
    
    /// Height to render character sprites in base coordinates (default 10)
    let charHeight: CGFloat?
    
    /// Horizontal alignment within the title bar rect (default "center")
    let alignment: TitleTextAlignment?
    
    /// Hex color to tint grayscale character sprites (nil = draw sprites as-is).
    /// Skin authors can provide white/grayscale sprites and tint them to any color.
    let tintColor: String?
    
    /// Left padding in base coordinates (default 0)
    let padLeft: CGFloat?
    
    /// Right padding in base coordinates (default 0)
    let padRight: CGFloat?
    
    /// Vertical nudge in base coordinates (default 0, positive = up)
    let verticalOffset: CGFloat?
    
    /// Image key for decoration sprite drawn to the left of the title text (nil = none).
    /// The image is loaded via `skin.image(for:)` and drawn at `charHeight`, preserving aspect ratio.
    let decorationLeft: String?
    
    /// Image key for decoration sprite drawn to the right of the title text (nil = none).
    let decorationRight: String?
    
    /// Spacing between decoration sprites and title text in base coordinates (default 3)
    let decorationSpacing: CGFloat?
    
    enum TitleTextMode: String, Codable {
        case image  // Use image-based rendering (full title image or character sprites)
        case font   // Use system font (current default behavior)
    }
    
    enum TitleTextAlignment: String, Codable {
        case left, center, right
    }
}

struct ElementConfig: Codable {
    /// Image path override (relative to skin bundle images/)
    let image: String?
    
    /// Position override
    let x: CGFloat?
    let y: CGFloat?
    
    /// Size override
    let width: CGFloat?
    let height: CGFloat?
    
    /// Per-element color override
    let color: String?
    
    /// Animation reference (key into animations dict)
    let animation: String?
}

struct AnimationConfig: Codable {
    /// Animation type
    let type: AnimationType
    
    /// Frame image paths (for spriteFrames type)
    let frames: [String]?
    
    /// Duration in seconds
    let duration: CGFloat?
    
    /// Repeat mode
    let repeatMode: RepeatMode?
    
    /// Min/max values for parametric animations
    let minValue: CGFloat?
    let maxValue: CGFloat?
    
    enum AnimationType: String, Codable {
        case spriteFrames
        case pulse
        case glow
        case rotate
        case colorCycle
    }
    
    enum RepeatMode: String, Codable {
        case loop
        case reverse
        case once
    }
}

// MARK: - NSColor Hex Extension

extension NSColor {
    /// Create NSColor from hex string (e.g., "#00ffcc" or "00ffcc")
    static func from(hex: String) -> NSColor {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        
        guard hexString.count == 6,
              let hexValue = UInt64(hexString, radix: 16) else {
            return .white
        }
        
        let r = CGFloat((hexValue >> 16) & 0xFF) / 255.0
        let g = CGFloat((hexValue >> 8) & 0xFF) / 255.0
        let b = CGFloat(hexValue & 0xFF) / 255.0
        
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
