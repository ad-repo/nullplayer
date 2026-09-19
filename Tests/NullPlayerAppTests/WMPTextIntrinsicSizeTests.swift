import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W218: a `<TEXT>` is sized by its own glyphs, and on the opening transaction nothing had told
/// the element model so.**
///
/// `WMPScriptContext.perform` syncs every element's frame from the layout the skin is *currently
/// drawn at*, which on the first transaction is no layout at all — so an unauthored `width`
/// answered the unset-numeric 0. `Colorchooser` is the only archive in the corpus that chains
/// geometry off a text node's measured width: its five transport buttons are
/// `left="jscript:<prev>.left+<prev>.width"`, so the chain never advanced, all four derived buttons
/// resolved to `left=16` where 16/28/40/52 was authored, the webdings glyphs overprinted at
/// `103,29 12x12`, and — `prevbutton` being last in z-order — the first click anywhere in that row
/// fired **previous**.
///
/// **It repaired itself on that same click**, because the relayout the click triggers is the first
/// one there is and the next transaction syncs real frames. That is why the defect is exactly one
/// click deep, why hand-testing did not reproduce it, and why the first test below drives a *cold*
/// load rather than asserting a steady state.
final class WMPTextIntrinsicSizeTests: XCTestCase {
    private func load(_ wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPTextIntrinsicSizeTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func build(_ skin: WMPLoadedSkin, _ size: WMPSize,
                       _ overrides: WMPSceneOverrides) async throws -> WMPScene {
        try await WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
            .build(viewID: "main", requestedSize: size, overrides: overrides)
    }

    private func frame(_ id: String, in scene: WMPScene, file: StaticString = #filePath,
                       line: UInt = #line) throws -> WMPRect {
        try XCTUnwrap(scene.widgets.first { $0.nodeID == id }, file: file, line: line).frame
    }

    /// `Colorchooser`'s transport, reduced to the chain: one authored button and one derived from
    /// its measured width. **The assertion is on the first frame the skin is ever drawn at**, with
    /// no click and no settle, because every later frame was already correct.
    func testAChainedButtonClearsTheButtonItIsMeasuredFromOnTheFirstFrame() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="playbutton" value=" 4 " fontFace="webdings" top="4" left="4"/>
            <TEXT id="stopbutton" value=" &lt; " fontFace="webdings"
                  top="jscript:playbutton.top"
                  height="jscript:playbutton.height"
                  left="jscript:playbutton.left+playbutton.width"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(skin: skin, viewID: "main",
                                            size: WMPSize(width: 300, height: 200),
                                            snapshot: WMPHostSnapshot(), event: nil)
        let scene = try await build(skin, WMPSize(width: 300, height: 200), output.overrides)

        let play = try frame("playbutton", in: scene)
        let stop = try frame("stopbutton", in: scene)
        XCTAssertEqual(stop.x, play.x + play.width,
                       "the chain advanced by the glyphs' own width — 0 put both buttons on one "
                       + "pixel, and the one drawn last answered every click in the row")
        XCTAssertGreaterThan(play.width, 0, "a text node is sized by its glyphs, never by 0")
        XCTAssertEqual(stop.y, play.y, "the row is level, which was never the defect")
    }

    /// **The measurement is the builder's, including its trim.** `WMPSceneBuilder.literalString`
    /// trims, and `Colorchooser` centres its webdings glyphs by padding the attribute
    /// (`value=" &lt; "`). Measuring the padding puts the button wider than the frame the builder
    /// lays out, which is the same row moving under the pointer for the opposite reason — so a
    /// padded value and a bare one must measure the same.
    func testPaddingInTheAuthoredValueDoesNotWidenTheFrameItIsMeasuredInto() async throws {
        func stopOrigin(_ value: String) async throws -> CGFloat {
            let skin = try await load("""
            <THEME><VIEW id="main" width="300" height="200">
                <TEXT id="playbutton" value="\(value)" fontFace="webdings" top="4" left="4"/>
                <TEXT id="stopbutton" value="x" fontFace="webdings" top="4" height="12"
                      left="jscript:playbutton.left+playbutton.width"/>
            </VIEW></THEME>
            """)
            let (runtime, cleanup) = try runtime()
            defer { cleanup() }
            let output = await runtime.transact(skin: skin, viewID: "main",
                                                size: WMPSize(width: 300, height: 200),
                                                snapshot: WMPHostSnapshot(), event: nil)
            let scene = try await build(skin, WMPSize(width: 300, height: 200), output.overrides)
            return try frame("stopbutton", in: scene).x
        }

        let padded = try await stopOrigin(" 4 ")
        let bare = try await stopOrigin("4")
        XCTAssertGreaterThan(bare, 4,
                             "the chain advanced at all — without this the assertion below holds "
                             + "trivially at 0 == 0 and guards nothing")
        XCTAssertEqual(padded, bare,
                       "the script runtime must measure what the builder lays out, and the builder "
                       + "trims: measuring the padding put Colorchooser's buttons at 24 wide "
                       + "against a frame the builder draws at 12")
    }

    /// The fallback is for a dimension the markup never stated, and nothing more. An authored
    /// number still wins — the glyph measurement is not allowed to outrank a size the skin chose,
    /// for the same reason the builder's artwork fallback is not (a skin that collapses a node to
    /// 0 deliberately must stay collapsed).
    func testAnAuthoredWidthOutranksTheGlyphs() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="playbutton" value=" 4 " fontFace="webdings" top="4" left="4" width="40"/>
            <TEXT id="stopbutton" value="x" fontFace="webdings" top="4" height="12"
                  left="jscript:playbutton.left+playbutton.width"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(skin: skin, viewID: "main",
                                            size: WMPSize(width: 300, height: 200),
                                            snapshot: WMPHostSnapshot(), event: nil)
        let scene = try await build(skin, WMPSize(width: 300, height: 200), output.overrides)
        XCTAssertEqual(try frame("stopbutton", in: scene).x, 44,
                       "4+40, the width the skin authored — not the width of its glyphs")
    }

    /// A text node with no value has no glyphs, so there is nothing to measure and the unset
    /// numeric 0 is still the honest answer. The corpus is full of these: an empty readout the
    /// host fills in later.
    func testAnEmptyTextStillMeasuresNothing() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="readout" fontFace="webdings" top="4" left="4"/>
            <TEXT id="after" value="x" fontFace="webdings" top="4" height="12"
                  left="jscript:readout.left+readout.width"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(skin: skin, viewID: "main",
                                            size: WMPSize(width: 300, height: 200),
                                            snapshot: WMPHostSnapshot(), event: nil)
        let scene = try await build(skin, WMPSize(width: 300, height: 200), output.overrides)
        XCTAssertEqual(try frame("after", in: scene).x, 4,
                       "4+0: an empty string is not a frame, and inventing one would move every "
                       + "readout the host has not filled in yet")
    }
}
