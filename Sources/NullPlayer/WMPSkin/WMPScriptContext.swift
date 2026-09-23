import Darwin
import Foundation
import JavaScriptCore

/// Everything the script pass needs to know about one view, derived from the retained graph off the
/// main actor. The element *definitions* are values: the live `WMPScriptElement` objects are made
/// once per view inside the context and keep their state for the whole session, which is what makes
/// a second click able to undo the first.
struct WMPScriptElementDefinition: Sendable {
    let id: String
    let stableID: Int
    let kind: WMPElementKind
    let properties: [String: WMPJSONValue]
    let authored: Set<String>
    /// Extra names this element answers to. The view is reachable as both `view` and its authored
    /// id, because the corpus uses both spellings in the same file.
    let aliases: [String]
}

struct WMPScriptViewPlan: Sendable {
    let viewID: String
    let elements: [WMPScriptElementDefinition]
    let expressions: [WMPScriptExpression]
    /// Lowercased `id.property` to the scene address the resolved value commits to.
    let expressionAddresses: [String: WMPScenePropertyAddress]
    /// Folded element id to stable graph id.
    let idToStableID: [String: Int]
    /// `stableID -> attribute -> handler source`, from the `<attribute>_onchange` attributes the
    /// SDK defines for every attribute of most elements (W129). Kept as its own map rather than
    /// looked up through the element because these are `.handler` attributes, so they are not in
    /// the element's property bag at all.
    ///
    /// It began as the four geometry properties — a skin keeping a dependent pane glued to one it
    /// moves (W87) — and is general because the mechanism is: `textWidth_onchange` and
    /// `selectedItem_onchange` are the same shape on the same elements. `value` is deliberately
    /// **not** here: it has its own map and its own two directions (W51/W52), and collecting it
    /// twice would raise it twice in one transaction.
    let attributeChangeHandlers: [Int: [String: WMPAmbientChangeHandler]]
    /// `stableID -> completion event -> handler source`, from the `onEndMove`/`onEndAlphaBlend`
    /// attributes a skin chains an animation sequence from (W55). Same shape and same reason as
    /// `attributeChangeHandlers`: these are `.handler` attributes, so they are not in the element's
    /// property bag.
    let completionHandlers: [Int: [String: String]]
    /// `stableID -> handler source`, from the `value_onchange`/`onChange` attribute a control uses
    /// to repaint whatever it drives. Same shape and reason as the two maps above (W51).
    let valueChangeHandlers: [Int: String]

    init(skin: WMPLoadedSkin, viewID: String) {
        self.viewID = viewID
        guard let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node else {
            elements = []; expressions = []; expressionAddresses = [:]; idToStableID = [:]
            attributeChangeHandlers = [:]; completionHandlers = [:]; valueChangeHandlers = [:]
            return
        }
        var included = Set<Int>()
        func include(_ node: WMPNode) { included.insert(node.stableID); node.children.forEach(include) }
        include(view)

        var definitions: [WMPScriptElementDefinition] = []
        var expressions: [WMPScriptExpression] = []
        var addresses: [String: WMPScenePropertyAddress] = [:]
        var ids: [String: Int] = [:]
        var changeHandlers: [Int: [String: WMPAmbientChangeHandler]] = [:]
        var completions: [Int: [String: String]] = [:]
        var valueChanges: [Int: String] = [:]
        for node in skin.graph.allNodes where included.contains(node.stableID) {
            let id = node === view ? "view" : (node.xmlID ?? "node\(node.stableID)")
            ids[WMPPath.fold(id)] = node.stableID
            var properties: [String: WMPJSONValue] = [:]
            var authored = Set<String>()
            for attribute in node.attributes {
                let name = attribute.name.lowercased()
                authored.insert(name)
                switch attribute.value {
                case let .literal(raw): properties[name] = Self.scalar(raw)
                case let .color(color): properties[name] = .string(color.description)
                case let .resource(path), let .unsupported(path): properties[name] = .string(path)
                case let .jScript(source) where WMPScriptExpression.geometryProperties.contains(name):
                    let key = "\(id).\(name)"
                    expressions.append(.init(key: key, source: source))
                    addresses[key.lowercased()] = .init(stableID: node.stableID, property: name)
                case let .binding(kind, source)
                    where kind == .property && WMPScriptExpression.geometryProperties.contains(name):
                    let key = "\(id).\(name)"
                    expressions.append(.init(key: key, source: source))
                    addresses[key.lowercased()] = .init(stableID: node.stableID, property: name)
                // `value_onchange` is the spelling 175 of 179 archives use and `onChange` is the
                // other; the app's own matcher accepts both for `change`, so both are collected
                // here rather than a second rule being invented (W51). **It is matched before the
                // general `_onchange` rule below**, which would otherwise claim it as an ambient
                // attribute handler and raise it a second time in the same transaction.
                case let .handler(event, source)
                    where ["value_onchange", "onchange", "change"].contains(event.lowercased()):
                    valueChanges[node.stableID] = source
                case let .handler(event, source) where event.lowercased().hasSuffix("_onchange")
                    && event.count > "_onchange".count:
                    let attribute = String(event.dropLast("_onchange".count))
                    changeHandlers[node.stableID, default: [:]][attribute.lowercased()] =
                        .init(attribute: attribute, source: source)
                case let .handler(event, source)
                    where Self.completionEvents.contains(event.lowercased()):
                    completions[node.stableID, default: [:]][
                        String(event.lowercased().dropFirst(2))] = source
                default: break
                }
            }
            let aliases = node === view && node.xmlID != nil ? [node.xmlID!] : []
            definitions.append(.init(id: id, stableID: node.stableID, kind: node.kind,
                                     properties: properties, authored: authored, aliases: aliases))
        }
        elements = definitions
        self.expressions = expressions
        expressionAddresses = addresses
        idToStableID = ids
        attributeChangeHandlers = changeHandlers
        completionHandlers = completions
        valueChangeHandlers = valueChanges
    }

    /// One ambient `<attribute>_onchange` handler: the **authored** spelling of the attribute
    /// beside its source. The spelling is carried rather than folded because the handler reads the
    /// attribute by its own name — 68 of the corpus's 77 `currentEffectType_onchange` uses are
    /// `mediacenter.effectType=currentEffectType`, and a bare name bound in the wrong case is a
    /// `ReferenceError` on the handler's first statement.
    struct WMPAmbientChangeHandler: Sendable {
        let attribute: String
        let source: String
    }

    /// Authored spellings of the two completion callbacks that have a dispatch site. `onEndResize`
    /// is not here because no archive in the corpus authors one.
    private static let completionEvents: Set<String> = ["onendmove", "onendalphablend"]

    private static func scalar(_ raw: String) -> WMPJSONValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("true") == .orderedSame { return .bool(true) }
        if trimmed.caseInsensitiveCompare("false") == .orderedSame { return .bool(false) }
        if let number = Double(trimmed), number.isFinite { return .number(number) }
        return .string(raw)
    }
}

struct WMPScriptExpression: Hashable, Sendable {
    let key: String
    let source: String

    static let geometryProperties: Set<String> = ["left", "top", "width", "height"]
}

struct WMPScriptRunResult: Sendable {
    var calls: [WMPJScriptCall] = []
    var mutations: [WMPJScriptMutation] = []
    var hostCommands: [WMPJScriptHostCommand] = []
    var preferenceWrites: [WMPJScriptPreferenceMutation] = []
    var repaintHints: [String] = []
    var diagnostics: [WMPJScriptDiagnostic] = []
    var expressions: [WMPJScriptExpressionResult] = []
    var expressionOrder: [String] = []
    var timers: [WMPJScriptTimerRequest] = []
    /// The tokens this transaction's script called `clearTimeout`/`clearInterval` on.
    ///
    /// **`timers` is what this one transaction registered, so the two are a delta and neither is
    /// the live set** (W119). A transaction that touched no timer at all reports both empty, which
    /// has to mean "nothing changed" rather than "there are none" — see
    /// `WMPMainWindowController.applyTimerDelta`.
    var clearedTimers: [Int] = []
    /// The tweens this transaction asked its caller to animate (W194). Only ever non-empty for a
    /// transaction run with `animatesTweens`; see `WMPObjectModel.tweenGroup`.
    var tweens: [WMPScriptTween] = []
    /// The view's own size at the end of the transaction, **clamped to the limits the builder
    /// will clamp the canvas to** (W99). `assignedViewSize` reads the raw mutations, which is the
    /// size the script *asked* for; this is the size it got. They differ exactly when the view
    /// declares a `minWidth`/`minHeight`/`maxWidth`/`maxHeight` its own script writes through.
    var drawnViewSize: WMPSize?
    /// How many mutations had been made when the handler called `view.size(corner)` (W225).
    /// `nil` when it never did. See `WMPObjectModel.resizeCallMutationIndex`.
    var resizeCallMutationIndex: Int?
}

