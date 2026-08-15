import XCTest
import ZIPFoundation
@testable import NullPlayer

final class WinampModernPhase3Tests: XCTestCase {
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
        var beginCount = 0
        var endCount = 0
        var actions: [String] = []

        func play() { actions.append("play") }
        func pause() { actions.append("pause") }
        func stop() { actions.append("stop") }
        func previous() { actions.append("previous") }
        func next() { actions.append("next") }
        func seek(to seconds: TimeInterval) { currentTime = seconds; actions.append("seek") }
        func openFiles() { actions.append("open") }
        func beginVisualizationConsumption() { beginCount += 1 }
        func endVisualizationConsumption() { endCount += 1 }
    }

    func testLocalCornerAmpBytecodeParsesWhenFixtureIsSupplied() throws {
        guard let path = ProcessInfo.processInfo.environment["WINAMP_MODERN_CORNERAMP_WAL"] else {
            throw XCTSkip("Set WINAMP_MODERN_CORNERAMP_WAL to a user-supplied CornerAmp_Redux.wal.")
        }
        let loaded = try WinampModernSkinLoader().load(from: URL(fileURLWithPath: path))
        defer { loaded.teardown() }

        let programs = try loaded.runtime.scriptBindings.map { binding in
            try MakiBytecodeParser().parse(
                loaded.vfs.data(at: binding.logicalPath, location: binding.source),
                source: binding.source,
                ownerID: binding.ownerID,
                parameter: binding.parameter
            )
        }
        XCTAssertFalse(programs.isEmpty)
        XCTAssertTrue(programs.allSatisfy { !$0.instructions.isEmpty && !$0.bindings.isEmpty })
        XCTAssertTrue(Set(programs.flatMap { $0.methods.map(\.name) }).isSuperset(of: [
            "onscriptloaded", "getcontainer", "setxmlparam", "setvolume", "seekto"
        ]))
    }

    func testLocalCornerAmpRunsFirstPaintScriptsAndBuildsInteractiveSceneWhenFixtureIsSupplied() throws {
        guard let path = ProcessInfo.processInfo.environment["WINAMP_MODERN_CORNERAMP_WAL"] else {
            throw XCTSkip("Set WINAMP_MODERN_CORNERAMP_WAL to a user-supplied CornerAmp_Redux.wal.")
        }
        let loaded = try WinampModernSkinLoader().load(from: URL(fileURLWithPath: path))
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host)
        defer {
            view.teardown()
            loaded.teardown()
        }

        try scripts.start()
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 246, height: 228))
        XCTAssertEqual(loaded.runtime.graph.objects(xmlID: "Main1").first?.attributes["visible"], "1")
        XCTAssertEqual(loaded.runtime.graph.objects(xmlID: "Main2").first?.attributes["visible"], "0")
        XCTAssertEqual(loaded.runtime.graph.objects(xmlID: "Previous").first?.attributes["x"], "13")
        XCTAssertGreaterThan(renderer.sceneNodes().count, 20)

        let play = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "Play").first)
        let playFrame = try XCTUnwrap(renderer.frame(of: play))
        XCTAssertTrue(renderer.object(at: CGPoint(x: playFrame.midX, y: playFrame.midY)) === play)
        let eventPoint = NSPoint(x: playFrame.midX, y: renderer.canvasSize.height - playFrame.midY)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: eventPoint,
                                                    modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil,
                                                    eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: eventPoint,
                                                  modifierFlags: [], timestamp: 0,
                                                  windowNumber: 0, context: nil,
                                                  eventNumber: 2, clickCount: 1, pressure: 0))
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        XCTAssertEqual(host.actions, ["play"])

        let width = Int(renderer.canvasSize.width)
        let height = Int(renderer.canvasSize.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        renderer.draw(in: try XCTUnwrap(context))
        let visiblePixels = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 8 }.count
        let coverage = Double(visiblePixels) / Double(width * height)
        XCTAssertGreaterThan(coverage, 0.10)
        XCTAssertLessThan(coverage, 0.90)
        XCTAssertEqual(loaded.runtime.state, .initialized)
        XCTAssertEqual(host.beginCount, 1)
    }

    func testMAKIParserAndInstructionBudgetRejectRunawayEvent() throws {
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
        data.append(0)
        data.append(1)
        appendUInt16(0, to: &data)
        for _ in 0..<4 { appendUInt16(0, to: &data) }
        data.append(1)
        data.append(1)
        appendUInt32(0, to: &data)
        appendUInt32(1, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(5, to: &data)
        data.append(18)
        appendUInt32(UInt32(bitPattern: -5), to: &data)

        let program = try MakiBytecodeParser().parse(data, source: WalSourceLocation(path: "/Synthetic/runaway.maki"))
        XCTAssertEqual(program.instructions.count, 1)
        let dispatcher = NoOpDispatcher()
        var limits = MakiExecutionLimits.production
        limits.maximumInstructionsPerEvent = 20
        let interpreter = MakiInterpreter(dispatcher: dispatcher, limits: limits)
        XCTAssertThrowsError(try interpreter.execute(program: program, at: 0)) { error in
            XCTAssertEqual((error as? WalFailure)?.diagnostics.first?.code, .scriptBudgetExceeded)
        }
    }

    func testTimerAndRuntimeTeardownReleaseAllConsumers() throws {
        let timers = MakiTimerService(maximumActiveTimers: 2)
        XCTAssertEqual(try timers.schedule(id: 1, period: 0.001) {}, 1.0 / 120.0, accuracy: 0.0001)
        XCTAssertEqual(try timers.schedule(id: 2, period: 1) {}, 1, accuracy: 0.0001)
        XCTAssertThrowsError(try timers.schedule(id: 3, period: 1) {})
        timers.teardown()
        XCTAssertEqual(timers.activeTimerCount, 0)
        XCTAssertTrue(timers.isTornDown)
    }

    func testScriptRuntimeTeardownReleasesTimersVisualizationAndGraph() throws {
        let xml = """
        <WasabiXML><container id="Main"><layout id="normal" w="10" h="10">
          <script file="main.maki"/>
        </layout></container></WasabiXML>
        """
        let url = try makeArchive(xml: xml, script: makeMinimalScript(code: Data([33])))
        let loaded = try WinampModernSkinLoader().load(from: url)
        let host = Host()
        let timers = MakiTimerService()
        _ = try timers.schedule(id: 7, period: 1) {}
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host, timers: timers)

        try runtime.start()
        XCTAssertEqual(host.beginCount, 1)
        XCTAssertEqual(timers.activeTimerCount, 1)
        runtime.teardown()
        loaded.teardown()

        XCTAssertEqual(host.endCount, 1)
        XCTAssertTrue(runtime.isTornDown)
        XCTAssertTrue(runtime.interpreter.isTornDown)
        XCTAssertTrue(timers.isTornDown)
        XCTAssertEqual(timers.activeTimerCount, 0)
        XCTAssertTrue(loaded.runtime.graph.isTornDown)
    }

    private final class NoOpDispatcher: MakiMethodDispatching {
        func signature(for method: String) -> MakiMethodSignature? { nil }
        func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                    program: MakiProgram) throws -> MakiValue { .null }
        func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
            MakiObjectReference(.system)
        }
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

    private func makeArchive(xml: String, script: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase3Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("main.maki", script)] {
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
