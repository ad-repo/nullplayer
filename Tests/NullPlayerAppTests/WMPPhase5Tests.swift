import CoreGraphics
import ImageIO
import XCTest
@testable import NullPlayer

/// Phase 5: the skin draws its own controls.
///
/// Every number these tests pin is a corpus measurement recorded next to it, because the reason
/// each rule exists is how many skins it breaks — and a rule about drawing is not proved by a graph
/// that parsed. `testSliderThumbAndProgressReachThePixels` is the one that renders.
final class WMPPhase5Tests: XCTestCase {

    // MARK: - Slider geometry

    func testHorizontalThumbTravelsBetweenTheBorderInsets() {
        let track = WMPRect(x: 10, y: 20, width: 100, height: 18)
        let thumb = WMPSize(width: 10, height: 18)
        func metrics(_ value: Double) -> WMPSliderMetrics {
            WMPSliderMetrics(direction: .horizontal, minimum: 0, maximum: 100,
                             value: value, borderSize: 5)
        }
        // Travel is 100 - 2*5 - 10 = 80, starting at the left inset.
        XCTAssertEqual(metrics(0).thumbFrame(in: track, thumbSize: thumb).x, 15)
        XCTAssertEqual(metrics(50).thumbFrame(in: track, thumbSize: thumb).x, 55)
        XCTAssertEqual(metrics(100).thumbFrame(in: track, thumbSize: thumb).x, 95)
        // Centred across the short axis, and never wider than its own artwork.
        XCTAssertEqual(metrics(50).thumbFrame(in: track, thumbSize: thumb).width, 10)
    }

    func testVerticalMaximumIsAtTheTop() {
        // 1,312 of the corpus's 2,008 `direction` attributes are vertical, and every equaliser band
        // is one: +14 dB belongs at the top of the bar, not the bottom.
        let track = WMPRect(x: 0, y: 100, width: 18, height: 67)
        let thumb = WMPSize(width: 18, height: 17)
        func metrics(_ value: Double) -> WMPSliderMetrics {
            WMPSliderMetrics(direction: .vertical, minimum: -14, maximum: 14,
                             value: value, borderSize: 8)
        }
        let travel = 67 - 16 - 17.0
        XCTAssertEqual(metrics(14).thumbFrame(in: track, thumbSize: thumb).y, 108)
        XCTAssertEqual(metrics(0).thumbFrame(in: track, thumbSize: thumb).y, 108 + travel / 2)
        XCTAssertEqual(metrics(-14).thumbFrame(in: track, thumbSize: thumb).y, 108 + travel)
    }

    func testPointerValueIsTheInverseOfThumbPlacement() {
        let track = WMPRect(x: 10, y: 20, width: 100, height: 18)
        let thumb = WMPSize(width: 10, height: 18)
        let metrics = WMPSliderMetrics(direction: .horizontal, minimum: 0, maximum: 100,
                                       value: 0, borderSize: 5)
        // A press at the centre of where the thumb would sit for 50 reads back as 50.
        let centre = WMPPoint(x: 55 + 5, y: 29)
        XCTAssertEqual(metrics.value(at: centre, in: track, thumbSize: thumb), 50, accuracy: 0.001)
        // Outside the track clamps rather than extrapolating.
        XCTAssertEqual(metrics.value(at: WMPPoint(x: -100, y: 29), in: track, thumbSize: thumb), 0)
        XCTAssertEqual(metrics.value(at: WMPPoint(x: 500, y: 29), in: track, thumbSize: thumb), 100)
    }

    func testDegenerateRangeAnswersZeroRatherThanDividingByIt() {
        let metrics = WMPSliderMetrics(direction: .horizontal, minimum: 5, maximum: 5,
                                       value: 5, borderSize: 0)
        XCTAssertEqual(metrics.fraction, 0)
    }

    func testVerticalProgressFillsFromTheBottom() {
        let track = WMPRect(x: 0, y: 0, width: 10, height: 100)
        let metrics = WMPSliderMetrics(direction: .vertical, minimum: 0, maximum: 100,
                                       value: 25, borderSize: 0)
        XCTAssertEqual(metrics.progressRect(in: track), WMPRect(x: 0, y: 75, width: 10, height: 25))
    }

    // MARK: - The scene the builder produces

