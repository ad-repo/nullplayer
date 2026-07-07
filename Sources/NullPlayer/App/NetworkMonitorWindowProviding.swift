import AppKit

/// Protocol abstracting the Network Monitor window.
/// Both modern and classic implementations conform to this protocol.
protocol NetworkMonitorWindowProviding: ModeDependentWindow {
    var window: NSWindow? { get }
    func showWindow(_ sender: Any?)
    func skinDidChange()
    func startMonitoringForShow()
    func stopMonitoringForHide()
    func tearDownMonitoring()
}
