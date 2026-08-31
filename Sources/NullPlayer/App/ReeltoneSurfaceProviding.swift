import AppKit

struct ReeltonePanelLayoutSnapshot {
    let surfaceID: ReeltoneSurfaceID
    let frame: NSRect
    let wasVisible: Bool
    let wasAttached: Bool
}

struct ReeltoneSurfaceLayoutSnapshot {
    let skinIdentity: String
    let panels: [ReeltonePanelLayoutSnapshot]
}

/// Narrow WindowManager seam for Reeltone's dynamic surface set.
protocol ReeltoneSurfaceProviding: AnyObject {
    var reeltoneWindows: [NSWindow] { get }
    var reeltonePanelMenuEntries: [ReeltonePanelMenuEntry] { get }
    func applyReeltoneScale(_ scale: CGFloat)
    func routeReeltoneComponent(_ component: ReeltoneComponent) -> Bool
    func setReeltoneAlwaysOnTop(_ enabled: Bool)
    func toggleReeltonePanel(_ name: String)
    func captureReeltoneSurfaceLayout() -> ReeltoneSurfaceLayoutSnapshot?
    func restoreReeltoneSurfaceLayout(_ snapshot: ReeltoneSurfaceLayoutSnapshot)
}
