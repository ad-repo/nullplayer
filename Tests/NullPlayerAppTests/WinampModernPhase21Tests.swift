import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 21 — a layout the skin gave no resize range is fixed at the size its author drew.
///
/// Reported from a live T800 run: the window came up several hundred pixels too wide with the
/// Terminator's head smeared across it. T800's whole face is one background layer in a 177×400
/// layout that declares no `minimum_*` and no `maximum_*`; we read "undeclared" as "unbounded", so
/// `AppStateManager`'s restored frame — saved by a different skin's session — passed the clamp and
/// stretched the scene. Winamp gives such a window no resize affordance at all.
///
/// cPro-Bento declares 317×168…1920×1080 and Winamp Modern 5.66 declares a minimum, so both stay
/// resizable; the rule keys on whether the skin described a range, not on what the range works out to.
final class WinampModernPhase21Tests: XCTestCase {
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

    // MARK: - What counts as a resize range

    func testALayoutDeclaringNoRangeIsFixedAtItsOwnSize() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="177" h="400">
          <text id="inner" text="x" x="0" y="0" w="177" h="400"/>
        </layout>
        """)
        XCTAssertFalse(renderer.layoutIsUserResizable)
        XCTAssertEqual(renderer.userResizeLimits.minimum, CGSize(width: 177, height: 400))
        XCTAssertEqual(renderer.userResizeLimits.maximum, CGSize(width: 177, height: 400))
    }

    func testAnyOneDeclaredLimitMakesTheLayoutResizable() throws {
        for attribute in ["minimum_w=\"50\"", "minimum_h=\"20\"",
                          "maximum_w=\"900\"", "maximum_h=\"900\""] {
            let renderer = try makeRenderer(layout: """
            <layout id="normal" w="200" h="100" \(attribute)>
              <text id="inner" text="x" x="0" y="0" w="200" h="100"/>
            </layout>
            """)
            XCTAssertTrue(renderer.layoutIsUserResizable, "\(attribute) describes a range")
            XCTAssertEqual(renderer.userResizeLimits.minimum, renderer.layoutMinimumSize)
            XCTAssertEqual(renderer.userResizeLimits.maximum, renderer.layoutMaximumSize)
        }
    }

    /// Each layout answers for itself: T800's shade declares nothing either, and mmd3 has a
    /// range-declaring `normal` beside shade layouts that declare none.
    func testTheRangeIsReadPerLayoutNotPerSkin() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="300" h="120" minimum_w="100" minimum_h="40">
              <text id="a" text="x" x="0" y="0" w="300" h="120"/>
            </layout>
            <layout id="shade" w="300" h="24">
              <text id="b" text="x" x="0" y="0" w="300" h="24"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }

        XCTAssertTrue(renderer.layoutIsUserResizable)
        _ = try renderer.activateLayout(id: "shade")
        XCTAssertFalse(renderer.layoutIsUserResizable)
        XCTAssertEqual(renderer.userResizeLimits.maximum, CGSize(width: 300, height: 24))
    }

    // MARK: - What the limits are used for

    /// The reported symptom, in the pure form the restore path uses.
    func testARestoredFrameCannotStretchAFixedLayout() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="177" h="400">
          <text id="inner" text="x" x="0" y="0" w="177" h="400"/>
        </layout>
        """)
        let limits = renderer.userResizeLimits
        let clamped = WinampModernMainWindowController.clamp(
            frame: NSRect(x: 40, y: 100, width: 900, height: 500),
            minimum: limits.minimum, maximum: limits.maximum)
        XCTAssertEqual(clamped.size, NSSize(width: 177, height: 400))
        XCTAssertEqual(clamped.minX, 40)
        XCTAssertEqual(clamped.maxY, 600, "the saved top edge is still preserved")
    }

    /// A script may still resize a fixed layout — Winamp lets one, and this is how a skin drives its
    /// own window. Only the *user*-facing range is pinned.
    func testAScriptCanStillResizeAFixedLayout() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="100">
          <text id="inner" text="x" x="0" y="0" w="200" h="100"/>
        </layout>
        """)
        XCTAssertEqual(renderer.resize(to: CGSize(width: 400, height: 300)),
                       CGSize(width: 400, height: 300))
        XCTAssertEqual(renderer.userResizeLimits.maximum, CGSize(width: 400, height: 300),
                       "and the window follows the size the script chose")
    }

    // MARK: - A missing font must not fail the whole skin

    /// Rika would not load at all: it declares `<truetypefont file="SUPERGLU.ttf">` and ships no such
    /// file, and a missing font threw where a missing bitmap has always been tolerated. Winamp falls
    /// back to a default face. Everything else in the skin has to survive the miss.
    func testAMissingTrueTypeFontDegradesInsteadOfFailingTheLoad() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <elements>
            <truetypefont id="player.tickerfont" file="NOTSHIPPED.ttf"/>
          </elements>
          <container id="main">
            <layout id="normal" w="120" h="40">
              <text id="ticker" text="hello" font="player.tickerfont" x="0" y="0" w="120" h="40"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertFalse(loaded.runtime.graph.objects(xmlID: "ticker").isEmpty,
                       "the skin loads and keeps the text the missing font was for")
        XCTAssertTrue(loaded.runtime.diagnostics.contains {
            $0.code == .resourceMissing && $0.message.contains("NOTSHIPPED.ttf")
        }, "and the miss is reported rather than swallowed")
    }

    // MARK: - The EQ preamp

    /// Rika's `eq.xml` reads the preamp while wiring its own equalizer window, and the missing method
    /// aborted that whole script. The scale is MAKI's −127…127, the same as a band.
    func testTheEqualizerPreampIsReadableAndWritable() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="60" h="20"/></container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        var preamp = 40
        runtime.equalizerPreampRequested = { preamp }
        runtime.equalizerPreampSetterRequested = { preamp = $0 }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        let system = MakiObjectReference(.system)

        XCTAssertNotNil(runtime.signature(for: "geteqpreamp", classGUID: nil))
        XCTAssertEqual(try runtime.invoke(method: "getEqPreamp", on: system, arguments: [],
                                          program: program).integerValue, 40)
        _ = try runtime.invoke(method: "setEqPreamp", on: system, arguments: [.integer(-90)],
                               program: program)
        XCTAssertEqual(preamp, -90)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty)
    }

    // MARK: - Fixture

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase21Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase21-\(UUID().uuidString).wal")
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
