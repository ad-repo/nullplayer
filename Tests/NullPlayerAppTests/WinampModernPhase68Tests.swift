import XCTest
@testable import NullPlayer

/// Phase 68 (backlog B48) — text NullPlayer draws on its own surfaces can always be read.
///
/// Reported live three times in one session — *"the playlist highlighter is white and the text
/// underneath is also light"*, *"black titlebars with black title text"*, *"white text on a light
/// background"* — and then measured across all 36 installed skins: **23 drew an unreadable selected
/// row** (nine at exactly 1.00:1, text and highlight the same colour) and 5 an unreadable window
/// title.
///
/// One cause, three faces. `WasabiPalette` resolves every role from its own independent id chain and
/// nothing ever checked that a foreground and the background it lands on can be seen together, so a
/// skin declaring two colour families gets a mongrel pairing. Big Bento is the measured case: its
/// highlight comes from `studio.list.item.selected` (orange, `color.selected.active`) and its row
/// text from `wasabi.list.text.selected` (pale blue-grey, `color.display`) — **1.06:1**, and a
/// *current* row over that same bar is orange on orange at **1.00:1**. Winamp never hits this
/// because its Media Library is a native Win32 list, where the OS guarantees a legible selection. We
/// draw the list ourselves, so the guarantee has to be ours.
///
/// Two things this deliberately does **not** do, both asserted below:
///
/// - **It never touches classic.** `PlaylistColors.selectedText` defaults to `currentText`, which is
///   exactly what the draw sites read before the field existed, so a `.wsz` skin is a zero-pixel
///   change and `SkinLoader` needed no edit.
/// - **It never overrules a skin that gave us something usable.** The candidate chain is the skin's
///   own colours, best-intent first; black/white is reached only when every one of them would be
///   invisible. Formamp is the boundary case and was closed as won't-do: its window background is
///   `(0,0,0,206)` — translucent by design — and its song title is *skin-declared* at 80,80,80.
///   Guarding text a skin spelled out for its own controls is overruling the author, not fixing our
///   legibility.
final class WinampModernPhase68Tests: XCTestCase {

