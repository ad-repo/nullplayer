import AppKit

/// Protocol abstracting the waveform window.
/// Both the classic `WaveformWindowController` and modern `ModernWaveformWindowController`
/// conform to this protocol so `WindowManager` can manage them without knowing the UI mode.
protocol WaveformWindowProviding: ModeDependentWindow {
    /// The underlying window.
    var window: NSWindow? { get }

    /// Show the window.
    func showWindow(_ sender: Any?)

    /// Notify that the skin has changed and the window should redraw.
    func skinDidChange()

    /// Update the active track used for waveform generation.
    func updateTrack(_ track: Track?)

    /// Update playback time for played/unplayed rendering.
    func updateTime(current: TimeInterval, duration: TimeInterval)

    /// Regenerate the waveform for the current track.
    func reloadWaveform(force: Bool)

    /// Stop any in-flight loading work when hidden.
    func stopLoadingForHide()
}
