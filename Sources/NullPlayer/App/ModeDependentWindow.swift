import AppKit

/// Common base for every window controller whose existence depends on the active UI mode
/// (classic vs. modern). `WindowManager` collects these into
/// `modeDependentWindowControllers` so it can tear them down and rebuild them as a group
/// when the UI is reloaded — without touching the mode-independent video player.
///
/// The teardown lifecycle hook `prepareForUITeardown()` is the synchronous moment for each
/// controller (and its root view) to release resources that must not outlive the window:
/// cancel in-flight tasks, invalidate timers, stop render loops, and unregister observers /
/// audio-consumer registrations. It runs *before* the window is closed and the controller is
/// niled, so it cannot rely on `deinit` (whose timing AppKit may defer via the autorelease
/// pool). Application-level services (audio engine, casting, library scans) must be left
/// running — only the UI layer is being replaced.
protocol ModeDependentWindow: AnyObject {
    /// The underlying window.
    var window: NSWindow? { get }

    /// Synchronously release any resources that must not survive a UI teardown.
    /// Default implementation is a no-op; controllers that own render loops, timers, or
    /// in-flight tasks should override (or inherit one of the protocol-specific defaults below).
    func prepareForUITeardown()
}

extension ModeDependentWindow {
    func prepareForUITeardown() {}
}

// MARK: - Protocol-specific teardown defaults

// Controllers that drive a continuous render loop already expose a "stop when hidden" hook;
// reuse it as the teardown action so rendering halts before the window is closed.

extension SpectrumWindowProviding {
    func prepareForUITeardown() { stopRenderingForHide() }
}

extension ProjectMWindowProviding {
    func prepareForUITeardown() { stopRenderingForHide() }
}

extension AudioAnalysisWindowProviding {
    func prepareForUITeardown() { stopRenderingForHide() }
}

extension PeppyMeterWindowProviding {
    func prepareForUITeardown() { tearDown() }
}

extension NetworkMonitorWindowProviding {
    func prepareForUITeardown() { tearDownMonitoring() }
}

extension WaveformWindowProviding {
    func prepareForUITeardown() { stopLoadingForHide() }
}
