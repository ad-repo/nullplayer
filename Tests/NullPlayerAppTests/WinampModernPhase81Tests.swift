import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 81 — the Wasabi standard **form widgets** (B66) and a `<Wasabi:TitleBox>` that declares no
/// height (B67).
///
/// **The widgets.** `<Wasabi:Text>`, `<Wasabi:CheckBox>`, `<Wasabi:EditBox>`, `<Wasabi:HSlider>` and
/// `<Wasabi:DropDownList>` are conventional XUI tags whose bodies live inside Winamp, so each
/// resolved to a structure-free shell and became an inert node — 156 declarations across 15 skins,
/// and what an empty settings page usually is. The measured insight is that Winamp's own definition
/// of each is a thin wrapper around **one primitive this engine already has**: the three skins that
/// ship a replacement for `Wasabi:Text` all write it as `<groupdef …><text/></groupdef>`. So the tag
/// becomes the primitive, and drawing, hit testing, `cfgattrib` binding and script dispatch follow.
///
/// **The title box.** Four of impulse's five state no `h` and no `relath`, so the box resolved to no
/// height and its body was laid out inside nothing. The height is measured from the body rather than
/// guessed at a constant.
final class WinampModernPhase81Tests: XCTestCase {

    // MARK: - B66: a standard tag becomes the primitive it wraps

