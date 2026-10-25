import CoreGraphics
import Foundation

/// An alpha mask placed in scene coordinates.
struct WasabiMaskClip {
    let mask: CGImage
    let rect: CGRect
}

/// What a group clips its children to beyond its declared box: the alpha of a background it does
/// not paint, and the aperture a target animation slides a child within.
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
        guard !frame.isEmpty, paintedBackingID(of: object) == nil,
              let background = object.attributes["background"], backgroundBitmap(of: object) != nil,
              let mask = resources.regionMask(WasabiRegionClip(mapID: background, mapPath: nil,
                                                               threshold: 0, reversed: false))
        else { return nil }
        return WasabiMaskClip(mask: mask, rect: frame)
    }
}
