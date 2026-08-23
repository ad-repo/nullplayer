import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 53 — B36/B37, Big Bento Modern's live defects. All four variants loaded after B35 but
/// drew wrongly, and the cause was one class of failure: 23 of the skin's `onScriptLoaded`
/// handlers aborted on an unsupported MAKI method, taking their layout work with them.
///
/// `getSettingsPath` was the first domino — the skin probes for a WACUP install at the top of
/// nearly every script — and behind it sat `getAutoHeight`, `getGuid` and `scrollToPercent`. The
/// menu bar's five items are placed by `mainmenu.maki`, not by a widget rule, which is why they
/// all sat at the group origin with `w=0`; nothing in the `Menu` widget needed changing.
///
/// The second half is the `display=` binding table, which knew only `time` / `songname` /
/// `songinfo` / `PE_Info`. Big Bento's readouts ask for `TIMEELAPSED`, `SONGLENGTH`, `SONGTITLE`
/// and `SONGSAMPLERATE`, so they fell through to the literal `text=` — empty — and the display
/// panel drew a lone `/` between two blank time fields.
final class WinampModernPhase53Tests: XCTestCase {

    // MARK: - The methods that aborted the handlers

    func testGetSettingsPathAnswersAnAbsoluteDirectory() throws {
        let (runtime, _) = try makeRuntimeWithObject()
        let path = try runtime.invoke(method: "getsettingspath", on: MakiObjectReference(.system),
                                      arguments: [], program: emptyProgram()).stringValue
        XCTAssertTrue(path.hasPrefix("/"), "a settings path a skin concatenates a filename onto")
        XCTAssertFalse(path.hasSuffix("/"), "callers append their own separator")
    }

