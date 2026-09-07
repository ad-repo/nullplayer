import XCTest
@testable import NullPlayer

/// MAKI has no null literal of its own — `NULL` compiles to a plain integer 0 — so an object-typed
/// variable assigned it held an *integer*. It compared equal to null and read as false, which is why
/// nothing looked wrong until a member access: that instruction fails closed on a non-object owner,
/// and ClassicPro's tab strip opens every tab activation with `closeTab(lastActiveT)` whose first
/// line reads `lastActiveT.ID`. The handler died there, before its `sendAction("show_tab")` and
/// before the strip re-aligned itself.
final class WinampModernMakiNullCoercionTests: XCTestCase {

    func testNullLiteralAssignedToObjectVariableBecomesNull() {
        guard case .null = MakiInterpreter.coerced(.integer(0), to: .object) else {
            return XCTFail("`NULL` stored in an object variable must be null, not integer 0.")
        }
        guard case .null = MakiInterpreter.coerced(.boolean(false), to: .object) else {
            return XCTFail("A false boolean stored in an object variable must be null.")
        }
    }

    /// A *non-zero* integer is not a null literal, and quietly turning one into null would hide a
    /// stack that is not what the instruction thinks it is.
    func testNonZeroIntegerIsNotTreatedAsNull() {
        guard case .integer(7) = MakiInterpreter.coerced(.integer(7), to: .object) else {
            return XCTFail("A non-zero integer must pass through unchanged.")
        }
    }

    /// The coercions that were already there stay: only the object case is new.
    func testExistingPrimitiveCoercionsAreUnchanged() {
        guard case .integer(3) = MakiInterpreter.coerced(.double(3.7), to: .integer) else {
            return XCTFail("A double stored in an integer truncates.")
        }
        guard case .boolean(true) = MakiInterpreter.coerced(.integer(2), to: .boolean) else {
            return XCTFail("A non-zero integer stored in a boolean is true.")
        }
        guard case .integer(0) = MakiInterpreter.coerced(.integer(0), to: .integer) else {
            return XCTFail("An integer target keeps its zero.")
        }
    }
}
