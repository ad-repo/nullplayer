import Foundation

final class HueManager {
    static let shared = HueManager()

    private enum DefaultsKeys {
        static let selectedTargetID = "hue_selected_target_id"
        static let reactiveMode = "hue_reactive_mode"
        static let reactiveIntensity = "hue_reactive_intensity"
        static let reactiveSpeed = "hue_reactive_speed"
        static let sceneAssignments = "hue_scene_assignments_v1"
    }

    private let discoveryService = HueBridgeDiscoveryService()
    private let authService = HueAuthService()
    private let commandQueue = HueCommandQueue()
    private let reactiveEngine = HueReactiveEngine()

    private var pinnedSession: URLSession?
    private var eventStreamTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    private let eventStreamPaths = ["/eventstream/clip/v2", "/clip/v2/eventstream"]

    private(set) var connectionState: HueConnectionState = .disconnected {
        didSet {
            NotificationCenter.default.post(name: .hueConnectionStateDidChange, object: self)
            NotificationCenter.default.post(name: .hueStateDidChange, object: self)
        }
    }

    private(set) var diagnosticsMessage: String = "Hue idle"
    private(set) var discoveredBridges: [HueBridge] = []
    private(set) var targets: [HueTarget] = []
    private(set) var scenes: [HueScene] = []

    private(set) var currentBridge: HueBridge?
    private(set) var appKey: String?

    private var lightsByID: [String: OpenHueLightResource] = [:]
    private var groupedLightsByID: [String: OpenHueGroupedLightResource] = [:]
    private var devicesByID: [String: OpenHueDeviceResource] = [:]
    private var rooms: [OpenHueRoomResource] = []
    private var zones: [OpenHueZoneResource] = []
    private var rawScenes: [OpenHueSceneResource] = []
    private var assignedSceneIDsByTargetID: [String: [String]] = [:]

    private var groupedLightStateByID: [String: HueLightState] = [:]
    private var lightStateByID: [String: HueLightState] = [:]

    private(set) var selectedTargetID: String? {
        didSet {
            UserDefaults.standard.set(selectedTargetID, forKey: DefaultsKeys.selectedTargetID)
            NotificationCenter.default.post(name: .hueStateDidChange, object: self)
        }
    }

    private(set) var reactiveSettings: HueReactiveSettings {
        didSet {
            UserDefaults.standard.set(reactiveSettings.mode.rawValue, forKey: DefaultsKeys.reactiveMode)
            UserDefaults.standard.set(reactiveSettings.intensity, forKey: DefaultsKeys.reactiveIntensity)
            UserDefaults.standard.set(reactiveSettings.speed, forKey: DefaultsKeys.reactiveSpeed)
            NotificationCenter.default.post(name: .hueStateDidChange, object: self)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        selectedTargetID = defaults.string(forKey: DefaultsKeys.selectedTargetID)

        let storedMode = defaults.string(forKey: DefaultsKeys.reactiveMode)
            .flatMap(HueReactiveMode.init(rawValue:)) ?? .off
        let storedIntensity = defaults.object(forKey: DefaultsKeys.reactiveIntensity) as? Double ?? 0.6
        let storedSpeed = defaults.object(forKey: DefaultsKeys.reactiveSpeed) as? Double ?? 0.5
        reactiveSettings = HueReactiveSettings(
            mode: storedMode,
            intensity: max(0.1, min(1.0, storedIntensity)),
            speed: max(0.0, min(1.0, storedSpeed))
        )

        if let data = defaults.data(forKey: DefaultsKeys.sceneAssignments),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            assignedSceneIDsByTargetID = decoded
        }
    }

    var hasPairedBridge: Bool {
        authService.pairedBridgeID() != nil && authService.appKey() != nil
    }

    var isHueAvailable: Bool {
        hasPairedBridge
    }

    var selectedTarget: HueTarget? {
        guard let selectedTargetID else { return targets.first }
        return targets.first(where: { $0.id == selectedTargetID }) ?? targets.first
    }

    var filteredScenes: [HueScene] {
        let assigned = assignedScenesForSelectedTarget() ?? []
        guard let target = selectedTarget else { return scenes }
        guard let groupIDs = resolvedSceneGroupIDs(for: target), groupIDs.isEmpty == false else { return scenes }
        let autoFiltered = scenes.filter { scene in
            guard let groupID = scene.groupID else { return false }
            return groupIDs.contains(groupID)
        }
        NSLog(
            "HueManager: scene filter target=%@ type=%@ candidateGroups=%@ total=%d auto=%d assigned=%d",
            target.id,
            target.targetType.rawValue,
            groupIDs.sorted().joined(separator: ","),
            scenes.count,
            autoFiltered.count,
            assigned.count
        )
        if assigned.isEmpty == false {
            var merged: [HueScene] = assigned
            var seen = Set(assigned.map(\.id))
            for scene in autoFiltered where seen.contains(scene.id) == false {
                merged.append(scene)
                seen.insert(scene.id)
            }
            return merged
        }

        if autoFiltered.isEmpty {
            return scenes
        }
        return autoFiltered
    }

