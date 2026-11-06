import AppKit

/// **The standard visualization keys**, the same in every window that shows one — each skin
/// family's main window, the visualization windows, the Spectrum analyzer and Art:
/// ⌘↓ / ⌘↑ step the engine (a main window's mode, Art's effect group), ⌘→ / ⌘← step the preset
/// inside it (an effect, a profile, a style). ⇧ added is a hard cut where an engine blends.
/// Plain arrows stay each window's own: seek and volume on a main window.
enum VisualizationKey {
    case engine(Int)
    case preset(Int)

    /// The key `event` is, or nil for any key that is not a ⌘-arrow.
    init?(_ event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return nil }
        switch event.keyCode {
        case 125: self = .engine(1)   // ⌘↓
        case 126: self = .engine(-1)  // ⌘↑
        case 124: self = .preset(1)   // ⌘→
        case 123: self = .preset(-1)  // ⌘←
        default: return nil
        }
    }
}

extension Array where Element: Equatable {
    /// The element `delta` places from `current`, wrapping at both ends; from the first element
    /// when `current` is not in the list.
    func stepping(from current: Element, by delta: Int) -> Element {
        let index = firstIndex(of: current) ?? 0
        return self[((index + delta) % count + count) % count]
    }
}

extension VisualizationType {
    /// The engine `delta` places along the Visualization Engine menu's order.
    func advanced(by delta: Int) -> VisualizationType { Array(Self.allCases).stepping(from: self, by: delta) }
}

extension MainWindowVisMode {
    /// The mode `delta` places along the double-click order, skipping a mode whose shader is
    /// missing. Off, which that order leaves out, steps to Classic.
    func advanced(by delta: Int) -> MainWindowVisMode {
        let modes = Self.visualizationOrder.filter {
            $0 == self || $0.spectrumQualityMode.map(SpectrumAnalyzerView.isShaderAvailable(for:)) ?? true
        }
        guard modes.contains(self) else { return .spectrum }
        return modes.stepping(from: self, by: delta)
    }
}

extension SpectrumQualityMode {
    /// The Spectrum window's mode `delta` places along its double-click order, skipping a mode whose
    /// shader is missing.
    func advanced(by delta: Int) -> SpectrumQualityMode {
        Self.visualizationOrder
            .filter { $0 == self || SpectrumAnalyzerView.isShaderAvailable(for: $0) }
            .stepping(from: self, by: delta)
    }
}

/// ⌘← / ⌘→ on a Classic or Original main window: the current mode's own list — Fire's flame style,
/// Lightning's style, Matrix's colour, EKG's style, Cava's colour preset, stored in the keys the
/// mode's right-click menu writes, and vis_classic's profile, which lives in the window's overlay.
@MainActor
enum MainWindowVisStyle {
    /// Steps the mode's list, or answers false for a mode that has none.
    static func step(_ mode: MainWindowVisMode, by delta: Int, overlay: SpectrumAnalyzerView?) -> Bool {
        switch mode {
        case .visClassicExact:
            guard let overlay else { return false }
            return delta > 0 ? overlay.loadNextVisClassicProfile() : overlay.loadPreviousVisClassicProfile()
        case .fire: step(FlameStyle.self, key: "mainWindowFlameStyle", fallback: .inferno, by: delta)
        case .electricity: step(LightningStyle.self, key: "mainWindowLightningStyle", fallback: .classic, by: delta)
        case .matrix: step(MatrixColorScheme.self, key: "mainWindowMatrixColorScheme", fallback: .classic, by: delta)
        case .ekg: step(EKGStyle.self, key: "mainWindowEKGStyle", fallback: .clinical, by: delta)
        case .cava: CavaSettings.stepColorScheme(by: delta, for: .mainWindow)
        default:
            return false
        }
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
        return true
    }

    private static func step<Style: RawRepresentable & CaseIterable & Equatable>(
        _: Style.Type, key: String, fallback: Style, by delta: Int
    ) where Style.RawValue == String {
        let current = UserDefaults.standard.string(forKey: key).flatMap(Style.init(rawValue:)) ?? fallback
        UserDefaults.standard.set(Array(Style.allCases).stepping(from: current, by: delta).rawValue, forKey: key)
    }
}
