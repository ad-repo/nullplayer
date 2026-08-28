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
            id: .cava,
            mainFrame: NSRect(x: 120, y: 516, width: 640, height: 232),
            maximumWidth: .greatestFiniteMagnitude)

        XCTAssertEqual(opened.width, 640, accuracy: 0.001)
        XCTAssertEqual(opened.minX, 120, accuracy: 0.001)
        XCTAssertEqual(opened.maxY, 516, accuracy: 0.001)
        XCTAssertEqual(opened.height, 116, accuracy: 0.001)
    }

    /// The registry default is a floor, never a ceiling: a narrow skin must not shrink Cava or the
    /// spectrum analyzer below the size their content was cut for.
    func testNarrowerPlayerLeavesAHostedWindowAtItsDefaultWidth() {
        let frame = NSRect(x: 0, y: 400, width: 275, height: 116)

        for id in WinampModernHostedWindowID.allCases where id != .equalizer {
            let opened = WindowManager.winampModernHostedOpeningFrame(
                frame,
                id: id,
                mainFrame: NSRect(x: 120, y: 516, width: 180, height: 232),
                maximumWidth: .greatestFiniteMagnitude)
            XCTAssertEqual(opened, frame, "\(id) followed a narrower player")
        }
    }

    /// The equalizer is the one window that matches the player in both directions, as it has in
    /// every UI mode since long before `.wal` skins existed.
    func testEqualizerStillMatchesEvenANarrowerPlayer() {
        let opened = WindowManager.winampModernHostedOpeningFrame(
            NSRect(x: 0, y: 400, width: 275, height: 116),
            id: .equalizer,
            mainFrame: NSRect(x: 120, y: 516, width: 180, height: 232),
            maximumWidth: .greatestFiniteMagnitude)

        XCTAssertEqual(opened.width, 180, accuracy: 0.001)
        XCTAssertEqual(opened.minX, 120, accuracy: 0.001)
    }

    /// The skin frame's own resize limits outrank the player's width, so the window is never set to
    /// a size the renderer would immediately bounce back.
    func testSkinFrameMaximumWidthClampsTheMatch() {
        let opened = WindowManager.winampModernHostedOpeningFrame(
            NSRect(x: 0, y: 400, width: 275, height: 116),
            id: .spectrum,
            mainFrame: NSRect(x: 120, y: 516, width: 900, height: 232),
            maximumWidth: 500)

        XCTAssertEqual(opened.width, 500, accuracy: 0.001)
    }
}
