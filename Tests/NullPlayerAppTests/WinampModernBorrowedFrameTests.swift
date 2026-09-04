import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// A skin whose standard frames draw chrome but never build a client area (Itemskin and its four
/// siblings). Synthesis borrows the layout of one of the skin's *own* windows instead — see
/// `WasabiSurfaceSynthesizer.FrameExemplar`.
final class WinampModernBorrowedFrameTests: XCTestCase {

    /// A frame that declares a `<script>` is not a frame that instantiates `content=`. Itemskin's
    /// `wasabi.standardframe.static` runs a script that draws its chrome and calls neither `getParam`
    /// nor `newGroup`; taken at face value it produced a window with no client area at all, which
    /// fails at materialization and drops every NullPlayer-owned window into NullPlayer's own chrome.
    func testAFrameWhoseScriptNeverCallsNewGroupIsNotUsedForItsContent() throws {
        let loaded = try makeSkin(xml: Self.borrowedFrameSkin)
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("expected a skin-frame route")
        }
        XCTAssertNotEqual(frame.groupIdentifier, "wasabi.standardframe.statusbar",
                          "the canonical frame's script draws only; it cannot host content")
        XCTAssertNotNil(frame.exemplar,
                        "a frame that does not build its own client area is used by copying a window")
    }

    /// Of the frames the skin lays out itself, the **thinnest border** wins. The heavy one here is
    /// the library's (33/55, as Itemskin's is); the thin one is the visualizer's (26/40).
    func testTheThinnestBorderedExemplarIsChosen() throws {
        let loaded = try makeSkin(xml: Self.borrowedFrameSkin)
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava],
              let exemplar = frame.exemplar else {
            return XCTFail("expected a borrowed-frame route")
        }
        XCTAssertEqual(frame.xuiTag, "Wasabi:StandardFrame:AVS")
        XCTAssertEqual(exemplar.frame["x"], "-16")
        // The client rect is the skin's own, grown by the bleed that tucks it under the border.
        XCTAssertEqual(exemplar.content["x"], "27")
        XCTAssertEqual(exemplar.content["w"], "-53")
    }

    /// The window carries the border on top of the contents: every size in the hosted-window registry
    /// is the size of the *client*, so a 33x55 border eating into it left the chrome around a sliver.
    func testAHostedWindowGrowsByTheBorderItWears() throws {
        let loaded = try makeSkin(xml: Self.borrowedFrameSkin)
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava],
              let definition = WinampModernHostedWindowRegistry.entry(id: .cava) else {
            return XCTFail("expected a borrowed-frame route")
        }
        let request = WinampModernHostedWindowInstantiation(definition: definition, frame: frame)
        // The exemplar's client is `w="-53" h="-66"`, so the border costs 53x66.
        XCTAssertEqual(request.defaultSize.width, definition.defaultSize.width + 53)
        XCTAssertEqual(request.defaultSize.height, definition.defaultSize.height + 66)
        XCTAssertEqual(request.minimumSize.width, definition.minimumSize.width + 53)
    }

    /// A frame that builds its own client area is the Wasabi contract and is taken unchanged — no
    /// exemplar, no borrowed layout, the same shape every working skin already had.
    func testAContentBuildingFrameIsStillUsedDirectly() throws {
        let loaded = try makeSkin(xml: Self.contentBuildingSkin, frameScriptBuildsContent: true)
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("expected a skin-frame route")
        }
        XCTAssertEqual(frame.groupIdentifier, "wasabi.standardframe.statusbar")
        XCTAssertNil(frame.exemplar)
    }

    /// The one window the skin declares that we re-frame: its media library, whose contents are
    /// entirely NullPlayer's and whose rows a frame drawn for a picture costs outright.
    func testTheSkinsOwnLibraryWindowIsReFramedInTheThinnerFrame() throws {
        let loaded = try makeSkin(xml: Self.borrowedFrameSkin)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "MLibrary")
        addTeardownBlock { renderer.teardown() }
        let frames = renderer.sceneNodes().filter {
            $0.object.typeName.lowercased().hasPrefix("wasabi:standardframe")
        }
        XCTAssertEqual(frames.first?.object.typeName, "Wasabi:StandardFrame:AVS",
                       "the library keeps a frame, and it is the thin one")
    }

    /// …and only ever *downward*. A skin whose library already wears its thinnest frame is untouched.
    func testALibraryAlreadyWearingTheThinFrameIsLeftAlone() throws {
        let loaded = try makeSkin(xml: Self.thinLibrarySkin)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "MLibrary")
        addTeardownBlock { renderer.teardown() }
        let component = renderer.sceneNodes().first {
            $0.object.typeName.caseInsensitiveCompare("component") == .orderedSame
        }
        XCTAssertEqual(component?.object.attributes["x"], "27",
                       "the declared rect stays exactly as the author wrote it")
    }

    // MARK: - Fixtures

    /// Two frames, neither building its own content: a heavy one the skin puts on its library and a
    /// thin one it puts on its visualizer. The shape of Itemskin, K-jr, MoonLight and Pure Inspired.
    private static let borrowedFrameSkin = """
    <WasabiXML>
      <bitmap id="frame.art" file="art.png" x="0" y="0" w="8" h="8"/>
      <groupdef id="wasabi.standardframe.statusbar" xuitag="Wasabi:StandardFrame:Status">
        <layer id="art" x="0" y="0" image="frame.art"/>
        <script file="scripts/standardframe.maki"/>
      </groupdef>
      <groupdef id="wasabi.standardframe.ml" xuitag="Wasabi:StandardFrame:ML">
        <layer id="art" x="0" y="0" image="frame.art"/>
        <script file="scripts/standardframe.maki"/>
      </groupdef>
      <groupdef id="wasabi.standardframe.avs" xuitag="Wasabi:StandardFrame:AVS">
        <layer id="art" x="0" y="0" image="frame.art"/>
        <script file="scripts/standardframe.maki"/>
      </groupdef>
      <container id="main">
        <layout id="normal" default_w="300" default_h="160"/>
      </container>
      <container id="MLibrary" component="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}">
        <layout id="normal" default_w="660" default_h="274" minimum_w="330" minimum_h="137">
          <Wasabi:StandardFrame:ML x="-8" y="7" w="15" h="3" relatw="1" relath="1"/>
          <component x="33" y="55" w="-66" h="-92" relatw="1" relath="1"
                     param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"/>
        </layout>
      </container>
      <container id="AVS_window" component="guid:{0000000A-000C-0010-FF7B-01014263450C}">
        <layout id="normal" default_w="330" default_h="137" minimum_w="330" minimum_h="137">
          <Wasabi:StandardFrame:AVS x="-16" y="-8" w="32" h="66" relatw="1" relath="1"/>
          <component x="27" y="40" w="-53" h="-66" relatw="1" relath="1"
                     param="guid:{0000000A-000C-0010-FF7B-01014263450C}"/>
        </layout>
      </container>
    </WasabiXML>
    """

    /// The library window already wears the thinnest frame the skin has.
    private static let thinLibrarySkin = """
    <WasabiXML>
      <bitmap id="frame.art" file="art.png" x="0" y="0" w="8" h="8"/>
      <groupdef id="wasabi.standardframe.avs" xuitag="Wasabi:StandardFrame:AVS">
        <layer id="art" x="0" y="0" image="frame.art"/>
        <script file="scripts/standardframe.maki"/>
      </groupdef>
      <container id="main">
        <layout id="normal" default_w="300" default_h="160"/>
      </container>
      <container id="MLibrary" component="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}">
        <layout id="normal" default_w="660" default_h="274">
          <Wasabi:StandardFrame:AVS x="-16" y="-8" w="32" h="66" relatw="1" relath="1"/>
          <component x="27" y="40" w="-53" h="-66" relatw="1" relath="1"
                     param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"/>
        </layout>
      </container>
    </WasabiXML>
    """

    private static let contentBuildingSkin = """
    <WasabiXML>
      <bitmap id="frame.art" file="art.png" x="0" y="0" w="8" h="8"/>
      <groupdef id="wasabi.standardframe.statusbar" xuitag="Wasabi:StandardFrame:Status">
        <layer id="art" x="0" y="0" image="frame.art"/>
        <script file="scripts/standardframe.maki"/>
      </groupdef>
      <container id="main">
        <layout id="normal" default_w="300" default_h="160"/>
      </container>
    </WasabiXML>
    """

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

    private func makeSkin(xml: String, frameScriptBuildsContent: Bool = false) throws
        -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BorrowedFrame-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("BorrowedFrame-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ payload: Data) throws {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        try add("skin.xml", Data(xml.utf8))
        try add("art.png", Self.pixel())
        try add("scripts/standardframe.maki",
                Self.makiScript(callingNewGroup: frameScriptBuildsContent))
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    /// A MAKI program that declares only a method table. Whether `newGroup` is in it is the whole
    /// question synthesis asks of a frame — a script that never calls it cannot build a client area,
    /// however much chrome it draws.
    private static func makiScript(callingNewGroup: Bool) -> Data {
        var data = Data([0x46, 0x47])
        func u16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        u16(0x0403); u32(23); u32(1)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        let methods = callingNewGroup ? ["getid", "newGroup"] : ["getid", "setXmlParam"]
        u32(UInt32(methods.count))
        for method in methods {
            u16(0); u16(0)
            let name = Array(method.utf8)
            u16(UInt16(name.count)); data.append(contentsOf: name)
        }
        u32(0); u32(0); u32(0); u32(0)
        return data
    }

    private static func pixel() -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.gray.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }
}
