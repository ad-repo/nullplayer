import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W236: a `fontFace` this player cannot resolve was not falling back to this player's default —
/// it was falling back to CoreText's.**
///
/// `netgen.wms` (`Revert`, `Revert (1)`) authors `fontFace="res://-/RT_STRING/#1888"` on all three
/// of its metadata readouts: `wmploc.dll` holds the shipping language's font family, which is how
/// one markup file serves an RTL locale. There is no honest family to invent for that id here, and
/// `WMPResourceStrings` answers the empty string for every id the corpus does not name.
///
/// **The empty string is not the same as an answer, and neither is the raw URL.**
/// `CTFontCreateWithName` never fails: a name it cannot match is silently substituted. Measured
/// 2026-09-20 at the sizes `netgen.wms` authors — `res://-/RT_STRING/#1888` and `""` both resolve
/// to **Helvetica** (line height 7.00 at 7pt), against `Arial`'s 8.05 — so those readouts drew in a
/// face nothing in the markup asked for, and routing the attribute through the string table would
/// have landed in exactly the same place.
///
/// **An unusable face is therefore an unstated one**, the reading W240 gave an unreadable geometry
/// value and W241 an empty one, and the ambient default answers it. The URL still goes through
/// `WMPResourceStrings` rather than being rejected outright, so a family that is ever earned for
/// `#1888` is used the moment the table row lands.
///
/// **Reach, re-measured 2026-09-20 over the 185 installed archives**: 953 literal `fontFace`/
/// `fontType` uses, **6 of them `res://` (3 each in `Revert`, `Revert (1)`) and 0 empty**, so the
/// rule moves those six and nothing else in the corpus. Reproduce by scanning the decoded markup
/// for `font(Face|Type)="…"` and tallying the empty and `res://` values.
///
/// The other half of the row closed as a note: `scrollingDirection` — `#1910`, beside these same
/// readouts — is consumed nowhere in `Sources`. The builder reads `scrolling`, `scrollingDelay` and
/// `scrollingAmount` only, so its empty answer draws nothing wrong until a scroll direction is
/// implemented, and answering it would move no pixel today.
final class WMPResourceFontFaceTests: XCTestCase {
    private func load(_ wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    private func build(_ skin: WMPLoadedSkin, _ size: WMPSize) async throws -> WMPScene {
        try await WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
            .build(viewID: "main", requestedSize: size, overrides: .empty)
    }

    /// The face the scene says it will draw `id` in.
    private func drawnFace(_ id: String, in scene: WMPScene,
                           file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let command = try XCTUnwrap(scene.commands.first {
            guard $0.nodeID == id else { return false }
            if case .text = $0.paint { return true }
            return false
        }, "the readout is painted at all", file: file, line: line)
        guard case let .text(text) = command.paint else {
            XCTFail("not a text command", file: file, line: line)
            return ""
        }
        return text.fontName
    }

    /// `netgen.wms`'s three metadata readouts, reduced to one, with the value its script writes
    /// once a track is open. **The assertion is the default face**, not merely "not the URL": the
    /// URL and the empty string were the same wrong answer.
    func testAnUnresolvableResourceFontFaceDrawsInTheDefaultFace() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="txt2" left="0" top="14" width="155" height="18" fontSize="10"
                  fontFace="res://-/RT_STRING/#1888" value="Some Track Name"/>
        </VIEW></THEME>
        """)
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        XCTAssertEqual(try drawnFace("txt2", in: scene), WMPTextMetrics.defaultFace,
            "an id wmploc.dll answers and this player cannot is an unstated face; CoreText "
            + "substituted Helvetica for both the URL and the empty string it resolves to")
    }

    /// The same readout with **no** `fontFace` at all must draw identically. That equality is the
    /// claim of the fix, and an assertion on the name alone would not make it.
    func testAnUnresolvableFaceAndAnAbsentFaceDrawTheSame() async throws {
        let markup = { (attribute: String) in """
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="txt2" left="0" top="14" width="155" height="18" fontSize="10"
                  \(attribute) value="Some Track Name"/>
        </VIEW></THEME>
        """ }
        let resource = try await build(
            try await load(markup("fontFace=\"res://-/RT_STRING/#1888\"")),
            WMPSize(width: 300, height: 200))
        let absent = try await build(try await load(markup("")),
                                     WMPSize(width: 300, height: 200))

        XCTAssertEqual(try drawnFace("txt2", in: resource), try drawnFace("txt2", in: absent),
                       "a face the engine cannot resolve is not a face the skin stated")
    }

    /// An **empty** face is the same authoring. The corpus authors none today, but the object model
    /// already skipped `""` where the builder did not, and the two seams have to agree: a face a
    /// script clears at runtime reaches the builder the same way.
    func testAnEmptyFaceIsAlsoUnstated() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="txt2" left="0" top="14" width="155" height="18" fontFace="" fontType="  "
                  value="Some Track Name"/>
        </VIEW></THEME>
        """)
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        XCTAssertEqual(try drawnFace("txt2", in: scene), WMPTextMetrics.defaultFace)
    }

    /// **`fontType` is the fallback, not a second unstated case.** 21 corpus skins author it and
    /// the rule must not swallow it when `fontFace` is the unusable one.
    func testAnUnusableFaceFallsThroughToTheAuthoredFontType() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="txt2" left="0" top="14" width="155" height="18"
                  fontFace="res://-/RT_STRING/#1888" fontType="Verdana" value="Some Track Name"/>
        </VIEW></THEME>
        """)
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        XCTAssertEqual(try drawnFace("txt2", in: scene), "Verdana",
                       "the skin stated a face; only the unusable candidate is skipped")
    }

    /// **A face the skin does state is untouched**, including one the table could never answer.
    /// 953 of the corpus's uses are ordinary family names and none of them may move.
    func testAnAuthoredFaceIsUnchanged() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="glyphs" left="4" top="4" width="80" height="12" fontFace="webdings"
                  value=" 4 "/>
        </VIEW></THEME>
        """)
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        XCTAssertEqual(try drawnFace("glyphs", in: scene), "webdings")
    }

    /// **A resource id the table *does* answer is still a string, not a face**, and the same
    /// resolver reaches both. This is the seam that keeps `#1888` open: the moment the corpus names
    /// a family for it, the row is used rather than skipped.
    func testATableAnsweredResourceIdIsUsedAsTheFace() {
        XCTAssertEqual(WMPTextMetrics.face("res://wmploc.dll/RT_STRING/#1812"), "Close",
            "a resolved id is a stated face; only an unanswered one falls back")
        XCTAssertEqual(WMPTextMetrics.face("res://wmploc/RT_STRING/#1910"),
                       WMPTextMetrics.defaultFace,
                       "#1910 is the scrolling direction and the table answers it blank")
    }

    /// The measurement that ranked the row, kept as an assertion so the fallback cannot quietly
    /// become the substitution again: CoreText answers an unmatched name rather than failing.
    func testCoreTextSubstitutesRatherThanFailingForAnUnmatchedFace() {
        let substituted = WMPTextMetrics.lineHeight(fontName: "res://-/RT_STRING/#1888",
                                                    fontSize: 7, bold: false, italic: false)
        let stated = WMPTextMetrics.lineHeight(fontName: WMPTextMetrics.defaultFace,
                                               fontSize: 7, bold: false, italic: false)
        XCTAssertNotEqual(substituted, stated,
            "if these ever agree the test above proves nothing — the whole defect is that an "
            + "unmatched name silently becomes a different face at a different height")
    }

    /// **A comma in `fontFace` is a fallback list (2026-09-26).** `Dreamcatcher`'s clock authors
    /// `"arial narrow,arial,tahoma,verdana"`; handed to CoreText whole it became Helvetica, whose
    /// shorter ascent lifted the digits into the logo above them. 62 uses across 40 of 179 archives.
    /// The first installed family is the one drawn; `tahomaArial` is a real typo from `bttf.wms`.
    func testACommaListDrawsInItsFirstInstalledFamily() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="time" left="0" top="0" width="54" fontSize="8" fontStyle="bold"
                  fontFace="arial narrow,arial,tahoma,verdana" value="0:20"/>
            <TEXT id="typo" left="0" top="20" width="80" fontFace="tahomaArial, verdana"
                  value="00:00"/>
        </VIEW></THEME>
        """)
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        XCTAssertEqual(try drawnFace("time", in: scene), "arial narrow")
        XCTAssertEqual(try drawnFace("typo", in: scene), "verdana",
                       "an uninstalled entry is skipped, and the next one is trimmed")
    }

    /// A list naming nothing installed reads as its first entry — what a single uninstalled name
    /// already does — so the rule moves only the lists that name a real family.
    func testACommaListNamingNothingInstalledKeepsItsFirstEntry() {
        XCTAssertEqual(WMPTextMetrics.face("NoSuchFaceA,NoSuchFaceB"), "NoSuchFaceA")
        XCTAssertEqual(WMPTextMetrics.face(" , ", "Verdana"), "Verdana",
                       "a list of empty entries is an unstated face, and falls through")
    }
}
