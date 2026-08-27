import AppKit

/// Where one surface lives in the loaded skin.
enum WinampModernSurfaceTarget: Equatable {
    /// The skin draws this surface inside a window it already owns (cPro's tabs and drawers).
    case embedded(containerID: WasabiObjectID)
    /// The skin declares a window of its own for it (mmd3's `Pledit`).
    case declaredContainer(id: String)
    /// NullPlayer appended a window built from the skin's own frame (Phase 13.2).
    case synthesizedContainer(id: String)
    /// Nothing in the skin can show it; NullPlayer's own window is used instead.
    case classicFallback(reason: String)

    var isSkinOwned: Bool {
        if case .classicFallback = self { return false }
        return true
    }
}

/// The reconciled answer for every routed surface, published once per loaded skin.
struct WinampModernSurfaceCatalog {
    let playlist: WinampModernSurfaceTarget
    let equalizer: WinampModernSurfaceTarget
    let library: WinampModernSurfaceTarget
    /// The skin's own video window (B20). Only ever `.declaredContainer` or `.classicFallback`: see
    /// `WinampModernSurfaceInventory.routedKinds` for why it is never embedded and never synthesized.
    let video: WinampModernSurfaceTarget
    /// The skin's own AVS/visualization window (B20a). Like `video`, only ever `.declaredContainer`
    /// or `.classicFallback`.
    let visualization: WinampModernSurfaceTarget

    /// The container ids this catalog already routes. A surface reached through the catalog has its
    /// own menu item (Windows → Playlist / Equalizer / Library), so anything listing skin windows
    /// must skip these or the user gets two entry points to one window — which is the disagreement
    /// the catalog was built to end. Container *kind* is not enough to spot them: Defix's `pledit`
    /// declares no `component=` GUID and is routed from the declarative surface inventory instead.
    var routedContainerIDs: Set<String> {
        var ids: Set<String> = []
        for kind in WinampModernSurfaceInventory.managedKinds {
            switch self[kind] {
            case .declaredContainer(let id), .synthesizedContainer(let id): ids.insert(id.lowercased())
            case .embedded, .classicFallback: continue
            }
        }
        return ids
    }

    subscript(kind: WinampModernComponentKind) -> WinampModernSurfaceTarget {
        switch kind {
        case .playlist: return playlist
        case .equalizer: return equalizer
        case .library: return library
        case .video: return video
        case .visualization: return visualization
        default: return .classicFallback(reason: "\(kind.rawValue) is not a routed surface")
        }
    }
}

/// The single place that answers "show the playlist" for a `.wal` skin.
///
/// Three different things can be meant by that, and before Phase 13 the answer depended on who asked:
/// the menu bar always opened a classic `.wsz` window, while a skin button asked the view, which
/// looked for an embedded holder first. On cPro-Bento that meant the skin's own tab and the View menu
/// disagreed about what the playlist *was*.
///
/// Everything now resolves through one catalog, in one order — embedded → declared or synthesized
/// container → classic fallback — so a menu item, a skin button, a restored session, and a live mode
/// switch cannot reach different windows.
final class WinampModernSurfaceCoordinator {

    /// What the coordinator needs from the window controller, kept as closures so the controller
    /// stays the sole owner of windows and views and this type owns no lifetime.
    struct Environment {
        /// Bring the main window forward and reveal an embedded surface inside it.
        let revealEmbedded: (WinampModernComponentKind, WasabiObjectID, Bool) -> Bool
        /// Whether the window hosting the embedded surfaces is on screen.
        let isMainWindowVisible: () -> Bool
        /// The native window hosting a container, if the controller made one.
        let window: (String) -> NSWindow?
        /// Show/hide a container's window.
        let setVisible: (String, Bool) -> Void
        /// Ask the classic provider to take this surface — the deliberate bypass that must never
        /// re-enter the public routing.
        let classicFallback: (WinampModernComponentKind, Bool) -> Void
        /// Redraw every `.wal` window (a surface's contents changed).
        let redraw: () -> Void
    }

    let catalog: WinampModernSurfaceCatalog
    private let environment: Environment

    init(catalog: WinampModernSurfaceCatalog, environment: Environment) {
        self.catalog = catalog
        self.environment = environment
    }

