import AppKit
import CoreGraphics
import Foundation

/// Rendering refusals that the provider can treat as donor-wide policy decisions.
/// A nil artwork result instead means no usable artwork for that request.
enum WMPHostedFrameRefusal: Error {
    case panelCannotBeSliced
    /// The diagnostic piece assembler found an open edge. The provider drops that donor as a
    /// fallback policy; this does not prove it fails at every size. The default whole-donor path
    /// uses gaps for repair and does not throw this refusal.
    case ringDoesNotClose
}

/// A donor selected from WMP markup for a native hosted window. Rings are rendered as the whole
/// donor view with donor-owned content, controls, readouts, and classified furniture subtracted;
/// fixed panels are nine-sliced around their resolved client hole. Selection metadata also supports
/// the older piece-assembly diagnostic path (`WMP_HOSTED_FRAME_WHOLE=0`).
///
/// Scene construction uses the normal WMP builder/renderer outside the live script runtime. The
/// default ring path renders at least at the donor floor, crops its painted extent, and maps that
/// image and client geometry onto the requested size. Insets come from resolved client geometry
/// with rail-aware rack reclamation, not raw bitmap widths (which may be mostly transparent).
struct WMPHostedFrameTemplate: Equatable, Sendable {
    /// The view the ring was taken from.
    let viewID: String
    /// Selected ring pieces by stable ID, used by selection, repair classification, and the
    /// diagnostic assembler. This is not a paint whitelist for the default whole-donor path.
    let ringNodeIDs: Set<Int>
    /// Ring pieces that must be given the **window's own height** before the frame is built, and
    /// those that must be given its width (W209).
    ///
    /// **A tiled edge piece with no authored length is resized by the skin's own script**, and the
    /// frame build runs no script: it is a private builder over a private image store, deliberately
    /// outside the runtime that is driving the skin the user is looking at. `Alienware Invader`
    /// resizes its rails in `onResize="resizeListBox();onPlResize();"`, so the lower half of both
    /// sides was drawn one bitmap tall — 0.231 of each side bare, which is the gap reported on
    /// 2026-09-16 — while the skin's own window looks right. Tiling *is* the statement that the
    /// piece repeats to fill its side, so the span is given to it here rather than inferred from
    /// pixels: an override on this build alone, in the same place the donor's resize floor is
    /// lifted.
    let stretchedDownNodeIDs: Set<Int>
    let stretchedAcrossNodeIDs: Set<Int>
    /// The pieces admitted **beyond** the first in each slot (W209), which are trusted less than
    /// the eight: they are dropped at render time wherever they turn out to lie inside the client
    /// hole. Markup cannot answer that — `Alienware Invader`'s rack pieces are anchored to the same
    /// left edge as its rails, and only their resolved frames separate the two — so it is asked of
    /// the built scene, where the hole is a rectangle and every piece has a frame.
    let extraNodeIDs: Set<Int>
    /// The stretched client subview whose resolved frame is the content hole.
    let clientNodeID: Int
    /// Selected top-right corner node, retained to measure legacy corner-width metadata.
    /// Borrowed close hit testing uses the capped 40×26-point corner target, not this node's width.
    let topRightNodeID: Int?
    /// The donor's declared floor, used by default whole-donor rendering before extent-to-target
    /// scaling. Diagnostic whole-without-floor and piece-assembly variants bypass that clamp.
    let minimumSize: CGSize

    /// The donor view node itself, so the floor can be overridden for the frame build alone.
    let viewNodeID: Int

    /// The **one-piece panel** this frame is nine-sliced from, where the skin lends a panel rather
    /// than a ring (W207), or nil for the eight-piece ring every field above describes.
    ///
    /// **Over half the corpus has no ring at all.** Measured at the library's own default size on
    /// 2026-09-16: 88 of 185 installed archives lend one and **97 lend nothing**, so for the larger
    /// half a `.wmz` coloured our windows and could not shape them. But 77 of those 97 do declare a
    /// window style — as *one fixed bitmap with the list inset inside it*, which is how a 2000-era
    /// skin draws a drawer: `anemone`'s `<subview id="playlisttray" backgroundImage="trayplaylist.bmp">`
    /// is 328x261 with its `<ITEMSPLAYLIST>` at 83,72 155x116. There are no authored edges to
    /// stretch, which is why the ring rule rejected them, and none are needed: **the hole states the
    /// four slice lines**, so the panel resizes as an ordinary nine-patch (margins 83/72/90/73 here).
    /// **48 of the 77 have the hole inset on all four sides** and are the population this serves;
    /// the other 30 put it flush to an edge and are a follow-up row rather than a zero-width border.
    ///
    /// Only where the skin has no ring: a ring is laid out by its author for every size and a slice
    /// is inferred, so a skin that lends both lends the ring. The 88 come out unchanged.
    /// Its frame is resolved from the scene like the client hole's, because a panel is a subview of
    /// a whole player rather than a window of its own and the artwork has to be cropped to it.
    var panelNodeID: Int? = nil

    /// **W209 prototype — the whole donor view, minus what is the skin's own (`WMP_HOSTED_FRAME_WHOLE=1`,
    /// or `defaults write com.nullplayer.NullPlayer WMPHostedFrameWholeView -bool YES`).**
    ///
    /// Every rule above selects *pieces* and reassembles them, and every open item on W209 is
    /// downstream of that: the extent crop, the bare-edge measurement, the ring-open refusal, the
    /// second "repairing" build, the logo plate composited after measurement, and the missing right
    /// rail that lives in a drawer the direct-children walk cannot reach. The reporter's own
    /// observation is that *the skin's playlist has none of these defects* — because the playlist is
    /// not reassembled, it is simply drawn.
    ///
    /// So this inverts the default: draw the donor view whole, and **subtract** the subtrees that
    /// are the skin's rather than the frame's — the client hole's own contents, every control, and
    /// every readout. What is left is the picture the skin drew, at our window's size.
    var excludedNodeIDs: Set<Int> = []

    /// Whether the donor view is drawn whole. **On.** `WMP_HOSTED_FRAME_WHOLE=0` restores the
    /// piece-selecting assembler it replaced, which is the comparison every number in W209's case
    /// study was measured against (`reference/skins/back-to-the-future-trilogy.md`).
    static let drawsWholeDonorView: Bool =
        ProcessInfo.processInfo.environment["WMP_HOSTED_FRAME_WHOLE"] != "0"

    /// Whether the whole-view build obeys the donor's own declared floor and scales down below it.
    /// **On.** `WMP_HOSTED_FRAME_WHOLE=1` draws whole but unclamped, which is the isolated
    /// comparison that separated the floor's contribution from the whole-view render's.
    static let wholeDonorViewObeysFloor: Bool =
        ProcessInfo.processInfo.environment["WMP_HOSTED_FRAME_WHOLE"] != "1"

    // MARK: - Derivation

    /// The eight places a ring piece can be anchored. A piece is classified by its *alignment*
    /// alone: that is the property the skin uses to keep the ring together while the window resizes,
    /// and it is readable without resolving a single expression.
    private enum Role: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

        init?(horizontal: WMPAxisAlignment, vertical: WMPAxisAlignment) {
            switch (horizontal, vertical) {
            case (.leading, .leading): self = .topLeft
            case (.stretch, .leading): self = .top
            case (.trailing, .leading): self = .topRight
            case (.leading, .stretch): self = .left
            case (.trailing, .stretch): self = .right
            case (.leading, .trailing): self = .bottomLeft
            case (.stretch, .trailing): self = .bottom
            case (.trailing, .trailing): self = .bottomRight
            // **A side is often drawn by more than one piece, and the middle one is anchored to the
            // *centre* of that side (W209).** `Alienware Invader` builds each rail out of three
            // subviews — `pl_left_tile.png` stretched from `top="60"`, `pl_left_mid.png` at
            // `verticalAlignment="center"`, and `pl_left_tile2.png` tiled from
            // `top="wmpprop:plLeftCenter.top"` — so a ring that takes one piece per side drew the
            // upper rail and nothing below the ornament. That is the gap the reporter saw on
            // 2026-09-16: *"alienware has gaps in its playlist still"*, 0.231 of both sides bare.
            case (.leading, .center): self = .left
            case (.trailing, .center): self = .right
            case (.center, .leading): self = .top
            case (.center, .trailing): self = .bottom
            default: return nil
            }
        }

        static let corners: Set<Role> = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    /// Pick the best ring in the skin, or answer nil when it has none.
    ///
    /// `playerViewID` is the view the app is presenting as the player. It is ranked last rather than
    /// excluded: the player's own body is what the user is already looking at, so wearing it on a
    /// spectrum window is the least interesting answer — but a skin whose *only* ring is there
    /// (`NVIDIA`, `WALL-E`) still has one, and one is better than none.
    static func derive(from skin: WMPLoadedSkin, playerViewID: String?) -> WMPHostedFrameTemplate? {
        var best: (template: WMPHostedFrameTemplate, score: Int)?
        for registration in skin.views {
            guard let candidate = template(for: registration) else { continue }
            // The ring's completeness is the score: an eight-piece ring resizes cleanly in both
            // axes, a four-corner one has gaps the skin filled some other way.
            // **The score is filled slots, not pieces.** A ring's completeness is what it measures,
            // and counting the repair-only extras with them re-ranked whole skins: `Project Gotham
            // Racing 2` has 8 slots in its playlist and 12 pieces in its video view, so the video
            // view won a contest it had already lost on the merits (W209).
            var score = candidate.ringNodeIDs.subtracting(candidate.extraNodeIDs).count
            // A panel that holds something — a playlist, a visualiser, a video surface — is the
            // window this skin means by "one of my windows". Several skins wrap the *same* ring
            // around an `upgradeView`, the nag panel a 2002 skin shows a player too old to run it,
            // and picking that one is picking the copy nothing was ever meant to look at.
            if hostsContent(registration.node) { score += 4 }
            if let playerViewID, registration.id.caseInsensitiveCompare(playerViewID) == .orderedSame {
                score -= 100
            }
            if best == nil || score > best!.score { best = (candidate, score) }
        }
        if let best { return best.template }
        // **No ring anywhere in the skin: take a panel instead (W207).** Ranked strictly below the
        // ring rather than scored against it — a ring is laid out by its author at every size and a
        // slice is inferred from the hole, so a skin that states both has already said which it
        // means. Reached by 97 of the 185 installed archives, 48 of which lend a panel.
        return panelTemplate(from: skin)
    }

