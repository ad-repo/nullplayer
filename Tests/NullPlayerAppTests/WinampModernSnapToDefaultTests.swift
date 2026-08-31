import XCTest
@testable import NullPlayer

/// B81 — Snap To Default has to be able to recover a `.wal` window.
///
/// The classic routine stacks windows read off the per-feature controllers, and in Winamp Modern
/// those are almost all nil: a skin's auxiliary containers and the hosted windows live elsewhere. So
/// the command moved only the player, and a skin-owned window dragged off the display had no way
/// back. The modern routine re-centres the player and then re-runs the launch arrangement — the
/// `WinampModernTiler` sweep — over everything else.
///
/// The AppKit half needs real windows and is verified live (see the skill). The two pure pieces are
/// the re-centring and the guarantee that tiling from a re-centred player brings a stranded window
/// back onto the screen, and those are what this pins.
final class WinampModernSnapToDefaultTests: XCTestCase {

    private let region = NSRect(x: 0, y: 0, width: 1600, height: 1000)

    // MARK: - Re-centring the player

    func testThePlayerIsCentredOnTheRegionAtItsOwnSize() {
        let frame = WindowManager.recenteredPlayerFrame(size: NSSize(width: 400, height: 380),
                                                        in: region)
        XCTAssertEqual(frame.size, NSSize(width: 400, height: 380), "the size is user state")
        XCTAssertEqual(frame.midX, region.midX)
        XCTAssertEqual(frame.midY, region.midY)
    }

    /// Unlike the launch sweep, this *moves* the player: recovering one dragged off the display is
    /// half the point of the command.
    func testAStrandedPlayerComesBackOntoTheRegion() {
        let frame = WindowManager.recenteredPlayerFrame(size: NSSize(width: 197, height: 297),
                                                        in: region)
        XCTAssertTrue(region.contains(frame))
    }

    /// A skin larger than the display must still land with its top-left visible, so the size is
    /// clamped before it is centred. Without this the "recovery" re-strands it.
    func testAPlayerLargerThanTheRegionIsClampedToIt() {
        let frame = WindowManager.recenteredPlayerFrame(size: NSSize(width: 2400, height: 1400),
                                                        in: region)
        XCTAssertEqual(frame, region)
    }

    func testTheRegionOriginIsHonouredRatherThanAssumedZero() {
        let offset = NSRect(x: -1200, y: 300, width: 800, height: 600)
        let frame = WindowManager.recenteredPlayerFrame(size: NSSize(width: 200, height: 100),
                                                        in: offset)
        XCTAssertEqual(frame.midX, offset.midX)
        XCTAssertEqual(frame.midY, offset.midY)
        XCTAssertTrue(offset.contains(frame))
    }

    // MARK: - The recovery the two pieces make together

    /// Ebonite's measured set on the display it was reported from — the reported case, reproduced.
    /// Every window comes back inside the region and none overlaps another or the player.
    ///
    /// Non-overlap is the invariant; staying on screen is a *preference* the tiler deliberately
    /// gives up when the screen runs out, since a right-edge clamp can only pull a column left into
    /// the one already there (see `WinampModernWindowTilingTests`). So containment is asserted
    /// against the 1920x1080 the live measurement was taken on, not as a universal claim.
    func testTilingFromTheRecentredPlayerRecoversEveryWindow() {
        let region = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let player = WindowManager.recenteredPlayerFrame(size: NSSize(width: 197, height: 297),
                                                         in: region)
        var tiler = WindowManager.WinampModernTiler(playerFrame: player, region: region)
        let sizes = [NSSize(width: 344, height: 250),   // Pledit
                     NSSize(width: 147, height: 106),   // equalizer
                     NSSize(width: 640, height: 400),   // nullplayer.library
                     NSSize(width: 197, height: 145)]   // a hosted spectrum window
        var placed: [NSRect] = [player]
        for size in sizes {
            let slot = tiler.nextSlot(for: size)
            XCTAssertTrue(region.contains(slot),
                          "\(NSStringFromRect(slot)) is not back on the screen")
            for other in placed {
                XCTAssertFalse(slot.intersects(other),
                               "\(NSStringFromRect(slot)) overlaps \(NSStringFromRect(other))")
            }
            placed.append(slot)
        }
    }

    // MARK: - One press, and only one

    /// The user-visible contract. The command used to need several presses and sometimes never
    /// worked: it re-ran the *same unclamped tiler*, so it reproduced the same off-screen layout,
    /// and only appeared to improve because more windows had materialized between presses and the
    /// occupancy set differed each time. With the tiler clamped, one sweep leaves everything on
    /// screen.
    func testOnePressLeavesEveryWindowReachable() {
        let player = WindowManager.recenteredPlayerFrame(size: NSSize(width: 1000, height: 878),
                                                         in: region)
        var tiler = WindowManager.WinampModernTiler(playerFrame: player, region: region)
        let sizes = [NSSize(width: 700, height: 500), NSSize(width: 700, height: 500),
                     NSSize(width: 900, height: 400), NSSize(width: 426, height: 122)]
        for size in sizes {
            let slot = tiler.nextSlot(for: size)
            XCTAssertTrue(WindowPlacement.isReachable(slot, screens: [region]),
                          "\(NSStringFromRect(slot)) is unreachable after one press")
        }
    }

    /// A second press must change nothing. The old routine was not idempotent, which is what made
    /// "press it a few times" the folk remedy.
    func testASecondPressIsANoOp() {
        let size = NSSize(width: 1000, height: 878)
        let first = WindowManager.recenteredPlayerFrame(size: size, in: region)
        let second = WindowManager.recenteredPlayerFrame(size: first.size, in: region)
        XCTAssertEqual(first, second)

        func arrangement(from player: NSRect) -> [NSRect] {
            var tiler = WindowManager.WinampModernTiler(playerFrame: player, region: region)
            return [NSSize(width: 700, height: 500), NSSize(width: 900, height: 400)]
                .map { tiler.nextSlot(for: $0) }
        }
        XCTAssertEqual(arrangement(from: first), arrangement(from: second))
    }

    /// A window the arrangement does not own — a classic-fallback playlist, the standalone video
    /// window — is rescued rather than left where it is. `nil` used to mean "leave it", and where it
    /// was is exactly the problem.
    func testAWindowTheArrangementDoesNotOwnIsStillBroughtBack() {
        let stranded = NSRect(x: 4000, y: -900, width: 500, height: 400)
        XCTAssertFalse(WindowPlacement.isReachable(stranded, screens: [region]))
        let host = WindowPlacement.hostScreen(for: stranded, screens: [region])
        XCTAssertNotNil(host)
        let rescued = WindowPlacement.rescued(stranded, into: host!)
        XCTAssertTrue(WindowPlacement.isReachable(rescued, screens: [region]))
        XCTAssertEqual(rescued.size, stranded.size, "recovery never resizes")
    }
}
