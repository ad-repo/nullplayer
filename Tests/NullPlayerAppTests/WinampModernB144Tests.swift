import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B144 — cPro2 Styler's time and bitrate readouts drew on top of each other, and the elapsed clock
/// came back with its digits chopped off at the bottom.
///
/// Reported live on the three Styler skins: `0:30/ 4:31` with the separator sitting on the last
/// digit, the stereo icon overlapping `858kbps`, and every round digit flat-bottomed. Settled
/// against the author's own **1:1** Winamp screenshots of the skin
/// (`deviantart.com/victhor/art/cPro2-Styler-Skin-project-468424123`) rather than by reasoning: the
/// info panel is 40px there and its stereo sprite 13px, which is what makes the shot measurable.
///
/// Two independent rules came out of it.
///
/// **A `<text>` reserves two pixels on each side, and `getTextWidth()` carries them.** ClassicPro's
/// `info-text.m` puts the total time at `trackTime.getTextWidth() - 4 + 21` inside a box that starts
/// at 21 and is `getTextWidth()` wide — a deliberate 4px tuck — and lays the bitrate row out as
/// `getTextWidth() + 18` around a right-aligned `w="-5" relatw="1"`. Neither has any clearance unless
/// the number a script reads back is wider than the ink drawn from it. In the reference `2:12` is
/// 35px of ink with the `/` 2px past it, putting Winamp's `getTextWidth("2:12")` at 42 against 37.24
/// of Century Gothic advances; the bitrate row clears its icon by 4px and needs the same margin.
/// Two font sizes, two string lengths, the same +4 — so it is neither per-glyph nor size-scaled. It
/// is also what [B87](WinampModernB87Tests.swift) met from the other side: ClassicPro's SUI tab is
/// `getAutoWidth() + 14` inside `w="-15" relatw="1"` and its v2 engine `getTextWidth() + 23` inside
/// `w="-26"`, boxes 1 and 3 short of the string they were sized for — the margin, less the slack a
/// tab wants.
///
/// **A line is centred in the cell the skin declared, even when it does not fit.** The renderer
/// centred on the *face's* `ascender - descender` and clamped the offset at zero, so any line taller
/// than its box became `valign="top"`. Century Gothic reports 23.5 for a 24px cell and puts 19.3 of
/// it above the baseline against digits only 14 tall, so Styler's clock sat a pixel low in its 22px
/// box — and ClassicPro's `two.info.text.time` group is exactly 20px (`h="50" relath="2"`, half the
/// info panel), so that pixel went through the group's clip and took the bottom off every `0`, `3`
/// and `9`. `WasabiTextMetrics.lineHeight(of:)` already answers `fontsize` for `getAutoHeight()`;
/// the renderer now centres on the same number, and the offset may go negative.
///
/// The vertical scissor moved to the object's own box at the same time. It used to follow the
/// *shifted* rect, which is the same rect while the line fits and is dragged out of the box the
/// moment a negative offset exists — carrying the cut above the box with it, where BB27 and B87 both
/// say the box bounds the string.
final class WinampModernB144Tests: XCTestCase {

    // MARK: - The box margin

    /// The rule itself: a script measuring a string is told four pixels more than the ink.
    func testGetTextWidthCarriesTheBoxMargin() throws {
        let runtime = try makeRuntime()
        let label = try object(named: "label", in: runtime)
        let metrics = runtime.metrics
        let font = try XCTUnwrap(metrics.font(identifier: nil,
                                              size: WasabiTextMetrics.pointSize(of: label)) as NSFont?)

        let reported = try width(of: label, in: runtime, method: "gettextwidth")
        let ink = metrics.measuredWidth(of: "Playback Stopped", font: font)

        XCTAssertEqual(CGFloat(reported), (ink + WasabiTextMetrics.boxMargin).rounded(.up),
                       "the string, plus two pixels on each side")
    }

    /// `getAutoWidth()` is the same measurement, and ClassicPro sizes its SUI tabs from it.
    func testGetAutoWidthCarriesTheSameMargin() throws {
        let runtime = try makeRuntime()
        let label = try object(named: "label", in: runtime)

        XCTAssertEqual(try width(of: label, in: runtime, method: "getautowidth"),
                       try width(of: label, in: runtime, method: "gettextwidth"))
    }

    /// An object showing nothing measures nothing. `autowidthsource` collapses a group whose source a
    /// script has not filled in yet, and a margin around an empty string would give it a 4px box.
    func testAnEmptyStringStillMeasuresZero() throws {
        let runtime = try makeRuntime()
        let label = try object(named: "label", in: runtime)
        _ = label.setAttribute("text", value: "")

        XCTAssertEqual(try width(of: label, in: runtime, method: "gettextwidth"), 0)
    }

    /// **Measurement only.** The margin moves the boxes a script computes and never the ink inside
    /// one: a right-aligned string still ends at its box's right edge, which is where Winamp's
    /// `DT_RIGHT` puts it, and four pixels of inset here would undo the clearance the rule exists to
    /// give.
    func testTheMarginDoesNotInsetTheDrawnString() throws {
        let scene = try makeScene(canvas: CGSize(width: 120, height: 40), markup: """
              <text id="label" x="0" y="0" w="120" h="40" fontsize="16" color="255,255,255"
                    align="right" text="Xy"/>
        """)
        let ink = try XCTUnwrap(scene.inkColumns())

        XCTAssertEqual(ink.upperBound, 120, accuracy: 2, "flush against the box's right edge")
    }

