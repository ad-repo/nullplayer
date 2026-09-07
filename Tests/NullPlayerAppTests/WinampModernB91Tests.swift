import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B91 — Hal's Eye: a manual whose pages would not turn, a credits box showing one clipped line, and
/// a rotating eye that never started.
///
/// Reported live 2026-08-31 as *"in 1-hal skin the user manual page buttons do not work, in the
/// credits window the text is truncated"*, then *"double click does not do anything"*. Four separate
/// causes under one skin, three of which are engine-wide capabilities rather than anything about this
/// archive.
///
/// **The pages.** `manual.maki`'s `onScriptLoaded` caches `getCurFrame()` and `getEndFrame()` off the
/// page sprite sheet and both button handlers clamp against them. Dispatch fails closed on a missing
/// **signature**, so the initialiser abandoned at the `getEndFrame` call with the end frame still 0 —
/// and 0 is also the current frame, so *both* guards read "already at the end" and returned. The
/// buttons drew, pressed, ran their handler and did nothing. Corpus: 4 skins call it.
///
/// **The credits.** `wrap="1"` was not implemented at all — every `<text>` drew as one line, cut at
/// its own box — and our synthesized `<Wasabi:Text>` seeded neither `wrap` nor `valign`. Winamp's own
/// definition of that tag is measured from the six skins that ship a replacement for it: all six say
/// `valign="top"` and four also say `wrap="1"`.
///
/// **The rotation.** `rotate.maki` clips the spinning eye to a region and aborts its whole
/// `onScriptLoaded` on `Region.loadFromBitmap`, which was unimplemented. That took the rotation timer
/// and the region with it. Three other corpus skins call it — BLAKK clips its seek bar and its
/// boombox spectrum this way, and both drew unclipped and permanently full.
///
/// **The double-click menu** is a fourth cause with no unit test here, because it is an AppKit event
/// ordering problem rather than an engine one: `onLeftButtonDblClk` is dispatched from `mouseDown`,
/// so `popAtMouse` opened its modal tracking loop with the left button still physically down and the
/// release that ended the double-click dismissed the menu before it drew. See
/// `WinampModernMainView.presentScriptPopup`, which drains that release first. It is covered by the
/// live verification, not by a test: nothing in the harness holds a mouse button down.
final class WinampModernB91Tests: XCTestCase {

    // MARK: - The page buttons: an animated layer's own frame range

    /// The Hal's Eye shape: a 232x1200 sheet cut into six 232x200 frames, with no explicit range set.
    /// Unset means "the whole sheet", so the end frame is the last one — which is what the skin's
    /// `next` guard compares against.
    func testGetEndFrameOnALayerWithNoRangeIsTheLastFrameOfTheSheet() throws {
        let (runtime, program) = try makeRuntime()
        let layer = try object(runtime, "pages")

        let end = try runtime.invoke(method: "getEndFrame", on: reference(layer),
                                     arguments: [], program: program)
        XCTAssertEqual(end.integerValue, 5, "six frames, so frames 0…5")
    }

    /// And the start of an unset range is frame 0, the other half of the same pair.
    func testGetStartFrameOnALayerWithNoRangeIsZero() throws {
        let (runtime, program) = try makeRuntime()
        let layer = try object(runtime, "pages")

        let start = try runtime.invoke(method: "getStartFrame", on: reference(layer),
                                       arguments: [], program: program)
        XCTAssertEqual(start.integerValue, 0)
    }

    /// A range a script set is what it reads back — the read halves answer `setStartFrame` and
    /// `setEndFrame`, which is how MMD3 sweeps its knobs frame-range to frame-range.
    func testAScriptSetRangeIsReadBack() throws {
        let (runtime, program) = try makeRuntime()
        let layer = try object(runtime, "pages")

        _ = try runtime.invoke(method: "setStartFrame", on: reference(layer),
                               arguments: [.integer(1)], program: program)
        _ = try runtime.invoke(method: "setEndFrame", on: reference(layer),
                               arguments: [.integer(4)], program: program)

        let start = try runtime.invoke(method: "getStartFrame", on: reference(layer),
                                       arguments: [], program: program)
        let end = try runtime.invoke(method: "getEndFrame", on: reference(layer),
                                     arguments: [], program: program)
        XCTAssertEqual(start.integerValue, 1)
        XCTAssertEqual(end.integerValue, 4)
    }

