import Foundation
import NullPlayerCore

/// Shared routing surface consumed by both the facade and CLI code.
/// Backends conform to this protocol; CLI and engine code must access
/// output routing only through this abstraction, never via platform-specific managers directly.
public protocol AudioOutputRouting: AnyObject {
    var outputDevices: [AudioOutputDevice] { get }
    var currentOutputDevice: AudioOutputDevice? { get }
    func refreshOutputs()
    @discardableResult
    func selectOutputDevice(persistentID: String?) -> Bool
}
