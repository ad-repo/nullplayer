import AppKit

/// Where a `.wal` skin's windows go.
///
/// Winamp Modern has no center stack — a skin's windows are whatever shape and size the author
/// chose — so their arrangement is a **tiling**, computed in one deterministic sweep rather than
/// negotiated per window as each one opens.
///
/// That distinction is the whole fix. Deciding a window's spot when it opens cannot work here:
/// at launch the skin's containers are created and shown during skin load, before `WindowManager`
/// has revealed the player at its restored frame, and before the UI-size pass has settled the
/// sizes. Measured on Defix, every window was placed against a player at `{{0,695},{406,355}}`
/// that finished at `{{0,677},{426,373}}`, and against its own size 5% smaller than it ended up.
/// Nor can the skin's own `default_x`/`default_y` be the answer: Defix's put `pledit` at x 822–1228
/// and the media library at x 1120–1920, overlapping by 108px before anything else happens.
///
/// So the layout is generated, not repaired. Columns run down from the player, each window flush
/// under the last; a window that will not fit starts the next column to the right. Fixed order and
/// no iteration — the same inputs always give the same arrangement. Only a window with no clear slot
/// is scored, and then only to pick whichever candidate covers least (`leastCovered`).
struct WinampModernTiler {
    let region: NSRect
    private var columnX: CGFloat
    private var columnWidth: CGFloat
    private var cursorY: CGFloat
    /// The columns left of the player, which fill right-to-left from its left edge: the right
    /// edge of the next one, its widest member so far, and its cursor.
    private var leftColumnMaxX: CGFloat
    private var leftColumnWidth: CGFloat = 0
    private var leftCursorY: CGFloat
    /// The player, which every placement cost weighs above the windows it opens.
    private let player: NSRect
    /// Every slot handed out so far, and the player: what a clamped slot must not land on.
    private var placed: [NSRect]
    /// Which cursor the last slot advanced, for `skip(past:)`.
    private var lastSlotWasLeft = false

    /// The player is the anchor and never moves: it owns the top of the first column, and the
    /// first slot is flush beneath it.
    init(playerFrame: NSRect, region: NSRect) {
        self.region = region
        self.columnX = playerFrame.minX
        self.columnWidth = playerFrame.width
        self.cursorY = playerFrame.minY
        self.leftColumnMaxX = playerFrame.minX
        self.leftCursorY = region.maxY
        self.player = playerFrame
        self.placed = [playerFrame]
    }

    /// The next slot for a window of `size`, advancing the cursor past it.
    mutating func nextSlot(for size: NSSize) -> NSRect {
        if cursorY - size.height < region.minY {
            columnX += columnWidth
            columnWidth = 0
            cursorY = region.maxY
        }
        var slot = clampedToBottom(NSRect(x: columnX, y: cursorY - size.height,
                                          width: size.width, height: size.height))
        // Overlapping windows are preferable to hidden ones, so a slot past the right edge comes
        // back onto the region. With a skin wider than half the display (EPS, Big Bento,
        // cPro-Bento) column 2 starts past `region.maxX`, and before the clamp *every* window
        // after the first column opened off screen. But a clamp can only pull a slot left, into
        // what is already there — at 125% UI Size a centred Sony_Walkman player had the library
        // pulled 69pt over it (B153) while the whole width left of the player stood empty. So
        // the clamp is the last resort: first the clamped slot if it lands on nothing, then the
        // columns left of the player, and only then whichever clamp covers less.
        if slot.maxX > region.maxX {
            let clamped = NSRect(x: max(region.minX, region.maxX - size.width), y: slot.minY,
                                 width: size.width, height: size.height)
            if overlap(of: clamped) == 0 {
                slot = clamped
            } else if let left = nextLeftSlot(for: size) {
                placed.append(left)
                lastSlotWasLeft = true
                return left
            } else {
                let leftClamped = clampedToBottom(NSRect(
                    x: region.minX, y: leftSlotTop(for: size) - size.height,
                    width: size.width, height: size.height))
                // The region's bottom corners too: on a crowded display a window wider than
                // either side of the player clamped onto the **player** both ways, where a corner
                // only clips a sub-window. Mac OS X Panther's 834pt library beside a centred
                // 310pt player is the measured case.
                // Ties go to the earlier candidate, so `clamped` wins unless something beats it.
                let bottomCorners = corners(for: size).prefix(2)
                let best = leastCovered(clamped, [leftClamped] + bottomCorners, among: placed)
                if best == leftClamped {
                    _ = nextLeftSlot(for: size, clampingTo: leftClamped)
                    placed.append(leftClamped)
                    lastSlotWasLeft = true
                    return leftClamped
                }
                if best != clamped {
                    placed.append(best)
                    lastSlotWasLeft = false
                    return best
                }
                slot = clamped
            }
        }
        cursorY = slot.minY
        columnWidth = max(columnWidth, size.width)
        placed.append(slot)
        lastSlotWasLeft = false
        return slot
    }

