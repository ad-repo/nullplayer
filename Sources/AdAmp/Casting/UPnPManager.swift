import Foundation
import Network

/// UPnP/DLNA manager for discovering and controlling Sonos speakers and DLNA TVs
/// Uses SSDP for discovery and SOAP for AVTransport control
class UPnPManager {
    
    // MARK: - Singleton
    
    static let shared = UPnPManager()
    
    // MARK: - Properties
    
    /// Serial queue for thread-safe state access
    private let stateQueue = DispatchQueue(label: "com.adamp.upnp.state")
    
    /// Discovered UPnP devices (Sonos + DLNA TVs) - access via stateQueue
    private var _devices: [CastDevice] = []
    var devices: [CastDevice] {
        stateQueue.sync { _devices }
    }
    
    /// Active cast session
    private(set) var activeSession: CastSession?
    
    /// Discovery state
    private(set) var isDiscovering: Bool = false
    
    /// BSD socket for SSDP
    private var ssdpSocket: Int32 = -1
    
    /// Dispatch source for reading socket
    private var readSource: DispatchSourceRead?
    
    /// Pending device descriptions being fetched - access via stateQueue
    private var _pendingDescriptions: Set<String> = []
    
    /// Sonos zone information for group detection
    private var sonosZones: [String: SonosZoneInfo] = [:]  // UDN -> ZoneInfo
    private var sonosGroupsFetched = false
    
    // MARK: - Sonos Zone Types
    
    /// Information about a Sonos zone (speaker)
    private struct SonosZoneInfo {
        let udn: String
        let roomName: String
        let address: String
        let port: Int
        let avTransportURL: URL?
        let descriptionURL: URL
    }
    
    /// Sonos group with coordinator and members
    private struct SonosGroup {
        let coordinatorUDN: String
        let memberUDNs: [String]
        
        var memberCount: Int { memberUDNs.count }
    }
    
    // MARK: - Constants
    
    /// SSDP multicast address
    private let ssdpMulticastAddress = "239.255.255.250"
    private let ssdpPort: UInt16 = 1900
    
    /// Search targets for discovery - only actual media renderers
    private let searchTargets = [
        "urn:schemas-upnp-org:device:MediaRenderer:1",  // DLNA TVs and media renderers
        "urn:schemas-upnp-org:device:ZonePlayer:1"      // Sonos speakers
    ]
    
    /// Known manufacturer patterns for Sonos
    private let sonosManufacturers = ["sonos"]
    
    /// Known TV manufacturers that support DLNA casting
    private let tvManufacturers = ["samsung", "lg", "sony", "vizio", "philips", "panasonic", "hisense", "tcl", "sharp", "toshiba"]
    
    /// Manufacturers/devices to explicitly exclude (not castable)
    private let excludedManufacturers = ["synology", "netgear", "directv", "pace", "signify", "philips hue", "qnap", "western digital", "asustor"]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Discovery
    
    /// Start discovering UPnP devices on the network
    func startDiscovery() {
        guard !isDiscovering else { return }
        
        NSLog("UPnPManager: Starting SSDP discovery...")
        isDiscovering = true
        
        // Create and configure UDP socket
        setupSocket()
        
        // Send M-SEARCH requests with delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendMSearchRequests()
        }
        
