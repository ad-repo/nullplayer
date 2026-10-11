import CoreGraphics
import Foundation
import NullPlayerCore

/// `WMP_TWEEN_TRACE=1`: what the tween trio decided, at the point it decided it.
///
/// A tween is the one script effect with **no settled-state signature at all** — with a clock it
/// arrives over time and without one it arrives at once, and both end on the same pixels — so a
/// render dump, a sweep `compare` and a screenshot taken after it lands are all blind to it.
/// Exists for W253: the load transaction was the window path that promised no clock, and telling
/// "the call never ran" from "the call ran and was flattened" needs the decision itself, not the
/// result. Writes to stderr, because a redirected `print` is block-buffered.
enum WMPTweenTrace {
    static let enabled = ProcessInfo.processInfo.environment["WMP_TWEEN_TRACE"] == "1"

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[wmp/tween] \(message())\n".utf8))
    }
}

/// How a member answered, and the only honest way to read a call trace.
///
/// `.inert` exists because of the most expensive class of phantom bug the `.wal` engine paid for: a
/// member that is *recognised* and returns a plausible default disappears from the demand tally and
/// reads, from every instrument, exactly like a working one. WMP's object model cannot be
/// implemented in full — there is no `wmploc.dll` on macOS to load a string out of — so some members
/// must answer something in order for the handler that touched them to keep running. Those answer
/// as `.inert`, are counted separately, and are listed in `reference/object-model.md`. A member that
/// is not implemented at all stays `.unrecognised`, aborts the one handler that touched it, and is
/// what ranks the backlog.
enum WMPMemberResolution: String, Hashable, Codable, Sendable {
    case live, inert, unrecognised
}

/// What a member is, once resolved: a value, another host object, or something callable.
enum WMPMemberValue {
    case value(WMPJSONValue)
    case object(String)
    case function
    case unrecognised(String)
}

/// One scriptable element. Element ids are globals in WMP — Corona's `OnLoad` calls
/// `ipl.setColumnResizeMode(…)` and `popupPreset.appendItem(…)` with no qualifier — and a write to
/// one of their properties mutates the retained graph. State lives here for the whole skin session,
/// which is the difference between a click that toggles a pane and a click that does nothing.
final class WMPScriptElement {
    let id: String
    let stableID: Int
    let kind: WMPElementKind
    /// Folded property name to value. Seeded from the authored attributes.
    var properties: [String: WMPJSONValue]
    /// Every property the markup authored. Those are always recognised, whatever they are named:
    /// a skin that writes `svMain.customFlag` after authoring it is using its own state.
    let authored: Set<String>
    /// POPUP items appended by script.
    var items: [String] = []
    /// Playlist column resize modes, by column index.
    var columnResizeModes: [Int: String] = [:]
    /// Playlist column widths set by script, by column index. Nothing draws playlist columns yet,
    /// so this is session state the skin can read back through its own bookkeeping and no more.
    var columnWidths: [Int: Double] = [:]
    /// The queue generation a `<PLAYLIST>` was pointed at a library playlist in (W136); see
    /// `WMPObjectModel.queueGeneration`.
    var libraryPlaylistGeneration = -1

    init(id: String, stableID: Int, kind: WMPElementKind,
         properties: [String: WMPJSONValue], authored: Set<String>) {
        self.id = id
        self.stableID = stableID
        self.kind = kind
        self.properties = properties
        self.authored = authored
    }
}

/// The host object model, in Swift.
///
/// Every capability the skin can reach is a member on this type. It is the security boundary that
/// replaced the helper process: `ActiveXObject`, `WScript`, `Enumerator` and every file and network
/// global are left undefined in the context, so the only way out of the sandbox is a member that
/// exists here, and every one of them is a value read off an immutable snapshot or a typed command
/// posted back to the host. Nothing here touches `AudioEngine`, AppKit, or the file system.
///
/// Member lookup is **case-insensitive**. WMP's objects are IDispatch, and the corpus spells the
/// same member both ways in the same file (`player.currentMedia.getItemInfo` and
/// `player.currentmedia.getiteminfo`); a case-sensitive bridge answers `undefined` for a call that
/// works in WMP.
///
/// Used only from `WMPScriptContext`'s serial queue.
final class WMPObjectModel {
    // Per-session state.
    var snapshot = WMPHostSnapshot()
    var preferences: [String: String] = [:]
    var currentViewID = ""
    /// **The display the skin is on, for WMP's `event` object.** `event.screenWidth` /
    /// `event.screenHeight` are the one part of that object that has an answer outside a live
    /// input event, and a skin reads them to decide how far its own window may grow:
    /// `Compact.wmz` opens both of its drawers with `view.maxWidth = event.screenWidth` before it
    /// widens the view, so with `event` undefined the assignment threw a `ReferenceError` and took
    /// the rest of `TogglePlaylist`/`ToggleSettings` — the growth and the slide — with it. Reported
    /// as "drawer controls don't work in compact wmp skin" (W184). Set per transaction from the
    /// window's own screen; the default is the harness's, so a headless sweep answers the same
    /// numbers on every machine.
    var screen = WMPObjectModel.defaultScreen

    /// What a transaction with no window behind it answers. Deliberately a constant rather than
    /// `NSScreen.main`: the corpus sweep compares captures across machines, and a screen-derived
    /// number would move every `max`-clamped layout with the display it was measured on.
    static let defaultScreen = WMPSize(width: 1920, height: 1080)

    /// The modifiers the transaction's own input event carried, answered as `event.shiftKey` and
    /// its two siblings. Empty outside an input transaction.
    var eventModifiers: WMPEventModifiers = []
    /// The key this transaction's own event carried, answered as `event.keyCode` — the member
    /// **405 of the 409** `event.` reads in the corpus's key handlers are (W53). Nil outside a
    /// keystroke.
    var eventKeyCode: Int?
    /// The mouse button this transaction's own event carried, answered as `event.button` — IE's
    /// numbering, which WMP inherits. Nil outside a mouse event; see `WMPJScriptEvent.button`.
    var eventButton: Int?
    /// Where the pointer is, in the view's top-left client coordinates, answered as
    /// `event.clientX`/`event.clientY`. Nil where no window could be asked.
    var eventPointer: WMPPoint?
    /// The element that raised this transaction's event, answered as `event.srcElement`. Both
    /// addresses are carried and resolved stable id first, for the same reason `WMPScriptContext`'s
    /// `eventOwner` is: an identifier is unique neither across views (W89) nor, in a malformed
    /// skin, within one — and the id where the stable id names no element installed here.
    var eventTargetID: String?
    var eventTargetStableID: Int?
    var elements: [String: WMPScriptElement] = [:]
    private var elementOrder: [String] = []
    /// Elements whose id an earlier node of the view already holds, by stable id. A script name
    /// reaches only the first declaration, but the host still addresses the later one by its node:
    /// `The_Sentinel` declares its EQ drawer panels `eq1`…`eq3` and then band sliders under the same
    /// ids, and a slider dropped from the registry had no element for its drag to write `value` to.
    private var shadowedElements: [Int: WMPScriptElement] = [:]
    /// The preset the skin last selected. WMP tracks one; the engine has no notion of a current
    /// preset, so it is session state and every selection is applied as ten band commands.
    var currentPresetIndex = 0
    /// What `player.mediaCollection` and `player.playlistCollection` answer from — the library
    /// browser's selected source, read-only (W66/W136). Session state the host replaces whole.
    private(set) var library = WMPLibraryCatalog.empty
    /// What this transaction asked of the library that the catalog does not hold yet —
    /// `playlist:<id>`, `query:<attribute>:<value>` or `play:<playlist path>`. The host fetches them and hands back a
    /// fuller catalog; until then the skin is answered with what is loaded, which is empty.
    private(set) var libraryDemands: Set<String> = []
    /// Set when this transaction assigned a playlist that could not play yet; see the
    /// `player.currentPlaylist` write.
    private var libraryPlayWithheld = false
    /// `<LISTBOX>` selections the script *wrote* this transaction. Reporting the selection as state
    /// on every transaction let one that started before a fast click put the old row back under
    /// the pointer; a write is the only thing that should move the highlight.
    private var listSelectionWrites: [Int: Int] = [:]

    /// A new catalog. **A different source is a different library**: a pane still pointed at
    /// a playlist id from the old one would show nothing, or the wrong server's list, so every pane
    /// goes back to the live queue and nothing is the current library playlist any more.
    /// The rows each shown library playlist draws, built once per catalog. A pane can show a
    /// library-sized playlist and `widgetState()` runs every transaction; rebuilding the rows each
    /// time is what made a large playlist cost a full pass per tick. Sharing the array also lets the
    /// host's equality check stop at the buffer.
    private var playlistRowsCache: [String: WMPWidgetScriptState.PlaylistRows] = [:]

    func replaceLibrary(_ catalog: WMPLibraryCatalog) {
        playlistRowsCache.removeAll()
        if catalog.sourceID != library.sourceID {
            currentLibraryPlaylist = nil
            queueGeneration += 1
            // A search result is a list of the old catalog's track numbers; kept across a switch it
            // named the new source's tracks at those positions, and came back as a stale search.
            scratchPlaylists.removeAll()
        }
        library = catalog
    }
    /// Playlists a skin built with `player.newPlaylist()` — `WoW`'s search results. Session state,
    /// never saved: WMP's own `newPlaylist` is not in the library until something adds it, and
    /// adding is the write a skin is refused. Oldest dropped past the cap.
    private var scratchPlaylists: [(serial: Int, tracks: [Int])] = []
    /// **The library playlist that became the current one** (W136). In WMP that object *is*
    /// `player.currentPlaylist` from then on: a control showing it shows the live queue — what the
    /// user adds or replaces from anywhere — and its name is the current playlist's name, which is
    /// how `WoW` finds it again (`nList` → `getByName`). Without this the pane kept a frozen copy
    /// and every queue change made outside the skin looked lost.
    private(set) var currentLibraryPlaylist: String?

    func adoptCurrentLibraryPlaylist(_ reference: String) {
        currentLibraryPlaylist = reference
    }

    /// **Bumped whenever the host's queue changes, from anywhere** (W136). A `<PLAYLIST>` pointed
    /// at a library playlist or a search result shows it only until the user's queue next
    /// changes: adding an artist or replacing the queue from the library browser puts the live
    /// queue back in front of them, rather than leaving the pane on a list that hides the change.
    private(set) var queueGeneration = 0
    private var lastSeenQueue: [WMPPlaylistItemSnapshot]?

    /// The library playlist a `<PLAYLIST>` shows, or nil when it shows the live queue.
    private func libraryPlaylistShown(by element: WMPScriptElement) -> String? {
        guard Self.isPlaylist(element.kind), let value = element.properties["playlist"],
              let reference = Self.objectReference(value),
              reference.hasPrefix(Self.libraryPathPrefix) else { return nil }
        guard element.libraryPlaylistGeneration == queueGeneration,
              reference != currentLibraryPlaylist else {
            element.properties["playlist"] = .string(Self.objectReferencePrefix + "player.currentplaylist")
            return nil
        }
        return reference
    }
    private var nextScratchSerial = 0
    private static let maximumScratchPlaylists = 16

    // Per-transaction output.
    private(set) var calls: [WMPJScriptCall] = []
    private(set) var mutations: [WMPJScriptMutation] = []
    private(set) var hostCommands: [WMPJScriptHostCommand] = []
    private(set) var preferenceWrites: [WMPJScriptPreferenceMutation] = []
    private(set) var repaintHints: [String] = []
    /// Elements whose `moveTo`/`alphaBlendTo` endpoint landed this transaction, in call order, as
    /// `(stableID, event)`. `WMPScriptContext.raiseCompletionHandlers` turns each into the
    /// `onEndMove`/`onEndAlphaBlend` the skin authored — the callback a sequence chains its next
    /// step from (W55). Recorded here rather than dispatched here because the model has no view
    /// plan and therefore no handler sources; it knows only that a call completed.
    private(set) var completions: [(stableID: Int, event: String)] = []
    /// Endpoints of `moveTo`/`resizeTo`/`alphaBlendTo` calls that named a duration, held until the
    /// handler that made them returns. See `flushPendingTweens()`.
    private var pendingTweens: [(element: WMPScriptElement, property: String, value: WMPJSONValue)] = []
    /// **Whether this transaction's caller has a frame clock (W194).** A window does; a render
    /// dump, a corpus sweep and the windowless dispatcher do not, and for them a tween's only
    /// honest answer is its settled state — which is what `pendingTweens` above lands and what
    /// every measurement on this subsystem was taken against. Only a transaction with a clock
    /// produces `tweens`, so the two paths agree on where the motion ends and differ only in
    /// whether anything is drawn on the way there.
    var animatesTweens = false
    /// The tweens this transaction asked the host to animate, in call order.
    private(set) var tweens: [WMPScriptTween] = []
    private(set) var diagnostics: [WMPJScriptDiagnostic] = []
    /// **Where `view.size(corner)` was called, counted in mutations.** WMP's `view.size` blocks
    /// until the user releases the button, so everything a handler writes *after* it happens when
    /// the drag is over — and a skin's resize bracket is built entirely out of that. Nothing here
    /// can block, so the split point is recorded instead and `WMPScriptRuntime` holds the tail.
    /// The first call wins: a second `view.size` in the same handler cannot start a second drag.
    private(set) var resizeCallMutationIndex: Int?
    /// Reads made since the last `beginDependencyCapture()`, in order. One expression's dependency
    /// list; the topological sort is built out of these.
    private(set) var dependencyReads: [String] = []
    private var capturingDependencies = false

    private static let maximumCalls = 4_096

    // MARK: Transaction lifecycle

    func beginTransaction(snapshot: WMPHostSnapshot, preferences: [String: String], viewID: String,
                          screen: WMPSize = WMPObjectModel.defaultScreen,
                          modifiers: WMPEventModifiers = [], keyCode: Int? = nil,
                          button: Int? = nil, pointer: WMPPoint? = nil,
                          targetID: String? = nil, targetStableID: Int? = nil) {
        self.snapshot = snapshot
        libraryDemands.removeAll()
        libraryPlayWithheld = false
        listSelectionWrites.removeAll()
        if lastSeenQueue?.isSameQueue(as: snapshot.playlistItems) != true {
            if lastSeenQueue != nil { queueGeneration += 1 }
        }
        lastSeenQueue = snapshot.playlistItems
        self.preferences = preferences
        currentViewID = viewID
        self.screen = screen
        eventModifiers = modifiers
        eventKeyCode = keyCode
        eventButton = button
        eventPointer = pointer
        eventTargetID = targetID
        eventTargetStableID = targetStableID
        calls.removeAll(keepingCapacity: true)
        mutations.removeAll(keepingCapacity: true)
        hostCommands.removeAll(keepingCapacity: true)
        preferenceWrites.removeAll(keepingCapacity: true)
        repaintHints.removeAll(keepingCapacity: true)
        diagnostics.removeAll(keepingCapacity: true)
        resizeCallMutationIndex = nil
        dependencyReads.removeAll(keepingCapacity: true)
        completions.removeAll(keepingCapacity: true)
        tweens.removeAll(keepingCapacity: true)
    }

    func beginDependencyCapture() {
        dependencyReads.removeAll(keepingCapacity: true)
        capturingDependencies = true
    }

    func endDependencyCapture() -> [String] {
        capturingDependencies = false
        return dependencyReads
    }

    func warn(_ code: String, _ message: String) {
        guard diagnostics.count < 256 else { return }
        diagnostics.append(.init(code: code, message: message))
    }

    // MARK: Elements

