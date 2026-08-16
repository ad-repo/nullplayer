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
    let treeText: NSColor
    let treeSelection: NSColor

    /// Only three roles have a literal of their own — list text, selection background, and content
    /// background, matching Winamp's own green-on-black list with a blue selection. The rest are
    /// *derived*: a skin that names no "current row" colour gets its list colour, not an invented
    /// one, which is what real skins expect when they declare a partial set.
    static let listTextFallback = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let selectionBackgroundFallback = NSColor(red: 0, green: 0, blue: 0.78, alpha: 1)
    static let contentBackgroundFallback = NSColor.black

    /// Exactly what `make` produces for a skin that declares no colours at all.
    static let fallback = WasabiPalette(
        listText: listTextFallback,
        currentText: listTextFallback,
        selectionText: listTextFallback,
        selectionBackground: selectionBackgroundFallback,
        contentBackground: contentBackgroundFallback,
        treeText: listTextFallback,
        treeSelection: selectionBackgroundFallback)

    /// Resolve every role against a skin, newest-first per chain.
    ///
    /// `resolve` is the renderer's own colour resolver (resource lookup + gamma), passed in rather
    /// than duplicated, so a palette colour and a skin-drawn colour of the same id are identical.
    static func make(resolve: (String) -> NSColor?) -> WasabiPalette {
        func first(_ identifiers: [String], default fallbackColor: NSColor) -> NSColor {
            for identifier in identifiers {
                if let color = resolve(identifier) { return color }
            }
            return fallbackColor
        }
        let listText = first(["pledit.text", "studio.list.text", "wasabi.list.text"],
                             default: listTextFallback)
        let selectionBackground = first(["studio.list.item.selected",
                                         "wasabi.list.text.selected.background",
                                         "pledit.currentoutline"],
                                        default: selectionBackgroundFallback)
        return WasabiPalette(
            listText: listText,
            currentText: first(["pledit.text.current", "wasabi.list.text.current"], default: listText),
            selectionText: first(["studio.list.item.selected.fg", "wasabi.list.text.selected"],
                                 default: listText),
            selectionBackground: selectionBackground,
            contentBackground: first(["wasabi.edit.background", "studio.list.column.background",
                                      "wasabi.list.background", "common.labelwnd.background"],
                                     default: contentBackgroundFallback),
            treeText: first(["studio.tree.text"], default: listText),
            treeSelection: first(["studio.tree.selected", "studio.tree.hilited"],
                                 default: selectionBackground))
    }
}
