import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

final class WinampModernHostedWindowTests: XCTestCase {
    func testHeadlessLoadRecordsRoutesWithoutCreatingHostedGraphRoots() throws {
        let loaded = try makeSkin()
        let count = loaded.runtime.graph.objectCount

        for id in WinampModernHostedWindowID.allCases {
            guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[id] else {
                return XCTFail("expected a skin-frame route for \(id)")
            }
            XCTAssertEqual(frame.groupIdentifier, "wasabi.standardframe.statusbar")
        }

        XCTAssertEqual(loaded.runtime.graph.objectCount, count)
        XCTAssertFalse(loaded.runtime.graph.roots.contains {
            ($0.xmlID ?? "").hasPrefix("nullplayer.spectrum")
                || ($0.xmlID ?? "").hasPrefix("nullplayer.cava")
        })
    }

    func testSkinAuthoredNPTokenIsInertWithoutTrustedProvenance() throws {
        let loaded = try makeSkin(extraMainContent: """
          <component id="untrusted" param="guid:np.spectrum" x="0" y="0" w="30" h="20"/>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host())
        addTeardownBlock { renderer.teardown() }
        let holder = try XCTUnwrap(renderer.componentHolders().first {
            $0.object.xmlID == "untrusted"
        })
        XCTAssertEqual(holder.surfaceID, .component(.other))
    }

    func testRequestMaterializesOnceAndReusesTheWindowAndSurface() throws {
        let parts = try makeMaterializer()
        XCTAssertTrue(parts.components.factoryCalls.isEmpty,
                      "constructing a materializer must not run an unopened window factory")
        let countBefore = parts.loaded.runtime.graph.objectCount
        var scriptEvents: [String] = []
        parts.scripts.dispatchObserver = { event, _, _ in scriptEvents.append(event) }

        XCTAssertTrue(parts.materializer.show(.spectrum))
        let firstWindow = try XCTUnwrap(parts.materializer.nativeWindow(ifMaterialized: .spectrum))
        let countAfterFirstShow = parts.loaded.runtime.graph.objectCount
        let surface = try XCTUnwrap(parts.components.surfaces[.spectrum])

        XCTAssertGreaterThan(countAfterFirstShow, countBefore)
        XCTAssertEqual(parts.components.factoryCalls[.spectrum], 1)
        XCTAssertEqual(surface.paletteApplications, 1)
        XCTAssertEqual(surface.scaleApplications, 1)
        XCTAssertGreaterThanOrEqual(surface.resumes, 1)
        XCTAssertNotNil(surface.view.superview)
        let loadedIndex = try XCTUnwrap(scriptEvents.firstIndex(of: "onscriptloaded"))
        let paramIndex = try XCTUnwrap(scriptEvents.firstIndex(of: "onsetxuiparam"))
        XCTAssertLessThan(loadedIndex, paramIndex,
                          "request-time frame scripts initialize before their XUI parameters")

        XCTAssertTrue(parts.materializer.show(.spectrum))
        XCTAssertTrue(parts.materializer.nativeWindow(ifMaterialized: .spectrum) === firstWindow)
        XCTAssertEqual(parts.loaded.runtime.graph.objectCount, countAfterFirstShow)
        XCTAssertEqual(parts.components.factoryCalls[.spectrum], 1)

        let topLeft = NSPoint(x: firstWindow.frame.minX, y: firstWindow.frame.maxY)
        parts.materializer.applySkinScale(2)
        XCTAssertEqual(parts.materializer.materializedWindows[0].view.skinScale, 2)
        XCTAssertEqual(NSPoint(x: firstWindow.frame.minX, y: firstWindow.frame.maxY), topLeft)
        XCTAssertEqual(surface.scaleApplications, 2)

        parts.materializer.hide(.spectrum)
        XCTAssertFalse(parts.materializer.isVisible(.spectrum))
        XCTAssertGreaterThanOrEqual(surface.suspends, 1)
        XCTAssertTrue(parts.materializer.show(.spectrum))
        XCTAssertTrue(parts.materializer.nativeWindow(ifMaterialized: .spectrum) === firstWindow)

        parts.materializer.teardown()
        XCTAssertEqual(surface.terminalTeardowns, 1)
        parts.materializer.teardown()
        XCTAssertEqual(surface.terminalTeardowns, 1)
    }

    func testAllRegisteredIDsUseTheSameMaterializerPath() throws {
        let parts = try makeMaterializer()
        for id in WinampModernHostedWindowID.allCases {
            XCTAssertTrue(parts.materializer.show(id), "failed to materialize \(id)")
            XCTAssertNotNil(parts.materializer.nativeWindow(ifMaterialized: id))
            XCTAssertEqual(parts.components.factoryCalls[id], 1)
        }
        XCTAssertEqual(parts.materializer.materializedWindows.count,
                       WinampModernHostedWindowID.allCases.count)
    }

    func testFailureRollsBackGraphAndFallsBackWithoutAnEmptyWindow() throws {
        let loaded = try makeSkin()
        let host = Host()
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        try scripts.start()
        let components = ComponentHost(makeSurfaces: false)
        var fallbacks: [(WinampModernHostedWindowID, Bool)] = []
        let materializer = makeMaterializer(loaded: loaded, host: host, scripts: scripts,
                                            components: components) {
            fallbacks.append(($0, $1))
        }
        addTeardownBlock { materializer.teardown(); scripts.teardown() }
        let countBefore = loaded.runtime.graph.objectCount

        XCTAssertFalse(materializer.show(.spectrum))
        XCTAssertEqual(fallbacks.map(\.0), [.spectrum])
        XCTAssertNil(materializer.nativeWindow(ifMaterialized: .spectrum))
        XCTAssertEqual(loaded.runtime.graph.objectCount, countBefore)
        XCTAssertFalse(loaded.runtime.graph.roots.contains {
            $0.xmlID == WinampModernHostedWindowID.spectrum.containerIdentifier
        })

        XCTAssertFalse(materializer.show(.spectrum))
        XCTAssertEqual(fallbacks.count, 2)
        XCTAssertEqual(components.factoryCalls[.spectrum], 1,
                       "a failed id becomes a deterministic fallback and is not rebuilt")
    }

    // MARK: - A hosted window is a window the skin's script can address (B110)

    /// **The reveal is the announcement.** A hosted window is materialized, placed by
    /// `WindowManager`, and only then ordered in — every one of those moves happens while the window
    /// is off screen, where AppKit posts no `windowDidMove`. A skin that draws this window's chrome
    /// in a *second* window is therefore told nothing at all unless the reveal itself says so, and
    /// its frame stays at the origin it was created at while the window docks under the player.
    /// Measured live on Ebonite, whose Flow frame came up 220px from its own contents.
    func testRevealAnnouncesTheWindowAndHidingDoesNot() throws {
        var settled: [WinampModernHostedWindowID] = []
        let parts = try makeMaterializer { settled.append($0.id) }

        XCTAssertTrue(parts.materializer.show(.spectrum))
        XCTAssertEqual(settled, [.spectrum], "revealing a hosted window must announce it")

        parts.materializer.hide(.spectrum)
        XCTAssertEqual(settled, [.spectrum], "hiding announces nothing — there is nowhere to be")

        XCTAssertTrue(parts.materializer.show(.spectrum))
        XCTAssertEqual(settled, [.spectrum, .spectrum], "every reveal announces, not just the first")
    }

    /// A hosted window's view is keyed by its **synthesized container's** stable id, which is the
    /// whole of what lets a script's `resize()` find it: `moveContainerWindow` resolves a container
    /// id to a window through `auxiliaryContainers`, `skinView` and then this table, and a hosted
    /// window is in none of the first two.
    ///
    /// Ebonite's frame answers its own drag with `syncContent()` —
    /// `comp_layout.resize(frame.getLeft(), frame.getTop(), …)` — so while that lookup failed the
    /// frame came away in the user's hand and left its contents behind. Dragging the *client* always
    /// worked, because a frame is an auxiliary container.
    func testAHostedWindowIsAddressableByItsContainerStableID() throws {
        let parts = try makeMaterializer()
        XCTAssertTrue(parts.materializer.show(.spectrum))
        let instance = try XCTUnwrap(parts.materializer.materializedWindows.first)

        XCTAssertEqual(instance.view.containerID, instance.graphRoot.stableID)
        XCTAssertEqual(instance.graphRoot.xmlID,
                       WinampModernHostedWindowID.spectrum.containerIdentifier)
        XCTAssertTrue(parts.materializer.materializedWindows
            .first { $0.view.containerID == instance.graphRoot.stableID }?.window === instance.window)
    }

    private struct MaterializerParts {
        let loaded: WinampModernLoadedSkin
        let scripts: WinampModernScriptRuntime
        let components: ComponentHost
        let materializer: WinampModernHostedWindowMaterializer
    }

    private func makeMaterializer(
        windowDidSettle: @escaping (WinampModernHostedWindowMaterializer.MaterializedWindow) -> Void
            = { _ in }
    ) throws -> MaterializerParts {
        let loaded = try makeSkin()
        let host = Host()
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        try scripts.start()
        let components = ComponentHost(makeSurfaces: true)
        let materializer = makeMaterializer(loaded: loaded, host: host, scripts: scripts,
                                            components: components,
                                            windowDidSettle: windowDidSettle) { _, _ in }
        addTeardownBlock { materializer.teardown(); scripts.teardown() }
        return MaterializerParts(loaded: loaded, scripts: scripts,
                                 components: components, materializer: materializer)
    }

    private func makeMaterializer(
        loaded: WinampModernLoadedSkin,
        host: Host,
        scripts: WinampModernScriptRuntime,
        components: ComponentHost,
        windowDidSettle: @escaping (WinampModernHostedWindowMaterializer.MaterializedWindow) -> Void
            = { _ in },
        fallback: @escaping (WinampModernHostedWindowID, Bool) -> Void
    ) -> WinampModernHostedWindowMaterializer {
        WinampModernHostedWindowMaterializer(
            loadedSkin: loaded,
            host: host,
            scripts: scripts,
            componentHost: components,
            skinScale: { 1.25 },
            classicFallback: fallback,
            windowDidSettle: windowDidSettle,
            testContentInstaller: { root, id in
                func frame(in object: WasabiObject) -> WasabiObject? {
                    if object.attributes["content"] == id.contentGroupIdentifier { return object }
                    for child in object.children {
                        if let found = frame(in: child) { return found }
                    }
                    return nil
                }
                let owner = try XCTUnwrap(frame(in: root))
                let instantiate = try XCTUnwrap(loaded.runtime.instantiateGroup)
                _ = try instantiate(id.contentGroupIdentifier, owner)
            })
    }

    private func makeSkin(extraMainContent: String = "") throws -> WinampModernLoadedSkin {
        let xml = """
        <WasabiXML>
          <groupdef id="wasabi.standardframe.statusbar" xuitag="Wasabi:StandardFrame:Status">
            <layer id="frame.art" x="0" y="0" w="0" h="8" relatw="1"/>
            <script file="scripts/standardframe.maki"/>
          </groupdef>
          <container id="main">
            <layout id="normal" default_w="300" default_h="160">
              <windowholder hold="guid:pl" x="0" y="0" w="20" h="20"/>
              <windowholder hold="guid:ml" x="20" y="0" w="20" h="20"/>
              \(extraMainContent)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil)
            .load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernHostedWindowTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Hosted-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ data: Data) throws {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < data.count else { return Data() }
                return data.subdata(in: start..<min(data.count, start + size))
            }
        }
        try add("skin.xml", Data(xml.utf8))
        try add("scripts/standardframe.maki", Self.frameMakiScript())
        return url
    }

    /// A synthetic frame script with observable `onScriptLoaded` and `onSetXuiParam` handlers.
    private static func frameMakiScript() -> Data {
        var data = Data([0x46, 0x47])
        func u8(_ value: UInt8) { data.append(value) }
        func u16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func string(_ value: String) {
            let bytes = Data(value.utf8)
            u16(UInt16(bytes.count)); data.append(bytes)
        }
        u16(0x0403); u32(23); u32(1)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        let methods = ["onscriptloaded", "onsetxuiparam"]
        u32(UInt32(methods.count))
        for method in methods { u16(0); u16(0); string(method) }
        u32(1)
        u8(0); u8(1); u16(0); u16(0); u16(0); u16(0); u16(0); u8(1); u8(1)
        u32(0)
        u32(UInt32(methods.count))
        for method in 0..<methods.count { u32(0); u32(UInt32(method)); u32(0) }
        u32(1); u8(33)
        return data
    }

    private final class Surface: WinampModernHostedSurface {
        let view = NSView(frame: .zero)
        var paletteApplications = 0
        var scaleApplications = 0
        var resumes = 0
        var suspends = 0
        var unmounts = 0
        var terminalTeardowns = 0
        func applyPalette(_ style: WinampModernSurfaceStyle) { paletteApplications += 1 }
        func applySkinScale(_ scale: CGFloat) { scaleApplications += 1 }
        func resume() { resumes += 1 }
        func suspend() { suspends += 1 }
        func unmountFromHolder() { unmounts += 1; view.removeFromSuperview() }
        func prepareForUITeardown() {
            guard terminalTeardowns == 0 else { return }
            terminalTeardowns = 1
            view.removeFromSuperview()
        }
    }

    private final class ComponentHost: WinampModernComponentHost {
        let makeSurfaces: Bool
        var surfaces: [WinampModernHostedWindowID: Surface] = [:]
        var factoryCalls: [WinampModernHostedWindowID: Int] = [:]
        init(makeSurfaces: Bool) { self.makeSurfaces = makeSurfaces }
        func makeHostedWindowSurface(id: WinampModernHostedWindowID) -> WinampModernHostedSurface? {
            factoryCalls[id, default: 0] += 1
            guard makeSurfaces else { return nil }
            let surface = Surface()
            surfaces[id] = surface
            return surface
        }
        func playlistSnapshot() -> WinampModernPlaylistSnapshot { .empty }
        func playlistSelect(row: Int) {}
        func playlistPlay(row: Int) {}
        func playlistRemove(row: Int) {}
        func equalizerSnapshot() -> WinampModernEQSnapshot { .flat }
        func equalizerSetBandGainDB(_ band: Int, gainDB: Float) {}
        func equalizerSetPreampDB(_ gainDB: Float) {}
        func equalizerSetEnabled(_ enabled: Bool) {}
        func equalizerSetAuto(_ enabled: Bool) {}
        func equalizerApplyPreset(named name: String) {}
        func toggleClassicWindow(for kind: WinampModernComponentKind) {}
    }

    private final class Host: WinampModernHost {
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
}
