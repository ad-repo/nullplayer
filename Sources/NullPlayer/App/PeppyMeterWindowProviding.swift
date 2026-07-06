import AppKit

/// Protocol abstracting the PeppyMeter window.
/// Both the modern and classic implementations conform to this protocol.
protocol PeppyMeterWindowProviding: ModeDependentWindow {
    var window: NSWindow? { get }
    var isFullscreen: Bool { get }
    func showWindow(_ sender: Any?)
    func skinDidChange()
    func startRenderingForShow()
    func stopRenderingForHide()
    func tearDown()
    func toggleFullscreen()
}
