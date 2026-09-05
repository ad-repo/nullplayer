import AppKit
import XCTest
@testable import NullPlayer

/// B130 — every playlist row in every `.wal` skin drew in a console font, a size too small.
///
/// Reported as *"in cpro2_bento and other skins it looks like it might be falling back to some type
/// of system/console font"*. It was, and two independent faults stacked:
///
/// 1. **No skin declares a list font.** `drawSurfaceText` looks up `pledit.font`, `wasabi.list.font`
///    and `studio.list.font`, and across all 73 `.wal` files on hand — the cPro family, Anaheim, Big
///    Bento, Winamp's own `winampmodern566.wal`, and NullPlayer's bundled `NullPlayer-Black.wal` —
///    **not one declares any of the three**. They declare the matching *colours* (`wasabi.list.text`,
///    `wasabi.list.background`) and no font at all. So the identifier handed down was always `nil`,
///    and `WasabiTextMetrics.resolvedFont` answered with the monospaced fallback it keeps for a name
///    that resolved to nothing. An **absent** declaration is not a **failed** one: Winamp supplies a
///    proportional default there, and these skins name `font="Arial"` on their own playlist windows'
///    text besides (Anaheim, on all four).
/// 2. **The point size was converted twice.** `pixelHeightToPointSize` (0.8) is a *GDI* rule for a
///    skin's own `fontsize=`; a host-drawn list has none, and `defaultPixelHeight` is a cell height we
///    chose ourselves. Pushing our number through someone else's unit conversion made an 11px cell
///    draw at 8.8pt. The monospaced fallback hid it — its x-height at a given point size is far larger
///    than Arial's — so fixing (1) is what made (2) visible.
final class WinampModernB130Tests: XCTestCase {

    // MARK: - The default face

    /// The fallback the undeclared case now resolves to has to exist and has to be proportional.
    /// Arial is the whole point: monospaced is what the bug looked like.
    func testTheDefaultListFaceIsInstalledAndProportional() throws {
        let resolved = try XCTUnwrap(NSFontManager.shared.font(withFamily: "Arial", traits: [],
                                                               weight: 5, size: 11),
                                     "the undeclared-list-font default must resolve on this system")
        XCTAssertFalse(resolved.isFixedPitch,
                       "a proportional face is the fix; a fixed-pitch one is the defect")
    }

    /// The monospaced fallback stays where it belongs — a name the skin *stated* that resolved to
    /// nothing still lands there, because that is a diagnostic and not a default.
    func testTheMonospacedFallbackIsStillFixedPitch() {
        XCTAssertTrue(NSFont.monospacedSystemFont(ofSize: 11, weight: .regular).isFixedPitch)
    }

    // MARK: - The size

    /// The GDI ratio is measured against a shipped reference render (Love is War Miku's own
    /// screenshot) and must not move to satisfy a host surface that never had a `fontsize` to convert.
    func testTheSkinDeclaredConversionIsUntouched() {
        XCTAssertEqual(WasabiTextMetrics.pixelHeightToPointSize, 0.8, accuracy: 0.0001)
    }

    /// The host cell conversion is its own number, and larger than the GDI one — the double
    /// conversion is what made the list a size too small.
    func testHostListTextIsNotConvertedByTheGDIRatio() {
        XCTAssertGreaterThan(WasabiSceneRenderer.playlistCellToPointSize,
                             WasabiTextMetrics.pixelHeightToPointSize)
    }

    /// Why 0.9 and not 1.0: a row is its cell plus 10%, so the line the point size produces has to fit
    /// inside that row. At a ratio of 1.0 an 11px cell draws an ~12.7px line into a 12px row and the
    /// descenders meet the row beneath. Checked across the range `auto` can reach (11px floor to the
    /// 18px cap) and at the explicit scales.
    func testEveryCellHeightDrawsALineThatFitsItsRow() throws {
        let family = try XCTUnwrap(NSFontManager.shared.font(withFamily: "Arial", traits: [],
                                                             weight: 5, size: 11))
        for cell in [11.0, 12.5, 13.75, 16.5, 18.0, 22.0] {
            let pointSize = cell * WasabiSceneRenderer.playlistCellToPointSize
            let rowHeight = (cell * 1.1).rounded()
            let font = try XCTUnwrap(NSFont(descriptor: family.fontDescriptor, size: pointSize))
            let line = ceil(font.ascender - font.descender)
            XCTAssertLessThanOrEqual(line, rowHeight,
                                     "a \(cell)px cell draws a \(line)px line into a \(rowHeight)px row")
        }
    }

    /// The sizes the Text Size menu actually produces, so a change to either end of the chain has to
    /// be deliberate. `auto` on a small skin is the case the report was made against.
    func testTheTextSizeMenuProducesTheExpectedPointSizes() {
        let ratio = WasabiSceneRenderer.playlistCellToPointSize
        // auto, any window under 528px tall — cPro2 Bento, Anaheim, every small skin.
        XCTAssertEqual(WinampModernTextScale.auto.cellPixelHeight(canvasHeight: 400) * ratio,
                       9.9, accuracy: 0.0001)
        // auto, at the cap — Big Bento's 878px window.
        XCTAssertEqual(WinampModernTextScale.auto.cellPixelHeight(canvasHeight: 878) * ratio,
                       16.2, accuracy: 0.0001)
        // An explicit choice is not capped.
        XCTAssertEqual(WinampModernTextScale.p125.cellPixelHeight(canvasHeight: 400) * ratio,
                       12.375, accuracy: 0.0001)
    }
}
