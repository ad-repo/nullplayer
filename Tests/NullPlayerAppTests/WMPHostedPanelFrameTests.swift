import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// The **one-piece panel** donor: a ring-less `.wmz` lending our windows the drawer it drew,
/// nine-sliced at its own hole (W207).
///
/// 88 of the 185 installed archives lend an eight-piece ring and 97 lend nothing; of those 97, 72
/// declare a panel this recognises and **32 produce a frame** once the two guards below have run.
/// `anemone` is the reported case and the numbers in these fixtures are its shape: a 328x261 tray
/// with its list at 83,72 155x116.
final class WMPHostedPanelFrameTests: XCTestCase {

    private func skin(_ markup: String, images: [String: Data] = [:]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8))]
        for (path, data) in images { entries.append(WMPTestArchiveEntry(path, data: data)) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// A solid panel with a distinct one-pixel border, so a nine-slice can be told from a stretch:
    /// the border colour must survive at 1:1 in the corners.
    private func panelImage(width: Int, height: Int) throws -> Data {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let edge = x == 0 || y == 0 || x == width - 1 || y == height - 1
                let offset = (y * width + x) * 4
                rgba[offset] = edge ? 255 : 0
                rgba[offset + 1] = edge ? 0 : 0
                rgba[offset + 2] = edge ? 0 : 255
                rgba[offset + 3] = 255
            }
        }
        return try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: rgba)
    }

    private static let tray = """
        <SUBVIEW id="tray" left="307" top="0" width="328" height="261"
                 backgroundImage="tray.png" transparencyColor="#00FF00" visible="false">
          <BUTTON id="closeTray" left="247" top="69" image="tray.png"/>
          <ITEMSPLAYLIST id="pl" left="83" top="72" width="155" height="116" visible="false"/>
        </SUBVIEW>
        """

    // MARK: - Derivation

    func testAPanelIsDerivedWhenTheSkinLendsNoRing() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="321" height="268">\(Self.tray)</VIEW></THEME>
        """, images: ["tray.png": try panelImage(width: 328, height: 261)])
        let template = WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview")
        XCTAssertNotNil(template?.panelNodeID)
        XCTAssertEqual(template?.viewID, "myview")
    }

    /// **A ring outranks a panel, and it is not scored against one.** A ring is laid out by its
    /// author at every size; a slice is inferred from the hole, so a skin that states both has
    /// already said which it means. This is what keeps the corpus's 88 ring archives unchanged.
    func testARingWinsWhereASkinStatesBoth() async throws {
        let loaded = try await skin("""
        <THEME>
        <VIEW id="myview" width="321" height="268">\(Self.tray)</VIEW>
        <VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left"    verticalAlignment="top"    backgroundImage="tray.png"/>
          <SUBVIEW horizontalAlignment="right"   verticalAlignment="top"    backgroundImage="tray.png"/>
          <SUBVIEW horizontalAlignment="left"    verticalAlignment="bottom" backgroundImage="tray.png"/>
          <SUBVIEW horizontalAlignment="right"   verticalAlignment="bottom" backgroundImage="tray.png"/>
          <SUBVIEW id="plFrame" horizontalAlignment="stretch" verticalAlignment="stretch"
                   left="10" top="10" width="180" height="180">
            <PLAYLIST id="plList" left="0" top="0" width="180" height="180"/>
          </SUBVIEW>
        </VIEW>
        </THEME>
        """, images: ["tray.png": try panelImage(width: 328, height: 261)])
        let template = WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview")
        XCTAssertNil(template?.panelNodeID)
        XCTAssertEqual(template?.viewID, "plView")
        XCTAssertEqual(template?.ringNodeIDs.count, 4)
    }

    /// **A player body with a list in it is not a window frame**, and the transport is what says so.
    /// `Erektorset`'s panel is its whole player — EQ graph, band sliders, volume and balance — and
    /// slicing it produces a picture of a player with a hole punched in its left third. 14 of the
    /// corpus's 46 otherwise-sliceable panels are in this position.
    func testAPanelCarryingTheTransportIsNotADonor() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="328" height="261">
        <SUBVIEW id="body" left="0" top="0" width="328" height="261"
                 backgroundImage="tray.png" transparencyColor="#00FF00">
          <VOLUMESLIDER id="vol" left="10" top="200" width="100" height="10"/>
          <ITEMSPLAYLIST id="pl" left="83" top="72" width="155" height="116"/>
        </SUBVIEW></VIEW></THEME>
        """, images: ["tray.png": try panelImage(width: 328, height: 261)])
        XCTAssertNil(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview"))
    }

    /// **A playlist that hides its items is a toolbar, not a hole.** `Heart_Butterfly`'s panel is a
    /// 149x205 blue box with a 22pt `playlistItemsVisible="false"` strip at its foot; slicing there
    /// gave every hosted window a 170pt band of blank panel above its content.
    func testAPlaylistHidingItsItemsIsNotAHole() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="350" height="400">
        <SUBVIEW id="panel" left="103" top="192" width="149" height="205"
                 backgroundImage="tray.png" visible="false">
          <PLAYLIST id="playList" left="7" top="170" width="135" height="22"
                    playlistItemsVisible="false" toolbarVisible="true" dropdownVisible="true"/>
        </SUBVIEW></VIEW></THEME>
        """, images: ["tray.png": try panelImage(width: 149, height: 205)])
        XCTAssertNil(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview"))
    }

    /// A hole flush to an edge leaves no border on that side, which is a hairline rather than a
    /// frame: 30 of the corpus's 77 panels, deliberately out of this landing.
    func testAHoleFlushToAnEdgeIsNotAPanel() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="328" height="261">
        <SUBVIEW id="tray" left="0" top="0" width="328" height="261"
                 backgroundImage="tray.png" transparencyColor="#00FF00">
          <ITEMSPLAYLIST id="pl" left="0" top="0" width="200" height="200"/>
        </SUBVIEW></VIEW></THEME>
        """, images: ["tray.png": try panelImage(width: 328, height: 261)])
        XCTAssertNil(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview"))
    }

    /// **Innermost wins.** A list is inside a drawer inside a player and all three carry artwork:
    /// the drawer is the window the skin drew, the body is the player the user is already looking at.
    func testTheInnermostPanelWins() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="466" height="400">
        <SUBVIEW id="body" left="0" top="0" width="466" height="400"
                 backgroundImage="tray.png" transparencyColor="#00FF00">
          <SUBVIEW id="drawer" left="20" top="20" width="226" height="204"
                   backgroundImage="tray.png" transparencyColor="#00FF00">
            <ITEMSPLAYLIST id="pl" left="25" top="55" width="177" height="117"/>
          </SUBVIEW>
        </SUBVIEW></VIEW></THEME>
        """, images: ["tray.png": try panelImage(width: 328, height: 261)])
        let loadedSkin = loaded
        let template = WMPHostedFrameTemplate.derive(from: loadedSkin, playerViewID: "myview")
        let drawer = loadedSkin.graph.allNodes.first { $0.xmlID == "drawer" }
        XCTAssertEqual(template?.panelNodeID, drawer?.stableID)
    }

    // MARK: - The artwork

    /// The four margins are the window's insets at **any** size — that is what slicing buys — and
    /// the centre is a hole rather than a fill, because our content goes there.
    func testTheSliceKeepsItsBordersAtEverySizeAndLeavesTheCentreOpen() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="321" height="268">\(Self.tray)</VIEW></THEME>
        """, images: ["tray.png": try panelImage(width: 328, height: 261)])
        guard let template = WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview") else {
            return XCTFail("no panel derived")
        }
        let store = WMPImageStore(provider: loaded.archive)
        let builder = WMPSceneBuilder(loadedSkin: loaded, imageStore: store)
        let renderer = WMPRenderer(imageStore: store)

        // Two sizes the donor can dress. Anything shorter than its own borders is refused, which
        // `testAWindowTooShortForTheBordersGetsNoFrameAndTheNextWindowStillDoes` pins.
        for size in [CGSize(width: 550, height: 464), CGSize(width: 400, height: 300)] {
            guard let artwork = try await template.artwork(builder: builder, renderer: renderer,
                                                           size: size, backingScale: 1) else {
                return XCTFail("no artwork at \(size)")
            }
            XCTAssertEqual(artwork.size, size)
            // `anemone`'s own numbers: 83 left, 72 above, 73 below. The right margin is 90 and the
            // ring path's side-rack rule pulls it back to the left's 83 — both paths share it.
            XCTAssertEqual(artwork.contentRect.minX, 83, accuracy: 0.5)
            XCTAssertEqual(artwork.contentRect.minY, 72, accuracy: 0.5)
            XCTAssertEqual(artwork.metrics.bottomBorder, 73, accuracy: 0.5)
            XCTAssertEqual(artwork.metrics.rightBorder, 83, accuracy: 0.5)

            let pixels = try XCTUnwrap(Self.rgba(artwork.image))
            let width = artwork.image.width, height = artwork.image.height
            func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
            func isBorder(_ x: Int, _ y: Int) -> Bool {
                let offset = (y * width + x) * 4
                return pixels[offset] > 200 && pixels[offset + 2] < 60 && pixels[offset + 3] > 200
            }
            // The panel's own one-pixel border, at 1:1 in all four corners — a stretched panel
            // would have smeared it across the whole edge.
            XCTAssertTrue(isBorder(0, 0), "top-left corner lost its border at \(size)")
            XCTAssertTrue(isBorder(width - 1, 0), "top-right corner lost its border at \(size)")
            XCTAssertTrue(isBorder(0, height - 1), "bottom-left corner lost its border at \(size)")
            XCTAssertTrue(isBorder(width - 1, height - 1), "bottom-right corner lost its border at \(size)")
            // The centre is untouched: the hosted surface is what fills it.
            XCTAssertEqual(alpha(width / 2, height / 2), 0, "the centre was painted at \(size)")
        }
    }

    /// **A short window is not given a scaled-down border — it is given no border, and grown (W207).**
    ///
    /// Three answers were reported wrong before this one, and this test used to assert the third:
    /// composing at the borders' own size left a five-point hole with the drawer squashed around it;
    /// refusing the window took the border off every window in the spectrum family; and a uniform
    /// scale-to-fit, which kept a third of each axis for content, drew the border thinner than the
    /// skin did — *"the interior is too small because the exterior border is very wide"*.
    ///
    /// The rule now is the one the reporter asked for: **the interior keeps its size and the border
    /// is added around it**, so a window too short to carry the border at 1:1 is answered nil and
    /// keeps its palette chrome until `HostedWindowBorderLayout` has grown it. Nothing is ever drawn
    /// at a scale its author did not choose.
    func testAShortWindowIsRefusedRatherThanGivenAShrunkenBorder() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="321" height="268">\(Self.tray)</VIEW></THEME>
        """, images: ["tray.png": try panelImage(width: 328, height: 261)])
        guard let template = WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview") else {
            return XCTFail("no panel derived")
        }
        let store = WMPImageStore(provider: loaded.archive)
        let builder = WMPSceneBuilder(loadedSkin: loaded, imageStore: store)
        let renderer = WMPRenderer(imageStore: store)

        // The spectrum family's own opening size. 145 points of border would leave 5.
        let short = try await template.artwork(builder: builder, renderer: renderer,
                                               size: CGSize(width: 600, height: 150), backingScale: 1)
        XCTAssertNil(short, "a window too short for the border was dressed in a shrunken one")

        // **Grown by exactly the border, it fits at 1:1 and the hole is the interior it asked for.**
        // 600x150 of interior plus this donor's 83/72/90/73 is what the layout asks for next.
        let insets = try await template.borderInsets(builder: builder, renderer: renderer,
                                                     backingScale: 1)
        let border = try XCTUnwrap(insets)
        let grown = CGSize(width: 600 + border.left + border.right,
                           height: 150 + border.top + border.bottom)
        guard let dressed = try await template.artwork(builder: builder, renderer: renderer,
                                                       size: grown, backingScale: 1) else {
            return XCTFail("the grown window still wears no border")
        }
        XCTAssertFalse(dressed.wasScaledToFit, "the border was scaled on a window sized to carry it")
        XCTAssertEqual(dressed.contentRect.width, 600, accuracy: 0.5)
        XCTAssertEqual(dressed.contentRect.height, 150, accuracy: 0.5)
        // The borders are the author's own numbers, not a fraction of them.
        XCTAssertEqual(dressed.metrics.titleHeight, border.top, accuracy: 0.5)
        XCTAssertEqual(dressed.metrics.bottomBorder, border.bottom, accuracy: 0.5)

        // And a roomier window is untouched — the hole takes every extra point.
        guard let roomy = try await template.artwork(builder: builder, renderer: renderer,
                                                     size: CGSize(width: 1200, height: 800),
                                                     backingScale: 1) else {
            return XCTFail("no artwork at 1200x800")
        }
        XCTAssertFalse(roomy.wasScaledToFit)
        XCTAssertEqual(roomy.contentRect.minY, 72, accuracy: 0.5)
        XCTAssertEqual(roomy.contentRect.width, 1034, accuracy: 0.5)
    }

    /// The other refusal is a verdict on the donor rather than on the window, so it is thrown: a
    /// panel sized by its own bitmap can only be checked against the resolved hole, one build after
    /// the derivation claimed it, and the provider drops the template on this error alone.
    func testAPanelWhoseResolvedHoleIsFlushToAnEdgeThrows() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="328" height="261">
        <SUBVIEW id="tray" left="0" top="0" backgroundImage="tray.png" transparencyColor="#00FF00">
          <ITEMSPLAYLIST id="pl" left="0" top="0" width="320" height="255"/>
        </SUBVIEW></VIEW></THEME>
        """, images: ["tray.png": try panelImage(width: 328, height: 261)])
        guard let template = WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview") else {
            return XCTFail("the derivation cannot see an unauthored size; it must claim this panel")
        }
        let store = WMPImageStore(provider: loaded.archive)
        let builder = WMPSceneBuilder(loadedSkin: loaded, imageStore: store)
        let renderer = WMPRenderer(imageStore: store)
        do {
            _ = try await template.artwork(builder: builder, renderer: renderer,
                                           size: CGSize(width: 550, height: 464), backingScale: 1)
            XCTFail("expected the slice to refuse this donor")
        } catch WMPHostedFrameRefusal.panelCannotBeSliced {
            // The provider drops the template here.
        }
    }

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ok = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width,
                                          height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                              | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return ok ? pixels : nil
    }
}
