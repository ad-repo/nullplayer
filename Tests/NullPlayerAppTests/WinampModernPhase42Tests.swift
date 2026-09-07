import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 42 (backlog B8) — the playlist-editor script API, `PlEdit`.
///
/// `std.mi` declares `PlEdit` as a host-owned global exactly as it declares `System`, and skins call
/// a dozen methods on it: the queue's length and current entry, an entry's title/length/filename/
/// metadata, and the edits behind a playlist context menu (play, remove, move, clear, scroll-to).
/// Six of the seventeen installed skins also ask `System.getPlaylistIndex()`, which was the most
/// demanded unimplemented method in the corpus.
///
/// Two things were measured rather than assumed, and both are asserted here:
///
/// 1. **The arities**, counted off the corpus's own call sites (`WINAMP_MODERN_RENDER_DISASM`). The
///    one that pays for the measurement is `moveTo`, which reads like a one-argument "scroll to" and
///    is `moveTo(from, to)` — Defix's *Move selected to top* passes a literal 0 and then a counter.
/// 2. **Which variable is `System`.** The compiler marks every host-owned global with the variable
///    record's `system` flag, and the parser read that as "this *is* the System object" — so every
///    `PlEdit.getCurrentIndex()` in the corpus arrived as a call on System and failed there as an
///    unknown System method. That is why the gap surfaced on interaction rather than at load.
final class WinampModernPhase42Tests: XCTestCase {

    // MARK: - 1. Which global is System

    /// The regression that hid the whole API: two system-flagged object globals, and the one declared
    /// with `PlEdit`'s class must not become System. It stays null for the runtime to bind by class.
    /// The carve-out is deliberately narrow — a system-flagged global of any *other* class keeps the
    /// System object it has always been given, so nothing that worked before turns into a null
    /// receiver on the strength of a GUID we have not measured.
    func testAPlEditGlobalIsNotSeededWithTheSystemObject() throws {
        let program = try MakiBytecodeParser().parse(Self.twoHostSingletons(),
                                                     source: WalSourceLocation(path: "std.maki"))

        XCTAssertEqual(program.variables.count, 2)
        guard case .object(let system) = program.variables[0].value else {
            return XCTFail("variable 0 should be the System object")
        }
        XCTAssertEqual(system.kind, .system)
        // Not System, and not silently something else either: null is what the runtime then binds.
        if case .object = program.variables[1].value {
            XCTFail("PlEdit must not be seeded with an object by the parser")
        }
        XCTAssertTrue(program.variables[1].isSystem, "the flag is still read; it just means less")
    }

    /// …and the runtime binds it, so a call on it reaches the playlist editor rather than the null
    /// receiver (which answers `.null` and would make a dead API look implemented).
    func testTheRuntimeBindsPlEditByItsClass() throws {
        let (runtime, _) = try makeRuntime(programData: Self.twoHostSingletons())

        let plEdit = try XCTUnwrap(runtime.programs.first?.variables[1].value)
        guard case .object(let reference) = plEdit else {
            return XCTFail("PlEdit should be bound to the playlist editor")
        }
        XCTAssertEqual(reference.kind, .playlistEditor)
    }

    // MARK: - 2. The arities, and the class they are gated on

    /// Counted from the bytecode, not ported from a header. A wrong arity desynchronises the
    /// interpreter's stack, which is the one failure the VM cannot recover from.
    func testTheMeasuredAritiesAreRegistered() throws {
        let (runtime, _) = try makeRuntime()
        let guid = Self.plEditGUID

        XCTAssertEqual(runtime.signature(for: "getCurrentIndex", classGUID: guid)?.argumentCount, 0)
        XCTAssertEqual(runtime.signature(for: "getNumTracks", classGUID: guid)?.argumentCount, 0)
        XCTAssertEqual(runtime.signature(for: "showCurrentlyPlayingTrack", classGUID: guid)?.argumentCount, 0)
        XCTAssertEqual(runtime.signature(for: "clear", classGUID: guid)?.argumentCount, 0)
        XCTAssertEqual(runtime.signature(for: "getTitle", classGUID: guid)?.argumentCount, 1)
        XCTAssertEqual(runtime.signature(for: "getLength", classGUID: guid)?.argumentCount, 1)
        XCTAssertEqual(runtime.signature(for: "getFileName", classGUID: guid)?.argumentCount, 1)
        XCTAssertEqual(runtime.signature(for: "playTrack", classGUID: guid)?.argumentCount, 1)
        XCTAssertEqual(runtime.signature(for: "removeTrack", classGUID: guid)?.argumentCount, 1)
        XCTAssertEqual(runtime.signature(for: "showTrack", classGUID: guid)?.argumentCount, 1)
        XCTAssertEqual(runtime.signature(for: "getMetaData", classGUID: guid)?.argumentCount, 2)
        XCTAssertEqual(runtime.signature(for: "moveTo", classGUID: guid)?.argumentCount, 2)
        // A string, not a number — ClassicPro tests it against "" before bracketing it.
        XCTAssertEqual(runtime.signature(for: "getLength", classGUID: guid)?.returnKind, .string)
    }

