import AppKit

/// Protocol abstracting the ProjectM visualization window.
/// Both the classic `ProjectMWindowController` and modern `ModernProjectMWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
///
/// Follows the same pattern as `MainWindowProviding` and `SpectrumWindowProviding`.
protocol ProjectMWindowProviding: AnyObject {
    /// The underlying window
    var window: NSWindow? { get }
    
    /// Whether the window is in shade (compact) mode
    var isShadeMode: Bool { get }
    
    /// Whether the window is in custom fullscreen mode
    var isFullscreen: Bool { get }
    
    /// Show the window
    func showWindow(_ sender: Any?)
    
    /// Notify that the skin has changed and views should redraw
    func skinDidChange()
    
    /// Stop rendering when window is hidden via orderOut (saves CPU)
    func stopRenderingForHide()
    
    /// Toggle shade (compact) mode
    func setShadeMode(_ enabled: Bool)
    
    /// Toggle custom fullscreen mode
    func toggleFullscreen()
    
    // MARK: - Preset Navigation
    
    /// Go to next preset
    func nextPreset(hardCut: Bool)
    
    /// Go to previous preset
    func previousPreset(hardCut: Bool)
    
    /// Select preset at specific index
    func selectPreset(at index: Int, hardCut: Bool)
    
    /// Select a random preset
    func randomPreset(hardCut: Bool)
    
    /// Lock or unlock the current preset
    var isPresetLocked: Bool { get set }
    
    /// Whether projectM is available
    var isProjectMAvailable: Bool { get }
    
    /// Current preset name
    var currentPresetName: String { get }
    
    /// Current preset index
    var currentPresetIndex: Int { get }
    
    /// Total number of presets
    var presetCount: Int { get }
    
    /// Reload all presets from bundled and custom folders
    func reloadPresets()
    
    /// Get information about loaded presets
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) { get }
}
