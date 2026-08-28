import XCTest
@testable import NullPlayer

/// B56 — where a `.wal` skin's windows go.
///
/// Winamp Modern has no center stack, so the arrangement is a **tiling** generated in one
/// deterministic sweep rather than negotiated per window as each one opens. Four attempts at the
/// latter failed, and the reason is not tunable: the inputs a per-window decision needs do not exist
/// when it runs. Measured on Defix, every window was placed during skin load against a player at
/// `{{0,695},{406,355}}` that finished at `{{0,677},{426,373}}`, and against its own size ~5% smaller
/// than it ended up.
///
/// The tiler is the pure part of that fix, so it is the part worth testing: given a player frame and
/// a screen, the same window sizes must always produce the same non-overlapping slots.
final class WinampModernWindowTilingTests: XCTestCase {

    /// A roomy screen with the player parked at the top-left, which is the arrangement's anchor.
    private let region = NSRect(x: 0, y: 0, width: 1600, height: 1000)
    private var player: NSRect { NSRect(x: 0, y: 620, width: 400, height: 380) }

    private func makeTiler() -> WindowManager.WinampModernTiler {
        WindowManager.WinampModernTiler(playerFrame: player, region: region)
    }

    // MARK: - Column packing

    func testFirstSlotSitsFlushBeneathThePlayer() {
        var tiler = makeTiler()
        let slot = tiler.nextSlot(for: NSSize(width: 400, height: 200))
        XCTAssertEqual(slot.minX, player.minX, "the first column is the player's own")
        XCTAssertEqual(slot.maxY, player.minY, "flush under the player, not overlapping it")
        XCTAssertFalse(slot.intersects(player))
    }

    func testWindowsStackFlushDownTheColumn() {
        var tiler = makeTiler()
        let first = tiler.nextSlot(for: NSSize(width: 400, height: 200))
        let second = tiler.nextSlot(for: NSSize(width: 400, height: 150))
        XCTAssertEqual(second.maxY, first.minY, "each window sits flush under the last")
        XCTAssertEqual(second.minX, first.minX)
        XCTAssertFalse(second.intersects(first))
    }

    func testAWindowThatWillNotFitStartsTheNextColumn() {
        var tiler = makeTiler()
        // 620pt of room below the player; this consumes 600 of it.
        _ = tiler.nextSlot(for: NSSize(width: 400, height: 600))
        let wrapped = tiler.nextSlot(for: NSSize(width: 300, height: 200))
        XCTAssertEqual(wrapped.minX, player.maxX, "the new column clears the widest of the last")
        XCTAssertEqual(wrapped.maxY, region.maxY, "and starts at the top of the screen")
    }

    /// A column is as wide as its widest member, so the next column cannot cut back into it.
    func testNextColumnClearsTheWidestWindowInThePrevious() {
        var tiler = makeTiler()
        let wide = tiler.nextSlot(for: NSSize(width: 800, height: 600))
        let wrapped = tiler.nextSlot(for: NSSize(width: 200, height: 200))
        XCTAssertEqual(wrapped.minX, wide.maxX)
        XCTAssertFalse(wrapped.intersects(wide))
    }

    // MARK: - The property that matters

    /// The whole point: whatever the sizes, no two slots may overlap, and none may cover the player.
    func testNoSlotEverOverlapsAnotherOrThePlayer() {
        var tiler = makeTiler()
        // Defix's real set, at the sizes it settles on: playlist, VISCON, media library, two speaker
        // cabinets, then a hosted equalizer and spectrum.
        let sizes = [
            NSSize(width: 426, height: 373), NSSize(width: 426, height: 378),
            NSSize(width: 840, height: 630), NSSize(width: 299, height: 373),
            NSSize(width: 299, height: 373), NSSize(width: 426, height: 122),
            NSSize(width: 360, height: 152)
        ]
        var placed: [NSRect] = [player]
        for size in sizes {
            let slot = tiler.nextSlot(for: size)
            XCTAssertEqual(slot.size, size, "a slot never resizes the window it is for")
            for other in placed {
                XCTAssertFalse(slot.intersects(other),
                               "\(NSStringFromRect(slot)) overlaps \(NSStringFromRect(other))")
            }
            placed.append(slot)
        }
    }

    /// Same inputs, same arrangement — there is no scoring and no iteration to drift.
    func testTilingIsDeterministic() {
        let sizes = [NSSize(width: 426, height: 373), NSSize(width: 840, height: 630),
                     NSSize(width: 299, height: 373)]
        func run() -> [NSRect] {
            var tiler = makeTiler()
            return sizes.map { tiler.nextSlot(for: $0) }
        }
        XCTAssertEqual(run(), run())
    }

    // MARK: - Edges

    /// The screen runs out before the windows do. Columns keep marching right rather than being
    /// clamped back on screen: a clamp can only pull a column *left*, into the one already there,
    /// which is a real overlap traded for a cosmetic one. Non-overlap is the invariant here.
    func testAFullScreenMarchesRightRatherThanOverlapping() {
        var tiler = makeTiler()
        var placed: [NSRect] = [player]
        for _ in 0..<14 {
            let slot = tiler.nextSlot(for: NSSize(width: 500, height: 900))
            for other in placed {
                XCTAssertFalse(slot.intersects(other),
                               "\(NSStringFromRect(slot)) overlaps \(NSStringFromRect(other))")
            }
            XCTAssertGreaterThanOrEqual(slot.minX, placed.last!.minX, "a column never moves left")
            placed.append(slot)
        }
    }

    /// A window taller than the room beneath the player still gets a whole column of its own rather
    /// than being wedged into a gap it does not fit.
    func testAWindowTallerThanTheColumnGetsItsOwnColumn() {
        var tiler = makeTiler()
        let tall = tiler.nextSlot(for: NSSize(width: 300, height: 900))
        XCTAssertFalse(tall.intersects(player))
        XCTAssertEqual(tall.maxY, region.maxY, "no room under the player, so it starts a column")
    }
}