    /// Half these names belong to other classes, and one of them was already implemented for one:
    /// `getLength` is an `animatedlayer`'s **frame count** — no arguments, an integer — which
    /// ClassicPro's `beat.m` reads 28 times. Registering `PlEdit`'s by name would have re-declared
    /// that one with the wrong arity and desynchronised the interpreter's stack in a skin that has
    /// nothing to do with playlists. The rest stay unclaimed, so their demand is still recorded.
    func testTheseNamesKeepTheirOtherClasses() throws {
        let (runtime, _) = try makeRuntime()

        let elsewhere = runtime.signature(for: "getLength", classGUID: Self.someOtherGUID)
        XCTAssertEqual(elsewhere?.argumentCount, 0)
        XCTAssertEqual(elsewhere?.returnKind, .integer)
        XCTAssertNil(runtime.signature(for: "getTitle", classGUID: Self.someOtherGUID))
        XCTAssertNil(runtime.signature(for: "clear", classGUID: Self.someOtherGUID))
        XCTAssertNil(runtime.signature(for: "moveTo", classGUID: Self.someOtherGUID))
        XCTAssertNil(runtime.signature(for: "getNumTracks", classGUID: Self.someOtherGUID))
    }

    // MARK: - 3. The reads

    func testTheQueueIsReadThroughTheComponentSeam() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(3, current: 1)