/// The skin's JavaScript context: one per skin session, on one dedicated serial queue.
///
/// Everything reachable from skin code is installed here and nothing else is. `ActiveXObject`,
/// `WScript` and `Enumerator` are explicitly undefined, and JavaScriptCore's bare global object has
/// no file, network, timer or process API of its own — so the object model is the entire surface.
///
/// The queue is not decoration. A skin that loops forever would otherwise wedge whichever executor
/// thread it landed on; here it wedges its own, the app stays live, and the execution-time limit
/// below terminates it.
final class WMPScriptContext: @unchecked Sendable {
    private let queue: DispatchQueue
    private let context: JSContext
    private let model = WMPObjectModel()
    private let executionSeconds: TimeInterval
    private var timerFunctions: [Int: JSValue] = [:]
    private var pendingTimers: [WMPJScriptTimerRequest] = []
    private var pendingClearedTimers: [Int] = []
    private var nextTimerToken = 0
    private var lastException: String?
    /// The live elements of every view this session has installed, and which one is installed now.
    ///
    /// Two paths read this back. A background dispatcher swaps its own in for the length of a tick
    /// (`runBackground`), and every open window's transaction swaps its own in on the way past
    /// (`restoreElements(for:)`) — one `JSContext` serves them all, and every view root is called
    /// `view`, so a panel's transaction must not run against the player's objects.
    private var viewRegistries: [String: WMPObjectModel.ElementRegistry] = [:]
    /// Every declared view's element definitions, from `prepare`. Kept so `discardElements` can
    /// hand a view back its markup state instead of deleting it out of the cross-view fallback.
    private var preparedDefinitions: [String: [WMPScriptElementDefinition]] = [:]
    private var installedViewID: String?
    /// Hashes of sources whose call sites have already been offered to `aliasCaseFoldedGlobals` —
    /// a handler on a timer is evaluated hundreds of times and the scan answers the same thing
    /// every time. Hashes rather than sources: a program is up to 4 MiB and this lives for the
    /// session. Bounded, because nothing stops a skin evaluating a string it just built.
    private var scannedCallSites: Set<Int> = []
    /// True only while `load` is evaluating the skin's programs. A program's call sites are scanned
    /// *after* the whole set has run, never before: the name a call needs is usually declared
    /// further down the same file.
    private var isLoadingPrograms = false
    /// The top-level functions each program defined or redefined, by resolved script path (W257).
    private var programFunctions: [String: [String: JSValue]] = [:]
    /// The exact names more than one program defines — the only ones a view scope rebinds.
    private var contestedFunctions: Set<String> = []
    /// Folded view id to the resolved paths of the scripts that view's own `scriptFile` names.
    private var viewScriptPaths: [String: [String]] = [:]
    /// Case-folded call-site alias to the global it was installed from, so a rebound function
    /// takes its aliases with it.
    private var installedAliases: [String: String] = [:]

    init(executionSeconds: TimeInterval = WMPPhase0Limits.scriptExecutionSeconds) {
        self.executionSeconds = executionSeconds
        queue = DispatchQueue(label: "com.nullplayer.wmp.script", qos: .userInitiated)
        context = JSContext(virtualMachine: JSVirtualMachine())!
        queue.sync { install() }
    }

    // MARK: Loading

    /// Evaluates the skin's own programs once, in declaration order. Their globals live for the
    /// session, which is the whole point: a handler and a geometry expression must see the same
    /// `g_paneCurrent`.
    ///
    /// `viewScripts` says which of those programs each view's own `scriptFile` names, and is what
    /// makes a name two programs both define resolve per view (`applyFunctionScope`, W257).
    func load(scripts: [String: String], order: [WMPScriptRegistration],
              viewScripts: [String: [String]] = [:]) -> [WMPJScriptDiagnostic] {
        queue.sync {
            var diagnostics: [WMPJScriptDiagnostic] = []
            var evaluated = Set<String>()
            viewScriptPaths = viewScripts
            programFunctions = [:]
            contestedFunctions = []
            isLoadingPrograms = true
            for registration in order {
                guard let path = registration.resolvedPath, let source = scripts[path],
                      evaluated.insert(path).inserted else { continue }
                let before = globalFunctions()
                if let error = evaluate(source, label: registration.authoredPath) {
                    diagnostics.append(.init(code: "script-error",
                                             message: "\(registration.authoredPath): \(error)"))
                }
                var defined: [String: JSValue] = [:]
                for (name, value) in globalFunctions()
                where !(before[name]?.isEqual(to: value) ?? false) {
                    defined[name] = value
                    if programFunctions.contains(where: { $0.value[name] != nil }) {
                        contestedFunctions.insert(name)
                    }
                }
                programFunctions[path] = defined
            }
            isLoadingPrograms = false
            for path in evaluated {
                guard let source = scripts[path] else { continue }
                aliasCaseFoldedGlobals(callSitesIn: source)
            }
            applyFunctionScope()
            return diagnostics
        }
    }

    /// `WMP_VIEW_SCRIPT_SCOPE=0` restores the pre-W257 binding, where the program evaluated last
    /// wins every call in every view. An A/B switch in the same binary rather than a baseline
    /// build: on `Plus! SlimLine` `=0` is the reported bounce and unset is the switch landing.
    static let viewFunctionScopeEnabled =
        ProcessInfo.processInfo.environment["WMP_VIEW_SCRIPT_SCOPE"] != "0"

    /// Every top-level function the global object currently holds, by exact name.
    ///
    /// An element global is a `Proxy` over a function target, so `typeof` calls it a function too;
    /// `__wmpPath` is what tells the two apart and is the one name the proxy answers for itself.
    private func globalFunctions() -> [String: JSValue] {
        let names = context.evaluateScript("""
        (function () {
            var found = [];
            var names = Object.getOwnPropertyNames(this);
            for (var i = 0; i < names.length; i++) {
                var value;
                try { value = this[names[i]]; } catch (e) { continue; }
                if (typeof value !== 'function') { continue; }
                if (value.__wmpPath) { continue; }
                found.push(names[i]);
            }
            return found;
        }).call(this);
        """)?.toArray() as? [String] ?? []
        var functions: [String: JSValue] = [:]
        for name in names {
            guard let value = context.objectForKeyedSubscript(name) else { continue }
            functions[name] = value
        }
        return functions
    }

    /// **A view's handlers run its own view's functions, not the last program's (W204/W257).**
    ///
    /// A `.wmz` has one script scope for the whole skin, so two views that each declare their own
    /// `scriptFile` and define the same top-level names silently collide: the program evaluated
    /// last wins every call, in both views. `Plus! SlimLine` is the reported case — `perfect.js`
    /// and `perfectV.js` each define `Init`, `savePrefs`, `switchSkin` and `EndVideo`, and the
    /// horizontal view therefore ran the *vertical* view's `Init`, whose `EndVideo()` calls
    /// `switchSkin('perfectVSkin')` and put the skin straight back where it came from. Reported
    /// 2026-09-22 as "when I click the recycle it switches and instantly switches back".
    ///
    /// **Only a contested name is rebound, and only for a view that names its own scripts.** A
    /// helper exactly one program defines is shared, which is what a skin whose views deliberately
    /// share one `.js` is relying on; a view declaring no `scriptFile` keeps whatever the skin's
    /// last program bound. Globals other than functions are untouched: they are one variable in one
    /// scope here as they are in the markup, and nothing in the corpus resolves a *value* per view.
    private func applyFunctionScope(for viewID: String? = nil) {
        guard Self.viewFunctionScopeEnabled, !contestedFunctions.isEmpty else { return }
        guard let key = (viewID.map { WMPPath.fold($0) } ?? installedViewID),
              let paths = viewScriptPaths[key], !paths.isEmpty else { return }
        var chosen: [String: JSValue] = [:]
        for path in paths {
            for (name, value) in programFunctions[path] ?? [:] where contestedFunctions.contains(name) {
                chosen[name] = value
            }
        }
        for (name, value) in chosen {
            context.setObject(value, forKeyedSubscript: name as NSString)
        }
        for (alias, real) in installedAliases {
            guard let value = chosen[real] else { continue }
            context.setObject(value, forKeyedSubscript: alias as NSString)
        }
    }

