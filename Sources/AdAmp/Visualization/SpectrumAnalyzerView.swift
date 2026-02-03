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
    case enhanced = "Enhanced"   // Smooth gradients with glow
    
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

// MARK: - Spectrum Parameters (for Metal shader)

/// Parameters passed to the Metal shader
struct SpectrumParams {
    var viewportSize: SIMD2<Float>  // Width, height in pixels
    var barCount: Int32             // Number of bars to render
    var barWidth: Float             // Width of each bar in pixels
    var barSpacing: Float           // Space between bars
    var maxHeight: Float            // Maximum bar height
    var qualityMode: Int32          // 0 = winamp, 1 = enhanced
    var glowIntensity: Float        // Glow effect intensity (enhanced mode)
    var padding: Float = 0          // Alignment padding
}

// MARK: - Spectrum Analyzer View

/// Metal-based spectrum analyzer visualization view
class SpectrumAnalyzerView: NSView {
    
    // MARK: - Configuration
    
    /// Quality mode (Winamp discrete vs Enhanced smooth)
    var qualityMode: SpectrumQualityMode = .winamp {
        didSet {
            UserDefaults.standard.set(qualityMode.rawValue, forKey: "spectrumQualityMode")
        }
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
    
    // Buffers
    private var vertexBuffer: MTLBuffer?
    private var colorBuffer: MTLBuffer?
    private var heightBuffer: MTLBuffer?
    private var paramsBuffer: MTLBuffer?
    
    // MARK: - Display Sync
    
    private var displayLink: CVDisplayLink?
    private var isRendering = false
    
    // MARK: - Thread-Safe Spectrum Data
    // Note: These properties are accessed from both the main thread and the CVDisplayLink callback thread.
    // They are protected by dataLock and marked nonisolated(unsafe) to allow cross-thread access.
    
    private let dataLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private var rawSpectrum: [Float] = []       // From audio engine (75 bands)
    nonisolated(unsafe) private var displaySpectrum: [Float] = []   // After decay smoothing
    nonisolated(unsafe) private var renderBarCount: Int = 19        // Bar count for rendering
    nonisolated(unsafe) private var renderDecayFactor: Float = 0.25 // Decay factor for rendering
    nonisolated(unsafe) private var renderColorPalette: [SIMD4<Float>] = [] // Colors for rendering
    nonisolated(unsafe) private var renderBarWidth: CGFloat = 3.0   // Bar width for rendering
    
    // LED Matrix state tracking (for Enhanced mode)
    nonisolated(unsafe) private var peakHoldPositions: [Float] = []  // Peak hold position per column (0-1)
    nonisolated(unsafe) private var cellBrightness: [[Float]] = []   // Brightness per cell [column][row]
    private let ledRowCount = 16  // Number of LED rows in matrix
    
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
        displaySpectrum = Array(repeating: 0, count: barCount)
        renderBarCount = barCount
        renderDecayFactor = decayMode.decayFactor
        renderBarWidth = barWidth
        
        // Set up Metal
        setupMetal()
        
        // Load colors from current skin
        updateColorsFromSkin()
        
        // Start rendering
        startRendering()
    }
    
    deinit {
        stopRendering()
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
        layer?.addSublayer(metalLayer)
        
        // Load shaders and create pipeline
        setupPipeline()
        
        // Create buffers
        setupBuffers()
    }
    
