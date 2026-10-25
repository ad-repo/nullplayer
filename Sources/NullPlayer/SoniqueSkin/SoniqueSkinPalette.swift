import AppKit

/// The colours NullPlayer's own windows wear beside a Sonique skin, read straight from its
/// `[sonique colors]` (decision record § *Auxiliary-window policy*): the screen's ground and its
/// playlist colours, the roles Sonique's own playlist screen paints with. `SkinnedSurfaceStyle` runs
/// every foreground through `legible`.
///
/// The selected and the playing playlist row are marked apart from the rows
/// (`SkinnedSurfaceStyle.marked`): the skin's other colours, readable on the
/// background, never the row colour. Classic white collides with the rows on
/// skins whose rows are near-white (sonique's cyan and Pokemon's yellow are 1.25:1 from it), and the
/// guard that keeps a row readable otherwise walks straight back to the row colour: on sonique,
/// BlueEyes, k2 and Pokemon the playing row was drawn in the row colour itself.
enum SoniqueSkinPalette {
    static func surfaceStyle(for skin: SoniqueSkin) -> SkinnedSurfaceStyle {
        let source = skin.source(for: .navigator)
        func colour(_ key: SoniqueColour) -> NSColor { NSColor(cgColor: SoniqueSkinRenderer.cgColor(source.settings.colour(key)))! }
        let text = colour(.playListColor1), current = colour(.playListColor2), selection = colour(.systemBkColor2)
        return SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
            background: colour(.systemBkColor1), text: text, currentText: current,
            selectionBackground: selection, selectionText: colour(.systemColor1),
            treeText: text, treeSelection: selection,
            // `.wal`'s candidates: the playing row's own colour then the selection's; the selected
            // row's, every colour the skin names past its rows.
            playlistMarks: .init(selected: [.playListColor2, .systemColor1, .systemColor2, .systemColor3].map(colour),
                                 playing: [.playListColor2, .systemColor1].map(colour))))
    }
}
