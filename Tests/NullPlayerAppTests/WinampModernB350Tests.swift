import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B350 — ClassicPro's SUI tabs open and close from the Windows menu.
///
/// The host never edits the strip: it sends the engine's own `switch_to_tab`, and closes a tab by
/// setting its *Auto Close Tab* flag for the one switch that takes it out. These tests stand in for
/// the engine with the two rules `CproTabs.m` was observed to follow (B350, `bento_tabs.sh`): a tab
/// whose flag is set leaves the strip as it is switched away from, and switching to a tab that is
/// out of the strip puts it back, at the end. What they pin is the host's half — which switches it
/// sends, in what order, and that no flag outlives the close.
final class WinampModernB350Tests: XCTestCase {

    // MARK: - Reading the strip

    func testTheStripListsOpenTabsInStripOrderThenClosedOnesWithoutThePluginPage() throws {
        let scene = try makeScene()
        _ = scene.group("tab.video").setAttribute("visible", value: "0")

        XCTAssertEqual(scene.strip.tabs.map(\.label),
                       ["Media Library", "Playlist", "Visualization", "Browser", "Now Playing", "Video"])
        XCTAssertEqual(scene.strip.tabs.map(\.isInStrip), [true, true, true, true, true, false])
        XCTAssertEqual(scene.strip.tabs.first(where: \.isActive)?.label, "Media Library")
    }

    func testMediaLibraryAndPlaylistAreTheHostSurfacesAndAWidgetTabIsNamedByItsID() throws {
        let scene = try makeScene()

        XCTAssertEqual(scene.strip.tab(for: .library)?.label, "Media Library")
        XCTAssertEqual(scene.strip.tab(for: .playlist)?.label, "Playlist")
        XCTAssertNil(scene.strip.tab(for: .video), "only the two surfaces the host lists itself")
        let widget = try XCTUnwrap(scene.strip.tab(named: "Now Playing"))
        XCTAssertEqual(widget.identity, .widget("centro.widgets.nowplaying"))
        XCTAssertEqual(widget.flagKey, "centro.widgets.nowplaying")
        XCTAssertNil(widget.kind)
    }

    /// The player's drawer has a `widget.loader` bucket of its own, and Venus Alpha declares it
    /// first: the strip reads its widget tabs from the bucket beside its buttons, or they are no tabs.
    func testWidgetTabsAreNamedFromTheStripsOwnBucketNotTheDrawers() throws {
        let scene = try makeScene(drawerBucket: true)
        let first = try XCTUnwrap(scene.loaded.runtime.graph.objects(xmlID: "widget.loader").first)
        XCTAssertEqual(first.children.first?.xmlID, "widget.drawer", "the drawer's bucket comes first")

        XCTAssertEqual(scene.strip.tab(named: "Now Playing")?.identity, .widget("centro.widgets.nowplaying"))
    }

    /// Engine two names the browser tab Web Reader and spells its flags `cpro2.…`. Which engine
    /// built the strip is read from where its `CproTabs.maki` lives, which is known before any script
    /// runs — a key the engine writes on its first tab switch left a fresh cPro2 skin read as engine
    /// one, its Web Reader no tab and its closes flags the engine never read.
    func testEngineTwoIsReadFromTheStripsScriptPath() throws {
        let scene = try makeScene(engine: "_v2")
        let webReader = try XCTUnwrap(scene.strip.tab(named: "Web Reader"))
        XCTAssertEqual(webReader.identity, .engine(4))

        scene.strip.close(webReader)
        ClassicProTabStrip.prepareFlags(in: scene.loaded)

        XCTAssertTrue(scene.isFlagged("4"))
        XCTAssertEqual(scene.loaded.configuration.integer(section: "@public", key: "Cpro.One.TabAutoClose.4",
                                                          default: 0), 0, "nothing in engine one's spelling")
    }

    // MARK: - Closing

    /// The engine removes a tab only as it is switched away from, so an inactive tab is selected and
    /// then left, and the selection ends where it was.
    func testClosingAnInactiveTabSwitchesToItAndBack() throws {
        let scene = try makeScene()
        let video = try XCTUnwrap(scene.strip.tab(named: "Video"))

        scene.strip.close(video)

        XCTAssertEqual(scene.switches, ["Video", "Media Library"])
        XCTAssertEqual(scene.flaggedAtSwitch, [false, true],
                       "only the switch away from Video sees a flag, and it is Video's")
        XCTAssertFalse(try XCTUnwrap(scene.strip.tab(named: "Video")).isInStrip)
        XCTAssertEqual(scene.strip.tabs.first(where: \.isActive)?.label, "Media Library")
        XCTAssertFalse(scene.isFlagged("2"), "and gone once it has")
        XCTAssertEqual(scene.closedRecord, "2")
    }

