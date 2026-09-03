import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 6 — ClassicPro user-supplied engine import (internal NSIS/LZMA extraction), the mounted
/// engine, the `ClassicProFile` shell adapters, and the `WinampVersionCheck` shim.
final class WinampModernPhase6Tests: XCTestCase {
    // MARK: - Test doubles

    private final class SpyHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 100
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Song"
        var trackInfo = "Artist"
        var spectrumLevels: [Float] = []
        var revealed: [String] = []
        var openedExternally: [String] = []
        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
        func revealInFinder(_ path: String) { revealed.append(path) }
        func openExternally(_ path: String) { openedExternally.append(path) }
    }

    // MARK: - 6.2 LZMA1 decoder

    // A raw LZMA1 stream (5 property bytes + range-coded data, no size field) produced from a known
    // input, exactly the framing NSIS uses. Regenerating: compress with FORMAT_ALONE, keep props[0..5]
    // + stream[13...].
    private static let lzmaRawB64 = "XQAAgAAAJx1JmFA27d1bEtgqYbnH0WLjtqy1GbU+ygVsPRBT8m8/yoXjg472yCaCMzHHwjTJoolEEu00LzGxSZg85sOPQGZlKRiLSbWE+rSHpdYXJbNhTgUgS/gAZTSvD81PV4SYtdboBWUrR//wPmwA"
    private static let lzmaOutB64 = "TnVsbFBsYXllciBMWk1BMSByYXcgZGVjb2RlciB2ZWN0b3IuIE51bGxQbGF5ZXIgTFpNQTEgcmF3IGRlY29kZXIgdmVjdG9yLiBOdWxsUGxheWVyIExaTUExIHJhdyBkZWNvZGVyIHZlY3Rvci4gTnVsbFBsYXllciBMWk1BMSByYXcgZGVjb2RlciB2ZWN0b3IuIE51bGxQbGF5ZXIgTFpNQTEgcmF3IGRlY29kZXIgdmVjdG9yLiBOdWxsUGxheWVyIExaTUExIHJhdyBkZWNvZGVyIHZlY3Rvci4gAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+Pw=="

    func testLZMADecoderMatchesReferenceVector() throws {
        let raw = Data(base64Encoded: Self.lzmaRawB64)!
        let expected = Data(base64Encoded: Self.lzmaOutB64)!
        let decoder = try LZMA1Decoder(stream: raw)
        try decoder.decode(untilOutputCount: expected.count)
        XCTAssertEqual(Data(decoder.output.prefix(expected.count)), expected)
    }

    func testLZMADecoderIsIncrementalAndConsistent() throws {
        let raw = Data(base64Encoded: Self.lzmaRawB64)!
        let expected = Data(base64Encoded: Self.lzmaOutB64)!
        let decoder = try LZMA1Decoder(stream: raw)
        // Decode in small chunks; the retained dictionary must yield the same bytes.
        for target in stride(from: 10, through: expected.count, by: 17) {
            try decoder.decode(untilOutputCount: target)
            XCTAssertGreaterThanOrEqual(decoder.output.count, target)
        }
        try decoder.decode(untilOutputCount: expected.count)
        XCTAssertEqual(Data(decoder.output.prefix(expected.count)), expected)
    }

    func testLZMADecoderRejectsShortStream() {
        XCTAssertThrowsError(try LZMA1Decoder(stream: Data([0x5D, 0, 0])))
    }

    // MARK: - 6.2a Fuzzing the installer boundary

    // `NSISArchive` and `LZMA1Decoder` parse a **user-supplied installer executable** — the last
    // untrusted-input parser in this subsystem that had only happy-path coverage. The guarantee
    // fuzzed for is the same one the archive/XML/MAKI fuzzers assert: a bounded outcome, either a
    // parse or a typed `WalFailure`, never a Swift trap, an unbounded allocation or a hang.

    /// Random bytes almost never carry the Nullsoft signature, so this half only ever reaches
    /// `findMagic`. Kept anyway: it is the shape a user actually hands us when they pick the wrong
    /// `.exe`, and it must fail cheaply.
    func testFuzzRandomBytesAsNSISArchiveNeverCrashes() {
        var rng = SeededRNG(seed: 0x0451)
        for _ in 0..<400 {
            let length = Int(rng.next() % 4096)
            var bytes = [UInt8](repeating: 0, count: length)
            for index in 0..<length { bytes[index] = UInt8(rng.next() & 0xFF) }
            expectBoundedOutcome { _ = try NSISArchive.extract(data: Data(bytes), limits: Self.fuzzArchiveLimits) }
        }
    }

    /// The half that matters. The signature is *planted*, so every iteration gets past `findMagic`
    /// and into the firstheader, the length-prefixed header block and the entry/string tables — the
    /// code that indexes into attacker-chosen offsets. The 24-byte firstheader following the magic
    /// is fuzzed too, which is what drives `headerSize` and therefore the decode target.
    func testFuzzPlantedNSISSignatureNeverCrashes() {
        // The signature `NSISArchive.findMagic` looks for, restated here so the fuzzer does not need
        // access to the private constant.
        let magic: [UInt8] = [0xEF, 0xBE, 0xAD, 0xDE] + Array("NullsoftInst".utf8)
        var rng = SeededRNG(seed: 0x5153)
        for _ in 0..<400 {
            var bytes = [UInt8]()
            // A little junk ahead of the signature, the way a real installer has its stub there.
            let leading = Int(rng.next() % 64)
            for _ in 0..<leading { bytes.append(UInt8(rng.next() & 0xFF)) }
            bytes += magic
            // The rest of the firstheader plus a payload of random bytes for the LZMA stream.
            let trailing = 24 + Int(rng.next() % 2048)
            for _ in 0..<trailing { bytes.append(UInt8(rng.next() & 0xFF)) }
            expectBoundedOutcome { _ = try NSISArchive.extract(data: Data(bytes), limits: Self.fuzzArchiveLimits) }
        }
    }

    /// The decoder underneath, driven directly. The property byte and the range-coder header are the
    /// two fields that pick array sizes and the initial model state, so both are left fully random;
    /// a stream that survives construction is then decoded against a small output cap, which is what
    /// exercises `copyMatch`'s distance bound and the end-marker path.
    func testFuzzRandomBytesAsLZMADecoderNeverCrashes() {
        var rng = SeededRNG(seed: 0xC0FFEE)
        for _ in 0..<600 {
            let length = Int(rng.next() % 512)
            var bytes = [UInt8](repeating: 0, count: length)
            for index in 0..<length { bytes[index] = UInt8(rng.next() & 0xFF) }
            expectBoundedOutcome {
                var limits = LZMA1Decoder.Limits()
                limits.maximumOutputBytes = 64 * 1_024
                let decoder = try LZMA1Decoder(stream: Data(bytes), limits: limits)
                try decoder.decode(untilOutputCount: 32 * 1_024)
            }
        }
    }

    /// Same, but with a **valid** 5-byte property header in front of random range-coded data, so the
    /// construction guards cannot short-circuit the run and every iteration reaches `step()`.
    func testFuzzValidLZMAHeaderWithGarbagePayloadNeverCrashes() {
        var rng = SeededRNG(seed: 0xD15EA5E)
        for _ in 0..<600 {
            // props = (pb * 5 + lp) * 9 + lc, the encoding `init` decodes; every value < 9 * 5 * 5
            // is legal, and each picks a different literal-table size.
            var bytes: [UInt8] = [UInt8(rng.next() % UInt64(9 * 5 * 5))]
            for _ in 0..<4 { bytes.append(UInt8(rng.next() & 0xFF)) }   // dictionary size, unread
            bytes.append(0)                                             // the range coder's zero byte
            let length = 4 + Int(rng.next() % 512)
            for _ in 0..<length { bytes.append(UInt8(rng.next() & 0xFF)) }
            expectBoundedOutcome {
                var limits = LZMA1Decoder.Limits()
                limits.maximumOutputBytes = 64 * 1_024
                let decoder = try LZMA1Decoder(stream: Data(bytes), limits: limits)
                try decoder.decode(untilOutputCount: 32 * 1_024)
            }
        }
    }

    /// Tight limits: a fuzzer that let the production 128 MB cap stand would spend its whole run
    /// decompressing, and a runaway would look like a slow test rather than a failure.
    private static let fuzzArchiveLimits: WalArchiveLimits = {
        var limits = WalArchiveLimits()
        limits.maximumTotalSize = 1 * 1_024 * 1_024
        return limits
    }()

    /// The single assertion every fuzz case makes: the call returns or throws `WalFailure`. Anything
    /// else is a bug in the parser, and a trap or a hang fails the run by taking the process down.
    private func expectBoundedOutcome(_ body: () throws -> Void, file: StaticString = #filePath,
                                      line: UInt = #line) {
        do {
            try body()
        } catch is WalFailure {
            // Expected for garbage input.
        } catch {
            XCTFail("expected a WalFailure or a clean parse, got \(error)", file: file, line: line)
        }
    }

    /// Small deterministic PRNG (xorshift64) so fuzz runs reproduce across machines.
    private struct SeededRNG {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    // MARK: - 6.1 Directory resource provider

    func testDirectoryResourceProviderReadsAndBoundsTree() throws {
        let dir = try makeTempDir()
        try writeFile(dir, "load.xml", "<root/>")
        try writeFile(dir, "one/player.xml", "<player/>")
        try writeFile(dir, "image/bg.png", "PNGDATA")
        let provider = try WalDirectoryResourceProvider(rootURL: dir)
        XCTAssertEqual(Set(provider.resourcePaths), ["load.xml", "one/player.xml", "image/bg.png"])
        XCTAssertEqual(try provider.data(for: "one/player.xml"), Data("<player/>".utf8))
        // Case-insensitive canonical lookup.
        XCTAssertEqual(provider.canonicalPath(for: "LOAD.XML"), "load.xml")
        XCTAssertNil(provider.canonicalPath(for: "missing.xml"))
    }

    func testDirectoryResourceProviderRejectsSymlink() throws {
        let dir = try makeTempDir()
        try writeFile(dir, "real.xml", "<x/>")
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("link.xml"),
            withDestinationURL: dir.appendingPathComponent("real.xml"))
        XCTAssertThrowsError(try WalDirectoryResourceProvider(rootURL: dir))
    }

    func testDirectoryResourceProviderEnforcesEntryLimit() throws {
        let dir = try makeTempDir()
        for i in 0..<5 { try writeFile(dir, "f\(i).txt", "x") }
        var limits = WalArchiveLimits()
        limits.maximumEntryCount = 3
        XCTAssertThrowsError(try WalDirectoryResourceProvider(rootURL: dir, limits: limits))
    }

    // MARK: - 6.4 Engine store: validation, install, provider

    private func syntheticEngineFiles() -> [String: Data] {
        [
            "load.xml": Data("<groupdef id=\"cproEngine\"/>".utf8),
            "one/load-one.xml": Data("<groupdef id=\"cproOne\"/>".utf8),
            "one/scripts/player.maki": Data([0x46, 0x47]),
        ]
    }

    func testEngineValidationRejectsNonEngineAndMissingFamily() {
        XCTAssertThrowsError(try ClassicProEngineStore.validate(engineFiles: ["foo.xml": Data()])) // no load.xml
        XCTAssertThrowsError(try ClassicProEngineStore.validate(
            engineFiles: ["load.xml": Data(), "two/x.xml": Data()])) // has load.xml but no "one" family
    }

    func testEngineValidationAcceptsOneFamilyAndHashesStably() throws {
        let info = try ClassicProEngineStore.validate(engineFiles: syntheticEngineFiles())
        XCTAssertTrue(info.families.contains("one"))
        XCTAssertEqual(info.fileCount, 3)
        let again = try ClassicProEngineStore.validate(engineFiles: syntheticEngineFiles())
        XCTAssertEqual(info.contentHash, again.contentHash)
    }

    func testEngineStoreInstallAndProviderRoundTrip() throws {
        let store = ClassicProEngineStore(rootDirectory: try makeTempDir())
        XCTAssertFalse(store.isInstalled)
        let info = try store.install(engineFiles: syntheticEngineFiles())
        XCTAssertTrue(store.isInstalled)
        XCTAssertEqual(store.info()?.contentHash, info.contentHash)
        let provider = try store.provider()
        XCTAssertEqual(try provider.data(for: "load.xml"), Data("<groupdef id=\"cproEngine\"/>".utf8))
    }

    // MARK: - 6.5 Importer from an already-extracted directory

    func testImporterFromExtractedEngineFolder() throws {
        let engineDir = try makeTempDir()
        try writeFile(engineDir, "load.xml", "<groupdef id=\"e\"/>")
        try writeFile(engineDir, "one/x.xml", "<x/>")
        let store = ClassicProEngineStore(rootDirectory: try makeTempDir())
        let importer = ClassicProEngineImporter(store: store)
        let info = try importer.importEngine(from: engineDir)
        XCTAssertTrue(info.families.contains("one"))
        XCTAssertTrue(store.isInstalled)
    }

    func testImporterFromNestedPluginsTree() throws {
        // A folder that contains Plugins/ClassicPro/engine/... rather than being the engine root.
        let root = try makeTempDir()
        try writeFile(root, "Plugins/ClassicPro/engine/load.xml", "<groupdef id=\"e\"/>")
        try writeFile(root, "Plugins/ClassicPro/engine/one/x.xml", "<x/>")
        let store = ClassicProEngineStore(rootDirectory: try makeTempDir())
        let info = try ClassicProEngineImporter(store: store).importEngine(from: root)
        XCTAssertEqual(info.fileCount, 2)
    }

    // MARK: - 6.6 Loader auto-mounts the installed engine

    func testLoaderMountsEngineForCproStyleInclude() throws {
        let store = ClassicProEngineStore(rootDirectory: try makeTempDir())
        _ = try store.install(engineFiles: [
            "load.xml": Data("<groupdef id=\"cproEngine\"/>".utf8),
            "one/marker.xml": Data("<groupdef id=\"cproOne\"/>".utf8),
        ])
        let skin = """
        <WasabiXML>
          <container id="main"><layout id="normal" w="100" h="50"/></container>
          <include file="@COLORTHEMESPATH@\\..\\..\\Plugins\\classicPro\\engine\\load.xml"/>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: store).load(from: makeArchive(xml: skin))
        defer { loaded.teardown() }
        // The engine include resolved (a missing mount would have thrown resourceMissing).
        XCTAssertTrue(loaded.runtime.graph.roots.contains { $0.xmlID?.lowercased() == "main" })
    }

    func testLoaderWithoutEngineLeavesCproIncludeUnresolved() throws {
        let store = ClassicProEngineStore(rootDirectory: try makeTempDir()) // not installed
        let skin = """
        <WasabiXML>
          <container id="main"><layout id="normal" w="100" h="50"/></container>
          <include file="@COLORTHEMESPATH@\\..\\..\\Plugins\\classicPro\\engine\\load.xml"/>
        </WasabiXML>
        """
        XCTAssertThrowsError(try WinampModernSkinLoader(engineStore: store).load(from: makeArchive(xml: skin)))
    }

    // MARK: - 6.7 / 6.8 Version shim + ClassicProFile dispatch

    private func makeRuntime(host: WinampModernHost) throws -> (WinampModernScriptRuntime, MakiProgram) {
        let skin = "<WasabiXML><container id=\"main\"><layout id=\"normal\" w=\"10\" h=\"10\"/></container></WasabiXML>"
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: makeArchive(xml: skin))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [],
                                  bindings: [], instructions: [],
                                  source: WalSourceLocation(path: "test.maki"),
                                  ownerID: nil, parameter: "2405;5.55")
        return (runtime, program)
    }

    func testVersionShimReportsBuildPastTheGate() throws {
        let (runtime, program) = try makeRuntime(host: SpyHost())
        let system = MakiObjectReference(.system)
        let build = try runtime.invoke(method: "getbuildnumber", on: system, arguments: [], program: program)
        XCTAssertGreaterThanOrEqual(build.integerValue, 2405, "must satisfy WinampVersionCheck's 2405 gate")
        // The public-config query the check performs before the build check must not throw.
        let publicInt = try runtime.invoke(method: "getpublicint", on: system,
                                           arguments: [.string("ClassicPro.dontRemindOldWinamp"), .integer(0)],
                                           program: program)
        XCTAssertEqual(publicInt.integerValue, 0)
        let doy = try runtime.invoke(method: "getdatedoy", on: system,
                                     arguments: [.integer(0)], program: program)
        XCTAssertGreaterThan(doy.integerValue, 0)
    }

    func testClassicProFileShellAdaptersRouteThroughPolicy() throws {
        let host = SpyHost()
        let (runtime, program) = try makeRuntime(host: host)
        let system = MakiObjectReference(.system)
        _ = try runtime.invoke(method: "explorefile", on: system,
                               arguments: [.string("/tmp/song.mp3")], program: program)
        _ = try runtime.invoke(method: "openfile", on: system,
                               arguments: [.string("/tmp/thing"), .string("")], program: program)
        let findResult = try runtime.invoke(method: "findfiles", on: system,
                                            arguments: [.string("/dir"), .string("*.mp3"), .null],
                                            program: program)
        XCTAssertEqual(host.revealed, ["/tmp/song.mp3"])
        XCTAssertEqual(host.openedExternally, ["/tmp/thing"])
        XCTAssertEqual(findResult.integerValue, -1, "findFiles is a bounded no-op (drives the early-return path)")
    }

    // MARK: - Opt-in: real ClassicPro installer (internal NSIS/LZMA extraction)

    /// Opt-in acceptance: internally extract a user-supplied ClassicPro installer (.exe/.zip/folder)
    /// and confirm the engine tree is recovered. `WINAMP_MODERN_ENGINE` points at the source.
    func testInternalEngineExtractionWhenInstallerSupplied() throws {
        guard let path = ProcessInfo.processInfo.environment["WINAMP_MODERN_ENGINE"] else {
            throw XCTSkip("Set WINAMP_MODERN_ENGINE to a ClassicPro installer (.exe), .zip, or engine folder.")
        }
        let store = ClassicProEngineStore(rootDirectory: try makeTempDir())
        let info = try ClassicProEngineImporter(store: store).importEngine(from: URL(fileURLWithPath: path))
        XCTAssertTrue(info.families.contains("one"), "engine \"one\" family required by cPro-Bento")
        XCTAssertGreaterThan(info.fileCount, 50)
        let provider = try store.provider()
        XCTAssertNoThrow(try provider.data(for: "load.xml"))
    }

    /// Opt-in end-to-end: with the engine imported (WINAMP_MODERN_ENGINE) and a cPro `.wal` supplied
    /// (WINAMP_MODERN_WAL), the skin loads with the engine mounted and yields exactly one main window.
    func testLocalCproBentoWithEngineWhenSupplied() throws {
        let env = ProcessInfo.processInfo.environment
        guard let enginePath = env["WINAMP_MODERN_ENGINE"], let walPath = env["WINAMP_MODERN_WAL"] else {
            throw XCTSkip("Set WINAMP_MODERN_ENGINE and WINAMP_MODERN_WAL for the cPro-Bento acceptance path.")
        }
        let store = ClassicProEngineStore(rootDirectory: try makeTempDir())
        _ = try ClassicProEngineImporter(store: store).importEngine(from: URL(fileURLWithPath: enginePath))
        let loaded = try WinampModernSkinLoader(engineStore: store).load(from: URL(fileURLWithPath: walPath))
        defer { loaded.teardown() }
        let windows = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        XCTAssertEqual(windows.filter(\.isMainPlayer).count, 1)
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func writeFile(_ dir: URL, _ relative: String, _ contents: String) throws {
        let url = dir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = try makeTempDir()
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        return url
    }
}
