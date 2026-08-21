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
}
