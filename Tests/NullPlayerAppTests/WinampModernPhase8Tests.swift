import XCTest
@testable import NullPlayer

/// Phase 8 — coverage for defects found by actually running the engine against the north-star
/// target (cPro-Bento + the ClassicPro engine) rather than headless synthetic fixtures.
final class WinampModernPhase8Tests: XCTestCase {

    // MARK: - MAKI opcode 104: dynamic `Member` access

    /// The ClassicPro engine declares extension members (`Member int CProWidget.custombg;`) and
    /// assigns them (`drawer_equalizer.custombg = 2;`). The compiler emits opcode 104 with the
    /// member's declared value type as its immediate. Before this was implemented, loading
    /// cPro-Bento hard-failed with "Unsupported MAKI opcode 104".
    func testMemberAccessRoundTripsThroughObjectStorage() throws {
        // v0 = system object, v1 = "custombg" (string constant), v2 = 7, v3 = result slot.
        var code = Data()
        // v0.custombg = v2
        code.append(pushVariable(0))
        code.append(pushVariable(1))
        code.append(memberAccess(.integer))
        code.append(pushVariable(2))
        code.append(Data([48]))                 // assign through the lvalue
        code.append(Data([2]))                  // discard the assignment's result
        // v3 = v0.custombg
        code.append(pushVariable(0))
        code.append(pushVariable(1))
        code.append(memberAccess(.integer))
        code.append(assignToVariable(3))

        let program = try MakiBytecodeParser().parse(
            makeScript(code: code), source: WalSourceLocation(path: "/member.maki"))
        let dispatcher = NoOpDispatcher()
        let interpreter = MakiInterpreter(dispatcher: dispatcher)
        try interpreter.execute(program: program, at: 0)

        XCTAssertEqual(program.variables[3].value.integerValue, 7,
                       "Reading the member back must observe the assigned value.")
    }

    /// Each declared type gets a typed zero value on first touch, before anything is assigned.
    func testUntouchedMemberReadsAsTypedDefault() throws {
        for (kind, expected) in [(MakiValueKind.integer, MakiValue.integer(0)),
                                 (.boolean, .boolean(false)),
                                 (.string, .string(""))] {
            var code = Data()
            code.append(pushVariable(0))
            code.append(pushVariable(1))
            code.append(memberAccess(kind))
            code.append(assignToVariable(3))

            let program = try MakiBytecodeParser().parse(
                makeScript(code: code), source: WalSourceLocation(path: "/default.maki"))
            let dispatcher = NoOpDispatcher()
            let interpreter = MakiInterpreter(dispatcher: dispatcher)
            try interpreter.execute(program: program, at: 0)
            XCTAssertEqual(program.variables[3].value.stringValue, expected.stringValue,
                           "Default for \(kind) should be \(expected).")
        }
    }

    /// A float/double constant is stored as two 16-bit halves, and the high half must be widened
    /// *before* it is shifted into place: `(0x80 | hi) << 16` on a `UInt16` shifts the implicit
    /// leading one and every stored bit clean out of the word, leaving only the low half. 2.55
    /// decoded as 0.003 that way, so a script's float arithmetic quietly did nothing — Love is War
    /// Miku's volume buttons ran their whole handler and moved the level by a fraction of a step.
    func testFloatConstantsDecodeToTheirRealValue() throws {
        let program = try MakiBytecodeParser().parse(
            makeScript(code: Data()), source: WalSourceLocation(path: "/float.maki"))
        XCTAssertEqual(program.variables[5].value.doubleValue, 2.55, accuracy: 0.0001)
    }

