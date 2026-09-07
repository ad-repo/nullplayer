import CoreGraphics
import XCTest
@testable import NullPlayer

/// B86 and B88 — the two faults that kept cPro's `ClassicPro.xml` extras and its volume bar dark.
///
/// **Why these need tests at all.** Both failed *silently*. ClassicPro reads its optional extras
/// behind `if (myDoc.exists())` and builds its beat-vis menu from whatever the parser handed back, so
/// a document that never resolved and a document with nothing in it produce the same empty menu and
/// the same absent feature — no diagnostic, no unsupported-method tally, nothing in a render dump.
/// The corpus patterns below *are* the specification; a regression in either would be invisible again.
final class WinampModernB86B88Tests: XCTestCase {

    // MARK: - B86: `parser_addCallback` path matching

    /// The four-component path ClassicPro's `<customvis>` entries actually sit at.
    private let customVis = ["ClassicPro", "Visualization", "BeatVis", "customvis"]

    /// Big Bento's pattern — absolute, same depth, `*` as one whole component. This is the shape the
    /// matcher was originally written to, and the one thing the B86 fix had to leave alone.
    func testAbsoluteSameDepthStillMatchesOnlyWhatItDid() {
        let pattern = "WasabiXML/BrowserPro/*"
        XCTAssertTrue(WinampModernScriptRuntime.parserPath(
            pattern, matches: ["WasabiXML", "BrowserPro", "sourceitem"]))
        // `*` is one component, not a subtree: the parent itself is not a match.
        XCTAssertFalse(WinampModernScriptRuntime.parserPath(
            pattern, matches: ["WasabiXML", "BrowserPro"]))
        // And a different branch at the same depth is still rejected.
        XCTAssertFalse(WinampModernScriptRuntime.parserPath(
            pattern, matches: ["WasabiXML", "Something", "sourceitem"]))
    }

    /// `ClassicPro/Visualization/BeatVis*` — a trailing `*` glued to the final component means that
    /// node **and everything beneath it**. Three components against a four-component path, which the
    /// old equal-count rule rejected outright.
    func testTrailingStarMatchesTheSubtree() {
        let pattern = "ClassicPro/Visualization/BeatVis*"
        XCTAssertTrue(WinampModernScriptRuntime.parserPath(pattern, matches: customVis))
        XCTAssertTrue(WinampModernScriptRuntime.parserPath(
            pattern, matches: ["ClassicPro", "Visualization", "BeatVis"]))
        XCTAssertFalse(WinampModernScriptRuntime.parserPath(
            pattern, matches: ["ClassicPro", "Visualization"]))
    }

    /// `ClassicPro/TextSettings*` and `ClassicPro/About:Skin*` — the same shape, and the two whose
    /// failure nobody had noticed: the songticker's antialias setting and the About box's skin info.
    func testTheOtherTwoTrailingStarPatterns() {
        XCTAssertTrue(WinampModernScriptRuntime.parserPath(
            "ClassicPro/TextSettings*", matches: ["ClassicPro", "TextSettings", "Style"]))
        XCTAssertTrue(WinampModernScriptRuntime.parserPath(
            "ClassicPro/About:Skin*", matches: ["ClassicPro", "About:Skin", "entry"]))
    }

    /// `BeatVis/*` — relative, aligned with the **end** of the path. `beat.maki` registers this
    /// alongside the absolute spelling for the same nodes, which is how we know both are meant to fire.
    func testRelativePatternAlignsWithTheEndOfThePath() {
        XCTAssertTrue(WinampModernScriptRuntime.parserPath("BeatVis/*", matches: customVis))
        // Anchored at the end, so it must be the *last* components that line up.
        XCTAssertFalse(WinampModernScriptRuntime.parserPath(
            "BeatVis/*", matches: ["ClassicPro", "BeatVis", "customvis", "deeper"]))
    }

    /// A one-component pattern must stay absolute. Suffix matching a bare name would fire callbacks
    /// for an element of that name at any depth — something no script registered for.
    func testSingleComponentPatternDoesNotMatchAtDepth() {
        XCTAssertTrue(WinampModernScriptRuntime.parserPath("ClassicPro", matches: ["ClassicPro"]))
        XCTAssertFalse(WinampModernScriptRuntime.parserPath("ClassicPro", matches: customVis))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(WinampModernScriptRuntime.parserPath(
            "classicpro/visualization/beatvis*", matches: customVis))
    }

    // MARK: - B86: `@SKINPATH@` carries a trailing separator

