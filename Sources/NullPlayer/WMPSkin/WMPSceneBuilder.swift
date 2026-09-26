import CoreGraphics
import Foundation

struct WMPSceneBuilder: @unchecked Sendable {
    let loadedSkin: WMPLoadedSkin
    let imageStore: WMPImageStore

    init(loadedSkin: WMPLoadedSkin, imageStore: WMPImageStore? = nil) {
        self.loadedSkin = loadedSkin
        self.imageStore = imageStore ?? WMPImageStore(provider: loadedSkin.archive)
    }

    /// **The width the hosted picture's own command bar needs, and the floor a view carrying a
    /// `<VIDEO>` is built to.**
    ///
    /// The picture in a `.wmz` is NullPlayer's video window parked over the skin's video box, and
    /// the play/subtitle/cast overlay goes with it. That bar does not compress — its controls are
    /// one required constraint chain — so in a box narrower than its fitting width it forces the
    /// parked window wider than the box and pushes the picture out through the skin's chrome. Most
    /// of the corpus authors a box narrower than that: `Combat_Flight_Simulator_3`'s is 360pt
    /// inside a 380pt view. Widening the *view* widens the box with it, because every one of these
    /// boxes is `view.width` minus a constant shell.
    ///
    /// Measured from the bar itself rather than written down twice —
    /// `VideoPlayerWindowController.videoControlBarMinimumWidth` is 395 — and pinned by
    /// `WMPVideoControlBarFloorTests` so a change to the bar's own controls fails there rather than
    /// silently cropping the picture in every skin.
    static let videoControlBarWidth: CGFloat = 395

    /// Layout, resource resolution, and image metadata/decode stay off the main thread even when a
    /// UI caller initiates the transaction.
    ///
    /// **A view with a video box is built twice when its box is too narrow for the command bar.**
    /// The box's width is almost always an expression off the view's own (`jscript:view.width-20`),
    /// so it cannot be read before the first pass and it follows the view exactly on the second.
    func build(viewID: String, requestedSize: WMPSize? = nil,
               interactionState: WMPInteractionState = WMPInteractionState(),
               dirtyNodeIDs: Set<Int>? = nil,
               overrides: WMPSceneOverrides = .empty) async throws -> WMPScene {
        try await Task.detached(priority: .userInitiated) {
            let scene = try buildOffMain(viewID: viewID, requestedSize: requestedSize,
                                         interactionState: interactionState,
                                         dirtyNodeIDs: dirtyNodeIDs, overrides: overrides)
            guard let widened = Self.videoBarShortfall(in: scene) else { return scene }
            return try buildOffMain(viewID: viewID, requestedSize: widened,
                                    interactionState: interactionState,
                                    dirtyNodeIDs: dirtyNodeIDs, overrides: overrides)
        }.value
    }

    /// The canvas this scene needs for its video box to carry the command bar, or nil when it
    /// already does, has no video box, or is not resizable — a fixed view is pinned to its canvas
    /// at both ends (`WMPWindowSizeLimits.forScene`), and growing one would be a window whose scene
    /// it is not (W213).
    static func videoBarShortfall(in scene: WMPScene) -> WMPSize? {
        guard scene.isResizable,
              let video = scene.widgets.last(where: { $0.kind == .video }),
              video.frame.width > 0, video.frame.width + 0.5 < videoControlBarWidth else {
            return nil
        }
        let widened = scene.canvasSize.width + (videoControlBarWidth - video.frame.width)
        guard widened > scene.canvasSize.width else { return nil }
        return WMPSize(width: widened, height: scene.canvasSize.height)
    }

