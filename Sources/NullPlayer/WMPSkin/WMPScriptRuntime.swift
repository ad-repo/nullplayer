import CryptoKit
import Foundation

// MARK: - The transaction vocabulary
//
// These types are the boundary between the script session and the app. They survived the move off
// the helper process unchanged because they were never about the process: they are what a skin's
// script did, expressed so the controller can apply it on the main actor without ever seeing a
// `JSValue`.

enum WMPJScriptProtocol {
    static let maximumMutations = 4_096
    static let maximumHostCommands = 256
    static let maximumPreferenceCount = 512
    static let maximumRepaintHints = 4_096
    static let maximumTransactionsPerSecond = 120
}

enum WMPJSONValue: Hashable, Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self), number.isFinite { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case let .bool(item): try value.encode(item)
        case let .number(item):
            guard item.isFinite else {
                throw EncodingError.invalidValue(item, .init(codingPath: encoder.codingPath,
                                                             debugDescription: "non-finite number"))
            }
            try value.encode(item)
        case let .string(item): try value.encode(item)
        }
    }

    var number: Double? {
        switch self {
        case let .number(value): return value.isFinite ? value : nil
        case let .bool(value): return value ? 1 : 0
        case let .string(value): return Double(value).flatMap { $0.isFinite ? $0 : nil }
        case .null: return nil
        }
    }

    var string: String? {
        switch self {
        case let .string(value): return value
        case let .number(value): return WMPJSONValue.numberText(value)
        case let .bool(value): return value ? "true" : "false"
        case .null: return nil
        }
    }

    /// JScript prints an integral number without a fractional part, and a skin comparing
    /// `theme.loadPreference("Panel") == "1"` sees the difference.
    private static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }
}

struct WMPJScriptMutation: Hashable, Codable, Sendable {
    let targetID: String
    let property: String
    let value: WMPJSONValue
}

struct WMPJScriptHostCommand: Hashable, Codable, Sendable {
    let action: String
    let value: WMPJSONValue?
}

struct WMPJScriptPreferenceMutation: Hashable, Codable, Sendable {
    let key: String
    let value: String?
}

struct WMPJScriptTimerRequest: Hashable, Codable, Sendable {
    let token: Int
    let periodMilliseconds: Int
    let repeats: Bool
    /// Either the literal source a skin passed to `setTimeout`, or `__wmpTimer:<token>` when it
    /// passed a function. The context keeps the function; re-evaluating its text would lose every
    /// variable the closure captured, which is most of what a skin's timers are for.
    let source: String

    static func tokenMarker(_ token: Int) -> String { "__wmpTimer:\(token)" }
    var callbackToken: Int? {
        guard source.hasPrefix("__wmpTimer:") else { return nil }
        return Int(source.dropFirst("__wmpTimer:".count))
    }
}

struct WMPJScriptDiagnostic: Hashable, Codable, Sendable {
    let code: String
    let message: String
}

struct WMPJScriptExpressionResult: Hashable, Codable {
    let key: String
    let value: WMPJSONValue?
    let dependencies: [String]
    let error: String?
}

struct WMPJScriptEvent: Hashable, Codable, Sendable {
    let name: String
    let targetID: String?
    let handlers: [String]
}

/// One host object-model access: what was touched, whether it was read, written or called, what
/// answered, and how the member resolved. This is the measured-demand record `WMP_CALL_TRACE`
/// prints — the only thing that catches a member answering a plausible-but-wrong default, which a
/// static scan of the source cannot see.
struct WMPJScriptCall: Hashable, Codable, Sendable {
    enum Kind: String, Hashable, Codable, Sendable { case read, write, invoke }
    let path: String
    let kind: Kind
    let value: WMPJSONValue?
    let resolution: WMPMemberResolution

    var recognised: Bool { resolution != .unrecognised }
}

/// The static half of the demand tally: what the engine claims to implement, used by the census to
/// rank markup that asks for something else. It is derived from the one object model rather than
/// restated, so a member cannot be listed here and missing there.
enum WMPJScriptCompatibility {
    static let members: [String: Set<String>] = [
        "player": ["controls", "settings", "currentMedia", "currentPlaylist", "network",
                   "playState", "openState", "status", "isOnline", "enabled", "versionInfo"],
        "controls": ["play", "pause", "stop", "previous", "next", "fastForward", "fastReverse",
                     "currentPosition", "currentPositionString", "currentItem", "isAvailable",
                     "playItem"],
        "settings": ["volume", "balance", "mute", "getMode", "setMode", "getString", "setString",
                     "autoStart", "enableErrorDialogs", "invokeURLs"],
        "media": ["name", "duration", "durationString", "getItemInfo", "getItemInfoByAtom",
                  "isReadOnly", "imageSourceWidth", "imageSourceHeight", "attributeCount"],
        "playlist": ["count", "name", "item", "attributeCount", "getAttributeName",
                     "setColumnResizeMode"],
        "network": ["bufferingProgress", "receptionQuality", "bandWidth", "framesSkipped",
                    "lostPackets", "receivedPackets"],
        "eq": ["enabled", "bands", "presetCount", "presetTitle", "currentPreset",
               "currentPresetTitle", "nextPreset", "previousPreset", "reset",
               "gainLevel1", "gainLevel2", "gainLevel3", "gainLevel4", "gainLevel5",
               "gainLevel6", "gainLevel7", "gainLevel8", "gainLevel9", "gainLevel10"],
        "theme": ["currentViewID", "loadPreference", "savePreference", "loadString", "openView"],
        "view": ["left", "top", "width", "height", "close", "minimize", "visible"],
        "popup": ["appendItem", "removeAllItems", "getItem", "itemCount"],
        "element": Set(WMPObjectModel.standardElementProperties).union(["id"])
    ]

