import XCTest
import AppKit
import ZIPFoundation
@testable import NullPlayer

/// Phase 43 (backlog B9) — `System.onKeyDown`.
///
/// Winamp hands the script **one string**, not a virtual keycode: `"alt+g"`, `"ctrl+w"`, `"esc"`.
/// Measured, not assumed (`WINAMP_MODERN_RENDER_DISASM=@<xml>` on the three skins that bind one):
/// every handler opens with a single string store and compares it against a **lowercase** literal —
/// multipass `System.strLower(strKey) == "alt+g"` and winampmodern566's `strKey == "alt+a"` /
/// `strLeft(strKey, 4) == "ctrl"` / Defix's `strKey == "esc"`. Two of the three compare without
/// normalising first, so an `"Alt+G"` would miss every one of them.
///
/// The corpus count in the backlog was five skins by grep; three of them bind the handler. Rika and
/// T800 ship Winamp's stock `playlisteditor.maki`, whose `onKeyDown` is the **edit control's**
/// (`editcontrol.onKeyDown(Int vkcode)` — a GUI receiver and an integer argument, a different event
/// entirely), and neither skin loads that program at all: their playlist windows are ours, not
/// theirs, so nothing binds it. Measured with `WINAMP_MODERN_RENDER_KEY` — both answer `handlers=0`.
final class WinampModernPhase43Tests: XCTestCase {

    // MARK: - The accelerator string

    func testAPlainLetterIsItsOwnName() {
        XCTAssertEqual(accelerator(keyCode: 5, characters: "g"), "g")
    }

    /// The three the corpus actually uses, in the order Winamp writes them. `ctrl` first is not
    /// cosmetic: winampmodern566's playlist tests `strLeft(strKey, 4) == "ctrl"`, so any other order
    /// silently disables its shade toggle.
    func testModifiersAreNamedInWinampsOrder() {
        XCTAssertEqual(accelerator(keyCode: 5, characters: "g", modifiers: .option), "alt+g")
        XCTAssertEqual(accelerator(keyCode: 13, characters: "w", modifiers: .control), "ctrl+w")
        XCTAssertEqual(accelerator(keyCode: 0, characters: "a", modifiers: [.control, .option, .shift]),
                       "ctrl+alt+shift+a")
    }

    /// The literal a skin compares against is lowercase, and `charactersIgnoringModifiers` reports an
    /// uppercase letter when Shift is down. The case goes into the `shift+` prefix, not the key.
    func testShiftLowercasesTheKeyAndAnnouncesItself() {
        XCTAssertEqual(accelerator(keyCode: 5, characters: "G", modifiers: .shift), "shift+g")
    }

    func testTheKeysWinampNamesRatherThanSpells() {
        XCTAssertEqual(accelerator(keyCode: 53, characters: "\u{1b}"), "esc")
        XCTAssertEqual(accelerator(keyCode: 99, characters: nil), "f3")
        XCTAssertEqual(accelerator(keyCode: 126, characters: nil), "up")
        XCTAssertEqual(accelerator(keyCode: 49, characters: " "), "space")
        XCTAssertEqual(accelerator(keyCode: 36, characters: "\r"), "enter")
    }

    /// Command is deliberately not folded onto `ctrl`. ⌘W closes a window and ⌘A selects all on this
    /// platform; letting a skin's `ctrl+w` shadow the app's own menu equivalents is a capability no
    /// skin asked for, and the responder chain has to keep seeing those events.
    func testACommandKeyEventIsNotAnAccelerator() {
        XCTAssertNil(accelerator(keyCode: 13, characters: "w", modifiers: .command))
        XCTAssertNil(accelerator(keyCode: 0, characters: "a", modifiers: [.command, .shift]))
    }

