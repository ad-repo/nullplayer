import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 37 (backlog B3) — `action="PAN"`, the balance slider.
///
/// `updateSlider` handled `SEEK`, `VOLUME` and the `EQ_*` family; `PAN` fell through to the default
/// branch, which writes the object's `value=` and nothing else. Eight declarations across seven of
/// the 17 measured skins (multipass ships two — a real slider and a ghosted LED twin over it) were
/// therefore a control the user could drag with nothing at the other end of it.
///
/// Both directions matter: the drag writes the engine's balance, and the thumb is drawn from the
/// engine's balance, so a change made anywhere else moves the skin's slider. The drag also moves the
/// object's own 0…255 position and dispatches `onSetPosition`, which is where a skin puts its only
/// feedback — multipass prints "Balance: Left +40%" on its song ticker from that handler alone.
final class WinampModernPhase37Tests: XCTestCase {
    // MARK: - The two units

    func testPositionConvertsToBalanceAroundACentredMiddle() {
        XCTAssertEqual(WinampModernPanAction.balance(normalized: 0), -1)
        XCTAssertEqual(WinampModernPanAction.balance(normalized: 0.5), 0)
        XCTAssertEqual(WinampModernPanAction.balance(normalized: 1), 1)
    }

    func testBalanceConvertsBackToTheSamePosition() {
        XCTAssertEqual(WinampModernPanAction.normalized(balance: -1), 0)
        XCTAssertEqual(WinampModernPanAction.normalized(balance: 0), 0.5)
        XCTAssertEqual(WinampModernPanAction.normalized(balance: 1), 1)
    }

    func testBothDirectionsClampRatherThanRunOff() {
        XCTAssertEqual(WinampModernPanAction.balance(normalized: 4), 1)
        XCTAssertEqual(WinampModernPanAction.balance(normalized: -4), -1)
        XCTAssertEqual(WinampModernPanAction.normalized(balance: 9), 1)
        XCTAssertEqual(WinampModernPanAction.normalized(balance: -9), 0)
    }

    func testOnlyPanMatches() {
        XCTAssertTrue(WinampModernPanAction.matches(action: "PAN"))
        XCTAssertTrue(WinampModernPanAction.matches(action: " pan "))
        XCTAssertFalse(WinampModernPanAction.matches(action: "PANEL"))
        XCTAssertFalse(WinampModernPanAction.matches(action: nil))
    }

    // MARK: - The drag

    func testDraggingThePanSliderWritesTheHostBalance() throws {
        let scene = try makeScene()
        scene.host.balance = 0

        scene.press(at: CGPoint(x: 2, y: 25))
        XCTAssertEqual(scene.host.balance, -1, accuracy: 0.06, "the left end is hard left")

        scene.press(at: CGPoint(x: 51, y: 25))
        XCTAssertEqual(scene.host.balance, 0, accuracy: 0.06, "the middle of the track is centred")

        scene.press(at: CGPoint(x: 99, y: 25))
        XCTAssertEqual(scene.host.balance, 1, accuracy: 0.06, "the right end is hard right")
    }

    func testAPanDragDoesNotDisturbTheVolume() throws {
        let scene = try makeScene()
        scene.host.volume = 0.42
        scene.press(at: CGPoint(x: 2, y: 25))
        XCTAssertEqual(scene.host.volume, 0.42)
    }

    /// Wasabi moves the object's own position on a drag and tells the skin. Both halves are the
    /// contract a script reads: `getPosition()` answers with the attribute, `onSetPosition` carries
    /// the same number.
    func testADragMovesThePositionAndNotifiesTheSkin() throws {
        let scene = try makeScene()
        scene.scripts.recordsDispatchedEventsForTesting = true

        scene.press(at: CGPoint(x: 99, y: 25))
        // The press is at 99 of a 100-wide track, so the position is 99% of 255 — the point is that
        // the object's own value moved with the drag, not that a click can reach the last pixel.
        XCTAssertEqual(scene.slider.attributes["value"], "252")
        XCTAssertTrue(scene.scripts.dispatchedEventsForTesting.contains {
            $0.object == "balance" && $0.event == "onsetposition"
        })
    }

