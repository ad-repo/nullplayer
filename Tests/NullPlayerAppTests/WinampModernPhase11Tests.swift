import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 11 — the MAKI surface cPro-Bento's ClassicPro engine needs. Every test here corresponds to a
/// call that aborted a real engine script's `onScriptLoaded`, taking the rest of that script's
/// wiring — menus, drawers, the SUI — down with it. The measured list came from the render harness's
/// compatibility report, and each receiver was pinned against the engine's shipped `.m` sources.
final class WinampModernPhase11Tests: XCTestCase {

    // MARK: - `delete`

    /// `delete obj` is an *expression*: the compiler emits `push; delete; pop`, so the delete must
    /// leave its operand for that discard pop. Consuming it underflowed the value stack — which is
    /// what killed `mainmenu.maki` three statements into `onScriptLoaded`, right after it read the
    /// skin's colours out of a `Map` and deleted it.
    func testDeleteLeavesItsOperandForTheCompilersDiscardPop() throws {
        var code = Data()
        code.append(pushVariable(0))    // the object
        code.append(Data([97]))         // delete
        code.append(Data([2]))          // the statement's own discard pop
        let program = try MakiBytecodeParser().parse(makeScript(code: code, methodName: "getid"),
                                                     source: WalSourceLocation(path: "/delete.maki"))
        let interpreter = MakiInterpreter(dispatcher: NoOpDispatcher())
        XCTAssertNoThrow(try interpreter.execute(program: program, at: 0),
                         "delete must not consume the value its own discard pop expects")
    }

    // MARK: - `Map`

    /// A `Map` is asked for its size and for whole pixels, not only for the single channel
    /// `getValue` returns. The channel index is **BGRA**, pinned by `player.maki` building a
    /// `colorbandpeak="r,g,b"` attribute out of channels 2, 1 and 0 in that order.
    func testMapReportsItsSizeAndPixelChannels() throws {
        let (runtime, program) = try makeRuntime()
        let map = try runtime.makeObject(classGUID: String(repeating: "0", count: 32), program: program)
        _ = try runtime.invoke(method: "loadMap", on: map, arguments: [.string("band.green")], program: program)

        XCTAssertEqual(try runtime.invoke(method: "getWidth", on: map, arguments: [], program: program).integerValue, 16)
        XCTAssertEqual(try runtime.invoke(method: "getHeight", on: map, arguments: [], program: program).integerValue, 16)

        // Row 4 of the fixture sheet is solid green.
        func channel(_ index: Int32) throws -> Int32 {
            try runtime.invoke(method: "getARGBValue", on: map,
                               arguments: [.integer(0), .integer(5), .integer(index)],
                               program: program).integerValue
        }
        XCTAssertEqual(try channel(0), 0, "channel 0 is blue")
        XCTAssertEqual(try channel(1), 255, "channel 1 is green")
        XCTAssertEqual(try channel(2), 0, "channel 2 is red")
        XCTAssertEqual(try channel(3), 255, "channel 3 is alpha")
    }

    /// `loadMap` takes a *path* as readily as a declared bitmap id. ClassicPro's install check is
    /// exactly this form — it loads `…/engine/image/installed.png` and treats any width but 1 as
    /// "the plugin is missing", which made cPro-Bento decide the engine was absent and try to switch
    /// skins before it had built anything.
    func testMapLoadsFromAPathAsWellAsAResourceIdentifier() throws {
        let (runtime, program) = try makeRuntime()
        let map = try runtime.makeObject(classGUID: String(repeating: "0", count: 32), program: program)
        _ = try runtime.invoke(method: "loadMap", on: map, arguments: [.string("sheet.png")], program: program)
        XCTAssertEqual(try runtime.invoke(method: "getWidth", on: map, arguments: [], program: program).integerValue, 16)
    }

    // MARK: - `isInvalid`

