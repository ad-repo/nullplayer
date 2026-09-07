import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B95 — a Winamp3-era skin expects the player to supply the standard window frame and the
/// `wasabi.button.*` chrome that sits in it.
///
/// The task named the chrome bitmaps, but the fatal half was the **frame**: a
/// `<Wasabi:StandardFrame:*>` names its body by group id (`content="player.content.group"`) and in
/// real Winamp the frame's own `standardframe.maki` instantiates it. A skin that expects Winamp's
/// frame ships neither that groupdef nor that script, so the tag resolved to nothing and the group
/// holding every piece of the skin's own artwork never entered the graph at all. `Winamp 3.0
/// Default` — Nullsoft's own *Winamp3 Base Skin* — is every full-size layout of one such frame, and
/// it measured 9 nodes and `resolved=0`: a blank white 275x116, the only skin in the corpus that
/// loaded and drew nothing. Its windowshade layouts are plain groups and always drew fine, which is
/// what isolated the cause to the frame rather than to the skin.
///
/// The containment is what these cases pin. A skin that declares its own frame keeps it untouched,
/// and a skin that reaches the shell as a plain `inherit_group` base keeps the empty base it asked
/// for — EPS's notifier does exactly that, and putting the title strip in the shell's *body* rather
/// than on the frame *instance* pushed a stray object into it.
final class WinampModernB95Tests: XCTestCase {

    // MARK: - The frame's client area

    /// The Winamp 3.0 Default shape: a frame tag the skin never defines, naming a content group it
    /// does define. Before this the group was absent from the graph, not merely undrawn.
    func testAStandardFrameTheSkinNeverDefinedInstantiatesItsContentGroup() throws {
        let runtime = try makeRuntime(markup: """
        <groupdef id="player.content" name="Winamp">
          <layer id="art" x="0" y="0" w="8" h="8" image="art/bar.png"/>
        </groupdef>
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <Wasabi:StandardFrame:NoStatus x="0" y="0" w="0" h="0" relatw="1" relath="1"
                                           content="player.content"/>
          </layout>
        </container>
        """)
        XCTAssertFalse(runtime.graph.objects(xmlID: "player.content").isEmpty,
                       "the frame's content group is in the graph")
        XCTAssertFalse(runtime.graph.objects(xmlID: "art").isEmpty,
                       "and so is the artwork inside it")
    }

    /// The client area sits below the title strip and clear of the border, so the skin's own
    /// coordinates land where its screenshot puts them.
    func testTheClientAreaIsInsetForTheTitleStrip() throws {
        let runtime = try makeRuntime(markup: """
        <groupdef id="player.content" name="Winamp"/>
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <Wasabi:StandardFrame:NoStatus x="0" y="0" w="0" h="0" relatw="1" relath="1"
                                           content="player.content"/>
          </layout>
        </container>
        """)
        let content = try XCTUnwrap(runtime.graph.objects(xmlID: "player.content").first)
        XCTAssertEqual(content.attributes["x"], String(Int(WasabiStandardFrames.contentInset.x)))
        XCTAssertEqual(content.attributes["y"], String(Int(WasabiStandardFrames.contentInset.y)))
        XCTAssertEqual(content.attributes["relatw"], "1")
        XCTAssertEqual(content.attributes["relath"], "1")
    }

    /// `<sendparams target="window.titlebar.title" default="WINAMP"/>` is how such a skin names its
    /// own player. With no object of that id the send lands nowhere, so the frame supplies one.
    func testTheFrameSuppliesTheTitleObjectSkinsAddressByName() throws {
        let runtime = try makeRuntime(markup: """
        <groupdef id="player.content" name="Winamp"/>
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <Wasabi:StandardFrame:NoStatus x="0" y="0" w="0" h="0" relatw="1" relath="1"
                                           content="player.content"/>
            <sendparams target="window.titlebar.title" default="WINAMP"/>
          </layout>
        </container>
        """)
        let title = try XCTUnwrap(runtime.graph.objects(xmlID: "window.titlebar.title").first)
        XCTAssertEqual(title.attributes["default"], "WINAMP", "the skin's sendparams reached it")
        XCTAssertEqual(title.attributes["h"],
                       String(Int(WasabiStandardFrames.titleHeight)),
                       "and it is confined to the title strip, not centred over the client area")
    }

