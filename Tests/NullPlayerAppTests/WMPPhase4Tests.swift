import AppKit
import AVFoundation
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

final class WMPPhase4Tests: XCTestCase {
    private let red = WMPColor(red: 255, green: 0, blue: 0)
    private let green = WMPColor(red: 0, green: 255, blue: 0)

    func testCanonicalMappingChannelsScalingTransparencyUnknownAndBounds() {
        let map = WMPMappingImage(width: 4, height: 1,
            rgb: [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 0],
            alpha: [255, 255, 255, 0], nodeByColor: [red: 10, green: 20])
        let frame = WMPRect(x: 10, y: 5, width: 40, height: 10)
        XCTAssertEqual(map.node(at: WMPPoint(x: 11, y: 6), in: frame), 10)
        XCTAssertEqual(map.node(at: WMPPoint(x: 25, y: 6), in: frame), 20)
        XCTAssertNil(map.node(at: WMPPoint(x: 35, y: 6), in: frame)) // unknown blue
        XCTAssertNil(map.node(at: WMPPoint(x: 45, y: 6), in: frame)) // transparent red
        XCTAssertEqual(map.boundsByNode[10], WMPRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(map.boundsByNode[20], WMPRect(x: 1, y: 0, width: 1, height: 1))
    }

    func testBMPDecodePreservesAuthoredTopLeftAndRowPadding() throws {
        let pixels: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255,
            0, 255, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255
        ]
        let data = try WMPSkinTestSupport.encodedImage(width: 3, height: 2, rgba: pixels, type: .bmp)
        let decoded = try WMPImageStore(provider: WMPMemoryResourceProvider(["map.bmp": data])).image(for: "map.bmp")
        let map = try WMPMappingImage(image: decoded.image, nodeByColor: [red: 1, green: 2])
        let frame = WMPRect(x: 0, y: 0, width: 3, height: 2)
        XCTAssertEqual(map.node(at: WMPPoint(x: 0.1, y: 0.1), in: frame), 1)
        XCTAssertEqual(map.node(at: WMPPoint(x: 0.1, y: 1.1), in: frame), 2)
    }

