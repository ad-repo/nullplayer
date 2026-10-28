import AppKit
import XCTest
@testable import NullPlayer

/// Three rules MIDISUI_1_1 found (sha256 6778daa5…):
///
/// - **A slide is a move within a box.** Its vis drawer is a layer in a group with no `w`/`h`, opened
///   with `setTargetX(-118)`; unclipped, the cover slid over the COMPONENT column and the playlist.
/// - **A `<group>` has no `image`.** Its `ledAnimation` group is instanced with the 280×14 LED sheet as
///   `image=`, and painting it drew 20 red dots over the panel labels and off the window's edge.
/// - **A braced GUID ends at its brace.** `guid:{6B0EDF80-…} (Media library)` held nothing.
final class WinampModernMIDISUITests: XCTestCase {

    private static let red: [UInt8] = [255, 0, 0, 255]

    func testAGroupDoesNotPaintItsImage() throws {
        let (_, pixels) = try render(content: #"<group id="leds" x="0" y="0" image="red"/>"#)
        XCTAssertEqual(pixels().at(10, 10)[3], 0, "the sheet named by a group's image= is not art")
    }

    func testATargetMovedChildClipsToItsUnsizedGroupsDeclaredBox() throws {
        let (renderer, pixels) = try render(
            content: #"<group id="drawer" x="20" y="0"/>"#,
            definitions: #"<groupdef id="drawer"><layer id="cover" x="0" y="0" w="20" h="20" image="red"/></groupdef>"#)
        XCTAssertEqual(pixels().at(25, 10), Self.red, "at rest the cover draws where it was declared")

        let cover = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "cover").first)
        cover.moveForTarget("x", to: "-20")
        let moved = pixels()
        XCTAssertEqual(moved.at(10, 10)[3], 0, "slid out of its box, it is clipped away")
        XCTAssertEqual(moved.at(25, 10)[3], 0)
    }

    /// B297, iCandy-2's remote: a drawer parked wholly left of its sizeless group's origin is closed.
    func testANodeWhollyBeforeAnUnsizedGroupsOriginIsNotDrawn() throws {
        let (_, pixels) = try render(
            content: #"<group id="lcd" x="20" y="0"/>"#,
            definitions: #"""
            <groupdef id="lcd"><group id="lcd.def" x="-20" y="0"/></groupdef>
            <groupdef id="lcd.def"><layer id="back" x="0" y="0" w="20" h="20" image="red"/></groupdef>
            """#)
        XCTAssertEqual(pixels().at(10, 10)[3], 0, "parked before the group's origin, the drawer is closed")
    }

    func testABracedGUIDEndsAtItsBrace() {
        XCTAssertEqual(WinampModernComponentRegistry.kind(
            for: "guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6} (Media library)"), .library)
        XCTAssertEqual(WinampModernComponentRegistry.kind(
            for: "guid:{F0816D7B-FFFC-4343-80F2-E8199AA15CC3};video"), .video)
    }

    // MARK: - Fixture

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        func at(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(bytes[offset..<(offset + 4)])
        }
    }

    private func render(content: String, definitions: String = "") throws
        -> (WasabiSceneRenderer, () -> Pixels) {
        let xml = """
        <WasabiXML>
          <bitmap id="red" file="red.png"/>
          \(definitions)
          <container id="Main">
            <layout id="normal" w="40" h="40">
              \(content)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try makeWinampModernSkin(xml: xml, files: ["red.png": try Self.redPNG()])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return (renderer, {
            let (width, height) = (Int(renderer.canvasSize.width), Int(renderer.canvasSize.height))
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                renderer.draw(in: context)
            }
            return Pixels(bytes: bytes, width: width)
        })
    }

    private static func redPNG() throws -> Data {
        var pixels = [UInt8](repeating: 0, count: 280 * 40 * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels.replaceSubrange(index..<(index + 4), with: red)
        }
        let image = pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: 280, height: 40, bitsPerComponent: 8,
                      bytesPerRow: 280 * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(image)).representation(using: .png, properties: [:]))
    }
}
