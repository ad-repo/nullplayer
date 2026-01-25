import Foundation
import Network

// MARK: - Cast Protocol Constants

enum CastNamespace: String {
    case connection = "urn:x-cast:com.google.cast.tp.connection"
    case heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    case receiver = "urn:x-cast:com.google.cast.receiver"
    case media = "urn:x-cast:com.google.cast.media"
}

// MARK: - CastMessage Protobuf Encoding/Decoding

struct CastMessage {
    var protocolVersion: Int = 0
    var sourceId: String = "sender-0"
    var destinationId: String = "receiver-0"
    var namespace: String
    var payloadType: Int = 0
    var payloadUtf8: String = ""
    
    init(namespace: String) {
        self.namespace = namespace
    }
    
    func encode() -> Data {
        var result = Data()
        
        // Field 1: protocol_version (varint)
        result.append(contentsOf: [0x08])
        result.append(contentsOf: encodeVarint(UInt64(protocolVersion)))
        
        // Field 2: source_id (length-delimited)
        result.append(contentsOf: [0x12])
        result.append(encodeString(sourceId))
        
        // Field 3: destination_id (length-delimited)
        result.append(contentsOf: [0x1a])
        result.append(encodeString(destinationId))
        
        // Field 4: namespace (length-delimited)
        result.append(contentsOf: [0x22])
        result.append(encodeString(namespace))
        
        // Field 5: payload_type (varint)
        result.append(contentsOf: [0x28])
        result.append(contentsOf: encodeVarint(UInt64(payloadType)))
        
        // Field 6: payload_utf8 (length-delimited)
        result.append(contentsOf: [0x32])
        result.append(encodeString(payloadUtf8))
        
        return result
    }
    
    private func encodeVarint(_ value: UInt64) -> [UInt8] {
        var result: [UInt8] = []
        var v = value
        while v > 127 {
            result.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        result.append(UInt8(v))
        return result
    }
    
    private func encodeString(_ str: String) -> Data {
        let utf8 = Data(str.utf8)
        var result = encodeVarint(UInt64(utf8.count))
        result.append(contentsOf: utf8)
        return Data(result)
    }
    
    static func decode(from data: Data) -> CastMessage? {
        var message = CastMessage(namespace: "")
        var offset = 0
        
        while offset < data.count {
            guard let (tag, newOffset) = decodeVarint(data, at: offset) else { break }
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x7)
            offset = newOffset
            
            switch (fieldNumber, wireType) {
            case (1, 0):
                guard let (v, o) = decodeVarint(data, at: offset) else { return nil }
                message.protocolVersion = Int(v)
                offset = o
            case (2, 2):
                guard let (v, o) = decodeString(data, at: offset) else { return nil }
                message.sourceId = v
                offset = o
            case (3, 2):
                guard let (v, o) = decodeString(data, at: offset) else { return nil }
                message.destinationId = v
                offset = o
            case (4, 2):
                guard let (v, o) = decodeString(data, at: offset) else { return nil }
                message.namespace = v
                offset = o
            case (5, 0):
                guard let (v, o) = decodeVarint(data, at: offset) else { return nil }
                message.payloadType = Int(v)
                offset = o
            case (6, 2):
                guard let (v, o) = decodeString(data, at: offset) else { return nil }
                message.payloadUtf8 = v
                offset = o
            default:
                guard let o = skipField(data, at: offset, wireType: wireType) else { return nil }
                offset = o
            }
        }
        return message
    }
    
