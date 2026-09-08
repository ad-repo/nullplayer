import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

// MARK: - The probe harness
//
// `.wmz` had one opt-in PNG dump and a skipped test, which is how 6,044 lines of engine reached a
// state where only 4 of 14 corpus archives load and `swift test` stayed green throughout. The
// `.wal` subsystem paid for the lesson first: *a vertical-flip and a wrong crop origin survived
// 490+ green tests because nothing ever rendered a frame.* Structural cleanliness measures almost
// nothing.
//
// So this file is the instrument, not a test of the engine. It prints one machine-readable line per
// measured fact, keyed by view, inside a `SKIN <file.wmz>` block, and `scripts/wmp_skin_census.sh`
// and `scripts/wmp_render_sweep.sh` parse those lines. Every flag is documented once, canonically,
// in `skills/wmp-skin-guide/reference/harness.md` — add a flag there in the same change that adds
// it here, and never restate a command anywhere else.
//
//   WMP_SKIN=<file-or-directory>   the archive, or a directory swept in one process invocation
//   WMP_RENDER_DUMP=<dir>          write every view to PNG, per-skin subdirectory in a sweep
//   WMP_RENDER_PROBE=<view|all>    every scene node: type, id, resolved frame, clip, paint, attrs
//   WMP_RENDER_BITMAPS=1           resolved bitmap count and every one that failed, with missing=
//   WMP_RENDER_SCRIPTS=1           per program: bytes, declared handlers, whether it evaluated
//   WMP_RENDER_EXPR=1              every JScript: geometry expression, its value, its order, deps
//   WMP_CALL_TRACE=1               every host object-model access, and whether it was recognised
//   WMP_RENDER_CLICK=<view>@x,y[;x,y…]   drive clicks in order and report what each one moved
//   WMP_RENDER_SETTLE=<seconds>    pump the run loop and drive onTimer before measuring
//   WMP_RENDER_SIZE=<W>x<H>        resize before measuring, then re-drive onResize
//
// A skin that fails to load prints `SKIN <file> FAILED <error>` and the sweep carries on: one
// broken archive must not abandon the other thirteen, and with 10 of 14 rejected today a harness
// that stopped on the first failure would measure nothing at all.

/// One `write(2)` per line, straight to the descriptor, never through stdio.
///
/// W35, the reason this exists. In the 180-archive sweep a `CALL` line and the `SKIN` line that
/// opened the next archive landed inside one another —
///
///     CALL vSKIN Windows_XP_Media_Center_Edition.wmz
///
/// — and the 5,087 bytes that should have followed the `CALL` (the rest of that skin's trace, two
/// `PNG` lines and a `RENDER-DUMP`) never reached the file at all. That cost **two** rows: the
/// containing block is flagged `damaged` and the swallowed skin reads `not-run`, and both skins
/// measure fine when run alone.
///
/// It is byte-identical across two full sweeps and does not reproduce on a two-archive corpus, so
/// it is the buffered stream rather than anything in the content: what is lost is whatever `stdout`
/// happened to be holding. `print` writes into that buffer. A lost buffer is lost measurements, and
/// a silently missing row reads exactly like a skin that stopped drawing — the failure mode this
/// whole harness exists to escape. Writing each line unbuffered and whole removes the buffer that
/// can be lost, and `testEmitsEveryLineWholeUnderConcurrentWriters` proves the emitter itself.
///
/// The `fflush` keeps stdio's own output (XCTest's case lines) ordered against ours; without it the
/// two streams would reach the file in different orders and a block boundary could move.
enum WMPHarnessOutput {
    private static let lock = NSLock()

    static func emit(_ line: String, to descriptor: Int32 = STDOUT_FILENO) {
        let bytes = Array((line + "\n").utf8)
        lock.lock()
        defer { lock.unlock() }
        fflush(stdout)
        bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress!.advanced(by: offset),
                                    buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0 && (errno == EINTR || errno == EAGAIN) {
                    continue
                } else {
                    // Nothing useful is left to do with a descriptor that will not take bytes; the
                    // census's short-capture floor is what notices a truncated run.
                    return
                }
            }
        }
    }
}

/// Everything the harness prints for one archive. Held as a value so a directory sweep and a
/// single-archive run take byte-identical paths and their captures diff cleanly.
struct WMPProbe {
    let env: [String: String]

    var wantsProbe: Bool { env["WMP_RENDER_PROBE"] != nil }
    var wantsBitmaps: Bool { env["WMP_RENDER_BITMAPS"] != nil }
    var wantsScripts: Bool { env["WMP_RENDER_SCRIPTS"] != nil }
    var wantsExpressions: Bool { env["WMP_RENDER_EXPR"] != nil }
    var wantsCallTrace: Bool { env["WMP_CALL_TRACE"] != nil }

    var requestedSize: WMPSize? {
        guard let spec = env["WMP_RENDER_SIZE"] else { return nil }
        let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return WMPSize(width: CGFloat(parts[0]), height: CGFloat(parts[1]))
    }

    var settleSeconds: TimeInterval {
        max(0, min(30, Double(env["WMP_RENDER_SETTLE"] ?? "") ?? 0))
    }

    /// `<view>@x,y[;x,y…]`. Several points in one run is how a second click is checked to undo the
    /// first: state that does not survive between them is the defect, not the harness.
    var clicks: (viewID: String, points: [WMPPoint])? {
        guard let spec = env["WMP_RENDER_CLICK"] else { return nil }
        let halves = spec.split(separator: "@", maxSplits: 1).map(String.init)
        guard halves.count == 2 else { return nil }
        let points = halves[1].split(separator: ";").compactMap { entry -> WMPPoint? in
            let pair = entry.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard pair.count == 2 else { return nil }
            return WMPPoint(x: CGFloat(pair[0]), y: CGFloat(pair[1]))
        }
        return points.isEmpty ? nil : (halves[0], points)
    }

