import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W161 — "the 2 windows_xp skins the eq does not work", reported live 2026-09-14.**
///
/// Not an equaliser defect at all: both `Windows_XP_Media_Center_Edition` archives open with an
/// intro that assigns `shutter_open.gif` to a `zIndex="20"` subview over the whole display, and the
/// engine held that GIF's last frame — an opaque blue plate — forever. The metadata, `STATUS:`,
/// elapsed readout, seek arc **and the equaliser panel the skin opens in the same rectangle** were
/// all built, drawn, and then buried. The skin's own markup is the argument for the rule: the
/// *closed* state is held by a separate static child the handler toggles, which only makes sense if
/// the animation leaves nothing behind.
///
/// The discrimination is what these tests are for. Applying "one-shot plus disposal 2" to the whole
/// final frame matches **379 corpus files** including `ALXMorph`'s idle logo and would erase artwork
/// nothing is wrong with; the degenerate final *block* matches **79 files in 33 archives**, almost
/// all named `shutter_open`, `shutter_close` or `intro_anim`. `Age_of_Mythology` settles it inside
/// one skin — `open_shutter.gif` carries the terminator and `close_shutter.gif` does not, ending
/// instead on a full-size 80%-opaque closed shutter that has to persist.
///
/// The corpus numbers above are a scan of the installed archives, not a committed script; the
/// on-screen half was verified by driving the app (`reference/skins/windows-xp-media-center.md`).
final class WMPGIFTerminatorTests: XCTestCase {

    // MARK: - The block walker

    /// A GIF stream assembled block by block, so a test can state an image descriptor's own size
    /// and disposal directly. The pixel payload is never decoded by the walker, so it is a stub.
    private struct GIFBuilder {
        var canvas: (width: Int, height: Int) = (32, 32)
        var globalColorTable = true
        private var frames: [(width: Int, height: Int, disposal: Int, localTable: Bool)] = []

        mutating func frame(_ width: Int, _ height: Int, disposal: Int, localTable: Bool = false) {
            frames.append((width, height, disposal, localTable))
        }

        func build(trailer: Bool = true) -> Data {
            func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
            var bytes: [UInt8] = Array("GIF89a".utf8)
            bytes += le16(canvas.width)
            bytes += le16(canvas.height)
            bytes += [globalColorTable ? 0x80 : 0x00, 0x00, 0x00]
            if globalColorTable { bytes += [0, 0, 0, 255, 255, 255] }
            for frame in frames {
                bytes += [0x21, 0xF9, 0x04, UInt8((frame.disposal & 7) << 2), 0x04, 0x00, 0x00, 0x00]
                bytes += [0x2C]
                bytes += le16(0)
                bytes += le16(0)
                bytes += le16(frame.width)
                bytes += le16(frame.height)
                bytes += [frame.localTable ? 0x80 : 0x00]
                if frame.localTable { bytes += [0, 0, 0, 255, 255, 255] }
                bytes += [0x02, 0x02, 0x44, 0x01, 0x00]
            }
            if trailer { bytes += [0x3B] }
            return Data(bytes)
        }
    }

    /// The `Windows_XP_Media_Center_Edition` / `Age_of_Mythology` / `MechAssault` shape: real frames
    /// and then a 1x1 block that disposes to the background.
    func testADegenerateFinalBlockThatDisposesToBackgroundClearsTheAnimation() {
        var gif = GIFBuilder()
        gif.frame(32, 32, disposal: 1)
        gif.frame(32, 32, disposal: 1)
        gif.frame(1, 1, disposal: 2)
        XCTAssertTrue(WMPGIFTerminator.clearsWhenFinished(gif.build()))
    }

    /// **The 379-file guard.** `ALXMorph`'s six-frame idle logo, `Age_of_Mythology`'s
    /// `close_shutter.gif` and every other one-shot animation that ends on real artwork declares
    /// disposal 2 on a *full-size* final frame. Reading disposal alone erases all of them.
    func testAFullSizeFinalFrameIsArtworkHoweverItDisposes() {
        var gif = GIFBuilder()
        gif.frame(32, 32, disposal: 1)
        gif.frame(32, 32, disposal: 2)
        XCTAssertFalse(WMPGIFTerminator.clearsWhenFinished(gif.build()))
    }

