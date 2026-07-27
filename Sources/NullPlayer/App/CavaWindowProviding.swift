import AppKit

/// Protocol abstracting the Cava window.
/// Both modern and classic implementations conform to this protocol.
protocol CavaWindowProviding: ModeDependentWindow {
    var window: NSWindow? { get }
    func showWindow(_ sender: Any?)
    func skinDidChange()
    func startRenderingForShow()
    func stopRenderingForHide()
    func tearDown()
}
