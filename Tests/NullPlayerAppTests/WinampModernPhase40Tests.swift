import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 40 (backlog B6) — `default_visible="1"` on an auxiliary container.
///
/// Winamp opens these windows *with* the skin. Defix's configurator declares it — `<container
/// id="Config" name="Skin Settings" default_visible="1">` — and here it was only ever *reachable*,
/// from the Skin Windows menu or its own `CONF` button. Every auxiliary window was `orderOut` at
/// setup and placed on first show, whatever the skin asked for.
///
/// Two halves are tested here: the attribute (parsed in `WinampModernContainerTopology`, where every
/// other container fact is decided) and the precedence that keeps a settings window from reopening at
/// every launch — the declaration is a *default*, and a window the user has closed stays closed. The
/// windows themselves are AppKit, which is the boundary every phase in this subsystem has drawn.
final class WinampModernPhase40Tests: XCTestCase {

    // MARK: - The attribute

    /// Defix's container list verbatim, which is also the fixture Phase 27.7 used for the window
    /// menu — the same markup answers a different question here.
    func testDefaultVisibleIsReadFromTheContainer() throws {
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
          <container id="SUI">
            <layout id="normal" w="800" h="600"/>
          </container>
        </WasabiXML>
        """)
        let byID = Dictionary(uniqueKeysWithValues:
            WinampModernContainerTopology.analyze(graph: loaded.runtime.graph).map { ($0.id, $0) })

        XCTAssertEqual(byID["Config"]?.opensByDefault, true, "the configurator opens with the skin")
        XCTAssertEqual(byID["SPEAKER1"]?.opensByDefault, false, "`0` is the skin saying no")
        XCTAssertEqual(byID["SUI"]?.opensByDefault, false,
                       "a container that declares nothing stays closed, as in Winamp")
        XCTAssertEqual(byID["main"]?.opensByDefault, true,
                       "the player is on screen whatever it declares")
    }

    /// Wasabi's boolean spelling is the same everywhere — `visible`, `autoopen`, and this — so a skin
    /// writing `true` or `yes` means the same thing as `1`, and anything unrecognised is not a yes.
    func testDefaultVisibleAcceptsWasabisBooleanSpellings() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="100" h="100"/></container>
          <container id="yes" default_visible="Yes"><layout id="normal" w="100" h="100"/></container>
          <container id="true" default_visible="TRUE"><layout id="normal" w="100" h="100"/></container>
          <container id="junk" default_visible="maybe"><layout id="normal" w="100" h="100"/></container>
        </WasabiXML>
        """)
        let byID = Dictionary(uniqueKeysWithValues:
            WinampModernContainerTopology.analyze(graph: loaded.runtime.graph).map { ($0.id, $0) })