    /// The substitution, one tag at a time. Each becomes the primitive the rest of the engine already
    /// knows how to draw and dispatch to — which is the whole reason this is a type map and not five
    /// new controls.
    func testEachStandardTagBecomesItsPrimitive() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="200" default_w="400" default_h="200">
          <Wasabi:Text id="label" x="0" y="0" w="100" text="Hold Time"/>
          <Wasabi:EditBox id="field" x="0" y="20" w="100" h="20"/>
          <Wasabi:HSlider id="bar" x="0" y="45" w="145" h="10" high="40"/>
          <Wasabi:CheckBox id="switch" x="0" y="60" text="Always on top"/>
          <Wasabi:DropDownList id="picker" x="0" y="80" w="200" h="20" items="One;Two"/>
        </layout>
        """, groups: "")
        let graph = renderer.loadedSkin.runtime.graph

        func type(of id: String) throws -> String {
            try XCTUnwrap(graph.objects(xmlID: id).first).typeName.lowercased()
        }
        XCTAssertEqual(try type(of: "label"), "text")
        XCTAssertEqual(try type(of: "field"), "edit")
        XCTAssertEqual(try type(of: "bar"), "slider")
        // A check box is a togglebutton because that is what a check box *is*: `toggleActivation`
        // gives it the flip and its script the `onToggle`/`onActivate` pair, and a bound one takes
        // the `cfgattrib` road every other switch in the skin already takes.
        XCTAssertEqual(try type(of: "switch"), "togglebutton")
        XCTAssertEqual(try type(of: "picker"), "button")
    }

    /// The containment, and the reason the substitution is safe at corpus scale: a skin that defines
    /// the tag itself resolves its own definition and never reaches the map. Big Bento Modern, Lobe
    /// and ZDL each ship `<groupdef xuitag="Wasabi:Text">`, and Styx and Shield_Amp wrap the
    /// drop-down in one of their own.
    func testASkinsOwnDefinitionOfTheTagWins() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="120" default_w="200" default_h="120">
          <Wasabi:Text id="label" x="0" y="0" w="100" h="12"/>
        </layout>
        """, groups: """
        <groupdef id="wasabi.text.group" xuitag="Wasabi:Text" embed_xui="wasabi.text" h="12">
          <text id="wasabi.text" x="0" y="0" w="0" h="0" relatw="1" relath="1" display="ERROR"/>
        </groupdef>
        """)
        let object = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "label").first)

        XCTAssertEqual(object.typeName.lowercased(), "wasabi:text",
                       "the skin's own groupdef claimed the tag, so nothing was substituted")
        XCTAssertNil(WasabiFormWidgets.kind(of: object))
        XCTAssertEqual(object.children.first?.xmlID, "wasabi.text",
                       "and the skin's own body came with it")
    }

    /// A slider takes the conventional standard-library artwork, because **19 of the 36 installed
    /// skins ship it** — this is the one widget that mostly does not reach a drawn fallback. Seeded
    /// only where the instance is silent: impulse names its own thumb and must keep it.
    func testTheSliderSeedsTheConventionalThumbWithoutOverridingADeclaredOne() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="100" default_w="400" default_h="100">
          <Wasabi:HSlider id="plain" x="0" y="0" w="145" h="10" high="40"/>
          <Wasabi:HSlider id="own" x="0" y="20" w="145" h="10" thumb="impulse.knob"/>
        </layout>
        """, groups: "")
        let graph = renderer.loadedSkin.runtime.graph
        let plain = try XCTUnwrap(graph.objects(xmlID: "plain").first)
        let own = try XCTUnwrap(graph.objects(xmlID: "own").first)

        XCTAssertEqual(plain.attributes["thumb"], WasabiFormWidgets.horizontalSliderThumb)
        XCTAssertEqual(plain.attributes["downthumb"], WasabiFormWidgets.horizontalSliderDownThumb)
        XCTAssertEqual(plain.attributes["high"], "40", "the instance's own range still stands")
        XCTAssertEqual(own.attributes["thumb"], "impulse.knob", "a declared thumb is never replaced")
    }

    /// A check box states neither width nor height, so it takes one row and sizes to its own label —
    /// which is what the groupdefs that replace the tag do (`h="14"`, `autowidthsource` on the label).
    /// Left at zero the box and its text both fell outside the object and the switch was unclickable.
    func testACheckBoxIsOneRowTallAndAsWideAsItsLabel() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="100" default_w="400" default_h="100">
          <Wasabi:CheckBox id="switch" x="5" y="0" text="Always on top (Ctrl+A)"/>
        </layout>
        """, groups: "")
        let box = try XCTUnwrap(frame(of: "switch", in: renderer))

        XCTAssertEqual(box.height, CGFloat(WasabiFormWidgets.checkBoxHeight))
        XCTAssertGreaterThan(box.width, WasabiFormWidgets.checkBoxGlyph
                             + WasabiFormWidgets.checkBoxLabelGap,
                             "the label is inside the object, not beyond its right edge")
    }

    /// The box has to be **opaque to hit testing** without owning a bitmap — the artwork is Winamp's,
    /// the same deliberate exception a `<Wasabi:Button text="…">` and a title box are. Without this a
    /// click passes straight through the switch.
    func testAFormWidgetIsUnderTheMouse() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="100" default_w="400" default_h="100">
          <Wasabi:CheckBox id="switch" x="0" y="0" text="Enable Tooltips"/>
        </layout>
        """, groups: "")

        let hit = renderer.object(at: CGPoint(x: 4, y: 6))
        XCTAssertEqual(hit?.xmlID, "switch")
    }

    // MARK: - B66: a check box that is really a radio

    /// 32 of the corpus's 67 check boxes name a `radioid`, so this is half the tag rather than an
    /// edge of it. Clicking one member turns the rest off — and clicking the member that is *already
    /// on* leaves it on, which is the difference between "choose Classic" and "choose nothing".
    func testARadioTurnsItsSetOffAndNeverTurnsItselfOff() throws {
        let runtime = try makeRuntime(layout: """
        <layout id="normal" w="400" h="100" default_w="400" default_h="100">
          <Wasabi:CheckBox id="classic" x="6" y="18" text="Classic" radioid="simode" radioval="1"/>
          <Wasabi:CheckBox id="modern" x="116" y="18" text="Vis" radioid="simode" radioval="0"/>
          <Wasabi:CheckBox id="cover" x="6" y="57" text="On" radioid="ac-on" radioval="1"/>
        </layout>
        """)
        let graph = runtime.loadedSkin.runtime.graph
        let classic = try XCTUnwrap(graph.objects(xmlID: "classic").first)
        let modern = try XCTUnwrap(graph.objects(xmlID: "modern").first)
        let cover = try XCTUnwrap(graph.objects(xmlID: "cover").first)
        _ = cover.setAttribute("activated", value: "1")

        XCTAssertTrue(runtime.selectRadioMember(classic))
        XCTAssertEqual(classic.attributes["activated"], "1")
        // A member that was already off is left alone rather than written to "0": a radio's
        // `onToggle` is what its script reads the choice from, and telling four members they are
        // still off is four events the skin never had to handle.
        XCTAssertNotEqual(modern.attributes["activated"], "1")
        XCTAssertEqual(cover.attributes["activated"], "1",
                       "a different radioid is a different set and must not be disturbed")

        XCTAssertTrue(runtime.selectRadioMember(classic), "clicking the live member is still handled")
        XCTAssertEqual(classic.attributes["activated"], "1", "a radio does not toggle itself off")

        XCTAssertTrue(runtime.selectRadioMember(modern))
        XCTAssertEqual(modern.attributes["activated"], "1")
        XCTAssertEqual(classic.attributes["activated"], "0", "the member that was on is turned off")
        XCTAssertEqual(cover.attributes["activated"], "1")
    }

    /// A check box with no `radioid` is an ordinary toggle and must keep going down the toggle road.
    func testAPlainCheckBoxIsNotARadio() throws {
        let runtime = try makeRuntime(layout: """
        <layout id="normal" w="400" h="100" default_w="400" default_h="100">
          <Wasabi:CheckBox id="switch" x="0" y="0" text="Always on top"/>
        </layout>
        """)
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "switch").first)

        XCTAssertFalse(runtime.selectRadioMember(object))
        XCTAssertTrue(runtime.toggleActivation(of: object))
        XCTAssertEqual(object.attributes["activated"], "1")
    }

    // MARK: - B66: the drop-down

    /// The handle a skin's script reaches for. Styx's and Shield_Amp's `customdropdownlist.maki` are
    /// the same script — `findObject("dropdownlist.text")`, then `onTextChanged` persists the pick —
    /// so with no object carrying that id the selection survives nothing. It is invisible because the
    /// drop-down draws its own label; a second text object would print the selection twice.
    func testTheDropDownCarriesTheLabelHandleItsScriptLooksFor() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="100" default_w="400" default_h="100">
          <Wasabi:DropDownList id="picker" x="0" y="0" w="200" h="20"/>
        </layout>
        """, groups: "")
        let picker = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "picker").first)
        let label = try XCTUnwrap(WasabiFormWidgets.dropDownLabel(of: picker))

        XCTAssertEqual(label.xmlID, WasabiFormWidgets.dropDownLabelID)
        XCTAssertEqual(label.attributes["visible"], "0")
        XCTAssertNil(frame(of: WasabiFormWidgets.dropDownLabelID, in: renderer),
                     "the handle is never drawn")
    }

    /// What a drop-down shows, in the order Winamp resolves it: `default` is what its own object
    /// reads and what a script writes back from a restored private string; `defaultlistitem` is what
    /// a skin naming the tag directly declares; the first item is the floor.
    func testTheDropDownShowsTheRestoredPickBeforeTheDeclaredDefault() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="100" default_w="400" default_h="100">
          <Wasabi:DropDownList id="declared" x="0" y="0" w="200" h="20"
                               items="1. Bottom Right;2. Bottom Left"
                               defaultlistitem="1. Bottom Right"/>
          <Wasabi:DropDownList id="bare" x="0" y="30" w="200" h="20" items="One;Two"/>
        </layout>
        """, groups: "")
        let graph = renderer.loadedSkin.runtime.graph
        let declared = try XCTUnwrap(graph.objects(xmlID: "declared").first)
        let bare = try XCTUnwrap(graph.objects(xmlID: "bare").first)

        XCTAssertEqual(WasabiFormWidgets.items(of: declared), ["1. Bottom Right", "2. Bottom Left"])
        XCTAssertEqual(WasabiFormWidgets.selection(of: declared), "1. Bottom Right")
        XCTAssertEqual(WasabiFormWidgets.selection(of: bare), "One")

        _ = declared.setAttribute("default", value: "2. Bottom Left")
        XCTAssertEqual(WasabiFormWidgets.selection(of: declared), "2. Bottom Left",
                       "a script's setXmlParam(\"default\", …) is what a restored pick arrives as")
    }

    // MARK: - B66: what the widgets draw

    /// No `.wal` in the corpus ships `wasabi.checkbox.*` artwork, so the box is drawn — the same
    /// deliberate exception as an artwork-less `<Wasabi:Button>`. A ticked box paints inside its
    /// outline; an empty one leaves it hollow.
    func testACheckedBoxPaintsItsGlyphAndAnEmptyOneDoesNot() throws {
        func centre(activated: Bool) throws -> [UInt8] {
            let pixels = try render(xml: """
            <WasabiXML>
              <container id="Main">
                <layout id="normal" w="16" h="16">
                  <Wasabi:CheckBox id="switch" x="0" y="0" w="16" h="16"
                                   color="0,255,0" activated="\(activated ? 1 : 0)"/>
                </layout>
              </container>
            </WasabiXML>
            """, size: CGSize(width: 16, height: 16))
            return colour(pixels, x: 5, y: 8)
        }

        XCTAssertGreaterThan(try centre(activated: true)[1], 0, "a ticked box is filled")
        XCTAssertEqual(try centre(activated: false), [0, 0, 0], "an empty box is an outline")
    }

    // MARK: - B67: a title box that declares no height

    /// The defect and its fix in one measurement. impulse's `Skin Options` is four 14px check boxes
    /// on a 20px pitch, the last at `y="60"`, so the body needs 74 and the box needs 74 + the inset
    /// it already sits in. The skin's own next box starts at `y="110"` against this box's `y="5"`,
    /// which leaves the 7px gap its one *sized* box has.
    func testATitleBoxWithNoHeightIsAsTallAsItsBodyNeeds() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="300" default_w="400" default_h="300">
          <Wasabi:TitleBox id="box" x="320" y="5" w="-325" relatw="1"
                           title="Skin Options" content="skinoptions.content"/>
        </layout>
        """, groups: """
        <groupdef id="skinoptions.content" autoheightsource="dockwindows">
          <layer id="animatedrawers" x="0" y="0" w="200" h="14"/>
          <layer id="aot" x="0" y="20" w="200" h="14"/>
          <layer id="tooltips" x="0" y="40" w="200" h="14"/>
          <layer id="dockwindows" x="0" y="60" w="200" h="14"/>
        </groupdef>
        """)
        let box = try XCTUnwrap(frame(of: "box", in: renderer))

        XCTAssertEqual(box.height, 74 - CGFloat(WasabiTitleBox.contentInset.height),
                       "the body's 74 plus the inset it sits in")
        XCTAssertEqual(box.maxY, 5 + 98, "which leaves the skin's own gap before its next box")
    }

    /// `autoheightsource` names the **last** child, and the answer is that child's bottom edge, not
    /// its own height. A group sized to the height of its last row would clip everything above it:
    /// impulse's Notifier Options names a 10px slider sitting at `y="120"`.
    func testTheAutoHeightSourceAnswersItsBottomEdgeNotItsHeight() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="400" default_w="400" default_h="400">
          <Wasabi:TitleBox id="box" x="320" y="110" w="-325" relatw="1"
                           title="Notifier Options" content="notifier.content"/>
        </layout>
        """, groups: """
        <groupdef id="notifier.content" autoheightsource="holdtime">
          <layer id="never" x="0" y="60" w="200" h="14"/>
          <layer id="holdtime" x="0" y="120" w="200" h="10"/>
        </groupdef>
        """)
        let box = try XCTUnwrap(frame(of: "box", in: renderer))

        XCTAssertEqual(box.height, 130 - CGFloat(WasabiTitleBox.contentInset.height))
    }

    /// With no `autoheightsource` the body is as tall as its lowest child reaches — the same rule,
    /// resolved from the children instead of from a name.
    func testABodyWithNoNamedSourceMeasuresItsLowestChild() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="300" default_w="400" default_h="300">
          <Wasabi:TitleBox id="box" x="0" y="0" w="200" relatw="0" content="body"/>
        </layout>
        """, groups: """
        <groupdef id="body">
          <layer id="top" x="0" y="0" w="50" h="12"/>
          <layer id="bottom" x="0" y="30" w="50" h="20"/>
        </groupdef>
        """)
        let box = try XCTUnwrap(frame(of: "box", in: renderer))

        XCTAssertEqual(box.height, 50 - CGFloat(WasabiTitleBox.contentInset.height))
    }

    /// A box that states its own height keeps it. impulse's `Color Themes` is the one of its five
    /// that does, and it was the only one that ever appeared.
    func testADeclaredHeightIsNeverMeasuredOver() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="300" default_w="400" default_h="300">
          <Wasabi:TitleBox id="box" x="5" y="5" w="305" h="200" content="body"/>
        </layout>
        """, groups: """
        <groupdef id="body">
          <layer id="row" x="0" y="0" w="50" h="20"/>
        </groupdef>
        """)
        let box = try XCTUnwrap(frame(of: "box", in: renderer))

        XCTAssertEqual(box.height, 200)
    }

    /// **Do not guess a constant.** A body that says nothing measurable — every child anchored to a
    /// height we are in the middle of computing — leaves the box exactly as it was, which is the
    /// documented alternative to inventing a number.
    func testABodyThatSaysNothingMeasurableInventsNoHeight() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="300" default_w="400" default_h="300">
          <Wasabi:TitleBox id="box" x="0" y="0" w="200" content="body"/>
        </layout>
        """, groups: """
        <groupdef id="body">
          <layer id="fill" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
        </groupdef>
        """)

        let box = try XCTUnwrap(frame(of: "box", in: renderer))
        XCTAssertEqual(box.height, 0,
                       "a box with no measurable body stays the zero-height box it declared")
    }

    // MARK: - Helpers

    private func frame(of id: String, in renderer: WasabiSceneRenderer) -> CGRect? {
        renderer.sceneNodes().first { $0.object.xmlID == id }?.frame
    }

    private func colour(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * 16 + x) * 4
        return Array(pixels[offset..<(offset + 3)])
    }

    private func render(xml: String, size: CGSize) throws -> [UInt8] {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }

        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: context)
        }
        return pixels
    }

    private func makeRenderer(layout: String, groups: String) throws -> WasabiSceneRenderer {
        let loaded = try load(layout: layout, groups: groups)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeRuntime(layout: String) throws -> WinampModernScriptRuntime {
        let runtime = try WinampModernScriptRuntime(loadedSkin: try load(layout: layout, groups: ""),
                                                    host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func load(layout: String, groups: String) throws -> WinampModernLoadedSkin {
        let url = try makeArchive(xml: """
        <WasabiXML>
          \(groups)
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase81Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
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
        func seek(to time: TimeInterval) {}
        func setVolume(_ volume: Double) {}
        func toggleShuffle() {}
        func toggleRepeat() {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
