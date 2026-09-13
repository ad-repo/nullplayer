import Foundation

/// Host state a skin declares in its **markup**, as opposed to state its script writes.
///
/// Two members today. The first is the whole equaliser. `<EQUALIZERSETTINGS>` is not a control — the
/// scene builder skips it (`WMPSceneBuilder.isNonLayout`) because 163 skins author it with no
/// geometry — so nothing read its attributes at all, and `enable` is the attribute that turns
/// WMP's equaliser on. Measured over the 177 readable archives on 2026-09-09: **146 of the 155
/// skins that bind a band slider to `wmpprop:eq.gainLevelN` author
/// `<equalizerSettings id="eq" enable="true">` (or the `enabled` spelling), and not one archive
/// anywhere in the corpus authors `"false"`.** Only `gnome` ever writes `eq.enabled` from script.
/// So without this the engine's equaliser stayed bypassed under every skin in the corpus: a band
/// drag wrote its gain, `setEQBand` reached `AudioEngine`, and nothing was audible — reported as
/// "the EQ is not enabled in WMP for any skin".
enum WMPDeclaredHostState {
    /// Whether the skin declares its equaliser on or off, or `nil` when it says nothing — in which
    /// case the user's own persisted setting stands, which is what WMP does with an unstated
    /// `enable`.
    ///
    /// Both spellings count: `enable` is authored by 88 skins and `enabled` by 57, the same pair
    /// `WMPTransportAction.boundAction` and `WMPPropertyRegistry` already accept on the script
    /// path. A `wmpprop:` binding is not an answer — it asks the host what the host is about to be
    /// told — so only a literal decides, and an unparseable one decides nothing.
    static func equalizerEnabled(in skin: WMPLoadedSkin) -> Bool? {
        for node in skin.graph.allNodes where isEqualizerSettings(node) {
            for name in ["enable", "enabled"] {
                guard case let .literal(raw)? = node.attribute(named: name)?.value else { continue }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.caseInsensitiveCompare("true") == .orderedSame { return true }
                if trimmed.caseInsensitiveCompare("false") == .orderedSame { return false }
            }
        }
        return nil
    }

    /// Matched on the authored tag as well as the kind, for the reason `WMPSkinSurfaces.matches`
    /// gives: what decides this is what the skin declared, not how much of it the graph classifies.
    private static func isEqualizerSettings(_ node: WMPNode) -> Bool {
        node.kind == .equalizerSettings || node.authoredTagName.uppercased() == "EQUALIZERSETTINGS"
    }

    /// The view the skin says it opens in — `<THEME currentViewID="…">` — or `nil` when it says
    /// nothing, which is 164 of the 180 archives.
    ///
    /// **It is a declaration, not a redirect**, so it belongs to the candidate walk rather than to
    /// `switchView`: the walk's first entry stays the *user's* persisted `wmpSkinViewID`, because a
    /// skin naming its startup view is not a skin overriding where the user last left it.
    ///
    /// Only `portals` needs it today — 16 archives author the attribute and it is the one whose
    /// walk lands elsewhere, because it defines `mode2` before `mode1` and the walk's fallback is
    /// document order. That opened the player on the skin's info mode, where the mode button the
    /// user is reaching for is not (W153). A literal decides and nothing else: a `wmpprop:` value
    /// here would be asking the host which view to show before any view exists.
    static func authoredStartupViewID(in skin: WMPLoadedSkin) -> String? {
        for node in skin.graph.roots where node.authoredTagName.uppercased() == "THEME" {
            guard case let .literal(raw)? = node.attribute(named: "currentViewID")?.value else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
