import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 45 — Defix's configurator, driven (B11).
///
/// The measured defect: a skin's configurator writes a preference from its *own* script
/// (`ConfigAttribute.setData`), and every other window applies it from `onDataChanged` on the copy
/// of the attribute **its** script registered. `setData` dispatched the event to the calling
/// object alone, so Defix's "Body material" arrows changed the configurator's own background and
/// left the player, both speaker cabinets, the playlist and the library wearing the old artwork —
/// while `WinampModernScriptRuntime.setConfigAttribute` (the host's Skin Settings window) had
/// broadcast to every holder since Phase 27. Two write routes, two different behaviours.
final class WinampModernPhase45Tests: XCTestCase {
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

    // MARK: - A script's own write is the shared write

    /// `setData` from a skin script must land on the same route the settings window uses: the value
    /// is stored, every surface is told to repaint, and a `cfgattrib` control bound to the same
    /// attribute reads the new state. Before this the script route wrote the value and repainted
    /// nothing, so a switch moved only when the *host* moved it.
    func testAScriptsSetDataWritesThroughTheSharedRouteAndRepaints() throws {
        let (runtime, program) = try makeRuntime()
        let attribute = try registerBackgroundToggle(runtime, program)
        let indicator = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "bg.switch").first)
        var repaints = 0
        runtime.graphDidMutate = { repaints += 1 }

        XCTAssertTrue(runtime.configValue(of: indicator), "the registered default is the state")
        _ = try runtime.invoke(method: "setData", on: attribute, arguments: [.string("0")],
                               program: program)

        XCTAssertEqual(runtime.configAttributeValue(runtime.registeredSettings[0]), "0")
        XCTAssertFalse(runtime.configValue(of: indicator), "the indicator follows the stored value")
        XCTAssertEqual(repaints, 1, "the windows are told, exactly as the settings window tells them")
    }

    /// Defix's shape: eight scripts register the same attribute, each getting its own object, and
    /// the configurator writes through *one* of them. The other seven must see the new value —
    /// that is how five windows change their background from one click on an arrow.
    func testASecondHolderOfTheSameAttributeSeesAScriptsWrite() throws {
        let (runtime, program) = try makeRuntime()
        let first = try registerBackgroundToggle(runtime, program)
        let second = try registerBackgroundToggle(runtime, program)
        XCTAssertNotEqual(describe(first), describe(second),
                          "each registration hands the script its own object, as Winamp does")

        _ = try runtime.invoke(method: "setData", on: first, arguments: [.string("0")], program: program)

        let readBack = try runtime.invoke(method: "getData", on: second, arguments: [], program: program)
        XCTAssertEqual(readBack.stringValue, "0")
        XCTAssertEqual(runtime.registeredSettings.count, 1, "and it is still one setting, not two")
    }

    /// The guard the shared route must not lose: `setData` is a `ConfigAttribute` method, and a
    /// `ConfigItem` (the *tree node* a skin registers its attributes under) is not one. Writing
    /// through it would invent a setting named after a GUID.
    func testSetDataOnAConfigItemWritesNothing() throws {
        let (runtime, program) = try makeRuntime()
        _ = try registerBackgroundToggle(runtime, program)
        let item = try newItem(runtime, program, name: "Appearance", guid: "{F1036C9C}")
        var repaints = 0
        runtime.graphDidMutate = { repaints += 1 }

        _ = try runtime.invoke(method: "setData", on: item, arguments: [.string("0")], program: program)

        XCTAssertEqual(runtime.configAttributeValue(runtime.registeredSettings[0]), "1",
                       "the attribute is untouched")
        XCTAssertEqual(repaints, 0)
    }

    // MARK: - Helpers

    private func describe(_ reference: MakiObjectReference) -> String {
        if case .dynamic(let id) = reference.kind { return "dynamic-\(id)" }
        return "\(reference.kind)"
    }

    private func newItem(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                         name: String, guid: String) throws -> MakiObjectReference {
        let value = try runtime.invoke(method: "newItem", on: MakiObjectReference(.system),
                                       arguments: [.string(name), .string(guid)], program: program)
        guard case .object(let reference) = value else {
            throw XCTSkip("newItem must answer with a ConfigItem")
        }
        return reference
    }

    /// Defix's `Bg Chng`: the pulse its configurator toggles to tell every window's frame script to
    /// re-read the background id it just stored.
    @discardableResult
    private func registerBackgroundToggle(_ runtime: WinampModernScriptRuntime,
                                          _ program: MakiProgram) throws -> MakiObjectReference {
        let item = try newItem(runtime, program, name: "Appearance", guid: "{F1036C9C}")
        let value = try runtime.invoke(method: "newAttribute", on: item,
                                       arguments: [.string("Bg Chng"), .string("1")], program: program)
        guard case .object(let reference) = value else {
            throw XCTSkip("newAttribute must answer with a ConfigAttribute")
        }
        return reference
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="120" h="120">
              <togglebutton id="bg.switch" x="0" y="0" w="60" h="20"
                            cfgattrib="{F1036C9C};Bg Chng"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, program)
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase45Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase45-\(UUID().uuidString).wal")
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
}
