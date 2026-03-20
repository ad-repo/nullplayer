import Foundation
import OpenGL.GL3

// Import the C projectM library when available
#if canImport(CProjectM)
import CProjectM
#endif

/// Swift wrapper around libprojectM v4 for ProjectM visualization
///
/// This class manages a projectM instance for rendering ProjectM presets
/// with real-time audio visualization.
class ProjectMWrapper: VisualizationEngine {
    
    // MARK: - Types
    
    /// Notification posted when preset changes
    static let presetDidChangeNotification = Notification.Name("ProjectMPresetDidChange")
    
    // MARK: - Properties
    
    #if canImport(CProjectM)
    /// The projectM instance handle
    private var handle: projectm_handle?
    #endif
    
    /// Whether projectM is available (library loaded)
    private(set) var isAvailable: Bool = false

    /// Display name for the visualization engine
    var displayName: String {
        return "ProjectM (ProjectM)"
    }

    /// Current viewport dimensions
    private var viewportWidth: Int = 0
    private var viewportHeight: Int = 0
    
    /// List of preset file paths
    private var presetFiles: [String] = []
    
    /// Current preset index
    private var _currentPresetIndex: Int = 0
    
    /// Pending preset index to load on the next render frame (protected by renderLock)
    /// Preset loading requires an active OpenGL context, so it must happen on the
    /// CVDisplayLink render thread where the context is always current.
    private var _pendingPresetIndex: Int? = nil
    
    /// Lock for thread-safe PCM updates
    private let pcmLock = NSLock()
    
    /// Lock for thread-safe rendering and preset switching
    private let renderLock = NSLock()
    
    // MARK: - Computed Properties
    
    /// Number of presets in the playlist
    var presetCount: Int {
        return presetFiles.count
    }
    
    /// Currently selected preset index
    var currentPresetIndex: Int {
        return _currentPresetIndex
    }
    
    /// Name of the currently selected preset
    var currentPresetName: String {
        return presetName(at: _currentPresetIndex)
    }
    
    /// Whether the current preset is locked (no auto-switching)
    var isPresetLocked: Bool {
        get {
            #if canImport(CProjectM)
            guard let h = handle else { return false }
            return projectm_get_preset_locked(h)
            #else
            return false
            #endif
        }
        set {
            #if canImport(CProjectM)
            guard let h = handle else { return }
            projectm_set_preset_locked(h, newValue)
            #endif
        }
    }
    
    /// Preset duration in seconds (0 = no auto-switching)
    var presetDuration: Double {
        get {
            #if canImport(CProjectM)
            guard let h = handle else { return 30.0 }
            return projectm_get_preset_duration(h)
            #else
            return 30.0
            #endif
        }
        set {
            #if canImport(CProjectM)
            guard let h = handle else { return }
            projectm_set_preset_duration(h, newValue)
            #endif
        }
    }
    
    /// Soft cut (blend) duration in seconds
    var softCutDuration: Double {
        get {
            #if canImport(CProjectM)
            guard let h = handle else { return 3.0 }
            return projectm_get_soft_cut_duration(h)
            #else
            return 3.0
            #endif
        }
        set {
            #if canImport(CProjectM)
            guard let h = handle else { return }
            projectm_set_soft_cut_duration(h, newValue)
            #endif
        }
    }
    
    /// Whether hard cuts on beats are enabled
    var hardCutEnabled: Bool {
        get {
            #if canImport(CProjectM)
            guard let h = handle else { return true }
            return projectm_get_hard_cut_enabled(h)
            #else
            return true
            #endif
        }
        set {
            #if canImport(CProjectM)
            guard let h = handle else { return }
            projectm_set_hard_cut_enabled(h, newValue)
            #endif
        }
    }
    
    /// Beat sensitivity (0.0-2.0, default 1.0)
    var beatSensitivity: Float {
        get {
            #if canImport(CProjectM)
            guard let h = handle else { return 1.0 }
            return projectm_get_beat_sensitivity(h)
            #else
            return 1.0
            #endif
        }
        set {
            #if canImport(CProjectM)
            guard let h = handle else { return }
            projectm_set_beat_sensitivity(h, max(0, min(2.0, newValue)))
            #endif
        }
    }
    
    // MARK: - Initialization
    
