import XCTest
@testable import NullPlayer

/// ONYX V2 — the defects its seek arc, File Type readout and mini player found, one engine rule each.
/// The skin's own record is `skills/winamp-modern-skin-guide/skins/onyx-v2.md`; the two renderer
/// rules are pinned in `WinampModernRenderPixelTests`.
final class WinampModernOnyxV2Tests: XCTestCase {

    // MARK: - MAKI integer constants are 32 bits

    /// A constant's two 16-bit halves are one value, low half first. Reading only the low half turned
    /// ONYX's one-hour test (3600000 ms = 0x0036_EE80) into 61056, so every track over a minute took
    /// the skin's long-time branch — the one calling the method below that did not exist.
    func testAnIntegerConstantKeepsItsHighHalf() throws {
        let program = try MakiBytecodeParser().parse(
            makeScript(integerConstants: [(0xEE80, 0x0036), (0xFFFF, 0xFFFF), (42, 0)]),
            source: WalSourceLocation(path: "/Skins/Synthetic/skin.xml"))
        XCTAssertEqual(program.variables[1].value.integerValue, 3_600_000)
        XCTAssertEqual(program.variables[2].value.integerValue, -1, "the high half carries the sign")
        XCTAssertEqual(program.variables[3].value.integerValue, 42)
    }

    // MARK: - System.integerToLongTime

    /// The same milliseconds as `integerToTime`, as `h:mm:ss`. ONYX's seek handler aborted on it
    /// before `seekTo`, so the seek arc never seeked.
    func testIntegerToLongTimeIsHoursMinutesSeconds() throws {
        let (runtime, program) = try makeRuntime()
        XCTAssertEqual(try system(runtime, program, "integerToLongTime", [.integer(3_725_000)]).stringValue,
                       "1:02:05")
        XCTAssertEqual(try system(runtime, program, "integerToLongTime", [.integer(-5)]).stringValue, "0:00:00")
    }

    // MARK: - getPlayItemString is the item's location

    /// Winamp answers the entry's filename or URL, and skins hand it to `getExtension`. ONYX's File
    /// Type readout printed the title's tail while this answered the display title.
    func testThePlayItemStringIsTheLocationWithTheTitleAsFallback() throws {
        let host = LocationHost()
        host.trackTitle = "Some Artist - Some Song"
        let (runtime, program) = try makeRuntime(host: host)

        host.trackPath = "/Music/song.flac"
        XCTAssertEqual(try system(runtime, program, "getPlayItemString").stringValue, "/Music/song.flac")
        host.trackPath = ""
        XCTAssertEqual(try system(runtime, program, "getPlayItemString").stringValue, "Some Artist - Some Song",
                       "an item with no location still answers non-empty, so `!= \"\"` still means playing")
    }

    /// A stream's location never carries the credentials its URL does, and a path with no extension
    /// of its own takes the format the server reported.
    func testAStreamLocationDropsCredentialsAndTakesTheReportedFormat() throws {
        func location(_ url: String, _ contentType: String?) throws -> String {
            WinampModernAudioEngineHost.playItemLocation(of: try XCTUnwrap(URL(string: url)), contentType: contentType)
        }
        XCTAssertEqual(try location("http://10.0.0.5:32400/library/parts/1/2/file.flac?X-Plex-Token=SECRET",
                                    "audio/flac"),
                       "http://10.0.0.5:32400/library/parts/1/2/file.flac")
        XCTAssertEqual(try location("https://music.example.com/rest/stream?id=42&u=me&t=abc&s=salt", "audio/mpeg"),
                       "https://music.example.com/rest/stream.mp3")
        XCTAssertEqual(try location("https://jf.example.com/Audio/a/universal?api_key=KEY", "flac"),
                       "https://jf.example.com/Audio/a/universal.flac")
        XCTAssertEqual(try location("https://emby.example.com/Audio/a/stream?api_key=KEY", "audio/x-flac"),
                       "https://emby.example.com/Audio/a/stream.flac")
        XCTAssertEqual(try location("https://music.example.com/rest/stream?id=7", "application/octet-stream"),
                       "https://music.example.com/rest/stream", "an opaque type names no format")
        XCTAssertEqual(try location("https://music.example.com/rest/stream?id=7", "octet-stream"),
                       "https://music.example.com/rest/stream", "nor does a bare opaque token")
        XCTAssertEqual(try location("https://user:pw@radio.example.com/live", nil), "https://radio.example.com/live")
        XCTAssertEqual(try location("file:///Music/a%20b.m4a", nil), "/Music/a b.m4a")
    }

    // MARK: - One window placed at another's position

    /// ONYX parks its visualization over the player's art box one attribute at a time:
    /// `vis.setXmlParam("x", player.getLeft() + 52)`. A layout reads 0, so the offset is relative to
    /// that window's desktop origin, and each axis of the read is spent by the write that uses it.
    func testAnOffsetFromALayoutReadIsRelativeToThatWindow() {
        var borrowed = WinampModernBorrowedOrigin()
        borrowed.record(.init(window: player, reported: .zero, desktop: CGPoint(x: 762, y: 293), onScreen: true))

        let x = borrowed.match(x: 52, y: nil, writtenOn: vis, current: CGPoint(x: 1548, y: 39))
        XCTAssertEqual(x?.request, .desktop(CGPoint(x: 814, y: 39)))
        XCTAssertEqual(x?.leader, player)
        XCTAssertEqual(borrowed.match(x: nil, y: 35, writtenOn: vis, current: CGPoint(x: 814, y: 39))?.request,
                       .desktop(CGPoint(x: 814, y: 328)))
        XCTAssertNil(borrowed.match(x: 52, y: nil, writtenOn: vis, current: .zero), "both axes are spent")
    }

