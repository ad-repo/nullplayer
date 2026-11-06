import XCTest
@testable import NullPlayer

/// B362 — a layout nothing sizes opens at its content, not at the classic 275x116.
///
/// Psonidelic's EQ shade is `<layout id="shade" background="…">` with no `w`/`h`, a background its
/// archive does not ship, and a `relatw`/`relath` group holding a 275x15 strip. It opened 275x116, the
/// strip at the top and black below.
final class WinampModernB362Tests: XCTestCase {

    func testAnUnsizedLayoutWithAMissingBackgroundTakesItsContentsExtent() throws {
        let renderer = try makeRenderer(layoutAttributes: #"background="not.shipped""#)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 60, height: 15))
    }

    func testAnAxisTheSkinSizedIsLeftAlone() throws {
        let renderer = try makeRenderer(layoutAttributes: #"background="not.shipped" h="40""#)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 60, height: 40))
    }

    func testAContainerDefaultStillSizesTheLayout() throws {
        let renderer = try makeRenderer(layoutAttributes: #"background="not.shipped""#,
                                        containerAttributes: #"default_h="50""#)
        XCTAssertEqual(renderer.canvasSize.height, 50)
    }

    /// A notifier names no background and its script sizes it at show time; at rest its content
    /// measures smaller than the toast, so the rule leaves it alone.
    func testALayoutNamingNoBackgroundKeepsTheClassicSize() throws {
        let renderer = try makeRenderer(layoutAttributes: "")
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 275, height: 116))
    }

    private func makeRenderer(layoutAttributes: String,
                              containerAttributes: String = "") throws -> WasabiSceneRenderer {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <bitmap id="strip" file="$solid" color="200,0,0" w="60" h="15"/>
          <groupdef id="content">
            <layer id="strip" image="strip" x="0" y="0" w="60" h="15"/>
            <layer id="bottom" image="strip" x="0" y="-15" w="60" h="15" relaty="1"/>
          </groupdef>
          <container id="main" \(containerAttributes)>
            <layout id="normal" \(layoutAttributes)>
              <group id="content" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { renderer.teardown() }
        loaded.runtime.markScriptsStarted()
        return renderer
    }
}
