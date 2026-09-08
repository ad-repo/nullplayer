import CoreGraphics
import Foundation
import ImageIO

struct WMPImageStoreLimits: Equatable {
    var maximumDimension = WMPPhase0Limits.imageDimension
    var maximumPixels = WMPPhase0Limits.imagePixels
    var maximumDecodedBytes = WMPPhase0Limits.imagePixels * 4
    var cacheBytes = 64 * 1024 * 1024

    static let production = WMPImageStoreLimits()
}

struct WMPImageStoreMetrics: Hashable, Codable {
    let cachedImageCount: Int
    let currentCacheBytes: Int
    let peakCacheBytes: Int
    let decodedImageCount: Int
    let evictionCount: Int
    let cachedMappingImageCount: Int
    let currentMappingBytes: Int
    let decodedMappingImageCount: Int
}

struct WMPDecodedImage {
    let image: CGImage
    let size: WMPSize
    let decodedBytes: Int
}

/// A multi-frame GIF's timing. **90 of the 180 corpus archives carry one** — 2,166 files, most of
/// them three to six frames — so an engine that draws frame zero forever is showing half the corpus
/// a still of something the skin animates.
struct WMPImageAnimation: Hashable, Codable {
    /// Per-frame delays in seconds, in authored order.
    let delays: [TimeInterval]
    /// How many times the GIF asked to be played: `0` is forever, `n > 0` plays `n` times and then
    /// **holds the last frame**.
    ///
    /// A GIF says this in the NETSCAPE2.0 application extension, and a one-shot animation is one
    /// that omits it — which ImageIO reports as `LoopCount = 1`. Looping regardless is what made
    /// `Halo 2` unusable: its 34-frame `m_shutter_open.gif` opens the shutter over the player's
    /// face, holds it open in WMP, and here slammed shut and re-opened every 3.4 seconds forever —
    /// reported on 2026-09-08 as "the shutter closes after it opens". The corpus authors both
    /// kinds: `m_shutter_open.gif` and `m_logo_hov.gif` are `1`, `seek_text_hov.gif` and ALXMorph's
    /// 61-frame `m_anim_coolant.gif` are `0`.
    let loopCount: Int

    var frameCount: Int { delays.count }
    var duration: TimeInterval { delays.reduce(0, +) }
    /// When the animation stops moving, or `nil` while it never does.
    var endOfPlayback: TimeInterval? { loopCount > 0 ? duration * TimeInterval(loopCount) : nil }

    init(delays: [TimeInterval], loopCount: Int = 0) {
        self.delays = delays
        self.loopCount = max(0, loopCount)
    }

    /// The frame showing at `clock` seconds in. A zero-duration animation — every delay unreadable
    /// — holds on frame zero rather than dividing by it, and a finished one holds its last frame.
    func frameIndex(at clock: TimeInterval) -> Int {
        guard frameCount > 1, duration > 0, clock.isFinite else { return 0 }
        if let end = endOfPlayback, clock >= end { return frameCount - 1 }
        var remaining = clock.truncatingRemainder(dividingBy: duration)
        if remaining < 0 { remaining += duration }
        for (index, delay) in delays.enumerated() {
            remaining -= delay
            if remaining < 0 { return index }
        }
        return frameCount - 1
    }
}

/// A lock-protected LRU whose keys include the color key. The retained graph never owns CGImage or
/// cache state. Callers use this store only from WMP background work.
final class WMPImageStore: @unchecked Sendable {
    private struct Entry {
        let image: WMPDecodedImage
        var access: UInt64
    }
    private struct MappingEntry {
        let mapping: WMPMappingImage
        var access: UInt64
    }
    private struct PositionEntry {
        let map: WMPPositionMap
        var access: UInt64
    }
    private struct ClipEntry {
        let mask: CGImage
        let bytes: Int
        var access: UInt64
    }

