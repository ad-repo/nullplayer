public protocol AudioOutputProviding: AnyObject {
    var outputDevices: [AudioOutputDevice] { get }
    var currentOutputDevice: AudioOutputDevice? { get }
    func refreshOutputs()
    @discardableResult
    func selectOutputDevice(persistentID: String?) -> Bool
}
