import Foundation
import NullPlayerCore

// MARK: - PlaybackFailure

public struct PlaybackFailure: Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - AnalysisFrame

/// Interleaved stereo float32 PCM frame from the audio backend.
/// Backed by mach_absolute_time on Darwin, CLOCK_MONOTONIC on Linux.
public struct AnalysisFrame: Sendable {
    public let samples: [Float]
    public let channels: Int
    public let sampleRate: Double
    /// Monotonic elapsed time since process start (seconds), for frame ordering.
    public let monotonicTime: TimeInterval?

    public init(samples: [Float], channels: Int, sampleRate: Double, monotonicTime: TimeInterval?) {
        self.samples = samples
        self.channels = channels
        self.sampleRate = sampleRate
        self.monotonicTime = monotonicTime
    }
}

// MARK: - AudioBackendEvent

/// Events emitted by an AudioBackend implementation and consumed by AudioEngineFacade.
/// All Track references use NullPlayerCore.Track, not the app-local Track.
public enum AudioBackendEvent: Sendable {
    case stateChanged(PlaybackState, token: UInt64)
    case timeUpdated(current: TimeInterval, duration: TimeInterval, token: UInt64)
    case endOfStream(token: UInt64)
    case loadFailed(track: NullPlayerCore.Track, failure: PlaybackFailure, token: UInt64)
    case formatChanged(sampleRate: Double, channels: Int, token: UInt64)
    case analysisFrame(AnalysisFrame, token: UInt64)
    case outputsChanged([AudioOutputDevice], current: AudioOutputDevice?)
}
