import AppKit

/// The artwork fetches both library browser views make the same way, and the one cache they share.
@MainActor
enum LibraryArtwork {
    static let cache = NSCache<NSString, NSImage>()

    /// A row's art cache key and loader, as `LibraryBrowserArt.itemArtwork` returns it.
    typealias ItemArtwork = (cacheKey: String?, load: () async -> NSImage?)

    /// An http(s) image, cached under `cacheNamespace`. A favicon passes without an image MIME type.
    static func remote(urlString: String, cacheNamespace: String) async -> NSImage? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        let cacheKey = NSString(string: "\(cacheNamespace):\(trimmed)")
        if let cached = cache.object(forKey: cacheKey) { return cached }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let looksLikeIcon = url.path.lowercased().hasSuffix(".ico") || mime.contains("icon")
            guard mime.contains("image") || looksLikeIcon else { return nil }
            guard let image = NSImage(data: data) else { return nil }
            cache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }

    /// A station's art: the track's own, then the station icon, then the stream host's favicon.
    static func radio(for track: Track, station: RadioStation? = nil) async -> NSImage? {
        if let thumb = track.artworkThumb,
           let image = await remote(urlString: thumb, cacheNamespace: "radio") {
            return image
        }

        let activeStation = station ?? RadioManager.shared.currentStation
        if let iconURL = activeStation?.iconURL?.absoluteString,
           let image = await remote(urlString: iconURL, cacheNamespace: "radio") {
            return image
        }

        var hosts = Set<String>()
        if let host = track.url.host, !host.isEmpty { hosts.insert(host) }
        if let host = activeStation?.url.host, !host.isEmpty { hosts.insert(host) }

        var candidates: [String] = []
        for host in hosts {
            candidates.append("https://\(host)/favicon.ico")
            if !host.lowercased().hasPrefix("www.") {
                candidates.append("https://www.\(host)/favicon.ico")
            }
            candidates.append("http://\(host)/favicon.ico")
        }

        for candidate in candidates {
            if let image = await remote(urlString: candidate, cacheNamespace: "radio-favicon") {
                return image
            }
        }

        return nil
    }

    /// The Primary image of a Jellyfin item (an `artworkItemId`).
    static func jellyfin(itemId: String) async -> NSImage? {
        await serverImage(cacheKey: "jellyfin:\(itemId)",
                          url: JellyfinManager.shared.imageURL(itemId: itemId, imageTag: nil, size: 400))
    }

    /// The Primary image of an Emby item (an `artworkItemId`).
    static func emby(itemId: String) async -> NSImage? {
        await serverImage(cacheKey: "emby:\(itemId)",
                          url: EmbyManager.shared.imageURL(itemId: itemId, imageTag: nil, size: 400))
    }

    /// A Jellyfin row's art, from its `artworkItemId` (nil when the item has no picture).
    static func jellyfinItem(_ itemId: String?) -> ItemArtwork {
        guard let itemId else { return (nil, { nil }) }
        return ("jellyfin:\(itemId)", { await jellyfin(itemId: itemId) })
    }

    /// An Emby row's art, from its `artworkItemId` (nil when the item has no picture).
    static func embyItem(_ itemId: String?) -> ItemArtwork {
        guard let itemId else { return (nil, { nil }) }
        return ("emby:\(itemId)", { await emby(itemId: itemId) })
    }

    /// A Plex image by its thumb path, sent with the Plex streaming headers.
    static func plex(thumb: String, cacheKey: String) async -> NSImage? {
        var request = PlexManager.shared.artworkURL(thumb: thumb, size: 400).map { URLRequest(url: $0) }
        for (key, value) in PlexManager.shared.streamingHeaders ?? [:] {
            request?.setValue(value, forHTTPHeaderField: key)
        }
        return await serverImage(cacheKey: cacheKey, request: request)
    }

    /// A Subsonic cover by its cover-art id.
    static func subsonic(coverArt: String, cacheKey: String) async -> NSImage? {
        await serverImage(cacheKey: cacheKey,
                          url: SubsonicManager.shared.coverArtURL(coverArtId: coverArt, size: 400))
    }

    /// The image cached under `key`, else `load`'s, cached when it finds one.
    static func cached(_ key: String, _ load: () async -> NSImage?) async -> NSImage? {
        let cacheKey = NSString(string: key)
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let image = await load() else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    /// An album cover from the iTunes Search API, for a track with no art of its own.
    static func web(artist: String?, album: String?, title: String?) async -> NSImage? {
        let searchTerm: String
        if let artist, !artist.isEmpty, let album, !album.isEmpty {
            searchTerm = "\(artist) \(album)"
        } else if let artist, !artist.isEmpty, let title, !title.isEmpty {
            searchTerm = "\(artist) \(title)"
        } else if let album, !album.isEmpty {
            searchTerm = album
        } else {
            return nil
        }

        let cacheKey = NSString(string: "web:\(searchTerm)")
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=album&limit=1") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let artworkURL = first["artworkUrl100"] as? String,
                  // 600x600 instead of the 100x100 the search returns.
                  let highRes = URL(string: artworkURL.replacingOccurrences(of: "100x100", with: "600x600")) else {
                return nil
            }
            let (imageData, _) = try await URLSession.shared.data(from: highRes)
            guard let image = NSImage(data: imageData) else { return nil }
            cache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            NSLog("LibraryArtwork: Failed to load web artwork: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            return nil
        }
    }

    /// A movie poster from TMDb, for a movie with no art of its own.
    static func moviePoster(title: String, year: Int?) async -> NSImage? {
        // Build search query
        var searchTerm = title
        if let year = year {
            searchTerm += " \(year)"
        }
        
        // Check cache first
        let cacheKey = NSString(string: "tmdb:\(searchTerm)")
        if let cached = LibraryArtwork.cache.object(forKey: cacheKey) {
            return cached
        }
        
        // URL encode the search term
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Use TMDb Search API
        // Note: This uses the public search endpoint which works without authentication for basic queries
        var urlString = "https://api.themoviedb.org/3/search/movie?query=\(encoded)"
        if let year = year {
            urlString += "&year=\(year)"
        }
        
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            var request = URLRequest(url: url)
            // TMDb requires an API key - use the read-only public key for search
            // This is a standard read-only key that allows basic search functionality
            request.setValue("Bearer eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJlNjUyZmJjMjE3NTcxYTZjNzU4NmYwNzE1MWQ4ZmRjOCIsInN1YiI6IjY1YjUyYTc3MGYyZmJkMDE3YzQ0OGU1OSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.tWcXq_3A4N4gP4Jz5MJNqVWfHBNZdEbwLZZGpZU9hTw", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Parse JSON response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let firstResult = results.first,
               let posterPath = firstResult["poster_path"] as? String {
                
                // Fetch poster image (w500 is a good size for display)
                let posterUrlString = "https://image.tmdb.org/t/p/w500\(posterPath)"
                
                if let posterUrl = URL(string: posterUrlString) {
                    let (imageData, _) = try await URLSession.shared.data(from: posterUrl)
                    if let image = NSImage(data: imageData) {
                        // Cache the result
                        LibraryArtwork.cache.setObject(image, forKey: cacheKey)
                        NSLog("LibraryArtwork: Loaded TMDb poster for: %@", title)
                        return image
                    }
                }
            }
        } catch {
            NSLog("LibraryArtwork: Failed to load TMDb poster: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
        }
        
        return nil
    }

    private static func serverImage(cacheKey: String, url: URL?) async -> NSImage? {
        await serverImage(cacheKey: cacheKey, request: url.map { URLRequest(url: $0) })
    }

    private static func serverImage(cacheKey: String, request: URLRequest?) async -> NSImage? {
        await cached(cacheKey) {
            guard let request, let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NSImage(data: data)
        }
    }
}
