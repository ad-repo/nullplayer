import AppKit

/// A window of NullPlayer's that a loaded skin may draw its own copy of. These are the surfaces every
/// family is asked about through one route; the visualization windows stay on their families' own
/// routes.
enum SkinSurface: CaseIterable {
    case playlist
    case library
    case equalizer
    case video
}

/// Answers show, toggle and visibility for the surfaces the loaded skin draws itself, so the View
/// menu, a restored session and the skin's own button reach the same thing. NullPlayer's window is
/// the fallback for every surface `drawsSurface` answers false for.
///
/// One conformer per family, picked by `WindowManager.skinSurfaceRouter`'s switch on the family:
/// `.wal`'s `WinampModernSurfaceCoordinator`, `.wmz`'s `WMPSkinSurfaceRouter` and Sonique's controller
/// (its navigator drawer is its equaliser).
protocol SkinSurfaceRouter {
    /// Whether the skin draws this surface itself, so NullPlayer must not open its own window for it.
    func drawsSurface(_ surface: SkinSurface) -> Bool
    /// Whether the skin's copy of a surface it draws is on screen.
    func isShowingSurface(_ surface: SkinSurface) -> Bool
    /// Whether a toggle of a surface the skin draws can put it away. False where the skin's own
    /// button only ever opens it (a `.wmz` view): the View menu then shows the item checked and
    /// inert while it is on screen, as there is nothing for it to do.
    func toggleClosesSurface(_ surface: SkinSurface) -> Bool
    /// Shows a surface the skin draws. `toggle` false is a show (a menu restore, the launch restore,
    /// a mode rebuild); `restoredFrame` is the saved frame for a skin-owned *window*, and a router
    /// whose surface has no window of its own ignores it.
    func revealSurface(_ surface: SkinSurface, toggle: Bool, restoredFrame: NSRect?)
    /// Holds the opening of NullPlayer's window for `surface` until the skin has said whether it draws
    /// that surface itself; false when there is nothing to wait for and the caller opens now.
    func deferUntilSkinLoads(_ surface: SkinSurface, _ open: @escaping () -> Void) -> Bool
}

extension SkinSurfaceRouter {
    func toggleClosesSurface(_ surface: SkinSurface) -> Bool { true }
    func deferUntilSkinLoads(_ surface: SkinSurface, _ open: @escaping () -> Void) -> Bool { false }
}
