import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 39 (backlog B5) — the `VIS_*` / `PE_*` / `VID_*` / `CB_*` host actions.
///
/// The corpus scan (17 skins, 2026-08-20) puts the demand at **108 declarations in 11 skins**:
/// `VIS_*` 27 in 5, `PE_*` 39 in 7, `VID_*` 28 in 5, `CB_*` 14 in 4. Every one of them is a visible
/// toolbar button, and every one of them reached the action switch's `default:` and stopped.
///
/// What is tested here is what can be tested without a menu-tracking run loop: the decoding of the
/// four families (including the three we answer with a recorded nothing), the visualization mode the
/// menu and the arrows write, and the set arithmetic behind Select All / Invert / Crop / Remove.
/// Presenting an `NSMenu` runs AppKit's own tracking loop, which a headless test cannot enter — the
/// same boundary Phase 36 drew around `TRACKMENU`.
final class WinampModernPhase39Tests: XCTestCase {
    // MARK: - Decoding the four families

    func testEveryDeclaredActionInTheCorpusDecodes() {
        typealias Action = WinampModernHostAction
        XCTAssertEqual(Action(action: "VIS_MENU"), .visualizationMenu)
        XCTAssertEqual(Action(action: "VIS_NEXT"), .visualizationNext)
        XCTAssertEqual(Action(action: "VIS_PREV"), .visualizationPrevious)
        XCTAssertEqual(Action(action: "VIS_CFG"), .visualizationConfig)
        XCTAssertEqual(Action(action: "VIS_FS"), .visualizationFullscreen)
        XCTAssertEqual(Action(action: "PE_ADD"), .playlistAdd)
        XCTAssertEqual(Action(action: "PE_REM"), .playlistRemove)
        XCTAssertEqual(Action(action: "PE_SEL"), .playlistSelect)
        XCTAssertEqual(Action(action: "PE_MISC"), .playlistMisc)
        XCTAssertEqual(Action(action: "PE_LIST"), .playlistList)
        XCTAssertEqual(Action(action: "VID_FS"), .videoFullscreen)
        XCTAssertEqual(Action(action: "VID_MISC"), .videoMenu)
    }

