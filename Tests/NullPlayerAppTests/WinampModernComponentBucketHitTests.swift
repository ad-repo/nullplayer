import XCTest
@testable import NullPlayer

/// Which `<componentbucket>` icon a press lands on: none under a control drawn over the strip
/// (B450, capsuleII's thinger under its `EQ` button), none on a strip a script faded out (B449,
/// Palillo's Thinger beside its equalizer).
final class WinampModernComponentBucketHitTests: XCTestCase {
    private func makeRenderer(bucket: String, over: String = "") throws -> WasabiSceneRenderer {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <elements><bitmap id="btn" file="btn.png"/></elements>
          <container id="Main">
            <layout id="normal" w="200" h="40">
              \(bucket)
              \(over)
            </layout>
          </container>
        </WasabiXML>
        """, files: ["btn.png": try whitePNG(width: 32, height: 32)])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private let strip = #"<componentbucket id="cb" x="0" y="0" w="200" h="32"/>"#

    func testAPressOnTheStripLandsOnAnIcon() throws {
        let renderer = try makeRenderer(bucket: strip)
        XCTAssertEqual(renderer.componentBucketIcon(at: CGPoint(x: 16, y: 16))?.index, 0)
    }

    func testAButtonDrawnOverTheStripTakesThePress() throws {
        let renderer = try makeRenderer(
            bucket: strip, over: #"<button id="eq" action="TOGGLE" param="eq" image="btn" x="0" y="0"/>"#)
        XCTAssertNil(renderer.componentBucketIcon(at: CGPoint(x: 16, y: 16)), "the EQ button is on top")
        XCTAssertNotNil(renderer.componentBucketIcon(at: CGPoint(x: 48, y: 16)), "beside the button")
    }

    func testAStripAScriptFadedOutTakesNoPress() throws {
        let renderer = try makeRenderer(
            bucket: #"<componentbucket id="cb" x="0" y="0" w="200" h="32" alpha="0" targeta="0"/>"#)
        XCTAssertNil(renderer.componentBucketIcon(at: CGPoint(x: 16, y: 16)))
    }
}

/// B447: a window the skin opens by default but still draws at `alpha="0"` once its scripts have
/// started (LayerONE's `colorthemes`) is not opened. B448: the click sweep drags a slider along its
/// own orientation.
final class WinampModernB447B448Tests: XCTestCase {
    /// Asked as the default windows open, after the scripts have started: a script that raised the
    /// layout's alpha by then wins.
    func testAWindowIsInvisibleOnlyWhileItsLayoutIsAtAlphaZero() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="275" h="116"/></container>
          <container id="colorthemes" default_visible="1" nomenu="1">
            <layout id="normal" w="286" h="160" alpha="0"/>
          </container>
          <container id="pledit" default_visible="1"><layout id="normal" w="286" h="160"/></container>
        </WasabiXML>
        """, files: [:])
        let byID = Dictionary(uniqueKeysWithValues:
            WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).map { ($0.id, $0) })
        let themes = try XCTUnwrap(byID["colorthemes"])
        XCTAssertTrue(WinampModernContainerTopology.isInvisible(themes))
        XCTAssertFalse(WinampModernContainerTopology.opensWithSkin(themes), "the sweeps open what the app opens")
        XCTAssertFalse(WinampModernContainerTopology.isInvisible(try XCTUnwrap(byID["pledit"])))
        let layout = try XCTUnwrap(WasabiSceneRenderer.primaryLayout(of: themes.object))
        _ = layout.setAttribute("alpha", value: "255")
        XCTAssertFalse(WinampModernContainerTopology.isInvisible(themes), "a script raised it at load")
    }

    func testTheSweepDragsAVerticalSliderAlongItsHeight() {
        let box = CGRect(x: 0, y: 0, width: 82, height: 70)
        XCTAssertEqual(WinampModernDebugClickSweep.quarterPoint(along: box, vertical: true), CGPoint(x: 41, y: 17.5))
        XCTAssertEqual(WinampModernDebugClickSweep.quarterPoint(along: box, vertical: false), CGPoint(x: 20.5, y: 35))
    }
}
