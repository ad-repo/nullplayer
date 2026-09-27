import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// **The first hosted window opens wearing the skin's frame, not NullPlayer's chrome (W230).**
///
/// `WMPHostedFrameProvider` never blocks: a size it has not rendered is answered from `mostRecent`
/// scaled. On a *first* open there is no `mostRecent`, so the window was answered nil and drew
/// palette chrome until a render at its own size landed — reported 2026-09-18 as *"it draws the
/// chrome default and then snaps into the themed native window after about .5 seconds"*.
///
/// Measured on `Ice`, 2026-09-19, before the fix: the library was unskinned for **881 ms** and paid
/// **four** donor renders in it (273/391/424/492 ms), because `HostedWindowBorderLayout` grows the
/// window and every new size is another full rebuild. Only the last was ever seen.
///
/// The stand-in for the first of those was already being built and thrown away. Learning a ring's
/// borders *is* composing one — `border(builder:renderer:backingScale:)` does it at the reference
/// size, 157–170 ms after the skin loads and before any window exists — so the composition is
/// handed back rather than discarded. These tests pin that it is handed back, that it is the same
/// picture the insets were read off, and that a panel donor correctly primes nothing.
final class WMPHostedFramePrimingTests: XCTestCase {

    // MARK: - Fixtures

    private func skin(_ markup: String, images: [String: Data] = [:]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8))]
        for (path, data) in images { entries.append(WMPTestArchiveEntry(path, data: data)) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// A solid opaque block. A ring piece only has to be *there*; what these tests measure is which
    /// picture comes back, not what is painted on it.
    private func block(width: Int, height: Int) throws -> Data {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = 20
            rgba[index + 1] = 90
            rgba[index + 2] = 180
            rgba[index + 3] = 255
        }
        return try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: rgba)
    }

    /// The four corners `derive` requires, plus the stretch/stretch client that states the hole.
    /// 40pt corners on a 400x300 view, so the border is 40 on every side and the hole 320x220.
    private static let ring = """
        <SUBVIEW id="tl" horizontalAlignment="left"  verticalAlignment="top"
                 left="0" top="0" width="40" height="40" backgroundImage="corner.png"/>
        <SUBVIEW id="tr" horizontalAlignment="right" verticalAlignment="top"
                 left="360" top="0" width="40" height="40" backgroundImage="corner.png"/>
        <SUBVIEW id="bl" horizontalAlignment="left"  verticalAlignment="bottom"
                 left="0" top="260" width="40" height="40" backgroundImage="corner.png"/>
        <SUBVIEW id="br" horizontalAlignment="right" verticalAlignment="bottom"
                 left="360" top="260" width="40" height="40" backgroundImage="corner.png"/>
        <SUBVIEW id="client" horizontalAlignment="stretch" verticalAlignment="stretch"
                 left="40" top="40" width="320" height="220"/>
        """

    private func ringSkin() async throws -> WMPLoadedSkin {
        try await skin("""
        <THEME><VIEW id="plview" width="400" height="300">\(Self.ring)</VIEW></THEME>
        """, images: ["corner.png": try block(width: 40, height: 40)])
    }

    private func parts(_ loaded: WMPLoadedSkin, playerViewID: String?)
        throws -> (WMPHostedFrameTemplate, WMPSceneBuilder, WMPRenderer) {
        let template = try XCTUnwrap(WMPHostedFrameTemplate.derive(from: loaded,
                                                                   playerViewID: playerViewID),
                                     "no donor derived from the fixture")
        let store = WMPImageStore(provider: loaded.archive)
        return (template, WMPSceneBuilder(loadedSkin: loaded, imageStore: store),
                WMPRenderer(imageStore: store))
    }

    // MARK: - The rule

    /// **A ring donor hands back the frame it composed to learn its borders.**
    ///
    /// This is the whole of W230: the picture exists either way, and before the fix it was dropped
    /// on the floor. It comes back at the reference size — `max(minWidth, 320) x max(minHeight,
    /// 240)`, here the view's own 400x300 — which is why the provider keeps it as `mostRecent`
    /// rather than in `cache`: it was built for the donor's size, not for any window's.
    func testARingDonorPrimesTheFrameItComposedForItsInsets() async throws {
        let (template, builder, renderer) = try parts(try await ringSkin(), playerViewID: nil)

        let border = try await template.border(builder: builder, renderer: renderer, backingScale: 1)

        XCTAssertNotNil(border.insets, "the ring donor answered no insets")
        let primed = try XCTUnwrap(border.primed,
                                   "the ring composed for the insets was discarded — W230 regressed")
        XCTAssertEqual(primed.size.width, 400, accuracy: 0.5)
        XCTAssertEqual(primed.size.height, 300, accuracy: 0.5)
    }

    /// **And the primed frame is the one the insets were read off, not a second opinion.**
    ///
    /// The insets are derived from this artwork's own `contentRect`, so a stand-in that disagreed
    /// with them would put the window's content somewhere the growth did not account for — the
    /// windows would be grown by one frame's borders and dressed in another's.
    func testThePrimedFrameAgreesWithTheInsetsItProduced() async throws {
        let (template, builder, renderer) = try parts(try await ringSkin(), playerViewID: nil)

        let border = try await template.border(builder: builder, renderer: renderer, backingScale: 1)
        let insets = try XCTUnwrap(border.insets)
        let primed = try XCTUnwrap(border.primed)

        XCTAssertEqual(primed.contentRect.minX, insets.left, accuracy: 0.5)
        XCTAssertEqual(primed.contentRect.minY, insets.top, accuracy: 0.5)
        XCTAssertEqual(primed.size.width - primed.contentRect.maxX, insets.right, accuracy: 0.5)
        XCTAssertEqual(primed.size.height - primed.contentRect.maxY, insets.bottom, accuracy: 0.5)
    }

    /// **`borderInsets` is unchanged**, because it is now a wrapper and every caller outside the
    /// provider — `HostedWindowBorderLayout` through `WindowManager`, and the panel tests — asks it
    /// the same question it always asked.
    func testBorderInsetsStillAnswersWhatTheCompositionSays() async throws {
        let (template, builder, renderer) = try parts(try await ringSkin(), playerViewID: nil)

        let answered = try await template.borderInsets(builder: builder, renderer: renderer,
                                                       backingScale: 1)
        let wrapped = try XCTUnwrap(answered)
        let full = try await template.border(builder: builder, renderer: renderer, backingScale: 1)
        let direct = try XCTUnwrap(full.insets)

        XCTAssertEqual(wrapped.top, direct.top, accuracy: 0.5)
        XCTAssertEqual(wrapped.left, direct.left, accuracy: 0.5)
        XCTAssertEqual(wrapped.bottom, direct.bottom, accuracy: 0.5)
        XCTAssertEqual(wrapped.right, direct.right, accuracy: 0.5)
    }

    /// **A panel donor primes nothing, and that is correct rather than a shortfall.**
    ///
    /// A panel's borders are four constants of its own bitmap, read without composing anything, so
    /// there is no picture here to hand back. It is also the answer the provider's own 15% guard
    /// wants: a nine-patch stretched from the donor's size onto a window is exactly the squash the
    /// slice exists to refuse, so a panel keeps the palette for its first open. 88 of the 185
    /// archives lend a ring and 32 lend a panel — this fix reaches the former.
    func testAPanelDonorPrimesNothing() async throws {
        let tray = """
            <SUBVIEW id="tray" left="0" top="0" width="328" height="261"
                     backgroundImage="tray.png">
                <ITEMSPLAYLIST id="rows" left="83" top="72" width="155" height="116"/>
            </SUBVIEW>
            """
        let loaded = try await skin("""
        <THEME><VIEW id="plview" width="328" height="261">\(tray)</VIEW></THEME>
        """, images: ["tray.png": try block(width: 328, height: 261)])
        let (template, builder, renderer) = try parts(loaded, playerViewID: nil)
        XCTAssertNotNil(template.panelNodeID, "the fixture did not derive a panel")

        let border = try await template.border(builder: builder, renderer: renderer, backingScale: 1)

        XCTAssertNotNil(border.insets, "a panel still answers its four constants")
        XCTAssertNil(border.primed, "a panel handed back a stand-in the 15% guard would refuse")
    }
}
