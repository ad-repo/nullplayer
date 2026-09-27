import AppKit

/// The `.wal` family's half of `SkinnedSurfaceStyle`: how a `WasabiPalette` becomes the seven roles a
/// hosted NullPlayer surface is painted from.
///
/// The style itself is family-neutral and lives in `App/Skinning/`, so the `.wmz` family can derive
/// one from its own markup without either engine learning about the other's. These two names are
/// typealiases rather than new types so every existing `.wal` call site — 15 in the app, plus the
/// tests — keeps referring to exactly what it always did.
typealias WinampModernSurfaceStyle = SkinnedSurfaceStyle
typealias WinampModernChrome = SkinnedSurfaceChrome

extension SkinnedSurfaceStyle {
    init(palette: WasabiPalette) {
        self.init(roles: SkinnedSurfaceRoles(
            background: palette.contentBackground,
            text: palette.listText,
            currentText: palette.currentText,
            selectionBackground: palette.selectionBackground,
            selectionText: palette.selectionText,
            treeText: palette.treeText,
            treeSelection: palette.treeSelection,
            selectionTextWasChosenByUser: palette.isOverridden(.selectionText)
        ))
    }

    /// The style a surface uses before any skin has been loaded, and in tests. Winamp's own
    /// green-on-black, through `WasabiPalette.fallback`.
    static let fallback = SkinnedSurfaceStyle(palette: .fallback)
}