    /// Make every view's live elements exist and bind a global for each of their ids, once per skin
    /// session (W40).
    ///
    /// A `.wmz` has one script scope for the whole skin, so a function in the shared `.js` names
    /// whatever view's elements it was written for and is called from whichever view gets there
    /// first. Installing only the view on screen left those names unbound — `Official_Xbox_XP`'s
    /// `mainBox` hides `videoBox`'s `videoWin`, `portals`' `mode2` hides `mode1`'s `ripple_button`
    /// — and a bare unbound name is a `ReferenceError` that takes the rest of the handler with it.
    /// WMP has the theme's whole element tree from the moment the skin loads; this is that, and the
    /// fallback that reads through it is `WMPObjectModel.setOtherViewElements`.
    ///
    /// A view already in `viewRegistries` is left alone: this runs before the first `install`, so
    /// there is nothing to preserve yet, but a re-`prepare` must never discard accumulated state.
    /// Nothing here *runs* a view — no handler, no geometry expression — so a prepared view holds
    /// exactly its markup until its own transaction opens it.
    func prepare(views: [(id: String, elements: [WMPScriptElementDefinition])]) {
        queue.sync {
            let presented = installedViewID.map { _ in model.captureElements() }
            for view in views {
                let key = WMPPath.fold(view.id)
                preparedDefinitions[key] = view.elements
                guard viewRegistries[key] == nil else { continue }
                installElements(view.elements)
                viewRegistries[key] = model.captureElements()
            }
            if let presented { model.restoreElements(presented) } else { model.resetElements([]) }
            refreshOtherViews()
        }
    }

    /// A pristine registry for one view, built without disturbing the installed one.
    private func pristineRegistry(_ definitions: [WMPScriptElementDefinition])
        -> WMPObjectModel.ElementRegistry {
        let presented = model.captureElements()
        installElements(definitions)
        let built = model.captureElements()
        model.restoreElements(presented)
        return built
    }

    func install(elements definitions: [WMPScriptElementDefinition], for viewID: String) {
        queue.sync {
            stashInstalled()
            installElements(definitions)
            installedViewID = WMPPath.fold(viewID)
            refreshOtherViews()
            applyFunctionScope()
        }
    }

    /// Put a covered view's own live elements back, and say whether this session still had them.
    /// A `false` answer means the caller must `install` from the plan instead — which, once
    /// `prepare` has run, is only a view the skin does not declare.
    func restoreElements(for viewID: String) -> Bool {
        queue.sync {
            guard let cached = viewRegistries[WMPPath.fold(viewID)] else { return false }
            stashInstalled()
            model.restoreElements(cached)
            installedViewID = WMPPath.fold(viewID)
            refreshOtherViews()
            applyFunctionScope()
            return true
        }
    }

    /// Forget a view's accumulated state. Its window has closed, or `theme.currentViewID` has
    /// replaced it — either way the next time this id is opened it starts from its markup again.
    ///
    /// **It resets the view rather than deleting it, because the theme still has it (W40).** A
    /// `theme.currentViewID` switch discards *both* views — the one leaving and the one arriving,
    /// `WMPMainWindowController.switchView` — so deleting took the arriving view's own elements and
    /// the departing view's out of the cross-view fallback in the same breath. `Plus! SlimLine`
    /// is the case: switching back to `perfectSkin` ran its `Init()` against a session that no
    /// longer had `perfectV_pl`, so it threw exactly as it did before the fallback existed and the
    /// view came back with no title bar and no progress bar. Reported live 2026-09-22 as *"the left
    /// button does not work in vertical mode, you get stuck in horizontal mode"*. In WMP the
    /// theme's element tree outlives any one window, and a rebuilt registry is what `install` would
    /// have produced from the plan — the same definitions, none of the state.
    func discardElements(for viewID: String) {
        queue.sync {
            let key = WMPPath.fold(viewID)
            if let definitions = preparedDefinitions[key] {
                viewRegistries[key] = pristineRegistry(definitions)
            } else {
                viewRegistries.removeValue(forKey: key)
            }
            if installedViewID == key { installedViewID = nil }
            refreshOtherViews()
        }
    }

    private func stashInstalled() {
        guard let installedViewID else { return }
        viewRegistries[installedViewID] = model.captureElements()
    }

    /// Hand the model every live view's elements but the one installed, so `element:<id>` can fall
    /// back out of the current view without ever shadowing it (W40).
    private func refreshOtherViews(current: String? = nil) {
        let key = current ?? installedViewID
        model.setOtherViewElements(viewRegistries.compactMap { $0.key == key ? nil : $0.value })
    }

    private func installElements(_ definitions: [WMPScriptElementDefinition]) {
        model.resetElements(definitions.map {
            WMPScriptElement(id: $0.id, stableID: $0.stableID, kind: $0.kind,
                             properties: $0.properties, authored: $0.authored)
        })
        for definition in definitions {
            bind(global: definition.id, to: "element:\(WMPPath.fold(definition.id))")
            for alias in definition.aliases {
                model.elements[WMPPath.fold(alias)] = model.element(definition.id)
                bind(global: alias, to: "element:\(WMPPath.fold(definition.id))")
            }
        }
        // The host objects win any name collision with an element id: a skin naming an element
        // `player` still means the player when it writes `player.controls.play()`.
        bindHostGlobals()
    }

    /// The items every list-like element currently holds, by stable id. A skin fills a `POPUP`
    /// from script — all four corpus popups are equaliser preset menus built in an `onLoad` — so
    /// this is the only source the AppKit menu has.
    func listItems() -> [Int: [String]] {
        var items: [Int: [String]] = [:]
        for element in model.elements.values where !element.items.isEmpty {
            items[element.stableID] = element.items
        }
        return items
    }

    func setElementValue(stableID: Int, value: Double) {
        queue.sync {
            guard let element = model.elements.values.first(where: { $0.stableID == stableID })
            else { return }
            element.properties["value"] = .number(value)
        }
    }

    /// A sticky button's latch, as the *pointer* left it. See `WMPScriptRuntime.setWidgetDown`.
    func setElementDown(stableID: Int, down: Bool) {
        queue.sync {
            guard let element = model.elements.values.first(where: { $0.stableID == stableID })
            else { return }
            element.properties["down"] = .bool(down)
        }
    }

    /// An `<EDITBOX>`'s text. `value` on an edit box is a string, not a number, and the skin's
    /// `onKeyUp` handler reads it straight back — `plSearchEdit.value` is what nine of the ten
    /// corpus edit boxes search on.
    func setElementText(stableID: Int, text: String) {
        queue.sync {
            guard let element = model.elements.values.first(where: { $0.stableID == stableID })
            else { return }
            element.properties["value"] = .string(text)
        }
    }

    func teardown() {
        queue.sync {
            timerFunctions.removeAll()
            pendingTimers.removeAll()
            pendingClearedTimers.removeAll()
            viewRegistries.removeAll()
            preparedDefinitions.removeAll()
            installedViewID = nil
            model.resetElements([])
            model.setOtherViewElements([])
        }
    }

    // MARK: Running a transaction