    /// A frame naming no content is left alone — nothing to instantiate, and no invented body.
    func testAFrameThatNamesNoContentInstantiatesNothing() throws {
        let runtime = try makeRuntime(markup: """
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <Wasabi:StandardFrame:NoStatus id="bare" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
          </layout>
        </container>
        """)
        let frame = try XCTUnwrap(runtime.graph.objects(xmlID: "bare").first)
        XCTAssertEqual(frame.children.count, 0)
    }

    // MARK: - Containment

    /// A skin that ships the frame *and the script that fills it* instantiates its own content, so
    /// ours must not instantiate it a second time. mmd3, CornerAmp and Winamp Modern all do.
    ///
    /// The script is what this turns on, not the groupdef: B143 found three skins that declare the
    /// groupdef and leave the script to Winamp, and they are covered below.
    func testASkinThatDeclaresItsOwnFrameIsNotGivenASecondClientArea() throws {
        let runtime = try makeRuntime(art: ["scripts/standardframe.maki": Self.frameScript()], markup: """
        <groupdef id="player.content" name="Winamp"/>
        <groupdef id="wasabi.standardframe.nostatusbar" xuitag="Wasabi:StandardFrame:NoStatus">
          <layer id="own.chrome" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
          <script id="standardframe.script" file="scripts/standardframe.maki"
                  param="5,15,-10,-34,0,0,1,1"/>
        </groupdef>
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <Wasabi:StandardFrame:NoStatus x="0" y="0" w="0" h="0" relatw="1" relath="1"
                                           content="player.content"/>
          </layout>
        </container>
        """)
        XCTAssertFalse(runtime.graph.objects(xmlID: "own.chrome").isEmpty,
                       "the skin's own frame body expanded")
        XCTAssertTrue(runtime.graph.objects(xmlID: "player.content").isEmpty,
                      "and its own script — not ours — is what instantiates the content")
        XCTAssertTrue(runtime.graph.objects(xmlID: "window.titlebar.title").isEmpty,
                      "nor did we add a title strip over the skin's own chrome")
    }

    // MARK: - B143 — the skin drew the frame and left the script to Winamp

    /// TRON Legacy's shape: the skin redefines `wasabi.standardframe.statusbar` with
    /// `inherit_content="scripts"` — "this is my artwork, keep the scripts of the definition I am
    /// replacing" — and the definition it replaces is Winamp's own, which we do not ship. So the
    /// frame is claimed (no hosted chrome) and scriptless (no `newGroup`), and the content group
    /// holding the whole playlist never entered the graph: the user saw the skin's chrome around a
    /// white void.
    func testAClaimedFrameWithNoScriptStillInstantiatesItsContent() throws {
        let runtime = try makeRuntime(markup: """
        <groupdef id="player.content" name="Winamp">
          <layer id="art" x="0" y="0" w="8" h="8"/>
        </groupdef>
        <groupdef id="wasabi.standardframe.statusbar" inherit_content="scripts">
          <layer id="own.chrome" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
        </groupdef>
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <Wasabi:StandardFrame:Status x="0" y="0" w="0" h="0" relatw="1" relath="1"
                                         content="player.content"/>
          </layout>
        </container>
        """)
        XCTAssertFalse(runtime.graph.objects(xmlID: "own.chrome").isEmpty,
                       "the skin's own frame body expanded")
        XCTAssertFalse(runtime.graph.objects(xmlID: "player.content").isEmpty,
                       "and nothing else was going to instantiate its content")
        XCTAssertFalse(runtime.graph.objects(xmlID: "art").isEmpty,
                       "so the artwork inside it is in the graph too")
    }

