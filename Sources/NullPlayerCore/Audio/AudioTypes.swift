import Foundation

/// Transport type for an audio output device.
/// Replaces the old isWireless / isAirPlayDiscovered booleans.
public enum AudioOutputTransport: String, Sendable {
    case builtIn
    case usb
    case bluetooth
    case airplay
    case network
    case unknown
}

/// Represents an audio output device with a backend-neutral stable identifier.
public struct AudioOutputDevice: Equatable, Hashable, Sendable {
    /// Stable string identifier that survives reboots and device reordering.
    /// Darwin: CoreAudio UID. Linux: hardware serial, device path, or hashed name.
    public let persistentID: String
    public let name: String
    /// Backend name, e.g. "CoreAudio" on Darwin, "GStreamer" on Linux.
    public let backend: String
    /// Optional backend-native ID (e.g. CoreAudio AudioDeviceID as a string). Internal use only.
    public let backendID: String?
    public let transport: AudioOutputTransport
    public let isAvailable: Bool

    public init(
        persistentID: String,
        name: String,
        backend: String,
        backendID: String? = nil,
        transport: AudioOutputTransport,
        isAvailable: Bool = true
    ) {
        self.persistentID = persistentID
        self.name = name
        self.backend = backend
        self.backendID = backendID
        self.transport = transport
        self.isAvailable = isAvailable
    }

    public static func == (lhs: AudioOutputDevice, rhs: AudioOutputDevice) -> Bool {
        return lhs.persistentID == rhs.persistentID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(persistentID)
    }
}

/// Notification name for audio output device changes
public let AudioOutputDevicesDidChangeNotification = Notification.Name("AudioOutputDevicesDidChange")
