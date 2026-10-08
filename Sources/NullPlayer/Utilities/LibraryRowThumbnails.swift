import AppKit
import AVFoundation

/// Round images for library list rows — album/artist/track/video art, radio station icons,
/// YouTube video thumbnails and channel avatars — shared by both library browsers.
///
/// One load makes both renditions of a row's art (`Renditions`): the round row thumbnail and the
/// hover preview. They are written to `RowThumbnailDiskCache`, which is read before any loader
/// runs, so a relaunch draws from disk. `thumbnail(for:)` only reads the cache; after each list
/// pass the browser calls `request` with every row it wants, which replaces the queue. When a
/// load lands, `didLoadNotification` is posted so the browser redraws.
@MainActor
final class LibraryRowThumbnails {
    static let shared = LibraryRowThumbnails()
    static let didLoadNotification = Notification.Name("LibraryRowThumbnailDidLoad")

    private static let maxConcurrentLoads = 4

    /// Where a row's art comes from, and the key both renditions are cached under. The key
    /// outlives the session on disk, so it names the image, not the row. A row kind that carries
    /// art always gets a source, even without art, so its circle keeps the placeholder and its
    /// title stays aligned with its neighbours'.
    struct Source {
        let key: String
        let load: () async -> NSImage?
        /// The view `load` calls into, if any. Once it is gone, a nil from `load` means the loader
        /// went away, not that the row has no art.
        private weak var owner: AnyObject?
        private let hasOwner: Bool

        init(key: String, owner: AnyObject? = nil, load: @escaping () async -> NSImage?) {
            self.key = key
            self.load = load
            self.owner = owner
            hasOwner = owner != nil
        }

        var isOrphaned: Bool { hasOwner && owner == nil }

        /// A browser item through the browser's own loader. `key` is `itemArtwork`'s
        /// `<service>:<id>`, scoped to `server` because ids repeat across servers (Plex rating keys
        /// are small integers).
        static func item(key: String, server: String?, owner: AnyObject,
                         load: @escaping () async -> NSImage?) -> Source {
            Source(key: server.map { "\($0)/\(key)" } ?? key, owner: owner, load: load)
        }

        /// One fetch at preview size; the thumbnail is cut from it.
        static func channel(_ channel: YouTubeChannel) -> Source {
            guard let url = channel.avatarURL(side: 320) else { return Source(key: "channel:\(channel.id)", load: { nil }) }
            return remote(url)
        }

        static func video(_ video: YouTubeVideo) -> Source { remote(video.rowThumbnailURL) }

        static func radio(_ station: RadioStation) -> Source {
            guard let url = station.iconURL else { return Source(key: "radio:\(station.id)", load: { nil }) }
            return remote(url)
        }