        XCTAssertEqual(call(runtime, "getnumtracks").integerValue, 3)
        XCTAssertEqual(call(runtime, "getcurrentindex").integerValue, 1)
        XCTAssertEqual(call(runtime, "gettitle", .integer(2)).stringValue, "Track 3")
        XCTAssertEqual(call(runtime, "getfilename", .integer(0)).stringValue, "/queue/track1.mp3")
    }

    /// `getPlaylistIndex` is a **System** method, not `PlEdit`'s, and six skins ask for it — the most
    /// demanded unimplemented method in the corpus. Winamp's own notifier shows it as
    /// `getPlaylistIndex() + 1 + " of " + getPlaylistLength()`, which pins the base and the pairing.
    func testSystemAnswersThePlaylistIndexAndLengthFromTheSameQueue() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(5, current: 3)

        let system = MakiObjectReference(.system)
        let program = try XCTUnwrap(runtime.programs.first)
        let index = try runtime.invoke(method: "getplaylistindex", on: system, arguments: [], program: program)
        let length = try runtime.invoke(method: "getplaylistlength", on: system, arguments: [], program: program)
        XCTAssertEqual(index.integerValue, 3)
        XCTAssertEqual(length.integerValue, 5)
    }

    /// An out-of-range index answers empty rather than failing: a skin polls this from a timer while
    /// the queue is edited underneath it, and an abort would take the rest of the handler with it.
    func testAnOutOfRangeIndexIsEmptyRatherThanAFailure() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(2, current: 0)

        XCTAssertEqual(call(runtime, "gettitle", .integer(9)).stringValue, "")
        XCTAssertEqual(call(runtime, "getmetadata", .integer(-1), .string("album")).stringValue, "")
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty)
    }

    func testGetLengthIsATimeStringAndEmptyWhenUnknown() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = [
            WinampModernPlaylistRow(title: "a", secondary: "", duration: 245, isCurrent: true),
            WinampModernPlaylistRow(title: "b", secondary: "", duration: 0, isCurrent: false),
        ]

        XCTAssertEqual(call(runtime, "getlength", .integer(0)).stringValue, "4:05")
        // The case ClassicPro's `!= ""` test exists for.
        XCTAssertEqual(call(runtime, "getlength", .integer(1)).stringValue, "")
    }

    /// Defix asks for `"album"` on every entry it draws art for, and the artist and album must not
    /// arrive joined — which is what the row's display string does with them.
    func testGetMetaDataAnswersTheIndividualFields() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(2, current: 0)

        XCTAssertEqual(call(runtime, "getmetadata", .integer(1), .string("album")).stringValue, "Album 2")
        XCTAssertEqual(call(runtime, "getmetadata", .integer(1), .string("Artist")).stringValue, "Artist 2")
        XCTAssertEqual(call(runtime, "getmetadata", .integer(1), .string("title")).stringValue, "Track 2")
        XCTAssertEqual(call(runtime, "getmetadata", .integer(1), .string("filename")).stringValue,
                       "/queue/track2.mp3")
        XCTAssertEqual(call(runtime, "getmetadata", .integer(1), .string("nosuchfield")).stringValue, "")
    }

    // MARK: - 4. The edits

    func testPlayAndRemoveReachTheHost() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(4, current: 0)

        _ = call(runtime, "playtrack", .integer(2))
        XCTAssertEqual(host.played, [2])

        _ = call(runtime, "removetrack", .integer(1))
        XCTAssertEqual(host.removed, [1])
    }

    /// The argument order the disassembly settles: the row being moved first, its destination second.
    /// Reversed, *Move selected to top* would move whatever is at the top to the selection.
    func testMoveToTakesTheSourceRowFirstAndTheDestinationSecond() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(4, current: 0)

        _ = call(runtime, "moveto", .integer(3), .integer(0))

        XCTAssertEqual(host.moved.count, 1)
        XCTAssertEqual(host.moved.first?.from, 3)
        XCTAssertEqual(host.moved.first?.to, 0)
    }

    func testClearEmptiesTheQueue() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(4, current: 0)

        _ = call(runtime, "clear")

        XCTAssertTrue(host.rows.isEmpty)
        XCTAssertEqual(call(runtime, "getcurrentindex").integerValue, -1)
    }

    // MARK: - 5. Scroll-to

    func testShowTrackAsksTheWindowToRevealTheRow() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(20, current: 7)
        var revealed: [Int] = []
        runtime.playlistRevealRowRequested = { revealed.append($0) }

        _ = call(runtime, "showtrack", .integer(12))
        _ = call(runtime, "showcurrentlyplayingtrack")

        XCTAssertEqual(revealed, [12, 7])
    }

    /// Nothing playing is nothing to scroll to — asking for row −1 would scroll the list to its top
    /// on every tick of a skin that calls this from a timer.
    func testShowCurrentlyPlayingTrackDoesNothingWithNoCurrentEntry() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = []
        var revealed: [Int] = []
        runtime.playlistRevealRowRequested = { revealed.append($0) }

        _ = call(runtime, "showcurrentlyplayingtrack")

        XCTAssertTrue(revealed.isEmpty)
    }

    /// `showCurrentlyPlayingEntry` is the same request made of the playlist *widget* — Itemskin and
    /// micro reach it through `findObject`, so it is a GUI method with a receiver, not a System one.
    func testShowCurrentlyPlayingEntryIsAnsweredOnTheWidget() throws {
        let (runtime, host) = try makeRuntime()
        host.rows = Self.rows(6, current: 4)
        var revealed: [Int] = []
        runtime.playlistRevealRowRequested = { revealed.append($0) }
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.allObjectsUnordered
            .first { $0.xmlID == "pl" })
        let program = try XCTUnwrap(runtime.programs.first)

        _ = try runtime.invoke(method: "showcurrentlyplayingentry",
                               on: MakiObjectReference(.gui(object.stableID)),
                               arguments: [], program: program)

        XCTAssertEqual(revealed, [4])
    }

    /// The scroll itself: the least movement that brings the row on screen, and none at all for a row
    /// already visible — a skin that calls this from a timer must not fight the user's own scrolling.
    func testRevealScrollsTheLeastItCanAndLeavesAVisibleRowAlone() throws {
        let renderer = try makeRenderer()
        let frame = CGRect(x: 0, y: 0, width: 100, height: renderer.playlistRowHeight() * 5)

        renderer.revealPlaylistRow(9, rowCount: 20, in: frame)
        XCTAssertEqual(renderer.playlistScrollOffsetForTesting, 5, "9 is the last of rows 5…9")

        renderer.revealPlaylistRow(7, rowCount: 20, in: frame)
        XCTAssertEqual(renderer.playlistScrollOffsetForTesting, 5, "already on screen")

        renderer.revealPlaylistRow(2, rowCount: 20, in: frame)
        XCTAssertEqual(renderer.playlistScrollOffsetForTesting, 2, "scrolled back to the row itself")

        renderer.revealPlaylistRow(99, rowCount: 20, in: frame)
        XCTAssertEqual(renderer.playlistScrollOffsetForTesting, 2, "an index off the end moves nothing")
    }

    // MARK: - 6. A repeated handler runs once; two different handlers both run

    /// A live defect found while verifying this phase, and not a playlist one: Defix's
    /// `MAIN_LAYOUT_1` declares `ConfBT2.onLeftClick()` **twice**, the same 125 instructions reading
    /// the same config string through two sets of temporaries. Running both fired that round
    /// button's whole assigned action twice per click, and because the action is a *toggle* the two
    /// cancelled — the playlist window flashed open and shut on every press, and an open one refused
    /// to close. A repeat of a handler's body is a compile artifact, so it is dropped.
    ///
    /// The render harness could not see this: it owns no windows, so the doubled toggle measured as
    /// one clean action. It was found by driving the click in the running app.
    func testADuplicateHandlerDeclarationRunsOnce() throws {
        let program = try MakiBytecodeParser().parse(Self.duplicateHandlerScript(),
                                                     source: WalSourceLocation(path: "dup.maki"))

        XCTAssertEqual(program.bindings.count, 2, "both declarations survive the parse")
        XCTAssertEqual(program.dispatchBindings.count, 1, "only one is dispatched")
        XCTAssertEqual(program.dispatchBindings.first?.instructionIndex,
                       program.bindings.first?.instructionIndex,
                       "the first of the repeats is the one that stands")
    }

    /// The other half of that rule, and B38.4: two handlers for the same (object, event) whose
    /// **bodies differ** are two real handlers and both run. Big Bento Modern's `mcvcore` declares
    /// `System.onScriptLoaded()` twice — once to find every object of the Multi Content View and
    /// pick which of the album-art and visualization panes to show, once to start a timer. Dropping
    /// the first left both panes in the scene, the visualization box drawn black over the cover.
    func testTwoDifferentBodiesForOneEventBothRun() throws {
        let program = try MakiBytecodeParser().parse(Self.divergentHandlerScript(),
                                                     source: WalSourceLocation(path: "two-bodies.maki"))

        XCTAssertEqual(program.bindings.count, 2)
        XCTAssertEqual(program.dispatchBindings.count, 2, "different bodies are different handlers")
    }

    /// …while two handlers for *different* events, or for different objects, both stand.
    func testDistinctHandlersAreAllKept() throws {
        let program = try MakiBytecodeParser().parse(Self.twoDistinctHandlersScript(),
                                                     source: WalSourceLocation(path: "two.maki"))

        XCTAssertEqual(program.dispatchBindings.count, 2)
    }

    // MARK: - Fixtures

    private static let plEditGUID = "bcee5b342902214990be6cb6a49a79d9"
    private static let systemGUID = "640ff5d6fa93b74993f1ba66efae3e98"
    /// Any class that is not `PlEdit` — the point is only that it is a different one.
    private static let someOtherGUID = "c1fe2961b7da514d916501ca0c1b70db"

    private static func rows(_ count: Int, current: Int) -> [WinampModernPlaylistRow] {
        (0..<count).map {
            WinampModernPlaylistRow(title: "Track \($0 + 1)", secondary: "", duration: 120,
                                    isCurrent: $0 == current, artist: "Artist \($0 + 1)",
                                    album: "Album \($0 + 1)", filePath: "/queue/track\($0 + 1).mp3")
        }
    }

    @discardableResult
    private func call(_ runtime: WinampModernScriptRuntime, _ method: String,
                      _ arguments: MakiValue...) -> MakiValue {
        guard let program = runtime.programs.first else {
            XCTFail("no program to attribute the call to")
            return .null
        }
        return (try? runtime.invoke(method: method, on: MakiObjectReference(.playlistEditor),
                                    arguments: arguments, program: program)) ?? .null
    }

    private func makeRuntime(programData: Data? = nil)
    throws -> (WinampModernScriptRuntime, PlaylistHost) {
        let loaded = try makeSkin(scriptData: programData ?? Self.twoHostSingletons())
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let host = PlaylistHost()
        runtime.componentHost = host
        return (runtime, host)
    }

    private func makeRenderer() throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(scriptData: Self.twoHostSingletons())
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(scriptData: Data) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase42Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase42-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="120">
              <text id="pl" x="0" y="0" w="200" h="20"/>
              <script id="s" file="s.maki"/>
            </layout>
          </container>
        </WasabiXML>
        """
        try Self.add(Data(xml.utf8), as: "skin.xml", to: archive)
        try Self.add(scriptData, as: "s.maki", to: archive)
        let loaded = try WinampModernSkinLoader().load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private static func add(_ payload: Data, as name: String, to archive: Archive) throws {
        try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(start + size, payload.count))
        }
    }

    /// A modern-layout MAKI program declaring the two host-owned globals `std.mi` declares — `System`
    /// and `PlEdit` — with the `system` flag set on **both**, which is how the real compiler writes
    /// them and what the parser used to read as "these are both System".
    private static func twoHostSingletons() -> Data {
        var data = Data([0x46, 0x47])
        func u8(_ value: UInt8) { data.append(value) }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func guid(_ hex: String) {
            for offset in stride(from: 0, to: hex.count, by: 2) {
                let start = hex.index(hex.startIndex, offsetBy: offset)
                u8(UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16) ?? 0)
            }
        }
        u16(0x0403)
        u32(23)
        u32(2)
        guid(systemGUID)
        guid(plEditGUID)
        u32(0) // no methods: the arities are asserted through `signature(for:)` directly
        u32(2) // two variables
        for classIndex in 0..<2 {
            u8(UInt8(classIndex)) // typeOffset — the class it is declared with
            u8(1)                 // object
            u16(0)                // not a subclass
            u16(0); u16(0); u16(0); u16(0)
            u8(1)                 // global
            u8(1)                 // system: the host owns it — *both* of them
        }
        u32(0); u32(0); u32(0)
        return data
    }

    /// One object variable, one method name, **two** bindings to it — the shape Defix ships.
    private static func duplicateHandlerScript() -> Data {
        makeScript(methodNames: ["onleftclick"], bindings: [(0, 0, 0), (0, 0, 1)])
    }

    /// Two bindings that are genuinely distinct: same object, two different events.
    private static func twoDistinctHandlersScript() -> Data {
        makeScript(methodNames: ["onleftclick", "onrightclick"], bindings: [(0, 0, 0), (0, 1, 1)])
    }

    /// The same object and the same event twice, over a body long enough for the two handlers to
    /// differ: the first is one `return`, the second is two — the shape Big Bento's `mcvcore` ships.
    private static func divergentHandlerScript() -> Data {
        makeScript(methodNames: ["onscriptloaded"], bindings: [(0, 0, 0), (0, 0, 1)],
                   instructionCount: 3)
    }

    /// A minimal modern-layout program: one class, `methodNames` methods on it, one object variable,
    /// and the given `(variable, method, byteOffset)` bindings over a body of two bare `return`s.
    private static func makeScript(methodNames: [String],
                                   bindings: [(UInt32, UInt32, UInt32)],
                                   instructionCount: Int = 2) -> Data {
        var data = Data([0x46, 0x47])
        func u8(_ value: UInt8) { data.append(value) }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        u16(0x0403)
        u32(23)
        u32(1)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        u32(UInt32(methodNames.count))
        for name in methodNames {
            u16(0); u16(0)
            let bytes = Array(name.utf8)
            u16(UInt16(bytes.count)); data.append(contentsOf: bytes)
        }
        u32(1)          // one object variable, the object the handlers are declared on
        u8(0); u8(1); u16(0); u16(0); u16(0); u16(0); u16(0); u8(1); u8(0)
        u32(0)          // no constants
        u32(UInt32(bindings.count))
        for (variable, method, offset) in bindings { u32(variable); u32(method); u32(offset) }
        // Bare `return`s (opcode 33), so each binding lands on a real instruction boundary.
        u32(UInt32(instructionCount))
        for _ in 0..<instructionCount { u8(33) }
        return data
    }

    private final class PlaylistHost: WinampModernComponentHost {
        var rows: [WinampModernPlaylistRow] = []
        var played: [Int] = []
        var removed: [Int] = []
        var moved: [(from: Int, to: Int)] = []

        func playlistSnapshot() -> WinampModernPlaylistSnapshot {
            WinampModernPlaylistSnapshot(rows: rows,
                                         currentIndex: rows.firstIndex(where: \.isCurrent) ?? -1,
                                         selectedIndex: -1)
        }

        func playlistSelect(row: Int) {}
        func playlistPlay(row: Int) { played.append(row) }
        func playlistRemove(row: Int) { removed.append(row) }
        func playlistMove(row: Int, to destination: Int) { moved.append((row, destination)) }
        func playlistClear() { rows = [] }
        func equalizerSnapshot() -> WinampModernEQSnapshot { .flat }
        func equalizerSetBandGainDB(_ band: Int, gainDB: Float) {}
        func equalizerSetPreampDB(_ gainDB: Float) {}
        func equalizerSetEnabled(_ enabled: Bool) {}
        func equalizerSetAuto(_ enabled: Bool) {}
        func equalizerApplyPreset(named name: String) {}
        func toggleClassicWindow(for kind: WinampModernComponentKind) {}
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 2
        var spectrumLevels: [Float] = []
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
