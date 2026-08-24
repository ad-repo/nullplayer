import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 55 — BB8, `ColorMgr.getGammaSet(name).apply()`: the colour-theme picker.
///
/// Big Bento Modern ships 77 themes and a page of 77 buttons, one per theme, each of which reads its
/// own label and applies the matching gammaset. None of `ColorMgr`, `getGammaSet` or `apply` existed
/// in the runtime, so every one of those handlers aborted and the picker did nothing.
///
/// This is a **binding** job, not a rendering one: `WasabiColorThemeCatalog` already holds every
/// `<gammaset>` the skin declared and tracks the active one, and `System.setColorTheme` already
/// routes a switch through `themeSwitchRequested`. `apply()` deliberately lands on that same route
/// rather than a second one that could disagree with it.
///
/// **Bound by class GUID, not by method name.** The interpreter passes the method's *declaring*
/// class, so `getGammaSet` is gated to `ColorMgr` and `apply` to `GammaSet`. `apply` is exactly the
/// sort of short verb several classes could declare, and a globally registered name would hand its
/// arity to all of them — a wrong argument count is the one error the interpreter cannot recover
/// from, because it leaves values on the stack. (Measured across the installed corpus, `apply`
/// appears on this one class; the gate is what keeps that true for the next skin.)
final class WinampModernPhase55Tests: XCTestCase {

    // MARK: - The class gate

    /// The GUIDs **as the compiled class table holds them**, which is what the interpreter hands to
    /// `signature(for:classGUID:)`. `MakiClassGUID.canonical` folds them, and it is an *involution* —
    /// folding an already-folded constant gives the raw form back, so passing `MakiClassGUID.colorManager`
    /// here would silently match nothing. Read off Big Bento Modern's own class table.
    private static let rawColorManager = "ff35e2aed1eb8f4996afd7e0dad4541a"
    private static let rawGammaSet = "b94d020d7495d042b8c726b553f1f987"

    func testGetGammaSetIsDeclaredOnColorMgrAndApplyOnGammaSet() throws {
        let runtime = try makeRuntime()
        let getter = try XCTUnwrap(runtime.signature(for: "getGammaSet",
                                                     classGUID: Self.rawColorManager))
        XCTAssertEqual(getter.argumentCount, 1)
        XCTAssertEqual(getter.returnKind, .object)
        let apply = try XCTUnwrap(runtime.signature(for: "apply", classGUID: Self.rawGammaSet))
        XCTAssertEqual(apply.argumentCount, 0)
        XCTAssertEqual(apply.returnKind, .null)
    }

    /// The whole point of the gate: an `apply` belonging to some other class must not pick up
    /// `GammaSet`'s arity. Refusing it is fail-closed and costs that one handler; answering it with
    /// the wrong count desynchronises the interpreter for everything after the call.
    func testApplyIsNotAnsweredForAnyOtherClass() throws {
        let runtime = try makeRuntime()
        XCTAssertNil(runtime.signature(for: "apply", classGUID: nil))
        XCTAssertNil(runtime.signature(for: "apply", classGUID: Self.rawColorManager))
        XCTAssertNil(runtime.signature(for: "apply",
                                       classGUID: "0123456789abcdef0123456789abcdef"))
        XCTAssertNil(runtime.signature(for: "getGammaSet", classGUID: Self.rawGammaSet))
    }

    /// The constants are the **canonical** form, because that is what the runtime compares against
    /// after folding the class table's raw value. Getting this backwards binds nothing at all, and
    /// silently: the method simply stays unsupported.
    func testTheClassConstantsAreTheCanonicalFormOfTheCompiledGUIDs() {
        XCTAssertEqual(MakiClassGUID.canonical(Self.rawColorManager), MakiClassGUID.colorManager)
        XCTAssertEqual(MakiClassGUID.canonical(Self.rawGammaSet), MakiClassGUID.gammaSet)
        XCTAssertTrue(MakiClassGUID.runtimeBound.contains(MakiClassGUID.colorManager),
                      "the parser must leave a ColorMgr global null so the runtime can seed it")
    }

    // MARK: - The call chain

    func testApplyingAGammaSetSwitchesTheTheme() throws {
        let runtime = try makeRuntime()
        var switched: [String] = []
        runtime.themeSwitchRequested = { switched.append($0); return true }
        let set = try runtime.invoke(method: "getgammaset",
                                     on: MakiObjectReference(.colorManager),
                                     arguments: [.string("Midnight")], program: emptyProgram())
        guard case .object(let handle) = set else { return XCTFail("getGammaSet answers an object") }
        _ = try runtime.invoke(method: "apply", on: handle, arguments: [], program: emptyProgram())
        XCTAssertEqual(switched, ["Midnight"])
    }

