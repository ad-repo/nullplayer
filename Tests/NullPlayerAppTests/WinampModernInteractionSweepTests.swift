import XCTest
import AppKit
@testable import NullPlayer

/// The S3 interaction sweep (`corpus-runner-plan.md` §3 S3, §7 step 5): every object a script hooks
/// the mouse on, in every open window's opening layout, driven the way `WinampModernMainView` drives
/// it, and asked whether anything happened. `RENDER_CLICK` generalised from one point to every hooked
/// object.
///
///     WINAMP_MODERN_INTERACTION_SWEEP=<dir[:dir…]> \
///     WINAMP_MODERN_INTERACTION_SWEEP_OUT=<file.tsv> \
///       swift test --filter WinampModernInteractionSweepTests
///
/// `scripts/wal_interaction_sweep.sh` shards this and writes `interaction.tsv`, one row per
/// (skin, container, layout, object, gesture), written straight to the file (B166).
///
/// Every target gets a **fresh load** and the skin's stored configuration back as it was, so a row
/// does not depend on which control was driven before it: a close button or a tab switch earlier in
/// the walk would otherwise make every later control read as unreachable.
final class WinampModernInteractionSweepTests: XCTestCase {

    static let pointerEvents = ["onleftbuttondown", "onleftbuttonup", "onleftclick", "onleftbuttondblclk",
                                "onrightbuttondown", "onrightbuttonup", "onrightclick", "onmousemove"]
    /// What a gesture is allowed to settle for between its last event and the measurement — a skin
    /// does a click's work from a timer it starts (`RENDER_SETTLE`).
    static let settle: TimeInterval = 0.3
    /// How long a fresh load runs before anything is measured, and how long the no-gesture control
    /// watches. 0.3 s for both left 33 of ~2,490 verdicts and Alpha_Media_Player_X5's control list
    /// flipping between two runs (2026-10-19): skins whose timers tick slower than the window.
    static let quiet: TimeInterval = 1

    func testSweepsHookedControls() throws {
        let env = ProcessInfo.processInfo.environment
        guard let list = env["WINAMP_MODERN_INTERACTION_SWEEP"],
              let out = env["WINAMP_MODERN_INTERACTION_SWEEP_OUT"] else {
            throw XCTSkip("Set WINAMP_MODERN_INTERACTION_SWEEP and WINAMP_MODERN_INTERACTION_SWEEP_OUT.")
        }
        let wals = WinampModernCorpusPaths.archives(in: list)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        // Appended per skin, so a long shard shows progress and a crash costs one skin, not the shard.
        FileManager.default.createFile(atPath: out, contents: nil)
        let file = try FileHandle(forWritingTo: URL(fileURLWithPath: out))
        defer { try? file.close() }
        for wal in wals {
            var rows: [String]
            do {
                rows = try Self.sweep(wal)
                // A skin with no hooked control in an open window is still a row.
                if rows.isEmpty { rows = [String(repeating: "-\t", count: 6) + "none" + String(repeating: "\t-", count: 4)] }
            } catch {
                // A skin that will not load is still a row, so nothing is skipped silently.
                rows = [String(repeating: "-\t", count: 6) + "failed" + String(repeating: "\t-", count: 4)]
            }
            file.write(Data(rows.map { "\(wal.lastPathComponent)\t\($0)\n" }.joined().utf8))
        }
    }

    /// One loaded skin with its scripts started, its renderers wired as the app wires them.
    private final class Session {
        let loaded: WinampModernLoadedSkin
        let runtime: WinampModernScriptRuntime
        let renderers: [String: WasabiSceneRenderer]

