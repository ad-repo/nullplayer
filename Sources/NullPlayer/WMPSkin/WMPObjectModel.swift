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
        case "eq": return readEqualizer(name)
        case "theme": return readTheme(name)
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

    private func readNetwork(_ name: String) -> WMPMemberValue {
        switch name {
        case "bufferingprogress": return .value(.number(snapshot.bufferingProgress))
        case "receptionquality": return .value(.number(snapshot.receptionQuality))
        case "bandwidth", "framesskipped", "lostpackets", "receivedpackets":
            inert(); return .value(.number(0))
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
        case "loadpreference", "savepreference", "loadstring": return .function
        default: return .unrecognised("theme member")
        }
    }

    private func readElement(_ element: WMPScriptElement, _ name: String) -> WMPMemberValue {
        if let method = elementMethod(element, name) { _ = method; return .function }
        switch name {
        case "id": return .value(.string(element.id))
        case "itemcount" where element.kind == .popup:
            return .value(.number(Double(element.items.count)))
        default: break
        }
        if let value = element.properties[name] { return .value(value) }
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

    private func readViewHost(_ name: String) -> WMPMemberValue? {
        switch name {
        case "close", "minimize": return .function
        default: return nil
        }
    }

    private func elementMethod(_ element: WMPScriptElement, _ name: String) -> String? {
        switch (element.kind, name) {
        case (.popup, "appenditem"), (.popup, "removeallitems"), (.popup, "getitem"): return name
        case (_, "moveto"), (_, "resizeto"): return name
        case (.view, "close"), (.view, "minimize"): return name
        default:
            return Self.isPlaylist(element.kind) && name == "setcolumnresizemode" ? name : nil
        }
    }

    /// Names WMP defines as element *methods*. One of these that this engine does not implement
    /// stays unrecognised rather than falling into the open property surface — otherwise
    /// `svPlaylist.moveTo(…)` reads as an empty string, fails with a bare `TypeError`, and the
    /// method never appears in the demand tally that ranks the work.
    static let elementMethodVocabulary: Set<String> = [
        "moveto", "resizeto", "show", "hide", "close", "minimize", "maximize", "appenditem",
        "removeallitems", "removeitem", "deleteitem", "getitem", "selectitem", "setcolumnresizemode",
        "setfocus", "invoke", "click", "play", "stop", "next", "previous"
    ]

    /// `PLAYLIST`, `DROPDOWNPLAYLIST` and the `ITEMSPLAYLIST` the corpus actually ships — the last
    /// is not a modelled element kind yet, and its column setup is the first thing Corona's
    /// `OnLoad` does, so refusing it there costs the whole handler.
    static func isPlaylist(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .playlist, .dropdownPlaylist: return true
        case let .unknown(tag): return tag.lowercased().hasSuffix("playlist")
        default: return false
        }
    }

    // MARK: - Writes

    private var sessionSettings: [String: WMPJSONValue] = [:]

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
        if path == "eq", name.hasPrefix("gainlevel"), let band = Int(name.dropFirst("gainlevel".count)),
           (1...10).contains(band) {
            hostCommand("setEQBand:\(band - 1)", value)
            return .value(value)
        }
        return .unrecognised("read-only or unknown member")
    }

    private func writeElement(_ element: WMPScriptElement, _ name: String,
                              _ value: WMPJSONValue) -> WMPMemberValue {
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
        case ("theme", "loadpreference"):
            return .value(.string(preferences[arguments.first?.string ?? ""] ?? ""))
        case ("theme", "savepreference"):
            savePreference(arguments)
            return .value(.null)
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
        case (.view, "close"): hostCommand("closeView", nil); return .value(.null)
        case (.view, "minimize"): hostCommand("minimizeWindow", nil); return .value(.null)
        // WMP tweens these over the third argument's milliseconds. The endpoint is applied now and
        // the tween is not drawn yet, so a pane arrives where the skin put it without sliding; the
        // animation is tracked as rendering work, not as a missing member.
        case (_, "moveto"):
            _ = writeElement(element, "left", .number(arguments.first?.number ?? 0))
            _ = writeElement(element, "top", .number(arguments.count > 1 ? (arguments[1].number ?? 0) : 0))
            return .value(.null)
        case (_, "resizeto"):
            _ = writeElement(element, "width", .number(max(0, arguments.first?.number ?? 0)))
            _ = writeElement(element, "height",
                             .number(max(0, arguments.count > 1 ? (arguments[1].number ?? 0) : 0)))
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
        "left", "top", "width", "height", "zindex", "value", "alpha", "min", "max"
    ]

    static let standardElementProperties: Set<String> = standardNumericProperties.union([
        "visible", "enabled", "down", "text", "tooltip", "image", "backgroundimage",
        "foregroundcolor", "backgroundcolor", "transparencycolor", "cursor", "sticky",
        "horizontalalignment", "verticalalignment"
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
