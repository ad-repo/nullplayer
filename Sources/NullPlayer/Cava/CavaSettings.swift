import Foundation
import AppKit

/// Cava spectrum analyzer user preferences, persisted in UserDefaults.
/// Independent of Remember-State; these are durable preferences.
enum CavaSettings {
    private static let defaults = UserDefaults.standard

    enum Mode: Int {
        case mono = 0
        case stereo = 1
    }

    private static let modeKey = "cavaMode"
    private static let barCountKey = "cavaBarCount"
    private static let lowGradientColorKey = "cavaLowGradientColor"
    private static let highGradientColorKey = "cavaHighGradientColor"
    private static let colorsCustomizedKey = "cavaColorsCustomized"
    private static let transparentBackgroundKey = "cavaTransparentBackground"
    private static let noiseReductionKey = "cavaNoiseReduction"
    private static let bassTiltKey = "cavaBassTilt"

    // Factory defaults for the exposed tuning knobs (the "Reset to Defaults" target).
    static let defaultBarCount = 32
    static let defaultNoiseReduction = 0.65   // smoothing / latency; lower = snappier
    static let defaultBassTilt = 0.3          // band bin-count exponent; higher = more bass

    // MARK: - Mode (Mono/Stereo)

    static var mode: Mode {
        get {
            guard defaults.object(forKey: modeKey) != nil else { return .stereo }
            let raw = defaults.integer(forKey: modeKey)
            return Mode(rawValue: raw) ?? .stereo
        }
        set {
            defaults.set(newValue.rawValue, forKey: modeKey)
        }
    }

    // MARK: - Bar Count

    static var barCount: Int {
        get {
            let count = defaults.integer(forKey: barCountKey)
            return count > 0 ? count : defaultBarCount
        }
        set {
            let clamped = max(1, min(128, newValue))
            defaults.set(clamped, forKey: barCountKey)
        }
    }

    // MARK: - DSP Tuning

    /// Temporal smoothing (0…0.95). Higher = smoother but laggier; lower = snappier/more real-time.
    static var noiseReduction: Double {
        get {
            guard defaults.object(forKey: noiseReductionKey) != nil else { return defaultNoiseReduction }
            return min(0.95, max(0.0, defaults.double(forKey: noiseReductionKey)))
        }
        set { defaults.set(min(0.95, max(0.0, newValue)), forKey: noiseReductionKey) }
    }

    /// Bass↔treble tilt: the per-band bin-count exponent (0…1). 0 = brightest, 1 = bassiest.
    static var bassTilt: Double {
        get {
            guard defaults.object(forKey: bassTiltKey) != nil else { return defaultBassTilt }
            return min(1.0, max(0.0, defaults.double(forKey: bassTiltKey)))
        }
        set { defaults.set(min(1.0, max(0.0, newValue)), forKey: bassTiltKey) }
    }

    /// Restore the exposed tuning knobs (bar count, smoothing, bass tilt) to factory defaults.
    /// Leaves mode / colors / transparency alone (those have their own controls).
    static func resetTuning() {
        defaults.removeObject(forKey: barCountKey)
        defaults.removeObject(forKey: noiseReductionKey)
        defaults.removeObject(forKey: bassTiltKey)
    }

    // MARK: - Gradient Colors

