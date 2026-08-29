import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B64 — Anexa's progress bar was invisible unless it was full.
///
/// Anexa draws both its main and its shade progress bar as a `<layer>` with no artwork of its own
/// beyond a gradient, clipped by a region map:
///
/// ```c
/// UpateTimer.onTimer() {
///   System.onSeek(getPosition());
/// }
/// System.onSeek(int newpos) {
///   if (newpos <= 0) return;
///   int len = getPlayItemLength();
///   if (len <= 0) return;
///   int devby = len/255;
///   if (devby <= 0) return;
///   spos.setRegionFromMap(sPosMap, newpos/devby, 1);
/// }
/// ```
///
/// Two independent faults stacked on it, and the *symptom* of both is the same empty bar:
///
/// 1. **`onSeek` was not in `dispatchableEventArity`.** The skin calls its own system handler as a
///    method, which is the only thing that ever fills the bar. Dispatch is fail-closed, so the call
///    abandoned the whole `onTimer` at its first statement and the region never moved. The bar was
///    seen full because `onStop` sets it to 255 — the one path that did run.
///
/// 2. **`getPosition()`/`getPlayItemLength()` answered seconds.** `int devby = len/255` then
///    truncates to **zero** for every track under 4:15 and takes the guard above, so even a
///    dispatched handler drew nothing. The unit is milliseconds: most of the corpus divides the two
///    into a ratio and cannot tell, so it has to be read off the skins that do absolute arithmetic —
///    this one, and Styx's notifier, which formats `getPlayItemLength()/1000` by hand.
///
/// The family moves together: `getPosition`, `getPlayItemLength`, `seekTo`, `integerToTime` and the
/// `length` metadata key. Splitting them is what would make a skin's own arithmetic disagree with its
/// own readout.
final class WinampModernB64Tests: XCTestCase {

    // MARK: - Fault 1: `System.onSeek` is callable

    func testOnSeekIsDispatchableWithOneArgument() throws {
        let (runtime, _) = try makeRuntime()
        let signature = try XCTUnwrap(runtime.signature(for: "onSeek", classGUID: nil),
                                      "Anexa's progress bar is filled by calling this handler")
        XCTAssertEqual(signature.argumentCount, 1)
        XCTAssertEqual(signature.returnKind, .null)
    }

    /// And the call is a *dispatch*, not a swallow — and is never counted as an unsupported method,
    /// which is what took the enclosing `onTimer` down with it.
    func testCallingOnSeekDispatchesTheSystemHandler() throws {
        let (runtime, program) = try makeRuntime()
        runtime.recordsDispatchedEventsForTesting = true

        _ = try runtime.invoke(method: "onSeek", on: MakiObjectReference(.system),
                               arguments: [.integer(105_000)], program: program)

        XCTAssertEqual(runtime.dispatchedSystemEventsForTesting.map(\.event), ["onseek"])
        XCTAssertEqual(runtime.dispatchedSystemEventsForTesting.first?.arguments.first?.integerValue,
                       105_000)
        XCTAssertNil(runtime.unsupportedMethodCalls["onseek"])
    }

    // MARK: - Fault 2: the time family is milliseconds

    func testThePlaybackClockIsReportedInMilliseconds() throws {
        let host = TestHost()
        host.currentTime = 105
        host.duration = 210
        let (runtime, program) = try makeRuntime(host: host)

        XCTAssertEqual(try call(runtime, program, "getPosition").integerValue, 105_000)
        XCTAssertEqual(try call(runtime, program, "getPlayItemLength").integerValue, 210_000)
        XCTAssertEqual(host.playItemMetadata(forKey: "length"), "210000")
        XCTAssertEqual(try call(runtime, program, "integerToTime",
                                [.integer(210_000)]).stringValue, "3:30")
    }

    /// `seekTo` reads what the other two answer, so a skin that scales the length by a map value
    /// lands where it aimed rather than a thousand times short.
    func testSeekToTakesTheSameMilliseconds() throws {
        let host = TestHost()
        host.duration = 210
        let (runtime, program) = try makeRuntime(host: host)

        _ = try call(runtime, program, "seekTo", [.integer(105_000)])
        XCTAssertEqual(host.seekedTo, 105)
    }

    /// The defect itself, in the skin's own arithmetic: `len/255` has to survive the narrowing store
    /// into an Int. In seconds a 3:30 track gives `devby == 0` and the handler returns without
    /// touching the region — which is the empty bar, exactly.
    func testAnexasScalingSurvivesTheNarrowingStoreOnAnOrdinaryTrack() throws {
        let host = TestHost()
        host.currentTime = 105
        host.duration = 210
        let (runtime, program) = try makeRuntime(host: host)

        let length = Int(try call(runtime, program, "getPlayItemLength").integerValue)
        let position = Int(try call(runtime, program, "getPosition").integerValue)
        let devby = length / 255
        XCTAssertGreaterThan(devby, 0, "a seconds answer truncates to 0 here and the bar stays empty")
        // Halfway through the track is halfway up the region map's 0…255 sweep.
        XCTAssertEqual(position / devby, 127)
    }

    // MARK: - Helpers

    private func call(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                      _ method: String, _ arguments: [MakiValue] = []) throws -> MakiValue {
        try runtime.invoke(method: method, on: MakiObjectReference(.system),
                           arguments: arguments, program: program)
    }

    private func makeRuntime(host: WinampModernHost? = nil) throws -> (WinampModernScriptRuntime, MakiProgram) {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <layer id="seek" x="0" y="0" w="4" h="4"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host ?? TestHost())
        addTeardownBlock { runtime.teardown() }
        // A program is only a source location to these calls; the fixture skin declares no scripts.
        let program = try MakiBytecodeParser().parse(makeEmptyScript(),
                                                     source: WalSourceLocation(path: "/Skins/Synthetic/skin.xml"))
        return (runtime, program)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB64Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
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

    /// The smallest well-formed `.maki`: one class, one method, one variable, no code.
    /// The smallest well-formed `.maki`: one class, one method, one system variable, no code. A
    /// program is only a source location to the calls above; the fixture skin declares no scripts.
    private func makeEmptyScript() -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString("getid", to: &data)
        appendUInt32(1, to: &data)                                  // variables
        data.append(0)                                              // type offset
        data.append(1)                                              // object
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)                                  // initial
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)
        data.append(1)                                              // system
        appendUInt32(0, to: &data)                                  // constants
        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(0, to: &data)                                  // code
        return data
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    private final class TestHost: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []
        var seekedTo: TimeInterval?

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) { seekedTo = seconds }
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
