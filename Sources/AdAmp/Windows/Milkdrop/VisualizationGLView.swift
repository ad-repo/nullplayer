import AppKit
import OpenGL.GL3
import CoreVideo
import Accelerate
import os

// Silence OpenGL deprecation warnings (macOS still supports OpenGL 4.1)
// We use OpenGL for visualization as Metal doesn't have the same ecosystem of presets

/// Protocol for receiving audio data for visualization
protocol VisualizationDataSource: AnyObject {
    /// Get current spectrum data (75 bands, normalized 0-1)
    var spectrumData: [Float] { get }
    
    /// Get current PCM audio samples (mono, -1 to 1)
    var pcmData: [Float] { get }
    
    /// Sample rate of PCM data
    var sampleRate: Double { get }
}

/// OpenGL view for real-time audio visualization
/// Uses CVDisplayLink for 60fps updates
/// Supports projectM for Milkdrop preset rendering with fallback to built-in visualizations
class VisualizationGLView: NSOpenGLView {
    
    // MARK: - Properties
    
    weak var dataSource: VisualizationDataSource?
    
    /// CVDisplayLink for vsync'd rendering
    private var displayLink: CVDisplayLink?
    
    /// Whether rendering is currently active
    private(set) var isRendering = false
    
    /// ProjectM wrapper for Milkdrop visualization
    private var projectM: ProjectMWrapper?
    
    /// Whether projectM is available and initialized
    var isProjectMAvailable: Bool {
        return projectM?.isAvailable ?? false
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
        
        // Set up OpenGL context
        openGLContext?.makeCurrentContext()
        setupOpenGL()
        setupProjectM()
        setupDisplayLink()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOpenGL()
        setupProjectM()
        setupDisplayLink()
    }
    
