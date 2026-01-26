import Foundation

/// Represents an audio output device
public struct AudioOutputDevice: Equatable, Hashable, Sendable {
    public let id: UInt32  // AudioDeviceID
    public let uid: String
    public let name: String
    /// True for AirPlay, Bluetooth, and other wireless devices
    public let isWireless: Bool
    /// True if this is a discovered AirPlay device (not yet a Core Audio device)
    public let isAirPlayDiscovered: Bool
    
    public init(id: UInt32, uid: String, name: String, isWireless: Bool, isAirPlayDiscovered: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isWireless = isWireless
        self.isAirPlayDiscovered = isAirPlayDiscovered
    }
    
    public static func == (lhs: AudioOutputDevice, rhs: AudioOutputDevice) -> Bool {
        return lhs.uid == rhs.uid
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

/// Notification name for audio output device changes
public let AudioOutputDevicesDidChangeNotification = Notification.Name("AudioOutputDevicesDidChange")
