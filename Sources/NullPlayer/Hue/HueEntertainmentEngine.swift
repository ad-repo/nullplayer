import Foundation
import Network
import Security

enum HueEntertainmentState: Equatable {
    case idle
    case connecting
    case streaming
    case failed(String)
}

final class HueEntertainmentEngine {
    private(set) var state: HueEntertainmentState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    var onStateChange: ((HueEntertainmentState) -> Void)?

    private var configuredBridge: HueBridge?
    private var configuredPSKIdentity: String?
    private var configuredClientKey: String?
    private var configuredAreaID: String?
    private var targetFPS: Int = 50
    private let sendQueue = DispatchQueue(label: "NullPlayer.HueEntertainmentEngine.SendQueue", qos: .userInteractive)
    private let sendQueueKey = DispatchSpecificKey<Void>()
    private var connection: NWConnection?
    private var keepAliveTimer: DispatchSourceTimer?
    private var sequenceNumber: UInt8 = 0
    private var lastFrameSendNanos: UInt64 = 0
    private var lastPacket: Data?
    private let keepAliveInterval: TimeInterval = 9.0
    private let packetBuilder = HueEntertainmentPacketBuilder()
    private var sentPacketCount: UInt64 = 0
    private var throttledFrameCount: UInt64 = 0
    private var lastStatsLogNanos: UInt64 = 0

    init() {
        sendQueue.setSpecific(key: sendQueueKey, value: ())
    }

    func configure(
        bridge: HueBridge,
        pskIdentity: String,
        clientKey: String,
        entertainmentAreaID: String,
        targetFPS: Int
    ) {
        configuredBridge = bridge
        configuredPSKIdentity = pskIdentity
        configuredClientKey = clientKey
        configuredAreaID = entertainmentAreaID
        self.targetFPS = max(20, min(60, targetFPS))
    }

    func start() {
        runOnSendQueueSync {
            guard let bridge = configuredBridge,
                  let pskIdentity = configuredPSKIdentity,
                  pskIdentity.isEmpty == false,
                  let clientKeyHex = configuredClientKey,
                  clientKeyHex.isEmpty == false,
                  configuredAreaID?.isEmpty == false else {
                state = .failed("Entertainment engine is missing bridge credentials")
                return
            }

            guard let clientKeyData = decodeHex(clientKeyHex) else {
                state = .failed("Invalid Hue client key format")
                return
            }

            stopKeepAliveTimer()
            connection?.cancel()
            connection = nil
            state = .connecting
            sequenceNumber = 0
            lastFrameSendNanos = 0
            lastPacket = nil
            sentPacketCount = 0
            throttledFrameCount = 0
            lastStatsLogNanos = 0
            NSLog("HueEntertainmentEngine: starting DTLS session host=%@ area=%@", bridge.ipAddress, configuredAreaID ?? "")

            let tlsOptions = NWProtocolTLS.Options()
            let securityOptions = tlsOptions.securityProtocolOptions
            sec_protocol_options_set_min_tls_protocol_version(securityOptions, .DTLSv12)
            sec_protocol_options_set_max_tls_protocol_version(securityOptions, .DTLSv12)
            if let ciphersuite = tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256) {
                sec_protocol_options_append_tls_ciphersuite(securityOptions, ciphersuite)
            }
            sec_protocol_options_set_verify_block(securityOptions, { _, _, complete in
                complete(true)
            }, sendQueue)
            sec_protocol_options_add_pre_shared_key(
                securityOptions,
                makeDispatchData(from: clientKeyData),
                makeDispatchData(from: Data(pskIdentity.utf8))
            )

            let parameters = NWParameters(dtls: tlsOptions, udp: NWProtocolUDP.Options())
            parameters.allowLocalEndpointReuse = true

            let hostString = bridge.ipAddress.components(separatedBy: "%").first ?? bridge.ipAddress
            guard let port = NWEndpoint.Port(rawValue: 2100) else {
                state = .failed("Invalid entertainment stream port")
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(hostString),
                port: port,
                using: parameters
            )
            connection.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                self.sendQueue.async {
                    switch newState {
                    case .ready:
                        NSLog("HueEntertainmentEngine: DTLS ready")
                        self.state = .streaming
                        self.startKeepAliveTimer()
                    case .waiting(let error):
                        NSLog("HueEntertainmentEngine: DTLS waiting: %@", error.localizedDescription)
                    case .failed(let error):
                        NSLog("HueEntertainmentEngine: DTLS failed: %@", error.localizedDescription)
                        self.stopKeepAliveTimer()
                        self.connection?.cancel()
                        self.connection = nil
                        self.state = .failed("Entertainment transport failed: \(error.localizedDescription)")
                    case .cancelled:
                        NSLog("HueEntertainmentEngine: DTLS cancelled")
                        self.stopKeepAliveTimer()
                        self.connection = nil
                        if self.state != .idle {
                            self.state = .idle
                        }
                    default:
                        break
                    }
                }
            }