    /// Creates a new projectM wrapper
    /// - Parameters:
    ///   - width: Initial viewport width
    ///   - height: Initial viewport height
    required init(width: Int = 512, height: Int = 512) {
        viewportWidth = width
        viewportHeight = height
        
        #if canImport(CProjectM)
        handle = projectm_create()
        isAvailable = handle != nil
        
        if let h = handle {
            projectm_set_window_size(h, size_t(viewportWidth), size_t(viewportHeight))
            
            // Set reasonable defaults
            // NOTE: Auto-switching is disabled by default to prevent race conditions
            // projectM's internal timer-based switching can cause crashes when it
            // switches presets while we're in the middle of rendering a frame.
            // Users can enable auto-switching via the UI if desired.
            projectm_set_preset_duration(h, 0.0)  // 0 = no auto-switching
            projectm_set_soft_cut_duration(h, 0.0)  // No blending (hard cuts only)
            projectm_set_hard_cut_enabled(h, false)  // No beat-triggered switches
            projectm_set_beat_sensitivity(h, 1.0)
            projectm_set_fps(h, 60)
            projectm_set_aspect_correction(h, true)
            projectm_set_preset_locked(h, true)  // Lock preset to prevent internal switching
            
            NSLog("ProjectMWrapper: Initialized projectM instance (auto-switching disabled for stability)")
        } else {
            NSLog("ProjectMWrapper: Failed to create projectM instance")
        }
        #else
        isAvailable = false
        NSLog("ProjectMWrapper: CProjectM module not available - libprojectM not installed")
        #endif
    }
    
    deinit {
        #if canImport(CProjectM)
        if let h = handle {
            projectm_destroy(h)
        }
        #endif
    }
    
    // MARK: - Viewport
    
    /// Updates the viewport size
    /// - Parameters:
    ///   - width: New width in pixels
    ///   - height: New height in pixels
    func setViewportSize(width: Int, height: Int) {
        #if canImport(CProjectM)
        guard let h = handle else { return }
        
        // Non-blocking lock attempt - skip if locked (during preset switch)
        guard renderLock.try() else { return }
        defer { renderLock.unlock() }
        
        // Check inside the lock to avoid race conditions
        guard width != viewportWidth || height != viewportHeight else { return }
        
        viewportWidth = width
        viewportHeight = height
        
        // Don't resize during preset loading or before preset is ready
        guard !_presetLoadInProgress && _presetLoaded && _framesAfterLoad >= framesRequiredAfterLoad else { return }
        
        projectm_set_window_size(h, size_t(width), size_t(height))
        #else
        viewportWidth = width
        viewportHeight = height
        #endif
    }
    
    // MARK: - Audio Input
    
    /// Adds mono PCM audio data for visualization
    /// - Parameters:
    ///   - samples: Array of float samples (-1.0 to 1.0)
    func addPCMMono(_ samples: [Float]) {
        #if canImport(CProjectM)
        guard let h = handle, !samples.isEmpty else { return }
        
        samples.withUnsafeBufferPointer { ptr in
            projectm_pcm_add_float(h, ptr.baseAddress, UInt32(samples.count), PROJECTM_MONO)
        }
        #endif
    }
    
    /// Adds stereo PCM audio data for visualization (interleaved LRLRLR)
    /// - Parameters:
    ///   - samples: Interleaved stereo samples
    ///   - sampleCount: Number of samples per channel
    func addPCMStereo(_ samples: [Float], sampleCount: Int) {
        #if canImport(CProjectM)
        guard let h = handle, !samples.isEmpty else { return }
        
        samples.withUnsafeBufferPointer { ptr in
            projectm_pcm_add_float(h, ptr.baseAddress, UInt32(sampleCount), PROJECTM_STEREO)
        }
        #endif
    }
    
    // MARK: - Rendering
    
    /// Whether a valid preset is currently loaded (thread-safe check)
    var hasValidPreset: Bool {
        renderLock.lock()
        defer { renderLock.unlock() }
        // A pending preset is queued but not yet loaded on the render thread — not ready yet
        guard _pendingPresetIndex == nil else { return false }
        let timeSinceChange = CFAbsoluteTimeGetCurrent() - _lastPresetChangeTime
        return presetCount > 0 && _currentPresetIndex >= 0 && _presetLoaded && !_presetLoadInProgress && _framesAfterLoad >= framesRequiredAfterLoad && timeSinceChange >= minTimeAfterPresetChange
    }
    
