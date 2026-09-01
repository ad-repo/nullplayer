import CryptoKit
import Foundation

struct WMPPhase5Output: Sendable {
    let overrides: WMPSceneOverrides
    let hostCommands: [WMPJScriptHostCommand]
    let diagnostics: [WMPJScriptDiagnostic]
    let repaintNodeIDs: Set<Int>
    let timerRequests: [WMPJScriptTimerRequest]
}

final class WMPPreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    let namespace: String
    private let maximumCount: Int

    init(skinData: Data, defaults: UserDefaults = .standard, maximumCount: Int = 512) {
        namespace = SHA256.hash(data: skinData).map { String(format: "%02x", $0) }.joined()
        self.defaults = defaults
        self.maximumCount = maximumCount
    }

    private var key: String { "wmp.preferences.\(namespace)" }

    func values() -> [String: String] { defaults.dictionary(forKey: key) as? [String: String] ?? [:] }

    @discardableResult
    func apply(_ mutations: [WMPJScriptPreferenceMutation]) -> [WMPJScriptDiagnostic] {
        var values = values(), diagnostics: [WMPJScriptDiagnostic] = []
        for mutation in mutations.prefix(WMPJScriptProtocol.maximumPreferenceCount) {
            guard mutation.key.utf8.count <= 1_024 else {
                diagnostics.append(.init(code: "preference-key-too-large", message: String(mutation.key.prefix(80)) + "…")); continue
            }
            if let value = mutation.value {
                guard value.utf8.count <= WMPPhase0Limits.preferenceValueBytes else {
                    diagnostics.append(.init(code: "preference-value-too-large", message: mutation.key)); continue
                }
                guard values[mutation.key] != nil || values.count < maximumCount else {
                    diagnostics.append(.init(code: "preference-count-limit", message: "maximum \(maximumCount) values")); continue
                }
                values[mutation.key] = value
            } else { values.removeValue(forKey: mutation.key) }
        }
        defaults.set(values, forKey: key)
        return diagnostics
    }

    func reset() { defaults.removeObject(forKey: key) }
}

