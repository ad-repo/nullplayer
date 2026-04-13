import Foundation
import NullPlayerPlayback

final class DarwinPlaybackPreferences: PlaybackPreferencesProviding {
    private enum Keys {
        static let gaplessPlaybackEnabled = "gaplessPlaybackEnabled"
        static let volumeNormalizationEnabled = "volumeNormalizationEnabled"
        static let sweetFadeEnabled = "sweetFadeEnabled"
        static let sweetFadeDuration = "sweetFadeDuration"
        static let selectedOutputDevicePersistentID = "selectedOutputDevicePersistentID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var gaplessPlaybackEnabled: Bool {
        get { defaults.bool(forKey: Keys.gaplessPlaybackEnabled) }
        set { defaults.set(newValue, forKey: Keys.gaplessPlaybackEnabled) }
    }

    var volumeNormalizationEnabled: Bool {
        get { defaults.bool(forKey: Keys.volumeNormalizationEnabled) }
        set { defaults.set(newValue, forKey: Keys.volumeNormalizationEnabled) }
    }

    var sweetFadeEnabled: Bool {
        get { defaults.bool(forKey: Keys.sweetFadeEnabled) }
        set { defaults.set(newValue, forKey: Keys.sweetFadeEnabled) }
    }

    var sweetFadeDuration: TimeInterval {
        get {
            let saved = defaults.double(forKey: Keys.sweetFadeDuration)
            return saved > 0 ? saved : 5.0
        }
        set { defaults.set(max(0.1, newValue), forKey: Keys.sweetFadeDuration) }
    }

    var selectedOutputDevicePersistentID: String? {
        get { defaults.string(forKey: Keys.selectedOutputDevicePersistentID) }
        set { defaults.set(newValue, forKey: Keys.selectedOutputDevicePersistentID) }
    }
}
