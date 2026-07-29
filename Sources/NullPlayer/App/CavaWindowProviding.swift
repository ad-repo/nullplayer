import AppKit

/// Protocol abstracting the Cava window.
/// Both modern and classic implementations conform to this protocol.
protocol CavaWindowProviding: ModeDependentWindow {
    var window: NSWindow? { get }
    func showWindow(_ sender: Any?)
    func skinDidChange()
    /// Re-read tuning from `CavaSettings` and re-derive skin-default colors after a
    /// "Reset All Visualization Preferences" cleared the standalone Cava window keys.
    func refreshAfterReset()
    func startRenderingForShow()
    func stopRenderingForHide()
    func tearDown()
}