    private let provider: WMPResourceProviding
    private let limits: WMPImageStoreLimits
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    private var currentBytes = 0
    private var peakBytes = 0
    private var decodeCount = 0
    private var evictions = 0
    private var mappingEntries: [String: MappingEntry] = [:]
    private var mappingBytes = 0
    private var mappingDecodeCount = 0
    private var positionEntries: [String: PositionEntry] = [:]
    private var positionBytes = 0
    private var clipEntries: [String: ClipEntry] = [:]
    private var clipBytes = 0
    /// `.some(nil)` is "checked, not animated" — a still must not be re-probed on every frame.
    private var animationEntries: [String: WMPImageAnimation??] = [:]

    init(provider: WMPResourceProviding, limits: WMPImageStoreLimits = .production) {
        self.provider = provider
        self.limits = limits
    }

    func image(for path: String, colorKey: WMPColor?) throws -> WMPDecodedImage {
        try image(for: path, colorKeys: colorKey.map { [$0] } ?? [])
    }

    /// `implicitKey` is the colour WMP keys out of a sprite whose node declares none of its own,
    /// whatever alpha the file carries (W78a). Passing it is the caller saying "this is drawn
    /// artwork": a mapping image, position map or clipping mask must never receive one, or a
    /// `#FF00FF` mapping colour would vanish from its own map.
    func image(for path: String, colorKeys: [WMPColor] = [],
               implicitKey: WMPColor? = nil) throws -> WMPDecodedImage {
        try image(for: path, colorKeys: colorKeys, implicitKey: implicitKey, frameSuffix: 0)
    }

    private func image(for path: String, colorKeys: [WMPColor], implicitKey: WMPColor? = nil,
                       frameSuffix frame: Int) throws -> WMPDecodedImage {
        let canonical = provider.canonicalPath(for: path) ?? path
        let cacheKey = canonical + colorKeys.map { "|key=\($0)" }.joined()
            + (implicitKey.map { "|implicit=\($0)" } ?? "")
            + (frame > 0 ? "|frame=\(frame)" : "")
        lock.lock()
        if var entry = entries[cacheKey] {
            clock &+= 1
            entry.access = clock
            entries[cacheKey] = entry
            lock.unlock()
            return entry.image
        }
        lock.unlock()

        let decoded = try decode(path: canonical, colorKeys: colorKeys,
                                 implicitKey: implicitKey, frame: frame)
        lock.lock()
        defer { lock.unlock() }
        if let existing = entries[cacheKey] { return existing.image }
        decodeCount += 1
        guard decoded.decodedBytes <= limits.cacheBytes else { return decoded }
        while currentBytes + decoded.decodedBytes > limits.cacheBytes,
              let victim = entries.min(by: { $0.value.access < $1.value.access }) {
            currentBytes -= victim.value.image.decodedBytes
            entries.removeValue(forKey: victim.key)
            evictions += 1
        }
        clock &+= 1
        entries[cacheKey] = Entry(image: decoded, access: clock)
        currentBytes += decoded.decodedBytes
        peakBytes = max(peakBytes, currentBytes)
        return decoded
    }

    func removeAll() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        currentBytes = 0
        mappingEntries.removeAll(keepingCapacity: false)
        mappingBytes = 0
        positionEntries.removeAll(keepingCapacity: false)
        positionBytes = 0
        clipEntries.removeAll(keepingCapacity: false)
        clipBytes = 0
        animationEntries.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    func mappingImage(for path: String, nodeByColor: [WMPColor: Int]) throws -> WMPMappingImage {
        let canonical = provider.canonicalPath(for: path) ?? path
        let assignments = nodeByColor.sorted { lhs, rhs in
            lhs.key.description == rhs.key.description ? lhs.value < rhs.value
                : lhs.key.description < rhs.key.description
        }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let key = "\(canonical)|map=\(assignments)"
        lock.lock()
        if var entry = mappingEntries[key] {
            clock &+= 1
            entry.access = clock
            mappingEntries[key] = entry
            lock.unlock()
            return entry.mapping
        }
        lock.unlock()

        let mapping = try WMPMappingImage(image: image(for: canonical).image, nodeByColor: nodeByColor)
        lock.lock()
        defer { lock.unlock() }
        if let existing = mappingEntries[key] { return existing.mapping }
        mappingDecodeCount += 1
        guard mapping.decodedBytes <= limits.cacheBytes else { return mapping }
        while mappingBytes + mapping.decodedBytes > limits.cacheBytes,
              let victim = mappingEntries.min(by: { $0.value.access < $1.value.access }) {
            mappingBytes -= victim.value.mapping.decodedBytes
            mappingEntries.removeValue(forKey: victim.key)
        }
        clock &+= 1
        mappingEntries[key] = MappingEntry(mapping: mapping, access: clock)
        mappingBytes += mapping.decodedBytes
        return mapping
    }

