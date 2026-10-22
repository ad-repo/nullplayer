import AppKit
import CoreGraphics
import Foundation

/// Timed motion: the `target*` animation a script starts on an object, the tick that
/// advances it, and the geometry each step writes back. Split out of
/// `WinampModernScriptRuntime.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    struct TargetAnimationState {
        var currentX: Double
        var currentY: Double
        var currentW: Double
        var currentH: Double
        var currentAlpha: Double
        var targetX: Double
        var targetY: Double
        var targetW: Double
        var targetH: Double
        var targetAlpha: Double
        let startX: Double
        let startY: Double
        let startW: Double
        let startH: Double
        let startAlpha: Double
        /// Seconds to reach the target — what Winamp's `setTargetSpeed(float insecond)` takes.
        let duration: Double
        let startTime: Double
        let hasTargetX: Bool
        let hasTargetY: Bool
        let hasTargetW: Bool
        let hasTargetH: Bool
        let hasTargetA: Bool
    }

    func setTarget(_ key: String, object: WasabiObject, value: MakiValue) -> MakiValue {
        _ = object.setAttribute(key, value: String(value.integerValue))
        _ = object.setAttribute("goingtotarget", value: "1")
        return .null
    }

    /// The timer service's ids are one space shared by every owner. A MAKI `Timer` uses its own
    /// dynamic-object id; the timers the runtime runs on a GUI object's behalf set a high bit over
    /// that object's id, one bit per job, so no two owners can collide.
    enum TimerNamespace: UInt64 {
        case frameEvents = 0x4000_0000_0000_0000
        case targetAnimation = 0x8000_0000_0000_0000

        func id(for objectID: WasabiObjectID) -> UInt64 { objectID.rawValue | rawValue }
    }

    private func targetAttr(_ object: WasabiObject, _ key: String, fallback: String) -> Double {
        Double(object.attributes[key] ?? object.attributes[fallback] ?? "0") ?? 0
    }

    /// A script's geometry write — `setXmlParam` of a geometry key, or `resize()` — and the window
    /// push that has to follow it.
    ///
    /// A window's reported origin is taken **before** the write, for `applyContainerGeometry` to
    /// recognise a round trip (B61), and only a window's: for anything else the read resolves the
    /// whole layout, the write invalidates it again, and doing that on every write was most of a
    /// skin switch's script start-up.
    func writeGeometry(_ attributes: [(key: String, value: String)], on object: WasabiObject,
                       borrowed: WinampModernBorrowedOrigin.Request? = nil) {
        let moves = attributes.contains { $0.key == "x" || $0.key == "y" }
        let reportedBeforeWrite = takeOriginRead(of: object, moves: moves) ? reportedOrigin(of: object) : nil
        for (key, value) in attributes { _ = object.setAttribute(key, value: value) }
        applyContainerGeometry(object, reportedOrigin: reportedBeforeWrite, borrowed: borrowed)
        noteGeometryChange()
        notifyGraphDidMutate()
    }

    /// Push a *container's* `x`/`y`/`w`/`h` out to its window.
    ///
    /// Every other object's geometry is read back out of the graph when the scene is next drawn, so
    /// writing the attribute is the whole job. A container is not drawn: its size lives in the
    /// window and its position on the desktop, and both are the host's to set. `resize()` and the
    /// `setTargetX/Y/W/H` animation are the two ways a script asks for either, and Big Bento's
    /// notifier uses both — it measures its own text with `getAutoWidth`, resizes to fit, and then
    /// animates itself into the corner of the screen. Silently dropping these is why that toast came
    /// out at its declared 540 with the text clipped into the third of it the XML reserves for the
    /// album art it had already hidden (BB27).
    ///
    /// `borrowed` overrides the position half: the caller has recognised the coordinates as
    /// another window's. `.desktop` carries them re-expressed in the desktop space this move is
    /// answered in; `.offScreen` drops the position half altogether, because they were read off a
    /// window that is not on screen (B156). See `WinampModernBorrowedOrigin`.
    ///
    /// **A pin goes out before the size** (B160). Wasabi applies the box whole and then notifies,
    /// and the size is the request that dispatches `onResize` inside the resized window — so a
    /// window still at its old position when that fires is a state Wasabi never shows a script.
    /// The host sizes a window around its top-left, the corner the pin names, so the position
    /// survives. A plain move still follows the size: it is clamped to the screen by the size the
    /// window ends up with. See `reference/scripting.md` → *The pin lands before the size*.
    func applyContainerGeometry(_ object: WasabiObject, reportedOrigin: CGPoint? = nil,
                                        borrowed: WinampModernBorrowedOrigin.Request? = nil) {
        // A **layout** is its window as much as the container is — a `noparent` popup is placed and
        // sized by writing `x`/`y`/`w`/`h` on the layout, in screen coordinates the script builds with
        // `clientToScreenX/Y`. Big Bento's playlist search does exactly that before showing its
        // results (BB31); `resize()` on a layout already routed its size here, and `setXmlParam` of
        // the same four attributes now does too, position included.
        guard let target = Self.windowTarget(of: object) else { return }
        // **A layout that is not showing is not the window.** Each Wasabi layout is a window of its
        // own, so a write to one the container is not on lands on that hidden window and waits for
        // the switch. Vortex parks its Dashboard layout at the screen edge from `onScriptLoaded` —
        // `x`/`y`/`h` on `layout#dashboard` — and taking that as the player's window squeezed the
        // 505-wide normal player into a 180×1169 strip.
        if object !== target, activeLayoutByContainer[target.stableID] != object.stableID { return }
        func applySize() {
            guard let width = Double(object.attributes["w"] ?? ""),
                  let height = Double(object.attributes["h"] ?? "") else { return }
            noteScriptSize(of: object, collapsed: width <= 0 && height <= 0)
            guard width > 0, height > 0 else { return }
            hooks.layoutResizeRequested?(target.stableID, CGSize(width: width, height: height))
        }
        switch borrowed {
        case .desktop(let pin):
            if Self.deliversResizeAsWasabiDoes {
                hooks.containerMoveRequested?(target.stableID, pin, true)
                applySize()
            } else {
                applySize()
                hooks.containerMoveRequested?(target.stableID, pin, true)
            }
        case .offScreen:
            applySize()
        case nil:
            applySize()
            guard let x = Double(object.attributes["x"] ?? ""),
                  let y = Double(object.attributes["y"] ?? "") else { return }
            // **Writing back the position that was just read is not a move.** `resize(getLeft(),
            // getTop(), w, h)` is how a skin resizes a window while leaving it where it is, and the
            // two halves have to agree about the space they are in: `getLeft()`/`getTop()` on a
            // layout answer its own canvas origin — 0 — so taking that 0 as a desktop coordinate
            // parked the window in the corner of the monitor. Big Bento's side playlist does exactly
            // this from `pledit.maki` every time the panel opens (B61).
            //
            // Only the *round trip* is recognised, not the value: a script that writes a position it
            // did not read — Big Bento's search-results popup places itself with a point it measured
            // (BB31) — is still a move, whatever that position happens to be.
            let unmoved = reportedOrigin.map {
                Int(x.rounded()) == Int($0.x.rounded()) && Int(y.rounded()) == Int($0.y.rounded())
            } ?? false
            if !unmoved { hooks.containerMoveRequested?(target.stableID, CGPoint(x: x, y: y), false) }
        }
    }

    /// The container whose window a show, hide or geometry write on `object` acts on: a container is
    /// its own, a layout is its container's (BB31), and anything else is not a window.
    static func windowTarget(of object: WasabiObject) -> WasabiObject? {
        if object.tag.is(.container) { return object }
        if object.tag.is(.layout) {
            return enclosingContainer(of: object)
        }
        return nil
    }

    /// Records a script size write on a layout. No size at all is a window Winamp draws 0×0: ONYX V2
    /// gives its visualization window no size in the mini player, and kept at its declared 67×72 it
    /// floated loose as a black square. The record is read when the window is next shown
    /// (`requestWindow`): a `show()` of a collapsed layout is answered as a **hide**, so a window
    /// already open at its old size goes too, and a real size lets the next `show()` through. The size
    /// write itself neither hides nor shows anything.
    func noteScriptSize(of layout: WasabiObject, collapsed: Bool) {
        guard layout.tag.is(.layout) else { return }
        if collapsed { scriptCollapsedLayouts.insert(layout.stableID) }
        else { scriptCollapsedLayouts.remove(layout.stableID) }
    }

    /// Whether the layout a show of `object` brings up — the layout itself, or the container's
    /// current one — has been sized to nothing.
    func isCollapsed(showing object: WasabiObject, in container: WasabiObject) -> Bool {
        let layout = object === container ? activeLayoutByContainer[container.stableID] : object.stableID
        return layout.map(scriptCollapsedLayouts.contains) ?? false
    }

    func startTargetAnimation(object: WasabiObject) {
        let id = object.stableID
        cancelTargetAnimation(objectID: id)

        let hasX = object.attributes["targetx"] != nil
        let hasY = object.attributes["targety"] != nil
        let hasW = object.attributes["targetw"] != nil
        let hasH = object.attributes["targeth"] != nil
        let hasA = object.attributes["targeta"] != nil

        let rawSpeed = Double(object.attributes["targetspeed"] ?? "0.5") ?? 0.5
        if rawSpeed <= 0 {
            if hasX { _ = object.moveForTarget("x", to: object.attributes["targetx"]!) }
            if hasY { _ = object.moveForTarget("y", to: object.attributes["targety"]!) }
            if hasW { _ = object.moveForTarget("w", to: object.attributes["targetw"]!) }
            if hasH { _ = object.moveForTarget("h", to: object.attributes["targeth"]!) }
            if hasA { _ = object.setAttribute("alpha", value: object.attributes["targeta"]!) }
            _ = object.setAttribute("goingtotarget", value: "0")
            applyContainerGeometry(object)
            notifyGraphDidMutate()
            _ = try? dispatch(object: object, event: "ontargetreached")
            return
        }
        // `setTargetSpeed` is a **duration**: "the number of seconds in which to reach the target"
        // (`std.mi`). It was read as a per-tick ease fraction capped at 1, so every value of 1 or
        // more snapped in a few ticks: Anunaki's notifier fades out over its 5 s setting and was
        // gone in a fraction of a second.
        let cx = Double(object.attributes["x"] ?? "0") ?? 0
        let cy = Double(object.attributes["y"] ?? "0") ?? 0
        let cw = Double(object.attributes["w"] ?? "0") ?? 0
        let ch = Double(object.attributes["h"] ?? "0") ?? 0
        let ca = Double(object.attributes["alpha"] ?? "255") ?? 255
        let state = TargetAnimationState(
            currentX: cx, currentY: cy, currentW: cw, currentH: ch, currentAlpha: ca,
            targetX: hasX ? (Double(object.attributes["targetx"]!) ?? cx) : cx,
            targetY: hasY ? (Double(object.attributes["targety"]!) ?? cy) : cy,
            targetW: hasW ? (Double(object.attributes["targetw"]!) ?? cw) : cw,
            targetH: hasH ? (Double(object.attributes["targeth"]!) ?? ch) : ch,
            targetAlpha: hasA ? (Double(object.attributes["targeta"]!) ?? ca) : ca,
            startX: cx, startY: cy, startW: cw, startH: ch, startAlpha: ca,
            duration: rawSpeed,
            startTime: ProcessInfo.processInfo.systemUptime,
            hasTargetX: hasX, hasTargetY: hasY, hasTargetW: hasW, hasTargetH: hasH, hasTargetA: hasA
        )

        if animationReached(state) {
            _ = object.setAttribute("goingtotarget", value: "0")
            notifyGraphDidMutate()
            _ = try? dispatch(object: object, event: "ontargetreached")
            return
        }

        _ = object.setAttribute("goingtotarget", value: "1")
        activeTargetAnimations[id] = state

        let timerID = TimerNamespace.targetAnimation.id(for: id)
        _ = try? timers.schedule(id: timerID, period: 1.0 / 60.0) { [weak self] in
            self?.tickTargetAnimation(objectID: id)
        }
    }

    private func tickTargetAnimation(objectID: WasabiObjectID) {
        guard var state = activeTargetAnimations[objectID] else { return }
        guard let object = loadedSkin.runtime.graph.object(withID: objectID) else {
            cancelTargetAnimation(objectID: objectID)
            return
        }

        // Linear from where the move started, over the stated duration, as Wasabi steps it.
        let progress = min(1, (ProcessInfo.processInfo.systemUptime - state.startTime) / state.duration)

        func lerp(_ start: Double, _ target: Double) -> Double {
            start + (target - start) * progress
        }

        state.currentX = lerp(state.startX, state.targetX)
        state.currentY = lerp(state.startY, state.targetY)
        state.currentW = lerp(state.startW, state.targetW)
        state.currentH = lerp(state.startH, state.targetH)
        state.currentAlpha = lerp(state.startAlpha, state.targetAlpha)

        // What this tick actually *changed*, kept apart by kind. A 60 Hz step writes an integer
        // attribute, so most ticks of a slow fade write the value the object already has —
        // `setAttribute` answers false and there is nothing on screen to repaint. And a tick that
        // moves only `alpha` moves no geometry: it needs the object's own rect repainted, not a
        // full-window relayout. Before B52 every tick took the heavy path unconditionally, which on
        // Big Bento Modern is a whole-tree re-solve plus a whole-window repaint, sixty times a
        // second, for a text row fading in.
        var movedGeometry = false
        var movedAlpha = false
        if state.hasTargetX { movedGeometry = object.moveForTarget("x", to: String(Int(state.currentX.rounded()))) || movedGeometry }
        if state.hasTargetY { movedGeometry = object.moveForTarget("y", to: String(Int(state.currentY.rounded()))) || movedGeometry }
        if state.hasTargetW { movedGeometry = object.moveForTarget("w", to: String(Int(state.currentW.rounded()))) || movedGeometry }
        if state.hasTargetH { movedGeometry = object.moveForTarget("h", to: String(Int(state.currentH.rounded()))) || movedGeometry }
        if state.hasTargetA { movedAlpha = object.setAttribute("alpha", value: String(Int(state.currentAlpha.rounded()))) }

        if animationReached(state) {
            if state.hasTargetX { _ = object.moveForTarget("x", to: String(Int(state.targetX))) }
            if state.hasTargetY { _ = object.moveForTarget("y", to: String(Int(state.targetY))) }
            if state.hasTargetW { _ = object.moveForTarget("w", to: String(Int(state.targetW))) }
            if state.hasTargetH { _ = object.moveForTarget("h", to: String(Int(state.targetH))) }
            if state.hasTargetA { _ = object.setAttribute("alpha", value: String(Int(state.targetAlpha))) }
            activeTargetAnimations.removeValue(forKey: objectID)
            timers.cancel(id: TimerNamespace.targetAnimation.id(for: objectID))
            _ = object.setAttribute("goingtotarget", value: "0")
            applyContainerGeometry(object)
            notifyGraphDidMutate()
            _ = try? dispatch(object: object, event: "ontargetreached")
        } else {
            activeTargetAnimations[objectID] = state
            if movedGeometry {
                applyContainerGeometry(object)
                notifyGraphDidMutate()
            } else if movedAlpha {
                requestRepaint(for: object)
            }
        }
    }

    private func animationReached(_ state: TargetAnimationState) -> Bool {
        abs(state.currentX - state.targetX) < 0.5 &&
        abs(state.currentY - state.targetY) < 0.5 &&
        abs(state.currentW - state.targetW) < 0.5 &&
        abs(state.currentH - state.targetH) < 0.5 &&
        abs(state.currentAlpha - state.targetAlpha) < 0.5
    }

    /// `AnimatedLayer.onFrame(frame)` for every frame a script-started play head moves to, and
    /// `onStop()` once a range play reaches its end frame. The play head is a function of the clock
    /// (`WasabiAnimation`), so nothing stepped it and neither event was ever raised. mmd3's knobs
    /// set the EQ from `onFrame` alone, so its bass knob turned without touching the EQ (B194).
    func startFrameEvents(for object: WasabiObject) {
        guard hasBinding(for: object, event: "onframe") || hasBinding(for: object, event: "onstop") else { return }
        let id = object.stableID
        var last = animationFrame(of: object)
        _ = try? timers.schedule(id: TimerNamespace.frameEvents.id(for: id), period: 1.0 / 60.0) { [weak self] in
            guard let self, let object = loadedSkin.runtime.graph.object(withID: id) else { return }
            let state = WasabiAnimation.state(of: object, frameCount: animationFrameCount(of: object))
            if state.frame != last {
                last = state.frame
                _ = try? dispatch(object: object, event: "onframe", arguments: [.integer(Int32(state.frame))])
            }
            if !state.isPlaying { stopFrameEvents(for: object) }
        }
    }

    /// Ends `startFrameEvents` with the layer's `onStop()`, if it was running.
    func stopFrameEvents(for object: WasabiObject) {
        let timerID = TimerNamespace.frameEvents.id(for: object.stableID)
        guard timers.contains(id: timerID) else { return }
        timers.cancel(id: timerID)
        _ = try? dispatch(object: object, event: "onstop")
    }

    func cancelTargetAnimation(objectID: WasabiObjectID) {
        activeTargetAnimations.removeValue(forKey: objectID)
        timers.cancel(id: TimerNamespace.targetAnimation.id(for: objectID))
    }

    func reverseTargetAnimation(object: WasabiObject) {
        let id = object.stableID
        if var state = activeTargetAnimations[id] {
            state.targetX = state.startX
            state.targetY = state.startY
            state.targetW = state.startW
            state.targetH = state.startH
            state.targetAlpha = state.startAlpha
            activeTargetAnimations[id] = state
        } else {
            startTargetAnimation(object: object)
        }
    }
}
