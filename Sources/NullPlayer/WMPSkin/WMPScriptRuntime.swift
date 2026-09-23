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
    /// Tweens a single transaction may start. A handler that slides four panes is the corpus
    /// idiom; anything past this applies its endpoint instantly rather than being dropped.
    static let maximumTweens = 64
    /// The tween loop's frame period. 30 fps against a `.wmz` transaction-plus-rebuild costs a
    /// third of the 120/s transaction budget and leaves the rest for the view's own timer, which
    /// is the clock every animating skin in the corpus is already running.
    static let tweenFramePeriodMilliseconds = 33
}

/// **One `moveTo`/`resizeTo`/`alphaBlendTo`, expressed as the motion it asked for (W194).**
///
/// WMP animates these over the call's duration argument. This engine landed the endpoint at the
/// handler boundary and raised the completion in the same transaction, so a 1,000 ms slide took one
/// frame — reported against `Compact`'s drawers as *"its not a smooth opening"*. The endpoint is
/// still what a caller with no frame clock applies (a render dump is a still, and `WMPObjectModel`
/// only produces one of these when the transaction is told it has a clock), so the settled state is
/// unchanged either way; what this adds is the frames in between and, with them, the honest moment
/// for `onEndMove`.
struct WMPScriptTweenChannel: Sendable, Hashable {
    let property: String
    let from: Double
    let to: Double
}

struct WMPScriptTween: Sendable, Hashable {
    /// The element's script id, which is what a mutation is addressed by.
    let targetID: String
    let stableID: Int
    let channels: [WMPScriptTweenChannel]
    let durationMilliseconds: Double
    /// `endmove` or `endalphablend`, raised when the tween **finishes** rather than when the
    /// handler that started it returns. Nil for `resizeTo`: `onEndResize` is zero uses corpus-wide
    /// and deliberately not implemented.
    let completionEvent: String?
}

/// **One frame of every tween in flight, as the transaction that draws it (W194).**
///
/// A tween frame is a real script transaction and not a shortcut around one: the interpolated value
/// is written through the object model so the element reads where it *is*, the write becomes a
/// mutation and therefore a scene override, and a tween that reached its end carries its
/// `onEndMove` into the same transaction's completion pass — which is how a skin's sequence chains
/// off the end of the motion rather than off the end of the handler that started it.
struct WMPTweenFrame: Sendable {
    struct Write: Sendable {
        let targetID: String
        let property: String
        let value: Double
    }

    struct Completion: Sendable {
        let stableID: Int
        let event: String
    }

    let writes: [Write]
    let completions: [Completion]
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

/// The modifier keys held while an input event was dispatched, which is the live half of WMP's
/// `event` object this engine can answer honestly: the flags are read off the dispatching event
/// rather than guessed. `Compact`'s ten equaliser sliders are all
/// `value_onchange="if (!event.shiftKey) eq.gainLevel<n> = value;"` — every one of them aborted on
/// the undefined global, so the sliders inside its settings drawer moved and changed nothing.
struct WMPEventModifiers: OptionSet, Hashable, Codable, Sendable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let shift = WMPEventModifiers(rawValue: 1 << 0)
    static let control = WMPEventModifiers(rawValue: 1 << 1)
    static let alt = WMPEventModifiers(rawValue: 1 << 2)
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
    /// **The element that raised the event, when the markup never named it.** `targetID` is the
    /// skin's own `id` attribute and the corpus leaves it off wherever it has no script to write:
    /// `anemone`'s ten equaliser bands are `<SLIDER value_onchange="eq.gainLevel1=value;">` with no
    /// `id` at all. The dispatch sites already know which node was hit — `handlers(in:event:)`
    /// selects the handlers by stable id — so the runtime is told the same thing, and both the
    /// bound `value` and the handler's own `with` scope resolve for an unnamed element too.
    let targetStableID: Int?
    let handlers: [Handler]
    /// The modifiers held when the input that raised this event was dispatched. Empty for the
    /// transactions that are not input — a view timer, a host state change — which is what the
    /// skin's own `if (!event.shiftKey)` guards read as *no modifier*, the ordinary path.
    var modifiers: WMPEventModifiers = []
    /// The key this event carries, as `event.keyCode` answers it — a Windows VK for `keydown` and
    /// `keyup`, a character code for `keypress` (`WMPVirtualKeyCode`). Nil for every transaction
    /// that is not a keystroke, and for a key with no honest VK, which is why `readEvent` answers
    /// the absent case rather than `0`: `0` is VK_NULL and every corpus handler switches over the
    /// number (W53, and W260's rule that an absent value is not a zero).
    var keyCode: Int?

