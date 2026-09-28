import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B99 — `Group.getNumObjects()` / `Group.enumObject(i)`.
///
/// ClassicPro's InfoViewer (`xui/CentroSUI/_v2/InfoViewer/auto_arange.m`) counts its tag lines in
/// `onScriptLoaded` and lays them out by index in `onResize`/`onAction`. Both calls were unsupported,
/// dispatch fails closed per handler, and all three handlers died: measured on cPro2 Dark Aluminum
/// 2026-09-27 the track-info pane under the library drew empty, and drew its tag lines once the calls
/// answered (A/B in one binary, live).
///
/// The script indexes the walk in declaration order — `a==11` is its rating group — so the answer
/// must be the group's own children, in order, and nothing else.
final class WinampModernB99Tests: XCTestCase {

    func testGetNumObjectsCountsTheGroupsDirectChildren() throws {
        let (runtime, program) = try makeRuntime()
        let count = try runtime.invoke(method: "getNumObjects", on: reference(try object(runtime, "lines")),
                                       arguments: [], program: program)
        XCTAssertEqual(count.integerValue, 3)
    }

    func testEnumObjectWalksChildrenInDeclarationOrder() throws {
        let (runtime, program) = try makeRuntime()
        let group = reference(try object(runtime, "lines"))
        var ids: [String] = []
        for index in 0..<3 {
            let value = try runtime.invoke(method: "enumObject", on: group,
                                           arguments: [.integer(Int32(index))], program: program)
            let id = try XCTUnwrap(guiID(of: value))
            ids.append(try XCTUnwrap(runtime.loadedSkin.runtime.graph.object(withID: id)?.xmlID))
        }
        XCTAssertEqual(ids, ["first", "second", "rating"])
    }

    /// Past the end is NULL, not an error — the script null-checks (`if(obj1 == NULL …)`).
    func testEnumObjectOutOfRangeIsNull() throws {
        let (runtime, program) = try makeRuntime()
        let group = reference(try object(runtime, "lines"))
        for index: Int32 in [3, -1] {
            let value = try runtime.invoke(method: "enumObject", on: group,
                                           arguments: [.integer(index)], program: program)
            XCTAssertNil(guiID(of: value))
        }
    }

    /// Without a signature the interpreter fails closed before the call is made at all.
    func testBothMethodsHaveSignatures() throws {
        let (runtime, _) = try makeRuntime()
        XCTAssertEqual(try XCTUnwrap(runtime.signature(for: "getNumObjects", classGUID: nil)).argumentCount, 0)
        XCTAssertEqual(try XCTUnwrap(runtime.signature(for: "enumObject", classGUID: nil)).argumentCount, 1)
    }

    // MARK: - Fixtures

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try load(files: [
            ("skin.xml", Data("""
            <WasabiXML>
              <container id="main">
                <layout id="normal" w="250" h="250">
                  <group id="lines" x="0" y="0" w="200" h="100">
                    <text id="first" x="0" y="0" w="200" h="14" text="Title:"/>
                    <text id="second" x="0" y="14" w="200" h="14" text="Artist:"/>
                    <group id="rating" x="0" y="28" w="200" h="14"/>
                  </group>
                </layout>
              </container>
            </WasabiXML>
            """.utf8)),
        ])
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return (runtime, Self.emptyProgram(path: "/Skins/Synthetic/b99.maki"))
    }

    private static func emptyProgram(path: String) -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: path),
                    ownerID: nil, parameter: nil)
    }

    private func guiID(of value: MakiValue) -> WasabiObjectID? {
        guard case .object(let reference) = value, case .gui(let id) = reference.kind else { return nil }
        return id
    }

    private func object(_ runtime: WinampModernScriptRuntime, _ id: String) throws -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: id).first)
    }

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
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

    private func load(files: [(String, Data)]) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB99Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B99-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return try WinampModernSkinLoader(engineStore: nil).load(from: url)
    }
}
