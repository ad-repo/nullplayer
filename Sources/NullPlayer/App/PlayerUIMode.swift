import Foundation

enum PlayerUIMode: String, CaseIterable {
    case classic
    case modern
    case metal

    static let userDefaultsKey = "uiMode"
    private static let legacyModernEnabledKey = "modernUIEnabled"

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .modern: return "Modern"
        case .metal: return "Metal"
        }
    }

    var usesModernControllers: Bool {
        switch self {
        case .classic: return false
        case .modern, .metal: return true
        }
    }

    var modernSkinFamily: ModernSkinFamily? {
        switch self {
        case .classic: return nil
        case .modern: return .modern
        case .metal: return .metal
        }
    }

    static func stored(
        in defaults: UserDefaults = .standard,
        forcedMode: PlayerUIMode? = AppPersistence.forcedUIMode
    ) -> PlayerUIMode {
        if let forcedMode {
            return forcedMode
        }
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           let mode = PlayerUIMode(rawValue: rawValue) {
            return mode
        }
        return defaults.bool(forKey: legacyModernEnabledKey) ? .modern : .classic
    }

    func persist(
        in defaults: UserDefaults = .standard,
        forcedMode: PlayerUIMode? = AppPersistence.forcedUIMode
    ) {
        guard forcedMode == nil else { return }
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
        defaults.set(usesModernControllers, forKey: Self.legacyModernEnabledKey)
    }

    static func allowsAssignment(
        _ requestedMode: PlayerUIMode,
        forcedMode: PlayerUIMode? = AppPersistence.forcedUIMode
    ) -> Bool {
        forcedMode == nil || forcedMode == requestedMode
    }
}
