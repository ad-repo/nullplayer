import XCTest
@testable import NullPlayer

/// B378: a slider's drawn thumb is part of the slider. Enya_Winamp_3_Skin's EQ bands are 3-px
/// `<slider>`s under a 5-px thumb, over a bar layer; a press on the knob's outer columns hit the bar.
final class WinampModernB378Tests: XCTestCase {
    /// Enya's band in miniature: a 5x39 bar, a 3x30 vertical slider centred on it, a 5x5 thumb.
    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="bar" file="bar.png"/>
        <bitmap id="knob" file="knob.png"/>
      </elements>
      <container id="Main">
        <layout id="normal" w="16" h="40">
          <layer id="eqbar" image="bar" x="5" y="0"/>
          <slider id="band" action="EQ_BAND" param="1" x="6" y="0" w="3" h="30" thumb="knob" orientation="v"/>
        </layout>
      </container>
    </WasabiXML>
    """

    func testThePressOnTheThumbsOuterColumnsIsTheSlidersNotTheBars() throws {
        let loaded = try makeWinampModernSkin(xml: Self.skinXML, files: [
            "bar.png": try whitePNG(width: 5, height: 39), "knob.png": try whitePNG(width: 5, height: 5),
        ])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: WinampModernStubHost(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let band = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "band").first)
        let thumb = try XCTUnwrap(renderer.sliderThumb(band, pressed: false, hovered: true))
        let knob = renderer.sliderThumbFrame(band, thumb: thumb, in: try XCTUnwrap(renderer.frame(of: band)))
        let row = knob.midY
        XCTAssertEqual(renderer.object(at: CGPoint(x: 5.5, y: row))?.xmlID, "band", "the knob's left column")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 9.5, y: row))?.xmlID, "band", "the knob's right column")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 7.5, y: row))?.xmlID, "band")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 5.5, y: 35))?.xmlID, "eqbar",
                       "the bar below the slider's travel is still the bar's")
    }
}
