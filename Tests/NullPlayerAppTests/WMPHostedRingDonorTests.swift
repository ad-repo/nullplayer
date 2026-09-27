import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// **Which view in a `.wmz` lends its ring to NullPlayer's own windows** — the two rules that
/// decide it where a skin dresses more than one of its windows in the same bitmaps (W179).
///
/// `Combat_Flight_Simulator_3` is the archive behind both. It builds its playlist *and* its video
/// view out of `vid_*.png`, so the two score identically, and it declares `videoView` first — which
/// is how the library came to wear the film drawer's BRIGHTNESS/CONTRAST/HUE/SATURATION plate
/// across its bottom bar, reported 2026-09-15 with a capture. Corpus effect of both rules together,
/// measured at 543x890 scale 2 over the 185 installed archives: **13 `HOSTED-FRAME` lines move
/// across 12 archives, every one of them `video → playlist`**, each holding or improving its
/// `gaps=`. The corner rule alone moves **nothing**.
final class WMPHostedRingDonorTests: XCTestCase {

    private func skin(_ markup: String) async throws -> WMPLoadedSkin {
        let entries = [WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8)),
                       WMPTestArchiveEntry("piece.png", data: try Self.piece())]
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private static func piece() throws -> Data {
        let side = 24
        return try WMPSkinTestSupport.encodedImage(
            width: side, height: side,
            rgba: [UInt8](repeating: 255, count: side * side * 4))
    }

    /// The three corners a fixture never varies, so each test states only the one under test.
    private static let otherCorners = """
        <SUBVIEW horizontalAlignment="right" verticalAlignment="top"    backgroundImage="piece.png"/>
        <SUBVIEW horizontalAlignment="left"  verticalAlignment="bottom" backgroundImage="piece.png"/>
        <SUBVIEW horizontalAlignment="right" verticalAlignment="bottom" backgroundImage="piece.png"/>
        """

    private static let listClient = """
        <SUBVIEW id="client" horizontalAlignment="stretch" verticalAlignment="stretch"
                 left="10" top="10" width="180" height="180">
          <PLAYLIST id="list" left="0" top="0" width="180" height="180"/>
        </SUBVIEW>
        """

    private static let videoClient = """
        <SUBVIEW id="client" horizontalAlignment="stretch" verticalAlignment="stretch"
                 left="10" top="10" width="180" height="180">
          <VIDEO id="film" left="0" top="0" width="180" height="180"/>
        </SUBVIEW>
        """

    // MARK: - Refusing a corner is only right when the refusal is free

    /// **The reported shape.** The corner *is* the plate — `vid_top_left.png`, 190x29, with the
    /// repeat and shuffle buttons drawn on top of it as children with images of their own — and
    /// nothing else claims the slot. Refusing the piece emptied the corner, which failed the
    /// four-corner guard, which withdrew the whole view as a candidate and handed the skin's ring
    /// to its video view instead.
    func testACornerPlateCarryingTheTransportStillLendsItsRing() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left" verticalAlignment="top" backgroundImage="piece.png">
            <BUTTON id="loop" left="11" top="0" width="30" height="29" image="piece.png"
                    onClick="player.settings.setMode('loop',down);"/>
          </SUBVIEW>
          \(Self.otherCorners)
          \(Self.listClient)
        </VIEW></THEME>
        """)
        let template = WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "mainView")
        XCTAssertEqual(template?.viewID, "plView")
        XCTAssertEqual(template?.ringNodeIDs.count, 4,
                       "the recovered corner is a ring piece like any other")
    }

    /// **And the refusal still stands where it costs nothing.** `Ice` writes its shuffle glyph six
    /// nodes before `Vid-bottomleft.bmp` and `Back to the Future Trilogy` its repeat pair six
    /// before `f_top_left.png` — a second declaration for the same slot — so the control is dropped
    /// and the real corner bitmap takes it. That is the population the rule was measured on, and
    /// recovery must not reach it: a recovered corner is a *last* resort, not a first one.
    func testAGlyphStillLosesTheCornerToTheBitmapDeclaredAfterIt() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW id="shuffle" horizontalAlignment="left" verticalAlignment="top"
                   backgroundImage="piece.png">
            <SHUFFLEBUTTON id="sh" left="0" top="0" width="26" height="24"/>
          </SUBVIEW>
          <SUBVIEW id="topLeftArt" horizontalAlignment="left" verticalAlignment="top"
                   backgroundImage="piece.png"/>
          \(Self.otherCorners)
          \(Self.listClient)
        </VIEW></THEME>
        """)
        let template = WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "mainView")
        let art = try XCTUnwrap(Self.node(in: loaded, id: "topLeftArt"))
        let glyph = try XCTUnwrap(Self.node(in: loaded, id: "shuffle"))
        XCTAssertTrue(template?.ringNodeIDs.contains(art.stableID) ?? false,
                      "the corner bitmap declared after the glyph still wins the slot")
        XCTAssertFalse(template?.ringNodeIDs.contains(glyph.stableID) ?? true,
                       "a glyph with a bitmap behind it is still not a corner")
    }

    // MARK: - A tie between a playlist and a video view

    /// Both views score 12 in the reported archive — eight filled slots and four for the content —
    /// and the winner was whichever the author declared first. A video view's border is drawn
    /// around a *picture* and carries the furniture a picture needs; every window borrowing this
    /// ring is a list.
    func testAPlaylistOutranksAVideoViewOnAnEqualScore() async throws {
        let loaded = try await skin("""
        <THEME>
        <VIEW id="videoView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left" verticalAlignment="top" backgroundImage="piece.png"/>
          \(Self.otherCorners)
          \(Self.videoClient)
        </VIEW>
        <VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left" verticalAlignment="top" backgroundImage="piece.png"/>
          \(Self.otherCorners)
          \(Self.listClient)
        </VIEW>
        </THEME>
        """)
        XCTAssertEqual(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "mainView")?.viewID,
                       "plView")
    }

    /// **A visualiser is not a video view, and the corpus is emphatic about it.** Written first as
    /// "a list beats anything that is not a list", the rule moved 17 lines and both regressions
    /// were `visView → plView`: `Constantine` grew a 145pt right rack where it had an 18pt rail —
    /// `Ice`'s recorded rack rejection coming back — and `QuickSilver`'s right edge went from 0.012
    /// bare to **0.908**. A skin gives its playlist a rack and its visualiser a rail.
    func testAVisualiserKeepsItsRingAgainstAPlaylistOnAnEqualScore() async throws {
        let loaded = try await skin("""
        <THEME>
        <VIEW id="visView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left" verticalAlignment="top" backgroundImage="piece.png"/>
          \(Self.otherCorners)
          <SUBVIEW id="client" horizontalAlignment="stretch" verticalAlignment="stretch"
                   left="10" top="10" width="180" height="180">
            <EFFECTS id="vis" left="0" top="0" width="180" height="180"/>
          </SUBVIEW>
        </VIEW>
        <VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left" verticalAlignment="top" backgroundImage="piece.png"/>
          \(Self.otherCorners)
          \(Self.listClient)
        </VIEW>
        </THEME>
        """)
        XCTAssertEqual(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "mainView")?.viewID,
                       "visView")
    }

    /// **Strictly a tie-break.** `score` still decides every contest it can, so a skin whose video
    /// view carries the more complete ring keeps it — and a skin whose *only* ring is there has one.
    func testAMoreCompleteVideoRingStillOutranksAThinnerPlaylistOne() async throws {
        let loaded = try await skin("""
        <THEME>
        <VIEW id="videoView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left"    verticalAlignment="top"     backgroundImage="piece.png"/>
          <SUBVIEW horizontalAlignment="stretch" verticalAlignment="top"     backgroundImage="piece.png"/>
          <SUBVIEW horizontalAlignment="left"    verticalAlignment="stretch" backgroundImage="piece.png"/>
          <SUBVIEW horizontalAlignment="right"   verticalAlignment="stretch" backgroundImage="piece.png"/>
          <SUBVIEW horizontalAlignment="stretch" verticalAlignment="bottom"  backgroundImage="piece.png"/>
          \(Self.otherCorners)
          \(Self.videoClient)
        </VIEW>
        <VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left" verticalAlignment="top" backgroundImage="piece.png"/>
          \(Self.otherCorners)
          \(Self.listClient)
        </VIEW>
        </THEME>
        """)
        XCTAssertEqual(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "mainView")?.viewID,
                       "videoView")
    }

    private static func node(in skin: WMPLoadedSkin, id: String) -> WMPNode? {
        func walk(_ node: WMPNode) -> WMPNode? {
            if node.attribute(named: "id")?.rawValue == id { return node }
            for child in node.children {
                if let found = walk(child) { return found }
            }
            return nil
        }
        for registration in skin.views {
            if let found = walk(registration.node) { return found }
        }
        return nil
    }
}
