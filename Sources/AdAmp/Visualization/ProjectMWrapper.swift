import Foundation
import OpenGL.GL3

// Import the C projectM library when available
#if canImport(CProjectM)
import CProjectM
#endif

/// Swift wrapper around libprojectM v4 for Milkdrop visualization
///
/// This class manages a projectM instance for rendering Milkdrop presets
/// with real-time audio visualization.
class ProjectMWrapper {
    
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
    
    /// Current viewport dimensions
    private var viewportWidth: Int = 0
    private var viewportHeight: Int = 0
    
    /// List of preset file paths
    private var presetFiles: [String] = []
    
    /// Current preset index
    private var _currentPresetIndex: Int = 0
    
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
    init(width: Int = 512, height: Int = 512) {
        viewportWidth = width
        viewportHeight = height
        
        #if canImport(CProjectM)
        handle = projectm_create()
        isAvailable = handle != nil
        
        if let h = handle {
            projectm_set_window_size(h, size_t(viewportWidth), size_t(viewportHeight))
            
            // Set reasonable defaults
            projectm_set_preset_duration(h, 30.0)  // 30 seconds per preset
            projectm_set_soft_cut_duration(h, 3.0)  // 3 second blend
            projectm_set_hard_cut_enabled(h, true)
            projectm_set_beat_sensitivity(h, 1.0)
            projectm_set_fps(h, 60)
            projectm_set_aspect_correction(h, true)
            
            NSLog("ProjectMWrapper: Initialized projectM instance")
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
        
        // Lock to ensure thread safety and atomic update of dimensions
        renderLock.lock()
        defer { renderLock.unlock() }
        
        // Check inside the lock to avoid race conditions
        guard width != viewportWidth || height != viewportHeight else { return }
        
        viewportWidth = width
        viewportHeight = height
        
        // Don't resize during preset loading - projectM may crash
        guard !_presetLoadInProgress else { return }
        
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
        return presetCount > 0 && _currentPresetIndex >= 0 && _presetLoaded && !_presetLoadInProgress
    }
    
    /// Flag indicating a preset has been successfully loaded
    private var _presetLoaded: Bool = false
    
    /// Flag indicating a preset load is currently in progress
    private var _presetLoadInProgress: Bool = false
    
    /// Renders a single frame of visualization
    /// Must be called with a valid OpenGL context active
    func renderFrame() {
        #if canImport(CProjectM)
        guard let h = handle else { return }
        
        // Lock to prevent concurrent preset switching during render
        renderLock.lock()
        defer { renderLock.unlock() }
        
        // Don't render until a preset is fully loaded - projectM crashes without one
        // Also skip if a preset load is in progress
        guard _presetLoaded && !_presetLoadInProgress else { return }
        
        // Update viewport
        glViewport(0, 0, GLsizei(viewportWidth), GLsizei(viewportHeight))
        
        // Render the frame
        projectm_opengl_render_frame(h)
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
        
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "milk" {
                newPresets.append(fileURL.path)
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
        
        // Load the first preset if available
        if !presetFiles.isEmpty {
            _currentPresetIndex = 0
            loadPreset(at: 0, smoothTransition: false)
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
    
    /// Loads a preset by index
    /// - Parameters:
    ///   - index: Preset index
    ///   - smoothTransition: If true, blend smoothly; if false, switch immediately
    func loadPreset(at index: Int, smoothTransition: Bool = true) {
        guard index >= 0 && index < presetFiles.count else {
            NSLog("ProjectMWrapper: Invalid preset index %d (count: %d)", index, presetFiles.count)
            return
        }
        
        #if canImport(CProjectM)
        guard let h = handle else {
            NSLog("ProjectMWrapper: No projectM handle available")
            return
        }
        
        let path = presetFiles[index]
        let name = presetName(at: index)
        
        NSLog("ProjectMWrapper: Loading preset %d: %@ from %@", index, name, path)
        
        // Lock to prevent concurrent rendering during preset switch
        renderLock.lock()
        
        // Mark that we're loading - this prevents rendering during the load
        _presetLoadInProgress = true
        _presetLoaded = false
        
        // Load the preset file
        projectm_load_preset_file(h, path, smoothTransition)
        
        // Update state after load completes
        _currentPresetIndex = index
        _presetLoaded = true
        _presetLoadInProgress = false
        
        renderLock.unlock()
        
        NSLog("ProjectMWrapper: Preset loaded successfully")
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
    
    /// Whether a custom presets folder is configured
    static var hasCustomPresetsFolder: Bool {
        if let folder = customPresetsFolder {
            return FileManager.default.fileExists(atPath: folder)
        }
        return false
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
        // Clear existing presets
        presetFiles.removeAll()
        _currentPresetIndex = 0
        _presetLoaded = false
        
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
        // For SPM, resources are in a separate bundle named AdAmp_AdAmp.bundle
        // Look for it next to the executable
        let executablePath = Bundle.main.executablePath ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        
        // SPM resource bundle path
        let spmBundlePath = (executableDir as NSString).appendingPathComponent("AdAmp_AdAmp.bundle/Resources/Presets")
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
        let devPath = (executableDir as NSString).appendingPathComponent("../../../Sources/AdAmp/Resources/Presets")
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
        let spmBundlePath = (executableDir as NSString).appendingPathComponent("AdAmp_AdAmp.bundle/Resources/Textures")
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
        let devPath = (executableDir as NSString).appendingPathComponent("../../../Sources/AdAmp/Resources/Textures")
        let normalizedDevPath = (devPath as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: normalizedDevPath) {
            return normalizedDevPath
        }
        #endif
        
        return nil
    }
    
    /// Configures the wrapper with bundled presets and textures
    func loadBundledPresets() {
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
