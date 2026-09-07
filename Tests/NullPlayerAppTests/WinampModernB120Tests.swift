import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B120 — a script asking its group for an id that a skin declares twice must be given the object
/// that **came up**, not the copy-paste leftover that did not.
///
/// Reported 2026-09-04 as *"in t800 skin the play button on the jaw does not work properly"*. T800's
/// jaw stacks `Play` and `Pause` on the same rect (105,288, both on `player.main.play`), and
/// `scripts/play2pause.maki` is supposed to keep exactly one of them visible. But `player-normal.xml`
/// declares a **second** `id="Pause"` earlier in the same group, parked at x=803 in a 177-wide layout
/// and drawn from `player.main.pause` — a bitmap the skin never declares, so the object has no size
/// and can neither draw nor be clicked. `getObject("Pause")` returned that corpse, the script hid and
/// showed it all session, and the live Pause on the jaw — declared *after* Play, so topmost-wins gives
/// it every click — was never hidden. Pressing play on the jaw sent `pause`, in every playback state.
///
/// The rule is narrow on purpose. Duplicate ids inside one group or layout are ordinary — 304 of them
/// across the 61-skin corpus — and declaration order still decides between two live objects. Only a
/// dead one steps aside, using the same notion of dead Wasabi exposes to skins as `isInvalid()`, and
/// only 6 lookups in the whole corpus have a dead candidate ahead of a live one.
final class WinampModernB120Tests: XCTestCase {

    /// T800's group, reduced to the three buttons that matter and in its declaration order.
    private static let jaw = """
    <WasabiXML>
      <elements>
        <bitmap id="play.image" file="$solid" color="255,255,255" w="27" h="13"/>
      </elements>
      <container id="Main">
        <layout id="normal" w="177" h="400">
          <group id="jaw" w="177" h="400">
            <button id="Pause" x="803" y="11" image="player.main.pause"/>
            <button id="Play" x="105" y="288" image="play.image"/>
            <button id="Pause" x="105" y="288" image="play.image"/>
          </group>
        </layout>
      </container>
    </WasabiXML>
    """

    // MARK: - The report

    /// The whole defect in one assertion: the script's `Pause` is the button on the jaw.
    func testGetObjectSkipsADuplicateThatNeverCameUp() throws {
        let runtime = try makeRuntime(xml: Self.jaw)
        let group = try object(named: "jaw", in: runtime)
        let matches = runtime.loadedSkin.runtime.graph.objects(xmlID: "Pause")
        XCTAssertEqual(matches.count, 2, "the fixture must make the lookup order observable")
        let dead = try XCTUnwrap(matches.first)
        let live = try XCTUnwrap(matches.last)
        XCTAssertTrue(runtime.isInvalid(dead), "the leftover names a bitmap the skin never declares")
        XCTAssertFalse(runtime.isInvalid(live))

        XCTAssertEqual(try invokeLookup("getobject", id: "Pause", from: group, in: runtime),
                       live.stableID)
    }

    /// `findObject` reaches wider but resolves the same way — it is the same lookup underneath, and a
    /// skin that spells the call the other way must not get the corpse back.
    func testFindObjectResolvesTheSameWay() throws {
        let runtime = try makeRuntime(xml: Self.jaw)
        let group = try object(named: "jaw", in: runtime)
        let live = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "Pause").last)

        XCTAssertEqual(try invokeLookup("findobject", id: "Pause", from: group, in: runtime),
                       live.stableID)
    }

    // MARK: - What the rule leaves alone

    /// Two live duplicates still resolve to the first, which is the behaviour every other skin has.
    func testTwoLiveDuplicatesStillResolveToTheFirst() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="play.image" file="$solid" color="255,255,255" w="4" h="4"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <group id="jaw" w="100" h="100">
                <button id="Pause" x="0" y="0" image="play.image"/>
                <button id="Pause" x="8" y="0" image="play.image"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """
        let runtime = try makeRuntime(xml: xml)
        let group = try object(named: "jaw", in: runtime)
        let first = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "Pause").first)

        XCTAssertEqual(try invokeLookup("getobject", id: "Pause", from: group, in: runtime),
                       first.stableID)
    }

    /// An id that is *only* ever dead still answers with it. ClassicPro asks for such objects on
    /// purpose — `isInvalid()` is how a script probes for artwork a skin is free to remove — and
    /// handing back null there would abandon the handler that asked.
    func testADeadObjectIsStillFoundWhenItIsTheOnlyMatch() throws {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <group id="jaw" w="100" h="100">
                <layer id="probe" image="never.declared"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """
        let runtime = try makeRuntime(xml: xml)
        let group = try object(named: "jaw", in: runtime)
        let probe = try object(named: "probe", in: runtime)
        XCTAssertTrue(runtime.isInvalid(probe))

        XCTAssertEqual(try invokeLookup("getobject", id: "probe", from: group, in: runtime),
                       probe.stableID)
    }

    /// An object carrying no artwork at all — a group, a text, a container — is never dead, so the
    /// rule cannot reorder the lookups that make up most of the corpus's duplicates.
    func testAnObjectWithNoImageIsNeverTreatedAsDead() throws {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <group id="jaw" w="100" h="100">
                <group id="pane" w="10" h="10"/>
                <group id="pane" w="20" h="20"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """
        let runtime = try makeRuntime(xml: xml)
        let group = try object(named: "jaw", in: runtime)
        let first = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "pane").first)
        XCTAssertFalse(runtime.isInvalid(first))

        XCTAssertEqual(try invokeLookup("getobject", id: "pane", from: group, in: runtime),
                       first.stableID)
    }

    // MARK: - Fixture

    private func makeRuntime(xml: String) throws -> WinampModernScriptRuntime {
        let loaded = try WinampModernSkinLoader(engineStore: nil)
            .load(from: try makeArchive(files: [("skin.xml", Data(xml.utf8))]))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func object(named xmlID: String, in runtime: WinampModernScriptRuntime) throws
        -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: xmlID).first)
    }

    private func invokeLookup(_ method: String, id: String, from object: WasabiObject,
                              in runtime: WinampModernScriptRuntime) throws -> WasabiObjectID? {
        let value = try runtime.invoke(method: method, on: MakiObjectReference(.gui(object.stableID)),
                                       arguments: [.string(id)], program: emptyProgram())
        guard case .object(let reference) = value, case .gui(let objectID) = reference.kind else {
            return nil
        }
        return objectID
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private func makeArchive(files: [(String, Data)]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB120Tests-\(UUID().uuidString)", isDirectory: true)
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

    private final class TestHost: WinampModernHost {
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
