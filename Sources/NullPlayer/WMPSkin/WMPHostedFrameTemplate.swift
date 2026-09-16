import AppKit
import CoreGraphics
import Foundation

/// The window frame a `.wmz` skin already draws for its *own* panels, borrowed for NullPlayer's
/// windows.
///
/// **What the corpus authors.** A WMP skin has no frame system — no `<Wasabi:StandardFrame>` a
/// hosted surface can be mounted in — so for a long time the only thing a `.wmz` gave our own
/// windows was `WMPSurfacePalette`'s colours. But a skin with a styled playlist or equaliser panel
/// is not drawing a coloured rectangle: it is drawing an **eight-piece resizable ring** — four
/// corner bitmaps anchored to the corners, four edge bitmaps tiled or stretched along the sides —
/// with its real content in a stretched client subview inside. `xsn_sports` and `Halo 2` are the
/// reported pair and they are not unusual: measured over the 180-archive corpus on 2026-09-12,
/// **85 archives declare a view whose four corners are all present, and all 85 of those views also
/// declare a stretched client subview**, which is what makes the ring reusable rather than merely
/// recognisable.
///
/// **What is borrowed, and what is not.** Only the ring. The donor view's buttons, playlist, text
/// and video surface are the *skin's* window, not ours, and a NullPlayer spectrum analyser wearing
/// Halo 2's playlist buttons would be a lie about what those buttons do. So a template records the
/// ring pieces and the client panel, and the artwork it produces contains the ring alone; the
/// palette still paints the client area and NullPlayer still draws its own content and controls
/// over it.
///
/// **The insets come from the client subview, never from the artwork's thickness.** `Halo 2`'s
/// `f_left_tile.png` is 190px wide on a 406px window and is mostly transparent — the ring is a
/// decorative surround, not a border — while its `plFrame` states the content hole exactly
/// (`left="22" top="34" width="view.width-43" height="view.height-81"`). Sizing a window's content
/// from the corner bitmaps would leave 190px of dead margin on a 275px window.
///
/// The template is markup-only and cheap; the *artwork* is produced by re-building the donor view
/// through the ordinary `WMPSceneBuilder` at the hosted window's size, so every alignment, tile and
/// `JScript:` layout expression is resolved by the same code that draws the skin itself rather than
/// by a second, divergent reading of the same markup.
/// Why a borrowed frame was refused. A `nil` artwork is "not for this window"; this is "not ever".
enum WMPHostedFrameRefusal: Error {
    case panelCannotBeSliced
}

struct WMPHostedFrameTemplate: Equatable, Sendable {
    /// The view the ring was taken from.
    let viewID: String
    /// The ring pieces, by stable id — the only nodes whose paint commands reach our windows.
    let ringNodeIDs: Set<Int>
    /// The stretched client subview whose resolved frame is the content hole.
    let clientNodeID: Int
    /// The ring's own top-right corner piece, where it declares one.
    ///
    /// **This is the width our close control has to clear, and the client hole is not.** A donor's
    /// client hole says where the skin's *content* goes, and for a playlist panel with a side rack
    /// — `Star Wars`'s `plView` leaves 164 of 575pt to the right of its list — that is a third of
    /// the window, so a close control aligned with the hole's right edge lands in the middle of the
    /// caption band with ring artwork either side of it (reported 2026-09-15: the fix put the x
    /// nowhere near the corner). What the control must actually avoid is the corner bitmap, which
    /// is where a skin paints its *own* close button.
    let topRightNodeID: Int?
    /// The donor view's own declared floor. A window smaller than this cannot be built at its own
    /// size, because `WMPResizeLimits.clamp` is what every other consumer of this view obeys.
    let minimumSize: CGSize

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
            var score = candidate.ringNodeIDs.count
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
                    clientNodeID: hole.stableID,
                    topRightNodeID: nil,
                    minimumSize: .zero,
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
        var client: WMPNode?

        // Direct children only. A ring is laid out against the *window*, so its pieces are the
        // window's own children; a nested panel that happens to stretch is part of the skin's
        // content, not of its frame.
        for child in view.children where child.kind == .subview {
            let horizontal = WMPAxisAlignment(horizontal: literal(child, "horizontalAlignment"))
            let vertical = WMPAxisAlignment(vertical: literal(child, "verticalAlignment"))
            if hasBackgroundImage(child) {
                guard let role = Role(horizontal: horizontal, vertical: vertical) else { continue }
                // First declaration wins, matching the duplicate-id rule elsewhere in the engine:
                // a skin that layers two bitmaps in one corner authored the lower one first.
                if ring[role] == nil { ring[role] = child }
            } else if horizontal == .stretch, vertical == .stretch, client == nil {
                client = child
            }
        }

