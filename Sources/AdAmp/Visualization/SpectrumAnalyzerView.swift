import MetalKit
import os.lock

// =============================================================================
// SPECTRUM ANALYZER VIEW - Metal-based real-time audio visualization
// =============================================================================
// A GPU-accelerated spectrum analyzer that supports two quality modes:
// - Winamp: Discrete color palette, pixel-art aesthetic
// - Enhanced: Smooth gradients with optional glow effect
//
// Uses CADisplayLink for 60Hz rendering synchronized to the display refresh.
// Thread-safe spectrum data updates via OSAllocatedUnfairLock.
// =============================================================================

// MARK: - Enums

/// Quality mode for spectrum analyzer rendering
enum SpectrumQualityMode: String, CaseIterable {
    case winamp = "Winamp"       // Discrete colors, pixel-art aesthetic
    case enhanced = "Enhanced"   // LED matrix with rainbow
    case ultra = "Ultra"         // Maximum visual quality with effects
    
    var displayName: String { rawValue }
}

/// Decay mode controlling how quickly bars fall
enum SpectrumDecayMode: String, CaseIterable {
    case instant = "Instant"     // No smoothing, immediate response
    case snappy = "Snappy"       // 25% retention - fast and punchy
    case balanced = "Balanced"   // 40% retention - good middle ground
    case smooth = "Smooth"       // 55% retention - original Winamp feel
    
    var displayName: String { rawValue }
    
    /// Decay factor (0 = instant, higher = slower decay)
    var decayFactor: Float {
        switch self {
        case .instant: return 0.0
        case .snappy: return 0.25
        case .balanced: return 0.40
        case .smooth: return 0.55
        }
    }
}

/// Normalization mode controlling how spectrum levels are scaled
enum SpectrumNormalizationMode: String, CaseIterable {
    case accurate = "Accurate"   // No normalization - true levels, flat pink noise, max dynamic range
    case adaptive = "Adaptive"   // Light global normalization that adapts to overall loudness
    case dynamic = "Dynamic"     // Per-region normalization for best visual appeal with music
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .accurate: return "True levels (flat pink noise)"
        case .adaptive: return "Adapts to loudness"
        case .dynamic: return "Best for music"
        }
    }
}

// MARK: - LED Parameters (for Metal shader)

/// Parameters passed to the Metal shader (must match Metal struct exactly)
/// Total size: 40 bytes, 8-byte aligned
struct LEDParams {
    var viewportSize: SIMD2<Float>  // 8 bytes (offset 0)
    var columnCount: Int32          // 4 bytes (offset 8)
    var rowCount: Int32             // 4 bytes (offset 12)
    var cellWidth: Float            // 4 bytes (offset 16)
    var cellHeight: Float           // 4 bytes (offset 20)
    var cellSpacing: Float          // 4 bytes (offset 24)
    var qualityMode: Int32          // 4 bytes (offset 28)
    var maxHeight: Float            // 4 bytes (offset 32)
    var padding: Float = 0          // 4 bytes (offset 36) - alignment to 40
}

/// Parameters for Ultra mode shader (must match Metal UltraParams exactly)
/// Total size: 56 bytes
struct UltraParams {
    var viewportSize: SIMD2<Float>  // 8 bytes (offset 0)
    var columnCount: Int32          // 4 bytes (offset 8)
    var rowCount: Int32             // 4 bytes (offset 12)
    var cellWidth: Float            // 4 bytes (offset 16)
    var cellHeight: Float           // 4 bytes (offset 20)
    var cellSpacing: Float          // 4 bytes (offset 24)
    var glowRadius: Float           // 4 bytes (offset 28)
    var glowIntensity: Float        // 4 bytes (offset 32)
    var reflectionHeight: Float     // 4 bytes (offset 36)
    var reflectionAlpha: Float      // 4 bytes (offset 40)
    var time: Float                 // 4 bytes (offset 44)
    var padding: SIMD2<Float> = SIMD2<Float>(0, 0)  // 8 bytes (offset 48) - alignment to 56
}

// MARK: - Spectrum Analyzer View

/// Metal-based spectrum analyzer visualization view
class SpectrumAnalyzerView: NSView {
    
    // MARK: - Configuration
    
    /// Quality mode (Winamp discrete vs Enhanced smooth vs Ultra high-quality)
    var qualityMode: SpectrumQualityMode = .winamp {
        didSet {
            UserDefaults.standard.set(qualityMode.rawValue, forKey: "spectrumQualityMode")
            let mode = qualityMode
            dataLock.withLock {
                renderQualityMode = mode
            }
            // Note: Don't change semaphore at runtime - it causes crashes when GPU work is in-flight
        }
    }
    