    init(name: String, targetID: String?, targetStableID: Int? = nil, handlers: [Handler],
         modifiers: WMPEventModifiers = [], keyCode: Int? = nil) {
        self.name = name; self.targetID = targetID; self.targetStableID = targetStableID
        self.handlers = handlers
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    init(name: String, targetID: String?, targetStableID: Int? = nil, handlers: [String],
         arguments: [String: WMPJSONValue] = [:], modifiers: WMPEventModifiers = [],
         keyCode: Int? = nil) {
        self.init(name: name, targetID: targetID, targetStableID: targetStableID,
                  handlers: handlers.map { Handler(source: $0, arguments: arguments) },
                  modifiers: modifiers, keyCode: keyCode)
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
                   "playState", "openState", "status", "isOnline", "enabled", "versionInfo",
                   "fullScreen"],
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
        // `downloadProgress`, `sourceProtocol` and `maxBitRate` joined this list when they stopped
        // being unrecognised (W104). The first two were the drift this comment's own invariant is
        // meant to prevent: `sourceProtocol` had been answered in `readNetwork` since W101's Corona
        // case while staying absent here, so the census went on ranking demand for a member the
        // engine already answered — the `alphaBlendTo` trap named on `theme` below.
        "network": ["bufferingProgress", "downloadProgress", "receptionQuality", "bandWidth",
                    "bitRate", "maxBitRate", "sourceProtocol", "framesSkipped",
                    "lostPackets", "receivedPackets"],
        "eq": ["enhancedAudio", "wowLevel", "truBassLevel", "speakerSize", "currentSpeakerName",
               "crossFade", "crossFadeWindow", "normalization",
               "enableSplineTension", "splineTension",
               "enabled", "bypass", "bands", "presetCount", "presetTitle", "currentPreset",
               "currentPresetTitle", "nextPreset", "previousPreset", "reset",
               "gainLevel1", "gainLevel2", "gainLevel3", "gainLevel4", "gainLevel5",
               "gainLevel6", "gainLevel7", "gainLevel8", "gainLevel9", "gainLevel10"],
        // `closeView` and `openViewRelative` joined this list the moment they became live host
        // commands (W41, W50). A member the runtime answers must never stay in the demand tally:
        // that is how `alphaBlendTo` came to be ranked as the largest open row while it worked.
        "theme": ["currentViewID", "loadPreference", "savePreference", "loadString", "openView",
                  "closeView", "openViewRelative"],
        // The two members of WMP's `event` object that describe the display rather than a live
        // input event. The rest of it stays off this list on purpose — see `readEvent`.
        "event": ["screenWidth", "screenHeight", "shiftKey", "ctrlKey", "altKey", "keyCode"],
        // `backgroundImage` is on this list because the view root resolves it the way every other
        // node does — a script override before the authored attribute (W75). Every skin with a
        // store-thumbnail `previewView` writes it, and the tally must not call it unknown.
        "view": ["left", "top", "width", "height", "close", "minimize", "size", "visible",
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
    /// **Whether this view still owes a tween frame (W194).** A `moveTo` with a duration animates
    /// only where something is driving frames, so this is the caller's own loop condition: keep
    /// calling `WMPScriptRuntime.tweenFrame` while it is true. False on every transaction run
    /// without `animatesTweens`, which is every headless one.
    let hasActiveTweens: Bool

    init(overrides: WMPSceneOverrides, hostCommands: [WMPJScriptHostCommand] = [],
         diagnostics: [WMPJScriptDiagnostic] = [], repaintNodeIDs: Set<Int> = [],
         timerRequests: [WMPJScriptTimerRequest] = [], clearedTimerTokens: [Int] = [],
         calls: [WMPJScriptCall] = [],
         expressions: [WMPJScriptExpressionResult] = [], expressionOrder: [String] = [],
         listItems: [Int: [String]] = [:], viewSize: WMPSize? = nil,
         hasActiveTweens: Bool = false) {
        self.hasActiveTweens = hasActiveTweens
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
    /// The value each authored geometry expression produced the last time it was evaluated, per
    /// view scope. An expression re-applies only when this changes — see `transact`.
    private var committedExpressions: [String: [WMPScenePropertyAddress: CGFloat]] = [:]
    /// Geometry addresses the script has explicitly assigned, per view scope. An authored
    /// `jscript:` expression never re-applies to one of these again (W159).
    private var scriptAssignedGeometry: [String: [WMPScenePropertyAddress: WMPSize]] = [:]
    /// The canvas each script-assigned alignment was written at, per view scope. See
    /// `WMPSceneOverrides.scriptAssignedAlignment`.
    private var scriptAssignedAlignment: [String: [WMPScenePropertyAddress: WMPSize]] = [:]
    /// **The half of a handler that WMP runs after the drag, held until the drag is over (W225).**
    /// Everything a handler writes after `view.size(corner)` — see
    /// `WMPObjectModel.resizeCallMutationIndex`. Keyed by view scope, replayed by
    /// `resumeAfterWindowResize`, and dropped with the rest of the scope by `discardView`.
    private var deferredResizeMutations: [String: [WMPJScriptMutation]] = [:]
    /// Mirrors `WMPSceneOverrides.scriptAlignmentExtent` — the size an element had when the script
    /// assigned its alignment. Kept out of the geometry overrides on purpose; see that field.
    private var scriptAlignmentExtent: [String: [WMPScenePropertyAddress: CGFloat]] = [:]
    private var recentTransactionTimes: [Date] = []
    /// **The tweens in flight, per view scope (W194).** A tween outlives the transaction that
    /// started it — that is the whole of this row — so it is runtime state rather than transaction
    /// output. A later call on the same element and property replaces the one running, because a
    /// skin retoggling a drawer mid-slide means "go the other way", not "queue a second slide".
    private var activeTweens: [String: [ActiveTween]] = [:]

    private struct ActiveTween {
        let tween: WMPScriptTween
        let started: Date

        var endsAt: Date { started.addingTimeInterval(tween.durationMilliseconds / 1_000) }
    }
    /// The dispatcher view's plan, built once. Building one walks the whole graph, and a dispatcher
    /// runs at the period its markup authored — 100 ms in every corpus skin that has one.
    private var dispatcherPlans: [String: WMPScriptViewPlan] = [:]
    private var torndown = false
    /// The display the skin's windows are on, answered to the skin as `event.screenWidth` /
    /// `event.screenHeight`. The controller sets it from the window's own screen and updates it
    /// when the window moves to another one; headlessly it stays at the harness default so a
    /// corpus sweep reads the same on every machine.
    private var screen = WMPObjectModel.defaultScreen
    /// The **usable** part of that display — the desktop minus the menu bar and the Dock — and the
    /// ceiling every view size is fitted into. Separate from `screen` because the two answer
    /// different questions: `screen` is what `event.screenWidth` means to a skin, and this is how
    /// big a window may actually be and still be reachable. See `WMPSize.fitted(within:)`.
    private var usableScreen = WMPObjectModel.defaultScreen

    init(preferences: WMPPreferenceStore,
         executionSeconds: TimeInterval = WMPPhase0Limits.scriptExecutionSeconds) {
        self.preferences = preferences
        self.executionSeconds = executionSeconds
    }

    func setScreen(_ size: WMPSize, usable: WMPSize? = nil) {
        guard size.width > 0, size.height > 0 else { return }
        screen = size
        if let usable, usable.width > 0, usable.height > 0 { usableScreen = usable }
    }

    /// `geometry` is the layout the skin is currently *drawn* at, keyed by stable id — the local
    /// frame of every node the last scene resolved. WMP's `element.height` answers the element's
    /// real current height, including one that came from its background artwork rather than from
    /// markup, and a script tests exactly that: Corona's compact view animates `svVideo` down to 0
    /// and gives up immediately if it reads 0 to begin with, which is what an authored-attributes-
    /// only model reports for an element sized by its bitmap.
    ///
    /// `animatesTweens` is the caller promising a frame clock: it will keep calling `tweenFrame`
    /// until the output stops reporting active tweens. Only a window can (W194); a render dump and
    /// the corpus census cannot, and for them a `moveTo` lands its endpoint in this transaction
    /// exactly as it did before that row.
    func transact(skin: WMPLoadedSkin, viewID: String, size: WMPSize,
                  snapshot: WMPHostSnapshot, event: WMPJScriptEvent?,
                  geometry: [Int: WMPRect] = [:],
                  animatesTweens: Bool = false,
                  tweenFrame: WMPTweenFrame? = nil,
                  injecting injected: [WMPJScriptMutation] = []) async -> WMPScriptOutput {
        let scope = WMPPath.fold(viewID)
        guard !torndown else { return WMPScriptOutput(overrides: overrides(for: scope)) }
        let now = Date()
        recentTransactionTimes.removeAll { now.timeIntervalSince($0) >= 1 }
        // **A tween frame is not rate limited, because it is not the script's to spend.** The cap
        // exists to stop a handler feeding itself; a frame comes from the host's own 30 Hz loop,
        // and dropping one would strand a drawer short of the pixel it was travelling to and lose
        // the `onEndMove` that frame was carrying (W194).
        guard tweenFrame != nil
                || recentTransactionTimes.count < WMPJScriptProtocol.maximumTransactionsPerSecond else {
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
        // **Every view's elements exist from the moment the skin's context does (W40).** One script
        // scope serves the whole skin, so a shared function names the view it was written for and
        // runs from whichever view calls it; installing only the view on screen left those names
        // unbound. This is markup only — no handler and no geometry expression runs here.
        if pendingLoad {
            context.prepare(views: skin.views.map {
                ($0.id, WMPScriptViewPlan(skin: skin, viewID: $0.id).elements)
            })
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
            startupDiagnostics = context.load(scripts: skin.scriptSources, order: skin.scripts,
                                              viewScripts: Self.viewScriptPaths(in: skin))
        }

        // **The host's own changes are resolved before the handlers, not after (W51).** They used
        // to be folded into the overrides once the transaction had run, which is fine for what the
        // scene *draws* and wrong for what the skin can *react to*: a control the host moved read
        // as unmoved for the whole handler pass, and nothing raised its `value_onchange` at all.
        // Committing them afterwards is unchanged — this only decides what the transaction knew.
        let boundChanges = propertyRegistries[scope]?.changes(for: snapshot, holding: heldElements) ?? []
        var boundValues: [Int: WMPJSONValue] = [:]
        for change in boundChanges where change.address.property == "value" {
            boundValues[change.address.stableID] = change.value
        }
        let result = await context.run(plan: plan, size: size, snapshot: snapshot,
                                       preferences: preferences.values(), event: event,
                                       geometry: geometry, boundValues: boundValues,
                                       retiredGeometry: Set((scriptAssignedGeometry[scope] ?? [:]).keys),
                                       screen: screen, usableScreen: usableScreen,
                                       animatesTweens: animatesTweens,
                                       tweenFrame: tweenFrame)
        register(tweens: result.tweens, in: scope)
        if WMPTweenTrace.enabled, !result.tweens.isEmpty || !(activeTweens[scope] ?? []).isEmpty {
            WMPTweenTrace.log("transact view=\(viewID) event=\(event?.name ?? "-")"
                + " clock=\(animatesTweens) frame=\(tweenFrame != nil)"
                + " registered=\(result.tweens.count) live=\((activeTweens[scope] ?? []).count)")
        }

        var diagnostics = startupDiagnostics + result.diagnostics
        #if DEBUG
        if ProcessInfo.processInfo.environment["WMP_CLICK_TRACE"] == "1", event?.name != "timer" {
            NSLog("[wmp/pref] view=%@ event=%@ sawCurrView=%@ writes=%@", viewID,
                  event?.name ?? "-", preferences.values()["currView"] ?? "-",
                  result.preferenceWrites.map { "\($0.key)=\($0.value ?? "nil")" }
                      .joined(separator: ",").isEmpty ? "-" :
                      result.preferenceWrites.map { "\($0.key)=\($0.value ?? "nil")" }
                      .joined(separator: ","))
        }
        #endif
        diagnostics.append(contentsOf: preferences.apply(result.preferenceWrites))
        var overrides = overrides(for: scope)
        /// The geometry this transaction started from, kept for a refused decoder-driven resize.
        let baselineGeometry = overrides.geometry
        for change in boundChanges {
            overrides.properties[change.address] = change.value
        }
        // **An authored geometry expression re-applies only when its own value changes, because
        // otherwise it overwrites the script assignment that came after it.**
        //
        // `JScript:` geometry is re-evaluated every transaction — that is what makes
        // `top="jscript:view.height-123"` follow a resize — and the result was being committed
        // unconditionally, ahead of the mutations. A transaction whose handlers never touch the
        // node contributes no mutation for it, so the expression's answer won and the node snapped
        // back to its authored position. Any view with an `onTimer` therefore undid its own script
        // within one tick: `xsn_sports` slides its video and visualisation drawers with
        // `visDrawer.moveTo(0, view.height-73, 400)` against `onTimer="htcpVis()" timerInterval="500"`,
        // and half a second later `view.height-123` put the drawer back while the settings panel
        // the drawer had revealed stayed visible — reported as "it still does not open and the
        // content still shows when retracted" (W144). This is the same distinction
        // `assignedViewSize` already draws for the root: an expression that re-resolves is a layout
        // reading the current size, not a fresh request.
        //
        // Comparing against the value this expression last produced is what keeps the resize case
        // working: `view.height` changing makes the expression's answer change, so it wins again,
        // and so does an expression reading another element the script moved
        // (`top="wmpprop:plLeftCenter.top"`). When the answer is identical, writing it or not
        // differs only where something else has since written the address — which is exactly the
        // assignment that must stand.
        var expressionValues = committedExpressions[scope] ?? [:]
        var scriptAssigned = scriptAssignedGeometry[scope] ?? [:]
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
            let resolved = CGFloat(value)
            defer { expressionValues[address] = resolved }
            // **A script assignment retires the authored expression for that address (W159).**
            //
            // W144 above stops an expression overwriting a script assignment *when its own value has
            // not moved*, which is the case it was reported on. It is not the whole of it: an
            // expression reading `view.width` moves precisely when the view resizes, and a handler
            // that assigns a geometry property and then resizes the view is doing both in one
            // breath. `NVIDIA`'s `setModesMinWidth('playlist')` sets `mainModeMetadata.left = 220`
            // and `width = view.width-266` and then takes the view from 285 to 700; the element
            // authors `left="55"` — a literal, which yields to the script permanently — and
            // `width="jscript:view.width-101"`, which came back on the next transaction with 629 and
            // took the property back. Measured in the running app: the node ended up
            // `left=220 width=629` in a 730-wide window, 119 px past its right edge, and the time
            // readout hanging off `left="jscript:mainModeMetadata.width-80"` resolved against 629
            // and drew at x=769, off the window entirely. Reported as "the timer in the playlist
            // draws at the wrong location".
            //
            // So an address the script has explicitly written is the script's from then on, and the
            // expression is only ever a starting value for it. The value is still recorded above, so
            // nothing re-fires spuriously if the address is ever released; `discardView` drops the
            // set with the rest of the view's scope, because a view that stops existing has no
            // assignments to honour.
            guard scriptAssigned[address] == nil else { continue }
            guard expressionValues[address] != resolved else { continue }
            overrides.geometry[address] = resolved
        }
        committedExpressions[scope] = expressionValues
        // **The half of the handler that runs after the drag (W225).** `view.size(corner)` blocks
        // in WMP until the user lets go, so a skin's resize bracket — `Compact`'s `DoSize()` pins
        // both drawers to the edges they must ride, calls it, unpins them — states the pin for the
        // *duration* of the drag. Nothing here can block, so the tail of the handler is held and
        // `resumeAfterWindowResize` replays it on the release.
        //
        // Gated on `animatesTweens` for the same reason a tween is (W194): that is the caller
        // promising it is a window, and only a window runs a drag at all. A render dump, the corpus
        // census and the windowless dispatcher have no drag to hold anything for, so for them the
        // handler still runs straight through and every measurement taken against them holds.
        var mutations = injected + result.mutations
        if animatesTweens, let index = result.resizeCallMutationIndex {
            let split = index + injected.count
            if split < mutations.count {
                deferredResizeMutations[scope, default: []]
                    .append(contentsOf: mutations[split...])
                wmpResizeTrace("hold \(mutations.count - split) of \(mutations.count) at "
                    + "\(size.width)x\(size.height): "
                    + mutations[split...].map { "\($0.targetID).\($0.property)=\($0.value.string ?? "-")" }
                        .joined(separator: " "))
                mutations = Array(mutations[..<split])
            }
        }
        var scriptAligned = scriptAssignedAlignment[scope] ?? [:]
        var alignmentExtent = scriptAlignmentExtent[scope] ?? [:]
        // **The canvas each mutation was written at, which moves *within* the transaction.** A
        // handler that grows its own window and then re-anchors something against the new size —
        // `Compact`'s `view.width += rightMove` between two `SetAlignment` calls — does both in one
        // transaction, so the incoming `size` is the right canvas for the writes before the resize
        // and the wrong one for the writes after it. Tracked over the mutation list in order, which
        // is the order the handlers made them in.
        let rootNode = skin.views.first {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        }?.node
        let rootStableID = rootNode?.stableID
        // Only a child of the view root can be frozen by an alignment write, for the same reason
        // only one can be anchored by it: the anchor is a view canvas, and a deeper node's parent
        // grew by an amount the canvas does not state.
        let rootChildIDs = Set((rootNode?.children ?? []).map(\.stableID))
        // The layout as the script knows it *now*: the frames the last scene resolved, advanced by
        // every geometry mutation this transaction has already made.
        var resolved = geometry
        var canvas = size
        for mutation in mutations {
            guard let stableID = plan.idToStableID[WMPPath.fold(mutation.targetID)] else { continue }
            let address = WMPScenePropertyAddress(stableID: stableID,
                                                  property: mutation.property.lowercased())
            if ["left", "top", "width", "height"].contains(address.property),
               let value = mutation.value.number, value.isFinite,
               !((address.property == "width" || address.property == "height") && value < 0) {
                overrides.geometry[address] = CGFloat(value)
                scriptAssigned[address] = canvas
                if alignmentExtent[address] != nil { alignmentExtent[address] = CGFloat(value) }
                if var frame = resolved[stableID] {
                    switch address.property {
                    case "left": frame.x = CGFloat(value)
                    case "top": frame.y = CGFloat(value)
                    case "width": frame.width = CGFloat(value)
                    default: frame.height = CGFloat(value)
                    }
                    resolved[stableID] = frame
                }
                if stableID == rootStableID, value > 0 {
                    let before = canvas
                    if address.property == "width" { canvas.width = CGFloat(value) }
                    if address.property == "height" { canvas.height = CGFloat(value) }
                    Self.carryAlignedPieces(through: WMPSize(width: canvas.width - before.width,
                                                             height: canvas.height - before.height),
                                            at: canvas, aligned: &scriptAligned,
                                            overrides: &overrides, assigned: &scriptAssigned,
                                            geometry: geometry, skin: skin)
                }
            } else {
                overrides.properties[address] = mutation.value
                if address.property == "horizontalalignment" || address.property == "verticalalignment" {
                    scriptAligned[address] = canvas
                    // **Assigning an alignment freezes the element where it currently is (W225).**
                    // WMP re-measures the element's margins against the canvas at the write, so the
                    // coordinate it holds afterwards is the one it is *drawn* at — not the one the
                    // markup authored. Resolving from the authored value instead is what made the
                    // skins' own resize bracket lossy: `Compact` pins `playlistDrawer` to `right`
                    // so it rides a drag out to the window's edge, then writes `left` back to park
                    // it, and the unpin teleported the drawer 478 px back into the middle of a
                    // stretched player, underneath the body, with its tab buried where nothing
                    // could click it. Recording the resolved frame — and anchoring it at this
                    // canvas, so the growth that counts afterwards is the growth since the write —
                    // is the same reading `scriptDelta` already gives a script-assigned coordinate.
                    //
                    // **One archive in the corpus assigns an alignment from script** (`Compact`, 20
                    // writes; decoded `.wms`+`.js` scan), so this can move nothing else.
                    if rootChildIDs.contains(stableID), let frame = resolved[stableID] {
                        let horizontal = address.property == "horizontalalignment"
                        let origin = horizontal ? ("left", frame.x) : ("top", frame.y)
                        let extent = horizontal ? ("width", frame.width) : ("height", frame.height)
                        // The origin half is an ordinary script-assigned coordinate…
                        if origin.1 >= 0 {
                            let frozen = WMPScenePropertyAddress(stableID: stableID,
                                                                 property: origin.0)
                            overrides.geometry[frozen] = origin.1
                            scriptAssigned[frozen] = canvas
                        }
                        // …the extent half is not, because `ownAuthoredSize` reads the geometry
                        // overrides and every child's alignment delta is measured from it.
                        if extent.1 >= 0 {
                            alignmentExtent[WMPScenePropertyAddress(stableID: stableID,
                                                                    property: extent.0)] = extent.1
                        }
                        wmpResizeTrace("freeze \(mutation.targetID) \(origin.0)=\(origin.1) "
                            + "\(extent.0)=\(extent.1) as \(mutation.value.string ?? "-") at "
                            + "\(canvas.width)x\(canvas.height)")
                    }
                }
            }
        }
        scriptAssignedAlignment[scope] = scriptAligned
        overrides.scriptAssignedAlignment = scriptAligned
        scriptAlignmentExtent[scope] = alignmentExtent
        overrides.scriptAlignmentExtent = alignmentExtent
        var assigned = Self.assignedViewSize(skin: skin, viewID: viewID, plan: plan,
                                             mutations: mutations, overrides: overrides,
                                             currentSize: size)
        // **The size the script asked for is not always the size it got (W99).** `assignedViewSize`
        // reads the raw mutations; the builder clamps the canvas to the view's own
        // `minWidth`/`minHeight`, so a script writing through that floor — `ALXMorph`'s
        // `onLoadVid()` assigns 316 into a `minHeight="357"` view — had the window, the next
        // transaction's size and every `jscript:view.height` expression all carrying a number
        // nothing is ever drawn at. The transaction applies the same clamp to the view element and
        // reports it here, so the one answer reaches all three.
        // **The decoder-driven test reads the *raw* assignment, before any clamp.** It recognises
        // a size by its formula — the authored shell plus the decoder's dimensions minus the
        // authored video box — and a clamped number is no longer that formula. Testing the clamped
        // one instead stopped `corona`, `Classic`, `9SeriesDefault` and `Compact` being recognised
        // at all the moment the display ceiling touched them, and the engine then *kept* an
        // assignment it exists to discard: all four grew from their authored canvas to the whole
        // screen. Measured corpus-wide, which is the only way that showed up.
        let mediaDrivenResize = assigned.map {
            Self.isMediaDrivenViewResize(in: skin, viewID: viewID, assigned: $0,
                                         source: snapshot.video)
        } ?? false
        if let drawn = result.drawnViewSize, assigned != nil {
            assigned = drawn
            // **The overrides are what the builder sizes the canvas from, so a clamp that is not
            // also the builder's own rule has to be written into them.** The view's floor is one
            // the builder re-applies from the markup; the display ceiling is not, and leaving the
            // raw assignment here built the scene at the size the script asked for while the
            // window, the script and every `jscript:view.width` carried the clamped one — which is
            // exactly the scene/window disagreement W213 names.
            if let root = skin.views.first(where: {
                $0.id.caseInsensitiveCompare(viewID) == .orderedSame
            })?.node {
                overrides.geometry[WMPScenePropertyAddress(stableID: root.stableID,
                                                           property: "width")] = drawn.width
                overrides.geometry[WMPScenePropertyAddress(stableID: root.stableID,
                                                           property: "height")] = drawn.height
            }
        }
        if mediaDrivenResize {
            // **A refused resize takes its whole layout with it, not just the root's two numbers.**
            // Every `jscript:` expression in the view resolved against the size the handler
            // assigned, so keeping those while refusing the window is the W99 disagreement at its
            // widest: measured on `Combat_Flight_Simulator_3` with a 2560x1440 film, the root came
            // back to its authored 380x351 while `centerBox`/`videoWin` — authored
            // `jscript:view.width-20` — stayed **1900x969** inside it, which is the box the picture
            // is parked over. Restoring the geometry the last committed transaction held drops all
            // of it together; where there is none (the first transaction, which is when a view
            // opens onto a film already playing) the builder resolves the expressions itself
            // against the authored canvas, which is exactly the layout that was wanted.
            overrides.geometry = baselineGeometry
        }
        let repaint = Set(result.repaintHints.compactMap { plan.idToStableID[WMPPath.fold($0)] })
        scriptAssignedGeometry[scope] = scriptAssigned
        overrides.scriptAssignedGeometry = scriptAssigned
        committedOverrides[scope] = overrides
        return WMPScriptOutput(overrides: overrides, hostCommands: result.hostCommands,
                               diagnostics: diagnostics, repaintNodeIDs: repaint,
                               timerRequests: result.timers, clearedTimerTokens: result.clearedTimers,
                               calls: result.calls,
                               expressions: result.expressions, expressionOrder: result.expressionOrder,
                               listItems: context.listItems(),
                               viewSize: mediaDrivenResize ? nil : assigned,
                               hasActiveTweens: !(activeTweens[scope] ?? []).isEmpty)
    }

    // MARK: Tweens (W194)

    /// A new call replaces whatever was animating the same element and property. `Compact`'s
    /// drawer tab is one handler that moves the drawer either way depending on where it reads it,
    /// so a press mid-slide has to reverse the motion from where it currently *is* — which it does
    /// for free, because the replacement's `from` was read off the element in the frame it landed.
    private func register(tweens: [WMPScriptTween], in scope: String) {
        guard !tweens.isEmpty else { return }
        let now = Date()
        var live = activeTweens[scope] ?? []
        for tween in tweens {
            let replaced = Set(tween.channels.map { $0.property })
            live.removeAll { existing in
                existing.tween.stableID == tween.stableID
                    && existing.tween.channels.contains { replaced.contains($0.property) }
            }
            live.append(.init(tween: tween, started: now))
        }
        activeTweens[scope] = live
    }

    /// **One frame of every tween in flight, or nil when there is nothing left to animate.**
    ///
    /// The caller is a frame loop, so this answers the whole question it has: it steps the clock,
    /// runs the transaction that draws the frame, and its output reports whether another frame is
    /// owed. A tween that reached its end contributes its endpoint *and* its completion to the
    /// same frame, so `onEndMove` is raised with the element already at its destination — a handler
    /// reading `subPlayList.left` to decide whether the drawer is now open sees the number it would
    /// see in WMP.
    ///
    /// Motion is linear. WMP's own easing is undocumented and the corpus is sliding drawers over
    /// two to four hundred milliseconds, where the curve is not what anyone is reporting.
    func tweenFrame(skin: WMPLoadedSkin, viewID: String, size: WMPSize,
                    snapshot: WMPHostSnapshot,
                    geometry: [Int: WMPRect] = [:]) async -> WMPScriptOutput? {
        let scope = WMPPath.fold(viewID)
        guard !torndown, let live = activeTweens[scope], !live.isEmpty else { return nil }
        let now = Date()
        var writes: [WMPTweenFrame.Write] = []
        var completions: [WMPTweenFrame.Completion] = []
        var remaining: [ActiveTween] = []
        for entry in live {
            let duration = entry.tween.durationMilliseconds / 1_000
            let progress = duration > 0
                ? min(1, max(0, now.timeIntervalSince(entry.started) / duration))
                : 1
            for channel in entry.tween.channels {
                let value = channel.from + (channel.to - channel.from) * progress
                writes.append(.init(targetID: entry.tween.targetID, property: channel.property,
                                    // The last frame is the endpoint itself rather than an
                                    // interpolation that happens to land near it: a drawer must
                                    // come to rest on the pixel the skin named.
                                    value: progress >= 1 ? channel.to : value))
            }
            if progress >= 1 {
                if let event = entry.tween.completionEvent {
                    completions.append(.init(stableID: entry.tween.stableID, event: event))
                }
            } else {
                remaining.append(entry)
            }
        }
        activeTweens[scope] = remaining
        return await transact(skin: skin, viewID: viewID, size: size, snapshot: snapshot,
                              event: nil, geometry: geometry, animatesTweens: true,
                              tweenFrame: .init(writes: writes, completions: completions))
    }

    /// Stop animating one view — its window closed, or its view was replaced. Nothing puts the
    /// endpoint back: a view that stops existing has no motion to finish.
    func cancelTweens(for viewID: String) {
        activeTweens.removeValue(forKey: WMPPath.fold(viewID))
    }

    /// **A script-assigned alignment is live *through* a resize the same handler makes.**
    ///
    /// The corpus idiom is three statements — pin the piece, change the view's size, pin it back —
    /// and it is how `Compact` keeps a drawer glued to the edge it lives on while the window
    /// changes size around it: `SnapToVideoSize` sets `playlistDrawer.horizontalAlignment="right"`,
    /// writes `view.width`, and sets it back to `"left"`. This engine lays a view out **once per
    /// transaction**, so the middle state never existed: the drawer stayed at the coordinate it had
    /// while the window grew past it, which puts its tab — authored 184 px inside it — outside the
    /// window, where nothing can ever click it again. Reported as "the drawers disappear … stuck in
    /// a bad state that you cannot escape and get the drawers back" (W192).
    ///
    /// So the delta is applied here, at the moment the size changes, to every piece whose alignment
    /// the script has set *so far in this transaction* — and each piece is re-anchored at the new
    /// canvas, so the builder's own alignment pass adds nothing on top and a later `="left"` in the
    /// same handler re-anchors to the same place. A **markup**-authored alignment is untouched: the
    /// builder already measures those from the view's authored size, which includes this resize.
    /// One archive in the corpus assigns an alignment from script, so nothing else can move.
    private nonisolated static func carryAlignedPieces(
        through delta: WMPSize, at canvas: WMPSize,
        aligned: inout [WMPScenePropertyAddress: WMPSize],
        overrides: inout WMPSceneOverrides,
        assigned: inout [WMPScenePropertyAddress: WMPSize],
        geometry: [Int: WMPRect], skin: WMPLoadedSkin
    ) {
        guard delta.width != 0 || delta.height != 0 else { return }
        for (address, _) in aligned {
            let horizontal = address.property == "horizontalalignment"
            let amount = horizontal ? delta.width : delta.height
            guard amount != 0,
                  let alignment = overrides.properties[address]?.string.map({
                      horizontal ? WMPAxisAlignment(horizontal: $0) : WMPAxisAlignment(vertical: $0)
                  }) else { continue }
            let origin = horizontal ? "left" : "top", extent = horizontal ? "width" : "height"
            // The piece's coordinate now: what the script has already written this transaction,
            // then the layout the view is currently drawn at, and finally the markup's own literal
            // — which is the only one a headless caller that passes no `geometry` can answer from.
            func current(_ property: String) -> CGFloat? {
                let key = WMPScenePropertyAddress(stableID: address.stableID, property: property)
                if let value = overrides.geometry[key] { return value }
                if let frame = geometry[address.stableID] {
                    switch property {
                    case "left": return frame.x
                    case "top": return frame.y
                    case "width": return frame.width
                    default: return frame.height
                    }
                }
                guard let node = skin.graph.allNodes.first(where: { $0.stableID == address.stableID })
                else { return nil }
                return WMPNumber.literal(node.attribute(named: property))
            }
            func move(_ property: String, by amount: CGFloat) {
                guard let value = current(property) else { return }
                let key = WMPScenePropertyAddress(stableID: address.stableID, property: property)
                overrides.geometry[key] = max(0, value + amount)
                assigned[key] = canvas
            }
            switch alignment {
            case .leading: break
            case .center: move(origin, by: amount / 2)
            case .trailing: move(origin, by: amount)
            case .stretch: move(extent, by: amount)
            }
            aligned[address] = canvas
        }
    }

    /// The size a transaction's script gave the view, or nil when it gave it none.
    ///
    /// Keyed off the **mutations**, not off `overrides.geometry`: an expression-driven
    /// `<VIEW width="jscript:…">` re-resolves on every transaction and is not a request to resize
    /// the window — it is a layout that already read the window's current size. Only an explicit
    /// assignment counts, which is what a compact-mode toggle is. A non-positive result is not a
    /// size: 34 corpus skins collapse a store-thumbnail `previewView` with `view.width = 0` before
    /// redirecting, and that view is one the controller declines to make a window out of.
    ///
    /// **One axis is a resize.** This used to demand an override for *both*, so a handler that grew
    /// only its width returned nil and the window never moved — and no headless probe could see it,
    /// because a render dump rebuilds the scene straight from the overrides and the canvas grows
    /// there whether or not this answers. `Compact`'s two drawers are exactly that shape
    /// (`view.width += rightMove` for one, `view.height += bottomMove` for the other): both slid
    /// open correctly in every capture and neither moved the window on screen (W186). The axis the
    /// script left alone is the window's current one, which is the user's.
    nonisolated static func assignedViewSize(skin: WMPLoadedSkin, viewID: String,
                                             plan: WMPScriptViewPlan,
                                             mutations: [WMPJScriptMutation],
                                             overrides: WMPSceneOverrides,
                                             currentSize: WMPSize) -> WMPSize? {
        guard let root = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node else { return nil }
        var width: CGFloat?, height: CGFloat?
        for mutation in mutations
        where plan.idToStableID[WMPPath.fold(mutation.targetID)] == root.stableID {
            guard let value = mutation.value.number, value.isFinite else { continue }
            switch mutation.property.lowercased() {
            case "width": width = CGFloat(value)
            case "height": height = CGFloat(value)
            default: continue
            }
        }
        guard width != nil || height != nil else { return nil }
        // **The axis this transaction did not assign is the window's current one, never the one
        // left in the overrides.** Those are cumulative: `Compact`'s playlist drawer writes 601 into
        // the root's width and it stays there for the session, so a later handler that touched only
        // the *height* — opening the settings drawer — re-asserted that stale 601 and yanked a
        // window the user had since stretched back to it. Reported as "the right side drawer keeps
        // stretching the window and releasing the stretch" (W188).
        let size = WMPSize(width: width ?? currentSize.width, height: height ?? currentSize.height)
        guard size.width > 0, size.height > 0 else { return nil }
        return size
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
        }) else {
            return false
        }
        // **The authored video box is optional, because for half the corpus there isn't one.**
        // A `<VIDEO>` sized `width="jscript:centerBox.width"` off a *sibling* rather than off the
        // view resolves to no literal here, and requiring it made the whole test answer false: 31
        // of the archives that size their window from the decoder — `xsn_sports`, `Blinx`, the
        // XBOX family, `Plus! SlimLine` — were never recognised at all and survived only by being
        // clamped to the display. The shell formula needs the box; the zoom formula does not.
        let box = authoredVideoSize(of: video, authoredViewSize: authoredViewSize)
        return WMPVideoPresentation.isMediaDrivenViewSize(assigned,
            authoredViewSize: authoredViewSize, authoredVideoSize: box, source: source)
    }

    /// The size the markup states for a view, per axis: its literal, else its declared floor.
    ///
    /// **The floor is not a fallback for tidiness — for two archives it is the only number there
    /// is.** `Official_Xbox` authors `<VIEW id="videoBox" width="player.currentMedia.\
    /// imageSourceWidth+91" height="400" minWidth="398" minHeight="400">`: the *markup itself* is
    /// decoder-driven, so a literal-only read answered nil, the decoder test never ran, and its
    /// `SnapToVideo()` (`x + 91` / `y + 179`, the same shape as 80 other archives) survived to
    /// become a full-screen window on a 1440p clip.
    private nonisolated static func authoredSize(of node: WMPNode) -> WMPSize? {
        func dimension(_ name: String, floor: String) -> CGFloat? {
            if let literal = WMPNumber.literal(node.attribute(named: name)), literal > 0 {
                return literal
            }
            guard let declared = WMPNumber.literal(node.attribute(named: floor)), declared > 0 else {
                return nil
            }
            return declared
        }
        guard let width = dimension("width", floor: "minWidth"),
              let height = dimension("height", floor: "minHeight") else { return nil }
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
                                                 preferences: preferences.values(), event: event,
                                                 screen: screen)
        var diagnostics = result.diagnostics
        diagnostics.append(contentsOf: preferences.apply(result.preferenceWrites))
        return WMPScriptOutput(overrides: .empty, hostCommands: result.hostCommands,
                               diagnostics: diagnostics, timerRequests: result.timers,
                               clearedTimerTokens: result.clearedTimers,
                               calls: result.calls)
    }