    func resetElements(_ elements: [WMPScriptElement]) {
        self.elements = [:]
        elementOrder = []
        shadowedElements = [:]
        for element in elements {
            let key = WMPPath.fold(element.id)
            guard self.elements[key] == nil else {
                shadowedElements[element.stableID] = element
                continue
            }
            self.elements[key] = element
            elementOrder.append(key)
        }
    }

    /// The live element objects of one view, lifted out whole.
    ///
    /// A windowless dispatcher view runs a transaction of its own while another view is on screen
    /// (W89), and the two cannot share a registry: element ids collide — every view root is `view`
    /// — and rebuilding the presented view's elements afterwards would discard the state a skin
    /// keeps in them between clicks. So the background view's registry is swapped in for the length
    /// of its transaction and the presented one swapped back, objects and all. The JavaScript
    /// globals need no part in this: each is a wrapper around the folded id, resolved through
    /// whichever registry is installed at the moment it is read.
    struct ElementRegistry {
        fileprivate let elements: [String: WMPScriptElement]
        fileprivate let order: [String]
        fileprivate let shadowed: [Int: WMPScriptElement]

        func element(stableID: Int) -> WMPScriptElement? {
            shadowed[stableID] ?? elements.values.first { $0.stableID == stableID }
        }
    }

    func captureElements() -> ElementRegistry {
        .init(elements: elements, order: elementOrder, shadowed: shadowedElements)
    }

    func restoreElements(_ registry: ElementRegistry) {
        elements = registry.elements
        elementOrder = registry.order
        shadowedElements = registry.shadowed
    }

    var elementIDs: [String] { elementOrder }

    /// Every *other* live view's elements, folded id first, for the one lookup that is allowed to
    /// leave the installed view (W40).
    ///
    /// A skin's views share one script scope, so a function declared in the shared `.js` is called
    /// from whichever view's handler reaches it first and names elements of the view it was written
    /// for: `Creed`'s `InfoPopup` runs the setup that configures `MainPlayer`'s `PlaylistFrame`,
    /// `holiday_skin`'s `Globe` hides `gingerbread`'s `videoLayer`, and `WWC`'s video-view volume
    /// slider clears `mainView`'s `mute`. In WMP those elements exist for as long as the theme does;
    /// here the registries are swapped one at a time, so the name resolved against the installed
    /// view and answered `no such element` — or threw `Can't find variable` outright when the
    /// holding view had never been opened at all.
    ///
    /// **The installed view always wins.** Ids are unique per view and not across them (W89) — every
    /// view root is `view` — so this is a fallback and never a merge.
    private var otherViewElements: [String: WMPScriptElement] = [:]

    func setOtherViewElements(_ registries: [ElementRegistry]) {
        otherViewElements = [:]
        for registry in registries {
            for (key, element) in registry.elements where otherViewElements[key] == nil {
                otherViewElements[key] = element
            }
        }
    }

    /// The element a receiver address names: the installed view first, then any other live view.
    private func liveElement(_ key: String) -> WMPScriptElement? {
        elements[key] ?? otherViewElements[key] ?? duplicateElement(key)
    }

    /// `#<stableID>`: the receiver key of an element whose id an earlier node of the view holds,
    /// which is how a handler is scoped to the node that raised it. See `shadowedElements`.
    private func duplicateElement(_ key: String) -> WMPScriptElement? {
        guard key.hasPrefix("#"), let stableID = Int(key.dropFirst()) else { return nil }
        return shadowedElements[stableID]
    }

    /// The receiver key that reaches exactly this element: its id, unless an earlier node of the
    /// view holds the id, in which case its stable id.
    func receiverKey(for element: WMPScriptElement) -> String {
        shadowedElements[element.stableID] === element ? "#\(element.stableID)" : WMPPath.fold(element.id)
    }

    func element(_ id: String) -> WMPScriptElement? { elements[WMPPath.fold(id)] }

    /// The element a stable id names. The dispatch sites know which *node* was hit even where the
    /// markup authored no `id`, and an element's identifier is not unique across views (W89), so
    /// this is the address that always answers.
    func element(stableID: Int) -> WMPScriptElement? {
        shadowedElements[stableID] ?? elements.values.first { $0.stableID == stableID }
    }

    // MARK: Member access

    /// `path` is a receiver address: a host object path (`player.controls`), `element:<id>`, or
    /// `playlistitem:<index>`.
    func get(_ path: String, _ member: String) -> WMPMemberValue {
        var result = read(path: path, member: member)
        if case .unrecognised = result, let element = shadowedElement(path) {
            result = read(path: element, member: member)
        }
        record(path: path, member: member, kind: .read, result: result)
        return result
    }

    @discardableResult
    func set(_ path: String, _ member: String, _ value: WMPJSONValue) -> WMPMemberValue {
        var result = write(path: path, member: member, value: value)
        if case .unrecognised = result, let element = shadowedElement(path) {
            result = write(path: element, member: member, value: value)
        }
        record(path: path, member: member, kind: .write, result: result, written: value)
        return result
    }

    func invoke(_ path: String, _ member: String, _ arguments: [WMPJSONValue]) -> WMPMemberValue {
        var result = call(path: path, member: member, arguments: arguments)
        if case .unrecognised = result, let element = shadowedElement(path) {
            result = call(path: element, member: member, arguments: arguments)
        }
        record(path: path, member: member, kind: .invoke, result: result)
        return result
    }

    /// **The skin's own element named `eq` answers what the equaliser does not (W309).** `eq` is
    /// bound as a host global over any element of that name, so `eq.visible = false` reached
    /// `write(path: "eq")`, came back unrecognised and killed the handler — and `US Army`'s
    /// `playlistpop()` and its three siblings set their open/closed flag *after* that line, so
    /// every toggle button opened its pane and never closed it again. In WMP `eq` is only ever the
    /// element (`<equalizerSettings id="eq">`, or `Navigator`'s `<SUBVIEW id="eq">`), so its open
    /// property surface is the honest fallback once the equaliser has declined the member.
    private func shadowedElement(_ path: String) -> String? {
        path == "eq" && liveElement("eq") != nil ? "element:eq" : nil
    }

    /// Does this receiver answer this member at all? Used by the `with` scope a geometry
    /// expression is evaluated in, so an identifier the element does not own falls through to the
    /// globals instead of being claimed and then failing.
    func recognises(_ path: String, _ member: String) -> Bool {
        let name = member.lowercased()
        if path.hasPrefix("element:") {
            let key = String(path.dropFirst("element:".count))
            guard let element = elements[key] ?? duplicateElement(key) else { return false }
            // Deliberately **not** the open property surface the read path answers with. Inside a
            // `with` scope this trap decides whether an identifier belongs to the element or to the
            // globals, and an element that claims every name swallows the skin's own functions:
            // Corona's `GetEqSliderLeft(1)` resolved to an empty string and all ten equaliser
            // sliders lost their geometry.
            if name == "id" { return true }
            // **An authored *handler* attribute is not a name the element owns in scope (W216).**
            // `<VIEW onLoad="OnLoad();">` authors `onload`, so an element that claims every
            // attribute it declares answers the bare `OnLoad` in its own handler with the
            // attribute's text instead of letting the skin's function of that name resolve —
            // `corona`'s whole startup died on `OnLoad is not a function`. WMP raises these; it
            // does not expose them as properties, and nothing in the corpus reads one back.
            if name.hasPrefix("on") || name.hasSuffix("_onchange") { return false }
            if element.properties[name] != nil { return true }
            if element.authored.contains(name) { return true }
            if Self.standardElementProperties.contains(name) { return true }
            // The computed properties `readElement` answers from the host rather than from the
            // element's own state. They are not authored and not standard, so without them a
            // handler's bare `textWidth` falls through to the globals and throws while the
            // qualified `metadata.textWidth` beside it answers — `Asia`'s marquee is the case:
            // `onEndMove="scrolling = textWidth > width"`.
            if Self.computedElementProperties(element).contains(name) { return true }
            if elementMethod(element, name) != nil { return true }
            if element.kind == .view, readViewHost(name) != nil { return true }
            return false
        }
        let answer = read(path: path, member: member)
        resolutionOverride = nil
        if case .unrecognised = answer { return false }
        return true
    }

    /// The trace path a census row is keyed by: `player.controls.play`, `svmain.left`. Element
    /// receivers print as the bare element id, which is how the skin spelled them.
    static func tracePath(_ path: String, _ member: String) -> String {
        let receiver: String
        if path.hasPrefix("element:") { receiver = String(path.dropFirst("element:".count)) }
        else if path.hasPrefix("playlistitem:") { receiver = "player.currentplaylist.item" }
        else if path.hasPrefix(libraryPathPrefix) {
            receiver = String(path.prefix { $0 != ":" })
        }
        else { receiver = path }
        return "\(receiver).\(member.lowercased())"
    }

    private func record(path: String, member: String, kind: WMPJScriptCall.Kind,
                        result: WMPMemberValue, written: WMPJSONValue? = nil) {
        let trace = Self.tracePath(path, member)
        if capturingDependencies, kind == .read { dependencyReads.append(trace) }
        guard calls.count < Self.maximumCalls else { return }
        let resolution: WMPMemberResolution
        var value: WMPJSONValue?
        switch result {
        case let .value(item): resolution = resolutionOverride ?? .live; value = written ?? item
        case .object, .function: resolution = resolutionOverride ?? .live; value = nil
        case .unrecognised: resolution = .unrecognised; value = nil
        }
        resolutionOverride = nil
        calls.append(WMPJScriptCall(path: trace, kind: kind, value: value, resolution: resolution))
    }

    /// Set by a member implementation that answers without a host behind it. Consumed by the very
    /// next `record`, which is always the one for that member.
    private var resolutionOverride: WMPMemberResolution?
    private func inert() { resolutionOverride = .inert }

    // MARK: - The library (W66/W136)
    //
    // Every object `mediaCollection`/`playlistCollection` hands out is a *query*, addressed by a
    // path that restates it: `library.playlists:all`, `library.query:genre:Rock`,
    // `library.playlist:3`, `library.media:120`. Nothing is allocated per call and a reference a
    // skin keeps across transactions (`playlist1.playlist = …`) still resolves in the next one.

    static let libraryPathPrefix = "library."
    /// How a host object travels through a JS *value*: `x.playlist = pl` or
    /// `player.currentPlaylist = pl` hand the proxy itself to `__wmpSet`, which has only JSON to
    /// carry it in. `WMPScriptContext.jsonValue` spells a proxy this way.
    static let objectReferencePrefix = "\u{1}wmpobject:"

    static func objectReference(_ value: WMPJSONValue) -> String? {
        guard let string = value.string, string.hasPrefix(objectReferencePrefix) else { return nil }
        return String(string.dropFirst(objectReferencePrefix.count))
    }

    static func libraryPath(_ kind: String, _ parts: String...) -> String {
        let escaped = parts.map {
            $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        }
        return libraryPathPrefix + kind + ":" + escaped.joined(separator: ":")
    }

    /// The playlist id a `library.playlist:<id>` reference names, for the host.
    static func libraryPlaylistID(inReference reference: String) -> String? {
        guard reference.hasPrefix(libraryPathPrefix) else { return nil }
        let (kind, parts) = libraryParts(reference)
        return kind == "playlist" ? parts.first : nil
    }

    private static func libraryParts(_ path: String) -> (kind: String, parts: [String]) {
        let body = path.dropFirst(libraryPathPrefix.count)
        let pieces = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        return (pieces.first ?? "", pieces.dropFirst().map { $0.removingPercentEncoding ?? $0 })
    }

    /// The playlists a `library.playlists:` array holds, as indices into `library.playlists`.
    /// `all` is the whole list and is answered without building it: `count` and `item(i)` are
    /// called once per playlist in a fill loop.
    private func libraryPlaylists(_ parts: [String]) -> [Int]? {
        if parts.first == "name" { return library.playlists(named: parts.count > 1 ? parts[1] : "") }
        return nil
    }

    /// The tracks a playlist-shaped path holds, as indices into `library.tracks`; nil for a path
    /// that is not a playlist.
    private func libraryTracks(_ path: String) -> [Int]? {
        guard path.hasPrefix(Self.libraryPathPrefix) else { return nil }
        let (kind, parts) = Self.libraryParts(path)
        switch kind {
        case "playlist":
            guard let id = parts.first, let index = library.playlistIndex(id: id) else { return [] }
            guard library.playlists[index].loaded else {
                libraryDemands.insert("playlist:" + id)
                return []
            }
            return library.playlists[index].tracks
        case "scratch":
            let serial = parts.first.flatMap(Int.init)
            return scratchPlaylists.first { $0.serial == serial }?.tracks ?? []
        case "query":
            guard let first = parts.first, first != "all" else { return allLibraryTracks() }
            guard let attribute = WMPLibraryCatalog.attribute(first) else { return [] }
            let value = parts.count > 1 ? parts[1] : ""
            // A server is never asked for everything of one media type — `WoW`'s "All Music" —
            // or for a title: those are filtered from what has been loaded.
            if library.isComplete || attribute == .mediaType || attribute == .title
                || attribute == .sourceURL {
                return library.tracks(where: attribute, equals: value)
            }
            let key = WMPLibraryCatalog.queryKey(attribute, value)
            if let answered = library.queryResults[key] { return answered }
            libraryDemands.insert("query:" + key)
            return []
        default: return nil
        }
    }

    /// What the skin's own controls show beyond their rows — see `WMPWidgetScriptState`.
    func widgetState() -> WMPWidgetScriptState {
        var state = WMPWidgetScriptState()
        // An alias is a second key for the same element, and writes the same entry twice.
        for element in elements.values {
            if let reference = libraryPlaylistShown(by: element) {
                if let cached = playlistRowsCache[reference] {
                    state.playlists[element.stableID] = cached
                } else if let tracks = libraryTracks(reference) {
                    let rows = WMPWidgetScriptState.PlaylistRows(reference: reference, items: tracks.map {
                        let track = library.tracks[$0]
                        return WMPPlaylistItemSnapshot(title: track.title, artist: track.artist,
                                                       duration: track.duration,
                                                       sourceURL: track.sourceURL)
                    }, tracks: tracks)
                    // An unloaded server playlist answers empty until its fetch lands, and a
                    // scratch playlist grows while a search fills it: neither is final yet.
                    if !tracks.isEmpty, !reference.hasPrefix(Self.libraryPathPrefix + "scratch:") {
                        playlistRowsCache[reference] = rows
                    }
                    state.playlists[element.stableID] = rows
                }
            }
            if element.kind == .editBox, let value = element.properties["value"]?.string {
                state.editValues[element.stableID] = value
            }
            if element.kind == .listBox, let index = listSelectionWrites[element.stableID] {
                state.listSelections[element.stableID] = index
            }
        }
        return state
    }

    /// `mediaCollection.getAll()`. A server's whole library is far too large to hand a skin —
    /// tens of thousands of tracks walked in a 0.25 s handler — so on a server the only caller that
    /// wants it, a skin's own search (`WoW`'s `onMlSearch`: `getAll()`, then filter each item by the
    /// text), is answered with **the server's search for the text in this view's search box**
    /// (W136). The first answer is empty and demands the search; the host runs the same event again
    /// when the results land, and the skin's loop filters them exactly as it would the library.
    /// With no search text it is what has been loaded, as before.
    private func allLibraryTracks() -> [Int] {
        // Only the user's own act is a search. A skin's `onLoad`, a timer, or the refresh the host
        // runs after a source switch reading `getAll()` with an old term still in the box used to
        // run that search again — the search that "kept coming back" on every source switch.
        guard !library.isComplete, Self.userInputEvents.contains(eventName ?? ""),
              let text = searchBoxText() else { return library.libraryTracks }
        let key = "search:" + text.lowercased()
        if let answered = library.queryResults[key] { return answered }
        libraryDemands.insert("query:" + key)
        return []
    }

