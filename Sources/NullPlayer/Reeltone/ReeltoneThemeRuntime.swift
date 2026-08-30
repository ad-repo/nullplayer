import Foundation

/// Installs the selected Reeltone palette as a transient presentation for Original content.
/// This deliberately bypasses Original selection persistence.
enum ReeltoneThemeRuntime {
    static func prepare() {
        let theme = ReeltoneSkinEngine.shared.activatePreferredTheme()
        activate(theme)
    }

    static func activateCurrentTheme() {
        activate(ReeltoneSkinEngine.shared.currentTheme)
    }

    private static func activate(_ theme: ReeltoneThemeAdapter) {
        ModernSkinEngine.shared.activateTransientSkin(
            theme.presentationSkin,
            named: "Reeltone — \(theme.name)"
        )
    }
}
