import Foundation

/// What the compact window shows below its player bar, picked by the footer tabs. Shared by the
/// classic and modern compact surfaces so the choice survives a UI-family switch.
enum CompactContentMode: Int, CaseIterable {
    case library = 0, queue = 1, equalizer = 2, visualizations = 3

    var label: String {
        switch self {
        case .library: return "Library"
        case .queue: return "Playlist"
        case .equalizer: return "EQ"
        case .visualizations: return "Vis"
        }
    }

    static var persisted: CompactContentMode {
        get { CompactContentMode(rawValue: UserDefaults.standard.integer(forKey: "compactContentMode")) ?? .library }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "compactContentMode") }
    }

    /// The footer tabs: equal, whole-unit slices of a strip `width` wide, one per mode in
    /// `allCases` order, with x measured from the strip's left edge.
    static func tabs(width: CGFloat) -> [(mode: CompactContentMode, minX: CGFloat, width: CGFloat)] {
        let count = CGFloat(allCases.count)
        return allCases.enumerated().map { i, mode in
            let minX = (width * CGFloat(i) / count).rounded()
            let maxX = (width * CGFloat(i + 1) / count).rounded()
            return (mode, minX, maxX - minX)
        }
    }

    /// The tab under `x` (measured like `tabs(width:)`); anything left of the strip is the first
    /// tab and anything right of it the last, so the whole footer is clickable.
    static func tab(atX x: CGFloat, width: CGFloat) -> CompactContentMode {
        tabs(width: width).last { x >= $0.minX }?.mode ?? .library
    }
}
