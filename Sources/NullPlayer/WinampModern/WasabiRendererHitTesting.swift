import AppKit
import CoreGraphics
import Foundation

/// Hit testing and region masks: which object a point lands on, the `move=` policy that
/// decides what a drag grabs, `rectrgn` clipping, and the window shape those regions cut.
/// Split out of `WasabiRenderer.swift`; see
/// `skills/winamp-modern-skin-guide/reference/rendering/hit-testing.md`.
extension WasabiSceneRenderer {
    func object(at point: CGPoint, interactiveOnly: Bool = true, includingGhosts: Bool = false,
                ignoring shouldIgnore: ((WasabiObject) -> Bool)? = nil) -> WasabiObject? {
        // Outside the window's own shape there is nothing to hit: a corner the skin trimmed away is
        // gone for the pointer as well as for the eye (B76).
        guard containsRegionPixel(at: point) else { return nil }
        for node in sceneNodes().reversed() where node.clip.contains(point) && node.frame.contains(point) {
            let object = node.object
            guard isVisible(object), includingGhosts || object.attributes["ghost"] != "1" else { continue }
            if shouldIgnore?(object) == true { continue }
            if interactiveOnly && !isInteractive(object) { continue }
            if !interactiveOnly && !isRenderable(object, bitmapID: node.bitmapID) { continue }
            // `rectrgn="1"` *is* the region — the whole rect, artwork or not — so it also settles the
            // alpha question, and testing the bitmap anyway contradicts the attribute. Defix's four
            // main-window buttons are `rectrgn="1"` icons drawn as outlines with transparent gaps: a
            // click through a gap fell past the button onto the `ButtonBG` panel behind it, so the
            // first and fourth buttons were dead while the second and third (denser artwork under the
            // same point) worked — which reads as "two of my buttons are broken", not as a hit test
            // disagreeing with a declared region.
            if object.attributes["rectrgn"] != "1",
               let bitmap = resources.bitmap(identifier: node.bitmapID),
               !scriptRegionContains(object, frame: node.frame, point: point) {
                // An animated layer's artwork is a *strip*, and mapping the point across the whole
                // sheet would sample whichever frame happened to line up with that row. Its region is
                // the union of its frames instead — a point is clickable if **any** frame paints
                // there. That is both stable (a click does not depend on which frame is showing) and
                // what a fill animation needs: multipass's seek bar is empty ahead of the playhead, so
                // testing the current frame alone would make the whole point of a seek bar — clicking
                // *forward* — unreachable.
                if object.tag.is(.animatedLayer) {
                    guard animationUnionAlpha(bitmap, object: object, node: node, point: point)
                            > Self.regionAlphaFloor
                    else { continue }
                } else {
                    let local = CGPoint(x: (point.x - node.frame.minX) / max(1, node.frame.width) * CGFloat(bitmap.width),
                                        y: (point.y - node.frame.minY) / max(1, node.frame.height) * CGFloat(bitmap.height))
                    guard bitmap.alpha(at: local) > Self.regionAlphaFloor else { continue }
                }
            }
            return object
        }
        return nil
    }

    /// Whether a point is inside the region a script gave this object.
    ///
    /// A script region only ever **adds** to what the artwork already claims. Itemskin's volume
    /// display is a hollow 65x7 outline (`pl.volume`), and `volume2.maki` makes the whole strip
    /// clickable with `region.loadFromBitmap("volumeregion"); vol.setRegion(region)` — a solid
    /// bitmap. Tested against the artwork alone, every click inside the outline fell through to the
    /// window behind it, so the skin's only volume control was dead (B111). It never removes: T800
    /// drags its volume across the whole strip while a threshold region clips most of it away.
    func scriptRegionContains(_ object: WasabiObject, frame: CGRect, point: CGPoint) -> Bool {
        guard let region = WasabiRegionClip(object: object) else { return false }
        return resources.regionContains(region,
                                        x: Int((point.x - frame.minX).rounded(.down)) - region.offsetX,
                                        y: Int((point.y - frame.minY).rounded(.down)) - region.offsetY)
    }