        // Repeat search periodically
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard self?.isDiscovering == true else { return }
            self?.sendMSearchRequests()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard self?.isDiscovering == true else { return }
            self?.sendMSearchRequests()
        }
    }
    
    /// Stop discovering devices
    func stopDiscovery() {
        NSLog("UPnPManager: Stopping discovery")
        isDiscovering = false
        
        readSource?.cancel()
        readSource = nil
        
        if ssdpSocket >= 0 {
            close(ssdpSocket)
            ssdpSocket = -1
        }
    }
    
    /// Setup UDP socket for SSDP
    private func setupSocket() {
        // Create UDP socket
        ssdpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard ssdpSocket >= 0 else {
            NSLog("UPnPManager: Failed to create socket: %d", errno)
            return
        }
        
        // Allow address reuse
        var reuseAddr: Int32 = 1
        setsockopt(ssdpSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(ssdpSocket, SOL_SOCKET, SO_REUSEPORT, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        
        // Bind to any address on a random port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // Let system choose port
        addr.sin_addr.s_addr = INADDR_ANY
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(ssdpSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if bindResult < 0 {
            NSLog("UPnPManager: Failed to bind socket: %d", errno)
            close(ssdpSocket)
            ssdpSocket = -1
            return
        }
        
        // Set non-blocking
        let flags = fcntl(ssdpSocket, F_GETFL, 0)
        fcntl(ssdpSocket, F_SETFL, flags | O_NONBLOCK)
        
        // Create dispatch source for reading
        readSource = DispatchSource.makeReadSource(fileDescriptor: ssdpSocket, queue: .main)
        readSource?.setEventHandler { [weak self] in
            self?.readSSDPResponse()
        }
        readSource?.resume()
        
        NSLog("UPnPManager: SSDP socket ready")
    }
    
    /// Send M-SEARCH requests for UPnP devices
    private func sendMSearchRequests() {
        guard isDiscovering, ssdpSocket >= 0 else { return }
        
        for target in searchTargets {
            sendMSearch(searchTarget: target)
        }
    }
    
    /// Send a single M-SEARCH request
    private func sendMSearch(searchTarget: String) {
        let searchMessage = "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: \(ssdpMulticastAddress):\(ssdpPort)\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 3\r\n" +
            "ST: \(searchTarget)\r\n" +
            "USER-AGENT: AdAmp/1.0 UPnP/1.1\r\n" +
            "\r\n"
        
        guard let data = searchMessage.data(using: .utf8) else { return }
        
        // Setup multicast destination address
        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = ssdpPort.bigEndian
        inet_pton(AF_INET, ssdpMulticastAddress, &destAddr.sin_addr)
        
        // Send the message
        let sent = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: &destAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(ssdpSocket, buffer.baseAddress, data.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        
        if sent < 0 {
            NSLog("UPnPManager: M-SEARCH send failed: %d", errno)
        } else {
            NSLog("UPnPManager: Sent M-SEARCH for %@ (%d bytes)", searchTarget, sent)
        }
    }
    
    /// Read SSDP response from socket
    private func readSSDPResponse() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var srcAddr = sockaddr_in()
        var srcAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let bytesRead = withUnsafeMutablePointer(to: &srcAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                recvfrom(ssdpSocket, &buffer, buffer.count, 0, sockaddrPtr, &srcAddrLen)
            }
        }
        
        guard bytesRead > 0 else { return }
        
        if let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
            // Get source IP for logging
            var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &srcAddr.sin_addr, &ipStr, socklen_t(INET_ADDRSTRLEN))
            let sourceIP = String(cString: ipStr)
            
            NSLog("UPnPManager: Received SSDP response from %@ (%d bytes)", sourceIP, bytesRead)
            handleSSDPResponse(response)
        }
    }
    
    /// Handle an SSDP response
    private func handleSSDPResponse(_ response: String) {
        // Parse LOCATION header to get device description URL
        guard let locationURL = parseHeader(response, header: "LOCATION") else {
            return
        }
        
        // Skip if already fetching this description (thread-safe)
        let shouldFetch = stateQueue.sync { () -> Bool in
            guard !_pendingDescriptions.contains(locationURL) else { return false }
            _pendingDescriptions.insert(locationURL)
            return true
        }
        
        guard shouldFetch else { return }
        
        NSLog("UPnPManager: Found device at %@", locationURL)
        
        // Fetch device description using completion handler
        fetchDeviceDescription(from: locationURL)
    }
    
    /// Parse a header value from HTTP response
    private func parseHeader(_ response: String, header: String) -> String? {
        let lines = response.components(separatedBy: "\r\n")
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let headerName = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                if headerName == header.lowercased() {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    /// Fetch and parse device description XML
    private func fetchDeviceDescription(from urlString: String) {
        guard let url = URL(string: urlString) else {
            stateQueue.async { [weak self] in
                self?._pendingDescriptions.remove(urlString)
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Remove from pending (thread-safe)
            self.stateQueue.async {
                self._pendingDescriptions.remove(urlString)
            }
            
            if let error = error {
                NSLog("UPnPManager: Failed to fetch description: %@", error.localizedDescription)
                return
            }
            
            guard let data = data else { return }
            
            // Parse on main queue
            DispatchQueue.main.async {
                self.parseDeviceDescription(data, baseURL: url)
            }
        }
        task.resume()
    }
    
    /// Parse device description XML
    private func parseDeviceDescription(_ data: Data, baseURL: URL) {
        guard let xmlString = String(data: data, encoding: .utf8) else { return }
        
        // Simple XML parsing
        let friendlyName = extractXMLValue(xmlString, tag: "friendlyName") ?? "Unknown Device"
        let manufacturer = extractXMLValue(xmlString, tag: "manufacturer") ?? ""
        let modelName = extractXMLValue(xmlString, tag: "modelName")
        let udn = extractXMLValue(xmlString, tag: "UDN") ?? UUID().uuidString
        
        // For Sonos, extract the room name
        let roomName = extractXMLValue(xmlString, tag: "roomName")
        
        let manufacturerLower = manufacturer.lowercased()
        
        // Skip excluded manufacturers (NAS, routers, etc.)
        if excludedManufacturers.contains(where: { manufacturerLower.contains($0) }) {
            NSLog("UPnPManager: Skipping non-castable device: %@ (%@)", friendlyName, manufacturer)
            return
        }
        
        // Find AVTransport control URL - REQUIRED for casting
        let controlURL = findAVTransportControlURL(xmlString, baseURL: baseURL)
        
        // Determine device type based on manufacturer
        let isSonos = sonosManufacturers.contains(where: { manufacturerLower.contains($0) })
        
        if isSonos {
            // For Sonos, store zone info and fetch group topology
            guard let host = baseURL.host else { return }
            let port = baseURL.port ?? 1400
            let displayName = roomName ?? friendlyName
            
            let zoneInfo = SonosZoneInfo(
                udn: udn,
                roomName: displayName,
                address: host,
                port: port,
                avTransportURL: controlURL,
                descriptionURL: baseURL
            )
            
            stateQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Store zone info if we don't have it yet
                guard self.sonosZones[udn] == nil else { return }
                self.sonosZones[udn] = zoneInfo
                
                let isFirstZone = self.sonosZones.count == 1
                
                NSLog("UPnPManager: Found Sonos zone: %@ at %@ (isFirst: %d, fetched: %d)", displayName, host, isFirstZone ? 1 : 0, self.sonosGroupsFetched ? 1 : 0)
                
                // Schedule group topology fetch only once after first zone discovered
                // Wait 6 seconds to allow more zones to be discovered
                if isFirstZone && !self.sonosGroupsFetched {
                    self.sonosGroupsFetched = true  // Set flag immediately to prevent duplicates
                    NSLog("UPnPManager: Scheduling group topology fetch in 6 seconds...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                        NSLog("UPnPManager: Group topology fetch timer fired")
                        UPnPManager.shared.fetchSonosGroupTopology()
                    }
                }
            }
            return
        }
        
        // Non-Sonos devices: require AVTransport
        guard let controlURL = controlURL else {
            NSLog("UPnPManager: Skipping device without AVTransport: %@ (%@)", friendlyName, manufacturer)
            return
        }
        
        let deviceType: CastDeviceType
        let displayName: String
        
        if tvManufacturers.contains(where: { manufacturerLower.contains($0) }) {
            deviceType = .dlnaTV
            displayName = friendlyName
        } else {
            // Check model name for clues
            let modelLower = (modelName ?? "").lowercased()
            let nameLower = friendlyName.lowercased()
            if modelLower.contains("tv") || modelLower.contains("television") || 
               nameLower.contains("tv") || nameLower.contains("television") {
                deviceType = .dlnaTV
                displayName = friendlyName
            } else {
                // Skip unknown devices that aren't clearly TVs or speakers
                NSLog("UPnPManager: Skipping unknown device type: %@ (%@)", friendlyName, manufacturer)
                return
            }
        }
        
        // Extract host and port from base URL
        guard let host = baseURL.host else { return }
        let port = baseURL.port ?? 80
        
        let device = CastDevice(
            id: udn,
            name: displayName,
            type: deviceType,
            address: host,
            port: port,
            manufacturer: manufacturer,
            modelName: modelName,
            avTransportControlURL: controlURL,
            descriptionURL: baseURL
        )
        
        // Add non-Sonos device thread-safely
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self._devices.contains(where: { $0.id == device.id }) else { return }
            
            self._devices.append(device)
            
            DispatchQueue.main.async {
                NSLog("UPnPManager: Added %@ device: %@ (%@)", deviceType.displayName, device.name, manufacturer)
                NotificationCenter.default.post(name: CastManager.devicesDidChangeNotification, object: nil)
            }
        }
    }
    
    // MARK: - Sonos Group Topology
    
    /// Fetch zone group topology from any Sonos device
    func fetchSonosGroupTopology() {
        // Get any Sonos zone to query
        let zones = stateQueue.sync { Array(sonosZones.values) }
        guard let zone = zones.first else {
            NSLog("UPnPManager: No Sonos zones found for group topology")
            return
        }
        
        NSLog("UPnPManager: Fetching Sonos group topology from %@", zone.address)
        
        // Build SOAP request for GetZoneGroupState
        let soapAction = "urn:schemas-upnp-org:service:ZoneGroupTopology:1#GetZoneGroupState"
        let soapBody = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
                <s:Body>
                    <u:GetZoneGroupState xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1"></u:GetZoneGroupState>
                </s:Body>
            </s:Envelope>
            """
        
        guard let url = URL(string: "http://\(zone.address):\(zone.port)/ZoneGroupTopology/Control") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(soapAction, forHTTPHeaderField: "SOAPAction")
        request.httpBody = soapBody.data(using: .utf8)
        request.timeoutInterval = 5
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("UPnPManager: Failed to fetch Sonos groups: %@", error.localizedDescription)
                // Fall back to showing individual zones
                self.createSonosDevicesFromZones(groups: nil)
                return
            }
            
            guard let data = data,
                  let responseString = String(data: data, encoding: .utf8) else {
                self.createSonosDevicesFromZones(groups: nil)
                return
            }
            
            // Parse the zone group state
            let groups = self.parseSonosGroupState(responseString)
            self.createSonosDevicesFromZones(groups: groups)
        }
        task.resume()
    }
    
    /// Parse Sonos zone group state XML
    private func parseSonosGroupState(_ xml: String) -> [SonosGroup] {
        var groups: [SonosGroup] = []
        
        // Extract ZoneGroupState content (it's HTML-encoded inside the SOAP response)
        guard let stateMatch = xml.range(of: "<ZoneGroupState>", options: .caseInsensitive),
              let stateEndMatch = xml.range(of: "</ZoneGroupState>", options: .caseInsensitive) else {
            NSLog("UPnPManager: Could not find ZoneGroupState in response")
            return groups
        }
        
        var zoneGroupState = String(xml[stateMatch.upperBound..<stateEndMatch.lowerBound])
        
        // Decode HTML entities
        zoneGroupState = zoneGroupState
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        
        // Parse ZoneGroup elements
        // Pattern: <ZoneGroup Coordinator="RINCON_xxx" ...>...<ZoneGroupMember UUID="RINCON_xxx".../>...</ZoneGroup>
        let groupPattern = "<ZoneGroup[^>]*Coordinator=\"([^\"]+)\"[^>]*>(.*?)</ZoneGroup>"
        guard let groupRegex = try? NSRegularExpression(pattern: groupPattern, options: [.dotMatchesLineSeparators]) else {
            return groups
        }
        
        let matches = groupRegex.matches(in: zoneGroupState, range: NSRange(zoneGroupState.startIndex..., in: zoneGroupState))
        
        for match in matches {
            guard let coordinatorRange = Range(match.range(at: 1), in: zoneGroupState),
                  let membersRange = Range(match.range(at: 2), in: zoneGroupState) else {
                continue
            }
            
            let coordinatorUUID = String(zoneGroupState[coordinatorRange])
            let membersXML = String(zoneGroupState[membersRange])
            
            // Find all member UUIDs
            let memberPattern = "UUID=\"([^\"]+)\""
            guard let memberRegex = try? NSRegularExpression(pattern: memberPattern, options: []) else {
                continue
            }
            
            let memberMatches = memberRegex.matches(in: membersXML, range: NSRange(membersXML.startIndex..., in: membersXML))
            var memberUDNs: [String] = []
            
            for memberMatch in memberMatches {
                if let uuidRange = Range(memberMatch.range(at: 1), in: membersXML) {
                    let uuid = String(membersXML[uuidRange])
                    memberUDNs.append("uuid:\(uuid)")
                }
            }
            
            let fullCoordinatorUDN = "uuid:\(coordinatorUUID)"
            let group = SonosGroup(
                coordinatorUDN: fullCoordinatorUDN,
                memberUDNs: memberUDNs
            )
            groups.append(group)
            
            NSLog("UPnPManager: Found Sonos group - coordinator: %@, members: %d", fullCoordinatorUDN, memberUDNs.count)
        }
        
        return groups
    }
    
    /// Create Sonos device entries from zones and groups
    private func createSonosDevicesFromZones(groups: [SonosGroup]?) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.sonosGroupsFetched = true
            
            // Remove any existing Sonos devices
            self._devices.removeAll(where: { $0.type == .sonos })
            
            NSLog("UPnPManager: Creating Sonos devices from %d groups, %d zones available", groups?.count ?? 0, self.sonosZones.count)
            
            // Debug: print all zone UDNs
            for (udn, zone) in self.sonosZones {
                NSLog("UPnPManager: Zone UDN: %@ -> %@", udn, zone.roomName)
            }
            
            var addedFromGroups = false
            
            if let groups = groups, !groups.isEmpty {
                // Create devices based on groups
                for group in groups {
                    NSLog("UPnPManager: Looking for coordinator: %@", group.coordinatorUDN)
                    
                    // Find the coordinator zone
                    guard let coordinatorZone = self.sonosZones[group.coordinatorUDN] else {
                        NSLog("UPnPManager: Coordinator %@ not found in zones", group.coordinatorUDN)
                        continue
                    }
                    
                    // Only show groups where the coordinator can receive audio
                    guard coordinatorZone.avTransportURL != nil else {
                        continue
                    }
                    
                    // Build display name: "Room Name" or "Room Name +N" for grouped speakers
                    let displayName: String
                    if group.memberCount > 1 {
                        displayName = "\(coordinatorZone.roomName) +\(group.memberCount - 1)"
                    } else {
                        displayName = coordinatorZone.roomName
                    }
                    
                    let device = CastDevice(
                        id: group.coordinatorUDN,
                        name: displayName,
                        type: .sonos,
                        address: coordinatorZone.address,
                        port: coordinatorZone.port,
                        manufacturer: "Sonos",
                        modelName: nil,
                        avTransportControlURL: coordinatorZone.avTransportURL,
                        descriptionURL: coordinatorZone.descriptionURL
                    )
                    
                    self._devices.append(device)
                    addedFromGroups = true
                    NSLog("UPnPManager: Added Sonos group: %@", displayName)
                }
            }
            
            // Fall back to individual zones if no group devices were added
            if !addedFromGroups {
                NSLog("UPnPManager: No groups added, falling back to individual zones")
                for zone in self.sonosZones.values {
                    guard zone.avTransportURL != nil else { continue }
                    
                    let device = CastDevice(
                        id: zone.udn,
                        name: zone.roomName,
                        type: .sonos,
                        address: zone.address,
                        port: zone.port,
                        manufacturer: "Sonos",
                        modelName: nil,
                        avTransportControlURL: zone.avTransportURL,
                        descriptionURL: zone.descriptionURL
                    )
                    
                    // Avoid duplicates by room name
                    if !self._devices.contains(where: { $0.name == device.name && $0.type == .sonos }) {
                        self._devices.append(device)
                        NSLog("UPnPManager: Added Sonos zone: %@", zone.roomName)
                    }
                }
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: CastManager.devicesDidChangeNotification, object: nil)
            }
        }
    }
    
    /// Extract a value from XML (simple regex-based extraction)
    private func extractXMLValue(_ xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range])
    }
    
    /// Find AVTransport control URL from device description
    private func findAVTransportControlURL(_ xml: String, baseURL: URL) -> URL? {
        // Look for AVTransport service
        let pattern = "<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>.*?<controlURL>([^<]*)</controlURL>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        
        let controlPath = String(xml[range])
        
        // Resolve relative URL
        if controlPath.starts(with: "/") {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = controlPath
            return components?.url
        } else {
            return URL(string: controlPath, relativeTo: baseURL)
        }
    }
    
    /// Remove all discovered devices
    func clearDevices() {
        stateQueue.async { [weak self] in
            self?._devices.removeAll()
            self?._pendingDescriptions.removeAll()
            self?.sonosZones.removeAll()
            self?.sonosGroupsFetched = false
        }
    }
    
    // MARK: - Playback Control
    
    /// Connect to a UPnP device
    func connect(to device: CastDevice) async throws {
        guard device.type == .sonos || device.type == .dlnaTV else {
            throw CastError.unsupportedDevice
        }
        
        guard device.avTransportControlURL != nil else {
            throw CastError.connectionFailed("No AVTransport control URL")
        }
        
        NSLog("UPnPManager: Connecting to %@", device.name)
        
        activeSession = CastSession(device: device)
        activeSession?.state = .connected
        
        NotificationCenter.default.post(name: CastManager.sessionDidChangeNotification, object: nil)
    }
    
    /// Disconnect from current device
    func disconnect() {
        guard let session = activeSession else { return }
        
        NSLog("UPnPManager: Disconnecting from %@", session.device.name)
        
        // Stop playback first
        Task {
            try? await stop()
        }
        
        activeSession = nil
        NotificationCenter.default.post(name: CastManager.sessionDidChangeNotification, object: nil)
    }
    
    /// Cast media to the connected device
    func cast(url: URL, metadata: CastMetadata) async throws {
        guard let session = activeSession,
              let controlURL = session.device.avTransportControlURL else {
            throw CastError.sessionNotActive
        }
        
        NSLog("UPnPManager: Casting %@ to %@", url.absoluteString, session.device.name)
        
        // Generate DIDL-Lite metadata
        let didlMetadata = metadata.toDIDLLite(streamURL: url)
        
        // Send SetAVTransportURI
        try await sendSOAPAction(
            controlURL: controlURL,
            action: "SetAVTransportURI",
            arguments: [
                ("InstanceID", "0"),
                ("CurrentURI", url.absoluteString),
                ("CurrentURIMetaData", didlMetadata)
            ]
        )
        
        // Send Play
        try await sendSOAPAction(
            controlURL: controlURL,
            action: "Play",
            arguments: [
                ("InstanceID", "0"),
                ("Speed", "1")
            ]
        )
        
        session.state = .casting
        session.currentURL = url
        session.metadata = metadata
        
        NotificationCenter.default.post(name: CastManager.sessionDidChangeNotification, object: nil)
        NotificationCenter.default.post(name: CastManager.playbackStateDidChangeNotification, object: nil)
    }
    
    /// Stop playback
    func stop() async throws {
        guard let session = activeSession,
              let controlURL = session.device.avTransportControlURL else {
            return
        }
        
        NSLog("UPnPManager: Stopping playback on %@", session.device.name)
        
        try await sendSOAPAction(
            controlURL: controlURL,
            action: "Stop",
            arguments: [("InstanceID", "0")]
        )
        
        session.state = .connected
        session.currentURL = nil
        session.metadata = nil
        
        NotificationCenter.default.post(name: CastManager.playbackStateDidChangeNotification, object: nil)
    }
    
    /// Pause playback
    func pause() async throws {
        guard let session = activeSession,
              let controlURL = session.device.avTransportControlURL else {
            throw CastError.sessionNotActive
        }
        
        NSLog("UPnPManager: Pausing playback on %@", session.device.name)
        
        try await sendSOAPAction(
            controlURL: controlURL,
            action: "Pause",
            arguments: [("InstanceID", "0")]
        )
    }
    
    /// Resume playback
    func resume() async throws {
        guard let session = activeSession,
              let controlURL = session.device.avTransportControlURL else {
            throw CastError.sessionNotActive
        }
        
        NSLog("UPnPManager: Resuming playback on %@", session.device.name)
        
        try await sendSOAPAction(
            controlURL: controlURL,
            action: "Play",
            arguments: [
                ("InstanceID", "0"),
                ("Speed", "1")
            ]
        )
    }
    
    /// Seek to position
    func seek(to time: TimeInterval) async throws {
        guard let session = activeSession,
              let controlURL = session.device.avTransportControlURL else {
            throw CastError.sessionNotActive
        }
        
        let seekTarget = formatSeekTime(time)
        NSLog("UPnPManager: Seeking to %@ on %@", seekTarget, session.device.name)
        
        try await sendSOAPAction(
            controlURL: controlURL,
            action: "Seek",
            arguments: [
                ("InstanceID", "0"),
                ("Unit", "REL_TIME"),
                ("Target", seekTarget)
            ]
        )
    }
    
    /// Get current position information
    func getPositionInfo() async throws -> (position: TimeInterval, duration: TimeInterval)? {
        guard let session = activeSession,
              let controlURL = session.device.avTransportControlURL else {
            return nil
        }
        
        let response = try await sendSOAPAction(
            controlURL: controlURL,
            action: "GetPositionInfo",
            arguments: [("InstanceID", "0")]
        )
        
        let relTime = extractXMLValue(response, tag: "RelTime") ?? "00:00:00"
        let trackDuration = extractXMLValue(response, tag: "TrackDuration") ?? "00:00:00"
        
        return (parseSeekTime(relTime), parseSeekTime(trackDuration))
    }
    
    // MARK: - Volume Control
    
    /// Set volume on the connected device (0-100)
    func setVolume(_ volume: Int) async throws {
        guard let session = activeSession else {
            throw CastError.sessionNotActive
        }
        
        let clampedVolume = max(0, min(100, volume))
        let controlURL = getRenderingControlURL(for: session.device)
        
        NSLog("UPnPManager: Setting volume to %d on %@", clampedVolume, session.device.name)
        
        try await sendRenderingControlAction(
            controlURL: controlURL,
            action: "SetVolume",
            arguments: [
                ("InstanceID", "0"),
                ("Channel", "Master"),
                ("DesiredVolume", "\(clampedVolume)")
            ]
        )
    }
    
    /// Get current volume (0-100)
    func getVolume() async throws -> Int {
        guard let session = activeSession else {
            return 0
        }
        
        let controlURL = getRenderingControlURL(for: session.device)
        
        let response = try await sendRenderingControlAction(
            controlURL: controlURL,
            action: "GetVolume",
            arguments: [
                ("InstanceID", "0"),
                ("Channel", "Master")
            ]
        )
        
        if let volumeStr = extractXMLValue(response, tag: "CurrentVolume"),
           let volume = Int(volumeStr) {
            return volume
        }
        
        return 0
    }
    
    /// Set mute state
    func setMute(_ muted: Bool) async throws {
        guard let session = activeSession else {
            throw CastError.sessionNotActive
        }
        
        let controlURL = getRenderingControlURL(for: session.device)
        
        NSLog("UPnPManager: Setting mute to %@ on %@", muted ? "ON" : "OFF", session.device.name)
        
        try await sendRenderingControlAction(
            controlURL: controlURL,
            action: "SetMute",
            arguments: [
                ("InstanceID", "0"),
                ("Channel", "Master"),
                ("DesiredMute", muted ? "1" : "0")
            ]
        )
    }
    
    /// Get RenderingControl URL for a device
    private func getRenderingControlURL(for device: CastDevice) -> URL {
        // For Sonos, the RenderingControl service is at a specific path
        var components = URLComponents()
        components.scheme = "http"
        components.host = device.address
        components.port = device.port
        components.path = "/MediaRenderer/RenderingControl/Control"
        return components.url!
    }
    
    // MARK: - SOAP Helpers
    
    /// Send a RenderingControl SOAP action
    @discardableResult
    private func sendRenderingControlAction(controlURL: URL, action: String, arguments: [(String, String)]) async throws -> String {
        let serviceType = "urn:schemas-upnp-org:service:RenderingControl:1"
        
        // Build SOAP body
        var argsXML = ""
        for (name, value) in arguments {
            argsXML += "<\(name)>\(value.xmlEscapedForSOAP)</\(name)>"
        }
        
        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:\(action) xmlns:u="\(serviceType)">
        \(argsXML)
        </u:\(action)>
        </s:Body>
        </s:Envelope>
        """
        
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = soapBody.data(using: .utf8)
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CastError.networkError(NSError(domain: "UPnP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }
        
        if httpResponse.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            NSLog("UPnPManager: RenderingControl SOAP error %d: %@", httpResponse.statusCode, errorBody)
            throw CastError.playbackFailed("SOAP error \(httpResponse.statusCode)")
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Send a SOAP action to the device
    @discardableResult
    private func sendSOAPAction(controlURL: URL, action: String, arguments: [(String, String)]) async throws -> String {
        let serviceType = "urn:schemas-upnp-org:service:AVTransport:1"
        
        // Build SOAP body
        var argsXML = ""
        for (name, value) in arguments {
            argsXML += "<\(name)>\(value.xmlEscapedForSOAP)</\(name)>"
        }
        
        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:\(action) xmlns:u="\(serviceType)">
        \(argsXML)
        </u:\(action)>
        </s:Body>
        </s:Envelope>
        """
        
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = soapBody.data(using: .utf8)
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CastError.networkError(NSError(domain: "UPnP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }
        
        if httpResponse.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            NSLog("UPnPManager: SOAP error %d: %@", httpResponse.statusCode, errorBody)
            throw CastError.playbackFailed("SOAP error \(httpResponse.statusCode)")
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Format time as HH:MM:SS for SOAP
    private func formatSeekTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
    
    /// Parse HH:MM:SS time format
    private func parseSeekTime(_ timeString: String) -> TimeInterval {
        let parts = timeString.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return 0
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}

// MARK: - String Extension for SOAP

private extension String {
    var xmlEscapedForSOAP: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