    func probes(_ viewID: String) -> Bool {
        guard let spec = env["WMP_RENDER_PROBE"] else { return false }
        return spec.isEmpty || spec == "1" || spec.caseInsensitiveCompare("all") == .orderedSame
            || spec.caseInsensitiveCompare(viewID) == .orderedSame
    }
}

/// The script pass.
///
/// It used to be able to be *absent*: the runtime lived in a helper process built beside the test
/// binary, and when that binary was missing every script-derived line below went quiet — which
/// reads exactly like a skin with no scripts, and is false for every corpus archive. The runtime is
/// now in-process, so there is nothing to be missing; `unavailableReason` stays only so the
/// `runtime=` field of the `SCRIPTS` line keeps its grammar and a future failure has somewhere
/// honest to be reported.
struct WMPScriptPass {
    let session: WMPScriptRuntime?
    let unavailableReason: String?

    init(archiveData: Data, defaults: UserDefaults) {
        // The production budget is 0.25 s per transaction. The harness is not measuring latency and
        // a corpus archive evaluates up to 87 KB of JScript in one pass, so it uses a generous one:
        // a timeout here would be reported as a script failure the app does not have.
        session = WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: archiveData,
                                                                   defaults: defaults),
                                   executionSeconds: 5)
        unavailableReason = nil
    }
}

final class WMPRenderDumpTests: XCTestCase {
    private let pixels: [UInt8] = [
        255, 0, 0, 255,   0, 255, 0, 255,
        0, 0, 255, 255,   255, 0, 255, 255
    ]

