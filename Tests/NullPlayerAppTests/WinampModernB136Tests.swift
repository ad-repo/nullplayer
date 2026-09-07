import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B136 / B137 — Nullsoft Winamp 2000 SP4, reported as "the titlebars are unreadable and the
/// visualization window opens collapsed".
///
/// Three independent defects, each of which that one skin is simply the first to exercise:
///
/// 1. **`activealpha`/`inactivealpha` were never read.** The skin stacks an active title and an
///    inactive title in the same slot and shows one at a time purely by that pair; both drew, in two
///    different colours, and every window title came out a smear.
/// 2. **`default_w`/`default_h` on a `<container>` were never read.** `default_x`/`default_y` always
///    were. Every auxiliary window this skin sizes that way opened at its `minimum_*` floor instead —
///    the playlist at 276 against a declared 550, the visualizer at 96 against 354.
/// 3. **A `<gradient>` that names no direction flat-filled its last stop.** All four coordinates
///    defaulted to 0, so `start == end` and `.drawsAfterEndLocation` painted the end colour over the
///    whole rect. The skin's Windows 2000 titlebar is an opaque navy gradient with a light blue one
///    laid over it at `points="0.0=…,0;1.0=…,255"` — flat-filled, the second hid the first.
///
/// The fourth entry is not a defect of its own but the trap the first fix set: the visualizer's
/// height is stated *nowhere*, and the fit that supplies it has to run **before** the skin's scripts
/// do, because the window tiler asks for every container's size while the skin is still loading. A
/// render dump reads that size late and the app reads it early, so the first version of the fix
/// measured perfect in the harness and changed nothing on screen.
final class WinampModernB136Tests: XCTestCase {

    // MARK: - activealpha / inactivealpha

    func testActiveAlphaIsUsedWhileTheWindowHasTheKeyboard() throws {
        let object = try makeObject(attributes: ["activealpha": "255", "inactivealpha": "0"])
        XCTAssertEqual(WasabiSceneRenderer.alphaFraction(of: object, active: true), 1)
        XCTAssertEqual(WasabiSceneRenderer.alphaFraction(of: object, active: false), 0)
    }

    func testTheReverseObjectInTheSameSlotAnswersTheOppositeWay() throws {
        let object = try makeObject(attributes: ["activealpha": "0", "inactivealpha": "255"])
        XCTAssertEqual(WasabiSceneRenderer.alphaFraction(of: object, active: true), 0)
        XCTAssertEqual(WasabiSceneRenderer.alphaFraction(of: object, active: false), 1)
    }

    /// Plain `alpha` is the value for both states, and an object declaring neither is opaque — the
    /// case every other skin in the corpus is, which is why this had to stay a no-op for them.
    func testPlainAlphaStillAnswersForBothStates() throws {
        let faded = try makeObject(attributes: ["alpha": "128"])
        XCTAssertEqual(WasabiSceneRenderer.alphaFraction(of: faded, active: true), 128.0 / 255)
        XCTAssertEqual(WasabiSceneRenderer.alphaFraction(of: faded, active: false), 128.0 / 255)
        let plain = try makeObject(attributes: [:])
        XCTAssertEqual(WasabiSceneRenderer.alphaFraction(of: plain, active: true), 1)
        XCTAssertEqual(WasabiSceneRenderer.alphaFraction(of: plain, active: false), 1)
    }

    // MARK: - Container default_w / default_h

