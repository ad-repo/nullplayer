import XCTest
@testable import NullPlayer

/// B363 — a `<text>`'s `shadowx`/`shadowy` draw the string again in `shadowcolor` at that offset.
///
/// The_Official_Lex_Luthor_Winamp5_Skin outlines its white frame titles with eight such copies, every
/// ±2 offset, and no `shadow="1"`.
final class WinampModernB363Tests: XCTestCase {

    func testTheOffsetIsDeclaredByShadowXOrShadowY() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="10" h="10">
          <text id="both" shadowx="2" shadowy="-2"/>
          <text id="y" shadowy="1"/>
          <text id="colour" shadowcolor="0,0,0"/>
          <text id="zero" shadow="1" shadowx="0" shadowy="0"/>
        </layout></container></WasabiXML>
        """)
        func offset(_ id: String) -> CGSize? {
            WasabiTextMetrics.shadowOffset(of: loaded.runtime.graph.objects(xmlID: id)[0])
        }
        XCTAssertEqual(offset("both"), CGSize(width: 2, height: -2))
        XCTAssertEqual(offset("y"), CGSize(width: 0, height: 1))
        XCTAssertNil(offset("colour"), "a colour alone places no shadow")
        XCTAssertNil(offset("zero"), "under the string is no shadow")
    }

    func testTheShadowIsDrawnInItsColourAtItsOffset() throws {
        XCTAssertGreaterThan(try redPixels(shadow: #"shadowcolor="255,0,0" shadowx="3" shadowy="3""#), 0)
        XCTAssertEqual(try redPixels(shadow: #"shadowcolor="255,0,0""#), 0)
    }

    /// Pixels drawn pure red over the black layout, with a white `W` on top.
    private func redPixels(shadow: String) throws -> Int {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <bitmap id="black" file="$solid" color="0,0,0" w="60" h="40"/>
          <container id="main">
            <layout id="normal" w="60" h="40" background="black">
              <text id="title" x="0" y="0" w="60" h="40" fontsize="30" default="W" color="255,255,255" \(shadow)/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { renderer.teardown() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8,
                                              bytesPerRow: 240, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        renderer.draw(in: context)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return stride(from: 0, to: 60 * 40 * 4, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] < 60 && pixels[$0 + 2] < 60
        }.count
    }
}