    func testScrollToPercentIsAcceptedRatherThanAborting() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        XCTAssertNoThrow(try runtime.invoke(method: "scrolltopercent", on: reference(object),
                                            arguments: [.integer(50)], program: emptyProgram()))
    }

    func testGetGuidAnswersTheDeclaredGuidAndEmptyWhenThereIsNone() throws {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <layer id="plain" x="0" y="0" w="10" h="10"/>
              <layer id="tagged" x="0" y="0" w="10" h="10" guid="{0000000A-000C-0010-FF7B-01014263450C}"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let plain = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "plain").first)
        let tagged = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "tagged").first)
        XCTAssertEqual(try runtime.invoke(method: "getguid", on: reference(plain),
                                          arguments: [], program: emptyProgram()).stringValue, "")
        XCTAssertEqual(try runtime.invoke(method: "getguid", on: reference(tagged),
                                          arguments: [], program: emptyProgram()).stringValue,
                       "{0000000A-000C-0010-FF7B-01014263450C}")
    }

    // MARK: - getAutoHeight

    func testGetAutoHeightPrefersTheDeclaredHeight() throws {
        let runtime = try makeRuntime(layout: """
        <layout id="normal" w="200" h="200">
          <text id="sized" x="0" y="0" w="80" h="37" text="Options" fontsize="20"/>
        </layout>
        """)
        XCTAssertEqual(try height(of: "sized", in: runtime), 37)
    }

    func testGetAutoHeightMeasuresOneLineWhenNoHeightIsDeclared() throws {
        let runtime = try makeRuntime(layout: """
        <layout id="normal" w="200" h="200">
          <text id="unsized" x="0" y="0" text="Options" fontsize="20"/>
        </layout>
        """)
        let measured = try height(of: "unsized", in: runtime)
        XCTAssertGreaterThan(measured, 0, "a text object has an intrinsic line height")
        XCTAssertLessThan(measured, 200, "one line, not the whole layout")
    }

    func testGetAutoHeightIsZeroForAnObjectWithNoIntrinsicHeight() throws {
        let runtime = try makeRuntime(layout: """
        <layout id="normal" w="200" h="200">
          <group id="bare" x="0" y="0"/>
        </layout>
        """)
        XCTAssertEqual(try height(of: "bare", in: runtime), 0)
    }

    // MARK: - display= bindings

    func testTimeElapsedAndSongLengthReadTheHostClock() throws {
        let host = Host()
        host.currentTime = 95
        host.duration = 245
        let elapsed = try object(attributes: ["display": "TIMEELAPSED"])
        let length = try object(attributes: ["display": "SONGLENGTH"])
        XCTAssertEqual(WasabiTextMetrics.content(of: elapsed, host: host), "1:35")
        XCTAssertEqual(WasabiTextMetrics.content(of: length, host: host), "4:05")
    }

    func testTimerHoursExtendsTheFieldPastAnHour() throws {
        let host = Host()
        host.currentTime = 5600
        let plain = try object(attributes: ["display": "TIMEELAPSED"])
        let hours = try object(attributes: ["display": "TIMEELAPSED", "timerhours": "1"])
        XCTAssertEqual(WasabiTextMetrics.content(of: plain, host: host), "93:20")
        XCTAssertEqual(WasabiTextMetrics.content(of: hours, host: host), "1:33:20")
    }

    func testSongTitleIsTheTitleAloneAndSongNameIsTheDisplayTitle() throws {
        let host = Host()
        host.trackTitle = "Electric Machine"
        host.trackArtist = "Acid King"
        let title = try object(attributes: ["display": "SONGTITLE"])
        let name = try object(attributes: ["display": "SONGNAME"])
        let artist = try object(attributes: ["display": "SONGARTIST"])
        XCTAssertEqual(WasabiTextMetrics.content(of: title, host: host), "Electric Machine")
        XCTAssertEqual(WasabiTextMetrics.content(of: name, host: host), "Acid King - Electric Machine")
        XCTAssertEqual(WasabiTextMetrics.content(of: artist, host: host), "Acid King")
    }

    func testSampleRateIsInKilohertzAndBitrateInKilobits() throws {
        let host = Host()
        host.bitrateKbps = 320
        host.sampleRateHz = 44100
        let rate = try object(attributes: ["display": "SONGSAMPLERATE"])
        let bitrate = try object(attributes: ["display": "SONGBITRATE"])
        // The skin draws its own "KHZ" label beside a 35px field: "44", never "44100".
        XCTAssertEqual(WasabiTextMetrics.content(of: rate, host: host), "44")
        XCTAssertEqual(WasabiTextMetrics.content(of: bitrate, host: host), "320")
    }

    func testUnknownBindingStillFallsBackToTheLiteralText() throws {
        let host = Host()
        let literal = try object(attributes: ["display": "Now Playing", "text": "-"])
        XCTAssertEqual(WasabiTextMetrics.content(of: literal, host: host), "-",
                       "an unmapped binding must not swallow the placeholder the skin ships")
    }

    // MARK: - offsetx / offsety shift the string, not the box

    func testTextOffsetMovesTheInkWithoutMovingTheBox() throws {
        let plain = try inkColumns(offset: "")
        let shifted = try inkColumns(offset: #"offsetx="40""#)
        let plainStart = try XCTUnwrap(plain.min(), "the control run must draw something")
        let shiftedStart = try XCTUnwrap(shifted.min(), "the shifted run must still draw something")
        XCTAssertGreaterThanOrEqual(shiftedStart - plainStart, 30,
                                    "offsetx=40 must push the string well to the right")
    }

    func testTextOffsetIsClippedByTheDeclaredBox() throws {
        // The box is 60 wide; a 200px offset puts every glyph outside it. This is exactly how Big
        // Bento Modern's icons-only tab strip hides its captions.
        XCTAssertTrue(try inkColumns(offset: #"offsetx="200""#).isEmpty,
                      "a string pushed past its own box must be clipped away entirely")
    }

    /// Canvas columns carrying any ink, for a single white `<text>` on a black layout.
    private func inkColumns(offset: String) throws -> [Int] {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="120" h="40">
              <text id="caption" x="0" y="0" w="60" h="40" text="IIII" fontsize="20"
                    color="255,255,255" \(offset)/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host())
        addTeardownBlock { renderer.teardown() }
        let (width, height) = (120, 40)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // `drawText` ends in `NSString.draw(in:)`, which renders into the *current*
            // `NSGraphicsContext` — without one installed every string is silently dropped.
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            defer { NSGraphicsContext.current = previous }
            renderer.draw(in: context)
        }
        return (0..<width).filter { column in
            (0..<height).contains { row in pixels[(row * width + column) * 4] > 40 }
        }
    }

    // MARK: - move="1" names a drag handle on any non-control element

    @MainActor
    func testMoveFlagDragsTheWindowOnAGridOrRectNotJustAGroup() throws {
        let view = try makeDragView()
        for identifier in ["titlebar.grid", "vic_mover", "caption"] {
            let object = try XCTUnwrap(view.renderer.sceneNodes()
                .first { $0.object.xmlID == identifier }?.object, identifier)
            XCTAssertTrue(view.shouldDragWindow(from: object),
                          "move=\"1\" on <\(object.typeName)> must name a drag handle")
        }
    }

    @MainActor
    func testMoveFlagOnAButtonStillLetsTheButtonKeepItsClick() throws {
        let view = try makeDragView()
        let button = try XCTUnwrap(view.renderer.sceneNodes()
            .first { $0.object.xmlID == "movingbutton" }?.object)
        XCTAssertFalse(view.shouldDragWindow(from: button),
                       "a control that also says move=\"1\" must not swallow its own click")
    }

    @MainActor
    func testAGroupWithoutTheMoveFlagIsStillNotAHandle() throws {
        let view = try makeDragView()
        let group = try XCTUnwrap(view.renderer.sceneNodes()
            .first { $0.object.xmlID == "plaingroup" }?.object)
        XCTAssertFalse(view.shouldDragWindow(from: group))
    }

    @MainActor
    private func makeDragView() throws -> WinampModernMainView {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <grid id="titlebar.grid" x="0" y="0" w="200" h="20" move="1"/>
              <rect id="vic_mover" fitparent="1" move="1" color="0,0,0" alpha="0"/>
              <text id="caption" x="0" y="30" w="80" h="20" text="Title" move="1"/>
              <button id="movingbutton" x="0" y="60" w="20" h="20" move="1"/>
              <group id="plaingroup" x="0" y="90" w="40" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                        componentHost: nil)
        view.setFrameSize(renderer.canvasSize)
        return view
    }

    // MARK: - Helpers

    private func height(of identifier: String, in runtime: WinampModernScriptRuntime) throws -> Int32 {
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: identifier).first)
        return try runtime.invoke(method: "getautoheight", on: reference(object),
                                  arguments: [], program: emptyProgram()).integerValue
    }

    private func object(attributes: [String: String]) throws -> WasabiObject {
        let declared = attributes.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <text id="readout" x="0" y="0" w="100" h="20" \(declared)/>
            </layout>
          </container>
        </WasabiXML>
        """)
        return try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "readout").first)
    }

    private func makeRuntime(layout: String) throws -> WinampModernScriptRuntime {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func makeRuntimeWithObject() throws -> (WinampModernScriptRuntime, WasabiObject) {
        let runtime = try makeRuntime(layout: """
        <layout id="normal" w="200" h="200">
          <layer id="movable" x="0" y="100" w="40" h="40"/>
        </layout>
        """)
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "movable").first)
        return (runtime, object)
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase53Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase53-\(UUID().uuidString).wal")
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

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
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
