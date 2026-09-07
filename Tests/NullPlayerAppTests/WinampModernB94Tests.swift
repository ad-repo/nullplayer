import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B94 — Wasabi creates a bitmap for an attribute that names an image **file** where a declared
/// `<bitmap>` id was expected, so `image="play/Bar.png"` is as good as `image="volume.bar"`.
/// Resolving only the declared form left a skin authored entirely that way drawing none of its own
/// artwork: Darjah 1 declares no `<bitmap>` for its player at all, both of its layouts reported
/// `resolved=0`, and it fell back to NullPlayer's generic transport over a plain background. 606
/// such declarations across 9 corpus skins.
///
/// The implicit bitmaps are registered after every declaration, which is what these cases pin: a
/// declaration always wins, keeps its crop, and — the case that made this worth a second pass — a
/// `<bitmapfont>` naming the same file keeps its own gamma group. An implicit bitmap has neither,
/// because a path form declares neither.
final class WinampModernB94Tests: XCTestCase {

    /// The Darjah shape: no `<bitmap>` anywhere, a layer that names a file, and the file is in the
    /// archive. Before this the layer resolved nothing and drew nothing.
    func testALayerImageNamingAFileDrawsThatFile() throws {
        let scene = try makeScene(
            markup: #"<layer id="bar" x="0" y="0" w="16" h="8" image="art/bar.png"/>"#,
            art: ["art/bar.png": Self.halvesPNG()]
        )
        let pixel = try XCTUnwrap(scene.pixel(x: 2, y: 4))
        XCTAssertEqual(Int(pixel.alpha), 255, "the layer has artwork")
        XCTAssertEqual(Int(pixel.red), 200, accuracy: 2)
        XCTAssertEqual(Int(pixel.green), 40, accuracy: 2)
    }

    /// Darjah writes `image="Player/Normal.png"` from `xml/player-normal.xml`, so the path is
    /// relative to the skin root while the declaration sits a directory down — the same either/or
    /// `background=` takes. The declaring file's own directory is tried first and the root second.
    func testAPathIsResolvedFromTheSkinRootAsWellAsTheDeclaringFile() throws {
        let scene = try makeScene(
            markup: #"<layer id="bar" x="0" y="0" w="16" h="8" image="art/bar.png"/>"#,
            includedFrom: "xml/window.xml",
            art: ["art/bar.png": Self.halvesPNG()]
        )
        let pixel = try XCTUnwrap(scene.pixel(x: 2, y: 4))
        XCTAssertEqual(Int(pixel.red), 200, accuracy: 2, "resolved from the root, not only from xml/")
    }

