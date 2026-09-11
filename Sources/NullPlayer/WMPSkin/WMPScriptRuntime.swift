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
    /// One authored handler and the arguments WMP raises it with.
    ///
    /// **A `<PLAYER>` event handler is a statement written against a named argument.** Corona's
    /// markup is `playstatechange="OnPlayStateChangeTransport(NewState);OnPlayStateChange();"` and
    /// `status_onchange="OnStatusChangeTransport(status);"`, and with neither name bound both
    /// handlers died on their first statement with a `ReferenceError` — which is why its
    /// `<WMPEFFECTS>` pane, turned on by `OnPlayStateChange`, never appeared. The arguments belong
    /// to the handler rather than to the transaction because one refresh raises `openstatechange`
    /// and `playstatechange` together and `NewState` is a *different* enum in each.
    struct Handler: Hashable, Codable, Sendable {
        let source: String
        var arguments: [String: WMPJSONValue] = [:]
    }

    let name: String
    let targetID: String?
    let handlers: [Handler]

    init(name: String, targetID: String?, handlers: [Handler]) {
        self.name = name; self.targetID = targetID; self.handlers = handlers
    }

    init(name: String, targetID: String?, handlers: [String],
         arguments: [String: WMPJSONValue] = [:]) {
        self.init(name: name, targetID: targetID,
                  handlers: handlers.map { Handler(source: $0, arguments: arguments) })
    }
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
                  "isReadOnly", "imageSourceWidth", "imageSourceHeight", "attributeCount",
                  "sourceURL"],
        "playlist": ["count", "name", "item", "attributeCount", "getAttributeName",
                     "setColumnResizeMode", "setColumnWidth"],
        "network": ["bufferingProgress", "receptionQuality", "bandWidth", "bitRate", "framesSkipped",
                    "lostPackets", "receivedPackets"],
        "eq": ["enabled", "bands", "presetCount", "presetTitle", "currentPreset",
               "currentPresetTitle", "nextPreset", "previousPreset", "reset",
               "gainLevel1", "gainLevel2", "gainLevel3", "gainLevel4", "gainLevel5",
               "gainLevel6", "gainLevel7", "gainLevel8", "gainLevel9", "gainLevel10"],
        // `closeView` and `openViewRelative` joined this list the moment they became live host
        // commands (W41, W50). A member the runtime answers must never stay in the demand tally:
        // that is how `alphaBlendTo` came to be ranked as the largest open row while it worked.
        "theme": ["currentViewID", "loadPreference", "savePreference", "loadString", "openView",
                  "closeView", "openViewRelative"],
        // `backgroundImage` is on this list because the view root resolves it the way every other
        // node does — a script override before the authored attribute (W75). Every skin with a
        // store-thumbnail `previewView` writes it, and the tally must not call it unknown.
        "view": ["left", "top", "width", "height", "close", "minimize", "visible",
                 "backgroundImage"],
        // Derived from the object model's own table rather than restated, so the static tally and
        // the runtime cannot disagree about what `mediacenter` answers. Every one of them is inert.
        "mediacenter": Set(WMPObjectModel.mediaCenterDefaults.keys).union(["getNamedString"]),
        "popup": ["appendItem", "removeAllItems", "getItem", "itemCount"],
        // Properties *and* methods: a call the runtime answers must not be counted as demand for
        // something unimplemented. Both halves are derived from the object model, never restated.
        "element": Set(WMPObjectModel.standardElementProperties)
            .union(WMPObjectModel.implementedElementMethods).union(["id"])
            // The `<EFFECTS>` rect's own four, which only that kind answers (W101). The set is
            // flat, so they are listed here rather than derived: a kind-aware table would have to
            // restate `elementMethod`, which is the authority.
            .union(["currentEffectType", "currentEffectTitle", "currentPreset", "currentPresetTitle"])
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
    /// The timers this transaction **registered**, which is a delta and not the live set: the
    /// script's `setTimeout`/`setInterval` calls from this one transaction, paired with
    /// `clearedTimerTokens`. See `WMPMainWindowController.applyTimerDelta` (W119).
    let timerRequests: [WMPJScriptTimerRequest]
    /// The tokens this transaction called `clearTimeout`/`clearInterval` on.
    let clearedTimerTokens: [Int]
    /// Every host object-model access the transaction made, in order. Carried for `WMP_CALL_TRACE`;
    /// no production path reads it.
    let calls: [WMPJScriptCall]
    /// Every `JScript:` geometry expression's result, and the order they were evaluated in.
    /// Carried for `WMP_RENDER_EXPR`; no production path reads either.
    let expressions: [WMPJScriptExpressionResult]
    let expressionOrder: [String]
    /// The items a `POPUP` or `LISTBOX` holds, by stable id. A skin fills these from script —
    /// `popupPreset.appendItem(...)` in an `onLoad` — so they are transaction output, not markup,
    /// and the AppKit menu has no other source for them.
    let listItems: [Int: [String]]
    /// The size this transaction's script **assigned to the view itself**, when it did.
    ///
    /// A `.wmz` compact mode is a script writing `view.width`/`view.height` and hiding one shell in
    /// favour of another, so it is the one thing in a transaction that has to reach the window
    /// rather than only the scene. Nil on every other transaction, which is nearly all of them —
    /// and nil for the store-thumbnail collapse to `0x0`, which is a view saying it has no window
    /// rather than one asking for a smaller one.
    let viewSize: WMPSize?

    init(overrides: WMPSceneOverrides, hostCommands: [WMPJScriptHostCommand] = [],
         diagnostics: [WMPJScriptDiagnostic] = [], repaintNodeIDs: Set<Int> = [],
         timerRequests: [WMPJScriptTimerRequest] = [], clearedTimerTokens: [Int] = [],
         calls: [WMPJScriptCall] = [],
         expressions: [WMPJScriptExpressionResult] = [], expressionOrder: [String] = [],
         listItems: [Int: [String]] = [:], viewSize: WMPSize? = nil) {
        self.listItems = listItems
        self.viewSize = viewSize
        self.overrides = overrides
        self.hostCommands = hostCommands
        self.diagnostics = diagnostics
        self.repaintNodeIDs = repaintNodeIDs
        self.timerRequests = timerRequests
        self.clearedTimerTokens = clearedTimerTokens
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
    /// Whose elements are installed in the context right now. One `JSContext` serves every open
    /// window, and every view root is called `view`, so the registry is swapped per transaction.
    private var contextViewID: String?
    /// **One registry per open view, and it is required rather than cosmetic.** The registry only
    /// reports values that *moved since it last looked*, so two windows sharing one would each see
    /// half the changes — the player's seek readout would settle on the ticks the playlist panel
    /// did not take, and vice versa.
    private var propertyRegistries: [String: WMPObservablePropertyRegistry] = [:]
    /// The scene overrides each open view has accumulated, by folded view id. A panel's script
    /// writes belong to its own window; before `theme.openView` opened one, applying them to the
    /// single presented view is what W90 was.
    private var committedOverrides: [String: WMPSceneOverrides] = [:]
    private var recentTransactionTimes: [Date] = []
    /// The dispatcher view's plan, built once. Building one walks the whole graph, and a dispatcher
    /// runs at the period its markup authored — 100 ms in every corpus skin that has one.
    private var dispatcherPlans: [String: WMPScriptViewPlan] = [:]
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
        let scope = WMPPath.fold(viewID)
        guard !torndown else { return WMPScriptOutput(overrides: overrides(for: scope)) }
        let now = Date()
        recentTransactionTimes.removeAll { now.timeIntervalSince($0) >= 1 }
        guard recentTransactionTimes.count < WMPJScriptProtocol.maximumTransactionsPerSecond else {
            return WMPScriptOutput(overrides: overrides(for: scope),
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
        guard let context else { return WMPScriptOutput(overrides: overrides(for: scope)) }
        if propertyRegistries[scope] == nil {
            propertyRegistries[scope] = WMPObservablePropertyRegistry(graph: skin.graph)
        }
        // **Swap this view's own live elements in, and leave the other window's stashed.** A
        // `restoreElements` that answers true is a view this session has already run — its objects,
        // its accumulated state — and the context stashes whichever view was installed before it on
        // the way past. A false answer is a view being opened for the first time, which installs
        // from the plan. This is the same primitive `runBackground` uses for the windowless
        // dispatcher, generalized: with more than one window there is no single "presented" view to
        // put back, and the next transaction for that window restores it.
        if contextViewID?.caseInsensitiveCompare(viewID) != .orderedSame {
            if !context.restoreElements(for: viewID) {
                context.install(elements: plan.elements, for: viewID)
            }
            contextViewID = viewID
        }
        // The elements are installed first on purpose: a skin's programs run top-level code that
        // touches its own elements, and WMP has the view before it has the script.
        if pendingLoad {
            startupDiagnostics = context.load(scripts: skin.scriptSources, order: skin.scripts)
        }

        // **The host's own changes are resolved before the handlers, not after (W51).** They used
        // to be folded into the overrides once the transaction had run, which is fine for what the
        // scene *draws* and wrong for what the skin can *react to*: a control the host moved read
        // as unmoved for the whole handler pass, and nothing raised its `value_onchange` at all.
        // Committing them afterwards is unchanged — this only decides what the transaction knew.
        let boundChanges = propertyRegistries[scope]?.changes(for: snapshot) ?? []
        var boundValues: [Int: WMPJSONValue] = [:]
        for change in boundChanges where change.address.property == "value" {
            boundValues[change.address.stableID] = change.value
        }
        let result = await context.run(plan: plan, size: size, snapshot: snapshot,
                                       preferences: preferences.values(), event: event,
                                       geometry: geometry, boundValues: boundValues)

        var diagnostics = startupDiagnostics + result.diagnostics
        diagnostics.append(contentsOf: preferences.apply(result.preferenceWrites))
        var overrides = overrides(for: scope)
        for change in boundChanges {
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
        let assigned = Self.assignedViewSize(skin: skin, viewID: viewID, plan: plan,
                                             mutations: result.mutations, overrides: overrides)
        let mediaDrivenResize = assigned.map {
            Self.isMediaDrivenViewResize(in: skin, viewID: viewID, assigned: $0,
                                         source: snapshot.video)
        } ?? false
        if mediaDrivenResize, let root = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node {
            // Do not retain a decoder-sized root assignment either. Otherwise the next binding-only
            // transaction would treat it as the view's default even though this transaction kept
            // the authored window size. Restore any pre-existing scripted size, if there was one.
            for property in ["width", "height"] {
                let address = WMPScenePropertyAddress(stableID: root.stableID, property: property)
                if let previous = self.overrides(for: scope).geometry[address] {
                    overrides.geometry[address] = previous
                } else {
                    overrides.geometry.removeValue(forKey: address)
                }
            }
        }
        let repaint = Set(result.repaintHints.compactMap { plan.idToStableID[WMPPath.fold($0)] })
        committedOverrides[scope] = overrides
        return WMPScriptOutput(overrides: overrides, hostCommands: result.hostCommands,
                               diagnostics: diagnostics, repaintNodeIDs: repaint,
                               timerRequests: result.timers, clearedTimerTokens: result.clearedTimers,
                               calls: result.calls,
                               expressions: result.expressions, expressionOrder: result.expressionOrder,
                               listItems: context.listItems(),
                               viewSize: mediaDrivenResize ? nil : assigned)
    }

    /// The size a transaction's script gave the view, or nil when it gave it none.
    ///
    /// Keyed off the **mutations**, not off `overrides.geometry`: an expression-driven
    /// `<VIEW width="jscript:…">` re-resolves on every transaction and is not a request to resize
    /// the window — it is a layout that already read the window's current size. Only an explicit
    /// assignment counts, which is what a compact-mode toggle is. A non-positive result is not a
    /// size: 34 corpus skins collapse a store-thumbnail `previewView` with `view.width = 0` before
    /// redirecting, and that view is one the controller declines to make a window out of.
    nonisolated static func assignedViewSize(skin: WMPLoadedSkin, viewID: String,
                                             plan: WMPScriptViewPlan,
                                             mutations: [WMPJScriptMutation],
                                             overrides: WMPSceneOverrides) -> WMPSize? {
        guard let root = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node else { return nil }
        let assigned = mutations.contains { mutation in
            plan.idToStableID[WMPPath.fold(mutation.targetID)] == root.stableID
                && ["width", "height"].contains(mutation.property.lowercased())
        }
        guard assigned,
              let width = overrides.geometry[WMPScenePropertyAddress(stableID: root.stableID,
                                                                     property: "width")],
              let height = overrides.geometry[WMPScenePropertyAddress(stableID: root.stableID,
                                                                      property: "height")],
              width > 0, height > 0 else { return nil }
        return WMPSize(width: width, height: height)
    }

    nonisolated static func isMediaDrivenViewResize(in skin: WMPLoadedSkin, viewID: String,
                                                    assigned: WMPSize,
                                                    source: WMPVideoSnapshot) -> Bool {
        guard let root = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node,
        let authoredViewSize = authoredSize(of: root),
        let video = descendant(of: root, matching: { node in
            node.kind == .video || node.kind == .wmpVideo
        }),
        let authoredVideoSize = authoredVideoSize(of: video, authoredViewSize: authoredViewSize) else {
            return false
        }
        return WMPVideoPresentation.isMediaDrivenViewSize(assigned,
            authoredViewSize: authoredViewSize, authoredVideoSize: authoredVideoSize, source: source)
    }

    private nonisolated static func authoredSize(of node: WMPNode) -> WMPSize? {
        guard let width = WMPNumber.literal(node.attribute(named: "width")),
              let height = WMPNumber.literal(node.attribute(named: "height")),
              width > 0, height > 0 else { return nil }
        return WMPSize(width: width, height: height)
    }

    private nonisolated static func descendant(of root: WMPNode,
                                               matching predicate: (WMPNode) -> Bool) -> WMPNode? {
        for child in root.children {
            if predicate(child) { return child }
            if let match = descendant(of: child, matching: predicate) { return match }
        }
        return nil
    }

    private nonisolated static func authoredVideoSize(of video: WMPNode,
                                                      authoredViewSize: WMPSize) -> WMPSize? {
        let container = video.parent?.kind == .view ? video : (video.parent ?? video)
        return authoredSize(of: container, authoredViewSize: authoredViewSize)
            ?? authoredSize(of: video, authoredViewSize: authoredViewSize)
    }

    private nonisolated static func authoredSize(of node: WMPNode,
                                                 authoredViewSize: WMPSize) -> WMPSize? {
        func dimension(_ name: String, _ fallback: CGFloat) -> CGFloat? {
            guard let attribute = node.attribute(named: name) else { return nil }
            if let literal = WMPNumber.literal(attribute) { return literal }
            let expression = attribute.rawValue.lowercased()
                .replacingOccurrences(of: " ", with: "")
            guard expression.contains("view.\(name.lowercased())") else { return nil }
            return fallback
        }
        guard let width = dimension("width", authoredViewSize.width),
              let height = dimension("height", authoredViewSize.height),
              width > 0, height > 0 else { return nil }
        return WMPSize(width: width, height: height)
    }

    /// One transaction for a **background dispatcher view** — a windowless view the skin keeps
    /// running alongside the player, polling its own preferences on its own timer (W89).
    ///
    /// It is deliberately not `transact`. A dispatcher produces no drawing: it has no window, so it
    /// has no scene, and letting its writes reach `committedOverrides` would apply one view's
    /// geometry to another's. It must also not consume the observable-property changes, which are
    /// delivered once and belong to the view that is on screen. What is left is what the caller
    /// wants: the host commands the handler posted, its preference writes, and its diagnostics.
    ///
    /// The rate limit is shared with `transact` on purpose — it bounds the whole session's script
    /// work, and a 100 ms dispatcher spends 10 of the 120 transactions a second it allows.
    func dispatch(skin: WMPLoadedSkin, viewID: String, currentViewID: String,
                  snapshot: WMPHostSnapshot, event: WMPJScriptEvent) async -> WMPScriptOutput {
        guard !torndown, let context, contextSkin == ObjectIdentifier(skin) else {
            return WMPScriptOutput(overrides: .empty)
        }
        let now = Date()
        recentTransactionTimes.removeAll { now.timeIntervalSince($0) >= 1 }
        guard recentTransactionTimes.count < WMPJScriptProtocol.maximumTransactionsPerSecond else {
            return WMPScriptOutput(overrides: .empty,
                diagnostics: [.init(code: "script-rate-limit",
                                    message: "more than 120 transactions per second")])
        }
        recentTransactionTimes.append(now)

        let plan = dispatcherPlans[WMPPath.fold(viewID)] ?? {
            let built = WMPScriptViewPlan(skin: skin, viewID: viewID)
            dispatcherPlans[WMPPath.fold(viewID)] = built
            return built
        }()
        let result = await context.runBackground(plan: plan, currentViewID: currentViewID,
                                                 snapshot: snapshot,
                                                 preferences: preferences.values(), event: event)
        var diagnostics = result.diagnostics
        diagnostics.append(contentsOf: preferences.apply(result.preferenceWrites))
        return WMPScriptOutput(overrides: .empty, hostCommands: result.hostCommands,
                               diagnostics: diagnostics, timerRequests: result.timers,
                               clearedTimerTokens: result.clearedTimers,
                               calls: result.calls)
    }

    func resetPreferences() { preferences.reset() }

    func setWidgetValue(stableID: Int, value: Double, viewID: String) {
        guard value.isFinite else { return }
        let scope = WMPPath.fold(viewID)
        var stored = overrides(for: scope)
        stored.properties[.init(stableID: stableID, property: "value")] = .number(value)
        committedOverrides[scope] = stored
        context?.setElementValue(stableID: stableID, value: value)
    }

    func setWidgetText(stableID: Int, text: String, viewID: String) {
        let scope = WMPPath.fold(viewID)
        var stored = overrides(for: scope)
        stored.properties[.init(stableID: stableID, property: "value")] = .string(text)
        committedOverrides[scope] = stored
        context?.setElementText(stableID: stableID, text: text)
    }

    private func overrides(for scope: String) -> WMPSceneOverrides {
        committedOverrides[scope] ?? .empty
    }

    /// **Drop one view's scope.** Called when its window closes and when `theme.currentViewID`
    /// replaces the view inside a window — the two moments a view genuinely stops existing.
    ///
    /// Its overrides, its observable-property registry and its live elements all go; the context
    /// does not, because a skin's globals are declared once by its `.js` files and every view shares
    /// them. **There is no restore counterpart any more.** `prepareForRestore` existed to put back a
    /// view that `theme.openView` had *covered* — WMP opened a second window and never touched the
    /// first, so this engine had to simulate one having survived. It now genuinely survives, in its
    /// own window, and nothing was ever put back except by that simulation (W90).
    func discardView(_ viewID: String) {
        let scope = WMPPath.fold(viewID)
        committedOverrides.removeValue(forKey: scope)
        propertyRegistries.removeValue(forKey: scope)
        context?.discardElements(for: viewID)
        if contextViewID?.caseInsensitiveCompare(viewID) == .orderedSame { contextViewID = nil }
    }

    func teardown() {
        torndown = true
        dispatcherPlans.removeAll()
        context?.teardown()
        context = nil
        contextSkin = nil
        contextViewID = nil
        committedOverrides.removeAll()
        propertyRegistries.removeAll()
    }
}
