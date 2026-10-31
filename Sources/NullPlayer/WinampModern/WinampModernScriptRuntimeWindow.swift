import AppKit
import CoreGraphics
import Foundation

/// The `GuiObject` methods that act on a window or on paint order rather than on one control's
/// content: client/screen conversion, snapping, centring, layout enumeration, stacking, and the
/// edit, tab-sheet and vis modes a window's script switches. Split out of
/// `WinampModernScriptRuntimeObject.swift`, whose `invokeGUI` asks this table last; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
}

extension WinampModernScriptRuntime {
    /// The window-level methods the header names.
    static let guiWindowMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
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
        table.add(["clienttoscreenx", "clienttoscreeny", "screentoclientx", "screentoclienty"], 1) { runtime, call in
            let origin = WasabiSceneRenderer.coordinateSpace(of: call.object) {
                runtime.hooks.resolvedGeometryRequested?($0)?.frame
            }?.origin ?? runtime.hooks.resolvedGeometryRequested?(call.object)?.parent.origin ?? .zero
            let offset = call.method.hasSuffix("x") ? origin.x : origin.y
            let signed = call.method.hasPrefix("client") ? offset : -offset
            return .integer(Int32(clamping: Int(Double(call.arguments[0].integerValue) + Double(signed))))
        }
        // Window-manager notifications around a layout resize. Arities read out of the bytecode
        // rather than guessed (`WINAMP_MODERN_RENDER_DISASM`): each is called on the layout, and
        // counting the net pushes between receiver and call gives `beforeRedock()` /
        // `snapAdjust(x, y, w, h)`. Guessing here is not an option — a wrong count desynchronises
        // the interpreter's stack.
        // Docking/snapping notifications a layout sends while resizing itself. NullPlayer places `.wal`
        // windows itself and has no docking model for them, so these are deliberate no-ops — but they
        // must *exist*, because a missing method aborts the whole handler: this trio is what stopped
        // Winamp Modern's CONFIG button from ever opening its drawer.
        table.add(["beforeredock", "redock"], 0) { runtime, call in .null }
        // The layout's snap margins: stored so `getSnapAdjust*` read them back (winampmodern566
        // sizes its drawer from `getSnapAdjustBottom`), not obeyed, since there is no docking model.
        table.add("snapadjust", 4) { runtime, call in
            for (edge, value) in zip(WinampModernScriptRuntime.snapAdjustEdges, call.arguments) {
                _ = call.object.setAttribute(WinampModernScriptRuntime.snapAdjustKey(edge),
                                             value: String(value.integerValue))
            }
            return .null
        }
        table.add(["getsnapadjustleft", "getsnapadjusttop", "getsnapadjustright", "getsnapadjustbottom"], 0) { runtime, call in
            let key = WinampModernScriptRuntime.snapAdjustKey(call.method.dropFirst("getsnapadjust".count))
            return .integer(Int32(call.object.attributes[key] ?? "") ?? 0)
        }
        // A width or height is the same in client and screen space: neither is scaled here.
        table.add(["clienttoscreenw", "clienttoscreenh", "screentoclientw", "screentoclienth"], 1) { runtime, call in
            .integer(call.arguments[0].integerValue)
        }
        // `Layout.center()` — the window centred on the display the viewport methods answer for
        // (1010 Fullscreen's frame windows, B201), through the same write as `resize`.
        table.add("center", 0) { runtime, call in
            if call.object.tag.is(.layout) {
                let screen = NSScreen.main?.frame.size ?? .zero
                let width = runtime.dimension(runtime.resolvedFrame(of: call.object)?.width,
                                              declared: runtime.declaredFrame(of: call.object).width)
                let height = runtime.dimension(runtime.resolvedFrame(of: call.object)?.height,
                                               declared: runtime.declaredFrame(of: call.object).height)
                runtime.writeGeometry([("x", String((Int32(screen.width) - width) / 2)),
                                       ("y", String((Int32(screen.height) - height) / 2))], on: call.object, borrowed: nil)
                return .null
            }
            return nil
        }
        // The hosted surface's name, as the thinger titles it. cPro labels its drawer tab with it
        // from a timer that aborted on every tick (`refreshAIOTab`, `checkVisName`, B193).
        table.add("getcomponentname", 0) { runtime, call in
            let kind = WasabiSceneRenderer.componentKind(of: call.object)
            return .string(WinampModernComponentBucketCatalog.icons.first { $0.kind == kind }?.title ?? "")
        }
        // The Bio-Nid lineage switches its playlist sidecar's page from script (B198).
        table.add("getcurpage", 0) { runtime, call in
            if WasabiTabSheet.isTabSheet(call.object) {
                return .integer(Int32(WasabiTabSheet.selectedIndex(of: call.object)))
            }
            return nil
        }
        table.add("setcurpage", 1) { runtime, call in
            if WasabiTabSheet.isTabSheet(call.object) {
                if WasabiTabSheet.select(index: Int(call.arguments[0].integerValue),
                                         on: call.object) { runtime.notifyGraphDidMutate() }
                return .null
            }
            return nil
        }
        // `Edit`: auto-enter makes every change an enter (the view reads the flag), and `enter()`
        // is the script pressing Return (B189).
        table.add("setautoenter", 1) { runtime, call in
            _ = call.object.setAttribute("autoenter", value: call.arguments[0].truthy ? "1" : "0")
            return .null
        }
        table.add("getautoenter", 0) { runtime, call in
            .integer(call.object.attributes["autoenter"] == "1" ? 1 : 0)
        }
        table.add("enter", 0) { runtime, call in
            _ = try runtime.dispatch(object: call.object, event: "onenter")
            return .null
        }
        // `Vis.getMode()`: what `setMode` and a click on the vis last wrote (Styx's `vis.m`, B190).
        table.add("getmode", 0) { runtime, call in
            .integer(Int32(WasabiVisualizationMode(attribute: call.object.attributes["mode"]).attributeValue) ?? 1)
        }
        // Paint order within the parent. ClassicPro raises a tab while it is being dragged along
        // the strip, and the missing method aborted the whole drag handler.
        // Paint order is sibling order (the renderer walks `children` front to back), so raising an
        // object is moving it to the end of its parent's list.
        table.add(["bringtofront", "bringtoback"], 0) { runtime, call in
            guard let parent = call.object.parent, parent.children.count > 1 else { return .null }
            try parent.insertChild(call.object, at: call.method == "bringtofront" ? parent.children.count : 0)
            runtime.notifyGraphDidMutate()
            return .null
        }
        // Paint order relative to a sibling: just under it, or just over it.
        table.add(["bringbelow", "bringabove"], 1) { runtime, call in
            guard case .object(let reference) = call.arguments[0], case .gui(let otherID) = reference.kind,
                  let other = runtime.loadedSkin.runtime.graph.object(withID: otherID), other !== call.object,
                  let parent = call.object.parent, other.parent === parent else { return .null }
            // `insertChild` takes the object out first, so the index is among the others.
            guard let index = parent.children.filter({ $0 !== call.object })
                .firstIndex(where: { $0 === other }) else { return .null }
            try parent.insertChild(call.object, at: call.method == "bringbelow" ? index : index + 1)
            runtime.notifyGraphDidMutate()
            return .null
        }
        table.add("islayout", 0) { runtime, call in .boolean(call.object.tag.is(.layout)) }
        table.add("getnumlayouts", 0) { runtime, call in
            .integer(Int32(call.object.children.filter { $0.tag.is(.layout) }.count))
        }
        table.add("enumlayout", 1) { runtime, call in
            let layouts = call.object.children.filter { $0.tag.is(.layout) }
            let index = Int(call.arguments[0].integerValue)
            return layouts.indices.contains(index) ? runtime.objectValue(layouts[index]) : .null
        }
        // The window's name, as the Windows menu lists it (Anunaki renames its own).
        table.add("setname", 1) { runtime, call in
            _ = call.object.setAttribute("name", value: call.arguments[0].stringValue)
            runtime.notifyGraphDidMutate()
            return .null
        }
        table.add("setdesktopalpha", 1) { runtime, call in
            _ = call.object.setAttribute("desktopalpha", value: call.arguments[0].truthy ? "1" : "0")
            runtime.notifyObjectDidMutate(call.object)
            return .null
        }
        table.add("getdesktopalpha", 0) { runtime, call in
            .boolean(call.object.attributes["desktopalpha"] == "1")
        }
        // `Button.rightClick()` is the script pressing the button's right side: its handler runs.
        table.add("rightclick", 0) { runtime, call in
            _ = try runtime.dispatch(object: call.object, event: "onrightclick")
            return .null
        }
        // `Slider.lock()` holds back the slider's own callbacks while a script moves it.
        table.add(["lock", "unlock"], 0) { runtime, call in
            _ = call.object.setAttribute("nullplayer.slider.locked", value: call.method == "lock" ? "1" : "0")
            return .null
        }
        table.add("nextmode", 0) { runtime, call in
            let mode = WasabiVisualizationMode(attribute: call.object.attributes["mode"]).stepped(by: 1)
            _ = call.object.setAttribute("mode", value: mode.attributeValue)
            runtime.notifyObjectDidMutate(call.object)
            return .null
        }
        // Whether the vis or animation draws every frame; ours always does.
        table.add("setrealtime", 1) { runtime, call in .null }
        return table
    }()
}
