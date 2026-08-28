import AppKit
import XCTest
@testable import NullPlayer

final class WinampModernHostedProviderTests: XCTestCase {
    func testRegistryEnablesEveryInitialProviderThroughOneContract() throws {
        XCTAssertEqual(WinampModernHostedWindowRegistry.all.map(\.id),
                       WinampModernHostedWindowID.allCases)
        XCTAssertEqual(Set(WinampModernHostedWindowRegistry.all.map(\.id)).count,
                       WinampModernHostedWindowID.allCases.count)
        XCTAssertTrue(WinampModernHostedWindowRegistry.all.allSatisfy { $0.makeSurface != nil })

        let context = WinampModernHostedSurfaceContext(
            audioEngine: WindowManager.shared.audioEngine,
            nativeWindow: { nil },
            requestClose: {},
            requestFullscreen: {})
        var surfaces: [WinampModernHostedWindowID: WinampModernHostedSurface] = [:]
        for definition in WinampModernHostedWindowRegistry.all {
            let surface = try XCTUnwrap(definition.makeSurface?(context))
            surfaces[definition.id] = surface
            XCTAssertTrue(surface.view === surface.view)
        }
        addTeardownBlock {
            surfaces.values.forEach { $0.prepareForUITeardown() }
        }

        XCTAssertTrue(surfaces[.spectrum] is SpectrumView)
        XCTAssertTrue(surfaces[.cava] is CavaView)
        XCTAssertTrue(surfaces[.flow] is NetworkMonitorView)
        XCTAssertTrue(surfaces[.peppyMeter] is PeppyMeterView)
        XCTAssertTrue(surfaces[.audioAnalysis] is AudioAnalysisView)
        XCTAssertTrue(surfaces[.waveform] is WaveformView)
        XCTAssertTrue(surfaces[.cava] is WinampModernHostedCavaSurface)
        XCTAssertTrue(surfaces[.peppyMeter] is WinampModernHostedFullscreenSurface)
        XCTAssertTrue(surfaces[.waveform] is WinampModernHostedWaveformSurface)
    }

