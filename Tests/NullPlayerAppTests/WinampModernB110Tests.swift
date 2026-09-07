import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B110 — a skin's window frame is a second window.
///
/// Reported live 2026-09-03 on Ebonite_2_1 as *"there is no right hand pad"*. Ebonite draws each
/// framed window's border, title, close button and resizer grips in a **second** container —
/// `newDynamicContainer("sc.alphaframe")` — parked on the client window's exact rect, which is why
/// the client's own group is declared short by that margin (`w="-17" relatw="1" h="-20" relath="1"`,
/// 233x230 of a 250x250 window). Three engine gaps kept that window off screen, and each one hid the
/// next:
///
/// 1. **`isDynamic()`** was unimplemented, and dispatch fails closed per handler, so
///    `if (!comp_layout.getContainer().isDynamic()) system.onScriptLoaded();` abandoned the whole of
///    `comp_layout.onSetVisible` two statements before `frame_layout.show()`.
/// 2. **`System.onScriptLoaded()` called as a method** — a script re-running its own startup body,
///    which is how this frame is rebuilt after the hide that closed it — had no dispatchable arity,
///    so the interpreter failed closed on the *signature* and the handler died there instead.
/// 3. **`newDynamicContainer` answered every caller with the one declared container.** Ebonite
///    includes `standardframe.maki` five times, once per framed window; all five drove one container,
///    so its playlist, library and frame windows ended up sharing a single rect.
///
/// Measured after the fix (2026-09-03, live): the playlist frame at (1072,530) 250x250 exactly over
/// its client, the library's own copy at (1072,30) 640x400 over its own — two live frames at once.
final class WinampModernB110Tests: XCTestCase {

    // MARK: - `isDynamic`

    /// The skin's own answer, read off the declaration: `dynamic="1"` is Winamp's mark for a container
    /// meant to be instantiated per use.
    func testIsDynamicAnswersTheContainerDeclaration() throws {
        let (runtime, program) = try makeRuntime()

        let dynamic = try runtime.invoke(method: "isDynamic",
                                         on: reference(try object(runtime, "frame")),
                                         arguments: [], program: program)
        XCTAssertTrue(dynamic.truthy)
    }

    /// And a container the skin declared as a singleton is not dynamic. This is the branch Ebonite
    /// actually takes — it asks the *client* container, and a `false` is what makes it rebuild the
    /// frame it closed on the last hide.
    func testIsDynamicIsFalseForADeclaredSingletonContainer() throws {
        let (runtime, program) = try makeRuntime()

        let dynamic = try runtime.invoke(method: "isDynamic",
                                         on: reference(try object(runtime, "main")),
                                         arguments: [], program: program)
        XCTAssertFalse(dynamic.truthy)
    }

    /// The signature is what the interpreter needs before it can make the call at all: without one it
    /// fails closed on the *signature* and abandons the handler, which is the failure this whole item
    /// starts with.
    func testIsDynamicHasASignature() throws {
        let (runtime, _) = try makeRuntime()
        let signature = try XCTUnwrap(runtime.signature(for: "isDynamic", classGUID: nil))
        XCTAssertEqual(signature.argumentCount, 0)
    }

    // MARK: - `newDynamicContainer` instancing

    /// The first caller keeps the declared container, exactly as every caller did before B110 — a
    /// popup that asks once (Big Bento's search results) must not start getting a copy.
    func testFirstCallerIsAnsweredWithTheDeclaredContainer() throws {
        let (runtime, program) = try makeRuntime()
        let declared = try object(runtime, "frame")

        let answer = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                                        arguments: [.string("frame")], program: program)

