import Foundation

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

    /// Render a single frame
    ///
    /// Called by the CVDisplayLink callback to render the visualization.
    /// The OpenGL context will be current when this is called.
    ///
    /// - Note: Must maintain 60fps performance. Heavy processing should be
    ///   done in `addPCMMono()` instead.
    func renderFrame()

    /// Clean up resources when the engine is being destroyed
    ///
    /// Optional method for engines that need explicit cleanup. Called before
    /// the engine is deallocated.
    ///
    /// - Note: Default implementation does nothing
    func cleanup()
}

/// Default implementations for optional protocol methods
extension VisualizationEngine {
    func cleanup() {
        // Default: no cleanup needed
    }
}

/// Available visualization engine types
///
/// Used to identify and switch between different visualization engines.
enum VisualizationType: String, CaseIterable, Codable {
    /// ProjectM engine (Milkdrop/WinAmp presets)
    case projectM = "ProjectM (Milkdrop)"

    /// TOC Spectrum analyzer
    case tocSpectrum = "TOC Spectrum"

    /// Human-readable display name
    var displayName: String {
        return self.rawValue
    }
}
