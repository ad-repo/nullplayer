import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 13 — playlist, EQ, and library surfaces for `.wal` skins.
///
/// Step 13.0 first: a window dragged below its layout minimum used to *scramble* rather than cramp,
/// because a child whose parent is shorter than the child's own margins resolves to a negative box
/// and `WasabiRect.standardized` painted it flipped across its origin, on top of its siblings.
final class WinampModernPhase13Tests: XCTestCase {

    // MARK: - 13.0 Negative-size culling

    /// A negative box is dropped instead of being flipped over its siblings.
    func testNegativelySizedObjectIsCulledRatherThanFlipped() throws {
        let renderer = try makeRenderer(layout: """
        <layer id="short" x="0" y="100" w="0" h="6" relatw="1"/>
        <group id="host" x="0" y="100" w="0" h="6" relatw="1">
          <layer id="taller.than.parent" x="2" y="2" w="-4" h="-15" relatw="1" relath="1"/>
        </group>
        """)
        let ids = renderer.sceneNodes().compactMap(\.object.xmlID)
        XCTAssertTrue(ids.contains("host"), "the parent itself is a real 6px-tall box")
        XCTAssertFalse(ids.contains("taller.than.parent"),
                       "a child needing 15px more than its parent has must draw nothing")
        for node in renderer.sceneNodes() {
            XCTAssertGreaterThanOrEqual(node.frame.width, 0)
            XCTAssertGreaterThanOrEqual(node.frame.height, 0)
        }
    }

    /// Culling takes the subtree with it: descendants resolve against a box that does not exist.
    func testCullingANegativeBoxAlsoDropsItsChildren() throws {
        let renderer = try makeRenderer(layout: """
        <group id="collapsed" x="0" y="0" w="-10" h="20">
          <layer id="child.of.collapsed" x="0" y="0" w="8" h="8"/>
          <group id="deep">
            <layer id="grandchild" x="0" y="0" w="8" h="8"/>
          </group>
        </group>
        """)
        let ids = Set(renderer.sceneNodes().compactMap(\.object.xmlID))
        XCTAssertFalse(ids.contains("collapsed"))
        XCTAssertFalse(ids.contains("child.of.collapsed"))
        XCTAssertFalse(ids.contains("grandchild"))
    }

    /// Zero-sized objects keep their existing pass-through behaviour — only *negative* boxes are
    /// bogus. Skins park real content in 0×0 groups that size themselves from their children.
    func testZeroSizedObjectsAreStillWalked() throws {
        let renderer = try makeRenderer(layout: """
        <group id="zero" x="0" y="0" w="0" h="0">
          <layer id="child.of.zero" x="0" y="0" w="10" h="10"/>
        </group>
        """)
        let ids = Set(renderer.sceneNodes().compactMap(\.object.xmlID))
        XCTAssertTrue(ids.contains("zero"))
        XCTAssertTrue(ids.contains("child.of.zero"))
    }

    /// The R1 case end to end. cPro-Bento's declared minimum is *itself* degenerate: at 168px the
    /// SUI area (`h="-168" relath="1"`) is zero-tall, so its contents go negative. A shrunk window
    /// must cramp — every remaining node inside the canvas — never stack flipped boxes over the
    /// chrome. `resize` already clamps to the layout minimum, so this is the smallest real size.
    func testShrinkingToTheLayoutMinimumNeverPaintsOutsideTheCanvas() throws {
        let renderer = try makeRenderer(layout: """
        <layer id="header" x="0" y="0" w="0" h="80" relatw="1"/>
        <group id="body" x="0" y="80" w="0" h="-80" relatw="1" relath="1">
          <layer id="body.fill" x="2" y="2" w="-4" h="-4" relatw="1" relath="1"/>
        </group>
        """)
        XCTAssertTrue(Set(renderer.sceneNodes().compactMap(\.object.xmlID))
            .isSuperset(of: ["header", "body", "body.fill"]))

        let clamped = renderer.resize(to: CGSize(width: 10, height: 10))
        XCTAssertEqual(clamped, CGSize(width: 120, height: 80), "resize clamps to the layout minimum")
        let nodes = renderer.sceneNodes()
        let ids = Set(nodes.compactMap(\.object.xmlID))
        XCTAssertTrue(ids.contains("header"), "the header is still a valid 80px box")
        XCTAssertFalse(ids.contains("body.fill"), "4px of margin inside a zero-tall body is negative")
        let canvas = CGRect(origin: .zero, size: clamped)
        for node in nodes where !node.frame.isEmpty {
            XCTAssertTrue(canvas.intersects(node.frame),
                          "\(node.object.xmlID ?? node.object.typeName) escaped the canvas at \(node.frame)")
            XCTAssertGreaterThanOrEqual(node.frame.minY, 0, "a flipped box paints above the canvas")
        }
    }

