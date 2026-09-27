import Foundation

/// WMP-owned visualization settings, remembered per installed skin.
///
/// **A `.wmz`'s `<EFFECTS>` rect is part of that skin's look, so the choices made in it belong to
/// that skin.** Picking MilkDrop with a preset in *Cerulean*, then switching to *Asimov Radio*,
/// must not carry Cerulean's effect into Asimov's frame — and coming back to Cerulean must show
/// what was left there. This is the same rule `WMPViewFrameStore` already applies to geometry:
/// what the user last decided for *this* skin wins.
///
/// **What is in scope is what WMP owns.** The selected effect and its preset (`WMPEffectSelection`)
/// plus every preference key already namespaced to the effects slot — Cava's `.wmpEffects` tuning
/// and vis_classic's `.wmpEffects` profile/fit/transparency. ProjectM, Geiss and Tripex cycle and
/// sensitivity settings are deliberately *not* here: those keys are shared with NullPlayer's own
/// Visualizations window and the `.wal` surface, so a cycle set in one place is the cycle in all of
/// them, and scoping them per skin would silently rewrite the standalone window's settings on every
/// skin switch.
///
/// A skin with no record restores the app's own defaults rather than inheriting the previous skin's
/// settings, which is what makes the scoping per skin rather than merely last-write-wins.
struct WMPVisualizationSettingsStore {
    private static let defaultsKey = "wmpVisualizationSettings"
    private static let effectField = "effect"
    private static let presetField = "preset"
    private static let defaultsField = "defaults"

    let defaults: UserDefaults

    /// The preference keys the effects slot owns. Both lists are asked of the subsystem that names
    /// them, so a key added to either scope is carried per skin without a change here.
    static var scopedKeys: [String] {
        let scope = VisClassicBridge.PreferenceScope.wmpEffects
        return CavaSettings.preferenceKeys(for: .wmpEffects)
            + [scope.lastProfileNameKey, scope.fitToWidthKey, scope.transparentBgKey, scope.opacityKey]
    }

    struct Selection: Equatable {
        var effect: String?
        var preset: Int
    }

    /// The record this skin would be saved as right now, built from the live selection and the live
    /// scoped keys. Callers compare it against what is stored to decide whether to write.
    func currentRecord(effect: String, preset: Int) -> [String: Any] {
        var scoped: [String: Any] = [:]
        for key in Self.scopedKeys {
            if let value = defaults.object(forKey: key) { scoped[key] = value }
        }
        return [Self.effectField: effect, Self.presetField: preset, Self.defaultsField: scoped]
    }

    func storedRecord(skin: String) -> [String: Any]? {
        defaults.dictionary(forKey: Self.defaultsKey)?[key(skin)] as? [String: Any]
    }

    /// Writes this skin's record, and only when something actually changed: an unconditional write
    /// would re-post `UserDefaults.didChangeNotification` and make the capture observer feed itself.
    @discardableResult
    func capture(skin: String, effect: String, preset: Int) -> Bool {
        let record = currentRecord(effect: effect, preset: preset)
        if let existing = storedRecord(skin: skin),
           NSDictionary(dictionary: existing).isEqual(to: record) { return false }
        var records = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        records[key(skin)] = record
        defaults.set(records, forKey: Self.defaultsKey)
        return true
    }

    /// Puts this skin's scoped preferences back in place and reports the selection it was left on.
    /// With no record, every scoped key is cleared so the skin starts from the app's own defaults.
    @discardableResult
    func restore(skin: String) -> Selection {
        let record = storedRecord(skin: skin)
        let scoped = record?[Self.defaultsField] as? [String: Any] ?? [:]
        for key in Self.scopedKeys {
            if let value = scoped[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        return Selection(effect: record?[Self.effectField] as? String,
                         preset: max(0, record?[Self.presetField] as? Int ?? 0))
    }

    func forget(skin: String) {
        guard var records = defaults.dictionary(forKey: Self.defaultsKey),
              records.removeValue(forKey: key(skin)) != nil else { return }
        defaults.set(records, forKey: Self.defaultsKey)
    }

    /// Length-prefixed like `WMPViewFrameStore`'s, so two skins whose names differ only by case or
    /// by a separator cannot collide.
    private func key(_ skin: String) -> String {
        "\(skin.utf8.count):\(skin.lowercased())"
    }
}