    func testSliderThumbAndProgressReachThePixels() async throws {
        // A 40x10 track, a 10x10 red thumb, and a green fill. At value 50 of 0...100 with
        // borderSize 5 the thumb's left edge is at 5 + (40 - 10 - 10) * 0.5 = 15.
        let track = try WMPSkinTestSupport.encodedImage(width: 40, height: 10,
            rgba: [UInt8](repeating: 0, count: 40 * 10 * 4).enumerated().map { index, _ in
                index % 4 == 3 ? 255 : 0 })
        let thumb = try WMPSkinTestSupport.encodedImage(width: 10, height: 10,
            rgba: (0..<(10 * 10)).flatMap { _ in [255, 0, 0, 255] as [UInt8] })
        let fill = try WMPSkinTestSupport.encodedImage(width: 40, height: 10,
            rgba: (0..<(40 * 10)).flatMap { _ in [0, 255, 0, 255] as [UInt8] })
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="10">
              <SLIDER id="bar" left="0" top="0" width="40" height="10" min="0" max="100"
                      value="50" borderSize="5" direction="horizontal"
                      backgroundImage="track.png" foregroundImage="fill.png" thumbImage="thumb.png"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("track.png", data: track),
            WMPTestArchiveEntry("thumb.png", data: thumb),
            WMPTestArchiveEntry("fill.png", data: fill)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let thumbCommand = try XCTUnwrap(scene.commands.last { command in
            guard case let .image(image) = command.paint else { return false }
            return image.resourcePath.hasSuffix("thumb.png")
        })
        XCTAssertEqual(thumbCommand.frame, WMPRect(x: 15, y: 0, width: 10, height: 10))

        let progress = try XCTUnwrap(scene.commands.first { command in
            guard case let .image(image) = command.paint else { return false }
            return image.resourcePath.hasSuffix("fill.png")
        })
        XCTAssertEqual(progress.frame, WMPRect(x: 0, y: 0, width: 20, height: 10),
                       "the filled half of a horizontal track runs from its left edge")

        // The widget carries what AppKit needs to drag it back, including the axis.
        let widget = try XCTUnwrap(scene.widgets.first { $0.nodeID == "bar" })
        XCTAssertEqual(widget.kind, .slider)
        XCTAssertEqual(widget.value, 50)
        XCTAssertEqual(widget.direction, .horizontal)
        XCTAssertEqual(widget.borderSize, 5)
        XCTAssertEqual(widget.thumbSize, WMPSize(width: 10, height: 10))

        // And it renders: red thumb pixels where the scene placed them, green fill to their left.
        let image = try await WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
            .render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 20, yFromTop: 5).prefix(3).map(Int.init),
                       [255, 0, 0], "the thumb is drawn at its resolved frame")
        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 5, yFromTop: 5).prefix(3).map(Int.init),
                       [0, 255, 0], "the progress artwork fills the track behind it")
    }

    func testAlphaBlendZeroHidesTheNodeAndItsSubtree() async throws {
        // 717 of the corpus's 778 `alphaBlend` uses are `"0"` — an element a script fades in later.
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20">
              <SUBVIEW id="hidden" left="0" top="0" width="40" height="10" alphaBlend="0">
                <TEXT id="inner" left="0" top="0" width="40" height="10" value="gone"/>
              </SUBVIEW>
              <SUBVIEW id="faded" left="0" top="10" width="40" height="10"
                       alphaBlend="128" backgroundColor="#FF0000"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertNil(scene.commands.first { $0.nodeID == "inner" },
                     "a transparent container takes its subtree with it")
        let faded = try XCTUnwrap(scene.commands.first { $0.nodeID == "faded" })
        XCTAssertEqual(Double(faded.alpha), 128.0 / 255, accuracy: 0.001)
    }

    func testPassthroughDrawsButNeverHits() async throws {
        // 83 corpus skins author `passthrough="true"`: drawn, and the pointer goes through it.
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20">
              <BUTTON id="live" left="0" top="0" width="40" height="20"/>
              <BUTTON id="glass" left="0" top="0" width="40" height="20" passthrough="true"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertEqual(scene.hits.map(\.nodeID), ["live"])
    }

    func testTextReadsFontFaceAndTheFullStyleSet() async throws {
        // `fontFace` is authored by 110 corpus skins against `fontType`'s 21; reading only the
        // latter rendered every one of them in the default face.
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="80" height="20">
              <TEXT id="label" left="0" top="0" width="80" height="20" value="Track"
                    fontFace="Courier New" fontSize="9" fontStyle="UNDERLINE, bold"
                    fontSmoothing="false" foregroundColor="#102030" justification="center"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let command = try XCTUnwrap(scene.commands.first { $0.nodeID == "label" })
        guard case let .text(text) = command.paint else { return XCTFail("expected a text paint") }
        XCTAssertEqual(text.fontName, "Courier New")
        XCTAssertEqual(text.fontSize, 9)
        XCTAssertTrue(text.bold); XCTAssertTrue(text.underline); XCTAssertFalse(text.italic)
        XCTAssertFalse(text.smoothed)
        XCTAssertEqual(text.alignment, .center)
        XCTAssertEqual(text.color, WMPColor(red: 0x10, green: 0x20, blue: 0x30))
    }

    // MARK: - Where a bound slider writes

    func testAValueBindingNamesTheActionTheSliderWritesTo() {
        // 163 corpus skins author a plain `<SLIDER>` and bind its value rather than using the
        // semantic tag, so the binding is the only statement of what the control does.
        XCTAssertEqual(WMPTransportAction.boundAction(for: "player.settings.volume"), .volume)
        XCTAssertEqual(WMPTransportAction.boundAction(for: "player.Controls.currentPosition"), .seek)
        XCTAssertEqual(WMPTransportAction.boundAction(for: "player.settings.balance"), .balance)
        XCTAssertEqual(WMPTransportAction.boundAction(for: "eq.gainLevel1"), .setEQBand(0))
        XCTAssertEqual(WMPTransportAction.boundAction(for: "eq.gainLevel10"), .setEQBand(9))
        XCTAssertNil(WMPTransportAction.boundAction(for: "eq.gainLevel11"))
        XCTAssertNil(WMPTransportAction.boundAction(for: "player.currentMedia.name"))
    }

    func testEqualizerGainsAnswerTheirBoundPaths() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20">
              <EQUALIZERSETTINGS id="eq" enabled="true"/>
              <SLIDER id="eq3" left="0" top="0" width="10" height="20" min="-12" max="12"
                      direction="vertical" value="wmpprop:eq.gainLevel3"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        var snapshot = WMPHostSnapshot()
        snapshot.equalizer.gains[2] = 6
        var registry = WMPObservablePropertyRegistry(graph: skin.graph)
        let changes = registry.changes(for: snapshot)
        let node = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "eq3" })
        let change = try XCTUnwrap(changes.first {
            $0.address == WMPScenePropertyAddress(stableID: node.stableID, property: "value")
        })
        XCTAssertEqual(change.value, .number(6))

        // And the scene places the thumb from it rather than from the authored default.
        var overrides = WMPSceneOverrides.empty
        overrides.properties[change.address] = change.value
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        let widget = try XCTUnwrap(scene.widgets.first { $0.nodeID == "eq3" })
        XCTAssertEqual(widget.value, 6)

        // `EQUALIZERSETTINGS` itself is a settings object with no geometry, never a control.
        XCTAssertNil(scene.widgets.first { $0.nodeID == "eq" })
    }
}

