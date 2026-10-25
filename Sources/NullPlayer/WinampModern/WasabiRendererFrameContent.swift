import CoreGraphics
import Foundation

/// A standard frame's content group that states the room it needs.
extension WasabiSceneRenderer {
    /// `size` grown on each axis until every standard frame's content group gets the `minimum_w`/
    /// `minimum_h` its groupdef declares (B261).
    ///
    /// The frame's script instantiates the content at the frame's margins, so the window's size is
    /// the content's plus those margins. H2O Liquid's `Cfg` is a 400x300 layout around a
    /// `Wasabi:StandardFrame:Static` whose `28,56,-55,-100` margins leave `cfg.content.group` 345x200,
    /// and the groupdef fixes itself at 350x235: its CPU-usage table showed 2½ of its five rows.
    /// Clamping the *group* to its range instead pushed content past the frame in five other skins,
    /// so it is the window that grows, to 405x335 there.
    ///
    /// Measured on the resolved scene, like the content fit: a content group that does not stretch
    /// with the canvas on an axis cannot be given room on it, and is left alone.
    func frameContentFittedSize(_ size: CGSize) -> CGSize {
        var grown = size
        let maximum = layoutMaximumSize
        for node in sceneNodes(canvas: size) where Self.isFrameContent(node.object) {
            let attributes = node.object.attributes
            func minimum(_ key: String) -> CGFloat? {
                attributes[key].flatMap(Double.init).map { CGFloat($0) }.flatMap { $0 > 0 ? $0 : nil }
            }
            if attributes["relatw"] == "1", let width = minimum("minimum_w") {
                grown.width = max(grown.width, min(maximum.width, size.width + width - node.frame.width))
            }
            if attributes["relath"] == "1", let height = minimum("minimum_h") {
                grown.height = max(grown.height, min(maximum.height, size.height + height - node.frame.height))
            }
        }
        return grown
    }

    /// Whether `object` is the group an enclosing standard frame names as its `content`.
    private static func isFrameContent(_ object: WasabiObject) -> Bool {
        guard object.tag.is(.group), let id = object.xmlID else { return false }
        var ancestor = object.parent
        while let frame = ancestor, !frame.tag.is(.layout) {
            if WasabiStandardFrames.contentGroupIdentifier(of: frame.attributes)?
                .caseInsensitiveCompare(id) == .orderedSame { return true }
            ancestor = frame.parent
        }
        return false
    }
}
