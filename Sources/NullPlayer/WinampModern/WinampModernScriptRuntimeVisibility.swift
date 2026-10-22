import AppKit
import CoreGraphics
import Foundation

/// Visibility: what a script's `setVisible`, `isVisible` and `isActive` answer, and the rule that a
/// layout is never left with no way to seek. Split out of `WinampModernScriptRuntime.swift`.

/// What `setVisible` remembers between events. Only this file writes it.
struct WinampModernScriptVisibility {
    /// Objects a script hid during this event that carry a *positional* host action, checked once the
    /// event unwinds (see `settleStrandedControls`).
    fileprivate var strandingCandidates: Set<WasabiObjectID> = []

    /// Objects the skin's own script has **closed**, as opposed to ones that merely start life
    /// `visible="0"` and have never been opened. The `autoopen` fallback needs the difference: a
    /// page the script deliberately shut is a decision to respect, while an unopened one is exactly
    /// what the fallback exists to open. Big Bento's `mcvcore` closes the whole file-info page when
    /// it switches the Multi Content View to the stretched visualization, and the fallback reopened
    /// one of those groups on the next reveal — two pages on screen at once.
    fileprivate(set) var scriptClosedObjects: Set<WasabiObjectID> = []

    /// The object is showing again, however it got there.
    mutating func reopened(_ id: WasabiObjectID) { scriptClosedObjects.remove(id) }
}

extension WinampModernScriptRuntime {
    // MARK: - A layout must not be left with no way to seek

    /// The host actions this rule protects, and why it is only these.
    ///
    /// A **positional** control — the seek bar — has no paired counterpart to swap with, so a layout
    /// that ends an event with none of them visible has lost the only way to perform that action and
    /// cannot get it back: an invisible object is not hit-testable, so nothing can re-show it. That is
    /// not true of transport buttons, which skins swap constantly (`play.hide(); pause.show()`), and
    /// including those would restore a PLAY button every time a track started. The set is
    /// demand-driven — extend it when a measured skin strands another action, not on principle.
    static let strandableActions: Set<String> = ["SEEK"]

    static func strandableAction(of object: WasabiObject) -> String? {
        guard let action = object.attributes["action"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              strandableActions.contains(action) else { return nil }
        return action
    }

    /// Undo a hide that left a layout with no visible control for a positional action.
    ///
    /// Checked at **settle** rather than vetoed at the `hide()` itself, because a skin that swaps one
    /// control for another writes `a.hide(); b.show();` — at the moment of the hide, `b` is still
    /// hidden, so a call-time veto would refuse a perfectly good swap and leave both on screen. By the
    /// time the outermost event unwinds, `b` is up and the rule correctly does nothing.
    ///
    /// Big Bento Modern is the measured case (BB16). `seek.maki` binds every one of its handlers to
    /// `seeker.ghost` and its `onLeftButtonUp` calls `hide()` on that same object — a duplicate
    /// `findObject("seeker.ghost")` where stock Winamp Modern's script reaches for a *readout* that
    /// does not exist in the layout, making the call a no-op on null there. The skin then mirrors
    /// `progressbar` and `player.seek.bg` to the seeker's visibility from `onSetVisible`, so one
    /// press-release took the whole seek bar with it and seeking stopped working until a track change.
    /// Restoring through `setVisible` rather than by writing the attribute is deliberate: the
    /// `onSetVisible(1)` it dispatches is what puts the trough and the fill back, so the skin's own
    /// mirror undoes itself.
    ///
    /// Defix runs the identical script and never reaches this: its `<Slider id="seeker">` stays
    /// visible, so the action still has a carrier. That is the difference the rule keys on — a
    /// capability of the layout, not the identity of the skin.
    func settleStrandedControls() {
        guard !visibility.strandingCandidates.isEmpty else { return }
        let candidates = visibility.strandingCandidates
        visibility.strandingCandidates.removeAll()
        for id in candidates {
            guard let object = loadedSkin.runtime.graph.object(withID: id),
                  let action = Self.strandableAction(of: object),
                  !isVisible(object) else { continue }
            guard let layout = ancestor(of: object, type: .layout) else { continue }
            guard !layoutHasVisibleControl(for: action, in: layout, excluding: object) else { continue }
            _ = try? setVisible(object, true)
        }
    }

    /// Is any object under `layout` carrying `action` visible all the way up to the layout?
    func layoutHasVisibleControl(for action: String, in layout: WasabiObject,
                                         excluding object: WasabiObject) -> Bool {
        var found = false
        func walk(_ node: WasabiObject, visibleSoFar: Bool) {
            if found { return }
            let visible = visibleSoFar && isVisible(node)
            if visible, node !== object, Self.strandableAction(of: node) == action {
                found = true
                return
            }
            // A hidden subtree can still contain the carrier the skin is *about* to reveal, but it is
            // not one today; recursing with `visible` false keeps that honest without losing the walk.
            for child in node.children { walk(child, visibleSoFar: visible) }
        }
        for child in layout.children { walk(child, visibleSoFar: true) }
        return found
    }

    /// `isInvalid()` — the object did not come up. For a *null* receiver that is answered in the
    /// interpreter; here it means an image-backed object whose bitmap never resolved, which is what
    /// the engine actually asks about. ClassicPro probes for optional artwork by declaring a hidden
    /// layer over it (`read.bg.left image="player.left.alt"`) and asking whether that layer is
    /// invalid; answering "valid" for a skin that ships no `mainframe_lr.png` made `player.maki`
    /// swap the window frame over to bitmaps that do not exist, punching holes in the window.
    func isInvalid(_ object: WasabiObject) -> Bool {
        guard let imageID = object.attributes["image"] ?? object.attributes["bitmap"] else { return false }
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: imageID),
              definition.kind == "bitmap" else { return true }
        // Generated bitmaps (`file="$solid"`) carry no file and are perfectly valid.
        if definition.attributes["file"]?.hasPrefix("$") == true { return false }
        return definition.logicalFile == nil
    }

