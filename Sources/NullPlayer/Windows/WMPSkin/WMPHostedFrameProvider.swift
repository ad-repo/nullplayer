import AppKit

/// Keeps the active `.wmz` skin's borrowed window frame (`WMPHostedFrameTemplate`) rendered at the
/// sizes NullPlayer's own windows are currently open at.
///
/// A ring is laid out by the skin's own alignment rules, so a frame rendered for one size cannot be
/// stretched to another without putting the corners in the wrong place: every distinct window size
/// is its own render. Two things follow, and they are the whole design of this type:
///
/// - **Nothing is built on the main thread.** `WMPSceneBuilder` resolves expressions and decodes
///   artwork, which the isolation rule in `wmp-skin-guide` keeps off the UI executor. A view asking
///   for a frame it does not have yet is answered *now* with the nearest thing available and told to
///   ask again when the real one lands (`.hostedSurfaceStyleDidChange`).
/// - **The nearest thing available is the last frame that was rendered, scaled.** Returning nil
///   during a live resize would drop every window back to palette chrome for the duration of the
///   drag and flash it back — so a stale ring, stretched, stands in for the one still being built.
///
/// The provider owns a **private** `WMPImageStore` rather than sharing the controller's. The
/// controller's store is read by the render loop that is painting the skin itself; a second
/// consumer on a background executor has no business in it.
@MainActor
final class WMPHostedFrameProvider {
    private struct Key: Hashable {
        let width: Int
        let height: Int
        init(_ size: CGSize) {
            width = Int(size.width.rounded())
            height = Int(size.height.rounded())
        }
        var size: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }
    }

    /// How many window sizes are kept. A user with every hosted window open has fewer than this;
    /// the cap exists so a live resize cannot grow the cache without bound.
    private static let cacheLimit = 12

    private(set) var template: WMPHostedFrameTemplate?
    private var builder: WMPSceneBuilder?
    private var renderer: WMPRenderer?
    private var cache: [Key: SkinnedSurfaceFrameArtwork] = [:]
    private var order: [Key] = []
    private var inFlight: Set<Key> = []
    /// Window sizes this skin's donor has **refused** (W207). A refusal is a real answer and it has
    /// to be remembered: without it `artwork(for:)` re-scheduled the same build on every draw and
    /// went on handing back `mostRecent` stretched onto the window, so a window the panel cannot
    /// dress showed the *library's* frame squashed into it — reported 2026-09-16 as "you are
    /// squashing the window borders to the window size".
    private var refused: Set<Key> = []
    private var mostRecent: SkinnedSurfaceFrameArtwork?
    /// **The skin that is on its way out, kept until the one coming in can replace it (W248).**
    ///
    /// A ring is a scene build per size — 1.27 s for the library's on `ALXVortex` — and a skin
    /// change used to empty the cache the instant the new skin arrived, so every hosted window on
    /// screen was stripped to flat palette chrome and waited out that render. Measured on the
    /// reporter's own pair, AlienMorph → ALXVortex, 2026-09-20: 51 draws on chrome, then the frame.
    /// **The prewarm cannot reach this case** — the window is already open when the skin changes, so
    /// it asks for its frame the same instant the prewarm queues it and both wait on one build.
    ///
    /// What the window was wearing a moment ago is real, complete, correctly-proportioned artwork
    /// for exactly this size. It is the wrong *skin* for a beat, and that is a far smaller lie than
    /// a stretched ring (which is why the 15% rule below still refuses one) or than nothing at all.
    /// So it is carried across the change, per size, and each entry is dropped the moment the new
    /// skin answers for that size — with a frame, or with a refusal.
    private var outgoing: [Key: SkinnedSurfaceFrameArtwork] = [:]
    private var generation = 0
    /// The sizes this skin has already had speculative builds queued for, so `prewarm` does no work
    /// twice however often the caller's broadcast fires. **Per size rather than per skin (W250)**:
    /// once-per-skin closed the queue the first time it ran, so a hosted window whose size only
    /// became knowable later — the user opened it, or resized another one — never got a speculative
    /// build at all and paid for its render on screen. A size is recorded when it is *queued*, not
    /// when it succeeds, so a build that produces nothing is not retried on every broadcast.
    /// Cleared by `reset()`, which is where a skin ends.
    private var prewarmedSizes: Set<Key> = []

    /// **The border this skin adds around a hosted window's interior, independent of any window
    /// (W207).** Resolved once per skin, because the growth that gives a window room for the border
    /// cannot wait for a frame rendered at a size the border does not yet fit in. Nil until it has
    /// been resolved, and for a skin that lends nothing.
    private(set) var donorInsets: NSEdgeInsets?

    /// Adopt a newly presented skin. Answers whether the skin has a frame to lend at all, which is
    /// what decides between artwork chrome and the palette-only chrome every `.wmz` gets today.
    @discardableResult
    func configure(skin: WMPLoadedSkin, playerViewID: String?) -> Bool {
        let derived = WMPHostedFrameTemplate.derive(from: skin, playerViewID: playerViewID)
        if derived == template, builder != nil { return derived != nil }
        // Held across `reset()`, and only when something is coming in to replace it: a skin that
        // lends no frame at all *should* put its windows back on palette chrome, and holding the
        // last skin's ring over it would be dressing them in a skin the user has left.
        let carried = derived != nil ? cache : [:]
        reset()
        outgoing = carried
        guard let derived else { return false }
        template = derived
        let store = WMPImageStore(provider: skin.archive)
        builder = WMPSceneBuilder(loadedSkin: skin, imageStore: store)
        renderer = WMPRenderer(imageStore: store)
        resolveDonorInsets()
        return true
    }

    /// Learn the donor's four borders. One scene build, off the UI executor like every other, and a
    /// `.hostedSurfaceStyleDidChange` when it lands so the windows can grow around their interiors.
    ///
    /// **It also primes the stand-in (W230).** Learning a ring's borders is composing one, and the
    /// composition used to be discarded — so the first hosted window to open found `mostRecent` nil,
    /// was answered no artwork, and drew NullPlayer's own palette chrome until a render at its own
    /// size landed. Measured on `Ice` 2026-09-19: 881 ms and four renders, because the border layout
    /// grows the window and every new size is another full donor rebuild. Adopting the ring this
    /// build already produced costs nothing and makes the *first* of those answerable immediately.
    ///
    /// It is deliberately **not** put in `cache`: it was composed at the donor's reference size, not
    /// at a window's, and a cache hit is a promise that the frame was built for the size asked for.
    /// `mostRecent` is the right slot — it is the one that means "the nearest thing available".
    private func resolveDonorInsets() {
        guard let template, let builder, let renderer else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let generation = self.generation
        let started = DispatchTime.now()
        Task { [weak self] in
            let border = try? await template.border(builder: builder, renderer: renderer,
                                                    backingScale: scale)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
            Self.trace("insets ok=\(border?.insets != nil) primed=\(border?.primed != nil) "
                + "ms=\(Int(elapsed.rounded()))")
            guard let self, let border, let insets = border.insets else { return }
            await MainActor.run {
                guard self.generation == generation else { return }
                self.donorInsets = insets
                if Self.primes, let primed = border.primed, self.mostRecent == nil {
                    self.mostRecent = primed
                }
                NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
            }
        }
    }

    /// Drop everything — a skin teardown, or a switch to the unskinned player.
    func reset() {
        generation &+= 1
        template = nil
        builder = nil
        renderer = nil
        cache.removeAll()
        order.removeAll()
        inFlight.removeAll()
        refused.removeAll()
        outgoing.removeAll()
        prewarmedSizes.removeAll()
        mostRecent = nil
        donorInsets = nil
    }

    /// The frame for a window of `size`, or nil when this skin lends none.
    ///
    /// Never blocks: a size that has not been rendered yet schedules its render and is answered with
    /// the last frame scaled to fit, or with nil when nothing has been rendered at all.
    func artwork(for size: CGSize) -> SkinnedSurfaceFrameArtwork? {
        guard template != nil, size.width > 0, size.height > 0 else { return nil }
        let key = Key(size)
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        // A size the donor has already turned down keeps the palette chrome it had before, and asks
        // no second time.
        if refused.contains(key) {
            Self.trace("miss \(key.width)x\(key.height) standin=refused")
            return nil
        }
        schedule(key)
        // **What this window was wearing a moment ago, while the new skin builds its own.** Exact
        // artwork for exactly this size, and the only wrong thing about it is whose skin it is.
        if let held = outgoingArtwork(for: key) {
            Self.trace("miss \(key.width)x\(key.height) standin=outgoing "
                + "from=\(Int(held.size.width))x\(Int(held.size.height))")
            return held.matches(size: key.size) ? held : held.scaled(to: key.size)
        }
        // **The stand-in is for a resize, not for a different window (W248).** A ring is laid out by
        // its author at every size and stretching yesterday's by a few points is invisible for the
        // frame or two before the real one lands. Stretching it onto a *different window* is not:
        // the tolerance below was written for panels, whose borders are a nine-patch that must keep
        // its thickness, but a ring carries the same defect in a form the slice cannot excuse —
        // a first open finds `mostRecent` holding the ring W230 primed at the **donor's reference
        // size**, and a donor nothing like the library's shape is stretched onto 603x594 without
        // limit. Reported 2026-09-20 as "the window loads with stretched graphics". So the 15% test
        // is every donor's, and past it the window wears flat palette chrome for the one render
        // rather than geometry that visibly deforms.
        guard let stale = mostRecent else {
            Self.trace("miss \(key.width)x\(key.height) standin=none")
            return nil
        }
        if !Self.standsInAtAnyScale {
            let widthRatio = stale.size.width > 0 ? size.width / stale.size.width : 0
            let heightRatio = stale.size.height > 0 ? size.height / stale.size.height : 0
            guard (0.85...1.15).contains(widthRatio), (0.85...1.15).contains(heightRatio) else {
                Self.trace("miss \(key.width)x\(key.height) standin=out-of-scale "
                    + "from=\(Int(stale.size.width))x\(Int(stale.size.height))")
                return nil
            }
        }
        Self.trace("miss \(key.width)x\(key.height) standin=scaled "
            + "from=\(Int(stale.size.width))x\(Int(stale.size.height))")
        return stale.scaled(to: key.size)
    }

    /// **Render the frames the hosted windows are going to ask for, before they ask (W248).**
    ///
    /// A ring is a full scene build per size and it is not cheap — `ALXVortex` measured **1.28 s**
    /// for the library's 550x890 on 2026-09-20 — so a window opened cold wears palette chrome for
    /// that long and then the skin arrives under the user's eyes. Nothing about the build needs the
    /// window: the size is `persisted interior + donorInsets`, both known once the skin has loaded.
    /// So the wait is moved off the user's click and onto the skin load, where there is nothing on
    /// screen to wait for it.
    ///
    /// **Serial, deliberately.** These are speculative builds for windows that may never open, and
    /// firing them concurrently would put every core on work nobody asked for while the skin the
    /// user *is* looking at is still settling. One at a time, each one answerable the moment it
    /// lands. A size already cached, refused or in flight is skipped — a real window that opens
    /// mid-queue is served by `artwork(for:)` as usual and its build is not duplicated.
    ///
    /// The caller decides *which* sizes, because the interiors and their recency belong to
    /// `HostedWindowBorderLayout`. This type only knows how to render one.
    func prewarm(_ sizes: [CGSize]) {
        guard Self.prewarms, let template, let builder, let renderer else { return }
        // **Per size, not per skin (W250).** The caller runs on a broadcast that fires many times
        // over a skin's life, and the sizes it can name grow as windows open and are resized. A
        // once-per-skin guard here meant the first broadcast fixed the queue for ever, so the
        // windows that came later were the ones that paid for their render on screen. `reset()`
        // clears this set, which is also the answer to two skins that lend the same four borders.
        var queue: [Key] = []
        for size in sizes where size.width > 0 && size.height > 0 {
            let key = Key(size)
            guard !prewarmedSizes.contains(key), cache[key] == nil, !refused.contains(key),
                  !inFlight.contains(key), !queue.contains(key) else { continue }
            queue.append(key)
            prewarmedSizes.insert(key)
            inFlight.insert(key)
        }
        guard !queue.isEmpty else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let generation = self.generation
        Self.trace("prewarm queued=" + queue.map { "\($0.width)x\($0.height)" }.joined(separator: ","))
        Task { [weak self] in
            for key in queue {
                let started = DispatchTime.now()
                let produced = try? await template.artwork(builder: builder, renderer: renderer,
                                                           size: key.size, backingScale: scale)
                guard let self else { return }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds
                    - started.uptimeNanoseconds) / 1e6
                let stop = await MainActor.run { () -> Bool in
                    // The skin changed under the queue: every remaining size belongs to a donor
                    // that is gone, and `reset()` has already emptied `inFlight`.
                    guard self.generation == generation else { return true }
                    self.inFlight.remove(key)
                    Self.trace("prewarmed \(key.width)x\(key.height) "
                        + "ok=\(produced != nil) ms=\(Int(elapsed.rounded()))")
                    // **A refusal here is not recorded.** `schedule` marks a size refused because a
                    // window is drawing at it and must stop asking every frame; a speculative build
                    // that fails has no window behind it, and a size this pass could not produce
                    // must still get its real answer — including the template-dropping verdicts —
                    // from the drawing path if a window ever does open at it.
                    guard let produced else { return false }
                    self.store(produced, for: key)
                    NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
                    return false
                }
                if stop { return }
            }
        }
    }

    /// The outgoing skin's frame for `key`, or the nearest one it has **within the same 15% the
    /// stand-in is held to**.
    ///
    /// The nearest is needed because a skin change is usually a *size* change as well: the two
    /// skins lend different borders, so `HostedWindowBorderLayout` grows or shrinks every hosted
    /// window by the difference, and the window asks for a size the outgoing skin was never asked
    /// for. The reporter's own pair moves the library 890 → 887 — three points, 0.3%, invisible
    /// stretched and the difference between a correct frame and bare chrome for 1.3 s. Past the
    /// tolerance nothing is offered, for the reason the tolerance exists at all.
    private func outgoingArtwork(for key: Key) -> SkinnedSurfaceFrameArtwork? {
        if let exact = outgoing[key] { return exact }
        return outgoing.values
            .filter { candidate in
                guard candidate.size.width > 0, candidate.size.height > 0 else { return false }
                let widthRatio = key.size.width / candidate.size.width
                let heightRatio = key.size.height / candidate.size.height
                return (0.85...1.15).contains(widthRatio) && (0.85...1.15).contains(heightRatio)
            }
            .min { lhs, rhs in
                abs(lhs.size.height - key.size.height) + abs(lhs.size.width - key.size.width)
                    < abs(rhs.size.height - key.size.height) + abs(rhs.size.width - key.size.width)
            }
    }

    /// **Whether this skin has a *final* answer for `size` right now (W250).**
    ///
    /// Three things count as final and they are not the same thing: a frame rendered for exactly
    /// this size, a refusal recorded for it, and a skin that lends no frame at all. Anything else
    /// means a window opening at this size would draw NullPlayer's own palette chrome while a
    /// render that has not finished — or has not started — catches up, and that flash is the whole
    /// of W250. `artwork(for:)` cannot answer this: it is the drawing seam, so asking it schedules
    /// work and it answers a stand-in rather than the truth.
    func hasSettledAnswer(for size: CGSize) -> Bool {
        guard template != nil, size.width > 0, size.height > 0 else { return true }
        let key = Key(size)
        return cache[key] != nil || refused.contains(key)
    }

    /// **Render `size` now, because a window is about to open at it (W250).**
    ///
    /// `prewarm` speculates from persisted interiors and is capped; this is the size a window is
    /// being opened at this instant, which is knowable exactly and is never speculative. Idempotent
    /// — `schedule` drops a size already in flight, so demanding one the prewarm queue is already
    /// building joins that build rather than duplicating it.
    func demand(_ size: CGSize) {
        guard template != nil, size.width > 0, size.height > 0 else { return }
        let key = Key(size)
        guard cache[key] == nil, !refused.contains(key) else { return }
        Self.trace("demand \(key.width)x\(key.height)")
        schedule(key)
    }

    /// **The frame actually rendered for `size` — no stand-in, and no build scheduled (W238).**
    ///
    /// `artwork(for:)` is the *drawing* path, and both of the things it does for a drawing view are
    /// wrong for a measuring one: it schedules a render as a side effect of being asked, and on a
    /// miss it answers the last ring stretched onto `size`, whose `metrics` are that ring's insets
    /// scaled. `HostedWindowBorderLayout` asking it what border a window is wearing is what closed
    /// the loop W238 is about — measuring a window grew it, growing it re-measured against a scaled
    /// ring, and the wrong answer paid for two more full donor renders at sizes nothing asked for.
    ///
    /// A measurement gets the cache or nothing. It does not `touch` either: reading a size must not
    /// reorder the eviction queue against the windows that are actually drawing.
    func renderedArtwork(for size: CGSize) -> SkinnedSurfaceFrameArtwork? {
        guard size.width > 0, size.height > 0 else { return nil }
        return cache[Key(size)]
    }

    /// Whether this skin lends a frame at all, which is **not** the same question as whether its
    /// borders have resolved yet. `donorInsets` is nil for both, and the two need telling apart: a
    /// skin that lends nothing is settled the moment it loads, while one that lends a ring is still
    /// resolving and a window's frame read back during that gap is read against the wrong border.
    var lendsFrame: Bool { template != nil }

    private func schedule(_ key: Key) {
        guard let template, let builder, let renderer, inFlight.insert(key).inserted else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let generation = self.generation
        let started = DispatchTime.now()
        Task { [weak self] in
            var produced: SkinnedSurfaceFrameArtwork?
            var unslicable = false
            var ringOpen = false
            do {
                produced = try await template.artwork(builder: builder, renderer: renderer,
                                                     size: key.size, backingScale: scale)
            } catch WMPHostedFrameRefusal.panelCannotBeSliced {
                unslicable = true
            } catch WMPHostedFrameRefusal.ringDoesNotClose {
                ringOpen = true
            } catch {
                produced = nil
            }
            guard let self else { return }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
            await MainActor.run {
                guard self.generation == generation else { return }
                self.inFlight.remove(key)
                Self.trace("built \(key.width)x\(key.height) "
                    + "ok=\(produced != nil) ms=\(Int(elapsed.rounded()))")
                guard let produced else {
                    // The older diagnostic assembler (`WMP_HOSTED_FRAME_WHOLE=0`) can refuse an
                    // open ring. This branch drops the donor and cached sizes as a fallback policy,
                    // not proof that every size fails. The default whole-donor path instead uses
                    // size-dependent gaps to attempt repair and does not throw ringDoesNotClose.
                    if ringOpen {
                        self.template = nil
                        self.donorInsets = nil
                        self.cache.removeAll()
                        self.order.removeAll()
                        self.mostRecent = nil
                        NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
                        return
                    }
                    // A refusal is an answer too: this skin will not dress this window, so the
                    // outgoing skin's frame stops standing in and the window takes the palette.
                    self.outgoing.removeValue(forKey: key)
                    if !unslicable { self.refused.insert(key) }
                    // **A panel that cannot be sliced lends nothing, and only the artwork pass
                    // knows** (W207): the four slice lines come from the *resolved* hole, so a
                    // donor whose list sits flush to an edge derives cleanly and then produces no
                    // frame — 26 of the corpus's 72 panels. Dropped rather than retried per window
                    // size, so the chrome settles on the palette it would have used anyway. Only
                    // for a panel, and only while nothing has ever been produced: a ring's nil is
                    // a degenerate window size, not a verdict on the skin.
                    // Only the donor's own verdict drops it. A window too short for the panel's
                    // borders is answered nil per size — dropping the template there would take
                    // the frame off the *library* because a 150pt analyser asked first.
                    if unslicable, self.template?.panelNodeID != nil, self.mostRecent == nil {
                        self.template = nil
                        NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
                    }
                    return
                }
                self.store(produced, for: key)
                NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
            }
        }
    }

    private func store(_ artwork: SkinnedSurfaceFrameArtwork, for key: Key) {
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["WMP_HOSTED_FRAME_DUMP"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let bitmap = NSBitmapImageRep(cgImage: artwork.image)
            try? bitmap.representation(using: .png, properties: [:])?.write(
                to: url.appendingPathComponent("\(key.width)x\(key.height)-frame.png"))
            Self.trace("dump \(key.width)x\(key.height) content=\(artwork.contentRect) over=\(artwork.paintsOverContent)")
        }
        #endif
        // The new skin has answered for this size, so the old one's frame has nothing left to cover.
        outgoing.removeValue(forKey: key)
        cache[key] = artwork
        mostRecent = artwork
        touch(key)
        while order.count > Self.cacheLimit, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    /// `WMP_FRAME_TRACE=1` — the first-open interval W230 is about, which nothing headless can
    /// see: a `HOSTED-FRAME` line is written after the artwork exists and the whole defect is the
    /// time before it does. `miss` is a window drawing without its frame; `built` closes it and
    /// carries the round trip in milliseconds. `NSLog`, not `print`, for the reason
    /// `WMP_BORDER_TRACE` records.
    /// `WMP_FRAME_PRIME=0` — withhold the primed stand-in and restore the pre-W230 first open,
    /// where a hosted window wears palette chrome until a render at its own size lands. An A/B
    /// switch in the same binary, which is the only honest way to ask whether a frame that looks
    /// wrong looks wrong *because* of the priming.
    private static let primes = ProcessInfo.processInfo.environment["WMP_FRAME_PRIME"] != "0"

    /// `WMP_HOSTED_PREWARM=0` — never build a frame for a window that is not open, and restore the
    /// pre-W248 first open, where the render starts when the user opens the window and they watch
    /// palette chrome for the length of it. The third of W248's A/B switches.
    private static let prewarms = ProcessInfo.processInfo.environment["WMP_HOSTED_PREWARM"] != "0"

    /// `WMP_FRAME_STANDIN=always` — restore the pre-W248 stand-in, where a ring was stretched onto
    /// any window size while its own render was in flight and only a panel was held to 15%. The A/B
    /// switch for the half of W248 that is about what is *drawn* during the gap, as its sibling
    /// `WMP_HOSTED_PRESIZE` is for the half about when the window is sized.
    private static let standsInAtAnyScale =
        ProcessInfo.processInfo.environment["WMP_FRAME_STANDIN"] == "always"

    private static let traces = ProcessInfo.processInfo.environment["WMP_FRAME_TRACE"] != nil

    private static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard traces else { return }
        NSLog("[wmp/frame] \(message())")
        #endif
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

extension SkinnedSurfaceFrameArtwork {
    /// The same picture stretched onto another window size, for the frame or two between a resize
    /// and the ring that was built for it. Its content hole moves proportionally, so the surface
    /// inside stays put rather than jumping twice.
    func scaled(to target: CGSize) -> SkinnedSurfaceFrameArtwork {
        guard size.width > 0, size.height > 0, !matches(size: target) else { return self }
        let scaleX = target.width / size.width
        let scaleY = target.height / size.height
        return SkinnedSurfaceFrameArtwork(
            image: image,
            size: target,
            contentRect: CGRect(x: contentRect.minX * scaleX, y: contentRect.minY * scaleY,
                                width: contentRect.width * scaleX, height: contentRect.height * scaleY),
            trailingCornerWidth: trailingCornerWidth.map { $0 * scaleX },
            wasScaledToFit: true,
            paintsOverContent: paintsOverContent
        )
    }
}
