import XCTest
import AppKit
@testable import NullPlayer

/// The S3 motion sweep (`corpus-runner-plan.md` §3 S3, §7 step 4): does anything a skin declares as
/// moving actually move, at rest? Every window container's opening layout is drawn on a four-rung
/// ladder, t = 0, 0.25, 1, 4 s, and each rung is a *pair*: the run loop is pumped until t (so a script
/// `Timer` gets its ticks) and the render clock is pinned to the same instant (so a play head, which
/// is a pure function of the clock, agrees with it).
///
///     WINAMP_MODERN_MOTION_SWEEP=<dir[:dir…]> \
///     WINAMP_MODERN_MOTION_SWEEP_OUT=<file.tsv> \
///       swift test --filter WinampModernMotionSweepTests
///
/// `scripts/wal_motion_sweep.sh` shards this and writes `motion.tsv`. One row per (skin, container,
/// layout), written straight to the file: a corpus run on the shared stdout loses lines (B166).
final class WinampModernMotionSweepTests: XCTestCase {

    static let rungs: [TimeInterval] = [0, 0.25, 1, 4]
    /// `Timer`, canonical (`docs/winamp-modern/maki-classes.tsv`).
    static let timerClass = "5d0c5bb64b1f7de1168d0fa741199459"

    func testSweepsMotionLadder() throws {
        let env = ProcessInfo.processInfo.environment
        guard let list = env["WINAMP_MODERN_MOTION_SWEEP"], let out = env["WINAMP_MODERN_MOTION_SWEEP_OUT"] else {
            throw XCTSkip("Set WINAMP_MODERN_MOTION_SWEEP and WINAMP_MODERN_MOTION_SWEEP_OUT.")
        }
        let wals = WinampModernCorpusPaths.archives(in: list)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var rows: [String] = []
        for wal in wals {
            do {
                rows += try Self.sweep(wal).map { "\(wal.lastPathComponent)\t\($0)" }
            } catch {
                // A skin that will not load is still a row, so nothing is skipped silently.
                rows.append("\(wal.lastPathComponent)\t-\t-\t-\t-\tfailed\t-\t-\t-\t-\t-\t-\t-")
            }
        }
        try (rows.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }

    /// One snapshot of a layout at one rung: its pixels, every scene node's drawn state, and every
    /// animated layer's play head.
    private struct Rung {
        let pixels: Data
        let nodes: [WasabiObjectID: String]
        let heads: [WasabiObjectID: (frame: Int, isPlaying: Bool, count: Int)]
    }

    /// Rows without the skin column: `container, layout, open, frames, verdict, animatedlayers,
    /// autoplay, timer, suspect, moved, anim, still`.
    private static func sweep(_ wal: URL) throws -> [String] {
        let loaded = try WinampModernSkinLoader(engineStore: .shared).load(from: wal)
        defer { loaded.teardown() }
        let host = WinampModernStubHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        defer { runtime.teardown() }

        var clock: TimeInterval = 0
        let containers = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        var renderers: [(info: WinampModernContainerInfo, renderer: WasabiSceneRenderer)] = []
        for info in containers {
            guard let renderer = try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                          containerID: info.id, clock: { clock }) else { continue }
            renderer.layerFXProvider = { [weak runtime] in runtime?.layerFXMesh(for: $0) }
            renderer.configStateProvider = { [weak runtime] in runtime?.configValue(of: $0) ?? false }
            renderer.configValueProvider = { [weak runtime] in runtime?.configInteger(of: $0) }
            renderers.append((info, renderer))
        }
        defer { renderers.forEach { $0.renderer.teardown() } }
        let all = renderers.map(\.renderer)
        runtime.hooks.resolvedGeometryRequested = { object in
            all.lazy.compactMap { $0.resolvedGeometry(of: object) }.first
        }

        try runtime.start()
        // As the app does right after `start()` (`scriptDidStart`); see the render dump's SEED.
        for renderer in all { runtime.dispatchResize(targets: renderer.resizeTargets(), previous: nil) }

        let timer = runtime.programs.contains { program in
            program.methods.contains { method in
                method.name.lowercased() == "start"
                    && program.classes.indices.contains(method.classIndex)
                    && MakiClassGUID.canonical(program.classes[method.classIndex]) == timerClass
            }
        }
        let layouts = renderers.map { ($0.renderer.activeLayoutID, Self.animatedLayers(in: $0.renderer.activeLayoutID,
                                                                                      of: $0.info.object)) }

        let base = WasabiAnimation.now()
        var ladders = Array(repeating: [Rung](), count: renderers.count)
        for t in rungs {
            let until = Date().addingTimeInterval(base + t - WasabiAnimation.now())
            if until > Date() { RunLoop.current.run(until: until) }
            clock = base + t
            for (index, entry) in renderers.enumerated() {
                ladders[index].append(rung(entry.renderer, animated: layouts[index].1, runtime: runtime, clock: clock))
            }
        }

        return renderers.enumerated().map { index, entry in
            let info = entry.info
            let ladder = ladders[index]
            let (layoutID, animated) = layouts[index]
            let open = info.isMainPlayer
                || (info.opensByDefault && WinampModernContainerTopology.defaultVisibilitySuppression(of: info) == nil)
            // `abca`: each rung labelled by the first rung it matches, so a timer that undoes its own
            // transition reads as one, not as static (Phase 26).
            var seen: [Data] = []
            let frames = String(ladder.map { rung -> Character in
                if let at = seen.firstIndex(of: rung.pixels) { return Character(UnicodeScalar(97 + at)!) }
                seen.append(rung.pixels)
                return Character(UnicodeScalar(96 + seen.count)!)
            })
            // ponytail: "back to the first frame" is the revert test, so a loop that happens to land
            // on frame 0 at t = 4 reads as reverted; compare per-object heads if that ever bites.
            let verdict = seen.count == 1 ? "static" : frames.last == "a" ? "reverted" : "moving"
            let moved = Set(ladder.dropFirst().flatMap { rung in
                rung.nodes.compactMap { id, state in ladder[0].nodes[id] == state ? nil : id }
                    + ladder[0].nodes.keys.filter { rung.nodes[$0] == nil }
            }).compactMap { loaded.runtime.graph.object(withID: $0) }
                .map { "\($0.typeName)#\($0.xmlID ?? "-")" }.sorted()
            let anim = animated.map { object -> String in
                "\(object.xmlID ?? "-")=\(cause(of: object.stableID, ladder: ladder, moving: seen.count > 1))"
            }.sorted()
            let autoplay = animated.filter { $0.attributes["autoplay"] == "1" || $0.attributes["autoreplay"] == "1" }.count
            // The plan's rule at layout level (§3 S3): an `animatedlayer` declared, pixels identical.
            let suspect = seen.count == 1 && !animated.isEmpty
            // The S4 impact score's numerator: animated layers that did not move.
            let still = animated.filter {
                cause(of: $0.stableID, ladder: ladder, moving: seen.count > 1) != "moving"
            }.count
            return [info.id, layoutID, open ? "1" : "0", frames, verdict, "\(animated.count)", "\(autoplay)",
                    timer ? "yes" : "no", suspect ? "1" : "0",
                    summary(moved), summary(anim), "\(still)"].joined(separator: "\t")
        }
    }

