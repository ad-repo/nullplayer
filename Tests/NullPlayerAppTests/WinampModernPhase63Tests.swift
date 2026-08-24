import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 63 (backlog B33) — an unclosed tag at end of file no longer kills the whole skin.
///
/// `Shield_Amp` was the only one of the 30 installed skins that failed outright: its
/// `opensource_notifier/notifier.xml`, pulled in by an `<include>` from `skin.xml`, opens two
/// `<container>`s, closes one, and ends on a `<script file="…"/>`. The skin's own bug — but Winamp
/// loads it, and `WalLenientXMLParser` is documented lenient, so the engine rule applies: malformed
/// optional input **warns, it does not fail**.
///
/// Nothing is lost by tolerating it. A node is attached to its parent (or to `roots`) when it
/// *opens*, not when it closes, so by the time the EOF check runs the unclosed tag already holds all
/// of its children and every sibling written after it — which is the first thing these tests pin.
/// `maximumDepth` still bounds how much can be left open, so nothing about the sandbox changes, and
/// the strict cases below stay strict.
final class WinampModernPhase63Tests: XCTestCase {

    // MARK: - The tree an unclosed tag leaves behind

    /// The shape of `notifier.xml`, reduced: a closed container, then one that never closes and whose
    /// children run to the end of the file. Both must be present, and the second must own its child.
    func testUnclosedTagAtEndOfFileWarnsAndKeepsTheWholeTree() throws {
        let xml = """
        <container id="closed"><layout id="normal" w="10" h="10"/></container>
        <container id="never.closed">
          <layout id="normal" w="20" h="20"/>
          <script file="notifier.maki"/>
        """

        let parsed = try WalLenientXMLParser().parse(xml, path: "/notifier.xml")

        XCTAssertEqual(parsed.roots.map { $0.attribute("id") }, ["closed", "never.closed"])
        XCTAssertEqual(parsed.roots[1].children.map { $0.name.lowercased() }, ["layout", "script"])

        XCTAssertEqual(parsed.diagnostics.count, 1)
        let warning = try XCTUnwrap(parsed.diagnostics.first)
        XCTAssertEqual(warning.code, .malformedXML)
        XCTAssertEqual(warning.severity, .warning)
        XCTAssertTrue(warning.message.contains("<container>"), warning.message)
        // The diagnostic points at the *open* tag, which is the only place worth looking.
        XCTAssertEqual(warning.location?.line, 2)
    }

    /// Well-formed markup gains nothing: no diagnostic, and the same tree as before.
    func testBalancedMarkupProducesNoDiagnostic() throws {
        let parsed = try WalLenientXMLParser()
            .parse("<container id=\"main\"><layout id=\"normal\"/></container>", path: "/skin.xml")

        XCTAssertTrue(parsed.diagnostics.isEmpty)
        XCTAssertEqual(parsed.roots.count, 1)
    }

    /// Several tags left open is still one diagnostic, naming the innermost and how many there are —
    /// a deeply truncated file must not emit a warning per level.
    func testSeveralTagsLeftOpenReportOnce() throws {
        let parsed = try WalLenientXMLParser()
            .parse("<container id=\"a\"><layout id=\"b\"><group id=\"c\">", path: "/t.xml")

        XCTAssertEqual(parsed.diagnostics.count, 1)
        let message = try XCTUnwrap(parsed.diagnostics.first?.message)
        XCTAssertTrue(message.contains("<group>"), message)
        XCTAssertTrue(message.contains("3 tags left open"), message)
    }

    // MARK: - What stays a hard failure

    /// A `</foo>` matching nothing on the stack is a different defect from a truncated file — the
    /// tree it would leave is genuinely ambiguous, and no skin in the corpus does it. It still throws.
    func testUnexpectedClosingTagStillThrows() {
        XCTAssertThrowsError(try WalLenientXMLParser().parse("<a></b></a>", path: "/t.xml")) { error in
            XCTAssertEqual((error as? WalFailure)?.diagnostics.first?.code, .malformedXML)
        }
    }

    /// A tag whose own `>` never arrives is truncation *mid-tag*, where the attributes are only half
    /// read. Unchanged, along with unterminated comments, declarations and attribute values.
    func testUnterminatedTagStillThrows() {
        XCTAssertThrowsError(try WalLenientXMLParser().parse("<container id=\"a\"", path: "/t.xml"))
        XCTAssertThrowsError(try WalLenientXMLParser().parse("<!-- forever", path: "/t.xml"))
        XCTAssertThrowsError(try WalLenientXMLParser().parse("<a b=\"unclosed>", path: "/t.xml"))
    }

    /// The depth bound is what keeps "leave everything open" from being a resource attack, so it has
    /// to fire *before* the new EOF tolerance can see the stack.
    func testDepthBoundStillFiresOnAnUnclosedRun() {
        let xml = String(repeating: "<g>", count: 40)
        XCTAssertThrowsError(try WalLenientXMLParser(maximumDepth: 8).parse(xml, path: "/t.xml")) { error in
            XCTAssertEqual((error as? WalFailure)?.diagnostics.first?.code, .xmlDepthExceeded)
        }
    }

    // MARK: - End to end, through the loader

    /// The warning has to survive include expansion and reach the loaded skin's diagnostics, or a
    /// skin that silently tolerated a truncated file would be indistinguishable from a clean one.
    func testATruncatedIncludeLoadsTheSkinAndReportsTheWarning() throws {
        let skin = """
        <WasabiXML>
          <include file="xml/truncated.xml"/>
          <container id="main"><layout id="normal" w="120" h="60"/></container>
        </WasabiXML>
        """
        let truncated = """
        <container id="notifier" default_visible="0">
          <layout id="normal" w="80" h="40"/>
        """
        let archive = try makeArchive(xml: skin, extraFiles: ["xml/truncated.xml": Data(truncated.utf8)])

        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: archive)
        defer { loaded.teardown() }

        XCTAssertTrue(loaded.runtime.graph.roots.contains { $0.xmlID?.lowercased() == "main" })
        XCTAssertTrue(loaded.runtime.graph.roots.contains { $0.xmlID?.lowercased() == "notifier" },
                      "the unclosed container is a real container, not a casualty of its own bug")

        let unclosed = loaded.runtime.diagnostics.filter {
            $0.code == .malformedXML && $0.message.contains("Unclosed")
        }
        XCTAssertEqual(unclosed.count, 1)
        XCTAssertEqual(unclosed.first?.severity, .warning)
        let path = unclosed.first?.location?.path
        XCTAssertEqual(path?.hasSuffix("/xml/truncated.xml"), true, path ?? "no location")
    }

    // MARK: - Helpers

    private func makeArchive(xml: String, extraFiles: [String: Data] = [:]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase63Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase63-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8))] + extraFiles.map({ ($0.key, $0.value) }) {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }
}