    static func supports(object: String, member: String) -> Bool {
        members[object.lowercased()]?.contains {
            $0.caseInsensitiveCompare(member) == .orderedSame
        } == true
    }
}

// MARK: - Output

struct WMPScriptOutput: Sendable {
    let overrides: WMPSceneOverrides
    let hostCommands: [WMPJScriptHostCommand]
    let diagnostics: [WMPJScriptDiagnostic]
    let repaintNodeIDs: Set<Int>
    let timerRequests: [WMPJScriptTimerRequest]
    /// Every host object-model access the transaction made, in order. Carried for `WMP_CALL_TRACE`;
    /// no production path reads it.
    let calls: [WMPJScriptCall]
    /// Every `JScript:` geometry expression's result, and the order they were evaluated in.
    /// Carried for `WMP_RENDER_EXPR`; no production path reads either.
    let expressions: [WMPJScriptExpressionResult]
    let expressionOrder: [String]

    init(overrides: WMPSceneOverrides, hostCommands: [WMPJScriptHostCommand] = [],
         diagnostics: [WMPJScriptDiagnostic] = [], repaintNodeIDs: Set<Int> = [],
         timerRequests: [WMPJScriptTimerRequest] = [], calls: [WMPJScriptCall] = [],
         expressions: [WMPJScriptExpressionResult] = [], expressionOrder: [String] = []) {
        self.overrides = overrides
        self.hostCommands = hostCommands
        self.diagnostics = diagnostics
        self.repaintNodeIDs = repaintNodeIDs
        self.timerRequests = timerRequests
        self.calls = calls
        self.expressions = expressions
        self.expressionOrder = expressionOrder
    }
}

// MARK: - Preferences

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
                diagnostics.append(.init(code: "preference-key-too-large",
                                         message: String(mutation.key.prefix(80)) + "…"))
                continue
            }
            if let value = mutation.value {
                guard value.utf8.count <= WMPPhase0Limits.preferenceValueBytes else {
                    diagnostics.append(.init(code: "preference-value-too-large", message: mutation.key))
                    continue
                }
                guard values[mutation.key] != nil || values.count < maximumCount else {
                    diagnostics.append(.init(code: "preference-count-limit",
                                             message: "maximum \(maximumCount) values"))
                    continue
                }
                values[mutation.key] = value
            } else { values.removeValue(forKey: mutation.key) }
        }
        defaults.set(values, forKey: key)
        return diagnostics
    }

    func reset() { defaults.removeObject(forKey: key) }
}

// MARK: - The session

