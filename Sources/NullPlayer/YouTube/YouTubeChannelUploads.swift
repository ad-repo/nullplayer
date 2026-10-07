import Foundation

/// Every channel's last fetched upload list, shared by both library browsers and kept on disk,
/// so an expanded channel shows its list at once — after a relaunch too. `load` runs
/// `YouTubeManager.videos(forChannel:limit:)` only when there is no list, it is older than
/// `maxAge`, it was fetched under a smaller Videos per Channel limit, or on Refresh; one fetch
/// per channel runs at a time. A smaller limit shows the newest uploads of the cached list.
@MainActor
final class YouTubeChannelUploads {
    static let shared = YouTubeChannelUploads(
        file: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NullPlayer/youtube_uploads.json"))

    /// A fetch started or finished: rows and channel spinners changed.
    static let didChangeNotification = Notification.Name("YouTubeChannelUploadsDidChange")

    /// A list this old is shown, then fetched again.
    nonisolated static let maxAge: TimeInterval = 60 * 60
    /// A list this old is dropped when the file is read, so unsubscribed channels previewed
    /// from a search don't pile up.
    static let maxStoredAge: TimeInterval = 30 * 24 * 60 * 60

    struct Entry: Codable {
        let limit: Int
        let fetchedAt: Date
        let videos: [YouTubeVideo]

        func isFresh(limit: Int, now: Date) -> Bool {
            self.limit >= limit && now.timeIntervalSince(fetchedAt) < YouTubeChannelUploads.maxAge
        }
    }

    typealias Fetch = (YouTubeChannel, Int) async throws -> [YouTubeVideo]

    private let file: URL
    private let limit: () -> Int
    private let fetch: Fetch
    private lazy var entries: [String: Entry] = Self.read(file)
    private var inFlight: Set<String> = []

    init(file: URL,
         limit: @escaping () -> Int = { YouTubeManager.shared.videoLimit },
         fetch: @escaping Fetch = { try await YouTubeManager.shared.videos(forChannel: $0, limit: $1) }) {
        self.file = file
        self.limit = limit
        self.fetch = fetch
    }

    var hasFetchesInFlight: Bool { !inFlight.isEmpty }

    func isFetching(_ channelId: String) -> Bool { inFlight.contains(channelId) }

    /// The cached uploads of these channels, cut to the current limit.
    func uploads(of channelIds: some Sequence<String>) -> [String: [YouTubeVideo]] {
        let limit = limit()
        var lists: [String: [YouTubeVideo]] = [:]
        for id in channelIds {
            if let entry = entries[id] { lists[id] = Array(entry.videos.prefix(limit)) }
        }
        return lists
    }

    /// Fetch each channel's uploads unless a fresh list is cached (`force`: Refresh) or a fetch
    /// is already running. Always posts `didChangeNotification` once, so a caller that changed
    /// what is expanded rebuilds from it; each fetch posts again when it ends.
    func load(_ channels: some Sequence<YouTubeChannel>, force: Bool = false) {
        for channel in channels { startFetch(channel, force: force) }
        didChange()
    }

    private func startFetch(_ channel: YouTubeChannel, force: Bool) {
        let limit = limit()
        let cached = entries[channel.id]
        guard !inFlight.contains(channel.id), force || cached?.isFresh(limit: limit, now: Date()) != true else { return }
        NSLog("YouTubeChannelUploads: fetching '%@' (limit %d; cached: %@)", channel.title, limit,
              cached.map { "\($0.videos.count) at limit \($0.limit), \(Int(Date().timeIntervalSince($0.fetchedAt)))s old" } ?? "none")
        inFlight.insert(channel.id)
        Task {
            let videos: [YouTubeVideo]?
            do {
                videos = try await fetch(channel, limit)
            } catch {
                videos = nil
                NSLog("YouTubeChannelUploads: failed to fetch '%@': %@", channel.title,
                      error.localizedDescription.redactingSensitiveURLQueryItems)
            }
            inFlight.remove(channel.id)
            if let videos {
                entries[channel.id] = Entry(limit: limit, fetchedAt: Date(), videos: videos)
                write()
            }
            // The limit grew while this fetch ran, so the list just stored is already short.
            if videos != nil, limit < self.limit() { startFetch(channel, force: false) }
            didChange()
        }
    }

    private func didChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // ponytail: the whole file is decoded on first use and rewritten per fetch on the main thread
    // (~60 KB per channel); move to a background writer if subscriptions grow into the hundreds.
    private static func read(_ file: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        let now = Date()
        return entries.filter { now.timeIntervalSince($0.value.fetchedAt) < maxStoredAge }
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
