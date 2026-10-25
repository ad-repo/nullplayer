import AppKit
import XCTest
@testable import NullPlayer

/// A `<group>`'s region is its `background` artwork's alpha, like any layer's. RODE 3 Lite lays a
/// 97%-transparent `player.main.sliders` over its whole player; tested as a solid box it covered 24
/// of the controls beneath it.
final class WinampModernGroupHitTests: XCTestCase {

    func testAGroupIsHitThroughItsBackgroundsAlpha() throws {
        let loaded = try makeWinampModernSkin(xml: """
            <WasabiXML>
              <container id="main">
                <layout id="normal" w="20" h="10">
                  <button id="under" x="0" y="0" w="20" h="10" action="PLAY"/>
                  <group id="cover" x="0" y="0" w="20" h="10" move="1" background="art/half.png"/>
                </layout>
              </container>
            </WasabiXML>
            """, files: ["art/half.png": try leftHalfOpaquePNG(width: 20, height: 10)])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }

        XCTAssertEqual(renderer.object(at: CGPoint(x: 5, y: 5))?.xmlID, "cover", "the art's opaque half")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 15, y: 5))?.xmlID, "under",
                       "the transparent half passes the click to the control beneath")
    }

    private func leftHalfOpaquePNG(width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try XCTUnwrap(rep.bitmapData)
        for y in 0..<height {
            for x in 0..<width / 2 { pixels[y * rep.bytesPerRow + x * 4 + 3] = 255 }
        }
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
