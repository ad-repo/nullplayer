import XCTest
@testable import NullPlayer

/// Phase 56 — `relatx`/`relaty`/`relatw`/`relath` are read as `atoi(value) != 0`, not as `== 1`.
///
/// Found live on Big Bento Modern: the Multi Content View drew the album cover **twice**, the second
/// a small crisp copy beside the real one. The object is the dimmed oversized backdrop in
/// `info.component.albumbg`, declared `w="99" h="100" relatw="2" relath="2" alpha="100"` — and `"2"`
/// failed the old `== 1` test, so it fell back to *absolute* geometry and drew at a literal 99×100.
///
/// Skins ship numbers other than 1 and mean nothing by them beyond "relative". The corpus:
/// Big Bento Modern (and its Windows 10 edition, plus both Light overlays through the base's XML)
/// `relatw="2"`; Ebonite_2_1 six declarations at `relatw="2"`; The_Nokia_5220 two at `relatw="5"`.
///
/// **`2` is a percentage; every other non-zero value is additive.** Phase 56 originally concluded
/// otherwise, and the correction is worth recording because the original reasoning looks sound.
///
/// The *defect* above discriminates absolute from relative, and nothing more: a literal 99×100 is
/// wrong, but both relative readings fix it, since 99% of a large parent is a large backdrop too.
/// Phase 56 then ruled the percentage out on Ebonite's `group w="0" h="0" relatw="2"` — 0% collapses
/// it, where additive gives the fill-the-parent idiom. That group carries **`alpha="0"`**: it is an
/// invisible Layer FX holder and draws nothing under either reading, so it cannot settle anything.
/// Its four neighbours in the same file are `x="3" y="0" w="85" h="93" relat*="2"` album-art/layerfx
/// pairs — percentage insets, and the identical shape to ClassicPro's cover below.
///
/// What does settle it is an object additive cannot place at *any* parent size: ClassicPro's Now
/// Playing cover, `x="12" y="4" w="85" h="93" relat*="2"`, inside its 80×74 jewel case. Additive puts
/// it at (202, 289, 165×167) — wholly outside its own clip, drawn nowhere, reported as "an empty
/// box". Percent insets it in the case, which is what the markup describes.
///
/// The corpus census agrees: `relat*` is `1` 8197 times, `0` 360, `2` **89** — and every value those
/// 89 carry is in 0…100. Additive geometry here is overwhelmingly negative (`w="-14" relatw="1"`).
/// `relatw="5"` stays additive; nothing measured suggests a third meaning for it.
final class WinampModernPhase56Tests: XCTestCase {

    private let parent = WasabiRect(x: 10, y: 20, width: 300, height: 200)

    /// Big Bento's backdrop, which must not be a literal 99×100. It is `alpha="100"` dimmed art
    /// behind the cover, and 99%/100% of its parent is the oversized-looking backdrop the skin wants
    /// — the same symptom the additive reading fixed, fixed by the reading the corpus supports.
    func testATwoIsAPercentageOfTheParent() {
        let spec = WasabiGeometrySpec(attributes: [
            "x": "0", "y": "0", "w": "99", "h": "100", "relatw": "2", "relath": "2",
        ])
        let resolved = spec.resolve(in: parent)
        XCTAssertEqual(resolved.width, 297, "99% of 300, not a literal 99 and not 300 + 99")
        XCTAssertEqual(resolved.height, 200, "100% of 200")
    }

    /// ClassicPro's Now Playing cover — the case additive cannot place at any parent size. Against
    /// an 80×74 jewel case it resolves outside its own clip; as a percentage it insets.
    func testATwoInsetsAnAlbumCoverInsideItsCase() {
        let spec = WasabiGeometrySpec(attributes: [
            "x": "12", "y": "4", "w": "85", "h": "93",
            "relatx": "2", "relaty": "2", "relatw": "2", "relath": "2",
        ])
        let box = WasabiRect(x: 110, y: 211, width: 80, height: 74)
        let resolved = spec.resolve(in: box)
        XCTAssertEqual(resolved.x, 110 + 9.6, accuracy: 0.001, "12% of 80, inside the case")
        XCTAssertEqual(resolved.y, 211 + 2.96, accuracy: 0.001, "4% of 74")
        XCTAssertEqual(resolved.width, 68, accuracy: 0.001, "85% of 80")
        XCTAssertEqual(resolved.height, 68.82, accuracy: 0.001, "93% of 74")
        XCTAssertLessThanOrEqual(resolved.x + resolved.width, box.x + box.width,
                                 "the cover stays inside the case it is drawn in")
    }

