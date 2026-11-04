import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

/// The AIMP probe harness, as `WMPRenderDumpTests` is `.wmz`'s: opt-in through `AIMP_SKIN`, skipped
/// otherwise, one machine-readable fact per line. Every flag is documented in
/// `skills/aimp-skin-guide/reference/harness.md` and nowhere else.
///
///     AIMP_SKIN=<file or dir> AIMP_RENDER_OUT=/tmp/aimp AIMP_RENDER_STATE=playing \
///       swift test --filter AIMPRenderDumpTests/testSweepsSkinOrCorpus
final class AIMPRenderDumpTests: XCTestCase {
    @MainActor func testSweepsSkinOrCorpus() throws {
        guard let path = ProcessInfo.processInfo.environment["AIMP_SKIN"], !path.isEmpty else {
            throw XCTSkip("Set AIMP_SKIN to an AIMP skin or a directory of them.")
        }
        AIMPSkinProbe.run(path)
    }
}

extension AIMPSkinPlayerSnapshot {
    /// The player the probe draws, and the unit tests run scripts, against: a sample track, the
    /// volume at 0.7, and dark, as the skins' previews show them. `AIMP_RENDER_STATE=playing` plays it.
    static var probe: AIMPSkinPlayerSnapshot {
        var player = AIMPSkinPlayerSnapshot()
        (player.title, player.artist, player.album) = ("Sample Track Title", "Sample Artist", "Sample Album")
        player.volume = 0.7
        player.nightMode = true
        return player
    }
}

/// The probe itself: a census block per skin, renders and the state-aware flags.
enum AIMPSkinProbe {
    static let extensions: Set<String> = ["acs5", "acs4", "acs3", "acs", "acs4proj"]