    /// Both halves are required. A tiny trailing block that does not ask for the background back is
    /// the last frame of the picture, not a terminator — `Blinx`'s `shutter_close.gif` and
    /// `The Unit`'s hover glows write exactly that, and clearing them would drop hover artwork
    /// while the pointer is still on the control.
    func testADegenerateFinalBlockWithAnyOtherDisposalHoldsItsFrame() {
        for disposal in [0, 1, 3] {
            var gif = GIFBuilder()
            gif.frame(32, 32, disposal: 1)
            gif.frame(1, 1, disposal: disposal)
            XCTAssertFalse(WMPGIFTerminator.clearsWhenFinished(gif.build()),
                           "disposal \(disposal) is not 'restore to background'")
        }
    }

    /// Degenerate means degenerate *relative to the canvas*. A genuinely tiny animation is artwork
    /// at its own size and must never be cleared by this rule.
    func testATinyCanvasIsArtworkAtItsOwnSizeRatherThanATerminator() {
        var gif = GIFBuilder()
        gif.canvas = (1, 1)
        gif.frame(1, 1, disposal: 1)
        gif.frame(1, 1, disposal: 2)
        XCTAssertFalse(WMPGIFTerminator.clearsWhenFinished(gif.build()))
    }

    /// The disposal belongs to the image block the graphic control extension **introduces**, so an
    /// earlier frame's disposal must not be read as the last one's.
    func testDisposalIsReadFromTheExtensionThatIntroducesTheFinalBlock() {
        var gif = GIFBuilder()
        gif.frame(32, 32, disposal: 2)
        gif.frame(1, 1, disposal: 1)
        XCTAssertFalse(WMPGIFTerminator.clearsWhenFinished(gif.build()),
                       "the 2 belongs to the frame before the degenerate one")
    }

    /// A local colour table sits between the image descriptor and the pixel data, and skipping it by
    /// the wrong size walks into the middle of a block and reads a size that is not a size.
    func testALocalColourTableIsSkippedByItsDeclaredSize() {
        var gif = GIFBuilder()
        gif.frame(32, 32, disposal: 1, localTable: true)
        gif.frame(1, 1, disposal: 2, localTable: true)
        XCTAssertTrue(WMPGIFTerminator.clearsWhenFinished(gif.build()))
    }

    /// **A stream this cannot read must never blank a skin's artwork.** Every malformed shape
    /// answers `false`, which is the engine's behaviour before this rule existed.
    func testAnythingUnreadableIsNotATerminator() {
        var gif = GIFBuilder()
        gif.frame(32, 32, disposal: 1)
        gif.frame(1, 1, disposal: 2)
        let complete = gif.build()
        XCTAssertFalse(WMPGIFTerminator.clearsWhenFinished(Data()))
        XCTAssertFalse(WMPGIFTerminator.clearsWhenFinished(Data("not a gif at all".utf8)))
        XCTAssertFalse(WMPGIFTerminator.clearsWhenFinished(complete.prefix(20)))
        // A stream that simply runs out mid-block still resolves, because the walk answers from
        // what it read rather than throwing; what it must not do is answer `true` off a truncated
        // descriptor it never reached.
        XCTAssertFalse(WMPGIFTerminator.clearsWhenFinished(complete.prefix(13)))
    }

    /// **A sliced `Data` keeps the original buffer's indices**, which is a standing trap in this
    /// subsystem, and a walker that started at a hard-coded `0` would read a slice's header out of
    /// the bytes in front of it. The same stream must answer the same way however it was carved.
    func testASlicedStreamReadsTheSameAsAStandaloneOne() {
        var gif = GIFBuilder()
        gif.frame(32, 32, disposal: 1)
        gif.frame(1, 1, disposal: 2)
        let complete = gif.build()
        var padded = Data(repeating: 0xAB, count: 37)
        padded.append(complete)
        let slice = padded[padded.startIndex.advanced(by: 37)...]
        XCTAssertNotEqual(slice.startIndex, 0, "the fixture has to be a genuine offset slice")
        XCTAssertTrue(WMPGIFTerminator.clearsWhenFinished(slice))
    }