    // MARK: - Vertical placement

    /// The reported chop: a line taller than its box is centred in it, so half the overflow is above
    /// the box and the digits no longer hang off the bottom.
    func testALineTallerThanItsBoxIsCentredNotTopAligned() throws {
        let scene = try makeScene(canvas: CGSize(width: 200, height: 60), markup: """
              <text id="label" x="0" y="20" w="200" h="20" fontsize="30" color="255,255,255"
                    text="0:09"/>
        """)
        let rows = try XCTUnwrap(scene.inkRows())
        let centre = (rows.lowerBound + rows.upperBound) / 2

        XCTAssertEqual(centre, 30, accuracy: 2, "the ink straddles the middle of its own box")
    }

    /// The same string in a box with room to spare is where it always was — the change is only ever
    /// about the case that does not fit.
    func testALineThatFitsIsUnmoved() throws {
        let scene = try makeScene(canvas: CGSize(width: 200, height: 60), markup: """
              <text id="label" x="0" y="10" w="200" h="40" fontsize="14" color="255,255,255"
                    text="0:09"/>
        """)
        let rows = try XCTUnwrap(scene.inkRows())
        let centre = (rows.lowerBound + rows.upperBound) / 2

        XCTAssertEqual(centre, 30, accuracy: 2, "centred in a box it fits, as before")
    }

    /// BB27 and B87's rule, which the negative offset must not take with it: the box is still what
    /// bounds a string vertically. Nothing may reach the row above it.
    func testTheBoxStillBoundsAnOverflowingLine() throws {
        let scene = try makeScene(canvas: CGSize(width: 200, height: 90), markup: """
              <text id="above" x="0" y="0"  w="200" h="30" fontsize="12" color="255,255,255"
                    text="Xy"/>
              <text id="label" x="0" y="40" w="200" h="10" fontsize="40" color="255,255,255"
                    text="0:09"/>
        """)
        let rows = try XCTUnwrap(scene.inkRows(in: 30..<90))

        XCTAssertGreaterThanOrEqual(rows.lowerBound, 40, "nothing above the box")
        XCTAssertLessThanOrEqual(rows.upperBound, 50, "nothing below it")
    }

    /// `valign="top"` still means the top. Centring an oversized line is the *default* alignment's
    /// business, not a new rule for the two a skin can ask for by name.
    func testAnExplicitTopAlignmentIsUnaffected() throws {
        let centred = try makeScene(canvas: CGSize(width: 200, height: 60), markup: """
              <text id="label" x="0" y="20" w="200" h="20" fontsize="30" color="255,255,255"
                    text="0:09"/>
        """)
        let topped = try makeScene(canvas: CGSize(width: 200, height: 60), markup: """
              <text id="label" x="0" y="20" w="200" h="20" fontsize="30" color="255,255,255"
                    valign="top" text="0:09"/>
        """)
        let a = try XCTUnwrap(centred.inkRows())
        let b = try XCTUnwrap(topped.inkRows())

        XCTAssertLessThan(a.lowerBound, b.lowerBound,
                          "the centred line rides higher than the one pinned to the box's top")
    }

    // MARK: - Fixture

    private struct Scene {
        let renderer: WasabiSceneRenderer

        func inkColumns(in band: Range<Int>? = nil) -> ClosedRange<CGFloat>? {
            extent(band: band, horizontal: true)
        }

        func inkRows(in band: Range<Int>? = nil) -> ClosedRange<CGFloat>? {
            extent(band: band, horizontal: false)
        }

        private func extent(band: Range<Int>?, horizontal: Bool) -> ClosedRange<CGFloat>? {
            let width = Int(renderer.canvasSize.width)
            let height = Int(renderer.canvasSize.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = pixels.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context else { return nil }
            renderer.invalidateSceneCache()
            // `NSString.draw(in:)` needs an AppKit context to draw into; without one the TrueType
            // path silently paints nothing and every measurement here reads empty.
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = saved
            var low = Int.max
            var high = Int.min
            // A row index is the scene's own y: the buffer is bottom-up and the renderer draws the
            // scene top-down, and the two cancel.
            let rows = horizontal ? 0..<height : (band ?? 0..<height)
            let columns = horizontal ? (band ?? 0..<width) : 0..<width
            for y in rows where y < height {
                for x in columns where x < width && pixels[(y * width + x) * 4 + 3] > 8 {
                    let value = horizontal ? x : y
                    low = min(low, value)
                    high = max(high, value + 1)
                }
            }
            guard low <= high else { return nil }
            return CGFloat(low)...CGFloat(high)
        }
    }

    private func width(of object: WasabiObject, in runtime: WinampModernScriptRuntime,
                       method: String) throws -> Int32 {
        try runtime.invoke(method: method, on: MakiObjectReference(.gui(object.stableID)),
                           arguments: [], program: emptyProgram()).integerValue
    }

    private func makeRuntime() throws -> WinampModernScriptRuntime {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="200" h="40">
              <text id="label" x="0" y="0" w="200" h="20" fontsize="13" text="Playback Stopped"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func object(named xmlID: String, in runtime: WinampModernScriptRuntime) throws
        -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: xmlID).first)
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private func makeScene(canvas: CGSize, markup: String) throws -> Scene {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="\(Int(canvas.width))" h="\(Int(canvas.height))">
        \(markup)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return Scene(renderer: renderer)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB144Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B144-\(UUID().uuidString).wal")
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
