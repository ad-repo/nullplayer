import XCTest
@testable import NullPlayer

/// Phase 14 — the `wasabi.*` standard-library shells, re-audited.
///
/// R2 was carried from Phase 7 as "`wasabi.*` widgets render empty because the artwork lives inside
/// Winamp". Measured across the four reference skins, that is not the shape of what is left: the skins
/// ship the standard artwork themselves, cPro-Bento references no `wasabi.*` group at all, and Winamp
/// Modern defines its own. What was missing was the standard library's *structure* for two ids —
/// `wasabi.tooltip` (off the curated list entirely) and `wasabi.titlebar` (a shell with no body, and
/// no `Wasabi:TitleBar` tag, so every CornerAmp window came up with a nameless title bar).
///
/// These tests pin the two additions *and* the boundaries around them: a skin's own definition and its
/// own `xuitag=` still win, and no other shell grew a body.
final class WinampModernPhase14Tests: XCTestCase {

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Synthetic Song"
        var trackInfo = "Synthetic Artist"
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

    private func initialize(xml: String) throws -> WasabiSkinRuntime {
        let provider = try WalMemoryResourceProvider(resources: ["skin.xml": Data(xml.utf8)])
        let vfs = try WalVirtualFileSystem(skinName: "Synthetic", skin: provider)
        let document = try WalXMLDocumentLoader(vfs: vfs).load(entryPath: "/Skins/Synthetic/skin.xml")
        return try WasabiSkinInitializer(vfs: vfs).initialize(document: document)
    }

    private func titleText(in runtime: WasabiSkinRuntime) -> [WasabiObject] {
        runtime.graph.objects(xmlID: "window.titlebar.title")
    }

    // MARK: - 14.1 `wasabi.tooltip`

    func testTooltipBaseIsOnTheCuratedList() throws {
        // mmd3's `xml/tooltip.xml` instantiates `<group id="wasabi.tooltip">`. Off the list it was a
        // genuinely unknown base: warn-and-drop.
        let runtime = try initialize(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal">
              <group id="wasabi.tooltip" w="300" h="25"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertTrue(runtime.diagnostics.filter { $0.code == .missingGroupDefinition }.isEmpty)
    }

    // MARK: - 14.2 The `Wasabi:TitleBar` shell

    func testTitleBarShellDrawsTheContainerName() throws {
        let runtime = try initialize(xml: """
        <WasabiXML>
          <container id="Pledit" name="Playlist Editor">
            <layout id="normal" w="320" h="200">
              <Wasabi:TitleBar id="wasabi.titlebar" x="22" y="2" w="-42" h="11" relatw="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let titles = titleText(in: runtime)
        XCTAssertEqual(titles.count, 1, "the shell should contribute exactly one title text")
        // `:componentname` is the frame-supplied placeholder; unresolved it would draw the literal.
        XCTAssertEqual(WasabiTextMetrics.content(of: try XCTUnwrap(titles.first), host: Host()),
                       "Playlist Editor")
    }

    func testTitleBarShellIsInertWithoutAName() throws {
        // No `componentname=` and no container `name=`: the placeholder resolves to nothing rather
        // than drawing ":componentname" across the title bar.
        let runtime = try initialize(xml: """
        <WasabiXML>
          <container id="Pledit">
            <layout id="normal" w="320" h="200">
              <Wasabi:TitleBar id="wasabi.titlebar" x="0" y="0" w="0" h="11" relatw="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertEqual(WasabiTextMetrics.content(of: try XCTUnwrap(titleText(in: runtime).first),
                                                 host: Host()), "")
    }

    func testSkinDefinitionWinsOverTheTitleBarShell() throws {
        // A skin that ships its own `wasabi.titlebar` gets its own body and nothing of ours.
        let runtime = try initialize(xml: """
        <WasabiXML>
          <groupdef id="wasabi.titlebar">
            <text id="skin.own.title" x="0" y="0" w="0" h="0" relatw="1" relath="1" text="Mine"/>
          </groupdef>
          <container id="Pledit" name="Playlist Editor">
            <layout id="normal" w="320" h="200">
              <group id="wasabi.titlebar" x="0" y="0" w="0" h="11" relatw="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertTrue(titleText(in: runtime).isEmpty)
        XCTAssertEqual(runtime.graph.objects(xmlID: "skin.own.title").count, 1)
    }

    func testSkinXUITagWinsOverTheConventionalAlias() throws {
        // Winamp Modern declares `xuitag="Wasabi:TitleBar"` on its own groupdef. The alias only fills
        // an *unclaimed* tag, so the tag must still reach the skin's definition.
        let runtime = try initialize(xml: """
        <WasabiXML>
          <groupdef id="skin.titlebar" xuitag="Wasabi:TitleBar">
            <text id="skin.own.title" x="0" y="0" w="0" h="0" relatw="1" relath="1" text="Mine"/>
          </groupdef>
          <container id="Pledit" name="Playlist Editor">
            <layout id="normal" w="320" h="200">
              <Wasabi:TitleBar id="wasabi.titlebar" x="0" y="0" w="0" h="11" relatw="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertTrue(titleText(in: runtime).isEmpty)
        XCTAssertEqual(runtime.graph.objects(xmlID: "skin.own.title").count, 1)
    }

    func testEveryOtherShellStaysIdentifierOnly() throws {
        // The shells are identifier-only by design — one with a body would put artwork we invented
        // into every skin that inherits it. `wasabi.titlebar` is the single measured exception.
        for identifier in WasabiSkinInitializer.wasabiStandardLibraryGroups
        where identifier != "wasabi.titlebar" {
            let runtime = try initialize(xml: """
            <WasabiXML>
              <container id="main">
                <layout id="normal" w="100" h="100">
                  <group id="\(identifier)" x="0" y="0" w="10" h="10"/>
                </layout>
              </container>
            </WasabiXML>
            """)
            let instances = runtime.graph.objects(xmlID: identifier)
            XCTAssertEqual(instances.first?.children.count, 0,
                           "'\(identifier)' should contribute no children of its own")
        }
    }
}
