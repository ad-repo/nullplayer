import Foundation

/// Static capabilities advertised by an AudioBackend implementation.
/// Used by AudioEngineFacade to gate features like gapless playback, sweet-fade, and EQ.
public struct AudioBackendCapabilities: Sendable {
    public let supportsOutputSelection: Bool
    public let supportsGaplessPlayback: Bool
    public let supportsSweetFade: Bool
    public let supportsEQ: Bool
    public let supportsWaveformFrames: Bool
    /// Number of EQ bands the backend supports. Must match the band count passed to setEQ.
    public let eqBandCount: Int

    public init(
        supportsOutputSelection: Bool,
        supportsGaplessPlayback: Bool,
        supportsSweetFade: Bool,
        supportsEQ: Bool,
        supportsWaveformFrames: Bool,
        eqBandCount: Int
    ) {
        self.supportsOutputSelection = supportsOutputSelection
        self.supportsGaplessPlayback = supportsGaplessPlayback
        self.supportsSweetFade = supportsSweetFade
        self.supportsEQ = supportsEQ
        self.supportsWaveformFrames = supportsWaveformFrames
        self.eqBandCount = eqBandCount
    }
}
