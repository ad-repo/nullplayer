import Foundation
import XCTest
@testable import NullPlayer

/// **W245: a view that reported its stats and then had its PNG write refused printed a second
/// `RENDER-DUMP` line, and the sweep read one view's two lines as a lost log block.**
///
/// `wmp_render_sweep.sh` and `wmp_skin_census.sh` both check a per-skin block against its own
/// `LOAD` line: `views=` declares how many views must report, and a block that reports fewer has
/// lost lines to an interleaved write. The arithmetic was counting `RENDER-DUMP ` lines, and a view
/// whose canvas is `0x0` emits two of them — the stats line, then `RENDER-DUMP <view> FAILED
/// [WMP0035] Canvas and backing scale must be positive.` when `WMPRenderer` refuses the empty
/// canvas. `XBOX.wmz` declares `views=5` and printed 6.
///
/// **What it cost was the comparison, not the capture.** `compare` leaves a damaged skin's lines
/// out of the invariants diff, so every archive holding one of these views went silently
/// unverified: measured 2026-09-20 over the installed corpus, **48 of 184 archives**, from **76
/// such `0x0` views** — the windowless class (`controlView`, `previewView`, `mediaSwitcherView`,
/// `versionView`) that W6 admits by contract and the renderer correctly refuses. The two captures
/// that found it flagged an *identical* set both times, which is what said the cause was arithmetic
/// rather than the non-deterministic interleaving the check was written for.
///
/// Both halves are pinned here, because either one alone still leaves the class open:
///
/// * **`RENDER-DUMP` is one line per view per outcome** — its stats, or `FAILED` when the scene
///   never built at all. A refused write is a `PNG` outcome and says so.
/// * **The detector counts distinct view ids**, the way the census has since W32, so the next pair
///   of lines about one view cannot recreate the class. It must still catch a genuinely short
///   block, which is the third case below.
///
/// Measured after the fix over the same 184 archives: damaged **48 → 0**, and the full invariants
/// diff against a baseline worktree is exactly 76 lines changing prefix, same view and same reason
/// on both sides, with all 553 PNGs byte-identical. Three consecutive captures came back
/// byte-identical with zero damaged, so the interleaving the first arm of the detector looks for is
/// unfired here rather than disproven — see `harness-history.md` § *The residue is a size fallback*.
final class WMPDumpLineAccountingTests: XCTestCase {

    // MARK: The emitter

