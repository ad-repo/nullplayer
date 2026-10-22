import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B178–B181 — published skins the loader refused over one reference it could degrade instead.
/// Each still loads, and each degraded reference is a warning finding.
final class WinampModernLoaderGapTests: XCTestCase {

    /// B178: `<groupdef id="wasabi.titlebox" inherit_group="wasabi.titlebox">` extends the system
    /// group it replaces (Official_Coldplay), and a tab page holding a second tab sheet is nesting
    /// (Graviton). A group whose body contains itself still fails.
    func testASystemGroupOverrideExtendsTheDefinitionItReplaces() throws {
        let loaded = try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
              <groupdef id="wasabi.titlebox" inherit_group="wasabi.titlebox"><layer id="extra"/></groupdef>
              <groupdef id="inner.page"><layer id="leaf"/></groupdef>
              <groupdef id="outer.page"><Wasabi:TabSheet children="inner.page"/></groupdef>
              <container id="main" name="Main Window">
                <layout id="normal" w="20" h="10">
                  <Wasabi:TitleBox title="t"/>
                  <Wasabi:TabSheet children="outer.page"/>
                </layout>
              </container>
            </WasabiXML>
            """.utf8),
        ])
        let ids = Set(loaded.runtime.graph.allObjectsUnordered.compactMap(\.xmlID))
        XCTAssertTrue(ids.isSuperset(of: ["extra", "leaf"]), "\(ids)")

        XCTAssertThrowsError(try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
              <groupdef id="loop"><Wasabi:TabSheet children="loop"/></groupdef>
              <container id="main"><layout id="normal" w="20" h="10"><group id="loop"/></layout></container>
            </WasabiXML>
            """.utf8),
        ])) { error in
            XCTAssertEqual((error as? WalFailure)?.diagnostics.first?.code, .groupInheritanceCycle)
        }
    }

    /// B214: an `embed_xui` wrapper passes `content=` and `children=` on to the TitleBox or TabSheet it
    /// embeds, which builds its body (1010 Fullscreen's `Deimos:ConfigPage` / `Deimos:ConfigSheet`).
    func testAnEmbeddedTitleBoxAndTabSheetBuildTheBodyTheirWrapperNames() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <groupdef id="page" xuitag="X:Page" embed_xui="box"><Wasabi:TitleBox id="box"/></groupdef>
          <groupdef id="sheet" xuitag="X:Sheet" embed_xui="tabs"><Wasabi:TabSheet id="tabs"/></groupdef>
          <groupdef id="body"><layer id="page.leaf"/></groupdef>
          <groupdef id="tab.one"><layer id="tab.leaf"/></groupdef>
          <container id="main"><layout id="normal" w="20" h="10">
            <X:Page content="body"/><X:Sheet children="tab.one"/>
          </layout></container>
        </WasabiXML>
        """)
        let ids = Set(loaded.runtime.graph.allObjectsUnordered.compactMap(\.xmlID))
        XCTAssertTrue(ids.isSuperset(of: ["page.leaf", "tab.leaf"]), "\(ids)")
    }

    /// A skin's `<groupdef id="wasabi.tabsheet">` restyles Winamp's tab sheet, which still builds the
    /// pages it is given (Mac OS X Panther, Anunaki); it does not replace the widget.
    func testARestyledTabSheetStillBuildsItsPages() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <groupdef id="wasabi.tabsheet"><layer id="restyle"/></groupdef>
          <groupdef id="tab.one"><layer id="tab.leaf"/></groupdef>
          <container id="main"><layout id="normal" w="20" h="10">
            <Wasabi:TabSheet children="tab.one"/>
          </layout></container>
        </WasabiXML>
        """)
        let ids = Set(loaded.runtime.graph.allObjectsUnordered.compactMap(\.xmlID))
        XCTAssertTrue(ids.isSuperset(of: ["restyle", "tab.leaf"]), "\(ids)")
        // The restyle is the content background, below the strip the tabs are drawn in.
        let restyle = try XCTUnwrap(loaded.runtime.graph.allObjectsUnordered.first { $0.xmlID == "restyle" })
        XCTAssertEqual(restyle.parent?.attributes["y"], String(Int(WasabiTabSheet.stripHeight)))
    }

    /// B179: the installed ClassicPro engine lacks `miniexes.xml`, which three cPro skins include.
    /// A missing include inside a mounted engine is skipped; an uninstalled engine still fails (B92).
    func testAMissingIncludeInsideAnInstalledEngineIsSkipped() throws {
        let engine = try WalMemoryResourceProvider(resources: ["load.xml": Data("<WasabiXML/>".utf8)])
        let loaded = try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
              <include file="@COLORTHEMESPATH@../../Plugins/classicPro/engine/load.xml"/>
              <include file="@COLORTHEMESPATH@../../Plugins/classicPro/engine/miniexes.xml"/>
            \(Self.container)
            </WasabiXML>
            """.utf8),
        ], mounts: [WinampModernAdditionalMount(logicalRoot: ClassicProEngineStore.logicalMountRoot,
                                                provider: engine)])
        XCTAssertTrue(loaded.runtime.diagnostics.contains {
            $0.severity == .warning && $0.message.contains("miniexes.xml")
        })
    }

    /// B180: VANDREAD points a bitmap at the author's `c:/…`, Slim names a script with a trailing
    /// space. The host path is still refused — it degrades to a missing bitmap — and the name is trimmed.
    func testAHostPathBitmapDegradesAndAFileNameIsTrimmed() throws {
        let loaded = try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
              <elements><bitmap id="pic" file="c:/vandread/pic1.jpg"/></elements>
            \(Self.container(script: "scripts/time.maki "))
            </WasabiXML>
            """.utf8),
            "scripts/time.maki": Data([0x46, 0x47]),
        ])
        XCTAssertNil(loaded.runtime.resources.definition(identifier: "pic")?.logicalFile)
        XCTAssertTrue(loaded.runtime.diagnostics.contains { $0.severity == .warning && $0.message.contains("c:/vandread") })
        XCTAssertEqual(loaded.runtime.graph.allObjectsUnordered.flatMap(\.scriptBindings).map(\.logicalPath),
                       ["/Skins/Gap/scripts/time.maki"])
    }

    /// B181: Braun CC 50 draws an easter egg from `../Big Bento/`, Nokia 5800 binds one script from
    /// it; Big Bento is Winamp's own and we cannot ship it. Both degrade with a warning naming it.
    /// An XML include from an absent skin still fails the load (B92's test).
    func testABitmapOrScriptFromAnAbsentSkinDegrades() throws {
        let loaded = try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
              <elements><bitmap id="egg" file="../Big Bento/about/nibbles/llama.png"/></elements>
            \(Self.container(script: "../Big Bento/scripts/mute.maki"))
            </WasabiXML>
            """.utf8),
        ])
        XCTAssertNil(loaded.runtime.resources.definition(identifier: "egg")?.logicalFile)
        let named = loaded.runtime.diagnostics.filter { $0.code == .missingRequiredMount }
        XCTAssertFalse(named.isEmpty)
        XCTAssertTrue(named.allSatisfy { $0.severity == .warning && $0.message.contains("Big Bento") })
        XCTAssertTrue(loaded.runtime.graph.allObjectsUnordered.allSatisfy(\.scriptBindings.isEmpty))
    }

    // MARK: - Fixtures

    private static let container = container(script: nil)

    private static func container(script: String?) -> String {
        """
        <container id="main" name="Main Window">
          <layout id="normal" w="20" h="10">
            <layer id="body" x="0" y="0" w="20" h="10"/>
            \(script.map { "<script file=\"\($0)\"/>" } ?? "")
          </layout>
        </container>
        """
    }

    private func load(files: [String: Data], mounts: [WinampModernAdditionalMount] = []) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernLoaderGapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Gap.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (entry, payload) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: entry, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url, additionalMounts: mounts)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
