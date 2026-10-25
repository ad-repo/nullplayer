import AppKit
import CoreGraphics
import Foundation

/// The MAKI `GuiObject` receiver: the surface every Group, Layer and Layout answers. The
/// window-level methods are in `…RuntimeWindow.swift` and the objects a script makes for itself
/// with `new` in `…RuntimeDynamic.swift`. Split out of `WinampModernScriptRuntime.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    func invokeGUI(method: String, object: WasabiObject, arguments: [MakiValue],
                           program: MakiProgram) throws -> MakiValue {
        if method == "showcurrentlyplayingentry" {
            let index = playlistSnapshot.currentIndex
            if index >= 0 { hooks.playlistRevealRowRequested?(index) }
            return .null
        }
        if WinampModernScriptSignatures.dispatchableEventArity[method] != nil {
            _ = try dispatch(object: object, event: method, arguments: arguments)
            // No handler can answer through this path (the interpreter's return value belongs to the
            // handler's own frame), so `onAction` reports the neutral slot 0 rather than a fiction.
            return method == "onaction" ? .integer(0) : .null
        }
        if let value = try invokeWidget(method: method, object: object, arguments: arguments) { return value }
        // One family at a time, in the order the methods were matched when they were one switch, so a
        // name two families both answer (a `where` on one of them) resolves as it always did.
        if let value = try invokeGUIStructure(method: method, object: object, arguments: arguments, program: program)
            ?? invokeGUIText(method: method, object: object, arguments: arguments, program: program)
            ?? invokeGUIState(method: method, object: object, arguments: arguments, program: program)
            ?? invokeGUIPosition(method: method, object: object, arguments: arguments, program: program)
            ?? invokeGUIAnimation(method: method, object: object, arguments: arguments, program: program)
            ?? invokeGUIList(method: method, object: object, arguments: arguments, program: program)
            ?? invokeGUIActions(method: method, object: object, arguments: arguments, program: program)
            ?? invokeWindowGUI(method: method, object: object, arguments: arguments) { return value }
        throw unsupported(method, program: program)
    }

    /// The object tree and its layouts, and the markup a script reads and writes.
    func invokeGUIStructure(method: String, object: WasabiObject, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue? {
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
                $0.tag.is(.layout) &&
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
            guard let root = ancestor(of: object, type: .container) else { return .null }
            return objectValue(descendant(of: root, xmlID: wanted))
        case "getcontainer": return objectValue(ancestor(of: object, type: .container))
        // A container the skin *declared* is static; one a script asked `newDynamicContainer` for is
        // dynamic, and Wasabi marks the declaration itself `dynamic="1"` for the ones meant to be
        // instantiated that way. Ebonite's standard frame branches on it —
        // `if (!comp_layout.getContainer().isDynamic()) system.onScriptLoaded();` — to rebuild the
        // frame overlay it closed on the last hide, and until this answered, the unsupported call
        // aborted the whole `onSetVisible` handler before `frame_layout.show()` (B110).
        case "isdynamic": return .boolean(object.attributes["dynamic"] == "1")
        case "getcurlayout":
            return objectValue(activeLayoutByContainer[object.stableID].flatMap(loadedSkin.runtime.graph.object(withID:)))
        case "switchtolayout":
            guard object.tag.is(.container),
                  let next = object.children.first(where: {
                      $0.tag.is(.layout) &&
                      $0.xmlID?.caseInsensitiveCompare(arguments[0].stringValue) == .orderedSame
                  }) else { return .null }
            activeLayoutByContainer[object.stableID] = next.stableID
            realizedLayouts.insert(next.stableID)
            _ = hooks.layoutSwitchRequested?(object.stableID, arguments[0].stringValue)
            _ = try dispatch(object: object, event: "onswitchtolayout", arguments: [objectValue(next)])
            return .null
        // `<script>` never enters the graph, so `children` is exactly the group's GUI objects in
        // declaration order — the index ClassicPro's InfoViewer relies on (`a==11` is its rating).
        case "getnumchildren", "getnumobjects": return .integer(Int32(clamping: object.children.count))
        case "enumchildren", "enumobject":
            let index = Int(arguments[0].integerValue)
            guard object.children.indices.contains(index) else { return .null }
            return objectValue(object.children[index])
        // `GroupList.instantiate(groupdef, count)` — the *list's* own expansion, as against
        // `System.newGroup`. Big Bento Modern builds all nine of its config pages and the SUI's
        // equalizer tab this way: the page's XML holds an empty `<GroupList>` and a scrollbar, and
        // every option on it lives in a `…part1` / `…part2` groupdef the script expands here. That
        // is why the whole family reported `unsupported` although it drew.
        case "instantiate":
            let identifier = arguments[0].stringValue
            // The count is skin input, so it is bounded here as well as by the shared object budget
            // `instantiateGroupAtRuntime` counts against. Nothing measured asks for more than one.
            let count = min(max(Int(arguments[1].integerValue), 0), Self.maximumGroupListInstances)
            var instantiated: WasabiObject?
            for _ in 0..<count {
                guard let child = try instantiateOrNull(identifier, object, program: program) else { break }
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
        case "getparentlayout": return objectValue(ancestor(of: object, type: .layout))
        case "getxmlparam": return .string(object.xmlParam(arguments[0].stringValue) ?? "")
        case "setxmlparam":
            let key = arguments[0].stringValue
            let value = arguments[1].stringValue
            object.forgetDeclaredXMLParam(key)
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
            // The one unregistered value that does load: a cover beside the playing file, which
            // draws the host's artwork (`WinampModernTrackFolderImage`).
            guard !Self.imageKeys.contains(key.lowercased()) || resolvesToResource(value)
                    || host.isTrackFolderImage(value)
            else { return .null }
            if Self.imageKeys.contains(key.lowercased()) { noteCoverRequest(value, by: program) }
            if Self.geometryKeys.contains(key.lowercased()) {
                // A container or a layout is a *window*: its box is not read back out of the graph at
                // the next repaint, it has to be pushed to AppKit. `resize()` already did this; the
                // same four attributes written one at a time did not, which is how Big Bento's search
                // results came out at the container's declared 275×116 in the corner of the screen
                // instead of under the search box it measured itself against (BB31).
                let borrowed: WinampModernBorrowedOrigin.Request?
                switch (key.lowercased(), Double(value)) {
                case ("x", let x?): borrowed = borrowedWindowOrigin(x: x, y: nil, writtenOn: object)
                case ("y", let y?): borrowed = borrowedWindowOrigin(x: nil, y: y, writtenOn: object)
                default: borrowed = nil
                }
                writeGeometry([(key, value)], on: object, borrowed: borrowed)
            } else {
                _ = object.setAttribute(key, value: value)
                // A layout that computes its own resize floor has said what the protective minimum
                // can only guess at (B125: ClassicPro engine two writes `minimum_h` =
                // titlebar+info+playback from `fullScreen(false)`, and our inferred floor was three
                // times it).
                if object.tag.is(.layout),
                   ["minimum_w", "minimum_h"].contains(key.lowercased()) {
                    object.noteScriptAuthoredMinimum(key)
                }
                notifyObjectDidMutate(object)
            }
            deliverRuntimeXUIParam(key, value: value, to: object)
            applyCustomObjectGroup(key, value: value, to: object)
            return .null
        default: return nil
        }
    }

    /// A text object's content and measurement.
    func invokeGUIText(method: String, object: WasabiObject, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue? {
        switch method {
        case "settext":
            // Through the `embed_xui` link, exactly as `setPosition`/`getPosition` are: the wrapper
            // **is** the control and its text must not exist in two places. Big Bento's file-info
            // lines are the case that proves it — `<groupdef id="bento.infodisplay.line"
            // embed_xui="text" xuitag="Bento:InfoLine">` — where `fileinfo.maki` fills the inner
            // `<Text id="text">` while `fileinfo_lyrics_finder.maki` reads the *wrapper* with
            // `getText()` to build its search. Kept apart, the reader answered "" and the lyrics
            // button searched the web for the bare word "lyrics" (B40).
            let object = embeddedControl(of: object) ?? object
            let contentBeforeWrite = WasabiTextMetrics.content(of: object, host: host)
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
            // Winamp raises `onTextChanged` from inside `setText`, and a skin may have no other
            // signal that the string moved. ClassicPro's file-info drawer is the measured case: every
            // row is a `<Text id="label">` beside a `<Text id="text">`, both declared at x=0, and
            // `infoline.maki` shifts the value clear of the label from `label.onTextChanged` alone —
            // where the label's own text arrives as an XUI param, i.e. through this method. Without
            // the dispatch the handler never ran and every row drew its value on top of its label
            // (B141). Only on an actual change, as Wasabi does, and never re-entrantly: a handler is
            // free to answer with another `setText` on the same object.
            let contentAfterWrite = WasabiTextMetrics.content(of: object, host: host)
            if contentAfterWrite != contentBeforeWrite, !textChangeInFlight.contains(object.stableID) {
                textChangeInFlight.insert(object.stableID)
                defer { textChangeInFlight.remove(object.stableID) }
                // The bound-text poll keys off the same content, so record it here too or the next
                // tick reports the script's own write as a host-side change and fires a second time.
                lastDispatchedText[object.stableID] = contentAfterWrite
                _ = try? dispatch(object: object, event: "ontextchanged",
                                  arguments: [.string(contentAfterWrite)])
            }
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
        default: return nil
        }
    }

    /// Visibility, alpha, activation, the box an object answers and the pointer over it.
    func invokeGUIState(method: String, object: WasabiObject, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue? {
        switch method {
        case "resize":
            let borrowed = borrowedWindowOrigin(x: Double(arguments[0].integerValue),
                                                y: Double(arguments[1].integerValue), writtenOn: object)
            writeGeometry(Array(zip(["x", "y", "w", "h"], arguments.map { String($0.integerValue) })),
                          on: object, borrowed: borrowed)
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
            if object.tag.is(.container),
               let id = object.xmlID {
                containerAlphaChanged?(id, CGFloat(clamped) / 255.0)
            }
            return .null
        case "getalpha": return .integer(Int32(object.attributes["alpha"] ?? "255") ?? 255)
        case "setenabled":
            _ = object.setAttribute("enabled", value: arguments[0].truthy ? "1" : "0")
            notifyObjectDidMutate(object)
            return .null
        // Wasabi notifies from `setActivated` only when the activation actually **changes**. An
        // unchanged write is silent, and that is what lets a skin call it from inside the very event
        // its `onToggle` would answer. Itemskin is the measured case and the reason this guard
        // exists: its `onVolumeChanged` deactivates the mute and ATT buttons on every volume change,
        // and each of their `onToggle` handlers answers a *false* with `setVolume(savedVolume)` — a
        // variable that is 0 until a real mute fills it in. Dispatching unconditionally drove the
        // volume to zero at load, `setVolume` re-raised `onVolumeChanged`, and the zero was then
        // persisted: the app came up silent on that skin, the slider could not lift it, and no other
        // skin in the corpus binds `onToggle` to the volume. `setActivatedNoCallback` remains the
        // deliberate silent write for a state that *did* move.
        // A `<Wasabi:CheckBox>` is a togglebutton (`WasabiFormWidgets`), so its checked state is its
        // activation: fifty skins set it in `onScriptLoaded` (B192).
        // A changed write raises `onActivate` but not `onToggle`, which is the click's event: Moon
        // Groove's `EqPage.onToggle` drew its EQ page over the LCD from a load-time restore (B255).
        // An `embed_xui` wrapper's activation is its button's: ClassicPro's `closeTab` deactivates
        // every `cpro.tab` *group*, and kept on the group every tab ever clicked stayed lit.
        case "setactivated", "setchecked":
            let object = embeddedControl(of: object) ?? object
            let wanted = arguments[0].truthy
            let activationChanged = (object.attributes["activated"] == "1") != wanted
            setActivated(object, wanted)
            if activationChanged { notifyActivated(object, activated: wanted) }
            return .null
        case "setactivatednocallback":
            setActivated(embeddedControl(of: object) ?? object, arguments[0].truthy)
            return .null
        // For a `cfgattrib`-bound control the stored preference **is** the activation — the button
        // keeps no second copy, which is why `toggleActivation` refuses these. Answering from the
        // `activated` attribute instead reported every such button as off forever, and mmd3's whole
        // crossfade/shuffle/repeat indicator set is `alpha = 255 * getActivated()` at load.
        case "getactivated", "ischecked":
            let object = embeddedControl(of: object) ?? object
            if Self.configBinding(of: object) != nil { return .boolean(configValue(of: object)) }
            if let on = equalizerSwitchState(of: object) { return .boolean(on) }
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
        //
        // **`getGui*` on a relative axis answers the markup, not the resolved box.** Wasabi's
        // `getGuiX/Y/W/H` are the object's own `x`/`y`/`w`/`h` parameters, with `relat*` beside
        // them, so the stock `centerobject.m` — read `getGuiY()`, write it back as `y` — leaves a
        // `y="-83" relaty="1"` group where it is. Answered with the resolved 1086, the write-back
        // added the layout's height on every resize and 1010 Fullscreen's transport left the canvas.
        case "getleft", "getguix":
            if method == "getguix", let markup = Self.relativeMarkup(of: object, axis: "x") { return .integer(markup) }
            return .integer(Int32(clamping: Int(scriptReadsOrigin(of: object).x)))
        case "gettop", "getguiy":
            if method == "getguiy", let markup = Self.relativeMarkup(of: object, axis: "y") { return .integer(markup) }
            return .integer(Int32(clamping: Int(scriptReadsOrigin(of: object).y)))
        case "getwidth", "getguiw":
            if method == "getguiw", let markup = Self.relativeMarkup(of: object, axis: "w") { return .integer(markup) }
            return .integer(dimension(resolvedFrame(of: object)?.width,
                                      declared: declaredFrame(of: object).width))
        case "getheight", "getguih":
            if method == "getguih", let markup = Self.relativeMarkup(of: object, axis: "h") { return .integer(markup) }
            return .integer(dimension(resolvedFrame(of: object)?.height,
                                      declared: declaredFrame(of: object).height))
        // Both sides of this comparison must be in the *same* window's space, so the point comes from
        // the window that renders this object rather than from the global mouse hook, and the rect is
        // the object's resolved frame in that window (not the parent-relative one `getLeft` answers).
        // With no window — the headless harness — the honest answer is "no", which still lets the
        // handler run to the end instead of aborting it.
        case "ismouseoverrect":
            guard let point = hooks.mousePositionInObjectSpaceRequested?(object),
                  let frame = hooks.resolvedGeometryRequested?(object)?.frame else { return .boolean(false) }
            return .boolean(frame.contains(point))
        // The point arrives in the object's parent space, the space its pointer events carry
        // (Core-X5 asks this in every main-window button's handler, B206).
        // ponytail: the frame only, not the object's region; add the region test when a skin needs it.
        case "ismouseover":
            let point = CGPoint(x: Int(arguments[0].integerValue), y: Int(arguments[1].integerValue))
            return .boolean(resolvedFrame(of: object)?.contains(point) ?? false)
        case "refresh":
            notifyObjectDidMutate(object)
            return .null
        // `AlbumArtLayer.isLoading()`. Only an `<AlbumArt>` has a fetch to wait on; any other
        // receiver is honestly not loading anything.
        case "isloading":
            // The XUI form (`<Wasabi:AlbumArt>`) keeps its namespace prefix in the element name.
            guard object.tag.isStandard(.albumArt) else { return .boolean(false) }
            return .boolean(host.isArtworkLoading)
        default: return nil
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
        guard let id = WasabiEmbeddedXUI.embeddedTag(of: object) else { return nil }
        return descendant(of: object, xmlID: id)
    }

    /// The named object in `root`'s subtree — **the first one that came up**.
    ///
    /// Ids are supposed to be unique inside a window and routinely are not: 304 duplicate ids inside
    /// one group/layout across the corpus, most of them harmless because nothing looks them up. The
    /// ones that matter are the copy-paste leftovers a skin never removed, and those are usually dead
    /// in exactly the way Wasabi itself names — `isInvalid()`, an object whose bitmap the skin never
    /// declared, so it has no size, cannot draw and cannot be clicked. T800 carries one: a second
    /// `id="Pause"` parked at x=803 (its layout is 177 wide) on the undeclared `player.main.pause`.
    /// `play2pause.maki` asks the group for "Pause", got that corpse, and hid and showed it for the
    /// rest of the session — while the *real* Pause, sitting on the jaw at the exact rect of the Play
    /// button and declared after it, was never hidden and took every click topmost-wins gave it. The
    /// play button on the jaw could not be pressed at all: pressing it sent `pause`.
    ///
    /// So a match that came up outranks a match that did not, and declaration order decides
    /// everything else. An object with no `image`/`bitmap` of its own is never invalid, so groups,
    /// text and containers are unaffected; a skin with two live duplicates still gets the first, the
    /// way it did before.
    func descendant(of root: WasabiObject, xmlID: String) -> WasabiObject? {
        var deadMatch: WasabiObject?
        func walk(_ node: WasabiObject) -> WasabiObject? {
            if node.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame {
                if !isInvalid(node) { return node }
                if deadMatch == nil { deadMatch = node }
            }
            for child in node.children {
                if let match = walk(child) { return match }
            }
            return nil
        }
        return walk(root) ?? deadMatch
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
                                    forScriptIn: owner.flatMap { ancestor(of: $0, type: .layout) },
                                    realized: realizedLayouts)
    }

    /// The rule itself, as a pure function of the two layouts and the realized set — so it can be
    /// asserted against a real object graph without a compiled MAKI program to carry it.
    ///
    /// Narrow on the *container* too. The gate models one window's mutually exclusive states, so it
    /// only has standing over the layouts of the window the script is in. Anaheim Player 01 asks
    /// across: `BodyColor.maki` lives in `group#Page2<layout#normal<container#skin_options` and wires
    /// **main**'s `normal` and `mini` bodies together, one `setXMLParam("image", …)` each, so that the
    /// player's body colour and the mini window's match. Gated against `main/mini` — a layout the user
    /// has not visited yet — `getLayout("mini")` answered NULL, the mini assignment went nowhere, and
    /// the mini window stayed on `MiniBody1` (white) however the main window was recoloured. Nothing
    /// in the Big Bento shape needs the cross-container half: both of its blocks name its own window.
    static func layoutIsCreated(_ layout: WasabiObject,
                                forScriptIn ownLayout: WasabiObject?,
                                realized: Set<WasabiObjectID>) -> Bool {
        guard let ownLayout else { return true }
        if ownLayout === layout || realized.contains(layout.stableID) { return true }
        guard let ownContainer = container(of: ownLayout),
              let askedContainer = container(of: layout) else { return true }
        return ownContainer !== askedContainer
    }

    private static func container(of object: WasabiObject) -> WasabiObject? {
        var candidate: WasabiObject? = object
        while let current = candidate {
            if current.tag.is(.container) { return current }
            candidate = current.parent
        }
        return nil
    }

    func ancestor(of object: WasabiObject, type: WasabiKind) -> WasabiObject? {
        var candidate: WasabiObject? = object
        while let current = candidate {
            if current.tag.is(type) { return current }
            candidate = current.parent
        }
        return nil
    }

    static let maximumPendingCalls = 256
    static let snapAdjustEdges = ["left", "top", "right", "bottom"]

    /// Where a script's `snapAdjust()` stores a layout's snap margin on `edge`.
    static func snapAdjustKey(_ edge: some StringProtocol) -> String { "nullplayer.snapadjust." + edge }

    /// A layout's snap margin on `edge` (`left`/`top`/`right`/`bottom`): what a script's
    /// `snapAdjust()` stored, else the markup's `snapadjust<edge>`.
    static func snapAdjust(_ edge: String, of layout: WasabiObject) -> Double {
        Double(layout.attributes[snapAdjustKey(edge)] ?? layout.attributes["snapadjust" + edge] ?? "") ?? 0
    }

    func object(_ value: MakiValue, equals reference: MakiObjectReference) -> Bool {
        guard case .object(let candidate) = value else { return false }
        if case .dynamic(let id) = candidate.kind, let objectID = dynamicGUIObjects[id] {
            return reference == MakiObjectReference(.gui(objectID)) || candidate == reference
        }
        return candidate == reference
    }
}
