import AppKit
import Foundation

/// What the **host** remembers about a `.wal` skin between launches (B44).
///
/// A skin's own preferences already survive on their own: `setPrivateInt`/`setPrivateString` and
/// `cfgattrib` write straight into `WinampModernConfiguration`, namespaced per skin, and a skin that
/// wants to remember something about itself does exactly that. What is collected here is the short
/// list the **engine** owns instead — state that lives in the object graph, which is rebuilt from the
/// markup on every load, so nothing about it survives unless we save it:
///
/// | State | Section | Key |
/// |---|---|---|
/// | A `<Wasabi:Frame>`'s divider offset | `@nullplayer.frames` | `container-id/frame-id` |
/// | Which layout a container is on (shade) | `@nullplayer.layouts` | `container-id` |
/// | Whether one of the skin's windows is open | `@nullplayer.windows` | `container-id` |
/// | How large the host draws its own text (Text Size) | `@nullplayer.text` | `size` |
/// | Whether the host fills a claimable holder (Waveform Seeker) | `@nullplayer.components` | `waveseeker` |
/// | A colour the user set by hand (Skin Colors) | `@nullplayer.colors` | `role/theme` |
///
/// The colour overrides are the clearest case of the rule below: they exist **only** because a user
/// said so, and the skin has an opinion of its own that they are deliberately outranking.
///
/// Text Size is the one entry that is not object-graph state — it is a plain per-skin preference —
/// but it belongs here for the same reason: it is the *host's* setting about a skin, so nothing the
/// skin itself writes would ever carry it.
///
/// Two things are deliberately **not** here. The active colour theme is already persisted by
/// `WasabiColorThemeList` under `appearance/theme`, which is where a skin's own script would look for
/// it. And a window's frame on screen belongs to the *player's* window rather than to the skin, so it
/// goes through `AppStateManager` with everything else the app restores.
///
/// **The rule every entry obeys: a state the *user* set is a preference and survives; a state the
/// skin's own script set is the author's default and does not.** A splitter is stored from mouse-up
/// and from nowhere else; a layout from a `SWITCH` on a control the user clicked; a window from a
/// menu item, a skin button or a close box. A script's `setPosition`, `switchToLayout` or `hide()` is
/// the skin describing *this* run, and recording it would freeze the author's opening layout into a
/// preference the user never expressed — Big Bento's `setPosition(434)` is a genuine "narrow player,
/// wide playlist" default, not a defect to be overridden.
///
/// Keys are the names that survive a reload — a container's and an object's `id`. `stableID` is a
/// per-load counter and would address a different object next launch, so an object with no `id` is
/// skipped rather than given a positional key a markup edit would silently reassign.
enum WinampModernSkinState {

    // MARK: - Sections

    static let framesSection = "@nullplayer.frames"
    static let layoutsSection = "@nullplayer.layouts"
    static let windowsSection = "@nullplayer.windows"
    static let textSection = "@nullplayer.text"
    static let textSizeKey = "size"
    static let visSection = "@nullplayer.vis"
    static let analyzerKey = "engine"
    /// The `{0000000A}` pane's own engine, on a key of its own so the `<vis>` boxes' `engine` above
    /// keeps meaning exactly what it meant before this surface had a choice at all.
    static let holderAnalyzerKey = "engine.holder"
    /// The `{0000000A}` pane's analyzer/oscilloscope/off. The `<vis>` boxes have no entry here
    /// because their mode is a `mode=` attribute the skin itself declares and its scripts write; an
    /// unhosted plugin pane has no markup of its own, so the host is the only thing that can remember
    /// what the user put in it.
    static let holderModeKey = "mode.holder"
    /// Host components the user can decline. See `waveformSeekerEnabled`.
    static let componentsSection = "@nullplayer.components"
    static let waveformSeekerKey = "waveseeker"
    /// Colours the user set by hand, per role **and per colour theme**. See `paletteOverride`.
    static let colorsSection = "@nullplayer.colors"

    // MARK: - A splitter's divider offset

    /// The stored divider offset, or nil when the user has never dragged this one.
    static func framePosition(container: String, frame: String,
                              in configuration: WinampModernConfiguration) -> Double? {
        storedInteger(section: framesSection, key: frameKey(container: container, frame: frame),
                      in: configuration).map(Double.init)
    }

    static func setFramePosition(_ position: Double, container: String, frame: String,
                                 in configuration: WinampModernConfiguration) {
        let value = position.isFinite ? Int32(clamping: Int(max(0, position.rounded()))) : 0
        configuration.setInteger(value, section: framesSection,
                                 key: frameKey(container: container, frame: frame))
    }

    /// The container is part of the key because a skin may carry the same frame id in two of its
    /// windows — and because a frame is only ever addressed from the container that declares it.
    static func frameKey(container: String, frame: String) -> String { "\(container)/\(frame)" }

