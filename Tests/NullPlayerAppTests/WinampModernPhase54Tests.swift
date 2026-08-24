import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 54 — BB7, `GroupList.instantiate(groupdef, count)`.
///
/// Big Bento Modern builds all nine of its config pages and the SUI's equalizer tab out of an
/// empty `<GroupList>` plus a scrollbar; every option on those pages lives in a `…part1` / `…part2`
/// groupdef that `config_vscrollbars.maki` expands into the list at load. Without the method the
/// handler aborted at its first call and the pages had no content at all — which is why all four
/// variants reported compatibility level `unsupported` although they drew.
///
/// Three things BB1 (this item's superseded first draft) had wrong, all settled from the bytecode:
/// the second argument is a **count**, not an index; the receiver is a `GroupList`, not a plain
/// `Group`; and there are two call sites in one script, not nine — the nine are nine *declarations*
/// of that same script, each with its own `param`.
///
/// The stacking is the part a groupdef cannot carry: the parts declare `h=` and no `w=` at all, so a
/// child left at its markup geometry is zero-width (and its own contents, which are `w="-203"
/// relatw="1"` against it, negative), and both parts would sit at `y=0` on top of each other.
final class WinampModernPhase54Tests: XCTestCase {

    // MARK: - instantiate

    func testInstantiateAddsTheGroupDefinitionToTheList() throws {
        let (runtime, list) = try makeListRuntime()
        let created = try runtime.invoke(method: "instantiate", on: reference(list),
                                         arguments: [.string("page.part1"), .integer(1)],
                                         program: emptyProgram())
        XCTAssertEqual(list.children.count, 1)
        let child = try XCTUnwrap(list.children.first)
        XCTAssertEqual(child.xmlID, "page.part1")
        // The call answers the group it made: the script keeps it in a `Group` local.
        guard case .object(let handle) = created, case .gui(let id) = handle.kind else {
            return XCTFail("instantiate answers the group it created")
        }
        XCTAssertEqual(id, child.stableID)
        // The groupdef's own contents came with it, which is the whole point of the call.
        XCTAssertEqual(child.children.count, 1)
        XCTAssertEqual(child.children.first?.xmlID, "part1.body")
    }

    func testTheSecondArgumentIsACountAndNotAnIndex() throws {
        let (runtime, list) = try makeListRuntime()
        _ = try runtime.invoke(method: "instantiate", on: reference(list),
                               arguments: [.string("page.part1"), .integer(3)],
                               program: emptyProgram())
        XCTAssertEqual(list.children.count, 3, "\"3\" is the amount of times the group is instantiated")
    }

    func testTwoCallsStackTopToBottomByTheirDeclaredHeights() throws {
        let (runtime, list) = try makeListRuntime()
        _ = try runtime.invoke(method: "instantiate", on: reference(list),
                               arguments: [.string("page.part1"), .integer(1)],
                               program: emptyProgram())
        _ = try runtime.invoke(method: "instantiate", on: reference(list),
                               arguments: [.string("page.part2"), .integer(1)],
                               program: emptyProgram())
        XCTAssertEqual(list.children.count, 2)
        XCTAssertEqual(list.children[0].attributes["y"], "0")
        // `page.part1` declares h="223", so the second entry starts where the first one ends rather
        // than covering it.
        XCTAssertEqual(list.children[1].attributes["y"], "223")
        XCTAssertEqual(list.children[1].attributes["h"], "220", "each entry keeps its own height")
    }

    func testEachEntrySpansTheListWidth() throws {
        let (runtime, list) = try makeListRuntime()
        _ = try runtime.invoke(method: "instantiate", on: reference(list),
                               arguments: [.string("page.part1"), .integer(1)],
                               program: emptyProgram())
        let child = try XCTUnwrap(list.children.first)
        XCTAssertEqual(child.attributes["x"], "0")
        XCTAssertEqual(child.attributes["w"], "0")
        XCTAssertEqual(child.attributes["relatw"], "1",
                       "a groupdef declares no width, and a zero-width entry draws nothing")
    }

