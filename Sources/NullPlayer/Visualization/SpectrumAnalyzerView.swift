import MetalKit
import os.lock

// =============================================================================
// SPECTRUM ANALYZER VIEW - Metal-based real-time audio visualization
// =============================================================================
// A GPU-accelerated spectrum analyzer that supports two quality modes:
// - Classic: Discrete color palette, pixel-art aesthetic
// - Enhanced: Smooth gradients with optional glow effect
//
// Uses CADisplayLink for 60Hz rendering synchronized to the display refresh.
// Thread-safe spectrum data updates via OSAllocatedUnfairLock.
// =============================================================================

// MARK: - Enums

/// Quality mode for spectrum analyzer rendering
enum SpectrumQualityMode: String, CaseIterable {
    case classic = "Classic"     // Discrete colors, pixel-art aesthetic
    case enhanced = "Enhanced"   // LED matrix with rainbow
    case ultra = "Ultra"         // Maximum visual quality with effects
    case flame = "Fire"          // GPU fire simulation driven by audio
    case cosmic = "JWST"         // Procedural nebula inspired by JWST Pillars of Creation
    case electricity = "Lightning" // GPU lightning storm driven by peak frequencies
    case matrix = "Matrix"           // Falling digital rain driven by spectrum
    
    var displayName: String { rawValue }
    
    /// The Metal shader file required for this mode.
    /// Returns nil if the mode shares a shader already checked by another mode.
    var requiredShaderFile: String {
        switch self {
        case .classic, .enhanced, .ultra: return "SpectrumShaders"
        case .flame: return "FlameShaders"
        case .cosmic: return "CosmicShaders"
        case .electricity: return "ElectricityShaders"
        case .matrix: return "MatrixShaders"
        }
    }
}

/// Visual style presets for Flame mode
enum FlameStyle: String, CaseIterable {
    case inferno = "Inferno"
    case aurora = "Aurora"
    case electric = "Electric"
    case ocean = "Ocean"
    var displayName: String { rawValue }
    var colorScheme: Int32 {
        switch self { case .inferno: return 0; case .aurora: return 1; case .electric: return 2; case .ocean: return 3 }
    }
    var buoyancy: Float {
        switch self { case .inferno: return 6.0; case .aurora: return 3.5; case .electric: return 8.0; case .ocean: return 4.0 }
    }
    var cooling: Float {
        switch self { case .inferno: return 0.28; case .aurora: return 0.17; case .electric: return 0.38; case .ocean: return 0.14 }
    }
    var turbulence: Float {
        switch self { case .inferno: return 2.0; case .aurora: return 1.2; case .electric: return 3.0; case .ocean: return 0.8 }
    }
    var diffusion: Float {
        switch self { case .inferno: return 0.04; case .aurora: return 0.08; case .electric: return 0.02; case .ocean: return 0.1 }
    }
    var windStrength: Float {
        switch self { case .inferno: return 1.2; case .aurora: return 2.5; case .electric: return 1.8; case .ocean: return 1.0 }
    }
    var emberRate: Float {
        switch self { case .inferno: return 0.002; case .aurora: return 0.001; case .electric: return 0.004; case .ocean: return 0.001 }
    }
}

/// Fire intensity presets controlling how aggressively the flame reacts to music
enum FlameIntensity: String, CaseIterable {
    case mellow = "Mellow"     // Gentle, ambient flame with smooth transitions
    case intense = "Intense"   // Punchy, beat-reactive flame with sharp spikes
    
    var displayName: String { rawValue }
    
    /// Shader intensity value (used by FlameShaders.metal to select burst params)
    var shaderValue: Float {
        switch self { case .mellow: return 1.0; case .intense: return 2.0 }
    }
    
    /// Smoothing attack speed (how fast flame jumps on beats)
    var attackSpeed: Float {
        switch self { case .mellow: return 0.3; case .intense: return 0.5 }
    }
    
    /// Smoothing release speed (how fast flame drops between beats)
    var releaseSpeed: Float {
        switch self { case .mellow: return 0.05; case .intense: return 0.12 }
    }
}

/// Parameters for Flame Metal shaders (must match Metal FlameParams struct)
struct FlameParams {
    var gridSize: SIMD2<Float>
    var viewportSize: SIMD2<Float>
    var time: Float
    var dt: Float
    var bassEnergy: Float
    var midEnergy: Float
    var trebleEnergy: Float
    var buoyancy: Float
    var cooling: Float
    var turbulence: Float
    var diffusion: Float
    var windStrength: Float
    var colorScheme: Int32
    var intensity: Float
    var emberRate: Float
    var padding: Float = 0
}

/// Parameters for Cosmic Metal shaders (must match Metal CosmicParams struct)
struct CosmicParams {
    var viewportSize: SIMD2<Float>  // 8 bytes (offset 0)
    var time: Float                  // 4 bytes (offset 8) - real clock time
    var scrollOffset: Float          // 4 bytes (offset 12) - music-speed-integrated drift
    var bassEnergy: Float            // 4 bytes (offset 16)
    var midEnergy: Float             // 4 bytes (offset 20)
    var trebleEnergy: Float          // 4 bytes (offset 24)
    var totalEnergy: Float           // 4 bytes (offset 28)
    var beatIntensity: Float         // 4 bytes (offset 32)
    var flareIntensity: Float = 0    // 4 bytes (offset 36) - big JWST flare on rare peaks
    var flareScroll: Float = 0       // 4 bytes (offset 40) - scroll snapshot when giant fired
    var brightnessBoost: Float = 1.0 // 4 bytes (offset 44) → total 48
}

/// Visual style presets for Lightning mode
enum LightningStyle: String, CaseIterable {
    case classic = "Classic"       // White/blue/violet — classic lightning
    case plasma = "Plasma"         // Hot pink/magenta/cyan
    case matrix = "Matrix"         // Green/emerald digital
    case ember = "Ember"           // Orange/red/gold — heat lightning
    case arctic = "Arctic"         // Ice blue/white/pale cyan
    case rainbow = "Rainbow"       // Each bolt a different vivid color
    case neon = "Neon"             // Hot pink, cyan, yellow mix
    case aurora = "Aurora"         // Green, purple, blue shifting
    var displayName: String { rawValue }
    var colorScheme: Int32 {
        switch self {
        case .classic: return 0; case .plasma: return 1; case .matrix: return 2
        case .ember: return 3; case .arctic: return 4; case .rainbow: return 5
        case .neon: return 6; case .aurora: return 7
        }
    }
}

/// Parameters for Electricity Metal shaders (must match Metal ElectricityParams struct)
struct ElectricityParams {
    var viewportSize: SIMD2<Float>  // 8 bytes (offset 0)
    var time: Float                  // 4 bytes (offset 8)
    var bassEnergy: Float            // 4 bytes (offset 12)
    var midEnergy: Float             // 4 bytes (offset 16)
    var trebleEnergy: Float          // 4 bytes (offset 20)
    var totalEnergy: Float           // 4 bytes (offset 24)
    var beatIntensity: Float         // 4 bytes (offset 28)
    var dramaticIntensity: Float     // 4 bytes (offset 32) - rare dramatic strike
    var colorScheme: Int32 = 0       // 4 bytes (offset 36) - lightning color palette
    var brightnessBoost: Float = 1.0 // 4 bytes (offset 40) → total 44
}

/// Color scheme presets for Matrix mode
enum MatrixColorScheme: String, CaseIterable {
    case classic = "Classic"     // Iconic green
    case amber = "Amber"         // Retro terminal orange
    case bluePill = "Blue Pill"  // Cool cyan/blue
    case bloodshot = "Bloodshot" // Crimson red
    case neon = "Neon"           // Cyberpunk magenta/pink
    var displayName: String { rawValue }
    var colorScheme: Int32 {
        switch self {
        case .classic: return 0; case .amber: return 1; case .bluePill: return 2
        case .bloodshot: return 3; case .neon: return 4
        }
    }
}

/// Intensity presets for Matrix mode
enum MatrixIntensity: String, CaseIterable {
    case subtle = "Subtle"     // Sparse rain, gentle glow, zen-like
    case intense = "Intense"   // Dense rain, strong glow, punchy beats
    var displayName: String { rawValue }
    var shaderValue: Float {
        switch self { case .subtle: return 1.0; case .intense: return 2.0 }
    }
    var attackSpeed: Float {
        switch self { case .subtle: return 0.3; case .intense: return 0.45 }
    }
    var releaseSpeed: Float {
        switch self { case .subtle: return 0.06; case .intense: return 0.12 }
    }
}