    func testMappingCacheReusesCanonicalBufferWithinByteBudget() throws {
        let data = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [255, 0, 0, 255, 0, 255, 0, 255])
        let store = WMPImageStore(provider: WMPMemoryResourceProvider(["map.png": data]),
            limits: WMPImageStoreLimits(maximumDimension: 10, maximumPixels: 100,
                                       maximumDecodedBytes: 400, cacheBytes: 16))
        _ = try store.mappingImage(for: "MAP.PNG", nodeByColor: [red: 1, green: 2])
        _ = try store.mappingImage(for: "map.png", nodeByColor: [red: 1, green: 2])
        XCTAssertEqual(store.metrics.decodedMappingImageCount, 1)
        XCTAssertEqual(store.metrics.cachedMappingImageCount, 1)
        XCTAssertLessThanOrEqual(store.metrics.currentMappingBytes, 16)
        store.removeAll()
        XCTAssertEqual(store.metrics.currentMappingBytes, 0)
    }

    func testHitTesterUsesReverseZOrderClipAndExactMappingPixels() {
        let map = WMPMappingImage(width: 2, height: 1, rgb: [255, 0, 0, 0, 0, 255],
                                  nodeByColor: [red: 30])
        let back = hit(id: 1, z: 0, order: 1, frame: WMPRect(x: 0, y: 0, width: 20, height: 20))
        let mapped = WMPHitMetadata(stableID: 2, nodeID: "group", kind: "buttonGroup",
            frame: WMPRect(x: 0, y: 0, width: 20, height: 20),
            clipRect: WMPRect(x: 0, y: 0, width: 15, height: 20), zIndex: 2, documentOrder: 2,
            action: nil, sticky: false, enabled: true, mappingImage: map,
            mappingTargets: [WMPHitTarget(stableID: 30, nodeID: "red", kind: "buttonElement",
                frame: WMPRect(x: 0, y: 0, width: 20, height: 20), action: .play,
                sticky: false, enabled: true)])
        let tester = WMPHitTester(hits: [back, mapped])
        XCTAssertEqual(tester.hitTest(WMPPoint(x: 2, y: 2))?.stableID, 30)
        XCTAssertEqual(tester.hitTest(WMPPoint(x: 12, y: 2))?.stableID, 1) // unknown map color falls through
        XCTAssertEqual(tester.hitTest(WMPPoint(x: 17, y: 2))?.stableID, 1) // clipped front target
    }

    func testInteractionCaptureReleaseStickyDisabledAndCancel() {
        let sticky = WMPHitTarget(stableID: 7, nodeID: "sticky", kind: "button", frame: .zero,
                                  action: .toggleShuffle, sticky: true, enabled: true)
        let other = WMPHitTarget(stableID: 8, nodeID: "other", kind: "button", frame: .zero,
                                 action: .play, sticky: false, enabled: true)
        var state = WMPInteractionState()
        XCTAssertEqual(state.press(sticky), [7])
        XCTAssertNil(state.release(over: other).activated)
        _ = state.press(sticky)
        XCTAssertEqual(state.release(over: sticky).activated, 7)
        XCTAssertEqual(state.visualState(for: 7), .down)
        XCTAssertEqual(state.setDisabled(true, node: 7), [7])
        XCTAssertEqual(state.visualState(for: 7), .disabled)
        _ = state.press(other)
        XCTAssertEqual(state.cancelCapture(), [8])
    }

    func testLiteralButtonTransportActionAllowsOnlyBoundedTransportStatement() throws {
        let document = try WMPXMLParser().parse("""
        <VIEW><BUTTON id="mute" onClick="checkSoundPref('click.wav'); player.settings.mute = !player.settings.mute;"/>
        <BUTTON id="scripted" onClick="doSomething(); player.controls.play();"/></VIEW>
        """, path: "literal.wms")
        let graph = WMPObjectGraph(document: document)
        XCTAssertEqual(WMPTransportAction.authoredAction(for: graph.nodes(id: "mute")[0]), .toggleMute)
        XCTAssertNil(WMPTransportAction.authoredAction(for: graph.nodes(id: "scripted")[0]))
    }

    func testSceneBuildCreatesSemanticMappedTargetsAndStateArtwork() async throws {
        let normal = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [10, 10, 10, 255, 10, 10, 10, 255])
        let hover = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [20, 20, 20, 255, 20, 20, 20, 255])
        let mapping = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [255, 0, 0, 255, 0, 255, 0, 255])
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="20" height="10"><BUTTONGROUP id="transport"
            left="0" top="0" width="20" height="10" image="normal.png" hoverImage="hover.png"
            mappingImage="map.png"><PLAYELEMENT id="play" mappingColor="#FF0000"/>
            <NEXTELEMENT id="next" mappingColor="#00FF00"/></BUTTONGROUP></VIEW></THEME>
            """.utf8)), WMPTestArchiveEntry("normal.png", data: normal),
            WMPTestArchiveEntry("hover.png", data: hover), WMPTestArchiveEntry("map.png", data: mapping)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let initial = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let group = try XCTUnwrap(initial.hits.first)
        XCTAssertEqual(group.mappingTargets.map(\.action), [.play, .next])
        XCTAssertEqual(WMPHitTester(hits: initial.hits).hitTest(WMPPoint(x: 2, y: 2))?.action, .play)
        let playTarget = try XCTUnwrap(group.mappingTargets.first)

        var state = WMPInteractionState()
        _ = state.move(over: playTarget)
        let hovered = try await WMPSceneBuilder(loadedSkin: skin).build(
            viewID: "main", interactionState: state, dirtyNodeIDs: [group.mappingTargets[0].stableID])
        let groupCommands = hovered.commands.filter { $0.stableID == group.stableID }
        XCTAssertEqual(groupCommands.count, 2)
        guard case let .image(base) = groupCommands[0].paint,
              case let .image(overlay) = groupCommands[1].paint else {
            return XCTFail("Expected normal group artwork plus a mapped state overlay")
        }
        XCTAssertEqual(base.resourcePath, "normal.png")
        XCTAssertNil(base.mappingMask)
        XCTAssertEqual(overlay.resourcePath, "hover.png")
        XCTAssertEqual(overlay.mappingMask?.nodeIDs, [playTarget.stableID])
        let rendered = try await WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
            .render(scene: hovered)
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 2, yFromTop: 5), [20, 20, 20, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 17, yFromTop: 5), [10, 10, 10, 255])
        XCTAssertEqual(hovered.dirtyBounds, group.frame)
    }

    func testOptInNineSeriesTransportMapIsPixelClickable() async throws {
        guard let path = ProcessInfo.processInfo.environment["WMP_TEST_WMZ"], !path.isEmpty else {
            throw XCTSkip("Set WMP_TEST_WMZ to a user-supplied transport skin.")
        }
        let skin = try await WMPSkinLoader().load(from: URL(fileURLWithPath: path))
        let viewID = skin.views.first { $0.id.caseInsensitiveCompare("vPlayer") == .orderedSame }?.id
            ?? skin.views[0].id
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: viewID)
        let hit = try XCTUnwrap(scene.hits.first { $0.mappingTargets.contains { $0.action != nil } })
        let map = try XCTUnwrap(hit.mappingImage)
        let target = try XCTUnwrap(hit.mappingTargets.first { $0.action != nil })
        _ = try XCTUnwrap(map.boundsByNode[target.stableID])
        let pixel = try XCTUnwrap(map.firstPixel(for: target.stableID))
        let point = WMPPoint(
            x: hit.frame.x + (pixel.x + 0.5) * hit.frame.width / CGFloat(map.width),
            y: hit.frame.y + (pixel.y + 0.5) * hit.frame.height / CGFloat(map.height))
        XCTAssertEqual(map.node(at: point, in: hit.frame), target.stableID)
        XCTAssertTrue(hit.frame.contains(point))
        XCTAssertTrue(hit.clipRect?.contains(point) ?? true,
                      "mapped target probe must be inside its inherited clip")
        XCTAssertEqual(WMPHitTester(hits: scene.hits).hitTest(point)?.stableID, target.stableID)
    }

    @MainActor
    func testAudioHostClampsTypedValuesAndUnskinnedControlsAreAccessible() {
        let engine = AudioEngine()
        let host = WMPAudioEngineHost(audioEngine: engine)
        host.perform(.volume, value: .number(4))
        host.perform(.balance, value: .string("-4"))
        XCTAssertEqual(engine.volume, 1)
        XCTAssertEqual(engine.balance, -1)
        host.perform(.volume, value: .number(.nan))
        XCTAssertEqual(engine.volume, 1)
        host.perform(.toggleMute, value: nil)
        XCTAssertTrue(host.snapshot.muted)
        host.perform(.toggleMute, value: nil)
        XCTAssertFalse(host.snapshot.muted)

        let view = WMPUnskinnedMainView(frame: NSRect(x: 0, y: 0, width: 440, height: 170))
        view.host = host
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view.subviews.first { $0.accessibilityIdentifier() == "wmp.unskinned.playPause" })
    }

    @MainActor
    func testAudioHostControlsRealLocalPlaybackWithoutReplacingEngineState() throws {
        let directory = try WMPSkinTestSupport.temporaryDirectory()
        let url = directory.appendingPathComponent("transport.wav")
        try writeSilentWAV(to: url)

        let engine = AudioEngine()
        let host = WMPAudioEngineHost(audioEngine: engine)
        engine.loadTracks([Track(url: url, title: "WMP transport fixture")])
        XCTAssertEqual(host.snapshot.state, .playing)
        host.perform(.pause, value: nil)
        XCTAssertEqual(host.snapshot.state, .paused)
        host.perform(.play, value: nil)
        XCTAssertEqual(host.snapshot.state, .playing)
        XCTAssertGreaterThan(host.snapshot.duration, 0)
        host.perform(.seek, value: .number(0.5))
        XCTAssertGreaterThan(host.snapshot.currentTime, 0)
        host.perform(.stop, value: nil)
        XCTAssertEqual(host.snapshot.state, .stopped)
        XCTAssertEqual(host.snapshot.playlistCount, 1)
    }

    @MainActor
    func testOptInAudioHostControlsRealStreamingPlayback() async throws {
        guard let raw = ProcessInfo.processInfo.environment["WMP_TEST_STREAM_URL"],
              let url = URL(string: raw) else {
            throw XCTSkip("Set WMP_TEST_STREAM_URL to a user-approved direct audio stream.")
        }
        let engine = AudioEngine()
        let host = WMPAudioEngineHost(audioEngine: engine)
        engine.loadTracks([Track(url: url, title: "WMP stream integration", isRadioOrigin: true)])
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(host.snapshot.state, .playing)
        host.perform(.pause, value: nil)
        XCTAssertEqual(host.snapshot.state, .paused)
        host.perform(.play, value: nil)
        XCTAssertEqual(host.snapshot.state, .playing)
        host.perform(.stop, value: nil)
        XCTAssertEqual(host.snapshot.state, .stopped)
    }

    private func writeSilentWAV(to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050))
        buffer.frameLength = 22_050
        try file.write(from: buffer)
    }

    @MainActor
    func testSkinnedScenePublishesAccessibilityChildren() {
        let view = WMPMainView(frame: NSRect(x: 0, y: 0, width: 100, height: 50))
        let scene = WMPScene(viewID: "main", canvasSize: WMPSize(width: 100, height: 50),
            resizeLimits: WMPResizeLimits(minimum: WMPSize(width: 100, height: 50), maximum: nil),
            commands: [], hits: [hit(id: 4, z: 1, order: 1,
                frame: WMPRect(x: 10, y: 10, width: 20, height: 10))], geometries: [:],
            unresolved: [], diagnostics: [], dirtyBounds: nil,
            metrics: WMPSceneMetrics(resolvedNodeCount: 1, unresolvedNodeCount: 0,
                                     visibleBounds: nil), wasBuiltOnMainThread: false)
        let context = CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        view.present(context.makeImage()!, scene: scene)
        let child = view.accessibilityChildren()?.first as? NSAccessibilityElement
        XCTAssertEqual(child?.accessibilityIdentifier(), "wmp.node4")
        XCTAssertEqual(child?.accessibilityLabel(), "Play")
    }

    private func hit(id: Int, z: Int, order: Int, frame: WMPRect) -> WMPHitMetadata {
        WMPHitMetadata(stableID: id, nodeID: "node\(id)", kind: "button", frame: frame,
            clipRect: nil, zIndex: z, documentOrder: order, action: .play, sticky: false,
            enabled: true, mappingImage: nil, mappingTargets: [])
    }
}