    var sceneCatalog: [HueScene] {
        scenes
    }

    var hasSceneAssignmentsForSelectedTarget: Bool {
        guard let targetID = selectedTarget?.id ?? selectedTargetID else { return false }
        return (assignedSceneIDsByTargetID[targetID]?.isEmpty == false)
    }

    func assignSceneToSelectedTarget(sceneID: String) {
        guard let targetID = selectedTarget?.id ?? selectedTargetID else {
            diagnosticsMessage = "Select a Hue target before assigning a scene"
            NotificationCenter.default.post(name: .hueStateDidChange, object: self)
            return
        }
        guard let scene = scenes.first(where: { $0.id == sceneID }) else {
            diagnosticsMessage = "Selected scene is not available from the Hue bridge"
            NotificationCenter.default.post(name: .hueStateDidChange, object: self)
            return
        }
        var ids = assignedSceneIDsByTargetID[targetID] ?? []
        if ids.contains(sceneID) == false {
            ids.append(sceneID)
            assignedSceneIDsByTargetID[targetID] = ids
            persistSceneAssignments()
            diagnosticsMessage = "Assigned scene '\(scene.name)' to \(targetID)"
            NotificationCenter.default.post(name: .hueStateDidChange, object: self)
        } else {
            diagnosticsMessage = "Scene '\(scene.name)' is already assigned to \(targetID)"
            NotificationCenter.default.post(name: .hueStateDidChange, object: self)
        }
    }

    func removeAssignedSceneFromSelectedTarget(sceneID: String) {
        guard let targetID = selectedTarget?.id ?? selectedTargetID else { return }
        guard var ids = assignedSceneIDsByTargetID[targetID] else { return }
        ids.removeAll { $0 == sceneID }
        if ids.isEmpty {
            assignedSceneIDsByTargetID.removeValue(forKey: targetID)
        } else {
            assignedSceneIDsByTargetID[targetID] = ids
        }
        persistSceneAssignments()
        NotificationCenter.default.post(name: .hueStateDidChange, object: self)
    }