    /// Flag indicating a preset has been successfully loaded
    private var _presetLoaded: Bool = false
    
    /// Flag indicating a preset load is currently in progress
    private var _presetLoadInProgress: Bool = false
    
    /// Counter for frames rendered since last preset load
    /// Used to give projectM time to fully initialize internal state
    private var _framesAfterLoad: Int = 0
    
    /// Number of frames to wait after preset load before rendering
    /// This gives projectM time to fully initialize textures and shaders
    private let framesRequiredAfterLoad: Int = 10
    
    /// Timestamp of last preset change (for time-based delay)
    private var _lastPresetChangeTime: CFAbsoluteTime = 0
    
    /// Minimum time (seconds) to wait after preset change before rendering
    /// This ensures textures are fully initialized even if frame timing is inconsistent
    private let minTimeAfterPresetChange: CFAbsoluteTime = 0.25
    
    /// Minimum time (seconds) between preset changes (rate limiting)
    /// Prevents crashes from rapid clicking by ignoring requests that are too close together
    private let minTimeBetweenPresetChanges: CFAbsoluteTime = 0.35
    
    /// Flag indicating we're currently inside renderFrame
    /// Used to detect and prevent re-entry
    private var _isRendering: Bool = false
    
    /// Whether the first render frame of the current preset has completed without crashing.
    /// Reset to false each time a new preset is loaded. Used by the crash-detection sentinel.
    private var _firstRenderCompleted: Bool = false
    
    /// Renders a single frame of visualization.
    /// Must be called with a valid OpenGL context active (CVDisplayLink render thread).
    func renderFrame() {
        #if canImport(CProjectM)
        guard let h = handle else { return }
        
        // Non-blocking lock attempt - skip frame if locked (during preset switch)
        // This prevents the CVDisplayLink thread from blocking
        guard renderLock.try() else { return }
        defer { renderLock.unlock() }
        
        // Prevent re-entry (shouldn't happen, but defensive)
        guard !_isRendering else { return }
        _isRendering = true
        defer { _isRendering = false }
        
        // Execute any pending preset load now that we're on the render thread with
        // the OpenGL context current. libprojectM creates shaders and loads textures
        // during preset loading, so the GL context MUST be active on this thread.
        if let pendingIndex = _pendingPresetIndex {
            _pendingPresetIndex = nil
            
            let path = presetFiles[pendingIndex]
            let name = presetName(at: pendingIndex)
            NSLog("ProjectMWrapper: Loading preset %d on render thread: %@", pendingIndex, name)
            
            _presetLoadInProgress = true
            projectm_load_preset_file(h, path, false)  // Always use hard cut for safety
            
            // Reset all GL textures after each preset load. libprojectM can free the 3D
            // noise volume texture (sampler_noisevol_hq) when switching to presets that
            // don't reference it, leaving a dangling pointer that crashes the next preset
            // rendering call for any preset that does use it.
            projectm_reset_textures(h)
            
            _presetLoaded = true
            _presetLoadInProgress = false
            _firstRenderCompleted = false  // Arm the crash-detection sentinel for this preset
            
            NSLog("ProjectMWrapper: Preset loaded and textures reset on render thread")
            
            // Clear to black this frame and let the warmup period begin
            glViewport(0, 0, GLsizei(viewportWidth), GLsizei(viewportHeight))
            glClearColor(0.0, 0.0, 0.0, 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }
        
        // Don't render until a preset is fully loaded - projectM crashes without one
        guard _presetLoaded && !_presetLoadInProgress else { return }
        
        // Wait for BOTH frame count AND time delay after preset load
        // This gives projectM time to fully initialize shaders and textures
        // Time-based delay handles cases where frame timing is inconsistent
        let timeSinceChange = CFAbsoluteTimeGetCurrent() - _lastPresetChangeTime
        if _framesAfterLoad < framesRequiredAfterLoad || timeSinceChange < minTimeAfterPresetChange {
            _framesAfterLoad += 1
            // Clear to black while waiting
            glViewport(0, 0, GLsizei(viewportWidth), GLsizei(viewportHeight))
            glClearColor(0.0, 0.0, 0.0, 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }
        
        // Update viewport
        glViewport(0, 0, GLsizei(viewportWidth), GLsizei(viewportHeight))
        
        // Before the first render of each new preset, write a crash-detection sentinel
        // file. If projectm_opengl_render_frame crashes (SIGSEGV in a buggy shader),
        // the file persists on disk. On the next app launch, that preset is permanently
        // blacklisted and removed from the rotation so the crash never recurs.
        if !_firstRenderCompleted {
            Self.writeCrashSentinel(presetPath: presetFiles[_currentPresetIndex])
        }
        
        projectm_opengl_render_frame(h)
        
        // Render succeeded — clear the sentinel and mark first render done
        if !_firstRenderCompleted {
            Self.clearCrashSentinel()
            _firstRenderCompleted = true
        }
        #endif
    }
    
    // MARK: - Preset Management
    
    /// Scans a directory for .milk preset files
    /// - Parameters:
    ///   - path: Path to the preset directory
    ///   - recursive: Whether to search subdirectories
    func addPresetPath(_ path: String, recursive: Bool = true) {
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: recursive ? [] : [.skipsSubdirectoryDescendants]
        ) else {
            NSLog("ProjectMWrapper: Failed to enumerate directory: %@", path)
            return
        }
        
        var newPresets: [String] = []
        let blacklist = Self.crashedPresetPaths
        
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "milk" {
                let filePath = fileURL.path
                if blacklist.contains(filePath) {
                    NSLog("ProjectMWrapper: Skipping blacklisted preset (crashed on previous render): %@", fileURL.lastPathComponent)
                } else {
                    newPresets.append(filePath)
                }
            }
        }
        
        presetFiles.append(contentsOf: newPresets)
        NSLog("ProjectMWrapper: Found %d presets in %@", newPresets.count, path)
    }
    
