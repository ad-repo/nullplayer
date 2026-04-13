import Foundation

// MARK: - PlaybackSleepEvent

public enum PlaybackSleepEvent: Sendable {
    case willSleep
    case didWake
}

// MARK: - PlaybackPreferencesProviding

/// Persisted playback preferences. Darwin implementation reads/writes UserDefaults;
/// a Linux stub can return defaults or read from a config file.
public protocol PlaybackPreferencesProviding: AnyObject {
    var gaplessPlaybackEnabled: Bool { get set }
    var volumeNormalizationEnabled: Bool { get set }
    var sweetFadeEnabled: Bool { get set }
    var sweetFadeDuration: TimeInterval { get set }
    /// Canonical key: selectedOutputDevicePersistentID
    var selectedOutputDevicePersistentID: String? { get set }
}

// MARK: - PlaybackEnvironmentProviding

/// Platform services consumed by AudioEngineFacade that are not part of the audio graph.
/// Darwin implementation uses NSAlert, NSWorkspace, and temp-file policy from AudioEngine.
/// A Linux implementation can stub or replace each service independently.
public protocol PlaybackEnvironmentProviding: AnyObject {
    /// Show or log a non-fatal playback error (e.g. unsupported format, NAS copy failure).
    func reportNonFatalPlaybackError(_ message: String)
    /// Copy a remote/NAS file to a local temp path for reliable playback access.
    /// Returns the original URL unchanged if no copy is needed (e.g. already local).
    func makeTemporaryPlaybackURLIfNeeded(for originalURL: URL) throws -> URL
    /// Register a handler to be called on system sleep/wake events.
    func beginSleepObservation(_ handler: @escaping @Sendable (PlaybackSleepEvent) -> Void)
}