    private func assignedScenesForSelectedTarget() -> [HueScene]? {
        guard let targetID = selectedTarget?.id ?? selectedTargetID,
              let assignedIDs = assignedSceneIDsByTargetID[targetID],
              assignedIDs.isEmpty == false else {
            return nil
        }

        let scenesByID = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0) })
        let resolved = assignedIDs.compactMap { scenesByID[$0] }

        if resolved.count != assignedIDs.count {
            assignedSceneIDsByTargetID[targetID] = resolved.map(\.id)
            persistSceneAssignments()
        }
        return resolved
    }

    private func isSceneAssignedToSelectedTarget(_ sceneID: String) -> Bool {
        guard let targetID = selectedTarget?.id ?? selectedTargetID,
              let assignedIDs = assignedSceneIDsByTargetID[targetID] else {
            return false
        }
        return assignedIDs.contains(sceneID)
    }

    private func applySceneToTarget(
        sceneID: String,
        to target: HueTarget,
        using client: OpenHueGeneratedClient
    ) async throws -> Bool {
        guard let scene = rawScenes.first(where: { $0.id == sceneID }) else {
            return false
        }
        guard let actions = scene.actions?.filter({ $0.action != nil }),
              actions.isEmpty == false else {
            NSLog("HueManager: scene %@ has no actions payload", sceneID)
            return false
        }

        let targetLightIDs = resolvedLightIDs(for: target)
        guard targetLightIDs.isEmpty == false else {
            NSLog("HueManager: scene %@ has no lights for target %@", sceneID, target.id)
            return false
        }

        let templates = actions.compactMap { action -> [String: Any]? in
            guard let lightAction = action.action else { return nil }
            return payload(from: lightAction)
        }
        guard templates.isEmpty == false else {
            NSLog("HueManager: scene %@ actions do not include mutable light state", sceneID)
            return false
        }

        let colorFallback = templates.first { template in
            template["color"] != nil
        }?["color"]
        let colorTemperatureFallback = templates.first { template in
            template["color_temperature"] != nil
        }?["color_temperature"]
        let dimmingFallback = templates.first { template in
            template["dimming"] != nil
        }?["dimming"]

        let enrichedTemplates = templates.map { template -> [String: Any] in
            var resolved = template
            if resolved["color"] == nil && resolved["color_temperature"] == nil {
                if let colorFallback {
                    resolved["color"] = colorFallback
                } else if let colorTemperatureFallback {
                    resolved["color_temperature"] = colorTemperatureFallback
                }
            }
            if resolved["dimming"] == nil, let dimmingFallback {
                resolved["dimming"] = dimmingFallback
            }
            return resolved
        }

        let colorTemplates = enrichedTemplates.filter { template in
            template["color"] != nil
        }
        let colorTemperatureTemplates = enrichedTemplates.filter { template in
            template["color"] == nil && template["color_temperature"] != nil
        }
        let nonChromaticTemplates = enrichedTemplates.filter { template in
            template["color"] == nil && template["color_temperature"] == nil
        }
        guard (colorTemplates.isEmpty && colorTemperatureTemplates.isEmpty && nonChromaticTemplates.isEmpty) == false else {
            return false
        }

        var colorIndex = 0
        var colorTemperatureIndex = 0
        var nonChromaticIndex = 0

        for lightID in targetLightIDs {
            let light = lightsByID[lightID]
            let prefersColor = light?.color != nil
            let prefersColorTemperature = light?.colorTemperature != nil

            let payload: [String: Any]
            if prefersColor && colorTemplates.isEmpty == false {
                payload = colorTemplates[colorIndex % colorTemplates.count]
                colorIndex += 1
            } else if prefersColorTemperature && colorTemperatureTemplates.isEmpty == false {
                payload = colorTemperatureTemplates[colorTemperatureIndex % colorTemperatureTemplates.count]
                colorTemperatureIndex += 1
            } else if colorTemplates.isEmpty == false {
                payload = colorTemplates[colorIndex % colorTemplates.count]
                colorIndex += 1
            } else if colorTemperatureTemplates.isEmpty == false {
                payload = colorTemperatureTemplates[colorTemperatureIndex % colorTemperatureTemplates.count]
                colorTemperatureIndex += 1
            } else {
                payload = nonChromaticTemplates[nonChromaticIndex % nonChromaticTemplates.count]
                nonChromaticIndex += 1
            }

            if payload.isEmpty { continue }
            try await client.setLight(id: lightID, payload: payload)
        }
        return true
    }

    private func persistSceneAssignments() {
        let data = try? JSONEncoder().encode(assignedSceneIDsByTargetID)
        UserDefaults.standard.set(data, forKey: DefaultsKeys.sceneAssignments)
    }

    func stateForSelectedTarget() -> HueLightState? {
        guard let target = selectedTarget else { return nil }
        return state(for: target)
    }

    func beginDiscovery() {
        NSLog("HueManager: beginDiscovery requested")
        discoveredBridges.removeAll()
        connectionState = .discovering
        diagnosticsMessage = "Discovering Hue bridges on your local network"
        NotificationCenter.default.post(name: .hueStateDidChange, object: self)

        discoveryService.discover { [weak self] bridges in
            guard let self else { return }
            NSLog("HueManager: discovery update received (%d bridge(s))", bridges.count)
            self.discoveredBridges = bridges
            if bridges.isEmpty {
                self.diagnosticsMessage = "No Hue bridge found yet"
            } else {
                self.diagnosticsMessage = "Found \(bridges.count) Hue bridge\(bridges.count == 1 ? "" : "s")"
            }
            NotificationCenter.default.post(name: .hueStateDidChange, object: self)
        }
    }

    func stopDiscovery() {
        discoveryService.stopDiscovery()
        if connectionState == .discovering {
            connectionState = .disconnected
            diagnosticsMessage = "Discovery stopped"
        }
    }

    func reconnectLastPairedBridgeIfAvailable() {
        guard let bridgeID = authService.pairedBridgeID(),
              let bridgeIP = authService.pairedBridgeIP(),
              let appKey = authService.appKey() else {
            return
        }

        let bridge = HueBridge(id: bridgeID.lowercased(), ipAddress: bridgeIP, name: "Hue Bridge", port: 443)
        self.appKey = appKey
        currentBridge = bridge
        pinnedSession = HueBridgeSessionFactory.makePinnedSession(expectedBridgeID: bridge.id)

        Task {
            await self.connectToCurrentBridge(refreshOnly: true)
        }
    }

    func pair(with bridge: HueBridge) {
        diagnosticsMessage = "Waiting for Hue Bridge link button"
        connectionState = .awaitingLinkButton
        NotificationCenter.default.post(name: .hueStateDidChange, object: self)

        let session = HueBridgeSessionFactory.makePinnedSession(expectedBridgeID: bridge.id)
        pinnedSession = session

        Task {
            do {
                let appKey = try await self.authService.pair(bridge: bridge, session: session)
                await MainActor.run {
                    self.authService.saveCredentials(appKey: appKey, bridge: bridge)
                    self.appKey = appKey
                    self.currentBridge = bridge
                }
                await self.connectToCurrentBridge(refreshOnly: false)
            } catch {
                NSLog("HueManager: pair failed for bridge %@: %@", bridge.id, error.localizedDescription)
                await MainActor.run {
                    self.connectionState = .error
                    self.diagnosticsMessage = error.localizedDescription
                    NotificationCenter.default.post(name: .hueStateDidChange, object: self)
                }
            }
        }
    }

    func retryConnection() {
        Task {
            await connectToCurrentBridge(refreshOnly: false)
        }
    }

    func forgetBridge() {
        authService.clearCredentials()
        disconnect()
        discoveredBridges.removeAll()
        diagnosticsMessage = "Hue bridge disconnected"
        NotificationCenter.default.post(name: .hueStateDidChange, object: self)
    }

    func disconnect() {
        stopDiscovery()
        eventStreamTask?.cancel()
        eventStreamTask = nil
        eventRefreshTask?.cancel()
        eventRefreshTask = nil
        Task {
            await commandQueue.cancelAll()
        }
        reactiveEngine.stop()
        currentBridge = nil
        appKey = nil
        pinnedSession?.invalidateAndCancel()
        pinnedSession = nil
        connectionState = .disconnected
        diagnosticsMessage = "Hue disconnected"
        NotificationCenter.default.post(name: .hueStateDidChange, object: self)
    }

    func selectTarget(id: String?) {
        selectedTargetID = id
    }

    func setPower(on: Bool) {
        guard let target = selectedTarget else { return }
        sendStateCommand(for: target, dedupeKey: "power", isSliderLike: false) { client, id, type in
            let payload = ["on": ["on": on]]
            switch type {
            case .light:
                try await client.setLight(id: id, payload: payload)
            default:
                try await client.setGroupedLight(id: id, payload: payload)
            }
        }
    }

    func setBrightness(_ brightnessPercent: Double) {
        guard let target = selectedTarget else { return }
        let clamped = max(1, min(100, brightnessPercent))
        sendStateCommand(for: target, dedupeKey: "brightness", isSliderLike: true) { client, id, type in
            let payload = ["dimming": ["brightness": clamped]]
            switch type {
            case .light:
                try await client.setLight(id: id, payload: payload)
            default:
                try await client.setGroupedLight(id: id, payload: payload)
            }
        }
    }

    func setColorTemperature(mirek: Int) {
        guard let target = selectedTarget else { return }
        let clamped = max(153, min(500, mirek))
        sendStateCommand(for: target, dedupeKey: "mirek", isSliderLike: true) { client, id, type in
            let payload = ["color_temperature": ["mirek": clamped]]
            switch type {
            case .light:
                try await client.setLight(id: id, payload: payload)
            default:
                try await client.setGroupedLight(id: id, payload: payload)
            }
        }
    }

    func setColor(x: Double, y: Double) {
        guard let target = selectedTarget else { return }
        let clampedX = max(0, min(1, x))
        let clampedY = max(0, min(1, y))
        sendStateCommand(for: target, dedupeKey: "xy", isSliderLike: true) { client, id, type in
            let payload: [String: Any] = [
                "color": ["xy": ["x": clampedX, "y": clampedY]]
            ]
            switch type {
            case .light:
                try await client.setLight(id: id, payload: payload)
            default:
                try await client.setGroupedLight(id: id, payload: payload)
            }
        }
    }

    func activateScene(_ sceneID: String) {
        guard let client = buildClient() else { return }
        Task {
            do {
                guard let target = selectedTarget else {
                    await MainActor.run {
                        self.diagnosticsMessage = "Select a room before applying a scene"
                        NotificationCenter.default.post(name: .hueStateDidChange, object: self)
                    }
                    return
                }
                guard target.targetType == .room else {
                    await MainActor.run {
                        self.diagnosticsMessage = "Scene application requires a room target"
                        NotificationCenter.default.post(name: .hueStateDidChange, object: self)
                    }
                    return
                }

                if try await applySceneToTarget(sceneID: sceneID, to: target, using: client) {
                    NSLog("HueManager: applied scene %@ to room %@", sceneID, target.id)
                } else {
                    await MainActor.run {
                        self.diagnosticsMessage = "Unable to apply this scene to the selected room"
                        NotificationCenter.default.post(name: .hueStateDidChange, object: self)
                    }
                    return
                }

                await self.refreshResources(reason: "Scene activated")
            } catch {
                NSLog("HueManager: activateScene failed for %@: %@", sceneID, error.localizedDescription)
                await MainActor.run {
                    self.connectionState = .error
                    self.diagnosticsMessage = error.localizedDescription
                    NotificationCenter.default.post(name: .hueStateDidChange, object: self)
                }
            }
        }
    }

    func setReactiveMode(_ mode: HueReactiveMode) {
        reactiveSettings.mode = mode
        updateReactiveEngineState()
    }

    func setReactiveIntensity(_ intensity: Double) {
        reactiveSettings.intensity = max(0.1, min(1.0, intensity))
        reactiveEngine.updateSettings(reactiveSettings)
    }

    func setReactiveSpeed(_ speed: Double) {
        reactiveSettings.speed = max(0.0, min(1.0, speed))
        reactiveEngine.updateSettings(reactiveSettings)
    }

    // MARK: - Internal connection/state

    private func connectToCurrentBridge(refreshOnly: Bool) async {
        guard currentBridge != nil else {
            NSLog("HueManager: connect requested but no current bridge is set")
            connectionState = .error
            diagnosticsMessage = "No Hue bridge selected"
            return
        }

        if appKey == nil {
            appKey = authService.appKey()
        }
        guard appKey != nil else {
            NSLog("HueManager: connect requested without app key (bridge not paired yet)")
            connectionState = .awaitingLinkButton
            diagnosticsMessage = "Hue bridge is not paired"
            return
        }

        await refreshResources(reason: "Connected to Hue bridge")
        if connectionState == .connected {
            startEventStreamIfNeeded()
            if refreshOnly == false {
                updateReactiveEngineState()
            }
        }
    }

    private func refreshResources(reason: String) async {
        guard let client = buildClient() else { return }

        do {
            async let lightsTask = client.getLights()
            async let groupedTask = client.getGroupedLights()
            async let devicesTask = client.getDevices()
            async let roomsTask = client.getRooms()
            async let zonesTask = client.getZones()
            async let scenesTask = client.getScenes()

            let lights = try await lightsTask
            let grouped = try await groupedTask
            let devices = try await devicesTask
            let rooms = try await roomsTask
            let zones = try await zonesTask
            let scenes = try await scenesTask

            await MainActor.run {
                self.lightsByID = Dictionary(uniqueKeysWithValues: lights.map { ($0.id, $0) })
                self.groupedLightsByID = Dictionary(uniqueKeysWithValues: grouped.map { ($0.id, $0) })
                self.devicesByID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
                self.rooms = rooms
                self.zones = zones
                self.rawScenes = scenes
                self.groupedLightStateByID = Dictionary(uniqueKeysWithValues: grouped.map { ($0.id, Self.lightState(from: $0)) })
                self.lightStateByID = Dictionary(uniqueKeysWithValues: lights.map { ($0.id, Self.lightState(from: $0)) })
                self.rebuildTargetsAndScenes()
                self.connectionState = .connected
                self.diagnosticsMessage = reason
                NotificationCenter.default.post(name: .hueStateDidChange, object: self)
            }
        } catch {
            NSLog("HueManager: refreshResources failed (%@): %@", reason, error.localizedDescription)
            await MainActor.run {
                self.connectionState = .error
                self.diagnosticsMessage = error.localizedDescription
                NotificationCenter.default.post(name: .hueStateDidChange, object: self)
            }
        }
    }

    private func rebuildTargetsAndScenes() {
        var rebuiltTargets: [HueTarget] = []

        let lightCapabilities: [String: HueCapabilityFlags] = Dictionary(uniqueKeysWithValues: lightsByID.values.map { light in
            (
                light.id,
                HueCapabilityFlags(
                    supportsColor: light.color != nil,
                    supportsColorTemperature: light.colorTemperature != nil,
                    supportsDimming: light.dimming != nil
                )
            )
        })

        let roomTargets = rooms.map { room -> HueTarget in
            let groupedID = room.services?.first(where: { $0.rtype == "grouped_light" })?.rid
            let childLightIDs = (room.children ?? []).filter { $0.rtype == "light" }.map { $0.rid }
            let caps = aggregateCapabilities(lightIDs: childLightIDs, fallbackGroupedID: groupedID, map: lightCapabilities)
            return HueTarget(
                id: "room:\(room.id)",
                name: room.metadata?.name ?? "Room",
                targetType: .room,
                groupedLightID: groupedID,
                lightID: nil,
                capabilities: caps
            )
        }

        let zoneTargets = zones.map { zone -> HueTarget in
            let groupedID = zone.services?.first(where: { $0.rtype == "grouped_light" })?.rid
            let childLightIDs = (zone.children ?? []).filter { $0.rtype == "light" }.map { $0.rid }
            let caps = aggregateCapabilities(lightIDs: childLightIDs, fallbackGroupedID: groupedID, map: lightCapabilities)
            return HueTarget(
                id: "zone:\(zone.id)",
                name: zone.metadata?.name ?? "Zone",
                targetType: .zone,
                groupedLightID: groupedID,
                lightID: nil,
                capabilities: caps
            )
        }

        let groupedTargets = groupedLightsByID.values.map { grouped in
            HueTarget(
                id: "grouped:\(grouped.id)",
                name: "Grouped Light \(grouped.id.prefix(6))",
                targetType: .groupedLight,
                groupedLightID: grouped.id,
                lightID: nil,
                capabilities: HueCapabilityFlags(
                    supportsColor: true,
                    supportsColorTemperature: true,
                    supportsDimming: grouped.dimming != nil
                )
            )
        }

        let lightTargets = lightsByID.values.map { light in
            HueTarget(
                id: "light:\(light.id)",
                name: light.metadata?.name ?? "Light",
                targetType: .light,
                groupedLightID: nil,
                lightID: light.id,
                capabilities: lightCapabilities[light.id] ?? .empty
            )
        }

        rebuiltTargets.append(contentsOf: roomTargets)
        rebuiltTargets.append(contentsOf: zoneTargets)
        rebuiltTargets.append(contentsOf: groupedTargets)
        rebuiltTargets.append(contentsOf: lightTargets)

        rebuiltTargets.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        targets = rebuiltTargets
        if let selectedTargetID,
           rebuiltTargets.contains(where: { $0.id == selectedTargetID }) == false {
            self.selectedTargetID = rebuiltTargets.first?.id
        } else if self.selectedTargetID == nil {
            self.selectedTargetID = rebuiltTargets.first?.id
        }

        scenes = rawScenes.map {
            HueScene(
                id: $0.id,
                name: $0.metadata?.name ?? "Scene",
                groupID: $0.group?.rid,
                groupType: $0.group?.rtype
            )
        }.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func aggregateCapabilities(
        lightIDs: [String],
        fallbackGroupedID: String?,
        map: [String: HueCapabilityFlags]
    ) -> HueCapabilityFlags {
        var supportsColor = false
        var supportsColorTemperature = false
        var supportsDimming = false

        for lightID in lightIDs {
            guard let caps = map[lightID] else { continue }
            supportsColor = supportsColor || caps.supportsColor
            supportsColorTemperature = supportsColorTemperature || caps.supportsColorTemperature
            supportsDimming = supportsDimming || caps.supportsDimming
        }

        if supportsDimming == false,
           let fallbackGroupedID,
           groupedLightsByID[fallbackGroupedID]?.dimming != nil {
            supportsDimming = true
        }

        return HueCapabilityFlags(
            supportsColor: supportsColor,
            supportsColorTemperature: supportsColorTemperature,
            supportsDimming: supportsDimming
        )
    }

    private func updateReactiveEngineState() {
        guard connectionState == .connected else {
            reactiveEngine.stop()
            return
        }

        guard reactiveSettings.mode == .groupFallback else {
            reactiveEngine.stop()
            return
        }

        guard selectedTarget != nil else {
            reactiveEngine.stop()
            return
        }

        reactiveEngine.start(audioEngine: WindowManager.shared.audioEngine, settings: reactiveSettings) { [weak self] output in
            self?.applyReactiveOutput(output)
        }
        diagnosticsMessage = "Reactive mode enabled"
        NotificationCenter.default.post(name: .hueStateDidChange, object: self)
    }

    private func applyReactiveOutput(_ output: HueReactiveOutput) {
        guard let target = selectedTarget else { return }
        let brightnessPercent = output.brightness * 100.0

        sendStateCommand(for: target, dedupeKey: "reactive", isSliderLike: false) { client, id, type in
            let payload: [String: Any] = [
                "dimming": ["brightness": brightnessPercent],
                "color_temperature": ["mirek": output.mirek],
                "color": ["xy": ["x": output.xy.x, "y": output.xy.y]]
            ]
            switch type {
            case .light:
                try await client.setLight(id: id, payload: payload)
            default:
                try await client.setGroupedLight(id: id, payload: payload)
            }
        }
    }

    private func sendStateCommand(
        for target: HueTarget,
        dedupeKey: String,
        isSliderLike: Bool,
        perform: @escaping (OpenHueGeneratedClient, String, HueControlTarget) async throws -> Void
    ) {
        guard let client = buildClient() else { return }
        guard let commandID = resolvedCommandResourceID(for: target) else { return }
        let type = target.targetType

        Task {
            await commandQueue.enqueue(
                .init(
                    dedupeKey: "\(target.id):\(dedupeKey)",
                    targetID: commandID,
                    isSliderLike: isSliderLike,
                    execute: {
                        try await perform(client, commandID, type)
                    }
                )
            )
        }
    }

    private func resolvedCommandResourceID(for target: HueTarget) -> String? {
        switch target.targetType {
        case .light:
            return target.lightID
        case .room, .zone, .groupedLight:
            return target.groupedLightID
        }
    }

    private func resolvedGroupedLightID(for target: HueTarget) -> String? {
        switch target.targetType {
        case .light:
            return nil
        case .room, .zone, .groupedLight:
            return target.groupedLightID
        }
    }

    private func resolvedSceneGroupIDs(for target: HueTarget) -> Set<String>? {
        switch target.targetType {
        case .room:
            guard target.id.hasPrefix("room:") else { return nil }
            let roomID = String(target.id.dropFirst(5))
            var result: Set<String> = [roomID]
            let roomLightIDs = lightIDsForRoom(id: roomID)
            if roomLightIDs.isEmpty == false {
                result.formUnion(zoneIDs(containingAny: roomLightIDs))
            }
            return result
        case .zone:
            guard target.id.hasPrefix("zone:") else { return nil }
            let zoneID = String(target.id.dropFirst(5))
            var result: Set<String> = [zoneID]
            let zoneLightIDs = lightIDsForZone(id: zoneID)
            if zoneLightIDs.isEmpty == false {
                result.formUnion(roomIDs(containingAny: zoneLightIDs))
            }
            return result
        case .groupedLight:
            guard let groupedID = target.groupedLightID else { return nil }
            var result = Set<String>()
            for room in rooms where room.services?.contains(where: { $0.rtype == "grouped_light" && $0.rid == groupedID }) == true {
                result.insert(room.id)
                result.formUnion(zoneIDs(containingAny: lightIDs(in: room)))
            }
            for zone in zones where zone.services?.contains(where: { $0.rtype == "grouped_light" && $0.rid == groupedID }) == true {
                result.insert(zone.id)
                result.formUnion(roomIDs(containingAny: lightIDs(in: zone)))
            }
            return result
        case .light:
            guard let lightID = target.lightID else { return nil }
            var result = Set<String>()
            for room in rooms where room.children?.contains(where: { $0.rtype == "light" && $0.rid == lightID }) == true {
                result.insert(room.id)
            }
            for zone in zones where zone.children?.contains(where: { $0.rtype == "light" && $0.rid == lightID }) == true {
                result.insert(zone.id)
            }
            return result
        }
    }

    private func lightIDsForRoom(id roomID: String) -> Set<String> {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return [] }
        return lightIDs(in: room)
    }

    private func lightIDsForZone(id zoneID: String) -> Set<String> {
        guard let zone = zones.first(where: { $0.id == zoneID }) else { return [] }
        return lightIDs(in: zone)
    }

    private func roomIDs(containingAny candidateLightIDs: Set<String>) -> Set<String> {
        guard candidateLightIDs.isEmpty == false else { return [] }
        var result = Set<String>()
        for room in rooms {
            if lightIDs(in: room).isDisjoint(with: candidateLightIDs) == false {
                result.insert(room.id)
            }
        }
        return result
    }

    private func zoneIDs(containingAny candidateLightIDs: Set<String>) -> Set<String> {
        guard candidateLightIDs.isEmpty == false else { return [] }
        var result = Set<String>()
        for zone in zones {
            if lightIDs(in: zone).isDisjoint(with: candidateLightIDs) == false {
                result.insert(zone.id)
            }
        }
        return result
    }

    private func lightIDs(in room: OpenHueRoomResource) -> Set<String> {
        lightIDs(from: room.children ?? [])
    }

    private func lightIDs(in zone: OpenHueZoneResource) -> Set<String> {
        lightIDs(from: zone.children ?? [])
    }

    private func lightIDs(from children: [OpenHueResourceIdentifier]) -> Set<String> {
        var result = Set<String>()
        for child in children {
            switch child.rtype {
            case "light":
                result.insert(child.rid)
            case "device":
                guard let device = devicesByID[child.rid] else { continue }
                for service in device.services ?? [] where service.rtype == "light" {
                    result.insert(service.rid)
                }
            default:
                continue
            }
        }
        return result
    }

    private func resolvedLightIDs(for target: HueTarget) -> [String] {
        switch target.targetType {
        case .light:
            guard let lightID = target.lightID else { return [] }
            return [lightID]
        case .room:
            guard target.id.hasPrefix("room:") else { return [] }
            let roomID = String(target.id.dropFirst(5))
            return Array(lightIDsForRoom(id: roomID)).sorted()
        case .zone:
            guard target.id.hasPrefix("zone:") else { return [] }
            let zoneID = String(target.id.dropFirst(5))
            return Array(lightIDsForZone(id: zoneID)).sorted()
        case .groupedLight:
            guard let groupedID = target.groupedLightID else { return [] }
            var ids = Set<String>()
            for room in rooms where room.services?.contains(where: { $0.rtype == "grouped_light" && $0.rid == groupedID }) == true {
                ids.formUnion(lightIDs(in: room))
            }
            for zone in zones where zone.services?.contains(where: { $0.rtype == "grouped_light" && $0.rid == groupedID }) == true {
                ids.formUnion(lightIDs(in: zone))
            }
            return Array(ids).sorted()
        }
    }

    private func payload(from action: OpenHueLightAction) -> [String: Any] {
        var payload: [String: Any] = [:]

        if let on = action.on?.on {
            payload["on"] = ["on": on]
        }
        if let brightness = action.dimming?.brightness {
            payload["dimming"] = ["brightness": max(1.0, min(100.0, brightness))]
        }
        if let mirek = action.colorTemperature?.mirek {
            payload["color_temperature"] = ["mirek": max(153, min(500, mirek))]
        }
        if let xy = action.color?.xy,
           let x = xy.x,
           let y = xy.y {
            payload["color"] = [
                "xy": [
                    "x": max(0, min(1, x)),
                    "y": max(0, min(1, y))
                ]
            ]
        }

        return payload
    }

    private func state(for target: HueTarget) -> HueLightState? {
        switch target.targetType {
        case .light:
            guard let lightID = target.lightID else { return nil }
            return lightStateByID[lightID]
        case .room, .zone, .groupedLight:
            guard let groupedID = target.groupedLightID else { return nil }
            return groupedLightStateByID[groupedID]
        }
    }

    private func buildClient() -> OpenHueGeneratedClient? {
        guard let bridge = currentBridge else {
            NSLog("HueManager: buildClient failed (missing current bridge)")
            return nil
        }
        guard let appKey = appKey ?? authService.appKey() else {
            NSLog("HueManager: buildClient failed (missing app key)")
            return nil
        }

        if pinnedSession == nil {
            pinnedSession = HueBridgeSessionFactory.makePinnedSession(expectedBridgeID: bridge.id)
        }
        guard let pinnedSession else {
            NSLog("HueManager: buildClient failed (missing pinned session)")
            return nil
        }

        return OpenHueGeneratedClient(bridge: bridge, appKey: appKey, session: pinnedSession)
    }

    private func startEventStreamIfNeeded() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task { [weak self] in
            await self?.runEventStreamLoop()
        }
    }

    private func runEventStreamLoop() async {
        var failures = 0
        while Task.isCancelled == false {
            do {
                try await consumeEventStream()
                failures = 0
            } catch {
                failures += 1
                NSLog(
                    "HueManager: event stream failure #%d: %@",
                    failures,
                    error.localizedDescription
                )
                if case HueClientError.httpStatus(let statusCode) = error,
                   (400...499).contains(statusCode) {
                    await MainActor.run {
                        self.diagnosticsMessage = "Hue event stream unavailable (HTTP \(statusCode)); continuing without stream"
                        NotificationCenter.default.post(name: .hueStateDidChange, object: self)
                    }
                    NSLog("HueManager: disabling event stream loop after HTTP %d", statusCode)
                    return
                }
                let delay: TimeInterval
                if failures == 1 {
                    delay = 2
                } else {
                    delay = min(30, pow(2, Double(failures - 1)))
                }

                await MainActor.run {
                    self.diagnosticsMessage = "Hue event stream reconnecting in \(Int(delay))s"
                    NotificationCenter.default.post(name: .hueStateDidChange, object: self)
                }

                let ns = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    private func consumeEventStream() async throws {
        guard let bridge = currentBridge,
              let appKey = appKey,
              let session = pinnedSession else {
            throw HueAuthError.missingCredentials
        }
        var lastError: Error = HueClientError.invalidResponse

        for path in eventStreamPaths {
            guard let url = URL(string: "\(bridge.baseURLString)\(path)") else {
                lastError = HueClientError.invalidBridgeURL
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue(appKey, forHTTPHeaderField: "hue-application-key")

            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    NSLog("HueManager: event stream %@ returned non-HTTP response", path)
                    lastError = HueClientError.invalidResponse
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    NSLog("HueManager: event stream %@ returned HTTP %d", path, http.statusCode)
                    lastError = HueClientError.httpStatus(http.statusCode)
                    continue
                }

                for try await line in bytes.lines {
                    if Task.isCancelled {
                        return
                    }
                    guard line.hasPrefix("data:") else { continue }
                    scheduleRefreshAfterEvent()
                }
                return
            } catch {
                if (error as NSError).domain == NSURLErrorDomain &&
                    (error as NSError).code == NSURLErrorCancelled {
                    throw error
                }
                NSLog("HueManager: event stream %@ transport error: %@", path, error.localizedDescription)
                lastError = error
            }
        }

        throw lastError
    }

    private func scheduleRefreshAfterEvent() {
        if eventRefreshTask != nil {
            return
        }

        eventRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self.refreshResources(reason: "Hue state updated")
            await MainActor.run {
                self.eventRefreshTask = nil
            }
        }
    }

    private static func lightState(from grouped: OpenHueGroupedLightResource) -> HueLightState {
        HueLightState(
            isOn: grouped.on?.on ?? false,
            brightness: grouped.dimming?.brightness,
            mirek: nil,
            colorXY: nil
        )
    }

    private static func lightState(from light: OpenHueLightResource) -> HueLightState {
        HueLightState(
            isOn: light.on?.on ?? false,
            brightness: light.dimming?.brightness,
            mirek: light.colorTemperature?.mirek,
            colorXY: {
                guard let xy = light.color?.xy,
                      let x = xy.x,
                      let y = xy.y else {
                    return nil
                }
                return (x: x, y: y)
            }()
        )
    }
}