    /// Sets the texture search paths
    /// - Parameter paths: Array of directory paths containing textures
    func setTexturePaths(_ paths: [String]) {
        #if canImport(CProjectM)
        guard let h = handle else { return }
        
        var cStrings = paths.map { strdup($0) }
        defer {
            for ptr in cStrings {
                free(ptr)
            }
        }
        
        cStrings.withUnsafeMutableBufferPointer { buffer in
            let ptrs = buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { $0 }
            projectm_set_texture_search_paths(h, ptrs, paths.count)
        }
        #endif
    }
    
    /// Loads all presets from added paths
    func loadPresets() {
        // Sort presets alphabetically
        presetFiles.sort()
        
        NSLog("ProjectMWrapper: Loaded %d presets total", presetFiles.count)
        
        // Load preferred startup preset if configured; otherwise fall back to first preset.
        if !presetFiles.isEmpty {
            let startupIndex = preferredDefaultPresetIndex() ?? 0
            _currentPresetIndex = startupIndex
            loadPreset(at: startupIndex, smoothTransition: false)
        }
    }
    
    /// Gets the name of a preset at the given index (filename without extension)
    /// - Parameter index: Preset index
    /// - Returns: Preset name, or empty string if invalid
    func presetName(at index: Int) -> String {
        guard index >= 0 && index < presetFiles.count else { return "" }
        
        let url = URL(fileURLWithPath: presetFiles[index])
        return url.deletingPathExtension().lastPathComponent
    }
    
    /// Persists the current preset as the startup default.
    func setCurrentPresetAsDefault() {
        guard _currentPresetIndex >= 0 && _currentPresetIndex < presetFiles.count else { return }
        
        let path = presetFiles[_currentPresetIndex]
        let name = presetName(at: _currentPresetIndex)
        Self.defaultPresetPath = path
        Self.defaultPresetName = name
        NSLog("ProjectMWrapper: Set default preset to %@", name)
    }
    
    /// Returns preferred preset index for startup if a saved default can be resolved.
    private func preferredDefaultPresetIndex() -> Int? {
        if let defaultPath = Self.defaultPresetPath,
           let index = presetFiles.firstIndex(of: defaultPath) {
            return index
        }
        
        if let defaultName = Self.defaultPresetName,
           !defaultName.isEmpty,
           let index = presetFiles.firstIndex(where: { filePath in
               let name = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
               return name.caseInsensitiveCompare(defaultName) == .orderedSame
           }) {
            return index
        }
        
        return nil
    }
    
