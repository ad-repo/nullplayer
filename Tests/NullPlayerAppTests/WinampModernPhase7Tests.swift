import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 7 — compatibility hardening.
///
/// Covers the predefined Wasabi standard library (7.1), the per-skin compatibility report (7.2),
/// unsupported-method demand instrumentation (7.3), fuzzing of the archive/XML/group paths (7.4) and
/// the MAKI bytecode parser + VM (7.5), and stress/lifecycle of timers, rapid load/teardown, and
/// malformed resources (7.6). Everything here runs headlessly on synthetic, self-authored fixtures —
/// no third-party skin assets. Live-GUI verification (7.8) is documented in the Phase 7 handoff.
final class WinampModernPhase7Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Synthetic Song"
        var trackInfo = "Synthetic Artist"
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

    // MARK: - 7.1 Predefined Wasabi standard library

    func testInheritingKnownWasabiBaseResolvesWithoutWarning() throws {
        let runtime = try initialize(xml: """
        <WasabiXML>
          <groupdef id="my.button" inherit_group="wasabi.button"/>
          <groupdef id="my.text" inherit_group="wasabi.text"/>
          <groupdef id="my.frame" inherit_group="wasabi.standardframe.nostatusbar"/>
        </WasabiXML>
        """)
        let missing = runtime.diagnostics.filter { $0.code == .missingGroupDefinition }
        XCTAssertTrue(missing.isEmpty, "Known wasabi.* bases should resolve, not warn: \(missing)")
    }

    func testGenuinelyUnknownBaseStillWarnsButLoads() throws {
        let runtime = try initialize(xml: """
        <WasabiXML>
          <groupdef id="my.widget" inherit_group="wasabi.totally.invented.base"/>
        </WasabiXML>
        """)
        let missing = runtime.diagnostics.filter { $0.code == .missingGroupDefinition }
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.severity, .warning)
        XCTAssertTrue(missing.first?.message.contains("wasabi.totally.invented.base") ?? false)
    }

    func testSkinDefinitionWinsOverPredefinedShell() throws {
        // A skin that ships its own `wasabi.panel` must not trigger a duplicate-identifier warning
        // from the predefined shell, and its attributes must survive.
        let runtime = try initialize(xml: """
        <WasabiXML>
          <groupdef id="wasabi.panel" x="7"/>
          <groupdef id="my.panel" inherit_group="wasabi.panel"/>
        </WasabiXML>
        """)
        XCTAssertTrue(runtime.diagnostics.filter { $0.code == .duplicateIdentifier }.isEmpty)
        let resolved = try XCTUnwrap(try? runtime.types.resolved(identifier: "my.panel"))
        XCTAssertEqual(resolved.defaultAttributes["x"], "7")
    }

    // MARK: - 7.2 Per-skin compatibility report

    func testCompatibilityReportFullForCleanSkin() throws {
        let runtime = try initialize(xml: "<WasabiXML><groupdef id=\"a\"/></WasabiXML>")
        let report = WinampModernCompatibilityReport(diagnostics: runtime.diagnostics)
        XCTAssertEqual(report.level, .full)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertFalse(report.hasBlockingFailure)
    }

    func testCompatibilityReportDegradedOnWarnings() {
        let diagnostics = [
            WalDiagnostic(.resourceMissing, "Optional bitmap missing.", severity: .warning),
            WalDiagnostic(.missingGroupDefinition, "Unknown base.", severity: .warning),
        ]
        let report = WinampModernCompatibilityReport(diagnostics: diagnostics)
        XCTAssertEqual(report.level, .degraded)
        XCTAssertEqual(report.occurrences(in: .resources), 1)
        XCTAssertEqual(report.occurrences(in: .groups), 1)
        XCTAssertFalse(report.hasBlockingFailure)
    }

    func testCompatibilityReportUnsupportedOnHardFailure() {
        let report = WinampModernCompatibilityReport(
            diagnostics: [WalDiagnostic(.unsafePath, "Traversal rejected.", severity: .error)],
            loadSucceeded: false)
        XCTAssertEqual(report.level, .unsupported)
        XCTAssertTrue(report.hasBlockingFailure)
        XCTAssertEqual(report.occurrences(in: .archive), 1)
    }

    func testCompatibilityReportSurfacesUnsupportedMethods() {
        let report = WinampModernCompatibilityReport(
            diagnostics: [],
            unsupportedMethodCalls: ["exoticmethod": 3, "anotherone": 1])
        XCTAssertEqual(report.level, .degraded)
        XCTAssertEqual(report.occurrences(in: .unsupportedMethods), 4)
    }

    func testCompatibilityReportDeduplicatesRepeatedDiagnostics() {
        let repeated = Array(repeating: WalDiagnostic(.resourceMissing, "same", severity: .warning), count: 5)
        let report = WinampModernCompatibilityReport(diagnostics: repeated)
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings.first?.count, 5)
        XCTAssertEqual(report.occurrences(in: .resources), 5)
    }

    func testLoadedSkinExposesCompatibilityReport() throws {
        let url = try makeArchive(xml: "<WasabiXML><groupdef id=\"a\"/></WasabiXML>", script: nil)
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        XCTAssertEqual(loaded.compatibilityReport.level, .full)
    }

    // MARK: - 7.3 Unsupported-method demand instrumentation

    func testUnsupportedMethodCallIsRecordedBeforeThrowing() throws {
        let url = try makeArchive(xml: "<WasabiXML><container id=\"main\"/></WasabiXML>", script: nil)
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        defer { runtime.teardown() }
        let program = try MakiBytecodeParser().parse(
            makeMinimalScript(code: Data([33])), source: WalSourceLocation(path: "/x.maki"))

        XCTAssertThrowsError(try runtime.invoke(method: "NoSuchMethod",
                                                on: MakiObjectReference(.system),
                                                arguments: [], program: program))
        XCTAssertThrowsError(try runtime.invoke(method: "nosuchmethod",
                                                on: MakiObjectReference(.system),
                                                arguments: [], program: program))
        XCTAssertEqual(runtime.unsupportedMethodCalls["nosuchmethod"], 2,
                       "Case-folded method name should accumulate demand.")

        let report = loaded.compatibilityReport(withRuntime: runtime)
        XCTAssertEqual(report.occurrences(in: .unsupportedMethods), 2)
    }

    // MARK: - 7.4 Fuzz: archive / XML / group expansion

    func testFuzzRandomBytesAsArchiveNeverCrashes() throws {
        var rng = SeededRNG(seed: 0xA11CE)
        for iteration in 0..<400 {
            let length = Int(rng.next() % 4096)
            var bytes = Data(count: length)
            for index in 0..<length { bytes[index] = UInt8(rng.next() & 0xFF) }
            let url = temporaryDirectory().appendingPathComponent("fuzz\(iteration).wal")
            try bytes.write(to: url)
            // Bounded outcome: either a valid archive or a typed WalFailure — never a Swift trap/hang.
            do {
                _ = try WalArchive(url: url)
            } catch is WalFailure {
                // expected for garbage input
            } catch {
                // ZIPFoundation may surface its own error type for malformed central directories;
                // that is still a bounded, non-crashing failure.
            }
        }
    }

    func testFuzzRandomXMLThroughInitializerIsBounded() {
        var rng = SeededRNG(seed: 0xBEEF)
        let tokens = ["<WasabiXML>", "</WasabiXML>", "<groupdef id=\"g", "\" inherit_group=\"wasabi.button\">",
                      "<container id=\"c\">", "</container>", "<layout w=\"10\" h=\"10\">", "</layout>",
                      "<bitmap id=\"b\" file=\"x.png\"/>", "<", ">", "\"", "/", "&amp;", "groupdef", "  "]
        for _ in 0..<600 {
            var xml = ""
            let count = Int(rng.next() % 40)
            for _ in 0..<count { xml += tokens[Int(rng.next() % UInt64(tokens.count))] }
            // The only guarantee under fuzz is bounded: a valid parse or a thrown error, never a
            // Swift trap or a hang. (Targeted cases below assert the specific typed diagnostics.)
            _ = try? initialize(xml: xml)
        }
    }

    /// Regression: a '/' inside a tag that does not close it (and a '/' at end of input) matched no
    /// branch of the attribute scanner and left the cursor parked, spinning forever on the calling
    /// thread. Found by `testFuzzRandomXMLThroughInitializerIsBounded`; every case must now terminate.
    func testStraySlashInTagDoesNotHangParser() {
        for xml in ["<WasabiXML><groupdef id=\"a\" /x></WasabiXML>",
                    "<WasabiXML><groupdef /",
                    "<WasabiXML><groupdef id=\"a\"//></WasabiXML>",
                    "<WasabiXML><groupdef / id=\"a\"></groupdef></WasabiXML>"] {
            // Success or a typed failure are both fine; the assertion is that this returns at all.
            _ = try? initialize(xml: xml)
        }
    }

    func testDeeplyNestedXMLHitsDepthLimit() {
        let depth = 5_000
        let xml = "<WasabiXML>" + String(repeating: "<group>", count: depth)
            + String(repeating: "</group>", count: depth) + "</WasabiXML>"
        XCTAssertThrowsError(try initialize(xml: xml)) { error in
            XCTAssertTrue(error is WalFailure)
        }
    }

    func testGroupInheritanceCycleFailsSafely() {
        let xml = """
        <WasabiXML>
          <groupdef id="a" inherit_group="b"/>
          <groupdef id="b" inherit_group="a"/>
        </WasabiXML>
        """
        // Cycles are a hard failure (unlike an unknown predefined base, which degrades).
        XCTAssertThrowsError(try initialize(xml: xml)) { error in
            XCTAssertEqual((error as? WalFailure)?.diagnostics.first?.code, .groupInheritanceCycle)
        }
    }

    // MARK: - 7.5 Fuzz: MAKI bytecode parser + VM

    func testFuzzRandomBytesAsMakiParserNeverCrashes() {
        var rng = SeededRNG(seed: 0x5CA1AB1E)
        let parser = MakiBytecodeParser()
        for _ in 0..<1_000 {
            let length = Int(rng.next() % 512)
            var bytes = Data(count: length)
            for index in 0..<length { bytes[index] = UInt8(rng.next() & 0xFF) }
            // Half the time, prefix a valid "FG" magic so the parser gets past the first gate.
            if rng.next() & 1 == 0, bytes.count >= 2 { bytes[0] = 0x46; bytes[1] = 0x47 }
            do {
                _ = try parser.parse(bytes, source: WalSourceLocation(path: "/fuzz.maki"))
            } catch is WalFailure {
            } catch {
                XCTFail("MAKI parser produced a non-WalFailure error: \(error)")
            }
        }
    }

    func testTruncatedValidScriptRejectsAtEveryPrefix() {
        let full = makeMinimalScript(code: Data([33]))
        let parser = MakiBytecodeParser()
        // Every strict prefix of a valid file must reject cleanly (never trap).
        for length in stride(from: 0, to: full.count, by: 3) {
            do {
                _ = try parser.parse(full.subdata(in: 0..<length), source: WalSourceLocation(path: "/t.maki"))
            } catch is WalFailure {
            } catch {
                XCTFail("Truncated MAKI produced a non-WalFailure error at \(length): \(error)")
            }
        }
    }

    func testInterpreterInstructionBudgetAborts() throws {
        // A single self-jumping instruction runs forever without a budget; the budget must abort it.
        // Opcode 18 is a relative jump; -5 (one instruction back) loops onto itself.
        var code = Data([18])
        appendUInt32(UInt32(bitPattern: -5), to: &code)
        let program = try MakiBytecodeParser().parse(
            makeMinimalScript(code: code), source: WalSourceLocation(path: "/loop.maki"))
        var limits = MakiExecutionLimits.production
        limits.maximumInstructionsPerEvent = 50
        // The interpreter holds `dispatcher` weakly, so it must be kept alive here — a temporary
        // would deallocate immediately and `execute` would silently no-op past the budget check.
        let dispatcher = NoOpDispatcher()
        let interpreter = MakiInterpreter(dispatcher: dispatcher, limits: limits)
        XCTAssertThrowsError(try interpreter.execute(program: program, at: 0)) { error in
            XCTAssertEqual((error as? WalFailure)?.diagnostics.first?.code, .scriptBudgetExceeded)
        }
    }

    // MARK: - 7.6 Stress: timers, rapid load/teardown, malformed resources

    func testTimerCapUnderStress() throws {
        let timers = MakiTimerService(maximumActiveTimers: 8)
        for id in 0..<8 { XCTAssertNoThrow(try timers.schedule(id: UInt64(id), period: 1) {}) }
        XCTAssertThrowsError(try timers.schedule(id: 99, period: 1) {})
        XCTAssertEqual(timers.activeTimerCount, 8)
        // Rescheduling an existing id must not exceed the cap.
        XCTAssertNoThrow(try timers.schedule(id: 0, period: 1) {})
        XCTAssertEqual(timers.activeTimerCount, 8)
        timers.teardown()
        XCTAssertEqual(timers.activeTimerCount, 0)
    }

    func testRapidLoadTeardownCyclesAreClean() throws {
        let url = try makeArchive(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="16" h="16">
          <script file="main.maki"/>
        </layout></container></WasabiXML>
        """, script: makeMinimalScript(code: Data([33])))
        for _ in 0..<50 {
            let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
            let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
            try runtime.start()
            runtime.teardown()
            loaded.teardown()
            XCTAssertTrue(runtime.isTornDown)
            XCTAssertTrue(loaded.runtime.graph.isTornDown)
        }
    }

    func testMalformedImageResourceDegradesInsteadOfCrashing() throws {
        // A bitmap whose file is present but is not a valid image must not hard-fail the load.
        var garbage = Data(count: 64)
        for index in 0..<garbage.count { garbage[index] = UInt8(truncatingIfNeeded: index &* 7) }
        do {
            let runtime = try initialize(
                xml: "<WasabiXML><bitmap id=\"bg\" file=\"junk.png\"/></WasabiXML>",
                resources: ["junk.png": garbage])
            // If it loads, the invalid image must be recorded as a diagnostic, not silently ideal.
            XCTAssertFalse(runtime.diagnostics.isEmpty)
        } catch let failure as WalFailure {
            // A typed invalid-image failure is also acceptable (bounded, non-crashing).
            XCTAssertEqual(failure.diagnostics.first?.code, .invalidImageResource)
        }
    }

    func testManyGroupdefsExpandWithinBounds() throws {
        var xml = "<WasabiXML>"
        for index in 0..<2_000 { xml += "<groupdef id=\"g\(index)\" inherit_group=\"wasabi.button\"/>" }
        xml += "</WasabiXML>"
        let runtime = try initialize(xml: xml)
        XCTAssertTrue(runtime.diagnostics.filter { $0.severity == .error }.isEmpty)
    }

    // MARK: - 7.7 Profiling instrumentation

    /// Informational profiling of the hot path (load → graph build → script start → teardown). This
    /// records wall-clock metrics via XCTest's `measure` without a hard time assertion (CI-timing
    /// safe). Phase 7 profiling found no hotspot warranting Metal; AppKit/Core Graphics drawing stays
    /// the renderer — see the Phase 7 handoff. This test guards that the path stays measurable and
    /// does not regress into a crash/hang.
    func testProfileLoadAndTeardownHotPath() throws {
        let url = try makeArchive(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="64" h="64">
          <script file="main.maki"/>
        </layout></container></WasabiXML>
        """, script: makeMinimalScript(code: Data([33])))
        measure {
            for _ in 0..<20 {
                guard let loaded = try? WinampModernSkinLoader(engineStore: nil).load(from: url),
                      let runtime = try? WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
                else { XCTFail("profiling load failed"); return }
                try? runtime.start()
                runtime.teardown()
                loaded.teardown()
            }
        }
    }

    // MARK: - Helpers

    /// Small deterministic PRNG (xorshift64) so fuzz runs are reproducible across machines/CI.
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

    private final class NoOpDispatcher: MakiMethodDispatching {
        func signature(for method: String, classGUID: String?) -> MakiMethodSignature? { nil }
        func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                    program: MakiProgram) throws -> MakiValue { .null }
        func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
            MakiObjectReference(.system)
        }
    }

    private func initialize(xml: String, resources: [String: Data] = [:]) throws -> WasabiSkinRuntime {
        var allResources = resources
        allResources["skin.xml"] = Data(xml.utf8)
        let provider = try WalMemoryResourceProvider(resources: allResources)
        let vfs = try WalVirtualFileSystem(skinName: "Synthetic", skin: provider)
        let document = try WalXMLDocumentLoader(vfs: vfs).load(entryPath: "/Skins/Synthetic/skin.xml")
        return try WasabiSkinInitializer(vfs: vfs).initialize(document: document)
    }

    private func makeArchive(xml: String, script: Data?) throws -> URL {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        var entries: [(String, Data)] = [("skin.xml", Data(xml.utf8))]
        if let script { entries.append(("main.maki", script)) }
        for (path, payload) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase7Tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(bytes)
    }

    private func makeMinimalScript(code: Data) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(1, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString("onscriptloaded", to: &data)
        appendUInt32(1, to: &data)
        data.append(contentsOf: [0, 1])
        for _ in 0..<5 { appendUInt16(0, to: &data) }
        data.append(contentsOf: [1, 1])
        appendUInt32(0, to: &data)
        appendUInt32(1, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }
}