    /// A range outside the sheet is clamped rather than handed back raw: the skin's guard is
    /// `curFrame == endFrame`, and an end frame the play head can never reach is a pager that never
    /// stops.
    func testARangeBeyondTheSheetIsClampedToIt() throws {
        let (runtime, program) = try makeRuntime()
        let layer = try object(runtime, "pages")

        _ = try runtime.invoke(method: "setEndFrame", on: reference(layer),
                               arguments: [.integer(99)], program: program)
        let end = try runtime.invoke(method: "getEndFrame", on: reference(layer),
                                     arguments: [], program: program)
        XCTAssertEqual(end.integerValue, 5)
    }

    /// The whole point of the pair: a signature the table does not carry aborts the handler that
    /// calls it, so "implemented" has to mean the runtime *accepts* the call, not merely that a case
    /// exists somewhere. This is the assertion that would have caught B91 at the source.
    func testTheFrameRangeMethodsAreAccepted() throws {
        let (runtime, program) = try makeRuntime()
        let layer = try object(runtime, "pages")

        for method in ["getStartFrame", "getEndFrame", "getCurFrame", "getLength"] {
            XCTAssertNoThrow(try runtime.invoke(method: method, on: reference(layer),
                                                arguments: [], program: program),
                             "\(method) must not fail closed")
        }
    }

    // MARK: - The credits box: a paragraph is not a line

    /// The reported defect. A long string in a `wrap="1"` box drew as a single line clipped at the
    /// box edge; it now breaks at word boundaries and stacks downward, so the tail of the string is
    /// on screen instead of thrown away.
    func testAWrappingTextDrawsMoreThanOneLine() throws {
        let unwrapped = try renderRows(wrap: false)
        let wrapped = try renderRows(wrap: true)

        XCTAssertEqual(unwrapped, 1, "without wrap the string is one clipped line")
        XCTAssertGreaterThan(wrapped, 2, "with it the paragraph occupies several rows of the box")
    }

    /// A paragraph's vertical alignment is measured against the **whole broken block**, not against
    /// one line's leading. Both boxes below are the same size and both take Wasabi's default
    /// centring; the one-liner sits on the middle of the box, and the block — being nearly as tall
    /// as the box — has to start near its top. Aligning the block by a single line's height instead
    /// would centre its *first* line on that same middle and run the other six out of the bottom,
    /// which on Hal's credits is everything below "…in this place".
    func testAWrappingBlockIsAlignedByItsOwnHeightNotByOneLine() throws {
        let oneLine = try makeTextScene(text: "one two", wrap: true, extra: "")
        let block = try makeTextScene(text: Self.paragraph, wrap: true, extra: "")
        let oneLineTop = try XCTUnwrap(oneLine.firstPaintedRow())
        let blockTop = try XCTUnwrap(block.firstPaintedRow())

        XCTAssertGreaterThan(oneLineTop, 30, "a single line centres on the box")
        XCTAssertLessThan(blockTop, oneLineTop - 10,
                          "and a block of seven does not start where that line does")
    }

