import AppKit

/// The windows a `.wal` skin's script keeps glued together: a frame drawn in a second window parked on
/// its content window (Ebonite, Itemskin, Pure Inspired, K-jr, MoonLight). The runtime learns each
/// pair from the script (`windowsGluedOver`); this keeps the pairs moving, stacking and dragging as
/// one. Owned by `WinampModernMainWindowController`, which supplies the pairs (B162).
final class WinampModernGluedWindows {
    /// `WINAMP_MODERN_GLUE_TRACE=1` — the script-glued window pairs and every restack, live.
    static let traces = ProcessInfo.processInfo.environment["WINAMP_MODERN_GLUE_TRACE"] != nil
    /// `WINAMP_MODERN_DRAG_GLUE=0` turns off carrying a glued frame with its window during a drag.
    static let carriesInDrag = ProcessInfo.processInfo.environment["WINAMP_MODERN_DRAG_GLUE"] != "0"

    /// The pairs the skin's scripts have glued, by container, leader first. Set by the owner.
    var pairIDs: () -> [(leader: WasabiObjectID, follower: WasabiObjectID)] = { [] }
    /// The window a container is shown in, if it has one. Set by the owner.
    var window: (WasabiObjectID) -> NSWindow? = { _ in nil }
    private var dragObservers: [NSObjectProtocol] = []
    /// The (leader, follower) pairs `attachForDrag` linked, undone when the drag ends.
    private var dragAttached: [(leader: NSWindow, follower: NSWindow)] = []

    init() {
        dragObservers = [
            NotificationCenter.default.addObserver(forName: .windowDragDidBegin, object: nil,
                                                   queue: .main) { [weak self] notification in
                self?.attachForDrag(dragged: notification.object as? NSWindow)
            },
            NotificationCenter.default.addObserver(forName: .windowDragDidEnd, object: nil,
                                                   queue: .main) { [weak self] _ in
                self?.detachAfterDrag()
            },
        ]
    }

