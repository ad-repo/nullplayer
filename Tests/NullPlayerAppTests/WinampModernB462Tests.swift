import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B462 — KTENSION's Library rows read teal on teal: a skin layer declared after the library's holder
/// painted over its plate. A Library in a window of its own now joins the playlist (B292) in the overlay
/// pass; embedded in the player it stays inline, under art the skin draws over it on purpose.
final class WinampModernB462Tests: XCTestCase {

    func testTheLibraryDefersOnlyInAWindowOfItsOwn() throws {
        let own = try makeRenderer(containerID: "ml")
        let player = try makeRenderer(containerID: "main")
        XCTAssertTrue(own.defersToOverlayPass(.library))
        XCTAssertFalse(player.defersToOverlayPass(.library))
        for renderer in [own, player] {
            XCTAssertTrue(renderer.defersToOverlayPass(.waveformSeeker))
            XCTAssertEqual(renderer.defersToOverlayPass(.playlist), !WasabiSceneRenderer.drawsPlaylistInline)
            XCTAssertFalse(renderer.defersToOverlayPass(.equalizer))
        }
    }

    // MARK: - Fixtures

    private func makeRenderer(containerID: String) throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" default_w="200" default_h="100"><layer id="a" x="0" y="0" w="200" h="100"/></layout>
          </container>
          <container id="ml">
            <layout id="normal" default_w="200" default_h="100"><layer id="b" x="0" y="0" w="200" h="100"/></layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost(), containerID: containerID)
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB462Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B462-\(UUID().uuidString).wal")
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
}