    private func setupPipeline() {
        guard let device = device else { return }
        
        // Try to load the shader library from the bundle
        // First try the default library (built into app), then try loading from file
        var library: MTLLibrary?
        
        // Try loading from default library first
        library = device.makeDefaultLibrary()
        
        if library == nil {
            // Try loading from the bundle
            if let libraryURL = BundleHelper.url(forResource: "default", withExtension: "metallib") {
                library = try? device.makeLibrary(URL: libraryURL)
            }
        }
        
        guard let library = library else {
            NSLog("SpectrumAnalyzerView: Failed to load Metal shader library - will use fallback rendering")
            return
        }
        
        guard let vertexFunction = library.makeFunction(name: "spectrum_vertex"),
              let fragmentFunction = library.makeFunction(name: "spectrum_fragment") else {
            NSLog("SpectrumAnalyzerView: Failed to find shader functions")
            return
        }
        
        // Create pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Spectrum Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // Enable blending for glow effect
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            NSLog("SpectrumAnalyzerView: Failed to create pipeline state: \(error)")
        }
    }
    
    private func setupBuffers() {
        guard let device = device else { return }
        
        // Heights buffer (updated each frame)
        let maxBars = 64  // Support up to 64 bars
        heightBuffer = device.makeBuffer(length: maxBars * MemoryLayout<Float>.stride, options: .storageModeShared)
        
        // Colors buffer (24 colors for Winamp palette)
        let maxColors = 24
        colorBuffer = device.makeBuffer(length: maxColors * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
        
        // Params buffer
        paramsBuffer = device.makeBuffer(length: MemoryLayout<SpectrumParams>.stride, options: .storageModeShared)
    }
    
    // MARK: - Display Link
    
    private func startRendering() {
        guard !isRendering else { return }
        isRendering = true
        
        // Create display link
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        
        guard let displayLink = link else {
            NSLog("SpectrumAnalyzerView: Failed to create display link")
            return
        }
        
        self.displayLink = displayLink
        
        // Set output callback
        let callbackPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
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
    }
    
    // MARK: - Rendering
    
    /// Called by display link at 60Hz
    /// Note: This is internal (not private) so the display link callback can access it
    func render() {
        guard isRendering, let metalLayer = metalLayer else { return }
        
        // Update display spectrum with decay
        updateDisplaySpectrum()
        
        // Get drawable
        guard let drawable = metalLayer.nextDrawable() else { return }
        
        // If Metal pipeline isn't ready, use fallback
        guard let pipelineState = pipelineState,
              let commandBuffer = commandQueue?.makeCommandBuffer() else {
            // Fallback to Core Graphics rendering
            DispatchQueue.main.async { [weak self] in
                self?.needsDisplay = true
            }
            return
        }
        
        // Create render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // Update buffers
        updateBuffers()
        
        // Set pipeline state
        encoder.setRenderPipelineState(pipelineState)
        
        // Set buffers
        if let heightBuffer = heightBuffer {
            encoder.setVertexBuffer(heightBuffer, offset: 0, index: 0)
        }
        if let paramsBuffer = paramsBuffer {
            encoder.setVertexBuffer(paramsBuffer, offset: 0, index: 1)
        }
        if let colorBuffer = colorBuffer {
            encoder.setFragmentBuffer(colorBuffer, offset: 0, index: 0)
        }
        if let paramsBuffer = paramsBuffer {
            encoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 1)
        }
        
        // Draw bars (6 vertices per bar - 2 triangles)
        // Use render-safe bar count
        var localBarCount: Int = 0
        dataLock.withLock {
            localBarCount = renderBarCount
        }
        let vertexCount = localBarCount * 6
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func updateDisplaySpectrum() {
        dataLock.withLock {
            let decay = renderDecayFactor
            let outputCount = renderBarCount
            
            // Map raw spectrum to display bars
            if rawSpectrum.isEmpty {
                // Decay existing values when no input
                for i in 0..<displaySpectrum.count {
                    displaySpectrum[i] *= decay
                    if displaySpectrum[i] < 0.01 {
                        displaySpectrum[i] = 0
                    }
                }
            } else {
                // Map input bands to display bars
                let inputCount = rawSpectrum.count
                
                // Ensure displaySpectrum has correct size
                if displaySpectrum.count != outputCount {
                    displaySpectrum = Array(repeating: 0, count: outputCount)
                }
                
                // Match main window's spectrum mapping exactly (simple averaging, no processing)
                // Scale factor leaves visual headroom at top (0.95 = peaks show at 95% height)
                let displayScale: Float = 0.95
                
                if inputCount >= outputCount {
                    // Average multiple input bands into each display bar
                    let bandsPerBar = inputCount / outputCount
                    for barIndex in 0..<outputCount {
                        let start = barIndex * bandsPerBar
                        let end = min(start + bandsPerBar, inputCount)
                        var sum: Float = 0
                        for i in start..<end {
                            sum += rawSpectrum[i]
                        }
                        let newValue = (sum / Float(end - start)) * displayScale
                        
                        // Apply decay
                        if newValue > displaySpectrum[barIndex] {
                            displaySpectrum[barIndex] = newValue  // Fast attack
                        } else {
                            displaySpectrum[barIndex] = displaySpectrum[barIndex] * decay + newValue * (1 - decay)
                        }
                    }
                } else {
                    // Interpolate when fewer input bands than display bars
                    for barIndex in 0..<outputCount {
                        let sourceIndex = Float(barIndex) * Float(inputCount - 1) / Float(outputCount - 1)
                        let lowerIndex = Int(sourceIndex)
                        let upperIndex = min(lowerIndex + 1, inputCount - 1)
                        let fraction = sourceIndex - Float(lowerIndex)
                        let newValue = (rawSpectrum[lowerIndex] * (1 - fraction) + rawSpectrum[upperIndex] * fraction) * displayScale
                        
                        // Apply decay
                        if newValue > displaySpectrum[barIndex] {
                            displaySpectrum[barIndex] = newValue
                        } else {
                            displaySpectrum[barIndex] = displaySpectrum[barIndex] * decay + newValue * (1 - decay)
                        }
                    }
                }
            }
            
            // Update LED matrix state (for Enhanced mode)
            updateLEDMatrixState()
        }
    }
    
    /// Updates peak hold positions and per-cell brightness for LED matrix mode
    private func updateLEDMatrixState() {
        let colCount = renderBarCount
        
        // Initialize arrays if needed
        if peakHoldPositions.count != colCount {
            peakHoldPositions = Array(repeating: 0, count: colCount)
        }
        if cellBrightness.count != colCount {
            cellBrightness = Array(repeating: Array(repeating: Float(0), count: ledRowCount), count: colCount)
        }
        
        let peakDecayRate: Float = 0.012      // How fast peak falls (per frame)
        let peakHoldFrames: Float = 0.985     // Slight delay before peak starts falling
        let cellFadeRate: Float = 0.025       // How fast cells fade out (slower = longer trails)
        
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
            
            // Update per-cell brightness
            for row in 0..<ledRowCount {
                if row < currentRow {
                    // Cell is currently lit - set to full brightness
                    cellBrightness[col][row] = 1.0
                } else {
                    // Cell is not lit - fade out
                    cellBrightness[col][row] = max(0, cellBrightness[col][row] - cellFadeRate)
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
        
        dataLock.withLock {
            localBarCount = renderBarCount
            localBarWidth = renderBarWidth
            localColors = renderColorPalette
            localSpectrum = displaySpectrum
        }
        
        // Update heights buffer
        if let heightBuffer = heightBuffer {
            let heights = heightBuffer.contents().bindMemory(to: Float.self, capacity: localBarCount)
            for i in 0..<min(localBarCount, localSpectrum.count) {
                heights[i] = localSpectrum[i]
            }
        }
        
        // Update colors buffer
        if let colorBuffer = colorBuffer {
            let colors = colorBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 24)
            for (i, color) in localColors.prefix(24).enumerated() {
                colors[i] = color
            }
        }
        
        // Update params buffer (these view properties are accessed from render thread - but since
        // CVDisplayLink runs on the main thread in macOS, this is safe)
        if let paramsBuffer = paramsBuffer {
            let params = paramsBuffer.contents().bindMemory(to: SpectrumParams.self, capacity: 1)
            let scale = metalLayer?.contentsScale ?? 1.0
            params.pointee = SpectrumParams(
                viewportSize: SIMD2<Float>(Float(bounds.width * scale), Float(bounds.height * scale)),
                barCount: Int32(localBarCount),
                barWidth: Float(localBarWidth * scale),
                barSpacing: Float(barSpacing * scale),
                maxHeight: Float(bounds.height * scale),
                qualityMode: qualityMode == .winamp ? 0 : 1,
                glowIntensity: glowIntensity
            )
        }
    }
    
    // MARK: - Public API
    
    /// Update spectrum data from audio engine (called from audio thread)
    func updateSpectrum(_ levels: [Float]) {
        dataLock.withLock {
            rawSpectrum = levels
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
        }
    }
    
    // MARK: - Fallback Drawing (Core Graphics)
    
    override func draw(_ dirtyRect: NSRect) {
        guard pipelineState == nil else { return }  // Only use fallback if Metal isn't available
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Clear background
        context.clear(bounds)
        
        // Get render-safe values (all in one lock to avoid deadlock)
        var localBarCount: Int = 0
        var localBarWidth: CGFloat = 0
        var localColors: [SIMD4<Float>] = []
        var localSpectrum: [Float] = []
        var localPeakPositions: [Float] = []
        var localCellBrightness: [[Float]] = []
        
        dataLock.withLock {
            localBarCount = renderBarCount
            localBarWidth = renderBarWidth
            localColors = renderColorPalette
            localSpectrum = displaySpectrum
            localPeakPositions = peakHoldPositions
            localCellBrightness = cellBrightness
        }
        
        let maxHeight = bounds.height
        let totalBarWidth = localBarWidth + barSpacing
        
        if qualityMode == .winamp {
            // === WINAMP MODE: Classic discrete pixel-art aesthetic ===
            // Draw in color bands (more efficient than pixel-by-pixel)
            let bandCount = min(24, localColors.count)
            let bandHeight = maxHeight / CGFloat(bandCount)
            
            for (i, level) in localSpectrum.prefix(localBarCount).enumerated() {
                let barX = CGFloat(i) * totalBarWidth
                let barHeight = CGFloat(level) * maxHeight
                
                guard barHeight > 0 else { continue }
                
                // Draw color bands from bottom to top
                for band in 0..<bandCount {
                    let bandY = CGFloat(band) * bandHeight
                    let bandTop = bandY + bandHeight
                    
                    // Skip bands above the bar height
                    if bandY >= barHeight { break }
                    
                    // Clip band to bar height
                    let clippedHeight = min(bandHeight, barHeight - bandY)
                    
                    let colorIndex = min(localColors.count - 1, band)
                    let color = localColors[colorIndex]
                    context.setFillColor(CGColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w)))
                    
                    let bandRect = CGRect(x: barX, y: bandY, width: localBarWidth, height: clippedHeight)
                    context.fill(bandRect)
                }
            }
        } else {
            // === ENHANCED MODE: LED Matrix with floating peaks and per-cell fade ===
            
            // LED matrix configuration
            let cellSpacing: CGFloat = 2.0  // Gap between cells
            let cellCornerRadius: CGFloat = 2.0
            let rowCount = ledRowCount
            let cellHeight = (maxHeight - CGFloat(rowCount - 1) * cellSpacing) / CGFloat(rowCount)
            let cellWidth = localBarWidth - 1  // Slightly narrower than bar spacing
            
            // localPeakPositions and localCellBrightness already fetched above
            
            // Rainbow color palette for columns (hue varies by column position)
            func rainbowColor(forColumn col: Int, totalColumns: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
                let hue = CGFloat(col) / CGFloat(totalColumns)
                
                // HSV to RGB conversion (full saturation, full value)
                let h = hue * 6.0
                let sector = Int(h)
                let f = h - CGFloat(sector)
                let q = 1.0 - f
                let t = f
                
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                switch sector % 6 {
                case 0: r = 1; g = t; b = 0      // Red -> Yellow
                case 1: r = q; g = 1; b = 0      // Yellow -> Green
                case 2: r = 0; g = 1; b = t      // Green -> Cyan
                case 3: r = 0; g = q; b = 1      // Cyan -> Blue
                case 4: r = t; g = 0; b = 1      // Blue -> Magenta
                case 5: r = 1; g = 0; b = q      // Magenta -> Red
                default: break
                }
                
                return (r, g, b)
            }
            
            // Draw each column
            for col in 0..<localBarCount {
                let colX = CGFloat(col) * totalBarWidth
                
                // Get column color from rainbow
                let baseColor = rainbowColor(forColumn: col, totalColumns: localBarCount)
                
                // Get current bar level and peak position
                let currentLevel = col < localSpectrum.count ? localSpectrum[col] : 0
                let currentBarRow = Int(CGFloat(currentLevel) * CGFloat(rowCount))
                
                let peakPosition = col < localPeakPositions.count ? localPeakPositions[col] : 0
                let peakRow = min(rowCount - 1, Int(peakPosition * Float(rowCount)))
                
                // Draw all lit cells in this column
                for row in 0..<rowCount {
                    let cellY = CGFloat(row) * (cellHeight + cellSpacing)
                    let cellRect = CGRect(x: colX, y: cellY, width: cellWidth, height: cellHeight)
                    
                    // Get cell brightness from state (each cell fades independently)
                    var brightness: Float = 0
                    if col < localCellBrightness.count && row < localCellBrightness[col].count {
                        brightness = localCellBrightness[col][row]
                    }
                    
                    // Check if this is the peak row (always draw peak)
                    let isPeakCell = (row == peakRow) && peakRow > 0
                    
                    if brightness > 0.01 || isPeakCell {
                        // For peak cell, use full brightness
                        let displayBrightness: CGFloat = isPeakCell ? 1.0 : CGFloat(brightness)
                        
                        var r = baseColor.r * displayBrightness
                        var g = baseColor.g * displayBrightness
                        var b = baseColor.b * displayBrightness
                        
                        // Peak cells are extra bright with white tint
                        if isPeakCell {
                            r = min(1.0, baseColor.r + 0.4)
                            g = min(1.0, baseColor.g + 0.4)
                            b = min(1.0, baseColor.b + 0.4)
                        }
                        
                        // Draw LED cell
                        context.saveGState()
                        
                        // Main cell body with rounded corners
                        let cellPath = CGPath(roundedRect: cellRect, cornerWidth: cellCornerRadius, cornerHeight: cellCornerRadius, transform: nil)
                        context.addPath(cellPath)
                        context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1.0))
                        context.fillPath()
                        
                        // 3D highlight on upper portion
                        let highlightRect = CGRect(x: colX + 1, y: cellY + cellHeight * 0.5, width: cellWidth - 2, height: cellHeight * 0.45)
                        let hlAlpha: CGFloat = isPeakCell ? 0.7 : 0.4 * displayBrightness
                        
                        let hlR = min(1.0, r * 1.3 + 0.2)
                        let hlG = min(1.0, g * 1.3 + 0.2)
                        let hlB = min(1.0, b * 1.3 + 0.2)
                        context.setFillColor(CGColor(red: hlR, green: hlG, blue: hlB, alpha: hlAlpha))
                        context.fill(highlightRect)
                        
                        // White shine spot (more prominent on peak)
                        let shineAlpha: CGFloat = isPeakCell ? 0.5 : 0.25 * displayBrightness
                        let shineRect = CGRect(x: colX + 1.5, y: cellY + cellHeight * 0.6, width: cellWidth * 0.35, height: cellHeight * 0.3)
                        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: shineAlpha))
                        context.fillEllipse(in: shineRect)
                        
                        // Bottom shadow for depth
                        if displayBrightness > 0.3 {
                            let shadowRect = CGRect(x: colX + 1, y: cellY + 1, width: cellWidth - 2, height: cellHeight * 0.2)
                            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.2))
                            context.fill(shadowRect)
                        }
                        
                        context.restoreGState()
                    }
                }
            }
        }
    }
}

// MARK: - Display Link Callback

private func displayLinkCallback(
    displayLink: CVDisplayLink,
    inNow: UnsafePointer<CVTimeStamp>,
    inOutputTime: UnsafePointer<CVTimeStamp>,
    flagsIn: CVOptionFlags,
    flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    displayLinkContext: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context = displayLinkContext else { return kCVReturnError }
    
    let view = Unmanaged<SpectrumAnalyzerView>.fromOpaque(context).takeUnretainedValue()
    view.render()
    
    return kCVReturnSuccess
}
