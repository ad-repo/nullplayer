import CoreGraphics

/// Row thumbnails kept by recency of use: past `limit`, the least recently used tenth goes. Not an
/// `NSCache`: every list pass draws them, and a cache emptied under memory pressure made each pass
/// reload them, whose arrival redrew the list and reloaded them again.
struct RecentThumbnails {
    private struct Entry {
        let image: CGImage
        var used: Int
    }

    /// 2000 × ~16 KB is ~32 MB, held through memory pressure — hence below the 3000 the old
    /// `NSCache` allowed, when the system could take them back.
    static let defaultLimit = 2000

    let limit: Int
    private var entries: [String: Entry] = [:]
    private var tick = 0

    init(limit: Int = defaultLimit) { self.limit = limit }

    var count: Int { entries.count }

    /// Whether `key` is held, without counting as a use.
    func contains(_ key: String) -> Bool { entries[key] != nil }

    /// The image for `key`, counted as a use: the rows on screen were drawn last, so they stay.
    mutating func use(_ key: String) -> CGImage? {
        tick += 1
        entries[key]?.used = tick
        return entries[key]?.image
    }

    mutating func insert(_ image: CGImage, key: String) {
        tick += 1
        entries[key] = Entry(image: image, used: tick)
        guard entries.count > limit else { return }
        for (old, _) in entries.sorted(by: { $0.value.used < $1.value.used }).prefix(max(1, limit / 10)) {
            entries[old] = nil
        }
    }
}
