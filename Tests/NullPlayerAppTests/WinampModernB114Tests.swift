import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B114 — a `desktopalpha="0"` layout has no per-pixel alpha, so what the skin paints is opaque and
/// what it does not paint is not there at all.
///
/// Reported 2026-09-04 on WMP11-BlueVU as *"missing backgrounds on the timer and track display"*.
/// The display is not missing a background — it never had one. The three bitmaps that cover that
/// area (`glass_bg_left_left.png`, `glass_bg_left_right.png`, `glass_bg_right.png`) are **alpha 0 in
/// every pixel**, deliberately, and `Glass.Left` paints a translucent sheen over them. With nothing
/// behind it the sheen composited over the window's own light backing; in Winamp it composites over
/// black, because `<layout id="normal" desktopalpha="0">` means no per-pixel alpha. Over the whole
/// reported area **9829 of 9831** changed pixels were *partially* transparent and only 2 were empty,
/// which is what makes this a composite against the wrong ground rather than a missing bitmap.
///
/// **It is a shape, not a fill.** The first fix filled the layout's rect black and let the
/// `sysregion` cut carve it, and it blacked out the gap between EPS High-End's speaker feet. That
/// skin declares its two speakers from the *same* artwork (`background="speaker"`) with
/// `desktopalpha="0"` on the left and `desktopalpha="1"` on the right — an author slip that is also
/// the control experiment, because the two are meant to look identical and do in Winamp. They can
/// only be identical if a pixel the skin left empty stays **outside the window** rather than going
/// black. So the rule is Win32's region: non-zero alpha is inside and opaque, alpha 0 is outside.
final class WinampModernB114Tests: XCTestCase {

    // MARK: - The report

    /// The defect in one assertion, and the reported shape is a *translucent* pixel rather than an
    /// empty one: WMP11-BlueVU's sheen over its deliberately empty spacers. It has to land on black
    /// and end up opaque, not on whatever is behind the window.
    func testATranslucentPixelBecomesOpaqueOverBlack() throws {
        let lit = try makeScene(layoutAttributes: #"desktopalpha="0""#, resources: Self.sheenBitmap,
                                markup: Self.sheenLayer, art: Self.sheenArt)
        let over = try XCTUnwrap(lit.pixel(x: 30, y: 20))
        XCTAssertEqual(Int(over.alpha), 255, "the painted pixel is part of an opaque window")
        XCTAssertEqual(Int(over.red), 180 * 112 / 255, accuracy: 3,
                       "180 at 112/255 over black, which is the sheen the skin drew")

        let unbacked = try makeScene(layoutAttributes: "", resources: Self.sheenBitmap,
                                     markup: Self.sheenLayer, art: Self.sheenArt)
        let alone = try XCTUnwrap(unbacked.pixel(x: 30, y: 20))
        XCTAssertEqual(Int(alone.alpha), 112, "and without the flag it is still just a sheen")
    }