    // MARK: - What the engine does with it

    private func store(_ gif: Data) -> WMPImageStore {
        WMPImageStore(provider: WMPMemoryResourceProvider(["a.gif": gif]))
    }

    /// The flag rides the decoded animation, so the renderer can ask one object about both the frame
    /// and whether there is a frame to draw at all.
    func testTheImageStoreCarriesTheTerminatorOntoTheAnimation() throws {
        let plain = WMPSkinTestSupport.animatedGIF(frameCount: 4, delayCentiseconds: 7, canvas: 32)
        let cleared = WMPSkinTestSupport.animatedGIF(frameCount: 4, delayCentiseconds: 7,
                                                     canvas: 32, terminator: true)
        XCTAssertFalse(try XCTUnwrap(store(plain).animation(for: "a.gif")).clearsWhenFinished)
        XCTAssertTrue(try XCTUnwrap(store(cleared).animation(for: "a.gif")).clearsWhenFinished)
    }

    /// **Nothing is cleared before the animation has finished**, and a terminator does not shorten
    /// it: every frame up to the end still draws, which is the whole intro the skin authored.
    func testTheAnimationIsOnlyClearedOnceItHasFinishedPlaying() throws {
        let gif = WMPSkinTestSupport.animatedGIF(frameCount: 4, delayCentiseconds: 10,
                                                 canvas: 32, terminator: true)
        let animation = try XCTUnwrap(store(gif).animation(for: "a.gif"))
        let end = try XCTUnwrap(animation.endOfPlayback)
        XCTAssertFalse(animation.isCleared(at: 0))
        XCTAssertFalse(animation.isCleared(at: end - 0.001))
        XCTAssertTrue(animation.isCleared(at: end))
        XCTAssertTrue(animation.isCleared(at: end + 60))
    }

    /// **An endless animation has no end to hold, so it can never be cleared** — `loops: 0` is the
    /// NETSCAPE2.0 forever, which 88 corpus GIFs declare. Without this guard a looping GIF that
    /// happened to carry a terminator would vanish the first time the clock passed its duration.
    func testAnEndlessAnimationIsNeverCleared() throws {
        let gif = WMPSkinTestSupport.animatedGIF(frameCount: 4, delayCentiseconds: 10, loops: 0,
                                                 canvas: 32, terminator: true)
        let animation = try XCTUnwrap(store(gif).animation(for: "a.gif"))
        XCTAssertNil(animation.endOfPlayback)
        XCTAssertFalse(animation.isCleared(at: 10_000))
    }

    /// The rule the reported defect is actually about: **the skin's own display comes back.** A
    /// subview drawn over the player's face with a finished terminator animation paints nothing, so
    /// what it was covering is what the window shows.
    func testAFinishedTerminatorAnimationDrawsNothingOverWhatItCovered() async throws {
        let covered = try WMPSkinTestSupport.encodedImage(width: 32, height: 32,
            rgba: (0..<(32 * 32)).flatMap { _ in [UInt8(0), 200, 0, 255] })
        let shutter = WMPSkinTestSupport.animatedGIF(frameCount: 4, delayCentiseconds: 10,
                                                    canvas: 32, terminator: true)
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="32" height="32">
                <SUBVIEW id="face" zIndex="5" left="0" top="0" backgroundImage="face.png"/>
                <SUBVIEW id="shutter" zIndex="20" left="0" top="0" backgroundImage="shutter.gif"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("face.png", data: covered),
            WMPTestArchiveEntry("shutter.gif", data: shutter)
        ]))
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let renderer = WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))

        let during = try await renderer.render(scene: scene, clock: 0).image
        let after = try await renderer.render(scene: scene, clock: 60).image
        XCTAssertNotEqual(WMPSkinTestSupport.rgba(during, x: 16, yFromTop: 16),
                          [0, 200, 0, 255], "the shutter is still playing and still covers the face")
        XCTAssertEqual(WMPSkinTestSupport.rgba(after, x: 16, yFromTop: 16), [0, 200, 0, 255],
                       "the finished terminator animation draws nothing, so the face shows")
    }
}