    deinit {
        stopRendering()
        cleanupOpenGL()
        projectM = nil
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
    
    // MARK: - ProjectM Setup
    
    /// Flag to defer projectM initialization until first render (for correct GL context)
    private var projectMNeedsSetup = true
    
    private func setupProjectM() {
        // Mark that we want to use projectM - actual setup will happen on first render
        // This ensures the OpenGL context is properly initialized on the render thread
        projectMNeedsSetup = true
        NSLog("VisualizationGLView: projectM setup deferred to render thread")
    }
    
    /// Actually initialize projectM - must be called on render thread with GL context current
    private func initializeProjectMOnRenderThread() {
        guard projectMNeedsSetup else { return }
        projectMNeedsSetup = false
        
        // Get initial viewport size
        let backingBounds = convertToBacking(bounds)
        let width = Int(backingBounds.width)
        let height = Int(backingBounds.height)
        
        NSLog("VisualizationGLView: Setting up projectM with viewport %dx%d on render thread", width, height)
        
        // Create projectM wrapper
        projectM = ProjectMWrapper(width: width, height: height)
        
        if let pm = projectM, pm.isAvailable {
            // Load bundled presets
            pm.loadBundledPresets()
            
            // Start with idle beat sensitivity (calmer until audio plays)
            pm.beatSensitivity = idleBeatSensitivity
            
            if pm.presetCount > 0 {
                NSLog("VisualizationGLView: projectM initialized with %d presets, idle beat sensitivity = %.2f", pm.presetCount, idleBeatSensitivity)
            } else {
                NSLog("VisualizationGLView: projectM available but no presets found")
            }
        } else {
            NSLog("VisualizationGLView: projectM not available")
        }
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
    
    /// Set whether audio is actively playing
    /// When false, visualization becomes calmer with reduced beat sensitivity
    func setAudioActive(_ active: Bool) {
        guard active != isAudioActive else { return }
        isAudioActive = active
        
        if active {
            // Audio started playing - restore normal beat sensitivity
            projectM?.beatSensitivity = normalBeatSensitivity
            NSLog("VisualizationGLView: Audio active, beat sensitivity = %.2f", normalBeatSensitivity)
        } else {
            // Audio stopped - reduce beat sensitivity for calmer visualization
            projectM?.beatSensitivity = idleBeatSensitivity
            NSLog("VisualizationGLView: Audio idle, beat sensitivity = %.2f", idleBeatSensitivity)
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
        
        // Initialize projectM on first render (ensures correct GL context)
        if projectMNeedsSetup {
            initializeProjectMOnRenderThread()
        }
        
        // Get PCM data snapshot
        let pcm = dataLock.withLock { localPCM }
        
        // Get viewport dimensions
        let backingBounds = convertToBacking(bounds)
        let viewportWidth = Int(backingBounds.width)
        let viewportHeight = Int(backingBounds.height)
        
        // Render with projectM (only if available AND has a valid preset loaded)
        if isProjectMAvailable && hasProjectMPresets {
            renderProjectM(pcm: pcm, width: viewportWidth, height: viewportHeight)
        } else {
            // projectM not available or no preset loaded - just clear to black
            glViewport(0, 0, GLsizei(viewportWidth), GLsizei(viewportHeight))
            glClearColor(0.0, 0.0, 0.0, 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
        
        // Swap buffers
        context.flushBuffer()
    }
    
    /// Render a frame using projectM
    private func renderProjectM(pcm: [Float], width: Int, height: Int) {
        guard let pm = projectM else { return }
        
        // Note: hasValidPreset and renderFrame both acquire the render lock internally.
        // We check hasValidPreset first to avoid unnecessary lock contention when no preset is loaded.
        // The actual preset validity is re-checked inside renderFrame() under the lock.
        guard pm.hasValidPreset else { return }
        
        // Update viewport size if changed (this is atomic with respect to rendering)
        pm.setViewportSize(width: width, height: height)
        
        // Feed PCM data to projectM
        pm.addPCMMono(pcm)
        
        // Render the frame (checks preset validity again under the lock)
        pm.renderFrame()
    }
    
    /// Whether projectM has valid presets loaded
    var hasProjectMPresets: Bool {
        return projectM?.hasValidPreset ?? false
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
        
        // Update projectM viewport
        projectM?.setViewportSize(width: Int(backingBounds.width), height: Int(backingBounds.height))
    }
    
    // MARK: - Hit Testing
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through clicks to parent view for window dragging
        return nil
    }
    
    // MARK: - ProjectM Preset Navigation
    
    /// Number of available presets
    var presetCount: Int {
        return projectM?.presetCount ?? 0
    }
    
    /// Index of currently selected preset
    var currentPresetIndex: Int {
        return projectM?.currentPresetIndex ?? 0
    }
    
    /// Name of currently selected preset
    var currentPresetName: String {
        return projectM?.currentPresetName ?? ""
    }
    
    /// Whether the current preset is locked
    var isPresetLocked: Bool {
        get { projectM?.isPresetLocked ?? false }
        set { projectM?.isPresetLocked = newValue }
    }
    
    /// Select next preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func nextPreset(hardCut: Bool = false) {
        projectM?.nextPreset(hardCut: hardCut)
    }
    
    /// Select previous preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func previousPreset(hardCut: Bool = false) {
        projectM?.previousPreset(hardCut: hardCut)
    }
    
    /// Select a random preset
    /// - Parameter hardCut: If true, switch immediately without blending
    func randomPreset(hardCut: Bool = false) {
        projectM?.randomPreset(hardCut: hardCut)
    }
    
    /// Select a preset by index
    /// - Parameters:
    ///   - index: The preset index to select
    ///   - hardCut: If true, switch immediately without blending
    func selectPreset(at index: Int, hardCut: Bool = false) {
        projectM?.selectPreset(at: index, hardCut: hardCut)
    }
    
    /// Get preset name at index
    func presetName(at index: Int) -> String {
        return projectM?.presetName(at: index) ?? ""
    }
    
    // MARK: - ProjectM Settings
    
    /// Preset duration in seconds (0 = no auto-switching)
    var presetDuration: Double {
        get { projectM?.presetDuration ?? 30.0 }
        set { projectM?.presetDuration = newValue }
    }
    
    /// Soft cut (blend) duration in seconds
    var softCutDuration: Double {
        get { projectM?.softCutDuration ?? 3.0 }
        set { projectM?.softCutDuration = newValue }
    }
    
    /// Whether hard cuts on beats are enabled
    var hardCutEnabled: Bool {
        get { projectM?.hardCutEnabled ?? true }
        set { projectM?.hardCutEnabled = newValue }
    }
    
    /// Beat sensitivity (0.0-2.0)
    var beatSensitivity: Float {
        get { projectM?.beatSensitivity ?? 1.0 }
        set { projectM?.beatSensitivity = newValue }
    }
    
    // MARK: - Preset Management
    
    /// Reload all presets from bundled and custom folders
    func reloadPresets() {
        projectM?.reloadAllPresets()
    }
    
    /// Get information about loaded presets
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        return projectM?.presetsInfo ?? (0, 0, nil)
    }
}
