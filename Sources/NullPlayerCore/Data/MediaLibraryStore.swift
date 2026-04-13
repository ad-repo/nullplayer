import Foundation
import Dispatch

/// Cross-platform media library store used by Linux UI and shared browser logic.
/// This implementation is intentionally lightweight for portability and does not rely on AppKit.
public final class MediaLibraryStore {
    public static let shared = MediaLibraryStore()
    public static let playHistoryDidChangeNotification = Notification.Name("PlayHistoryDidChange")

    private let queue = DispatchQueue(label: "NullPlayerCore.MediaLibraryStore")

    private var tracksByPath: [String: LibraryTrack] = [:]
    private var trackRatingsByID: [UUID: Int] = [:]
    private var albumRatingsByID: [String: Int] = [:]
    private var artistRatingsByID: [String: Int] = [:]
    private var watchFolders: Set<URL> = []
    private var scanSignaturesByPath: [String: FileScanSignature] = [:]
    private var opened = false

    private var persistenceURL: URL

    private struct PersistentState: Codable {
        var tracks: [LibraryTrack]
        var trackRatingsByID: [String: Int]
        var albumRatingsByID: [String: Int]
        var artistRatingsByID: [String: Int]
        var watchFolders: [String]
        var scanSignaturesByPath: [String: FileScanSignature]
    }

    public static func makeForTesting() -> MediaLibraryStore {
        MediaLibraryStore(persistenceURL: nil)
    }

    public init(persistenceURL: URL? = nil) {
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL()
    }

    public func open() {
        queue.sync {
            guard !opened else { return }
            resetInMemoryState()
            loadPersistentState()
            opened = true
        }
    }

    public func open(at url: URL) {
        let overrideURL = url.standardizedFileURL
        queue.sync {
            if opened, persistenceURL == overrideURL {
                return
            }
            if opened {
                savePersistentState()
                opened = false
            }
            persistenceURL = overrideURL
            resetInMemoryState()
            loadPersistentState()
            opened = true
        }
    }

    public func close() {
        queue.sync {
            guard opened else { return }
            savePersistentState()
            opened = false
        }
    }

    public func checkpoint() {
        queue.sync {
            savePersistentState()
        }
    }

    public func allTracks() -> [LibraryTrack] {
        queue.sync {
            tracksByPath.values.sorted(by: trackSortByDateAddedDesc)
        }
    }

    public func allMovies() -> [LocalVideo] { [] }
    public func allEpisodes() -> [LocalEpisode] { [] }

    public func allWatchFolders() -> [URL] {
        queue.sync { watchFolders.sorted(by: { $0.path < $1.path }) }
    }

    public func albumRatings() -> [String: Int] {
        queue.sync { albumRatingsByID }
    }

    public func artistRatings() -> [String: Int] {
        queue.sync { artistRatingsByID }
    }

    public func allSignatures() -> [String: FileScanSignature] {
        queue.sync { scanSignaturesByPath }
    }

    public func artistCount() -> Int {
        queue.sync {
            Set(tracksByPath.values.compactMap(primaryArtist(from:))).count
        }
    }

    public func albumCount() -> Int {
        queue.sync {
            buildAlbumSummaries(from: Array(tracksByPath.values)).count
        }
    }

    public func trackCount() -> Int {
        queue.sync { tracksByPath.count }
    }

    public func movieCount() -> Int { 0 }
    public func episodeCount() -> Int { 0 }

    public func artistNames(limit: Int, offset: Int, sort: ModernBrowserSortOption) -> [String] {
        queue.sync {
            let unique = Array(Set(tracksByPath.values.compactMap(primaryArtist(from:))))
            let sorted = sortArtists(unique, by: sort)
            return paged(sorted, limit: limit, offset: offset)
        }
    }

