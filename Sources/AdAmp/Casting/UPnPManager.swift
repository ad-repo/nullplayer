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
    
    /// mDNS browser for Sonos discovery (fallback/supplement to SSDP)
    private var sonosBrowser: NWBrowser?
    
    /// Pending device descriptions being fetched - access via stateQueue
    private var _pendingDescriptions: Set<String> = []
    
    /// Active URL tasks for device description fetches (can be cancelled)
    private var activeTasks: [String: URLSessionTask] = [:]
    
    /// Sonos zone information for group detection
    private var sonosZones: [String: SonosZoneInfo] = [:]  // UDN -> ZoneInfo
    private var sonosGroupsFetched = false
    
    /// Work item for Sonos group topology fetch (can be cancelled)
    private var sonosTopologyWorkItem: DispatchWorkItem?
    
    // MARK: - Sonos Zone Types
    
    /// Information about a Sonos zone (speaker) - internal use
    private struct SonosZoneInfo {
        let udn: String
        let roomName: String
        let address: String
        let port: Int
        let avTransportURL: URL?
        let descriptionURL: URL
    }
    
    /// Sonos group with coordinator and members - internal use
    private struct SonosGroup {
        let coordinatorUDN: String
        let memberUDNs: [String]
        
        var memberCount: Int { memberUDNs.count }
    }
    
    /// Last fetched group topology (for UI access)
    private var lastFetchedGroups: [SonosGroup] = []
    
    /// Zones that are bonded (stereo pairs, surrounds) and can't be grouped independently
    /// These have Invisible="1" in the topology
    private var bondedZoneUDNs: Set<String> = []
    
    /// Satellite speakers in surround systems (from HTSatChanMapSet) - should not be room representatives
    private var satelliteZoneUDNs: Set<String> = []
    
    /// Main units that control surround systems (have HTSatChanMapSet) - prefer these as room representatives
    private var mainUnitZoneUDNs: Set<String> = []
    
    // MARK: - Public Sonos Summary Types (for UI)
    
    /// Public summary of a Sonos zone for grouping UI
    struct SonosZoneSummary: Identifiable {
        let id: String      // UDN
        let name: String    // Room name
        let address: String
        let port: Int
    }
    
    /// Public summary of a Sonos group for grouping UI
    struct SonosGroupSummary: Identifiable {
        let id: String              // Coordinator UDN
        let coordinatorName: String
        let memberUDNs: [String]
        var memberCount: Int { memberUDNs.count }
    }
    
    /// All individual Sonos zones (for grouping UI)
    /// Filters out devices that can't be grouped independently:
    /// - Sub, Boost, Bridge devices
    /// - Bonded speakers (stereo pairs, surround satellites with Invisible="1")
    var allSonosZones: [SonosZoneSummary] {
        stateQueue.sync {
            sonosZones.values
                .filter { zone in
                    // Filter out devices that can't be grouped independently
                    let nameLower = zone.roomName.lowercased()
                    let isSubOrBridge = nameLower == "sub" || 
                                        nameLower.hasSuffix(" sub") ||
                                        nameLower == "boost" ||
                                        nameLower == "bridge"
                    
                    // Filter out bonded speakers (stereo pairs, surround satellites)
                    let isBonded = bondedZoneUDNs.contains(zone.udn)
                    
                    if isBonded {
                        NSLog("UPnPManager: Filtering out bonded zone '%@' from grouping UI", zone.roomName)
                    }
                    
                    return !isSubOrBridge && !isBonded
                }
                .map { zone in
                    SonosZoneSummary(
                        id: zone.udn,
                        name: zone.roomName,
                        address: zone.address,
                        port: zone.port
                    )
                }
                .sorted { $0.name < $1.name }
        }
    }
    
    /// Current Sonos group topology (for grouping UI)
    var sonosGroups: [SonosGroupSummary] {
        stateQueue.sync {
            lastFetchedGroups.compactMap { group in
                guard let coordinatorZone = sonosZones[group.coordinatorUDN] else { return nil }
                return SonosGroupSummary(
                    id: group.coordinatorUDN,
                    coordinatorName: coordinatorZone.roomName,
                    memberUDNs: group.memberUDNs
                )
            }.sorted { $0.coordinatorName < $1.coordinatorName }
        }
    }
    
    /// Get zone name by UDN (for UI display)
    func zoneName(for udn: String) -> String? {
        stateQueue.sync {
            sonosZones[udn]?.roomName
        }
    }
    
    /// Summary of a room for the simplified grouping UI
    struct SonosRoomSummary: Identifiable {
        let id: String              // Representative zone UDN (coordinator of this room's speakers)
        let name: String            // Room name
        let isGroupCoordinator: Bool // Is this room the coordinator of a multi-room group?
        let isInGroup: Bool         // Is this room part of another room's group?
        let groupCoordinatorUDN: String? // If in a group, the coordinator's UDN
        let groupCoordinatorName: String? // If in a group, the coordinator's room name
    }
    
    /// Get unique rooms for simplified grouping UI
    /// Returns one entry per room name (not per speaker), with group membership info
    var sonosRooms: [SonosRoomSummary] {
        stateQueue.sync {
            // Build map of zone UDN -> its group's coordinator UDN
            var zoneToGroupCoordinator: [String: String] = [:]
            var groupCoordinatorUDNs: Set<String> = []
            var multiRoomGroups: Set<String> = []  // Coordinators that have members from different rooms
            
            for group in lastFetchedGroups {
                groupCoordinatorUDNs.insert(group.coordinatorUDN)
                
                // Get unique room names in this group, but EXCLUDE satellites and bonded speakers
                // (they can have different names like "Sub" but shouldn't count as separate rooms)
                var roomNamesInGroup: Set<String> = []
                for memberUDN in group.memberUDNs {
                    zoneToGroupCoordinator[memberUDN] = group.coordinatorUDN
                    
                    // Skip satellites (surround speakers) and bonded speakers (stereo pair secondaries)
                    if satelliteZoneUDNs.contains(memberUDN) || bondedZoneUDNs.contains(memberUDN) {
                        continue
                    }
                    
                    if let roomName = sonosZones[memberUDN]?.roomName {
                        roomNamesInGroup.insert(roomName)
                    }
                }
                
                // If more than one unique room name (from non-satellite speakers), it's a multi-room group
                if roomNamesInGroup.count > 1 {
                    multiRoomGroups.insert(group.coordinatorUDN)
                }
            }
            
            // Get unique room names (dedup by name, pick the best representative for each room)
            // Priority: main unit (soundbar) > group coordinator > first found
            var roomsByName: [String: SonosZoneInfo] = [:]
            for zone in sonosZones.values {
                // Skip bonded (Invisible) zones - stereo pair secondary speakers
                if bondedZoneUDNs.contains(zone.udn) {
                    continue
                }
                
                // Skip satellite speakers (surround rears, sub) - they can't be controlled independently
                if satelliteZoneUDNs.contains(zone.udn) {
                    continue
                }
                
                // Skip Sub, Boost, Bridge by name
                let nameLower = zone.roomName.lowercased()
                if nameLower == "sub" || nameLower.hasSuffix(" sub") ||
                   nameLower == "boost" || nameLower == "bridge" {
                    continue
                }
                
                // Pick the best representative for each room name
                if roomsByName[zone.roomName] == nil {
                    roomsByName[zone.roomName] = zone
                } else {
                    // Prefer main units (soundbars with HTSatChanMapSet) - they control the whole surround
                    if mainUnitZoneUDNs.contains(zone.udn) {
                        NSLog("UPnPManager: Preferring main unit %@ for room '%@'", zone.udn, zone.roomName)
                        roomsByName[zone.roomName] = zone
                    }
                    // Otherwise prefer group coordinators
                    else if groupCoordinatorUDNs.contains(zone.udn) && !mainUnitZoneUDNs.contains(roomsByName[zone.roomName]!.udn) {
                        roomsByName[zone.roomName] = zone
                    }
                }
            }
            
            // Build room summaries
            var rooms: [SonosRoomSummary] = []
            for (roomName, zone) in roomsByName {
                let groupCoordUDN = zoneToGroupCoordinator[zone.udn]
                let isGroupCoordinator = groupCoordinatorUDNs.contains(zone.udn) && multiRoomGroups.contains(zone.udn)
                let isInOtherGroup = groupCoordUDN != nil && groupCoordUDN != zone.udn && multiRoomGroups.contains(groupCoordUDN!)
                
                var coordName: String? = nil
                if let coordUDN = groupCoordUDN, isInOtherGroup {
                    coordName = sonosZones[coordUDN]?.roomName
                }
                
                rooms.append(SonosRoomSummary(
                    id: zone.udn,
                    name: roomName,
                    isGroupCoordinator: isGroupCoordinator,
                    isInGroup: isInOtherGroup,
                    groupCoordinatorUDN: isInOtherGroup ? groupCoordUDN : nil,
                    groupCoordinatorName: coordName
                ))
            }
            
            return rooms.sorted { $0.name < $1.name }
        }
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
        guard !isDiscovering else {
            NSLog("UPnPManager: Already discovering, skipping start")
            return
        }
        
        NSLog("UPnPManager: Starting discovery (SSDP + mDNS)...")
        isDiscovering = true
        
        // Start SSDP discovery for DLNA devices and Sonos
        setupSocket()
        
        if ssdpSocket >= 0 {
            // Send M-SEARCH requests with delays for thorough discovery
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.sendMSearchRequests()
            }
            
            // Repeat search periodically to catch slow-responding devices
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard self?.isDiscovering == true else { return }
                self?.sendMSearchRequests()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard self?.isDiscovering == true else { return }
                self?.sendMSearchRequests()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                guard self?.isDiscovering == true else { return }
                self?.sendMSearchRequests()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard self?.isDiscovering == true else { return }
                self?.sendMSearchRequests()
            }
        } else {
            NSLog("UPnPManager: SSDP socket setup failed, relying on mDNS only")
        }
        
        // Start mDNS discovery for Sonos (more reliable fallback)
        startSonosMDNSDiscovery()
    }
    
    /// Send an immediate M-SEARCH boost (for refresh operations)
    /// This can be called externally to trigger additional discovery
    func sendDiscoveryBoost() {
        guard isDiscovering else {
            NSLog("UPnPManager: Cannot send discovery boost - not discovering")
            return
        }
        
        if ssdpSocket >= 0 {
            NSLog("UPnPManager: Sending discovery boost M-SEARCH")
            sendMSearchRequests()
        } else {
            NSLog("UPnPManager: SSDP socket invalid, mDNS discovery still active")
        }
    }
    
    // MARK: - Sonos mDNS Discovery
    
    /// Start mDNS/Bonjour discovery for Sonos devices
    /// This is a fallback/supplement to SSDP discovery
    private func startSonosMDNSDiscovery() {
        NSLog("UPnPManager: Starting Sonos mDNS discovery (_sonos._tcp)...")
        
        // Browse for Sonos devices via mDNS
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_sonos._tcp", domain: "local.")
        let parameters = NWParameters()
        
        sonosBrowser = NWBrowser(for: descriptor, using: parameters)
        
        sonosBrowser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            
            for change in changes {
                switch change {
                case .added(let result):
                    self.handleSonosMDNSResult(result)
                case .removed(let result):
                    NSLog("UPnPManager: Sonos mDNS device removed: %@", String(describing: result.endpoint))
                default:
                    break
                }
            }
        }
        
        sonosBrowser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("UPnPManager: Sonos mDNS browser ready")
            case .failed(let error):
                NSLog("UPnPManager: Sonos mDNS browser failed: %@", error.localizedDescription)
            case .cancelled:
                NSLog("UPnPManager: Sonos mDNS browser cancelled")
            default:
                break
            }
        }
        
        sonosBrowser?.start(queue: .main)
    }
    
    /// Handle a Sonos device discovered via mDNS
    private func handleSonosMDNSResult(_ result: NWBrowser.Result) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }
        
        NSLog("UPnPManager: Sonos mDNS found: %@", name)
        
        // Resolve the service to get IP address
        let parameters = NWParameters.tcp
        let connection = NWConnection(to: result.endpoint, using: parameters)
        var resolved = false
        
        connection.stateUpdateHandler = { [weak self] state in
            guard !resolved else { return }
            
            switch state {
            case .ready:
                resolved = true
                if let path = connection.currentPath,
                   let remoteEndpoint = path.remoteEndpoint {
                    self?.processSonosMDNSEndpoint(remoteEndpoint, name: name)
                }
                connection.cancel()
                
            case .failed, .cancelled:
                resolved = true
                connection.cancel()
                
            default:
                break
            }
        }
        
        connection.start(queue: .main)
        
        // Timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard !resolved else { return }
            resolved = true
            connection.cancel()
        }
    }
    
    /// Process a resolved Sonos mDNS endpoint
    private func processSonosMDNSEndpoint(_ endpoint: NWEndpoint, name: String) {
        var address: String?
        
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let ipv4):
                address = "\(ipv4)"
            case .ipv6(let ipv6):
                // Skip IPv6 for now, Sonos works fine with IPv4
                NSLog("UPnPManager: Skipping IPv6 address for Sonos: %@", "\(ipv6)")
                return
            case .name(let hostname, _):
                address = hostname
            @unknown default:
                break
            }
        default:
            break
        }
        
        guard let deviceAddress = address else { return }
        
        // Sonos always uses port 1400 for UPnP
        let descriptionURL = "http://\(deviceAddress):1400/xml/device_description.xml"
        
        NSLog("UPnPManager: Sonos mDNS resolved: %@ -> %@", name, descriptionURL)
        
        // Check if we've already fetched this description (via SSDP or mDNS)
        let shouldFetch = stateQueue.sync { () -> Bool in
            guard !_pendingDescriptions.contains(descriptionURL) else { return false }
            _pendingDescriptions.insert(descriptionURL)
            return true
        }
        
        guard shouldFetch else {
            NSLog("UPnPManager: Already fetched description for %@", deviceAddress)
            return
        }
        
        // Fetch device description (same as SSDP flow)
        fetchDeviceDescription(from: descriptionURL)
    }
    
    /// Stop discovering devices
    func stopDiscovery() {
        NSLog("UPnPManager: Stopping discovery")
        isDiscovering = false
        
        // Stop SSDP discovery
        if let source = readSource {
            source.cancel()
            readSource = nil
        }
        
        if ssdpSocket >= 0 {
            close(ssdpSocket)
            ssdpSocket = -1
            NSLog("UPnPManager: SSDP socket closed")
        }
        
        // Stop mDNS discovery
        if sonosBrowser != nil {
            sonosBrowser?.cancel()
            sonosBrowser = nil
            NSLog("UPnPManager: Sonos mDNS browser stopped")
        }
    }
    
    /// Setup UDP socket for SSDP
    private func setupSocket() {
        // Ensure any previous socket is cleaned up
        if ssdpSocket >= 0 {
            NSLog("UPnPManager: Warning - previous socket still exists, closing it")
            close(ssdpSocket)
            ssdpSocket = -1
        }
        
        // Create UDP socket
        ssdpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard ssdpSocket >= 0 else {
            NSLog("UPnPManager: Failed to create socket: %d", errno)
            return
        }
        
        NSLog("UPnPManager: Created socket fd=%d", ssdpSocket)
        
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
        _ = fcntl(ssdpSocket, F_SETFL, flags | O_NONBLOCK)
        
        // Create dispatch source for reading
        readSource = DispatchSource.makeReadSource(fileDescriptor: ssdpSocket, queue: .main)
        readSource?.setEventHandler { [weak self] in
            self?.readSSDPResponse()
        }
        readSource?.resume()
        
        NSLog("UPnPManager: SSDP socket ready (fd=%d)", ssdpSocket)
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
            
            // Remove from pending and active tasks (thread-safe)
            self.stateQueue.async {
                self._pendingDescriptions.remove(urlString)
                self.activeTasks.removeValue(forKey: urlString)
            }
            
            if let error = error {
                // Don't log cancellation errors (expected during refresh)
                if (error as NSError).code != NSURLErrorCancelled {
                    NSLog("UPnPManager: Failed to fetch description: %@", error.localizedDescription)
                }
                return
            }
            
            guard let data = data else { return }
            
            // Parse on main queue
            DispatchQueue.main.async {
                self.parseDeviceDescription(data, baseURL: url)
            }
        }
        
        // Track the task for potential cancellation
        stateQueue.async { [weak self] in
            self?.activeTasks[urlString] = task
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
                    NSLog("UPnPManager: Scheduling group topology fetch in 3 seconds...")
                    
                    // Cancel any existing work item
                    UPnPManager.shared.sonosTopologyWorkItem?.cancel()
                    
                    // Create new cancellable work item
                    let workItem = DispatchWorkItem {
                        NSLog("UPnPManager: Group topology fetch timer fired")
                        UPnPManager.shared.fetchSonosGroupTopology()
                    }
                    UPnPManager.shared.sonosTopologyWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
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
        var newBondedZones: Set<String> = []
        
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
        
        // First pass: find all bonded/invisible zones and surround satellites
        // We need to match both ZoneGroupMember and Satellite tags
        // Tags can be self-closing (<Tag .../>) or have content (<Tag ...>...</Tag>)
        var newSatellites: Set<String> = []
        var newMainUnits: Set<String> = []
        
        // Match opening tags for ZoneGroupMember and Satellite (capture the whole tag including attributes)
        let tagPattern = "<(ZoneGroupMember|Satellite)[^>]*UUID=\"([^\"]+)\"[^>]*"
        if let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            let allMatches = tagRegex.matches(in: zoneGroupState, range: NSRange(zoneGroupState.startIndex..., in: zoneGroupState))
            for match in allMatches {
                if let matchRange = Range(match.range, in: zoneGroupState),
                   let uuidRange = Range(match.range(at: 2), in: zoneGroupState) {
                    let tagXML = String(zoneGroupState[matchRange])
                    let uuid = String(zoneGroupState[uuidRange])
                    let udn = "uuid:\(uuid)"
                    
                    // Check for Invisible="1" (stereo pair secondary or surround satellite)
                    if tagXML.contains("Invisible=\"1\"") {
                        newBondedZones.insert(udn)
                        NSLog("UPnPManager: Zone %@ is bonded (Invisible=1) - excluding from grouping", uuid)
                    }
                    
                    // Check for HTSatChanMapSet (surround system - main unit or satellite)
                    // The main unit has LF,RF channels, satellites have SW, LR, or RR
                    if let htSatRange = tagXML.range(of: "HTSatChanMapSet=\"") {
                        let afterQuote = tagXML[htSatRange.upperBound...]
                        if let endQuote = afterQuote.firstIndex(of: "\"") {
                            let htSatValue = String(afterQuote[..<endQuote])
                            
                            // Find which channels this zone has
                            let entries = htSatValue.components(separatedBy: ";")
                            for entry in entries {
                                let parts = entry.components(separatedBy: ":")
                                if parts.count >= 2 && parts[0] == uuid {
                                    let channels = parts[1]
                                    if channels.contains("LF") || channels.contains("RF") {
                                        // This is the main unit (soundbar)
                                        newMainUnits.insert(udn)
                                        NSLog("UPnPManager: Zone %@ is surround main unit (%@)", uuid, channels)
                                    } else {
                                        // This is a satellite (sub, rear speakers)
                                        newSatellites.insert(udn)
                                        NSLog("UPnPManager: Zone %@ is surround satellite (%@)", uuid, channels)
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Store bonded zones and satellites
        stateQueue.async { [weak self] in
            self?.bondedZoneUDNs = newBondedZones
            self?.satelliteZoneUDNs = newSatellites
            self?.mainUnitZoneUDNs = newMainUnits
        }
        
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
            
            // Find all member UUIDs (excluding invisible/bonded ones from count)
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
            
            // Store groups for UI access
            self.lastFetchedGroups = groups ?? []
            
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
                    
                    // Just use the room name
                    let displayName = coordinatorZone.roomName
                    
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
        NSLog("UPnPManager: clearDevices called")
        
        // Cancel any pending Sonos topology fetch (on main queue where it was scheduled)
        sonosTopologyWorkItem?.cancel()
        sonosTopologyWorkItem = nil
        
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel all in-flight description fetches
            let taskCount = self.activeTasks.count
            for (_, task) in self.activeTasks {
                task.cancel()
            }
            self.activeTasks.removeAll()
            
            // Clear all state atomically
            let deviceCount = self._devices.count
            let zoneCount = self.sonosZones.count
            self._devices.removeAll()
            self._pendingDescriptions.removeAll()
            self.sonosZones.removeAll()
            self.lastFetchedGroups.removeAll()
            self.bondedZoneUDNs.removeAll()
            self.satelliteZoneUDNs.removeAll()
            self.mainUnitZoneUDNs.removeAll()
            self.sonosGroupsFetched = false
            
            NSLog("UPnPManager: Cleared %d devices, %d zones, cancelled %d tasks", deviceCount, zoneCount, taskCount)
        }
    }
    
    /// Reset discovery state without clearing visible devices
    /// Used during refresh to allow re-discovery while keeping existing devices visible
    func resetDiscoveryState() {
        NSLog("UPnPManager: Resetting discovery state (keeping devices and zone info)")
        
        // Cancel any pending Sonos topology fetch
        sonosTopologyWorkItem?.cancel()
        sonosTopologyWorkItem = nil
        
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel in-flight description fetches
            for (_, task) in self.activeTasks {
                task.cancel()
            }
            self.activeTasks.removeAll()
            
            // Clear pending descriptions so devices can be re-fetched
            self._pendingDescriptions.removeAll()
            
            // IMPORTANT: Keep sonosZones, lastFetchedGroups, and bonded/satellite info intact
            // so that sonosRooms keeps returning valid data during refresh.
            // These will be updated when new zone info comes in.
            // Only reset the "fetched" flag so topology gets re-fetched.
            self.sonosGroupsFetched = false
            
            NSLog("UPnPManager: Reset discovery state, kept %d devices and %d zones visible", 
                  self._devices.count, self.sonosZones.count)
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
    
    // MARK: - Sonos Grouping
    
    /// Join a Sonos zone to a group (make it follow the coordinator)
    /// Uses AVTransport SetAVTransportURI with x-rincon:{coordinator_uid} URI
    /// - Parameters:
    ///   - zoneUDN: The UDN of the zone to join (e.g., "uuid:RINCON_xxx")
    ///   - coordinatorUDN: The UDN of the group coordinator to join
    func joinSonosZone(_ zoneUDN: String, toCoordinator coordinatorUDN: String) async throws {
        // Get zone info for the joining zone
        let zoneInfo = stateQueue.sync { sonosZones[zoneUDN] }
        guard let zone = zoneInfo else {
            NSLog("UPnPManager: Zone not found: %@", zoneUDN)
            throw CastError.playbackFailed("Zone not found: \(zoneUDN)")
        }
        
        // Build the AVTransport control URL for the joining zone
        // If the zone doesn't have a dedicated AVTransport URL, construct it
        let controlURL: URL
        if let avURL = zone.avTransportURL {
            controlURL = avURL
        } else {
            // Construct standard Sonos AVTransport URL
            guard let url = URL(string: "http://\(zone.address):\(zone.port)/MediaRenderer/AVTransport/Control") else {
                throw CastError.playbackFailed("Cannot construct AVTransport URL")
            }
            controlURL = url
        }
        
        // Extract the RINCON ID from the coordinator UDN (remove "uuid:" prefix)
        let coordinatorRincon = coordinatorUDN.replacingOccurrences(of: "uuid:", with: "")
        let rinconURI = "x-rincon:\(coordinatorRincon)"
        
        NSLog("UPnPManager: Joining zone '%@' (%@) to coordinator '%@'", zone.roomName, zone.address, coordinatorRincon)
        NSLog("UPnPManager: Using control URL: %@", controlURL.absoluteString)
        NSLog("UPnPManager: Using x-rincon URI: %@", rinconURI)
        
        // Send SetAVTransportURI with x-rincon: URI to join the group
        try await sendSOAPAction(
            controlURL: controlURL,
            action: "SetAVTransportURI",
            arguments: [
                ("InstanceID", "0"),
                ("CurrentURI", rinconURI),
                ("CurrentURIMetaData", "")
            ]
        )
        
        NSLog("UPnPManager: Zone '%@' joined group", zone.roomName)
        
        // Refresh group topology after a short delay to let Sonos update
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        await refreshSonosGroupTopology()
    }
    
    /// Make a Sonos zone standalone (leave its current group)
    /// Uses AVTransport BecomeCoordinatorOfStandaloneGroup action
    /// - Parameter zoneUDN: The UDN of the zone to make standalone
    func unjoinSonosZone(_ zoneUDN: String) async throws {
        // Get zone info
        let zoneInfo = stateQueue.sync { sonosZones[zoneUDN] }
        guard let zone = zoneInfo else {
            NSLog("UPnPManager: Zone not found: %@", zoneUDN)
            throw CastError.playbackFailed("Zone not found: \(zoneUDN)")
        }
        
        // Build the AVTransport control URL
        // If the zone doesn't have a dedicated AVTransport URL, construct it
        let controlURL: URL
        if let avURL = zone.avTransportURL {
            controlURL = avURL
        } else {
            // Construct standard Sonos AVTransport URL
            guard let url = URL(string: "http://\(zone.address):\(zone.port)/MediaRenderer/AVTransport/Control") else {
                throw CastError.playbackFailed("Cannot construct AVTransport URL")
            }
            controlURL = url
        }
        
        NSLog("UPnPManager: Making zone '%@' (%@) standalone", zone.roomName, zone.address)
        NSLog("UPnPManager: Using control URL: %@", controlURL.absoluteString)
        
        // Send BecomeCoordinatorOfStandaloneGroup to leave the group
        try await sendSOAPAction(
            controlURL: controlURL,
            action: "BecomeCoordinatorOfStandaloneGroup",
            arguments: [
                ("InstanceID", "0")
            ]
        )
        
        NSLog("UPnPManager: Zone '%@' is now standalone", zone.roomName)
        
        // Refresh group topology after a short delay
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        await refreshSonosGroupTopology()
    }
    
    /// Refresh Sonos group topology and update devices
    func refreshSonosGroupTopology() async {
        // Run on main queue to use existing fetchSonosGroupTopology
        await MainActor.run {
            fetchSonosGroupTopology()
        }
    }
    
    // MARK: - SOAP Helpers
    
    /// Maximum number of retries for transient SOAP errors
    private let maxRetries = 2
    
    /// Base delay between retries (will be multiplied by attempt number for backoff)
    private let retryBaseDelay: UInt64 = 500_000_000  // 0.5 seconds in nanoseconds
    
    /// HTTP status codes that are considered transient and worth retrying
    private func isTransientError(_ statusCode: Int) -> Bool {
        // 500 Internal Server Error - device temporarily busy
        // 502 Bad Gateway - proxy/gateway issue
        // 503 Service Unavailable - device overloaded
        // 504 Gateway Timeout - timeout from device
        return [500, 502, 503, 504].contains(statusCode)
    }
    
    /// Send a RenderingControl SOAP action with retry logic for transient errors
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
        
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            if attempt > 0 {
                // Exponential backoff: 0.5s, 1s, 2s
                let delay = retryBaseDelay * UInt64(1 << (attempt - 1))
                NSLog("UPnPManager: Retrying RenderingControl %@ (attempt %d/%d) after %.1fs", action, attempt + 1, maxRetries + 1, Double(delay) / 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
            
            var request = URLRequest(url: controlURL)
            request.httpMethod = "POST"
            request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
            request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
            request.httpBody = soapBody.data(using: .utf8)
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CastError.networkError(NSError(domain: "UPnP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                }
                
                if httpResponse.statusCode >= 400 {
                    let errorBody = String(data: data, encoding: .utf8) ?? ""
                    
                    // Check if this is a transient error worth retrying
                    if isTransientError(httpResponse.statusCode) && attempt < maxRetries {
                        NSLog("UPnPManager: RenderingControl %@ got transient error %d, will retry: %@", action, httpResponse.statusCode, errorBody)
                        lastError = CastError.playbackFailed("SOAP error \(httpResponse.statusCode)")
                        continue
                    }
                    
                    NSLog("UPnPManager: RenderingControl SOAP error %d: %@", httpResponse.statusCode, errorBody)
                    throw CastError.playbackFailed("SOAP error \(httpResponse.statusCode)")
                }
                
                // Success
                if attempt > 0 {
                    NSLog("UPnPManager: RenderingControl %@ succeeded on retry attempt %d", action, attempt + 1)
                }
                return String(data: data, encoding: .utf8) ?? ""
                
            } catch let error as CastError {
                lastError = error
                // Don't retry CastErrors that aren't from transient HTTP errors
                if case .playbackFailed(let msg) = error, msg.contains("SOAP error") {
                    // Already handled above - this is from a non-transient error
                    throw error
                }
                throw error
            } catch {
                // Network errors might be transient too
                if attempt < maxRetries {
                    NSLog("UPnPManager: RenderingControl %@ network error, will retry: %@", action, error.localizedDescription)
                    lastError = CastError.networkError(error)
                    continue
                }
                throw CastError.networkError(error)
            }
        }
        
        throw lastError ?? CastError.playbackFailed("Unknown error after retries")
    }
    
    /// Send a SOAP action to the device with retry logic for transient errors
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
        
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            if attempt > 0 {
                // Exponential backoff: 0.5s, 1s, 2s
                let delay = retryBaseDelay * UInt64(1 << (attempt - 1))
                NSLog("UPnPManager: Retrying AVTransport %@ (attempt %d/%d) after %.1fs", action, attempt + 1, maxRetries + 1, Double(delay) / 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
            
            var request = URLRequest(url: controlURL)
            request.httpMethod = "POST"
            request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
            request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
            request.httpBody = soapBody.data(using: .utf8)
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CastError.networkError(NSError(domain: "UPnP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                }
                
                if httpResponse.statusCode >= 400 {
                    let errorBody = String(data: data, encoding: .utf8) ?? ""
                    
                    // Parse SOAP fault for more details
                    var errorDetail = "SOAP error \(httpResponse.statusCode)"
                    if let faultString = extractXMLValue(errorBody, tag: "faultstring") {
                        errorDetail = faultString
                    } else if let upnpError = extractXMLValue(errorBody, tag: "errorDescription") {
                        errorDetail = upnpError
                    }
                    
                    // Check if this is a transient error worth retrying
                    if isTransientError(httpResponse.statusCode) && attempt < maxRetries {
                        NSLog("UPnPManager: AVTransport %@ got transient error %d, will retry: %@", action, httpResponse.statusCode, errorBody)
                        lastError = CastError.playbackFailed(errorDetail)
                        continue
                    }
                    
                    NSLog("UPnPManager: SOAP error %d for %@: %@", httpResponse.statusCode, action, errorBody)
                    throw CastError.playbackFailed(errorDetail)
                }
                
                // Success
                if attempt > 0 {
                    NSLog("UPnPManager: AVTransport %@ succeeded on retry attempt %d", action, attempt + 1)
                }
                return String(data: data, encoding: .utf8) ?? ""
                
            } catch let error as CastError {
                lastError = error
                // Don't retry CastErrors that aren't from transient HTTP errors
                if case .playbackFailed(let msg) = error, msg.contains("SOAP error") {
                    // Already handled above - this is from a non-transient error
                    throw error
                }
                throw error
            } catch {
                // Network errors might be transient too
                if attempt < maxRetries {
                    NSLog("UPnPManager: AVTransport %@ network error, will retry: %@", action, error.localizedDescription)
                    lastError = CastError.networkError(error)
                    continue
                }
                throw CastError.networkError(error)
            }
        }
        
        throw lastError ?? CastError.playbackFailed("Unknown error after retries")
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
