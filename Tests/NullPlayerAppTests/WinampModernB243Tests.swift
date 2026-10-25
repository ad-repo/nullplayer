import XCTest
@testable import NullPlayer

/// B243 — a MAKI method's arity and its body are declared once, side by side, in their concern's
/// table, and `signature(for:classGUID:)` is derived from those tables.
///
/// A name several tables answer (`getposition` on `System` and on a slider, `stop` on `System`, a
/// timer and an animated layer) is declared in each of them, and the interpreter unwinds the stack by
/// one arity whichever body ends up answering. So the declarations have to agree, or the derived
/// table silently keeps whichever it read first.
final class WinampModernB243Tests: XCTestCase {
    func testEveryNameCarriesOneArityPerReceiverClass() {
        var seen: [String: MakiMethodDeclaration] = [:]
        for declaration in WinampModernScriptSignatures.tables.joined() {
            let key = (declaration.declaringClass ?? "*") + "." + declaration.name
            guard let first = seen[key] else {
                seen[key] = declaration
                continue
            }
            XCTAssertEqual(first.signature.argumentCount, declaration.signature.argumentCount, key)
        }
    }

    /// A table pulled back onto another receiver keeps every declaration, so ClassicProFile answers a
    /// script-made object with the arities it answers `System` with, and a TreeItem's reach the
    /// derived table through the dynamic list rather than a hand-kept one.
    func testAPulledBackTableKeepsItsDeclarations() {
        typealias R = WinampModernScriptRuntime
        let pulled = R.classicProFileMethods.pulledBack { (_: MakiDynamicReceiver) in () }
        let sorted = { (table: [MakiMethodDeclaration]) in
            table.map { "\($0.name)/\($0.signature.argumentCount)" }.sorted()
        }
        XCTAssertEqual(sorted(pulled.declarations), sorted(R.classicProFileMethods.declarations))
        XCTAssertTrue(R.dynamicFamilies.contains { $0["findfiles"] != nil })
        XCTAssertNotNil(WinampModernScriptSignatures.signature(for: "explorefile", classGUID: nil))
        XCTAssertNotNil(WinampModernScriptSignatures.signature(for: "setlabel", classGUID: nil),
                        "a TreeItem arity reaches the derived table through the dynamic list")
    }

    /// The tables are lowercased-name keyed, because that is what `invoke` looks them up by.
    func testEveryDeclaredNameIsLowercased() {
        for declaration in WinampModernScriptSignatures.tables.joined() {
            XCTAssertEqual(declaration.name, declaration.name.lowercased())
        }
    }
}