    func testUprightCropColorKeyNestedClipZOrderAndBackingScale() async throws {
        let bmp = try WMPSkinTestSupport.encodedImage(width: 2, height: 2, rgba: pixels, type: .bmp)
        let xml = """
        <THEME><VIEW id="main" width="8" height="6">
          <SUBVIEW id="parent" left="1" top="1" width="5" height="4">
            <IMAGE id="whole" left="1" top="1" width="2" height="2" image="pixel.bmp" transparencyColor="#FF00FF"/>
            <IMAGE id="crop" left="3" top="1" width="1" height="1" image="pixel.bmp"
                   cropLeft="1" cropTop="0" cropWidth="1" cropHeight="1"/>
          </SUBVIEW>
          <SUBVIEW id="back" left="0" top="0" width="1" height="1" zIndex="1" backgroundColor="#0000FF"/>
          <SUBVIEW id="front" left="0" top="0" width="1" height="1" zIndex="2" backgroundColor="#FF0000"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8)),
            WMPTestArchiveEntry("pixel.bmp", data: bmp)
        ])
        let skin = try await WMPSkinLoader().load(from: url)
        let store = WMPImageStore(provider: skin.archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")
        let one = try await WMPRenderer(imageStore: store).render(scene: scene, backingScale: 1)
        XCTAssertFalse(scene.wasBuiltOnMainThread)
        XCTAssertFalse(one.wasRenderedOnMainThread)
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 0, yFromTop: 0), [255, 0, 0, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 2, yFromTop: 2), [255, 0, 0, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 3, yFromTop: 2), [0, 255, 0, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 2, yFromTop: 3), [0, 0, 255, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 3, yFromTop: 3), [0, 0, 0, 0])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 4, yFromTop: 2), [0, 255, 0, 255])

        let two = try await WMPRenderer(imageStore: store).render(scene: scene, backingScale: 2)
        XCTAssertEqual(two.image.width, 16)
        XCTAssertEqual(two.image.height, 12)
        XCTAssertEqual(WMPSkinTestSupport.rgba(two.image, x: 4, yFromTop: 4), [255, 0, 0, 255])
    }

    /// A subview commonly declares `clippingColor` — the colour cut out of its own artwork to shape
    /// the window — *and* `transparencyColor`, as two different colours. Keying only one of them
    /// leaves the other painted as a flat slab (W8).
    func testClippingAndTransparencyColorsAreBothKeyedOut() async throws {
        let bmp = try WMPSkinTestSupport.encodedImage(width: 2, height: 2, rgba: pixels, type: .bmp)
        let xml = """
        <THEME><VIEW id="main" width="2" height="2">
          <IMAGE id="both" left="0" top="0" width="2" height="2" image="pixel.bmp"
                 transparencyColor="#FF00FF" clippingColor="#FF0000"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8)),
            WMPTestArchiveEntry("pixel.bmp", data: bmp)
        ])
        let skin = try await WMPSkinLoader().load(from: url)
        let store = WMPImageStore(provider: skin.archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")
        guard case let .image(specification)? = scene.commands.first(where: { $0.nodeID == "both" })?.paint else {
            return XCTFail("The keyed image command is missing from the scene.")
        }
        XCTAssertEqual(specification.colorKeys, [WMPColor(red: 255, green: 0, blue: 255),
                                                 WMPColor(red: 255, green: 0, blue: 0)])
        let rendered = try await WMPRenderer(imageStore: store).render(scene: scene, backingScale: 1)
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 0, yFromTop: 0), [0, 0, 0, 0])
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 1, yFromTop: 1), [0, 0, 0, 0])
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 1, yFromTop: 0), [0, 255, 0, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 0, yFromTop: 1), [0, 0, 255, 255])
    }

    func testTextCounterTransformKeepsGlyphsUprightInTopFrame() async throws {
        let xml = """
        <THEME><VIEW id="main" width="80" height="40">
          <TEXT id="label" left="2" top="2" width="50" height="16" value="Ab"
                fontType="Arial" fontSize="12" foregroundColor="#FFFFFF"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))])
        let skin = try await WMPSkinLoader().load(from: url)
        let store = WMPImageStore(provider: skin.archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")
        let result = try await WMPRenderer(imageStore: store).render(scene: scene)
        var topAlpha = 0, bottomAlpha = 0
        for y in 0..<40 {
            for x in 0..<80 {
                let alpha = WMPSkinTestSupport.rgba(result.image, x: x, yFromTop: y)[3]
                if y < 20 { topAlpha += alpha > 0 ? 1 : 0 }
                else { bottomAlpha += alpha > 0 ? 1 : 0 }
            }
        }
        XCTAssertGreaterThan(topAlpha, 0)
        XCTAssertEqual(bottomAlpha, 0)
    }

    // MARK: - Instrument proofs
    //
    // Three `.wal` harness blind spots each made a real defect look absent, so a probe is not
    // trusted about absence until it has been shown reporting a presence. These run on every plain
    // `swift test`; if one of them stops holding, the corresponding sweep column is lying.

    /// `WMP_RENDER_BITMAPS` separates "art is absent" (Class C) from "art draws wrong" (Class B),
    /// and it can only do that if it actually notices an absence. Rename the asset the markup asks
    /// for and the probe must name it.
    func testRenderBitmapsProbeReportsAMissingAsset() async throws {
        let bmp = try WMPSkinTestSupport.encodedImage(width: 2, height: 2, rgba: pixels, type: .bmp)
        let xml = """
        <THEME><VIEW id="main" width="8" height="6">
          <IMAGE id="present" left="0" top="0" width="2" height="2" image="pixel.bmp"/>
          <IMAGE id="absent" left="4" top="0" width="2" height="2" image="renamed.bmp"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8)),
            WMPTestArchiveEntry("pixel.bmp", data: bmp)
        ])
        let skin = try await WMPSkinLoader().load(from: url)
        let store = WMPImageStore(provider: skin.archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")
        let tally = WMPHarness.bitmapTally(scene: scene, skin: skin, imageStore: store)
        XCTAssertEqual(tally.resolved, 1)
        XCTAssertEqual(tally.missing, ["renamed.bmp"])
    }

    /// The probe must name the nodes the renderer actually drew, with the frames it drew them at —
    /// "a node exists" says nothing about where it landed, which is the whole Class B distinction.
    func testRenderProbeReportsResolvedFramesForEveryDrawnNode() async throws {
        let xml = """
        <THEME><VIEW id="main" width="40" height="20">
          <SUBVIEW id="pane" left="4" top="2" width="20" height="10" backgroundColor="#102030"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))])
        let skin = try await WMPSkinLoader().load(from: url)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let lines = WMPHarness.probeLines(scene: scene, skin: skin)
        let pane = try XCTUnwrap(lines.first { $0.contains("id=pane") })
        XCTAssertTrue(pane.contains("frame=4,2 20x10"), pane)
        XCTAssertTrue(pane.contains("paint=fill:#102030"), pane)
    }

    /// `WMP_RENDER_EXPR` is the layout engine's only witness for the 13 of 14 corpus skins that
    /// compute geometry in JScript. An expression that silently answers 0 is the difference between
    /// a skin and a blank window, so the probe must report both the value and the fact it resolved.
    func testExpressionProbeReportsSourceAndResolvedValue() async throws {
        let xml = """
        <THEME><VIEW id="main" width="100" height="40">
          <SUBVIEW id="pane" left="0" top="0" width="jscript:view.width - 20" height="10"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))])
        let skin = try await WMPSkinLoader().load(from: url)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let lines = WMPHarness.expressionLines(scene: scene, skin: skin, viewID: "main", output: nil)
        let width = try XCTUnwrap(lines.first { $0.contains("pane.width") })
        XCTAssertTrue(width.contains("view.width - 20"), width)
        XCTAssertTrue(width.contains("-> 80"), width)
    }

    /// The emitter itself, because a lost line is the one defect this harness cannot report on.
    ///
    /// W35 lost 5,087 bytes of one skin's measurements mid-line in a 180-archive sweep, and the
    /// only reason anyone knew is that the collision left a visible splice for the census to flag.
    /// A loss that had landed on a line boundary would have read as a skin that simply drew less.
    /// So: many writers, lines longer than any stdio buffer, and every line has to come back whole
    /// and exactly once.
    func testEmitsEveryLineWholeUnderConcurrentWriters() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wmp-emit-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let writers = 8, perWriter = 200
        DispatchQueue.concurrentPerform(iterations: writers) { writer in
            for index in 0..<perWriter {
                // Every fourth line is 9 KB — past any stdio buffer, so a line that survives whole
                // proves the partial-write loop and not just that the line happened to fit.
                let padding = index % 4 == 0 ? String(repeating: "x", count: 9_000) : "value"
                WMPHarnessOutput.emit("CALL writer\(writer) line\(index) \(padding)",
                                      to: handle.fileDescriptor)
            }
        }
        try handle.close()

        let lines = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(lines.count, writers * perWriter, "lines were lost or split")
        var seen = Set<String>()
        for line in lines {
            XCTAssertTrue(line.hasPrefix("CALL writer"), "a line was spliced: \(line.prefix(60))")
            let identity = line.split(separator: " ").prefix(3).joined(separator: " ")
            XCTAssertTrue(seen.insert(identity).inserted, "duplicated: \(identity)")
        }
        XCTAssertEqual(seen.count, writers * perWriter)
    }

    // MARK: - The corpus sweep

    /// `WMP_SKIN` accepts a file **or a directory**. Directory mode sweeps the whole corpus in one
    /// process invocation: the `.wal` sweep does 79 archives in ~5 minutes where a shell loop over
    /// them took 25, and the startups were nearly all of the difference. One invocation also cannot
    /// be invalidated halfway — a sweep is a build, and an edit landing mid-loop silently wrote
    /// *empty* captures that then diffed as "everything changed".
    func testSweepsSkinOrCorpus() async throws {
        let env = ProcessInfo.processInfo.environment
        // WMP_TEST_WMZ is the flag this harness shipped with. Kept as an alias so the Phase 0–8
        // handoff docs' invocations still run; WMP_SKIN is the documented name.
        guard let path = env["WMP_SKIN"] ?? env["WMP_TEST_WMZ"], !path.isEmpty else {
            throw XCTSkip("Set WMP_SKIN to a .wmz file or a directory of them. "
                + "See skills/wmp-skin-guide/reference/harness.md.")
        }
        let root = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        // The enumeration rule, applied: `-type f` and a case-insensitive extension. A corpus is
        // allowed to hold a directory, and `.WMZ` is a real spelling.
        let archives: [URL] = isDirectory.boolValue
            ? ((try? FileManager.default.contentsOfDirectory(at: root,
                    includingPropertiesForKeys: [.isRegularFileKey])) ?? [])
                .filter { $0.pathExtension.lowercased() == "wmz"
                    && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            : [root]
        guard !archives.isEmpty else { throw XCTSkip("No .wmz archives under \(path).") }

        let dumpRoot = (env["WMP_RENDER_DUMP"] ?? env["WMP_RENDER_DUMP_DIR"]).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let dumpRoot {
            try FileManager.default.createDirectory(at: dumpRoot, withIntermediateDirectories: true)
        }
        // The harness must not write the user's real preferences: `theme.savePreference` is the
        // second-ranked host call in the corpus (116 occurrences) and a sweep would persist every
        // skin's idea of its own state into the app the user then launches.
        let suite = "wmp.harness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let probe = WMPProbe(env: env)
        WMPHarnessOutput.emit("HARNESS \(archives.count) archive(s) from \(path)")
        for archive in archives {
            // The sweep's own frame. Every other line is keyed by view, which is not unique across
            // skins, so without this a directory run is an unattributable wall of text. Printed for
            // a single archive too, so one skin's capture and its row in a sweep stay identical.
            WMPHarnessOutput.emit("SKIN \(archive.lastPathComponent)")
            let dump = dumpRoot.map { root -> URL in
                archives.count > 1
                    ? root.appendingPathComponent(archive.deletingPathExtension().lastPathComponent,
                                                  isDirectory: true)
                    : root
            }
            do {
                try await WMPHarness.measure(archive: archive, dump: dump, probe: probe, defaults: defaults)
            } catch {
                // One unloadable archive must not abandon the rest — with 10 of 14 rejected today,
                // stopping here would measure nothing. The failure is printed where the diff sees it.
                WMPHarnessOutput.emit("SKIN \(archive.lastPathComponent) FAILED \(WMPHarness.oneLine(error))")
            }
            fflush(stdout)
        }
        // The harness asserts nothing about the corpus: 10 of 14 archives are expected to fail
        // today, and a red test would stop the sweep from producing the rows that rank the work.
        // The census and the sweep read the printed lines; this only proves the run completed.
        XCTAssertFalse(archives.isEmpty)
    }
}

