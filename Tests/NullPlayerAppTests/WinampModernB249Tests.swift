import AppKit
import XCTest
@testable import NullPlayer

/// B249 — a region group's mask clips hit testing as well as drawing.
///
/// A group whose `background` is not painted is shaped by it (ArmorAmp's blade-shaped `visgroup.bg`).
/// The mask used to be a second clip field only the draw read, so a control in a masked-off part of
/// the group stayed clickable where nothing was drawn.
final class WinampModernB249Tests: XCTestCase {

    func testAClickInARegionGroupsMaskedOffAreaFallsThrough() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <elements><bitmap id="region" file="region.png"/></elements>
          <container id="main"><layout id="normal" w="40" h="20">
            <button id="under" x="0" y="0" w="40" h="20" action="PLAY" rectrgn="1"/>
            <group id="shaped" x="0" y="0" w="20" h="10" background="region" drawbackground="0">
              <button id="over" x="0" y="0" w="20" h="10" action="STOP" rectrgn="1"/>
            </group>
          </layout></container>
        </WasabiXML>
        """, files: ["region.png": try leftHalfOpaque(width: 20, height: 10)])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { renderer.teardown() }
        XCTAssertEqual(renderer.object(at: CGPoint(x: 5, y: 5))?.xmlID, "over", "inside the mask")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 15, y: 5))?.xmlID, "under", "masked off")
    }

    private func leftHalfOpaque(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
