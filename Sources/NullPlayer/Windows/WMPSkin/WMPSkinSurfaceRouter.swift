import AppKit

/// `.wmz`'s answer to the shared surface route, over the controller that owns the skin's windows.
///
/// The skin draws the playlist or the equaliser whenever it declares one (`WMPSkinSurfaces`), and
/// NullPlayer's window is the fallback for the handful that do not. The format has no library, so
/// the library is always NullPlayer's. `WindowManager.skinSurfaceRouter` builds it over the
/// controller for the `.wmp` family.
struct WMPSkinSurfaceRouter: SkinSurfaceRouter {
    let controller: WMPMainWindowController

    /// The `.wmz` surface a shared one maps to, nil for one the format cannot declare.
    static func wmpSurface(_ surface: SkinSurface) -> WMPSkinSurface? {
        switch surface {
        case .playlist: return .playlist
        case .equalizer: return .equalizer
        case .video: return .video
        case .library: return nil
        }
    }

    func drawsSurface(_ surface: SkinSurface) -> Bool {
        Self.wmpSurface(surface).map(controller.skinSurfaces.provides) ?? false
    }

    /// On screen in **any** open WMP window, not only the player's view: a panel the skin opened
    /// with `theme.openView` is a window of its own.
    func isShowingSurface(_ surface: SkinSurface) -> Bool {
        Self.wmpSurface(surface).map { controller.windowShowing($0) != nil } ?? false
    }

    /// Opens the surface the way the skin's own button does, for a toggle and a show alike: a
    /// surface already on screen is left alone. A skin's view sizes itself, so `restoredFrame` is
    /// ignored.
    func revealSurface(_ surface: SkinSurface, toggle: Bool, restoredFrame: NSRect?) {
        guard let wmp = Self.wmpSurface(surface) else { return }
        controller.revealSkinSurface(wmp)
    }

    /// A skin's view opens; its button never closes it.
    func toggleClosesSurface(_ surface: SkinSurface) -> Bool { false }

    /// During the launch hold the skin has not said yet what it draws (`launchHoldTimeout`).
    func deferUntilSkinLoads(_ surface: SkinSurface, _ open: @escaping () -> Void) -> Bool {
        controller.deferUntilLaunchSettles(open)
    }
}