/// Phase 5, part two: the elements and attributes the first pass left ranked rather than built.
/// Each number below is `scripts/wmp_markup_census.sh` output over the 177 archives it can read.
final class WMPPhase5ControlsTests: XCTestCase {

    // MARK: - CUSTOMSLIDER (93 skins)

    func testAPositionMapReadsFractionsOutOfAGreyscaleRamp() throws {
        // The encoding was read out of `ALXMorph/seek_map.png`, which is 86x10 and steps
        // 0, 2, 5, 8 … 252 across every column: luminance is the fraction.
        let ramp = try WMPSkinTestSupport.encodedImage(width: 4, height: 2,
            rgba: (0..<2).flatMap { _ in
                [0, 0, 0, 255, 85, 85, 85, 255, 170, 170, 170, 255, 255, 255, 255, 255] as [UInt8]
            })
        let map = try WMPPositionMap(image: XCTUnwrap(decode(ramp)))
        let frame = WMPRect(x: 10, y: 20, width: 40, height: 20)
        XCTAssertEqual(try XCTUnwrap(map.fraction(at: WMPPoint(x: 15, y: 25), in: frame)), 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(map.fraction(at: WMPPoint(x: 45, y: 25), in: frame)), 1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(map.fraction(at: WMPPoint(x: 25, y: 25), in: frame)),
                       85.0 / 255, accuracy: 0.01)
    }

    func testAVerticalRampIsNotMirrored() throws {
        // A horizontal ramp is identical under a vertical flip, so it cannot see a row-order bug —
        // the same blind spot that hid W47. Dark at the top, light at the bottom.
        let ramp = try WMPSkinTestSupport.encodedImage(width: 1, height: 4,
            rgba: [0, 0, 0, 255, 85, 85, 85, 255, 170, 170, 170, 255, 255, 255, 255, 255])
        let map = try WMPPositionMap(image: XCTUnwrap(decode(ramp)))
        let frame = WMPRect(x: 0, y: 0, width: 10, height: 40)
        XCTAssertEqual(try XCTUnwrap(map.fraction(at: WMPPoint(x: 5, y: 1), in: frame)), 0,
                       accuracy: 0.01, "the top row is the authored top row")
        XCTAssertEqual(try XCTUnwrap(map.fraction(at: WMPPoint(x: 5, y: 38), in: frame)), 1,
                       accuracy: 0.01)
    }