// MARK: - Line production

/// Every line the harness prints, in one place, so the grammar the census and sweep parse has a
/// single definition. Nothing here is used by the app.
enum WMPHarness {

    static func oneLine(_ error: Error) -> String {
        let text = (error as? WMPFailure)?.errorDescription ?? "\(error)"
        return text.replacingOccurrences(of: "\n", with: " · ")
    }

    static func measure(archive: URL, dump: URL?, probe: WMPProbe, defaults: UserDefaults) async throws {
        let started = CFAbsoluteTimeGetCurrent()
        let skin = try await WMPSkinLoader().load(from: archive)
        let loadMilliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        let archiveData = (try? Data(contentsOf: archive)) ?? Data()

        let bytes = skin.archive.entries.reduce(UInt64(0)) { $0 &+ $1.uncompressedSize }
        WMPHarnessOutput.emit("LOAD definition=\(skin.definitionPath) encoding=\(skin.textEncoding.rawValue) "
            + "entries=\(skin.archive.entries.count) bytes=\(bytes) views=\(skin.views.count) "
            + "nodes=\(skin.graph.allNodes.count) scripts=\(skin.scripts.count) "
            + "resources=\(skin.resources.count) loadms=\(String(format: "%.1f", loadMilliseconds))")
        for line in findingLines(skin.diagnostics) { WMPHarnessOutput.emit(line) }
        for line in compatibilityLines(skin) { WMPHarnessOutput.emit(line) }

        let pass = WMPScriptPass(archiveData: archiveData, defaults: defaults)
        if let reason = pass.unavailableReason {
            // Printed once per archive whether or not WMP_RENDER_SCRIPTS asked, because every
            // script-derived line below goes quiet without it and quiet reads as "no scripts".
            WMPHarnessOutput.emit("SCRIPTS programs=\(skin.scripts.count) runtime=unavailable (\(reason))")
        }
        if probe.wantsScripts { for line in scriptLines(skin: skin, pass: pass) { WMPHarnessOutput.emit(line) } }

        let store = WMPImageStore(provider: skin.archive)
        let builder = WMPSceneBuilder(loadedSkin: skin, imageStore: store)
        for view in skin.views {
            do {
                try await measure(view: view.id, skin: skin, builder: builder, imageStore: store,
                                  pass: pass, dump: dump, probe: probe)
            } catch {
                WMPHarnessOutput.emit("RENDER-DUMP \(view.id) FAILED \(oneLine(error))")
            }
        }
        if let session = pass.session { await session.teardown() }
    }

