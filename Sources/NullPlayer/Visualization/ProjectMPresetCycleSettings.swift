import Foundation

enum VisualizationCycleMode: String {
    case off
    case cycle
    case random
}

enum ProjectMPresetCycleSettings {
    enum DefaultsKey {
        static let cycleMode = "projectM.cycleMode"
        static let cycleInterval = "projectM.cycleInterval"
    }

    static let defaultMode: VisualizationCycleMode = .off
    static let defaultInterval: TimeInterval = 30.0

    static func loadMode(defaults: UserDefaults = .standard) -> VisualizationCycleMode {
        guard let raw = defaults.string(forKey: DefaultsKey.cycleMode),
              let mode = VisualizationCycleMode(rawValue: raw) else {
            return defaultMode
        }
        return mode
    }

    static func loadInterval(defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.double(forKey: DefaultsKey.cycleInterval)
        return stored > 0 ? stored : defaultInterval
    }

    static func save(
        mode: VisualizationCycleMode,
        interval: TimeInterval,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: DefaultsKey.cycleMode)
        defaults.set(interval, forKey: DefaultsKey.cycleInterval)
    }
}
