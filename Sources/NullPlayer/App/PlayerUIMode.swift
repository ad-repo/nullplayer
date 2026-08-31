import Foundation

enum PlayerUIMode: String, CaseIterable {
    case classic
    case modern
    case metal
    case reeltone

    static let userDefaultsKey = "uiMode"
    private static let legacyModernEnabledKey = "modernUIEnabled"

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .modern: return ModernSkinFamily.modern.displayName
        case .metal: return ModernSkinFamily.metal.displayName
        case .reeltone: return "Reeltone"
        }
    }

    var usesModernControllers: Bool {
        switch self {
        case .classic: return false
        case .modern, .metal, .reeltone: return true
        }
    }

    /// Whether this mode uses the 21-band EQ layout.
    ///
    /// This matches the controller family in NullPlayer, but remains a distinct policy
    /// because downstream modes may use custom controllers while retaining the modern EQ.
    var usesModernEQLayout: Bool {
        switch self {
        case .classic: return false
        case .modern, .metal, .reeltone: return true
        }
    }

    /// Whether the main window is owned by the Reeltone surface subsystem.
    /// Auxiliary windows continue to use Original controllers until a skin declares
    /// its own hosted surface for them in a later implementation phase.
    var usesReeltoneSurfaces: Bool {
        self == .reeltone
    }

    /// Reeltone surfaces intentionally remain a regular-window-only UI.
    var supportsCompactSurfaces: Bool {
        self != .reeltone
    }

    var modernSkinFamily: ModernSkinFamily? {
        switch self {
        case .classic, .reeltone: return nil
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
