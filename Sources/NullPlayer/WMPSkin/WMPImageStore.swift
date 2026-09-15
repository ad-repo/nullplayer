import Accelerate
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

/// The images WMP supplies to skins rather than reads from their archive. These names are a closed
/// compatibility surface: an arbitrary `WMPImage_*` spelling is still a missing skin resource.
enum WMPBuiltInImage: String, CaseIterable {
    case albumArtLarge = "WMPImage_AlbumArtLarge"
    case albumArtSmall = "WMPImage_AlbumArtSmall"

    var pixelSize: Int {
        switch self {
        case .albumArtLarge: return 200
        case .albumArtSmall: return 75
        }
    }

    static func named(_ value: String) -> WMPBuiltInImage? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
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

    /// **The animation ends by drawing nothing**, because its final frame is the *terminator*
    /// idiom: a degenerate image block — one or two pixels — whose disposal method is
    /// `restore to background`. See `WMPGIFTerminator`.
    let clearsWhenFinished: Bool

    var frameCount: Int { delays.count }
    var duration: TimeInterval { delays.reduce(0, +) }
    /// When the animation stops moving, or `nil` while it never does.
    var endOfPlayback: TimeInterval? { loopCount > 0 ? duration * TimeInterval(loopCount) : nil }

    init(delays: [TimeInterval], loopCount: Int = 0, clearsWhenFinished: Bool = false) {
        self.delays = delays
        self.loopCount = max(0, loopCount)
        self.clearsWhenFinished = clearsWhenFinished
    }

    /// Whether the element has nothing left to draw at `clock`. Only a finite animation can reach
    /// it — an endless one has no end to hold.
    func isCleared(at clock: TimeInterval) -> Bool {
        guard clearsWhenFinished, let end = endOfPlayback, clock.isFinite else { return false }
        return clock >= end
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
    private var regionShapeEntries: [String: Bool] = [:]
    private var shapeMaskEntries: [String: Bool] = [:]
    /// One `WMPColor?` per bitmap for `cornerColor`; smaller than a decoded frame, so never evicted.
    private var cornerColorEntries: [String: WMPColor?] = [:]
    /// `filmstripIsDescending` answers, keyed by path, frame count and axis. One bool each:
    /// no eviction, because the whole map is smaller than one decoded frame.
    private var descendingStripEntries: [String: Bool] = [:]
    /// `.some(nil)` is "checked, not animated" — a still must not be re-probed on every frame.
    private var animationEntries: [String: WMPImageAnimation??] = [:]
    /// Artwork belongs to the WMP session, not to the archive. The transparent defaults preserve
    /// WMP's intrinsic built-in-image sizes while a remote source is still loading.
    private var builtInImages: [WMPBuiltInImage: WMPDecodedImage] = Dictionary(
        uniqueKeysWithValues: WMPBuiltInImage.allCases.map { image in
            (image, WMPImageStore.transparentImage(size: image.pixelSize))
        }
    )

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
               implicitKey: WMPColor? = nil, hueShift: Double = 0) throws -> WMPDecodedImage {
        try image(for: path, colorKeys: colorKeys, implicitKey: implicitKey,
                  frameSuffix: 0, hueShift: hueShift)
    }

    private func image(for path: String, colorKeys: [WMPColor], implicitKey: WMPColor? = nil,
                       frameSuffix frame: Int, hueShift: Double = 0) throws -> WMPDecodedImage {
        if let builtIn = WMPBuiltInImage.named(path) {
            lock.lock()
            let image = builtInImages[builtIn]!
            lock.unlock()
            return image
        }
        let degrees = Self.canonicalHueShift(hueShift)
        let canonical = provider.canonicalPath(for: path) ?? path
        let cacheKey = canonical + colorKeys.map { "|key=\($0)" }.joined()
            + (implicitKey.map { "|implicit=\($0)" } ?? "")
            + (frame > 0 ? "|frame=\(frame)" : "")
            + (degrees > 0 ? "|hue=\(degrees)" : "")
        lock.lock()
        if var entry = entries[cacheKey] {
            clock &+= 1
            entry.access = clock
            entries[cacheKey] = entry
            lock.unlock()
            return entry.image
        }
        lock.unlock()

        var decoded = try decode(path: canonical, colorKeys: colorKeys,
                                 implicitKey: implicitKey, frame: frame)
        // The rotation is folded into the decode rather than applied at the draw, so everything
        // downstream — the crop, the Lanczos upscale, the mapping and clipping masks — sees the
        // colour the skin asked for. See `hueRotated`.
        if degrees > 0, let rotated = Self.hueRotated(decoded.image, degrees: degrees) {
            decoded = WMPDecodedImage(image: rotated,
                                      size: decoded.size,
                                      decodedBytes: rotated.width * rotated.height * 4)
        }
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
        regionShapeEntries.removeAll(keepingCapacity: false)
        shapeMaskEntries.removeAll(keepingCapacity: false)
        cornerColorEntries.removeAll(keepingCapacity: false)
        descendingStripEntries.removeAll(keepingCapacity: false)
        clipBytes = 0
        animationEntries.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    /// Replace WMP's in-memory album-art resources from one decoded artwork image. This is called
    /// after the WMP-owned asynchronous artwork load completes; it never asks a skin archive for
    /// data and `WMPImage_AdBanner` intentionally has no entry here.
    func setAlbumArtwork(_ image: CGImage?) {
        lock.lock()
        defer { lock.unlock() }
        for resource in WMPBuiltInImage.allCases {
            builtInImages[resource] = image.map { Self.scaledImage($0, size: resource.pixelSize) }
                ?? Self.transparentImage(size: resource.pixelSize)
        }
    }

    private static func transparentImage(size: Int) -> WMPDecodedImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: size * 4, space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let image = context.makeImage()!
        return WMPDecodedImage(image: image,
                               size: WMPSize(width: CGFloat(size), height: CGFloat(size)),
                               decodedBytes: size * size * 4)
    }

