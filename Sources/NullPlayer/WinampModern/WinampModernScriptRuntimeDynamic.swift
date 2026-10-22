import AppKit
import CoreGraphics
import Foundation

/// The objects a script makes for itself with `new` — `Timer`, `List`, `Map`, `Region`, `XmlDoc`,
/// a GUI object before its `init` — and the roles their first distinguishing call settles. Split
/// out of `WinampModernScriptRuntimeObject.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    struct DynamicObjectState {
        var role: DynamicRole = .generic
        var delayMilliseconds: Int32 = 5_000
        /// Backing store for a MAKI `List`. Kept on every dynamic object rather than in the role: a
        /// `List` is created by the same `new` as a `Timer` or a `Map` and only its first list call
        /// would distinguish it, and nothing else ever touches these items.
        var items: [MakiValue] = []
        /// Element paths an `XmlDoc` has registered with `parser_addCallback`, in the order the
        /// script added them. Kept beside `items` for the same reason: the role is settled by the
        /// first call that only an `XmlDoc` accepts, and these arrive before `parser_start`.
        var parserCallbacks: [String] = []
        /// A script-owned string object's contents — `new`, `setText(…)`, `getText()`. Kept here for
        /// the same reason as `items`: `new` says nothing about the class, and this is the first call
        /// that would distinguish one.
        var text: String = ""
    }

    /// Arms (or re-arms) a script `Timer` to fire `onTimer` every `delayMilliseconds`.
    private func scheduleTimer(id: UInt64, delayMilliseconds: Int32) throws {
        let reference = MakiObjectReference(.dynamic(id))
        _ = try timers.schedule(id: id, period: TimeInterval(max(8, delayMilliseconds)) / 1_000) { [weak self] in
            guard let self else { return }
            _ = try? self.dispatch(target: reference, event: "ontimer", arguments: [])
        }
    }

    func invokeDynamic(method: String, id: UInt64, arguments: [MakiValue],
                               program: MakiProgram) throws -> MakiValue {
        guard var state = dynamicObjects[id] else { return .null }
        // A script may call one of *this* object's event handlers as a method, exactly as it may a
        // GUI object's or `System`'s (the two routes above). For a `Timer` that is the "run the
        // timer's body now, don't wait for the next tick" idiom: Big Bento Modern's songticker
        // answers `sendAction("cancelinfo")` — which `seek.maki` posts on every mouse-up and on
        // `onSetFinalPosition` — with `timer.onTimer()`, and without this the whole `onAction`
        // handler aborted there, leaving the ticker stuck on its `Seek: 1:13/4:05 (30%)` preview.
        if WinampModernScriptSignatures.dispatchableEventArity[method] != nil {
            _ = try dispatch(target: MakiObjectReference(.dynamic(id)), event: method,
                             arguments: arguments)
            return method == "onaction" ? .integer(0) : .null
        }
        if let value = try invokeTreeItem(method: method, id: id, arguments: arguments) { return value }
        if case .pendingGUI(let type, var attributes, var calls) = state.role {
            switch method {
            case "setxmlparam":
                attributes[arguments[0].stringValue.lowercased()] = arguments[1].stringValue
                dynamicObjects[id]?.role = .pendingGUI(type: type, attributes: attributes, calls: calls)
                return .null
            case "getxmlparam":
                return .string(attributes[arguments[0].stringValue.lowercased()] ?? "")
            case "init":
                break
            case _ where signature(for: method, classGUID: nil) != nil
                && calls.count < Self.maximumPendingCalls:
                calls.append((method, arguments))
                dynamicObjects[id]?.role = .pendingGUI(type: type, attributes: attributes, calls: calls)
                return .null
            default:
                break
            }
        }
        switch method {
        // `GammaSet.apply()` — switch to the theme this object names, through the one route
        // `System.setColorTheme` already uses. A theme the skin does not ship is refused by the
        // catalog and the call is simply inert.
        case "apply":
            guard case .gammaSet(let name) = state.role else { return .null }
            // Re-applying the theme already showing is how a script shows the groups it retinted.
            if hooks.themeSwitchRequested?(name) != true,
               name.caseInsensitiveCompare(loadedSkin.themeCoordinator.activeTheme) == .orderedSame {
                loadedSkin.themeCoordinator.reapply()
            }
            return .null
        case "enumgammagroup":
            guard case .gammaSet(let name) = state.role,
                  let group = loadedSkin.themeCoordinator.catalog.groupIdentifier(
                    theme: name, index: Int(arguments[0].integerValue)) else { return .null }
            return dynamicValue(role: .gammaGroup(theme: name, group: group))
        case "setred", "setgreen", "setblue":
            guard case .gammaGroup(let theme, let group) = state.role else { return .null }
            loadedSkin.themeCoordinator.catalog.setGammaChannel(["setred": 0, "setgreen": 1, "setblue": 2][method] ?? 0,
                                                               to: Int(arguments[0].integerValue),
                                                               theme: theme, group: group)
            return .null
        // The map's own shape: every pixel at or above 1, the unreversed `loadFromMap` form.
        case "getregion":
            guard case .map(let bitmapID, let source) = state.role else { return .null }
            return dynamicValue(role: .region(clip: WasabiRegionClip(
                mapID: bitmapID, mapPath: mapLogicalPath(bitmapID: bitmapID, source: source),
                threshold: 1, reversed: false)))
        case "loadmap":
            noteCoverRequest(arguments[0].stringValue, by: program)
            state.role = .map(bitmapID: arguments[0].stringValue, source: program.source)
            dynamicObjects[id] = state
            return .null
        case "loadfrommap":
            // Argument 0 is the `Map` object itself, so the region borrows the bitmap that map
            // already resolved — including the path form, which has no `<bitmap>` definition and so
            // has to be handed to the renderer as an already-resolved logical path.
            guard case .object(let reference) = arguments[0],
                  case .dynamic(let mapID) = reference.kind,
                  let mapState = dynamicObjects[mapID],
                  case .map(let bitmapID, let source) = mapState.role else { return .null }
            state.role = .region(clip: WasabiRegionClip(mapID: bitmapID,
                                                        mapPath: mapLogicalPath(bitmapID: bitmapID, source: source),
                                                        threshold: Int(arguments[1].integerValue),
                                                        reversed: arguments[2].truthy))
            dynamicObjects[id] = state
            return .null
        case "loadfrombitmap":
            // A bitmap region is its artwork's silhouette: every pixel the image actually paints is
            // inside, every transparent one is outside. `regionMask` already drops a pixel whose
            // alpha is zero, so a threshold of 0 taken forward — which admits every value — is
            // exactly that rule and nothing more.
            let bitmapID = arguments[0].stringValue
            state.role = .region(clip: WasabiRegionClip(
                mapID: bitmapID, mapPath: mapLogicalPath(bitmapID: bitmapID, source: program.source),
                threshold: 0, reversed: false))
            dynamicObjects[id] = state
            return .null
        case "offset":
            guard case .region(let clip) = state.role else { return .null }
            state.role = .region(clip: WasabiRegionClip(mapID: clip.mapID, mapPath: clip.mapPath,
                                                        threshold: clip.threshold, reversed: clip.reversed,
                                                        offsetX: clip.offsetX + Int(arguments[0].integerValue),
                                                        offsetY: clip.offsetY + Int(arguments[1].integerValue)))
            dynamicObjects[id] = state
            return .null
        case "load":
            state.role = .xmlDocument(logicalPath: xmlDocumentPath(arguments[0].stringValue,
                                                                   program: program))
            state.parserCallbacks = []
            dynamicObjects[id] = state
            return .null
        case "exists":
            guard case .xmlDocument(let path) = state.role else { return .boolean(false) }
            return .boolean(path != nil)
        case "parser_addcallback":
            guard case .xmlDocument = state.role,
                  state.parserCallbacks.count < WinampModernXmlDocReader.maximumCallbacks else { return .null }
            state.parserCallbacks.append(arguments[0].stringValue)
            dynamicObjects[id] = state
            return .null
        case "parser_start":
            guard case .xmlDocument(let path) = state.role, let path else { return .null }
            parserStart(documentAt: path, callbacks: state.parserCallbacks, id: id, program: program)
            return .null
        case "parser_destroy":
            guard case .xmlDocument = state.role else { return .null }
            state.parserCallbacks = []
            dynamicObjects[id] = state
            return .null
        case "inregion", "getvalue":
            guard case .map(let bitmapID, let source) = state.role else {
                return method == "inregion" ? .boolean(false) : .integer(0)
            }
            let sample = mapPixel(bitmapID: bitmapID, source: source,
                                  x: Int(arguments[0].integerValue), y: Int(arguments[1].integerValue))
            if method == "inregion" {
                // A map with an alpha channel masks its region; MMD3's are opaque grayscale, where
                // being inside the bitmap *is* being in the region.
                return .boolean(sample.inBounds && sample.alpha > 0)
            }
            // `getValue(0,0) > 0` is how most cover scripts ask "did the file load?", and a cover
            // whose corner pixel is pure black would answer no. For a cover the question is only
            // ever that one, so a loaded cover reads at least 1.
            if sample.inBounds, host.isTrackFolderImage(bitmapID) {
                return .integer(Int32(max(1, sample.red)))
            }
            return .integer(Int32(sample.red))
        case "getargbvalue":
            // One channel of one pixel. The channel index is BGRA — pinned by `player.maki`, which
            // builds a `colorbandpeak="r,g,b"` attribute from channels 2, 1, 0 in that order.
            guard case .map(let bitmapID, let source) = state.role else { return .integer(0) }
            let sample = mapPixel(bitmapID: bitmapID, source: source,
                                  x: Int(arguments[0].integerValue), y: Int(arguments[1].integerValue))
            switch arguments[2].integerValue {
            case 0: return .integer(Int32(sample.blue))
            case 1: return .integer(Int32(sample.green))
            case 2: return .integer(Int32(sample.red))
            case 3: return .integer(Int32(sample.alpha))
            default: return .integer(0)
            }
        // `Color.getRed/getGreen/getBlue` — the channels `ColorMgr.getColor` resolved.
        //
        // The `…WithGamma` spellings answer the *same* numbers, and that is the correct reading
        // rather than a stub: Winamp's plain getters hand back the colour as the skin declared it and
        // the gamma ones hand it back after the active `<gammaset>` has been applied, while
        // `ColorMgr.getColor` here resolves through `WasabiSceneRenderer.resolvedColor`, which
        // already follows references *and* applies the gammagroup and the live colour theme. There is
        // no un-gamma'd form left to distinguish. ClassicPro's Web Reader is what needs them: every
        // provider URL carrying a `%COLOR:LBG%` token goes through `getColorHex()`, which reads all
        // three, so the miss aborted `surfSelected()` before its `navigateUrl` and the reader tab
        // never loaded a page (B128).
        case "getred", "getgreen", "getblue",
             "getredwithgamma", "getgreenwithgamma", "getbluewithgamma":
            if case .gammaGroup(let theme, let group) = state.role {
                let channel = method.hasPrefix("getred") ? 0 : method.hasPrefix("getgreen") ? 1 : 2
                return .integer(Int32(loadedSkin.themeCoordinator.catalog.gammaChannel(channel, theme: theme, group: group)))
            }
            guard case .color(let red, let green, let blue) = state.role else { return .integer(0) }
            switch method {
            case "getred", "getredwithgamma": return .integer(red)
            case "getgreen", "getgreenwithgamma": return .integer(green)
            default: return .integer(blue)
            }
        case "getwidth", "getheight":
            // The map's own size, which for a sliced `<bitmap>` is the slice's, not the sheet's —
            // same reason as `mapCrop`. The path form has no definition and stays the whole file,
            // which is what ClassicPro's two width probes (`read.suiframe.png`, `installed.png`) ask.
            guard case .map(let bitmapID, let source) = state.role else { return .integer(0) }
            // A map whose bitmap does not load is Wasabi's missing-bitmap placeholder, which is
            // 64x64 — the corpus's cover scripts test for exactly that (`getWidth() != 64`,
            // `getWidth()==64 && getHeight()==64` = "not found"). Skin Consortium's `SC:Cover` relies
            // on it the other way: it sizes its `<AlbumArt>` holders by `ArtW/ArtH` from a map of a
            // file name that is still empty, so 0x0 made the ratio 0/0 and the holders vanished,
            // where Winamp's 64/64 filled the frame. Its pixels still read 0 (`getValue`, above).
            guard let image = mapImage(bitmapID: bitmapID, source: source) else {
                return .integer(Self.missingMapSide)
            }
            let crop = mapCrop(bitmapID: bitmapID, image: image)
            return .integer(Int32(clamping: method == "getwidth" ? crop.width : crop.height))
        case "additem":
            guard state.items.count < Self.maximumListItems else { return .integer(-1) }
            state.items.append(arguments[0])
            dynamicObjects[id] = state
            return .integer(Int32(state.items.count - 1))
        case "enumitem":
            let index = Int(arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .null }
            return state.items[index]
        case "getnumitems", "getsize": return .integer(Int32(clamping: state.items.count))
        case "setsize":
            // `BitList` — same backing store as `List`, holding booleans. ClassicPro sizes one to the
            // widget count and ticks off the widgets it has already initialised.
            let size = max(0, min(Self.maximumListItems, Int(arguments[0].integerValue)))
            state.items = (0..<size).map { index in
                index < state.items.count ? state.items[index] : .boolean(false)
            }
            dynamicObjects[id] = state
            return .null
        case "getitem":
            let index = Int(arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .boolean(false) }
            return .boolean(state.items[index].truthy)
        case "setitem":
            let index = Int(arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .null }
            state.items[index] = .boolean(arguments[1].truthy)
            dynamicObjects[id] = state
            return .null
        case "removeitem":
            let index = Int(arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .null }
            state.items.remove(at: index)
            dynamicObjects[id] = state
            return .null
        case "removeall":
            state.items.removeAll()
            dynamicObjects[id] = state
            return .null
        case "finditem":
            // `Any` items: an object matches by identity, everything else by its string form, which is
            // how the engine searches its string lists.
            let index = state.items.firstIndex { item in
                if case .object(let reference) = arguments[0] { return object(item, equals: reference) }
                if case .object = item { return false }
                return item.stringValue == arguments[0].stringValue
            }
            return .integer(Int32(index ?? -1))
        case "getint", "getbool", "getstring":
            guard case .configGroup(let section) = state.role else {
                return method == "getstring" ? .string("") : .integer(0)
            }
            let key = arguments[0].stringValue
            // An unset item reads 0. That is also the right answer for the one item ClassicPro asks
            // about — `"frequencies"`, where 0 means Winamp's classic EQ frequencies, which is what
            // NullPlayer's `EQConfiguration.classic10` uses.
            let value = loadedSkin.configuration.integer(section: section, key: key, default: 0)
            switch method {
            case "getbool": return .boolean(value != 0)
            case "getstring": return .string(loadedSkin.configuration.string(section: section, key: key))
            default: return .integer(value)
            }
        // Wasabi's `STimer::setDelay` re-arms a started timer at the new delay, and skins rely on it
        // from inside their own `onTimer`: Shield_Amp's `OneDirectionText` starts its ticker on a
        // 1000 ms first delay, then drops to the 60 ms step on the first tick. Storing the value
        // without re-arming left the ticker stepping once a second (B148).
        case "setdelay":
            state.delayMilliseconds = arguments[0].integerValue
            dynamicObjects[id] = state
            if timers.contains(id: id) { try scheduleTimer(id: id, delayMilliseconds: state.delayMilliseconds) }
            return .null
        // The delay as set, unclamped — the same script compares it against its own first delay.
        case "getdelay": return .integer(state.delayMilliseconds)
        // Ticks the timer service dropped because the main thread was late. It coalesces rather
        // than counting, so none are reported.
        case "getskipped": return .integer(0)
        case "sendcommand":
            guard case .wac = state.role else { return .null }
            return .integer(0)
        case "start":
            if MakiInterpreter.tracesExecution {
                print("MAKI timer start id=\(id) delay=\(state.delayMilliseconds) "
                      + "by=\(MakiInterpreter.traceStack.last ?? "-")")
            }
            try scheduleTimer(id: id, delayMilliseconds: state.delayMilliseconds)
            return .boolean(true)
        case "stop":
            if MakiInterpreter.tracesExecution {
                print("MAKI timer stop id=\(id) running=\(timers.contains(id: id)) "
                      + "by=\(MakiInterpreter.traceStack.last ?? "-")")
            }
            timers.cancel(id: id)
            return .null
        case "isrunning": return .boolean(timers.contains(id: id))
        case "newattribute", "getattribute":
            guard case .configItem(let section) = state.role else { return .null }
            let key = arguments[0].stringValue
            if method == "newattribute" {
                let defaultValue = arguments[1].stringValue
                let existing = loadedSkin.configuration.string(section: section, key: key,
                                                                 default: defaultValue)
                loadedSkin.configuration.setString(existing, section: section, key: key)
                recordRegisteredSetting(section: section, name: key, defaultValue: defaultValue)
            }
            return dynamicValue(role: .configAttribute(section: section, key: key))
        // Skin-options code finds the toggle it owns by the attribute's name (B185).
        case "getattributename":
            guard case .configAttribute(_, let key) = state.role else { return .string("") }
            return .string(key)
        case "getdata":
            guard case .configAttribute(let section, let key) = state.role else { return .string("") }
            let data = loadedSkin.configuration.string(
                section: section, key: key,
                default: WinampModernConfigBridge.hostDefault(section: section, key: key) ?? "")
            if Self.tracesEveryCall {
                print("CALL-TRACE getdata[\(section);\(key)] -> \(data)")
            }
            return .string(data)
        case "setdata":
            guard case .configAttribute(let section, let key) = state.role else { return .null }
            // Through the shared write route, not this object alone. A skin's configurator writes an
            // attribute from one script and every *other* script that registered the same attribute
            // applies it from its own `onDataChanged` — Defix changes its background that way, one
            // `setData` in the configurator against a `STANDARDFRAME` script per window. Dispatching
            // only to the caller left the write visible in exactly the window that made it.
            setConfigAttribute(section: section, key: key, value: arguments[0].stringValue)
            return .null
        // A script-owned string object: `setText` stores, `getText` reads back **with Wasabi's path
        // variables expanded**, which is the whole reason a skin makes one. Big Bento Modern's Web
        // Reader builds the path behind its `%CUSTOMSOURCE%` token that way —
        // `s.setText("@SKINSPATH@"); s.getText() + "/Big Bento Modern/scripts/reader/source/"` — and
        // a string with no `@…@` in it is handed back untouched, because canonicalising ordinary text
        // as a path would turn it into one.
        case "settext":
            state.text = arguments[0].stringValue
            dynamicObjects[id] = state
            return .null
        case "gettext":
            guard state.text.contains("@") else { return .string(state.text) }
            let expanded = try? loadedSkin.vfs.resolve(state.text, relativeTo: program.source.path,
                                                       location: program.source, mustExist: false)
            return .string(expanded?.logicalPath ?? state.text)
        case "getid":
            switch state.role {
            case .configItem(let section): return .string(section)
            case .configAttribute(_, let key): return .string(key)
            case .map(let bitmapID, _): return .string(bitmapID)
            case .region(let clip): return .string(clip.mapID)
            case .xmlDocument(let path): return .string(path ?? "")
            case .configGroup(let section): return .string(section)
            case .gammaSet(let name): return .string(name)
            case .color(let red, let green, let blue): return .string("\(red),\(green),\(blue)")
            case .wac(let guid): return .string(guid)
            case .gammaGroup(_, let group): return .string(group)
            case .generic, .pendingGUI: return .string("dynamic_\(id)")
            }
        // A GUI object the script made with `new`: it enters the graph beneath its parent here, and
        // from then on the reference answers as that object (`dynamicGUIObjects`).
        case "init":
            guard case .pendingGUI(let type, let attributes, let calls) = state.role,
                  case .object(let reference) = arguments.first,
                  case .gui(let parentID) = reference.kind,
                  let parent = loadedSkin.runtime.graph.object(withID: parentID),
                  let created = try loadedSkin.runtime.instantiateElement?(type, attributes, parent)
            else { return .null }
            dynamicGUIObjects[id] = created.stableID
            dynamicObjects[id]?.role = .generic
            for call in calls {
                _ = try invokeGUI(method: call.method, object: created, arguments: call.arguments, program: program)
            }
            noteGeometryChange()
            notifyGraphDidMutate()
            return .null
        case "callme": return .null
        default:
            if let value = classicProFileMethod(method, arguments: arguments) { return value }
            throw unsupported(method, program: program)
        }
    }
}
