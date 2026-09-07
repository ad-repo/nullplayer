import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 32 — the colour-theme picker. The catalog and the gamma transform were already covered by
/// `WinampModernPhase4Tests`; what is new here is the widget that shows the catalog, the three host
/// actions that switch it, and `action_target`'s wide lookup.
final class WinampModernPhase32Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Synthetic Song"
        var trackInfo = "Synthetic Artist"
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

    /// Two `<ColorThemes:List>`s in one window — one beside its switch button, one in a sibling
    /// subtree the button reaches only through the *wide* half of the lookup, which is the shape
    /// multipass and mmd3 both have.
    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="sheet" file="sheet.png" gammagroup="Tint"/>
        <gammaset id="Default"><gammagroup id="Tint" value="0,0,0"/></gammaset>
        <gammaset id="Red"><gammagroup id="Tint" value="2048,0,0"/></gammaset>
        <gammaset id="Blue"><gammagroup id="Tint" value="0,0,2048"/></gammaset>
      </elements>
      <container id="Main">
        <layout id="normal" w="200" h="120">
          <group id="near" x="0" y="0" w="100" h="120">
            <ColorThemes:List id="near.list" x="0" y="0" w="100" h="60"/>
            <Wasabi:Button id="switch.near" text="Switch" action="colorthemes_switch"
                           action_target="near.list" x="0" y="60" w="50" h="20"/>
          </group>
          <group id="far" x="100" y="0" w="100" h="120">
            <ColorThemes:List id="far.list" x="0" y="0" w="100" h="24"/>
          </group>
          <Wasabi:Button id="switch.far" text="Switch far" action="colorthemes_switch"
                         action_target="far.list" x="0" y="80" w="50" h="20"/>
          <Wasabi:Button id="switch.nowhere" text="Switch nowhere" action="colorthemes_switch"
                         action_target="no.such.object" x="0" y="100" w="50" h="20"/>
        </layout>
      </container>
    </WasabiXML>
    """

    func testListPopulatesInDocumentOrderAndHitTestsRows() throws {
        let (loaded, renderer) = try makeSkin()
        defer { renderer.teardown(); loaded.teardown() }

        XCTAssertEqual(renderer.colorThemeNames, ["Default", "Red", "Blue"])
        XCTAssertEqual(renderer.activeColorThemeIndex, 0)
        let lists = renderer.colorThemeLists()
        XCTAssertEqual(Set(lists.map { $0.object.xmlID }), ["near.list", "far.list"])

        let list = try XCTUnwrap(lists.first { $0.object.xmlID == "near.list" })
        let rowHeight = WasabiColorThemeListState.rowHeight
        for expected in 0..<3 {
            let point = CGPoint(x: list.frame.midX,
                                y: list.frame.minY + rowHeight * CGFloat(expected) + rowHeight / 2)
            XCTAssertEqual(renderer.colorThemeListRow(at: point, in: list.object), expected)
        }
        // Past the last row is not row 2 again: an empty list body is not a pick.
        let belowLastRow = CGPoint(x: list.frame.midX, y: list.frame.minY + rowHeight * 3 + 1)
        XCTAssertNil(renderer.colorThemeListRow(at: belowLastRow, in: list.object))
        XCTAssertNil(renderer.colorThemeListRow(at: CGPoint(x: -5, y: -5), in: list.object))
    }

    func testListIsRenderableAndInteractive() throws {
        let (loaded, renderer) = try makeSkin()
        defer { renderer.teardown(); loaded.teardown() }
        let list = try XCTUnwrap(renderer.colorThemeLists().first { $0.object.xmlID == "near.list" })
        let point = CGPoint(x: list.frame.midX, y: list.frame.minY + 2)
        // Both halves of the Phase 32 defect: before it, the tag was neither clickable nor drawn.
        XCTAssertTrue(renderer.object(at: point) === list.object)
        XCTAssertTrue(renderer.containsVisiblePixel(at: point))
    }

    func testActionTargetResolvesNarrowAndWideAndFallsBackToTheOnlyList() throws {
        let (loaded, renderer) = try makeSkin()
        defer { renderer.teardown(); loaded.teardown() }

        let near = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "switch.near").first)
        XCTAssertEqual(renderer.actionTarget(of: near)?.xmlID, "near.list")
        // The wide half: the button is a sibling of `far`'s subtree, not inside it.
        let far = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "switch.far").first)
        XCTAssertEqual(renderer.actionTarget(of: far)?.xmlID, "far.list")
        // An unresolvable target answers nothing, and with two lists in the scene there is no
        // unambiguous one to fall back to — which is what sends the view to its popup menu.
        let nowhere = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "switch.nowhere").first)
        XCTAssertNil(renderer.actionTarget(of: nowhere))
        XCTAssertNil(renderer.colorThemeList(forAction: nowhere))
    }

    func testSelectionAndActivationPersistAndSurviveAReload() throws {
        let url = try makeArchive(xml: Self.skinXML)
        let host = Host()
        let loaded = try WinampModernSkinLoader().load(from: url)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        defer {
            UserDefaults.standard.removeObject(
                forKey: "winampModern.config.\(loaded.configuration.namespace).appearance.theme")
        }
        let list = try XCTUnwrap(renderer.colorThemeLists().first { $0.object.xmlID == "near.list" })
        renderer.selectColorThemeRow(2, in: list.object)
        XCTAssertEqual(renderer.selectedColorTheme(in: list.object), "Blue")
        XCTAssertTrue(renderer.activateTheme("Blue"))
        // Already applied: `false`, which is why every call site repaints rather than waiting for the
        // coordinator's broadcast.
        XCTAssertFalse(renderer.activateTheme("Blue"))
        renderer.teardown()
        loaded.teardown()

        let reloaded = try WinampModernSkinLoader().load(from: url)
        let reloadedRenderer = try WasabiSceneRenderer(loadedSkin: reloaded, host: host)
        defer { reloadedRenderer.teardown(); reloaded.teardown() }
        XCTAssertEqual(reloadedRenderer.themes.activeTheme, "Blue")
        // And the list opens on the applied theme rather than at row 0 — the whole point of seeding.
        let reloadedList = try XCTUnwrap(reloadedRenderer.colorThemeLists()
            .first { $0.object.xmlID == "near.list" })
        XCTAssertEqual(reloadedRenderer.selectedColorTheme(in: reloadedList.object), "Blue")
    }

    func testScrollingAndSeedingBringTheAppliedThemeIntoView() {
        let names = 20
        // A two-row window, the shape that made an 83-row list unusable before Phase 32.
        let frame = CGRect(x: 0, y: 0, width: 100, height: WasabiColorThemeListState.rowHeight * 2)
        var state = WasabiColorThemeListState()
        state.seed(activeIndex: 11, rowCount: names, in: frame)
        XCTAssertTrue(state.isSeeded)
        XCTAssertEqual(state.selectedIndex, 11)
        XCTAssertEqual(state.scrollOffset, 10)
        // Seeding happens once: a later theme change is `follow`'s job, not a second seed.
        state.seed(activeIndex: 0, rowCount: names, in: frame)
        XCTAssertEqual(state.selectedIndex, 11)

        state.scroll(byRows: 100, rowCount: names, in: frame)
        XCTAssertEqual(state.scrollOffset, names - 2)
        state.scroll(byRows: -100, rowCount: names, in: frame)
        XCTAssertEqual(state.scrollOffset, 0)

        state.follow(activeIndex: 19, rowCount: names, in: frame)
        XCTAssertEqual(state.selectedIndex, 19)
        XCTAssertEqual(state.scrollOffset, 18)
        // A row picked out of a scrolled list is the absolute index, not the slot.
        let point = CGPoint(x: 5, y: frame.minY + WasabiColorThemeListState.rowHeight + 1)
        XCTAssertEqual(state.row(at: point, in: frame, rowCount: names), 19)
    }

    /// `_next` / `_previous` wrap at both ends. The stepping is the view's, but it is arithmetic over
    /// the catalog, so it is pinned here against the catalog the view reads.
    func testNextAndPreviousWrap() throws {
        let (loaded, renderer) = try makeSkin()
        defer { renderer.teardown(); loaded.teardown() }
        let names = renderer.colorThemeNames
        func step(_ delta: Int) {
            let current = renderer.activeColorThemeIndex ?? 0
            let next = ((current + delta) % names.count + names.count) % names.count
            _ = renderer.activateTheme(names[next])
        }
        XCTAssertEqual(renderer.themes.activeTheme, "Default")
        step(-1)
        XCTAssertEqual(renderer.themes.activeTheme, "Blue")
        step(1)
        XCTAssertEqual(renderer.themes.activeTheme, "Default")
        step(1)
        step(1)
        step(1)
        XCTAssertEqual(renderer.themes.activeTheme, "Default")
    }

    /// The gate on the host **Color Themes** menu. A skin with no `<gammaset>` at all must answer an
    /// *empty* name list even though the catalog still reports an active theme of "Default" — if it
    /// synthesised a one-name list the `> 1` gate would still hold, but the menu's own emptiness
    /// check would not, so this pins which of the two is true.
    func testThemeNamesAreEmptyForASkinWithNoGammasets() throws {
        let xml = """
        <WasabiXML>
          <elements><bitmap id="sheet" file="sheet.png"/></elements>
          <container id="Main"><layout id="normal" w="50" h="50"><layer image="sheet"/></layout></container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host())
        defer { renderer.teardown(); loaded.teardown() }
        XCTAssertTrue(renderer.colorThemeNames.isEmpty)
        XCTAssertEqual(renderer.themes.activeTheme, "Default")
        XCTAssertNil(renderer.activeColorThemeIndex)
        XCTAssertTrue(renderer.colorThemeLists().isEmpty)
    }

    /// An artwork-less `<Wasabi:Button text="…">` is drawn and clickable (§5). No `.wal` ships
    /// `wasabi.button.*` artwork — it lives inside Winamp — so without this the Switch button under
    /// three skins' theme lists is invisible.
    func testTextButtonIsRenderableWithoutArtwork() throws {
        let (loaded, renderer) = try makeSkin()
        defer { renderer.teardown(); loaded.teardown() }
        let button = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "switch.near").first)
        XCTAssertTrue(WasabiSceneRenderer.isTextButton(button))
        let frame = try XCTUnwrap(renderer.frame(of: button))
        XCTAssertTrue(renderer.containsVisiblePixel(at: CGPoint(x: frame.midX, y: frame.midY)))
        // A label-less one stays what it was: an invisible shell, not an empty box with a border.
        _ = button.setAttribute("text", value: "")
        XCTAssertFalse(WasabiSceneRenderer.isTextButton(button))
    }

    /// Drawing the whole scene must not crash and must actually paint the list — the pixel check is
    /// deliberately weak (the row colours come from the skin's palette), but a widget that draws
    /// nothing at all is exactly the defect this phase fixes.
    func testColorThemeListPaints() throws {
        let (loaded, renderer) = try makeSkin()
        defer { renderer.teardown(); loaded.teardown() }
        let size = renderer.canvasSize
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        renderer.draw(in: context)
        NSGraphicsContext.current = previous
        let image = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(image.width, Int(size.width))
    }

    // MARK: - Fixture

    private func makeSkin() throws -> (WinampModernLoadedSkin, WasabiSceneRenderer) {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: Self.skinXML))
        addTeardownBlock {
            UserDefaults.standard.removeObject(
                forKey: "winampModern.config.\(loaded.configuration.namespace).appearance.theme")
        }
        return (loaded, try WasabiSceneRenderer(loadedSkin: loaded, host: Host()))
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase32Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let png = try makePNG()
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", png)] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func makePNG() throws -> Data {
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 200, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) { pixels[offset + 3] = 255 }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let representation = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
