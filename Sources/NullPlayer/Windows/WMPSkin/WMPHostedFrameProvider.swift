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
    private var generation = 0

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
        reset()
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
        mostRecent = nil
        donorInsets = nil
    }

    /// The frame for a window of `size`, or nil when this skin lends none.
    ///
    /// Never blocks: a size that has not been rendered yet schedules its render and is answered with
    /// the last frame scaled to fit, or with nil when nothing has been rendered at all.
    func artwork(for size: CGSize) -> SkinnedSurfaceFrameArtwork? {
        guard let template, size.width > 0, size.height > 0 else { return nil }
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
        // **The stand-in is for a resize, not for a different window.** A ring is laid out by its
        // author at every size and stretching yesterday's by a few points is invisible for the frame
        // or two before the real one lands. A *panel* is a nine-patch whose whole point is that its
        // borders keep their thickness, so stretching one from 550x464 onto a 350x170 window is the
        // squash the user sees — and it is the one thing the slice exists to avoid. Past 15% in
        // either axis a panel answers nil instead and the window wears the palette for that frame.
        guard let stale = mostRecent else {
            Self.trace("miss \(key.width)x\(key.height) standin=none")
            return nil
        }
        if template.panelNodeID != nil {
            let widthRatio = stale.size.width > 0 ? size.width / stale.size.width : 0
            let heightRatio = stale.size.height > 0 ? size.height / stale.size.height : 0
            guard (0.85...1.15).contains(widthRatio), (0.85...1.15).contains(heightRatio) else {
                Self.trace("miss \(key.width)x\(key.height) standin=panel-refused")
                return nil
            }
        }
        Self.trace("miss \(key.width)x\(key.height) standin=scaled "
            + "from=\(Int(stale.size.width))x\(Int(stale.size.height))")
        return stale.scaled(to: key.size)
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
