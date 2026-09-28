import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B148 — Shield_Amp's and Ebonite_2_1's `OneDirectionText` ticker never scrolled.
///
/// Three links, each measured live: Winamp's own *Text Ticker Speed* preference read `""` (so the
/// move delay was infinite), `Timer.getDelay()` was unimplemented (so the tick handler aborted before
/// moving anything), and `setDelay` on a running timer did not re-arm it (so the 60 ms step stayed on
/// the 1000 ms first delay). Winamp answers `"0.333333"`, returns the delay, and re-arms.
final class WinampModernB148Tests: XCTestCase {
    private static let uiOptions = "{9149C445-3C30-4e04-8433-5A518ED0FDDE}"

    func testTheTickerSpeedAnswersWinampsDefault() throws {
        let runtime = try makeRuntime()
        XCTAssertEqual(try tickerSpeed(section: Self.uiOptions, in: runtime), "0.333333")
    }

    /// Ebonite spells the same GUID `4E04` in other scripts; Winamp parses the GUID, so case is moot.
    func testTheTickerSpeedIgnoresTheGUIDsHexCase() throws {
        let runtime = try makeRuntime()
        XCTAssertEqual(try tickerSpeed(section: Self.uiOptions.uppercased(), in: runtime), "0.333333")
    }

    /// A stored value still wins: the default only answers an unset preference.
    func testAStoredTickerSpeedOutranksTheDefault() throws {
        let runtime = try makeRuntime()
        runtime.loadedSkin.configuration.setString("0", section: Self.uiOptions, key: "Text Ticker Speed")
        XCTAssertEqual(try tickerSpeed(section: Self.uiOptions, in: runtime), "0")
    }

    /// Only Winamp's own preferences get a default; a skin's unset attribute still reads empty.
    func testAnUnrelatedAttributeStillReadsEmpty() throws {
        let runtime = try makeRuntime()
        let item = try invoke("getitembyguid", on: MakiObjectReference(.system),
                              [.string(Self.uiOptions)], in: runtime)
        let attribute = try invoke("getattribute", on: try reference(item),
                                   [.string("Enable desktop alpha")], in: runtime)
        XCTAssertEqual(try invoke("getdata", on: try reference(attribute), [], in: runtime).stringValue, "")
    }

    func testGetDelayAnswersTheDelayAsSet() throws {
        let runtime = try makeRuntime()
        let timer = try makeTimer(in: runtime)
        _ = try invoke("setdelay", on: timer, [.integer(1000)], in: runtime)
        XCTAssertEqual(try invoke("getdelay", on: timer, [], in: runtime).integerValue, 1000)
    }

    /// The ticker's own sequence: start on the first delay, then drop to the step from `onTimer`.
    func testSetDelayReArmsARunningTimer() throws {
        let runtime = try makeRuntime()
        let timer = try makeTimer(in: runtime)
        guard case .dynamic(let id) = timer.kind else { return XCTFail("not a dynamic object") }
        _ = try invoke("setdelay", on: timer, [.integer(1000)], in: runtime)
        _ = try invoke("start", on: timer, [], in: runtime)
        XCTAssertEqual(try XCTUnwrap(runtime.timers.period(id: id)), 1.0, accuracy: 0.0001)

        _ = try invoke("setdelay", on: timer, [.integer(60)], in: runtime)
        XCTAssertEqual(try XCTUnwrap(runtime.timers.period(id: id)), 0.06, accuracy: 0.0001)
    }

    /// Setting a delay on a stopped timer must not start it.
    func testSetDelayLeavesAStoppedTimerStopped() throws {
        let runtime = try makeRuntime()
        let timer = try makeTimer(in: runtime)
        guard case .dynamic(let id) = timer.kind else { return XCTFail("not a dynamic object") }
        _ = try invoke("setdelay", on: timer, [.integer(60)], in: runtime)
        XCTAssertFalse(runtime.timers.contains(id: id))
    }

    // MARK: - Fixtures

    private func tickerSpeed(section: String, in runtime: WinampModernScriptRuntime) throws -> String {
        let item = try invoke("getitembyguid", on: MakiObjectReference(.system), [.string(section)],
                              in: runtime)
        let attribute = try invoke("getattribute", on: try reference(item),
                                   [.string("Text Ticker Speed")], in: runtime)
        return try invoke("getdata", on: try reference(attribute), [], in: runtime).stringValue
    }

    private func makeTimer(in runtime: WinampModernScriptRuntime) throws -> MakiObjectReference {
        try runtime.makeObject(classGUID: "{00000000-0000-0000-0000-000000000000}", program: emptyProgram())
    }

    private func reference(_ value: MakiValue) throws -> MakiObjectReference {
        guard case .object(let reference) = value else {
            XCTFail("expected an object, got \(value)")
            throw CancellationError()
        }
        return reference
    }

    private func invoke(_ method: String, on reference: MakiObjectReference, _ arguments: [MakiValue],
                        in runtime: WinampModernScriptRuntime) throws -> MakiValue {
        try runtime.invoke(method: method, on: reference, arguments: arguments, program: emptyProgram())
    }

    private func makeRuntime() throws -> WinampModernScriptRuntime {
        let xml = """
        <WasabiXML>
          <container id="Main"><layout id="normal" w="40" h="20"/></container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil)
            .load(from: try makeArchive(files: [("skin.xml", Data(xml.utf8))]))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let section = Self.uiOptions
        runtime.loadedSkin.configuration.removeValue(section: section, key: "Text Ticker Speed")
        runtime.loadedSkin.configuration.removeValue(section: section.uppercased(), key: "Text Ticker Speed")
        addTeardownBlock {
            runtime.loadedSkin.configuration.removeValue(section: section, key: "Text Ticker Speed")
        }
        return runtime
    }

    private func makeArchive(files: [(String, Data)]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB148Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Synthetic Song"
        var trackInfo = "Synthetic Artist"
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
