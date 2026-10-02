import AppKit
import XCTest
@testable import NullPlayer

/// Golden-image regression cover for a keyed `.wmz` window's outline (W316, `WMPOutlineFeather`).
///
/// Every fixture is rendered **twice at each backing scale** — the hard outline the colour key
/// cuts (`featheringOutline: false`) and the feathered one the app presents — and both are compared
/// against committed PNGs. The hard golden pins what the key and the 2x resample produce, so a
/// change to keying or upscaling fails there; the feathered golden pins what the feather makes of
/// it, so a change to the feather fails there. An improvement fails exactly like a regression:
/// regenerate, read the comparison sheet, and commit both.
///
/// The fixtures are **synthetic** — keyed artwork built here in code, never a real skin, which
/// this repository may not ship (`wmp-skin-guide` § *Phase 7 hardening contracts*) — and each one
/// stands for an outline the corpus taught the feather about:
///
/// | Scene | What it stands for |
/// |---|---|
/// | `shallow-flank` | `BlueCrush_MP7`'s sides, one pixel across for every five down, with a pale one-pixel rim — the report |
/// | `round-body` | `AlienMorph`'s and `corona`'s curves |
/// | `diagonal` | `xXx_night_vision_redx`'s 45° edges |
/// | `small-artwork` | `Erektorset`'s one-pixel lines and slits, a 2x2 dot and hole, and square corners, which must not move |
///
/// Regenerate after an *intended* change, and read `<scene>-compare@2x.png` before committing:
///
/// ```sh
/// WMP_OUTLINE_GOLDEN_UPDATE=1 swift test --filter WMPOutlineGoldenImageTests
/// ```
///
/// An update also writes `<scene>-compare@<n>x.png` beside the goldens: hard | feathered, enlarged,
/// over a dark and a light ground. A failing comparison writes `<golden>.actual.png` and a sheet
/// `<golden>.compare.png` (golden | actual | differing pixels in red) to `WMP_OUTLINE_GOLDEN_DUMP`,
/// or the temporary directory.
final class WMPOutlineGoldenImageTests: XCTestCase {
    /// Per-channel slack for a resampler or rasterizer that rounds differently on another OS.
    private static let channelTolerance = 2
    private static let size = 64

    // MARK: - The scenes

    /// The body is left of `x = 14 + y / 5` and right of `x = 50 - y / 5`, under a rounded top;
    /// its outermost pixel is a pale rim, the artist's antialiasing against a light background.
    func testShallowFlankGolden() async throws {
        try await assertGoldens(named: "shallow-flank") { x, y in
            let left = 14 - y / 5, right = 50 + y / 5
            let top = 6 + abs(x - 32) * abs(x - 32) / 40
            guard x >= left, x < right, y >= top, y < 60 else { return nil }
            let rim = x == left || x == right - 1 || y == top
            return rim ? [240, 228, 236] : [232, 160, 196]
        }
    }

    func testRoundBodyGolden() async throws {
        try await assertGoldens(named: "round-body") { x, y in
            let dx = Double(x) - 31.5, dy = Double(y) - 31.5
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance < 27 else { return nil }
            return distance > 24 ? [70, 90, 190] : [190, 200, 230]
        }
    }

    func testDiagonalGolden() async throws {
        try await assertGoldens(named: "diagonal") { x, y in
            guard x + y >= 24, x + y < 104, x - y < 40, y - x < 40 else { return nil }
            return [20, 60, 20]
        }
    }

    /// Nothing here may move: every feature is smaller than a staircase step, or a square corner.
    func testSmallArtworkGolden() async throws {
        try await assertGoldens(named: "small-artwork") { x, y in
            if x == 4, (4..<40).contains(y) { return [250, 220, 0] }                // one-pixel line
            if (9..<11).contains(x), (4..<6).contains(y) { return [250, 220, 0] }   // 2x2 dot
            if (16..<60).contains(x), (16..<60).contains(y) {                       // square block
                if x == 38, (22..<54).contains(y) { return nil }                    // one-pixel slit
                if (26..<28).contains(x), (26..<28).contains(y) { return nil }      // 2x2 hole
                return [250, 220, 0]
            }
            return nil
        }
    }

    // MARK: - Rendering