    /// The EPS High-End case, which is what makes this a region rather than a fill: a pixel the skin
    /// never painted stays **out** of the window. Filling the layout's rect black blacked out the gap
    /// between that skin's speaker feet, and its other speaker — same artwork, `desktopalpha="1"` —
    /// is the control that says the two must match.
    func testAnUnpaintedPixelStaysOutsideTheWindow() throws {
        let scene = try makeScene(
            layoutAttributes: #"desktopalpha="0""#,
            resources: Self.sheenBitmap,
            markup: #"<layer id="sheen" x="0" y="0" w="60" h="40" image="sheen" alpha="112"/>"#,
            art: Self.sheenArt
        )
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 30, y: 20)).alpha), 255,
                       "the half the skin painted is opaque")
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 90, y: 20)).alpha), 0,
                       "and the half it did not is not there at all")
    }

    // MARK: - The guards

    /// A layout that says nothing keeps the per-pixel alpha it has always had. Most of the corpus is
    /// this case and none of it may grow a rectangle.
    func testALayoutThatDeclaresNoDesktopAlphaStaysTransparent() throws {
        let scene = try makeScene(layoutAttributes: "")
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 30, y: 20)).alpha), 0)
    }

    /// `desktopalpha="1"` is the *opt in* to per-pixel alpha, so it is emphatically not a backing.
    func testADesktopAlphaOneLayoutStaysTransparent() throws {
        let scene = try makeScene(layoutAttributes: #"desktopalpha="1""#)
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 30, y: 20)).alpha), 0)
    }

    /// A `sysregion` cut still takes the window away, backing and all — the shape the skin declares
    /// and the shape its alpha implies are the same region, and the cut lands on the finished
    /// picture either way.
    func testASysregionCutStillTakesThePaintedWindowAway() throws {
        let scene = try makeScene(
            layoutAttributes: #"desktopalpha="0""#,
            resources: Self.sheenBitmap + #"<bitmap id="bite" file="bite.png"/>"#,
            markup: Self.sheenLayer
                + #"<layer id="bite" x="0" y="0" w="60" h="40" image="bite" sysregion="-2"/>"#,
            art: Self.sheenArt.merging(["bite.png": Self.solidPNG(red: 255, green: 255, blue: 255)]) { a, _ in a }
        )
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 30, y: 20)).alpha), 0,
                       "the region took this half of the window away")
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 90, y: 20)).alpha), 255,
                       "and the half it kept is opaque")
    }

    /// The buffer the opaque path renders through is snapped to the caller's device grid, so the
    /// picture that comes back is the same one an ordinary draw produces — pixel for pixel, at 2x.
    func testTheOpaquePathIsPixelExactAtRetinaScale() throws {
        let scene = try makeScene(layoutAttributes: #"desktopalpha="0""#, resources: Self.sheenBitmap,
                                  markup: Self.sheenLayer, art: Self.sheenArt)
        let plain = try makeScene(layoutAttributes: "", resources: Self.sheenBitmap,
                                  markup: Self.sheenLayer, art: Self.sheenArt)
        let opaque = try XCTUnwrap(scene.pixel(x: 30, y: 20, scale: 2))
        let reference = try XCTUnwrap(plain.pixel(x: 30, y: 20, scale: 2))
        XCTAssertEqual(Int(opaque.alpha), 255)
        XCTAssertEqual(Int(opaque.red), Int(reference.red), accuracy: 1,
                       "the colours are untouched — only the alpha channel is promoted")
    }

    // MARK: - Fixture

    /// WMP11-BlueVU's shape: a translucent sheen laid over the whole window and nothing beneath it.
    private static let sheenBitmap = #"<bitmap id="sheen" file="sheen.png"/>"#
    private static let sheenLayer = #"<layer id="sheen" x="0" y="0" w="120" h="40" image="sheen" alpha="112"/>"#
    private static let sheenArt = ["sheen.png": solidPNG(red: 180, green: 180, blue: 180)]

    private struct Scene {
        let renderer: WasabiSceneRenderer

        func pixel(x: Int, y: Int, scale: Int = 1) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
            let width = Int(renderer.canvasSize.width) * scale
            let height = Int(renderer.canvasSize.height) * scale
            guard x >= 0, x * scale < width, y >= 0, y * scale < height else { return nil }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = pixels.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context else { return nil }
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            renderer.invalidateSceneCache()
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = saved
            // The buffer is bottom-up and the renderer draws the scene top-down, so a scene row is
            // read from the far end.
            let offset = ((height - 1 - y * scale) * width + x * scale) * 4
            return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
        }
    }

    private func makeScene(layoutAttributes: String,
                           resources: String = "",
                           markup: String = "",
                           art: [String: Data] = [:]) throws -> Scene {
        var files: [String: Data] = art
        files["skin.xml"] = Data("""
        <WasabiXML>
          <elements>\(resources)</elements>
          <container id="Main">
            <layout id="normal" w="120" h="40" \(layoutAttributes)>
        \(markup)
            </layout>
          </container>
        </WasabiXML>
        """.utf8)

        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(files: files))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return Scene(renderer: renderer)
    }

    private func makeArchive(files: [String: Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB114Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B114-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, payload) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private static func solidPNG(red: UInt8, green: UInt8, blue: UInt8) -> Data {
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB,
                                              bytesPerRow: 32, bitsPerPixel: 32)!
        var components = [Int(red), Int(green), Int(blue), 255]
        for y in 0..<8 {
            for x in 0..<8 {
                representation.setPixel(&components, atX: x, y: y)
            }
        }
        return representation.representation(using: .png, properties: [:])!
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 200
        var volume: Double = 0.5
        var balance: Double = 0
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
