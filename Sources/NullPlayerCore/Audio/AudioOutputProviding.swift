public protocol AudioOutputProviding: AnyObject {
    var outputDevices: [AudioOutputDevice] { get }
    var currentDeviceUID: String? { get }
    func refreshDevices()
    func selectDevice(uid: String) -> Bool
}
