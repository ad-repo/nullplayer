import Foundation

/// The two decisions a skin's `<component param="{F0816D7B-…}">` makes about the host's video output,
/// kept apart from the window layer so both can be measured without an `NSWindow` (B20).
enum WinampModernVideoHolder {

    /// Winamp's command bar over the picture. `noshowcmdbar="1"` on the holder is the skin saying it
    /// draws the transport itself — five of the six corpus video windows do, and mmd3's does not.
    static func showsCommandBar(holderAttributes: [String: String]) -> Bool {
        switch holderAttributes["noshowcmdbar"]?.lowercased() {
        case "1", "true", "yes": return false
        default: return true
        }
    }

    /// `VID_1X` / `VID_2X`: the canvas the skin's video **window** needs so that its **box** is the
    /// stream's own pixel size times `multiple`.
    ///
    /// A `.wal` video layout is chrome around a `relatw="1"` holder, so the window grows by exactly
    /// the difference between the box the skin is drawing now and the box the stream wants; the
    /// frame, the buttons and the status bar keep their sizes and their places. `nil` when the
    /// decoder has published no size yet — where these buttons stay inert rather than sizing the
    /// window to a guess.
    static func canvasSize(canvas: CGSize, holder: CGRect, native: CGSize,
                           multiple: CGFloat) -> CGSize? {
        guard native.width > 0, native.height > 0, multiple > 0 else { return nil }
        return CGSize(width: canvas.width - holder.width + native.width * multiple,
                      height: canvas.height - holder.height + native.height * multiple)
    }
}
