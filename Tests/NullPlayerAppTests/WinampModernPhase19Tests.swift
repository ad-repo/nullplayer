import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 19 — a groupdef redefined mid-document, and what drags a window.
///
/// Measured against T800, which gives `player.main.cms` one body for its full layout and a second,
/// completely different one for its shade layout. Winamp's parser is streaming, so each `<group>`
/// expands whatever definition has been read *so far*; taking the last one silently replaced the
/// full player's controls with the shade's, most of which then fell outside the canvas and were
/// culled — every button in the skin dead but the one in the group with a unique id.
final class WinampModernPhase19Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var trackDisplayTitle = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 2
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

    /// `body` is defined twice, T800-style: the first body serves `normal`, the second `shade`.
    /// `chrome` is defined once and used by both, and `late` is referenced before it is defined.
    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="base" file="base.png"/>
        <bitmap id="knob" file="base.png" x="0" y="0" w="10" h="10"/>
      </elements>
      <groupdef id="chrome">
        <layer id="handle" image="knob" x="100" y="0"/>
      </groupdef>
      <groupdef id="body">
        <button id="fullPlay" action="Play" x="10" y="150" image="knob"/>
      </groupdef>
      <container id="main">
        <layout id="normal" background="base">
          <group id="body" w="120" h="200"/>
          <group id="chrome" w="120" h="200"/>
          <group id="late" w="120" h="200"/>
          <group id="dragbyflag" move="1" x="0" y="0" w="120" h="200"/>
          <group id="notadraghandle" move="0" x="0" y="0" w="10" h="10"/>
        </layout>
        <groupdef id="body">
          <button id="shadePlay" action="Play" x="10" y="4" image="knob"/>
        </groupdef>
        <layout id="shade" background="base" w="120" h="20">
          <group id="body" w="120" h="20"/>
        </layout>
      </container>
      <groupdef id="late">
        <button id="lateButton" action="Stop" x="60" y="60" image="knob"/>
      </groupdef>
    </WasabiXML>
    """

    // MARK: - The definition in force where the group is written

    func testEachLayoutExpandsTheDefinitionThatPrecedesIt() throws {
        let (_, renderer) = try makeSkin()
        XCTAssertTrue(renderer.sceneNodes().contains { $0.object.xmlID == "fullPlay" },
                      "the full layout keeps the body written above it")
        XCTAssertFalse(renderer.sceneNodes().contains { $0.object.xmlID == "shadePlay" })

        _ = try renderer.activateLayout(id: "shade")
        XCTAssertTrue(renderer.sceneNodes().contains { $0.object.xmlID == "shadePlay" },
                      "and the shade layout gets the redefinition below it")
        XCTAssertFalse(renderer.sceneNodes().contains { $0.object.xmlID == "fullPlay" })
    }

    func testTheEarlierDefinitionsControlsAreStillHitTestable() throws {
        let (_, renderer) = try makeSkin()
        let hit = renderer.object(at: CGPoint(x: 14, y: 154))
        XCTAssertEqual(hit?.xmlID, "fullPlay", "the button the user clicks has to be the one drawn")
    }

    func testAGroupDefinedOnceIsUnaffected() throws {
        let (_, renderer) = try makeSkin()
        XCTAssertTrue(renderer.sceneNodes().contains { $0.object.xmlID == "handle" })
        _ = try renderer.activateLayout(id: "shade")
        XCTAssertFalse(renderer.sceneNodes().contains { $0.object.xmlID == "handle" },
                       "shade simply does not reference it")
    }

    /// Winamp would render nothing here; we are deliberately more forgiving than the parser we copy.
    func testAGroupReferencedBeforeItsOnlyDefinitionStillExpands() throws {
        let (_, renderer) = try makeSkin()
        XCTAssertTrue(renderer.sceneNodes().contains { $0.object.xmlID == "lateButton" })
    }

    func testTheRedefinitionIsReportedRatherThanSilentlyApplied() throws {
        let (loaded, _) = try makeSkin()
        XCTAssertTrue(loaded.runtime.diagnostics.contains {
            $0.code == .duplicateIdentifier && $0.message.contains("'body'")
        })
    }

    // MARK: - What drags the window

    @MainActor
    func testTheLayoutBackgroundDragsTheWindow() throws {
        let (view, renderer) = try makeView()
        let layout = try XCTUnwrap(renderer.object(at: CGPoint(x: 119, y: 199)))
        XCTAssertEqual(layout.typeName.lowercased(), "layout",
                       "the corner of this fixture is bare background")
        XCTAssertTrue(view.shouldDragWindow(from: layout),
                      "a skin that paints its whole frame on the layout has nothing else to drag by")
    }

    @MainActor
    func testABareGroupDragsOnlyWhenTheSkinSaysItMoves() throws {
        let (view, renderer) = try makeView()
        let objects = renderer.sceneNodes().map(\.object)
        let moving = try XCTUnwrap(objects.first { $0.attributes["id"] == "dragbyflag" })
        let fixed = try XCTUnwrap(objects.first { $0.attributes["id"] == "notadraghandle" })
        XCTAssertTrue(view.shouldDragWindow(from: moving))
        XCTAssertFalse(view.shouldDragWindow(from: fixed))
    }

    @MainActor
    func testALayerTheSkinPinsIsNotADragHandle() throws {
        let (view, renderer) = try makeView()
        let handle = try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "handle" }?.object)
        XCTAssertTrue(view.shouldDragWindow(from: handle))
        _ = handle.setAttribute("move", value: "0")
        XCTAssertFalse(view.shouldDragWindow(from: handle),
                       "move=\"0\" is the skin claiming that press for itself")
    }

    // MARK: - Fixture

    private func makeSkin() throws -> (WinampModernLoadedSkin, WasabiSceneRenderer) {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return (loaded, renderer)
    }

    @MainActor
    private func makeView() throws -> (WinampModernMainView, WasabiSceneRenderer) {
        let (loaded, renderer) = try makeSkin()
        let host = Host()
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                        componentHost: nil)
        view.setFrameSize(renderer.canvasSize)
        return (view, renderer)
    }

    private func makeArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase19Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let entries: [(String, Data)] = [("skin.xml", Data(Self.skinXML.utf8)),
                                         ("base.png", try makePNG(width: 120, height: 200))]
        for (path, payload) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = 40
            pixels[offset + 1] = 90
            pixels[offset + 2] = 30
        }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
