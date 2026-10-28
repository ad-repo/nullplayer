import CoreGraphics
import Foundation

/// An alpha mask placed in scene coordinates. A point is tested against the mask itself, so a hit
/// lands exactly where the draw clips to.
struct WasabiMaskClip {
    let mask: CGImage
    let rect: CGRect

    func contains(_ point: CGPoint) -> Bool {
        guard rect.contains(point) else { return false }
        let x = (point.x - rect.minX) / max(1, rect.width) * CGFloat(mask.width)
        let y = (point.y - rect.minY) / max(1, rect.height) * CGFloat(mask.height)
        return WasabiResourceCache.maskContains(mask, x: Int(x.rounded(.down)), y: Int(y.rounded(.down)))
    }
}

/// What a scene node draws and is hit inside (B249): its ancestors' clip rect, intersected down the
/// tree, and the alpha masks of the region groups above it, outermost first. One value, so drawing
/// and `object(at:)` cannot disagree — while the masks were a second field only the draw read, a
/// control in a masked-off part of a region group stayed clickable where nothing was drawn.
struct WasabiClip {
    var rect: CGRect
    var masks: [WasabiMaskClip] = []

    func intersected(with box: CGRect) -> WasabiClip {
        let cut = rect.intersection(box)
        return WasabiClip(rect: cut.isNull ? CGRect(origin: box.origin, size: .zero) : cut, masks: masks)
    }

    func contains(_ point: CGPoint) -> Bool {
        rect.contains(point) && masks.allSatisfy { $0.contains(point) }
    }

    /// The masks are placed at `.none`, as a script region is (`applyRegionClip`): a mask is
    /// coverage, and smoothing it would feather the edge it draws.
    func apply(to context: WasabiDrawList) {
        context.clip(to: rect)
        guard !masks.isEmpty else { return }
        let quality = context.interpolationQuality
        context.interpolationQuality = .none
        for mask in masks { context.clip(to: mask.rect, mask: mask.mask) }
        context.interpolationQuality = quality
    }
}

/// What a group clips its children to beyond its declared box — the alpha of a background it does
/// not paint, and the aperture a target animation slides a child within — the region a script gives
/// one object, and the backing an object paints.
extension WasabiSceneRenderer {
    static let cullsBeforeGroupOrigin =
        ProcessInfo.processInfo.environment["WINAMP_MODERN_GROUP_NO_ORIGIN_CULL"] != "1"

    /// Whether a group's descendant lies wholly left of or above the group's origin, on an axis the
    /// group does not clip (`clipAxes`). A group is a window, so such a node shows whatever size the
    /// group has: it is dropped, as a drawer parked off its group is closed (B297). iCandy-2's remote
    /// parks its closed LCD at `x="-233"` in the sizeless `remote.lcd`, and drawn, a strip of it
    /// showed left of the remote body and round its curves.
    ///
    /// Only wholly: cutting a node that straddles the origin also trims slider thumbs that overhang a
    /// sizeless group's top (hm_Touch_m_1's shade seeker lost its top 2 px, not its bottom 2) and
    /// full-window overlays a group offsets back to the window origin (Official_Zwan_Skin's
    /// thin shade). `WINAMP_MODERN_GROUP_NO_ORIGIN_CULL=1` is the A/B switch.
    func liesBeforeOrigin(of group: WasabiObject, frame: CGRect, child: CGRect) -> Bool {
        guard Self.cullsBeforeGroupOrigin, group.tag.is(.group), !child.isEmpty else { return false }
        let clipped = clipAxes(of: group)
        return (!clipped.contains(.x) && child.maxX <= frame.minX)
            || (!clipped.contains(.y) && child.maxY <= frame.minY)
    }

