import AppKit
import OpenGL.GL3
import CoreVideo
import Accelerate
import os

// Silence OpenGL deprecation warnings (macOS still supports OpenGL 4.1)
// We use OpenGL for visualization as Metal doesn't have the same ecosystem of presets

/// OpenGL view for real-time audio visualization
/// Uses CVDisplayLink for 60fps updates
/// Supports projectM for Milkdrop preset rendering with fallback to built-in visualizations
class VisualizationGLView: NSOpenGLView {
    
    // MARK: - Properties

    /// CVDisplayLink for vsync'd rendering
    private var displayLink: CVDisplayLink?

    /// Whether rendering is currently active
    private(set) var isRendering = false

    /// Current visualization engine
    private var engine: VisualizationEngine?

    /// Current engine type
    private(set) var currentEngineType: VisualizationType = .projectM

    /// Whether projectM is available and initialized (backward compatibility)
    var isProjectMAvailable: Bool {
        guard case .projectM = currentEngineType else { return false }
        return (engine as? ProjectMWrapper)?.isAvailable ?? false
    }
    
    
    /// Whether audio is currently playing (affects visualization behavior)
    private var isAudioActive = false
    
    /// Normal beat sensitivity (restored when audio starts)
    private let normalBeatSensitivity: Float = 1.0
    
    /// Idle beat sensitivity (used when audio is not playing for calmer visualization)
    private let idleBeatSensitivity: Float = 0.2
    
    /// Local copy of PCM data for thread-safe access
    /// Using nonisolated(unsafe) because we manually manage thread safety via dataLock
    private nonisolated(unsafe) var localPCM: [Float] = Array(repeating: 0, count: 512)

    /// Local copy of spectrum data for thread-safe access (75 bands)
    /// Using nonisolated(unsafe) because we manually manage thread safety via dataLock
    private nonisolated(unsafe) var localSpectrum: [Float] = Array(repeating: 0, count: 75)

    private let dataLock = OSAllocatedUnfairLock()  // Faster than NSLock for short critical sections
    
    // MARK: - Initialization
    
