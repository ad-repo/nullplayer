import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 51 (B30) — a mouse event's x/y are in the receiver's **parent** space.
///
/// Reported live on LOBE 2026-08-21: "the volume and seek sliders do not work". Neither is a slider —
/// each is an `<AnimatedLayer>` inside a placed group, driven by a MAKI script that samples a `Map`:
///
/// ```c
/// SeekAnim.onLeftButtonUp(int x, int y) {
///     float v = seekMap.getValue(x - SeekAnim.getLeft(), y - SeekAnim.getTop());
///     System.seekTo(v * System.getPlayItemLength() / 255);
/// }
/// ```
///
/// `getLeft()` is parent-relative, so `x` has to be too. We sent the canvas point, so a click on the
/// dial sampled (213, 26) of a 48×35 map — 0 everywhere outside it — and every drag seeked to zero.
/// The same script drives the volume strip, and Rika's knobs are written the same way.
///
/// mmd3 proves it from the other side, in shipped source (`scripts/volumebasstreble.m`):
///
/// ```c
/// Volume.onLeftButtonDown(int x, int y) {
///     WinX = getMousePosX() - x + Volume.getLeft() + (Volume.getWidth()/2);
///     x = x - Volume.getLeft();
/// ```
///
/// `getMousePosX() - x` is only the parent's origin — the conversion the rest of that knob needs —
/// if `x` is parent-relative and `getMousePosX()` is not. mmd3's own knob group is at (0, 0), which
/// is why the two conventions agreed there and the defect stayed invisible for 50 phases.
final class WinampModernPhase51Tests: XCTestCase {

    func testAControlInAPlacedGroupIsToldItsParentRelativePoint() throws {
        let scene = try makeScene()
        // The dial's canvas frame is (210 + 27, 10 + 25) — the group's origin plus its own x/y.
        XCTAssertEqual(scene.renderer.frame(of: scene.dial), CGRect(x: 237, y: 35, width: 48, height: 35))
        let local = scene.view.pointInParentSpace(of: scene.dial, canvasPoint: CGPoint(x: 240, y: 51))
        XCTAssertEqual(local, CGPoint(x: 30, y: 41))
        // Which is the whole point: the script subtracts its own getLeft()/getTop() from this and
        // lands inside its own artwork.
        XCTAssertEqual(CGPoint(x: local.x - 27, y: local.y - 25), CGPoint(x: 3, y: 16))
    }

    /// The case that hid the defect: a control hanging straight off the layout is unchanged, which is
    /// most of the corpus (17 of 30 installed skins have every scripted mouse receiver at the origin).
    func testAControlAtTheOriginIsUnchanged() throws {
        let scene = try makeScene()
        let point = CGPoint(x: 12, y: 9)
        XCTAssertEqual(scene.view.pointInParentSpace(of: scene.loose, canvasPoint: point), point)
    }

    /// An object the scene cannot place (a hidden layout's control, the headless case) keeps the
    /// point it was given rather than losing the event.
    func testAnUnplaceableObjectKeepsTheCanvasPoint() throws {
        let scene = try makeScene()
        let offscreen = try XCTUnwrap(scene.loaded.runtime.graph.objects(xmlID: "elsewhere").first)
        let point = CGPoint(x: 40, y: 40)
        XCTAssertNil(scene.renderer.resolvedGeometry(of: offscreen))
        XCTAssertEqual(scene.view.pointInParentSpace(of: offscreen, canvasPoint: point), point)
    }

    // MARK: - Fixture

    private struct Scene {
        let loaded: WinampModernLoadedSkin
        let renderer: WasabiSceneRenderer
        let view: WinampModernMainView
        let dial: WasabiObject
        let loose: WasabiObject
    }

    private func makeScene() throws -> Scene {
        let xml = """
        <WasabiXML>
          <bitmap id="art" file="sheet.png" w="48" h="35"/>
          <groupdef id="seeker" w="152" h="159">
            <layer id="dial" image="art" x="27" y="25" w="48" h="35"/>
          </groupdef>
          <container id="Main">
            <layout id="normal" w="400" h="300">
              <layer id="loose" image="art" x="0" y="0" w="48" h="35"/>
              <group id="seeker" x="210" y="10" w="156" h="148"/>
            </layout>
            <layout id="other" w="400" h="300">
              <layer id="elsewhere" image="art" x="5" y="5" w="10" h="10"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host)
        addTeardownBlock { view.teardown() }
        return Scene(loaded: loaded, renderer: renderer, view: view,
                     dial: try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "dial").first),
                     loose: try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "loose").first))
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase51Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase51-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", try makePNG())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func makePNG() throws -> Data {
        let size = NSSize(width: 48, height: 35)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
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
