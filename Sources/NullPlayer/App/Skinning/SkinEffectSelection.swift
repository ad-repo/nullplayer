import AppKit

/// What a skin's effects surface (`SkinEffectsSurfaceView`) draws, and the one place that answer
/// lives — one instance per skin family that hosts the surface, so a choice in one family never
/// moves another's.
///
/// **A `.wmz` skin has already said where the choice lives.** 96 of the 179 corpus archives bind
/// `currentEffectType="wmpprop:mediacenter.effectType"` and `currentPreset="wmpprop:mediacenter.
/// effectPreset"` (172 and 144 uses), 82 call `visEffects.next()` and 74 `visEffects.previous()`,
/// and 51 wire an `onClick` on the rect itself to cycle. So the selector is a host property the
/// markup reads and writes — not a menu this engine invents, and not a fixed surface (W101).
///
/// **The catalogue is eight, and every one of them fills the authored rect (W140).** It used to be
/// five, because a full-frame renderer in the slot showed as a conspicuous black rectangle in
/// Asimov Radio and Cerulean. That was the occlusion defect (W139), not the engines: nothing a skin
/// drew could cover the surface, so *any* opaque renderer was a black rectangle there. With the
/// skin's own artwork compositing over the rect, ProjectM, Geiss and Tripex join the three compact
/// WMP-native effects, Cava and vis_classic — the three rendering offscreen and presented as an
/// image rather than mounted as a live `NSOpenGLView`.
///
/// This choice is independent of NullPlayer's standalone Visualizations window — a skin cycling
/// `visEffects` must never reconfigure the user's separate visualization engine. WMP's is
/// **remembered per skin**, not per session: `WMPVisualizationSettingsStore` saves it, and the
/// slot's Cava and vis_classic settings with it, against the installed skin that was showing.
@MainActor
final class SkinEffectSelection {
    /// A `.wmz` skin's `<EFFECTS>` rects.
    static let wmp = SkinEffectSelection(cavaScope: .wmpEffects, visClassicScope: .wmpEffects,
                                         waveformConsumerID: "wmp.effects.visclassic")
    /// The Sonique navigator's visual mode screen: one choice for the family, as Sonique had one
    /// visualizer, remembered across launches.
    static let sonique = SkinEffectSelection(cavaScope: .soniqueEffects, visClassicScope: .soniqueEffects,
                                             waveformConsumerID: "sonique.effects.visclassic",
                                             persistenceKey: "soniqueEffect")

    /// The family's own Cava and vis_classic settings, which its surfaces draw with, so a choice
    /// in one family's right-click menu never moves another's or the standalone windows'.
    let cavaScope: CavaSettings.Scope
    let visClassicScope: VisClassicBridge.PreferenceScope
    let waveformConsumerID: String
    /// Where the selection saves itself on every change (the effect id, and the preset under the
    /// key plus `Preset`); nil when its family remembers it elsewhere (WMP, per skin).
    private let persistenceKey: String?

    struct Effect {
        let id: String
        let title: String
        let style: NativeStyle

        /// The suite engine this effect runs, for the styles that are one. It is what the shared
        /// `VisualizationMenuTarget` menu acts on, and it is **never** written back to
        /// `visualizationEngineType`: that preference belongs to the standalone Visualizations
        /// window and the menu bar, and a skin cycling `visEffects` is not entitled to rewrite it.
        var engine: VisualizationType? {
            switch style {
            case .projectM: return .projectM
            case .geiss: return .geiss
            case .tripex: return .tripex
            case .bars, .spikes, .ambience, .cava, .visClassic: return nil
            }
        }

        /// A GL engine renders offscreen and is presented as a `CGImage`; the rest draw themselves
        /// straight into the surface's `draw(_:)`. Both fill the authored rect and the skin's own
        /// artwork is what shapes them.
        var isOffscreenEngine: Bool { engine != nil }
    }

    enum NativeStyle: String {
        case bars, spikes, ambience, cava, visClassic, projectM, geiss, tripex
    }

    /// Posted, with the selection as its object, when the selected effect or preset changes, so
    /// every surface on that selection follows one choice.
    static let didChange = Notification.Name("SkinEffectSelectionDidChange")

    /// **Eight effects, all rendering the same way in the rect** (W140). The first five are drawn
    /// by the surface itself; ProjectM, Geiss and Tripex render offscreen and are presented as an
    /// image. Spikes stays first because it is what a skin that selects nothing shows.
    static let catalogue: [Effect] = [
        Effect(id: "spikes", title: "Spikes", style: .spikes),
        Effect(id: "bars", title: "Bars", style: .bars),
        Effect(id: "ambience", title: "Ambience", style: .ambience),
        Effect(id: "cava", title: "Cava", style: .cava),
        Effect(id: "vis_classic", title: "vis_classic", style: .visClassic),
        Effect(id: "projectm", title: "projectM", style: .projectM),
        Effect(id: "geiss", title: "Geiss", style: .geiss),
        Effect(id: "tripex", title: "Tripex", style: .tripex)
    ]

    private(set) var index: Int
    private(set) var preset: Int = 0
    /// Written by the surface that applied the preset, because only the running engine knows what
    /// preset number that landed on. Never posts a change: it is a report, not a choice.
    var presetTitle: String = ""

    private init(cavaScope: CavaSettings.Scope, visClassicScope: VisClassicBridge.PreferenceScope,
                 waveformConsumerID: String, persistenceKey: String? = nil) {
        self.cavaScope = cavaScope
        self.visClassicScope = visClassicScope
        self.waveformConsumerID = waveformConsumerID
        self.persistenceKey = persistenceKey
        // The compact Spikes is a better first effect for the small, framed rectangles skins
        // author than borrowing the application's full-window visualization preference.
        index = 0
        presetTitle = ""
        if let persistenceKey {
            let defaults = UserDefaults.standard
            index = Self.index(of: defaults.string(forKey: persistenceKey)) ?? 0
            preset = max(0, defaults.integer(forKey: persistenceKey + "Preset"))
        }
    }

    /// The catalogue entry a skin or a saved choice names, by id or title, case-insensitively.
    private static func index(of name: String?) -> Int? {
        let wanted = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return catalogue.firstIndex { $0.id == wanted || $0.title.lowercased() == wanted }
    }

    var current: Effect { Self.catalogue[min(max(0, index), Self.catalogue.count - 1)] }

    /// Select by the id or the title the skin wrote, case-insensitively. An unknown name — every
    /// WMP visualizer name in the corpus is one — changes nothing, so the surface keeps drawing
    /// what it was drawing and the read-back stays honest.
    @discardableResult
    func select(_ name: String) -> Bool {
        guard let match = Self.index(of: name) else { return false }
        guard match != index else { return true }
        index = match
        preset = 0
        presetTitle = ""
        post()
        return true
    }

    /// Puts the rect back on what this skin was last left showing (`WMPVisualizationSettingsStore`).
    /// Unlike `select`, a missing or unknown id means *the default* rather than "change nothing":
    /// restoring a skin that has no record must not leave the previous skin's effect on screen.
    func restore(effect id: String?, preset value: Int) {
        index = Self.index(of: id) ?? 0
        preset = max(0, value)
        presetTitle = ""
        post()
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

    private func post() {
        if let persistenceKey {
            UserDefaults.standard.set(current.id, forKey: persistenceKey)
            UserDefaults.standard.set(preset, forKey: persistenceKey + "Preset")
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