    /// The name of the event this transaction runs, set per transaction by the context.
    var eventName: String?

    private static let userInputEvents: Set<String> = [
        "click", "dblclick", "keyup", "keydown", "keypress", "mousedown", "mouseup"
    ]

    /// The text in this view's `<EDITBOX>`, when there is exactly one with something in it.
    private func searchBoxText() -> String? {
        var seen = Set<Int>(), texts: [String] = []
        for element in elements.values where element.kind == .editBox
            && seen.insert(element.stableID).inserted {
            if let text = element.properties["value"]?.string?.trimmingCharacters(in: .whitespaces),
               !text.isEmpty { texts.append(text) }
        }
        return texts.count == 1 ? texts[0] : nil
    }

    private func libraryPlaylistName(_ path: String) -> String {
        let (kind, parts) = Self.libraryParts(path)
        if kind == "playlist", let id = parts.first, let index = library.playlistIndex(id: id) {
            return library.playlists[index].name
        }
        return parts.count > 1 ? parts[1] : "Library"
    }

    private func readLibrary(_ path: String, _ name: String) -> WMPMemberValue {
        let (kind, parts) = Self.libraryParts(path)
        switch kind {
        case "playlists":
            switch name {
            case "count":
                return .value(.number(Double(libraryPlaylists(parts)?.count ?? library.playlists.count)))
            case "item": return .function
            default: return .unrecognised("playlistArray member")
            }
        case "strings":
            switch name {
            case "count":
                guard let attribute = WMPLibraryCatalog.attribute(parts.first ?? "") else {
                    return .value(.number(0))
                }
                return .value(.number(Double(library.strings(of: attribute,
                    mediaType: parts.count > 1 ? parts[1] : "").count)))
            case "item": return .function
            default: return .unrecognised("stringCollection member")
            }
        case "playlist", "query", "scratch":
            switch name {
            // Only `count` needs the tracks. Reading them for every member made a chooser's fill
            // loop — `playlistArray.item(i).getItemInfo("Title")` — demand every server playlist's
            // tracks: 1,850 serial fetches on Jellyfin for a list of names (W274).
            case "count": return .value(.number(Double((libraryTracks(path) ?? []).count)))
            case "name": return .value(.string(libraryPlaylistName(path)))
            case "item", "getiteminfo", "attributecount", "getattributename": return .function
            case "appenditem" where kind == "scratch", "clear" where kind == "scratch": return .function
            default: return .unrecognised("playlist member")
            }
        case "media":
            // A reference from a catalog that has since been replaced — the source switched under a
            // skin still holding a search result — is an empty media item, not an error: WMP's
            // media objects always answer, and `NVIDIA`'s `updatePlInfo()` threw on every
            // `playlist_onChange` after a switch.
            guard let index = parts.first.flatMap(Int.init), library.tracks.indices.contains(index)
            else {
                switch name {
                case "name", "sourceurl", "durationstring": return .value(.string(""))
                case "duration": return .value(.number(0))
                case "getiteminfo", "getiteminfobyatom": return .function
                default: return .unrecognised("media member")
                }
            }
            let track = library.tracks[index]
            switch name {
            case "name": return .value(.string(track.title))
            case "sourceurl": return .value(.string(track.sourceURL))
            case "duration": return .value(.number(track.duration))
            case "durationstring": return .value(.string(Self.timeString(track.duration)))
            case "getiteminfo", "getiteminfobyatom": return .function
            default: return .unrecognised("media member")
            }
        default: return .unrecognised("unknown library object")
        }
    }

    /// The attribute names `getMediaAtom` numbers, by atom. Any stable numbering will do: a skin
    /// only ever hands the number straight back to `getItemInfoByAtom`.
    private static let mediaAtoms = ["title", "author", "artist", "wm/albumtitle", "album",
                                     "wm/albumartist", "wm/genre", "genre", "mediatype", "sourceurl"]

    private func callLibrary(_ path: String, _ name: String,
                             _ arguments: [WMPJSONValue]) -> WMPMemberValue {
        let (kind, parts) = Self.libraryParts(path)
        let index = Int(arguments.first?.number ?? -1)
        switch (kind, name) {
        case ("playlists", "item"):
            let resolved: Int?
            if let named = libraryPlaylists(parts) {
                resolved = named.indices.contains(index) ? named[index] : nil
            } else {
                resolved = library.playlists.indices.contains(index) ? index : nil
            }
            guard let resolved else { return .value(.null) }
            return .object(Self.libraryPath("playlist", library.playlists[resolved].id))
        case ("strings", "item"):
            guard let attribute = WMPLibraryCatalog.attribute(parts.first ?? "") else { return .value(.null) }
            let strings = library.strings(of: attribute, mediaType: parts.count > 1 ? parts[1] : "")
            return .value(strings.indices.contains(index) ? .string(strings[index]) : .null)
        case ("playlist", "item"), ("query", "item"), ("scratch", "item"):
            let tracks = libraryTracks(path) ?? []
            guard tracks.indices.contains(index) else { return .value(.null) }
            return .object(Self.libraryPath("media", String(tracks[index])))
        // Playlist-level attributes. The one the corpus reads is the title (`WoW`'s chooser is
        // `playlistArray.item(i).getItemInfo("Title")`); the rest are decorations this player's
        // playlists never carry, and the empty string is WMP's answer for an absent one.
        case ("playlist", "getiteminfo"), ("query", "getiteminfo"), ("scratch", "getiteminfo"):
            let attribute = (arguments.first?.string ?? "").lowercased()
            return .value(.string(attribute == "title" || attribute == "name"
                ? libraryPlaylistName(path) : ""))
        case ("playlist", "attributecount"), ("query", "attributecount"), ("scratch", "attributecount"):
            return .value(.number(1))
        case ("playlist", "getattributename"), ("query", "getattributename"),
             ("scratch", "getattributename"):
            return .value(.string(index == 0 ? "Title" : ""))
        // A skin's own playlist is the one thing it may change: `WoW`'s search appends each hit.
        case ("scratch", "appenditem"):
            guard let serial = parts.first.flatMap(Int.init),
                  let slot = scratchPlaylists.firstIndex(where: { $0.serial == serial }),
                  let reference = arguments.first.flatMap(Self.objectReference),
                  reference.hasPrefix(Self.libraryPathPrefix + "media:"),
                  let track = Self.libraryParts(reference).parts.first.flatMap(Int.init),
                  library.tracks.indices.contains(track),
                  scratchPlaylists[slot].tracks.count < 10_000 else { return .value(.null) }
            scratchPlaylists[slot].tracks.append(track)
            return .value(.null)
        case ("scratch", "clear"):
            let serial = parts.first.flatMap(Int.init)
            if let slot = scratchPlaylists.firstIndex(where: { $0.serial == serial }) {
                scratchPlaylists[slot].tracks.removeAll()
            }
            return .value(.null)
        case ("media", "getiteminfo"), ("media", "getiteminfobyatom"):
            var attributeName = arguments.first?.string ?? ""
            if name == "getiteminfobyatom", let atom = arguments.first?.number {
                let index = Int(atom)
                attributeName = Self.mediaAtoms.indices.contains(index) ? Self.mediaAtoms[index] : ""
            }
            guard let track = parts.first.flatMap(Int.init),
                  let attribute = WMPLibraryCatalog.attribute(attributeName) else {
                return .value(.string(""))
            }
            return .value(.string(library.value(of: attribute, track: track)))
        default: return .unrecognised("library method")
        }
    }

    // MARK: - Reads

    private func read(path: String, member: String) -> WMPMemberValue {
        let name = member.lowercased()
        if path.hasPrefix("element:") {
            guard let element = liveElement(String(path.dropFirst("element:".count))) else {
                return .unrecognised("no such element")
            }
            // **The name a skin gave its `<EQUALIZERSETTINGS>` is another spelling of `eq` (W256).**
            //
            // `eq` is a bound global on the *path* `eq`, so the routing below reached `readEqualizer` only
            // for that one identifier: `<equalizerSettings id="ElvisEQS">` is an ordinary element, and
            // `ElvisEQS.gainLevel1 = value` therefore landed in the element's own property bag — it
            // round-tripped through the bag, changed no audio, and the band slider bound to
            // `wmpprop:ElvisEQS.gainLevel1` never moved, because that binding resolves from the host.
            // Reported live as "an equaliser slider cannot be dragged" on `elvis`. **7 of the 184
            // measured archives name it something other than `eq`** — `scripts/wmp_slider_drag_census.py`.
            //
            // The element still answers everything the equaliser does not: `readEqualizer` ends in
            // `unrecognised`, and a handler dies on its first unrecognised member, so an `<EQUALIZERSETTINGS>`
            // property this engine has never heard of must keep falling through to the open element
            // surface rather than aborting the handler that sets it.
            //
            // **The three the element keeps are the three it is the right home for.**
            // `enableSplineTension`, `splineTension` and `bypass` are `inertEqualizerSettingsProperties`:
            // bookkeeping this engine has no DSP for, whose authored value a skin reads straight
            // back (W134). Those stay the element's, so a named `<EQUALIZERSETTINGS>` answers its
            // own markup exactly as it always has; only the members that reach the audio are
            // routed.
            if element.kind == .equalizerSettings,
               !Self.inertEqualizerSettingsProperties.contains(name) {
                let answer = readEqualizer(name)
                if case .unrecognised = answer {} else { return answer }
            }
            return readElement(element, name)
        }
        if path.hasPrefix(Self.libraryPathPrefix) { return readLibrary(path, name) }
        if path.hasPrefix("playlistitem:") {
            guard let index = Int(path.dropFirst("playlistitem:".count)),
                  snapshot.playlistItems.indices.contains(index) else {
                return .unrecognised("no such playlist item")
            }
            let item = snapshot.playlistItems[index]
            switch name {
            case "name": return .value(.string(item.title))
            // **Not the title.** `Compact` asks whether item 0 starts with `wmpdvd:` and
            // `digitaldj`'s query filter drops any item whose URL contains `://` or ends `.asx`
            // — both were reading a track name as a URL (W41).
            case "sourceurl": return .value(.string(item.sourceURL))
            case "duration": return .value(.number(item.duration))
            case "durationstring": return .value(.string(WMPObjectModel.timeString(item.duration)))
            case "getiteminfo", "getiteminfobyatom": return .function
            default: return .unrecognised("playlist item member")
            }
        }
        switch path {
        case "player": return readPlayer(name)
        case "player.controls": return readControls(name)
        case "player.settings": return readSettings(name)
        case "player.currentmedia": return readMedia(name)
        case "player.currentplaylist": return readPlaylist(name)
        case "player.network": return readNetwork(name)
        case "player.dvd": return readDVD(name)
        case "player.playlistcollection":
            switch name {
            case "getall", "getbyname": return .function
            default: return .unrecognised("playlistCollection member (read-only)")
            }
        case "player.mediacollection":
            switch name {
            case "getall", "getbyattribute", "getbyalbum", "getbygenre", "getbyauthor", "getbyname",
                 "getattributestringcollection", "getmediaatom": return .function
            default: return .unrecognised("mediaCollection member (read-only)")
            }
        // **There is no CD drive, and saying so is the answer.** `WoW`'s `fillListBox()` walks
        // `cdromCollection.Count` between the "Now Playing" row and the playlists, so an
        // unrecognised collection aborted the fill before any playlist was appended.
        case "player.cdromcollection":
            switch name {
            case "count": return .value(.number(0))
            case "item", "getbydrivespecifier": return .function
            default: return .unrecognised("cdromCollection member")
            }
        case "eq": return readEqualizer(name)
        case "theme": return readTheme(name)
        case "event": return readEvent(name)
        case "mediacenter": return readMediaCenter(name)
        default: return .unrecognised("unknown host object")
        }
    }

    private func readPlayer(_ name: String) -> WMPMemberValue {
        switch name {
        case "controls": return .object("player.controls")
        case "settings": return .object("player.settings")
        case "currentmedia": return .object("player.currentmedia")
        case "currentplaylist": return .object("player.currentplaylist")
        case "network": return .object("player.network")
        case "playlistcollection": return .object("player.playlistcollection")
        case "newplaylist": return .function
        case "mediacollection": return .object("player.mediacollection")
        case "cdromcollection": return .object("player.cdromcollection")
        // **There is no DVD, and saying so is the answer rather than refusing the question.**
        // `Corona`'s metadata table opens with `player.dvd.isAvailable('dvd')==false` on all three
        // of its rows, so an unrecognised `dvd` aborted the handler that reads the track title —
        // and, further down the same chain, the one that turns its visualization pane on.
        case "dvd": return .object("player.dvd")
        // WMP reports these as numbers from its own enumerations, and skins compare them against
        // the `ps*`/`os*` globals rather than against strings.
        case "playstate": return .value(.number(Double(WMPScriptConstants.playState(for: snapshot.state))))
        case "openstate":
            return .value(.number(Double(WMPScriptConstants.openState(for: snapshot))))
        // Live since 2026-09-14 — see `WMPHostSnapshot.statusText` for the wording and for why
        // there is no buffering case. It must stay out of `inert()`: a member the runtime answers
        // has to leave the demand tally, which is how `alphaBlendTo` came to be ranked as the
        // largest open row while it worked.
        case "status": return .value(.string(snapshot.statusText))
        // **`player.fullScreen` is the Player's own property, not only the `<VIDEO>` element's.**
        //
        // 35 corpus archives read or write it, every Alienware/ALX frame among them, and an
        // unrecognised member aborts the handler it appears in. `alienware.js`'s
        // `onChangeVidPlayerState()` reaches `if(!player.fullScreen){ checkSnapStatus(); }` from
        // `onLoadVid()`, so the throw took the four statements after it with it — including
        // `toggleVidDrawer('0')`, which is what closes the video settings drawer at load.
        // Reported 2026-09-20 as "the video adjustment drawer is open by default".
        case "fullscreen": return .value(.bool(snapshot.video.fullScreen))
        case "isonline": inert(); return .value(.bool(true))
        case "enabled": inert(); return .value(.bool(true))
        case "versioninfo": inert(); return .value(.string("12.0.0.0"))
        default: return .unrecognised("player member")
        }
    }

    private func readControls(_ name: String) -> WMPMemberValue {
        switch name {
        case "currentposition": return .value(.number(snapshot.currentTime))
        case "currentpositionstring": return .value(.string(snapshot.elapsedText))
        case "currentitem": return .object("player.currentmedia")
        case "play", "pause", "stop", "next", "previous", "fastforward", "fastreverse",
             "isavailable", "playitem": return .function
        default: return .unrecognised("controls member")
        }
    }

    private func readSettings(_ name: String) -> WMPMemberValue {
        switch name {
        case "volume": return .value(.number((snapshot.volume * 100).rounded()))
        case "balance": return .value(.number((snapshot.balance * 100).rounded()))
        case "mute": return .value(.bool(snapshot.muted))
        case "getmode", "setmode", "getstring", "setstring": return .function
        case "autostart", "enableerrordialogs", "invokeurls":
            inert(); return .value(sessionSettings[name] ?? .bool(false))
        default: return .unrecognised("settings member")
        }
    }

