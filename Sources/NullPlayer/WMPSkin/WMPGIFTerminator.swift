import Foundation

/// **A one-shot GIF that ends on a degenerate `restore to background` frame ends showing nothing.**
///
/// A `.wmz` opens its shutter by assigning an animated GIF to a `<SUBVIEW>` drawn *over* the
/// player's face — `shutterSub.backgroundImage = "shutter_open.gif"` — and nothing in the skin's
/// script ever hides that subview again. The closed state is held by a separate static child
/// (`<subview id="shutterStatic" backgroundImage="shutter_static.png">`) that the same handler
/// turns on and off, which only makes sense if the *animation* itself leaves nothing behind. Holding
/// its last frame instead buried everything under it: on `Windows_XP_Media_Center_Edition` the
/// final frame is an opaque blue plate over the whole display, so the metadata, status, elapsed
/// readout, seek slider **and the equaliser panel the skin opens in the same rectangle** were all
/// drawn and then covered. Reported 2026-09-14 as "the eq does not work".
///
/// The authors say it two ways and both are one-shot (no NETSCAPE2.0 loop extension):
///
/// - `Halo 2`'s `m_shutter_open.gif` ends on a **full-size frame that is entirely the key colour**,
///   so holding it is already invisible and this rule changes nothing there;
/// - the Windows XP family, `Age_of_Mythology`, `MechAssault`, `T3-Skynet`, `bruteforce`,
///   `Plus! Pulsar` and 27 other archives append a **1x1 image block with disposal method 2**
///   after the last real frame — a terminator several GIF tools emit for "and then it is gone".
///
/// `Age_of_Mythology` is the case that settles the shape of the rule: its `open_shutter.gif` carries
/// the terminator and its `close_shutter.gif` does not, ending instead on a full-size 80%-opaque
/// closed shutter that must persist. The author uses the terminator exactly where the animation has
/// to vanish. **Disposal alone is not the test** — 379 corpus GIFs are one-shot with a full-size
/// disposal-2 final frame, including `ALXMorph`'s six-frame idle logo, and clearing those would
/// erase artwork nothing is wrong with. The degenerate final *block* is what separates them:
/// **79 files across 33 archives**, measured over the installed corpus on 2026-09-14, and they are
/// almost entirely named `shutter_open`, `shutter_close` and `intro_anim`.
///
/// Only the **renderer** consults this. Hit testing and coverage still read the sprite, so a
/// cleared animation does not change which control a click reaches.
enum WMPGIFTerminator {

    /// The most pixels a final image block may cover and still be a terminator rather than artwork.
    /// Every corpus terminator is exactly `1x1`; the slack is for a tool that writes `2x1`. The
    /// **canvas** must be larger than this too — a genuinely tiny animation is artwork at its own
    /// size, and "degenerate" only means anything relative to what the frame is a frame *of*.
    static let degenerateFramePixels = 4

    /// GIF's "restore to background colour" disposal method.
    private static let restoreToBackground = 2

    /// Walks the GIF block stream for the last image block's size and the disposal method of the
    /// graphic control extension that introduced it. Returns `false` for anything it cannot read —
    /// a malformed stream must not blank a skin's artwork.
    static func clearsWhenFinished(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        // Header (6) + logical screen descriptor (7).
        guard bytes.count > 13, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 else {
            return false
        }
        let canvasPixels = (Int(bytes[6]) | Int(bytes[7]) << 8) * (Int(bytes[8]) | Int(bytes[9]) << 8)
        guard canvasPixels > degenerateFramePixels else { return false }
        var cursor = 13
        let screenPacked = bytes[10]
        if screenPacked & 0x80 != 0 { cursor += 3 << ((Int(screenPacked) & 7) + 1) }

        var pendingDisposal = 0
        var lastDisposal = 0
        var lastFrameIsDegenerate = false

        while cursor < bytes.count {
            switch bytes[cursor] {
            case 0x3B:                                              // trailer
                return lastFrameIsDegenerate && lastDisposal == restoreToBackground
            case 0x21:                                              // extension
                cursor += 1
                guard cursor < bytes.count else { return false }
                let label = bytes[cursor]
                cursor += 1
                // Graphic control extension: one 4-byte sub-block whose first byte packs the
                // disposal method in bits 2-4. It applies to the image block that follows it.
                if label == 0xF9, cursor + 1 < bytes.count, bytes[cursor] >= 1 {
                    pendingDisposal = Int((bytes[cursor + 1] >> 2) & 7)
                }
                cursor = skipSubBlocks(in: bytes, from: cursor)
            case 0x2C:                                              // image descriptor
                guard cursor + 10 <= bytes.count else { return false }
                let width = Int(bytes[cursor + 5]) | Int(bytes[cursor + 6]) << 8
                let height = Int(bytes[cursor + 7]) | Int(bytes[cursor + 8]) << 8
                let framePacked = bytes[cursor + 9]
                lastFrameIsDegenerate = width * height <= degenerateFramePixels
                lastDisposal = pendingDisposal
                pendingDisposal = 0
                cursor += 10
                if framePacked & 0x80 != 0 { cursor += 3 << ((Int(framePacked) & 7) + 1) }
                guard cursor < bytes.count else { return false }
                cursor += 1                                         // LZW minimum code size
                cursor = skipSubBlocks(in: bytes, from: cursor)
            default:
                return false
            }
        }
        return lastFrameIsDegenerate && lastDisposal == restoreToBackground
    }

    /// Past a run of length-prefixed data sub-blocks, ending on the zero-length terminator.
    private static func skipSubBlocks(in bytes: [UInt8], from start: Int) -> Int {
        var cursor = start
        while cursor < bytes.count {
            let length = Int(bytes[cursor])
            cursor += 1
            if length == 0 { break }
            cursor += length
        }
        return cursor
    }
}