/// Parameters for Matrix Metal shaders (must match Metal MatrixParams struct)
struct MatrixParams {
    var viewportSize: SIMD2<Float>  // 8 bytes (offset 0)
    var time: Float                  // 4 bytes (offset 8)
    var bassEnergy: Float            // 4 bytes (offset 12)
    var midEnergy: Float             // 4 bytes (offset 16)
    var trebleEnergy: Float          // 4 bytes (offset 20)
    var totalEnergy: Float           // 4 bytes (offset 24)
    var beatIntensity: Float         // 4 bytes (offset 28)
    var dramaticIntensity: Float     // 4 bytes (offset 32) - rare awakening flash
    var scrollOffset: Float          // 4 bytes (offset 36)
    var colorScheme: Int32 = 0       // 4 bytes (offset 40) - matrix color palette
    var intensity: Float = 1.0       // 4 bytes (offset 44) - 1.0=subtle, 2.0=intense
    var brightnessBoost: Float = 1.0 // 4 bytes (offset 48) → total 52 (padded to 56)
}

/// Decay mode controlling how quickly bars fall
enum SpectrumDecayMode: String, CaseIterable {
    case instant = "Instant"     // No smoothing, immediate response
    case snappy = "Snappy"       // 25% retention - fast and punchy
    case balanced = "Balanced"   // 40% retention - good middle ground
    case smooth = "Smooth"       // 55% retention - original Classic feel
    
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
/// Total size: 44 bytes
struct LEDParams {
    var viewportSize: SIMD2<Float>  // 8 bytes (offset 0)
    var columnCount: Int32          // 4 bytes (offset 8)
    var rowCount: Int32             // 4 bytes (offset 12)
    var cellWidth: Float            // 4 bytes (offset 16)
    var cellHeight: Float           // 4 bytes (offset 20)
    var cellSpacing: Float          // 4 bytes (offset 24)
    var qualityMode: Int32          // 4 bytes (offset 28)
    var maxHeight: Float            // 4 bytes (offset 32)
    var time: Float = 0             // 4 bytes (offset 36) - animation time in seconds
    var brightnessBoost: Float = 1.0 // 4 bytes (offset 40) - brightness multiplier
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
    var brightnessBoost: Float = 1.0 // 4 bytes (offset 48) - brightness multiplier
    var padding: Float = 0          // 4 bytes (offset 52) - alignment to 56
}

// MARK: - Spectrum Analyzer View

/// Metal-based spectrum analyzer visualization view
class SpectrumAnalyzerView: NSView {
    
    // MARK: - Shader Availability
    
    /// Check if the Metal shader file for a given mode is available in the app bundle.
    /// This is a static check that works without a SpectrumAnalyzerView instance, making it
    /// safe to call from MainWindowView/ModernMainWindowView before the overlay is created.
    static func isShaderAvailable(for mode: SpectrumQualityMode) -> Bool {
        return BundleHelper.url(forResource: mode.requiredShaderFile, withExtension: "metal") != nil
    }
    
    /// Check if the Metal render pipeline for a given mode was successfully created.
    /// Only valid after setupMetal() has run. Use isShaderAvailable() for pre-init checks.
    private func isPipelineAvailable(for mode: SpectrumQualityMode) -> Bool {
        switch mode {
        case .classic: return barPipelineState != nil
        case .enhanced: return ledPipelineState != nil
        case .ultra: return ultraPipelineState != nil
        case .flame: return flamePropPipeline != nil && flameRenderPipeline != nil
        case .cosmic: return cosmicRenderPipeline != nil
        case .electricity: return electricityRenderPipeline != nil
        case .matrix: return matrixRenderPipeline != nil
        }
    }
    
    // MARK: - Configuration
    
    /// When true, this view is embedded in another window (e.g., main window flame overlay).
    /// Embedded views do NOT persist quality/decay mode to UserDefaults and do NOT
    /// respond to SpectrumSettingsChanged notifications for quality mode changes.
    /// This prevents cross-contamination between the standalone spectrum window and the overlay.
    var isEmbedded: Bool = false
    
    /// UserDefaults key used to read normalization mode each frame.
    /// Defaults to "spectrumNormalizationMode" for the standalone spectrum window.
    /// Embedded views (e.g., main window overlay) should set this to their own key
    /// (e.g., "mainWindowNormalizationMode") to avoid cross-contamination.
    var normalizationUserDefaultsKey: String = "spectrumNormalizationMode"
    