    private static func decodeVarint(_ data: Data, at offset: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift = 0
        var pos = offset
        while pos < data.count {
            let byte = data[pos]
            pos += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (value, pos) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
    
    private static func decodeString(_ data: Data, at offset: Int) -> (String, Int)? {
        guard let (length, dataOffset) = decodeVarint(data, at: offset) else { return nil }
        let end = dataOffset + Int(length)
        guard end <= data.count else { return nil }
        guard let str = String(data: data[dataOffset..<end], encoding: .utf8) else { return nil }
        return (str, end)
    }
    
    private static func skipField(_ data: Data, at offset: Int, wireType: Int) -> Int? {
        switch wireType {
        case 0: return decodeVarint(data, at: offset)?.1
        case 1: return offset + 8
        case 2:
            guard let (len, o) = decodeVarint(data, at: offset) else { return nil }
            return o + Int(len)
        case 5: return offset + 4
        default: return nil
        }
    }
}

// MARK: - Cast Media Status

/// Represents the current media playback status from a Chromecast device
struct CastMediaStatus {
    /// Current playback position in seconds
    var currentTime: TimeInterval = 0
    /// Total media duration in seconds (if known)
    var duration: TimeInterval?
    /// Current player state
    var playerState: CastPlayerState = .unknown
    /// Media session ID
    var mediaSessionId: Int = 0
}

/// Chromecast player states
enum CastPlayerState: String {
    case idle = "IDLE"
    case buffering = "BUFFERING"
    case playing = "PLAYING"
    case paused = "PAUSED"
    case unknown = "UNKNOWN"
}

/// Delegate protocol for receiving Chromecast status updates
protocol CastSessionControllerDelegate: AnyObject {
    /// Called when media status is updated (position, state changes)
    func castSessionDidUpdateMediaStatus(_ status: CastMediaStatus)
    /// Called when the session is closed (e.g., app stopped, connection lost)
    func castSessionDidClose()
}

// MARK: - Cast Session Controller (Class-based with manual synchronization)

/// Thread-safe session controller using class with locks
class CastSessionController {
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var transportId: String?
    private var mediaSessionId: Int?
    private var requestId = 0
    private var isConnected = false
    private var heartbeatTimer: Timer?
    private var statusPollTimer: Timer?
    
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.adamp.castcontroller")
    
    /// Delegate for receiving status updates
    weak var delegate: CastSessionControllerDelegate?
    
    // Completion handlers for async operations
    private var transportIdCompletion: ((String?) -> Void)?
    
    deinit {
        disconnect()
    }
    
    private func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
    
    private func nextRequestId() -> Int {
        return withLock {
            requestId += 1
            return requestId
        }
    }
    
    /// Connect to a Chromecast device
    func connect(host: String, port: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Strip interface suffix (e.g., %en0)
        let cleanHost = host.components(separatedBy: "%").first ?? host
        NSLog("CastSessionController: Connecting to %@:%d", cleanHost, port)
        
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, completion in
            completion(true)  // Accept self-signed certs
        }, queue)
        
        let params = NWParameters(tls: tlsOptions)
        let conn = NWConnection(host: NWEndpoint.Host(cleanHost), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: params)
        
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                NSLog("CastSessionController: TLS connected")
                self.withLock { self.isConnected = true }
                self.startReceiving()
                self.sendMessage(namespace: .connection, payload: ["type": "CONNECT"], to: "receiver-0")
                self.startHeartbeat()
                completion(.success(()))
                
            case .failed(let error):
                NSLog("CastSessionController: Connection failed: %@", error.localizedDescription)
                completion(.failure(error))
                
            case .cancelled:
                NSLog("CastSessionController: Connection cancelled")
                
            default:
                break
            }
        }
        
        self.connection = conn
        conn.start(queue: queue)
    }
    
    func disconnect() {
        NSLog("CastSessionController: Disconnecting")
        
        // Stop timers
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
            self?.statusPollTimer?.invalidate()
            self?.statusPollTimer = nil
        }
        
        withLock {
            isConnected = false
            
            if let tid = transportId {
                sendMessageUnsafe(namespace: .connection, payload: ["type": "CLOSE"], to: tid)
            }
            sendMessageUnsafe(namespace: .connection, payload: ["type": "CLOSE"], to: "receiver-0")
            
            connection?.cancel()
            connection = nil
            transportId = nil
            mediaSessionId = nil
        }
    }
    
    /// Launch the Default Media Receiver and wait for transportId
    func launchApp(completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("CastSessionController: Launching media receiver app")
        
        let rid = nextRequestId()
        sendMessage(namespace: .receiver, payload: [
            "type": "LAUNCH",
            "appId": "CC1AD845",
            "requestId": rid
        ], to: "receiver-0")
        
        // Set up completion handler for when we get transportId
        withLock {
            self.transportIdCompletion = { [weak self] tid in
                guard let self = self else { return }
                
                if let tid = tid {
                    NSLog("CastSessionController: Got transportId: %@", tid)
                    // Connect to the app transport
                    self.sendMessage(namespace: .connection, payload: ["type": "CONNECT"], to: tid)
                    completion(.success(()))
                } else {
                    completion(.failure(CastError.playbackFailed("Timeout launching media receiver")))
                }
            }
        }
        
        // Set up timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self else { return }
            let handler = self.withLock { () -> ((String?) -> Void)? in
                let h = self.transportIdCompletion
                self.transportIdCompletion = nil
                return h
            }
            
            // Only call if we haven't already received transportId
            if self.withLock({ self.transportId }) == nil {
                handler?(nil)
            }
        }
    }
    
    /// Load media to play
    func loadMedia(url: URL, contentType: String, title: String?, artist: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tid = withLock({ transportId }) else {
            completion(.failure(CastError.playbackFailed("Not connected to app")))
            return
        }
        
        NSLog("CastSessionController: Loading media: %@", url.absoluteString)
        
        let rid = nextRequestId()
        var media: [String: Any] = [
            "contentId": url.absoluteString,
            "contentType": contentType,
            "streamType": "BUFFERED"
        ]
        
        if let title = title {
            media["metadata"] = [
                "type": 0,
                "metadataType": 0,
                "title": title,
                "subtitle": artist ?? ""
            ]
        }
        
        sendMessage(namespace: .media, payload: [
            "type": "LOAD",
            "media": media,
            "autoplay": true,
            "requestId": rid
        ], to: tid)
        
        // Consider load successful after sending
        completion(.success(()))
    }
    
    func play() {
        guard let tid = withLock({ transportId }),
              let msid = withLock({ mediaSessionId }) else { return }
        
        sendMessage(namespace: .media, payload: [
            "type": "PLAY",
            "mediaSessionId": msid,
            "requestId": nextRequestId()
        ], to: tid)
    }
    
    func pause() {
        guard let tid = withLock({ transportId }),
              let msid = withLock({ mediaSessionId }) else { return }
        
        sendMessage(namespace: .media, payload: [
            "type": "PAUSE",
            "mediaSessionId": msid,
            "requestId": nextRequestId()
        ], to: tid)
    }
    
    func stop() {
        let (tid, msid) = withLock { (transportId, mediaSessionId) }
        
        guard let tid = tid else {
            NSLog("CastSessionController: stop() - no transportId, cannot send STOP command")
            return
        }
        guard let msid = msid else {
            NSLog("CastSessionController: stop() - no mediaSessionId, cannot send STOP command")
            return
        }
        
        NSLog("CastSessionController: Sending STOP command with mediaSessionId: %d", msid)
        sendMessage(namespace: .media, payload: [
            "type": "STOP",
            "mediaSessionId": msid,
            "requestId": nextRequestId()
        ], to: tid)
    }
    
    func seek(to time: TimeInterval) {
        let (tid, msid) = withLock { (transportId, mediaSessionId) }
        
        guard let tid = tid else {
            NSLog("CastSessionController: seek() - no transportId, cannot send SEEK command")
            return
        }
        guard let msid = msid else {
            NSLog("CastSessionController: seek() - no mediaSessionId, cannot send SEEK command")
            return
        }
        
        NSLog("CastSessionController: Sending SEEK command to %.1fs with mediaSessionId: %d", time, msid)
        sendMessage(namespace: .media, payload: [
            "type": "SEEK",
            "mediaSessionId": msid,
            "currentTime": time,
            "requestId": nextRequestId()
        ], to: tid)
        
        // Request status update after seek to confirm position and get updated mediaSessionId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.requestMediaStatus()
        }
    }
    
    /// Request current media status from the Chromecast
    func requestMediaStatus() {
        guard let tid = withLock({ transportId }) else { return }
        
        sendMessage(namespace: .media, payload: [
            "type": "GET_STATUS",
            "requestId": nextRequestId()
        ], to: tid)
    }
    
    func setVolume(_ level: Float) {
        sendMessage(namespace: .receiver, payload: [
            "type": "SET_VOLUME",
            "volume": ["level": level],
            "requestId": nextRequestId()
        ], to: "receiver-0")
    }
    
    func setMute(_ muted: Bool) {
        sendMessage(namespace: .receiver, payload: [
            "type": "SET_VOLUME",
            "volume": ["muted": muted],
            "requestId": nextRequestId()
        ], to: "receiver-0")
    }
    
    // MARK: - Private Methods
    
    private func sendMessage(namespace: CastNamespace, payload: [String: Any], to destination: String) {
        withLock {
            sendMessageUnsafe(namespace: namespace, payload: payload, to: destination)
        }
    }
    
    private func sendMessageUnsafe(namespace: CastNamespace, payload: [String: Any], to destination: String) {
        guard let conn = connection, isConnected else { return }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        var msg = CastMessage(namespace: namespace.rawValue)
        msg.destinationId = destination
        msg.payloadUtf8 = jsonString
        
        let data = msg.encode()
        
        // Frame with 4-byte length prefix
        var framed = Data()
        var len = UInt32(data.count).bigEndian
        framed.append(Data(bytes: &len, count: 4))
        framed.append(data)
        
        conn.send(content: framed, completion: .contentProcessed { error in
            if let e = error {
                NSLog("CastSessionController: Send error: %@", e.localizedDescription)
            }
        })
    }
    
    private func startReceiving() {
        guard let conn = connection else {
            NSLog("CastSessionController: startReceiving - no connection!")
            return
        }
        
        NSLog("CastSessionController: startReceiving - setting up receive handler")
        
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else {
                NSLog("CastSessionController: receive callback - self deallocated")
                return
            }
            
            if let error = error {
                NSLog("CastSessionController: Receive error: %@", error.localizedDescription)
                return
            }
            
            if let data = content {
                NSLog("CastSessionController: Received %d bytes", data.count)
                self.handleReceivedData(data)
            }
            
            if isComplete {
                NSLog("CastSessionController: Connection closed by remote")
            } else if error == nil {
                // Continue receiving
                self.startReceiving()
            }
        }
    }
    
    private func handleReceivedData(_ data: Data) {
        withLock {
            receiveBuffer.append(data)
        }
        
        processBuffer()
    }
    
    private func processBuffer() {
        while true {
            let (msgData, shouldContinue) = withLock { () -> (Data?, Bool) in
                guard receiveBuffer.count >= 4 else { return (nil, false) }
                
                // Read length (big-endian UInt32) - use startIndex for proper slice handling
                let b0 = receiveBuffer[receiveBuffer.startIndex]
                let b1 = receiveBuffer[receiveBuffer.startIndex + 1]
                let b2 = receiveBuffer[receiveBuffer.startIndex + 2]
                let b3 = receiveBuffer[receiveBuffer.startIndex + 3]
                let length = UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3)
                
                let total = 4 + Int(length)
                guard receiveBuffer.count >= total else { return (nil, false) }
                
                // Extract message data using proper slice indices
                let startIdx = receiveBuffer.startIndex + 4
                let endIdx = receiveBuffer.startIndex + total
                let msgData = Data(receiveBuffer[startIdx..<endIdx])
                
                // Remove processed data from buffer
                receiveBuffer = Data(receiveBuffer.dropFirst(total))
                
                return (msgData, true)
            }
            
            guard shouldContinue, let msgData = msgData else { break }
            
            if let msg = CastMessage.decode(from: msgData) {
                handleMessage(msg)
            }
        }
    }
    
    private func handleMessage(_ msg: CastMessage) {
        NSLog("CastSessionController: handleMessage - namespace: %@, from: %@", msg.namespace, msg.sourceId)
        
        guard let data = msg.payloadUtf8.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            NSLog("CastSessionController: handleMessage - failed to parse JSON")
            return
        }
        
        NSLog("CastSessionController: handleMessage - type: %@", type)
        
        switch type {
        case "PONG":
            break
            
        case "RECEIVER_STATUS":
            if let status = json["status"] as? [String: Any],
               let apps = status["applications"] as? [[String: Any]],
               let app = apps.first,
               let tid = app["transportId"] as? String {
                
                let handler = withLock { () -> ((String?) -> Void)? in
                    self.transportId = tid
                    let h = self.transportIdCompletion
                    self.transportIdCompletion = nil
                    return h
                }
                
                NSLog("CastSessionController: Got transportId: %@", tid)
                handler?(tid)
            }
            
        case "MEDIA_STATUS":
            if let statuses = json["status"] as? [[String: Any]],
               let status = statuses.first {
                
                // Extract mediaSessionId
                if let msid = status["mediaSessionId"] as? Int {
                    withLock { self.mediaSessionId = msid }
                    
                    // Build status object with all available info
                    var mediaStatus = CastMediaStatus()
                    mediaStatus.mediaSessionId = msid
                    
                    // Extract currentTime (playback position)
                    if let currentTime = status["currentTime"] as? Double {
                        mediaStatus.currentTime = currentTime
                    }
                    
                    // Extract playerState
                    if let stateString = status["playerState"] as? String,
                       let state = CastPlayerState(rawValue: stateString) {
                        mediaStatus.playerState = state
                    }
                    
                    // Extract duration from media object if present
                    if let media = status["media"] as? [String: Any],
                       let duration = media["duration"] as? Double {
                        mediaStatus.duration = duration
                    }
                    
                    NSLog("CastSessionController: MEDIA_STATUS - sessionId: %d, time: %.1f, state: %@", 
                          msid, mediaStatus.currentTime, mediaStatus.playerState.rawValue)
                    
                    // Notify delegate on main thread
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.castSessionDidUpdateMediaStatus(mediaStatus)
                    }
                } else {
                    NSLog("CastSessionController: MEDIA_STATUS - no mediaSessionId in status")
                }
            } else {
                // Empty status array might indicate media stopped
                NSLog("CastSessionController: MEDIA_STATUS - empty or invalid status array")
            }
            
        case "CLOSE":
            NSLog("CastSessionController: Received CLOSE from %@", msg.sourceId)
            // Notify delegate that session closed
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.castSessionDidClose()
            }
            
        default:
            break
        }
    }
    
    private func startHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.sendMessage(namespace: .heartbeat, payload: ["type": "PING"], to: "receiver-0")
            }
        }
    }
    
    /// Start polling for media status updates (keeps position synced during buffering)
    func startStatusPolling(interval: TimeInterval = 1.0) {
        stopStatusPolling()
        
        DispatchQueue.main.async { [weak self] in
            self?.statusPollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.requestMediaStatus()
            }
            // Also use common mode so timer fires during menu tracking
            if let timer = self?.statusPollTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    /// Stop polling for media status
    func stopStatusPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.statusPollTimer?.invalidate()
            self?.statusPollTimer = nil
        }
    }
}