        XCTAssertEqual(guiID(of: answer), declared.stableID)
    }

    /// A *second* program asking for the same id is the case that was broken: it gets a live copy of
    /// its own, with its own stable id and a distinct container id.
    func testASecondProgramGetsItsOwnCopy() throws {
        let (runtime, program) = try makeRuntime()
        let other = Self.emptyProgram(path: "/Skins/Synthetic/b110-second.maki")
        let declared = try object(runtime, "frame")

        _ = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                               arguments: [.string("frame")], program: program)
        let second = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                                        arguments: [.string("frame")], program: other)

        let copyID = try XCTUnwrap(guiID(of: second))
        XCTAssertNotEqual(copyID, declared.stableID)
        let copy = try XCTUnwrap(runtime.loadedSkin.runtime.graph.object(withID: copyID))
        XCTAssertEqual(copy.xmlID, "frame#2")
        XCTAssertEqual(copy.attributes[WasabiSkinRuntime.dynamicInstanceAttribute], "frame")
        XCTAssertTrue(runtime.loadedSkin.runtime.graph.roots.contains { $0 === copy },
                      "the copy is a real root, not a detached subtree")
    }

    /// The copy is a real window: it carries the declared container's children, so the frame artwork
    /// the skin put in it is there to draw.
    func testTheCopyCarriesTheDeclaredContainerSContents() throws {
        let (runtime, program) = try makeRuntime()
        let other = Self.emptyProgram(path: "/Skins/Synthetic/b110-second.maki")
        _ = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                               arguments: [.string("frame")], program: program)

        let second = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                                        arguments: [.string("frame")], program: other)
        let copy = try XCTUnwrap(runtime.loadedSkin.runtime.graph.object(withID: XCTUnwrap(guiID(of: second))))

        let layout = try XCTUnwrap(copy.children.first)
        XCTAssertEqual(layout.xmlID, "scdef")
        XCTAssertTrue(layout.children.contains { $0.xmlID == "window.top" })
    }

    /// The copy's opening layout is **realized**, or `getLayout` answers NULL for it — and the caller's
    /// very next statement is `frame_cont.getLayout("scdef")`. Measured: without this the second
    /// framed window came up with no chrome at all, because every `frame_layout.findObject(…)` after
    /// it ran on a null receiver.
    func testTheCopySLayoutAnswersGetLayout() throws {
        let (runtime, program) = try makeRuntime()
        let other = Self.emptyProgram(path: "/Skins/Synthetic/b110-second.maki")
        _ = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                               arguments: [.string("frame")], program: program)
        let second = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                                        arguments: [.string("frame")], program: other)

        let layout = try runtime.invoke(method: "getLayout", on: MakiObjectReference(.gui(XCTUnwrap(guiID(of: second)))),
                                        arguments: [.string("scdef")], program: other)
        XCTAssertNotNil(guiID(of: layout), "getLayout answered NULL for a copy nobody had realized")
    }

    /// The same program asking twice means "the one I already have", not "another window". Ebonite
    /// asks on every re-show — it closes its frame on hide — so anything else is a window per toggle.
    func testTheSameProgramAskingTwiceGetsTheSameContainer() throws {
        let (runtime, program) = try makeRuntime()
        let other = Self.emptyProgram(path: "/Skins/Synthetic/b110-second.maki")
        _ = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                               arguments: [.string("frame")], program: program)

        let first = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                                       arguments: [.string("frame")], program: other)
        let again = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                                       arguments: [.string("frame")], program: other)

        XCTAssertEqual(guiID(of: first), guiID(of: again))
        XCTAssertEqual(runtime.loadedSkin.runtime.graph.roots.filter {
            $0.xmlID?.hasPrefix("frame") == true
        }.count, 2, "one declared container and one copy, however many times it is asked for")
    }

    /// A container the skin did *not* declare `dynamic="1"` is a singleton and is never copied: a copy
    /// of it would be a window nothing can address.
    func testASingletonContainerIsNeverCopied() throws {
        let (runtime, program) = try makeRuntime()
        let other = Self.emptyProgram(path: "/Skins/Synthetic/b110-second.maki")
        let declared = try object(runtime, "still")

        _ = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                               arguments: [.string("still")], program: program)
        let second = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                                        arguments: [.string("still")], program: other)

        XCTAssertEqual(guiID(of: second), declared.stableID)
    }

    /// `getContainer` is the other half of the split and is unchanged: it always names the declared
    /// container, whoever asks.
    func testGetContainerStillAliasesTheDeclaredContainer() throws {
        let (runtime, program) = try makeRuntime()
        let other = Self.emptyProgram(path: "/Skins/Synthetic/b110-second.maki")
        let declared = try object(runtime, "frame")

        _ = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                               arguments: [.string("frame")], program: program)
        let byName = try runtime.invoke(method: "getContainer", on: MakiObjectReference(.system),
                                        arguments: [.string("frame")], program: other)

        XCTAssertEqual(guiID(of: byName), declared.stableID)
    }

    // MARK: - `onUserResize`

    /// Distinct from `onResize`, which fires on any box change: a standard frame answers `onUserResize`
    /// by resizing the window it is glued to, so firing it on a programmatic resize would have the two
    /// windows resizing each other. Four arguments, the same box `onResize` carries.
    func testOnUserResizeHasTheSameAritySignatureAsOnResize() throws {
        let (runtime, _) = try makeRuntime()
        let signature = try XCTUnwrap(runtime.signature(for: "onUserResize", classGUID: nil))
        XCTAssertEqual(signature.argumentCount, 4)
    }

    /// And it is addressed at the container and its layout, the way `onMove` is — nothing is dispatched
    /// where nothing binds it, which is what keeps the corpus's other 65 skins out of this path.
    func testOnUserResizeDispatchesNothingWhenNoScriptBindsIt() throws {
        let (runtime, _) = try makeRuntime()
        let container = try object(runtime, "main")
        let layout = try XCTUnwrap(container.children.first)

        XCTAssertEqual(runtime.dispatchWindowUserResize(container: container, layout: layout,
                                                        size: CGSize(width: 300, height: 200)), 0)
    }

    // MARK: - Fixtures

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try load(files: [
            ("skin.xml", Data("""
            <WasabiXML>
              <elements>
                <bitmap id="edge" file="edge.png"/>
              </elements>
              <container id="main">
                <layout id="normal" w="250" h="250"/>
              </container>
              <container id="frame" dynamic="1" default_visible="0" nomenu="1">
                <layout id="scdef" w="200" h="150">
                  <layer id="window.top" x="0" y="0" w="200" h="30" image="edge"/>
                </layout>
              </container>
              <container id="still" dynamic="0">
                <layout id="normal" w="120" h="90"/>
              </container>
            </WasabiXML>
            """.utf8)),
            ("edge.png", Self.solidPNG(width: 8, height: 8)),
        ])
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return (runtime, Self.emptyProgram(path: "/Skins/Synthetic/b110.maki"))
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

    private static func solidPNG(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func load(files: [(String, Data)]) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB110Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B110-\(UUID().uuidString).wal")
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
