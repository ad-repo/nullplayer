import AppKit

/// What `WinampModernGluedWindows` reads from the controller that owns the skin's windows.
protocol WinampModernGlueSource: AnyObject {
    /// The pairs the skin's scripts have glued (frame over client), leader first.
    var gluedOver: [(leader: WasabiObjectID, follower: WasabiObjectID)] { get }
    /// Declared window pairs a script keeps on one origin, which count only if the follower is a backdrop.
    var gluedBehindCandidates: [(leader: WasabiObjectID, follower: WasabiObjectID)] { get }
    /// The window a container is shown in, if it has one.
    func gluedWindow(_ id: WasabiObjectID) -> NSWindow?
    /// The newest alpha a container's window drew, if it has drawn.
    func gluedPicture(_ id: WasabiObjectID) -> CGImage?
    /// Whether a container *is* a host surface (a visualization, a library): its `component=` or its id
    /// names one. A frame's chrome window is not; its client may be.
    func isHostSurface(_ id: WasabiObjectID) -> Bool
}

extension Notification.Name {
    /// A `.wal` window drew a frame whose outline (its alpha shape) changed.
    static let winampModernOutlineDidChange = Notification.Name("winampModernOutlineDidChange")
}

/// The windows a `.wal` skin's script keeps glued together: a frame drawn in a second window parked on
/// its content window (Ebonite, Itemskin, Pure Inspired, K-jr, MoonLight). The runtime learns each
/// pair from the script (`windowsGluedOver`); this keeps the pairs moving, stacking and dragging as
/// one. Owned by `WinampModernMainWindowController`, which supplies the pairs (B162).
final class WinampModernGluedWindows {
    /// `WINAMP_MODERN_GLUE_TRACE=1` — the script-glued window pairs and every restack, live.
    static let traces = ProcessInfo.processInfo.environment["WINAMP_MODERN_GLUE_TRACE"] != nil

