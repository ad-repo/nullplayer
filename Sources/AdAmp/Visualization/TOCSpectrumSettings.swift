import Foundation

/// Settings manager for TOC Spectrum visualization
///
/// Provides centralized access to user preferences for the TOC Spectrum renderer.
/// All settings are persisted to UserDefaults.
class TOCSpectrumSettings {

    // MARK: - UserDefaults Keys

    private static let colorSchemeKey = "tocSpectrumColorScheme"
    private static let barCountKey = "tocSpectrumBarCount"
    private static let scaleModeKey = "tocSpectrumScaleMode"
    private static let smoothingKey = "tocSpectrumSmoothing"
    private static let reflectionKey = "tocSpectrumReflection"
    private static let wireframeKey = "tocSpectrumWireframe"
    private static let visualizationModeKey = "tocSpectrumVisualizationMode"

    // MARK: - Shared Instance

    static let shared = TOCSpectrumSettings()

    private init() {}

    // MARK: - Settings Properties

    /// Color scheme for the visualization
    var colorScheme: TOCSpectrumRenderer.ColorScheme {
        get {
            if let str = UserDefaults.standard.string(forKey: Self.colorSchemeKey),
               let scheme = TOCSpectrumRenderer.ColorScheme(rawValue: str) {
                return scheme
            }
            return .classic  // Default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.colorSchemeKey)
            postSettingsChangedNotification()
        }
    }

    /// Number of spectrum bars to display
    var barCount: Int {
        get {
            let count = UserDefaults.standard.integer(forKey: Self.barCountKey)
            return count > 0 ? count : 128  // Default
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.barCountKey)
            postSettingsChangedNotification()
        }
    }

    /// Frequency scale mode
    var scaleMode: TOCSpectrumRenderer.ScaleMode {
        get {
            if let str = UserDefaults.standard.string(forKey: Self.scaleModeKey),
               let mode = TOCSpectrumRenderer.ScaleMode(rawValue: str) {
                return mode
            }
            return .logarithmic  // Default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.scaleModeKey)
            postSettingsChangedNotification()
        }
    }

    /// Smoothing factor (0.0 - 1.0)
    var smoothing: Float {
        get {
            if UserDefaults.standard.object(forKey: Self.smoothingKey) != nil {
                return UserDefaults.standard.float(forKey: Self.smoothingKey)
            }
            return 0.75  // Default
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.smoothingKey)
            postSettingsChangedNotification()
        }
    }

    /// Whether reflection is enabled
    var reflectionEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.reflectionKey) != nil {
                return UserDefaults.standard.bool(forKey: Self.reflectionKey)
            }
            return false  // Default
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.reflectionKey)
            postSettingsChangedNotification()
        }
    }

    /// Whether wireframe mode is enabled
    var wireframeMode: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Self.wireframeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.wireframeKey)
            postSettingsChangedNotification()
        }
    }

    /// Visualization mode
    var visualizationMode: TOCSpectrumRenderer.VisualizationMode {
        get {
            if let str = UserDefaults.standard.string(forKey: Self.visualizationModeKey),
               let mode = TOCSpectrumRenderer.VisualizationMode(rawValue: str) {
                return mode
            }
            return .circularLayers  // Default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.visualizationModeKey)
            postSettingsChangedNotification()
        }
    }

    // MARK: - Reset to Defaults

    /// Reset all settings to their default values
    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.colorSchemeKey)
        UserDefaults.standard.removeObject(forKey: Self.barCountKey)
        UserDefaults.standard.removeObject(forKey: Self.scaleModeKey)
        UserDefaults.standard.removeObject(forKey: Self.smoothingKey)
        UserDefaults.standard.removeObject(forKey: Self.reflectionKey)
        UserDefaults.standard.removeObject(forKey: Self.wireframeKey)
        UserDefaults.standard.removeObject(forKey: Self.visualizationModeKey)

        postSettingsChangedNotification()
    }

    // MARK: - Notifications

    /// Notification posted when settings change
    static let settingsChangedNotification = Notification.Name("TOCSpectrumSettingsChanged")

    private func postSettingsChangedNotification() {
        NotificationCenter.default.post(name: Self.settingsChangedNotification, object: self)
    }

    // MARK: - Convenience Methods

    /// Available bar count options
    static let availableBarCounts = [64, 128, 256]

    /// Available color schemes
    static let availableColorSchemes = TOCSpectrumRenderer.ColorScheme.allCases

    /// Available scale modes
    static let availableScaleModes: [TOCSpectrumRenderer.ScaleMode] = [.linear, .logarithmic]

    /// Available visualization modes
    static let availableVisualizationModes = TOCSpectrumRenderer.VisualizationMode.allCases
}
