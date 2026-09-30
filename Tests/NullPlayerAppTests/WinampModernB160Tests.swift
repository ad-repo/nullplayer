import XCTest
import AppKit
@testable import NullPlayer

/// B160 — a `.wal` window the user stretched did not tell its own scene.
///
/// Reported live on Itemskin as *"the playlist window cannot be stretched/resized unless the
/// PeppyMeter window is also open"*. The mechanism is in `reference/components.md` → *Resize, and
/// why a skin needs it*.
///
/// What is pinned here is the delivery: the scene's resize baseline moves in the same turn as the
/// window. The bound half — a compiled handler answering it, and `onUserResize` from a drag on a
/// skin handle — has no headless route and is verified live; see `skins/itemskin.md`.
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
    /// size it already had — dispatches nothing. Asked of a scene that has not been seeded, where
    /// a diffing dispatch would deliver every object its first `onResize` ahead of
    /// `scriptsDidStart`.
    @MainActor
    func testAWindowResizeThatLeavesTheCanvasAloneDispatchesNothing() throws {
        let scene = try makeScene(seeded: false)
        scene.controller.windowDidResize(Notification(name: NSWindow.didResizeNotification,
                                                      object: scene.window))
        XCTAssertTrue(scene.view.resizeBaselineForTesting.isEmpty)
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
    private func makeScene(seeded: Bool = true) throws -> Scene {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="330" h="137" minimum_w="330" minimum_h="137">
              <group id="border" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = WinampModernStubHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                        componentHost: nil)
        view.setFrameSize(renderer.canvasSize)
        if seeded { view.scriptsDidStart() }

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
}