    /// The second half of B86, and the one that actually kept the document dark: ClassicPro builds
    /// the path by bare concatenation — `getParam() + "ClassicPro.xml"` — with no separator of its
    /// own. Without a trailing `/` that resolved to `/Skins/<name>ClassicPro.xml`, which is nothing.
    func testSkinPathVariableEndsWithASeparatorSoBareConcatenationResolves() throws {
        let provider = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data("<WasabiXML/>".utf8),
            "ClassicPro.xml": Data("<ClassicPro/>".utf8),
        ])
        let vfs = try WalVirtualFileSystem(skinName: "cPro_T2T-by-MAC", skin: provider)

        let resolved = try vfs.resolve("@SKINPATH@ClassicPro.xml", relativeTo: "/skin.xml")
        XCTAssertEqual(resolved.logicalPath, "/Skins/cPro_T2T-by-MAC/ClassicPro.xml")

        // Case-folded, the way `beat.m` spells it.
        let lower = try vfs.resolve("@SKINPATH@classicpro.xml", relativeTo: "/skin.xml")
        XCTAssertEqual(lower.logicalPath, "/Skins/cPro_T2T-by-MAC/ClassicPro.xml")
    }

    /// The separator must not leak into paths that bring their own — the engine include is written
    /// `@COLORTHEMESPATH@\..\..\Plugins\…`, and the doubled slash has to canonicalize away.
    func testASeparatorAlreadyInThePathIsNotDoubled() throws {
        let provider = try WalMemoryResourceProvider(resources: ["skin.xml": Data("<WasabiXML/>".utf8)])
        let vfs = try WalVirtualFileSystem(skinName: "S", skin: provider)
        let resolved = try vfs.resolve(#"@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml"#,
                                       relativeTo: "/skin.xml", mustExist: false)
        XCTAssertEqual(resolved.logicalPath, "/Plugins/classicPro/engine/load.xml")
    }

    /// Every internal consumer wants the root *without* the separator, so the accessor trims it.
    func testSkinRootAccessorHasNoTrailingSeparator() throws {
        let provider = try WalMemoryResourceProvider(resources: ["skin.xml": Data("<WasabiXML/>".utf8)])
        let vfs = try WalVirtualFileSystem(skinName: "S", skin: provider)
        XCTAssertEqual(vfs.skinRoot, "/Skins/S")
    }

    // MARK: - B88: the `<images>` filmstrip

    /// ClassicPro's volume sheet: 97×288, pitch 16, frame height 15 — 18 frames with a blank row
    /// between each. Pitch and height differ on purpose, and conflating them draws a row of gaps.
    func testVolumeSheetGeometry() {
        XCTAssertEqual(WasabiFilmstrip.frameCount(sheetHeight: 288, pitch: 16), 18)

        let bottom = WasabiFilmstrip.crop(sheetWidth: 97, sheetHeight: 288, pitch: 16,
                                          frameHeight: 15, normalized: 0)
        XCTAssertEqual(bottom, CGRect(x: 0, y: 0, width: 97, height: 15))

        let top = WasabiFilmstrip.crop(sheetWidth: 97, sheetHeight: 288, pitch: 16,
                                       frameHeight: 15, normalized: 1)
        // Frame 17 at pitch 16 starts at 272, and 272 + 15 stays inside the 288-tall sheet.
        XCTAssertEqual(top, CGRect(x: 0, y: 272, width: 97, height: 15))
    }

    /// Ends inclusive: full volume must reach the **last** frame, not the one before it. Truncating
    /// instead of rounding is the classic way to lose the top of the range.
    func testEndsOfTheRangeReachTheEndFrames() {
        XCTAssertEqual(WasabiFilmstrip.frameIndex(normalized: 0, count: 18), 0)
        XCTAssertEqual(WasabiFilmstrip.frameIndex(normalized: 1, count: 18), 17)
        XCTAssertEqual(WasabiFilmstrip.frameIndex(normalized: 0.5, count: 18), 9)
    }

    func testValuesOutsideTheRangeAreClamped() {
        XCTAssertEqual(WasabiFilmstrip.frameIndex(normalized: -3, count: 18), 0)
        XCTAssertEqual(WasabiFilmstrip.frameIndex(normalized: 12, count: 18), 17)
    }

    /// A declaration that is not a filmstrip must draw nothing rather than divide by zero or crop
    /// past the sheet.
    func testNonFilmstripDeclarationsAreRefused() {
        XCTAssertNil(WasabiFilmstrip.crop(sheetWidth: 97, sheetHeight: 288, pitch: 0,
                                          frameHeight: 15, normalized: 0.5))
        XCTAssertNil(WasabiFilmstrip.crop(sheetWidth: 97, sheetHeight: 8, pitch: 16,
                                          frameHeight: 15, normalized: 0.5))
        XCTAssertNil(WasabiFilmstrip.crop(sheetWidth: 0, sheetHeight: 288, pitch: 16,
                                          frameHeight: 15, normalized: 0.5))
    }

    /// A sheet with no gap between frames: the frame height falls back to the pitch.
    func testMissingFrameHeightFallsBackToThePitch() {
        XCTAssertEqual(WasabiFilmstrip.crop(sheetWidth: 20, sheetHeight: 100, pitch: 10,
                                            frameHeight: nil, normalized: 0),
                       CGRect(x: 0, y: 0, width: 20, height: 10))
    }

    /// A frame height that would run off the bottom is clipped to the sheet rather than refused —
    /// `cropping(to:)` answers nil for an out-of-bounds rect, which would blank the last frame.
    func testLastFrameIsClippedToTheSheetRatherThanLost() {
        // Frame height 20 at pitch 10: the last frame starts at 80 with only 15 rows left under it,
        // so it is trimmed to 15. Handing the full 20 to `cropping(to:)` answers nil for an
        // out-of-bounds rect, which would blank the top of the range rather than shorten it.
        let crop = WasabiFilmstrip.crop(sheetWidth: 20, sheetHeight: 95, pitch: 10,
                                        frameHeight: 20, normalized: 1)
        XCTAssertEqual(crop, CGRect(x: 0, y: 80, width: 20, height: 15))
    }
}