    /// A container reads its desktop position, so only Wasabi's ±1 jiggle of it is the idiom; a
    /// different number is a position of its own.
    func testAContainerReadOnlyMatchesWithinAPixel() {
        var borrowed = WinampModernBorrowedOrigin()
        let read = WinampModernBorrowedOrigin.Read(window: player, reported: CGPoint(x: 762, y: 293),
                                                   desktop: CGPoint(x: 762, y: 293), onScreen: true)
        borrowed.record(read)
        XCTAssertNil(borrowed.match(x: 814, y: 328, writtenOn: vis, current: .zero))
        XCTAssertEqual(borrowed.match(x: 763, y: 292, writtenOn: vis, current: .zero)?.request,
                       .desktop(CGPoint(x: 763, y: 292)))
    }

    /// The window read is never the window written (that round trip is B61's no-op), a read the event
    /// has finished with lends nothing, and a window off screen has no position to lend (B156).
    func testABorrowedPositionNeedsAnotherWindowAFreshReadAndAnOnScreenOne() {
        var borrowed = WinampModernBorrowedOrigin()
        borrowed.record(.init(window: player, reported: .zero, desktop: CGPoint(x: 762, y: 293), onScreen: true))
        XCTAssertNil(borrowed.match(x: 0, y: 0, writtenOn: player, current: .zero))
        borrowed.forget()
        XCTAssertNil(borrowed.match(x: 52, y: 35, writtenOn: vis, current: .zero))

        borrowed.record(.init(window: player, reported: .zero, desktop: CGPoint(x: 0, y: 1032), onScreen: false))
        XCTAssertEqual(borrowed.match(x: 52, y: 35, writtenOn: vis, current: .zero)?.request, .offScreen)
    }

    // MARK: - A layout sized to nothing stays off screen

    /// ONYX gives its visualization window no size in the mini player: `setXmlParam` of `w`/`h` 0,
    /// then `show()`. Winamp draws that window 0×0; showing it must not bring back its declared size,
    /// and a real size brings it back.
    func testALayoutSizedToNothingIsNotShownUntilItHasASize() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="100" h="100"/></container>
          <container id="viscontainer"><layout id="shade" w="67" h="72"/></container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { runtime.teardown() }
        var shown: [Bool] = []
        runtime.containerVisibilityRequested = { id, visible in
            if id == "viscontainer" { shown.append(visible) }
        }
        let layout = try XCTUnwrap(object(runtime, type: "layout", id: "shade"))
        func call(_ method: String, _ arguments: [MakiValue] = []) throws {
            _ = try runtime.invoke(method: method, on: MakiObjectReference(.gui(layout.stableID)),
                                   arguments: arguments, program: Self.syntheticProgram)
        }

        try call("setXmlParam", [.string("w"), .string("0")])
        try call("setXmlParam", [.string("h"), .string("0")])
        try call("show")
        XCTAssertEqual(shown.last, false)

        try call("resize", [.integer(0), .integer(0), .integer(252), .integer(194)])
        try call("hide")
        try call("show")
        XCTAssertEqual(shown.last, true, "any real size, from any writer, brings the window back")
    }

    // MARK: - Helpers

    private let player = WasabiObjectID(rawValue: 1)
    private let vis = WasabiObjectID(rawValue: 2)

    private static let syntheticProgram = MakiProgram(
        version: 0x0403, classes: [], methods: [], variables: [], bindings: [], instructions: [],
        source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"), ownerID: nil, parameter: nil)

    private func system(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                        _ method: String, _ arguments: [MakiValue] = []) throws -> MakiValue {
        try runtime.invoke(method: method, on: MakiObjectReference(.system), arguments: arguments, program: program)
    }

    private func makeRuntime(host: WinampModernHost = WinampModernStubHost()) throws
        -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="16" h="16"/></container></WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        return (runtime, Self.syntheticProgram)
    }

    private func object(_ runtime: WinampModernScriptRuntime, type: String, id: String) -> WasabiObject? {
        func walk(_ objects: [WasabiObject]) -> WasabiObject? {
            for object in objects {
                if object.typeName.caseInsensitiveCompare(type) == .orderedSame,
                   object.xmlID?.caseInsensitiveCompare(id) == .orderedSame { return object }
                if let match = walk(object.children) { return match }
            }
            return nil
        }
        return walk(runtime.loadedSkin.runtime.graph.roots)
    }

    /// A `.maki` with the System object and one integer variable per `(low, high)` pair, no code.
    private func makeScript(integerConstants: [(UInt16, UInt16)]) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString("getid", to: &data)
        appendUInt32(UInt32(1 + integerConstants.count), to: &data) // variables
        appendVariable(type: 0, object: true, low: 0, high: 0, system: true, to: &data)
        for (low, high) in integerConstants {
            appendVariable(type: MakiValueKind.integer.rawValue, object: false, low: low, high: high,
                           system: false, to: &data)
        }
        appendUInt32(0, to: &data)                                  // constants
        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(0, to: &data)                                  // code
        return data
    }

    private func appendVariable(type: UInt8, object: Bool, low: UInt16, high: UInt16, system: Bool,
                                to data: inout Data) {
        data.append(type)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)                                  // subclass
        appendUInt16(low, to: &data)
        appendUInt16(high, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)                                              // global
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
        let bytes = Array(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    private final class LocationHost: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var trackPath = ""
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
