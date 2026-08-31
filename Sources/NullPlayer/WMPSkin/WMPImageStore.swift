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
}

struct WMPDecodedImage {
    let image: CGImage
    let size: WMPSize
    let decodedBytes: Int
}

/// A lock-protected LRU whose keys include the color key. The retained graph never owns CGImage or
/// cache state. Callers use this store only from WMP background work.
final class WMPImageStore: @unchecked Sendable {
    private struct Entry {
        let image: WMPDecodedImage
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

    init(provider: WMPResourceProviding, limits: WMPImageStoreLimits = .production) {
        self.provider = provider
        self.limits = limits
    }

    func image(for path: String, colorKey: WMPColor? = nil) throws -> WMPDecodedImage {
        let canonical = provider.canonicalPath(for: path) ?? path
        let cacheKey = canonical + (colorKey.map { "|key=\($0)" } ?? "")
        lock.lock()
        if var entry = entries[cacheKey] {
            clock &+= 1
            entry.access = clock
            entries[cacheKey] = entry
            lock.unlock()
            return entry.image
        }
        lock.unlock()

        let decoded = try decode(path: canonical, colorKey: colorKey)
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
        lock.unlock()
    }

    var metrics: WMPImageStoreMetrics {
        lock.lock()
        defer { lock.unlock() }
        return WMPImageStoreMetrics(cachedImageCount: entries.count,
            currentCacheBytes: currentBytes, peakCacheBytes: peakBytes,
            decodedImageCount: decodeCount, evictionCount: evictions)
    }

    private func decode(path: String, colorKey: WMPColor?) throws -> WMPDecodedImage {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ["bmp", "gif", "jpg", "jpeg", "png"].contains(ext) else {
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "Image '\(path)' is not BMP, GIF, JPEG, or PNG."))
        }
        let data = try provider.data(for: path) as CFData
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = integer(properties[kCGImagePropertyPixelWidth]),
              let height = integer(properties[kCGImagePropertyPixelHeight]) else {
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "ImageIO could not read metadata for '\(path)'."))
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, width <= limits.maximumDimension,
              height <= limits.maximumDimension, !overflow, pixels <= limits.maximumPixels,
              !byteOverflow, bytes <= limits.maximumDecodedBytes else {
            throw WMPFailure(WMPDiagnostic(.oversizedImage,
                "Image '\(path)' declares \(width)x\(height), beyond the decoded image limit."))
        }
        let decodeOptions = [kCGImageSourceShouldCacheImmediately: true,
                             kCGImageSourceShouldCache: true] as CFDictionary
        guard var image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions) else {
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "ImageIO could not decode '\(path)'."))
        }
        if let colorKey { image = try WMPColorKey.applying(colorKey, to: image) }
        return WMPDecodedImage(image: image,
            size: WMPSize(width: CGFloat(width), height: CGFloat(height)), decodedBytes: bytes)
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
