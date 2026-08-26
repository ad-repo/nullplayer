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

    /// The one entry point: each correction below is tried in turn, and every one of them is scoped
    /// tightly enough that at most one can ever answer for a given object.
    static func correctedFrame(for object: WasabiObject, resolved: CGRect) -> CGRect? {
        if let corrected = bentoSidePlaylistHeight(for: object, resolved: resolved) { return corrected }
        return promoArtOffset(for: object, resolved: resolved)
    }

    /// Big Bento Modern (all four variants): the side playlist's height is written as an absolute
    /// pixel count through the *relative* flag.
    ///
    /// `pledit.maki` lays out the side playlist from `player.mainframe.big`, the splitter whose own
    /// markup comment reads *"h=202 determines Side Playlist height"*. Enlarging it writes:
    ///
    /// ```
    /// mainframe.setXmlParam("relath", "1");
    /// mainframe.setXmlParam("h", integerToString(h));   // 819 at an 878px window
    /// ```
    ///
    /// and 819 is `(sui.content.y + sui.content.h) − mainframe.y` = `853 − 34` — the skin's own
    /// arithmetic for *"reach the bottom of the tab area"*, an absolute height. Resolved relatively
    /// (`parent.height + h`, which is what every other `relath="1"` in the corpus means) it comes out
    /// at 1697 in an 878px window: the splitter's right pane hangs 800px below the window, and with
    /// it `player.component.playlist.buttons`, which is anchored to that pane's *bottom* edge
    /// (`y="-37" relaty="1"`). Measured: the playlist's add/remove/collapse bar lands at y=1570 and
    /// the enlarged playlist is indistinguishable on screen from the collapsed one, because both
    /// simply fill to the window edge and clip. Taking the number as written puts the bar back on
    /// screen and makes the two states differ by the 617px the skin intends.
    ///
    /// The collapse branch writes `relath="0"` with `h="202"`, so only the enlarge branch is ever
    /// corrected here, and the script recomputes the number on every resize — which is what makes
    /// this exact at every window size rather than a fixed offset.
    ///
    /// Scoped to that one splitter, by id *and* type: a positive relative height on anything else is
    /// left exactly as the skin wrote it.
    private static func bentoSidePlaylistHeight(for object: WasabiObject, resolved: CGRect) -> CGRect? {
        guard object.xmlID?.caseInsensitiveCompare(sidePlaylistFrameID) == .orderedSame,
              WasabiFrame.isFrame(object), object.attributes["relath"] == "1",
              let declared = Double(object.attributes["h"] ?? ""), declared > 0,
              CGFloat(declared) < resolved.height else { return nil }
        return CGRect(x: resolved.minX, y: resolved.minY,
                      width: resolved.width, height: CGFloat(declared))
    }

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
    private static func promoArtOffset(for object: WasabiObject, resolved: CGRect) -> CGRect? {
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

    private static let sidePlaylistFrameID = "player.mainframe.big"
    private static let promoGroupID = "beatpromo"
    private static let promoArtID = "beat.promo"
}
