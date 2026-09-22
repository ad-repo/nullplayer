import Foundation
import XCTest
@testable import NullPlayer

/// **W41 — `sourceURL` resolved, and the string it resolved to was one no skin could read.**
///
/// The member itself has answered since W115; what was left under the row was the *value*. Every
/// consumer in the corpus classifies this string rather than opening it, and every classifier is
/// written against Windows syntax — `cd:` for a disc, a backslash for a file, anything else for the
/// network. A macOS `file:///Users/…` matches none of them, so nine archives lit their **network**
/// lamp for every local track and two put a buffering readout behind it.
///
/// Re-measured 2026-09-22 over 184 archives with the `WMPTextDecoder` decode (encoding breakdown
/// 158 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM, the harness's own calibration):
/// **19 uses across 14 archives**, not the "4 skins" the row carried. The classifier split is
/// 9 archives on the local/CD/network lamp, 1 on `indexOf('http')` (`Cablemusic`), 1 on a
/// `player.currentPlaylist.item(0).sourceURL` prefix test (`Compact`), and 1 filtering a query by
/// `://` (`digitaldj`).
///
/// The rule the row leaves behind: **the conversion lives at the host boundary**, the same seam
/// that states `crossFadeWindow` in milliseconds because WMP does.
final class WMPMediaSourceURLTests: XCTestCase {

    private func load(wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))
        ]))
    }

    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPMediaSourceURLTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func stableID(_ skin: WMPLoadedSkin, _ id: String) throws -> Int {
        try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
    }

    /// The conversion itself. A file is stated as a Windows player would state it — which is what
    /// the corpus's `search(/\\/)` and `search(/:\\/)` are asking — and a remote media is already
    /// the string WMP would report, so it is passed through untouched.
    @MainActor func testALocalFileIsSpelledTheWayTheCorpusClassifiesIt() {
        let local = WMPAudioEngineHost.sourceURLSpelling(
            URL(fileURLWithPath: "/Users/listener/Music/Back in Black.mp3"))
        XCTAssertEqual(local, #"C:\Users\listener\Music\Back in Black.mp3"#)
        // The eight archives that ask this question, and `Kids`, which wants the `:\` as well.
        XCTAssertNotNil(local.range(of: #"\"#), "the local branch of nine skins' classifier")
        XCTAssertNotNil(local.range(of: #":\"#), "`Kids` tests for the drive colon too")
        XCTAssertNil(local.range(of: "://"), "`digitaldj` drops any item whose URL contains `://`")
        XCTAssertNil(local.range(of: "http"), "`Cablemusic` reads a file as a file")
    }

    @MainActor func testARemoteMediaKeepsTheURLWMPWouldHaveReported() {
        XCTAssertEqual(WMPAudioEngineHost.sourceURLSpelling(URL(string: "http://example.test/s.mp3")),
                       "http://example.test/s.mp3")
        XCTAssertEqual(WMPAudioEngineHost.sourceURLSpelling(URL(string: "mms://example.test/live")),
                       "mms://example.test/live")
        // Nothing playing is the empty string, not a spelling of nothing.
        XCTAssertEqual(WMPAudioEngineHost.sourceURLSpelling(nil), "")
    }

    /// **A playlist item's `sourceURL` answered the item's *title*.** `Compact` asks whether item 0
    /// starts with `wmpdvd:` and `digitaldj`'s query filter drops any item whose URL contains
    /// `://` or ends `.asx`, so a track name stood in for a URL in both.
    func testAPlaylistItemAnswersItsURLRatherThanItsTitle() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <TEXT id="out" left="0" top="0" width="90" height="12" fontSize="10" value=""/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        var snapshot = WMPHostSnapshot()
        snapshot.playlistItems = [WMPPlaylistItemSnapshot(title: "Hells Bells", artist: "AC/DC",
                                                          duration: 312,
                                                          sourceURL: #"C:\Music\hells.mp3"#)]
        snapshot.playlistCount = 1

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 100, height: 100), snapshot: snapshot,
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [
                "out.value = player.currentPlaylist.item(0).sourceURL;"
            ]))
        XCTAssertTrue(output.diagnostics.isEmpty, "the handler runs to the end: \(output.diagnostics)")
        let value = output.overrides.properties[.init(stableID: try stableID(skin, "out"),
                                                      property: "value")]
        XCTAssertEqual(value, .string(#"C:\Music\hells.mp3"#))
        XCTAssertNotEqual(value, .string("Hells Bells"), "the title is `name`, never `sourceURL`")
    }

    /// The name half must keep answering the name — the two were one `case` and splitting them is
    /// where a swap would hide.
    func testAPlaylistItemStillAnswersItsName() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <TEXT id="out" left="0" top="0" width="90" height="12" fontSize="10" value=""/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        var snapshot = WMPHostSnapshot()
        snapshot.playlistItems = [WMPPlaylistItemSnapshot(title: "Hells Bells", artist: "AC/DC",
                                                          duration: 312,
                                                          sourceURL: #"C:\Music\hells.mp3"#)]
        snapshot.playlistCount = 1

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 100, height: 100), snapshot: snapshot,
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [
                "out.value = player.currentPlaylist.item(0).name;"
            ]))
        XCTAssertEqual(output.overrides.properties[.init(stableID: try stableID(skin, "out"),
                                                         property: "value")],
                       .string("Hells Bells"))
    }

    /// **The corpus's own classifier, run against both spellings.** This is the shape shipped by
    /// `Stealth`, `Thomas`, `elvis`, `Nautical`, `Plus! HueShifter`, `Television`, `activate` and
    /// `holiday_skin`; it is the whole reason the value's spelling is a defect rather than a
    /// cosmetic choice, so it is pinned as the skins wrote it.
    func testTheShippedLocalCDNetworkClassifierReachesItsLocalBranch() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <TEXT id="out" left="0" top="0" width="90" height="12" fontSize="10" value=""/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let classifier = """
        var strSourceURL = player.currentMedia.sourceURL;
        if (strSourceURL.search(/cd:/i) != -1) { out.value = 'cd'; }
        else if (strSourceURL.search(/\\\\/i) != -1) { out.value = 'local'; }
        else { out.value = 'net'; }
        """
        func branch(for sourceURL: String) async throws -> WMPJSONValue? {
            var snapshot = WMPHostSnapshot()
            snapshot.metadata = WMPMediaMetadata(title: "Hells Bells", sourceURL: sourceURL)
            let output = await runtime.transact(
                skin: skin, viewID: "main", size: WMPSize(width: 100, height: 100),
                snapshot: snapshot,
                event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [classifier]))
            XCTAssertTrue(output.diagnostics.isEmpty, "the handler runs: \(output.diagnostics)")
            return output.overrides.properties[.init(stableID: try stableID(skin, "out"),
                                                     property: "value")]
        }
        let local = await MainActor.run {
            WMPAudioEngineHost.sourceURLSpelling(URL(fileURLWithPath: "/Users/l/a.mp3"))
        }
        var reached = try await branch(for: local)
        XCTAssertEqual(reached, .string("local"),
                       "a local file lights LOCAL — it lit NET for every track before W41")
        reached = try await branch(for: "file:///Users/l/a.mp3")
        XCTAssertEqual(reached, .string("net"),
                       "and the spelling is the whole defect: the old value takes the net branch")
        reached = try await branch(for: "http://example.test/s.mp3")
        XCTAssertEqual(reached, .string("net"))
        reached = try await branch(for: "cd://drive/1")
        XCTAssertEqual(reached, .string("cd"))
    }
}
