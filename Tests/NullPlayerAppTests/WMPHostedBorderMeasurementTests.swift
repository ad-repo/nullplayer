import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// **Measuring a hosted window must not move it, and must not cost a render (W238).**
///
/// Reported 2026-09-19 as *"other windows react to windows being launched and flash and redraw when
/// others are opened"*. Measured on `Ice`: with the library settled, opening PeppyMeter ran the
/// border layout **ten times over both windows**, walked the library's frame
/// 603x594 → 603x732 → **603x709**, and paid **two extra full donor renders** (395 ms, 363 ms) for
/// sizes nothing had asked for.
///
/// It was a feedback loop with two halves that disagreed about what "the border" is:
///
/// - `HostedWindowBorderLayout.apply()` **adds** `WMPHostedFrameProvider.donorInsets` — the donor's
///   four borders, stated once per skin without reference to any window (W207).
/// - `windowDidResize` **subtracted** the *artwork's* metrics at the window's current size. On a
///   size nothing had rendered yet, `artwork(for:)` answers the last ring **stretched** onto it, and
///   a stretched ring's insets are stretched with it.
///
/// So each pass left a residue and the two chased each other across renders — and because the
/// measurement went through the drawing seam, *asking* what border a window wore **scheduled a
/// donor rebuild** as a side effect.
///
/// These tests pin the two halves: the arithmetic is now a round trip rather than a measurement,
/// and the measuring seam answers the cache or nothing without scheduling anything.
final class WMPHostedBorderMeasurementTests: XCTestCase {

    // MARK: - `Ice`, the skin the defect was measured on

    /// `Ice`'s borders as the live trace printed them on 2026-09-19:
    /// `donorBorder=34/40/66/40` — title / left / bottom / right.
    private static let ice = SkinnedSurfaceChrome.Metrics(
        titleHeight: 34, leftBorder: 40, rightBorder: 40, bottomBorder: 66)

    // MARK: - The arithmetic

    /// **An interior read back against the border it was grown by is the interior it started as.**
    ///
    /// This is the fixed point the fix establishes, and the reason both halves of the rule now go
    /// through one `borderInPlay` helper. Donor borders are resolved from `JScript:` arithmetic and
    /// come out fractional, so the round trip has to survive that too — `outerSize` rounds its
    /// result and `interiorSize` does not, which is exactly where a half point of residue would
    /// accumulate if the two were ever allowed to disagree.
    @MainActor
    func testAnInteriorReadBackAgainstTheBorderItWasGrownByIsUnchanged() {
        let borders = [
            Self.ice,
            SkinnedSurfaceChrome.Metrics(titleHeight: 34.4, leftBorder: 40.2,
                                         rightBorder: 40.2, bottomBorder: 69.7),
            SkinnedSurfaceChrome.Metrics(titleHeight: 83, leftBorder: 72,
                                         rightBorder: 73, bottomBorder: 90),
            SkinnedSurfaceChrome.Metrics(titleHeight: 5, leftBorder: 0,
                                         rightBorder: 0, bottomBorder: 60),
        ]
        let interiors = [CGSize(width: 523, height: 632), CGSize(width: 299, height: 154),
                         CGSize(width: 297, height: 111), CGSize(width: 148, height: 1)]

        for border in borders {
            for interior in interiors {
                let outer = HostedWindowBorderLayout.outerSize(interior: interior, border: border)
                let readBack = HostedWindowBorderLayout.interiorSize(outer: outer, border: border)

                // Within the half point `outerSize` rounds away, and — the part that matters —
                // *not* accumulating: a second pass lands on the same frame.
                XCTAssertEqual(readBack.width, interior.width, accuracy: 0.5)
                XCTAssertEqual(readBack.height, interior.height, accuracy: 0.5)
                XCTAssertEqual(HostedWindowBorderLayout.outerSize(interior: readBack, border: border),
                               outer,
                               "a second pass moved the window: the rule is not a fixed point")
            }
        }
    }

