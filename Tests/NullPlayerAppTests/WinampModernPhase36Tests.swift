import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 36 (backlog B2) — `dblclickaction=` / `rightclickaction=`.
///
/// Wasabi puts three independent commands on one object: `action=` on a click, `dblclickaction=` on
/// the second click, `rightclickaction=` on the right button. Only the first was read, so across the
/// 17 measured skins 62 declarations were inert — `TRACKINFO` (6 skins), `TRACKMENU` (5) and the
/// `SWITCH;<layout>` that takes a titlebar to winshade (mmd3, multipass, winampmodern566, ZDL,
/// Overdrive_2). Two halves had to be fixed together: the object had to become **reachable** by the
/// hit test (a `<text>` carrying only `dblclickaction` is none of the interactive types and has no
/// `action=`), and the attribute had to be **decoded**, including the `ACTION;PARAM` spelling that
/// 45 of the 62 uses are written in.
final class WinampModernPhase36Tests: XCTestCase {
    // MARK: - Decoding

    func testSemicolonTailIsTheParameter() {
        let resolved = WasabiClickAction.split(action: "SWITCH;shade", parameter: nil)
        XCTAssertEqual(resolved.action, "SWITCH")
        XCTAssertEqual(resolved.parameter, "shade")
    }

    func testActionWithoutATailKeepsItsSiblingParameter() {
        let resolved = WasabiClickAction.split(action: "WA5:Prefs", parameter: "42")
        XCTAssertEqual(resolved.action, "WA5:Prefs")
        XCTAssertEqual(resolved.parameter, "42")
    }

    func testExplicitParameterWinsOverATail() {
        XCTAssertEqual(WasabiClickAction.split(action: "SWITCH;shade", parameter: "normal").parameter,
                       "normal", "a declared param= is what Wasabi passes")
    }

    func testOnlyTheFirstSemicolonSeparates() {
        // winampmodern566: `action="SWITCHTO;optionsgroup.notifications;subpage"`.
        let resolved = WasabiClickAction.split(action: "SWITCHTO;group;subpage", parameter: nil)
        XCTAssertEqual(resolved.action, "SWITCHTO")
        XCTAssertEqual(resolved.parameter, "group;subpage")
    }

    func testResolveReadsBothGesturesAndIgnoresABlankOne() throws {
        let renderer = try makeRenderer(xml: Self.skin(body: """
            <text id="song" display="SONGNAME" x="0" y="0" w="60" h="12" ghost="0"
                  dblClickAction="TRACKINFO" rightclickaction="TRACKMENU"/>
            <layer id="mousetrap" x="0" y="20" w="60" h="12" rectrgn="1" dblClickAction="  "/>
            """))
        let song = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "song").first)
        let trap = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "mousetrap").first)

        // The attribute is written `dblClickAction` in the markup; the graph lowercases every key.
        XCTAssertEqual(WasabiClickAction.resolve(song, gesture: .double)?.action, "TRACKINFO")
        XCTAssertEqual(WasabiClickAction.resolve(song, gesture: .right)?.action, "TRACKMENU")
        XCTAssertNil(WasabiClickAction.resolve(song, gesture: .right)?.parameter)
        XCTAssertNil(WasabiClickAction.resolve(trap, gesture: .double))
        XCTAssertNil(WasabiClickAction.resolve(trap, gesture: .right))
    }

    // MARK: - Reachability

    func testTextCarryingOnlyADoubleClickActionIsHitTested() throws {
        let renderer = try makeRenderer(xml: Self.skin(body: """
            <text id="song" display="SONGNAME" x="0" y="0" w="60" h="12" ghost="0"
                  dblclickaction="TRACKINFO"/>
            """))
        XCTAssertEqual(renderer.object(at: CGPoint(x: 10, y: 6))?.xmlID, "song",
                       "a song title's only command is on its second click; it has to be reachable")
    }

    func testTextCarryingOnlyARightClickActionIsHitTested() throws {
        let renderer = try makeRenderer(xml: Self.skin(body: """
            <text id="song" display="SONGNAME" x="0" y="0" w="60" h="12" ghost="0"
                  rightclickaction="TRACKMENU"/>
            """))
        XCTAssertEqual(renderer.object(at: CGPoint(x: 10, y: 6))?.xmlID, "song")
    }

    func testAPlainTextIsStillNotInteractive() throws {
        let renderer = try makeRenderer(xml: Self.skin(body: """
            <text id="song" display="SONGNAME" x="0" y="0" w="60" h="12" ghost="0"/>
            """))
        XCTAssertNil(renderer.object(at: CGPoint(x: 10, y: 6)),
                     "a readout with no command must not start swallowing clicks")
    }

    func testAGhostedClickActionStillPassesTheClickThrough() throws {
        // multipass's playlist ticker is `ghost="1"` *and* carries `dblclickaction` — Wasabi's ghost
        // is "the mouse is not mine", and it outranks the attribute.
        let renderer = try makeRenderer(xml: Self.skin(body: """
            <text id="song" display="SONGNAME" x="0" y="0" w="60" h="12" ghost="1"
                  dblclickaction="TRACKINFO"/>
            """))
        XCTAssertNil(renderer.object(at: CGPoint(x: 10, y: 6)))
    }

    // MARK: - Fixtures

    private static func skin(body: String) -> String {
        """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="80" h="40">
              \(body)
            </layout>
          </container>
        </WasabiXML>
        """
    }

    private func makeRenderer(xml: String) throws -> WasabiSceneRenderer {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase36Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase36-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        return url
    }

    private final class Host: WinampModernHost {
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
