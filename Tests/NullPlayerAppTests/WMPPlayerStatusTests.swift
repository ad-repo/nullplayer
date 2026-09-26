import Foundation
import XCTest
@testable import NullPlayer

/// **W162 — `player.status` was inert and empty, so 69 of the 180 archives painted a blank
/// readout.** Found while closing W161 on `Windows_XP_Media_Center_Edition`: that skin draws a
/// `STATUS:` label beside `<TEXT value="wmpprop:player.status">` and showed the label alone.
///
/// The wording is free to be WMP's own sentence because **not one of the corpus's 128 uses compares
/// it against a literal** — every one prints it, either straight into a readout or prepended to the
/// track name (`metadata.value = player.status; if (metadata.value != "") metadata.value += " - ";`,
/// the Alienware family's idiom). No handler can branch on it, so no handler can be broken by it.
///
/// The corpus render sweep over the change moved **14 images and nothing else**, every one of them a
/// readout that painted nothing now painting `Ready` in the skin's own font. (A fifteenth,
/// `Scooby-Doo_2/infoView`, differs run to run on its own `Math.random()` — see
/// `reference/harness/sweep-limits.md` § *A sweep has two nondeterministic outputs*.)
final class WMPPlayerStatusTests: XCTestCase {

    // MARK: - The sentence

    /// WMP says `Ready` before anything is open and `Stopped` once something is and is not running,
    /// which is the same split `isEnabled(.play)` already makes.
    func testTheStatusSentenceFollowsPlayStateAndWhetherAnythingIsOpen() {
        var snapshot = WMPHostSnapshot()
        XCTAssertEqual(snapshot.statusText, "Ready", "nothing open yet")

        snapshot.playlistCount = 3
        XCTAssertEqual(snapshot.statusText, "Stopped", "media is open and not running")

        snapshot.state = .playing
        XCTAssertEqual(snapshot.statusText, "Playing")

        snapshot.state = .paused
        XCTAssertEqual(snapshot.statusText, "Paused")
    }

    /// **There is deliberately no `Buffering (n%)` case.** WMP spells one, but `bufferingProgress`
    /// is 0-100 with 100 meaning *full* and nothing outside the harness ever writes it, so a
    /// `< 100` test would report every skin permanently buffering on its default `0`.
    func testABufferingProgressOfZeroDoesNotClaimTheSkinIsBuffering() {
        var snapshot = WMPHostSnapshot()
        snapshot.playlistCount = 1
        snapshot.state = .playing
        XCTAssertEqual(snapshot.bufferingProgress, 0, "the default nothing in the app overwrites")
        XCTAssertEqual(snapshot.statusText, "Playing")
    }

    // MARK: - The three places a skin can reach it

    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPPlayerStatusTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func snapshot(_ state: WMPHostSnapshot.State, tracks: Int = 3) -> WMPHostSnapshot {
        var snapshot = WMPHostSnapshot()
        snapshot.state = state
        snapshot.playlistCount = tracks
        return snapshot
    }

    /// The object-model member, which is what `metadata.value = player.status` reads — the corpus's
    /// single most common use, 35 of its 75 `status_onchange` sources being `updateMetadata()`.
    ///
    /// It must also resolve **`live` rather than `inert`**: a member the runtime answers has to
    /// leave the demand tally, or it is ranked as missing work while it works.
    func testTheObjectModelMemberAnswersTheSentenceAndResolvesLive() async throws {
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="200" height="60">
                <TEXT id="metadata" left="4" top="4" width="120" fontSize="8" value=""/>
            </VIEW></THEME>
            """.utf8))
        ]))
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 60),
            snapshot: snapshot(.playing),
            event: WMPJScriptEvent(name: "change", targetID: "metadata",
                                   handlers: ["metadata.value = player.status;"]))

        let address = WMPScenePropertyAddress(
            stableID: try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "metadata" }?.stableID),
            property: "value")
        XCTAssertEqual(output.overrides.properties[address], .string("Playing"))
        XCTAssertEqual(output.calls.first { $0.path == "player.status" }?.resolution, .live,
                       "an answered member must not stay in the demand tally")
    }

    /// **The binding is a separate resolution of the same path**, and the readout stays empty
    /// however live the member is unless the registry answers it too — which is exactly how this
    /// shipped blank: the member was inert *and* the path was absent here.
    func testTheWmppropBindingResolvesTheSamePath() async throws {
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="200" height="60">
                <TEXT id="status" left="4" top="4" width="120" fontSize="8"
                      value="wmpprop:player.status"/>
            </VIEW></THEME>
            """.utf8))
        ]))
        let address = WMPScenePropertyAddress(
            stableID: try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "status" }?.stableID),
            property: "value")

        var registry = WMPObservablePropertyRegistry(graph: skin.graph)
        let playing = registry.changes(for: snapshot(.playing))
        XCTAssertEqual(playing.first { $0.address == address }?.value.string, "Playing")

        // And it settles on a state change rather than sticking at whatever it opened on.
        let paused = registry.changes(for: snapshot(.paused))
        XCTAssertEqual(paused.first { $0.address == address }?.value.string, "Paused")
    }

    /// `status_onchange="OnStatusChangeTransport(status);"` is Corona's, and the argument has to
    /// agree with the property the same handler can read — an argument that disagreed would be
    /// worse than no argument at all.
    @MainActor
    func testTheStatusEventArgumentAgreesWithTheProperty() {
        for state in [WMPHostSnapshot.State.stopped, .playing, .paused] {
            let snapshot = snapshot(state)
            let arguments = WMPMainWindowController.arguments(for: "status_onchange", snapshot)
            XCTAssertEqual(arguments["status"]?.string, snapshot.statusText)
        }
    }
}