    /// `valign=` still wins where a skin states one, so this is a default and not a policy.
    func testAnExplicitValignStillPlacesAWrappingBlock() throws {
        let top = try makeTextScene(text: "one two", wrap: true, extra: #"valign="top""#)
        let bottom = try makeTextScene(text: "one two", wrap: true, extra: #"valign="bottom""#)
        let topRow = try XCTUnwrap(top.firstPaintedRow())
        let bottomRow = try XCTUnwrap(bottom.firstPaintedRow())
        XCTAssertGreaterThan(bottomRow, topRow, "bottom alignment pushes the block down its box")
    }

    /// Winamp's own `<Wasabi:Text>` is a wrapping, top-aligned label. Seeded rather than forced: an
    /// instance that states either keeps its own.
    func testTheStandardTextWidgetWrapsAndAlignsTopByDefault() throws {
        let substitution = try XCTUnwrap(WasabiFormWidgets.substitution(forTypeName: "Wasabi:Text"))
        XCTAssertEqual(substitution.typeName, "text")
        XCTAssertEqual(substitution.defaults["wrap"], "1")
        XCTAssertEqual(substitution.defaults["valign"], "top")
    }

    /// XML has no way to write a line break inside an attribute value, so a skin spells one the way
    /// the MAKI compiler takes it. Hal's credits is the corpus's only such literal and its escapes
    /// ran straight through into the drawn text.
    func testABackslashNInAMarkupLiteralIsALineBreak() throws {
        let scene = try makeTextScene(text: #"alpha\nbeta"#, wrap: true, extra: "")
        XCTAssertGreaterThan(scene.paintedRowCount(), 1, "two lines, not one with a stray glyph pair")
        XCTAssertFalse(scene.drawnText.contains("\\n"), "the escape is consumed, not drawn")
        XCTAssertTrue(scene.drawnText.contains("\n"))
    }

    /// The bound: only the **markup** literal. A string a script assigned already carries real
    /// newlines — MAKI resolves its own escapes at compile time — so translating there would eat a
    /// backslash the script meant to keep.
    func testAScriptAssignedStringKeepsItsBackslashes() throws {
        let (runtime, program) = try makeRuntime()
        let label = try object(runtime, "caption")

        _ = try runtime.invoke(method: "setText", on: reference(label),
                               arguments: [.string(#"C:\new\table"#)], program: program)
        XCTAssertEqual(WasabiTextMetrics.content(of: label, host: runtime.host),
                       #"C:\new\table"#)
    }

    // MARK: - The rotating eye: a region from a bitmap

    /// `Region.loadFromBitmap(id)` is `loadFromMap` without the `Map` in front of it: the shape is
    /// the bitmap's own opaque area. The layer is clipped to the silhouette, so a pixel the mask
    /// bitmap leaves transparent is not painted even where the layer's own artwork is solid.
    func testARegionLoadedFromABitmapClipsTheLayerToItsOpaqueArea() throws {
        let scene = try makeRegionScene()
        let inside = try XCTUnwrap(scene.pixel(x: 4, y: 4))
        let outside = try XCTUnwrap(scene.pixel(x: 12, y: 12))
        XCTAssertEqual(Int(inside.alpha), 255, "the mask is opaque here, so the layer draws")
        XCTAssertEqual(Int(outside.alpha), 0, "and transparent here, so it does not")
    }

    /// And it is accepted, which is the half that mattered: the call sat in the middle of
    /// `rotate.maki`'s initialiser and BLAKK's `boombox.m`, so failing closed on it cost everything
    /// those handlers had left to do.
    func testLoadFromBitmapIsAccepted() throws {
        let (runtime, program) = try makeRuntime()
        // `new Region` is a bytecode instruction, not a method call, so a test reaches the object
        // through the same factory the interpreter uses. The GUID is unimportant: every class
        // without a host singleton behind it becomes a generic dynamic shell, and `loadFromBitmap`
        // is what gives this one its role.
        let region = MakiValue.object(try runtime.makeObject(classGUID: "region", program: program))
        guard case .object(let reference) = region else {
            return XCTFail("`new Region` did not produce an object")
        }
        XCTAssertNoThrow(try runtime.invoke(method: "loadFromBitmap", on: reference,
                                            arguments: [.string("mask")], program: program))
    }

    // MARK: - Fixture

    private static let paragraph = """
        There are some people who have been a great help making this skin and I want to thank them \
        in this place, and this sentence is long enough that no single line of it fits the box.
        """

    private struct Scene {
        let renderer: WasabiSceneRenderer
        let drawnText: String

        private func pixels() -> (data: [UInt8], width: Int, height: Int)? {
            let width = Int(renderer.canvasSize.width)
            let height = Int(renderer.canvasSize.height)
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let context = buffer.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context else { return nil }
            renderer.invalidateSceneCache()
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = saved
            return (buffer, width, height)
        }

        func pixel(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
            guard let (data, width, height) = pixels(),
                  x >= 0, x < width, y >= 0, y < height else { return nil }
            // `y` counts down from the top of the scene, which is also the order the bitmap
            // context's rows are stored in — verified against `valign="top"` landing near row 0.
            let offset = (y * width + x) * 4
            return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
        }

        /// Scene rows carrying any painted pixel — the objective form of "how many lines is this?".
        private func paintedRows() -> [Int] {
            guard let (data, width, height) = pixels() else { return [] }
            var rows: [Int] = []
            for y in 0..<height {
                for x in 0..<width where data[(y * width + x) * 4 + 3] > 0 {
                    rows.append(y)
                    break
                }
            }
            return rows
        }

        /// Painted rows collapsed into runs, which is the line count: the gap between two lines of
        /// text is a band of untouched rows.
        func paintedRowCount() -> Int {
            let rows = paintedRows()
            guard let first = rows.first else { return 0 }
            var lines = 1
            var previous = first
            for row in rows.dropFirst() {
                if row > previous + 1 { lines += 1 }
                previous = row
            }
            return lines
        }

        func firstPaintedRow() -> Int? { paintedRows().first }
    }

    private func renderRows(wrap: Bool) throws -> Int {
        try makeTextScene(text: Self.paragraph, wrap: wrap, extra: #"valign="top""#).paintedRowCount()
    }

    /// A box narrower than the string, on a transparent layout, so every painted pixel is the text.
    private func makeTextScene(text: String, wrap: Bool, extra: String) throws -> Scene {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="120" h="90">
              <text id="body" x="0" y="0" w="120" h="90" font="Helvetica" fontsize="12"
                    color="255,255,255" wrap="\(wrap ? 1 : 0)" \(extra) default="\(text)"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try makeSkin(xml: xml)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        addTeardownBlock { loaded.teardown() }
        let body = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "body").first)
        return Scene(renderer: renderer,
                     drawnText: WasabiTextMetrics.content(of: body, host: TestHost()))
    }

    /// An 8x8 opaque square in the top-left of a 16x16 sheet: the mask's own alpha is the shape, and
    /// the clipped layer's artwork covers the whole box, so the region is the only thing that can
    /// make its bottom-right transparent.
    private func makeRegionScene() throws -> Scene {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="mask" file="mask.png"/>
            <bitmap id="fill" file="fill.png"/>
          </elements>
          <container id="main">
            <layout id="normal" w="16" h="16">
              <layer id="clipped" image="fill" x="0" y="0" w="16" h="16"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try load(files: [
            ("skin.xml", Data(xml.utf8)),
            ("mask.png", Self.cornerPNG()),
            ("fill.png", Self.solidPNG()),
        ])
        addTeardownBlock { loaded.teardown() }
        let host = TestHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        let program = Self.emptyProgram()

        // `new Region` is a bytecode instruction, not a method call, so a test reaches the object
        // through the same factory the interpreter uses. The GUID is unimportant: every class
        // without a host singleton behind it becomes a generic dynamic shell, and `loadFromBitmap`
        // is what gives this one its role.
        let region = MakiValue.object(try runtime.makeObject(classGUID: "region", program: program))
        guard case .object(let regionReference) = region else {
            throw XCTSkip("`new Region` did not produce an object")
        }
        _ = try runtime.invoke(method: "loadFromBitmap", on: regionReference,
                               arguments: [.string("mask")], program: program)
        let clipped = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "clipped").first)
        _ = try runtime.invoke(method: "setRegion", on: MakiObjectReference(.gui(clipped.stableID)),
                               arguments: [region], program: program)

        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return Scene(renderer: renderer, drawnText: "")
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try load(files: [
            ("skin.xml", Data("""
            <WasabiXML>
              <elements>
                <bitmap id="sheet" file="sheet.png"/>
                <bitmap id="mask" file="mask.png"/>
              </elements>
              <container id="main">
                <layout id="normal" w="120" h="90">
                  <animatedlayer id="pages" image="sheet" x="0" y="0" w="16" h="8"/>
                  <text id="caption" x="0" y="60" w="120" h="20" default=""/>
                </layout>
              </container>
            </WasabiXML>
            """.utf8)),
            // 16x48 cut into 16x8 frames: six of them, the Hal's Eye shape in miniature.
            ("sheet.png", Self.solidPNG(width: 16, height: 48)),
            ("mask.png", Self.cornerPNG()),
        ])
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return (runtime, Self.emptyProgram())
    }

    private static func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/b91.maki"),
                    ownerID: nil, parameter: nil)
    }

    private func object(_ runtime: WinampModernScriptRuntime, _ id: String) throws -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: id).first)
    }

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        try load(files: [("skin.xml", Data(xml.utf8))])
    }

    private func load(files: [(String, Data)]) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB91Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B91-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return try WinampModernSkinLoader(engineStore: nil).load(from: url)
    }

    private static func solidPNG(width: Int = 16, height: Int = 16) -> Data {
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
                                              pixelsHigh: height, bitsPerSample: 8,
                                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: width * 4,
                                              bitsPerPixel: 32)!
        var components = [220, 40, 60, 255]
        for y in 0..<height {
            for x in 0..<width { representation.setPixel(&components, atX: x, y: y) }
        }
        return representation.representation(using: .png, properties: [:])!
    }

    /// Opaque in the top-left 8x8, fully transparent elsewhere.
    private static func cornerPNG() -> Data {
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB,
                                              bytesPerRow: 64, bitsPerPixel: 32)!
        for y in 0..<16 {
            for x in 0..<16 {
                var components = x < 8 && y < 8 ? [255, 255, 255, 255] : [0, 0, 0, 0]
                representation.setPixel(&components, atX: x, y: y)
            }
        }
        return representation.representation(using: .png, properties: [:])!
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
        var trackDisplayTitle = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 2
        var spectrumLevels: [Float] = []
        var isArtworkLoading = false
        var vuLevels: (left: Double, right: Double) = (0, 0)

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
