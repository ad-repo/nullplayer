import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W255 — `wmpenabled:player.controls.seek` was answered "no", and the slider vanished.**
///
/// Reported live 2026-09-22 as *"there are no seek controls for the movie"*, and it was never about
/// the movie: `Revert` had no seek bar for music either, and had not since the engine existed.
///
/// `IWMPControls` carries **both** `currentPosition` and `seek`, so the same slider is authored
/// either way. The `wmpenabled:` table answered only the first and sent everything else to
/// `default: return nil`, which `unansweredValue` turns into `.bool(false)` — the right default for
/// a control this engine cannot drive and exactly wrong for one it can.
///
/// It then cost the control twice, because `Revert`'s slider mirrors its own gate:
///
/// ```xml
/// <slider id="seek" enabled="wmpenabled:player.controls.seek" visible="wmpprop:seek.enabled" … />
/// ```
///
/// `visible="wmpprop:seek.enabled"` names an element in the skin's own graph — that element being
/// the slider itself — so `WMPSceneBuilder.mirroredVisibility` read the false `enabled` override and
/// **deleted the node**. Not a greyed-out seek bar: no seek bar at all. `vwPlayer` built 12 nodes
/// with no `slider` among them, and 13 afterwards.
///
/// **Reach over 185 archives**, decoding script text the way `WMPTextDecoder` does:
/// `player.controls.seek` 2 uses / 2 skins — and those two are `Revert` and `Revert (1)`, the same
/// markup, so **one skin**. `fastforward`/`fastreverse` are 3 uses / 3 skins each and were
/// unanswered for the same reason. The rest of the table was already answered: `pause` 151/125,
/// `play` 36/30, `stop` 21/17, `previous`/`next` 11/10, `currentposition` 6/6.
final class WMPSeekAvailabilityTests: XCTestCase {

    private func snapshot(duration: TimeInterval, tracks: Int = 3) -> WMPHostSnapshot {
        var snapshot = WMPHostSnapshot()
        snapshot.state = .playing
        snapshot.playlistCount = tracks
        snapshot.duration = duration
        snapshot.currentTime = min(63, duration)
        return snapshot
    }

    /// Both of WMP's names for the same capability answer the same thing, and the scan pair rides
    /// the quantity it actually depends on.
    func testSeekAndScanAreAnsweredFromTheHostRatherThanDefaultingToDisabled() async throws {
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="v" width="256" height="130">
              <SLIDER id="seek" left="7" top="86" width="242" height="13"
                      enabled="wmpenabled:player.controls.seek"/>
              <SLIDER id="pos" left="7" top="100" width="242" height="13"
                      enabled="wmpenabled:player.controls.currentPosition"/>
              <BUTTON id="ff" left="7" top="20" width="16" height="16"
                      enabled="wmpenabled:player.controls.fastForward"/>
              <BUTTON id="rw" left="30" top="20" width="16" height="16"
                      enabled="wmpenabled:player.controls.fastReverse"/>
            </VIEW></THEME>
            """.utf8))
        ]))
        func address(_ id: String) throws -> WMPScenePropertyAddress {
            .init(stableID: try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID),
                  property: "enabled")
        }
        var registry = WMPObservablePropertyRegistry(graph: skin.graph)

        // A media with a length: every one of the four is available, and `seek` must agree with
        // `currentPosition` because they are two spellings of one capability.
        var playing: [WMPScenePropertyAddress: WMPJSONValue] = [:]
        for change in registry.changes(for: snapshot(duration: 213)) { playing[change.address] = change.value }
        XCTAssertEqual(playing[try address("seek")], .bool(true),
                       "the name Revert authors, and the whole of W255")
        XCTAssertEqual(playing[try address("pos")], .bool(true), "the name that already worked")
        XCTAssertEqual(playing[try address("ff")], .bool(true))
        XCTAssertEqual(playing[try address("rw")], .bool(true))

        // A zero-length media is still false, so the fix is an answer rather than a constant. A
        // radio stream is the live case: it plays, and there is nothing to seek within.
        var stream: [WMPScenePropertyAddress: WMPJSONValue] = [:]
        for change in registry.changes(for: snapshot(duration: 0)) { stream[change.address] = change.value }
        XCTAssertEqual(stream[try address("seek")], .bool(false), "a zero-length media is not seekable")
        XCTAssertEqual(stream[try address("pos")], .bool(false))
        XCTAssertEqual(stream[try address("ff")], .bool(false))
        XCTAssertEqual(stream[try address("rw")], .bool(false))
    }

    /// The half of the defect that made it invisible rather than grey: a control that mirrors
    /// `visible` onto its own `enabled` is **deleted** when the gate answers false, so an
    /// unanswered `wmpenabled:` path is a content defect and not only a cosmetic one. This is
    /// `Revert`'s own markup, reduced to the two attributes that carry it.
    func testASliderMirroringItsOwnEnabledSurvivesTheBuildOnceSeekIsAnswered() async throws {
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="vwPlayer" width="256" height="130">
              <SLIDER id="seek" left="7" top="86" width="242" height="13"
                      enabled="wmpenabled:player.controls.seek" visible="wmpprop:seek.enabled"/>
            </VIEW></THEME>
            """.utf8))
        ]))
        var registry = WMPObservablePropertyRegistry(graph: skin.graph)
        var overrides = WMPSceneOverrides.empty
        for change in registry.changes(for: snapshot(duration: 213)) {
            overrides.properties[change.address] = change.value
        }
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "vwPlayer", overrides: overrides)

        XCTAssertTrue(scene.widgets.contains { $0.nodeID == "seek" },
                      "the node was deleted outright before W255 — 12 nodes with no slider in them")
    }
}
