import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Golden-image regression cover for the `.wal` render sweep (backlog B10).
///
/// Every rendering phase before this one proved itself the same way: dump all seventeen installed
/// skins to PNG, look at them, and compare by eye against the previous run. That sweep is manual,
/// needs third-party artwork nothing in this repository may ship, and catches a third skin
/// regressing only if someone happens to notice. Nothing in CI looked at a pixel except
/// `WinampModernRenderPixelTests`, which asserts four points of three scenes.
///
/// These fixtures are **synthetic** — an atlas of flat colour blocks and a bitmap font of flat
/// colour glyph cells, built here in code — so the goldens can be committed, and they exercise the
/// four mechanisms the sweep exists to protect:
///
/// | Scene | What a regression here looks like in a real skin |
/// |---|---|
/// | `group-clipping` | Defix's cassette reels spilling 53px over the song ticker below them |
/// | `frame-collapsed` | cPro-Bento's closed mini view painting its strip over the volume slider |
/// | `animated-layer` | a meter piling on frame 0, or cutting the wrong row of its sheet |
/// | `text-placement` | a readout pinned to `valign="top"`, or a right-aligned run off its box |
/// | `alpha-stack` | Defix's Kbps / KHz / Channels readouts printed on top of each other (Phase 25.1) |
///
/// Each scene is a whole rendered canvas compared against a committed PNG, not a handful of probe
/// points: a defect anywhere in the frame fails the test, which is the property the manual sweep had
/// and the point assertions do not.
///
/// Regenerate after an *intended* rendering change, and read the diff before committing it:
///
/// ```sh
/// WINAMP_MODERN_GOLDEN_UPDATE=1 swift test --filter WinampModernGoldenImageTests
/// ```
///
/// A failing comparison writes `<scene>.actual.png` and `<scene>.diff.png` (differing pixels in red)
/// next to the goldens' directory in `WINAMP_MODERN_GOLDEN_DUMP`, or the temporary directory.
final class WinampModernGoldenImageTests: XCTestCase {

    /// Per-channel slack. Every fixture blits flat colour at natural size, so an exact match is the
    /// expectation; this only absorbs a CoreGraphics resampler that rounds an edge differently on a
    /// different OS version, and is far tighter than any real defect.
    private static let channelTolerance = 2

    private static let canvas = CGSize(width: 64, height: 64)

    // MARK: - The scenes

    /// A `<group>` whose box the skin declared is a window: its children stop at its edge.
    /// The red sprite is twice the group's height and must paint only the top half of it; the blue
    /// one sits inside a `fitparent` group, whose clip is the layout's own box, so it paints whole.
    func testGroupClippingGolden() throws {
        try assertGolden(named: "group-clipping", xml: """
        \(Self.elements)
          <container id="Main">
            <layout id="normal" w="64" h="64">
              <group id="sized" x="0" y="0" w="32" h="16">
                <layer id="overhang" image="sprite.red" x="0" y="0" w="32" h="32"/>
              </group>
              <group id="fitted" fitparent="1">
                <layer id="corner" image="sprite.blue" x="32" y="32" w="32" h="32"/>
              </group>
              <layer id="marker" image="sprite.green" x="0" y="48" w="16" h="16"/>
            </layout>
          </container>
        </WasabiXML>
        """)
    }

    /// A `<Wasabi:Frame>` lays its two panes either side of the divider, and a pane is a window in
    /// Wasabi — it clips whether or not the skin says so. The divider sits 16px from the top, which
    /// leaves the top pane 12px tall (16 − the divider's half-thickness); `escapee` is anchored for
    /// the strip that pane has when open, resolves *above* it, and must not paint at all.
    func testCollapsedFramePaneGolden() throws {
        try assertGolden(named: "frame-collapsed", xml: """
        \(Self.elements)
          <groupdef id="pane.top">
            <layer id="topfill" image="sprite.green" fitparent="1"/>
            <layer id="escapee" image="sprite.red" x="0" y="-32" w="64" h="32"/>
          </groupdef>
          <groupdef id="pane.bottom">
            <layer id="bottomfill" image="sprite.blue" fitparent="1"/>
          </groupdef>
          <container id="Main">
            <layout id="normal" w="64" h="64">
              <Wasabi:Frame id="split" fitparent="1" from="top" orientation="h"
                            top="pane.top" bottom="pane.bottom" height="16"/>
            </layout>
          </container>
        </WasabiXML>
        """)
    }