    /// The smallest panel in the skin that states a hole, over every view.
    ///
    /// **Innermost wins, and that is the whole of the ranking.** A list is inside a drawer which is
    /// inside a player, and all three are containers with artwork of their own: `Creed` offers its
    /// 466x400 body and its 226x204 `PlaylistDrawer`, `Cubist` its 508x189 body and its 190x178
    /// `sPl`. The drawer is the window the skin drew; the body is the player the user is already
    /// looking at, and lending *that* is the ring path's own rejected answer (`derive` scores the
    /// player view -100 for the same reason).
    private static func panelTemplate(from skin: WMPLoadedSkin) -> WMPHostedFrameTemplate? {
        var best: (template: WMPHostedFrameTemplate, depth: Int, area: CGFloat)?
        for registration in skin.views {
            walk(registration.node) { node in
                guard node.kind == .view || node.kind == .subview,
                      hasBackgroundImage(node),
                      // `Gorillaz`'s rule, one tier up: a tiled swatch is a ground, not a panel.
                      literal(node, "backgroundTiled")?.caseInsensitiveCompare("true") != .orderedSame,
                      let hole = firstHole(in: node),
                      // **A player body with a list in it is not a window frame (W207).** The ring
                      // path says this by scoring the player view -100; a panel is a subview, so
                      // the same question has to be asked of the artwork itself, and what answers
                      // it is the *transport*. `Erektorset`'s panel is its whole player — EQ graph,
                      // ten band sliders, volume and balance all baked into the bitmap — and
                      // slicing it produces a picture of a player with a hole punched in its left
                      // third. A drawer carries the list and its own close box and nothing else:
                      // `anemone`'s tray is one `<BUTTON>`, and its *equaliser* tray, which does
                      // carry the controls, is rejected here and was never the candidate anyway.
                      // Area cannot ask this — `anemone`'s tray is 99.5% of its player's canvas.
                      !carriesTransport(node)
                else { return }
                // **The four slice lines are checked wherever they are readable.** A panel that
                // declares its own size states them in markup and is rejected here; a panel sized by
                // its own bitmap has no markup to read — 2000-era authoring leaves the size off
                // constantly — and is checked against the *resolved* frames in `panelArtwork`, which
                // is the same guard one build later. Deriving stayed markup-only either way.
                let size = authoredSize(node)
                if let size, let holeFrame = authoredFrame(hole, relativeTo: node) {
                    let margins = [holeFrame.minX, holeFrame.minY,
                                   size.width - holeFrame.maxX, size.height - holeFrame.maxY]
                    guard margins.allSatisfy({ $0 >= minimumBorder }) else { return }
                }
                // **Innermost wins, and depth is how that is asked without a size.** A list is
                // inside a drawer inside a player and all three carry artwork: `Creed` offers its
                // 466x400 body and its 226x204 `PlaylistDrawer`, `Cubist` its 508x189 body and its
                // 190x178 `sPl`. The drawer is the window the skin drew; the body is the player the
                // user is already looking at, and lending *that* is the ring path's own rejected
                // answer (`derive` scores the player view -100 for the same reason).
                let depth = ancestorCount(of: node)
                let area = size.map { $0.width * $0.height } ?? .greatestFiniteMagnitude
                if let current = best,
                   (depth, -area) <= (current.depth, -current.area) { return }
                best = (WMPHostedFrameTemplate(
                    viewID: registration.id,
                    ringNodeIDs: [],
                    stretchedDownNodeIDs: [],
                    stretchedAcrossNodeIDs: [],
                    extraNodeIDs: [],
                    clientNodeID: hole.stableID,
                    topRightNodeID: nil,
                    minimumSize: .zero,
                    viewNodeID: registration.node.stableID,
                    panelNodeID: node.stableID), depth, area)
            }
        }
        return best?.template
    }

    /// Whether a container holds any of the player's own controls. Transport, the three host
    /// sliders and the equaliser — the elements that make a panel a *player* rather than a frame.
    /// A plain `<BUTTON>` is deliberately not in the list: a drawer's close box is one, and so is
    /// every decorative button a skin paints inside its own panel.
    private static func carriesTransport(_ node: WMPNode) -> Bool {
        for child in node.children {
            switch child.kind {
            case .playButton, .pauseButton, .stopButton, .prevButton, .nextButton,
                 .rewButton, .ffwdButton, .muteButton, .repeatButton, .shuffleButton,
                 .playElement, .pauseElement, .stopElement, .prevElement, .nextElement,
                 .rewElement, .ffwdElement,
                 .seekSlider, .volumeSlider, .balanceSlider, .equalizerSettings:
                return true
            default:
                if carriesTransport(child) { return true }
            }
        }
        return false
    }

    /// **A transport control does not have to be a transport *tag* (W209).** W208 refused a corner
    /// candidate that holds one of the typed elements above, which is how `Ice` spells its playlist
    /// shuffle (`<Repeatbutton>`). `Back to the Future Trilogy` spells the same pair of controls as
    /// a plain `<buttongroup>` of `<buttonelement>`s whose `onClick` is
    /// `player.settings.setMode('loop', down)` — nothing in the markup's *vocabulary* says transport
    /// — and it declares them six nodes before `f_top_left.png`, so first-declaration-wins handed
    /// the top-left corner to the skin's repeat and shuffle glyphs exactly as `Ice` handed over its
    /// bottom-left. Same defect, different spelling, so the rule is extended by what the control
    /// *does* rather than by widening it to everything clickable, which is the answer W208 measured
    /// and rejected (it costs 7 of the 88 rings — a resize grip and a close box are frame
    /// furniture).
    ///
    /// **The ring path only.** `carriesTransport` is shared with the panel path, and asking this
    /// question there costs six donors that the corpus says are right: `Gorillaz`'s panel — the
    /// skill's own counter-evidence for "a painted control is pixels, not nodes" — plus
    /// `deepbluesomething`, `HOB`, `Vario`, `Combat_Flight_Simulator_3` and `TDK`, all of which
    /// went from a frame to nothing when the rule was written into the shared helper. A panel is a
    /// whole drawer and may legitimately carry a scripted button somewhere inside it; a *ring
    /// piece* is one bitmap in one corner, and a corner that plays music is never right.
    private static func scriptsTransport(_ node: WMPNode) -> Bool {
        if isScriptedTransportControl(node) { return true }
        for child in node.children where scriptsTransport(child) { return true }
        return false
    }

    private static func isScriptedTransportControl(_ node: WMPNode) -> Bool {
        switch node.kind {
        case .button, .buttonGroup, .buttonElement, .repeatButton, .customSlider, .slider:
            break
        default:
            return false
        }
        for attribute in node.attributes {
            // **An event handler only.** `enabled`, `down` and the other bindings *read* the player
            // — `Combat_Flight_Simulator_3`'s zoom button is
            // `onClick="videoZoom();" enabled="wmpenabled:player.controls.stop"`, which greys itself
            // out when nothing is playing and controls nothing — and reading is what every skin's
            // own readout does. What makes a control the player's is what it does when pressed.
            guard attribute.name.lowercased().hasPrefix("on") else { continue }
            let script = attribute.rawValue.lowercased()
            guard script.contains("player.") || script.contains("settings.") else { continue }
            guard transportCalls.contains(where: { script.contains($0) }) else { continue }
            // **A control that leaves the window is furniture, whatever it does on its way out.**
            // `Combat_Flight_Simulator_3` closes its video view with
            // `player.controls.pause();} view.close();` and stops playback from the corner above it,
            // and both are its *close* box — the one control W208 measured as belonging in a corner.
            // Without this the skin's whole ring collapsed (no complete corner set) and a donor that
            // measures a perfect 0.000 on all four edges lent nothing at all.
            if navigationCalls.contains(where: { script.contains($0) }) { continue }
            return true
        }
        return false
    }

    /// What a script has to touch for the control that raises it to be the *player's*. Deliberately
    /// short: these are the calls that change what the user is listening to, which is the line W208
    /// drew. Reading or displaying a property is not on it — a skin's own caption binds
    /// `player.currentMedia.name` and is decoration.
    private static let transportCalls = [
        "settings.setmode", "controls.play", "controls.pause", "controls.stop", "controls.next",
        "controls.previous", "controls.fastforward", "controls.fastreverse",
        "settings.mute", "settings.volume", "settings.balance", "settings.rate",
    ]

    /// What a control does when it is a *window's* control rather than the player's: it goes
    /// somewhere. A close box that pauses on its way out is still a close box.
    private static let navigationCalls = [
        ".close(", "closeview", "currentviewid", "openview", "minimize", "returntomediacenter",
    ]

    /// Whether a node *is*, or wraps, something the user can press.
    ///
    /// `carriesTransport` asks the narrower question the panel path needs — is this the player's own
    /// control cluster. A ring piece has to refuse anything clickable at all, because a corner is a
    /// corner: `Ice`'s shuffle is a `<Repeatbutton>` (which `carriesTransport` does catch) but the
    /// same skin family wraps plain `<button>`s in edge-anchored subviews too, and one of those in a
    /// corner slot is the same defect.
    private static func isControl(_ node: WMPNode) -> Bool {
        for child in node.children {
            switch child.kind {
            case .button, .repeatButton, .buttonGroup, .slider, .customSlider, .popup:
                return true
            default:
                if isControl(child) { return true }
            }
        }
        return false
    }

    /// The narrowest border a slice line can leave. Below it the "frame" is a hole with a hairline
    /// around one side, which is not what a skin drew — 30 of the corpus's 77 panels put the list
    /// flush to an edge and are deliberately outside this landing.
    private static let minimumBorder: CGFloat = 4

    private static func ancestorCount(of node: WMPNode) -> Int {
        var count = 0
        var current = node.parent
        while let node = current { count += 1; current = node.parent }
        return count
    }

    private static func walk(_ node: WMPNode, _ body: (WMPNode) -> Void) {
        body(node)
        for child in node.children { walk(child, body) }
    }

    /// The list a panel is drawn around. Document order, and lists only: a panel's hole is where the
    /// skin puts *rows*, which is the one surface of ours that is the same shape as the donor's.
    private static func firstHole(in node: WMPNode) -> WMPNode? {
        for child in node.children {
            switch child.kind {
            case .playlist, .dropdownPlaylist, .listBox: return child
            default: if let found = firstHole(in: child) { return found }
            }
        }
        return nil
    }

