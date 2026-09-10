import AppKit
import XCTest
@testable import NullPlayer

final class WMPVideoTests: XCTestCase {
    private func load(_ body: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(body.utf8))
        ]))
    }

    func testFitFlagsIndependentlyControlShrinkingAndEnlargement() {
        let source = CGSize(width: 640, height: 360)
        let small = CGRect(x: 10, y: 20, width: 320, height: 240)
        let large = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let natural = WMPVideoPresentation(shrinkToFit: false)
        XCTAssertEqual(natural.imageRect(source: source, bounds: small).size, source)
        // The default, which is what a box authoring no fit flags draws: shrunk, never enlarged.
        let shrinking = WMPVideoPresentation()
        XCTAssertEqual(shrinking.imageRect(source: source, bounds: small),
                       CGRect(x: 10, y: 50, width: 320, height: 180))
        XCTAssertEqual(shrinking.imageRect(source: source, bounds: large).size, source)
        let stretching = WMPVideoPresentation(shrinkToFit: false, stretchToFit: true)
        XCTAssertEqual(stretching.imageRect(source: source, bounds: large),
                       CGRect(x: 0, y: 40, width: 1280, height: 720))
        XCTAssertEqual(stretching.imageRect(source: source, bounds: small).size, source)
        let distorted = WMPVideoPresentation(shrinkToFit: true, stretchToFit: true,
                                               maintainAspectRatio: false)
        XCTAssertEqual(distorted.imageRect(source: source, bounds: small), small)
    }

    /// **The corpus's own case: 77 of its 97 sized `<VIDEO>` elements author no `shrinkToFit`, and
    /// 73 are boxes under 640x480.** Defaulting the flag false drew every one of them at native
    /// pixel size, centre-cropped to the middle of the frame; no archive authors `"false"`.
    func testAnUnattributedVideoBoxShrinksAndAnAuthoredFalseIsStillObeyed() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="400" height="300">
          <VIDEO id="plain" width="200" height="150"/>
          <VIDEO id="cropped" width="200" height="150" shrinkToFit="false" stretchToFit="true"/>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let widgets = scene.widgets.filter { $0.kind == .video }
        XCTAssertEqual(widgets.map(\.videoPresentation),
                       [WMPVideoPresentation(),
                        WMPVideoPresentation(shrinkToFit: false, stretchToFit: true)])
        // A DVD-sized picture in the corpus's typical box: letterboxed to the full width, not the
        // centre 200x150 of a 720x480 frame.
        let drawn = try XCTUnwrap(widgets.first?.videoPresentation)
            .imageRect(source: CGSize(width: 720, height: 480),
                       bounds: CGRect(x: 0, y: 0, width: 200, height: 150))
        XCTAssertEqual(drawn.width, 200, accuracy: 0.01)
        XCTAssertEqual(drawn.height, 200 * 480 / 720, accuracy: 0.01)
        XCTAssertEqual(drawn.midY, 75, accuracy: 0.01)
    }

    func testVideoEventsFollowDecoderPresenceAndNotPauseOrFullscreen() {
        let absent = WMPVideoSnapshot()
        let present = WMPVideoSnapshot(width: 640, height: 360)
        XCTAssertEqual(WMPVideoPresentation.events(previous: nil, current: absent), [])
        XCTAssertEqual(WMPVideoPresentation.events(previous: absent, current: present), ["videostart"])
        XCTAssertEqual(WMPVideoPresentation.events(previous: present, current: present), [])
        XCTAssertEqual(WMPVideoPresentation.events(previous: present,
            current: WMPVideoSnapshot(width: 640, height: 360, fullScreen: true)), [])
        XCTAssertEqual(WMPVideoPresentation.events(previous: present, current: absent), ["videoend"])
        XCTAssertFalse(WMPVideoSnapshot(width: .infinity, height: 360).hasVideo)
    }

    func testVideoEventLatchSurvivesOutputTeardownButClearsAtMediaEnd() {
        let absent = WMPVideoSnapshot()
        let present = WMPVideoSnapshot(width: 640, height: 360)
        var latch = WMPVideoEventLatch()

        let started = latch.update(mediaIdentity: "movie-a", current: present, didReachEnd: false)
        XCTAssertEqual(started, present)

        let duringOutputRebuild = latch.update(mediaIdentity: "movie-a", current: absent,
                                               didReachEnd: false)
        XCTAssertFalse(absent.hasVideo, "the live surface must see the output teardown")
        XCTAssertEqual(duringOutputRebuild, present,
                       "event state must stay present for the same open media")
        XCTAssertEqual(WMPVideoPresentation.events(previous: started,
                                                   current: duringOutputRebuild), [])

        let ended = latch.update(mediaIdentity: "movie-a", current: absent, didReachEnd: true)
        XCTAssertEqual(ended, absent)
        XCTAssertEqual(WMPVideoPresentation.events(previous: duringOutputRebuild, current: ended),
                       ["videoend"])

        let replayed = latch.update(mediaIdentity: "movie-a", current: present, didReachEnd: false)
        XCTAssertEqual(WMPVideoPresentation.events(previous: ended, current: replayed), ["videostart"])
    }

    func testVideoEventLatchClearsWhenMediaIdentityChanges() {
        let present = WMPVideoSnapshot(width: 640, height: 360)
        var latch = WMPVideoEventLatch()
        _ = latch.update(mediaIdentity: "movie-a", current: present, didReachEnd: false)

        let newMediaWithoutOutput = latch.update(mediaIdentity: "movie-b", current: .init(),
                                                 didReachEnd: false)
        XCTAssertFalse(newMediaWithoutOutput.hasVideo)
    }

    func testMediaDrivenViewResizeIsRecognizedOnlyForLegacySourceSizeFormula() {
        let source = WMPVideoSnapshot(width: 1920, height: 1080)
        XCTAssertTrue(WMPVideoPresentation.isMediaDrivenViewSize(
            WMPSize(width: 2196, height: 1308),
            authoredViewSize: WMPSize(width: 596, height: 468),
            authoredVideoSize: WMPSize(width: 320, height: 240), source: source))
        XCTAssertTrue(WMPVideoPresentation.isMediaDrivenViewSize(
            WMPSize(width: 1920, height: 1256),
            authoredViewSize: WMPSize(width: 285, height: 359),
            authoredVideoSize: WMPSize(width: 285, height: 183), source: source))
        XCTAssertFalse(WMPVideoPresentation.isMediaDrivenViewSize(
            WMPSize(width: 475, height: 373),
            authoredViewSize: WMPSize(width: 593, height: 600),
            authoredVideoSize: WMPSize(width: 320, height: 240), source: source))
    }

    func testRuntimeDropsLegacySourceSizeRootResizeFromSceneOutput() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="596" height="468">
          <SUBVIEW id="videoBox" width="320" height="240">
            <WMPVIDEO id="video" width="jscript:videoBox.width" height="jscript:videoBox.height"/>
          </SUBVIEW>
        </VIEW></THEME>
        """)
        let suite = "WMPVideoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(
            skinData: Data(suite.utf8), defaults: defaults))
        var snapshot = WMPHostSnapshot()
        snapshot.video = WMPVideoSnapshot(width: 1920, height: 1080)
        let output = await runtime.transact(skin: skin, viewID: "main",
            size: WMPSize(width: 596, height: 468), snapshot: snapshot,
            event: .init(name: "videostart", targetID: nil, handlers: [
                "view.width = player.currentMedia.imageSourceWidth + 276;"
                    + "view.height = player.currentMedia.imageSourceHeight + 228;"
            ]))
        XCTAssertNil(output.viewSize)
        let root = try XCTUnwrap(skin.views.first?.node)
        XCTAssertNil(output.overrides.geometry[WMPScenePropertyAddress(stableID: root.stableID,
                                                                       property: "width")])
        XCTAssertNil(output.overrides.geometry[WMPScenePropertyAddress(stableID: root.stableID,
                                                                       property: "height")])
        await runtime.teardown()
    }

    func testRoutingIgnoresEventOnlyVideosAndUsesEitherAuthoredVideoSpelling() async throws {
        let skin = try await load("""
        <THEME>
          <VIEW id="control"><VIDEO visible="false" onVideoStart="start()"/></VIEW>
          <VIEW id="tiny" width="80" height="40"><VIDEO width="0" onVideoStart="start()"/></VIEW>
          <VIEW id="movie" width="320" height="240"><VIDEO id="picture" width="320" height="240"/></VIEW>
          <VIEW id="legacy" width="320" height="240"><WMPVIDEO id="picture" width="320" height="240"/></VIEW>
        </THEME>
        """)
        let surfaces = WMPSkinSurfaces(skin: skin)
        XCTAssertEqual(surfaces.viewIDs(for: .video), ["movie", "legacy"])
        let noVideo = try await load("<THEME><VIEW id='audio' width='20' height='20'/></THEME>")
        XCTAssertFalse(WMPSkinSurfaces(skin: noVideo).provides(.video), "native window is the fallback")
    }

    func testScriptVideoFitReachesSceneAndFullscreenIsAHostCommand() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="400" height="300">
          <SUBVIEW id="clip" left="20" top="30" width="200" height="100">
            <VIDEO id="vid" width="300" height="200" fullScreen="true"/>
          </SUBVIEW>
          <TEXT id="size" width="100" height="20"/>
        </VIEW></THEME>
        """)
        let suite = "WMPVideoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(suite.utf8), defaults: defaults))
        var snapshot = WMPHostSnapshot()
        snapshot.video = WMPVideoSnapshot(width: 640, height: 360)
        let output = await runtime.transact(skin: skin, viewID: "main",
            size: WMPSize(width: 400, height: 300), snapshot: snapshot,
            event: .init(name: "click", targetID: "vid", handlers: ["""
              vid.shrinkToFit=true; vid.stretchToFit=true; vid.maintainAspectRatio=false;
              size.value=player.currentMedia.imageSourceWidth + 'x' + player.currentMedia.imageSourceHeight;
              if (!vid.fullScreen) vid.fullScreen=true;
            """]))
        XCTAssertFalse(output.diagnostics.contains { $0.code == "handler-error" })
        XCTAssertEqual(output.hostCommands.filter { $0.action == "setVideoFullScreen" }.count, 1,
                       "the runtime write, not the markup's fullscreen=true, requests fullscreen")
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main", overrides: output.overrides)
        let widget = try XCTUnwrap(scene.widgets.first { $0.kind == .video })
        XCTAssertEqual(widget.videoPresentation,
                       WMPVideoPresentation(shrinkToFit: true, stretchToFit: true, maintainAspectRatio: false))
        XCTAssertEqual(widget.clipRect, WMPRect(x: 20, y: 30, width: 200, height: 100))
        XCTAssertFalse(scene.commands.contains { $0.nodeID == "vid" }, "no opaque placeholder")
        await runtime.teardown()
    }

    @MainActor
    func testVideoHandlersAreClassifiedAndRemainScopedToTheirView() async throws {
        let skin = try await load("""
        <THEME><VIEW id="a" width="20" height="20">
        <VIDEO id="vid" onVideoStart="startA()" onVideoEnd="endA()"/>
        </VIEW><VIEW id="b" width="20" height="20">
        <VIDEO id="vid" onVideoStart="startB()" onVideoEnd="endB()"/>
        </VIEW></THEME>
        """)
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "videostart", targetID: nil,
                                                       viewID: "a"), ["startA()"])
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "videoend", targetID: nil,
                                                       viewID: "b"), ["endB()"])
    }
}
