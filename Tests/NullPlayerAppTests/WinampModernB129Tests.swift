import XCTest
@testable import NullPlayer

/// B129 — the two bars that never lit: cPro2's seek bar and its volume slider.
///
/// Reported as "the volume bar, spectrum analyzer and progress bar are missing the glowing highlight
/// mouseover that the play controls have". Four independent faults sat behind it, and each one alone
/// was enough to keep the glow off screen:
///
/// 1. **`Slider.getPosition()` answered the `value` attribute, not the host.** Nothing writes that
///    attribute until the user drags that very slider, so `sc_sliderbar.m` — which sizes *both* the
///    volume fill and its glow from `max*mySlider.getPosition()/255` — computed a width of zero at
///    load and after every volume change made anywhere else. Two layers of the right artwork, zero
///    pixels wide.
/// 2. **`hoverthumb` was never drawn.** `drawSlider` honoured `downthumb` and skipped its sibling, so
///    the knob stayed dark while the bar behind it brightened.
/// 3. **`onSetFinalPosition` was never dispatched.** cPro2 draws a "finder" overlay that follows the
///    pointer from `onSetPosition` and clears it *only* there, so after a seek the stretch you seeked
///    into kept the darker `down` artwork while playback filled normally past it — the bar came out in
///    two colours.
/// 4. **The glow was themed through the muted gammagroup.** This skin's colour themes carry two hover
///    tints; the play controls get the glowing one and the two bars declare the muted ones, which most
///    of the sixty themes leave as a plain darkening with no tint at all.
///
/// And one resting-state defect the fixes exposed: the seek bar's hover overlay is the only fade layer
/// in the engine whose markup omits `alpha="0"`, so it rested lit instead of hidden.
final class WinampModernB129Tests: XCTestCase {

    private func makeObject(_ typeName: String, _ attributes: [String: String]) -> WasabiObject {
        let graph = WasabiObjectGraph()
        addTeardownBlock { graph.teardown() }
        return graph.makeObject(typeName: typeName, attributes: attributes,
                                source: WalSourceLocation(path: "test", line: 0, column: 0))
    }

    // MARK: - A host-bound slider's position is the host's

    /// Winamp's default slider range is 0…255, and a host reading has to arrive in it — this is the
    /// number `sc_sliderbar.m` multiplies its bar width by.
    func testAHostReadingArrivesInTheSlidersOwnRange() {
        let slider = makeObject("slider", ["action": "VOLUME"])
        XCTAssertEqual(WinampModernScriptRuntime.sliderPosition(normalized: 0.7, of: slider), 179)
        XCTAssertEqual(WinampModernScriptRuntime.sliderPosition(normalized: 0, of: slider), 0)
        XCTAssertEqual(WinampModernScriptRuntime.sliderPosition(normalized: 1, of: slider), 255)
    }

    /// A slider that declares a range is answered in *that* unit, not in 0…255 — mmd3 cuts its
    /// crossfade slider `high="20"` and prints the number straight into a readout as seconds.
    func testADeclaredRangeIsTheUnitTheReadingComesBackIn() {
        let slider = makeObject("slider", ["action": "VOLUME", "low": "0", "high": "20"])
        XCTAssertEqual(WinampModernScriptRuntime.sliderPosition(normalized: 0.5, of: slider), 10)
        XCTAssertEqual(WinampModernScriptRuntime.sliderPosition(normalized: 1, of: slider), 20)
    }

    // MARK: - The glow is themed through the play controls' group

    /// The two muted groups are redirected; everything else keeps the group it declares. Keyed on the
    /// declared group rather than on bitmap ids, so it covers the full-size, compact and shade
    /// variants of both bars at once.
    func testOnlyTheTwoMutedFillGroupsAreRedirected() {
        XCTAssertEqual(WasabiSkinQuirks.gammaGroup(declared: "n.infoseek.seek.hover"),
                       "n.playback.button.hoverdown")
        XCTAssertEqual(WasabiSkinQuirks.gammaGroup(declared: "n.playback.volume.active"),
                       "n.playback.button.hoverdown")
        // Case is not the skin's to get right.
        XCTAssertEqual(WasabiSkinQuirks.gammaGroup(declared: "N.InfoSeek.Seek.Hover"),
                       "n.playback.button.hoverdown")
    }

    /// The neighbours stay exactly as declared — including the *muted* fill under the glow, whose
    /// whole job is to be the resting colour, and the seek bar's own down/inactive artwork.
    func testEveryOtherGammaGroupIsLeftAlone() {
        for group in ["n.infoseek.seek.active", "n.infoseek.seek.inactive", "n.infoseek.seek.down",
                      "n.playback.button.hoverdown", "n.playback.vis", "n.playback.volume.thumb"] {
            XCTAssertNil(WasabiSkinQuirks.gammaGroup(declared: group), group)
        }
        XCTAssertNil(WasabiSkinQuirks.gammaGroup(declared: nil))
    }

    // MARK: - The resting state the markup forgot

    /// The seek bar's hover overlay rests hidden, like every other fade layer in the engine.
    func testTheSeekerHoverOverlayRestsHidden() {
        let overlay = makeObject("group", ["id": "two.info.seeker.hover.layer"])
        XCTAssertEqual(WasabiSkinQuirks.restingAlpha(for: overlay), 0)
    }

    /// **Only while the attribute is absent.** The skin's own fade eases *from* whatever `alpha`
    /// says, so once a handler has written one the script owns the value — a quirk that kept
    /// answering would pin the overlay and kill the fade in both directions.
    func testAWrittenAlphaEndsTheSeeding() {
        let overlay = makeObject("group", ["id": "two.info.seeker.hover.layer", "alpha": "255"])
        XCTAssertNil(WasabiSkinQuirks.restingAlpha(for: overlay))
    }

    /// Nothing else is seeded — a group with no `alpha` is opaque, which is Wasabi's own default and
    /// what all but one object in the corpus means by omitting it.
    func testNoOtherObjectIsSeeded() {
        for id in ["two.info.seeker.active.layer", "two.playback.volslider.bar.2", "mute.fade"] {
            XCTAssertNil(WasabiSkinQuirks.restingAlpha(for: makeObject("group", ["id": id])), id)
        }
        XCTAssertNil(WasabiSkinQuirks.restingAlpha(for: makeObject("group", [:])))
    }
}