    private func readMedia(_ name: String) -> WMPMemberValue {
        switch name {
        case "name": return .value(.string(snapshot.metadata.title))
        case "duration": return .value(.number(snapshot.duration))
        case "durationstring": return .value(.string(snapshot.durationText))
        // **`sourceURL` is what a skin asks before it asks anything else.** It was unrecognised, and
        // an unrecognised member aborts the handler that touched it — `Cablemusic` reads it on the
        // third line of the one function that fills its show/clip/author/copyright readouts, so
        // every one of them stayed empty through a whole track. Reported as "the track information
        // does not appear".
        case "sourceurl": return .value(.string(snapshot.metadata.sourceURL))
        case "getiteminfo", "getiteminfobyatom", "setiteminfo", "isreadonly": return .function
        // No video surface exists yet, so there is genuinely no image source. Zero is the true
        // answer rather than a placeholder, and it is what makes Corona take its audio path.
        case "imagesourcewidth": return .value(.number(snapshot.video.width))
        case "imagesourceheight": return .value(.number(snapshot.video.height))
        case "attributecount": return .value(.number(3))
        default: return .unrecognised("media member")
        }
    }

    private func readPlaylist(_ name: String) -> WMPMemberValue {
        switch name {
        case "count": return .value(.number(Double(snapshot.playlistCount)))
        case "name":
            if let currentLibraryPlaylist {
                return .value(.string(libraryPlaylistName(currentLibraryPlaylist)))
            }
            inert(); return .value(.string("Now Playing"))
        case "item", "getiteminfo", "attributecount", "getattributename": return .function
        default: return .unrecognised("playlist member")
        }
    }

    /// WMP's DVD control. This player has no DVD support at all, so `isAvailable` answers false
    /// and every other member stays unrecognised and ranks itself.
    private func readDVD(_ name: String) -> WMPMemberValue {
        switch name {
        case "isavailable": return .function
        case "domain": inert(); return .value(.string(""))
        default: return .unrecognised("dvd member")
        }
    }

    private func readNetwork(_ name: String) -> WMPMemberValue {
        switch name {
        // **`downloadProgress` is the corpus's most-read network member, and the count is not the
        // blast radius** (measured 2026-09-21, 184 archives, 400 script/markup files): 58 uses
        // across 42 archives, but **55 of them are `wmpprop:` bindings that already resolved** in
        // `WMPPropertyRegistry` — a separate resolution of the same path, right since W93. Only
        // **3 script reads, all in `tubeframe.wmz`**, reached this switch and aborted the handler.
        // So `object-model.md`'s "both already resolve" was true of a `<TEXT value=...>` binding
        // and false of a script read, and splitting the two is what found the one real case.
        //
        // **This answers `0`, and in `tubeframe` that is visibly wrong on purpose.** Its
        // `GetMetaData` prints `downloadProgress + "% downloaded"` whenever the value is under 100,
        // so the readout reads `Playing: 0% downloaded` rather than falling through to its bitrate
        // branch — the trap `WMPHost.statusText` names, now reached instead of predicted. The
        // alternative was a constant 100, which is the truer answer for a player where the media
        // has always fully arrived, but it would flip ~36 archives' buffer bars from empty to full
        // off one unmeasured constant. Answering the field this engine actually has beats inventing
        // a better one; make it live (W104's option B) and both readouts come right together.
        case "bufferingprogress", "downloadprogress":
            return .value(.number(snapshot.bufferingProgress))
        case "receptionquality": return .value(.number(snapshot.receptionQuality))
        // **`bitRate` is a real number this player has, and it was aborting a handler.**
        // `Cablemusic`'s `handlePlayStateChange` reaches `UpdateBitrate()` before it reaches the
        // function that fills every readout in the player, so an unrecognised member here cost the
        // whole show/clip/author/copyright block on every track — the second cause of "the track
        // information does not appear", found only by reading `INPUT script-diag` in the running
        // app after the first one (`player.currentMedia.sourceURL`) was closed. `Track.bitrate` is
        // kilobits; WMP's unit is bits per second, and the skin prints it with a `bps` suffix.
        case "bitrate": return .value(.number(snapshot.bitrate))
        // `maxBitRate` is the stream's ceiling across its authored bands, which a player with no
        // multi-bitrate session has no value for. Inert zero, and it joins this group rather than
        // answering `bitrate`: 3 archives read it (`9SeriesDefault`, `Compact`, `corona`) and all
        // three print it beside the live rate, where echoing one into the other would draw a
        // confident wrong number. `framesSkipped`, `lostPackets` and `receivedPackets` have **no
        // reader in the corpus at all** and are answered only so a handler cannot abort on one.
        case "bandwidth", "maxbitrate", "framesskipped", "lostpackets", "receivedpackets":
            inert(); return .value(.number(0))
        // The transport a stream arrived over — `mms`, `http`, `rtsp` — which is a property of the
        // network session WMP had and this player does not. `Corona`'s `OnStatusChange` reads it
        // to decide whether it is showing a live broadcast, and an unrecognised member there aborts
        // the handler that turns its visualization pane on (W101's Corona case). Local playback has
        // no source protocol, so the empty string is the true answer and it is counted inert.
        case "sourceprotocol": inert(); return .value(.string(""))
        default: return .unrecognised("network member")
        }
    }

    private func readEqualizer(_ name: String) -> WMPMemberValue {
        if name.hasPrefix("gainlevel"), let band = Int(name.dropFirst("gainlevel".count)),
           (1...10).contains(band) {
            let gains = snapshot.equalizer.gains
            return .value(.number(gains.indices.contains(band - 1) ? gains[band - 1] : 0))
        }
        switch name {
        case "enhancedaudio": return .value(.bool(snapshot.equalizer.enhancedAudio))
        case "wowlevel": return .value(.number(snapshot.equalizer.wowLevel))
        case "trubasslevel": return .value(.number(snapshot.equalizer.truBassLevel))
        case "speakersize": return .value(.number(Double(snapshot.equalizer.speakerSize)))
        case "currentspeakername": return .value(.string(snapshot.equalizer.currentSpeakerName))
        case "enabled": return .value(.bool(snapshot.equalizer.enabled))
        // **`bypass` is `enabled` inverted, and it is how a skin's equaliser on/off switch is
        // authored.** `Compact`'s is `down="wmpprop:eq.bypass" onClick="eq.bypass=down"` with a
        // `down_onchange` that relabels it, so with the member unrecognised the button in its
        // settings drawer did nothing, its `UpdateEQOnOff()` aborted, and the "On"/"Off" label
        // beside it never moved. 46 uses across 7 archives.
        case "bypass": return .value(.bool(!snapshot.equalizer.enabled))
        case "presetcount": return .value(.number(Double(EQPreset.allPresets.count)))
        case "currentpreset": return .value(.number(Double(currentPresetIndex)))
        case "currentpresettitle":
            return .value(.string(EQPreset.allPresets.indices.contains(currentPresetIndex)
                ? EQPreset.allPresets[currentPresetIndex].name : ""))
        case "presettitle", "nextpreset", "previouspreset", "reset": return .function
        case "bands": return .value(.number(10))
        // **Crossfade is Sweet Fades, so these are live and not inert.** The corpus's idiom is a
        // sticky button whose handler is `eq.crossFade = !eq.crossFade;eq.crossFadeWindow=7000`,
        // and with `crossFade` unrecognised the read threw before the `!` and took the whole
        // handler with it — including the `checkSoundPref('click.wav')` in front of it on the
        // Alienware, Batman, Constantine, Disney, Dreamcatcher and KungFuChaos spellings.
        // 123 uses across 38 archives for `crossFade`, 40 across 35 for the window.
        case "crossfade": return .value(.bool(snapshot.equalizer.crossFade))
        case "crossfadewindow": return .value(.number(snapshot.equalizer.crossFadeWindow))
        case "normalization": return .value(.bool(snapshot.equalizer.normalization))
        // **Spline tension is how WMP's ten sliders drag each other, and this equaliser's do not.**
        // Inert, and the value is stored because it is read back: `Back to the Future Trilogy`'s
        // `checkSplineTension()` tests `eq.enableSplineTension && eq.splineTension==2` to decide
        // which of its three grouping buttons is lit, so a constant would light the same one
        // whatever was pressed. `false`/`0` is the honest default — independent sliders is exactly
        // what this player does — and it is the same pair `inertEqualizerSettingsProperties`
        // answers on the `<EQUALIZERSETTINGS>` element, so the two spellings agree.
        // 68 uses across 51 archives, and 56 across 48.
        case "enablesplinetension", "splinetension":
            inert()
            return .value(equalizerSessionSettings[name]
                ?? Self.defaultInertEqualizerSettingsValue(for: name))
        default: return .unrecognised("eq member")
        }
    }

    /// **WMP's `event` object: the two display members, and the three modifier flags the
    /// dispatching event actually carries.** `keyCode` and the pointer coordinates are *not* here
    /// and stay unrecognised, so `WMP_CALL_TRACE` tallies them as the demand they are (433 uses
    /// across 79 archives for `keyCode` alone): this engine dispatches no `onKeyDown`, and
    /// answering `keyCode = 0` would tell every one of those handlers that a key it never saw was
    /// pressed. A modifier flag is different in kind — it is a state the dispatch knows.
    private func readEvent(_ name: String) -> WMPMemberValue {
        switch name {
        case "screenwidth": return .value(.number(Double(screen.width)))
        case "screenheight": return .value(.number(Double(screen.height)))
        case "shiftkey": return .value(.bool(eventModifiers.contains(.shift)))
        case "ctrlkey": return .value(.bool(eventModifiers.contains(.control)))
        case "altkey": return .value(.bool(eventModifiers.contains(.alt)))
        // **Absent is not zero.** Outside a keystroke there is no key, and `0` is VK_NULL — a
        // number `switch(event.keyCode)` can match. `null` matches no numeric `case` and compares
        // false against every literal in the corpus, which is the honest answer to "which key",
        // and the member still *resolves*, so a handler reading it outside a keystroke runs on
        // rather than dying with a `ReferenceError` (W53, and W260's absent-is-not-zero rule).
        case "keycode": return .value(eventKeyCode.map { .number(Double($0)) } ?? .null)
        // **The element the event was raised on, and the reason a whole skin depends on it.**
        // `Cablemusic` gives all eighteen of its station buttons the same
        // `onMouseDown="StartProgram();"` and the function asks which one it was:
        // `var i = Number(String(event.srcElement.id).substring(2));`. Eighteen presets share
        // `AssignPreset()` the same way, so an unrecognised member here took both surfaces — the
        // handler dies on its first statement and nothing on the skin's face does anything.
        //
        // Answered as the element object rather than as its id, because that is what WMP hands
        // back and `.id` is only the member the corpus happens to read first.
        case "srcelement":
            let target = eventTargetStableID.flatMap(element(stableID:)) ?? eventTargetID.flatMap(element)
            guard let element = target, !element.id.isEmpty else {
                // Absent is not a wrong element: outside an element-raised event, and for a node
                // the markup left unnamed, there is nothing honest to hand back. The member still
                // resolves, so the handler runs on — W260's rule, as `keyCode` applies it above.
                return .value(.null)
            }
            return .object("element:\(WMPPath.fold(element.id))")
        case "button": return .value(eventButton.map { .number(Double($0)) } ?? .null)
        case "clientx": return .value(eventPointer.map { .number(Double($0.x)) } ?? .null)
        case "clienty": return .value(eventPointer.map { .number(Double($0.y)) } ?? .null)
        default: return .unrecognised("event member")
        }
    }

    private func readTheme(_ name: String) -> WMPMemberValue {
        switch name {
        case "currentviewid": return .value(.string(currentViewID))
        case "loadpreference", "savepreference", "loadstring", "opendialog", "openview", "playsound",
             "closeview", "openviewrelative":
            return .function
        default: return .unrecognised("theme member")
        }
    }

    /// WMP's Media Center host object: the video surface, the visualization ("effects") selection,
    /// and the shell's own localised strings. **Every member is `inert()`**, and that is the whole
    /// finding rather than a shortcut — this engine has no video surface at all
    /// (`imageSourceWidth`/`Height` already answer 0 for the same reason), draws exactly one
    /// effect with no type and no presets, and has no high-contrast mode. There is nothing behind
    /// any of it to be live about.
    ///
    /// What it is *not* is a stub that answers a constant. Skins round-trip these — `Plus! Perfect`
    /// writes `mediacenter.effectPreset = visEffects.currentPreset` and reads it back into a second
    /// view's control — so a write stores session state and the next read answers it, exactly as
    /// `player.settings.autoStart` does. A constant would break the read-back and be invisible while
    /// doing it.
    ///
    /// The defaults are chosen to describe what this player actually does, not to echo WMP's:
    /// nothing is fitted to anything, so both fit flags are false; no titles are drawn over a video
    /// that does not exist, so `showTitles` is false; the effects surface is always drawn, so
    /// `showEffects` is true; there is no high-contrast mode, so `contrastMode` is the empty string
    /// the corpus tests `!= "BW"` and `!= "WB"` against.
    private func readMediaCenter(_ name: String) -> WMPMemberValue {
        if name == "getnamedstring" { return .function }
        // **Two of the nine now have a host behind them.** `effectType` and `effectPreset` are
        // where 162 archives keep their visualization selection, and the `<EFFECTS>` rect they
        // select for is hosted (W101), so these answer what is being drawn rather than what was
        // last written. The other seven are still honestly inert; see the doc comment above.
        switch name {
        case "effecttype": return .value(.string(snapshot.effects.type))
        case "effectpreset": return .value(.number(Double(snapshot.effects.preset)))
        default: break
        }
        guard let fallback = Self.mediaCenterDefaults[name] else {
            return .unrecognised("mediacenter member")
        }
        inert()
        return .value(mediaCenterState[name] ?? fallback)
    }

    /// The member surface, with the value each one answers before a skin has written it. The corpus
    /// asks for exactly these nine names and never uses `mediacenter` as a bare identifier, so this
    /// table is the whole object; a tenth name stays `unrecognised` and ranks itself.
    static let mediaCenterDefaults: [String: WMPJSONValue] = [
        "videozoom": .number(100),
        "videostretchtofit": .bool(false),
        "videoshrinktofit": .bool(false),
        "effecttype": .string(""),
        "effectpreset": .number(0),
        "showtitles": .bool(false),
        "showeffects": .bool(true),
        "contrastmode": .string("")
    ]

    /// The members a skin may write. `contrastMode` is the host's accessibility setting and is
    /// read-only in WMP too, so a write stays unrecognised rather than being quietly accepted.
    static let mediaCenterWritableMembers: Set<String> = Set(mediaCenterDefaults.keys)
        .subtracting(["contrastmode"])

    /// What `readElement` computes for a kind, as the `with` scope's own list. Kept beside it:
    /// a computed property added there and not here is readable qualified and invisible bare.
    private static func computedElementProperties(_ element: WMPScriptElement) -> Set<String> {
        var names: Set<String> = ["textwidth"]
        switch element.kind {
        case .popup, .listBox: names.insert("itemcount")
        case .effects:
            names.formUnion(["currenteffecttype", "currenteffecttitle",
                             "currentpreset", "currentpresettitle"])
        case .video, .wmpVideo:
            names.formUnion(["fullscreen", "shrinktofit", "stretchtofit", "maintainaspectratio"])
        default: break
        }
        return names
    }

