import AppKit
import CoreGraphics
import Foundation

/// The fits' bookkeeping for one renderer (`WasabiSceneRenderer.autoFit`), in one place so a layout
/// switch and a bounds change reset it as a unit.
struct WasabiLayoutAutoFit {
    /// The content fit's measurements for the active layout: `fitted` from the content and
    /// frame-content fits, `titleWidth` the width its title needs on top of that (never less than
    /// `fitted.width`).
    struct ContentFit {
        let declared: CGSize
        let fitted: CGSize
        let titleWidth: CGFloat
    }

    /// The canvas the renderer last chose *for itself*. While `canvasSize` still equals it the fits
    /// may replace it; the moment anything else sets a size — a drag, a script, restored state — the
    /// two diverge and the fit never touches the canvas again.
    var canvas: CGSize?
    /// The once-only guards of the content and component-room fits. `isFittingContent` also keeps
    /// the content floor from re-entering the measurement it shares with the fit.
    var hasFittedContent = false
    var isFittingContent = false
    var hasFittedComponentRoom = false
    var isFittingComponentRoom = false
    /// `contentFit()`, measured once per layout.
    var contentFit: ContentFit?
    /// `hostedComponentFloorWidth`, per layout id.
    var hostedComponentFloor: [String: CGFloat?] = [:]

    init(canvas: CGSize) { self.canvas = canvas }

    /// A layout switch: the entered layout's own canvas, and a content fit still to run against it.
    /// The component-room fit and the per-layout floors carry over.
    mutating func enterLayout(canvas: CGSize) {
        self.canvas = canvas
        hasFittedContent = false
        contentFit = nil
    }

    /// The layout's bounds were rewritten, so what was measured against them is stale.
    mutating func forgetMeasurements() {
        contentFit = nil
        hostedComponentFloor.removeAll()
    }
}

/// How big a layout opens: its declared size (`defaultSize`), and the fits that replace it where the
/// skin's numbers leave it unsized — the content fit, the component-room fit and the hosted
/// component's floor. Split out of `WasabiRenderer.swift`; see
/// `skills/winamp-modern-skin-guide/reference/rendering.md`.
extension WasabiSceneRenderer {
    static func dimension(_ attributes: [String: String], keys: [String], fallback: CGFloat) -> CGFloat {
        for key in keys {
            // Trimmed, as `WasabiGeometrySpec` trims an object's: wTunes' player is `w=" 300"`.
            if let raw = attributes[key], let value = Double(raw.trimmingCharacters(in: .whitespaces)),
               value > 0 { return CGFloat(value) }
        }
        return fallback
    }

    func defaultSize(for layout: WasabiObject) -> CGSize {
        Self.defaultSize(for: layout, resources: resources)
    }

    /// Size a layout that describes no size of its own to the content it turns out to hold.
    ///
    /// Runs **once**, on the first scene resolved after `runtime.start()`, because that is when the
    /// content exists: a `Wasabi:StandardFrame`'s client group is instantiated by the skin's own
    /// `standardframe.maki`, not by the markup, so a fit measured in `init` reads an empty frame and
    /// settles on the wrong number. (Measured: ClassicPro's Widgets Manager is 19 nodes at `init`
    /// and 30 after — and a first attempt that fitted in `init` left it at 100x400, its whole
    /// defect, while growing four *other* skins that happened to be complete by then.)
    func fitCanvasToContentIfNeeded() {
        guard !autoFit.hasFittedContent, !autoFit.isFittingContent,
              loadedSkin.runtime.hasStartedScripts,
              storedCanvasSize == autoFit.canvas else { return }
        autoFit.isFittingContent = true
        defer { autoFit.isFittingContent = false; autoFit.hasFittedContent = true }
        let fit = contentFit()
        commitAutoFit(componentRoomFittedSize(CGSize(width: fit.titleWidth, height: fit.fitted.height),
                                              for: layout))
    }

