import AppKit
import XCTest
@testable import NullPlayer

/// Two ways a `.wal` window drew less than its skin declares.
///
/// - **A layout's backing.** DDtank Glass's equalizer and about window are
///   `drawbackground="0" desktopalpha="1" background="eq.main" alphabackground="eq.main"`, and the
///   renderer obeyed the flag on the layout: the controls drew on the bare desktop where the skin's
///   own preview shows a glass panel. A layout paints its backing; a `desktopalpha="1"` layout paints
///   its `alphabackground` (Fuzzy Muffins' `background` is the opaque mask variant). The flag still
///   holds for a group — BLAKK's region map stays off its display.
/// - **A negative bitmap offset.** hm_Touch ships its timer digits as a one-row sheet declared
///   `y="-30" h="60"`, which puts them on a bitmap font's digit row. Clamped to 0, the sheet was one
///   row tall and the player's big timer drew nothing.
final class WinampModernLayoutBackingTests: XCTestCase {

    private static let red: [UInt8] = [255, 0, 0, 255]
    private static let blue: [UInt8] = [0, 0, 255, 255]

    func testALayoutPaintsItsBackingDespiteDrawBackgroundZero() throws {
        let pixels = try render(layout: #"drawbackground="0" background="red""#)
        XCTAssertEqual(pixels.at(10, 10), Self.red)
    }

    func testADesktopAlphaLayoutPaintsItsAlphaBackground() throws {
        let pixels = try render(layout: #"drawbackground="0" desktopalpha="1" background="red" alphabackground="blue""#)
        XCTAssertEqual(pixels.at(10, 10), Self.blue)
    }

    func testAnOpaqueLayoutKeepsItsBackground() throws {
        let pixels = try render(layout: #"background="red" alphabackground="blue""#)
        XCTAssertEqual(pixels.at(10, 10), Self.red)
    }

    /// The flag is a group's, and it still holds there.
    func testAGroupStillHonoursDrawBackgroundZero() throws {
        let pixels = try render(layout: "",
                                content: #"<group id="g" x="0" y="0" w="40" h="40" background="red" drawbackground="0"/>"#)
        XCTAssertEqual(pixels.at(10, 10)[3], 0)
    }

    /// A one-row digit sheet declared one row above itself draws its digits.
    func testANegativeBitmapOffsetPadsTheSheet() throws {
        let content = #"<text id="clock" x="0" y="0" w="40" h="10" font="nums" valign="top" align="left" text="00"/>"#
        let pixels = try render(layout: "", content: content,
                                fontSource: #"<bitmap id="nums.source" file="digits.png" x="0" y="-10" w="160" h="20"/>"#)
        XCTAssertEqual(pixels.at(4, 5), [255, 255, 255, 255], "the 0 glyph is drawn")
    }

    func testPaddingIgnoresARelativeOffset() throws {
        let image = try XCTUnwrap(Self.image(width: 4, height: 4, rgba: Self.red))
        XCTAssertNil(WasabiResourceCache.padForNegativeOffset(image, attributes: ["x": "-2", "relatx": "1"]))
        let padded = try XCTUnwrap(WasabiResourceCache.padForNegativeOffset(image, attributes: ["y": "-3"]))
        XCTAssertEqual(padded.height, 7)
        XCTAssertEqual(padded.width, 4)
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

    private func render(layout: String, content: String = "", fontSource: String = "") throws -> Pixels {
        let xml = """
        <WasabiXML>
          <bitmap id="red" file="red.png"/>
          <bitmap id="blue" file="blue.png"/>
          \(fontSource)
          <bitmapfont id="nums" file="nums.source" charwidth="10" charheight="10" hspacing="0"/>
          <container id="Main">
            <layout id="normal" w="40" h="40" \(layout)>
              \(content)
            </layout>
          </container>
        </WasabiXML>
        """
        // One row of 16 ten-pixel digit cells, each inked in its middle 8x8: the bitmap font reads
        // digits from row 1, which only exists once the declared `y="-10"` pads the sheet.
        let digits = Self.image(width: 160, height: 10, rgba: [255, 255, 255, 255]) { x, y in
            (1...8).contains(x % 10) && (1...8).contains(y)
        }
        let loaded = try makeWinampModernSkin(xml: xml, files: [
            "red.png": try png(Self.image(width: 40, height: 40, rgba: Self.red)),
            "blue.png": try png(Self.image(width: 40, height: 40, rgba: Self.blue)),
            "digits.png": try png(digits),
        ])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let (width, height) = (Int(renderer.canvasSize.width), Int(renderer.canvasSize.height))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        // Drawn inside the closure: the context's pointer into `bytes` is only valid there.
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            renderer.draw(in: context)
            return true
        }
        XCTAssertTrue(drawn)
        return Pixels(bytes: bytes, width: width)
    }

    private static func image(width: Int, height: Int, rgba: [UInt8],
                              ink: ((Int, Int) -> Bool)? = nil) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where ink?(x, y) ?? true {
                pixels.replaceSubrange((y * width + x) * 4..<((y * width + x) * 4 + 4), with: rgba)
            }
        }
        return pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    private func png(_ image: CGImage?) throws -> Data {
        try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(image)).representation(using: .png, properties: [:]))
    }
}