    /// Where the pairs, windows and pictures come from: the controller that owns the skin's windows.
    weak var source: WinampModernGlueSource?
    /// The verdict for each candidate pair, with the two window sizes it was judged at.
    private var verdicts: [String: (leader: CGSize, follower: CGSize, isBackdrop: Bool)] = [:]
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
            NotificationCenter.default.addObserver(forName: .winampModernOutlineDidChange, object: nil,
                                                   queue: .main) { [weak self] _ in
                self?.judgeCandidates()
            },
        ]
    }

    deinit {
        dragObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Every pair whose two windows exist and differ. A declared frame pair always goes over; a
    /// candidate counts only once `judgeCandidates` found its follower to be a backdrop. A lookup, no
    /// pixel work: it runs on every mouse press and restack.
    private var pairs: [(leader: NSWindow, follower: NSWindow, isBackdrop: Bool)] {
        guard let source else { return [] }
        let over = source.gluedOver.map { ($0.leader, $0.follower, false) }
        let behind = source.gluedBehindCandidates.filter { verdicts[Self.key($0.leader, $0.follower)]?.isBackdrop == true }
            .map { ($0.leader, $0.follower, true) }
        return (over + behind).compactMap { leaderID, followerID, isBackdrop in
            guard let leader = source.gluedWindow(leaderID), let follower = source.gluedWindow(followerID),
                  leader !== follower else { return nil }
            return (leader, follower, isBackdrop)
        }
    }

    private static func key(_ leader: WasabiObjectID, _ follower: WasabiObjectID) -> String {
        "\(leader)/\(follower)"
    }

    /// Decide, for each candidate pair, whether the follower is seen through the leader's holes and so
    /// belongs *under* it (`WinampModernGlueBackdrop`). Judged once, when both windows have drawn, and
    /// again only when either window's size changes (a layout switch); a frame, or a pair that has not
    /// drawn yet, stays above. Not on every outline change: Würlitzer's player reports a new outline
    /// about 7 times a second while music plays (its art animates) and the verdict never moves, so
    /// the pixel work stays off the per-frame path. Runs on `.winampModernOutlineDidChange` and at each
    /// restack; once decided, either is a size compare per pair.
    func judgeCandidates() {
        guard let source else { return }
        for (leaderID, followerID) in source.gluedBehindCandidates {
            guard let leader = source.gluedWindow(leaderID), let follower = source.gluedWindow(followerID),
                  leader !== follower, source.isHostSurface(followerID), !source.isHostSurface(leaderID),
                  // A closed window has nothing on screen to judge; the pair waits until both show.
                  leader.isVisible, follower.isVisible
            else { continue }
            let key = Self.key(leaderID, followerID)
            // Before fetching a picture, which is a render: a kept verdict costs two size compares.
            if let kept = verdicts[key], kept.leader == leader.frame.size, kept.follower == follower.frame.size {
                continue
            }
            guard let leaderImage = source.gluedPicture(leaderID),
                  let followerImage = source.gluedPicture(followerID) else { continue }
            let share = WinampModernGlueBackdrop.Plane(leaderImage, frame: leader.frame).flatMap { leaderPlane in
                WinampModernGlueBackdrop.Plane(followerImage, frame: follower.frame).flatMap {
                    WinampModernGlueBackdrop.transparentShare(leader: leaderPlane, follower: $0)
                }
            }
            let result = WinampModernGlueBackdrop.isBackdrop(transparentShare: share)
            // No overlap, nothing to judge: stay undecided so the pair is judged again once glued.
            verdicts[key] = share == nil ? nil : (leader.frame.size, follower.frame.size, result)
            if Self.traces {
                NSLog("GLUE-TRACE %@ %@ leader transparent over follower's art %@", key,
                      result ? "BACKDROP" : "frame", share.map { String(format: "%.3f", $0) } ?? "none")
            }
        }
        // A verdict usually lands after the follower opened (it has to draw first), and the window
        // that just opened is in front: put it under now, not at the next click.
        attachBackdrops()
    }

    /// Every visible backdrop is a child window of its leader, ordered below it (B390). The window
    /// server then keeps it under the leader whatever is raised, moves it in the same operation as a
    /// drag (no lagging square at the edges) and takes it into the Dock and back with the leader, so
    /// minimizing never leaves it on its own tile. A backdrop that closed is let go, so ordering the
    /// leader in cannot bring it back.
    private func attachBackdrops() {
        for (leader, follower, isBackdrop) in pairs where isBackdrop {
            let wanted = leader.isVisible && follower.isVisible
            if wanted, follower.parent !== leader {
                follower.parent?.removeChildWindow(follower)
                leader.addChildWindow(follower, ordered: .below)
                if Self.traces {
                    NSLog("GLUE-TRACE backdrop %@ child of %@", follower.accessibilityIdentifier(),
                          leader.accessibilityIdentifier())
                }
            } else if !wanted, follower.parent === leader {
                leader.removeChildWindow(follower)
            }
        }
    }

    /// Whether `window` is glued *under* another as its backdrop.
    func isBackdrop(_ window: NSWindow) -> Bool {
        pairs.contains { $0.follower === window && $0.isBackdrop }
    }

    /// The window a script keeps glued to `window`, over it or under it. Snapping skips it.
    func partner(of window: NSWindow) -> NSWindow? {
        for (leader, follower, _) in pairs {
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
        guard let source, !source.gluedOver.isEmpty || !source.gluedBehindCandidates.isEmpty else {
            if Self.traces { NSLog("GLUE-TRACE restack: no pairs recorded") }
            return
        }
        judgeCandidates()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if Self.traces {
                for (leaderID, followerID) in source.gluedOver {
                    let leaderWindow = source.gluedWindow(leaderID)
                    let followerWindow = source.gluedWindow(followerID)
                    let leaderName: String = leaderWindow?.accessibilityIdentifier() ?? "none"
                    let followerName: String = followerWindow?.accessibilityIdentifier() ?? "none"
                    NSLog("GLUE-TRACE pair leader=%@(%@) follower=%@(%@)",
                          leaderName, leaderWindow?.isVisible == true ? "visible" : "hidden",
                          followerName, followerWindow?.isVisible == true ? "visible" : "hidden")
                }
            }
            self.attachBackdrops()
            for (leader, follower, isBackdrop) in pairs where leader.isVisible && follower.isVisible {
                // A backdrop goes under its leader whoever has the keyboard. Of a frame pair, whichever
                // the user is in stays where it is and the other joins it, so clicking the frame's
                // title bar does not leave its client stranded behind something.
                if isBackdrop {
                    // Its child-window ordering is the window server's now; only a stray needs it.
                    if follower.parent !== leader { follower.order(.below, relativeTo: leader.windowNumber) }
                } else if follower.isKeyWindow {
                    leader.order(.below, relativeTo: follower.windowNumber)
                } else {
                    follower.order(.above, relativeTo: leader.windowNumber)
                }
                if Self.traces {
                    let followerName: String = follower.accessibilityIdentifier() ?? "-"
                    let leaderName: String = leader.accessibilityIdentifier() ?? "-"
                    NSLog("GLUE-TRACE restacked %@ %@ %@ (levels %ld/%ld, order index %ld/%ld)",
                          followerName, isBackdrop ? "under" : "over", leaderName, follower.level.rawValue,
                          leader.level.rawValue, follower.orderedIndex, leader.orderedIndex)
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
    /// frame onto the content itself, and a second carry would move the frame twice. A backdrop is
    /// already a child for good (`attachBackdrops`).
    private func attachForDrag(dragged: NSWindow?) {
        detachAfterDrag()
        attachBackdrops()
        for (leader, follower, isBackdrop) in pairs
        where !isBackdrop && follower !== dragged && leader.isVisible && follower.isVisible && follower.parent == nil {
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
