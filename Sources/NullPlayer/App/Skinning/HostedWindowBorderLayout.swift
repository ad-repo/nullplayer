import AppKit

/// **A hosted window is its interior plus the border, not its interior squeezed to fit one (W207).**
///
/// Every one of NullPlayer's own windows — Cava, the spectrum analyser, Flow, the waveform, the
/// analyser, PeppyMeter, ProjectM, the library — draws its own chrome, and when a foreign skin lends
/// one a frame that chrome becomes the skin's. The frames a `.wmz` lends are not thin: `anemone`'s
/// drawer is 83/72/90/73 around its list, 173x145 of border, and the spectrum family opens about
/// 600x150. Three answers to that were shipped and reported wrong, all of them variations on taking
/// the border *out* of the window (squash, refuse, scale the border down), and this is the fourth
/// and the one the reporter asked for on 2026-09-16:
///
/// > *"the interior window … should be its full borderless size. then the border is added after that
/// > and the final size is simply the full interior + border. whatever the border is. different
/// > skins will have different width borders. this is ok."*
///
/// So the window is **grown**. The interior each window wants is remembered, the donor's four
/// borders are asked for without reference to any window (`WMPHostedFrameProvider.donorInsets`, so
/// that a window too small to carry the border can still be told how much to grow by), and the frame
/// is set to `interior + border`, anchored at its top-left so the window stays where the user put
/// its title bar. Take the skin away and the interior is given back its own chrome and its own size.
///
/// **Why this is central rather than per-window.** It observes `NSWindow.didResizeNotification` for
/// every window it manages instead of asking eight controllers to call it, so a hosted window added
/// later inherits the rule by appearing in `WindowManager.hostedBorderWindows` alone. The same
/// reason `SkinnedSurfaceChrome.hostedGroundRect` lives in one place.
@MainActor
final class HostedWindowBorderLayout {
    /// The size a window's *contents* want, and the smallest they may be shrunk to — both in
    /// borderless points, which is the only frame of reference that survives a skin change.
    private struct Interior {
        var size: CGSize
        var minimum: CGSize
    }

