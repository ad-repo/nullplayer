import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// **What a hosted window wears while its own frame does not exist yet (W248).**
///
/// `WMPHostedFrameProvider` never blocks, so every one of these moments is answered with something
/// other than the frame that was asked for, and the whole of W248 is *which* something. Three
/// answers are pinned here, each reported by a user before it was written:
///
/// - **A stretched ring is refused for a window it was not built for.** The 15% tolerance was a
///   panel's rule; a ring was stretched without limit, so a first open — where `mostRecent` holds
///   the ring W230 primed at the *donor's* reference size — dressed a 550x890 library in a 389x247
///   player's frame. Reported 2026-09-20 as *"the window loads with stretched graphics"*.
/// - **A skin change keeps the outgoing skin's frames until the incoming skin answers.** The cache
///   was emptied the instant a new skin arrived, so every hosted window on screen dropped to flat
///   palette chrome for a full scene build — measured on AlienMorph → ALXVortex at **1.29 s**. The
///   prewarm cannot reach this case: the window is already open when the skin changes.
/// - **A speculative render is made before any window asks for it**, so the wait belongs to the
///   skin load rather than to the user's click.
///
/// The fixtures are two ring donors with *different* border thicknesses, because that is the case
/// the reporter's own pair is: the two skins lend different borders, so the change moves every
/// hosted window by the difference and the incoming size is one the outgoing skin never rendered.
@MainActor
final class WMPHostedFrameTransitionTests: XCTestCase {

    // MARK: - Fixtures