    /// The immediate is a `MakiValueKind`, not a class index — a bogus one must be rejected at parse
    /// time rather than mis-typing storage at run time.
    func testMemberAccessWithUnknownValueTypeIsRejected() {
        var code = Data()
        code.append(pushVariable(0))
        code.append(pushVariable(1))
        code.append(Data([104]))
        appendUInt32(200, to: &code)            // not a MakiValueKind
        XCTAssertThrowsError(try MakiBytecodeParser().parse(
            makeScript(code: code), source: WalSourceLocation(path: "/bad.maki"))) { error in
            XCTAssertTrue(error is WalFailure)
        }
    }

    /// A member access on a non-object fails closed with a typed diagnostic instead of corrupting
    /// the stack or trapping.
    func testMemberAccessOnNonObjectFailsClosed() throws {
        var code = Data()
        code.append(pushVariable(2))            // an integer, not an object
        code.append(pushVariable(1))
        code.append(memberAccess(.integer))

        let program = try MakiBytecodeParser().parse(
            makeScript(code: code), source: WalSourceLocation(path: "/nonobject.maki"))
        let dispatcher = NoOpDispatcher()
        let interpreter = MakiInterpreter(dispatcher: dispatcher)
        XCTAssertThrowsError(try interpreter.execute(program: program, at: 0)) { error in
            XCTAssertEqual((error as? WalFailure)?.diagnostics.first?.code, .invalidScript)
        }
    }

    /// Members are keyed per object, so the store cannot grow without bound from a hostile script.
    func testObjectMemberStorageIsBounded() throws {
        var limits = MakiExecutionLimits.production
        limits.maximumObjectMembers = 1
        var code = Data()
        code.append(pushVariable(0))
        code.append(pushVariable(1))
        code.append(memberAccess(.integer))
        code.append(Data([2]))
        code.append(pushVariable(0))
        code.append(pushVariable(4))            // a second, differently-named member
        code.append(memberAccess(.integer))

        let program = try MakiBytecodeParser().parse(
            makeScript(code: code), source: WalSourceLocation(path: "/bounded.maki"))
        let dispatcher = NoOpDispatcher()
        let interpreter = MakiInterpreter(dispatcher: dispatcher, limits: limits)
        XCTAssertThrowsError(try interpreter.execute(program: program, at: 0)) { error in
            XCTAssertEqual((error as? WalFailure)?.diagnostics.first?.code, .scriptBudgetExceeded)
        }
    }

    func testTeardownReleasesObjectMembers() throws {
        var code = Data()
        code.append(pushVariable(0))
        code.append(pushVariable(1))
        code.append(memberAccess(.integer))
        code.append(pushVariable(2))
        code.append(Data([48]))
        code.append(Data([2]))

        let program = try MakiBytecodeParser().parse(
            makeScript(code: code), source: WalSourceLocation(path: "/teardown.maki"))
        let dispatcher = NoOpDispatcher()
        let interpreter = MakiInterpreter(dispatcher: dispatcher)
        try interpreter.execute(program: program, at: 0)
        interpreter.teardown()
        // Post-teardown execution is inert; the point is that this neither traps nor retains state.
        XCTAssertNoThrow(try interpreter.execute(program: program, at: 0))
    }

    // MARK: - XML parser progress guarantee

    /// Regression for the production hang found by the Phase 7 fuzz test: a stray '/' inside a tag
    /// matched no branch of the attribute scanner and parked the cursor forever.
    func testStraySlashVariantsAllTerminate() throws {
        let cases = ["<x a=\"1\" /b></x>", "<x /", "<x//>", "<x / a=\"1\"></x>", "<x /=/>"]
        for xml in cases {
            let parser = WalLenientXMLParser()
            _ = try? parser.parse(xml, path: "/t.xml")
        }
    }

    // MARK: - Opt-in: the app's real path against a user-supplied skin

