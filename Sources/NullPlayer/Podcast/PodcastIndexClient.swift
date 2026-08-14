import CryptoKit
import Foundation

struct PodcastIndexCredentials: Codable, Equatable, Sendable {
    var apiKey: String
    var apiSecret: String

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum PodcastIndexError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(Int, String?)
    case credentialsRequired
    case noPlayableEpisodes

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Podcast Index returned an invalid URL."
        case .invalidResponse: return "Podcast Index returned an unreadable response."
        case .http(let status, let detail):
            return detail?.isEmpty == false ? "Podcast Index error \(status): \(detail!)" : "Podcast Index error \(status)."
        case .credentialsRequired: return "Podcast Index API credentials are required for this feature."
        case .noPlayableEpisodes: return "This feed does not contain playable audio or video episodes."
        }
    }
}

final class PodcastIndexClient {
    static let shared = PodcastIndexClient()

    private let apiBase = URL(string: "https://api.podcastindex.org/api/1.0")!
    private let publicBase = URL(string: "https://api.podcastindex.org")!
    private let userAgent = "NullPlayer/1.0 (PodcastIndex.org)"

    /// Shared session with request/resource timeouts so a stalled or deliberately slow feed can't
    /// hang a fetch indefinitely; combined with `maxResponseBytes` this bounds a hostile server.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    /// Ceiling for in-memory feed/JSON/artwork responses. Real feeds are well under 1 MB; anything
    /// past this is rejected rather than parsed, so a malicious server can't force a huge allocation.
    static let maxResponseBytes = 25 * 1024 * 1024

    /// Receives a response incrementally and abandons the underlying URLSession task as soon as
    /// it crosses the in-memory ceiling. `data(for:)` cannot provide this guarantee because it
    /// buffers the complete body before returning.
    static func boundedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maxResponseBytes) {
            throw PodcastIndexError.invalidResponse
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maxResponseBytes))
        }
        for try await byte in bytes {
            guard data.count < maxResponseBytes else { throw PodcastIndexError.invalidResponse }
            data.append(byte)
        }
        return (data, response)
    }

    static func boundedData(from url: URL) async throws -> (Data, URLResponse) {
        try await boundedData(for: URLRequest(url: url))
    }

    var credentials: PodcastIndexCredentials? {
        KeychainHelper.shared.getPodcastIndexCredentials()
    }

    func search(term: String, max: Int = 60) async throws -> [PodcastFeed] {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if credentials?.isConfigured == true {
            return try await authenticatedFeeds(path: "search/byterm", query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "max", value: String(max)),
                URLQueryItem(name: "clean", value: nil)
            ])
        }
        return try await publicSearch(term: query)
    }

    func episodes(for feed: PodcastFeed, max: Int = 300) async throws -> [PodcastEpisode] {
        if let indexId = feed.indexId, credentials?.isConfigured == true {
            do {
                var components = URLComponents(url: apiBase.appendingPathComponent("episodes/byfeedid"),
                                               resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "id", value: String(indexId)),
                    URLQueryItem(name: "max", value: String(max)),
                    URLQueryItem(name: "fulltext", value: nil)
                ]
                guard let url = components.url else { throw PodcastIndexError.invalidURL }
                let response: EpisodeResponse = try await authenticated(url: url)
                let mapped = response.items.compactMap { $0.makeEpisode(feed: feed) }
                if !mapped.isEmpty { return mapped }
            } catch {
                NSLog("PodcastIndexClient: episode API failed; falling back to RSS: %@", error.localizedDescription)
            }
        }
        let parsed = try await RSSPodcastParser.load(feed: feed)
        guard !parsed.isEmpty else { throw PodcastIndexError.noPlayableEpisodes }
        return Array(parsed.prefix(max))
    }

    func feed(forURL url: URL) async throws -> PodcastFeed {
        if credentials?.isConfigured == true {
            var components = URLComponents(url: apiBase.appendingPathComponent("podcasts/byfeedurl"),
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
            if let requestURL = components.url {
                struct Response: Decodable { let feed: FeedDTO }
                if let response: Response = try? await authenticated(url: requestURL),
                   let feed = response.feed.makeFeed() {
                    return feed
                }
            }
        }
        return try await RSSPodcastParser.loadFeed(url: url)
    }

    private func authenticatedFeeds(path: String, query: [URLQueryItem]) async throws -> [PodcastFeed] {
        var components = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw PodcastIndexError.invalidURL }
        let response: FeedResponse = try await authenticated(url: url)
        return response.feeds.compactMap { $0.makeFeed() }
    }

    private func publicSearch(term: String) async throws -> [PodcastFeed] {
        var components = URLComponents(url: publicBase.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "term", value: term)]
        guard let url = components.url else { throw PodcastIndexError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await perform(request)
        let response = try JSONDecoder().decode(PublicSearchResponse.self, from: data)
        return response.results.compactMap { $0.makeFeed() }
    }

    private func authenticated<T: Decodable>(url: URL) async throws -> T {
        guard let credentials, credentials.isConfigured else {
            throw PodcastIndexError.credentialsRequired
        }
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let authSource = credentials.apiKey + credentials.apiSecret + timestamp
        let digest = Insecure.SHA1.hash(data: Data(authSource.utf8))
        let authorization = digest.map { String(format: "%02x", $0) }.joined()
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue(timestamp, forHTTPHeaderField: "X-Auth-Date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            NSLog("PodcastIndexClient decode failure: %@", error.localizedDescription)
            throw PodcastIndexError.invalidResponse
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await Self.boundedData(for: request)
        guard let http = response as? HTTPURLResponse else { throw PodcastIndexError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            // Log the server's error body for diagnostics only. Surfacing it in the UI banner would
            // let a malicious feed/proxy inject arbitrary text, so the thrown error omits it.
            if let detail = String(data: data, encoding: .utf8)?.prefix(300), !detail.isEmpty {
                NSLog("PodcastIndexClient: HTTP %d body: %@", http.statusCode, String(detail))
            }
            throw PodcastIndexError.http(http.statusCode, nil)
        }
        return data
    }
}

