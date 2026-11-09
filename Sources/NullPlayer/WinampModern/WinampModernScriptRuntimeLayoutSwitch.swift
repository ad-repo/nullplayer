import Foundation

/// A container's window shows one layout at a time: the script-side half of switching it. Split out of
/// `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// `WINAMP_MODERN_LAYOUT_WINDOW_TRACE=1` — every show or hide of a layout the window is not in.
    static let tracesLayoutWindow = ProcessInfo.processInfo.environment["WINAMP_MODERN_LAYOUT_WINDOW_TRACE"] != nil

    /// A script's `switchToLayout`: the container's window now shows `layout`.
    func switchContainer(_ container: WasabiObject, to layout: WasabiObject) throws {
        activeLayoutByContainer[container.stableID] = layout.stableID
        realizedLayouts.insert(layout.stableID)
        _ = hooks.layoutSwitchRequested?(container.stableID, layout.xmlID ?? "")
        try announceLayoutSwitch(in: container, to: layout)
    }

    /// `Container.onSwitchToLayout(layout)` — raised whoever switched: a script's own `switchToLayout`
    /// and the user's SWITCH button alike. Würlitzer's player closes its floating visualization
    /// window from this event when it shades; with only the script route raising it, a shade button
    /// press left that window standing over the desktop (B390).
    func announceLayoutSwitch(in container: WasabiObject, to layout: WasabiObject) throws {
        _ = try dispatch(object: container, event: "onswitchtolayout", arguments: [objectValue(layout)])
    }

    /// Whether a `show()`/`hide()` of `object`, which belongs to the `target` window, goes on to the host.
    ///
    /// A container has one window, showing one layout at a time (`activeLayoutByContainer`). A layout
    /// the window is not in has no window of its own to hide, and showing it brings the window up in it.
    /// Würlitzer's `avs` container holds two backdrops, `fond` and `underlayer`, and its avsbtn flips
    /// them with `underlay.show(); overlay.hide()`: the hide of the layout being left closed the whole
    /// visualization window (B390).
    func forwardsLayoutVisibility(of object: WasabiObject, in target: WasabiObject, visible: Bool) -> Bool {
        guard object !== target, let active = activeLayoutByContainer[target.stableID],
              active != object.stableID else { return true }
        if Self.tracesLayoutWindow {
            NSLog("LAYOUT-WINDOW-TRACE %@ %@.%@ (window shows %@)", visible ? "show" : "hide",
                  target.xmlID ?? "-", object.xmlID ?? "-",
                  loadedSkin.runtime.graph.object(withID: active)?.xmlID ?? "-")
        }
        guard visible else { return false }
        // A script's show must not fail the script; the switch's only throw is a handler's own error.
        do { try switchContainer(target, to: object) } catch {
            #if DEBUG
            NSLog("WinampModern layout switch to %@ threw %@", object.xmlID ?? "-", String(describing: error))
            #endif
        }
        return true
    }
}