    private func buildOffMain(viewID: String, requestedSize: WMPSize?,
                              interactionState: WMPInteractionState,
                              dirtyNodeIDs: Set<Int>?, overrides: WMPSceneOverrides) throws -> WMPScene {
        guard let registration = loadedSkin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        }) else {
            throw WMPFailure(WMPDiagnostic(.invalidGeometry, "WMP view '\(viewID)' does not exist."))
        }
        let view = registration.node
        // A view sizes itself the way every other node does: an authored literal first, then a
        // script override, then the natural size of its own background artwork. WMP skins routinely
        // author a top-level `<VIEW backgroundImage="...">` with no width or height at all — the
        // window *is* the bitmap — and rejecting those was the single largest cause of a skin that
        // loads and then draws nothing.
        func viewOverride(_ name: String) -> CGFloat? {
            guard let value = overrides.geometry[WMPScenePropertyAddress(stableID: view.stableID,
                                                                         property: name.lowercased())],
                  value.isFinite, value >= 0 else { return nil }
            return value
        }
        func viewDimension(_ name: String) throws -> CGFloat? {
            // **Script override first, then the markup — the same order as every other node.**
            // `parseDimension` has always read the overrides before the attribute; the view root
            // read them the other way round, so a `<VIEW width="593" height="600">` could never be
            // resized by its own script. That is what a `.wmz` compact mode is made of:
            // `Cablemusic`'s `SwitchSmall()` writes `view.width = 475; view.height = 373` and hides
            // the full-size artwork, and with the literal winning the canvas stayed 593x600 — the
            // compact player drawn in the corner of a window two hundred pixels too big on both
            // axes, the rest of it empty. Reported as "when you click the compact button there is
            // a large overlay".
            //
            // A literal zero is authored on purpose: `pharaoh` declares `vGhost` and
            // `vGhostAutoDetect` as `width="0" height="0"` views whose only job is to run an
            // `onLoad` that redirects to another view. Zero is an answer; only a negative one is
            // not — and that is true of an override too, which is the store-thumbnail collapse.
            if let value = literal(view, name), value >= 0 { return value }
            return nil
        }
        // Declared here rather than with the other scene accumulators below: resolving the view's
        // own background is the first thing that can warn.
        var diagnostics = loadedSkin.diagnostics
        var authoredWidth = try viewDimension("width")
        var authoredHeight = try viewDimension("height")
        if authoredWidth == nil || authoredHeight == nil,
           let (_, path) = try resolveResource(view, names: ["backgroundImage", "background"],
                                               overrides: overrides,
                                               warn: { diagnostics.append($0) }) {
            let intrinsic = try imageStore.image(for: path).size
            if authoredWidth == nil, intrinsic.width > 0 { authoredWidth = intrinsic.width }
            if authoredHeight == nil, intrinsic.height > 0 { authoredHeight = intrinsic.height }
        }
        if authoredWidth == nil || authoredHeight == nil {
            // Neither a literal nor its own artwork: the window is sized by what it contains.
            // WMP fits such a view to its content, and skins rely on it — `iconic` hangs its whole
            // player off one `<SUBVIEW backgroundImage="base.gif">`, and `Darkling` wraps four
            // resolution-specific subviews its script picks between. Rejecting these was a total
            // blackout for both. Only geometry the builder can place without executing script
            // counts, and visibility is deliberately ignored: Darkling authors every one of its
            // wrappers `visible="false"` and turns one on in `onLoad`, so a union of the visible
            // children alone is empty.
            let union = try contentUnionSize(of: view, overrides: overrides,
                                             warn: { diagnostics.append($0) })
            if authoredWidth == nil, union.width > 0 { authoredWidth = union.width }
            if authoredHeight == nil, union.height > 0 { authoredHeight = union.height }
        }
        // Nothing sized it and it can place nothing: the view has no drawable content at all.
        // That is a legal WMP construct, not a defect — 25 corpus skins author a `controlView`
        // holding only `<player>` and a hidden `<video>` so that a script can run with host
        // bindings and no window, and `pharaoh` writes the same idea as an explicit 0x0 view.
        // The builder still invents no geometry; the honest size of empty content is empty.
        let width = authoredWidth ?? 0
        let height = authoredHeight ?? 0
        // **A `<VIEW>` that states a size its own background artwork does not have anchors that
        // artwork at the origin; it does not stretch to fill.** The image is the window's picture,
        // and where the two disagree the author meant the surplus to be empty — WMP keys the view's
        // `transparencyColor` out of it and the window simply is not there. `Colorchooser` declares
        // `width="300" height="200"` over a 246x202 `colorBack.bmp`: stretched to the canvas its
        // drawn box landed at x=87…299 while `mainBackground`, the white panel that belongs inside
        // it, stayed at the authored 77…241 — the frame and its contents visibly out of register,
        // which is most of what "totally broken" was. `Cubist` (508x189 art in a 508x350 view) and
        // `Radio` (265x128 in 265x167) author a top band and are the same shape vertically;
        // `Tomb Raider 2` is both axes at once.
        //
        // Scoped to a mismatch the **markup** states, not one a resize produced: 17 corpus views
        // declare literal `width`/`height` alongside a resolvable background image and exactly
        // those 4 disagree with it. Where the authored size and the artwork agree, a canvas the
        // user or a script grew still stretches the background exactly as before.
        var rootBackgroundSize: WMPSize?
        if authoredWidth != nil, authoredHeight != nil,
           let (_, backgroundPath) = try resolveResource(view, names: ["backgroundImage", "background"],
                                                         overrides: overrides,
                                                         warn: { diagnostics.append($0) }),
           let intrinsic = try? imageStore.image(for: backgroundPath).size,
           intrinsic.width > 0, intrinsic.height > 0,
           intrinsic.width != width || intrinsic.height != height {
            rootBackgroundSize = intrinsic
        }
        // **The size a script assigned the view is the window's; the size the markup authored stays
        // the baseline every child's alignment delta is measured against.** They are two different
        // questions and reading one value for both broke each in turn. A `.wmz` compact mode is a
        // handler writing `view.width`/`view.height` — `Cablemusic`'s `SwitchSmall()` asks for
        // 475x373 — and with the literal winning the canvas the compact player drew inside a
        // 593x600 window with two hundred empty pixels around it ("a large overlay"). But letting
        // the override *replace* the authored size collapsed every alignment delta to zero:
        // `LostPlanet`'s `onLoadInfo` opens with `view.width = view.minWidth`, and its stretch
        // tiles — sized from `canvas − authored` — stopped covering the 61 px they had been
        // covering, punching holes through the window frame.
        let defaultSize = WMPSize(width: viewOverride("width") ?? width,
                                  height: viewOverride("height") ?? height)
        // **A mode is a size floor the script writes, not one the markup states (W196).** Four of
        // the view's attributes are a resize *contract* rather than a layout — `minWidth`,
        // `minHeight`, `maxWidth`, `maxHeight` — and a skin with more than one mode moves them as
        // it switches: `NVIDIA`'s `setModesMinWidth('playlist')` raises the floor from 285x301 to
        // 700x480 before `autoSizeView` grows the window to it, and lowers it again for audio mode.
        // Read only from the markup, the floor stayed at the audio mode's 285x301 for the whole
        // session, so the playlist could be dragged — or left by a script that assigned one axis —
        // down to a quarter of the size its own layout needs, where `plListBoxSub`, `plExtraInfo`
        // and four more of its children resolve to negative heights and the library, the search box
        // and the album badge draw on top of one another. Reported 2026-09-16 as "the playlist
        // library is opening very small size now and possibly distorting the aspect ratio".
        //
        // These arrive in `overrides.properties` and not in `overrides.geometry`: the runtime
        // routes only `left`/`top`/`width`/`height` to geometry, and a limit is not a frame. So it
        // is `literalNumber`'s rule — a script write first, then the attribute — spelled here
        // because the view root is sized before that helper is in scope.
        func viewLimit(_ name: String) -> CGFloat? {
            if let value = overrides.properties[WMPScenePropertyAddress(stableID: view.stableID,
                                                                        property: name.lowercased())],
               let number = value.number, number.isFinite, number >= 0 { return CGFloat(number) }
            return literal(view, name)
        }
        let minimum = WMPSize(width: viewLimit("minWidth") ?? defaultSize.width,
                              height: viewLimit("minHeight") ?? defaultSize.height)
        let maxWidth = viewLimit("maxWidth"), maxHeight = viewLimit("maxHeight")
        let maximum: WMPSize? = maxWidth == nil && maxHeight == nil ? nil
            : WMPSize(width: maxWidth ?? .greatestFiniteMagnitude,
                      height: maxHeight ?? .greatestFiniteMagnitude)
        let resizeLimits = WMPResizeLimits(minimum: minimum, maximum: maximum)
        // `resizAble` is the corpus's dominant spelling and `resizable` the other; both appear in
        // the same archive. Absent is false — a borderless window gets its resize edges from this
        // and from nothing else.
        let resizable = (literalString(view, "resizAble") ?? literalString(view, "resizable"))?
            .caseInsensitiveCompare("true") == .orderedSame
        let canvas = resizeLimits.clamp(requestedSize ?? defaultSize)
        let canvasRect = WMPRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        // **A script that resizes a view the user cannot resize has not asked for its picture to
        // stretch either.** W164 anchored only a mismatch the markup states; a size a *script*
        // wrote on a fixed view is the same statement made at runtime. `gadget` opens its drawer
        // with `view.height = 333` over a 336x246 `base_unit.bmp` and hangs the drawer subview,
        // with its own `clippingColor` shape, in the rows below: stretched, the whole player grew
        // 35% taller and the view's black `backgroundColor` — unkeyed once the bitmap no longer
        // matched the frame — filled the canvas edge to edge. A resizable view is left as W164
        // left it.
        if rootBackgroundSize == nil, !resizable, !backgroundTiles(view),
           let (_, backgroundPath) = try resolveResource(view, names: ["backgroundImage", "background"],
                                                         overrides: overrides,
                                                         warn: { diagnostics.append($0) }),
           let intrinsic = try? imageStore.image(for: backgroundPath).size,
           intrinsic.width > 0, intrinsic.height > 0, intrinsic != canvas {
            rootBackgroundSize = intrinsic
        }

        // **A view whose own field states a matte gives its visualizer the rect as a backdrop
        // (W213).** An `<EFFECTS>` with no ancestor shape used to take no ground at all, and a
        // visualizer with no backdrop is a window with holes in it: `circle` showed the desktop
        // through the antialias fringe round its dial, through its three track-number panels — ten
        // `num*.bmp` that are nothing but a magenta glyph in a red matte, so the digit *is* whatever
        // the surface paints — and through its whole right-hand field. Reported 2026-09-17 as
        // *"it is still missing the backing on the volume"*.
        //
        // **The permission is a `clippingColor` on a full-canvas child, and that is the signal that
        // separates the reported skin from the one that refuses it.** `Plus! Plasma Ball/BubbleSkin`
        // shapes itself with `transparencyColor` **alone** — it never names a matte — and grounding
        // its rect turns 40,334 px of it black outside the silhouette, measured, which is the
        // counter-evidence `WMPEffectsGround` has carried since W174. A skin that declares both keys
        // over a canvas-sized field has distinguished *hole* from *matte*, and both of them are the
        // visualizer's. Read from the markup and the bitmap's own size, before the walk, because the
        // child that states it is laid out after the `<EFFECTS>` is visited.
        let viewStatesAMatte: Bool = try {
            for child in view.children where child.kind == .subview {
                guard !colors(child, names: ["clippingColor"]).isEmpty,
                      let path = try resource(child, names: ["backgroundImage", "background"])?.1,
                      literalString(child, "backgroundTiled")?
                          .caseInsensitiveCompare("true") != .orderedSame,
                      let decoded = try? imageStore.image(for: path),
                      CGFloat(decoded.image.width) == canvas.width,
                      CGFloat(decoded.image.height) == canvas.height else { continue }
                return true
            }
            return false
        }()

        var commands: [WMPPaintCommand] = []
        var hits: [WMPHitMetadata] = []
        // One alpha plane per (sprite, keys) for the length of this build. Coverage is asked for
        // once per interactive node and several nodes share a sprite, so decoding it per node is
        // the only cost worth avoiding here; nothing outlives the build.
        var paintSequence = 0
        var alphaPlanes: [String: WMPAlphaPlane?] = [:]
        /// A container shape read as a *keep* plane, for the coverage walks. Same cache discipline
        /// as `alphaPlane`, and the same lifetime; `WMPImageStore` caches the mask itself anyway.
        var keepPlanes: [String: WMPAlphaPlane?] = [:]
        func keepPlane(for shape: WMPSceneClipMask) -> WMPAlphaPlane? {
            let key = "\(shape.resourcePath)|\(shape.keyedOut.map(\.description).joined(separator: ","))"
                + (shape.exteriorOnly ? "|exterior" : "")
            if let cached = keepPlanes[key] { return cached }
            let plane = (try? imageStore.regionMask(for: shape))
                .flatMap { WMPAlphaPlane(keepMask: $0) }
            keepPlanes[key] = plane
            return plane
        }
        func alphaPlane(for image: WMPSceneImage) -> WMPAlphaPlane? {
            let key = "\(image.resourcePath)|\(image.colorKeys.map(\.description).joined(separator: ","))"
                + "|\(image.implicitColorKey?.description ?? "-")"
            if let cached = alphaPlanes[key] { return cached }
            let plane = (try? imageStore.image(for: image.resourcePath, colorKeys: image.colorKeys,
                                               implicitKey: image.implicitColorKey))
                .flatMap { WMPAlphaPlane($0.image) }
            alphaPlanes[key] = plane
            return plane
        }
        var widgets: [WMPWidget] = []
        // A fully transparent node still lays out — its geometry is readable, and a script fades
        // it in by writing `alphaBlend` — but it draws nothing, so it must not reach the command
        // list at all. Leaving it there put invisible artwork inside `visibleBounds` and every
        // dirty rect derived from it. Filtering here rather than after the walk is what keeps an
        // index into `commands` captured *during* the walk (`WMPWidget.commandSplitIndex`) exact.
        /// The clipping shapes of every container this walk is currently *inside*, outermost
        /// first. A node's own artwork is emitted before its own shape is pushed, so a container
        /// never clips itself twice: `WMPSceneImage.clippingMaskPath` already shapes its own draw.
        var clipMaskStack: [WMPSceneClipMask] = []
        /// The window shapes the containers above the current node have stated, innermost last.
        /// Only a `clippingColor` contributes one; see `WMPEffectsGround` and `groundShape`.
        var groundShapeStack: [WMPSceneClipMask] = []
        /// Whether the node being walked was put behind its parent's own artwork by that parent,
        /// and that parent authored an opaque fill under a keyed background image. See
        /// `WMPEffectsGround` — it is the one other permission a ground takes.
        var behindFilledArtworkStack: [Bool] = []
        /// The innermost keyed `<SUBVIEW>` the walk is inside, if any. See `WMPSceneMatte`.
        var matteStack: [WMPSceneMatte?] = []
        func emit(_ command: WMPPaintCommand) {
            guard command.alpha > 0 else { return }
            var matte = matteStack.last ?? nil
            if let candidate = matte, case .image(let image) = command.paint {
                matte = (try? imageStore.holdsKey(candidate.keys, for: image.resourcePath,
                                                  colorKeys: image.colorKeys,
                                                  implicitKey: image.implicitColorKey)) == true
                    ? candidate : nil
            }
            commands.append(command.under(matte).inside(clipMaskStack))
        }
        var geometries: [Int: WMPResolvedGeometry] = [:]
        /// Local frames of the drawn `<SUBVIEW>`s already walked under each parent, in paint order —
        /// the surfaces a later sibling sits on. Read only to bound an unsized `<TEXT>`.
        var drawnSurfaces: [Int: [(frame: WMPRect, stableID: Int)]] = [:]
        var unresolved: [WMPUnresolvedGeometry] = []
        var unresolvedNodes = Set<Int>()
        var unresolvedAttributes = Set<String>()
        var resolvedNodes = Set<Int>()
        var layoutResolver = WMPInitialLayoutResolver(graph: loadedSkin.graph, view: view, canvas: canvas)
        // The same grammar read at the canvas the markup was *written* for — the root's own
        // authored size, which is the baseline the root hands its children. See `authoredDimension`.
        var authoredLayoutResolver = WMPInitialLayoutResolver(
            graph: loadedSkin.graph, view: view, canvas: WMPSize(width: width, height: height))
        // Folded element id to node, for the view being built. `wmpprop:` paths that name another
        // element resolve through this; the first id wins, matching the duplicate-id rule.
        var idToNode: [String: WMPNode] = [:]
        func indexIDs(_ node: WMPNode) {
            if let id = node.xmlID?.lowercased(), idToNode[id] == nil { idToNode[id] = node }
            node.children.forEach(indexIDs)
        }
        indexIDs(view)

        /// The elements some other node reads a **coordinate** off, through
        /// `<attr>="wmpprop:<id>.<left|top|width|height>"`.
        ///
        /// A hidden node is never walked, so it has no resolved frame and `laidOutGeometry` falls
        /// back to the markup — the size the element was *authored* at, which is the size the
        /// window was born at and not the size it has been dragged to. `Compact` sizes its
        /// visualisation pane with `<subview id="svVisual" height="wmpprop:video1.height">`, and
        /// `video1` is `visible="false"` for the whole of audio playback: stretching the window
        /// grew the pane's width and left its height at the authored 240, so the visualizer inside
        /// it never followed the drag (W226).
        ///
        /// So a hidden node is measured — geometry only, no paint, no hit target, no widget and no
        /// children — but only when the graph actually asks where it is. Every other hidden node
        /// returns exactly where it did before.
        var geometryBindingTargets = Set<Int>()
        func indexGeometryBindings(_ node: WMPNode) {
            for name in ["left", "top", "width", "height"] {
                guard let attribute = node.attribute(named: name),
                      case let .binding(kind, path) = attribute.value, kind == .property,
                      let id = path.split(separator: ".", maxSplits: 1).first,
                      let target = idToNode[String(id).lowercased()] else { continue }
                geometryBindingTargets.insert(target.stableID)
            }
            node.children.forEach(indexGeometryBindings)
        }
        indexGeometryBindings(view)

        /// **A node a script has shown is drawn even inside a hidden container (W263).** Markup inherits —
        /// a default-visible child of a `visible="false"` subview stays hidden, and 2,630 corpus
        /// children rely on that — but an explicit script write of `visible = true` is the node's
        /// own answer. `Charlies_Angels_Full_Throttle` nests its whole face in `pos`, and its
        /// Gallery hides `pos` and shows `boxsmall`, the cut-down face inside it, along with the
        /// gallery's wings and pictures; drawing nothing below `pos` emptied the window. The US
        /// forces skins (`Stars and Stripes` and five siblings) show their Help and Credits text
        /// inside `help`/`credits`, which are authored hidden and never shown by any script.
        /// These are the hidden ancestors the walk has to pass through to reach such a node.
        var passThroughAncestors = Set<Int>()
        /// A binding's `true` is the node's default state, not a script's decision to show it.
        func scriptShows(_ node: WMPNode) -> Bool {
            let address = WMPScenePropertyAddress(stableID: node.stableID, property: "visible")
            return overrides.properties[address]?.truth == true
                && !overrides.boundProperties.contains(address)
        }
        /// **Only a show that changes the node's answer escapes (W308).** Every pass-through the
        /// corpus needs is a node authored hidden (`visible="false"`, or a binding) and shown by script — `Charlies_Angels`'
        /// `boxsmall`, the `US Army` family's `helpmask`/`helpdrawer`. `Gorillaz` writes
        /// `vis.visible = true` on a button that was never hidden when its left drawer opens, then
        /// closes the drawer by hiding `left_ear11`, the frame the button lives in; read as an
        /// escape, the button stayed on screen beside the shut drawer.
        func escapesHiddenAncestor(_ node: WMPNode) -> Bool {
            guard scriptShows(node), node.statedAttribute(named: "visible") != nil else { return false }
            return self.literalString(node, "visible")?.caseInsensitiveCompare("true") != .orderedSame
        }
        /// **…but never out of a pane the skin itself has closed (W309).** A container authored
        /// hidden that a script has shown before is a toggle, and hiding it again closes
        /// everything in it: `US Army`'s `hideinfomode()` hides `infomode` and, in the same
        /// handler, sets `infodown2.visible = true` on a scroll arrow inside it — and the
        /// `sflink` credit link it showed earlier sits inside `creditsmask`, closed the same way.
        /// Read as escapes, both stayed on the face after Info closed. `help`/`credits` (never
        /// shown by any script) and `Charlies_Angels`' `pos` (authored visible) are not toggles
        /// by this rule and still pass their shown children through.
        ///
        /// **…nor out of one the skin opens and has not opened yet.** `modernblue` nests its
        /// small player in `smallplayer`, authored hidden and shown only by `switchToSmall()`, and
        /// `onPlayStateChange` shows `smpauseb` inside it on every play; read as an escape, the
        /// small pause button drew over the large player's display. What separates it from
        /// `help` is that the skin's code can show `smallplayer` at all
        /// (`WMPLoadedSkin.scriptShowableIDs`).
        func closesSubtree(_ node: WMPNode) -> Bool {
            let address = WMPScenePropertyAddress(stableID: node.stableID, property: "visible")
            if overrides.scriptShown.contains(node.stableID) {
                return overrides.properties[address]?.truth == false
                    && self.literalString(node, "visible")?.caseInsensitiveCompare("false") == .orderedSame
            }
            guard overrides.properties[address]?.truth != true,
                  let attribute = node.attribute(named: "visible"),
                  case let .literal(authored) = attribute.value,
                  authored.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("false") == .orderedSame,
                  let id = node.xmlID?.lowercased() else { return false }
            return loadedSkin.scriptShowableIDs.contains(id)
        }
        /// **…and never out of a pane closed *after* it was shown (W311).** `Navigator`'s
        /// `movescren()` shows `vis` inside `visual`, an authored-visible pane, and `showconf()`/
        /// `showlist()`/`showlink()` then hide `visual` over it; read as an escape, the visualizer
        /// drew over the EQ, playlist and links. `Charlies_Angels`' Gallery hides `pos` *first* and
        /// then shows `boxsmall` inside it, which still escapes. The position of a script's last
        /// hide of any ancestor, or 0 when none hid it.
        func scriptHideOrder(_ node: WMPNode) -> Int {
            let address = WMPScenePropertyAddress(stableID: node.stableID, property: "visible")
            guard overrides.properties[address]?.truth == false,
                  !overrides.boundProperties.contains(address) else { return 0 }
            return overrides.visibleWriteOrder[node.stableID] ?? 0
        }
        func indexScriptShown(_ node: WMPNode, ancestors: [Int], closedAt: Int) -> Void {
            if closesSubtree(node) { return }
            if escapesHiddenAncestor(node),
               closedAt == 0 || overrides.visibleWriteOrder[node.stableID, default: 0] > closedAt {
                passThroughAncestors.formUnion(ancestors)
            }
            let closedAt = max(closedAt, scriptHideOrder(node))
            for child in node.children {
                indexScriptShown(child, ancestors: ancestors + [node.stableID], closedAt: closedAt)
            }
        }
        indexScriptShown(view, ancestors: [], closedAt: 0)

        /// A number a script may have written, then the markup's own.
        ///
        /// The type's `literal(_:_:)` reads the attribute and nothing else, and `<TEXT>` is where
        /// that showed: `Cablemusic` lays its readouts out with `txtShowLabel.fontSize = 7` over a
        /// markup that says `fontSize="10"`, so every label was measured *and* drawn three points
        /// too large — "Copyright:" ran out of its 55 px box and off the left edge of the LCD it
        /// was supposed to sit inside. Geometry has `parseDimension` and a slider has
        /// `sliderMetrics`; this is the same rule for the rest.
        func literalNumber(_ node: WMPNode, _ name: String) -> CGFloat? {
            if let value = overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                                        property: name.lowercased())],
               let number = value.number, number.isFinite { return CGFloat(number) }
            return literal(node, name) ?? referencedNumber(node, name)
        }

        /// A `<attr>="jscript:<element>.<property>"` answered from that element's own number.
        ///
        /// The runtime evaluates `jscript:` for geometry only, so `Classic`'s metadata readouts —
        /// `fontsize="jscript:clip_label.fontsize"` against a label's literal `9` — fell to the
        /// 12pt default and drew three points larger than their labels, running into the pane's
        /// right edge. The corpus authors this shape for nothing else. Bounded to one hop, like
        /// `mirroredVisibility`.
        func referencedNumber(_ node: WMPNode, _ name: String) -> CGFloat? {
            guard let attribute = node.attribute(named: name),
                  case let .jScript(source) = attribute.value else { return nil }
            let parts = source.trimmingCharacters(in: CharacterSet(charactersIn: "; \t\r\n"))
                .split(separator: ".")
            guard parts.count == 2,
                  let target = idToNode[String(parts[0]).lowercased()], target !== node,
                  String(parts[1]).caseInsensitiveCompare(name) == .orderedSame else { return nil }
            if let value = overrides.properties[WMPScenePropertyAddress(stableID: target.stableID,
                                                                        property: name.lowercased())],
               let number = value.number, number.isFinite { return CGFloat(number) }
            return literal(target, name)
        }

        func literalString(_ node: WMPNode, _ name: String) -> String? {
            if let value = overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                                        property: name.lowercased())] {
                return value.string
            }
            guard let attribute = node.attribute(named: name),
                  case let .literal(value) = attribute.value else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// A `visible="wmpprop:<element>.<property>"` answered from the skin's own graph, or nil
        /// when the path names no element here — `WoW` writes `wmpprop:plMode.visible`, and
        /// `plMode` is a name WMP's own object model owns and this skin never declares. Nil means
        /// *no answer*, which leaves the authored value standing; it is never the answer "hidden".
        /// Bounded to one hop: a mirror of a mirror is not authored anywhere in the corpus.
        func mirroredVisibility(of node: WMPNode) -> Bool? {
            guard let attribute = node.attribute(named: "visible"),
                  case let .binding(kind, path) = attribute.value, kind == .property else { return nil }
            let parts = path.split(separator: ".", maxSplits: 1)
            guard parts.count == 2,
                  let target = idToNode[String(parts[0]).lowercased()] else { return nil }
            let property = String(parts[1]).lowercased()
            if let override = overrides.properties[WMPScenePropertyAddress(stableID: target.stableID,
                                                                           property: property)] {
                return override.truth
            }
            guard let mirrored = target.attribute(named: property) else { return nil }
            guard case let .literal(value) = mirrored.value else { return nil }
            return value.caseInsensitiveCompare("false") != .orderedSame && !value.isEmpty
        }

        /// The colour a node draws with, which is not always the one its markup states.
        ///
        /// Three sources, in the order WMP answers them: a value the script assigned the property,
        /// the authored attribute, and — for `<attr>="wmpprop:<element>.<property>"` — the value
        /// that other element currently holds. `Colorchooser` needs all three at once and is the
        /// only archive in the corpus that binds a colour this way: its caption takes
        /// `foregroundColor="wmpprop:style.foregroundColor"` from an invisible `<TEXT id="style">`
        /// held purely as a palette, its transport strip takes
        /// `backgroundColor="wmpprop:mainBackground.backgroundColor"`, and its three RGB sliders
        /// drive `mainBackground.backgroundColor` from script. Reading markup alone drew the
        /// caption in the unset-colour white on a white panel — invisible — painted no fill at all
        /// behind the transport, and left the sliders with nothing to change.
        ///
        /// One hop, like `mirroredVisibility`, and for the same reason: a mirror of a mirror is not
        /// authored anywhere in the corpus.
        func mirroredColor(of node: WMPNode, names: [String]) -> WMPColor? {
            for name in names {
                if let override = overrides.properties[
                        WMPScenePropertyAddress(stableID: node.stableID, property: name.lowercased())],
                   let text = override.string,
                   let parsed = WMPAttributeParser.color(from: text) {
                    return parsed
                }
                guard let attribute = node.attribute(named: name) else { continue }
                if case let .color(value) = attribute.value { return value }
                if case let .binding(kind, path) = attribute.value, kind == .property {
                    let parts = path.split(separator: ".", maxSplits: 1)
                    guard parts.count == 2,
                          let target = idToNode[String(parts[0]).lowercased()] else { continue }
                    let property = String(parts[1])
                    if let override = overrides.properties[
                            WMPScenePropertyAddress(stableID: target.stableID,
                                                    property: property.lowercased())],
                       let text = override.string,
                       let parsed = WMPAttributeParser.color(from: text) {
                        return parsed
                    }
                    if let mirrored = target.attribute(named: property) {
                        if case let .color(value) = mirrored.value { return value }
                        if let parsed = WMPAttributeParser.color(from: mirrored.rawValue) { return parsed }
                    }
                    continue
                }
                if let parsed = WMPAttributeParser.color(from: attribute.rawValue) { return parsed }
            }
            return nil
        }

        /// A node's paint order, which the **script** owns as much as the markup does.
        ///
        /// `zIndex` is an ordinary writable property and seven archives animate it — 58 assignments
        /// across `Beck`, `Cablemusic`, `Charlies_Angels_Full_Throttle`, `Colorchooser`,
        /// `Plus! Professional`, `Spider-man` and `cyberchannel`. Reading only the markup left every
        /// one of those swaps drawing in its authored order, and on `Colorchooser` that reached the
        /// window itself: its `checkForContent()` raises `viz.zIndex` from -5 to 5 to bring the
        /// visualizer out in front, and with the node still sorted at -5 everything the skin painted
        /// after it — including `mainBackground`, the opaque white panel the whole player sits on —
        /// counted as artwork *above* the surface and was punched out by `windowedEffectsRects`.
        /// The result was a transparent, click-through hole through a non-opaque window wherever the
        /// visualizer was, for as long as a track played. Reported on 2026-09-14 as "the window has
        /// no backing when a track plays and it clicks through to the background".
        func zIndex(of node: WMPNode) -> Int {
            if let override = overrides.properties[
                    WMPScenePropertyAddress(stableID: node.stableID, property: "zindex")],
               let number = override.number, number.isFinite {
                return Int(number)
            }
            return Int(literal(node, "zIndex") ?? 0)
        }

        /// **At a `zIndex` tie a `<SUBVIEW>` paints above its non-subview siblings**, whichever
        /// comes first in the markup. `Plus! HueShifter` authors its equaliser drawer as the band
        /// subview *then* the tray's opaque `<buttonGroup>`, both `zIndex="2"`, and its shipped
        /// `hueshifter_final.jpg` shows the thumbs over the tray; `Plus! SlimLine` authors the same
        /// drawer the other way round at `zIndex="1"` and shows the same thing. Document order
        /// alone buried HueShifter's eight bands under the tray — no thumbs drawn, and every press
        /// landed on the tray artwork — reported as "the EQ in Plus! HueShifter is non-functional".
        /// Measured 2026-09-24 over 179 archives: 14 subview/sibling ties overlap, and apart from
        /// HueShifter they are hosted widgets (which sit above the scene regardless) or `TDK` and
        /// `portals`' `content_image`, which is hidden until the script pages to it.
        ///
        /// **Not against an `<EFFECTS>`, which keeps document order.** `anemone`
        /// parks `<subview id="blback" zIndex="-1">` — the black lens — *before* its
        /// `<effects zindex="-1">`; lifting the subview put the lens in the overlay over the
        /// spectrum and took it out of the backdrop lookup that shapes the surface (W205).
        func paintOrder(_ lhs: WMPNode, _ rhs: WMPNode) -> Bool {
            let leftZ = zIndex(of: lhs), rightZ = zIndex(of: rhs)
            guard leftZ == rightZ else { return leftZ < rightZ }
            let leftSubview = lhs.kind == .subview, rightSubview = rhs.kind == .subview
            guard leftSubview == rightSubview || lhs.kind == .effects || rhs.kind == .effects
            else { return rightSubview }
            return lhs.stableID < rhs.stableID
        }

        func recordUnresolved(_ node: WMPNode, attribute: String, value: String) {
            let key = "\(node.stableID):\(attribute.lowercased())"
            guard unresolvedAttributes.insert(key).inserted else { return }
            unresolved.append(WMPUnresolvedGeometry(stableID: node.stableID, nodeID: node.xmlID,
                                                    attribute: attribute, authoredValue: value))
            unresolvedNodes.insert(node.stableID)
            diagnostics.append(WMPDiagnostic(.unresolvedGeometry,
                "Static layout cannot resolve \(node.authoredTagName).\(attribute)='\(value)'.",
                severity: .warning, location: node.location))
        }

        /// A `wmpprop:<element>.<left|top|width|height>` answered from **where that element is**,
        /// rather than from the attribute it does not carry.
        ///
        /// The static resolver reads the target's authored attribute, and a coordinate an
        /// alignment computes is not authored anywhere: the Alienware/ALX frame family hangs every
        /// side column off `<subview id="plLeftCenter" verticalAlignment="center">` with no `top`,
        /// and states the tile above it as `top="wmpprop:plLeftCenter.top"`. Read from markup that
        /// is **0**, so the tile painted at the top of the window, over the corner piece, and the
        /// white filler its author baked in for the list to cover landed in the caption band's
        /// right end — on every NullPlayer window wearing the borrowed frame (W212). WMP answers
        /// the read from the live object model, which is where the element *is*, and so does this
        /// skin's own window through the script runtime; the surfaces built without one — the
        /// borrowed frame — had no other source for it.
        ///
        /// Two sources, in this order. An element this build has already placed answers from its
        /// resolved frame. One it has not is answered only for the coordinate **centring**
        /// computes — the walk is in paint order, so a tile at `zIndex=6` reads a centre piece at
        /// `zIndex=10` — and only when it states no coordinate of its own on that axis, which is
        /// the whole of the case the static resolver reads wrong.
        var resolvingBindings = Set<Int>()
        func laidOutGeometry(_ path: String) -> CGFloat? {
            let parts = path.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, let target = idToNode[String(parts[0]).lowercased()],
                  resolvingBindings.insert(target.stableID).inserted else { return nil }
            defer { resolvingBindings.remove(target.stableID) }
            let property = String(parts[1]).lowercased()
            if let geometry = geometries[target.stableID] {
                switch property {
                case "left": return geometry.localFrame.x
                case "top": return geometry.localFrame.y
                case "width": return geometry.localFrame.width
                case "height": return geometry.localFrame.height
                default: return nil
                }
            }
            guard property == "top" || property == "left",
                  target.attribute(named: property) == nil,
                  view.children.contains(where: { $0 === target }) else { return nil }
            let down = property == "top"
            let alignment = down ? WMPAxisAlignment(vertical: literalString(target, "verticalAlignment"))
                                 : WMPAxisAlignment(horizontal: literalString(target, "horizontalAlignment"))
            guard alignment == .center else { return nil }
            var extent = parseDimension(target, down ? "height" : "width")
            if extent == nil,
               let resolved = try? resolveResource(target,
                                                   names: intrinsicSizeResourceNames(for: target.kind),
                                                   overrides: overrides, warn: { _ in }),
               let size = try? imageStore.image(for: resolved.1).size {
                extent = down ? size.height : size.width
            }
            guard let extent, extent.isFinite else { return nil }
            return ((down ? canvas.height : canvas.width) - extent) / 2
        }

        func parseDimension(_ node: WMPNode, _ name: String) -> CGFloat? {
            if let value = overrides.geometry[WMPScenePropertyAddress(stableID: node.stableID,
                                                                      property: name.lowercased())],
               value.isFinite { return value }
            if let attribute = node.attribute(named: name),
               case let .binding(kind, path) = attribute.value, kind == .property,
               let value = laidOutGeometry(path), value.isFinite {
                return value
            }
            guard let property = WMPInitialLayoutResolver.Property(rawValue: name.lowercased()) else { return nil }
            switch layoutResolver.resolve(node, property: property) {
            case let .value(value): return value
            case let .unresolved(reason, interpretable):
                // An *extent* the grammar cannot read at all is about to be answered by the
                // artwork's own size in `statesDimension`, so recording it here would report a
                // starved node that is not one — and if there is no artwork, the size guard below
                // still records it as `missing literal geometry` (W240). An **origin** is not in
                // that bargain: there is no ambient default to take a position from, and
                // `left="JScript:danger();"` must stay a rejection rather than quietly become 0.
                let answerable = !interpretable && (name.lowercased() == "width"
                                                    || name.lowercased() == "height")
                guard !answerable, let attribute = node.statedAttribute(named: name) else { return nil }
                recordUnresolved(node, attribute: name, value: "\(attribute.rawValue) [\(reason)]")
                return nil
            }
        }

        /// Did the skin **state** this dimension, in the sense the ambient default cares about?
        ///
        /// Three things answer no, and they are one rule: the attribute is absent, it is present
        /// with an empty value (W241), or it carries a value this grammar rejects outright (W240).
        /// In all three WMP falls back to its ambient default — 0 for an origin, the artwork's own
        /// size for an extent — because none of them is a statement of geometry. A *well-formed*
        /// expression whose references are not known yet is the opposite case and stays stated:
        /// a script may still satisfy it, and stamping the bitmap's size over it is the regression
        /// the intrinsic-size gate's own comment warns about.
        func statesDimension(_ node: WMPNode, _ name: String) -> Bool {
            guard node.statedAttribute(named: name) != nil else { return false }
            // Extents only. An origin has no content-derived default to fall back to, so an
            // unreadable `left` stays a rejection — which is what keeps `left="JScript:danger();"`
            // out of the scene instead of drawing it at 0.
            guard let property = WMPInitialLayoutResolver.Property(rawValue: name.lowercased()),
                  property == .width || property == .height else {
                return true
            }
            // The resolver memoizes per node and property, so this is the same lookup
            // `parseDimension` already made.
            if case .unresolved(_, false) = layoutResolver.resolve(node, property: property) {
                return false
            }
            return true
        }

        /// The extent this node states **in its own markup**, with a geometry binding read the way
        /// the static grammar reads it rather than from where the target has been laid out.
        ///
        /// `parseDimension` is the frame; this is the baseline every child's alignment delta is
        /// measured from, and the two part company on exactly one kind of attribute. A
        /// `height="wmpprop:video1.height"` now follows the target's *resolved* frame, so a pane
        /// bound to a stretching sibling grows with the window — and if that grown extent were
        /// also the baseline, the delta would be zero and nothing inside the pane would move.
        /// `Compact`'s `svVisual` is 240 authored and 462 when the window is dragged 222 taller:
        /// its visualizer and the effects strip under it follow the drag only because the
        /// difference between those two numbers is what their alignment reads (W226).
        ///
        /// **An expression is read at the authored canvas too, for the same reason.** `Back to
        /// the Future Trilogy`'s playlist drawer is `height="jscript:view.height"`, and its right
        /// rail inside it is a 12pt `stretch` tile between a 194pt top and a 102pt bottom — which
        /// meet exactly at the view's authored 308. Read at the live canvas the drawer's baseline
        /// was the grown height, the rail's delta was zero, and every height past 308 opened a
        /// bare run down the window's right edge: 168pt at 464, 339pt on a 635pt library window.
        func authoredDimension(_ node: WMPNode, _ name: String) -> CGFloat? {
            let address = WMPScenePropertyAddress(stableID: node.stableID, property: name.lowercased())
            // A script-*assigned* extent is a baseline — W225's reason: the handler stated that
            // size deliberately, and its children's margins are measured from it. An override the
            // runtime wrote while re-evaluating an authored expression or binding is not: it is
            // this canvas's answer, echoed back, and reading it here is what made the delta zero.
            if overrides.scriptAssignedGeometry[address] != nil,
               let value = overrides.geometry[address], value.isFinite { return value }
            guard let property = WMPInitialLayoutResolver.Property(rawValue: name.lowercased()),
                  case let .value(value) = authoredLayoutResolver.resolve(node, property: property)
            else { return nil }
            return value
        }

        /// Did this coordinate come from something that already knows the view's current size?
        ///
        /// A script override and a `JScript:`/`wmpprop:` attribute both do — they were evaluated
        /// against this canvas. So does a bare literal the static grammar has to parse rather than
        /// read (`left="view.width-10"`, which the corpus writes without the prefix). Only a plain
        /// finite number, or an absent attribute, is geometry alignment is entitled to move.
        func isComputed(_ node: WMPNode, _ name: String) -> Bool {
            let address = WMPScenePropertyAddress(stableID: node.stableID,
                                                  property: name.lowercased())
            if overrides.geometry[address] != nil {
                return true
            }
            guard let attribute = node.attribute(named: name) else { return false }
            guard case let .literal(raw) = attribute.value else { return true }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(trimmed).map { !$0.isFinite } ?? true
        }

        func resource(_ node: WMPNode, names: [String]) throws -> (String, String)? {
            try resolveResource(node, names: names, overrides: overrides,
                                warn: { diagnostics.append($0) })
        }

        /// The clipping shape this node imposes on its own contents, or nil for the overwhelming
        /// majority of nodes that impose none.
        ///
        /// The bitmap is the `clippingImage` where one is declared and the node's own background
        /// artwork otherwise — 84 `<SUBVIEW>`s across 38 archives and 26 `<VIEW>`s across 17 state
        /// the shape that second way, with a `clippingColor` and no `clippingImage`, and
        /// `Combat_Flight_Simulator_3` is the archive that showed what it costs to ignore them.
        /// A childless node needs no mask: its own draw already carries one.
        ///
        /// **`transparencyColor` states the shape as often as `clippingColor` does, and only on the
        /// background-image path (W172).** A `<SUBVIEW>` whose whole background *is* a two-tone
        /// mask has said the same thing whichever attribute names the key — `Plus! HueShifter`'s
        /// five subviews write `transparencyColor="white"` over `body_Mask.gif`,
        /// `playlist_tray_wholemask.gif` and three siblings, and reading only `clippingColor` left
        /// every one of them a plain rectangle: its bottom "candy" hung 22 px below the player's
        /// silhouette in a colour nothing else on screen was, reported as *"has a green section"*.
        /// 127 nodes across 17 archives qualify, every one of them naming a file `…mask`, and the
        /// three guards below are what separate them from artwork — the mask is at the node's own
        /// size, untiled, and two-toned. `clippingImage` is deliberately **not** widened the same
        /// way: a node that names a mask file outright has one key attribute for it.
        func clipMask(_ node: WMPNode, frame: WMPRect) throws -> WMPSceneClipMask? {
            guard !node.children.isEmpty, !frame.isEmpty else { return nil }
            let clipping = colors(node, names: ["clippingColor"])
            if let path = try resource(node, names: ["clippingImage"])?.1 {
                guard !clipping.isEmpty, clippingImageFits(path, frame) else { return nil }
                return WMPSceneClipMask(resourcePath: path, keyedOut: clipping, frame: frame)
            }
            let keys = clipping.isEmpty ? colors(node, names: ["transparencyColor"]) : clipping
            guard !keys.isEmpty else { return nil }
            // **A background image is only a shape when it is authored at the node's own size.**
            // `Gorillaz` is why: its `noodle` view is 781x467 over a `background.gif` that is a
            // 50x28 swatch of solid `#33CC66` with `backgroundTiled="true"`, and its
            // `clippingColor="#33CC66"` says "my ground is invisible" — not "my window is empty".
            // Reading the tile as a shape clipped away the whole skin, all 143,248 px of it, and it
            // is the corpus's only total loss under this rule. The same test is what W160 landed on
            // for resampling: a bitmap standing in for a frame it does not cover is not that frame.
            // …and only when it is a mask rather than a picture with a keyed hole in it, which is
            // `isShapeMask` and is where `YIL!OMA2K` holds the rule down.
            guard let path = try resource(node, names: ["backgroundImage", "background"])?.1,
                  literalString(node, "backgroundTiled")?.caseInsensitiveCompare("true") != .orderedSame,
                  let decoded = try? imageStore.image(for: path),
                  CGFloat(decoded.image.width) == frame.width,
                  CGFloat(decoded.image.height) == frame.height,
                  try imageStore.isShapeMask(for: path) else { return nil }
            return WMPSceneClipMask(resourcePath: path, keyedOut: keys, frame: frame)
        }

        /// The window shape a container states for an `<EFFECTS>` ground beneath it: its clipping
        /// artwork with its own `clippingColor` keyed out, and nothing else.
        ///
        /// **`clippingColor` only — never `transparencyColor`, and never a fallback to it.** This
        /// is the one place the W172 widening must not reach: a container that shapes itself with
        /// `transparencyColor` alone has not distinguished the matte outside its silhouette from a
        /// hole inside it, and a ground keyed off that would paint black outside the skin
        /// (`Plus! BubbleSkin`'s 44% of its rect, `circle`'s `vVid`). Where a container writes both
        /// — `backgroundColor="none" clippingColor="#FF0000" transparencyColor="#FF00FF"`, the
        /// corpus's house idiom — it has said exactly which one is which. See `WMPEffectsGround`.
        ///
        /// The background path takes the same size guard `clipMask` does and for the same reason:
        /// a bitmap standing in for a frame it does not cover is not that frame (`Gorillaz`).
        /// `isShapeMask` is deliberately *not* required — this artwork is a picture with keys cut
        /// out of it, which is exactly the population that guard excludes.
        /// The window silhouette a `<VIEW>` takes from its body when it states none of its own:
        /// the lowest subview, sized by its artwork alone to the whole canvas and keyed by
        /// `transparencyColor`, with the keyed matte round the outside cut from **everything** in
        /// the view — not only from the body's own artwork.
        ///
        /// A WMP window is a region, and a control drawn over the region's matte is outside the
        /// window. `xXx_night_vision_redx` is authored against that: its open, info and EQ buttons
        /// carry a flat `#ADCC31` field outside the ring, every pixel of it over `main_bg.png`'s
        /// `#FF00FF`, and drawn unclipped they were green boxes on the window's edge. Only the matte
        /// connected to the bitmap's edge is cut (`exteriorOnly`): a keyed hole inside the body is
        /// where it shows its visualizer, and `transparencyColor` alone does not say which is which.
        func bodySilhouette(_ node: WMPNode, frame: WMPRect) throws -> WMPSceneClipMask? {
            guard node.kind == .view, !frame.isEmpty,
                  node.statedAttribute(named: "clippingColor") == nil,
                  node.statedAttribute(named: "clippingImage") == nil,
                  try resource(node, names: ["backgroundImage", "background"]) == nil else { return nil }
            let subviews = node.children.filter { $0.kind == .subview }
            guard let lowest = subviews.map({ zIndex(of: $0) }).min() else { return nil }
            let bodies = subviews.filter { zIndex(of: $0) == lowest }
            guard bodies.count == 1, let body = bodies.first,
                  literalString(body, "left").map({ Double($0) == 0 }) ?? true,
                  literalString(body, "top").map({ Double($0) == 0 }) ?? true,
                  body.statedAttribute(named: "width") == nil,
                  body.statedAttribute(named: "height") == nil,
                  body.statedAttribute(named: "clippingColor") == nil,
                  body.statedAttribute(named: "clippingImage") == nil,
                  literalString(body, "backgroundTiled")?.caseInsensitiveCompare("true") != .orderedSame
            else { return nil }
            let keys = colors(body, names: ["transparencyColor"])
            guard !keys.isEmpty,
                  let path = try resource(body, names: ["backgroundImage", "background"])?.1,
                  let decoded = try? imageStore.image(for: path),
                  CGFloat(decoded.image.width) == frame.width,
                  CGFloat(decoded.image.height) == frame.height else { return nil }
            var mask = WMPSceneClipMask(resourcePath: path, keyedOut: keys, frame: frame)
            mask.exteriorOnly = true
            return mask
        }

        /// The matte a keyed `<SUBVIEW>`'s artwork states for the children drawn inside it: its
        /// `transparencyColor`-keyed pixels, under the same size and tiling guards `clipMask`
        /// takes. See `WMPSceneMatte`.
        func matte(_ node: WMPNode, frame: WMPRect) throws -> WMPSceneMatte? {
            guard node.kind == .subview, !node.children.isEmpty, !frame.isEmpty,
                  literalString(node, "backgroundTiled")?.caseInsensitiveCompare("true") != .orderedSame
            else { return nil }
            let keys = colors(node, names: ["transparencyColor"])
            guard !keys.isEmpty,
                  let path = try resource(node, names: ["backgroundImage", "background"])?.1,
                  let decoded = try? imageStore.image(for: path),
                  CGFloat(decoded.image.width) == frame.width,
                  CGFloat(decoded.image.height) == frame.height else { return nil }
            var shape = WMPSceneClipMask(resourcePath: path, keyedOut: keys, frame: frame)
            shape.inverted = true
            return WMPSceneMatte(shape: shape, keys: keys)
        }

        /// Whether a node's `clippingImage` can shape it at all. A mask larger than the node on
        /// **both** axes cannot (W309): `US Army` and its five siblings clip their 191x143
        /// `helpmask` and `creditsmask` panes with `infomask.gif`, a 370x370 plate whose black key
        /// is exactly the pane's rect in its *parent's* coordinates. Stretched over the pane, the
        /// black cut a hole in the help text and the pane's pink `backgroundColor` showed through;
        /// at the pane's origin it cut the corner instead; at the parent's origin it keys out the
        /// whole pane, text and all. The skin is only right with no mask: the opaque 191-wide
        /// `infohelp1.gif`/`infocred1.gif` then cover the pink, which is what the authors saw.
        /// Those twelve nodes are the corpus's whole population of this shape; every other
        /// mismatched mask is smaller than its node on at least one axis and keeps the stretch.
        func clippingImageFits(_ path: String, _ frame: WMPRect) -> Bool {
            guard let image = try? imageStore.image(for: path).image else { return true }
            return !(CGFloat(image.width) > frame.width && CGFloat(image.height) > frame.height)
        }

        func groundShape(_ node: WMPNode, frame: WMPRect) throws -> WMPSceneClipMask? {
            guard !frame.isEmpty else { return nil }
            let clipping = colors(node, names: ["clippingColor"])
            guard !clipping.isEmpty else { return nil }
            if let path = try resource(node, names: ["clippingImage"])?.1 {
                guard clippingImageFits(path, frame) else { return nil }
                return WMPSceneClipMask(resourcePath: path, keyedOut: clipping, frame: frame)
            }
            guard let path = try resource(node, names: ["backgroundImage", "background"])?.1,
                  literalString(node, "backgroundTiled")?.caseInsensitiveCompare("true") != .orderedSame,
                  let decoded = try? imageStore.image(for: path),
                  CGFloat(decoded.image.width) == frame.width,
                  CGFloat(decoded.image.height) == frame.height else { return nil }
            return WMPSceneClipMask(resourcePath: path, keyedOut: clipping, frame: frame)
        }

        /// The region a container's own `backgroundColor` fill is allowed to paint in: its
        /// background artwork with **both** of its keys cut away.
        ///
        /// **A container's fill and its background image are one layer, and the container's keys
        /// are applied to the composite** — which is what `backgroundColor="none"` already gets by
        /// having no fill at all. Painting the fill as a bare rectangle under a keyed image is two
        /// layers, and it fills in every hole the image cuts: the `clippingColor` matte outside the
        /// silhouette, so the window is a slab rather than a shape, and the `transparencyColor`
        /// hole inside it, which on this idiom is *always* the visualizer's (W199).
        ///
        /// **The measured population is 10 nodes in 9 archives** — a container declaring a
        /// `backgroundColor` other than `none`, at least one key, and a background image
        /// (`Asimov_Radio`, `Nautical`, `anime`, `aoe`, `bluegrid`, `cerulean`, `claw`, `gadget`,
        /// and `pharaoh` twice) — and **five of them hang an `<EFFECTS zIndex="-1">` under the
        /// keyed hole**: `aoe`, `bluegrid`, `claw`, `gadget` and `pharaoh`, each rect within 2 px
        /// of the hole's own bounds. Every one of those five rendered a fully opaque rectangle with
        /// no visualizer in it, and `pharaoh`'s own `vRos` is the control — same markup, same keys,
        /// `backgroundColor="none"`, and it clips.
        ///
        /// Both keys, unlike `groundShape`, and the difference is deliberate: that one answers
        /// *where the window is* and must never read a hole as a matte, while this one answers
        /// *where the composite is opaque* and a hole is as transparent as the matte around it.
        ///
        /// The size and tiling guards are `clipMask`'s, for `clipMask`'s reason — a bitmap standing
        /// in for a frame it does not cover is not that frame (`Gorillaz`). `isShapeMask` is not
        /// required here for `groundShape`'s reason: this artwork is a picture with keys cut out of
        /// it, which is exactly the population that guard excludes.
        func backgroundFillMask(_ node: WMPNode, frame: WMPRect) throws -> WMPSceneClipMask? {
            guard node.kind == .view || node.kind == .subview, !frame.isEmpty else { return nil }
            let keys = colors(node, names: ["clippingColor", "transparencyColor"])
            guard !keys.isEmpty else { return nil }
            guard let path = try resource(node, names: ["backgroundImage", "background"])?.1,
                  literalString(node, "backgroundTiled")?.caseInsensitiveCompare("true") != .orderedSame,
                  let decoded = try? imageStore.image(for: path),
                  CGFloat(decoded.image.width) == frame.width,
                  CGFloat(decoded.image.height) == frame.height else { return nil }
            return WMPSceneClipMask(resourcePath: path, keyedOut: keys, frame: frame)
        }

        /// A slider's numbers, from the same three places every other property comes from: a live
        /// script/`wmpprop:` override first, then an authored literal, then WMP's own default.
        func sliderMetrics(_ node: WMPNode) -> WMPSliderMetrics {
            func number(_ names: [String]) -> Double? {
                for name in names {
                    if let override = overrides.properties[WMPScenePropertyAddress(
                        stableID: node.stableID, property: name.lowercased())]?.number,
                       override.isFinite { return override }
                    if let value = literal(node, name) { return Double(value) }
                }
                return nil
            }
            // **WMP's default range is 0-100, and a `<BALANCESLIDER>`'s is not.** The tag states
            // its own scale — balance runs -100 (full left) to 100 (full right) with silence at
            // the centre — so 15 of the corpus's 16 balance sliders, which author no `min` at all,
            // were being laid out on a 0-100 track with their value at the bottom of it. The
            // matching implicit `value` binding is `WMPObservablePropertyRegistry.implicit`.
            let defaults = Self.defaultRange(for: node.kind)
            let minimum = number(["min", "minValue"]) ?? defaults.minimum
            let maximum = number(["max", "maxValue"]) ?? defaults.maximum
            return WMPSliderMetrics(direction: WMPSliderDirection(authored: literalString(node, "direction")),
                minimum: minimum, maximum: maximum,
                value: number(["value"]) ?? minimum,
                borderSize: literal(node, "borderSize") ?? 0)
        }

        /// The metrics the `foregroundImage` fill is measured with — the slider's own value
        /// unless the skin redirected it to `foregroundProgress`, which WMP scales 0-100.
        func progressSource(_ node: WMPNode, _ slider: WMPSliderMetrics) -> WMPSliderMetrics {
            guard literalString(node, "useForegroundProgress")?.caseInsensitiveCompare("true") == .orderedSame,
                  let progress = overrides.properties[WMPScenePropertyAddress(
                    stableID: node.stableID, property: "foregroundprogress")]?.number
                    ?? literal(node, "foregroundProgress").map(Double.init),
                  progress.isFinite else { return slider }
            return WMPSliderMetrics(direction: slider.direction, minimum: 0, maximum: 100,
                                    value: progress, borderSize: slider.borderSize)
        }

        func thumbSize(_ node: WMPNode) throws -> WMPSize? {
            guard let (_, path) = try resource(node, names: ["thumbImage", "thumbDownImage",
                                                             "thumbHoverImage", "thumbDisabledImage"]) else {
                return nil
            }
            return try imageStore.image(for: path).size
        }

        /// `alphaBlend` is 0-255 and inherits: a container the skin fades takes its whole subtree
        /// with it, which is how a `.wmz` hides a pane it has not opened yet.
        func inheritedAlpha(_ node: WMPNode, _ parent: CGFloat) -> CGFloat {
            guard let authored = overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                                              property: "alphablend")]?.number
                    ?? literal(node, "alphaBlend").map(Double.init) else { return parent }
            guard authored.isFinite else { return parent }
            return parent * max(0, min(1, CGFloat(authored) / 255))
        }

        func walk(_ node: WMPNode, parentFrame: WMPRect, parentAuthoredSize: WMPSize,
                  inheritedClip: WMPRect?, parentAlpha: CGFloat = 1, isRoot: Bool = false,
                  parentNode: WMPNode? = nil, parentNodeFrame: WMPRect? = nil,
                  insideHidden: Bool = false) throws {
            // A script override outranks the markup. Corona's `SetPane` switches its video and
            // visualization panes purely by writing `vid.visible` / `vis.visible`, so a builder
            // that reads only the authored attribute draws whichever the author happened to leave
            // on — which is how an opaque video pane ended up over the artwork as soon as playback
            // started.
            var hidden = false
            let visibleOverride = overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                                               property: "visible")]
            if let override = visibleOverride {
                if !override.truth { hidden = true }
            } else if let mirrored = mirroredVisibility(of: node) {
                // **A `wmpprop:` path can name another element in the same skin, not only a host
                // property.** 150 of the corpus's `visible="wmpprop:…"` attributes do: `WoW` hangs
                // its CD-rip bar off `wmpprop:playlist2.visible`, and 8 skins share that exact
                // line. Resolving it here is what keeps the bar hidden now that an *unanswerable*
                // path no longer resolves to a falsy empty string.
                if !mirrored { hidden = true }
            } else if !isRoot,
                      literalString(node, "visible")?.caseInsensitiveCompare("false") == .orderedSame {
                // `visible` is not a `<VIEW>` attribute: `gnome` is the one skin in the corpus that
                // authors `<view visible="false">`, never shows it from script, and loads in WMP.
                // Honouring it here dropped every node and left the main window empty.
                hidden = true
            }
            // Below a hidden ancestor only a node the script itself has shown is drawn — see
            // `passThroughAncestors`.
            if insideHidden, !escapesHiddenAncestor(node) { hidden = true }
            let passesThrough = hidden && passThroughAncestors.contains(node.stableID)
            // Measured-only, and only for a node the graph reads a coordinate off. A node with no
            // frame of its own has no coordinate to give, so `isNonLayout` still leaves here.
            if hidden, !passesThrough,
               !geometryBindingTargets.contains(node.stableID) || isNonLayout(node) { return }
            if isNonLayout(node) {
                for child in node.children.sorted(by: paintOrder) {
                    try walk(child, parentFrame: parentFrame, parentAuthoredSize: parentAuthoredSize,
                             inheritedClip: inheritedClip, parentAlpha: parentAlpha,
                             parentNode: parentNode, parentNodeFrame: parentNodeFrame,
                             insideHidden: hidden)
                }
                return
            }

            let frame: WMPRect
            // The size this node would have had if its parent had not grown: the baseline every
            // child's alignment delta is measured against. It is *not* re-read from the markup
            // afterwards, because a node sized by its own artwork has no markup to re-read and the
            // frame is by then the stretched one — which made the delta zero and stopped alignment
            // cascading past any intrinsically sized container.
            let ownAuthoredSize: WMPSize
            if isRoot {
                frame = canvasRect
                ownAuthoredSize = WMPSize(width: width, height: height)
            } else {
                // **An origin the markup never stated can still have been written by script, and
                // asking the markup first meant it never was.** `left`/`top` default to 0 when the
                // skin authors neither — but the check was `attribute == nil ? 0 : resolve`, so a
                // node with no authored `left` short-circuited to 0 *before* `parseDimension` could
                // look in the scene overrides, and every element a handler positions from nothing
                // stacked at its parent's origin. `Cablemusic`'s two drawers are seventeen station
                // rows each, laid out entirely by `InitPrograms()` writing `pr<N>.top`/`.left`:
                // all thirty-four drew on top of one another in the corner of the drawer. Size
                // never had the bug, which is why the rows were the right *width* in the wrong
                // place. Overrides first, then the markup, then the default.
                let left = parseDimension(node, "left")
                    ?? (node.statedAttribute(named: "left") == nil ? 0 : nil)
                let top = parseDimension(node, "top")
                    ?? (node.statedAttribute(named: "top") == nil ? 0 : nil)
                var width = parseDimension(node, "width")
                var height = parseDimension(node, "height")

                if isStringConstantText(node, overrides, literalString) { return }

                if width == nil || height == nil,
                   !statesDimension(node, "width") || !statesDimension(node, "height"),
                   let (_, path) = try resource(node, names: intrinsicSizeResourceNames(for: node.kind)) {
                    let intrinsic = try imageStore.image(for: path).size
                    // `width`/`height` are already non-nil here only when a script override
                    // supplied them, since the markup authored no such attribute. The artwork's
                    // natural size is the fallback for an *unstated* dimension, never an answer
                    // that outranks one the skin computed: Corona's compact view collapses
                    // `svVideo` to height 0 through its own timer, and the background bitmap kept
                    // stamping 241 back over it, leaving a black panel across the whole window.
                    if !statesDimension(node, "width"), width == nil { width = intrinsic.width }
                    if !statesDimension(node, "height"), height == nil { height = intrinsic.height }
                }
                if isText(node.kind), width == nil || height == nil,
                   let glyphs = intrinsicTextSize(node, literal: literalNumber,
                                                  literalString: literalString) {
                    if !statesDimension(node, "width"), width == nil {
                        width = glyphs.width
                        // **An unsized `<TEXT>` is bounded by the surface it is drawn on.** WMP
                        // sizes it to its glyphs and lets a long value run on; `anime` hangs its
                        // `wmpprop:player.currentmedia.name` title at `left="400"` on the 350-wide
                        // screen that starts at 358, and a real track name ran off the screen,
                        // over the bezel and out of the window. Capped at the right edge of the
                        // smallest drawn sibling under its origin, the value overflows its box and
                        // the unauthored-`scrolling` marquee takes it. A value that fits is untouched.
                        // **A keyed sibling whose hole the text starts in bounds it at the hole.**
                        // The screen in `anime` is the `#00FF00` hole in the bezel subview drawn over
                        // that panel, and at the title's rows the bezel's rounded corner comes in
                        // 16 px short of the panel edge — the last glyphs sat on the grey rim.
                        if let left, let top, let parentNode,
                           let surfaces = drawnSurfaces[parentNode.stableID]?
                               .filter({ $0.frame.x <= left && left < $0.frame.x + $0.frame.width
                                         && $0.frame.y <= top && top < $0.frame.y + $0.frame.height }),
                           let smallest = surfaces.min(by: {
                               $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
                            var bound = smallest.frame.x + smallest.frame.width - left
                            for surface in surfaces {
                                guard let image = commands.last(where: { $0.stableID == surface.stableID })
                                        .flatMap({ command -> WMPSceneImage? in
                                            if case .image(let image) = command.paint { return image }
                                            return nil
                                        }),
                                      let plane = alphaPlane(for: image),
                                      surface.frame.width > 0, surface.frame.height > 0 else { continue }
                                let sx = CGFloat(plane.width) / surface.frame.width
                                let sy = CGFloat(plane.height) / surface.frame.height
                                let x0 = Int(((left - surface.frame.x) * sx).rounded(.down))
                                let rows = Int(((top - surface.frame.y) * sy).rounded(.down))
                                    ..< max(Int(((top - surface.frame.y) * sy).rounded(.down)) + 1,
                                            Int(((top + glyphs.height - surface.frame.y) * sy).rounded(.up)))
                                guard plane.alpha(atX: x0, y: rows.lowerBound) == 0 else { continue }
                                var edge = plane.width
                                for y in rows where y < plane.height {
                                    var x = x0
                                    while x < edge, plane.alpha(atX: x, y: y) == 0 { x += 1 }
                                    edge = min(edge, x)
                                }
                                bound = min(bound, surface.frame.x + CGFloat(edge) / sx - left)
                            }
                            if glyphs.width > bound, bound > 0 { width = bound }
                        }
                    }
                    if !statesDimension(node, "height"), height == nil { height = glyphs.height }
                }
                if !statesDimension(node, "height"), height == nil,
                   let intrinsicHeight = widgetKind(node)?.intrinsicHeight {
                    height = intrinsicHeight
                }
                guard let left, let top else {
                    if !unresolvedNodes.contains(node.stableID), !hidden {
                        recordUnresolved(node, attribute: "position", value: "missing literal geometry")
                    }
                    return
                }
                guard var width, var height else {
                    let isStringTable = width == nil && height == nil
                        && isStringTableText(node, literalString)
                    if !unresolvedNodes.contains(node.stableID), !isStringTable, !hidden {
                        let missing = [width == nil ? "width" : nil, height == nil ? "height" : nil]
                            .compactMap { $0 }.joined(separator: "+")
                        recordUnresolved(node, attribute: "size",
                                         value: "missing literal geometry (\(missing))")
                    }
                    // A script-sized container can still have a literal origin and independently
                    // literal descendants. Keep the container unresolved/unpainted and carry only
                    // its known origin. A zero-sized private baseline makes alignment delta zero; it
                    // is never emitted as authored geometry or used as a fallback paint frame.
                    let partial = WMPRect(x: parentFrame.x + left, y: parentFrame.y + top,
                        width: width ?? 0, height: height ?? 0)
                    let partialAuthored = WMPSize(width: width ?? 0, height: height ?? 0)
                    for child in hidden && !passesThrough ? [] : node.children.sorted(by: paintOrder) {
                        try walk(child, parentFrame: partial, parentAuthoredSize: partialAuthored,
                                 inheritedClip: inheritedClip, parentAlpha: parentAlpha,
                                 parentNode: node, parentNodeFrame: partial, insideHidden: hidden)
                    }
                    return
                }
                ownAuthoredSize = WMPSize(width: authoredDimension(node, "width") ?? width,
                                          height: authoredDimension(node, "height") ?? height)
                // **Alignment moves geometry the skin left as a literal, and nothing else.**
                //
                // A resizing `.wmz` states the same intent twice: WoW's `pl5_1` authors
                // `left="JScript:view.width-202"` *and* `horizontalAlignment="right"`, and so do its
                // six siblings and `plFrame` with `stretch`. The expression already reads the new
                // `view.width`, so adding the parent's growth on top counts the resize twice —
                // measured at exactly +200 on a 453→653 drag, which threw the whole right-hand
                // chrome (close button, search box, resize grip) off the canvas and read as "the
                // window resizes and the skin doesn't". The literal cases are untouched: `pl8_1`
                // has `left=208` with no `width`, and its `stretch` still fills the top tile.
                //
                // **`center` is the one alignment that is not a margin, and treating it as one was
                // a whole window frame.** `right`, `bottom` and `stretch` all say "hold this edge's
                // authored distance to the parent's edge", which is the delta form and is a no-op at
                // the authored size. `center` says the element *stays centred*, so the coordinate is
                // computed from the parent and the element's own size and the authored one on that
                // axis is not an offset into it — which is why a skin that wants a centred piece
                // authors no `top` for it at all. The Alienware/ALX frame family is built entirely
                // out of that: every one of their playlist, equaliser, visualisation and video
                // windows hangs its side columns off `<subview id="plLeftCenter"
                // verticalAlignment="center" backgroundImage="f_left_center.png"/>` with no `top`,
                // plus a tile above and below at `top="wmpprop:plLeftCenter.top"`. Read as an
                // offset, all of it collapsed to `top=0`: the two 175-wide side pieces painted over
                // `f_top_left.png`/`f_top_right.png` and took the window's whole title bar and the
                // top of its inner border with them, leaving white stubs where only the centre tile
                // survived. Reported as "the playlist and eq windows are not properly constructed,
                // the window border is not correct and there are large gaps", against AlienMorph and
                // every skin that shares the frame.
                //
                // **Nothing outranks centring on the centred axis — not an expression, and not a
                // coordinate a script wrote.** W143 carried the `isComputed` guard onto `center`
                // alongside the other three values, on WoW's `left="JScript:view.width-202"` beside
                // an alignment; WoW's alignment on that node is `right`, and a decoded scan of the
                // 180-archive corpus finds **3** centred nodes authoring an expression on the
                // centred axis, all in `Ice`, against 285 + 91 that author no coordinate at all. The
                // guard protected nothing it was written for and cost every drawer a skin slides by
                // script: `xsn_sports` opens both its video and visualisation drawers with
                // `visDrawer.moveTo(0, view.height-73, 400)`, where the `0` is not a position —
                // `moveTo` takes both axes, and the horizontal one is how the author says
                // "unchanged" for a piece that is centred. Honouring it pinned the 141-wide drawer
                // to the window's left edge while the cover artwork above it stayed centred, so the
                // window drew two drawers, one of them doubling the bottom border, with the
                // settings panel inside the misplaced one showing through the video and its tab
                // out at the corner where no click could reach it (W144). Ice's three read as
                // counter-evidence and agree: its 313-wide `Pl-xp.bmp` bottom bar ran off the right
                // edge of the playlist and visualisation windows and now sits under them.
                let horizontal = WMPAxisAlignment(horizontal: literalString(node, "horizontalAlignment"))
                let vertical = WMPAxisAlignment(vertical: literalString(node, "verticalAlignment"))
                // **A script-assigned alignment is anchored at the canvas it was assigned at.**
                // Writing the attribute is WMP re-measuring the element's margins there and then,
                // so the growth that counts afterwards is the growth *since the write* — the same
                // reading `scriptDelta` gives a script-assigned coordinate, for the same reason.
                // Only a child of the view root can be anchored this way: the anchor is a view
                // canvas, and a deeper node's parent grew by an amount the canvas does not state.
                func alignmentBaseline(_ property: String, _ authored: CGFloat,
                                       _ axis: KeyPath<WMPSize, CGFloat>) -> CGFloat {
                    guard isRoot || parentNode == nil || parentNode?.kind == .view,
                          let canvas = overrides.scriptAssignedAlignment[
                            WMPScenePropertyAddress(stableID: node.stableID, property: property)]
                    else { return authored }
                    return canvas[keyPath: axis]
                }
                let deltaWidth = parentFrame.width
                    - alignmentBaseline("horizontalalignment", parentAuthoredSize.width, \.width)
                let deltaHeight = parentFrame.height
                    - alignmentBaseline("verticalalignment", parentAuthoredSize.height, \.height)
                // **A coordinate a script wrote is anchored at the canvas it was written at (W159).**
                //
                // `isComputed` says "an expression owns this, so alignment must not move it" — an
                // expression has already re-read `view.width`/`view.height` and adding the parent's
                // growth would count the resize twice. A script assignment is neither that nor a
                // markup literal: the handler wrote a plain number against whatever the view
                // measured *at that moment*, so what carries its intent forward is the growth
                // **since the assignment**, not the growth since the markup was authored.
                //
                // Both skins in this story need exactly that reading. `NVIDIA`'s
                // `setModesMinWidth('playlist')` sets `mainModeMetadata.width = view.width-266`
                // while the view is still 285 — the number is 19 — and then takes the view to 730;
                // 19 plus the 445 it grew by is 464, which is `view.width-266` at the new size and
                // the width the bar visibly wants. `xsn_sports` writes
                // `visDrawer.moveTo(0, view.height-73, 400)` and is *already* at that canvas, so its
                // delta is zero and the drawer stays exactly where the script put it — and grows
                // only if the user later resizes the window, which is the re-anchoring that keeps a
                // retracted drawer retracted.
                //
                // Measuring it from the *authored* size instead moved 15 views that had no business
                // moving: `Catwoman`'s video settings drawer, the whole Alienware/ALX `videoView`
                // family and `Scooby-Doo_2`'s info panel all opened their panels into view, because
                // those skins size their view by script at load and the authored-size delta is not
                // zero there. The corpus render sweep is what caught it.
                let anchor = overrides.scriptAssignedGeometry
                func scriptDelta(_ name: String, _ fallback: CGFloat, _ axis: KeyPath<WMPSize, CGFloat>,
                                 _ parentExtent: CGFloat) -> CGFloat {
                    guard let canvas = anchor[WMPScenePropertyAddress(stableID: node.stableID,
                                                                      property: name)]
                    else { return fallback }
                    // **A script assignment on a nested node is already the answer, and the
                    // authored-size delta must not be added to it.** The re-anchoring above is the
                    // growth of the element's *parent* since the assignment, and only a child of
                    // the view root has a parent whose extent this canvas is — for anything deeper,
                    // `parentExtent` is a subview's height and the canvas is not what it grew from.
                    // The fallback is worse than nothing there: it is the growth since the
                    // *markup*, added on top of a number the handler measured at the current size,
                    // so the resize is counted twice.
                    //
                    // `Compact` is the worked case, and it is what is on screen. `svBanner`'s
                    // `visible_onchange` writes `svScreen.height = svScreenOuter.height -
                    // svScreen.top` the first time a track plays, and `myeffect` is
                    // `height="jscript:svScreen.height - top"` under it. Stretch the player to
                    // 620x573 and *then* start playing: both write the right number for that
                    // canvas — 435 and 410 — and both were then drawn 195 taller, 195 being
                    // 573 − 378, the growth since the authored size. The visualizer spilled out of
                    // the window over the transport strip. Nothing moves for a node the script
                    // never wrote, which is every other node in the corpus.
                    //
                    // **Growth after the write still counts.** The runtime records the parent's
                    // extent at the write, so the delta is how far the parent has grown since —
                    // zero at the canvas the handler measured, and the drag's share afterwards.
                    guard isRoot || parentNode == nil || parentNode?.kind == .view else {
                        guard let base = overrides.scriptAssignedParentExtent[
                            WMPScenePropertyAddress(stableID: node.stableID, property: name)]
                        else { return 0 }
                        return parentExtent - base
                    }
                    return parentExtent - canvas[keyPath: axis]
                }
                // The size the element had when the script assigned its alignment, if it did. The
                // markup's own value otherwise, which is every other node in the corpus.
                func alignmentExtent(_ name: String, _ authored: CGFloat) -> CGFloat {
                    guard isRoot || parentNode == nil || parentNode?.kind == .view,
                          let base = overrides.scriptAlignmentExtent[
                            WMPScenePropertyAddress(stableID: node.stableID, property: name)]
                    else { return authored }
                    return base
                }
                func aligns(_ name: String) -> Bool {
                    anchor[WMPScenePropertyAddress(stableID: node.stableID, property: name)] != nil
                        || !isComputed(node, name)
                }
                var x = left, y = top
                switch horizontal {
                case .center: x = (parentFrame.width - width) / 2
                case .trailing where aligns("left"):
                    x += scriptDelta("left", deltaWidth, \.width, parentFrame.width)
                case .stretch where aligns("width"):
                    width = max(0, alignmentExtent("width", width) + scriptDelta("width", deltaWidth,
                                                                                 \.width, parentFrame.width))
                default: break
                }
                switch vertical {
                case .center: y = (parentFrame.height - height) / 2
                case .trailing where aligns("top"):
                    y += scriptDelta("top", deltaHeight, \.height, parentFrame.height)
                case .stretch where aligns("height"):
                    height = max(0, alignmentExtent("height", height)
                        + scriptDelta("height", deltaHeight, \.height, parentFrame.height))
                default: break
                }
                frame = WMPRect(x: parentFrame.x + x, y: parentFrame.y + y, width: width, height: height)
            }

            let visible = inheritedClip.flatMap { frame.intersection($0) } ?? (inheritedClip == nil ? frame : nil)
            let local = WMPRect(x: frame.x - parentFrame.x, y: frame.y - parentFrame.y,
                                width: frame.width, height: frame.height)
            geometries[node.stableID] = WMPResolvedGeometry(localFrame: local,
                absoluteFrame: frame, visibleFrame: visible, clipRect: inheritedClip)
            if !hidden, node.kind == .subview, !frame.isEmpty, let parentNode {
                drawnSurfaces[parentNode.stableID, default: []].append((local, node.stableID))
            }
            // **A container collapsed to nothing clips its children away too.** `nil` is "no clip
            // at all" here, so a zero-area frame has to hand down a zero-area rect: `Classic` sets
            // `view.height = 359 - 183` for audio, its `stretch` video pane collapses to zero
            // height, and the centred `wmlogo` inside it drew unclipped across the nav bar.
            //
            // **Only a collapsed frame, not one that merely misses its parent.** `Back to the
            // Future Trilogy` authors its "previous visualization" button at `left="-25"`, wholly
            // outside the logo strip it belongs to, mirroring the next button on the other side —
            // clipping that too took the button off the window. Whether WMP clips it is unproven;
            // the corpus sweep said this is the one rule that moves only the reported skin.
            //
            // **A top-level `<SUBVIEW>` sized by its artwork alone is not a box, and does not clip
            // to one.** With no `width` or `height` of its own its frame is only the bitmap's
            // extent, and `Ursula` slides its playlist drawer out of the 388x224 `mainbg.bmp`
            // subview to `top="212"` in a 320-high view: clipped to the bitmap, the opened drawer
            // showed its first 12 rows and nothing else. `Creed` (same drawer, past `Main.bmp`) and
            // `Asimov_Radio` (a 190-high face hung 30px inside the sign it belongs to) say the same.
            // **Only a direct child of the view.** Nested, the same shape is a clipping window:
            // `Melvin`'s `x` subview is `clip.gif` with the eyelid parked wholly above it until a
            // blink slides it down, and unclipped the eyelid sat on top of the head.
            // **Only a keyed one — a window body, not a patch.** All three bodies declare a
            // `clippingColor` or `transparencyColor`. The `Xbox` family's `screen_buttons_back.png`
            // declares neither, and parks its visualization arrows 9px past its bottom edge to
            // hide them until the visualizer is on; unclipped they drew as two black boxes.
            let sizedByArtworkAlone = node.kind == .subview && parentNode?.kind == .view
                && (node.statedAttribute(named: "clippingColor") != nil
                    || node.statedAttribute(named: "transparencyColor") != nil)
                && node.statedAttribute(named: "width") == nil
                && node.statedAttribute(named: "height") == nil
                && authoredDimension(node, "width") == nil
                && authoredDimension(node, "height") == nil
            let childClip = frame.isEmpty && inheritedClip != nil
                ? WMPRect(x: frame.x, y: frame.y, width: 0, height: 0)
                : sizedByArtworkAlone ? inheritedClip
                : inheritedClip.flatMap { frame.intersection($0) } ?? (inheritedClip == nil ? frame : nil)
            // A measured hidden node stops here: it answers where it is and nothing else. Paint,
            // hit targets, widgets and the resolved/unresolved tallies all stay exactly as they
            // were before it was measured at all. Its children are walked only to reach a node the
            // script has shown (`passThroughAncestors`), and are hidden themselves unless they are.
            if hidden {
                guard passesThrough else { return }
                for child in node.children.sorted(by: paintOrder) {
                    try walk(child, parentFrame: frame, parentAuthoredSize: ownAuthoredSize,
                             inheritedClip: childClip, parentAlpha: inheritedAlpha(node, parentAlpha),
                             parentNode: node, parentNodeFrame: frame, insideHidden: true)
                }
                return
            }
            resolvedNodes.insert(node.stableID)
            let z = zIndex(of: node)
            let alpha = inheritedAlpha(node, parentAlpha)
            let slider = isSlider(node.kind) ? sliderMetrics(node) : nil
            let positionMap = try node.kind == .customSlider
                ? resource(node, names: ["positionImage"]).map {
                    try imageStore.positionMap(for: $0.1,
                        keyedOut: colors(node, names: ["transparencyColor", "clippingColor"]))
                  }
                : nil

            // **The container's artwork is the visualizer's shape.** Only `<EFFECTS>` reads it:
            // a `SUBVIEW`'s `transparencyColor` carves the region its windowless child is confined
            // to, and every other hosted surface in this engine is a real rectangular control.
            var regionMask: WMPWidgetRegionMask?
            // **…unless the `<EFFECTS>` names its own shape (W309).** `US Army` and its five
            // siblings write `clippingImage="vismask.gif" clippingColor="#FF00FF"` on the surface
            // itself — a 370x370 plate that keeps a small black disc in the middle of the face.
            // Its parent's `backgroundImage` is the same opaque file, which `shapesChildrenByRegion`
            // correctly refuses (Cerulean), so without this the spectrum filled the whole window.
            if node.kind == .effects, !frame.isEmpty,
               let (_, maskPath) = try resource(node, names: ["clippingImage"]) {
                let keys = clippingMaskKeys(node, path: maskPath)
                if !keys.isEmpty {
                    regionMask = WMPWidgetRegionMask(resourcePath: maskPath, keyedOut: keys, frame: frame)
                }
            }
            if node.kind == .effects, regionMask == nil, let parentNode, let parentNodeFrame,
               !parentNodeFrame.isEmpty,
               let (_, maskPath) = try resource(parentNode, names: ["backgroundImage", "background"]) {
                let keys = colors(parentNode, names: ["transparencyColor", "clippingColor"])
                // Only a container that shapes by region, never one that occludes by paint — the
                // two read the key oppositely, and `shapesChildrenByRegion` carries the corpus
                // measurement that separates them. Cerulean is the case this guard protects.
                if !keys.isEmpty,
                   try imageStore.shapesChildrenByRegion(for: maskPath, keyedOut: keys) {
                    regionMask = WMPWidgetRegionMask(resourcePath: maskPath, keyedOut: keys,
                                                     frame: parentNodeFrame)
                }
            }

            // **A skin can state the shape with the backdrop it parks behind the visualizer
            // instead of with the container around it (W205).** `anemone`'s `<EFFECTS>` is a child
            // of the `<VIEW>`, which has `backgroundColor="none"` and no artwork at all, so
            // neither the container rule above nor `groundShape` has anything to read — and its
            // own player art *cannot* be read as a shape, because `background.bmp` keys the lens
            // hole and the matte outside the anemone in the same `#00FF00` (19,433 px of hole,
            // 30,943 of matte). What does state it is the sibling immediately behind the surface:
            // `<subview id="blback" zIndex="-1" backgroundImage="blback.bmp"
            // transparencyColor="#00FF00">`, a 239x187 bitmap in exactly two colours — the black
            // lens the visualizer draws on, and the key around it.
            //
            // **The nearest sibling behind, and only if it is a mask rather than a picture.** Both
            // halves are load-bearing and `Mandalay` holds them down: its `<effects zIndex="-2">`
            // has `displayback` (5,691 colours, a picture) directly behind it at the same rect and
            // `black1.bmp` (two-toned, 531 black px) five layers further back at `zIndex="-7"`.
            // Taking any two-toned sibling would clip its visualizer to a 135x204 strip; taking
            // the nearest one finds the picture, which `isShapeMask` then rejects. Those two are
            // the whole corpus population of a childless keyed container beside an `<EFFECTS>`
            // (with `Vario` and `Military`, whose backdrops are pictures too).
            if node.kind == .effects, regionMask == nil, let parentNode {
                let behind = parentNode.children.sorted(by: paintOrder)
                    .prefix { $0.stableID != node.stableID }
                for sibling in behind.reversed() {
                    guard sibling.kind == .subview || sibling.kind == .view,
                          sibling.children.isEmpty,
                          let maskFrame = geometries[sibling.stableID]?.absoluteFrame,
                          !maskFrame.isEmpty,
                          let (_, maskPath) = try resource(sibling,
                                                           names: ["backgroundImage", "background"])
                    else { continue }
                    let keys = colors(sibling, names: ["transparencyColor", "clippingColor"])
                    // The size and tiling guards are `clipMask`'s, for `clipMask`'s reason — a
                    // bitmap standing in for a frame it does not cover is not that frame
                    // (`Gorillaz`).
                    guard !keys.isEmpty,
                          literalString(sibling, "backgroundTiled")?
                              .caseInsensitiveCompare("true") != .orderedSame,
                          let decoded = try? imageStore.image(for: maskPath),
                          CGFloat(decoded.image.width) == maskFrame.width,
                          CGFloat(decoded.image.height) == maskFrame.height,
                          try imageStore.isShapeMask(for: maskPath) else { break }
                    regionMask = WMPWidgetRegionMask(resourcePath: maskPath, keyedOut: keys,
                                                     frame: maskFrame)
                    break
                }
            }

            // **An `<EFFECTS>` that authors no backdrop of its own still has one, and in WMP it is
            // black (W174).** Only where the skin painted nothing does it show: the ground is laid
            // under every command in the below layer. A rect whose node declares its own
            // `backgroundImage` is excluded — that backdrop is already emitted and already moves
            // the split index past itself.
            //
            // **A parent that fills its own keyed artwork and hangs the rect behind it has said the
            // same thing a matte says.** `bluegrid`'s view is `backgroundImage="background.bmp"
            // backgroundColor="#000000" transparencyColor="#FF00FF"` with no `clippingColor`, and
            // its 19,200 magenta pixels are exactly the 160x120 screen its `<effects zIndex="-1">`
            // sits in. With no shape in scope that screen took no ground: a hole straight through
            // the window, see-through and click-through. Reported 2026-09-24 as *"visualizer has
            // empty background and can be clicked through"*. `Plus! BubbleSkin`, the reason the
            // transparency key alone is not a shape, authors no `backgroundColor` anywhere.
            var effectsGround: WMPEffectsGround?
            if node.kind == .effects, !frame.isEmpty,
               groundShapeStack.last != nil || viewStatesAMatte
                || behindFilledArtworkStack.last == true,
               try resource(node, names: ["backgroundImage", "background"]) == nil {
                let authored = color(node, names: ["backgroundColor"])
                effectsGround = WMPEffectsGround(frame: frame,
                    color: authored ?? WMPColor(red: 0, green: 0, blue: 0),
                    shape: groundShapeStack.last)
            }

            // **The window's own shape confines the surface too, and that is a separate statement
            // from the artwork drawn over it.** `groundShapeStack.last` is the nearest container's
            // `clippingColor` region — already what `effectsGround` is painted through — and a
            // rect that reaches past the silhouette needs it whether or not that ground is emitted
            // (a rect with its own `backgroundImage` has no ground). Cerulean is the reported case:
            // `face.bmp` occludes by paint, and paint stops at the pixels the skin cut away.
            var clippingShape: WMPWidgetRegionMask?
            if node.kind == .effects, let shape = groundShapeStack.last {
                clippingShape = WMPWidgetRegionMask(resourcePath: shape.resourcePath,
                                                   keyedOut: shape.keyedOut, frame: shape.frame)
            }

            // Patched once this node's own background is emitted — see `effectsWidgetIndex` below.
            var effectsWidgetIndex: Int?
            if let kind = widgetKind(node), visible != nil {
                if kind == .effects { effectsWidgetIndex = widgets.count }
                let label = literalString(node, "accessibleName")
                    ?? literalString(node, "title") ?? literalString(node, "name")
                    ?? node.xmlID ?? node.kind.description
                widgets.append(WMPWidget(stableID: node.stableID, nodeID: node.xmlID, kind: kind,
                    frame: frame, clipRect: inheritedClip, label: label,
                    toolTip: literalString(node, "toolTip") ?? literalString(node, "tooltip"),
                    minimumValue: slider?.minimum ?? (literal(node, "min") ?? literal(node, "minValue")).map(Double.init),
                    maximumValue: slider?.maximum ?? (literal(node, "max") ?? literal(node, "maxValue")).map(Double.init),
                    value: slider?.value, direction: slider?.direction,
                    borderSize: slider?.borderSize ?? 0,
                    thumbSize: try slider == nil ? nil : thumbSize(node),
                    valueBindingPath: valueBindingPath(node),
                    videoPresentation: kind == .video ? WMPVideoPresentation(
                        shrinkToFit: literalString(node, "shrinkToFit")?.lowercased() != "false",
                        stretchToFit: literalString(node, "stretchToFit")?.lowercased() == "true",
                        maintainAspectRatio: literalString(node, "maintainAspectRatio")?.lowercased() != "false",
                        alpha: Double(alpha)) : nil,
                    // The same inherited `alphaBlend` `emit` filters paint on. A hosted surface
                    // obeys its container's fade or it draws over artwork the fade removed.
                    alpha: alpha,
                    regionMask: regionMask, effectsGround: effectsGround,
                    clippingShape: clippingShape,
                    commandSplitIndex: commands.count,
                    isWindowedEffects: kind == .effects
                        && literalString(node, "windowed")?.lowercased() == "true"))
            }

            // **A negative `zIndex` means behind the parent's own artwork, so those children are
            // walked before this node paints anything.**
            //
            // DFS order alone cannot express it: a parent always paints before its children, so a
            // `zIndex="-1"` child emitted in tree order lands *over* the background it is declared
            // to sit behind. Cerulean is the worked case — `face.bmp` with a 73px magenta hole
            // keyed out of it, over `<effects zIndex="-1">` and `<button id="bEye" zIndex="-2">` —
            // and 32 `<EFFECTS>` across 30 skins use the same mechanism. Siblings are already
            // sorted by zIndex, so the eye still lands under the visualizer.
            let orderedChildren = node.children.sorted(by: paintOrder)
            // **A clipping shape shapes the element's contents, not only the element.** The mask
            // covers this node's frame and every descendant's paint is cut to it; see
            // `WMPSceneClipMask` for the two archives that state the rule and the one that guards
            // the key list. Past the bitmap of a container sized by it, the shape says nothing.
            let ownClipMask = try clipMask(node, frame: frame).map { mask -> WMPSceneClipMask in
                var mask = mask
                mask.boundedByFrame = !sizedByArtworkAlone
                return mask
            } ?? bodySilhouette(node, frame: frame)
            let ownGroundShape = try groundShape(node, frame: frame)
            let backgroundImage = try resource(node, names: ["backgroundImage", "background"])
            let hasBackgroundImage = backgroundImage != nil
            // **Artwork with no key has no hole, so nothing sits behind it (W310).** `Navigator`'s
            // `config` pane paints the opaque `screenback.bmp` with no `transparencyColor`,
            // `clippingColor` or `clippingImage`, and holds its EQ, links, playlist and video
            // settings panes at `zIndex="-2"`; behind that artwork every one of them was invisible
            // however the script showed it. Those children draw over it in `zIndex` order instead.
            // Three containers in the corpus have this shape (`Navigator`'s and two in `tubeframe`).
            // **A PNG's own alpha is a hole too.** `Age_of_Mythology_MPXP`'s `visMask` states no
            // key: `vis_back.png` carries its lens as transparency, and its `zIndex="-15"`
            // `<EFFECTS>` drew over the headdress and the ring instead of through the lens.
            let artworkHasNoHole = hasBackgroundImage
                && colors(node, names: ["transparencyColor", "clippingColor"]).isEmpty
                && node.statedAttribute(named: "clippingImage") == nil
                && backgroundImage.map { (try? imageStore.carriesOwnTransparency(for: $0.1)) != true } ?? true
            let behindOwnArtwork = artworkHasNoHole ? [] : orderedChildren.prefix { zIndex(of: $0) < 0 }
            // **A plain colour is the ground under every child, however negative its `zIndex`.**
            // Behind-own-artwork is for artwork with a hole in it (`Cerulean`'s `face.bmp`); a
            // `backgroundColor` with no image beside it has no hole, so a child drawn behind it is
            // simply gone. `Melvin`'s belly is `<subview id="look" backgroundColor="white">`
            // holding `<effects zindex="-2">`, and the white slab landed in the overlay above the
            // hosted visualizer: a playing track showed a blank belly and the vis button seemed
            // dead. With an image the order is unchanged — the fill is keyed with that image.
            let groundsNegativeChildren = !behindOwnArtwork.isEmpty && !hasBackgroundImage
            if groundsNegativeChildren, !frame.isEmpty,
               let background = mirroredColor(of: node, names: ["backgroundColor"]) {
                emit(WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID,
                    frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, paint: .fill(background), alpha: alpha))
            }
            // A container already shaping its children by a region has nothing more to say here:
            // `Plus! Hard Boiled`'s white-keyed mask subviews would key white out of every JPEG
            // they hold, at the JPEG's tolerance.
            let ownMatte = ownClipMask == nil ? try matte(node, frame: frame) : nil
            matteStack.append(ownMatte ?? matteStack.last ?? nil)
            if let ownClipMask { clipMaskStack.append(ownClipMask) }
            if let ownGroundShape { groundShapeStack.append(ownGroundShape) }
            behindFilledArtworkStack.append(hasBackgroundImage
                && !colors(node, names: ["transparencyColor"]).isEmpty
                && mirroredColor(of: node, names: ["backgroundColor"]) != nil)
            for child in behindOwnArtwork {
                try walk(child, parentFrame: frame, parentAuthoredSize: ownAuthoredSize,
                         inheritedClip: childClip, parentAlpha: alpha,
                         parentNode: node, parentNodeFrame: frame)
            }
            matteStack.removeLast()
            behindFilledArtworkStack.removeLast()
            if ownClipMask != nil { clipMaskStack.removeLast() }
            if ownGroundShape != nil { groundShapeStack.removeLast() }

            // `clippingImage` shapes an element by a bitmap the way `clippingColor` shapes it by a
            // colour, and the `clippingColor` beside it is what the mask keys out. 169 of the
            // corpus's 172 declarations state one; the three that do not take the mask's own
            // corner instead — see `clippingMaskKeys`.
            // Everything emitted from here to the hit registration below is this node's own
            // artwork, and that span is what `WMPHitCoverage` is built from.
            let ownPaintStart = commands.count
            // **`hueShift` is a script property before it is an authored one (W173).** No corpus
            // node writes it in markup; the one archive that uses it at all assigns it from a
            // handler — `Plus! HueShifter`'s `changeHue()` steps five elements through the
            // spectrum, and `loadPrefs()` restores the saved angle on load. Resolved here, where
            // the overrides are, because `imageCommand` sees only the authored attributes.
            let hueShift: Double = {
                let address = WMPScenePropertyAddress(stableID: node.stableID,
                                                      property: "hueshift")
                if let value = overrides.properties[address]?.number, value.isFinite { return value }
                return literal(node, "hueShift").map(Double.init) ?? 0
            }()
            let clippingPath = try resource(node, names: ["clippingImage"])?.1
            let backgroundPath = try resource(node, names: ["backgroundImage", "background"])?.1
            let childStates = node.kind == .buttonGroup
                ? node.children.map { ($0.stableID, interactionState.visualState(for: $0.stableID)) } : []
            let visualState: WMPVisualInteractionState
            if childStates.contains(where: { $0.1 == .down }) { visualState = .down }
            else if childStates.contains(where: { $0.1 == .hover }) { visualState = .hover }
            else if !childStates.isEmpty && childStates.allSatisfy({ $0.1 == .disabled }) { visualState = .disabled }
            else { visualState = interactionState.visualState(for: node.stableID) }
            let backgroundNames = visualState == .hover && isText(node.kind)
                ? ["hoverBackgroundColor", "backgroundColor"]
                : ["backgroundColor"]
            if !groundsNegativeChildren,
               let background = mirroredColor(of: node, names: backgroundNames), !frame.isEmpty {
                // The fill is under this node's own keyed artwork and is keyed with it — never a
                // bare rectangle filling in the holes that artwork cuts. See `backgroundFillMask`;
                // `Cerulean`'s face used to be a named exemption here and is now one of ten.
                // The root's art is anchored at its own size when the view is not (W164), and the
                // fill is keyed with the art where it is drawn — past it there is no window.
                let fillMask = try backgroundFillMask(node, frame: isRoot ? (rootBackgroundSize.map {
                    WMPRect(x: frame.x, y: frame.y, width: $0.width, height: $0.height)
                } ?? frame) : frame)
                emit(WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID,
                    frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, paint: .fill(background), alpha: alpha,
                    inheritedClipMasks: fillMask.map { [$0] } ?? [],
                    confinedToPaint: node.kind == .video || node.kind == .wmpVideo))
            }
            if let path = backgroundPath, !frame.isEmpty {
                var backgroundFrame = isRoot ? (rootBackgroundSize.map {
                    WMPRect(x: frame.x, y: frame.y, width: $0.width, height: $0.height)
                } ?? frame) : frame
                // **A background bitmap does not stretch onto an axis the skin never asked it to
                // stretch on (W208).** `backgroundImage` fills its frame because a `stretch`-aligned
                // subview grows with a resizable window and its tile is what covers the delta — that
                // is still true and is the whole reason the two `stretch` axes are exempt here, along
                // with `backgroundTiled`, which says the same thing a different way.
                //
                // What is left is a box the skin made *bigger than the art on purpose*, and then the
                // art is art: it draws at its own size in the corner of the box, exactly as a
                // `<BUTTON>`'s `image` and a `CUSTOMSLIDER`'s strip cell already do. `Ice`'s playlist
                // is the case that showed it — reported 2026-09-16 as the right border being drawn
                // *twice*. Its four right-hand pieces are anchored at four different offsets and
                // declared four boxes wider than their bitmaps, so stretched they ended at 487, 468,
                // 468 and 483 and the border came apart into two ragged edges; at their own widths
                // all four end at **468**, which is the single edge the skin drew.
                //
                // Measured over the 185-archive corpus before changing it: of 2,959 non-tiled
                // background paints whose bitmap could be read, **93 across 29 skins** have a box
                // larger than the art on a non-stretch axis, and the other 2,866 are untouched by
                // construction. Every changed view was rendered and compared.
                if !isRoot, let natural = try? imageStore.image(for: path).size {
                    let horizontalAlignment = WMPAxisAlignment(
                        horizontal: literalString(node, "horizontalAlignment"))
                    let verticalAlignment = WMPAxisAlignment(
                        vertical: literalString(node, "verticalAlignment"))
                    let tiled = backgroundTiles(node)
                    // **Its own size, not the smaller of the two.** `min` was the first shape of
                    // this rule and it still squashed the other half of the population: `Ice`'s
                    // `Vid-topleft.bmp` is 43x61 inside a 62x52 box, so `min` drew it 43x52 and the
                    // corner's curve stopped meeting the left tile below it — a step in the border
                    // that reads as a detached side panel, reported the same evening as *"left
                    // window side panel is wrong"*. Art larger than its box overflows and is trimmed
                    // by the clip it already inherits, which is the behaviour the `<BUTTON>` rule
                    // above depends on for the Alienware time readout. **70 of 2,961 paints across
                    // 13 skins** are on this side of it.
                    if !tiled {
                        if horizontalAlignment != .stretch, natural.width > 0 {
                            backgroundFrame.width = natural.width
                        }
                        if verticalAlignment != .stretch, natural.height > 0 {
                            backgroundFrame.height = natural.height
                        }
                    }
                }
                // **Art larger than a subview's box stops at the box.** A subview is a window
                // region and its bitmap is trimmed to it, which is how a skin reveals a drawer by
                // animating `height`: `Asimov_Radio` sizes `splView` to 255 over a 436-tall
                // `vid_screen.bmp` and opens it to 470, so the parent's clip drew the closed
                // drawer as a granite slab behind the whole head. Only where the art overflows —
                // a background that exactly fills a fractional box would gain an antialiased seam.
                let ownClip = node.kind == .subview && !isRoot
                    && (backgroundFrame.width > frame.width + 0.5 || backgroundFrame.height > frame.height + 0.5)
                    ? (inheritedClip.flatMap { frame.intersection($0) } ?? frame) : inheritedClip
                emit(imageCommand(node: node, path: path, frame: backgroundFrame,
                    clip: ownClip, z: z, background: true, alpha: alpha,
                    clippingPath: clippingPath, hueShift: hueShift))
            }
            // **An `<EFFECTS>` rect's own backdrop belongs under the visualizer, not over it.**
            // The split is taken when the node is visited, which is before the two emits above, so
            // a skin that declares `backgroundColor="#000000"` on the rect had that fill hoisted
            // into the overlay and repainted over the hosted surface — a black block where the
            // visualizer was, for the whole of `New Super Mario Bros`, `Gorillaz`, `Primitive`,
            // `Tomb Raider 2`, `MSN` and `robbie`. Behind the surface it still does the job WMP
            // gives it: it is what shows while nothing is playing. Only the node's *background* is
            // moved past; anything the skin paints afterwards — its own foreground, its siblings,
            // its parent's keyed artwork (Cerulean) — stays in the overlay where it was.
            if let effectsWidgetIndex { widgets[effectsWidgetIndex].commandSplitIndex = commands.count }
            let foregroundNames: [String]
            switch visualState {
            case .disabled: foregroundNames = ["disabledImage", "image"]
            case .down:
                // A toggle left on, with the pointer on it (W132) — see `isHoverDown`. Every
                // corpus node authoring `hoverDownImage` also authors `downImage`.
                foregroundNames = node.kind != .buttonGroup && interactionState.isHoverDown(node.stableID)
                    ? ["hoverDownImage", "downImage", "image"] : ["downImage", "image"]
            case .hover: foregroundNames = ["hoverImage", "image"]
            case .normal: foregroundNames = ["image"]
            }
            if !frame.isEmpty, node.kind != .subview && node.kind != .view {
                // **A `BUTTONGROUP`'s state artwork is a sheet the size of the whole group, and it
                // is only ever painted through the group's mapping mask.** `hoverImage` and
                // `downImage` are the *entire* player redrawn with one control lit; the mask is
                // what cuts out the region the pointer is actually over.
                //
                // The normal `image` used to be required for any of that to happen, and a group
                // that authors none — its normal state being the window's own background artwork —
                // fell through to the generic single-image path below and painted the whole sheet
                // over the window. On `Cablemusic` that is a 593x600 bitmap with a dark green
                // surround, so hovering any button in any of its six groups covered the entire
                // player: reported as "when you mouse over the compact button there is a huge
                // overlay". Nothing reached it before W108 gave those groups a frame at all — the
                // second latent trap that row uncovered, after the duplicate `mappingColor`.
                //
                // So the normal artwork is now optional and only the mask is required. With no
                // `image` there is nothing to draw *under* the lit region, which is correct: what
                // is under it is the window, exactly as in the group's normal state.
                //
                // **The normal `image` is the same sheet and takes the same mask (W154).** It was
                // the one state drawn whole, and the dead area a sheet carries around its controls
                // is not keyed by the group's `transparencyColor`: an author names the *map's*
                // dead colour there, because that is the one colour every one of the group's
                // bitmaps shares. `portals/mode1` states it three times over and settles it — its
                // `cbuttons_play` sheet is white around the ovals and its mask is black around
                // them, 24,997 pixels each, and `transparencyColor="#000000"` keys neither, so the
                // transport drew on a white slab at `13,236 280x140`; its `sysbuttons_group` is the
                // same shape in magenta, 829 pixels against 829 black mask pixels, which is the
                // patch the corpus PNG-diff invariant has been carrying; and its
                // `shufrep_buttons` is the control case, 3,723 magenta in the art against 3,723
                // magenta in the *map*, where the one declared key covers both and nothing was ever
                // wrong. One rule explains all three: the mask is what the sheet is painted
                // through, in every state. The normal sheet takes the union of every registered
                // child, a lit sheet takes the children in that state, and a group lit by itself
                // rather than by a child takes the union too.
                //
                // **`showBackground="true"` is the author's exemption, and it is not a guess —
                // the corpus states both polarities.** A group whose `image` is genuinely the
                // window's own artwork rather than a sheet of controls says so: `elvis` wraps its
                // entire 335x396 body in one (`elvis_body.jpg` over `elvis_body_map.gif`), as do
                // `Plus! HueShifter`, `Plus! Plasma Ball`, `Plus! Hard Boiled`, `Plus! SlimLine`
                // and `Asimov_Radio` — **41 declarations across 7 of the 177 measurable archives**,
                // every one of them `true` except `Compact`, which writes `showBackground="false"`
                // twice and is the only skin in the corpus that bothers to state the default.
                // Masking those four Plus!-family bodies to their mapped regions left a hole where
                // the player had been; painting the other 150 skins' sheets whole is the defect
                // this rule closes. Only the *base* sheet is exempted — a lit state is still cut to
                // the control the pointer is on, which is W108 and is what makes `elvis`'s
                // `elvis_body_down.jpg` light one button instead of redrawing the whole body.
                let showsBackground = literalString(node, "showBackground")?
                    .caseInsensitiveCompare("true") == .orderedSame
                if node.kind == .buttonGroup,
                   let (_, mappingPath) = try resource(node, names: ["mappingImage"]),
                   case let colors = mappingColors(of: node), !colors.isEmpty {
                    let mapping = try imageStore.mappingImage(for: mappingPath, nodeByColor: colors)
                    let everyChild = Array(Set(colors.values))
                    let normalPath = try resource(node, names: ["image"])?.1
                    let activeIDs = childStates.filter { $0.1 == visualState }.map(\.0)
                    if let normalPath {
                        // The base sheet keeps the anchoring every other foreground image has —
                        // drawn at its own size, top-left, never stretched to a frame it does not
                        // fill. It reached this branch from the generic path below, where that rule
                        // lives, and `Plus! SlimLine`'s `perfectV_SideBar_normal.jpg` is what
                        // notices: its group is authored 35x243 against shorter artwork, so drawing
                        // it at the frame stretched the whole icon column.
                        let artwork = try imageStore.image(for: normalPath).size
                        emit(imageCommand(node: node, path: normalPath,
                            frame: WMPRect(x: frame.x, y: frame.y,
                                           width: min(frame.width, artwork.width),
                                           height: min(frame.height, artwork.height)),
                            clip: inheritedClip, z: z, background: false, alpha: alpha,
                            mappingMask: showsBackground ? nil
                                : WMPSceneMappingMask(mapping: mapping, nodeIDs: everyChild,
                                                        resourcePath: mappingPath),
                            clippingPath: clippingPath, hueShift: hueShift))
                    }
                    // A group whose own artwork *is* the sheet swaps it wholesale, the way a
                    // `<BUTTON>` does. One with no artwork of its own and nothing lit draws
                    // nothing, which is its normal state.
                    if visualState != .normal,
                       let (_, statePath) = try resource(node, names: foregroundNames) {
                        emit(imageCommand(node: node, path: statePath, frame: frame,
                            clip: inheritedClip, z: z, background: false, alpha: alpha,
                            mappingMask: WMPSceneMappingMask(mapping: mapping,
                                nodeIDs: activeIDs.isEmpty ? everyChild : activeIDs,
                                resourcePath: mappingPath),
                            clippingPath: clippingPath, hueShift: hueShift))
                    }
                    // A latched child the pointer is on takes `hoverDownImage` over the down
                    // sheet, cut to that child alone (W132); the other down children keep it.
                    if visualState == .down, let hovered = interactionState.hoveredNode,
                       activeIDs.contains(hovered), interactionState.isHoverDown(hovered),
                       let (_, hoverDownPath) = try resource(node, names: ["hoverDownImage"]) {
                        emit(imageCommand(node: node, path: hoverDownPath, frame: frame,
                            clip: inheritedClip, z: z, background: false, alpha: alpha,
                            mappingMask: WMPSceneMappingMask(mapping: mapping, nodeIDs: [hovered],
                                                             resourcePath: mappingPath),
                            clippingPath: clippingPath, hueShift: hueShift))
                    }
                } else if let (_, path) = try resource(node, names: foregroundNames) {
                    // A `CUSTOMSLIDER`'s artwork is a strip of every position it can be in, and the
                    // value picks the frame. `frame(for:in:)` returns nil for art that is not a
                    // whole multiple of the map, and then this is an ordinary image again.
                    let artwork = try imageStore.image(for: path).size
                    // **Which end of the strip is the minimum is a property of the art.** The
                    // corpus authors both orders against identical markup — see
                    // `WMPImageStore.filmstripIsDescending`, which measures it and which 13 of the
                    // 342 stripped `CUSTOMSLIDER`s select.
                    let descending = try positionMap?.stripLayout(in: artwork).map { layout in
                        try imageStore.filmstripIsDescending(for: path, frameCount: layout.frames,
                                                             vertical: layout.vertical,
                                                             gradient: positionMap?.gradient(),
                                                             cellLength: positionMap.map {
                                                                 layout.vertical ? $0.height : $0.width
                                                             })
                    } ?? false
                    let strip = slider.flatMap {
                        positionMap?.frame(for: $0.fraction, in: artwork, descending: descending)
                    }
                    // **An element's own artwork is drawn at its own size, anchored top-left, and
                    // the box it does not fill is left to whatever is under it.** WMP never scales
                    // a `<BUTTON>`'s `image` to the authored frame, and a skin that swaps the image
                    // from script is written against exactly that: the Alienware/ALX family's time
                    // readout is four buttons authored the width of a *ten-digit strip*
                    // (`time1.png`, 250x23), each inside a 25 px subview that clips it to the first
                    // cell, and `drawSeekDigits()` then assigns a single 25x23 `time1_<n>.gif` per
                    // tick. Scaling that to the 250 px frame drew one tenth of a digit blown up ten
                    // times — reported as "in all the alien type skins the numeric display is
                    // illegible". The clip is already the parent's, so the smaller artwork lands
                    // exactly where the strip's first cell did.
                    //
                    // Only the *foreground* image takes this. `backgroundImage` still fills its
                    // frame, because a `stretch`-aligned subview grows with a resizable window and
                    // its background tile is what covers the delta.
                    //
                    // **A strip cell is artwork too, and it takes the same rule (W208).** This read
                    // `: frame` — the selected cell stretched to whatever box the node declared —
                    // and a `CUSTOMSLIDER` is exactly where the two differ, because `borderSize`
                    // exists to make the control's box *bigger than its art*: `Ice` authors ten
                    // equaliser bands as `width="20" height="140" borderSize="20"` over a 5x65
                    // `positionImage`, so each 5x65 cell was blown up four times across and twice
                    // down. That is what drew the band grid a second time below the frosted panel
                    // and over the window's bottom frame — reported 2026-09-16 with a screenshot of
                    // Ice's own equaliser. Measured over the 185-archive corpus: **318 `customSlider`
                    // paints across 75 skins, of which 17 across 4 skins were stretched** and the
                    // other 301 already had cell and frame the same size, so this is a no-op for
                    // them by construction.
                    let source = strip.map { WMPSize(width: $0.width, height: $0.height) } ?? artwork
                    let drawn = WMPRect(x: frame.x, y: frame.y,
                                        width: min(frame.width, source.width),
                                        height: min(frame.height, source.height))
                    emit(imageCommand(node: node, path: path, frame: drawn,
                        clip: inheritedClip, z: z, background: false, alpha: alpha,
                        sourceOverride: strip, clippingPath: clippingPath, hueShift: hueShift))
                }
            }

            // **A slider is its track plus a thumb the scene has to place.** 163 of 178 corpus
            // skins author one and 164 give it a `thumbImage`; before this the engine drew the
            // track and nothing else, so every seek bar, volume control and equaliser band in the
            // corpus rendered as an empty groove that could still be dragged invisibly.
            if let slider, !frame.isEmpty, visible != nil {
                // `foregroundImage` is the filled part of the track, revealed up to the value.
                // Cropping the source rather than scaling it keeps the artwork's own pixels: a
                // progress bar squeezed into the filled width reads as a different bitmap.
                if let (_, path) = try resource(node, names: ["foregroundImage"]) {
                    // `useForegroundProgress="true"` (46 skins) says the fill is *not* the value:
                    // it is `foregroundProgress`, which the corpus binds to the network's download
                    // progress. A seek bar authored that way shows how much is buffered behind a
                    // thumb showing where playback is, and the two are different numbers.
                    let filled = progressSource(node, slider).progressRect(in: frame)
                    if !filled.isEmpty {
                        let source = WMPRect(x: filled.x - frame.x, y: filled.y - frame.y,
                                             width: filled.width, height: filled.height)
                        emit(imageCommand(node: node, path: path, frame: filled,
                            clip: inheritedClip, z: z, background: false, alpha: alpha,
                            sourceOverride: source, hueShift: hueShift))
                    }
                }
                let thumbNames: [String]
                switch visualState {
                case .disabled: thumbNames = ["thumbDisabledImage", "thumbImage"]
                case .down: thumbNames = ["thumbDownImage", "thumbImage"]
                case .hover: thumbNames = ["thumbHoverImage", "thumbImage"]
                case .normal: thumbNames = ["thumbImage"]
                }
                if let (_, path) = try resource(node, names: thumbNames) {
                    let size = try imageStore.image(for: path).size
                    let thumb = slider.thumbFrame(in: frame, thumbSize: size)
                    if !thumb.isEmpty {
                        emit(imageCommand(node: node, path: path, frame: thumb,
                            clip: inheritedClip, z: z, background: false, alpha: alpha, hueShift: hueShift))
                    }
                }
            }
            if isText(node.kind), !frame.isEmpty,
               // A skin writes WMP's own resource strings straight into a readout; what the user
               // sees is the string, never the URL. See `WMPResourceStrings` (W189).
               let value = WMPResourceStrings.resolved(literalString(node, "value")) {
                let alignment: WMPTextAlignment
                switch literalString(node, "justification")?.lowercased() {
                case "left": alignment = .left
                case "center": alignment = .center
                case "right": alignment = .right
                // `CURRENTPOSITIONTEXT` reserves the trailing cell of a composite readout.
                // WMP right-aligns that clock by default; treating it as ordinary left-aligned
                // TEXT put `0:08` directly against Cerulean's scrolling metadata. `DURATIONTEXT`
                // is the other half of the same clock and takes the same default — and the corpus
                // says so rather than the SDK: of its two uses, `pharaoh` writes
                // `justification="Left"` explicitly on its `elapsed / total` pair, which is a
                // statement only worth authoring against a right-aligned default.
                default: alignment = node.kind == .currentPositionText
                    || node.kind == .durationText ? .right : .left
                }
                // **`fontFace` is the attribute the corpus authors, not `fontType`**: 110 skins
                // against 21. Reading only `fontType` rendered every one of those in Arial, which
                // is why so many readouts sat in the wrong face at the right size.
                let style = ((visualState == .disabled
                    ? literalString(node, "disabledFontStyle") : nil)
                    ?? literalString(node, "fontStyle") ?? "").lowercased()
                let textColorNames: [String]
                switch visualState {
                case .disabled: textColorNames = ["disabledForegroundColor", "foregroundColor", "color"]
                case .hover: textColorNames = ["hoverForegroundColor", "foregroundColor", "color"]
                case .down, .normal: textColorNames = ["foregroundColor", "color"]
                }
                let text = WMPSceneText(value: value,
                    fontName: WMPTextMetrics.face(literalString(node, "fontFace"),
                                                  literalString(node, "fontType")),
                    fontSize: max(1, literalNumber(node, "fontSize") ?? 12),
                    bold: style.contains("bold"), italic: style.contains("italic"),
                    underline: style.contains("underline"),
                    smoothed: literalString(node, "fontSmoothing")?.caseInsensitiveCompare("false") != .orderedSame,
                    // **An unauthored colour is black.** `Colorchooser` — Microsoft's own SDK
                    // sample — draws its `red`/`green`/`blue` labels and its panel's `x` with no
                    // colour on a white panel, which reads only against a black default.
                    color: mirroredColor(of: node, names: textColorNames)
                        ?? WMPColor(red: 0, green: 0, blue: 0), alignment: alignment,
                    // **A departure from WMP, by request:** WMP clips an overflowing readout unless
                    // `scrolling` is on (`modernblue`'s artist and title, `Science`'s title, which
                    // authors `false`). Here every text may scroll, whatever the skin authors or
                    // scripts; the renderer only runs a marquee when the text overflows its box.
                    scrolling: true,
                    scrollDelayMilliseconds: Double(literalNumber(node, "scrollingDelay") ?? 100),
                    scrollAmount: max(1, literalNumber(node, "scrollingAmount") ?? 1))
                emit(WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID,
                    frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, paint: .text(text), alpha: alpha))
            }
            // `passthrough="true"` is authored by 83 corpus skins, and it means exactly what it
            // says: the element is drawn and the pointer goes through it to whatever is beneath.
            // A decorative overlay registered as a hit target swallows the controls it covers.
            let passthrough = literalString(node, "passthrough")?.caseInsensitiveCompare("true") == .orderedSame
            if isInteractive(node.kind) || authorsInputHandler(node), visible != nil, !passthrough {
                let enabled = literalString(node, "enabled")?.caseInsensitiveCompare("false") != .orderedSame
                    && !interactionState.disabledNodesForScene.contains(node.stableID)
                // A `<MUTEBUTTON>`, `<REPEATBUTTON>` or `<SHUFFLEBUTTON>` is a toggle by being one,
                // and the corpus authors `sticky` on one of their 14 uses (W265).
                let sticky = literalString(node, "sticky").map { $0.caseInsensitiveCompare("true") == .orderedSame }
                    ?? [.muteButton, .repeatButton, .shuffleButton].contains(node.kind)
                var mappingImage: WMPMappingImage?
                var mappingTargets: [WMPHitTarget] = []
                if node.kind == .buttonGroup,
                   let (_, mappingPath) = try resource(node, names: ["mappingImage"]) {
                    // WMP allows both literal BUTTONELEMENT nodes and semantic transport elements
                    // (PLAYELEMENT, NEXTELEMENT, and peers) inside one mapping image.
                    let children = node.children.filter { $0.attribute(named: "mappingColor") != nil }
                    let colors = mappingColors(of: node)
                    if !colors.isEmpty {
                        mappingImage = try imageStore.mappingImage(for: mappingPath, nodeByColor: colors)
                        mappingTargets = children.compactMap { child in
                            guard colors.values.contains(child.stableID) else { return nil }
                            let childEnabled = literalString(child, "enabled")?.caseInsensitiveCompare("false") != .orderedSame
                                && !interactionState.disabledNodesForScene.contains(child.stableID)
                            let childAction = WMPTransportAction.authoredAction(for: child)
                            var target = WMPHitTarget(stableID: child.stableID, nodeID: child.xmlID,
                                kind: child.kind.description, frame: frame,
                                action: childAction,
                                sticky: literalString(child, "sticky")?.caseInsensitiveCompare("true") == .orderedSame,
                                enabled: childEnabled,
                                toolTip: toolTip(child, state: interactionState.visualState(for: child.stableID),
                                                  literal: literalString),
                                handlerOwnsAction: childAction.map {
                                    WMPTransportAction.handlerOwnsAction($0, on: child)
                                } ?? false)
                            target.greyedOut = !childEnabled && !authorsLiteralDisabled(child)
                            return target
                        }
                    }
                }
                // `cursor` is a *named* shape in 2,246 of its 2,319 non-empty corpus uses. The
                // remainder name a `.cur`/`.ani` file, which is a Windows cursor format nothing
                // here decodes; those resolve to no cursor rather than to a missing bitmap, which
                // is also what stops `BITMAPS … missing=hand sizenwse` reporting cursor names as
                // absent artwork.
                let cursor = literalString(node, "cursor").flatMap(WMPCursor.init(authored:))
                // The traversal position, taken where the hit is registered: after this node's own
                // artwork and any negative-`zIndex` children, before the siblings that paint over
                // it. See `WMPHitMetadata.paintOrder`.
                paintSequence += 1
                let ownPaint = commands[ownPaintStart...].filter { $0.stableID == node.stableID }
                // **A mapping image is already the authority on its group's hit region**, per
                // colour and per child, and `WMPHitTester` consults it directly — an unregistered
                // or alpha-zero pixel there falls through exactly as coverage would make it. Asking
                // the group's artwork as well can only contradict the map: a `#FF00FF` mapping
                // colour is a real region, while the same colour in artwork is the implicit
                // transparency key, so the two disagree about the same pixel by construction.
                // **A `CUSTOMSLIDER`'s position map is the authority on its region**, exactly as a
                // mapping image is for a `<BUTTONGROUP>`, and for the same reason: the map says
                // which pixels are the control and the artwork does not. Deriving coverage from the
                // sprite instead cost `Plus! Pulsar` 577 pixels of its seek arc and 551 of its
                // volume arc — the soft edges, which the art keys out and the map claims — while
                // `seek.png` is a 13-frame filmstrip whose opaque area is a property of the *frame*
                // the current value happens to select.
                let coverage: WMPHitCoverage?
                if mappingImage != nil {
                    coverage = nil
                } else if let positionMap {
                    coverage = positionMap.coverage()
                // **A slider's region is the track it authored, not the artwork drawn in it
                // (W256).** Every other control is its artwork, and for a slider that rule reads
                // the *thumb*: `elvis`'s eight bands are `<slider width="10" height="75">` with a
                // `thumbImage` and no track sprite at all, so coverage claimed the 11x12 knob and
                // the other four fifths of each band rejected the pointer — the press fell through
                // to the tray's `<buttonGroup>` behind it and dragged the window instead. WMP
                // moves the thumb to wherever the track is clicked, so the frame is the control:
                // the skin authored a 10x75 box because that is the box it wants pressed. A
                // `CUSTOMSLIDER` is the exception above and keeps its position map, which is a
                // *better* answer than the frame rather than a worse one (W150).
                } else if isSlider(node.kind) {
                    coverage = nil
                } else if node.kind != .buttonGroup, node.kind != .subview, node.kind != .view {
                    // **A button's region is every state sprite it authors, not the one it is
                    // drawing (W306).** The pointer sees the hover sprite, so that is the shape it
                    // aims at: `xsn_sports`' `visDrawerButton` is a 13x7 arrow in `image` and
                    // `downImage` under a 19x13 tab, opaque edge to edge, in `hoverImage` and
                    // `hoverDownImage`, and a press on the tab's margin fell through to nothing.
                    // Each sprite is placed the way the foreground path draws it — natural size,
                    // top-left. Only a node that already has a shape widens: a union can only add
                    // pixels, and a hit catcher (no coverage of its own) keeps its whole rect.
                    let own = Array(ownPaint)
                    var states: [WMPPaintCommand] = []
                    for name in ["image", "downImage", "hoverImage", "hoverDownImage"] {
                        guard let (_, statePath) = try resource(node, names: [name]) else { continue }
                        let command = imageCommand(node: node, path: statePath, frame: frame,
                            clip: inheritedClip, z: z, background: false,
                            clippingPath: clippingPath, hueShift: hueShift)
                        guard case .image(let image) = command.paint, image.sourceRect == nil else {
                            states.append(command)
                            continue
                        }
                        states.append(imageCommand(node: node, path: statePath, frame: frame,
                            clip: inheritedClip, z: z, background: false,
                            sourceOverride: WMPRect(x: 0, y: 0, width: frame.width, height: frame.height),
                            clippingPath: clippingPath, hueShift: hueShift))
                    }
                    // Sampling reads only the paints and the frame's size, so those are the key.
                    let key = "\(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))|"
                        + String(describing: own.map(\.paint)) + "|" + String(describing: states.map(\.paint))
                    coverage = imageStore.stateCoverage(key: key) {
                        guard WMPHitCoverageBuilder.coverage(for: own, frame: frame,
                                                             pixels: alphaPlane) != nil else { return nil }
                        // `nil` here is a union with no hole left in it — the whole rect, as for
                        // any node — never a reason to fall back to the node's own coverage.
                        return WMPHitCoverageBuilder.coverage(for: own + states, frame: frame,
                                                              pixels: alphaPlane)
                    }
                } else {
                    coverage = WMPHitCoverageBuilder.coverage(for: Array(ownPaint), frame: frame,
                                                             pixels: alphaPlane)
                }
                // **A `<BUTTONGROUP>` that resolved no mapping children is artwork, not a control
                // (W149).** It is a hit target by *kind*, so one that names no regions still
                // claimed its whole rectangle and swallowed everything drawn under it.
                //
                // `Plus! SlimLine`'s left drawer is the reported case: its `<BUTTONGROUP>` declares
                // `mappingImage="perfectV_progressbar.jpg"` — the same file as its own `image`,
                // not a map — so it has no regions and no handler, and its 173x32 rect lies across
                // the bottom-left of the vertical body strip, exactly over `btnProgress`. The
                // pointer hit the drawer instead of the arrow that closes it, so with the drawer
                // open the arrow could never be pressed: `WMP_RENDER_OCCLUDED` reports
                // `btnProgress … reached=neither by=[-#120:buttonGroup …]`, and live the click
                // traced to `raw=buttonGroup#120`. Reported 2026-09-22 as *"the left arrow does not
                // work"*.
                //
                // A group that authors its own handler, or carries a transport action, is a control
                // and stays — this only drops the ones with nothing behind them.
                let inertGroup = node.kind == .buttonGroup && mappingImage == nil
                    && mappingTargets.isEmpty && !authorsInputHandler(node)
                    && WMPTransportAction.authoredAction(for: node) == nil
                if !inertGroup {
                var hit = WMPHitMetadata(stableID: node.stableID, nodeID: node.xmlID,
                    kind: node.kind.description, frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, paintOrder: paintSequence,
                    action: WMPTransportAction.authoredAction(for: node),
                    sticky: sticky, enabled: enabled, mappingImage: mappingImage,
                    mappingTargets: mappingTargets, coverage: coverage, cursor: cursor,
                    tabStop: literalString(node, "tabStop")?.caseInsensitiveCompare("false") != .orderedSame,
                    positionMap: positionMap,
                    toolTip: toolTip(node, state: visualState, literal: literalString),
                    handlerOwnsAction: WMPTransportAction.authoredAction(for: node).map {
                        WMPTransportAction.handlerOwnsAction($0, on: node)
                    } ?? false)
                hit.greyedOut = !enabled && !authorsLiteralDisabled(node)
                hits.append(hit)
                }
            }

            matteStack.append(ownMatte ?? matteStack.last ?? nil)
            if let ownClipMask { clipMaskStack.append(ownClipMask) }
            if let ownGroundShape { groundShapeStack.append(ownGroundShape) }
            behindFilledArtworkStack.append(false)
            for child in orderedChildren.dropFirst(behindOwnArtwork.count) {
                try walk(child, parentFrame: frame, parentAuthoredSize: ownAuthoredSize,
                         inheritedClip: childClip, parentAlpha: alpha,
                         parentNode: node, parentNodeFrame: frame)
            }
            matteStack.removeLast()
            behindFilledArtworkStack.removeLast()
            if ownClipMask != nil { clipMaskStack.removeLast() }
            if ownGroundShape != nil { groundShapeStack.removeLast() }
        }

        try walk(view, parentFrame: canvasRect,
                 parentAuthoredSize: WMPSize(width: width, height: height),
                 inheritedClip: canvasRect, parentAlpha: 1, isRoot: true)

        // **A hosted surface is its picture, and its picture ends where the skin paints over it
        // (W213).** The layer above it is already separated out for drawing (`commandSplitIndex`),
        // so the same list answers where a click can still reach the surface. A **windowed** one is
        // excluded: nothing the skin paints is drawn over a real child window, so its rect is live
        // whatever the markup declares after it.
        for index in hits.indices where hits[index].coverage == nil
            && hits[index].kind.caseInsensitiveCompare("effects") == .orderedSame {
            guard let widget = widgets.first(where: { $0.stableID == hits[index].stableID }),
                  !widget.isWindowedEffects, let split = widget.commandSplitIndex,
                  split < commands.count else { continue }
            hits[index].coverage = WMPHitCoverageBuilder.surfaceCoverage(
                frame: hits[index].frame, coveredBy: Array(commands[split...]),
                pixels: alphaPlane, keeps: keepPlane)
        }
        hits.sort { $0.paintOrder < $1.paintOrder }
        let allDirty = commands.compactMap { command in
            command.clipRect.flatMap { command.frame.intersection($0) } ?? command.frame
        }.reduce(nil as WMPRect?) { accumulated, next in
            accumulated.map { $0.union(next) } ?? next
        }
        let dirty = dirtyNodeIDs.map { identifiers in
            hits.filter { identifiers.contains($0.stableID)
                || $0.mappingTargets.contains(where: { identifiers.contains($0.stableID) }) }
                .compactMap { hit in hit.clipRect.flatMap { hit.frame.intersection($0) } ?? hit.frame }
                .reduce(nil as WMPRect?) { accumulated, next in
                    accumulated.map { $0.union(next) } ?? next
                }
        } ?? allDirty
        let metrics = WMPSceneMetrics(resolvedNodeCount: resolvedNodes.count,
            unresolvedNodeCount: unresolvedNodes.count, visibleBounds: allDirty)
        return WMPScene(viewID: registration.id, canvasSize: canvas, resizeLimits: resizeLimits,
            isResizable: resizable,
            commands: commands, hits: hits, widgets: widgets, geometries: geometries, unresolved: unresolved,
            diagnostics: diagnostics, dirtyBounds: dirty, metrics: metrics,
            wasBuiltOnMainThread: Thread.isMainThread)
    }

    private func imageCommand(node: WMPNode, path: String, frame: WMPRect,
                              clip: WMPRect?, z: Int, background: Bool, alpha: CGFloat = 1,
                              mappingMask: WMPSceneMappingMask? = nil,
                              sourceOverride: WMPRect? = nil,
                              clippingPath: String? = nil,
                              hueShift: Double = 0) -> WMPPaintCommand {
        let prefix = background ? "background" : ""
        let sourceX = literal(node, prefix + "CropLeft") ?? literal(node, "cropLeft")
        let sourceY = literal(node, prefix + "CropTop") ?? literal(node, "cropTop")
        let sourceWidth = literal(node, prefix + "CropWidth") ?? literal(node, "cropWidth")
        let sourceHeight = literal(node, prefix + "CropHeight") ?? literal(node, "cropHeight")
        let source = sourceOverride
            ?? (sourceX == nil && sourceY == nil && sourceWidth == nil && sourceHeight == nil ? nil
                : WMPRect(x: sourceX ?? 0, y: sourceY ?? 0,
                          width: sourceWidth ?? frame.width, height: sourceHeight ?? frame.height))
        // **Drawn artwork always keys WMP's implicit magenta (W78), declared key or not.** A node
        // that declares nothing keys magenta alone, including one whose only key is a colour the
        // parser rejected: `Alpine7618_v09` writes `transparencyColor="FF00FF"` with no `#`. A node
        // that declares another colour keys magenta *as well*: `MSN`'s `funb`/`wlb` key `#ff0000`
        // and their `hoverImage`s hold magenta in exactly the pixels the up and down faces hold red
        // (193 and 59), which drew a magenta fringe under the pointer; `Ovoid`'s prev button
        // (`#00FF00`, 332 magenta in hover and down), `QuickSilver`'s pause (`#000000`, a 1,732-px
        // magenta surround) and `Plus! Pulsar`'s shutter (`#ffffff`, 49) are the same authoring.
        // No corpus node declaring a non-magenta key draws magenta it means to show.
        //
        // **And `clippingColor` keys the *clipping image*, not the artwork, whenever the node
        // declares one.** The two attributes were read as one list here, which is harmless while
        // they name the same colour and destructive when they do not: `Plus! Plasma Ball`'s
        // `mainButtons` states `clippingImage="screen_MASK.gif" clippingColor="auto"`, so once
        // `auto` resolved (W167) the mask's white was also keyed out of `screen_normal.jpg` — a
        // JPEG, so with `jpegComponentTolerance` 64 — and every light tone in the player's button
        // plates and glyph highlights went transparent. Reported as *"you made the high res
        // graphics low res"*: the artwork was not resampled worse, it was being eaten.
        let declared = colors(node, names: clippingPath == nil
            ? ["transparencyColor", "clippingColor"] : ["transparencyColor"])
        let image = WMPSceneImage(resourcePath: path, sourceRect: source,
            colorKeys: declared,
            tiled: background ? backgroundTiles(node)
                : literalString(node, "tiled")?.caseInsensitiveCompare("true") == .orderedSame,
            interpolation: .low, mappingMask: mappingMask,
            clippingMaskPath: clippingPath,
            clippingMaskKeys: clippingPath.map { clippingMaskKeys(node, path: $0) } ?? [],
            implicitColorKey: WMPBuiltInImage.named(path) == nil
                ? WMPColorKey.implicitTransparency : nil,
            hueShift: hueShift)
        return WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID, frame: frame,
            clipRect: clip, zIndex: z, documentOrder: node.stableID, paint: .image(image),
            alpha: alpha)
    }

    /// Resolve the first resource attribute among `names` to a path inside the archive.
    /// Shared by the view root, which must resolve its background before any nested helper exists.
    ///
    /// **Artwork is a scripted property like any other.** `mainBack.backgroundImage =
    /// "png24/intro_anim_f568.png"` is how a whole family of skins swaps what a node draws —
    /// `Alienware Invader` hides its entire player behind 568 such writes — so a script override is
    /// consulted before the authored attribute. The string it carries is an authored path and
    /// resolves under the same provider rules as markup; one that resolves to nothing warns and
    /// leaves the authored artwork in place rather than blanking the node.
    private func resolveResource(_ node: WMPNode, names: [String],
                                 overrides: WMPSceneOverrides = .empty,
                                 warn: (WMPDiagnostic) -> Void = { _ in }) throws -> (String, String)? {
        for name in names {
            if let override = overrides.properties[WMPScenePropertyAddress(
                stableID: node.stableID, property: name.lowercased())]?.string {
                let authored = override.trimmingCharacters(in: .whitespacesAndNewlines)
                // `view.backgroundImage = ""` is how every store-thumbnail `previewView` clears its
                // splash bitmap: an empty override is an authored absence, not a missing file.
                if authored.isEmpty { continue }
                if let builtIn = WMPBuiltInImage.named(authored) {
                    return (name, builtIn.rawValue)
                }
                // `try?`, not `try`: an override is a runtime value and `resolve` *throws* for a
                // path outside the provider. A skin that assigns a `res://wmploc/RT_IMAGE/#2024`
                // it read back off its own markup must warn like any other unresolvable path. When
                // the throw escaped it took **five views across three skins** with it — `corona`
                // and `9SeriesDefault` both lost `vPlayer` and `viewTiny` outright — which is a
                // whole player rejected over one attribute.
                if let path = try? loadedSkin.archive.resolve(authored,
                                                              relativeTo: loadedSkin.definitionPath) {
                    return (name, path)
                }
                warn(WMPDiagnostic(.resourceMissing,
                    "Script set \(node.authoredTagName).\(name) to '\(authored)', which the skin does not contain.",
                    severity: .warning, location: node.location))
            }
            guard let attribute = node.attribute(named: name) else { continue }
            guard case let .resource(authored) = attribute.value else { continue }
            if let builtIn = WMPBuiltInImage.named(authored) {
                return (name, builtIn.rawValue)
            }
            if let path = try loadedSkin.archive.resolve(authored, relativeTo: loadedSkin.definitionPath) {
                return (name, path)
            }
        }
        return nil
    }

    private func literal(_ node: WMPNode, _ name: String) -> CGFloat? {
        WMPNumber.literal(node.attribute(named: name))
    }

    /// `enabled="false"` written in the markup, as opposed to a binding that currently answers false.
    private func authorsLiteralDisabled(_ node: WMPNode) -> Bool {
        literalString(node, "enabled")?.caseInsensitiveCompare("false") == .orderedSame
    }

    private func literalString(_ node: WMPNode, _ name: String) -> String? {
        guard let attribute = node.attribute(named: name), case let .literal(value) = attribute.value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every key `names` resolves on this node, in order and deduplicated. `color` stops at the
    /// first hit because it answers "what colour is this"; a keyed image needs all of them.
    private func colors(_ node: WMPNode, names: [String]) -> [WMPColor] {
        var resolved: [WMPColor] = []
        for name in names {
            guard let value = color(node, names: [name]), !resolved.contains(value) else { continue }
            resolved.append(value)
        }
        return resolved
    }

    private func color(_ node: WMPNode, names: [String]) -> WMPColor? {
        for name in names {
            guard let attribute = node.attribute(named: name) else { continue }
            if case let .color(value) = attribute.value { return value }
            if let value = WMPAttributeParser.color(from: attribute.rawValue) { return value }
            if attribute.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("auto") == .orderedSame,
               let derived = autoColorKey(node, attribute: name) { return derived }
        }
        return nil
    }

    /// `auto` on a colour key means "take it from the bitmap", and the bitmap is the one that
    /// attribute governs: `clippingColor` keys the `clippingImage` where a node declares one and
    /// the node's own artwork otherwise, every other key the artwork itself. The corner is where
    /// the value comes from — see `WMPImageStore.cornerColor`, which carries the corpus measurement
    /// and the reason a rejected `auto` is not the same thing as no key at all (W167).
    private func autoColorKey(_ node: WMPNode, attribute name: String) -> WMPColor? {
        let artwork = ["image", "backgroundImage", "background", "normalImage"]
        let names = name.caseInsensitiveCompare("clippingColor") == .orderedSame
            ? ["clippingImage"] + artwork : artwork
        guard let path = (try? resolveResource(node, names: names))?.1 else { return nil }
        return (try? imageStore.cornerColor(for: path)) ?? nil
    }

    /// What a node's `clippingImage` keys out, and where the colour comes from when the node names
    /// none (W171).
    ///
    /// `clippingColor` is the answer wherever it is written, and 169 of the corpus's 172
    /// `clippingImage` declarations write it. The other three name a mask and no key at all —
    /// `Plus! HueShifter`'s `body_lower.jpg` group, `Charlies_Angels_Full_Throttle`'s `visEffects`
    /// and `gnome`'s `myeffects2` — and reading that as "no key" makes the mask a no-op: all three
    /// bitmaps are **fully opaque**, so `clippingMask`'s source-alpha test keeps every pixel and the
    /// node draws its whole rectangle. On HueShifter that is `body_lower.jpg`, a 213x66 lavender
    /// plate carrying two wings, painted as a hard-edged box across the bottom of the player with
    /// the skin's green bottom candy behind it.
    ///
    /// The colour is the mask's own corner, which is the derivation `clippingColor="auto"` already
    /// uses (W167) and is white in all three files — the same `clippingColor="white"` their sibling
    /// layers state by hand. **Only for a mask with no transparency of its own**: one that authored
    /// alpha has said what it cuts, and a corner key would cut it a second time.
    private func clippingMaskKeys(_ node: WMPNode, path: String) -> [WMPColor] {
        let declared = colors(node, names: ["clippingColor", "transparencyColor"])
        guard declared.isEmpty else { return declared }
        guard (try? imageStore.carriesOwnTransparency(for: path)) == false,
              let corner = (try? imageStore.cornerColor(for: path)) ?? nil else { return [] }
        return [corner]
    }

    /// Whether `backgroundImage` repeats across the node's frame rather than drawing once.
    ///
    /// **A slider spells it `tiled`, not `backgroundTiled`** — the SDK's `SLIDER.tiled` is the
    /// background's tiling, and 114 slider backgrounds across 24 corpus skins author it that way.
    /// Reading only `backgroundTiled` sent them through W208's natural-size rule, which drew
    /// `Colorchooser`'s 1x11 `sliderBack.bmp` one pixel wide inside its 40 px slider: three
    /// thumbs over no track, reported 2026-09-26 as *"lost the tracks on the sliders"*.
    private func backgroundTiles(_ node: WMPNode) -> Bool {
        let names = isSlider(node.kind) ? ["tiled", "backgroundTiled"] : ["backgroundTiled"]
        return names.contains { literalString(node, $0)?.caseInsensitiveCompare("true") == .orderedSame }
    }

    private func isSlider(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .slider, .volumeSlider, .seekSlider, .balanceSlider, .customSlider, .progressBar:
            return true
        default: return false
        }
    }

    private func isText(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .text, .statusText, .currentPositionText, .durationText: return true
        default: return false
        }
    }

    /// The `wmpprop:` path a control's `value` is bound to, lower-cased, or nil when the skin
    /// authored a literal or an expression instead.
    private func valueBindingPath(_ node: WMPNode) -> String? {
        guard let attribute = node.attribute(named: "value"),
              case let .binding(kind, path) = attribute.value, kind == .property else { return nil }
        return path.lowercased()
    }

    /// A node the markup gave a mouse handler is a hit target whatever its kind.
    ///
    /// WMP dispatches mouse events to *any* element, and skins rely on it: `Sports` builds its
    /// playlist out of ten `<TEXT>` rows that highlight under the pointer through `hilightMe()`,
    /// and hovering one hit the equaliser slider behind it instead — reported on 2026-09-08 as
    /// "Sports has no hover actions". Measured over the 179-archive corpus, **537 nodes across 143
    /// skins** carry a mouse handler on a kind `isInteractive` does not list: 326 `<TEXT>` across
    /// 69 skins, 90 `<EFFECTS>` across 81, 21 `<VIDEO>` across 21, and a tail of transport spellings
    /// this engine parses as unknown kinds. Reproduce with `python3 scripts/wmp_input_kinds.py`;
    /// see `reference/harness/line-grammar.md` § *Input and tooltips the markup authors*.
    ///
    /// `passthrough="true"` still wins — it is the attribute that says "drawn, not touchable" — so
    /// a decorative overlay does not start swallowing the controls under it.
    private func authorsInputHandler(_ node: WMPNode) -> Bool {
        node.attributes.contains { attribute in
            guard case .handler = attribute.value else { return false }
            let name = attribute.name.lowercased()
            return ["onclick", "onmouseover", "onmouseout", "onmousedown", "onmouseup"].contains(name)
        }
    }

    /// The tip for one control in the state it is currently drawn in.
    ///
    /// WMP swaps the text with the button: `upToolTip` while it is up, `downToolTip` while it is
    /// down, and `toolTip` when the skin authored only one — a mute button reads "Mute" and then
    /// "Sound". The corpus authors 4,789 `upToolTip`, 3,797 `toolTip` and 541 `downToolTip` across
    /// 176, 175 and 105 of the 179 archives; reproduce those with the scan in
    /// `reference/harness/line-grammar.md` § *Input and tooltips the markup authors*.
    ///
    /// `literal` is the caller's resolver rather than this type's, so a script assignment —
    /// `alx_dl.wms` writes `toolTip='Volume'` from its slider's `onMouseUp` — is read through the
    /// scene overrides instead of being shadowed by the authored attribute.
    private func toolTip(_ node: WMPNode, state: WMPVisualInteractionState,
                         literal: (WMPNode, String) -> String?) -> String? {
        let stateTip = state == .down ? literal(node, "downToolTip") : literal(node, "upToolTip")
        // `transport.js` sets the play button's tooltip to `res://wmploc.dll/RT_STRING/#1800` on
        // the same swap that sets its artwork, so a tooltip carries these as often as a readout.
        guard let tip = WMPResourceStrings.resolved(stateTip ?? literal(node, "toolTip")),
              !tip.isEmpty else { return nil }
        return tip
    }

    private func isInteractive(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .button, .buttonGroup, .slider, .volumeSlider, .seekSlider,
             .balanceSlider, .customSlider, .playElement, .pauseElement, .stopElement, .prevElement,
             .nextElement, .rewElement, .ffwdElement,
             .playButton, .pauseButton, .stopButton, .prevButton, .nextButton,
             .rewButton, .ffwdButton, .muteButton, .repeatButton,
             .returnButton, .shuffleButton, .playlist, .dropdownPlaylist, .popup,
             .editBox, .listBox: return true
        default: return false
        }
    }

    /// The extent of the subtree a node can place using authored literals and artwork alone, in
    /// the node's own coordinates. Anything script-driven contributes nothing rather than a guess —
    /// the builder never invents geometry — but a container whose own size is unknown is still
    /// descended into at its known origin, which is how `Darkling`'s unsized `viewWrapper` reports
    /// the walls beneath it.
    private func contentUnionSize(of node: WMPNode, overrides: WMPSceneOverrides,
                                  warn: (WMPDiagnostic) -> Void) throws -> WMPSize {
        var extent = WMPSize(width: 0, height: 0)
        for child in node.children {
            if isNonLayout(child) {
                let nested = try contentUnionSize(of: child, overrides: overrides, warn: warn)
                extent = WMPSize(width: max(extent.width, nested.width),
                                 height: max(extent.height, nested.height))
                continue
            }
            guard let left = child.statedAttribute(named: "left") == nil ? 0 : literal(child, "left"),
                  let top = child.statedAttribute(named: "top") == nil ? 0 : literal(child, "top") else { continue }
            var width = literal(child, "width")
            var height = literal(child, "height")
            if width == nil || height == nil,
               let (_, path) = try resolveResource(child, names: intrinsicSizeResourceNames(for: child.kind),
                                                   overrides: overrides, warn: warn) {
                let intrinsic = try imageStore.image(for: path).size
                if width == nil, intrinsic.width > 0 { width = intrinsic.width }
                if height == nil, intrinsic.height > 0 { height = intrinsic.height }
            }
            if width == nil || height == nil {
                let nested = try contentUnionSize(of: child, overrides: overrides, warn: warn)
                if width == nil, nested.width > 0 { width = nested.width }
                if height == nil, nested.height > 0 { height = nested.height }
            }
            guard let width, let height, width > 0, height > 0 else { continue }
            extent = WMPSize(width: max(extent.width, left + width),
                             height: max(extent.height, top + height))
        }
        return extent
    }

    /// **A `<TEXT>`'s own artwork is its glyphs.** Every other node falls back to the natural size
    /// of its `backgroundImage`; a text has none, and WMP sizes it from the face and the string.
    ///
    /// This is the single largest starvation class in the corpus: **1,441 `<TEXT>` nodes across 127
    /// of the 179 archives** resolve no size in the default state, 1,058 of them missing width
    /// *and* height. `Cablemusic` is the worked case — its script lays out ten readouts with
    /// `txtShow.top/left/width/fontSize` and never a `height`, because in WMP there is nothing to
    /// set — so the whole show/clip/author/copyright/bitrate block, and the seventeen station rows
    /// in each of its two drawers, had no frame and never drew. Reported as "there is no track
    /// display".
    ///
    /// A width measured from the *current* value is WMP's own behaviour: the box grows with the
    /// string. That makes an empty value legitimately zero-wide and therefore still undrawn, which
    /// is correct — there is nothing to draw — and it starts drawing on the transaction that gives
    /// it a value, because a script write to `value` rebuilds the scene. An authored dimension
    /// always wins; this only answers one the skin never stated.
    ///
    /// `literal`/`literalString` are the caller's override-aware resolvers rather than this type's
    /// markup-only ones. That is the whole point here: the string and the face this measures are
    /// what a script just wrote, not what the markup declared, and reading the markup answered nil
    /// for every node whose value only exists at runtime — which is all of them.
    private func intrinsicTextSize(_ node: WMPNode,
                                   literal: (WMPNode, String) -> CGFloat?,
                                   literalString: (WMPNode, String) -> String?) -> WMPSize? {
        guard let value = literalString(node, "value") else { return nil }
        let face = WMPTextMetrics.face(literalString(node, "fontFace"),
                                       literalString(node, "fontType"))
        let size = max(1, literal(node, "fontSize") ?? 12)
        let style = (literalString(node, "fontStyle") ?? "").lowercased()
        let bold = style.contains("bold"), italic = style.contains("italic")
        return WMPSize(
            width: WMPTextMetrics.width(of: value, fontName: face, fontSize: size,
                                        bold: bold, italic: italic).rounded(.up),
            height: WMPTextMetrics.lineHeight(fontName: face, fontSize: size,
                                              bold: bold, italic: italic))
    }

    private func intrinsicSizeResourceNames(for kind: WMPElementKind) -> [String] {
        switch kind {
        case .customSlider:
            // **A `CUSTOMSLIDER` is the size of its `positionImage`, not of its `image`.** The
            // image is a filmstrip of every position the control can be in — `ALXMorph/volume.png`
            // is 2232x38 against a 72x38 map, 31 frames — so sizing from it makes the control
            // thirty times too wide. The map comes first for that reason alone.
            return ["positionImage", "image", "backgroundImage", "background", "foregroundImage"]
        case .slider, .volumeSlider, .seekSlider, .balanceSlider, .progressBar:
            // WMP slider controls conventionally omit width/height and take their track size from
            // foregroundImage. thumbImage is a last-resort size for unusual authored controls.
            return ["image", "backgroundImage", "background", "foregroundImage", "thumbImage"]
        case .buttonGroup:
            // **A `BUTTONGROUP`'s size is its mapping image's size, and often nothing else can say
            // so.** The group's normal state is usually the window's own background artwork, so the
            // skin authors no `image` and no geometry at all: `Cablemusic`'s six groups — its eight
            // presets, stop, close, minimize, next/previous effect, shrink, the bandwidth pair and
            // all three drawer tabs — are `<BUTTONGROUP mappingImage="map.gif" hoverImage="…"
            // downImage="…">` and nothing more. With no size the group resolved no frame, so it
            // registered no hit target and every control in it was dead, while the artwork beneath
            // still drew the buttons: reported as "most buttons don't work". The mapping image is
            // definitionally the group's own pixel grid — every child is a colour region inside
            // it — so it is the right fallback, and the state images are the same bitmap again.
            // 31 groups across 16 of the 179 corpus archives resolve no size today.
            return ["image", "mappingImage", "hoverImage", "downImage",
                    "backgroundImage", "background"]
        default:
            return ["image", "backgroundImage", "background"]
        }
    }

    /// **A `<PLAYLIST playlistItemsVisible="false">` is a dropdown, not a list.** It draws only its
    /// toolbar, so the skin sizes it as one: `Heart_Butterfly` and `Josie_and_the_Pussycats` give
    /// it 22pt, where the list surface drew one clipped row over its own ground.
    private func widgetKind(_ node: WMPNode) -> WMPWidgetKind? {
        if node.kind == .playlist,
           literalString(node, "playlistItemsVisible")?
               .caseInsensitiveCompare("false") == .orderedSame {
            return .dropdownPlaylist
        }
        return widgetKind(node.kind)
    }

    private func widgetKind(_ kind: WMPElementKind) -> WMPWidgetKind? {
        switch kind {
        case .text: return .text
        case .slider, .volumeSlider, .seekSlider, .balanceSlider, .customSlider, .progressBar:
            return .slider
        case .playlist: return .playlist
        case .dropdownPlaylist: return .dropdownPlaylist
        case .popup: return .popup
        case .editBox: return .editBox
        case .listBox: return .listBox
        case .effects: return .effects
        case .video, .wmpVideo: return .video
        default: return nil
        }
    }

    /// The mapping-image colour of each child that declares one, keyed by colour.
    ///
    /// **Two children can declare the same `mappingColor`, and building this with
    /// `uniqueKeysWithValues` traps the process.** `Cablemusic` authors `bnpb6` and `bnpb7` both as
    /// `#00C0FF` — one preset button too many for the eight regions its `map.gif` has — and WMP
    /// draws and hits the first of them rather than refusing the skin. Nothing reached this code
    /// before because that skin's groups resolved no frame at all; sizing them from the mapping
    /// image is what turned a dead control into a crash on load. First in document order wins.
    private func mappingColors(of group: WMPNode) -> [WMPColor: Int] {
        Dictionary(group.children.compactMap { child -> (WMPColor, Int)? in
            guard let value = child.attribute(named: "mappingColor")?.value,
                  case let .color(color) = value else { return nil }
            return (color, child.stableID)
        }, uniquingKeysWith: { first, _ in first })
    }

    /// **A `BUTTONGROUP` child that declares a `mappingColor` is a region of the group's mapping
    /// image, not a box on the canvas.** `<BUTTONELEMENT>` was already exempt from layout; its
    /// semantic siblings — `<PLAYELEMENT>`, `<STOPELEMENT>`, `<NEXTELEMENT>` and peers — were not,
    /// so every one of them was walked as a control, failed to find geometry it never had, and was
    /// recorded `unresolved`. That is **494 of the corpus's 2,380 unresolved nodes across ~90
    /// skins**, and none of it was ever a drawing defect: hit testing already reaches them through
    /// the group's `mappingTargets`. It mattered because `starved.tsv` ranks on that numerator, so
    /// a fifth of the ranking was phantom rows.
    ///
    /// The test is the attribute **under a `BUTTONGROUP`** rather than the kind, because that pair
    /// is exactly what `mappingColors(of:)` builds the group's targets from — and the attribute
    /// alone is not enough. `polygon` authors `<subview id="ToggleButton" left="75" top="27"
    /// width="18" height="18" mappingImage="Toggle_MAP.bmp" mappingColor="#FF0000">`: a mask on the
    /// subview itself, not a group membership. Testing the attribute alone dropped its geometry,
    /// which lost the panel it draws and moved the `returnButton` inside it to the window's corner.
    /// A skin that authors one of the transport tags standalone, with its own artwork and frame,
    /// still lays out for the same reason.
    private func isNonLayout(_ node: WMPNode) -> Bool {
        if node.parent?.kind == .buttonGroup, node.attribute(named: "mappingColor") != nil {
            return true
        }
        return isNonLayout(node.kind)
    }

    /// A `<TEXT>` that states no text and no box: the skin is using it as a **string table**, not
    /// as a control, and it was never going to draw a pixel.
    ///
    /// The Skins Factory house style declares one `<subview id="locSub">` per view holding a
    /// `<text id="locShowPl" toolTip="Show Playlist" />` for every string its script needs, and
    /// reads them back as `locShowPl.toolTip`. Nothing gives such a node a size — there is no
    /// `value` to measure and no artwork to fall back on — so every one of them was recorded
    /// `unresolved`, which is the numerator `starved.tsv` ranks the whole corpus on. That is
    /// **733 of the 1,183 unresolved nodes** in the 184-archive sweep, and it put two skins at the
    /// very top of the ranking that are not starved at all: `Batman Begins/mainView` and
    /// `Alienware Invader/mainView` both score 0.90 and both draw their whole player once their
    /// intro animation has run (`WMP_RENDER_SETTLE=160` for Batman's 154 frames). Ranking a
    /// phantom is the same defect `isNonLayout` was written for; see W111.
    ///
    /// The test is deliberately narrower than "a text node with no size". A node the *script*
    /// fills resolves the moment it is filled, because `literalString` reads the scene overrides
    /// before the markup — so asking for the override too is what keeps this from swallowing one.
    /// A `value` authored as a `wmpprop:`/`jscript:` binding answers nil from `literalString` and
    /// is not literal text, so the raw attribute is tested as well. And only `.text` qualifies:
    /// `<STATUSTEXT>`, `<CURRENTPOSITIONTEXT>` and `<DURATIONTEXT>` take their content from the
    /// player rather than from an attribute, so an unsized one genuinely has nowhere to draw.
    private func isStringTableText(_ node: WMPNode,
                                   _ literalString: (WMPNode, String) -> String?) -> Bool {
        node.kind == .text
            && node.attribute(named: "value") == nil
            && literalString(node, "value") == nil
    }

    /// The other half of the string table: a `<TEXT>` that states a **string** and no geometry
    /// whatsoever. `isStringTableText` answers the tooltip half — `Disney_Mix_Central`'s
    /// `<subview id="locSub">` of `<text id="locShowPl" toolTip="Show Playlist"/>` — which has no
    /// value to measure and so never resolved a size and never drew. The Skins Factory house style
    /// declares a *second* such subview holding the strings its script substitutes into WMP's own
    /// rip-CD readouts, and those carry a literal `value`, so `intrinsicTextSize` measures the
    /// glyphs, the node resolves at its parent's origin and the sentence is painted across the
    /// top-left corner of the player. `Disney_Mix_Central/mainView` draws five of them over the
    /// artwork — "Insert an audio CD and select tracks to rip...", "Media Library" and three more,
    /// stacked on one another at `0,0` — which is what W68 counted as its "five widgets".
    ///
    /// WMP does not draw them, and the reason is the one the unsized `<PLAYLIST>` established: a
    /// node that states no `width`/`height` and carries no image is 0x0 in WMP's own arithmetic.
    /// A string constant is a variable the skin reads back, not a control, and every one of these
    /// subviews is authored with no geometry at any level.
    ///
    /// **The test is "no geometry at all", and the override half of it is load-bearing.**
    /// `Cablemusic` declares its thirty-four station rows as `<TEXT id="pr0" value="">` with no
    /// geometry either, and lays every one of them out from `InitPrograms()` writing
    /// `pr<N>.top`/`.left`/`.width` — so a markup-only reading of this rule would delete both its
    /// drawers. The scene overrides are asked alongside the markup for that reason, and directly
    /// rather than through `parseDimension`, which answers an unstated `left`/`top` with the
    /// resolver's own 0 and so can never say "the skin stated nothing". An authored alignment is
    /// geometry too: `Constantine`'s and `NVIDIA`'s
    /// `<text id="visEffectName" horizontalAlignment="center" value="test"/>` is a readout whose
    /// position is computed from its parent, and 35 skins author exactly one of those.
    ///
    /// **A bound `value` is not a string constant either**, and the residue census is what says so:
    /// the 61 `<TEXT>` nodes `isStringTableText` correctly leaves unresolved are mostly a
    /// `wmpprop:`/`jscript:` `value` on a node that states no box, and they stay reported. Only a
    /// value the markup *states* — or no value at all — reaches this rule.
    ///
    /// Corpus reach over the 185 archives: **246 nodes across 42 archives** stop painting at their
    /// parent's origin; the 35 aligned readouts, the bound readouts and `Cablemusic`'s script-placed
    /// rows are untouched.
    private func isStringConstantText(_ node: WMPNode, _ overrides: WMPSceneOverrides,
                                      _ literalString: (WMPNode, String) -> String?) -> Bool {
        guard node.kind == .text,
              node.attribute(named: "horizontalAlignment") == nil,
              node.attribute(named: "verticalAlignment") == nil,
              node.attribute(named: "value") == nil || literalString(node, "value") != nil
        else { return false }
        for name in ["left", "top", "width", "height"] {
            guard node.attribute(named: name) == nil,
                  overrides.geometry[WMPScenePropertyAddress(stableID: node.stableID,
                                                             property: name)] == nil
            else { return false }
        }
        return true
    }

    private func isNonLayout(_ kind: WMPElementKind) -> Bool {
        switch kind {
        // `<EQUALIZERSETTINGS id="eq" enabled="true"/>` is the object a skin's own equaliser
        // sliders bind to through `wmpprop:eq.gainLevelN`, not a control: 164 of 178 corpus skins
        // author it and not one gives it geometry. Treating it as a widget hung an AppKit panel of
        // NSSliders on it, over the artwork the skin draws its own bands with.
        case .theme, .player, .network, .script, .buttonElement, .equalizerSettings: return true
        default: return false
        }
    }

    /// The range a slider has when the skin states none, which is WMP's answer and not a generic
    /// one: only the semantic tags carry a scale of their own. `<SEEKSLIDER>` keeps 0-100 here and
    /// takes its real top end from the implicit `max` binding on the track's duration.
    private static func defaultRange(for kind: WMPElementKind) -> (minimum: Double, maximum: Double) {
        kind == .balanceSlider ? (-100, 100) : (0, 100)
    }

}

