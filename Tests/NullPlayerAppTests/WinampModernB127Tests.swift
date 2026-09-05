import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B127 — a layout whose own script computes `minimum_w`/`minimum_h` beats the protective probe.
///
/// Reported 2026-09-05 against **cPro2 Dark Aluminum** with the author's reference render alongside:
/// dragged down to the small player, Winamp shows titlebar + info band + transport and nothing else,
/// while ours stopped with the SUI tab strip and the library still on screen. The window's floor was
/// **240x352** against the **240x106** the skin's own `two/scripts/layout.m` computes and writes
/// (`i_titlebar + i_info + i_playback + 8`) from `fullScreen(false)`.
///
/// The whole 246px came from the protective minimum (`WINAMP_MODERN_RENDER_MINIMUM=1`, which now
/// probes both axes and names the culprit's frame and ancestry):
///
///     MINIMUM main/normal hbelow=351 declared=240x106 protective=240x352
///       culprit group#PlaylistPro.topbar frame=(36,306,196,19) parentFrame=(36,306,196,18)
///
/// The probe resolves a *hypothetical* canvas without telling the scripts about it, so it measures a
/// scene the skin would never draw: `xui/PlaylistPro/_v2/PlaylistPro.m` answers its own `onResize`
/// with `if (h < 102 …) topbar.hide()`, and with the 19px search bar left standing it overhung its
/// pane by one pixel and pinned the whole player three times taller than its author's floor.
///
/// So the rule is: a skin that **writes** its floor at runtime has stated what the probe can only
/// infer, and the probe stands down — per axis, and only for the axis it wrote. Measured across the
/// installed corpus (69 skins, 2026-09-05) exactly two layouts write one at all: this player, and
/// Ebonite's `sc.alphaframe/scdef`, whose written 250x250 already equals its protective 250x250.
final class WinampModernB127Tests: XCTestCase {

    /// The shape the report is made of: a child that overhangs a non-clipping parent as the canvas
    /// shrinks, so the probe raises the floor well above what the layout declares.
    private static let overflowsOntoItsSiblings = """
    <layout id="normal" w="300" h="300" default_w="300" default_h="300" minimum_w="50" minimum_h="20">
      <layer id="panel" x="0" y="0" w="-100" h="-100" relatw="1" relath="1">
        <text id="inner" text="x" x="100" y="100" w="100" h="100"/>
      </layer>
    </layout>
    """

    func testTheProbeRaisesTheFloorWithoutAScriptSaying() throws {
        let renderer = try makeRenderer(layout: Self.overflowsOntoItsSiblings)
        XCTAssertGreaterThan(renderer.layoutMinimumSize.height, 20,
                             "nothing has said otherwise, so the probe's floor stands")
        XCTAssertGreaterThan(renderer.layoutMinimumSize.width, 50)
    }

    /// cPro2's case: the layout's script has written `minimum_h`, so the height it wrote is the
    /// floor — even though the probe would have raised it.
    func testAScriptWrittenMinimumStandsAgainstTheProbe() throws {
        let renderer = try makeRenderer(layout: Self.overflowsOntoItsSiblings)
        let raised = renderer.layoutMinimumSize
        renderer.layoutForTesting.noteScriptAuthoredMinimum("minimum_h")
        XCTAssertEqual(renderer.layoutMinimumSize.height, 20, "the value the skin wrote")
        XCTAssertEqual(renderer.layoutMinimumSize.width, raised.width,
                       "the other axis is untouched — a script speaks only for the axis it wrote")
    }

    /// The declared value alone is not a statement: an XML `minimum_h` is exactly the number written
    /// for Winamp, where a group clips its children, and it is what the probe exists to correct.
    func testTheXMLValueAloneDoesNotStandDown() throws {
        let renderer = try makeRenderer(layout: Self.overflowsOntoItsSiblings)
        XCTAssertTrue(renderer.layoutForTesting.scriptAuthoredMinimumAxes.isEmpty)
        XCTAssertGreaterThan(renderer.layoutMinimumSize.height,
                             renderer.declaredMinimumSize.height)
    }

    /// The window reads its `contentMinSize` from here, so the stand-down has to reach that too.
    func testTheWindowsResizeLimitFollows() throws {
        let renderer = try makeRenderer(layout: Self.overflowsOntoItsSiblings)
        renderer.layoutForTesting.noteScriptAuthoredMinimum("minimum_h")
        XCTAssertEqual(renderer.userResizeLimits.minimum.height, 20)
    }

    // MARK: - Fixtures

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB127Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // A unique archive name gives each fixture its own configuration namespace.
        let url = directory.appendingPathComponent("B127-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private final class TestHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

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