    /// Two different names must not collapse onto one object — the picker applies a *different*
    /// theme per button, and 77 of them are alive at once.
    func testEachGammaSetCarriesItsOwnName() throws {
        let runtime = try makeRuntime()
        var switched: [String] = []
        runtime.themeSwitchRequested = { switched.append($0); return true }
        for name in ["Midnight", "Orange", "Midnight"] {
            let set = try runtime.invoke(method: "getgammaset",
                                         on: MakiObjectReference(.colorManager),
                                         arguments: [.string(name)], program: emptyProgram())
            guard case .object(let handle) = set else { return XCTFail("expected an object") }
            _ = try runtime.invoke(method: "apply", on: handle, arguments: [], program: emptyProgram())
        }
        XCTAssertEqual(switched, ["Midnight", "Orange", "Midnight"])
    }

    /// A theme the skin does not ship is answered with the object anyway and `apply()` is simply
    /// inert. Refusing at `getGammaSet` would abort the caller's whole handler over one bad name.
    func testAnUnknownThemeIsInertRatherThanFatal() throws {
        let runtime = try makeRuntime()
        runtime.themeSwitchRequested = { _ in false }
        let set = try runtime.invoke(method: "getgammaset",
                                     on: MakiObjectReference(.colorManager),
                                     arguments: [.string("No Such Theme")], program: emptyProgram())
        guard case .object(let handle) = set else { return XCTFail("getGammaSet answers an object") }
        XCTAssertNoThrow(try runtime.invoke(method: "apply", on: handle,
                                            arguments: [], program: emptyProgram()))
    }

    /// `apply` on something that is not a gamma set at all — a `Map`, a timer, a bare `new` — must
    /// not switch a theme. The dynamic-object pool is shared across all of those roles.
    func testApplyOnAnObjectThatIsNotAGammaSetDoesNothing() throws {
        let runtime = try makeRuntime()
        var switched: [String] = []
        runtime.themeSwitchRequested = { switched.append($0); return true }
        let other = try runtime.makeObject(classGUID: "0123456789abcdef0123456789abcdef",
                                           program: emptyProgram())
        _ = try runtime.invoke(method: "apply", on: other, arguments: [], program: emptyProgram())
        XCTAssertTrue(switched.isEmpty)
    }

    /// **The regression guard.** Before `ColorMgr` was bound, a global of that class was seeded with
    /// the *System* object, so every call on it went to `invokeSystem`. Winamp declares the rest of
    /// the colour-theme API on `ColorMgr` too, and this runtime answers it on `System` — so handling
    /// `getGammaSet` alone and returning null for everything else silently takes those methods away
    /// from any skin that reaches them through its `ColorMgr` global. Binding a singleton must only
    /// ever *add* to what its receiver could already do.
    ///
    /// This was caught by a corpus render sweep: one skin's images changed with no new diagnostic and
    /// no failed handler, which is exactly what losing a *working* method looks like. That skin has
    /// since been removed from the corpus, so this test is the detector now.
    func testTheColorManagerStillAnswersEverythingSystemAnswered() throws {
        let runtime = try makeRuntime()
        runtime.themeNamesRequested = { ["Midnight", "Orange"] }
        runtime.activeThemeRequested = { "Midnight" }
        var switched: [String] = []
        runtime.themeSwitchRequested = { switched.append($0); return true }
        let colorManager = MakiObjectReference(.colorManager)

        XCTAssertEqual(try runtime.invoke(method: "getcolortheme", on: colorManager,
                                          arguments: [], program: emptyProgram()).stringValue,
                       "Midnight")
        XCTAssertEqual(try runtime.invoke(method: "getnumcolorthemes", on: colorManager,
                                          arguments: [], program: emptyProgram()).integerValue, 2)
        XCTAssertEqual(try runtime.invoke(method: "enumcolorthemes", on: colorManager,
                                          arguments: [.integer(1)], program: emptyProgram()).stringValue,
                       "Orange")
        _ = try runtime.invoke(method: "setcolortheme", on: colorManager,
                               arguments: [.string("Orange")], program: emptyProgram())
        XCTAssertEqual(switched, ["Orange"])
    }

    /// A method that is on neither `ColorMgr` nor `System` still fails the way an unknown method on
    /// `System` fails, rather than being quietly swallowed — the fall-through must not turn the
    /// receiver into a sink that accepts anything.
    func testAnUnknownMethodOnTheColorManagerIsStillUnsupported() throws {
        let runtime = try makeRuntime()
        XCTAssertThrowsError(try runtime.invoke(method: "nosuchmethod",
                                                on: MakiObjectReference(.colorManager),
                                                arguments: [], program: emptyProgram()))
    }

    // MARK: - Helpers

    private func makeRuntime() throws -> WinampModernScriptRuntime {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <layer id="plain" x="0" y="0" w="10" h="10"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase55Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase55-\(UUID().uuidString).wal")
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
