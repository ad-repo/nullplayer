#if os(Linux)
import Foundation
import CGStreamer
import NullPlayerCore

final class GStreamerOutputRouter: AudioOutputRouting {
    private let queue = DispatchQueue(label: "NullPlayer.GStreamerOutputRouter")
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private var devices: [AudioOutputDevice] = []
    private var currentPersistentID: String?
    private var monitor: UnsafeMutablePointer<GstDeviceMonitor>?
    private var pollTimer: DispatchSourceTimer?

    var onDevicesChanged: (@Sendable ([AudioOutputDevice], AudioOutputDevice?) -> Void)?

    init() {
        queue.setSpecific(key: Self.queueKey, value: 1)
        setupMonitorIfNeeded()
        refreshOutputs()
        startPolling()
    }

    deinit {
        pollTimer?.cancel()
        pollTimer = nil

        if let monitor {
            _ = gst_device_monitor_stop(monitor)
            gst_object_unref(UnsafeMutableRawPointer(monitor))
        }
    }

    var outputDevices: [AudioOutputDevice] {
        queue.sync { devices }
    }

    var currentOutputDevice: AudioOutputDevice? {
        queue.sync {
            guard let currentPersistentID else { return nil }
            return devices.first { $0.persistentID == currentPersistentID }
        }
    }

    func refreshOutputs() {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            refreshOutputsOnQueue()
            return
        }
        queue.sync { refreshOutputsOnQueue() }
    }

    @discardableResult
    func selectOutputDevice(persistentID: String?) -> Bool {
        queue.sync {
            guard let persistentID else {
                currentPersistentID = nil
                return true
            }

            guard devices.contains(where: { $0.persistentID == persistentID }) else {
                return false
            }

            currentPersistentID = persistentID
            return true
        }
    }

    func preferredOutputSinkFactory() -> String {
        // Phase 2 MVP: keep sink type stable and route through default system backend.
        // Device-specific sink creation can be layered on top of selected GstDevice later.
        return "autoaudiosink"
    }

    private func setupMonitorIfNeeded() {
        guard monitor == nil else { return }
        guard let monitor = gst_device_monitor_new() else { return }

        _ = gst_device_monitor_add_filter(monitor, "Audio/Sink", nil)
        _ = gst_device_monitor_start(monitor)

        self.monitor = monitor
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.refreshOutputs()
        }
        timer.resume()
        pollTimer = timer
    }

    private func refreshOutputsOnQueue() {
        let previousDevices = devices
        devices = enumerateDevices()

        if let currentPersistentID,
           !devices.contains(where: { $0.persistentID == currentPersistentID }) {
            self.currentPersistentID = nil
        }

        if self.currentPersistentID == nil {
            self.currentPersistentID = devices.first?.persistentID
        }

        if previousDevices != devices {
            let current = currentPersistentID.flatMap { id in
                devices.first { $0.persistentID == id }
            }
            onDevicesChanged?(devices, current)
        }
    }

    private func enumerateDevices() -> [AudioOutputDevice] {
        guard let monitor,
              let list = gst_device_monitor_get_devices(monitor) else {
            return [
                AudioOutputDevice(
                    persistentID: "gstreamer:auto",
                    name: "System Default",
                    backend: "GStreamer",
                    backendID: nil,
                    transport: .unknown,
                    isAvailable: true
                )
            ]
        }

        defer {
            g_list_free(list)
        }

        var results: [AudioOutputDevice] = []
        var node: UnsafeMutablePointer<GList>? = list

        while let entry = node {
            guard let data = entry.pointee.data else {
                node = entry.pointee.next
                continue
            }

            let device = data.assumingMemoryBound(to: GstDevice.self)
            let displayName = gst_device_get_display_name(device).map { String(cString: $0) } ?? "Unknown Output"
            let deviceClass = gst_device_get_device_class(device).map { String(cString: $0) } ?? "Audio/Sink"

            var persistentID: String?
            var backendID: String?

            if let properties = gst_device_get_properties(device) {
                persistentID = makePersistentID(from: properties, displayName: displayName, backend: deviceClass)
                backendID = firstProperty(in: properties, keys: [
                    "device.api",
                    "device.path",
                    "alsa.card_name",
                    "object.path"
                ])
                gst_structure_free(properties)
            }

            let stableID = persistentID ?? "display:\(fnv1a64(displayName.lowercased()))"
            let transport = inferTransport(from: displayName, deviceClass: deviceClass)

            results.append(
                AudioOutputDevice(
                    persistentID: stableID,
                    name: displayName,
                    backend: "GStreamer",
                    backendID: backendID,
                    transport: transport,
                    isAvailable: true
                )
            )

            gst_object_unref(UnsafeMutableRawPointer(device))

            node = entry.pointee.next
        }

        results.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if results.isEmpty {
            results.append(
                AudioOutputDevice(
                    persistentID: "gstreamer:auto",
                    name: "System Default",
                    backend: "GStreamer",
                    backendID: nil,
                    transport: .unknown,
                    isAvailable: true
                )
            )
        }

        return results
    }

    private func makePersistentID(
        from properties: UnsafeMutablePointer<GstStructure>,
        displayName: String,
        backend: String
    ) -> String {
        if let serial = firstProperty(in: properties, keys: [
            "device.serial",
            "alsa.card.serial",
            "serial"
        ]), !serial.isEmpty {
            return "serial:\(serial)"
        }

        if let path = firstProperty(in: properties, keys: [
            "device.path",
            "sysfs.path",
            "object.path"
        ]), !path.isEmpty {
            return "path:\(backend):\(path)"
        }

        if let uniqueName = firstProperty(in: properties, keys: [
            "device.name",
            "device.id",
            "alsa.card",
            "api.alsa.card"
        ]), !uniqueName.isEmpty {
            return "name:\(backend):\(uniqueName)"
        }

        return "display:\(fnv1a64(displayName.lowercased()))"
    }

    private func firstProperty(
        in structure: UnsafeMutablePointer<GstStructure>,
        keys: [String]
    ) -> String? {
        for key in keys {
            let value: String? = key.withCString { keyPtr in
                guard let pointer = gst_structure_get_string(structure, keyPtr) else {
                    return nil
                }
                return String(cString: pointer)
            }
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func inferTransport(from displayName: String, deviceClass: String) -> AudioOutputTransport {
        let text = "\(displayName) \(deviceClass)".lowercased()
        if text.contains("bluetooth") {
            return .bluetooth
        }
        if text.contains("airplay") {
            return .airplay
        }
        if text.contains("usb") {
            return .usb
        }
        if text.contains("network") || text.contains("remote") {
            return .network
        }
        if text.contains("built-in") || text.contains("internal") {
            return .builtIn
        }
        return .unknown
    }

    private func fnv1a64(_ text: String) -> String {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}
#endif