    /// Measured once per layout and shared by the auto-fit and the floor. Every step resolves the
    /// scene at hypothetical canvases — the title fit alone up to five times — over the object graph
    /// the scripts own on the main thread, so it cannot move off it; it can only run less.
    /// Callers set `autoFit.isFittingContent` around it, so neither re-enters it.
    func contentFit() -> WasabiLayoutAutoFit.ContentFit {
        if let cached = autoFit.contentFit { return cached }
        let declared = defaultSize(for: layout)
        let fitted = shapeFittedSize(frameContentFittedSize(contentFittedSize(declared, for: layout)))
        let fit = WasabiLayoutAutoFit.ContentFit(declared: declared, fitted: fitted,
                                                 titleWidth: titleFittedSize(fitted).width)
        autoFit.contentFit = fit
        return fit
    }

    /// Grow a layout whose only size is a bare `w`/`h` to where its `sysregion` artwork ends.
    ///
    /// A layout that states nothing but `w`/`h` — no `default_*`, `minimum_*` or `background` of its
    /// own, no container default — and is shaped by `sysregion` layers is a shaped window, and a
    /// shaped window ends where its shape does (the same rule `alphabackground` follows in
    /// `defaultSize`, B254). AR-7 declares `w="320" h="225"` over a body whose artwork runs to 362,
    /// so the ML button and the readout were clipped at the right edge (B395). Measured on the
    /// artwork's own pixels, not its box: that body is a 400x405 sheet whose opaque part ends at 362
    /// by 213. Only ever grows, clamped by `maximum_*`.
    private func shapeFittedSize(_ size: CGSize) -> CGSize {
        let attributes = layout.attributes
        let container = layout.parent?.attributes ?? [:]
        let states = ["default_w", "default_h", "minimum_w", "minimum_h", "background", "alphabackground"]
        guard attributes["w"] != nil || attributes["h"] != nil,
              !states.contains(where: { attributes[$0] != nil }),
              container["default_w"] == nil, container["default_h"] == nil else { return size }
        var reach = size
        for node in sceneNodes(canvas: size) where node.object !== layout {
            guard (Self.windowRegionValue(of: node.object) ?? 0) > 0, node.object.tag.is(.layer),
                  (Int(node.object.attributes["alpha"] ?? "255") ?? 255) > 0,
                  let id = node.bitmapID, let bitmap = resources.bitmap(identifier: id),
                  let opaque = WasabiResourceCache.opaqueBounds(of: bitmap.image) else { continue }
            let scaleX = node.frame.width / CGFloat(bitmap.width), scaleY = node.frame.height / CGFloat(bitmap.height)
            reach.width = max(reach.width, node.frame.minX + opaque.maxX * scaleX)
            reach.height = max(reach.height, node.frame.minY + opaque.maxY * scaleY)
        }
        let maximum = layoutMaximumSize
        return CGSize(width: min(maximum.width, reach.width.rounded(.up)),
                      height: min(maximum.height, reach.height.rounded(.up)))
    }

    /// The size the content fit asks for, as a **floor** as well as a default — `nil` for a layout
    /// the skin sized itself, which is nearly all of them.
    ///
    /// `fitCanvasToContentIfNeeded` only applies while the canvas is still the one this renderer
    /// chose, so it cannot help a window whose size arrives from somewhere else first — restored
    /// state, above all. ClassicPro's Widgets Manager is the case: a frame saved before the fit
    /// existed puts the canvas at its useless 100x400 *before* the scripts run, the fit then declines
    /// to touch a canvas it did not set, and the window comes back the wrong size every launch.
    ///
    /// Making it a minimum settles that without second-guessing the user: below this width the
    /// content is genuinely clipped (a 305px header in a 92px pane), so it is not a size anyone can
    /// have meant, and the existing `contentMinSize` plumbing carries it to the window.
    var contentFittedFloor: CGSize? {
        // Same gate as the fit: before the scripts run, a `Wasabi:StandardFrame`'s content does not
        // exist yet and the measurement would be of an empty frame.
        guard loadedSkin.runtime.hasStartedScripts, !autoFit.isFittingContent else { return nil }
        autoFit.isFittingContent = true
        defer { autoFit.isFittingContent = false }
        let fit = contentFit()
        let content: CGSize? = fit.fitted == fit.declared ? nil : fit.fitted
        // The title floors the width alone: Silverskin_3's playlist states `default_h="154"` over a
        // `minimum_h="116"`, and a floor of the whole fitted size took that minimum to 154.
        guard fit.titleWidth > fit.fitted.width else { return content }
        return CGSize(width: fit.titleWidth, height: content?.height ?? 0)
    }

