import Foundation
import CoreAudio
import AudioToolbox
import Network

/// Represents an audio output device
struct AudioOutputDevice: Equatable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    /// True for AirPlay, Bluetooth, and other wireless devices
    let isWireless: Bool
    /// True if this is a discovered AirPlay device (not yet a Core Audio device)
    let isAirPlayDiscovered: Bool
    
    init(id: AudioDeviceID, uid: String, name: String, isWireless: Bool, isAirPlayDiscovered: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isWireless = isWireless
        self.isAirPlayDiscovered = isAirPlayDiscovered
    }
    
    static func == (lhs: AudioOutputDevice, rhs: AudioOutputDevice) -> Bool {
        return lhs.uid == rhs.uid
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

/// Manages audio output device discovery and selection using Core Audio
class AudioOutputManager {
    
    // MARK: - Singleton
    
    static let shared = AudioOutputManager()
    
    // MARK: - Notifications
    
    static let devicesDidChangeNotification = Notification.Name("AudioOutputDevicesDidChange")
    
    // MARK: - Properties
    
    /// All available output devices
    private(set) var outputDevices: [AudioOutputDevice] = []
    
    /// Currently selected device ID (nil means system default)
    private(set) var currentDeviceID: AudioDeviceID?
    
    /// UserDefaults key for persisted device UID
    private let savedDeviceUIDKey = "selectedAudioOutputDeviceUID"
    
    /// Discovered AirPlay devices (via Bonjour)
    private(set) var discoveredAirPlayDevices: [AudioOutputDevice] = []
    
    /// Network browser for AirPlay devices
    private var airPlayBrowser: NWBrowser?
    
    // MARK: - Initialization
    
    private init() {
        refreshDevices()
        setupDeviceChangeListener()
        startAirPlayDiscovery()
        
        // Debug: Write device info to file on startup
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.writeDeviceDebugInfoToFile()
        }
        #endif
    }
    
    deinit {
        removeDeviceChangeListener()
        airPlayBrowser?.cancel()
    }
    
    // MARK: - AirPlay Discovery
    
    private func startAirPlayDiscovery() {
        // Browse for AirPlay devices using Bonjour
        // AirPlay devices advertise as _airplay._tcp
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_airplay._tcp", domain: "local.")
        let parameters = NWParameters()
        
        airPlayBrowser = NWBrowser(for: descriptor, using: parameters)
        
        airPlayBrowser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleAirPlayBrowseResults(results)
        }
        
        airPlayBrowser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("AirPlay browser ready")
            case .failed(let error):
                print("AirPlay browser failed: \(error)")
            default:
                break
            }
        }
        
        airPlayBrowser?.start(queue: .main)
    }
    
    private func handleAirPlayBrowseResults(_ results: Set<NWBrowser.Result>) {
        var newDevices: [AudioOutputDevice] = []
        
        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, let interface):
                // Create a discovered AirPlay device
                let uid = "airplay:\(name).\(type).\(domain)"
                let device = AudioOutputDevice(
                    id: 0, // No Core Audio ID yet
                    uid: uid,
                    name: name,
                    isWireless: true,
                    isAirPlayDiscovered: true
                )
                newDevices.append(device)
            default:
                break
            }
        }
        
        // Filter out devices that already exist as Core Audio devices
        let coreAudioNames = Set(outputDevices.map { $0.name.lowercased() })
        discoveredAirPlayDevices = newDevices.filter { !coreAudioNames.contains($0.name.lowercased()) }
        
        // Notify observers
        NotificationCenter.default.post(name: Self.devicesDidChangeNotification, object: self)
    }
    
    /// Get all available devices (Core Audio + discovered AirPlay)
    var allOutputDevices: [AudioOutputDevice] {
        var all = outputDevices
        all.append(contentsOf: discoveredAirPlayDevices)
        return all
    }
    
    // MARK: - Device Enumeration
    
    /// Refresh the list of available output devices
    func refreshDevices() {
        outputDevices = enumerateOutputDevices()
        
        // Restore saved device if available
        if let savedUID = UserDefaults.standard.string(forKey: savedDeviceUIDKey),
           let device = outputDevices.first(where: { $0.uid == savedUID }) {
            currentDeviceID = device.id
        }
    }
    
    /// Enumerate all audio output devices
    private func enumerateOutputDevices() -> [AudioOutputDevice] {
        var devices: [AudioOutputDevice] = []
        
        // Get all audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("Failed to get audio devices size: \(status)")
            return devices
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("Failed to get audio devices: \(status)")
            return devices
        }
        
        // Filter for output devices and get their properties
        for deviceID in deviceIDs {
            if hasOutputChannels(deviceID: deviceID),
               let name = getDeviceName(deviceID: deviceID),
               let uid = getDeviceUID(deviceID: deviceID),
               !shouldHideDevice(deviceID: deviceID, name: name) {
                let isWireless = checkIfWireless(deviceID: deviceID)
                let device = AudioOutputDevice(id: deviceID, uid: uid, name: name, isWireless: isWireless, isAirPlayDiscovered: false)
                devices.append(device)
            }
        }
        
        // Sort: wired devices first, then wireless, alphabetically within each group
        devices.sort { device1, device2 in
            if device1.isWireless != device2.isWireless {
                return !device1.isWireless // Wired first
            }
            return device1.name.localizedCaseInsensitiveCompare(device2.name) == .orderedAscending
        }
        
        return devices
    }
    
    /// Check if a device has output channels
    private func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        
        guard status == noErr, dataSize > 0 else { return false }
        
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }
        
        let getStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard getStatus == noErr else { return false }
        
        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }
    
    /// Get the name of a device
    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var name: Unmanaged<CFString>?
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        
        guard status == noErr, let cfName = name?.takeUnretainedValue() else { return nil }
        return cfName as String
    }
    
    /// Get the UID of a device (persistent identifier)
    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uid: Unmanaged<CFString>?
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)
        
        guard status == noErr, let cfUID = uid?.takeUnretainedValue() else { return nil }
        return cfUID as String
    }
    
    /// Check if a device is a wireless device (AirPlay, Bluetooth, Sonos, HomePod, etc.)
    private func checkIfWireless(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &transportType)
        
        guard status == noErr else { return false }
        
        // Transport types for wireless/network devices:
        // kAudioDeviceTransportTypeAirPlay = 'airp' = 0x61697270
        // kAudioDeviceTransportTypeAVB = 'eavb' = 0x65617662 (Ethernet Audio Video Bridging)
        // kAudioDeviceTransportTypeBluetooth = 'blue' = 0x626C7565
        // kAudioDeviceTransportTypeBluetoothLE = 'blea' = 0x626C6561
        let wirelessTypes: Set<UInt32> = [
            0x61697270, // 'airp' - AirPlay
            0x65617662, // 'eavb' - AVB (network audio)
            0x626C7565, // 'blue' - Bluetooth
            0x626C6561, // 'blea' - Bluetooth LE
        ]
        
        if wirelessTypes.contains(transportType) {
            return true
        }
        
        // Also check device name for common wireless speaker patterns
        if let name = getDeviceName(deviceID: deviceID)?.lowercased() {
            let wirelessPatterns = ["airplay", "sonos", "homepod", "airpod", "bluetooth", "wireless"]
            for pattern in wirelessPatterns {
                if name.contains(pattern) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Check if a device should be hidden (aggregate devices, etc.)
    private func shouldHideDevice(deviceID: AudioDeviceID, name: String) -> Bool {
        // Hide devices with empty or placeholder names
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            return true
        }
        
        // Check transport type for aggregate/multi-output devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &transportType)
        
        if status == noErr {
            // kAudioDeviceTransportTypeAggregate = 'grup' = 0x67727570
            // Hide aggregate devices unless they have a user-friendly name
            if transportType == 0x67727570 {
                // Hide system-generated aggregate devices (they have auto-generated names)
                if name.contains("CADefaultDeviceAggregate") || name.contains("CAAggregate") {
                    return true
                }
                // Allow aggregate devices that seem intentional (like "Multi-Output Device")
                let allowedAggregatePatterns = ["Multi-Output", "Aggregate Device"]
                let isAllowed = allowedAggregatePatterns.contains { name.contains($0) }
                return !isAllowed
            }
        }
        
        return false
    }
    
    /// Get transport type name for debugging
    private func getTransportTypeName(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &transportType)
        guard status == noErr else { return "unknown" }
        
        // Convert FourCC to string
        let chars = [
            Character(UnicodeScalar((transportType >> 24) & 0xFF)!),
            Character(UnicodeScalar((transportType >> 16) & 0xFF)!),
            Character(UnicodeScalar((transportType >> 8) & 0xFF)!),
            Character(UnicodeScalar(transportType & 0xFF)!)
        ]
        return String(chars)
    }
    
    /// Print debug info about all detected audio devices
    func printDeviceDebugInfo() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            print("Failed to get devices size")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            print("Failed to get devices")
            return
        }
        
        print("=== Audio Device Debug Info ===")
        print("Total devices found: \(deviceCount)")
        
        for deviceID in deviceIDs {
            let name = getDeviceName(deviceID: deviceID) ?? "(no name)"
            let uid = getDeviceUID(deviceID: deviceID) ?? "(no uid)"
            let transportType = getTransportTypeName(deviceID: deviceID)
            let hasOutput = hasOutputChannels(deviceID: deviceID)
            let isWireless = checkIfWireless(deviceID: deviceID)
            let isHidden = shouldHideDevice(deviceID: deviceID, name: name)
            
            print("  Device ID: \(deviceID)")
            print("    Name: \(name)")
            print("    UID: \(uid)")
            print("    Transport: \(transportType)")
            print("    Has Output: \(hasOutput)")
            print("    Is Wireless: \(isWireless)")
            print("    Hidden: \(isHidden)")
            print("")
        }
        print("=== End Debug Info ===")
    }
    
    /// Write debug info to a file for easier inspection
    func writeDeviceDebugInfoToFile() {
        var output = "=== Audio Device Debug Info ===\n"
        output += "Generated: \(Date())\n\n"
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            output += "Failed to get devices size\n"
            writeToFile(output)
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            output += "Failed to get devices\n"
            writeToFile(output)
            return
        }
        
        output += "Total devices found: \(deviceCount)\n\n"
        
        for deviceID in deviceIDs {
            let name = getDeviceName(deviceID: deviceID) ?? "(no name)"
            let uid = getDeviceUID(deviceID: deviceID) ?? "(no uid)"
            let transportType = getTransportTypeName(deviceID: deviceID)
            let hasOutput = hasOutputChannels(deviceID: deviceID)
            let isWireless = checkIfWireless(deviceID: deviceID)
            let isHidden = shouldHideDevice(deviceID: deviceID, name: name)
            
            output += "Device ID: \(deviceID)\n"
            output += "  Name: \(name)\n"
            output += "  UID: \(uid)\n"
            output += "  Transport: \(transportType)\n"
            output += "  Has Output: \(hasOutput)\n"
            output += "  Is Wireless: \(isWireless)\n"
            output += "  Hidden: \(isHidden)\n"
            output += "  VISIBLE IN MENU: \(hasOutput && !isHidden)\n"
            output += "\n"
        }
        
        output += "=== Devices in outputDevices array ===\n"
        for device in outputDevices {
            output += "  - \(device.name) (wireless: \(device.isWireless))\n"
        }
        
        output += "\n=== Discovered AirPlay Devices ===\n"
        if discoveredAirPlayDevices.isEmpty {
            output += "  (none found yet - discovery in progress)\n"
        } else {
            for device in discoveredAirPlayDevices {
                output += "  - \(device.name)\n"
            }
        }
        
        writeToFile(output)
    }
    
    private func writeToFile(_ content: String) {
        let path = "/tmp/adamp_audio_devices.txt"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        print("Audio device debug info written to: \(path)")
    }
    
    /// Get the system default output device ID
    func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        return status == noErr ? deviceID : nil
    }
    
    // MARK: - Device Selection
    
    /// Select an output device by ID
    /// - Parameter deviceID: The device ID to select, or nil for system default
    func selectDevice(_ deviceID: AudioDeviceID?) {
        currentDeviceID = deviceID
        
        // Save the UID for persistence
        if let deviceID = deviceID,
           let device = outputDevices.first(where: { $0.id == deviceID }) {
            UserDefaults.standard.set(device.uid, forKey: savedDeviceUIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: savedDeviceUIDKey)
        }
    }
    
    /// Get device by UID
    func device(withUID uid: String) -> AudioOutputDevice? {
        return outputDevices.first { $0.uid == uid }
    }
    
    // MARK: - Device Change Listener
    
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    
    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        listenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                self?.handleDevicesChanged()
            }
        }
        
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )
        
        if status != noErr {
            print("Failed to add device change listener: \(status)")
        }
    }
    
    private func removeDeviceChangeListener() {
        guard let block = listenerBlock else { return }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }
    
    private func handleDevicesChanged() {
        let previousDevices = outputDevices
        refreshDevices()
        
        // Check if selected device is still available
        if let currentID = currentDeviceID,
           !outputDevices.contains(where: { $0.id == currentID }) {
            // Device was removed, reset to default
            currentDeviceID = nil
            UserDefaults.standard.removeObject(forKey: savedDeviceUIDKey)
        }
        
        // Notify observers if devices changed
        if previousDevices != outputDevices {
            NotificationCenter.default.post(name: Self.devicesDidChangeNotification, object: self)
        }
    }
}