    /// Queues a preset to load by index.
    ///
    /// The actual `projectm_load_preset_file` call is deferred to the CVDisplayLink
    /// render thread (via `renderFrame()`), where the OpenGL context is always current.
    /// Calling libprojectM GL functions from the main thread without an active context
    /// corrupts GL state and causes crashes after a few preset changes.
    ///
    /// - Parameters:
    ///   - index: Preset index
    ///   - smoothTransition: Ignored (always hard-cut for safety); kept for API compatibility
    func loadPreset(at index: Int, smoothTransition: Bool = true) {
        guard index >= 0 && index < presetFiles.count else {
            NSLog("ProjectMWrapper: Invalid preset index %d (count: %d)", index, presetFiles.count)
            return
        }
        
        #if canImport(CProjectM)
        guard handle != nil else {
            NSLog("ProjectMWrapper: No projectM handle available")
            return
        }
        
        // Rate limiting: ignore preset changes that are too close together
        let timeSinceLastChange = CFAbsoluteTimeGetCurrent() - _lastPresetChangeTime
        if timeSinceLastChange < minTimeBetweenPresetChanges && _presetLoaded {
            return
        }
        
        let name = presetName(at: index)
        NSLog("ProjectMWrapper: Queuing preset %d: %@ (will load on render thread)", index, name)
        
        renderLock.lock()
        
        // Double-check rate limiting inside the lock (in case of concurrent calls)
        let timeSinceLastChangeLocked = CFAbsoluteTimeGetCurrent() - _lastPresetChangeTime
        if timeSinceLastChangeLocked < minTimeBetweenPresetChanges && _presetLoaded {
            renderLock.unlock()
            return
        }
        
        // Queue the preset for loading on the render thread (where GL context is current).
        // Reset rendering state so frames are suppressed until the load completes.
        _pendingPresetIndex = index
        _presetLoaded = false
        _presetLoadInProgress = false
        _framesAfterLoad = 0
        _lastPresetChangeTime = CFAbsoluteTimeGetCurrent()
        
        // Optimistic update so UI (preset name, index) reflects the selection immediately
        _currentPresetIndex = index
        
        renderLock.unlock()
        
        postPresetChangeNotification()
        #endif
    }
    
    /// Selects a preset by index
    /// - Parameters:
    ///   - index: Preset index
    ///   - hardCut: If true, switch immediately; if false, blend smoothly
    func selectPreset(at index: Int, hardCut: Bool = false) {
        loadPreset(at: index, smoothTransition: !hardCut)
    }
    
    /// Selects the next preset in the playlist
    /// - Parameter hardCut: If true, switch immediately; if false, blend smoothly
    func nextPreset(hardCut: Bool = false) {
        guard !presetFiles.isEmpty else { return }
        
        let newIndex = (_currentPresetIndex + 1) % presetFiles.count
        loadPreset(at: newIndex, smoothTransition: !hardCut)
    }
    
    /// Selects the previous preset in the playlist
    /// - Parameter hardCut: If true, switch immediately; if false, blend smoothly
    func previousPreset(hardCut: Bool = false) {
        guard !presetFiles.isEmpty else { return }
        
        let newIndex = (_currentPresetIndex - 1 + presetFiles.count) % presetFiles.count
        loadPreset(at: newIndex, smoothTransition: !hardCut)
    }
    
    /// Selects a random preset
    /// - Parameter hardCut: If true, switch immediately; if false, blend smoothly
    func randomPreset(hardCut: Bool = false) {
        guard presetFiles.count > 1 else { return }
        
        var newIndex: Int
        repeat {
            newIndex = Int.random(in: 0..<presetFiles.count)
        } while newIndex == _currentPresetIndex
        
        loadPreset(at: newIndex, smoothTransition: !hardCut)
    }
    
    // MARK: - Private Helpers
    
    private func postPresetChangeNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.presetDidChangeNotification,
                object: self,
                userInfo: [
                    "index": self._currentPresetIndex,
                    "name": self.currentPresetName
                ]
            )
        }
    }
}

// MARK: - Custom Presets Folder

extension ProjectMWrapper {
    
    /// UserDefaults key for custom presets folder
    private static let customPresetsFolderKey = "customPresetsFolder"
    
