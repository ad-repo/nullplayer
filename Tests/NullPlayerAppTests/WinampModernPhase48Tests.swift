import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 48 (B20a) — the skin's own AVS/visualization window holds the host's visualization engine.
///
/// Eight of the 31 installed skins declare a container — `avs`, `avs_window`, `AVS`, `AVS_window` —
/// whose body is a `<component param="{0000000A-000C-0010-FF7B-01014263450C}">`: Winamp's
/// visualization *plugin* holder. We painted the engine-drawn spectrum analyzer into it, so a skin's
/// dedicated visualization window was a second, larger copy of the little `<vis>` box in the player.
///
/// Two decisions are tested here, because both were wrong before and neither is visible from the
/// pixels alone:
///
/// * the box is **routed** (`routedKinds`), which is what gives it any way to be opened at all — a
///   container carrying a `component=` GUID is deliberately kept out of the Skin Windows menu so a
///   routed surface cannot be reached twice, and nothing routed the visualization;
/// * a **hosted** holder is left to its engine, while an unhosted one keeps the analyzer — the
///   headless renderer has no view layer, so the fallback is what every render sweep and golden
///   image still measures.
final class WinampModernPhase48Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .playing
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
        /// Every band at full scale, so a bar covers its whole column and a painted analyzer cannot
        /// be mistaken for the black behind it.
        var spectrumLevels: [Float] = Array(repeating: 1, count: 16)

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

    private static let visGUID = "{0000000A-000C-0010-FF7B-01014263450C}"

    // MARK: - What the box draws

    func testAnUnhostedVisualizationComponentKeepsTheAnalyzer() throws {
        let (renderer, _) = try makeAVSScene()
        let pixels = try render(renderer)
        XCTAssertTrue(hasColour(pixels), "a headless render has no view layer, so the bars stay")
    }

    func testAHostedVisualizationComponentIsLeftToItsEngine() throws {
        let (renderer, holder) = try makeAVSScene()
        renderer.hostedVisualizationHolders = [holder.object.stableID]
        let pixels = try render(renderer)
        XCTAssertFalse(hasColour(pixels),
                       "bars under a live OpenGL engine are a visualization nobody can see")
        XCTAssertEqual(pixel(pixels, x: 32, y: 10), [0, 0, 0, 255],
                       "and the box is black, which is what shows before the first frame arrives")
    }

    /// The `<vis>` box and the component holder are different things — Winamp's built-in analyzer and
    /// its plugin surface — and a skin that draws both wants both.
    func testHostingTheComponentDoesNotSilenceTheSkinsOwnVisBox() throws {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="64" h="20">
              <vis id="vis" x="0" y="0" w="64" h="20" colorallbands="0,0,255"/>
            </layout>
          </container>
          <container id="avs" component="\(Self.visGUID)">
            <layout id="normal" w="64" h="20">
              <component id="avs.component" param="\(Self.visGUID)" x="0" y="0" w="64" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try load(xml: xml)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "main", clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        // Every holder in the skin claimed by the view layer — the `<vis>` is not one of them.
        renderer.hostedVisualizationHolders = Set(
            loaded.runtime.graph.allObjectsUnordered.map(\.stableID))
        let pixels = try render(renderer)
        XCTAssertEqual(pixel(pixels, x: 2, y: 10), [0, 0, 255, 255],
                       "the skin's own analyzer is untouched by what fills its AVS window")
    }

    // MARK: - Routing

    func testTheVisualizationIsRoutedButNeverSynthesized() {
        XCTAssertTrue(WinampModernSurfaceInventory.routedKinds.contains(.visualization),
                      "without this there is no way to open a skin's AVS window at all")
        XCTAssertFalse(WinampModernSurfaceInventory.managedKinds.contains(.visualization),
                       "a skin that draws no AVS window is served by NullPlayer's own")
    }

    func testASkinsAVSContainerIsFoundAndRoutedToItself() throws {
        let loaded = try load(xml: skinXML(withAVSContainer: true))
        XCTAssertEqual(loaded.surfaceInventory.declaredContainers[.visualization], "avs")
        XCTAssertFalse(loaded.surfaceInventory.synthesizableKinds.contains(.visualization))

        let catalog = WinampModernSurfaceCoordinator.makeCatalog(
            loadedSkin: loaded, hostedContainerIDs: ["avs"], embeddedContainerID: nil)
        XCTAssertEqual(catalog.visualization, .declaredContainer(id: "avs"))
        XCTAssertTrue(catalog.summaryLine.contains("visualization=declared:avs"))
    }

    func testWithoutAnAVSContainerTheHostsOwnWindowTakesIt() throws {
        let loaded = try load(xml: skinXML(withAVSContainer: false))
        XCTAssertNil(loaded.surfaceInventory.declaredContainers[.visualization])
        let catalog = WinampModernSurfaceCoordinator.makeCatalog(
            loadedSkin: loaded, hostedContainerIDs: [], embeddedContainerID: nil)
        guard case .classicFallback = catalog.visualization else {
            return XCTFail("got \(catalog.visualization)")
        }
    }

    /// The coordinator moves the skin's own window when it has one, and calls the classic fallback
    /// exactly once when it does not — the same two paths every other routed surface takes.
    func testTheCoordinatorRoutesTheVisualizationLikeEveryOtherSurface() {
        var visibility: [String: Bool] = ["avs": false]
        var classicCalls: [WinampModernComponentKind] = []
        func coordinator(_ target: WinampModernSurfaceTarget) -> WinampModernSurfaceCoordinator {
            let catalog = WinampModernSurfaceCatalog(
                playlist: .classicFallback(reason: "none"),
                equalizer: .classicFallback(reason: "none"),
                library: .classicFallback(reason: "none"),
                video: .classicFallback(reason: "none"),
                visualization: target)
            return WinampModernSurfaceCoordinator(catalog: catalog, environment: .init(
                revealEmbedded: { _, _, _ in
                    XCTFail("the visualization is never embedded")
                    return false
                },
                isMainWindowVisible: { true },
                window: { _ in nil },
                setVisible: { id, visible in visibility[id] = visible },
                classicFallback: { kind, _ in classicCalls.append(kind) },
                redraw: {}))
        }

        let skinOwned = coordinator(.declaredContainer(id: "avs"))
        XCTAssertTrue(skinOwned.handles(.visualization))
        skinOwned.showSurface(.visualization)
        XCTAssertEqual(visibility["avs"], true)
        XCTAssertTrue(classicCalls.isEmpty, "a skin-owned window never falls back")

        let hostOwned = coordinator(.classicFallback(reason: "the skin declares no AVS window"))
        XCTAssertFalse(hostOwned.handles(.visualization))
        hostOwned.showSurface(.visualization)
        XCTAssertEqual(classicCalls, [.visualization])
    }

    /// The topology keeps a named AVS container menu-eligible so the host can route its standard
    /// Visualizations command to it; the reconciled catalog then removes it from the separate
    /// skin-owned block so the same window is not listed twice.
    func testTheAVSWindowIsEligibleForTheWindowsMenu() throws {
        let loaded = try load(xml: skinXML(withAVSContainer: true))
        let containers = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        let avs = try XCTUnwrap(containers.first { $0.id == "avs" })
        XCTAssertEqual(avs.kind, .visualization)
        XCTAssertTrue(WinampModernContainerTopology.isListedInWindowMenu(avs),
                      "otherwise the window has no way to be opened at all")
        XCTAssertEqual(WinampModernContainerTopology.displayName(of: avs), "Visualization")
    }

    func testEveryRoutedContainerIsExcludedFromTheSkinOwnedWindowBlock() {
        let catalog = WinampModernSurfaceCatalog(
            playlist: .declaredContainer(id: "pledit"),
            equalizer: .declaredContainer(id: "eq"),
            library: .synthesizedContainer(id: "nullplayer.library"),
            video: .declaredContainer(id: "video"),
            visualization: .declaredContainer(id: "avs"))

        XCTAssertEqual(catalog.routedContainerIDs,
                       ["pledit", "eq", "nullplayer.library", "video", "avs"])
    }

    /// And the rule it must not break: a surface that *does* have a menu item of its own stays out,
    /// or the user gets two entries reaching one window.
    func testAManagedSurfacesContainerStaysOutOfTheMenu() throws {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="64" h="20"/>
          </container>
          <container id="Pledit" name="Playlist Editor" component="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}">
            <layout id="normal" w="64" h="20"/>
          </container>
        </WasabiXML>
        """
        let loaded = try load(xml: xml)
        let containers = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        let pledit = try XCTUnwrap(containers.first { $0.id == "Pledit" })
        XCTAssertFalse(WinampModernContainerTopology.isListedInWindowMenu(pledit))
    }

    /// **The second live defect.** Anaheim_Player_01's `avs_window` declares `default_w="120"` with
    /// `minimum_w="180"`, and Styx's `AVS` 300×300 with a 400×230 minimum: the window opened at the
    /// default, so its standard frame's corner art was laid out for a window wider than the one
    /// drawing it and the chrome came out cut off — "a misformed rectangle box". Four layouts in the
    /// corpus declare a default below their own minimum and two are AVS windows.
    func testALayoutNeverOpensBelowItsOwnDeclaredMinimum() throws {
        let xml = """
        <WasabiXML>
          <container id="avs" name="Visualization" component="\(Self.visGUID)">
            <layout id="normal" default_w="120" default_h="260" minimum_w="180" minimum_h="120">
              <component id="avs.component" param="\(Self.visGUID)" x="10" y="30" w="0" h="0"
                         relatw="1" relath="1"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try load(xml: xml)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "avs", clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 180, height: 260),
                       "the narrow default is raised to the skin's own minimum; the tall one is kept")
    }

    /// The GUID the eight corpus skins write, in both spellings a `component`/`TOGGLE` uses.
    func testTheVisualizationGUIDResolves() {
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: Self.visGUID), .visualization)
        XCTAssertEqual(WinampModernComponentRegistry.kind(for: "guid:vis"), .visualization)
        XCTAssertEqual(WinampModernComponentRegistry.canonicalGUID(for: .visualization), Self.visGUID)
    }

    // MARK: - Fixture

    private func makeAVSScene() throws -> (WasabiSceneRenderer, WinampModernComponentHolder) {
        let xml = """
        <WasabiXML>
          <container id="avs" component="\(Self.visGUID)">
            <layout id="normal" w="64" h="20">
              <component id="avs.component" param="\(Self.visGUID)" x="0" y="0" w="64" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try load(xml: xml)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: "avs", clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let holder = try XCTUnwrap(renderer.componentHolders().first { $0.kind == .visualization })
        return (renderer, holder)
    }

    private func skinXML(withAVSContainer: Bool) -> String {
        let avs = withAVSContainer ? """
          <container id="avs" name="Visualization" component="\(Self.visGUID)">
            <layout id="normal" w="64" h="20">
              <component id="avs.component" param="\(Self.visGUID)" x="0" y="0" w="64" h="20"/>
            </layout>
          </container>
        """ : ""
        return """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="64" h="20">
              <vis id="vis" x="0" y="0" w="64" h="20"/>
            </layout>
          </container>
        \(avs)
        </WasabiXML>
        """
    }

    private func hasColour(_ pixels: [UInt8]) -> Bool {
        stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] > 0 || pixels[$0 + 1] > 0 || pixels[$0 + 2] > 0 }
    }

    private func pixel(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * 64 + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }

    private func render(_ renderer: WasabiSceneRenderer) throws -> [UInt8] {
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

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase48Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase48-\(UUID().uuidString).wal")
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
}
