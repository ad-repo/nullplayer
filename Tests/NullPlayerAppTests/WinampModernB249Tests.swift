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
        """, files: ["region.png": try png(width: 20, height: 10, opaque: CGRect(x: 0, y: 0, width: 10, height: 10))])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { renderer.teardown() }
        XCTAssertEqual(renderer.object(at: CGPoint(x: 5, y: 5))?.xmlID, "over", "inside the mask")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 15, y: 5))?.xmlID, "under", "masked off")
    }

    /// The mask is stored bottom-up for the flipped scene context; the hit test reads it top-down.
    func testTheMaskIsReadTheRightWayUp() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <elements><bitmap id="region" file="region.png"/></elements>
          <container id="main"><layout id="normal" w="20" h="20">
            <button id="under" x="0" y="0" w="20" h="20" action="PLAY" rectrgn="1"/>
            <group id="shaped" x="0" y="0" w="20" h="20" background="region" drawbackground="0">
              <button id="over" x="0" y="0" w="20" h="20" action="STOP" rectrgn="1"/>
            </group>
          </layout></container>
        </WasabiXML>
        """, files: ["region.png": try png(width: 20, height: 20, opaque: CGRect(x: 0, y: 0, width: 20, height: 5))])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { renderer.teardown() }
        XCTAssertEqual(renderer.object(at: CGPoint(x: 10, y: 2))?.xmlID, "over", "top strip, inside")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 10, y: 15))?.xmlID, "under", "below it, masked off")
    }

    /// A PNG opaque inside `opaque`, given in top-left (Wasabi) coordinates.
    private func png(width: Int, height: Int, opaque: CGRect) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: opaque.minX, y: CGFloat(height) - opaque.maxY,
                            width: opaque.width, height: opaque.height))
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
