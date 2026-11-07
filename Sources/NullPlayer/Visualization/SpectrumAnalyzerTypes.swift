// Modes, style presets and Metal parameter structs for SpectrumAnalyzerView.

/// Quality mode for spectrum analyzer rendering
enum SpectrumQualityMode: String, CaseIterable {
    case classic = "Classic"     // Soft bars in the skin's palette
    case enhanced = "Enhanced"   // Filled flowing curve with a glowing crest
    case ultra = "Ultra"         // Dense rounded bars with bloom and reflection
    case flame = "Fire"          // GPU fire simulation driven by audio
    case cosmic = "JWST"         // Procedural nebula inspired by JWST Pillars of Creation
    case electricity = "Lightning" // GPU lightning storm driven by peak frequencies
    case matrix = "Matrix"           // Falling digital rain driven by spectrum
    case snow = "Snow"               // Audio-reactive snowfall driven by spectrum density
    case ekg = "EKG"                 // Beat-synced electrocardiogram monitor driven by BPM and waveform amplitude
    case visClassicExact = "vis_classic" // Exact-port vis_classic analyzer core (CPU frame path)
    
    var displayName: String { rawValue }

    /// Whether the Responsiveness and Normalization menus apply: vis_classic runs its own core and
    /// ignores both; Fire normalizes itself.
    var offersResponsiveness: Bool { self != .visClassicExact }
    var offersNormalization: Bool { self != .flame && self != .visClassicExact }

    /// Shared user-facing order for visualization mode menus and click cycling.
    static let visualizationOrder: [SpectrumQualityMode] = [
        .classic,
        .enhanced,
        .ultra,
        .flame,
        .cosmic,
        .electricity,
        .matrix,
        .snow,
        .ekg,
        .visClassicExact
    ]
    
    /// The Metal shader file required for this mode.
    /// Returns nil if the mode shares a shader already checked by another mode.
    var requiredShaderFile: String {
        switch self {
        case .classic, .enhanced, .ultra: return "SpectrumShaders"
        case .flame: return "FlameShaders"
        case .cosmic: return "CosmicShaders"
        case .electricity: return "ElectricityShaders"
        case .matrix: return "MatrixShaders"
        case .snow: return "SnowShaders"
        case .ekg: return "EKGShaders"
        case .visClassicExact: return "SpectrumShaders" // Always bundled; keeps mode enabled in menus
        }
    }
}

/// Visual style presets for Flame mode
enum FlameStyle: String, CaseIterable {
    case inferno = "Inferno"
    case aurora = "Aurora"
    case electric = "Electric"
    case ocean = "Ocean"
    case emerald = "Emerald"
    case toxic = "Toxic"
    case plasma = "Plasma"
    case sunset = "Sunset"
    case ice = "Ice"
    case gold = "Gold"
    case blood = "Blood"
    case ghost = "Ghost"
    case spectrum = "Spectrum"
    case cobalt = "Cobalt"
    case candle = "Candle"
    case synthwave = "Synthwave"
    var displayName: String { rawValue }
    /// Row in `kFlamePalettes` (FlameShaders.metal), which lists the palettes in this case order.
    var colorScheme: Int32 { Int32(Self.allCases.firstIndex(of: self)!) }
    /// Styles past Ocean are colour variants and burn like Inferno.
    var motion: FlameMotion {
        switch self {
        case .aurora: return FlameMotion(buoyancy: 3.5, cooling: 0.17, turbulence: 1.2, diffusion: 0.08, windStrength: 2.5, emberRate: 0.001)
        case .electric: return FlameMotion(buoyancy: 8.0, cooling: 0.28, turbulence: 3.0, diffusion: 0.02, windStrength: 1.8, emberRate: 0.004)
        case .ocean: return FlameMotion(buoyancy: 4.0, cooling: 0.14, turbulence: 0.8, diffusion: 0.1, windStrength: 1.0, emberRate: 0.001)
        default: return FlameMotion(buoyancy: 6.0, cooling: 0.28, turbulence: 2.0, diffusion: 0.04, windStrength: 1.2, emberRate: 0.002)
        }
    }
}