    /// **The old arithmetic reproduced, so the drift it caused cannot come back unnoticed.**
    ///
    /// Reading back against a *scaled* ring instead of against the border `apply()` adds is what
    /// walked `Ice`'s library. Every number here is from the live trace, and they reconstruct the
    /// reported drift exactly: a ring built for 594 points of height, stretched onto 732, has its
    /// 34/66 borders stretched to 41.9/81.3, so the interior reads **608** where it was 632 — the
    /// reported `523x494 → 523x608` — and the next target is 708.8, rounded to the reported **709**.
    ///
    /// The test asserts the *fixed* rule does not do this. The scaled reading is computed alongside
    /// only to show the two answers are genuinely different numbers, which is the whole defect.
    @MainActor
    func testReadingBackAgainstAStretchedRingIsWhatWalkedTheWindow() {
        let border = Self.ice
        let settled = CGSize(width: 603, height: 594)
        let grown = CGSize(width: 603, height: 732)

        // What the drawing seam answered for a size it had not rendered: the ring built for
        // `settled`, stretched onto `grown`, with its insets stretched too.
        let stretch = grown.height / settled.height
        let stretched = SkinnedSurfaceChrome.Metrics(
            titleHeight: border.titleHeight * stretch, leftBorder: border.leftBorder,
            rightBorder: border.rightBorder, bottomBorder: border.bottomBorder * stretch)

        let byStretchedRing = HostedWindowBorderLayout.interiorSize(outer: grown, border: stretched)
        let nextTarget = HostedWindowBorderLayout.outerSize(interior: byStretchedRing, border: border)

        // The defect, reconstructed from the trace: interior 608, next frame 709.
        XCTAssertEqual(byStretchedRing.height, 608, accuracy: 1)
        XCTAssertEqual(nextTarget.height, 709, accuracy: 1)
        XCTAssertNotEqual(nextTarget.height, grown.height,
                          "the stretched reading has to disagree, or this test pins nothing")

        // And what the rule does now: subtract the border it adds, and stay put.
        let byBorderInPlay = HostedWindowBorderLayout.interiorSize(outer: grown, border: border)
        XCTAssertEqual(byBorderInPlay.height, 632, accuracy: 0.5)
        XCTAssertEqual(HostedWindowBorderLayout.outerSize(interior: byBorderInPlay, border: border),
                       grown,
                       "the window moved on a pass that measured it — W238 regressed")
    }

    // MARK: - The measuring seam