        init(_ wal: URL) throws {
            loaded = try WinampModernSkinLoader(engineStore: .shared).load(from: wal)
            let host = WinampModernStubHost()
            runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
            var renderers: [String: WasabiSceneRenderer] = [:]
            for info in WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph) {
                guard let renderer = try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                              containerID: info.id) else { continue }
                renderer.layerFXProvider = { [weak runtime] in runtime?.layerFXMesh(for: $0) }
                renderer.configStateProvider = { [weak runtime] in runtime?.configValue(of: $0) ?? false }
                renderer.pressBindingProvider = { [weak runtime] in runtime?.hasPressBinding(for: $0) ?? false }
                renderer.configValueProvider = { [weak runtime] in runtime?.configInteger(of: $0) }
                renderers[info.id] = renderer
            }
            self.renderers = renderers
            let all = Array(renderers.values)
            runtime.hooks.resolvedGeometryRequested = { object in
                all.lazy.compactMap { $0.resolvedGeometry(of: object) }.first
            }
            try runtime.start()
            for renderer in all { runtime.dispatchResize(targets: renderer.resizeTargets(), previous: nil) }
            RunLoop.current.run(until: Date().addingTimeInterval(quiet))
        }

        func teardown() {
            renderers.values.forEach { $0.teardown() }
            runtime.teardown()
            loaded.teardown()
        }
    }

    /// Rows without the skin column: `container, layout, object, gesture, point, hit, verdict,
    /// handlers, failed, changed, effect`.
    private static func sweep(_ wal: URL) throws -> [String] {
        // Taken before the first load, which may itself write values; scoped below to this skin's
        // own namespace, because the other shards are writing theirs into the same defaults domain.
        let everything = storedConfiguration(prefix: configurationPrefix)
        // The census load: which controls exist, and where each is first reachable.
        let census = try Session(wal)
        let namespace = configurationPrefix + census.loaded.configuration.namespace + "."
        let stored = everything.filter { $0.key.hasPrefix(namespace) }
        defer { restore(stored, prefix: namespace) }
        let containers = WinampModernContainerTopology.windowContainers(graph: census.loaded.runtime.graph)
            .filter { info in
                info.isMainPlayer
                    || (info.opensByDefault && WinampModernContainerTopology.defaultVisibilitySuppression(of: info) == nil)
            }
        var targets: [(container: String, layout: String, path: [Int], label: String,
                       point: CGPoint?, blocker: String, gestures: [String])] = []
        for info in containers {
            guard let renderer = census.renderers[info.id] else { continue }
            for node in renderer.sceneNodes() {
                let object = node.object
                let bound = Set(pointerEvents.filter { census.runtime.hasBinding(for: object, event: $0) })
                guard !bound.isEmpty else { continue }
                var gestures: [String] = []
                if !bound.isDisjoint(with: ["onleftbuttondown", "onleftbuttonup", "onleftclick"]) { gestures.append("click") }
                if bound.contains("onleftbuttondblclk") { gestures.append("dblclick") }
                // A knob or strip that polls the pointer from a timer while pressed binds no
                // `onMouseMove` (mmd3's bass/treble knobs), so a pressed non-button is dragged too.
                let pressable = ["layer", "animatedlayer", "slider"].contains(object.typeName.lowercased())
                if bound.contains("onmousemove") || (pressable && bound.contains("onleftbuttondown")) {
                    gestures.append("drag")
                }
                if !bound.isDisjoint(with: ["onrightbuttondown", "onrightbuttonup", "onrightclick"]) { gestures.append("right") }
                let point = reachablePoint(of: object, frame: node.frame.intersection(node.clip),
                                           renderer: renderer, runtime: census.runtime)
                // Why an unreachable control is unreachable: clipped out of its window, or what the
                // hit test answers at its centre instead.
                let blocker = point != nil ? "yes"
                    : node.frame.intersection(node.clip).isEmpty ? "clipped"
                    : "covered:" + (renderer.object(at: CGPoint(x: node.frame.midX, y: node.frame.midY)).map(label) ?? "nothing")
                targets.append((info.id, renderer.activeLayoutID, path(of: object, in: census.loaded.runtime.graph),
                                label(object), point, blocker, gestures))
            }
        }
        census.teardown()
        restore(stored, prefix: namespace)

        var rows: [String] = []
        for target in targets {
            for gesture in target.gestures {
                let prefix = [target.container, target.layout, target.label, gesture,
                              target.point.map { "\(Int($0.x)),\(Int($0.y))" } ?? "-"]
                guard let point = target.point else {
                    rows.append((prefix + [target.blocker, "unreachable", "-", "-", "-", "-"]).joined(separator: "\t"))
                    continue
                }
                let session = try Session(wal)
                defer { session.teardown(); restore(stored, prefix: namespace) }
                guard let renderer = session.renderers[target.container],
                      let object = resolve(target.path, in: session.loaded.runtime.graph) else {
                    rows.append((prefix + ["no", "gone", "-", "-", "-", "-"]).joined(separator: "\t"))
                    continue
                }
                rows.append((prefix + drive(gesture, on: object, at: point, renderer: renderer, session: session))
                    .joined(separator: "\t"))
            }
        }
        return rows
    }

    /// `hit, verdict, handlers, failed, changed, effect` for one gesture on a fresh session.
    private static func drive(_ gesture: String, on object: WasabiObject, at point: CGPoint,
                              renderer: WasabiSceneRenderer, session: Session) -> [String] {
        let runtime = session.runtime
        // Driven as the view drives it: at whatever the press lands on, which forwards to an
        // embedding group. `hit` is `no` when the fresh load disagrees with the census about that.
        let receiver = receiver(at: point, for: object, renderer: renderer, runtime: runtime)
        let hit = receiver != nil
        let pressed = receiver ?? object
        // The control: one settle with no gesture. Whatever a ticker or a timer changes by itself in
        // that time is not the gesture's doing, and would otherwise make every silent control on a
        // busy skin read as working.
        let idle = graphState(session.loaded.runtime.graph)
        let idlePixels = pixels(renderer)
        // Handlers a timer runs on its own, and failures it hits on every tick (EPS's clock fails
        // `formatDate` each second), are the same kind of noise.
        var idleEvents: Set<String> = []
        var idleFailures: Set<String> = []
        runtime.dispatchObserver = { event, _, failure in
            idleEvents.insert(event)
            if let failure { idleFailures.insert(failure.diagnostics.map(Self.failureLabel).joined(separator: "+")) }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(quiet))
        let before = graphState(session.loaded.runtime.graph)
        let pixelsBefore = pixels(renderer)
        let noisy = Set(before.keys.filter { idle[$0] != before[$0] })
        let pixelsAreQuiet = idlePixels == pixelsBefore

        var ran = 0
        var failures: Set<String> = []
        runtime.dispatchObserver = { event, _, failure in
            guard !idleEvents.contains(event) else { return }
            ran += 1
            if let failure {
                let label = failure.diagnostics.map(Self.failureLabel).joined(separator: "+")
                if !idleFailures.contains(label) { failures.insert(label) }
            }
        }
        var effects: [String] = []
        runtime.hooks.actionRequested = { action, parameter in effects.append("action:\(action)\(parameter.map { ";\($0)" } ?? "")") }
        runtime.hooks.containerVisibilityRequested = { id, visible in effects.append("window:\(id)=\(visible ? 1 : 0)") }
        runtime.popupPresenter = { items, _ in
            effects.append("menu:\(items.filter { !$0.isSeparator }.count)")
            return WinampModernScriptRuntime.popupDismissed
        }
        var pointer = point
        runtime.hooks.mousePositionInObjectSpaceRequested = { _ in pointer }
        func send(_ event: String, at canvas: CGPoint? = nil) {
            if let canvas {
                pointer = canvas
                // As `WinampModernMainView.dispatch(object:event:point:)` sends them.
                let local = runtime.pointInEventSpace(of: pressed, event: event, canvasPoint: canvas,
                                                      renderer: renderer)
                _ = try? runtime.dispatch(object: pressed, event: event,
                                          arguments: [.integer(Int32(local.x)), .integer(Int32(local.y))])
            } else {
                _ = try? runtime.dispatch(object: pressed, event: event)
            }
        }
        // The view's own half of a gesture: the markup command it performs and, for a click, the
        // radio / toggle / `cfgattrib` flip it makes — mirrored as the render dump's `CLICK` does.
        // Without it a transport button whose script only lights a label reads as dead (Dreliction).
        // A command the host answers as inert is not an effect.
        func markup(_ raw: (action: String, parameter: String?)?) {
            guard let raw else { return }
            if case .inert? = WinampModernHostAction(action: raw.action) { return }
            effects.append("markup:\(raw.action)")
        }
        switch gesture {
        case "click":
            send("onleftbuttondown", at: point); send("onleftbuttonup", at: point); send("onleftclick")
            if let raw = pressed.attributes["action"], !raw.isEmpty {
                markup(WasabiClickAction.split(action: raw, parameter: pressed.attributes["param"]))
            }
            if !runtime.selectRadioMember(pressed) { _ = runtime.toggleActivation(of: pressed) }
            if WinampModernScriptRuntime.configBinding(of: pressed) != nil { runtime.toggleConfigAttribute(of: pressed) }
        case "dblclick":
            send("onleftbuttondown", at: point); send("onleftbuttondblclk", at: point); send("onleftbuttonup", at: point)
            markup(WasabiClickAction.resolve(pressed, gesture: .double))
        case "drag":
            // Along the control's long axis to its far edge, in four steps, as a strip or a seek bar
            // is dragged. A knob's arc is not modelled: a straight line still moves its angle.
            let frame = renderer.frame(of: object) ?? CGRect(origin: point, size: .zero)
            let end = frame.width >= frame.height ? CGPoint(x: frame.maxX - 1, y: point.y)
                : CGPoint(x: point.x, y: frame.maxY - 1)
            send("onleftbuttondown", at: point)
            for step in 1...4 {
                let t = CGFloat(step) / 4
                send("onmousemove", at: CGPoint(x: point.x + (end.x - point.x) * t, y: point.y + (end.y - point.y) * t))
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            send("onleftbuttonup", at: end)
        default:
            send("onrightbuttondown", at: point); send("onrightbuttonup", at: point); send("onrightclick")
            markup(WasabiClickAction.resolve(pressed, gesture: .right))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        runtime.dispatchObserver = nil

        let after = graphState(session.loaded.runtime.graph)
        let changed = after.filter { before[$0.key] != $0.value && !noisy.contains($0.key) }.count
        // Pixels only count where the idle settle left them still; a ticker repaints regardless.
        let moved = pixelsAreQuiet && pixels(renderer) != pixelsBefore
        let verdict = !failures.isEmpty ? "blocked"
            : ran == 0 ? "unbound"
            : (changed > 0 || moved || !effects.isEmpty) ? "works" : "silent"
        return [hit ? "yes" : "no", verdict, "\(ran)",
                failures.isEmpty ? "-" : failures.sorted().joined(separator: ","),
                "\(changed)\(moved ? "+px" : "")",
                effects.isEmpty ? "-" : Array(Set(effects)).sorted().prefix(6).joined(separator: ",")]
    }

    /// The first point, centre first and then on a 7×7 grid, where the hit test returns `object`.
    /// The artwork's alpha and the declared region both decide that, so asking the hit test is the
    /// plan's "pick the point from the artwork alpha or region" without a second model of either.
    private static func reachablePoint(of object: WasabiObject, frame: CGRect, renderer: WasabiSceneRenderer,
                                       runtime: WinampModernScriptRuntime) -> CGPoint? {
        guard !frame.isEmpty else { return nil }
        var candidates = [CGPoint(x: frame.midX, y: frame.midY)]
        for row in 0..<7 {
            for column in 0..<7 {
                let x: CGFloat = frame.minX + frame.width * (CGFloat(column) + 0.5) / 7
                let y: CGFloat = frame.minY + frame.height * (CGFloat(row) + 0.5) / 7
                candidates.append(CGPoint(x: x, y: y))
            }
        }
        return candidates.first { receiver(at: $0, for: object, renderer: renderer, runtime: runtime) != nil }
    }

    /// What the view would dispatch to for a press at `point` that reaches `object`: the object
    /// itself, or the control an `embed_xui` group wraps, whose pointer events the runtime forwards
    /// to the group (`bento:tabbutton`, `Wasabi:Frame`). `nil` when a press there reaches neither.
    private static func receiver(at point: CGPoint, for object: WasabiObject, renderer: WasabiSceneRenderer,
                                 runtime: WinampModernScriptRuntime) -> WasabiObject? {
        guard let hit = renderer.object(at: point) else { return nil }
        return hit === object || runtime.embeddingOwners(of: hit).contains(where: { $0 === object }) ? hit : nil
    }

    private static func pixels(_ renderer: WasabiSceneRenderer) -> Data {
        let size = renderer.canvasSize
        guard size.width >= 1, size.height >= 1,
              let context = CGContext(data: nil, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        renderer.draw(in: context)
        NSGraphicsContext.current = previous
        guard let data = context.data else { return Data() }
        return Data(bytes: data, count: context.bytesPerRow * context.height)
    }

    /// Every object's click-relevant attributes, keyed by its child-index path — the render dump's
    /// `CLICK changed` snapshot, graph-wide.
    private static func graphState(_ graph: WasabiObjectGraph) -> [String: String] {
        var state: [String: String] = [:]
        func walk(_ objects: [WasabiObject], _ prefix: String) {
            for (index, object) in objects.enumerated() {
                let key = "\(prefix)/\(index)"
                state[key] = WinampModernRenderDumpTests.state(of: object)
                walk(object.children, key)
            }
        }
        walk(graph.roots, "")
        return state
    }

    /// Where an object sits in the graph, as child indices from its root — stable across two loads
    /// of one skin, where a `stableID` is not guaranteed to be.
    private static func path(of object: WasabiObject, in graph: WasabiObjectGraph) -> [Int] {
        var path: [Int] = []
        var current = object
        while let parent = current.parent {
            path.insert(parent.children.firstIndex { $0 === current } ?? -1, at: 0)
            current = parent
        }
        return [graph.roots.firstIndex { $0 === current } ?? -1] + path
    }

    private static func resolve(_ path: [Int], in graph: WasabiObjectGraph) -> WasabiObject? {
        guard let first = path.first, graph.roots.indices.contains(first) else { return nil }
        var object = graph.roots[first]
        for index in path.dropFirst() {
            guard object.children.indices.contains(index) else { return nil }
            object = object.children[index]
        }
        return object
    }

    /// `method:<name>` for a call the runtime lacks — the demand index's unit — else the code.
    private static func failureLabel(_ diagnostic: WalDiagnostic) -> String {
        let message = diagnostic.message
        if let start = message.range(of: "support method '"),
           let end = message[start.upperBound...].firstIndex(of: "'") {
            return "method:" + message[start.upperBound..<end]
        }
        return "\(diagnostic.code)"
    }

    private static func label(_ object: WasabiObject) -> String {
        "\(object.typeName)#\(object.xmlID ?? "-")".replacingOccurrences(of: "\t", with: " ")
    }

    // MARK: - The skin's stored configuration

    /// A click that writes a private value would otherwise carry into the next target's load and into
    /// later harness runs: the configuration lives in this process's `UserDefaults` (`harness.md`).
    private static let configurationPrefix = "winampModern.config."

    private static func storedConfiguration(prefix: String) -> [String: Any] {
        WinampModernConfiguration.processDefaults.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) }
    }

    /// Put one skin's keys back as they were, touching no other skin's: shards share the domain.
    private static func restore(_ stored: [String: Any], prefix: String) {
        let defaults = WinampModernConfiguration.processDefaults
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            if let value = stored[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        for (key, value) in stored { defaults.set(value, forKey: key) }
    }
}
