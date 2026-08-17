import CoreGraphics
import Foundation

/// Corrections for arithmetic a skin's own script gets wrong, applied to resolved geometry only.
///
/// **This file should stay almost empty.** The engine runs a skin's scripts and draws what they
/// compute; second-guessing them is how a renderer ends up full of per-skin special cases that nobody
/// dares touch. An entry belongs here only when all of this holds:
///
/// 1. the defect is visible and repeatable in a real run,
/// 2. the correct placement is *derivable from the skin's own numbers* rather than guessed, and
/// 3. the correction is exact at every size, and provably a no-op in the cases that already work.
///
/// Each entry names the skin, the script, and the measurement that justifies it, so a future agent can
/// delete it the moment a real Winamp shows the uncorrected behaviour is what the author intended.
enum WasabiSkinQuirks {

    /// ClassicPro (cPro-Bento): the promo art double-centres itself.
    ///
    /// `beat.m` shows either the beat visualization or a ClassicPro logo in the same slot of the
    /// display, and double-clicking swaps them. The beat visualization lands centred at every width.
    /// The logo does not, and it is out by exactly its own offset *inside* its box:
    ///
    /// ```c
    /// // engine/one/scripts/beat.m, frameGroup.onResize:
    /// else { promoPic.setXmlParam("image","cPro.promo.1"); promoPic.resize(150,0,99,45); }
    /// promoGroup.setXmlParam("x", integerToString(143+(w-317)/2-promoPic.getWidth()/2));
    /// ```
    ///
    /// `beatpromo` is a fixed 300-wide box; the picture is placed **inside** it at +0 / +50 / +150 for
    /// the 300 / 200 / 99-wide art (the first two are exactly `(300 − artWidth) / 2`, i.e. centred in
    /// the box). The box is then placed at `displayCentre − artWidth/2` — which already centres the
    /// *picture*, so the picture's own in-box offset is applied twice. Measured against the display
    /// centre `143 + (w − 317) / 2`, with the beat visualization for comparison:
    ///
    /// | canvas | centre | beat vis | promo art | promo offset |
    /// |---|---|---|---|---|
    /// | 700 | 334.5 | 334 ✓ | 334 ✓ | +0 |
    /// | 560 | 264.5 | 264 ✓ | 314 ✗ | +50 |
    /// | 500 | 234.5 | 234 ✓ | 384.5 ✗ | +150 |
    ///
    /// So: shift the box left by the picture's in-box offset. Exact at all three branches, and a no-op
    /// for the 300-wide art, which already lands correctly — the case that proves our `resize()` /
    /// `getWidth()` semantics are right and that this is the skin's arithmetic, not ours.
    ///
    /// Scoped by the two ids together (`beatpromo` holding a `beat.promo`), which only ClassicPro's
    /// engine declares, in either of its `one`/`two` variants.
    static func correctedFrame(for object: WasabiObject, resolved: CGRect) -> CGRect? {
        guard object.xmlID?.caseInsensitiveCompare(promoGroupID) == .orderedSame,
              let picture = object.children.first(where: {
                  $0.xmlID?.caseInsensitiveCompare(promoArtID) == .orderedSame
              }),
              let offset = Double(picture.attributes["x"] ?? ""), offset > 0,
              // The picture is positioned in raw pixels inside the box; a relative x is a different
              // idiom and not the one measured here.
              picture.attributes["relatx"] != "1" else { return nil }
        return resolved.offsetBy(dx: -CGFloat(offset), dy: 0)
    }

    private static let promoGroupID = "beatpromo"
    private static let promoArtID = "beat.promo"
}
