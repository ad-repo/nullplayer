import AppKit
import XCTest
@testable import NullPlayer

/// Phase 75 — B53: NullPlayer's own spectrum analyzers, selectable in a `.wal` skin's `<vis>` box.
///
/// The box stays the skin's — its geometry, its colours, its `mode` — and what paints it becomes a
/// choice between Winamp's own analyzer/oscilloscope, Cava and vis_classic. The seam is B51's
/// `WasabiVisRenderer`, so the engines are three implementations of one protocol rather than a
/// larger switch.
///
/// What is asserted here is what live QA could not settle by eye, and what a later change is most
/// likely to break:
///
/// - the **selection** and its per-skin persistence, including the sentinel a downgrade leaves;
/// - the **geometry** a suite engine is handed, which is the run of adjacent boxes rather than one
///   box (Big Bento declares `main.vis` + `main.vis2` side by side, and drawing one analyzer in each
///   of them is two copies of the same picture);
/// - the **gain calibration**, because the three engines measure the same audio on scales that were
///   never meant to agree;
/// - and the popup's **command ids**, where a real defect lived: `0` is MAKI's "nothing chosen" and
///   is also carried by a submenu parent, so treating it as a skin mode row made every pick of ours
///   hand the box straight back to the skin's engine four milliseconds later.
final class WinampModernPhase75Tests: XCTestCase {

    private var defaults: UserDefaults!
    private let graph = WasabiObjectGraph()

    /// The renderer's own construction route, as Phase 61's flip tests use it.
    private func vis(_ attributes: [String: String]) -> WasabiObject {
        var merged = attributes
        merged["id"] = merged["id"] ?? "vis"
        return graph.makeObject(typeName: "vis", attributes: merged,
                                source: WalSourceLocation(path: "/test.xml"))
    }