    private func block(width: Int, height: Int) throws -> Data {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = 20
            rgba[index + 1] = 90
            rgba[index + 2] = 180
            rgba[index + 3] = 255
        }
        return try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: rgba)
    }

    /// The same 400x300 ring the priming tests use: 40pt corners, so a 40pt border on every side
    /// and a 320x220 hole.
    private func ringSkin() async throws -> WMPLoadedSkin {
        let markup = """
        <THEME><VIEW id="plview" width="400" height="300">
        <SUBVIEW id="tl" horizontalAlignment="left"  verticalAlignment="top"
                 left="0" top="0" width="40" height="40" backgroundImage="corner.png"/>
        <SUBVIEW id="tr" horizontalAlignment="right" verticalAlignment="top"
                 left="360" top="0" width="40" height="40" backgroundImage="corner.png"/>
        <SUBVIEW id="bl" horizontalAlignment="left"  verticalAlignment="bottom"
                 left="0" top="260" width="40" height="40" backgroundImage="corner.png"/>
        <SUBVIEW id="br" horizontalAlignment="right" verticalAlignment="bottom"
                 left="360" top="260" width="40" height="40" backgroundImage="corner.png"/>
        <SUBVIEW id="client" horizontalAlignment="stretch" verticalAlignment="stretch"
                 left="40" top="40" width="320" height="220"/>
        </VIEW></THEME>
        """
        let entries = [WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8)),
                       WMPTestArchiveEntry("corner.png", data: try block(width: 40, height: 40))]
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// Give the provider's off-actor builds room to land. A build that never comes back leaves the
    /// cache empty, which is the same observation as "nothing was scheduled" — so the tests that
    /// depend on the difference assert the positive case too.
    @MainActor
    private func settle(_ provider: WMPHostedFrameProvider,
                        until ready: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if ready() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// **Asking what border a window wears must not schedule a donor rebuild.**
    ///
    /// The heart of W238's third question — *should a measurement path be allowed to schedule
    /// renders at all?* The answer is no: `HostedWindowBorderLayout` reads a window's border back on
    /// every resize and on every broadcast, and routing that through the drawing seam meant each
    /// look cost a full `WMPSceneBuilder`/`WMPRenderer` pass at a size nothing was drawing.
    ///
    /// If `renderedArtwork(for:)` scheduled, a build would land within the settle window and the
    /// cache would fill. It stays empty.
    @MainActor
    func testMeasuringASizeNeverRenderedSchedulesNoBuild() async throws {
        let provider = WMPHostedFrameProvider()
        let skin = try await ringSkin()
        XCTAssertTrue(provider.configure(skin: skin, playerViewID: nil),
                      "the ring fixture lent no frame")
        let size = CGSize(width: 512, height: 384)

        for _ in 0..<20 { XCTAssertNil(provider.renderedArtwork(for: size)) }
        await settle(provider) { false }

        XCTAssertNil(provider.renderedArtwork(for: size),
                     "measuring a size scheduled a render for it — W238 regressed")
    }

    /// **And it does answer, once the frame is genuinely in hand.** The guard above is only worth
    /// anything if the seam is not simply always nil: a drawing pass fills the cache, and the
    /// measurement then reads the real frame rather than a stretched stand-in.
    @MainActor
    func testMeasuringAnswersTheFrameOnceADrawHasRenderedIt() async throws {
        let provider = WMPHostedFrameProvider()
        let skin = try await ringSkin()
        XCTAssertTrue(provider.configure(skin: skin, playerViewID: nil))
        let size = CGSize(width: 512, height: 384)

        _ = provider.artwork(for: size)                     // the drawing seam: schedules the build
        await settle(provider) { provider.renderedArtwork(for: size) != nil }

        let measured = try XCTUnwrap(provider.renderedArtwork(for: size),
                                     "the drawing seam's build never reached the measuring seam")
        XCTAssertTrue(measured.matches(size: size),
                      "the measuring seam answered a frame built for another size")
        XCTAssertFalse(measured.wasScaledToFit,
                       "the measuring seam answered a stand-in, which is what it exists to refuse")
    }

    /// **"This skin lends no border" and "its borders have not resolved yet" are different answers,
    /// and `donorInsets` gives nil to both.**
    ///
    /// The distinction is what `hostedSurfaceBordersAreSettled` is built on. Without it, gating the
    /// interior read on resolved insets would have frozen every window under a skin that lends
    /// nothing at all: its insets never resolve, so a user's resize would never be adopted and the
    /// rule would put the window straight back.
    @MainActor
    func testLendsFrameTellsNoDonorApartFromInsetsNotYetResolved() async throws {
        let provider = WMPHostedFrameProvider()
        XCTAssertFalse(provider.lendsFrame, "a provider with no skin cannot lend a frame")

        let skin = try await ringSkin()
        XCTAssertTrue(provider.configure(skin: skin, playerViewID: nil))
        XCTAssertTrue(provider.lendsFrame,
                      "a ring donor lends a frame from the moment it is configured, "
                        + "whether or not its insets have resolved")

        await settle(provider) { provider.donorInsets != nil }
        XCTAssertNotNil(provider.donorInsets, "the ring donor never resolved its insets")

        provider.reset()
        XCTAssertFalse(provider.lendsFrame)
        XCTAssertNil(provider.donorInsets)
    }
}
