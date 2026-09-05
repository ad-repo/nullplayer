import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B100 — cPro2's Now Playing selector picked nothing, because a script cannot call the pointer's
/// own handlers.
///
/// Reported 2026-09-04 as "the album art window area menu does not work — not the art, file info,
/// visualizations". `WINAMP_MODERN_CALL_TRACE=1` named it in one line: the handler simply stops.
///
/// ```
/// CALL-TRACE popatxy(760,297) -> 0
/// CALL-TRACE ismouseoverrect() on button#comp.goto -> 0
/// CALL-TRACE ismouseoverrect() on Wasabi:AlbumArt#centro.playlist.wasabicover -> 0
///                                     <- nothing; `openMini(result)` never ran
/// ```
///
/// The next statement in `CentroSUI2.m` is `wasabiCover.onLeaveArea()`. The **events** were already
/// dispatched on hover (`WinampModernMainView` fires both), but neither name was in
/// `dispatchableEventArity`, and a missing *signature* fails closed in the interpreter — before the
/// call is traced at all, which is why there was no `UNSUPPORTED` line either.
///
/// It costs all three entries the report named, at two different points. `but_miniGoto.onLeftClick`
/// calls it at line 663 on `result <= 0`, and **Album Art is command id 0**, so that pick dies before
/// `openMini`. File Info (1) and Visualization (4) reach `openMini`, which hides every pane and *then*
/// calls `wasabiCover.onEnterArea()` — dying with the old pane gone and the new one not yet shown.
///
/// Arity is measured: 57 handler declarations in the ClassicPro engine and 193 across the 69-skin
/// corpus, every one `()`, and all six explicit calls in the engine pass no arguments.
final class WinampModernB100Tests: XCTestCase {

    func testThePointerHandlersAreCallableWithNoArguments() throws {
        let (runtime, _, _) = try makeRuntime()
        for name in ["onEnterArea", "onLeaveArea"] {
            let signature = try XCTUnwrap(runtime.signature(for: name, classGUID: nil),
                                          "CentroSUI calls \(name) as a method five times")
            XCTAssertEqual(signature.argumentCount, 0)
            XCTAssertEqual(signature.returnKind, .null)
        }
    }

    /// And the call is a *dispatch* on the receiver, not a swallow — and is never counted as an
    /// unsupported method, which is what took the enclosing handler down with it.
    func testCallingThemDispatchesTheHandlerOnTheReceiver() throws {
        let (runtime, program, cover) = try makeRuntime()
        runtime.recordsDispatchedEventsForTesting = true

        for name in ["onLeaveArea", "onEnterArea"] {
            _ = try runtime.invoke(method: name, on: MakiObjectReference(.gui(cover.stableID)),
                                   arguments: [], program: program)
        }

        XCTAssertEqual(runtime.dispatchedEventsForTesting.map(\.event), ["onleavearea", "onenterarea"])
        XCTAssertEqual(runtime.dispatchedEventsForTesting.map(\.object), ["cover", "cover"])
        XCTAssertNil(runtime.unsupportedMethodCalls["onleavearea"])
        XCTAssertNil(runtime.unsupportedMethodCalls["onenterarea"])
    }

    // MARK: - Helpers

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram, WasabiObject) {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <layer id="cover" x="0" y="0" w="8" h="8"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let cover = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "cover").first)
        let program = try MakiBytecodeParser().parse(makeEmptyScript(),
                                                     source: WalSourceLocation(path: "/Skins/Synthetic/skin.xml"))
        return (runtime, program, cover)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB100Tests-\(UUID().uuidString)", isDirectory: true)
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

    /// The smallest well-formed `.maki`: one class, one method, one system variable, no code. A
    /// program is only a source location to the calls above; the fixture skin declares no scripts.
    private func makeEmptyScript() -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(1, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString("getid", to: &data)
        appendUInt32(1, to: &data)
        data.append(0)
        data.append(1)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)
        data.append(1)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
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

    /// The host is only a seam here: nothing in these two calls reaches playback.
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
