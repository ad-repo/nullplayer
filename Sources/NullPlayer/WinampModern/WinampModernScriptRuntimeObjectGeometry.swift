import CoreGraphics
import Foundation

/// Where a GUI object sits, as its script asks: the scene's resolved box when there is one, the
/// markup's declared geometry otherwise, and `<GroupList>` stacking.
extension WinampModernScriptRuntime {
    /// `getGui*` on an axis the markup made relative: the markup's own value, or nil for an absolute
    /// axis, which answers the resolved box like `getLeft`/`getWidth`.
    static func relativeMarkup(of object: WasabiObject, axis: String) -> Int32? {
        guard ["1", "2"].contains(object.attributes["relat" + axis]),
              let raw = Double(object.attributes[axis] ?? "") else { return nil }
        return Int32(clamping: Int(raw))
    }

    /// An object's box in its **parent's** coordinates — the space Wasabi's `getGuiX`/`getGuiY` and
    /// `getLeft`/`getTop` report in — or `nil` when no scene can place it.
    ///
    /// Reading the raw `x`/`y`/`w`/`h` attributes instead is only right for absolute geometry, and
    /// Bento-style skins barely use any: cPro's tab strip is `w="-4" relatw="1"`, so `getWidth()`
    /// answered **−4**, `CproTabs.m` concluded it had no room for its tabs, switched to short names and
    /// squeezed every tab to the 20px floor. The declared value stays as the fallback for an object the
    /// active scene does not contain (a hidden layout, or a runtime with no window wired at all).
    func resolvedFrame(of object: WasabiObject) -> CGRect? {
        guard let geometry = hooks.resolvedGeometryRequested?(object) else { return nil }
        return geometry.frame.offsetBy(dx: -geometry.parent.minX, dy: -geometry.parent.minY)
    }

    /// Wasabi's `<GroupList>` is a **vertical stack**: each instance spans the list's width and sits
    /// below the ones already in it. Two things follow, and both have to be stamped onto the child
    /// here because a groupdef carries neither.
    ///
    /// *Width.* The part groupdefs declare `h=` and no `w=` at all, so a child left at its markup
    /// geometry is zero-width and draws nothing — its own contents are relative to it
    /// (`w="-203" relatw="1"`), which is a negative box, not a small one.
    ///
    /// *Top.* Both parts would otherwise land at `y=0` and cover each other. The offset is the sum of
    /// the heights the earlier siblings declare, which is the number the author writes the groupdef's
    /// `h=` for (Big Bento's pages are 223+220, 243+251, …) — and the same number the page's
    /// scrollbar script compares its `param`'s third token against to decide whether to show itself.
    ///
    /// Anything that is not a `GroupList` keeps whatever geometry it was instantiated with.
    func stackInGroupList(_ child: WasabiObject, list: WasabiObject) {
        guard list.tag.is(.groupList) else { return }
        var top = 0.0
        for sibling in list.children where sibling !== child { top += stackedHeight(of: sibling) }
        _ = child.setAttribute("x", value: "0")
        _ = child.setAttribute("relatx", value: "0")
        _ = child.setAttribute("y", value: String(Int(top.rounded())))
        _ = child.setAttribute("relaty", value: "0")
        _ = child.setAttribute("w", value: "0")
        _ = child.setAttribute("relatw", value: "1")
    }

    /// The vertical room one list entry takes. The declared `h=` is the authority — the entries are
    /// stacked before any layout pass has run, so a resolved frame exists for at most the ones
    /// already on screen, and mixing the two units would stack the second entry against the first
    /// one's *scene* height rather than the height the author sized the list around.
    func stackedHeight(of object: WasabiObject) -> Double {
        max(0, Double(object.attributes["h"] ?? "") ?? 0)
    }

    /// A resolved coordinate when the scene could supply one, and the markup's own value otherwise.
    /// Where an object sits by its declared geometry alone, for one no window has laid out — a layout
    /// that is not showing. Its relative sizes resolve against its parents up to the layout, which
    /// is sized by `w`, `default_w` or `minimum_w`. Answering the raw attribute instead gave
    /// NEO_CLASSIC's shrunk layout a title bar `-32` wide (`w="-32" relatw="1"`), and its title
    /// script centred the title on that.
    func declaredFrame(of object: WasabiObject, depth: Int = 0) -> WasabiRect {
        if Self.isWindowObject(object) || depth > 64 {
            func size(_ keys: [String]) -> Double {
                keys.lazy.compactMap { object.attributes[$0].flatMap(Double.init) }.first { $0 > 0 } ?? 0
            }
            return WasabiRect(x: 0, y: 0, width: size(["w", "default_w", "minimum_w"]),
                              height: size(["h", "default_h", "minimum_h"]))
        }
        guard let parent = object.parent else { return object.geometry.resolve(in: .zero) }
        return object.geometry.resolve(in: declaredFrame(of: parent, depth: depth + 1))
    }

    func dimension(_ resolved: CGFloat?, declared: Double) -> Int32 {
        Int32(clamping: Int(resolved.map(Double.init) ?? declared))
    }
}