    private var interiors: [ObjectIdentifier: Interior] = [:]
    /// The size this rule last asked each window for. **A window does not always land on it** — the
    /// docking pass re-lays the stack out afterwards and a window comes to rest a point or two off,
    /// in a `didResize` that is no longer inside `isApplying`. Read as the user's, that one point
    /// re-derived the interior against the donor's border and the analyser came back from a skin
    /// switch 387x219 where its siblings came back 321x145 (measured 2026-09-16). So a resize is the
    /// user's only when it is not the settling of our own.
    private var lastApplied: [ObjectIdentifier: CGSize] = [:]
    /// Set while we are the ones moving a window, so our own `setFrame` is not read back as the user
    /// choosing a new interior.
    private var isApplying = false
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .hostedSurfaceStyleDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        // **A window that opens after the skin has to be caught too.** The frame notification fires
        // once, when the skin lands, and every hosted window the user opens afterwards misses it —
        // which is the whole defect this instrument found: the traces were empty because `apply()`
        // had run once, before any of these windows existed. Opening one makes it key and posts a
        // layout change, so both are listened to, and a second pass costs nothing because a window
        // already at its target is skipped.
        for name in [NSWindow.didBecomeKeyNotification, Notification.Name.windowLayoutDidChange] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, !self.isApplying else { return }
                        self.apply()
                    }
                })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.windowDidResize(note.object as? NSWindow) }
            })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - The rule

    /// Grow (or give back) every hosted window so that its interior keeps the size it asked for and
    /// the current border is added around it.
    func apply() {
        let border = WindowManager.shared.hostedSurfaceBorderInsets
        Self.traceRun(border)
        for entry in WindowManager.shared.hostedBorderWindows {
            guard let window = entry.window, window.frame.width > 0, window.frame.height > 0 else {
                continue
            }
            let interior = seededInterior(for: window, fallback: entry.fallback)
            let insets = border ?? entry.fallback
            // **Only the border is added. The donor's own floor is not.** Growing each window up
            // to the donor's declared minimum was tried here and reported broken the same day:
            // `Ice` declares `min=585x308`, so every hosted window — a 321x145 analyser included —
            // was forced to 585x308 at once. It is also the answer the ring path already rejected
            // in one line, for the reason that survived this test: *forcing every hosted window up
            // to the donor's minimum moves windows the user placed*. A ring below its floor keeps
            // its own scale-to-fit, which draws the border thinner than authored but in the
            // proportions its author chose, and the window is still exactly interior + border.
            let target = Self.outerSize(interior: interior.size, border: insets)
            let minimum = Self.outerSize(interior: interior.minimum, border: insets)

            window.minSize = NSSize(width: minimum.width, height: minimum.height)
            Self.trace(window, interior: interior.size, insets: insets, target: target,
                       donor: border != nil)
            // A point of slack: the window server rounds a frame to the backing grid, so demanding
            // an exact landing is demanding a fight it always wins.
            guard abs(target.width - window.frame.width) > 1.5
                    || abs(target.height - window.frame.height) > 1.5 else { continue }
            apply(size: target, to: window)
        }
    }

    private static func traceRun(_ border: SkinnedSurfaceChrome.Metrics?) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["WMP_BORDER_TRACE"] != nil else { return }
        NSLog("[wmp/border] run donorBorder=\(border.map { "\(Int($0.titleHeight))/\(Int($0.leftBorder))/\(Int($0.bottomBorder))/\(Int($0.rightBorder))" } ?? "none") "
            + "windows=\(WindowManager.shared.hostedBorderWindows.compactMap { $0.window }.count)")
        #endif
    }

    /// `WMP_BORDER_TRACE=1` — what this rule decided for each hosted window, every time it runs.
    /// Printed through `NSLog`, because a `print` into `kill_build_run.sh --log` is block-buffered
    /// and never arrives. The one instrument that separates "the border was never learned" from
    /// "the window was never grown" from "the frame was never rendered at the grown size".
    private static func trace(_ window: NSWindow, interior: CGSize,
                              insets: SkinnedSurfaceChrome.Metrics, target: CGSize, donor: Bool) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["WMP_BORDER_TRACE"] != nil else { return }
        NSLog("[wmp/border] \(window.accessibilityIdentifier()) donor=\(donor) "
            + "frame=\(Int(window.frame.width))x\(Int(window.frame.height)) "
            + "interior=\(Int(interior.width))x\(Int(interior.height)) "
            + "border=\(Int(insets.titleHeight))/\(Int(insets.leftBorder))/"
            + "\(Int(insets.bottomBorder))/\(Int(insets.rightBorder)) "
            + "target=\(Int(target.width))x\(Int(target.height))")
        #endif
    }

    /// The window a size `interior` of content needs once `border` is laid around it.
    /// **Rounded**, because a donor's borders are resolved from `jscript:` arithmetic and come out
    /// fractional: `Ice`'s are 34/40/70/40 only after rounding, and an unrounded target asked for a
    /// window of 435x215.4 that AppKit landed at 435x216. `apply()` then saw a 0.6pt error, resized,
    /// landed 216 again, and the two fought on every layout notification.
    static func outerSize(interior: CGSize, border: SkinnedSurfaceChrome.Metrics) -> CGSize {
        CGSize(width: (max(0, interior.width) + border.leftBorder + border.rightBorder).rounded(),
               height: (max(0, interior.height) + border.titleHeight + border.bottomBorder).rounded())
    }

    /// The content left inside `outer` once `border` has taken its share. Never negative: a window
    /// that has not been grown yet reports no interior rather than a backwards one.
    static func interiorSize(outer: CGSize, border: SkinnedSurfaceChrome.Metrics) -> CGSize {
        CGSize(width: max(0, outer.width - border.leftBorder - border.rightBorder),
               height: max(0, outer.height - border.titleHeight - border.bottomBorder))
    }

    /// Anchored at the top-left. A window grows down and to the right — the corner the user dragged
    /// the window to by is the one that stays put — and is nudged back onto its screen if that
    /// pushes it off.
    private func apply(size: CGSize, to window: NSWindow) {
        var frame = window.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = NSSize(width: size.width, height: size.height)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        }
        lastApplied[ObjectIdentifier(window)] = size
        isApplying = true
        window.setFrame(frame, display: true)
        isApplying = false
    }

    // MARK: - What the interior is

    /// The user just resized a window: whatever is inside the border now is the interior they chose,
    /// and it is what the next skin's border gets laid around.
    private func windowDidResize(_ window: NSWindow?) {
        guard !isApplying, let window,
              let entry = WindowManager.shared.hostedBorderWindows.first(where: { $0.window === window })
        else { return }
        let key = ObjectIdentifier(window)
        if let applied = lastApplied[key],
           abs(applied.width - window.frame.width) <= 2, abs(applied.height - window.frame.height) <= 2 {
            return
        }
        var interior = seededInterior(for: window, fallback: entry.fallback)
        interior.size = Self.interiorSize(outer: window.frame.size,
                                          border: Self.drawnBorder(of: window, fallback: entry.fallback))
        interiors[key] = interior
        lastApplied[key] = nil
        // **Only a reading taken against a border we are certain of is worth keeping.** While a
        // donor is up but its frame for *this* size has not been rendered yet, the window is wearing
        // its own chrome and the interior read off it is a guess — and a guess written here outlives
        // the session and comes back next launch as the size the user gets. That is what happened
        // across a run of skin switches: Cava came back wanting a 299x70 interior and the waveform
        // 355x111 where both should have been 297x111, so the stack opened at four different heights.
        // Either the skin lends nothing (the classic border is certain) or the frame is in hand.
        let certain = WindowManager.shared.hostedSurfaceBorderInsets == nil
            || WindowManager.shared.hostedSurfaceFrameArtwork(for: window.frame.size) != nil
        if certain { persist(interior.size, for: window) }
    }

    /// **The first sight of a window is read against its *own* chrome, not the skin's.** A window
    /// opens at a size its controller derived from `SkinElements` — interior plus classic border —
    /// so that is what the first reading has to subtract, or the very first skin would find an
    /// interior that had already had the donor's border taken out of it and would never grow.
    ///
    /// A window restored from a previous launch is the exception, because its saved frame already
    /// had a donor's border in it: the interior is persisted alongside, and a stored one wins.
    private func seededInterior(for window: NSWindow, fallback: SkinnedSurfaceChrome.Metrics) -> Interior {
        let key = ObjectIdentifier(window)
        if let known = interiors[key] { return known }
        let border = Self.drawnBorder(of: window, fallback: fallback)
        let minimum = Self.interiorSize(outer: window.minSize, border: border)
        let size = restored(for: window) ?? Self.interiorSize(outer: window.frame.size, border: border)
        let interior = Interior(size: size, minimum: minimum)
        interiors[key] = interior
        return interior
    }

    /// **The border the window is wearing right now, which is not the border the donor lends.**
    ///
    /// This distinction is the whole of the defect the `WMP_BORDER_TRACE` instrument found on
    /// 2026-09-16: reading a window's interior back as `frame − donorBorder` made every window a
    /// fixed point of its own rule. Cava opens 321x145 and `anemone` lends 173x145 of border, so the
    /// interior came back 148x**0**, the target came back 321x145 — the size it already was — and the
    /// window never grew, never reached a size the panel could be sliced onto, and wore the palette
    /// for ever. It reads as "the fix did nothing", and the trace is what separated it from the three
    /// other places it could have failed.
    ///
    /// A window is wearing the donor's border only where a frame was actually rendered for the size
    /// it is at — which is the same question `SkinnedSurfaceChrome.metrics(for:fallback:)` asks in
    /// the view's own `draw`. Everywhere else it is wearing its own chrome, and that is what has to
    /// come off to find the interior.
    private static func drawnBorder(of window: NSWindow,
                                    fallback: SkinnedSurfaceChrome.Metrics) -> SkinnedSurfaceChrome.Metrics {
        WindowManager.shared.hostedSurfaceFrameArtwork(for: window.frame.size)?.metrics ?? fallback
    }

    // MARK: - Across launches

    /// Keyed by the accessibility identifier every one of these windows already sets, so the stored
    /// interior follows the window rather than a controller instance.
    private static func defaultsKey(for window: NSWindow) -> String? {
        let id = window.accessibilityIdentifier()
        guard !id.isEmpty else { return nil }
        // Versioned: the unsuffixed key holds interiors written before the rule above existed, and
        // those are the poisoned ones. A new name discards them without a migration.
        return "hostedInteriorSize2.\(id)"
    }

    private func persist(_ size: CGSize, for window: NSWindow) {
        guard let key = Self.defaultsKey(for: window) else { return }
        UserDefaults.standard.set(["w": size.width, "h": size.height], forKey: key)
    }

    private func restored(for window: NSWindow) -> CGSize? {
        guard let key = Self.defaultsKey(for: window),
              let stored = UserDefaults.standard.dictionary(forKey: key),
              let width = (stored["w"] as? Double).map({ CGFloat($0) }),
              let height = (stored["h"] as? Double).map({ CGFloat($0) }),
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
