import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// **What a hosted window wears while its own frame does not exist yet (W248, reworked 2026-09-23).**
///
/// `WMPHostedFrameProvider` never blocks, so every one of these moments is answered with something
/// other than the frame that was asked for, and the requirement is that none of it is visible as a
/// transition:
///
/// - **A stand-in is the nearest render re-laid out, never stretched.** W248 refused a stretched
///   ring past 15% and drew palette chrome instead, and a drag crosses 15% in a few pixels — the
///   reported skin → chrome → skin flicker.
/// - **A drag builds one frame at a time and cannot evict a resting window's frame.**
/// - **A skin change keeps the old skin live until the new one can dress every open window**, then
///   switches them all at once. The W248 "outgoing" stand-in it replaces is what left windows
///   wearing the previous skin after a drag.
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

    // MARK: - A stand-in is re-laid out, never stretched

    /// **A size nothing has rendered is answered with the nearest render re-laid out (2026-09-23).**
    ///
    /// W248 refused a stretched ring past 15% and the window drew palette chrome, which a drag
    /// crossed within a few pixels: skin → chrome → skin. A relayout keeps the border's thickness
    /// at any distance, so no tolerance applies and the insets are the source's exactly.
    func testAStandInForAnotherSizeKeepsTheBorderItWasRenderedWith() async throws {
        let (provider, rendered) = try await providerWithRenderedFrame()

        let far = CGSize(width: 900, height: 900)
        let answered = try XCTUnwrap(provider.artwork(for: far),
                                     "a window far from the rendered size was left on palette chrome")

        XCTAssertEqual(answered.size.width, far.width, accuracy: 0.5)
        XCTAssertEqual(answered.size.height, far.height, accuracy: 0.5)
        XCTAssertEqual(answered.metrics.titleHeight, rendered.metrics.titleHeight, accuracy: 0.5,
                       "the border was stretched with the window")
        XCTAssertEqual(answered.metrics.leftBorder, rendered.metrics.leftBorder, accuracy: 0.5)
        XCTAssertEqual(answered.metrics.rightBorder, rendered.metrics.rightBorder, accuracy: 0.5)
        XCTAssertEqual(answered.metrics.bottomBorder, rendered.metrics.bottomBorder, accuracy: 0.5)
        let pixelsPerPoint = CGFloat(rendered.image.width) / rendered.size.width
        XCTAssertEqual(CGFloat(answered.image.width), far.width * pixelsPerPoint, accuracy: 1,
                       "the picture was not re-laid out to the window, only mapped onto it")
    }

    /// **The seams fall between the borders, and the output adds up to the target.** Growing
    /// repeats a column, shrinking removes some, and the border columns are copied one for one.
    func testARelayoutPlanLeavesTheBordersWhole() {
        let uniform = [Bool](repeating: true, count: 99)
        for target in [60, 100, 250] {
            let segments = try! XCTUnwrap(WMPHostedFrameRelayout.plan(
                length: 100, target: target, lead: 20, trail: 15, uniform: uniform))
            XCTAssertEqual(segments.map(\.length).reduce(0, +), target)
            XCTAssertEqual(segments.first, .init(source: 0, length: segments.first!.length, repeats: false))
            XCTAssertGreaterThanOrEqual(segments.first!.length, 20, "the leading border was cut")
            XCTAssertFalse(segments.last!.repeats)
            XCTAssertEqual(segments.last!.source + segments.last!.length, 100)
            XCTAssertGreaterThanOrEqual(segments.last!.length, 15, "the trailing border was cut")
        }
        XCTAssertNil(WMPHostedFrameRelayout.plan(length: 100, target: 30, lead: 20, trail: 15,
                                                 uniform: uniform),
                     "a window too small for its border was answered")
    }

    // MARK: - A drag

    /// **One drag build at a time, and the latest size behind it (step B).** Every pixel of a drag
    /// used to start its own render — ~30 at once on `ALXVortex`, each 2–4.7 s. A size the drag
    /// only passed through while a build was running is never built.
    func testADragBuildsTheLatestSizeNotEverySize() async throws {
        let (provider, _) = try await providerWithRenderedFrame()
        provider.beginLiveResize()

        let first = CGSize(width: 410, height: 300)
        let passedThrough = CGSize(width: 420, height: 300)
        let latest = CGSize(width: 430, height: 300)
        _ = provider.artwork(for: first)
        _ = provider.artwork(for: passedThrough)
        _ = provider.artwork(for: latest)

        _ = try await waitForRender(provider, at: latest)
        XCTAssertNil(provider.renderedArtwork(for: passedThrough),
                     "a size the drag only passed through was rendered")
        provider.endLiveResize(at: latest)
    }

    /// **A drag cannot evict a resting window's frame (step B).** The cache holds twelve sizes and
    /// a drag passes through more than that; the untouched windows then missed their frame and wore
    /// the previous skin's. The drag's own sizes go first, and all but the last go when it ends.
    func testADragNeverEvictsAWindowAtRest() async throws {
        let (provider, _) = try await providerWithRenderedFrame()
        provider.beginLiveResize()
        var sizes: [CGSize] = []
        for step in 1...14 {
            let size = CGSize(width: 400 + CGFloat(step) * 7, height: 300)
            sizes.append(size)
            _ = provider.artwork(for: size)
            _ = try await waitForRender(provider, at: size)
        }
        XCTAssertNotNil(provider.renderedArtwork(for: Self.windowSize),
                        "the drag pushed a resting window's frame out of the cache")

        provider.endLiveResize(at: sizes.last!)
        XCTAssertNil(provider.renderedArtwork(for: sizes[sizes.count - 2]),
                     "an intermediate drag size outlived the drag")
        XCTAssertNotNil(provider.renderedArtwork(for: sizes.last!),
                        "the size the drag came to rest at was dropped")
        XCTAssertNotNil(provider.renderedArtwork(for: Self.windowSize))
    }

    // MARK: - A skin change

    /// **The old skin answers, unchanged, until the new one can dress every open window — then all
    /// of them change at once (step E).** No stand-in of the previous skin exists any more: before
    /// the commit the window wears the old skin's exact frame, after it the new skin's.
    func testASkinChangeKeepsTheOldSkinLiveUntilItCommits() async throws {
        let (provider, outgoing) = try await providerWithRenderedFrame(corner: 40, red: 20)
        provider.hostedWindowsVisible = { true }
        provider.openWindowTargets = { _ in [Self.windowSize] }

        let incomingSkin = try await ringSkin(corner: 30, red: 200, tag: "b")
        XCTAssertTrue(provider.configure(skin: incomingSkin, playerViewID: nil))
        XCTAssertEqual(provider.artwork(for: Self.windowSize)?.image, outgoing.image,
                       "the window stopped wearing the live skin before the new one was ready")

        let deadline = Date().addingTimeInterval(20)
        while provider.renderedArtwork(for: Self.windowSize)?.image == outgoing.image,
              Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let incoming = try XCTUnwrap(provider.renderedArtwork(for: Self.windowSize),
                                     "the switch committed without the window's own frame")
        XCTAssertNotEqual(incoming.image, outgoing.image, "the new skin never replaced the old one")
        XCTAssertEqual(provider.artwork(for: Self.windowSize)?.image, incoming.image)
    }

    /// **A held-back player commits with the frames (step E).** `stage` returns once every target
    /// has its frame; until `configure` the old skin is still live, and `configure` flips it in one
    /// call — the new border and every target's exact frame at once.
    func testAStagedSwitchCommitsEveryTargetInOneStep() async throws {
        let (provider, outgoing) = try await providerWithRenderedFrame(corner: 40, red: 20)
        let deadline = Date().addingTimeInterval(20)
        while provider.donorInsets == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let outgoingInsets = try XCTUnwrap(provider.donorInsets)
        // The new border moves the window: the target is a size the old skin never rendered.
        let moved = CGSize(width: Self.windowSize.width, height: Self.windowSize.height - 3)
        provider.hostedWindowsVisible = { true }
        provider.openWindowTargets = { _ in [moved] }

        let incomingSkin = try await ringSkin(corner: 30, red: 200, tag: "b")
        await provider.stage(skin: incomingSkin, playerViewID: nil)
        XCTAssertEqual(provider.artwork(for: Self.windowSize)?.image, outgoing.image,
                       "staging replaced the live skin before the player was presented")
        XCTAssertEqual(provider.donorInsets?.top, outgoingInsets.top)

        XCTAssertTrue(provider.configure(skin: incomingSkin, playerViewID: nil))
        XCTAssertNotEqual(provider.donorInsets?.top, outgoingInsets.top, "the border did not change")
        XCTAssertNotNil(provider.renderedArtwork(for: moved),
                        "a window resized to the new border would have drawn without its frame")
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