    private static func measure(view viewID: String, skin: WMPLoadedSkin, builder: WMPSceneBuilder,
                                imageStore: WMPImageStore, pass: WMPScriptPass,
                                dump: URL?, probe: WMPProbe) async throws {
        // The size the scene is measured at. `WMP_RENDER_SIZE` reproduces the user's window, which
        // for an expression-driven layout is a different layout, not the same one scaled.
        var scene = try await builder.build(viewID: viewID, requestedSize: probe.requestedSize)

        var output: WMPScriptOutput?
        if let session = pass.session {
            await session.prepareForViewSwitch()
            // The load pass: the skin's programs evaluate, every `JScript:` geometry expression
            // resolves, and the view's own `onLoad` handlers run — exactly what the app's first
            // transaction does. Driving `onLoad` here is not optional detail: it is where a skin
            // sets up its panes, and a harness that skipped it measured a skin nobody sees.
            output = await session.transact(skin: skin, viewID: viewID, size: scene.canvasSize,
                                            snapshot: WMPHostSnapshot(),
                                            event: eventFor(name: "onLoad", skin: skin, viewID: viewID),
                                            geometry: scene.scriptGeometry)
            if probe.requestedSize != nil {
                // A resize is a second layout pass, not a re-scale: the expressions must run again
                // against the new `view.width`/`view.height` before anything is measured.
                output = await session.transact(skin: skin, viewID: viewID, size: scene.canvasSize,
                                                snapshot: WMPHostSnapshot(),
                                                event: eventFor(name: "onResize", skin: skin, viewID: viewID),
                                                geometry: scene.scriptGeometry)
            }
            if probe.settleSeconds > 0, let timer = eventFor(name: "onTimer", skin: skin, viewID: viewID) {
                // The view's own timer, run for real rather than fired once.
                //
                // A `.wmz` animates through `view.timerInterval`: Corona's compact view registers a
                // timed event and writes the interval it wants, and its player view declares
                // `timerInterval="4000"` in markup to drive its transport readouts. A single
                // `onTimer` call cannot reach the end of an animation that takes twenty of them, so
                // this drives the loop the app drives, at the period the skin asks for, honouring
                // every `setViewTimerInterval` the handlers post back.
                // Seeded from the markup, then from whatever the load pass already asked for:
                // Corona's compact view declares `timerInterval="0"` and its `OnTinyLoad` turns the
                // timer on, so reading only the attribute measures a skin that never animates.
                var interval = WMPMainWindowController.authoredTimerInterval(in: skin, viewID: viewID)
                for command in output?.hostCommands ?? [] where command.action == "setViewTimerInterval" {
                    interval = Int(command.value?.number ?? 0)
                }
                let deadline = Date().addingTimeInterval(probe.settleSeconds)
                while Date() < deadline {
                    let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds, interval)
                    guard interval > 0 else { break }
                    // `RunLoop.run(until:)` returns immediately with no input sources attached,
                    // which turned this into a busy loop that tripped the runtime's own 120/s rate
                    // limit and measured nothing.
                    try? await Task.sleep(nanoseconds: UInt64(period) * 1_000_000)
                    output = await session.transact(skin: skin, viewID: viewID, size: scene.canvasSize,
                                                    snapshot: WMPHostSnapshot(), event: timer,
                                                    geometry: scene.scriptGeometry)
                    // Rebuild between ticks: an animation reads the geometry it is drawn at, and a
                    // loop that fed it the same starting frame every time would freeze on the first
                    // step while still looking like it was running.
                    if let overrides = output?.overrides, overrides != .empty,
                       let rebuilt = try? await builder.build(viewID: viewID,
                                                              requestedSize: probe.requestedSize,
                                                              overrides: overrides) {
                        scene = rebuilt
                    }
                    for command in output?.hostCommands ?? []
                    where command.action == "setViewTimerInterval" {
                        interval = Int(command.value?.number ?? 0)
                    }
                }
                if interval == 0, output == nil {
                    output = await session.transact(skin: skin, viewID: viewID, size: scene.canvasSize,
                                                    snapshot: WMPHostSnapshot(), event: timer,
                                                    geometry: scene.scriptGeometry)
                }
            }
            if let output, output.overrides != .empty {
                scene = try await builder.build(viewID: viewID, requestedSize: probe.requestedSize,
                                                overrides: output.overrides)
            }
            for diagnostic in output?.diagnostics ?? [] {
                WMPHarnessOutput.emit("SCRIPT-DIAG \(viewID) [\(diagnostic.code)] \(diagnostic.message)")
            }
        }

        WMPHarnessOutput.emit("RENDER-DUMP \(viewID): \(WMPNumber.format(scene.canvasSize.width))x"
            + "\(WMPNumber.format(scene.canvasSize.height)), \(scene.metrics.resolvedNodeCount) nodes, "
            + "\(scene.commands.count) commands, \(scene.hits.count) hits, "
            + "\(scene.widgets.count) widgets, \(scene.metrics.unresolvedNodeCount) unresolved")

