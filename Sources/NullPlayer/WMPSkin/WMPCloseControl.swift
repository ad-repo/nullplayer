import Foundation

/// **Whether a skin gives the user any way to close its player.**
///
/// WMP drew a Windows title bar around a view unless the skin wrote `titleBar="false"`, so a skin
/// that relied on that frame authors no close of its own — `Classic` is a rectangle with a "Return
/// to Full Mode" toggle and nothing else. A `.wmz` window here is always borderless, so such a skin
/// left the user no way to close it but the menu bar. When this answers false the player window
/// gets an invisible close target in its top-right corner (`WMPMainView.closeTargetEnabled`).
///
/// Read over the whole skin rather than per view, because a close is routinely reached indirectly:
/// the Skins Factory archives' close button writes a preference that a windowless `controlView`
/// turns into `view.close()` 100 ms later. Any close spelled anywhere counts. Of the 185 installed
/// archives, five author none: `Classic`, `Alpine7618_v09`, `Cubist`, `Stealth` and the excluded
/// `Darkling`.
enum WMPCloseControl {
    private static let pattern = try? NSRegularExpression(
        // `<viewID>.close(` as much as `view.close(`: `circle`'s `vMain.close()` and `Kids`'
        // `KidsView.close()` name their view. `player.close()` closes the media, not a window.
        pattern: #"(?<![\w.])(?!player\b)[A-Za-z_]\w*\s*\.\s*close\s*\(|(?<![\w.])close\s*\(\s*\)|\bcloseView\s*\(|<\s*closeButton\b"#,
        options: [.caseInsensitive])

    static func authorsClose(definitionSource: String, scriptSources: [String: String]) -> Bool {
        guard let pattern else { return true }
        return ([definitionSource] + Array(scriptSources.values)).contains { source in
            pattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
        }
    }
}