    /// Get the display refresh rate from the current display link
    private func getDisplayRefreshRate() -> Double {
        guard let displayLink = displayLink else { return 60.0 }
        let time = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink)
        // Ensure we have valid values to avoid division issues
        guard time.timeValue > 0 && time.timeScale > 0 else { return 60.0 }
        return Double(time.timeScale) / Double(time.timeValue)
    }
    
    /// Decay/responsiveness mode
    var decayMode: SpectrumDecayMode = .snappy {
        didSet {
            UserDefaults.standard.set(decayMode.rawValue, forKey: "spectrumDecayMode")
            let factor = decayMode.decayFactor
            dataLock.withLock {
                renderDecayFactor = factor
            }
        }
    }
    
    /// Number of bars to display
    var barCount: Int = 19 {
        didSet {
            let count = barCount
            dataLock.withLock {
                renderBarCount = count
            }
        }
    }
    
    /// Bar width in pixels (scaled in shader)
    var barWidth: CGFloat = 3.0 {
        didSet {
            let width = barWidth
            dataLock.withLock {
                renderBarWidth = width
            }
        }
    }
    
    /// Spacing between bars
    var barSpacing: CGFloat = 1.0
    
    /// Glow intensity for enhanced mode (0-1)
    var glowIntensity: Float = 0.5
    
    // MARK: - Metal Resources
    
    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState?
    
    // Pipeline states for all modes
    private var ledPipelineState: MTLRenderPipelineState?
    private var barPipelineState: MTLRenderPipelineState?
    private var ultraPipelineState: MTLRenderPipelineState?
    
    // Buffers
    private var vertexBuffer: MTLBuffer?
    private var colorBuffer: MTLBuffer?
    private var heightBuffer: MTLBuffer?
    private var paramsBuffer: MTLBuffer?
    
    // LED Matrix buffers
    private var cellBrightnessBuffer: MTLBuffer?
    private var peakPositionsBuffer: MTLBuffer?
    
    // Ultra mode buffers
    private var ultraCellBrightnessBuffer: MTLBuffer?
    private var ultraParamsBuffer: MTLBuffer?
    
    // MARK: - Display Sync
    
    private var displayLink: CVDisplayLink?
    /// Retained context wrapper for safe display link callback - prevents use-after-free
    private var displayLinkContextRef: Unmanaged<DisplayLinkContext>?
    private var isRendering = false
    
    // Frame pacing semaphore - limits in-flight command buffers to prevent memory buildup
    // Use triple buffering (3) for all modes - simpler and avoids crashes when switching modes
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    
    // MARK: - Thread-Safe Spectrum Data
    // Note: These properties are accessed from both the main thread and the CVDisplayLink callback thread.
    // They are protected by dataLock and marked nonisolated(unsafe) to allow cross-thread access.
    
    private let dataLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private var rawSpectrum: [Float] = []       // From audio engine (75 bands)
    nonisolated(unsafe) private var displaySpectrum: [Float] = []   // After decay smoothing (Enhanced/Winamp)
    nonisolated(unsafe) private var ultraDisplaySpectrum: [Float] = []  // After decay smoothing (Ultra mode - 96 bars)
    nonisolated(unsafe) private var renderBarCount: Int = 19        // Bar count for rendering
    nonisolated(unsafe) private var renderDecayFactor: Float = 0.25 // Decay factor for rendering
    nonisolated(unsafe) private var renderColorPalette: [SIMD4<Float>] = [] // Colors for rendering
    nonisolated(unsafe) private var renderBarWidth: CGFloat = 3.0   // Bar width for rendering
    nonisolated(unsafe) private var renderQualityMode: SpectrumQualityMode = .winamp // Quality mode for rendering
    
    // LED Matrix state tracking (for Enhanced and Ultra modes)
    nonisolated(unsafe) private var peakHoldPositions: [Float] = []  // Peak hold position per column (0-1) - Enhanced mode
    nonisolated(unsafe) private var ultraPeakPositions: [Float] = []  // Peak positions for Ultra mode (separate to avoid resize conflicts)
    nonisolated(unsafe) private var cellBrightness: [[Float]] = []   // Brightness per cell [column][row]
    private let ledRowCount = 16  // Number of LED rows in matrix (Enhanced mode)
    private let ultraLedRowCount = 64  // Ultra high resolution
    private let ultraBarCount = 512  // Maximum fidelity
    
    // Ultra mode state tracking
    nonisolated(unsafe) private var ultraCellBrightness: [[Float]] = []  // Brightness per cell [column][row] for Ultra
    nonisolated(unsafe) private var peakVelocities: [Float] = []  // Peak velocity for physics simulation
    nonisolated(unsafe) private var animationTime: Float = 0  // For subtle animations
    
    // MARK: - Color Palette
    
    /// Current skin's visualization colors (24 colors, updated on skin change)
    private var colorPalette: [SIMD4<Float>] = []
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        
        // Restore saved settings
        if let savedQuality = UserDefaults.standard.string(forKey: "spectrumQualityMode"),
           let mode = SpectrumQualityMode(rawValue: savedQuality) {
            qualityMode = mode
        }
        
        if let savedDecay = UserDefaults.standard.string(forKey: "spectrumDecayMode"),
           let mode = SpectrumDecayMode(rawValue: savedDecay) {
            decayMode = mode
        }
        
        // Initialize display spectrum and sync to render-safe variables
        // Use max size to avoid any resizing during mode switches
        let maxBars = max(barCount, ultraBarCount)
        displaySpectrum = Array(repeating: 0, count: maxBars)
        ultraDisplaySpectrum = Array(repeating: 0, count: maxBars)
        
        // Pre-initialize ALL arrays to maximum size to prevent crashes during mode switches
        // Ultra mode arrays
        ultraPeakPositions = Array(repeating: 0, count: maxBars)
        peakVelocities = Array(repeating: 0, count: maxBars)
        ultraCellBrightness = Array(repeating: Array(repeating: Float(0), count: ultraLedRowCount), count: maxBars)
        
        // Enhanced mode arrays - also max size
        peakHoldPositions = Array(repeating: 0, count: maxBars)
        cellBrightness = Array(repeating: Array(repeating: Float(0), count: ledRowCount), count: maxBars)
        
        renderBarCount = barCount
        renderDecayFactor = decayMode.decayFactor
        renderBarWidth = barWidth
        renderQualityMode = qualityMode
        
        // Set up Metal
        setupMetal()
        
        // Load colors from current skin
        updateColorsFromSkin()
        
        // Observe window occlusion state to stop rendering when not visible
        // This prevents drawable accumulation when the window is minimized or occluded
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeOcclusionState),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMiniaturize),
                                               name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidDeminiaturize),
                                               name: NSWindow.didDeminiaturizeNotification, object: nil)
        
        // Observe spectrum settings changes from main menu
        NotificationCenter.default.addObserver(self, selector: #selector(spectrumSettingsChanged),
                                               name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
        
        // Observe audio source changes to reset state
        NotificationCenter.default.addObserver(self, selector: #selector(handleSourceChange),
                                               name: NSNotification.Name("ResetSpectrumState"), object: nil)
        
        // Observe playback state changes to ensure display link restarts when playback begins
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackStateChange),
                                               name: .audioPlaybackStateChanged, object: nil)
        
        // Start rendering
        startRendering()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopRendering()
    }
    
    // MARK: - Window Occlusion Handling
    
    /// Track if rendering was stopped due to window occlusion (vs idle)
    private var stoppedDueToOcclusion: Bool = false
    
    @objc private func windowDidChangeOcclusionState(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        
        if window?.occlusionState.contains(.visible) == true {
            // Window became visible - restart rendering if we stopped due to occlusion
            if stoppedDueToOcclusion {
                stoppedDueToOcclusion = false
                startRendering()
            }
        } else {
            // Window no longer visible - stop rendering to save resources and prevent drawable accumulation
            if isRendering {
                stoppedDueToOcclusion = true
                stopRendering()
            }
        }
    }
    
    @objc private func windowDidMiniaturize(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        if isRendering {
            stoppedDueToOcclusion = true
            stopRendering()
        }
    }
    
    @objc private func windowDidDeminiaturize(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        if stoppedDueToOcclusion {
            stoppedDueToOcclusion = false
            startRendering()
        }
    }
    
    @objc private func spectrumSettingsChanged(_ notification: Notification) {
        // Reload settings from UserDefaults
        if let savedQuality = UserDefaults.standard.string(forKey: "spectrumQualityMode"),
           let mode = SpectrumQualityMode(rawValue: savedQuality) {
            qualityMode = mode
        }
        
        if let savedDecay = UserDefaults.standard.string(forKey: "spectrumDecayMode"),
           let mode = SpectrumDecayMode(rawValue: savedDecay) {
            decayMode = mode
        }
        
        // Note: We no longer reset state arrays on mode switch since pre-allocated
        // arrays handle all modes and the display naturally transitions. Resetting
        // was causing frame drops due to long lock hold times.
        
        // Just reset idle tracking to ensure rendering continues smoothly
        dataLock.withLock {
            idleFrameCount = 0
            hasClearedAfterIdle = false
        }
    }
    
    @objc private func handleSourceChange(_ notification: Notification) {
        // Called when switching between local/streaming sources
        // Reset all state to ensure clean transition
        resetState()
    }
    
    @objc private func handlePlaybackStateChange(_ notification: Notification) {
        // When playback starts, ensure the display link is running
        // This handles race conditions where the display link stopped but playback resumed
        guard let userInfo = notification.userInfo,
              let state = userInfo["state"] as? PlaybackState else { return }
        
        if state == .playing && !isRendering {
            startRendering()
        }
    }
    
    // MARK: - Metal Setup
    
    private func setupMetal() {
        // Get the default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("SpectrumAnalyzerView: Metal is not supported on this device")
            return
        }
        self.device = device
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            NSLog("SpectrumAnalyzerView: Failed to create command queue")
            return
        }
        self.commandQueue = commandQueue
        
        // Configure Metal layer
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.frame = bounds
        // CRITICAL: Limit drawable pool size to prevent unbounded memory growth
        // Without this, CAMetalLayer can create unlimited drawables during continuous rendering
        metalLayer.maximumDrawableCount = 3
        // Disable display sync to allow dropping frames when GPU falls behind
        // This prevents drawable accumulation when rendering can't keep up
        metalLayer.displaySyncEnabled = false
        layer?.addSublayer(metalLayer)
        
        // Load shaders and create pipeline
        setupPipeline()
        
        // Create buffers
        setupBuffers()
    }
    
    private func setupPipeline() {
        guard let device = device else { return }
        
        // Load shader source from file (runtime compilation for SPM compatibility)
        // This is required because makeDefaultLibrary() returns nil in SPM executables
        guard let shaderURL = BundleHelper.url(forResource: "SpectrumShaders", withExtension: "metal"),
              let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            NSLog("SpectrumAnalyzerView: Failed to load shader source file")
            return
        }
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            
            // Create LED matrix pipeline (Enhanced mode)
            if let vertexFunc = library.makeFunction(name: "led_matrix_vertex"),
               let fragmentFunc = library.makeFunction(name: "led_matrix_fragment") {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "LED Matrix Pipeline"
                descriptor.vertexFunction = vertexFunc
                descriptor.fragmentFunction = fragmentFunc
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                ledPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            }
            
            // Create bar pipeline (Winamp mode)
            if let vertexFunc = library.makeFunction(name: "spectrum_vertex"),
               let fragmentFunc = library.makeFunction(name: "spectrum_fragment") {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "Spectrum Bar Pipeline"
                descriptor.vertexFunction = vertexFunc
                descriptor.fragmentFunction = fragmentFunc
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                barPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            }
            
            // Create Ultra pipeline (Ultra mode with bloom and reflection)
            if let vertexFunc = library.makeFunction(name: "ultra_matrix_vertex"),
               let fragmentFunc = library.makeFunction(name: "ultra_matrix_fragment") {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "Ultra Matrix Pipeline"
                descriptor.vertexFunction = vertexFunc
                descriptor.fragmentFunction = fragmentFunc
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                // Enable blending for glow effects
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].rgbBlendOperation = .add
                descriptor.colorAttachments[0].alphaBlendOperation = .add
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                ultraPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            }
            
            // Keep pipelineState for backward compatibility (points to current mode)
            switch qualityMode {
            case .winamp:
                pipelineState = barPipelineState
            case .enhanced:
                pipelineState = ledPipelineState
            case .ultra:
                pipelineState = ultraPipelineState
            }
            
            NSLog("SpectrumAnalyzerView: Metal pipelines created successfully")
        } catch {
            NSLog("SpectrumAnalyzerView: Failed to compile shaders: \(error)")
        }
    }
    
    private func setupBuffers() {
        guard let device = device else { return }
        
        let maxColumns = 512  // Enough for Ultra mode's 512 bars
        let maxRows = 16
        let maxCells = maxColumns * maxRows
        
        // Ultra mode has more rows (64) for ultra high resolution
        let ultraMaxRows = 64
        let ultraMaxCells = maxColumns * ultraMaxRows
        
        // Cell brightness buffer (one float per cell) - for LED matrix mode
        cellBrightnessBuffer = device.makeBuffer(
            length: maxCells * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Peak positions buffer (one float per column) - for LED matrix mode
        peakPositionsBuffer = device.makeBuffer(
            length: maxColumns * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Heights buffer (for Winamp bar mode, reused from existing)
        heightBuffer = device.makeBuffer(
            length: maxColumns * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Colors buffer (24 colors for Winamp palette)
        colorBuffer = device.makeBuffer(
            length: 24 * MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        )
        
        // Params buffer (shared between Winamp and Enhanced modes)
        paramsBuffer = device.makeBuffer(
            length: MemoryLayout<LEDParams>.stride,
            options: .storageModeShared
        )
        
        // Ultra mode buffers
        ultraCellBrightnessBuffer = device.makeBuffer(
            length: ultraMaxCells * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        ultraParamsBuffer = device.makeBuffer(
            length: MemoryLayout<UltraParams>.stride,
            options: .storageModeShared
        )
    }
    
    // MARK: - Display Link
    
    private func startRendering() {
        guard !isRendering else { return }
        isRendering = true
        
        // Reset idle tracking state (protected by dataLock)
        dataLock.withLock {
            idleFrameCount = 0
            hasClearedAfterIdle = false
            stoppedDueToIdle = false
        }
        
        // Create display link
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        
        guard let displayLink = link else {
            NSLog("SpectrumAnalyzerView: Failed to create display link")
            return
        }
        
        self.displayLink = displayLink
        
        // Create a retained context wrapper with weak view reference
        // This prevents use-after-free crashes when the view is deallocated
        // while the display link callback is still running on a background thread
        let context = DisplayLinkContext(view: self)
        let retainedContext = Unmanaged.passRetained(context)
        self.displayLinkContextRef = retainedContext
        let callbackPointer = retainedContext.toOpaque()
        
        // Set output callback with safe context
        CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, callbackPointer)
        
        // Start the display link
        CVDisplayLinkStart(displayLink)
    }
    
    private func stopRendering() {
        guard isRendering else { return }
        isRendering = false
        
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
        
        // Release the retained context wrapper
        // The weak reference inside will safely return nil if accessed after this
        if let contextRef = displayLinkContextRef {
            contextRef.release()
            displayLinkContextRef = nil
        }
        
        // Note: In-flight command buffers will complete asynchronously and signal
        // the semaphore via their completion handlers. The weak reference to self
        // in the handler ensures no retain cycle during deallocation.
    }
    
    // MARK: - Rendering
    
    /// Track if we have any visible spectrum data (for idle optimization)
    /// Protected by dataLock for thread-safe access from render and updateSpectrum
    /// nonisolated(unsafe) because Swift doesn't recognize our lock-based synchronization
    nonisolated(unsafe) private var hasVisibleData: Bool = false
    
    /// Track if we've cleared the display after data stopped (only need to clear once)
    /// Protected by dataLock for thread-safe access from render and updateSpectrum
    /// nonisolated(unsafe) because Swift doesn't recognize our lock-based synchronization
    nonisolated(unsafe) private var hasClearedAfterIdle: Bool = false
    
    /// Count consecutive frames with no data - used to stop display link when idle
    /// Protected by dataLock for thread-safe access from render and updateSpectrum
    /// nonisolated(unsafe) because Swift doesn't recognize our lock-based synchronization
    nonisolated(unsafe) private var idleFrameCount: Int = 0
    
    /// Frames to wait before stopping display link when idle (~1 second at 60fps)
    private let idleFrameThreshold: Int = 60
    
    /// Track if we stopped rendering due to idle (vs window hidden)
    /// Protected by dataLock for thread-safe access from render and updateSpectrum
    /// nonisolated(unsafe) because Swift doesn't recognize our lock-based synchronization
    nonisolated(unsafe) private var stoppedDueToIdle: Bool = false
    
    /// Called by display link at 60Hz
    /// Note: This is internal (not private) so the display link callback can access it
    func render() {
        guard isRendering, let metalLayer = metalLayer else { return }
        
        // Non-blocking check for semaphore slot - if GPU is backed up, skip frame immediately
        // This prevents frame accumulation and keeps the display responsive
        guard inFlightSemaphore.wait(timeout: .now()) == .success else {
            return  // Skip frame if we're backed up - don't block
        }
        
        // Update display spectrum and get render state in a single lock acquisition
        // This minimizes lock contention between the render thread and main thread
        var hadData = false
        var shouldStopDueToIdle = false
        var shouldSkipFrame = false
        var currentMode: SpectrumQualityMode = .winamp
        
        dataLock.withLock {
            // Update display spectrum with decay
            hadData = updateDisplaySpectrumLocked()
            
            // Check idle state
            if !hadData {
                idleFrameCount += 1
                
                if idleFrameCount >= idleFrameThreshold {
                    stoppedDueToIdle = true
                    shouldStopDueToIdle = true
                } else if hasClearedAfterIdle {
                    shouldSkipFrame = true
                } else {
                    hasClearedAfterIdle = true
                }
            } else {
                idleFrameCount = 0
                hasClearedAfterIdle = false
            }
            
            // Get current mode for pipeline selection
            currentMode = renderQualityMode
        }
        
        if shouldStopDueToIdle {
            inFlightSemaphore.signal()
            DispatchQueue.main.async { [weak self] in
                self?.stopRendering()
            }
            return
        }
        
        if shouldSkipFrame {
            inFlightSemaphore.signal()
            return
        }
        
        // Get drawable - this must succeed for us to render
        guard let drawable = metalLayer.nextDrawable() else {
            inFlightSemaphore.signal()  // Release slot since we won't use it
            return
        }
        let activePipeline: MTLRenderPipelineState?
        switch currentMode {
        case .winamp:
            activePipeline = barPipelineState
        case .enhanced:
            activePipeline = ledPipelineState
        case .ultra:
            activePipeline = ultraPipelineState
        }
        
        guard let pipeline = activePipeline,
              let commandBuffer = commandQueue?.makeCommandBuffer() else {
            inFlightSemaphore.signal()  // Release slot since we won't render
            return
        }
        
        // Create render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            inFlightSemaphore.signal()  // Release slot since we won't render
            return
        }
        
        // Update buffers with current data
        updateBuffers()
        
        // Set pipeline state
        encoder.setRenderPipelineState(pipeline)
        
        // Get bar count for vertex calculation
        var localBarCount: Int = 0
        dataLock.withLock {
            localBarCount = renderBarCount
        }
        
        switch currentMode {
        case .enhanced:
            // LED Matrix mode - bind LED buffers
            if let buffer = cellBrightnessBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            }
            if let buffer = peakPositionsBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 1)
            }
            if let buffer = paramsBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 2)
                encoder.setFragmentBuffer(buffer, offset: 0, index: 1)
            }
            
            // Each cell is 6 vertices, total cells = columns * rows
            let vertexCount = localBarCount * ledRowCount * 6
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
            
        case .ultra:
            // Ultra mode - bind Ultra buffers
            if let buffer = ultraCellBrightnessBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            }
            if let buffer = peakPositionsBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 1)
            }
            if let buffer = ultraParamsBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 2)
                encoder.setFragmentBuffer(buffer, offset: 0, index: 1)
            }
            
            // Ultra has 96 bars and 32 rows for high resolution
            let vertexCount = ultraBarCount * ultraLedRowCount * 6
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
            
        case .winamp:
            // Winamp bar mode - bind bar buffers
            if let buffer = heightBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            }
            if let buffer = paramsBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 2)
            }
            if let buffer = colorBuffer {
                encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
            }
            if let buffer = paramsBuffer {
                encoder.setFragmentBuffer(buffer, offset: 0, index: 1)
            }
            
            // 6 vertices per bar
            let vertexCount = localBarCount * 6
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }
        
        encoder.endEncoding()
        
        // Signal semaphore when GPU is done with this frame
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    /// Update display spectrum with decay and return whether there's visible data
    /// Thread-safe version that acquires the lock
    /// - Returns: true if any bar has visible data (> 0.01), false if all bars are essentially zero
    @discardableResult
    private func updateDisplaySpectrum() -> Bool {
        return dataLock.withLock {
            updateDisplaySpectrumLocked()
        }
    }
    
    /// Update display spectrum with decay - caller MUST hold dataLock
    /// - Returns: true if any bar has visible data (> 0.01), false if all bars are essentially zero
    private func updateDisplaySpectrumLocked() -> Bool {
        var hasData = false
        
        let decay = renderDecayFactor
        let outputCount = renderBarCount
        let ultraOutputCount = ultraBarCount
        
        // Check normalization mode - Accurate uses full height for max dynamic range
        let isAccurateMode = UserDefaults.standard.string(forKey: "spectrumNormalizationMode") == SpectrumNormalizationMode.accurate.rawValue
        
        // Scale factor: Accurate mode uses full height, others leave headroom for peaks
        let displayScale: Float = isAccurateMode ? 1.0 : 0.95
        
        // Map raw spectrum to display bars
        if rawSpectrum.isEmpty {
            // Decay existing values when no input
            for i in 0..<displaySpectrum.count {
                displaySpectrum[i] *= decay
                if displaySpectrum[i] < 0.01 {
                    displaySpectrum[i] = 0
                } else {
                    hasData = true
                }
            }
            // Also decay Ultra spectrum
            for i in 0..<ultraDisplaySpectrum.count {
                ultraDisplaySpectrum[i] *= decay
                if ultraDisplaySpectrum[i] < 0.01 {
                    ultraDisplaySpectrum[i] = 0
                }
            }
        } else {
            // Map input bands to display bars
            let inputCount = rawSpectrum.count
            
            // Ensure displaySpectrum has correct size (for Enhanced/Winamp modes)
            if displaySpectrum.count != outputCount {
                displaySpectrum = Array(repeating: 0, count: outputCount)
            }
            
            // Ensure ultraDisplaySpectrum has correct size (96 bars for Ultra mode)
            if ultraDisplaySpectrum.count != ultraOutputCount {
                ultraDisplaySpectrum = Array(repeating: 0, count: ultraOutputCount)
            }
            
            // Update standard display spectrum (for Enhanced/Winamp)
            if inputCount >= outputCount {
                let bandsPerBar = inputCount / outputCount
                for barIndex in 0..<outputCount {
                    let start = barIndex * bandsPerBar
                        let end = min(start + bandsPerBar, inputCount)
                        var sum: Float = 0
                        for i in start..<end {
                            sum += rawSpectrum[i]
                        }
                        let newValue = (sum / Float(end - start)) * displayScale
                        
                        if newValue > displaySpectrum[barIndex] {
                            displaySpectrum[barIndex] = newValue
                        } else {
                            displaySpectrum[barIndex] = displaySpectrum[barIndex] * decay + newValue * (1 - decay)
                        }
                        
                        if displaySpectrum[barIndex] > 0.01 {
                            hasData = true
                        }
                    }
                } else {
                    for barIndex in 0..<outputCount {
                        let sourceIndex = Float(barIndex) * Float(inputCount - 1) / Float(outputCount - 1)
                        let lowerIndex = Int(sourceIndex)
                        let upperIndex = min(lowerIndex + 1, inputCount - 1)
                        let fraction = sourceIndex - Float(lowerIndex)
                        let newValue = (rawSpectrum[lowerIndex] * (1 - fraction) + rawSpectrum[upperIndex] * fraction) * displayScale
                        
                        if newValue > displaySpectrum[barIndex] {
                            displaySpectrum[barIndex] = newValue
                        } else {
                            displaySpectrum[barIndex] = displaySpectrum[barIndex] * decay + newValue * (1 - decay)
                        }
                        
                        if displaySpectrum[barIndex] > 0.01 {
                            hasData = true
                        }
                    }
                }
                
                // Update Ultra display spectrum (96 bars - interpolate from raw spectrum)
                for barIndex in 0..<ultraOutputCount {
                    let sourceIndex = Float(barIndex) * Float(inputCount - 1) / Float(ultraOutputCount - 1)
                    let lowerIndex = Int(sourceIndex)
                    let upperIndex = min(lowerIndex + 1, inputCount - 1)
                    let fraction = sourceIndex - Float(lowerIndex)
                    let newValue = (rawSpectrum[lowerIndex] * (1 - fraction) + rawSpectrum[upperIndex] * fraction) * displayScale
                    
                    if newValue > ultraDisplaySpectrum[barIndex] {
                        ultraDisplaySpectrum[barIndex] = newValue
                    } else {
                        ultraDisplaySpectrum[barIndex] = ultraDisplaySpectrum[barIndex] * decay + newValue * (1 - decay)
                    }
                }
            }
            
        // Update LED matrix state based on mode
        switch renderQualityMode {
        case .enhanced:
            updateLEDMatrixState()
        case .ultra:
            updateUltraMatrixState()
        case .winamp:
            break  // Winamp mode doesn't use LED matrix
        }
        
        hasVisibleData = hasData
        return hasData
    }
    
    /// Updates peak hold positions and per-cell brightness for LED matrix mode
    /// Note: Only called when qualityMode == .enhanced
    private func updateLEDMatrixState() {
        let colCount = renderBarCount
        
        // Arrays are pre-allocated in commonInit - no resizing needed
        
        let peakDecayRate: Float = 0.012      // How fast peak falls (per frame)
        let peakHoldFrames: Float = 0.985     // Slight delay before peak starts falling
        let cellFadeRate: Float = 0.03        // How fast cells fade out
        let cellAttackRate: Float = 0.4       // How fast cells brighten (smooth attack prevents sparkle)
        
        for col in 0..<min(colCount, displaySpectrum.count) {
            let currentLevel = displaySpectrum[col]
            let currentRow = Int(currentLevel * Float(ledRowCount))
            
            // Update peak hold position
            if currentLevel > peakHoldPositions[col] {
                // New peak - jump to current level
                peakHoldPositions[col] = currentLevel
            } else {
                // Decay peak slowly
                peakHoldPositions[col] = max(0, peakHoldPositions[col] * peakHoldFrames - peakDecayRate)
            }
            
            // Update per-cell brightness with smooth transitions (prevents sparkle/shimmer)
            for row in 0..<ledRowCount {
                let targetBrightness: Float = row < currentRow ? 1.0 : 0.0
                let currentBrightness = cellBrightness[col][row]
                
                if targetBrightness > currentBrightness {
                    // Cell should be lit - smoothly increase brightness (prevents sparkle on threshold cells)
                    cellBrightness[col][row] = min(1.0, currentBrightness + cellAttackRate)
                } else {
                    // Cell should be dark - fade out
                    cellBrightness[col][row] = max(0, currentBrightness - cellFadeRate)
                }
            }
        }
    }
    
    /// Updates state for Ultra mode with physics-based peaks and higher resolution
    private func updateUltraMatrixState() {
        let colCount = ultraBarCount
        
        // Arrays are pre-allocated in commonInit - no resizing needed
        
        // Physics constants for smooth, satisfying peak animation
        let gravity: Float = 0.012           // Acceleration downward per frame (slightly faster)
        let bounceCoeff: Float = 0.35        // How much velocity is retained on bounce
        let minBounceVelocity: Float = 0.015 // Minimum velocity to trigger bounce
        
        // Fade rates for smooth trails
        let cellFadeRate: Float = 0.04       // How fast unlit cells fade (faster = more responsive)
        let trailFadeRate: Float = 0.025     // Slower fade for recently-lit cells (creates trail)
        
        // Floor cutoff for better dynamic range - values below this become 0
        // This removes the always-lit bottom rows during normal playback
        let floor: Float = 0.15
        let ceiling: Float = 1.0
        let range = ceiling - floor
        
        // Update animation time
        animationTime += 1.0 / 60.0
        
        for col in 0..<min(colCount, ultraDisplaySpectrum.count) {
            let rawLevel = ultraDisplaySpectrum[col]
            // Apply floor: subtract floor and rescale to 0-1
            let currentLevel = max(0, (rawLevel - floor) / range)
            let currentRow = Int(currentLevel * Float(ultraLedRowCount))
            
            // Physics-based peak animation
            if currentLevel > ultraPeakPositions[col] {
                // New peak - jump to current level and reset velocity
                ultraPeakPositions[col] = currentLevel
                peakVelocities[col] = 0
            } else {
                // Apply gravity (acceleration)
                peakVelocities[col] -= gravity
                ultraPeakPositions[col] += peakVelocities[col]
                
                // Check for collision with current bar level (bounce)
                if ultraPeakPositions[col] < currentLevel {
                    ultraPeakPositions[col] = currentLevel
                    // Bounce with energy loss, but only if moving fast enough
                    if abs(peakVelocities[col]) > minBounceVelocity {
                        peakVelocities[col] = -peakVelocities[col] * bounceCoeff
                    } else {
                        peakVelocities[col] = 0
                    }
                }
                
                // Clamp to valid range
                ultraPeakPositions[col] = max(0, min(1.0, ultraPeakPositions[col]))
            }
            
            // Update per-cell brightness with trails
            for row in 0..<ultraLedRowCount {
                if row < currentRow {
                    // Cell is currently lit - set to full brightness
                    ultraCellBrightness[col][row] = 1.0
                } else if ultraCellBrightness[col][row] > 0.7 {
                    // Recently lit cell - fade slower to create trail effect
                    ultraCellBrightness[col][row] = max(0, ultraCellBrightness[col][row] - trailFadeRate)
                } else {
                    // Older unlit cell - fade faster
                    ultraCellBrightness[col][row] = max(0, ultraCellBrightness[col][row] - cellFadeRate)
                }
            }
        }
    }
    
    private func updateBuffers() {
        // Get render-safe values inside lock
        var localBarCount: Int = 0
        var localBarWidth: CGFloat = 0
        var localColors: [SIMD4<Float>] = []
        var localSpectrum: [Float] = []
        var localPeakPositions: [Float] = []
        var localCellBrightness: [[Float]] = []
        var localUltraCellBrightness: [[Float]] = []
        var localQualityMode: SpectrumQualityMode = .winamp
        var localAnimationTime: Float = 0
        
        dataLock.withLock {
            localBarCount = renderBarCount
            localBarWidth = renderBarWidth
            localColors = renderColorPalette
            localSpectrum = displaySpectrum
            // Use appropriate peak positions based on mode
            localPeakPositions = renderQualityMode == .ultra ? ultraPeakPositions : peakHoldPositions
            localCellBrightness = cellBrightness
            localUltraCellBrightness = ultraCellBrightness
            localQualityMode = renderQualityMode
            localAnimationTime = animationTime
        }
        
        let scale = metalLayer?.contentsScale ?? 1.0
        let scaledWidth = Float(bounds.width * scale)
        let scaledHeight = Float(bounds.height * scale)
        
        switch localQualityMode {
        case .enhanced:
            // Calculate cell dimensions for Enhanced mode (16 rows)
            let cellSpacing: Float = 2.0 * Float(scale)
            let cellHeight = (scaledHeight - Float(ledRowCount - 1) * cellSpacing) / Float(ledRowCount)
            let cellWidth = Float(localBarWidth * scale) - 1.0
            
            // Update params buffer
            if let buffer = paramsBuffer {
                let ptr = buffer.contents().bindMemory(to: LEDParams.self, capacity: 1)
                ptr.pointee = LEDParams(
                    viewportSize: SIMD2<Float>(scaledWidth, scaledHeight),
                    columnCount: Int32(localBarCount),
                    rowCount: Int32(ledRowCount),
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    cellSpacing: cellSpacing,
                    qualityMode: 1,
                    maxHeight: scaledHeight
                )
            }
            
            // Update cell brightness buffer
            if let buffer = cellBrightnessBuffer {
                let ptr = buffer.contents().bindMemory(to: Float.self, capacity: localBarCount * ledRowCount)
                for col in 0..<localBarCount {
                    for row in 0..<ledRowCount {
                        let index = col * ledRowCount + row
                        if col < localCellBrightness.count && row < localCellBrightness[col].count {
                            ptr[index] = localCellBrightness[col][row]
                        } else {
                            ptr[index] = 0
                        }
                    }
                }
            }
            
            // Update peak positions buffer
            if let buffer = peakPositionsBuffer {
                let ptr = buffer.contents().bindMemory(to: Float.self, capacity: localBarCount)
                for col in 0..<localBarCount {
                    ptr[col] = col < localPeakPositions.count ? localPeakPositions[col] : 0
                }
            }
            
        case .ultra:
            // Calculate cell dimensions for Ultra mode - ZERO gaps for seamless gradient
            let ultraCols = ultraBarCount
            let cellSpacing: Float = 0.0  // No gaps at all - completely seamless
            let cellHeight = scaledHeight / Float(ultraLedRowCount)
            let cellWidth = scaledWidth / Float(ultraCols)
            
            // Update Ultra params buffer
            if let buffer = ultraParamsBuffer {
                let ptr = buffer.contents().bindMemory(to: UltraParams.self, capacity: 1)
                ptr.pointee = UltraParams(
                    viewportSize: SIMD2<Float>(scaledWidth, scaledHeight),
                    columnCount: Int32(ultraCols),
                    rowCount: Int32(ultraLedRowCount),
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    cellSpacing: cellSpacing,
                    glowRadius: 4.0,            // Glow spread
                    glowIntensity: 1.0,         // Maximum glow for flashy neon effect
                    reflectionHeight: 0.0,      // No reflection
                    reflectionAlpha: 0.0,
                    time: localAnimationTime
                )
            }
            
            // Update Ultra cell brightness buffer
            if let buffer = ultraCellBrightnessBuffer {
                let ptr = buffer.contents().bindMemory(to: Float.self, capacity: ultraCols * ultraLedRowCount)
                
                for col in 0..<ultraCols {
                    for row in 0..<ultraLedRowCount {
                        let index = col * ultraLedRowCount + row
                        if col < localUltraCellBrightness.count && row < localUltraCellBrightness[col].count {
                            ptr[index] = localUltraCellBrightness[col][row]
                        } else {
                            ptr[index] = 0
                        }
                    }
                }
            }
            
            // Update peak positions buffer for Ultra mode (96 bars)
            if let buffer = peakPositionsBuffer {
                let ptr = buffer.contents().bindMemory(to: Float.self, capacity: ultraCols)
                for col in 0..<ultraCols {
                    ptr[col] = col < localPeakPositions.count ? localPeakPositions[col] : 0
                }
            }
            
        case .winamp:
            // Calculate cell dimensions for Winamp mode - use exact bar width
            let cellSpacing: Float = 1.0 * Float(scale)
            let cellHeight = (scaledHeight - Float(ledRowCount - 1) * cellSpacing) / Float(ledRowCount)
            let cellWidth = Float(localBarWidth * scale)
            
            // Update params buffer for Winamp
            if let buffer = paramsBuffer {
                let ptr = buffer.contents().bindMemory(to: LEDParams.self, capacity: 1)
                ptr.pointee = LEDParams(
                    viewportSize: SIMD2<Float>(scaledWidth, scaledHeight),
                    columnCount: Int32(localBarCount),
                    rowCount: Int32(ledRowCount),
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    cellSpacing: cellSpacing,
                    qualityMode: 0,
                    maxHeight: scaledHeight
                )
            }
            
            // Update heights buffer
            if let buffer = heightBuffer {
                let ptr = buffer.contents().bindMemory(to: Float.self, capacity: localBarCount)
                for i in 0..<min(localBarCount, localSpectrum.count) {
                    ptr[i] = localSpectrum[i]
                }
            }
            
            // Update colors buffer
            if let buffer = colorBuffer {
                let ptr = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 24)
                for (i, color) in localColors.prefix(24).enumerated() {
                    ptr[i] = color
                }
            }
        }
    }
    
    // MARK: - Public API
    
    /// Reset all spectrum state - call when switching audio sources
    func resetState() {
        dataLock.withLock {
            // Clear raw spectrum
            rawSpectrum = []
            
            // Clear display spectrums
            for i in 0..<displaySpectrum.count {
                displaySpectrum[i] = 0
            }
            for i in 0..<ultraDisplaySpectrum.count {
                ultraDisplaySpectrum[i] = 0
            }
            
            // Reset peak positions
            for i in 0..<peakHoldPositions.count {
                peakHoldPositions[i] = 0
            }
            for i in 0..<ultraPeakPositions.count {
                ultraPeakPositions[i] = 0
            }
            
            // Reset cell brightness
            for col in 0..<cellBrightness.count {
                for row in 0..<cellBrightness[col].count {
                    cellBrightness[col][row] = 0
                }
            }
            for col in 0..<ultraCellBrightness.count {
                for row in 0..<ultraCellBrightness[col].count {
                    ultraCellBrightness[col][row] = 0
                }
            }
            
            // Reset peak velocities
            for i in 0..<peakVelocities.count {
                peakVelocities[i] = 0
            }
            
            // Reset idle tracking
            idleFrameCount = 0
            hasClearedAfterIdle = false
            stoppedDueToIdle = false
        }
        NSLog("SpectrumAnalyzerView: State reset")
    }
    
    /// Update spectrum data from audio engine (called from audio thread)
    func updateSpectrum(_ levels: [Float]) {
        // Check if we have any non-zero data
        let hasData = levels.contains { $0 > 0.01 }
        
        // Update raw spectrum and check/reset idle state atomically
        dataLock.withLock {
            rawSpectrum = levels
            
            // Reset idle tracking if we have data
            if hasData {
                stoppedDueToIdle = false
                idleFrameCount = 0
                hasClearedAfterIdle = false
            }
        }
        
        // Check if we need to restart rendering (must check isRendering outside lock
        // to avoid race conditions with async stopRendering calls)
        // This handles: idle timeout, window occlusion recovery, and any other case
        // where the display link stopped but we now have data to display
        if hasData && !isRendering {
            DispatchQueue.main.async { [weak self] in
                self?.startRendering()
            }
        }
    }
    
    /// Update colors from current skin
    func updateColorsFromSkin() {
        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        let nsColors = skin.visColors
        
        // Convert NSColor to SIMD4<Float>
        colorPalette = nsColors.map { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
            rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
        }
        
        // Ensure we have at least 24 colors
        while colorPalette.count < 24 {
            let brightness = Float(colorPalette.count) / 23.0
            colorPalette.append(SIMD4<Float>(0, brightness, 0, 1))
        }
        
        // Sync to render-safe variable
        let colors = colorPalette
        dataLock.withLock {
            renderColorPalette = colors
        }
    }
    
    /// Notify that skin changed
    func skinDidChange() {
        updateColorsFromSkin()
    }
    
    /// Stop the display link (for when window is hidden but not closed)
    func stopDisplayLink() {
        stopRendering()
    }
    
    /// Start the display link (for when window becomes visible)
    func startDisplayLink() {
        startRendering()
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
        metalLayer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            metalLayer?.contentsScale = window?.backingScaleFactor ?? 2.0
            startRendering()
        } else {
            // Window closed - stop the display link to release CPU
            stopRendering()
        }
    }
    
}

// MARK: - Display Link Callback

/// Weak wrapper for safe display link callback - prevents use-after-free crashes
/// when the view is deallocated while the display link callback is still running.
/// The display link callback runs on a background thread and CVDisplayLinkStop()
/// is not synchronous, creating a race condition with deallocation.
private class DisplayLinkContext {
    weak var view: SpectrumAnalyzerView?
    init(view: SpectrumAnalyzerView) {
        self.view = view
    }
}

private func displayLinkCallback(
    displayLink: CVDisplayLink,
    inNow: UnsafePointer<CVTimeStamp>,
    inOutputTime: UnsafePointer<CVTimeStamp>,
    flagsIn: CVOptionFlags,
    flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    displayLinkContext: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context = displayLinkContext else { return kCVReturnError }
    
    // Use retained wrapper with weak view reference to prevent use-after-free
    let wrapper = Unmanaged<DisplayLinkContext>.fromOpaque(context).takeUnretainedValue()
    
    // Safely check if view still exists before rendering
    guard let view = wrapper.view else {
        // View was deallocated - this is expected during shutdown
        return kCVReturnSuccess
    }
    
    view.render()
    
    return kCVReturnSuccess
}