    /// UserDefaults key for default preset path selected by the user.
    fileprivate static let defaultPresetPathKey = "projectMDefaultPresetPath"
    
    /// UserDefaults key for default preset display name as fallback when path changes.
    fileprivate static let defaultPresetNameKey = "projectMDefaultPresetName"
    
    /// Gets or sets the custom presets folder path
    static var customPresetsFolder: String? {
        get {
            return UserDefaults.standard.string(forKey: customPresetsFolderKey)
        }
        set {
            if let path = newValue {
                UserDefaults.standard.set(path, forKey: customPresetsFolderKey)
            } else {
                UserDefaults.standard.removeObject(forKey: customPresetsFolderKey)
            }
        }
    }
    
    /// Full path of the user-selected startup default preset.
    static var defaultPresetPath: String? {
        get {
            return UserDefaults.standard.string(forKey: defaultPresetPathKey)
        }
        set {
            if let path = newValue, !path.isEmpty {
                UserDefaults.standard.set(path, forKey: defaultPresetPathKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultPresetPathKey)
            }
        }
    }
    
    /// Display name of the user-selected startup default preset.
    /// Used when the absolute preset path changes between launches.
    static var defaultPresetName: String? {
        get {
            return UserDefaults.standard.string(forKey: defaultPresetNameKey)
        }
        set {
            if let name = newValue, !name.isEmpty {
                UserDefaults.standard.set(name, forKey: defaultPresetNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultPresetNameKey)
            }
        }
    }
    
    /// Whether a custom presets folder is configured
    static var hasCustomPresetsFolder: Bool {
        if let folder = customPresetsFolder {
            return FileManager.default.fileExists(atPath: folder)
        }
        return false
    }
    
    /// Gets preset counts without needing an instance (for menu display)
    /// Returns (bundledCount, customCount)
    static var staticPresetCounts: (bundled: Int, custom: Int) {
        var bundledCount = 0
        var customCount = 0
        
        // Count bundled presets
        if let bundledPath = bundledPresetsPath {
            bundledCount = countMilkFiles(in: bundledPath)
        }
        
        // Count custom presets
        if let customPath = customPresetsFolder,
           FileManager.default.fileExists(atPath: customPath) {
            customCount = countMilkFiles(in: customPath)
        }
        
        return (bundledCount, customCount)
    }
    
    /// Counts .milk files in a directory recursively
    private static func countMilkFiles(in path: String) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        
        var count = 0
        while let file = enumerator.nextObject() as? String {
            if file.lowercased().hasSuffix(".milk") {
                count += 1
            }
        }
        return count
    }
    
    /// Adds presets from a custom folder
    /// - Parameter path: Path to the folder containing .milk files
    /// - Returns: Number of presets found
    @discardableResult
    func addCustomPresetPath(_ path: String) -> Int {
        let countBefore = presetFiles.count
        addPresetPath(path, recursive: true)
        let countAfter = presetFiles.count
        let added = countAfter - countBefore
        NSLog("ProjectMWrapper: Added %d custom presets from %@", added, path)
        return added
    }
    
    /// Clears all presets and reloads from configured paths
    func reloadAllPresets() {
        // Check for a previous crash sentinel before rebuilding the list
        Self.checkAndHandlePreviousCrash()
        
        // Clear existing presets
        presetFiles.removeAll()
        _currentPresetIndex = 0
        _presetLoaded = false
        _framesAfterLoad = 0
        
        // Reload bundled presets
        if let bundledPath = Self.bundledPresetsPath {
            addPresetPath(bundledPath, recursive: true)
        }
        
        // Add custom presets folder if configured
        if let customPath = Self.customPresetsFolder,
           FileManager.default.fileExists(atPath: customPath) {
            addPresetPath(customPath, recursive: true)
        }
        
        // Load presets (sorts and loads first preset)
        loadPresets()
        
        NSLog("ProjectMWrapper: Reloaded %d total presets", presetCount)
    }
    
    /// Gets information about the current presets configuration
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        var bundledCount = 0
        var customCount = 0
        
        // Count bundled presets
        if let bundledPath = Self.bundledPresetsPath {
            for file in presetFiles {
                if file.hasPrefix(bundledPath) {
                    bundledCount += 1
                }
            }
        }
        
        // Count custom presets
        if let customPath = Self.customPresetsFolder {
            for file in presetFiles {
                if file.hasPrefix(customPath) {
                    customCount += 1
                }
            }
        }
        
        return (bundledCount, customCount, Self.customPresetsFolder)
    }
}