    /// An implicit bitmap is the **whole file**: a path form declares no `x`/`y`/`w`/`h`, so the
    /// 16×8 sheet is stretched across the 16px layer and its left half is still the left colour.
    func testAnImplicitBitmapIsTheWholeFileWithNoCrop() throws {
        let scene = try makeScene(
            markup: #"<layer id="bar" x="0" y="0" w="16" h="8" image="art/bar.png"/>"#,
            art: ["art/bar.png": Self.halvesPNG()]
        )
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 2, y: 4)).red), 200, accuracy: 2)
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 13, y: 4)).green), 220, accuracy: 2,
                       "both halves are present, so nothing was cropped")
    }

    /// And a declaration always wins, crop included. The implicit pass runs after every `<bitmap>`
    /// and never displaces one, so no skin's resolved artwork can change because some file happens
    /// to share its id.
    func testADeclaredBitmapWinsOverAFileOfTheSameNameAndKeepsItsCrop() throws {
        let scene = try makeScene(
            resources: #"<bitmap id="art/bar.png" file="art/bar.png" x="8" y="0" w="8" h="8"/>"#,
            markup: #"<layer id="bar" x="0" y="0" w="16" h="8" image="art/bar.png"/>"#,
            art: ["art/bar.png": Self.halvesPNG()]
        )
        let pixel = try XCTUnwrap(scene.pixel(x: 2, y: 4))
        XCTAssertEqual(Int(pixel.green), 220, accuracy: 2,
                       "the declared right-half crop, stretched, not the whole file")
    }

    /// The regression this cost a second sweep to find. MMD3 writes
    /// `<bitmapfont file="player/tickerfont2.png">`, and the font's sheet carries the font's own
    /// `gammagroup` or the colour theme tints the skin's artwork and leaves its text untinted. Once
    /// that path had an implicit bitmap the id branch of `fontSheet` won and returned the untinted
    /// whole file, so MMD3's ticker, time, KBPS and KHZ went grey inside a themed player.
    func testABitmapFontKeepsItsOwnGammaGroupWhenALayerNamesTheSameFile() throws {
        let scene = try makeScene(
            resources: """
            <gammaset id="Tinted"><gammagroup id="Ink" value="0,-4096,-4096"/></gammaset>
            <bitmapfont id="ticker" file="art/bar.png" gammagroup="Ink" charwidth="8" charheight="8"/>
            """,
            markup: #"<layer id="bar" x="0" y="0" w="16" h="8" image="art/bar.png"/>"#,
            art: ["art/bar.png": Self.halvesPNG()]
        )
        let definition = try XCTUnwrap(
            scene.loadedSkin.runtime.resources.resolvedDefinition(identifier: "ticker"))
        let sheet = try XCTUnwrap(scene.renderer.resources.fontSheet(for: definition))
        let ink = try XCTUnwrap(Self.topLeftPixel(of: sheet.image))
        XCTAssertEqual(Int(ink.red), 200, accuracy: 2)
        XCTAssertEqual(Int(ink.green), 0, accuracy: 2, "the font's own gamma group was applied")

        // The layer beside it is the implicit bitmap, which declares no group and stays untinted.
        let drawn = try XCTUnwrap(scene.pixel(x: 2, y: 4))
        XCTAssertEqual(Int(drawn.green), 40, accuracy: 2)
    }

    /// A file-shaped value the archive does not contain registers nothing and draws nothing, exactly
    /// as an unknown id always has. Darjah still has one of these — `play/on.png`, where the file it
    /// ships is `player/On.png` in a different directory, which Winamp misses too.
    func testAPathTheArchiveDoesNotContainRegistersNothing() throws {
        let scene = try makeScene(
            markup: #"<layer id="bar" x="0" y="0" w="16" h="8" image="art/missing.png"/>"#,
            art: ["art/bar.png": Self.halvesPNG()]
        )
        XCTAssertNil(scene.loadedSkin.runtime.resources.resolvedDefinition(identifier: "art/missing.png"))
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 2, y: 4)).alpha), 0)
    }

    /// A value that is not path-shaped is left alone, so the pass cannot invent a resource for an
    /// ordinary id — and an id that resolves to nothing still resolves to nothing.
    func testAnUndeclaredIdIsStillUnresolved() throws {
        let scene = try makeScene(
            markup: #"<layer id="bar" x="0" y="0" w="16" h="8" image="volume.bar"/>"#,
            art: ["art/bar.png": Self.halvesPNG()]
        )
        XCTAssertNil(scene.loadedSkin.runtime.resources.resolvedDefinition(identifier: "volume.bar"))
        XCTAssertEqual(Int(try XCTUnwrap(scene.pixel(x: 2, y: 4)).alpha), 0)
    }

    // MARK: - Fixture

    private struct Scene {
        let loadedSkin: WinampModernLoadedSkin
        let renderer: WasabiSceneRenderer

        func pixel(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
            let width = Int(renderer.canvasSize.width)
            let height = Int(renderer.canvasSize.height)
            guard x >= 0, x < width, y >= 0, y < height else { return nil }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = pixels.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context else { return nil }
            renderer.invalidateSceneCache()
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = saved
            // The buffer is bottom-up and the renderer draws the scene top-down, so a scene row is
            // read from the far end.
            let offset = ((height - 1 - y) * width + x) * 4
            return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
        }
    }

    /// `includedFrom` puts the container in a second file so the path form is resolved from a
    /// directory that is *not* the skin root — the Darjah shape.
    private func makeScene(resources: String = "",
                           markup: String = "",
                           includedFrom: String? = nil,
                           art: [String: Data] = [:]) throws -> Scene {
        let container = """
        <container id="Main">
          <layout id="normal" w="16" h="8">
        \(markup)
          </layout>
        </container>
        """
        var files: [String: Data] = art
        let root: String
        if let includedFrom {
            files[includedFrom] = Data("<WasabiXML>\n\(container)\n</WasabiXML>".utf8)
            root = """
            <WasabiXML>
              <elements>\(resources)</elements>
              <include file="\(includedFrom)"/>
            </WasabiXML>
            """
        } else {
            root = """
            <WasabiXML>
              <elements>\(resources)</elements>
            \(container)
            </WasabiXML>
            """
        }
        files["skin.xml"] = Data(root.utf8)

        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(files: files))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return Scene(loadedSkin: loaded, renderer: renderer)
    }

    private func makeArchive(files: [String: Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB94Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B94-\(UUID().uuidString).wal")
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

    /// 16×8: the left half one colour, the right half another, so a crop and the whole file are
    /// told apart by one pixel.
    private static func halvesPNG() -> Data {
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 8,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB,
                                              bytesPerRow: 64, bitsPerPixel: 32)!
        for y in 0..<8 {
            for x in 0..<16 {
                var components = x < 8 ? [200, 40, 60, 255] : [10, 220, 30, 255]
                representation.setPixel(&components, atX: x, y: y)
            }
        }
        return representation.representation(using: .png, properties: [:])!
    }

    private static func topLeftPixel(of image: CGImage) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = pixel.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let context else { return nil }
        // The whole sheet scaled into one pixel would average the two halves; draw it at natural
        // size against a 1×1 clip instead so the sample is the top-left pixel itself.
        context.draw(image, in: CGRect(x: 0, y: CGFloat(1 - image.height),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return (pixel[0], pixel[1], pixel[2])
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