    func testAnUnmappedPixelIsNotPartOfTheControl() throws {
        // `volume_map.png` is an arc: most of its rectangle is not on the slider's path at all.
        let punched = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [0, 0, 0, 0, 255, 255, 255, 255])
        let map = try WMPPositionMap(image: XCTUnwrap(decode(punched)))
        let frame = WMPRect(x: 0, y: 0, width: 20, height: 10)
        XCTAssertNil(map.fraction(at: WMPPoint(x: 4, y: 5), in: frame),
                     "an alpha-zero pixel is off the control, not a value of zero")
        XCTAssertEqual(try XCTUnwrap(map.fraction(at: WMPPoint(x: 15, y: 5), in: frame)), 1, accuracy: 0.01)
    }

    func testTheFilmstripAxisComesFromTheArtworkNotAnAttribute() throws {
        let ramp = try WMPSkinTestSupport.encodedImage(width: 2, height: 2,
            rgba: [0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255])
        let map = try WMPPositionMap(image: XCTUnwrap(decode(ramp)))
        // Horizontal strip: 3 frames of 2x2. `ALXMorph/volume.png` is this shape at 2232x38.
        let horizontal = WMPSize(width: 6, height: 2)
        XCTAssertEqual(map.frame(for: 0, in: horizontal), WMPRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertEqual(map.frame(for: 1, in: horizontal), WMPRect(x: 4, y: 0, width: 2, height: 2))
        // Vertical strip: 3 frames of 2x2. `ALXMorph/seek.png` is this shape at 86x600.
        let vertical = WMPSize(width: 2, height: 6)
        XCTAssertEqual(map.frame(for: 0, in: vertical), WMPRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertEqual(map.frame(for: 1, in: vertical), WMPRect(x: 0, y: 4, width: 2, height: 2))
        // Artwork that is not a whole multiple is not a strip, and is drawn whole.
        XCTAssertNil(map.frame(for: 0.5, in: WMPSize(width: 5, height: 2)))
        XCTAssertNil(map.frame(for: 0.5, in: WMPSize(width: 2, height: 2)))
    }

    func testACustomSliderIsSizedByItsMapAndNotByItsFilmstrip() async throws {
        // The bug this pins is quantitative: sizing from `image` makes ALXMorph's volume control
        // 2,232 pixels wide inside a 400-pixel window.
        let map = try WMPSkinTestSupport.encodedImage(width: 10, height: 4,
            rgba: (0..<40).flatMap { index in
                let value = UInt8(index % 10 * 25)
                return [value, value, value, 255] as [UInt8]
            })
        let strip = try WMPSkinTestSupport.encodedImage(width: 50, height: 4,
            rgba: (0..<200).flatMap { _ in [10, 20, 30, 255] as [UInt8] })
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20">
              <CUSTOMSLIDER id="vol" left="0" top="0" min="0" max="100" value="50"
                            image="strip.png" positionImage="map.png"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("map.png", data: map),
            WMPTestArchiveEntry("strip.png", data: strip)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let geometry = try XCTUnwrap(scene.geometries.values.first { $0.absoluteFrame.width == 10 })
        XCTAssertEqual(geometry.absoluteFrame, WMPRect(x: 0, y: 0, width: 10, height: 4))
        // 5 frames of 10 wide; value 50 of 0...100 selects frame 2.
        let command = try XCTUnwrap(scene.commands.first { $0.nodeID == "vol" })
        guard case let .image(image) = command.paint else { return XCTFail("expected an image") }
        XCTAssertEqual(image.sourceRect, WMPRect(x: 20, y: 0, width: 10, height: 4))
        XCTAssertEqual(try XCTUnwrap(scene.hits.first { $0.nodeID == "vol" }).positionMap?.size,
                       WMPSize(width: 10, height: 4), "the drag reads the same map the scene drew")
    }

    // MARK: - cursor (145 skins) and tabStop (119)

    func testNamedCursorsAreRecognisedAndFileCursorsAreNot() async throws {
        // 2,246 of the corpus's 2,319 non-empty `cursor` values are named; the rest are `.cur`
        // and `.ani` files, which no macOS decoder reads.
        XCTAssertEqual(WMPCursor(authored: "hand"), .hand)
        XCTAssertEqual(WMPCursor(authored: "SIZENWSE"), .sizeNWSE)
        XCTAssertEqual(WMPCursor(authored: "system"), .system)
        XCTAssertNil(WMPCursor(authored: "resize.cur"))
        XCTAssertNil(WMPCursor(authored: "over.ani"))

        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20">
              <BUTTON id="a" left="0" top="0" width="20" height="20" cursor="hand" tabStop="false"/>
              <BUTTON id="b" left="20" top="0" width="20" height="20"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let a = try XCTUnwrap(scene.hits.first { $0.nodeID == "a" })
        let b = try XCTUnwrap(scene.hits.first { $0.nodeID == "b" })
        XCTAssertEqual(a.cursor, .hand); XCTAssertNil(b.cursor)
        XCTAssertFalse(a.tabStop, "tabStop=\"false\" is out of the keyboard ring")
        XCTAssertTrue(b.tabStop, "absent means in, as in WMP")
    }

    // MARK: - clippingImage (25 skins with a non-empty one)

    func testAClippingImageShapesTheElement() async throws {
        // Split top/bottom on purpose: a left/right mask cannot see a vertical flip, which is the
        // bug W47 was.
        let art = try WMPSkinTestSupport.encodedImage(width: 4, height: 4,
            rgba: (0..<16).flatMap { _ in [0, 0, 255, 255] as [UInt8] })
        let mask = try WMPSkinTestSupport.encodedImage(width: 4, height: 4,
            rgba: (0..<16).flatMap { index -> [UInt8] in
                index < 8 ? [255, 0, 255, 255] : [255, 255, 255, 255]   // top half keyed out
            })
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="4" height="4">
              <IMAGE id="art" left="0" top="0" width="4" height="4" image="art.png"
                     clippingImage="mask.png" clippingColor="#FF00FF"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("art.png", data: art),
            WMPTestArchiveEntry("mask.png", data: mask)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let artCommand = try XCTUnwrap(scene.commands.first { $0.nodeID == "art" })
        guard case let .image(spec) = artCommand.paint else { return XCTFail("expected an image") }
        XCTAssertNotNil(spec.clippingMaskPath, "the scene carries the mask")
        XCTAssertEqual(spec.clippingMaskKeys, [WMPColor(red: 255, green: 0, blue: 255)])
        let image = try await WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
            .render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 1, yFromTop: 0)[3], 0,
                       "the top half is cut away by the mask")
        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 1, yFromTop: 3).prefix(3).map(Int.init),
                       [0, 0, 255], "the bottom half survives — and it is the bottom, not the top")
    }

    // MARK: - Animated GIFs (90 of 180 archives)

    func testAnimationClockPicksTheFrameAndZeroDurationHolds() {
        let animation = WMPImageAnimation(delays: [0.1, 0.2, 0.1])
        XCTAssertEqual(animation.duration, 0.4, accuracy: 0.0001)
        XCTAssertEqual(animation.frameIndex(at: 0), 0)
        XCTAssertEqual(animation.frameIndex(at: 0.15), 1)
        XCTAssertEqual(animation.frameIndex(at: 0.35), 2)
        XCTAssertEqual(animation.frameIndex(at: 0.45), 0, "it loops")
        XCTAssertEqual(WMPImageAnimation(delays: [0]).frameIndex(at: 5), 0,
                       "a zero-duration animation holds rather than dividing by it")
        XCTAssertEqual(WMPImageAnimation(delays: [0.1, 0.1]).frameIndex(at: .infinity), 0,
                       "a non-finite clock is not a frame index")
    }

    // MARK: - POPUP (4 skins, all of them equaliser preset menus)

    func testPopupItemsComeFromTheSkinsOwnScript() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20" onLoad="Fill();" scriptFile="s.js">
              <POPUP id="popupPreset" left="0" top="0" width="40" height="20"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("s.js", data: Data("""
            function Fill() {
                popupPreset.appendItem('Rock');
                popupPreset.appendItem('Jazz');
            }
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let suite = "WMPPhase5ControlsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = WMPScriptRuntime(
            preferences: WMPPreferenceStore(skinData: Data("popup".utf8), defaults: defaults))
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let output = await runtime.transact(skin: skin, viewID: "main", size: scene.canvasSize,
                                            snapshot: WMPHostSnapshot(),
                                            event: WMPJScriptEvent(name: "load", targetID: nil,
                                                                   handlers: ["Fill();"]),
                                            geometry: scene.scriptGeometry)
        let node = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "popupPreset" })
        XCTAssertEqual(output.listItems[node.stableID], ["Rock", "Jazz"],
                       "the menu's contents are transaction output; the markup names none of them")
        await runtime.teardown()
    }

    private func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