    /// Quality mode (Classic discrete vs Enhanced smooth vs Ultra high-quality)
    var qualityMode: SpectrumQualityMode = .classic {
        didSet {
            if !isEmbedded {
                UserDefaults.standard.set(qualityMode.rawValue, forKey: "spectrumQualityMode")
            }
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
            if !isEmbedded {
                UserDefaults.standard.set(decayMode.rawValue, forKey: "spectrumDecayMode")
            }
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
    
    /// Brightness multiplier for all GPU-rendered modes (1.0 = default, >1.0 = brighter).
    /// Used to boost brightness when the view is embedded at small sizes (e.g., main window vis area).
    var brightnessBoost: Float = 1.0
    
    /// Bass energy attenuation factor (1.0 = full bass, <1.0 = reduced bass influence).
    /// Used to tame bass-heavy visuals in small embedded views where bass dominates.
    var bassAttenuation: Float = 1.0
    
    /// Current lightning style preset (only used when qualityMode == .electricity)
    var lightningStyle: LightningStyle = .classic {
        didSet {
            if !isEmbedded {
                UserDefaults.standard.set(lightningStyle.rawValue, forKey: "lightningStyle")
            }
            let style = lightningStyle
            dataLock.withLock { renderLightningStyle = style }
        }
    }
    
    /// Current matrix color scheme (only used when qualityMode == .matrix)
    var matrixColorScheme: MatrixColorScheme = .classic {
        didSet {
            if !isEmbedded {
                UserDefaults.standard.set(matrixColorScheme.rawValue, forKey: "matrixColorScheme")
            }
            let scheme = matrixColorScheme
            dataLock.withLock { renderMatrixColorScheme = scheme }
        }
    }
    
    /// Current matrix intensity preset (only used when qualityMode == .matrix)
    var matrixIntensity: MatrixIntensity = .subtle {
        didSet {
            if !isEmbedded {
                UserDefaults.standard.set(matrixIntensity.rawValue, forKey: "matrixIntensity")
            }
            let intensity = matrixIntensity
            dataLock.withLock { renderMatrixIntensity = intensity }
        }
    }
    
    /// Current flame style preset (only used when qualityMode == .flame)
    var flameStyle: FlameStyle = .inferno {
        didSet {
            if !isEmbedded {
                UserDefaults.standard.set(flameStyle.rawValue, forKey: "flameStyle")
            }
            let style = flameStyle
            dataLock.withLock { renderFlameStyle = style }
        }
    }
    
    /// Current flame intensity preset (only used when qualityMode == .flame)
    var flameIntensity: FlameIntensity = .mellow {
        didSet {
            if !isEmbedded {
                UserDefaults.standard.set(flameIntensity.rawValue, forKey: "flameIntensity")
            }
            let intensity = flameIntensity
            dataLock.withLock { renderFlameIntensity = intensity }
        }
    }
    
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
    
    // Cosmic mode resources
    private var cosmicRenderPipeline: MTLRenderPipelineState?
    private var cosmicParamsBuffer: MTLBuffer?
    
    // Electricity mode resources
    private var electricityRenderPipeline: MTLRenderPipelineState?
    private var electricityParamsBuffer: MTLBuffer?
    
    // Matrix mode resources
    private var matrixRenderPipeline: MTLRenderPipelineState?
    private var matrixParamsBuffer: MTLBuffer?
    
    // Flame mode resources
    private var flamePropPipeline: MTLComputePipelineState?
    private var flameRenderPipeline: MTLRenderPipelineState?
    private var flameSimTextureA: MTLTexture?
    private var flameSimTextureB: MTLTexture?
    private var flameSpectrumBuffer: MTLBuffer?
    private var flameParamsBuffer: MTLBuffer?
    private let flameGridWidth: Int = 128
    private let flameGridHeight: Int = 96
    nonisolated(unsafe) private var flameCurrentTex: Int = 0
    
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
    nonisolated(unsafe) private var displaySpectrum: [Float] = []   // After decay smoothing (Enhanced/Classic)
    nonisolated(unsafe) private var ultraDisplaySpectrum: [Float] = []  // After decay smoothing (Ultra mode - 96 bars)
    nonisolated(unsafe) private var renderBarCount: Int = 19        // Bar count for rendering
    nonisolated(unsafe) private var renderDecayFactor: Float = 0.25 // Decay factor for rendering
    nonisolated(unsafe) private var renderColorPalette: [SIMD4<Float>] = [] // Colors for rendering
    nonisolated(unsafe) private var renderBarWidth: CGFloat = 3.0   // Bar width for rendering
    nonisolated(unsafe) private var renderQualityMode: SpectrumQualityMode = .classic // Quality mode for rendering
    
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
    
    // Cosmic mode state
    nonisolated(unsafe) private var cosmicSmoothBass: Float = 0
    nonisolated(unsafe) private var cosmicSmoothMid: Float = 0
    nonisolated(unsafe) private var cosmicSmoothTreble: Float = 0
    nonisolated(unsafe) private var cosmicBeatIntensity: Float = 0
    nonisolated(unsafe) private var cosmicScrollOffset: Float = 0
    nonisolated(unsafe) private var cosmicFlareIntensity: Float = 0
    nonisolated(unsafe) private var cosmicFlareCooldown: Int = 0  // Frames until next flare allowed
    nonisolated(unsafe) private var cosmicFlareScrollSnapshot: Float = 0  // Scroll position when giant fired
    nonisolated(unsafe) private var cosmicFlareLPF: Float = 0  // Low-pass filtered energy for giant detection
    
    // Electricity mode state
    nonisolated(unsafe) private var electricitySmoothBass: Float = 0
    nonisolated(unsafe) private var electricitySmoothMid: Float = 0
    nonisolated(unsafe) private var electricitySmoothTreble: Float = 0
    nonisolated(unsafe) private var electricityBeatIntensity: Float = 0
    nonisolated(unsafe) private var electricityDramaticIntensity: Float = 0  // Rare dramatic strike (like JWST giant flare)
    nonisolated(unsafe) private var electricityDramaticLPF: Float = 0  // Slow-moving energy baseline for peak detection
    nonisolated(unsafe) private var electricityDramaticCooldown: Int = 0  // Frames until next dramatic strike allowed
    nonisolated(unsafe) private var renderLightningStyle: LightningStyle = .classic
    
    // Matrix mode state
    nonisolated(unsafe) private var matrixSmoothBass: Float = 0
    nonisolated(unsafe) private var matrixSmoothMid: Float = 0
    nonisolated(unsafe) private var matrixSmoothTreble: Float = 0
    nonisolated(unsafe) private var matrixBeatIntensity: Float = 0
    nonisolated(unsafe) private var matrixScrollOffset: Float = 0
    nonisolated(unsafe) private var matrixDramaticIntensity: Float = 0  // Rare awakening flash
    nonisolated(unsafe) private var matrixDramaticLPF: Float = 0  // Slow-moving energy baseline
    nonisolated(unsafe) private var matrixDramaticCooldown: Int = 0  // Frames until next dramatic allowed
    nonisolated(unsafe) private var renderMatrixColorScheme: MatrixColorScheme = .classic
    nonisolated(unsafe) private var renderMatrixIntensity: MatrixIntensity = .subtle
    
    // Flame mode state
    nonisolated(unsafe) private var renderFlameStyle: FlameStyle = .inferno
    nonisolated(unsafe) private var renderFlameIntensity: FlameIntensity = .mellow
    nonisolated(unsafe) private var flameSmoothBass: Float = 0
    nonisolated(unsafe) private var flameSmoothMid: Float = 0
    nonisolated(unsafe) private var flameSmoothTreble: Float = 0
    
    // MARK: - Color Palette
    
    /// Current skin's visualization colors (24 colors, updated on skin change)
    private var colorPalette: [SIMD4<Float>] = []
    
    /// Optional color override for the modern skin system.
    /// When set, these colors are used instead of the classic skin's visColors.
    var spectrumColors: [NSColor]? {
        didSet {
            if spectrumColors != nil {
                applySpectrumColorOverride()
            } else {
                updateColorsFromSkin()
            }
        }
    }
    
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
        
        if let saved = UserDefaults.standard.string(forKey: "flameStyle"),
           let style = FlameStyle(rawValue: saved) {
            flameStyle = style
        }
        if let saved = UserDefaults.standard.string(forKey: "flameIntensity"),
           let intensity = FlameIntensity(rawValue: saved) {
            flameIntensity = intensity
        }
        renderFlameStyle = flameStyle
        renderFlameIntensity = flameIntensity
        
        if let saved = UserDefaults.standard.string(forKey: "lightningStyle"),
           let style = LightningStyle(rawValue: saved) {
            lightningStyle = style
        }
        renderLightningStyle = lightningStyle
        
        if let saved = UserDefaults.standard.string(forKey: "matrixColorScheme"),
           let scheme = MatrixColorScheme(rawValue: saved) {
            matrixColorScheme = scheme
        }
        renderMatrixColorScheme = matrixColorScheme
        if let saved = UserDefaults.standard.string(forKey: "matrixIntensity"),
           let intensity = MatrixIntensity(rawValue: saved) {
            matrixIntensity = intensity
        }
        renderMatrixIntensity = matrixIntensity
        
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
        
        // Validate the restored mode has a working pipeline — if a shader file is missing
        // (e.g., DMG didn't include it), fall back to Classic to prevent crashes.
        // This must run AFTER setupMetal() so isPipelineAvailable() gives accurate results.
        if !isPipelineAvailable(for: qualityMode) {
            NSLog("SpectrumAnalyzerView: Pipeline not available for \(qualityMode.rawValue), falling back to Classic")
            qualityMode = .classic
        }
        
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
        // Embedded views (e.g., main window flame overlay) keep their own quality/decay mode
        // and only respond to flame style changes (which are shared)
        if !isEmbedded {
            // Reload settings from UserDefaults
            if let savedQuality = UserDefaults.standard.string(forKey: "spectrumQualityMode"),
               let mode = SpectrumQualityMode(rawValue: savedQuality) {
                qualityMode = mode
            }
            
            if let savedDecay = UserDefaults.standard.string(forKey: "spectrumDecayMode"),
               let mode = SpectrumDecayMode(rawValue: savedDecay) {
                decayMode = mode
            }
        }
        
        // Reload flame style and intensity (only for non-embedded views; embedded overlay uses its own key)
        if !isEmbedded {
            if let savedStyle = UserDefaults.standard.string(forKey: "flameStyle"),
               let style = FlameStyle(rawValue: savedStyle) {
                flameStyle = style
            }
            if let savedIntensity = UserDefaults.standard.string(forKey: "flameIntensity"),
               let intensity = FlameIntensity(rawValue: savedIntensity) {
                flameIntensity = intensity
            }
            if let savedStyle = UserDefaults.standard.string(forKey: "lightningStyle"),
               let style = LightningStyle(rawValue: savedStyle) {
                lightningStyle = style
            }
            if let savedScheme = UserDefaults.standard.string(forKey: "matrixColorScheme"),
               let scheme = MatrixColorScheme(rawValue: savedScheme) {
                matrixColorScheme = scheme
            }
            if let savedMatIntensity = UserDefaults.standard.string(forKey: "matrixIntensity"),
               let matIntensity = MatrixIntensity(rawValue: savedMatIntensity) {
                matrixIntensity = matIntensity
            }
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
        guard let userInfo = notification.userInfo,
              let state = userInfo["state"] as? PlaybackState else { return }
        
        switch state {
        case .playing:
            // Ensure the display link is running when playback starts
            if !isRendering {
                startRendering()
            }
        case .paused:
            // Freeze the display - stop rendering but keep current frame visible
            stopRendering()
        case .stopped:
            // Clear all data, flame textures, and render a final black frame
            resetState()
            clearFlameTextures()
            stopRendering()
            renderBlackFrame()
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
        setupFlamePipelines()
        setupCosmicPipelines()
        setupElectricityPipelines()
        setupMatrixPipelines()
        
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
                // Enable blending for anti-aliased rounded corners and glow effects
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].rgbBlendOperation = .add
                descriptor.colorAttachments[0].alphaBlendOperation = .add
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                ledPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            }
            
            // Create bar pipeline (Classic mode)
            if let vertexFunc = library.makeFunction(name: "spectrum_vertex"),
               let fragmentFunc = library.makeFunction(name: "spectrum_fragment") {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "Spectrum Bar Pipeline"
                descriptor.vertexFunction = vertexFunc
                descriptor.fragmentFunction = fragmentFunc
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                // Enable blending for anti-aliased peak indicators
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].rgbBlendOperation = .add
                descriptor.colorAttachments[0].alphaBlendOperation = .add
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
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
            case .classic:
                pipelineState = barPipelineState
            case .enhanced:
                pipelineState = ledPipelineState
            case .ultra:
                pipelineState = ultraPipelineState
            case .flame:
                pipelineState = flameRenderPipeline
            case .cosmic:
                pipelineState = cosmicRenderPipeline
            case .electricity:
                pipelineState = electricityRenderPipeline
            case .matrix:
                pipelineState = matrixRenderPipeline
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
        
        // Heights buffer (for Classic bar mode, reused from existing)
        heightBuffer = device.makeBuffer(
            length: maxColumns * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Colors buffer (24 colors for Classic palette)
        colorBuffer = device.makeBuffer(
            length: 24 * MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        )
        
        // Params buffer (shared between Classic and Enhanced modes)
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
        
        // Flame mode buffers
        flameSpectrumBuffer = device.makeBuffer(length: 75 * MemoryLayout<Float>.stride, options: .storageModeShared)
        flameParamsBuffer = device.makeBuffer(length: MemoryLayout<FlameParams>.stride, options: .storageModeShared)
        
        // Cosmic mode buffers
        cosmicParamsBuffer = device.makeBuffer(length: MemoryLayout<CosmicParams>.stride, options: .storageModeShared)
        
        // Electricity mode buffers
        electricityParamsBuffer = device.makeBuffer(length: MemoryLayout<ElectricityParams>.stride, options: .storageModeShared)
        
        // Matrix mode buffers
        matrixParamsBuffer = device.makeBuffer(length: MemoryLayout<MatrixParams>.stride, options: .storageModeShared)
    }
    
    /// Set up flame compute and render pipelines
    private func setupFlamePipelines() {
        guard let device = device else { return }
        guard let url = BundleHelper.url(forResource: "FlameShaders", withExtension: "metal"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("SpectrumAnalyzerView: FlameShaders.metal not found")
            return
        }
        do {
            let lib = try device.makeLibrary(source: src, options: nil)
            if let fn = lib.makeFunction(name: "propagate_fire") {
                flamePropPipeline = try device.makeComputePipelineState(function: fn)
            }
            if let vf = lib.makeFunction(name: "flame_vertex"),
               let ff = lib.makeFunction(name: "flame_fragment") {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = vf; d.fragmentFunction = ff
                d.colorAttachments[0].pixelFormat = .bgra8Unorm
                d.colorAttachments[0].isBlendingEnabled = true
                d.colorAttachments[0].rgbBlendOperation = .add
                d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                d.colorAttachments[0].sourceAlphaBlendFactor = .one
                d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                flameRenderPipeline = try device.makeRenderPipelineState(descriptor: d)
            }
            NSLog("SpectrumAnalyzerView: Flame pipelines created")
        } catch {
            NSLog("SpectrumAnalyzerView: Flame shader error: \(error)")
        }
        // Create simulation textures
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: flameGridWidth, height: flameGridHeight, mipmapped: false)
        td.usage = [.shaderRead, .shaderWrite]; td.storageMode = .private
        flameSimTextureA = device.makeTexture(descriptor: td)
        flameSimTextureB = device.makeTexture(descriptor: td)
        // Clear textures
        if let cb = commandQueue?.makeCommandBuffer(), let be = cb.makeBlitCommandEncoder() {
            let size = MTLSize(width: flameGridWidth, height: flameGridHeight, depth: 1)
            let bpr = flameGridWidth * 4 * MemoryLayout<Float>.stride
            let zeros = [UInt8](repeating: 0, count: bpr * flameGridHeight)
            if let buf = device.makeBuffer(bytes: zeros, length: zeros.count, options: .storageModeShared) {
                let origin = MTLOrigin(x: 0, y: 0, z: 0)
                be.copy(from: buf, sourceOffset: 0, sourceBytesPerRow: bpr, sourceBytesPerImage: zeros.count, sourceSize: size, to: flameSimTextureA!, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
                be.copy(from: buf, sourceOffset: 0, sourceBytesPerRow: bpr, sourceBytesPerImage: zeros.count, sourceSize: size, to: flameSimTextureB!, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
            }
            be.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        }
    }
    
    /// Set up Cosmic mode render pipeline
    private func setupCosmicPipelines() {
        guard let device = device else { return }
        guard let url = BundleHelper.url(forResource: "CosmicShaders", withExtension: "metal"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("SpectrumAnalyzerView: CosmicShaders.metal not found")
            return
        }
        do {
            let lib = try device.makeLibrary(source: src, options: nil)
            if let vf = lib.makeFunction(name: "cosmic_vertex"),
               let ff = lib.makeFunction(name: "cosmic_fragment") {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = vf; d.fragmentFunction = ff
                d.colorAttachments[0].pixelFormat = .bgra8Unorm
                cosmicRenderPipeline = try device.makeRenderPipelineState(descriptor: d)
            }
            NSLog("SpectrumAnalyzerView: Cosmic pipeline created")
        } catch {
            NSLog("SpectrumAnalyzerView: Cosmic shader error: \(error)")
        }
    }
    
    /// Set up Electricity mode render pipeline
    private func setupElectricityPipelines() {
        guard let device = device else { return }
        guard let url = BundleHelper.url(forResource: "ElectricityShaders", withExtension: "metal"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("SpectrumAnalyzerView: ElectricityShaders.metal not found")
            return
        }
        do {
            let lib = try device.makeLibrary(source: src, options: nil)
            if let vf = lib.makeFunction(name: "electricity_vertex"),
               let ff = lib.makeFunction(name: "electricity_fragment") {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = vf; d.fragmentFunction = ff
                d.colorAttachments[0].pixelFormat = .bgra8Unorm
                electricityRenderPipeline = try device.makeRenderPipelineState(descriptor: d)
            }
            NSLog("SpectrumAnalyzerView: Electricity pipeline created")
        } catch {
            NSLog("SpectrumAnalyzerView: Electricity shader error: \(error)")
        }
    }
    
    /// Set up Matrix mode render pipeline
    private func setupMatrixPipelines() {
        guard let device = device else { return }
        guard let url = BundleHelper.url(forResource: "MatrixShaders", withExtension: "metal"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("SpectrumAnalyzerView: MatrixShaders.metal not found")
            return
        }
        do {
            let lib = try device.makeLibrary(source: src, options: nil)
            if let vf = lib.makeFunction(name: "matrix_vertex"),
               let ff = lib.makeFunction(name: "matrix_fragment") {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = vf; d.fragmentFunction = ff
                d.colorAttachments[0].pixelFormat = .bgra8Unorm
                matrixRenderPipeline = try device.makeRenderPipelineState(descriptor: d)
            }
            NSLog("SpectrumAnalyzerView: Matrix pipeline created")
        } catch {
            NSLog("SpectrumAnalyzerView: Matrix shader error: \(error)")
        }
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
    
    /// Frame skip counter for 30fps effective rendering (skip every other frame)
    nonisolated(unsafe) private var frameSkipCounter: Int = 0
    
    /// Frames to wait before stopping display link when idle (~1 second at effective 30fps)
    private let idleFrameThreshold: Int = 30
    
    /// Track if we stopped rendering due to idle (vs window hidden)
    /// Protected by dataLock for thread-safe access from render and updateSpectrum
    /// nonisolated(unsafe) because Swift doesn't recognize our lock-based synchronization
    nonisolated(unsafe) private var stoppedDueToIdle: Bool = false
    
    /// Called by display link at 60Hz, renders at effective 30fps via frame skipping
    /// Note: This is internal (not private) so the display link callback can access it
    func render() {
        // Skip every other frame for effective 30fps rendering.
        // A spectrum analyzer is visually indistinguishable at 30fps vs 60fps,
        // and this halves CPU-side work (decay, band mapping, peak tracking, vertex updates).
        frameSkipCounter += 1
        guard frameSkipCounter & 1 == 0 else { return }
        
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
        var currentMode: SpectrumQualityMode = .classic
        
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
        
        // Safety net: if the mode requires a pipeline that doesn't exist, skip the frame.
        // This should never happen if commonInit() validation worked, but guards against
        // race conditions or runtime pipeline failures.
        if !isPipelineAvailable(for: currentMode) {
            inFlightSemaphore.signal()
            return
        }
        
        // Flame, Cosmic, and Electricity modes use completely different pipelines
        if currentMode == .flame {
            renderFlame(drawable: drawable)
            return
        }
        if currentMode == .cosmic {
            renderCosmic(drawable: drawable)
            return
        }
        if currentMode == .electricity {
            renderElectricity(drawable: drawable)
            return
        }
        if currentMode == .matrix {
            renderMatrix(drawable: drawable)
            return
        }
        
        let activePipeline: MTLRenderPipelineState?
        switch currentMode {
        case .classic:
            activePipeline = barPipelineState
        case .enhanced:
            activePipeline = ledPipelineState
        case .ultra:
            activePipeline = ultraPipelineState
        case .flame:
            activePipeline = nil  // Handled by renderFlame() above
        case .cosmic:
            activePipeline = nil  // Handled by renderCosmic() above
        case .electricity:
            activePipeline = nil  // Handled by renderElectricity() above
        case .matrix:
            activePipeline = nil  // Handled by renderMatrix() above
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
            
        case .classic:
            // Classic bar mode - bind bar buffers
            if let buffer = heightBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            }
            if let buffer = peakPositionsBuffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 1)
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
            
        case .flame:
            break  // Handled by renderFlame() above
        case .cosmic:
            break  // Handled by renderCosmic() above
        case .electricity:
            break  // Handled by renderElectricity() above
        case .matrix:
            break  // Handled by renderMatrix() above
        }
        
        encoder.endEncoding()
        
        // Signal semaphore when GPU is done with this frame
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    /// Render flame mode: single compute pass + render pass with ping-pong textures
    private func renderFlame(drawable: CAMetalDrawable) {
        // Guard ALL required pipelines BEFORE creating any encoders to prevent Metal API violations.
        // Creating an encoder without calling endEncoding() leaves the command buffer in an invalid state.
        guard let cb = commandQueue?.makeCommandBuffer(),
              let simA = flameSimTextureA, let simB = flameSimTextureB,
              let computePL = flamePropPipeline, let renderPL = flameRenderPipeline else {
            inFlightSemaphore.signal(); return
        }
        var localSpectrum: [Float] = []; var localStyle: FlameStyle = .inferno; var localTime: Float = 0
        var localIntensity: FlameIntensity = .mellow
        dataLock.withLock {
            animationTime += 1.0 / 60.0; localTime = animationTime
            localStyle = renderFlameStyle; localSpectrum = rawSpectrum
            localIntensity = renderFlameIntensity
            var bass: Float = 0; var mid: Float = 0; var treble: Float = 0
            if !rawSpectrum.isEmpty {
                for i in 0..<min(16, rawSpectrum.count) { bass += rawSpectrum[i] }; bass /= 16.0
                for i in 16..<min(50, rawSpectrum.count) { mid += rawSpectrum[i] }; mid /= 34.0
                for i in 50..<min(75, rawSpectrum.count) { treble += rawSpectrum[i] }; treble /= 25.0
            }
            bass *= bassAttenuation
            let attack = localIntensity.attackSpeed
            let release = localIntensity.releaseSpeed
            flameSmoothBass += (bass - flameSmoothBass) * (bass > flameSmoothBass ? attack : release)
            flameSmoothMid += (mid - flameSmoothMid) * (mid > flameSmoothMid ? attack * 0.8 : release * 0.67)
            flameSmoothTreble += (treble - flameSmoothTreble) * (treble > flameSmoothTreble ? attack * 0.8 : release * 0.67)
        }
        if let buf = flameSpectrumBuffer {
            let p = buf.contents().bindMemory(to: Float.self, capacity: 75)
            let bassAtten = bassAttenuation
            for i in 0..<75 {
                var val: Float = i < localSpectrum.count ? localSpectrum[i] : 0
                if i < 16 { val *= bassAtten }
                p[i] = val
            }
        }
        let scale = metalLayer?.contentsScale ?? 2.0
        if let buf = flameParamsBuffer {
            let p = buf.contents().bindMemory(to: FlameParams.self, capacity: 1)
            p.pointee = FlameParams(
                gridSize: SIMD2<Float>(Float(flameGridWidth), Float(flameGridHeight)),
                viewportSize: SIMD2<Float>(Float(bounds.width * scale), Float(bounds.height * scale)),
                time: localTime, dt: 1.0 / 60.0,
                bassEnergy: flameSmoothBass, midEnergy: flameSmoothMid, trebleEnergy: flameSmoothTreble,
                buoyancy: localStyle.buoyancy, cooling: localStyle.cooling, turbulence: localStyle.turbulence,
                diffusion: localStyle.diffusion, windStrength: localStyle.windStrength,
                colorScheme: localStyle.colorScheme, intensity: localIntensity.shaderValue, emberRate: localStyle.emberRate)
        }
        let readTex = flameCurrentTex == 0 ? simA : simB
        let writeTex = flameCurrentTex == 0 ? simB : simA
        flameCurrentTex = 1 - flameCurrentTex
        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let tgs = MTLSize(width: (flameGridWidth + 15) / 16, height: (flameGridHeight + 15) / 16, depth: 1)
        if let enc = cb.makeComputeCommandEncoder() {
            enc.setComputePipelineState(computePL)
            enc.setTexture(readTex, index: 0); enc.setTexture(writeTex, index: 1)
            enc.setBuffer(flameParamsBuffer, offset: 0, index: 0)
            enc.setBuffer(flameSpectrumBuffer, offset: 0, index: 1)
            enc.dispatchThreadgroups(tgs, threadsPerThreadgroup: tgSize); enc.endEncoding()
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear; rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(renderPL)
            enc.setFragmentTexture(writeTex, index: 0)
            enc.setFragmentBuffer(flameParamsBuffer, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6); enc.endEncoding()
        }
        cb.addCompletedHandler { [weak self] _ in self?.inFlightSemaphore.signal() }
        cb.present(drawable); cb.commit()
    }
    
    /// Render cosmic mode: procedural nebula flythrough driven by music intensity
    /// Music drives the SPEED of drifting through the nebula, not shape.
    private func renderCosmic(drawable: CAMetalDrawable) {
        guard let cb = commandQueue?.makeCommandBuffer() else {
            inFlightSemaphore.signal(); return
        }
        
        var localTime: Float = 0
        var localScroll: Float = 0
        
        dataLock.withLock {
            animationTime += 1.0 / 60.0
            localTime = animationTime
            
            // Compute band energies from raw spectrum
            var bass: Float = 0; var mid: Float = 0; var treble: Float = 0
            if !rawSpectrum.isEmpty {
                for i in 0..<min(16, rawSpectrum.count) { bass += rawSpectrum[i] }; bass /= 16.0
                for i in 16..<min(50, rawSpectrum.count) { mid += rawSpectrum[i] }; mid /= 34.0
                for i in 50..<min(75, rawSpectrum.count) { treble += rawSpectrum[i] }; treble /= 25.0
            }
            bass *= bassAttenuation
            
            // Smooth audio values (fast attack, slower release)
            cosmicSmoothBass += (bass - cosmicSmoothBass) * (bass > cosmicSmoothBass ? 0.3 : 0.08)
            cosmicSmoothMid += (mid - cosmicSmoothMid) * (mid > cosmicSmoothMid ? 0.3 : 0.08)
            cosmicSmoothTreble += (treble - cosmicSmoothTreble) * (treble > cosmicSmoothTreble ? 0.3 : 0.08)
            
            // Beat detection: bass spike above smoothed level
            if bass > cosmicSmoothBass + 0.12 {
                cosmicBeatIntensity = min(1.0, cosmicBeatIntensity + 0.5)
            }
            cosmicBeatIntensity *= 0.92
            
            // Rare big flare: only on strong peaks, with long cooldown
            // While active, suppresses all small flares — the giant owns the screen
            if cosmicFlareCooldown > 0 {
                cosmicFlareCooldown -= 1
            }
            // Giant flare detection with low-pass filter
            // LPF tracks a very slow-moving average of total energy.
            // When instantaneous energy exceeds LPF by a threshold, fire.
            // The slow LPF (alpha=0.02) prevents the reference from chasing
            // transients, so real peaks reliably exceed it.
            let instantEnergy = (bass + mid + treble) / 3.0
            cosmicFlareLPF += (instantEnergy - cosmicFlareLPF) * 0.02  // Very slow follower
            let flareDelta = instantEnergy - cosmicFlareLPF
            
            if flareDelta > 0.10 && cosmicFlareCooldown == 0 && cosmicFlareIntensity < 0.05 {
                // Energy spike above low-pass baseline — fire the giant
                cosmicFlareIntensity = 1.0
                cosmicFlareScrollSnapshot = cosmicScrollOffset
                cosmicFlareCooldown = 420  // ~7 seconds cooldown at 60fps
            }
            // Very slow decay: ~5.5 seconds to fade from 1.0 to ~0.05
            // 0.991^330 ≈ 0.05 → 330 frames = 5.5 seconds
            cosmicFlareIntensity *= 0.991
            
            // Accumulate scroll distance based on music intensity
            // Gentle drift always, slightly faster when loud — chill ride through space
            let totalEnergy = (cosmicSmoothBass + cosmicSmoothMid + cosmicSmoothTreble) / 3.0
            let speed: Float = 0.08 + totalEnergy * 0.5
            cosmicScrollOffset += speed * (1.0 / 60.0)
            localScroll = cosmicScrollOffset
        }
        
        // Update cosmic params (no spectrum buffer — pure atmospheric mode)
        let scale = metalLayer?.contentsScale ?? 2.0
        let totalE = (cosmicSmoothBass + cosmicSmoothMid + cosmicSmoothTreble) / 3.0
        if let buf = cosmicParamsBuffer {
            let p = buf.contents().bindMemory(to: CosmicParams.self, capacity: 1)
            p.pointee = CosmicParams(
                viewportSize: SIMD2<Float>(Float(bounds.width * scale), Float(bounds.height * scale)),
                time: localTime,
                scrollOffset: localScroll,
                bassEnergy: cosmicSmoothBass,
                midEnergy: cosmicSmoothMid,
                trebleEnergy: cosmicSmoothTreble,
                totalEnergy: totalE,
                beatIntensity: cosmicBeatIntensity,
                flareIntensity: cosmicFlareIntensity,
                flareScroll: cosmicFlareScrollSnapshot,
                brightnessBoost: brightnessBoost
            )
        }
        
        // Render full-screen quad
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        // Guard pipeline BEFORE creating encoder to prevent Metal API violations
        guard let pl = cosmicRenderPipeline else {
            inFlightSemaphore.signal(); return
        }
        
        // Update spectrum buffer for frequency-aligned flares
        // Uses displaySpectrum (already normalized by AudioEngine) not rawSpectrum
        var localSpectrum: [Float] = []
        dataLock.withLock { localSpectrum = displaySpectrum }
        if let buf = flameSpectrumBuffer {
            let p = buf.contents().bindMemory(to: Float.self, capacity: 75)
            let bassAtten = bassAttenuation
            for i in 0..<75 {
                var val: Float = i < localSpectrum.count ? localSpectrum[i] : 0
                if i < 16 { val *= bassAtten }
                p[i] = val
            }
        }
        
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pl)
            enc.setFragmentBuffer(cosmicParamsBuffer, offset: 0, index: 0)
            enc.setFragmentBuffer(flameSpectrumBuffer, offset: 0, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            enc.endEncoding()
        }
        
        cb.addCompletedHandler { [weak self] _ in self?.inFlightSemaphore.signal() }
        cb.present(drawable); cb.commit()
    }
    
    /// Render electricity mode: procedural lightning storm driven by spectrum peaks
    private func renderElectricity(drawable: CAMetalDrawable) {
        guard let cb = commandQueue?.makeCommandBuffer() else {
            inFlightSemaphore.signal(); return
        }
        
        var localTime: Float = 0
        
        dataLock.withLock {
            animationTime += 1.0 / 60.0
            localTime = animationTime
            
            // Compute band energies from raw spectrum
            var bass: Float = 0; var mid: Float = 0; var treble: Float = 0
            if !rawSpectrum.isEmpty {
                for i in 0..<min(16, rawSpectrum.count) { bass += rawSpectrum[i] }; bass /= 16.0
                for i in 16..<min(50, rawSpectrum.count) { mid += rawSpectrum[i] }; mid /= 34.0
                for i in 50..<min(75, rawSpectrum.count) { treble += rawSpectrum[i] }; treble /= 25.0
            }
            bass *= bassAttenuation
            
            // Smooth audio values — JWST-style gentle tracking
            electricitySmoothBass += (bass - electricitySmoothBass) * (bass > electricitySmoothBass ? 0.25 : 0.06)
            electricitySmoothMid += (mid - electricitySmoothMid) * (mid > electricitySmoothMid ? 0.2 : 0.06)
            electricitySmoothTreble += (treble - electricitySmoothTreble) * (treble > electricitySmoothTreble ? 0.2 : 0.06)
            
            // Beat detection: gentle
            if bass > electricitySmoothBass + 0.14 {
                electricityBeatIntensity = min(0.6, electricityBeatIntensity + 0.25)
            }
            electricityBeatIntensity *= 0.94
            
            // Dramatic strike detection — JWST-style rare event with long cooldown
            // LPF tracks slow-moving energy baseline, dramatic fires on spikes above it
            if electricityDramaticCooldown > 0 {
                electricityDramaticCooldown -= 1
            }
            let instantEnergy = (bass + mid + treble) / 3.0
            electricityDramaticLPF += (instantEnergy - electricityDramaticLPF) * 0.02  // Very slow follower
            let dramaticDelta = instantEnergy - electricityDramaticLPF
            
            if dramaticDelta > 0.10 && electricityDramaticCooldown == 0 && electricityDramaticIntensity < 0.05 {
                // Energy spike above baseline — fire dramatic strike
                electricityDramaticIntensity = 1.0
                electricityDramaticCooldown = 480  // ~8 seconds cooldown at 60fps
            }
            // Very slow decay: ~5 seconds to fade (like JWST giant flare)
            // 0.991^300 ≈ 0.05
            electricityDramaticIntensity *= 0.991
        }
        
        // Update spectrum buffer (reuse flameSpectrumBuffer like cosmic does)
        var localSpectrum: [Float] = []
        dataLock.withLock { localSpectrum = displaySpectrum }
        if let buf = flameSpectrumBuffer {
            let p = buf.contents().bindMemory(to: Float.self, capacity: 75)
            let bassAtten = bassAttenuation
            for i in 0..<75 {
                var val: Float = i < localSpectrum.count ? localSpectrum[i] : 0
                if i < 16 { val *= bassAtten }
                p[i] = val
            }
        }
        
        // Update electricity params
        let scale = metalLayer?.contentsScale ?? 2.0
        let totalE = (electricitySmoothBass + electricitySmoothMid + electricitySmoothTreble) / 3.0
        if let buf = electricityParamsBuffer {
            let p = buf.contents().bindMemory(to: ElectricityParams.self, capacity: 1)
            var localColorScheme: Int32 = 0
            dataLock.withLock { localColorScheme = renderLightningStyle.colorScheme }
            p.pointee = ElectricityParams(
                viewportSize: SIMD2<Float>(Float(bounds.width * scale), Float(bounds.height * scale)),
                time: localTime,
                bassEnergy: electricitySmoothBass,
                midEnergy: electricitySmoothMid,
                trebleEnergy: electricitySmoothTreble,
                totalEnergy: totalE,
                beatIntensity: electricityBeatIntensity,
                dramaticIntensity: electricityDramaticIntensity,
                colorScheme: localColorScheme,
                brightnessBoost: brightnessBoost
            )
        }
        
        // Guard pipeline BEFORE creating encoder to prevent Metal API violations
        guard let pl = electricityRenderPipeline else {
            inFlightSemaphore.signal(); return
        }
        
        // Render full-screen quad
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pl)
            enc.setFragmentBuffer(electricityParamsBuffer, offset: 0, index: 0)
            enc.setFragmentBuffer(flameSpectrumBuffer, offset: 0, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            enc.endEncoding()
        }
        
        cb.addCompletedHandler { [weak self] _ in self?.inFlightSemaphore.signal() }
        cb.present(drawable); cb.commit()
    }
    
    /// Render matrix mode: falling digital rain driven by spectrum
    private func renderMatrix(drawable: CAMetalDrawable) {
        guard let cb = commandQueue?.makeCommandBuffer() else {
            inFlightSemaphore.signal(); return
        }
        
        var localTime: Float = 0
        var localScroll: Float = 0
        var localColorScheme: Int32 = 0
        var localIntensityVal: Float = 1.0
        
        dataLock.withLock {
            animationTime += 1.0 / 60.0
            localTime = animationTime
            
            // Compute band energies from raw spectrum
            var bass: Float = 0; var mid: Float = 0; var treble: Float = 0
            if !rawSpectrum.isEmpty {
                for i in 0..<min(16, rawSpectrum.count) { bass += rawSpectrum[i] }; bass /= 16.0
                for i in 16..<min(50, rawSpectrum.count) { mid += rawSpectrum[i] }; mid /= 34.0
                for i in 50..<min(75, rawSpectrum.count) { treble += rawSpectrum[i] }; treble /= 25.0
            }
            bass *= bassAttenuation
            
            // Get current intensity preset for attack/release speeds
            let intensityPreset = renderMatrixIntensity
            let attack = intensityPreset.attackSpeed
            let release = intensityPreset.releaseSpeed
            
            // Smooth audio values
            matrixSmoothBass += (bass - matrixSmoothBass) * (bass > matrixSmoothBass ? attack : release)
            matrixSmoothMid += (mid - matrixSmoothMid) * (mid > matrixSmoothMid ? attack : release)
            matrixSmoothTreble += (treble - matrixSmoothTreble) * (treble > matrixSmoothTreble ? attack : release)
            
            // Beat detection: bass spike above smoothed level
            if bass > matrixSmoothBass + 0.12 {
                matrixBeatIntensity = min(1.0, matrixBeatIntensity + 0.5)
            }
            matrixBeatIntensity *= 0.90
            
            // Dramatic awakening detection — LPF-based spike detection with cooldown
            if matrixDramaticCooldown > 0 {
                matrixDramaticCooldown -= 1
            }
            let instantEnergy = (bass + mid + treble) / 3.0
            matrixDramaticLPF += (instantEnergy - matrixDramaticLPF) * 0.02  // Very slow follower
            let dramaticDelta = instantEnergy - matrixDramaticLPF
            
            if dramaticDelta > 0.10 && matrixDramaticCooldown == 0 && matrixDramaticIntensity < 0.05 {
                matrixDramaticIntensity = 1.0
                matrixDramaticCooldown = 420  // ~7 seconds cooldown at 60fps
            }
            matrixDramaticIntensity *= 0.991  // Very slow decay
            
            // Accumulate scroll offset with steady base speed + gentle energy modulation
            // Keep the speed relatively constant so rain falls smoothly —
            // spectrum drives brightness/trail length in the shader, not position.
            let totalEnergy = (matrixSmoothBass + matrixSmoothMid + matrixSmoothTreble) / 3.0
            let speed: Float = 0.8 + totalEnergy * 0.6
            matrixScrollOffset += speed * (1.0 / 60.0)
            localScroll = matrixScrollOffset
            
            localColorScheme = renderMatrixColorScheme.colorScheme
            localIntensityVal = renderMatrixIntensity.shaderValue
        }
        
        // Update spectrum buffer (reuse flameSpectrumBuffer like cosmic/electricity does)
        var localSpectrum: [Float] = []
        dataLock.withLock { localSpectrum = displaySpectrum }
        if let buf = flameSpectrumBuffer {
            let p = buf.contents().bindMemory(to: Float.self, capacity: 75)
            let bassAtten = bassAttenuation
            for i in 0..<75 {
                var val: Float = i < localSpectrum.count ? localSpectrum[i] : 0
                if i < 16 { val *= bassAtten }
                p[i] = val
            }
        }
        
        // Update matrix params
        let scale = metalLayer?.contentsScale ?? 2.0
        let totalE = (matrixSmoothBass + matrixSmoothMid + matrixSmoothTreble) / 3.0
        if let buf = matrixParamsBuffer {
            let p = buf.contents().bindMemory(to: MatrixParams.self, capacity: 1)
            p.pointee = MatrixParams(
                viewportSize: SIMD2<Float>(Float(bounds.width * scale), Float(bounds.height * scale)),
                time: localTime,
                bassEnergy: matrixSmoothBass,
                midEnergy: matrixSmoothMid,
                trebleEnergy: matrixSmoothTreble,
                totalEnergy: totalE,
                beatIntensity: matrixBeatIntensity,
                dramaticIntensity: matrixDramaticIntensity,
                scrollOffset: localScroll,
                colorScheme: localColorScheme,
                intensity: localIntensityVal,
                brightnessBoost: brightnessBoost
            )
        }
        
        // Guard pipeline BEFORE creating encoder to prevent Metal API violations
        guard let pl = matrixRenderPipeline else {
            inFlightSemaphore.signal(); return
        }
        
        // Render full-screen quad
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pl)
            enc.setFragmentBuffer(matrixParamsBuffer, offset: 0, index: 0)
            enc.setFragmentBuffer(flameSpectrumBuffer, offset: 0, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            enc.endEncoding()
        }
        
        cb.addCompletedHandler { [weak self] _ in self?.inFlightSemaphore.signal() }
        cb.present(drawable); cb.commit()
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
        
        // Decay factor is tuned for 60fps; square it for 30fps to maintain same visual decay speed
        // (at 30fps each frame spans 2x the time, so decay^2 gives equivalent per-second decay)
        let decay = renderDecayFactor * renderDecayFactor
        let outputCount = renderBarCount
        let ultraOutputCount = ultraBarCount
        
        // Check normalization mode - Accurate uses full height for max dynamic range
        let isAccurateMode = UserDefaults.standard.string(forKey: normalizationUserDefaultsKey) == SpectrumNormalizationMode.accurate.rawValue
        
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
            
            // Ensure displaySpectrum has correct size (for Enhanced/Classic modes)
            if displaySpectrum.count != outputCount {
                displaySpectrum = Array(repeating: 0, count: outputCount)
            }
            
            // Ensure ultraDisplaySpectrum has correct size (96 bars for Ultra mode)
            if ultraDisplaySpectrum.count != ultraOutputCount {
                ultraDisplaySpectrum = Array(repeating: 0, count: ultraOutputCount)
            }
            
            // Update standard display spectrum (for Enhanced/Classic)
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
            
        // Update LED matrix / peak state based on mode
        switch renderQualityMode {
        case .enhanced:
            updateLEDMatrixState()
        case .ultra:
            updateUltraMatrixState()
        case .classic:
            updateClassicPeakState()
        case .flame:
            break  // Flame handles its own state in renderFlame()
        case .cosmic:
            break  // Cosmic handles its own state in renderCosmic()
        case .electricity:
            break  // Electricity handles its own state in renderElectricity()
        case .matrix:
            break  // Matrix handles its own state in renderMatrix()
        }

        hasVisibleData = hasData
        return hasData
    }
    