    /// The client rect is **measured** from the frame's own `resize=` strips, so it is the hole the
    /// skin's artwork actually leaves rather than the inset we invent for a frame of our own. TRON's
    /// strips are 5px sides, a 15px top and a 19px bottom band; corners are deliberately not counted,
    /// because a corner sprite is as wide as the rounding (24px there) and not as thick as the border.
    func testTheClaimedFrameClientIsMeasuredFromItsResizeStrips() throws {
        let runtime = try makeRuntime(markup: """
        <elements>
          <bitmap id="edge.top" file="art.png" x="0" y="0" w="8" h="15"/>
          <bitmap id="edge.corner" file="art.png" x="0" y="0" w="24" h="19"/>
        </elements>
        <groupdef id="player.content" name="Winamp"/>
        <groupdef id="wasabi.standardframe.statusbar" inherit_content="scripts">
          <layer id="c.bottom" x="24" y="-19" h="19" relatw="1" relaty="1" resize="bottom"/>
          <layer id="c.bottom.left" x="0" y="-23" h="23" relaty="1" resize="bottomleft"/>
          <group id="wasabi.frame.layout" x="0" y="0" w="0" relatw="1" h="-23" relath="1"/>
        </groupdef>
        <groupdef id="wasabi.frame.layout">
          <layer id="c.left" x="0" y="19" w="5" relath="1" resize="left"/>
          <layer id="c.right" x="-5" y="19" w="5" relatx="1" relath="1" resize="right"/>
          <layer id="c.top" x="24" y="0" relatw="1" image="edge.top" resize="top"/>
          <layer id="c.top.left" x="0" y="0" image="edge.corner" resize="topleft"/>
        </groupdef>
        <container id="Main">
          <layout id="normal" w="275" h="116">
            <Wasabi:StandardFrame:Status x="0" y="0" w="0" h="0" relatw="1" relath="1"
                                         content="player.content"/>
          </layout>
        </container>
        """)
        let content = try XCTUnwrap(runtime.graph.objects(xmlID: "player.content").first)
        XCTAssertEqual(content.attributes["x"], "5", "the left strip, not the 24px corner")
        XCTAssertEqual(content.attributes["y"], "15", "the top strip, whose height comes from its bitmap")
        XCTAssertEqual(content.attributes["w"], "-10")
        XCTAssertEqual(content.attributes["h"], "-34", "15 top plus the 19px status band")
        XCTAssertEqual(content.attributes["relatw"], "1")
        XCTAssertEqual(content.attributes["relath"], "1")
    }

    /// The other spelling of the same parameter: a plain `<group id="wasabi.standardframe.statusbar"
    /// notify="content,…">` rather than the XUI tag. Sony Walkman writes its windows that way, and
    /// the script that reads `content` is the same script in both cases.
    func testTheNotifySpellingOfContentIsHonouredToo() throws {
        let runtime = try makeRuntime(markup: """
        <groupdef id="player.content" name="Winamp"/>
        <groupdef id="wasabi.standardframe.statusbar" inherit_content="scripts">
          <layer id="own.chrome" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
        </groupdef>
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <group id="wasabi.standardframe.statusbar" x="0" y="0" w="0" h="0"
                   relatw="1" relath="1" notify="content,player.content"/>
          </layout>
        </container>
        """)
        XCTAssertFalse(runtime.graph.objects(xmlID: "player.content").isEmpty)
    }

    /// A frame that names no content at all is still left alone — there is nothing to instantiate,
    /// and inventing a body would put an object into EPS's notifier base.
    func testAClaimedFrameNamingNoContentInstantiatesNothing() throws {
        let runtime = try makeRuntime(markup: """
        <groupdef id="wasabi.standardframe.statusbar" inherit_content="scripts">
          <layer id="own.chrome" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
        </groupdef>
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <Wasabi:StandardFrame:Status id="bare" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
          </layout>
        </container>
        """)
        let frame = try XCTUnwrap(runtime.graph.objects(xmlID: "bare").first)
        XCTAssertEqual(frame.children.count, 1, "its own chrome layer, and nothing else")
    }

