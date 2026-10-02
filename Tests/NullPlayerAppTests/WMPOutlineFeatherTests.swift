import CoreGraphics
import XCTest
@testable import NullPlayer

/// W316: a keyed window's outline, antialiased at the backing scale. See `WMPOutlineFeather`.
final class WMPOutlineFeatherTests: XCTestCase {
    /// A keyed layer as the renderer hands it over: opaque grey wherever `inside` says, at `scale`
    /// device pixels to a skin pixel, so every edge is a staircase of whole skin pixels.
    private func layer(width: Int, height: Int, scale: Int = 2,
                       alpha: (Int, Int) -> UInt8) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * scale * height * scale * 4)
        for y in 0..<(height * scale) {
            for x in 0..<(width * scale) {
                let value = alpha(x / scale, y / scale)
                let offset = (y * width * scale + x) * 4
                // Premultiplied grey at half intensity.
                bytes[offset] = value / 2; bytes[offset + 1] = value / 2; bytes[offset + 2] = value / 2
                bytes[offset + 3] = value
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width * scale, height: height * scale,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * scale * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    /// Every alpha byte, top row first.
    private func alphas(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
    }

    private func feathered(_ image: CGImage, width: Int, height: Int,
                           scale: CGFloat = 2) -> CGImage {
        guard let feather = WMPOutlineFeather.feather(
            layers: [image], canvasSize: WMPSize(width: CGFloat(width), height: CGFloat(height)),
            backingScale: scale) else { return image }
        return WMPOutlineFeather.apply(feather, to: image)
    }

    /// `BlueCrush_MP7`'s flank: one pixel across for every five down. A kernel over the pixel grid
    /// trimmed one device pixel per step and left this standing; tracing the outline and
    /// smoothing along it turns each step into a ramp, so the rows of one step no longer share
    /// one edge.
    func testAShallowStaircaseBecomesARamp() throws {
        let width = 40, height = 60
        let image = try layer(width: width, height: height) { x, y in x < 10 + y / 5 ? 255 : 0 }
        let before = alphas(image), after = alphas(feathered(image, width: width, height: height))
        let deviceWidth = width * 2
        // Inside one step (skin rows 20-24, device rows 40-49), the old edge column is the same on
        // every row; after, the partial coverage moves across the rows of the step.
        let edgeColumn = (10 + 4) * 2 - 1
        let coverages = (40..<50).map { after[$0 * deviceWidth + edgeColumn] }
        XCTAssertTrue((40..<50).allSatisfy { before[$0 * deviceWidth + edgeColumn] == 255 })
        XCTAssertGreaterThan(Set(coverages).count, 3,
                             "one edge pixel's coverage varies down the step: \(coverages)")
        // The column is new at the top of the step, so its outer corner is there.
        XCTAssertLessThan(coverages.first!, coverages.last!,
                          "and falls toward the step's outer corner: \(coverages)")
        // Nothing more than a skin pixel from the outline moves.
        for y in 0..<(height * 2) {
            let edge = (10 + (y / 2) / 5) * 2
            for x in 0..<deviceWidth where abs(x - edge) > 3 {
                XCTAssertEqual(after[y * deviceWidth + x], before[y * deviceWidth + x],
                               "(\(x), \(y)) is not near the outline")
            }
        }
    }

    /// A straight edge already lies where the smoothed outline does.
    func testAStraightEdgeDoesNotMove() throws {
        let width = 40, height = 40
        let image = try layer(width: width, height: height) { x, _ in x < 20 ? 255 : 0 }
        let before = alphas(image), after = alphas(feathered(image, width: width, height: height))
        for y in 10..<70 {
            XCTAssertEqual(Array(after[(y * 80)..<(y * 80 + 80)]),
                           Array(before[(y * 80)..<(y * 80 + 80)]), "row \(y)")
        }
    }

    /// Smoothing alone halves a one-pixel line where it ends, closes a one-pixel slit, fades a
    /// 2x2 dot and fills a 2x2 hole — `Erektorset` lost every one-pixel line it has at 1x. Each of
    /// these keeps its pixels.
    func testSmallArtworkKeepsItsShape() throws {
        let width = 60, height = 60
        let shape: (Int, Int) -> UInt8 = { x, y in
            if x == 5, (5..<40).contains(y) { return 255 }              // a one-pixel line
            if (10..<12).contains(x), (5..<7).contains(y) { return 255 } // a 2x2 dot
            if (20..<55).contains(x), (20..<55).contains(y) {            // a block holding
                if x == 37, (25..<50).contains(y) { return 0 }           // a one-pixel slit
                if (28..<30).contains(x), (28..<30).contains(y) { return 0 } // and a 2x2 hole
                return 255
            }
            return 0
        }
        for scale in [1, 2] {
            let image = try layer(width: width, height: height, scale: scale, alpha: shape)
            let before = alphas(image)
            let after = alphas(feathered(image, width: width, height: height, scale: CGFloat(scale)))
            let deviceWidth = width * scale
            func check(_ xs: Range<Int>, _ ys: Range<Int>, _ what: String) {
                for skinY in ys { for skinX in xs {
                    for dy in 0..<scale { for dx in 0..<scale {
                        let index = (skinY * scale + dy) * deviceWidth + skinX * scale + dx
                        XCTAssertEqual(after[index], before[index], "\(what) at \(scale)x")
                    } }
                } }
            }
            check(5..<6, 5..<40, "the line")
            check(10..<12, 5..<7, "the dot")
            check(37..<38, 25..<50, "the slit")
            check(28..<30, 28..<30, "the hole")
        }
    }

    /// Fainter artwork is never removed: `corona` paints its own shadow at alpha 1-60 under its
    /// solid edge, and the feather only ever lowers a pixel that is at least half opaque.
    func testFaintArtworkIsNeverLowered() throws {
        let width = 40, height = 60
        let image = try layer(width: width, height: height) { x, y in
            if x < 10 + y / 5 { return 255 }
            return x < 14 + y / 5 ? 40 : 0
        }
        let before = alphas(image), after = alphas(feathered(image, width: width, height: height))
        for index in before.indices where before[index] > 0 && before[index] < 128 {
            XCTAssertGreaterThanOrEqual(after[index], before[index])
        }
    }

    // MARK: - Through the renderer

    /// A keyed diagonal body with a marquee scrolling inside it, at 2x.
    private func shapedMarqueeScene() async throws -> (WMPRenderer, WMPScene) {
        var rgba: [UInt8] = []
        for row in 0..<40 {
            for column in 0..<120 {
                rgba += column < 30 + row / 4 ? [255, 0, 255, 255] : [40, 60, 80, 255]
            }
        }
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="120" height="40" backgroundImage="body.png"
                         transparencyColor="#FF00FF">
              <TEXT id="meta" left="60" top="14" width="40" height="12" fontSize="10"
                    foregroundColor="#FFFFFF" value="MMMMMMMMMMMMMMMMMMMMMMMM"
                    scrolling="true" scrollingDelay="50" scrollingAmount="2"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("body.png", data: try WMPSkinTestSupport.encodedImage(
                width: 120, height: 40, rgba: rgba)),
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        return (WMPRenderer(imageStore: WMPImageStore(provider: skin.archive)), scene)
    }

    /// **A repaint draws over the unfeathered frame.** The feather is read off the opaque set, so
    /// feathering a feathered frame would erode the outline a little more on every repaint — a
    /// marquee repaints twelve times a second.
    func testRepaintsNeverErodeTheOutline() async throws {
        let (renderer, scene) = try await shapedMarqueeScene()
        let dirty = try XCTUnwrap(renderer.animationCadence(for: scene)).bounds
        let whole = try await renderer.render(scene: scene, backingScale: 2, clock: 0)
        XCTAssertNotNil(whole.outlineFeather, "the diagonal is feathered")
        let hard = try await renderer.render(scene: scene, backingScale: 2,
                                             featheringOutline: false)
        XCTAssertNotEqual(alphas(whole.image), alphas(hard.image))
        var frame = whole
        for step in 1...5 {
            frame = try await renderer.render(scene: scene, backingScale: 2,
                                              clock: Double(step) * 0.37,
                                              reusing: frame, dirty: dirty)
            XCTAssertFalse(frame.alphaChanged, "a marquee over opaque art leaves the outline alone")
        }
        XCTAssertEqual(alphas(frame.image), alphas(whole.image),
                       "five repaints later the outline is the one the first render drew")
    }

    /// `WMPHostedFrameTemplate` assembles pieces whose edges meet the client hole, so its renders
    /// opt out — and an opted-out render is the hard outline, with nothing kept for a repaint.
    func testAnOptedOutRenderIsTheHardOutline() async throws {
        let (renderer, scene) = try await shapedMarqueeScene()
        let hard = try await renderer.render(scene: scene, backingScale: 2, featheringOutline: false)
        XCTAssertNil(hard.outlineFeather)
        XCTAssertNil(hard.unfeatheredImage)
    }
}
