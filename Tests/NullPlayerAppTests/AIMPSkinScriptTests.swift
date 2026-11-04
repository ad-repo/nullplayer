import Foundation
import XCTest
@testable import NullPlayer

/// The FastScript interpreter on synthetic programs, written as the syntax tree AIMP compiles
/// (`.fsxml`, `reference/format.md` § *Scripts*), run against a one-form skin built in memory.
@MainActor
final class AIMPSkinScriptTests: XCTestCase {
    // MARK: - Declarations

    /// `var X: T = value` starts at its value, and a parameter left out takes its default.
    func testInitializersAndParameterDefaults() throws {
        let engine = try Self.run("""
        <program>
          <function><name text="Tries"/>
            <parameters><var><ident text="Name"/><type text="String"/></var>
              <var><ident text="Count"/><type text="Integer"/><init><expr><number text="5"/></expr></init></var></parameters>
            <compoundstmt><assignstmt><dsgn><node text="Result"/></dsgn><expr><dsgn><node text="Count"/></dsgn></expr></assignstmt></compoundstmt>
          </function>
          <procedure><name text="Execute"/>
            <var><ident text="Normalize"/><type text="Boolean"/><init><expr><dsgn><node text="True"/></dsgn></expr></init></var>
            <var><ident text="Plain"/><type text="Integer"/></var>
            <compoundstmt>
              <assignstmt><dsgn><node text="Defaulted"/></dsgn>
                <expr><dsgn><node text="Tries"/><expr><string text="'a'"/></expr></dsgn></expr></assignstmt>
              <assignstmt><dsgn><node text="Given"/></dsgn>
                <expr><dsgn><node text="Tries"/><expr><string text="'a'"/></expr><expr><number text="2"/></expr></dsgn></expr></assignstmt>
              <assignstmt><dsgn><node text="Seen"/></dsgn>
                <expr><dsgn><node text="Normalize"/></dsgn><op text="+"/><dsgn><node text="Plain"/></dsgn></expr></assignstmt>
            </compoundstmt>
          </procedure>
        </program>
        """)
        XCTAssertEqual(engine.state.script.variables["defaulted"], "5")
        XCTAssertEqual(engine.state.script.variables["given"], "2")
        XCTAssertEqual(engine.state.script.variables["seen"], "1", "True plus an uninitialised Integer")
    }

