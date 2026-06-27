import Foundation

enum ModernSkinFamily {
    case modern
    case metal

    var skinNameKey: String {
        switch self {
        case .modern: return "modernSkinName"
        case .metal: return "metalSkinName"
        }
    }

    var defaultSkinName: String {
        switch self {
        case .modern: return "NeonWave"
        case .metal: return "Brushed Steel"
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