    private func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(deviceRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    /// The palette Big Bento Modern actually resolves, from `WINAMP_MODERN_RENDER_PALETTE=1`.
    private var bigBentoPalette: WasabiPalette {
        WasabiPalette(listText: rgb(147, 175, 185),
                      currentText: rgb(255, 150, 32),
                      selectionText: rgb(147, 175, 185),
                      selectionBackground: rgb(255, 150, 32),
                      contentBackground: rgb(55, 57, 64),
                      treeText: rgb(147, 175, 185),
                      treeSelection: rgb(255, 150, 32))
    }

    // MARK: - The primitives

    func testContrastRatioSpansTheFullWCAGRange() {
        XCTAssertEqual(WinampModernSurfaceStyle.contrastRatio(.black, .white), 21, accuracy: 0.01)
        XCTAssertEqual(WinampModernSurfaceStyle.contrastRatio(.white, .white), 1, accuracy: 0.001)
        // The nine skins measured at 1.00:1 are exactly this: one colour drawn on itself.
        let orange = rgb(255, 150, 32)
        XCTAssertEqual(WinampModernSurfaceStyle.contrastRatio(orange, orange), 1, accuracy: 0.001)
    }

    func testBigBentoIsTheMeasuredMongrelPairing() {
        // Both halves of the report, in numbers: the pairing the skin's own chains produce.
        let palette = bigBentoPalette
        XCTAssertLessThan(WinampModernSurfaceStyle.contrastRatio(palette.selectionText,
                                                                 palette.selectionBackground), 1.5)
        XCTAssertLessThan(WinampModernSurfaceStyle.contrastRatio(palette.currentText,
                                                                 palette.selectionBackground), 1.5)
    }

    func testLegibleTakesTheFirstCandidateThatClears() {
        let background = rgb(255, 150, 32)
        let unreadable = rgb(147, 175, 185)
        let readable = rgb(55, 57, 64)
        let picked = WinampModernSurfaceStyle.legible(preferring: [unreadable, readable],
                                                      on: background)
        XCTAssertEqual(picked, readable)
    }

    func testLegibleKeepsASkinsOwnColourWhenItAlreadyClears() {
        // The whole point of the ordering: a skin that gives us something usable is never overridden.
        let background = rgb(0, 0, 199)
        let green = rgb(0, 255, 0)
        XCTAssertEqual(WinampModernSurfaceStyle.legible(preferring: [green, .white], on: background),
                       green)
    }

    func testLegibleFallsBackToBlackOrWhiteAndTheFallbackAlwaysClears() {
        for background in [rgb(255, 150, 32), rgb(20, 19, 19), rgb(128, 128, 128), rgb(237, 237, 237)] {
            // Every candidate is the background itself, so nothing the "skin" named can be read.
            let picked = WinampModernSurfaceStyle.legible(preferring: [background, background],
                                                          on: background)
            XCTAssertTrue(picked == NSColor.black || picked == NSColor.white)
            XCTAssertGreaterThanOrEqual(
                WinampModernSurfaceStyle.contrastRatio(picked, background),
                WinampModernSurfaceStyle.minimumContrast,
                "no background may leave both extremes unreadable")
        }
    }

    func testCompositedFlattensAHalfAlphaFillOntoWhatIsBehindIt() {
        // `PlexBrowserView`'s focused search field draws over a half-alpha highlight; judging the
        // written colour instead of the composited one leaves that state unreadable while the opaque
        // selection row is fixed.
        let flattened = WinampModernSurfaceStyle.composited(NSColor(deviceRed: 1, green: 1, blue: 1,
                                                                    alpha: 0.5),
                                                            over: .black)
        XCTAssertEqual(flattened.usingColorSpace(.deviceRGB)!.redComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(flattened.usingColorSpace(.deviceRGB)!.alphaComponent, 1, accuracy: 0.001)
    }

    // MARK: - The guarantee, on the style

    func testSelectedTextIsReadableOnTheHighlightForBigBento() {
        let style = WinampModernSurfaceStyle(palette: bigBentoPalette)
        XCTAssertGreaterThanOrEqual(
            WinampModernSurfaceStyle.contrastRatio(style.selectedText, style.selectionBackground),
            WinampModernSurfaceStyle.minimumContrast)
    }

    func testEveryRoleAndBackgroundPairOfEveryMeasuredPaletteClears() {
        // The three shapes the corpus produced: two colour families (Bento), a single near-black
        // family (Formamp), and the green-on-blue fallback.
        let palettes = [bigBentoPalette,
                        WasabiPalette(listText: rgb(80, 80, 80), currentText: rgb(120, 120, 120),
                                      selectionText: rgb(80, 80, 80),
                                      selectionBackground: rgb(20, 19, 19),
                                      contentBackground: rgb(20, 19, 19),
                                      treeText: rgb(80, 80, 80), treeSelection: rgb(20, 19, 19)),
                        WasabiPalette.fallback]
        for palette in palettes {
            let style = WinampModernSurfaceStyle(palette: palette)
            XCTAssertGreaterThanOrEqual(
                WinampModernSurfaceStyle.contrastRatio(style.selectedText, style.selectionBackground),
                WinampModernSurfaceStyle.minimumContrast)
            XCTAssertGreaterThanOrEqual(
                WinampModernSurfaceStyle.contrastRatio(style.legibleText(style.text, on: style.barBackground),
                                                       style.barBackground),
                WinampModernSurfaceStyle.minimumContrast)
            XCTAssertGreaterThanOrEqual(
                WinampModernSurfaceStyle.contrastRatio(style.legibleDimText(on: style.barBackground),
                                                       style.barBackground),
                WinampModernSurfaceStyle.minimumContrast)
        }
    }

    func testDimTextStaysDimmerThanThePrimaryWhereverAWeakerDimStillClears() {
        // Guarding `dimText` naively snaps it to full strength on nearly every skin, because it is a
        // 40% blend toward the background — that would erase the active/inactive title distinction
        // corpus-wide to fix the five skins where the inactive title is invisible.
        let style = WinampModernSurfaceStyle(palette: bigBentoPalette)
        let dim = style.legibleDimText(on: style.barBackground)
        XCTAssertNotEqual(dim, style.text)
        XCTAssertLessThan(
            WinampModernSurfaceStyle.contrastRatio(dim, style.barBackground),
            WinampModernSurfaceStyle.contrastRatio(style.text, style.barBackground),
            "a secondary label must stay quieter than the primary it sits beside")
    }

    func testAFallbackSkinIsUnchanged() {
        // Winamp's own green-on-blue already clears, so nothing about the default look moves.
        let style = WinampModernSurfaceStyle.fallback
        XCTAssertEqual(style.selectedText, style.currentText)
    }

    // MARK: - Classic is out of reach

    func testPlaylistColorsSelectedTextDefaultsToCurrentText() {
        // The zero-pixel guarantee for `.wsz` skins: the four draw sites read `selectedText`, and for
        // every classic skin that is the `currentText` they read before.
        let colors = PlaylistColors(normalText: .green, currentText: .white, normalBackground: .black,
                                    selectedBackground: .blue, font: .systemFont(ofSize: 8))
        XCTAssertEqual(colors.selectedText, colors.currentText)
        XCTAssertEqual(PlaylistColors.default.selectedText, PlaylistColors.default.currentText)
    }

    func testTheStyleIsTheOnlyThingThatEverSuppliesADifferentSelectedText() {
        // `SkinLoader` never passes the argument, so a classic skin cannot acquire a guarded colour
        // however odd its `pledit.txt` is.
        let style = WinampModernSurfaceStyle(palette: bigBentoPalette)
        XCTAssertEqual(style.playlistColors.selectedText, style.selectedText)
        XCTAssertNotEqual(style.playlistColors.selectedText, style.playlistColors.currentText)
    }
}