    func testAPositionThatDidNotMoveIsNotReannounced() throws {
        // Skins pair sliders that write each other's position from their own `onSetPosition`
        // (multipass's balance and its LED twin); re-announcing an unchanged value is the round trip
        // that never ends.
        let scene = try makeScene()
        scene.press(at: CGPoint(x: 99, y: 25))
        scene.scripts.recordsDispatchedEventsForTesting = true
        scene.press(at: CGPoint(x: 99, y: 25))
        XCTAssertFalse(scene.scripts.dispatchedEventsForTesting.contains { $0.event == "onsetposition" })
    }

    // MARK: - The thumb

    /// The slider is drawn from the host, not from its own `value=`, so a balance changed from
    /// anywhere else — the menu bar, another window — moves the skin's thumb.
    func testTheThumbFollowsTheHostBalance() throws {
        let scene = try makeScene()

        scene.host.balance = -1
        let left = try XCTUnwrap(scene.thumbCentreX())
        scene.host.balance = 0
        let centre = try XCTUnwrap(scene.thumbCentreX())
        scene.host.balance = 1
        let right = try XCTUnwrap(scene.thumbCentreX())

        XCTAssertLessThan(left, centre)
        XCTAssertLessThan(centre, right)
        XCTAssertEqual(centre, 50, accuracy: 4, "centred balance draws the thumb mid-track")
    }

    // MARK: - Fixture

    private struct Scene {
        let loaded: WinampModernLoadedSkin
        let renderer: WasabiSceneRenderer
        let scripts: WinampModernScriptRuntime
        let view: WinampModernMainView
        let host: Host
        let slider: WasabiObject

        /// A press at a skin-space point, through the view's own mouse path.
        func press(at point: CGPoint) {
            let location = NSPoint(x: point.x, y: renderer.canvasSize.height - point.y)
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location,
                                                modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                context: nil, eventNumber: 1, clickCount: 1,
                                                pressure: 1),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location,
                                              modifierFlags: [], timestamp: 0, windowNumber: 0,
                                              context: nil, eventNumber: 2, clickCount: 1,
                                              pressure: 0) else { return }
            view.mouseDown(with: down)
            view.mouseUp(with: up)
        }

        /// Where the white thumb currently sits, as the centroid of the lit pixels along the track.
        func thumbCentreX() -> CGFloat? {
            let width = Int(renderer.canvasSize.width)
            let height = Int(renderer.canvasSize.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = pixels.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context else { return nil }
            renderer.invalidateSceneCache()
            renderer.draw(in: context)
            var weighted: CGFloat = 0
            var count: CGFloat = 0
            for y in 0..<height {
                for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                    weighted += CGFloat(x)
                    count += 1
                }
            }
            return count == 0 ? nil : weighted / count
        }
    }

    private func makeScene() throws -> Scene {
        let xml = """
        <WasabiXML>
          <bitmap id="pan.thumb" file="thumb.png" w="4" h="10"/>
          <container id="Main">
            <layout id="normal" w="100" h="50">
              <slider id="balance" action="PAN" x="0" y="20" w="100" h="10" thumb="pan.thumb"/>
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
        let slider = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "balance").first)
        return Scene(loaded: loaded, renderer: renderer, scripts: scripts, view: view,
                     host: host, slider: slider)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase37Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase37-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        // A real PNG, not a `file="$solid"` generated bitmap: a generated one resolves as a *colour*
        // and has no pixels to draw, so the thumb would never appear.
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("thumb.png", try makeWhitePNG())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    /// The thumb's artwork: 4×10, opaque white.
    private func makeWhitePNG() throws -> Data {
        let width = 4
        let height = 10
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    /// A host that keeps balance the way the engine does, so the round trip is measurable.
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
