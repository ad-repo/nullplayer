import Foundation
import CoreAudio
import AudioToolbox
import Network
import NullPlayerCore
import NullPlayerPlayback

/// Manages audio output device discovery and selection using Core Audio
class AudioOutputManager: AudioOutputProviding, AudioOutputRouting {
    
    // MARK: - Singleton
    
    static let shared = AudioOutputManager()
    
    // MARK: - Notifications
    
    static let devicesDidChangeNotification = AudioOutputDevicesDidChangeNotification
    
    // MARK: - Properties
    
    /// All available output devices
    private(set) var outputDevices: [AudioOutputDevice] = []
    
    /// Currently selected device ID (nil means system default)
    private(set) var currentDeviceID: AudioDeviceID?

    var currentOutputDevice: AudioOutputDevice? {
        if let currentDeviceID {
            return outputDevices.first(where: { $0.backendID == String(currentDeviceID) })
        }
        if let savedID = UserDefaults.standard.string(forKey: savedDeviceUIDKey) {
            return outputDevices.first(where: { $0.persistentID == savedID })
        }
        return nil
    }
    
    /// Canonical UserDefaults key for persisted output device.
    static let savedDevicePersistentIDKey = "selectedOutputDevicePersistentID"
    /// Legacy keys checked once for migration, then removed.
    static let legacyDevicePersistentIDKeys = ["selectedOutputDeviceUID", "selectedAudioOutputDeviceUID"]

    private let savedDeviceUIDKey = AudioOutputManager.savedDevicePersistentIDKey
    private let legacyDeviceUIDKeys = AudioOutputManager.legacyDevicePersistentIDKeys
    
    /// Discovered AirPlay devices (via Bonjour)
    private(set) var discoveredAirPlayDevices: [AudioOutputDevice] = []
    
    /// Network browser for AirPlay devices
    private var airPlayBrowser: NWBrowser?
    
    // MARK: - Initialization
    
    private init() {
        refreshOutputs()
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
                    persistentID: uid,
                    name: name,
                    backend: "CoreAudio",
                    backendID: nil,
                    transport: .airplay
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
        NotificationCenter.default.post(name: AudioOutputDevicesDidChangeNotification, object: self)
    }
    
    /// Get all available devices (Core Audio + discovered AirPlay)
    var allOutputDevices: [AudioOutputDevice] {
        var all = outputDevices
        all.append(contentsOf: discoveredAirPlayDevices)
        return all
    }
    
    // MARK: - Device Enumeration
    
    /// Refresh the list of available output devices
    func refreshOutputs() {
        outputDevices = enumerateOutputDevices()

        let savedID = AudioOutputManager.resolvePersistedOutputDevicePersistentID(
            defaults: .standard,
            availablePersistentIDs: Set(outputDevices.map(\.persistentID))
        )

        if let savedID,
           let device = outputDevices.first(where: { $0.persistentID == savedID }),
           let backendIDStr = device.backendID,
           let deviceID = AudioDeviceID(backendIDStr) {
            currentDeviceID = deviceID
        }
    }

    @available(*, deprecated, renamed: "refreshOutputs")
    func refreshDevices() { refreshOutputs() }

    static func resolvePersistedOutputDevicePersistentID(
        defaults: UserDefaults = .standard,
        availablePersistentIDs: Set<String>? = nil
    ) -> String? {
        let canonical = savedDevicePersistentIDKey
        let legacy = legacyDevicePersistentIDKeys

        var resolved = defaults.string(forKey: canonical)

        if resolved == nil {
            resolved = legacy.compactMap { defaults.string(forKey: $0) }.first
            if let resolved {
                defaults.set(resolved, forKey: canonical)
            }
        }

        for key in legacy where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }

        if let resolved,
           let availablePersistentIDs,
           !availablePersistentIDs.contains(resolved) {
            defaults.removeObject(forKey: canonical)
            return nil
        }

