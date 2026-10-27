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
    func paintedBackingID(of object: WasabiObject) -> String? {
        if object.tag.is(.layout) {
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
    private func needsFrameBaseTexture(_ object: WasabiObject) -> Bool {
        guard WasabiStandardFrames.isStandardFrame(object),
              let layout = object.parent, layout.tag.is(.layout) else { return false }
        return layout.attributes["background"] == nil && layout.attributes["desktopalpha"] != "1"
    }
}