    /// One view with a canvas and one without, which is the shape of every archive in the 48:
    /// `pharaoh` authors its windowless view as an explicit `0x0` and the other 47 reach the same
    /// size by having nothing to place.
    private func fixture() throws -> URL {
        let xml = """
        <THEME>
          <VIEW id="ghost" width="0" height="0"/>
          <VIEW id="main" width="8" height="6" backgroundColor="#0000FF"/>
        </THEME>
        """
        return try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))
        ])
    }

    /// `HarnessOutput` writes to `STDOUT_FILENO` unbuffered and whole — that is the point of it —
    /// so reading it back means owning the descriptor for the duration. The capture is small (a
    /// dozen lines) and stays well inside the pipe buffer, so the write side cannot block while
    /// nothing is draining it.
    private func captureHarnessOutput(_ body: () async throws -> Void) async throws -> [String] {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        let saved = dup(STDOUT_FILENO)
        fflush(stdout)
        XCTAssertNotEqual(dup2(fds[1], STDOUT_FILENO), -1)
        // Restore *before* draining. `read` blocks while any write end is open, and the redirected
        // `STDOUT_FILENO` is one: putting this in a `defer` that runs after the drain hung the test
        // outright rather than failing it.
        func restore() {
            fflush(stdout)
            dup2(saved, STDOUT_FILENO)
            close(saved)
            close(fds[1])
        }
        do { try await body() } catch {
            restore(); close(fds[0])
            throw error
        }
        restore()
        var data = Data()
        while true {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let read = read(fds[0], &buffer, buffer.count)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        close(fds[0])
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func testARefusedPNGWriteIsAPNGOutcomeAndNotASecondRenderDumpLine() async throws {
        let archive = try fixture()
        let dump = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "wmp.accounting.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let lines = try await captureHarnessOutput {
            try await WMPHarness.measure(archive: archive, dump: dump,
                                         probe: WMPProbe(env: [:]), defaults: defaults)
        }

        let load = try XCTUnwrap(lines.first { $0.hasPrefix("LOAD ") })
        XCTAssertTrue(load.contains("views=2"), load)

        // The whole of the arithmetic the sweep does, asserted the way the sweep does it.
        let dumps = lines.filter { $0.hasPrefix("RENDER-DUMP ") }
        XCTAssertEqual(dumps.count, 2, "\(dumps)")
        XCTAssertEqual(dumps.filter { $0.contains(" FAILED ") }, [], "a built view reports stats")
        XCTAssertEqual(Set(dumps.map { $0.split(separator: " ")[1] }), ["ghost:", "main:"])

        // The refusal is still reported — losing it would trade a miscount for a blind spot.
        let refusals = lines.filter { $0.hasPrefix("PNG ") && $0.contains(" FAILED ") }
        XCTAssertEqual(refusals.count, 1, "\(lines)")
        let refusal = try XCTUnwrap(refusals.first)
        XCTAssertTrue(refusal.hasPrefix("PNG ghost FAILED "), refusal)
        XCTAssertTrue(refusal.contains("[\(WMPDiagnosticCode.renderFailed.rawValue)]"), refusal)

        // And the view that does have a canvas still writes its image and says which file.
        XCTAssertEqual(lines.filter { $0.hasPrefix("PNG main: ") }.count, 1, "\(lines)")
    }

    // MARK: The detector

    /// The sweep's damaged-log check, lifted out of the script and run over a fixture log, so the
    /// rule is pinned where a Swift change to the line grammar will see it. Reading it out of the
    /// file rather than restating it here is deliberate: a copy would pass while the script the
    /// sweep actually runs regressed.
    private func damagedSkins(in log: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = root.appendingPathComponent("scripts/wmp_render_sweep.sh")
        let source = try String(contentsOf: script, encoding: .utf8)
        let opener = "python3 - \"$out/raw.txt\" > \"$out/damaged.txt\" <<'PYDAMAGED'\n"
        guard let start = source.range(of: opener),
              let end = source.range(of: "\nPYDAMAGED", range: start.upperBound..<source.endIndex)
        else { throw XCTSkip("wmp_render_sweep.sh no longer embeds a PYDAMAGED block.") }
        let detector = String(source[start.upperBound..<end.lowerBound])

        let directory = try WMPSkinTestSupport.temporaryDirectory()
        let raw = directory.appendingPathComponent("raw.txt")
        let program = directory.appendingPathComponent("detector.py")
        try log.write(to: raw, atomically: true, encoding: .utf8)
        try detector.write(to: program, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", program.path, raw.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// `views=5` against six `RENDER-DUMP ` lines for five view ids — `XBOX.wmz`'s own block,
    /// reduced. Under the old emitter this was the shape of all 48.
    func testAViewReportingTwiceIsNotALostLogBlock() throws {
        let log = """
        SKIN XBOX.wmz
        LOAD definition=xbox.wms encoding=utf8 entries=146 bytes=1653020 views=5 nodes=163 scripts=3 resources=197
        RENDER-DUMP view-2: 0x0, 1 nodes, 0 commands, 0 hits, 0 widgets, 0 unresolved
        RENDER-DUMP view-2 FAILED [WMP0035] Canvas and backing scale must be positive.
        RENDER-DUMP mainBox: 350x216, 29 nodes, 25 commands, 15 hits, 4 widgets, 1 unresolved
        RENDER-DUMP videoBox: 398x400, 29 nodes, 27 commands, 4 hits, 0 widgets, 1 unresolved
        RENDER-DUMP plBox: 438x316, 27 nodes, 26 commands, 5 hits, 1 widgets, 0 unresolved
        RENDER-DUMP contentBox: 398x316, 17 nodes, 14 commands, 4 hits, 0 widgets, 0 unresolved
        """
        XCTAssertEqual(try damagedSkins(in: log), [])
    }

    /// The same block as the emitter writes it today: five views, five lines, and the refusal on
    /// its own `PNG` line where it belongs.
    func testTheCurrentLineGrammarLeavesTheBlockWhole() throws {
        let log = """
        SKIN XBOX.wmz
        LOAD definition=xbox.wms encoding=utf8 entries=146 bytes=1653020 views=5 nodes=163 scripts=3 resources=197
        RENDER-DUMP view-2: 0x0, 1 nodes, 0 commands, 0 hits, 0 widgets, 0 unresolved
        PNG view-2 FAILED [WMP0035] Canvas and backing scale must be positive.
        RENDER-DUMP mainBox: 350x216, 29 nodes, 25 commands, 15 hits, 4 widgets, 1 unresolved
        PNG mainBox: mainBox@1x.png
        RENDER-DUMP videoBox: 398x400, 29 nodes, 27 commands, 4 hits, 0 widgets, 1 unresolved
        PNG videoBox: videoBox@1x.png
        RENDER-DUMP plBox: 438x316, 27 nodes, 26 commands, 5 hits, 1 widgets, 0 unresolved
        PNG plBox: plBox@1x.png
        RENDER-DUMP contentBox: 398x316, 17 nodes, 14 commands, 4 hits, 0 widgets, 0 unresolved
        PNG contentBox: contentBox@1x.png
        """
        XCTAssertEqual(try damagedSkins(in: log), [])
    }

    /// The check must still do the job it exists for. This is the block above with one view's line
    /// taken out, which is what an interleaved write leaves behind.
    func testABlockThatLostAViewIsStillReportedAsDamaged() throws {
        let log = """
        SKIN XBOX.wmz
        LOAD definition=xbox.wms encoding=utf8 entries=146 bytes=1653020 views=5 nodes=163 scripts=3 resources=197
        RENDER-DUMP view-2: 0x0, 1 nodes, 0 commands, 0 hits, 0 widgets, 0 unresolved
        PNG view-2 FAILED [WMP0035] Canvas and backing scale must be positive.
        RENDER-DUMP mainBox: 350x216, 29 nodes, 25 commands, 15 hits, 4 widgets, 1 unresolved
        RENDER-DUMP videoBox: 398x400, 29 nodes, 27 commands, 4 hits, 0 widgets, 1 unresolved
        RENDER-DUMP contentBox: 398x316, 17 nodes, 14 commands, 4 hits, 0 widgets, 0 unresolved
        """
        XCTAssertEqual(try damagedSkins(in: log), ["XBOX.wmz"])
    }

    /// A rejected archive carries no `LOAD` line and is not a block with rows missing — the
    /// distinction the `views=` arm depends on to stay quiet about the skins that never loaded.
    func testARejectedArchiveIsNotADamagedBlock() throws {
        let log = """
        SKIN broken.wmz
        SKIN broken.wmz FAILED [WMP0015] No skin definition in the archive.
        """
        XCTAssertEqual(try damagedSkins(in: log), [])
    }
}
