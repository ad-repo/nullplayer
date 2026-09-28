import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B152 — a script stepping an `<animatedlayer>` repaints that layer, not the window.
///
/// WMP11-BlueVU's `beatvisualization.maki` calls `gotoframe` on 12 layers every 10 ms. Each call
/// ended in `notifyObjectDidMutate`, which is the main window's whole-window relayout and repaint,
/// so the player repainted its full area ~120 times a second while music played.
final class WinampModernB152Tests: XCTestCase {

    /// A step of a stopped layer is a cell swap, so it takes the object-targeted repaint seam.
    func testSteppingAStoppedLayerRepaintsOnlyThatLayer() throws {
        let (runtime, layer) = try makeRuntime()
        try invoke("gotoframe", on: layer, runtime: runtime, [.integer(0)])
        let counts = observe(runtime)
        try invoke("gotoframe", on: layer, runtime: runtime, [.integer(3)])
        XCTAssertEqual(counts.mutations(), 0, "no whole-window relayout for a cell swap")
        XCTAssertEqual(counts.objectRepaints(), [layer.stableID])
    }

    /// The beat meter asks for the frame it already shows on most ticks. That is not a change.
    func testSteppingToTheSameFrameRepaintsNothing() throws {
        let (runtime, layer) = try makeRuntime()
        try invoke("gotoframe", on: layer, runtime: runtime, [.integer(3)])
        let counts = observe(runtime)
        try invoke("gotoframe", on: layer, runtime: runtime, [.integer(3)])
        XCTAssertEqual(counts.mutations(), 0)
        XCTAssertEqual(counts.objectRepaints(), [])
    }

    /// Stopping a self-playing layer changes the animation clock's set, which only the full
    /// notification re-reads.
    func testSteppingAPlayingLayerStillTakesTheFullNotification() throws {
        let (runtime, layer) = try makeRuntime()
        try invoke("play", on: layer, runtime: runtime, [])
        let counts = observe(runtime)
        try invoke("gotoframe", on: layer, runtime: runtime, [.integer(2)])
        XCTAssertEqual(counts.mutations(), 1)
        XCTAssertEqual(layer.attributes["playing"], "0")
    }

    // MARK: - Helpers

    private static let skin = """
    <WasabiXML>
      <container id="main" name="Main">
        <layout id="normal" w="100" h="40">
          <animatedlayer id="beat" x="10" y="10" w="20" h="20"/>
        </layout>
      </container>
    </WasabiXML>
    """

    private struct Counts {
        let mutations: () -> Int
        let objectRepaints: () -> [WasabiObjectID]
    }

    private func observe(_ runtime: WinampModernScriptRuntime) -> Counts {
        var mutations = 0
        var repaints: [WasabiObjectID] = []
        runtime.graphDidMutate = { mutations += 1 }
        runtime.objectRepaintRequested = { repaints.append($0.stableID) }
        return Counts(mutations: { mutations }, objectRepaints: { repaints })
    }

    private func invoke(_ method: String, on object: WasabiObject, runtime: WinampModernScriptRuntime,
                        _ arguments: [MakiValue]) throws {
        _ = try runtime.invoke(method: method, on: MakiObjectReference(.gui(object.stableID)),
                               arguments: arguments, program: emptyProgram())
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, WasabiObject) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB152Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(Self.skin.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let layer = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "beat").first)
        return (runtime, layer)
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
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
