import XCTest
@testable import NullPlayer

/// Two `mc.exe` outputs the parser refused: the class table with the short 13-byte variable record
/// (header word `0x16`; ten bronze skins' scripts), and a string in the compiler's ANSI code page
/// rather than UTF-8 (five bronze skins).
final class WinampModernMakiLayoutTests: XCTestCase {

    func testClassTableWithShortVariableRecordsParses() throws {
        let program = try MakiBytecodeParser().parse(makeScript(shortVariables: true, methodName: "onscriptloaded"),
                                                     source: WalSourceLocation(path: "/x.maki"))
        XCTAssertEqual(program.classes.count, 1)
        XCTAssertEqual(program.variables.count, 2)
        XCTAssertTrue(program.variables[0].isSystem, "variable 0 is System in the short record")
        XCTAssertTrue(program.variables[1].isGlobal, "the short record's byte is `global`")
    }

    func testAnANSIStringIsReadAsWindows1252() throws {
        let program = try MakiBytecodeParser().parse(makeScript(shortVariables: false, methodName: "caf\u{E9}", ansi: true),
                                                     source: WalSourceLocation(path: "/x.maki"))
        XCTAssertEqual(program.methods.first?.name, "café")
    }

    func testAnAnyVariableParsesAsUntyped() throws {
        let program = try MakiBytecodeParser().parse(makeScript(shortVariables: false, methodName: "x", secondType: 8),
                                                     source: WalSourceLocation(path: "/x.maki"))
        XCTAssertEqual(program.variables[1].declaredKind, .null)
    }

    // MARK: - Fixture

    private func makeScript(shortVariables: Bool, methodName: String, ansi: Bool = false,
                            secondType: UInt8 = MakiValueKind.integer.rawValue) -> Data {
        var data = Data([0x46, 0x47])
        append16(0x0403, &data)
        append32(shortVariables ? 0x16 : 0x17, &data)
        append32(1, &data)                                      // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        append32(1, &data)                                      // methods
        append16(0, &data)
        append16(0, &data)
        let name = ansi ? methodName.data(using: .windowsCP1252)! : Data(methodName.utf8)
        append16(UInt16(name.count), &data)
        data.append(name)
        append32(2, &data)                                      // variables
        for (index, object) in [true, false].enumerated() {
            data.append(index == 0 ? 0 : secondType)
            data.append(object ? 1 : 0)
            for _ in 0..<5 { append16(0, &data) }             // subclass, two initials, two unused
            if shortVariables { data.append(1) }                 // the one `global` byte
            else { data.append(object ? 1 : 0); data.append(object ? 1 : 0) } // global, system
        }
        append32(0, &data)                                      // constants
        append32(0, &data)                                      // bindings
        append32(0, &data)                                      // code
        return data
    }

    private func append16(_ value: UInt16, _ data: inout Data) {
        data.append(UInt8(value & 0xff)); data.append(UInt8(value >> 8))
    }

    private func append32(_ value: UInt32, _ data: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> UInt32(shift)) & 0xff)) }
    }
}
