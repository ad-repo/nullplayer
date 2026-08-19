import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 27 — the two script methods every skin-drawn meter depends on.
///
/// Measured from Defix Hi-End 200 (`skills/winamp-modern-skin-guide/skins/defix-hi-end-200.md`): `getVisBand` was
/// missing, so its speaker cones, VU needles and level bars were dead by construction — no artwork
/// problem, the scripts simply never got a number. `isLoading` was missing on `<AlbumArt>`, which
/// aborted the playlist window's `ontimer` on every single tick.
final class WinampModernPhase27Tests: XCTestCase {
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

    // MARK: - `System.getVisBand(channel, band)`

    /// The value has to track the level the host is fed, in the vis-byte scale (0…255) the meter
    /// artwork is cut for — `std.mi` declares `Int System.getVisBand(int channel, int band)`.
    func testGetVisBandTracksTheInjectedLevel() throws {
        let (runtime, host, program) = try makeRuntime()
        host.spectrumLevels = Array(repeating: 0, count: WinampModernScriptRuntime.visBandCount)

        XCTAssertEqual(try visBand(runtime, program, band: 0), 0)
        host.spectrumLevels[0] = 1
        XCTAssertEqual(try visBand(runtime, program, band: 0), 255)
        host.spectrumLevels[0] = 0.5
        XCTAssertEqual(try visBand(runtime, program, band: 0), 128)
        XCTAssertEqual(try visBand(runtime, program, band: 1), 0,
                       "each band answers for itself")
    }

    /// The tap is mono, so both channels answer from it rather than one of them reading zero —
    /// documented in `compatibility.md`, and the reason a stereo meter still moves on both sides.
    func testBothChannelsAnswerFromTheOneMonoTap() throws {
        let (runtime, host, program) = try makeRuntime()
        host.spectrumLevels = Array(repeating: 1, count: WinampModernScriptRuntime.visBandCount)
        XCTAssertEqual(try visBand(runtime, program, channel: 0, band: 4), 255)
        XCTAssertEqual(try visBand(runtime, program, channel: 1, band: 4), 255)
    }

    /// A skin asks in Winamp's fixed 0…75 scale; the host's analyser produces 75 bands. The request
    /// is resampled, so the top of the skin's scale reaches the top of the tap rather than falling
    /// off the end of the array.
    func testABandRequestIsResampledIntoTheHostsBandCount() throws {
        let (runtime, host, program) = try makeRuntime()
        var levels = [Float](repeating: 0, count: 75)
        levels[74] = 1
        host.spectrumLevels = levels
        XCTAssertEqual(try visBand(runtime, program, band: 75), 255,
                       "the last band a skin can ask for reaches the last band the tap produces")
        XCTAssertEqual(try visBand(runtime, program, band: 0), 0)
    }

