import AppKit

/// Protocol defining the interface for visualization engines
///
/// Visualization engines render real-time audio visualizations using audio data
/// provided through the `addPCMMono()` method. Implementations must handle their
/// own OpenGL resource management and rendering.
protocol VisualizationEngine: AnyObject {
    /// Whether the engine is available and initialized
    ///
    /// This should return `false` if initialization failed or required resources
    /// are not available.
    var isAvailable: Bool { get }

    /// Human-readable display name for the visualization engine
    ///
    /// Used in UI elements to identify the engine (e.g., "ProjectM", "TOC Spectrum")
    var displayName: String { get }

    /// Initialize the engine with the specified viewport dimensions
    ///
    /// - Parameters:
    ///   - width: Initial viewport width in pixels
    ///   - height: Initial viewport height in pixels
    ///
    /// - Note: OpenGL context must be current when calling `init`
    init(width: Int, height: Int)

    /// Update the viewport size
    ///
    /// Called when the visualization view is resized. The engine should adjust
    /// its rendering to match the new dimensions.
    ///
    /// - Parameters:
    ///   - width: New width in pixels
    ///   - height: New height in pixels
    ///
    /// - Note: This method may be called from the render thread
    func setViewportSize(width: Int, height: Int)

    /// Add mono PCM audio data for visualization
    ///
    /// This method is called from the audio processing thread with new audio samples.
    /// Implementations must be thread-safe.
    ///
    /// - Parameter samples: Array of mono PCM samples, normalized to [-1.0, 1.0]
    ///
    /// - Note: Called at high frequency (~60 times per second). Implementations
    ///   should minimize processing time.
    func addPCMMono(_ samples: [Float])

    /// Add a normalized magnitude spectrum for engines that consume host FFT data.
    ///
    /// ProjectM computes its own analysis from PCM, but Geiss mirrors Winamp's
    /// host contract and reads a 256-bin spectrum alongside waveform data.
    ///
    /// - Parameter mags: Magnitudes normalized to [0.0, 1.0]
    func setSpectrum(_ mags: [Float])

    /// Render a single frame
    ///
    /// Called by the CVDisplayLink callback to render the visualization.
    /// The OpenGL context will be current when this is called.
    ///
    /// - Note: Must maintain 60fps performance. Heavy processing should be
    ///   done in `addPCMMono()` instead.
    func renderFrame()

    /// False when the last `renderFrame` drew nothing (Tripex skips frames an effect is not due to
    /// draw), so the host keeps the previous frame on screen rather than presenting an undrawn
    /// buffer, which showed a stale picture and made the effect judder. Default: true.
    var drewLastFrame: Bool { get }

    /// Clean up resources when the engine is being destroyed
    ///
    /// Optional method for engines that need explicit cleanup. Called before
    /// the engine is deallocated.
    ///
    /// - Note: Default implementation does nothing
    func cleanup()

    // MARK: Presets
    //
    // Whatever the engine calls them (ProjectM's preset list, Geiss's, Tripex's and Goom's effects,
    // AVS's preset files, Corona's palettes, Smear's move scripts), every host reaches them through
    // these, forwarded once by `VisualizationGLView+Presets`. `hardCut` (switch without blending)
    // matters only to ProjectM, the one engine that blends.

    var presetCount: Int { get }
    /// The running preset's index, nil when there is none yet.
    var presetIndex: Int? { get }
    func presetName(at index: Int) -> String
    func selectPreset(at index: Int, hardCut: Bool)
    /// One preset forwards or backwards, wrapping.
    func stepPreset(forward: Bool, hardCut: Bool)
    func randomPreset(hardCut: Bool)

    /// The engine's own items in the shared menu (`VisualizationContextMenu`): only what no other
    /// engine has, targeting the engine itself so no host repeats them. Default: none. ProjectM's
    /// ratings stay in the menu itself, beside the star titles they share one ratings read with.
    func addMenuItems(to menu: NSMenu)
}

/// Default implementations for optional protocol methods
extension VisualizationEngine {
    func setSpectrum(_ mags: [Float]) {
        // Default: engine does not consume host-provided spectrum data.
    }

    func cleanup() {
        // Default: no cleanup needed
    }

    var drewLastFrame: Bool { true }

    func addMenuItems(to menu: NSMenu) {}
}

/// The canvas a software engine (Geiss, AVS, Corona, Smear) renders for a viewport. Their effects are
/// sized in pixels, so a small canvas shows a coarse close-up of the scene: in a skin's effects
/// slot (Sonique's top circle is 182x176 px) Geiss's waveform ran off both edges. Below
/// `minWidth` the canvas is scaled up, at the viewport's aspect, and the engine shrinks it to fit.
/// The scaled height stops at `maxScaledHeight` (a 1x600 viewport would ask for 400x240,000), so
/// only a viewport over 4:1 tall and under 400 px wide is drawn at another aspect.
enum SoftwareCanvas {
    static let minWidth = 400
    static let maxScaledHeight = 4 * minWidth

    static func atLeastMinimum(width: Int, height: Int) -> (width: Int, height: Int) {
        let width = max(1, width), height = max(1, height)
        guard width < minWidth else { return (width, height) }
        return (minWidth, min(height * minWidth / width, max(height, maxScaledHeight)))
    }
}

/// Available visualization engine types
///
/// Used to identify and switch between different visualization engines.
enum VisualizationType: String, CaseIterable, Codable {
    /// ProjectM engine (ProjectM/projectM presets)
    case projectM = "ProjectM (ProjectM)"

    /// Geiss engine (palette-LUT indexed framebuffer; stubbed in Phase 1)
    case geiss = "Geiss"

    /// Tripex engine (ben-marsh/tripex, ported to OpenGL on macOS)
    case tripex = "Tripex"

    /// Advanced Visualization Studio (vendored libavs; the `avs-port` skill)
    case avs = "AVS"

    /// Goom (j3k0/goom's Goom2k26 C core; the `goom-port` skill)
    case goom = "Goom"

    /// Corona (libvisual's port of the Sonique visualizer; the `corona-port` skill)
    case corona = "Corona"

    /// Smear (mykel and xplo's Sonique visualizer; the `smear-port` skill)
    case smear = "Smear"

    /// Engines fed the host spectrum (`VisualizationEngine.setSpectrum`) from the audio thread.
    var consumesHostSpectrum: Bool { self == .geiss || self == .corona || self == .smear }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .projectM:
            return "ProjectM"
        default:
            return self.rawValue
        }
    }
}
