import AppKit
import CoreGraphics
import Foundation

/// The rest of the MAKI `GuiObject` receiver, by object family; `invokeGUI` in
/// `WinampModernScriptRuntimeObject.swift` dispatches to each in turn (B259).
extension WinampModernScriptRuntime {
    /// Sliders, splitters and `cfgattrib` controls: the position a script reads and sets.
    func invokeGUIPosition(method: String, object: WasabiObject, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue? {
        switch method {
        case "getposition" where WasabiFrame.isFrame(object.tag):
            // A splitter's position is its divider offset, not a slider value. ClassicPro reads it to
            // decide whether the side view is open (`mainFrame.getPosition()==0`).
            return .integer(Int32(clamping: Int(WasabiFrame.position(of: object))))
        case "setposition" where WasabiFrame.isFrame(object.tag):
            guard WasabiFrame.setPosition(Double(arguments[0].integerValue), on: object) else { return .null }
            noteGeometryChange()
            notifyGraphDidMutate()
            _ = try dispatch(object: object, event: "onsetposition", arguments: [arguments[0]])
            return .null
        // Same rule as `getactivated`: for a bound control the setting *is* the position, and the
        // `value` attribute is not a second copy of it. mmd3 seeds its crossfade readout with
        // `slidercb.onSetPosition(slidercb.getPosition())` at load, which read 0 whatever the
        // stored duration was.
        case "getposition":
            let readFrom = embeddedControl(of: object) ?? object
            // **A host-bound slider stands where the host stands, not where its last drag left a
            // copy.** The renderer already draws the thumb from `host.volume` / the playback clock /
            // the balance / the EQ snapshot (`normalizedValue(of:)`); the script side read the
            // `value` attribute, which nothing writes until the *user drags this very slider*. So a
            // skin that sizes its own artwork from the position it reads back got 0 at load and
            // after every volume change made anywhere else: ClassicPro's `sc_sliderbar` runs both
            // cPro2's volume fill and its hover glow off `max*mySlider.getPosition()/255`, and with
            // 0 for the position both layers were sized to zero width — the bar never filled and
            // hovering it lit nothing (B129).
            if let normalized = hostBoundValue(of: readFrom) {
                return .integer(Self.sliderPosition(normalized: normalized, of: readFrom))
            }
            if let value = configInteger(of: readFrom) { return .integer(value) }
            return .integer(Int32(readFrom.attributes["value"] ?? readFrom.attributes["position"] ?? "0") ?? 0)
        case "setposition" where Self.configBinding(of: object) != nil:
            if let binding = Self.configBinding(of: object) {
                setConfigAttribute(section: binding.section, key: binding.key,
                                   value: String(arguments[0].integerValue))
            }
            _ = try dispatch(object: object, event: "onsetposition", arguments: [arguments[0]])
            return .null
        case "setposition":
            // Only an actual change notifies, as in Wasabi. Skins pair sliders that write each
            // other's position from their own `onSetPosition`; notifying unconditionally turns that
            // into an endless round trip.
            // Clamped to the range the slider declares, as Wasabi does. A skin that steps a slider
            // relative to itself — `slider.setPosition(slider.getPosition() + 5)`, which is how every
            // scrollbar's up/down button in the corpus works — otherwise walks straight off the end
            // and never comes back, and whatever reads the position is handed a number outside the
            // unit it was cut for. Only a declared range clamps: an object that states neither `low`
            // nor `high` is left exactly as it was.
            let target = embeddedControl(of: object) ?? object
            let clamped = Self.clampedSliderPosition(arguments[0].integerValue, of: target)
            let position = String(clamped)
            // A host-bound slider stands where the host stands (see `getposition`), so that is what a
            // write is compared against — and the write moves the host, as a drag does. Not a seek
            // bar: Winamp seeks on the *release*, so a script that keeps its thumb in step with the
            // clock (shark5's `seekslide`, from a timer) must not seek on every tick.
            let hostReading = target.attributes["action"]?.lowercased() == "seek"
                ? nil : hostBoundValue(of: target)
            let current = hostReading.map { String(Self.sliderPosition(normalized: $0, of: target)) }
                ?? target.attributes["value"]
            guard current != position else { return .null }
            _ = target.setAttribute("value", value: position)
            if hostReading != nil {
                driveHost(from: target, normalized: Self.normalizedSliderPosition(clamped, of: target))
            }
            notifyObjectDidMutate(target)
            // Dispatched at the control that actually moved; `embeddedXUIForwardedEvents` carries it
            // back up to the wrapper, so a script bound to either one hears it exactly once.
            _ = try dispatch(object: target, event: "onsetposition",
                             arguments: [.integer(Int32(position) ?? arguments[0].integerValue)])
            return .null
        default: return nil
        }
    }

    /// Animated layers: the play head, its range and its speed.
    func invokeGUIAnimation(method: String, object: WasabiObject, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue? {
        switch method {
        case "setmode":
            _ = object.setAttribute("mode", value: arguments[0].stringValue)
            notifyObjectDidMutate(object)
            return .null
        case "play":
            // Stamp the clock so the frame is a pure function of elapsed time (`WasabiAnimation`),
            // which keeps the renderer and `isPlaying()` on exactly the same model.
            _ = object.setAttribute("animstart", value: String(WasabiAnimation.now()))
            _ = object.setAttribute("playing", value: "1")
            notifyObjectDidMutate(object)
            startFrameEvents(for: object)
            return .null
        case "pause", "stop":
            // Freeze where the animation actually is, not where it started.
            _ = object.setAttribute("frame", value: String(animationFrame(of: object)))
            _ = object.setAttribute("playing", value: "0")
            notifyObjectDidMutate(object)
            if method == "stop" { stopFrameEvents(for: object) }
            return .null
        case "gotoframe", "setframe":
            let moved = object.setAttribute("frame", value: String(max(0, arguments[0].integerValue)))
            // Stopping a self-playing layer changes the animation clock's set, which only the full
            // notification re-reads. A step of an already-stopped layer is a cell swap — `frame` is
            // scene-neutral — so it repaints the layer's own rect: a beat meter stepping 12 layers
            // every 10 ms made each step a whole-window relayout and repaint (B152).
            if object.setAttribute("playing", value: "0") { notifyObjectDidMutate(object) }
            else if moved { requestRepaint(for: object) }
            return .null
        case "getcurframe": return .integer(Int32(animationFrame(of: object)))
        case "getlength":
            noteCoverRequest(object.attributes["image"] ?? "", by: program)
            return .integer(Int32(clamping: animationFrameCount(of: object)))
        case "setstartframe":
            _ = object.setAttribute("startframe", value: String(max(0, arguments[0].integerValue)))
            return .null
        case "setendframe":
            _ = object.setAttribute("endframe", value: String(max(0, arguments[0].integerValue)))
            return .null
        case "getstartframe":
            // Unset means "the whole sheet", exactly as `WasabiAnimation` reads it.
            let count = animationFrameCount(of: object)
            let raw = Int(object.attributes["startframe"] ?? "") ?? 0
            return .integer(Int32(max(0, min(count - 1, raw))))
        case "getendframe":
            let count = animationFrameCount(of: object)
            let raw = Int(object.attributes["endframe"] ?? "") ?? (count - 1)
            return .integer(Int32(max(0, min(count - 1, raw))))
        case "setspeed":
            _ = object.setAttribute("speed", value: String(max(1, arguments[0].integerValue)))
            return .null
        case "setautoreplay":
            // Written to the same attribute the markup carries, so `WasabiAnimation` reads one value
            // whether the skin declared it or a script set it. It only decides what a layer does with
            // *no* explicit `playing`, which is why a range play started right after is unaffected.
            _ = object.setAttribute("autoreplay", value: arguments[0].integerValue != 0 ? "1" : "0")
            return .null
        case "isplaying":
            return .boolean(WasabiAnimation.state(of: object,
                                                  frameCount: animationFrameCount(of: object)).isPlaying)
        // Wasabi has no third state for a layer, so this is exactly `!isPlaying` and is written from
        // the same reading rather than a second one that could drift from it.
        case "isstopped":
            return .boolean(!WasabiAnimation.state(of: object,
                                                   frameCount: animationFrameCount(of: object)).isPlaying)
        default: return nil
        }
    }

    /// The `<list>` control a script fills and reads.
    func invokeGUIList(method: String, object: WasabiObject, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue? {
        switch method {
        // The `<list>` control. Its rows live on the object (`WasabiGuiList`), so the renderer draws
        // what the script just wrote with no second copy in between.
        case "deleteallitems" where WasabiGuiList.isList(object):
            WasabiGuiList.setItems([], on: object)
            WasabiGuiList.setSelection([], on: object)
            WasabiGuiList.setScrollOffset(0, on: object)
            _ = object.setAttribute(WasabiGuiList.iconsKey, value: "")
            notifyObjectDidMutate(object)
            return .null
        case "additem" where WasabiGuiList.isList(object):
            var items = WasabiGuiList.items(of: object)
            guard items.count < WasabiGuiList.maximumItems else { return .integer(-1) }
            items.append(arguments[0].stringValue)
            WasabiGuiList.setItems(items, on: object)
            notifyObjectDidMutate(object)
            return .integer(Int32(items.count - 1))
        case "getnumitems" where WasabiGuiList.isList(object):
            return .integer(Int32(clamping: WasabiGuiList.items(of: object).count))
        case "getitemlabel" where WasabiGuiList.isList(object):
            // `getItemLabel(row, column)`. A row a script wrote with a plain `addItem` has one cell,
            // so column 0 is that whole string — which is what Big Bento's playlist search reads back
            // — while its Web Reader, which fills two columns per row, gets the cell it asks for.
            let cells = WasabiGuiList.columns(ofRow: Int(arguments[0].integerValue), on: object)
            let column = Int(arguments[1].integerValue)
            return .string(cells.indices.contains(column) ? cells[column] : "")
        case "getfirstitemselected" where WasabiGuiList.isList(object):
            return .integer(Int32(WasabiGuiList.selection(of: object).first ?? -1))
        case "getnextitemselected" where WasabiGuiList.isList(object):
            let after = Int(arguments[0].integerValue)
            return .integer(Int32(WasabiGuiList.selection(of: object).first { $0 > after } ?? -1))
        case "setitemlabel" where WasabiGuiList.isList(object):
            WasabiGuiList.setColumn(0, ofRow: Int(arguments[0].integerValue),
                                    to: arguments[1].stringValue, on: object)
            notifyObjectDidMutate(object)
            return .null
        case "setsubitem" where WasabiGuiList.isList(object):
            WasabiGuiList.setColumn(Int(arguments[1].integerValue), ofRow: Int(arguments[0].integerValue),
                                    to: arguments[2].stringValue, on: object)
            notifyObjectDidMutate(object)
            return .null
        case "setselected" where WasabiGuiList.isList(object):
            var selection = Set(WasabiGuiList.selection(of: object))
            let row = Int(arguments[0].integerValue)
            if arguments[1].truthy { selection.insert(row) } else { selection.remove(row) }
            WasabiGuiList.setSelection(Array(selection), on: object)
            notifyObjectDidMutate(object)
            return .null
        case "setitemicon" where WasabiGuiList.isList(object):
            WasabiGuiList.setIcon(arguments[1].stringValue, ofRow: Int(arguments[0].integerValue),
                                  on: object)
            notifyObjectDidMutate(object)
            return .null
        case "seticonwidth", "seticonheight", "setshowicons":
            // The icon column's geometry, written before the rows are added. The renderer draws the
            // icons at the row's own height, so the two sizes are recorded rather than obeyed; what
            // matters is `setShowIcons`, which is what decides whether the column is drawn at all.
            guard WasabiGuiList.isList(object) else { return .null }
            _ = object.setAttribute(method == "setshowicons" ? WasabiGuiList.showIconsKey
                                        : "nullplayer.script.list\(method.dropFirst(3))",
                                    value: arguments[0].stringValue)
            notifyObjectDidMutate(object)
            return .null
        case "setcancelieerrorpage":
            _ = object.setAttribute("nullplayer.script.cancelieerrorpage",
                                    value: arguments[0].truthy ? "1" : "0")
            return .null
        case "scrolltoitem" where WasabiGuiList.isList(object):
            // The row becomes the top of the box. Wasabi scrolls the least it can, but the renderer
            // clamps this against the box it ends up drawing in, and a script only ever asks for this
            // to bring a fresh hit into view.
            WasabiGuiList.setScrollOffset(Int(arguments[0].integerValue), on: object)
            notifyObjectDidMutate(object)
            return .null
        default: return nil
        }
    }

    /// Focus, clicks, target animations, actions, scale, regions and runtime instantiation.
    func invokeGUIActions(method: String, object: WasabiObject, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue? {
        switch method {
        case "setfocus":
            // The view owns the focus, because the keyboard is a window's property rather than the
            // graph's. It resolves the object to the `<edit>` it is or contains — a skin focuses the
            // wrapper (`Wasabi:EditBox2`) as often as the control.
            hooks.focusRequested?(embeddedControl(of: object) ?? object)
            return .null
        case "setfontsize":
            // The same pixel height the XML attribute carries, so it goes through the one
            // `WasabiTextMetrics` conversion the renderer and `getAutoWidth()` share.
            _ = object.setAttribute("fontsize", value: String(arguments[0].integerValue))
            notifyObjectDidMutate(object)
            return .null
        case "setalternatetext":
            // A script's alternate text *replaces* what the object shows — MMD3 puts its SEEK, VOLUME,
            // BASS and TREBLE readouts on the song ticker this way, then clears them a second later.
            // Empty restores the normal content. It is written to its own key rather than over the
            // XML `alternatetext`, which is a placeholder for "nothing to show" and must not be
            // promoted into an override (that is what pinned MMD3's display to "updating songticker").
            _ = object.setAttribute(WasabiTextMetrics.scriptAlternateTextKey,
                                    value: arguments[0].stringValue)
            notifyObjectDidMutate(object)
            expireAlternateText(of: object)
            return .null
        case "leftclick":
            // `leftClick()` is a press, so a togglebutton flips and a `cfgattrib` control writes its
            // attribute, exactly as `WinampModernMainView.performAction` does for the mouse (B71).
            // Defix's detached visualizer is the measured case: its Reattach and Random buttons are
            // plain groups whose script answers a click with `leftClick()` on a ghosted
            // `cfgattrib` togglebutton, and with only `onLeftClick` dispatched the attribute never
            // moved and neither button did anything. The flip comes first, as the mouse's does.
            _ = toggleActivation(of: object)
            _ = try dispatch(object: object, event: "onleftclick")
            let action = object.attributes["action"]
            hooks.actionRequested?(action ?? "", object.attributes["param"])
            if action == nil { _ = toggleConfigAttribute(of: object) }
            return .null
        case "settargetx": return setTarget("targetx", object: object, value: arguments[0])
        case "settargety": return setTarget("targety", object: object, value: arguments[0])
        case "settargetw": return setTarget("targetw", object: object, value: arguments[0])
        case "settargeth": return setTarget("targeth", object: object, value: arguments[0])
        case "settargeta": return setTarget("targeta", object: object, value: arguments[0])
        case "settargetspeed":
            _ = object.setAttribute("targetspeed", value: String(arguments[0].doubleValue))
            return .null
        case "gototarget":
            startTargetAnimation(object: object)
            return .null
        case "canceltarget":
            cancelTargetAnimation(objectID: object.stableID)
            _ = object.setAttribute("goingtotarget", value: "0")
            return .null
        case "reversetarget":
            reverseTargetAnimation(object: object)
            return .null
        case "isgoingtotarget": return .boolean(object.attributes["goingtotarget"] == "1")
        case "sendaction":
            // `sendAction` is Wasabi's script-to-script channel, and the receiver hears it as its own
            // `onAction(action, param, x, y, p1, p2, source)` — six arguments in, seven out, the last
            // being the sender. Routing it only to the host's action handler (the previous behaviour)
            // left every internal ClassicPro message unheard: the tab strip answers a click with
            // `CproSUI.sendAction("show_tab", …)`, and with nothing dispatching that, clicking a tab
            // reached the button's script and then stopped dead there.
            //
            // Delivered to the addressed object only, not down its subtree: every measured use names
            // the exact group whose script declares the handler.
            let source = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:))
            if Self.tracesActions {
                print("ACTION \(arguments[0].stringValue) param=\(arguments[1].stringValue) "
                      + "-> \(object.typeName)#\(object.xmlID ?? "-")")
            }
            let handled = try dispatch(object: object, event: "onaction",
                                       arguments: Array(arguments.prefix(6)) + [objectValue(source)])
            // The host action route is kept: a skin is also free to name one of NullPlayer's own
            // actions here, and nothing that used to work should stop.
            //
            // The **browser pair is the exception**, and only because both ends are real here now
            // (B40): a skin that ships its own reader answers `browser_search` / `browser_navigate`
            // itself — Big Bento's turns the terms into a query with its own engine setting and
            // navigates its `<browser>` — so letting the host act as well loads that same surface a
            // second time, with a URL the skin did not choose. They reach the host only when no
            // script took them, which is the skin that sends one and ships no reader.
            if handled == 0 || !Self.scriptOwnedBrowserActions.contains(arguments[0].stringValue.lowercased()) {
                hooks.actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
            }
            return .null
        case "triggeraction":
            hooks.actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
            return .null
        case "isinvalid":
            return .boolean(isInvalid(object))
        case "getcurcfgval":
            // A button bound to a config attribute (`cfgattrib="{GUID};Name"`) reports that
            // attribute's value; the GUID is the section key, exactly as `getItemByGuid` uses it.
            // Unbound objects fall back to their own toggle state.
            if let value = configInteger(of: object) { return .integer(value) }
            return .integer(Int32(object.attributes["value"] ?? "") ?? (object.attributes["activated"] == "1" ? 1 : 0))
        case "setscale":
            // "Scale all my windows to this." Answered by the host's UI Size, and only from a
            // **layout** receiver: that is the only form in the corpus, and a scale stamped on a
            // child object would be a second, rival scale for the same pixels. A non-layout
            // receiver is accepted and inert rather than refused — refusing a method aborts the
            // handler that called it.
            if object.tag.is(.layout) {
                let factor = arguments[0].doubleValue
                // A skin is not allowed to drive the host off the end of the scale; the host snaps
                // the request to one of its own levels anyway, and a garbage value should not reach
                // it as one. Winamp's own range is 1…3.
                if factor.isFinite, factor > 0 {
                    hooks.uiScaleRequested?(CGFloat(min(max(factor, 0.25), 4)))
                }
            }
            return .null
        case "getscale":
            // The scale the layout is drawn at, which here is UI Size. Skins that fill the screen
            // size the layout to `viewport / getScale()` — Nitrous Audio's monitor mode, 1010's
            // party mode, ClassicPro's maximize — and answered 1 at 135% they opened 1.35× the screen.
            return .float(Double(hooks.uiScaleQuery?() ?? 1))
        case "setredraw":
            // A redraw hint (`widgetsManager` throttles its list while populating). The renderer
            // repaints from the graph, so there is no suspended-drawing state to honour.
            return .null
        case "scrolltopercent":
            // Park a scrolling container at a percentage of its travel: `0` is the top, `100` the
            // bottom, and the renderer turns it into an offset applied to the children (see
            // `WasabiSceneRenderer.scrollOffset`). Every route a user has ends here — Big Bento
            // Modern's settings pages drive it from the scrollbar's drag (`onSetPosition`), from its
            // up/down buttons (`cscrollbar.maki` nudges the slider by 5), and from the wheel — so
            // while this was an accepted no-op *nothing* scrolled, by any means, and everything below
            // the fold on a settings page was unreachable (BB19).
            let percent = max(0, min(100, arguments[0].doubleValue))
            _ = object.setAttribute(WasabiSceneRenderer.scrollPercentKey, value: String(percent))
            noteGeometryChange()
            notifyObjectDidMutate(object)
            return .null
        case "back", "forward":
            if WasabiSceneRenderer.isBrowserElement(object) {
                hooks.browserHistoryRequested?(object.stableID, method == "forward")
            }
            return .null
        case "navigateurl":
            // A browser object may drive only its own embedded, policy-gated WebKit surface. Calls
            // on any other GUI object stay quietly inert so an untrusted skin cannot turn a generic
            // object reference into a network primitive.
            if WasabiSceneRenderer.isBrowserElement(object) {
                hooks.browserNavigationRequested?(object.stableID, arguments[0].stringValue)
            }
            return .null
        case let name where name.hasPrefix("fx_"):
            // The layer warp itself: `invokeLayerFX` writes the configuration and `fx_update()` is
            // what re-runs the skin's callbacks. See `WasabiLayerFX.swift` for the model.
            return invokeLayerFX(method: name, object: object, arguments: arguments)
        case "setregion":
            // The renderer draws from the graph and nothing else, so a region is stamped onto the
            // object and the scene redrawn — the same route `play`/`gotoFrame` take. A region that
            // was never loaded from a map (or an explicitly null one) clears the clip.
            var applied = false
            if case .object(let reference) = arguments[0],
               case .dynamic(let regionID) = reference.kind,
               let regionState = dynamicObjects[regionID],
               case .region(let clip) = regionState.role {
                applied = clip.apply(to: object)
            } else {
                applied = WasabiRegionClip.clear(on: object)
            }
            if applied { notifyGraphDidMutate() }
            return .null
        case "setregionfrommap":
            // The short form: a map, a threshold and the reversed flag, with no `Region` in between.
            guard case .object(let reference) = arguments[0],
                  case .dynamic(let mapID) = reference.kind,
                  let mapState = dynamicObjects[mapID],
                  case .map(let bitmapID, let source) = mapState.role else {
                if WasabiRegionClip.clear(on: object) { notifyGraphDidMutate() }
                return .null
            }
            let clip = WasabiRegionClip(mapID: bitmapID,
                                        mapPath: mapLogicalPath(bitmapID: bitmapID, source: source),
                                        threshold: Int(arguments[1].integerValue),
                                        reversed: arguments[2].truthy)
            if clip.apply(to: object) { notifyGraphDidMutate() }
            return .null
        case "islayoutanimationsafe", "istransparencysafe": return .boolean(true)
        // `init(parent)` — the second half of Wasabi's two-step runtime instantiation: `newGroup(id)`
        // *creates* the group, `init(parent)` **puts it where the script wants it**. Treating it as a
        // no-op is what made cPro-Bento's tab strip inert, and it is the whole of TASKS §15.6:
        //
        //   Tab tabI = newGroup("cpro.tab");   // lands under the script group, `Cpro.tabs`
        //   tabI.init(tabHolder);              // belongs in `cprotabs.buttons`, the 4px-inset strip
        //
        // Left under `Cpro.tabs`, each tab's `getParent()` answered the wrong object, so
        // `CproTabButton.m`'s `setDispatcher(getScriptGroup().getParent())` addressed `Cpro.tabs` while
        // `CproTabs.m` receives on `cprotabs.buttons` — a click reached the button's own script and
        // then went nowhere. It also left every pill 4px up and to the left of where the skin's own
        // reference render puts it. (§15.6 blamed the strip's script never initializing; it does run.)
        case "init":
            if case .object(let reference) = arguments[0], case .gui(let parentID) = reference.kind,
               let parent = loadedSkin.runtime.graph.object(withID: parentID), parent !== object.parent {
                // `insertChild` detaches from the old parent and refuses a cycle, so a script cannot
                // reparent an object into its own subtree.
                try parent.appendChild(object)
                noteGeometryChange()
                notifyGraphDidMutate()
            }
            // Attachment is also when the new subtree's own scripts start — see `pendingRuntimeGroups`.
            try startPendingScripts(for: object)
            return .null
        case "getautoreplay": return .boolean(object.attributes["autoreplay"] == "1")
        case "callme": return .null
        default: return nil
        }
    }
}