    /// The stacking belongs to the list, not to instantiation: `System.newGroup` puts a groupdef
    /// under an arbitrary parent and must leave the markup's geometry exactly as it found it.
    func testANonListParentKeepsTheGroupDefinitionsOwnGeometry() throws {
        let (runtime, _) = try makeListRuntime()
        let plain = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "plaingroup").first)
        _ = try runtime.invoke(method: "instantiate", on: reference(plain),
                               arguments: [.string("page.part1"), .integer(1)],
                               program: emptyProgram())
        let child = try XCTUnwrap(plain.children.first)
        XCTAssertNil(child.attributes["relatw"])
        XCTAssertEqual(child.attributes["h"], "223")
    }

    func testAnUnknownGroupDefinitionFailsRatherThanAddingAnEmptyEntry() throws {
        let (runtime, list) = try makeListRuntime()
        XCTAssertThrowsError(try runtime.invoke(method: "instantiate", on: reference(list),
                                                arguments: [.string("page.nosuch"), .integer(1)],
                                                program: emptyProgram()))
        XCTAssertTrue(list.children.isEmpty)
    }

    /// The count is skin input, so it is bounded — a skin cannot ask for a million entries and make
    /// the engine build them.
    func testTheCountIsBoundedAndANonPositiveCountAddsNothing() throws {
        let (runtime, list) = try makeListRuntime()
        _ = try runtime.invoke(method: "instantiate", on: reference(list),
                               arguments: [.string("page.part1"), .integer(-4)],
                               program: emptyProgram())
        XCTAssertTrue(list.children.isEmpty)
        _ = try runtime.invoke(method: "instantiate", on: reference(list),
                               arguments: [.string("page.part1"), .integer(100_000)],
                               program: emptyProgram())
        XCTAssertLessThanOrEqual(list.children.count, 64)
        XCTAssertGreaterThan(list.children.count, 0)
    }

    /// Arity is the one thing the interpreter cannot recover from getting wrong: a mismatch leaves
    /// values on the stack and desynchronises everything after the call.
    func testInstantiateIsDeclaredWithTwoArgumentsAndAnObjectResult() throws {
        let (runtime, _) = try makeListRuntime()
        let signature = try XCTUnwrap(runtime.signature(for: "instantiate", classGUID: nil))
        XCTAssertEqual(signature.argumentCount, 2)
        XCTAssertEqual(signature.returnKind, .object)
    }

    // MARK: - getApplicationPath

    /// The method behind `instantiate` in the same cascade: with the pages built, the Localization
    /// page's own script ran and aborted on this. The skin concatenates a `/Lang/*.wlz` filename
    /// onto it and probes with `File.load`/`exists`/`getSize`, all of which are sandboxed here, so
    /// the branch it takes ("that language pack is not installed") is the truthful one.
    func testGetApplicationPathAnswersAnAbsoluteDirectory() throws {
        let (runtime, _) = try makeListRuntime()
        let path = try runtime.invoke(method: "getapplicationpath", on: MakiObjectReference(.system),
                                      arguments: [], program: emptyProgram()).stringValue
        XCTAssertTrue(path.hasPrefix("/"))
        XCTAssertFalse(path.hasSuffix("/"), "callers append their own separator")
    }

    // MARK: - Helpers

    private func makeListRuntime() throws -> (WinampModernScriptRuntime, WasabiObject) {
        let loaded = try load(xml: """
        <WasabiXML>
          <groupdef id="page.part1" h="223">
            <rect id="part1.body" x="0" y="0" w="0" h="0" relatw="1" relath="1" color="0,0,0"/>
          </groupdef>
          <groupdef id="page.part2" h="220">
            <rect id="part2.body" x="0" y="0" w="0" h="0" relatw="1" relath="1" color="0,0,0"/>
          </groupdef>
          <container id="main">
            <layout id="normal" w="400" h="600">
              <GroupList id="grplst" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
              <group id="plaingroup" x="0" y="0" w="10" h="10"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let list = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "grplst").first)
        return (runtime, list)
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase54Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase54-\(UUID().uuidString).wal")
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

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackArtist = ""
        var trackAlbum = ""
        var trackInfo = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var spectrumLevels: [Float] = []
        var trackDisplayTitle: String {
            trackArtist.isEmpty ? trackTitle : "\(trackArtist) - \(trackTitle)"
        }
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
