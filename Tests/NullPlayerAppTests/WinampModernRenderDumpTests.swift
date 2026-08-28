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
        guard let walPath = env["WINAMP_MODERN_WAL"] else {
            throw XCTSkip("Set WINAMP_MODERN_WAL and WINAMP_MODERN_RENDER_DUMP (and WINAMP_MODERN_ENGINE for cPro).")
        }
        // A probe-only run needs no PNGs. `WINAMP_MODERN_RENDER_THEMES` is asked of all sixteen
        // installed skins in one loop, and requiring a dump directory for each of them buys nothing
        // but sixteen directories of images nobody looks at.
        let isProbeOnly = env["WINAMP_MODERN_RENDER_THEMES"] != nil
            || env["WINAMP_MODERN_RENDER_PALETTE"] != nil
        guard let dumpPath = env["WINAMP_MODERN_RENDER_DUMP"] ?? (isProbeOnly
                ? NSTemporaryDirectory() + "WinampModernRenderDump-\(UUID().uuidString)" : nil) else {
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

        // WINAMP_MODERN_RENDER_PLAYLIST=<count>[,current=<n>] stands a synthetic queue up behind the
        // component seam **before** the scripts start, which is the only way a `.wal` skin's
        // playlist-editor API can be observed headlessly: the dump harness sets no component host, so
        // `PlEdit` reads an empty queue and every script that walks it takes its empty branch. With
        // it, `PlEdit.getNumTracks`/`getTitle`/`getMetaData` answer, the drawn playlist panel is no
        // longer blank, and a script's `removeTrack`/`moveTo`/`clear` is visible in the "after" line
        // printed below (Phase 42). Pair it with `WINAMP_MODERN_CALL_TRACE=1` to see each call.
        var playlistHost: RenderComponentHost?
        if let spec = env["WINAMP_MODERN_RENDER_PLAYLIST"] {
            var count = 8
            var current = 0
            for entry in spec.split(separator: ",") {
                let text = entry.trimmingCharacters(in: .whitespaces)
                if let value = Int(text) { count = value }
                else if text.lowercased().hasPrefix("current="), let value = Int(text.dropFirst(8)) {
                    current = value
                }
            }
            let host = RenderComponentHost(count: max(0, count), current: current)
            playlistHost = host
            runtime.componentHost = host
            WasabiTextMetrics.componentTextProvider = { [weak host] in host?.playlistSnapshot() }
            runtime.playlistRevealRowRequested = { print("PLAYLIST reveal row=\($0)") }
            print("PLAYLIST before: \(host.describe())")
        }

        // `layout.setScale(f)` — a skin driving the host's **UI Size** (Phase 46, B12). The harness
        // owns no windows, so this is the only place the request can be seen at all; it is installed
        // before `start()` because the five scripts that carry it call it from `onScriptLoaded`, and
        // it names the level the app would snap to so a button that asks for 250% is not confused
        // with one that asks for 200%.
        runtime.uiScaleRequested = { factor in
            print(String(format: "SCALE request %.3f -> %@%%", Double(factor),
                         UIScaleLevel.nearest(toScaleFactor: factor).rawValue))
        }

        // Every container's renderer, built **before** `start()` and asked in turn — the app is the
        // model here (`wireContainerCallbacks` installs this closure before `scripts.start()` and
        // consults every container's view). Installed inside the per-container loop instead, as it
        // used to be, it is absent for the whole of `onScriptLoaded` — and skins do nearly all of
        // their layout there, so every `getWidth`/`getLeft`/`getGuiW` fell back to the raw markup
        // attribute: `0` for a `w="0" relatw="1"` group, `-7` for a `w="-7"` one. Big Bento's
        // visualizer measured `getwidth() -> 0` headlessly against `346` in the app, and the harness
        // then agreed with the symptom for the wrong reason (BB20).
        let dumpClock = Double(env["WINAMP_MODERN_RENDER_CLOCK"] ?? "") ?? 0
        var renderersByContainer: [String: WasabiSceneRenderer] = [:]
        for info in WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph) {
            guard let renderer = try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                          containerID: info.id,
                                                          clock: { dumpClock }) else { continue }
            renderersByContainer[info.id] = renderer
        }
        let allRenderers = Array(renderersByContainer.values)
        runtime.resolvedGeometryRequested = { object in
            for renderer in allRenderers {
                if let geometry = renderer.resolvedGeometry(of: object) { return geometry }
            }
            return nil
        }

        try runtime.start()

        if let settle = env["WINAMP_MODERN_RENDER_SETTLE"].flatMap(Double.init) {
            RunLoop.current.run(until: Date().addingTimeInterval(settle))
            // The harness has no component host, so `PE_Info` reads empty and a skin that drives its
            // readouts from `onTextChanged` can never be seen to do it. Seed the cache empty, then
            // stand a synthetic queue up behind it — the same "it changed" the app produces when the
            // playlist is edited, which is the only thing that raises the event.
            runtime.refreshBoundText()
            if playlistHost == nil {
                WasabiTextMetrics.componentTextProvider = {
                    WinampModernPlaylistSnapshot(
                        rows: (0..<3).map { WinampModernPlaylistRow(title: "t\($0)", secondary: "",
                                                                    duration: 120, isCurrent: $0 == 0) },
                        currentIndex: 0, selectedIndex: 0)
                }
            }
            runtime.refreshBoundText()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        // WINAMP_MODERN_RENDER_EQ=<band>=<value>[,…] drives an equalizer change from *outside* the
        // skin — the route the app takes when a preset, the menu bar or the classic equalizer window
        // moves it — and reports the handlers it reached. `band` is 0…9 or `preamp`; `value` is
        // MAKI's −127…127. Bare `1` sweeps every band. Without it the harness installs no equalizer at
        // all, so `System.getEqBand` answers 0 and the events never fire (Phase 41).
        if let spec = env["WINAMP_MODERN_RENDER_EQ"] {
            var bands = Array(repeating: 0, count: WinampModernEQAction.bandCount)
            var preamp = 0
            runtime.equalizerBandRequested = { bands.indices.contains($0) ? bands[$0] : 0 }
            runtime.equalizerBandSetterRequested = { band, value in
                guard bands.indices.contains(band) else { return }
                bands[band] = value
            }
            runtime.equalizerPreampRequested = { preamp }
            runtime.equalizerPreampSetterRequested = { preamp = $0 }
            // Seed silently: the opening state is announced once, and what this probe is asking about
            // is the *change* the skin is told about afterwards.
            runtime.refreshEqualizerState()
            if spec.trimmingCharacters(in: .whitespaces) == "1" {
                for index in bands.indices { bands[index] = index % 2 == 0 ? 96 : -96 }
                preamp = 48
            } else {
                for entry in spec.split(separator: ",") {
                    let parts = entry.split(separator: "=", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    guard parts.count == 2, let value = Int(parts[1]) else { continue }
                    if parts[0].lowercased() == "preamp" { preamp = value }
                    else if let band = Int(parts[0]), bands.indices.contains(band) { bands[band] = value }
                }
            }
            let previousObserver = runtime.dispatchObserver
            runtime.dispatchObserver = { event, program, failure in
                guard event == "oneqbandchanged" || event == "oneqpreampchanged" else { return }
                print("EQ handler \(event) -> \((program.source.path as NSString).lastPathComponent)"
                      + (failure == nil ? "" : " !FAILED: "
                         + failure!.diagnostics.map(\.message).joined(separator: "; ")))
            }
            runtime.refreshEqualizerState()
            runtime.dispatchObserver = previousObserver
            print("EQ drove preamp=\(preamp) bands=\(bands)")
            // What a skin reads *instead* of the event: multipass's fillbars re-read their slider.
            for object in loaded.runtime.graph.allObjectsUnordered
            where object.typeName.caseInsensitiveCompare("slider") == .orderedSame
                && WinampModernEQAction.decode(action: object.attributes["action"],
                                               parameter: object.attributes["param"]) != nil {
                print("EQ slider \(object.xmlID ?? "-") action=\(object.attributes["action"] ?? "-")"
                      + " param=\(object.attributes["param"] ?? "-")"
                      + " position=\(object.attributes["value"] ?? "-")")
            }
        }

        // WINAMP_MODERN_RENDER_TEXT=1 polls the host-bound text objects the way the running window
        // does, so `onTextChanged` — the handler a skin hangs its whole per-track readout logic off —
        // fires here too. Nothing else in the harness drives it: the poll lives in the window
        // controller, so every `onTextChanged` in the corpus measured as an unreached handler and a
        // skin whose readouts are written only from it read as a skin with no readouts (B38.3).
        if env["WINAMP_MODERN_RENDER_TEXT"] != nil {
            let previousObserver = runtime.dispatchObserver
            var reached = 0
            runtime.dispatchObserver = { event, program, failure in
                guard event == "ontextchanged" else { return }
                reached += 1
                print("TEXT handler -> \((program.source.path as NSString).lastPathComponent)"
                      + " owner=\(program.ownerID.flatMap(loaded.runtime.graph.object(withID:))?.xmlID ?? "-")"
                      + (failure == nil ? "" : " !FAILED: "
                         + failure!.diagnostics.map(\.message).joined(separator: "; ")))
            }
            runtime.refreshBoundText()
            runtime.dispatchObserver = previousObserver
            print("TEXT ontextchanged handlers=\(reached)")
            for object in loaded.runtime.graph.allObjectsUnordered
            where runtime.hasBinding(for: object, event: "ontextchanged") {
                print("TEXT bound \(object.typeName)#\(object.xmlID ?? "-")"
                      + " display=\(object.attributes["display"] ?? "-")"
                      + " text=\(WasabiTextMetrics.content(of: object, host: host))")
            }
        }

        // WINAMP_MODERN_RENDER_KEY=<accelerator>[,<accelerator>] presses keys at the skin the way the
        // window does — `System.onKeyDown("alt+g")` — and reports the handlers each one reached, in
        // order, plus whether any of them ran MAKI's `complete;` (which is what tells the view to
        // swallow the key). Accelerators are Winamp's own lowercase strings: `alt+g`, `ctrl+w`, `esc`.
        // Without it there is no keyboard in the harness at all and every `onKeyDown` in the corpus
        // measures as an unreached handler (Phase 43).
        if let spec = env["WINAMP_MODERN_RENDER_KEY"] {
            for entry in spec.split(separator: ",") {
                let accelerator = entry.trimmingCharacters(in: .whitespaces).lowercased()
                guard !accelerator.isEmpty else { continue }
                let previousObserver = runtime.dispatchObserver
                var reached = 0
                runtime.dispatchObserver = { event, program, failure in
                    guard event == "onkeydown" else { return }
                    reached += 1
                    print("KEY handler \(accelerator) -> \((program.source.path as NSString).lastPathComponent)"
                          + (failure == nil ? "" : " !FAILED: "
                             + failure!.diagnostics.map(\.message).joined(separator: "; ")))
                }
                let consumed = runtime.dispatchKeyDown(accelerator)
                runtime.dispatchObserver = previousObserver
                print("KEY \(accelerator): handlers=\(reached) consumed=\(consumed ? 1 : 0)")
            }
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
        // `WINAMP_MODERN_RENDER_SHOW=<container>[,<container>]` opens auxiliary windows the way the
        // user does from the Skin Windows menu. Without it the harness can only ever see the windows
        // a skin opens by default, and a defect confined to one that starts hidden — Defix's speaker
        // cabinets, whose `getVisBand` timer starts from `onSetVisible` — is invisible to every probe.
        let shownContainers = Set((env["WINAMP_MODERN_RENDER_SHOW"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
        if env["WINAMP_MODERN_RENDER_FX"] != nil || !shownContainers.isEmpty {
            // `default_visible="1"` opens a window with the skin in the app (B6), so the harness sees
            // the same set: a probe that measured Defix's configurator as closed was measuring a
            // state the app no longer starts in.
            // `windowContainers`, not `analyze`: the app only opens containers that are real
            // windows, so a collapsed SUI stub that declares the attribute is not one of them.
            let defaultVisibleContainers = WinampModernContainerTopology
                .windowContainers(graph: loaded.runtime.graph)
                .filter { $0.opensByDefault && !$0.isMainPlayer }
            for info in defaultVisibleContainers {
                guard let suppression = WinampModernContainerTopology
                    .defaultVisibilitySuppression(of: info) else { continue }
                print("DEFAULT-VISIBLE \(info.id) suppressed: \(suppression.reason)")
            }
            let defaultVisible = Set(defaultVisibleContainers
                .filter { WinampModernContainerTopology.defaultVisibilitySuppression(of: $0) == nil }
                .map { $0.id.lowercased() })
            for container in loaded.runtime.graph.roots
            where container.typeName.caseInsensitiveCompare("container") == .orderedSame {
                let identifier = container.xmlID ?? ""
                let isMain = identifier.caseInsensitiveCompare("main") == .orderedSame
                let opensByDefault = defaultVisible.contains(identifier.lowercased())
                let isShown = shownContainers.contains(identifier.lowercased())
                runtime.notifyContainerVisibility(containerID: container.stableID,
                                                  visible: isMain || isShown || opensByDefault)
                if isShown { print("SHOW \(identifier)") }
                else if opensByDefault { print("SHOW \(identifier) (default_visible)") }
            }
            // A window that has just opened has not ticked yet: the timer `onSetVisible` starts is
            // the whole point of opening it, so settle *again* after the show or every probe below
            // measures the scene one frame after launch.
            if let settle = env["WINAMP_MODERN_RENDER_SETTLE"].flatMap(Double.init),
               !shownContainers.isEmpty || !defaultVisible.isEmpty {
                RunLoop.current.run(until: Date().addingTimeInterval(settle))
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

        // WINAMP_MODERN_RENDER_SET=<section>;<key>=<value>[|…] writes a registered setting **after**
        // the skin is up, which is what the host's Skin Settings window does and what
        // `WINAMP_MODERN_RENDER_CONFIG` deliberately cannot do: that one seeds the store *before*
        // `onScriptLoaded`, so a skin that keeps its own private copy of the value (Defix reads
        // `CurVuVis`, not the attribute) ignores it entirely. The change here goes through
        // `setConfigAttribute`, the single write route, so every script that registered the same
        // attribute gets `onDataChanged` — the only headless way to select one of a skin's display
        // styles or songticker modes and see what it draws (Phase 45).
        if let spec = env["WINAMP_MODERN_RENDER_SET"] {
            for entry in spec.split(separator: "|") {
                let parts = entry.split(separator: ";", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let assignment = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                guard assignment.count == 2 else { continue }
                let section = parts[0]
                let key = assignment[0]
                let previousObserver = runtime.dispatchObserver
                var reached = 0
                runtime.dispatchObserver = { event, program, failure in
                    guard event == "ondatachanged" else { return }
                    reached += 1
                    print("SET handler \(key) -> \((program.source.path as NSString).lastPathComponent)"
                          + (failure == nil ? "" : " !FAILED: "
                             + failure!.diagnostics.map(\.message).joined(separator: "; ")))
                }
                runtime.setConfigAttribute(section: section, key: key, value: assignment[1])
                runtime.dispatchObserver = previousObserver
                print("SET [\(section)] \(key) = \(assignment[1]) handlers=\(reached)")
            }
            // A skin applies part of a setting from a timer it starts in `onDataChanged`, so give it
            // the same settle the rest of the harness gets before anything is measured.
            if let settle = env["WINAMP_MODERN_RENDER_SETTLE"].flatMap(Double.init) {
                RunLoop.current.run(until: Date().addingTimeInterval(settle))
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
                        case .playlistEditor: bound = "PlEdit"
                        case .colorManager: bound = "ColorMgr"
                        case .popupMenu: bound = "PopupMenu"
                        case .dynamic: bound = "dynamic"
                        }
                    }
                    // The entry point tells two same-named bindings apart. A program may declare the
                    // same (object, event) twice with *different* bodies — Big Bento's `mcvcore`
                    // declares `System.onScriptLoaded` for its layout routine and again for a timer
                    // — and which body a dispatch reaches is then the whole question.
                    print("SCRIPT   bind \(event) v\(binding.variableIndex) -> \(bound)"
                          + " @\(binding.instructionIndex) body=\(program.bodyHash(of: binding))"
                          + (program.dispatchBindings.contains { $0.instructionIndex == binding.instructionIndex
                              && $0.variableIndex == binding.variableIndex } ? "" : " (shadowed)")
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
        // Only containers the app can actually open: a container whose layouts the renderer cannot
        // select is dropped by `setupAuxiliaryContainers` and never reaches the menu, and a probe
        // reading the raw topology reported it as offered anyway (B26, LOBE).
        let openable = containers.filter { WasabiSceneRenderer.primaryLayout(of: $0.object) != nil }
        print("RENDER-DUMP skin windows: "
              + "\(openable.filter { WinampModernContainerTopology.isListedInWindowMenu($0) && !routed.contains($0.id.lowercased()) }.map(WinampModernContainerTopology.displayName))")
        for dropped in containers where WasabiSceneRenderer.primaryLayout(of: dropped.object) == nil {
            print("RENDER-DUMP dropped container: \(dropped.id) (no layout)")
        }

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

        // WINAMP_MODERN_RENDER_PALETTE=1 — the colours NullPlayer's own surfaces (the embedded
        // library, and any playlist/EQ/library window a skin declares none of) are painted in, and
        // how each one resolved. The palette is skin-wide, so any container's renderer answers.
        if env["WINAMP_MODERN_RENDER_PALETTE"] != nil, let renderer = renderersByContainer.values.first {
            print("PALETTE skin: \((walPath as NSString).lastPathComponent) "
                  + "theme=\(loaded.themeCoordinator.catalog.activeTheme)")
            for line in renderer.paletteResolutionReport() { print(line) }
            // What the panel actually ends up filled with: `background` is the fill, and the derived
            // chrome roles are what a "black rectangle" complaint is really about.
            let style = WinampModernSurfaceStyle(palette: renderer.palette)
            func rgb(_ color: NSColor) -> String {
                guard let c = color.usingColorSpace(.deviceRGB) else { return "non-RGB" }
                return String(format: "rgb(%.0f,%.0f,%.0f)", c.redComponent * 255,
                              c.greenComponent * 255, c.blueComponent * 255)
            }
            print("PALETTE surface background=\(rgb(style.background)) bar=\(rgb(style.barBackground)) "
                  + "border=\(rgb(style.border)) divider=\(rgb(style.divider)) "
                  + "text=\(rgb(style.text)) dimText=\(rgb(style.dimText))")
        }

        var printedThemeCatalog = false
        // The scene walk only reaches what is *on screen*, and a colour-theme picker usually is not:
        // multipass, winampmodern566 and Anexa all keep theirs in a drawer or a window that starts
        // closed, so a scene-only probe reported "no picker" for three skins that ship a full one.
        // This is the declarative half — every list and every `colorthemes_*` action in the graph,
        // visible or not — and it is what the plan's per-skin table is re-derived from.
        if env["WINAMP_MODERN_RENDER_THEMES"] != nil {
            func container(of object: WasabiObject) -> String {
                var ancestor: WasabiObject? = object
                while let current = ancestor,
                      current.typeName.caseInsensitiveCompare("container") != .orderedSame {
                    ancestor = current.parent
                }
                return ancestor?.xmlID ?? "-"
            }
            func walkThemes(_ objects: [WasabiObject]) {
                for object in objects {
                    if WasabiSceneRenderer.isColorThemeList(object) {
                        print("THEMES graph-list \(container(of: object)) #\(object.xmlID ?? "-") "
                              + "visible=\(object.attributes["visible"] ?? "1")")
                    }
                    if let action = object.attributes["action"]?.lowercased(),
                       action.hasPrefix("colorthemes_") {
                        // What the target *is* matters as much as whether it resolves: a target that
                        // is not a `<ColorThemes:List>` is a skin driving its picker some other way,
                        // and that is a different feature (multipass names a group, not a list).
                        let resolved = (object.attributes["action_target"].map {
                            loaded.runtime.graph.objects(xmlID: $0)
                        } ?? []).map { "\($0.typeName)#\($0.xmlID ?? "-")" }
                        print("THEMES graph-action \(container(of: object)) \(action) "
                              + "on=\(object.typeName)#\(object.xmlID ?? "-") "
                              + "action_target=\(object.attributes["action_target"] ?? "-") "
                              + "resolves=\(resolved.isEmpty ? "nothing" : resolved.joined(separator: ","))")
                    }
                    walkThemes(object.children)
                }
            }
            walkThemes(loaded.runtime.graph.roots)
        }
        // The container `WINAMP_MODERN_RENDER_CLICK` names is dumped **first**, so every other window
        // is rendered *after* the click and shows what it did. Ordering matters more than it looks: a
        // click on Defix's configurator changes the background art of five other windows, and with the
        // configurator in its declared position (second to last) all five had already been written —
        // the probe reported a change no PNG in the dump could show (Phase 45).
        let clickedContainer = env["WINAMP_MODERN_RENDER_CLICK"]?
            .split(separator: "@").first?.split(separator: "/").first.map(String.init)
        let isClicked = { (id: String) in
            clickedContainer.map { id.caseInsensitiveCompare($0) == .orderedSame } ?? false
        }
        let orderedContainers = containers.filter { isClicked($0.id) }
            + containers.filter { !isClicked($0.id) }
        for info in orderedContainers {
            // A fixed clock makes ticker/animation frames reproducible; set
            // WINAMP_MODERN_RENDER_CLOCK to a different value to capture a later frame.
            // The renderer the scripts have been answering geometry from since before `start()` — the
            // same instance, not a second one, or the scene the skin laid itself out against is not
            // the scene that gets dumped.
            guard let renderer = renderersByContainer[info.id] else {
                print("RENDER-DUMP \(info.id): no renderable normal layout")
                continue
            }
            // Layer FX, as the app wires it — so a warped layer is warped in the dumped PNG too.
            renderer.layerFXProvider = { [weak runtime] in runtime?.layerFXMesh(for: $0) }
            // A `cfgattrib` control's state *is* the stored preference, and both app paths wire this.
            // Without it every switch in Defix's configurator dumped its "off" artwork whatever the
            // value was — nine indicators reading OFF against three settings that ship as 1, which is
            // a blind instrument reporting a defect the app does not have (Phase 45).
            renderer.configStateProvider = { [weak runtime] in runtime?.configValue(of: $0) ?? false }
            renderer.configValueProvider = { [weak runtime] in runtime?.configInteger(of: $0) }
            // The same synthetic queue the scripts see, so the drawn playlist panel is no longer the
            // empty box the harness has always produced (§2's documented blind spot).
            renderer.componentHost = playlistHost
            // And the same settle the window layer drives, so a script that collapses a pane sees the
            // `onResize` it is waiting on — cPro's side-view buttons swap from it.
            var lastFrames: [WasabiObjectID: CGRect] = [:]
            runtime.geometryDidSettle = {
                let targets = renderer.resizeTargets()
                runtime.dispatchResize(targets: targets, previous: lastFrames)
                lastFrames = Dictionary(renderer.resizeTargets().map { ($0.object.stableID, $0.frame) },
                                        uniquingKeysWith: { _, latest in latest })
            }
            // `resolvedGeometryRequested` stays installed — it belongs to the whole run now, not to
            // one container's turn in the loop.
            defer { runtime.geometryDidSettle = nil }
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
                        // Same rule as the settle after a window is shown: a skin routinely does the
                        // *work* of an event from a timer the handler starts, not in the handler. Big
                        // Bento's notifier starts a 30 ms poll from `onTitleChange` and lays the toast
                        // out on its first tick, so without this the scene is always measured one
                        // frame too early and the layout routine reads as one that never ran (BB27).
                        if let settle = env["WINAMP_MODERN_RENDER_SETTLE"].flatMap(Double.init) {
                            RunLoop.current.run(until: Date().addingTimeInterval(settle))
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
                // WINAMP_MODERN_RENDER_GEOMETRY=<id>[,<id>] — the resolved box of a named object and
                // of its direct children, **including hidden ones**. `RENDER_PROBE` walks the visible
                // scene, so anything inside a closed tab measures as absent: Big Bento's settings
                // pages live in one, and "is this content taller than its box?" — the whole question
                // behind a scrollbar — could not be asked at all without this.
                if let wanted = env["WINAMP_MODERN_RENDER_GEOMETRY"] {
                    let ids = Set(wanted.lowercased().split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) })
                    let all = renderer.layoutNodesForTesting()
                    for node in all where ids.contains(node.object.xmlID?.lowercased() ?? "") {
                        print("GEOM \(node.object.typeName)#\(node.object.xmlID ?? "-") "
                              + "frame=\(node.frame) clip=\(node.clip) "
                              + "visible=\(node.object.attributes["visible"] ?? "-") "
                              + "scroll=\(node.object.attributes[WasabiSceneRenderer.scrollPercentKey] ?? "-") "
                              + "children=\(node.object.children.count)")
                        var extent = node.frame.minY
                        for child in node.object.children {
                            let box = all.first { $0.object === child }
                            let declared = "y=\(child.attributes["y"] ?? "-") h=\(child.attributes["h"] ?? "-") "
                                + "low=\(child.attributes["low"] ?? "-") high=\(child.attributes["high"] ?? "-") "
                                + "value=\(child.attributes["value"] ?? "-")"
                            if let box { extent = max(extent, box.frame.maxY) }
                            print("GEOM   child \(child.typeName)#\(child.xmlID ?? "-") "
                                  + "frame=\(box.map { "\($0.frame)" } ?? "not laid out") \(declared)")
                        }
                        print("GEOM   content=\(extent - node.frame.minY) box=\(node.frame.height) "
                              + "travel=\(max(0, extent - node.frame.minY - node.frame.height))")
                    }
                }
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
                        // The host action a click ultimately asks for. A skin routes a visible button
                        // to a hidden one and calls `leftClick()` on it (Defix's round PL/EQ buttons
                        // reach `PLSBt`/`EQSwitch` that way), and the *view* is what performs the
                        // resulting action — so with nothing wired here the probe reported "nothing
                        // changed" for a button that works, and could not tell that apart from one
                        // that asks for an action the view does not implement.
                        runtime.actionRequested = { action, parameter in
                            print("CLICK action: \(action.isEmpty ? "-" : action) param=\(parameter ?? "-")")
                        }
                        defer { runtime.actionRequested = nil }
                        // The other half of "what did this click ask the host for": a skin that opens
                        // one of its own windows does it with `getContainer(id).show()`, which is a
                        // window request, not an action. There are no windows in the harness, so this
                        // is the only place it can be seen.
                        runtime.containerVisibilityRequested = { id, visible in
                            print("CLICK window: \(id) visible=\(visible)")
                        }
                        defer { runtime.containerVisibilityRequested = nil }
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
                            // `onrightbuttondown` is in the list because Wasabi's right button is a
                            // pair and a skin picks either half: Defix hangs its four "what does this
                            // button open" menus off the *down*, and while the probe drove only the up
                            // it reported four dead buttons that the skin implements fully.
                            // `WINAMP_MODERN_RENDER_CLICK_EVENTS=onleftbuttondown,onleftbuttonup`
                            // narrows the blast to the events a *plain* click sends. The full seven
                            // include the double-click and both right-button halves, and a skin that
                            // hangs a command off one of those (cPro's tab strip maximizes the window
                            // from its dblclk) makes every probe of an ordinary click unreadable.
                            let requested = (env["WINAMP_MODERN_RENDER_CLICK_EVENTS"] ?? "")
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                                .filter { !$0.isEmpty }
                            let allEvents = ["onleftbuttondown", "onleftbuttondblclk", "onleftbuttonup",
                                             "onleftclick", "onrightbuttondown", "onrightbuttonup",
                                             "onrightclick"]
                            for event in (requested.isEmpty ? allEvents
                                          : allEvents.filter { requested.contains($0) }) {
                                // The button events carry the click's x/y, exactly as the view sends
                                // them: a handler that pops two arguments off an empty stack fails
                                // with an underflow that belongs to the harness, not the skin.
                                // Parent-relative, exactly as the view sends them (see
                                // `WinampModernMainView.dispatch`): a knob script subtracts its own
                                // `getLeft()` from this, and a canvas point put Lobe's dial off the
                                // end of its map.
                                let parent = renderer.resolvedGeometry(of: target)?.parent ?? .zero
                                let local = CGPoint(x: point.x - parent.minX, y: point.y - parent.minY)
                                let arguments: [MakiValue] = ["onleftclick", "onrightclick"].contains(event) ? []
                                    : [.integer(Int32(local.x)), .integer(Int32(local.y))]
                                if event.hasPrefix("onright") {
                                    // No view here to show a menu, so record what the skin built.
                                    runtime.popupPresenter = { items, point in
                                        let where_ = point.map { " at \(Int($0.x)),\(Int($0.y))" } ?? ""
                                        print("CLICK menu\(where_): " + Self.describe(items))
                                        // A menu the user *dismisses* answers 0, and for a skin whose
                                        // command only takes effect on a later click that is the same
                                        // as never opening it. ClassicPro's multi-button is the case:
                                        // the right-click menu only records which command the **left**
                                        // click will run, so every one of its six choices was
                                        // unmeasurable without a pick.
                                        let picked = env["WINAMP_MODERN_RENDER_CLICK_PICK"]
                                            .flatMap { Int32($0) } ?? 0
                                        if picked != 0 { print("CLICK menu pick: \(picked)") }
                                        return picked
                                    }
                                }
                                let handled = (try? runtime.dispatch(object: target, event: event,
                                                                     arguments: arguments)) ?? -1
                                print("CLICK   \(event) -> \(handled)")
                            }
                        }
                        // A togglebutton's own state change is the view's job too, and a skin can put
                        // its whole drawer behind the `onToggle` that follows it. Mirrored here for
                        // the same reason the `cfgattrib` step below is.
                        if let target, runtime.toggleActivation(of: target) {
                            print("CLICK toggled \(target.xmlID ?? "-") "
                                  + "activated=\(target.attributes["activated"] ?? "0")")
                        }
                        // The object's **own** `action=`, decoded the way the view decodes it.
                        // Every line above reports what the *scripts* did with a click; a plain
                        // toolbar button has no script at all — its whole behaviour is this one
                        // attribute, performed by the view — so the probe reported seven zero counts
                        // and no action for a button that works. It also names the host-action family
                        // the action falls into, which is what makes "is this button answered?"
                        // (Phase 39's question, across 108 declarations) a one-run check.
                        if let target, let raw = target.attributes["action"], !raw.isEmpty {
                            let resolved = WasabiClickAction.split(action: raw,
                                                                   parameter: target.attributes["param"])
                            let family = WinampModernHostAction(action: resolved.action)
                            let routing: String
                            switch family {
                            case .none: routing = ""
                            case .inert(_, let reason)?: routing = " host=inert(\(reason))"
                            case .some(let action): routing = " host=\(action)"
                            }
                            print("CLICK markup action: \(resolved.action) "
                                  + "param=\(resolved.parameter ?? "-")" + routing)
                        }
                        // The other two action attributes: a command on the second click or the
                        // right button. The view performs these, so like the toggle above they are
                        // mirrored rather than dispatched — a titlebar mousetrap's `SWITCH;shade`
                        // and a song title's `TRACKINFO` are invisible in every other probe line.
                        for gesture in [WasabiClickGesture.double, .right] {
                            guard let target,
                                  let resolved = WasabiClickAction.resolve(target, gesture: gesture)
                            else { continue }
                            print("CLICK \(gesture.rawValue)action: \(resolved.action) "
                                  + "param=\(resolved.parameter ?? "-")")
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
                // The video box a skin declares, and the two things about it the window layer needs
                // (B20): the frame the picture is placed at, and whether the holder asked for
                // Winamp's command bar. A `video=declared:…` catalog entry whose container turns out
                // to hold no `<component>` would route and never fill, and this is where that shows.
                for holder in holders where holder.kind == .video {
                    let bar = WinampModernVideoHolder.showsCommandBar(
                        holderAttributes: holder.object.attributes)
                    print("VIDEO holder \(info.id)/\(layoutID): \(holder.object.xmlID ?? "-")"
                          + "\(holder.frame) cmdbar=\(bar ? 1 : 0)")
                }
                // …and the ones that are in the graph but **not on screen** (B23). An SUI skin keeps
                // its video component in a tab, so at load the holder is inside a hidden group and
                // every visibility-filtered probe answers "this skin declares no video box" — which
                // is exactly what routing believed about cPro-Bento while its Video tab sat empty and
                // the film opened a window of its own. No frame: an object that is not in the scene
                // has no resolved geometry to report, and inventing one would be a lie.
                for object in Self.hiddenComponentHolders(kind: .video, in: info.object)
                where !holders.contains(where: { $0.object === object }) {
                    print("VIDEO holder \(info.id)/\(layoutID): \(object.xmlID ?? "-") hidden"
                          + " cmdbar=\(WinampModernVideoHolder.showsCommandBar(holderAttributes: object.attributes) ? 1 : 0)")
                }
                // The visualization surfaces a skin declares (B20a): the AVS/vis `<component>`
                // holder, which is the one the host's own visualization engine fills, and every
                // `<vis>` box in this layout with the mode it is asking for. The two are different
                // things — a `<vis>` is the skin's own analyzer/scope and stays engine-drawn — and
                // telling them apart is the whole routing question, so both are printed.
                for holder in holders where holder.kind == .visualization {
                    // `name=` and `nomenu=` decide whether the host can offer this window in its own
                    // Windows menu, which for an AVS container is the only way a user reaches it —
                    // the skins bind no button to it (Phase 48).
                    print("VIS holder \(info.id)/\(layoutID): \(holder.object.xmlID ?? "-")"
                          + "\(holder.frame) name=\(info.object.attributes["name"] ?? "-")"
                          + " nomenu=\(info.object.attributes["nomenu"] ?? "-")")
                }
                // The playlist holder and the metrics NullPlayer draws its rows at. The rows are the
                // host's, not the skin's — a `<windowholder hold="guid:{45F3F7C1-…}">` is filled by
                // the player, so there is no `fontsize` on it to read and nothing in the rendered
                // dump shows the size headlessly (the harness sets no component host, so the panel
                // comes out empty). `text=` is the Text Size setting resolved against this window's
                // canvas, and `scale=` says whether it came from `auto` or from a user's choice —
                // which is the whole question behind "the playlist font is tiny in this skin".
                let textScaleLabel = renderer.textScale == .auto
                    ? "auto(\(WinampModernTextScale.resolvedPercent(canvasHeight: renderer.canvasSize.height))%)"
                    : "set(\(renderer.textScale.storedValue)%)"
                for holder in holders where holder.kind == .playlist {
                    print("PLAYLIST holder \(info.id)/\(layoutID): \(holder.object.xmlID ?? "-")"
                          + "\(holder.frame) text=\(renderer.playlistTextPixelHeight(in: holder.object))px"
                          + " row=\(renderer.playlistRowHeight(in: holder.object))px"
                          + " scale=\(textScaleLabel)")
                }
                // An SUI keeps its playlist in a closed tab, so the visible-scene pass above reports
                // nothing for the skins that most need measuring (every Big Bento variant). The
                // metrics come from markup, not from the scene, so a hidden holder answers them too.
                for object in Self.hiddenComponentHolders(kind: .playlist, in: info.object)
                where !holders.contains(where: { $0.object === object }) {
                    print("PLAYLIST holder \(info.id)/\(layoutID): \(object.xmlID ?? "-") hidden"
                          + " text=\(renderer.playlistTextPixelHeight(in: object))px"
                          + " row=\(renderer.playlistRowHeight(in: object))px"
                          + " scale=\(textScaleLabel)")
                }
                for node in renderer.sceneNodes()
                where node.object.typeName.caseInsensitiveCompare("vis") == .orderedSame {
                    let mode = WasabiVisualizationMode(attribute: node.object.attributes["mode"])
                    print("VIS box \(info.id)/\(layoutID): \(node.object.xmlID ?? "-")\(node.frame) "
                          + "mode=\(mode.attributeValue)(\(mode.displayName))")
                }
                // WINAMP_MODERN_RENDER_THEMES=1 — the colour-theme picture for this skin, which is
                // otherwise unmeasurable: a `.wal` is a compressed NSIS archive with no unpacked form,
                // so `strings … | grep -i colorthemes` answers 0 for four skins that ship a full
                // picker. It prints the catalog once, then every `<ColorThemes:List>` in the scene
                // with its resolved frame, and every object carrying a `colorthemes_*` action with
                // the target its `action_target` resolves to (Phase 32).
                if env["WINAMP_MODERN_RENDER_THEMES"] != nil {
                    if !printedThemeCatalog {
                        printedThemeCatalog = true
                        let names = renderer.colorThemeNames
                        print("THEMES catalog: count=\(names.count) "
                              + "active=\(loaded.themeCoordinator.catalog.activeTheme) "
                              + "default=\(names.first ?? "-")")
                        print("THEMES names: \(names.joined(separator: " | "))")
                    }
                    for entry in renderer.colorThemeLists() {
                        print("THEMES list \(info.id)/\(layoutID) #\(entry.object.xmlID ?? "-") "
                              + "frame=\(entry.frame) "
                              + "rows=\(renderer.colorThemeNames.count) "
                              + "visible=\(WasabiColorThemeListState.visibleRowCount(in: entry.frame)) "
                              + "selected=\(renderer.selectedColorTheme(in: entry.object) ?? "-")")
                    }
                    for node in renderer.sceneNodes() {
                        let action = (node.object.attributes["action"] ?? "").lowercased()
                        guard action.hasPrefix("colorthemes_") else { continue }
                        let target = renderer.actionTarget(of: node.object)
                        let list = renderer.colorThemeList(forAction: node.object)
                        print("THEMES action \(info.id)/\(layoutID) \(action) "
                              + "on=\(node.object.typeName)#\(node.object.xmlID ?? "-") "
                              + "text=\(node.object.attributes["text"] ?? "-") "
                              + "action_target=\(node.object.attributes["action_target"] ?? "-") "
                              + "resolves=\(target.map { "\($0.typeName)#\($0.xmlID ?? "-")" } ?? "nothing") "
                              + "list=\(list?.xmlID ?? "none") frame=\(node.frame)")
                    }
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

        // What the skin's scripts did to the queue. A `removeTrack`, `moveTo` or `clear` is invisible
        // in the dump — the drawn panel is one frame taken before the click that triggers it — so the
        // queue is printed again here and diffed by eye against the "before" line.
        if let playlistHost {
            print("PLAYLIST after: \(playlistHost.describe())")
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
        case "onshownotification":
            // What `WinampModernMainWindowController.showNotifier` dispatches on a track change, at
            // the same target and arity. It is the *only* entry into a notifier script's layout
            // routine — Big Bento's reads its four `Notifications` settings, hides the album line or
            // the transport group, and moves and resizes the text group from there — so without it
            // every notifier in the corpus measures as a window whose script does nothing (BB27).
            print("EVENT \(event) -> \((try? runtime.dispatchSystem(event: event)) ?? -1)")
        case "onvolumechanged":
            let handled = (try? runtime.dispatchSystem(
                event: event, arguments: [.integer(Int32((host.volume * 255).rounded()))])) ?? -1
            print("EVENT \(event) -> \(handled)")
        case "onenter", "onabort", "oneditupdate":
            // The `<edit>` control's own events, at every edit in the layout (arity 0). The box is
            // usually `visible="0"` until a script shows it — Big Bento's playlist search is — so the
            // hidden ones are driven too, or the only text field in the corpus is undrivable. Text
            // typed into it comes from `WINAMP_MODERN_RENDER_TYPE`.
            var edits: [WasabiObject] = []
            var stack = [renderer.layout]
            while let node = stack.popLast() {
                stack.append(contentsOf: node.children)
                if node.typeName.lowercased().components(separatedBy: ":").last == "edit" {
                    edits.append(node)
                }
            }
            if let typed = ProcessInfo.processInfo.environment["WINAMP_MODERN_RENDER_TYPE"] {
                for edit in edits { _ = edit.setAttribute("text", value: typed) }
            }
            for edit in edits {
                var handled = -1
                do {
                    handled = try runtime.dispatch(object: edit, event: event)
                } catch let failure as WalFailure {
                    print("EVENT \(event) !FAILED: "
                          + failure.diagnostics.map(\.message).joined(separator: "; "))
                } catch {
                    print("EVENT \(event) !FAILED: \(error)")
                }
                var chain: [String] = []
                var node = edit.parent
                while let current = node, chain.count < 6 {
                    chain.append("\(current.typeName)#\(current.xmlID ?? "-")")
                    node = current.parent
                }
                print("EVENT \(event) -> \(edit.xmlID ?? "-") handlers=\(handled) "
                      + "bound=\(runtime.hasBinding(for: edit, event: event)) "
                      + "text=\(edit.attributes["text"] ?? "") in \(chain.joined(separator: "<"))")
            }
            if edits.isEmpty { print("EVENT \(event): this layout declares no <edit>") }
        case "onmousewheelup", "onmousewheeldown":
            // Addressed to the **layout**, which is where every corpus binding for these lands, and
            // with two arguments (both `op3` stores at the handler's entry, in two independent skins).
            //
            // Two things this deliberately cannot show, both of which live in the window layer:
            // the skins gate the turn on `isMouseOverRect()` and the harness owns no window, so that
            // answers `false` for every page; and this calls `dispatch` itself rather than going
            // through `WinampModernMainView.scrollWheel`, so it says nothing about whether the wheel
            // is *wired* to the skin at all. A `handlers=` count here means "the bindings exist, the
            // arity unwinds, and nothing aborts" — not "something scrolled". Reading it as a working
            // scrollbar is exactly the blind-instrument mistake this file warns about elsewhere; that
            // half only measures in the running app.
            let handled = (try? runtime.dispatch(object: renderer.layout, event: event,
                                                 arguments: [.integer(1), .integer(3)])) ?? -1
            print("EVENT \(event) -> \(handled) handlers on layout#\(renderer.layout.xmlID ?? "-") "
                  + "(isMouseOverRect answers false headlessly — no window)")
        default:
            print("EVENT \(event): no harness target/arity — add one to `drive(event:…)`")
        }
    }

    /// A script-built menu as one line: `Title > [child, …]`, separators as `--`.
    /// Every component holder of `kind` anywhere under a container's retained subtree, visible or
    /// not. The companion to `componentHolders()`, which only ever answers for the current scene.
    private static func hiddenComponentHolders(kind: WinampModernComponentKind,
                                               in container: WasabiObject) -> [WasabiObject] {
        var found: [WasabiObject] = []
        func visit(_ object: WasabiObject) {
            if WinampModernComponentRegistry.isHolderElement(object.typeName),
               WasabiSceneRenderer.componentKind(of: object) == kind {
                found.append(object)
            }
            for child in object.children { visit(child) }
        }
        visit(container)
        return found
    }

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

    /// A synthetic playlist/equalizer host for the harness, so the component seam answers something.
    /// Writes land in this array rather than in an `AudioEngine`, which is the point: a probe run can
    /// drive a skin's *Remove selected* without a player.
    private final class RenderComponentHost: WinampModernComponentHost {
        private struct Row { var title: String; var artist: String; var album: String; var path: String }
        private var rows: [Row]
        private var current: Int
        private var selection: Set<Int> = []
        private var anchor = -1
        private var bands = Array(repeating: Float(0), count: 10)
        private var preamp: Float = 0

        init(count: Int, current: Int) {
            rows = (0..<count).map {
                Row(title: "Track \($0 + 1)", artist: "Artist \($0 + 1)",
                    album: "Album \($0 % 3 + 1)", path: "/tmp/harness/track\($0 + 1).mp3")
            }
            self.current = rows.indices.contains(current) ? current : (rows.isEmpty ? -1 : 0)
        }

        func describe() -> String {
            "current=\(current) rows=[" + rows.map(\.title).joined(separator: ", ") + "]"
        }

        func playlistSnapshot() -> WinampModernPlaylistSnapshot {
            WinampModernPlaylistSnapshot(
                rows: rows.enumerated().map { index, row in
                    WinampModernPlaylistRow(title: row.title, secondary: row.artist,
                                            duration: TimeInterval(120 + index),
                                            isCurrent: index == current,
                                            artist: row.artist, album: row.album, filePath: row.path)
                },
                currentIndex: current, selectedIndex: anchor, selectedRows: selection)
        }

        func playlistSelect(row: Int) {
            guard rows.indices.contains(row) else { return }
            anchor = row
            selection = [row]
        }

        func playlistSetSelection(_ rows: Set<Int>) {
            selection = rows.filter { self.rows.indices.contains($0) }
            anchor = selection.min() ?? -1
        }

        func playlistPlay(row: Int) {
            guard rows.indices.contains(row) else { return }
            current = row
        }

        func playlistRemove(row: Int) {
            guard rows.indices.contains(row) else { return }
            rows.remove(at: row)
            if current == row { current = rows.isEmpty ? -1 : min(row, rows.count - 1) }
            else if current > row { current -= 1 }
        }

        func playlistMove(row: Int, to destination: Int) {
            guard rows.indices.contains(row), rows.indices.contains(destination), row != destination else { return }
            let moved = rows.remove(at: row)
            rows.insert(moved, at: destination)
            if current == row { current = destination }
            else if row < current && destination >= current { current -= 1 }
            else if row > current && destination <= current { current += 1 }
        }

        func playlistClear() {
            rows.removeAll()
            current = -1
            anchor = -1
            selection = []
        }

        func equalizerSnapshot() -> WinampModernEQSnapshot {
            WinampModernEQSnapshot(bandGainsDB: bands, preampDB: preamp, enabled: true,
                                   auto: false, presetNames: [])
        }

        func equalizerSetBandGainDB(_ band: Int, gainDB: Float) {
            guard bands.indices.contains(band) else { return }
            bands[band] = gainDB
        }

        func equalizerSetPreampDB(_ gainDB: Float) { preamp = gainDB }
        func equalizerSetEnabled(_ enabled: Bool) {}
        func equalizerSetAuto(_ enabled: Bool) {}
        func equalizerApplyPreset(named name: String) {}
        func toggleClassicWindow(for kind: WinampModernComponentKind) {}
    }

    private final class RenderHost: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 73
        var duration: TimeInterval = 245
        var volume: Double = 0.7
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "A Very Long Song Title That Must Scroll Across The Display"
        /// The protocol's defaults are both `""`, which is a *playing nothing* state no window in the
        /// app is ever in — and a notifier is three stacked readouts, so with two of them empty its
        /// whole vertical arrangement measures as one line and any collision between them is
        /// invisible (BB27). Deliberately long enough to need more room than the toast declares.
        var trackArtist = "Some Artist Whose Name Runs On"
        var trackAlbum = "An Album Title That Also Runs On"
        var trackInfo = "NullPlayer QA"
        var trackDisplayTitle = "Some Artist - A Very Long Song Title That Must Scroll Across The Display"
        var bitrateKbps = 320
        var sampleRateHz = 44_100
        var channelCount = 2
        /// A static ramp by default. Scaled by `WINAMP_MODERN_RENDER_VU` when that is set, because
        /// `getVisBand` — not `getLeftVUMeter` — is what the skin-drawn meters that read the
        /// *spectrum* use (Defix's speaker cones), and a constant spectrum pins them to one frame
        /// however well they work. Without this the cones measure as dead at every level.
        var spectrumLevels: [Float] {
            get {
                let spec = ProcessInfo.processInfo.environment["WINAMP_MODERN_RENDER_VU"]
                guard let spec, !spec.isEmpty else { return storedSpectrumLevels }
                let scale = Float(vuLevels.left)
                return storedSpectrumLevels.map { min(1, $0 * scale + scale * 0.5) }
            }
            set { storedSpectrumLevels = newValue }
        }
        private var storedSpectrumLevels: [Float] = (0..<64).map { Float(($0 % 16)) / 16 }
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