    private func readElement(_ element: WMPScriptElement, _ name: String) -> WMPMemberValue {
        if let method = elementMethod(element, name) { _ = method; return .function }
        if element.kind == .video || element.kind == .wmpVideo {
            if name == "fullscreen" { return .value(.bool(snapshot.video.fullScreen)) }
            if ["shrinktofit", "stretchtofit", "maintainaspectratio"].contains(name) {
                // The same defaults `WMPVideoPresentation` draws with, and for the same reason: a
                // skin that reads back a flag it never authored must be told what is on screen.
                return .value(element.properties[name] ?? .bool(name != "stretchtofit"))
            }
        }
        switch name {
        case "id": return .value(.string(element.id))
        case "itemcount" where element.kind == .popup || element.kind == .listBox:
            return .value(.number(Double(element.items.count)))
        // **`textWidth` is how a skin decides to marquee.** `WoW` writes
        // `metadata.scrolling = (metadata.textWidth > metadata.width)` on every metadata change,
        // and 92 of the 180 corpus archives read it. Answering the unset-numeric 0 told every one
        // of them the string fits, so scrolling was never turned on and the readout was drawn in
        // full — unclipped, across the rest of the player. Measured through `WMPTextMetrics`, the
        // same path the renderer lays the line out with, so the comparison is against what is drawn.
        case "textwidth":
            return .value(.number(Double(Self.measuredTextWidth(element))))
        // The `<EFFECTS>` rect's own view of the same selection `mediacenter` holds: 66 archives
        // read `currentEffectType`/`currentPreset` off the element, 61 `currentEffectTitle` and 42
        // `currentPresetTitle` — the strings they draw beside the surface (W101).
        case "currenteffecttype" where element.kind == .effects:
            return .value(.string(snapshot.effects.type))
        case "currenteffecttitle" where element.kind == .effects:
            return .value(.string(snapshot.effects.title))
        case "currentpreset" where element.kind == .effects:
            return .value(.number(Double(snapshot.effects.preset)))
        case "currentpresettitle" where element.kind == .effects:
            return .value(.string(snapshot.effects.presetTitle))
        default: break
        }
        // WMP exposes these settings on `<EQUALIZERSETTINGS>`, but NullPlayer has no
        // spline-tension DSP or separate bypass state.  Keep the value a skin authored (or later
        // writes) so its own bookkeeping round-trips, while keeping it in the INERT tally rather
        // than pretending that it changed the audio engine (W134).
        if element.kind == .equalizerSettings,
           Self.inertEqualizerSettingsProperties.contains(name) {
            inert()
            return .value(element.properties[name] ?? Self.defaultInertEqualizerSettingsValue(for: name))
        }
        if let value = element.properties[name] {
            // A host object a skin stored on its own element — `playlist1.playlist = lbCurrentItem`
            // — reads back as that object, not as the reference string it was carried in.
            if let reference = Self.objectReference(value) {
                // A pane whose library playlist the queue has moved past reads back as the live
                // queue, which is what it is showing.
                if name == "playlist", libraryPlaylistShown(by: element) == nil {
                    return .object("player.currentplaylist")
                }
                return .object(reference)
            }
            return .value(value)
        }
        // **A `<TEXT>` is sized by its own glyphs, and until the first layout exists nothing
        // has told the element model so.** `perform` syncs every element's frame from the layout
        // the skin is *currently drawn at*, which on the opening transaction is no layout at all —
        // so an unauthored `width` fell through to the unset-numeric 0 below. `Colorchooser` is
        // the only archive in the corpus that chains geometry off a text node's measured width:
        // its five transport buttons are `left="jscript:<prev>.left+<prev>.width"`, so with every
        // `width` answering 0 the chain never advanced and `stopbutton`, `pausebutton`,
        // `nextbutton` and `prevbutton` all resolved to `left=16` where 16/28/40/52 was authored.
        // The glyphs overprinted at `103,29 12x12` and, `prevbutton` being last in z-order, the
        // first click anywhere in that row fired **previous**. It repaired itself on that same
        // click — the relayout it triggered is the first one there is, so the next transaction
        // syncs real frames — which is why the defect is one click deep and survived hand-testing.
        // Measured the way `WMPSceneBuilder.intrinsicTextSize` measures it, because frame 0 has to
        // agree with the frame the builder lays out or the row would move under the pointer.
        if Self.isText(element.kind), !element.authored.contains(name),
           let size = Self.intrinsicTextSize(element) {
            if name == "width" { return .value(.number(Double(size.width))) }
            if name == "height" { return .value(.number(Double(size.height))) }
        }
        // WMP's `alphaBlend` is 0-255 and an element that never authored it is fully opaque. The
        // unset-numeric default of 0 would tell a skin reading its own element that it is invisible,
        // and a fade written as `x.alphaBlendTo(x.alphaBlend + 32, 200)` would never leave zero.
        if name == "alphablend" { return .value(.number(255)) }
        // WMP's own defaults for both are **true**, which is already what the renderer draws: an
        // element the markup never hid is on screen and a control it never disabled takes a click.
        // Answering the unset-standard `""` told a skin reading back its own layout the opposite,
        // and `Combat_Flight_Simulator_3` is what that costs: `mainTimer()` tests
        // `mainIntro.visible` — an attribute its markup never authors — takes the `!visible`
        // branch every tick, never calls `hideIntro()`, and leaves the whole main face inert
        // behind the buttons `disableButtons()` hid at startup (W181). Measured over the 184
        // installed archives: `.visible` is read 513 times in 67 of them and `.enabled` 35 times
        // in 9, and the reads this default reaches are the 81 / 21 and 25 / 5 that name an
        // element whose markup authors no such attribute.
        if name == "visible" || name == "enabled" { return .value(.bool(true)) }
        // The view is also a host object: `view.close()` and `view.width` reach the same receiver.
        if element.kind == .view, let host = readViewHost(name) { return host }
        if element.authored.contains(name) || Self.standardElementProperties.contains(name) {
            // Authored but never given a value, or a standard property the markup left out. Zero is
            // what WMP answers for an unset numeric property and the empty string for the rest.
            return .value(Self.standardNumericProperties.contains(name) ? .number(0) : .string(""))
        }
        if Self.elementMethodVocabulary.contains(name) {
            return .unrecognised("element method")
        }
        // A WMP element carries far more properties than this engine draws — `hoverFontStyle` on a
        // TEXT, for one — and refusing them would abort the handler that sets them, which in
        // Corona is the whole of `InitControls`. They are held as element state and answer as
        // **inert**, so the census can rank "properties skins set that nothing renders" instead of
        // losing them: the surface is open, the tally is not.
        inert()
        return .value(Self.standardNumericProperties.contains(name) ? .number(0) : .string(""))
    }