    func run(plan: WMPScriptViewPlan, size: WMPSize, snapshot: WMPHostSnapshot,
             preferences: [String: String], event: WMPJScriptEvent?,
             geometry: [Int: WMPRect],
             boundValues: [Int: WMPJSONValue] = [:],
             retiredGeometry: Set<WMPScenePropertyAddress> = [],
             screen: WMPSize = WMPObjectModel.defaultScreen,
             usableScreen: WMPSize = WMPObjectModel.defaultScreen,
             animatesTweens: Bool = false,
             tweenFrame: WMPTweenFrame? = nil) async -> WMPScriptRunResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: perform(plan: plan, size: size, snapshot: snapshot,
                                                       preferences: preferences, event: event,
                                                       geometry: geometry, boundValues: boundValues,
                                                       retiredGeometry: retiredGeometry,
                                                       screen: screen,
                                                       usableScreen: usableScreen,
                                                       animatesTweens: animatesTweens,
                                                       tweenFrame: tweenFrame))
            }
        }
    }

    /// One transaction for a view that is **not** the one on screen.
    ///
    /// 24 of the 180 corpus archives — the whole Alienware/Skins Factory family and every skin
    /// built from its template — author a windowless `controlView` polling at 100 ms, and route
    /// their panel, minimize and close buttons through it: the button writes a preference and this
    /// handler is what reads it back and acts (W89). It is a real open window in WMP; here it is a
    /// view that never becomes one, so it runs on its own timer with its own elements swapped in
    /// for the length of the call and the presented view's swapped back afterwards, objects and
    /// all. Nothing it produces describes the drawing: the caller wants its host commands.
    ///
    /// `currentViewID` is the view the *user* is looking at, not this one — a script asking
    /// `theme.currentViewID` from a dispatcher means the window, and answering `controlView` would
    /// name something that is not on screen.
    func runBackground(plan: WMPScriptViewPlan, currentViewID: String, snapshot: WMPHostSnapshot,
                       preferences: [String: String], event: WMPJScriptEvent,
                       screen: WMPSize = WMPObjectModel.defaultScreen) async -> WMPScriptRunResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let presented = model.captureElements()
                if let cached = viewRegistries[WMPPath.fold(plan.viewID)] {
                    model.restoreElements(cached)
                } else {
                    installElements(plan.elements)
                }
                refreshOtherViews(current: WMPPath.fold(plan.viewID))
                applyFunctionScope(for: plan.viewID)
                let result = perform(plan: plan, size: WMPSize(width: 0, height: 0),
                                     snapshot: snapshot, preferences: preferences, event: event,
                                     geometry: [:], currentViewID: currentViewID, screen: screen)
                viewRegistries[WMPPath.fold(plan.viewID)] = model.captureElements()
                model.restoreElements(presented)
                refreshOtherViews()
                applyFunctionScope()
                continuation.resume(returning: result)
            }
        }
    }

    private func perform(plan: WMPScriptViewPlan, size: WMPSize, snapshot: WMPHostSnapshot,
                         preferences: [String: String], event: WMPJScriptEvent?,
                         geometry: [Int: WMPRect], currentViewID: String? = nil,
                         boundValues: [Int: WMPJSONValue] = [:],
                         retiredGeometry: Set<WMPScenePropertyAddress> = [],
                         screen: WMPSize = WMPObjectModel.defaultScreen,
                         usableScreen: WMPSize = WMPObjectModel.defaultScreen,
                         animatesTweens: Bool = false,
                         tweenFrame: WMPTweenFrame? = nil) -> WMPScriptRunResult {
        model.beginTransaction(snapshot: snapshot, preferences: preferences,
                               viewID: currentViewID ?? plan.viewID, screen: screen,
                               modifiers: event?.modifiers ?? [], keyCode: event?.keyCode)
        model.animatesTweens = animatesTweens
        pendingTimers.removeAll()
        pendingClearedTimers.removeAll()
        // Sync the element state to the layout the skin is drawn at. The scene was built with the
        // previous transaction's overrides, so this is the skin's own values where it set them and
        // the resolved truth — artwork size, alignment stretch — everywhere else.
        if !geometry.isEmpty {
            for element in model.elements.values {
                guard let frame = geometry[element.stableID] else { continue }
                element.properties["left"] = .number(Double(frame.x))
                element.properties["top"] = .number(Double(frame.y))
                element.properties["width"] = .number(Double(frame.width))
                element.properties["height"] = .number(Double(frame.height))
            }
        }
        // **A control the host moved has to *read* as moved before any handler runs (W51).** The
        // value of a `wmpprop:`-bound slider lives in the scene's overrides, so the element model
        // never had it: `seek.value` answered the markup's, which for the corpus's seek bars is
        // nothing at all. This is the same sync the geometry block above is, for the same reason —
        // the transaction's starting state is what the skin is currently drawn at.
        for (stableID, value) in boundValues {
            guard let element = model.elements.values.first(where: { $0.stableID == stableID })
            else { continue }
            element.properties["value"] = value
        }
        if let view = model.element("view") {
            view.properties["width"] = .number(Double(size.width))
            view.properties["height"] = .number(Double(size.height))
            view.properties["left"] = .number(0)
            view.properties["top"] = .number(0)
        }

        // **The frame is written before the expressions, not after.** A `.wmz` positions one pane
        // off another — `top="wmpprop:plLeftCenter.top"` — and an expression resolved against last
        // frame's value would leave the dependent pane one frame behind the pane it is glued to,
        // which is W87 in miniature and visible as a tearing drawer. The writes become mutations,
        // so the runtime commits them over the expression's answer for the same reason a handler's
        // assignment wins.
        if let tweenFrame {
            for write in tweenFrame.writes {
                model.applyTweenFrame(targetID: write.targetID, property: write.property,
                                      value: write.value)
            }
            for completion in tweenFrame.completions {
                model.completeTween(stableID: completion.stableID, event: completion.event)
            }
        }

        var result = WMPScriptRunResult()
        let ordered = resolveExpressions(plan: plan, into: &result,
                                         retiredGeometry: retiredGeometry)
        result.expressionOrder = ordered

        if let event {
            // **A control's event handler reads its own `value` as a bare name.** WMP evaluates a
            // handler against the element that raised it, and the corpus depends on it in exactly
            // one place worth paying for: 111 of the 141 `onDragEnd` sources are
            // `player.controls.currentPosition = value`, the seek commit on release (W55). Binding
            // the one identifier is deliberate rather than scoping the whole element — a bare
            // *assignment* like `toolTip='Seek'` (6 uses) creates a global and costs nothing either
            // way, so only reads were ever blocked, and `with(element)` would change name
            // resolution for every handler in the corpus to buy those six.
            // **The element that raised the event, by stable id where the markup named none
            // (W256).** `anemone`'s ten equaliser bands author no `id`, so both this binding and
            // the handler's own scope below were keyed on nil: the handler ran, `value` resolved to
            // the undefined global, and `eq.gainLevel1 = value` wrote null — the band never moved
            // and the thumb settled straight back onto the host's unchanged gain.
            let eventOwner = event.targetID.flatMap(model.element)
                ?? event.targetStableID.flatMap(model.element(stableID:))
            var boundEventValue = false
            if let value = eventOwner?.properties["value"] {
                context.setObject(Self.jsAny(value), forKeyedSubscript: "value" as NSString)
                boundEventValue = true
            }
            defer {
                // Cleared with the event that defined it: a bare `value` is a control's own
                // property, and leaving the last drag's number bound as a global would let an
                // unrelated later handler read a stale one instead of failing honestly.
                if boundEventValue { context.setObject(nil, forKeyedSubscript: "value" as NSString) }
            }
            for (index, handler) in event.handlers.enumerated() {
                // The event's own arguments, bound and then cleared exactly as `value` above is:
                // a stale `NewState` left standing as a global would be read by an unrelated later
                // handler instead of failing honestly.
                for (name, argument) in handler.arguments {
                    context.setObject(Self.jsAny(argument), forKeyedSubscript: name as NSString)
                }
                defer {
                    for name in handler.arguments.keys {
                        context.setObject(nil, forKeyedSubscript: name as NSString)
                    }
                }
                let source = handler.source
                // Fail closed per handler, never per session. A skin puts its whole startup in one
                // handler, so one missing member costs many unrelated features — and the demand
                // tally is what makes that visible. A session-wide kill switch made it invisible.
                if let error = invokeHandler(source, label: "\(event.name)[\(index)]",
                                             owner: eventOwner?.id) {
                    result.diagnostics.append(.init(code: "handler-error",
                                                    message: "\(event.name)[\(index)]: \(error)"))
                }
            }
        }

        // A tween started by a top-level program rather than by a handler has no handler boundary
        // to land on; this is it.
        model.flushPendingTweens()
        // Completions first: a chained step writes geometry, and those writes are what the
        // geometry cascade below exists to propagate. The other order would make a pane positioned
        // off a moved one trail it by a transaction, which is W87 again.
        raiseValueChangeHandlers(plan: plan, changes: boundValues, into: &result)
        raiseCompletionHandlers(plan: plan, into: &result)
        raiseAttributeChangeHandlers(plan: plan, into: &result)

        // **A handler that resizes its own view leaves every `view.width`/`view.height` expression
        // resolved against a size nothing is drawn at (W99).** Two separate reasons, one symptom,
        // and the fix for either alone makes the other worse.
        //
        // The expression pass runs before the handlers on purpose — a pane positioned off another
        // must see the frame that pane lands at rather than its markup — but the view's own size is
        // the one input a handler can change out from under a pass that has already read it.
        // `xsn_sports` authors `<view id="videoView" height="396">` and its `onLoad` writes
        // `view.height = 416` whenever the player has nothing to stop, so the scene is built at 416
        // while `top="jscript:view.height-221"` still answers 175. The entire bottom of the skin —
        // eight frame pieces, both drawer covers, `vidOutline` and the resize grip — sits 20 px
        // high until the view's own 500 ms timer opens a second transaction at the new size, and
        // then drops. Reported as the drawer's toggle button drifting out from under the pointer.
        //
        // **The other reason is that the builder can refuse the assignment, and only the builder
        // knew.** `canvas = resizeLimits.clamp(…)`, so a view declaring `minHeight` has a floor its
        // own script cannot write through: `ALXMorph` is `<view id="videoView" height="357"
        // minHeight="357">` and `onLoadVid()` assigns 316. The canvas stays 357 and the script goes
        // on answering 316, so `view.height-187` resolves 41 px above the window it is anchored to.
        // Re-resolving against the raw assignment rather than the clamped one is not a smaller
        // version of the fix, it is the defect with more reach: measured over 20 archives it walked
        // `Back to the Future Trilogy/videoView` out to x=-94 and `Plus! Professional/videoView` to
        // y=-8. So the clamp is applied to the view element itself, which is both what the next
        // transaction reads back and what these expressions now see.
        //
        // The limits are read from the view element's own properties, which is the same rule
        // `WMPSceneBuilder.viewLimit` applies from the other side — a script write first, then the
        // markup literal — because `WMPScriptViewPlan` seeds every authored attribute and a script
        // write lands on top of it. The fallback floor is the assigned size, matching the builder's
        // `?? defaultSize`: a view that declares no minimum cannot be clamped by one.
        //
        // **This is the first-transaction defect and nothing else.** A view with an `onTimer`
        // corrects itself on the next tick, which is why `xsn_sports` read as a flicker; 146 of the
        // 217 corpus views authoring this shape have no timer at all and never correct.
        if let viewElement = model.element("view"),
           let assignedWidth = viewElement.properties["width"]?.number,
           let assignedHeight = viewElement.properties["height"]?.number,
           assignedWidth.isFinite, assignedHeight.isFinite {
            func limit(_ name: String) -> Double? {
                guard let value = viewElement.properties[name]?.number,
                      value.isFinite, value >= 0 else { return nil }
                return value
            }
            // **The display is the last word, and it is applied after the view's own floor.** A
            // skin's `SnapToVideo()` sizes this view from the decoder, so a 2560x1440 clip asks
            // 84 corpus views for a window bigger than any desktop — see `WMPSize.fitted(within:)`.
            // The floor is the skin's and the ceiling is the machine's, so where a view declares a
            // `minWidth` larger than the screen the screen still wins: `min(max(…))` composed this
            // way lands on the ceiling, which is a window the user can still reach the edges of.
            let drawn = WMPSize(
                width: CGFloat(min(max(assignedWidth, limit("minwidth") ?? assignedWidth),
                                   limit("maxwidth") ?? .greatestFiniteMagnitude)),
                height: CGFloat(min(max(assignedHeight, limit("minheight") ?? assignedHeight),
                                    limit("maxheight") ?? .greatestFiniteMagnitude)))
                .fitted(within: usableScreen)
            if drawn.width != size.width || drawn.height != size.height {
                // The size the window is about to be, written back before anything reads it: the
                // clamp is the builder's answer, and a script that reads `view.height` after
                // assigning through a floor must get the height it actually got.
                viewElement.properties["width"] = .number(Double(drawn.width))
                viewElement.properties["height"] = .number(Double(drawn.height))
                // A handler's own geometry write still wins twice over: `WMPScriptRuntime` applies
                // this transaction's mutations to the overrides *after* the expression values, and
                // the addresses it wrote are retired here so a dependent reads the script's number
                // rather than the expression's.
                var retired = retiredGeometry
                for mutation in model.mutations {
                    guard let stableID = plan.idToStableID[WMPPath.fold(mutation.targetID)] else {
                        continue
                    }
                    retired.insert(WMPScenePropertyAddress(stableID: stableID,
                                                           property: mutation.property.lowercased()))
                }
                result.expressions.removeAll()
                result.expressionOrder = resolveExpressions(plan: plan, into: &result,
                                                            retiredGeometry: retired)
            }
            result.drawnViewSize = drawn
        }

        result.calls = model.calls
        result.mutations = model.mutations
        result.hostCommands = model.hostCommands
        result.preferenceWrites = model.preferenceWrites
        result.repaintHints = model.repaintHints
        result.diagnostics += model.diagnostics
        result.timers = pendingTimers
        result.clearedTimers = pendingClearedTimers
        result.tweens = model.tweens
        result.resizeCallMutationIndex = model.resizeCallMutationIndex
        return result
    }

    /// **A slider is bound both ways, so the *host* moving it raises `value_onchange` too (W51).**
    ///
    /// The user-driven half closed with W52 and this is the other direction, which is how a seek
    /// bar's readout follows playback and how a preset changing ten gains re-runs each band's
    /// handler. `Catwoman` is the case that named it: its clock is four digit filmstrips positioned
    /// by `value_onchange="drawSeekDigits(value)"` on a seek slider whose value the host owns, so
    /// with nothing raising the handler the slider tracked the song (W120) and the clock stayed on
    /// `00:00`. Measured over the corpus, **every one of the 19 handlers on a position-bound slider
    /// is a readout painter** — `drawSeekDigits(value)` ×17, `DrawTimeNormalView(value)`,
    /// `seek2.value=seek.value` — and none writes the position back, so this direction cannot
    /// re-seek. The write-backs elsewhere (`eq.gainLevel1=value`, `player.settings.volume = value`)
    /// are WMP's own idiom and settle: the registry only reports values that actually *moved*, so
    /// a handler writing back the number it was just given produces an identical snapshot and no
    /// further change.
    ///
    /// Bounded like both cascades beside it — only what the markup authored, only `value`, once per
    /// element per transaction — and it runs *before* them so a repaint that writes geometry still
    /// propagates through the W87 cascade in the same frame.
    private func raiseValueChangeHandlers(plan: WMPScriptViewPlan, changes: [Int: WMPJSONValue],
                                          into result: inout WMPScriptRunResult) {
        guard !changes.isEmpty, !plan.valueChangeHandlers.isEmpty else { return }
        for stableID in changes.keys.sorted() {
            guard let source = plan.valueChangeHandlers[stableID],
                  let value = changes[stableID] else { continue }
            // The bare `value` a control's handler reads, bound and cleared exactly as the event
            // path binds it: `drawSeekDigits(value)` is the whole of what these handlers are.
            context.setObject(Self.jsAny(value), forKeyedSubscript: "value" as NSString)
            defer { context.setObject(nil, forKeyedSubscript: "value" as NSString) }
            if let error = invokeHandler(source, label: "value_onchange",
                                         owner: ownerID(forStableID: stableID)) {
                result.diagnostics.append(.init(code: "handler-error",
                                                message: "value_onchange: \(error)"))
            }
        }
    }

    /// **An `<attribute>_onchange` fires in the same transaction as the write that triggered it.**
    ///
    /// The alternative — letting the dependent catch up on the next transaction — is what tore the
    /// compact view in half (W87). A `.wmz` animates by writing geometry once per timer tick, and a
    /// pane positioned off the moving one then trails it by a whole frame the entire way down; the
    /// *last* frame is the one that lasts, because the animation ends and nothing else runs until
    /// the skin's idle timer comes round. On `9SeriesDefault` that is four seconds of a window
    /// visibly split into two pieces, reported as exactly that.
    ///
    /// This raises only what the skin itself declared, which is the narrow half of the problem and
    /// the half WMP actually specifies: 16 attributes across 6 archives, of which both compact-mode
    /// skins author `height_onchange` on the panel they collapse. **W129 widened the property, not
    /// the rule** — the SDK defines the mechanism for every attribute of most elements, so the
    /// geometry filter that stood here is gone and a mutation of any attribute the markup declared
    /// a handler for raises it. The bound stays exactly where it was: only declared handlers, once
    /// per `(element, attribute)` per transaction. **It deliberately does not
    /// re-run the view's `JScript:` geometry expressions** — those are an initial layout, not a live
    /// binding, and re-resolving them after a handler was measured against the corpus and moved 175
    /// of 545 images, turning `Back to the Future Trilogy`'s `videoView` and `ALXMorph`'s frame into
    /// scattered fragments. The skin's own wiring is the mechanism; the expression set is not.
    ///
    /// Cascades are bounded and each handler fires at most once per transaction, so a pair of panes
    /// that position off one another cannot loop.
    private func raiseAttributeChangeHandlers(plan: WMPScriptViewPlan,
                                              into result: inout WMPScriptRunResult) {
        guard !plan.attributeChangeHandlers.isEmpty else { return }
        var consumed = 0
        var fired = Set<String>()
        for _ in 0..<WMPPhase0Limits.expressionPasses {
            let fresh = model.mutations[consumed...]
            consumed = model.mutations.count
            guard !fresh.isEmpty else { return }
            var raised = false
            for mutation in fresh {
                let property = mutation.property.lowercased()
                guard let stableID = plan.idToStableID[WMPPath.fold(mutation.targetID)],
                      let handler = plan.attributeChangeHandlers[stableID]?[property]
                else { continue }
                let token = "\(stableID).\(property)"
                guard fired.insert(token).inserted else { continue }
                raised = true
                // **The changing attribute is readable by its own name inside its handler**, the
                // way `value` is inside `value_onchange` and `NewState` is inside
                // `playstatechange`. Bound in the authored spelling and cleared with the handler,
                // so a stale one cannot be read by an unrelated later handler.
                context.setObject(Self.jsAny(mutation.value),
                                  forKeyedSubscript: handler.attribute as NSString)
                defer { context.setObject(nil, forKeyedSubscript: handler.attribute as NSString) }
                if let error = invokeHandler(handler.source, label: "\(property)_onchange",
                                             owner: mutation.targetID) {
                    result.diagnostics.append(.init(code: "handler-error",
                                                    message: "\(property)_onchange: \(error)"))
                }
            }
            if !raised { return }
        }
    }

    /// **`moveTo` and `alphaBlendTo` land their endpoint immediately, so their completion is now**
    /// (W55). WMP tweens over the call's third argument and raises `onEndMove`/`onEndAlphaBlend`
    /// when the tween finishes; this engine applies the endpoint in the call itself (W38), so the
    /// honest completion of an instant move is the same transaction. A skin chains its next step
    /// from these — `corona`'s playlist drawer is the case that named the row: `TogglePlaylist()`
    /// only calls `svPlaylist.moveTo(0, 33, PANEL_VELOCITY)`, and the list inside it is revealed
    /// solely by `onEndMove="ddpl.visible=ipl.visible=g_playlistIsVisible;"`. Without this the
    /// drawer opened onto nothing, which is the half of W97 the element kind could not reach.
    ///
    /// Bounded exactly as the geometry cascade is, and for the same reason: a completion handler
    /// may itself call `moveTo`, so each `(element, event)` fires at most once per transaction and
    /// the whole loop is capped. An animation that moves the same pane every tick still gets one
    /// completion per tick, because each tick is its own transaction.
    private func raiseCompletionHandlers(plan: WMPScriptViewPlan,
                                         into result: inout WMPScriptRunResult) {
        guard !plan.completionHandlers.isEmpty else { return }
        var consumed = 0
        var fired = Set<String>()
        for _ in 0..<WMPPhase0Limits.expressionPasses {
            let fresh = model.completions[consumed...]
            consumed = model.completions.count
            guard !fresh.isEmpty else { return }
            var raised = false
            for completion in fresh {
                guard let source = plan.completionHandlers[completion.stableID]?[completion.event]
                else { continue }
                let token = "\(completion.stableID).\(completion.event)"
                guard fired.insert(token).inserted else { continue }
                raised = true
                if let error = invokeHandler(source, label: "on\(completion.event)",
                                             owner: ownerID(forStableID: completion.stableID)) {
                    result.diagnostics.append(.init(code: "handler-error",
                                                    message: "on\(completion.event): \(error)"))
                }
            }
            if !raised { return }
        }
    }

    /// Two passes. The first measures what each expression reads, because the dependency order is a
    /// fact about the skin that only running it can tell you; the second evaluates in that order and
    /// commits each value before its dependents run.
    ///
    /// A failing expression costs itself and nothing else. The model this replaced returned an empty
    /// ordered list when any single expression failed, so one `ReferenceError` in one attribute left
    /// a whole skin with no computed geometry at all (W21).
    private func resolveExpressions(plan: WMPScriptViewPlan,
                                    into result: inout WMPScriptRunResult,
                                    retiredGeometry: Set<WMPScenePropertyAddress> = []) -> [String] {
        guard !plan.expressions.isEmpty else { return [] }
        var dependencies: [String: Set<String>] = [:]
        // Every read, not only the ones that happen to be expressions themselves: the ordering
        // graph needs the intersection, but the `EXPR` probe line needs to show what the
        // expression actually touched, which is how a wrong value gets traced back to its source.
        var reads: [String: [String]] = [:]
        var probeErrors: [String: String] = [:]
        let keys = Set(plan.expressions.map { $0.key.lowercased() })
        for expression in plan.expressions {
            model.beginDependencyCapture()
            let error = evaluateExpression(expression.source, owner: Self.owner(of: expression.key))
            let captured = model.endDependencyCapture()
            let key = expression.key.lowercased()
            if let error = error.1 { probeErrors[key] = error }
            let touched = captured.map { $0.lowercased() }
            reads[key] = Array(NSOrderedSet(array: touched).array as? [String] ?? touched)
            dependencies[key] = Set(touched).intersection(keys).subtracting([key])
        }

        var ordered: [String] = []
        var remaining = keys
        for _ in 0..<WMPPhase0Limits.expressionPasses {
            let ready = remaining.filter { dependencies[$0, default: []].isDisjoint(with: remaining) }.sorted()
            if ready.isEmpty { break }
            ordered += ready
            ready.forEach { remaining.remove($0) }
            if remaining.isEmpty { break }
        }
        if !remaining.isEmpty {
            // A cycle costs the keys inside it and nothing else; the rest of the view still lays out.
            result.diagnostics.append(.init(code: "dependency-cycle",
                                            message: remaining.sorted().joined(separator: ", ")))
        }

        let byKey = Dictionary(plan.expressions.map { ($0.key.lowercased(), $0) }) { first, _ in first }
        for key in ordered {
            guard let expression = byKey[key] else { continue }
            let (value, error) = evaluateExpression(expression.source,
                                                    owner: Self.owner(of: expression.key))
            if error == nil, let number = value?.number, number.isFinite,
               let address = plan.expressionAddresses[key] {
                // Commit before the dependents run: an expression reading a sibling's geometry must
                // see the value that sibling landed at, never its markup.
                //
                // **Except where the script has taken the address over (W159)** — then the value
                // the sibling landed at is the script's, which the geometry sync at the top of the
                // transaction has already put in the model, and writing the expression's answer
                // here would hand it to every dependent even though nothing draws it.
                // `NVIDIA`'s time readout is the case: retiring `mainModeMetadata.width` kept the
                // bar itself at the script's 464, and its children — `metadata.width` and the time
                // group's `left="jscript:mainModeMetadata.width-80"` — went on resolving against
                // the expression's 629 and drew 119 px past the window's right edge, which is the
                // defect this was supposed to close.
                if !retiredGeometry.contains(address) {
                    model.element(Self.owner(of: key))?.properties[address.property] = .number(number)
                }
            }
            result.expressions.append(.init(key: expression.key, value: value,
                                            dependencies: reads[key] ?? [],
                                            error: error ?? probeErrors[key]))
        }
        return ordered
    }

    // MARK: Evaluation

    private func evaluateExpression(_ source: String, owner: String? = nil) -> (WMPJSONValue?, String?) {
        lastException = nil
        // Authored geometry is a statement in the markup — `JScript:view.width-svMain.left;` — and
        // the trailing semicolon the corpus writes is a syntax error inside a `return (…)`.
        var trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(";") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // An expression is evaluated with its own element in scope. WMP resolves an unqualified
        // property against the object the attribute is on — Corona's `svBottomLeft.width-left`
        // means *this* element's `left` — and without the scope that reads as a ReferenceError and
        // the element gets no width at all.
        let scope = owner.map { "with (__wmpWrap('element:\($0)')) " } ?? ""
        let wrapped = "(function(){ \(scope){ return (\(trimmed)); } })()"
        let value = context.evaluateScript(wrapped)
        if let error = lastException { return (nil, error) }
        guard let value, !value.isUndefined, !value.isNull else { return (nil, "undefined") }
        return (Self.jsonValue(value), nil)
    }

    /// **A handler resolves an unqualified name against the element it is authored on (W216).**
    ///
    /// WMP puts that element at the front of the handler's scope chain, and the corpus writes
    /// against it both ways: `<EFFECTS onClick="previous();">` in 20 archives calls the element's
    /// own method, and 100 archives name one of its own properties bare — `player.settings.mute =
    /// down` on a sticky mute button (196 uses across 89 archives), `toolTip='Seek'` on release,
    /// `scrolling = textWidth > width` on a marquee. Without the scope a read throws
    /// `ReferenceError: Can't find variable: down` and the handler dies on that statement, while a
    /// write silently makes a global and never reaches the element.
    ///
    /// It is the same `with (__wmpWrap(...))` the geometry expressions are evaluated in, and it is
    /// safe here for the same reason it is safe there: `WMPObjectModel.recognises` — not the open
    /// property surface the read path answers with — decides whether a name belongs to the element
    /// or falls through to the globals, so an element cannot swallow the skin's own functions.
    ///
    /// The `value` and `<attribute>` globals the call sites bind stay: they are bound for the
    /// element that *raised* the event, which is not always the one the handler is written on.
    private func invokeHandler(_ source: String, label: String, owner: String? = nil) -> String? {
        // The handler boundary is where a tween's endpoint lands: WMP is animating for the
        // duration the call named, so the rest of *this* handler must still read the element where
        // it was. See `WMPObjectModel.tween(_:_:_:duration:)`.
        defer { model.flushPendingTweens() }
        if let token = WMPJScriptTimerRequest(token: 0, periodMilliseconds: 0, repeats: false,
                                              source: source).callbackToken {
            guard let function = timerFunctions[token] else { return nil }
            lastException = nil
            function.call(withArguments: [])
            return lastException
        }
        guard let owner, model.element(owner) != nil else { return evaluate(source, label: label) }
        // Not wrapped in a function: a handler's `var` is the skin's global, and the corpus holds
        // its state in exactly those — `corona`'s `g_playlistIsVisible` is declared in one handler
        // and read by every other. A `with` block keeps them where they were.
        let scope = "with (__wmpWrap('element:\(WMPPath.fold(owner))')) {\n\(source)\n}"
        return evaluate(scope, label: label)
    }

    /// The element a stable id names, as `invokeHandler`'s owner. The cascades below key their
    /// handlers by stable id because an element's *identifier* is not unique across views (W89).
    private func ownerID(forStableID stableID: Int) -> String? {
        model.elements.values.first(where: { $0.stableID == stableID })?.id
    }

    /// **A skin calls its own function in the wrong case, and the handler dies on that statement.**
    ///
    /// `elvis.js`'s `Init()` calls `UpdateMetaData()` and declares `UpdateMetadata`; `TDK.wms` binds
    /// `onLoad="onLoadVideo();"` against `function OnLoadVideo`. JavaScriptCore resolves a global by
    /// exact spelling, so the call throws `ReferenceError: Can't find variable: …` and every
    /// statement after it in that handler is lost — for `elvis` that is the whole of `Init` past
    /// line 17: the column modes, the volume slider's position and the video/visualization pane.
    /// 16 of the 184 installed archives hold one of these, including `Plus! HueShifter`, `TDK`,
    /// `portals`, `deepbluesomething` and the five-skin US military family.
    ///
    /// The alias is **last resort and never a fold**: it is installed only for a spelling that
    /// resolves to nothing at all, only when exactly one global case-folds to it, and only when
    /// that global is a function. Three archives (`Kids`, `Cablemusic`, `HOB`) declare two
    /// top-level names that differ only in case — `Kids` has both `StartVideo` and `startVideo`
    /// with different bodies — and every one of their call sites resolves exactly, so none of them
    /// reaches this path and an ambiguous fold is declined even if one did.
    ///
    /// Element ids cannot be aliased into: they are objects rather than functions.
    private func aliasCaseFoldedGlobals(callSitesIn source: String) {
        guard source.utf8.count <= WMPPhase0Limits.scriptBytes,
              scannedCallSites.count < 4096,
              scannedCallSites.insert(source.hashValue).inserted else { return }
        var candidates: Set<String> = []
        let scalars = Array(source.unicodeScalars)
        var index = 0
        func isStart(_ scalar: Unicode.Scalar) -> Bool {
            CharacterSet.letters.contains(scalar) || scalar == "_" || scalar == "$"
        }
        func isPart(_ scalar: Unicode.Scalar) -> Bool {
            isStart(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
        while index < scalars.count {
            guard isStart(scalars[index]) else { index += 1; continue }
            // A member call (`player.controls.play()`) belongs to the object model, not here.
            if index > 0, scalars[index - 1] == "." || isPart(scalars[index - 1]) {
                while index < scalars.count, isPart(scalars[index]) { index += 1 }
                continue
            }
            let start = index
            while index < scalars.count, isPart(scalars[index]) { index += 1 }
            var lookahead = index
            while lookahead < scalars.count, scalars[lookahead] == " " || scalars[lookahead] == "\t" {
                lookahead += 1
            }
            guard lookahead < scalars.count, scalars[lookahead] == "(" else { continue }
            var name = ""
            name.unicodeScalars.append(contentsOf: scalars[start..<index])
            guard !Self.jScriptKeywords.contains(name.lowercased()) else { continue }
            candidates.insert(name)
        }
        guard !candidates.isEmpty else { return }
        // A candidate is a JScript identifier by construction — letters, digits, `_` and `$` — so
        // there is nothing in it a string literal has to escape.
        let list = candidates.map { "\"\($0)\"" }.joined(separator: ",")
        // The pairs it installs come back so that `applyFunctionScope` can carry an alias with the
        // function it aliases when a view rebinds it (W257).
        let installed = context.evaluateScript("""
        (function(wanted) {
            var folded = {};
            var made = [];
            for (var key in this) {
                var lower = key.toLowerCase();
                folded[lower] = (lower in folded) ? null : key;
            }
            for (var i = 0; i < wanted.length; i++) {
                var name = wanted[i];
                if (typeof this[name] !== 'undefined') { continue; }
                var real = folded[name.toLowerCase()];
                if (!real || typeof this[real] !== 'function') { continue; }
                this[name] = this[real];
                made.push([name, real]);
            }
            return made;
        }).call(this, [\(list)]);
        """)?.toArray() as? [[String]] ?? []
        for pair in installed where pair.count == 2 { installedAliases[pair[0]] = pair[1] }
    }

    /// Words a `name(` scan would otherwise offer as a call. None of them can alias — nothing
    /// case-folds to them — but skipping them keeps the candidate list honest.
    private static let jScriptKeywords: Set<String> = [
        "if", "for", "while", "switch", "return", "function", "catch", "typeof", "new", "delete",
        "void", "do", "else", "with", "in", "this", "case", "throw", "var", "instanceof"
    ]

    @discardableResult
    private func evaluate(_ source: String, label: String) -> String? {
        if !isLoadingPrograms { aliasCaseFoldedGlobals(callSitesIn: source) }
        lastException = nil
        // Every program and every markup handler goes through here, and every one of them is
        // JScript rather than JavaScript. `WMPJScriptDialect.liveForIn` is the reconciliation; see
        // that file for why a `for-in` is the difference that decides whether a whole skin family
        // can reach its compact view (W86). A program with no `for-in` comes back unchanged.
        context.evaluateScript(WMPJScriptDialect.liveForIn(source),
                               withSourceURL: URL(string: "wmp:///\(label)"))
        return lastException
    }

    // MARK: Installation

    private func install() {
        applyExecutionTimeLimit()
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastException = exception.map { Self.describe($0) } ?? "unknown error"
        }

        let get: @convention(block) (String, String) -> Any? = { [weak self] path, member in
            guard let self else { return nil }
            return self.answer(self.model.get(path, member), path: path, member: member)
        }
        let set: @convention(block) (String, String, JSValue?) -> Void = { [weak self] path, member, value in
            guard let self else { return }
            let result = self.model.set(path, member, Self.jsonValue(value) ?? .null)
            if case let .unrecognised(reason) = result { self.throwUnknown(path, member, reason) }
        }
        let call: @convention(block) (String, String, JSValue?) -> Any? = { [weak self] path, member, args in
            guard let self else { return nil }
            var arguments: [WMPJSONValue] = []
            if let args, args.isObject || args.isArray {
                let count = Int(args.forProperty("length")?.toInt32() ?? 0)
                for index in 0..<min(count, 32) {
                    arguments.append(Self.jsonValue(args.atIndex(index)) ?? .null)
                }
            }
            return self.answer(self.model.invoke(path, member, arguments), path: path, member: member)
        }
        let has: @convention(block) (String, String) -> Bool = { [weak self] path, member in
            self?.model.recognises(path, member) ?? false
        }
        let timer: @convention(block) (JSValue?, Double, Bool) -> Int = { [weak self] function, period, repeats in
            self?.registerTimer(function: function, period: period, repeats: repeats) ?? 0
        }
        let clearTimer: @convention(block) (Int) -> Void = { [weak self] token in
            self?.timerFunctions.removeValue(forKey: token)
            self?.pendingTimers.removeAll { $0.token == token }
            // Recorded as well as removed: the token may belong to a timer an *earlier*
            // transaction registered, which this one cannot see in `pendingTimers` and which is
            // running as a task in the controller.
            self?.pendingClearedTimers.append(token)
        }
        context.setObject(get, forKeyedSubscript: "__wmpGet" as NSString)
        context.setObject(set, forKeyedSubscript: "__wmpSet" as NSString)
        context.setObject(call, forKeyedSubscript: "__wmpCall" as NSString)
        context.setObject(has, forKeyedSubscript: "__wmpHas" as NSString)
        context.setObject(timer, forKeyedSubscript: "__wmpTimer" as NSString)
        context.setObject(clearTimer, forKeyedSubscript: "__wmpClearTimer" as NSString)
        context.evaluateScript(Self.bootstrap)
        // The live enumerator the JScript `for-in` rewrite targets. Evaluated raw, never rewritten:
        // its own `for-in` is the native snapshotting one, and re-running it per `next()` is what
        // makes the rewritten loop live.
        context.evaluateScript(WMPJScriptDialect.prelude)
        // Bound here as well as after every view's elements, because a skin's programs run
        // top-level code — `metadata.js` line 15 is `theme.loadString(…)` — before any handler.
        bindHostGlobals()
        for (name, value) in WMPScriptConstants.values {
            context.setObject(value, forKeyedSubscript: name as NSString)
        }
    }

    private func bindHostGlobals() {
        bind(global: "player", to: "player")
        bind(global: "eq", to: "eq")
        bind(global: "theme", to: "theme")
        bind(global: "network", to: "player.network")
        bind(global: "mediacenter", to: "mediacenter")
        // WMP's `event` is a global object, not a handler argument: `Compact`'s drawer handlers
        // read `event.screenWidth` from a plain function call, and its view root reads it from a
        // `jscript:` attribute where no event exists at all.
        bind(global: "event", to: "event")
    }

    private func bind(global name: String, to path: String) {
        guard Self.isIdentifier(name),
              let wrap = context.objectForKeyedSubscript("__wmpWrap"),
              !wrap.isUndefined else { return }
        context.setObject(wrap.call(withArguments: [path]), forKeyedSubscript: name as NSString)
    }

    private func answer(_ value: WMPMemberValue, path: String, member: String) -> Any? {
        switch value {
        case let .value(item):
            var payload: [String: Any] = ["k": 0]
            if let bridged = Self.jsAny(item) { payload["v"] = bridged }
            return payload
        case let .object(child): return ["k": 1, "o": child]
        case .function: return ["k": 2]
        case let .unrecognised(reason):
            throwUnknown(path, member, reason)
            return nil
        }
    }

    /// An unrecognised member throws. That aborts the one handler that touched it — never the
    /// session — and the call trace has already tallied it as measured demand.
    private func throwUnknown(_ path: String, _ member: String, _ reason: String) {
        let trace = WMPObjectModel.tracePath(path, member)
        guard let current = JSContext.current() else { return }
        current.exception = JSValue(newErrorFromMessage: "WMP: unimplemented \(trace) (\(reason))",
                                    in: current)
    }

    private func registerTimer(function: JSValue?, period: Double, repeats: Bool) -> Int {
        guard pendingTimers.count < WMPPhase0Limits.activeTimers else { return 0 }
        nextTimerToken += 1
        let token = nextTimerToken
        let milliseconds = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds,
                               Int(period.isFinite ? period : 0))
        var source = WMPJScriptTimerRequest.tokenMarker(token)
        if let function, function.isString {
            source = function.toString() ?? source
        } else if let function {
            timerFunctions[token] = function
        }
        pendingTimers.append(.init(token: token, periodMilliseconds: milliseconds,
                                   repeats: repeats, source: source))
        return token
    }

    /// `svmain.width` names the element `svmain`.
    private static func owner(of key: String) -> String {
        guard let dot = key.lastIndex(of: ".") else { return key }
        return WMPPath.fold(String(key[key.startIndex..<dot]))
    }

    // MARK: Bridging

    static func jsonValue(_ value: JSValue?) -> WMPJSONValue? {
        guard let value else { return nil }
        if value.isUndefined || value.isNull { return .null }
        if value.isBoolean { return .bool(value.toBool()) }
        if value.isNumber {
            let number = value.toDouble()
            return .number(number.isFinite ? number : 0)
        }
        return .string(value.toString() ?? "")
    }

    static func jsAny(_ value: WMPJSONValue) -> Any? {
        switch value {
        case .null: return nil
        case let .bool(item): return item
        case let .number(item): return item
        case let .string(item): return item
        }
    }

    private static func describe(_ exception: JSValue) -> String {
        let message = exception.toString() ?? "error"
        guard let line = exception.forProperty("line"), line.isNumber else { return message }
        return "\(message) (line \(line.toInt32()))"
    }

    private static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_" || first == "$" else { return false }
        return name.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "$"
        }
    }

    // MARK: The execution-time limit
    //
    // JavaScriptCore's public API cannot interrupt a running script. The C entry point that can is
    // exported by the framework but not declared in a public header, so it is resolved by name and
    // simply absent if it ever goes away: the context then runs unbounded on its own queue, which
    // stalls that skin's rendering and nothing else. Recorded as a known limit in the decision
    // record rather than hidden behind a claim the code cannot keep.
    private typealias SetExecutionTimeLimit = @convention(c) (
        OpaquePointer?, Double, (@convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Bool)?,
        UnsafeMutableRawPointer?) -> Void

    private(set) var executionLimitApplied = false

    private func applyExecutionTimeLimit() {
        guard let handle = dlopen(nil, RTLD_NOW),
              let getGroup = dlsym(handle, "JSContextGetGroup"),
              let setLimit = dlsym(handle, "JSContextGroupSetExecutionTimeLimit") else { return }
        typealias GetGroup = @convention(c) (OpaquePointer?) -> OpaquePointer?
        let group = unsafeBitCast(getGroup, to: GetGroup.self)(context.jsGlobalContextRef)
        unsafeBitCast(setLimit, to: SetExecutionTimeLimit.self)(group, executionSeconds, { _, _ in true }, nil)
        executionLimitApplied = true
    }

    // MARK: The bootstrap
    //
    // Deliberately tiny. Every decision — whether a member exists, what it answers, whether it is
    // live or inert — is made in Swift, so the trace and the object model cannot disagree with each
    // other. This is only the proxy that routes a property access to them.
    private static let bootstrap = #"""
    (function (global) {
      'use strict';
      var INTERNAL = {
        toString: 1, valueOf: 1, toJSON: 1, constructor: 1, prototype: 1, length: 1,
        hasOwnProperty: 1, then: 1, inspect: 1, splice: 1, call: 1, apply: 1
      };
      function wrap(path) {
        var cache = Object.create(null);
        return new Proxy(function () {}, {
          get: function (target, property) {
            if (typeof property === 'symbol') return undefined;
            var name = String(property);
            if (name === '__wmpPath') return path;
            if (INTERNAL[name] === 1) return target[name];
            if (cache[name] !== undefined) return cache[name];
            var answer = __wmpGet(path, name);
            if (!answer) return undefined;
            if (answer.k === 1) { cache[name] = wrap(answer.o); return cache[name]; }
            if (answer.k === 2) {
              cache[name] = function () {
                var answered = __wmpCall(path, name, Array.prototype.slice.call(arguments));
                if (!answered) return undefined;
                if (answered.k === 1) return wrap(answered.o);
                return answered.v;
              };
              return cache[name];
            }
            return answer.v;
          },
          set: function (target, property, value) {
            if (typeof property === 'symbol') return true;
            __wmpSet(path, String(property), value);
            return true;
          },
          // `with` asks this for every identifier in a geometry expression, so it must answer for
          // the element's own properties and *only* those: `svBottomLeft.width - left` means this
          // element's `left`, while `svBottomLeft` has to reach the global of that name.
          has: function (target, property) {
            if (typeof property === 'symbol') return false;
            return __wmpHas(path, String(property));
          }
        });
      }
      global.__wmpWrap = wrap;
      global.setTimeout = function (fn, ms) { return __wmpTimer(fn, Number(ms) || 0, false); };
      global.setInterval = function (fn, ms) { return __wmpTimer(fn, Number(ms) || 0, true); };
      global.clearTimeout = function (token) { __wmpClearTimer(Number(token) || 0); };
      global.clearInterval = global.clearTimeout;
      global.ActiveXObject = undefined;
      global.WScript = undefined;
      global.Enumerator = undefined;
      global.VBArray = undefined;
      global.GetObject = undefined;
    })(this);
    """#
}