private struct FeedResponse: Decodable { let feeds: [FeedDTO] }
private struct EpisodeResponse: Decodable { let items: [EpisodeDTO] }

private struct FeedDTO: Decodable {
    let id: Int64?
    let title: String?
    let url: String?
    let originalUrl: String?
    let link: String?
    let description: String?
    let author: String?
    let ownerName: String?
    let image: String?
    let artwork: String?
    let language: String?
    let episodeCount: Int?
    let explicit: Bool?
    let categories: [String: String]?

    func makeFeed() -> PodcastFeed? {
        guard let rawURL = url ?? originalUrl, let feedURL = URL(string: rawURL),
              feedURL.isPodcastRemoteURL, let title, !title.isEmpty else { return nil }
        return PodcastFeed(
            indexId: id, title: title, author: author ?? ownerName, summary: description,
            feedURL: feedURL, websiteURL: link.flatMap(URL.init(string:)),
            imageURL: (image ?? artwork).flatMap(URL.init(string:)),
            categories: categories?.values.sorted() ?? [], language: language,
            episodeCount: episodeCount, explicit: explicit ?? false
        )
    }
}

private struct EpisodeDTO: Decodable {
    let id: Int64?
    let title: String?
    let description: String?
    let guid: String?
    let link: String?
    let datePublished: TimeInterval?
    let duration: TimeInterval?
    let enclosureUrl: String?
    let enclosureType: String?
    let enclosureLength: Int64?
    let image: String?
    let feedImage: String?
    let explicit: Int?

    func makeEpisode(feed: PodcastFeed) -> PodcastEpisode? {
        guard let title, let enclosureUrl, let url = URL(string: enclosureUrl),
              url.isPodcastRemoteURL else { return nil }
        return PodcastEpisode(
            indexId: id, guid: guid, feed: feed, title: title, summary: description,
            publishedAt: datePublished.map(Date.init(timeIntervalSince1970:)), duration: duration,
            enclosureURL: url, enclosureType: enclosureType, enclosureLength: enclosureLength,
            imageURL: (image ?? feedImage).flatMap(URL.init(string:)),
            websiteURL: link.flatMap(URL.init(string:)), explicit: explicit == 1
        )
    }
}

private struct PublicSearchResponse: Decodable {
    let results: [PublicFeedDTO]
}

private struct PublicFeedDTO: Decodable {
    let collectionId: Int64?
    let collectionName: String?
    let artistName: String?
    let feedUrl: String?
    let collectionViewUrl: String?
    let artworkUrl600: String?
    let artworkUrl100: String?
    let genres: [String]?
    let trackCount: Int?
    let trackExplicitness: String?

    func makeFeed() -> PodcastFeed? {
        guard let collectionName, let feedUrl, let url = URL(string: feedUrl),
              url.isPodcastRemoteURL else { return nil }
        // The Apple-compatible endpoint exposes an Apple collection id, not necessarily
        // Podcast Index's internal feed id, so keep indexId nil and use RSS for episodes.
        return PodcastFeed(
            title: collectionName, author: artistName, feedURL: url,
            websiteURL: collectionViewUrl.flatMap(URL.init(string:)),
            imageURL: (artworkUrl600 ?? artworkUrl100).flatMap(URL.init(string:)),
            categories: genres ?? [], episodeCount: trackCount,
            explicit: trackExplicitness?.lowercased() == "explicit"
        )
    }
}

final class RSSPodcastParser: NSObject, XMLParserDelegate {
    private let seed: PodcastFeed?
    private var channelTitle = ""
    private var channelAuthor = ""
    private var channelSummary = ""
    private var channelLink: URL?
    private var channelImage: URL?
    private var channelLanguage: String?
    private var currentElement = ""
    private var buffer = ""
    private var insideItem = false
    private var item: Item?
    private(set) var episodes: [PodcastEpisode] = []

    private struct Item {
        var title = ""
        var guid: String?
        var summary = ""
        var publishedAt: Date?
        var duration: TimeInterval?
        var enclosureURL: URL?
        var enclosureType: String?
        var enclosureLength: Int64?
        var imageURL: URL?
        var link: URL?
        var explicit = false
    }