    /// Ebonite's `alpha="0"` Layer FX holder. 0% is zero-sized, which is the honest answer for a
    /// declaration that says zero — and it draws nothing either way, which is why it never settled
    /// the question it was once cited for.
    func testAZeroSizeWithRelativeTwoIsZeroSized() {
        let spec = WasabiGeometrySpec(attributes: [
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "2", "relath": "2",
        ])
        XCTAssertEqual(spec.resolve(in: parent).width, 0)
        XCTAssertEqual(spec.resolve(in: parent).height, 0)
    }

    /// The_Nokia_5220 ships `relatw="5"`. Nothing about 5 is special; it is simply non-zero, and
    /// stays additive — only `2` is the percentage.
    func testAnyNonZeroNumberOtherThanTwoIsAdditive() {
        for value in ["3", "5", "17", "-1"] {
            let spec = WasabiGeometrySpec(attributes: ["w": "10", "relatw": value])
            XCTAssertEqual(spec.resolve(in: parent).width, 310, "relatw=\"\(value)\" is additive")
        }
    }

    /// `atoi("%")` is 0, and two skins depend on that answer — corneramp_redux and Shield_Amp ship a
    /// literal `relatw="%"`. A non-numeric value must stay absolute.
    func testANonNumericValueStaysAbsolute() {
        for value in ["%", "", "none", "false", "no", "abc"] {
            let spec = WasabiGeometrySpec(attributes: ["w": "10", "relatw": value])
            XCTAssertEqual(spec.resolve(in: parent).width, 10, "relatw=\"\(value)\" is absolute")
        }
    }

    func testZeroAndAbsentStayAbsolute() {
        XCTAssertEqual(WasabiGeometrySpec(attributes: ["w": "10", "relatw": "0"])
            .resolve(in: parent).width, 10)
        XCTAssertEqual(WasabiGeometrySpec(attributes: ["w": "10"]).resolve(in: parent).width, 10)
    }

    /// The spellings that were already accepted keep working — they are not numbers, so they need
    /// their own branch ahead of the `atoi`.
    func testTheWordFormsStillWork() {
        for value in ["true", "yes", "TRUE", "Yes", " 1 "] {
            let spec = WasabiGeometrySpec(attributes: ["w": "10", "relatw": value])
            XCTAssertEqual(spec.resolve(in: parent).width, 310, "relatw=\"\(value)\" is relative")
        }
    }

    /// `atoi` takes the leading integer rather than refusing the whole string, which is what
    /// distinguishes it from `Int(_:)`.
    func testALeadingIntegerIsTakenTheWayAtoiTakesIt() {
        XCTAssertEqual(WasabiGeometrySpec(attributes: ["w": "10", "relatw": "1px"])
            .resolve(in: parent).width, 310)
        XCTAssertEqual(WasabiGeometrySpec(attributes: ["w": "10", "relatw": "0px"])
            .resolve(in: parent).width, 10)
    }

    /// The position flags go through the same reader, so they split the same way: `2` is a
    /// percentage of the parent's span, every other non-zero value adds it.
    func testThePositionFlagsUseTheSameRule() {
        let spec = WasabiGeometrySpec(attributes: ["x": "5", "y": "6", "relatx": "2", "relaty": "5"])
        let resolved = spec.resolve(in: parent)
        XCTAssertEqual(resolved.x, 25, "parent.x + 5% of the parent width")
        XCTAssertEqual(resolved.y, 226, "parent.y + 6 + parent.height")
    }
}