    /// `includingGhosts` counts `ghost="1"` artwork too: it takes no press itself, but the window it
    /// paints still does, and the press goes to the layout (the stock notifier is all ghosts, B183).
    func containsVisiblePixel(at point: CGPoint, includingGhosts: Bool = false) -> Bool {
        object(at: point, interactiveOnly: false, includingGhosts: includingGhosts) != nil
            // The black a `sysregion` box is backed with is the window too (Prakrit's whole body).
            || backedRegionBoxes().contains { $0.contains(point) }
    }

    /// Every draggable `<Wasabi:Frame>` divider in the active scene, with its grab strip in skin
    /// coordinates. Innermost last, so a hit test walking backwards finds the nested splitter first
    /// (cPro-Bento's playlist frame lives inside its main frame).
    func frameDividers() -> [(object: WasabiObject, rect: CGRect, isVertical: Bool)] {
        sceneNodes().compactMap { node in
            guard WasabiFrame.isFrame(node.object.tag), isVisible(node.object),
                  let rect = WasabiFrame.dividerRect(of: node.object, in: node.frame) else { return nil }
            return (node.object, rect, rect.height >= rect.width)
        }
    }

    /// What outranks a splitter on the splitter's own grab strip.
    ///
    /// `object(at:)` answers "is anything interactive here", and for a splitter that question is too
    /// generous. A grab strip spans the full height of its frame, so it crosses whatever the skin has
    /// laid over that column — cPro's tab strip runs straight through the 8px seam, and a control the
    /// user can see must always win. But Big Bento Modern covers **every pixel of its window** with
    /// `<layer id="player.resizer.disable" move="1" alpha="0">`, plus four alpha-0
    /// `player.mainframe.grabber.mousetrap*` layers laid directly on the seam. Against the plain rule
    /// the splitter therefore never claimed a single press: every drag on it moved the window, while
    /// `resetCursorRects` promised a resize cursor over that same pixel (BB21).
    ///
    /// Two things do not outrank a splitter. **An object the user cannot see** (`alpha="0"`) is a
    /// mousetrap, not a control — it exists to catch events the skin routes elsewhere, and it has no
    /// claim on a strip the user is being shown a resize cursor over. **A surface whose only
    /// interactivity is `move="1"`** is window dragging, which is precisely the gesture a splitter
    /// exists to reinterpret over its own 8px strip. Everything else still wins.
    func objectOverridingDivider(at point: CGPoint) -> WasabiObject? {
        object(at: point) { object in
            if (Int(object.attributes["alpha"] ?? "255") ?? 255) <= 0 { return true }
            // `move="1"` alone. An object that also carries an action, or is a button or a slider, is
            // a real control that happens to be draggable, and keeps its claim.
            return object.attributes["move"] == "1" && !Self.hasOwnCommand(object)
        }
    }

    /// Whether an object carries a command of its own, independent of being draggable — the test that
    /// separates a skin's window-drag surface from a control that also moves the window.
    ///
    /// The **bare** kinds only, unlike `isInteractive`: a `Wasabi:Button` with no command of its own
    /// is still a drag surface — Styx's title strip is a `<Wasabi:button move="1">`.
    private static func hasOwnCommand(_ object: WasabiObject) -> Bool {
        if object.tag.is(anyOf: WasabiKind.commands) { return true }
        return object.attributes["action"] != nil
            || object.attributes[WasabiClickGesture.double.actionAttribute] != nil
            || object.attributes[WasabiClickGesture.right.actionAttribute] != nil
    }

    func frameDivider(at point: CGPoint) -> WasabiObject? {
        frameDividers().reversed().first { $0.rect.contains(point) }?.object
    }

    /// Clip one object to the region a script gave it, if any.
    ///
    /// The mask is placed at its own natural size at the object's origin, not stretched to the
    /// object's rect: a region is a set of *map pixels*, and `Region.offset` moves it in those same
    /// units. An unresolvable map leaves the object unclipped — a skin whose map is missing should
    /// look the way it did before regions existed, not lose the control altogether.
    func applyRegionClip(of object: WasabiObject, frame: CGRect, context: WasabiDrawList) {
        guard let region = WasabiRegionClip(object: object),
              let mask = resources.regionMask(region) else { return }
        let rect = CGRect(x: frame.minX + CGFloat(region.offsetX),
                          y: frame.minY + CGFloat(region.offsetY),
                          width: CGFloat(mask.width), height: CGFloat(mask.height))
        let quality = context.interpolationQuality
        context.interpolationQuality = .none
        context.clip(to: rect, mask: mask)
        context.interpolationQuality = quality
    }