    /// The shell is also reachable as an ordinary base. EPS's notifier writes
    /// `<group id="wasabi.standardframe.nostatusbar" …/>` and wants the empty base it asked for —
    /// putting the title strip in the shell's body rather than on the frame instance put a stray
    /// object into it, which is what `testEveryOtherShellStaysIdentifierOnly` caught.
    func testTheShellStaysEmptyWhenUsedAsAPlainGroupBase() throws {
        let runtime = try makeRuntime(markup: """
        <container id="Main">
          <layout id="normal" w="64" h="64">
            <group id="wasabi.standardframe.nostatusbar" x="0" y="0" w="10" h="10"/>
          </layout>
        </container>
        """)
        let base = try XCTUnwrap(
            runtime.graph.objects(xmlID: "wasabi.standardframe.nostatusbar").first)
        XCTAssertEqual(base.children.count, 0)
    }

    // MARK: - The chrome buttons

    /// A button whose `image=` names an undeclared `wasabi.button.*` id has no artwork to size to,
    /// so it resolved to 0x0 and never appeared. `Winamp 3.0 Default`'s titlebar is four of them.
    func testAChromeButtonWithNoArtworkTakesAMeasuredSize() throws {
        let scene = try makeScene(markup: """
        <button id="Close" action="CLOSE" x="0" y="0" image="wasabi.button.exit"/>
        """)
        let frame = try XCTUnwrap(scene.frame(ofXMLID: "Close"))
        XCTAssertEqual(frame.width, WasabiChromeButtons.Role.exit.defaultSize.width)
        XCTAssertEqual(frame.height, WasabiChromeButtons.Role.exit.defaultSize.height)
    }

    /// And it draws — the same deliberate exception to the identifier-only-shell rule as an
    /// artwork-less `<Wasabi:Button text="…">` and a `<Wasabi:TitleBox>`.
    func testAChromeButtonWithNoArtworkDrawsItsGlyph() throws {
        let scene = try makeScene(markup: """
        <button id="Close" action="CLOSE" x="0" y="0" image="wasabi.button.exit"/>
        """)
        let ink = scene.inkColours()
        XCTAssertFalse(ink.isEmpty, "the close glyph is on the canvas")
        XCTAssertFalse(ink.contains(Self.artworkInk),
                       "and it is a glyph we stroked, not artwork — this skin ships none")
    }

    /// A skin's stated size always wins: the default is what a button with no artwork *and* no
    /// geometry falls back to, not a size imposed on one that states its own.
    func testADeclaredSizeWinsOverTheDefault() throws {
        let scene = try makeScene(markup: """
        <button id="Close" action="CLOSE" x="0" y="0" w="30" h="20" image="wasabi.button.exit"/>
        """)
        let frame = try XCTUnwrap(scene.frame(ofXMLID: "Close"))
        XCTAssertEqual(frame.width, 30)
        XCTAssertEqual(frame.height, 20)
    }

    /// Contained by construction: a skin that ships the artwork resolves it and never reaches the
    /// fallback. Formamp and corneramp_redux each declare part of the set and keep every piece.
    func testASkinThatShipsTheArtworkDrawsItsOwn() throws {
        let scene = try makeScene(
            resources: #"<bitmap id="wasabi.button.exit" file="art/bar.png" x="0" y="0" w="8" h="8"/>"#,
            markup: #"<button id="Close" action="CLOSE" x="0" y="0" image="wasabi.button.exit"/>"#,
            art: ["art/bar.png": Self.solidPNG()])
        let frame = try XCTUnwrap(scene.frame(ofXMLID: "Close"))
        XCTAssertEqual(frame.width, 8, "sized to the artwork it ships, not to our default")
        XCTAssertEqual(scene.inkColours(), [Self.artworkInk],
                       "and drawn from the skin's own artwork, with no glyph over it")
    }

    /// An unresolved id under the prefix that is not a control we know is left alone. This draws a
    /// known button, not a box around every id that failed to resolve.
    func testAnUnknownWasabiButtonIdIsLeftAlone() throws {
        let scene = try makeScene(markup: """
        <button id="Odd" action="CLOSE" x="0" y="0" image="wasabi.button.notachromecontrol"/>
        """)
        XCTAssertNil(WasabiChromeButtons.role(forBitmapID: "wasabi.button.notachromecontrol"))
        XCTAssertTrue(scene.inkColours().isEmpty, "nothing was drawn for it")
    }

