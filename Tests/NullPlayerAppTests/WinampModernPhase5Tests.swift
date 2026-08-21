import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 5 — playlist, EQ, library, and component hosting.
final class WinampModernPhase5Tests: XCTestCase {
    // MARK: - Test doubles

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 200
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Song"
        var trackInfo = "Artist"
        var spectrumLevels: [Float] = [0.2, 0.6]
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

    private final class MockComponentHost: WinampModernComponentHost {
        var playlist = WinampModernPlaylistSnapshot(
            rows: (0..<8).map { WinampModernPlaylistRow(title: "Track \($0)", secondary: "",
                                                        duration: 100, isCurrent: $0 == 2) },
            currentIndex: 2, selectedIndex: -1)
        var eq = WinampModernEQSnapshot.flat
        var selected = -1, played = -1, removed = -1
        var bandGains: [Int: Float] = [:]
        var preamp: Float?
        var enabled: Bool?
        var auto: Bool?
        var preset: String?
        var librarySurface: StubLibrarySurface?
        var libraryViewRequests = 0
        var classicToggles: [WinampModernComponentKind] = []

        func playlistSnapshot() -> WinampModernPlaylistSnapshot { playlist }
        func playlistSelect(row: Int) { selected = row }
        func playlistPlay(row: Int) { played = row }
        func playlistRemove(row: Int) { removed = row }
        func equalizerSnapshot() -> WinampModernEQSnapshot { eq }
        func equalizerSetBandGainDB(_ band: Int, gainDB: Float) { bandGains[band] = gainDB }
        func equalizerSetPreampDB(_ gainDB: Float) { preamp = gainDB }
        func equalizerSetEnabled(_ enabled: Bool) { self.enabled = enabled }
        func equalizerSetAuto(_ enabled: Bool) { auto = enabled }
        func equalizerApplyPreset(named name: String) { preset = name }
        func makeLibrarySurface() -> WinampModernLibrarySurface? {
            libraryViewRequests += 1
            return librarySurface
        }
        func toggleClassicWindow(for kind: WinampModernComponentKind) { classicToggles.append(kind) }
    }

    // MARK: - 5.1 GUID → kind registry

