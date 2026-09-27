import XCTest
@testable import NullPlayer

/// W306: a button's clickable area is every state sprite it authors, not the one it is drawing.
/// W307: a fill bar drawn dark on a light ground is not read as running backwards.
final class WMPStateSpriteCoverageTests: XCTestCase {
    private func load(wms: String, images: [String: Data]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        entries += images.map { WMPTestArchiveEntry($0.key, data: $0.value) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// An RGBA sprite opaque black inside `opaque` (or everywhere, when nil) and clear elsewhere.
    private func sprite(_ width: Int, _ height: Int, opaque: CGRect? = nil) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: width, height: height,
            rgba: (0..<(width * height)).flatMap { index -> [UInt8] in
                let inside = opaque.map { $0.contains(CGPoint(x: index % width, y: index / width)) } ?? true
                return inside ? [0, 0, 0, 255] : [0, 0, 0, 0]
            })
    }

    /// `xsn_sports`' drawer tab: a small arrow in `image`/`downImage`, and a hover sprite opaque
    /// edge to edge. The pointer sees the hover sprite, so its margin must press the tab rather
    /// than fall through to the body behind it.
    func testTheHoverSpritesMarginPressesTheButton() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="40" height="40">
            <BUTTON id="body" left="0" top="0" width="40" height="40" image="body.png"/>
            <BUTTON id="tab" left="10" top="10" image="arrow.png" downImage="arrow.png"
                    hoverImage="tab.png" hoverDownImage="tab.png" sticky="true"/>
        </VIEW></THEME>
        """, images: [
            "body.png": try sprite(40, 40),
            "arrow.png": try sprite(19, 13, opaque: CGRect(x: 3, y: 3, width: 13, height: 7)),
            "tab.png": try sprite(19, 13),
        ])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let tester = WMPHitTester(hits: scene.hits)

        XCTAssertEqual(tester.hitTest(WMPPoint(x: 11, y: 11))?.nodeID, "tab",
                       "the hover sprite's margin is the tab")
        XCTAssertEqual(tester.hitTest(WMPPoint(x: 18, y: 16))?.nodeID, "tab")
        XCTAssertEqual(tester.hitTest(WMPPoint(x: 35, y: 35))?.nodeID, "body",
                       "and it claims nothing outside its own frame")
    }

    /// A fully transparent `image` is a hit catcher (`holiday_skin`, `Grinch`): an opaque hover
    /// sprite must not turn it into a shape and take the rest of its rect away.
    func testAHitCatcherKeepsItsWholeRect() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="40" height="40">
            <BUTTON id="body" left="0" top="0" width="40" height="40" image="body.png"/>
            <BUTTON id="catcher" left="10" top="10" image="clear.png"
                    hoverImage="spot.png"/>
        </VIEW></THEME>
        """, images: [
            "body.png": try sprite(40, 40),
            "clear.png": try sprite(20, 20, opaque: .zero),
            "spot.png": try sprite(20, 20, opaque: CGRect(x: 0, y: 0, width: 4, height: 4)),
        ])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertEqual(WMPHitTester(hits: scene.hits).hitTest(WMPPoint(x: 25, y: 25))?.nodeID,
                       "catcher")
    }

    /// `Secura`'s `bar.gif`, in miniature: a dark fill growing from a one-pixel sliver over a light
    /// ground. By brightness the empty frame is the lit one, which reversed the bar; the middle
    /// frame at the minimum end says the last frame is full.
    func testADarkFillOverALightGroundIsNotReversed() throws {
        let frames = 5, frameWidth = 10, height = 3
        let width = frames * frameWidth
        let rgba = (0..<(width * height)).flatMap { index -> [UInt8] in
            let frame = (index % width) / frameWidth, x = index % frameWidth
            let filled = x <= frame * (frameWidth - 1) / (frames - 1)
            let value: UInt8 = filled ? 40 : 200
            return [value, value, value, 255]
        }
        let store = WMPImageStore(provider: WMPMemoryResourceProvider([
            "bar.png": try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: rgba)
        ]))
        XCTAssertFalse(try store.filmstripIsDescending(for: "bar.png", frameCount: frames,
                                                       vertical: false, gradient: (true, true)))
    }
}
