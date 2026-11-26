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

    /// With `relatx` a negative offset counts in from the far edge (Wurlitzer_v2's right corner,
    /// B422); a positive one stays absolute (CardiumII's shadow).
    func testARelativeNegativeOffsetCutsFromTheFarEdge() throws {
        let sheet = try Self.image(width: 10, height: 4, opaque: CGRect(x: 6, y: 0, width: 4, height: 4))
        let right = try XCTUnwrap(WasabiResourceCache.cut(sheet, attributes: ["x": "-4", "relatx": "1", "w": "4"]))
        XCTAssertEqual(WasabiResourceCache.opaqueBounds(of: right), CGRect(x: 0, y: 0, width: 4, height: 4))
        let absolute = try XCTUnwrap(WasabiResourceCache.cut(sheet, attributes: ["x": "6", "relatx": "1", "w": "4"]))
        XCTAssertEqual(WasabiResourceCache.opaqueBounds(of: absolute), CGRect(x: 0, y: 0, width: 4, height: 4))
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
                                                         bitmapOpaqueBounds: { id, _ in art[id] })
        XCTAssertEqual(border, .init(left: 4, top: 5, right: 4, bottom: 4))
    }

    func testAnUnreadableStripFallsBackToItsDeclaredSize() {
        let border = WasabiStandardFrames.measuredBorder(in: Self.strips, group: { _ in nil },
                                                         bitmapOpaqueBounds: { _, _ in nil })
        XCTAssertEqual(border, .init(left: 39, top: 0, right: 39, bottom: 37))
    }

    /// LCDx's strips are readable and wholly transparent: they draw no edge, so they are no border,
    /// and with no bottom edge the client still ends above the frame's status slot.
    func testATransparentStripIsNoBorderAndTheStatusSlotBoundsTheBottom() {
        let status = WalXMLNode(name: "LayoutStatus", attributes: ["x": "10", "y": "-17", "relaty": "1", "h": "15"],
                                location: WalSourceLocation(path: "/frame.xml"))
        let border = WasabiStandardFrames.measuredBorder(in: Self.strips + [status], group: { _ in nil },
                                                         bitmapOpaqueBounds: { _, _ in .zero })
        XCTAssertEqual(border, .init(left: 0, top: 0, right: 0, bottom: 17))
    }

    /// Blogz's status slot sits 42px up over a 28px bottom strip: the client ends above the slot, not
    /// at the strip, or its playlist covers the Add/Rem/Sel bar drawn there (B482).
    func testTheStatusSlotBoundsTheBottomOverAThinnerStrip() {
        let status = WalXMLNode(name: "LayoutStatus", attributes: ["x": "10", "y": "-42", "relaty": "1", "h": "17"],
                                location: WalSourceLocation(path: "/frame.xml"))
        let art: [String: CGRect] = ["b": CGRect(x: 0, y: 9, width: 39, height: 28)]
        let border = WasabiStandardFrames.measuredBorder(in: Self.strips + [status], group: { _ in nil },
                                                         bitmapOpaqueBounds: { id, _ in art[id] ?? .zero })
        XCTAssertEqual(border.bottom, 42)
    }

    /// Center_Fresh's frame is one nine-slice `<grid>`: its edges are the strips, trimmed against the
    /// grid's own flat `middle`, the far ones measured in from their cut's size (B465). Measured as
    /// no strips at all, the border was zero and every hosted window opened bare.
    func testAGridFrameIsMeasuredByItsEdges() {
        let grid = WalXMLNode(name: "grid", attributes: [
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
            "top": "t", "left": "l", "right": "r", "bottom": "b", "middle": "m",
        ], location: WalSourceLocation(path: "/frame.xml"))
        let group = WalXMLNode(name: "group", attributes: ["id": "frame.group"],
                               location: WalSourceLocation(path: "/frame.xml"))
        let sizes: [String: CGSize] = ["t": CGSize(width: 325, height: 50), "l": CGSize(width: 21, height: 133),
                                       "r": CGSize(width: 20, height: 133), "b": CGSize(width: 325, height: 50)]
        // Whole tiles, then trimmed of the black rows the panel shares with `m`.
        let border = WasabiStandardFrames.measuredBorder(
            in: [group], group: { $0 == "frame.group" ? [grid] : nil },
            bitmapSize: { sizes[$0] },
            bitmapOpaqueBounds: { id, body in
                switch (id, body) {
                case ("t", "m"): CGRect(x: 0, y: 0, width: 325, height: 40)
                case ("b", "m"): CGRect(x: 0, y: 11, width: 325, height: 39)
                default: sizes[id].map { CGRect(origin: .zero, size: $0) }
                }
            })
        XCTAssertEqual(border, .init(left: 21, top: 40, right: 20, bottom: 39))

        // A grid that does not span the window draws its far edges inside it: they are no border.
        var inset = grid.attributes
        inset["relatw"] = nil; inset["relath"] = nil; inset["w"] = "100"; inset["h"] = "80"
        let short = WalXMLNode(name: "grid", attributes: inset, location: grid.location)
        let shortBorder = WasabiStandardFrames.measuredBorder(
            in: [short], group: { _ in nil }, bitmapSize: { sizes[$0] },
            bitmapOpaqueBounds: { id, _ in sizes[id].map { CGRect(origin: .zero, size: $0) } })
        XCTAssertEqual(shortBorder, .init(left: 21, top: 50, right: 0, bottom: 0))

        // A grid inset from the window's edges is a panel inside the client (Morlock's modal frame
        // holds the engine's `wasabi.panel` 35-50px in): it is no border at all.
        let panel = WalXMLNode(name: "group", attributes: ["id": "wasabi.panel", "x": "35", "y": "50",
                                                           "w": "-70", "h": "-80", "relatw": "1", "relath": "1"],
                               location: grid.location)
        let panelBorder = WasabiStandardFrames.measuredBorder(
            in: [panel], group: { $0 == "wasabi.panel" ? [grid] : nil }, bitmapSize: { sizes[$0] },
            bitmapOpaqueBounds: { id, _ in sizes[id].map { CGRect(origin: .zero, size: $0) } })
        XCTAssertEqual(panelBorder, .init())
    }

    /// Trance_Critic_v2_0's `frame-tm.png` is a short edge and then rows of its navy base texture
    /// (B464): only rows of the frame's flat body colour are trimmed, and a textured body trims none.
    func testRowsOfTheFlatBaseTextureAreBodyNotBorder() throws {
        let edge = (r: 0.8, g: 0.8, b: 1.0), navy = (r: 0.0, g: 0.2, b: 0.4)
        let strip = try Self.bands(width: 10, rows: [(8, edge), (22, navy)])
        let body = try Self.bands(width: 4, rows: [(4, navy)])
        XCTAssertEqual(WasabiResourceCache.edgeBounds(of: strip), CGRect(x: 0, y: 0, width: 10, height: 30))
        XCTAssertEqual(WasabiResourceCache.edgeBounds(of: strip, body: body), CGRect(x: 0, y: 0, width: 10, height: 8))
        let texture = try Self.bands(width: 4, rows: [(2, navy), (2, edge)])
        XCTAssertEqual(WasabiResourceCache.edgeBounds(of: strip, body: texture), CGRect(x: 0, y: 0, width: 10, height: 30))
    }

    /// The trim never takes the top past the title: canum draws its title over a plain body-coloured
    /// strip, and pumaSKIN's title group states no height, so its title text (`y=0 h=20`) decides.
    func testTheBodyTrimStopsAtTheTitle() {
        let location = WalSourceLocation(path: "/frame.xml")
        let top = WalXMLNode(name: "layer", attributes: ["x": "30", "y": "0", "image": "t", "resize": "top"],
                             location: location)
        let bounds: (String, String?) -> CGRect? = { _, body in CGRect(x: 0, y: 0, width: 30, height: body != nil ? 8 : 30) }
        func border(title: [String: String], text: [WalXMLNode] = []) -> Double {
            let node = WalXMLNode(name: "group", attributes: title.merging(["id": "wasabi.titlebar"]) { $1 },
                                  location: location)
            return WasabiStandardFrames.measuredBorder(in: [top, node], group: { $0 == "wasabi.titlebar" ? text : nil },
                                                       frameBody: "body", bitmapOpaqueBounds: bounds).top
        }
        XCTAssertEqual(border(title: ["y": "0", "h": "18"]), 18)
        let titleText = WalXMLNode(name: "text", attributes: ["id": "window.titlebar.title", "y": "0", "h": "20"],
                                   location: location)
        XCTAssertEqual(border(title: ["y": "5"], text: [titleText]), 25)
        XCTAssertEqual(border(title: ["y": "5"]), 8, "no title height anywhere: the trim stands")
    }

    // MARK: - Fixture

    /// An opaque image of horizontal colour bands, top first.
    private static func bands(width: Int, rows: [(Int, (r: Double, g: Double, b: Double))]) throws -> CGImage {
        let height = rows.reduce(0) { $0 + $1.0 }
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var top = 0
        for (count, colour) in rows {
            context.setFillColor(red: colour.r, green: colour.g, blue: colour.b, alpha: 1)
            context.fill(CGRect(x: 0, y: height - top - count, width: width, height: count))
            top += count
        }
        return try XCTUnwrap(context.makeImage())
    }

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
