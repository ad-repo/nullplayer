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

    /// `WINAMP_MODERN_NO_LOOKFOR_REVEAL=1`: the A/B switch for B385 (`harness.md`): a reveal no longer
    /// asks the skin `onLookForComponent` after its `onGetCancelComponent` left no holder visible.
    private static let lookForComponentRevealDisabled =
        ProcessInfo.processInfo.environment["WINAMP_MODERN_NO_LOOKFOR_REVEAL"] == "1"

    /// Tuneup_v1 (B385): its `onGetCancelComponent` only *hides* the inline playlist group; the group is
    /// shown by `onLookForComponent`, the event a skin answers with where it hosts the component. A
    /// skin whose cancel handler did not put a holder on screen is asked that next. True when it did.
    func skinHostsComponent(_ kind: WinampModernComponentKind, guid: String,
                            scripts: WinampModernScriptRuntime) -> Bool {
        guard !Self.lookForComponentRevealDisabled else { return false }
        let answered: Int
        do {
            answered = try scripts.dispatchSystem(event: "onlookforcomponent", arguments: [.string(guid)])
        } catch {
            // A skin handler that throws is the skin's fault; the reveal goes on to the autoopen fallback.
            #if DEBUG
            NSLog("WinampModern reveal %@ onLookForComponent threw %@", kind.rawValue, String(describing: error))
            #endif
            return false
        }
        return answered > 0 && hasVisibleHolder(kind)
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

    /// A skin can hold a component in another layout of the player rather than in this one:
    /// AmpTunes_III's Video tab is a layout of its own (`iWinamp Video`), reached by the skin's
    /// `action="SWITCH"` button. This switches there, as that button does, and the window takes that
    /// layout's size; left to the `autoopen` fallback, which only searches the active layout, a film
    /// opened in NullPlayer's own window and jumped into the tab only when the user picked it.
    func revealBySwitchingLayout(_ kind: WinampModernComponentKind) -> Bool {
        guard let view = skinView else { return false }
        func holds(_ object: WasabiObject) -> Bool {
            (WinampModernComponentRegistry.isHolderElement(object.tag)
                && WasabiSceneRenderer.componentKind(of: object) == kind)
                || object.children.contains(where: holds)
        }
        let active = view.renderer.layout.stableID
        guard let target = view.renderer.container.children.first(where: {
            $0.tag.is(.layout) && $0.stableID != active && holds($0)
        }), let id = target.xmlID else { return false }
        return view.activateLayout(id: id) && hasVisibleHolder(kind)
    }
}