    deinit {
        dragObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Every pair whose two windows exist and differ.
    private var pairs: [(leader: NSWindow, follower: NSWindow)] {
        pairIDs().compactMap { leaderID, followerID in
            guard let leader = window(leaderID), let follower = window(followerID),
                  leader !== follower else { return nil }
            return (leader, follower)
        }
    }

    /// The window a script keeps glued to `window`, over it or under it. Snapping skips it.
    func partner(of window: NSWindow) -> NSWindow? {
        for (leader, follower) in pairs {
            if leader === window { return follower }
            if follower === window { return leader }
        }
        return nil
    }

    /// Place `window` and carry the frame glued over it, so the pair never shows a stale frame.
    ///
    /// Itemskin's frame is a second window its script parks on the content window from a 10 ms
    /// timer, and the same script pulls the content back onto the frame from the frame's own
    /// `onResize`/`onMove`. A UI Size change rescales every window and tiles them in one pass, and the
    /// frame's `onResize` can be dispatched before its timer has carried it after the content. It then
    /// read the frame where the content *used* to be and dragged the content back there, off its
    /// slot and sometimes below the screen. Moved together, there is no stale frame to read.
    func move(_ window: NSWindow, to origin: NSPoint, trace: Bool) {
        let follower = pairs.first { $0.leader === window }?.follower
        // The offset is taken before the move and re-applied after it, rather than the move's delta
        // added on: a skin whose script follows the move synchronously has already carried its frame
        // by the time `setFrameOrigin` returns (Ebonite's `onMove` does), and a second delta threw it
        // off by the whole distance.
        let offset = follower.map {
            NSPoint(x: $0.frame.minX - window.frame.minX, y: $0.frame.minY - window.frame.minY)
        }
        window.setFrameOrigin(origin)
        guard let follower, let offset, follower.isVisible else { return }
        let carried = NSPoint(x: origin.x + offset.x, y: origin.y + offset.y)
        guard follower.frame.origin != carried else { return }
        if trace {
            NSLog("[place/tile] glued %@ -> %@", NSStringFromRect(follower.frame),
                  NSStringFromPoint(carried))
        }
        follower.setFrameOrigin(carried)
    }

    /// Put every script-glued frame back on top of the window it is drawn on.
    ///
    /// Idempotent and cheap — a skin has a handful of these — so it is run from every moment that can
    /// disturb the order rather than from a guessed subset: a window opening, a window taking the
    /// keyboard, and once after launch has settled. Keying it to `windowDidBecomeKey` alone was not
    /// enough and produced the exact half-and-half window the reporter saw: at launch the frame is
    /// created and shown first and the client is shown *after* it, so the client sat on top with only
    /// the frame's right edge and bottom-right grip showing past the client's own box — one half of
    /// the window in the skin's grey chrome, the other a bare black client.
    ///
    /// One runloop turn late on purpose: a `windowDidBecomeKey` notification is delivered *during* the
    /// ordering that raised the window, and an `order(.above:)` issued inside it is undone by the rest
    /// of that pass. `WindowManager.bringAllWindowsToFront` calls it after every `.wal` raise.
    func restack() {
        guard !pairIDs().isEmpty else {
            if Self.traces { NSLog("GLUE-TRACE restack: no pairs recorded") }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if Self.traces {
                for (leaderID, followerID) in pairIDs() {
                    let leaderWindow = window(leaderID)
                    let followerWindow = window(followerID)
                    let leaderName: String = leaderWindow?.accessibilityIdentifier() ?? "none"
                    let followerName: String = followerWindow?.accessibilityIdentifier() ?? "none"
                    NSLog("GLUE-TRACE pair leader=%@(%@) follower=%@(%@)",
                          leaderName, leaderWindow?.isVisible == true ? "visible" : "hidden",
                          followerName, followerWindow?.isVisible == true ? "visible" : "hidden")
                }
            }
            for (leader, follower) in pairs where leader.isVisible && follower.isVisible {
                // Whichever of the pair the user is in stays where it is and the other joins it, so
                // clicking the frame's title bar does not leave its client stranded behind something.
                if follower.isKeyWindow {
                    leader.order(.below, relativeTo: follower.windowNumber)
                } else {
                    follower.order(.above, relativeTo: leader.windowNumber)
                }
                if Self.traces {
                    let followerName: String = follower.accessibilityIdentifier() ?? "-"
                    let leaderName: String = leader.accessibilityIdentifier() ?? "-"
                    NSLog("GLUE-TRACE restacked %@ over %@ (levels %ld/%ld)",
                          followerName, leaderName, follower.level.rawValue, leader.level.rawValue)
                }
            }
        }
    }

    /// A drag carries every script-glued frame with its window in the window server's own move.
    ///
    /// Pure Inspired, Itemskin, K-jr and MoonLight draw each component window's frame in a second
    /// window that their script parks on the content from a 10 ms timer. A host drag moves the
    /// content — directly, as a docked peer, or as the player's child — but never the frame, which
    /// is not a snap target. So the frame trailed its content by one timer tick on every drag step.
    /// That was measured on Pure Inspired's docked playlist at 5-15 ms and ~16 pt per step, and on
    /// screen the border and interior pulled apart.
    /// As a child window the frame moves in the same window-server operation as its content.
    ///
    /// A follower that is the dragged window itself is left alone: it moves itself, and its own
    /// `onMove` pulls the content after it, as it always has. Linked only for the drag, because a
    /// script-driven move or resize of the content must not carry the frame. The script moves the
    /// frame onto the content itself, and a second carry would move the frame twice.
    private func attachForDrag(dragged: NSWindow?) {
        guard Self.carriesInDrag else { return }
        detachAfterDrag()
        for (leader, follower) in pairs
        where follower !== dragged && leader.isVisible && follower.isVisible && follower.parent == nil {
            leader.addChildWindow(follower, ordered: .above)
            dragAttached.append((leader, follower))
            if Self.traces {
                NSLog("GLUE-TRACE drag carries %@ with %@", follower.accessibilityIdentifier(),
                      leader.accessibilityIdentifier())
            }
        }
    }

    func detachAfterDrag() {
        for (leader, follower) in dragAttached where follower.parent === leader {
            leader.removeChildWindow(follower)
        }
        dragAttached.removeAll()
    }
}