    /// The element's current `value` measured in its current face — both read from the live property
    /// bag, so a `textWidth` read in the same handler that just assigned `value` sees the new string.
    /// The kinds `WMPSceneBuilder.isText` sizes from glyphs, and the same list for the same reason.
    private static func isText(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .text, .statusText, .currentPositionText, .durationText: return true
        default: return false
        }
    }

    /// The size the builder would lay this text out at, from the live property bag.
    ///
    /// `measuredTextWidth` answers `textWidth`, which is a typographic measurement a skin compares
    /// against its own box; this is a *frame*, and the builder rounds it up before laying it out.
    /// They stay separate so that rounding cannot move a marquee decision.
    private static func intrinsicTextSize(_ element: WMPScriptElement) -> WMPSize? {
        // **Trimmed, because `WMPSceneBuilder.literalString` trims and the frame has to match.**
        // `Colorchooser` centres its webdings glyphs by padding the attribute — `value=" &lt; "` —
        // and measuring the padding put the button at 24 wide where the builder lays it out at 12,
        // which is the same row moving under the pointer for the opposite reason.
        guard let value = element.properties["value"]?.string
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              !value.isEmpty else { return nil }
        let style = (element.properties["fontstyle"]?.string ?? "").lowercased()
        let face = WMPTextMetrics.face(element.properties["fontface"]?.string,
                                       element.properties["fonttype"]?.string)
        let size = CGFloat(max(1, element.properties["fontsize"]?.number ?? 12))
        let bold = style.contains("bold"), italic = style.contains("italic")
        return WMPSize(
            width: WMPTextMetrics.width(of: value, fontName: face, fontSize: size,
                                        bold: bold, italic: italic).rounded(.up),
            height: WMPTextMetrics.lineHeight(fontName: face, fontSize: size,
                                              bold: bold, italic: italic))
    }

    private static func measuredTextWidth(_ element: WMPScriptElement) -> CGFloat {
        guard let value = element.properties["value"]?.string, !value.isEmpty else { return 0 }
        let style = (element.properties["fontstyle"]?.string ?? "").lowercased()
        let face = WMPTextMetrics.face(element.properties["fontface"]?.string,
                                       element.properties["fonttype"]?.string)
        let size = element.properties["fontsize"]?.number ?? 12
        return WMPTextMetrics.width(of: value, fontName: face, fontSize: CGFloat(max(1, size)),
                                    bold: style.contains("bold"), italic: style.contains("italic"))
    }

    private func readViewHost(_ name: String) -> WMPMemberValue? {
        switch name {
        case "close", "minimize", "returntomediacenter", "size": return .function
        default: return nil
        }
    }

    private func elementMethod(_ element: WMPScriptElement, _ name: String) -> String? {
        switch (element.kind, name) {
        case (.popup, "appenditem"), (.popup, "removeallitems"), (.popup, "getitem"): return name
        // A `<LISTBOX>` is filled the same way, under the SDK's own names (W136): `WoW`'s
        // `fillListBox()` opens with `plListBox1.deleteAll()`.
        case (.listBox, "appenditem"), (.listBox, "deleteall"), (.listBox, "getitem"),
             (.listBox, "insertitem"), (.listBox, "deleteitem"): return name
        // 82 archives call `visEffects.next()` and 74 `visEffects.previous()` — the corpus's own
        // way of cycling the surface, and the reason the selector never needed a menu (W101).
        case (.effects, "next"), (.effects, "previous"), (.effects, "nextpreset"): return name
        case (_, "moveto"), (_, "resizeto"), (_, "alphablendto"): return name
        case (.view, "close"), (.view, "minimize"), (.view, "returntomediacenter"),
             (.view, "size"): return name
        default:
            return Self.isPlaylist(element.kind)
                && ["setcolumnresizemode", "setcolumnwidth"].contains(name) ? name : nil
        }
    }

    /// The element methods this engine answers, on whatever kind defines them — `elementMethod` is
    /// the kind-aware authority and this is the flat name set the corpus census classifies against.
    /// Without it a call the runtime handles is still counted as unimplemented demand: that is how
    /// `alphaBlendTo` came to be measured as the largest row on the backlog while `moveTo`, which
    /// has been implemented since Phase 3, was counted beside it (W38).
    static let implementedElementMethods: Set<String> = [
        "moveto", "resizeto", "alphablendto", "close", "minimize", "returntomediacenter", "size",
        "appenditem", "removeallitems", "getitem", "setcolumnresizemode", "setcolumnwidth",
        "next", "previous", "nextpreset", "deleteall", "insertitem", "deleteitem"
    ]

    /// Names WMP defines as element *methods*. One of these that this engine does not implement
    /// stays unrecognised rather than falling into the open property surface — otherwise
    /// `svPlaylist.moveTo(…)` reads as an empty string, fails with a bare `TypeError`, and the
    /// method never appears in the demand tally that ranks the work.
    ///
    /// **This is the SDK's element-method list, not a guess** (W128). It is transcribed from the
    /// Skin Programming Reference pages named per group below, so a method the corpus calls is
    /// counted whether or not this engine has ever seen it: a name missing from here is invisible
    /// to `WMP_CALL_TRACE`, which is the instrument every row in `WMP_TASKS.md` is ranked from.
    /// `view.returnToMediaCenter` is the evidence — it had to be found by a live reporter (W100)
    /// because the tally could not see it. Widening this set implements nothing; `elementMethod`
    /// stays the authority on what actually runs and `implementedElementMethods` on what is
    /// counted as answered.
    ///
    /// A name is only ever added here, never removed: dropping one turns a call the census
    /// currently tallies back into a silent empty string, which is the defect this set exists for.
    static let elementMethodVocabulary: Set<String> = [
        // Ambient — every element (`ambient-attributes`). `resizeTo` is *not* ambient in the SDK;
        // this engine implements it anyway, so it stays.
        "alphablendto", "movesizeto", "moveto", "slideto", "resizeto",
        // VIEW (`view-element`).
        "close", "maximize", "minimize", "restore", "returntomediacenter", "size",
        // PLAYLIST (`playlist-element`) — 18.
        "abortcopy", "addselectedtoplaylist", "copy", "deleteselected",
        "deleteselectedfromlibrary", "getnextcheckeditem", "getnextcheckeditem2",
        "getnextselecteditem", "getnextselecteditem2", "moveselecteddown", "moveselectedup",
        "setcheckedstate", "setcheckedstate2", "setcolumnresizemode", "setcolumnwidth",
        "setselectedstate", "setselectedstate2", "sortcolumn",
        // LISTBOX and POPUP (`listbox-element`, `popup-element` — identical) — 11, of which
        // `getNextSelectedItem` and `setSelectedState` are spelled the same as PLAYLIST's above.
        "appenditem", "deleteall", "deleteitem", "dismiss", "finditem", "getitem",
        "insertitem", "replaceitem", "show",
        // EDITBOX (`editbox-element`) — 7.
        "getline", "getlinefromchar", "getlineindex", "getselectionend", "getselectionstart",
        "replaceselection", "setselection",
        // EFFECTS (`effects-element`) — 9.
        "effecttitle", "effecttype", "next", "nexteffect", "nextpreset", "previous",
        "previouseffect", "previouspreset", "settings",
        // BUTTONGROUP (`buttongroup-element`) — 2.
        "click", "getbutton",
        // **Non-SDK residue, kept deliberately.** These were here before the list was checked
        // against the specification and the corpus calls them; they are already tallied, and
        // removing a name can only make a measured call silent again.
        "hide", "removeallitems", "removeitem", "selectitem", "setfocus", "invoke", "play", "stop"
    ]

    /// `PLAYLIST`, `DROPDOWNPLAYLIST` and the `ITEMSPLAYLIST` the corpus actually ships. The last
    /// now parses as `.playlist` (W97), so the first case answers it; the suffix rule stays because
    /// it is what let Corona's `OnLoad` reach its column setup before the kind existed, and it
    /// still covers any `*PLAYLIST` spelling the corpus has not shown us.
    static func isPlaylist(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .playlist, .dropdownPlaylist: return true
        case let .unknown(tag): return tag.lowercased().hasSuffix("playlist")
        default: return false
        }
    }

    // MARK: - Writes

    private var sessionSettings: [String: WMPJSONValue] = [:]
    /// The `eq` members this engine stores and applies nothing for — see `readEqualizer`.
    private var equalizerSessionSettings: [String: WMPJSONValue] = [:]
    /// Written by the skin, read back by the skin, and behind none of it is a host. See
    /// `readMediaCenter`.
    private var mediaCenterState: [String: WMPJSONValue] = [:]

    private func write(path: String, member: String, value: WMPJSONValue) -> WMPMemberValue {
        let name = member.lowercased()
        if path.hasPrefix("element:") {
            guard let element = liveElement(String(path.dropFirst("element:".count))) else {
                return .unrecognised("no such element")
            }
            // The read side's rule, on the write side: the equaliser owns the members that
            // reach the audio, the element keeps its own bookkeeping (W256, W134).
            if element.kind == .equalizerSettings,
               !Self.inertEqualizerSettingsProperties.contains(name) {
                let answer = write(path: "eq", member: member, value: value)
                if case .unrecognised = answer {} else { return answer }
            }
            if name == "playlist" { element.libraryPlaylistGeneration = queueGeneration }
            if name == "selecteditem", element.kind == .listBox, let index = value.number {
                listSelectionWrites[element.stableID] = Int(index)
            }
            return writeElement(element, name, value)
        }
        switch (path, name) {
        // **`player.currentPlaylist = <a library playlist>` is how a skin plays what its chooser
        // selected** (W136) — `WoW`'s `playSelPlaylist()`. The playlist arrives as an object
        // reference (`WMPScriptContext.jsonValue`); anything else, including the current playlist
        // handed back to itself, changes nothing.
        case ("player", "currentplaylist"):
            guard let reference = Self.objectReference(value),
                  reference != currentLibraryPlaylist,
                  let tracks = libraryTracks(reference) else {
                inert()
                return .value(value)
            }
            // **A playlist with nothing to play does not become the current one** (W136). WMP's
            // assignment is synchronous; here a server playlist may still be loading, or its
            // fetch may have failed. Adopting it anyway, and then running the `play()` every skin
            // writes after the assignment, played whatever was queued before under the new
            // playlist's name. A loading playlist is played when it arrives; a failed one plays
            // nothing — and either way this transaction's `play()` is withheld.
            guard !tracks.isEmpty else {
                libraryPlayWithheld = true
                if libraryDemands.contains(where: { $0.hasPrefix("playlist:") }) {
                    libraryDemands.insert("play:" + reference)
                }
                return .value(value)
            }
            currentLibraryPlaylist = reference
            // Catalog indices, not URLs: `sourceURL` is WMP's spelling for the skin to read, and
            // the host holds the real locations beside the catalog it built.
            hostCommand("loadLibraryTracks",
                        .string(tracks.map(String.init).joined(separator: ",")))
            return .value(value)
        // WMP renames the playlist; this player's queue has no name to give it. Accepted so the
        // `player.controls.play()` after it in `WoW`'s `playSelPlaylist()` still runs.
        case ("player.currentplaylist", "name"):
            inert()
            return .value(value)
        // **The Xbox skins' `resetCode()` writes the key back every timer tick** (W266):
        // `event.keycode = 65` so a stale X cannot fire the Easter egg on hover. `eventKeyCode`
        // is set afresh by every `beginTransaction`, so the write lives for this dispatch only —
        // later reads in the same handler see it, the next event does not.
        case ("event", "keycode"):
            eventKeyCode = value.number.map { Int($0) }
            return .value(value)
        case ("player.controls", "currentposition"):
            hostCommand("seekSeconds", value)
            return .value(value)
        // Stored as well as sent, so a read later in the same handler sees the write: `Asimov_Radio`'s
        // `SetVolume` clamps and `DisplayVolume` lights its bars off the value it just set (W280).
        case ("player.settings", "volume"):
            guard let number = value.number, number.isFinite else { return .value(.number(snapshot.volume * 100)) }
            let percent = max(0, min(100, number))
            snapshot.volume = percent / 100
            hostCommand("volumePercent", .number(percent))
            return .value(.number(percent))
        case ("player.settings", "balance"):
            hostCommand("balancePercent", value)
            return .value(value)
        case ("player.settings", "mute"):
            hostCommand("setMute", .number(value.truth ? 1 : 0))
            return .value(value)
        case ("player.settings", "autostart"), ("player.settings", "enableerrordialogs"),
             ("player.settings", "invokeurls"):
            sessionSettings[name] = value
            inert()
            return .value(value)
        case ("eq", "enhancedaudio"):
            snapshot.equalizer.enhancedAudio = value.truth
            hostCommand("setWOWEnabled", .number(value.truth ? 1 : 0))
            return .value(.bool(value.truth))
        case ("eq", "wowlevel"):
            guard let number = value.number, number.isFinite else { return .value(.number(snapshot.equalizer.wowLevel)) }
            let level = max(0, min(100, number))
            snapshot.equalizer.wowLevel = level
            hostCommand("setWOWLevel", .number(level))
            return .value(.number(level))
        case ("eq", "trubasslevel"):
            guard let number = value.number, number.isFinite else { return .value(.number(snapshot.equalizer.truBassLevel)) }
            let level = max(0, min(100, number))
            snapshot.equalizer.truBassLevel = level
            hostCommand("setTruBassLevel", .number(level))
            return .value(.number(level))
        case ("eq", "speakersize"):
            guard let number = value.number, number.isFinite else { return .value(.number(Double(snapshot.equalizer.speakerSize))) }
            // Authored cycling uses -1 followed by ++ within one transaction.
            let speaker = Int(max(-1, min(2, number)))
            snapshot.equalizer.speakerSize = speaker
            if speaker >= 0 { hostCommand("setSpeakerSize", .number(Double(speaker))) }
            return .value(.number(Double(speaker)))
        case ("eq", "crossfade"):
            snapshot.equalizer.crossFade = value.truth
            hostCommand("setCrossFade", .number(value.truth ? 1 : 0))
            return .value(.bool(value.truth))
        case ("eq", "crossfadewindow"):
            guard let number = value.number, number.isFinite else {
                return .value(.number(snapshot.equalizer.crossFadeWindow))
            }
            // WMP's own range. The corpus only ever writes 7000, but a window of zero is a cut and
            // one of an hour is a stuck fade, so the bound is here rather than in the engine.
            let window = max(0, min(20_000, number))
            snapshot.equalizer.crossFadeWindow = window
            hostCommand("setCrossFadeWindow", .number(window))
            return .value(.number(window))
        case ("eq", "normalization"):
            snapshot.equalizer.normalization = value.truth
            hostCommand("setNormalization", .number(value.truth ? 1 : 0))
            return .value(.bool(value.truth))
        case ("eq", "enablesplinetension"), ("eq", "splinetension"):
            equalizerSessionSettings[name] = value
            inert()
            return .value(value)
        case ("eq", "enabled"):
            hostCommand("setEQEnabled", .number(value.truth ? 1 : 0))
            return .value(value)
        case ("eq", "bypass"):
            snapshot.equalizer.enabled = !value.truth
            hostCommand("setEQEnabled", .number(value.truth ? 0 : 1))
            return .value(value)
        case ("eq", "currentpreset"):
            applyPreset(index: Int(value.number ?? 0))
            return .value(value)
        // The write half of the member above. The same host command the `<VIDEO>` element's own
        // `fullScreen` write posts, so the two spellings drive one picture.
        case ("player", "fullscreen"):
            hostCommand("setVideoFullScreen", .bool(value.truth))
            return .value(.bool(value.truth))
        case ("theme", "currentviewid"):
            hostCommand("setCurrentView", .string(value.string ?? ""))
            return .value(value)
        default: break
        }
        if path == "mediacenter" {
            // The write half of the two live members. 47 skins post
            // `mediacenter.effectType=currentEffectType` straight back out of the rect's own
            // `_onchange`, so this is the round trip the surface is driven by.
            switch name {
            case "effecttype":
                hostCommand("setEffectType", .string(value.string ?? ""))
                return .value(value)
            case "effectpreset":
                hostCommand("setEffectPreset", .number(value.number ?? 0))
                return .value(value)
            default: break
            }
            guard Self.mediaCenterWritableMembers.contains(name) else {
                return .unrecognised(Self.mediaCenterDefaults[name] == nil
                    ? "mediacenter member" : "mediacenter member is read-only")
            }
            mediaCenterState[name] = value
            inert()
            return .value(value)
        }
        if path == "eq", name.hasPrefix("gainlevel"), let band = Int(name.dropFirst("gainlevel".count)),
           (1...10).contains(band) {
            hostCommand("setEQBand:\(band - 1)", value)
            return .value(value)
        }
        return .unrecognised("read-only or unknown member")
    }

    private func writeElement(_ element: WMPScriptElement, _ name: String,
                              _ written: WMPJSONValue) -> WMPMemberValue {
        // **A boolean property written as a quoted string is stored as a boolean, because the skin
        // reads its own write back and JScript's `"false"` is true.**
        //
        // `Plus! SlimLine`'s bottom arrows are the reported case: `toggleProgressBar()` tests
        // `if (progressBar.visible)` and assigns `progressBar.visible = "false"`. The scene was
        // always right — it reads the mutation through `WMPJSONValue.truth`, which knows `"false"`
        // — but the property bag handed the string straight back, so the next click read a truthy
        // `"false"`, took the hide branch again, and the arrow worked exactly once. Reported live
        // 2026-09-22 as *"the bottom arrows do not work reliably"*.
        //
        // **It is the element's bag that needs this and not the host objects**: `player.settings.mute`
        // already applies `truth` on the way out and answers the *host's* state on the way back, so
        // a string written there never survives to be re-read. Measured over the 184 installed
        // archives — the property names a skin writes with a quoted `true`/`false`, and the set
        // below is that list less the host-object ones: `enabled` 170 uses / 4 archives, `visible`
        // 148 / 12, `tabStop` 60 / 1, `down` 16 / 2, `scrolling` 6 / 1, `fullScreen` 4 / 2. The
        // ones that make it a *defect* rather than a stored oddity are the ones read back as a
        // condition — `Plus! SlimLine`, `tubeframe`, `elvis` and `Heart_Butterfly`.
        //
        // Markup needs no part of this: `WMPScriptViewPlan.scalar` already turns an authored
        // `visible="false"` into `.bool`, so this is the script path catching up with the markup.
        // Only a *string* is wrong. A number written to one of these already reads back with the
        // truthiness it was given — `0` is falsy in JScript as it is in `truth` — so narrowing to
        // the string case keeps the coercion to the shape that actually lies.
        var value = written
        if case .string = written, Self.standardBooleanProperties.contains(name) {
            value = .bool(written.truth)
        }
        let videoProperty = (element.kind == .video || element.kind == .wmpVideo)
            && ["shrinktofit", "stretchtofit", "maintainaspectratio"].contains(name)
        if (element.kind == .video || element.kind == .wmpVideo), name == "fullscreen" {
            hostCommand("setVideoFullScreen", .bool(value.truth))
            return .value(value)
        }
        // The view's own timer, which is a host timer and not a scene property. A skin drives its
        // animation from it — Corona's compact view collapses its video panel by registering a
        // `TimerEvent` and then writing the interval it wants — so a write that only stored a
        // number would leave the skin frozen in whatever state it was authored in.
        if element.kind == .effects, name == "currenteffecttype" || name == "currentpreset" {
            element.properties[name] = value
            if name == "currenteffecttype" { hostCommand("setEffectType", .string(value.string ?? "")) }
            else { hostCommand("setEffectPreset", .number(value.number ?? 0)) }
            return .value(value)
        }
        if element.kind == .view, name == "timerinterval" {
            element.properties[name] = value
            hostCommand("setViewTimerInterval", .number(max(0, value.number ?? 0)))
            return .value(value)
        }
        if element.kind == .equalizerSettings,
           Self.inertEqualizerSettingsProperties.contains(name) {
            element.properties[name] = value
            inert()
            return .value(value)
        }
        // **A view's four resize limits are a contract the scene reads, so a write to one has to
        // commit as a mutation (W196).** They are not on `standardElementProperties` because they
        // mean nothing on any other element, and without this the write survived only where the
        // markup happened to author the same attribute — the rule would then be about the markup
        // rather than about the property. Measured over the 185 installed archives: **3 write a
        // view limit from script** (`Compact`, `Disney_Mix_Central`, `NVIDIA`) and all three author
        // every name they write, so this moves nothing in the corpus today and is here so the next
        // skin that writes an unauthored one is not silently ignored.
        let viewLimit = element.kind == .view && Self.viewResizeLimitProperties.contains(name)
        let rendered = videoProperty || viewLimit || element.authored.contains(name)
            || Self.standardElementProperties.contains(name)
            || element.properties[name] != nil
        // Same contract as the read side: the property surface is open, and one nothing draws is
        // stored and counted as inert rather than refused.
        if !rendered { inert() }
        element.properties[name] = value
        if rendered, mutations.count < WMPJScriptProtocol.maximumMutations {
            mutations.append(.init(targetID: element.id, property: name, value: value))
        }
        if rendered, repaintHints.count < WMPJScriptProtocol.maximumRepaintHints {
            repaintHints.append(element.id)
        }
        return .value(value)
    }

    /// The element properties WMP types as Boolean, so a script's quoted `"false"` is stored as one.
    /// See `writeElement`. A name belongs here when WMP's own type is Boolean **and** something
    /// reads it back — add the next one with the corpus count that found it.
    static let standardBooleanProperties: Set<String> = [
        "visible", "enabled", "down", "tabstop", "scrolling", "sticky",
        // The `<VIDEO>` flags. `fullscreen` reaches the host through `truth` already; the other
        // three are stored and read back by the skin that set them.
        "fullscreen", "windowless", "stretchtofit", "shrinktofit", "maintainaspectratio",
        // `<EQUALIZERSETTINGS>`'s two inert booleans, which are answered from the bag (W134).
        "bypass", "enablesplinetension"
    ]

    /// The `<VIEW>` attributes that bound a resize rather than describe a layout. See `writeElement`
    /// and `WMPSceneBuilder`'s `viewLimit`.
    static let viewResizeLimitProperties: Set<String> = [
        "minwidth", "minheight", "maxwidth", "maxheight"
    ]

    private static let inertEqualizerSettingsProperties: Set<String> = [
        "enablesplinetension", "splinetension", "bypass"
    ]

    private static func defaultInertEqualizerSettingsValue(for name: String) -> WMPJSONValue {
        switch name {
        case "enablesplinetension", "bypass": return .bool(false)
        case "splinetension": return .number(0)
        default: return .string("")
        }
    }

    // MARK: - Calls

    private func call(path: String, member: String, arguments: [WMPJSONValue]) -> WMPMemberValue {
        let name = member.lowercased()
        if path.hasPrefix("element:") {
            guard let element = liveElement(String(path.dropFirst("element:".count))) else {
                return .unrecognised("no such element")
            }
            // The element is the `eq` object under the skin's own name, on this surface too
            // (W256): `elvis`'s reset button is `onclick="ElvisEQS.Reset(); balance.Reset();"`,
            // and the equaliser's own methods have to answer it or the handler dies on the first
            // statement and takes the balance reset with it.
            if element.kind == .equalizerSettings {
                let answer = call(path: "eq", member: member, arguments: arguments)
                if case .unrecognised = answer {} else { return answer }
            }
            return callElement(element, name, arguments)
        }
        if path.hasPrefix("playlistitem:") {
            guard let index = Int(path.dropFirst("playlistitem:".count)),
                  snapshot.playlistItems.indices.contains(index), name == "getiteminfo" else {
                return .unrecognised("playlist item member")
            }
            return .value(.string(Self.itemInfo(arguments.first?.string ?? "",
                                                title: snapshot.playlistItems[index].title,
                                                artist: snapshot.playlistItems[index].artist,
                                                album: "")))
        }
        if path.hasPrefix(Self.libraryPathPrefix) { return callLibrary(path, name, arguments) }
        switch (path, name) {
        case ("player.playlistcollection", "getall"):
            return .object(Self.libraryPath("playlists", "all"))
        case ("player.playlistcollection", "getbyname"):
            return .object(Self.libraryPath("playlists", "name", arguments.first?.string ?? ""))
        case ("player.mediacollection", "getall"):
            return .object(Self.libraryPath("query", "all"))
        case ("player.mediacollection", "getbyattribute"):
            return .object(Self.libraryPath("query", arguments.first?.string ?? "",
                                            arguments.count > 1 ? arguments[1].string ?? "" : ""))
        case ("player.mediacollection", "getbyalbum"), ("player.mediacollection", "getbygenre"),
             ("player.mediacollection", "getbyauthor"), ("player.mediacollection", "getbyname"):
            let attribute = ["getbyalbum": "album", "getbygenre": "genre",
                             "getbyauthor": "artist", "getbyname": "title"][name] ?? "title"
            return .object(Self.libraryPath("query", attribute, arguments.first?.string ?? ""))
        case ("player.mediacollection", "getattributestringcollection"):
            return .object(Self.libraryPath("strings", arguments.first?.string ?? "",
                                            arguments.count > 1 ? arguments[1].string ?? "" : ""))
        case ("player.cdromcollection", "item"), ("player.cdromcollection", "getbydrivespecifier"):
            return .value(.null)
        case ("player", "newplaylist"):
            nextScratchSerial += 1
            scratchPlaylists.append((nextScratchSerial, []))
            if scratchPlaylists.count > Self.maximumScratchPlaylists { scratchPlaylists.removeFirst() }
            return .object(Self.libraryPath("scratch", String(nextScratchSerial),
                                            arguments.first?.string ?? ""))
        // An atom is WMP's number for an attribute name; `getItemInfoByAtom` takes it back.
        case ("player.mediacollection", "getmediaatom"):
            let name = (arguments.first?.string ?? "").lowercased()
            return .value(.number(Double(Self.mediaAtoms.firstIndex(of: name) ?? -1)))
        case ("player.controls", "play"):
            if !libraryPlayWithheld { hostCommand("play", nil) }
            return .value(.null)
        case ("player.controls", "pause"): hostCommand("pause", nil); return .value(.null)
        case ("player.controls", "stop"): hostCommand("stop", nil); return .value(.null)
        case ("player.controls", "next"): hostCommand("next", nil); return .value(.null)
        case ("player.controls", "previous"): hostCommand("previous", nil); return .value(.null)
        case ("player.controls", "fastforward"): hostCommand("scanForward", nil); return .value(.null)
        case ("player.controls", "fastreverse"): hostCommand("scanReverse", nil); return .value(.null)
        case ("player.controls", "playitem"):
            guard let index = arguments.first?.number else { return .value(.null) }
            hostCommand("playPlaylistItem:\(Int(index))", nil)
            return .value(.null)
        case ("player.controls", "isavailable"):
            return .value(.bool(isAvailable(arguments.first?.string ?? "")))
        case ("player.settings", "getmode"):
            switch (arguments.first?.string ?? "").lowercased() {
            case "shuffle": return .value(.bool(snapshot.shuffle))
            case "loop": return .value(.bool(snapshot.repeatMode))
            default: return .unrecognised("settings mode")
            }
        case ("player.settings", "setmode"):
            let mode = (arguments.first?.string ?? "").lowercased()
            let on = arguments.count > 1 && arguments[1].truth
            switch mode {
            case "shuffle": hostCommand("setShuffle", .number(on ? 1 : 0))
            case "loop": hostCommand("setRepeat", .number(on ? 1 : 0))
            default: return .unrecognised("settings mode")
            }
            return .value(.null)
        case ("player.settings", "getstring"):
            return .value(.string(preferences[arguments.first?.string ?? ""] ?? ""))
        case ("player.settings", "setstring"):
            savePreference(arguments)
            return .value(.null)
        case ("player.currentmedia", "getiteminfo"), ("player.currentmedia", "getiteminfobyatom"):
            return .value(.string(Self.itemInfo(arguments.first?.string ?? "",
                                                title: snapshot.metadata.title,
                                                artist: snapshot.metadata.artist,
                                                album: snapshot.metadata.album)))
        case ("player.currentmedia", "isreadonly"): inert(); return .value(.bool(true))
        case ("player.currentmedia", "setiteminfo"): return .unrecognised("media is read-only")
        case ("player.currentplaylist", "item"):
            guard let index = arguments.first?.number.map({ Int($0) }),
                  snapshot.playlistItems.indices.contains(index) else { return .value(.null) }
            return .object("playlistitem:\(index)")
        case ("player.dvd", "isavailable"):
            inert()
            return .value(.bool(false))
        // Playlist-level attributes — `IconPaths`, `HDCDMode`, the store's own decorations. A
        // playlist this player made carries none of them, so the empty string is the true answer
        // and the skin's `parseInt` of it takes the same branch WMP's absent attribute would.
        case ("player.currentplaylist", "getiteminfo"):
            inert()
            return .value(.string(""))
        case ("player.currentplaylist", "attributecount"): return .value(.number(3))
        case ("player.currentplaylist", "getattributename"):
            let index = Int(arguments.first?.number ?? 0)
            let names = ["name", "artist", "duration"]
            return .value(.string(names.indices.contains(index) ? names[index] : ""))
        case ("eq", "presettitle"):
            let index = Int(arguments.first?.number ?? 0)
            return .value(.string(EQPreset.allPresets.indices.contains(index)
                ? EQPreset.allPresets[index].name : ""))
        case ("eq", "nextpreset"):
            applyPreset(index: currentPresetIndex + 1)
            return .value(.null)
        case ("eq", "previouspreset"):
            applyPreset(index: currentPresetIndex - 1)
            return .value(.null)
        case ("eq", "reset"):
            for band in 0..<10 { hostCommand("setEQBand:\(band)", .number(0)) }
            return .value(.null)
        case ("theme", "openview"):
            // WMP opens the named view as an *additional* window beside the player and leaves the
            // opener alone; only `theme.currentViewID` replaces a view. That is now what this does:
            // the controller materializes a window for the named view and the calling window is
            // untouched. 90 of the 180 archives ask for a panel this way, 579 times.
            guard let id = arguments.first?.string, !id.isEmpty else {
                return .unrecognised("openView needs a view id")
            }
            hostCommand("openView", .string(id))
            return .value(.null)
        case ("theme", "openviewrelative"):
            // **The placing variant, and its offset is no longer meaningless (W50).** It was
            // deliberately left unimplemented while this engine had one window, because aliasing it
            // to `openView` would have dropped the displacement silently and taken the member out of
            // the demand tally — the trap `INERT` exists for. `Revert` hangs its EQ under the player
            // with `theme.openViewRelative('vwEQ', 0, 130)` and its playlist beside it, in the
            // skin's own pixels from the opener's top-left.
            guard let id = arguments.first?.string, !id.isEmpty else {
                return .unrecognised("openViewRelative needs a view id")
            }
            // The offset rides the action, the way `setEQBand:<n>` and `playPlaylistItem:<n>`
            // already do — a host command carries one value and the view id is it.
            let dx = arguments.count > 1 ? (arguments[1].number ?? 0) : 0
            let dy = arguments.count > 2 ? (arguments[2].number ?? 0) : 0
            guard dx.isFinite, dy.isFinite else {
                hostCommand("openView", .string(id))
                return .value(.null)
            }
            hostCommand("openViewRelative:\(dx),\(dy)", .string(id))
            return .value(.null)
        case ("theme", "closeview"):
            // **Live, not inert, and by name.** 84 of the 180 archives call this and every one of
            // them has been aborting the handler that does: `Halo 2`'s `checkRemoteViewStatus()`
            // dies on `theme.closeView('vidRemoteView')` and never reaches the four statements after
            // it. With no argument it keeps the meaning `view.close()` already posts — close the
            // window the handler is running in.
            let id = arguments.first?.string ?? ""
            hostCommand("closeView", id.isEmpty ? nil : .string(id))
            return .value(.null)
        case ("theme", "loadpreference"):
            // WMP skins use "--" as the absent-preference sentinel. Returning an empty string
            // makes an untouched preference look like a saved value and inverts their defaults.
            return .value(.string(preferences[arguments.first?.string ?? ""] ?? "--"))
        case ("theme", "savepreference"):
            savePreference(arguments)
            return .value(.null)
        case ("theme", "opendialog"):
            // WMP answers a path synchronously; the panel here is main-actor work and the script
            // runs off it, so the host opens the picker and plays what it gets. The skin's own
            // `player.URL = newFile` line then does nothing, which is why this is counted inert
            // rather than live even though the button works.
            guard (arguments.first?.string ?? "").uppercased().contains("FILE_OPEN") else {
                return .unrecognised("only FILE_OPEN is implemented")
            }
            hostCommand("openFileDialog", nil)
            inert()
            return .value(.string(""))
        case ("mediacenter", "getnamedstring"):
            // The same `wmploc.dll` string table `theme.loadString` names, reached by a second
            // route: the corpus asks for `BuyMusicButton`, `BuyMusicURL` and `PLCID`, which are the
            // WMP store's own resources. There is no such library on macOS.
            inert()
            return .value(.string(""))
        case ("theme", "loadstring"):
            // Every corpus use of this names a string inside `wmploc.dll`, which does not exist on
            // macOS and never will. `WMPResourceStrings` answers the handful of ids the corpus
            // itself names (W189) and the empty string for the rest, which is what this returned
            // for all of them before; still counted as inert so the skins asking stay in the census.
            inert()
            return .value(.string(WMPResourceStrings.resolved(arguments.first?.string) ?? ""))
        case ("theme", "playsound"):
            // Sound effects are authored as part of state transitions.  NullPlayer does not play
            // a skin's bundled WAVs, but refusing the call aborts the rest of that handler:
            // AlienMorph opens its shutter, calls `theme.playSound('intro.wav')`, then stops its
            // one-second intro timer.  An unrecognised sound call skipped that final line, so the
            // timer repeatedly opened and closed the centre shutter.
            inert()
            return .value(.null)
        default: return .unrecognised("unknown host member")
        }
    }

    private func callElement(_ element: WMPScriptElement, _ name: String,
                             _ arguments: [WMPJSONValue]) -> WMPMemberValue {
        switch (element.kind, name) {
        case (.popup, "appenditem"), (.listBox, "appenditem"):
            guard element.items.count < 1_024 else { return .value(.null) }
            element.items.append(arguments.first?.string ?? "")
            return .value(.number(Double(element.items.count - 1)))
        case (.popup, "removeallitems"), (.listBox, "deleteall"):
            element.items.removeAll()
            return .value(.null)
        case (.listBox, "insertitem"):
            guard element.items.count < 1_024 else { return .value(.null) }
            let index = max(0, min(element.items.count, Int(arguments.first?.number ?? 0)))
            element.items.insert(arguments.count > 1 ? arguments[1].string ?? "" : "", at: index)
            return .value(.null)
        case (.listBox, "deleteitem"):
            let index = Int(arguments.first?.number ?? -1)
            if element.items.indices.contains(index) { element.items.remove(at: index) }
            return .value(.null)
        case (.popup, "getitem"), (.listBox, "getitem"):
            let index = Int(arguments.first?.number ?? -1)
            return .value(.string(element.items.indices.contains(index) ? element.items[index] : ""))
        case (_, "setcolumnresizemode") where Self.isPlaylist(element.kind):
            let column = Int(arguments.first?.number ?? 0)
            element.columnResizeModes[column] = arguments.count > 1 ? (arguments[1].string ?? "") : ""
            return .value(.null)
        case (.effects, "next"): hostCommand("stepEffect", .number(1)); return .value(.null)
        case (.effects, "previous"): hostCommand("stepEffect", .number(-1)); return .value(.null)
        case (.effects, "nextpreset"): hostCommand("stepEffectPreset", .number(1)); return .value(.null)
        case (.view, "close"): hostCommand("closeView", nil); return .value(.null)
        case (.view, "minimize"): hostCommand("minimizeWindow", nil); return .value(.null)
        // **The only resize a `.wmz` window has (W193).** A skin window is borderless and carries
        // no OS frame, so `onMouseDown="view.size('bottomright')"` — 235 calls in 88 of the 185
        // installed archives — *is* its resize grip, and WMP tracks the pointer from the press
        // that called it until the button comes up. Inert, the user reaches for the macOS window
        // edge instead and skips whatever the skin does around its own resize: `Compact`'s
        // `DoSize()` pins both drawers to their edges for the duration of the drag and unpins them
        // after, so a window widened any other way leaves the drawer behind.
        //
        // The corner rides the value because a host command carries exactly one: `bottomright`
        // (86 archives), `topright` (4), `right` (3), `bottom`/`bottomleft`/`left`/`topleft` (2
        // each). Every one of the 88 authors `resizAble="true"`, which is the same permission the
        // window-edge band asks for, so the host gate costs the corpus nothing.
        case (.view, "size"):
            hostCommand("sizeWindow", .string(arguments.first?.string ?? ""))
            // **WMP's `view.size` does not return until the drag does, and the skins are written
            // against exactly that (W225).** `Compact`'s `DoSize()` pins both drawers to the edges
            // they must ride, calls this, and unpins them again — so the pin is meant to stand for
            // the whole drag. Run straight through, the pin and the unpin both land before the
            // first pixel moves, the drawers keep their absolute positions while the body stretches
            // over them, and their tabs end up buried under it where no click can ever reach them.
            // The call cannot block here, so the mutation count is the seam: see
            // `WMPScriptRuntime.transact`.
            if resizeCallMutationIndex == nil { resizeCallMutationIndex = mutations.count }
            return .value(.null)
        // **The most widely authored control in the corpus: 162 of 180 archives, 196 of them, and
        // 179 tooltipped "Return to full mode"** (W100). WMP leaves skin mode for the player's own
        // shell — menu bar, library, playlist — which this player has no single equivalent of, so
        // it opens the Library Browser: the closest surface NullPlayer has to what that shell is
        // *for*, and the one the user is reaching for when they leave a skin. **It is not
        // `closeView`** — that would take the skin away and is what the backlog row forbade.
        // Every corpus use is the last statement of its handler (0 of 196 have anything after it),
        // so nothing downstream depends on what this returns. 13 of them call it on a named view
        // element rather than `view` (`vFull`, `ballview`, `KidsView`, `digitaldj`…), which is why
        // it dispatches on `.view` and never on the receiver's name.
        case (.view, "returntomediacenter"): hostCommand("toggleLibrary", nil); return .value(.null)
        // WMP tweens these over the third argument's milliseconds. The endpoint still lands in this
        // transaction — the tween itself is rendering work, not a missing member (W38) — but **not
        // until the handler that asked for it has returned**; see `tween(_:_:_:duration:)`.
        case (_, "moveto"):
            tweenGroup(element, duration: arguments.count > 2 ? arguments[2].number : nil,
                       completion: "endmove",
                       channels: [("left", arguments.first?.number ?? 0),
                                  ("top", arguments.count > 1 ? (arguments[1].number ?? 0) : 0)])
            return .value(.null)
        case (_, "resizeto"):
            tweenGroup(element, duration: arguments.count > 2 ? arguments[2].number : nil,
                       completion: nil,
                       channels: [("width", max(0, arguments.first?.number ?? 0)),
                                  ("height", max(0, arguments.count > 1 ? (arguments[1].number ?? 0) : 0))])
            return .value(.null)
        // The third of the trio, and the one the Alienware/ALX family is built out of: its big
        // `m_anim_*` artwork hangs off subviews authored `alphaBlend="0"`, which the scene lays out
        // and drops from the command list, and the only thing that was ever going to bring them
        // back is this call. The endpoint is applied now, so the subtree arrives at the alpha the
        // skin asked for without fading to it.
        case (_, "alphablendto"):
            tweenGroup(element, duration: arguments.count > 1 ? arguments[1].number : nil,
                       completion: "endalphablend",
                       channels: [("alphablend", min(255, max(0, arguments.first?.number ?? 0)))])
            return .value(.null)
        // Nothing draws playlist columns, so this stores what the skin asked for and is counted
        // inert — the census keeps ranking the demand instead of losing it to a working-looking
        // member.
        case (_, "setcolumnwidth") where Self.isPlaylist(element.kind):
            let column = Int(arguments.first?.number ?? 0)
            element.columnWidths[column] = max(0, arguments.count > 1 ? (arguments[1].number ?? 0) : 0)
            inert()
            return .value(.null)
        default: return .unrecognised("element method")
        }
    }

    // MARK: Helpers

    /// **A tween's endpoint is not readable by the rest of the handler that started it.**
    ///
    /// WMP animates `moveTo`/`resizeTo`/`alphaBlendTo` over the duration argument, so an element's
    /// `left` still answers where it *is* for the remainder of the statement list — and skins write
    /// code that depends on exactly that. `Cablemusic`'s playlist tab is
    /// `onClick="PlayListMove();HidePlist();"`: the first call slides the drawer and the second
    /// reads `subPlayList.left` to decide whether the drawer is now open or shut, and hides the
    /// playlist control while it slides. Applying the endpoint inside the call made that read
    /// answer the destination, so closing the drawer left `pl.visible` true and the playlist
    /// stayed on screen over the player forever. Reported as "the playlist is always showing".
    ///
    /// The endpoint still lands in the same transaction, which is W38, and `onEndMove` is still
    /// raised from it, which is W55 — `WMPScriptContext` flushes the queue when the handler
    /// returns, before it raises any completion. **A duration of zero is not a tween**: it is an
    /// instant move and a later read in the same handler must see it, which is what
    /// `movePlayButton()` and `moveSetDrawer()` toggle on.
    /// **One call of the trio, and the decision of whether anything animates (W194).**
    ///
    /// A duration is a request for motion and this engine can only honour it where something is
    /// going to draw the frames: `animatesTweens` is the transaction saying its caller has a clock.
    /// With no clock — a render dump, the corpus census, the windowless dispatcher (W89) — the call
    /// behaves exactly as it did before this row: the endpoint lands at the handler boundary (W38)
    /// and the completion is raised in the same transaction (W55). With one, the endpoint is held
    /// back entirely and `WMPScriptRuntime` steps it, which is the only way `onEndMove` can be
    /// raised when the tween *ends* rather than when the handler returns.
    ///
    /// Three things fall back to the instant path rather than being animated, and each is a case
    /// where a frame would be a guess: a duration of zero (never a tween — `movePlayButton()`'s
    /// `moveTo(x, 116, 0)` toggle depends on reading it back), a channel already at its
    /// destination, and a channel whose current value the model does not hold. That last one is
    /// why the ALX family's `alphaBlendTo` on an unauthored `alphaBlend` still arrives instantly:
    /// an absent `alphaBlend` inherits its parent's (`WMPSceneBuilder.inheritedAlpha`), so the
    /// only number a fade could start from is the opaque default, and the corpus leans on those
    /// subtrees *arriving* rather than on their fading in.
    private func tweenGroup(_ element: WMPScriptElement, duration: Double?, completion: String?,
                            channels: [(property: String, value: Double)]) {
        // **A later call supersedes an earlier one on the same channels, in this transaction too.**
        // `Plus! Space`'s `TogglePlaylist()` with the equaliser open runs `CloseEqualizer()` —
        // `svDrawer.moveTo(left, closed, 120)` — then `svDrawer.moveTo(left, opened, 120)` in the
        // same handler. The second call reads `top` as still open and drops as already-there, so
        // unless it also cancels the first, the drawer slides shut and its `onEndMove` reveals the
        // playlist over the player. `WMPScriptRuntime.register` does the same across transactions.
        let superseded = Set(channels.map { $0.property })
        tweens = tweens.compactMap { queued in
            guard queued.stableID == element.stableID else { return queued }
            let kept = queued.channels.filter { !superseded.contains($0.property) }
            guard kept.count != queued.channels.count else { return queued }
            WMPTweenTrace.log("supersede \(element.id)"
                + " channels=[\(superseded.sorted().joined(separator: ","))] kept=\(kept.count)")
            guard !kept.isEmpty else { return nil }
            return .init(targetID: queued.targetID, stableID: queued.stableID, channels: kept,
                         durationMilliseconds: queued.durationMilliseconds,
                         completionEvent: queued.completionEvent)
        }
        let animates = animatesTweens && (duration.map { $0.isFinite && $0 > 0 } ?? false)
        var resolved: [WMPScriptTweenChannel] = []
        if animates {
            for channel in channels {
                // `alphaBlend` is the one property with a meaningful default: absent means the
                // element inherits, which at full opacity is 255.
                let current = element.properties[channel.property]?.number
                    ?? (channel.property == "alphablend" ? 255 : nil)
                guard let current, current.isFinite, current != channel.value else {
                    let held: String = element.properties[channel.property]?.number
                        .map { "\($0)" } ?? "nil"
                    let why: String = current == nil ? "no-current-value" : "already-there"
                    WMPTweenTrace.log("drop \(element.id).\(channel.property)"
                        + " to=\(channel.value) current=\(held) reason=\(why)")
                    continue
                }
                resolved.append(.init(property: channel.property, from: current, to: channel.value))
            }
        }
        let durationText: String = duration.map { "\($0)" } ?? "nil"
        WMPTweenTrace.log("call \(element.id) duration=\(durationText)"
            + " clock=\(animatesTweens) animates=\(animates)"
            + " channels=[\(channels.map { "\($0.property)->\($0.value)" }.joined(separator: ","))]"
            + " resolved=\(resolved.count)")
        guard animates, !resolved.isEmpty, tweens.count < WMPJScriptProtocol.maximumTweens else {
            for channel in channels {
                tween(element, channel.property, .number(channel.value), duration: duration)
            }
            // A tween with nowhere to travel is over the moment it starts, so its completion is
            // now — the step a sequence chains off must not be lost to a no-op move.
            if let completion { completions.append((element.stableID, completion)) }
            return
        }
        tweens.append(.init(targetID: element.id, stableID: element.stableID, channels: resolved,
                            durationMilliseconds: duration ?? 0, completionEvent: completion))
    }

    private func tween(_ element: WMPScriptElement, _ property: String, _ value: WMPJSONValue,
                       duration: Double?) {
        guard let duration, duration.isFinite, duration > 0 else {
            _ = writeElement(element, property, value)
            return
        }
        pendingTweens.append((element, property, value))
    }

    /// **One tween frame, written where the handler's endpoint would have gone.**
    ///
    /// The mutation this records is what carries the frame into the view's overrides, and it leaves
    /// the element reading where it now *is* — which is what a handler that runs mid-tween has to
    /// see, and the whole point of W112.
    func applyTweenFrame(targetID: String, property: String, value: Double) {
        guard let element = element(targetID) else { return }
        _ = writeElement(element, property, .number(value))
    }

    /// A finished tween's `onEndMove`/`onEndAlphaBlend`, queued for this transaction's completion
    /// pass — the one `WMPScriptContext.raiseCompletionHandlers` already runs (W55).
    func completeTween(stableID: Int, event: String) {
        completions.append((stableID, event))
    }

    /// Applies every endpoint queued since the last flush. Called by `WMPScriptContext` at each
    /// handler boundary — the point at which WMP's own tween would have been free to advance.
    func flushPendingTweens() {
        guard !pendingTweens.isEmpty else { return }
        let queued = pendingTweens
        pendingTweens.removeAll()
        for entry in queued { _ = writeElement(entry.element, entry.property, entry.value) }
    }

    private func hostCommand(_ action: String, _ value: WMPJSONValue?) {
        guard hostCommands.count < WMPJScriptProtocol.maximumHostCommands else { return }
        hostCommands.append(.init(action: action, value: value))
    }

    private func savePreference(_ arguments: [WMPJSONValue]) {
        guard let key = arguments.first?.string, !key.isEmpty else { return }
        let value = arguments.count > 1 ? (arguments[1].string ?? "") : ""
        preferences[key] = value
        guard preferenceWrites.count < WMPJScriptProtocol.maximumPreferenceCount else { return }
        preferenceWrites.append(.init(key: key, value: value))
    }

    private func applyPreset(index: Int) {
        let presets = EQPreset.allPresets
        guard !presets.isEmpty else { return }
        let wrapped = ((index % presets.count) + presets.count) % presets.count
        currentPresetIndex = wrapped
        for (band, gain) in presets[wrapped].bands.prefix(10).enumerated() {
            hostCommand("setEQBand:\(band)", .number(Double(gain)))
        }
    }

    private func isAvailable(_ name: String) -> Bool {
        switch name.lowercased() {
        case "play": return snapshot.isEnabled(.play)
        case "pause": return snapshot.isEnabled(.pause)
        case "stop": return snapshot.isEnabled(.stop)
        case "previous": return snapshot.isEnabled(.previous)
        case "next": return snapshot.isEnabled(.next)
        case "currentposition", "fastforward", "fastreverse": return snapshot.isEnabled(.seek)
        default: return false
        }
    }

    private static func itemInfo(_ name: String, title: String, artist: String,
                                 album: String) -> String {
        switch name.lowercased() {
        case "title", "name": return title
        case "artist", "author", "wm/albumartist": return artist
        case "album", "wm/albumtitle": return album
        default: return ""
        }
    }

    private static func timeString(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static let standardNumericProperties: Set<String> = [
        "left", "top", "width", "height", "zindex", "value", "alpha", "min", "max",
        // The marquee's clock and step. Rendered, so a script write has to commit as a mutation
        // rather than be stored inert; see `scrolling` below.
        "scrollingdelay", "scrollingamount",
        // Rendered, and numeric: an unset read answers 0 like every other number here.
        "fontsize",
        // **The property `Plus! HueShifter` is named after (W173).** Degrees of hue rotation on
        // the element's artwork. Rendered, so a write must commit as a mutation rather than be
        // stored inert — `changeHue()` assigns it to five candies per press and nothing else in
        // the handler would tell the scene anything moved. Unset reads 0, which is no shift.
        "hueshift"
    ]

    static let standardElementProperties: Set<String> = standardNumericProperties.union([
        // `alphaBlend` is deliberately not in `standardNumericProperties`: it is rendered, so a
        // write to it must commit as a mutation, but its unset value is 255 and not the 0 that set
        // answers with. `readElement` holds that default.
        "alphablend",
        "visible", "enabled", "down", "text", "tooltip", "image", "backgroundimage",
        "foregroundcolor", "backgroundcolor", "transparencycolor", "cursor", "sticky",
        "horizontalalignment", "verticalalignment",
        // **The `<TEXT>` face, laid out by script.** All four are read by `WMPSceneBuilder`'s text
        // path, so a write to one has to commit as a mutation rather than be stored inert. They
        // were only reached when the markup happened to author the same attribute:
        // `Cablemusic`'s `LayoutProgramInfoExpanded()` sets `justification` on ten readouts that
        // declare none, and every one of those writes was dropped, drawing a right-aligned label
        // column flush left. `justification` alone is 788 authored uses across 150 of the 172
        // archives the markup census can read.
        "justification", "fontface", "fontstyle",
        // **`scrolling` is written by script far more often than it is authored.** `WoW`'s
        // `metadata` declares `scrollingDelay` and `scrollingAmount` in markup and never
        // `scrolling` — the handler turns it on when the new title does not fit. Without this the
        // write was stored inert, never reached the scene, and the marquee could not start.
        "scrolling"
    ])
}