    // MARK: - Which layout a container is on

    /// The layout the user last switched this container to, or nil when they never have.
    ///
    /// This is Winamp's "it comes back shaded if you left it shaded". Empty is read as nil so a
    /// cleared value cannot name a layout no container has.
    static func layout(container: String, in configuration: WinampModernConfiguration) -> String? {
        let stored = configuration.string(section: layoutsSection, key: container, default: "")
        return stored.isEmpty ? nil : stored
    }

    static func setLayout(_ id: String, container: String,
                          in configuration: WinampModernConfiguration) {
        configuration.setString(id, section: layoutsSection, key: container)
    }

    // MARK: - Whether one of the skin's windows is open

    /// What the user last did with this window, or nil when they have never said. Distinct from
    /// "closed": a window they have never touched falls back to what the skin declares.
    static func windowIsVisible(container: String,
                                in configuration: WinampModernConfiguration) -> Bool? {
        storedInteger(section: windowsSection, key: container, in: configuration).map { $0 != 0 }
    }

    static func setWindowIsVisible(_ visible: Bool, container: String,
                                   in configuration: WinampModernConfiguration) {
        configuration.setInteger(visible ? 1 : 0, section: windowsSection, key: container)
    }

    // MARK: - How large the host draws its own text

    /// The Text Size the user chose for this skin, or `.auto` when they never have.
    ///
    /// Stored as the raw percent, so `0` is `auto` — a legal value, which is exactly why the "never
    /// set" sentinel below cannot be zero. A value no longer in the enum reads as `.auto` rather than
    /// resurrecting a size the menu can no longer show.
    static func textScale(in configuration: WinampModernConfiguration) -> WinampModernTextScale {
        guard let stored = storedInteger(section: textSection, key: textSizeKey, in: configuration)
        else { return .auto }
        return WinampModernTextScale.from(storedValue: Int(stored))
    }

    static func setTextScale(_ scale: WinampModernTextScale,
                             in configuration: WinampModernConfiguration) {
        configuration.setInteger(Int32(scale.storedValue), section: textSection, key: textSizeKey)
    }

    // MARK: - Host components the user can decline

    /// Whether the host may fill this skin's claimable seeker holder, defaulting to **yes** — the
    /// strip is empty without us, so the interesting state is the one that needs no decision.
    ///
    /// Per skin, like Text Size and for the same reason: a user who does not want Big Bento's strip
    /// filled has said nothing about a different skin that gains one later.
    static func waveformSeekerEnabled(in configuration: WinampModernConfiguration) -> Bool {
        configuration.integer(section: componentsSection, key: waveformSeekerKey,
                              default: 1) != 0
    }

    static func setWaveformSeekerEnabled(_ enabled: Bool,
                                         in configuration: WinampModernConfiguration) {
        configuration.setInteger(enabled ? 1 : 0, section: componentsSection, key: waveformSeekerKey)
    }

    // MARK: - What paints a visualization box

    /// The visualization engine the user chose for this skin's `<vis>` boxes, or `.skin` when they
    /// never have — a skin looks the way its author drew it until somebody says otherwise.
    ///
    /// A string rather than an integer, because the value is an engine's *name*: an ordinal would
    /// silently re-point at a different engine the first time the list changes order.
    static func spectrumAnalyzer(for surface: WinampModernVisSurface,
                                 in configuration: WinampModernConfiguration) -> WinampModernSpectrumAnalyzer {
        WinampModernSpectrumAnalyzer.from(
            storedValue: configuration.string(section: visSection, key: analyzerKey(for: surface),
                                              default: ""))
    }

    static func setSpectrumAnalyzer(_ suite: WinampModernSpectrumAnalyzer,
                                    for surface: WinampModernVisSurface,
                                    in configuration: WinampModernConfiguration) {
        configuration.setString(suite.rawValue, section: visSection, key: analyzerKey(for: surface))
    }

    private static func analyzerKey(for surface: WinampModernVisSurface) -> String {
        switch surface {
        case .visBox: return analyzerKey
        case .componentHolder: return holderAnalyzerKey
        }
    }

    // MARK: - What an unhosted `{0000000A}` pane is showing

    /// Analyzer, oscilloscope or nothing, for the plugin panes that have no `<vis>` markup to say.
    /// Winamp's own default in that slot is its spectrum analyzer (BB9), so that is what a user who
    /// has never chosen gets.
    static func visualizationHolderMode(in configuration: WinampModernConfiguration) -> WasabiVisualizationMode {
        // An unwritten entry is the empty string, which `WasabiVisualizationMode` already reads as
        // the analyzer — the same default a `<vis>` with no `mode=` gets.
        WasabiVisualizationMode(
            attribute: configuration.string(section: visSection, key: holderModeKey, default: ""))
    }

