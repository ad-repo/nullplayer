import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B82 — a subtree brought up mid-session is told what is already playing.
///
/// ClassicPro's Now Playing widget fills its three `SC:FadeText` lines only from
/// `System.onTitleChange`, and the NOW tab builds a fresh instance through
/// `CustomObject.setXmlParam("groupid", …)` on every click. The first instance, made at load, hears
/// the window's opening title; every later one heard nothing, so the lines stayed empty until the
/// next track. The fixture is that shape in miniature: a `<customobject>` whose widget carries a
/// script that records `onTitleChange`'s argument and whether `onPlay` ran.
final class WinampModernB82Tests: XCTestCase {

    func testAWidgetBroughtUpMidTrackHearsTheTitleAndThePlay() throws {
        let host = Host()
        host.trackTitle = "Artist - Song"
        host.playbackState = .playing
        let runtime = try makeStartedRuntime(host: host)
        let widget = try bringUpWidget(in: runtime)
        XCTAssertEqual(widget.variables[Self.titleSlot].value.stringValue, "Artist - Song")
        XCTAssertEqual(widget.variables[Self.playSlot].value.stringValue, "played")
    }

    /// Winamp reports the transition, and a paused or stopped track has not just started playing.
    func testAStoppedTrackIsNamedButNotAnnouncedAsPlaying() throws {
        let host = Host()
        host.trackTitle = "Artist - Song"
        let runtime = try makeStartedRuntime(host: host)
        let widget = try bringUpWidget(in: runtime)
        XCTAssertEqual(widget.variables[Self.titleSlot].value.stringValue, "Artist - Song")
        XCTAssertEqual(widget.variables[Self.playSlot].value.stringValue, "")
    }

    func testNothingLoadedSendsNoTitle() throws {
        let runtime = try makeStartedRuntime(host: Host())
        let widget = try bringUpWidget(in: runtime)
        XCTAssertEqual(widget.variables[Self.titleSlot].value.stringValue, "")
    }

    /// The seed goes to the new programs only. A skin-wide replay reaches every running script, and
    /// ClassicPro's `beat.m` resets its VU maximum on each `onTitleChange` it hears.
    func testScriptsAlreadyRunningDoNotHearTheSeed() throws {
        let host = Host()
        host.trackTitle = "Artist - Song"
        host.playbackState = .playing
        let runtime = try makeStartedRuntime(host: host)
        let skinLevel = try XCTUnwrap(runtime.programs.first)
        _ = try bringUpWidget(in: runtime)
        XCTAssertEqual(skinLevel.variables[Self.titleSlot].value.stringValue, "")
        XCTAssertEqual(skinLevel.variables[Self.playSlot].value.stringValue, "")
    }

    // MARK: - Fixture

    private static let titleSlot = 1
    private static let playSlot = 3

    private static let skinXML = """
    <WasabiXML>
      <groupdef id="np.widget">
        <layer id="np.line" x="0" y="0" w="10" h="10"/>
        <script id="np.script" file="scripts/np.maki"/>
      </groupdef>
      <container id="main">
        <layout id="normal" w="120" h="60">
          <customobject id="widget.holder" x="0" y="0" w="120" h="60"/>
        </layout>
      </container>
      <scripts>
        <script id="running" file="scripts/np.maki"/>
      </scripts>
    </WasabiXML>
    """

    private func makeStartedRuntime(host: Host) throws -> WinampModernScriptRuntime {
        let loaded = try makeSkin()
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        try runtime.start()
        return runtime
    }

    /// What CentroSUI's NOW tab does: name the widget on the holder.
    private func bringUpWidget(in runtime: WinampModernScriptRuntime) throws -> MakiProgram {
        let holder = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "widget.holder").first)
        let before = runtime.programs.count
        _ = try runtime.invoke(method: "setxmlparam", on: MakiObjectReference(.gui(holder.stableID)),
                               arguments: [.string("groupid"), .string("np.widget")],
                               program: Self.emptyProgram())
        XCTAssertEqual(runtime.programs.count, before + 1, "the widget's own script started")
        return try XCTUnwrap(runtime.programs.last)
    }

    private static func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                    ownerID: nil, parameter: nil)
    }

    /// ```
    /// System.onTitleChange(String t) { title = t; }
    /// System.onPlay() { played = "played"; }
    /// ```
    /// Variables: 0 System, 1 `title`, 2 the literal, 3 `played`, 4 the return value.
    private static func makeScript() -> Data {
        var code = Data()
        appendInstruction(3, variable: 1, to: &code)        // title = <argument>
        appendInstruction(1, variable: 4, to: &code)
        appendInstruction(33, to: &code)                    // ret
        let onPlay = code.count
        appendInstruction(1, variable: 2, to: &code)        // push "played"
        appendInstruction(3, variable: 3, to: &code)        // played = …
        appendInstruction(1, variable: 4, to: &code)
        appendInstruction(33, to: &code)                    // ret

        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)                          // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(2, to: &data)                          // methods
        for name in ["onTitleChange", "onPlay"] {
            appendUInt16(0, to: &data)                      // class index
            appendUInt16(0, to: &data)                      // return type
            appendString(name, to: &data)
        }
        appendUInt32(5, to: &data)                          // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, to: &data)
        appendUInt32(1, to: &data)                          // constants
        appendUInt32(2, to: &data)
        appendString("played", to: &data)
        appendUInt32(2, to: &data)                          // bindings
        for (method, offset) in [(0, 0), (1, onPlay)] {
            appendUInt32(0, to: &data)                      // variable: the System object
            appendUInt32(UInt32(method), to: &data)
            appendUInt32(UInt32(offset), to: &data)
        }
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private static func appendInstruction(_ opcode: UInt8, variable: Int? = nil, to data: inout Data) {
        data.append(opcode)
        if let variable { appendUInt32(UInt32(variable), to: &data) }
    }

    private static func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                       to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)          // subclass
        appendUInt16(0, to: &data)          // initial
        appendUInt16(0, to: &data)          // initial2
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)                      // global
        data.append(system ? 1 : 0)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private static func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(bytes)
    }

    private func makeSkin() throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB82Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B82-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(Self.skinXML.utf8)),
                                ("scripts/np.maki", Self.makeScript())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return try WinampModernSkinLoader(engineStore: nil).load(from: url)
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
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
