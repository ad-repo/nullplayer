import AppKit

/// The colours NullPlayer's own drawing uses inside a `.wal` skin.
///
/// A playlist, an equalizer, and a library browser drawn by us have to sit inside artwork drawn by the
/// skin, so their text and selection colours must come from the skin's colour resources — through the
/// same resolver and the same colour-theme gamma as everything else, or a theme switch recolours the
/// chrome and leaves the contents behind.
///
/// Skins disagree about the names, though. Winamp Modern and mmd3 use the classic `pledit.*` ids;
/// CornerAmp and ClassicPro use the `studio.*`/`wasabi.*` Wasabi library ids. Each role therefore has
/// a chain, tried in order, ending in a documented literal so a surface is never drawn in an
/// accidental colour.
struct WasabiPalette: Equatable {
    let listText: NSColor
    let currentText: NSColor
    let selectionText: NSColor
    let selectionBackground: NSColor
    let contentBackground: NSColor
    /// The plate behind a `<Wasabi:EditBox>` and a `<Wasabi:DropDownList>` — a *text field*, not a list.
    /// Split from `contentBackground` by B113: both used to resolve from one chain led by
    /// `wasabi.edit.background`, so fixing the lists would have dragged the form widgets onto the
    /// list colour with them. Eleven corpus skins declare the two ids differently and mean it.
    let editBackground: NSColor
    let treeText: NSColor
    let treeSelection: NSColor

    /// Only three roles have a literal of their own — list text, selection background, and content
    /// background, matching Winamp's own green-on-black list with a blue selection. The rest are
    /// *derived*: a skin that names no "current row" colour gets its list colour, not an invented
    /// one, which is what real skins expect when they declare a partial set.
    static let listTextFallback = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let selectionBackgroundFallback = NSColor(red: 0, green: 0, blue: 0.78, alpha: 1)
    static let contentBackgroundFallback = NSColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// Every role is stored in device RGB, whatever the caller passed in.
    ///
    /// The surfaces painted from this palette read the channels directly — the star rating dims the
    /// text colour, `WinampModernSurfaceStyle` blends roles into chrome — and `redComponent` and
    /// friends **raise** on a colour that is not in an RGB space. `.white`, `.black`, and anything
    /// AppKit vends as a greyscale tagged pointer are exactly that, and they reach here from a skin
    /// whose colour resource is missing or unparseable. Converting once, here, means no consumer has
    /// to defend itself.
    init(listText: NSColor, currentText: NSColor, selectionText: NSColor,
         selectionBackground: NSColor, contentBackground: NSColor,
         editBackground: NSColor? = nil,
         treeText: NSColor, treeSelection: NSColor) {
        self.listText = Self.rgb(listText)
        self.currentText = Self.rgb(currentText)
        self.selectionText = Self.rgb(selectionText)
        self.selectionBackground = Self.rgb(selectionBackground)
        self.contentBackground = Self.rgb(contentBackground)
        self.editBackground = Self.rgb(editBackground ?? contentBackground)
        self.treeText = Self.rgb(treeText)
        self.treeSelection = Self.rgb(treeSelection)
    }

