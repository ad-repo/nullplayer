import XCTest
import AppKit
@testable import NullPlayer

/// Phase 16 — the surfaces NullPlayer draws itself, themed from the `.wal` skin.
///
/// The library embedded in a skin's holder, and the playlist / equalizer / library windows opened
/// when a skin declares none of its own, used to be painted by the *classic* renderer: `.wsz` sprite
/// sheets, the 5×6 bitmap font, and `skin.playlistColors` from a skin the user is not even looking
/// at. `WinampModernSurfaceStyle` replaces that with the loaded skin's own palette.
///
/// Two invariants carry the whole change and are what these tests pin:
///
/// 1. **The advance is unchanged.** The views lay themselves out as
///    `text.count * SkinElements.TextFont.charWidth * scale`, in ~77 places in the browser alone. If
///    the replacement font measured differently, every one of those boxes would be wrong.
/// 2. **A partial palette still produces a usable surface.** Real skins declare three roles, not
///    seven, so the chrome roles are blends of what the skin *did* declare — never a fixed grey,
///    which would be invisible on a skin of that shade.
final class WinampModernPhase16Tests: XCTestCase {

    // MARK: - Text metrics

    func testReplacementFontAdvanceMatchesTheClassicCharacterCell() {
        for scale in [CGFloat(0.8), 1, 1.4, 2, 3] {
            let font = WinampModernSurfaceStyle.font(scale: scale)
            let attributes = WinampModernSurfaceStyle.attributes(scale: scale, color: .white)
            let sample = "LIBRARY 0123"
            let measured = (sample as NSString).size(withAttributes: attributes).width
            let expected = WinampModernSurfaceStyle.measuredWidth(sample, scale: scale)
            XCTAssertEqual(measured, expected, accuracy: 0.5,
                           "scale \(scale): a layout computed from charWidth would not fit its own text")
            XCTAssertTrue(font.pointSize > 0)
        }
    }

    func testMeasuredWidthIsTheClassicCellWidth() {
        XCTAssertEqual(WinampModernSurfaceStyle.measuredWidth("ABC", scale: 2),
                       3 * SkinElements.TextFont.charWidth * 2, accuracy: 0.0001)
        XCTAssertEqual(WinampModernSurfaceStyle.measuredWidth("", scale: 1), 0, accuracy: 0.0001)
    }

    func testDrawingTextIsBoundedAndReportsItsOwnAdvance() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 40, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let advance = WinampModernSurfaceStyle.drawText("PLAYLIST", at: NSPoint(x: 4, y: 4), scale: 1,
                                                        color: .white, in: context)
        XCTAssertEqual(advance, WinampModernSurfaceStyle.measuredWidth("PLAYLIST", scale: 1),
                       accuracy: 0.0001)
    }

    // MARK: - Derivation from a partial palette

    /// The documented "skin declares nothing" case: Winamp's own green-on-black with a blue
    /// selection, and chrome roles that are visible against it rather than a fixed grey.
    func testChromeRolesAreDerivedFromWhateverTheSkinDeclared() {
        let style = WinampModernSurfaceStyle(palette: .fallback)
        XCTAssertEqual(style.background, WasabiPalette.contentBackgroundFallback)
        XCTAssertEqual(style.text, WasabiPalette.listTextFallback)

        // Every derived role must sit strictly between the two ends it was blended from, or it is
        // either invisible against the background or indistinguishable from the text.
        for role in [style.barBackground, style.border, style.divider] {
            let brightness = Self.brightness(role)
            XCTAssertGreaterThan(brightness, Self.brightness(style.background))
            XCTAssertLessThan(brightness, Self.brightness(style.text))
        }
        XCTAssertLessThan(Self.brightness(style.dimText), Self.brightness(style.text),
                          "secondary text must read as secondary")
    }

    /// The same derivation on a *light* skin has to move the other way. A fixed grey chrome would be
    /// correct on one of these two skins and invisible on the other.
    func testDerivationFollowsTheSkinsOwnDirection() {
        let light = WasabiPalette(listText: .black, currentText: .black, selectionText: .white,
                                  selectionBackground: NSColor(deviceRed: 0.2, green: 0.4, blue: 0.9, alpha: 1),
                                  contentBackground: .white, treeText: .black,
                                  treeSelection: NSColor(deviceRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        let style = WinampModernSurfaceStyle(palette: light)
        XCTAssertLessThan(Self.brightness(style.barBackground), Self.brightness(style.background),
                          "on a light skin the chrome must get darker, not lighter")
        XCTAssertFalse(style.prefersDarkAppearance)
        XCTAssertTrue(WinampModernSurfaceStyle.fallback.prefersDarkAppearance)
    }

    func testPlaylistColorsCarryThePaletteIntoTheClassicDrawingRoutines() {
        let style = WinampModernSurfaceStyle.fallback
        let colors = style.playlistColors
        XCTAssertEqual(colors.normalText, style.text)
        XCTAssertEqual(colors.currentText, style.currentText)
        XCTAssertEqual(colors.normalBackground, style.background)
        XCTAssertEqual(colors.selectedBackground, style.selectionBackground)
    }

    func testBlendEndpointsAreExact() {
        let a = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        let b = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        XCTAssertEqual(Self.brightness(WinampModernSurfaceStyle.blend(a, toward: b, by: 0)), 0, accuracy: 0.001)
        XCTAssertEqual(Self.brightness(WinampModernSurfaceStyle.blend(a, toward: b, by: 1)), 1, accuracy: 0.001)
        // Out-of-range fractions clamp rather than extrapolating into an invalid colour.
        XCTAssertEqual(Self.brightness(WinampModernSurfaceStyle.blend(a, toward: b, by: 4)), 1, accuracy: 0.001)
    }

    // MARK: - Mode gating

    /// The whole change is opt-in per mode: outside `winampModern` the views must take their
    /// untouched classic path, and inside it they must still do so until a skin has actually loaded.
    @MainActor
    func testNoStyleOutsideWinampModernMode() {
        let manager = WindowManager.shared
        let original = manager.uiMode
        defer { manager.uiMode = original }
        for mode in PlayerUIMode.allCases where mode.controllerFamily != .winampModern {
            manager.uiMode = mode
            XCTAssertNil(manager.winampModernSurfaceStyle, "\(mode) must keep the classic drawing")
        }
    }

    private static func brightness(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0 }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }
}
