import Foundation
import AppKit

/// Combined memory and disk cache for Met Museum images
///
/// - Memory cache: NSCache<NSNumber, NSImage> for fast access
/// - Disk cache: ~/Library/Caches/NullPlayer/MetMuseum/ keyed by objectID
/// - LRU pruning: Keeps disk cache ≤ 200 MB (configurable)
final class MetMuseumImageCache {

    // MARK: - Configuration

    private var maxDiskCacheSizeBytes: Int = 200 * 1024 * 1024  // 200 MB default

    // MARK: - State

    private let memoryCache = NSCache<NSNumber, NSData>()
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let cacheLock = NSLock()

    // MARK: - Init

    init() {
        // Create cache directory: ~/Library/Caches/NullPlayer/MetMuseum/
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("Unable to locate Caches directory")
        }

        let nullPlayerCache = cachesDir.appendingPathComponent("NullPlayer", isDirectory: true)
        self.cacheDirectory = nullPlayerCache.appendingPathComponent("MetMuseum", isDirectory: true)

        // Ensure directory exists
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)

        // Set memory cache limits
        memoryCache.totalCostLimit = 100 * 1024 * 1024  // 100 MB memory cache
    }

    // MARK: - Public API

    /// Retrieve raw image data from cache (memory first, then disk)
    func cachedImageData(for objectID: Int) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Try memory cache first
        let key = NSNumber(value: objectID)
        if let data = memoryCache.object(forKey: key) as Data? {
            return data
        }

        // Try disk cache
        let fileURL = fileURLForObject(objectID)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        // Populate memory cache
        let cost = data.count
        memoryCache.setObject(data as NSData, forKey: key, cost: cost)

        return data
    }

    /// Store raw image data in both memory and disk caches
    func store(_ data: Data, for objectID: Int) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let key = NSNumber(value: objectID)

        // Store in memory cache
        memoryCache.setObject(data as NSData, forKey: key, cost: data.count)

        // Store in disk cache
        let fileURL = fileURLForObject(objectID)
        try? data.write(to: fileURL)

        // Prune disk cache if needed
        pruneDiskCacheIfNeeded()
    }

    /// Clear all cached images
    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    /// Prune disk cache to max size (called after each store)
    func prune(maxBytes: Int) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let oldMax = self.maxDiskCacheSizeBytes
        self.maxDiskCacheSizeBytes = maxBytes
        pruneDiskCacheIfNeeded()
        self.maxDiskCacheSizeBytes = oldMax
    }

    // MARK: - Private Helpers

    private func fileURLForObject(_ objectID: Int) -> URL {
        cacheDirectory.appendingPathComponent("\(objectID).dat")
    }

    /// LRU prune: remove oldest files until total size ≤ maxDiskCacheSizeBytes
    private func pruneDiskCacheIfNeeded() {
        guard let fileURLs = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return
        }

        var totalSize: Int = 0
        var fileInfo: [(url: URL, size: Int, date: Date)] = []

        for url in fileURLs {
            guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = resources.fileSize,
                  let date = resources.contentModificationDate else {
                continue
            }
            fileInfo.append((url: url, size: size, date: date))
            totalSize += size
        }

        // If we're under the limit, nothing to do
        if totalSize <= maxDiskCacheSizeBytes {
            return
        }

        // Sort by modification date (oldest first)
        fileInfo.sort { $0.date < $1.date }

        // Remove files until we're under the limit
        var removed = 0
        for (url, size, _) in fileInfo {
            guard totalSize > maxDiskCacheSizeBytes else { break }

            try? fileManager.removeItem(at: url)
            totalSize -= size
            removed += 1
        }

    }
}
