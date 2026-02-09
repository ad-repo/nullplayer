import AppKit

/// Represents a loaded classic skin skin with all its assets
struct Skin {
    // MARK: - Main Window Assets
    
    /// Main window background (main.bmp)
    let main: NSImage?
    
    /// Control buttons sprite sheet (cbuttons.bmp)
    let cbuttons: NSImage?
    
    /// Mono/stereo indicator (monoster.bmp)
    let monoster: NSImage?
    
    /// Time display numbers (numbers.bmp)
    let numbers: NSImage?
    
    /// Extended numbers (nums_ex.bmp) - optional
    let numsEx: NSImage?
    
    /// Play/pause status indicator (playpaus.bmp)
    let playpaus: NSImage?
    
    /// Position/seek bar (posbar.bmp)
    let posbar: NSImage?
    
    /// Shuffle/repeat buttons (shufrep.bmp)
    let shufrep: NSImage?
    
    /// Scrolling text font (text.bmp)
    let text: NSImage?
    
    /// Title bar elements (titlebar.bmp)
    let titlebar: NSImage?
    
    /// Volume slider (volume.bmp)
    let volume: NSImage?
    
    /// Balance slider (balance.bmp)
    let balance: NSImage?
    
    // MARK: - Equalizer Assets
    
    /// Equalizer background (eqmain.bmp)
    let eqmain: NSImage?
    
    /// EQ extras (eq_ex.bmp) - optional
    let eqEx: NSImage?
    
    // MARK: - Playlist Assets
    
    /// Playlist editor background (pledit.bmp)
    let pledit: NSImage?
    
    // MARK: - Generic/AVS/ProjectM Window Assets
    
    /// Generic window sprites including font (gen.bmp)
    let gen: NSImage?
    
    // MARK: - NullPlayer Custom Assets (loaded from .wsz if present)
    
    /// Library window image (library-window.png inside .wsz)
    let libraryWindow: NSImage?
    
    /// NullPlayer logo icon (null_outline.png inside .wsz)
    let nullPlayerLogo: NSImage?
    
    /// Playlist colors
    let playlistColors: PlaylistColors
    
    // MARK: - Other Assets
    
    /// Visualization colors
    let visColors: [NSColor]
    
    /// Window regions for non-rectangular shapes
    let regions: WindowRegions?
    
    /// Custom cursors
    let cursors: [String: NSCursor]
    
    // MARK: - Window Dimensions
    
    /// Scale factor for the UI (1.25 = 25% larger than original)
    static let scaleFactor: CGFloat = 1.25
    
    /// Base classic skin dimensions (275x116 in classic classic skin) - used for sprite coordinate calculations
    static let baseMainSize = NSSize(width: 275, height: 116)
    
    /// Main window size scaled - actual window dimensions
    static let mainWindowSize = NSSize(width: baseMainSize.width * scaleFactor, height: baseMainSize.height * scaleFactor)
    
    /// Base EQ dimensions (same as main in classic classic skin)
    static let baseEQSize = NSSize(width: 275, height: 116)
    
    /// Equalizer window size scaled
    static let eqWindowSize = NSSize(width: baseEQSize.width * scaleFactor, height: baseEQSize.height * scaleFactor)
    
    /// Playlist minimum size scaled
    static let playlistMinSize = NSSize(width: baseMainSize.width * scaleFactor, height: baseMainSize.height * scaleFactor)
    
    /// Shade mode height scaled
    static let shadeHeight: CGFloat = 14 * scaleFactor
    
    // MARK: - Custom Window Image Helpers
    
    /// Get the library window image from this skin instance (loaded from .wsz)
    /// Returns nil if not present in the skin package
    var libraryWindowImage: NSImage? { libraryWindow }
    
    /// Get the NullPlayer logo icon from this skin instance (loaded from .wsz)
    /// Returns nil if not present in the skin package
    var nullPlayerLogoImage: NSImage? { nullPlayerLogo }
    
    /// Get the gen window image from this skin instance (loaded from .wsz as gen.bmp/gen.png)
    /// Returns nil if not present in the skin package
    var genWindowImage: NSImage? { gen }
}

// MARK: - Playlist Colors

struct PlaylistColors {
    let normalText: NSColor
    let currentText: NSColor
    let normalBackground: NSColor
    let selectedBackground: NSColor
    let font: NSFont
    
    static let `default` = PlaylistColors(
        normalText: NSColor(hex: "#00FF00") ?? .green,
        currentText: .white,
        normalBackground: .black,
        selectedBackground: NSColor(hex: "#0000FF") ?? .blue,
        font: .systemFont(ofSize: 8)
    )
    
    init(normalText: NSColor, currentText: NSColor, normalBackground: NSColor, selectedBackground: NSColor, font: NSFont) {
        self.normalText = normalText
        self.currentText = currentText
        self.normalBackground = normalBackground
        self.selectedBackground = selectedBackground
        self.font = font
    }
}

// MARK: - Window Regions

struct WindowRegions {
    let mainNormal: [NSPoint]?
    let mainShade: [NSPoint]?
    let eqNormal: [NSPoint]?
    let eqShade: [NSPoint]?
    let playlistNormal: [NSPoint]?
    let playlistShade: [NSPoint]?
}

// MARK: - NSColor Extension

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
