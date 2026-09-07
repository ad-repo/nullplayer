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
        let speed: Double
        var lastTick: Double
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

    private func targetTimerID(for objectID: WasabiObjectID) -> UInt64 {
        objectID.rawValue | 0x8000_0000_0000_0000
    }

    private func targetAttr(_ object: WasabiObject, _ key: String, fallback: String) -> Double {
        Double(object.attributes[key] ?? object.attributes[fallback] ?? "0") ?? 0
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
    /// `desktopOrigin` overrides the position half: the caller has recognised the coordinates as
    /// another window's, and re-expressed them in the desktop space this move is answered in. See
    /// `borrowedWindowOrigin`.
    func applyContainerGeometry(_ object: WasabiObject, reportedOrigin: CGPoint? = nil,
                                        desktopOrigin: CGPoint? = nil) {
        // A **layout** is its window as much as the container is — a `noparent` popup is placed and
        // sized by writing `x`/`y`/`w`/`h` on the layout, in screen coordinates the script builds with
        // `clientToScreenX/Y`. Big Bento's playlist search does exactly that before showing its
        // results (BB31); `resize()` on a layout already routed its size here, and `setXmlParam` of
        // the same four attributes now does too, position included.
        let target: WasabiObject?
        if object.typeName.caseInsensitiveCompare("container") == .orderedSame {
            target = object
        } else if object.typeName.caseInsensitiveCompare("layout") == .orderedSame {
            target = Self.enclosingContainer(of: object)
        } else {
            target = nil
        }
        guard let target else { return }
        if let width = Double(object.attributes["w"] ?? ""),
           let height = Double(object.attributes["h"] ?? ""), width > 0, height > 0 {
            layoutResizeRequested?(target.stableID, CGSize(width: width, height: height))
        }
        if let desktopOrigin {
            containerMoveRequested?(target.stableID, desktopOrigin, true)
        } else if let x = Double(object.attributes["x"] ?? ""),
                  let y = Double(object.attributes["y"] ?? "") {
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
            if !unmoved { containerMoveRequested?(target.stableID, CGPoint(x: x, y: y), false) }
        }
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
            if hasX { _ = object.setAttribute("x", value: object.attributes["targetx"]!) }
            if hasY { _ = object.setAttribute("y", value: object.attributes["targety"]!) }
            if hasW { _ = object.setAttribute("w", value: object.attributes["targetw"]!) }
            if hasH { _ = object.setAttribute("h", value: object.attributes["targeth"]!) }
            if hasA { _ = object.setAttribute("alpha", value: object.attributes["targeta"]!) }
            _ = object.setAttribute("goingtotarget", value: "0")
            applyContainerGeometry(object)
            notifyGraphDidMutate()
            _ = try? dispatch(object: object, event: "ontargetreached")
            return
        }
        let speed = min(1.0, rawSpeed)
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
            speed: speed,
            lastTick: ProcessInfo.processInfo.systemUptime,
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

        let timerID = targetTimerID(for: id)
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

        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0.001, now - state.lastTick)
        state.lastTick = now
        let factor = 1 - pow(1 - state.speed, dt / Self.wasabiTargetTickPeriod)

        func lerp(_ current: Double, _ target: Double) -> Double {
            current + (target - current) * factor
        }

        state.currentX = lerp(state.currentX, state.targetX)
        state.currentY = lerp(state.currentY, state.targetY)
        state.currentW = lerp(state.currentW, state.targetW)
        state.currentH = lerp(state.currentH, state.targetH)
        state.currentAlpha = lerp(state.currentAlpha, state.targetAlpha)

        // What this tick actually *changed*, kept apart by kind. A 60 Hz ease writes an integer
        // attribute, so most ticks of a slow fade write the value the object already has —
        // `setAttribute` answers false and there is nothing on screen to repaint. And a tick that
        // moves only `alpha` moves no geometry: it needs the object's own rect repainted, not a
        // full-window relayout. Before B52 every tick took the heavy path unconditionally, which on
        // Big Bento Modern is a whole-tree re-solve plus a whole-window repaint, sixty times a
        // second, for a text row fading in.
        var movedGeometry = false
        var movedAlpha = false
        if state.hasTargetX { movedGeometry = object.setAttribute("x", value: String(Int(state.currentX.rounded()))) || movedGeometry }
        if state.hasTargetY { movedGeometry = object.setAttribute("y", value: String(Int(state.currentY.rounded()))) || movedGeometry }
        if state.hasTargetW { movedGeometry = object.setAttribute("w", value: String(Int(state.currentW.rounded()))) || movedGeometry }
        if state.hasTargetH { movedGeometry = object.setAttribute("h", value: String(Int(state.currentH.rounded()))) || movedGeometry }
        if state.hasTargetA { movedAlpha = object.setAttribute("alpha", value: String(Int(state.currentAlpha.rounded()))) }

        if animationReached(state) {
            if state.hasTargetX { _ = object.setAttribute("x", value: String(Int(state.targetX))) }
            if state.hasTargetY { _ = object.setAttribute("y", value: String(Int(state.targetY))) }
            if state.hasTargetW { _ = object.setAttribute("w", value: String(Int(state.targetW))) }
            if state.hasTargetH { _ = object.setAttribute("h", value: String(Int(state.targetH))) }
            if state.hasTargetA { _ = object.setAttribute("alpha", value: String(Int(state.targetAlpha))) }
            activeTargetAnimations.removeValue(forKey: objectID)
            timers.cancel(id: targetTimerID(for: objectID))
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

    func cancelTargetAnimation(objectID: WasabiObjectID) {
        activeTargetAnimations.removeValue(forKey: objectID)
        timers.cancel(id: targetTimerID(for: objectID))
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