    /// A dead key, a function key we do not name, or anything that is not one printable ASCII
    /// character has no Winamp name — and inventing one would put a string in front of a skin that no
    /// handler can ever match while swallowing the key from the responder chain.
    func testAKeyWithNoWinampNameProducesNoAccelerator() {
        XCTAssertNil(accelerator(keyCode: 200, characters: nil))
        XCTAssertNil(accelerator(keyCode: 200, characters: "é"))
        XCTAssertNil(accelerator(keyCode: 200, characters: "ab"))
    }

    // MARK: - The dispatch

    /// The arity is one, and it is declared: a handler dispatched with the wrong argument count
    /// desynchronises the interpreter's value stack for the rest of the program.
    func testTheEventIsDeclaredWithTheArityTheSkinsUse() throws {
        let runtime = try makeRuntime(matching: "alt+g")
        XCTAssertEqual(runtime.signature(for: "onKeyDown", classGUID: nil)?.argumentCount, 1)
    }

    func testTheAcceleratorReachesTheHandlerAsAString() throws {
        let runtime = try makeRuntime(matching: "alt+g")
        runtime.recordsDispatchedEventsForTesting = true

        runtime.dispatchKeyDown("alt+g")

        let dispatched = runtime.dispatchedSystemEventsForTesting.filter { $0.event == "onkeydown" }
        XCTAssertEqual(dispatched.count, 1)
        XCTAssertEqual(dispatched.first?.arguments.first?.stringValue, "alt+g")
    }

    /// `complete;` is MAKI's "I dealt with this", and it is the only thing that can tell the window
    /// whether to swallow the key. A handler that ran and matched none of its branches never reaches
    /// one — Defix's `esc` handler is exactly that shape — and the key must fall through.
    func testAHandlerThatCompletesConsumesTheKeyAndOneThatDoesNotDoesNot() throws {
        let runtime = try makeRuntime(matching: "alt+g")

        XCTAssertTrue(runtime.dispatchKeyDown("alt+g"), "the branch that matched ran `complete;`")
        XCTAssertFalse(runtime.dispatchKeyDown("esc"), "no branch matched, so nothing was consumed")
    }

    /// A skin with no key handler at all must leave every key to the app, so the answer for the other
    /// fourteen skins in the corpus is "not consumed" without anything else having to know.
    func testASkinWithNoHandlerConsumesNothing() throws {
        let runtime = try makeRuntime(matching: nil)
        XCTAssertFalse(runtime.dispatchKeyDown("alt+g"))
    }

    // MARK: - `isActive()`

