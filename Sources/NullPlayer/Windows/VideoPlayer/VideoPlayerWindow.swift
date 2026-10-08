import AppKit

/// The video controller's window. A borderless `NSWindow` answers `canBecomeKey` / `canBecomeMain`
/// false, so the free window never took focus and the video keys never reached it (M28).
///
/// Parked over a skin's video box it stays unfocusable: it is a child laid over a skin window that
/// holds key itself (`setAuxiliaryWindow` for `.wal`, `revealSkinSurface` for `.wmz`), and a click on
/// the picture must not take focus from the skin. The skin window hands the film its keys
/// (`handleParkedVideoKey`, M18).
final class VideoPlayerWindow: NSWindow {
    private var isParked: Bool { (windowController as? VideoPlayerWindowController)?.isVideoOutputHosted ?? false }
    override var canBecomeKey: Bool { !isParked }
    override var canBecomeMain: Bool { !isParked }
}
