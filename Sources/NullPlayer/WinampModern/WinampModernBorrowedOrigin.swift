import CoreGraphics

/// **One window placed at another window's position** — and the one rule that recognises it.
///
/// A layout answers `getLeft()`/`getTop()` in its own canvas space (0), while the `x`/`y` a script
/// writes on a window are pushed to the desktop. B61 fixed the *self* round trip
/// (`me.resize(me.getLeft(), …)`) by recognising it and not moving. This is the *cross-window* one: a
/// script reads one window's position and writes a second window's from it. Two skins measured it:
///
/// - Itemskin's window chrome is a second, dynamic container per component window, and every frame
///   script keeps it on its content with `chrome.resize(content.getLeft(), content.getTop(), …)`.
///   Both are layouts, so both read 0, and the move was suppressed as a no-op (B69).
/// - ONYX V2 parks its visualization window over the player's art box one attribute at a time:
///   `vis.setXmlParam("x", player.getLeft() + 52)`. Taken as a plain move it went to desktop 52.
///
/// So a write on a window object is re-expressed in the space the *reader* was in — only when it
/// follows a read of a **different** window object, and only when it is either within a pixel of what
/// that read answered, or the read was a layout's canvas origin (0), whose arithmetic can only mean
/// "relative to that window". A value the script did not read stays a plain move, as it does for B61.
///
/// **A read is spent axis by axis by the write that uses it**, and forgotten when the outermost event
/// that made it unwinds, so a stale read can never pin a later write that only happens to name the
/// same coordinates: each `resize()` and each `setXmlParam` pair is preceded by its own reads.
struct WinampModernBorrowedOrigin {
    /// What a write on a window object asks for when its coordinates are another window's.
    enum Request: Equatable {
        /// That window's desktop origin plus the script's offset: the write is a pinned move there.
        case desktop(CGPoint)
        /// The window read was not on screen, so it had no position to lend. The write keeps its
        /// window where it is (B156).
        case offScreen
    }

    /// A position a script read off a window object: what `getLeft()`/`getTop()` answered, and the
    /// desktop origin that window actually sits at.
    struct Read {
        let window: WasabiObjectID
        let reported: CGPoint
        let desktop: CGPoint
        /// No answer (the headless harness) counts as on screen, as it did before B156.
        let onScreen: Bool
    }

    private var read: Read?
    private var unspentX = false
    private var unspentY = false

    mutating func record(_ read: Read) {
        self.read = read
        unspentX = true
        unspentY = true
    }

    /// The event that made the read has unwound.
    mutating func forget() { read = nil }

    /// The request a write of `x` and/or `y` on `window` really makes, with the window read — or nil
    /// when the write is not this idiom. An axis the write does not name stays at `current`.
    mutating func match(x: Double?, y: Double?, writtenOn window: WasabiObjectID,
                        current: CGPoint?) -> (request: Request, leader: WasabiObjectID)? {
        guard let read, read.window != window,
              x == nil || unspentX, y == nil || unspentY, x != nil || y != nil else { return nil }
        let deltaX = x.map { Int($0.rounded()) - Int(read.reported.x.rounded()) }
        let deltaY = y.map { Int($0.rounded()) - Int(read.reported.y.rounded()) }
        // A **one-pixel** tolerance, not an exact match, because the idiom demands it: Wasabi's
        // standard frame nudges its minimum-size clamp by ±1 to force a re-layout —
        // `frame.resize(content.getLeft()+1, content.getTop()+1, 258, 258)` then the same with −1
        // (`standardframe.m:501-517`). Read exactly, both writes miss by one, degrade to plain moves,
        // and park the frame in the corner of the display (B110). The offset is carried through to
        // the desktop origin, so the 1px jiggle the script asked for is what happens.
        let withinAPixel = [deltaX, deltaY].allSatisfy { abs($0 ?? 0) <= 1 }
        guard read.reported == .zero || withinAPixel else { return nil }
        guard let origin = Self.origin(read: read, deltaX: deltaX, deltaY: deltaY, current: current)
        else { return nil }
        if x != nil { unspentX = false }
        if y != nil { unspentY = false }
        if !unspentX && !unspentY { self.read = nil }
        // **A window that is not on screen has no position to lend** (B156). Itemskin's frame script
        // answers its content window's `onSetVisible(1)` with `syncContent()` *before* it shows the
        // frame, so the frame read is one the host has never placed. Taken as a pin, that parked the
        // content below the screen over the slot the tiler had just given it. The script's 10 ms timer
        // puts the frame on the content once it is shown, which is the direction the pair settles in.
        return (read.onScreen ? .desktop(origin) : .offScreen, read.window)
    }

    private static func origin(read: Read, deltaX: Int?, deltaY: Int?, current: CGPoint?) -> CGPoint? {
        guard let x = deltaX.map({ read.desktop.x + CGFloat($0) }) ?? current?.x,
              let y = deltaY.map({ read.desktop.y + CGFloat($0) }) ?? current?.y else { return nil }
        return CGPoint(x: x, y: y)
    }
}
