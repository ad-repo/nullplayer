import AppKit

/// Round images for library list rows — album/artist/track/video art, radio station icons,
/// YouTube video thumbnails and channel avatars — shared by both library browsers.
///
/// One load makes both renditions of a row's art (`Renditions`): the round row thumbnail and the
/// hover preview. They are written to `RowThumbnailDiskCache`, which is read before any loader
/// runs, so a relaunch draws from disk. `thumbnail(for:)` returns a cached image or queues a load;
/// when one lands, `didLoadNotification` is posted so the browser redraws. Rows on screen load
/// first, newest request first; `preload` queues the rows either side of them behind those.
@MainActor
final class LibraryRowThumbnails {
    static let shared = LibraryRowThumbnails()
    static let didLoadNotification = Notification.Name("LibraryRowThumbnailDidLoad")

    private static let maxConcurrentLoads = 4
    private static let maxPendingLoads = 300

    /// Where a row's art comes from, and the key both renditions are cached under.
    struct Source {
        let key: String
        let load: () async -> NSImage?

        /// One fetch at preview size; the thumbnail is cut from it. A channel without an avatar
        /// still gets a source, so its row keeps the placeholder and its title stays aligned.
        static func channel(_ channel: YouTubeChannel) -> Source {
            guard let url = channel.avatarURL(side: 320) else { return Source(key: "channel:\(channel.id)", load: { nil }) }
            return remote(url)
        }

        static func video(_ video: YouTubeVideo) -> Source { remote(video.rowThumbnailURL) }

        private static func remote(_ url: URL) -> Source {
            Source(key: "url:\(url.absoluteString)", load: {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                return NSImage(data: data)
            })
        }
    }

    /// The two sizes of one row's art: a square for the round row thumbnail, and the art in its
    /// own shape for the hover preview.
    struct Renditions {
        let thumbnail: CGImage
        let preview: CGImage

        /// Pixel side of the thumbnail: a row is ~18 pt, so this covers 2x with headroom.
        static let thumbnailPixels = 64
        /// The preview's longer side in pixels: 2x `RowThumbnailPreview.maxSide`.
        static let previewPixels = 400

        /// Centre-crop and downscale for the thumbnail; downscale (never up) in the art's own
        /// aspect for the preview, flattened onto black so it can be stored as JPEG.
        init?(from source: NSImage) {
            guard let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let square = source.squareCenterCropped().cgImage(forProposedRect: nil, context: nil, hints: nil),
                  image.width > 0, image.height > 0 else { return nil }
            let thumbnailSide = min(Self.thumbnailPixels, square.width)
            let scale = min(1, CGFloat(Self.previewPixels) / CGFloat(max(image.width, image.height)))
            guard let thumbnail = Self.render(square, width: thumbnailSide, height: thumbnailSide, opaque: false),
                  let preview = Self.render(image,
                                            width: max(1, Int((CGFloat(image.width) * scale).rounded())),
                                            height: max(1, Int((CGFloat(image.height) * scale).rounded())),
                                            opaque: true) else { return nil }
            self.init(thumbnail: thumbnail, preview: preview)
        }

        init(thumbnail: CGImage, preview: CGImage) {
            self.thumbnail = thumbnail
            self.preview = preview
        }

