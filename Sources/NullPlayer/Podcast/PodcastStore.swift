import AppKit
import Foundation

@MainActor
final class PodcastStore: ObservableObject {
    static let shared = PodcastStore()

    enum Section: String, CaseIterable, Identifiable {
        case subscriptions = "Subscriptions"
        case discover = "Discover"
        case favorites = "Favorites"
        case downloads = "Downloads"
        var id: String { rawValue }
    }

    static let libraryDidChangeNotification = Notification.Name("PodcastLibraryDidChange")
    static let showSettingsNotification = Notification.Name("ShowPodcastIndexSettings")
    static let showAddFeedNotification = Notification.Name("ShowAddPodcastFeed")

    @Published private(set) var subscriptions: [PodcastSubscription] = []
    @Published private(set) var episodeStates: [String: PodcastEpisodeState] = [:]
    @Published private(set) var knownEpisodes: [String: PodcastEpisode] = [:]
    @Published private(set) var discoveryFeeds: [PodcastFeed] = []
    @Published private(set) var selectedFeed: PodcastFeed?
    @Published private(set) var selectedEpisodes: [PodcastEpisode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var section: Section = .subscriptions
    @Published var episodeSearch = ""
    @Published private(set) var sleepTimerEnd: Date?

    private let client = PodcastIndexClient.shared
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var sleepTimer: Timer?
    private var didStartPersistence = false
    /// The last submitted directory query while in `.discover`, so refresh re-runs the user's
    /// search rather than silently swapping in trending results.
    private var lastSearchTerm: String?

    private init() {}

    var hasCredentials: Bool { client.credentials?.isConfigured == true }
    var subscribedFeeds: [PodcastFeed] { subscriptions.map(\.feed) }
    var downloadedEpisodes: [PodcastEpisode] {
        knownEpisodes.values.filter { episodeStates[$0.id]?.downloadedPath != nil }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }
    var favoriteEpisodes: [PodcastEpisode] {
        knownEpisodes.values.filter { episodeStates[$0.id]?.isFavorite == true }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    func isSubscribed(_ feed: PodcastFeed) -> Bool { subscriptions.contains { $0.feed.id == feed.id } }
    func state(for episode: PodcastEpisode) -> PodcastEpisodeState { episodeStates[episode.id] ?? PodcastEpisodeState() }
    func isDownloading(_ episode: PodcastEpisode) -> Bool { downloadTasks[episode.id] != nil }

    func start() {
        guard !didStartPersistence else { return }
        didStartPersistence = true
        isLoading = true
        PodcastPersistenceCoordinator.shared.load { [weak self] snapshot in
            guard let self else { return }
            subscriptions = snapshot.subscriptions
            episodeStates = snapshot.episodeStates
            knownEpisodes = snapshot.knownEpisodes
            isLoading = false
        }
    }

    func search(_ term: String) {
        searchTask?.cancel()
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        lastSearchTerm = query
        closeFeed()
        section = .discover
        isLoading = true
        errorMessage = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let feeds = try await client.search(term: query)
                guard !Task.isCancelled else { return }
                discoveryFeeds = feeds
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func select(_ feed: PodcastFeed) {
        selectedFeed = feed
        selectedEpisodes = []
        episodeSearch = ""
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let episodes = try await client.episodes(for: feed)
                guard !Task.isCancelled, selectedFeed?.id == feed.id else { return }
                selectedEpisodes = episodes
                for episode in episodes { knownEpisodes[episode.id] = episode }
                persistEpisodes(episodes)
                await autoDownloadNewestIfNeeded(feed: feed, episodes: episodes)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func closeFeed() {
        selectedFeed = nil
        selectedEpisodes = []
        episodeSearch = ""
        loadTask?.cancel()
        isLoading = false
        errorMessage = nil
    }

    func showSubscriptions() {
        searchTask?.cancel()
        lastSearchTerm = nil
        section = .subscriptions
        closeFeed()
    }

    func subscribe(_ feed: PodcastFeed) {
        if let index = subscriptions.firstIndex(where: { $0.feed.id == feed.id }) {
            subscriptions[index].feed = feed
        } else {
            subscriptions.append(PodcastSubscription(feed: feed, subscribedAt: Date(), autoDownloadNewest: false))
            subscriptions.sort { $0.feed.title.localizedStandardCompare($1.feed.title) == .orderedAscending }
        }
        persistSubscriptionsAndNotify()
    }

    func unsubscribe(_ feed: PodcastFeed) {
        subscriptions.removeAll { $0.feed.id == feed.id }
        persistSubscriptionsAndNotify()
    }

    func toggleSubscription(_ feed: PodcastFeed) {
        isSubscribed(feed) ? unsubscribe(feed) : subscribe(feed)
    }

    func toggleAutoDownload(_ feed: PodcastFeed) {
        guard let index = subscriptions.firstIndex(where: { $0.feed.id == feed.id }) else { return }
        subscriptions[index].autoDownloadNewest.toggle()
        persistSubscriptionsAndNotify()
    }

    func addFeed(urlString: String) async throws {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw PodcastIndexError.invalidURL
        }
        isLoading = true
        do {
            let feed = try await client.feed(forURL: url)
            subscribe(feed)
            select(feed)
        } catch {
            isLoading = false
            throw error
        }
    }

    func refresh() {
        if let selectedFeed { select(selectedFeed) }
        else if section == .discover, let term = lastSearchTerm { search(term) }
    }

    func refreshAllSubscriptions() {
        guard !subscriptions.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        loadTask?.cancel()
        let feeds = subscriptions.map(\.feed)
        loadTask = Task { [weak self] in
            guard let self else { return }
            var loaded: [PodcastEpisode] = []
            for feed in feeds {
                guard !Task.isCancelled else { break }
                do {
                    let episodes = try await client.episodes(for: feed, max: 100)
                    for episode in episodes { knownEpisodes[episode.id] = episode }
                    loaded.append(contentsOf: episodes)
                    await autoDownloadNewestIfNeeded(feed: feed, episodes: episodes)
                } catch {
                    NSLog("PodcastStore: refresh failed for %@: %@", feed.title, error.localizedDescription)
                }
            }
            persistEpisodes(loaded)
            isLoading = false
        }
    }

    func play(_ episode: PodcastEpisode) {
        knownEpisodes[episode.id] = episode
        let track = makeTrack(for: episode)
        var episodeState = state(for: episode)
        episodeState.lastPlayedAt = Date()
        episodeStates[episode.id] = episodeState
        persistEpisode(episode)

        let canResume = !episode.isVideo && episodeState.position > 5 &&
            episodeState.position < max(0, (episode.duration ?? .greatestFiniteMagnitude) - 15)
        let audioEngine = WindowManager.shared.audioEngine
        let waitForStreamingReadiness = canResume && !track.url.isFileURL && !audioEngine.isCastingActive
        audioEngine.playNow(
            [track],
            resumeStreamingAt: waitForStreamingReadiness ? episodeState.position : nil
        )

        guard canResume, !waitForStreamingReadiness else { return }
        let episodeID = episode.id
        let resumePosition = episodeState.position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard let current = WindowManager.shared.audioEngine.currentTrack,
                  current.podcastEpisodeID == episodeID else { return }
            WindowManager.shared.audioEngine.seek(to: resumePosition)
        }
    }

    func playNext(_ episode: PodcastEpisode) {
        knownEpisodes[episode.id] = episode
        WindowManager.shared.audioEngine.insertTracksAfterCurrent([makeTrack(for: episode)], startPlaybackIfEmpty: true)
        persistEpisode(episode)
    }

    func addToPlaylist(_ episode: PodcastEpisode) {
        knownEpisodes[episode.id] = episode
        WindowManager.shared.audioEngine.appendTracks([makeTrack(for: episode)])
        persistEpisode(episode)
    }

    func addUnplayedToPlaylist(_ episodes: [PodcastEpisode]) {
        let unplayed = episodes.filter { !state(for: $0).isPlayed }
        guard !unplayed.isEmpty else { return }
        for episode in unplayed { knownEpisodes[episode.id] = episode }
        WindowManager.shared.audioEngine.appendTracks(unplayed.map(makeTrack(for:)))
        persistEpisodes(unplayed)
    }

    func togglePlayed(_ episode: PodcastEpisode) {
        var value = state(for: episode)
        value.isPlayed.toggle()
        if value.isPlayed { value.position = episode.duration ?? value.position }
        else { value.position = 0 }
        value.duration = episode.duration ?? value.duration
        value.lastPlayedAt = Date()
        episodeStates[episode.id] = value
        persistEpisodeAndNotify(episode)
    }

    func toggleFavorite(_ episode: PodcastEpisode) {
        var value = state(for: episode)
        value.isFavorite.toggle()
        episodeStates[episode.id] = value
        persistEpisodeAndNotify(episode)
    }

    func download(_ episode: PodcastEpisode) {
        guard downloadTasks[episode.id] == nil else { return }
        guard episode.enclosureURL.isPodcastRemoteURL else {
            errorMessage = "This episode has an unsupported download URL."
            return
        }
        knownEpisodes[episode.id] = episode
        let task = Task { [weak self] in
            guard let self else { return }
            defer { downloadTasks[episode.id] = nil; objectWillChange.send() }
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: episode.enclosureURL)
                guard !Task.isCancelled else { return }
                let suggestedFilename = response.suggestedFilename
                let destination = try await Task.detached(priority: .utility) {
                    let destination = try Self.downloadDestination(
                        for: episode,
                        suggestedFilename: suggestedFilename
                    )
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: temporaryURL, to: destination)
                    return destination
                }.value
                var value = state(for: episode)
                value.downloadedPath = destination.path
                episodeStates[episode.id] = value
                persistEpisodeAndNotify(episode)
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
        downloadTasks[episode.id] = task
        objectWillChange.send()
    }

    func removeDownload(_ episode: PodcastEpisode) {
        guard var value = episodeStates[episode.id], let path = value.downloadedPath else { return }
        value.downloadedPath = nil
        episodeStates[episode.id] = value
        persistEpisodeAndNotify(episode)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        guard let minutes, minutes > 0 else { sleepTimerEnd = nil; return }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEnd = end
        sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                WindowManager.shared.audioEngine.pause()
                self.sleepTimerEnd = nil
                self.sleepTimer = nil
            }
        }
    }

    func saveCredentials(key: String, secret: String) {
        let credentials = PodcastIndexCredentials(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   apiSecret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
        _ = KeychainHelper.shared.setPodcastIndexCredentials(credentials)
        objectWillChange.send()
    }

    func clearCredentials() {
        KeychainHelper.shared.clearPodcastIndexCredentials()
        discoveryFeeds = []
        errorMessage = nil
        objectWillChange.send()
    }

    func importOPML(from url: URL) async throws {
        let outlines = try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: url)
            return PodcastOPMLParser(data: data).feedURLs
        }.value
        for outline in outlines {
            // OPML files are untrusted input; only import remote http(s) feed URLs so an imported
            // outline can't point the RSS loader at a local file.
            guard outline.url.isPodcastRemoteURL else { continue }
            do {
                let feed = try await client.feed(forURL: outline.url)
                subscribe(feed)
            } catch {
                let fallback = PodcastFeed(title: outline.title ?? outline.url.host ?? "Podcast", feedURL: outline.url)
                subscribe(fallback)
            }
        }
    }

    func exportOPML(to url: URL) async throws {
        let outlines = subscriptions.map {
            "    <outline type=\"rss\" text=\"\($0.feed.title.xmlEscapedForPodcast)\" title=\"\($0.feed.title.xmlEscapedForPodcast)\" xmlUrl=\"\($0.feed.feedURL.absoluteString.xmlEscapedForPodcast)\"/>"
        }.joined(separator: "\n")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>NullPlayer Podcasts</title></head><body>
        \(outlines)
        </body></opml>
        """
        let data = Data(xml.utf8)
        try await Task.detached(priority: .utility) {
            try data.write(to: url, options: .atomic)
        }.value
    }

    private func makeTrack(for episode: PodcastEpisode) -> Track {
        let state = state(for: episode)
        let localURL = state.downloadedPath.flatMap(URL.init(fileURLWithPath:))
        return Track(
            url: localURL ?? episode.enclosureURL,
            title: episode.title,
            artist: episode.feedAuthor,
            album: episode.feedTitle,
            duration: episode.duration,
            artworkThumb: episode.imageURL?.absoluteString,
            mediaType: episode.isVideo ? .video : .audio,
            playHistoryContentTypeOverride: episode.isVideo ? "video-podcast" : "podcast",
            podcastEpisodeID: episode.id,
            contentType: episode.enclosureType
        )
    }

    private func autoDownloadNewestIfNeeded(feed: PodcastFeed, episodes: [PodcastEpisode]) async {
        guard subscriptions.first(where: { $0.feed.id == feed.id })?.autoDownloadNewest == true,
              let newest = episodes.first,
              state(for: newest).downloadedPath == nil else { return }
        download(newest)
    }

    nonisolated private static func downloadDestination(for episode: PodcastEpisode,
                                                        suggestedFilename: String?) throws -> URL {
        let root = try storageRoot().appendingPathComponent("Downloads", isDirectory: true)
        // `episode.id`, `feedID`, and the server-supplied filename all derive from untrusted feed
        // content (e.g. the RSS <guid>). Sanitize every path component so a value like "../../x"
        // cannot escape the Downloads directory.
        let ext = sanitizedFileToken(fileExtension(suggestedFilename: suggestedFilename, episode: episode))
        return root.appendingPathComponent(sanitizedFileToken(episode.feedID), isDirectory: true)
            .appendingPathComponent(sanitizedFileToken(episode.id))
            .appendingPathExtension(ext)
    }

    /// Picks a file extension from the server-supplied filename (last path component only), falling
    /// back to the enclosure URL's extension and finally a media-type default.
    nonisolated private static func fileExtension(suggestedFilename: String?, episode: PodcastEpisode) -> String {
        if let suggestedFilename {
            let ext = (URL(fileURLWithPath: suggestedFilename).lastPathComponent as NSString).pathExtension
            if let ext = ext.nilIfBlankForPodcast { return ext }
        }
        if let ext = episode.enclosureURL.pathExtension.nilIfBlankForPodcast { return ext }
        return episode.isVideo ? "mp4" : "mp3"
    }

    /// Reduces an untrusted string to a single safe path component: only ASCII alphanumerics, `-`,
    /// and `_` survive (so `/`, `:`, and `.` — and therefore `..` — cannot appear), length-capped
    /// to stay within filesystem limits. Never empty.
    nonisolated private static func sanitizedFileToken(_ raw: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = String(raw.map { allowed.contains($0) ? $0 : "_" })
        let trimmed = mapped.isEmpty ? "item" : mapped
        return String(trimmed.prefix(120))
    }

    nonisolated private static func storageRoot() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appendingPathComponent("NullPlayer/Podcasts", isDirectory: true)
    }

    /// Persists a single episode and its current state (targeted write, not a full-library rewrite).
    private func persistEpisode(_ episode: PodcastEpisode) {
        persistEpisodes([episode])
    }

    /// Persists the given episodes and their known states via the coordinator, which merges in any
    /// newer live playback progress before writing.
    private func persistEpisodes(_ episodes: [PodcastEpisode]) {
        guard !episodes.isEmpty else { return }
        let states = episodes.reduce(into: [String: PodcastEpisodeState]()) { result, episode in
            if let state = episodeStates[episode.id] { result[episode.id] = state }
        }
        PodcastPersistenceCoordinator.shared.saveEpisodes(episodes, states: states)
    }

    private func persistEpisodeAndNotify(_ episode: PodcastEpisode) {
        persistEpisode(episode)
        notifyLibraryChanged()
    }

    private func persistSubscriptionsAndNotify() {
        PodcastPersistenceCoordinator.shared.saveSubscriptions(subscriptions)
        notifyLibraryChanged()
    }

    private func notifyLibraryChanged() {
        NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: self)
    }
}

private final class PodcastOPMLParser: NSObject, XMLParserDelegate {
    struct Outline: Sendable { let title: String?; let url: URL }
    private(set) var feedURLs: [Outline] = []

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName.lowercased() == "outline",
              let raw = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"],
              let url = URL(string: raw) else { return }
        feedURLs.append(Outline(title: attributeDict["title"] ?? attributeDict["text"], url: url))
    }
}

private extension String {
    var nilIfBlankForPodcast: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var xmlEscapedForPodcast: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
