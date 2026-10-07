import Foundation

enum ModernSkinFamily {
    case modern
    case metal

    /// User-facing family name. Internal identifiers retain their original values so
    /// existing preferences and on-disk skin directories remain compatible.
    var displayName: String {
        switch self {
        case .modern: return "Original"
        case .metal: return "Original-Metal"
        }
    }

    var skinNameKey: String {
        switch self {
        case .modern: return "modernSkinName"
        case .metal: return "metalSkinName"
        }
    }

    var defaultSkinName: String {
        switch self {
        case .modern: return "NullPlayer-Orange"
        case .metal: return "Brushed Steel"
        }
    }

    /// The UI mode that shows this family — the inverse of `PlayerUIMode.modernSkinFamily`.
    var playerUIMode: PlayerUIMode {
        switch self {
        case .modern: return .modern
        case .metal: return .metal
        }
    }

    /// The edition capability that gates this family.
    var appFeature: AppFeature {
        switch self {
        case .modern: return .modernMode
        case .metal: return .metalMode
        }
    }

    var renderStyle: ModernRenderStyle {
        switch self {
        case .modern: return .standard
        case .metal: return .metal
        }
    }
}

enum ModernRenderStyle {
    case standard
    case metal
}