    /// Updates peak hold positions and per-cell brightness for LED matrix mode
    /// Note: Only called when qualityMode == .enhanced
    /// Features: gravity-based bouncing peaks, two-phase warm-glow fade trails
    private func updateLEDMatrixState() {
        let colCount = renderBarCount
        
        // Increment animation time for shader effects
        animationTime += 1.0 / 60.0
        
        // Arrays are pre-allocated in commonInit - no resizing needed
        
        // Physics constants for gravity-based peak animation
        let gravity: Float = 0.005            // Acceleration downward per frame
        let bounceCoeff: Float = 0.25         // Energy retained on bounce
        let minBounceVelocity: Float = 0.008  // Minimum velocity to trigger bounce
        
        // Two-phase cell brightness transition for warm glow trail effect
        let cellAttackRate: Float = 0.5       // Fast attack for punchy response
        let cellFadeRateSlow: Float = 0.018   // Phase 1: slow fade (warm glow lingers)
        let cellFadeRateFast: Float = 0.055   // Phase 2: faster fade to dark
        let warmGlowThreshold: Float = 0.45   // Below this brightness, fade faster
        
        for col in 0..<min(colCount, displaySpectrum.count) {
            let currentLevel = displaySpectrum[col]
            let currentRow = Int(currentLevel * Float(ledRowCount))
            
            // Physics-based peak animation (gravity + bounce)
            if currentLevel > peakHoldPositions[col] {
                // New peak - jump to current level and reset velocity
                peakHoldPositions[col] = currentLevel
                peakVelocities[col] = 0
            } else {
                // Apply gravity (acceleration downward)
                peakVelocities[col] -= gravity
                peakHoldPositions[col] += peakVelocities[col]
                
                // Bounce off bar level
                if peakHoldPositions[col] < currentLevel {
                    peakHoldPositions[col] = currentLevel
                    if abs(peakVelocities[col]) > minBounceVelocity {
                        peakVelocities[col] = -peakVelocities[col] * bounceCoeff
                    } else {
                        peakVelocities[col] = 0
                    }
                }
                
                // Clamp to valid range
                peakHoldPositions[col] = max(0, min(1.0, peakHoldPositions[col]))
            }
            
            // Two-phase cell fade for warm glow trail effect
            // Phase 1 (bright → warmGlowThreshold): slow fade, cells linger with warm glow
            // Phase 2 (warmGlowThreshold → 0): faster fade, cells quickly go dark
            for row in 0..<ledRowCount {
                let targetBrightness: Float = row < currentRow ? 1.0 : 0.0
                let current = cellBrightness[col][row]
                
                if targetBrightness > current {
                    // Fast attack - cells light up quickly for punchy response
                    cellBrightness[col][row] = min(1.0, current + cellAttackRate)
                } else if current > warmGlowThreshold {
                    // Phase 1: slow fade - warm glow lingers beautifully
                    cellBrightness[col][row] = max(0, current - cellFadeRateSlow)
                } else {
                    // Phase 2: faster fade to dark
                    cellBrightness[col][row] = max(0, current - cellFadeRateFast)
                }
            }
        }
    }
    
