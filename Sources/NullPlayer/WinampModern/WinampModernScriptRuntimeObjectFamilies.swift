import AppKit
import CoreGraphics
import Foundation

/// The rest of the MAKI `GuiObject` receiver, one table per object family; `invokeGUI` in
/// `WinampModernScriptRuntimeObject.swift` asks each in turn (B259, B243).
extension WinampModernScriptRuntime {
}

extension WinampModernScriptRuntime {
    /// Sliders, splitters and `cfgattrib` controls: the position a script reads and sets.
    static let guiPositionMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
        // Same rule as `getactivated`: for a bound control the setting *is* the position, and the
        // `value` attribute is not a second copy of it. mmd3 seeds its crossfade readout with
        // `slidercb.onSetPosition(slidercb.getPosition())` at load, which read 0 whatever the
        // stored duration was.
        table.add("getposition", 0) { runtime, call in
            if WasabiFrame.isFrame(call.object.tag) {
                // A splitter's position is its divider offset, not a slider value. ClassicPro reads it to
                // decide whether the side view is open (`mainFrame.getPosition()==0`).
                return .integer(Int32(clamping: Int(WasabiFrame.position(of: call.object))))
            }
            let readFrom = runtime.embeddedControl(of: call.object) ?? call.object
            // **A host-bound slider stands where the host stands, not where its last drag left a
            // copy.** The renderer already draws the thumb from `host.volume` / the playback clock /
            // the balance / the EQ snapshot (`normalizedValue(of:)`); the script side read the
            // `value` attribute, which nothing writes until the *user drags this very slider*. So a
            // skin that sizes its own artwork from the position it reads back got 0 at load and
            // after every volume change made anywhere else: ClassicPro's `sc_sliderbar` runs both
            // cPro2's volume fill and its hover glow off `max*mySlider.getPosition()/255`, and with
            // 0 for the position both layers were sized to zero width — the bar never filled and
            // hovering it lit nothing (B129).
            if let normalized = runtime.hostBoundValue(of: readFrom) {
                return .integer(WinampModernScriptRuntime.sliderPosition(normalized: normalized, of: readFrom))
            }
            if let value = runtime.configInteger(of: readFrom) { return .integer(value) }
            return .integer(Int32(readFrom.attributes["value"] ?? readFrom.attributes["position"] ?? "0") ?? 0)
        }
        table.add("setposition", 1) { runtime, call in
            if WasabiFrame.isFrame(call.object.tag) {
                guard WasabiFrame.setPosition(Double(call.arguments[0].integerValue),
                                              on: call.object) else { return .null }
                runtime.noteGeometryChange()
                runtime.notifyGraphDidMutate()
                _ = try runtime.dispatch(object: call.object, event: "onsetposition", arguments: [call.arguments[0]])
                return .null
            }
            if WinampModernScriptRuntime.configBinding(of: call.object) != nil {
                if let binding = WinampModernScriptRuntime.configBinding(of: call.object) {
                    runtime.setConfigAttribute(section: binding.section, key: binding.key,
                                               value: String(call.arguments[0].integerValue))
                }
                _ = try runtime.dispatch(object: call.object, event: "onsetposition", arguments: [call.arguments[0]])
                return .null
            }
            // Only an actual change notifies, as in Wasabi. Skins pair sliders that write each
            // other's position from their own `onSetPosition`; notifying unconditionally turns that
            // into an endless round trip.
            // Clamped to the range the slider declares, as Wasabi does. A skin that steps a slider
            // relative to itself — `slider.setPosition(slider.getPosition() + 5)`, which is how every
            // scrollbar's up/down button in the corpus works — otherwise walks straight off the end
            // and never comes back, and whatever reads the position is handed a number outside the
            // unit it was cut for. Only a declared range clamps: an object that states neither `low`
            // nor `high` is left exactly as it was.
            let target = runtime.embeddedControl(of: call.object) ?? call.object
            let clamped = WinampModernScriptRuntime.clampedSliderPosition(call.arguments[0].integerValue, of: target)
            let position = String(clamped)
            // A host-bound slider stands where the host stands (see `getposition`), so that is what a
            // write is compared against — and the write moves the host, as a drag does. Not a seek
            // bar: Winamp seeks on the *release*, so a script that keeps its thumb in step with the
            // clock (shark5's `seekslide`, from a timer) must not seek on every tick.
            let hostReading = target.attributes["action"]?.lowercased() == "seek"
                ? nil : runtime.hostBoundValue(of: target)
            let current = hostReading.map { String(WinampModernScriptRuntime.sliderPosition(normalized: $0,
                                                                                            of: target)) }
                ?? target.attributes["value"]
            guard current != position else { return .null }
            _ = target.setAttribute("value", value: position)
            if hostReading != nil {
                runtime.driveHost(from: target, normalized: WinampModernScriptRuntime.normalizedSliderPosition(clamped,
                                                                                                               of: target))
            }
            runtime.notifyObjectDidMutate(target)
            // Dispatched at the control that actually moved; `embeddedXUIForwardedEvents` carries it
            // back up to the wrapper, so a script bound to either one hears it exactly once.
            _ = try runtime.dispatch(object: target, event: "onsetposition",
                                     arguments: [.integer(Int32(position) ?? call.arguments[0].integerValue)])
            return .null
        }
        return table
    }()

    /// Animated layers: the play head, its range and its speed.
    static let guiAnimationMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
        table.add("setmode", 1) { runtime, call in
            _ = call.object.setAttribute("mode", value: call.arguments[0].stringValue)
            runtime.notifyObjectDidMutate(call.object)
            return .null
        }
        table.add("play", 0) { runtime, call in
            // Stamp the clock so the frame is a pure function of elapsed time (`WasabiAnimation`),
            // which keeps the renderer and `isPlaying()` on exactly the same model.
            _ = call.object.setAttribute("animstart", value: String(WasabiAnimation.now()))
            _ = call.object.setAttribute("playing", value: "1")
            runtime.notifyObjectDidMutate(call.object)
            runtime.startFrameEvents(for: call.object)
            return .null
        }
        table.add(["pause", "stop"], 0) { runtime, call in
            // Freeze where the animation actually is, not where it started.
            _ = call.object.setAttribute("frame", value: String(runtime.animationFrame(of: call.object)))
            _ = call.object.setAttribute("playing", value: "0")
            runtime.notifyObjectDidMutate(call.object)
            if call.method == "stop" { runtime.stopFrameEvents(for: call.object) }
            return .null
        }
        table.add(["gotoframe", "setframe"], 1) { runtime, call in
            let moved = call.object.setAttribute("frame", value: String(max(0, call.arguments[0].integerValue)))
            // Stopping a self-playing layer changes the animation clock's set, which only the full
            // notification re-reads. A step of an already-stopped layer is a cell swap — `frame` is
            // scene-neutral — so it repaints the layer's own rect: a beat meter stepping 12 layers
            // every 10 ms made each step a whole-window relayout and repaint (B152).
            if call.object.setAttribute("playing", value: "0") { runtime.notifyObjectDidMutate(call.object) }
            else if moved { runtime.requestRepaint(for: call.object) }
            return .null
        }
        table.add("getcurframe", 0) { runtime, call in
            .integer(Int32(runtime.animationFrame(of: call.object)))
        }
        // Animated-layer playback control. MMD3's volume/bass/treble knobs are animated layers
        // played frame-range to frame-range, and the driving timer polls `isPlaying()`.
        table.add("getlength", 0) { runtime, call in
            runtime.noteCoverRequest(call.object.attributes["image"] ?? "", by: call.program)
            return .integer(Int32(clamping: runtime.animationFrameCount(of: call.object)))
        }
        table.add("setstartframe", 1) { runtime, call in
            _ = call.object.setAttribute("startframe", value: String(max(0, call.arguments[0].integerValue)))
            return .null
        }
        table.add("setendframe", 1) { runtime, call in
            _ = call.object.setAttribute("endframe", value: String(max(0, call.arguments[0].integerValue)))
            return .null
        }
        // The read halves of the same pair. A skin that pages through a sprite sheet by hand
        // asks the layer where its own ends are rather than hard-coding a count: Hal's Eye
        // `manual.maki` caches `getCurFrame()`/`getEndFrame()` in `onScriptLoaded` and clamps
        // both page buttons against them, so with the signature missing the handler abandoned
        // the whole initialiser at that call and both buttons sat at frame 0 forever (B91).
        table.add("getstartframe", 0) { runtime, call in
            // Unset means "the whole sheet", exactly as `WasabiAnimation` reads it.
            let count = runtime.animationFrameCount(of: call.object)
            let raw = Int(call.object.attributes["startframe"] ?? "") ?? 0
            return .integer(Int32(max(0, min(count - 1, raw))))
        }
        table.add("getendframe", 0) { runtime, call in
            let count = runtime.animationFrameCount(of: call.object)
            let raw = Int(call.object.attributes["endframe"] ?? "") ?? (count - 1)
            return .integer(Int32(max(0, min(count - 1, raw))))
        }
        table.add("setspeed", 1) { runtime, call in
            _ = call.object.setAttribute("speed", value: String(max(1, call.arguments[0].integerValue)))
            return .null
        }
        // Part of the same four-call preamble every skin writes before `play()`, and the one that
        // was missing: Big Bento Modern's `animbutton` sets start, end, **autoreplay** and speed
        // in that order, so a missing signature here abandoned the whole handler at the third
        // call — the play/pause morph never ran and the buttons were never swapped.
        table.add("setautoreplay", 1) { runtime, call in
            // Written to the same attribute the markup carries, so `WasabiAnimation` reads one value
            // whether the skin declared it or a script set it. It only decides what a layer does with
            // *no* explicit `playing`, which is why a range play started right after is unaffected.
            _ = call.object.setAttribute("autoreplay", value: call.arguments[0].integerValue != 0 ? "1" : "0")
            return .null
        }
        table.add("isplaying", 0) { runtime, call in
            return .boolean(WasabiAnimation.state(of: call.object,
                                                  frameCount: runtime.animationFrameCount(of: call.object)).isPlaying)
        }
        // `isStopped()` is the **`AnimatedLayer`'s**, not the player's — the same receiver
        // `play()` and `stop()` take, pinned by the call sites (`RENDER_DISASM=isStopped`:
        // `op1(v3) op24(isstopped)` where `v3` is also the receiver of `play`). It reads like a
        // transport question, and that resemblance is the trap: `isPlaying` beside it was already
        // implemented for animated layers, so the pair looked complete while T800's jaw animation
        // — `Noname2.maki`, behind the `animationbutton` under the mouth — aborted on the missing
        // half every time it was pressed.
        // Wasabi has no third state for a layer, so this is exactly `!isPlaying` and is written from
        // the same reading rather than a second one that could drift from it.
        table.add("isstopped", 0) { runtime, call in
            return .boolean(!WasabiAnimation.state(of: call.object,
                                                   frameCount: runtime.animationFrameCount(of: call.object)).isPlaying)
        }
        return table
    }()

    /// The `<list>` control a script fills and reads.
    static let guiListMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
        // The `<list>` control a script fills — Big Bento's playlist search is the measured
        // consumer, and every arity here is counted from its call sites: `deleteAllItems()`,
        // `getItemLabel(item, column)`, `getFirstItemSelected()`, `getNextItemSelected(after)`,
        // `scrollToItem(item)`. `addItem` is already declared (the dynamic `List` container shares
        // the name); the receiver decides which one answers.
        // The `<list>` control. Its rows live on the object (`WasabiGuiList`), so the renderer draws
        // what the script just wrote with no second copy in between.
        table.add("deleteallitems", 0) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                WasabiGuiList.setItems([], on: call.object)
                WasabiGuiList.setSelection([], on: call.object)
                WasabiGuiList.setScrollOffset(0, on: call.object)
                _ = call.object.setAttribute(WasabiGuiList.iconsKey, value: "")
                runtime.notifyObjectDidMutate(call.object)
                return .null
            }
            return nil
        }
        table.add("additem", 1) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                var items = WasabiGuiList.items(of: call.object)
                guard items.count < WasabiGuiList.maximumItems else { return .integer(-1) }
                items.append(call.arguments[0].stringValue)
                WasabiGuiList.setItems(items, on: call.object)
                runtime.notifyObjectDidMutate(call.object)
                return .integer(Int32(items.count - 1))
            }
            return nil
        }
        table.add("getnumitems", 0) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                return .integer(Int32(clamping: WasabiGuiList.items(of: call.object).count))
            }
            return nil
        }
        table.add("getitemlabel", 2) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                // `getItemLabel(row, column)`. A row a script wrote with a plain `addItem` has one cell,
                // so column 0 is that whole string — which is what Big Bento's playlist search reads back
                // — while its Web Reader, which fills two columns per row, gets the cell it asks for.
                let cells = WasabiGuiList.columns(ofRow: Int(call.arguments[0].integerValue), on: call.object)
                let column = Int(call.arguments[1].integerValue)
                return .string(cells.indices.contains(column) ? cells[column] : "")
            }
            return nil
        }
        table.add("getfirstitemselected", 0) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                return .integer(Int32(WasabiGuiList.selection(of: call.object).first ?? -1))
            }
            return nil
        }
        table.add("getnextitemselected", 1) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                let after = Int(call.arguments[0].integerValue)
                return .integer(Int32(WasabiGuiList.selection(of: call.object).first { $0 > after } ?? -1))
            }
            return nil
        }
        // The write half of the same control, and Big Bento Modern's Web Reader is the measured
        // consumer: its provider drop-down adds a placeholder row per `parser_onCallback` and
        // then fills that row's two columns and its icon. The three `setIcon*`/`setShowIcons`
        // calls sit at the very top of the same `onSetVisible` that loads the provider file, so
        // until they existed the handler aborted before reaching the parser at all.
        table.add("setitemlabel", 2) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                WasabiGuiList.setColumn(0, ofRow: Int(call.arguments[0].integerValue),
                                        to: call.arguments[1].stringValue, on: call.object)
                runtime.notifyObjectDidMutate(call.object)
                return .null
            }
            return nil
        }
        table.add("setsubitem", 3) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                WasabiGuiList.setColumn(Int(call.arguments[1].integerValue), ofRow: Int(call.arguments[0].integerValue),
                                        to: call.arguments[2].stringValue, on: call.object)
                runtime.notifyObjectDidMutate(call.object)
                return .null
            }
            return nil
        }
        // `setSelected(row, selected)` — the write half of `getFirstItemSelected`. The reader
        // selects the provider it restored so the drop-down opens on it.
        table.add("setselected", 2) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                var selection = Set(WasabiGuiList.selection(of: call.object))
                let row = Int(call.arguments[0].integerValue)
                if call.arguments[1].truthy { selection.insert(row) } else { selection.remove(row) }
                WasabiGuiList.setSelection(Array(selection), on: call.object)
                runtime.notifyObjectDidMutate(call.object)
                return .null
            }
            return nil
        }
        table.add("setitemicon", 2) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                WasabiGuiList.setIcon(call.arguments[1].stringValue, ofRow: Int(call.arguments[0].integerValue),
                                      on: call.object)
                runtime.notifyObjectDidMutate(call.object)
                return .null
            }
            return nil
        }
        table.add(["seticonwidth", "seticonheight", "setshowicons"], 1) { runtime, call in
            // The icon column's geometry, written before the rows are added. The renderer draws the
            // icons at the row's own height, so the two sizes are recorded rather than obeyed; what
            // matters is `setShowIcons`, which is what decides whether the column is drawn at all.
            guard WasabiGuiList.isList(call.object) else { return .null }
            _ = call.object.setAttribute(call.method == "setshowicons" ? WasabiGuiList.showIconsKey
                                        : "nullplayer.script.list\(call.method.dropFirst(3))",
                                    value: call.arguments[0].stringValue)
            runtime.notifyObjectDidMutate(call.object)
            return .null
        }
        // Internet Explorer's own error page, which a `<browser>` asks Winamp to suppress so it
        // can show its own. There is no IE here — the surface is WebKit — so the preference is
        // recorded and nothing else; refusing it aborted the handler that sets it, which on Big
        // Bento Modern is the one that also loads the Web Reader's provider list.
        table.add("setcancelieerrorpage", 1) { runtime, call in
            _ = call.object.setAttribute("nullplayer.script.cancelieerrorpage",
                                         value: call.arguments[0].truthy ? "1" : "0")
            return .null
        }
        table.add("scrolltoitem", 1) { runtime, call in
            if WasabiGuiList.isList(call.object) {
                // The row becomes the top of the box. Wasabi scrolls the least it can, but the renderer
                // clamps this against the box it ends up drawing in, and a script only ever asks for this
                // to bring a fresh hit into view.
                WasabiGuiList.setScrollOffset(Int(call.arguments[0].integerValue), on: call.object)
                runtime.notifyObjectDidMutate(call.object)
                return .null
            }
            return nil
        }
        return table
    }()

    /// Focus, clicks, target animations, actions, scale, regions and runtime instantiation.
    static let guiActionMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
        // `setFocus()` — the keyboard, asked for by the object that wants it. Big Bento's
        // `playlistpro.maki` shows its playlist search box and focuses it in the same handler, so
        // without this the handler aborted at the focus call and the box could never be typed in.
        table.add("setfocus", 0) { runtime, call in
            // The view owns the focus, because the keyboard is a window's property rather than the
            // graph's. It resolves the object to the `<edit>` it is or contains — a skin focuses the
            // wrapper (`Wasabi:EditBox2`) as often as the control.
            runtime.hooks.focusRequested?(runtime.embeddedControl(of: call.object) ?? call.object)
            return .null
        }
        table.add("setfontsize", 1) { runtime, call in
            // The same pixel height the XML attribute carries, so it goes through the one
            // `WasabiTextMetrics` conversion the renderer and `getAutoWidth()` share.
            _ = call.object.setAttribute("fontsize", value: String(call.arguments[0].integerValue))
            runtime.notifyObjectDidMutate(call.object)
            return .null
        }
        table.add("setalternatetext", 1) { runtime, call in
            // A script's alternate text *replaces* what the object shows — MMD3 puts its SEEK, VOLUME,
            // BASS and TREBLE readouts on the song ticker this way, then clears them a second later.
            // Empty restores the normal content. It is written to its own key rather than over the
            // XML `alternatetext`, which is a placeholder for "nothing to show" and must not be
            // promoted into an override (that is what pinned MMD3's display to "updating songticker").
            _ = call.object.setAttribute(WasabiTextMetrics.scriptAlternateTextKey,
                                         value: call.arguments[0].stringValue)
            runtime.notifyObjectDidMutate(call.object)
            runtime.expireAlternateText(of: call.object)
            return .null
        }
        table.add("leftclick", 0) { runtime, call in
            // `leftClick()` is a press, so a togglebutton flips and a `cfgattrib` control writes its
            // attribute, exactly as `WinampModernMainView.performAction` does for the mouse (B71).
            // Defix's detached visualizer is the measured case: its Reattach and Random buttons are
            // plain groups whose script answers a click with `leftClick()` on a ghosted
            // `cfgattrib` togglebutton, and with only `onLeftClick` dispatched the attribute never
            // moved and neither button did anything. Both flips come first, as the mouse's do (B279).
            if !runtime.toggleActivation(of: call.object), call.object.attributes["action"] == nil {
                _ = runtime.toggleConfigAttribute(of: call.object)
            }
            _ = try runtime.dispatch(object: call.object, event: "onleftclick")
            // Read after the handler, as the mouse does: one that `setXmlParam`s its own action
            // sends the new one.
            runtime.hooks.actionRequested?(call.object.attributes["action"] ?? "", call.object.attributes["param"])
            return .null
        }
        table.add("settargetx", 1) { runtime, call in
            runtime.setTarget("targetx", object: call.object, value: call.arguments[0])
        }
        table.add("settargety", 1) { runtime, call in
            runtime.setTarget("targety", object: call.object, value: call.arguments[0])
        }
        table.add("settargetw", 1) { runtime, call in
            runtime.setTarget("targetw", object: call.object, value: call.arguments[0])
        }
        table.add("settargeth", 1) { runtime, call in
            runtime.setTarget("targeth", object: call.object, value: call.arguments[0])
        }
        table.add("settargeta", 1) { runtime, call in
            runtime.setTarget("targeta", object: call.object, value: call.arguments[0])
        }
        table.add("settargetspeed", 1) { runtime, call in
            _ = call.object.setAttribute("targetspeed", value: String(call.arguments[0].doubleValue))
            return .null
        }
        table.add("gototarget", 0) { runtime, call in
            runtime.startTargetAnimation(object: call.object)
            return .null
        }
        table.add("canceltarget", 0) { runtime, call in
            runtime.cancelTargetAnimation(objectID: call.object.stableID)
            _ = call.object.setAttribute("goingtotarget", value: "0")
            return .null
        }
        table.add("reversetarget", 1) { runtime, call in
            runtime.reverseTargetAnimation(object: call.object)
            return .null
        }
        table.add("isgoingtotarget", 0) { runtime, call in
            .boolean(call.object.attributes["goingtotarget"] == "1")
        }
        table.add("sendaction", 6) { runtime, call in
            // `sendAction` is Wasabi's script-to-script channel, and the receiver hears it as its own
            // `onAction(action, param, x, y, p1, p2, source)` — six arguments in, seven out, the last
            // being the sender. Routing it only to the host's action handler (the previous behaviour)
            // left every internal ClassicPro message unheard: the tab strip answers a click with
            // `CproSUI.sendAction("show_tab", …)`, and with nothing dispatching that, clicking a tab
            // reached the button's script and then stopped dead there.
            //
            // Delivered to the addressed object only, not down its subtree: every measured use names
            // the exact group whose script declares the handler.
            let source = call.program.ownerID.flatMap(runtime.loadedSkin.runtime.graph.object(withID:))
            if WinampModernScriptRuntime.tracesActions {
                print("ACTION \(call.arguments[0].stringValue) param=\(call.arguments[1].stringValue) "
                      + "-> \(call.object.typeName)#\(call.object.xmlID ?? "-")")
            }
            let handled = try runtime.dispatch(object: call.object, event: "onaction",
                                               arguments: Array(call.arguments.prefix(6)) + [runtime.objectValue(source)])
            // The host action route is kept: a skin is also free to name one of NullPlayer's own
            // actions here, and nothing that used to work should stop.
            //
            // The **browser pair is the exception**, and only because both ends are real here now
            // (B40): a skin that ships its own reader answers `browser_search` / `browser_navigate`
            // itself — Big Bento's turns the terms into a query with its own engine setting and
            // navigates its `<browser>` — so letting the host act as well loads that same surface a
            // second time, with a URL the skin did not choose. They reach the host only when no
            // script took them, which is the skin that sends one and ships no reader.
            let action = call.arguments[0].stringValue
            if handled == 0 || !WinampModernScriptRuntime.scriptOwnedBrowserActions.contains(action.lowercased()) {
                runtime.hooks.actionRequested?(call.arguments[0].stringValue, call.arguments[1].stringValue)
            }
            return .null
        }
        table.add("triggeraction", 2) { runtime, call in
            runtime.hooks.actionRequested?(call.arguments[0].stringValue, call.arguments[1].stringValue)
            return .null
        }
        // `isInvalid()` is how a ClassicPro script asks "did this element survive the skin's
        // overrides?" before configuring it; `getScale()` is a layout's zoom factor.
        table.add("isinvalid", 0) { runtime, call in .boolean(runtime.isInvalid(call.object)) }
        table.add("getcurcfgval", 0) { runtime, call in
            // A button bound to a config attribute (`cfgattrib="{GUID};Name"`) reports that
            // attribute's value; the GUID is the section key, exactly as `getItemByGuid` uses it.
            // Unbound objects fall back to their own toggle state.
            if let value = runtime.configInteger(of: call.object) { return .integer(value) }
            let attributes = call.object.attributes
            return .integer(Int32(attributes["value"] ?? "") ?? (attributes["activated"] == "1" ? 1 : 0))
        }
        // Its write half is the host's UI Size, not a layout transform — see `uiScaleRequested`.
        table.add("setscale", 1) { runtime, call in
            // "Scale all my windows to this." Answered by the host's UI Size, and only from a
            // **layout** receiver: that is the only form in the corpus, and a scale stamped on a
            // child object would be a second, rival scale for the same pixels. A non-layout
            // receiver is accepted and inert rather than refused — refusing a method aborts the
            // handler that called it.
            if call.object.tag.is(.layout) {
                let factor = call.arguments[0].doubleValue
                // A skin is not allowed to drive the host off the end of the scale; the host snaps
                // the request to one of its own levels anyway, and a garbage value should not reach
                // it as one. Winamp's own range is 1…3.
                if factor.isFinite, factor > 0 {
                    runtime.hooks.uiScaleRequested?(CGFloat(min(max(factor, 0.25), 4)))
                }
            }
            return .null
        }
        table.add("getscale", 0) { runtime, call in
            // The scale the layout is drawn at, which here is UI Size. Skins that fill the screen
            // size the layout to `viewport / getScale()` — Nitrous Audio's monitor mode, 1010's
            // party mode, ClassicPro's maximize — and answered 1 at 135% they opened 1.35× the screen.
            return .float(Double(runtime.hooks.uiScaleQuery?() ?? 1))
        }
        table.add("setredraw", 1) { runtime, call in
            // A redraw hint (`widgetsManager` throttles its list while populating). The renderer
            // repaints from the graph, so there is no suspended-drawing state to honour.
            return .null
        }
        // `scrollToPercent(pct)` on a scrolling group. Arity 1, result discarded — pinned by the
        // bytecode (`v103.scrollToPercent(v119)` followed by `op2`).
        table.add("scrolltopercent", 1) { runtime, call in
            // Park a scrolling container at a percentage of its travel: `0` is the top, `100` the
            // bottom, and the renderer turns it into an offset applied to the children (see
            // `WasabiSceneRenderer.scrollOffset`). Every route a user has ends here — Big Bento
            // Modern's settings pages drive it from the scrollbar's drag (`onSetPosition`), from its
            // up/down buttons (`cscrollbar.maki` nudges the slider by 5), and from the wheel — so
            // while this was an accepted no-op *nothing* scrolled, by any means, and everything below
            // the fold on a settings page was unreachable (BB19).
            let percent = max(0, min(100, call.arguments[0].doubleValue))
            _ = call.object.setAttribute(WasabiSceneRenderer.scrollPercentKey, value: String(percent))
            runtime.noteGeometryChange()
            runtime.notifyObjectDidMutate(call.object)
            return .null
        }
        table.add(["back", "forward"], 0) { runtime, call in
            if WasabiSceneRenderer.isBrowserElement(call.object) {
                runtime.hooks.browserHistoryRequested?(call.object.stableID, call.method == "forward")
            }
            return .null
        }
        table.add("navigateurl", 1) { runtime, call in
            // A browser object may drive only its own embedded, policy-gated WebKit surface. Calls
            // on any other GUI object stay quietly inert so an untrusted skin cannot turn a generic
            // object reference into a network primitive.
            if WasabiSceneRenderer.isBrowserElement(call.object) {
                runtime.hooks.browserNavigationRequested?(call.object.stableID, call.arguments[0].stringValue)
            }
            return .null
        }
        table.add("setregion", 1) { runtime, call in
            // The renderer draws from the graph and nothing else, so a region is stamped onto the
            // object and the scene redrawn — the same route `play`/`gotoFrame` take. A region that
            // was never loaded from a map (or an explicitly null one) clears the clip.
            var applied = false
            if case .object(let reference) = call.arguments[0],
               case .dynamic(let regionID) = reference.kind,
               let regionState = runtime.dynamicObjects[regionID],
               case .region(let clip) = regionState.role {
                applied = clip.apply(to: call.object)
            } else {
                applied = WasabiRegionClip.clear(on: call.object)
            }
            if applied { runtime.notifyGraphDidMutate() }
            return .null
        }
        table.add("setregionfrommap", 3) { runtime, call in
            // The short form: a map, a threshold and the reversed flag, with no `Region` in between.
            guard case .object(let reference) = call.arguments[0],
                  case .dynamic(let mapID) = reference.kind,
                  let mapState = runtime.dynamicObjects[mapID],
                  case .map(let bitmapID, let source) = mapState.role else {
                if WasabiRegionClip.clear(on: call.object) { runtime.notifyGraphDidMutate() }
                return .null
            }
            let clip = WasabiRegionClip(mapID: bitmapID,
                                        mapPath: runtime.mapLogicalPath(bitmapID: bitmapID, source: source),
                                        threshold: Int(call.arguments[1].integerValue),
                                        reversed: call.arguments[2].truthy)
            if clip.apply(to: call.object) { runtime.notifyGraphDidMutate() }
            return .null
        }
        table.add(["islayoutanimationsafe", "istransparencysafe"], 0) { runtime, call in .boolean(true) }
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
        table.add("init", 1) { runtime, call in
            if case .object(let reference) = call.arguments[0], case .gui(let parentID) = reference.kind,
               let parent = runtime.loadedSkin.runtime.graph.object(withID: parentID), parent !== call.object.parent {
                // `insertChild` detaches from the old parent and refuses a cycle, so a script cannot
                // reparent an object into its own subtree.
                try parent.appendChild(call.object)
                runtime.noteGeometryChange()
                runtime.notifyGraphDidMutate()
            }
            // Attachment is also when the new subtree's own scripts start — see `pendingRuntimeGroups`.
            try runtime.startPendingScripts(for: call.object)
            return .null
        }
        table.add("getautoreplay", 0) { runtime, call in
            .boolean(call.object.attributes["autoreplay"] == "1")
        }
        table.add("callme", 1) { runtime, call in .null }
        return table
    }()
}
