import AppKit
import XCTest
@testable import NullPlayer

/// W217 — `.wmz` windows have to be placeable and recoverable, and neither was true.
///
/// Two seams branched only on `.winampModern` and let `.wmp` fall through to the Classic stack:
/// `WindowManager.positionSubWindow`, which opens each window under the lowest one already open
/// and clamps nothing, and `snapToDefaultPositions`, whose Classic routine measures against
/// `screen.frame`, builds its column from the per-feature controllers, and ends with no
/// reachability pass. In Classic both are fine — a parked window is a placement, not damage. In
/// `.wmz` the windows are borderless: once one walks past an edge there is no title bar left to
/// drag it back by, and the app offered no route home.
///
/// The AppKit half needs real windows and was verified live (see `wmp-skin-guide`). The pure piece
/// is the geometry, and that is what this pins: the failure the Classic stack produced, and that
/// one shared `WinampModernTiler` — the same instrument `.wal` recovers with — does not produce it.
final class WMPSnapToDefaultTests: XCTestCase {

    /// The display the live measurement was taken on: 1800x1169 with a 39pt menu bar.
    private let region = NSRect(x: 0, y: 0, width: 1800, height: 1130)

    /// `Halo 2`'s player, and the ten windows opened over it in the measured session, in the order
    /// the Windows menu opens them.
    private let player = NSSize(width: 327, height: 294)
    private let session = [NSSize(width: 406, height: 209),   // eqView (the skin's own)
                           NSSize(width: 406, height: 265),   // plView (the skin's own)
                           NSSize(width: 346, height: 192),   // Spectrum Analyzer
                           NSSize(width: 335, height: 257),   // PeppyMeter
                           NSSize(width: 590, height: 651),   // Waveform
                           NSSize(width: 335, height: 182),   // Cava
                           NSSize(width: 335, height: 182),   // Audio Analyzer
                           NSSize(width: 335, height: 182),   // Flow
                           NSSize(width: 660, height: 507),   // Library Browser
                           NSSize(width: 914, height: 507)]   // Visualizations

    // MARK: - The failure the gate was letting through

    /// The Classic stack, reproduced: each window opens flush under the lowest one already open,
    /// with nothing stopping the column at the bottom of the screen. Measured live before the fix
    /// on exactly this set — Cava straddled the bottom edge, Audio Analyzer opened entirely below
    /// it and Flow 200pt further down again.
    ///
    /// This is not a claim about Classic, where the same walk is the intended arrangement. It is
    /// the reason `.wmz` could not be left in it.
    func testTheClassicStackWalksOffTheBottomOfTheScreen() {
        let playerFrame = WindowManager.recenteredPlayerFrame(size: player, in: region)
        var nextY = playerFrame.minY
        var stranded = 0
        for size in session {
            nextY -= size.height
            let frame = NSRect(x: playerFrame.minX, y: nextY, width: size.width, height: size.height)
            if !WindowPlacement.isReachable(frame, screens: [region]) { stranded += 1 }
        }
        XCTAssertGreaterThan(stranded, 0,
                             "the unbounded column is the defect; if it no longer strands anything, "
                             + "the stack rule changed and this test is the record of why the gate exists")
    }

    // MARK: - What replaces it

    /// One tiler, walked once, over the measured session: every window lands inside the visible
    /// frame. The clamp lives in `WinampModernTiler.nextSlot`, which is why `.wmz` shares it rather
    /// than growing a second definition of "on screen".
    func testOneSharedTilerKeepsTheWholeSessionOnScreen() {
        let playerFrame = WindowManager.recenteredPlayerFrame(size: player, in: region)
        XCTAssertTrue(region.contains(playerFrame))
        var tiler = WindowManager.WinampModernTiler(playerFrame: playerFrame, region: region)
        for size in session {
            let slot = tiler.nextSlot(for: size)
            XCTAssertTrue(WindowPlacement.isReachable(slot, screens: [region]),
                          "\(NSStringFromRect(slot)) is unreachable after one press")
            XCTAssertTrue(region.intersects(slot),
                          "\(NSStringFromRect(slot)) is off the display entirely")
        }
    }

    /// The contract the command has to keep: a second press changes nothing. The arrangement is a
    /// function of the player's frame and the window sizes, and re-centring an already-centred
    /// player is a fixed point — so running it twice must produce the same slots.
    func testASecondPressIsANoOp() {
        func arrangement() -> [NSRect] {
            let playerFrame = WindowManager.recenteredPlayerFrame(size: player, in: region)
            var tiler = WindowManager.WinampModernTiler(playerFrame: playerFrame, region: region)
            return session.map { tiler.nextSlot(for: $0) }
        }
        XCTAssertEqual(arrangement(), arrangement())
    }

    /// The per-window `tiledOrigin(for:avoiding:)` call is the wrong instrument here, and this is
    /// why. It builds a *fresh* tiler each time and returns the first slot free of the occupancy
    /// set, which is how a window opened **after** an arrangement joins one; asked to lay out a
    /// whole session it re-derives every column from the current window's own width, and late
    /// windows pile onto each other. A shared cursor is what makes the result an arrangement.
    func testASharedCursorIsWhatSeparatesTheSlots() {
        let playerFrame = WindowManager.recenteredPlayerFrame(size: player, in: region)
        var tiler = WindowManager.WinampModernTiler(playerFrame: playerFrame, region: region)
        var placed: [NSRect] = []
        for size in session {
            let slot = tiler.nextSlot(for: size)
            XCTAssertFalse(placed.contains(slot),
                           "\(NSStringFromRect(slot)) was handed out twice")
            placed.append(slot)
        }
    }

    // MARK: - Recovery

    /// A window the arrangement does not own — one owned by no controller in either list — is
    /// rescued rather than left where it is, and recovery never resizes it. This is the leg the
    /// live run could not exercise: a `.wmz` window is not movable by its background and macOS
    /// clamps a drag at the screen edge, so a genuinely stranded one cannot be produced by hand.
    func testAStrandedWindowIsBroughtBackWithoutBeingResized() {
        let stranded = NSRect(x: 3200, y: -1400, width: 406, height: 209)
        XCTAssertFalse(WindowPlacement.isReachable(stranded, screens: [region]))
        let host = try? XCTUnwrap(WindowPlacement.hostScreen(for: stranded, screens: [region]))
        let rescued = WindowPlacement.rescued(stranded, into: host ?? region)
        XCTAssertTrue(WindowPlacement.isReachable(rescued, screens: [region]))
        XCTAssertEqual(rescued.size, stranded.size, "recovery moves, it never resizes")
    }
}
