import XCTest
@testable import NullPlayer

/// **A skin that commits a seek by reading its own slider back must read what the user left there.**
///
/// Reported against `Plus! Pulsar` as "the seek area does not work properly", with the observation
/// that made it findable: *"the volume is fine and has the same control shape"*. Both are diagonal
/// arcs driven by the same kind of position map, so geometry was never the difference. The markup
/// was: `volume` carries `value="wmpprop:player.settings.volume"`, so `performSlider` recognises a
/// bound transport action and commits it natively, in-process, the moment the pointer moves.
/// `seekMain` carries no `value` binding at all and commits through its own script —
/// `onmouseup="player.controls.currentPosition=seekMain.value;"` — while the same file authors
/// `<controls currentPosition_onchange="seekMain.value=player.controls.currentPosition;">`, which
/// the host raises on **every** `currentTime` change.
///
/// So a playback tick landing between the drag and the release wrote the live position into the
/// element the release was about to read, and the seek committed to where the track already was.
final class WMPSliderCommitTests: XCTestCase {
    private func pulsar() throws -> URL {
        let path = ("~/Library/Application Support/NullPlayer/WMPSkins/Plus! Pulsar.wmz" as NSString)
            .expandingTildeInPath
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path),
                          "installed WMP corpus not present")
        return URL(fileURLWithPath: path)
    }

    func testAPlaybackTickBetweenDragAndReleaseDoesNotEatTheSeek() async throws {
        let skin = try await WMPSkinLoader().load(from: try pulsar())
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data()))
        let store = WMPImageStore(provider: skin.archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "mainView")
        let seek = try XCTUnwrap(scene.hits.first { $0.nodeID == "seekMain" })
        var snapshot = WMPHostSnapshot()
        snapshot.duration = 213
        snapshot.currentTime = 63

        func raise(_ event: String, targetID: String? = nil, targetStableID: Int? = nil) async
            -> WMPScriptOutput {
            let handlers = WMPMainWindowController.handlers(in: skin, event: event,
                targetID: targetID, targetStableID: targetStableID, viewID: "mainView")
            return await runtime.transact(skin: skin, viewID: "mainView", size: scene.canvasSize,
                snapshot: snapshot,
                event: WMPJScriptEvent(name: event, targetID: targetID, handlers: handlers),
                geometry: scene.scriptGeometry)
        }

        _ = await raise("load")
        // The skin does author the write-back this test is about; if that ever stops being true the
        // test is measuring nothing.
        XCTAssertFalse(WMPMainWindowController.handlers(in: skin, event: "currentposition_onchange",
            targetID: nil, viewID: "mainView").isEmpty,
            "pulsar.wms authors <controls currentPosition_onchange=…>")

        // The drag, a playback tick, then the release — the order the app produces.
        await runtime.setWidgetValue(stableID: seek.stableID, value: 150, viewID: "mainView")
        _ = await raise("currentposition_onchange")
        // `onSliderRelease` re-asserts the user's value first, in the same task as the handlers.
        await runtime.setWidgetValue(stableID: seek.stableID, value: 150, viewID: "mainView")
        let released = await raise("mouseup", targetID: "seekMain", targetStableID: seek.stableID)

        let seeks = released.hostCommands.filter { $0.action == "seekSeconds" }
        XCTAssertEqual(seeks.count, 1, "the release commits exactly one seek")
        XCTAssertEqual(seeks.first?.value?.number ?? -1, 150, accuracy: 0.001,
                       "the seek must land where the user let go, not at the live position (63)")
    }

    /// The `max` the seek scales against is a `wmpprop:` binding, and it only reaches the scene
    /// through a transaction's overrides — a scene built without them scales the whole arc to the
    /// default 0-100 instead of the track's duration.
    func testTheSeekRangeComesFromTheTracksDuration() async throws {
        let skin = try await WMPSkinLoader().load(from: try pulsar())
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data()))
        let store = WMPImageStore(provider: skin.archive)
        let builder = WMPSceneBuilder(loadedSkin: skin, imageStore: store)
        let scene = try await builder.build(viewID: "mainView")
        var snapshot = WMPHostSnapshot()
        snapshot.duration = 213
        snapshot.currentTime = 63
        let loaded = await runtime.transact(skin: skin, viewID: "mainView", size: scene.canvasSize,
            snapshot: snapshot,
            event: WMPJScriptEvent(name: "load", targetID: nil,
                handlers: WMPMainWindowController.handlers(in: skin, event: "load",
                    targetID: nil, viewID: "mainView")),
            geometry: scene.scriptGeometry)
        let settled = try await builder.build(viewID: "mainView", overrides: loaded.overrides)
        let seek = try XCTUnwrap(settled.hits.first { $0.nodeID == "seekMain" })
        let widget = try XCTUnwrap(settled.widgets.first { $0.stableID == seek.stableID })
        XCTAssertEqual(try XCTUnwrap(widget.maximumValue), 213, accuracy: 0.001)
        // And the arc's own ends read as the ends of the track.
        let top = seek.positionMap?.fraction(at: WMPPoint(x: 332, y: 78), in: seek.frame)
        let end = seek.positionMap?.fraction(at: WMPPoint(x: 273, y: 206), in: seek.frame)
        XCTAssertEqual(try XCTUnwrap(top), 1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(end), 0, accuracy: 0.05)
    }
}
