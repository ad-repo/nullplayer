import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 76 — BB29, the time display in the four Big Bento Modern variants. Reported live: the
/// elapsed time and the `/` beside it were neither level nor apart (`1:13/ 4:05`).
///
/// Two independent causes, both in the shared text path:
///
/// 1. **`valign="middle"` is not one of the three spellings Wasabi knows**, and an unrecognised
///    value reads as `top` — only an *absent* `valign` centres. Bento's two small readouts declare
///    `middle` and `songticker.maki` then pushes each of them down by 4px, which is exactly the gap
///    between a 21px line and the top of the 30px box it sits in. Read `middle` as `center` and that
///    correction lands on top of a centring already done, putting both times 4px below the `/`
///    between them — which declares no `valign` at all.
///
/// 2. **A clock is a run of fields, not a string.** The colon carries a cell of its own
///    (`timecolonwidth`), the leading field holds room for the two digits it can reach, and the run
///    keeps clear of the box edge it aligns against. Bento's elapsed readout is right-aligned in a
///    box the `/`'s own box overlaps by four pixels, so drawn flush it lands on top of it.
final class WinampModernPhase76Tests: XCTestCase {

    // MARK: - valign

    func testAbsentValignCentres() throws {
        let readout = try object(attributes: [:])
        XCTAssertEqual(WasabiTextMetrics.verticalAlignment(of: readout), .center)
    }

    func testDeclaredValignIsDecoded() throws {
        XCTAssertEqual(WasabiTextMetrics.verticalAlignment(of: try object(attributes: ["valign": "top"])),
                       .top)
        XCTAssertEqual(WasabiTextMetrics.verticalAlignment(of: try object(attributes: ["valign": "center"])),
                       .center)
        XCTAssertEqual(WasabiTextMetrics.verticalAlignment(of: try object(attributes: ["valign": "bottom"])),
                       .bottom)
    }

    /// The whole of BB29's vertical half: `middle` is not `center`.
    func testUnrecognisedValignReadsAsTop() throws {
        XCTAssertEqual(WasabiTextMetrics.verticalAlignment(of: try object(attributes: ["valign": "middle"])),
                       .top)
        XCTAssertEqual(WasabiTextMetrics.verticalAlignment(of: try object(attributes: ["valign": ""])),
                       .top)
    }

    /// Read as `center`, a `middle` readout in Bento's own geometry sits a whole 4px below one that
    /// declares nothing — the two are meant to share a baseline.
    func testMiddleAndAnUndeclaredNeighbourShareABaseline() throws {
        let font = NSFont.systemFont(ofSize: 17.6)
        let line = font.ascender - font.descender
        let box = CGFloat(30)
        // The skin's script moves the `middle` readout down by this much, and the separator not at all.
        let scriptOffset = ((box - line) / 2).rounded()
        let middle = WasabiTextMetrics.verticalAlignment(of: try object(attributes: ["valign": "middle"]))
            .offset(cell: line, in: box) + scriptOffset
        let neighbour = WasabiTextMetrics.verticalAlignment(of: try object(attributes: [:]))
            .offset(cell: line, in: box)
        XCTAssertEqual(middle, neighbour, accuracy: 1)
    }

    // MARK: - The clock run

    func testOnlyATimeDisplayLaysOutAsAClock() throws {
        let font = NSFont.systemFont(ofSize: 20)
        for display in ["time", "timeelapsed", "songlength"] {
            XCTAssertNotNil(WasabiTextMetrics.clockRun(of: try object(attributes: ["display": display]),
                                                       text: "1:13", font: font), display)
        }
        XCTAssertNil(WasabiTextMetrics.clockRun(of: try object(attributes: ["display": "songtitle"]),
                                                text: "1:13", font: font),
                     "a title that happens to contain a colon is still a string")
        XCTAssertNil(WasabiTextMetrics.clockRun(of: try object(attributes: ["display": "time"]),
                                                text: "", font: font))
    }