    /// Skins spell these three ways in the same file — `VIS_Prev`, `vis_prev`, `VIS_PREV` — and
    /// Winamp Modern's own markup carries the whitespace.
    func testDecodingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(WinampModernHostAction(action: "vis_prev"), .visualizationPrevious)
        XCTAssertEqual(WinampModernHostAction(action: " VID_Misc "), .videoMenu)
        XCTAssertEqual(WinampModernHostAction(action: "PE_Add"), .playlistAdd)
    }

    /// Winamp's "playlist of playlists" is its saved-playlist manager, which is the list `PE_LIST`
    /// already offers.
    func testListOfListsIsTheSameMenuAsList() {
        XCTAssertEqual(WinampModernHostAction(action: "PE_LISTOFLISTS"), .playlistList)
    }

    /// The ones we answer with a recorded nothing, so the demand is visible in a report instead of
    /// looking like a dead button of unknown cause. `VID_1X` / `VID_2X` left this list in B20: a
    /// skin-hosted picture has a native size to scale from, which is the thing they lacked. The four
    /// `CB_*` left it in B34, when the thinger gained an icon set to scroll.
    func testTheDeliberatelyInertActionsCarryTheirReason() {
        for name in ["VID_TV", "ML_SENDTO"] {
            guard case .inert(let action, let reason)? = WinampModernHostAction(action: name) else {
                return XCTFail("\(name) should decode as inert")
            }
            XCTAssertEqual(action, name)
            XCTAssertFalse(reason.isEmpty, "\(name) must say why it does nothing")
        }
    }

    /// The thinger's four scroll commands: one icon, or a whole screenful for the `*PAGE` pair.
    func testTheComponentBucketActionsScrollTheStrip() {
        XCTAssertEqual(WinampModernHostAction(action: "CB_NEXT"),
                       .componentBucketScroll(delta: 1, page: false))
        XCTAssertEqual(WinampModernHostAction(action: "CB_PREV"),
                       .componentBucketScroll(delta: -1, page: false))
        XCTAssertEqual(WinampModernHostAction(action: "CB_NEXTPAGE"),
                       .componentBucketScroll(delta: 1, page: true))
        XCTAssertEqual(WinampModernHostAction(action: "cb_prevpage"),
                       .componentBucketScroll(delta: -1, page: true))
    }

    func testAnUnrelatedActionIsNotClaimed() {
        XCTAssertNil(WinampModernHostAction(action: "PLAY"))
        XCTAssertNil(WinampModernHostAction(action: "TOGGLE"))
        XCTAssertNil(WinampModernHostAction(action: "PE_"))
        XCTAssertNil(WinampModernHostAction(action: ""))
    }

    // MARK: - The visualization mode

    /// The pairing the renderer draws from: `1` analyzer, `2` oscilloscope, `0`/`3` off, undeclared
    /// analyzer. MMD3 ships `mode="3"` (its own animated display) and must read back as off.
    func testModeDecodesTheSameWayTheRendererDrawsIt() {
        XCTAssertEqual(WasabiVisualizationMode(attribute: "1"), .analyzer)
        XCTAssertEqual(WasabiVisualizationMode(attribute: "2"), .oscilloscope)
        XCTAssertEqual(WasabiVisualizationMode(attribute: "0"), .off)
        XCTAssertEqual(WasabiVisualizationMode(attribute: "3"), .off)
        XCTAssertEqual(WasabiVisualizationMode(attribute: nil), .analyzer)
        XCTAssertEqual(WasabiVisualizationMode(attribute: "banana"), .analyzer)
    }

    func testSteppingWrapsInBothDirections() {
        XCTAssertEqual(WasabiVisualizationMode.analyzer.stepped(by: 1), .oscilloscope)
        XCTAssertEqual(WasabiVisualizationMode.oscilloscope.stepped(by: 1), .off)
        XCTAssertEqual(WasabiVisualizationMode.off.stepped(by: 1), .analyzer)
        XCTAssertEqual(WasabiVisualizationMode.analyzer.stepped(by: -1), .off)
        XCTAssertEqual(WasabiVisualizationMode.off.stepped(by: -1), .oscilloscope)
    }

    func testWritingAModeRoundTripsThroughTheAttribute() {
        for mode in WasabiVisualizationMode.allCases {
            XCTAssertEqual(WasabiVisualizationMode(attribute: mode.attributeValue), mode)
        }
    }

    // MARK: - The `<vis>` boxes, through the renderer

    /// `VIS_NEXT` writes the same attribute a skin's own `setMode` writes, and writes it to **every**
    /// `<vis>` in the graph: a skin draws its visualization in several layouts, and stepping the mode
    /// in one must not leave the others showing the mode the user just stepped away from.
    func testSteppingTheModeWritesEveryVisBoxInTheGraph() throws {
        let scene = try makeScene()
        XCTAssertEqual(scene.renderer.visualizationObjects().count, 2)
        XCTAssertEqual(scene.renderer.visualizationMode, .analyzer)

        scene.click(id: "next")
        XCTAssertEqual(scene.renderer.visualizationMode, .oscilloscope)
        for object in scene.renderer.visualizationObjects() {
            XCTAssertEqual(object.attributes["mode"], "2")
        }

        scene.click(id: "prev")
        XCTAssertEqual(scene.renderer.visualizationMode, .analyzer)
    }

    func testABandwidthWriteReportsWhetherAnythingMoved() throws {
        let scene = try makeScene()
        XCTAssertFalse(scene.renderer.analyzerBandwidthIsThin)
        XCTAssertTrue(scene.renderer.setVisualizationAttribute("bandwidth", value: "thin"))
        XCTAssertTrue(scene.renderer.analyzerBandwidthIsThin)
        XCTAssertFalse(scene.renderer.setVisualizationAttribute("bandwidth", value: "thin"),
                       "an unchanged attribute must not claim a repaint")
    }

    /// A skin with no `<vis>` of its own (Defix, whose VIS buttons are a toolbar over the host's
    /// visualization window) answers `nil` rather than inventing a mode.
    func testASkinWithoutAVisBoxHasNoMode() throws {
        let scene = try makeScene(includeVis: false)
        XCTAssertTrue(scene.renderer.visualizationObjects().isEmpty)
        XCTAssertNil(scene.renderer.visualizationMode)
        scene.click(id: "next")   // must not crash, must change nothing
        XCTAssertNil(scene.renderer.visualizationMode)
    }

    // MARK: - The selection arithmetic behind PE_SEL / PE_REM

    func testSelectAllAndInvertAreComplements() {
        XCTAssertEqual(WinampModernPlaylistSelection.all(count: 4), [0, 1, 2, 3])
        XCTAssertEqual(WinampModernPlaylistSelection.all(count: 0), [])
        XCTAssertEqual(WinampModernPlaylistSelection.inverted([1, 3], count: 4), [0, 2])
        XCTAssertEqual(WinampModernPlaylistSelection.inverted([], count: 3), [0, 1, 2])
    }

    /// Cropping to *nothing* would empty the queue, which is Remove All under another name — so an
    /// empty selection crops nothing at all.
    func testCropKeepsTheSelectionAndRefusesAnEmptyOne() {
        XCTAssertEqual(WinampModernPlaylistSelection.cropVictims(keeping: [1], count: 4), [0, 2, 3])
        XCTAssertEqual(WinampModernPlaylistSelection.cropVictims(keeping: [], count: 4), [])
    }

    func testRemovalRunsFromTheHighestRowDown() {
        XCTAssertEqual(WinampModernPlaylistSelection.removalOrder([0, 3, 1]), [3, 1, 0])
    }

    func testTheSelectionLandsOnWhateverTookTheRemovedRowsPlace() {
        XCTAssertEqual(WinampModernPlaylistSelection.selectionAfterRemoval(of: [1], count: 4), 1)
        XCTAssertEqual(WinampModernPlaylistSelection.selectionAfterRemoval(of: [3], count: 4), 2,
                       "removing the last row leaves the selection on the new last row")
        XCTAssertEqual(WinampModernPlaylistSelection.selectionAfterRemoval(of: [0, 1, 2], count: 3), -1,
                       "an emptied queue has no selection")
    }

    // MARK: - The snapshot's selection

    /// The anchor is still the anchor: a click, the Delete key and a skin's own readouts all mean the
    /// single row by "the selection", while `PE_SEL` works on the set.
    func testSnapshotSelectionDefaultsToTheAnchor() {
        let rows = (0..<3).map { WinampModernPlaylistRow(title: "\($0)", secondary: "",
                                                         duration: 0, isCurrent: false) }
        let anchored = WinampModernPlaylistSnapshot(rows: rows, currentIndex: 0, selectedIndex: 1)
        XCTAssertEqual(anchored.selectedRows, [1])
        XCTAssertTrue(anchored.isSelected(1))
        XCTAssertFalse(anchored.isSelected(2))

        let none = WinampModernPlaylistSnapshot(rows: rows, currentIndex: 0, selectedIndex: -1)
        XCTAssertTrue(none.selectedRows.isEmpty)

        let many = WinampModernPlaylistSnapshot(rows: rows, currentIndex: 0, selectedIndex: 0,
                                                selectedRows: [0, 2])
        XCTAssertTrue(many.isSelected(2))
    }

    /// A host with no selection model of its own still answers both new calls — the default removes
    /// row by row, highest first, so nothing shifts under it.
    func testTheDefaultHostImplementationsComposeTheOldOnes() {
        let host = SingleSelectionHost()
        host.playlistRemoveRows([0, 2, 1])
        XCTAssertEqual(host.removedRows, [2, 1, 0])
        host.playlistSetSelection([3, 5])
        XCTAssertEqual(host.selectedRow, 3)
    }

    private final class SingleSelectionHost: WinampModernComponentHost {
        var removedRows: [Int] = []
        var selectedRow = -1

        func playlistSnapshot() -> WinampModernPlaylistSnapshot { .empty }
        func playlistSelect(row: Int) { selectedRow = row }
        func playlistPlay(row: Int) {}
        func playlistRemove(row: Int) { removedRows.append(row) }
        func equalizerSnapshot() -> WinampModernEQSnapshot { .flat }
        func equalizerSetBandGainDB(_ band: Int, gainDB: Float) {}
        func equalizerSetPreampDB(_ gainDB: Float) {}
        func equalizerSetEnabled(_ enabled: Bool) {}
        func equalizerSetAuto(_ enabled: Bool) {}
        func equalizerApplyPreset(named name: String) {}
        func toggleClassicWindow(for kind: WinampModernComponentKind) {}
    }

    // MARK: - Fixture

    private struct Scene {
        let loaded: WinampModernLoadedSkin
        let renderer: WasabiSceneRenderer
        let view: WinampModernMainView

        /// Click the button with this id, through the view's own mouse path.
        func click(id: String) {
            guard let object = loaded.runtime.graph.objects(xmlID: id).first,
                  let frame = renderer.frame(of: object) else { return XCTFail("no \(id) on screen") }
            let point = NSPoint(x: frame.midX, y: renderer.canvasSize.height - frame.midY)
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point,
                                                modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point,
                                              modifierFlags: [], timestamp: 0, windowNumber: 0,
                                              context: nil, eventNumber: 2, clickCount: 1, pressure: 0)
            else { return }
            view.mouseDown(with: down)
            view.mouseUp(with: up)
        }
    }

    private func makeScene(includeVis: Bool = true) throws -> Scene {
        let vis = includeVis
            ? """
              <vis id="vis.normal" x="0" y="0" w="60" h="20"/>
              <vis id="vis.shade" x="60" y="0" w="60" h="20"/>
              """
            : ""
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="120" h="60">
              \(vis)
              <button id="prev" action="VIS_PREV" x="0" y="30" w="20" h="20"/>
              <button id="next" action="VIS_NEXT" x="20" y="30" w="20" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host)
        addTeardownBlock { view.teardown() }
        return Scene(loaded: loaded, renderer: renderer, view: view)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase39Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase39-\(UUID().uuidString).wal")
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
