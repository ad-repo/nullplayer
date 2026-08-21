import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 49 (B26) — a container whose layouts are none of them named `normal`.
///
/// `WasabiSceneRenderer.init` used to accept the layout called `normal`, *or* the sole layout when a
/// container declared exactly one. LOBE's `Color Themes` container declares six (`about1`…`about6`)
/// and none of them is `normal`, so the initializer threw and the host answered with a bare
/// `continue`: the skin's whole About / Colour Themes window — its 43-theme picker included — was
/// unreachable by every route, and nothing said so.
///
/// Winamp's rule is the container's **first declared** layout, which the "exactly one layout" case
/// was already reaching for. `WinampModernContainerTopology` has always measured by that rule, so
/// this also makes the geometry the topology reports and the scene the renderer draws the same
/// window.
final class WinampModernPhase49Tests: XCTestCase {
    func testNormalWinsWhereverItIsDeclared() throws {
        let container = try makeContainer(layouts: [("about1", 100, 40), ("normal", 200, 60)])
        XCTAssertEqual(WasabiSceneRenderer.primaryLayout(of: container)?.xmlID, "normal")
    }

    func testTheFirstDeclaredLayoutIsTakenWhenNoneIsNormal() throws {
        let container = try makeContainer(layouts: [("about1", 100, 40), ("about2", 200, 60)])
        XCTAssertEqual(WasabiSceneRenderer.primaryLayout(of: container)?.xmlID, "about1")
    }

    func testAContainerWithNoLayoutAtAllStillHasNone() throws {
        let container = try makeContainer(layouts: [])
        XCTAssertNil(WasabiSceneRenderer.primaryLayout(of: container))
    }

    /// The defect as the user met it: the window opens, and it opens at the first layout's size.
    func testTheRendererOpensSuchAContainerAtItsFirstLayout() throws {
        let loaded = try makeSkin(layouts: [("about1", 100, 40), ("about2", 200, 60)])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "themes", clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        XCTAssertEqual(renderer.activeLayoutID, "about1")
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 100, height: 40))
        XCTAssertEqual(renderer.availableLayoutIDs, ["about1", "about2"])
    }

    /// The topology measures the same window the renderer draws — the two picked by different rules
    /// before, which is how a dropped container still reported a size to the Skin Windows menu.
    func testTopologyAndRendererAgreeOnTheWindow() throws {
        let loaded = try makeSkin(layouts: [("about1", 100, 40), ("about2", 200, 60)])
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "themes", clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let info = try XCTUnwrap(WinampModernContainerTopology
            .windowContainers(graph: loaded.runtime.graph)
            .first { $0.id.caseInsensitiveCompare("themes") == .orderedSame })
        XCTAssertEqual(info.defaultSize, renderer.canvasSize)
    }

    /// Reaching a container is not the same as offering it: the standard library's `Component`
    /// shell (`name=":componenttitle"`, three skins) became openable with the layout fallback, and a
    /// string-table reference is not a name to put in a menu.
    func testAStringTableNameIsNotOfferedInTheWindowMenu() throws {
        let loaded = try makeSkin(layouts: [("about1", 100, 40)], themesName: ":componenttitle")
        let info = try XCTUnwrap(WinampModernContainerTopology
            .windowContainers(graph: loaded.runtime.graph)
            .first { $0.id.caseInsensitiveCompare("themes") == .orderedSame })
        XCTAssertFalse(WinampModernContainerTopology.isListedInWindowMenu(info))
    }

    func testAPlainNameStillIs() throws {
        let loaded = try makeSkin(layouts: [("about1", 100, 40)])
        let info = try XCTUnwrap(WinampModernContainerTopology
            .windowContainers(graph: loaded.runtime.graph)
            .first { $0.id.caseInsensitiveCompare("themes") == .orderedSame })
        XCTAssertTrue(WinampModernContainerTopology.isListedInWindowMenu(info))
    }

    // MARK: - Fixture

    private func makeContainer(layouts: [(String, Int, Int)]) throws -> WasabiObject {
        let loaded = try makeSkin(layouts: layouts)
        return try XCTUnwrap(loaded.runtime.graph.roots.first {
            $0.typeName.caseInsensitiveCompare("container") == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare("themes") == .orderedSame
        })
    }

    private func makeSkin(layouts: [(String, Int, Int)],
                          themesName: String = "Color Themes") throws -> WinampModernLoadedSkin {
        let body = layouts.map { id, w, h in
            "    <layout id=\"\(id)\" w=\"\(w)\" h=\"\(h)\"/>"
        }.joined(separator: "\n")
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="300" h="60"/>
          </container>
          <container id="themes" name="\(themesName)">
        \(body)
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase49Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase49-\(UUID().uuidString).wal")
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
