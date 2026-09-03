import AppKit
import CoreGraphics
import Foundation

/// The MAKI object receivers: the `GuiObject` surface every Group, Layer and Layout
/// answers, and the runtime-instantiated objects a script makes for itself. Split out of
/// `WinampModernScriptRuntime.swift`; see
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

    func invokeGUI(method: String, object: WasabiObject, arguments: [MakiValue],
                           program: MakiProgram) throws -> MakiValue {
        if method == "showcurrentlyplayingentry" {
            let index = playlistSnapshot.currentIndex
            if index >= 0 { playlistRevealRowRequested?(index) }
            return .null
        }
        if Self.dispatchableEventArity[method] != nil {
            _ = try dispatch(object: object, event: method, arguments: arguments)
            // No handler can answer through this path (the interpreter's return value belongs to the
            // handler's own frame), so `onAction` reports the neutral slot 0 rather than a fiction.
            return method == "onaction" ? .integer(0) : .null
        }
        switch method {
        // A layout Winamp has not created yet does not answer. Winamp builds a container's layouts
        // on demand, so `getContainer("main").getLayout("shade")` is NULL until the window is shaded
        // — and a skin whose scripts branch on that (`if (normal) {…} if (shade) {…}`, two blocks
        // meant to be mutually exclusive) has both blocks run here, because we build every layout up
        // front. Big Bento Modern is the measured case: 89 of its bindings were overwritten by the
        // second block and landed in the shade layout, which is why its normal layout had no working
        // volume control. See `WinampModernScriptRuntime.realizedLayouts`.
        case "getlayout":
            guard let match = object.children.first(where: {
                $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
                $0.xmlID?.caseInsensitiveCompare(arguments[0].stringValue) == .orderedSame
            }) ?? descendant(of: object, xmlID: arguments[0].stringValue) else { return .null }
            return isLayoutCreated(match, askedBy: program) ? objectValue(match) : .null
        case "getobject":
            return objectValue(descendant(of: object, xmlID: arguments[0].stringValue))
        // `findObject` is the *wide* lookup and `getObject` the narrow one — Wasabi searches the
        // receiver's own subtree first and then the rest of the window, which is the whole reason a
        // skin reaches for one name over the other. Defix's core script holds `sui.content` and asks
        // it for `switch.ml`, a tab button that lives in `grid.s2`, a **sibling** subtree: answered
        // from descendants alone every one of the five tab lookups came back null, the script bound
        // its click handlers to nothing, and the SUI body never switched tabs however well the
        // buttons themselves lit up. The nearest match still wins, so a skin with the same id in
        // both places keeps getting its own.
        case "findobject":
            let wanted = arguments[0].stringValue
            if let near = descendant(of: object, xmlID: wanted) { return objectValue(near) }
            guard let root = ancestor(of: object, type: "container") else { return .null }
            return objectValue(descendant(of: root, xmlID: wanted))
        case "getcontainer": return objectValue(ancestor(of: object, type: "container"))
        case "getcurlayout":
            return objectValue(activeLayoutByContainer[object.stableID].flatMap(loadedSkin.runtime.graph.object(withID:)))
        case "switchtolayout":
            guard object.typeName.caseInsensitiveCompare("container") == .orderedSame,
                  let next = object.children.first(where: {
                      $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
                      $0.xmlID?.caseInsensitiveCompare(arguments[0].stringValue) == .orderedSame
                  }) else { return .null }
            activeLayoutByContainer[object.stableID] = next.stableID
            realizedLayouts.insert(next.stableID)
            _ = layoutSwitchRequested?(object.stableID, arguments[0].stringValue)
            _ = try dispatch(object: object, event: "onswitchtolayout", arguments: [objectValue(next)])
            return .null
        case "getnumchildren": return .integer(Int32(clamping: object.children.count))
        case "enumchildren":
            let index = Int(arguments[0].integerValue)
            guard object.children.indices.contains(index) else { return .null }
            return objectValue(object.children[index])
        // `GroupList.instantiate(groupdef, count)` — the *list's* own expansion, as against
        // `System.newGroup`. Big Bento Modern builds all nine of its config pages and the SUI's
        // equalizer tab this way: the page's XML holds an empty `<GroupList>` and a scrollbar, and
        // every option on it lives in a `…part1` / `…part2` groupdef the script expands here. That
        // is why the whole family reported `unsupported` although it drew.
        case "instantiate":
            guard let instantiate = loadedSkin.runtime.instantiateGroup else { return .null }
            let identifier = arguments[0].stringValue
            // The count is skin input, so it is bounded here as well as by the shared object budget
            // `instantiateGroupAtRuntime` counts against. Nothing measured asks for more than one.
            let count = min(max(Int(arguments[1].integerValue), 0), Self.maximumGroupListInstances)
            var instantiated: WasabiObject?
            for _ in 0..<count {
                let child = try instantiate(identifier, object)
                stackInGroupList(child, list: object)
                // Started **now**, not queued behind the dispatch like `newGroup`'s. The queue exists
                // for Wasabi's two-step create-then-`init(parent)` dance, where a script must not look
                // around before it has been put where it belongs; `instantiate` has no second step —
                // the child is parented into the list on the line above. And the caller's very next
                // move is to configure it: `widgetsManager.maki` does
                // `g = grplst.instantiate("widgets.manager.listitem", 1)` and then eight
                // `g.setXmlParam(…)` calls in a row, all of which the item's own
                // `system.onSetXuiParam` has to hear. Deferred, every one of them landed before the
                // handler was listening and each Widgets Manager row drew its groupdef placeholders.
                try? startScripts(addedBeneath: child)
                instantiated = child
            }
            if instantiated != nil {
                noteGeometryChange()
                notifyGraphDidMutate()
            }
            return objectValue(instantiated)
        case "getid": return .string(object.xmlID ?? "")
        case "getparent": return objectValue(object.parent)
        case "getparentlayout": return objectValue(ancestor(of: object, type: "layout"))
        case "getxmlparam": return .string(object.attributes[arguments[0].stringValue.lowercased()] ?? "")
        case "setxmlparam":
            let key = arguments[0].stringValue
            let value = arguments[1].stringValue
            // An image-valued param is a *load*, and a load that fails leaves the object wearing the
            // artwork it already had — including when the new id is empty, which loads nothing.
            //
            // Defix names its background art from a stored preference and never seeds one:
            // `getPrivateString(getSkinName(), "BG", "")`. On a profile that has not opened its
            // configurator that is `""`, so the layout is asked for background `""` and every one of
            // the nine frame slices for `"" + "_background_material.Element.top.left"` — ids no skin
            // defines. Taking them literally threw away the wood panel the layout declares
            // (`background="BG1"`) and the frame around the player, both speakers, the playlist and
            // the library, leaving flat black boxes. The skin ships a screenshot of itself framed and
            // panelled, which is what Winamp shows for a set that never loaded.
            guard !Self.imageKeys.contains(key.lowercased()) || resolvesToResource(value)
            else { return .null }
            let reportedBeforeWrite = reportedOrigin(of: object)
            _ = object.setAttribute(key, value: value)
            if Self.geometryKeys.contains(key.lowercased()) {
                // A container or a layout is a *window*: its box is not read back out of the graph at
                // the next repaint, it has to be pushed to AppKit. `resize()` already did this; the
                // same four attributes written one at a time did not, which is how Big Bento's search
                // results came out at the container's declared 275×116 in the corner of the screen
                // instead of under the search box it measured itself against (BB31).
                applyContainerGeometry(object, reportedOrigin: reportedBeforeWrite)
                noteGeometryChange()
                notifyGraphDidMutate()
            } else {
                notifyObjectDidMutate(object)
            }
            deliverRuntimeXUIParam(key, value: value, to: object)
            applyCustomObjectGroup(key, value: value, to: object)
            return .null
        case "settext":
            // Through the `embed_xui` link, exactly as `setPosition`/`getPosition` are: the wrapper
            // **is** the control and its text must not exist in two places. Big Bento's file-info
            // lines are the case that proves it — `<groupdef id="bento.infodisplay.line"
            // embed_xui="text" xuitag="Bento:InfoLine">` — where `fileinfo.maki` fills the inner
            // `<Text id="text">` while `fileinfo_lyrics_finder.maki` reads the *wrapper* with
            // `getText()` to build its search. Kept apart, the reader answered "" and the lyrics
            // button searched the web for the bare word "lyrics" (B40).
            let object = embeddedControl(of: object) ?? object
            _ = object.setAttribute("text", value: arguments[0].stringValue)
            // Written to its own key as well, because a non-empty value has to beat the object's
            // `display=` binding — see `WasabiTextMetrics.scriptTextKey`. Empty writes through as
            // empty, which is exactly the revert a skin means by `setText("")`.
            _ = object.setAttribute(WasabiTextMetrics.scriptTextKey, value: arguments[0].stringValue)
            // `setText` is also how a skin takes an alternate text back down: MMD3's ticker timer
            // fires `setText("")` a second after a `setAlternateText("VOLUME: 40%")` and expects the
            // song title back.
            _ = object.setAttribute(WasabiTextMetrics.scriptAlternateTextKey, value: "")
            notifyObjectDidMutate(object)
            return .null
        // What the object *shows*, not just the literal it was declared with. MMD3's songinfo timer
        // reads `getText()` off the `display="songinfo"` text and tokenises it for KBPS/KHZ; answering
        // with the (empty) `default=` attribute left both fields blank forever.
        // Read through the same `embed_xui` link `setText` writes through, above.
        case "gettext":
            return .string(WasabiTextMetrics.content(of: embeddedControl(of: object) ?? object,
                                                     host: host))
        case "getautowidth":
            return .integer(autoWidth(of: object))
        case "getautoheight":
            return .integer(autoHeight(of: object))
        case "gettextwidth":
            // Measured with the font the renderer draws with, and through the same content
            // resolution — a `display=` binding, a songticker's implicit title, `setAlternateText` —
            // so the answer is about the string on screen rather than the XML literal. Through the
            // `embed_xui` link for the same reason `getText` is: the wrapper draws nothing itself,
            // so measuring it measures an empty string.
            let measured = embeddedControl(of: object) ?? object
            return .integer(Int32(clamping: Int(metrics.width(
                of: measured, text: WasabiTextMetrics.content(of: measured, host: host)).rounded(.up))))
        case "getguid":
            return .string(object.attributes["guid"] ?? "")
        case "resize":
            let reportedBeforeResize = reportedOrigin(of: object)
            let borrowed = borrowedWindowOrigin(
                matching: CGPoint(x: Double(arguments[0].integerValue),
                                  y: Double(arguments[1].integerValue)),
                writtenOn: object)
            for (key, value) in zip(["x", "y", "w", "h"], arguments) {
                _ = object.setAttribute(key, value: String(value.integerValue))
            }
            if object.typeName.caseInsensitiveCompare("layout") == .orderedSame,
               let container = ancestor(of: object, type: "container") {
                layoutResizeRequested?(container.stableID,
                                       CGSize(width: CGFloat(arguments[2].integerValue),
                                              height: CGFloat(arguments[3].integerValue)))
            }
            applyContainerGeometry(object, reportedOrigin: reportedBeforeResize,
                                   desktopOrigin: borrowed)
            noteGeometryChange()
            notifyGraphDidMutate()
            return .null
        // `onSetVisible` fires only on an actual change, as in Wasabi. ClassicPro's `beat.m` hangs its
        // VU timer off `beatGroup.onSetVisible`, and `showGroup` hides both display groups before
        // showing one — notifying unconditionally would stop and restart the timer on every refresh.
        case "show": return try setVisible(object, true)
        case "hide": return try setVisible(object, false)
        // `toggle()` is `show`/`hide` with the direction read back first, and the direction has to
        // come from the **host's** window state rather than from the graph. Ujola Cat's two console
        // buttons carry no `action` at all — `getContainer("colorthemes").toggle()` is their entire
        // behaviour — and a window's visibility changes by four routes that never write the graph's
        // `visible` attribute (the Windows menu, a markup `TOGGLE`, this call, the window's own close
        // button), so an attribute-read toggle inverts after the first manual close.
        case "toggle": return try setVisible(object, !effectiveVisibility(of: object))
        case "isvisible": return .boolean(effectiveVisibility(of: object))
        case "isactive": return .boolean(isActive(object))
        case "setalpha":
            let clamped = max(0, min(255, arguments[0].integerValue))
            _ = object.setAttribute("alpha", value: String(clamped))
            notifyObjectDidMutate(object)
            if object.typeName.caseInsensitiveCompare("container") == .orderedSame,
               let id = object.xmlID {
                containerAlphaChanged?(id, CGFloat(clamped) / 255.0)
            }
            return .null
        case "getalpha": return .integer(Int32(object.attributes["alpha"] ?? "255") ?? 255)
        case "setenabled":
            _ = object.setAttribute("enabled", value: arguments[0].truthy ? "1" : "0")
            notifyObjectDidMutate(object)
            return .null
        case "setactivated":
            setActivated(object, arguments[0].truthy)
            _ = try dispatch(object: object, event: "ontoggle", arguments: [.boolean(arguments[0].truthy)])
            notifyActivated(object, activated: arguments[0].truthy)
            return .null
        case "setactivatednocallback":
            setActivated(object, arguments[0].truthy)
            return .null
        // For a `cfgattrib`-bound control the stored preference **is** the activation — the button
        // keeps no second copy, which is why `toggleActivation` refuses these. Answering from the
        // `activated` attribute instead reported every such button as off forever, and mmd3's whole
        // crossfade/shuffle/repeat indicator set is `alpha = 255 * getActivated()` at load.
        case "getactivated":
            if Self.configBinding(of: object) != nil { return .boolean(configValue(of: object)) }
            return .boolean(object.attributes["activated"] == "1")
        // The graph type, which is the XML tag the object was declared with (`layer`, `button`,
        // `togglebutton`, `slider`, …) — what a script comparing `strUpper(getClassName())` against
        // "LAYER" is asking for.
        case "getclassname": return .string(object.typeName)
        // A container closing itself is that window going away; anything else has no window and the
        // request stops in the graph, exactly as `hide()` does.
        case "close":
            _ = object.setAttribute("visible", value: "0")
            notifyGraphDidMutate()
            requestWindow(for: object, visible: false)
            return .null
        // Client ↔ screen conversion, relative to the receiver's **parent** client area — the space
        // `getLeft()`/`getTop()` already answer in, which is what every measured call site converts:
        // `b.clientToScreenX(b.getLeft())`, receiver and coordinate the same object. Reading it as the
        // receiver's *own* box instead double-counts that idiom, and reading it as pure identity loses
        // the parent chain, which is what put ClassicPro's tab menu at the window's left edge instead
        // of under its tab.
        //
        // "Screen" is this window's client space: a `.wal` window is borderless and positioned by us,
        // so the window origin is a constant that cancels in the round trip every caller makes, and
        // the popup presenter places `popAtXY` in the same window the point came from. Winamp Modern's
        // titlebar centres its title with `layout.clientToScreenX((w − titleW) / 2)`, converts back
        // through the titlebar group and subtracts that group's own `getLeft()`; both objects hang off
        // the layout, so the round trip returns the input and the correction lands.
        case "clienttoscreenx", "clienttoscreeny", "screentoclientx", "screentoclienty":
            let origin = resolvedGeometryRequested?(object)?.parent.origin ?? .zero
            let offset = method.hasSuffix("x") ? origin.x : origin.y
            let signed = method.hasPrefix("client") ? offset : -offset
            return .integer(Int32(clamping: Int(Double(arguments[0].integerValue) + Double(signed))))
        // Docking/snapping notifications a layout sends while resizing itself. NullPlayer places `.wal`
        // windows itself and has no docking model for them, so these are deliberate no-ops — but they
        // must *exist*, because a missing method aborts the whole handler: this trio is what stopped
        // Winamp Modern's CONFIG button from ever opening its drawer.
        case "beforeredock", "redock", "snapadjust": return .null
        case "debugstring": return .null
        // A **window's** left and top are where it sits on the desktop, not where it sits inside
        // itself. A layout resolves to the origin of its own canvas, so both answered 0 — and Big
        // Bento's playlist search reads them straight back to re-place its results popup
        // (`results.resize(results.getLeft(), results.getTop(), w, h)` after writing the screen
        // position it measured), which put the window at (0,0) and undid the placement (BB31).
        //
        // **For a `<container>` the host is asked first, and the attribute is only the fallback.** A
        // window moves by routes that never write `x`/`y` — the user dragging it, `place`, the
        // tiler, state restoration — so the attribute is the last position a *script* wrote and
        // drifts from the screen the moment anything else moves the window. Big Bento's side
        // playlist is the case that showed it: opening the panel re-places the player with
        // `resize(getLeft(), getTop(), w, h)`, read a stale 0 for a window the user had moved, and
        // threw the player into the top-left corner of the monitor (B61).
        //
        // A `<layout>` is deliberately **not** asked, and answers its own canvas origin as before.
        // Wasabi calls it a window, but here it is the space every object inside it is laid out in,
        // and skins do arithmetic across that boundary: multipass positions its drawers from
        // `layoutMainNormal.getLeft()`, and adding the desktop origin there moved every drawer and
        // its hover region off the artwork it belongs to. The read-back-and-write-it-again idiom
        // that made this look necessary is handled on the **write** instead — see
        // `applyContainerGeometry`.
        case "getleft", "getguix":
            if Self.isWindowObject(object) {
                noteWindowOriginRead(of: object)
                if object.typeName.caseInsensitiveCompare("container") == .orderedSame,
                   let origin = windowOrigin(of: object) {
                    return .integer(Int32(clamping: Int(origin.x.rounded())))
                }
                if let x = Double(object.attributes["x"] ?? "") {
                    return .integer(Int32(clamping: Int(x)))
                }
            }
            return .integer(dimension(resolvedFrame(of: object)?.minX, declared: object.geometry.x))
        case "gettop", "getguiy":
            if Self.isWindowObject(object) {
                noteWindowOriginRead(of: object)
                if object.typeName.caseInsensitiveCompare("container") == .orderedSame,
                   let origin = windowOrigin(of: object) {
                    return .integer(Int32(clamping: Int(origin.y.rounded())))
                }
                if let y = Double(object.attributes["y"] ?? "") {
                    return .integer(Int32(clamping: Int(y)))
                }
            }
            return .integer(dimension(resolvedFrame(of: object)?.minY, declared: object.geometry.y))
        case "getwidth", "getguiw":
            return .integer(dimension(resolvedFrame(of: object)?.width,
                                      declared: object.geometry.width ?? 0))
        case "getheight", "getguih":
            return .integer(dimension(resolvedFrame(of: object)?.height,
                                      declared: object.geometry.height ?? 0))
        // Both sides of this comparison must be in the *same* window's space, so the point comes from
        // the window that renders this object rather than from the global mouse hook, and the rect is
        // the object's resolved frame in that window (not the parent-relative one `getLeft` answers).
        // With no window — the headless harness — the honest answer is "no", which still lets the
        // handler run to the end instead of aborting it.
        case "ismouseoverrect":
            guard let point = mousePositionInObjectSpaceRequested?(object),
                  let frame = resolvedGeometryRequested?(object)?.frame else { return .boolean(false) }
            return .boolean(frame.contains(point))
        case "refresh":
            notifyObjectDidMutate(object)
            return .null
        // `AlbumArtLayer.isLoading()`. Only an `<AlbumArt>` has a fetch to wait on; any other
        // receiver is honestly not loading anything.
        case "isloading":
            // The XUI form (`<Wasabi:AlbumArt>`) keeps its namespace prefix in the element name.
            let type = object.typeName.lowercased().components(separatedBy: ":").last ?? ""
            guard type == "albumart" else { return .boolean(false) }
            return .boolean(host.isArtworkLoading)
        case "getposition" where WasabiFrame.isFrame(object):
            // A splitter's position is its divider offset, not a slider value. ClassicPro reads it to
            // decide whether the side view is open (`mainFrame.getPosition()==0`).
            return .integer(Int32(clamping: Int(WasabiFrame.position(of: object))))
        case "setposition" where WasabiFrame.isFrame(object):
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
            let position = String(Self.clampedSliderPosition(arguments[0].integerValue, of: target))
            guard target.attributes["value"] != position else { return .null }
            _ = target.setAttribute("value", value: position)
            notifyObjectDidMutate(target)
            // Dispatched at the control that actually moved; `embeddedXUIForwardedEvents` carries it
            // back up to the wrapper, so a script bound to either one hears it exactly once.
            _ = try dispatch(object: target, event: "onsetposition",
                             arguments: [.integer(Int32(position) ?? arguments[0].integerValue)])
            return .null
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
            return .null
        case "pause", "stop":
            // Freeze where the animation actually is, not where it started.
            _ = object.setAttribute("frame", value: String(animationFrame(of: object)))
            _ = object.setAttribute("playing", value: "0")
            notifyObjectDidMutate(object)
            return .null
        case "gotoframe", "setframe":
            _ = object.setAttribute("frame", value: String(max(0, arguments[0].integerValue)))
            _ = object.setAttribute("playing", value: "0")
            notifyObjectDidMutate(object)
            return .null
        case "getcurframe": return .integer(Int32(animationFrame(of: object)))
        case "getlength": return .integer(Int32(clamping: animationFrameCount(of: object)))
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
        case "setfocus":
            // The view owns the focus, because the keyboard is a window's property rather than the
            // graph's. It resolves the object to the `<edit>` it is or contains — a skin focuses the
            // wrapper (`Wasabi:EditBox2`) as often as the control.
            focusRequested?(embeddedControl(of: object) ?? object)
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
            return .null
        case "leftclick":
            _ = try dispatch(object: object, event: "onleftclick")
            actionRequested?(object.attributes["action"] ?? "", object.attributes["param"])
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
                actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
            }
            return .null
        case "triggeraction":
            actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
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
            // child object would be a second, rival scale for the same pixels (see `getscale`
            // below, which stays 1 for exactly that reason). A non-layout receiver is accepted and
            // inert rather than refused — refusing a method aborts the handler that called it.
            if object.typeName.caseInsensitiveCompare("layout") == .orderedSame {
                let factor = arguments[0].doubleValue
                // A skin is not allowed to drive the host off the end of the scale; the host snaps
                // the request to one of its own levels anyway, and a garbage value should not reach
                // it as one. Winamp's own range is 1…3.
                if factor.isFinite, factor > 0 {
                    uiScaleRequested?(CGFloat(min(max(factor, 0.25), 4)))
                }
            }
            return .null
        case "getscale":
            // The scene is always on the skin's own pixel grid: UI Size is applied at the view's
            // drawing/input boundary and is deliberately invisible to scripts (Phase 10), so the
            // layout's own scale is 1. ClassicPro multiplies its resize arithmetic by this.
            return .float(1)
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
        case "navigateurl":
            // A browser object may drive only its own embedded, policy-gated WebKit surface. Calls
            // on any other GUI object stay quietly inert so an untrusted skin cannot turn a generic
            // object reference into a network primitive.
            if WasabiSceneRenderer.isBrowserElement(object) {
                browserNavigationRequested?(object.stableID, arguments[0].stringValue)
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
        // Paint order is sibling order (the renderer walks `children` front to back), so raising an
        // object is moving it to the end of its parent's list.
        case "bringtofront", "bringtoback":
            guard let parent = object.parent, parent.children.count > 1 else { return .null }
            try parent.insertChild(object, at: method == "bringtofront" ? parent.children.count : 0)
            notifyGraphDidMutate()
            return .null
        case "callme": return .null
        default:
            throw unsupported(method, program: program)
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
        if Self.dispatchableEventArity[method] != nil {
            _ = try dispatch(target: MakiObjectReference(.dynamic(id)), event: method,
                             arguments: arguments)
            return method == "onaction" ? .integer(0) : .null
        }
        switch method {
        // `GammaSet.apply()` — switch to the theme this object names, through the one route
        // `System.setColorTheme` already uses. A theme the skin does not ship is refused by the
        // catalog and the call is simply inert.
        case "apply":
            guard case .gammaSet(let name) = state.role else { return .null }
            _ = themeSwitchRequested?(name)
            return .null
        case "loadmap":
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
                  state.parserCallbacks.count < Self.maximumParserCallbacks else { return .null }
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
        case "getred", "getgreen", "getblue":
            guard case .color(let red, let green, let blue) = state.role else { return .integer(0) }
            switch method {
            case "getred": return .integer(red)
            case "getgreen": return .integer(green)
            default: return .integer(blue)
            }
        case "getwidth", "getheight":
            // The map's own size, which for a sliced `<bitmap>` is the slice's, not the sheet's —
            // same reason as `mapCrop`. The path form has no definition and stays the whole file,
            // which is what ClassicPro's two width probes (`read.suiframe.png`, `installed.png`) ask.
            guard case .map(let bitmapID, let source) = state.role,
                  let image = mapImage(bitmapID: bitmapID, source: source) else { return .integer(0) }
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
        case "setdelay":
            state.delayMilliseconds = max(8, arguments[0].integerValue)
            dynamicObjects[id] = state
            return .null
        case "start":
            let reference = MakiObjectReference(.dynamic(id))
            if MakiInterpreter.tracesExecution {
                print("MAKI timer start id=\(id) delay=\(state.delayMilliseconds) "
                      + "by=\(MakiInterpreter.traceStack.last ?? "-")")
            }
            _ = try timers.schedule(id: id, period: TimeInterval(state.delayMilliseconds) / 1_000) { [weak self] in
                guard let self else { return }
                _ = try? self.dispatch(target: reference, event: "ontimer", arguments: [])
            }
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
        case "getdata":
            guard case .configAttribute(let section, let key) = state.role else { return .string("") }
            let data = loadedSkin.configuration.string(section: section, key: key)
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
            case .generic: return .string("dynamic_\(id)")
            }
        case "init", "callme": return .null
        default:
            if let value = classicProFileMethod(method, arguments: arguments) { return value }
            throw unsupported(method, program: program)
        }
    }

    /// The control a `<groupdef embed_xui="…">` wrapper speaks for.
    ///
    /// The wrapper **is** that control, so its value has to be one number and not two. Big Bento
    /// Modern's scrollbar is the case that proves it: `cscrollbar.maki` moves the *inner* `<slider>`
    /// from the up/down buttons, while the settings page reads `vscroll.getPosition()` on the
    /// **wrapper**. Kept apart, the two drifted permanently — the page read 0 however far the bar had
    /// been moved, and opened every settings page scrolled to its own bottom (BB19).
    func embeddedControl(of object: WasabiObject) -> WasabiObject? {
        guard let id = object.attributes["nullplayer.embedxui"] else { return nil }
        return descendant(of: object, xmlID: id)
    }

    func descendant(of root: WasabiObject, xmlID: String) -> WasabiObject? {
        if root.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return root }
        for child in root.children {
            if let match = descendant(of: child, xmlID: xmlID) { return match }
        }
        return nil
    }

    /// Whether `getLayout` may hand this layout back to `program`.
    ///
    /// A script that **lives inside a layout** is asking from inside one window state, and Winamp
    /// builds a container's layouts on demand, so from there the layouts that are not on screen do
    /// not exist yet. We build them all up front, which breaks a script written against that: Big
    /// Bento Modern wires its volume, mute, play/pause animation and display with
    ///
    /// ```maki
    /// if (normal) { vol = normal.findObject("vol.on"); ... }
    /// if (shade)  { vol = shade.findObject("vol.on");  ... }
    /// ```
    ///
    /// — two blocks over **the same variables**, meant to be mutually exclusive. Both ran and the
    /// second won, so 89 of the skin's bindings pointed into `layout#shade`; 57 of those belong to
    /// the layout on screen, and the visible player had no working volume control at all.
    ///
    /// Narrow on purpose. A script with **no layout scope** — a skin-level `<scripts>` block — is
    /// unaffected, because such a script is often the only place a skin wires its *other* layouts
    /// from: multipass's `skin.xml` wires normal and shade together, from one program, into separate
    /// variables. Gating it too cost 236 (event, object) pairs across the corpus's shade and stick
    /// layouts to buy nothing. A layout already shown once also still answers, so a script that
    /// reaches across after the user has been there keeps working.
    func isLayoutCreated(_ layout: WasabiObject, askedBy program: MakiProgram) -> Bool {
        let owner = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:))
        return Self.layoutIsCreated(layout,
                                    forScriptIn: owner.flatMap { ancestor(of: $0, type: "layout") },
                                    realized: realizedLayouts)
    }

    /// The rule itself, as a pure function of the two layouts and the realized set — so it can be
    /// asserted against a real object graph without a compiled MAKI program to carry it.
    static func layoutIsCreated(_ layout: WasabiObject,
                                forScriptIn ownLayout: WasabiObject?,
                                realized: Set<WasabiObjectID>) -> Bool {
        guard let ownLayout else { return true }
        return ownLayout === layout || realized.contains(layout.stableID)
    }

    func ancestor(of object: WasabiObject, type: String) -> WasabiObject? {
        var candidate: WasabiObject? = object
        while let current = candidate {
            if current.typeName.caseInsensitiveCompare(type) == .orderedSame { return current }
            candidate = current.parent
        }
        return nil
    }

    /// An object's box in its **parent's** coordinates — the space Wasabi's `getGuiX`/`getGuiY` and
    /// `getLeft`/`getTop` report in — or `nil` when no scene can place it.
    ///
    /// Reading the raw `x`/`y`/`w`/`h` attributes instead is only right for absolute geometry, and
    /// Bento-style skins barely use any: cPro's tab strip is `w="-4" relatw="1"`, so `getWidth()`
    /// answered **−4**, `CproTabs.m` concluded it had no room for its tabs, switched to short names and
    /// squeezed every tab to the 20px floor. The declared value stays as the fallback for an object the
    /// active scene does not contain (a hidden layout, or a runtime with no window wired at all).
    func resolvedFrame(of object: WasabiObject) -> CGRect? {
        guard let geometry = resolvedGeometryRequested?(object) else { return nil }
        return geometry.frame.offsetBy(dx: -geometry.parent.minX, dy: -geometry.parent.minY)
    }

    /// Wasabi's `<GroupList>` is a **vertical stack**: each instance spans the list's width and sits
    /// below the ones already in it. Two things follow, and both have to be stamped onto the child
    /// here because a groupdef carries neither.
    ///
    /// *Width.* The part groupdefs declare `h=` and no `w=` at all, so a child left at its markup
    /// geometry is zero-width and draws nothing — its own contents are relative to it
    /// (`w="-203" relatw="1"`), which is a negative box, not a small one.
    ///
    /// *Top.* Both parts would otherwise land at `y=0` and cover each other. The offset is the sum of
    /// the heights the earlier siblings declare, which is the number the author writes the groupdef's
    /// `h=` for (Big Bento's pages are 223+220, 243+251, …) — and the same number the page's
    /// scrollbar script compares its `param`'s third token against to decide whether to show itself.
    ///
    /// Anything that is not a `GroupList` keeps whatever geometry it was instantiated with.
    func stackInGroupList(_ child: WasabiObject, list: WasabiObject) {
        guard list.typeName.caseInsensitiveCompare("grouplist") == .orderedSame else { return }
        var top = 0.0
        for sibling in list.children where sibling !== child { top += stackedHeight(of: sibling) }
        _ = child.setAttribute("x", value: "0")
        _ = child.setAttribute("relatx", value: "0")
        _ = child.setAttribute("y", value: String(Int(top.rounded())))
        _ = child.setAttribute("relaty", value: "0")
        _ = child.setAttribute("w", value: "0")
        _ = child.setAttribute("relatw", value: "1")
    }

    /// The vertical room one list entry takes. The declared `h=` is the authority — the entries are
    /// stacked before any layout pass has run, so a resolved frame exists for at most the ones
    /// already on screen, and mixing the two units would stack the second entry against the first
    /// one's *scene* height rather than the height the author sized the list around.
    func stackedHeight(of object: WasabiObject) -> Double {
        max(0, Double(object.attributes["h"] ?? "") ?? 0)
    }

    /// A resolved coordinate when the scene could supply one, and the markup's own value otherwise.
    func dimension(_ resolved: CGFloat?, declared: Double) -> Int32 {
        Int32(clamping: Int(resolved.map(Double.init) ?? declared))
    }

    func object(_ value: MakiValue, equals reference: MakiObjectReference) -> Bool {
        guard case .object(let candidate) = value else { return false }
        return candidate == reference
    }
}
