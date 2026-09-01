import Foundation

enum PlayerUIControllerFamily: String, CaseIterable {
    case classic
    case nullPlayerModern
    case wmp
}

enum PlayerUIMode: String, CaseIterable {
    case classic
    case modern
    case metal
    case wmp

    static let userDefaultsKey = "uiMode"
    private static let legacyModernEnabledKey = "modernUIEnabled"

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .modern: return ModernSkinFamily.modern.displayName
        case .metal: return ModernSkinFamily.metal.displayName
        case .wmp: return "Windows Media Player"
        }
    }

    var controllerFamily: PlayerUIControllerFamily {
        switch self {
        case .classic: return .classic
        case .modern, .metal: return .nullPlayerModern
        case .wmp: return .wmp
        }
    }

    var usesModernControllers: Bool {
        switch self {
        case .classic, .wmp: return false
        case .modern, .metal: return true
        }
    }

    /// Whether this mode uses the 21-band EQ layout.
    ///
    /// This matches the controller family in NullPlayer, but remains a distinct policy
    /// because downstream modes may use custom controllers while retaining the modern EQ.
    var usesModernEQLayout: Bool {
        controllerFamily == .nullPlayerModern
    }

    var modernSkinFamily: ModernSkinFamily? {
        switch self {
        case .classic, .wmp: return nil
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
        // Preserve users upgrading from releases that stored only this Boolean. A genuinely fresh
        // profile has neither key and starts in WMP's app-authored unskinned player.
        if defaults.object(forKey: legacyModernEnabledKey) != nil {
            return defaults.bool(forKey: legacyModernEnabledKey) ? .modern : .classic
        }
        return .wmp
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

    /// Diagnostic GUI launch override supplied by `-uiMode <mode>` in NSArgumentDomain.
    /// This remains available in release builds so packaged WMP failures can be reproduced.
    static var argumentOverride: PlayerUIMode? {
        return argumentOverride(
            from: UserDefaults.standard.volatileDomain(forName: "NSArgumentDomain"))
    }

    static func argumentOverride(from arguments: [String: Any]) -> PlayerUIMode? {
        guard let rawValue = arguments[userDefaultsKey] as? String,
              let mode = PlayerUIMode(rawValue: rawValue),
              mode != .wmp || AppCapabilities.supports(.wmpSkinMode) else { return nil }
        return mode
    }
}