/// The globals WMP defines for its own enumerations. A skin compares `player.openState` against
/// `osMediaOpen` rather than against a number, so without these Corona's `OnLoad` throws a
/// `ReferenceError` on its first state test and every later line of the handler is lost.
enum WMPScriptConstants {
    static let osUndefined = 0
    static let osMediaOpening = 12
    static let osMediaOpen = 13

    /// **The `os*` value `player.openState` answers — the one derivation, read by the property, by
    /// the `NewState` argument, and by the event edge (W252).**
    ///
    /// `osMediaOpen` used to be the answer the instant the queue was non-empty, so a media that was
    /// still opening claimed to be open and **the only `openstatechange` a video ever raised landed
    /// before the decoder had reported a picture size**. `Revert`'s `vwPlayer_SelectVideoOrVis()`
    /// shows its `<VIDEO>` only when `player.openState == 13` *and*
    /// `player.currentMedia.imageSourceWidth/Height` are both above zero, and hides it otherwise;
    /// reading a zero size at that one edge latched the visualizer on, and nothing raised the
    /// handler again for the rest of the film. Reported live 2026-09-21 as a video playing with no
    /// picture in the skin.
    ///
    /// `WMPHostSnapshot.State.transitioning` is exactly the interval WMP spells `osMediaOpening`:
    /// VLC is running the media and has not answered with a size yet. Reporting it keeps the
    /// distinction WMP's own enumeration makes, and the `12 -> 13` edge that follows raises
    /// `openstatechange` a second time — with `imageSourceWidth` now non-zero, which is the reading
    /// the handler was written against. Audio never transitions, so nothing outside video moves.
    ///
    /// **A media only opens once.** `transitioning` is also raised mid-film while VLC rebuilds its
    /// drawable output, and a `13 -> 12 -> 13` round trip there would hide and re-show `Revert`'s
    /// picture on every rebuild. `videoEvent` is the latched snapshot that survives exactly that
    /// gap (see `WMPVideoEventLatch`), so a media that has ever reported a size stays open.
    static func openState(for snapshot: WMPHostSnapshot?) -> Int {
        guard let snapshot, snapshot.playlistCount > 0 else { return osUndefined }
        let opening = snapshot.state == .transitioning && !snapshot.videoEvent.hasVideo
        return opening ? osMediaOpening : osMediaOpen
    }