    /// The gate a skin puts in front of a key handler. A System event reaches every program in the
    /// skin whatever window is focused — Winamp does it that way too — so winampmodern566's playlist
    /// asks `isActive()` before acting on `ctrl+w`, and without an answer from the host its shade
    /// toggle would fire from the main window.
    func testIsActiveAnswersForTheContainerTheObjectBelongsTo() throws {
        let runtime = try makeRuntime(matching: nil)
        let layer = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "probe").first)
        var focused = "main"
        runtime.containerActiveQuery = { $0.caseInsensitiveCompare(focused) == .orderedSame }

        XCTAssertTrue(try invoke("isActive", on: layer, in: runtime).truthy)
        focused = "other"
        XCTAssertFalse(try invoke("isActive", on: layer, in: runtime).truthy)
    }

    /// With no host installed there is no focus to report, and a probe driving a handler that gates on
    /// this must still get through it. In the app the host always answers.
    func testIsActiveReadsActiveWithNoHostToAsk() throws {
        let runtime = try makeRuntime(matching: nil)
        let layer = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "probe").first)
        XCTAssertTrue(try invoke("isActive", on: layer, in: runtime).truthy)
    }

    // MARK: - Helpers

    private func accelerator(keyCode: UInt16, characters: String?,
                             modifiers: NSEvent.ModifierFlags = []) -> String? {
        WinampModernKeyAccelerator.accelerator(keyCode: keyCode,
                                               charactersIgnoringModifiers: characters,
                                               modifiers: modifiers)
    }

    private func invoke(_ method: String, on object: WasabiObject,
                        in runtime: WinampModernScriptRuntime) throws -> MakiValue {
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/S/t.maki"),
                                  ownerID: nil, parameter: nil)
        return try runtime.invoke(method: method, on: MakiObjectReference(.gui(object.stableID)),
                                  arguments: [], program: program)
    }

    /// A runtime over a one-layer skin, optionally carrying a compiled `System.onKeyDown` handler
    /// shaped like the corpus's: store the argument, compare it against a literal, `complete;` on a
    /// match and fall out otherwise.
    private func makeRuntime(matching literal: String?) throws -> WinampModernScriptRuntime {
        var files: [String: Data] = [:]
        var scriptTag = ""
        if let literal {
            files["scripts/keys.maki"] = makeKeyDownScript(matching: literal)
            scriptTag = #"<script id="keys" file="scripts/keys.maki"/>"#
        }
        files["skin.xml"] = Data("""
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="120" h="60">
              <layer id="probe" x="0" y="0" w="10" h="10"/>
            </layout>
          </container>
          \(scriptTag)
        </WasabiXML>
        """.utf8)
        let loaded = try makeSkin(files: files)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        try runtime.start()
        return runtime
    }

    /// ```
    /// System.onKeyDown(String key) {
    ///   if (key == "<literal>") complete;
    /// }
    /// ```
    /// Variables: 0 the System object, 1 the string argument, 2 the literal, 3 the return value.
    private func makeKeyDownScript(matching literal: String) -> Data {
        var code = Data()
        appendInstruction(3, variable: 1, to: &code)        // store the argument
        appendInstruction(1, variable: 1, to: &code)        // push it
        appendInstruction(1, variable: 2, to: &code)        // push the literal
        appendInstruction(8, to: &code)                     // ==
        let branch = code.count
        // The branch is 5 bytes (opcode + immediate) and `complete` is 1, so a miss lands on the
        // return two instructions along.
        appendInstruction(16, jumpFrom: branch, to: branch + 6, in: &code)
        appendInstruction(40, to: &code)                    // complete;
        appendInstruction(1, variable: 3, to: &code)        // push the return value
        appendInstruction(33, to: &code)                    // ret

        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)                          // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(1, to: &data)                          // methods
        appendUInt16(0, to: &data)                          // class index
        appendUInt16(0, to: &data)                          // return type
        appendString("onKeyDown", to: &data)
        appendUInt32(4, to: &data)                          // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, to: &data)
        appendUInt32(1, to: &data)                          // constants
        appendUInt32(2, to: &data)
        appendString(literal, to: &data)
        appendUInt32(1, to: &data)                          // bindings
        appendUInt32(0, to: &data)                          // variable: the System object
        appendUInt32(0, to: &data)                          // method: onKeyDown
        appendUInt32(0, to: &data)                          // code offset
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private func appendInstruction(_ opcode: UInt8, variable: Int? = nil, to data: inout Data) {
        data.append(opcode)
        if let variable { appendUInt32(UInt32(variable), to: &data) }
    }

    private func appendInstruction(_ opcode: UInt8, jumpFrom origin: Int, to target: Int,
                                   in data: inout Data) {
        data.append(opcode)
        // A jump immediate is relative to the instruction *after* this one (opcode + 4 immediate).
        appendUInt32(UInt32(bitPattern: Int32(target - origin - 5)), to: &data)
    }

    private func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)          // subclass
        appendUInt16(0, to: &data)          // initial
        appendUInt16(0, to: &data)          // initial2
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)                      // global
        data.append(system ? 1 : 0)
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
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(bytes)
    }

    private func makeSkin(files: [String: Data]) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase43Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase43-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 provider: { position, size in
                let start = Int(position)
                return payload.subdata(in: start..<min(start + size, payload.count))
            })
        }
        return try WinampModernSkinLoader().load(from: url)
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var balance: Double = 0
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