    /// A layer that contributes its bitmap to the **window region** and nothing else.
    ///
    /// `sysregion` is a signed combining mode, and a **negative** value means "region only, do not
    /// paint". The bitmap behind such a layer is a silhouette mask, not artwork: Ujola Cat's
    /// `standardframe.xml` — inherited by every `Wasabi:StandardFrame:*`, so by the playlist window
    /// and by the library window the synthesizer builds — carries five of them over
    /// `window-regions.png`, a magenta-and-white mask. Painted as ordinary layers they put a magenta
    /// slab across the full width at the top and white slabs along the bottom, on top of the real
    /// title strips: "layered full backgrounds in different colours" and "multiple top menubars".
    ///
    /// Only the sign of `windowRegionValue` matters. `0`, a positive value (Ujola's own console art is
    /// `sysregion="1"` on real bitmaps) and the non-numeric forms a skin writes (`"AND"`, which Anexa
    /// uses 15 times) all paint exactly as before. `sysregion="-2"` appears in 11 of the 18 installed
    /// skins.
    static func isRegionOnly(_ object: WasabiObject) -> Bool {
        guard object.tag.is(anyOf: [.layer, .animatedLayer]), let value = windowRegionValue(of: object)
        else { return false }
        return value < 0
    }

    /// This object's signed contribution to the **window region**: its `sysregion`, or else a
    /// negative `regionop`. Nil when it declares neither, or a form that is not a number.
    ///
    /// `regionop` combines an object into its *group's* region rather than the window's, but every
    /// negative one in the corpus (37 skins) is the same idiom: four corner silhouettes cut out of a
    /// standard frame whose group is the whole window, so the group's region is the window's.
    /// Alpine9243's `frame-cut.png` is opaque magenta exactly where the corner goes; drawn as a
    /// layer it put a pink triangle in every framed window's corner (#582). A positive `regionop`
    /// adds to a region the rect already covers, so it is left out rather than read as `sysregion`.
    static func windowRegionValue(of object: WasabiObject) -> Int? {
        if let raw = object.attributes["sysregion"] {
            return Int(raw.trimmingCharacters(in: .whitespaces))
        }
        guard let raw = object.attributes["regionop"],
              let value = Int(raw.trimmingCharacters(in: .whitespaces)), value < 0
        else { return nil }
        return value
    }

