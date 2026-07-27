import Foundation
import AppKit

/// Cava spectrum analyzer user preferences, persisted in UserDefaults.
/// Independent of Remember-State; these are durable preferences.
enum CavaSettings {
    private static let defaults = UserDefaults.standard

    enum Scope: CaseIterable {
        case cavaWindow
        case mainWindow

        var identifier: String {
            switch self {
            case .cavaWindow: return "window"
            case .mainWindow: return "mainWindow"
            }
        }
    }

    enum Mode: Int {
        case mono = 0
        case stereo = 1
    }

    private enum SettingKey: String, CaseIterable {
        case mode
        case barCount
        case lowGradientColor
        case highGradientColor
        case colorsCustomized
        case transparentBackground
        case noiseReduction
        case bassTilt
    }

    /// Preserve the standalone window's legacy keys while giving embedded Cava an independent
    /// namespace.
    private static func key(_ setting: SettingKey, for scope: Scope) -> String {
        switch scope {
        case .cavaWindow:
            switch setting {
            case .mode: return "cavaMode"
            case .barCount: return "cavaBarCount"
            case .lowGradientColor: return "cavaLowGradientColor"
            case .highGradientColor: return "cavaHighGradientColor"
            case .colorsCustomized: return "cavaColorsCustomized"
            case .transparentBackground: return "cavaTransparentBackground"
            case .noiseReduction: return "cavaNoiseReduction"
            case .bassTilt: return "cavaBassTilt"
            }
        case .mainWindow:
            return "cava.mainWindow.\(setting.rawValue)"
        }
    }

    /// Durable keys owned by a scope. Used by the centralized visualization reset path.
    static func preferenceKeys(for scope: Scope) -> [String] {
        SettingKey.allCases.compactMap { setting in
            if scope == .mainWindow && setting == .transparentBackground {
                return nil
            }
            return key(setting, for: scope)
        }
    }

    // Factory defaults for the exposed tuning knobs (the "Reset to Defaults" target).
    static let defaultBarCount = 32
    static let defaultNoiseReduction = 0.65   // smoothing / latency; lower = snappier
    static let defaultBassTilt = 0.3          // band bin-count exponent; higher = more bass

    /// Canonical menu presets shared by the standalone and embedded Cava controls.
    static func barCountPresets(for scope: Scope) -> [Int] {
        switch scope {
        case .cavaWindow:
            return [16, 24, 32, 48, 64]
        case .mainWindow:
            return [12, 19, 24, 32]
        }
    }

    static let smoothingPresets: [(name: String, value: Double)] = [
        ("Snappy", 0.50),
        ("Balanced", 0.65),
        ("Smooth", 0.80),
        ("Very Smooth", 0.90),
    ]

    static let bassTiltPresets: [(name: String, value: Double)] = [
        ("Less", 0.15),
        ("Balanced", 0.30),
        ("More", 0.50),
        ("Max", 0.70),
    ]

    // MARK: - Mode (Mono/Stereo)

    static func mode(for scope: Scope) -> Mode {
        // Stereo is unreadable in the 16px-tall embedded visualization area.
        guard scope != .mainWindow else { return .mono }
        let preferenceKey = key(.mode, for: scope)
        guard defaults.object(forKey: preferenceKey) != nil else { return .stereo }
        let raw = defaults.integer(forKey: preferenceKey)
        return Mode(rawValue: raw) ?? .stereo
    }

    static func setMode(_ mode: Mode, for scope: Scope) {
        defaults.set(mode.rawValue, forKey: key(.mode, for: scope))
    }

    static var mode: Mode {
        get { mode(for: .cavaWindow) }
        set { setMode(newValue, for: .cavaWindow) }
    }

    // MARK: - Bar Count

    static func barCount(for scope: Scope) -> Int {
        let count = defaults.integer(forKey: key(.barCount, for: scope))
        return count > 0 ? count : defaultBarCount
    }

    static func setBarCount(_ count: Int, for scope: Scope) {
        defaults.set(max(1, min(128, count)), forKey: key(.barCount, for: scope))
    }

    static var barCount: Int {
        get { barCount(for: .cavaWindow) }
        set { setBarCount(newValue, for: .cavaWindow) }
    }

    // MARK: - DSP Tuning

    /// Temporal smoothing (0…0.95). Higher = smoother but laggier; lower = snappier/more real-time.
    static func noiseReduction(for scope: Scope) -> Double {
        let preferenceKey = key(.noiseReduction, for: scope)
        guard defaults.object(forKey: preferenceKey) != nil else { return defaultNoiseReduction }
        return min(0.95, max(0.0, defaults.double(forKey: preferenceKey)))
    }

    static func setNoiseReduction(_ value: Double, for scope: Scope) {
        defaults.set(min(0.95, max(0.0, value)), forKey: key(.noiseReduction, for: scope))
    }

    static var noiseReduction: Double {
        get { noiseReduction(for: .cavaWindow) }
        set { setNoiseReduction(newValue, for: .cavaWindow) }
    }

    /// Bass↔treble tilt: the per-band bin-count exponent (0…1). 0 = brightest, 1 = bassiest.
    static func bassTilt(for scope: Scope) -> Double {
        let preferenceKey = key(.bassTilt, for: scope)
        guard defaults.object(forKey: preferenceKey) != nil else { return defaultBassTilt }
        return min(1.0, max(0.0, defaults.double(forKey: preferenceKey)))
    }

