import Foundation
import Network

/// Protocol for Chromecast discovery and playback control
/// Uses mDNS to discover devices advertising _googlecast._tcp
class ChromecastManager: CastSessionControllerDelegate {
    
    // MARK: - Singleton
    
    static let shared = ChromecastManager()
    
    // MARK: - Notifications
    
    /// Posted when media status is updated from Chromecast (contains CastMediaStatus in userInfo)
    static let mediaStatusDidUpdateNotification = Notification.Name("ChromecastMediaStatusDidUpdate")
    
    // MARK: - Properties
    
    /// Discovered Chromecast devices
    private(set) var devices: [CastDevice] = []
    
    /// Network browser for mDNS discovery
    private var browser: NWBrowser?
    
    /// Active connections to Chromecast devices
    private var connections: [String: NWConnection] = [:]
    
    /// Active cast session
    private(set) var activeSession: CastSession?
    
    /// Cast protocol session controller
    private var sessionController: CastSessionController?
    
    /// Discovery state
    private(set) var isDiscovering: Bool = false
    
    // MARK: - Constants
    
    /// Chromecast default port for Cast protocol
    private let chromecastPort = 8009
    
    /// Default Media Receiver app ID
    private let defaultMediaReceiverAppID = "CC1AD845"
    
    /// Heartbeat interval in seconds
    private let heartbeatInterval: TimeInterval = 5.0
    
    /// Connection timeout
    private let connectionTimeout: TimeInterval = 10.0
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Discovery
    