    /// Updates peak hold positions for Classic mode with gravity-based physics
    /// Peaks jump to new bar heights, then float and fall with satisfying gravity
    private func updateClassicPeakState() {
        let colCount = renderBarCount
        
        // Physics constants for satisfying peak animation
        let gravity: Float = 0.004           // Acceleration downward per frame
        let bounceCoeff: Float = 0.3         // Energy retained on bounce
        let minBounceVelocity: Float = 0.008 // Minimum velocity to trigger bounce
        
        for col in 0..<min(colCount, displaySpectrum.count) {
            let currentLevel = displaySpectrum[col]
            
            if currentLevel > peakHoldPositions[col] {
                // New peak - jump to current level and reset velocity
                peakHoldPositions[col] = currentLevel
                peakVelocities[col] = 0
            } else {
                // Apply gravity (acceleration downward)
                peakVelocities[col] -= gravity
                peakHoldPositions[col] += peakVelocities[col]
                
                // Bounce off bar level
                if peakHoldPositions[col] < currentLevel {
                    peakHoldPositions[col] = currentLevel
                    if abs(peakVelocities[col]) > minBounceVelocity {
                        peakVelocities[col] = -peakVelocities[col] * bounceCoeff
                    } else {
                        peakVelocities[col] = 0
                    }
                }
                
                // Clamp to valid range
                peakHoldPositions[col] = max(0, min(1.0, peakHoldPositions[col]))
            }
        }
    }
    