    // MARK: - 13.0 Layout limits and restored-frame clamping

    /// The limits come from the layout the renderer is *showing*, not from a fixed constant.
    func testRendererExposesTheActiveLayoutLimits() throws {
        let renderer = try makeRenderer(layout: "<layer id=\"x\" x=\"0\" y=\"0\" w=\"4\" h=\"4\"/>")
        XCTAssertEqual(renderer.layoutMinimumSize, CGSize(width: 120, height: 80))
        XCTAssertEqual(renderer.layoutMaximumSize, CGSize(width: 16_384, height: 16_384),
                       "a layout with no maximum is bounded only by the renderer's own ceiling")
    }

    /// Each container carries its own minimum — an auxiliary playlist window is not bounded by the
    /// player's floor.
    func testContainersCarryTheirOwnMinimaAndMaxima() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" default_w="500" default_h="500" minimum_w="317" minimum_h="168"/>
          </container>
          <container id="Pledit" component="guid:{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}">
            <layout id="normal" default_w="381" default_h="260" minimum_w="240" minimum_h="60"
                    maximum_w="900"/>
          </container>
        </WasabiXML>
        """)
        let containers = WinampModernContainerTopology.analyze(graph: loaded.runtime.graph)
        let main = try XCTUnwrap(containers.first { $0.id == "main" })
        let playlist = try XCTUnwrap(containers.first { $0.id == "Pledit" })
        XCTAssertEqual(main.defaultSize, CGSize(width: 500, height: 500))
        XCTAssertEqual(main.minimumSize, CGSize(width: 317, height: 168))
        XCTAssertNil(main.maximumSize, "no maximum_* means freely resizable")
        XCTAssertEqual(playlist.minimumSize, CGSize(width: 240, height: 60))
        XCTAssertEqual(playlist.maximumSize?.width, 900)
        XCTAssertEqual(playlist.maximumSize?.height, .greatestFiniteMagnitude,
                       "a maximum on one axis only leaves the other unbounded")
    }

    /// R1: a saved frame is honoured for position, never for a size the layout rejects. The saved
    /// top-left stays put, so a clamped window grows downward rather than jumping.
    func testRestoredFrameIsClampedToTheLayoutWhilePreservingTopLeft() {
        let minimum = NSSize(width: 317, height: 168)
        let maximum = NSSize(width: 16_384, height: 16_384)
        let saved = NSRect(x: 700, y: 400, width: 376, height: 100)
        let clamped = WinampModernMainWindowController.clamp(frame: saved, minimum: minimum, maximum: maximum)
        XCTAssertEqual(clamped.width, 376, "a width already above the minimum is left alone")
        XCTAssertEqual(clamped.height, 168)
        XCTAssertEqual(clamped.minX, saved.minX)
        XCTAssertEqual(clamped.maxY, saved.maxY, "the saved top edge is the anchor")

        let valid = NSRect(x: 10, y: 10, width: 500, height: 500)
        XCTAssertEqual(WinampModernMainWindowController.clamp(frame: valid, minimum: minimum, maximum: maximum),
                       valid, "a frame inside the limits is untouched")

        let huge = NSRect(x: 10, y: 10, width: 40_000, height: 40_000)
        let capped = WinampModernMainWindowController.clamp(frame: huge, minimum: minimum, maximum: maximum)
        XCTAssertEqual(capped.size, maximum)
    }

    /// UI Size multiplies the skin's pixel grid, so the limits scale with it at every level.
    func testLayoutLimitsScaleWithEveryUISizeLevel() throws {
        let renderer = try makeRenderer(layout: "<layer id=\"x\" x=\"0\" y=\"0\" w=\"4\" h=\"4\"/>")
        let minimum = renderer.layoutMinimumSize
        for level in UIScaleLevel.allCases {
            let scale = level.scaleFactor
            let scaled = NSSize(width: (minimum.width * scale).rounded(),
                                height: (minimum.height * scale).rounded())
            let saved = NSRect(x: 0, y: 1_000, width: 10, height: 10)
            let clamped = WinampModernMainWindowController.clamp(
                frame: saved, minimum: scaled,
                maximum: NSSize(width: 16_384 * scale, height: 16_384 * scale))
            XCTAssertEqual(clamped.size, scaled, "UI Size \(level) must clamp to its own scaled minimum")
            XCTAssertEqual(clamped.maxY, saved.maxY)
        }
    }

    // MARK: - 13.1 Component and container classification

    /// `<component param="guid:…">` is the third holder form, and the one every separate-window skin
    /// actually uses for its playlist and library content.
    func testComponentElementIsAHolderAndTakesItsKindFromParam() throws {
        let renderer = try makeRenderer(layout: """
        <component id="pl.content" param="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}"
                   x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
        """)
        let holders = renderer.componentHolders()
        XCTAssertEqual(holders.count, 1)
        XCTAssertEqual(holders.first?.kind, .playlist)
        XCTAssertEqual(holders.first?.frame, CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertEqual(renderer.componentHolder(at: CGPoint(x: 100, y: 100))?.kind, .playlist)
    }

    /// The other two forms keep working, and `hold` still wins over an id.
    func testWindowholderAndBucketRemainHolders() throws {
        let renderer = try makeRenderer(layout: """
        <windowholder id="myviswnd" hold="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"
                      x="0" y="0" w="100" h="100"/>
        <componentbucket id="my.bucket" x="100" y="0" w="100" h="100" wndtype="skin.config"/>
        """)
        XCTAssertEqual(renderer.componentHolders().map(\.kind), [.library],
                       "a bucket naming no known component is not a surface")
    }

    /// A holder naming something we have no surface for stays inert instead of falling through to
    /// the wrong host surface, and says so in the compatibility report.
    func testUnknownComponentBecomesAnInertOtherSurfaceWithADiagnostic() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="200" h="200">
              <component id="mystery" param="guid:{DEADBEEF-0000-0000-0000-000000000000}"
                         x="0" y="0" w="50" h="50"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        XCTAssertEqual(renderer.componentHolders().map(\.kind), [.other])
        let report = loaded.compatibilityReport
        XCTAssertTrue(report.findings.contains { $0.code == WalDiagnosticCode.unknownComponent.rawValue },
                      "an unrecognized component GUID is a reported compatibility gap")
    }

    /// Container kind comes from `component=`, never from a substring of the id.
    func testContainerKindComesFromItsComponentAttribute() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="100" h="100"/></container>
          <container id="Pledit" component="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}">
            <layout id="normal" w="100" h="100"/>
          </container>
          <container id="MLibrary" component="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}">
            <layout id="normal" w="100" h="100"/>
          </container>
          <container id="eq"><layout id="normal" w="100" h="100"/></container>
          <container id="colorthemes"><layout id="normal" w="100" h="100"/></container>
        </WasabiXML>
        """)
        let byID = WinampModernContainerTopology.analyze(graph: loaded.runtime.graph)
            .reduce(into: [String: WinampModernContainerInfo]()) { $0[$1.id] = $1 }
        XCTAssertEqual(byID["Pledit"]?.kind, .playlist)
        XCTAssertEqual(byID["MLibrary"]?.kind, .library)
        XCTAssertEqual(byID["eq"]?.kind, .equalizer, "an exact short-token id is the one id fallback")
        XCTAssertNil(byID["colorthemes"]?.kind)
        XCTAssertNil(byID["main"]?.kind)
        XCTAssertEqual(byID["Pledit"]?.isSynthesized, false)
    }

    /// The registry itself: exact matches only, with the fuzzy holder-id rule kept separate.
    func testRegistryMatchesExactlyAndKeepsTheHolderIdHeuristicSeparate() {
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "guid:pl"), .playlist)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"), .library)
        XCTAssertNil(WinampModernComponentRegistry.kind(for: "Pledit"), "no substring matching")
        XCTAssertNil(WinampModernComponentRegistry.kind(for: "MLibrary"))
        XCTAssertNil(WinampModernComponentRegistry.kind(for: "colorthemes"))
        XCTAssertEqual(WinampModernComponentRegistry.kindFromHolderIdentifier("centro.windowholder.library"),
                       .library)
        XCTAssertEqual(WinampModernComponentRegistry.kindFromHolderIdentifier("centro.windowholder.visualization"),
                       .visualization)
        XCTAssertNil(WinampModernComponentRegistry.kindFromHolderIdentifier("centro.windowholder.other"))
        XCTAssertTrue(WinampModernComponentRegistry.isHolderElement("Component"))
        XCTAssertFalse(WinampModernComponentRegistry.isHolderElement("group"))
    }

    // MARK: - 13.2 Inventory

    /// A skin that declares a playlist window and embeds nothing: separate windows, one declared
    /// surface, the rest synthesizable.
    func testInventoryReadsDeclaredContainersAndMissingSurfaces() throws {
        let inventory = try makeInventory(xml: Self.separateWindowSkin)
        XCTAssertEqual(inventory.arrangement, .separateWindows)
        XCTAssertEqual(inventory.declaredContainers[.playlist], "Pledit")
        XCTAssertTrue(inventory.embeddedKinds.isEmpty)
        XCTAssertEqual(inventory.synthesizableKinds.sorted { $0.rawValue < $1.rawValue },
                       [.equalizer, .library])
    }

    /// Reachability follows a standard frame's `content=` into the group it names, and on through
    /// `inherit_group`, XUI tags, and `Wasabi:Frame` panes.
    func testInventoryFollowsContentInheritanceAndFramePanes() throws {
        let inventory = try makeInventory(xml: """
        <WasabiXML>
          <groupdef id="frame.base">
            <component param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}" x="0" y="0" w="10" h="10"/>
          </groupdef>
          <groupdef id="content.group" inherit_group="frame.base">
            <Wasabi:Frame id="split" left="pane.left" right="pane.right" from="left" width="60"/>
          </groupdef>
          <groupdef id="pane.left">
            <component param="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}" x="0" y="0" w="10" h="10"/>
          </groupdef>
          <groupdef id="pane.right"><slider action="EQ_BAND" param="3" x="0" y="0" w="8" h="40"/></groupdef>
          <groupdef id="wasabi.standardframe.statusbar" xuitag="Wasabi:StandardFrame:Status">
            <script id="frame.script" file="scripts/standardframe.maki"/>
          </groupdef>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <Wasabi:StandardFrame:Status content="content.group" x="0" y="0" w="0" h="0"
                                           relatw="1" relath="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let main = try XCTUnwrap(inventory.containers.first { $0.isMainPlayer })
        XCTAssertEqual(main.reachableKinds, [.playlist, .library],
                       "content= → inherit_group → frame panes are all reachable")
        XCTAssertTrue(main.hasEqualizerControls, "an EQ_BAND slider inside a pane is an EQ surface")
        XCTAssertEqual(inventory.arrangement, .singleWindowSUI)
        XCTAssertTrue(inventory.synthesizableKinds.isEmpty, "an SUI skin is never synthesized into")
    }

    /// The cPro shape: surfaces embedded in the main window through engine holders. Nothing is
    /// missing, so nothing may be synthesized — a duplicate window is the failure to avoid.
    func testSUISkinWithScriptBuiltHoldersSynthesizesNothing() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <groupdef id="centro.sui">
            <windowholder id="centro.windowholder.library" x="0" y="0" w="10" h="10"/>
            <windowholder id="PlaylistPro.wdh" hold="guid:pl" x="0" y="10" w="10" h="10"/>
          </groupdef>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <group id="centro.sui" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertEqual(loaded.surfaceInventory.arrangement, .singleWindowSUI)
        XCTAssertEqual(loaded.surfaceInventory.embeddedKinds, [.playlist, .library])
        XCTAssertTrue(loaded.surfaceSynthesis.synthesizedContainers.isEmpty)
        XCTAssertEqual(WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).count, 1)
    }

    // MARK: - 13.2 Synthesis

    /// The measured mmd3 shape: conventional frame ids with no `xuitag=`. The alias lets the frame be
    /// found, and the synthesized container is a real window built from the skin's own frame.
    func testMissingSurfaceIsSynthesizedFromAConventionalStandardFrame() throws {
        let loaded = try makeSkin(xml: Self.separateWindowSkin)
        let synthesis = loaded.surfaceSynthesis
        XCTAssertEqual(synthesis.synthesizedContainers[.library], "nullplayer.library")
        XCTAssertEqual(synthesis.synthesizedContainers[.equalizer], "nullplayer.equalizer")
        XCTAssertTrue(synthesis.unavailable.isEmpty)

        let containers = WinampModernContainerTopology.analyze(graph: loaded.runtime.graph)
        let library = try XCTUnwrap(containers.first { $0.id == "nullplayer.library" })
        XCTAssertTrue(library.isSynthesized)
        XCTAssertEqual(library.kind, .library)
        XCTAssertEqual(library.defaultSize, CGSize(width: 640, height: 400))
        XCTAssertTrue(library.isVisibleWindow)

        // The window is a real, renderable container whose frame points at a registered content
        // group. Instantiating that group is the frame script's job at runtime (the fixture's script
        // is a stub); the render harness covers the real thing on mmd3 and CornerAmp.
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost(),
                                               containerID: "nullplayer.library")
        addTeardownBlock { renderer.teardown() }
        let frame = try XCTUnwrap(renderer.sceneNodes().first {
            $0.object.typeName.caseInsensitiveCompare("Wasabi:StandardFrame:Status") == .orderedSame
        })
        XCTAssertEqual(frame.object.attributes["content"], "nullplayer.library.content")
        XCTAssertEqual(frame.object.attributes["componentname"], "Media Library")
        XCTAssertEqual(frame.frame, CGRect(x: 0, y: 0, width: 640, height: 400))
        XCTAssertTrue(loaded.runtime.types.contains(identifier: "nullplayer.library.content"))
    }

    /// Winamp's identifier-only standard-library shells are not a window. A skin that declares no
    /// frame of its own must fall back to the classic window, with a reason.
    func testEmptyWasabiShellsProduceAClassicFallbackNotABlankWindow() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="200" h="200"/></container>
          <container id="Pledit" component="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}">
            <layout id="normal" w="100" h="100"/>
          </container>
        </WasabiXML>
        """)
        XCTAssertTrue(loaded.surfaceSynthesis.synthesizedContainers.isEmpty)
        XCTAssertNotNil(loaded.surfaceSynthesis.unavailable[.library])
        XCTAssertNotNil(loaded.surfaceSynthesis.unavailable[.equalizer])
        XCTAssertTrue(loaded.surfaceSynthesis.unavailable[.library]?.contains("standardframe") == true,
                      "the reason names the prerequisite that failed")
        XCTAssertFalse(WinampModernContainerTopology.analyze(graph: loaded.runtime.graph)
            .contains { $0.isSynthesized })
    }

    /// `<text default=":componentname">` is a placeholder the frame fills, not a string to draw.
    func testComponentNamePlaceholderResolvesFromTheNearestFrameOrContainer() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="Pledit" name="Playlist Editor">
            <layout id="normal" w="200" h="200">
              <group id="frame" componentname="My Component" x="0" y="0" w="100" h="20">
                <text id="title" default=":componentname" x="0" y="0" w="100" h="20"/>
              </group>
              <text id="outer.title" default=":componentname" x="0" y="40" w="100" h="20"/>
              <text id="plain" default="literal" x="0" y="60" w="100" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        func text(_ id: String) throws -> String {
            let object = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: id).first)
            return WasabiTextMetrics.content(of: object, host: host)
        }
        XCTAssertEqual(try text("title"), "My Component", "the nearest componentname wins")
        XCTAssertEqual(try text("outer.title"), "Playlist Editor", "otherwise the container's name")
        XCTAssertEqual(try text("plain"), "literal")
    }

    /// A skin declaring its own `xuitag=` always wins; an alias only fills an unclaimed tag.
    func testXUITagAliasNeverStealsATagASkinDeclared() {
        let registry = WasabiTypeRegistry()
        func define(_ identifier: String, xuiTag: String?) {
            registry.register(WasabiGroupDefinition(identifier: identifier, xuiTag: xuiTag,
                                                    inheritedGroup: nil, embeddedXUITag: nil,
                                                    defaultAttributes: [:], templateChildren: [],
                                                    source: WalSourceLocation(path: "/test.xml")))
        }
        define("skin.frame", xuiTag: "Wasabi:StandardFrame:Status")
        define("wasabi.standardframe.statusbar", xuiTag: nil)
        XCTAssertFalse(registry.registerXUITagAlias("Wasabi:StandardFrame:Status",
                                                    to: "wasabi.standardframe.statusbar"),
                       "the skin already claimed this tag")
        XCTAssertFalse(registry.registerXUITagAlias("Wasabi:StandardFrame:NoStatus",
                                                    to: "wasabi.standardframe.nostatusbar"),
                       "the destination groupdef does not exist")
        define("wasabi.standardframe.nostatusbar", xuiTag: nil)
        XCTAssertTrue(registry.registerXUITagAlias("Wasabi:StandardFrame:NoStatus",
                                                   to: "wasabi.standardframe.nostatusbar"))
        XCTAssertTrue(registry.isXUITag("Wasabi:StandardFrame:NoStatus"))
    }

    /// An mmd3-shaped skin: a declared playlist window, a usable statusbar frame declared with the
    /// conventional id and *no* `xuitag`, and no equalizer or library window.
    private static let separateWindowSkin = """
    <WasabiXML>
      <groupdef id="wasabi.standardframe.statusbar" background="wasabi.frame.basetexture">
        <layer id="window.top" image="wasabi.frame.top" x="0" y="0" w="0" relatw="1" h="8"/>
        <script id="standardframe.script" file="scripts/standardframe.maki"/>
      </groupdef>
      <groupdef id="pledit.content.group">
        <component param="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}"
                   x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
      </groupdef>
      <container id="main"><layout id="normal" default_w="400" default_h="200"/></container>
      <container id="Pledit" component="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}">
        <layout id="normal" default_w="381" default_h="260">
          <Wasabi:StandardFrame:Status content="pledit.content.group" x="0" y="0" w="0" h="0"
                                       relatw="1" relath="1"/>
        </layout>
      </container>
    </WasabiXML>
    """

    /// The inventory as taken *before* synthesis — `loaded.document` is the post-synthesis document.
    private func makeInventory(xml: String) throws -> WinampModernSurfaceInventory {
        try makeSkin(xml: xml).surfaceInventory
    }

    // MARK: - Helpers

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="200" h="200" minimum_w="120" minimum_h="80">
        \(layout)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try makeSkin(xml: xml)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase13Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ payload: Data) throws {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        try add("skin.xml", Data(xml.utf8))
        // A standard frame is only usable if it carries the script that builds its client area, and a
        // declared `<script file=…>` must resolve, so the fixtures ship a do-nothing one.
        try add("scripts/standardframe.maki", Self.emptyMakiScript())
        return url
    }

    /// The smallest well-formed MAKI object: header, one class, one no-op method, no code.
    private static func emptyMakiScript() -> Data {
        var data = Data([0x46, 0x47])                              // "FG"
        func appendUInt16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func appendUInt32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        appendUInt16(0x0403)                                       // version
        appendUInt32(23)
        appendUInt32(1)                                            // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(1)                                            // methods
        appendUInt16(0)
        appendUInt16(0)
        let name = Array("getid".utf8)
        appendUInt16(UInt16(name.count))
        data.append(contentsOf: name)
        appendUInt32(0)                                            // variables
        appendUInt32(0)                                            // constants
        appendUInt32(0)                                            // bindings
        appendUInt32(0)                                            // code length
        return data
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