    /// Conversion only fails for a pattern colour, which has no single component value to give; a
    /// skin cannot declare one, so the opaque-black substitute is unreachable in practice.
    private static func rgb(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.deviceRGB) ?? NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
    }

    /// Exactly what `make` produces for a skin that declares no colours at all.
    static let fallback = WasabiPalette(
        listText: listTextFallback,
        currentText: listTextFallback,
        selectionText: listTextFallback,
        selectionBackground: selectionBackgroundFallback,
        contentBackground: contentBackgroundFallback,
        editBackground: contentBackgroundFallback,
        treeText: listTextFallback,
        treeSelection: selectionBackgroundFallback)

    /// The roles, and the skin colour ids each one tries in order.
    ///
    /// Held as data rather than inlined into `make` so a probe can report *which* link of a chain
    /// answered — and why the earlier ones did not — without re-declaring the chains beside it and
    /// drifting from them the first time one changes (BB2a).
    enum Role: String, CaseIterable {
        case listText, currentText, selectionText, selectionBackground, contentBackground
        case editBackground, treeText, treeSelection

        var identifiers: [String] {
            switch self {
            case .listText: return ["studio.list.text", "wasabi.list.text", "pledit.text"]
            case .currentText: return ["wasabi.list.text.current", "pledit.text.current"]
            case .selectionText: return ["studio.list.item.selected.fg", "wasabi.list.text.selected"]
            case .selectionBackground: return ["studio.list.item.selected",
                                               "wasabi.list.text.selected.background",
                                               "pledit.currentoutline"]
            // `wasabi.list.background` comes first (B113). `wasabi.edit.background` is a *text
            // field's* colour, and a skin that declares both means them differently: Itemskin's list
            // is gold (220,175,0 — what its dark-olive `wasabi.list.text` was drawn for) and its
            // edit fields are near-black 42,42,42. Asking for the edit colour first painted our rows
            // on the wrong surface in **11 of the 69** corpus skins, and left the plain (unselected)
            // row text below 3:1 on six of them — Itemskin's 1.52:1 olive-on-charcoal was the live
            // report, K-jr and Pure Inspired were black-on-charcoal at 1.46:1. Every one of the 11
            // improves except MoonLight, which goes 4.27:1 → 3.11:1 onto the near-white list
            // background its author declared. B48's legibility guard cannot reach any of this:
            // `legibleRowColor` deliberately leaves *unselected* rows alone.
            case .contentBackground: return ["wasabi.list.background", "wasabi.edit.background",
                                             "studio.list.column.background",
                                             "common.labelwnd.background"]
            case .editBackground: return ["wasabi.edit.background", "studio.list.column.background",
                                          "common.labelwnd.background"]
            case .treeText: return ["studio.tree.text"]
            case .treeSelection: return ["studio.tree.selected", "studio.tree.hilited"]
            }
        }

        /// What a role falls back to when no id in its chain answers: a literal of its own, or
        /// another role's resolved colour.
        var fallbackDescription: String {
            switch self {
            case .listText: return "literal 0,255,0"
            case .selectionBackground: return "literal 0,0,199"
            case .contentBackground: return "literal 0,0,0"
            case .editBackground: return "role contentBackground"
            case .currentText, .selectionText, .treeText: return "role listText"
            case .treeSelection: return "role selectionBackground"
            }
        }
    }

    func color(for role: Role) -> NSColor {
        switch role {
        case .listText: return listText
        case .currentText: return currentText
        case .selectionText: return selectionText
        case .selectionBackground: return selectionBackground
        case .contentBackground: return contentBackground
        case .editBackground: return editBackground
        case .treeText: return treeText
        case .treeSelection: return treeSelection
        }
    }

    /// Resolve every role against a skin, newest-first per chain.
    ///
    /// `resolve` is the renderer's own colour resolver (resource lookup + gamma), passed in rather
    /// than duplicated, so a palette colour and a skin-drawn colour of the same id are identical.
    static func make(resolve: (String) -> NSColor?) -> WasabiPalette {
        func first(_ role: Role, default fallbackColor: NSColor) -> NSColor {
            for identifier in role.identifiers {
                if let color = resolve(identifier) { return color }
            }
            return fallbackColor
        }
        let listText = first(.listText, default: listTextFallback)
        let selectionBackground = first(.selectionBackground, default: selectionBackgroundFallback)
        let contentBackground = first(.contentBackground, default: contentBackgroundFallback)
        return WasabiPalette(
            listText: listText,
            currentText: first(.currentText, default: listText),
            selectionText: first(.selectionText, default: listText),
            selectionBackground: selectionBackground,
            contentBackground: contentBackground,
            editBackground: first(.editBackground, default: contentBackground),
            treeText: first(.treeText, default: listText),
            treeSelection: first(.treeSelection, default: selectionBackground))
    }
}