    /// One region object's contribution to the window shape (`windowRegionValue`), and the key the
    /// cache turns on.
    ///
    /// Rebuilding the shape is a canvas-sized allocation and a pass over every pixel, and the graph's
    /// mutation counter moves for anything a script writes — so keying on that alone would rebuild a
    /// 1526×868 buffer on frames where nothing about the region changed. What the shape actually
    /// depends on is *these* objects, in *this* order, at these boxes, and nothing else.
    struct WasabiRegionCut: Equatable {
        let object: WasabiObject
        let frame: CGRect
        let clip: CGRect
        let bitmapID: String?
        /// A positive value adds this object to the window; a negative one takes it away.
        let additive: Bool
        /// For a positive, artwork-less group whose descendants declare their own region: the boxes
        /// of what it holds — its visible leaves, and any group inside that paints a `background`.
        /// Such a group reaches that far, not as far as its own box. Nil for anything else.
        let contentBoxes: [CGRect]?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.object === rhs.object && lhs.frame == rhs.frame && lhs.clip == rhs.clip
                && lhs.bitmapID == rhs.bitmapID && lhs.additive == rhs.additive
                && lhs.contentBoxes == rhs.contentBoxes
        }
    }

    /// Every object that shapes the window, **in scene order**.
    ///
    /// `sysregion` is a combining mode against the region built so far, so the order is the whole
    /// semantic and a set of "the negative ones" cannot express it. S7Reflex is the case that proves
    /// it: its config drawer, which `main/normal` lays out *behind* the player, carries two
    /// `sysregion="-1"` silhouettes 350 and 251 px wide, and the `player.main` group declared after
    /// them carries `sysregion="1"` — so the player adds back everything the drawer took, and a
    /// model that merely subtracted every negative layer cut away the left third of the window
    /// (measured: 31,289 px, 16.6% of `main/normal`).
    ///
    /// Only the sign of `windowRegionValue` is read: every negative magnitude in the corpus is a
    /// cut-away — `sysregion="-2"` on the corner and edge silhouettes of 28 skins, `-1` on
    /// winampmodern566's and S7Reflex's config drawer, `regionop="-2"` on the frame corners of 37 —
    /// and the non-numeric forms a skin writes (`"AND"`, which Anexa uses 15 times) shape nothing,
    /// as they have never painted. A negative `regionop` is a cut for the same-group rule below too,
    /// so a positive `sysregion` beside one in its group is not restored; no corpus skin has both.
    private func regionCuts() -> [WasabiRegionCut] {
        let nodes = sceneNodes()
        let declared: [(node: WasabiSceneNode, additive: Bool)] = nodes.compactMap { node in
            guard let value = Self.windowRegionValue(of: node.object), value != 0 else { return nil }
            return (node, value > 0)
        }
        // **A group's own cut-out is not undone from inside it.** A restore that crosses groups is a
        // real idiom — S7Reflex's player is laid over the config drawer's silhouettes and puts back
        // what they took, which is why the order above is read at all — but siblings inside one
        // group are describing *one* shape between them, and an author who writes both a cut and a
        // fill there means "this box, less its border, and here is the backing", not "put the border
        // back".
        //
        // Ebonite's standard frame is the measured case. `wasabi.frame.dummy` carries four
        // `sysregion="-2"` strips that cut the client window down to exactly the opening in the
        // frame window the skin opens over it — top 30, left 10, right 17, bottom 30, which is that
        // frame's inner rect to the pixel — and beside them a `sysregion="1"` backdrop layer,
        // `inner`, whose box overhangs that opening by 13px into the title bar and 7px into the
        // bottom bar. Restoring it printed an opaque black bar across the frame's own glossy
        // titlebar, stopping 19px short of the right edge where the backdrop's own box ends.
        let cutParents = Set(declared.lazy.filter { !$0.additive }
            .compactMap { $0.node.object.parent.map(ObjectIdentifier.init) })
        // A layout that cuts nothing keeps its rectangle (see `buildWindowRegion`), and this runs on
        // every frame as the cache key, so the content walk below is only paid for one that cuts.
        let cuts = declared.contains { !$0.additive }
        let contentBoxes = cuts ? wrapperContentBoxes(nodes: nodes, declared: declared) : [:]
        return declared.compactMap { entry in
            let object = entry.node.object
            if entry.additive, let parent = object.parent, cutParents.contains(ObjectIdentifier(parent)) {
                return nil
            }
            return WasabiRegionCut(object: object, frame: entry.node.frame, clip: entry.node.clip,
                                   bitmapID: entry.node.bitmapID, additive: entry.additive,
                                   contentBoxes: contentBoxes[ObjectIdentifier(object)])
        }
    }

    /// `WasabiRegionCut.contentBoxes` for every positive, artwork-less group with a region object
    /// beneath it, keyed by that group.
    private func wrapperContentBoxes(nodes: [WasabiSceneNode],
                                     declared: [(node: WasabiSceneNode, additive: Bool)])
        -> [ObjectIdentifier: [CGRect]] {
        func ancestors(of object: WasabiObject) -> [ObjectIdentifier] {
            var result: [ObjectIdentifier] = []
            var ancestor = object.parent
            while let next = ancestor {
                result.append(ObjectIdentifier(next))
                ancestor = next.parent
            }
            return result
        }
        let regionAncestors = Set(declared.flatMap { ancestors(of: $0.node.object) })
        let wrappers = Set(declared.lazy.filter {
            $0.additive && $0.node.bitmapID == nil && $0.node.object.attributes["background"] == nil
                && regionAncestors.contains(ObjectIdentifier($0.node.object))
        }.map { ObjectIdentifier($0.node.object) })
        guard !wrappers.isEmpty else { return [:] }
        var boxes: [ObjectIdentifier: [CGRect]] = Dictionary(uniqueKeysWithValues: wrappers.map { ($0, []) })
        let parents = Set(nodes.compactMap { $0.object.parent.map(ObjectIdentifier.init) })
        // A group counts when it paints a `background`; otherwise its box is only the room its
        // children are laid out in.
        for node in nodes where !parents.contains(ObjectIdentifier(node.object))
            || node.object.attributes["background"] != nil {
            let box = node.frame.intersection(node.clip)
            guard !box.isNull, !box.isEmpty else { continue }
            for ancestor in ancestors(of: node.object) where wrappers.contains(ancestor) {
                boxes[ancestor]?.append(box)
            }
        }
        return boxes
    }

    /// Whether a `sysregion="1"` box is backed black: every layout that has not opted in to
    /// per-pixel alpha with `desktopalpha="1"` (B151). See `regionBoxes()`.
    private var layoutBacksRegionBoxes: Bool {
        guard let raw = layout.attributes["desktopalpha"] else { return true }
        return Int(raw.trimmingCharacters(in: .whitespaces)) != 1
    }

    /// The `sysregion` boxes this layout paints black — what `drawScene` fills, and so part of the
    /// window for the pointer too.
    func backedRegionBoxes() -> [CGRect] {
        layoutBacksRegionBoxes ? regionBoxes() : []
    }

    /// The boxes a `Wasabi:StandardFrame:*` with `sysregion="1"` and no artwork of its own puts
    /// **inside** the window, in the scene's top-left space and clipped as drawn (B151).
    ///
    /// Such a frame is its box: its groupdef says "all of this is window", pixels the frame leaves
    /// empty included, and Winamp's region draws those black. WMP11-BlueVU's VU Meters are the case —
    /// the frame's client area is 2px wider than the meter face on every side, and with nothing
    /// painted in that ring it drew as a band of desktop between the frame and the face.
    ///
    /// Two bounds, each a measured regression without it. **Standard frames only**: a plain
    /// `sysregion="1"` group is as often a drawer or a silhouette's wrapper, and backing every one
    /// laid black slabs across S7Reflex and Lobe. **Not when the skin cut a real region**: then it
    /// has drawn the window's shape itself — Ebonite cuts its client window down to the opening in a
    /// separate frame window, and a backing grew black strips under that frame's edges.
    ///
    /// A `<rect>` is a box by construction, so one with `sysregion="1"` is backed the same way.
    /// Prakrit's whole player body is `<rect id="bckg" sysregion="1" w="200" h="250"/>`, and
    /// without a backing its panels were desktop.
    func regionBoxes() -> [CGRect] {
        guard windowRegion() == nil else { return [] }
        return regionCuts().compactMap { cut in
            guard cut.additive, cut.bitmapID == nil,
                  cut.object.tag.is(.rect) || (cut.object.tag.namespace == .wasabiStandardFrame
                      && cut.object.attributes["background"].map({ resources.bitmap(identifier: $0) == nil }) ?? true)
            else { return nil }
            let box = cut.frame.intersection(cut.clip)
            return box.isNull || box.isEmpty ? nil : box
        }
    }

    /// Take the window's shape out of the finished scene: the bite the skin's `sysregion` objects take
    /// out of it, an image whose alpha is the *cut* coverage — transparent where the window stays,
    /// opaque where it goes. Nothing at all when the layout cuts nothing, the common case.
    ///
    /// **Why a composite and not a clip.** A `CGContext` clip mask is consulted by *every* drawing
    /// operation, so a fractional mask value is applied once per overlapping draw and accumulates:
    /// two opaque layers through a 50% mask leave 75% alpha with the two colours blended, which
    /// across winampmodern566's stacked player artwork moved 8451 pixels the region never meant to
    /// touch. The cut has to land **once**, on the finished picture, which is what `.destinationOut`
    /// over the completed scene does.
    ///
    /// The image is built through the same y-flip the scene draw uses, so it is composited in the
    /// *unflipped* space `draw` starts and ends in.
    ///
    /// **At a fractional scale the cut reaches half a skin pixel further.** The artwork is smoothed
    /// there (`WasabiBitmapInterpolationPolicy`), so a cut pixel's art bleeds up to half a skin pixel
    /// into its uncut neighbour, and the opaque promotion turns that bleed solid: CopperdeckII at UI
    /// Size 135% on Retina (2.7) kept alpha 63 of `player/back.png`'s cut edge in a column beside it,
    /// a dark line floating outside the rounded corners. Four draws nudged just under half a skin
    /// pixel each way reach every pixel the bleed can, four full-canvas composites per whole frame.
    /// Their own edges fall inside the canvas, so they are drawn aliased: an antialiased edge cuts
    /// its pixels only partly, and the promotion turns them solid again.
    func drawWindowRegionCut(in context: WasabiDrawList) {
        guard let cut = windowRegion()?.cut else { return }
        let canvas = CGRect(origin: .zero, size: canvasSize)
        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.interpolationQuality = .none
        if WasabiBitmapInterpolationPolicy.isInteger(context.deviceScale) {
            context.draw(cut, in: canvas)
        } else {
            context.setShouldAntialias(false)
            for dx: CGFloat in [-0.49, 0.49] {
                for dy: CGFloat in [-0.49, 0.49] {
                    context.draw(cut, in: canvas.offsetBy(dx: dx, dy: dy))
                }
            }
        }
        context.restoreGState()
    }

    private func windowRegion() -> (cut: CGImage, alpha: [UInt8], width: Int, height: Int)? {
        let cuts = regionCuts()
        if let cache = windowRegionCache, cache.canvas == canvasSize, cache.cuts == cuts {
            return cache.region
        }
        let region = buildWindowRegion(cuts: cuts)
        windowRegionCache = (cuts, canvasSize, region)
        return region
    }

    private func buildWindowRegion(cuts: [WasabiRegionCut])
        -> (cut: CGImage, alpha: [UInt8], width: Int, height: Int)? {
        // **A window is never shrunk by additions alone.** 672 of the corpus's 926 `sysregion`
        // declarations are positive, and most are ordinary painted artwork saying "I am part of the
        // window" — Ujola Cat marks fourteen console layers that way. Composing a region purely from
        // those would decide the shape of every skin that uses the attribute at all, on the strength
        // of whichever layers its author happened to mark, and take a window away wherever the union
        // fell short. A layout that cuts nothing keeps the rectangle it has always had.
        guard cuts.contains(where: { !$0.additive }) else { return nil }
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        guard width >= 1, height >= 1 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            guard let target = CGContext(data: bytes.baseAddress, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            // The window starts as its own rect. Winamp builds the region up from nothing instead,
            // but every framed window in the corpus opens that composition with a full-bleed
            // positive anyway (`wasabi.standardframe.*` and `Wasabi:MainFrame:*` all carry
            // `sysregion="1"` on the group that fills the window), so seeding the rect gives the same
            // answer where a skin does say — and leaves the window whole where one does not, rather
            // than erasing it.
            target.setFillColor(gray: 1, alpha: 1)
            target.fill(CGRect(x: 0, y: 0, width: width, height: height))
            target.translateBy(x: 0, y: CGFloat(height))
            target.scaleBy(x: 1, y: -1)
            // Drawn through the scene's own sprite path, which records; replayed straight back.
            let context = WasabiDrawList(ctm: target.ctm,
                                         clip: CGRect(x: 0, y: 0, width: width, height: height),
                                         interpolationQuality: target.interpolationQuality)
            defer { context.replay(into: target) }
            // **Except inside a full-bleed group that only wraps the window's real content.** Such a
            // group reaches as far as what it holds, not as far as its box — and not merely as far
            // as its descendants' region, because a standard frame's client content declares none
            // and is still window. XENERGY's `Wasabi:MainFrame:NoStatus` fills a 601x280 layout
            // whose player and closed config drawer end at y=146 — the rest is room for the drawer
            // to slide into — and a 252x1 `<vis>` at y=215 drew a flickering line across the
            // desktop below. Outside such a box the rect stands, so a window whose positive layers
            // merely decorate it is not trimmed to them.
            for cut in cuts {
                guard let contentBoxes = cut.contentBoxes else { continue }
                context.saveGState()
                context.clip(to: cut.clip)
                context.clear(cut.frame)
                context.fill(contentBoxes)
                context.restoreGState()
            }
            for cut in cuts {
                context.saveGState()
                context.clip(to: cut.clip)
                // Subtract or restore, in scene order. Colours are discarded either way — the buffer
                // is read for its alpha alone — so only the silhouette's coverage matters.
                context.setBlendMode(cut.additive ? .normal : .destinationOut)
                if let bitmapID = cut.bitmapID, let bitmap = resources.bitmap(identifier: bitmapID) {
                    draw(bitmap, object: cut.object, frame: cut.frame, context: context)
                } else if let background = cut.object.attributes["background"],
                          let bitmap = resources.bitmap(identifier: background) {
                    draw(bitmap, object: cut.object, frame: cut.frame, context: context)
                } else if cut.additive {
                    // A group with no artwork of its own is its box — or, wrapping region objects,
                    // what it holds: that is what a `<groupdef … sysregion="1">` wrapping a whole
                    // window contributes. Only additive, because a *negative* object with no bitmap
                    // has no silhouette to cut with, and taking its whole rect would remove
                    // everything it happens to span.
                    context.setFillColor(gray: 1, alpha: 1)
                    context.fill(cut.contentBoxes ?? [cut.frame])
                }
                context.restoreGState()
            }
        }
        // **The cut is binary**, and the buffer is thresholded in place before it becomes an image.
        // A window region is a shape, not a translucency: Win32's own is, and a skin is entitled to
        // hand us a silhouette that is neither fully opaque nor fully clear. Ebonite draws its four
        // frame strips with `wasabi.frame.dummybg`, a crop of the window's *background texture* at
        // alpha 179 — as coverage that leaves the whole border of every framed window at 30%
        // opacity, which reads as a rendering fault rather than as a shape. `alpha` is what the hit
        // test reads, and the two must agree pixel for pixel or a click lands on a corner the eye
        // cannot see.
        var alpha = [UInt8](repeating: 255, count: width * height)
        var cutsAnything = false
        rgba.withUnsafeMutableBufferPointer { buffer in
            for index in 0..<(width * height) {
                // The buffer holds what the window *keeps*; the image it becomes is the complement,
                // because what gets composited is the bite. Premultiplied, so the colour components
                // follow the alpha they were scaled by.
                let cut: UInt8 = buffer[index * 4 + 3] >= Self.regionKeepFloor ? 0 : 255
                for component in 0..<4 { buffer[index * 4 + component] = cut }
                alpha[index] = 255 - cut
                if cut != 0 { cutsAnything = true }
            }
        }
        // Region objects that resolve to nothing overlapping the window leave it rectangular, and an
        // empty cut is a full-window composite per frame for no shape at all.
        guard cutsAnything else { return nil }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cut = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent)
        else { return nil }
        return (cut, alpha, width, height)
    }

    /// Is this skin-space point inside the window's shape?
    ///
    /// True when there is no region at all. A window corner stays opaque to the pointer however
    /// carefully the renderer erased it, so this gates `object(at:)`: a click on a trimmed corner has
    /// to fall through to whatever is behind the window, the way it already does on the hand-drawn
    /// layouts whose artwork has transparent corners of its own.
    func containsRegionPixel(at point: CGPoint) -> Bool {
        guard let region = windowRegion() else { return true }
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < region.width, y < region.height else { return true }
        return region.alpha[y * region.width + x] > 0
    }

    private func isInteractive(_ object: WasabiObject) -> Bool {
        // The button it wraps takes the press, and that button's events reach the wrapper's script.
        if WasabiEmbeddedXUI.wrapsButton(object) { return false }
        // The standard library's `<Wasabi:Button>` and `<Wasabi:ToggleButton>` are buttons too, and
        // Wasabi hit-tests them as such. Left to `isTextButton` or `action=`, a button whose whole
        // behaviour is a script binding was never under the mouse: T800's five `Mem1…Mem5` song
        // slots are `rectrgn="1"` 4x3 boxes driven entirely from `quicksongpick.maki`, and Big
        // Bento's `query.pathurl` `Ok` is artwork-backed with `text=""`. Prakrit's Rep/Shu/Xfd
        // switches are alpha-0 `Wasabi:ToggleButton`s carrying only a `cfgattrib`, so every press
        // fell to the XUI wrapper and toggled nothing.
        if object.tag.isStandard(anyOf: WasabiKind.commands) { return true }
        // A `<Menu>` is a hit region and nothing else — it draws no artwork and carries no `action`,
        // so without naming it here the pointer never reached a single entry of a skin's own menu
        // bar. Its box is explicit (`w="0" relatw="1" h="21"`) and `object(at:)` skips the alpha test
        // for an object with no bitmap, so the whole declared rect is live, which is what a menu
        // entry needs.
        if WasabiMenuBar.isMenu(object) { return true }
        if object.attributes["action"] != nil { return true }
        // A command on the *second* click or the right button is still a command, and it is the only
        // one some objects carry: a `<text>` song title with `dblclickaction="TRACKINFO"` is not one
        // of the types above and has no `action=`, so it was never under the mouse at all. Ghosts are
        // already excluded by `object(at:)`, which is what keeps multipass's `ghost="1"` playlist
        // ticker from swallowing clicks meant for the list behind it.
        if object.attributes[WasabiClickGesture.double.actionAttribute] != nil
            || object.attributes[WasabiClickGesture.right.actionAttribute] != nil { return true }
        // A colour-theme list owns no bitmap and carries no action — Winamp supplies the widget, the
        // skin supplies only the tag — so without naming it here a click could never reach a row.
        if Self.isColorThemeList(object) { return true }
        // Same for a component bucket: the skin ships the box, Winamp ships the icons, and clicking
        // one is how the thinger opens that component (B34).
        if Self.isComponentBucket(object) { return true }
        // `<Wasabi:Button text="…">` with no artwork: the renderer draws the label and its border
        // (see `drawTextButton`), so it has a region and has to be clickable. Every measured instance
        // also carries an `action`, which the line above already accepts; this covers one that does
        // not and is driven from a script instead.
        if Self.isTextButton(object) { return true }
        // A container has **no region of its own** in Wasabi — its children supply one. MMD3 declares
        // `<group id="main.mmd3" move="1">` last in its layout, so it is topmost across the whole
        // window; accepting a bare group for `move="1"` made it swallow every click that was not over
        // one of its own children, which is what killed the drawer tabs and the colour-theme strip
        // declared before it. A group that paints a background does have a region and keeps one.
        // (Window dragging is unaffected: `shouldDragWindow` only ever accepts a `layer`.)
        // A `<CustomObject>` is the same kind of holder: Anunaki's `main.lcd.layouts` says `move="1"`
        // and is sized to its 482x281 group, so it sat over the whole EQ drawer and took every press
        // meant for the EQ sliders, presets and buttons.
        if object.tag.is(anyOf: [.group, .layout, .customObject]) {
            return object.attributes["background"] != nil
        }
        if object.attributes["move"] == "1" { return true }
        // ponytail: asks the runtime's bindings per candidate under the pointer; cache per object if
        // hover profiling shows it.
        if pressBindingProvider?(object) == true { return true }
        // An `animatedlayer` is a layer that moves. MMD3's rotary volume/bass/treble knobs are
        // animated layers with their own `onLeftButtonDown` handlers, and leaving the type out here
        // meant a click never reached them.
        return object.tag.is(anyOf: [.layer, .animatedLayer]) && object.attributes["ghost"] != "1"
    }

    /// The coverage at which a pixel is still part of the window.
    ///
    /// Half: the midpoint of an anti-aliased edge, which puts the boundary of a rounded corner where
    /// the artwork draws it, and it keeps a silhouette a skin drew at partial opacity (Ebonite's 179)
    /// on the cut side, where a Win32 region would also have put it.
    private static let regionKeepFloor: UInt8 = 128
}