    /// Which of the plan's three dead-animation causes, from the play head across the ladder:
    /// `never-played`, `stuck` (playing, frame never advanced), `not-repainted` (frame advanced,
    /// layout pixels did not) — or `one-frame` (playing, but its sheet resolves to a single frame),
    /// `hidden` (advancing, not in the drawn scene) and `moving`.
    private static func cause(of id: WasabiObjectID, ladder: [Rung], moving: Bool) -> String {
        let heads = ladder.compactMap { $0.heads[id] }
        if Set(heads.map(\.frame)).count > 1 {
            if ladder.allSatisfy({ $0.nodes[id] == nil }) { return "hidden" }
            return moving ? "moving" : "not-repainted"
        }
        guard heads.contains(where: \.isPlaying) else { return "never-played" }
        return heads.allSatisfy({ $0.count <= 1 }) ? "one-frame" : "stuck"
    }

    private static func rung(_ renderer: WasabiSceneRenderer, animated: [WasabiObject],
                             runtime: WinampModernScriptRuntime, clock: TimeInterval) -> Rung {
        let size = renderer.canvasSize
        var pixels = Data()
        if size.width >= 1, size.height >= 1,
           let context = CGContext(data: nil, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                                   bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            // Text draws into the current NSGraphicsContext, not the CGContext it is handed.
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = previous
            if let data = context.data { pixels = Data(bytes: data, count: context.bytesPerRow * context.height) }
        }
        var nodes: [WasabiObjectID: String] = [:]
        for node in renderer.sceneNodes() {
            nodes[node.object.stableID] = "\(node.frame) \(node.bitmapID ?? "-") \(node.inheritedAlpha) "
                + (node.object.attributes["alpha"] ?? "-")
        }
        var heads: [WasabiObjectID: (frame: Int, isPlaying: Bool, count: Int)] = [:]
        for object in animated {
            let count = runtime.animationFrameCount(of: object)
            let state = WasabiAnimation.state(of: object, frameCount: count, clock: clock)
            heads[object.stableID] = (state.frame, state.isPlaying, count)
        }
        return Rung(pixels: pixels, nodes: nodes, heads: heads)
    }

    /// Every `animatedlayer` under the container's opening layout, shown or not.
    private static func animatedLayers(in layoutID: String, of container: WasabiObject) -> [WasabiObject] {
        guard let layout = container.children.first(where: {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame && $0.xmlID == layoutID
        }) else { return [] }
        var found: [WasabiObject] = []
        var stack = [layout]
        while let object = stack.popLast() {
            if object.typeName.caseInsensitiveCompare("animatedlayer") == .orderedSame { found.append(object) }
            stack += object.children
        }
        return found
    }

    /// `-` when empty; at most twelve entries, then `+<n>`, so one busy layout cannot swamp a row.
    private static func summary(_ items: [String]) -> String {
        guard !items.isEmpty else { return "-" }
        let shown = items.prefix(12).joined(separator: ",")
        return items.count > 12 ? "\(shown),+\(items.count - 12)" : shown
    }
}
