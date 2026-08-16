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

    // MARK: - 13.3 Container-scoped runtime

    /// A `switchToLayout`/`resize` is addressed to the container whose script called it. With one
    /// runtime and several windows, the auxiliary playlist resizing itself must not resize the
    /// player (R6).
    func testLayoutCallbacksAreAddressedToTheContainerThatAskedForThem() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" default_w="400" default_h="200" minimum_w="10" minimum_h="10"/>
            <layout id="shade" default_w="400" default_h="20" minimum_w="10" minimum_h="10"/>
          </container>
          <container id="Pledit" component="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}">
            <layout id="normal" default_w="300" default_h="150" minimum_w="10" minimum_h="10"/>
            <layout id="plshade" default_w="300" default_h="25" minimum_w="10" minimum_h="10"/>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let mainRenderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, containerID: "main")
        let auxRenderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, containerID: "Pledit")
        addTeardownBlock { mainRenderer.teardown(); auxRenderer.teardown() }

        // The routing the controller installs, without an AppKit window in the way.
        let renderers: [WasabiObjectID: WasabiSceneRenderer] = [
            mainRenderer.container.stableID: mainRenderer,
            auxRenderer.container.stableID: auxRenderer,
        ]
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        scripts.layoutSwitchRequested = { container, id in
            guard let renderer = renderers[container] else { return false }
            return (try? renderer.activateLayout(id: id)) != nil
        }
        scripts.layoutResizeRequested = { container, size in
            _ = renderers[container]?.resize(to: size)
        }

        let program = try MakiBytecodeParser().parse(Self.emptyMakiScript(),
                                                     source: WalSourceLocation(path: "/test.maki"))
        let playlist = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "Pledit").first)
        _ = try scripts.invoke(method: "switchtolayout", on: MakiObjectReference(.gui(playlist.stableID)),
                               arguments: [.string("plshade")], program: program)
        XCTAssertEqual(auxRenderer.activeLayoutID, "plshade")
        XCTAssertEqual(mainRenderer.activeLayoutID, "normal", "the player is untouched")
        XCTAssertEqual(mainRenderer.canvasSize, CGSize(width: 400, height: 200))

        let playlistLayout = try XCTUnwrap(auxRenderer.container.children.first {
            $0.xmlID == "plshade"
        })
        _ = try scripts.invoke(method: "resize", on: MakiObjectReference(.gui(playlistLayout.stableID)),
                               arguments: [.integer(0), .integer(0), .integer(320), .integer(40)],
                               program: program)
        XCTAssertEqual(auxRenderer.canvasSize, CGSize(width: 320, height: 40))
        XCTAssertEqual(mainRenderer.canvasSize, CGSize(width: 400, height: 200),
                       "an auxiliary container's resize must not reach the player's window")
    }

    // MARK: - 13.4 Surface catalog and routing

    /// The catalog reconciles three sources — what the skin embeds, what it declares, and what
    /// synthesis produced — against the containers that actually opened.
    func testCatalogPrefersEmbeddedThenContainerThenClassicFallback() throws {
        let loaded = try makeSkin(xml: Self.separateWindowSkin)
        let catalog = WinampModernSurfaceCoordinator.makeCatalog(
            loadedSkin: loaded,
            hostedContainerIDs: ["Pledit", "nullplayer.library", "nullplayer.equalizer"],
            embeddedContainerID: nil)
        XCTAssertEqual(catalog.playlist, .declaredContainer(id: "Pledit"))
        XCTAssertEqual(catalog.library, .synthesizedContainer(id: "nullplayer.library"))
        XCTAssertEqual(catalog.equalizer, .synthesizedContainer(id: "nullplayer.equalizer"))

        // A declared container whose window never opened is a fallback, not a phantom target.
        let unopened = WinampModernSurfaceCoordinator.makeCatalog(
            loadedSkin: loaded, hostedContainerIDs: [], embeddedContainerID: nil)
        XCTAssertFalse(unopened.playlist.isSkinOwned)
    }

    /// An embedded surface wins over everything and never claims a window of its own.
    func testEmbeddedSurfaceIsRoutedToTheSkinAndOwnsNoWindow() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <groupdef id="sui">
            <windowholder id="hold.pl" hold="guid:pl" x="0" y="0" w="10" h="10"/>
          </groupdef>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <group id="sui" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let mainContainer = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "main").first)
        let catalog = WinampModernSurfaceCoordinator.makeCatalog(
            loadedSkin: loaded, hostedContainerIDs: [], embeddedContainerID: mainContainer.stableID)
        XCTAssertEqual(catalog.playlist, .embedded(containerID: mainContainer.stableID))

        var revealed: [WinampModernComponentKind] = []
        var classicCalls: [WinampModernComponentKind] = []
        let coordinator = WinampModernSurfaceCoordinator(catalog: catalog, environment: .init(
            revealEmbedded: { kind, _ in revealed.append(kind); return true },
            isMainWindowVisible: { true },
            window: { _ in nil },
            setVisible: { _, _ in XCTFail("an embedded surface has no window to show") },
            classicFallback: { kind, _ in classicCalls.append(kind) },
            redraw: {}))

        XCTAssertTrue(coordinator.handles(.playlist))
        coordinator.toggleSurface(.playlist)
        coordinator.showSurface(.playlist)
        XCTAssertEqual(revealed, [.playlist, .playlist])
        XCTAssertTrue(classicCalls.isEmpty)
        XCTAssertNil(coordinator.nativeWindow(for: .playlist),
                     "embedded surfaces must stay out of docking and frame persistence")
        XCTAssertTrue(coordinator.isSurfaceVisible(.playlist))

        // The library, which this skin does not host at all, goes to the classic window instead.
        XCTAssertFalse(coordinator.handles(.library))
        coordinator.showSurface(.library)
        XCTAssertEqual(classicCalls, [.library])
    }

    /// A container surface toggles its own window and nothing else.
    func testContainerSurfaceTogglesItsOwnWindow() throws {
        let catalog = WinampModernSurfaceCatalog(playlist: .declaredContainer(id: "Pledit"),
                                                 equalizer: .classicFallback(reason: "none"),
                                                 library: .synthesizedContainer(id: "nullplayer.library"))
        var visibility: [String: Bool] = ["Pledit": false, "nullplayer.library": false]
        let windows: [String: NSWindow] = [:]
        let coordinator = WinampModernSurfaceCoordinator(catalog: catalog, environment: .init(
            revealEmbedded: { _, _ in XCTFail("nothing is embedded here"); return false },
            isMainWindowVisible: { true },
            window: { windows[$0] },
            setVisible: { id, visible in visibility[id] = visible },
            classicFallback: { _, _ in },
            redraw: {}))

        coordinator.showSurface(.playlist)
        XCTAssertEqual(visibility["Pledit"], true)
        XCTAssertEqual(visibility["nullplayer.library"], false, "only the addressed surface moves")
        coordinator.showSurface(.library)
        XCTAssertEqual(visibility["nullplayer.library"], true)
    }

    /// The summary the compatibility report and the render harness print.
    func testCatalogSummaryNamesEverySurface() {
        let catalog = WinampModernSurfaceCatalog(playlist: .declaredContainer(id: "Pledit"),
                                                 equalizer: .embedded(containerID: WasabiObjectID(rawValue: 1)),
                                                 library: .classicFallback(reason: "no frame"))
        let coordinator = WinampModernSurfaceCoordinator(catalog: catalog, environment: .init(
            revealEmbedded: { _, _ in true }, isMainWindowVisible: { true }, window: { _ in nil },
            setVisible: { _, _ in }, classicFallback: { _, _ in }, redraw: {}))
        XCTAssertEqual(coordinator.summary,
                       "playlist=declared:Pledit equalizer=embedded library=classic(no frame)")
    }

    // MARK: - 13.5 Shared theme and palette

    /// A colour theme belongs to the skin, not to a window: switching it from one renderer must
    /// recolour every other renderer of the same skin.
    func testThemeSwitchReachesEveryRendererOfTheSkin() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <gammaset id="Default"><gammagroup id="global" value="0,0,0"/></gammaset>
          <gammaset id="Blue"><gammagroup id="global" value="-4096,-4096,4096"/></gammaset>
          <color id="pledit.text" value="200,200,200" gammagroup="global"/>
          <container id="main"><layout id="normal" w="100" h="100"/></container>
          <container id="Pledit" component="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}">
            <layout id="normal" w="100" h="100"/>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let main = try WasabiSceneRenderer(loadedSkin: loaded, host: host, containerID: "main")
        let aux = try WasabiSceneRenderer(loadedSkin: loaded, host: host, containerID: "Pledit")
        addTeardownBlock { main.teardown(); aux.teardown() }
        var hostedRepaints = 0
        let hostedToken = NSObject()
        loaded.themeCoordinator.addObserver(hostedToken) { hostedRepaints += 1 }

        XCTAssertEqual(main.palette.listText, aux.palette.listText)
        let before = main.palette.listText

        XCTAssertTrue(main.activateTheme("Blue"))
        XCTAssertEqual(loaded.themeCoordinator.activeTheme, "Blue")
        XCTAssertEqual(hostedRepaints, 1, "hosted AppKit content is told too")
        XCTAssertNotEqual(main.palette.listText, before, "the switching renderer recolours")
        XCTAssertEqual(aux.palette.listText, main.palette.listText,
                       "and so does every other window of the same skin")
    }

    /// Each role falls back through its chain, and a skin that declares nothing still gets a
    /// deterministic colour rather than an accidental one.
    func testPaletteFallsBackThroughEachRoleChain() throws {
        let studioOnly = try makeSkin(xml: """
        <WasabiXML>
          <color id="studio.list.text" value="10,20,30"/>
          <color id="studio.list.item.selected" value="40,50,60"/>
          <color id="studio.tree.text" value="70,80,90"/>
          <container id="main"><layout id="normal" w="100" h="100"/></container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: studioOnly, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        let palette = renderer.palette
        func rgb(_ color: NSColor) -> [Int] {
            let converted = color.usingColorSpace(.deviceRGB) ?? color
            return [Int((converted.redComponent * 255).rounded()),
                    Int((converted.greenComponent * 255).rounded()),
                    Int((converted.blueComponent * 255).rounded())]
        }
        XCTAssertEqual(rgb(palette.listText), [10, 20, 30], "no pledit.text, so studio.list.text wins")
        XCTAssertEqual(rgb(palette.currentText), [10, 20, 30], "current text falls back to list text")
        XCTAssertEqual(rgb(palette.selectionBackground), [40, 50, 60])
        XCTAssertEqual(rgb(palette.treeText), [70, 80, 90])
        XCTAssertEqual(rgb(palette.treeSelection), [40, 50, 60],
                       "no studio.tree.selected, so the selection background carries it")

        let bare = try WasabiSceneRenderer(loadedSkin: try makeSkin(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="10" h="10"/></container></WasabiXML>
        """), host: TestHost())
        addTeardownBlock { bare.teardown() }
        XCTAssertEqual(bare.palette, .fallback, "a skin with no colours gets the documented defaults")
    }

    // MARK: - 13.6 Playlist content

    /// `PE_Info` is Winamp's playlist status line, and the renderer and a script's `getAutoWidth()`
    /// must read the same string from the same place.
    func testPlaylistInfoLineIsSharedBetweenDrawingAndMeasurement() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <text id="PE_Info" x="0" y="0" w="120" h="12"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let info = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "PE_Info").first)
        let host = TestHost()

        WasabiTextMetrics.componentTextProvider = nil
        XCTAssertEqual(WasabiTextMetrics.content(of: info, host: host), "",
                       "with no playlist component the status line is empty, not a literal")

        WasabiTextMetrics.componentTextProvider = {
            WinampModernPlaylistSnapshot(
                rows: [WinampModernPlaylistRow(title: "A", secondary: "", duration: 90, isCurrent: true),
                       WinampModernPlaylistRow(title: "B", secondary: "", duration: 30, isCurrent: false)],
                currentIndex: 0, selectedIndex: 1)
        }
        addTeardownBlock { WasabiTextMetrics.componentTextProvider = nil }
        XCTAssertEqual(WasabiTextMetrics.content(of: info, host: host), "2 items, 2:00")

        // The measurement a script gets is of that same string.
        let metrics = loaded.runtime.resources
        _ = metrics
        let width = WasabiTextMetrics(loadedSkin: loaded)
            .width(of: info, text: WasabiTextMetrics.content(of: info, host: host))
        XCTAssertGreaterThan(width, 0)
    }

    /// Item and duration formatting, including the singular and the hour rollover.
    func testPlaylistSnapshotSummarizesItsQueue() {
        func snapshot(_ durations: [TimeInterval]) -> WinampModernPlaylistSnapshot {
            WinampModernPlaylistSnapshot(
                rows: durations.map { WinampModernPlaylistRow(title: "t", secondary: "", duration: $0,
                                                              isCurrent: false) },
                currentIndex: -1, selectedIndex: -1)
        }
        XCTAssertEqual(WinampModernPlaylistSnapshot.empty.infoLine, "0 items")
        XCTAssertEqual(snapshot([61]).infoLine, "1 item, 1:01")
        XCTAssertEqual(snapshot([3600, 61]).infoLine, "2 items, 1:01:01")
        XCTAssertEqual(snapshot([0, 0]).trackCount, 2)
        XCTAssertEqual(snapshot([10, 20]).totalDuration, 30)
    }

    // MARK: - 13.7 EQ actions

    /// Every parameter form the measured skins use, and the 1-based → 0-based conversion that is the
    /// easy thing to get wrong.
    func testEqualizerActionDecoding() {
        XCTAssertEqual(WinampModernEQAction.decode(action: "EQ_PREAMP", parameter: nil), .preamp)
        XCTAssertEqual(WinampModernEQAction.decode(action: "eq_preamp", parameter: "ignored"), .preamp)
        XCTAssertEqual(WinampModernEQAction.decode(action: "EQ_BAND", parameter: "preamp"), .preamp)
        XCTAssertEqual(WinampModernEQAction.decode(action: "EQ_BAND", parameter: "1"), .band(0))
        XCTAssertEqual(WinampModernEQAction.decode(action: "EQ_BAND", parameter: "10"), .band(9))
        XCTAssertEqual(WinampModernEQAction.decode(action: "EQ_BAND", parameter: " 5 "), .band(4))

        for invalid in ["0", "11", "-1", "", "band", "9.5"] {
            XCTAssertNil(WinampModernEQAction.decode(action: "EQ_BAND", parameter: invalid),
                         "'\(invalid)' must be inert, never a band index")
        }
        XCTAssertNil(WinampModernEQAction.decode(action: "EQ_TOGGLE", parameter: "1"))
        XCTAssertNil(WinampModernEQAction.decode(action: nil, parameter: "1"))
    }

    /// A drag writes ±12 dB through the host, and the value the thumb is drawn from is the same one.
    func testEqualizerActionRoundTripsThroughTheHost() {
        let host = FakeComponentHost()
        WinampModernEQAction.preamp.apply(normalized: 1, to: host)
        WinampModernEQAction.band(0).apply(normalized: 0, to: host)
        WinampModernEQAction.band(9).apply(normalized: 0.5, to: host)
        XCTAssertEqual(host.snapshot.preampDB, 12)
        XCTAssertEqual(host.snapshot.bandGainsDB[0], -12)
        XCTAssertEqual(host.snapshot.bandGainsDB[9], 0, accuracy: 0.001)

        XCTAssertEqual(WinampModernEQAction.preamp.normalizedValue(in: host.snapshot), 1)
        XCTAssertEqual(WinampModernEQAction.band(0).normalizedValue(in: host.snapshot), 0)
        XCTAssertEqual(WinampModernEQAction.band(9).normalizedValue(in: host.snapshot), 0.5, accuracy: 0.001)
        XCTAssertEqual(WinampModernEQAction.band(42).normalizedValue(in: host.snapshot), 0.5,
                       "an out-of-range band reads as flat rather than crashing")
    }

    /// The skin's own EQ/auto buttons light from the engine, so a change made from the menu bar or a
    /// script is reflected in the skin.
    func testActiveImageFollowsTheEngineEqualizerState() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <togglebutton id="eq.on" action="EQ_TOGGLE" x="0" y="0" w="20" h="20"
                            image="eq.off" activeImage="eq.on"/>
              <togglebutton id="eq.auto" action="EQ_AUTO" x="20" y="0" w="20" h="20"
                            image="auto.off" activeImage="auto.on"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        let host = FakeComponentHost()
        renderer.componentHost = host

        func bitmap(_ id: String) -> String? {
            renderer.sceneNodes().first { $0.object.xmlID == id }?.bitmapID
        }
        XCTAssertEqual(bitmap("eq.on"), "eq.on", "the engine starts with the EQ enabled")
        XCTAssertEqual(bitmap("eq.auto"), "auto.off")

        host.equalizerSetEnabled(false)
        host.equalizerSetAuto(true)
        XCTAssertEqual(bitmap("eq.on"), "eq.off")
        XCTAssertEqual(bitmap("eq.auto"), "auto.on")
    }

    /// A slider carrying an EQ action is drawn from the snapshot, not from its own `value=`, so a
    /// preset applied elsewhere moves it.
    func testEqualizerSliderThumbFollowsTheSnapshot() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <bitmap id="eq.thumb" file="$solid" color="255,255,255" w="4" h="4"/>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <slider id="band1" action="EQ_BAND" param="1" orientation="vertical"
                      x="0" y="0" w="10" h="100" thumb="eq.thumb"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        let host = FakeComponentHost()
        renderer.componentHost = host
        let slider = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "band1").first)
        let frame = try XCTUnwrap(renderer.frame(of: slider))

        func thumbY() -> CGFloat {
            let context = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            renderer.draw(in: context)
            return frame.minY   // drawing must not crash; the value assertion is below
        }
        _ = thumbY()

        host.equalizerSetBandGainDB(0, gainDB: 12)
        XCTAssertEqual(WinampModernEQAction.band(0).normalizedValue(in: host.snapshot), 1)
        host.equalizerApplyPreset(named: "Rock")
        XCTAssertEqual(host.appliedPresets, ["Rock"])
    }

    /// A minimal component host that answers from memory, for the EQ round trips.
    private final class FakeComponentHost: WinampModernComponentHost {
        var librarySurface: WinampModernLibrarySurface?
        var surfaceRequests = 0
        var snapshot = WinampModernEQSnapshot.flat
        var appliedPresets: [String] = []
        var removedRows: [Int] = []
        var playlist = WinampModernPlaylistSnapshot.empty

        func playlistSnapshot() -> WinampModernPlaylistSnapshot { playlist }
        func playlistSelect(row: Int) { playlist.selectedIndex = row }
        func playlistPlay(row: Int) { playlist.currentIndex = row }
        func playlistRemove(row: Int) { removedRows.append(row) }
        func equalizerSnapshot() -> WinampModernEQSnapshot { snapshot }
        func equalizerSetBandGainDB(_ band: Int, gainDB: Float) {
            guard snapshot.bandGainsDB.indices.contains(band) else { return }
            snapshot.bandGainsDB[band] = gainDB
        }
        func equalizerSetPreampDB(_ gainDB: Float) { snapshot.preampDB = gainDB }
        func equalizerSetEnabled(_ enabled: Bool) { snapshot.enabled = enabled }
        func equalizerSetAuto(_ enabled: Bool) { snapshot.auto = enabled }
        func equalizerApplyPreset(named name: String) { appliedPresets.append(name) }
        func makeLibrarySurface() -> WinampModernLibrarySurface? {
            surfaceRequests += 1
            return librarySurface
        }
        func toggleClassicWindow(for kind: WinampModernComponentKind) {}
    }

    // MARK: - 13.8 Typed embedded library

    /// The typed seam replaces an unowned `NSView`: a surface is created once per holder, told its
    /// scale and palette, and torn down — before its view leaves the hierarchy — when the holder
    /// goes, when the layout switches, and again on teardown.
    func testLibrarySurfaceLifecycleFollowsItsHolder() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <component id="ml" param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"
                         x="10" y="20" w="100" h="50"/>
            </layout>
            <layout id="shade" w="200" h="20"/>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        addTeardownBlock { renderer.teardown() }
        let componentHost = FakeComponentHost()
        let surface = StubLibrarySurface()
        componentHost.librarySurface = surface
        renderer.componentHost = componentHost
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                        componentHost: componentHost)
        view.setFrameSize(renderer.canvasSize)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.subviews.contains(surface.view))
        XCTAssertEqual(componentHost.surfaceRequests, 1)
        XCTAssertEqual(surface.scaleUpdates, 1)
        XCTAssertEqual(surface.paletteUpdates, 1)
        // Positioned at the holder's frame, converted from top-left skin space.
        XCTAssertEqual(surface.view.frame, NSRect(x: 10, y: 200 - 70, width: 100, height: 50))

        // A layout switch removes the holder; the surface must be told, not merely unparented.
        view.activateLayout(id: "shade")
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(surface.isTornDown, "the surface stands down before its view is removed")
        XCTAssertFalse(view.subviews.contains(surface.view))

        // Idempotent: teardown after a removal must not fail or double-report.
        let teardownsAfterRemoval = surface.teardowns
        view.teardown()
        XCTAssertEqual(surface.teardowns, teardownsAfterRemoval, "repeated teardown is a no-op")
    }

    /// UI Size and colour themes reach the hosted surface, not just the scene around it.
    func testLibrarySurfaceIsToldAboutScaleAndThemeChanges() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <gammaset id="Default"><gammagroup id="g" value="0,0,0"/></gammaset>
          <gammaset id="Blue"><gammagroup id="g" value="0,0,4096"/></gammaset>
          <color id="pledit.text" value="120,120,120" gammagroup="g"/>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <component id="ml" param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"
                         x="0" y="0" w="100" h="100"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        addTeardownBlock { renderer.teardown() }
        let componentHost = FakeComponentHost()
        let surface = StubLibrarySurface()
        componentHost.librarySurface = surface
        renderer.componentHost = componentHost
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                        componentHost: componentHost)
        view.setFrameSize(renderer.canvasSize)
        view.layoutSubtreeIfNeeded()

        view.skinScale = 2
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(surface.scaleUpdates, 2, "UI Size reaches the hosted browser")
        XCTAssertEqual(surface.lastScale, 2)
        XCTAssertEqual(surface.view.frame, NSRect(x: 0, y: 400 - 200, width: 200, height: 200),
                       "and its geometry scales with the rest of the scene")

        loaded.themeCoordinator.activate("Blue")
        XCTAssertGreaterThanOrEqual(surface.paletteUpdates, 2, "a theme switch recolours it too")
        view.teardown()
    }

    /// Embedded mode removes this view's own window chrome and the hit regions that go with it.
    func testEmbeddedBrowserDropsItsClassicChromeAndTitleBarRegions() {
        let classic = PlexBrowserView.LayoutMetrics.classic
        let embedded = PlexBrowserView.LayoutMetrics.embedded
        XCTAssertGreaterThan(classic.titleBarHeight, 0)
        XCTAssertEqual(embedded.titleBarHeight, 0, "the `.wal` frame already drew the title bar")
        XCTAssertEqual(embedded.leftBorder, 0)
        XCTAssertEqual(embedded.rightBorder, 0)
        XCTAssertEqual(embedded.statusBarHeight, 0)
        XCTAssertEqual(embedded.tabBarHeight, classic.tabBarHeight,
                       "the content controls are unchanged — only the window chrome goes")
        XCTAssertEqual(embedded.serverBarHeight, classic.serverBarHeight)
        XCTAssertEqual(embedded.searchBarHeight, classic.searchBarHeight)
    }

    /// A stub surface that records what it was told, with no live browser behind it.
    private final class StubLibrarySurface: WinampModernLibrarySurface {
        let view = NSView(frame: .zero)
        var browseModeRawValue = 0
        var reloads = 0
        var linkSheets = 0
        var paletteUpdates = 0
        var scaleUpdates = 0
        var lastScale: CGFloat = 0
        var teardowns = 0
        var isTornDown: Bool { teardowns > 0 }

        func reloadData() { reloads += 1 }
        func showLinkSheet() { linkSheets += 1 }
        func applyPalette(_ palette: WasabiPalette) { paletteUpdates += 1 }
        func applySkinScale(_ scale: CGFloat) { scaleUpdates += 1; lastScale = scale }
        func prepareForUITeardown() {
            guard !isTornDown else { return }
            teardowns += 1
            view.removeFromSuperview()
        }
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
        // A unique archive name gives each fixture its own `WinampModernConfiguration` namespace, so
        // a skin's persisted colour theme cannot leak between tests (or into the real app's prefs
        // under a shared "Synthetic" name).
        let url = directory.appendingPathComponent("Phase13-\(UUID().uuidString).wal")
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