    static let values: [String: Int] = [
        // Open state
        "osUndefined": 0, "osPlaylistChanging": 1, "osPlaylistLocating": 2,
        "osPlaylistConnecting": 3, "osPlaylistLoading": 4, "osPlaylistOpening": 5,
        "osPlaylistOpenNoMedia": 6, "osPlaylistChanged": 7, "osMediaChanging": 8,
        "osMediaLocating": 9, "osMediaConnecting": 10, "osMediaLoading": 11,
        "osMediaOpening": 12, "osMediaOpen": 13,
        // The rest of `WMPOpenState`. A skin switches over the whole enumeration — `Corona`'s
        // `OnOpenStateChangeTransport` names `osMediaWaiting` — and a missing global is a
        // `ReferenceError` that kills the handler, which is the W37 class rather than a gap in a
        // table nothing reads.
        "osBeginCodecAcquisition": 14, "osEndCodecAcquisition": 15,
        "osBeginLicenseAcquisition": 16, "osEndLicenseAcquisition": 17,
        "osBeginIndividualization": 18, "osEndIndividualization": 19,
        "osMediaWaiting": 20, "osOpeningUnknownURL": 21,
        // Play state
        "psUndefined": 0, "psStopped": 1, "psPaused": 2, "psPlaying": 3,
        "psScanForward": 4, "psScanReverse": 5, "psBuffering": 6, "psWaiting": 7,
        "psMediaEnded": 8, "psTransitioning": 9, "psReady": 10, "psReconnecting": 11
    ]

    static func playState(for state: WMPHostSnapshot.State) -> Int {
        switch state {
        case .stopped: return 1
        case .paused: return 2
        case .playing: return 3
        case .transitioning: return 9
        }
    }
}

extension WMPJSONValue {
    /// JScript truthiness, which is what a skin writing `x.visible = someString` means.
    var truth: Bool {
        switch self {
        case .null: return false
        case let .bool(value): return value
        case let .number(value): return value != 0
        case let .string(value):
            if value.caseInsensitiveCompare("false") == .orderedSame { return false }
            return !value.isEmpty
        }
    }
}