struct WMPScenePropertyAddress: Hashable, Codable, Sendable {
    let stableID: Int
    let property: String
}

struct WMPSceneOverrides: Hashable, Codable, Sendable {
    var geometry: [WMPScenePropertyAddress: CGFloat]
    var properties: [WMPScenePropertyAddress: WMPJSONValue]
    /// The geometry addresses in `geometry` a **script assigned**, each against the view canvas it
    /// was assigned at (W159). An authored `jscript:` expression re-reads `view.width`/`view.height`
    /// and is therefore always expressed at the current size; a script wrote a plain number at
    /// whatever size the view had when the handler ran, so the canvas is what makes it meaningful
    /// later. Alignment is where the difference shows — see `isComputed` and `scriptAnchorDelta`.
    var scriptAssignedGeometry: [WMPScenePropertyAddress: WMPSize] = [:]
    /// **The canvas an alignment was on when a script assigned it.** WMP re-anchors an element the
    /// moment its `horizontalAlignment`/`verticalAlignment` is written: the margins a `stretch`
    /// keeps are the ones it has right then, not the ones its markup was authored with. A skin
    /// grows its own window against exactly that — `Compact`'s drawer handlers pin `playerView` to
    /// `left`/`top`, widen the view by 179, then set it back to `stretch`, so the player body keeps
    /// its 422 and the 179 it did not take is the drawer. Measuring from the authored size instead
    /// stretched the body over the whole new window and the drawer opened *underneath* it —
    /// reported as "the drawers do not slide out, they change the size/shape of the player" (W185).
    /// Only a script-assigned alignment is anchored, and `Compact` is the corpus's only skin that
    /// assigns one (20 writes, 1 of 185 archives), so nothing else in the corpus can move.
    var scriptAssignedAlignment: [WMPScenePropertyAddress: WMPSize] = [:]
    /// **The extent a script-assigned alignment was measured at, kept out of the geometry (W225).**
    /// Assigning an alignment freezes the element at the size it is *drawn*, and the origin half of
    /// that is an ordinary script-assigned coordinate — but the size half cannot be, because
    /// `ownAuthoredSize` reads the geometry overrides and is what every child's own alignment delta
    /// is measured from. Written there, `Compact`'s `SetAlignment(true)` made `playerView`'s
    /// authored 422 read as the 754 it had been dragged to, so its whole chrome — the tiles, the
    /// right-hand corners, the transport strip — saw a zero delta and collapsed back to the
    /// authored arrangement inside a 754-wide frame, with both drawers still correctly out at the
    /// window's edges. Keyed by `width`/`height`; the canvas it is anchored at is the alignment's
    /// own, in `scriptAssignedAlignment`.
    var scriptAlignmentExtent: [WMPScenePropertyAddress: CGFloat] = [:]
    /// **The parent's extent a script-assigned size on a nested node was written against.**
    /// `scriptAssignedGeometry`'s canvas anchors only a child of the view root; below that, the
    /// growth that counts is the *parent's* since the write. `Compact`'s `SizeViz()` sets
    /// `myeffect.height` inside `svVisual`, and with no anchor the visualizer kept that height
    /// through every later window resize while its width stretched. Keyed by `width`/`height`;
    /// absent when the parent had no resolved frame or the view resized earlier in the same
    /// transaction, which leaves the assignment unanchored, as before.
    var scriptAssignedParentExtent: [WMPScenePropertyAddress: CGFloat] = [:]
    /// **The addresses in `properties` a `wmpprop:`/`wmpenabled:` binding last wrote, not a
    /// script (W301).** Both land in `properties`, and on `visible` the difference decides whether a
    /// node escapes a hidden ancestor — only a script's own `visible = true` does (W263).
    /// `Alpine7618_v09` hangs a 362x211 `<EFFECTS visible="wmpenabled:player.controls.stop">` inside `VisPanel`, a
    /// `visible="false"` subview its VIS button shows; read as a script show, the binding put the
    /// visualization over the window's transparent top half the moment playback started, with no
    /// control to take it away.
    var boundProperties: Set<WMPScenePropertyAddress> = []
    /// Every node a script has written `visible = true` to this session, whatever it holds now.
    /// This is what tells a pane the skin opens and closes from one it never opens — see
    /// `closesSubtree` in `WMPSceneBuilder` (W309).
    var scriptShown: Set<Int> = []
    /// When each node's `visible` last changed by script this session, as a position in
    /// `visibleWriteCount` — the order a show and an ancestor's hide happened in, which is what
    /// tells a child shown inside a closed pane from one the pane was closed over (W311).
    var visibleWriteOrder: [Int: Int] = [:]
    var visibleWriteCount = 0

    static let empty = WMPSceneOverrides(geometry: [:], properties: [:])
}
