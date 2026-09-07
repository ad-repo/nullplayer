import XCTest
@testable import NullPlayer

/// Phase 71 (B50) — Text Size: how large NullPlayer draws its **own** text inside a `.wal` skin.
///
/// The rule this replaces read the median `fontsize` declared near the playlist holder, and it could
/// not separate the two skins it had to: Big Bento Modern declares 22 and wants the large rows, Defix
/// Hi-END 200 declares 19/20 in a 406×355 window and does not. **Window size separates them
/// cleanly**, so `auto` is keyed on the hosting layout's canvas height and on nothing the skin says
/// about text. What these tests pin is that rule's two ends, the one place an explicit choice is
/// deliberately *not* clamped, and the round trip through per-skin storage.
final class WinampModernPhase71Tests: XCTestCase {

    private func makeConfiguration(_ name: String = #function) -> WinampModernConfiguration {
        let suite = "WinampModernPhase71.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return WinampModernConfiguration(namespace: "TestSkin", defaults: defaults)
    }

    // MARK: - The auto rule

    /// Defix Hi-END 200's playlist window. 355/48 is 7.4, below the Wasabi default, so it clamps up to
    /// 11 — which is exactly the size it drew at before `b2980d3a` regressed it.
    func testAutoClampsASmallWindowToTheWasabiDefault() {
        XCTAssertEqual(WinampModernTextScale.auto.cellPixelHeight(canvasHeight: 355), 11, accuracy: 0.001)
        XCTAssertEqual(WinampModernTextScale.auto.contentScale(canvasHeight: 355), 1, accuracy: 0.001)
    }

    /// Big Bento Modern. 878/48 is 18.29, so it lands on the cap — the size its playlist draws at
    /// today, unchanged by this rule.
    func testAutoClampsALargeWindowToTheCap() {
        XCTAssertEqual(WinampModernTextScale.auto.cellPixelHeight(canvasHeight: 878), 18, accuracy: 0.001)
    }

    /// Between the ends the rule is plain arithmetic: Defix's 800×600 SUI comes out mild rather than
    /// jumping to either clamp.
    func testAutoIsProportionalBetweenTheClamps() {
        XCTAssertEqual(WinampModernTextScale.auto.cellPixelHeight(canvasHeight: 600), 12.5, accuracy: 0.001)
    }

    /// A canvas that is zero or nonsense must land on the default, not on a NaN row height that would
    /// divide the playlist's hit testing by zero.
    func testAutoSurvivesADegenerateCanvas() {
        XCTAssertEqual(WinampModernTextScale.auto.cellPixelHeight(canvasHeight: 0), 11, accuracy: 0.001)
        XCTAssertEqual(WinampModernTextScale.auto.cellPixelHeight(canvasHeight: .nan), 11, accuracy: 0.001)
    }

    // MARK: - An explicit choice

    /// The 18px cap belongs to `auto`, which is guessing. A user who picks 200% is not, so their
    /// choice beats it — and it does not depend on the window at all.
    func testExplicitChoiceIgnoresTheAutoCapAndTheCanvas() {
        XCTAssertEqual(WinampModernTextScale.p200.cellPixelHeight(canvasHeight: 355), 22, accuracy: 0.001)
        XCTAssertEqual(WinampModernTextScale.p200.cellPixelHeight(canvasHeight: 878), 22, accuracy: 0.001)
        XCTAssertEqual(WinampModernTextScale.p200.contentScale(canvasHeight: 355), 2, accuracy: 0.001)
    }

    func testOneHundredPercentIsTheWasabiDefault() {
        XCTAssertEqual(WinampModernTextScale.p100.cellPixelHeight(canvasHeight: 878), 11, accuracy: 0.001)
        XCTAssertEqual(WinampModernTextScale.p100.contentScale(canvasHeight: 878), 1, accuracy: 0.001)
    }

    /// What the `Auto (n%)` menu entry shows.
    func testResolvedPercentNamesWhatAutoAmountsTo() {
        XCTAssertEqual(WinampModernTextScale.resolvedPercent(canvasHeight: 355), 100)
        XCTAssertEqual(WinampModernTextScale.resolvedPercent(canvasHeight: 878), 164)
    }

    // MARK: - Per-skin storage

    func testUnsetSkinStateReadsAsAuto() {
        XCTAssertEqual(WinampModernSkinState.textScale(in: makeConfiguration()), .auto)
    }

    func testSkinStateRoundTripsAnExplicitValue() {
        let configuration = makeConfiguration()
        WinampModernSkinState.setTextScale(.p175, in: configuration)
        XCTAssertEqual(WinampModernSkinState.textScale(in: configuration), .p175)
    }

    /// `0` is a legal stored value, not the "never set" sentinel — so a user who goes 175% → Auto is
    /// stored as Auto rather than silently keeping 175%.
    func testAutoChosenAfterAnExplicitValueIsStored() {
        let configuration = makeConfiguration()
        WinampModernSkinState.setTextScale(.p175, in: configuration)
        WinampModernSkinState.setTextScale(.auto, in: configuration)
        XCTAssertEqual(WinampModernSkinState.textScale(in: configuration), .auto)
    }

    /// A percent the menu can no longer show reads as Auto rather than resurrecting a size nothing
    /// can now select.
    func testAnUnknownStoredPercentReadsAsAuto() {
        let configuration = makeConfiguration()
        configuration.setInteger(133, section: WinampModernSkinState.textSection,
                                 key: WinampModernSkinState.textSizeKey)
        XCTAssertEqual(WinampModernSkinState.textScale(in: configuration), .auto)
    }

    /// Per skin, so sizing Bento's text says nothing about Defix.
    func testTextSizeIsScopedPerSkin() {
        let suite = "WinampModernPhase71.scoping.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let bento = WinampModernConfiguration(namespace: "BigBentoModern", defaults: defaults)
        let defix = WinampModernConfiguration(namespace: "Defix", defaults: defaults)

        WinampModernSkinState.setTextScale(.p175, in: bento)

        XCTAssertEqual(WinampModernSkinState.textScale(in: bento), .p175)
        XCTAssertEqual(WinampModernSkinState.textScale(in: defix), .auto)
    }
}