    public func albumSummaries(limit: Int, offset: Int, sort: ModernBrowserSortOption) -> [AlbumSummary] {
        queue.sync {
            let tracks = Array(tracksByPath.values)
            let summaries = sortAlbums(buildAlbumSummaries(from: tracks), by: sort, tracks: tracks)
            return paged(summaries, limit: limit, offset: offset)
        }
    }

    public func albumsForArtist(_ artistName: String) -> [AlbumSummary] {
        queue.sync {
            let all = buildAlbumSummaries(from: Array(tracksByPath.values))
            return all.filter { ($0.artist ?? "Unknown Artist").caseInsensitiveCompare(artistName) == .orderedSame }
        }
    }

    public func albumsForArtistsBatch(_ names: [String]) -> [String: [AlbumSummary]] {
        queue.sync {
            var result: [String: [AlbumSummary]] = [:]
            let all = buildAlbumSummaries(from: Array(tracksByPath.values))
            for name in names {
                result[name] = all.filter { ($0.artist ?? "Unknown Artist").caseInsensitiveCompare(name) == .orderedSame }
            }
            return result
        }
    }

    public func tracksForAlbum(_ albumId: String) -> [LibraryTrack] {
        queue.sync {
            tracksByPath.values
                .filter { albumID(for: $0) == albumId }
                .sorted(by: trackSortByTrackThenTitle)
        }
    }

    public func searchTracks(query: String, limit: Int, offset: Int) -> [LibraryTrack] {
        queue.sync {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            let q = query.lowercased()
            let matches = tracksByPath.values.filter { track in
                track.title.lowercased().contains(q) ||
                (track.artist?.lowercased().contains(q) ?? false) ||
                (track.album?.lowercased().contains(q) ?? false)
            }
            .sorted(by: trackSortByDateAddedDesc)
            return paged(matches, limit: limit, offset: offset)
        }
    }