    /// `show` / `hide` / `toggle`, in one place: the attribute, the notification, and the host
    /// request a container needs, in the order Wasabi does them.
    func setVisible(_ object: WasabiObject, _ visible: Bool) throws -> MakiValue {
        let changed = object.setAttribute("visible", value: visible ? "1" : "0")
        #if DEBUG
        if changed, ProcessInfo.processInfo.environment["WINAMP_MODERN_DEBUG_HOLDERS"] != nil {
            NSLog("WinampModern SETVISIBLE %@ -> %d by=%@", object.xmlID ?? object.typeName,
                  visible ? 1 : 0, MakiInterpreter.traceStack.last ?? "-")
        }
        #endif
        if visible { visibility.reopened(object.stableID) }
        else { visibility.scriptClosedObjects.insert(object.stableID) }
        if changed, !visible, Self.strandableAction(of: object) != nil {
            visibility.strandingCandidates.insert(object.stableID)
        }
        if changed { noteGeometryChange() }
        notifyGraphDidMutate()
        if changed {
            _ = try dispatch(object: object, event: "onsetvisible", arguments: [.boolean(visible)])
        }
        requestWindow(for: object, visible: visible)
        return .null
    }

    /// Visible *as the user sees it*. The window this object lives in is the outer term — only the
    /// host knows whether it is on screen — and the object's own `visible` attribute is the inner
    /// one. `nil` from the host (the headless harness, the player's own container, an id no window
    /// backs) falls back to the attribute alone.
    ///
    /// The ancestor **groups** between the two are deliberately not consulted: Winamp's
    /// `GuiObject::isVisible()` answers for the object itself, and walking the group chain broke
    /// cPro-Bento's tab system, whose script shows a tab page whose parent group is still hidden
    /// (B22). A closed *window* is a different question, and it is the one Defix asks.
    /// The player window's box in **Winamp's screen space** — y measured downward from the top of the
    /// screen the window is on — or `nil` when no host has answered (the headless harness).
    ///
    /// The obvious `NSApp.mainWindow?.frame` is wrong twice over. `NSApp` is an implicitly-unwrapped
    /// global that is **nil** until an `NSApplication` exists, so reading it traps in the headless
    /// harness rather than answering; and AppKit's `minY` is the window's *bottom* measured upward,
    /// which is the opposite of the coordinate every other window read in this runtime answers in
    /// (`getLeft`/`getTop` go through `containerOriginQuery`, which the controller fills from
    /// `winampScreenOrigin`). ClassicPro seeds `normal.resize(x, y, …)` from `getCurAppTop()` when
    /// the user has no stored position, so an upward y put the player wherever the flip landed.
    ///
    /// Both faults were unreachable until `System.onShowLayout` began to be dispatched: `fullScreen()`
    /// is the only caller, and nothing ran it.
    var playerWindowFrame: CGRect? {
        guard let origin = containerOriginQuery?(Self.playerContainerID),
              let size = hooks.playerWindowSizeRequested?() else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The id Winamp gives the player's own container. The same literal the topology keys `isMainPlayer` on.
    static let playerContainerID = "main"

    /// One edge of that frame as MAKI sees it: clamped, and 0 when there is no window to measure.
    static func appFrameDimension(_ value: CGFloat?) -> Int32 {
        guard let value, value.isFinite else { return 0 }
        return Int32(clamping: Int(value.rounded()))
    }

    func effectiveVisibility(of object: WasabiObject) -> Bool {
        let hosted = enclosingWindowID(of: object).flatMap { containerVisibilityQuery?($0) }
        // Nothing inside a closed window is on screen, whatever its own attribute still says.
        // Defix's `ML` round button asks the media-library tab page this before deciding what
        // its click means; with the SUI window shut and the page's stale `visible="1"` answering
        // yes, every press took the "already showing — close it" branch, so the button could
        // only ever shut a window the menu had opened (B22).
        if hosted == false { return false }
        // A container shows exactly **one** layout at a time, so a layout that is not its
        // container's active one is not on screen however open the window is. Answering for the
        // window alone made `normal` and `shade` both report visible simultaneously, which is a
        // state no Winamp skin can be in, and a skin that tells the two apart then read the wrong
        // one: ClassicPro engine "two" lays its whole player out from
        // `if(_layout==normal && !shade.isVisible())` on cold start, and with `shade` answering yes
        // that branch never ran — `two.screen` kept its default `y=0`, the info and transport bands
        // drew over the titlebar, and a 28px dead strip sat above the SUI (cPro2 Dark Aluminum).
        //
        // This is deliberately answered from the graph rather than from the host, so it holds in
        // the headless harness too, where no container visibility is reported at all.
        if object.tag.is(.layout),
           let container = Self.enclosingContainer(of: object),
           let active = activeLayoutByContainer[container.stableID] {
            return active == object.stableID
        }
        // A layout answers for its window as its container does, and for the same reason: the window
        // is the thing that is actually on screen, and the host can close it (a dismissed
        // `autoclose` popup) without the graph attribute moving. Big Bento asks its search results'
        // *layout* whether it is open before re-showing it, so a stale `visible="1"` there left the
        // skin believing a window the user had dismissed was still up — and the next search filled a
        // list nobody could see (BB31).
        if hosted == true, Self.isWindowObject(object) { return true }
        return isVisible(object)
    }

    /// The container id of the window this object belongs to, for the host queries that are answered
    /// per window rather than per object.
    func enclosingWindowID(of object: WasabiObject) -> String? {
        let container = object.tag.is(.container)
            ? object
            : Self.enclosingContainer(of: object)
        guard let id = container?.xmlID, !id.isEmpty else { return nil }
        return id
    }

    /// Active *as the window server sees it*: the container this object belongs to owns the
    /// keyboard.
    ///
    /// Winamp answers this per object, and winampmodern566's playlist asks it of two different ones —
    /// the content group and that container's `shade` layout — before it will act on `ctrl+w`. Both
    /// live in the same window, and the window is the only thing that can actually be focused, so
    /// walking up to the container and asking the host once answers both terms correctly.
    ///
    /// With no host installed (the headless harness) there is no focus to report and every object
    /// reads active, so a probe can still drive a handler that gates on it. In the app the host
    /// always answers.
    func isActive(_ object: WasabiObject) -> Bool {
        guard let query = containerActiveQuery else { return true }
        var node: WasabiObject? = object
        while let current = node {
            if current.tag.is(.container),
               let id = current.xmlID, !id.isEmpty {
                return query(id) ?? false
            }
            node = current.parent
        }
        return false
    }

    func isVisible(_ object: WasabiObject) -> Bool {
        let value = object.attributes["visible"]?.lowercased()
        return value != "0" && value != "false" && value != "no"
    }
}