    /// The box a group that declares none clips to while a target animation has moved one of its
    /// children: the children's union at their **declared** places (`xmlParam`, which `gotoTarget`
    /// leaves alone). A slide is a move within a box. MIDISUI's vis drawer is a 121×124 `Drawer`
    /// layer in a `DrawerGroup` with no `w`/`h`; `drawer.maki` opens it with `setTargetX(-118)`, and
    /// unclipped the cover slid out over the COMPONENT column and the playlist, burying the
    /// playlist / vis studio / video buttons, instead of disappearing into its own frame.
    ///
    /// Only while something has moved: at rest the union is the children themselves, and a group
    /// with no declared box otherwise keeps the inherited clip (`clipAxes`).
    func targetAperture(of group: WasabiObject,
                                children: ArraySlice<WasabiSceneNode>) -> CGRect? {
        guard group.tag.is(.group), clipAxes(of: group).isEmpty else {
            return nil
        }
        var union = CGRect.null
        var moved = false
        for node in children where node.object.parent === group {
            let child = node.object
            func offset(_ key: String) -> CGFloat {
                guard let now = Double(child.attributes[key] ?? ""),
                      let declared = Double(child.xmlParam(key) ?? "") else { return 0 }
                return CGFloat(now - declared)
            }
            let dx = offset("x"), dy = offset("y")
            if dx != 0 || dy != 0 { moved = true }
            if !node.frame.isEmpty { union = union.union(node.frame.offsetBy(dx: -dx, dy: -dy)) }
        }
        return moved && !union.isNull ? union : nil
    }

