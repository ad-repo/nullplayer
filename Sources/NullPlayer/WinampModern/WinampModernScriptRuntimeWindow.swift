import AppKit
import CoreGraphics
import Foundation

/// The `GuiObject` methods that act on a window or on paint order rather than on one control's
/// content: client/screen conversion, snapping, centring, layout enumeration, stacking, and the
/// edit, tab-sheet and vis modes a window's script switches. Split out of
/// `WinampModernScriptRuntimeObject.swift`, whose `invokeGUI` asks this after its own switch; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    /// `method` on `object`, or nil when it is not one of these.
    func invokeWindowGUI(method: String, object: WasabiObject, arguments: [MakiValue]) throws -> MakiValue? {
        switch method {
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
            let origin = hooks.resolvedGeometryRequested?(object)?.parent.origin ?? .zero
            let offset = method.hasSuffix("x") ? origin.x : origin.y
            let signed = method.hasPrefix("client") ? offset : -offset
            return .integer(Int32(clamping: Int(Double(arguments[0].integerValue) + Double(signed))))
        // Docking/snapping notifications a layout sends while resizing itself. NullPlayer places `.wal`
        // windows itself and has no docking model for them, so these are deliberate no-ops — but they
        // must *exist*, because a missing method aborts the whole handler: this trio is what stopped
        // Winamp Modern's CONFIG button from ever opening its drawer.
        case "beforeredock", "redock": return .null
        // The layout's snap margins: stored so `getSnapAdjust*` read them back (winampmodern566
        // sizes its drawer from `getSnapAdjustBottom`), not obeyed, since there is no docking model.
        case "snapadjust":
            for (edge, value) in zip(Self.snapAdjustEdges, arguments) {
                _ = object.setAttribute(Self.snapAdjustKey(edge), value: String(value.integerValue))
            }
            return .null
        case "getsnapadjustleft", "getsnapadjusttop", "getsnapadjustright", "getsnapadjustbottom":
            let key = Self.snapAdjustKey(method.dropFirst("getsnapadjust".count))
            return .integer(Int32(object.attributes[key] ?? "") ?? 0)
        // A width or height is the same in client and screen space: neither is scaled here.
        case "clienttoscreenw", "clienttoscreenh", "screentoclientw", "screentoclienth":
            return .integer(arguments[0].integerValue)
        // `Layout.center()` — the window centred on the display the viewport methods answer for
        // (1010 Fullscreen's frame windows, B201), through the same write as `resize`.
        case "center" where object.tag.is(.layout):
            let screen = NSScreen.main?.frame.size ?? .zero
            let width = dimension(resolvedFrame(of: object)?.width, declared: declaredFrame(of: object).width)
            let height = dimension(resolvedFrame(of: object)?.height, declared: declaredFrame(of: object).height)
            writeGeometry([("x", String((Int32(screen.width) - width) / 2)),
                           ("y", String((Int32(screen.height) - height) / 2))], on: object, borrowed: nil)
            return .null
        // The hosted surface's name, as the thinger titles it. cPro labels its drawer tab with it
        // from a timer that aborted on every tick (`refreshAIOTab`, `checkVisName`, B193).
        case "getcomponentname":
            let kind = WasabiSceneRenderer.componentKind(of: object)
            return .string(WinampModernComponentBucketCatalog.icons.first { $0.kind == kind }?.title ?? "")
        // The Bio-Nid lineage switches its playlist sidecar's page from script (B198).
        case "getcurpage" where WasabiTabSheet.isTabSheet(object):
            return .integer(Int32(WasabiTabSheet.selectedIndex(of: object)))
        case "setcurpage" where WasabiTabSheet.isTabSheet(object):
            if WasabiTabSheet.select(index: Int(arguments[0].integerValue), on: object) { notifyGraphDidMutate() }
            return .null
        // `Edit`: auto-enter makes every change an enter (the view reads the flag), and `enter()`
        // is the script pressing Return (B189).
        case "setautoenter":
            _ = object.setAttribute("autoenter", value: arguments[0].truthy ? "1" : "0")
            return .null
        case "getautoenter": return .integer(object.attributes["autoenter"] == "1" ? 1 : 0)
        case "enter":
            _ = try dispatch(object: object, event: "onenter")
            return .null
        // `Vis.getMode()`: what `setMode` and a click on the vis last wrote (Styx's `vis.m`, B190).
        case "getmode":
            return .integer(Int32(WasabiVisualizationMode(attribute: object.attributes["mode"]).attributeValue) ?? 1)
        // Paint order is sibling order (the renderer walks `children` front to back), so raising an
        // object is moving it to the end of its parent's list.
        case "bringtofront", "bringtoback":
            guard let parent = object.parent, parent.children.count > 1 else { return .null }
            try parent.insertChild(object, at: method == "bringtofront" ? parent.children.count : 0)
            notifyGraphDidMutate()
            return .null
        // Paint order relative to a sibling: just under it, or just over it.
        case "bringbelow", "bringabove":
            guard case .object(let reference) = arguments[0], case .gui(let otherID) = reference.kind,
                  let other = loadedSkin.runtime.graph.object(withID: otherID), other !== object,
                  let parent = object.parent, other.parent === parent else { return .null }
            // `insertChild` takes the object out first, so the index is among the others.
            guard let index = parent.children.filter({ $0 !== object })
                .firstIndex(where: { $0 === other }) else { return .null }
            try parent.insertChild(object, at: method == "bringbelow" ? index : index + 1)
            notifyGraphDidMutate()
            return .null
        case "islayout": return .boolean(object.tag.is(.layout))
        case "getnumlayouts":
            return .integer(Int32(object.children.filter { $0.tag.is(.layout) }.count))
        case "enumlayout":
            let layouts = object.children.filter { $0.tag.is(.layout) }
            let index = Int(arguments[0].integerValue)
            return layouts.indices.contains(index) ? objectValue(layouts[index]) : .null
        // The window's name, as the Windows menu lists it (Anunaki renames its own).
        case "setname":
            _ = object.setAttribute("name", value: arguments[0].stringValue)
            notifyGraphDidMutate()
            return .null
        case "setdesktopalpha":
            _ = object.setAttribute("desktopalpha", value: arguments[0].truthy ? "1" : "0")
            notifyObjectDidMutate(object)
            return .null
        case "getdesktopalpha": return .boolean(object.attributes["desktopalpha"] == "1")
        // `Button.rightClick()` is the script pressing the button's right side: its handler runs.
        case "rightclick":
            _ = try dispatch(object: object, event: "onrightclick")
            return .null
        // `Slider.lock()` holds back the slider's own callbacks while a script moves it.
        case "lock", "unlock":
            _ = object.setAttribute("nullplayer.slider.locked", value: method == "lock" ? "1" : "0")
            return .null
        case "nextmode":
            let mode = WasabiVisualizationMode(attribute: object.attributes["mode"]).stepped(by: 1)
            _ = object.setAttribute("mode", value: mode.attributeValue)
            notifyObjectDidMutate(object)
            return .null
        // Whether the vis or animation draws every frame; ours always does.
        case "setrealtime": return .null
        default: return nil
        }
    }
}