    /// Build the catalog from what the skin declared and what synthesis produced, reconciled against
    /// the containers the controller actually opened windows for.
    static func makeCatalog(loadedSkin: WinampModernLoadedSkin,
                            hostedContainerIDs: Set<String>,
                            embeddedContainerID: WasabiObjectID?) -> WinampModernSurfaceCatalog {
        let inventory = loadedSkin.surfaceInventory
        let synthesis = loadedSkin.surfaceSynthesis

        func target(for kind: WinampModernComponentKind) -> WinampModernSurfaceTarget {
            if inventory.embeddedKinds.contains(kind), let embeddedContainerID {
                return .embedded(containerID: embeddedContainerID)
            }
            if let id = inventory.declaredContainers[kind], hostedContainerIDs.contains(id) {
                return .declaredContainer(id: id)
            }
            if let id = synthesis.synthesizedContainers[kind], hostedContainerIDs.contains(id) {
                // Never the equalizer: `synthesizableKinds` excludes it, because a synthesized
                // window's body is a component holder we invented and the equalizer's hosted surface
                // is only a stand-in. See `WasabiSurfaceInventory.synthesizableKinds`.
                return .synthesizedContainer(id: id)
            }
            if let reason = synthesis.unavailable[kind] {
                return .classicFallback(reason: reason)
            }
            if inventory.declaredContainers[kind] != nil || synthesis.synthesizedContainers[kind] != nil {
                // Declared but not hosted: its container had no renderable normal layout.
                return .classicFallback(reason: "the skin's \(kind.rawValue) container did not open")
            }
            return .classicFallback(reason: "the skin declares no \(kind.rawValue) surface")
        }

        return WinampModernSurfaceCatalog(playlist: target(for: .playlist),
                                          equalizer: target(for: .equalizer),
                                          library: target(for: .library),
                                          video: target(for: .video),
                                          visualization: target(for: .visualization))
    }

    // MARK: - Routing

    /// True when the skin itself owns this surface, so `WindowManager` must not create its own window.
    func handles(_ kind: WinampModernComponentKind) -> Bool { catalog[kind].isSkinOwned }

    /// True when the skin draws this surface inside a window it already owns, rather than in a
    /// window of its own or NullPlayer's.
    func isEmbedded(_ kind: WinampModernComponentKind) -> Bool {
        if case .embedded = catalog[kind] { return true }
        return false
    }

    func isSurfaceVisible(_ kind: WinampModernComponentKind) -> Bool {
        switch catalog[kind] {
        case .embedded:
            // An embedded surface is part of the player window: it is as visible as that window is.
            // There is no separate thing to hide, and nothing to hand to docking or persistence.
            return environment.isMainWindowVisible()
        case .declaredContainer(let id), .synthesizedContainer(let id):
            return environment.window(id)?.isVisible == true
        case .classicFallback:
            return false
        }
    }

    func showSurface(_ kind: WinampModernComponentKind,
                     allowEmbeddedAutoOpenFallback: Bool = true) {
        switch catalog[kind] {
        case .embedded(let containerID):
            _ = environment.revealEmbedded(kind, containerID, allowEmbeddedAutoOpenFallback)
        case .declaredContainer(let id), .synthesizedContainer(let id):
            environment.setVisible(id, true)
        case .classicFallback:
            environment.classicFallback(kind, true)
        }
    }

    func toggleSurface(_ kind: WinampModernComponentKind) {
        switch catalog[kind] {
        case .embedded(let containerID):
            _ = environment.revealEmbedded(kind, containerID, true)
        case .declaredContainer(let id), .synthesizedContainer(let id):
            environment.setVisible(id, !(environment.window(id)?.isVisible == true))
        case .classicFallback:
            environment.classicFallback(kind, false)
        }
    }

    /// The native window a surface uses, or nil for an embedded one — an embedded surface must never
    /// be handed to docking, compact-mode snapshots, or frame persistence as if it owned a window.
    func nativeWindow(for kind: WinampModernComponentKind) -> NSWindow? {
        switch catalog[kind] {
        case .declaredContainer(let id), .synthesizedContainer(let id): return environment.window(id)
        case .embedded, .classicFallback: return nil
        }
    }

    /// A surface's contents changed (the playlist queue, an EQ preset).
    func surfaceContentDidChange() { environment.redraw() }

    /// One line per surface, for the compatibility report and the render harness.
    var summary: String { catalog.summaryLine }
}

extension WinampModernSurfaceCatalog {
    /// Where each surface lives, in one readable line.
    var summaryLine: String {
        WinampModernSurfaceInventory.routedKinds.map { kind in
            switch self[kind] {
            case .embedded: return "\(kind.rawValue)=embedded"
            case .declaredContainer(let id): return "\(kind.rawValue)=declared:\(id)"
            case .synthesizedContainer(let id): return "\(kind.rawValue)=synthesized:\(id)"
            case .classicFallback(let reason): return "\(kind.rawValue)=classic(\(reason))"
            }
        }.joined(separator: " ")
    }
}