/// Phase 5 session state. The actor serializes transactions, but every evaluation is still a fresh,
/// killable helper process. A hard failure permanently disables script for this skin session.
actor WMPPhase5Session {
    private let runtime: WMPJScriptRuntime
    private let preferences: WMPPreferenceStore
    private(set) var scriptsDisabled = false
    private var emittedFailure = false
    private var propertyRegistry: WMPObservablePropertyRegistry?
    private var committedOverrides = WMPSceneOverrides.empty
    private var recentTransactionTimes: [Date] = []

    init(runtime: WMPJScriptRuntime, preferences: WMPPreferenceStore) {
        self.runtime = runtime
        self.preferences = preferences
    }

    func transact(skin: WMPLoadedSkin, viewID: String, size: WMPSize,
                  snapshot: WMPHostSnapshot, event: WMPJScriptEvent?) async -> WMPPhase5Output {
        guard !scriptsDisabled else { return emptyOutput() }
        let now = Date()
        recentTransactionTimes.removeAll { now.timeIntervalSince($0) >= 1 }
        guard recentTransactionTimes.count < WMPJScriptProtocol.maximumTransactionsPerSecond else {
            return WMPPhase5Output(overrides: committedOverrides, hostCommands: [],
                diagnostics: [.init(code: "script-rate-limit", message: "more than 120 transactions per second")],
                repaintNodeIDs: [], timerRequests: [])
        }
        recentTransactionTimes.append(now)
        let context = buildContext(skin: skin, viewID: viewID, size: size, snapshot: snapshot)
        if propertyRegistry == nil { propertyRegistry = WMPObservablePropertyRegistry(graph: skin.graph) }
        let probe = WMPJScriptBatch(registrations: context.registrations, scripts: [],
                                    expressions: context.expressions, host: context.host,
                                    preferences: preferences.values())
        let probeResult = await runtime.transact(probe)
        let orderedExpressions: [WMPJScriptExpression]
        var topologyDiagnostics: [WMPJScriptDiagnostic] = []
        switch probeResult {
        case let .failure(error): return fail(error)
        case let .success(transaction):
            switch topologicallySorted(context.expressions, results: transaction.expressions,
                                       knownIDs: Set(context.idToStableID.keys)) {
            case let .failure(diagnostics):
                orderedExpressions = []
                topologyDiagnostics = diagnostics
            case let .success(expressions): orderedExpressions = expressions
            }
        }

        let batch = WMPJScriptBatch(registrations: context.registrations,
            scripts: context.scripts, expressions: orderedExpressions, event: event,
            host: context.host, preferences: preferences.values())
        switch await runtime.transact(batch) {
        case let .failure(error): return fail(error)
        case let .success(transaction):
            var diagnostics = transaction.diagnostics
            diagnostics.append(contentsOf: topologyDiagnostics)
            diagnostics.append(contentsOf: preferences.apply(transaction.preferences))
            var overrides = committedOverrides
            for change in propertyRegistry?.changes(for: snapshot) ?? [] {
                overrides.properties[change.address] = change.value
            }
            for result in transaction.expressions {
                guard result.error == nil, let value = result.value?.number,
                      value.isFinite, let address = context.expressionAddresses[result.key] else {
                    if let error = result.error { diagnostics.append(.init(code: "expression-error", message: "\(result.key): \(error)")) }
                    continue
                }
                let geometry = CGFloat(value)
                if (address.property == "width" || address.property == "height") && geometry < 0 {
                    diagnostics.append(.init(code: "invalid-geometry", message: "\(result.key) is negative")); continue
                }
                overrides.geometry[address] = geometry
            }
            for mutation in transaction.mutations {
                guard let stableID = context.idToStableID[WMPPath.fold(mutation.targetID)] else { continue }
                let address = WMPScenePropertyAddress(stableID: stableID, property: mutation.property.lowercased())
                if ["left", "top", "width", "height"].contains(address.property), let value = mutation.value.number {
                    if value.isFinite && (!(address.property == "width" || address.property == "height") || value >= 0) {
                        overrides.geometry[address] = CGFloat(value)
                    }
                } else { overrides.properties[address] = mutation.value }
            }
            let repaint = Set(transaction.repaintHints.compactMap { context.idToStableID[WMPPath.fold($0)] })
            committedOverrides = overrides
            return WMPPhase5Output(overrides: overrides, hostCommands: transaction.hostCommands,
                                   diagnostics: diagnostics, repaintNodeIDs: repaint,
                                   timerRequests: transaction.timers)
        }
    }

    func resetPreferences() { preferences.reset() }
    func teardown() { scriptsDisabled = true }

    private struct Context {
        let registrations: [WMPJScriptRegistration]
        let expressions: [WMPJScriptExpression]
        let expressionAddresses: [String: WMPScenePropertyAddress]
        let scripts: [String]
        let host: [String: WMPJSONValue]
        let idToStableID: [String: Int]
    }

    private func buildContext(skin: WMPLoadedSkin, viewID: String, size: WMPSize,
                              snapshot: WMPHostSnapshot) -> Context {
        guard let view = skin.views.first(where: { $0.id.caseInsensitiveCompare(viewID) == .orderedSame })?.node else {
            return Context(registrations: [], expressions: [], expressionAddresses: [:], scripts: [], host: [:], idToStableID: [:])
        }
        var included = Set<Int>()
        func include(_ node: WMPNode) { included.insert(node.stableID); node.children.forEach(include) }
        include(view)
        var registrations: [WMPJScriptRegistration] = [], expressions: [WMPJScriptExpression] = []
        var addresses: [String: WMPScenePropertyAddress] = [:], ids: [String: Int] = [:]
        for node in skin.graph.allNodes where included.contains(node.stableID) {
            let id = node === view ? "view" : (node.xmlID ?? "node\(node.stableID)")
            ids[WMPPath.fold(id)] = node.stableID
            var properties: [String: WMPJSONValue] = [:]
            for attribute in node.attributes {
                let name = attribute.name.lowercased()
                switch attribute.value {
                case let .literal(raw): properties[name] = jsonScalar(raw)
                case let .color(color): properties[name] = .string(color.description)
                case let .jScript(source) where ["left", "top", "width", "height"].contains(name):
                    let key = "\(id).\(name)"; expressions.append(.init(key: key, source: source))
                    addresses[key] = .init(stableID: node.stableID, property: name)
                case let .binding(kind, source) where kind == .property && ["left", "top", "width", "height"].contains(name):
                    let key = "\(id).\(name)"; expressions.append(.init(key: key, source: source))
                    addresses[key] = .init(stableID: node.stableID, property: name)
                default: break
                }
            }
            if node === view { properties["width"] = .number(Double(size.width)); properties["height"] = .number(Double(size.height)); properties["left"] = .number(0); properties["top"] = .number(0) }
            registrations.append(.init(id: id, properties: properties))
        }
        let scripts = skin.scripts.compactMap(\.resolvedPath).compactMap { skin.scriptSources[$0] }
        let host: [String: WMPJSONValue] = [
            "state": .string(snapshot.state.rawValue), "currentTime": .number(snapshot.currentTime),
            "duration": .number(snapshot.duration), "elapsedText": .string(snapshot.elapsedText),
            "durationText": .string(snapshot.durationText), "volume": .number(snapshot.volume),
            "balance": .number(snapshot.balance), "muted": .bool(snapshot.muted),
            "shuffle": .bool(snapshot.shuffle), "repeatMode": .bool(snapshot.repeatMode),
            "title": .string(snapshot.metadata.title), "artist": .string(snapshot.metadata.artist),
            "album": .string(snapshot.metadata.album), "playlistCount": .number(Double(snapshot.playlistCount)),
            "playlistIndex": .number(Double(snapshot.playlistIndex)), "viewID": .string(viewID),
            "bufferingProgress": .number(snapshot.bufferingProgress),
            "receptionQuality": .number(snapshot.receptionQuality),
            "view": .string("registered")
        ]
        return Context(registrations: registrations, expressions: expressions,
                       expressionAddresses: addresses, scripts: scripts, host: host, idToStableID: ids)
    }

    private enum TopologyResult { case success([WMPJScriptExpression]), failure([WMPJScriptDiagnostic]) }

    private func topologicallySorted(_ expressions: [WMPJScriptExpression],
        results: [WMPJScriptExpressionResult], knownIDs: Set<String>)
        -> TopologyResult {
        let byKey = Dictionary(uniqueKeysWithValues: expressions.map { ($0.key.lowercased(), $0) })
        guard !byKey.isEmpty else { return .success([]) }
        let resultByKey = Dictionary(uniqueKeysWithValues: results.map { ($0.key.lowercased(), $0) })
        var dependencies: [String: Set<String>] = [:], diagnostics: [WMPJScriptDiagnostic] = []
        for expression in expressions {
            let key = expression.key.lowercased()
            guard let result = resultByKey[key] else { diagnostics.append(.init(code: "missing-expression-result", message: expression.key)); continue }
            if let error = result.error { diagnostics.append(.init(code: "expression-error", message: "\(expression.key): \(error)")) }
            var local = Set<String>()
            for dependency in result.dependencies {
                let folded = dependency.lowercased()
                let object = folded.split(separator: ".").dropLast().joined(separator: ".")
                if object != "player" && !object.hasPrefix("player.") && object != "preferences"
                    && !knownIDs.contains(WMPPath.fold(object)) {
                    diagnostics.append(.init(code: "missing-id", message: "\(expression.key) reads \(dependency)"))
                }
                if byKey[folded] != nil { local.insert(folded) }
            }
            dependencies[key] = local
        }
        guard diagnostics.isEmpty else { return .failure(diagnostics) }
        var ordered: [WMPJScriptExpression] = [], remaining = Set(byKey.keys)
        for _ in 0..<WMPPhase0Limits.expressionPasses {
            let ready = remaining.filter { dependencies[$0, default: []].isDisjoint(with: remaining) }.sorted()
            if ready.isEmpty { break }
            for key in ready { if let expression = byKey[key] { ordered.append(expression) }; remaining.remove(key) }
            if remaining.isEmpty { return .success(ordered) }
        }
        return .failure([.init(code: "dependency-cycle", message: remaining.sorted().joined(separator: ", "))])
    }

    private func jsonScalar(_ raw: String) -> WMPJSONValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("true") == .orderedSame { return .bool(true) }
        if trimmed.caseInsensitiveCompare("false") == .orderedSame { return .bool(false) }
        if let number = Double(trimmed), number.isFinite { return .number(number) }
        return .string(raw)
    }

    private func fail(_ error: WMPPhase0Diagnostic) -> WMPPhase5Output {
        scriptsDisabled = true
        let diagnostics = emittedFailure ? [] : [WMPJScriptDiagnostic(code: error.code.rawValue,
            message: "WMP script was disabled for this skin session: \(error.detail)")]
        emittedFailure = true
        return WMPPhase5Output(overrides: committedOverrides, hostCommands: [], diagnostics: diagnostics,
                               repaintNodeIDs: [], timerRequests: [])
    }

    private func emptyOutput() -> WMPPhase5Output {
        WMPPhase5Output(overrides: committedOverrides, hostCommands: [], diagnostics: [],
                        repaintNodeIDs: [], timerRequests: [])
    }
}

extension WMPJScriptRuntime {
    static func bundledHelperURL(bundle: Bundle = .main) -> URL {
        if let helpers = bundle.privateFrameworksURL?.deletingLastPathComponent().appendingPathComponent("Helpers/WMPScriptIsolationHelper"),
           FileManager.default.isExecutableFile(atPath: helpers.path) { return helpers }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/WMPScriptIsolationHelper")
    }
}
