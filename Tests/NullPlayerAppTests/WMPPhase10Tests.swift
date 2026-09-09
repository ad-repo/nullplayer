import CoreGraphics
import XCTest
@testable import NullPlayer

/// The 2026-09-09 live report on `WoW`, which was four defects wearing each other's symptoms: the
/// skin opened on an empty playlist panel with no player behind it, the Now Playing readout painted
/// across the whole shield instead of marqueeing inside its box, and the playlist itself was empty
/// however many tracks were queued.
///
/// Every one of them is invisible to a graph that parsed and to a headless sweep of the *same*
/// tree, which is why each test below pins the mechanism rather than the picture — and why the
/// corpus numbers beside them are what decides how much a rule is allowed to move.
final class WMPPhase10Tests: XCTestCase {

    // MARK: - A `<TEXT>` is a box (114 of 180 archives author `scrolling`)

    private func textFixture(_ attributes: String, canvas: String = "width=\"120\" height=\"20\"")
        throws -> URL {
        try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" \(canvas) backgroundColor="#000000">
              <TEXT id="meta" left="10" top="4" width="30" height="12" fontSize="10"
                    foregroundColor="#FFFFFF" \(attributes)/>
            </VIEW></THEME>
            """.utf8))
        ])
    }

    /// **The reported picture.** `WoW`'s `metadata` is a 77x30 box and the host puts
    /// "- AC/DC - Shoot to Thrill / Playing" in it; drawn unclipped, that ran straight across the
    /// player's buttons. The clip is horizontal only — see `WMPRenderer.draw(_:in:context:clock:)`
    /// for why the vertical half stays open.
    func testTextIsClippedToItsOwnBoxHorizontally() async throws {
        let archive = try textFixture(#"value="MMMMMMMMMMMMMMMMMMMMMMMM""#)
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let image = try await WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
            .render(scene: scene).image

        // Inside the box the text is drawn; one pixel past its right edge nothing is.
        let inside = (0..<12).contains { WMPSkinTestSupport.rgba(image, x: 20, yFromTop: 4 + $0)[0] > 0 }
        XCTAssertTrue(inside, "the readout draws inside its own frame")
        for y in 0..<20 {
            XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 45, yFromTop: y)[0], 0,
                           "nothing is painted past the box's right edge (row \(y))")
        }
    }

    /// A marquee is the only animation a skin turns on from script rather than by naming a GIF, so
    /// it has to join the repaint cadence or it renders one frame and stops.
    func testScrollingTextDrivesTheRepaintCadenceAndMovesWithTheClock() async throws {
        let archive = try textFixture(
            #"value="MMMMMMMMMMMMMMMMMMMMMMMM" scrolling="true" scrollingDelay="50" scrollingAmount="2""#)
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let renderer = WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))

        let cadence = try XCTUnwrap(renderer.animationCadence(for: scene),
                                    "a scrolling readout is what schedules its own repaints")
        XCTAssertEqual(cadence.shortestDelay, 0.05, accuracy: 0.0001)
        XCTAssertNil(cadence.endsAt, "a marquee never plays a last frame")
        XCTAssertEqual(cadence.bounds, WMPRect(x: 10, y: 4, width: 30, height: 12),
                       "and it repaints its own box, not the window")

        func column(_ clock: TimeInterval) async throws -> [UInt8] {
            let image = try await renderer.render(scene: scene, clock: clock).image
            return (0..<12).map { WMPSkinTestSupport.rgba(image, x: 20, yFromTop: 4 + $0)[0] }
        }
        let settled = try await column(0)
        let later = try await column(0.5)
        XCTAssertNotEqual(settled, later, "ten steps of 2 px moves the glyphs under the sample")
    }

    /// A string that already fits is not scrolled: jittering a static readout is worse than leaving
    /// it alone, and `WoW` turns `scrolling` on and off from one handler as titles change.
    func testAStringThatFitsIsNotScrolled() async throws {
        let archive = try textFixture(#"value="ii" scrolling="true" scrollingDelay="50""#)
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let renderer = WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
        XCTAssertNil(renderer.animationCadence(for: scene))
    }

    // MARK: - `textWidth` is how a skin decides to marquee (133 uses / 92 skins)

    /// `WoW` writes `metadata.scrolling = (metadata.textWidth > metadata.width)` on every metadata
    /// change. `textWidth` answered the unset-numeric 0, so the comparison was always false and no
    /// skin in the corpus could ever turn its marquee on.
    func testTextWidthIsMeasuredAndScrollingCommitsToTheScene() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="120" height="20" scriptFile="skin.js" onLoad="run()">
              <TEXT id="meta" left="10" top="4" width="30" height="12" fontSize="10"
                    fontFace="Arial" value="MMMMMMMMMMMMMMMMMMMMMMMM"
                    scrollingDelay="40" scrollingAmount="1"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("skin.js", data: Data("""
            var measured = 0;
            function run() { measured = meta.textWidth; meta.scrolling = (meta.textWidth > meta.width); }
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let suite = "WMPPhase10Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data("p10".utf8),
                                                                       defaults: defaults))
        let output = await runtime.transact(skin: skin, viewID: "main",
            size: WMPSize(width: 120, height: 20), snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "onLoad", targetID: nil, handlers: ["run()"]))
        XCTAssertTrue(output.diagnostics.isEmpty, "\(output.diagnostics)")

        let node = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "meta" })
        let address = WMPScenePropertyAddress(stableID: node.stableID, property: "scrolling")
        // The write has to *commit*: `scrolling` is not authored here, and a property nothing
        // renders is stored inert and never reaches the builder.
        XCTAssertEqual(output.overrides.properties[address]?.truth, true,
                       "a measured overflow turns the marquee on, and the write reaches the scene")

        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: output.overrides)
        let text = try XCTUnwrap(scene.commands.compactMap { command -> WMPSceneText? in
            guard case let .text(text) = command.paint, command.nodeID == "meta" else { return nil }
            return text
        }.first)
        XCTAssertTrue(text.scrolling)
        XCTAssertEqual(text.scrollDelayMilliseconds, 40)
        XCTAssertEqual(text.scrollAmount, 1)
    }

    // MARK: - What an unanswerable `wmpprop:` means (1,459 uses in the corpus)

    private func registryChange(_ markup: String, id: String, property: String) async throws
        -> WMPJSONValue? {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        var registry = WMPObservablePropertyRegistry(graph: skin.graph)
        let node = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id })
        let address = WMPScenePropertyAddress(stableID: node.stableID, property: property)
        return registry.changes(for: WMPHostSnapshot()).first { $0.address == address }?.value
    }

    /// **The reported defect.** `WoW` authors `<PLAYLIST visible="wmpprop:plMode.visible">`, and
    /// `plMode` is a name WMP's own UI owns rather than one of this skin's elements. Resolving it to
    /// the empty string committed a falsy `visible`, and the builder deletes a node whose `visible`
    /// override is false: the playlist control, its rows and its hosted widget were all gone.
    func testAnUnknownElementPathDoesNotHideTheNode() async throws {
        let unknown = try await registryChange("""
            <THEME><VIEW id="main" width="40" height="20">
              <PLAYLIST id="pl" left="0" top="0" width="40" height="20"
                        visible="wmpprop:plMode.visible"/>
            </VIEW></THEME>
            """, id: "pl", property: "visible")
        XCTAssertNil(unknown, "an element this skin never declared is unknown, not hidden")

        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20">
              <PLAYLIST id="pl" left="0" top="0" width="40" height="20"
                        visible="wmpprop:plMode.visible"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertNotNil(scene.widgets.first { $0.nodeID == "pl" },
                        "the playlist keeps its hosted surface, which is what holds the rows")
    }

    /// **And a host property this engine does not implement genuinely is off.** `xsn_sports` hangs
    /// its whole SRS WOW panel off `visible="wmpprop:eq.enhancedAudio"` (101 uses across 33 skins);
    /// showing the "SRS ON" badge would claim a feature that does nothing.
    func testAnUnimplementedHostPathStillHides() async throws {
        let answered = try await registryChange("""
            <THEME><VIEW id="main" width="40" height="20">
              <SUBVIEW id="srs" left="0" top="0" width="40" height="20"
                       visible="wmpprop:eq.enhancedAudio"/>
            </VIEW></THEME>
            """, id: "srs", property: "visible")
        XCTAssertEqual(answered, .string(""))
    }

    /// A `wmpprop:` path may name another element in the same skin — 150 of the corpus's
    /// `visible="wmpprop:…"` attributes do. `WoW` hangs its CD-rip bar off
    /// `wmpprop:playlist2.visible`, and 8 skins share that exact line.
    func testVisibleMirrorsAnotherElementInTheSameSkin() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20">
              <PLAYLIST id="playlist2" left="0" top="0" width="40" height="20" visible="false"/>
              <SUBVIEW id="ripBar" left="0" top="0" width="40" height="8"
                       backgroundColor="#FF0000" visible="wmpprop:playlist2.visible"/>
              <SUBVIEW id="listBar" left="0" top="8" width="40" height="8"
                       backgroundColor="#00FF00" visible="wmpprop:playlist2.enabled"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertNil(scene.commands.first { $0.nodeID == "ripBar" },
                     "the bar follows the element it mirrors, which is authored hidden")
        XCTAssertNotNil(scene.commands.first { $0.nodeID == "listBar" },
                        "a property that element never authored is unknown, not false")
    }
}
