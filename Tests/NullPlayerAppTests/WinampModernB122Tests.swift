import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B122 — the playing row of a synthesized playlist has to stay *marked*.
///
/// Reported 2026-09-04 on **Firefox** as "the playlist current playing track loses highlight when
/// the track is advanced", and only on some skins. Firefox declares no playlist window, so its
/// playlist is the container we synthesize and `drawPlaylistComponent` draws — and two of its
/// declarations collide there:
///
/// - `studio.list.item.selected` is `7,92,129`, the **same value** as its `wasabi.list.background`.
///   The selection bar paints the plate onto the plate, so nothing appears.
/// - `wasabi.list.text.current` is `37,122,159`, **1.53:1** on that plate. B48's guard rejects it
///   and walks on — to `wasabi.list.text`, the colour every *ordinary* row is drawn in. The guard
///   that made the row readable also made it anonymous.
///
/// Both halves are needed: with the bar invisible, the row colour is the only marker left, and it
/// had collapsed onto the plain one. The fix keeps the ordering policy that B48 is built on — a
/// skin that gives us anything usable is never overridden — and only acts where the skin's own
/// choice cannot be seen at all.
final class WinampModernB122Tests: XCTestCase {

    /// Firefox's own declarations, which are the report. `wasabi.list.text.selected` is included
    /// because it is the second candidate the current row tries, and on this skin it fails too
    /// (2.31:1), which is what leaves the extreme as the only answer.
    private static let firefoxColours = """
    <color id="wasabi.list.text" value="97,185,209"/>
    <color id="wasabi.list.background" value="7,92,129"/>
    <color id="wasabi.list.text.current" value="37,122,159"/>
    <color id="wasabi.list.text.selected" value="223,115,29"/>
    <color id="studio.list.item.selected" value="7,92,129"/>
    """

    /// A skin whose bar and current colour are both usable — the corpus majority, which must not move.
    private static let readableColours = """
    <color id="wasabi.list.text" value="200,200,200"/>
    <color id="wasabi.list.background" value="20,20,20"/>
    <color id="wasabi.list.text.current" value="0,220,0"/>
    <color id="studio.list.item.selected" value="0,0,180"/>
    """

    // MARK: - The bar

    /// The premise of the report: this skin's selection bar is its own list plate.
    func testTheSkinsSelectionBarIsIndistinguishableFromItsPlate() throws {
        let renderer = try renderer(resources: Self.firefoxColours)
        XCTAssertEqual(channels(renderer.palette.selectionBackground),
                       channels(renderer.palette.contentBackground),
                       "Firefox declares the two ids at the same value; the fill draws nothing")
    }

    /// So the bar that is actually filled is derived from the skin's own two ends.
    func testAnInvisibleBarIsDerivedFromTheSkinsOwnColours() throws {
        let renderer = try renderer(resources: Self.firefoxColours)
        XCTAssertGreaterThan(contrast(renderer.rowSelectionBackground,
                                      renderer.palette.contentBackground), 1.15,
                             "a selected row is visible as a row")
    }

    /// And a skin whose bar already differs keeps it, untouched. The guard is for the collision only.
    func testADistinctBarIsLeftExactlyAsTheSkinDeclaredIt() throws {
        let renderer = try renderer(resources: Self.readableColours)
        XCTAssertEqual(channels(renderer.rowSelectionBackground), [0, 0, 180])
    }

    // MARK: - The playing row

    /// The whole defect in one assertion: the playing row does not look like the rows around it.
    ///
    /// The comparison is against an **unselected** neighbour, because that is what surrounds the
    /// playing row on screen — the selection follows playback, so the playing row is normally the
    /// only selected one. Against a *selected* neighbour there is nothing left to assert on this
    /// skin: both the selection text and the current colour are unreadable on the derived bar, so
    /// both land on the same white extreme, and a selected row is then marked by the bar rather
    /// than by its text. That is the ceiling of what a palette this collapsed can express, and it
    /// is Winamp's own division of labour — the bar says "selected", the colour says "playing".
    func testThePlayingRowIsNeverTheSameColourAsAnOrdinaryRow() throws {
        let renderer = try renderer(resources: Self.firefoxColours)
        let bar = renderer.rowSelectionBackground
        let neighbour = renderer.legibleRowColor(renderer.palette.listText, selected: false)
        let current = renderer.legibleCurrentRowColor(on: bar,
                                                      plain: renderer.legibleRowColor(
                                                        renderer.palette.selectionText, selected: true))
        XCTAssertNotEqual(channels(current), channels(neighbour),
                          "the advanced-to row has a marker of its own")
        XCTAssertGreaterThanOrEqual(contrast(current, bar),
                                    WinampModernSurfaceStyle.minimumContrast,
                                    "and it can be read on the bar it is drawn over")
    }

    /// The unselected case, which is what a user sees when the selection is somewhere else. Here the
    /// row lands on the plate rather than the bar, and the plain colour is `listText`.
    func testAnUnselectedPlayingRowIsAlsoKeptApartFromItsNeighbours() throws {
        let renderer = try renderer(resources: Self.firefoxColours)
        let plate = renderer.palette.contentBackground
        let plain = renderer.legibleRowColor(renderer.palette.listText, selected: false)
        let current = renderer.legibleCurrentRowColor(on: plate, plain: plain)
        XCTAssertNotEqual(channels(current), channels(plain))
        XCTAssertGreaterThanOrEqual(contrast(current, plate),
                                    WinampModernSurfaceStyle.minimumContrast)
    }

    /// B48's ordering policy survives: a skin whose current colour is readable keeps that colour,
    /// exactly. Overriding a usable choice is the regression this guard must not become.
    func testAUsableCurrentColourIsNeverOverridden() throws {
        let renderer = try renderer(resources: Self.readableColours)
        let plain = renderer.legibleRowColor(renderer.palette.listText, selected: false)
        let current = renderer.legibleCurrentRowColor(on: renderer.palette.contentBackground,
                                                      plain: plain)
        XCTAssertEqual(channels(current), [0, 220, 0], "the skin's own current colour")
    }

    // MARK: - Fixture

    private func channels(_ color: NSColor) -> [Int] {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return [] }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    /// WCAG relative contrast, the same measure `minimumContrast` is expressed in.
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

    private func renderer(resources: String) throws -> WasabiSceneRenderer {
        let xml = """
        <WasabiXML>
          <elements>
        \(resources)
          </elements>
          <container id="main">
            <layout id="normal" w="64" h="20"/>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB122Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B122-\(UUID().uuidString).wal")
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
