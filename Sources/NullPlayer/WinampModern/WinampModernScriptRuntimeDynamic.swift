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
        guard let state = dynamicObjects[id] else { return .null }
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
        if let value = try answer(Self.treeItemMethods,
                                  MakiCall(method: method, receiver: id, arguments: arguments, program: program)) {
            return value
        }
        let call = MakiCall(method: method, receiver: MakiDynamicReceiver(id: id, state: state),
                            arguments: arguments, program: program)
        if case .pendingGUI(let type, let attributes, var calls) = state.role {
            if let value = try answer(Self.pendingGUIMethods, call) { return value }
            // Anything else with an arity waits for `init`, which replays it on the object it creates.
            if method != "init", signature(for: method, classGUID: nil) != nil,
               calls.count < Self.maximumPendingCalls {
                calls.append((method, arguments))
                dynamicObjects[id]?.role = .pendingGUI(type: type, attributes: attributes, calls: calls)
                return .null
            }
        }
        if let value = try answer(Self.dynamicMethods, call)
            ?? answer(Self.classicProFileMethods, MakiCall(method: method, receiver: (), arguments: arguments,
                                                           program: program)) {
            return value
        }
        throw unsupported(method, program: program)
    }

    /// A GUI object a script made with `new` and has not `init`'d yet. It is not in the graph, so its
    /// markup is kept on the role until `init` puts it there.
    static let pendingGUIMethods: MakiMethodTable<MakiDynamicReceiver> = {
        var table = MakiMethodTable<MakiDynamicReceiver>()
        table.add("setxmlparam", 2) { runtime, call in
            guard case .pendingGUI(let type, var attributes, let calls) = call.state.role else { return nil }
            attributes[call.arguments[0].stringValue.lowercased()] = call.arguments[1].stringValue
            runtime.dynamicObjects[call.id]?.role = .pendingGUI(type: type, attributes: attributes, calls: calls)
            return .null
        }
        table.add("getxmlparam", 1) { runtime, call in
            guard case .pendingGUI(_, let attributes, _) = call.state.role else { return nil }
            return .string(attributes[call.arguments[0].stringValue.lowercased()] ?? "")
        }
        return table
    }()

    /// The objects a script makes with `new`, each answering by the role its first call settled.
    static let dynamicMethods: MakiMethodTable<MakiDynamicReceiver> = {
        var table = MakiMethodTable<MakiDynamicReceiver>()
        // `GammaSet.apply()` — switch to the theme this object names, through the one route
        // `System.setColorTheme` already uses. A theme the skin does not ship is refused by the
        // catalog and the call is simply inert.
        table.add("apply", 0, on: MakiClassGUID.gammaSet) { runtime, call in
            guard case .gammaSet(let name) = call.state.role else { return .null }
            // Re-applying the theme already showing is how a script shows the groups it retinted.
            if runtime.hooks.themeSwitchRequested?(name) != true,
               name.caseInsensitiveCompare(runtime.loadedSkin.themeCoordinator.activeTheme) == .orderedSame {
                runtime.loadedSkin.themeCoordinator.reapply()
            }
            return .null
        }
        table.add("enumgammagroup", 1) { runtime, call in
            guard case .gammaSet(let name) = call.state.role,
                  let group = runtime.loadedSkin.themeCoordinator.catalog.groupIdentifier(
                    theme: name, index: Int(call.arguments[0].integerValue)) else { return .null }
            return runtime.dynamicValue(role: .gammaGroup(theme: name, group: group))
        }
        table.add(["setred", "setgreen", "setblue"], 1) { runtime, call in
            guard case .gammaGroup(let theme, let group) = call.state.role else { return .null }
            runtime.loadedSkin.themeCoordinator.catalog.setGammaChannel(["setred": 0, "setgreen": 1,
                                                                         "setblue": 2][call.method] ?? 0,
                                                               to: Int(call.arguments[0].integerValue),
                                                               theme: theme, group: group)
            return .null
        }
        // The map's own shape: every pixel at or above 1, the unreversed `loadFromMap` form.
        table.add("getregion", 0) { runtime, call in
            guard case .map(let bitmapID, let source) = call.state.role else { return .null }
            return runtime.dynamicValue(role: .region(clip: WasabiRegionClip(
                mapID: bitmapID, mapPath: runtime.mapLogicalPath(bitmapID: bitmapID, source: source),
                threshold: 1, reversed: false)))
        }
        // `Map`: a bitmap sampled by the script (the knob-angle lookup MMD3 drives its rotary
        // controls with). `new Map` yields a generic dynamic object; `loadMap` gives it its role.
        table.add("loadmap", 1) { runtime, call in
            var state = call.state
            runtime.noteCoverRequest(call.arguments[0].stringValue, by: call.program)
            state.role = .map(bitmapID: call.arguments[0].stringValue, source: call.program.source)
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        // `Region`: `loadFromMap(Map, Int threshold, Boolean reversed)` turns a map into a
        // shape, `offset` moves it into the clipped object's own space, and `setRegion` clips
        // the object to it. T800 fills its volume bar this way; the stock `customseek.m` its
        // seek ghost.
        table.add("loadfrommap", 3) { runtime, call in
            var state = call.state
            // Argument 0 is the `Map` object itself, so the region borrows the bitmap that map
            // already resolved — including the path form, which has no `<bitmap>` definition and so
            // has to be handed to the renderer as an already-resolved logical path.
            guard case .object(let reference) = call.arguments[0],
                  case .dynamic(let mapID) = reference.kind,
                  let mapState = runtime.dynamicObjects[mapID],
                  case .map(let bitmapID, let source) = mapState.role else { return .null }
            state.role = .region(clip: WasabiRegionClip(mapID: bitmapID,
                                                        mapPath: runtime.mapLogicalPath(bitmapID: bitmapID,
                                                                                        source: source),
                                                        threshold: Int(call.arguments[1].integerValue),
                                                        reversed: call.arguments[2].truthy))
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        // `loadFromBitmap(String bitmapid)` is the same region without the `Map` in front of it:
        // the shape is the bitmap's own opaque area. MMD3's `std.mi` declares the pair together
        // (`extern Region.loadFromMap(…); extern Region.loadFromBitmap(String bitmapid);`) and
        // three more skins call it — BLAKK's `boombox.m` clips its seek bar with
        // `seekregion.loadfrombitmap("player.bb-seek-region"); seek1.setregion(seekregion);`.
        table.add("loadfrombitmap", 1) { runtime, call in
            var state = call.state
            // A bitmap region is its artwork's silhouette: every pixel the image actually paints is
            // inside, every transparent one is outside. `regionMask` already drops a pixel whose
            // alpha is zero, so a threshold of 0 taken forward — which admits every value — is
            // exactly that rule and nothing more.
            let bitmapID = call.arguments[0].stringValue
            state.role = .region(clip: WasabiRegionClip(
                mapID: bitmapID, mapPath: runtime.mapLogicalPath(bitmapID: bitmapID, source: call.program.source),
                threshold: 0, reversed: false))
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("offset", 2) { runtime, call in
            var state = call.state
            guard case .region(let clip) = state.role else { return .null }
            state.role = .region(clip: WasabiRegionClip(mapID: clip.mapID, mapPath: clip.mapPath,
                                                        threshold: clip.threshold, reversed: clip.reversed,
                                                        offsetX: clip.offsetX + Int(call.arguments[0].integerValue),
                                                        offsetY: clip.offsetY + Int(call.arguments[1].integerValue)))
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        // ClassicPro `ClassicProFile` shell service (the entire native surface, P0B §1).
        // `XmlDoc`: load an optional config document. Bounded — see `DynamicRole.xmlDocument`.
        table.add("load", 1) { runtime, call in
            var state = call.state
            state.role = .xmlDocument(logicalPath: runtime.xmlDocumentPath(call.arguments[0].stringValue,
                                                                           program: call.program))
            state.parserCallbacks = []
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("exists", 0) { runtime, call in
            guard case .xmlDocument(let path) = call.state.role else { return .boolean(false) }
            return .boolean(path != nil)
        }
        // `XmlDoc`'s callback parser. The document is walked once by `parser_start()`, which
        // dispatches `parser_onCallback` back at the same object for every element matching a
        // path registered with `parser_addCallback`. Big Bento Modern's Web Reader is the whole
        // measured demand: its provider drop-down is built entirely from those callbacks, so
        // without them `exists()` answered false, the skin took its "Oops! Something went wrong!"
        // branch on every `onSetVisible`, and the list came up empty.
        table.add("parser_addcallback", 1) { runtime, call in
            var state = call.state
            guard case .xmlDocument = state.role,
                  state.parserCallbacks.count < WinampModernXmlDocReader.maximumCallbacks else { return .null }
            state.parserCallbacks.append(call.arguments[0].stringValue)
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("parser_start", 0) { runtime, call in
            guard case .xmlDocument(let path) = call.state.role, let path else { return .null }
            runtime.parserStart(documentAt: path, callbacks: call.state.parserCallbacks, id: call.id,
                                program: call.program)
            return .null
        }
        table.add("parser_destroy", 0) { runtime, call in
            var state = call.state
            guard case .xmlDocument = state.role else { return .null }
            state.parserCallbacks = []
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("inregion", 2) { runtime, call in
            guard case .map(let bitmapID, let source) = call.state.role else { return .boolean(false) }
            let sample = runtime.mapPixel(bitmapID: bitmapID, source: source,
                                          x: Int(call.arguments[0].integerValue), y: Int(call.arguments[1].integerValue))
            // A map with an alpha channel masks its region; MMD3's are opaque grayscale, where
            // being inside the bitmap *is* being in the region.
            return .boolean(sample.inBounds && sample.alpha > 0)
        }
        table.add("getvalue", 2) { runtime, call in
            guard case .map(let bitmapID, let source) = call.state.role else { return .integer(0) }
            let sample = runtime.mapPixel(bitmapID: bitmapID, source: source,
                                          x: Int(call.arguments[0].integerValue), y: Int(call.arguments[1].integerValue))
            // `getValue(0,0) > 0` is how most cover scripts ask "did the file load?", and a cover
            // whose corner pixel is pure black would answer no. For a cover the question is only
            // ever that one, so a loaded cover reads at least 1.
            if sample.inBounds, runtime.host.isTrackFolderImage(bitmapID) {
                return .integer(Int32(max(1, sample.red)))
            }
            return .integer(Int32(sample.red))
        }
        // A `Map` is also queried for its own size and for whole pixels: ClassicPro reads its
        // colour scheme out of a bitmap (`player.maki` builds the classic-vis colour bands from
        // `getARGBValue`) and sizes animations from `getWidth`/`getHeight`.
        table.add("getargbvalue", 3) { runtime, call in
            // One channel of one pixel. The channel index is BGRA — pinned by `player.maki`, which
            // builds a `colorbandpeak="r,g,b"` attribute from channels 2, 1, 0 in that order.
            guard case .map(let bitmapID, let source) = call.state.role else { return .integer(0) }
            let sample = runtime.mapPixel(bitmapID: bitmapID, source: source,
                                          x: Int(call.arguments[0].integerValue), y: Int(call.arguments[1].integerValue))
            switch call.arguments[2].integerValue {
            case 0: return .integer(Int32(sample.blue))
            case 1: return .integer(Int32(sample.green))
            case 2: return .integer(Int32(sample.red))
            case 3: return .integer(Int32(sample.alpha))
            default: return .integer(0)
            }
        }
        // `Color`'s channels. Global rather than class-gated: all three are zero-argument getters,
        // so even a collision with another class's same-named verb cannot desynchronise the stack
        // the way a wrong *count* would.
        // `Color.getRed/getGreen/getBlue` — the channels `ColorMgr.getColor` resolved — and on a
        // `GammaGroup`, its theme's channel.
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
        for (channel, colour) in ["red", "green", "blue"].enumerated() {
            table.add(["get" + colour, "get" + colour + "withgamma"], 0) { runtime, call in
                switch call.state.role {
                case .gammaGroup(let theme, let group):
                    return .integer(Int32(runtime.loadedSkin.themeCoordinator.catalog.gammaChannel(channel,
                                                                                                   theme: theme,
                                                                                                    group: group)))
                case .color(let red, let green, let blue): return .integer([red, green, blue][channel])
                default: return .integer(0)
                }
            }
        }
        table.add(["getwidth", "getheight"], 0) { runtime, call in
            // The map's own size, which for a sliced `<bitmap>` is the slice's, not the sheet's —
            // same reason as `mapCrop`. The path form has no definition and stays the whole file,
            // which is what ClassicPro's two width probes (`read.suiframe.png`, `installed.png`) ask.
            guard case .map(let bitmapID, let source) = call.state.role else { return .integer(0) }
            // A map whose bitmap does not load is Wasabi's missing-bitmap placeholder, which is
            // 64x64 — the corpus's cover scripts test for exactly that (`getWidth() != 64`,
            // `getWidth()==64 && getHeight()==64` = "not found"). Skin Consortium's `SC:Cover` relies
            // on it the other way: it sizes its `<AlbumArt>` holders by `ArtW/ArtH` from a map of a
            // file name that is still empty, so 0x0 made the ratio 0/0 and the holders vanished,
            // where Winamp's 64/64 filled the frame. Its pixels still read 0 (`getValue`, above).
            guard let image = runtime.mapImage(bitmapID: bitmapID, source: source) else {
                return .integer(WinampModernScriptRuntime.missingMapSide)
            }
            let crop = runtime.mapCrop(bitmapID: bitmapID, image: image)
            return .integer(Int32(clamping: call.method == "getwidth" ? crop.width : crop.height))
        }
        // `List`: MAKI's own container (`extern List.addItem(Any)` …). ClassicPro builds its tab
        // order, its widget registry and its beat-vis names in one, so a missing `addItem` aborts
        // the script that assembles the SUI's tab strip.
        table.add("additem", 1) { runtime, call in
            var state = call.state
            guard state.items.count < WinampModernScriptRuntime.maximumListItems else { return .integer(-1) }
            state.items.append(call.arguments[0])
            runtime.dynamicObjects[call.id] = state
            return .integer(Int32(state.items.count - 1))
        }
        table.add("enumitem", 1) { runtime, call in
            let index = Int(call.arguments[0].integerValue)
            guard call.state.items.indices.contains(index) else { return .null }
            return call.state.items[index]
        }
        table.add(["getnumitems", "getsize"], 0) { runtime, call in
            .integer(Int32(clamping: call.state.items.count))
        }
        // `BitList` — a sized array of flags, sharing the `List` backing store.
        table.add("setsize", 1) { runtime, call in
            var state = call.state
            // `BitList` — same backing store as `List`, holding booleans. ClassicPro sizes one to the
            // widget count and ticks off the widgets it has already initialised.
            let size = max(0, min(WinampModernScriptRuntime.maximumListItems, Int(call.arguments[0].integerValue)))
            state.items = (0..<size).map { index in
                index < state.items.count ? state.items[index] : .boolean(false)
            }
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("getitem", 1) { runtime, call in
            let index = Int(call.arguments[0].integerValue)
            guard call.state.items.indices.contains(index) else { return .boolean(false) }
            return .boolean(call.state.items[index].truthy)
        }
        table.add("setitem", 2) { runtime, call in
            var state = call.state
            let index = Int(call.arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .null }
            state.items[index] = .boolean(call.arguments[1].truthy)
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("removeitem", 1) { runtime, call in
            var state = call.state
            let index = Int(call.arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .null }
            state.items.remove(at: index)
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("removeall", 0) { runtime, call in
            var state = call.state
            state.items.removeAll()
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("finditem", 1) { runtime, call in
            // `Any` items: an object matches by identity, everything else by its string form, which is
            // how the engine searches its string lists.
            let index = call.state.items.firstIndex { item in
                if case .object(let reference) = call.arguments[0] { return runtime.object(item, equals: reference) }
                if case .object = item { return false }
                return item.stringValue == call.arguments[0].stringValue
            }
            return .integer(Int32(index ?? -1))
        }
        // An unset item reads 0. That is also the right answer for the one item ClassicPro asks about —
        // `"frequencies"`, where 0 means Winamp's classic EQ frequencies, which is what NullPlayer's
        // `EQConfiguration.classic10` uses.
        table.add("getint", 1) { runtime, call in
            guard case .configGroup(let section) = call.state.role else { return .integer(0) }
            return .integer(runtime.loadedSkin.configuration.integer(section: section,
                                                                     key: call.arguments[0].stringValue,
                                                                     default: 0))
        }
        table.add("getbool", 1) { runtime, call in
            guard case .configGroup(let section) = call.state.role else { return .integer(0) }
            return .boolean(runtime.loadedSkin.configuration.integer(section: section,
                                                                     key: call.arguments[0].stringValue,
                                                                     default: 0) != 0)
        }
        table.add("getstring", 1) { runtime, call in
            guard case .configGroup(let section) = call.state.role else { return .string("") }
            return .string(runtime.loadedSkin.configuration.string(section: section,
                                                                   key: call.arguments[0].stringValue))
        }
        // Wasabi's `STimer::setDelay` re-arms a started timer at the new delay, and skins rely on it
        // from inside their own `onTimer`: Shield_Amp's `OneDirectionText` starts its ticker on a
        // 1000 ms first delay, then drops to the 60 ms step on the first tick. Storing the value
        // without re-arming left the ticker stepping once a second (B148).
        table.add("setdelay", 1) { runtime, call in
            var state = call.state
            state.delayMilliseconds = call.arguments[0].integerValue
            runtime.dynamicObjects[call.id] = state
            if runtime.timers.contains(id: call.id) {
                try runtime.scheduleTimer(id: call.id, delayMilliseconds: state.delayMilliseconds)
            }
            return .null
        }
        // The delay as set, unclamped — the same script compares it against its own first delay.
        table.add("getdelay", 0) { runtime, call in .integer(call.state.delayMilliseconds) }
        // Ticks the timer service dropped because the main thread was late. It coalesces rather
        // than counting, so none are reported.
        table.add("getskipped", 0) { runtime, call in .integer(0) }
        table.add("sendcommand", 4) { runtime, call in
            guard case .wac = call.state.role else { return .null }
            return .integer(0)
        }
        table.add("start", 0) { runtime, call in
            if MakiInterpreter.tracesExecution {
                print("MAKI timer start id=\(call.id) delay=\(call.state.delayMilliseconds) "
                      + "by=\(MakiInterpreter.traceStack.last ?? "-")")
            }
            try runtime.scheduleTimer(id: call.id, delayMilliseconds: call.state.delayMilliseconds)
            return .boolean(true)
        }
        table.add("stop", 0) { runtime, call in
            if MakiInterpreter.tracesExecution {
                print("MAKI timer stop id=\(call.id) running=\(runtime.timers.contains(id: call.id)) "
                      + "by=\(MakiInterpreter.traceStack.last ?? "-")")
            }
            runtime.timers.cancel(id: call.id)
            return .null
        }
        table.add("isrunning", 0) { runtime, call in .boolean(runtime.timers.contains(id: call.id)) }
        let newattributeBody: MakiMethodDefinition<MakiDynamicReceiver>.Body = { runtime, call in
            guard case .configItem(let section) = call.state.role else { return .null }
            let key = call.arguments[0].stringValue
            if call.method == "newattribute" {
                let defaultValue = call.arguments[1].stringValue
                let existing = runtime.loadedSkin.configuration.string(section: section, key: key,
                                                                       default: defaultValue)
                runtime.loadedSkin.configuration.setString(existing, section: section, key: key)
                runtime.recordRegisteredSetting(section: section, name: key, defaultValue: defaultValue)
            }
            return runtime.dynamicValue(role: .configAttribute(section: section, key: key))
        }
        table.add("newattribute", 2, newattributeBody)
        table.add("getattribute", 1, newattributeBody)
        // Skin-options code finds the toggle it owns by the attribute's name (B185).
        table.add("getattributename", 0) { runtime, call in
            guard case .configAttribute(_, let key) = call.state.role else { return .string("") }
            return .string(key)
        }
        table.add("getdata", 0) { runtime, call in
            guard case .configAttribute(let section, let key) = call.state.role else { return .string("") }
            let data = runtime.loadedSkin.configuration.string(
                section: section, key: key,
                default: WinampModernConfigBridge.hostDefault(section: section, key: key) ?? "")
            if WinampModernScriptRuntime.tracesEveryCall {
                print("CALL-TRACE getdata[\(section);\(key)] -> \(data)")
            }
            return .string(data)
        }
        table.add("setdata", 1) { runtime, call in
            guard case .configAttribute(let section, let key) = call.state.role else { return .null }
            // Through the shared write route, not this object alone. A skin's configurator writes an
            // attribute from one script and every *other* script that registered the same attribute
            // applies it from its own `onDataChanged` — Defix changes its background that way, one
            // `setData` in the configurator against a `STANDARDFRAME` script per window. Dispatching
            // only to the caller left the write visible in exactly the window that made it.
            runtime.setConfigAttribute(section: section, key: key, value: call.arguments[0].stringValue)
            return .null
        }
        // A script-owned string object: `setText` stores, `getText` reads back **with Wasabi's path
        // variables expanded**, which is the whole reason a skin makes one. Big Bento Modern's Web
        // Reader builds the path behind its `%CUSTOMSOURCE%` token that way —
        // `s.setText("@SKINSPATH@"); s.getText() + "/Big Bento Modern/scripts/reader/source/"` — and
        // a string with no `@…@` in it is handed back untouched, because canonicalising ordinary text
        // as a path would turn it into one.
        table.add("settext", 1) { runtime, call in
            var state = call.state
            state.text = call.arguments[0].stringValue
            runtime.dynamicObjects[call.id] = state
            return .null
        }
        table.add("gettext", 0) { runtime, call in
            guard call.state.text.contains("@") else { return .string(call.state.text) }
            let expanded = try? runtime.loadedSkin.vfs.resolve(call.state.text, relativeTo: call.program.source.path,
                                                               location: call.program.source, mustExist: false)
            return .string(expanded?.logicalPath ?? call.state.text)
        }
        table.add("getid", 0) { runtime, call in
            switch call.state.role {
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
            case .generic, .pendingGUI: return .string("dynamic_\(call.id)")
            }
        }
        // A GUI object the script made with `new`: it enters the graph beneath its parent here, and
        // from then on the reference answers as that object (`dynamicGUIObjects`).
        table.add("init", 1) { runtime, call in
            guard case .pendingGUI(let type, let attributes, let calls) = call.state.role,
                  case .object(let reference) = call.arguments.first,
                  case .gui(let parentID) = reference.kind,
                  let parent = runtime.loadedSkin.runtime.graph.object(withID: parentID),
                  let created = try runtime.loadedSkin.runtime.instantiateElement?(type, attributes, parent)
            else { return .null }
            runtime.dynamicGUIObjects[call.id] = created.stableID
            runtime.dynamicObjects[call.id]?.role = .generic
            for pending in calls {
                _ = try runtime.invokeGUI(method: pending.method, object: created, arguments: pending.arguments,
                                          program: call.program)
            }
            runtime.noteGeometryChange()
            runtime.notifyGraphDidMutate()
            return .null
        }
        table.add("callme", 1) { runtime, call in .null }
        return table
    }()
}
