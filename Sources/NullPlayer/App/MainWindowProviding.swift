import AppKit

/// Protocol abstracting the main player window.
/// Both the classic `MainWindowController` and modern `ModernMainWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
protocol MainWindowProviding: AnyObject {
    /// The underlying window
    var window: NSWindow? { get }
    
    /// Whether the window is in shade (compact) mode
    var isShadeMode: Bool { get }
    
    /// Whether the window is currently visible
    var isWindowVisible: Bool { get }
    
    /// Show the window
    func showWindow(_ sender: Any?)
    
    /// Update the displayed track info (title, artist, bitrate, etc.)
    func updateTrackInfo(_ track: Track?)
    
    /// Update video track info display
    func updateVideoTrackInfo(title: String)
    
    /// Clear video track info and revert to audio display
    func clearVideoTrackInfo()
    
    /// Update the time display
    func updateTime(current: TimeInterval, duration: TimeInterval)
    
    /// Update playback state indicators (play/pause/stop)
    func updatePlaybackState()
    
    /// Feed spectrum analyzer data for visualization
    func updateSpectrum(_ levels: [Float])
    
    /// Toggle shade (compact) mode
    func toggleShadeMode()
    
    /// Notify that the skin has changed and views should redraw
    func skinDidChange()
    
    /// Notify that window visibility of sibling windows changed (for toggle button states)
    func windowVisibilityDidChange()
    
    /// Mark the window content as needing redraw
    func setNeedsDisplay()
}

// MARK: - Default Implementations

extension MainWindowProviding {
    var isWindowVisible: Bool {
        window?.isVisible == true
    }
    
    func setNeedsDisplay() {
        window?.contentView?.needsDisplay = true
    }
}