    /// `color` is the artwork per skin pixel; nil is the magenta key.
    private func assertGoldens(named name: String, color: (Int, Int) -> [UInt8]?,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        var rgba: [UInt8] = []
        for y in 0..<Self.size {
            for x in 0..<Self.size { rgba += (color(x, y) ?? [255, 0, 255]) + [255] }
        }
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="\(Self.size)" height="\(Self.size)"
                         backgroundImage="body.png" transparencyColor="#FF00FF"/></THEME>
            """.utf8)),
            WMPTestArchiveEntry("body.png", data: try WMPSkinTestSupport.encodedImage(
                width: Self.size, height: Self.size, rgba: rgba)),
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let renderer = WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
        for scale in [1, 2] {
            var rendered: [Bool: CGImage] = [:]
            for feathered in [false, true] {
                let image = try await renderer.render(scene: scene, backingScale: CGFloat(scale),
                                                      featheringOutline: feathered).image
                rendered[feathered] = image
                try compare(image, golden: "\(name)-\(feathered ? "feathered" : "hard")@\(scale)x",
                            file: file, line: line)
            }
            if Self.updating, let hard = rendered[false], let soft = rendered[true] {
                try Self.writePNG(Self.sheet([hard, soft], zoom: 8 / scale),
                                  to: Self.goldensDirectory
                                    .appendingPathComponent("\(name)-compare@\(scale)x.png"))
            }
        }
    }

    // MARK: - Comparison

    private static var updating: Bool {
        ProcessInfo.processInfo.environment["WMP_OUTLINE_GOLDEN_UPDATE"] != nil
    }

    private func compare(_ image: CGImage, golden name: String,
                         file: StaticString, line: UInt) throws {
        let url = Self.goldensDirectory.appendingPathComponent("\(name).png")
        if Self.updating {
            try FileManager.default.createDirectory(at: Self.goldensDirectory,
                                                    withIntermediateDirectories: true)
            try Self.writePNG(image, to: url)
            print("GOLDEN wrote \(url.path)")
            return
        }
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let expectedImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("No golden '\(name)'. Regenerate with WMP_OUTLINE_GOLDEN_UPDATE=1.",
                           file: file, line: line)
        }
        guard expectedImage.width == image.width, expectedImage.height == image.height else {
            return XCTFail("Golden '\(name)' is \(expectedImage.width)x\(expectedImage.height), "
                           + "the render \(image.width)x\(image.height).", file: file, line: line)
        }
        let actual = WMPSkinTestSupport.premultipliedRGBA(image)
        let expected = WMPSkinTestSupport.premultipliedRGBA(expectedImage)
        var differing = Set<Int>()
        for index in stride(from: 0, to: actual.count, by: 4) where (0..<4).contains(where: {
            abs(Int(actual[index + $0]) - Int(expected[index + $0])) > Self.channelTolerance
        }) { differing.insert(index / 4) }
        guard !differing.isEmpty else { return }

        let directory = URL(fileURLWithPath: ProcessInfo.processInfo
            .environment["WMP_OUTLINE_GOLDEN_DUMP"] ?? NSTemporaryDirectory(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.writePNG(image, to: directory.appendingPathComponent("\(name).actual.png"))
        var marked = expected
        for pixel in differing {
            marked[pixel * 4] = 255; marked[pixel * 4 + 1] = 0
            marked[pixel * 4 + 2] = 0; marked[pixel * 4 + 3] = 255
        }
        let diff = try WMPSkinTestSupport.image(premultipliedRGBA: marked, width: image.width,
                                                height: image.height)
        try Self.writePNG(Self.sheet([expectedImage, image, diff], zoom: 16 / max(1, image.width / 64)),
                          to: directory.appendingPathComponent("\(name).compare.png"))
        XCTFail("Golden '\(name)': \(differing.count) pixel(s) differ. Wrote \(directory.path)"
                + "/\(name).compare.png (golden | actual | diff). Regenerate with "
                + "WMP_OUTLINE_GOLDEN_UPDATE=1 once the change is intended.", file: file, line: line)
    }

    // MARK: - Images

    /// The goldens live beside the tests rather than in a resource bundle, so an update run writes
    /// straight into the working tree and `git diff` shows the change being committed.
    private static var goldensDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Goldens/WMPOutline", isDirectory: true)
    }

    /// The images side by side, enlarged without smoothing, over a dark ground and below that a
    /// light one — the two a desktop shows an outline against.
    private static func sheet(_ images: [CGImage], zoom: Int) throws -> CGImage {
        let zoom = max(1, zoom), gap = 8
        let cell = CGSize(width: images[0].width * zoom, height: images[0].height * zoom)
        let width = images.count * Int(cell.width) + (images.count - 1) * gap
        let height = Int(cell.height) * 2 + gap
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (row, ground) in [(1, CGFloat(0.12)), (0, CGFloat(0.9))] {
            for (column, image) in images.enumerated() {
                let frame = CGRect(x: CGFloat(column) * (cell.width + CGFloat(gap)),
                                   y: CGFloat(row) * (cell.height + CGFloat(gap)),
                                   width: cell.width, height: cell.height)
                context.setFillColor(red: ground, green: ground, blue: ground, alpha: 1)
                context.fill(frame)
                context.draw(image, in: frame)
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png,
                                                                                  properties: [:]))
        try data.write(to: url)
    }
}