    /// A component window narrower than this on an axis its skin never sized has no window in it.
    /// The trigger is the *degenerate* case only — see `componentRoomFittedSize`. Two 12px playlist rows:
    /// _Mercury's playlist is a 116px frame around a 31px list, a size its author chose (B325); at the
    /// old 32 the fit grew its canvas to 335 under a 116px window and the user saw half of it.
    private static let degenerateComponentExtent: CGFloat = 24
    /// What such an axis is grown to give the component. Winamp's own stock Modern skin opens the
    /// same visualization window at `354x280`, whose client area under the standard frame is a little
    /// over 250px tall; this reproduces that rather than inventing a number.
    private static let componentRoomExtent: CGFloat = 250

    /// The component-room fit, applied **before the skin's scripts run**.
    ///
    /// `fitCanvasToContentIfNeeded` deliberately waits for `runtime.start()`, because the content it
    /// measures is instantiated by the skin's own MAKI. This one must not wait, and the app is where
    /// that showed: every auxiliary window is placed while the skin is still loading, so the tiler
    /// asked for the visualizer's size before any script had run and got the unfitted box —
    /// `[place/tile] AVS {{0, 0}, {354, 30}}` with `WINAMP_MODERN_PLACE_TRACE=1`, against the
    /// 354x278 the headless dump reports *after* start. The dump reads the size late and the app
    /// reads it early, which is exactly the gap a render dump cannot show.
    ///
    /// Waiting buys nothing here anyway: the `<component>` this measures is plain markup inside the
    /// layout, in the graph from the moment it is built, and its box is relative to the canvas alone.
    func fitCanvasToComponentRoomIfNeeded() {
        guard !autoFit.hasFittedComponentRoom, !autoFit.isFittingComponentRoom,
              storedCanvasSize == autoFit.canvas else { return }
        autoFit.isFittingComponentRoom = true
        defer { autoFit.isFittingComponentRoom = false; autoFit.hasFittedComponentRoom = true }
        commitAutoFit(componentRoomFittedSize(storedCanvasSize, for: layout))
    }

    /// Grow an axis a layout never states when the component it exists to host has no room on it.
    ///
    /// Nullsoft Winamp 2000 SP4's `AVS/normal` states no height at all — only `minimum_h="30"`, a
    /// floor barely taller than the standard frame's own titlebar — so its visualization holder
    /// resolved to **346x2** and the window opened as a black sliver the user had to drag open by
    /// hand (B136). A floor is not a size, but demoting `minimum_*` in `defaultSize` is not the fix:
    /// it would take micro's deliberate 150x110 player to 275x116 as collateral.
    ///
    /// So the rule is as narrow as the measurement that justifies it. Across the whole installed
    /// corpus — 69 skins, 590 rendered layouts — **exactly one** component holder resolves under
    /// `degenerateComponentExtent`, and it is this one. An axis is grown only when the skin states no
    /// size for it *anywhere* (neither on the layout nor on its container) and the holder it feeds is
    /// degenerate; a layout whose author sized it, and one whose component already has room, is
    /// untouched. The corpus sweep is what has to keep proving that.
    private func componentRoomFittedSize(_ declared: CGSize, for layout: WasabiObject) -> CGSize {
        let attributes = layout.attributes
        let container = layout.parent?.attributes ?? [:]
        // Only a window that exists *to* host a component. A player window parks holders it is not
        // showing — Lobe keeps two 25px ones in `main/normal` and `main/switch` — and growing a
        // player around a parked holder is exactly the collateral this rule must not cause.
        guard container["component"] != nil else { return declared }
        let statesWidth = attributes["w"] != nil || attributes["default_w"] != nil
            || container["default_w"] != nil
        let statesHeight = attributes["h"] != nil || attributes["default_h"] != nil
            || container["default_h"] != nil
        guard !statesWidth || !statesHeight, let holder = holderExtent(atCanvas: declared) else {
            return declared
        }
        var size = declared
        if !statesWidth, holder.width < Self.degenerateComponentExtent {
            size.width = min(Self.optionalDimension(attributes["maximum_w"]) ?? .greatestFiniteMagnitude,
                             size.width + Self.componentRoomExtent - holder.width)
        }
        if !statesHeight, holder.height < Self.degenerateComponentExtent {
            size.height = min(Self.optionalDimension(attributes["maximum_h"]) ?? .greatestFiniteMagnitude,
                              size.height + Self.componentRoomExtent - holder.height)
        }
        return size
    }

