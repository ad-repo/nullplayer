import AppKit

/// Small square images for YouTube list rows — video thumbnails and channel avatars — shared
/// by both library browsers. `image(for:)` returns a cached image or starts a fetch and returns
/// nil; when a fetch lands, `didLoadNotification` is posted so the browser redraws.
@MainActor
final class YouTubeRowThumbnails {
    static let shared = YouTubeRowThumbnails()
    static let didLoadNotification = Notification.Name("YouTubeRowThumbnailDidLoad")

    /// Pixel side of a cached thumbnail: a row is ~18 pt, so this covers 2x with headroom.
    nonisolated private static let pixelSide = 64

    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let cache: NSCache<NSURL, Entry> = {
        let cache = NSCache<NSURL, Entry>()
        cache.countLimit = 1000
        return cache
    }()
    private var inFlight: Set<URL> = []
    /// URLs that failed once (404, not an image) — not retried this session.
    private var failed: Set<URL> = []

    private init() {}

    private func image(for url: URL) -> CGImage? {
        if let entry = cache.object(forKey: url as NSURL) { return entry.image }
        guard !inFlight.contains(url), !failed.contains(url) else { return nil }
        inFlight.insert(url)
        Task { [weak self] in
            let image = await Self.fetch(url)
            guard let self else { return }
            self.inFlight.remove(url)
            guard let image else { self.failed.insert(url); return }
            self.cache.setObject(Entry(image), forKey: url as NSURL)
            NotificationCenter.default.post(name: Self.didLoadNotification, object: self)
        }
        return nil
    }

    nonisolated private static func fetch(_ url: URL) async -> CGImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let source = NSImage(data: data)?.squareCenterCropped(),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Downscale once here so drawing a list of them stays cheap.
        let side = min(pixelSide, cgImage.width)
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cgImage }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage() ?? cgImage
    }

    /// Draw a channel's avatar, clipped round, once it has loaded (nothing until then).
    func draw(channel: YouTubeChannel, in context: CGContext, at x: CGFloat, rowRect: NSRect, side: CGFloat) {
        guard let url = channel.avatarURL(side: 88) else { return }
        draw(url, in: context, at: x, rowRect: rowRect, side: side) { CGPath(ellipseIn: $0, transform: nil) }
    }

    /// Draw a video's thumbnail with slightly rounded corners once it has loaded.
    func draw(video: YouTubeVideo, in context: CGContext, at x: CGFloat, rowRect: NSRect, side: CGFloat) {
        draw(video.rowThumbnailURL, in: context, at: x, rowRect: rowRect, side: side) {
            CGPath(roundedRect: $0, cornerWidth: 2, cornerHeight: 2, transform: nil)
        }
    }

    /// Draw a row thumbnail centred vertically in `rowRect` at `x`. The context's CTM must be
    /// y-up at this point (the classic browser draws it inside its text counter-flip).
    private func draw(_ url: URL, in context: CGContext, at x: CGFloat, rowRect: NSRect, side: CGFloat,
                      clip: (CGRect) -> CGPath) {
        guard let image = image(for: url) else { return }
        let rect = CGRect(x: x, y: rowRect.midY - side / 2, width: side, height: side)
        context.saveGState()
        context.addPath(clip(rect))
        context.clip()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
    }
}
