import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B139 — unshading a cPro player returned it to the size its markup declares, not the size it had.
///
/// Found while measuring B138 and fixed with it: shading the player and unshading it put the window
/// at 500x500 when it had been 691x541, and the tab strip came back on its abbreviated artwork
/// (`LIB`/`PLE`/`VID` instead of `Media Library`/`Playlist`/`Video`) because the skin lays that out
/// from the width it is given.
///
/// `activateLayout` reset the canvas to `defaultSize(for:)` on every switch, and for cPro's player
/// that is `default_w="500" default_h="500"` — the *opening* size. The window it actually had came
/// from the content fit, which runs once and cannot be re-derived after a switch, so the size was
/// simply gone. Measured in the running app: `resizeWindow({500, 500}) reason=canvasSizeDidChange
/// from={{722, 698}, {691, 23}}`.
///
/// Two rules replace the reset, and both are Winamp's:
///
/// - a layout comes back to the canvas **it** was last on, so a container with three layouts
///   remembers three sizes;
/// - `linkwidth` — two layouts that name each other share a width. cPro's player declares exactly
///   that pair (`one/xml/player-normal.xml` has `linkwidth="shade"`, `player-shade.xml` has
///   `linkwidth="normal"`), which is why shading now keeps the window's width instead of snapping it
///   to 500. The height stays the entered layout's own business, so shade's `maximum_h="23"` still
///   wins.
final class WinampModernB139Tests: XCTestCase {

    // MARK: - The defect

    /// The reported round trip. A size the window was actually on — a user drag, or the content fit —
    /// survives a trip through another layout.
    func testALayoutComesBackToTheCanvasItWasLastOn() throws {
        let renderer = try makeLinkedLayoutsRenderer()
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 500, height: 500),
                       "the premise: `normal` opens on its declared default")

        _ = renderer.resize(to: CGSize(width: 691, height: 541))
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 691, height: 541))

        _ = try renderer.activateLayout(id: "shade")
        _ = try renderer.activateLayout(id: "normal")

        XCTAssertEqual(renderer.canvasSize, CGSize(width: 691, height: 541),
                       "unshading returns the window to the size it had, not to `default_w`/`default_h`")
    }

    /// Each layout keeps its own, so a third layout is not handed the player's size.
    func testEachLayoutRemembersItsOwnCanvas() throws {
        let renderer = try makeLinkedLayoutsRenderer()
        _ = renderer.resize(to: CGSize(width: 691, height: 541))

        _ = try renderer.activateLayout(id: "mini")
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 260, height: 130),
                       "`mini` links no width and has never been shown, so it opens on its own default")

        _ = renderer.resize(to: CGSize(width: 300, height: 130))
        _ = try renderer.activateLayout(id: "normal")
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 691, height: 541))
        _ = try renderer.activateLayout(id: "mini")
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 300, height: 130),
                       "and comes back to what it was resized to, not to the player's size")
    }

    // MARK: - `linkwidth`

    /// Winamp's rule for a shade pair: the width carries, the height does not.
    func testLinkwidthCarriesTheWidthIntoAShadeSeenForTheFirstTime() throws {
        let renderer = try makeLinkedLayoutsRenderer()
        _ = renderer.resize(to: CGSize(width: 691, height: 541))

        _ = try renderer.activateLayout(id: "shade")

        XCTAssertEqual(renderer.canvasSize.width, 691,
                       "`shade` declares linkwidth=\"normal\", so it takes the width it was left at")
        XCTAssertEqual(renderer.canvasSize.height, 23,
                       "and its own `maximum_h` still decides the height")
    }

    /// A layout that links nothing is unaffected — it opens on its declared size however wide the
    /// window happened to be.
    func testALayoutWithoutLinkwidthKeepsItsDeclaredWidth() throws {
        let renderer = try makeLinkedLayoutsRenderer()
        _ = renderer.resize(to: CGSize(width: 691, height: 541))

        _ = try renderer.activateLayout(id: "mini")

        XCTAssertEqual(renderer.canvasSize.width, 260)
    }

    /// The link is a *pair*: a layout naming a different one does not take the width of whatever the
    /// window happens to be leaving.
    func testLinkwidthOnlyAppliesBetweenTheTwoLayoutsThatNameEachOther() throws {
        let renderer = try makeLinkedLayoutsRenderer()
        _ = try renderer.activateLayout(id: "mini")
        _ = renderer.resize(to: CGSize(width: 400, height: 130))

        _ = try renderer.activateLayout(id: "shade")

        XCTAssertEqual(renderer.canvasSize.width, 500,
                       "`shade` links `normal`, not `mini`, so it opens on its own declared width")
    }

    // MARK: - What must not change

    /// A remembered size is still the layout's to clamp. A window left wider than a layout allows
    /// comes back inside that layout's limits rather than restoring an illegal canvas.
    func testARememberedSizeIsClampedByTheLayoutItReturnsTo() throws {
        let renderer = try makeLinkedLayoutsRenderer()
        _ = renderer.resize(to: CGSize(width: 691, height: 541))
        _ = try renderer.activateLayout(id: "shade")
        _ = try renderer.activateLayout(id: "normal")

        // The layout's own floor still wins over anything remembered.
        _ = renderer.resize(to: CGSize(width: 10, height: 10))
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 317, height: 168),
                       "`minimum_w`/`minimum_h` are unaffected by the memory")
    }

    /// A container that never leaves its opening layout behaves exactly as it did — the memory is
    /// empty until the first switch.
    func testAContainerThatNeverSwitchesIsUnchanged() throws {
        let renderer = try makeLinkedLayoutsRenderer()
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 500, height: 500))
        _ = renderer.resize(to: CGSize(width: 600, height: 450))
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 600, height: 450))
    }

    // MARK: -

    /// cPro's player layouts, reduced to the attributes the rules read.
    private func makeLinkedLayoutsRenderer() throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="317" h="168" minimum_w="317" minimum_h="168"
                    default_w="500" default_h="500" linkwidth="shade">
              <group id="content" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
            </layout>
            <layout id="shade" w="500" h="23" minimum_w="317" minimum_h="23" maximum_h="23"
                    linkwidth="normal">
              <group id="shade.content" x="0" y="0" w="0" h="23" relatw="1"/>
            </layout>
            <layout id="mini" w="260" h="130" minimum_w="120" minimum_h="60">
              <group id="mini.content" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
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
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB139Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B139-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