        guard Role.corners.isSubset(of: Set(ring.keys)), let client else { return nil }
        return WMPHostedFrameTemplate(
            viewID: registration.id,
            ringNodeIDs: Set(ring.values.map(\.stableID)),
            clientNodeID: client.stableID,
            topRightNodeID: ring[.topRight]?.stableID,
            minimumSize: CGSize(width: number(view, "minWidth") ?? number(view, "width") ?? 0,
                                height: number(view, "minHeight") ?? number(view, "height") ?? 0)
        )
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
        let scene = try await builder.build(viewID: viewID,
                                            requestedSize: WMPSize(width: size.width, height: size.height))
        guard let client = scene.geometries[clientNodeID]?.absoluteFrame, !client.isEmpty else {
            return nil
        }
        let ring = scene.commands.filter { ringNodeIDs.contains($0.stableID) }
        guard !ring.isEmpty else { return nil }

        let canvas = scene.canvasSize
        let ringOnly = WMPScene(viewID: scene.viewID, canvasSize: canvas,
                                resizeLimits: scene.resizeLimits, isResizable: scene.isResizable,
                                commands: ring, hits: [], widgets: [], geometries: [:],
                                unresolved: [], diagnostics: [], dirtyBounds: nil,
                                metrics: scene.metrics, wasBuiltOnMainThread: false)
        let rendered = try await renderer.render(scene: ringOnly, backingScale: backingScale)

        // The scene may have been clamped up to the donor's floor; map it back onto the window.
        let scaleX = canvas.width > 0 ? size.width / canvas.width : 1
        let scaleY = canvas.height > 0 ? size.height / canvas.height : 1
        var content = CGRect(x: client.x * scaleX, y: client.y * scaleY,
                             width: client.width * scaleX, height: client.height * scaleY)
        content = Self.reclaimingSideRacks(content, in: size)
        // The corner piece our close control has to clear, mapped onto the window the same way.
        let corner = topRightNodeID.flatMap { scene.geometries[$0]?.absoluteFrame }
        return SkinnedSurfaceFrameArtwork(
            image: rendered.image, size: size, contentRect: content,
            trailingCornerWidth: corner.map { $0.width * scaleX },
            wasScaledToFit: abs(scaleX - 1) > 0.001 || abs(scaleY - 1) > 0.001)
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
        // **A panel's borders are absolute, and a short window has to be given them anyway (W207).**
        //
        // `anemone`'s tray is 83/72/90/73 around its list — 173x145 of frame — and the spectrum
        // family opens about 600x150. Two answers were tried and reported wrong, in this order:
        // composing at `floor + 1` and mapping that onto the window left a **five-point hole** with
        // the whole drawer squashed around it (*"waveform, cava and the analyser"*), and refusing the
        // window outright took the border off every one of them (*"you removed the border from all
        // the windows except peppymeter"* — PeppyMeter being the only one tall enough to clear the
        // floor). The third is the ring path's own: **scale the frame, uniformly, until the hole is
        // worth having.** The slice is composed on a canvas large enough that the borders leave a
        // third of each axis for content, and the whole picture is then drawn into the window —
        // thinner borders in the same proportions the skin drew, never a distorted one, and never a
        // window that is all frame. `wasScaledToFit` reports it, exactly as a ring below its donor's
        // floor does.
        //
        // A window that *can* carry the borders at 1:1 is untouched: the scale is 1 and the hole
        // absorbs every point of the window's own size, which is the whole purpose of slicing
        // (550x464 → 83/72/83/73 with a 384x319 hole; 1200x800 → the same borders, a 1034x655 hole).
        let floor = CGSize(width: margins.left + margins.right, height: margins.top + margins.bottom)
        let fit = max(1, max(floor.width * 1.5 / size.width, floor.height * 1.5 / size.height))
        let target = CGSize(width: size.width * fit, height: size.height * fit)
        guard let composed = Self.ninePatch(cropped, panel: CGSize(width: panel.width, height: panel.height),
                                            margins: margins, target: target, scale: backingScale)
        else { return nil }
        let scaleX = target.width > 0 ? size.width / target.width : 1
        let scaleY = target.height > 0 ? size.height / target.height : 1
        var content = CGRect(x: margins.left * scaleX, y: margins.top * scaleY,
                             width: max(0, (target.width - floor.width)) * scaleX,
                             height: max(0, (target.height - floor.height)) * scaleY)
        content = Self.reclaimingSideRacks(content, in: size)
        return SkinnedSurfaceFrameArtwork(
            image: composed, size: size, contentRect: content,
            trailingCornerWidth: margins.right,
            wasScaledToFit: abs(scaleX - 1) > 0.001 || abs(scaleY - 1) > 0.001)
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