    /// The last slot landed on `obstacles`, so the next one starts flush under the lowest of
    /// them rather than one window-height further down (B157). Every slot whose top is above
    /// that edge would overlap it too, so nothing clear is skipped.
    mutating func skip(past obstacles: [NSRect]) {
        guard let bottom = obstacles.map(\.minY).min() else { return }
        if lastSlotWasLeft {
            leftCursorY = min(leftCursorY, bottom)
        } else {
            cursorY = min(cursorY, bottom)
        }
    }

    /// A window taller than the region keeps its top on screen rather than its bottom.
    private func clampedToBottom(_ slot: NSRect) -> NSRect {
        var slot = slot
        if slot.minY < region.minY { slot.origin.y = region.minY }
        return slot
    }

    /// The top of the left column a window of `size` would go in, wrapping to a fresh column.
    private func leftSlotTop(for size: NSSize) -> CGFloat {
        leftCursorY - size.height < region.minY ? region.maxY : leftCursorY
    }

    /// The next slot left of the player, or `nil` when it would leave the region or land on a
    /// window already placed, advancing the left cursor past what it returns. `clampingTo` takes
    /// a slot already pulled onto the region instead.
    private mutating func nextLeftSlot(for size: NSSize,
                                       clampingTo forced: NSRect? = nil) -> NSRect? {
        var maxX = leftColumnMaxX
        var width = leftColumnWidth
        var top = leftCursorY
        if top - size.height < region.minY {
            maxX -= width
            width = 0
            top = region.maxY
        }
        let slot = forced ?? clampedToBottom(NSRect(x: maxX - size.width, y: top - size.height,
                                                     width: size.width, height: size.height))
        guard forced != nil || (slot.minX >= region.minX && overlap(of: slot) == 0) else {
            return nil
        }
        leftColumnMaxX = maxX
        leftColumnWidth = max(width, size.width)
        leftCursorY = slot.minY
        return slot
    }

    /// A window of `size` pushed into each of the region's corners, the bottom two first.
    func corners(for size: NSSize) -> [NSRect] {
        [region.minY, region.maxY - size.height].flatMap { y in
            [region.minX, region.maxX - size.width].map {
                WindowPlacement.rescued(NSRect(x: $0, y: y, width: size.width, height: size.height),
                                        into: region)
            }
        }
    }

    /// The candidate that covers least of `others`, with the player's share counted four times:
    /// covering the player hides the controls everything else is opened from. Ties go to the
    /// earlier candidate.
    func leastCovered(_ first: NSRect, _ rest: [NSRect], among others: [NSRect]) -> NSRect {
        func cost(_ slot: NSRect) -> CGFloat {
            Self.area(of: slot, on: others) + 3 * Self.area(of: slot, on: [player])
        }
        return rest.reduce(first) { best, slot in cost(slot) < cost(best) ? slot : best }
    }

    /// How much of `slot` lies on windows already placed.
    private func overlap(of slot: NSRect) -> CGFloat { Self.area(of: slot, on: placed) }

    private static func area(of slot: NSRect, on others: [NSRect]) -> CGFloat {
        others.reduce(0) { total, other in
            let shared = other.intersection(slot)
            return total + (shared.isNull ? 0 : shared.width * shared.height)
        }
    }
}