    static func setVisualizationHolderMode(_ mode: WasabiVisualizationMode,
                                           in configuration: WinampModernConfiguration) {
        configuration.setString(mode.attributeValue, section: visSection, key: holderModeKey)
    }

    // MARK: - Colours the user set by hand (B146)

    /// One role's user colour for this skin under `theme`, or nil when they have never set it.
    ///
    /// **Per theme, not just per skin.** A skin's `<gammaset>`s re-tint the list roles independently —
    /// winampmodern566 ships 88 of them — so a colour that fixes one theme's Media Library is simply a
    /// different wrong colour under the next. The key is `role/theme`, the same composite shape
    /// `frameKey` uses, and the theme is the catalog's canonical display name (`activeTheme`), which is
    /// stable across launches because the catalog vends it from the skin's own markup.
    ///
    /// Stored as `#rrggbb`. Alpha is deliberately not stored: every role here is drawn opaque, and a
    /// colour a user could set to invisible is a way to make the panel produce a blank window.
    ///
    /// One accepted collision: `WinampModernConfiguration.safeComponent` folds punctuation to `_`, so
    /// two themes whose names differ only in punctuation would share a slot. No corpus skin does that,
    /// and the cost of getting it wrong is one theme showing another's override — not data loss.
    static func paletteOverride(role: WasabiPalette.Role, theme: String,
                                in configuration: WinampModernConfiguration) -> NSColor? {
        let stored = configuration.string(section: colorsSection,
                                          key: paletteKey(role: role, theme: theme), default: "")
        return stored.isEmpty ? nil : color(fromHex: stored)
    }

    /// Set or clear one role's user colour. **Clearing removes the key**, because there is no free
    /// value a colour could spell "unset" with — see `WinampModernConfiguration.removeValue`.
    static func setPaletteOverride(_ color: NSColor?, role: WasabiPalette.Role, theme: String,
                                   in configuration: WinampModernConfiguration) {
        let key = paletteKey(role: role, theme: theme)
        guard let color else {
            configuration.removeValue(section: colorsSection, key: key)
            return
        }
        configuration.setString(hexString(color), section: colorsSection, key: key)
    }

    /// Every role the user has set for this skin under `theme` — what `WasabiPalette.make` asks for.
    static func paletteOverrides(theme: String,
                                 in configuration: WinampModernConfiguration) -> [WasabiPalette.Role: NSColor] {
        var overrides: [WasabiPalette.Role: NSColor] = [:]
        for role in WasabiPalette.Role.allCases {
            if let color = paletteOverride(role: role, theme: theme, in: configuration) {
                overrides[role] = color
            }
        }
        return overrides
    }

    /// The whole-skin reset: drop every override under **every** theme.
    ///
    /// The two-level reset exists because per-theme storage is otherwise a trap — a user who fixed one
    /// theme months ago has no way to find the other five they also touched. Per-role clears this
    /// theme; this clears the skin.
    static func clearPaletteOverrides(in configuration: WinampModernConfiguration) {
        configuration.removeSection(colorsSection)
    }

    static func paletteKey(role: WasabiPalette.Role, theme: String) -> String {
        "\(role.rawValue)/\(theme.isEmpty ? "Default" : theme)"
    }

    /// `#rrggbb` from a colour that may be in any space — `redComponent` traps on a greyscale or
    /// catalog colour, and `NSColorWell` hands back whatever the colour panel was last showing.
    static func hexString(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.deviceRGB) ?? NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        func channel(_ value: CGFloat) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channel(rgb.redComponent),
                      channel(rgb.greenComponent), channel(rgb.blueComponent))
    }

    /// The inverse. Strict — anything that is not exactly six hex digits behind a `#` reads as nil, so
    /// a hand-edited or corrupted preference falls back to the skin rather than to an invented colour.
    static func color(fromHex value: String) -> NSColor? {
        var text = value.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return nil }
        text.removeFirst()
        guard text.count == 6, let packed = UInt32(text, radix: 16) else { return nil }
        return NSColor(deviceRed: CGFloat((packed >> 16) & 0xff) / 255,
                       green: CGFloat((packed >> 8) & 0xff) / 255,
                       blue: CGFloat(packed & 0xff) / 255,
                       alpha: 1)
    }

    // MARK: - The sentinel

    /// `-1` means "never set", which is why it cannot be spelled as `0`: **zero is a legal value for
    /// every integer entry here.** ClassicPro closes its side view with `setPosition(0)` and a user
    /// may leave it closed, `0` is exactly how a deliberately closed window is stored, and `0` is how
    /// Text Size spells the `auto` a user may have chosen deliberately after setting a percent.
    private static let unset: Int32 = -1

    private static func storedInteger(section: String, key: String,
                                      in configuration: WinampModernConfiguration) -> Int32? {
        let stored = configuration.integer(section: section, key: key, default: unset)
        return stored < 0 ? nil : stored
    }
}
