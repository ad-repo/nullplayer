import AppKit
import CoreGraphics
import Foundation

/// Whether the current event owes the scene an `onResize` pass, and whether one is running.
struct WinampModernGeometrySettle {
    /// Whether anything a script did during the current event could have moved an object. Only the
    /// mutations that can — geometry, visibility, parentage, splitter position — set it, so a skin whose
    /// timer merely advances an animation frame (cPro's beat display, every 10 ms) costs nothing.
    private var mayHaveChanged = false
    /// Guards the settle callback against the `onResize` dispatch it makes re-entering it.
    private var isSettling = false

    mutating func noteChange() { mayHaveChanged = true }

    /// Whether there was a change to settle; it is spent by asking.
    mutating func takeChange() -> Bool {
        defer { mayHaveChanged = false }
        return mayHaveChanged
    }

    /// Starts a settle, or answers false when one is already running.
    mutating func begin() -> Bool {
        guard !isSettling else { return false }
        isSettling = true
        return true
    }

    mutating func end() { isSettling = false }
}

/// Window geometry: origins a script reads and writes, glued windows, settling geometry after a
/// change, and the move/resize events. Split out of
/// `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// Route a `show()`/`hide()` on a top-level container to whoever owns that window. Anything else
    /// — a group, a layer, a layout — is graph state and stops here.
    func requestWindow(for object: WasabiObject, visible: Bool) {
        // A **layout** counts as its container: showing a layout is how Winamp opens the window that
        // holds it, and skins say it that way as often as they name the container. Big Bento's
        // playlist search is the measured case — it fills the `searchresults` container's list, sizes
        // it, and then calls `show()` on that container's `normal` *layout*. Routed only from a
        // `<container>`, the results window never opened and pressing Return looked like a dead key,
        // with the search itself demonstrably running (BB31).
        guard let target = Self.windowTarget(of: object), let id = target.xmlID, !id.isEmpty else { return }
        // A show of a layout a script sized to nothing is answered as a hide: see `noteScriptSize`.
        hooks.containerVisibilityRequested?(id, visible && !isCollapsed(showing: object, in: target))
    }

    /// Whether this object *is* a window — a `<container>` or one of its `<layout>`s. Both carry a
    /// desktop position rather than a position inside a parent.
    static func isWindowObject(_ object: WasabiObject) -> Bool {
        object.tag.is(.container)
            || object.tag.is(.layout)
    }

    /// Where the window backing this container or layout sits on the desktop, in Winamp's screen
    /// space, or `nil` when no host has answered (the headless harness, an id no window backs).
    func windowOrigin(of object: WasabiObject) -> CGPoint? {
        guard Self.isWindowObject(object) else { return nil }
        return enclosingWindowID(of: object).flatMap { containerOriginQuery?($0) }
    }

    /// Whether a geometry write on `object` can be a round trip of its own origin: it is a window
    /// object whose origin a script read since its last move. A write that `moves` the origin
    /// spends the read.
    func takeOriginRead(of object: WasabiObject, moves: Bool) -> Bool {
        guard Self.isWindowObject(object) else { return false }
        return borrowedOrigin.takeRead(of: object.stableID, moves: moves)
    }

    /// `getLeft()`/`getTop()`: the reported origin, remembered when it was read off a window object
    /// so a write on another window can be recognised as relative to it.
    func scriptReadsOrigin(of object: WasabiObject) -> CGPoint {
        let reported = reportedOrigin(of: object)
        guard Self.isWindowObject(object) else { return reported }
        borrowedOrigin.noteRead(of: object.stableID)
        if let desktop = windowOrigin(of: object) {
            let onScreen = enclosingWindowID(of: object).flatMap { containerVisibilityQuery?($0) } != false
            borrowedOrigin.record(.init(window: object.stableID, reported: reported, desktop: desktop,
                                        onScreen: onScreen))
        }
        return reported
    }

    /// What a script's write of `x` and/or `y` on a window object really asks for when those
    /// coordinates are another window's, or nil when they are a plain position.
    func borrowedWindowOrigin(x: Double?, y: Double?,
                              writtenOn object: WasabiObject) -> WinampModernBorrowedOrigin.Request? {
        guard Self.isWindowObject(object),
              let match = borrowedOrigin.match(x: x, y: y, writtenOn: object.stableID,
                                               current: windowOrigin(of: object))
        else { return nil }
        noteWindowGluedOver(follower: object, leader: match.leader)
        return match.request
    }

    /// The pairing this idiom *is*: the window being written follows the window that was read.
    /// Nothing else in the host knows it — the relationship lives entirely in the skin's script — and
    /// the window layer needs it to keep a frame from being buried by the client it is drawn on
    /// (B110). Recorded by container, because that is what owns a window.
    ///
    /// **Directional, and the direction has to be decided here.** A standard frame writes *both*
    /// ways: `syncFrame()` puts the frame on the client's origin and `syncContent()` puts the client
    /// back on the frame's, so taken at face value this idiom records A-over-B and B-over-A. Recorded
    /// both ways the window layer fought itself and whichever pair it restacked last won — which is
    /// exactly how the client came back on top of its own chrome. The frame is the one of the two a
    /// script asked `newDynamicContainer` for; the client is a window the skin declares and the user
    /// opens. So only that direction is kept.
    func noteWindowGluedOver(follower object: WasabiObject, leader leaderID: WasabiObjectID) {
        guard let follower = Self.enclosingContainer(of: object) ?? (Self.isWindowObject(object) ? object : nil),
              let leaderObject = loadedSkin.runtime.graph.object(withID: leaderID),
              let leader = Self.enclosingContainer(of: leaderObject)
                ?? (Self.isWindowObject(leaderObject) ? leaderObject : nil),
              follower.stableID != leader.stableID,
              isDynamicallyClaimed(follower.stableID), !isDynamicallyClaimed(leader.stableID)
        else { return }
        windowsGluedOver[leader.stableID] = follower.stableID
    }

    /// The window drawn on top of `container`'s, if a script has glued one there.
    func windowGluedOver(_ container: WasabiObjectID) -> WasabiObjectID? {
        windowsGluedOver[container]
    }

    /// What `getLeft()`/`getTop()` answer for this object right now, in whatever space they answer
    /// in — the host's desktop origin for a container, the layout's own canvas origin (usually 0) for
    /// a layout. **The only place that answer is worked out**, so the round trip
    /// `applyContainerGeometry` recognises compares against the very integers the script was handed:
    /// a layout's `x="12.7"` reads back as 12, and a 12 written back is not a move.
    func reportedOrigin(of object: WasabiObject) -> CGPoint {
        let isWindow = Self.isWindowObject(object)
        if isWindow, object.tag.is(.container),
           let origin = windowOrigin(of: object) {
            return CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        }
        // A window's own `x`/`y`, truncated as Wasabi reads them; anything else, or a window that
        // never declared one, answers from the resolved layout.
        let x = isWindow ? Double(object.attributes["x"] ?? "") : nil
        let y = isWindow ? Double(object.attributes["y"] ?? "") : nil
        let frame = x == nil || y == nil ? resolvedFrame(of: object) : nil
        return CGPoint(x: x.map { Double(Int($0)) } ?? Double(dimension(frame?.minX, declared: object.geometry.x)),
                       y: y.map { Double(Int($0)) } ?? Double(dimension(frame?.minY, declared: object.geometry.y)))
    }

    func noteGeometryChange() {
        geometrySettle.noteChange()
        // A mutation made *outside* any event (the host, or a direct call) has no event to unwind, so
        // it settles at once. Inside one it waits: a handler that moves five things in a row should
        // produce one round of `onResize`, not five.
        if !isDispatchingEvent { settleGeometryIfNeeded() }
    }

    /// `setXmlParam` keys that can move an object or take it out of the layout. Everything else a
    /// script writes (an image swap, a tooltip, a colour) leaves every frame where it was.
    static let geometryKeys: Set<String> = [
        "x", "y", "w", "h", "relatx", "relaty", "relatw", "relath",
        "visible", "fitparent", "position", "sysregion"
    ]

    /// `setXmlParam` keys whose value names a resource rather than being a value in itself.
    static let imageKeys: Set<String> = [
        "image", "bitmap", "background", "downimage", "hoverimage", "activeimage",
        "thumb", "downthumb", "hoverthumb", "notfoundimage"
    ]

    /// Does this identifier name a resource the skin actually registered? `background` is written
    /// with a colour id as well as a bitmap one, so the question is registration, not kind.
    func resolvesToResource(_ identifier: String) -> Bool {
        loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier) != nil
    }

    func settleGeometryIfNeeded() {
        // Never mid-draw: a Layer FX callback runs inside a repaint, and settling geometry from there
        // would re-solve the scene while it is being painted.
        guard !layerFX.isEvaluating, geometrySettle.begin() else { return }
        defer { geometrySettle.end() }
        // Before the resize pass, and independently of whether a scene is listening: the stranding
        // rule is about the graph, and a headless load has no `geometryDidSettle` to hang it off.
        // A restore here marks the geometry dirty again, so the pass below sees the restored state.
        settleStrandedControls()
        guard let geometryDidSettle, geometrySettle.takeChange() else { return }
        geometryDidSettle()
    }

    /// Report a resize to the scene, as Wasabi does: every object whose own box changed hears about
    /// its **own** new geometry, in its own parent's coordinates.
    ///
    /// `previous` is the pre-change frame per object; pass `nil` to seed the whole scene, which is the
    /// one dispatch that has to happen after `start()` — a script that only assigns state inside
    /// `onResize` (ClassicPro's `beat.m` sets `showBeat`/`showPromo` nowhere else) has none of it until
    /// the event has fired at least once, and the first `onPlay` then hides its display for good.
    /// (Its declaration follows `dispatchWindowMove` below.)

    /// The **window** moved on the desktop — Wasabi's `onMove()`, which takes no arguments and is
    /// addressed at the container and its active layout.
    ///
    /// A resize is a change inside the scene and every object hears it; a move is not, because
    /// nothing inside the window changed position relative to anything else. Only the window objects
    /// are told. Itemskin is what needs it: each of its component windows is drawn by a *second*,
    /// dynamic container holding the frame artwork, and `onMove` on the frame's layout is how the
    /// content window is pulled along when the user drags the frame (B69).
    @discardableResult
    func dispatchWindowMove(container: WasabiObject, layout: WasabiObject) -> Int {
        var dispatched = 0
        for object in (container === layout ? [container] : [container, layout]) {
            guard hasBinding(for: object, event: "onmove") else { continue }
            if (try? dispatch(object: object, event: "onmove")) != nil { dispatched += 1 }
        }
        return dispatched
    }

    /// Wasabi's `onUserResize` — a resize the user dragged, as against every other way a window's box
    /// can change. Addressed at the container and its active layout, the way `onMove` is: a skin
    /// binds it on the layout (Ebonite's standard frame does) and the box is the layout's own, so `x`
    /// and `y` are its canvas origin exactly as `onResize` reports them.
    @discardableResult
    func dispatchWindowUserResize(container: WasabiObject, layout: WasabiObject,
                                  size: CGSize) -> Int {
        let arguments: [MakiValue] = [.integer(0), .integer(0),
                                      .integer(Int32(clamping: Int(size.width.rounded()))),
                                      .integer(Int32(clamping: Int(size.height.rounded())))]
        var dispatched = 0
        for object in (container === layout ? [container] : [container, layout]) {
            guard hasBinding(for: object, event: "onuserresize") else { continue }
            if (try? dispatch(object: object, event: "onuserresize", arguments: arguments)) != nil {
                dispatched += 1
            }
        }
        return dispatched
    }

    /// Wasabi's `onScale(newScale)` — the layout's scale changed, which here is UI Size (B239). Skins
    /// that fill the screen from `viewport / getScale()` — Nitrous Audio's monitor mode — re-fit
    /// from it, or stay sized for the old scale.
    @discardableResult
    func dispatchLayoutScale(layout: WasabiObject, scale: CGFloat) -> Int {
        (try? dispatch(object: layout, event: "onscale", arguments: [.float(Double(scale))])) ?? 0
    }

    @discardableResult
    func dispatchResize(targets: [(object: WasabiObject, frame: CGRect)],
                        previous: [WasabiObjectID: CGRect]?) -> Int {
        var dispatched = 0
        // An object that has *left* the layout resized too, and it has to hear that exactly once.
        //
        // A pane collapsed to nothing takes its subtree out of the scene entirely: closing Big Bento's
        // side playlist leaves `player.component.playlist.frame` 0 wide, so `playlist.dualwnd` inside
        // it resolves to `w = 0 − 10` and the negative-box rule drops it and everything under it. The
        // group that reacts to the close — `player.component.playlist`, whose `onResize` is where
        // `pledit.maki` gives the tab area its width back — is inside that subtree, so it was never
        // told, and the SUI content kept the 335px hole the open playlist had left in it on every tab.
        //
        // Wasabi resizes a window to nothing rather than forgetting about it, so that is what this
        // does: the vanished object hears its old origin at 0×0, once, and then drops out of
        // `previous` because the caller records the new target set.
        vanishedResizeTargetsForTesting = []
        if let previous {
            let present = Set(targets.map(\.object.stableID))
            for (id, before) in previous where !present.contains(id) {
                vanishedResizeTargetsForTesting.append(id)
                guard let object = loadedSkin.runtime.graph.object(withID: id),
                      hasBinding(for: object, event: "onresize") else { continue }
                let origin: [MakiValue] = [.integer(Int32(clamping: Int(before.minX))),
                                           .integer(Int32(clamping: Int(before.minY)))]
                dispatched += (try? dispatch(object: object, event: "onresize",
                                             arguments: origin + [.integer(0), .integer(0)])) ?? 0
            }
        }
        for target in targets {
            if let previous, let before = previous[target.object.stableID], before == target.frame {
                continue
            }
            let frame = target.frame
            let arguments: [MakiValue] = [.integer(Int32(clamping: Int(frame.minX))),
                                          .integer(Int32(clamping: Int(frame.minY))),
                                          .integer(Int32(clamping: Int(frame.width))),
                                          .integer(Int32(clamping: Int(frame.height)))]
            dispatched += (try? dispatch(object: target.object, event: "onresize",
                                         arguments: arguments)) ?? 0
        }
        return dispatched
    }
}
