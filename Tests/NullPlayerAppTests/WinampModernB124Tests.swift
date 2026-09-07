import XCTest
@testable import NullPlayer

/// B124 — a MAKI object must never compare equal to NULL.
///
/// Reported 2026-09-04 against **cPro2 Dark Aluminum** as "the seek bar is in the wrong place at the
/// top and other details are off", with the author's own reference render alongside. The whole info
/// band — title, artist, seek fill, beat visualization, time and bitrate — drew *on top of* the
/// titlebar, and a 28px dead strip opened underneath it above the SUI.
///
/// The cause was one missing case in the `==` / `!=` opcode. `MakiValue.object`'s `stringValue` is
/// `""` and so is `.null`'s, so the string fallback answered **equal** for every object compared
/// against NULL. That is not a corner case: `getLayout` legitimately answers NULL for a layout the
/// window has not switched to yet — Winamp creates them on demand, and `isLayoutCreated` models it —
/// and skins branch on exactly that. ClassicPro engine two's `two/scripts/layout.m` opens
///
///     System.onShowLayout(Layout _layout){
///         if(shade == NULL) shade = player.getLayout("shade");
///         if(_layout==shade && normal.isVisible()){ saveSkinPos(); }
///         else if(_layout==normal && !shade.isVisible()){ fullScreen(fullscreen); } // On cold start
///     }
///
/// so the *normal* layout matched the shade branch, and `fullScreen()` — the sole cold-start caller
/// that places `two.screen` — never ran. `WINAMP_MODERN_TRACE_MAKI=1` named it in four lines: the
/// handler entered, called `getLayout(shade)`, called `normal.isVisible()`, and jumped straight into
/// `saveSkinPos` without ever asking `shade.isVisible()`.
///
/// The `!=` half was wrong in the mirror image, and reaches far more skins: `x != NULL` was
/// permanently **false**, so every `while (t != NULL)` walk exited before its first iteration
/// (ClassicPro's `CproTabs.m` is built out of them) and every `if (x != NULL)` guard was skipped.
/// The corpus sweep for this fix caught Big Bento Modern's Windows 10 edition drawing the *restore*
/// glyph on a window that was not maximized, from precisely such a guard.
final class WinampModernB124Tests: XCTestCase {

    private func object(_ id: UInt64) -> MakiValue {
        .object(MakiObjectReference(.gui(WasabiObjectID(rawValue: id))))
    }

    // MARK: - The report

    /// The defect itself: a live object is not NULL, in either argument order.
    func testObjectIsNeverEqualToNull() {
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(object(1), .null))
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(.null, object(1)))
    }

    /// `NULL` has no literal of its own in MAKI — it compiles to integer 0 — so an object compared
    /// against the *written* `NULL` takes this path rather than the one above.
    func testObjectIsNeverEqualToTheNullLiteral() {
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(object(1), .integer(0)))
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(.integer(0), object(1)))
    }

    /// cPro2's branch, reduced to the comparison that decides it: the argument is the normal layout
    /// and `shade` is still null, so this must be false and the handler must fall through to the
    /// `else if` that calls `fullScreen()`.
    func testColdStartLayoutDoesNotMatchAnUncreatedShadeLayout() {
        let normal = object(10)
        let shadeStillNull = MakiValue.null
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(normal, shadeStillNull))
    }

    // MARK: - What must not move

    /// Identity still decides two objects — the case the fix is ordered after.
    func testTwoObjectsCompareByIdentity() {
        XCTAssertTrue(MakiInterpreter.valuesAreEqual(object(7), object(7)))
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(object(7), object(8)))
    }

    /// NULL is still NULL, and still equal to the integer 0 it compiles from.
    func testNullComparisonsAreUnchanged() {
        XCTAssertTrue(MakiInterpreter.valuesAreEqual(.null, .null))
        XCTAssertTrue(MakiInterpreter.valuesAreEqual(.null, .integer(0)))
        XCTAssertTrue(MakiInterpreter.valuesAreEqual(.integer(0), .null))
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(.null, .integer(1)))
    }

    /// Strings are still matched case-insensitively, which is how Wasabi compares them.
    func testStringComparisonIsUnchanged() {
        XCTAssertTrue(MakiInterpreter.valuesAreEqual(.string("Normal"), .string("normal")))
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(.string("normal"), .string("shade")))
    }

    /// An empty string is not an object, even though both render as `""`. This is the pair the old
    /// string fallback confused, and the reason the object cases have to come first.
    func testEmptyStringIsNotAnObject() {
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(object(1), .string("")))
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(.string(""), object(1)))
    }

    /// Numbers still compare by value across the kinds MAKI mixes freely.
    func testNumericComparisonIsUnchanged() {
        XCTAssertTrue(MakiInterpreter.valuesAreEqual(.integer(28), .integer(28)))
        XCTAssertFalse(MakiInterpreter.valuesAreEqual(.integer(28), .integer(98)))
        XCTAssertTrue(MakiInterpreter.valuesAreEqual(.boolean(true), .boolean(true)))
    }
}
