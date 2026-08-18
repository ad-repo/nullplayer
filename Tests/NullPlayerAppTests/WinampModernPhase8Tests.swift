import XCTest
import ZIPFoundation
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

    /// A member on a **null** object is tolerated, exactly as a method call on one is: the read gives
    /// the declared type's default and the write goes nowhere.
    ///
    /// Skins depend on it. ClassicPro's tab strip opens every click with `closeTab(lastActiveT)`, and
    /// on the *first* click `lastActiveT` is still NULL while `closeTab` reads `.ID` off it — so
    /// throwing here took the whole handler down and no tab in cPro-Bento could ever be activated
    /// (Phase 24; TASKS §15.6 had blamed the tab strip's script never running, which it does).
    func testMemberAccessOnANullObjectReadsTheTypedDefault() throws {
        var code = Data()
        code.append(pushVariable(6))            // a null object
        code.append(pushVariable(1))
        code.append(memberAccess(.integer))
        code.append(assignToVariable(3))

        let program = try MakiBytecodeParser().parse(
            makeScript(code: code), source: WalSourceLocation(path: "/nullowner.maki"))
        let interpreter = MakiInterpreter(dispatcher: NoOpDispatcher())
        XCTAssertNoThrow(try interpreter.execute(program: program, at: 0))
        XCTAssertEqual(program.variables[3].value.integerValue, 0,
                       "the declared type's default, and no storage anywhere to read it back from")
    }

    /// A member access on a non-object that is **not** null still fails closed: MAKI's compiler cannot
    /// emit one on an integer, so seeing it means the stack is not what the instruction thinks it is.
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

    // MARK: - `findObject` is wide; `getObject` stays narrow

    func testFindObjectFindsAMatchInTheReceiversOwnSubtree() throws {
        let runtime = try makeGraphRuntime()
        let receiver = try object(named: "receiver", in: runtime)
        let expected = try object(named: "near.target", in: runtime)

        XCTAssertEqual(try invokeLookup("findobject", id: "near.target", from: receiver,
                                        in: runtime), expected.stableID)
    }

    /// Defix's core script holds `sui.content` and asks it for `switch.ml`, which lives in a sibling
    /// subtree. This is the case that changed `findObject` for every skin.
    func testFindObjectFindsAMatchInASiblingSubtree() throws {
        let runtime = try makeGraphRuntime()
        let receiver = try object(named: "receiver", in: runtime)
        let expected = try object(named: "sibling.target", in: runtime)

        XCTAssertEqual(try invokeLookup("findobject", id: "sibling.target", from: receiver,
                                        in: runtime), expected.stableID)
    }

    func testFindObjectPrefersTheReceiversSubtreeWhenIDsRepeat() throws {
        let runtime = try makeGraphRuntime()
        let receiver = try object(named: "receiver", in: runtime)
        let matches = runtime.loadedSkin.runtime.graph.objects(xmlID: "duplicate.target")
        let expected = try XCTUnwrap(receiver.children.first { $0.xmlID == "duplicate.target" })
        XCTAssertEqual(matches.count, 2, "the fixture must make the lookup order observable")

        XCTAssertEqual(try invokeLookup("findobject", id: "duplicate.target", from: receiver,
                                        in: runtime), expected.stableID)
    }

    func testFindObjectDoesNotEscapeTheReceiversContainer() throws {
        let runtime = try makeGraphRuntime()
        let receiver = try object(named: "receiver", in: runtime)
        XCTAssertNotNil(runtime.loadedSkin.runtime.graph.objects(xmlID: "other.container.target").first,
                        "the target exists, but only in a different container")

        XCTAssertNil(try invokeLookup("findobject", id: "other.container.target", from: receiver,
                                      in: runtime))
    }

    func testGetObjectStillDoesNotSearchSiblingSubtrees() throws {
        let runtime = try makeGraphRuntime()
        let receiver = try object(named: "receiver", in: runtime)

        XCTAssertNil(try invokeLookup("getobject", id: "sibling.target", from: receiver,
                                      in: runtime))
    }

    // MARK: - `embed_xui` event forwarding

    func testEmbeddedXUITargetForwardsMouseEventsToItsEmbeddingGroup() throws {
        let runtime = try makeEmbeddedXUIRuntime()
        let trap = try object(named: "mouse.trap", in: runtime)
        let inner = try object(named: "inner", in: runtime)
        XCTAssertTrue(runtime.hasBinding(for: inner, event: "onleftclick"),
                      "the synthetic script must be bound to the group, not the child")

        XCTAssertEqual(try runtime.dispatch(object: trap, event: "onleftclick"), 1)
    }

    func testEmbeddedXUITargetDoesNotForwardNonMouseEvents() throws {
        let runtime = try makeEmbeddedXUIRuntime()
        let trap = try object(named: "mouse.trap", in: runtime)
        let inner = try object(named: "inner", in: runtime)
        XCTAssertTrue(runtime.hasBinding(for: inner, event: "onsetvisible"))

        XCTAssertEqual(try runtime.dispatch(object: trap, event: "onsetvisible",
                                            arguments: [.boolean(true)]), 0,
                       "forwarding lifecycle/data events would run one occurrence twice")
        XCTAssertEqual(try runtime.dispatch(object: inner, event: "onsetvisible",
                                            arguments: [.boolean(true)]), 1,
                       "the zero above must come from the forwarding guard, not a missing binding")
    }

    func testObjectThatIsNotTheEmbeddedXUITargetForwardsNothing() throws {
        let runtime = try makeEmbeddedXUIRuntime()
        let other = try object(named: "other.button", in: runtime)

        XCTAssertEqual(try runtime.dispatch(object: other, event: "onleftclick"), 0)
    }

    func testEmbeddedXUIForwardingStopsAfterTheMatchingAncestor() throws {
        let runtime = try makeEmbeddedXUIRuntime()
        let inner = try object(named: "inner", in: runtime)

        // `inner` is itself the object named by the outer group's `embed_xui`. Its own handler and
        // the outer handler each run once; forwarding directly to the owner must not recurse.
        XCTAssertEqual(try runtime.dispatch(object: inner, event: "onleftclick"), 2)
    }

    // MARK: - `cfgattrib` mutation and notification

    func testConfigAttributeFlipPersistsAndAnUnboundObjectIsIgnored() throws {
        let runtime = try makeConfigRuntime()
        let bound = try object(named: "config.control", in: runtime)
        let unbound = try object(named: "ordinary.control", in: runtime)

        XCTAssertFalse(runtime.configValue(of: bound))
        XCTAssertTrue(runtime.toggleConfigAttribute(of: bound))
        XCTAssertTrue(runtime.configValue(of: bound))
        XCTAssertTrue(runtime.toggleConfigAttribute(of: bound))
        XCTAssertFalse(runtime.configValue(of: bound))
        XCTAssertFalse(runtime.toggleConfigAttribute(of: unbound))
    }

    func testConfigAttributeFlipNotifiesEveryRegisteredDynamicObject() throws {
        let runtime = try makeConfigRuntime()
        let bound = try object(named: "config.control", in: runtime)
        let program = try XCTUnwrap(runtime.programs.first)
        guard case .object(let first) = program.variables[2].value,
              case .object(let second) = program.variables[4].value else {
            return XCTFail("the fixture must register two dynamic config attributes")
        }
        XCTAssertNotEqual(first, second, "each script registration is a distinct dynamic object")
        var notifications = 0
        runtime.dispatchObserver = { event, _, failure in
            if event == "ondatachanged" && failure == nil { notifications += 1 }
        }

        XCTAssertTrue(runtime.toggleConfigAttribute(of: bound))
        XCTAssertEqual(notifications, 2,
                       "every object registered against the same section/key must be told")
    }

    // MARK: - `isMouseOverRect` uses the receiver's window

    func testIsMouseOverRectDistinguishesInsideFromOutside() throws {
        let runtime = try makeGraphRuntime()
        let receiver = try object(named: "receiver", in: runtime)
        runtime.resolvedGeometryRequested = { object in
            guard object === receiver else { return nil }
            let frame = CGRect(x: 20, y: 30, width: 40, height: 10)
            return (frame, frame)
        }
        runtime.mousePositionInObjectSpaceRequested = { _ in CGPoint(x: 25, y: 35) }
        XCTAssertTrue(try invokeMouseOver(receiver, in: runtime))

        runtime.mousePositionInObjectSpaceRequested = { _ in CGPoint(x: 19, y: 35) }
        XCTAssertFalse(try invokeMouseOver(receiver, in: runtime))
    }

    func testIsMouseOverRectRequestsTheAuxiliaryObjectsOwnWindowSpace() throws {
        let runtime = try makeGraphRuntime()
        let main = try object(named: "receiver", in: runtime)
        let auxiliary = try object(named: "other.container.target", in: runtime)
        runtime.resolvedGeometryRequested = { object in
            guard object === main || object === auxiliary else { return nil }
            let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
            return (frame, frame)
        }
        runtime.mousePositionInObjectSpaceRequested = { object in
            object === auxiliary ? CGPoint(x: 5, y: 5) : CGPoint(x: 50, y: 50)
        }

        XCTAssertTrue(try invokeMouseOver(auxiliary, in: runtime))
        XCTAssertFalse(try invokeMouseOver(main, in: runtime),
                       "the main window's cursor position is a different coordinate space")
    }

    func testIsMouseOverRectIsFalseWhenNoWindowCanPlaceTheObject() throws {
        let runtime = try makeGraphRuntime()
        let receiver = try object(named: "receiver", in: runtime)
        runtime.resolvedGeometryRequested = { _ in
            let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
            return (frame, frame)
        }

        XCTAssertFalse(try invokeMouseOver(receiver, in: runtime))
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

    private func makeGraphRuntime() throws -> WinampModernScriptRuntime {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <group id="receiver">
                <layer id="near.target"/>
                <layer id="duplicate.target"/>
              </group>
              <group id="sibling">
                <layer id="sibling.target"/>
                <layer id="duplicate.target"/>
              </group>
            </layout>
          </container>
          <container id="Other">
            <layout id="normal" w="100" h="100">
              <layer id="other.container.target"/>
            </layout>
          </container>
        </WasabiXML>
        """
        return try makeRuntime(xml: xml)
    }

    private func makeEmbeddedXUIRuntime() throws -> WinampModernScriptRuntime {
        let xml = """
        <WasabiXML>
          <groupdef id="synthetic.inner" xuitag="Synthetic:Inner" embed_xui="mouse.trap">
            <button id="mouse.trap"/>
            <button id="other.button"/>
            <script file="events.maki"/>
          </groupdef>
          <groupdef id="synthetic.outer" xuitag="Synthetic:Outer" embed_xui="inner">
            <Synthetic:Inner id="inner"/>
            <script file="events.maki"/>
          </groupdef>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <Synthetic:Outer id="outer"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let runtime = try makeRuntime(xml: xml, files: [("events.maki", makeEventScript())])
        try runtime.start()
        return runtime
    }

    private func makeConfigRuntime() throws -> WinampModernScriptRuntime {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="40" h="20">
              <togglebutton id="config.control" cfgattrib="{SYNTHETIC};Window;Control"/>
              <button id="ordinary.control"/>
            </layout>
          </container>
          <scripts><script file="config.maki"/></scripts>
        </WasabiXML>
        """
        let runtime = try makeRuntime(xml: xml,
                                      files: [("config.maki", makeConfigNotificationScript())])
        try runtime.start()
        return runtime
    }

    private func makeRuntime(xml: String, files: [(String, Data)] = []) throws
        -> WinampModernScriptRuntime {
        let loaded = try WinampModernSkinLoader(engineStore: nil)
            .load(from: try makeArchive(files: [("skin.xml", Data(xml.utf8))] + files))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func object(named xmlID: String, in runtime: WinampModernScriptRuntime) throws
        -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: xmlID).first)
    }

    private func invokeLookup(_ method: String, id: String, from object: WasabiObject,
                              in runtime: WinampModernScriptRuntime) throws -> WasabiObjectID? {
        let value = try runtime.invoke(method: method, on: MakiObjectReference(.gui(object.stableID)),
                                       arguments: [.string(id)], program: emptyProgram())
        guard case .object(let reference) = value, case .gui(let objectID) = reference.kind else {
            return nil
        }
        return objectID
    }

    private func invokeMouseOver(_ object: WasabiObject, in runtime: WinampModernScriptRuntime) throws
        -> Bool {
        try runtime.invoke(method: "ismouseoverrect",
                           on: MakiObjectReference(.gui(object.stableID)), arguments: [],
                           program: emptyProgram()).truthy
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private func makeArchive(files: [(String, Data)]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase8Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    /// An object-owned script that binds `onLeftClick` and `onSetVisible` to its script group.
    /// `onScriptLoaded` performs `group = getScriptGroup()`; each event handler is an empty return.
    private func makeEventScript() -> Data {
        var setup = Data()
        setup.append(pushVariable(0))
        setup.append(callMethod(1))
        setup.append(assignToVariable(1))
        setup.append(Data([33]))
        let handlerOffset = UInt32(setup.count)
        setup.append(Data([33]))

        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))

        let methods = ["onscriptloaded", "getscriptgroup", "onleftclick", "onsetvisible"]
        appendUInt32(UInt32(methods.count), to: &data)
        for method in methods {
            appendUInt16(0, to: &data)
            appendUInt16(0, to: &data)
            appendString(method, to: &data)
        }

        appendUInt32(2, to: &data)
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)
        appendVariable(typeOffset: 0, object: true, to: &data)
        appendUInt32(0, to: &data)

        appendUInt32(3, to: &data)
        for (variable, method, offset) in [(UInt32(0), UInt32(0), UInt32(0)),
                                           (1, 2, handlerOffset), (1, 3, handlerOffset)] {
            appendUInt32(variable, to: &data)
            appendUInt32(method, to: &data)
            appendUInt32(offset, to: &data)
        }
        appendUInt32(UInt32(setup.count), to: &data)
        data.append(setup)
        return data
    }

    /// Registers the same config attribute twice and binds `onDataChanged` on both returned objects.
    private func makeConfigNotificationScript() -> Data {
        var setup = Data()
        func appendRegistration(groupVariable: UInt32, attributeVariable: UInt32) {
            setup.append(pushVariable(0))
            setup.append(pushVariable(5))
            setup.append(callMethod(1))
            setup.append(assignToVariable(groupVariable))
            setup.append(pushVariable(groupVariable))
            // MAKI arguments are pushed right-to-left: default first, then the attribute name.
            setup.append(pushVariable(7))
            setup.append(pushVariable(6))
            setup.append(callMethod(2))
            setup.append(assignToVariable(attributeVariable))
        }
        appendRegistration(groupVariable: 1, attributeVariable: 2)
        appendRegistration(groupVariable: 3, attributeVariable: 4)
        setup.append(Data([33]))
        let handlerOffset = UInt32(setup.count)
        setup.append(Data([33]))

        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))

        let methods = ["onscriptloaded", "getitembyguid", "newattribute", "ondatachanged"]
        appendUInt32(UInt32(methods.count), to: &data)
        for method in methods {
            appendUInt16(0, to: &data)
            appendUInt16(0, to: &data)
            appendString(method, to: &data)
        }

        appendUInt32(8, to: &data)
        appendVariable(typeOffset: 0, object: true, system: true, to: &data) // system
        for _ in 0..<4 { appendVariable(typeOffset: 0, object: true, to: &data) }
        for _ in 0..<3 { appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data) }

        appendUInt32(3, to: &data)
        for (variable, value) in [(UInt32(5), "{SYNTHETIC}"),
                                  (6, "Window;Control"), (7, "0")] {
            appendUInt32(variable, to: &data)
            appendString(value, to: &data)
        }

        appendUInt32(3, to: &data)
        for (variable, method, offset) in [(UInt32(0), UInt32(0), UInt32(0)),
                                           (2, 3, handlerOffset), (4, 3, handlerOffset)] {
            appendUInt32(variable, to: &data)
            appendUInt32(method, to: &data)
            appendUInt32(offset, to: &data)
        }
        appendUInt32(UInt32(setup.count), to: &data)
        data.append(setup)
        return data
    }

    private func callMethod(_ index: UInt32) -> Data {
        var data = Data([24])
        appendUInt32(index, to: &data)
        return data
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

        appendUInt32(7, to: &data)                                  // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)     // v0
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)     // v1
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, initial: 7, to: &data) // v2
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, to: &data)    // v3
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)     // v4
        // v5: the double 2.55, as MAKI stores it — low mantissa half, then exponent + high half.
        appendVariable(typeOffset: MakiValueKind.double.rawValue, initial: 13107,
                       initial2: 16419, to: &data)
        // v6: an object variable that is **null** — a script's own `Group`/`Tab` handle before anything
        // has been assigned to it. Appended last so no existing index moves.
        appendVariable(typeOffset: 0, object: true, to: &data)

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