    /// The widest and the tallest visible component holder the active layout resolves at `canvas`, or
    /// `nil` when it has none — what the component-room fit measures the window's shortfall from.
    /// Visible only: a player parks holders it is not showing.
    private func holderExtent(atCanvas canvas: CGSize) -> CGSize? {
        let holders = sceneNodes(canvas: canvas).filter {
            WinampModernComponentRegistry.isHolderElement($0.object.tag)
        }
        guard !holders.isEmpty else { return nil }
        return holders.reduce(CGSize.zero) {
            CGSize(width: max($0.width, $1.frame.width), height: max($0.height, $1.frame.height))
        }
    }

    /// The window width at which the holder gets the room its component asks for
    /// (`WinampModernComponentRegistry.minimumHolderWidth`) — `nil` for a container that hosts no such
    /// component. Anaheim Player 01 declares its `MLibrary` 260 wide with a 40px frame, so the library
    /// browser opened in a 220px hole; the skin's size is overruled because what fills the hole is
    /// NullPlayer's, not the skin's.
    ///
    /// It is a floor even where the declared size already clears it, because a script or a restored
    /// frame can take the window below its declared size: Itemskin declares its library 660 wide and
    /// its own script shrinks it to the 330 minimum on open.
    ///
    /// Cached only once the scripts have started: a `Wasabi:*Frame`'s client group — where the holder
    /// lives — is instantiated by the skin's MAKI, so an answer taken earlier (the component-room fit
    /// asks before start) reads no holder, and caching it left EMP2's library without its floor.
    var hostedComponentFloorWidth: CGFloat? {
        let key = activeLayoutID
        if let cached = autoFit.hostedComponentFloor[key] { return cached }
        let computed = computeHostedComponentFloorWidth()
        if loadedSkin.runtime.hasStartedScripts { autoFit.hostedComponentFloor[key] = computed }
        return computed
    }

    private func computeHostedComponentFloorWidth() -> CGFloat? {
        guard let kind = WinampModernComponentRegistry.kind(for: container.attributes["component"]),
              let room = WinampModernComponentRegistry.minimumHolderWidth(for: kind) else { return nil }
        let declared = defaultSize(for: layout)
        // Hidden holders count: a holder's visibility is a skin script's moment, not its markup, and
        // the floor must not depend on when it was first asked.
        let holders = canvasProbe(at: declared, grownBy: CGSize(width: room, height: 0), includingHidden: true)
            .filter { WinampModernComponentRegistry.isHolderElement($0.node.object.tag) }
        // The arithmetic below assumes the holder stretches with the canvas (`relatw`). Checked rather
        // than assumed: around a fixed-width holder, widening the window only widens the frame.
        guard let holder = holders.map(\.node.frame.width).max(), let wider = holders.map(\.grown.width).max(),
              wider > holder else { return nil }
        return min(layoutMaximumSize.width, declared.width + room - holder)
    }

    /// How the content fit treats one axis of a layout, decided once by `axisFit(of:)`.
    private enum AxisFit {
        /// The skin sized it — a box, a default, or artwork that ships — and the fit leaves it alone.
        case authored
        /// The layout states nothing for it and names no `background`: the fit grows it from the
        /// declared size (ClassicPro's Widgets Manager, below).
        case growFromDeclared
        /// The layout is sized by a `background` its archive does not ship and states nothing else,
        /// so `defaultSize` left it at the classic 275x116, a number nobody drew. The fit starts it at
        /// the content's own extent and grows from there (B362): Psonidelic's EQ shade opened 275x116
        /// with a 15-row strip at its top and black below.
        case seedFromContent
    }