    static func setBassTilt(_ value: Double, for scope: Scope) {
        defaults.set(min(1.0, max(0.0, value)), forKey: key(.bassTilt, for: scope))
    }

    static var bassTilt: Double {
        get { bassTilt(for: .cavaWindow) }
        set { setBassTilt(newValue, for: .cavaWindow) }
    }

    /// Restore the exposed tuning knobs (bar count, smoothing, bass tilt) to factory defaults.
    /// Leaves mode / colors / transparency alone (those have their own controls).
    static func resetTuning(scope: Scope = .cavaWindow) {
        defaults.removeObject(forKey: key(.barCount, for: scope))
        defaults.removeObject(forKey: key(.noiseReduction, for: scope))
        defaults.removeObject(forKey: key(.bassTilt, for: scope))
    }

    // MARK: - Gradient Colors

    /// Low-frequency bar color (default: dark blue).
    static func lowGradientColor(for scope: Scope) -> NSColor {
        let data = defaults.data(forKey: key(.lowGradientColor, for: scope))
        if let data, let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return NSColor(red: 0.0, green: 0.3, blue: 1.0, alpha: 1.0)
    }

    static func setLowGradientColor(_ color: NSColor, for scope: Scope) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            defaults.set(data, forKey: key(.lowGradientColor, for: scope))
        }
    }

    static var lowGradientColor: NSColor {
        get { lowGradientColor(for: .cavaWindow) }
        set { setLowGradientColor(newValue, for: .cavaWindow) }
    }

    /// High-frequency bar color (default: bright magenta).
    static func highGradientColor(for scope: Scope) -> NSColor {
        let data = defaults.data(forKey: key(.highGradientColor, for: scope))
        if let data, let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
    }

    static func setHighGradientColor(_ color: NSColor, for scope: Scope) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            defaults.set(data, forKey: key(.highGradientColor, for: scope))
        }
    }

    static var highGradientColor: NSColor {
        get { highGradientColor(for: .cavaWindow) }
        set { setHighGradientColor(newValue, for: .cavaWindow) }
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
    static func currentColorSchemeIndex(for scope: Scope) -> Int? {
        let low = lowGradientColor(for: scope)
        let high = highGradientColor(for: scope)
        return colorSchemes.firstIndex {
            colorsMatch($0.low, low) && colorsMatch($0.high, high)
        }
    }

    static var currentColorSchemeIndex: Int? {
        currentColorSchemeIndex(for: .cavaWindow)
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
        get { defaults.bool(forKey: key(.transparentBackground, for: .cavaWindow)) }
        set { defaults.set(newValue, forKey: key(.transparentBackground, for: .cavaWindow)) }
    }

    // MARK: - Skin-derived default colors

    /// True once the user has explicitly picked a color preset. Until then, Cava follows the
    /// active skin's palette (see `effectiveLowColor`/`effectiveHighColor`).
    static func hasCustomColors(for scope: Scope) -> Bool {
        defaults.bool(forKey: key(.colorsCustomized, for: scope))
    }

    static func setHasCustomColors(_ customized: Bool, for scope: Scope) {
        defaults.set(customized, forKey: key(.colorsCustomized, for: scope))
    }

    static var hasCustomColors: Bool {
        get { hasCustomColors(for: .cavaWindow) }
        set { setHasCustomColors(newValue, for: .cavaWindow) }
    }

    /// Skin-derived default gradient, pushed by the (skin-aware) window views on show / skin change.
    /// In-memory only — recomputed from the skin each session; falls back to the blue→magenta pair.
    private static var skinDefaultLow: [Scope: NSColor] = [:]
    private static var skinDefaultHigh: [Scope: NSColor] = [:]

    /// Set the skin-derived default gradient. Classic passes green; modern passes primary→accent.
    static func setSkinDefaultColors(low: NSColor, high: NSColor, scope: Scope = .cavaWindow) {
        skinDefaultLow[scope] = low
        skinDefaultHigh[scope] = high
    }

    /// The colors actually drawn: the user's pick if customized, otherwise the skin default.
    static func effectiveLowColor(for scope: Scope) -> NSColor {
        if hasCustomColors(for: scope) {
            return lowGradientColor(for: scope)
        }
        return skinDefaultLow[scope] ?? NSColor(red: 0.0, green: 0.3, blue: 1.0, alpha: 1.0)
    }

    static func effectiveHighColor(for scope: Scope) -> NSColor {
        if hasCustomColors(for: scope) {
            return highGradientColor(for: scope)
        }
        return skinDefaultHigh[scope] ?? NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
    }

    static var effectiveLowColor: NSColor { effectiveLowColor(for: .cavaWindow) }
    static var effectiveHighColor: NSColor { effectiveHighColor(for: .cavaWindow) }

    /// Look up a preset by name (e.g. the classic "Winamp Green" default).
    static func scheme(named name: String) -> ColorScheme? {
        colorSchemes.first { $0.name == name }
    }

    /// Reset all settings to defaults.
    static func reset(scope: Scope = .cavaWindow) {
        for preferenceKey in preferenceKeys(for: scope) {
            defaults.removeObject(forKey: preferenceKey)
        }
    }
}
