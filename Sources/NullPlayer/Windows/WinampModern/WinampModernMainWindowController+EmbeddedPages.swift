import Foundation

/// The embedded pages the surface coordinator opens, closes and asks about. A ClassicPro strip owns
/// the pages that are its tabs (B350); every other page is whatever the skin's holders show.
extension WinampModernMainWindowController {
    /// Bring the player forward and show the page: select its tab, or ask the skin for it.
    func revealEmbeddedPage(_ kind: WinampModernComponentKind, scripts: WinampModernScriptRuntime,
                            allowAutoOpenFallback: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        defer { skinView?.needsDisplay = true }
        if let strip = classicProTabs, let tab = strip.tab(for: kind) {
            // During the load a reveal is the session restore, and the strip has restored its own
            // tabs: selecting Playlist then closed the side view and the engine reopened a Media
            // Library tab the user had closed (B358).
            if scripts.loadHasSettled || !tab.isInStrip { strip.open(tab) }
            return true
        }
        return revealEmbeddedSurface(kind, scripts: scripts, allowAutoOpenFallback: allowAutoOpenFallback)
    }

    /// Put the page away: take its tab out of the strip, or tell the skin it is going.
    func concealEmbeddedPage(_ kind: WinampModernComponentKind, scripts: WinampModernScriptRuntime) {
        defer { skinView?.needsDisplay = true }
        if let strip = classicProTabs, let tab = strip.tab(for: kind) {
            strip.close(tab)
        } else {
            concealEmbeddedSurface(kind, scripts: scripts)
        }
    }

    /// Whether the player draws the page: its tab is in the strip, or a holder of its kind is visible.
    func showsEmbeddedPage(_ kind: WinampModernComponentKind) -> Bool {
        if let tab = classicProTabs?.tab(for: kind) { return tab.isInStrip }
        return hasVisibleHolder(kind)
    }

    /// The other half of the reveal contract: `System.onGetCancelComponent(guid, false)` tells the
    /// skin a component is going away, and the skin picks what fills its place — ClassicPro's
    /// `openDefaultTab` switches the SUI to another tab, or folds the side playlist away (B350).
    /// No fallback: a skin that leaves the holder up has declined, and the page stays.
    private func concealEmbeddedSurface(_ kind: WinampModernComponentKind,
                                        scripts: WinampModernScriptRuntime) {
        guard let guid = WinampModernComponentRegistry.canonicalGUID(for: kind) else { return }
        let handled = (try? scripts.dispatchSystem(event: "ongetcancelcomponent",
                                                   arguments: [.string(guid), .boolean(false)])) ?? 0
        #if DEBUG
        NSLog("WinampModern conceal %@ guid=%@ handlers=%d", kind.rawValue, guid, handled)
        #else
        _ = handled
        #endif
    }
}