    /// The frame timing of an animated image, or nil when it has one frame.
    ///
    /// GIF delays are authored in hundredths of a second and browsers have taught authors that
    /// 0 and 0.01 mean "as fast as possible", which in practice is about 10 fps — so both are
    /// clamped to 0.1 rather than spinning the render loop for a skin that asked for 100 fps.
    func animation(for path: String) throws -> WMPImageAnimation? {
        let canonical = provider.canonicalPath(for: path) ?? path
        lock.lock()
        if let cached = animationEntries[canonical] { lock.unlock(); return cached.flatMap { $0 } }
        lock.unlock()

        guard (canonical as NSString).pathExtension.lowercased() == "gif" else {
            lock.lock(); animationEntries[canonical] = .some(nil); lock.unlock()
            return nil
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(try provider.data(for: canonical) as CFData, options) else {
            lock.lock(); animationEntries[canonical] = .some(nil); lock.unlock()
            return nil
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1, count <= WMPPhase0Limits.animationFrames else {
            lock.lock(); animationEntries[canonical] = .some(nil); lock.unlock()
            return nil
        }
        var delays: [TimeInterval] = []
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            delays.append(unclamped <= 0.011 ? 0.1 : unclamped)
        }
        let properties = CGImageSourceCopyProperties(source, options) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        // Absent means "play once" in the GIF grammar — only the NETSCAPE2.0 extension asks for a
        // loop — and that is what ImageIO's `1` means here as well.
        let loopCount = (gifProperties?[kCGImagePropertyGIFLoopCount] as? Int) ?? 1
        let animation = WMPImageAnimation(delays: delays, loopCount: loopCount)
        lock.lock(); animationEntries[canonical] = .some(animation); lock.unlock()
        return animation
    }

    /// One frame of an animated image, color-keyed and cached exactly like a still.
    func image(for path: String, colorKeys: [WMPColor] = [], implicitKey: WMPColor? = nil,
               frame: Int) throws -> WMPDecodedImage {
        guard frame > 0 else { return try image(for: path, colorKeys: colorKeys, implicitKey: implicitKey) }
        return try image(for: path, colorKeys: colorKeys, implicitKey: implicitKey, frameSuffix: frame)
    }

    /// A `CUSTOMSLIDER`'s greyscale position map, cached under the same byte bound as every other
    /// derived buffer. Keyed by canonical path alone: unlike a mapping image, nothing about the
    /// node changes what the map decodes to.
    func positionMap(for path: String) throws -> WMPPositionMap {
        let canonical = provider.canonicalPath(for: path) ?? path
        lock.lock()
        if var entry = positionEntries[canonical] {
            clock &+= 1
            entry.access = clock
            positionEntries[canonical] = entry
            lock.unlock()
            return entry.map
        }
        lock.unlock()

        let map = try WMPPositionMap(image: image(for: canonical).image)
        lock.lock()
        defer { lock.unlock() }
        if let existing = positionEntries[canonical] { return existing.map }
        guard map.decodedBytes <= limits.cacheBytes else { return map }
        while positionBytes + map.decodedBytes > limits.cacheBytes,
              let victim = positionEntries.min(by: { $0.value.access < $1.value.access }) {
            positionBytes -= victim.value.map.decodedBytes
            positionEntries.removeValue(forKey: victim.key)
        }
        clock &+= 1
        positionEntries[canonical] = PositionEntry(map: map, access: clock)
        positionBytes += map.decodedBytes
        return map
    }

    /// A `clippingImage` as an alpha mask: opaque where the artwork shows through, transparent
    /// where it is cut away.
    ///
    /// WMP shapes an element by its clipping image's *own* transparency, and by `clippingColor`
    /// where one is declared — 25 corpus skins author a non-empty `clippingImage` and every one of
    /// them also declares a `clippingColor`. A `CGImage` mask wants "keep" as opaque, so the two
    /// tests are combined into one alpha channel here rather than at every draw.
    func clippingMask(for path: String, keyedOut: [WMPColor]) throws -> CGImage {
        let canonical = provider.canonicalPath(for: path) ?? path
        let keys = keyedOut.map(\.description).joined(separator: ",")
        let key = "\(canonical)|clip=\(keys)"
        lock.lock()
        if var entry = clipEntries[key] {
            clock &+= 1
            entry.access = clock
            clipEntries[key] = entry
            lock.unlock()
            return entry.mask
        }
        lock.unlock()

        let source = try image(for: canonical).image
        let mask = try Self.makeClippingMask(from: source, keyedOut: keyedOut)
        let bytes = mask.width * mask.height
        lock.lock()
        defer { lock.unlock() }
        if let existing = clipEntries[key] { return existing.mask }
        guard bytes <= limits.cacheBytes else { return mask }
        while clipBytes + bytes > limits.cacheBytes,
              let victim = clipEntries.min(by: { $0.value.access < $1.value.access }) {
            clipBytes -= victim.value.bytes
            clipEntries.removeValue(forKey: victim.key)
        }
        clock &+= 1
        clipEntries[key] = ClipEntry(mask: mask, bytes: bytes, access: clock)
        clipBytes += bytes
        return mask
    }

    private static func makeClippingMask(from image: CGImage, keyedOut: [WMPColor]) throws -> CGImage {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else {
            throw WMPFailure(WMPDiagnostic(.renderFailed, "Clipping image has no pixels."))
        }
        var source = [UInt8](repeating: 0, count: width * height * 4)
        source.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var alpha = [UInt8](repeating: 0, count: width * height)
        // Row zero is the authored **top** row: drawing a CGImage into a bitmap context copies it
        // that way round, and `WMPMappingImage` says so in as many words. Flipping the rows here
        // "to correct for CoreGraphics" mirrors the mask and clips the half it should keep — which
        // is W47 arriving by a second route, and is what the top/bottom fixture below caught.
        for y in 0..<height {
            let sourceRow = y * width * 4
            for x in 0..<width {
                let offset = sourceRow + x * 4
                let a = source[offset + 3]
                guard a > 0 else { continue }
                let scale = Double(a) / 255
                let red = UInt8(max(0, min(255, Double(source[offset]) / scale)))
                let green = UInt8(max(0, min(255, Double(source[offset + 1]) / scale)))
                let blue = UInt8(max(0, min(255, Double(source[offset + 2]) / scale)))
                let keyed = keyedOut.contains { $0.red == red && $0.green == green && $0.blue == blue }
                alpha[y * width + x] = keyed ? 0 : 255
            }
        }
        // A **grayscale image**, not a `CGImage` image mask: `clip(to:mask:)` reads the two
        // oppositely — an image mask paints where its samples are 0 — and 255-means-keep is the
        // convention `WMPMappingImage.maskImage` already established, so the two mask paths in this
        // engine must not disagree. Getting this backwards keeps exactly the half it should cut.
        guard let provider = CGDataProvider(data: Data(alpha) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let mask = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw WMPFailure(WMPDiagnostic(.renderFailed, "Unable to build a clipping mask."))
        }
        return mask
    }

    var metrics: WMPImageStoreMetrics {
        lock.lock()
        defer { lock.unlock() }
        return WMPImageStoreMetrics(cachedImageCount: entries.count,
            currentCacheBytes: currentBytes, peakCacheBytes: peakBytes,
            decodedImageCount: decodeCount, evictionCount: evictions,
            cachedMappingImageCount: mappingEntries.count, currentMappingBytes: mappingBytes,
            decodedMappingImageCount: mappingDecodeCount)
    }

    private func decode(path: String, colorKeys: [WMPColor], implicitKey: WMPColor? = nil,
                        frame: Int = 0) throws -> WMPDecodedImage {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ["bmp", "gif", "jpg", "jpeg", "png"].contains(ext) else {
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "Image '\(path)' is not BMP, GIF, JPEG, or PNG."))
        }
        let bytes = try provider.data(for: path)
        let data = bytes as CFData
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = integer(properties[kCGImagePropertyPixelWidth]),
              let height = integer(properties[kCGImagePropertyPixelHeight]) else {
            if ext == "bmp" {
                return try decodeBitmapOurselves(bytes, path: path, colorKeys: colorKeys,
                    implicitKey: implicitKey, imageIOReason: "could not read metadata")
            }
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "ImageIO could not read metadata for '\(path)'."))
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        let (decodedByteCount, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, width <= limits.maximumDimension,
              height <= limits.maximumDimension, !overflow, pixels <= limits.maximumPixels,
              !byteOverflow, decodedByteCount <= limits.maximumDecodedBytes else {
            throw WMPFailure(WMPDiagnostic(.oversizedImage,
                "Image '\(path)' declares \(width)x\(height), beyond the decoded image limit."))
        }
        let decodeOptions = [kCGImageSourceShouldCacheImmediately: true,
                             kCGImageSourceShouldCache: true] as CFDictionary
        // A GIF's later frames are commonly authored as a *partial* update over the one before —
        // ImageIO returns the composited frame at an index, which is what a skin means by "frame n".
        let frameIndex = min(max(0, frame), CGImageSourceGetCount(source) - 1)
        guard var image = CGImageSourceCreateImageAtIndex(source, frameIndex, decodeOptions) else {
            if ext == "bmp" {
                return try decodeBitmapOurselves(bytes, path: path, colorKeys: colorKeys,
                    implicitKey: implicitKey, imageIOReason: "could not decode")
            }
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "ImageIO could not decode '\(path)'."))
        }
        image = try WMPColorKey.applying(keys(colorKeys, implicitKey: implicitKey), to: image)
        return WMPDecodedImage(image: image,
            size: WMPSize(width: CGFloat(width), height: CGFloat(height)),
            decodedBytes: decodedByteCount)
    }

    /// ImageIO refuses legacy WMP bitmaps over details Windows treats as advisory — `biClrImportant`
    /// set while `biClrUsed` is zero, and some well-formed RLE8 streams. Those files are not corrupt
    /// and every Windows player draws them, so fall back to the bounded in-house reader.
    private func decodeBitmapOurselves(_ data: Data, path: String, colorKeys: [WMPColor],
                                       implicitKey: WMPColor? = nil,
                                       imageIOReason: String) throws -> WMPDecodedImage {
        let bounds = WMPBitmapDecoder.Limits(maximumDimension: limits.maximumDimension,
            maximumPixels: limits.maximumPixels, maximumDecodedBytes: limits.maximumDecodedBytes)
        do {
            let decoded = try WMPBitmapDecoder.decode(data, limits: bounds)
            var image = decoded.image
            image = try WMPColorKey.applying(keys(colorKeys, implicitKey: implicitKey), to: image)
            return WMPDecodedImage(image: image,
                size: WMPSize(width: CGFloat(decoded.width), height: CGFloat(decoded.height)),
                decodedBytes: decoded.decodedBytes)
        } catch WMPBitmapDecoder.Failure.oversized(let size) {
            throw WMPFailure(WMPDiagnostic(.oversizedImage,
                "Image '\(path)' declares \(size), beyond the decoded image limit."))
        } catch let failure as WMPBitmapDecoder.Failure {
            guard case .unsupported(let reason) = failure else { throw failure }
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "ImageIO \(imageIOReason) '\(path)', and the BMP reader could not either: \(reason)."))
        }
    }

    /// The declared keys, or the implicit one when the node declared none. The sprite's own alpha
    /// channel does **not** veto it: see `WMPColorKey.implicitTransparency` for what the corpus
    /// says about an alpha-carrying sprite that also holds the key colour (W78a).
    private func keys(_ colorKeys: [WMPColor], implicitKey: WMPColor?) -> [WMPColor] {
        guard colorKeys.isEmpty, let implicitKey else { return colorKeys }
        return [implicitKey]
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
