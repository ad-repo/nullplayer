import Foundation

/// The container a program was handed by `newDynamicContainer`, and — for a container the skin
/// declared `dynamic="1"` — every object's attributes as they stood when it was handed out, which is
/// what a re-ask after the program closed it restores (B309).
struct HeldDynamicContainer {
    let id: WasabiObjectID
    let firstHandedOut: [WasabiObjectID: [String: String]]?
}

/// `System.newDynamicContainer`: which container each program is handed, and what it gets back when
/// it asks again. Split out of `WinampModernScriptRuntimeSystem.swift`.
extension WinampModernScriptRuntime {
    /// `System.newDynamicContainer(id)` — Winamp builds a **fresh instance** of a declared container
    /// so a skin can have several of the same window at once.
    ///
    /// The copy is made **per calling program**, and that is the whole rule. The first program to ask
    /// gets the declared root, exactly as every caller did before B110, so Big Bento's search popups,
    /// MoonLight's four frames and every other single-holder caller behave as they did. A *second*
    /// program asking for the same id is the case that was broken: Ebonite includes
    /// `standardframe.maki` five times, once per framed window, and answering all five with the one
    /// declared root left its playlist, library and frame windows sharing a rect, because every
    /// `frame_layout.resize(…)` wrote to the same container. A program that asks twice — Ebonite does,
    /// on every re-show, since it closes its frame on hide — gets back the container it already holds
    /// rather than another window (`reclaim`).
    ///
    /// A container the skin did not declare `dynamic="1"` is never copied: `dynamic="0"` is the skin
    /// saying this window is a singleton, and a copy of it would be a window nothing can address.
    func dynamicContainer(named id: String, for program: MakiProgram) -> WasabiObject? {
        let key = id.lowercased()
        let owner = ObjectIdentifier(program)
        if let held = dynamicContainerInstances[key]?[owner],
           let container = loadedSkin.runtime.graph.object(withID: held.id), !container.isTornDown {
            reclaim(container, held)
            return container
        }
        guard let declared = findRoot(type: .container, xmlID: id) else { return nil }
        var takenIDs = Set(dynamicContainerInstances[key]?.values.map(\.id) ?? [])
        // A NullPlayer-owned window borrowing this skin's frame never takes the **declared**
        // container: that object is the skin's own window's chrome, and the borrowed frame has to be
        // a copy we may adapt without touching it. See `adoptChromeForHostedWindow`.
        let hostedCaller = hostedWindowContainer(of: program)
        if hostedCaller != nil { takenIDs.insert(declared.stableID) }
        let isDynamic = declared.attributes["dynamic"] == "1"
        let root: WasabiObject
        if !takenIDs.contains(declared.stableID) {
            root = declared
        } else if isDynamic, let instance = (try? loadedSkin.runtime.instantiateContainer?(id)) ?? nil {
            // The same two things `start()` does for every declared container, in the same order: the
            // opening layout has to be *realized* before anything else touches the instance, because
            // `getLayout` answers only for realized layouts — and the caller's very next statement is
            // `frame_cont.getLayout("scdef")`. Without it the whole rebuild ran against a null layout
            // and the second framed window came up with no chrome at all.
            if let opening = WasabiSceneRenderer.primaryLayout(of: instance) {
                markLayoutRealized(opening)
            }
            containerInstanceCreated?(instance)
            // A copy carrying its own `<script>` (a notifier, say) starts it exactly as a runtime
            // group's is started. Ebonite's frame is pure markup and adds none.
            try? startScripts(addedBeneath: instance)
            if let hostedCaller { adoptChromeForHostedWindow(instance, for: hostedCaller) }
            root = instance
        } else {
            // Out of copies (or a singleton container): the declared root is still the right answer —
            // a shared window is a worse result than a working one, and it is what shipped before.
            root = declared
        }
        dynamicContainerInstances[key, default: [:]][owner] = HeldDynamicContainer(
            id: root.stableID, firstHandedOut: isDynamic ? Self.attributes(under: root) : nil)
        return root
    }

    /// A program asking again for the `dynamic="1"` container it holds, after closing it, gets it back
    /// **as it was first handed out** (B309). Winamp builds a fresh instance on every call:
    /// GlassAMPfinal's `reset()` hides its notifier and drops the reference, and the next track's
    /// `createNotifier()` asks again expecting the window its XML declares. Handed back unchanged, the
    /// `coverandbutton.resize(0,0,…)` one show left stayed for the rest of the session, 11 px up and
    /// left of the frame. Restoring the attributes gives that fresh state without a second window, so
    /// the programs started inside it (GlassAMP's `<covern>`) keep running against the same objects —
    /// a copy per call would leak a discarded copy's timers on every track.
    ///
    /// "Closed" is `effectiveVisibility`: not on screen, whether the host closed its window or (with no
    /// host) the script's `hide()` left it hidden. A container still open is handed back as it is.
    /// `visible` itself is not restored, so a re-ask never shows a window — the program does that.
    private func reclaim(_ container: WasabiObject, _ held: HeldDynamicContainer) {
        guard let firstHandedOut = held.firstHandedOut, !effectiveVisibility(of: container) else { return }
        func restore(_ object: WasabiObject) {
            if let attributes = firstHandedOut[object.stableID] {
                cancelTargetAnimation(objectID: object.stableID)
                for key in Set(object.attributes.keys).union(attributes.keys) where key != "visible" {
                    object.forgetDeclaredXMLParam(key)
                    object.setAttribute(key, value: attributes[key])
                }
            }
            object.children.forEach(restore)
        }
        restore(container)
        noteGeometryChange()
        notifyGraphDidMutate()
    }

    private static func attributes(under root: WasabiObject) -> [WasabiObjectID: [String: String]] {
        var attributes: [WasabiObjectID: [String: String]] = [:]
        func record(_ object: WasabiObject) {
            attributes[object.stableID] = object.attributes
            object.children.forEach(record)
        }
        record(root)
        return attributes
    }

    /// Whether a script has taken this container as a `newDynamicContainer` — a window Winamp creates
    /// **on demand**, whether it turned out to be the declared container (the first caller) or a copy.
    ///
    /// The distinction the window layer needs, and the reason it cannot read `dynamic="1"` instead:
    /// several corpus skins declare their real `Pledit`, `MLibrary` and `AVS` windows `dynamic="1"`,
    /// and those are ordinary skin windows — tiled, snapped to, listed in the menu, remembered. What
    /// makes Ebonite's `sc.alphaframe` different is not the attribute, it is that a script asked for it.
    func isDynamicallyClaimed(_ container: WasabiObjectID) -> Bool {
        dynamicContainerInstances.values.contains { $0.values.contains { $0.id == container } }
    }
}