    /// An animated layer cuts one cell out of its sheet: `frame` selects it, `framewidth`/
    /// `frameheight` say how the sheet is divided, and the row is `index / columns`. The sheet here
    /// is a 2×2 grid — cyan, magenta / yellow, orange — so frames 0…3 are four different colours and
    /// a wrong row or column changes the picture.
    ///
    /// The fourth layer is *playing* against the fixed clock the harness installs (1.0s at the
    /// declared 100ms per frame is ten steps, `(0 + 10) % 4` = frame 2, yellow) — the path a live
    /// meter takes, and the one that piles on frame 0 when its input is in the wrong unit.
    func testAnimatedLayerFramingGolden() throws {
        try assertGolden(named: "animated-layer", xml: """
        \(Self.elements)
          <container id="Main">
            <layout id="normal" w="64" h="64">
              <animatedlayer id="first"  image="sheet.anim" x="0"  y="0"  w="16" h="16"
                             framewidth="16" frameheight="16" frame="0"/>
              <animatedlayer id="second" image="sheet.anim" x="16" y="0"  w="16" h="16"
                             framewidth="16" frameheight="16" frame="1"/>
              <animatedlayer id="third"  image="sheet.anim" x="32" y="0"  w="16" h="16"
                             framewidth="16" frameheight="16" frame="2"/>
              <animatedlayer id="fourth" image="sheet.anim" x="48" y="0"  w="16" h="16"
                             framewidth="16" frameheight="16" frame="3"/>
              <animatedlayer id="playing" image="sheet.anim" x="0" y="32" w="16" h="16"
                             framewidth="16" frameheight="16" frame="0"
                             autoplay="1" speed="100" animstart="0"/>
            </layout>
          </container>
        </WasabiXML>
        """, clock: 1.0)
    }

    /// Where a run of bitmap-font glyphs lands in its box. `align` places it horizontally and
    /// `valign` vertically — the second was pinned to `top` until Phase 20, which is a whole line's
    /// leading out on a tall box. Each glyph cell is a flat colour keyed to its position in the
    /// sheet, so a wrong glyph is a wrong colour.
    func testBitmapTextPlacementGolden() throws {
        try assertGolden(named: "text-placement", xml: """
        \(Self.elements)
          <container id="Main">
            <layout id="normal" w="64" h="64">
              <text id="tl" font="font.cells" text="abc" x="0" y="0"  w="64" h="16"
                    align="left"   valign="top"/>
              <text id="cc" font="font.cells" text="def" x="0" y="16" w="64" h="16"
                    align="center" valign="center"/>
              <text id="br" font="font.cells" text="ghi" x="0" y="32" w="64" h="16"
                    align="right"  valign="bottom"/>
              <text id="pad" font="font.cells" text="jk" x="0" y="48" w="64" h="16"
                    align="left"   valign="center" leftpadding="8"/>
            </layout>
          </container>
        </WasabiXML>
        """)
    }

    /// `alpha` belongs to the object, not to one kind of drawing (Phase 25.1). The `alpha="0"` text
    /// must be absent from the frame entirely — Defix stacks its Kbps / KHz / Channels readouts in
    /// one slot and shows one at a time purely by moving their alphas — and the half-alpha sprite
    /// must blend with the white beneath it rather than replace it.
    func testAlphaAppliesToEveryObjectGolden() throws {
        try assertGolden(named: "alpha-stack", xml: """
        \(Self.elements)
          <container id="Main">
            <layout id="normal" w="64" h="64">
              <layer id="paper" image="sprite.white" fitparent="1"/>
              <text id="hidden"  font="font.cells" text="abc" x="0" y="0"  w="64" h="16" alpha="0"/>
              <text id="shown"   font="font.cells" text="abc" x="0" y="16" w="64" h="16"/>
              <layer id="half"   image="sprite.red" x="0" y="32" w="32" h="16" alpha="128"/>
              <layer id="opaque" image="sprite.red" x="32" y="32" w="32" h="16"/>
            </layout>
          </container>
        </WasabiXML>
        """)
    }

    // MARK: - Comparison

    private func assertGolden(named name: String, xml: String, clock: TimeInterval = 0,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let pixels = try render(xml: xml, clock: clock)
        let url = Self.goldensDirectory.appendingPathComponent("\(name).png")

        if ProcessInfo.processInfo.environment["WINAMP_MODERN_GOLDEN_UPDATE"] != nil {
            try FileManager.default.createDirectory(at: Self.goldensDirectory,
                                                    withIntermediateDirectories: true)
            try Self.png(from: pixels).write(to: url)
            print("GOLDEN wrote \(url.path)")
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return XCTFail("No golden for '\(name)'. Regenerate with WINAMP_MODERN_GOLDEN_UPDATE=1.",
                           file: file, line: line)
        }
        let expected = try Self.pixels(ofPNGAt: url)
        guard expected.count == pixels.count else {
            return XCTFail("Golden '\(name)' is a different size than the scene.", file: file, line: line)
        }

        var differing: [(x: Int, y: Int)] = []
        let width = Int(Self.canvas.width)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let apart = (0..<4).contains {
                abs(Int(pixels[index + $0]) - Int(expected[index + $0])) > Self.channelTolerance
            }
            if apart { differing.append((x: (index / 4) % width, y: (index / 4) / width)) }
        }
        guard !differing.isEmpty else { return }