    /// Each axis's `AxisFit`. Only a missing background seeds from the content: a layout that names
    /// no background at all is often sized by its script at show time (Minus' and MIPOD's notifiers
    /// measured 95x90 at rest and lost their title), so it only ever grows from what it declares.
    private func axisFit(of layout: WasabiObject) -> (width: AxisFit, height: AxisFit) {
        let attributes = layout.attributes, container = layout.parent?.attributes ?? [:]
        let background = attributes["background"]
        let backgroundIsMissing = background != nil && resources.bitmap(identifier: background) == nil
        func fit(_ own: String, _ box: String, _ floor: String) -> AxisFit {
            guard background != nil else {
                return attributes[box] == nil && attributes[own] == nil ? .growFromDeclared : .authored
            }
            let statesNothing = Self.dimension(attributes, keys: [own, box, floor], fallback: 0) == 0
                && Self.dimension(container, keys: [own], fallback: 0) == 0
            return backgroundIsMissing && statesNothing ? .seedFromContent : .authored
        }
        return (fit("default_w", "w", "minimum_w"), fit("default_h", "h", "minimum_h"))
    }

    /// Size a layout to the content it lays out, on each axis its `AxisFit` leaves open.
    ///
    /// The third fallback in the chain `defaultSize` walks. A layout that declares `w`/`default_w`
    /// is sized by its author, and one with a `background` bitmap is sized by that artwork (ZDL's
    /// Reel-To-Reel); a layout with neither used to be sized by its **`minimum_w`** — the floor it
    /// is allowed to shrink to, which is not a size anybody drew. ClassicPro's Widgets Manager is the
    /// measured case: `<layout id="normal" minimum_h="400" minimum_w="100" …>` and nothing else, so
    /// it opened 100x400 — a tall empty sliver — on all five cPro skins, cPro-Bento included. Its
    /// content group's header layer is a 305x57 bitmap, clipped to 92 wide and invisible along with
    /// everything the list draws. A layout whose `background` is missing from its archive is the
    /// other open case (`AxisFit.seedFromContent`), and starts from its content's extent.
    ///
    /// Measured, never inferred: the layout is resolved at the candidate size and any node that
    /// escapes **its own parent's box** is content the canvas is too small to hold, so the canvas
    /// grows by the largest such escape and the layout is resolved again. Relative children track the
    /// canvas and never overflow, so the only thing that moves the number is intrinsic artwork, and
    /// the loop reaches its fixed point in one or two passes. It is bounded to four regardless, and
    /// clamped by any `maximum_w`/`maximum_h` the layout declares.
    ///
    /// The gate is deliberately narrow. A skin that sized its window is left exactly where it was —
    /// which is what the corpus sweep diff has to keep proving, because a slider thumb that overhangs
    /// its track on purpose looks identical to content that does not fit.
    func contentFittedSize(_ declared: CGSize, for layout: WasabiObject) -> CGSize {
        let key = layout.xmlID ?? "-"
        let attributes = layout.attributes
        let fit = axisFit(of: layout)
        var fitsWidth = fit.width != .authored, fitsHeight = fit.height != .authored
        guard fitsWidth || fitsHeight else { return declared }
        let ceiling = CGSize(
            width: Self.optionalDimension(attributes["maximum_w"]) ?? 16384,
            height: Self.optionalDimension(attributes["maximum_h"]) ?? 16384)
        let trace = Self.tracesContentFit
        var size = declared
        if fit.width == .seedFromContent || fit.height == .seedFromContent {
            let content = intrinsicContentExtent(at: declared)
            if fit.width == .seedFromContent, content.width > 0 { size.width = min(ceiling.width, content.width) }
            if fit.height == .seedFromContent, content.height > 0 { size.height = min(ceiling.height, content.height) }
            if trace { print("FIT \(key) axes \(fit) -> content \(content)") }
        }
        var previousSize = size
        var previous: CGSize?
        for _ in 0..<4 {
            var growth = CGSize.zero
            let nodes = sceneNodes(canvas: size)
            // An axis the object sized with an absolute number is its author's box, and one that
            // overhangs its parent does so on purpose: CopperdeckII's frames run a `w="2136"` bottom
            // strip under every window and let the window clip it, and fitting to it opened the
            // video window 2147 wide. What the fit is for is artwork with no box of its own.
            func authored(_ object: WasabiObject, _ axis: String, _ relative: String) -> Bool {
                object.attributes[axis] != nil && object.attributes[relative] != "1"
            }
            for node in nodes where node.object !== layout {
                if !authored(node.object, "w", "relatw") {
                    growth.width = max(growth.width, node.frame.maxX - node.parentFrame.maxX)
                }
                if !authored(node.object, "h", "relath") {
                    growth.height = max(growth.height, node.frame.maxY - node.parentFrame.maxY)
                }
            }
            if trace { print("FIT \(key) at \(size) growth=\(growth) nodes=\(nodes.count)") }
            // Overflow that does not shrink when the canvas grows is not content the window is too
            // small for — it is artwork drawn deliberately past its box, and no size will ever
            // satisfy it. Stop and **step back one**, to the last size that was not chosen to chase
            // this residual. Two measured cases, and the step-back is what serves both:
            //
            // * BLAKK's video window stretches `component.bottom.middle-video`, a 407px sheet,
            //   across a 204px frame and reports the same 51px overhang at *every* canvas. It stalls
            //   on the first comparison, so the step back is to its declared 204 — which is right,
            //   its `minimum_w="204"` is the window its author drew.
            // * ClassicPro's Widgets Manager overflows by 213 (the header), then by a standing 3
            //   from a list item's artwork. It stalls on the second comparison, so the step back is
            //   to the 313 the header asked for rather than all the way to the useless 100.
            if let previous {
                if growth.width > 0, growth.width >= previous.width {
                    if trace { print("FIT \(key) width stalled at \(growth.width) — stepping back to \(previousSize.width)") }
                    size.width = previousSize.width
                    fitsWidth = false
                }
                if growth.height > 0, growth.height >= previous.height {
                    if trace { print("FIT \(key) height stalled at \(growth.height) — stepping back to \(previousSize.height)") }
                    size.height = previousSize.height
                    fitsHeight = false
                }
                if !fitsWidth && !fitsHeight { return size }
            }
            previous = growth
            previousSize = size
            let next = CGSize(
                width: fitsWidth ? min(ceiling.width, size.width + max(0, growth.width)) : size.width,
                height: fitsHeight ? min(ceiling.height, size.height + max(0, growth.height)) : size.height)
            if next == size { break }
            size = next
        }
        return size
    }

