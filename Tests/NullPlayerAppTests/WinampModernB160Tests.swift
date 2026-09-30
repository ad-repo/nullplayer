import XCTest
import AppKit
import ZIPFoundation
@testable import NullPlayer

/// B160 — a `.wal` window the user stretched did not tell its own scene.
///
/// Reported live on Itemskin as *"the playlist window cannot be stretched/resized unless the
/// PeppyMeter window is also open"*. Itemskin draws each component window's frame in a second
/// window. The frame script sizes the frame onto its contents from a 10 ms timer, and sizes the
/// contents to the frame from the frame's `onResize`. `windowDidResize` resized the renderer and
/// dispatched nothing: `onResize` reached a scene only when some script's own geometry write set
/// off `geometryDidSettle`. With one framed window open, the only script writing geometry was the
/// timer that had already put the frame back, so the drag was undone 10 ms after every step. A
/// second framed window (PeppyMeter wears a copy of the AVS frame) ran a second timer whose
/// settle delivered the first window's overdue `onResize`, which is the whole of "unless the
/// PeppyMeter window is also open".
///
/// What is pinned here is the delivery: the scene's resize baseline moves in the same turn as the
/// window. The bound half — a compiled handler answering it — has no headless route and is
/// verified live; see `skins/itemskin.md`.
final class WinampModernB160Tests: XCTestCase {

    @MainActor
    func testAWindowResizeReachesTheSceneInTheSameTurn() throws {
        let scene = try makeScene()
        let layoutID = scene.renderer.layoutForTesting.stableID
        XCTAssertEqual(scene.view.resizeBaselineForTesting[layoutID]?.size, CGSize(width: 330, height: 137),
                       "fixture must be seeded, or the comparison below proves nothing")

        scene.window.setContentSize(NSSize(width: 380, height: 197))
        scene.controller.windowDidResize(Notification(name: NSWindow.didResizeNotification,
                                                      object: scene.window))

        XCTAssertEqual(scene.renderer.canvasSize, CGSize(width: 380, height: 197))
        XCTAssertEqual(scene.view.resizeBaselineForTesting[layoutID]?.size, CGSize(width: 380, height: 197),
                       "the layout heard its own resize; before B160 this stayed at 330x137 until "
                       + "some other script moved something")
    }

    /// A resize that leaves the canvas where it was — a UI Size change, a frame restored at the
    /// size it already had — dispatches nothing, as before.
    @MainActor
    func testAWindowResizeThatLeavesTheCanvasAloneDispatchesNothing() throws {
        let scene = try makeScene()
        let before = scene.view.resizeBaselineForTesting
        scene.controller.windowDidResize(Notification(name: NSWindow.didResizeNotification,
                                                      object: scene.window))
        XCTAssertEqual(scene.view.resizeBaselineForTesting, before)
    }

    /// Only a press on one of the skin's own `resize=` handles makes a resize the user's; a view
    /// nobody is dragging must not turn a tiler or script resize into `onUserResize` (B110).
    @MainActor
    func testAViewNobodyIsDraggingIsNotInAHandleResize() throws {
        XCTAssertFalse(try makeScene().view.isResizingFromSkinHandle)
    }

    func testTheNotificationIsOnUnlessTheDebugSwitchTurnsItOff() {
        XCTAssertEqual(WasabiWindowResizeNotification.isEnabled,
                       ProcessInfo.processInfo.environment["WINAMP_MODERN_RESIZE_NOTIFY"] != "0")
    }

    // MARK: - Fixtures

    private struct Scene {
        let controller: WinampModernMainWindowController
        let window: NSWindow
        let renderer: WasabiSceneRenderer
        let view: WinampModernMainView
    }

    /// Itemskin's frame window, reduced to what the rule turns on: a resizable layout in a window
    /// whose delegate is the skin controller.
    @MainActor
    private func makeScene() throws -> Scene {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="330" h="137" minimum_w="330" minimum_h="137">
              <group id="border" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                        componentHost: nil)
        view.setFrameSize(renderer.canvasSize)
        view.scriptsDidStart()

        // Built through the designated initializer rather than `init()`, which would load whichever
        // skin the machine running the tests happens to have selected.
        let player = WinampModernSkinWindow(contentRect: NSRect(x: 0, y: 0, width: 275, height: 116),
                                            styleMask: [.borderless], backing: .buffered, defer: false)
        player.isReleasedWhenClosed = false
        let controller = WinampModernMainWindowController(window: player)
        let window = WinampModernSkinWindow(contentRect: NSRect(origin: .zero, size: renderer.canvasSize),
                                            styleMask: [.borderless, .resizable], backing: .buffered,
                                            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        addTeardownBlock { @MainActor in
            window.contentView = nil
            player.contentView = nil
            _ = controller
        }
        return Scene(controller: controller, window: window, renderer: renderer, view: view)
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

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB160Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B160-\(UUID().uuidString).wal")
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
}