    /// Low-frequency bar color (default: dark blue).
    static var lowGradientColor: NSColor {
        get {
            let data = defaults.data(forKey: lowGradientColorKey)
            if let data, let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                return color
            }
            return NSColor(red: 0.0, green: 0.3, blue: 1.0, alpha: 1.0)  // Default: bright blue
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false) {
                defaults.set(data, forKey: lowGradientColorKey)
            }
        }
    }

    /// High-frequency bar color (default: bright magenta).
    static var highGradientColor: NSColor {
        get {
            let data = defaults.data(forKey: highGradientColorKey)
            if let data, let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                return color
            }
            return NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)  // Default: magenta
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false) {
                defaults.set(data, forKey: highGradientColorKey)
            }
        }
    }

    // MARK: - Color Schemes

    /// A named low→high gradient preset offered in the right-click menu.
    struct ColorScheme {
        let name: String
        let low: NSColor
        let high: NSColor
    }

    static let colorSchemes: [ColorScheme] = [
        // Low color = short/quiet bars, high color = tall/loud bars (interpolated by bar height).
        ColorScheme(name: "Blue → Magenta",
                    low: NSColor(red: 0.0, green: 0.3, blue: 1.0, alpha: 1.0),
                    high: NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)),
        ColorScheme(name: "Green → Red",
                    low: NSColor(red: 0.0, green: 0.85, blue: 0.2, alpha: 1.0),
                    high: NSColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)),
        ColorScheme(name: "Fire",
                    low: NSColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0),
                    high: NSColor(red: 0.9, green: 0.1, blue: 0.0, alpha: 1.0)),
        ColorScheme(name: "Ice",
                    low: NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0),
                    high: NSColor(red: 0.55, green: 0.1, blue: 1.0, alpha: 1.0)),
        ColorScheme(name: "Winamp Green",
                    low: NSColor(red: 0.0, green: 0.35, blue: 0.0, alpha: 1.0),
                    high: NSColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)),
        ColorScheme(name: "Sunset",
                    low: NSColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1.0),
                    high: NSColor(red: 0.8, green: 0.0, blue: 0.45, alpha: 1.0)),
        ColorScheme(name: "Vaporwave",
                    low: NSColor(red: 0.0, green: 0.9, blue: 0.9, alpha: 1.0),
                    high: NSColor(red: 1.0, green: 0.3, blue: 0.8, alpha: 1.0)),
        ColorScheme(name: "Aurora",
                    low: NSColor(red: 0.0, green: 0.9, blue: 0.5, alpha: 1.0),
                    high: NSColor(red: 0.4, green: 0.2, blue: 1.0, alpha: 1.0)),
        ColorScheme(name: "Lava",
                    low: NSColor(red: 0.5, green: 0.0, blue: 0.0, alpha: 1.0),
                    high: NSColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)),
        ColorScheme(name: "Ocean",
                    low: NSColor(red: 0.0, green: 0.2, blue: 0.5, alpha: 1.0),
                    high: NSColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1.0)),
        ColorScheme(name: "Neon",
                    low: NSColor(red: 0.1, green: 1.0, blue: 0.1, alpha: 1.0),
                    high: NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)),
        ColorScheme(name: "Grayscale",
                    low: NSColor(white: 0.35, alpha: 1.0),
                    high: NSColor(white: 1.0, alpha: 1.0)),

        // Metallic gradients: darker shade of the metal for short bars, bright sheen for tall bars.
        ColorScheme(name: "Gold",
                    low: NSColor(red: 0.45, green: 0.32, blue: 0.05, alpha: 1.0),
                    high: NSColor(red: 1.0, green: 0.86, blue: 0.35, alpha: 1.0)),
        ColorScheme(name: "Silver",
                    low: NSColor(red: 0.38, green: 0.40, blue: 0.44, alpha: 1.0),
                    high: NSColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1.0)),
        ColorScheme(name: "Copper",
                    low: NSColor(red: 0.33, green: 0.14, blue: 0.07, alpha: 1.0),
                    high: NSColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1.0)),
        ColorScheme(name: "Bronze",
                    low: NSColor(red: 0.28, green: 0.19, blue: 0.07, alpha: 1.0),
                    high: NSColor(red: 0.82, green: 0.62, blue: 0.32, alpha: 1.0)),
        ColorScheme(name: "Gunmetal",
                    low: NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0),
                    high: NSColor(red: 0.58, green: 0.66, blue: 0.74, alpha: 1.0)),
    ]

    /// Index of the preset matching the current gradient, or nil if the colors are custom.
    static var currentColorSchemeIndex: Int? {
        let low = lowGradientColor
        let high = highGradientColor
        return colorSchemes.firstIndex {
            colorsMatch($0.low, low) && colorsMatch($0.high, high)
        }
    }

    private static func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        let tol: CGFloat = 0.01
        return abs(x.redComponent - y.redComponent) < tol
            && abs(x.greenComponent - y.greenComponent) < tol
            && abs(x.blueComponent - y.blueComponent) < tol
    }

    // MARK: - Transparent Background

    /// Whether the (modern) Cava window draws a translucent background. **Off by default** — Cava
    /// is opaque and does not inherit the spectrum window's transparency. Modern only.
    static var transparentBackground: Bool {
        get { defaults.bool(forKey: transparentBackgroundKey) }
        set { defaults.set(newValue, forKey: transparentBackgroundKey) }
    }

    // MARK: - Skin-derived default colors

    /// True once the user has explicitly picked a color preset. Until then, Cava follows the
    /// active skin's palette (see `effectiveLowColor`/`effectiveHighColor`).
    static var hasCustomColors: Bool {
        get { defaults.bool(forKey: colorsCustomizedKey) }
        set { defaults.set(newValue, forKey: colorsCustomizedKey) }
    }

    /// Skin-derived default gradient, pushed by the (skin-aware) window views on show / skin change.
    /// In-memory only — recomputed from the skin each session; falls back to the blue→magenta pair.
    private static var _skinDefaultLow = NSColor(red: 0.0, green: 0.3, blue: 1.0, alpha: 1.0)
    private static var _skinDefaultHigh = NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)

    /// Set the skin-derived default gradient. Classic passes green; modern passes primary→accent.
    static func setSkinDefaultColors(low: NSColor, high: NSColor) {
        _skinDefaultLow = low
        _skinDefaultHigh = high
    }

    /// The colors actually drawn: the user's pick if customized, otherwise the skin default.
    static var effectiveLowColor: NSColor { hasCustomColors ? lowGradientColor : _skinDefaultLow }
    static var effectiveHighColor: NSColor { hasCustomColors ? highGradientColor : _skinDefaultHigh }

    /// Look up a preset by name (e.g. the classic "Winamp Green" default).
    static func scheme(named name: String) -> ColorScheme? {
        colorSchemes.first { $0.name == name }
    }

    /// Reset all settings to defaults.
    static func reset() {
        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: barCountKey)
        defaults.removeObject(forKey: lowGradientColorKey)
        defaults.removeObject(forKey: highGradientColorKey)
        defaults.removeObject(forKey: colorsCustomizedKey)
        defaults.removeObject(forKey: transparentBackgroundKey)
        defaults.removeObject(forKey: noiseReductionKey)
        defaults.removeObject(forKey: bassTiltKey)
    }
}
