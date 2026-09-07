import Foundation

/// The controller family a `PlayerUIMode` is rendered by. This is the explicit, non-binary
/// replacement for the old "modern vs. classic" boolean: a mode is not merely "modern or not",
/// it belongs to exactly one of four independently-implemented families.
///
/// - `classic`: the original Winamp 2.x-style `MainWindowController` family.
/// - `nullPlayerModern`: NullPlayer's own modern controllers (`Modern*WindowController`),
///   used by both `.modern` and `.metal` (they differ only in skin family, not controllers).
/// - `winampModern`: the Winamp 5.x `.wal` (Wasabi XML + MAKI) family. Distinct from the other
///   two — it is neither "classic" nor "NullPlayer modern". Callers must route controller,
///   geometry, and auxiliary-window decisions through this enum, never through a boolean that
///   would silently fold `winampModern` into one of the other families.
/// - `wmp`: the Windows Media Player `.wmz`/`.wms` family.
enum PlayerUIControllerFamily {
    case classic
    case nullPlayerModern
    case winampModern
    case wmp
}

enum PlayerUIMode: String, CaseIterable {
    case classic
    case modern
    case metal
    case winampModern
    case wmp

    static let userDefaultsKey = "uiMode"
    private static let legacyModernEnabledKey = "modernUIEnabled"

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .modern: return ModernSkinFamily.modern.displayName
        case .metal: return ModernSkinFamily.metal.displayName
        case .winampModern: return "Modern"
        case .wmp: return "Windows Media Player"
        }
    }

    /// The controller family that renders this mode. The single source of truth for
    /// classic vs. NullPlayer-modern vs. Winamp-modern vs. WMP routing.
    var controllerFamily: PlayerUIControllerFamily {
        switch self {
        case .classic: return .classic
        case .modern, .metal: return .nullPlayerModern
        case .winampModern: return .winampModern
        case .wmp: return .wmp
        }
    }

    /// Whether this mode uses NullPlayer's own modern controllers (`Modern*WindowController`).
    ///
    /// This is intentionally narrow: it is true **only** for the `nullPlayerModern` family, NOT
    /// for `winampModern` or `wmp`. Each of those is a separate family that selects its own
    /// window controllers, so folding them in here would pick the wrong window family. Callers
    /// that need multi-way behavior must switch on `controllerFamily`.
    var usesModernControllers: Bool {
        controllerFamily == .nullPlayerModern
    }

    /// Whether this mode uses the 21-band EQ layout.
    ///
    /// This matches the NullPlayer modern controller family, but remains a distinct policy
    /// because other families may use custom controllers with a different EQ. `winampModern`
    /// deliberately uses the **classic 10-band** layout (cPro-Bento embeds a classic-10 EQ), so
    /// it returns `false` here even though it is a "modern" skin system.
    var usesModernEQLayout: Bool {
        switch self {
        case .classic, .winampModern, .wmp: return false
        case .modern, .metal: return true
        }
    }

    var modernSkinFamily: ModernSkinFamily? {
        switch self {
        case .classic, .winampModern, .wmp: return nil
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
