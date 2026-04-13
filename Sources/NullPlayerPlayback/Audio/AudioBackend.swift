import Foundation
import NullPlayerCore

/// Protocol implemented by each platform's audio backend (Darwin AVAudioEngine, Linux GStreamer, etc.).
/// Backends emit AudioBackendEvent via eventHandler; they must NOT call delegates or mutate playlist state.
/// All Track references are NullPlayerCore.Track, not the app-local Track.
public protocol AudioBackend: AudioOutputRouting {
    var capabilities: AudioBackendCapabilities { get }
    var eventHandler: (@Sendable (AudioBackendEvent) -> Void)? { get set }

    /// Called once before first use. Backends should allocate resources here, not in init.
    func prepare()
    /// Tear down resources. No events should be emitted after shutdown returns.
    func shutdown()

    // MARK: Transport

    func load(track: NullPlayerCore.Track, token: UInt64, startPaused: Bool)
    func play(token: UInt64)
    func pause(token: UInt64)
    func stop(token: UInt64)
    func seek(to time: TimeInterval, token: UInt64)

    // MARK: Levels

    func setVolume(_ value: Float, token: UInt64)
    func setBalance(_ value: Float, token: UInt64)
    /// Band count must match capabilities.eqBandCount.
    func setEQ(enabled: Bool, preamp: Float, bands: [Float], token: UInt64)

    // MARK: Gapless hint

    /// Optional pre-roll hint for the next track. Backends that do not support gapless may ignore this.
    func setNextTrackHint(_ track: NullPlayerCore.Track?, token: UInt64)
}