    private static func scaledImage(_ source: CGImage, size: Int) -> WMPDecodedImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: size * 4, space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let scale = min(CGFloat(size) / CGFloat(source.width), CGFloat(size) / CGFloat(source.height))
        let width = CGFloat(source.width) * scale
        let height = CGFloat(source.height) * scale
        context.draw(source, in: CGRect(x: (CGFloat(size) - width) / 2,
                                         y: (CGFloat(size) - height) / 2,
                                         width: width, height: height))
        return WMPDecodedImage(image: context.makeImage()!,
                               size: WMPSize(width: CGFloat(size), height: CGFloat(size)),
                               decodedBytes: size * size * 4)
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
    /// GIF delays are authored in hundredths of a second, and 0, 1 or 2 cs means "as fast as
    /// possible". That still needs a floor — nothing here may spin the repaint loop — but the
    /// floor a **browser** uses for it (0.1s, 10 fps) is not this corpus's answer and was the
    /// largest single cause of "the animations are slow": **768 of the corpus's 2,166 multi-frame
    /// GIFs, across 62 of the 90 skins that animate at all, author a minimum delay of 0 or 1 cs**,
    /// and 625 of those author *nothing else* — every frame is "as fast as possible". Clamping
    /// them to 10 fps stretched `AlienMorph`'s 119-frame shutter to 12 seconds.
    ///
    /// **The floor itself is set by eye, and there is no measurement that can set it** — the file
    /// said "as fast as possible", so every value is a choice about what that should look like.
    /// What the corpus does say is the shape of what it is applied to: **679 of the 768 are
    /// one-shot transitions**, not loops — a shutter opening, a button lighting under the pointer —
    /// so the floor is choosing how long a transition takes, and only one endless GIF in the
    /// corpus is short enough for the rate to read as a flicker (`Creed`'s 3-frame `CloseGates`).
    ///
    /// 0.1s was too slow (`AlienMorph`'s 119-frame shutter took 11.9s, `Blinx`'s 4.7s) and 0.04s
    /// was then reported too fast on sight. 0.0667s is where it sits: the alien shutter runs 9.8s,
    /// `Blinx` 3.1s, a 9-frame hover glow 0.6s. Every duration scales linearly with this number,
    /// so it is the one dial — and it is a judgement, not a finding. Do not "correct" it against
    /// the corpus's authored delays; that argument produced 0.04.
    static let animationFloor: TimeInterval = 0.0667

