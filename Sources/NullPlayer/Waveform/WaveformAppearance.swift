import AppKit

extension Notification.Name {
    static let waveformAppearanceDidChange = Notification.Name("waveformAppearanceDidChange")
}

enum WaveformBackgroundMode: Equatable {
    case opaque
    case glass
    case clear
}

enum WaveformTransparentBackgroundStyle: String, Codable {
    case glass
    case clear
}

enum WaveformAppearancePreferences {
    static let transparentBackgroundKey = "waveformTransparentBackground"

    private static let bundledGlassSkinNames: Set<String> = [
        "SmoothGlass",
        "SeaGlass",
        "BloodGlass"
    ]

    static func transparentBackgroundEnabled(
        defaults: UserDefaults = .standard,
        isRunningModernUI: Bool,
        modernSkinName: String?
    ) -> Bool {
        guard isRunningModernUI else { return false }

        if let override = defaults.object(forKey: transparentBackgroundKey) as? NSNumber {
            return override.boolValue
        }

        guard let modernSkinName else {
            return false
        }

        return bundledGlassSkinNames.contains(modernSkinName)
    }

    static func setTransparentBackgroundEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: transparentBackgroundKey)
        NotificationCenter.default.post(name: .waveformAppearanceDidChange, object: nil)
    }
}