    override init?(frame frameRect: NSRect, pixelFormat format: NSOpenGLPixelFormat?) {
        // Create pixel format for OpenGL 4.1 Core Profile
        // projectM requires OpenGL 3.3+ Core Profile
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            UInt32(NSOpenGLPFAStencilSize), 8,  // Required by projectM
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]
        
        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attrs) else {
            NSLog("VisualizationGLView: Failed to create OpenGL pixel format")
            super.init(frame: frameRect, pixelFormat: nil)
            return nil
        }
        
        super.init(frame: frameRect, pixelFormat: pixelFormat)
        
        wantsBestResolutionOpenGLSurface = true

        // Load saved engine type preference (defaults to ProjectM)
        if let savedType = UserDefaults.standard.string(forKey: "visualizationEngineType"),
           let type = VisualizationType(rawValue: savedType) {
            currentEngineType = type
        }

        // Set up OpenGL context
        openGLContext?.makeCurrentContext()
        setupOpenGL()
        setupEngine()
        setupDisplayLink()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        // Load saved engine type preference (defaults to ProjectM)
        if let savedType = UserDefaults.standard.string(forKey: "visualizationEngineType"),
           let type = VisualizationType(rawValue: savedType) {
            currentEngineType = type
        }

        setupOpenGL()
        setupEngine()
        setupDisplayLink()
    }

    deinit {
        stopRendering()
        cleanupOpenGL()
        engine?.cleanup()
        engine = nil
    }
    
    // MARK: - OpenGL Setup
    
    private func setupOpenGL() {
        guard let context = openGLContext else { return }
        context.makeCurrentContext()
        
        // Enable vsync
        var swapInterval: GLint = 1
        context.setValues(&swapInterval, for: .swapInterval)
        
        // Set up basic OpenGL state
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))
    }
    
    private func cleanupOpenGL() {
        // Nothing to clean up - projectM manages its own resources
    }
    
    // MARK: - Engine Setup

    /// Flag to defer engine initialization until first render (for correct GL context)
    private var engineNeedsSetup = true

    private func setupEngine() {
        // Mark that we want to initialize the engine - actual setup will happen on first render
        // This ensures the OpenGL context is properly initialized on the render thread
        engineNeedsSetup = true
        NSLog("VisualizationGLView: Engine setup deferred to render thread (type: %@)", currentEngineType.displayName)
    }

    /// Factory method to create visualization engine instances
    /// - Parameters:
    ///   - type: The type of engine to create
    ///   - width: Viewport width in pixels
    ///   - height: Viewport height in pixels
    /// - Returns: A new engine instance, or nil if creation failed
    private func createEngine(type: VisualizationType, width: Int, height: Int) -> VisualizationEngine? {
        switch type {
        case .projectM:
            let pm = ProjectMWrapper(width: width, height: height)
            if pm.isAvailable {
                // Load bundled presets
                pm.loadBundledPresets()

                // Start with idle beat sensitivity (calmer until audio plays)
                pm.beatSensitivity = idleBeatSensitivity

                if pm.presetCount > 0 {
                    NSLog("VisualizationGLView: ProjectM initialized with %d presets, idle beat sensitivity = %.2f", pm.presetCount, idleBeatSensitivity)
                } else {
                    NSLog("VisualizationGLView: ProjectM available but no presets found")
                }
                return pm
            } else {
                NSLog("VisualizationGLView: ProjectM not available")
                return nil
            }

        case .tocSpectrum:
            let renderer = TOCSpectrumRenderer(width: width, height: height)
            if renderer.isAvailable {
                NSLog("VisualizationGLView: TOC Spectrum initialized successfully")
                return renderer
            } else {
                NSLog("VisualizationGLView: TOC Spectrum initialization failed")
                return nil
            }
        }
    }

    /// Actually initialize the engine - must be called on render thread with GL context current
    private func initializeEngineOnRenderThread() {
        guard engineNeedsSetup else { return }
        engineNeedsSetup = false

        // Get initial viewport size
        let backingBounds = convertToBacking(bounds)
        let width = Int(backingBounds.width)
        let height = Int(backingBounds.height)

        NSLog("VisualizationGLView: Setting up %@ with viewport %dx%d on render thread", currentEngineType.displayName, width, height)

        // Create engine using factory
        engine = createEngine(type: currentEngineType, width: width, height: height)

        if engine != nil {
            NSLog("VisualizationGLView: %@ initialized successfully", currentEngineType.displayName)
        } else {
            NSLog("VisualizationGLView: %@ initialization failed", currentEngineType.displayName)
        }
    }

    /// Switch to a different visualization engine
    /// - Parameter type: The engine type to switch to
    ///
    /// This method can be called from any thread - it will defer the actual switch
    /// to the render thread to ensure proper OpenGL context.
    func switchEngine(to type: VisualizationType) {
        // Skip if already using this engine type
        guard type != currentEngineType else {
            NSLog("VisualizationGLView: Already using %@", type.displayName)
            return
        }

        NSLog("VisualizationGLView: Switching engine from %@ to %@", currentEngineType.displayName, type.displayName)

        // Update the engine type
        currentEngineType = type

        // Save preference
        UserDefaults.standard.set(type.rawValue, forKey: "visualizationEngineType")

        // Mark engine for reinitialization on next render
        engineNeedsSetup = true

        // Clean up old engine (will be replaced on next render)
        engine?.cleanup()
        engine = nil

        NSLog("VisualizationGLView: Engine switch queued, will initialize on next render")
    }

    // MARK: - Display Link
    
    private func setupDisplayLink() {
        // Create display link
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        guard let displayLink = displayLink else {
            NSLog("VisualizationGLView: Failed to create CVDisplayLink")
            return
        }
        
        // Set the callback
        let callback: CVDisplayLinkOutputCallback = { displayLink, inNow, inOutputTime, flagsIn, flagsOut, context in
            let view = Unmanaged<VisualizationGLView>.fromOpaque(context!).takeUnretainedValue()
            view.renderFrame()
            return kCVReturnSuccess
        }
        
        CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())
        
        // Set the display link to the display of the OpenGL context
        if let cglContext = openGLContext?.cglContextObj,
           let cglPixelFormat = pixelFormat?.cglPixelFormatObj {
            CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink, cglContext, cglPixelFormat)
        }
    }
    
    // MARK: - Rendering Control
    
    func startRendering() {
        guard let displayLink = displayLink, !isRendering else { return }
        
        CVDisplayLinkStart(displayLink)
        isRendering = true
        NSLog("VisualizationGLView: Started rendering")
    }
    
    func stopRendering() {
        guard let displayLink = displayLink, isRendering else { return }
        
        CVDisplayLinkStop(displayLink)
        isRendering = false
        NSLog("VisualizationGLView: Stopped rendering")
    }
    
    // MARK: - Data Update
    
    /// Update PCM data (called from audio thread for low latency)
    func updatePCM(_ data: [Float]) {
        dataLock.withLock {
            for i in 0..<min(data.count, localPCM.count) {
                localPCM[i] = data[i]
            }
        }
    }

    /// Update spectrum data (called from audio thread for low latency)
    func updateSpectrum(_ data: [Float]) {
        dataLock.withLock {
            for i in 0..<min(data.count, localSpectrum.count) {
                localSpectrum[i] = data[i]
            }
        }
    }

    /// Set whether audio is actively playing
    /// When false, visualization becomes calmer with reduced beat sensitivity
    func setAudioActive(_ active: Bool) {
        guard active != isAudioActive else { return }
        isAudioActive = active

        if active {
            // Audio started playing - restore normal beat sensitivity (ProjectM only)
            if let pm = engine as? ProjectMWrapper {
                pm.beatSensitivity = normalBeatSensitivity
                NSLog("VisualizationGLView: Audio active, beat sensitivity = %.2f", normalBeatSensitivity)
            }
        } else {
            // Audio stopped - reduce beat sensitivity for calmer visualization (ProjectM only)
            if let pm = engine as? ProjectMWrapper {
                pm.beatSensitivity = idleBeatSensitivity
                NSLog("VisualizationGLView: Audio idle, beat sensitivity = %.2f", idleBeatSensitivity)
            }
        }
    }
    
    // MARK: - Frame Rendering
    
    private func renderFrame() {
        guard let context = openGLContext else { return }

        // Make context current on this thread
        context.makeCurrentContext()

        // Lock focus
        CGLLockContext(context.cglContextObj!)
        defer { CGLUnlockContext(context.cglContextObj!) }

        // Initialize engine on first render (ensures correct GL context)
        if engineNeedsSetup {
            initializeEngineOnRenderThread()
        }

        // Get data snapshots (thread-safe)
        let (pcm, spectrum) = dataLock.withLock { (localPCM, localSpectrum) }

        // Get viewport dimensions
        let backingBounds = convertToBacking(bounds)
        let viewportWidth = Int(backingBounds.width)
        let viewportHeight = Int(backingBounds.height)

        // Render with the current engine
        if let eng = engine, eng.isAvailable {
            renderEngine(engine: eng, pcm: pcm, spectrum: spectrum, width: viewportWidth, height: viewportHeight)
        } else {
            // Engine not available - just clear to black
            glViewport(0, 0, GLsizei(viewportWidth), GLsizei(viewportHeight))
            glClearColor(0.0, 0.0, 0.0, 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }

        // Swap buffers
        context.flushBuffer()
    }

    /// Render a frame using the current visualization engine
    private func renderEngine(engine: VisualizationEngine, pcm: [Float], spectrum: [Float], width: Int, height: Int) {
        // Update viewport size if changed
        engine.setViewportSize(width: width, height: height)

        // Feed PCM data to engine
        engine.addPCMMono(pcm)

        // For TOC Spectrum, also provide spectrum data
        if let tocRenderer = engine as? TOCSpectrumRenderer {
            tocRenderer.updateSpectrum(spectrum)
        }

        // Render the frame
        engine.renderFrame()
    }

    /// Whether projectM has valid presets loaded (backward compatibility)
    var hasProjectMPresets: Bool {
        guard let pm = engine as? ProjectMWrapper else { return false }
        return pm.hasValidPreset
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil {
            // Start rendering when added to a window
            startRendering()
        } else {
            // Stop rendering when removed from window
            stopRendering()
        }
    }
    
    override func viewDidHide() {
        super.viewDidHide()
        stopRendering()
    }
    
    override func viewDidUnhide() {
        super.viewDidUnhide()
        if window != nil {
            startRendering()
        }
    }
    
    override func reshape() {
        super.reshape()

        // Update viewport on resize
        openGLContext?.makeCurrentContext()
        openGLContext?.update()

        let backingBounds = convertToBacking(bounds)
        glViewport(0, 0, GLsizei(backingBounds.width), GLsizei(backingBounds.height))

        // Update engine viewport
        engine?.setViewportSize(width: Int(backingBounds.width), height: Int(backingBounds.height))
    }
    
    // MARK: - Hit Testing
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through clicks to parent view for window dragging
        return nil
    }
    
    // MARK: - ProjectM Preset Navigation (Backward Compatibility)

    /// Number of available presets (ProjectM only)
    var presetCount: Int {
        guard let pm = engine as? ProjectMWrapper else { return 0 }
        return pm.presetCount
    }

    /// Index of currently selected preset (ProjectM only)
    var currentPresetIndex: Int {
        guard let pm = engine as? ProjectMWrapper else { return 0 }
        return pm.currentPresetIndex
    }

    /// Name of currently selected preset (ProjectM only)
    var currentPresetName: String {
        guard let pm = engine as? ProjectMWrapper else { return "" }
        return pm.currentPresetName
    }

    /// Whether the current preset is locked (ProjectM only)
    var isPresetLocked: Bool {
        get {
            guard let pm = engine as? ProjectMWrapper else { return false }
            return pm.isPresetLocked
        }
        set {
            guard let pm = engine as? ProjectMWrapper else { return }
            pm.isPresetLocked = newValue
        }
    }

    /// Select next preset (ProjectM only)
    /// - Parameter hardCut: If true, switch immediately without blending
    func nextPreset(hardCut: Bool = false) {
        guard let pm = engine as? ProjectMWrapper else { return }
        pm.nextPreset(hardCut: hardCut)
    }

    /// Select previous preset (ProjectM only)
    /// - Parameter hardCut: If true, switch immediately without blending
    func previousPreset(hardCut: Bool = false) {
        guard let pm = engine as? ProjectMWrapper else { return }
        pm.previousPreset(hardCut: hardCut)
    }

    /// Select a random preset (ProjectM only)
    /// - Parameter hardCut: If true, switch immediately without blending
    func randomPreset(hardCut: Bool = false) {
        guard let pm = engine as? ProjectMWrapper else { return }
        pm.randomPreset(hardCut: hardCut)
    }

    /// Select a preset by index (ProjectM only)
    /// - Parameters:
    ///   - index: The preset index to select
    ///   - hardCut: If true, switch immediately without blending
    func selectPreset(at index: Int, hardCut: Bool = false) {
        guard let pm = engine as? ProjectMWrapper else { return }
        pm.selectPreset(at: index, hardCut: hardCut)
    }

    /// Get preset name at index (ProjectM only)
    func presetName(at index: Int) -> String {
        guard let pm = engine as? ProjectMWrapper else { return "" }
        return pm.presetName(at: index)
    }

    // MARK: - ProjectM Settings (Backward Compatibility)

    /// Preset duration in seconds (0 = no auto-switching) (ProjectM only)
    var presetDuration: Double {
        get {
            guard let pm = engine as? ProjectMWrapper else { return 30.0 }
            return pm.presetDuration
        }
        set {
            guard let pm = engine as? ProjectMWrapper else { return }
            pm.presetDuration = newValue
        }
    }

    /// Soft cut (blend) duration in seconds (ProjectM only)
    var softCutDuration: Double {
        get {
            guard let pm = engine as? ProjectMWrapper else { return 3.0 }
            return pm.softCutDuration
        }
        set {
            guard let pm = engine as? ProjectMWrapper else { return }
            pm.softCutDuration = newValue
        }
    }

    /// Whether hard cuts on beats are enabled (ProjectM only)
    var hardCutEnabled: Bool {
        get {
            guard let pm = engine as? ProjectMWrapper else { return true }
            return pm.hardCutEnabled
        }
        set {
            guard let pm = engine as? ProjectMWrapper else { return }
            pm.hardCutEnabled = newValue
        }
    }

    /// Beat sensitivity (0.0-2.0) (ProjectM only)
    var beatSensitivity: Float {
        get {
            guard let pm = engine as? ProjectMWrapper else { return 1.0 }
            return pm.beatSensitivity
        }
        set {
            guard let pm = engine as? ProjectMWrapper else { return }
            pm.beatSensitivity = newValue
        }
    }

    // MARK: - Preset Management (Backward Compatibility)

    /// Reload all presets from bundled and custom folders (ProjectM only)
    func reloadPresets() {
        guard let pm = engine as? ProjectMWrapper else { return }
        pm.reloadAllPresets()
    }

    /// Get information about loaded presets (ProjectM only)
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        guard let pm = engine as? ProjectMWrapper else { return (0, 0, nil) }
        return pm.presetsInfo
    }
}
