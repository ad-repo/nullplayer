import XCTest
import ZIPFoundation
@testable import NullPlayer

/// CPro_iPhone3gv2 (intake #2): every ClassicPro tab ever clicked stayed lit.
///
/// `CproTabButton` answers `onLeftButtonUp` by asking `CproTabs` to clear every tab, then
/// `setActivated(1)` on itself. Two faults sat on that path:
///
/// - `closeTab` clears each `cpro.tab` **group**, the `embed_xui` wrapper, and the activation stayed
///   on the group instead of reaching the togglebutton it embeds — so no tab ever went dark.
/// - The view flipped the togglebutton *after* the release reached the script, so once the clear
///   worked the tab just chosen was flipped back off. Wasabi flips it in `onLeftPush`, first.
final class WinampModernEmbeddedToggleTests: XCTestCase {

    func testAWrappersActivationIsItsButtons() throws {
        let (loaded, scripts) = try makeRuntime()
        let wrapper = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "tab").first)
        let button = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "tab.button").first)
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        let reference = MakiObjectReference(.gui(wrapper.stableID))

        _ = try scripts.invoke(method: "setActivated", on: reference, arguments: [.boolean(true)], program: program)
        XCTAssertEqual(button.attributes["activated"], "1", "the call on the group reaches the button")
        XCTAssertTrue(try scripts.invoke(method: "getActivated", on: reference, arguments: [], program: program).truthy,
                      "and the group reads the button's state back")

        _ = try scripts.invoke(method: "setActivated", on: reference, arguments: [.boolean(false)], program: program)
        XCTAssertEqual(button.attributes["activated"], "0", "closeTab's clear turns the tab off")
    }

    func testAClickFlipsTheToggleBeforeTheScriptHearsTheRelease() throws {
        let (loaded, scripts) = try makeRuntime()
        let host = TestHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host)
        addTeardownBlock { view.teardown() }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: renderer.canvasSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.setFrameSize(renderer.canvasSize)
        scripts.recordsDispatchedEventsForTesting = true

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 10, y: 10),
                                                         modifierFlags: [], timestamp: 0,
                                                         windowNumber: window.windowNumber, context: nil,
                                                         eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }

        let events = scripts.dispatchedEventsForTesting.filter { $0.object == "tab.button" }.map(\.event)
        let toggle = try XCTUnwrap(events.firstIndex(of: "ontoggle"), "the click flips the button")
        let release = try XCTUnwrap(events.firstIndex(of: "onleftbuttonup"))
        XCTAssertLessThan(toggle, release, "flipped before the script's own setActivated can run")
    }

    // MARK: -

    private func makeRuntime() throws -> (WinampModernLoadedSkin, WinampModernScriptRuntime) {
        let xml = """
        <WasabiXML>
          <groupdef id="tab" embed_xui="tab.button">
            <togglebutton id="tab.button" fitparent="1"/>
          </groupdef>
          <container id="main">
            <layout id="normal" w="20" h="20">
              <group id="tab" x="0" y="0" w="20" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernEmbeddedToggleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("toggle.wal")
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
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { scripts.teardown() }
        return (loaded, scripts)
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
