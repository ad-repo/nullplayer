import AppKit

/// Keeps the active `.wmz` skin's borrowed window frame (`WMPHostedFrameTemplate`) rendered at the
/// sizes NullPlayer's own windows are currently open at.
///
/// A ring is laid out by the skin's own alignment rules, so a frame rendered for one size cannot be
/// stretched to another without putting the corners in the wrong place: every distinct window size
/// is its own render. Three things follow, and they are the whole design of this type:
///
/// - **Nothing is built on the main thread.** `WMPSceneBuilder` resolves expressions and decodes
///   artwork, which the isolation rule in `wmp-skin-guide` keeps off the UI executor. A view asking
///   for a frame it does not have yet is answered *now* with the nearest thing available and told to
///   ask again when the real one lands (`.hostedSurfaceStyleDidChange`).
/// - **The nearest thing available is the nearest render of the current skin, re-laid out — never
///   stretched.** `WMPHostedFrameRelayout` moves a ring to another size the way its alignment rules
///   do: border thickness fixed, corners 1:1, edges spanning. A proportional stretch distorted the
///   corners; flat palette chrome flashed. Neither is drawn any more.
/// - **A hosted window never shows a transitional state.** A drag builds one render at a time and
///   never evicts a resting window's frame; a skin switch builds the new skin's frames in a staged
///   slot while the old skin keeps answering, and swaps every window over in one runloop turn.
///
/// The provider owns a **private** `WMPImageStore` rather than sharing the controller's. The
/// controller's store is read by the render loop that is painting the skin itself; a second
/// consumer on a background executor has no business in it.
@MainActor
final class WMPHostedFrameProvider {
    fileprivate struct Key: Hashable {
        let width: Int
        let height: Int
        init(_ size: CGSize) {
            width = Int(size.width.rounded())
            height = Int(size.height.rounded())
        }
        var size: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }
        var label: String { "\(width)x\(height)" }
    }

    /// How many window sizes are kept. A user with every hosted window open has fewer than this;
    /// the cap exists so a live resize cannot grow the cache without bound — and a drag's sizes are
    /// evicted first, so it can never push out the frame of a window nobody is touching.
    private static let cacheLimit = 12

    /// **One skin's frames.** A build captures the slot it was started for and writes only into it,
    /// which is what lets a staged skin and the live one coexist: a render that lands after its skin
    /// was replaced finds its slot gone and is dropped, with no generation counter to keep in step.
    @MainActor
    fileprivate final class Slot {
        /// What `derive` produced, kept even when a build's verdict drops `template` — it is what a
        /// later `configure` for the same skin is recognised by.
        let derived: WMPHostedFrameTemplate
        var template: WMPHostedFrameTemplate?
        let builder: WMPSceneBuilder
        let renderer: WMPRenderer
        var cache: [Key: SkinnedSurfaceFrameArtwork] = [:]
        var order: [Key] = []
        var inFlight: Set<Key> = []
        /// Window sizes this skin's donor has **refused** (W207). A refusal is a real answer and it
        /// has to be remembered: without it `artwork(for:)` re-scheduled the same build on every draw
        /// and went on standing a different window's frame in for it — reported 2026-09-16 as "you
        /// are squashing the window borders to the window size".
        var refused: Set<Key> = []
        /// Sizes rendered for a live resize rather than for a window at rest. Evicted first, and
        /// dropped when the drag ends, so a drag cannot push a resting window's frame out.
        var transient: Set<Key> = []
        var mostRecent: SkinnedSurfaceFrameArtwork?
        /// **The border this skin adds around a hosted window's interior, independent of any window
        /// (W207).** Nil until resolved, and for a donor that states none.
        var donorInsets: NSEdgeInsets?
        var insetsResolved = false
        /// The sizes this skin has already had speculative builds queued for (W250 — per size, not
        /// per skin). Recorded when queued, not when it succeeds, so a build that produces nothing
        /// is not retried on every broadcast.
        var prewarmedSizes: Set<Key> = []
        /// The one drag build in flight, and the latest size the drag asked for behind it.
        var dragBuild: Key?
        var pendingDrag: Key?

        init(template: WMPHostedFrameTemplate, skin: WMPLoadedSkin) {
            derived = template
            self.template = template
            let store = WMPImageStore(provider: skin.archive)
            builder = WMPSceneBuilder(loadedSkin: skin, imageStore: store)
            renderer = WMPRenderer(imageStore: store)
        }

        func touch(_ key: Key) {
            order.removeAll { $0 == key }
            order.append(key)
        }

        func forget(_ key: Key) {
            cache.removeValue(forKey: key)
            order.removeAll { $0 == key }
            transient.remove(key)
        }
    }

    /// **A skin on its way in (step E of the 2026-09-23 drag fix).** Its frames are rendered here, at
    /// the sizes every open hosted window will be once the new border is laid around its interior,
    /// while `live` goes on answering with the old skin unchanged. It becomes `live` in one runloop
    /// turn — with the player, when the controller holds the player back for it.
    @MainActor
    private final class Staged {
        let slot: Slot
        /// Commit by itself when ready. False while the controller is waiting to present the player
        /// in the same turn; that path commits from `configure`.
        let autoCommits: Bool
        let started = DispatchTime.now()
        var targets: Set<Key> = []
        var answered: Set<Key> = []
        var queue: [Key] = []
        var building = false
        var released = false
        var budgetExpired = false
        var waiters: [CheckedContinuation<Void, Never>] = []
        var budget: Timer?

        init(slot: Slot, autoCommits: Bool) {
            self.slot = slot
            self.autoCommits = autoCommits
        }

        var isReady: Bool {
            guard slot.template != nil else { return true }
            return slot.insetsResolved && targets.isSubset(of: answered)
        }
    }

    private var live: Slot? {
        didSet { if live !== oldValue { liveGeneration &+= 1 } }
    }
    /// Counts every change of `live`. An object's address is not an identity: a slot freed by one
    /// switch can be reallocated at the same address by the next.
    private var liveGeneration = 0
    private var staged: Staged?

    /// How many hosted windows are being dragged (step A). While positive, a miss is coalesced into
    /// one build at a time and the drag's sizes are transient.
    private var liveResizeDepth = 0
    /// The size the last drag ended at: the one drag size that is kept.
    private var lastResizeEnd: Key?

    /// Relaid stand-ins, per target size, so a window redrawn twenty times at one size during a drag
    /// pays for one relayout. Cleared whenever the cache the stand-ins were cut from changes.
    private var standIns: [Key: SkinnedSurfaceFrameArtwork] = [:]
    /// The seam analysis of each source render, by image identity; one pass over its pixels per render.
    private var relayouts: [ObjectIdentifier: (image: CGImage, relayout: WMPHostedFrameRelayout)] = [:]

    /// The sizes the open hosted windows will be at under `insets` — supplied by the controller from
    /// `HostedWindowBorderLayout`, which owns the interiors. Used to stage a skin switch.
    var openWindowTargets: (NSEdgeInsets) -> [CGSize] = { _ in [] }
    /// Whether any hosted window is on screen, wearing a frame the user would see change. A skin
    /// load with nothing on screen has nothing to keep consistent and is not staged.
    var hostedWindowsVisible: () -> Bool = { false }

    var template: WMPHostedFrameTemplate? { live?.template }

    /// **The border this skin adds around a hosted window's interior (W207)** — the live skin's.
    var donorInsets: NSEdgeInsets? { live?.donorInsets }

    /// Whether this skin lends a frame at all, which is **not** the same question as whether its
    /// borders have resolved yet. `donorInsets` is nil for both, and the two need telling apart: a
    /// skin that lends nothing is settled the moment it loads, while one that lends a ring is still
    /// resolving and a window's frame read back during that gap is read against the wrong border.
    var lendsFrame: Bool { live?.template != nil }

    /// The live skin's identity: changes exactly when a switch commits, which is when the border
    /// every hosted window wears changes. Nil while no skin lends a frame.
    var liveSkinToken: Int? { live == nil ? nil : liveGeneration }

    /// Whether a skin is on its way in while the old one goes on answering.
    var isStagingSwitch: Bool { staged != nil }

    // MARK: - Adopting a skin

    /// Adopt a newly presented skin. Answers whether the skin has a frame to lend at all, which is
    /// what decides between artwork chrome and the palette-only chrome every `.wmz` gets today.
    ///
    /// Three outcomes: a staged switch for this skin is **committed** — every hosted window flips in
    /// this turn; a skin arriving while hosted windows are on screen and nothing was staged is
    /// **staged now** and commits itself when ready, the old skin answering meanwhile; and otherwise
    /// it is adopted immediately, because nothing on screen would see the difference.
    // MARK: - The donor's scripted appearance (W145)

    /// What the donor view's `onLoad` committed, for the skin and donor view it was run against.
    private var scriptedAppearance: (skin: ObjectIdentifier, viewID: String, overrides: WMPSceneOverrides)?

    /// The template for `skin`, drawn with the appearance its donor's script chose when one was
    /// computed for this skin and this donor.
    private func derive(_ skin: WMPLoadedSkin, playerViewID: String?) -> WMPHostedFrameTemplate? {
        guard let derived = WMPHostedFrameTemplate.derive(from: skin, playerViewID: playerViewID) else {
            return nil
        }
        guard let scriptedAppearance, scriptedAppearance.skin == ObjectIdentifier(skin),
              scriptedAppearance.viewID.caseInsensitiveCompare(derived.viewID) == .orderedSame
        else { return derived }
        return derived.appearing(scriptedAppearance.overrides)
    }

    /// **Run the donor view's `onLoad` off-screen and keep what it did to the frame's artwork.**
    ///
    /// A throwaway runtime over a *copy* of the skin's preferences: the handler runs exactly as it
    /// would when the skin opens that view, and none of its writes, timers or host commands reach
    /// the session. Returns whether the appearance moved, so the caller knows to rebuild.
    /// `WMP_FRAME_APPEARANCE=0` draws the frame from markup alone, as before W145 — the A/B switch.
    static let followsScriptedAppearance =
        ProcessInfo.processInfo.environment["WMP_FRAME_APPEARANCE"] != "0"

    @discardableResult
    func refreshScriptedAppearance(skin: WMPLoadedSkin, playerViewID: String?,
                                   preferences: [String: String],
                                   snapshot: WMPHostSnapshot) async -> Bool {
        guard Self.followsScriptedAppearance,
              let template = WMPHostedFrameTemplate.derive(from: skin, playerViewID: playerViewID),
              let registration = skin.views.first(where: {
                  $0.id.caseInsensitiveCompare(template.viewID) == .orderedSame
              })
        else { return false }
        let handlers = WMPMainWindowController.handlers(in: skin, event: "load", targetID: nil,
                                                        viewID: registration.id)
        guard !handlers.isEmpty,
              let scene = try? await WMPSceneBuilder(loadedSkin: skin).build(viewID: registration.id)
        else { return false }
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(copying: preferences))
        let output = await runtime.transact(
            skin: skin, viewID: registration.id, size: scene.canvasSize, snapshot: snapshot,
            event: WMPJScriptEvent(name: "load", targetID: registration.id, handlers: handlers),
            geometry: scene.scriptGeometry)
        await runtime.teardown()
        let before = scriptedAppearance.flatMap {
            $0.skin == ObjectIdentifier(skin) ? template.appearing($0.overrides).appearance : nil
        } ?? [:]
        scriptedAppearance = (ObjectIdentifier(skin), template.viewID, output.overrides)
        let after = template.appearing(output.overrides).appearance
        Self.trace("appearance view=\(template.viewID) properties=\(after.count) moved=\(after != before)")
        return after != before
    }

    @discardableResult
    func configure(skin: WMPLoadedSkin, playerViewID: String?) -> Bool {
        let derived = derive(skin, playerViewID: playerViewID)
        if let live, derived == live.template, staged == nil { return derived != nil }
        if let staged, let derived, staged.slot.derived == derived {
            // A switch staging itself in the background is not hurried by a second present of the
            // same skin; one the controller held the player back for commits with the player.
            if staged.autoCommits, !staged.isReady { return true }
            commit(reason: staged.isReady ? "ready" : "budget")
            return lendsFrame
        }
        cancelStaged()
        guard let derived else {
            reset()
            return false
        }
        if let live, derived == live.template { return true }
        let slot = Slot(template: derived, skin: skin)
        if Self.stagesSwitches, hostedWindowsVisible() {
            beginStaging(slot, autoCommits: true)
            return true
        }
        reset()
        live = slot
        resolveInsets(slot)
        return true
    }

    /// **Build the incoming skin's frames before the player is presented (step E).** Returns when
    /// every open hosted window has a final answer from the new skin — a frame or a refusal — or
    /// when the `WMP_HOSTED_HOLD_MS` budget runs out. The caller then presents the player, and
    /// `configure` from that same turn commits the switch, so the player and every hosted window
    /// change skin in one frame.
    ///
    /// Returns at once when there is nothing to keep consistent: no hosted window on screen, a skin
    /// that lends nothing (it commits immediately in `configure`), or the skin already live.
    func stage(skin: WMPLoadedSkin, playerViewID: String?) async {
        guard Self.stagesSwitches, hostedWindowsVisible(),
              let derived = derive(skin, playerViewID: playerViewID),
              derived != live?.template
        else { return }
        if staged?.slot.derived != derived {
            cancelStaged()
            beginStaging(Slot(template: derived, skin: skin), autoCommits: false)
        }
        guard let staged, !staged.released else { return }
        await withCheckedContinuation { continuation in staged.waiters.append(continuation) }
    }

    /// Drop everything — a skin teardown, or a switch to the unskinned player.
    func reset() {
        cancelStaged()
        live = nil
        scriptedAppearance = nil
        standIns.removeAll()
        relayouts.removeAll()
    }

    private func beginStaging(_ slot: Slot, autoCommits: Bool) {
        let entry = Staged(slot: slot, autoCommits: autoCommits)
        staged = entry
        Self.trace("stage begin auto=\(autoCommits)")
        entry.budget = Timer.scheduledTimer(withTimeInterval: Self.stageBudget, repeats: false) {
            [weak self, weak entry] _ in
            MainActor.assumeIsolated {
                guard let self, let entry, self.staged === entry else { return }
                entry.budgetExpired = true
                if entry.autoCommits {
                    self.commit(reason: "budget")
                } else {
                    self.release(entry)
                }
            }
        }
        resolveInsets(slot)
    }

    /// The staged skin's border has resolved: its targets are now knowable.
    private func stagedInsetsResolved(_ entry: Staged) {
        retarget(entry)
        checkStaged()
    }

    /// Ask the border layout what size every open hosted window will be under the staged border, and
    /// queue whatever the staged skin has not answered yet. Re-run when a drag ends mid-switch.
    private func retarget(_ entry: Staged) {
        guard entry.slot.template != nil, let insets = entry.slot.donorInsets else { return }
        for size in openWindowTargets(insets) where size.width > 0 && size.height > 0 {
            let key = Key(size)
            guard entry.targets.insert(key).inserted else { continue }
            if entry.slot.cache[key] != nil || entry.slot.refused.contains(key) {
                entry.answered.insert(key)
            } else if !entry.queue.contains(key) {
                entry.queue.append(key)
            }
        }
        Self.trace("stage targets=" + entry.targets.map(\.label).sorted().joined(separator: ","))
        pumpStaged()
    }

    /// One staged build at a time: these are the frames a switch waits on, and running them side by
    /// side slows every one of them down (a drag's concurrent builds measured 2–4.7 s each against
    /// 0.3–1.3 s alone).
    private func pumpStaged() {
        guard let entry = staged, !entry.building, entry.slot.template != nil else { return }
        while let next = entry.queue.first {
            entry.queue.removeFirst()
            if entry.slot.cache[next] != nil || entry.slot.refused.contains(next) {
                entry.answered.insert(next)
                continue
            }
            entry.building = true
            schedule(next, in: entry.slot)
            return
        }
    }

    private func checkStaged() {
        guard let entry = staged, entry.isReady else { return }
        if entry.autoCommits {
            commit(reason: "ready")
        } else {
            release(entry)
        }
    }

    /// Let a caller waiting in `stage` go on to present the player.
    private func release(_ entry: Staged) {
        guard !entry.released else { return }
        entry.released = true
        Self.trace("stage \(entry.budgetExpired ? "budget" : "ready") ms=\(Self.elapsed(since: entry.started))")
        let waiters = entry.waiters
        entry.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// **The switch, in one turn.** The staged skin becomes live, its border becomes the border, and
    /// one notification makes `HostedWindowBorderLayout` resize every window to exactly the sizes
    /// that were pre-rendered — so each one draws its own exact frame on the first draw.
    private func commit(reason: String) {
        guard let entry = staged else { return }
        entry.budget?.invalidate()
        staged = nil
        live = entry.slot.template != nil ? entry.slot : nil
        standIns.removeAll()
        relayouts.removeAll()
        let unanswered = entry.targets.subtracting(entry.answered).map(\.label).sorted()
        Self.trace("commit reason=\(reason) ms=\(Self.elapsed(since: entry.started)) "
            + "targets=\(entry.targets.count) unanswered=\(unanswered.joined(separator: ","))")
        let waiters = entry.waiters
        entry.waiters.removeAll()
        entry.released = true
        waiters.forEach { $0.resume() }
        // Whatever the staged queue had not reached is still wanted, now by the live skin.
        if let live { for key in entry.queue { schedule(key, in: live) } }
        NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
    }

    private func cancelStaged() {
        guard let entry = staged else { return }
        entry.budget?.invalidate()
        staged = nil
        Self.trace("stage cancelled")
        let waiters = entry.waiters
        entry.waiters.removeAll()
        entry.released = true
        waiters.forEach { $0.resume() }
    }

    private func owns(_ slot: Slot) -> Bool { slot === live || slot === staged?.slot }

    /// Learn the donor's four borders. One scene build, off the UI executor like every other.
    ///
    /// **It also primes the stand-in (W230).** Learning a ring's borders is composing one, and the
    /// composition is kept as `mostRecent` — never in `cache`, which promises a frame was built for
    /// the size asked for — so the first hosted window to open has something to relay from.
    private func resolveInsets(_ slot: Slot) {
        guard let template = slot.template else { return }
        let builder = slot.builder, renderer = slot.renderer
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let started = DispatchTime.now()
        Task { [weak self] in
            let border = try? await template.border(builder: builder, renderer: renderer,
                                                    backingScale: scale)
            Self.trace("insets ok=\(border?.insets != nil) primed=\(border?.primed != nil) "
                + "ms=\(Self.elapsed(since: started))")
            await MainActor.run {
                guard let self, self.owns(slot) else { return }
                slot.insetsResolved = true
                slot.donorInsets = border?.insets
                if Self.primes, let primed = border?.primed, slot.mostRecent == nil {
                    slot.mostRecent = primed
                }
                if slot === self.live {
                    guard border?.insets != nil else { return }
                    NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
                } else if let entry = self.staged, entry.slot === slot {
                    self.stagedInsetsResolved(entry)
                }
            }
        }
    }

    // MARK: - A live resize

    /// A hosted window started being dragged to a new size (step A).
    func beginLiveResize() {
        liveResizeDepth += 1
        Self.trace("live-resize begin depth=\(liveResizeDepth)")
    }

    /// The drag ended at `size`. Every intermediate size is dropped, the final one is built — it is
    /// the size the window will rest at — and a switch staged meanwhile learns the new interior.
    func endLiveResize(at size: CGSize) {
        guard liveResizeDepth > 0 else { return }
        liveResizeDepth -= 1
        Self.trace("live-resize end depth=\(liveResizeDepth) at=\(Key(size).label)")
        guard liveResizeDepth == 0 else { return }
        let final = Key(size)
        lastResizeEnd = final
        if let live {
            live.pendingDrag = nil
            for key in live.transient where key != final { live.forget(key) }
            live.transient.removeAll()
            standIns.removeAll()
        }
        demand(size)
        if let entry = staged { retarget(entry) }
    }

    // MARK: - Drawing

    /// The frame for a window of `size`, or nil when this skin lends none.
    ///
    /// Never blocks: a size that has not been rendered yet schedules its render and is answered with
    /// the nearest render of this skin, re-laid out to fit.
    func artwork(for size: CGSize) -> SkinnedSurfaceFrameArtwork? {
        guard let slot = live, slot.template != nil, size.width > 0, size.height > 0 else { return nil }
        let key = Key(size)
        if let cached = slot.cache[key] {
            slot.touch(key)
            return cached
        }
        // A size the donor has already turned down keeps the palette chrome it had before, and asks
        // no second time.
        if slot.refused.contains(key) {
            Self.trace("miss \(key.label) standin=refused")
            return nil
        }
        guard Self.relaysDuringResize else { return legacyStandIn(for: key, in: slot) }
        if liveResizeDepth > 0 {
            scheduleDrag(key, in: slot)
        } else {
            schedule(key, in: slot)
        }
        return standIn(for: key, in: slot)
    }

    /// **The nearest render of the current skin, re-laid out to `key` — never stretched.** No
    /// tolerance applies: a relayout keeps the border's thickness and the corners' shape at any
    /// distance, which is exactly what the 15% rule was there to protect.
    private func standIn(for key: Key, in slot: Slot) -> SkinnedSurfaceFrameArtwork? {
        if let memo = standIns[key] { return memo }
        guard let source = nearest(to: key, in: slot) else {
            Self.trace("miss \(key.label) standin=none")
            return nil
        }
        guard let relaid = relayout(of: source)?.relaid(source, to: key.size) else {
            Self.trace("miss \(key.label) standin=unrelayable from=\(Key(source.size).label)")
            return nil
        }
        Self.trace("miss \(key.label) standin=relaid from=\(Key(source.size).label)")
        if standIns.count > 16 { standIns.removeAll() }
        standIns[key] = relaid
        return relaid
    }

    private func nearest(to key: Key, in slot: Slot) -> SkinnedSurfaceFrameArtwork? {
        var candidates = Array(slot.cache.values)
        if let primed = slot.mostRecent, !candidates.contains(where: { $0.image === primed.image }) {
            candidates.append(primed)
        }
        return candidates.min { lhs, rhs in
            abs(lhs.size.width - key.size.width) + abs(lhs.size.height - key.size.height)
                < abs(rhs.size.width - key.size.width) + abs(rhs.size.height - key.size.height)
        }
    }

    private func relayout(of source: SkinnedSurfaceFrameArtwork) -> WMPHostedFrameRelayout? {
        let id = ObjectIdentifier(source.image)
        if let known = relayouts[id], known.image === source.image { return known.relayout }
        guard let made = WMPHostedFrameRelayout(source) else { return nil }
        if relayouts.count > 16 { relayouts.removeAll() }
        relayouts[id] = (source.image, made)
        return made
    }

    /// `WMP_FRAME_LIVE_RESIZE=0` — the pre-2026-09-23 stand-in: the last render stretched, and
    /// refused past 15% so the window drew palette chrome.
    private func legacyStandIn(for key: Key, in slot: Slot) -> SkinnedSurfaceFrameArtwork? {
        schedule(key, in: slot)
        guard let stale = slot.mostRecent else {
            Self.trace("miss \(key.label) standin=none")
            return nil
        }
        if !Self.standsInAtAnyScale {
            let widthRatio = stale.size.width > 0 ? key.size.width / stale.size.width : 0
            let heightRatio = stale.size.height > 0 ? key.size.height / stale.size.height : 0
            guard (0.85...1.15).contains(widthRatio), (0.85...1.15).contains(heightRatio) else {
                Self.trace("miss \(key.label) standin=out-of-scale from=\(Key(stale.size).label)")
                return nil
            }
        }
        Self.trace("miss \(key.label) standin=scaled from=\(Key(stale.size).label)")
        return stale.scaled(to: key.size)
    }

    // MARK: - Speculative and demanded builds

    /// **Render the frames the hosted windows are going to ask for, before they ask (W248).**
    ///
    /// Serial, deliberately: these are speculative builds for windows that may never open. A size
    /// already cached, refused or in flight is skipped. The caller decides *which* sizes, because the
    /// interiors and their recency belong to `HostedWindowBorderLayout`.
    func prewarm(_ sizes: [CGSize]) {
        // **Not during a drag.** `HostedWindowBorderLayout` names the dragged window's live frame,
        // which is a size the drag is passing through — a full render nothing will rest at, outside
        // the one-at-a-time drag queue. The drag's end demands the size it came to rest at.
        guard Self.prewarms, liveResizeDepth == 0 || !Self.relaysDuringResize,
              let slot = live, let template = slot.template else { return }
        var queue: [Key] = []
        for size in sizes where size.width > 0 && size.height > 0 {
            let key = Key(size)
            guard !slot.prewarmedSizes.contains(key), slot.cache[key] == nil,
                  !slot.refused.contains(key), !slot.inFlight.contains(key),
                  !queue.contains(key) else { continue }
            queue.append(key)
            slot.prewarmedSizes.insert(key)
            slot.inFlight.insert(key)
        }
        guard !queue.isEmpty else { return }
        let builder = slot.builder, renderer = slot.renderer
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Self.trace("prewarm queued=" + queue.map(\.label).joined(separator: ","))
        Task { [weak self] in
            for key in queue {
                let started = DispatchTime.now()
                let produced = try? await template.artwork(builder: builder, renderer: renderer,
                                                           size: key.size, backingScale: scale)
                guard let self else { return }
                let stop = await MainActor.run { () -> Bool in
                    // The skin changed under the queue: every remaining size belongs to a donor
                    // that is gone.
                    guard slot === self.live else { return true }
                    slot.inFlight.remove(key)
                    Self.trace("prewarmed \(key.label) ok=\(produced != nil) "
                        + "ms=\(Self.elapsed(since: started))")
                    // **A refusal here is not recorded.** A speculative build has no window behind
                    // it; the drawing path gives a size its real answer if a window opens at it.
                    guard let produced else { return false }
                    self.store(produced, for: key, in: slot, transient: false)
                    NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
                    return false
                }
                if stop { return }
            }
        }
    }

    /// **Whether this skin has a *final* answer for `size` right now (W250)** — a frame rendered for
    /// exactly this size, a refusal recorded for it, or a skin that lends no frame at all.
    func hasSettledAnswer(for size: CGSize) -> Bool {
        guard let slot = live, slot.template != nil, size.width > 0, size.height > 0 else { return true }
        let key = Key(size)
        return slot.cache[key] != nil || slot.refused.contains(key)
    }

    /// **Render `size` now, because a window is about to open — or has come to rest — at it (W250).**
    /// Idempotent: a size already in flight joins that build.
    func demand(_ size: CGSize) {
        guard let slot = live, slot.template != nil, size.width > 0, size.height > 0 else { return }
        let key = Key(size)
        slot.transient.remove(key)
        guard slot.cache[key] == nil, !slot.refused.contains(key) else { return }
        Self.trace("demand \(key.label)")
        schedule(key, in: slot)
    }

    /// **The frame actually rendered for `size` — no stand-in, and no build scheduled (W238).** The
    /// measuring seam: a relaid stand-in's insets are the source's, and asking must not cost a render.
    func renderedArtwork(for size: CGSize) -> SkinnedSurfaceFrameArtwork? {
        guard size.width > 0, size.height > 0 else { return nil }
        return live?.cache[Key(size)]
    }

    /// **One drag build at a time (step B).** Every pixel of a drag used to start its own full
    /// render, dozens at once, finishing out of order and each re-laying out every hosted window;
    /// the size the drag ended at waited behind all of them. Now the latest size waits behind the
    /// one build in flight, and the frame updates progressively at render speed.
    private func scheduleDrag(_ key: Key, in slot: Slot) {
        if slot.dragBuild == nil {
            guard !slot.inFlight.contains(key) else { return }
            slot.dragBuild = key
            schedule(key, in: slot, isDragBuild: true)
        } else if slot.dragBuild != key {
            slot.pendingDrag = key
        }
    }

    private func schedule(_ key: Key, in slot: Slot, isDragBuild: Bool = false) {
        guard let template = slot.template, slot.inFlight.insert(key).inserted else { return }
        let builder = slot.builder, renderer = slot.renderer
        let scale = NSScreen.main?.backingScaleFactor ?? 2
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
            await MainActor.run {
                guard self.owns(slot) else { return }
                self.landed(key, produced: produced, unslicable: unslicable, ringOpen: ringOpen,
                            in: slot, isDragBuild: isDragBuild, started: started)
            }
        }
    }

    private func landed(_ key: Key, produced: SkinnedSurfaceFrameArtwork?, unslicable: Bool,
                        ringOpen: Bool, in slot: Slot, isDragBuild: Bool, started: DispatchTime) {
        slot.inFlight.remove(key)
        let stagedEntry = staged?.slot === slot ? staged : nil
        Self.trace("built \(key.label) ok=\(produced != nil) ms=\(Self.elapsed(since: started))"
            + (isDragBuild ? " drag" : "") + (stagedEntry != nil ? " staged" : ""))
        defer {
            if isDragBuild {
                slot.dragBuild = nil
                if liveResizeDepth > 0, let pending = slot.pendingDrag {
                    slot.pendingDrag = nil
                    if slot.cache[pending] == nil, !slot.refused.contains(pending) {
                        scheduleDrag(pending, in: slot)
                    }
                }
            }
            if let stagedEntry {
                stagedEntry.answered.insert(key)
                stagedEntry.building = false
                pumpStaged()
                checkStaged()
            }
        }
        guard let produced else {
            // The older diagnostic assembler (`WMP_HOSTED_FRAME_WHOLE=0`) can refuse an open ring.
            // This branch drops the donor as a fallback policy, not proof that every size fails.
            if ringOpen {
                slot.template = nil
                slot.donorInsets = nil
                slot.cache.removeAll()
                slot.order.removeAll()
                slot.transient.removeAll()
                slot.mostRecent = nil
                if slot === live {
                    standIns.removeAll()
                    NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
                }
                return
            }
            if !unslicable { slot.refused.insert(key) }
            // **A panel that cannot be sliced lends nothing, and only the artwork pass knows**
            // (W207). Only the donor's own verdict drops it, and only while nothing has ever been
            // produced: a window too short for the panel's borders is answered nil per size.
            if unslicable, slot.template?.panelNodeID != nil, slot.mostRecent == nil {
                slot.template = nil
                if slot === live {
                    NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
                }
            }
            return
        }
        // A drag build is transient unless the drag has already ended *at* it.
        let transient = isDragBuild && !(liveResizeDepth == 0 && key == lastResizeEnd)
        store(produced, for: key, in: slot, transient: transient)
        if slot === live {
            NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
        }
    }

    private func store(_ artwork: SkinnedSurfaceFrameArtwork, for key: Key, in slot: Slot,
                       transient: Bool) {
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["WMP_HOSTED_FRAME_DUMP"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let bitmap = NSBitmapImageRep(cgImage: artwork.image)
            try? bitmap.representation(using: .png, properties: [:])?.write(
                to: url.appendingPathComponent("\(key.label)-frame.png"))
            Self.trace("dump \(key.label) content=\(artwork.contentRect) over=\(artwork.paintsOverContent)")
        }
        #endif
        slot.cache[key] = artwork
        slot.mostRecent = artwork
        if transient { slot.transient.insert(key) } else { slot.transient.remove(key) }
        slot.touch(key)
        while slot.order.count > Self.cacheLimit {
            // **A drag's sizes go first**, so a drag can never evict the exact frame of a window at
            // rest — which is what left the untouched windows missing, and wearing the old skin.
            guard let victim = slot.order.first(where: { slot.transient.contains($0) })
                    ?? slot.order.first else { break }
            slot.forget(victim)
        }
        if slot === live { standIns.removeAll() }
    }

    // MARK: - Switches

    /// `WMP_FRAME_TRACE=1` — the interval before a frame exists, which nothing headless can see.
    /// `miss` is a window drawing without its own frame, and `standin=` says what it drew instead:
    /// `relaid from=` (the nearest render, re-laid out), `refused`, `none`, `unrelayable`, and with
    /// `WMP_FRAME_LIVE_RESIZE=0` the old `scaled` / `out-of-scale`. `built` closes it, marked `drag`
    /// or `staged`; `stage …` and `commit reason=ready|budget` trace a skin switch, and a
    /// `reason=budget` is the switch failing, not working. `NSLog`, not `print`, for the reason
    /// `WMP_BORDER_TRACE` records.
    /// `WMP_FRAME_PRIME=0` — withhold the primed stand-in and restore the pre-W230 first open.
    private static let primes = ProcessInfo.processInfo.environment["WMP_FRAME_PRIME"] != "0"

    /// `WMP_HOSTED_PREWARM=0` — never build a frame for a window that is not open (W248's A/B).
    private static let prewarms = ProcessInfo.processInfo.environment["WMP_HOSTED_PREWARM"] != "0"

    /// `WMP_FRAME_STANDIN=always` — with `WMP_FRAME_LIVE_RESIZE=0`, the pre-W248 stand-in that
    /// stretched a ring onto any window size.
    private static let standsInAtAnyScale =
        ProcessInfo.processInfo.environment["WMP_FRAME_STANDIN"] == "always"

    /// `WMP_FRAME_LIVE_RESIZE=0` — restore the pre-2026-09-23 behaviour in one binary: a build per
    /// drag pixel, the last render stretched and refused past 15% (palette chrome), and a skin
    /// switch adopted at once rather than staged. The A/B switch for the whole drag fix.
    private static let liveResizeFix =
        ProcessInfo.processInfo.environment["WMP_FRAME_LIVE_RESIZE"] != "0"
    private static var relaysDuringResize: Bool { liveResizeFix }
    private static var stagesSwitches: Bool { liveResizeFix }

    /// How long a staged switch may take before it commits anyway — `WMP_HOSTED_HOLD_MS`, the same
    /// budget a held window open gets (default 4000 ms).
    private static let stageBudget: TimeInterval = {
        let stated = ProcessInfo.processInfo.environment["WMP_HOSTED_HOLD_MS"].flatMap(Double.init)
        return max(0, (stated ?? 4000) / 1000)
    }()

    private static let traces = ProcessInfo.processInfo.environment["WMP_FRAME_TRACE"] != nil

    private static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard traces else { return }
        NSLog("[wmp/frame] \(message())")
        #endif
    }

    private nonisolated static func elapsed(since started: DispatchTime) -> Int {
        Int((Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6).rounded())
    }
}

extension SkinnedSurfaceFrameArtwork {
    /// The same picture stretched onto another window size. Only the `WMP_FRAME_LIVE_RESIZE=0`
    /// stand-in still draws this; everything else relays out (`WMPHostedFrameRelayout`).
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