// MARK: - Bundle Paths

extension ProjectMWrapper {
    
    /// Gets the path to the bundled presets directory
    static var bundledPresetsPath: String? {
        // For SPM, resources are in a separate bundle named NullPlayer_NullPlayer.bundle
        // Look for it next to the executable
        let executablePath = Bundle.main.executablePath ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        
        // SPM resource bundle path
        let spmBundlePath = (executableDir as NSString).appendingPathComponent("NullPlayer_NullPlayer.bundle/Resources/Presets")
        if FileManager.default.fileExists(atPath: spmBundlePath) {
            NSLog("ProjectMWrapper: Found presets at SPM bundle path: %@", spmBundlePath)
            return spmBundlePath
        }
        
        // Try standard app bundle path
        if let resourcePath = Bundle.main.resourcePath {
            let presetsPath = (resourcePath as NSString).appendingPathComponent("Presets")
            if FileManager.default.fileExists(atPath: presetsPath) {
                NSLog("ProjectMWrapper: Found presets at bundle resource path: %@", presetsPath)
                return presetsPath
            }
            
            // Also try Resources/Presets
            let altPresetsPath = (resourcePath as NSString).appendingPathComponent("Resources/Presets")
            if FileManager.default.fileExists(atPath: altPresetsPath) {
                NSLog("ProjectMWrapper: Found presets at alt bundle path: %@", altPresetsPath)
                return altPresetsPath
            }
        }
        
        // Development path - look relative to executable for source directory
        #if DEBUG
        let devPath = (executableDir as NSString).appendingPathComponent("../../../Sources/NullPlayer/Resources/Presets")
        let normalizedDevPath = (devPath as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: normalizedDevPath) {
            NSLog("ProjectMWrapper: Found presets at dev path: %@", normalizedDevPath)
            return normalizedDevPath
        }
        #endif
        
        NSLog("ProjectMWrapper: Could not find presets directory")
        return nil
    }
    
    /// Gets the path to the bundled textures directory
    static var bundledTexturesPath: String? {
        let executablePath = Bundle.main.executablePath ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        
        // SPM resource bundle path
        let spmBundlePath = (executableDir as NSString).appendingPathComponent("NullPlayer_NullPlayer.bundle/Resources/Textures")
        if FileManager.default.fileExists(atPath: spmBundlePath) {
            return spmBundlePath
        }
        
        if let resourcePath = Bundle.main.resourcePath {
            let texturesPath = (resourcePath as NSString).appendingPathComponent("Textures")
            if FileManager.default.fileExists(atPath: texturesPath) {
                return texturesPath
            }
            
            let altTexturesPath = (resourcePath as NSString).appendingPathComponent("Resources/Textures")
            if FileManager.default.fileExists(atPath: altTexturesPath) {
                return altTexturesPath
            }
        }
        
        #if DEBUG
        let devPath = (executableDir as NSString).appendingPathComponent("../../../Sources/NullPlayer/Resources/Textures")
        let normalizedDevPath = (devPath as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: normalizedDevPath) {
            return normalizedDevPath
        }
        #endif
        
        return nil
    }
    