    /// Start discovering Chromecast devices on the network
    func startDiscovery() {
        guard !isDiscovering else { return }
        
        NSLog("ChromecastManager: Starting discovery...")
        isDiscovering = true
        
        // Browse for Chromecast devices via mDNS
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_googlecast._tcp", domain: "local.")
        let parameters = NWParameters()
        
        browser = NWBrowser(for: descriptor, using: parameters)
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            NSLog("ChromecastManager: Browse results changed - %d results, %d changes", results.count, changes.count)
            for change in changes {
                switch change {
                case .added(let result):
                    NSLog("ChromecastManager: Device added: %@", String(describing: result.endpoint))
                case .removed(let result):
                    NSLog("ChromecastManager: Device removed: %@", String(describing: result.endpoint))
                case .changed(let old, let new, _):
                    NSLog("ChromecastManager: Device changed: %@ -> %@", String(describing: old.endpoint), String(describing: new.endpoint))
                case .identical:
                    break
                @unknown default:
                    break
                }
            }
            self?.handleBrowseResults(results)
        }
        
        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .setup:
                NSLog("ChromecastManager: Browser setting up...")
            case .ready:
                NSLog("ChromecastManager: Browser ready - actively discovering _googlecast._tcp services")
            case .failed(let error):
                NSLog("ChromecastManager: Browser failed: %@", error.localizedDescription)
                self?.isDiscovering = false
            case .cancelled:
                NSLog("ChromecastManager: Browser cancelled")
                self?.isDiscovering = false
            case .waiting(let error):
                NSLog("ChromecastManager: Browser waiting: %@", error.localizedDescription)
            @unknown default:
                break
            }
        }
        
        browser?.start(queue: .main)
    }
    
    /// Stop discovering devices
    func stopDiscovery() {
        NSLog("ChromecastManager: Stopping discovery")
        browser?.cancel()
        browser = nil
        isDiscovering = false
    }
    
    /// Handle browse results from mDNS
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            if case let .service(name, type, domain, _) = result.endpoint {
                NSLog("ChromecastManager: Processing service: %@ (type: %@, domain: %@)", name, type, domain)
                
                // Resolve the service to get the address
                resolveService(result: result, name: name) { device in
                    if let device = device {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            if !self.devices.contains(where: { $0.id == device.id }) {
                                self.devices.append(device)
                                NSLog("ChromecastManager: Added device: %@ at %@:%d", device.name, device.address, device.port)
                                NotificationCenter.default.post(name: CastManager.devicesDidChangeNotification, object: nil)
                            }
                        }
                    } else {
                        NSLog("ChromecastManager: Failed to resolve service: %@", name)
                    }
                }
            }
        }
    }
    
    /// Resolve a Bonjour service to get IP address and port with retry logic
    private func resolveService(result: NWBrowser.Result, name: String, completion: @escaping (CastDevice?) -> Void) {
        resolveServiceWithRetry(result: result, name: name, attempt: 1, maxAttempts: 3, completion: completion)
    }
    
    /// Internal retry implementation for service resolution
    private func resolveServiceWithRetry(result: NWBrowser.Result, name: String, attempt: Int, maxAttempts: Int, completion: @escaping (CastDevice?) -> Void) {
        let endpoint = result.endpoint
        
        NSLog("ChromecastManager: Resolving endpoint: %@ (attempt %d/%d)", String(describing: endpoint), attempt, maxAttempts)
        
        // Try to extract info directly from the endpoint if possible
        if case let .service(serviceName, _, _, _) = endpoint {
            // Try using NWConnection to resolve
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            
            let connection = NWConnection(to: endpoint, using: parameters)
            var completed = false
            
            connection.stateUpdateHandler = { [weak self] state in
                guard !completed else { return }
                
                switch state {
                case .preparing:
                    NSLog("ChromecastManager: Connection preparing for %@", serviceName)
                case .ready:
                    completed = true
                    NSLog("ChromecastManager: Connection ready for %@", serviceName)
                    // Get the resolved address
                    if let path = connection.currentPath,
                       let remoteEndpoint = path.remoteEndpoint {
                        NSLog("ChromecastManager: Resolved to: %@", String(describing: remoteEndpoint))
                        let device = self?.createDevice(from: remoteEndpoint, name: name, metadata: result.metadata)
                        connection.cancel()
                        completion(device)
                    } else {
                        NSLog("ChromecastManager: No remote endpoint found for %@", serviceName)
                        connection.cancel()
                        // Retry if we have attempts left
                        if attempt < maxAttempts {
                            self?.retryResolution(result: result, name: name, attempt: attempt, maxAttempts: maxAttempts, completion: completion)
                        } else {
                            completion(nil)
                        }
                    }
                case .failed(let error):
                    completed = true
                    NSLog("ChromecastManager: Connection failed for %@: %@", serviceName, error.localizedDescription)
                    connection.cancel()
                    // Retry if we have attempts left
                    if attempt < maxAttempts {
                        self?.retryResolution(result: result, name: name, attempt: attempt, maxAttempts: maxAttempts, completion: completion)
                    } else {
                        completion(nil)
                    }
                case .cancelled:
                    if !completed {
                        completed = true
                        completion(nil)
                    }
                case .waiting(let error):
                    NSLog("ChromecastManager: Connection waiting for %@: %@", serviceName, error.localizedDescription)
                default:
                    break
                }
            }
            
            connection.start(queue: .main)
            
            // Timeout the resolution (shorter timeout per attempt: 5s instead of 10s)
            let timeout: TimeInterval = 5.0
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard !completed else { return }
                completed = true
                NSLog("ChromecastManager: Connection timeout for %@ (attempt %d)", serviceName, attempt)
                connection.cancel()
                // Retry if we have attempts left
                if attempt < maxAttempts {
                    self?.retryResolution(result: result, name: name, attempt: attempt, maxAttempts: maxAttempts, completion: completion)
                } else {
                    completion(nil)
                }
            }
        } else {
            completion(nil)
        }
    }
    
    /// Schedule a retry for service resolution with backoff
    private func retryResolution(result: NWBrowser.Result, name: String, attempt: Int, maxAttempts: Int, completion: @escaping (CastDevice?) -> Void) {
        // Exponential backoff: 1s, 2s, 4s
        let delay = TimeInterval(1 << (attempt - 1))
        NSLog("ChromecastManager: Scheduling retry for %@ in %.0fs", name, delay)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.isDiscovering == true else {
                completion(nil)
                return
            }
            self?.resolveServiceWithRetry(result: result, name: name, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion)
        }
    }
    
    /// Create a CastDevice from a resolved endpoint
    private func createDevice(from endpoint: NWEndpoint, name: String, metadata: NWBrowser.Result.Metadata?) -> CastDevice? {
        var address: String?
        var port = chromecastPort
        
        switch endpoint {
        case .hostPort(let host, let resolvedPort):
            switch host {
            case .ipv4(let ipv4):
                address = "\(ipv4)"
            case .ipv6(let ipv6):
                address = "\(ipv6)"
            case .name(let hostname, _):
                address = hostname
            @unknown default:
                break
            }
            port = Int(resolvedPort.rawValue)
        default:
            break
        }
        
        guard let deviceAddress = address else { return nil }
        
        // Parse TXT record metadata if available
        var modelName: String?
        if case let .bonjour(txtRecord) = metadata {
            // Chromecast TXT records contain model name (md), friendly name (fn), etc.
            // NWTXTRecord values are already strings
            modelName = txtRecord["md"]
        }
        
        let deviceID = "chromecast:\(deviceAddress):\(port)"
        
        return CastDevice(
            id: deviceID,
            name: name,
            type: .chromecast,
            address: deviceAddress,
            port: port,
            manufacturer: "Google",
            modelName: modelName
        )
    }
    
    /// Remove all discovered devices
    func clearDevices() {
        devices.removeAll()
    }
    
    // MARK: - Connection
    
    /// Connect to a Chromecast device
    func connect(to device: CastDevice) async throws {
        guard device.type == .chromecast else {
            throw CastError.unsupportedDevice
        }
        
        NSLog("ChromecastManager: Connecting to %@ at %@:%d", device.name, device.address, device.port)
        
        // Create session controller and connect
        let controller = CastSessionController()
        
        // Strip interface suffix from address (e.g., "192.168.0.199%en0" -> "192.168.0.199")
        let cleanAddress = device.address.components(separatedBy: "%").first ?? device.address
        
        // Use continuation to bridge completion handler to async/await
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controller.connect(host: cleanAddress, port: device.port) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        sessionController = controller
        sessionController?.delegate = self
        activeSession = CastSession(device: device)
        activeSession?.state = .connected
        
        NSLog("ChromecastManager: Connected to %@", device.name)
    }
    
    /// Disconnect from the current device
    func disconnect() {
        guard let session = activeSession else { return }
        
        NSLog("ChromecastManager: Disconnecting from %@", session.device.name)
        
        // Stop status polling before disconnecting
        sessionController?.stopStatusPolling()
        sessionController?.disconnect()
        sessionController = nil
        
        connections[session.device.id]?.cancel()
        connections.removeValue(forKey: session.device.id)
        activeSession = nil
        
        NotificationCenter.default.post(name: CastManager.sessionDidChangeNotification, object: nil)
    }
    
    // MARK: - Playback Control
    
    /// Cast media to the connected device
    func cast(url: URL, metadata: CastMetadata) async throws {
        guard let session = activeSession,
              let controller = sessionController else {
            throw CastError.sessionNotActive
        }
        
        NSLog("ChromecastManager: Casting %@ to %@", url.absoluteString, session.device.name)
        
        // Launch the Default Media Receiver app
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controller.launchApp { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Load the media
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controller.loadMedia(
                url: url,
                contentType: metadata.contentType,
                title: metadata.title,
                artist: metadata.artist
            ) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Update session state
        activeSession?.state = .casting
        activeSession?.currentURL = url
        activeSession?.metadata = metadata
        
        // Start polling for status updates to keep position synced
        controller.startStatusPolling(interval: 1.0)
        
        NSLog("ChromecastManager: Successfully started casting to %@", session.device.name)
        
        NotificationCenter.default.post(name: CastManager.playbackStateDidChangeNotification, object: nil)
    }
    
    /// Stop casting
    func stop() {
        guard let session = activeSession else { return }
        
        NSLog("ChromecastManager: Stopping playback on %@", session.device.name)
        
        // Stop status polling
        sessionController?.stopStatusPolling()
        sessionController?.stop()
        
        session.state = .connected
        session.currentURL = nil
        session.metadata = nil
        
        NotificationCenter.default.post(name: CastManager.playbackStateDidChangeNotification, object: nil)
    }
    
    /// Pause playback
    func pause() {
        guard let session = activeSession else { return }
        NSLog("ChromecastManager: Pausing playback on %@", session.device.name)
        sessionController?.pause()
    }
    
    /// Resume playback
    func resume() {
        guard let session = activeSession else { return }
        NSLog("ChromecastManager: Resuming playback on %@", session.device.name)
        sessionController?.play()
    }
    
    /// Seek to position
    func seek(to time: TimeInterval) {
        guard let session = activeSession else { return }
        NSLog("ChromecastManager: Seeking to %.1f on %@", time, session.device.name)
        sessionController?.seek(to: time)
    }
    
    // MARK: - Volume Control
    
    /// Set volume (0.0 - 1.0)
    func setVolume(_ volume: Float) {
        guard let session = activeSession else { return }
        NSLog("ChromecastManager: Setting volume to %.2f on %@", volume, session.device.name)
        sessionController?.setVolume(volume)
    }
    
    /// Get current volume
    func getVolume() -> Float {
        return 1.0
    }
    
    /// Set mute state
    func setMuted(_ muted: Bool) {
        guard let session = activeSession else { return }
        NSLog("ChromecastManager: Setting mute to %@ on %@", muted ? "ON" : "OFF", session.device.name)
        sessionController?.setMute(muted)
    }
    
    // MARK: - CastSessionControllerDelegate
    
    func castSessionDidUpdateMediaStatus(_ status: CastMediaStatus) {
        // Post notification so CastManager can update time tracking
        NotificationCenter.default.post(
            name: Self.mediaStatusDidUpdateNotification,
            object: self,
            userInfo: ["status": status]
        )
    }
    
    func castSessionDidClose() {
        NSLog("ChromecastManager: Session closed unexpectedly")
        
        // Stop status polling
        sessionController?.stopStatusPolling()
        
        // Update session state
        if let session = activeSession {
            session.state = .idle
            session.currentURL = nil
            session.metadata = nil
        }
        
        NotificationCenter.default.post(name: CastManager.sessionDidChangeNotification, object: nil)
    }
}