        return resolved
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
                let transport = checkTransport(deviceID: deviceID)
                let device = AudioOutputDevice(
                    persistentID: uid,
                    name: name,
                    backend: "CoreAudio",
                    backendID: String(deviceID),
                    transport: transport
                )
                devices.append(device)
            }
        }
        
        // Sort: wired/built-in first, then wireless, alphabetically within each group
        devices.sort { device1, device2 in
            let w1 = device1.transport == .airplay || device1.transport == .bluetooth || device1.transport == .network
            let w2 = device2.transport == .airplay || device2.transport == .bluetooth || device2.transport == .network
            if w1 != w2 { return !w1 }
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
    
    /// Map CoreAudio transport type to the portable AudioOutputTransport enum.
    private func checkTransport(deviceID: AudioDeviceID) -> AudioOutputTransport {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &transportType)
        guard status == noErr else { return .unknown }

        // CoreAudio FourCC transport codes
        switch transportType {
        case 0x626C746E: return .builtIn    // 'bltn' kAudioDeviceTransportTypeBuiltIn
        case 0x7573626D: return .usb        // 'usbm' kAudioDeviceTransportTypeUSB
        case 0x626C7565,
             0x626C6561: return .bluetooth  // 'blue'/'blea' Bluetooth/BLE
        case 0x61697270: return .airplay    // 'airp' kAudioDeviceTransportTypeAirPlay
        case 0x65617662: return .network    // 'eavb' kAudioDeviceTransportTypeAVB
        default: break
        }

        // Fallback: check device name for common wireless speaker patterns
        if let name = getDeviceName(deviceID: deviceID)?.lowercased() {
            let wirelessPatterns = ["airplay", "sonos", "homepod", "airpod", "bluetooth", "wireless"]
            if wirelessPatterns.contains(where: { name.contains($0) }) { return .network }
        }

        return .unknown
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
            let isWireless = checkTransport(deviceID: deviceID) != .builtIn && checkTransport(deviceID: deviceID) != .usb && checkTransport(deviceID: deviceID) != .unknown
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
            output += "  - \(device.name) (transport: \(device.transport))\n"
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
        let path = "/tmp/nullplayer_audio_devices.txt"
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
    
    /// Select an output device by CoreAudio device ID (internal use only).
    func selectDevice(_ deviceID: AudioDeviceID?) {
        currentDeviceID = deviceID

        if let deviceID = deviceID,
           let device = outputDevices.first(where: { $0.backendID == String(deviceID) }) {
            UserDefaults.standard.set(device.persistentID, forKey: savedDeviceUIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: savedDeviceUIDKey)
        }
    }

    func selectOutputDevice(persistentID: String?) -> Bool {
        guard let persistentID else {
            selectDevice(nil)
            return true
        }
        guard let device = outputDevices.first(where: { $0.persistentID == persistentID }),
              let backendIDStr = device.backendID,
              let deviceID = AudioDeviceID(backendIDStr) else {
            return false
        }
        selectDevice(deviceID)
        return true
    }

    @available(*, deprecated, renamed: "selectOutputDevice(persistentID:)")
    func selectDevice(uid: String) -> Bool {
        return selectOutputDevice(persistentID: uid)
    }

    /// Get device by persistent ID (Darwin: CoreAudio UID).
    func device(withUID uid: String) -> AudioOutputDevice? {
        return outputDevices.first { $0.persistentID == uid }
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
        refreshOutputs()
        
        // Check if selected device is still available
        if let currentID = currentDeviceID,
           !outputDevices.contains(where: { $0.backendID == String(currentID) }) {
            // Device was removed, reset to default
            currentDeviceID = nil
            UserDefaults.standard.removeObject(forKey: savedDeviceUIDKey)
        }

        // Notify observers if devices changed
        if previousDevices != outputDevices {
            NotificationCenter.default.post(name: AudioOutputDevicesDidChangeNotification, object: self)
        }
    }
}

enum AudioOutputRoutingProvider {
    static var shared: any AudioOutputRouting {
        AudioOutputManager.shared
    }
}
