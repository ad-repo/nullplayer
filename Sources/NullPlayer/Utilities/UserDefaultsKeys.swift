import Foundation

// =============================================================================
// USER DEFAULTS KEYS
// =============================================================================
// Centralized, strongly-typed keys for UserDefaults.
// =============================================================================

extension UserDefaults {
    enum Keys {
        // --- UI State ---
        static let modernUIEnabled = "modernUIEnabled"
        static let modernSkinName = "modernSkinName"
        static let lastClassicSkinPath = "lastClassicSkinPath"
        static let hideTitleBars = "hideTitleBars"
        static let isAlwaysOnTop = "isAlwaysOnTop"
        static let doubleSizeMode = "doubleSizeMode"

        // --- Audio Playback ---
        static let gaplessPlaybackEnabled = "gaplessPlaybackEnabled"
        static let volumeNormalizationEnabled = "volumeNormalizationEnabled"
        static let sweetFadeEnabled = "sweetFadeEnabled"
        static let sweetFadeDuration = "sweetFadeDuration"
        static let selectedOutputDeviceUID = "selectedOutputDeviceUID"

        // --- Radio ---
        static let radioAutoReconnect = "RadioAutoReconnect"
        
        // --- App State ---
        static let rememberStateEnabled = "rememberStateEnabled"
        static let savedAppState = "savedAppState"
        
        // --- Visualizations ---
        static let spectrumNormalizationMode = "spectrumNormalizationMode"
    }
}