        if probe.probes(viewID) {
            for line in probeLines(scene: scene, skin: skin) { WMPHarnessOutput.emit(line) }
        }
        if probe.wantsBitmaps {
            let tally = bitmapTally(scene: scene, skin: skin, imageStore: imageStore)
            WMPHarnessOutput.emit("BITMAPS \(viewID): resolved=\(tally.resolved) missing=\(tally.missing.joined(separator: " "))")
        }
        if probe.wantsExpressions {
            for line in expressionLines(scene: scene, skin: skin, viewID: viewID, output: output) { WMPHarnessOutput.emit(line) }
        }
        if probe.wantsCallTrace {
            for line in callTraceLines(viewID: viewID, output: output, unavailable: pass.unavailableReason) {
                WMPHarnessOutput.emit(line)
            }
        }
        if let clicks = probe.clicks, clicks.viewID.caseInsensitiveCompare(viewID) == .orderedSame {
            scene = await drive(clicks: clicks.points, on: scene, viewID: viewID, skin: skin,
                                builder: builder, pass: pass, probe: probe)
        }
        if let dump {
            try FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
            let record = try await WMPRenderer(imageStore: imageStore).dump(scene: scene, to: dump)
            WMPHarnessOutput.emit("PNG \(viewID): \(record.pngFilename)")
        }
    }

    // MARK: Findings and compatibility

    static func findingLines(_ diagnostics: [WMPDiagnostic]) -> [String] {
        var counts: [String: (WMPDiagnostic, Int)] = [:]
        for diagnostic in diagnostics {
            let key = "\(diagnostic.code.rawValue)|\(diagnostic.message)"
            counts[key] = (diagnostic, (counts[key]?.1 ?? 0) + 1)
        }
        return counts.values.sorted {
            $0.0.code.rawValue == $1.0.code.rawValue ? $0.0.message < $1.0.message
                : $0.0.code.rawValue < $1.0.code.rawValue
        }.map { diagnostic, count in
            "FINDING [\(diagnostic.severity.rawValue)] \(diagnostic.code.rawValue) ×\(count) "
                + diagnostic.message.replacingOccurrences(of: "\n", with: " ")
        }
    }

    /// The static half of the demand tally: what the markup and the scripts *ask for*, minus what
    /// the engine claims to implement. It ranks Class A work. It is not a substitute for
    /// `WMP_CALL_TRACE`, which is the only thing that catches a member that is recognised and
    /// answers wrong.
    static func compatibilityLines(_ skin: WMPLoadedSkin) -> [String] {
        let report = skin.compatibilityReport
        let tags = report.tags.filter { !supportedTags.contains($0.name) }
        let members = report.members.filter { !supportsMember($0.name) }
        var lines = ["COMPAT unknown-tags=\(tags.count) unknown-members=\(members.count) "
            + "resources-missing=\(skin.resources.filter { $0.status == .missing }.count) "
            + "resources-unsupported=\(skin.resources.filter { $0.status == .unsupported }.count)"]
        lines += tags.sorted { $0.count > $1.count }.map { "UNKNOWN tag \($0.name) ×\($0.count)" }
        lines += members.sorted { $0.count > $1.count }.prefix(40)
            .map { "UNKNOWN member \($0.name) ×\($0.count)" }
        return lines
    }

    // MARK: The scene probe

    /// Type, id, resolved frame, clip, paint and authored attributes for every node the scene
    /// actually placed. A node existing says nothing about where it is drawn; this is the line that
    /// says where.
    static func probeLines(scene: WMPScene, skin: WMPLoadedSkin) -> [String] {
        var lines = scene.widgets.map { widget in
            "WIDGET \(scene.viewID)/\(widget.stableID) \(widget.kind) id=\(widget.nodeID ?? "-") "
                + "frame=\(widget.frame) clip=\(widget.clipRect.map(String.init(describing:)) ?? "-") "
                + "visible=\(widget.clipRect.flatMap { widget.frame.intersection($0) }.map(String.init(describing:)) ?? "none")"
        }
        lines += Self.paintProbeLines(scene: scene, skin: skin)
        return lines
    }

    private static func paintProbeLines(scene: WMPScene, skin: WMPLoadedSkin) -> [String] {
        let nodesByID = Dictionary(skin.graph.allNodes.map { ($0.stableID, $0) }) { first, _ in first }
        return scene.commands.map { command in
            let node = nodesByID[command.stableID]
            let paint: String
            switch command.paint {
            case let .fill(color): paint = "fill:\(color)"
            case let .image(image):
                let crop = image.sourceRect.map { " crop=\($0)" } ?? ""
                let key = image.colorKeys.map { " colorKey=\($0)" }.joined()
                paint = "image:\(image.resourcePath)\(crop)\(key)\(image.tiled ? " tiled" : "")"
            case let .text(text): paint = "text:\(text.value)"
            }
            let attributes = (node?.attributes ?? []).prefix(12)
                .map { "\($0.name)=\(condense($0.rawValue))" }.joined(separator: " ")
            return "PROBE \(scene.viewID)/\(command.stableID) \(node?.kind.description ?? "?") "
                + "id=\(command.nodeID ?? "-") frame=\(command.frame) "
                + "clip=\(command.clipRect.map(String.init(describing:)) ?? "-") z=\(command.zIndex) "
                + "paint=\(paint) attrs=[\(attributes)]"
        }
    }

    // MARK: Bitmaps

    /// Separates "art is absent" (Class C, small) from "art draws wrong" (Class B, expensive). A
    /// path counts as resolved only when the store actually decoded it: a resource that resolves in
    /// the archive and then fails to decode is missing as far as the screen is concerned.
    static func bitmapTally(scene: WMPScene, skin: WMPLoadedSkin,
                            imageStore: WMPImageStore) -> (resolved: Int, missing: [String]) {
        var resolved = Set<String>(), missing = Set<String>()
        for command in scene.commands {
            guard case let .image(image) = command.paint else { continue }
            if (try? imageStore.image(for: image.resourcePath, colorKeys: image.colorKeys)) != nil {
                resolved.insert(image.resourcePath)
            } else {
                missing.insert(image.resourcePath)
            }
        }
        // A resource the loader could not resolve at all never reaches a paint command, so the scan
        // above cannot see it. Those are exactly the renamed and absent assets this probe exists to
        // name, so they are added from the registration list. An authored path that is *empty* is
        // named `<empty>` rather than inserted blank: a blank entry disappears into the space-
        // separated list and the probe would under-report by one with nothing to show for it.
        for registration in skin.resources where registration.status != .available {
            let authored = registration.authoredPath.trimmingCharacters(in: .whitespacesAndNewlines)
            missing.insert(authored.isEmpty ? "<empty:\(registration.attributeName)>" : authored)
        }
        return (resolved.count, missing.sorted(by: WMPPath.less))
    }

    // MARK: Expressions

    /// 13 of 14 corpus skins compute their geometry in JScript, so this is the layout engine's
    /// witness. Both evaluators are reported: the static grammar in `WMPInitialLayoutExpression`
    /// that the scene builder uses today, and — when the script runtime ran — the value the real
    /// context produced, with the dependency order it was evaluated in.
    static func expressionLines(scene: WMPScene, skin: WMPLoadedSkin, viewID: String,
                                output: WMPScriptOutput?) -> [String] {
        guard let view = skin.views.first(where: { $0.id.caseInsensitiveCompare(viewID) == .orderedSame })?.node
        else { return [] }
        var resolver = WMPInitialLayoutResolver(graph: skin.graph, view: view, canvas: scene.canvasSize)
        let order = Dictionary(uniqueKeysWithValues: output?.expressionOrder.enumerated()
            .map { ($0.element.lowercased(), $0.offset) } ?? [])
        let results = Dictionary(output?.expressions.map { ($0.key.lowercased(), $0) } ?? []) { first, _ in first }

        var lines: [String] = []
        for node in skin.graph.allNodes {
            for attribute in node.attributes {
                let name = attribute.name.lowercased()
                guard ["left", "top", "width", "height"].contains(name) else { continue }
                let source: String
                switch attribute.value {
                case let .jScript(text): source = text
                case let .binding(kind, path) where kind == .property: source = path
                default: continue
                }
                let id = node === view ? "view" : (node.xmlID ?? "node\(node.stableID)")
                let key = "\(id).\(name)"
                let statically: String
                if let property = WMPInitialLayoutResolver.Property(rawValue: name) {
                    switch resolver.resolve(node, property: property) {
                    case let .value(value): statically = WMPNumber.format(value)
                    case let .unresolved(reason): statically = "UNRESOLVED(\(reason))"
                    }
                } else { statically = "UNRESOLVED(no property)" }
                let result = results[key.lowercased()]
                let live = result.map { entry -> String in
                    if let error = entry.error { return "ERROR(\(condense(error)))" }
                    return entry.value?.number.map { WMPNumber.format(CGFloat($0)) }
                        ?? entry.value?.string ?? "null"
                } ?? "-"
                let deps = result?.dependencies.joined(separator: ",") ?? ""
                let position = order[key.lowercased()].map { "#\($0)" } ?? "#-"
                lines.append("EXPR \(scene.viewID)/\(key) \(position): \(condense(source)) "
                    + "-> \(statically) live=\(live) deps=[\(deps)]")
            }
        }
        return lines
    }

    // MARK: Scripts

    /// Read this before believing anything about what a skin contains. All 14 corpus archives ship
    /// JScript; a skin whose handlers never ran looks identical, from the outside, to one that has
    /// none.
    static func scriptLines(skin: WMPLoadedSkin, pass: WMPScriptPass) -> [String] {
        let total = skin.scriptSources.values.reduce(0) { $0 + $1.utf8.count }
        let state = pass.unavailableReason.map { "unavailable (\($0))" } ?? "available"
        var lines = ["SCRIPTS programs=\(skin.scripts.count) bytes=\(total) runtime=\(state)"]
        for registration in skin.scripts.sorted(by: { WMPPath.less($0.authoredPath, $1.authoredPath) }) {
            guard let path = registration.resolvedPath, let source = skin.scriptSources[path] else {
                lines.append("SCRIPT \(registration.authoredPath): status=\(registration.status.rawValue)")
                continue
            }
            let handlers = declaredHandlers(in: source)
            lines.append("SCRIPT \(registration.authoredPath): bytes=\(source.utf8.count) "
                + "handlers=[\(handlers.joined(separator: ","))]")
        }
        // Handlers declared on the markup itself, which is where a skin puts its transport wiring.
        var inline: [String: Int] = [:]
        for node in skin.graph.allNodes {
            for attribute in node.attributes {
                guard case .handler = attribute.value else { continue }
                inline[attribute.name.lowercased(), default: 0] += 1
            }
        }
        if !inline.isEmpty {
            lines.append("SCRIPT inline: " + inline.sorted { $0.value > $1.value }
                .map { "\($0.key)×\($0.value)" }.joined(separator: " "))
        }
        return lines
    }

    private static func declaredHandlers(in source: String) -> [String] {
        let pattern = #"function\s+([A-Za-z_$][A-Za-z0-9_$]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var names: [String] = []
        for match in regex.matches(in: source, range: range) {
            guard let swiftRange = Range(match.range(at: 1), in: source) else { continue }
            let name = String(source[swiftRange])
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Exactly what the app dispatches, through the app's own selector — including its view scope,
    /// so the harness cannot measure a skin the app never runs.
    private static func eventFor(name: String, skin: WMPLoadedSkin, viewID: String) -> WMPJScriptEvent? {
        let handlers = WMPMainWindowController.handlers(in: skin, event: name, targetID: nil,
                                                        viewID: viewID)
        guard !handlers.isEmpty else { return nil }
        return WMPJScriptEvent(name: name, targetID: viewID, handlers: handlers)
    }

    // MARK: Call trace

    /// Every host object-model access with what answered and whether the member was recognised. The
    /// ranked `UNRECOGNISED` tail is the Class A backlog; the recognised lines are the only place a
    /// member answering a plausible-but-wrong default is visible at all.
    static func callTraceLines(viewID: String, output: WMPScriptOutput?,
                               unavailable: String?) -> [String] {
        guard let output else {
            return ["CALLS \(viewID): none (\(unavailable ?? "no script transaction"))"]
        }
        var lines = output.calls.map { call in
            "CALL \(viewID) \(call.path) \(call.kind.rawValue) "
                + "value=\(call.value?.string ?? "null") \(Self.resolutionText(call.resolution))"
        }
        var counts: [String: (Int, WMPMemberResolution)] = [:]
        for call in output.calls {
            let existing = counts[call.path] ?? (0, .live)
            // The worst resolution any of them got: a member that answers live once and
            // unrecognised once is not a working member.
            let worst: WMPMemberResolution
            if existing.1 == .unrecognised || call.resolution == .unrecognised { worst = .unrecognised }
            else if existing.1 == .inert || call.resolution == .inert { worst = .inert }
            else { worst = .live }
            counts[call.path] = (existing.0 + 1, worst)
        }
        lines += counts.sorted { $0.value.0 == $1.value.0 ? $0.key < $1.key : $0.value.0 > $1.value.0 }
            .map { "CALLS \(viewID) \($0.key) ×\($0.value.0) \(Self.resolutionText($0.value.1))" }
        return lines
    }

    /// `INERT` is its own word on purpose. A member that is recognised and answers a plausible
    /// default is the most expensive phantom bug this engine can carry — it disappears from the
    /// demand tally and reads as working — so the ones that have no host behind them say so.
    static func resolutionText(_ resolution: WMPMemberResolution) -> String {
        switch resolution {
        case .live: return "ok"
        case .inert: return "INERT"
        case .unrecognised: return "UNRECOGNISED"
        }
    }

    // MARK: Clicks

    /// Several points in order, because a second click undoing the first is the thing worth
    /// checking: under a runtime that cannot hold state between events it does not, and that is the
    /// defect this probe is here to make visible rather than infer.
    private static func drive(clicks: [WMPPoint], on scene: WMPScene, viewID: String,
                              skin: WMPLoadedSkin, builder: WMPSceneBuilder,
                              pass: WMPScriptPass, probe: WMPProbe) async -> WMPScene {
        var scene = scene
        let nodesByID = Dictionary(skin.graph.allNodes.map { ($0.stableID, $0) }) { first, _ in first }
        var previous = WMPSceneOverrides.empty
        for point in clicks {
            let where_ = "\(viewID)@\(WMPNumber.format(point.x)),\(WMPNumber.format(point.y))"
            guard let target = WMPHitTester(hits: scene.hits).hitTest(point) else {
                WMPHarnessOutput.emit("CLICK \(where_) MISS")
                continue
            }
            let node = nodesByID[target.stableID]
            let handlers: [String] = (node?.attributes ?? []).compactMap { attribute in
                guard case let .handler(event, source) = attribute.value,
                      event.caseInsensitiveCompare("onClick") == .orderedSame else { return nil }
                return source
            }
            WMPHarnessOutput.emit("CLICK \(where_) hit=\(target.nodeID ?? "-")#\(target.stableID) kind=\(target.kind) "
                + "action=\(target.action.map(String.init(describing:)) ?? "-") "
                + "sticky=\(target.sticky) handlers=\(handlers.count)")
            guard let session = pass.session, !handlers.isEmpty else { continue }
            let output = await session.transact(skin: skin, viewID: viewID, size: scene.canvasSize,
                snapshot: WMPHostSnapshot(),
                event: WMPJScriptEvent(name: "onClick", targetID: target.nodeID, handlers: handlers),
                geometry: scene.scriptGeometry)
            // Every attribute changed anywhere in the graph, not only on the object that was hit:
            // a skin's click handler routinely moves a sibling pane, and a probe that reported only
            // the target would call that click inert.
            for line in changeLines(from: previous, to: output.overrides, nodes: nodesByID) {
                WMPHarnessOutput.emit("CLICK \(where_) \(line)")
            }
            previous = output.overrides
            for command in output.hostCommands {
                WMPHarnessOutput.emit("CLICK \(where_) command=\(command.action) value=\(command.value?.string ?? "-")")
            }
            for diagnostic in output.diagnostics {
                WMPHarnessOutput.emit("CLICK \(where_) [\(diagnostic.code)] \(diagnostic.message)")
            }
            // The compatibility surface taken *after* driving the event: a member is only demanded
            // once the handler that reaches it has run.
            if probe.wantsCallTrace {
                let unrecognised = Set(output.calls.filter { !$0.recognised }.map(\.path)).sorted()
                WMPHarnessOutput.emit("CLICK \(where_) unrecognised=[\(unrecognised.joined(separator: ","))]")
            }
            if let rebuilt = try? await builder.build(viewID: viewID, requestedSize: probe.requestedSize,
                                                      overrides: output.overrides) {
                scene = rebuilt
                WMPHarnessOutput.emit("CLICK \(where_) after: \(rebuilt.commands.count) commands, "
                    + "\(rebuilt.metrics.unresolvedNodeCount) unresolved")
            }
        }
        return scene
    }

    private static func changeLines(from before: WMPSceneOverrides, to after: WMPSceneOverrides,
                                    nodes: [Int: WMPNode]) -> [String] {
        var changes: [String] = []
        for (address, value) in after.geometry.sorted(by: { addressOrder($0.key, $1.key) })
        where before.geometry[address] != value {
            changes.append("\(name(address, nodes))=\(WMPNumber.format(value))")
        }
        for (address, value) in after.properties.sorted(by: { addressOrder($0.key, $1.key) })
        where before.properties[address] != value {
            changes.append("\(name(address, nodes))=\(condense(value.string ?? "null"))")
        }
        guard !changes.isEmpty else { return ["changed=[]"] }
        return ["changed=[\(changes.joined(separator: " "))]"]
    }

    private static func addressOrder(_ lhs: WMPScenePropertyAddress, _ rhs: WMPScenePropertyAddress) -> Bool {
        lhs.stableID == rhs.stableID ? lhs.property < rhs.property : lhs.stableID < rhs.stableID
    }

    private static func name(_ address: WMPScenePropertyAddress, _ nodes: [Int: WMPNode]) -> String {
        "\(nodes[address.stableID]?.xmlID ?? "node\(address.stableID)").\(address.property)"
    }

    // MARK: Shared

    private static func condense(_ value: String) -> String {
        let flat = value.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count <= 80 ? flat : String(flat.prefix(77)) + "…"
    }

    private static let supportedTags: Set<String> = [
        "theme", "view", "subview", "text", "image", "button", "buttongroup", "buttonelement",
        "slider", "volumeslider", "seekslider", "balanceslider", "playlist", "dropdownplaylist",
        "playelement", "pausebutton", "stopelement", "prevelement", "nextelement", "rewbutton",
        "rewelement", "ffwdbutton", "ffwdelement", "returnbutton", "shufflebutton",
        "equalizersettings", "popup", "wmpeffects", "video", "wmpvideo", "player", "network", "script"
    ]

    private static func supportsMember(_ path: String) -> Bool {
        let parts = path.lowercased().split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return false }
        let object: String, member: String
        switch parts[0] {
        case "player" where parts.count >= 3:
            switch parts[1] {
            case "controls": object = "controls"; member = parts[2]
            case "settings": object = "settings"; member = parts[2]
            case "currentmedia": object = "media"; member = parts[2]
            case "currentplaylist": object = "playlist"; member = parts[2]
            case "network": object = "network"; member = parts[2]
            default: object = "player"; member = parts[1]
            }
        case "metadata": object = "metadata"; member = parts[1]
        case "theme": object = "theme"; member = parts[1]
        case "view": object = "view"; member = parts[1]
        case "eq": object = "eq"; member = parts[1]
        case "vis": object = "vis"; member = parts[1]
        case "ipl", "ddpl": object = "playlist"; member = parts[1]
        default:
            object = parts[0]; member = parts[1]
            if WMPJScriptCompatibility.supports(object: "element", member: member) { return true }
        }
        return WMPJScriptCompatibility.supports(object: object, member: member)
    }
}
