import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

/// NullPlayer's own windows beside a `.wmz` skin: where their colours come from, and when the skin
/// owns the surface instead.
final class WMPHostedSurfaceTests: XCTestCase {

    private func skin(_ markup: String) async throws -> WMPLoadedSkin {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8))
        ])
        return try await WMPSkinLoader().load(from: archive)
    }

    // MARK: - Palette derivation

    /// A `PLAYLIST` states the roles a list needs, and it outranks the ground a `SUBVIEW` chose for
    /// artwork to sit on — 73 corpus skins declare that background and 74 the foreground.
    func testPlaylistDeclarationsOutrankViewAndSubviewColors() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="main" width="20" height="10" backgroundColor="#101010">
        <SUBVIEW id="panel" backgroundColor="#202020"/>
        <TEXT id="caption" foregroundColor="#909090"/>
        <PLAYLIST id="pl" backgroundColor="#FFFFFF" foregroundColor="#000000"
                  itemPlayingColor="#FF0000" itemPlayingBackgroundColor="#DDDDDD"/>
        </VIEW></THEME>
        """)
        let palette = WMPSurfacePalette(skin: loaded, viewID: "main")
        XCTAssertEqual(palette.background, WMPColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(palette.text, WMPColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(palette.playingText, WMPColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(palette.playingBackground, WMPColor(red: 221, green: 221, blue: 221))
    }

    /// Without a `PLAYLIST`, the view's own ground and the first `TEXT` colour carry the palette —
    /// 93 corpus skins declare a `VIEW` background and `TEXT foregroundColor` is the most authored
    /// colour in the corpus outside the transparency keys.
    func testViewBackgroundAndTextForegroundCarryThePaletteWhenNoPlaylistDeclaresOne() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="main" width="20" height="10" backgroundColor="#123456">
        <TEXT id="caption" foregroundColor="#ABCDEF"/></VIEW></THEME>
        """)
        let palette = WMPSurfacePalette(skin: loaded, viewID: "main")
        XCTAssertEqual(palette.background, WMPColor(red: 0x12, green: 0x34, blue: 0x56))
        XCTAssertEqual(palette.text, WMPColor(red: 0xAB, green: 0xCD, blue: 0xEF))
    }

    /// The second pass over the *other* views is what makes a stock WMP template usable: its player
    /// declares nothing while its playlist view declares a full list palette.
    func testPaletteFallsBackToAnotherViewsDeclarationsForRolesThePresentedViewLeavesUnset() async throws {
        let loaded = try await skin("""
        <THEME>
        <VIEW id="main" width="20" height="10"><SUBVIEW id="panel"/></VIEW>
        <VIEW id="plView" width="20" height="10">
        <PLAYLIST id="pl" backgroundColor="#0A0A0A" foregroundColor="#00FF00"/></VIEW>
        </THEME>
        """)
        let palette = WMPSurfacePalette(skin: loaded, viewID: "main")
        XCTAssertEqual(palette.viewID, "main")
        XCTAssertEqual(palette.background, WMPColor(red: 10, green: 10, blue: 10))
        XCTAssertEqual(palette.text, WMPColor(red: 0, green: 255, blue: 0))
    }

    /// `itemPlayingColor` is not in `WMPAttributeParser`'s colour set, so it is read from the raw
    /// value — and must be rejected on exactly the values the engine rejects. `FF00FF` with no `#`
    /// is one the corpus authors and the parser refuses (W48).
    func testColorAttributesAreParsedAsStrictlyAsTheEngineDoes() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="main" width="20" height="10">
        <PLAYLIST id="pl" itemPlayingColor="00FF00" itemPlayingBackgroundColor="#00FF00"/>
        </VIEW></THEME>
        """)
        let palette = WMPSurfacePalette(skin: loaded, viewID: "main")
        XCTAssertNil(palette.playingText)
        XCTAssertEqual(palette.playingBackground, WMPColor(red: 0, green: 255, blue: 0))
    }

    /// Half the corpus declares no colour at all (96 of 180 declare any background), so a palette
    /// with nothing in it must still be a usable one — the app-authored WMP-neutral pair, never
    /// another skin family's.
    func testUndeclaredPaletteLandsOnTheAppAuthoredNeutralGround() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="main" width="20" height="10"><SUBVIEW id="panel"/></VIEW></THEME>
        """)
        let palette = WMPSurfacePalette(skin: loaded, viewID: "main")
        XCTAssertNil(palette.background)
        let style = palette.surfaceStyle
        XCTAssertEqual(style.background, WMPSurfacePalette.neutralBackground.nsColor)
        XCTAssertGreaterThanOrEqual(SkinnedSurfaceStyle.contrastRatio(style.text, style.background),
                                    SkinnedSurfaceStyle.minimumContrast)
    }

    /// The legibility rule Modern uses, applied here for a reason `.wal` does not have: a `.wms`
    /// declares colours per element, so the ground and the lettering routinely come from elements
    /// that were never drawn on each other.
    func testUnreadablePairingsAreGuardedAgainstTheGroundEachRoleIsDrawnOn() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="main" width="20" height="10">
        <PLAYLIST id="pl" backgroundColor="#000000" foregroundColor="#050505"
                  itemPlayingColor="#020202" itemPlayingBackgroundColor="#000000"/>
        </VIEW></THEME>
        """)
        let style = WMPSurfacePalette(skin: loaded, viewID: "main").surfaceStyle
        // Row text against the window background, the playing row against the same ground, and the
        // selection against the highlight — every one of them readable.
        for (foreground, background) in [(style.text, style.background),
                                         (style.currentText, style.background),
                                         (style.selectedText, style.selectionBackground)] {
            XCTAssertGreaterThanOrEqual(SkinnedSurfaceStyle.contrastRatio(foreground, background),
                                        SkinnedSurfaceStyle.minimumContrast)
        }
    }

    /// A declaration that *can* be read is never overridden: the guard's candidates are the skin's
    /// own colours, tried best-intent first.
    func testReadableDeclarationsSurviveTheGuardUnchanged() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="main" width="20" height="10">
        <PLAYLIST id="pl" backgroundColor="#000000" foregroundColor="#00CC00"/>
        </VIEW></THEME>
        """)
        let style = WMPSurfacePalette(skin: loaded, viewID: "main").surfaceStyle
        XCTAssertEqual(style.text, WMPColor(red: 0, green: 0xCC, blue: 0).nsColor)
    }

    /// Sampling is bucketed, not averaged: a player of dark chrome with one bright display must
    /// answer the chrome, not the grey between them. Transparent pixels are the window's shape and
    /// are not artwork.
    func testDominantColorAnswersTheMajorityColourAndIgnoresTransparentPixels() throws {
        var rgba: [UInt8] = []
        for index in 0..<64 {
            switch index {
            case 0..<16: rgba += [0, 0, 0, 0]           // cut-out: must not count
            case 16..<56: rgba += [40, 40, 60, 255]     // the chrome
            default: rgba += [255, 255, 0, 255]         // a bright display
            }
        }
        let data = try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba)
        let image = try WMPImageStore(provider: WMPMemoryResourceProvider(["v.png": data])).image(for: "v.png")
        let dominant = try XCTUnwrap(WMPSurfacePalette.dominantColor(of: image.image))
        XCTAssertLessThan(Int(dominant.red), 96)
        XCTAssertLessThan(Int(dominant.green), 96)
        XCTAssertGreaterThan(Int(dominant.blue), Int(dominant.red))
    }

    /// The sample only stands in for a background the markup never declared.
    func testSampledBackgroundIsOnlyUsedWhenTheMarkupDeclaresNone() async throws {
        let declared = try await skin("""
        <THEME><VIEW id="main" width="20" height="10" backgroundColor="#123456"/></THEME>
        """)
        var palette = WMPSurfacePalette(skin: declared, viewID: "main")
        palette.sampledBackground = WMPColor(red: 200, green: 0, blue: 0)
        XCTAssertEqual(palette.surfaceStyle.background, WMPColor(red: 0x12, green: 0x34, blue: 0x56).nsColor)

        var undeclared = WMPSurfacePalette(viewID: "main")
        undeclared.sampledBackground = WMPColor(red: 200, green: 0, blue: 0)
        XCTAssertEqual(undeclared.surfaceStyle.background, WMPColor(red: 200, green: 0, blue: 0).nsColor)
    }

    // MARK: - Surfaces the skin owns

    /// 171 of the 180 corpus skins declare a playlist and 164 an equaliser, so NullPlayer's are the
    /// fallback: a skin that declares one must be recognised as owning it.
    func testSkinOwnedPlaylistAndEqualizerAreRecognisedPerView() async throws {
        let loaded = try await skin("""
        <THEME>
        <VIEW id="main" width="20" height="10"><EQUALIZERSETTINGS id="eq"/></VIEW>
        <VIEW id="plView" width="20" height="10"><PLAYLIST id="pl"/></VIEW>
        </THEME>
        """)
        let surfaces = WMPSkinSurfaces(skin: loaded)
        XCTAssertTrue(surfaces.provides(.playlist))
        XCTAssertTrue(surfaces.provides(.equalizer))
        XCTAssertEqual(surfaces.viewIDs(for: .playlist), ["plView"])
        XCTAssertEqual(surfaces.viewIDs(for: .equalizer), ["main"])
        XCTAssertTrue(surfaces.view("MAIN", provides: .equalizer))
        XCTAssertFalse(surfaces.view("main", provides: .playlist))
        XCTAssertFalse(surfaces.view(nil, provides: .playlist))
    }

    /// `ITEMSPLAYLIST` is a playlist the object model does not model yet — Corona's drawer is one —
    /// so a kind-only test would report that skin as owning no playlist and open ours on top of it.
    /// What decides the routing is what the skin declares, not how much of it the engine hosts.
    func testUnmodelledPlaylistTagsStillCountAsSkinOwned() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="main" width="20" height="10">
        <SUBVIEW id="drawer"><ITEMSPLAYLIST id="pl"/></SUBVIEW></VIEW></THEME>
        """)
        XCTAssertTrue(WMPSkinSurfaces(skin: loaded).view("main", provides: .playlist))
    }

    /// **Recognising `ITEMSPLAYLIST` for routing is only half of it — it has to become a widget.**
    /// W93 stood NullPlayer's playlist aside whenever the skin declared one, and `ITEMSPLAYLIST`
    /// fell to `.unknown`, so `corona` users got an empty drawer instead of a second window: the
    /// better failure of the two, and still a failure. 13 of the 179 measured archives declare one
    /// and **not one of them declares a `PLAYLIST` beside it**, so it is the only playlist those
    /// skins have (W97).
    func testAnItemsPlaylistIsAPlaylistWidgetAndNotJustASkinOwnedSurface() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="main" width="300" height="200">
        <ITEMSPLAYLIST id="ipl" left="10" top="10" width="200" height="150"/></VIEW></THEME>
        """)
        let node = try XCTUnwrap(loaded.graph.allNodes.first { $0.xmlID == "ipl" })
        XCTAssertEqual(node.kind, .playlist,
                       "the authored tag is retained separately, so mapping the kind loses nothing")
        XCTAssertEqual(node.authoredTagName.uppercased(), "ITEMSPLAYLIST")
    }

    func testDropdownPlaylistCountsAndASkinDeclaringNeitherSurfaceOwnsNothing() async throws {
        let dropdown = try await skin("""
        <THEME><VIEW id="main" width="20" height="10"><DROPDOWNPLAYLIST id="pl"/></VIEW></THEME>
        """)
        XCTAssertTrue(WMPSkinSurfaces(skin: dropdown).provides(.playlist))

        let bare = try await skin("""
        <THEME><VIEW id="main" width="20" height="10"><SUBVIEW id="panel"/></VIEW></THEME>
        """)
        let surfaces = WMPSkinSurfaces(skin: bare)
        XCTAssertFalse(surfaces.provides(.playlist))
        XCTAssertFalse(surfaces.provides(.equalizer))
        XCTAssertTrue(WMPSkinSurfaces.empty.viewIDs(for: .playlist).isEmpty)
    }
}