    public func searchArtistNames(query: String) -> [String] {
        queue.sync {
            let q = query.lowercased()
            let all = Set(tracksByPath.values.compactMap(primaryArtist(from:)))
            return all.filter { $0.lowercased().contains(q) }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    public func searchAlbumSummaries(query: String) -> [AlbumSummary] {
        queue.sync {
            let q = query.lowercased()
            return buildAlbumSummaries(from: Array(tracksByPath.values))
                .filter {
                    $0.name.lowercased().contains(q) ||
                    ($0.artist?.lowercased().contains(q) ?? false)
                }
        }
    }

    public func artistLetterOffsets(sort: ModernBrowserSortOption) -> [String: Int] {
        let artists = artistNames(limit: Int.max, offset: 0, sort: sort)
        return letterOffsets(from: artists)
    }

    public func albumLetterOffsets(sort: ModernBrowserSortOption) -> [String: Int] {
        let albums = albumSummaries(limit: Int.max, offset: 0, sort: sort).map(\.name)
        return letterOffsets(from: albums)
    }

    public func upsertTrack(_ track: LibraryTrack, sig: FileScanSignature?) {
        queue.sync {
            tracksByPath[track.url.path] = track
            if let sig {
                scanSignaturesByPath[track.url.path] = sig
            }
        }
    }

    public func upsertTracks(_ items: [(track: LibraryTrack, sig: FileScanSignature?)]) {
        queue.sync {
            for item in items {
                tracksByPath[item.track.url.path] = item.track
                if let sig = item.sig {
                    scanSignaturesByPath[item.track.url.path] = sig
                }
            }
        }
    }

    public func track(forURL url: URL) -> LibraryTrack? {
        queue.sync { tracksByPath[url.path] }
    }

    public func deleteTrackByPath(_ path: String) {
        queue.sync {
            if let removed = tracksByPath.removeValue(forKey: path) {
                trackRatingsByID.removeValue(forKey: removed.id)
            }
            scanSignaturesByPath.removeValue(forKey: path)
        }
    }

    public func deleteAllTracks() {
        queue.sync {
            tracksByPath.removeAll()
            trackRatingsByID.removeAll()
            scanSignaturesByPath.removeAll()
        }
    }

    public func deleteAllMovies() {}
    public func deleteAllEpisodes() {}

    public func deleteAllMedia() {
        deleteAllTracks()
    }

    public func updateTrackRating(trackId: UUID, rating: Int?) {
        queue.sync {
            trackRatingsByID[trackId] = rating
        }
    }

    public func setAlbumRating(albumId: String, rating: Int?) {
        queue.sync {
            albumRatingsByID[albumId] = rating
        }
    }

    public func setArtistRating(artistId: String, rating: Int?) {
        queue.sync {
            artistRatingsByID[artistId] = rating
        }
    }

    public func insertWatchFolder(_ url: URL) {
        queue.sync {
            _ = watchFolders.insert(url.standardizedFileURL)
        }
    }

    public func deleteWatchFolder(_ path: String) {
        queue.sync {
            let canonical = URL(fileURLWithPath: path).standardizedFileURL
            watchFolders = watchFolders.filter { $0.standardizedFileURL != canonical }
        }
    }

    public func refreshTracksFromWatchFolders(includeVideo: Bool = false) {
        let folders = allWatchFolders()
        guard !folders.isEmpty else {
            checkpoint()
            return
        }

        let result = LocalFileDiscovery.discoverMedia(
            from: folders,
            recursiveDirectories: true,
            includeVideo: includeVideo
        )

        let tracks = result.audioFiles.map { discovered in
            LibraryTrack(
                url: discovered.url,
                title: discovered.url.deletingPathExtension().lastPathComponent,
                duration: 0,
                fileSize: discovered.fileSize,
                dateAdded: Date()
            )
        }

        let entries = tracks.map { track in
            (track: track, sig: result.audioFiles.first(where: { $0.path == track.url.path }).map {
                FileScanSignature(fileSize: $0.fileSize, contentModificationDate: $0.contentModificationDate)
            })
        }

        upsertTracks(entries)
        checkpoint()
    }

    // MARK: - Private

    private func loadPersistentState() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let state = try? JSONDecoder().decode(PersistentState.self, from: data) else {
            return
        }

        var loadedTracks: [String: LibraryTrack] = [:]
        for track in state.tracks {
            loadedTracks[track.url.path] = track
        }
        tracksByPath = loadedTracks
        trackRatingsByID = Dictionary(
            uniqueKeysWithValues: state.trackRatingsByID.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            }
        )
        albumRatingsByID = state.albumRatingsByID
        artistRatingsByID = state.artistRatingsByID
        watchFolders = Set(state.watchFolders.compactMap { URL(string: $0) })
        scanSignaturesByPath = state.scanSignaturesByPath
    }

    private func resetInMemoryState() {
        tracksByPath.removeAll()
        trackRatingsByID.removeAll()
        albumRatingsByID.removeAll()
        artistRatingsByID.removeAll()
        watchFolders.removeAll()
        scanSignaturesByPath.removeAll()
    }

