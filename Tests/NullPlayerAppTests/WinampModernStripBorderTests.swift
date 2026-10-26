import CoreGraphics
import XCTest
@testable import NullPlayer

/// A measured standard frame's border is the opaque part of its `resize=` strips, not their tiles
/// (B260): Mad Magazine's strips are 39x37 tiles whose art is a 4-5px edge.
final class WinampModernStripBorderTests: XCTestCase {

    func testOpaqueBoundsIsTheArtNotTheTile() throws {
        let tile = try Self.image(width: 39, height: 37, opaque: CGRect(x: 35, y: 0, width: 4, height: 37))
        XCTAssertEqual(WasabiResourceCache.opaqueBounds(of: tile), CGRect(x: 35, y: 0, width: 4, height: 37))
        let empty = try Self.image(width: 8, height: 8, opaque: .zero)
        XCTAssertNil(WasabiResourceCache.opaqueBounds(of: empty))
    }

    /// The cut is the renderer's, negative offset included: art on the sheet's top row lands below
    /// the transparent space a `y="-5"` puts before it.
    func testTheCutPadsANegativeOffsetAsTheRendererDoes() throws {
        let sheet = try Self.image(width: 10, height: 10, opaque: CGRect(x: 0, y: 0, width: 10, height: 2))
        let cut = try XCTUnwrap(WasabiResourceCache.cut(sheet, attributes: ["y": "-5", "h": "10"]))
        XCTAssertEqual(WasabiResourceCache.opaqueBounds(of: cut), CGRect(x: 0, y: 5, width: 10, height: 2))
    }

    /// Geometry is the skin's to write: a value `Int(_:)` traps on, or a negative offset whose padding
    /// would outgrow the pixel budget, is ignored rather than crashing or allocating it.
    func testTheCutSurvivesHostileGeometry() throws {
        let sheet = try Self.image(width: 10, height: 10, opaque: CGRect(x: 0, y: 0, width: 10, height: 2))
        for attributes in [["x": "nan"], ["y": "inf"], ["w": "1e30"], ["h": "-1e30"], ["y": "-1e30"]] {
            XCTAssertNotNil(WasabiResourceCache.cut(sheet, attributes: attributes), "\(attributes)")
        }
        XCTAssertNil(WasabiResourceCache.padForNegativeOffset(sheet, attributes: ["y": "-20000000"]))
    }

    func testEveryEdgeMeasuresTheArtOverADeclaredSize() {
        let art: [String: CGRect] = [
            "l": CGRect(x: 0, y: 0, width: 4, height: 37),
            "r": CGRect(x: 35, y: 0, width: 4, height: 37),
            "t": CGRect(x: 0, y: 0, width: 39, height: 5),
            "b": CGRect(x: 0, y: 33, width: 39, height: 4),
        ]
        let border = WasabiStandardFrames.measuredBorder(in: Self.strips, group: { _ in nil },
                                                         bitmapOpaqueBounds: { art[$0] })
        XCTAssertEqual(border, .init(left: 4, top: 5, right: 4, bottom: 4))
    }

    func testAnUnreadableStripFallsBackToItsDeclaredSize() {
        let border = WasabiStandardFrames.measuredBorder(in: Self.strips, group: { _ in nil },
                                                         bitmapOpaqueBounds: { _ in nil })
        XCTAssertEqual(border, .init(left: 39, top: 0, right: 39, bottom: 37))
    }

    /// LCDx's strips are readable and wholly transparent: they draw no edge, so they are no border,
    /// and with no bottom edge the client still ends above the frame's status slot.
    func testATransparentStripIsNoBorderAndTheStatusSlotBoundsTheBottom() {
        let status = WalXMLNode(name: "LayoutStatus", attributes: ["x": "10", "y": "-17", "relaty": "1", "h": "15"],
                                location: WalSourceLocation(path: "/frame.xml"))
        let border = WasabiStandardFrames.measuredBorder(in: Self.strips + [status], group: { _ in nil },
                                                         bitmapOpaqueBounds: { _ in .zero })
        XCTAssertEqual(border, .init(left: 0, top: 0, right: 0, bottom: 17))
    }

    // MARK: - Fixture

    /// Mad Magazine's four strips, as `component.*` declares them.
    private static let strips: [WalXMLNode] = [
        ["x": "0", "y": "15", "w": "39", "image": "l", "resize": "left"],
        ["x": "-39", "y": "15", "relatx": "1", "image": "r", "resize": "right"],
        ["x": "39", "y": "0", "image": "t", "resize": "top"],
        ["x": "39", "y": "-37", "relaty": "1", "h": "37", "image": "b", "resize": "bottom"],
    ].map { WalXMLNode(name: "layer", attributes: $0, location: WalSourceLocation(path: "/frame.xml")) }

    /// A transparent `width`x`height` image with `opaque` (top-left origin) filled.
    private static func image(width: Int, height: Int, opaque: CGRect) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: opaque.minX, y: CGFloat(height) - opaque.maxY,
                            width: opaque.width, height: opaque.height))
        return try XCTUnwrap(context.makeImage())
    }
}