    /// ClassicPro probes for optional artwork by declaring a hidden layer over it and asking whether
    /// that layer is invalid. Answering "valid" for a skin that ships no `mainframe_lr.png` sent
    /// `player.maki` on to swap the window frame over to bitmaps that do not exist — visible as
    /// holes punched through the window's edges.
    func testIsInvalidDistinguishesAMissingImageFromAPresentOne() throws {
        let (runtime, program) = try makeRuntime()
        func isInvalid(_ id: String) throws -> Bool {
            let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: id).first)
            return try runtime.invoke(method: "isInvalid",
                                      on: MakiObjectReference(.gui(object.stableID)),
                                      arguments: [], program: program).truthy
        }
        XCTAssertFalse(try isInvalid("present"), "a layer whose bitmap resolved is valid")
        XCTAssertTrue(try isInvalid("absent"), "a layer whose bitmap file is not in the archive is not")
    }

    /// The other half of the question: an object that was never found at all. The generic
    /// null-receiver rule answers `null` (falsy), which would claim the missing object is fine.
    func testIsInvalidOnANullReceiverIsTrue() throws {
        let (runtime, _) = try makeRuntime()
        XCTAssertTrue(runtime.nullReceiverResult(for: "isInvalid").truthy)
        XCTAssertFalse(runtime.nullReceiverResult(for: "getId").truthy,
                       "every other call on a null object stays a no-op")
    }

    // MARK: - Config

    /// A button bound with `cfgattrib="{GUID};Name"` reports that attribute's value. The GUID is the
    /// section key — the same addressing `getItemByGuid` uses, so the two agree.
    func testGetCurCfgValReadsTheBoundConfigAttribute() throws {
        let (runtime, program) = try makeRuntime()
        runtime.loadedSkin.configuration.setInteger(2, section: "{45F3F7C1}", key: "Repeat")
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "repeat.button").first)
        let value = try runtime.invoke(method: "getCurCfgVal", on: MakiObjectReference(.gui(object.stableID)),
                                       arguments: [], program: program)
        XCTAssertEqual(value.integerValue, 2)
    }

    /// `getItemByGuid` and `getItem` name the same private store, so a value written through one is
    /// visible through the other.
    func testGetItemByGuidAddressesTheSameConfigurationAsGetItem() throws {
        let (runtime, program) = try makeRuntime()
        let item = try runtime.invoke(method: "getItemByGuid", on: MakiObjectReference(.system),
                                      arguments: [.string("{280876CF}")], program: program)
        let reference = try XCTUnwrap({ if case .object(let value) = item { return value } else { return nil } }())
        let attribute = try runtime.invoke(method: "newAttribute", on: reference,
                                           arguments: [.string("Always on top"), .string("1")], program: program)
        let attributeReference = try XCTUnwrap({ if case .object(let value) = attribute { return value } else { return nil } }())
        XCTAssertEqual(try runtime.invoke(method: "getData", on: attributeReference,
                                          arguments: [], program: program).stringValue, "1")
        XCTAssertEqual(runtime.loadedSkin.configuration.string(section: "{280876CF}", key: "Always on top"), "1")
    }

    // MARK: - System

    /// Years since 1900, as C's `tm_year`. `cproabout.m` pins the scale twice: it computes an age as
    /// `1899 + getDateYear(...) - birthYear` (+1 once the birthday has passed) and leap-year-tests
    /// the same value with `% 4`.
    func testGetDateYearIsYearsSince1900() throws {
        let (runtime, program) = try makeRuntime()
        // 2024-02-29, a leap day: tm_year 124, and 124 % 4 == 0.
        var components = DateComponents()
        components.year = 2024
        components.month = 2
        components.day = 29
        components.hour = 12
        let date = try XCTUnwrap(Calendar.current.date(from: components))
        let value = try runtime.invoke(method: "getDateYear", on: MakiObjectReference(.system),
                                       arguments: [.integer(Int32(date.timeIntervalSince1970))],
                                       program: program)
        XCTAssertEqual(value.integerValue, 124)
        XCTAssertEqual(value.integerValue % 4, 0, "the engine leap-year-tests this value directly")
    }

    /// `getPosition` shares its unit with `getPlayItemLength` — `SC-ProgressGrid` divides one by the
    /// other, and `info.maki` runs the length through `integerToTime`, which pins both to seconds.
    func testGetPositionSharesItsUnitWithPlayItemLength() throws {
        let host = TestHost()
        host.currentTime = 73
        host.duration = 245
        let (runtime, program) = try makeRuntime(host: host)
        XCTAssertEqual(try runtime.invoke(method: "getPosition", on: MakiObjectReference(.system),
                                          arguments: [], program: program).integerValue, 73)
        XCTAssertEqual(try runtime.invoke(method: "getPlayItemLength", on: MakiObjectReference(.system),
                                          arguments: [], program: program).integerValue, 245)
    }

    /// A skin asking the player to load a *different* skin is a host decision. The call is accepted
    /// so the calling script survives, and does nothing.
    func testSwitchSkinIsAcceptedAndInert() throws {
        let (runtime, program) = try makeRuntime()
        XCTAssertNoThrow(try runtime.invoke(method: "switchSkin", on: MakiObjectReference(.system),
                                            arguments: [.string("winamp classic")], program: program))
    }

    // MARK: - Helpers

    private func makeRuntime(host: WinampModernHost? = nil) throws -> (WinampModernScriptRuntime, MakiProgram) {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="band.green" file="sheet.png" x="0" y="0" w="16" h="16"/>
            <bitmap id="band.absent" file="nowhere.png" x="0" y="0" w="16" h="16"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <layer id="present" image="band.green" x="0" y="0" w="4" h="4"/>
              <layer id="absent" image="band.absent" x="4" y="0" w="4" h="4"/>
              <togglebutton id="repeat.button" x="8" y="0" w="4" h="4"
                            cfgattrib="{45F3F7C1};Repeat"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host ?? TestHost())
        addTeardownBlock { runtime.teardown() }
        // A program is only a source location and a parameter to these calls; the fixture skin
        // declares no scripts of its own.
        let program = try MakiBytecodeParser().parse(makeScript(code: Data(), methodName: "getid"),
                                                     source: WalSourceLocation(path: "/Skins/Synthetic/skin.xml"))
        return (runtime, program)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase11Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", try makeGreenPNG())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    /// 16×16, solid opaque green.
    private func makeGreenPNG() throws -> Data {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index + 1] = 255
            pixels[index + 3] = 255
        }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: side, height: side,
                                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    // MARK: - Minimal MAKI assembler (mirrors the Phase 8/10 helpers)

    private final class NoOpDispatcher: MakiMethodDispatching {
        func signature(for method: String, classGUID: String?) -> MakiMethodSignature? {
            .init(argumentCount: 0, returnKind: .string)
        }
        func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                    program: MakiProgram) throws -> MakiValue { .string("called") }
        func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
            MakiObjectReference(.system)
        }
    }

    private func pushVariable(_ index: UInt32) -> Data {
        var data = Data([1])
        appendUInt32(index, to: &data)
        return data
    }

    private func makeScript(code: Data, methodName: String) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)

        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))

        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString(methodName, to: &data)

        appendUInt32(1, to: &data)                                  // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)

        appendUInt32(0, to: &data)                                  // constants
        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                initial: UInt16 = 0, to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)
        appendUInt16(initial, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)
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

    private final class TestHost: WinampModernHost {
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