    private func savePersistentState() {
        let state = PersistentState(
            tracks: Array(tracksByPath.values),
            trackRatingsByID: Dictionary(
                uniqueKeysWithValues: trackRatingsByID.map { ($0.key.uuidString, $0.value) }
            ),
            albumRatingsByID: albumRatingsByID,
            artistRatingsByID: artistRatingsByID,
            watchFolders: watchFolders.map(\.absoluteString),
            scanSignaturesByPath: scanSignaturesByPath
        )

        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            fputs("MediaLibraryStore(core): failed to persist state: \(error)\n", stderr)
        }
    }

    private static func defaultPersistenceURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("nullplayer", isDirectory: true)
                .appendingPathComponent("media-library.json")
        }
        let home = env["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("nullplayer", isDirectory: true)
            .appendingPathComponent("media-library.json")
    }

    private func buildAlbumSummaries(from tracks: [LibraryTrack]) -> [AlbumSummary] {
        var grouped: [String: [LibraryTrack]] = [:]
        for track in tracks {
            grouped[albumID(for: track), default: []].append(track)
        }

        return grouped.map { albumID, tracks in
            let first = tracks.first
            return AlbumSummary(
                id: albumID,
                name: first?.album ?? "Unknown Album",
                artist: first.flatMap(primaryArtist(from:)),
                year: tracks.compactMap(\.year).first,
                trackCount: tracks.count
            )
        }
    }

    private func albumID(for track: LibraryTrack) -> String {
        let artist = primaryArtist(from: track) ?? "Unknown Artist"
        let album = track.album ?? "Unknown Album"
        return "\(artist)|\(album)"
    }

    private func primaryArtist(from track: LibraryTrack) -> String? {
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty { return albumArtist }
        if let artist = track.artist, !artist.isEmpty { return artist }
        return nil
    }

    private func sortArtists(_ names: [String], by sort: ModernBrowserSortOption) -> [String] {
        switch sort {
        case .nameAsc, .dateAddedDesc, .dateAddedAsc, .yearDesc, .yearAsc:
            return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .nameDesc:
            return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }
        }
    }

    private func sortAlbums(
        _ summaries: [AlbumSummary],
        by sort: ModernBrowserSortOption,
        tracks: [LibraryTrack]
    ) -> [AlbumSummary] {
        switch sort {
        case .nameAsc:
            return summaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return summaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .dateAddedDesc:
            let latestDates = latestAlbumDates(from: tracks)
            return summaries.sorted { lhs, rhs in
                let lhsDate = latestDates[lhs.id] ?? .distantPast
                let rhsDate = latestDates[rhs.id] ?? .distantPast
                return lhsDate > rhsDate
            }
        case .dateAddedAsc:
            let latestDates = latestAlbumDates(from: tracks)
            return summaries.sorted { lhs, rhs in
                let lhsDate = latestDates[lhs.id] ?? .distantFuture
                let rhsDate = latestDates[rhs.id] ?? .distantFuture
                return lhsDate < rhsDate
            }
        case .yearDesc:
            return summaries.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc:
            return summaries.sorted { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        }
    }

    private func latestAlbumDates(from tracks: [LibraryTrack]) -> [String: Date] {
        var latestByAlbum: [String: Date] = [:]
        for track in tracks {
            let id = albumID(for: track)
            if let current = latestByAlbum[id] {
                if track.dateAdded > current {
                    latestByAlbum[id] = track.dateAdded
                }
            } else {
                latestByAlbum[id] = track.dateAdded
            }
        }
        return latestByAlbum
    }

    private func letterOffsets(from values: [String]) -> [String: Int] {
        var offsets: [String: Int] = [:]
        for (index, name) in values.enumerated() {
            let first = String(name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(1))
            let letter = first.isEmpty ? "#" : first
            if offsets[letter] == nil {
                offsets[letter] = index
            }
        }
        return offsets
    }

    private func paged<T>(_ values: [T], limit: Int, offset: Int) -> [T] {
        let safeOffset = max(0, offset)
        guard safeOffset < values.count else { return [] }
        let end = min(values.count, safeOffset + max(0, limit))
        return Array(values[safeOffset..<end])
    }

    private func trackSortByDateAddedDesc(_ lhs: LibraryTrack, _ rhs: LibraryTrack) -> Bool {
        lhs.dateAdded > rhs.dateAdded
    }

    private func trackSortByTrackThenTitle(_ lhs: LibraryTrack, _ rhs: LibraryTrack) -> Bool {
        let lhsTrackNumber = lhs.trackNumber ?? Int.max
        let rhsTrackNumber = rhs.trackNumber ?? Int.max
        if lhsTrackNumber != rhsTrackNumber {
            return lhsTrackNumber < rhsTrackNumber
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
