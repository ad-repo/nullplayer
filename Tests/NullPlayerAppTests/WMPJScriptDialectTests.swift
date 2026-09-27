import Foundation
import JavaScriptCore
import XCTest
@testable import NullPlayer

/// JScript's live `for-in`, which is the dialect difference that decides whether the WMP9 skin
/// family can reach its compact view at all (W86).
///
/// The first test is the one that matters and it is written as the corpus writes it: a dispatcher
/// that enumerates an array while a finished entry's `eval`'d continuation appends the next one.
/// Under JavaScriptCore's snapshot enumeration the appended entry is never visited; under JScript's
/// it is, and so is Windows Media Player's.
final class WMPJScriptDialectTests: XCTestCase {

    /// Evaluates a program the way `WMPScriptContext` does — prelude raw, program rewritten — and
    /// answers one expression.
    private func evaluate(_ program: String, answer: String) throws -> String {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        context.evaluateScript(WMPJScriptDialect.prelude)
        context.evaluateScript(WMPJScriptDialect.liveForIn(program))
        let value = context.evaluateScript(WMPJScriptDialect.liveForIn(answer))
        if let failure { XCTFail("script error: \(failure)"); return "" }
        return try XCTUnwrap(value?.toString())
    }

    /// **The WMP9 compact-mode chain, reduced.** `corona_tiny.js`'s `TimerDispatch` enumerates
    /// `g_grpTimerEvents`, and a finished event's `end` string registers the next one onto that same
    /// array. Snapshot enumeration drops it; the skin's whole compact view and its only way back to
    /// the player are that dropped event.
    func testAnEntryAppendedDuringEnumerationIsVisited() throws {
        let program = """
        var queue = ["first"];
        var survivors = [];
        var visited = [];
        for (item in queue) {
            visited[visited.length] = queue[item];
            if (queue[item] == "first") { queue[queue.length] = "chained"; }
            else { survivors[survivors.length] = queue[item]; }
        }
        """
        XCTAssertEqual(try evaluate(program, answer: "visited.join(',')"), "first,chained")
        XCTAssertEqual(try evaluate(program, answer: "survivors.join(',')"), "chained")
    }