        let dump = try Self.writeFailureArtifacts(name: name, actual: pixels, expected: expected,
                                                  differing: Set(differing.map { $0.y * width + $0.x }))
        let sample = differing.prefix(4).map { "(\($0.x),\($0.y))" }.joined(separator: " ")
        XCTFail("Golden '\(name)': \(differing.count) pixel(s) differ, first at \(sample). "
                + "Wrote \(dump.path). Regenerate with WINAMP_MODERN_GOLDEN_UPDATE=1 once the change "
                + "is intended.", file: file, line: line)
    }

    private func render(xml: String, clock: TimeInterval) throws -> [UInt8] {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "Main", clock: { clock })
        addTeardownBlock { renderer.teardown() }
        XCTAssertEqual(renderer.canvasSize, Self.canvas, "a scene must declare the golden's size")

        let width = Int(Self.canvas.width)
        let height = Int(Self.canvas.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // `drawText` ends in AppKit, which paints into the *current* NSGraphicsContext rather
            // than the CGContext it was handed — without this every TrueType string is silently
            // dropped and the harness lies about the scene (see the harness reference).
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = previous
        }
        return pixels
    }

    // MARK: - Failure artifacts

    private static func writeFailureArtifacts(name: String, actual: [UInt8], expected: [UInt8],
                                              differing: Set<Int>) throws -> URL {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo
            .environment["WINAMP_MODERN_GOLDEN_DUMP"] ?? NSTemporaryDirectory(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png(from: actual).write(to: directory.appendingPathComponent("\(name).actual.png"))
        var diff = expected
        for index in differing {
            diff[index * 4] = 255
            diff[index * 4 + 1] = 0
            diff[index * 4 + 2] = 0
            diff[index * 4 + 3] = 255
        }
        try png(from: diff).write(to: directory.appendingPathComponent("\(name).diff.png"))
        return directory
    }

    // MARK: - Fixture

    /// The goldens live beside the tests rather than in a resource bundle, so an update run writes
    /// straight into the working tree and `git diff` shows the change that is being committed.
    private static var goldensDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/WinampModern", isDirectory: true)
    }

    /// The declarations every scene shares: four flat sprites, the animation sheet cut out of the
    /// same atlas, and the bitmap font.
    private static let elements = """
    <WasabiXML>
      <elements>
        <bitmap id="sprite.red"   file="atlas.png" x="0"  y="0" w="16" h="16"/>
        <bitmap id="sprite.green" file="atlas.png" x="16" y="0" w="16" h="16"/>
        <bitmap id="sprite.blue"  file="atlas.png" x="32" y="0" w="16" h="16"/>
        <bitmap id="sprite.white" file="atlas.png" x="48" y="0" w="16" h="16"/>
        <bitmap id="sheet.anim"   file="atlas.png" x="0"  y="16" w="32" h="32"/>
        <bitmapfont id="font.cells" file="font.png" charwidth="4" charheight="6" hspacing="0"/>
      </elements>
    """

    /// 64×64, one flat colour per 16×16 cell. Rows 1–2 of columns 0–1 are the animation sheet, in
    /// frame order: cyan, magenta / yellow, orange.
    private static func makeAtlas() throws -> Data {
        let cells: [[[UInt8]]] = [
            [[220, 40, 40], [40, 200, 40], [40, 80, 220], [255, 255, 255]],
            [[0, 200, 200], [200, 0, 200], [220, 220, 0], [230, 130, 0]],
            [[0, 120, 120], [120, 0, 120], [140, 140, 0], [150, 80, 0]],
            [[90, 90, 90], [30, 30, 30], [180, 180, 180], [10, 10, 10]],
        ]
        return try makePNG(width: 64, height: 64) { x, y in cells[y / 16][x / 16] }
    }

    /// The bitmap font's sheet: 30 columns × 3 rows of 4×6 cells, matching the glyph map the
    /// renderer uses. Each cell is a flat colour keyed to its position, so "which glyph landed
    /// where" is readable straight off the pixels.
    private static func makeFontSheet() throws -> Data {
        try makePNG(width: 30 * 4, height: 3 * 6) { x, y in
            let column = x / 4
            let row = y / 6
            return [UInt8(20 + column * 8), UInt8(row * 100), 200]
        }
    }

    private static func makePNG(width: Int, height: Int,
                                color: (Int, Int) -> [UInt8]) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let rgb = color(x, y)
                let offset = (y * width + x) * 4
                pixels[offset] = rgb[0]
                pixels[offset + 1] = rgb[1]
                pixels[offset + 2] = rgb[2]
                pixels[offset + 3] = 255
            }
        }
        return try png(from: pixels, width: width, height: height)
    }

    private static func png(from pixels: [UInt8], width: Int = Int(canvas.width),
                            height: Int = Int(canvas.height)) throws -> Data {
        var pixels = pixels
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    /// A golden read back as premultiplied RGBA at the canvas size — the same layout the scene is
    /// rendered into, so the two are comparable byte for byte whatever the file's own encoding.
    private static func pixels(ofPNGAt url: URL) throws -> [UInt8] {
        let data = try Data(contentsOf: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        guard image.width == width, image.height == height else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernGoldenImageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Golden.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)),
                                ("atlas.png", try Self.makeAtlas()),
                                ("font.png", try Self.makeFontSheet())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
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