    func resetPreferences() { preferences.reset() }

    /// Elements the pointer is dragging. See `WMPPropertyRegistry.changes(for:origin:holding:)`.
    private var heldElements: Set<Int> = []

    func holdElement(stableID: Int) { heldElements.insert(stableID) }
    func releaseElement(stableID: Int) { heldElements.remove(stableID) }

    func setWidgetValue(stableID: Int, value: Double, viewID: String) {
        guard value.isFinite else { return }
        let scope = WMPPath.fold(viewID)
        var stored = overrides(for: scope)
        stored.properties[.init(stableID: stableID, property: "value")] = .number(value)
        committedOverrides[scope] = stored
        context?.setElementValue(stableID: stableID, value: value)
    }

    /// **A sticky button's latch, as the pointer left it (W206).** WMP flips a `sticky="true"`
    /// button's `down` on mouse-up *before* it raises the `onClick`, and the corpus's drawer idiom
    /// reads it straight back: `anemone`'s playlist and audio-controls buttons are
    /// `onclick="setVisibility('openPlaylist')"` over `if(plb.down == true){…open…}else{…close…}`.
    /// The latch lived only in `WMPInteractionState` — the artwork's state, never the script's — so
    /// `plb.down` answered its authored value on every press, the handler took its `else` branch
    /// every time, and neither drawer could be opened while both buttons drew themselves down.
    /// Committed as an override as well as into the live element so the *artwork* follows a script
    /// that writes the latch back (`setVisibility('closePlaylist')` clears it from inside the tray).
    func setWidgetDown(stableID: Int, down: Bool, viewID: String) {
        let scope = WMPPath.fold(viewID)
        var stored = overrides(for: scope)
        stored.properties[.init(stableID: stableID, property: "down")] = .bool(down)
        committedOverrides[scope] = stored
        context?.setElementDown(stableID: stableID, down: down)
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
    /// **The release that ends a `view.size(corner)` drag (W225).** Replays the half of the handler
    /// that WMP would have run when its own call returned — `Compact`'s unpin of both drawers and
    /// the `DoSnapToSize()` behind it — against the size the window actually finished at, which is
    /// the canvas those writes are meant to be measured from. Answers `nil` when the transaction
    /// held nothing, which is every grip in the corpus whose handler is the call and nothing else.
    ///
    /// The controller calls this on mouse-up **and** when the drag never started, so a bracket can
    /// never be stranded half-applied.
    func resumeAfterWindowResize(skin: WMPLoadedSkin, viewID: String, size: WMPSize,
                                 snapshot: WMPHostSnapshot,
                                 geometry: [Int: WMPRect] = [:]) async -> WMPScriptOutput? {
        let scope = WMPPath.fold(viewID)
        guard let held = deferredResizeMutations.removeValue(forKey: scope), !held.isEmpty
        else {
            wmpResizeTrace("resume \(viewID): nothing held")
            return nil
        }
        wmpResizeTrace("resume \(viewID) at \(size.width)x\(size.height): \(held.count) writes")
        return await transact(skin: skin, viewID: viewID, size: size, snapshot: snapshot,
                              event: nil, geometry: geometry, animatesTweens: true,
                              injecting: held)
    }

    /// Which programs each view's **own** `scriptFile` names, folded id to resolved path, in the
    /// order the attribute writes them. `WMPLoadedSkin.scripts` is the skin-wide set and dedupes by
    /// resolved path, so it cannot answer this on its own; the view node still carries the
    /// attribute it was registered from. Consumed by `WMPScriptContext.applyFunctionScope` (W257).
    nonisolated static func viewScriptPaths(in skin: WMPLoadedSkin) -> [String: [String]] {
        var resolved: [String: String] = [:]
        for registration in skin.scripts {
            guard let path = registration.resolvedPath else { continue }
            resolved[WMPPath.fold(registration.authoredPath)] = path
        }
        var paths: [String: [String]] = [:]
        for view in skin.views {
            guard let raw = view.node.attribute(named: "scriptFile")?.rawValue else { continue }
            let declared = raw.split(separator: ";").compactMap { item -> String? in
                let authored = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !authored.isEmpty else { return nil }
                return resolved[WMPPath.fold(authored)]
            }
            guard !declared.isEmpty else { continue }
            paths[WMPPath.fold(view.id)] = declared
        }
        return paths
    }

    func discardView(_ viewID: String) {
        let scope = WMPPath.fold(viewID)
        committedOverrides.removeValue(forKey: scope)
        committedExpressions.removeValue(forKey: scope)
        scriptAssignedGeometry.removeValue(forKey: scope)
        scriptAssignedAlignment.removeValue(forKey: scope)
        deferredResizeMutations.removeValue(forKey: scope)
        scriptAlignmentExtent.removeValue(forKey: scope)
        propertyRegistries.removeValue(forKey: scope)
        activeTweens.removeValue(forKey: scope)
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
        committedExpressions.removeAll()
        scriptAssignedGeometry.removeAll()
        scriptAssignedAlignment.removeAll()
        deferredResizeMutations.removeAll()
        scriptAlignmentExtent.removeAll()
        propertyRegistries.removeAll()
        activeTweens.removeAll()
    }
}
