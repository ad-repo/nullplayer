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
    
    /// Per-element overrides (position, size, color, image path)
    let elements: [String: ElementConfig]?
    
    /// Named animation definitions
    let animations: [String: AnimationConfig]?
}

// MARK: - Sub-Configs

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
    
    // MARK: - Color Resolution
    
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
}

struct FontConfig: Codable {
    /// Primary font name (e.g., "DepartureMono-Regular")
    let primaryName: String
    
    /// Fallback system font name if primary can't be loaded
    let fallbackName: String?
    
    /// Font sizes for different contexts
    let titleSize: CGFloat?
    let bodySize: CGFloat?
    let smallSize: CGFloat?
    let timeSize: CGFloat?
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
}

struct WindowConfig: Codable {
    let borderWidth: CGFloat?
    let borderColor: String?
    let cornerRadius: CGFloat?
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