    /// The Phase 6 opt-in acceptance stopped at load + topology, so it never parsed the engine's
    /// MAKI — which is why "Unsupported MAKI opcode 104" only appeared when the app was actually
    /// run. This drives the full controller path: load → script runtime → start, and reports what
    /// the skin still cannot do.
    ///
    ///     WINAMP_MODERN_ENGINE=/path/ClassicPro_2.01.exe \
    ///     WINAMP_MODERN_WAL=/path/cPro-Bento.wal \
    ///       swift test --filter testLocalSkinScriptRuntimeStartsWhenSupplied
    func testLocalSkinScriptRuntimeStartsWhenSupplied() throws {
        let env = ProcessInfo.processInfo.environment
        guard let walPath = env["WINAMP_MODERN_WAL"] else {
            throw XCTSkip("Set WINAMP_MODERN_WAL (and WINAMP_MODERN_ENGINE for cPro-Bento).")
        }
        var store: ClassicProEngineStore?
        if let enginePath = env["WINAMP_MODERN_ENGINE"] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("WinampModernPhase8-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let engineStore = ClassicProEngineStore(rootDirectory: directory)
            _ = try ClassicProEngineImporter(store: engineStore)
                .importEngine(from: URL(fileURLWithPath: enginePath))
            store = engineStore
        }

        let loaded = try WinampModernSkinLoader(engineStore: store)
            .load(from: URL(fileURLWithPath: walPath))
        defer { loaded.teardown() }

        let host = Host()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        defer { runtime.teardown() }
        try runtime.start()

        // Print the measured-demand signal (Phase 7.3) so a QA run captures it.
        let report = loaded.compatibilityReport(withRuntime: runtime)
        print("Winamp Modern compatibility [\(URL(fileURLWithPath: walPath).lastPathComponent)]:\n"
              + report.summary)
        for category in WinampModernCompatibilityReport.Category.allCases {
            let findings = report.findings.filter { $0.category == category }
            guard !findings.isEmpty else { continue }
            print("--- \(category.rawValue) (\(findings.count) distinct)")
            for finding in findings.sorted(by: { $0.count > $1.count }).prefix(30) {
                print("    [\(finding.count)x \(finding.severity)] \(finding.message)")
            }
        }
        XCTAssertFalse(runtime.isTornDown)
    }

    // MARK: - Fixtures

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

    private final class NoOpDispatcher: MakiMethodDispatching {
        func signature(for method: String, classGUID: String?) -> MakiMethodSignature? { nil }
        func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                    program: MakiProgram) throws -> MakiValue { .null }
        func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
            MakiObjectReference(.system)
        }
    }

    private func pushVariable(_ index: UInt32) -> Data {
        var data = Data([1])
        appendUInt32(index, to: &data)
        return data
    }

    private func assignToVariable(_ index: UInt32) -> Data {
        var data = Data([3])
        appendUInt32(index, to: &data)
        return data
    }

    private func memberAccess(_ kind: MakiValueKind) -> Data {
        var data = Data([104])
        appendUInt32(UInt32(kind.rawValue), to: &data)
        return data
    }

    /// A MAKI file with one class, one event method, and five variables:
    /// v0 system object, v1 = "custombg", v2 = 7, v3 = result slot, v4 = "other".
    private func makeScript(code: Data) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)

        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))

        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString("onscriptloaded", to: &data)

        appendUInt32(6, to: &data)                                  // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)     // v0
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)     // v1
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, initial: 7, to: &data) // v2
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, to: &data)    // v3
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)     // v4
        // v5: the double 2.55, as MAKI stores it — low mantissa half, then exponent + high half.
        appendVariable(typeOffset: MakiValueKind.double.rawValue, initial: 13107,
                       initial2: 16419, to: &data)

        appendUInt32(2, to: &data)                                  // constants
        appendUInt32(1, to: &data)
        appendString("custombg", to: &data)
        appendUInt32(4, to: &data)
        appendString("other", to: &data)

        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                initial: UInt16 = 0, initial2: UInt16 = 0, to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)          // subclass
        appendUInt16(initial, to: &data)
        appendUInt16(initial2, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)                      // global
        data.append(system ? 1 : 0)
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
}