    func testTheColonTakesTheCellTheSkinDeclares() throws {
        let font = NSFont.systemFont(ofSize: 20)
        let readout = try object(attributes: ["display": "timeelapsed", "timecolonwidth": "9"])
        let run = try XCTUnwrap(WasabiTextMetrics.clockRun(of: readout, text: "1:13", font: font))
        let colon = try XCTUnwrap(run.cells.first { $0.text == ":" })
        XCTAssertEqual(colon.width, 9)
        XCTAssertTrue(colon.centred, "a cell wider than the glyph must not leave it leaning on one side")
        XCTAssertEqual(run.cells.map(\.text), ["1", ":", "13"])
    }

    /// Undeclared, the run measures exactly as the string does — nothing moves in a skin that never
    /// asked for a clock in columns.
    func testWithoutADeclaredColonTheRunMeasuresAsTheString() throws {
        let font = NSFont.systemFont(ofSize: 20)
        let readout = try object(attributes: ["display": "time"])
        let run = try XCTUnwrap(WasabiTextMetrics.clockRun(of: readout, text: "1:13", font: font))
        XCTAssertEqual(run.width, ("1:13" as NSString).size(withAttributes: [.font: font]).width,
                       accuracy: 0.01)
        XCTAssertEqual(run.layoutWidth, run.width, accuracy: 0.01)
    }

    /// The leading field holds two digits' room whether or not it needs them, so a clock rolling from
    /// `9:59` to `10:00` grows into space it was already holding instead of jumping a column sideways.
    func testTheLeadingFieldHoldsRoomForTwoDigits() throws {
        let font = NSFont.systemFont(ofSize: 20)
        let readout = try object(attributes: ["display": "timeelapsed", "timecolonwidth": "5"])
        let short = try XCTUnwrap(WasabiTextMetrics.clockRun(of: readout, text: "1:13", font: font))
        let long = try XCTUnwrap(WasabiTextMetrics.clockRun(of: readout, text: "10:13", font: font))
        XCTAssertEqual(short.layoutWidth, long.layoutWidth, accuracy: 0.01,
                       "both values are aligned by the same room")
        XCTAssertLessThan(short.width, short.layoutWidth, "one digit leaves the second's room empty")
        XCTAssertLessThanOrEqual(long.width, long.layoutWidth,
                                 "the room is two of the widest digit, so a proportional 10 fits inside it")
    }

    func testFixedPitchGivesEveryGlyphItsOwnCell() throws {
        let font = NSFont.systemFont(ofSize: 20)
        let readout = try object(attributes: ["display": "time", "forcefixed": "1",
                                              "timecolonwidth": "4"])
        let run = try XCTUnwrap(WasabiTextMetrics.clockRun(of: readout, text: "1:13", font: font))
        XCTAssertEqual(run.cells.map(\.text), ["1", ":", "1", "3"])
        XCTAssertTrue(run.cells.allSatisfy(\.centred))
        let digits = run.cells.filter { $0.text != ":" }
        XCTAssertEqual(Set(digits.map(\.width)).count, 1, "one cell width for every digit")
    }

    /// `getTextWidth()` and the renderer have to agree: a skin lays out everything beside a readout
    /// from what it measures.
    func testMeasurementFollowsTheClockRun() throws {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <text id="readout" x="0" y="0" w="100" h="30" display="TIMEELAPSED" timecolonwidth="20"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let readout = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "readout").first)
        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }
        let font = try XCTUnwrap(metrics.font(identifier: nil, size: WasabiTextMetrics.pointSize(of: readout)))
        let run = try XCTUnwrap(WasabiTextMetrics.clockRun(of: readout, text: "1:13", font: font))
        XCTAssertEqual(metrics.width(of: readout, text: "1:13"), run.width, accuracy: 0.01)
    }

    // MARK: - Fixtures

    private func object(attributes: [String: String]) throws -> WasabiObject {
        let declared = attributes.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <text id="readout" x="0" y="0" w="100" h="30" \(declared)/>
            </layout>
          </container>
        </WasabiXML>
        """)
        return try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "readout").first)
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase76Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase76-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