    /// **What counts as "as fast as possible", and why it is 2 cs rather than a browser's 1.**
    ///
    /// The corpus contains the one experiment that can settle this: the Alienware family ships the
    /// *same shutter animation* authored twice. `AlienMorph`/`AlienwareTeleport` write 108 of their
    /// 119 frames as 0 cs; `ALXMorph`/`ALXVortex` write 134 of their 138 as 2 cs. With the trigger
    /// at 1 cs only the first pair was floored, so one ran 9.8s and the other 3.9s — reported as
    /// "ALXMorph's animation runs so quickly, it is basically the same animation". A 282x282 GIF at
    /// 2 cs is 50 fps, which is "every frame anything will draw" exactly as 0 is; both authors
    /// asked for the same thing and only the spelling differed.
    ///
    /// Measured over the installed corpus by parsing every GIF's Graphic Control Extension blocks
    /// (2,170 multi-frame GIFs across 91 archives): the minimum authored delay is 0 cs for 494,
    /// 1 cs for 278 and **2 cs for 28**, then 3 cs for 62 and 5 cs for 859. So moving the trigger
    /// from 1 to 2 reaches **28 GIFs across 9 archives** and leaves the 772 already floored exactly
    /// where they were — `ALXMorph`/`ALXVortex` to 10.14s against `AlienMorph`'s 9.82s, `Constantine`
    /// and `Plus! Mecha`'s shutters to 2.3s and 1.8s, and eighteen Xbox/QuantumRedshift hover glows
    /// to 0.13–0.40s, which is the median of the cohort the floor was tuned on. 3 cs is deliberately
    /// outside it: 62 GIFs author it as a real rate.
    ///
    /// This is a departure from the browser convention, which floors 1 cs and honours 2. It is
    /// taken on the strength of the A/B above and nothing else, so **re-run that comparison before
    /// moving this number** rather than re-deriving it from authored delays in aggregate.
    static let asFastAsPossibleCentiseconds: TimeInterval = 0.021

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
        let data = try provider.data(for: canonical)
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
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
            delays.append(unclamped <= Self.asFastAsPossibleCentiseconds
                          ? Self.animationFloor : unclamped)
        }
        let properties = CGImageSourceCopyProperties(source, options) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        // Absent means "play once" in the GIF grammar — only the NETSCAPE2.0 extension asks for a
        // loop — and that is what ImageIO's `1` means here as well.
        let loopCount = (gifProperties?[kCGImagePropertyGIFLoopCount] as? Int) ?? 1
        let animation = WMPImageAnimation(delays: delays, loopCount: loopCount,
                                          clearsWhenFinished: WMPGIFTerminator.clearsWhenFinished(data))
        lock.lock(); animationEntries[canonical] = .some(animation); lock.unlock()
        return animation
    }

    /// One frame of an animated image, color-keyed and cached exactly like a still.
    func image(for path: String, colorKeys: [WMPColor] = [], implicitKey: WMPColor? = nil,
               frame: Int, hueShift: Double = 0) throws -> WMPDecodedImage {
        guard frame > 0 else {
            return try image(for: path, colorKeys: colorKeys,
                             implicitKey: implicitKey, hueShift: hueShift)
        }
        return try image(for: path, colorKeys: colorKeys, implicitKey: implicitKey,
                         frameSuffix: frame, hueShift: hueShift)
    }

    /// `hueShift` in degrees, normalised the way the one skin that writes it does.
    ///
    /// **It is degrees, and `Plus! HueShifter` is the authority** — `changeHue()` steps
    /// `360.0 / 11` per press and `savePrefs` clamps to `0…360`, so the ten stops it offers are
    /// 33°, 65°, 98° … 327°. A -1…1 reading would clamp every one of them to the same value and
    /// the button the skin is named after would do nothing visible, which is not what Microsoft
    /// shipped. 0 and 360 are both "no shift" and take the untouched decode.
    static func canonicalHueShift(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return Int((wrapped < 0 ? wrapped + 360 : wrapped).rounded())  % 360
    }

    /// Rotate every pixel's hue by `degrees`, leaving saturation, luminance and **alpha** alone.
    ///
    /// This is what the `hueShift` property means, and one archive in the corpus needs it: the
    /// whole premise of `Plus! HueShifter` is a paintbrush button whose `changeHue()` assigns the
    /// same value to its five "candy" pieces — `topCandy`, `botCandy`, `leftCandy`, `rightCandy`
    /// and `botCandyFacade` — so the ring around the player cycles through the spectrum. Without
    /// it the property write was inert and the candies were frozen at their native green.
    ///
    /// **A luma-preserving matrix, not a round trip through HSB.** Rotating the chroma about the
    /// luma axis is what a hue rotation is defined as, and it keeps the artwork's shading, its
    /// black wedges and its white specular highlight exactly where they were — a grey has no hue
    /// and does not move at any angle. Going via HSB instead would quantise every pixel twice and
    /// drift the greys, which on artwork this soft reads as banding.
    ///
    /// Alpha is untouched and the pixels are un-premultiplied before the matrix and re-premultiplied
    /// after. Rotating premultiplied colour scales the result by its own alpha and fringes every
    /// keyed silhouette — the same trap `unpremultiply` exists for.
    static func hueRotated(_ image: CGImage, degrees: Int) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let radians = Double(degrees) * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        // The SVG/CSS `hue-rotate` matrix: luma column, plus a chroma rotation about it. Using the
        // standard one rather than the NTSC YIQ constants is deliberate — the YIQ form rotates the
        // *other* way (120 degrees takes red to blue, where every other implementation takes it to
        // green) and its blue row has coefficients of 1.25 and -1.05, which drive a saturated pixel
        // far out of gamut and then clamp it, costing the luminance the rotation is supposed to
        // keep. Measured on one flat red: YIQ gave (24, 42, 255), this gives (0, 113, 0).
        let matrix = [
            0.213 + 0.787 * cosine - 0.213 * sine,
            0.715 - 0.715 * cosine - 0.715 * sine,
            0.072 - 0.072 * cosine + 0.928 * sine,
            0.213 - 0.213 * cosine + 0.143 * sine,
            0.715 + 0.285 * cosine + 0.140 * sine,
            0.072 - 0.072 * cosine - 0.283 * sine,
            0.213 - 0.213 * cosine - 0.787 * sine,
            0.715 - 0.715 * cosine + 0.715 * sine,
            0.072 + 0.928 * cosine + 0.072 * sine
        ]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[index + 3]
            guard alpha > 0 else { continue }
            let red = Double(unpremultiply(pixels[index], alpha: alpha))
            let green = Double(unpremultiply(pixels[index + 1], alpha: alpha))
            let blue = Double(unpremultiply(pixels[index + 2], alpha: alpha))
            let out = (
                matrix[0] * red + matrix[1] * green + matrix[2] * blue,
                matrix[3] * red + matrix[4] * green + matrix[5] * blue,
                matrix[6] * red + matrix[7] * green + matrix[8] * blue
            )
            pixels[index] = premultiply(out.0, alpha: alpha)
            pixels[index + 1] = premultiply(out.1, alpha: alpha)
            pixels[index + 2] = premultiply(out.2, alpha: alpha)
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func premultiply(_ value: Double, alpha: UInt8) -> UInt8 {
        let clamped = min(255, max(0, value))
        guard alpha < 255 else { return UInt8(clamped.rounded()) }
        return UInt8(min(255, (clamped * Double(alpha) / 255).rounded()))
    }

    /// Artwork resampled up to the device's own pixel grid, so the renderer can blit it 1:1.
    ///
    /// **This is the only way a 1x `.wmz` gets crisp edges on a 2x display.** CoreGraphics offers
    /// bilinear (`.low`/`.high`, which are byte-identical on the draw path) and nearest (`.none`);
    /// the first blurs the artwork and the second blocks it, and a reporter looking at
    /// `Plus! Hard Boiled` rejected both. Lanczos reconstructs an edge instead of smearing or
    /// replicating it, and a light luminance sharpen restores the acutance the resample costs.
    /// `CISharpenLuminance` is chosen over `CIUnsharpMask` deliberately: it leaves alpha alone, so a
    /// keyed silhouette cannot grow a ringing halo.
    ///
    /// **The caller crops before it scales, never after.** Lanczos reads a ~3px neighbourhood, so
    /// upscaling a filmstrip whole would bleed each sprite into the one beside it — a volume slider
    /// picking up a sliver of the next frame. `sourceRect` is therefore part of the key.
    ///
    /// Cached in the same LRU and under the same byte bound as every decoded image, because that is
    /// what keeps a skin that animates from running Core Image at its repaint cadence.
    func upscaledImage(for path: String, colorKeys: [WMPColor] = [], implicitKey: WMPColor? = nil,
                       frame: Int = 0, sourceRect: WMPRect?, scale: Int,
                       hueShift: Double = 0) throws -> WMPDecodedImage {
        let base = try image(for: path, colorKeys: colorKeys, implicitKey: implicitKey,
                             frame: frame, hueShift: hueShift)
        let cropped = Self.crop(sourceRect, from: base.image)
        guard scale > 1 else {
            return WMPDecodedImage(image: cropped,
                                   size: WMPSize(width: CGFloat(cropped.width),
                                                 height: CGFloat(cropped.height)),
                                   decodedBytes: cropped.width * cropped.height * 4)
        }
        let canonical = provider.canonicalPath(for: path) ?? path
        var cacheKey = canonical
        cacheKey += colorKeys.map { "|key=\($0)" }.joined()
        if let implicitKey { cacheKey += "|implicit=\(implicitKey)" }
        if frame > 0 { cacheKey += "|frame=\(frame)" }
        if let sourceRect {
            cacheKey += "|crop=\(sourceRect.x),\(sourceRect.y)"
            cacheKey += ",\(sourceRect.width)x\(sourceRect.height)"
        }
        cacheKey += "|up=\(scale)"
        // The rotation happens before the resample, so the upscale of a shifted sprite is its own
        // entry — two candies at different hues must not share one cached bitmap.
        let degrees = Self.canonicalHueShift(hueShift)
        if degrees > 0 { cacheKey += "|hue=\(degrees)" }
        lock.lock()
        if var entry = entries[cacheKey] {
            clock &+= 1
            entry.access = clock
            entries[cacheKey] = entry
            lock.unlock()
            return entry.image
        }
        lock.unlock()

        // Past the renderer's own ceiling there is nothing to gain and a throw to lose: hand back
        // the unscaled bitmap and let the draw filter it as it always did.
        let pixels = UInt64(cropped.width * cropped.height) * UInt64(scale * scale)
        guard pixels <= WMPPhase0Limits.imagePixels,
              let scaled = Self.lanczosUpscale(cropped, scale: scale) else {
            return WMPDecodedImage(image: cropped,
                                   size: WMPSize(width: CGFloat(cropped.width),
                                                 height: CGFloat(cropped.height)),
                                   decodedBytes: cropped.width * cropped.height * 4)
        }
        let decoded = WMPDecodedImage(image: scaled,
                                      size: WMPSize(width: CGFloat(scaled.width),
                                                    height: CGFloat(scaled.height)),
                                      decodedBytes: scaled.width * scaled.height * 4)
        lock.lock()
        defer { lock.unlock() }
        if let existing = entries[cacheKey] { return existing.image }
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

    /// How hard the post-resample sharpen bites, over `sharpenDivisor`. The effective amount is
    /// `sharpenStrength / sharpenDivisor` per neighbour, so 6/16 is a light touch.
    ///
    /// **This is the number that has to stay small.** The first version wrote the kernel with a
    /// divisor of 1, which is an amount of *four*, and the reporter's skin came back ringing —
    /// white halos around every bevel and the artwork barely readable. A 3x3 sharpen is a strong
    /// filter and the resample it is correcting is a gentle one. 6/16 still speckled the smooth
    /// light band of `Plus! Hard Boiled`, which is JPEG noise being amplified; 3/16 is the most
    /// this artwork takes cleanly. Plain Lanczos with no sharpen at all (`0`) is the conservative
    /// setting and is still a clear improvement on the bilinear draw.
    private static let sharpenStrength: Int32 = 3
    private static let sharpenDivisor: Int32 = 16

    /// Lanczos-class upscale, in vImage rather than Core Image.
    ///
    /// **Core Image was the first implementation and both of its failures were real.** A
    /// `CILanczosScaleTransform` treats everything outside the source extent as transparent black
    /// and bleeds it inward, which turned the opaque red corner of the render fixture into
    /// `alpha=155` and would have put a soft halo around every sprite in the corpus; and a retained
    /// `CIContext` costs a file descriptor for the life of the process, which
    /// `testHundredRapidLoadsViewsResizesAndCacheTeardownRemainBounded` counts. vImage has neither
    /// problem: `kvImageEdgeExtend` replicates the border instead of inventing transparency, and
    /// there is no device context to retain.
    private static func lanczosUpscale(_ image: CGImage, scale: Int) -> CGImage? {
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8, bitsPerPixel: 32,
            colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue),
            version: 0, decode: nil, renderingIntent: .defaultIntent)

        var source = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&source, &format, nil, image,
                                           vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        defer { free(source.data) }

        var scaled = vImage_Buffer()
        guard vImageBuffer_Init(&scaled, source.height * UInt(scale), source.width * UInt(scale),
                                32, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        defer { free(scaled.data) }
        // `kvImageHighQualityResampling` is the Lanczos path; `kvImageEdgeExtend` is what keeps the
        // sprite's own border out of the transparent surround.
        let scaleFlags = vImage_Flags(kvImageHighQualityResampling | kvImageEdgeExtend)
        guard vImageScale_ARGB8888(&source, &scaled, nil, scaleFlags) == kvImageNoError else {
            return nil
        }

        sharpen(&scaled)

        var error = kvImageNoError
        let cgImage = vImageCreateCGImageFromBuffer(&scaled, &format, nil, nil,
                                                    vImage_Flags(kvImageNoFlags), &error)
        guard error == kvImageNoError, let cgImage else { return nil }
        return cgImage.takeRetainedValue()
    }

    /// A 3x3 sharpen over the colour channels only.
    ///
    /// **Alpha is deliberately left alone**, which is why this unpacks to planes rather than
    /// convolving the interleaved buffer: sharpening a silhouette's alpha is what produces a ringing
    /// halo around a keyed sprite. The data is unpremultiplied first for the same reason — a
    /// convolution over premultiplied colour pulls the background through every soft edge.
    ///
    /// Every step here is best-effort: a failure leaves `buffer` holding the un-sharpened resample,
    /// which is still the Lanczos result and still far better than what the draw filter produced.
    private static func sharpen(_ buffer: inout vImage_Buffer) {
        guard vImageUnpremultiplyData_RGBA8888(&buffer, &buffer,
                                               vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return
        }
        defer {
            _ = vImagePremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags))
        }

        var planes = [vImage_Buffer](repeating: vImage_Buffer(), count: 4)
        for index in planes.indices {
            guard vImageBuffer_Init(&planes[index], buffer.height, buffer.width, 8,
                                    vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
                for freed in planes.indices where freed < index { free(planes[freed].data) }
                return
            }
        }
        defer { for plane in planes { free(plane.data) } }

        // The converter is named for ARGB but is channel-order agnostic: it splits the four
        // interleaved channels in the order given, so for this RGBA buffer plane 0 is red and
        // plane 3 is alpha.
        guard vImageConvert_ARGB8888toPlanar8(&buffer, &planes[0], &planes[1], &planes[2],
                                              &planes[3],
                                              vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return
        }
        // Weights sum to `sharpenDivisor`, so the filter preserves overall brightness.
        let centre = sharpenDivisor + 4 * sharpenStrength
        let kernel: [Int16] = [0, Int16(-sharpenStrength), 0,
                               Int16(-sharpenStrength), Int16(centre), Int16(-sharpenStrength),
                               0, Int16(-sharpenStrength), 0]
        // Index 3 is alpha and is not convolved.
        for index in 0..<3 {
            var plane = planes[index]
            var destination = vImage_Buffer()
            guard vImageBuffer_Init(&destination, plane.height, plane.width, 8,
                                    vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return }
            let flags = vImage_Flags(kvImageEdgeExtend)
            let status = kernel.withUnsafeBufferPointer { pointer in
                vImageConvolve_Planar8(&plane, &destination, nil, 0, 0, pointer.baseAddress!,
                                       3, 3, sharpenDivisor, 0, flags)
            }
            guard status == kvImageNoError else { free(destination.data); return }
            free(planes[index].data)
            planes[index] = destination
        }

        _ = vImageConvert_Planar8toARGB8888(&planes[0], &planes[1], &planes[2], &planes[3],
                                            &buffer, vImage_Flags(kvImageNoFlags))
    }

    private static func crop(_ rect: WMPRect?, from image: CGImage) -> CGImage {
        guard let rect else { return image }
        let bounds = WMPRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        guard let clipped = rect.intersection(bounds) else { return image }
        return image.cropping(to: CGRect(x: clipped.x, y: clipped.y,
                                         width: clipped.width, height: clipped.height)) ?? image
    }

    /// A `CUSTOMSLIDER`'s greyscale position map, cached under the same byte bound as every other
    /// derived buffer. Keyed by canonical path alone: unlike a mapping image, nothing about the
    /// node changes what the map decodes to.
    func positionMap(for path: String, keyedOut: [WMPColor] = []) throws -> WMPPositionMap {
        let canonical = provider.canonicalPath(for: path) ?? path
        // Keyed by path **and** the node's transparency colours: those decide which pixels are part
        // of the control, so two nodes sharing one map file but keying different colours out of it
        // do not decode to the same answer. (It used to be keyed by path alone.)
        let cacheKey = "\(canonical)|\(keyedOut.map(\.description).joined(separator: ","))"
        lock.lock()
        if var entry = positionEntries[cacheKey] {
            clock &+= 1
            entry.access = clock
            positionEntries[cacheKey] = entry
            lock.unlock()
            return entry.map
        }
        lock.unlock()

        // The map is read for its colours, so it must never be decoded with a key applied — the
        // same rule `mappingImage` follows. `keyedOut` is interpreted by `WMPPositionMap`, not by
        // the decoder.
        let map = try WMPPositionMap(image: image(for: canonical).image, keyedOut: keyedOut)
        lock.lock()
        defer { lock.unlock() }
        if let existing = positionEntries[cacheKey] { return existing.map }
        guard map.decodedBytes <= limits.cacheBytes else { return map }
        while positionBytes + map.decodedBytes > limits.cacheBytes,
              let victim = positionEntries.min(by: { $0.value.access < $1.value.access }) {
            positionBytes -= victim.value.map.decodedBytes
            positionEntries.removeValue(forKey: victim.key)
        }
        clock &+= 1
        positionEntries[cacheKey] = PositionEntry(map: map, access: clock)
        positionBytes += map.decodedBytes
        return map
    }

    /// Whether a `CUSTOMSLIDER`'s filmstrip is authored **maximum first**, so the frame index has
    /// to count back from the end.
    ///
    /// **The corpus authors both orders with identical markup, so the direction is a property of
    /// the art and nothing else can say which way round it runs.** `ALXMorph/seek.png` steps its
    /// thumb left to right across sixty frames and `Catwoman/srs_slider.png` fills downward across
    /// eighteen — frame 0 is the minimum in both. `Halo 2/srs_slider.png` is the same control as
    /// Catwoman's, against the same left-to-right `0…251` position map and the same `min="0"
    /// max="100"`, and its fourteen frames run the other way: frame 0 is all thirteen segments lit
    /// and frame 13 is empty. Indexing it forwards drew *one* segment for a TruBass of 95 and the
    /// whole bar for 0 — reported as "the SRS WOW effect and TruBass level controls do not fire
    /// correctly", because the audio followed the pointer while the bar ran backwards under it.
    ///
    /// So the *map* says which end of the control is the minimum and the *art* says which end of
    /// the strip is, and they are answered separately. Two readings, because the corpus draws these
    /// two ways: a **fill bar** is read by lit coverage — alpha times luminance summed over the
    /// frame, first against last, descending when the first carries half again the last's — and a
    /// **moving thumb**, which is flat under coverage, by where its centre of mass sits in the two
    /// frames, measured along the axis the map's own ramp increases on (`WMPPositionMap.gradient`)
    /// and needing 15% of the frame's travel before it counts.
    ///
    /// Measured over the 180 installed archives this selects **19 of the 342 stripped
    /// `CUSTOMSLIDER`s, in 7 skins**: 13 by coverage — Halo 2's and STALKER's TruBass and WOW,
    /// `Plus! Mecha`'s, `Rave-MP`'s and `Xbox Live Skin`'s seek, `Secura`'s pair, `XBOX`'s and
    /// `Xbox Live Skin`'s volume — and 6 by travel, every one of them Halo 2's or STALKER's balance
    /// and the four video sliders beside it. Nothing outside those two families is reached by the
    /// second reading, which is what says it is picking up one authoring habit rather than firing
    /// on art in general.
    func filmstripIsDescending(for path: String, frameCount: Int, vertical: Bool,
                               gradient: (horizontal: Bool, positive: Bool)?) throws -> Bool {
        guard frameCount > 1 else { return false }
        let canonical = provider.canonicalPath(for: path) ?? path
        let axis = gradient.map { "\($0.horizontal)|\($0.positive)" } ?? "-"
        let cacheKey = "\(canonical)|\(frameCount)|\(vertical)|\(axis)"
        lock.lock()
        if let cached = descendingStripEntries[cacheKey] { lock.unlock(); return cached }
        lock.unlock()
        let image = try self.image(for: canonical).image
        let width = image.width, height = image.height
        let frameWidth = vertical ? width : width / frameCount
        let frameHeight = vertical ? height / frameCount : height
        guard frameWidth > 0, frameHeight > 0 else { return false }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Row zero is the authored top row, as everywhere else this store reads pixels back. The
        // centre of mass rides the map's own axis, so a thumb's travel is measured in the direction
        // the map calls "more" rather than in raw pixels.
        let alongX = gradient?.horizontal ?? true
        func measure(frame index: Int) -> (coverage: Double, centre: Double?) {
            let originX = vertical ? 0 : index * frameWidth
            let originY = vertical ? index * frameHeight : 0
            var total = 0.0, moment = 0.0
            for y in originY..<(originY + frameHeight) {
                for x in originX..<(originX + frameWidth) {
                    let offset = (y * width + x) * 4
                    // Premultiplied, so the three channels already carry the alpha weighting.
                    let weight = Double(Int(bytes[offset]) + Int(bytes[offset + 1])
                                        + Int(bytes[offset + 2])) / 765
                    total += weight
                    moment += weight * Double(alongX ? x - originX : y - originY)
                }
            }
            return (total, total > 0 ? moment / total : nil)
        }
        let first = measure(frame: 0), last = measure(frame: frameCount - 1)
        let answer: Bool
        if first.coverage > last.coverage * 1.5 { answer = true }
        else if last.coverage > first.coverage * 1.5 { answer = false }
        else if let start = first.centre, let end = last.centre,
                abs(start - end) > Double(alongX ? frameWidth : frameHeight) * 0.15 {
            // A thumb that ends up *behind* where it started, read along the map's own direction,
            // is a strip authored the other way round.
            answer = (gradient?.positive ?? true) ? start > end : start < end
        } else { answer = false }
        lock.lock()
        descendingStripEntries[cacheKey] = answer
        lock.unlock()
        return answer
    }

    /// A `clippingImage` as an alpha mask: opaque where the artwork shows through, transparent
    /// where it is cut away.
    ///
    /// WMP shapes an element by its clipping image's *own* transparency, and by `clippingColor`
    /// where one is declared — 25 corpus skins author a non-empty `clippingImage` and every one of
    /// them also declares a `clippingColor`. A `CGImage` mask wants "keep" as opaque, so the two
    /// tests are combined into one alpha channel here rather than at every draw.
    func clippingMask(for path: String, keyedOut: [WMPColor]) throws -> CGImage {
        try mask(for: path, keyedOut: keyedOut, honoringSourceAlpha: true, kind: "clip")
    }

    /// A container's artwork read as a **region** rather than as a clipping image: in the region
    /// wherever the pixel is not the keyed-out colour, *whatever its alpha*.
    ///
    /// That last clause is the whole difference from `clippingMask`, and it is what a `SUBVIEW`'s
    /// `transparencyColor` means. `Plus! Bionic Dot`'s `main_vis_back.png` is 169x160 and paints
    /// 1,369 pixels — a highlight ring, 5% of the file. The other 95% carries the shape in two
    /// distinct values the author chose deliberately: 9,865 pixels of `#ff00ff` marking the
    /// *outside* of the lens, and 15,806 fully transparent pixels marking its *inside*. Reading
    /// alpha as "cut away" there — which `clippingMask` correctly does for a `clippingImage` —
    /// would mask away the lens and keep the surround, exactly inverting the shape.
    ///
    /// 30 `<EFFECTS>` across 27 archives hang off a parent that carries a `backgroundImage` and a
    /// `transparencyColor`, and the Plus! family names the asset outright: `Egg_Body_Mask.gif`,
    /// `body_Mask.gif`, `green_body_MASK.gif`, `perfect_tray_shape_mask.gif`.
    /// Whether a container's background image shapes its children by **region** — the caller's
    /// licence to use `regionMask` at all.
    ///
    /// **Two states or three is the whole question, and the corpus answers it cleanly.** A keyed
    /// container comes in two shapes, and they mean opposite things:
    ///
    /// - *Artwork with a keyed hole.* Every pixel is either the key or opaque paint. The key marks
    ///   the **opening** the child shows through, and the paint occludes the rest — which this
    ///   engine already renders correctly, by hosting the container's own paint commands above the
    ///   surface (`WMPWidget.commandSplitIndex`). Cerulean's `face.bmp` is this: 56% key, 44%
    ///   opaque, **0% transparent**. Masking it by region would keep the visualizer only where the
    ///   face already covers it and clip it away inside the hole — erasing the visualizer outright.
    /// - *A shape mask.* The file carries a third state, and the author is using it to say
    ///   something the first shape cannot: the key marks the **outside**, genuinely transparent
    ///   pixels mark the opening, and what little paint there is is trim.
    ///
    /// Measured over every `<EFFECTS>` in the installed corpus whose container declares both a
    /// background image and a transparency colour — 30 of them, in 27 archives — **29 are
    /// two-state and one is three-state**: `Plus! Bionic Dot`'s `main_vis_back.png`, at 36% key,
    /// 58% transparent and 5% paint (it ships in two archives, so 2 of 30 rows). Nothing else in
    /// the corpus, Plus! or otherwise, mixes the two. So the predicate is *has transparent pixels
    /// alongside keyed ones*, not a threshold and not a skin name.
    /// The colour a `clippingColor="auto"` / `transparencyColor="auto"` declaration means.
    ///
    /// **`auto` cannot mean "no key".** Four declarations across three archives write it —
    /// `Plus! Plasma Ball` twice, `Compact` and `digitaldj` once each — and rejecting the value is
    /// what W167 was: `Plasma Ball`'s `mainButtons` carries `clippingImage="screen_MASK.gif"`
    /// beside it, that mask is 242x299 with **zero** transparent pixels, so an unresolved key left
    /// the whole 242x299 `screen_normal.jpg` opaque over the player and the window showed as a flat
    /// `#9FA8AD` box. WMP derives the key from the bitmap the declaration governs, and its corner
    /// is where every one of the four authors put it: `screen_MASK.gif` and
    /// `playlist_vid_panel_MASK.gif` are white at 0,0 — the same `clippingColor="white"` their four
    /// sibling layers in the same file state by hand — and `digitaldj/preview.bmp` is `#FF0000`
    /// there, a matte colour covering 10% of the file.
    func cornerColor(for path: String) throws -> WMPColor? {
        let canonical = provider.canonicalPath(for: path) ?? path
        lock.lock()
        if let cached = cornerColorEntries[canonical] { lock.unlock(); return cached }
        lock.unlock()
        let answer = Self.topLeftColor(of: try image(for: canonical).image)
        lock.lock()
        cornerColorEntries[canonical] = answer
        lock.unlock()
        return answer
    }

    /// Un-premultiplied, and nil for a corner that is already transparent — a bitmap that authored
    /// its own alpha has said what is see-through and there is no matte colour to infer.
    private static func topLeftColor(of image: CGImage) -> WMPColor? {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // Draw the whole bitmap into a 1x1 window on its own top-left pixel: the CTM is
            // y-flipped relative to the bitmap's row zero, so the origin offset carries the height.
            context.translateBy(x: 0, y: 1 - CGFloat(image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let alpha = pixel[3]
        guard alpha > 0 else { return nil }
        return WMPColor(red: unpremultiply(pixel[0], alpha: alpha),
                        green: unpremultiply(pixel[1], alpha: alpha),
                        blue: unpremultiply(pixel[2], alpha: alpha))
    }

    private static func unpremultiply(_ value: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha < 255, alpha > 0 else { return value }
        return UInt8(min(255, Int(value) * 255 / Int(alpha)))
    }

    /// Whether a bitmap carries transparency of its own.
    ///
    /// This is what decides whether a `clippingImage` declared with **no** key beside it needs one
    /// derived. A mask that authored its own alpha has already said what it cuts, and
    /// `clippingMask(for:keyedOut:)` honours that alpha; a fully opaque mask has said nothing and
    /// clips nothing at all unless a colour makes it a shape — see
    /// `WMPSceneBuilder.clippingMaskKeys`.
    func carriesOwnTransparency(for path: String) throws -> Bool {
        let canonical = provider.canonicalPath(for: path) ?? path
        lock.lock()
        if let cached = regionShapeEntries[canonical] { lock.unlock(); return cached }
        lock.unlock()
        let answer = Self.hasTransparentPixels(try image(for: canonical).image)
        lock.lock()
        regionShapeEntries[canonical] = answer
        lock.unlock()
        return answer
    }

    func shapesChildrenByRegion(for path: String, keyedOut: [WMPColor]) throws -> Bool {
        guard !keyedOut.isEmpty else { return false }
        let canonical = provider.canonicalPath(for: path) ?? path
        lock.lock()
        if let cached = regionShapeEntries[canonical] { lock.unlock(); return cached }
        lock.unlock()
        let source = try image(for: canonical).image
        let answer = Self.hasTransparentPixels(source)
        lock.lock()
        regionShapeEntries[canonical] = answer
        lock.unlock()
        return answer
    }

    private static func hasTransparentPixels(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] == 0 { return true }
        return false
    }

    /// Whether a bitmap is a **shape mask** rather than artwork: is it two-toned?
    ///
    /// This is the licence for a container's `backgroundImage` to shape its children, and the
    /// corpus forced it. 84 `<SUBVIEW>`s in 38 archives and 26 `<VIEW>`s in 17 declare a
    /// `clippingColor` with no `clippingImage`, and they are two different authoring idioms that
    /// the attribute cannot tell apart:
    ///
    /// - *A mask.* `Combat_Flight_Simulator_3`'s `main_bg_mask.png` is 584x321 in exactly three
    ///   colours — 71% white, 29% black and one stray `#D4D4D4` pixel — and the black is the
    ///   aeroplane its `main_bg.jpg` child is cut to (W168).
    /// - *Artwork with a keyed hole.* `YIL!OMA2K`'s `yMain Body.bmp` is 530x440 in **34,688**
    ///   colours with a 246x179 rectangle of `#6699FF` cut out of it for the video, and a
    ///   `<subview zIndex="-2">` of solid black parked behind the body to show through that hole.
    ///   Shaping children by it clips the backdrop away and leaves the display empty — which is the
    ///   W147/Cerulean inversion arriving through `clippingColor` instead of `transparencyColor`.
    ///
    /// Two tones or many is the whole question, and it separates the two populations cleanly: the
    /// mask idiom is 3 and 10 colours, the artwork idiom 2,181 to 34,688. The threshold is a share
    /// rather than a count because a mask's own edges are antialiased — `main_vismask.png` is 10
    /// colours at 100.0% in its top two.
    func isShapeMask(for path: String) throws -> Bool {
        let canonical = provider.canonicalPath(for: path) ?? path
        lock.lock()
        if let cached = shapeMaskEntries[canonical] { lock.unlock(); return cached }
        lock.unlock()
        let answer = Self.isTwoToned(try image(for: canonical).image)
        lock.lock()
        shapeMaskEntries[canonical] = answer
        lock.unlock()
        return answer
    }

    private static func isTwoToned(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return false }
        var counts: [UInt32: Int] = [:]
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt32(pixels[index]) << 24 | UInt32(pixels[index + 1]) << 16
                | UInt32(pixels[index + 2]) << 8 | UInt32(pixels[index + 3])
            counts[value, default: 0] += 1
        }
        let top = counts.values.sorted(by: >).prefix(2).reduce(0, +)
        return Double(top) >= 0.99 * Double(width * height)
    }

    func regionMask(for path: String, keyedOut: [WMPColor]) throws -> CGImage {
        try mask(for: path, keyedOut: keyedOut, honoringSourceAlpha: false, kind: "region")
    }

    /// The 8-bit region mask a `<BUTTONGROUP>` paints one of its sheets through, cached.
    ///
    /// **It is a pure function of the bitmap and the child set, and it must not be rebuilt per
    /// draw.** W154 made every group's *base* sheet mask on every frame rather than only the one
    /// group the pointer was lighting, and `WMPMappingImage.maskImage` — an allocation and a full
    /// pixel walk — went straight to the top of a live profile: six saturated cooperative threads
    /// on `New Super Mario Bros`, the renderer running off-main and starving everything else
    /// awaiting that pool, reported as the app stuttering and hanging while clicking its playlist
    /// and equalizer buttons. The main thread was idle throughout, which is why the profile had to
    /// settle it rather than the symptom.
    ///
    /// Shares the clipping-mask LRU: both are one byte per pixel keyed by a resource path, and a
    /// mapping mask is evicted on the same budget as any other.
    func mappingMask(for mask: WMPSceneMappingMask) -> CGImage? {
        let canonical = provider.canonicalPath(for: mask.resourcePath) ?? mask.resourcePath
        let nodes = mask.nodeIDs.sorted()
        let key = "\(canonical)|mapmask=\(nodes.map(String.init).joined(separator: ","))"
        lock.lock()
        if var entry = clipEntries[key] {
            clock &+= 1
            entry.access = clock
            clipEntries[key] = entry
            lock.unlock()
            return entry.mask
        }
        lock.unlock()

        guard let image = mask.mapping.maskImage(for: Set(nodes)) else { return nil }
        let bytes = image.width * image.height
        lock.lock()
        defer { lock.unlock() }
        if let existing = clipEntries[key] { return existing.mask }
        guard bytes <= limits.cacheBytes else { return image }
        while clipBytes + bytes > limits.cacheBytes,
              let victim = clipEntries.min(by: { $0.value.access < $1.value.access }) {
            clipBytes -= victim.value.bytes
            clipEntries.removeValue(forKey: victim.key)
        }
        clock &+= 1
        clipEntries[key] = ClipEntry(mask: image, bytes: bytes, access: clock)
        clipBytes += bytes
        return image
    }

    private func mask(for path: String, keyedOut: [WMPColor], honoringSourceAlpha: Bool,
                      kind: String) throws -> CGImage {
        let canonical = provider.canonicalPath(for: path) ?? path
        let keys = keyedOut.map(\.description).joined(separator: ",")
        let key = "\(canonical)|\(kind)=\(keys)"
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
        let mask = try Self.makeClippingMask(from: source, keyedOut: keyedOut,
                                             honoringSourceAlpha: honoringSourceAlpha)
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

    private static func makeClippingMask(from image: CGImage, keyedOut: [WMPColor],
                                        honoringSourceAlpha: Bool = true) throws -> CGImage {
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
                // A region reads a transparent pixel as *inside* the shape — see `regionMask`.
                // A clipping image reads it as cut away, which is the `honoringSourceAlpha` case.
                guard a > 0 else {
                    if !honoringSourceAlpha { alpha[y * width + x] = 255 }
                    continue
                }
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
        image = try WMPColorKey.applying(keys(colorKeys, implicitKey: implicitKey), to: image,
            componentTolerance: (ext == "jpg" || ext == "jpeg") ? WMPColorKey.jpegComponentTolerance : 0)
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
