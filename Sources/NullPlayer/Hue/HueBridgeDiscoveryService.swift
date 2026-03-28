import Foundation
import Network

final class HueBridgeDiscoveryService {
    private var browser: NWBrowser?
    private var onUpdate: (([HueBridge]) -> Void)?
    private var discovered = [String: HueBridge]()
    private let queue = DispatchQueue.main
    private var noResultsWorkItem: DispatchWorkItem?
    private var cloudFallbackTask: Task<Void, Never>?
    private var discoveryToken: UUID?

    func discover(onUpdate: @escaping ([HueBridge]) -> Void) {
        stopDiscovery()
        self.onUpdate = onUpdate
        discovered.removeAll()
        let token = UUID()
        discoveryToken = token

        NSLog("HueBridgeDiscoveryService: starting discovery")
        publish()

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_hue._tcp", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: descriptor, using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            NSLog(
                "HueBridgeDiscoveryService: browse results changed (%d results, %d changes)",
                results.count,
                changes.count
            )
            for change in changes {
                switch change {
                case .added(let result):
                    NSLog("HueBridgeDiscoveryService: service added: %@", String(describing: result.endpoint))
                case .removed(let result):
                    NSLog("HueBridgeDiscoveryService: service removed: %@", String(describing: result.endpoint))
                case .changed(let old, let new, _):
                    NSLog(
                        "HueBridgeDiscoveryService: service changed: %@ -> %@",
                        String(describing: old.endpoint),
                        String(describing: new.endpoint)
                    )
                case .identical:
                    break
                @unknown default:
                    break
                }
            }
            self.handleBrowseResults(results)
        }

        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .setup:
                NSLog("HueBridgeDiscoveryService: browser setup")
            case .ready:
                NSLog("HueBridgeDiscoveryService: browser ready")
            case .waiting(let error):
                NSLog("HueBridgeDiscoveryService: browser waiting: %@", error.localizedDescription)
                self?.scheduleCloudFallback(after: 0.5, token: token)
            case .failed(let error):
                NSLog("HueBridgeDiscoveryService: browser failed: %@", error.localizedDescription)
                self?.scheduleCloudFallback(after: 0.1, token: token)
            case .cancelled:
                NSLog("HueBridgeDiscoveryService: browser cancelled")
                self?.browser = nil
            @unknown default:
                break
            }
        }

        browser?.start(queue: queue)
        scheduleNoResultsTimeout(token: token)
        scheduleCloudFallback(after: 2.0, token: token)
    }

    func stopDiscovery() {
        noResultsWorkItem?.cancel()
        noResultsWorkItem = nil
        cloudFallbackTask?.cancel()
        cloudFallbackTask = nil
        discoveryToken = nil
        browser?.cancel()
        browser = nil
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard !results.isEmpty else {
            NSLog("HueBridgeDiscoveryService: no bonjour results yet")
            publish()
            return
        }

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            resolve(result: result, serviceName: name)
        }
    }

    private func resolve(result: NWBrowser.Result, serviceName: String) {
        NSLog("HueBridgeDiscoveryService: resolving service %@", serviceName)

        let connectionParams = NWParameters.tcp
        connectionParams.includePeerToPeer = true
        let connection = NWConnection(to: result.endpoint, using: connectionParams)
        var done = false

        let finish: (HueBridge?, String) -> Void = { [weak self] bridge, reason in
            guard let self else { return }
            guard !done else { return }
            done = true
            connection.cancel()

            if let bridge {
                NSLog(
                    "HueBridgeDiscoveryService: resolved %@ to %@:%d (id: %@)",
                    serviceName,
                    bridge.ipAddress,
                    bridge.port,
                    bridge.id
                )
                self.discovered[bridge.id] = bridge
                self.publish()
            } else {
                NSLog("HueBridgeDiscoveryService: resolve failed for %@ (%@)", serviceName, reason)
            }
        }

        connection.stateUpdateHandler = { [weak self] state in
            guard self != nil else { return }
            switch state {
            case .preparing:
                NSLog("HueBridgeDiscoveryService: connection preparing for %@", serviceName)
            case .ready:
                let metadataBridgeID = self?.bridgeID(from: result.metadata)
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = endpoint {
                    let ip = Self.hostString(host)
                    guard !ip.isEmpty else {
                        finish(nil, "empty host string")
                        return
                    }
                    let bridgeID = metadataBridgeID ?? self?.bridgeIDFromName(serviceName) ?? "hue-\(ip)"
                    finish(
                        HueBridge(id: bridgeID, ipAddress: ip, name: serviceName, port: Int(port.rawValue)),
                        "ready"
                    )
                } else {
                    finish(nil, "missing remote endpoint")
                }
            case .waiting(let error):
                NSLog(
                    "HueBridgeDiscoveryService: connection waiting for %@: %@",
                    serviceName,
                    error.localizedDescription
                )
            case .failed(let error):
                finish(nil, "connection failed: \(error.localizedDescription)")
            case .cancelled:
                finish(nil, "connection cancelled")
            default:
                break
            }
        }

        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 3) {
            finish(nil, "connection timeout")
        }
    }

    private func bridgeID(from metadata: NWBrowser.Result.Metadata?) -> String? {
        guard case .bonjour(let txt)? = metadata else { return nil }
        if let value = txt["bridgeid"], !value.isEmpty {
            return value.lowercased()
        }
        if let value = txt["id"], !value.isEmpty {
            return value.lowercased()
        }
        return nil
    }

    private func bridgeIDFromName(_ name: String) -> String {
        name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .lowercased()
    }

    private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let ip): return "\(ip)"
        case .ipv6(let ip): return "\(ip)"
        case .name(let name, _): return name
        @unknown default: return ""
        }
    }

    private func publish() {
        let sorted = discovered.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        if sorted.isEmpty {
            NSLog("HueBridgeDiscoveryService: publishing 0 bridges")
        } else {
            NSLog("HueBridgeDiscoveryService: publishing %d bridge(s)", sorted.count)
            noResultsWorkItem?.cancel()
            noResultsWorkItem = nil
        }
        onUpdate?(sorted)
    }

    private func scheduleNoResultsTimeout(token: UUID) {
        noResultsWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.discoveryToken == token else { return }
            guard self.discovered.isEmpty else { return }
            NSLog("HueBridgeDiscoveryService: no bridges discovered after timeout")
            self.publish()
        }
        noResultsWorkItem = work
        queue.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func scheduleCloudFallback(after delaySeconds: TimeInterval, token: UUID) {
        cloudFallbackTask?.cancel()
        cloudFallbackTask = Task { [weak self] in
            guard let self else { return }
            if delaySeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self.discoverViaCloudFallback(token: token)
        }
    }

    private func discoverViaCloudFallback(token: UUID) async {
        guard discoveryToken == token else { return }
        guard let url = URL(string: "https://discovery.meethue.com/") else { return }
        NSLog("HueBridgeDiscoveryService: attempting cloud discovery fallback")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                NSLog("HueBridgeDiscoveryService: cloud discovery fallback returned non-2xx")
                return
            }

            let bridges = try JSONDecoder().decode([OpenHueDiscoveryBridge].self, from: data)
            await MainActor.run {
                guard self.discoveryToken == token else { return }
                for bridge in bridges {
                    let hueBridge = HueBridge(
                        id: bridge.id.lowercased(),
                        ipAddress: bridge.internalipaddress,
                        name: "Hue Bridge",
                        port: bridge.port ?? 443
                    )
                    if let existingKey = self.discovered.keys.first(where: { Self.bridgeIDsLikelyMatch($0, hueBridge.id) }) {
                        let existing = self.discovered[existingKey]
                        self.discovered.removeValue(forKey: existingKey)
                        let merged = HueBridge(
                            id: hueBridge.id,
                            ipAddress: hueBridge.ipAddress,
                            name: existing?.name ?? hueBridge.name,
                            port: hueBridge.port
                        )
                        self.discovered[merged.id] = merged
                    } else {
                        self.discovered[hueBridge.id] = hueBridge
                    }
                }
                NSLog("HueBridgeDiscoveryService: cloud fallback returned %d bridge(s)", bridges.count)
                self.publish()
            }
        } catch {
            NSLog("HueBridgeDiscoveryService: cloud discovery fallback failed: %@", error.localizedDescription)
            await MainActor.run {
                guard self.discoveryToken == token else { return }
                self.publish()
            }
        }
    }

    private static func bridgeIDsLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.caseInsensitiveCompare(rhs) == .orderedSame {
            return true
        }
        guard let leftSuffix = bridgeIDHexSuffix(lhs),
              let rightSuffix = bridgeIDHexSuffix(rhs) else {
            return false
        }
        return leftSuffix == rightSuffix
    }

    private static func bridgeIDHexSuffix(_ value: String) -> String? {
        var run = ""
        var best = ""

        for char in value.lowercased() {
            if char.isASCII && (char.isNumber || (char >= "a" && char <= "f")) {
                run.append(char)
            } else {
                if run.count >= 6 {
                    best = run
                }
                run.removeAll(keepingCapacity: true)
            }
        }
        if run.count >= 6 {
            best = run
        }

        guard !best.isEmpty else { return nil }
        return String(best.suffix(6))
    }
}
