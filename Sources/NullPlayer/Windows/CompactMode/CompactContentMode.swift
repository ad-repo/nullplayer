import Foundation

/// What the compact window shows below its player bar, picked by the footer tabs: one tab per
/// Original sub-window, in the Windows menu's order. Raw values are persisted, so new cases go on
/// the end of the numbering whatever their position, and a retired one's number is never reused
/// (5 Cava, 10 Play History and 12 Flow were tabs once).
enum CompactContentMode: Int, CaseIterable {
    case library = 0, queue = 1, equalizer = 2, visualizations = 3, spectrum = 4,
         waveform = 6, art = 7, peppyMeter = 8, audioAnalysis = 9, sonos = 11

    /// The Windows menu's name for the tab's window; the glyph's tooltip.
    var label: String {
        switch self {
        case .library: return "Library Browser"
        case .queue: return "Playlist Editor"
        case .equalizer: return "Equalizer"
        case .visualizations: return "Visualizations"
        case .spectrum: return "Spectrum Analyzer"
        case .waveform: return "Waveform"
        case .art: return "Art"
        case .peppyMeter: return "PeppyMeter"
        case .audioAnalysis: return "Audio Analyzer"
        case .sonos: return "Sonos Rooms"
        }
    }

    /// The SF Symbol the tab is drawn with.
    var glyph: String {
        switch self {
        case .library: return "books.vertical"
        case .queue: return "list.bullet"
        case .equalizer: return "slider.vertical.3"
        case .visualizations: return "sparkles"
        case .spectrum: return "chart.bar.xaxis"
        case .waveform: return "waveform"
        case .art: return "photo"
        case .peppyMeter: return "gauge.with.needle"
        case .audioAnalysis: return "waveform.badge.magnifyingglass"
        case .sonos: return "hifispeaker.2"
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