    /// The state suffix skins append is not part of the role: `Winamp 3.0 Default` writes the
    /// pressed id as the resting `image=` on one of each button's two alpha-gated copies.
    func testTheRoleIgnoresTheStateSuffix() {
        XCTAssertEqual(WasabiChromeButtons.role(forBitmapID: "wasabi.button.appmenu.pressed"),
                       .appmenu)
        XCTAssertEqual(WasabiChromeButtons.role(forBitmapID: "WASABI.BUTTON.WINSHADE"), .winshade)
        XCTAssertNil(WasabiChromeButtons.role(forBitmapID: "player.button.play"),
                     "a skin's own button is not chrome")
    }

    // MARK: - Fixture

    private struct Scene {
        let loadedSkin: WinampModernLoadedSkin
        let renderer: WasabiSceneRenderer

        func frame(ofXMLID xmlID: String) -> CGRect? {
            renderer.sceneNodes().first { $0.object.attributes["id"] == xmlID }?.frame
        }

        /// Every distinct opaque colour painted anywhere on the canvas.
        ///
        /// Deliberately coordinate-free: what these cases ask is *whether* an object drew and *what
        /// it drew with* — its own artwork or a glyph — and the harness's raw context is not flipped
        /// the way the app's view is, so a box in scene coordinates would be pinning a fixture
        /// artifact rather than the behaviour. The render dump is where placement is checked.
        func inkColours() -> Set<[Int]> {
            let width = Int(renderer.canvasSize.width)
            let height = Int(renderer.canvasSize.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = pixels.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context else { return [] }
            renderer.invalidateSceneCache()
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = saved
            var colours: Set<[Int]> = []
            for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] > 200 {
                colours.insert([Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2])])
            }
            return colours
        }
    }

    private func makeRuntime(art: [String: Data] = [:], markup: String) throws -> WasabiSkinRuntime {
        try makeScene(rawMarkup: markup, art: art).loadedSkin.runtime
    }

    /// A MAKI program that declares only a method table — enough for a `<script file=…>` to resolve
    /// and bind. What it contains does not matter here: this path asks whether the skin declares a
    /// frame script at all, not what that script does.
    private static func frameScript() -> Data {
        var data = Data([0x46, 0x47])
        func u16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        u16(0x0403); u32(23); u32(1)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        let methods = ["getid", "newGroup"]
        u32(UInt32(methods.count))
        for method in methods {
            u16(0); u16(0)
            let name = Array(method.utf8)
            u16(UInt16(name.count)); data.append(contentsOf: name)
        }
        u32(0); u32(0); u32(0); u32(0)
        return data
    }

    private func makeScene(resources: String = "",
                           markup: String = "",
                           rawMarkup: String? = nil,
                           art: [String: Data] = [:]) throws -> Scene {
        let body = rawMarkup ?? """
        <container id="Main">
          <layout id="normal" w="64" h="64">
        \(markup)
          </layout>
        </container>
        """
        var files: [String: Data] = art
        files["skin.xml"] = Data("""
        <WasabiXML>
          <elements>\(resources)</elements>
        \(body)
        </WasabiXML>
        """.utf8)

        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(files: files))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return Scene(loadedSkin: loaded, renderer: renderer)
    }

    private func makeArchive(files: [String: Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB95Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B95-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, payload) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    /// The skin's artwork colour. A glyph is stroked in `palette.listText` instead, so "this pixel
    /// came from the archive" and "this pixel came from us" are told apart by one value.
    private static let artworkInk = [200, 40, 60]

    /// 8×8, one opaque colour — enough to tell "drawn from the skin's artwork" from "drawn by us".
    private static func solidPNG() -> Data {
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB,
                                              bytesPerRow: 32, bitsPerPixel: 32)!
        for y in 0..<8 {
            for x in 0..<8 {
                var components = [200, 40, 60, 255]
                representation.setPixel(&components, atX: x, y: y)
            }
        }
        return representation.representation(using: .png, properties: [:])!
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 200
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
