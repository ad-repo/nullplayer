import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B113 — the plate NullPlayer's own lists are painted on is the skin's **list** background, not its
/// **edit** background.
///
/// Reported 2026-09-04 as *"is there a filter in front of the displays?"* on Itemskin: the library,
/// the playlist and every readout drew in a dark, muddy olive. There is no filter, and the empty
/// first `<gammaset>` the first diagnosis blamed is a red herring — an author who names a set
/// `(default)` and leaves it empty means the artwork as drawn, and 6 of the 47 corpus skins that
/// declare gammasets do exactly that.
///
/// The defect was one link of one chain. Itemskin declares `wasabi.list.text` `80,70,0` against
/// `wasabi.list.background` `220,175,0` — dark olive on gold, 4.59:1, and gold is the skin's whole
/// display language — while its *text fields* are `wasabi.edit.background` `42,42,42`.
/// `contentBackground` led with the edit colour, so the rows landed on charcoal at **1.52:1**, and
/// B48's guard cannot lift them: `legibleRowColor` deliberately leaves unselected rows alone.
///
/// **Eleven of the 69 corpus skins** declare the two ids and mean them differently, six of them
/// below 3:1 before the fix (K-jr and Pure Inspired at 1.46:1, black on charcoal). In every one of
/// them the *column header* colour — unambiguously part of the list — sits in the same lightness
/// family as `wasabi.list.background` and not as `wasabi.edit.background`, which is the independent
/// corroboration that the list ids are the right pick.
///
/// The second half is why `editBackground` exists at all: `<Wasabi:EditBox>` and
/// `<Wasabi:DropDownList>` are exactly the surface `wasabi.edit.background` names, so promoting the
/// list colour without splitting the role would have dragged the form widgets onto the list plate
/// with the lists — and then flipped their labels dark-on-dark, because the drop-down's legibility
/// guard judges the label against the plate it is drawn on.
final class WinampModernB113Tests: XCTestCase {

    /// Itemskin's own declarations, which are the report.
    private static let itemskinColours = """
    <color id="wasabi.list.text" value="80,70,0"/>
    <color id="wasabi.list.background" value="220,175,0"/>
    <color id="wasabi.edit.background" value="42,42,42"/>
    """

    // MARK: - The chain

    /// The whole defect in one assertion.
    func testTheListBackgroundOutranksTheEditBackground() throws {
        let renderer = try renderer(resources: Self.itemskinColours)
        XCTAssertEqual(channels(renderer.palette.contentBackground), [220, 175, 0],
                       "the rows land on the skin's list colour, not on its text-field colour")
        XCTAssertGreaterThan(contrast(renderer.palette.listText, renderer.palette.contentBackground),
                             3.0, "and that pairing is the readable one the author drew")
    }

    /// The form widgets keep the colour their author named for them.
    func testTheEditBackgroundStaysWithTheFormWidgets() throws {
        let renderer = try renderer(resources: Self.itemskinColours)
        XCTAssertEqual(channels(renderer.palette.editBackground), [42, 42, 42])
    }

    /// A skin that names only the edit background still gets it: the fix is a reordering, not a
    /// removal, and dropping the id would have taken the plate off every skin that names only it.
    func testASkinThatNamesOnlyTheEditBackgroundStillGetsItForContent() throws {
        let renderer = try renderer(resources: #"<color id="wasabi.edit.background" value="42,42,42"/>"#)
        XCTAssertEqual(channels(renderer.palette.contentBackground), [42, 42, 42])
    }

    /// And the new role is *derived*, not invented: a skin naming no edit colour dresses its fields
    /// in the content plate, which is what they were drawn in before the split.
    func testEditBackgroundFallsBackToTheContentPlate() throws {
        let renderer = try renderer(resources: #"<color id="wasabi.list.background" value="220,175,0"/>"#)
        XCTAssertEqual(channels(renderer.palette.editBackground), [220, 175, 0])
        XCTAssertEqual(channels(renderer.palette.editBackground),
                       channels(renderer.palette.contentBackground))
    }

    /// The chain itself, so the `RENDER_PALETTE` probe and the resolver keep reporting one order.
    func testTheContentChainLeadsWithTheListBackground() {
        XCTAssertEqual(WasabiPalette.Role.contentBackground.identifiers.first,
                       "wasabi.list.background")
        XCTAssertEqual(WasabiPalette.Role.editBackground.identifiers.first,
                       "wasabi.edit.background")
    }

    // MARK: - The plate a form widget is actually drawn on

    /// A pixel, because the split is only worth anything at the draw site. A drop-down inside a skin
    /// declaring both colours is filled with the **edit** colour; filling it with the content plate
    /// is the regression the split exists to prevent.
    func testADropDownIsFilledWithTheEditBackground() throws {
        let pixels = try render(layout: """
        <layout id="normal" w="64" h="20" default_w="64" default_h="20">
          <Wasabi:DropDownList id="picker" x="0" y="0" w="64" h="20"/>
        </layout>
        """, resources: Self.itemskinColours)
        // Left of the arrow and clear of the 1px frame, where nothing but the plate is drawn.
        XCTAssertEqual(Array(pixel(pixels, x: 4, y: 10).prefix(3)), [42, 42, 42])
    }

    // MARK: - Fixture

    private func channels(_ color: NSColor) -> [Int] {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return [] }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    /// WCAG relative contrast, the same measure B48's `minimumContrast` is expressed in.
    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            let c = channels(color).map { value -> CGFloat in
                let v = CGFloat(value) / 255
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        }
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    private func pixel(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * 64 + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }

    private func renderer(resources: String,
                          layout: String = #"<layout id="normal" w="64" h="20"/>"#) throws -> WasabiSceneRenderer {
        let xml = """
        <WasabiXML>
          <elements>
        \(resources)
          </elements>
          <container id="main">
        \(layout)
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func render(layout: String, resources: String) throws -> [UInt8] {
        let renderer = try renderer(resources: resources, layout: layout)
        var pixels = [UInt8](repeating: 0, count: 64 * 20 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 64, height: 20,
                                                  bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: context)
        }
        return pixels
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB113Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B113-\(UUID().uuidString).wal")
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