    init(seed: PodcastFeed?) { self.seed = seed }

    static func load(feed: PodcastFeed) async throws -> [PodcastEpisode] {
        guard feed.feedURL.isPodcastRemoteURL else { throw PodcastIndexError.invalidURL }
        let (data, response) = try await PodcastIndexClient.boundedData(from: feed.feedURL)
        guard (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? true else {
            throw PodcastIndexError.invalidResponse
        }
        return try parse(data: data, feed: feed)
    }

    static func parse(data: Data, feed: PodcastFeed) throws -> [PodcastEpisode] {
        let delegate = RSSPodcastParser(seed: feed)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? PodcastIndexError.invalidResponse }
        return delegate.episodes.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    static func loadFeed(url: URL) async throws -> PodcastFeed {
        guard url.isPodcastRemoteURL else { throw PodcastIndexError.invalidURL }
        let placeholder = PodcastFeed(title: url.host ?? "Podcast", feedURL: url)
        let (data, response) = try await PodcastIndexClient.boundedData(from: url)
        guard (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? true else {
            throw PodcastIndexError.invalidResponse
        }
        let delegate = RSSPodcastParser(seed: placeholder)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? PodcastIndexError.invalidResponse }
        return PodcastFeed(
            title: delegate.channelTitle.isEmpty ? (url.host ?? "Podcast") : delegate.channelTitle,
            author: delegate.channelAuthor, summary: delegate.channelSummary, feedURL: url,
            websiteURL: delegate.channelLink, imageURL: delegate.channelImage,
            language: delegate.channelLanguage, episodeCount: delegate.episodes.count
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        buffer = ""
        if currentElement == "item" || currentElement == "entry" {
            insideItem = true; item = Item()
        } else if currentElement == "enclosure", insideItem {
            // Only accept remote http(s) enclosures — a crafted file:// enclosure must never
            // reach playback, download, or casting.
            if let raw = attributeDict["url"], let url = URL(string: raw), url.isPodcastRemoteURL {
                item?.enclosureURL = url
                item?.enclosureType = attributeDict["type"]
                item?.enclosureLength = attributeDict["length"].flatMap(Int64.init)
            }
        } else if currentElement.hasSuffix("image"), let href = attributeDict["href"], let url = URL(string: href) {
            if insideItem { item?.imageURL = url } else { channelImage = url }
        } else if currentElement == "link", let href = attributeDict["href"], let url = URL(string: href) {
            if insideItem {
                let rel = attributeDict["rel"]?.lowercased()
                if rel == "enclosure" {
                    guard url.isPodcastRemoteURL else { return }
                    item?.enclosureURL = url
                    item?.enclosureType = attributeDict["type"]
                    item?.enclosureLength = attributeDict["length"].flatMap(Int64.init)
                } else { item?.link = url }
            } else { channelLink = url }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        buffer += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if insideItem {
            switch element {
            case "title": item?.title = value
            case "guid", "id": item?.guid = value
            case "description", "summary", "content:encoded": if !value.isEmpty { item?.summary = value }
            case "pubdate", "published", "updated": item?.publishedAt = Self.parseDate(value)
            case "itunes:duration", "duration": item?.duration = Self.parseDuration(value)
            case "link": if item?.link == nil { item?.link = URL(string: value) }
            case "itunes:explicit", "explicit": item?.explicit = ["yes", "true", "1", "explicit"].contains(value.lowercased())
            case "item", "entry": finishItem(); insideItem = false; item = nil
            default: break
            }
        } else {
            switch element {
            case "title": if channelTitle.isEmpty { channelTitle = value }
            case "itunes:author", "author": if channelAuthor.isEmpty { channelAuthor = value }
            case "description", "subtitle": if channelSummary.isEmpty { channelSummary = value }
            case "language": channelLanguage = value
            case "link": if channelLink == nil { channelLink = URL(string: value) }
            case "url": if channelImage == nil { channelImage = URL(string: value) }
            default: break
            }
        }
        buffer = ""
    }

    private func finishItem() {
        guard let item, let enclosureURL = item.enclosureURL else { return }
        let feed = seed ?? PodcastFeed(title: channelTitle, author: channelAuthor,
                                       summary: channelSummary, feedURL: enclosureURL,
                                       websiteURL: channelLink, imageURL: channelImage,
                                       language: channelLanguage)
        episodes.append(PodcastEpisode(
            guid: item.guid, feed: feed, title: item.title, summary: item.summary,
            publishedAt: item.publishedAt, duration: item.duration, enclosureURL: enclosureURL,
            enclosureType: item.enclosureType, enclosureLength: item.enclosureLength,
            imageURL: item.imageURL, websiteURL: item.link, explicit: item.explicit
        ))
    }

    private static func parseDuration(_ value: String) -> TimeInterval? {
        if let direct = TimeInterval(value), !value.contains(":") { return direct }
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reversed().enumerated().reduce(0) { total, pair in
            total + pair.element * pow(60, Double(pair.offset))
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
