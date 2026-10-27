import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B299 — Quadelic's `vol +`/`vol -` (`action="VOLUME_UP"`/`"VOLUME_DOWN"`) had no handler.
final class WinampModernB299Tests: XCTestCase {
    func testVolumeButtonsStepTheHostBothWays() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="100">
              <button id="up" action="VOLUME_UP" x="0" y="0" w="20" h="20"/>
              <button id="down" action="VOLUME_DOWN" x="40" y="0" w="20" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host, componentHost: nil)
        view.setFrameSize(renderer.canvasSize)

        func click(_ id: String) throws {
            let object = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: id).first)
            let frame = try XCTUnwrap(renderer.frame(of: object))
            let point = NSPoint(x: frame.midX, y: renderer.canvasSize.height - frame.midY)
            for (type, number) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                             timestamp: 0, windowNumber: 0, context: nil,
                                                             eventNumber: number, clickCount: 1, pressure: 1))
                if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
            }
        }
        try click("up")
        XCTAssertEqual(host.volume, 0.55, accuracy: 1e-9)
        try click("down")
        try click("down")
        XCTAssertEqual(host.volume, 0.45, accuracy: 1e-9)
    }

    private final class TestHost: WinampModernHost {
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

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB299Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B299-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
