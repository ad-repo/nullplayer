import AppKit

/// What a skin's `<EFFECTS>` rect draws, and the one place that answer lives.
///
/// **The skin has already said where the choice lives.** 96 of the 179 corpus archives bind
/// `currentEffectType="wmpprop:mediacenter.effectType"` and `currentPreset="wmpprop:mediacenter.
/// effectPreset"` (172 and 144 uses), 82 call `visEffects.next()` and 74 `visEffects.previous()`,
/// and 51 wire an `onClick` on the rect itself to cycle. So the selector is a host property the
/// markup reads and writes — not a menu this engine invents, and not a fixed surface (W101).
///
/// The catalogue is deliberately WMP-native. `<EFFECTS>` is an in-skin display slot, not a tiny
/// ProjectM window: a skin such as Asimov Radio or Cerulean has composed its frame around the old
/// WMP effects plug-in, and a modern full-frame renderer turns that carefully placed slot into a
/// conspicuous black rectangle. These compact renderers — including Cava and vis_classic — are
/// drawn by the WMP surface itself and preserve that contract.
///
/// This is a session choice, independent of NullPlayer's standalone Visualizations window. A skin
/// cycling `visEffects` must never reconfigure the user's separate visualization engine.
@MainActor
final class WMPEffectSelection {
    static let shared = WMPEffectSelection()

    struct Effect {
        let id: String
        let title: String
        let style: NativeStyle

        /// Kept as an explicit seam for the shared menu-target protocol. WMP effects never vend a
        /// standalone renderer into the skin's slot.
        var engine: VisualizationType? { nil }
    }

    enum NativeStyle: String {
        case bars, spikes, ambience, cava, visClassic
    }

    /// Posted when the selected effect or preset changes, so every hosted surface follows one
    /// choice. A WMP session has one skin and one window; the surfaces in it are the observers.
    static let didChange = Notification.Name("WMPEffectSelectionDidChange")

    static let catalogue: [Effect] = [
        Effect(id: "spikes", title: "Spikes", style: .spikes),
        Effect(id: "bars", title: "Bars", style: .bars),
        Effect(id: "ambience", title: "Ambience", style: .ambience),
        Effect(id: "cava", title: "Cava", style: .cava),
        Effect(id: "vis_classic", title: "vis_classic", style: .visClassic)
    ]

    private(set) var index: Int
    private(set) var preset: Int = 0
    /// Written by the surface that applied the preset, because only the running engine knows what
    /// preset number that landed on. Never posts a change: it is a report, not a choice.
    var presetTitle: String = ""

    private init() {
        // WMP's compact Spikes is a better first effect for the tiny, framed rectangles these
        // skins author than borrowing the application's full-window visualization preference.
        index = 0
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