    func testComponentRegistryMapsGuidsShortformsAndNamedHolders() {
        typealias K = WinampModernComponentKind
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "guid:{45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d}"), .playlist)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"), .library)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "0000000A-000C-0010-FF7B-01014263450C"), .visualization)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "guid:F0816D7B-FFFC-4343-80F2-E8199AA15CC3"), .video)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "guid:pl"), .playlist)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "eq"), .equalizer)
        // Phase 13.1 split the fuzzy rule out of `kind(for:)`: an engine holder's *id* may still be
        // read for its kind, but a container id or a menu parameter never is.
        XCTAssertNil(WinampModernComponentRegistry.kind(for: "centro.windowholder.library"))
        XCTAssertEqual(WinampModernComponentRegistry.kindFromHolderIdentifier("centro.windowholder.library"),
                       .library)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "@all@"), .other)
        XCTAssertNil(WinampModernComponentRegistry.kind(for: "unrelated-token"))
        XCTAssertNil(WinampModernComponentRegistry.kind(for: nil))
    }

    // MARK: - 5.2 Windowholder discovery

    func testWindowholderDiscoveryResolvesKindsAndFrames() throws {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: Self.suiSkin))
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        defer { renderer.teardown(); loaded.teardown() }

        let holders = renderer.componentHolders()
        let kinds = Set(holders.map(\.kind))
        XCTAssertTrue(kinds.contains(.playlist))
        XCTAssertTrue(kinds.contains(.library))
        XCTAssertTrue(kinds.contains(.equalizer))

        let playlist = try XCTUnwrap(holders.first { $0.kind == .playlist })
        XCTAssertEqual(playlist.frame, CGRect(x: 0, y: 20, width: 200, height: 48))
    }

    // MARK: - 5.3 / 5.9 Container topology and window mapping

    func testContainerTopologyClassifiesVisibleAndCollapsedContainers() throws {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: Self.multiContainerSkin))
        defer { loaded.teardown() }
        let infos = WinampModernContainerTopology.analyze(graph: loaded.runtime.graph)

        let main = try XCTUnwrap(infos.first { $0.id.caseInsensitiveCompare("main") == .orderedSame })
        XCTAssertTrue(main.isMainPlayer)
        XCTAssertTrue(main.isVisibleWindow)

        let collapsed = try XCTUnwrap(infos.first { $0.id.caseInsensitiveCompare("pl") == .orderedSame })
        XCTAssertFalse(collapsed.isVisibleWindow, "A 1×1 window-overrides stub is not a native window")

        let video = try XCTUnwrap(infos.first { $0.id.caseInsensitiveCompare("video") == .orderedSame })
        XCTAssertTrue(video.isVisibleWindow)

        let windows = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        XCTAssertEqual(Set(windows.map(\.id)), ["main", "video"])
        XCTAssertEqual(windows.filter { !$0.isMainPlayer }.count, 1, "One auxiliary window")
    }

    func testSuiSkinCollapsesToSingleWindow() throws {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: Self.suiSkin))
        defer { loaded.teardown() }
        let windows = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        XCTAssertEqual(windows.map(\.id), ["main"], "SUI: everything else is embedded, not a window")
    }

    // MARK: - 5.4 / 5.7 EQ adapter bridges AudioEngine (classic10)

    func testEqualizerBridgeReflectsAndMutatesAudioEngine() throws {
        let engine = AudioEngine()
        let bridge = WinampModernComponentBridge(engine: engine)

        let snapshot = bridge.equalizerSnapshot()
        XCTAssertEqual(snapshot.bandGainsDB.count, 10)
        XCTAssertEqual(snapshot.presetNames, EQPreset.allPresets.map(\.name))

        bridge.equalizerSetBandGainDB(3, gainDB: 6)
        XCTAssertEqual(engine.getEQBand(3), 6, accuracy: 0.001)
        bridge.equalizerSetPreampDB(-4)
        XCTAssertEqual(engine.getPreamp(), -4, accuracy: 0.001)
        bridge.equalizerSetEnabled(false)
        XCTAssertFalse(engine.isEQEnabled())
        bridge.equalizerSetEnabled(true)

        let preset = EQPreset.imYoung
        bridge.equalizerApplyPreset(named: preset.name)
        for (band, gain) in preset.bands.enumerated() {
            XCTAssertEqual(engine.getEQBand(band), gain, accuracy: 0.001)
        }
    }

    func testPlaylistBridgeBridgesAudioEnginePlaylist() throws {
        let engine = AudioEngine()
        let placeholder = URL(string: "about:blank")!
        engine.setPlaylistTracks((0..<4).map { Track(url: placeholder, title: "Song \($0)") })
        let bridge = WinampModernComponentBridge(engine: engine)

        let snapshot = bridge.playlistSnapshot()
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertEqual(snapshot.rows[1].title, "Song 1")

        bridge.playlistSelect(row: 2)
        XCTAssertEqual(bridge.playlistSnapshot().selectedIndex, 2)
        bridge.playlistRemove(row: 0)
        XCTAssertEqual(bridge.playlistSnapshot().rows.count, 3)
        // Out-of-range operations are safe no-ops.
        bridge.playlistPlay(row: 99)
        bridge.playlistRemove(row: -1)
        XCTAssertEqual(bridge.playlistSnapshot().rows.count, 3)
    }

    // MARK: - Phase 26 album artwork host

    func testAlbumArtworkIsNilWithoutACurrentTrack() {
        let engine = AudioEngine()
        var snapshotReads = 0
        let host = WinampModernAudioEngineHost(engine: engine) {
            snapshotReads += 1
            return (UUID(), NSImage(size: NSSize(width: 1, height: 1)))
        }

        XCTAssertNil(host.albumArtwork)
        XCTAssertEqual(snapshotReads, 0, "no track means there is no artwork snapshot to consult")
    }

    func testAlbumArtworkRejectsArtworkForAStaleTrack() throws {
        let engine = AudioEngine()
        let track = Track(url: URL(string: "about:blank")!, title: "Current")
        engine.setPlaylistTracks([track])
        engine.selectTrackForDisplay(at: 0)
        let staleArtwork = try makeArtwork(red: 255)
        let host = WinampModernAudioEngineHost(engine: engine) {
            (UUID(), staleArtwork)
        }

        XCTAssertNil(host.albumArtwork,
                     "art still loading for the previous track must never appear over the current one")
    }

    func testAlbumArtworkIsCachedPerTrackAndRecomputedAfterATrackChange() throws {
        let engine = AudioEngine()
        let tracks = [Track(url: URL(string: "about:one")!, title: "One"),
                      Track(url: URL(string: "about:two")!, title: "Two")]
        engine.setPlaylistTracks(tracks)
        let firstArtwork = try makeArtwork(red: 255)
        let secondArtwork = try makeArtwork(red: 64)
        var snapshotReads = 0
        var snapshot = (trackID: Optional(tracks[0].id), image: Optional(firstArtwork))
        let host = WinampModernAudioEngineHost(engine: engine) {
            snapshotReads += 1
            return snapshot
        }

        engine.selectTrackForDisplay(at: 0)
        XCTAssertNotNil(host.albumArtwork)
        XCTAssertNotNil(host.albumArtwork)
        XCTAssertEqual(snapshotReads, 1, "repainting one track must reuse its converted CGImage")

        snapshot = (tracks[1].id, secondArtwork)
        engine.selectTrackForDisplay(at: 1)
        XCTAssertNotNil(host.albumArtwork)
        XCTAssertEqual(snapshotReads, 2, "a new track id invalidates the per-track cache")
    }

    /// Phase 27: `AlbumArtLayer.isLoading()`. A skin polls this from a timer, so a permanent "yes"
    /// is a spinner that never stops — it is true only while a fetch is genuinely in flight for a
    /// track that has no cover yet.
    func testArtworkIsLoadingOnlyWhileAFetchIsInFlightForAnUncoveredTrack() throws {
        let engine = AudioEngine()
        var loading = true
        var snapshot: (trackID: UUID?, image: NSImage?) = (nil, nil)
        let host = WinampModernAudioEngineHost(engine: engine, artworkLoading: { loading }) { snapshot }

        XCTAssertFalse(host.isArtworkLoading, "nothing is playing, so there is nothing to load")

        let track = Track(url: URL(string: "about:blank")!, title: "Current")
        engine.setPlaylistTracks([track])
        engine.selectTrackForDisplay(at: 0)
        XCTAssertTrue(host.isArtworkLoading)

        // The cover arriving is exactly what `artworkDidLoadNotification` announces, and what drops
        // the host's per-track cache — without it the nil this track cached would outlive the fetch.
        snapshot = (track.id, try makeArtwork(red: 255))
        NotificationCenter.default.post(name: NowPlayingManager.artworkDidLoadNotification, object: nil)
        let delivered = expectation(description: "artwork cache invalidated on the main queue")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 2)
        XCTAssertFalse(host.isArtworkLoading, "the cover arrived; the wait is over")

        loading = false
        XCTAssertFalse(host.isArtworkLoading)
    }

    // MARK: - 5.5 / 5.6 Playlist hosting: hit-testing, scroll, rendering

    func testPlaylistRowHitTestingAndScroll() throws {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: Self.suiSkin))
        let host = Host()
        let mock = MockComponentHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        renderer.componentHost = mock
        defer { renderer.teardown(); loaded.teardown() }

        let holder = try XCTUnwrap(renderer.componentHolders().first { $0.kind == .playlist })
        let frame = holder.frame
        // First row is at the holder's top; rows advance by playlistRowHeight.
        let top = CGPoint(x: frame.midX, y: frame.minY + 1)
        XCTAssertEqual(renderer.playlistRow(at: top, in: frame), 0)
        let third = CGPoint(x: frame.midX, y: frame.minY + renderer.playlistRowHeight * 2 + 1)
        XCTAssertEqual(renderer.playlistRow(at: third, in: frame), 2)

        // Scrolling shifts the absolute row under the same point.
        renderer.scrollPlaylist(byRows: 3, rowCount: mock.playlist.rows.count, in: frame)
        XCTAssertEqual(renderer.playlistRow(at: top, in: frame), 3)
        // Scroll clamps at the last page.
        renderer.scrollPlaylist(byRows: 999, rowCount: mock.playlist.rows.count, in: frame)
        let maxOffset = mock.playlist.rows.count - renderer.playlistVisibleRowCount(in: frame)
        XCTAssertEqual(renderer.playlistRow(at: top, in: frame), max(0, maxOffset))
    }

    func testEmbeddedComponentsRenderWithoutError() throws {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: Self.suiSkin))
        let host = Host()
        let mock = MockComponentHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        renderer.componentHost = mock
        defer { renderer.teardown(); loaded.teardown() }

        let size = renderer.canvasSize
        let context = try XCTUnwrap(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        renderer.draw(in: context) // must exercise playlist/library/EQ holder drawing paths
        XCTAssertGreaterThan(renderer.componentHolders().count, 0)
    }

    // MARK: - 5.10 Toggle routing

    func testToggleRoutingPrefersEmbeddedComponentsThenClassicFallback() throws {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: Self.suiSkin))
        let host = Host()
        let mock = MockComponentHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        renderer.componentHost = mock
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host, componentHost: mock)
        defer { view.teardown(); loaded.teardown() }

        // Playlist is embedded in the SUI → toggling must NOT open a classic window.
        view.routeComponentToggle(.playlist)
        XCTAssertTrue(mock.classicToggles.isEmpty)

        // Video is not embedded and no separate window is provided → classic fallback.
        view.routeComponentToggle(.video)
        XCTAssertEqual(mock.classicToggles, [.video])

        // When a separate skin window is offered, it wins over the classic fallback.
        var separateToggles: [WinampModernComponentKind] = []
        view.componentWindowToggleRequested = { kind in separateToggles.append(kind); return true }
        view.routeComponentToggle(.video)
        XCTAssertEqual(separateToggles, [.video])
        XCTAssertEqual(mock.classicToggles, [.video], "No new classic fallback when a skin window handled it")
    }

    // MARK: - 5.8 / 5.11 Library subview hosting + teardown

    func testLibrarySubviewIsEmbeddedAndReleasedOnTeardown() throws {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: Self.suiSkin))
        let host = Host()
        let mock = MockComponentHost()
        let surface = StubLibrarySurface()
        mock.librarySurface = surface
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        renderer.componentHost = mock
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host, componentHost: mock)

        view.setFrameSize(renderer.canvasSize)
        // Phase 13.8: hosted surfaces are reconciled from `layout()`, never from `draw` — creating
        // and adding a subview inside a draw cycle is a re-entrant hierarchy mutation.
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.subviews.contains(surface.view), "Library holder hosts the live surface")
        XCTAssertGreaterThanOrEqual(mock.libraryViewRequests, 1)
        XCTAssertEqual(surface.scaleUpdates, 1, "the surface is told the skin's UI Size on creation")
        XCTAssertEqual(surface.paletteUpdates, 1)

        view.teardown()
        XCTAssertTrue(surface.isTornDown, "teardown reaches the surface, not just its view")
        XCTAssertFalse(view.subviews.contains(surface.view), "Teardown removes hosted subviews")

        loaded.teardown()
    }

    /// A library surface that records what it was told, with no live browser behind it.
    private final class StubLibrarySurface: WinampModernLibrarySurface {
        let view = NSView(frame: .zero)
        var browseModeRawValue = 0
        var reloads = 0
        var linkSheets = 0
        var paletteUpdates = 0
        var scaleUpdates = 0
        private(set) var isTornDown = false

        func reloadData() { reloads += 1 }
        func showLinkSheet() { linkSheets += 1 }
        func applyPalette(_ palette: WasabiPalette) { paletteUpdates += 1 }
        func applySkinScale(_ scale: CGFloat) { scaleUpdates += 1 }
        func prepareForUITeardown() {
            isTornDown = true
            view.removeFromSuperview()
        }
        func unmountFromHolder() { view.removeFromSuperview() }
    }

    // MARK: - Opt-in user-supplied fixtures

    /// Opt-in acceptance on a user-supplied self-contained skin: it loads, classifies its container
    /// topology (always at least the main window), and discovers any embedded component holders. The
    /// cPro-Bento + external-engine path is exercised by Phase 6's importer once it lands.
    func testLocalComponentHostingWhenFixtureSupplied() throws {
        guard let path = ProcessInfo.processInfo.environment["WINAMP_MODERN_WAL"] else {
            throw XCTSkip("Set WINAMP_MODERN_WAL to a user-supplied Winamp Modern .wal fixture.")
        }
        // Engine-dependent skins (e.g. cPro-Bento) also work here when WINAMP_MODERN_ENGINE points at
        // a ClassicPro engine source; it is imported into a temporary store and mounted by the loader.
        var engineStore: ClassicProEngineStore? = .shared
        if let enginePath = ProcessInfo.processInfo.environment["WINAMP_MODERN_ENGINE"] {
            let store = ClassicProEngineStore(rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("Phase5Engine-\(UUID().uuidString)", isDirectory: true))
            addTeardownBlock { try? FileManager.default.removeItem(at: store.rootDirectory) }
            _ = try ClassicProEngineImporter(store: store).importEngine(from: URL(fileURLWithPath: enginePath))
            engineStore = store
        }
        let loaded = try WinampModernSkinLoader(engineStore: engineStore).load(from: URL(fileURLWithPath: path))
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        defer { renderer.teardown(); loaded.teardown() }
        let windows = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        XCTAssertEqual(windows.filter(\.isMainPlayer).count, 1, "Exactly one main player window")
        // Every discovered holder resolves to a typed kind (nothing escapes the registry).
        for holder in renderer.componentHolders() {
            XCTAssertTrue(WinampModernComponentKind.allCases.contains(holder.kind))
        }
    }

    // MARK: - Fixtures

    private static let suiSkin = """
    <WasabiXML>
      <elements><bitmap id="bg" file="sheet.png" x="0" y="0" w="8" h="8"/></elements>
      <container id="main">
        <layout id="normal" w="200" h="116">
          <windowholder id="plholder" hold="guid:{45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d}" x="0" y="20" w="200" h="48"/>
          <windowholder id="libraryholder" hold="guid:{6b0edf80-c9a5-11d3-9f26-00c04f39ffc6}" x="0" y="0" w="200" h="10"/>
          <windowholder id="eqholder" hold="guid:eq" x="0" y="10" w="200" h="10"/>
        </layout>
      </container>
    </WasabiXML>
    """

    private static let multiContainerSkin = """
    <WasabiXML>
      <container id="main"><layout id="normal" w="300" h="200"/></container>
      <container id="pl"><layout id="normal" w="1" h="1"/></container>
      <container id="video"><layout id="normal" w="200" h="150"/></container>
    </WasabiXML>
    """

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase5Tests-\(UUID().uuidString)", isDirectory: true)
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
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func makeArtwork(red: UInt8) throws -> NSImage {
        var pixel = [red, UInt8(0), UInt8(0), UInt8(255)]
        let image = try pixel.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                                  bitsPerComponent: 8, bytesPerRow: 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return NSImage(cgImage: image, size: NSSize(width: 1, height: 1))
    }
}