    /// A group whose `background` is not painted (`drawbackground="0"`) is shaped by it: Wasabi takes
    /// a group's region from its background's alpha, and the group's children draw inside that region
    /// only. ArmorAmp is the measured case: its spectrum is a 170x70 `<vis>` inside
    /// `background="visgroup.bg"`, a blade-shaped map of the screen. Clipped only to the box, the bars
    /// spilled over the screen bezel.
    func groupRegionMask(of object: WasabiObject, frame: CGRect) -> WasabiMaskClip? {
        guard object.tag.is(.group), !frame.isEmpty, paintedBackingID(of: object) == nil,
              let background = object.attributes["background"],
              let mask = resources.alphaMask(background: background, declaredIn: object.source)
        else { return nil }
        return WasabiMaskClip(mask: mask, rect: frame)
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

    /// Whether `object` paints only inside the window region the rest of the scene forms: a region
    /// layout (`layoutWantsOpaqueBacking`) and `sysregion="0"` on the object or a group above it.
    ///
    /// A region window is every pixel something paints (`promoteAlphaToRegion`), and `0` is the
    /// author opting an overlay out of that. cPro__Mecha marks exactly its four watermark and
    /// overlay-word layers so, and its `wm1` (grey at alpha ≤ 44) hangs past the frame into the 5px
    /// transparent resize strip whenever the player is narrower than ~393: counted as window, those
    /// pixels came out an opaque dark smudge its `screenshot.png` does not show (B286). Drawn
    /// `.sourceAtop`, such an object keeps the alpha already beneath it, so it tints the window and
    /// never extends it.
    /// ponytail: clips to what is drawn *before* the object, not to the finished region; an opted-out
    /// layer under the art that forms the window would vanish. Composite against the final region
    /// when a skin shows one.
    func paintsOnlyInsideRegion(_ object: WasabiObject) -> Bool {
        guard layoutWantsOpaqueBacking else { return false }
        return sequence(first: object, next: \.parent).contains {
            $0.attributes["sysregion"]?.trimmingCharacters(in: .whitespaces) == "0"
        }
    }

    /// The bitmap an object paints as its backing, or nil when it paints none. `background` is
    /// painted by default, as Wasabi does, unless `drawbackground` turns it off.
    ///
    /// A **layout** paints its backing whatever `drawbackground` says: the window's backing is the
    /// layout's bitmap, and the flag is a group's. 36 corpus skins pair `drawbackground="0"` with a
    /// layout `background=` — DDtank Glass's equalizer and about window drew their controls on the
    /// bare desktop, where its own preview shows the glass panel behind them. A `desktopalpha="1"`
    /// layout paints its `alphabackground` — `background` is then the opaque or region-map variant
    /// (Fuzzy Muffins' `main.alpha`, impulse's `player.normal.background.region`), and painting it
    /// put the mask's grey through every translucent pane.
    ///
    /// The one exception is a layout that pairs `drawbackground="0"` with `sysregion="1"`: its
    /// backings shape the window and are not painted. Only the iCandy family says both (iCandy,
    /// i-Skin, iCandy-2), and its `alphabackground`s are flat masks of where a drawer opens —
    /// painted, they were a black slab under the closed EQ drawer and a white one behind the
    /// remote's LCD (B273).
    func paintedBackingID(of object: WasabiObject) -> String? {
        if object.tag.is(.layout) {
            if object.attributes["drawbackground"] == "0", object.attributes["sysregion"] == "1" { return nil }
            if object.attributes["desktopalpha"] == "1", let alpha = object.attributes["alphabackground"] {
                return alpha
            }
            return object.attributes["background"]
        }
        guard let background = object.attributes["background"] else { return nil }
        let flag = object.attributes["drawbackground"]?.lowercased()
        return flag == "0" || flag == "false" || flag == "no" ? nil : background
    }

    enum Backing {
        case bitmap(WasabiBitmap)
        /// A backing the skin asked for and the `.wal` does not ship. 13 corpus skins name a layout
        /// `background=` — `component.basetexture`, `wasabi.frame.basetexture`, `studio.BaseTexture`,
        /// `wasabi.frame` — that in Winamp comes from the base Wasabi skin, which we have no
        /// equivalent of. A window whose only backing is one of those drew entirely transparent: EPS
        /// High-End's and Itemskin's notifier preferences are the reported case, where every control
        /// is painted in the skin's light list colours and vanishes against the desktop. Vision's
        /// standard frames name both base textures and ship neither, so they were see-through
        /// between the chrome and the content. The skin's own content background is the nearest
        /// thing we can answer with, and it is the same colour NullPlayer's embedded surfaces already
        /// use. Only when the skin *asked* for a backing: a layout that declares none is deliberately
        /// shaped and must stay transparent. So must a `desktopalpha="1"` layout, which composites
        /// against the desktop: Ryoko Asakura's player (`background="player.mainbg.ghost"`, a `.bmp`
        /// the archive does not ship) drew a solid white slab where its own screenshot shows the
        /// player art over the wallpaper (B271).
        case contentBackground
    }

    /// What an object paints behind its contents: its own backing, else a standard frame's base
    /// texture, else the content colour standing in for either one the skin names and lacks.
    func backing(of object: WasabiObject) -> Backing? {
        let backingID = paintedBackingID(of: object)
        if let bitmap = backingID.flatMap({ resources.bitmap(background: $0, declaredIn: object.source) }) {
            return .bitmap(bitmap)
        }
        if needsFrameBaseTexture(object) {
            if let texture = resources.bitmap(identifier: "wasabi.frame.basetexture")
                ?? resources.bitmap(identifier: "component.basetexture") {
                return .bitmap(texture)
            }
            return .contentBackground
        }
        guard object.tag.is(.layout), backingID != nil, object.attributes["desktopalpha"] != "1" else { return nil }
        return .contentBackground
    }

    /// The backing Winamp's own standard frame paints, for a frame whose window gives none.
    ///
    /// 19 corpus skins put a `<Wasabi:StandardFrame:*>` in a layout with no `background=` and
    /// declare `wasabi.frame.basetexture` (or `component.basetexture`) without ever naming it: the
    /// stock frame draws it. machina's help window drew its dark-on-transparent help art on the
    /// bare desktop without it, where its playlist — the same frame on `background="component.bg"`
    /// — was gold. A layout that declares a backing, or composites against the desktop, keeps its own.
    ///
    /// The XUI tag is shorthand for the group itself, so `<group id="wasabi.standardframe.*">` is the
    /// same frame: iCandy-2's Component layouts place theirs that way, and the strip between the
    /// title bar and the component showed the desktop (B276).
    private func needsFrameBaseTexture(_ object: WasabiObject) -> Bool {
        let isFrame = WasabiStandardFrames.isStandardFrame(object)
            || (object.tag.is(.group) && WasabiStandardFrames.isStandardFrameIdentifier(object.xmlID ?? ""))
        guard isFrame,
              let layout = object.parent, layout.tag.is(.layout) else { return false }
        return layout.attributes["background"] == nil && layout.attributes["desktopalpha"] != "1"
    }
}
