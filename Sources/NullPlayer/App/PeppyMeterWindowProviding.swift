import AppKit

/// Protocol abstracting the PeppyMeter window.
/// Both the modern and classic implementations conform to this protocol.
protocol PeppyMeterWindowProviding: ModeDependentWindow {
    var window: NSWindow? { get }
    func showWindow(_ sender: Any?)
    func skinDidChange()
    func startRenderingForShow()
    func stopRenderingForHide()
    func tearDown()
}
