import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **The NVIDIA playlist report (W196): a mode is a size floor the script writes.**
///
/// Reported as *"the playlist library is opening very small size now and possibly distorting the
/// aspect ratio"*, and it was two defects. This file covers the one with a seam a unit test can
/// reach — `minWidth`/`minHeight`/`maxWidth`/`maxHeight` assigned from script never reaching
/// `WMPResizeLimits`, so a skin that raises its own floor for the mode it is switching into kept
/// the floor the markup opened with.
///
/// **W197 is not here on purpose.** It is a race between a cancelled transaction and the window
/// frame, so the only instrument that shows it is the running app; the reproduction and the
/// measurement are in `skills/wmp-skin-guide/reference/skins/nvidia.md`.
final class WMPModeSizeFloorTests: XCTestCase {
    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPModeSizeFloorTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func load(_ wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    private func build(_ skin: WMPLoadedSkin, _ size: WMPSize,
                       _ overrides: WMPSceneOverrides) async throws -> WMPScene {
        try await WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
            .build(viewID: "main", requestedSize: size, overrides: overrides)
    }

    /// `NVIDIA`'s `setModesMinWidth('playlist')`, in the smallest markup that reproduces it: raise
    /// the floor, then take the window to it. Read from the markup alone the floor stayed at the
    /// audio mode's, and the playlist could then be dragged to a quarter of the size its own layout
    /// needs — where six of its children resolve to negative heights.
    func testAScriptAssignedMinimumIsTheFloorTheSceneClampsTo() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="285" height="301" minWidth="285" minHeight="301"
                     resizable="true">
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="view.minWidth = 700; view.minHeight = 480;
                             view.width = view.minWidth; view.height = view.minHeight;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let opened = try await build(skin, WMPSize(width: 285, height: 301), WMPSceneOverrides.empty)
        XCTAssertEqual(opened.resizeLimits.minimum, WMPSize(width: 285, height: 301),
                       "the markup's own floor, before any handler has run")

        let source = """
        view.minWidth = 700; view.minHeight = 480;
        view.width = view.minWidth; view.height = view.minHeight;
        """
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 285, height: 301),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [source]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 700, height: 480),
                       "`view.minWidth` reads back what the same handler just wrote to it")

        let switched = try await build(skin, WMPSize(width: 700, height: 480), output.overrides)
        XCTAssertEqual(switched.resizeLimits.minimum, WMPSize(width: 700, height: 480),
                       "the floor the script is holding now, not the one the markup opened with")

        // The question the report was actually about: what happens to a window already below it.
        let shrunk = try await build(skin, WMPSize(width: 300, height: 320), output.overrides)
        XCTAssertEqual(shrunk.canvasSize, WMPSize(width: 700, height: 480),
                       "a request under the mode's floor is clamped up to it rather than laid out "
                       + "at a size the mode's own children cannot resolve in")
    }

    /// The same rule on the other limit, and the reason it is the same rule: a skin that narrows
    /// what its window may grow to has said so with `maxWidth`/`maxHeight`, and reading only the
    /// markup would let the window pass a ceiling the script had just lowered.
    func testAScriptAssignedMaximumIsTheCeilingTheSceneClampsTo() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="100" resizable="true">
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="view.maxWidth = 260; view.maxHeight = 140;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let unbounded = try await build(skin, WMPSize(width: 900, height: 700), WMPSceneOverrides.empty)
        XCTAssertEqual(unbounded.canvasSize, WMPSize(width: 900, height: 700),
                       "a view that authored no ceiling has none")

        let source = "view.maxWidth = 260; view.maxHeight = 140;"
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [source]))
        XCTAssertNil(output.viewSize, "a limit is not a frame: this handler resized nothing")

        let bounded = try await build(skin, WMPSize(width: 900, height: 700), output.overrides)
        XCTAssertEqual(bounded.canvasSize, WMPSize(width: 260, height: 140))
        XCTAssertEqual(bounded.resizeLimits.maximum, WMPSize(width: 260, height: 140))
    }

    /// A limit the script never touched still comes from the markup, and a view that authors none
    /// still falls back to its own size. Both are what every other skin in the corpus relies on,
    /// and neither may move because one skin writes its floor from a handler.
    func testAnUntouchedLimitIsStillTheMarkups() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="100" minWidth="180" resizable="true">
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="view.minHeight = 90;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go",
                                   handlers: ["view.minHeight = 90;"]))
        let scene = try await build(skin, WMPSize(width: 10, height: 10), output.overrides)
        XCTAssertEqual(scene.resizeLimits.minimum, WMPSize(width: 180, height: 90),
                       "the width is the markup's `minWidth` and the height is the script's; an "
                       + "unwritten limit is not replaced by the authored size")
    }
}