    private func id(_ raw: UInt64) -> WasabiObjectID { WasabiObjectID(rawValue: raw) }

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WinampModernPhase75Tests.\(UUID().uuidString)")
        WinampModernVisSensitivity.invalidateCache()
    }

    override func tearDown() {
        WinampModernVisSensitivity.invalidateCache()
        defaults = nil
        super.tearDown()
    }

    // MARK: - The choice, and what a skin remembers about it

    /// The default is the skin's own engine: a skin looks the way its author drew it until the user
    /// says otherwise, which is the rule the colour themes and Text Size already follow.
    func testAnUntouchedSkinDrawsWithItsOwnEngine() {
        let configuration = WinampModernConfiguration(namespace: "untouched", defaults: defaults)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(in: configuration), .skin)
    }

    func testTheChoiceIsRememberedPerSkin() {
        let bento = WinampModernConfiguration(namespace: "bento", defaults: defaults)
        let miku = WinampModernConfiguration(namespace: "miku", defaults: defaults)
        WinampModernSkinState.setSpectrumAnalyzer(.cava, in: bento)

        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(in: bento), .cava)
        // The other skin is untouched — the choice is about how *this* skin should look.
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(in: miku), .skin)
    }

    /// Stored by name rather than by ordinal, so a value the build no longer knows falls back to the
    /// one choice that is always right for a skin we know nothing else about.
    func testAnUnknownStoredNameFallsBackToTheSkinsOwnEngine() {
        let configuration = WinampModernConfiguration(namespace: "future", defaults: defaults)
        configuration.setString("milkdrop", section: WinampModernSkinState.visSection,
                                key: WinampModernSkinState.analyzerKey)
        XCTAssertEqual(WinampModernSkinState.spectrumAnalyzer(in: configuration), .skin)
        XCTAssertEqual(WinampModernSpectrumAnalyzer.from(storedValue: ""), .skin)
    }

    // MARK: - One analyzer across a run of boxes

    /// Big Bento's header: `main.vis` and `main.vis2`, 144×30 each, flush against one another. A
    /// suite engine is handed the pair's 288px rect and clipped to whichever box it is drawing, so
    /// the two show one continuous analyzer instead of two copies of the same one.
    func testAdjacentBoxesOfTheSameHeightAreOneRun() {
        let left = CGRect(x: 436, y: 10, width: 144, height: 30)
        let right = CGRect(x: 580, y: 10, width: 144, height: 30)
        let rows = WasabiSceneRenderer.visualizationRows(boxes: [(id(1), left), (id(2), right)])

        XCTAssertEqual(rows[id(1)], left.union(right))
        XCTAssertEqual(rows[id(2)], left.union(right))
        XCTAssertEqual(rows[id(1)]?.width, 288)
    }

    /// The reflection strips beneath them are 10px tall, so they are a run of their own rather than
    /// part of the row they reflect — otherwise one analyzer would be stretched over both.
    func testBoxesOfADifferentHeightAreADifferentRun() {
        let bar = CGRect(x: 436, y: 10, width: 144, height: 30)
        let mirror = CGRect(x: 436, y: 40, width: 144, height: 10)
        let rows = WasabiSceneRenderer.visualizationRows(boxes: [(id(1), bar), (id(2), mirror)])

        // Neither is in a run with the other, and a lone box has no run at all — it keeps its frame.
        XCTAssertNil(rows[id(1)])
        XCTAssertNil(rows[id(2)])
    }

    /// A skin that puts two boxes at opposite ends of its window means two visualizations, not one
    /// stretched across the gap between them.
    func testBoxesSeparatedByAGapStayApart() {
        let left = CGRect(x: 0, y: 10, width: 100, height: 30)
        let right = CGRect(x: 400, y: 10, width: 100, height: 30)
        XCTAssertTrue(WasabiSceneRenderer.visualizationRows(boxes: [(id(1), left), (id(2), right)]).isEmpty)
    }

    /// A hairline seam is still one visualization: the rule is "touching", not "exactly flush".
    func testAHairlineSeamIsStillOneRun() {
        let left = CGRect(x: 0, y: 10, width: 100, height: 30)
        let right = CGRect(x: 101, y: 10, width: 100, height: 30)
        XCTAssertEqual(WasabiSceneRenderer.visualizationRows(boxes: [(id(1), left), (id(2), right)])[id(1)],
                       left.union(right))
    }

    // MARK: - The horizontal mirror is Winamp's, not every engine's

    /// `fliph` makes Big Bento's two analyzers meet low-frequency-to-low-frequency — a composition
    /// drawn for a row of bands. A mirrored Cava runs its frequency sweep backwards, so the flip is
    /// dropped for NullPlayer's engines and kept for the skin's own.
    func testTheHorizontalFlipCanBeSuppressedWithoutTouchingTheVerticalOne() {
        let object = vis(["fliph": "1", "flipv": "1"])
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)

        let both = WasabiSceneRenderer.flipTransform(of: object, frame: frame)
        XCTAssertEqual(both?.a, -1)
        XCTAssertEqual(both?.d, -1)

        let verticalOnly = WasabiSceneRenderer.flipTransform(of: object, frame: frame,
                                                            suppressHorizontal: true)
        XCTAssertEqual(verticalOnly?.a, 1)
        XCTAssertEqual(verticalOnly?.d, -1)
    }

    /// With nothing left to mirror there is no transform at all, so a box that only asked for the
    /// horizontal flip costs nothing when a suite engine is drawing it.
    func testSuppressingTheOnlyFlipLeavesNoTransform() {
        let object = vis(["fliph": "1"])
        XCTAssertNil(WasabiSceneRenderer.flipTransform(of: object, frame: CGRect(x: 0, y: 0,
                                                                                width: 10, height: 10),
                                                       suppressHorizontal: true))
    }

    // MARK: - Gain: three engines, one loudness

    /// `Normal` is exactly the calibration, which is what makes the five steps mean the same thing
    /// for every engine.
    func testNormalSensitivityIsTheCalibrationItself() {
        XCTAssertEqual(WinampModernVisSensitivity.stored(for: .cava, defaults: defaults), .normal)
        XCTAssertEqual(WinampModernVisSensitivity.gain(for: .skin, defaults: defaults),
                       WasabiVisStyle.Gain.builtInAnalyzer, accuracy: 0.0001)
        XCTAssertEqual(WinampModernVisSensitivity.gain(for: .cava, defaults: defaults),
                       CGFloat(WasabiVisStyle.Gain.cava), accuracy: 0.0001)
    }

    /// The two surfaces of the skin's own engine share one Sensitivity — it is one engine and one
    /// row in the menu — but they are calibrated apart: the analyzer needed turning down off its
    /// decibel curve and the oscilloscope, which draws the wave itself, never did.
    func testTheSkinsAnalyzerAndOscilloscopeShareOneSettingAndTwoCalibrations() {
        WinampModernVisSensitivity.set(.higher, for: .skin, defaults: defaults)

        XCTAssertEqual(WinampModernVisSensitivity.gain(for: .skin, defaults: defaults),
                       WasabiVisStyle.Gain.builtInAnalyzer * 1.3, accuracy: 0.0001)
        XCTAssertEqual(WinampModernVisSensitivity.oscilloscopeGain(defaults: defaults),
                       WasabiVisStyle.Gain.builtInOscilloscope * 1.3, accuracy: 0.0001)
        XCTAssertNotEqual(WasabiVisStyle.Gain.builtInAnalyzer,
                          WasabiVisStyle.Gain.builtInOscilloscope)
    }

    /// Per engine and not per skin: it calibrates an engine's own scale, so a Cava turned up once
    /// stays turned up in every skin.
    func testSensitivityIsHeldPerEngine() {
        WinampModernVisSensitivity.set(.highest, for: .cava, defaults: defaults)
        XCTAssertEqual(WinampModernVisSensitivity.stored(for: .cava, defaults: defaults), .highest)
        XCTAssertEqual(WinampModernVisSensitivity.stored(for: .visClassic, defaults: defaults),
                       .normal)
    }

    func testAnUnknownSensitivityReadsAsNormal() {
        XCTAssertEqual(WinampModernVisSensitivity.from(storedValue: 42), .normal)
    }

    /// vis_classic takes its gain on the input, because the core runs its own FFT and paints its own
    /// bars. The buffer is Winamp's `visdata` — `UInt8` centred on 128 — so the excursion is scaled
    /// about that centre and clamped to the byte range rather than wrapping around it.
    func testTheVisClassicInputGainScalesAboutTheCentreAndClamps() {
        let samples: [UInt8] = [128, 168, 88, 255, 0]
        let amplified = VisClassicVisRenderer.amplified(samples, gain: 2)

        XCTAssertEqual(amplified[0], 128, "silence is the centre line, whatever the gain")
        XCTAssertEqual(amplified[1], 208, "+40 doubles to +80")
        XCTAssertEqual(amplified[2], 48, "-40 doubles to -80")
        XCTAssertEqual(amplified[3], 255, "a full-scale sample cannot exceed the byte range")
        XCTAssertEqual(amplified[4], 0)
    }

    func testAUnitInputGainLeavesTheBufferAlone() {
        let samples: [UInt8] = [0, 64, 128, 192, 255]
        XCTAssertEqual(VisClassicVisRenderer.amplified(samples, gain: 1), samples)
    }

    // MARK: - The skin's own popup, and the id that meant "nothing"

    /// **The defect this file exists for.** Our rows leave the script's command id at `0`, which is
    /// MAKI's "nothing chosen" — and a submenu parent carries `0` too, which is exactly what Big
    /// Bento's own `Spectrum Analyzer ▸` row is. Collecting `0` as a skin mode row made picking Cava
    /// select Cava and then hand the box back to the skin's engine on the same click.
    func testACommandIDOfZeroIsNeverTakenForASkinModeRow() {
        let parent = NSMenuItem(title: "Spectrum Analyzer", action: nil, keyEquivalent: "")
        parent.tag = 0
        let child = NSMenuItem(title: "Thin", action: nil, keyEquivalent: "")
        child.tag = 4711
        let submenu = NSMenu()
        submenu.addItem(child)
        parent.submenu = submenu

        XCTAssertEqual(WinampModernMainView.commandIDs(of: parent), [4711])
    }

    /// A row that carries a real command keeps it, submenu or not — that is what tells us the user
    /// asked for the skin's own engine back.
    func testARealCommandIDIsCollectedWithItsChildren() {
        let row = NSMenuItem(title: "Oscilloscope", action: nil, keyEquivalent: "")
        row.tag = 12
        let submenu = NSMenu()
        for tag in [13, 14] {
            let child = NSMenuItem(title: "\(tag)", action: nil, keyEquivalent: "")
            child.tag = tag
            submenu.addItem(child)
        }
        row.submenu = submenu

        XCTAssertEqual(Set(WinampModernMainView.commandIDs(of: row)), [12, 13, 14])
    }
}