    func testClosingTheActiveTabSelectsTheTabBeforeIt() throws {
        let scene = try makeScene()
        let browser = try XCTUnwrap(scene.strip.tab(named: "Browser"))
        scene.strip.open(browser)
        scene.switches.removeAll()

        scene.strip.close(try XCTUnwrap(scene.strip.tab(named: "Browser")))

        XCTAssertEqual(scene.switches, ["Visualization"])
        XCTAssertEqual(scene.strip.tabs.first(where: \.isActive)?.label, "Visualization")
        XCTAssertFalse(try XCTUnwrap(scene.strip.tab(named: "Browser")).isInStrip)
        XCTAssertFalse(scene.isFlagged("4"))
    }

    func testTheFirstTabClosesTowardsTheTabAfterIt() throws {
        let scene = try makeScene()

        scene.strip.close(try XCTUnwrap(scene.strip.tab(for: .library)))

        XCTAssertEqual(scene.switches, ["Playlist"])
        XCTAssertEqual(scene.strip.tabs.first(where: \.isActive)?.label, "Playlist")
    }

    func testTheLastOpenTabCannotClose() throws {
        let scene = try makeScene()
        for label in ["Playlist", "Video", "Visualization", "Browser", "Now Playing"] {
            scene.strip.close(try XCTUnwrap(scene.strip.tab(named: label)))
        }
        scene.switches.removeAll()
        let last = try XCTUnwrap(scene.strip.tab(for: .library))

        XCTAssertFalse(ClassicProTabStrip.canClose(last, among: scene.strip.tabs))
        scene.strip.close(last)

        XCTAssertTrue(scene.switches.isEmpty)
        XCTAssertTrue(try XCTUnwrap(scene.strip.tab(for: .library)).isInStrip)
    }

    // MARK: - Opening

    func testOpeningAClosedTabPutsItBackSelectedAndForgetsItWasClosed() throws {
        let scene = try makeScene()
        scene.strip.close(try XCTUnwrap(scene.strip.tab(named: "Now Playing")))
        XCTAssertEqual(scene.closedRecord, "centro.widgets.nowplaying")

        scene.strip.open(try XCTUnwrap(scene.strip.tab(named: "Now Playing")))

        let tab = try XCTUnwrap(scene.strip.tab(named: "Now Playing"))
        XCTAssertTrue(tab.isInStrip)
        XCTAssertTrue(tab.isActive)
        XCTAssertEqual(scene.closedRecord, "")
    }

    // MARK: - Across a reload

    /// Before the scripts start, the tabs closed at the last unload are flagged so the engine builds
    /// them hidden; once it has, every flag goes, so the engine reopening one later does not lose it
    /// again at the next click.
    func testTheClosedTabsAreFlaggedForTheNextLoadAndClearedAfterIt() throws {
        let scene = try makeScene()
        scene.strip.close(try XCTUnwrap(scene.strip.tab(named: "Video")))
        scene.strip.close(try XCTUnwrap(scene.strip.tab(named: "Now Playing")))

        ClassicProTabStrip.prepareFlags(in: scene.loaded)
        XCTAssertTrue(scene.isFlagged("2"))
        XCTAssertTrue(scene.isFlagged("centro.widgets.nowplaying"))
        XCTAssertFalse(scene.isFlagged("4"))

        ClassicProTabStrip.clearFlags(in: scene.loaded.configuration)
        XCTAssertFalse(scene.isFlagged("2"))
        XCTAssertFalse(scene.isFlagged("centro.widgets.nowplaying"))
    }

    func testRestoringTheDefaultLayoutForgetsTheClosedTabs() throws {
        let scene = try makeScene()
        scene.strip.close(try XCTUnwrap(scene.strip.tab(named: "Video")))

        ClassicProTabStrip.resetLayout(in: scene.loaded.configuration)
        ClassicProTabStrip.prepareFlags(in: scene.loaded)

        XCTAssertEqual(scene.closedRecord, "")
        XCTAssertFalse(scene.isFlagged("2"))
    }

    // MARK: - The tab menu

    func testScriptPopupsNoLongerOfferAutoCloseTab() throws {
        let scene = try makeScene()
        var shown: [String] = []
        scene.scripts.popupPresenter = { items, _ in shown = items.map(\.title); return 0 }

        _ = ClassicProTabStrip.attach(to: scene.scripts)
        _ = scene.scripts.presentPopup([popupItem("Auto Close Tab"), popupItem("Show Status Bar")], at: nil)

        XCTAssertEqual(shown, ["Show Status Bar"])
    }

    // MARK: -

    private final class Scene {
        let loaded: WinampModernLoadedSkin
        let scripts: WinampModernScriptRuntime
        /// The engine's spelling of its flags.
        let flagPrefix: String
        var strip: ClassicProTabStrip!
        var switches: [String] = []
        /// Whether the outgoing tab's flag was set at each switch.
        var flaggedAtSwitch: [Bool] = []

        init(loaded: WinampModernLoadedSkin, scripts: WinampModernScriptRuntime, flagPrefix: String) {
            self.loaded = loaded
            self.scripts = scripts
            self.flagPrefix = flagPrefix
        }

        func group(_ id: String) -> WasabiObject { loaded.runtime.graph.objects(xmlID: id)[0] }