/// One persistent JavaScript context per loaded skin, living for the whole skin session.
///
/// The fresh-process-per-transaction model this replaced could not hold a variable between two
/// clicks, which is most of what a WMP skin is: `g_paneCurrent` is set by one handler and read by
/// the next. It also could not let a `JScript:` geometry expression call a function the skin's own
/// `.js` file declares, because the probe pass that ordered the expressions was sent no scripts at
/// all (W21) — and one such failure emptied the whole ordered list, so *no* expression evaluated.
///
/// The security boundary moved with it, from the process to the object model: `ActiveXObject`,
/// `WScript`, `Enumerator` and every file and network global are undefined in the context, every
/// capability is reachable only through `WMPObjectModel`, and `WMPPhase0Limits` still bounds
/// timers, preferences and execution time. See Amendment 2 in `docs/wmp-skin/phase-0-decision-record.md`.
actor WMPScriptRuntime {
    private let preferences: WMPPreferenceStore
    private let executionSeconds: TimeInterval
    private var context: WMPScriptContext?
    private var contextSkin: ObjectIdentifier?
    private var contextViewID: String?
    private var propertyRegistry: WMPObservablePropertyRegistry?
    private var committedOverrides = WMPSceneOverrides.empty
    private var recentTransactionTimes: [Date] = []
    private var torndown = false

    init(preferences: WMPPreferenceStore,
         executionSeconds: TimeInterval = WMPPhase0Limits.scriptExecutionSeconds) {
        self.preferences = preferences
        self.executionSeconds = executionSeconds
    }

    /// `geometry` is the layout the skin is currently *drawn* at, keyed by stable id — the local
    /// frame of every node the last scene resolved. WMP's `element.height` answers the element's
    /// real current height, including one that came from its background artwork rather than from
    /// markup, and a script tests exactly that: Corona's compact view animates `svVideo` down to 0
    /// and gives up immediately if it reads 0 to begin with, which is what an authored-attributes-
    /// only model reports for an element sized by its bitmap.
    func transact(skin: WMPLoadedSkin, viewID: String, size: WMPSize,
                  snapshot: WMPHostSnapshot, event: WMPJScriptEvent?,
                  geometry: [Int: WMPRect] = [:]) async -> WMPScriptOutput {
        guard !torndown else { return WMPScriptOutput(overrides: committedOverrides) }
        let now = Date()
        recentTransactionTimes.removeAll { now.timeIntervalSince($0) >= 1 }
        guard recentTransactionTimes.count < WMPJScriptProtocol.maximumTransactionsPerSecond else {
            return WMPScriptOutput(overrides: committedOverrides,
                diagnostics: [.init(code: "script-rate-limit",
                                    message: "more than 120 transactions per second")])
        }
        recentTransactionTimes.append(now)

        let plan = WMPScriptViewPlan(skin: skin, viewID: viewID)
        var startupDiagnostics: [WMPJScriptDiagnostic] = []
        var pendingLoad = false
        if context == nil || contextSkin != ObjectIdentifier(skin) {
            context = WMPScriptContext(executionSeconds: executionSeconds)
            contextSkin = ObjectIdentifier(skin)
            contextViewID = nil
            pendingLoad = true
        }
        guard let context else { return WMPScriptOutput(overrides: committedOverrides) }
        if propertyRegistry == nil { propertyRegistry = WMPObservablePropertyRegistry(graph: skin.graph) }
        if contextViewID?.caseInsensitiveCompare(viewID) != .orderedSame {
            context.install(elements: plan.elements)
            contextViewID = viewID
        }
        // The elements are installed first on purpose: a skin's programs run top-level code that
        // touches its own elements, and WMP has the view before it has the script.
        if pendingLoad {
            startupDiagnostics = context.load(scripts: skin.scriptSources, order: skin.scripts)
        }

        let result = await context.run(plan: plan, size: size, snapshot: snapshot,
                                       preferences: preferences.values(), event: event,
                                       geometry: geometry)

        var diagnostics = startupDiagnostics + result.diagnostics
        diagnostics.append(contentsOf: preferences.apply(result.preferenceWrites))
        var overrides = committedOverrides
        for change in propertyRegistry?.changes(for: snapshot) ?? [] {
            overrides.properties[change.address] = change.value
        }
        for expression in result.expressions {
            guard expression.error == nil, let value = expression.value?.number, value.isFinite,
                  let address = plan.expressionAddresses[expression.key.lowercased()] else {
                if let error = expression.error {
                    diagnostics.append(.init(code: "expression-error",
                                             message: "\(expression.key): \(error)"))
                }
                continue
            }
            if (address.property == "width" || address.property == "height") && value < 0 {
                diagnostics.append(.init(code: "invalid-geometry", message: "\(expression.key) is negative"))
                continue
            }
            overrides.geometry[address] = CGFloat(value)
        }
        for mutation in result.mutations {
            guard let stableID = plan.idToStableID[WMPPath.fold(mutation.targetID)] else { continue }
            let address = WMPScenePropertyAddress(stableID: stableID,
                                                  property: mutation.property.lowercased())
            if ["left", "top", "width", "height"].contains(address.property),
               let value = mutation.value.number, value.isFinite,
               !((address.property == "width" || address.property == "height") && value < 0) {
                overrides.geometry[address] = CGFloat(value)
            } else {
                overrides.properties[address] = mutation.value
            }
        }
        let repaint = Set(result.repaintHints.compactMap { plan.idToStableID[WMPPath.fold($0)] })
        committedOverrides = overrides
        return WMPScriptOutput(overrides: overrides, hostCommands: result.hostCommands,
                               diagnostics: diagnostics, repaintNodeIDs: repaint,
                               timerRequests: result.timers, calls: result.calls,
                               expressions: result.expressions, expressionOrder: result.expressionOrder)
    }

    func resetPreferences() { preferences.reset() }

    func setWidgetValue(stableID: Int, value: Double) {
        guard value.isFinite else { return }
        committedOverrides.properties[.init(stableID: stableID, property: "value")] = .number(value)
        context?.setElementValue(stableID: stableID, value: value)
    }

    /// A view switch drops this view's overrides and its element registrations, but **not** the
    /// context: a skin's globals are declared once by its `.js` files and every view shares them.
    func prepareForViewSwitch() {
        committedOverrides = .empty
        propertyRegistry = nil
        contextViewID = nil
    }

    func teardown() {
        torndown = true
        context?.teardown()
        context = nil
        contextSkin = nil
        contextViewID = nil
    }
}
