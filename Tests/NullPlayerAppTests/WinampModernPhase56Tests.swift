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
/// **A percentage reading fits some of that and is wrong.** `99`/`100` and `85`/`93` look like
/// percentages until Ebonite's `group w="0" h="0" relatw="2"` — 0% would collapse the group, where
/// the plain relative reading gives the ordinary fill-the-parent idiom — and until `relatw="5"`,
/// which is not a percentage at all. Non-zero-means-relative fits every case in the corpus.
final class WinampModernPhase56Tests: XCTestCase {

    private let parent = WasabiRect(x: 10, y: 20, width: 300, height: 200)

    /// The defect exactly as it shipped: Big Bento's backdrop wants to be *oversized*, and read as
    /// absolute it is a small crisp second copy of the cover instead.
    func testATwoIsRelativeSoAnOversizedBackdropIsOversized() {
        let spec = WasabiGeometrySpec(attributes: [
            "x": "0", "y": "0", "w": "99", "h": "100", "relatw": "2", "relath": "2",
        ])
        let resolved = spec.resolve(in: parent)
        XCTAssertEqual(resolved.width, 399, "parent width + 99, not a literal 99")
        XCTAssertEqual(resolved.height, 300, "parent height + 100, not a literal 100")
    }

    /// The case that rules out reading the number as a percentage: 0% would collapse Ebonite's group
    /// to nothing, where the relative reading gives it the parent's box.
    func testAZeroSizeWithRelativeTwoFillsTheParent() {
        let spec = WasabiGeometrySpec(attributes: [
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "2", "relath": "2",
        ])
        XCTAssertEqual(spec.resolve(in: parent).width, 300)
        XCTAssertEqual(spec.resolve(in: parent).height, 200)
    }

    /// The_Nokia_5220 ships `relatw="5"`. Nothing about 5 is special; it is simply non-zero.
    func testAnyNonZeroNumberIsRelative() {
        for value in ["2", "3", "5", "17", "-1"] {
            let spec = WasabiGeometrySpec(attributes: ["w": "10", "relatw": value])
            XCTAssertEqual(spec.resolve(in: parent).width, 310, "relatw=\"\(value)\" is relative")
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

    /// The position flags go through the same reader, so they change with it.
    func testThePositionFlagsUseTheSameRule() {
        let spec = WasabiGeometrySpec(attributes: ["x": "5", "y": "6", "relatx": "2", "relaty": "5"])
        let resolved = spec.resolve(in: parent)
        XCTAssertEqual(resolved.x, 315, "parent.x + 5 + parent.width")
        XCTAssertEqual(resolved.y, 226, "parent.y + 6 + parent.height")
    }
}