        func isFlagged(_ key: String) -> Bool {
            loaded.configuration.integer(section: "@public", key: "\(flagPrefix).One.TabAutoClose.\(key)",
                                          default: 0) == 1
        }

        var closedRecord: String { loaded.configuration.string(section: "@nullplayer.tabs", key: "closed") }

        /// The engine's `switch_to_tab`: the outgoing tab leaves the strip if its flag is set, and the
        /// incoming one is put back at the end if it was out, then selected.
        func engineSwitch(to tab: ClassicProTabStrip.Tab) {
            switches.append(tab.label)
            let groups = group("cprotabs.buttons").children
            func button(_ group: WasabiObject) -> WasabiObject { group.children[0] }
            let outgoing = groups.first { button($0).attributes["activated"] == "1" }
            let incoming = groups.first { button($0).attributes["tooltip"] == tab.label }!
            if let outgoing, outgoing !== incoming {
                let key = strip.tabs.first { $0.label == button(outgoing).attributes["tooltip"] }!.flagKey
                flaggedAtSwitch.append(isFlagged(key))
                if isFlagged(key) { _ = outgoing.setAttribute("visible", value: "0") }
            }
            if incoming.attributes["visible"] == "0" {
                let end = groups.compactMap { Int($0.attributes["x"] ?? "") }.max() ?? 0
                _ = incoming.setAttribute("x", value: String(end + 50))
                _ = incoming.setAttribute("visible", value: "1")
            }
            for group in groups {
                _ = button(group).setAttribute("activated", value: group === incoming ? "1" : "0")
            }
        }
    }

    /// cPro's strip as `engine` (`_v1` or `_v2`) builds it: the SUI, `Cpro.tabs` inside it, one group per tab in
    /// `cprotabs.buttons` with its `cpro.tab.button`, the plugin page among them, and the component
    /// bucket the widget tabs are named from. Media Library starts selected.
    /// `drawerBucket` puts the player drawer's own `widget.loader` ahead of the strip's.
    private func makeScene(engine: String = "_v1", drawerBucket: Bool = false) throws -> Scene {
        func tab(_ id: String, _ label: String, x: Int, active: Bool = false) -> String {
            #"<group id="\#(id)" x="\#(x)" y="0" w="50" h="25"><button id="cpro.tab.button" tooltip="\#(label)" activated="\#(active ? 1 : 0)"/></group>"#
        }
        // Only the path is read; the script never runs.
        let script = "engine/xui/CentroSUI/\(engine)/CproTabs/CproTabs.maki"
        let loaded = try makeSkin(files: [script: Data()], xml: """
        <WasabiXML>
          <groupdef id="cprotabs.buttons">
            \(tab("tab.ml", "Media Library", x: 0, active: true))
            \(tab("tab.pl", "Playlist", x: 50))
            \(tab("tab.video", "Video", x: 100))
            \(tab("tab.vis", "Visualization", x: 150))
            \(tab("tab.browser", engine == "_v2" ? "Web Reader" : "Browser", x: 200))
            \(tab("tab.np", "Now Playing", x: 250))
            \(tab("tab.plugin", "Plugin", x: 300))
          </groupdef>
          <groupdef id="cprotabs.xui" xuitag="Cpro:Tabs">
            <componentbucket id="widget.loader" x="0" y="0" w="20" h="20" visible="0">
              <group id="widget.np" name="Now Playing;NP" userdata="centro.widgets.nowplaying;1"/>
            </componentbucket>
            <group id="cprotabs.buttons" x="3" y="0" w="-3" h="25" relatw="1"/>
            <script file="\(script)"/>
          </groupdef>
          <groupdef id="centro.sui" xuitag="Centro:SUI">
            <Cpro:Tabs id="Cpro.tabs" x="0" y="0" w="400" h="25"/>
          </groupdef>
          <container id="main">
            <layout id="normal" w="400" h="200">
              \(drawerBucket ? #"<componentbucket id="widget.loader" x="0" y="0" w="20" h="20" visible="0"><group id="widget.drawer" name="Drawer Widget;DW" userdata="centro.widgets.drawer.one;1"/></componentbucket>"# : "")
              <Centro:SUI id="sui" x="0" y="0" w="400" h="200"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { scripts.teardown() }
        let scene = Scene(loaded: loaded, scripts: scripts, flagPrefix: engine == "_v2" ? "cpro2" : "Cpro")
        scene.strip = try XCTUnwrap(ClassicProTabStrip(runtime: scripts) { [unowned scene] in
            scene.engineSwitch(to: $0)
        })
        return scene
    }

    private func popupItem(_ title: String) -> WinampModernPopupMenuItem {
        WinampModernPopupMenuItem(title: title, commandID: 1, checked: false, disabled: false,
                                  isSeparator: false, children: [])
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

    private func makeSkin(files: [String: Data], xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB350Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B350-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files.merging(["skin.xml": Data(xml.utf8)], uniquingKeysWith: { $1 }) {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