        XCTAssertEqual(byID["yes"]?.opensByDefault, true)
        XCTAssertEqual(byID["true"]?.opensByDefault, true)
        XCTAssertEqual(byID["junk"]?.opensByDefault, false)
    }

    // MARK: - The precedence

    /// The reason honouring the attribute is safe: it is a *default*, not a command. A settings
    /// window that reopened at every launch however often you closed it would be worse than one that
    /// never opened at all, which is exactly why this was left unimplemented for eight phases.
    func testWhatTheUserLastDecidedWinsOverWhatTheSkinDeclares() {
        typealias Controller = WinampModernMainWindowController
        // Never touched: the skin decides.
        XCTAssertTrue(Controller.opensAtLoad(opensByDefault: true, remembered: nil))
        XCTAssertFalse(Controller.opensAtLoad(opensByDefault: false, remembered: nil))
        // Closed by the user: stays closed, even though the skin asks for it every load.
        XCTAssertFalse(Controller.opensAtLoad(opensByDefault: true, remembered: false))
        // Opened by the user: comes back, even though the skin ships it closed.
        XCTAssertTrue(Controller.opensAtLoad(opensByDefault: false, remembered: true))
    }

    /// And where that decision lives: the *skin's own* namespaced configuration, so two skins that
    /// both declare a `Config` window do not share one answer, and "never said" is distinguishable
    /// from "said no".
    func testTheRememberedStateIsScopedToTheSkin() throws {
        let defaults = UserDefaults(suiteName: "WinampModernPhase40Tests-\(UUID().uuidString)")!
        let section = "@nullplayer.windows"
        let defix = WinampModernConfiguration(namespace: "Defix", defaults: defaults)
        let mmd3 = WinampModernConfiguration(namespace: "mmd3", defaults: defaults)

        XCTAssertEqual(defix.integer(section: section, key: "Config", default: -1), -1,
                       "never said is not the same as said no")
        defix.setInteger(0, section: section, key: "Config")

        XCTAssertEqual(defix.integer(section: section, key: "Config", default: -1), 0)
        XCTAssertEqual(mmd3.integer(section: section, key: "Config", default: -1), -1,
                       "another skin's window of the same name is untouched")
    }

    // MARK: - What is not opened, and why

    /// Host-managed transient windows remain suppressed, while a browser-only window is now useful
    /// and may honor the skin's default. Suppression never affects explicit open routes.
    func testNotifierIsSuppressedButAWorkingBrowserWindowMayOpenWithTheSkin() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="275" h="116"/></container>
          <container id="notifier" name="Notifier" default_visible="1" nomenu="1">
            <layout id="normal" w="300" h="80"/>
          </container>
          <container id="Warp Browser" name="Rika HOME" default_visible="1">
            <layout id="normal" w="860" h="704">
              <browser id="browser" url="http://example.invalid/home.htm" x="0" y="0" w="800" h="600"/>
            </layout>
          </container>
          <container id="Pledit" name="Playlist Editor" default_visible="1">
            <layout id="normal" w="406" h="355"/>
          </container>
        </WasabiXML>
        """)
        let byID = Dictionary(uniqueKeysWithValues:
            WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
                .map { ($0.id, $0) })
        func suppression(_ id: String) -> WinampModernDefaultVisibilitySuppression? {
            guard let info = byID[id] else { return nil }
            return WinampModernContainerTopology.defaultVisibilitySuppression(of: info)
        }

        XCTAssertEqual(suppression("notifier"), .hostManagedTransient)
        XCTAssertNil(suppression("Warp Browser"),
                     "a working embedded browser no longer suppresses its declared window")
        XCTAssertNil(suppression("Pledit"), "an ordinary window the skin ships open")
        XCTAssertNil(suppression("main"), "the player is not a suppression case at all")
        XCTAssertFalse(WinampModernDefaultVisibilitySuppression.hostManagedTransient.reason.isEmpty)
    }

    // MARK: - Where the window opens

    /// A window that opens with the skin has to open *where the skin puts it*, or the arrangement is
    /// not the skin's. Winamp Modern says `default_x="354" default_y="165"` for its album art, beside
    /// and below a player at the origin — and the player here is wherever the user left it.
    func testTheSkinsOwnArrangementIsMeasuredFromThePlayersTopLeft() {
        let player = NSRect(x: 100, y: 800, width: 354, height: 164)
        let size = NSSize(width: 275, height: 116)

        let beside = WinampModernMainWindowController.arrangedOrigin(
            playerFrame: player, size: size, offset: CGPoint(x: 354, y: 0), scale: 1)
        XCTAssertEqual(beside.x, 454, "354 skin pixels right of the player's left edge")
        XCTAssertEqual(beside.y, player.maxY - size.height, "level with its top edge")

        // Skin y runs downward; AppKit's runs up.
        let below = WinampModernMainWindowController.arrangedOrigin(
            playerFrame: player, size: size, offset: CGPoint(x: 354, y: 165), scale: 1)
        XCTAssertEqual(below.y, player.maxY - 165 - size.height)

        // And the offset is in *skin* pixels, so UI Size moves it with everything else.
        let doubled = WinampModernMainWindowController.arrangedOrigin(
            playerFrame: player, size: size, offset: CGPoint(x: 354, y: 165), scale: 2)
        XCTAssertEqual(doubled.x, 100 + 708)
        XCTAssertEqual(doubled.y, player.maxY - 330 - size.height)
    }

    /// The offset is relative because the corpus is: every skin that positions a window declares
    /// `default_x="0" default_y="0"` on its player and measures the rest from there.
    func testTheDeclaredOriginIsReadPerAxis() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main" default_x="0" default_y="0"><layout id="normal" w="275" h="116"/></container>
          <container id="EQ" default_y="348"><layout id="normal" w="275" h="116"/></container>
          <container id="silent"><layout id="normal" w="275" h="116"/></container>
        </WasabiXML>
        """)
        let byID = Dictionary(uniqueKeysWithValues:
            WinampModernContainerTopology.analyze(graph: loaded.runtime.graph).map { ($0.id, $0) })

        XCTAssertEqual(byID["main"]?.defaultOrigin, .zero)
        XCTAssertEqual(byID["EQ"]?.defaultOrigin, CGPoint(x: 0, y: 348),
                       "an axis the skin leaves out is 0, as in Winamp")
        XCTAssertNil(byID["silent"]?.defaultOrigin,
                     "a container that declares neither is stacked, not placed")
    }

    // MARK: - Fixture

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase40Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase40-\(UUID().uuidString).wal")
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
