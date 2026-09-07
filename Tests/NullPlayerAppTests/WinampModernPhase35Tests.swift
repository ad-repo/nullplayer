import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 35 (backlog B1) — the two skins that did not load at all.
///
/// `Itemskin` and `Overdrive_2` were 2 of the 17 measured skins and neither appeared: both name an
/// `<include>` their archive does not ship, and the include expander failed the whole load for it.
/// Winamp warns and carries on, which is the policy the initializer already applies to a missing
/// bitmap, cursor or TTF. Fixing that exposed the next abort behind it, so this file covers all
/// three changes:
///
/// 1. A missing include *inside the skin* is a warning; the rest of the document still expands. One
///    that climbs into another mount (a ClassicPro engine that is not installed) stays fatal.
/// 2. A script the parser cannot read is dropped with a diagnostic instead of failing the skin.
/// 3. The pre-5.0 MAKI layout `Overdrive_2/scripts/seek.maki` is written in — no class GUID table,
///    13-byte variable records — parses, under the same version word as the modern form.
final class WinampModernPhase35Tests: XCTestCase {
    // MARK: - 1. A missing include is a warning

    func testMissingSkinIncludeWarnsAndTheSkinStillLoads() throws {
        let xml = """
        <WasabiXML>
          <include file="xml/never-shipped.xml"/>
          <container id="main"><layout id="normal" w="120" h="60"/></container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        defer { loaded.teardown() }

        XCTAssertTrue(loaded.runtime.graph.roots.contains { $0.xmlID?.lowercased() == "main" })
        let missing = loaded.runtime.diagnostics.filter {
            $0.code == .resourceMissing && $0.message.contains("never-shipped.xml")
        }
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.severity, .warning)
    }

    // MARK: - 2. An unreadable script does not take the skin down

    func testUnreadableScriptIsRecordedRatherThanFatal() throws {
        let xml = """
        <WasabiXML>
          <container id="main"><layout id="normal" w="120" h="60"/></container>
          <scripts><script id="broken" file="scripts/broken.maki"/></scripts>
        </WasabiXML>
        """
        let url = try makeArchive(xml: xml, extraFiles: ["scripts/broken.maki": Data("FGnot-a-program".utf8)])
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        defer { loaded.teardown() }

        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        defer { runtime.teardown() }
        XCTAssertTrue(runtime.scriptFailures.contains { $0.code == .invalidScript })
    }

    // MARK: - 3. The pre-5.0 MAKI layout

    func testLegacyMakiWithoutAClassTableParses() throws {
        let program = try MakiBytecodeParser().parse(Self.legacyScript(),
                                                     source: WalSourceLocation(path: "seek.maki"))

        XCTAssertTrue(program.classes.isEmpty)
        XCTAssertEqual(program.methods.map(\.name), ["onscriptloaded", "loadmap", "addcommand"])
        // The class code survives even with nothing to resolve it against: dispatch is by name.
        XCTAssertEqual(program.methods.map(\.classIndex), [8, 25, 3])
        // 13-byte records: `System` first, then an integer initialised to 1000 and a string.
        XCTAssertEqual(program.variables.count, 3)
        XCTAssertTrue(program.variables[0].isSystem)
        XCTAssertEqual(program.variables[1].value.integerValue, 1000)
        XCTAssertEqual(program.variables[2].value.stringValue, "player")
        // `new` on a class the program cannot name builds a generic dynamic object, except for the
        // one class the dispatcher treats specially, which its methods still identify.
        XCTAssertEqual(program.classGUID(atIndex: 25), "")
        XCTAssertEqual(program.classGUID(atIndex: 3), MakiProgram.popupMenuClassGUID)
    }

    func testModernMakiStillParsesAsBefore() throws {
        let program = try MakiBytecodeParser().parse(Self.modernScript(),
                                                     source: WalSourceLocation(path: "modern.maki"))
        XCTAssertEqual(program.classes.count, 1)
        XCTAssertEqual(program.methods.map(\.name), ["getid"])
        XCTAssertTrue(program.variables.isEmpty)
    }

    // MARK: - Fixtures

    /// A pre-5.0 program: no class GUID table at all, and variable records one byte shorter, with
    /// the trailing `global`/`system` pair replaced by a single `object` flag.
    private static func legacyScript() -> Data {
        var data = Data([0x46, 0x47])
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func method(_ classCode: UInt16, _ name: String) {
            u16(classCode); u16(0)
            let bytes = Array(name.utf8)
            u16(UInt16(bytes.count)); data.append(contentsOf: bytes)
        }
        func variable(type: UInt8, initial: UInt16, object: Bool) {
            data.append(type); data.append(0)
            u16(0); u16(initial); u16(0); u16(0); u16(0)
            data.append(object ? 1 : 0)
        }
        u16(0x0403)
        u32(21)                                     // the same header word the modern form carries
        u32(3)                                      // methods — no class table precedes them
        method(8, "onScriptLoaded")
        method(25, "loadMap")
        method(3, "addCommand")
        u32(3)                                      // variables, 13 bytes each
        variable(type: 8, initial: 0, object: true) // System
        variable(type: 2, initial: 1000, object: false)
        variable(type: 6, initial: 0, object: false)
        u32(1)                                      // constants
        u32(2)
        let constant = Array("player".utf8)
        u16(UInt16(constant.count)); data.append(contentsOf: constant)
        u32(0)                                      // bindings
        u32(0)                                      // code length
        return data
    }

    /// The ordinary 5.x form, for the regression half of the retry.
    private static func modernScript() -> Data {
        var data = Data([0x46, 0x47])
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        u16(0x0403)
        u32(23)
        u32(1)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        u32(1)
        u16(0); u16(0)
        let name = Array("getid".utf8)
        u16(UInt16(name.count)); data.append(contentsOf: name)
        u32(0); u32(0); u32(0); u32(0)
        return data
    }

    private func makeArchive(xml: String, extraFiles: [String: Data] = [:]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase35Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase35-\(UUID().uuidString).wal")
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

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
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
