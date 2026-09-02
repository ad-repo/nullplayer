import AppKit
import CoreGraphics
import Foundation

/// Hit testing and region masks: which object a point lands on, the `move=` policy that
/// decides what a drag grabs, `rectrgn` clipping, and the window shape those regions cut.
/// Split out of `WasabiRenderer.swift`; see
/// `skills/winamp-modern-skin-guide/reference/rendering/hit-testing.md`.
extension WasabiSceneRenderer {
    func object(at point: CGPoint, interactiveOnly: Bool = true,
                ignoring shouldIgnore: ((WasabiObject) -> Bool)? = nil) -> WasabiObject? {
        // Outside the window's own shape there is nothing to hit: a corner the skin trimmed away is
        // gone for the pointer as well as for the eye (B76).
        guard containsRegionPixel(at: point) else { return nil }
        for node in sceneNodes().reversed() where node.clip.contains(point) && node.frame.contains(point) {
            let object = node.object
            guard isVisible(object), object.attributes["ghost"] != "1" else { continue }
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
               let bitmap = resources.bitmap(identifier: node.bitmapID) {
                // An animated layer's artwork is a *strip*, and mapping the point across the whole
                // sheet would sample whichever frame happened to line up with that row. Its region is
                // the union of its frames instead — a point is clickable if **any** frame paints
                // there. That is both stable (a click does not depend on which frame is showing) and
                // what a fill animation needs: multipass's seek bar is empty ahead of the playhead, so
                // testing the current frame alone would make the whole point of a seek bar — clicking
                // *forward* — unreachable.
                if object.typeName.caseInsensitiveCompare("animatedlayer") == .orderedSame {
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

    func containsVisiblePixel(at point: CGPoint) -> Bool {
        object(at: point, interactiveOnly: false) != nil
    }

    /// Every draggable `<Wasabi:Frame>` divider in the active scene, with its grab strip in skin
    /// coordinates. Innermost last, so a hit test walking backwards finds the nested splitter first
    /// (cPro-Bento's playlist frame lives inside its main frame).
    func frameDividers() -> [(object: WasabiObject, rect: CGRect, isVertical: Bool)] {
        sceneNodes().compactMap { node in
            guard WasabiFrame.isFrame(node.object), isVisible(node.object),
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
    private static func hasOwnCommand(_ object: WasabiObject) -> Bool {
        let type = object.typeName.lowercased()
        if type == "button" || type == "togglebutton" || type == "nstatesbutton" || type == "slider" {
            return true
        }
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
    func applyRegionClip(of object: WasabiObject, frame: CGRect, context: CGContext) {
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
    /// Only the sign matters. `0`, a positive value (Ujola's own console art is `sysregion="1"` on
    /// real bitmaps) and the non-numeric forms a skin writes (`"AND"`, which Anexa uses 15 times)
    /// all paint exactly as before. `sysregion="-2"` appears in 11 of the 18 installed skins.
    static func isRegionOnly(_ object: WasabiObject, type: String) -> Bool {
        guard type == "layer" || type == "animatedlayer",
              let raw = object.attributes["sysregion"], let value = Int(raw.trimmingCharacters(in: .whitespaces))
        else { return false }
        return value < 0
    }

    /// One `sysregion` object's contribution to the window shape, and the key the cache turns on.
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
        /// A positive `sysregion` adds this object to the window; a negative one takes it away.
        let additive: Bool

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.object === rhs.object && lhs.frame == rhs.frame && lhs.clip == rhs.clip
                && lhs.bitmapID == rhs.bitmapID && lhs.additive == rhs.additive
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
    /// Only the sign is read, as everywhere `sysregion` is consulted: both negative magnitudes in
    /// the corpus are cut-aways — `-2` on the corner and edge silhouettes of 28 skins, `-1` on
    /// winampmodern566's and S7Reflex's config drawer — and the non-numeric forms a skin writes
    /// (`"AND"`, which Anexa uses 15 times) shape nothing, as they have never painted.
    private func regionCuts() -> [WasabiRegionCut] {
        sceneNodes().compactMap { node in
            guard let raw = node.object.attributes["sysregion"],
                  let value = Int(raw.trimmingCharacters(in: .whitespaces)), value != 0
            else { return nil }
            return WasabiRegionCut(object: node.object, frame: node.frame, clip: node.clip,
                                   bitmapID: node.bitmapID, additive: value > 0)
        }
    }

    /// The window's shape, as the bite the skin's `sysregion` objects take out of it: an image whose
    /// alpha is the *cut* coverage — transparent where the window stays, opaque where it goes.
    ///
    /// Nil when the layout cuts nothing, which is the common case and costs nothing.
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
    func windowRegionCutImage() -> CGImage? { windowRegion()?.cut }

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
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
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
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
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
                    // A group with no artwork of its own is its box: that is what a `<groupdef …
                    // sysregion="1">` wrapping a whole window contributes. Only additive, because a
                    // *negative* object with no bitmap has no silhouette to cut with, and taking its
                    // whole rect would remove everything it happens to span.
                    context.setFillColor(gray: 1, alpha: 1)
                    context.fill(cut.frame)
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
        let type = object.typeName.lowercased()
        if type == "button" || type == "togglebutton" || type == "nstatesbutton" || type == "slider" {
            return true
        }
        // `<Wasabi:Button>` is a button — the standard library's, but a button, and Wasabi hit-tests
        // it as one. It reached here only through `isTextButton` (a *label* it has to draw) or an
        // `action=`, so a button whose whole behaviour is a script binding was never under the mouse
        // at all: T800's five `Mem1…Mem5` song slots are `rectrgn="1"` 4x3 boxes driven entirely from
        // `quicksongpick.maki`, and every click fell past them onto the layout. Big Bento's
        // `query.pathurl` dialog has the same shape from the other direction — its `Ok` is
        // artwork-backed with `text=""`, so the label test rejected it too.
        //
        // Contained by what a `<Wasabi:Button>` *is*: all 32 in the corpus are either an explicit
        // click target (`rectrgn="1"`), artwork-backed, or labelled, so none of them becomes an
        // invisible box that swallows a click meant for something behind it.
        if type == "wasabi:button" { return true }
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
        if type == "group" || type == "layout" { return object.attributes["background"] != nil }
        if object.attributes["move"] == "1" { return true }
        // An `animatedlayer` is a layer that moves. MMD3's rotary volume/bass/treble knobs are
        // animated layers with their own `onLeftButtonDown` handlers, and leaving the type out here
        // meant a click never reached them.
        return (type == "layer" || type == "animatedlayer") && object.attributes["ghost"] != "1"
    }

    /// The coverage at which a pixel is still part of the window.
    ///
    /// Half: the midpoint of an anti-aliased edge, which puts the boundary of a rounded corner where
    /// the artwork draws it, and it keeps a silhouette a skin drew at partial opacity (Ebonite's 179)
    /// on the cut side, where a Win32 region would also have put it.
    private static let regionKeepFloor: UInt8 = 128
}
