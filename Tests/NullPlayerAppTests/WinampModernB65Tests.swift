import XCTest
@testable import NullPlayer

/// B65 — a division by zero abandoned the whole handler.
///
/// MAKI's `/` is IEEE division, so Winamp gets infinity (or NaN for 0/0) and runs on; opcode 67 threw
/// `invalidScript` instead. Shield_Amp's and Ebonite's `OneDirectionText` songtickers divide by an
/// unregistered config attribute in `onScriptLoaded` and never initialised, and cPro2's InfoViewer
/// lost its `onAction`/`onResize`. The divide now answers IEEE and the warning is reported, not thrown.
final class WinampModernB65Tests: XCTestCase {
    private final class RecordingDispatcher: MakiMethodDispatching {
        var reported: [WalDiagnostic] = []
        func signature(for method: String, classGUID: String?) -> MakiMethodSignature? { nil }
        func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                    program: MakiProgram) throws -> MakiValue { .null }
        func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
            MakiObjectReference(.system)
        }
        func report(_ diagnostic: WalDiagnostic) { reported.append(diagnostic) }
    }

    func testIntegerDivisionByZeroIsInfinityAndReportedAsAWarning() throws {
        let dispatcher = RecordingDispatcher()
        let value = try run([push(1), push(2), [67], [33]], dispatcher: dispatcher)   // 7 / 0
        XCTAssertEqual(value.doubleValue, .infinity)
        XCTAssertEqual(dispatcher.reported.map(\.severity), [.warning])
        XCTAssertEqual(dispatcher.reported.first?.message, "MAKI division by zero.")
    }

    func testZeroOverZeroIsNaN() throws {
        let value = try run([push(2), push(3), [67], [33]], dispatcher: RecordingDispatcher())
        XCTAssertTrue(value.doubleValue.isNaN)
        // Stored into an Int, NaN reads as 0 rather than trapping.
        XCTAssertEqual(value.integerValue, 0)
    }

    /// The point of the item: the instructions after the divide still run.
    func testTheHandlerCarriesOnPastTheDivide() throws {
        let value = try run([push(1), push(2), [67], [2], push(1), [33]], dispatcher: RecordingDispatcher())
        XCTAssertEqual(value.integerValue, 7)
    }

    /// Integer modulo has no IEEE answer, so it stays fail-closed.
    func testModuloByZeroStillThrows() {
        XCTAssertThrowsError(try run([push(1), push(2), [68], [33]], dispatcher: RecordingDispatcher()))
    }

    // MARK: - Bytecode fixtures

    private func run(_ parts: [[UInt8]], dispatcher: RecordingDispatcher) throws -> MakiValue {
        let program = try MakiBytecodeParser().parse(makeScript(code: Data(parts.joined())),
                                                     source: WalSourceLocation(path: "/b65.maki"))
        return try MakiInterpreter(dispatcher: dispatcher).execute(program: program, at: 0)
    }

    private func push(_ index: UInt32) -> [UInt8] {
        var data = Data([1])
        appendUInt32(index, to: &data)
        return Array(data)
    }

    /// One class, one `onscriptloaded` method; v1 the integer 7, v2 and v3 the integer 0.
    private func makeScript(code: Data) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)

        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))

        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString("onscriptloaded", to: &data)

        appendUInt32(4, to: &data)                                  // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, initial: 7, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, to: &data)

        appendUInt32(0, to: &data)                                  // constants
        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                initial: UInt16 = 0, to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)          // subclass
        appendUInt16(initial, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)                      // global
        data.append(system ? 1 : 0)
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(bytes)
    }
}