    /// Operators bind as Pascal's do, left to right within a level, a unary one to the operand after it.
    func testExpressionsCompileByPrecedence() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Seen"/></dsgn>
            <expr><number text="10"/><op text="-"/><number text="2"/><op text="*"/><number text="3"/><op text="-"/>
              <op text="unminus"/><number text="1"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Given"/></dsgn>
            <expr><op text="not"/><number text="0"/><op text="="/><number text="1"/></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "5", "10 - 2 * 3 - -1")
        XCTAssertEqual(engine.state.script.variables["given"], "1", "(not 0) = 1")
    }

    /// A tree the compiler does not take is a load-time finding, not a run that stops.
    func testAMalformedTreeDoesNotCompile() throws {
        let unknown = try Self.node("<program><compoundstmt><gotostmt/></compoundstmt></program>")
        XCTAssertThrowsError(try AIMPSkinScript.compile(unknown))
        let dangling = try Self.node("""
        <program><compoundstmt><assignstmt><dsgn><node text="X"/></dsgn><expr><number text="1"/><op text="+"/></expr></assignstmt>
        </compoundstmt></program>
        """)
        XCTAssertThrowsError(try AIMPSkinScript.compile(dangling))
    }

    // MARK: - Entry points

    /// A counter's script gets its state as its `var` parameter, whatever the parameter is called,
    /// and what the script leaves there is the counter's new position.
    func testACounterStateParameterMayHaveAnyName() throws {
        let program = try AIMPSkinScript.compile(Self.node("""
        <program><procedure><name text="Execute"/>
          <parameters><varparams/><var><ident text="ALayout"/><type text="Integer"/></var></parameters>
          <compoundstmt><assignstmt><dsgn><node text="ALayout"/></dsgn>
            <expr><dsgn><node text="ALayout"/></dsgn><op text="+"/><number text="1"/></expr></assignstmt></compoundstmt>
        </procedure></program>
        """))
        XCTAssertEqual(try Self.engine().run(program, statePosition: 2), 3)
    }

    /// A unit with no `Execute` runs its own `begin … end.` block and finishes.
    func testAProgramWithoutExecuteRunsItsBlock() throws {
        let engine = try Self.run("""
        <program><compoundstmt>
          <assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="1"/></expr></assignstmt>
        </compoundstmt><types/></program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "1")
    }

    /// A skin's `except` does not hide what the interpreter cannot do: the run stops, after its
    /// `finally`, and the gap shows.
    func testUnsupportedPassesThroughExcept() throws {
        let program = try AIMPSkinScript.compile(Self.node("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <trystmt>
            <callstmt><dsgn><node text="NoSuchCall"/></dsgn></callstmt>
            <exceptstmt><assignstmt><dsgn><node text="Given"/></dsgn><expr><number text="1"/></expr></assignstmt></exceptstmt>
            <finallystmt><assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="1"/></expr></assignstmt></finallystmt>
          </trystmt>
        </compoundstmt></procedure></program>
        """))
        let engine = try Self.engine()
        XCTAssertThrowsError(try engine.run(program)) { XCTAssertTrue($0 is AIMPSkinScript.Unsupported) }
        XCTAssertEqual(engine.state.script.variables["seen"], "1", "the cleanup ran")
        XCTAssertNil(engine.state.script.variables["given"], "the handler did not")
    }

    // MARK: - Operators

    /// Script arithmetic answers as a binding's `Expression` does: one operator core
    /// (`AIMPSkinExpression.Operator.apply`). `and`, `or`, `xor` are bitwise on whole numbers, as
    /// Pascal's on integers, and so logical on 0 and 1.
    func testOperatorsAnswerAsBindingsDo() throws {
        let cases: [(Double, String, Double)] = [
            (6, "xor", 3), (6, "and", 3), (4, "or", 1), (1, "xor", 1), (1, "and", 0), (7, "div", 2), (7, "mod", 3),
            (-7, "mod", 3), (7, "/", 2), (1, "shl", 3), (16, "shr", 2), (2, "=", 2), (2, "<>", 3), (2, "<=", 1),
        ]
        for (left, op, right) in cases {
            let engine = try Self.run("""
            <program><procedure><name text="Execute"/><compoundstmt>
              <assignstmt><dsgn><node text="Seen"/></dsgn>
                <expr><number text="\(left)"/><op text="\(op.replacingOccurrences(of: "<", with: "&lt;"))"/><number text="\(right)"/></expr></assignstmt>
            </compoundstmt></procedure></program>
            """)
            let binding = try XCTUnwrap(AIMPSkinExpression("value1 \(op) value2")?.evaluate(variables: ["value1": left, "value2": right]))
            XCTAssertEqual(engine.state.script.variables["seen"], AIMPSkinScript.Value.number(binding).string, "\(left) \(op) \(right)")
        }
        XCTAssertEqual(AIMPSkinExpression("6 and 3")?.evaluate(value: 0), 2, "bitwise, not logical")
    }

    /// A zero divisor raises, as Delphi's `EDivByZero` does: the skin's `except` catches it, and the
    /// assignment it stopped does not happen. Uncaught, it ends the run, keeping what ran before it.
    /// A binding's expression gives nil (`AIMPSkinModelTests`).
    func testDivisionByZeroRaisesWhatExceptCatches() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <trystmt>
            <assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="1"/><op text="div"/><number text="0"/></expr></assignstmt>
            <exceptstmt><assignstmt><dsgn><node text="Given"/></dsgn><expr><number text="1"/></expr></assignstmt></exceptstmt>
          </trystmt>
          <assignstmt><dsgn><node text="Defaulted"/></dsgn><expr><number text="1"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Where"/></dsgn><expr><number text="0"/><op text="/"/><number text="0"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Defaulted"/></dsgn><expr><number text="2"/></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["given"], "1", "the handler ran")
        XCTAssertNil(engine.state.script.variables["seen"], "no value assigned")
        XCTAssertEqual(engine.state.script.variables["defaulted"], "1", "uncaught: the run ended there, what it did kept")
        XCTAssertNil(engine.state.script.variables["where"])
    }

    /// Comparisons are numeric when a number meets a number, or text that reads as one; text
    /// against text compares as text, as Delphi's variants do.
    func testComparisonsMeetNumbersAsNumbers() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Seen"/></dsgn><expr><string text="'1.0'"/><op text="="/><number text="1"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Given"/></dsgn><expr><string text="'10'"/><op text="&lt;"/><string text="'9'"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Defaulted"/></dsgn><expr><string text="'a'"/><op text="="/><number text="0"/></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "1", "'1.0' = 1")
        XCTAssertEqual(engine.state.script.variables["given"], "1", "'10' < '9' as text")
        XCTAssertEqual(engine.state.script.variables["defaulted"], "0", "text that is no number is not 0")
    }

    // MARK: - Host calls

    /// A runaway loop of host calls, the costliest steps skins take, stops at the step limit within
    /// a frame at 30 fps: scripts run on the main thread, between frames. Timed in an optimized
    /// build only (`swift test -Xswiftc -O`); a debug build runs it about ten times slower.
    func testRunawayHostCallsStopWithinAFrame() throws {
        let engine = try Self.engine()
        let program = try AIMPSkinScript.compile(Self.node("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <whilestmt><expr><number text="1"/></expr><compoundstmt>
            <assignstmt><dsgn><node text="Where"/></dsgn><expr><dsgn><node text="BindingsGetDataAsText3"/>
              <expr><string text="'prvPlayingFileInfo'"/></expr><expr><string text="'FileInfo'"/></expr>
              <expr><string text="''"/></expr><expr><string text="'%R'"/></expr></dsgn></expr></assignstmt>
          </compoundstmt></whilestmt>
        </compoundstmt></procedure></program>
        """))
        let began = CFAbsoluteTimeGetCurrent()
        XCTAssertThrowsError(try engine.run(program)) { XCTAssertTrue($0 is AIMPSkinScript.Budget.Spent) }
        let spent = (CFAbsoluteTimeGetCurrent() - began) * 1_000
        XCTAssertEqual(engine.budget.steps, AIMPSkinScript.Budget.stepLimit)
        print("AIMP script budget: \(AIMPSkinScript.Budget.stepLimit) host-call steps spent in \(Int(spent)) ms")
        var optimized = true
        assert({ optimized = false; return true }())
        if optimized { XCTAssertLessThan(spent, 1_000 / 30) }
    }

    /// `BindingsGetDataAsText3(source, pin, expression, format)` formats the playing file's tags.
    func testBindingsGetDataAsText3FormatsFileInfo() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Where"/></dsgn><expr><dsgn><node text="BindingsGetDataAsText3"/>
            <expr><string text="'prvPlayingFileInfo'"/></expr><expr><string text="'FileInfo'"/></expr>
            <expr><string text="''"/></expr><expr><string text="'%R'"/></expr></dsgn></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["where"], AIMPSkinPlayerSnapshot.probe.artist)
    }

    /// Calls for player features NullPlayer lacks finish with a neutral answer: the colour dialog
    /// reads as cancelled, switching skins and seeding `Random` do nothing.
    func testHostCallsNullPlayerLacksAreNeutral() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <callstmt><dsgn><node text="Randomize"/></dsgn></callstmt>
          <callstmt><dsgn><node text="ApplySkin"/><expr><string text="'Other'"/></expr></dsgn></callstmt>
          <assignstmt><dsgn><node text="Seen"/></dsgn>
            <expr><dsgn><node text="ExecuteColorPicker"/><expr><number text="0"/></expr></dsgn></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "0")
        XCTAssertTrue(engine.actions.isEmpty)
    }

    /// The effect resets set speed and tempo to 1 and pitch to 0: each moves NullPlayer's speed as
    /// its knob does, so pitch 0 is the knob's middle, normal speed.
    func testPitchMovesTheSpeedAsItsKnobDoes() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <callstmt><dsgn><node text="FindObject"/><expr><string text="'prvTempo'"/></expr><node text="Set"/>
            <expr><string text="'Position'"/></expr><expr><number text="1"/></expr></dsgn></callstmt>
          <callstmt><dsgn><node text="FindObject"/><expr><string text="'prvPitch'"/></expr><node text="Set"/>
            <expr><string text="'Position'"/></expr><expr><number text="0"/></expr></dsgn></callstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.actions, [.speed(1), .setValue(provider: .speed, 0.5)])
    }

    /// AIMP bands that share a NullPlayer band are asked for once, at their mean; a band written
    /// twice counts as its latest.
    func testEqualizerWritesAreAskedForOncePerBand() throws {
        let band = { (aimp: Int) in AIMPSkinPlayerSnapshot.probe.eqBand(aimp: aimp, aimp5: false) }
        let one = try XCTUnwrap((1..<18).first { band($0) == band($0 + 1) }, "no two AIMP bands share a NullPlayer band")
        let first = try XCTUnwrap(band(one)), shared = one + 1
        func write(_ aimp: Int, _ dB: Int) -> String {
            """
            <callstmt><dsgn><node text="FindObject"/><expr><string text="'prvEqualizer'"/></expr><node text="Set"/>
              <expr><string text="'BandValue\(aimp)'"/></expr><expr><number text="\(dB)"/></expr></dsgn></callstmt>
            """
        }
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          \(write(one, 2)) \(write(one, 4)) \(write(shared, 8))
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.actions, [.equalizerBand(first, dB: 6)])
    }

    /// A script docks and undocks forms and moves items: `form.Undock`, `form.Dock`,
    /// `FindObject(a).Parent := FindObject(b)`, and reads where one sits.
    func testDockingAndMovingItems() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <callstmt><dsgn><node text="FindObject"/><expr><string text="'LibraryForm'"/></expr><node text="Undock"/></dsgn></callstmt>
          <callstmt><dsgn><node text="FindObject"/><expr><string text="'PlaylistForm'"/></expr><node text="Dock"/></dsgn></callstmt>
          <assignstmt><dsgn><node text="FindObject"/><expr><string text="'Table'"/></expr><node text="Parent"/></dsgn>
            <expr><dsgn><node text="FindObject"/><expr><string text="'AioHost'"/></expr></dsgn></expr></assignstmt>
          <assignstmt><dsgn><node text="Where"/></dsgn>
            <expr><dsgn><node text="FindObject"/><expr><string text="'Table'"/></expr><node text="Parent"/></dsgn></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.docked, ["LibraryForm": false, "PlaylistForm": true])
        XCTAssertEqual(engine.state.script.parents, ["Table": "AioHost"])
        XCTAssertEqual(engine.state.script.variables["where"], "AioHost")
    }

    // MARK: - Helpers

    private static func node(_ xml: String) throws -> AIMPNode {
        try AIMPNode.parse(Data(xml.utf8), name: "test.xml")
    }

    /// `program` compiled and run once from a fresh state; its results are the skin's variables.
    private static func run(_ program: String) throws -> AIMPSkinScript.Engine {
        let engine = try engine()
        try engine.run(AIMPSkinScript.compile(node(program)))
        return engine
    }

    private static func engine() throws -> AIMPSkinScript.Engine {
        AIMPSkinScript.Engine(skin: try skin(), host: AIMPSkinHostState(player: .probe), state: AIMPSkinState())
    }

    /// A project file (`ACSJ`) holding one main form (empty unless given), any `more` entries, and a
    /// `Schema.xml` declaring the variables the tests read their results from: what a script needs of a skin.
    static func skin(form: String = #"<form name="AIMPMainForm"/>"#, entries more: [(String, String)] = []) throws -> AIMPSkin {
        func utf16LE(_ text: String) -> Data {
            Data([UInt8(text.utf16.count & 0xFF), UInt8(text.utf16.count >> 8)]) + (text.data(using: .utf16LittleEndian) ?? Data())
        }
        func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        let schema = """
        <schema><variables><variable name="Defaulted" value="0"/><variable name="Given" value="0"/><variable name="Seen" value="0"/>
          <variable name="Where" value="" valueType="String"/></variables></schema>
        """
        let entries = [("AIMPMainForm.xml", form), ("Schema.xml", schema)] + more
        // The header (13 bytes), the metadata block (u32 length: name, author, about, no preview),
        // the entry count and the entries.
        let meta = utf16LE("Test") + utf16LE("") + utf16LE("") + [0]
        var data = Data("ACSJ".utf8) + Data(count: 9) + u32(meta.count) + meta + u32(entries.count)
        for (name, text) in entries {
            data += utf16LE(name) + u32(Data(text.utf8).count) + Data(text.utf8)
        }
        return try AIMPSkinLoader.load(data: data)
    }
}