        private static func render(_ image: CGImage, width: Int, height: Int, opaque: Bool) -> CGImage? {
            let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)
            else { return nil }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            if opaque {
                context.setFillColor(NSColor.black.cgColor)
                context.fill(rect)
            }
            context.interpolationQuality = .high
            context.draw(image, in: rect)
            return context.makeImage()
        }
    }

    private final class ImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let thumbnails: NSCache<NSString, ImageBox> = {
        let cache = NSCache<NSString, ImageBox>()
        cache.countLimit = 3000
        return cache
    }()
    /// Previews are ~600 KB decoded each, so memory holds the recent ones and disk the rest.
    private let previews: NSCache<NSString, ImageBox> = {
        let cache = NSCache<NSString, ImageBox>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private let diskCache = RowThumbnailDiskCache.standard
    /// Queued loads, lowest priority first: `popLast` takes the next.
    private var pending: [Source] = []
    private var pendingKeys: Set<String> = []
    private var inFlight: [String: Task<Renditions?, Never>] = [:]
    /// Keys whose load failed or found no art — not retried this session.
    private var failed: Set<String> = []
    private var didLoadPostScheduled = false

    private(set) lazy var preview = RowThumbnailPreview { [unowned self] in await self.previewImage(for: $0) }

    private init() {
        let diskCache = diskCache
        Task.detached(priority: .background) { diskCache.prune() }
    }

    /// The row thumbnail, or nil while it loads (the request moves to the front of the queue)
    /// or when the row has no art.
    func thumbnail(for source: Source) -> CGImage? {
        if let cached = thumbnails.object(forKey: source.key as NSString) { return cached.image }
        guard inFlight[source.key] == nil, !failed.contains(source.key) else { return nil }
        removeFromPending(source.key)
        pending.append(source)
        pendingKeys.insert(source.key)
        trimPending()
        startPendingLoads()
        return nil
    }

    /// Queue the rows either side of `visible` behind everything already waiting. `source` maps a
    /// row index to its art; rows already loaded, loading, queued or failed are left alone.
    func preload(around visible: Range<Int>, count: Int, source: (Int) -> Source?) {
        var added = false
        for index in Self.preloadOrder(around: visible, count: count) {
            guard let source = source(index) else { continue }
            let key = source.key
            guard thumbnails.object(forKey: key as NSString) == nil, inFlight[key] == nil,
                  !failed.contains(key), !pendingKeys.contains(key) else { continue }
            pending.insert(source, at: 0)
            pendingKeys.insert(key)
            added = true
        }
        guard added else { return }
        trimPending()
        startPendingLoads()
    }

    /// Two screens of rows either side of `visible`, nearest first, alternating below and above.
    nonisolated static func preloadOrder(around visible: Range<Int>, count: Int) -> [Int] {
        let span = max(visible.count, 10) * 2
        return (0..<span)
            .flatMap { [visible.upperBound + $0, visible.lowerBound - 1 - $0] }
            .filter { (0..<count).contains($0) }
    }

    /// The hover preview: memory, then disk, then the row's own load (moved to the front).
    private func previewImage(for source: Source) async -> CGImage? {
        let key = source.key
        if let cached = previews.object(forKey: key as NSString) { return cached.image }
        guard !failed.contains(key) else { return nil }
        let diskCache = diskCache
        if let preview = await Task.detached(priority: .userInitiated, operation: { diskCache.readPreview(key) }).value {
            previews.setObject(ImageBox(preview), forKey: key as NSString, cost: preview.bytesPerRow * preview.height)
            return preview
        }
        removeFromPending(key)
        return await startLoad(source).value?.preview
    }

    private func removeFromPending(_ key: String) {
        guard pendingKeys.remove(key) != nil else { return }
        pending.removeAll { $0.key == key }
    }

    private func trimPending() {
        let excess = pending.count - Self.maxPendingLoads
        guard excess > 0 else { return }
        for dropped in pending.prefix(excess) { pendingKeys.remove(dropped.key) }
        pending.removeFirst(excess)
    }

    private func startPendingLoads() {
        while inFlight.count < Self.maxConcurrentLoads, let next = pending.popLast() {
            pendingKeys.remove(next.key)
            startLoad(next)
        }
    }

    @discardableResult
    private func startLoad(_ source: Source) -> Task<Renditions?, Never> {
        if let running = inFlight[source.key] { return running }
        let task = Task { await self.load(source) }
        inFlight[source.key] = task
        Task {
            let renditions = await task.value
            self.inFlight[source.key] = nil
            if let renditions {
                let key = source.key as NSString
                self.thumbnails.setObject(ImageBox(renditions.thumbnail), forKey: key)
                self.previews.setObject(ImageBox(renditions.preview), forKey: key,
                                        cost: renditions.preview.bytesPerRow * renditions.preview.height)
                self.postDidLoad()
            } else {
                self.failed.insert(source.key)
            }
            self.startPendingLoads()
        }
        return task
    }

    /// Disk first; otherwise run the row's loader, render both renditions and write them back.
    private func load(_ source: Source) async -> Renditions? {
        let key = source.key
        let diskCache = diskCache
        if let cached = await Task.detached(priority: .utility, operation: { diskCache.read(key) }).value {
            return cached
        }
        guard let image = await source.load() else { return nil }
        return await Task.detached(priority: .utility) {
            guard let renditions = Renditions(from: image) else { return nil }
            diskCache.write(renditions, key: key)
            return renditions
        }.value
    }

    /// Preloads land in bursts; one redraw per run-loop pass covers them all.
    private func postDidLoad() {
        guard !didLoadPostScheduled else { return }
        didLoadPostScheduled = true
        DispatchQueue.main.async {
            self.didLoadPostScheduled = false
            NotificationCenter.default.post(name: Self.didLoadNotification, object: self)
        }
    }
}

/// One browser's row thumbnails in its current list pass: each is drawn round through the shared
/// cache, and where it landed is kept so a mouse position can show that row's preview.
@MainActor
final class LibraryRowThumbnailTracker {
    private var drawn: [(rect: CGRect, source: LibraryRowThumbnails.Source)] = []
    private var placeholder = NSColor.clear

    /// Start a list pass. `placeholder` fills a circle until its art loads, or when there is none,
    /// so titles never shift.
    func beginPass(placeholder: NSColor) {
        drawn.removeAll(keepingCapacity: true)
        self.placeholder = placeholder
    }

    /// Draw `source` round, centred vertically in `rowRect` at `x`. The context's CTM must be y-up
    /// here: the classic browser draws inside its text counter-flip, where a rect centred on the
    /// row comes out the same in its unflipped coordinates.
    func draw(_ source: LibraryRowThumbnails.Source, in context: CGContext, at x: CGFloat, rowRect: NSRect,
              side: CGFloat) {
        guard side > 0 else { return }
        let rect = CGRect(x: x, y: rowRect.midY - side / 2, width: side, height: side)
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        if let image = LibraryRowThumbnails.shared.thumbnail(for: source) {
            context.interpolationQuality = .high
            context.draw(image, in: rect)
        } else {
            context.setFillColor(placeholder.cgColor)
            context.fill(rect)
        }
        context.restoreGState()
        drawn.append((rect, source))
    }

    /// Show the preview of the thumbnail under `point`, or hide it when there is none. `point` and
    /// the drawn rects share the browser's drawing coordinates; `toScreen` maps a rect from them.
    func hover(at point: CGPoint, toScreen: (CGRect) -> NSRect) {
        let preview = LibraryRowThumbnails.shared.preview
        guard let hit = drawn.last(where: { $0.rect.contains(point) }) else {
            preview.hide()
            return
        }
        preview.show(hit.source, anchor: toScreen(hit.rect))
    }
}
