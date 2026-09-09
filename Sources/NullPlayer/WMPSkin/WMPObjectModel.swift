import CoreGraphics
import Foundation
import NullPlayerCore

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
    var elements: [String: WMPScriptElement] = [:]
    private var elementOrder: [String] = []
    /// The preset the skin last selected. WMP tracks one; the engine has no notion of a current
    /// preset, so it is session state and every selection is applied as ten band commands.
    var currentPresetIndex = 0

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
    private(set) var diagnostics: [WMPJScriptDiagnostic] = []
    /// Reads made since the last `beginDependencyCapture()`, in order. One expression's dependency
    /// list; the topological sort is built out of these.
    private(set) var dependencyReads: [String] = []
    private var capturingDependencies = false

    private static let maximumCalls = 4_096

    // MARK: Transaction lifecycle

    func beginTransaction(snapshot: WMPHostSnapshot, preferences: [String: String], viewID: String) {
        self.snapshot = snapshot
        self.preferences = preferences
        currentViewID = viewID
        calls.removeAll(keepingCapacity: true)
        mutations.removeAll(keepingCapacity: true)
        hostCommands.removeAll(keepingCapacity: true)
        preferenceWrites.removeAll(keepingCapacity: true)
        repaintHints.removeAll(keepingCapacity: true)
        diagnostics.removeAll(keepingCapacity: true)
        dependencyReads.removeAll(keepingCapacity: true)
        completions.removeAll(keepingCapacity: true)
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
        for element in elements {
            let key = WMPPath.fold(element.id)
            guard self.elements[key] == nil else { continue }
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
    }

    func captureElements() -> ElementRegistry { .init(elements: elements, order: elementOrder) }

    func restoreElements(_ registry: ElementRegistry) {
        elements = registry.elements
        elementOrder = registry.order
    }

    var elementIDs: [String] { elementOrder }

    func element(_ id: String) -> WMPScriptElement? { elements[WMPPath.fold(id)] }

    // MARK: Member access

    /// `path` is a receiver address: a host object path (`player.controls`), `element:<id>`, or
    /// `playlistitem:<index>`.
    func get(_ path: String, _ member: String) -> WMPMemberValue {
        let result = read(path: path, member: member)
        record(path: path, member: member, kind: .read, result: result)
        return result
    }

    @discardableResult
    func set(_ path: String, _ member: String, _ value: WMPJSONValue) -> WMPMemberValue {
        let result = write(path: path, member: member, value: value)
        record(path: path, member: member, kind: .write, result: result, written: value)
        return result
    }

    func invoke(_ path: String, _ member: String, _ arguments: [WMPJSONValue]) -> WMPMemberValue {
        let result = call(path: path, member: member, arguments: arguments)
        record(path: path, member: member, kind: .invoke, result: result)
        return result
    }

    /// Does this receiver answer this member at all? Used by the `with` scope a geometry
    /// expression is evaluated in, so an identifier the element does not own falls through to the
    /// globals instead of being claimed and then failing.
    func recognises(_ path: String, _ member: String) -> Bool {
        let name = member.lowercased()
        if path.hasPrefix("element:") {
            guard let element = elements[String(path.dropFirst("element:".count))] else { return false }
            // Deliberately **not** the open property surface the read path answers with. Inside a
            // `with` scope this trap decides whether an identifier belongs to the element or to the
            // globals, and an element that claims every name swallows the skin's own functions:
            // Corona's `GetEqSliderLeft(1)` resolved to an empty string and all ten equaliser
            // sliders lost their geometry.
            if name == "id" { return true }
            if element.properties[name] != nil { return true }
            if element.authored.contains(name) { return true }
            if Self.standardElementProperties.contains(name) { return true }
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

    // MARK: - Reads

    private func read(path: String, member: String) -> WMPMemberValue {
        let name = member.lowercased()
        if path.hasPrefix("element:") {
            guard let element = elements[String(path.dropFirst("element:".count))] else {
                return .unrecognised("no such element")
            }
            return readElement(element, name)
        }
        if path.hasPrefix("playlistitem:") {
            guard let index = Int(path.dropFirst("playlistitem:".count)),
                  snapshot.playlistItems.indices.contains(index) else {
                return .unrecognised("no such playlist item")
            }
            let item = snapshot.playlistItems[index]
            switch name {
            case "name", "sourceurl": return .value(.string(item.title))
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
        case "eq": return readEqualizer(name)
        case "theme": return readTheme(name)
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
        // **There is no DVD, and saying so is the answer rather than refusing the question.**
        // `Corona`'s metadata table opens with `player.dvd.isAvailable('dvd')==false` on all three
        // of its rows, so an unrecognised `dvd` aborted the handler that reads the track title —
        // and, further down the same chain, the one that turns its visualization pane on.
        case "dvd": return .object("player.dvd")
        // WMP reports these as numbers from its own enumerations, and skins compare them against
        // the `ps*`/`os*` globals rather than against strings.
        case "playstate": return .value(.number(Double(WMPScriptConstants.playState(for: snapshot.state))))
        case "openstate":
            return .value(.number(Double(snapshot.playlistCount > 0
                ? WMPScriptConstants.osMediaOpen : WMPScriptConstants.osUndefined)))
        case "status": inert(); return .value(.string(""))
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
        case "volume": return .value(.number(snapshot.volume * 100))
        case "balance": return .value(.number(snapshot.balance * 100))
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
        case "getiteminfo", "getiteminfobyatom", "setiteminfo", "isreadonly": return .function
        // No video surface exists yet, so there is genuinely no image source. Zero is the true
        // answer rather than a placeholder, and it is what makes Corona take its audio path.
        case "imagesourcewidth", "imagesourceheight": return .value(.number(0))
        case "attributecount": return .value(.number(3))
        default: return .unrecognised("media member")
        }
    }

    private func readPlaylist(_ name: String) -> WMPMemberValue {
        switch name {
        case "count": return .value(.number(Double(snapshot.playlistCount)))
        case "name": inert(); return .value(.string("Now Playing"))
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
        case "bufferingprogress": return .value(.number(snapshot.bufferingProgress))
        case "receptionquality": return .value(.number(snapshot.receptionQuality))
        case "bandwidth", "framesskipped", "lostpackets", "receivedpackets":
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
        case "enabled": return .value(.bool(snapshot.equalizer.enabled))
        case "presetcount": return .value(.number(Double(EQPreset.allPresets.count)))
        case "currentpreset": return .value(.number(Double(currentPresetIndex)))
        case "currentpresettitle":
            return .value(.string(EQPreset.allPresets.indices.contains(currentPresetIndex)
                ? EQPreset.allPresets[currentPresetIndex].name : ""))
        case "presettitle", "nextpreset", "previouspreset", "reset": return .function
        case "bands": return .value(.number(10))
        default: return .unrecognised("eq member")
        }
    }

    private func readTheme(_ name: String) -> WMPMemberValue {
        switch name {
        case "currentviewid": return .value(.string(currentViewID))
        case "loadpreference", "savepreference", "loadstring", "opendialog", "openview":
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

    private func readElement(_ element: WMPScriptElement, _ name: String) -> WMPMemberValue {
        if let method = elementMethod(element, name) { _ = method; return .function }
        switch name {
        case "id": return .value(.string(element.id))
        case "itemcount" where element.kind == .popup:
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
        if let value = element.properties[name] { return .value(value) }
        // WMP's `alphaBlend` is 0-255 and an element that never authored it is fully opaque. The
        // unset-numeric default of 0 would tell a skin reading its own element that it is invisible,
        // and a fade written as `x.alphaBlendTo(x.alphaBlend + 32, 200)` would never leave zero.
        if name == "alphablend" { return .value(.number(255)) }
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
    private static func measuredTextWidth(_ element: WMPScriptElement) -> CGFloat {
        guard let value = element.properties["value"]?.string, !value.isEmpty else { return 0 }
        let style = (element.properties["fontstyle"]?.string ?? "").lowercased()
        let face = ["fontface", "fonttype"].lazy
            .compactMap { element.properties[$0]?.string }
            .first { !$0.isEmpty } ?? "Arial"
        let size = element.properties["fontsize"]?.number ?? 12
        return WMPTextMetrics.width(of: value, fontName: face, fontSize: CGFloat(max(1, size)),
                                    bold: style.contains("bold"), italic: style.contains("italic"))
    }

    private func readViewHost(_ name: String) -> WMPMemberValue? {
        switch name {
        case "close", "minimize": return .function
        default: return nil
        }
    }

    private func elementMethod(_ element: WMPScriptElement, _ name: String) -> String? {
        switch (element.kind, name) {
        case (.popup, "appenditem"), (.popup, "removeallitems"), (.popup, "getitem"): return name
        // 82 archives call `visEffects.next()` and 74 `visEffects.previous()` — the corpus's own
        // way of cycling the surface, and the reason the selector never needed a menu (W101).
        case (.effects, "next"), (.effects, "previous"), (.effects, "nextpreset"): return name
        case (_, "moveto"), (_, "resizeto"), (_, "alphablendto"): return name
        case (.view, "close"), (.view, "minimize"): return name
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
        "moveto", "resizeto", "alphablendto", "close", "minimize",
        "appenditem", "removeallitems", "getitem", "setcolumnresizemode", "setcolumnwidth",
        "next", "previous", "nextpreset"
    ]

    /// Names WMP defines as element *methods*. One of these that this engine does not implement
    /// stays unrecognised rather than falling into the open property surface — otherwise
    /// `svPlaylist.moveTo(…)` reads as an empty string, fails with a bare `TypeError`, and the
    /// method never appears in the demand tally that ranks the work.
    static let elementMethodVocabulary: Set<String> = [
        "moveto", "resizeto", "alphablendto", "show", "hide", "close", "minimize", "maximize",
        "appenditem", "removeallitems", "removeitem", "deleteitem", "getitem", "selectitem",
        "setcolumnresizemode", "setcolumnwidth", "setfocus", "invoke", "click", "play", "stop",
        "next", "previous", "nextpreset", "settings"
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
    /// Written by the skin, read back by the skin, and behind none of it is a host. See
    /// `readMediaCenter`.
    private var mediaCenterState: [String: WMPJSONValue] = [:]

    private func write(path: String, member: String, value: WMPJSONValue) -> WMPMemberValue {
        let name = member.lowercased()
        if path.hasPrefix("element:") {
            guard let element = elements[String(path.dropFirst("element:".count))] else {
                return .unrecognised("no such element")
            }
            return writeElement(element, name, value)
        }
        switch (path, name) {
        case ("player.controls", "currentposition"):
            hostCommand("seekSeconds", value)
            return .value(value)
        case ("player.settings", "volume"):
            hostCommand("volumePercent", value)
            return .value(value)
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
        case ("eq", "enabled"):
            hostCommand("setEQEnabled", .number(value.truth ? 1 : 0))
            return .value(value)
        case ("eq", "currentpreset"):
            applyPreset(index: Int(value.number ?? 0))
            return .value(value)
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
                              _ value: WMPJSONValue) -> WMPMemberValue {
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
        let rendered = element.authored.contains(name) || Self.standardElementProperties.contains(name)
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

    // MARK: - Calls

    private func call(path: String, member: String, arguments: [WMPJSONValue]) -> WMPMemberValue {
        let name = member.lowercased()
        if path.hasPrefix("element:") {
            guard let element = elements[String(path.dropFirst("element:".count))] else {
                return .unrecognised("no such element")
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
        switch (path, name) {
        case ("player.controls", "play"): hostCommand("play", nil); return .value(.null)
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
            // WMP opens the named view as an *additional* window. This app has exactly one WMP
            // window, so the honest reduction is to present the view: that is precisely right for
            // the dominant corpus use — a windowless `controlView` whose `onLoad` opens the real
            // player — and for an auxiliary panel it is a view switch the host can return from,
            // which `closeView` does. It is live, not inert: something is drawn as a result.
            guard let id = arguments.first?.string, !id.isEmpty else {
                return .unrecognised("openView needs a view id")
            }
            hostCommand("openView", .string(id))
            return .value(.null)
        case ("theme", "loadpreference"):
            return .value(.string(preferences[arguments.first?.string ?? ""] ?? ""))
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
            // macOS and never will. The empty string is the whole of what can be answered; it is
            // counted as inert so the skins asking for it stay visible in the census.
            inert()
            return .value(.string(""))
        default: return .unrecognised("unknown host member")
        }
    }

    private func callElement(_ element: WMPScriptElement, _ name: String,
                             _ arguments: [WMPJSONValue]) -> WMPMemberValue {
        switch (element.kind, name) {
        case (.popup, "appenditem"):
            guard element.items.count < 1_024 else { return .value(.null) }
            element.items.append(arguments.first?.string ?? "")
            return .value(.number(Double(element.items.count - 1)))
        case (.popup, "removeallitems"):
            element.items.removeAll()
            return .value(.null)
        case (.popup, "getitem"):
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
        // WMP tweens these over the third argument's milliseconds. The endpoint is applied now and
        // the tween is not drawn yet, so a pane arrives where the skin put it without sliding; the
        // animation is tracked as rendering work, not as a missing member.
        case (_, "moveto"):
            _ = writeElement(element, "left", .number(arguments.first?.number ?? 0))
            _ = writeElement(element, "top", .number(arguments.count > 1 ? (arguments[1].number ?? 0) : 0))
            completions.append((element.stableID, "endmove"))
            return .value(.null)
        case (_, "resizeto"):
            _ = writeElement(element, "width", .number(max(0, arguments.first?.number ?? 0)))
            _ = writeElement(element, "height",
                             .number(max(0, arguments.count > 1 ? (arguments[1].number ?? 0) : 0)))
            return .value(.null)
        // The third of the trio, and the one the Alienware/ALX family is built out of: its big
        // `m_anim_*` artwork hangs off subviews authored `alphaBlend="0"`, which the scene lays out
        // and drops from the command list, and the only thing that was ever going to bring them
        // back is this call. The endpoint is applied now, so the subtree arrives at the alpha the
        // skin asked for without fading to it.
        case (_, "alphablendto"):
            _ = writeElement(element, "alphablend",
                             .number(min(255, max(0, arguments.first?.number ?? 0))))
            completions.append((element.stableID, "endalphablend"))
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
        "scrollingdelay", "scrollingamount"
    ]

    static let standardElementProperties: Set<String> = standardNumericProperties.union([
        // `alphaBlend` is deliberately not in `standardNumericProperties`: it is rendered, so a
        // write to it must commit as a mutation, but its unset value is 255 and not the 0 that set
        // answers with. `readElement` holds that default.
        "alphablend",
        "visible", "enabled", "down", "text", "tooltip", "image", "backgroundimage",
        "foregroundcolor", "backgroundcolor", "transparencycolor", "cursor", "sticky",
        "horizontalalignment", "verticalalignment",
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
    static let osMediaOpen = 13

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
