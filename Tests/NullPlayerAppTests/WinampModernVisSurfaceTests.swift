import AppKit
import XCTest
@testable import NullPlayer

/// BB9a — the engine picker over an unhosted `{0000000A}` visualization pane.
///
/// A `.wal` skin draws in two kinds of box and they are not the same surface. `<vis>` is the skin's
/// own artwork — cut, sized and coloured by its author, and Big Bento Modern's butterfly is four of
/// them. A `{0000000A}` plugin holder the view layer has not filled with the real engine has **no
/// markup at all**: Winamp's default there is its built-in spectrum analyzer (BB9), and until this
/// change that was the only thing it could ever be.
///
/// It now carries the same choice a `<vis>` box has — Winamp's own analyzer and oscilloscope, Cava,
/// vis_classic — against a selection of its **own**, which is the whole point of
/// `WinampModernVisSurface`: putting Cava in the big pane must not overpaint the butterfly.
///
/// What is asserted here is what live QA could not settle by eye, plus the one defect that reached
/// the running app: picking a *mode* row left the outgoing engine selected, so the row ticked, the
/// pane went on drawing vis_classic, and there was no way back out of it.
final class WinampModernVisSurfaceTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WinampModernVisSurfaceTests.\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    private func configuration(_ namespace: String) -> WinampModernConfiguration {
        WinampModernConfiguration(namespace: namespace, defaults: defaults)
    }

    // MARK: - Two surfaces, two selections

    /// The pane starts on the skin's own engine for the same reason the `<vis>` boxes do: a skin
    /// looks the way its author drew it until somebody says otherwise.
    func testAnUntouchedPaneDrawsWithTheSkinsOwnEngine() {
        let bento = configuration("untouched")
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .componentHolder, in: bento), .skin)
        XCTAssertEqual(WinampModernSkinState.visualizationHolderMode(in: bento), .analyzer)
    }

    /// **The reason the surface enum exists.** Choosing Cava for the pane must leave the butterfly
    /// exactly as its author drew it, and the reverse.
    func testTheTwoSurfacesKeepSeparateEngines() {
        let bento = configuration("bento")
        WinampModernSkinState.setSpectrumAnalyzer(.cava, for: .componentHolder, in: bento)

        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .componentHolder, in: bento), .cava)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .visBox, in: bento), .skin)

        WinampModernSkinState.setSpectrumAnalyzer(.visClassic, for: .visBox, in: bento)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .componentHolder, in: bento), .cava)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .visBox, in: bento), .visClassic)
    }

    /// Per skin, like every other entry `WinampModernSkinState` owns.
    func testThePanesChoiceIsRememberedPerSkin() {
        let bento = configuration("bento")
        let miku = configuration("miku")
        WinampModernSkinState.setSpectrumAnalyzer(.visClassic, for: .componentHolder, in: bento)

        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .componentHolder, in: bento), .visClassic)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .componentHolder, in: miku), .skin)
    }

    /// The `<vis>` boxes' key is untouched by the split, so a skin somebody had already set to Cava
    /// before the pane had a choice at all still comes back on Cava — and its pane does not.
    func testAnEngineStoredBeforeTheSplitStaysWithTheVisBoxes() {
        let bento = configuration("upgraded")
        bento.setString(WinampModernSpectrumAnalyzer.cava.rawValue,
                        section: WinampModernSkinState.visSection,
                        key: WinampModernSkinState.analyzerKey)

        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .visBox, in: bento), .cava)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .componentHolder, in: bento), .skin)
    }

    // MARK: - The pane's mode

    /// The pane has no `mode=` attribute to read, so the host remembers it. Round-trips as a name,
    /// not an ordinal, for `spectrumAnalyzer`'s reason.
    func testThePanesModeRoundTrips() {
        let bento = configuration("bento")
        for mode in WasabiVisualizationMode.allCases {
            WinampModernSkinState.setVisualizationHolderMode(mode, in: bento)
            XCTAssertEqual(WinampModernSkinState.visualizationHolderMode(in: bento), mode)
        }
    }

    /// A mode is the pane's, not the skin's: writing one must not reach the `<vis>` boxes' engine or
    /// the pane's, which are the other two entries in the same config section.
    func testThePanesModeIsIndependentOfBothEngines() {
        let bento = configuration("bento")
        WinampModernSkinState.setSpectrumAnalyzer(.cava, for: .visBox, in: bento)
        WinampModernSkinState.setSpectrumAnalyzer(.visClassic, for: .componentHolder, in: bento)
        WinampModernSkinState.setVisualizationHolderMode(.oscilloscope, in: bento)

        XCTAssertEqual(WinampModernSkinState.visualizationHolderMode(in: bento), .oscilloscope)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .visBox, in: bento), .cava)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(for: .componentHolder, in: bento), .visClassic)
    }

    // MARK: - Selection state

    /// Switching one surface's engine leaves the other's renderer alone.
    ///
    /// `select` discards the outgoing engine's state — its taps, its cores, its per-box bars — so an
    /// engine nobody is looking at stops costing audio work. With two surfaces that has to be
    /// conditional: discarding while the other surface is still drawing with that engine would wipe
    /// the bars out from under a box the user never touched.
    func testSwitchingOneSurfaceLeavesTheOtherEngineRunning() {
        let bento = configuration("bento")
        let state = WinampModernSpectrumAnalyzerState()

        XCTAssertTrue(state.select(.cava, for: .visBox, in: bento))
        XCTAssertTrue(state.select(.cava, for: .componentHolder, in: bento))
        // Both surfaces are on the same engine, so both resolve to the one renderer object — two
        // instances would be two audio consumers against the same audio.
        XCTAssertTrue(state.renderer(for: .visBox, in: bento)
                      === state.renderer(for: .componentHolder, in: bento))

        // Taking the pane off Cava must leave the butterfly's Cava exactly where it was.
        XCTAssertTrue(state.select(.skin, for: .componentHolder, in: bento))
        XCTAssertEqual(state.suite(for: .visBox, in: bento), .cava)
        XCTAssertEqual(state.suite(for: .componentHolder, in: bento), .skin)
    }

    /// Re-selecting what is already drawing reports no change, so the caller can skip the repaint.
    func testSelectingTheRunningEngineIsNotAChange() {
        let bento = configuration("bento")
        let state = WinampModernSpectrumAnalyzerState()
        XCTAssertFalse(state.select(.skin, for: .componentHolder, in: bento))
        XCTAssertTrue(state.select(.visClassic, for: .componentHolder, in: bento))
        XCTAssertFalse(state.select(.visClassic, for: .componentHolder, in: bento))
    }

    // MARK: - The mode rows and the engine rows are one group

    /// **The defect that reached the running app.** Picking `Spectrum Analyzer` or `Oscilloscope`
    /// wrote the mode and left vis_classic selected, so the row ticked, the pane went on drawing
    /// vis_classic, and there was no way back out of it — a one-way door into every NullPlayer
    /// engine. Winamp's own two modes are Winamp's own engine.
    func testPickingOneOfWinampsModesTakesThePaneBackToWinampsEngine() {
        XCTAssertEqual(WinampModernSpectrumAnalyzer.chosen(byPicking: .analyzer, current: .visClassic), .skin)
        XCTAssertEqual(WinampModernSpectrumAnalyzer.chosen(byPicking: .oscilloscope, current: .cava), .skin)
        XCTAssertEqual(WinampModernSpectrumAnalyzer.chosen(byPicking: .analyzer, current: .skin), .skin)
    }

    /// `Off` is not one of Winamp's modes but the absence of all of them, so it leaves the selection
    /// alone: switching the pane back on returns it to whatever was last in it.
    func testOffLeavesTheSelectedEngineAlone() {
        XCTAssertEqual(WinampModernSpectrumAnalyzer.chosen(byPicking: .off, current: .cava), .cava)
        XCTAssertEqual(WinampModernSpectrumAnalyzer.chosen(byPicking: .off, current: .visClassic), .visClassic)
        XCTAssertEqual(WinampModernSpectrumAnalyzer.chosen(byPicking: .off, current: .skin), .skin)
    }
}
