import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B93 — a skin XML file that opens with a byte order mark.
///
/// The decode chain was UTF-8, then ISO-8859-1. `ff fe` is not valid UTF-8, so a UTF-16 file went
/// straight to the second — and ISO-8859-1 maps every one of the 256 byte values, so it accepts any
/// input at all and can never report a wrong guess. It handed the parser one character per byte,
/// nulls included: `ÿþ<\0g\0a\0m\0m\0a…`. Every `<` scanned as an opening tag and no `</` ever
/// matched it, so nesting climbed until the depth guard fired — `cpro2_dark_aluminum`'s
/// `colorthemes.xml:260:6: [xmlDepthExceeded]`, and the skin was refused. The guard was behaving
/// correctly; nothing upstream of it had decoded anything. A total fallback is why the mark must be
/// read before the chain rather than after it.
///
/// Windows XML tooling emits UTF-16 routinely, so the corpus count (3 files, 1 of them on an include
/// path) is a floor rather than the reach.
final class WinampModernB93Tests: XCTestCase {

    // MARK: - The decoder

    /// The bug in one case. UTF-8 rejects the mark, ISO-8859-1 accepts anything, and what comes out
    /// of it is the byte soup the parser choked on — so the old chain had no failing branch to add
    /// a third encoding to. Sniffing has to come first.
    func testAMarkedFileIsDecodedRatherThanFallingThroughToISO8859() {
        let source = "<gammaset id=\"*Default\">"
        let data = Self.encode(source, .utf16LittleEndian, bom: [0xFF, 0xFE])

        XCTAssertNil(String(data: data, encoding: .utf8), "the mark itself is not valid UTF-8")
        let asLatin1 = String(data: data, encoding: .isoLatin1)
        XCTAssertNotNil(asLatin1, "and ISO-8859-1 never says no")
        XCTAssertTrue(asLatin1!.contains("\u{0000}"), "which is how the nulls reached the parser")

        XCTAssertEqual(WalXMLDocumentLoader.decodeText(data), source)
    }

    func testABigEndianMarkDecodes() {
        let source = "<gammaset id=\"*Default\">"
        XCTAssertEqual(WalXMLDocumentLoader.decodeText(Self.encode(source, .utf16BigEndian, bom: [0xFE, 0xFF])),
                       source)
    }

    /// A UTF-8 mark decodes as U+FEFF, which would sit in front of the first tag. It is consumed.
    func testAUTF8MarkIsStrippedRatherThanLeftInTheText() {
        let source = "<gammaset/>"
        let decoded = WalXMLDocumentLoader.decodeText(Self.encode(source, .utf8, bom: [0xEF, 0xBB, 0xBF]))
        XCTAssertEqual(decoded, source)
        XCTAssertEqual(decoded?.first, "<", "no leading U+FEFF survives")
    }

    /// `ff fe` opens both UTF-16LE and UTF-32LE, so the longer mark has to be tested first or a
    /// UTF-32 file decodes as UTF-16 full of nulls — the same failure by another route.
    func testAUTF32MarkIsNotMistakenForUTF16() {
        let source = "<gammaset/>"
        XCTAssertEqual(WalXMLDocumentLoader.decodeText(Self.encode(source, .utf32LittleEndian, bom: [0xFF, 0xFE, 0x00, 0x00])),
                       source)
        XCTAssertEqual(WalXMLDocumentLoader.decodeText(Self.encode(source, .utf32BigEndian, bom: [0x00, 0x00, 0xFE, 0xFF])),
                       source)
    }

    /// The containment. No mark means the pre-existing chain, unchanged: UTF-8, then ISO-8859-1 for
    /// the bytes UTF-8 rejects. This is the path all but a handful of corpus files take.
    func testAnUnmarkedFileTakesTheOriginalChain() {
        XCTAssertEqual(WalXMLDocumentLoader.decodeText(Data("<gammaset/>".utf8)), "<gammaset/>")

        let latin1 = Data([0x3C, 0x61, 0x20, 0x76, 0x3D, 0x22, 0xE9, 0x22, 0x2F, 0x3E])  // <a v="é"/>
        XCTAssertNil(String(data: latin1, encoding: .utf8), "0xE9 alone is not UTF-8")
        XCTAssertEqual(WalXMLDocumentLoader.decodeText(latin1), "<a v=\"\u{00E9}\"/>")
    }

    /// An empty file, and a file shorter than the mark it appears to start, decode rather than trap.
    func testShortAndEmptyInputsAreSafe() {
        XCTAssertEqual(WalXMLDocumentLoader.decodeText(Data()), "")
        XCTAssertNotNil(WalXMLDocumentLoader.decodeText(Data([0xFF])))
        XCTAssertEqual(WalXMLDocumentLoader.decodeText(Data([0xFF, 0xFE])), "", "a mark and nothing else")
    }

    // MARK: - The skin

    /// The cpro2 shape end to end: a UTF-16LE file reached through an `<include>`. Before the fix
    /// this threw `xmlDepthExceeded` and the skin did not load at all.
    func testAnIncludedUTF16FileLoadsInsteadOfExhaustingTheDepthGuard() throws {
        let loaded = try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
            \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
              <include file="xml/themes.xml"/>
            </WasabiXML>
            """.utf8),
            "xml/themes.xml": Self.encode("""
            <WasabiXML>
            \(Self.container(id: "Themes", name: "Color Themes", width: 24, height: 12))
            </WasabiXML>
            """, .utf16LittleEndian, bom: [0xFF, 0xFE]),
        ])
        XCTAssertFalse(loaded.runtime.diagnostics.contains { $0.code == .xmlDepthExceeded },
                       "the depth guard was the symptom, not the cause")
        let ids = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).map(\.id)
        XCTAssertTrue(ids.contains("Themes"), "the UTF-16 file's declarations reach the graph")
    }

    /// And when the root itself carries the mark, which is the same decode a step earlier.
    func testAUTF16RootSkinLoads() throws {
        let loaded = try load(files: [
            "skin.xml": Self.encode("""
            <WasabiXML>
            \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
            </WasabiXML>
            """, .utf16LittleEndian, bom: [0xFF, 0xFE]),
        ])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "main", clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 20, height: 10),
                       "the layout parsed out of the UTF-16 root, attributes and all")
    }

    // MARK: - Fixtures

    private static func encode(_ text: String, _ encoding: String.Encoding, bom: [UInt8]) -> Data {
        Data(bom) + text.data(using: encoding)!
    }

    private static func container(id: String, name: String, width: Int, height: Int) -> String {
        """
        <container id="\(id)" name="\(name)">
          <layout id="normal" w="\(width)" h="\(height)">
            <layer id="\(id).body" x="0" y="0" w="\(width)" h="\(height)"/>
          </layout>
        </container>
        """
    }

    private func load(files: [String: Data]) throws -> WinampModernLoadedSkin {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(files: files))
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(files: [String: Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB93Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B93-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, payload) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 200
        var volume: Double = 0.5
        var balance: Double = 0
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