    private func skin(_ markup: String, images: [String: Data]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8))]
        for (path, data) in images { entries.append(WMPTestArchiveEntry(path, data: data)) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// A solid opaque block. A ring piece only has to be *there*; these tests measure which picture
    /// comes back, never what is painted on it.
    private func block(width: Int, height: Int, red: UInt8) throws -> Data {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = red
            rgba[index + 1] = 90
            rgba[index + 2] = 180
            rgba[index + 3] = 255
        }
        return try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: rgba)
    }

    /// A ring donor on a 400x300 view whose border is `corner` points on every side.
    ///
    /// **`tag` makes it a different skin, and it is not decoration.** `WMPHostedFrameTemplate` is
    /// `Equatable` and `configure(skin:playerViewID:)` short-circuits on an equal one, so two
    /// fixtures that differ only in their geometry and their pixels derive the *same* template and
    /// no skin change happens at all — the first draft of these tests measured a cache hit and read
    /// as "the new skin's frame never replaced the one held over". The tag suffixes every node id,
    /// which is what the template is identified by.
    private func ringSkin(corner: Int, red: UInt8, tag: String = "a") async throws -> WMPLoadedSkin {
        let far = 400 - corner
        let low = 300 - corner
        let hole = (width: 400 - corner * 2, height: 300 - corner * 2)
        return try await skin("""
        <THEME><VIEW id="plview\(tag)" width="400" height="300">
        <SUBVIEW id="tl\(tag)" horizontalAlignment="left"  verticalAlignment="top"
                 left="0" top="0" width="\(corner)" height="\(corner)" backgroundImage="corner.png"/>
        <SUBVIEW id="tr\(tag)" horizontalAlignment="right" verticalAlignment="top"
                 left="\(far)" top="0" width="\(corner)" height="\(corner)" backgroundImage="corner.png"/>
        <SUBVIEW id="bl\(tag)" horizontalAlignment="left"  verticalAlignment="bottom"
                 left="0" top="\(low)" width="\(corner)" height="\(corner)" backgroundImage="corner.png"/>
        <SUBVIEW id="br\(tag)" horizontalAlignment="right" verticalAlignment="bottom"
                 left="\(far)" top="\(low)" width="\(corner)" height="\(corner)" backgroundImage="corner.png"/>
        <SUBVIEW id="client\(tag)" horizontalAlignment="stretch" verticalAlignment="stretch"
                 left="\(corner)" top="\(corner)" width="\(hole.width)" height="\(hole.height)"/>
        </VIEW></THEME>
        """, images: ["corner.png": try block(width: corner, height: corner, red: red)])
    }

    /// A skin with no corners, from which no donor can be derived — the "lends nothing" case.
    private func bareSkin() async throws -> WMPLoadedSkin {
        try await skin("""
        <THEME><VIEW id="plview" width="400" height="300">
        <SUBVIEW id="client" horizontalAlignment="stretch" verticalAlignment="stretch"
                 left="0" top="0" width="400" height="300"/>
        </VIEW></THEME>
        """, images: [:])
    }

    private static let windowSize = CGSize(width: 400, height: 300)

    /// Poll until the provider has really rendered `size`. The builds are `Task`s the provider owns,
    /// so there is nothing to await directly; `renderedArtwork` is the measuring seam (W238) and
    /// answers the cache or nothing, which is exactly the question "has it landed yet".
    private func waitForRender(_ provider: WMPHostedFrameProvider, at size: CGSize,
                               timeout: TimeInterval = 20) async throws -> SkinnedSurfaceFrameArtwork {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let rendered = provider.renderedArtwork(for: size) { return rendered }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return try XCTUnwrap(nil as SkinnedSurfaceFrameArtwork?,
                             "no frame was rendered for \(size) within \(timeout)s")
    }

    /// A provider holding one rendered frame at `windowSize`, which is the state every transition
    /// below starts from: a window is open and dressed.
    private func providerWithRenderedFrame(corner: Int = 40, red: UInt8 = 20)
        async throws -> (WMPHostedFrameProvider, SkinnedSurfaceFrameArtwork) {
        let provider = WMPHostedFrameProvider()
        let loaded = try await ringSkin(corner: corner, red: red)
        XCTAssertTrue(provider.configure(skin: loaded, playerViewID: nil),
                      "the fixture lends no frame, so nothing below is being measured")
        _ = provider.artwork(for: Self.windowSize)
        let rendered = try await waitForRender(provider, at: Self.windowSize)
        return (provider, rendered)
    }

    // MARK: - A stand-in is for a resize, not for a different window

    /// **Past 15% a ring is refused, and the window takes the palette for that frame.**
    ///
    /// Before W248 this tolerance held panels only, and the ring came back stretched onto whatever
    /// was asked for. The size here is the shape of the reported case: a window more than twice the
    /// donor's height.
    func testARingStandInIsRefusedForAWindowItWasNotBuiltFor() async throws {
        let (provider, _) = try await providerWithRenderedFrame()

        let answered = provider.artwork(for: CGSize(width: 900, height: 900))

        XCTAssertNil(answered, "a ring was stretched onto a window it was never built for — W248 regressed")
    }

    /// **And inside the tolerance it still stands in**, which is the case it exists for: a live
    /// resize, where returning nil would drop the window to palette chrome for the drag and flash it
    /// back. Five percent, and the stretch is invisible for the frame or two before the real one.
    func testARingStandInStillCoversASmallResize() async throws {
        let (provider, rendered) = try await providerWithRenderedFrame()

        let nudged = CGSize(width: 420, height: 315)
        let answered = try XCTUnwrap(provider.artwork(for: nudged),
                                     "a 5% resize was left without a frame")

        XCTAssertEqual(answered.image, rendered.image, "the stand-in is not the frame that was rendered")
        XCTAssertEqual(answered.size.width, nudged.width, accuracy: 0.5)
        XCTAssertEqual(answered.size.height, nudged.height, accuracy: 0.5)
        XCTAssertTrue(answered.wasScaledToFit)
    }

    // MARK: - A skin change

    /// **The outgoing skin's frame covers the change, and is replaced the moment the new skin has
    /// one of its own.** Not "looks similar" — the same `CGImage`, then a different one.
    func testASkinChangeKeepsTheOutgoingFrameUntilTheNewSkinAnswers() async throws {
        let (provider, outgoing) = try await providerWithRenderedFrame(corner: 40, red: 20)

        let incomingSkin = try await ringSkin(corner: 30, red: 200, tag: "b")
        XCTAssertTrue(provider.configure(skin: incomingSkin, playerViewID: nil))
        let duringTheChange = try XCTUnwrap(provider.artwork(for: Self.windowSize),
                                            "the window was stripped to palette chrome by a skin change")
        XCTAssertEqual(duringTheChange.image, outgoing.image,
                       "something other than the outgoing skin's own frame was handed back")

        let incoming = try await waitForRender(provider, at: Self.windowSize)
        XCTAssertNotEqual(incoming.image, outgoing.image,
                          "the new skin's frame never replaced the one held over")
        XCTAssertEqual(provider.artwork(for: Self.windowSize)?.image, incoming.image,
                       "the outgoing frame outlived the answer that should have dropped it")
    }

    /// **A skin change is usually a size change too**, because the two skins lend different borders
    /// and every hosted window is grown or shrunk by the difference. The held frame covers the new
    /// size as well, within the same 15% — the reporter's pair moves the library 890 → 887.
    func testTheOutgoingFrameCoversTheSizeTheNewBorderCauses() async throws {
        let (provider, outgoing) = try await providerWithRenderedFrame(corner: 40, red: 20)

        let incomingSkin = try await ringSkin(corner: 30, red: 200, tag: "b")
        XCTAssertTrue(provider.configure(skin: incomingSkin, playerViewID: nil))
        let moved = CGSize(width: Self.windowSize.width, height: Self.windowSize.height - 3)
        let answered = try XCTUnwrap(provider.artwork(for: moved),
                                     "the three points the new border moved the window cost it its frame")

        XCTAssertEqual(answered.image, outgoing.image)
        XCTAssertEqual(answered.size.height, moved.height, accuracy: 0.5)
    }

    /// **A skin that lends no frame carries nothing over.** Its windows *should* go back to the
    /// palette, and holding the last skin's ring over them would dress them in a skin the user has
    /// left.
    func testASkinThatLendsNoFrameCarriesNothingOver() async throws {
        let (provider, _) = try await providerWithRenderedFrame()

        let bare = try await bareSkin()
        XCTAssertFalse(provider.configure(skin: bare, playerViewID: nil),
                       "the bare fixture derived a donor, so this test measures nothing")

        XCTAssertNil(provider.artwork(for: Self.windowSize),
                     "a skin that lends no frame went on wearing the previous skin's")
    }

    // MARK: - Before any window asks

    /// **A frame is built for a size no window has asked for**, which is the whole of the prewarm:
    /// the 1.28 s a ring costs is paid at skin load instead of on the user's click.
    func testPrewarmRendersASizeNoWindowHasAskedFor() async throws {
        let provider = WMPHostedFrameProvider()
        let loaded = try await ringSkin(corner: 40, red: 20)
        XCTAssertTrue(provider.configure(skin: loaded, playerViewID: nil))

        provider.prewarm([Self.windowSize])

        _ = try await waitForRender(provider, at: Self.windowSize)
    }

    /// **Once per size, not once per skin (W250).** `apply()` runs on a broadcast that fires many
    /// times over a skin's life and the sizes it can name *grow* as windows open and are resized,
    /// so a once-per-skin guard fixed the queue on the first broadcast and every window that came
    /// later paid for its render on screen. A size the first pass never heard of must still be
    /// built.
    func testPrewarmCoversASizeLearnedAfterTheFirstPass() async throws {
        let provider = WMPHostedFrameProvider()
        let loaded = try await ringSkin(corner: 40, red: 20)
        XCTAssertTrue(provider.configure(skin: loaded, playerViewID: nil))

        provider.prewarm([Self.windowSize])
        _ = try await waitForRender(provider, at: Self.windowSize)

        let second = CGSize(width: 360, height: 280)
        provider.prewarm([second])

        _ = try await waitForRender(provider, at: second)
    }

    // MARK: - The open that waits for its frame

    /// **A skin with no answer for a size is what `hold(_:until:)` waits on (W250).** The predicate
    /// separates three states a drawing view cannot tell apart: nothing rendered yet (a window
    /// opening here would wear palette chrome), a frame rendered for exactly this size, and a skin
    /// that lends nothing at all — the last of which is settled immediately, or the hold would
    /// never end.
    func testSettledAnswerIsFalseOnlyWhileAFrameIsStillOwed() async throws {
        let provider = WMPHostedFrameProvider()
        XCTAssertTrue(provider.hasSettledAnswer(for: Self.windowSize),
                      "a provider with no skin owes no frame and must not hold an open")

        let loaded = try await ringSkin(corner: 40, red: 20)
        XCTAssertTrue(provider.configure(skin: loaded, playerViewID: nil))
        XCTAssertFalse(provider.hasSettledAnswer(for: Self.windowSize),
                       "a size nothing has been rendered for is not an answer")

        provider.demand(Self.windowSize)
        _ = try await waitForRender(provider, at: Self.windowSize)

        XCTAssertTrue(provider.hasSettledAnswer(for: Self.windowSize),
                      "a rendered frame settles the size it was rendered for")
    }
}
