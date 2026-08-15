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
