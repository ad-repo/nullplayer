import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 90 (backlog BB13) — `System.setClipboardText`.
///
/// The method was absent, and dispatch is fail-closed, so it did not merely fail to copy: it threw
/// `unsupported` and abandoned the **whole handler**. Defix Hi-END 200 calls it from the handler
/// that builds its playlist popup menu (`SCRIPTS/PLAYLIST_LAYOUT_SCRIPT.maki`, beside the menu's own
/// "Copy … to clipboard" strings), and the ClassicPro engine from eight more — its file-info,
/// shade-info and album-art menus.
///
/// The seam is deliberately one-way. Winamp has no matching read, and a skin that could read the
/// pasteboard would be reading whatever the user last copied in another application.
final class WinampModernPhase90Tests: XCTestCase {

    // MARK: - The call reaches the host

    func testSetClipboardTextHandsTheStringToTheHost() throws {
        let host = Host()
        let runtime = try makeRuntime(host: host)
        let result = try runtime.invoke(method: "setclipboardtext", on: MakiObjectReference(.system),
                                        arguments: [.string("Artist - Title")], program: emptyProgram())
        XCTAssertEqual(host.copied, ["Artist - Title"])
        // Void in Winamp: a script that assigns the result would otherwise read a stray value.
        guard case .null = result else { return XCTFail("setClipboardText answers null") }
    }

    /// **The regression guard, and the reason the item was filed.** What a skin loses to a missing
    /// method is not the one call — it is everything after it in the same handler.
    func testACallDoesNotAbandonTheRestOfTheHandler() throws {
        let host = Host()
        host.trackTitle = "Still Running"
        let runtime = try makeRuntime(host: host)
        _ = try runtime.invoke(method: "setclipboardtext", on: MakiObjectReference(.system),
                               arguments: [.string("copied")], program: emptyProgram())
        let title = try runtime.invoke(method: "getplayitemstring", on: MakiObjectReference(.system),
                                       arguments: [], program: emptyProgram())
        XCTAssertEqual(title.stringValue, "Still Running")
    }

    /// One argument, recorded in the signature table rather than inferred: an unknown arity
    /// desynchronises the interpreter's stack, which corrupts the rest of the program rather than
    /// failing at the call.
    func testTheSignatureTakesExactlyOneArgument() throws {
        let runtime = try makeRuntime(host: Host())
        let signature = try XCTUnwrap(runtime.signature(for: "setclipboardtext", classGUID: nil))
        XCTAssertEqual(signature.argumentCount, 1)
    }

    // MARK: - What a host with no pasteboard does

    /// The render harness and every test double take the protocol's default. It swallows the write
    /// rather than reaching `NSPasteboard.general`, so a corpus sweep over 36 skins cannot leave the
    /// user's clipboard holding whatever the last skin's startup script copied.
    func testAHostThatImplementsNothingStillAcceptsTheCall() throws {
        let runtime = try makeRuntime(host: BareHost())
        XCTAssertNoThrow(try runtime.invoke(method: "setclipboardtext", on: MakiObjectReference(.system),
                                            arguments: [.string("ignored")], program: emptyProgram()))
    }

    // MARK: - The bound

    /// The strings the corpus copies are a title, a path or a tag line. A script-built megabyte is
    /// truncated rather than allowed to fill the pasteboard.
    func testAnOversizedStringIsTruncatedRatherThanRefused() {
        let short = "Artist - Title"
        XCTAssertEqual(WinampModernAudioEngineHost.boundedClipboardText(short), short)
        let long = String(repeating: "a", count: 200_000)
        XCTAssertEqual(WinampModernAudioEngineHost.boundedClipboardText(long).count, 64 * 1_024)
    }

    // MARK: - Helpers

    private func makeRuntime(host: WinampModernHost) throws -> WinampModernScriptRuntime {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <layer id="plain" x="0" y="0" w="10" h="10"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase90Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase90-\(UUID().uuidString).wal")
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

    /// Records the write instead of performing it.
    private final class Host: WinampModernHost {
        var copied: [String] = []
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []
        func setClipboardText(_ text: String) { copied.append(text) }
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

    /// Implements only the protocol's requirements — the shape of the render harness's host.
    private final class BareHost: WinampModernHost {
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