    func testAContainerSizesALayoutThatStatesNoBoxOfItsOwn() throws {
        let renderer = try makeRenderer(
            container: #"<container id="pl" default_w="550" default_h="242">"#,
            layout: #"<layout id="normal" minimum_w="276" minimum_h="242"/>"#)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 550, height: 242))
    }

    /// The layout's own box outranks the container's default — the container answers only for an
    /// axis the layout never states.
    func testALayoutThatStatesItsOwnBoxKeepsIt() throws {
        let renderer = try makeRenderer(
            container: #"<container id="pl" default_w="550" default_h="242">"#,
            layout: #"<layout id="normal" w="300" h="120" minimum_w="276"/>"#)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 300, height: 120))
    }

    /// A floor is still a floor: it clamps whatever the chain produced.
    func testTheDeclaredMinimumStillClampsTheResult() throws {
        let renderer = try makeRenderer(
            container: #"<container id="pl" default_w="100" default_h="40">"#,
            layout: #"<layout id="normal" minimum_w="276" minimum_h="242"/>"#)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 276, height: 242))
    }

    // MARK: - The component-room fit

    /// The reported window: a component container whose layout states no height at all, only a
    /// 30px floor, leaving its `<component>` box two pixels tall.
    func testAComponentContainerWithNoStatedHeightIsOpenedToFitItsComponent() throws {
        let renderer = try makeRenderer(
            container: #"<container id="AVS" default_w="354" component="guid:{0000000A-000C-0010-FF7B-01014263450C}">"#,
            layout: """
            <layout id="normal" minimum_w="96" minimum_h="30">
              <component x="4" y="24" w="-8" h="-28" relatw="1" relath="1"
                         param="guid:{0000000A-000C-0010-FF7B-01014263450C}"/>
            </layout>
            """)
        // 30 (the floor it opened at) + 250 (the room the component is given) - 2 (what it had).
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 354, height: 278))
    }

    /// **The regression this fix had on its first attempt**, kept as a test: the fit must not run for
    /// a player window, which parks component holders it is not showing. Lobe's `main` layout grew by
    /// 225px around one.
    func testAWindowThatIsNotAComponentContainerIsNeverGrown() throws {
        let renderer = try makeRenderer(
            container: #"<container id="main">"#,
            layout: """
            <layout id="normal" minimum_w="400" minimum_h="300">
              <component x="4" y="24" w="-8" h="-298" relatw="1" relath="1"
                         param="guid:{0000000A-000C-0010-FF7B-01014263450C}"/>
            </layout>
            """)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 400, height: 300))
    }

    /// A component that already has room is left exactly where its author put it.
    func testAComponentWindowWithRoomIsLeftAlone() throws {
        let renderer = try makeRenderer(
            container: #"<container id="AVS" component="guid:{0000000A-000C-0010-FF7B-01014263450C}">"#,
            layout: """
            <layout id="normal" w="354" h="280">
              <component x="4" y="24" w="-8" h="-28" relatw="1" relath="1"
                         param="guid:{0000000A-000C-0010-FF7B-01014263450C}"/>
            </layout>
            """)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 354, height: 280))
    }

    // MARK: - Gradient direction

    /// The measurement that named the defect: with the direction defaulted to `start == end`, every
    /// pixel of the strip was the *end* colour. It must ramp instead.
    func testAGradientWithNoStatedDirectionRunsLeftToRight() throws {
        let renderer = try makeRenderer(
            container: #"<container id="main">"#,
            layout: """
            <layout id="normal" w="200" h="20">
              <gradient id="ramp" x="0" y="0" w="200" h="20"
                        points="0.0=0,0,0,255;1.0=255,255,255,255"/>
            </layout>
            """)
        let pixels = try render(renderer)
        let left = pixels(10, 10), right = pixels(190, 10)
        XCTAssertLessThan(left.red, 40, "the left end should be the first stop")
        XCTAssertGreaterThan(right.red, 215, "the right end should be the last stop")
        XCTAssertGreaterThan(right.red, left.red + 100, "and the strip between them should ramp")
    }

    /// A skin that states a direction still gets exactly what it states — ClassicPro's
    /// `cdbox.fg.fademask` names all four and fades top to bottom.
    func testAStatedDirectionIsObeyedUnchanged() throws {
        let renderer = try makeRenderer(
            container: #"<container id="main">"#,
            layout: """
            <layout id="normal" w="200" h="20">
              <gradient id="ramp" x="0" y="0" w="200" h="20"
                        gradient_x1="0" gradient_y1="0" gradient_x2="0" gradient_y2="1"
                        points="0.0=0,0,0,255;1.0=255,255,255,255"/>
            </layout>
            """)
        let pixels = try render(renderer)
        XCTAssertEqual(pixels(10, 2).red, pixels(190, 2).red, accuracy: 8,
                       "a vertical fade must not vary along x")
        XCTAssertGreaterThan(pixels(100, 18).red, pixels(100, 2).red + 100)
    }

    // MARK: - Fixtures

    private func makeObject(attributes: [String: String]) throws -> WasabiObject {
        let rendered = attributes.map { " \($0.key)=\"\($0.value)\"" }.joined()
        let renderer = try makeRenderer(
            container: #"<container id="main">"#,
            layout: """
            <layout id="normal" w="100" h="20">
              <layer id="probe" x="0" y="0" w="10" h="10"\(rendered)/>
            </layout>
            """)
        return try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "probe" }?.object)
    }

    private func makeRenderer(container: String, layout: String) throws -> WasabiSceneRenderer {
        let xml = """
        <WasabiXML>
        \(container)
        \(layout)
        </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let id = try XCTUnwrap(loaded.runtime.graph.roots.first {
            $0.typeName.caseInsensitiveCompare("container") == .orderedSame
        }?.xmlID)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: id, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    /// Paint the scene and hand back a pixel reader in skin coordinates (y down from the top).
    private func render(_ renderer: WasabiSceneRenderer) throws
        -> (Int, Int) -> (red: Int, green: Int, blue: Int) {
        let width = Int(renderer.canvasSize.width), height = Int(renderer.canvasSize.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = saved
        }
        // The bitmap's row 0 is the context's *bottom*; the scene is painted y-flipped into it, so a
        // skin y reads back at the same row it was drawn at.
        return { x, y in
            let offset = (y * width + x) * 4
            return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
        }
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB136Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B136-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        return url
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
