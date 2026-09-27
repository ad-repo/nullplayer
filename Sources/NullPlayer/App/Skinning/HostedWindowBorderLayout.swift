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
    /// Windows kept invisible until the skin can dress them (W250), by identity.
    private var holds: [ObjectIdentifier: Hold] = [:]
    /// The skin `interiors` were built under — `WindowManager.hostedInteriorScope`. **A window's
    /// interior belongs to the skin that produced it**: one carried across a skin switch is saved
    /// under the next skin's key the first time the user touches the window, and from then on every
    /// skin inherits every other's sizes. `nil` until the first settled pass.
    private var scope: String?

    init() {
        // **Guarded like its siblings below, and for the same reason (W238).** This one is posted
        // with `object: nil` by *every* render completion, so it re-runs the rule over every hosted
        // window each time any frame lands — and a run that is itself a resize must not re-enter
        // while our own `setFrame` is still settling.
        observers.append(NotificationCenter.default.addObserver(
            forName: .hostedSurfaceStyleDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isApplying else { return }
                    self.apply()
                }
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
        // **A drag is not a series of new windows (the 2026-09-23 drag fix).** Every pixel of a
        // drag used to reach the frame provider as a size nobody had asked for, and each started its
        // own full donor render. The provider is told when a hosted window starts and stops being
        // dragged instead. NullPlayer's own windows resize by hand (`ResizableWindow`), which never
        // enters AppKit's live resize, so both families of notification are listened to.
        for name in [NSWindow.willStartLiveResizeNotification, Notification.Name.windowEdgeResizeDidBegin] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated { self?.liveResize(note.object as? NSWindow, began: true) }
                })
        }
        for name in [NSWindow.didEndLiveResizeNotification, Notification.Name.windowEdgeResizeDidEnd] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated { self?.liveResize(note.object as? NSWindow, began: false) }
                })
        }
        // **A window closed while held has to be given its opacity back (W250)**, or the next open
        // finds it at alpha 0 with nothing left to reveal it.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = note.object as? NSWindow else { return }
                    self.reveal(ObjectIdentifier(window), reason: "closed")
                    self.liveResize(window, began: false)
                    // A closed window's interior dies with it: a `.wmz` one is persisted, and every
                    // other mode resets to its default on show. Left here, a later window at the
                    // same address would inherit it.
                    self.forget(window)
                }
            })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        // This rule is torn down when the mode changes, which is exactly when a held window would
        // be left invisible with nothing listening for its frame.
        for held in holds.values {
            held.timer.invalidate()
            held.window?.alphaValue = held.alpha
        }
    }

    // MARK: - The rule

    /// Grow (or give back) every hosted window so that its interior keeps the size it asked for and
    /// the current border is added around it.
    func apply() {
        syncScope()
        let border = WindowManager.shared.hostedSurfaceBorderInsets
        Self.traceRun(border)
        for entry in WindowManager.shared.hostedBorderWindows {
            guard let window = entry.window, window.frame.width > 0, window.frame.height > 0 else {
                continue
            }
            let interior = seededInterior(for: window, fallback: entry.fallback)
            let insets = Self.borderInPlay(fallback: entry.fallback)
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
        prewarmRecentlyOpened(border)
        // **After the loop, not before it (W250).** A held window may have just been grown, and the
        // question a hold asks is about the size it is at now.
        releaseSettledHolds()
    }

    // MARK: - A drag

    /// Windows being dragged right now, so a begin and its end are counted once each however many of
    /// the two notification families report them.
    private var resizing: Set<ObjectIdentifier> = []

    private func liveResize(_ window: NSWindow?, began: Bool) {
        guard let window,
              WindowManager.shared.hostedBorderWindows.contains(where: { $0.window === window })
        else { return }
        let key = ObjectIdentifier(window)
        if began {
            guard resizing.insert(key).inserted else { return }
        } else {
            guard resizing.remove(key) != nil else { return }
        }
        WindowManager.shared.hostedSurfaceLiveResize(began: began, size: window.frame.size)
    }

    /// **The size every open hosted window would be under `border`** — `apply()`'s target, asked for
    /// a border that is not in play yet. A `.wmz` skin switch renders these before it commits, and
    /// the commit's `apply()` then resizes each window to exactly the size that was rendered.
    func openTargets(border: SkinnedSurfaceChrome.Metrics) -> [CGSize] {
        // **The incoming skin's interiors, not the outgoing one's.** Only a staged switch asks, and
        // the commit's `apply()` reseeds every window from the same two places (`syncScope`), so the
        // sizes rendered here are the sizes the windows land at.
        WindowManager.shared.hostedBorderWindows.compactMap { entry in
            guard let window = entry.window, window.isVisible,
                  window.frame.width > 0, window.frame.height > 0 else { return nil }
            let interior = Self.defaultsKey(forIdentifier: window.accessibilityIdentifier())
                .flatMap(Self.storedInterior(forKey:))
                ?? Self.defaultInterior(for: window, fallback: entry.fallback)
                ?? seededInterior(for: window, fallback: entry.fallback).size
            return Self.outerSize(interior: interior, border: border)
        }
    }

    // MARK: - Before the window opens

    /// **Ask the skin for the frames the windows that are not open will want (W248).**
    ///
    /// A ring is a full scene build per size — 1.28 s for the library's on `ALXVortex` — so a window
    /// opened cold wears palette chrome for the length of it. The size is knowable long before the
    /// click: it is this rule's own `interior + border`, and the interior is persisted across
    /// launches by `persist(_:for:)`. So the sizes are computed here, at the first pass after a skin
    /// resolves its border, and handed to the provider to build while nothing is waiting on them.
    ///
    /// **Only the windows this user actually opens**, most-recent-first and capped: the persisted
    /// interiors cover eleven windows across two controller families, and rendering all of them
    /// would put minutes of speculative work behind every skin load to serve a list of windows most
    /// of which will not be opened. The recency list is written by `prepare(_:)`, which is the one
    /// place every hosted window's open passes through — so a fresh install prewarms nothing, and
    /// learns what to prewarm from the first session that opens anything.
    private func prewarmRecentlyOpened(_ border: SkinnedSurfaceChrome.Metrics?) {
        // Once-per-skin is the provider's own guard (`prewarmedGeneration`), not a comparison of
        // borders here: two skins can lend the same four numbers with an emptied cache between them.
        guard let border else { return }
        // **A window that is already open is asked for the size it is at, not the size defaults
        // remembers it by.** The stored interior is a reading from some earlier session and it can
        // be points away from the live one. Measured on `ALXVortex` 2026-09-20 — the prewarm queued
        // 550x887 from defaults while the library stood at 550x890, so the one window that needed a
        // frame was the one window that did not get one. After a skin switch the loop above has
        // reseeded every open window from the *new* skin's stored interior (or its default) and
        // grown it to this border, so their frames are the new skin's targets.
        //
        // Include both the computed target and the actual frame; the provider deduplicates them.
        // W249 inferred a docking refusal from a trace printed BEFORE apply(size:to:). Live
        // retesting reached 893 and preserved the 825-point interior in both directions. A
        // pre-apply frame/target difference does not establish a competing size owner; see
        // LOW_QUALITY_TASKS.md for the measurements and the evidence needed to revive that claim.
        var sizes: [CGSize] = []
        for entry in WindowManager.shared.hostedBorderWindows {
            guard let window = entry.window, window.frame.width > 0, window.frame.height > 0
            else { continue }
            sizes.append(Self.outerSize(interior: seededInterior(for: window, fallback: entry.fallback).size,
                                        border: border))
            sizes.append(window.frame.size)
        }
        // Then the windows that are not open, which is all defaults can speak for.
        sizes += Self.recentlyOpened().compactMap { identifier in
            Self.defaultsKey(forIdentifier: identifier).flatMap(Self.storedInterior(forKey:))
                .map { Self.outerSize(interior: $0, border: border) }
        }
        guard !sizes.isEmpty else { return }
        WindowManager.shared.prewarmHostedSurfaceFrames(sizes)
    }

    /// How many windows deep the prewarm goes. **Every hosted window there is (W250).** Four was
    /// what a user has open at once, and it made the prewarm a guarantee for four windows and
    /// nothing for the other four — `ALXVortex` 2026-09-21 queued `PeppyMeter, Cava, Waveform,
    /// PlexBrowser` and the spectrum analyser opened onto palette chrome. The open itself is what
    /// guarantees the frame now (`hold(_:until:)`), so this list is a latency measure rather than a
    /// correctness one, and it costs a serial background render per entry for sizes this user's own
    /// defaults say they do open.
    private static let prewarmDepth = 8

    private static let recencyKey = "hostedWindowRecency"

    /// The hosted windows this user opened most recently, most recent first.
    private static func recentlyOpened() -> [String] {
        (UserDefaults.standard.array(forKey: recencyKey) as? [String] ?? [])
            .prefix(prewarmDepth)
            .map { $0 }
    }

    /// Note that a window was opened, so the next skin load knows to build its frame first. Written
    /// on the pre-show pass rather than on a resize: it is the *opening* that this orders.
    private static func rememberOpened(_ window: NSWindow) {
        let identifier = window.accessibilityIdentifier()
        guard !identifier.isEmpty else { return }
        var recency = (UserDefaults.standard.array(forKey: recencyKey) as? [String] ?? [])
        recency.removeAll { $0 == identifier }
        recency.insert(identifier, at: 0)
        UserDefaults.standard.set(Array(recency.prefix(prewarmDepth * 2)), forKey: recencyKey)
    }

    private static func storedInterior(forKey key: String) -> CGSize? {
        guard let stored = UserDefaults.standard.dictionary(forKey: key),
              let width = (stored["w"] as? Double).map({ CGFloat($0) }),
              let height = (stored["h"] as? Double).map({ CGFloat($0) }),
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// **The same rule, for one window, before it is ordered front (W248).**
    ///
    /// `apply()` can only run once a window is visible — it is driven by `didBecomeKey` and by the
    /// layout notification a show posts on its way out, and the observers are registered with
    /// `queue: .main`, so the growth lands a runloop turn *after* the window the user asked for is
    /// already on screen. That turn is one of the two visible jumps reported on 2026-09-20 as
    /// "the window loads with stretched graphics, might resize and then snaps in": the window
    /// appears wearing its own chrome at its own size and is then resized under the user's eyes.
    ///
    /// Nothing about the target needs the window to be visible. The donor's border is resolved once
    /// per skin without reference to any window (W207) and the interior is either persisted or the
    /// size the controller just positioned the window at, so the whole computation can be done while
    /// the window is still off screen. This is that computation — `apply()`'s loop body for one
    /// window — and after it `apply()` finds the window already at its target and skips it.
    ///
    /// Called by each hosted window's show path **after it has positioned the window and before
    /// `showWindow(nil)`**. Guarded on the window not yet being visible, so a second call on a
    /// window already up is a no-op rather than a resize the user did not ask for.
    func prepare(_ window: NSWindow) {
        syncScope()
        guard !window.isVisible,
              window.frame.width > 0, window.frame.height > 0,
              let entry = WindowManager.shared.hostedBorderWindows.first(where: { $0.window === window })
        else { return }
        let interior = seededInterior(for: window, fallback: entry.fallback)
        let insets = Self.borderInPlay(fallback: entry.fallback)
        let target = Self.outerSize(interior: interior.size, border: insets)
        let minimum = Self.outerSize(interior: interior.minimum, border: insets)
        Self.trace(window, interior: interior.size, insets: insets, target: target,
                   donor: WindowManager.shared.hostedSurfaceBorderInsets != nil)
        Self.rememberOpened(window)
        // **The presize switch still withholds everything it withheld before (W250).** The hold
        // below is a separate question with a separate switch, so the two can be measured apart.
        if Self.presizes {
            window.minSize = NSSize(width: minimum.width, height: minimum.height)
            if abs(target.width - window.frame.width) > 1.5
                || abs(target.height - window.frame.height) > 1.5 {
                apply(size: target, to: window)
            }
        }
        // **Last, and independent of whether anything was resized (W250).** A window already at its
        // target still opens into a skin that may have no frame for it, and that is the case the
        // presize half of W248 cannot touch.
        hold(window, until: Self.presizes ? target : window.frame.size)
    }

    // MARK: - Holding the open until the skin can dress it

    /// **A hosted window is not shown until the skin can dress it (W250).**
    ///
    /// W248 stopped a cold window wearing a *stretched* ring, and what it left in its place is flat
    /// palette chrome: `WMPHostedFrameProvider.artwork(for:)` refuses a stand-in past 15% of the
    /// last-rendered size, so a window opening at a size nothing has been rendered for draws
    /// NullPlayer's own chrome until its build lands. Measured on `ALXVortex` 2026-09-21 — the
    /// spectrum analyser opened 368x145, drew palette chrome twenty times over
    /// `standin=out-of-scale from=550x893`, and was re-dressed 263 ms later.
    ///
    /// The prewarm was W248's cover for that and it cannot be the guarantee: it speculates from
    /// persisted interiors, so it reaches no window this user has never opened, and no window
    /// whose size it could not know. **The guarantee has to live on the open itself**, where the
    /// size is known exactly and the window is still off screen — which is this, and which is why
    /// it is the last thing `prepare(_:)` does.
    ///
    /// The window is made transparent rather than kept out of the window list: it is about to be
    /// ordered front by its own show path, which this rule does not own and must not fight. It is
    /// revealed the moment the skin has a final answer for the size it is at — a frame, a refusal,
    /// or no frame to lend — and a `budget` timer reveals it regardless, so no failure anywhere
    /// below can strand a window the user asked for.
    private func hold(_ window: NSWindow, until target: CGSize) {
        guard Self.holdsOpens, holds[ObjectIdentifier(window)] == nil,
              !Self.isDressed(at: target)
        else { return }
        // **Only a settled border makes `target` a real size (W250).** A window opening while the
        // skin is still resolving is sized against its *own* chrome, so demanding that size buys a
        // full donor render of a frame nothing will ever wear — two of them at launch, measured
        // 2026-09-21 — and worse, the frame it produces can settle the hold and reveal the window
        // at a size `apply()` is about to grow. The hold still runs; it just waits for the border
        // before it names a size.
        if WindowManager.shared.hostedSurfaceBordersAreSettled {
            WindowManager.shared.demandHostedSurfaceFrame(for: target)
        }
        let key = ObjectIdentifier(window)
        // A window held once and revealed at alpha 0 would never be seen again, so a zero reading —
        // our own previous hold, interrupted — restores to opaque rather than to what it found.
        let restore = window.alphaValue > 0 ? window.alphaValue : 1
        window.alphaValue = 0
        let timer = Timer.scheduledTimer(withTimeInterval: Self.holdBudget, repeats: false) { _ in
            MainActor.assumeIsolated { self.reveal(key, reason: "budget") }
        }
        holds[key] = Hold(window: window, alpha: restore, timer: timer, since: Date())
        Self.traceHold(window, size: target, budget: Self.holdBudget)
    }

    /// Reveal every held window the skin can now dress, asked at the size each one is **at** rather
    /// than the size it was held for: `apply()` may have grown it since, and a window revealed
    /// against a stale size is revealed wearing chrome, which is the defect.
    private func releaseSettledHolds() {
        for (key, held) in holds {
            guard let window = held.window else {
                reveal(key, reason: "gone")
                continue
            }
            if Self.isDressed(at: window.frame.size) {
                reveal(key, reason: "frame")
            } else if WindowManager.shared.hostedSurfaceBordersAreSettled {
                // **The size a window is held at can change under it.** A window held at launch is
                // held against its own chrome, and the loop above has just grown it to the donor's
                // border — so the size it now needs is one nothing has been asked for. Demanding it
                // here makes the hold self-terminating rather than dependent on the prewarm having
                // guessed the same number.
                WindowManager.shared.demandHostedSurfaceFrame(for: window.frame.size)
            }
        }
    }

    private func reveal(_ key: ObjectIdentifier, reason: String) {
        guard let held = holds.removeValue(forKey: key) else { return }
        held.timer.invalidate()
        held.window?.alphaValue = held.alpha
        Self.traceReveal(held.window, reason: reason, waited: Date().timeIntervalSince(held.since))
    }

    /// Whether a window of `size` would be drawn wearing the skin rather than palette chrome: the
    /// border has resolved **and** the skin has a final answer for that size. Both halves, because
    /// a skin still resolving answers "no frame" for every size and that is not an answer.
    private static func isDressed(at size: CGSize) -> Bool {
        WindowManager.shared.hostedSurfaceBordersAreSettled
            && WindowManager.shared.hostedSurfaceHasSettledFrameAnswer(for: size)
    }

    private struct Hold {
        weak var window: NSWindow?
        let alpha: CGFloat
        let timer: Timer
        let since: Date
    }

    /// `WMP_HOSTED_HOLD=0` — show a hosted window the instant its controller does, restoring the
    /// pre-W250 open where it appears wearing palette chrome and is re-dressed when its frame
    /// lands. The A/B switch for W250.
    private static let holdsOpens = ProcessInfo.processInfo.environment["WMP_HOSTED_HOLD"] != "0"

    /// `WMP_HOSTED_HOLD_MS` — how long a held window may stay invisible before it is shown
    /// regardless. It is a backstop, not a budget the common case spends: the prewarm and the
    /// demand this rule issues mean a settled skin answers immediately. Past it the user gets the
    /// pre-W250 behaviour rather than a window that never appears, which is the only failure mode
    /// worse than the one being fixed.
    ///
    /// **Four seconds, from the worst case measured rather than from taste.** A restored window at
    /// launch waits for three things in series: the skin to render (≈0.4 s), the donor's borders to
    /// resolve, and its own ring — and on `ALXVortex` 2026-09-21 the library came out at 2.09 s of
    /// which 1.4 s was the ring alone. A budget set near that number turns a slower donor into the
    /// flash this rule exists to remove, so it is set clear of it.
    private static let holdBudget: TimeInterval = {
        let stated = ProcessInfo.processInfo.environment["WMP_HOSTED_HOLD_MS"].flatMap(Double.init)
        return max(0, (stated ?? 4000) / 1000)
    }()

    /// `WMP_HOSTED_PRESIZE=0` — withhold the pre-show growth and restore the pre-W248 open, where a
    /// hosted window appears at its own size and is grown a turn later. The A/B switch for the half
    /// of W248 that is about *when* a window is sized, as `WMP_FRAME_STANDIN` is for the half about
    /// what is drawn while its frame is still being rendered.
    private static let presizes = ProcessInfo.processInfo.environment["WMP_HOSTED_PRESIZE"] != "0"

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

    /// `WMP_BORDER_TRACE=1` — the two ends of a W250 hold. `hold` is a window kept off screen
    /// because the skin has no answer for its size yet; `reveal` closes it and carries the wait in
    /// milliseconds and **why** it ended — `frame` is the skin answering, `budget` is it running
    /// out of time, and a run full of `budget` is the fix failing rather than working.
    private static func traceHold(_ window: NSWindow, size: CGSize, budget: TimeInterval) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["WMP_BORDER_TRACE"] != nil else { return }
        NSLog("[wmp/border] hold \(window.accessibilityIdentifier()) "
            + "size=\(Int(size.width))x\(Int(size.height)) budgetMs=\(Int(budget * 1000))")
        #endif
    }

    private static func traceReveal(_ window: NSWindow?, reason: String, waited: TimeInterval) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["WMP_BORDER_TRACE"] != nil else { return }
        NSLog("[wmp/border] reveal \(window?.accessibilityIdentifier() ?? "gone") "
            + "reason=\(reason) waitedMs=\(Int((waited * 1000).rounded()))")
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

    // MARK: - Which skin the interiors belong to

    /// **A skin switch moves every hosted window to the new skin's size**, visible or not: its
    /// stored interior under that skin, else its default. `apply()`'s loop then resizes each one to
    /// interior + new border in the same pass that re-borders it, through `apply(size:to:)`, so the
    /// resize is recorded in `lastApplied` and never saved as the user's.
    ///
    /// **Never reseeded from the frame.** `frame − drawnBorder` read against a just-emptied cache is
    /// the W207 fixed point; the store and the default depend on no frame, so none can form.
    ///
    /// Flipped only once the new skin's borders are settled: a `.wmz` switch is staged, and the old
    /// skin answers with its own border until every window flips — flipping earlier resizes once
    /// against the old border and again when the new one lands.
    private func syncScope() {
        guard WindowManager.shared.hostedSurfaceBordersAreSettled,
              let current = WindowManager.shared.hostedInteriorScope, current != scope else { return }
        let previous = scope
        scope = current
        // The first settled pass is a window's first sight, which `seededInterior` handles.
        guard previous != nil else { return }
        for entry in WindowManager.shared.hostedBorderWindows {
            guard let window = entry.window else { continue }
            let key = ObjectIdentifier(window)
            lastApplied[key] = nil
            guard let size = restored(for: window)
                    ?? Self.defaultInterior(for: window, fallback: entry.fallback) else {
                interiors[key] = nil
                continue
            }
            let border = SkinnedSurfaceChrome.paletteMetrics(entry.fallback)
            let minimum = interiors[key]?.minimum ?? Self.interiorSize(outer: window.minSize, border: border)
            interiors[key] = Interior(size: size, minimum: minimum)
        }
    }

    /// The interior of a window's default size: the size it opens at with nothing saved, less the
    /// chrome it draws for itself there.
    private static func defaultInterior(for window: NSWindow,
                                        fallback: SkinnedSurfaceChrome.Metrics) -> CGSize? {
        WindowManager.shared.nativeWindowDefaultSize(for: window).map {
            interiorSize(outer: $0, border: SkinnedSurfaceChrome.paletteMetrics(fallback))
        }
    }

    /// Drop what is known about one window.
    private func forget(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        interiors[key] = nil
        lastApplied[key] = nil
    }

    /// Drop what is known about every window — a mode switch releases them all, and a new window
    /// at a reused address must not match a stale entry.
    func forgetAllWindows() {
        interiors.removeAll()
        lastApplied.removeAll()
        scope = nil
    }

    // MARK: - What the interior is

    /// The user just resized a window: whatever is inside the border now is the interior they chose,
    /// and it is what the next skin's border gets laid around.
    private func windowDidResize(_ window: NSWindow?) {
        // **A hidden window is never resized by the user.** A show path resets a window to its
        // default before it is ordered front, and a donor-grown window reset that way read back as
        // `default − donorBorder` — anemone's 166x145 of border left a 344x145 analyser a 178x0
        // interior, saved under the skin (measured 2026-09-27).
        guard !isApplying, let window, window.isVisible,
              let entry = WindowManager.shared.hostedBorderWindows.first(where: { $0.window === window })
        else { return }
        let key = ObjectIdentifier(window)
        if let applied = lastApplied[key],
           abs(applied.width - window.frame.width) <= 2, abs(applied.height - window.frame.height) <= 2 {
            return
        }
        // **Only a reading taken against a border we are certain of is worth keeping, and that
        // now gates the in-memory interior too — not just the stored one (W238).** A guess written
        // here outlives the session and comes back next launch as the size the user gets: Cava came
        // back wanting a 299x70 interior and the waveform 355x111 where both should have been
        // 297x111, so the stack opened at four different heights. But the same guess adopted only
        // for the session is no better while the session lasts — `apply()` reads it back on the
        // very next broadcast and grows the window to it. An uncertain resize is not read at all;
        // the interior the window already had stands, and the rule puts it back.
        guard WindowManager.shared.hostedSurfaceBordersAreSettled else { return }
        var interior = seededInterior(for: window, fallback: entry.fallback)
        // **Subtract the border `apply()` adds, not the one the artwork happens to show (W238).**
        // These were two different numbers and that asymmetry was the loop: `apply()` grows by the
        // donor's stated insets, while this read back `frame − drawnBorder`, and on a size nothing
        // had rendered yet `drawnBorder` was a *stretched* ring whose insets were scaled with it.
        // Measured on `Ice`: the library at 603x594 was grown to 603x732, read back against a ring
        // scaled 732/594 — its 34/70 borders stretched to 42/86 — and so re-targeted at 603x709,
        // paying a full donor render for each size on the way. Against the border this rule itself
        // adds the read is a round trip instead of a measurement, and a window resized by the user
        // lands on exactly the interior they dragged it to.
        interior.size = Self.interiorSize(outer: window.frame.size,
                                          border: Self.borderInPlay(fallback: entry.fallback))
        interiors[key] = interior
        lastApplied[key] = nil
        persist(interior.size, for: window)
    }

    /// The border `apply()` lays around an interior: the donor's four, stated without reference to
    /// any window (W207), or the window's own chrome where no skin lends any. **One helper because
    /// the half of this rule that adds the border and the half that subtracts it have to agree** —
    /// when they did not, each pass left a residue and the two chased each other across renders.
    private static func borderInPlay(fallback: SkinnedSurfaceChrome.Metrics) -> SkinnedSurfaceChrome.Metrics {
        WindowManager.shared.hostedSurfaceBorderInsets ?? SkinnedSurfaceChrome.paletteMetrics(fallback)
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
        // **Under a donor, a window with nothing saved for this skin opens at its default** — not
        // at `frame − drawnBorder`, which is the W207 fixed point whenever the skin has a frame
        // rendered at the size the window happens to be. The frame is read only where the window
        // wears its own chrome, and there it is the size the show path just set.
        let size = restored(for: window)
            ?? (WindowManager.shared.hostedSurfaceBorderInsets != nil
                ? Self.defaultInterior(for: window, fallback: fallback) : nil)
            ?? Self.interiorSize(outer: window.frame.size, border: border)
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
    /// **Asked of the rendered frame alone (W238).** The drawing seam schedules a build for a size
    /// it has not got and stands a stretched ring in for it meanwhile, and neither belongs in a
    /// measurement: seeding a window's interior would have scheduled a donor render as a side
    /// effect of looking at it, and a stretched ring's insets are that ring's scaled, which is not
    /// the border this window is wearing. `hostedSurfaceRenderedFrameArtwork(for:)` answers the
    /// frame or nothing, which is exactly the question this doc comment already claimed to ask.
    private static func drawnBorder(of window: NSWindow,
                                    fallback: SkinnedSurfaceChrome.Metrics) -> SkinnedSurfaceChrome.Metrics {
        WindowManager.shared.hostedSurfaceRenderedFrameArtwork(for: window.frame.size)?.metrics
            ?? SkinnedSurfaceChrome.paletteMetrics(fallback)
    }

    // MARK: - Across launches

    /// **Keyed by the `.wmz` skin that lends the border, then by window** — the accessibility
    /// identifier every one of these windows already sets, so the stored interior follows the window
    /// rather than a controller instance. The one place the key is built: the prewarm asks for the
    /// same keys the rule writes.
    ///
    /// **Read and written only while a `.wmz` skin lends a border** (`persist`, `restored`).
    /// Classic, Original and `.wal` measure against their own chrome and reset to their default on
    /// show; a stored interior read there is another skin's size — the window census measured a
    /// classic analyser at 762x167 from one — and one written there is the same leak the other way.
    ///
    /// Versioned: `…2` was one key for every skin and every mode, and its values are exactly that
    /// leak. A new name discards them without a migration, as `…2` did the unsuffixed key.
    private static func defaultsKey(forIdentifier id: String) -> String? {
        guard !id.isEmpty, let skin = WindowManager.shared.hostedInteriorSkinKey else { return nil }
        return "hostedInteriorSize3.\(skin).\(id)"
    }

    private func persist(_ size: CGSize, for window: NSWindow) {
        guard WindowManager.shared.hostedSurfaceBorderInsets != nil,
              !WindowManager.shared.hostedSurfaceIsStagingSwitch,
              let key = Self.defaultsKey(forIdentifier: window.accessibilityIdentifier()) else { return }
        UserDefaults.standard.set(["w": size.width, "h": size.height], forKey: key)
    }

    private func restored(for window: NSWindow) -> CGSize? {
        guard WindowManager.shared.hostedSurfaceBorderInsets != nil else { return nil }
        return Self.defaultsKey(forIdentifier: window.accessibilityIdentifier()).flatMap(Self.storedInterior(forKey:))
    }
}