    /// The same program without the rewrite, so the test above is known to be measuring the rewrite
    /// and not something that happened to pass anyway.
    func testJavaScriptCoreAloneDropsTheAppendedEntry() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var queue = ["first"];
        var visited = [];
        for (item in queue) {
            visited[visited.length] = queue[item];
            if (queue[item] == "first") { queue[queue.length] = "chained"; }
        }
        """)
        XCTAssertEqual(context.evaluateScript("visited.join(',')")?.toString(), "first",
                       "if this ever reports 'first,chained', JavaScriptCore changed and the "
                       + "rewrite may no longer be needed")
    }

    func testAVarHeadStaysADeclarationAndTheLoopVariableSurvives() throws {
        let program = """
        var seen = [];
        var object = { a: 1, b: 2 };
        for (var key in object) { seen[seen.length] = key; }
        """
        XCTAssertEqual(try evaluate(program, answer: "seen.join(',')"), "a,b")
    }

    /// A bare head leaves JScript's implicit global in place; a skin that reads the loop variable
    /// after the loop still finds it.
    func testABareHeadKeepsItsImplicitGlobal() throws {
        let program = "var object = { only: 1 }; for (key in object) { }"
        XCTAssertEqual(try evaluate(program, answer: "key"), "only")
    }

    func testBreakContinueAndLabelsStillWork() throws {
        let program = """
        var out = [];
        var object = { a: 1, b: 2, c: 3, d: 4 };
        outer:
        for (var key in object) {
            if (key == "b") continue;
            if (key == "d") break outer;
            out[out.length] = key;
        }
        """
        XCTAssertEqual(try evaluate(program, answer: "out.join(',')"), "a,c")
    }

    func testABodyWithNoBracesStillBinds() throws {
        let program = "var out = []; var o = { a: 1, b: 2 }; for (var k in o) out[out.length] = k;"
        XCTAssertEqual(try evaluate(program, answer: "out.join(',')"), "a,b")
    }

    func testNestedLoopsGetSeparateEnumerators() throws {
        let program = """
        var pairs = [];
        var outer = { a: 1, b: 2 };
        var inner = { x: 1, y: 2 };
        for (var i in outer) { for (var j in inner) { pairs[pairs.length] = i + j; } }
        """
        XCTAssertEqual(try evaluate(program, answer: "pairs.join(',')"), "ax,ay,bx,by")
    }

    /// A three-clause `for` is not a `for-in` and must come through untouched — including one whose
    /// own body or condition contains the letters `in`.
    func testAnOrdinaryForIsNotRewritten() {
        let source = "for (var i = 0; i < index.length; i++) { total += index[i]; }"
        XCTAssertEqual(WMPJScriptDialect.liveForIn(source), source)
    }

    func testWordsContainingInAreNotSplitPoints() {
        let source = "for (var i = 0; i < 3; i++) { inside(); }"
        XCTAssertEqual(WMPJScriptDialect.liveForIn(source), source)
        XCTAssertFalse(WMPJScriptDialect.liveForIn("for (interval in list) {}").contains("terval in"))
    }

    /// String bodies, comments and regular-expression literals are not code. A rewrite driven by a
    /// textual search fires inside `metadata.js`'s string tables.
    func testLiteralsAndCommentsAreNotRewritten() {
        for source in ["var help = \"for (a in b)\";",
                       "var help = 'for (a in b)';",
                       "// for (a in b)\nvar x = 1;",
                       "/* for (a in b) */ var x = 1;",
                       "var pattern = /for (a in b)/; var y = 2;"] {
            XCTAssertEqual(WMPJScriptDialect.liveForIn(source), source, "rewrote inside a literal: \(source)")
        }
    }

    /// **The corpus is CRLF, and Swift folds `"\r\n"` into one `Character` that is not `"\n"`.**
    /// A line-comment scanner comparing against `"\n"` therefore runs to the end of the file, and
    /// since every script in this corpus opens with a `//` banner the rewrite silently did nothing
    /// at all — `changed=false` on the real `corona_tiny.js` while all the LF-only tests above
    /// passed. That is the shape of the bug, so this is the shape of the test.
    func testACRLFProgramIsStillRewrittenPastItsOpeningComment() throws {
        let program = "// timed event dispatcher\r\n"
            + "var queue = [\"first\"];\r\n"
            + "var visited = [];\r\n"
            + "for (item in queue) {\r\n"
            + "\tvisited[visited.length] = queue[item];\r\n"
            + "\tif (queue[item] == \"first\") { queue[queue.length] = \"chained\"; }\r\n"
            + "}\r\n"
        XCTAssertNotEqual(WMPJScriptDialect.liveForIn(program), program, "CRLF source was not rewritten")
        XCTAssertEqual(try evaluate(program, answer: "visited.join(',')"), "first,chained")
    }

    /// A CR-only file — the other line ending the loader already has to tolerate.
    func testACROnlyProgramIsStillRewritten() throws {
        let program = "// banner\rvar o = { a: 1 };\rvar out = [];\rfor (var k in o) { out[out.length] = k; }\r"
        XCTAssertEqual(try evaluate(program, answer: "out.join(',')"), "a")
    }

    func testAProgramWithNoForInIsReturnedUnchanged() {
        let source = "function f() { return 1; }\nvar a = f();\n"
        XCTAssertEqual(WMPJScriptDialect.liveForIn(source), source)
    }

    /// Enumerating something that is not an object is what a starved skin does on its first tick,
    /// and it must not throw where JScript quietly does nothing.
    func testEnumeratingNullOrUndefinedIsEmptyRatherThanAThrow() throws {
        let program = """
        var count = 0;
        var nothing = null;
        for (var k in nothing) { count++; }
        for (var j in undefined) { count++; }
        """
        XCTAssertEqual(try evaluate(program, answer: "count"), "0")
    }

    /// `seen` is a null-prototype map for this reason.
    func testAKeyNamedForAnObjectPrototypeMemberIsStillVisited() throws {
        let program = """
        var out = [];
        var object = {}; object["constructor"] = 1; object["toString"] = 2;
        for (var k in object) { out[out.length] = k; }
        """
        XCTAssertEqual(try evaluate(program, answer: "out.join(',')"), "constructor,toString")
    }
}
