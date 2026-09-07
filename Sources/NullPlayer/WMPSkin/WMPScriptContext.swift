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

    init(skin: WMPLoadedSkin, viewID: String) {
        self.viewID = viewID
        guard let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node else {
            elements = []; expressions = []; expressionAddresses = [:]; idToStableID = [:]
            return
        }
        var included = Set<Int>()
        func include(_ node: WMPNode) { included.insert(node.stableID); node.children.forEach(include) }
        include(view)

        var definitions: [WMPScriptElementDefinition] = []
        var expressions: [WMPScriptExpression] = []
        var addresses: [String: WMPScenePropertyAddress] = [:]
        var ids: [String: Int] = [:]
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
    }

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
    private var nextTimerToken = 0
    private var lastException: String?

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
    func load(scripts: [String: String], order: [WMPScriptRegistration]) -> [WMPJScriptDiagnostic] {
        queue.sync {
            var diagnostics: [WMPJScriptDiagnostic] = []
            var evaluated = Set<String>()
            for registration in order {
                guard let path = registration.resolvedPath, let source = scripts[path],
                      evaluated.insert(path).inserted else { continue }
                if let error = evaluate(source, label: registration.authoredPath) {
                    diagnostics.append(.init(code: "script-error",
                                             message: "\(registration.authoredPath): \(error)"))
                }
            }
            return diagnostics
        }
    }

    func install(elements definitions: [WMPScriptElementDefinition]) {
        queue.sync {
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
    }

    func setElementValue(stableID: Int, value: Double) {
        queue.sync {
            guard let element = model.elements.values.first(where: { $0.stableID == stableID })
            else { return }
            element.properties["value"] = .number(value)
        }
    }

    func teardown() {
        queue.sync {
            timerFunctions.removeAll()
            pendingTimers.removeAll()
            model.resetElements([])
        }
    }

    // MARK: Running a transaction

    func run(plan: WMPScriptViewPlan, size: WMPSize, snapshot: WMPHostSnapshot,
             preferences: [String: String], event: WMPJScriptEvent?) async -> WMPScriptRunResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: perform(plan: plan, size: size, snapshot: snapshot,
                                                       preferences: preferences, event: event))
            }
        }
    }

    private func perform(plan: WMPScriptViewPlan, size: WMPSize, snapshot: WMPHostSnapshot,
                         preferences: [String: String], event: WMPJScriptEvent?) -> WMPScriptRunResult {
        model.beginTransaction(snapshot: snapshot, preferences: preferences, viewID: plan.viewID)
        pendingTimers.removeAll()
        if let view = model.element("view") {
            view.properties["width"] = .number(Double(size.width))
            view.properties["height"] = .number(Double(size.height))
            view.properties["left"] = .number(0)
            view.properties["top"] = .number(0)
        }

        var result = WMPScriptRunResult()
        let ordered = resolveExpressions(plan: plan, into: &result)
        result.expressionOrder = ordered

        if let event {
            for (index, source) in event.handlers.enumerated() {
                // Fail closed per handler, never per session. A skin puts its whole startup in one
                // handler, so one missing member costs many unrelated features — and the demand
                // tally is what makes that visible. A session-wide kill switch made it invisible.
                if let error = invokeHandler(source, label: "\(event.name)[\(index)]") {
                    result.diagnostics.append(.init(code: "handler-error",
                                                    message: "\(event.name)[\(index)]: \(error)"))
                }
            }
        }

        result.calls = model.calls
        result.mutations = model.mutations
        result.hostCommands = model.hostCommands
        result.preferenceWrites = model.preferenceWrites
        result.repaintHints = model.repaintHints
        result.diagnostics += model.diagnostics
        result.timers = pendingTimers
        return result
    }

    /// Two passes. The first measures what each expression reads, because the dependency order is a
    /// fact about the skin that only running it can tell you; the second evaluates in that order and
    /// commits each value before its dependents run.
    ///
    /// A failing expression costs itself and nothing else. The model this replaced returned an empty
    /// ordered list when any single expression failed, so one `ReferenceError` in one attribute left
    /// a whole skin with no computed geometry at all (W21).
    private func resolveExpressions(plan: WMPScriptViewPlan,
                                    into result: inout WMPScriptRunResult) -> [String] {
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
                model.element(Self.owner(of: key))?.properties[address.property] = .number(number)
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

    private func invokeHandler(_ source: String, label: String) -> String? {
        if let token = WMPJScriptTimerRequest(token: 0, periodMilliseconds: 0, repeats: false,
                                              source: source).callbackToken {
            guard let function = timerFunctions[token] else { return nil }
            lastException = nil
            function.call(withArguments: [])
            return lastException
        }
        return evaluate(source, label: label)
    }

    @discardableResult
    private func evaluate(_ source: String, label: String) -> String? {
        lastException = nil
        context.evaluateScript(source, withSourceURL: URL(string: "wmp:///\(label)"))
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
        }
        context.setObject(get, forKeyedSubscript: "__wmpGet" as NSString)
        context.setObject(set, forKeyedSubscript: "__wmpSet" as NSString)
        context.setObject(call, forKeyedSubscript: "__wmpCall" as NSString)
        context.setObject(has, forKeyedSubscript: "__wmpHas" as NSString)
        context.setObject(timer, forKeyedSubscript: "__wmpTimer" as NSString)
        context.setObject(clearTimer, forKeyedSubscript: "__wmpClearTimer" as NSString)
        context.evaluateScript(Self.bootstrap)
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
