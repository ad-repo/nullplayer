import Foundation
import XCTest
@testable import NullPlayer

/// **W170 — `openstatechange` rode the play state, so pausing told every skin a media had opened.**
///
/// Reported live as *"pressing pause does not pause the stream"*, then *"stop does not stop"*, both
/// against `Plus! HueShifter` with a Plex track playing. The skin's `OnOpenStateChange` is a switch
/// whose `osMediaOpen` arm ends in `player.controls.play()`, so the spurious edge restarted
/// playback 16 ms after every pause — and after a stop the re-play found the player stopped and
/// reloaded the track from zero:
///
/// ```
/// 16:32:56.431  StreamingAudioPlayer: State changed from playing to paused
/// 16:32:56.455  play(): Starting streaming playback via AudioStreaming (state: paused)
/// ```
///
/// **109 of the 180 installed archives author `OpenState_onchange`** and three answer it by playing
/// (`Plus! HueShifter`, `Plus! Plasma Ball`, `Plus! SlimLine`), so the wrong edge reached the whole
/// corpus and three skins turned it into a dead transport.
///
/// No headless probe could see it: a sweep seeds one host snapshot and never transitions, so the
/// edge that raises these two events is never computed — W73's class, and the reason this rule is
/// extracted as `stateEdgeEvents` rather than left inline in `refreshHostState`.
final class WMPHostEventEdgeTests: XCTestCase {

    private func snapshot(_ state: WMPHostSnapshot.State, open: Int = 3) -> WMPHostSnapshot {
        var snapshot = WMPHostSnapshot()
        snapshot.state = state
        snapshot.playlistCount = open
        return snapshot
    }

    /// The defect, in the two gestures that reported it.
    func testPausingAndStoppingRaiseThePlayStateEdgeAndNotTheOpenStateOne() {
        let playing = snapshot(.playing)
        XCTAssertEqual(WMPMainWindowController.stateEdgeEvents(previous: playing,
                                                               current: snapshot(.paused)),
                       ["playstatechange"],
                       "a pause changes the play state and nothing about what is open")
        XCTAssertEqual(WMPMainWindowController.stateEdgeEvents(previous: playing,
                                                               current: snapshot(.stopped)),
                       ["playstatechange"],
                       "a stop leaves the same media open — HueShifter reloaded the track from zero")
        XCTAssertEqual(WMPMainWindowController.stateEdgeEvents(previous: snapshot(.paused),
                                                               current: playing),
                       ["playstatechange"],
                       "and resuming is the same edge in the other direction")
    }

    /// The other half: the event still has to be raised for its own quantity, or 109 archives'
    /// handler never runs at all.
    func testOpeningAndClosingMediaRaiseTheOpenStateEdge() {
        XCTAssertEqual(WMPMainWindowController.stateEdgeEvents(previous: nil, current: snapshot(.stopped)),
                       ["playstatechange", "openstatechange"],
                       "the first snapshot with something open is a media that opened")
        XCTAssertEqual(WMPMainWindowController.stateEdgeEvents(previous: snapshot(.playing, open: 0),
                                                               current: snapshot(.playing)),
                       ["openstatechange"],
                       "a queue that gains its first item opened a media without touching play state")
        XCTAssertEqual(WMPMainWindowController.stateEdgeEvents(previous: snapshot(.stopped),
                                                               current: snapshot(.stopped, open: 0)),
                       ["openstatechange"],
                       "and emptying the queue closes it")
        XCTAssertTrue(WMPMainWindowController.stateEdgeEvents(previous: snapshot(.playing),
                                                             current: snapshot(.playing))
                        .isEmpty,
                      "an unchanged snapshot is not an edge")
    }

    /// The value the event carries and the property a handler reads must agree, because
    /// `OnOpenStateChange` branches on one of them — HueShifter reads `player.OpenState`, and
    /// `arguments(for:)` hands the same number to a handler that reads `NewState` instead.
    func testTheOpenStateEdgeAgreesWithTheValueTheEventCarries() {
        for open in [0, 1, 4] {
            let snapshot = snapshot(.playing, open: open)
            let argument = WMPMainWindowController.arguments(for: "openstatechange", snapshot)["NewState"]
            XCTAssertEqual(argument, .number(Double(WMPMainWindowController.openState(snapshot))),
                           "the edge and the argument are one derivation, at playlistCount \(open)")
        }
        XCTAssertEqual(WMPMainWindowController.openState(nil), WMPScriptConstants.osUndefined,
                       "before anything is open")
    }
}
