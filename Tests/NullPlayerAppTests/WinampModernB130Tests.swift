import AppKit
import XCTest
import ZIPFoundation
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

    // MARK: - B131 — the unresolvable case substitutes proportionally too, and says so

    /// The fixed-pitch fallback for a *stated* name that resolved to nothing was defended as a
    /// diagnostic. It was not one — nothing recorded it. Both ways in now substitute proportionally:
    /// a `<truetypefont>` whose file is absent (the whole cPro family's `font.ttf`) and a family name
    /// this system does not have (Calibri, Segoe UI, `ariblk`).
    func testAnUnresolvableFontSubstitutesProportionally() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <elements>
            <truetypefont id="player.missingfont" file="NOTSHIPPED.ttf"/>
          </elements>
          <container id="main"><layout id="normal" w="80" h="20"/></container>
        </WasabiXML>
        """)
        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }

        for identifier in ["player.missingfont", "NoSuchFamilyXYZ", "Calibri"] {
            let font = try XCTUnwrap(metrics.font(identifier: identifier, size: 12),
                                     "\(identifier) still resolves to something drawable")
            XCTAssertFalse(font.isFixedPitch,
                           "\(identifier) substitutes proportionally, the way GDI does with a name "
                           + "it cannot match")
        }
    }

    /// And the substitution is *recorded*, which is the half that was missing. A person debugging a
    /// skin reads this; nobody could read a monospaced rendering.
    func testAnUnresolvableFontRecordsADiagnostic() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <elements>
            <truetypefont id="player.missingfont" file="NOTSHIPPED.ttf"/>
          </elements>
          <container id="main"><layout id="normal" w="80" h="20"/></container>
        </WasabiXML>
        """)
        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }
        _ = metrics.font(identifier: "player.missingfont", size: 12)
        _ = metrics.font(identifier: "NoSuchFamilyXYZ", size: 12)

        let recorded = loaded.runtime.diagnostics.filter { $0.code == .unresolvedFont }
        XCTAssertEqual(recorded.count, 2, "one per unresolvable name")
        XCTAssertTrue(recorded.allSatisfy { $0.severity == .warning },
                      "the string still draws, so this is not an error")
        // The two failures are reported differently: a declared font whose file never shipped is not
        // "you named a font nobody has", and the corpus is full of the former.
        XCTAssertTrue(recorded.contains { $0.message.contains("player.missingfont")
                                          && $0.message.contains("not in the archive") },
                      "a declared <truetypefont> with no file is reported as exactly that")
        XCTAssertTrue(recorded.contains { $0.message.contains("NoSuchFamilyXYZ")
                                          && $0.message.contains("installed") },
                      "an uninstalled family name is reported as exactly that")
    }

    /// The host asks for the substitute family by name for its own undeclared-list-font default. A
    /// system without Arial is our problem, not the skin's, and must not be filed against one.
    func testTheHostsOwnDefaultIsNeverFiledAgainstTheSkin() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="80" h="20"/></container></WasabiXML>
        """)
        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }
        _ = metrics.font(identifier: WasabiTextMetrics.substituteFamily, size: 12)

        XCTAssertTrue(loaded.runtime.diagnostics.allSatisfy { $0.code != .unresolvedFont },
                      "the host's own default is not a skin defect")
    }

    /// A resolvable name is untouched — no substitution, no diagnostic.
    func testAResolvableFontIsLeftAlone() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="80" h="20"/></container></WasabiXML>
        """)
        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }
        let mono = try XCTUnwrap(metrics.font(identifier: "Monaco", size: 12))

        XCTAssertTrue(mono.isFixedPitch,
                      "a skin that genuinely asks for a fixed-pitch face still gets one")
        XCTAssertTrue(loaded.runtime.diagnostics.allSatisfy { $0.code != .unresolvedFont })
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

    // MARK: - Harness

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB130Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B130-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
