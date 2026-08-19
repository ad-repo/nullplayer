import XCTest
import AppKit
@testable import NullPlayer

/// Opt-in render harness. Phases 3–8 never watched a target skin paint — every check was structural
/// (graph built, scripts ran), which is exactly why a vertical-flip bug in every bitmap draw could
/// survive 490+ green tests. This renders the real scene to a PNG so the output can be looked at.
///
///     WINAMP_MODERN_ENGINE=/path/ClassicPro_2.01.exe \
///     WINAMP_MODERN_WAL=/path/cPro-Bento.wal \
///     WINAMP_MODERN_RENDER_DUMP=/path/to/dump-dir \
///       swift test --filter WinampModernRenderDumpTests
final class WinampModernRenderDumpTests: XCTestCase {

    func testRendersEachContainerToPNG() throws {
        let env = ProcessInfo.processInfo.environment
        guard let walPath = env["WINAMP_MODERN_WAL"], let dumpPath = env["WINAMP_MODERN_RENDER_DUMP"] else {
            throw XCTSkip("Set WINAMP_MODERN_WAL and WINAMP_MODERN_RENDER_DUMP (and WINAMP_MODERN_ENGINE for cPro).")
        }
        let dumpDirectory = URL(fileURLWithPath: dumpPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dumpDirectory, withIntermediateDirectories: true)

        var store: ClassicProEngineStore?
        if let enginePath = env["WINAMP_MODERN_ENGINE"] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("WinampModernRenderDump-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let engineStore = ClassicProEngineStore(rootDirectory: directory)
            _ = try ClassicProEngineImporter(store: engineStore)
                .importEngine(from: URL(fileURLWithPath: enginePath))
            store = engineStore
        }

        // With no WINAMP_MODERN_ENGINE the already-installed engine store is used, so a cPro skin
        // renders from the engine the app itself imported instead of failing on `load.xml`.
        let loaded = try WinampModernSkinLoader(engineStore: store ?? .shared)
            .load(from: URL(fileURLWithPath: walPath))
        defer { loaded.teardown() }
        let host = RenderHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        defer { runtime.teardown() }
        // Installed *before* `start()`: the whole point of the tap is to see which `onScriptLoaded`
        // handlers ran, and they all run inside it.
        var executedEvents: [ObjectIdentifier: Set<String>] = [:]
        var failedEvents: [ObjectIdentifier: [String: String]] = [:]
        if env["WINAMP_MODERN_RENDER_SCRIPTS"] != nil {
            runtime.dispatchObserver = { event, program, failure in
                let key = ObjectIdentifier(program)
                executedEvents[key, default: []].insert(event)
                if let failure {
                    failedEvents[key, default: [:]][event] =
                        failure.diagnostics.map(\.message).joined(separator: "; ")
                }
            }
        }
        // WINAMP_MODERN_RENDER_CONFIG=<section>;<key>=<value>[|…] writes skin configuration before
        // the scripts start, which is where the app reads it from: the value is persisted, so a skin
        // option the user picked in an earlier session (Defix's eight display styles) is already set
        // when `onScriptLoaded` runs. Note it *stays* set for later runs of the harness, exactly as
        // it does for the app.
        if let spec = env["WINAMP_MODERN_RENDER_CONFIG"] {
            for entry in spec.split(separator: "|") {
                let parts = entry.split(separator: ";", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let assignment = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                guard assignment.count == 2 else { continue }
                loaded.configuration.setString(assignment[1], section: parts[0], key: assignment[0])
                print("CONFIG set [\(parts[0])] \(assignment[0]) = \(assignment[1])")
            }
        }

        try runtime.start()

        if let settle = env["WINAMP_MODERN_RENDER_SETTLE"].flatMap(Double.init) {
            RunLoop.current.run(until: Date().addingTimeInterval(settle))
            // The harness has no component host, so `PE_Info` reads empty and a skin that drives its
            // readouts from `onTextChanged` can never be seen to do it. Seed the cache empty, then
            // stand a synthetic queue up behind it — the same "it changed" the app produces when the
            // playlist is edited, which is the only thing that raises the event.
            runtime.refreshBoundText()
            WasabiTextMetrics.componentTextProvider = {
                WinampModernPlaylistSnapshot(
                    rows: (0..<3).map { WinampModernPlaylistRow(title: "t\($0)", secondary: "",
                                                                duration: 120, isCurrent: $0 == 0) },
                    currentIndex: 0, selectedIndex: 0)
            }
            runtime.refreshBoundText()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        // WINAMP_MODERN_RENDER_SETTINGS lists what the skin registered with `newAttribute` — the
        // options Winamp shows in its preferences dialog and a skin often binds no control to. It is
        // the only way to see, without a GUI, what the host's Skin Settings window will offer
        // (Phase 27.3).
        if env["WINAMP_MODERN_RENDER_SETTINGS"] != nil {
            for setting in runtime.registeredSettings {
                print("SETTING \(setting.sectionName) [\(setting.section)] "
                      + "\(setting.name) = \(runtime.configAttributeValue(setting)) "
                      + "(default \(setting.defaultValue))")
            }
        }

        // What the app does once a container's window is on screen: a `.wal` skin starts and stops
        // its animation from `onSetVisible` (Defix's cassette reels turn their Layer FX on there), so
        // without this nothing in the skin is warped at all. Before any `RENDER_CONFIG` write, since
        // a style switched *while the window is up* is what the app does.
        if env["WINAMP_MODERN_RENDER_FX"] != nil {
            for container in loaded.runtime.graph.roots
            where container.typeName.caseInsensitiveCompare("container") == .orderedSame {
                let isMain = container.xmlID?.caseInsensitiveCompare("main") == .orderedSame
                runtime.notifyContainerVisibility(containerID: container.stableID, visible: isMain)
            }
        }

        // WINAMP_MODERN_RENDER_FX lists the Layer FX layers (Phase 28): which layers the skin warps,
        // how they are configured, and where the evaluated mesh samples its corners from. A mesh that
        // is not the identity is a layer that is actually moving; the harness has no audio, so the
        // *amount* is whatever the skin computes at silence.
        if env["WINAMP_MODERN_RENDER_FX"] != nil {
            // `=play` tells the skin a track started. A meter's FX is switched on from playback in
            // every measured skin (a cassette's reels do not spin while stopped), so the layers are
            // not warped at all until the skin has heard `onPlay`.
            if env["WINAMP_MODERN_RENDER_FX"] == "play" {
                _ = try? runtime.dispatchSystem(event: "onplay")
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            }
            // WINAMP_MODERN_RENDER_FX_SPIN=<seconds> samples every warped layer's angle at 60 Hz for
            // that long, printing the wall-clock step between updates and how far the layer turned in
            // it. This is the measurement behind "the animation is rough": a smooth meter is a small,
            // even step at an even interval, and both halves are visible here without a window.
            if let seconds = env["WINAMP_MODERN_RENDER_FX_SPIN"].flatMap(Double.init) {
                let objects = runtime.enabledLayerFXObjects.sorted { ($0.xmlID ?? "") < ($1.xmlID ?? "") }
                var last: [String: (time: TimeInterval, angle: Double)] = [:]
                let start = Date()
                while Date().timeIntervalSince(start) < seconds {
                    RunLoop.current.run(until: Date().addingTimeInterval(1.0 / 60))
                    let now = Date().timeIntervalSince(start)
                    for object in objects {
                        let id = object.xmlID ?? "-"
                        guard let angle = runtime.layerFXAnswerBreakdown(for: object).first?.answer else { continue }
                        guard let previous = last[id] else { last[id] = (now, angle); continue }
                        guard abs(angle - previous.angle) > 1e-9 else { continue }
                        print(String(format: "FX-SPIN %@ dt=%.1fms d(angle)=%+.4f rad", id,
                                     (now - previous.time) * 1000, angle - previous.angle))
                        last[id] = (now, angle)
                    }
                }
            }
            for object in runtime.enabledLayerFXObjects.sorted(by: { ($0.xmlID ?? "") < ($1.xmlID ?? "") }) {
                let state = runtime.layerFXState(of: object)
                let mesh = runtime.layerFXMesh(for: object)
                let corners = mesh.map { $0.sources.prefix(4).map { point in
                    String(format: "(%.3f,%.3f)", point.x, point.y) }.joined(separator: " ") } ?? "-"
                let breakdown = runtime.layerFXAnswerBreakdown(for: object)
                    .map { String(format: "%@=%.4f", $0.program, $0.answer) }.joined(separator: " ")
                print("FX-BINDINGS \(object.xmlID ?? "-") \(breakdown)")
                print("FX \(object.typeName)#\(object.xmlID ?? "-") "
                      + "grid=\(state?.gridX ?? 0)x\(state?.gridY ?? 0) "
                      + "rect=\(state?.rect == true) wrap=\(state?.wrap == true) "
                      + "bilinear=\(state?.bilinear == true) realtime=\(state?.realtime == true) "
                      + "mesh=\(mesh == nil ? "identity" : "\(mesh!.columns)x\(mesh!.rows)") \(corners)")
            }
        }

        if env["WINAMP_MODERN_RENDER_XUI"] != nil {
            func walk(_ objects: [WasabiObject]) {
                for object in objects {
                    if !object.scriptBindings.isEmpty {
                        print("XUI \(object.typeName) id=\(object.xmlID ?? "-") "
                              + "isXUITag=\(loaded.runtime.types.isXUITag(object.typeName)) "
                              + "scripts=\(object.scriptBindings.map { ($0.logicalPath as NSString).lastPathComponent }) "
                              + "onsetxuiparam=\(runtime.hasBinding(for: object, event: "onsetxuiparam")) "
                              + "onscriptloaded=\(runtime.hasBinding(for: object, event: "onscriptloaded"))")
                    }
                    walk(object.children)
                }
            }
            walk(loaded.runtime.graph.roots)
        }
        // WINAMP_MODERN_RENDER_SCRIPTS answers the question `WINAMP_MODERN_RENDER_XUI` cannot: for
        // every parsed program, who owns it, whether its `onScriptLoaded` actually *ran* (or failed and
        // with what), and where the objects it hooks ended up. `hasBinding` reads the bytecode's
        // declared bindings; only the dispatch tap sees execution.
        if env["WINAMP_MODERN_RENDER_SCRIPTS"] != nil {
            for program in runtime.programs {
                let key = ObjectIdentifier(program)
                let owner = program.ownerID.flatMap(loaded.runtime.graph.object(withID:))
                let handlers = Set(program.bindings.map { program.methods[$0.methodIndex].name })
                print("SCRIPT \((program.source.path as NSString).lastPathComponent) "
                      + "owner=\(owner?.typeName ?? "-")#\(owner?.xmlID ?? "-") "
                      + "param=\(program.parameter ?? "-") "
                      + "handlers=\(handlers.sorted().joined(separator: ",")) "
                      + "ran=\((executedEvents[key] ?? []).sorted().joined(separator: ",")) "
                      + "failed=\(failedEvents[key]?.map { "\($0.key): \($0.value)" }.sorted().joined(separator: " | ") ?? "-")")
                // What each handler is bound *to* right now. A binding whose variable is still null is
                // a script whose `onScriptLoaded` never assigned it, and one pointing at the wrong
                // object is a lookup that resolved somewhere unexpected — the two failure modes behind
                // "the event dispatches to 0 handlers".
                for binding in program.bindings {
                    let event = program.methods[binding.methodIndex].name
                    guard env["WINAMP_MODERN_RENDER_SCRIPTS"] == "bindings" else { continue }
                    let variable = program.variables[binding.variableIndex]
                    var bound = "null"
                    if case .object(let reference) = variable.value {
                        switch reference.kind {
                        case .system: bound = "System"
                        case .gui(let id):
                            let object = loaded.runtime.graph.object(withID: id)
                            bound = "\(object?.typeName ?? "?")#\(object?.xmlID ?? "-")"
                        case .popupMenu: bound = "PopupMenu"
                        case .dynamic: bound = "dynamic"
                        }
                    }
                    print("SCRIPT   bind \(event) -> \(bound)"
                          + (variable.isClass ? " (class, \(variable.classMembers.count) members)" : ""))
                }
                // ClassicPro addresses other scripts by walking `getParent()` a fixed number of times
                // (`CproTabs.m` reaches the SUI with four of them), so the exact ancestor chain of a
                // script's own group is load-bearing and worth printing.
                if let owner {
                    var chain: [String] = []
                    var node: WasabiObject? = owner.parent
                    while let current = node, chain.count < 8 {
                        chain.append("\(current.typeName)#\(current.xmlID ?? "-")")
                        node = current.parent
                    }
                    print("SCRIPT   ancestors=\(chain.joined(separator: " < "))")
                }
                // The D6 subject: a runtime-created `cpro.tab` group's button is what
                // `CproTabButton.maki` resolves through `getScriptGroup().findObject(...)`, so print
                // the same lookup and the handler state it should have left behind.
                guard let owner, owner.xmlID?.lowercased().hasPrefix("cpro.tab") == true else { continue }
                for id in ["cpro.tab.button", "cpro.tab.text", "cpro.tab.grid"] {
                    guard let found = Self.descendant(of: owner, xmlID: id) else {
                        print("SCRIPT   findObject(\(id))=nil")
                        continue
                    }
                    let hooks: [String] = ["onleftbuttondown", "onleftbuttonup", "onmousemove",
                                           "onleftbuttondblclk"]
                        .filter { runtime.hasBinding(for: found, event: $0) }
                    print("SCRIPT   findObject(\(id))=\(found.typeName)#\(found.xmlID ?? "-") "
                          + "mouseHandlers=\(hooks.joined(separator: ","))")
                }
            }
        }
        // WINAMP_MODERN_RENDER_DISASM=<method> — the instructions around every call site of a method,
        // which is how an unknown **arity** is settled. The compiler emits the receiver, then one push
        // per argument, then the call, so counting the pushes between the receiver and the call gives
        // the argument count — the one thing the interpreter cannot guess and cannot recover from
        // getting wrong.
        //
        // `WINAMP_MODERN_RENDER_DISASM=@<source-substring>` instead lists a whole program: every
        // handler's entry point and every instruction, with constants and method names resolved. An
        // arity can be counted from a window of eight instructions; *what a handler computes* cannot,
        // and that is what a layout question ("who moves the titlebar streaks?") actually needs.
        if let wanted = env["WINAMP_MODERN_RENDER_DISASM"]?.lowercased() {
            if wanted.hasPrefix("@") {
                let needle = String(wanted.dropFirst())
                for program in runtime.programs
                where program.source.path.lowercased().contains(needle) {
                    let owner = program.ownerID.flatMap(loaded.runtime.graph.object(withID:))
                    print("DISASM-ALL \(program.source.path) owner=\(owner?.typeName ?? "-")"
                          + "#\(owner?.xmlID ?? "-") param=\(program.parameter ?? "-")")
                    var entryPoints: [Int: [String]] = [:]
                    for binding in program.bindings where program.methods.indices.contains(binding.methodIndex) {
                        entryPoints[binding.instructionIndex, default: []]
                            .append(program.methods[binding.methodIndex].name)
                    }
                    for (index, step) in program.instructions.enumerated() {
                        if let events = entryPoints[index] {
                            print("DISASM-ALL   --- \(events.sorted().joined(separator: " / ")) ---")
                        }
                        var label = "op\(step.opcode)"
                        switch step.argument {
                        case .method(let m) where program.methods.indices.contains(m):
                            label += " \(program.methods[m].name)"
                        case .variable(let v) where program.variables.indices.contains(v):
                            let variable = program.variables[v]
                            label += " v\(v)=\(Self.describe(variable.value))"
                        case .instruction(let target):
                            label += " -> \(target)"
                        case .type(let t) where program.classes.indices.contains(t):
                            label += " \(program.classes[t])"
                        case .valueKind(_, let guid):
                            label += " member\(guid.map { " \($0)" } ?? "")"
                        default: break
                        }
                        print("DISASM-ALL   \(index): \(label)")
                    }
                }
            }
            for program in runtime.programs {
                for (index, instruction) in program.instructions.enumerated()
                where instruction.opcode == 24 || instruction.opcode == 112 {
                    guard case .method(let methodIndex) = instruction.argument,
                          program.methods.indices.contains(methodIndex),
                          program.methods[methodIndex].name.lowercased() == wanted else { continue }
                    let window = program.instructions[max(0, index - 8)...index]
                    let text = window.map { step -> String in
                        var label = "op\(step.opcode)"
                        if case .method(let m) = step.argument, program.methods.indices.contains(m) {
                            label += "(\(program.methods[m].name))"
                        }
                        if case .variable(let v) = step.argument { label += "(v\(v))" }
                        return label
                    }.joined(separator: " ")
                    print("DISASM \((program.source.path as NSString).lastPathComponent): \(text)")
                }
            }
        }
        // The measured-demand list: what the skin's load + `onscriptloaded` pass actually reached for
        // and did not find. Printed here so the harness answers "missing art, bad geometry, or a
        // script that never ran" in one run.
        let report = loaded.compatibilityReport(withRuntime: runtime)
        print("RENDER-DUMP compatibility level=\(report.level)\n\(report.summary)")
        for finding in report.findings.sorted(by: { $0.severity.rawValue < $1.severity.rawValue }) {
            print("FINDING [\(finding.severity)] \(finding.category.rawValue)/\(finding.code) "
                  + "×\(finding.count) \(finding.message) @\(finding.location ?? "-")")
        }

        // The reconciled surface picture: what the skin declared, what was embedded, what NullPlayer
        // synthesized, and what is left to the classic fallback.
        let inventory = loaded.surfaceInventory
        print("RENDER-DUMP arrangement=\(inventory.arrangement) "
              + "embedded=\(inventory.embeddedKinds.map(\.rawValue).sorted()) "
              + "declared=\(inventory.declaredContainers.map { "\($0.key.rawValue)=\($0.value)" }.sorted()) "
              + "synthesized=\(loaded.surfaceSynthesis.synthesizedContainers.map { "\($0.key.rawValue)=\($0.value)" }.sorted()) "
              + "fallback=\(loaded.surfaceSynthesis.unavailable.map(\.key.rawValue).sorted())")

        let containers = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        print("RENDER-DUMP containers: \(containers.map { "\($0.id) main=\($0.isMainPlayer)" })")
        XCTAssertFalse(containers.isEmpty, "Skin declares no window containers.")

        // The surface picture must be *consistent* for any skin, measured or not: each surface has
        // exactly one home, an SUI skin is never synthesized into, and nothing is synthesized that
        // the skin already shows. This is the assertion that would catch a duplicate playlist window.
        let hostedIDs = Set(containers.map(\.id))
        let catalog = WinampModernSurfaceCoordinator.makeCatalog(
            loadedSkin: loaded, hostedContainerIDs: hostedIDs,
            embeddedContainerID: containers.first(where: \.isMainPlayer)?.object.stableID)
        for kind in WinampModernSurfaceInventory.managedKinds {
            let embedded = inventory.embeddedKinds.contains(kind)
            let declared = inventory.declaredContainers[kind]
            let synthesized = loaded.surfaceSynthesis.synthesizedContainers[kind]
            if embedded {
                XCTAssertNil(synthesized,
                             "\(kind.rawValue) is embedded; synthesizing a window would duplicate it")
            }
            if let synthesized {
                XCTAssertEqual(inventory.arrangement, .separateWindows,
                               "an SUI skin's surfaces are embedded, not missing")
                XCTAssertNil(declared, "\(kind.rawValue) already has a declared window")
                XCTAssertTrue(hostedIDs.contains(synthesized),
                              "synthesized container '\(synthesized)' never opened")
            }
        }
        print("RENDER-DUMP catalog: \(catalog.summaryLine)")
        // Which containers the host's Skin Windows menu offers — the only way to open a window a skin
        // declares, names, and binds no button to (Phase 27.7). Printed after the catalog because a
        // container the catalog routes is deliberately not listed twice.
        let routed = catalog.routedContainerIDs
        print("RENDER-DUMP skin windows: "
              + "\(containers.filter { WinampModernContainerTopology.isListedInWindowMenu($0) && !routed.contains($0.id.lowercased()) }.map(WinampModernContainerTopology.displayName))")

        // Written beside the PNGs so a dump can be read without the console scrollback.
        let sidecar = [
            "skin: \((walPath as NSString).lastPathComponent)",
            "arrangement: \(inventory.arrangement)",
            "catalog: \(catalog.summaryLine)",
            "containers: \(containers.map(\.id).joined(separator: " "))",
            "",
            report.summary,
        ].joined(separator: "\n")
        try sidecar.write(to: dumpDirectory.appendingPathComponent("surfaces.txt"),
                          atomically: true, encoding: .utf8)

        for info in containers {
            // A fixed clock makes ticker/animation frames reproducible; set
            // WINAMP_MODERN_RENDER_CLOCK to a different value to capture a later frame.
            let clock = Double(env["WINAMP_MODERN_RENDER_CLOCK"] ?? "") ?? 0
            guard let renderer = try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                          containerID: info.id, clock: { clock }) else {
                print("RENDER-DUMP \(info.id): no renderable normal layout")
                continue
            }
            // Scripts ask this renderer where its objects landed, exactly as the app's window layer
            // does — without it `getWidth()` on a relatively-sized object answers its raw attribute
            // and the skin lays itself out against a negative number.
            runtime.resolvedGeometryRequested = { object in renderer.resolvedGeometry(of: object) }
            // Layer FX, as the app wires it — so a warped layer is warped in the dumped PNG too.
            renderer.layerFXProvider = { [weak runtime] in runtime?.layerFXMesh(for: $0) }
            // And the same settle the window layer drives, so a script that collapses a pane sees the
            // `onResize` it is waiting on — cPro's side-view buttons swap from it.
            var lastFrames: [WasabiObjectID: CGRect] = [:]
            runtime.geometryDidSettle = {
                let targets = renderer.resizeTargets()
                runtime.dispatchResize(targets: targets, previous: lastFrames)
                lastFrames = Dictionary(renderer.resizeTargets().map { ($0.object.stableID, $0.frame) },
                                        uniquingKeysWith: { _, latest in latest })
            }
            defer {
                runtime.resolvedGeometryRequested = nil
                runtime.geometryDidSettle = nil
            }
            for layoutID in renderer.availableLayoutIDs {
                _ = try? renderer.activateLayout(id: layoutID)
                // WINAMP_MODERN_RENDER_SIZE=WxH measures the scene at the *user's* window size rather
                // than only the size the layout declares. Clamped by the layout, exactly as a drag is.
                if let spec = env["WINAMP_MODERN_RENDER_SIZE"] {
                    let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2 {
                        _ = renderer.resize(to: CGSize(width: parts[0], height: parts[1]))
                    }
                }
                // WINAMP_MODERN_RENDER_EVENTS=[<container>/<layout>@]onresize,onplay,… drives the named
                // events in order before the scene is measured and drawn, which is how a symptom that
                // only appears *after* playback starts (cPro's beat vis) reproduces headlessly.
                if let spec = env["WINAMP_MODERN_RENDER_EVENTS"] {
                    let addressed = spec.contains("@")
                    let target = spec.split(separator: "@").first.map(String.init) ?? ""
                    let list = addressed ? spec.split(separator: "@").dropFirst().joined(separator: "@") : spec
                    let applies = addressed ? target == "\(info.id)/\(layoutID)"
                        : (info.isMainPlayer && layoutID == renderer.availableLayoutIDs.first)
                    if applies {
                        for event in list.split(separator: ",").map({
                            $0.trimmingCharacters(in: .whitespaces).lowercased()
                        }) where !event.isEmpty {
                            drive(event: event, renderer: renderer, runtime: runtime, host: host)
                        }
                    }
                }
                let size = renderer.canvasSize
                let minimum = renderer.layoutMinimumSize
                let declared = renderer.declaredMinimumSize
                let maximum = renderer.layoutMaximumSize
                print("RENDER-DUMP \(info.id)/\(layoutID): \(Int(size.width))x\(Int(size.height)), "
                      + "\(renderer.sceneNodes().count) nodes, "
                      + "min=\(Int(minimum.width))x\(Int(minimum.height)), "
                      + "declared=\(Int(declared.width))x\(Int(declared.height)), "
                      + "max=\(Int(maximum.width))x\(Int(maximum.height))")
                // WINAMP_MODERN_RENDER_PROBE=<container>/<layout> dumps that scene's node list.
                if env["WINAMP_MODERN_RENDER_PROBE"] == "\(info.id)/\(layoutID)" {
                    for node in renderer.sceneNodes() {
                        print("PROBE \(node.object.typeName) id=\(node.object.xmlID ?? "-") "
                              + "frame=\(node.frame) clip=\(node.clip) bitmap=\(node.bitmapID ?? "-") "
                              + "attrs=\(node.object.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
                    }
                }
                // WINAMP_MODERN_RENDER_MINIMUM names the objects that make the protective minimum
                // what it is: those overflowing one pixel below it but not at the skin's own size.
                if env["WINAMP_MODERN_RENDER_MINIMUM"] != nil {
                    let below = CGSize(width: max(1, minimum.width - 1), height: minimum.height)
                    let reference = Set(renderer.sceneNodes().map(\.object.stableID))
                    let failures = renderer.fitFailures(atCanvas: below, reference: reference)
                    let baseline = renderer.fitFailures(atCanvas: size, reference: reference)
                    let culprits = failures.overflowing.union(failures.missing)
                        .subtracting(baseline.overflowing.union(baseline.missing))
                    let named = renderer.sceneNodes().filter { culprits.contains($0.object.stableID) }
                    print("MINIMUM \(info.id)/\(layoutID) below=\(Int(below.width)): "
                          + named.map { "\($0.object.typeName)#\($0.object.xmlID ?? "-")" }
                            .joined(separator: " "))
                }
                // WINAMP_MODERN_RENDER_CLICKABLE lists objects the markup-only hit test rejects but
                // a script hooks the mouse on — the ClassicPro SUI tabs are the measured case.
                if env["WINAMP_MODERN_RENDER_CLICKABLE"] != nil {
                    let events = ["onleftbuttondown", "onleftbuttonup", "onleftclick"]
                    let scripted = renderer.sceneNodes().filter { node in
                        renderer.object(at: CGPoint(x: node.frame.midX, y: node.frame.midY)) !== node.object
                            && events.contains { runtime.hasBinding(for: node.object, event: $0) }
                    }
                    print("CLICKABLE \(info.id)/\(layoutID): "
                          + scripted.map { "\($0.object.typeName)#\($0.object.xmlID ?? "-")\($0.frame)" }
                            .joined(separator: " "))
                }
                // WINAMP_MODERN_RENDER_CLICK=<container>/<layout>@x,y drives a real click through the
                // same sequence the view uses, and reports what the scene did about it. Several points
                // may be given as `x,y;x,y` and are driven **in order** — which is how a "does the
                // second click undo the first" question gets answered (cPro's close/open side buttons
                // sit at the same place, one hidden behind the other).
                if let spec = env["WINAMP_MODERN_RENDER_CLICK"],
                   spec.hasPrefix("\(info.id)/\(layoutID)@") {
                    let points = (spec.split(separator: "@").last?.split(separator: ";") ?? [])
                        .compactMap { entry -> CGPoint? in
                            let coords = entry.split(separator: ",").compactMap { Double($0) }
                            return coords.count == 2 ? CGPoint(x: coords[0], y: coords[1]) : nil
                        }
                    for point in points {
                        // Every object in the graph, not only the ones currently on screen: a control
                        // that was hidden and becomes visible is exactly what a click like this does
                        // (cPro swaps its close-side button for its open-side one).
                        var beforeState: [WasabiObjectID: String] = [:]
                        func record(_ objects: [WasabiObject]) {
                            for object in objects {
                                beforeState[object.stableID] = Self.state(of: object)
                                record(object.children)
                            }
                        }
                        record(loaded.runtime.graph.roots)
                        let target = renderer.object(at: point)
                        // There is no cursor here, and a button that asks `isMouseOverRect()` in its
                        // `onLeftButtonUp` gets "no" and takes its drag-cancelled path — so the probe
                        // would report a dead control that works perfectly under a real mouse. The
                        // pointer is placed where the click is, which is where it is in the app.
                        runtime.mousePositionInObjectSpaceRequested = { _ in point }
                        print("CLICK at \(point) hits "
                              + "\(target?.typeName ?? "-")#\(target?.xmlID ?? "-") "
                              + "bindings=\(target.map { runtime.hasBinding(for: $0) } ?? false)"
                              + (target.flatMap { renderer.frame(of: $0) }.map { " frame=\($0)" } ?? "")
                              + (target?.attributes["image"].map { " image=\($0)" } ?? ""))
                        // Every handler the click reaches, in order — the only way to see where a
                        // chain of script-to-script messages stops (the D6 subject: a tab's
                        // `onLeftButtonUp` → `sendAction("show_tab")` → the SUI's `onAction`).
                        var chain: [String] = []
                        runtime.dispatchObserver = { event, program, failure in
                            chain.append("\((program.source.path as NSString).lastPathComponent)."
                                         + event + (failure == nil ? "" : "!FAILED"))
                        }
                        defer {
                            print("CLICK chain: \(chain.joined(separator: " -> "))")
                            runtime.dispatchObserver = nil
                        }
                        if let target {
                            // `onleftbuttondblclk` is included because the view sends it (on
                            // `clickCount == 2`) between the down and the up, and skins put real
                            // commands on it — cPro cycles its beat animations from one.
                            for event in ["onleftbuttondown", "onleftbuttondblclk", "onleftbuttonup",
                                          "onleftclick", "onrightbuttonup"] {
                                // The button events carry the click's x/y, exactly as the view sends
                                // them: a handler that pops two arguments off an empty stack fails
                                // with an underflow that belongs to the harness, not the skin.
                                let arguments: [MakiValue] = event == "onleftclick" ? []
                                    : [.integer(Int32(point.x)), .integer(Int32(point.y))]
                                if event == "onrightbuttonup" {
                                    // No view here to show a menu, so record what the skin built.
                                    runtime.popupPresenter = { items, point in
                                        let where_ = point.map { " at \(Int($0.x)),\(Int($0.y))" } ?? ""
                                        print("CLICK menu\(where_): " + Self.describe(items))
                                        return 0
                                    }
                                }
                                let handled = (try? runtime.dispatch(object: target, event: event,
                                                                     arguments: arguments)) ?? -1
                                print("CLICK   \(event) -> \(handled)")
                            }
                        }
                        // A `cfgattrib`-bound control carries no `action`; the binding is what it
                        // does, and the *view* is what performs it. Mirror that here so a settings
                        // switch can be driven headlessly, and report the stored value either side.
                        if let target, let binding = WinampModernScriptRuntime.configBinding(of: target) {
                            let before = runtime.configValue(of: target)
                            runtime.toggleConfigAttribute(of: target)
                            print("CLICK cfgattrib \(binding.section);\(binding.key) "
                                  + "\(before) -> \(runtime.configValue(of: target))")
                        }
                        // Skins gate a transition on a timer — Defix's tab switch is literally
                        // `if (anim.isRunning()) return; anim.start();` — so with nothing pumping the
                        // run loop the timer never fires, never stops, and every click after the first
                        // returns at that guard. The app has a run loop; the harness has to borrow one,
                        // or a working tab strip measures as a strip where only the first tab responds.
                        if let settle = env["WINAMP_MODERN_RENDER_SETTLE"].flatMap(Double.init) {
                            RunLoop.current.run(until: Date().addingTimeInterval(settle))
                        }
                        // What the click actually *changed* in the scene — the question a click probe
                        // exists to answer. A control that swaps two buttons or moves a splitter shows
                        // up here even when the node count is identical.
                        for (id, before) in beforeState {
                            let object = loaded.runtime.graph.object(withID: id)
                            let after = object.map { Self.state(of: $0) }
                            guard let after, after != before else { continue }
                            print("CLICK changed \(object?.typeName ?? "?")#\(object?.xmlID ?? "-") "
                                  + "\(before) -> \(after)")
                        }
                        // WINAMP_MODERN_RENDER_CLICK_WATCH=id,id — where these objects ended up after
                        // the click, whether or not they changed. For "it opened, but in the wrong
                        // place" questions, which a changed-attributes list cannot answer.
                        for id in (env["WINAMP_MODERN_RENDER_CLICK_WATCH"] ?? "")
                            .split(separator: ",").map(String.init) where !id.isEmpty {
                            for object in loaded.runtime.graph.objects(xmlID: id) {
                                let geometry = renderer.resolvedGeometry(of: object)
                                print("CLICK watch \(object.typeName)#\(id) "
                                      + "frame=\(geometry.map { "\($0.frame)" } ?? "not laid out") "
                                      + "state=[\(Self.state(of: object))]")
                            }
                        }
                        // Whether the click left the *bindings* where it found them. A handler that
                        // runs and does nothing on every click after the first is usually a variable
                        // the dispatch itself moved, and that is invisible in the state diff above.
                        if env["WINAMP_MODERN_RENDER_SCRIPTS"] != nil {
                            for program in runtime.programs {
                                for binding in program.bindings
                                where program.methods[binding.methodIndex].name == "onleftclick" {
                                    let variable = program.variables[binding.variableIndex]
                                    var bound = "null"
                                    if case .object(let reference) = variable.value,
                                       case .gui(let id) = reference.kind {
                                        let object = loaded.runtime.graph.object(withID: id)
                                        bound = "\(object?.xmlID ?? "-")"
                                    }
                                    print("CLICK bind onleftclick -> \(bound)")
                                }
                            }
                        }
                        print("CLICK volume: \(host.volume)")
                        print("CLICK after: \(renderer.sceneNodes().count) nodes, holders="
                              + renderer.componentHolders().map { "\($0.kind.rawValue)" }.joined(separator: ","))
                        // A handler that ran to *zero* handlers is a binding problem; one that ran
                        // and failed is a missing capability, and only a report taken after the
                        // click can tell you which — the load-time one was clean before it.
                        for finding in loaded.compatibilityReport(withRuntime: runtime).findings
                        where finding.category == .scripts || finding.category == .unsupportedMethods {
                            print("CLICK finding: \(finding.code) ×\(finding.count) \(finding.message)")
                        }
                    }
                }
                let dividers = renderer.frameDividers()
                if !dividers.isEmpty {
                    print("DIVIDERS \(info.id)/\(layoutID): "
                          + dividers.map { "\($0.object.xmlID ?? "-")\($0.rect)"
                              + (($0.isVertical) ? "|" : "-") }.joined(separator: " "))
                }
                let holders = renderer.componentHolders()
                if !holders.isEmpty {
                    print("HOLDERS \(info.id)/\(layoutID): "
                          + holders.map { "\($0.kind.rawValue)@\($0.object.xmlID ?? "-")\($0.frame)" }
                            .joined(separator: " "))
                }
                if env["WINAMP_MODERN_RENDER_BITMAPS"] != nil {
                    var missing: Set<String> = []
                    var resolved = 0
                    for node in renderer.sceneNodes() {
                        for id in [node.bitmapID, node.object.attributes["background"]].compactMap({ $0 }) {
                            if renderer.resources.bitmap(identifier: id) == nil { missing.insert(id) }
                            else { resolved += 1 }
                        }
                    }
                    print("BITMAPS \(info.id)/\(layoutID): resolved=\(resolved) "
                          + "missing=\(missing.sorted().joined(separator: " "))")
                }
                guard size.width >= 1, size.height >= 1,
                      let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { continue }
                // `drawText` ends in `NSString.draw(in:withAttributes:)`, which renders into the
                // *current NSGraphicsContext* — not the CGContext it was handed. Without this the
                // harness silently drops every TrueType/system-font string while the real app (which
                // always has a current context inside `NSView.draw`) shows them.
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                renderer.draw(in: context)
                // WINAMP_MODERN_RENDER_TIME=<frames> repaints the whole scene that many times and
                // reports the per-frame cost — the measurement behind "does this skin hold 30 Hz?",
                // and the one Layer FX needs, since a warp is a CPU resample on the paint path. Each
                // pass re-evaluates every FX mesh, as a moving meter does.
                if let frames = env["WINAMP_MODERN_RENDER_TIME"].flatMap(Int.init), frames > 0 {
                    // WINAMP_MODERN_RENDER_TIME_SCALE=2 measures the *backing-store* cost the app
                    // actually pays on a Retina display, where every draw is at twice the linear size.
                    let scale = env["WINAMP_MODERN_RENDER_TIME_SCALE"].flatMap(Double.init) ?? 1
                    let scaled = CGContext(data: nil, width: Int(size.width * scale),
                                           height: Int(size.height * scale),
                                           bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    let target = scale == 1 ? context : (scaled ?? context)
                    if scale != 1 { target.scaleBy(x: scale, y: scale) }
                    // WINAMP_MODERN_RENDER_TIME_CLIP=1 measures the same frame clipped to the union
                    // of the warped layers' own rects — what a targeted `setNeedsDisplay(rect)` would
                    // cost, against repainting the whole window for a meter that moved.
                    var clip: CGRect?
                    if env["WINAMP_MODERN_RENDER_TIME_CLIP"] != nil {
                        for object in runtime.enabledLayerFXObjects {
                            guard let frame = renderer.resolvedGeometry(of: object)?.frame else { continue }
                            clip = clip.map { $0.union(frame) } ?? frame
                        }
                    }
                    let start = Date()
                    for _ in 0..<frames {
                        for object in runtime.enabledLayerFXObjects { runtime.invalidateLayerFXMesh(for: object) }
                        if let clip {
                            target.saveGState()
                            target.clip(to: CGRect(x: clip.minX, y: size.height - clip.maxY,
                                                   width: clip.width, height: clip.height))
                            renderer.draw(in: target)
                            target.restoreGState()
                        } else {
                            renderer.draw(in: target)
                        }
                    }
                    let milliseconds = Date().timeIntervalSince(start) * 1000 / Double(frames)
                    for (name, total) in WasabiSceneRenderer.drawProfile.sorted(by: { $0.value > $1.value }).prefix(8) {
                        print(String(format: "DRAW-PROFILE %@ %.2f ms/frame", name, total * 1000 / Double(frames)))
                    }
                    WasabiSceneRenderer.drawProfile.removeAll()
                    print(String(format: "RENDER-TIME %@/%@: %.2f ms/frame over %d frames "
                                 + "(%d FX layers)", info.id, layoutID, milliseconds, frames,
                                 runtime.enabledLayerFXObjects.count))
                }
                NSGraphicsContext.current = previous
                guard let image = context.makeImage() else { continue }
                let url = dumpDirectory.appendingPathComponent("\(info.id)-\(layoutID).png")
                let rep = NSBitmapImageRep(cgImage: image)
                try rep.representation(using: .png, properties: [:])?.write(to: url)
                print("RENDER-DUMP wrote \(url.path)")
            }
            renderer.teardown()
        }
    }

    /// Drive one named event at its real target with its real arguments.
    ///
    /// The arity matters as much as the target: a handler that pops four arguments off an empty stack
    /// fails with an underflow that belongs to the harness, not to the skin. `onresize` is the only
    /// GUI-addressed one here, and it carries each object's own frame (see `dispatchResize`).
    private func drive(event: String, renderer: WasabiSceneRenderer,
                       runtime: WinampModernScriptRuntime, host: RenderHost) {
        switch event {
        case "onresize":
            let dispatched = runtime.dispatchResize(targets: renderer.resizeTargets(), previous: nil)
            print("EVENT onresize -> \(dispatched) handlers over \(renderer.resizeTargets().count) targets")
        case "onplay", "onresume":
            host.playbackState = .playing
            print("EVENT \(event) -> \((try? runtime.dispatchSystem(event: event)) ?? -1)")
        case "onpause":
            host.playbackState = .paused
            print("EVENT \(event) -> \((try? runtime.dispatchSystem(event: event)) ?? -1)")
        case "onstop":
            host.playbackState = .stopped
            print("EVENT \(event) -> \((try? runtime.dispatchSystem(event: event)) ?? -1)")
        case "ontitlechange":
            let handled = (try? runtime.dispatchSystem(event: event,
                                                       arguments: [.string(host.trackDisplayTitle)])) ?? -1
            print("EVENT \(event) -> \(handled)")
        case "onvolumechanged":
            let handled = (try? runtime.dispatchSystem(
                event: event, arguments: [.integer(Int32((host.volume * 255).rounded()))])) ?? -1
            print("EVENT \(event) -> \(handled)")
        default:
            print("EVENT \(event): no harness target/arity — add one to `drive(event:…)`")
        }
    }

    /// A script-built menu as one line: `Title > [child, …]`, separators as `--`.
    private static func describe(_ items: [WinampModernPopupMenuItem]) -> String {
        items.map { item in
            if item.isSeparator { return "--" }
            let flags = (item.checked ? "*" : "") + (item.disabled ? "!" : "")
            guard !item.children.isEmpty else { return "\(flags)\(item.title)#\(item.commandID)" }
            return "\(flags)\(item.title) > [\(describe(item.children))]"
        }.joined(separator: ", ")
    }

    /// The attributes a click is likely to move: geometry, visibility, and which art is showing.
    private static func state(of object: WasabiObject) -> String {
        ["x", "y", "w", "h", "visible", "image", "position", "text"]
            .compactMap { key in object.attributes[key].map { "\(key)=\($0)" } }
            .joined(separator: " ")
    }

    /// First descendant with this `id`, matching `findObject`'s own search.
    private static func descendant(of root: WasabiObject, xmlID: String) -> WasabiObject? {
        for child in root.children {
            if child.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return child }
            if let match = descendant(of: child, xmlID: xmlID) { return match }
        }
        return nil
    }

    /// A MAKI constant as it reads in source, for the `@` listing.
    private static func describe(_ value: MakiValue) -> String {
        switch value {
        case .null: return "null"
        case .integer(let v): return "\(v)"
        case .float(let v): return "\(v)f"
        case .double(let v): return "\(v)"
        case .boolean(let v): return "\(v)"
        case .string(let v): return "\"\(v)\""
        case .object: return "object"
        }
    }

    private final class RenderHost: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 73
        var duration: TimeInterval = 245
        var volume: Double = 0.7
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "A Very Long Song Title That Must Scroll Across The Display"
        var trackInfo = "NullPlayer QA"
        var trackDisplayTitle = "Some Artist - A Very Long Song Title That Must Scroll Across The Display"
        var bitrateKbps = 320
        var sampleRateHz = 44_100
        var channelCount = 2
        var spectrumLevels: [Float] = (0..<64).map { Float(($0 % 16)) / 16 }
        /// WINAMP_MODERN_RENDER_VU=<left>[,<right>] injects a program level per channel (0…1), the
        /// unit `getLeftVUMeter`/`getRightVUMeter` answer in. It is what makes a meter *deflect*
        /// headlessly — the harness has no audio, so without it every VU reads silence.
        var vuLevels: (left: Double, right: Double) {
            let spec = ProcessInfo.processInfo.environment["WINAMP_MODERN_RENDER_VU"] ?? ""
            // `sweep` oscillates 0…1 at 0.5 Hz, which is what makes a *meter* measurable headlessly:
            // a needle at a fixed level tells you nothing about how it follows one.
            if spec == "sweep" {
                let phase = ProcessInfo.processInfo.systemUptime * 0.5
                let level = 0.5 - 0.5 * cos(phase * 2 * .pi)
                return (level, level)
            }
            let values = spec.split(separator: ",").compactMap { Double($0) }
            guard let left = values.first else { return (0, 0) }
            return (left, values.count > 1 ? values[1] : left)
        }

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