    /// How far the probes below grow the canvas. Any growth separates the two kinds of node: one that
    /// stretches or anchors to the canvas moves its far edge by its share of the growth, and one sized
    /// by its own artwork or box moves it by none. 64 is only "big enough to see": a percentage-placed
    /// edge's share of it clears `canvasProbeTolerance` down to a 1% share.
    private static let canvasProbeGrowth: CGFloat = 64
    /// Under this, an edge did not move with the canvas; resolved frames are fractional.
    private static let canvasProbeTolerance: CGFloat = 0.5

    /// Every node of the active layout at `canvas`, paired with its frame at `canvas` grown by
    /// `growth`: how a fit tells geometry that tracks the canvas from geometry that does not. A node
    /// the grown scene lacks is left out.
    private func canvasProbe(at canvas: CGSize, grownBy growth: CGSize,
                             includingHidden: Bool = false) -> [(node: WasabiSceneNode, grown: CGRect)] {
        let grownCanvas = CGSize(width: canvas.width + growth.width, height: canvas.height + growth.height)
        let grownFrames = Dictionary(sceneNodes(canvas: grownCanvas, includingHidden: includingHidden)
                                        .map { (ObjectIdentifier($0.object), $0.frame) },
                                     uniquingKeysWith: { first, _ in first })
        return sceneNodes(canvas: canvas, includingHidden: includingHidden).compactMap { node in
            grownFrames[ObjectIdentifier(node.object)].map { (node, $0) }
        }
    }

    /// How far the layout's content reaches on each axis when that reach does not depend on the
    /// canvas: artwork and absolute boxes count, and children that stretch or anchor to the canvas
    /// (they end wherever it does) do not. Read off the resolved geometry by `canvasProbe`, rather
    /// than from a second model of `relat*`.
    private func intrinsicContentExtent(at canvas: CGSize) -> CGSize {
        let growth = CGSize(width: Self.canvasProbeGrowth, height: Self.canvasProbeGrowth)
        var extent = CGSize.zero
        for (node, grown) in canvasProbe(at: canvas, grownBy: growth) where node.object !== layout {
            if abs(grown.maxX - node.frame.maxX) < Self.canvasProbeTolerance {
                extent.width = max(extent.width, node.frame.maxX)
            }
            if abs(grown.maxY - node.frame.maxY) < Self.canvasProbeTolerance {
                extent.height = max(extent.height, node.frame.maxY)
            }
        }
        return extent
    }