    /// A node's own authored size. Declared where the markup declares it; a container sized by its
    /// artwork has no markup to read, so nil there — and a panel whose size is an expression is not
    /// a fixed bitmap panel at all.
    private static func authoredSize(_ node: WMPNode) -> CGSize? {
        guard let width = number(node, "width"), let height = number(node, "height"),
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    /// The hole's frame in the panel's coordinates, accumulated through any container between them.
    /// `anemone` states it directly on the panel; `Creed` and `Cubist` nest one subview in between.
    private static func authoredFrame(_ hole: WMPNode, relativeTo panel: WMPNode) -> CGRect? {
        var x: CGFloat = 0, y: CGFloat = 0
        var node: WMPNode? = hole
        while let current = node, current !== panel {
            guard let left = number(current, "left"), let top = number(current, "top") else {
                return nil
            }
            x += left; y += top
            node = current.parent
        }
        guard node === panel, let width = number(hole, "width"), let height = number(hole, "height"),
              width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func template(for registration: WMPViewRegistration) -> WMPHostedFrameTemplate? {
        let view = registration.node
        var ring: [Role: WMPNode] = [:]
        var pieces: [WMPNode] = []
        var stretchedDown: Set<Int> = []
        var stretchedAcross: Set<Int> = []
        var extras: Set<Int> = []
        var client: WMPNode?

        // Direct children only. A ring is laid out against the *window*, so its pieces are the
        // window's own children; a nested panel that happens to stretch is part of the skin's
        // content, not of its frame.
        for child in view.children where child.kind == .subview {
            let horizontal = WMPAxisAlignment(horizontal: literal(child, "horizontalAlignment"))
            let vertical = WMPAxisAlignment(vertical: literal(child, "verticalAlignment"))
            if hasBackgroundImage(child) {
                guard let role = Role(horizontal: horizontal, vertical: vertical) else { continue }
                // **A ring piece is decoration. A subview with a control in it is a control (W208).**
                //
                // The role is read off alignment alone, and a skin's own buttons are anchored to the
                // window's edges exactly as its corner bitmaps are — so they compete for the same
                // eight slots, and "first declaration wins" hands the slot to whichever the author
                // happened to write first. `Ice` writes its playlist shuffle button —
                // `<subview id="Plshuffle" horizontalAlignment="left" verticalAlignment="Bottom"
                // backgroundimage="Pl-shuffle.bmp">`, 26x24, wrapping a `<Repeatbutton>` — six nodes
                // *before* `Vid-bottomleft.bmp`, so every NullPlayer window wearing that ring got the
                // skin's shuffle glyph where its bottom-left corner should be, hanging outside the
                // frame's own curve. Reported 2026-09-16: *"you are still using the wrong piece on
                // the bottom left"*.
                //
                // This is the ring's half of a rule the panel path already states — a container
                // holding the player's controls is not a frame — and of the doctrine at the top of
                // this file: the donor's buttons are the skin's window, not ours. Borrowing one is
                // not merely ugly, it is a lie about what that glyph does.
                // **Transport only, deliberately.** Refusing *anything* clickable costs seven of
                // the corpus's 88 rings: a window's own resize grip and close box are plain
                // `<button>`s wrapped in edge-anchored subviews, and they are frame furniture — the
                // corner art *is* the grip in `Ice`'s own bottom-right. What must never be borrowed
                // is a control that claims to do something to the user's playback, which is exactly
                // the set `carriesTransport` already names for the panel path. Measured: this leaves
                // all 88 ring lines standing and moves only the corners a transport control had
                // taken.
                // **The script-based half is asked of the four corners only.** The typed rule
                // above is W208's and applies to every slot; this one reaches deeper — it inspects
                // handlers rather than tags — and asked of the edges it moved seven donors' client
                // holes and refused five rings that measured a clean 0.000 (`AlienMorph`,
                // `ALXMorph`, `ALXVortex`, `AlienwareTeleport`, `Project…`), because a slot it
                // emptied was filled by the next declaration and the ring no longer met. Both
                // reported cases are corners — `Ice`'s bottom-left, `Back to the Future Trilogy`'s
                // top-left — and a corner is where a skin paints its own window controls.
                let centred = horizontal == .center || vertical == .center
                let isExtra = centred || ring[role] != nil
                if carriesTransport(child) { continue }
                if scriptsTransport(child), Role.corners.contains(role) || isExtra { continue }
                // First declaration wins **for the role**, matching the duplicate-id rule elsewhere
                // in the engine: a skin that layers two bitmaps in one corner authored the lower one
                // first. That decides which piece *names* the slot — which corners exist, and which
                // bitmap the close control has to clear.
                // **A centre-anchored piece never claims a slot.** The eight alignment pairs are
                // the ring as every rule before this one measured it, and letting a `center` piece
                // hold one displaces the real edge bitmap into the extras — which refused five
                // clean rings and moved seven donors' client holes when it was first tried. It is
                // admitted below, as a repair, which is the only thing it was ever needed for.
                if !centred, ring[role] == nil {
                    ring[role] = child
                    pieces.append(child)
                    note(child, role, &stretchedDown, &stretchedAcross)
                    continue
                }
                // **But the ring is every piece, not eight of them (W209).** A side is routinely
                // drawn by two or three subviews — `Alienware Invader`'s rails are a tile, a centre
                // ornament and a second tile, the last of which declares no alignment at all and so
                // lands in the top-left slot behind the corner that already holds it — and taking
                // one piece per slot left a quarter of both sides bare. Later pieces are drawn as
                // well as the first; only the slot's identity is exclusive.
                //
                // **A later piece must not be clickable**, and that is a narrower rule than the
                // slots' own (W208 measured that refusing everything clickable costs 7 rings,
                // because a resize grip and a close box are frame furniture in a *corner*). A
                // second bitmap anchored to the middle of an edge is a different population: it is
                // where a skin paints its logo — `Back to the Future Trilogy`'s `f_logo.png` wraps
                // a button that opens the film's website — and a NullPlayer window is not the place
                // to advertise it.
                pieces.append(child)
                extras.insert(child.stableID)
                note(child, role, &stretchedDown, &stretchedAcross)
            } else if horizontal == .stretch, vertical == .stretch, client == nil {
                client = child
            }
        }

        guard Role.corners.isSubset(of: Set(ring.keys)), let client else { return nil }
        return WMPHostedFrameTemplate(
            viewID: registration.id,
            ringNodeIDs: Set(pieces.map(\.stableID)),
            stretchedDownNodeIDs: stretchedDown,
            stretchedAcrossNodeIDs: stretchedAcross,
            extraNodeIDs: extras,
            clientNodeID: client.stableID,
            topRightNodeID: ring[.topRight]?.stableID,
            minimumSize: CGSize(width: number(view, "minWidth") ?? number(view, "width") ?? 0,
                                height: number(view, "minHeight") ?? number(view, "height") ?? 0),
            viewNodeID: view.stableID,
            excludedNodeIDs: notOurs(view, client: client)
        )
    }

    /// Everything in the donor view that is the **skin's own**, as stable ids, for the whole-view
    /// path to subtract (W209 prototype).
    ///
    /// The selecting rules above ask "is this piece frame?" and answer no by default, which is why
    /// a rail nested in a drawer, a tile sized by script and a plate over a join all fall out. This
    /// asks the opposite question, and the three things it subtracts are the three the doctrine at
    /// the top of this file names: the donor's **content** (its list, video and effects surfaces —
    /// ours goes in the hole), its **controls** (a borrowed button is a lie about what it does), and
    /// its **readouts** (a caption bound to the skin's own player state, stale on our window).
    ///
    /// Whole subtrees, because a `BUTTONGROUP`'s mapping image and a `PLAYLIST`'s rows are painted
    /// by descendants with ids of their own. The client subview itself is kept — it is where the
    /// donor's interior fill is painted, and the fill is what `erasingInteriorFill` opens.
    /// Whether the node is itself something the user can press, as opposed to wrapping one.
    private static func isControlKind(_ node: WMPNode) -> Bool {
        switch node.kind {
        case .button, .repeatButton, .buttonGroup, .slider, .customSlider, .popup,
             .volumeSlider, .seekSlider, .balanceSlider:
            return true
        default:
            return false
        }
    }

    /// Whether a control does nothing but resize or move the window it is drawn on.
    ///
    /// These are the corner and edge grips: `view.size('topright')`, `view.dragMove()`. They are
    /// authored as buttons because that is the only node a `.wmz` can hang a mouse handler on, and
    /// the image they carry is the window's own corner rather than a glyph — W193 counted 235
    /// `view.size(corner)` calls in the corpus, every one of them on `onMouseDown`. A control that
    /// also reaches player state is not one of these.
    private static func isWindowGeometryGrip(_ node: WMPNode) -> Bool {
        let handlers = ["onmousedown", "onmouseup", "onclick", "ondblclick", "onmousemove"]
            .compactMap { literal(node, $0)?.lowercased() }
        guard !handlers.isEmpty else { return false }
        let script = handlers.joined(separator: ";")
        guard script.contains("view.size") || script.contains("view.dragmove") else { return false }
        return !script.contains("player.")
    }

    private static func notOurs(_ view: WMPNode, client: WMPNode) -> Set<Int> {
        var excluded: Set<Int> = []
        func subtree(_ node: WMPNode) {
            excluded.insert(node.stableID)
            for child in node.children { subtree(child) }
        }
        for child in client.children { subtree(child) }
        // **A subview whose background image *is* a control's image is that control's backing.**
        // Dropping the control alone is not enough: `Back to the Future Trilogy` spells every one
        // of its window controls as `<subview backgroundImage="pl_shuff_no.png">` wrapping a
        // `<buttongroup image="pl_shuff_no.png">`, so the glyph is painted twice and the subview's
        // copy survived — the loop and shuffle pair in the top-left corner, the close box in the
        // top-right, the resize grip in the bottom-right, all borrowed onto a NullPlayer window
        // that has its own.
        //
        // The same image in both places is what separates a backing from a plate: the logo subview
        // beside it carries `f_logo.png` and wraps a button drawn from `f_logo_no.png`, and that
        // plate is frame — it covers the join between two pieces of the bottom bar, and leaving it
        // out is the notch reported three times.
        walk(view) { node in
            guard node.kind == .subview, let backing = literal(node, "backgroundImage") else { return }
            for child in node.children where Self.isControl(child) || Self.isControlKind(child) {
                for name in ["image", "backgroundImage"] where
                    literal(child, name)?.caseInsensitiveCompare(backing) == .orderedSame {
                    // **A resize grip is the window's corner, not a control's picture (W222).** The
                    // rule above reads "the same image in both places" as a glyph painted twice and
                    // drops the pair. `TheUnit` writes its top-right corner that way and the button
                    // in it does not press anything: `onmousedown="view.size('topright')"`, the
                    // artwork *is* the grip. Subtracting it took the rounded corner and the top of
                    // the right rail off every hosted window — reported 2026-09-17 as *"the issue
                    // is the right top corner"*, on every window at once, which is the signature of
                    // a piece the frame never had rather than one a window mislaid.
                    //
                    // So the backing stays and only the control goes, the way it does everywhere
                    // else: the walk below drops the button itself, our window keeps its own
                    // resize, and nothing of the skin's behaviour is borrowed. Window geometry is
                    // the whole exemption — a grip asks the *view* for its size and touches no
                    // player state, so a control that reaches `player.` is a glyph as before.
                    if Self.isWindowGeometryGrip(child) { continue }
                    subtree(node)
                    return
                }
            }
        }
        walk(view) { node in
            switch node.kind {
            case .button, .buttonGroup, .buttonElement, .slider, .customSlider, .volumeSlider,
                 .seekSlider, .balanceSlider, .progressBar, .popup, .editBox,
                 .playButton, .pauseButton, .stopButton, .prevButton, .nextButton, .rewButton,
                 .ffwdButton, .muteButton, .repeatButton, .returnButton, .shuffleButton,
                 .playElement, .pauseElement, .stopElement, .prevElement, .nextElement,
                 .rewElement, .ffwdElement,
                 .playlist, .dropdownPlaylist, .listBox, .video, .wmpVideo, .effects,
                 .equalizerSettings,
                 .text, .statusText, .currentPositionText, .durationText:
                subtree(node)
            default:
                break
            }
        }
        return excluded
    }

    /// Record an edge piece whose length its author left to script. Tiled, in a side role, with the
    /// dimension along that side unstated in markup: three conditions, all readable without
    /// resolving anything, and every one of them necessary — a piece with an authored height is
    /// saying how tall it is, and a piece that does not tile has nothing to repeat.
    private static func note(_ node: WMPNode, _ role: Role,
                             _ down: inout Set<Int>, _ across: inout Set<Int>) {
        guard literal(node, "backgroundTiled")?.caseInsensitiveCompare("true") == .orderedSame else {
            return
        }
        switch role {
        case .left, .right:
            if number(node, "height") == nil { down.insert(node.stableID) }
        case .top, .bottom:
            if number(node, "width") == nil { across.insert(node.stableID) }
        default:
            break
        }
    }

    /// Whether a view carries one of the surfaces a WMP panel exists to hold.
    private static func hostsContent(_ node: WMPNode) -> Bool {
        for child in node.children {
            switch child.kind {
            case .playlist, .dropdownPlaylist, .video, .wmpVideo, .effects, .listBox,
                 .equalizerSettings:
                return true
            default:
                if hostsContent(child) { return true }
            }
        }
        return false
    }

    private static func hasBackgroundImage(_ node: WMPNode) -> Bool {
        for name in ["backgroundImage", "background"] {
            guard let attribute = node.attribute(named: name) else { continue }
            if case .resource = attribute.value { return true }
        }
        return false
    }

    private static func literal(_ node: WMPNode, _ name: String) -> String? {
        node.attribute(named: name)?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ node: WMPNode, _ name: String) -> CGFloat? {
        WMPNumber.literal(node.attribute(named: name))
    }

    // MARK: - Producing artwork

    /// Render the ring for a window of `size` points.
    ///
    /// The donor view is built at the window's own size wherever its declared floor allows it, so
    /// the pieces land where the skin's alignment rules put them. Below that floor the frame is
    /// built at the floor and **scaled to fit**: the ring is the skin's, and a skin that says its
    /// panel is never narrower than 406px has not been asked what 275px looks like. The alternative
    /// — forcing every hosted window up to the donor's minimum — moves windows the user placed.
    func artwork(builder: WMPSceneBuilder, renderer: WMPRenderer, size: CGSize,
                 backingScale: CGFloat) async throws -> SkinnedSurfaceFrameArtwork? {
        guard size.width > 0, size.height > 0 else { return nil }
        if panelNodeID != nil {
            return try await panelArtwork(builder: builder, renderer: renderer, size: size,
                                          backingScale: backingScale)
        }
        // **The ring is assembled as the skin lays it out, and only repaired if it fails.** The
        // second pass gives every script-sized edge piece the span of its side (W209); it is a
        // repair, so it is reached only by a donor whose ring came out open, and every ring that
        // closes on the first pass is byte-identical to what it was before the rule existed —
        // measured over the corpus, and `Back to the Future Trilogy` is why the check matters:
        // stretching its tiles unconditionally moved its client hole and opened a gap on its right
        // edge that its own layout does not have.
        guard let first = try await composeRing(builder: builder, renderer: renderer, size: size,
                                                backingScale: backingScale, repairing: false)
        else { return nil }
        var assembled = first
        // **A view drawn whole cannot come *apart*, but it can still be drawn short (W212).**
        //
        // The frame build is a private builder outside the script runtime, so a side tile whose
        // height only the skin's own `onResize` ever sets keeps its bitmap's — `Alienware Invader`
        // sizes both its rails in `onPlResize()` and the borrowed frame carried a 20% bare band
        // down each side, which is the desktop showing through a 99pt rail on every hosted window.
        //
        // So the repair pass is reachable here, under the same rule as the ring path — only for a
        // frame whose own edges came out bare — and under two more, because this is the attempt
        // that was measured, reverted and recorded as a dead end (`W212`): the furniture
        // classification is **pinned to the first pass**, where the pieces are the size their
        // author drew them, and the repair is accepted only if it closes the gap *and* leaves the
        // donor's client hole exactly where the first pass put it. A repair that moves the hole is
        // rewriting the window, not closing a seam.
        if Self.drawsWholeDonorView {
            // `edgeGaps` is [top, left, bottom, right]. **Only the side that came out bare is
            // spanned**: giving this donor's top tile the width of the canvas as well painted its
            // white filler straight over both side rails, because the tile is drawn after them.
            let down = Self.edgeCameOutBare(max(first.gaps[1], first.gaps[3]),
                                            along: size.height)
            let across = Self.edgeCameOutBare(max(first.gaps[0], first.gaps[2]),
                                              along: size.width)
            if down || across,
               down ? !stretchedDownNodeIDs.isEmpty : !stretchedAcrossNodeIDs.isEmpty,
               let repaired = try await composeRing(builder: builder, renderer: renderer, size: size,
                                                    backingScale: backingScale, repairing: true,
                                                    spans: (down, across),
                                                    pinnedFurniture: first.furniture),
               repaired.gap < first.gap,
               // **The hole may not move.** Not the donor's client rect — the *window's* content
               // rect, which is the client rect mapped through the frame's own extent: stretching
               // a tile down paints further than the first pass did, the alpha bounding box grows
               // with it, and the hole rides the crop. `KungFuChaos` and `The_Last_Samurai` are
               // both that shape — three edges closer to closed and 47pt of the window's interior
               // taken by a border that is not there.
               Self.sameHole(repaired.artwork.contentRect, first.artwork.contentRect) {
                assembled = repaired
            }
            return assembled.artwork
        }
        if first.gap > Self.ringEdgeGapLimit,
           !extraNodeIDs.isEmpty || !stretchedDownNodeIDs.isEmpty || !stretchedAcrossNodeIDs.isEmpty {
            if let repaired = try await composeRing(builder: builder, renderer: renderer, size: size,
                                                    backingScale: backingScale, repairing: true),
               repaired.gap < first.gap {
                assembled = repaired
            }
        }
        // **Thrown, not nil**: like the panel path's unslicable verdict, this is about the donor at
        // every size rather than about the window that asked.
        guard assembled.gap <= Self.ringEdgeGapLimit else {
            throw WMPHostedFrameRefusal.ringDoesNotClose
        }
        return assembled.artwork
    }

    /// One complete ring: built, grown if it falls short of its own view, cropped to its extent,
    /// measured for bare edges, and opened up so it can be painted over the content.
    private func composeRing(builder: WMPSceneBuilder, renderer: WMPRenderer, size: CGSize,
                             backingScale: CGFloat, repairing: Bool,
                             spans: (down: Bool, across: Bool) = (true, true),
                             pinnedFurniture: Set<Int>? = nil) async throws
        -> (artwork: SkinnedSurfaceFrameArtwork, gap: CGFloat, gaps: [CGFloat],
            furniture: Set<Int>, client: CGRect)? {
        guard var built = try await ringRender(builder: builder, renderer: renderer, canvas: size,
                                               backingScale: backingScale,
                                               repairing: repairing, spans: spans,
                                               pinnedFurniture: pinnedFurniture) else { return nil }

        // **A ring does not always reach the edges of its own view (W207).** `Ice`'s `plView` parks
        // a hidden drawer down its right side — every right-anchored piece is placed at
        // `view.width-163` and is 65 wide — so ~117pt of the canvas is authored empty, and the frame
        // we cut from it left the right sixth of every hosted window bare. Measured as the rendered
        // alpha's bounding box, which is the only place that shortfall is visible: the markup is a
        // pile of `jscript:` offsets and every one of them resolves.
        //
        // The answer is to give the ring the canvas it needs and then keep only the ring: build a
        // second time on a canvas grown by the shortfall, and crop to the extent. Exactly one extra
        // build, only for a donor that needs it — a ring that already fills its view measures a full
        // extent, takes neither branch, and comes out byte-identical.
        let shortfall = CGSize(width: size.width - built.extent.width,
                               height: size.height - built.extent.height)
        if shortfall.width > 1 || shortfall.height > 1 {
            let grown = CGSize(width: size.width + max(0, shortfall.width),
                               height: size.height + max(0, shortfall.height))
            if let second = try await ringRender(builder: builder, renderer: renderer, canvas: grown,
                                                 backingScale: backingScale,
                                                 repairing: repairing, spans: spans,
                                                 pinnedFurniture: pinnedFurniture) {
                built = second
            }
        }
        guard let cropped = built.image.cropping(to: CGRect(
            x: (built.extent.minX * backingScale).rounded(),
            y: (built.extent.minY * backingScale).rounded(),
            width: (built.extent.width * backingScale).rounded(),
            height: (built.extent.height * backingScale).rounded())) else { return nil }

        // **A ring that does not close is not a frame (W209).** Every rule above assumes the pieces
        // meet: the roles come from alignment, the insets from the client subview, and the extent
        // from the alpha — and all three resolve perfectly for a donor whose pieces only meet at
        // the *skin's own* layout. Nothing on the `HOSTED-FRAME` line can see that; the assembled
        // pixels can. The caller decides what to do with the number.
        let gaps = Self.edgeGaps(cropped, scale: backingScale) ?? [0, 0, 0, 0]
        let gap = gaps.max() ?? 0

        // The extent is the frame; map the client hole into it and then onto the window.
        let scaleX = built.extent.width > 0 ? size.width / built.extent.width : 1
        let scaleY = built.extent.height > 0 ? size.height / built.extent.height : 1
        var content = CGRect(x: (built.client.minX - built.extent.minX) * scaleX,
                             y: (built.client.minY - built.extent.minY) * scaleY,
                             width: built.client.width * scaleX, height: built.client.height * scaleY)
        let hole = content
        content = Self.reclaimingSideRacks(content, in: size)
        content = Self.clearOfTheDonorsOwnRail(content, hole: hole, in: cropped, size: size)
        // **Erase the interior fill so the frame can be painted whole (W209).** See
        // `SkinnedSurfaceFrameArtwork.paintsOverContent` for what the cut it replaces was costing.
        let opened = Self.erasingInteriorFill(cropped, content: content, size: size,
                                              scale: backingScale)
        // **The hole stays the client subview's, not the erased fill's bounding box.** Deriving it
        // from the pixels was tried and made the borders lopsided — 43pt on the left against 16 on
        // the right on `Back to the Future Trilogy`, because its left bezel dips into the subview
        // and its right does not. Reported as *"the left and right are not equal"*. The overhang it
        // was meant to trim no longer needs trimming: the frame is painted over the content now, so
        // the bezel covers whatever runs under it.
        return (SkinnedSurfaceFrameArtwork(
            image: opened?.image ?? cropped, size: size, contentRect: content,
            trailingCornerWidth: built.corner.map { $0 * scaleX },
            wasScaledToFit: abs(scaleX - 1) > 0.001 || abs(scaleY - 1) > 0.001,
            paintsOverContent: opened != nil), gap, gaps, built.furniture, built.client)
    }

    /// **A rack may be reclaimed only as far as the donor leaves it unpainted (W212).**
    ///
    /// `reclaimingSideRacks` hands a one-sided margin back to our content on the reading that a
    /// margin that deep is furniture rather than border. On `Alienware Invader` half of it is
    /// furniture and half is not: its `plView` states a 134pt left margin, of which 99pt is a
    /// three-piece rail it paints its own list *beside*, and the rule handed all 134 away. The
    /// frame is painted over the content (W209), so 54pt of every hosted window was laid out under
    /// an opaque rail — the grey column, reported 2026-09-17.
    ///
    /// **What separates the rail from the rack is neither position nor paint order** — both sit in
    /// the reclaimed strip, and this donor paints both after its list. It is that the rail is the
    /// donor's *own artwork* and the rack, once dropped, leaves bare canvas. So the strip is
    /// measured: how far in from the edge the donor paints something that is neither transparent
    /// nor its interior fill.
    ///
    /// The fill has to be excluded or the measurement answers the opposite question. These border
    /// bitmaps carry the interior colour baked in for the skin's own list to cover — `f_right_tile`
    /// is 96px wide and its inner 73 are opaque `(255,255,255,255)` — so a run measured on alpha
    /// alone reads a 96pt right border and takes back the width the donor gives its own content. It
    /// is counted, not assumed, exactly as `erasingInteriorFill` counts it, and a donor whose
    /// interior is a picture has no fill to exclude and is left alone.
    ///
    /// The run is the **median** across the rows the hole spans, so a rail with a gap in it — this
    /// donor's side tiles are sized by a script the frame build never runs, leaving a 20% bare band
    /// down each side — still reads its own thickness.
    private static func clearOfTheDonorsOwnRail(_ content: CGRect, hole: CGRect,
                                                in image: CGImage, size: CGSize) -> CGRect {
        guard content.minX < hole.minX || content.maxX > hole.maxX else { return content }
        let width = image.width, height = image.height
        guard width > 0, height > 0, size.width > 0, size.height > 0, !hole.isEmpty else {
            return content
        }
        let pixelsX = CGFloat(width) / size.width, pixelsY = CGFloat(height) / size.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = pixels.withUnsafeMutableBytes({ bytes -> CGContext? in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return content }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        func key(_ index: Int) -> UInt32 {
            UInt32(pixels[index] >> 5) << 10 | UInt32(pixels[index + 1] >> 5) << 5
                | UInt32(pixels[index + 2] >> 5)
        }
        let y0 = max(0, Int((hole.minY * pixelsY).rounded(.down)))
        let y1 = min(height, Int((hole.maxY * pixelsY).rounded()))
        let x0 = max(0, Int((hole.minX * pixelsX).rounded(.down)))
        let x1 = min(width, Int((hole.maxX * pixelsX).rounded()))
        guard y1 - y0 >= 2, x1 - x0 >= 2 else { return content }
        var tally: [UInt32: Int] = [:]
        for y in y0..<y1 {
            let row = y * width * 4
            for x in x0..<x1 where pixels[row + x * 4 + 3] > 200 {
                tally[key(row + x * 4), default: 0] += 1
            }
        }
        let area = (x1 - x0) * (y1 - y0)
        guard area > 0 else { return content }
        // **A donor with no interior fill has nothing to exclude, and that is not a reason to stop
        // measuring (W219, `TheUnit`).** The fill is excluded because these border bitmaps carry the
        // interior colour baked in; a donor that paints *no* colour behind its own content — the
        // client subview's contents are ours and are subtracted, so its hole comes out transparent
        // — has no such colour, and the rule returned the rack unmeasured. That is the reclaim at
        // its most dangerous rather than its safest: nothing is known about the strip, and the
        // whole of it is handed away. Excluding nothing measures every opaque pixel in the strip as
        // border, which can only make the reclaim smaller.
        let candidate = tally.max(by: { $0.value < $1.value })
        let fill = (candidate.map { CGFloat($0.value) >= CGFloat(area) * 0.5 } ?? false)
            ? candidate?.key : nil

        func isBorder(_ index: Int) -> Bool {
            pixels[index + 3] > 200 && key(index) != fill
        }
        func median(_ runs: [Int]) -> CGFloat {
            guard !runs.isEmpty else { return 0 }
            return CGFloat(runs.sorted()[runs.count / 2])
        }
        // **The run tolerates a hole in the artwork, because these rails have one.** A strict run
        // of border pixels stops at the first that is not: `pl_left_tile` carries a one-pixel pure
        // white highlight 15px in, which reads as fill and answered a 13pt rail for a 99pt one. So
        // the run is the furthest point in from the edge at which the strip behind it is still
        // *mostly* painted — dense enough to be artwork, which a bare margin never is.
        //
        // **It starts where the donor starts painting, not at the window's edge (W219, `TheUnit`).** The
        // run assumed a border grows inwards from the edge; this one is the other way round.
        // `left_stretch.png` is 37px wide and its outer **30 are the transparency key** — the
        // window's own curved silhouette — with the rail in the inner 7, so a run anchored at the
        // edge is starved by 30 bare columns before it reaches any artwork and answers a rail of
        // zero. The 37pt rack then goes to our content whole, and because this donor keeps the
        // rectangular cut (`whole=no`) the cut erases the rail it was just handed: no left bezel on
        // any hosted window, our black ground running out to the window's edge. Skipping the bare
        // lead-in costs the rule nothing where a border does reach the edge — the skip is zero
        // there — and it is the *inner* end of the artwork that bounds our content either way.
        func run(_ row: Int, from edge: Int, step: Int, limit: Int) -> Int {
            var lead = 0
            while lead < limit, lead < width, pixels[row + (edge + lead * step) * 4 + 3] <= 200 {
                lead += 1
            }
            guard lead < limit else { return 0 }
            var painted = 0, reached = 0
            for offset in lead..<limit where offset < width {
                guard isBorder(row + (edge + offset * step) * 4) else { continue }
                painted += 1
                // Dense enough behind it to be artwork, and the run ends on the artwork rather
                // than on the slack the density test allows past it.
                if painted * 5 >= (offset - lead + 1) * 4 { reached = offset + 1 }
            }
            return reached
        }
        var fromLeft: [Int] = [], fromRight: [Int] = []
        for y in y0..<y1 {
            let row = y * width * 4
            fromLeft.append(run(row, from: 0, step: 1, limit: x0))
            fromRight.append(run(row, from: width - 1, step: -1, limit: width - x1))
        }
        // Never past the donor's own hole: the rail is a floor under the reclaim, not a new border.
        let left = min(hole.minX, max(content.minX, median(fromLeft) / pixelsX))
        let right = min(size.width - hole.maxX, max(size.width - content.maxX, median(fromRight) / pixelsX))
        guard left > content.minX || right > size.width - content.maxX else { return content }
        return CGRect(x: left, y: content.minY, width: max(0, size.width - left - right),
                      height: content.height)
    }

    /// Remove the ring's **interior fill** — the flat colour a donor paints behind its own content —
    /// from the client rect, leaving every other pixel the skin drew there.
    ///
    /// The fill is found, not assumed: the most common opaque colour inside the client rect. That is
    /// the one thing about someone else's chrome that can be *counted* rather than inferred, which
    /// is the distinction the four dead title-bar rules were on the wrong side of. A donor whose
    /// interior is a picture has no such colour — its most common one is a few percent of the rect —
    /// and is answered nil, so the caller keeps cutting the hole as it always has.
    ///
    /// Nil also when the erase leaves the rect still substantially painted: whatever is left there
    /// would be drawn over the user's content, which is the failure the cut exists to prevent.
    private static func erasingInteriorFill(_ image: CGImage, content: CGRect, size: CGSize,
                                            scale: CGFloat) -> (image: CGImage, opening: CGRect)? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, scale > 0, !content.isEmpty,
              size.width > 0, size.height > 0 else { return nil }
        // The artwork's pixels per point. The crop above can leave the image a point or two off the
        // window, so the rect is mapped through the image's own scale rather than the backing one.
        let pixelsX = CGFloat(width) / size.width, pixelsY = CGFloat(height) / size.height
        let hole = CGRect(x: (content.minX * pixelsX).rounded(.down),
                          y: (content.minY * pixelsY).rounded(.down),
                          width: (content.width * pixelsX).rounded(),
                          height: (content.height * pixelsY).rounded())
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard hole.width >= 2, hole.height >= 2 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = pixels.withUnsafeMutableBytes({ bytes -> CGContext? in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let x0 = Int(hole.minX), y0 = Int(hole.minY)
        let x1 = min(width, Int(hole.maxX)), y1 = min(height, Int(hole.maxY))
        // Quantised to 8 levels an axis: these fills are flat, and two neighbouring pixels of a
        // gradient must not count as two different colours.
        var tally: [UInt32: Int] = [:]
        var opaque = 0
        for y in y0..<y1 {
            let row = y * width * 4
            for x in x0..<x1 where pixels[row + x * 4 + 3] > 200 {
                opaque += 1
                let key = UInt32(pixels[row + x * 4] >> 5) << 10
                    | UInt32(pixels[row + x * 4 + 1] >> 5) << 5
                    | UInt32(pixels[row + x * 4 + 2] >> 5)
                tally[key, default: 0] += 1
            }
        }
        let area = (x1 - x0) * (y1 - y0)
        guard area > 0, let fill = tally.max(by: { $0.value < $1.value }),
              // A fill is a fill when it is most of what is painted in there. Below this the
              // interior is a picture and there is nothing to erase.
              CGFloat(fill.value) >= CGFloat(area) * 0.5 else { return nil }
        // **The fill is one connected region, and its extent is the skin's content area.**
        //
        // The client subview states where the donor puts its *list*; the area the skin actually
        // paints its content colour over can be larger, and in `Back to the Future Trilogy` it is:
        // the black runs below the client rect into a tab in the bottom bar, where the skin plates
        // it with its logo. Deriving the hole from the subview alone left our graph stopping short
        // of that, and the strip of the skin's own black below it read as a notch hanging out of
        // the border — reported four times, and correctly: *"you are creating this notch, it is not
        // in the art"*. It was our content being too small for the opening, not artwork.
        //
        // So the fill is flooded from the client rect, erased wherever it reaches, and **the hole
        // is its bounding box**. Our content then covers every pixel the donor filled, which is
        // exactly what the donor's own window does. Nothing of the border is repainted: the flood
        // only clears the content colour, and the frame — drawn over the content since this change
        // — puts every bezel, corner and plate back on top of whatever overhangs.
        //
        // Two earlier attempts failed either side of this. Erasing the tab without growing the hole
        // left a gap the window's backing showed through; filling that gap from the nearest
        // surviving pixel painted it with the black above it. Both *made* the tab they were
        // chasing.
        func isFill(_ index: Int) -> Bool {
            guard pixels[index + 3] > 0 else { return false }
            let key = UInt32(pixels[index] >> 5) << 10
                | UInt32(pixels[index + 1] >> 5) << 5
                | UInt32(pixels[index + 2] >> 5)
            return key == fill.key
        }
        var queue: [Int] = []
        var seen = [Bool](repeating: false, count: width * height)
        for y in y0..<y1 {
            for x in x0..<x1 where isFill((y * width + x) * 4) && !seen[y * width + x] {
                seen[y * width + x] = true
                queue.append(y * width + x)
            }
        }
        var flooded: [Int] = []
        var minX = width, minY = height, maxX = -1, maxY = -1
        var head = 0
        while head < queue.count {
            let cell = queue[head]; head += 1
            let x = cell % width, y = cell / width
            flooded.append(cell)
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height, !seen[ny * width + nx],
                      isFill((ny * width + nx) * 4) else { continue }
                seen[ny * width + nx] = true
                queue.append(ny * width + nx)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // **The hole never grows past the client subview.**
        //
        // Letting the flood's own bounding box be the hole was tried and reported wrong twice in one
        // pass: our content then reaches below the donor's bezel and over its bottom bar — on the
        // waveform window the black ran straight over the skin's logo — and out to the right edge,
        // because a donor whose border is painted in the same colour as its content area gives the
        // flood nothing to stop at. The subview is the skin's statement of where content goes, and
        // it stands. The flood's only job is to find the fill *inside* it, so a bezel that dips into
        // the rectangle is not mistaken for content.
        minX = max(minX, x0); minY = max(minY, y0)
        maxX = min(maxX, x1 - 1); maxY = min(maxY, y1 - 1)
        guard maxX >= minX, maxY >= minY else { return nil }
        // Erase only what the accepted hole covers. Outside it the fill is the donor's border and
        // is not ours to touch — clearing it was what produced the tab in the first place.
        for cell in flooded {
            let x = cell % width, y = cell / width
            guard x >= minX, x <= maxX, y >= minY, y <= maxY else { continue }
            for channel in 0..<4 { pixels[cell * 4 + channel] = 0 }
        }
        var remaining = 0
        for y in y0..<y1 {
            let row = y * width * 4
            for x in x0..<x1 where pixels[row + x * 4 + 3] > 200 { remaining += 1 }
        }
        // **What may survive the erase, and the two measurements that bound it.** Whatever is left
        // is painted over the user's content, so the bar is how much of their window the donor may
        // keep. `Back to the Future Trilogy` keeps **5.8%** at the live window's 357x238 — its
        // inner bezel and the tab that rises through the bottom bar, which is frame and has to be
        // drawn. `Alienware Invader` keeps **19%** — an album-art panel, a search box and a list
        // rack baked into one 190pt corner bitmap (pixels rather than nodes, the `Gorillaz` rule),
        // which would sit on top of the library's rows. Between them, and it is the *size the
        // window actually is* that has to be measured: at 550x464 the same BTTF frame keeps 2%, so
        // a bar set from a probe at one size passed there and failed at the size on screen, which
        // is how three rounds of fixes changed nothing the reporter could see.
        let leftover = CGFloat(remaining) / CGFloat(area)
        guard leftover <= 0.10, let made = context.makeImage() else { return nil }
        let opening = CGRect(x: CGFloat(minX) / pixelsX, y: CGFloat(minY) / pixelsY,
                             width: CGFloat(maxX - minX + 1) / pixelsX,
                             height: CGFloat(maxY - minY + 1) / pixelsY)
        return (made, opening)
    }

    /// One ring render on a canvas of `canvas` points, plus the three things read off it: the client
    /// hole, the top-right corner's width, and **the extent the ring's pixels actually cover**.
    private func ringRender(builder: WMPSceneBuilder, renderer: WMPRenderer, canvas: CGSize,
                            backingScale: CGFloat, repairing: Bool,
                            spans: (down: Bool, across: Bool) = (true, true),
                            pinnedFurniture: Set<Int>? = nil) async throws
        -> (image: CGImage, client: CGRect, corner: CGFloat?, extent: CGRect, furniture: Set<Int>)? {
        // **Below the donor's own floor, build at the floor (W209 prototype).** A skin that declares
        // `minWidth=560 minHeight=260` has never been asked what 357x238 looks like, and it shows:
        // `Back to the Future Trilogy` is clean at every size from 420x260 up and grows a ~13x20pt
        // black tab beside its logo the moment the height drops under 260, because two of its
        // bottom pieces are placed at `view.height-86` and `view.height-93` against a corner bitmap
        // 215 tall. The ring path answered this by unclamping and letting the pieces fall where
        // they may; a view drawn whole has the author's own layout to fall back on.
        var built = canvas
        if Self.drawsWholeDonorView, Self.wholeDonorViewObeysFloor {
            built = CGSize(width: max(canvas.width, minimumSize.width),
                           height: max(canvas.height, minimumSize.height))
        }
        let scene = try await builder.build(viewID: viewID,
                                            requestedSize: WMPSize(width: built.width, height: built.height),
                                            overrides: repairing
                                                ? laidOut(on: canvas, down: spans.down, across: spans.across)
                                                : unclamped)
        guard let client = scene.geometries[clientNodeID]?.absoluteFrame, !client.isEmpty else {
            return nil
        }
        // **An extra piece that lands inside the hole is the donor's own furniture, not frame
        // (W209).** `Alienware Invader` anchors its album-art panel, search box and playlist rack
        // to the same left edge as its rails, so markup cannot tell them apart; their frames can.
        // The eight slot-holders are exempt — a corner bitmap is routinely wider than the border it
        // sits in (190pt on `Halo 2`) and overlapping the hole is what decorative corners do.
        let overlapping = Set(extraNodeIDs.filter { id in
            guard let frame = scene.geometries[id]?.absoluteFrame else { return false }
            let piece = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            guard piece.width > 0, piece.height > 0 else { return false }
            let hole = CGRect(x: client.x, y: client.y, width: client.width, height: client.height)
            let overlap = piece.intersection(hole)
            guard !overlap.isNull else { return false }
            return overlap.width * overlap.height > piece.width * piece.height * 0.5
        })
        // **The eight slots first, the rest only to repair (W209).** Admitting every edge-anchored
        // bitmap unconditionally moved things far outside the skins it was meant to fix: measured
        // over the corpus it re-cut the client hole on seven donors and opened gaps that refused six
        // rings which had measured a clean 0.000 — `AlienMorph`, `ALXMorph`, `ALXVortex`,
        // `AlienwareTeleport`, `Harry_Potter…` and `Project…`. A ring that closes is already right,
        // and the extra pieces are only ever an answer to one that does not.
        // **An extra that sits in the border is frame furniture, and it is drawn from the start.**
        // `Back to the Future Trilogy` plates its bottom bar with `f_logo.png` over a tab of the
        // same black its content area is filled with; refuse the plate and the tab is a hole in the
        // bar — the notch, reported three times. It wraps a button that opens the film's website,
        // and W208's rule is about a *corner* glyph that claims to do something to playback, which
        // this is not: our chrome is a picture, the donor's handlers are never wired, and a bar
        // with a hole in it is the worse answer. Transport is still refused, everywhere.
        // Extras that overlap the hole are the donor's own content furniture and stay out of the
        // first pass; they are admitted only when a ring has to be repaired.
        // **The whole donor view, minus what is the skin's own (W209 prototype).** See
        // `excludedNodeIDs`. Nothing is selected, so nothing can be left out: the drawer's nested
        // right rail, the script-sized lower tiles and the plate over the bottom bar's join are all
        // drawn because the skin drew them, in the skin's own order, at the skin's own positions.
        if Self.drawsWholeDonorView {
            // **A piece that sits inside the hole and touches no edge is the donor's furniture.**
            // Subtracting by kind cannot see it: `Alienware Invader` paints its album-art rack, its
            // search box and its list rack as ordinary decorated subviews, and they arrived on our
            // windows as an alien head and two empty boxes over the library's rows. What separates
            // them from frame is where they are — a border piece reaches an edge of the view, and a
            // corner bitmap routinely dips well into the hole while doing it (190pt on `Halo 2`),
            // so touching an edge is the exemption rather than overlap being the test.
            //
            // **A piece the donor draws *over its own content* and inside the strip our content is
            // given is furniture too (W210).** `Alienware Invader`'s three rack nodes at `left=18`
            // sit to the left of its client subview, so the test above is right not to fire on
            // them; `reclaimingSideRacks` then judges that 134pt margin a rack, hands the strip to
            // our content, and the frame is painted over it (W209) — an alien head and two empty
            // boxes on the library's rows. Widening the hole to the reclaimed rect alone is not the
            // answer: `Ice`'s right rail (`Vid-righttile.bmp`, 37pt of the 157pt margin the same
            // rule reclaims) lands in its strip too, and dropping it took the inner right border
            // off every window that borrows that frame.
            //
            // **Paint order is what tells them apart, because it is the donor's own answer to the
            // same question.** A piece drawn *before* the client subview is behind the skin's own
            // list — a rail, a bezel, a background — and it is behind ours for the same reason. A
            // piece drawn *after* it is over the skin's content, and over ours. `Ice` paints its
            // rail at `zIndex=5` under a `zIndex=50` list; `Alienware Invader` paints its racks at
            // `zIndex=10` over a list with no `zIndex` at all. Read off `commands`, which is the
            // order the renderer draws in, rather than off `zIndex`, which is ordered among
            // siblings only.
            let hole = CGRect(x: client.x, y: client.y, width: client.width, height: client.height)
            let reclaimed = Self.reclaimingSideRacks(hole, in: built)
            let paintOrder = Dictionary(scene.commands.enumerated().map { ($0.element.stableID, $0.offset) },
                                        uniquingKeysWith: min)
            let clientOrder = paintOrder[clientNodeID]
            let bounds = CGRect(x: 0, y: 0, width: built.width, height: built.height)
            let derivedFurniture = Set(scene.geometries.compactMap { id, geometry -> Int? in
                let frame = geometry.absoluteFrame
                let piece = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                guard piece.width > 0, piece.height > 0 else { return nil }
                let touchesEdge = piece.minX <= bounds.minX + 1 || piece.minY <= bounds.minY + 1
                    || piece.maxX >= bounds.maxX - 1 || piece.maxY >= bounds.maxY - 1
                guard !touchesEdge else { return nil }
                let half = piece.width * piece.height * 0.5
                let inHole = piece.intersection(hole)
                if !inHole.isNull, inHole.width * inHole.height > half { return id }
                // Only over the reclaimed strip, and only for a piece the donor draws over its own
                // content.
                guard let clientOrder, let order = paintOrder[id], order > clientOrder else { return nil }
                let inReclaimed = piece.intersection(reclaimed)
                guard !inReclaimed.isNull else { return nil }
                return inReclaimed.width * inReclaimed.height > half ? id : nil
            })
            // **The repair pass does not re-classify (W212).** Giving a script-sized tile the span
            // of its side changes every rect the test above reads: this donor's list rack doubles
            // in height, reaches the bottom edge, and is exempted as a border piece — which is how
            // the earlier attempt at this repair put the rack back on every hosted window. The
            // first pass is where the pieces are the size their author drew them, so its verdict
            // is the one that stands.
            let furniture = pinnedFurniture ?? derivedFurniture
            let whole = scene.commands.filter {
                !excludedNodeIDs.contains($0.stableID) && !furniture.contains($0.stableID)
            }
            guard !whole.isEmpty else { return nil }
            let wholeScene = WMPScene(viewID: scene.viewID, canvasSize: scene.canvasSize,
                                      resizeLimits: scene.resizeLimits, isResizable: scene.isResizable,
                                      commands: whole, hits: [], widgets: [], geometries: [:],
                                      unresolved: [], diagnostics: [], dirtyBounds: nil,
                                      metrics: scene.metrics, wasBuiltOnMainThread: false)
            let drawn = try await renderer.render(scene: wholeScene, backingScale: backingScale)
            let canvasRect = CGRect(x: 0, y: 0,
                                    width: scene.canvasSize.width, height: scene.canvasSize.height)
            return (drawn.image,
                    CGRect(x: client.x, y: client.y, width: client.width, height: client.height),
                    topRightNodeID.flatMap { scene.geometries[$0]?.absoluteFrame }.map(\.width),
                    Self.opaqueExtent(drawn.image, scale: backingScale) ?? canvasRect,
                    furniture)
        }
        let admitted = repairing ? ringNodeIDs : ringNodeIDs.subtracting(extraNodeIDs)
        let ring = scene.commands.filter { admitted.contains($0.stableID) && !overlapping.contains($0.stableID) }
        guard !ring.isEmpty else { return nil }
        let ringOnly = WMPScene(viewID: scene.viewID, canvasSize: scene.canvasSize,
                                resizeLimits: scene.resizeLimits, isResizable: scene.isResizable,
                                commands: ring, hits: [], widgets: [], geometries: [:],
                                unresolved: [], diagnostics: [], dirtyBounds: nil,
                                metrics: scene.metrics, wasBuiltOnMainThread: false)
        let rendered = try await renderer.render(scene: ringOnly, backingScale: backingScale)
        let full = CGRect(x: 0, y: 0, width: scene.canvasSize.width, height: scene.canvasSize.height)
        let extent = Self.opaqueExtent(rendered.image, scale: backingScale) ?? full

        // **The border's own decoration is drawn, and it is drawn *after* the extent is measured.**
        //
        // A skin plates its border where two pieces meet: `Back to the Future Trilogy` covers the
        // join in its bottom bar with `f_logo.png`, and the piece underneath carries the black of
        // the screen area up into the bar because the plate was always going to hide it. Leave the
        // plate out and that black is a tab hanging in the middle of the border — reported four
        // times, and reported correctly as *"you are creating this notch, it is not in the art"*:
        // the skin's own playlist has no tab, because the skin draws the plate.
        //
        // Nothing may move as a result, so this is deliberately not part of the ring. The extent
        // above, the crop taken from it and the bare-edge measurement are all made from the slot
        // pieces alone; the decoration is composited on top afterwards. Adding it to the ring was
        // tried first and grew the alpha bounding box, which shifted the crop, which changed the
        // edge measurement, which refused `Harry_Potter…` and moved `Ice`'s client hole — all for
        // a plate a few points across. Painted here, every number on every skin is untouched.
        var image = rendered.image
        let decoration = scene.commands.filter {
            extraNodeIDs.contains($0.stableID) && !admitted.contains($0.stableID)
                && !overlapping.contains($0.stableID)
        }
        if !decoration.isEmpty {
            let decorScene = WMPScene(viewID: scene.viewID, canvasSize: scene.canvasSize,
                                      resizeLimits: scene.resizeLimits, isResizable: scene.isResizable,
                                      commands: ring + decoration, hits: [], widgets: [], geometries: [:],
                                      unresolved: [], diagnostics: [], dirtyBounds: nil,
                                      metrics: scene.metrics, wasBuiltOnMainThread: false)
            if let plated = try? await renderer.render(scene: decorScene, backingScale: backingScale) {
                image = plated.image
            }
        }
        return (image,
                CGRect(x: client.x, y: client.y, width: client.width, height: client.height),
                topRightNodeID.flatMap { scene.geometries[$0]?.absoluteFrame }.map(\.width),
                extent, [])
    }

    /// The bounding box, in points, of everything in `image` that is not fully transparent.
    ///
    /// Alpha only — no colour rule, no threshold to tune. It answers one question: how much of the
    /// canvas did the ring paint. Nil when the image is empty or cannot be read, and the caller then
    /// treats the whole canvas as the extent, which is the pre-W207 behaviour.
    private static func opaqueExtent(_ image: CGImage, scale: CGFloat) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, scale > 0 else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        guard let context = alpha.withUnsafeMutableBytes({ bytes -> CGContext? in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    /// How much of each edge of a frame the ring leaves **bare**, as the longest unbroken run of
    /// unpainted rows or columns divided by that edge's length — top, left, bottom, right (W209).
    ///
    /// A ring is a closed surround by definition, so every edge of the assembled frame should be
    /// painted along its whole length. Measured over the installed corpus at 550x464, the skins
    /// whose rings close read **0 to 0.024**; the two that do not read 0.37/0.34 (`Back to the
    /// Future Trilogy`) and 0.23 (`Alienware Invader`, whose side rails stop two-thirds down).
    ///
    /// **The longest *run*, not the total, and that distinction is the rule.** A skin with rounded
    /// corners or a keyed notch leaves bare pixels scattered along an edge and its total climbs
    /// while every gap stays a few points wide; a ring that came apart leaves one hole a third of
    /// the edge long. Only the second is a frame with a piece missing.
    ///
    /// Alpha only, read in a band the depth of the thinnest border worth having, because a piece
    /// anchored a point or two off the edge is still a border and a piece 200pt inside it is not.
    static func edgeGaps(_ image: CGImage, scale: CGFloat) -> [CGFloat]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, scale > 0 else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        guard let context = alpha.withUnsafeMutableBytes({ bytes -> CGContext? in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let band = max(1, Int((edgeBandDepth * scale).rounded()))
        // A bitmap context stores row 0 at the *top* of the image it produces, whatever its
        // coordinate origin, so row 0 is the frame's top edge. The four edges are symmetric and the
        // names matter only to the caller's log line; they were checked against a dumped PNG.
        let painted: (Int, Int) -> Bool = { x, y in alpha[y * width + x] > edgeAlphaFloor }
        func longestRun(_ count: Int, _ bare: (Int) -> Bool) -> CGFloat {
            var longest = 0, run = 0
            for index in 0..<count {
                run = bare(index) ? run + 1 : 0
                if run > longest { longest = run }
            }
            return CGFloat(longest) / CGFloat(count)
        }
        let top = longestRun(width) { x in !(0..<min(band, height)).contains { painted(x, $0) } }
        let bottom = longestRun(width) { x in
            !(max(0, height - band)..<height).contains { painted(x, $0) }
        }
        let left = longestRun(height) { y in !(0..<min(band, width)).contains { painted($0, y) } }
        let right = longestRun(height) { y in
            !(max(0, width - band)..<width).contains { painted($0, y) }
        }
        return [top, left, bottom, right]
    }

    static func widestEdgeGap(_ image: CGImage, scale: CGFloat) -> CGFloat? {
        edgeGaps(image, scale: scale)?.max()
    }

    /// The deepest a piece can sit from the window's edge and still be that edge's border, in
    /// points. Six: thinner than every border in the corpus, so a piece inside it is unambiguously
    /// the edge, and deep enough to absorb a ring anchored a point or two in.
    private static let edgeBandDepth: CGFloat = 6
    /// Below this a pixel is the anti-aliased fringe of something drawn elsewhere, not a border.
    private static let edgeAlphaFloor: UInt8 = 40
    /// The widest bare run an edge may carry before the ring is refused (W209).
    ///
    /// **The population is bimodal and this sits in the empty middle.** Measured over the 185
    /// installed archives at 550x464 on 2026-09-16, the 88 rings split into 59 that measure
    /// **0.000 to 0.052** and 28 that measure **0.231 to 1.000**, with nothing in between but
    /// `Dreamcatcher` at 0.109. There is no continuum to tune along: a ring either closes or has a
    /// piece missing. Two of the 28 were reported from the running app on the day this was written
    /// — `Back to the Future Trilogy` (0.369, a third of its top edge) and `Alienware Invader`
    /// (0.231, side rails that stop two-thirds down) — and five of them measure 0.9 or more, which
    /// is a whole edge of the window with no frame on it.
    private static let ringEdgeGapLimit: CGFloat = 0.15

    /// The longest bare run an edge may carry in **points** before the span repair is reached
    /// (W228).
    ///
    /// **A fraction is a property of the window as much as of the ring, and the repair gate needs
    /// the property of the ring.** `Alienware Invader` sizes both its rails in `onPlResize()`, so
    /// the frame build — outside the script runtime — leaves the same **107pt** hole down each side
    /// at every window size. That is 0.231 of a 464pt-tall window and trips `ringEdgeGapLimit`, and
    /// 0.132 of the library browser's 810 and does not: the identical hole was repaired on nine
    /// hosted windows and left open on the tallest one, which is the *"alien invader media library
    /// window draws broken"* report. Nothing about the frame differs between the two — the
    /// `HOSTED-FRAME` lines are the same ring, the same pieces and the same 107pt.
    ///
    /// Forty points, and the measurement is the same shape as the fraction's. Over the 185
    /// installed archives at 710x810 the rings that close run **0 to 24.3pt** and the ones with a
    /// piece missing measure **49.7** (`Half-Life_2`), **85.2** (`Combat_Flight_Simulator_3`) and
    /// **106.9** (`Alienware Invader`), with nothing between — the same empty middle 0.15 sits in
    /// at 550x464. A run is measured along its own edge, so a side gap is judged against the
    /// window's height and a top or bottom gap against its width.
    private static let ringEdgeGapPointLimit: CGFloat = 40

    /// Whether an edge came out bare enough to be a missing piece rather than a keyed notch:
    /// too large a share of its edge, **or** too long in absolute terms. See
    /// `ringEdgeGapPointLimit` for why one test cannot answer for every window size.
    static func edgeCameOutBare(_ gap: CGFloat, along edge: CGFloat) -> Bool {
        gap > ringEdgeGapLimit || gap * edge > ringEdgeGapPointLimit
    }

    /// Nine-slice the one-piece panel (W207) onto a window of `size` points.
    ///
    /// The panel is drawn once at the size its author drew it — a fixed bitmap has no alignment
    /// rules to re-resolve, and building the donor view at the *window's* size would only move the
    /// skin's own furniture around inside it — then cropped to the panel's own frame and recomposed:
    /// the four corners at 1:1, the four edge strips stretched along their axis, and the centre left
    /// out. **The centre is a hole, not a fill**: our content goes there, and the ring path cuts the
    /// same hole for the same reason (`PlexBrowserView.drawWinampModernChrome`, and the `Scooby Doo`
    /// case behind it).
    ///
    /// Stretched, not tiled. A one-piece panel authored no edge pieces, so there is nothing that
    /// says a strip repeats rather than extends, and a 1px-wide strip is the same either way; where
    /// the border carries a pattern — `anemone`'s spikes — stretching smears it and tiling would
    /// break its corners' registration. Stretching is the one of the two that cannot land the seam
    /// in the wrong place.
    private func panelArtwork(builder: WMPSceneBuilder, renderer: WMPRenderer, size: CGSize,
                              backingScale: CGFloat) async throws -> SkinnedSurfaceFrameArtwork? {
        guard let slices = try await panelSlices(builder: builder, renderer: renderer,
                                                 backingScale: backingScale) else { return nil }
        return Self.compose(slices, size: size, backingScale: backingScale)
    }

    /// The panel's own bitmap and the four slice lines cut out of it, resolved from the donor's
    /// layout alone.
    ///
    /// **Nothing here depends on the window's size**, and that is the point: a one-piece panel is
    /// laid out by its author at one size with no alignment rules to re-resolve, so its borders are
    /// four constants. `borderInsets` is those constants, which is what lets a hosted window be
    /// *grown* around its interior before any frame has been rendered for it (W207).
    func panelSlices(builder: WMPSceneBuilder, renderer: WMPRenderer,
                     backingScale: CGFloat) async throws -> PanelSlices? {
        guard let panelNodeID else { return nil }
        // **A drawer is authored shut, and a node that is not drawn resolves no frame.** Every panel
        // in this population is a `visible="false"` tray the skin slides out on a button — the
        // builder returns before it records a geometry, so without this the artwork came back nil
        // for the whole class while the derivation looked perfect. Overridden for this build only;
        // it is a private builder over a private image store (`WMPHostedFrameProvider`), never the
        // one drawing the skin.
        var overrides = WMPSceneOverrides.empty
        for node in [panelNodeID, clientNodeID] {
            overrides.properties[WMPScenePropertyAddress(stableID: node, property: "visible")] = .bool(true)
        }
        var scene = try await builder.build(viewID: viewID, overrides: overrides)
        guard var panel = scene.geometries[panelNodeID]?.absoluteFrame, !panel.isEmpty,
              var hole = scene.geometries[clientNodeID]?.absoluteFrame, !hole.isEmpty else {
            return nil
        }
        // **A drawer is parked outside the window it slides into.** `anemone`'s tray is at
        // `left="307"` in a 321-wide view and is 328 wide, because the skin widens its own window to
        // 635 as it opens it (`myview.width=635`). The render is clipped to the canvas, so the first
        // build returns the panel's frame and almost none of its artwork — 14px of one edge. Built a
        // second time on a canvas that contains it, and the geometry re-read there rather than
        // carried over, because a canvas that grew is a different layout for every expression in the
        // view.
        if panel.x + panel.width > scene.canvasSize.width
            || panel.y + panel.height > scene.canvasSize.height {
            let wider = WMPSize(width: max(scene.canvasSize.width, panel.x + panel.width),
                                height: max(scene.canvasSize.height, panel.y + panel.height))
            scene = try await builder.build(viewID: viewID, requestedSize: wider, overrides: overrides)
            guard let rebuiltPanel = scene.geometries[panelNodeID]?.absoluteFrame, !rebuiltPanel.isEmpty,
                  let rebuiltHole = scene.geometries[clientNodeID]?.absoluteFrame, !rebuiltHole.isEmpty
            else { return nil }
            panel = rebuiltPanel
            hole = rebuiltHole
        }
        // The panel's **own** artwork and nothing else: the donor's buttons, readouts and list are
        // the skin's window, not ours — the ring path's rule, stated there at length.
        let own = scene.commands.filter { $0.stableID == panelNodeID }
        guard !own.isEmpty else { return nil }
        let canvas = scene.canvasSize
        let panelOnly = WMPScene(viewID: scene.viewID, canvasSize: canvas,
                                 resizeLimits: scene.resizeLimits, isResizable: scene.isResizable,
                                 commands: own, hits: [], widgets: [], geometries: [:],
                                 unresolved: [], diagnostics: [], dirtyBounds: nil,
                                 metrics: scene.metrics, wasBuiltOnMainThread: false)
        let rendered = try await renderer.render(scene: panelOnly, backingScale: backingScale)
        guard let cropped = rendered.image.cropping(to: CGRect(
            x: panel.x * backingScale, y: panel.y * backingScale,
            width: panel.width * backingScale, height: panel.height * backingScale)) else {
            return nil
        }

        // The four slice lines, in the panel's own coordinates.
        let margins = NSEdgeInsets(top: hole.y - panel.y, left: hole.x - panel.x,
                                   bottom: (panel.y + panel.height) - (hole.y + hole.height),
                                   right: (panel.x + panel.width) - (hole.x + hole.width))
        // The same guard the derivation applies wherever the markup was readable, now against the
        // resolved frames — this is the only place a panel sized by its own bitmap can be checked.
        // **Thrown, not nil**: this is a verdict on the donor at every size, and the provider drops
        // the template on it, where a nil is only ever about the window that asked.
        guard [margins.top, margins.left, margins.bottom, margins.right]
            .allSatisfy({ $0 >= Self.minimumBorder }) else {
            throw WMPHostedFrameRefusal.panelCannotBeSliced
        }
        return PanelSlices(image: cropped,
                           panel: CGSize(width: panel.width, height: panel.height),
                           margins: margins)
    }

    /// The panel's bitmap and the four slice lines cut out of it. Size-independent, by construction.
    struct PanelSlices: @unchecked Sendable {
        let image: CGImage
        /// The panel's own size in points, the coordinates `margins` are stated in.
        let panel: CGSize
        /// Top / left / bottom / right, in points. **These are the border, at the thickness its
        /// author drew it**, and they never change with the window (W207).
        let margins: NSEdgeInsets
    }

    /// **The border is added around the interior, never taken out of it (W207).**
    ///
    /// The slice is composed at the window's own size with its four borders at 1:1 — so the hole is
    /// exactly `window − border`, and a window that wants a 600x150 interior is expected to have
    /// been *grown* to 600+left+right by 150+top+bottom before it asks
    /// (`HostedWindowBorderLayout`, driven by `borderInsets`). Reported 2026-09-16:
    /// *"the interior window … should be its full borderless size, then the border is added after
    /// that, and the final size is simply the full interior + border"*.
    ///
    /// Three answers preceded it and each was reported wrong: composing at `floor + 1` and mapping
    /// that onto the window left a five-point hole with the drawer squashed around it; refusing a
    /// window that could not carry the borders took the frame off everything but PeppyMeter; and a
    /// uniform scale-to-fit sized so the hole keeps a third of each axis is the thin, shrunken
    /// border the report above is about. Growing the window is the fourth, and the only one that
    /// leaves both the interior and the border at the size their authors chose.
    ///
    /// A window that still cannot carry its borders — one clamped by the screen, or one asking
    /// before the growth has landed — is answered nil and keeps the palette chrome for that size,
    /// rather than being handed a frame with no room in it.
    private static func compose(_ slices: PanelSlices, size: CGSize,
                                backingScale: CGFloat) -> SkinnedSurfaceFrameArtwork? {
        let margins = slices.margins
        let floor = CGSize(width: margins.left + margins.right, height: margins.top + margins.bottom)
        guard size.width >= floor.width + minimumInterior.width,
              size.height >= floor.height + minimumInterior.height else { return nil }
        guard let composed = ninePatch(slices.image, panel: slices.panel, margins: margins,
                                       target: size, scale: backingScale) else { return nil }
        var content = CGRect(x: margins.left, y: margins.top,
                             width: size.width - floor.width, height: size.height - floor.height)
        content = reclaimingSideRacks(content, in: size)
        return SkinnedSurfaceFrameArtwork(
            image: composed, size: size, contentRect: content,
            trailingCornerWidth: margins.right, wasScaledToFit: false)
    }

    /// **The donor's resize floor, lifted, so the ring is laid out at the window's own size (W207).**
    ///
    /// A ring is eight pieces with stretched or tiled edges: laying it out at 300pt is exactly the
    /// operation its author built it for. The floor is a constraint on the *skin's* window, and
    /// obeying it here meant building the ring on a canvas the window is not, then stretching the
    /// picture — which distorts the border and, where a view's floor is larger than its own natural
    /// size, does worse. `Ice` is that case and it is what the reporter saw: `<view id="plView"
    /// width="383" … minWidth="585">`, so the ring was composed on a 585x308 canvas its own art only
    /// reaches 487x279 of, and the stretched result left the right sixth of every hosted window bare
    /// (measured 2026-09-16 — the alpha bounding box of `WMP_HOSTED_FRAME_DUMP`, identical at every
    /// window size because the canvas was always the floor).
    ///
    /// With the window grown to `interior + border`, there is no longer a size the ring has to be
    /// squeezed into: it is drawn 1:1 at whatever the window is, and `wasScaledToFit` goes false.
    private var unclamped: WMPSceneOverrides {
        var overrides = WMPSceneOverrides.empty
        for name in ["minwidth", "minheight"] {
            overrides.properties[WMPScenePropertyAddress(stableID: viewNodeID, property: name)] = .number(1)
        }
        return overrides
    }

    /// `unclamped`, plus the span every script-sized edge piece needs to reach along its own side
    /// (W209). See `stretchedDownNodeIDs`. The length is the whole canvas rather than the distance
    /// to the next corner: a tile is clipped by the window and painted under the corner pieces,
    /// which are drawn after it by the same paint order the skin declares.
    private func laidOut(on canvas: CGSize, down: Bool = true, across: Bool = true) -> WMPSceneOverrides {
        var overrides = unclamped
        // `geometry`, not `properties`: a dimension is resolved through `parseDimension`, which
        // reads the geometry overrides a script's own writes land in.
        if down {
            for id in stretchedDownNodeIDs {
                overrides.geometry[WMPScenePropertyAddress(stableID: id, property: "height")] = canvas.height
            }
        }
        if across {
            for id in stretchedAcrossNodeIDs {
                overrides.geometry[WMPScenePropertyAddress(stableID: id, property: "width")] = canvas.width
            }
        }
        return overrides
    }

    /// The smallest hole worth cutting. Below it the "window" is all frame, which is the failure the
    /// growth exists to avoid — and a window this small has not been grown yet.
    private static let minimumInterior = CGSize(width: 24, height: 24)

    /// **The border this donor adds around a hosted window's interior, before any frame has been
    /// rendered for that window (W207).**
    ///
    /// This is the number `HostedWindowBorderLayout` grows a window by, and it has to be answerable
    /// without a window size, because the window cannot reach a size that can carry the border until
    /// it knows how thick the border is. A panel's borders are four constants of its own bitmap. A
    /// ring's are resolved from its client subview, which *can* depend on the window — so it is read
    /// once at the donor's own declared floor, where its author laid it out.
    func borderInsets(builder: WMPSceneBuilder, renderer: WMPRenderer,
                      backingScale: CGFloat) async throws -> NSEdgeInsets? {
        if panelNodeID != nil {
            guard let slices = try await panelSlices(builder: builder, renderer: renderer,
                                                     backingScale: backingScale) else { return nil }
            let m = slices.margins
            return Self.effectiveBorder(
                hole: CGRect(x: m.left, y: m.top,
                             width: slices.panel.width - m.left - m.right,
                             height: slices.panel.height - m.top - m.bottom),
                in: slices.panel)
        }
        let reference = CGSize(width: max(minimumSize.width, 320), height: max(minimumSize.height, 240))
        // **Composed, not derived, because half of a rack can be the donor's own rail (W212).**
        // The reclaim these insets are measured through is bounded by the artwork the donor paints
        // in that margin (`clearOfTheDonorsOwnRail`), which is a fact about pixels — so the border
        // the window is grown by is read off the frame it will wear, at the reference size, rather
        // than from a second rule that can only see the markup. A donor whose ring cannot be
        // composed falls back to the geometry, which is the answer this rule gave before.
        if Self.drawsWholeDonorView,
           let composed = try? await composeRing(builder: builder, renderer: renderer,
                                                 size: reference, backingScale: backingScale,
                                                 repairing: false) {
            let content = composed.artwork.contentRect
            if !content.isEmpty {
                return NSEdgeInsets(top: max(0, content.minY), left: max(0, content.minX),
                                    bottom: max(0, reference.height - content.maxY),
                                    right: max(0, reference.width - content.maxX))
            }
        }
        let scene = try await builder.build(
            viewID: viewID,
            requestedSize: WMPSize(width: reference.width, height: reference.height))
        guard let client = scene.geometries[clientNodeID]?.absoluteFrame, !client.isEmpty else {
            return nil
        }
        let canvas = CGSize(width: scene.canvasSize.width, height: scene.canvasSize.height)
        return Self.effectiveBorder(
            hole: CGRect(x: client.x, y: client.y, width: client.width, height: client.height),
            in: canvas)

    }

    /// **The border a window actually wears, which is not every point outside the donor's hole.**
    ///
    /// A donor's client hole says where the *skin's* content goes, and a playlist view with a rack
    /// down one side leaves a third of the window outside it — `Ice`'s `plView` states a 157pt right
    /// margin on a 585pt canvas. Growing a window by that put 157pt of decorative artwork on its
    /// right edge and nothing in it. `reclaimingSideRacks` is the rule that already refuses to give
    /// a rack away at *draw* time, so the growth is measured through the same rule: the border added
    /// around the interior is the border the content will be laid out against.
    private static func effectiveBorder(hole: CGRect, in size: CGSize) -> NSEdgeInsets {
        let content = reclaimingSideRacks(hole, in: size)
        return NSEdgeInsets(top: max(0, content.minY), left: max(0, content.minX),
                            bottom: max(0, size.height - content.maxY),
                            right: max(0, size.width - content.maxX))
    }

    /// Nine pieces of `source`, laid out for a `target`-point window. Pixel work, so it is kept
    /// separate from the geometry above and takes its scale explicitly.
    private static func ninePatch(_ source: CGImage, panel: CGSize, margins: NSEdgeInsets,
                                  target: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((target.width * scale).rounded())
        let height = Int((target.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        // Column and row edges, in source pixels and in destination pixels. The middles are what
        // stretch; everything either side of them is 1:1.
        let sx = [0, margins.left * scale, (panel.width - margins.right) * scale, panel.width * scale]
        let sy = [0, margins.top * scale, (panel.height - margins.bottom) * scale, panel.height * scale]
        let dx = [0, margins.left * scale, target.width * scale - margins.right * scale, target.width * scale]
        let dy = [0, margins.top * scale, target.height * scale - margins.bottom * scale, target.height * scale]
        for row in 0..<3 {
            for column in 0..<3 {
                if row == 1, column == 1 { continue }   // the hole our content goes in
                let sourceRect = CGRect(x: sx[column], y: sy[row],
                                        width: sx[column + 1] - sx[column],
                                        height: sy[row + 1] - sy[row]).integral
                let destination = CGRect(x: dx[column], y: dy[row],
                                         width: dx[column + 1] - dx[column],
                                         height: dy[row + 1] - dy[row])
                guard sourceRect.width >= 1, sourceRect.height >= 1,
                      destination.width >= 1, destination.height >= 1,
                      let piece = source.cropping(to: sourceRect) else { continue }
                // Both spaces are top-left in this method's arithmetic and `CGContext` is
                // bottom-left, so the destination is flipped once, here, rather than in four places.
                context.draw(piece, in: CGRect(x: destination.minX,
                                               y: CGFloat(height) - destination.maxY,
                                               width: destination.width,
                                               height: destination.height))
            }
        }
        return context.makeImage()
    }

    /// Two content rects that are the same hole, to within the rounding a re-render can move.
    private static func sameHole(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5 && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    /// Widen the client hole back over a **side rack**: a donor panel's own furniture beside its
    /// content, which is not a border and must not be charged to ours.
    ///
    /// A donor's client subview says where the *skin's* content goes, and for a playlist panel with
    /// a rack down one side that leaves a third of the window outside it — `Star Wars`'s `plView`
    /// 164 of 575pt on the right, `Ginger Man` 186 on the left, `QuickSilver` 225. A hosted window
    /// laid out in the hole alone gives that third up to artwork with nothing in it, which is what
    /// the reporter saw beside the library on 2026-09-15: *"reclaim it, we have no content for it"*.
    /// The rack is still drawn — the ring is untouched — the surface simply runs under it, the same
    /// way it runs under the frame's own decorative overlap everywhere else.
    ///
    /// **A side is a rack when it is deeper than both the caption band and the opposite side.** That
    /// is the shape of the distinction: a frame is roughly even all the way round and a rack is
    /// one-sided, and the band is how thick this skin's own chrome runs. Measured over the installed
    /// corpus at 575x464 on 2026-09-15: **88 archives lend a ring, 21 carry a right rack and 31 a
    /// left one**, while `NVIDIA` — 44pt each side under an 84pt band — is a genuinely thick
    /// *frame* and is left exactly as it was, as is every skin whose sides already agree.
    private static func reclaimingSideRacks(_ content: CGRect, in size: CGSize) -> CGRect {
        guard content.width > 0, content.minY > 0 else { return content }
        let band = content.minY
        let left = max(0, content.minX)
        let right = max(0, size.width - content.maxX)
        let reclaimedLeft = left > max(band, right) ? max(band, right) : left
        let reclaimedRight = right > max(band, left) ? max(band, left) : right
        guard reclaimedLeft != left || reclaimedRight != right else { return content }
        return CGRect(x: reclaimedLeft, y: content.minY,
                      width: max(0, size.width - reclaimedLeft - reclaimedRight),
                      height: content.height)
    }

}
