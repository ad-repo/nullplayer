import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 78 — B41: monitor dimensions come from the display containing the `.wal` player.
final class WinampModernPhase78Tests: XCTestCase {

    func testMonitorMethodsUseTheWindowSuppliedLogicalScreenSize() throws {
        let (runtime, program) = try makeRuntime()
        runtime.monitorSizeRequested = { CGSize(width: 2_560, height: 1_440) }

        XCTAssertEqual(try invoke("getMonitorWidth", runtime, program).integerValue, 2_560)
        XCTAssertEqual(try invoke("getMonitorHeight", runtime, program).integerValue, 1_440)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty)
    }

    func testMonitorDimensionsFloorFractionalLogicalPoints() throws {
        let (runtime, program) = try makeRuntime()
        runtime.monitorSizeRequested = { CGSize(width: 1_727.75, height: 1_116.5) }

        XCTAssertEqual(try invoke("getMonitorWidth", runtime, program).integerValue, 1_727)
        XCTAssertEqual(try invoke("getMonitorHeight", runtime, program).integerValue, 1_116)
    }

    func testInvalidAndOversizedMonitorDimensionsDegradeSafely() throws {
        let (runtime, program) = try makeRuntime()

        runtime.monitorSizeRequested = { CGSize(width: CGFloat.nan, height: -1) }
        XCTAssertEqual(try invoke("getMonitorWidth", runtime, program).integerValue, 0)
        XCTAssertEqual(try invoke("getMonitorHeight", runtime, program).integerValue, 0)

        runtime.monitorSizeRequested = {
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat(Int32.max))
        }
        XCTAssertEqual(try invoke("getMonitorWidth", runtime, program).integerValue, Int32.max)
        XCTAssertEqual(try invoke("getMonitorHeight", runtime, program).integerValue, Int32.max)
    }

    func testTeardownReleasesTheWindowQuery() throws {
        let (runtime, _) = try makeRuntime()
        runtime.monitorSizeRequested = { CGSize(width: 2_560, height: 1_440) }

        runtime.teardown()

        XCTAssertNil(runtime.monitorSizeRequested)
    }

    private func invoke(_ method: String, _ runtime: WinampModernScriptRuntime,
                        _ program: MakiProgram) throws -> MakiValue {
        try runtime.invoke(method: method, on: MakiObjectReference(.system),
                           arguments: [], program: program)
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase78Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Phase78.wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data("""
        <WasabiXML>
          <container id="main"><layout id="normal" w="120" h="80"/></container>
        </WasabiXML>
        """.utf8)
        try archive.addEntry(with: "skin.xml", type: .file,
                             uncompressedSize: Int64(payload.count), compressionMethod: .none) {
            position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }

        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return (runtime, MakiProgram(version: 0x0403, classes: [], methods: [], variables: [],
                                     bindings: [], instructions: [],
                                     source: WalSourceLocation(path: "/Skins/Synthetic/monitor.maki"),
                                     ownerID: nil, parameter: nil))
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
        var trackDisplayTitle = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 2
        var spectrumLevels: [Float] = []
        var isArtworkLoading = false
        var vuLevels: (left: Double, right: Double) = (0, 0)

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