    @MainActor private static func live(_ skin: AIMPSkin, canvas: CGSize, player start: AIMPSkinPlayerSnapshot) {
        let view = AIMPSkinMainView(frame: CGRect(origin: .zero, size: canvas))
        view.scheduler.timing = .probe(clock: nil)
        var player = start
        player.playState = .playing
        let runtime = AIMPSkinRuntime(skin: skin, player: player)
        var companions: [AIMPSkinMainView] = []
        var depth = 0, deepest = 0, actions = 0, frameActions = 0, floods = 0, looped = false
        var seen: [String: Int] = [:]
        func publish() {
            depth += 1
            deepest = max(deepest, depth)
            defer { depth -= 1 }
            // A real loop nests without end; well past any honest chain, stop feeding it.
            if depth > 25 { looped = true; return }
            runtime.update(player: player)
        }
        runtime.onAction = { action in
            actions += 1
            frameActions += 1
            seen[action.description, default: 0] += 1
            switch action {
            case .action(.playerPlay):
                if player.playState == .playing { player.position = 0; player.elapsedSeconds = 0 } else {
                    if player.playState == .stopped { player.tracksStarted += 1 }
                    player.playState = .playing
                }
            case .action(.playerStop): player.playState = .stopped; player.position = 0; player.elapsedSeconds = 0; player.tracksFinished += 1
            case .action(.playerPause), .action(.playerPlayPause): player.playState = player.playState == .playing ? .paused : .playing
            case .action(.playerNextTrack), .action(.playerPrevTrack):
                player.title += "'"; player.position = 0; player.elapsedSeconds = 0; player.tracksFinished += 1; player.tracksStarted += 1
            case .seek(let seconds):
                player.elapsedSeconds = Int(seconds)
                player.position = player.durationSeconds > 0 ? min(1, seconds / Double(player.durationSeconds)) : 0
            case .setValue(let provider, let value): if provider == .volume { player.volume = value }
            case .position: break
            default: return
            }
            publish()
        }
        var clock = 1000.0
        view.scheduler.timing = .probe(clock: clock)
        view.runtime = runtime
        // The skin's other windows, on the deck's runtime as the window controller wires them
        // (GX-77 Grey's intro-scan switch is on its playlist window).
        for companion in skin.companions where companion.opensWindow {
            let other = AIMPSkinMainView(frame: CGRect(origin: .zero, size: canvas))
            other.scheduler.timing = .probe(clock: nil)
            other.formName = companion.name
            other.runtime = runtime
            companions.append(other)
        }
        runtime.start()
        var times: [Double] = []
        // Six seconds: play 2 s, stop 1 s, play 1 s, next track 1 s, pause 1 s; each start and end
        // counted as the host counts them, which skins' track-start scripts watch.
        let script: [(Int, (inout AIMPSkinPlayerSnapshot) -> Void)] = [
            (60, { $0.tracksStarted += 1 }),
            (30, { $0.playState = .stopped; $0.position = 0; $0.elapsedSeconds = 0; $0.tracksFinished += 1 }),
            (30, { $0.playState = .playing; $0.tracksStarted += 1 }),
            (30, { $0.title += " (next)"; $0.position = 0; $0.elapsedSeconds = 0; $0.tracksFinished += 1; $0.tracksStarted += 1 }),
            (30, { $0.playState = .paused }),
        ]
        var frame = 0
        func step() {
            clock += 1.0 / 30
            frame += 1
            view.scheduler.timing = .probe(clock: clock)
            runtime.update(player: player)
            frameActions = 0
            runtime.tick()
            if frameActions > 10 { floods += 1 }
        }
        // Every control a click can reach without a dialog, menu, text box or quitting, pressed
        // twice (on, then off), a few frames apart: a skin's mode switches arm the scripts that
        // only then run (GX-77 Grey's intro scan seeks on each track start).
        let unsafe: Set<String> = ["acMainExit", "acMainOpenFiles", "acMainOpenFolder", "acOptions", "acOptionSkins", "acMainAbout",
                                   "acMLAddFiles", "acMainMinimize"]
        let clickable = ([view] + companions).flatMap { owner in (owner.drawnFrame?.targets ?? []).map { (owner, $0) } }.filter { _, target in
            switch target.kind {
            case .action(let action): return !unsafe.contains(action.name)
            case .page, .handler, .counter, .toggle, .setValue: return true
            default: return false
            }
        }
        var clicked = 0
        func pressAll() {
            for (owner, target) in clickable where !looped {
                clicked += 1
                owner.activate(target, at: .zero)
                // The tick a click schedules runs on the next turn of the run loop, at the same
                // moment, as in the app.
                runtime.tick()
                for _ in 0..<3 { step() }
            }
        }
        // On, then the scripted run with its track starts and stops, then off.
        pressAll()
        for (frames, change) in script {
            change(&player)
            publish()
            for _ in 0..<frames {
                clock += 1.0 / 30
                frame += 1
                if player.playState == .playing {
                    player.elapsedSeconds = Int(Double(frame) / 30) + 10
                    player.position = player.durationSeconds > 0 ? Double(player.elapsedSeconds) / Double(player.durationSeconds) : 0
                }
                let pulse = 0.5 + 0.4 * sin(Double(frame) / 4)
                runtime.levels = player.playState == .playing ? (pulse, 1 - pulse) : (0, 0)
                runtime.spectrum = player.playState == .playing ? (0..<64).map { 0.2 + 0.6 * pulse * (1 - Double($0) / 80) } : []
                view.scheduler.timing = .probe(clock: clock)
                runtime.update(player: player)
                frameActions = 0
                let began = CACurrentMediaTime()
                runtime.tick()
                times.append((CACurrentMediaTime() - began) * 1000)
                if frameActions > 10 { floods += 1 }
            }
        }
        pressAll()
        let sorted = times.sorted()
        let average = times.reduce(0, +) / Double(max(1, times.count))
        let top = seen.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }
        emit("  LIVE frames=\(times.count) avg=\(String(format: "%.2f", average))ms p95=\(String(format: "%.2f", sorted[Int(Double(sorted.count) * 0.95)]))ms "
             + "max=\(String(format: "%.2f", sorted.last ?? 0))ms actions=\(actions) deepest=\(deepest) floods=\(floods)"
             + (looped ? " LOOP" : "") + " clicked=\(clicked) top=\(top)")
    }

    /// Runs and exits when the probe is requested; returns otherwise.
    @MainActor static func run(_ path: String) {
        let env = ProcessInfo.processInfo.environment
        let out = env["AIMP_RENDER_OUT"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let size = env["AIMP_RENDER_SIZE"].flatMap { value -> CGSize? in
            let parts = value.lowercased().split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        }
        let item = env["AIMP_RENDER_ITEM"].flatMap { $0.isEmpty ? nil : $0 }
        var state = AIMPSkinState()
        for pair in (env["AIMP_RENDER_PAGES"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let page = Int(parts[1]) { state.script.activePages[String(parts[0])] = page }
        }
        for pair in (env["AIMP_RENDER_COUNTERS"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let value = Int(parts[1]) { state.script.counters[String(parts[0])] = value }
        }
        var host = AIMPSkinHostState(player: .probe)
        if env["AIMP_RENDER_STATE"] == "playing" {
            host.player.playState = .playing
            // A smile on the EQ, and a test card for cover art: four coloured quarters.
            host.player.eqGains = (0..<10).map { 0.5 + 0.3 * pow(Double($0 - 5) / 5, 2) - 0.1 }
            host.player.preamp = 0.55
            if let card = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                for (i, rgb) in [(0.9, 0.2, 0.2), (0.2, 0.7, 0.3), (0.2, 0.4, 0.9), (0.95, 0.8, 0.2)].enumerated() {
                    card.setFillColor(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
                    card.fill(CGRect(x: (i % 2) * 32, y: (i / 2) * 32, width: 32, height: 32))
                }
                host.player.coverArt = card.makeImage()
            }
            host.player.elapsedSeconds = 108
            host.player.position = 0.3
            host.player.playlist = .init(rows: (1...24).map { .init(title: "Sample Artist - Sample Track \($0)", seconds: 150 + $0 * 7) },
                                  generation: 1)
            host.player.playlistIndex = 2
            host.player.fileType = "MP3"
            (host.player.bitrate, host.player.sampleRate, host.player.channels, host.player.year, host.player.fileSize, host.player.rating) = (320, 44_100, 2, 1985, 8_400_000, 4)
            host.player.durationSeconds = 360
            host.feedback.levelL = 0.6
            host.feedback.levelR = 0.45
            // A small library for the skin's library window: five artists, two albums each.
            // (`AIMP_RENDER_LIBRARY=empty` for a library with nothing in it.)
            let emptyLibrary = ProcessInfo.processInfo.environment["AIMP_RENDER_LIBRARY"] == "empty"
            host.player.library = AIMPSkinLibrary(tracks: emptyLibrary ? [] : (0..<40).map { i in
                LibraryTrack(url: URL(fileURLWithPath: "/Music/Album \(i / 4 + 1)/\(i).mp3"), title: "Sample Song \(i % 4 + 1)",
                             artist: "Sample Artist \(i / 8 + 1)", album: "Sample Album \(i / 4 + 1)", albumArtist: "",
                             genre: ["Rock", "Jazz"][i % 2], year: 1980 + i / 4, trackNumber: i % 4 + 1, discNumber: 1,
                             duration: TimeInterval(180 + i * 3), fileSize: 7_000_000)
            })
            host.feedback.spectrum = (0..<64).map { (band: Int) -> Double in
                let x = Double(band)
                let wave: Double = abs(sin(x / 5))
                return 0.15 + 0.7 * wave * (1 - x / 80)
            }
        }
        let skins = files(at: path)
        emit("HARNESS \(skins.count) skin(s) from \(path)")
        if let out { try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        var rendered = 0
        for file in skins {
            let stem = file.deletingPathExtension().lastPathComponent
            emit("SKIN \(file.lastPathComponent)")
            let started = Date()
            let skin: AIMPSkin
            do {
                skin = try AIMPSkinLoader.load(contentsOf: file)
            } catch {
                emit("  FATAL \(error)")
                continue
            }
            emit("  FORMAT \(skin.archive.format.rawValue) NAME \(skin.name) AUTHOR \(skin.archive.author)")
            let drawn = skin.images.values.filter(\.hasPixels).count
            emit("  ENTRIES \(skin.archive.entries.count) IMAGES \(skin.images.count) WITH_PIXELS \(drawn) RESOURCES \(skin.resources.count) "
                 + "LOAD_MS \(Int(Date().timeIntervalSince(started) * 1_000))")
            let nodes = skin.mainForm.descendants()
            emit("  FORM items=\(nodes.filter { $0.tag == "item" }.count) controls=\(nodes.filter { $0.tag == "control" }.count)")
            for finding in skin.findings { emit("  WARN \(finding)") }
            if env["AIMP_RENDER_SCRIPTS"] == "1" {
                let runs = AIMPCorpusLoadTests.dryRun(skin)
                emit("  SCRIPTS \(runs.filter(\.ran).count) of \(runs.count)")
                for run in runs where !run.ran { emit("  SCRIPT_FAIL \(run.name) \(run.why)") }
            }
            guard let out else { continue }
            // What the window opens at: its natural size, or the `InitialSize` of one the user sizes.
            let natural = AIMPSkinRenderer.naturalSize(skin, item: item)
            guard let canvas = size ?? natural.map({ natural in
                item == nil ? AIMPSkinRenderer.initialSize(skin, natural: natural) ?? natural : natural
            }) else {
                emit("  RENDER NO_SIZE")
                continue
            }
            // Each step below on a script engine of its own, over `state` as `host` shows the player.
            func scripts(_ host: AIMPSkinHostState, _ state: AIMPSkinState,
                         _ body: (AIMPSkinScript.Engine) -> Void) -> AIMPSkinScript.Engine {
                let engine = AIMPSkinScript.Engine(skin: skin, host: host, state: state)
                body(engine)
                return engine
            }
            // The scripts the skin runs as it is shown (`AIMPSkinScript.Engine.loaded`), then one timer
            // tick, as the window's first frame runs, then the scripts it moved.
            let shown = scripts(host, state) { $0.loaded() }.state
            var ticked = scripts(host, shown) { $0.fireTimers() }.state
            // `AIMP_RENDER_VISUALIZE=n`: n frames of a pulsing spectrum, a thirtieth of a second apart,
            // each run as the window runs one: timers, visualization, then the scripts that moved.
            var visualHost = host
            for frame in 0..<(Int(env["AIMP_RENDER_VISUALIZE"] ?? "") ?? 0) {
                visualHost.feedback.clock = host.feedback.clock + Double(frame + 1) / 30
                let beat = frame % 8 == 0 ? 1.0 : 0.2
                visualHost.feedback.spectrum = (0..<75).map { beat * (1 - Double($0) / 100) }
                ticked = scripts(visualHost, ticked) { $0.fireTimers() }.state
                ticked = scripts(visualHost, ticked) { $0.visualize() }.state
                ticked = scripts(visualHost, ticked) { $0.settle() }.state
            }
            if env["AIMP_RENDER_VISUALIZE"] != nil {
                emit("  VISUAL frames=\(ticked.animation.animatorFrames.count) lamps=\(ticked.animation.opacities.count) "
                     + ticked.animation.opacities.sorted { $0.key < $1.key }.prefix(4).map { "\($0.key)=\(Int($0.value))" }.joined(separator: " "))
            }
            var settled = scripts(host, ticked) { $0.settle() }.state
            var frame = AIMPSkinRenderer.frame(skin, size: canvas, item: item, host: host, state: settled)
            // What `AutoHide` hid, as the window's next frame reads it.
            if let hidden = frame?.autoHidden, hidden != settled.script.autoHidden {
                settled.script.autoHidden = hidden
                settled = scripts(host, settled) { $0.settle() }.state
                frame = AIMPSkinRenderer.frame(skin, size: canvas, item: item, host: host, state: settled)
            }
            // `AIMP_RENDER_HOVER=x,y`: the pointer comes to rest there (enter, move), then redraw.
            let hover = (env["AIMP_RENDER_HOVER"] ?? "").split(separator: ",").compactMap { Double($0) }
            if hover.count == 2, let first = frame {
                let point = CGPoint(x: hover[0], y: hover[1])
                var hovered = settled
                for handlers in first.mouseHandlers where handlers.rect.contains(point) {
                    for script in [handlers.enter, handlers.move].compactMap({ $0 }) {
                        hovered = scripts(host, hovered) {
                            $0.handle(script, sender: handlers.name,
                                      arguments: ["X": point.x - handlers.rect.minX, "Y": point.y - handlers.rect.minY])
                        }.state
                    }
                }
                var pointed = host
                pointed.feedback.pointer = .at(point)
                pointed.feedback.hoverRects = first.namedRects
                // The control under it lights as the window lights it.
                let interaction = AIMPSkinInteraction(hovered: first.target(at: point)?.control)
                frame = AIMPSkinRenderer.frame(skin, size: canvas, item: item, host: pointed, state: hovered,
                                               interaction: interaction)
            }
            if env["AIMP_RENDER_TARGETS"] == "1" {
                for target in frame?.targets ?? [] {
                    emit("  TARGET \(target.name) \(target.kind) \(Int(target.rect.minX)),\(Int(target.rect.minY)) "
                         + "\(Int(target.rect.width))x\(Int(target.rect.height))"
                         + (target.rightClick.map { " right=\($0)" } ?? ""))
                }
            }
            if let click = env["AIMP_RENDER_CLICK"], let target = frame?.targets.last(where: { $0.name == click }) {
                if case .handler(let handler) = target.kind {
                    let result = scripts(host, settled) { $0.handle(handler, sender: click) }
                    emit("  CLICK \(click) handler=\(handler) actions=\(result.actions.map(\.description))")
                } else if case .hold(let down, let up) = target.kind {
                    // Pressed at a quarter of the way across, held 0.2 s (timers fire), released.
                    let pressed = scripts(host, settled) {
                        $0.handle(down, sender: click, arguments: ["X": Double(target.rect.width) / 4, "Y": Double(target.rect.height) / 2])
                    }
                    var later = host
                    later.feedback.clock += 0.2
                    let held = scripts(later, pressed.state) { $0.fireTimers() }
                    let released = up.map { up in scripts(later, held.state) { $0.handle(up, sender: click) } }
                    emit("  CLICK \(click) down=\(pressed.actions.map(\.description)) held=\(held.actions.map(\.description)) up=\((released?.actions ?? []).map(\.description))")
                } else if case .counter(let name, let step) = target.kind {
                    let current = AIMPSkinDataflow(skin: skin, host: host, state: settled).value(name, "Position")
                    let next = step.next(from: current) ?? current
                    let result = scripts(host, settled) { $0.setCounter(name, to: Int(next)) }
                    let downstream = scripts(host, result.state) { $0.settle() }.actions
                    emit("  CLICK \(click) counter=\(name) \(Int(current))->\(Int(next)) actions=\((result.actions + downstream).map(\.description))")
                } else {
                    emit("  CLICK \(click) \(target.kind)")
                }
            }
            // `AIMP_RENDER_LIVE=1` runs a real main view for six seconds of frames against a player
            // that answers at once, as AudioEngine does (an action changes the host, which redraws
            // inside the action): play, stop, play, next track, pause. It prints the frame times and
            // flags a frame whose actions nest or flood, the live-only loops the renders cannot show.
            // The probe runs on the main thread, as the app's windows do.
            if env["AIMP_RENDER_LIVE"] == "1" { live(skin, canvas: canvas, player: host.player) }
            // `AIMP_RENDER_WHEEL=<target>:<steps>;…` turns the wheel over each target (an empty name:
            // the form's bare face) through a fresh real main view, and prints what it asked of the player.
            for wheel in (env["AIMP_RENDER_WHEEL"] ?? "").split(separator: ";") {
                guard let colon = wheel.lastIndex(of: ":"), let steps = Int(wheel[wheel.index(after: colon)...]) else { continue }
                let name = String(wheel[..<colon])
                let view = AIMPSkinMainView(frame: CGRect(origin: .zero, size: canvas))
                view.scheduler.timing = .probe(clock: nil)
                var asked: [String] = []
                let runtime = AIMPSkinRuntime(skin: skin, player: host.player)
                runtime.onAction = { asked.append($0.description) }
                view.runtime = runtime
                runtime.start()
                let target = name.isEmpty ? nil : view.drawnFrame?.targets.last { $0.name == name }
                let before = view.skinState
                view.wheel(over: target, steps: steps)
                let counters = view.skinState.script.counters.filter { before.script.counters[$0.key] != $0.value }
                    .map { "\($0.key) \(before.script.counters[$0.key].map { String(Int($0)) } ?? "?")->\(Int($0.value))" }
                let pages = view.skinState.script.activePages.filter { before.script.activePages[$0.key] != $0.value }.map { "\($0.key)->\($0.value)" }
                emit("  WHEEL \(name.isEmpty ? "-" : name) \(steps): \(target.map { "\($0.kind)" } ?? "face") asked=\(asked) "
                     + "counters=\(counters.sorted()) pages=\(pages.sorted())")
            }
            for point in (env["AIMP_RENDER_HIT"] ?? "").split(separator: ";") {
                let xy = point.split(separator: ",").compactMap { Double($0) }
                guard xy.count == 2 else { continue }
                emit("  HIT \(Int(xy[0])),\(Int(xy[1])) \(frame?.target(at: CGPoint(x: xy[0], y: xy[1]))?.name ?? "-")")
            }
            for (site, docked) in skin.index.sites.sorted(by: { $0.key < $1.key }) {
                emit("  DOCKED \(docked.form) in \(site)" + (docked.initiallyDocked ? "" : " (starts undocked)"))
            }
            // Each companion window, beside the main form: `<skin>-<ext>-<form>.png`.
            for companion in skin.companions where companion.opensWindow {
                let size = AIMPSkinRenderer.naturalSize(skin, form: companion.name)
                emit("  COMPANION \(companion.name) \"\(companion.title)\" visible=\(companion.initiallyVisible) "
                     + (size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "NO_SIZE"))
                guard let size, let companionFrame = AIMPSkinRenderer.frame(skin, size: size, form: companion.name, host: host,
                                                                            state: settled) else { continue }
                let image = companionFrame.image
                // A click on a companion's handler key: what its script did.
                if let click = env["AIMP_RENDER_CLICK"], let target = companionFrame.targets.last(where: { $0.name == click }),
                   case .handler(let handler) = target.kind {
                    let result = scripts(host, settled) { $0.handle(handler, sender: click) }
                    let after = scripts(host, result.state) { $0.settle() }
                    emit("    CLICK \(click) handler=\(handler) actions=\((result.actions + after.actions).map(\.description)) "
                         + "counters=\(after.state.script.counters) docked=\(after.state.script.docked) visible=\(after.state.script.visible)")
                }
                if env["AIMP_RENDER_TARGETS"] == "1" {
                    for target in companionFrame.targets {
                        emit("    TARGET \(target.name) \(target.kind) \(Int(target.rect.minX)),\(Int(target.rect.minY)) "
                             + "\(Int(target.rect.width))x\(Int(target.rect.height))"
                         + (target.rightClick.map { " right=\($0)" } ?? ""))
                    }
                }
                let url = out.appendingPathComponent("\(stem)-\(file.pathExtension.lowercased())-\(companion.name).png")
                if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    _ = CGImageDestinationFinalize(destination)
                }
            }
            guard let image = frame?.image else {
                emit("  RENDER EMPTY")
                continue
            }
            let url = out.appendingPathComponent("\(stem)-\(file.pathExtension.lowercased()).png")
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                if CGImageDestinationFinalize(destination) {
                    rendered += 1
                    emit("  RENDER \(image.width)x\(image.height) \(url.path)")
                }
            }
        }
        if out != nil { emit("RENDERED \(rendered) of \(skins.count)") }
    }

    static func files(at path: String) -> [URL] {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return names.filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted().map { url.appendingPathComponent($0) }
    }

    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