    /// Nothing playing, and a band index a skin has no business asking for. Both are answered, not
    /// trapped: a meter that polls from a timer would otherwise abort its handler every tick.
    func testGetVisBandIsBoundedWithoutASpectrumAndOutsideItsRange() throws {
        let (runtime, host, program) = try makeRuntime()
        XCTAssertEqual(try visBand(runtime, program, band: 0), 0, "no levels means silence")

        host.spectrumLevels = Array(repeating: 1, count: WinampModernScriptRuntime.visBandCount)
        XCTAssertEqual(try visBand(runtime, program, band: -5), 255)
        XCTAssertEqual(try visBand(runtime, program, band: 9_999), 255)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty)
    }

    // MARK: - `System.getLeftVUMeter()` / `getRightVUMeter()` (27.5)

    /// A VU meter reads **program level**, not the spectrum: the host's RMS model, per channel, in
    /// the 0…255 vis-byte scale. Reading a peak band out of the bar-display tap instead pinned every
    /// needle — that tap is mono and already normalised so bars fill their window.
    func testVUMetersReadTheHostsPerChannelLevelRatherThanTheSpectrum() throws {
        let (runtime, host, program) = try makeRuntime()
        // A spectrum sitting at full scale must not move a needle by itself.
        host.spectrumLevels = Array(repeating: 1, count: WinampModernScriptRuntime.visBandCount)
        XCTAssertEqual(try vuMeter(runtime, program, left: true), 0)
        XCTAssertEqual(try vuMeter(runtime, program, left: false), 0)

        host.vuLevels = (left: 1, right: 0.5)
        XCTAssertEqual(try vuMeter(runtime, program, left: true), 255)
        XCTAssertEqual(try vuMeter(runtime, program, left: false), 128,
                       "the channels answer independently — the level model is stereo")
    }

    /// Levels are clamped rather than trusted: a model that overshoots, or a NaN out of a silent
    /// buffer, must not hand a skin a value outside the byte scale it indexes artwork with.
    func testVUMeterValuesAreClamped() throws {
        let (runtime, host, program) = try makeRuntime()
        host.vuLevels = (left: 4, right: -1)
        XCTAssertEqual(try vuMeter(runtime, program, left: true), 255)
        XCTAssertEqual(try vuMeter(runtime, program, left: false), 0)

        host.vuLevels = (left: .nan, right: 0)
        XCTAssertEqual(try vuMeter(runtime, program, left: true), 0)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty)
    }

    // MARK: - `AlbumArtLayer.isLoading()`

    /// Defix's `PLAYLIST_WINDOW` polls its `<AlbumArt>` from `ontimer`, and the missing method took
    /// that handler down continuously. The answer comes from the host's real fetch state.
    func testAlbumArtIsLoadingReportsTheHostsFetchState() throws {
        let (runtime, host, program) = try makeRuntime()
        let art = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "aa.curr").first)
        let reference = MakiObjectReference(.gui(art.stableID))

        XCTAssertNotNil(runtime.signature(for: "isloading", classGUID: nil))
        XCTAssertFalse(try runtime.invoke(method: "isLoading", on: reference, arguments: [],
                                          program: program).truthy)
        host.isArtworkLoading = true
        XCTAssertTrue(try runtime.invoke(method: "isLoading", on: reference, arguments: [],
                                         program: program).truthy)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty,
                      "the call is implemented, so it must not show up as unmet demand")
    }

    /// Only an `<AlbumArt>` has a fetch to wait on. Any other receiver is honestly not loading
    /// anything, rather than inheriting the album art's answer.
    func testIsLoadingIsFalseForAnObjectWithNothingToLoad() throws {
        let (runtime, host, program) = try makeRuntime()
        host.isArtworkLoading = true
        let layer = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "plain").first)
        XCTAssertFalse(try runtime.invoke(method: "isLoading",
                                          on: MakiObjectReference(.gui(layer.stableID)),
                                          arguments: [], program: program).truthy)
    }

    // MARK: - The settings a skin registers but binds nothing to (27.3)

    /// Defix's shape exactly: one `Config.newItem` per setting, then one `newAttribute` per *value*
    /// — the attribute names are the values ("Audio cassette"), the item is the setting
    /// ("Visualizer"). The list has to keep registration order and the item's own display name, or
    /// a settings window can only group by raw GUID.
    func testRegisteredSettingsAreEnumeratedInOrderWithTheirSectionName() throws {
        let (runtime, _, program) = try makeRuntime()
        try registerVisualizerAndSongticker(runtime, program)

        XCTAssertEqual(runtime.registeredSettings.map(\.name),
                       ["Audio cassette", "Left Right VU", "Disable Songticker Scrolling"])
        XCTAssertEqual(runtime.registeredSettings.map(\.sectionName),
                       ["Visualizer", "Visualizer", "Songticker"])
        XCTAssertEqual(runtime.registeredSettings.map(\.section),
                       ["{E9C2D926}", "{E9C2D926}", "{7061FDE0}"])
        XCTAssertEqual(runtime.configAttributeValue(runtime.registeredSettings[0]), "1",
                       "the declared default is the value until something changes it")
        XCTAssertEqual(runtime.configAttributeValue(runtime.registeredSettings[1]), "0")
    }

    /// Every script that needs a setting registers it again — Defix's eight scripts each register
    /// the same eleven — so the list has to survive being told the same thing repeatedly.
    func testRegisteringTheSameAttributeTwiceListsItOnce() throws {
        let (runtime, _, program) = try makeRuntime()
        try registerVisualizerAndSongticker(runtime, program)
        try registerVisualizerAndSongticker(runtime, program)
        XCTAssertEqual(runtime.registeredSettings.count, 3)
    }

    /// The write-back is the *same* route a `cfgattrib` control the skin drew itself uses, so the
    /// two cannot disagree about the value or about whether the skin was told.
    func testWritingASettingIsTheSameRouteAsAConfigBoundControl() throws {
        let (runtime, _, program) = try makeRuntime()
        try registerVisualizerAndSongticker(runtime, program)
        let control = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "style.switch").first)
        var repaints = 0
        runtime.graphDidMutate = { repaints += 1 }

        XCTAssertTrue(runtime.configValue(of: control), "the control reads the registered default")
        runtime.setConfigAttribute(section: "{E9C2D926}", key: "Audio cassette", value: "0")
        XCTAssertFalse(runtime.configValue(of: control))
        XCTAssertEqual(repaints, 1, "the surfaces are told to repaint")

        // And the skin's own control still writes the same value back through the same path.
        XCTAssertTrue(runtime.toggleConfigAttribute(of: control))
        XCTAssertTrue(runtime.configValue(of: control))
        XCTAssertEqual(runtime.configAttributeValue(runtime.registeredSettings[0]), "1")
        XCTAssertEqual(repaints, 2)
    }

    /// The empty state: a skin that registers nothing must offer no entry point at all, rather than
    /// an empty window. `WindowManager` asks this before it builds the menu item.
    func testASkinThatRegistersNothingHasNoSettings() throws {
        let (runtime, _, _) = try makeRuntime()
        XCTAssertTrue(runtime.registeredSettings.isEmpty)
    }

    // MARK: - The skin's own extra windows (27.7)

    /// Reported live: *there is no way to open the speaker windows.* Defix declares `SPEAKER 1` and
    /// `SPEAKER 2` — they render — and binds no button anywhere in the skin to either; in Winamp they
    /// are opened from Winamp's Windows menu. The rule for what belongs in that menu is the skin's
    /// own markup, and this fixture is Defix's container list verbatim.
    func testTheWindowMenuListsNamedContainersTheSkinBindsNoButtonTo() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main" name="Main Window">
            <layout id="normal" w="406" h="355"/>
          </container>
          <container id="Config" name="Skin Settings" default_visible="1">
            <layout id="normal" w="406" h="355"/>
          </container>
          <container id="SPEAKER1" name="SPEAKER 1" default_visible="0">
            <layout id="normal" w="285" h="355"/>
          </container>
          <container id="notifier" name="Notifier" nomenu="1" default_visible="0">
            <layout id="normal" w="128" h="80"/>
          </container>
          <container id="SUI" default_visible="0">
            <layout id="normal" w="800" h="600"/>
          </container>
          <container id="pledit" name="Playlist Editor" component="guid:{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}">
            <layout id="normal" w="406" h="355"/>
          </container>
        </WasabiXML>
        """)
        let listed = WinampModernContainerTopology.analyze(graph: loaded.runtime.graph)
            .filter(WinampModernContainerTopology.isListedInWindowMenu)
            .map(WinampModernContainerTopology.displayName)

        XCTAssertEqual(listed, ["Skin Settings", "SPEAKER 1"],
                       "named, menu-visible containers with no surface of their own")
        // Each exclusion for its own reason, so a future change cannot quietly widen the list:
        // `main` is never closed from a list; `nomenu="1"` is the skin saying "not in the menu";
        // an unnamed container is reached by the skin's own buttons; and a container the surface
        // catalog already routes has its own menu item, so a second entry would be a second route.
        XCTAssertFalse(listed.contains("Main Window"))
        XCTAssertFalse(listed.contains("Notifier"))
        XCTAssertFalse(listed.contains("SUI"))
        XCTAssertFalse(listed.contains("Playlist Editor"))
    }

    // MARK: - Fixture

    /// `Config.newItem(name, guid)` + `ConfigItem.newAttribute(value, default)`, the way a skin's
    /// `onScriptLoaded` does it.
    private func registerVisualizerAndSongticker(_ runtime: WinampModernScriptRuntime,
                                                 _ program: MakiProgram) throws {
        func item(_ name: String, _ guid: String) throws -> MakiObjectReference {
            let value = try runtime.invoke(method: "newItem", on: MakiObjectReference(.system),
                                           arguments: [.string(name), .string(guid)], program: program)
            guard case .object(let reference) = value else {
                throw XCTSkip("newItem must answer with a ConfigItem")
            }
            return reference
        }
        func attribute(_ item: MakiObjectReference, _ name: String, _ defaultValue: String) throws {
            _ = try runtime.invoke(method: "newAttribute", on: item,
                                   arguments: [.string(name), .string(defaultValue)], program: program)
        }
        let visualizer = try item("Visualizer", "{E9C2D926}")
        try attribute(visualizer, "Audio cassette", "1")
        try attribute(visualizer, "Left Right VU", "0")
        let songticker = try item("Songticker", "{7061FDE0}")
        try attribute(songticker, "Disable Songticker Scrolling", "1")
    }

    private func vuMeter(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                         left: Bool) throws -> Int32 {
        try runtime.invoke(method: left ? "getLeftVUMeter" : "getRightVUMeter",
                           on: MakiObjectReference(.system), arguments: [],
                           program: program).integerValue
    }

    private func visBand(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                         channel: Int32 = 0, band: Int32) throws -> Int32 {
        try runtime.invoke(method: "getVisBand", on: MakiObjectReference(.system),
                           arguments: [.integer(channel), .integer(band)],
                           program: program).integerValue
    }

    // MARK: - `System.getPlaylistLength()`

    /// Defix's playlist box writes its track count as `"Items: " + integerToString(getPlaylistLength())`
    /// — it does *not* parse that number out of `PE_Info`. The call sat before the write, so the
    /// missing method aborted the whole `onTimer` handler and the readout never appeared at all.
    /// It answers from the same snapshot `PE_Info` is built from, so a skin showing both agrees with
    /// itself.
    func testGetPlaylistLengthAnswersFromThePlaylistSnapshot() throws {
        let (runtime, _, program) = try makeRuntime()

        WasabiTextMetrics.componentTextProvider = nil
        XCTAssertEqual(try playlistLength(runtime, program), 0, "no component means an empty queue")

        WasabiTextMetrics.componentTextProvider = {
            WinampModernPlaylistSnapshot(
                rows: (0..<3).map { WinampModernPlaylistRow(title: "t\($0)", secondary: "",
                                                            duration: 60, isCurrent: $0 == 0) },
                currentIndex: 0, selectedIndex: 0)
        }
        addTeardownBlock { WasabiTextMetrics.componentTextProvider = nil }
        XCTAssertEqual(try playlistLength(runtime, program), 3)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty,
                      "the method must be implemented, not merely declared — a refused call takes "
                      + "the rest of the handler with it")
    }

    private func playlistLength(_ runtime: WinampModernScriptRuntime,
                                _ program: MakiProgram) throws -> Int32 {
        try runtime.invoke(method: "getPlaylistLength", on: MakiObjectReference(.system),
                           arguments: [], program: program).integerValue
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, TestHost, MakiProgram) {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="120" h="120">
              <AlbumArt id="aa.curr" x="0" y="0" w="60" h="60"/>
              <layer id="plain" x="60" y="0" w="60" h="60"/>
              <togglebutton id="style.switch" x="0" y="60" w="60" h="20"
                            cfgattrib="{E9C2D926};Audio cassette"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, host, program)
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase27Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase27-\(UUID().uuidString).wal")
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
