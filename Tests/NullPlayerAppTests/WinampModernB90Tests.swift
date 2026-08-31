import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B90 — a layout's `background=` is the window's backing, and both ways it can fail to resolve left
/// the whole window transparent.
///
/// **The path form.** Winamp accepts either a declared `<bitmap>` id or a path to an image inside the
/// skin, exactly as `loadMap` and `<bitmapfont file=>` do — and this cache already answered both of
/// those and only the id form here. Itemskin's notifier preferences is the corpus's one path-form
/// declaration (`<layout background="notifier\config.png">`) and drew 82.6% fully transparent.
///
/// **The undeclared base-skin resource.** `component.basetexture`, `wasabi.frame.basetexture`,
/// `studio.BaseTexture` and `wasabi.frame` come from Winamp's own Wasabi base skin, which we have no
/// equivalent of — 41 declarations across 13 corpus skins. Where the skin paints its own chrome on
/// top it never showed; where the layout background is the *only* backing the window vanished. EPS
/// High-End's notifier preferences is the reported case: every control is drawn, in the skin's
/// near-white list colours, against nothing.
///
/// The guard that makes the fill safe is that it is keyed on the skin having **asked** for a backing.
/// A layout that declares no `background=` at all is deliberately shaped and must stay transparent,
/// or every `sysregion` player in the corpus grows a rectangle.
final class WinampModernB90Tests: XCTestCase {

    /// The Itemskin shape: a path, with a Windows separator, written from the **skin root** while the
    /// declaration itself sits one directory down.
    func testALayoutBackgroundNamingAFileDrawsThatFile() throws {
        let scene = try makeScene(
            layoutAttributes: #"background="art\bg.png""#,
            includedFrom: "xml/window.xml",
            art: ["art/bg.png": Self.solidPNG(red: 200, green: 40, blue: 60)]
        )
        let pixel = try XCTUnwrap(scene.pixel(x: 30, y: 20))
        XCTAssertEqual(Int(pixel.alpha), 255, "the window has a backing")
        XCTAssertEqual(Int(pixel.red), 200, accuracy: 2)
        XCTAssertEqual(Int(pixel.green), 40, accuracy: 2)
        XCTAssertEqual(Int(pixel.blue), 60, accuracy: 2)
    }

    /// A declared id still wins, and still wins over a same-named file — the path form is only ever
    /// the fallback, so no skin's resolved artwork can be displaced by a stray filename collision.
    func testADeclaredBitmapIdIsPreferredOverAPathOfTheSameName() throws {
        let scene = try makeScene(
            layoutAttributes: #"background="art/bg.png""#,
            resources: #"<bitmap id="art/bg.png" file="art/other.png"/>"#,
            art: ["art/bg.png": Self.solidPNG(red: 200, green: 40, blue: 60),
                  "art/other.png": Self.solidPNG(red: 10, green: 220, blue: 30)]
        )
        let pixel = try XCTUnwrap(scene.pixel(x: 30, y: 20))
        XCTAssertEqual(Int(pixel.green), 220, accuracy: 2, "the declared bitmap, not the file beside it")
    }

    /// The EPS case: a base-skin id the `.wal` does not ship. The skin asked for a backing, so it gets
    /// one, in the skin's own content colour rather than an invented grey.
    func testAnUnresolvableLayoutBackgroundFallsBackToTheSkinsContentColour() throws {
        let scene = try makeScene(
            layoutAttributes: #"background="component.basetexture""#,
            resources: #"<color id="wasabi.list.background" value="10,20,30"/>"#
        )
        let pixel = try XCTUnwrap(scene.pixel(x: 30, y: 20))
        XCTAssertEqual(Int(pixel.alpha), 255, "the window is not transparent")
        XCTAssertEqual(Int(pixel.red), 10, accuracy: 2)
        XCTAssertEqual(Int(pixel.green), 20, accuracy: 2)
        XCTAssertEqual(Int(pixel.blue), 30, accuracy: 2)
    }

    /// The guard. A layout that declares no background is shaped by its own artwork and stays
    /// transparent — this is what keeps the fill off every `sysregion` player in the corpus.
    func testALayoutThatDeclaresNoBackgroundStaysTransparent() throws {
        let scene = try makeScene(
            layoutAttributes: "",
            resources: #"<color id="wasabi.list.background" value="10,20,30"/>"#
        )
        let pixel = try XCTUnwrap(scene.pixel(x: 30, y: 20))
        XCTAssertEqual(Int(pixel.alpha), 0, "nothing was asked for and nothing is painted")
    }

    /// And the fill is the *window's* backing, not a rule about `background=`. A group whose
    /// background does not resolve keeps drawing nothing, because a group with no region of its own
    /// filled opaque would slab over whatever the layout put behind it.
    func testAGroupWithAnUnresolvableBackgroundIsNotFilled() throws {
        let scene = try makeScene(
            layoutAttributes: "",
            resources: #"<color id="wasabi.list.background" value="10,20,30"/>"#,
            markup: #"<group id="panel" x="0" y="0" w="120" h="40" background="component.basetexture"/>"#
        )
        let pixel = try XCTUnwrap(scene.pixel(x: 30, y: 20))
        XCTAssertEqual(Int(pixel.alpha), 0, "only a layout answers for the window's backing")
    }

    // MARK: - Fixture

    private struct Scene {
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
    /// directory that is *not* the skin root — the Itemskin shape.
    private func makeScene(layoutAttributes: String,
                           resources: String = "",
                           markup: String = "",
                           includedFrom: String? = nil,
                           art: [String: Data] = [:]) throws -> Scene {
        let container = """
        <container id="Main">
          <layout id="normal" w="120" h="40" \(layoutAttributes)>
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
        return Scene(renderer: renderer)
    }

    private func makeArchive(files: [String: Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB90Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B90-\(UUID().uuidString).wal")
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