    /// A layout's canvas size.
    ///
    /// `w`/`h` are **optional** on a layout: Wasabi sizes one that declares none to its `background`
    /// bitmap, exactly as it sizes every other object with artwork and no box. ZDL's Reel-To-Reel
    /// declares every one of its layouts that way, so falling straight through to the 275×116 classic
    /// default gave its 275×348 player a canvas a third of its height — everything below the reels
    /// landed outside the canvas, where `append` drops it, and what was left stacked on top of the
    /// reels. The declared box still wins where a skin gives one.
    /// The size a layout opens at: its own `default_w`/`default_h`, **never below the minimum it
    /// declares for itself**.
    ///
    /// Four layouts in the 31-skin corpus declare a default smaller than their own minimum, and two
    /// of them are the visualization windows this was found on: Anaheim_Player_01's `avs_window` is
    /// `default_w="120"` against `minimum_w="180"`, and Styx's `AVS` is 300×300 against 400×230. The
    /// window opened at the default, so the standard frame's corner and edge art was laid out for a
    /// window 60pt wider than the one drawing it and the chrome came out cut off down the right-hand
    /// side — reported as "a misformed rectangle box". Winamp cannot show a window below its declared
    /// minimum either; this is the same clamp `resize(to:)` already applies to every later size.
    ///
    /// Only the **declared** minimum clamps here, not `layoutMinimumSize` — that one folds in the
    /// computed protective minimum, which is a defence against a *shrunk* window and has no business
    /// enlarging one the skin's author sized deliberately.
    ///
    /// **`default_w`/`default_h` are container attributes too** (B136). `default_x`/`default_y` were
    /// already read off the container (`WinampModernContainerTopology.defaultOrigin`) and the size
    /// pair was not, so a skin that sizes its windows there — 29 declarations across the installed
    /// corpus — got nothing, and every one of those windows opened at its own `minimum_*` floor
    /// instead. Nullsoft Winamp 2000 SP4 sizes *every* auxiliary window that way: measured on that
    /// skin, its playlist opened 276×242 against the author's `PLEdit default_w="550"`, its library
    /// 275×484 against `550×484`, and its visualizer 96×30 against `AVS default_w="354"`. A layout's
    /// own box still wins; the container only answers for an axis the layout never states.
    static func defaultSize(for layout: WasabiObject, resources: WasabiResourceCache) -> CGSize {
        let attributes = layout.attributes
        let minimum = CGSize(width: dimension(attributes, keys: ["minimum_w"], fallback: 1),
                             height: dimension(attributes, keys: ["minimum_h"], fallback: 1))
        let background = resources.bitmap(identifier: attributes["background"])
        /// A layout shaped by its `alphabackground` ends where that artwork does, so the container's
        /// default cannot resize it (B254: Ganbare's 408-wide player under `default_w="816"`, M3's
        /// 222-tall one cut off by `default_h="164"`).
        let container = attributes["alphabackground"] != nil && background != nil
            ? [:] : layout.parent?.attributes ?? [:]
        /// The layout's own box, then the container's default, then the floor, then the artwork.
        func extent(_ own: String, _ box: String, _ floor: String, artwork: CGFloat?,
                    classic: CGFloat) -> CGFloat {
            dimension(attributes, keys: [own, box],
                      fallback: dimension(container, keys: [own],
                                          fallback: dimension(attributes, keys: [floor],
                                                              fallback: artwork ?? classic)))
        }
        let size = CGSize(
            width: extent("default_w", "w", "minimum_w",
                          artwork: background.map { CGFloat($0.width) }, classic: 275),
            height: extent("default_h", "h", "minimum_h",
                           artwork: background.map { CGFloat($0.height) }, classic: 116))
        return CGSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
    }

    static func optionalDimension(_ raw: String?) -> CGFloat? {
        guard let raw, let value = Double(raw), value > 0 else { return nil }
        return CGFloat(value)
    }
}
