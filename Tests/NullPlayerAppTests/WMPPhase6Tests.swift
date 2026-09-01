import AppKit
import CoreGraphics
import NullPlayerCore
import XCTest
@testable import NullPlayer

final class WMPPhase6Tests: XCTestCase {
    private var helperURL: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/WMPScriptIsolationHelper")
    }

    func testSceneInventoriesCompletedWidgetsAndHostedSurfaces() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="full" width="400" height="240">
              <TEXT id="title" left="4" top="4" width="100" height="20" value="Now Playing" accessibleName="Now playing"/>
              <SLIDER id="rate" left="4" top="28" width="100" height="16" min="1" max="5" tooltip="Rate"/>
              <PLAYLIST id="list" left="4" top="48" width="180" height="100" title="Playlist"/>
              <DROPDOWNPLAYLIST id="drop" left="190" top="48" width="180" height="24"/>
              <EQUALIZERSETTINGS id="eq" left="190" top="76" width="180" height="72"/>
              <POPUP id="presets" left="4" top="154" width="100" height="24"/>
              <WMPEFFECTS id="vis" left="110" top="154" width="120" height="72"/>
              <WMPVIDEO id="video" left="236" top="154" width="130" height="72"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "full")
        XCTAssertEqual(Set(scene.widgets.map(\.kind)),
            Set([.text, .slider, .playlist, .dropdownPlaylist, .equalizer, .popup, .effects, .video]))
        let slider = try XCTUnwrap(scene.widgets.first { $0.nodeID == "rate" })
        XCTAssertEqual(slider.minimumValue, 1); XCTAssertEqual(slider.maximumValue, 5)
        XCTAssertEqual(slider.toolTip, "Rate")
        XCTAssertFalse(scene.wasBuiltOnMainThread)
    }

    func testScriptCompatibilityProvidesPlaylistEQAndViewCommands() async throws {
        let runtime = WMPJScriptRuntime(helperURL: helperURL, timeout: 0.5)
        let playlist = "[{\"title\":\"One\",\"artist\":\"Artist\",\"duration\":42}]"
        let transaction = try success(await runtime.transact(WMPJScriptBatch(
            scripts: ["var n=player.currentPlaylist.item(0).name; eq.gainLevel3=7; theme.currentViewID='tiny';"],
            expressions: [.init(key: "view.width", source: "player.currentPlaylist.item(0).duration")],
            host: ["playlistCount": .number(1), "playlistJSON": .string(playlist),
                   "eqGainsJSON": .string("[0,0,0,0,0,0,0,0,0,0]"), "viewID": .string("full")]
        )))
        XCTAssertEqual(transaction.expressions.first?.value, .number(42))
        XCTAssertTrue(transaction.hostCommands.contains { $0.action == "setEQBand:2" && $0.value == .number(7) })
        XCTAssertTrue(transaction.hostCommands.contains { $0.action == "setCurrentView" && $0.value == .string("tiny") })
    }

    @MainActor
    func testAudioHostMapsTenBandEQAndGatesVisualizerConsumer() {
        let engine = AudioEngine()
        engine.applyEQLayout(forModernUI: true)
        let host = WMPAudioEngineHost(audioEngine: engine)
        XCTAssertEqual(host.snapshot.equalizer.gains.count, 10)
        host.perform(.setEQBand(4), value: .number(8))
        XCTAssertEqual(host.snapshot.equalizer.gains.count, 10)
        XCTAssertTrue(host.snapshot.equalizer.gains.allSatisfy(\.isFinite))
        XCTAssertFalse(engine.spectrumNeeded)
        host.setSpectrumConsumerActive(true); host.setSpectrumConsumerActive(true)
        XCTAssertTrue(engine.spectrumNeeded)
        host.setSpectrumConsumerActive(false)
        XCTAssertFalse(engine.spectrumNeeded)
    }

    func testPerSkinViewSizePersistenceIsIsolated() throws {
        let suite = "WMPPhase6Frames.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WMPViewFrameStore(defaults: defaults)
        store.setSize(.init(width: 320, height: 180), skin: "Skin A", view: "full")
        store.setSize(.init(width: 120, height: 60), skin: "Skin A", view: "tiny")
        XCTAssertEqual(store.size(skin: "Skin A", view: "full"), .init(width: 320, height: 180))
        XCTAssertEqual(store.size(skin: "Skin A", view: "tiny"), .init(width: 120, height: 60))
        XCTAssertNil(store.size(skin: "Skin B", view: "full"))
    }

    @MainActor
    func testNativeSurfacesReplaceWithSceneAndReleaseSpectrumOnTeardown() throws {
        let size = WMPSize(width: 200, height: 100)
        let widgets = [
            WMPWidget(stableID: 1, nodeID: "playlist", kind: .playlist,
                frame: .init(x: 0, y: 0, width: 100, height: 100), clipRect: nil,
                label: "Playlist", toolTip: nil, minimumValue: nil, maximumValue: nil),
            WMPWidget(stableID: 2, nodeID: "effects", kind: .effects,
                frame: .init(x: 100, y: 0, width: 100, height: 100), clipRect: nil,
                label: "Visualization", toolTip: nil, minimumValue: nil, maximumValue: nil)
        ]
        let scene = WMPScene(viewID: "full", canvasSize: size,
            resizeLimits: .init(minimum: size, maximum: size), commands: [], hits: [], widgets: widgets,
            geometries: [:], unresolved: [], diagnostics: [], dirtyBounds: nil,
            metrics: .init(resolvedNodeCount: 2, unresolvedNodeCount: 0, visibleBounds: nil),
            wasBuiltOnMainThread: false)
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8,
            bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let view = WMPMainView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var demand: [Bool] = []; view.onSpectrumDemandChanged = { demand.append($0) }
        view.present(try XCTUnwrap(context.makeImage()), scene: scene)
        XCTAssertEqual(view.subviews.compactMap { $0 as? WMPPlaylistSurfaceView }.count, 1)
        XCTAssertEqual(view.subviews.compactMap { $0 as? WMPEffectsSurfaceView }.count, 1)
        XCTAssertEqual(demand.last, true)
        view.prepareForUITeardown()
        XCTAssertEqual(demand.last, false)
        XCTAssertTrue(view.subviews.isEmpty)
    }

    @MainActor
    func testControllerSwitchesFullAndTinyViewsPreservingTopLeft() async throws {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "WMPPhase6Views.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let importer = WMPSkinImporter(directoryURL: root, defaults: defaults)
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="full" width="240" height="120"><TEXT left="2" top="2" width="40" height="10" value="Full"/></VIEW>
            <VIEW id="tiny" width="100" height="40"><TEXT left="2" top="2" width="40" height="10" value="Tiny"/></VIEW></THEME>
            """.utf8))
        ], filename: "Views.wmz")
        _ = try await importer.importSkin(from: archive)
        let controller = WMPMainWindowController(importer: importer)
        try await waitUntil { controller.window?.contentView is WMPMainView }
        let topLeft = NSPoint(x: controller.window!.frame.minX, y: controller.window!.frame.maxY)
        controller.switchView(to: "tiny")
        try await waitUntil { controller.window?.frame.size == NSSize(width: 100, height: 40) }
        XCTAssertEqual(defaults.string(forKey: WMPSkinImporter.selectedViewIDKey), "tiny")
        XCTAssertEqual(controller.window!.frame.minX, topLeft.x, accuracy: 0.5)
        XCTAssertEqual(controller.window!.frame.maxY, topLeft.y, accuracy: 0.5)
        controller.switchView(to: "full")
        try await waitUntil { controller.window?.frame.size == NSSize(width: 240, height: 120) }
        controller.prepareForUITeardown(); controller.window?.close()
    }

    private func success(_ result: Result<WMPJScriptTransaction, WMPPhase0Diagnostic>) throws -> WMPJScriptTransaction {
        switch result { case let .success(value): return value; case let .failure(error): throw error }
    }

    @MainActor
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: @escaping @MainActor () -> Bool) async throws {
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { XCTFail("Timed out waiting for WMP Phase 6 state"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
