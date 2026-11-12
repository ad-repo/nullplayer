import Foundation

enum VisualizationCycleMode: String {
    case off
    case cycle
    case random

    /// The C key's order: Manual Only → Auto-Cycle → Auto-Random → Manual Only.
    var next: VisualizationCycleMode {
        switch self {
        case .off: return .cycle
        case .cycle: return .random
        case .random: return .off
        }
    }
}

/// Each engine's auto-cycle choice, remembered per engine (`<engine>.cycleMode` /
/// `<engine>.cycleInterval`) and shared by every host that shows that engine.
/// `VisualizationPresetCycler` is what acts on it.
enum VisualizationCycleSettings {
    static let intervals: [TimeInterval] = [5, 10, 20, 30, 60, 120]
    static let defaultInterval: TimeInterval = 30

    /// Geiss, Goom, Corona (its palettes), Smear (its move scripts) and Tripex used to change
    /// effects by themselves, so they start out cycling.
    static func defaultMode(for engine: VisualizationType) -> VisualizationCycleMode {
        switch engine {
        case .projectM, .avs: return .off
        case .tripex: return .cycle
        case .geiss, .goom, .corona, .smear: return .random
        }
    }

    static func modeKey(for engine: VisualizationType) -> String { "\(prefix(for: engine)).cycleMode" }
    static func intervalKey(for engine: VisualizationType) -> String { "\(prefix(for: engine)).cycleInterval" }

    /// Cleared by the Visualizations window's preference reset.
    static var preferenceKeys: [String] {
        VisualizationType.allCases.flatMap { [modeKey(for: $0), intervalKey(for: $0)] }
    }

    static func mode(for engine: VisualizationType, defaults: UserDefaults = .standard) -> VisualizationCycleMode {
        defaults.string(forKey: modeKey(for: engine)).flatMap(VisualizationCycleMode.init) ?? defaultMode(for: engine)
    }

    static func interval(for engine: VisualizationType, defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.double(forKey: intervalKey(for: engine))
        return stored > 0 ? stored : defaultInterval
    }

    static func save(mode: VisualizationCycleMode, for engine: VisualizationType, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: modeKey(for: engine))
    }

    static func save(interval: TimeInterval, for engine: VisualizationType, defaults: UserDefaults = .standard) {
        defaults.set(interval, forKey: intervalKey(for: engine))
    }

    /// The keys predate this type; ProjectM's, Tripex's and AVS's keep their old names.
    private static func prefix(for engine: VisualizationType) -> String {
        switch engine {
        case .projectM: return "projectM"
        case .geiss: return "geiss"
        case .tripex: return "tripex"
        case .avs: return "avs"
        case .goom: return "goom"
        case .corona: return "corona"
        case .smear: return "smear"
        }
    }
}