/// How a flame style moves; the `FlameParams` fields of the same names.
struct FlameMotion {
    let buoyancy: Float
    let cooling: Float
    let turbulence: Float
    let diffusion: Float
    let windStrength: Float
    let emberRate: Float
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
    var brightnessBoost: Float = 1.0 // 4 bytes (offset 40)
    var peak1Band: Float = 0.5       // 4 bytes (offset 44) - normalized position of loudest band
    var peak1Energy: Float = 0.0     // 4 bytes (offset 48) - energy of loudest band
    var peak2Band: Float = 0.3       // 4 bytes (offset 52) - normalized position of 2nd loudest band
    var peak2Energy: Float = 0.0     // 4 bytes (offset 56) → total 60
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

/// Color/style presets for EKG mode
enum EKGStyle: String, CaseIterable {
    case clinical = "Clinical"
    case cyan = "Cyan"
    case amber = "Amber"
    case neon = "Neon"
    case crimson = "Crimson"
    case ice = "Ice"
    case inferno = "Inferno"
    case aurora = "Aurora"
    case ocean = "Ocean"
    case toxic = "Toxic"
    case plasma = "Plasma"
    case sunset = "Sunset"
    case gold = "Gold"
    case ghost = "Ghost"
    case cobalt = "Cobalt"
    case violet = "Violet"
    case synthwave = "Synthwave"
    case emerald = "Emerald"

    var displayName: String { rawValue }
    /// Row in `kEKGPalettes` (EKGShaders.metal), which lists the palettes in this case order.
    var colorScheme: Int32 { Int32(Self.allCases.firstIndex(of: self)!) }
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

/// Parameters for Snow Metal shaders (must match Metal SnowParams struct)
struct SnowParams {
    var viewportSize: SIMD2<Float>  // 8 bytes (offset 0)
    var time: Float                  // 4 bytes (offset 8)
    var bassEnergy: Float            // 4 bytes (offset 12)
    var trebleEnergy: Float          // 4 bytes (offset 16)
    var totalEnergy: Float           // 4 bytes (offset 20)
    var beatIntensity: Float         // 4 bytes (offset 24)
    var fallOffset: Float            // 4 bytes (offset 28)
    var windPhase: Float             // 4 bytes (offset 32)
    var density: Float               // 4 bytes (offset 36)
    var brightnessBoost: Float = 1.0 // 4 bytes (offset 40)
    var stormLevel: Float = 0        // 4 bytes (offset 44) → total 48
}

/// Parameters for EKG Metal shaders (must match Metal EKGParams struct).
/// Peak-driven: `beatTimes0`/`beatTimes1` carry up to 8 recent audio-onset timestamps
/// in localTime seconds; unused slots are -1000.
struct EKGParams {
    var viewportSize: SIMD2<Float>  // 8 bytes (offset 0)
    var time: Float                  // 4 bytes (offset 8)
    var amplitudeLevel: Float        // 4 bytes (offset 12)
    var noiseLevel: Float            // 4 bytes (offset 16)
    var scrollDelta: Float           // 4 bytes (offset 20)
    var brightnessBoost: Float = 1.0 // 4 bytes (offset 24)
    var colorScheme: Int32 = 0       // 4 bytes (offset 28)
    var beatCount: Int32 = 0         // 4 bytes (offset 32)
    var pad0: Float = 0              // 4 bytes (offset 36)
    var pad1: Float = 0              // 4 bytes (offset 40)
    var pad2: Float = 0              // 4 bytes (offset 44) → 48 (float4-aligned)
    var beatTimes0: SIMD4<Float> = .init(repeating: -1000)  // 16 bytes (offset 48)
    var beatTimes1: SIMD4<Float> = .init(repeating: -1000)  // 16 bytes (offset 64)
    var beatAmps0: SIMD4<Float> = .init(repeating: 1)       // 16 bytes (offset 80)
    var beatAmps1: SIMD4<Float> = .init(repeating: 1)       // 16 bytes (offset 96) → total 112
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
