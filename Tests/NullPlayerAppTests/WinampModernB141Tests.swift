import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B141 — a script's `setText` raised no `onTextChanged`, so ClassicPro's file-info rows drew on top
/// of their labels.
///
/// Winamp raises the event from *inside* `setText`, and a skin may have no other signal that the
/// string moved. The measured case is the drawer's File Info page: every row is a
/// `<Text id="label">` beside a `<Text id="text">`, both declared at x=0 and stacked on purpose, and
/// `infoline.maki` is what pulls them apart — it measures the label and shifts the value clear of it
/// from `label.onTextChanged` alone, where the label's own string arrives as an XUI param, i.e.
/// through this method. With no dispatch the handler never ran and every value drew over its label.
///
/// Two guards go with it, and both are load-bearing:
///
/// - **only on an actual change**, as Wasabi does, so a script that rewrites the same string does not
///   set the row's layout going again;
/// - **never re-entrantly** — a handler is free to answer with another `setText` on the same object,
///   which is an unbounded recursion rather than a second event.
///
/// It also records the new value in `lastDispatchedText`, because the bound-text poll keys off the
/// same content and would otherwise report the script's own write as a host-side change and fire a
/// second time on the next tick.
///
/// Measured with `WINAMP_MODERN_RENDER_SCRIPTS=1`: 26 of cPro-Bento's programs run `ontextchanged`
/// that never ran before, no other event's set changes, and every PNG of the default layouts is
/// byte-identical — the page these rows live on is not shown at load.
final class WinampModernB141Tests: XCTestCase {

    /// ClassicPro's row, reduced to the two objects that overlap.
    private static let infoRow = """
    <WasabiXML>
      <container id="Main">
        <layout id="normal" w="200" h="100">
          <group id="row" x="0" y="0" w="200" h="20">
            <text id="label" x="0" y="0" w="60" h="20" text="Title"/>
            <text id="value" x="0" y="0" w="140" h="20"/>
          </group>
        </layout>
      </container>
    </WasabiXML>
    """

    // MARK: - The defect

    /// The whole report in one assertion: writing an object's text tells that object's script.
    func testSetTextRaisesOnTextChanged() throws {
        let runtime = try makeRuntime()
        let label = try object(named: "label", in: runtime)
        runtime.recordsDispatchedEventsForTesting = true

        try setText("A Very Long Song Title", on: label, in: runtime)

        XCTAssertEqual(runtime.dispatchedEventsForTesting.filter { $0.event == "ontextchanged" }
                              .map(\.object),
                       ["label"])
    }

    // MARK: - The guards

    /// Wasabi raises it on a *change*. Rewriting the same string is not one.
    func testRewritingTheSameTextRaisesNothing() throws {
        let runtime = try makeRuntime()
        let label = try object(named: "label", in: runtime)
        try setText("Title", on: label, in: runtime)
        runtime.recordsDispatchedEventsForTesting = true

        try setText("Title", on: label, in: runtime)

        XCTAssertTrue(runtime.dispatchedEventsForTesting.isEmpty,
                      "the string did not move, so nothing is announced")
    }

    /// A handler answering with another `setText` on the same object is ordinary, and must not
    /// recurse. The object is held for the duration and released after.
    func testAWriteFromInsideTheHandlerDoesNotRecurse() throws {
        let runtime = try makeRuntime()
        let label = try object(named: "label", in: runtime)
        runtime.textChangeInFlight.insert(label.stableID)
        runtime.recordsDispatchedEventsForTesting = true

        try setText("Album", on: label, in: runtime)

        XCTAssertTrue(runtime.dispatchedEventsForTesting.isEmpty,
                      "the object's handler is already running; this is its own write coming back")
        XCTAssertEqual(WasabiTextMetrics.content(of: label, host: runtime.host), "Album",
                       "the write itself still lands — only the second event is suppressed")
    }

    /// Once the handler returns, the object is announceable again.
    func testTheGuardIsReleasedAfterTheDispatch() throws {
        let runtime = try makeRuntime()
        let label = try object(named: "label", in: runtime)

        try setText("Title one", on: label, in: runtime)
        XCTAssertTrue(runtime.textChangeInFlight.isEmpty)

        runtime.recordsDispatchedEventsForTesting = true
        try setText("Title two", on: label, in: runtime)
        XCTAssertEqual(runtime.dispatchedEventsForTesting.filter { $0.event == "ontextchanged" }.count, 1)
    }

    /// The poll and the dispatch share one record of what the object last said, so the next tick does
    /// not read the script's own write as a host-side change and fire again.
    func testThePollDoesNotFireASecondTimeForTheScriptsOwnWrite() throws {
        let runtime = try makeRuntime()
        let label = try object(named: "label", in: runtime)

        try setText("Rating", on: label, in: runtime)

        XCTAssertEqual(runtime.lastDispatchedText[label.stableID], "Rating")
    }

    // MARK: -

    private func setText(_ text: String, on object: WasabiObject,
                         in runtime: WinampModernScriptRuntime) throws {
        _ = try runtime.invoke(method: "settext",
                               on: MakiObjectReference(.gui(object.stableID)),
                               arguments: [.string(text)], program: emptyProgram())
    }

    private func makeRuntime() throws -> WinampModernScriptRuntime {
        let loaded = try WinampModernSkinLoader(engineStore: nil)
            .load(from: try makeArchive(files: [("skin.xml", Data(Self.infoRow.utf8))]))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func object(named xmlID: String, in runtime: WinampModernScriptRuntime) throws
        -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: xmlID).first)
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private func makeArchive(files: [(String, Data)]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB141Tests-\(UUID().uuidString)", isDirectory: true)
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