    /// Configures the wrapper with bundled presets and textures
    func loadBundledPresets() {
        // Check if a previous run crashed during preset rendering and blacklist that preset.
        // Must happen before addPresetPath so the blacklist is applied when scanning files.
        Self.checkAndHandlePreviousCrash()
        
        // Add texture path first (presets may reference textures)
        var texturePaths: [String] = []
        if let texturesPath = Self.bundledTexturesPath {
            texturePaths.append(texturesPath)
            NSLog("ProjectMWrapper: Added bundled texture path: %@", texturesPath)
        }
        
        // Add custom textures path if custom presets folder is configured
        if let customPath = Self.customPresetsFolder {
            let customTexturesPath = (customPath as NSString).appendingPathComponent("Textures")
            if FileManager.default.fileExists(atPath: customTexturesPath) {
                texturePaths.append(customTexturesPath)
                NSLog("ProjectMWrapper: Added custom texture path: %@", customTexturesPath)
            }
        }
        
        if !texturePaths.isEmpty {
            setTexturePaths(texturePaths)
        }
        
        // Add bundled preset path
        if let presetsPath = Self.bundledPresetsPath {
            addPresetPath(presetsPath, recursive: true)
            NSLog("ProjectMWrapper: Added bundled preset path: %@", presetsPath)
        } else {
            NSLog("ProjectMWrapper: WARNING - No bundled presets directory found!")
        }
        
        // Add custom presets folder if configured
        if let customPath = Self.customPresetsFolder,
           FileManager.default.fileExists(atPath: customPath) {
            addPresetPath(customPath, recursive: true)
            NSLog("ProjectMWrapper: Added custom preset path: %@", customPath)
        }
        
        // Load the presets (this will load the first preset)
        loadPresets()
        
        NSLog("ProjectMWrapper: Loaded %d presets total", presetCount)
        
        if presetCount == 0 {
            NSLog("ProjectMWrapper: No presets available - visualization will show idle screen")
        }
        // Note: We no longer immediately call randomPreset() here.
        // The first preset loaded by loadPresets() will be used initially.
        // This avoids a race condition where rapid preset switching during
        // initialization could leave projectM in an inconsistent state.
        // Users can switch presets manually or auto-switching will happen
        // based on the preset duration setting.
    }
}

// MARK: - Crash Detection

extension ProjectMWrapper {
    
    /// Path to the crash-detection sentinel file.
    ///
    /// This file is written immediately before the first `projectm_opengl_render_frame`
    /// call for a new preset, and deleted immediately after it succeeds. If the app
    /// crashes during rendering (SIGSEGV/SIGBUS inside a buggy libprojectM shader),
    /// the file persists. On the next launch, the offending preset is permanently
    /// blacklisted and excluded from the rotation.
    static var crashSentinelPath: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NullPlayer", isDirectory: true).path
        return (dir as NSString).appendingPathComponent("projectm_crash_sentinel.txt")
    }
    
    /// UserDefaults key for the set of preset file paths that have crashed on rendering.
    private static let crashedPresetsKey = "projectMCrashedPresets"
    
    /// The set of preset file paths that have previously crashed libprojectM on rendering.
    /// These are excluded when building the preset list.
    static var crashedPresetPaths: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: crashedPresetsKey) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: crashedPresetsKey)
        }
    }
    
    /// Writes the crash-detection sentinel file with the given preset path.
    /// Must be called just before `projectm_opengl_render_frame`.
    static func writeCrashSentinel(presetPath: String) {
        let sentinelDir = (crashSentinelPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: sentinelDir,
                                                  withIntermediateDirectories: true)
        // Write atomically so the file is either fully written or not present
        try? presetPath.write(toFile: crashSentinelPath, atomically: true, encoding: .utf8)
    }
    
    /// Removes the crash-detection sentinel file after a successful render.
    static func clearCrashSentinel() {
        try? FileManager.default.removeItem(atPath: crashSentinelPath)
    }
    
    /// Checks whether a previous run crashed during preset rendering.
    ///
    /// If a sentinel file exists, the preset it names crashed libprojectM. That preset
    /// is added to the persistent blacklist and the sentinel is removed.
    /// Call this once at startup (before building the preset list).
    static func checkAndHandlePreviousCrash() {
        guard let crashedPath = try? String(contentsOfFile: crashSentinelPath, encoding: .utf8),
              !crashedPath.isEmpty else { return }
        
        // Remove the sentinel so we don't re-process it on the next launch
        clearCrashSentinel()
        
        var crashed = crashedPresetPaths
        if !crashed.contains(crashedPath) {
            crashed.insert(crashedPath)
            crashedPresetPaths = crashed
            NSLog("ProjectMWrapper: Blacklisted preset that crashed libprojectM on render: %@",
                  (crashedPath as NSString).lastPathComponent)
        }
    }
    
    /// Clears the entire preset blacklist (for troubleshooting / user-facing "reset" action).
    static func clearCrashedPresetsBlacklist() {
        UserDefaults.standard.removeObject(forKey: crashedPresetsKey)
        clearCrashSentinel()
        NSLog("ProjectMWrapper: Cleared preset crash blacklist")
    }
}