    func testRegistryGeometryRemainsFeatureSpecific() throws {
        let peppy = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .peppyMeter))
        let waveform = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .waveform))
        let spectrum = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .spectrum))

        XCTAssertEqual(peppy.defaultSize, SkinElements.PeppyMeterWindow.windowSize)
        XCTAssertEqual(waveform.defaultSize, SkinElements.WaveformWindow.windowSize)
        XCTAssertGreaterThan(peppy.defaultSize.height, spectrum.defaultSize.height)
        XCTAssertEqual(peppy.stackPolicy.preferredHeightMultiplier, 1.75)
    }

    // MARK: - Opening width

    /// A `.wal` player is any width the skin says. When it is wider than a hosted window's own
    /// default, the window opens at the player's width and left edge instead of leaving a ragged
    /// column beside it.
    func testWiderPlayerWidensAHostedWindowToMatchIt() {
        let opened = WindowManager.winampModernHostedOpeningFrame(
            NSRect(x: 0, y: 400, width: 275, height: 116),
            mainFrame: NSRect(x: 120, y: 516, width: 640, height: 232),
            minimumWidth: 0,
            maximumWidth: .greatestFiniteMagnitude)

        XCTAssertEqual(opened.width, 640, accuracy: 0.001)
        XCTAssertEqual(opened.minX, 120, accuracy: 0.001)
        XCTAssertEqual(opened.maxY, 516, accuracy: 0.001)
        XCTAssertEqual(opened.height, 116, accuracy: 0.001)
    }

    /// The match runs in both directions: a skin whose player is narrower than the registry default
    /// — Anaheim and its kind — pulls the window in, so the stack stays one column wide.
    func testNarrowerPlayerNarrowsAHostedWindowToMatchIt() {
        let opened = WindowManager.winampModernHostedOpeningFrame(
            NSRect(x: 0, y: 400, width: 275, height: 116),
            mainFrame: NSRect(x: 120, y: 516, width: 180, height: 232),
            minimumWidth: 0,
            maximumWidth: .greatestFiniteMagnitude)

        XCTAssertEqual(opened.width, 180, accuracy: 0.001)
        XCTAssertEqual(opened.minX, 120, accuracy: 0.001)
        XCTAssertEqual(opened.height, 116, accuracy: 0.001)
    }

    /// The skin frame's own drawable minimum is the floor, so following a very narrow player never
    /// hands the renderer a width it would bounce straight back.
    func testSkinFrameMinimumWidthFloorsTheMatch() {
        let opened = WindowManager.winampModernHostedOpeningFrame(
            NSRect(x: 0, y: 400, width: 275, height: 116),
            mainFrame: NSRect(x: 120, y: 516, width: 90, height: 232),
            minimumWidth: 160,
            maximumWidth: .greatestFiniteMagnitude)

        XCTAssertEqual(opened.width, 160, accuracy: 0.001)
        XCTAssertEqual(opened.minX, 120, accuracy: 0.001)
    }

    /// The skin frame's own resize limits outrank the player's width, so the window is never set to
    /// a size the renderer would immediately bounce back.
    func testSkinFrameMaximumWidthClampsTheMatch() {
        let opened = WindowManager.winampModernHostedOpeningFrame(
            NSRect(x: 0, y: 400, width: 275, height: 116),
            mainFrame: NSRect(x: 120, y: 516, width: 900, height: 232),
            minimumWidth: 0,
            maximumWidth: 500)

        XCTAssertEqual(opened.width, 500, accuracy: 0.001)
    }

    // MARK: - The width floor a synthesized frame declares

    private func instantiation(_ id: WinampModernHostedWindowID,
                               playerWidth: CGFloat?) throws
        -> WinampModernHostedWindowInstantiation {
        let definition = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: id))
        return WinampModernHostedWindowInstantiation(
            definition: definition,
            frame: WinampModernHostedFrameDescriptor(groupIdentifier: "test.frame",
                                                     xuiTag: "Wasabi:StandardFrame",
                                                     hasArtwork: true),
            playerWidth: playerWidth)
    }

    /// The registry width minimums are the classic 275, which is also these windows' default width,
    /// so under a 240-wide skin (Anaheim, micro) the floor sat above the player and no window could
    /// follow it in. The skin's own player width caps that floor.
    func testANarrowerPlayerLowersTheDeclaredWidthFloor() throws {
        for id in WinampModernHostedWindowID.allCases {
            let request = try instantiation(id, playerWidth: 240)
            let registry = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: id)).minimumSize
            XCTAssertEqual(request.minimumSize.width, min(registry.width, 240), accuracy: 0.001,
                           "\(id) kept a width floor above the player")
            XCTAssertEqual(request.minimumSize.height, registry.height, accuracy: 0.001,
                           "\(id) moved its height floor")
        }
    }

    /// A wide player never *raises* the floor: the registry minimum is what the content needs.
    func testAWiderPlayerLeavesTheDeclaredFloorAlone() throws {
        let request = try instantiation(.cava, playerWidth: 900)
        let registry = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .cava)).minimumSize

        XCTAssertEqual(request.minimumSize, registry)
    }

    /// No player on screen to measure, and no degenerate one, leaves the registry floor in place.
    func testAnUnmeasurablePlayerLeavesTheDeclaredFloorAlone() throws {
        let registry = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .spectrum)).minimumSize

        XCTAssertEqual(try instantiation(.spectrum, playerWidth: nil).minimumSize, registry)
        XCTAssertEqual(try instantiation(.spectrum, playerWidth: 0).minimumSize, registry)
    }

    /// No player to follow means no change: a zero-width main frame leaves the window at its default.
    func testMissingPlayerLeavesTheFrameAlone() {
        let frame = NSRect(x: 0, y: 400, width: 275, height: 116)
        let opened = WindowManager.winampModernHostedOpeningFrame(
            frame,
            mainFrame: NSRect(x: 120, y: 516, width: 0, height: 232),
            minimumWidth: 0,
            maximumWidth: .greatestFiniteMagnitude)

        XCTAssertEqual(opened, frame)
    }
}