    /// Updates state for Ultra mode with physics-based peaks and higher resolution
    /// Designed for maximum fluidity: smooth exponential decay, gradient bar tops,
    /// no hard cutoffs -- everything flows and breathes naturally
    private func updateUltraMatrixState() {
        let colCount = ultraBarCount
        let rowCount = ultraLedRowCount
        let rowCountF = Float(rowCount)
        
        // Arrays are pre-allocated in commonInit - no resizing needed
        
        // Physics constants for smooth, satisfying peak animation
        let gravity: Float = 0.008            // Gentle gravity for floatier peaks
        let bounceCoeff: Float = 0.3          // Energy retained on bounce
        let minBounceVelocity: Float = 0.01   // Minimum velocity to trigger bounce
        
        // Smooth exponential decay factor (per frame at effective 30fps)
        // Original 0.94 at 60fps → squared for 30fps to maintain same visual decay speed
        let decayMultiplier: Float = 0.94 * 0.94  // ≈ 0.8836
        
        // Soft gradient zone at bar top (in normalized 0-1 space)
        // Instead of hard cutoff, brightness ramps smoothly over this range
        let gradientZone: Float = 3.0 / rowCountF  // ~3 cells of soft transition
        
        // Gentle floor to avoid always-lit bottom with smooth ramp
        let floor: Float = 0.08
        let ceiling: Float = 1.0
        let range = ceiling - floor
        
        // Update animation time (effective 30fps due to frame skipping)
        animationTime += 1.0 / 30.0
        
        for col in 0..<min(colCount, ultraDisplaySpectrum.count) {
            let rawLevel = ultraDisplaySpectrum[col]
            let currentLevel = max(0, (rawLevel - floor) / range)
            
            // Physics-based peak animation
            if currentLevel > ultraPeakPositions[col] {
                ultraPeakPositions[col] = currentLevel
                peakVelocities[col] = 0
            } else {
                peakVelocities[col] -= gravity
                ultraPeakPositions[col] += peakVelocities[col]
                
                if ultraPeakPositions[col] < currentLevel {
                    ultraPeakPositions[col] = currentLevel
                    if abs(peakVelocities[col]) > minBounceVelocity {
                        peakVelocities[col] = -peakVelocities[col] * bounceCoeff
                    } else {
                        peakVelocities[col] = 0
                    }
                }
                ultraPeakPositions[col] = max(0, min(1.0, ultraPeakPositions[col]))
            }
            
            // Smooth per-cell brightness with gradient bar top and exponential decay
            for row in 0..<rowCount {
                let rowNorm = Float(row) / rowCountF
                let current = ultraCellBrightness[col][row]
                
                if rowNorm < currentLevel - gradientZone {
                    // Well below bar top - instant full brightness (no smoothing here,
                    // smoothing in the interior causes visible pulsing from audio jitter)
                    ultraCellBrightness[col][row] = 1.0
                } else if rowNorm < currentLevel {
                    // Gradient zone at bar top - smooth ramp for soft edge
                    let t = (currentLevel - rowNorm) / gradientZone
                    let target = 0.4 + 0.6 * t
                    ultraCellBrightness[col][row] = max(target, current * decayMultiplier)
                } else {
                    // Above bar - smooth exponential decay
                    ultraCellBrightness[col][row] = current * decayMultiplier
                }
                
                // Clean floor to avoid sub-perceptual ghost values
                if ultraCellBrightness[col][row] < 0.003 {
                    ultraCellBrightness[col][row] = 0
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
        var localQualityMode: SpectrumQualityMode = .classic
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
                    maxHeight: scaledHeight,
                    time: localAnimationTime,
                    brightnessBoost: brightnessBoost
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
                    time: localAnimationTime,
                    brightnessBoost: brightnessBoost
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
            
        case .classic:
            // Calculate cell dimensions for Classic mode - use exact bar width
            let cellSpacing: Float = 1.0 * Float(scale)
            let cellHeight = (scaledHeight - Float(ledRowCount - 1) * cellSpacing) / Float(ledRowCount)
            let cellWidth = Float(localBarWidth * scale)
            
            // Update params buffer for Classic
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
            
            // Update peak positions buffer for floating peak indicators
            if let buffer = peakPositionsBuffer {
                let ptr = buffer.contents().bindMemory(to: Float.self, capacity: localBarCount)
                for col in 0..<localBarCount {
                    ptr[col] = col < localPeakPositions.count ? localPeakPositions[col] : 0
                }
            }
            
            // Update colors buffer
            if let buffer = colorBuffer {
                let ptr = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 24)
                for (i, color) in localColors.prefix(24).enumerated() {
                    ptr[i] = color
                }
            }
            
        case .flame:
            break  // Flame updates its own buffers in renderFlame()
        case .cosmic:
            break  // Cosmic updates its own buffers in renderCosmic()
        case .electricity:
            break  // Electricity updates its own buffers in renderElectricity()
        case .matrix:
            break  // Matrix updates its own buffers in renderMatrix()
        }
    }
    
    // MARK: - Public API
    
    /// Clear flame simulation textures to zero (makes fire go black immediately)
    func clearFlameTextures() {
        guard let device = device, let simA = flameSimTextureA, let simB = flameSimTextureB else { return }
        if let cb = commandQueue?.makeCommandBuffer(), let be = cb.makeBlitCommandEncoder() {
            let size = MTLSize(width: flameGridWidth, height: flameGridHeight, depth: 1)
            let bpr = flameGridWidth * 4 * MemoryLayout<Float>.stride
            let zeros = [UInt8](repeating: 0, count: bpr * flameGridHeight)
            if let buf = device.makeBuffer(bytes: zeros, length: zeros.count, options: .storageModeShared) {
                let origin = MTLOrigin(x: 0, y: 0, z: 0)
                be.copy(from: buf, sourceOffset: 0, sourceBytesPerRow: bpr, sourceBytesPerImage: zeros.count, sourceSize: size, to: simA, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
                be.copy(from: buf, sourceOffset: 0, sourceBytesPerRow: bpr, sourceBytesPerImage: zeros.count, sourceSize: size, to: simB, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
            }
            be.endEncoding(); cb.commit()
        }
    }
    
    /// Render a single black frame to clear the display after stopping
    private func renderBlackFrame() {
        guard let metalLayer = metalLayer,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
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
        // If modern skin override is set, use that instead
        if spectrumColors != nil {
            applySpectrumColorOverride()
            return
        }
        
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
    
    /// Apply the spectrumColors override from the modern skin system
    private func applySpectrumColorOverride() {
        guard let overrideColors = spectrumColors else { return }
        
        colorPalette = overrideColors.map { color in
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