            self.connection = connection
            connection.start(queue: sendQueue)
        }
    }

    func stop() {
        runOnSendQueueSync {
            NSLog(
                "HueEntertainmentEngine: stop (sent=%llu throttled=%llu)",
                sentPacketCount,
                throttledFrameCount
            )
            stopKeepAliveTimer()
            connection?.cancel()
            connection = nil
            lastPacket = nil
            state = .idle
        }
    }

    func push(frame: HueLightshowFrame, channelByLightID: [String: UInt8]) {
        sendQueue.async { [weak self] in
            guard let self else { return }
            switch self.state {
            case .connecting, .streaming:
                break
            case .idle, .failed:
                return
            }
            guard let areaID = self.configuredAreaID else { return }
            guard let connection = self.connection else { return }

            let nowNanos = DispatchTime.now().uptimeNanoseconds
            let minIntervalNanos = UInt64(1_000_000_000 / max(1, self.targetFPS))
            if nowNanos - self.lastFrameSendNanos < minIntervalNanos {
                self.throttledFrameCount &+= 1
                return
            }

            guard let packet = self.packetBuilder.encode(
                frame,
                entertainmentAreaID: areaID,
                channelByLightID: channelByLightID,
                colorSpace: .xyb,
                sequenceNumber: self.sequenceNumber
            ) else {
                self.state = .failed("Entertainment packet encoding failed")
                return
            }

            self.sequenceNumber &+= 1
            self.lastFrameSendNanos = nowNanos
            self.lastPacket = packet
            connection.send(content: packet, completion: .contentProcessed({ [weak self] error in
                guard let self else { return }
                if let error {
                    self.sendQueue.async {
                        NSLog("HueEntertainmentEngine: send failed: %@", error.localizedDescription)
                        self.state = .failed("Entertainment send failed: \(error.localizedDescription)")
                    }
                } else {
                    self.sendQueue.async {
                        self.sentPacketCount &+= 1
                        let now = DispatchTime.now().uptimeNanoseconds
                        if now - self.lastStatsLogNanos >= 1_000_000_000 {
                            self.lastStatsLogNanos = now
                            NSLog(
                                "HueEntertainmentEngine: packets sent=%llu throttled=%llu seq=%u",
                                self.sentPacketCount,
                                self.throttledFrameCount,
                                self.sequenceNumber
                            )
                        }
                    }
                }
            }))
        }
    }

    private func startKeepAliveTimer() {
        stopKeepAliveTimer()
        let timer = DispatchSource.makeTimerSource(queue: sendQueue)
        timer.schedule(deadline: .now() + keepAliveInterval, repeating: keepAliveInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.state == .streaming else { return }
            guard let connection = self.connection else { return }
            guard let lastPacket = self.lastPacket else { return }
            connection.send(content: lastPacket, completion: .contentProcessed({ [weak self] error in
                guard let self else { return }
                if let error {
                    self.sendQueue.async {
                        self.state = .failed("Entertainment keepalive failed: \(error.localizedDescription)")
                    }
                }
            }))
        }
        keepAliveTimer = timer
        timer.resume()
    }

    private func stopKeepAliveTimer() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
    }

    private func decodeHex(_ value: String) -> Data? {
        let stripped = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.count % 2 == 0 else { return nil }
        var data = Data(capacity: stripped.count / 2)
        var index = stripped.startIndex
        while index < stripped.endIndex {
            let next = stripped.index(index, offsetBy: 2)
            guard let byte = UInt8(stripped[index..<next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        return data
    }

    private func makeDispatchData(from data: Data) -> dispatch_data_t {
        return data.withUnsafeBytes { buffer in
            DispatchData(bytes: buffer) as dispatch_data_t
        }
    }

    private func runOnSendQueueSync(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: sendQueueKey) != nil {
            work()
        } else {
            sendQueue.sync(execute: work)
        }
    }
}
