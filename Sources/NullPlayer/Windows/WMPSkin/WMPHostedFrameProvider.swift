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
    private var mostRecent: SkinnedSurfaceFrameArtwork?
    private var generation = 0

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
        return true
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
        mostRecent = nil
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
        schedule(key)
        return mostRecent?.scaled(to: key.size)
    }

    private func schedule(_ key: Key) {
        guard let template, let builder, let renderer, inFlight.insert(key).inserted else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let generation = self.generation
        Task { [weak self] in
            let produced = try? await template.artwork(builder: builder, renderer: renderer,
                                                       size: key.size, backingScale: scale)
            guard let self else { return }
            await MainActor.run {
                guard self.generation == generation else { return }
                self.inFlight.remove(key)
                guard let produced else { return }
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
            wasScaledToFit: true
        )
    }
}
