import AppKit

/// What a skin's `<EFFECTS>` rect draws, and the one place that answer lives.
///
/// **The skin has already said where the choice lives.** 96 of the 179 corpus archives bind
/// `currentEffectType="wmpprop:mediacenter.effectType"` and `currentPreset="wmpprop:mediacenter.
/// effectPreset"` (172 and 144 uses), 82 call `visEffects.next()` and 74 `visEffects.previous()`,
/// and 51 wire an `onClick` on the rect itself to cycle. So the selector is a host property the
/// markup reads and writes — not a menu this engine invents, and not a fixed surface (W101).
///
/// The catalogue is what this player can actually draw in a rect: the WMP-style bars this engine
/// already had, plus the three engines NullPlayer's own visualization window runs. A skin's own
/// authored type — `spikes`, `ambience`, `random` — names a WMP visualizer that does not exist
/// here, so it selects nothing and a read answers what is really on screen.
///
/// **The session's choice, not the app's preference.** It opens on whatever engine the
/// Visualizations menu is set to, so a skin shows what NullPlayer's own window would have shown,
/// but a skin cycling its effect does *not* write `visualizationEngineType` back: a `.wmz` startup
/// script that calls `next()` would otherwise silently reconfigure the user's visualization window.
@MainActor
final class WMPEffectSelection {
    static let shared = WMPEffectSelection()

    struct Effect {
        let id: String
        let title: String
        /// nil for the bars surface this engine draws itself.
        let engine: VisualizationType?
    }

    /// Posted when the selected effect or preset changes, so every hosted surface follows one
    /// choice. A WMP session has one skin and one window; the surfaces in it are the observers.
    static let didChange = Notification.Name("WMPEffectSelectionDidChange")

    static let catalogue: [Effect] = [
        Effect(id: "bars", title: "Bars", engine: nil),
        Effect(id: "projectm", title: "ProjectM", engine: .projectM),
        Effect(id: "geiss", title: "Geiss", engine: .geiss),
        Effect(id: "tripex", title: "Tripex", engine: .tripex)
    ]

    private(set) var index: Int
    private(set) var preset: Int = 0
    /// Written by the surface that applied the preset, because only the running engine knows what
    /// preset number that landed on. Never posts a change: it is a report, not a choice.
    var presetTitle: String = ""

    private init() {
        let engine = WindowManager.shared.visualizationEngineType
        index = Self.catalogue.firstIndex { $0.engine == engine } ?? 0
        presetTitle = ""
    }

    var current: Effect { Self.catalogue[min(max(0, index), Self.catalogue.count - 1)] }

    /// Select by the id or the title the skin wrote, case-insensitively. An unknown name — every
    /// WMP visualizer name in the corpus is one — changes nothing, so the surface keeps drawing
    /// what it was drawing and the read-back stays honest.
    @discardableResult
    func select(_ name: String) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = Self.catalogue.firstIndex(where: {
            $0.id == wanted || $0.title.lowercased() == wanted
        }) else { return false }
        guard match != index else { return true }
        index = match
        preset = 0
        presetTitle = ""
        post()
        return true
    }

    func step(by delta: Int) {
        let count = Self.catalogue.count
        index = ((index + delta) % count + count) % count
        preset = 0
        presetTitle = ""
        post()
    }

    func setPreset(_ value: Int) {
        let wanted = max(0, value)
        guard wanted != preset else { return }
        preset = wanted
        post()
    }

    func stepPreset(by delta: Int) { setPreset(max(0, preset + delta)) }

    private func post() { NotificationCenter.default.post(name: Self.didChange, object: self) }

    var snapshot: WMPEffectsSnapshot {
        WMPEffectsSnapshot(type: current.id, title: current.title,
                           preset: preset, presetTitle: presetTitle)
    }
}