        /// A file's embedded art; a stream URL keeps the placeholder.
        static func localFile(_ url: URL) -> Source {
            guard url.isFileURL else { return Source(key: "stream:\(url.absoluteString)", load: { nil }) }
            return Source(key: "local:\(url.path)", load: {
                guard let metadata = try? await AVURLAsset(url: url).load(.metadata) else { return nil }
                for item in metadata where item.commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue), let image = NSImage(data: data) { return image }
                }
                return nil
            })
        }

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
    /// What the latest list pass wants that is not loaded or loading yet, highest priority first.
    private var pending: [Source] = []
    private var inFlight: [String: Task<Renditions?, Never>] = [:]
    /// Keys whose load failed or found no art — not retried this session.
    private var failed: Set<String> = []
    private var didLoadPostScheduled = false

    private init() {
        let diskCache = diskCache
        Task.detached(priority: .background) { diskCache.prune() }
    }

    /// The row thumbnail, or nil while it is wanted or loading, or when the row has no art.
    func thumbnail(for source: Source) -> CGImage? {
        thumbnails.object(forKey: source.key as NSString)?.image
    }

    /// The preview if memory holds it; `previewImage(for:)` also reads disk.
    func cachedPreview(for source: Source) -> CGImage? {
        previews.object(forKey: source.key as NSString)?.image
    }

    /// True once `source` has loaded: both renditions are stored together, so `previewImage(for:)`
    /// reads the preview back from memory or disk instead of starting a load past the queue.
    func hasLoaded(_ source: Source) -> Bool {
        thumbnails.object(forKey: source.key as NSString) != nil
    }

    /// Replace the queue with `sources`, highest priority first: one list pass's rows on screen,
    /// then the rows around them. Rows a scroll has left behind drop out on the next pass.
    func request(_ sources: [Source]) {
        var queued: Set<String> = []
        pending = sources.filter { needsLoad($0) && queued.insert($0.key).inserted }
        startPendingLoads()
    }

    private func needsLoad(_ source: Source) -> Bool {
        let key = source.key
        return thumbnails.object(forKey: key as NSString) == nil && inFlight[key] == nil
            && !failed.contains(key) && !source.isOrphaned
    }

    /// Two screens of rows either side of `visible`, nearest first, alternating below and above.
    nonisolated static func preloadOrder(around visible: Range<Int>, count: Int) -> [Int] {
        let span = max(visible.count, 10) * 2
        return (0..<span)
            .flatMap { [visible.upperBound + $0, visible.lowerBound - 1 - $0] }
            .filter { (0..<count).contains($0) }
    }

    /// The hover preview: memory, then disk, then the row's own load, started now.
    func previewImage(for source: Source) async -> CGImage? {
        let key = source.key
        if let cached = previews.object(forKey: key as NSString) { return cached.image }
        guard !failed.contains(key) else { return nil }
        let diskCache = diskCache
        if let preview = await Task.detached(priority: .userInitiated, operation: { diskCache.readPreview(key) }).value {
            cachePreview(preview, key: key)
            return preview
        }
        return await startLoad(source).value?.preview
    }

    private func cachePreview(_ preview: CGImage, key: String) {
        previews.setObject(ImageBox(preview), forKey: key as NSString, cost: preview.bytesPerRow * preview.height)
    }

    private func startPendingLoads() {
        while inFlight.count < Self.maxConcurrentLoads, !pending.isEmpty {
            let next = pending.removeFirst()
            // A preview may have loaded it since the pass, or its browser may have gone.
            if needsLoad(next) { startLoad(next) }
        }
    }

    /// Load `source` once, store the result, and start whatever is queued next. A second caller
    /// for the same key gets the running task.
    @discardableResult
    private func startLoad(_ source: Source) -> Task<Renditions?, Never> {
        let key = source.key
        if let running = inFlight[key] { return running }
        let task = Task {
            let renditions = await self.load(source)
            self.inFlight[key] = nil
            if let renditions {
                self.thumbnails.setObject(ImageBox(renditions.thumbnail), forKey: key as NSString)
                self.cachePreview(renditions.preview, key: key)
                self.postDidLoad()
            } else if !source.isOrphaned {
                // An orphan's nil says its browser went away; the next browser asks again.
                self.failed.insert(key)
            }
            self.startPendingLoads()
            return renditions
        }
        inFlight[key] = task
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
/// cache, and where it landed is kept so a mouse position can show that row's preview. The
/// browser's only contact with row thumbnails: `beginPass`, `draw`, `endPass`, `hover`.
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

    /// End a list pass: load the rows just drawn, then the rows around `visible`. `source` maps a
    /// row index to its art.
    func endPass(visible: Range<Int>, count: Int, source: (Int) -> LibraryRowThumbnails.Source?) {
        let preload = LibraryRowThumbnails.preloadOrder(around: visible, count: count).compactMap(source)
        LibraryRowThumbnails.shared.request(drawn.map(\.source) + preload)
    }

    /// Draw `source` round, centred vertically in `rowRect` at `x`, and return how far a title
    /// after it moves right. The context's CTM must be y-up here: the classic browser draws inside
    /// its text counter-flip, where a rect centred on the row comes out the same in its unflipped
    /// coordinates.
    @discardableResult
    func draw(_ source: LibraryRowThumbnails.Source, in context: CGContext, at x: CGFloat, rowRect: NSRect,
              side: CGFloat) -> CGFloat {
        guard side > 0 else { return 0 }
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
        return side + 4
    }

    /// Show the preview of the thumbnail under `point`, or hide it when there is none or `point`
    /// is nil (the mouse is off the list). `point` and the drawn rects share the browser's drawing
    /// coordinates; `toScreen` maps a rect from them, or returns nil without a window.
    func hover(at point: CGPoint?, toScreen: (CGRect) -> NSRect?) {
        guard let point, let hit = drawn.last(where: { $0.rect.contains(point) }),
              let anchor = toScreen(hit.rect) else {
            RowThumbnailPreview.shared.hide()
            return
        }
        RowThumbnailPreview.shared.show(hit.source, anchor: anchor)
    }
}
