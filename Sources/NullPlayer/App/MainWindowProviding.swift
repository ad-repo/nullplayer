import AppKit

/// Protocol abstracting the main player window.
/// Both the classic `MainWindowController` and modern `ModernMainWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
protocol MainWindowProviding: ModeDependentWindow {
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
    func updateVideoTrackInfo(title: String, artworkTrack: Track?)
    
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

    /// Show (or update) a transient activity indicator with a spinner + message,
    /// overlaid on the main window. Used for background work like ripping.
    func showActivity(_ message: String)

    /// Remove the activity indicator overlay.
    func hideActivity()
}

// MARK: - Default Implementations

private let activityOverlayID = NSUserInterfaceItemIdentifier("MainWindowActivityOverlay")
private let activityLabelID = NSUserInterfaceItemIdentifier("MainWindowActivityLabel")

extension MainWindowProviding {
    var isWindowVisible: Bool {
        window?.isVisible == true
    }

    func setNeedsDisplay() {
        window?.contentView?.needsDisplay = true
    }

    func showActivity(_ message: String) {
        guard let content = window?.contentView else { return }

        // Reuse the existing overlay if it is already showing.
        if let existing = content.subviews.first(where: { $0.identifier == activityOverlayID }) {
            (existing.subviews.first { $0.identifier == activityLabelID } as? NSTextField)?.stringValue = message
            content.addSubview(existing, positioned: .above, relativeTo: nil) // keep on top
            return
        }

        let barHeight: CGFloat = 22
        // Pinned to the TOP of the window (macOS origin is bottom-left).
        let bar = NSView(frame: NSRect(x: 0, y: content.bounds.height - barHeight, width: content.bounds.width, height: barHeight))
        bar.identifier = activityOverlayID
        bar.autoresizingMask = [.width, .minYMargin]
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor

        let spinner = NSProgressIndicator(frame: NSRect(x: 6, y: (barHeight - 14) / 2, width: 14, height: 14))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        bar.addSubview(spinner)

        let label = NSTextField(labelWithString: message)
        label.identifier = activityLabelID
        label.font = .systemFont(ofSize: 10)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 26, y: (barHeight - 14) / 2, width: content.bounds.width - 32, height: 14)
        label.autoresizingMask = [.width]
        bar.addSubview(label)

        content.addSubview(bar, positioned: .above, relativeTo: nil)
    }

    func hideActivity() {
        window?.contentView?.subviews
            .first { $0.identifier == activityOverlayID }?
            .removeFromSuperview()
    }
}
