import Foundation
import AVFoundation
import AppKit
import SQLite

/// Represents an entry in the media library with full metadata
struct LibraryTrack: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var discNumber: Int?
    var duration: TimeInterval
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var fileSize: Int64
    var dateAdded: Date
    var lastPlayed: Date?
    var playCount: Int
    var rating: Int?             // User rating on 0-10 scale (matching Plex), nil if unrated
    var composer: String?
    var comment: String?
    var grouping: String?
    var bpm: Int?
    var musicalKey: String?
    var isrc: String?
    var copyright: String?
    var musicBrainzRecordingID: String?
    var musicBrainzReleaseID: String?
    var discogsReleaseID: Int?
    var discogsMasterID: Int?
    var discogsLabel: String?
    var discogsCatalogNumber: String?
    var artworkURL: String?

    /// Transient — populated from `track_artists` table, not persisted via Codable.
    var artists: [(name: String, role: ArtistRole)] = []

    private enum CodingKeys: String, CodingKey {
        case id, url, title, artist, album, albumArtist, genre, year
        case trackNumber, discNumber, duration, bitrate, sampleRate, channels
        case fileSize, dateAdded, lastPlayed, playCount, rating
        case composer, comment, grouping, bpm, musicalKey, isrc, copyright
        case musicBrainzRecordingID, musicBrainzReleaseID
        case discogsReleaseID, discogsMasterID, discogsLabel, discogsCatalogNumber
        case artworkURL
        // `artists` is intentionally omitted — transient, re-populated from track_artists
    }

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.duration = 0
        self.fileSize = 0
        self.dateAdded = Date()
        self.playCount = 0
    }
    
    init(id: UUID = UUID(),
         url: URL,
         title: String,
         artist: String? = nil,
         album: String? = nil,
         albumArtist: String? = nil,
         genre: String? = nil,
         year: Int? = nil,
         trackNumber: Int? = nil,
         discNumber: Int? = nil,
         duration: TimeInterval = 0,
         bitrate: Int? = nil,
         sampleRate: Int? = nil,
         channels: Int? = nil,
         fileSize: Int64 = 0,
         dateAdded: Date = Date(),
         lastPlayed: Date? = nil,
         playCount: Int = 0,
         rating: Int? = nil,
         composer: String? = nil,
         comment: String? = nil,
         grouping: String? = nil,
         bpm: Int? = nil,
         musicalKey: String? = nil,
         isrc: String? = nil,
         copyright: String? = nil,
         musicBrainzRecordingID: String? = nil,
         musicBrainzReleaseID: String? = nil,
         discogsReleaseID: Int? = nil,
         discogsMasterID: Int? = nil,
         discogsLabel: String? = nil,
         discogsCatalogNumber: String? = nil,
         artworkURL: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.playCount = playCount
        self.rating = rating
        self.composer = composer
        self.comment = comment
        self.grouping = grouping
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.isrc = isrc
        self.copyright = copyright
        self.musicBrainzRecordingID = musicBrainzRecordingID
        self.musicBrainzReleaseID = musicBrainzReleaseID
        self.discogsReleaseID = discogsReleaseID
        self.discogsMasterID = discogsMasterID
        self.discogsLabel = discogsLabel
        self.discogsCatalogNumber = discogsCatalogNumber
        self.artworkURL = artworkURL
    }
    
    /// Display title (artist - title or just title)
    /// Sanitizes newlines and control characters for proper display
    var displayTitle: String {
        let result: String
        if let artist = artist, !artist.isEmpty {
            result = "\(artist) - \(title)"
        } else {
            result = title
        }
        // Remove newlines and other control characters that break playlist display
        return result.replacingOccurrences(of: "\n", with: " ")
                     .replacingOccurrences(of: "\r", with: " ")
                     .replacingOccurrences(of: "\t", with: " ")
    }
    
    /// Formatted duration string (MM:SS)
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Convert to Track for playback
    func toTrack() -> Track {
        return Track(
            id: id,
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels,
            genre: genre
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Equatable conformance (custom to exclude `artists`)

    static func == (lhs: LibraryTrack, rhs: LibraryTrack) -> Bool {
        lhs.id == rhs.id &&
        lhs.url == rhs.url &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.albumArtist == rhs.albumArtist &&
        lhs.genre == rhs.genre &&
        lhs.year == rhs.year &&
        lhs.trackNumber == rhs.trackNumber &&
        lhs.discNumber == rhs.discNumber &&
        lhs.duration == rhs.duration &&
        lhs.bitrate == rhs.bitrate &&
        lhs.sampleRate == rhs.sampleRate &&
        lhs.channels == rhs.channels &&
        lhs.fileSize == rhs.fileSize &&
        lhs.dateAdded == rhs.dateAdded &&
        lhs.lastPlayed == rhs.lastPlayed &&
        lhs.playCount == rhs.playCount &&
        lhs.rating == rhs.rating &&
        lhs.composer == rhs.composer &&
        lhs.comment == rhs.comment &&
        lhs.grouping == rhs.grouping &&
        lhs.bpm == rhs.bpm &&
        lhs.musicalKey == rhs.musicalKey &&
        lhs.isrc == rhs.isrc &&
        lhs.copyright == rhs.copyright &&
        lhs.musicBrainzRecordingID == rhs.musicBrainzRecordingID &&
        lhs.musicBrainzReleaseID == rhs.musicBrainzReleaseID &&
        lhs.discogsReleaseID == rhs.discogsReleaseID &&
        lhs.discogsMasterID == rhs.discogsMasterID &&
        lhs.discogsLabel == rhs.discogsLabel &&
        lhs.discogsCatalogNumber == rhs.discogsCatalogNumber &&
        lhs.artworkURL == rhs.artworkURL
        // `artists` is not compared — it's transient
    }

    mutating func rebuildArtistRoles() {
        // Primary/featured roles from the artist tag.
        artists = ArtistSplitter.split(artist ?? "", isAlbumArtist: false)

        // album_artist role rows — mirrors coalesce(albumArtist, artist, 'Unknown Artist') fallback.
        let albumArtistRows: [(name: String, role: ArtistRole)]
        if let albumArtist, !albumArtist.isEmpty {
            albumArtistRows = ArtistSplitter.split(albumArtist, isAlbumArtist: true)
        } else if let artist, !artist.isEmpty {
            albumArtistRows = ArtistSplitter.split(artist, isAlbumArtist: true)
        } else {
            albumArtistRows = [(name: "Unknown Artist", role: .albumArtist)]
        }
        artists.append(contentsOf: albumArtistRows)
    }

}

/// Represents an album in the library
struct Album: Identifiable, Hashable {
    let id: String  // "artist|album" key
    let name: String
    let artist: String?
    let year: Int?
    var tracks: [LibraryTrack]
    
    var displayName: String {
        if let artist = artist, !artist.isEmpty {
            return "\(artist) - \(name)"
        }
        return name
    }
    
    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
    
    var formattedDuration: String {
        let totalSeconds = Int(totalDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, totalSeconds % 60)
        }
        return String(format: "%d:%02d", minutes, totalSeconds % 60)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Represents an artist in the library
struct Artist: Identifiable, Hashable {
    let id: String  // Artist name as key
    let name: String
    var albums: [Album]
    
    var trackCount: Int {
        albums.reduce(0) { $0 + $1.tracks.count }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Lightweight summary of an album for paginated display (no tracks loaded).
struct AlbumSummary: Identifiable {
    let id: String       // "albumArtist|album" key
    let name: String
    let artist: String?
    let year: Int?
    let trackCount: Int
}

/// Represents a local video file (movie) in the library
struct LocalVideo: Identifiable, Codable {
    let id: UUID
    let url: URL
    var title: String
    var year: Int?
    var duration: TimeInterval
    var fileSize: Int64
    var dateAdded: Date

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.duration = 0
        self.fileSize = 0
        self.dateAdded = Date()
    }

    init(id: UUID, url: URL, title: String, year: Int?, duration: TimeInterval, fileSize: Int64, dateAdded: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.year = year
        self.duration = duration
        self.fileSize = fileSize
        self.dateAdded = dateAdded
    }

    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, totalSeconds % 60)
        }
        return String(format: "%d:%02d", minutes, totalSeconds % 60)
    }
}

/// Represents a local TV episode in the library
struct LocalEpisode: Identifiable, Codable {
    let id: UUID
    let url: URL
    var title: String
    var showTitle: String
    var seasonNumber: Int      // Defaults to 1 if unknown
    var episodeNumber: Int?
    var duration: TimeInterval
    var fileSize: Int64
    var dateAdded: Date

    init(url: URL, showTitle: String, seasonNumber: Int = 1, episodeNumber: Int? = nil) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.duration = 0
        self.fileSize = 0
        self.dateAdded = Date()
    }

    init(id: UUID, url: URL, title: String, showTitle: String, seasonNumber: Int, episodeNumber: Int?,
         duration: TimeInterval, fileSize: Int64, dateAdded: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.duration = duration
        self.fileSize = fileSize
        self.dateAdded = dateAdded
    }

    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, totalSeconds % 60)
        }
        return String(format: "%d:%02d", minutes, totalSeconds % 60)
    }
}

/// A season within a local TV show (derived grouping, not persisted directly)
struct LocalSeason {
    let number: Int
    var episodes: [LocalEpisode]
}

/// A TV show grouping in the local library (derived, not persisted directly)
struct LocalShow: Identifiable {
    let id: String  // show title used as stable key
    let title: String
    var seasons: [LocalSeason]

    var episodeCount: Int {
        seasons.reduce(0) { $0 + $1.episodes.count }
    }
}

/// Sort options for library browsing
enum LibrarySortOption: String, CaseIterable, Codable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case dateAdded = "Date Added"
    case duration = "Duration"
    case playCount = "Play Count"
}

/// Filter options for library browsing
struct LibraryFilter: Codable {
    var searchText: String = ""
    var artists: Set<String> = []
    var albums: Set<String> = []
    var genres: Set<String> = []
    var yearRange: ClosedRange<Int>?
    
    var isEmpty: Bool {
        searchText.isEmpty && artists.isEmpty && albums.isEmpty && genres.isEmpty && yearRange == nil
    }
}

/// Per-watch-folder library counts used by folder-management UI.
struct WatchFolderSummary {
    let url: URL
    let trackCount: Int
    let movieCount: Int
    let episodeCount: Int

    var totalCount: Int { trackCount + movieCount + episodeCount }
}

struct FileScanSignature: Codable, Hashable {
    let fileSize: Int64
    let contentModificationDate: Date?
}

/// The main media library manager
class MediaLibrary {
    
    // MARK: - Singleton
    
    static let shared = MediaLibrary()
    
    // MARK: - Properties
    
    /// Serial queue to guard library state (tracks, movies, episodes, signatures)
    private let dataQueue = DispatchQueue(label: "NullPlayer.MediaLibrary.data")

    /// Separate queue for ratings — must NOT share dataQueue because draw() calls
    /// albumRating/artistRating on the main thread, and dataQueue is held for extended
    /// periods during import (O(N) pass, batch flushes), which blocks every frame.
    private let ratingsQueue = DispatchQueue(label: "NullPlayer.MediaLibrary.ratings")
    
    /// All tracks in the library (guarded by dataQueue)
    private var tracks: [LibraryTrack] = []
    
    /// Indexed by URL path for quick lookup (guarded by dataQueue)
    private var tracksByPath: [String: LibraryTrack] = [:]
    
    /// Watch folders for automatic scanning (guarded by dataQueue)
    private var watchFolders: [URL] = []

    /// All local video files (movies) (guarded by dataQueue)
    private var movies: [LocalVideo] = []

    /// All local TV episodes (guarded by dataQueue)
    private var episodes: [LocalEpisode] = []

    /// URL-path index for quick video lookup (guarded by dataQueue)
    private var moviesByPath: [String: LocalVideo] = [:]
    private var episodesByPath: [String: LocalEpisode] = [:]

    /// Album and artist ratings keyed by id (guarded by ratingsQueue, NOT dataQueue)
    private var albumRatings: [String: Int] = [:]   // Key: album.id ("artist|album")
    private var artistRatings: [String: Int] = [:]  // Key: artist.id (artist name)

    /// Incremental scan signatures keyed by file path (guarded by dataQueue)
    private var scanSignaturesByPath: [String: FileScanSignature] = [:]

    /// Library file location
    private let libraryURL: URL
    
    /// Whether the library is currently scanning (main thread only)
    private(set) var isScanning = false

    /// Scan progress (0.0 - 1.0) (main thread only)
    private(set) var scanProgress: Double = 0

    /// Incremented whenever a clear is requested; in-flight scans check this to discard stale results (main thread only)
    private var scanGeneration: Int = 0

    /// Throttle scan progress notifications to avoid excessive UI churn.
    private var lastScanProgressEmitTime: CFAbsoluteTime = 0
    private var lastScanProgressValue: Double = 0

    private let store = MediaLibraryStore.shared

    private let scanProgressStateQueue = DispatchQueue(label: "NullPlayer.MediaLibrary.scanProgressState")
    
    /// Notification names
    static let libraryDidChangeNotification = Notification.Name("MediaLibraryDidChange")
    static let scanProgressNotification = Notification.Name("MediaLibraryScanProgress")
    static let trackRatingDidChangeNotification = Notification.Name("MediaLibraryTrackRatingDidChange")
    
    // MARK: - Initialization
    
    private init() {
        // Create library directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let libraryDir = appSupport.appendingPathComponent("NullPlayer", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        
        libraryURL = libraryDir.appendingPathComponent("library.db")

        store.open()
        loadLibrary()

        // Trigger backfill if v2→v3 migration ran and track_artists are not yet populated
        if !UserDefaults.standard.bool(forKey: "trackArtistsBackfillComplete") {
            store.backfillTrackArtistsIfNeeded {
                self.loadLibrary()
                NotificationCenter.default.post(name: MediaLibrary.libraryDidChangeNotification, object: nil)
            }
        }
    }

    // MARK: - Thread-Safe Accessors
    
    var tracksSnapshot: [LibraryTrack] {
        dataQueue.sync { tracks }
    }
    
    var watchFoldersSnapshot: [URL] {
        dataQueue.sync { watchFolders }
    }

    /// Summaries for each watched folder with local-library item counts by type.
    func watchFolderSummaries() -> [WatchFolderSummary] {
        let folders = watchFoldersSnapshot
        let tracks = tracksSnapshot
        let movies = moviesSnapshot
        let episodes = episodesSnapshot

        // Pre-compute paths once outside the per-folder loop. Tracks are scanned from the
        // already-normalized watch folder URL, so url.path is already resolved — calling
        // resolvingSymlinksInPath() inside the loop (O(N×M) filesystem hits) hangs the
        // window on large libraries backed by network volumes.
        let folderPaths = folders.map { Self.normalizedPath(for: $0) }
        let trackPaths   = tracks.map   { $0.url.path }
        let moviePaths   = movies.map   { $0.url.path }
        let episodePaths = episodes.map { $0.url.path }

        return zip(folders, folderPaths).map { folder, folderPath in
            let trackCount   = trackPaths.reduce(0)   { $0 + (Self.isPath($1, insideFolderPath: folderPath) ? 1 : 0) }
            let movieCount   = moviePaths.reduce(0)   { $0 + (Self.isPath($1, insideFolderPath: folderPath) ? 1 : 0) }
            let episodeCount = episodePaths.reduce(0) { $0 + (Self.isPath($1, insideFolderPath: folderPath) ? 1 : 0) }
            return WatchFolderSummary(url: folder, trackCount: trackCount,
                                     movieCount: movieCount, episodeCount: episodeCount)
        }.sorted {
            $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
        }
    }

    /// Returns the number of entries that would be removed if this watch folder is removed
    /// with `removeEntries = true` (overlap-safe with remaining watch folders).
    func removalCountsForWatchFolder(_ url: URL) -> (tracks: Int, movies: Int, episodes: Int) {
        let removedFolderPath = Self.normalizedPath(for: url)
        return dataQueue.sync {
            let remainingFolderPaths = watchFolders
                .map { Self.normalizedPath(for: $0) }
                .filter { $0 != removedFolderPath }

            let trackCount = tracks.reduce(0) { count, track in
                let path = Self.normalizedPath(for: track.url)
                return count + (Self.shouldRemovePath(
                    path,
                    whenRemovingFolderPath: removedFolderPath,
                    remainingFolderPaths: remainingFolderPaths
                ) ? 1 : 0)
            }

            let movieCount = movies.reduce(0) { count, movie in
                let path = Self.normalizedPath(for: movie.url)
                return count + (Self.shouldRemovePath(
                    path,
                    whenRemovingFolderPath: removedFolderPath,
                    remainingFolderPaths: remainingFolderPaths
                ) ? 1 : 0)
            }

            let episodeCount = episodes.reduce(0) { count, episode in
                let path = Self.normalizedPath(for: episode.url)
                return count + (Self.shouldRemovePath(
                    path,
                    whenRemovingFolderPath: removedFolderPath,
                    remainingFolderPaths: remainingFolderPaths
                ) ? 1 : 0)
            }

            return (trackCount, movieCount, episodeCount)
        }
    }

    var moviesSnapshot: [LocalVideo] {
        dataQueue.sync { movies }
    }

    var episodesSnapshot: [LocalEpisode] {
        dataQueue.sync { episodes }
    }

    /// Returns all TV shows derived by grouping episodes by show title → season → episode number.
    func allShows() -> [LocalShow] {
        let snapshot = dataQueue.sync { episodes }
        var grouped: [String: [Int: [LocalEpisode]]] = [:]
        for ep in snapshot {
            grouped[ep.showTitle, default: [:]][ep.seasonNumber, default: []].append(ep)
        }
        return grouped.map { showTitle, seasonMap in
            let seasons = seasonMap.sorted { $0.key < $1.key }.map { num, eps in
                LocalSeason(number: num, episodes: eps.sorted {
                    ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0)
                })
            }
            return LocalShow(id: showTitle, title: showTitle, seasons: seasons)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Library Management
    
    /// Add a single track to the library (quick validates file before adding)
    /// Set skipValidation to true for internal use when validation was already done
    @discardableResult
    func addTrack(url: URL, skipValidation: Bool = false) -> LibraryTrack? {
        let path = url.path

        // Quick check under lock
        if let existing = dataQueue.sync(execute: { tracksByPath[path] }) {
            return existing
        }
        
        // Quick validate file (existence + extension check - fast)
        if !skipValidation {
            if let error = AudioFileValidator.quickValidate(url: url) {
                NSLog("MediaLibrary: Skipping invalid file '%@': %@", url.lastPathComponent, error)
                return nil
            }
        }
        
        // Create track with metadata outside lock
        var track = LibraryTrack(url: url)
        parseMetadata(for: &track)
        let signature = signatureFromFileSystem(url: url, fallbackFileSize: track.fileSize)
        
        var didAdd = false
        var result: LibraryTrack?
        
        dataQueue.sync {
            if let existing = tracksByPath[path] {
                result = existing
                return
            }
            
            tracks.append(track)
            tracksByPath[path] = track
            if let signature {
                scanSignaturesByPath[path] = signature
            }
            result = track
            didAdd = true
        }
        
        if didAdd {
            store.upsertTrack(track, sig: signature)
            notifyChange()
        }

        return result
    }

    /// Add multiple tracks to the library (quick validates all files first)
    func addTracks(urls: [URL]) {
        guard !urls.isEmpty else { return }

        // Quick validate all files first (existence + extension - fast)
        let validation = AudioFileValidator.quickValidate(urls: urls)

        // Notify about invalid files
        if validation.hasInvalidFiles {
            AudioFileValidator.notifyInvalidFiles(validation.invalidFiles)
        }

        guard !validation.validURLs.isEmpty else { return }
        importMedia(
            urls: validation.validURLs,
            recursiveDirectories: false,
            includeVideo: false,
            isLibraryScan: false,
            cleanMissingFolderPaths: []
        )
    }
    
    /// Remove a track from the library
    func removeTrack(_ track: LibraryTrack) {
        dataQueue.sync {
            tracks.removeAll { $0.id == track.id }
            tracksByPath.removeValue(forKey: track.url.path)
            scanSignaturesByPath.removeValue(forKey: track.url.path)
        }
        store.deleteTrackByPath(track.url.path)
        notifyChange()
    }

    /// Remove tracks by URL
    func removeTracks(urls: [URL]) {
        let pathsToRemove = Set(urls.map(\.path))
        guard !pathsToRemove.isEmpty else { return }

        dataQueue.sync {
            tracks.removeAll { pathsToRemove.contains($0.url.path) }
            for path in pathsToRemove {
                tracksByPath.removeValue(forKey: path)
                scanSignaturesByPath.removeValue(forKey: path)
            }
        }
        for path in pathsToRemove { store.deleteTrackByPath(path) }
        notifyChange()
    }
    
    /// Clear all local media entries from the library (tracks, movies, episodes).
    /// Watch folders are preserved.
    func clearLibrary() {
        NSLog("MediaLibrary: Clearing entire library")
        scanGeneration += 1
        cancelScanIfActive()
        dataQueue.sync {
            tracks.removeAll()
            tracksByPath.removeAll()
            movies.removeAll()
            moviesByPath.removeAll()
            episodes.removeAll()
            episodesByPath.removeAll()
            scanSignaturesByPath.removeAll()
        }
        ratingsQueue.sync {
            albumRatings.removeAll()
            artistRatings.removeAll()
        }
        store.deleteAllMedia()
        notifyChange()
    }

    /// Clear music entries only (tracks + track-derived ratings).
    /// Movies, TV episodes, and watch folders are preserved.
    func clearMusicLibrary() {
        NSLog("MediaLibrary: Clearing music library")
        scanGeneration += 1
        cancelScanIfActive()
        dataQueue.sync {
            tracks.removeAll()
            tracksByPath.removeAll()
            scanSignaturesByPath = scanSignaturesByPath.filter { path, _ in
                moviesByPath[path] != nil || episodesByPath[path] != nil
            }
        }
        ratingsQueue.sync {
            albumRatings.removeAll()
            artistRatings.removeAll()
        }
        store.deleteAllTracks()
        notifyChange()
    }

    /// Clear movie entries only.
    /// Music tracks, TV episodes, and watch folders are preserved.
    func clearMovieLibrary() {
        NSLog("MediaLibrary: Clearing movie library")
        scanGeneration += 1
        cancelScanIfActive()
        dataQueue.sync {
            movies.removeAll()
            moviesByPath.removeAll()
            scanSignaturesByPath = scanSignaturesByPath.filter { path, _ in
                tracksByPath[path] != nil || episodesByPath[path] != nil
            }
        }
        store.deleteAllMovies()
        notifyChange()
    }

    /// Clear TV entries only (episodes/shows).
    /// Music tracks, movies, and watch folders are preserved.
    func clearTVLibrary() {
        NSLog("MediaLibrary: Clearing TV library")
        scanGeneration += 1
        cancelScanIfActive()
        dataQueue.sync {
            episodes.removeAll()
            episodesByPath.removeAll()
            scanSignaturesByPath = scanSignaturesByPath.filter { path, _ in
                tracksByPath[path] != nil || moviesByPath[path] != nil
            }
        }
        store.deleteAllEpisodes()
        notifyChange()
    }
    
    /// Update play statistics for a track
    func recordPlay(for track: LibraryTrack) {
        var updatedTrack: LibraryTrack?
        dataQueue.sync {
            guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
            tracks[index].playCount += 1
            tracks[index].lastPlayed = Date()
            tracksByPath[track.url.path] = tracks[index]
            updatedTrack = tracks[index]
        }
        if let t = updatedTrack {
            store.updatePlayStats(trackId: t.id, playCount: t.playCount, lastPlayed: t.lastPlayed ?? Date())
        }
    }
    
    /// Set the rating for a track
    /// - Parameters:
    ///   - trackId: The UUID of the track to rate
    ///   - rating: Rating on 0-10 scale (matching Plex), or nil to clear
    func setRating(for trackId: UUID, rating: Int?) {
        var didUpdate = false
        dataQueue.sync {
            guard let index = tracks.firstIndex(where: { $0.id == trackId }) else { return }
            tracks[index].rating = rating
            tracksByPath[tracks[index].url.path] = tracks[index]
            didUpdate = true
        }
        if didUpdate {
            store.updateTrackRating(trackId: trackId, rating: rating)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.trackRatingDidChangeNotification, object: trackId)
            }
        }
    }
    
    func albumRating(for albumId: String) -> Int? {
        ratingsQueue.sync { albumRatings[albumId] }
    }

    func artistRating(for artistId: String) -> Int? {
        ratingsQueue.sync { artistRatings[artistId] }
    }

    func setAlbumRating(albumId: String, rating: Int?) {
        ratingsQueue.sync {
            if let rating = rating { albumRatings[albumId] = rating }
            else { albumRatings.removeValue(forKey: albumId) }
        }
        store.setAlbumRating(albumId: albumId, rating: rating)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: nil)
        }
    }

    func setArtistRating(artistId: String, rating: Int?) {
        ratingsQueue.sync {
            if let rating = rating { artistRatings[artistId] = rating }
            else { artistRatings.removeValue(forKey: artistId) }
        }
        store.setArtistRating(artistId: artistId, rating: rating)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: nil)
        }
    }

    /// Update a track's metadata in the library (in-app only, no file write-back)
    func updateTrack(_ track: LibraryTrack) {
        var normalizedTrack = track
        normalizedTrack.rebuildArtistRoles()
        var sig: FileScanSignature?
        var foundInMemory = false
        dataQueue.sync {
            if let index = tracks.firstIndex(where: { $0.id == normalizedTrack.id }) {
                tracks[index] = normalizedTrack
                foundInMemory = true
            } else if let index = tracks.firstIndex(where: { $0.url.path == normalizedTrack.url.path }) {
                tracks[index] = normalizedTrack
                foundInMemory = true
            }
            if foundInMemory {
                tracksByPath[normalizedTrack.url.path] = normalizedTrack
                sig = signatureFromFileSystem(url: normalizedTrack.url, fallbackFileSize: normalizedTrack.fileSize)
                if let s = sig { scanSignaturesByPath[normalizedTrack.url.path] = s }
            }
        }
        if !foundInMemory {
            // In-memory miss: browser edit panels can be opened before the cache loads a track.
            // Only append and persist if the row still exists in the DB — this prevents an editor
            // saving a stale snapshot from recreating a row that was deleted since the panel opened.
            guard store.track(forURL: normalizedTrack.url) != nil else { return }
            dataQueue.sync {
                tracks.append(normalizedTrack)
                tracksByPath[normalizedTrack.url.path] = normalizedTrack
                sig = signatureFromFileSystem(url: normalizedTrack.url, fallbackFileSize: normalizedTrack.fileSize)
                if let s = sig { scanSignaturesByPath[normalizedTrack.url.path] = s }
            }
        }
        store.upsertTrack(normalizedTrack, sig: sig)
        notifyChange()
    }

    /// Update a movie's metadata in the library (in-app only, no file write-back)
    func updateMovie(_ movie: LocalVideo) {
        var sig: FileScanSignature?
        var didUpdate = false
        dataQueue.sync {
            guard let index = movies.firstIndex(where: { $0.id == movie.id }) else { return }
            movies[index] = movie; moviesByPath[movie.url.path] = movie
            sig = signatureFromFileSystem(url: movie.url, fallbackFileSize: movie.fileSize)
            if let s = sig { scanSignaturesByPath[movie.url.path] = s }
            didUpdate = true
        }
        if didUpdate { store.upsertMovie(movie, sig: sig); notifyChange() }
    }

    /// Update an episode's metadata in the library (in-app only, no file write-back)
    func updateEpisode(_ episode: LocalEpisode) {
        var sig: FileScanSignature?
        var didUpdate = false
        dataQueue.sync {
            guard let index = episodes.firstIndex(where: { $0.id == episode.id }) else { return }
            episodesByPath.removeValue(forKey: episodes[index].url.path)
            episodes[index] = episode; episodesByPath[episode.url.path] = episode
            sig = signatureFromFileSystem(url: episode.url, fallbackFileSize: episode.fileSize)
            if let s = sig { scanSignaturesByPath[episode.url.path] = s }
            didUpdate = true
        }
        if didUpdate { store.upsertEpisode(episode, sig: sig); notifyChange() }
    }

    /// Remove a movie from the library (file is not deleted)
    func removeMovie(_ movie: LocalVideo) {
        removeMovies(urls: [movie.url])
    }

    /// Remove movies by URL
    func removeMovies(urls: [URL]) {
        let pathsToRemove = Set(urls.map(\.path))
        guard !pathsToRemove.isEmpty else { return }

        dataQueue.sync {
            movies.removeAll { pathsToRemove.contains($0.url.path) }
            for path in pathsToRemove {
                moviesByPath.removeValue(forKey: path)
                scanSignaturesByPath.removeValue(forKey: path)
            }
        }
        for path in pathsToRemove { store.deleteMovieByPath(path) }
        notifyChange()
    }

    /// Remove an episode from the library (file is not deleted)
    func removeEpisode(_ episode: LocalEpisode) {
        removeEpisodes(urls: [episode.url])
    }

    /// Remove episodes by URL
    func removeEpisodes(urls: [URL]) {
        let pathsToRemove = Set(urls.map(\.path))
        guard !pathsToRemove.isEmpty else { return }

        dataQueue.sync {
            episodes.removeAll { pathsToRemove.contains($0.url.path) }
            for path in pathsToRemove {
                episodesByPath.removeValue(forKey: path)
                scanSignaturesByPath.removeValue(forKey: path)
            }
        }
        for path in pathsToRemove { store.deleteEpisodeByPath(path) }
        notifyChange()
    }

    /// Remove all episodes for a given show title from the library
    func removeShow(title: String) {
        var pathsToRemove: [String] = []
        dataQueue.sync {
            let toRemove = episodes.filter { $0.showTitle == title }
            toRemove.forEach {
                episodesByPath.removeValue(forKey: $0.url.path)
                scanSignaturesByPath.removeValue(forKey: $0.url.path)
                pathsToRemove.append($0.url.path)
            }
            episodes.removeAll { $0.showTitle == title }
        }
        for path in pathsToRemove { store.deleteEpisodeByPath(path) }
        notifyChange()
    }

    /// Remove all episodes for a given season of a show from the library
    func removeSeason(showTitle: String, seasonNumber: Int) {
        var pathsToRemove: [String] = []
        dataQueue.sync {
            let toRemove = episodes.filter { $0.showTitle == showTitle && $0.seasonNumber == seasonNumber }
            toRemove.forEach {
                episodesByPath.removeValue(forKey: $0.url.path)
                scanSignaturesByPath.removeValue(forKey: $0.url.path)
                pathsToRemove.append($0.url.path)
            }
            episodes.removeAll { $0.showTitle == showTitle && $0.seasonNumber == seasonNumber }
        }
        for path in pathsToRemove { store.deleteEpisodeByPath(path) }
        notifyChange()
    }

    /// Find a library track by its file URL
    func findTrack(byURL url: URL) -> LibraryTrack? {
        dataQueue.sync { tracksByPath[url.path] }
    }
    
    // MARK: - Folder Scanning

    /// Return a canonical filesystem URL representation for watch-folder matching.
    static func normalizedWatchFolderURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Return canonical path string for matching.
    static func normalizedPath(for url: URL) -> String {
        normalizedWatchFolderURL(url).path
    }

    /// Whether a file path is in (or equals) a folder path.
    static func isPath(_ filePath: String, insideFolderPath folderPath: String) -> Bool {
        if folderPath == "/" { return true }
        return filePath == folderPath || filePath.hasPrefix(folderPath + "/")
    }

    /// Whether a file path is inside any folder path in the provided list.
    static func isPath(_ filePath: String, insideAnyFolderPaths folderPaths: [String]) -> Bool {
        folderPaths.contains { isPath(filePath, insideFolderPath: $0) }
    }

    /// Folder-removal policy for path-level cleanup.
    static func shouldRemovePath(
        _ filePath: String,
        whenRemovingFolderPath removedFolderPath: String,
        remainingFolderPaths: [String]
    ) -> Bool {
        guard isPath(filePath, insideFolderPath: removedFolderPath) else { return false }
        return !isPath(filePath, insideAnyFolderPaths: remainingFolderPaths)
    }
    
    /// Add a watch folder
    func addWatchFolder(_ url: URL) {
        let normalized = Self.normalizedWatchFolderURL(url)
        let normalizedPath = Self.normalizedPath(for: normalized)
        var didAdd = false
        dataQueue.sync {
            let alreadyPresent = watchFolders.contains {
                Self.normalizedPath(for: $0) == normalizedPath
            }
            if !alreadyPresent {
                watchFolders.append(normalized)
                didAdd = true
            }
        }
        if didAdd {
            NSLog("MediaLibrary: Added watch folder: %@", normalized.path)
            store.insertWatchFolder(normalized)
        }
    }
    
    /// Remove a watch folder while keeping existing indexed entries for compatibility.
    func removeWatchFolder(_ url: URL) {
        removeWatchFolder(url, removeEntries: false)
    }

    /// Remove a watch folder
    func removeWatchFolder(_ url: URL, removeEntries: Bool) {
        let removedFolderPath = Self.normalizedPath(for: url)
        var didMutateWatchFolders = false
        var removalCounts = (tracks: 0, movies: 0, episodes: 0)

        dataQueue.sync {
            let originalCount = watchFolders.count
            watchFolders.removeAll {
                Self.normalizedPath(for: $0) == removedFolderPath
            }
            didMutateWatchFolders = watchFolders.count != originalCount

            guard removeEntries, didMutateWatchFolders else { return }

            let remainingFolderPaths = watchFolders.map { Self.normalizedPath(for: $0) }

            tracks.removeAll { track in
                let normalizedTrackPath = Self.normalizedPath(for: track.url)
                guard Self.shouldRemovePath(
                    normalizedTrackPath,
                    whenRemovingFolderPath: removedFolderPath,
                    remainingFolderPaths: remainingFolderPaths
                ) else { return false }
                tracksByPath.removeValue(forKey: track.url.path)
                scanSignaturesByPath.removeValue(forKey: track.url.path)
                removalCounts.tracks += 1
                return true
            }

            movies.removeAll { movie in
                let normalizedMoviePath = Self.normalizedPath(for: movie.url)
                guard Self.shouldRemovePath(
                    normalizedMoviePath,
                    whenRemovingFolderPath: removedFolderPath,
                    remainingFolderPaths: remainingFolderPaths
                ) else { return false }
                moviesByPath.removeValue(forKey: movie.url.path)
                scanSignaturesByPath.removeValue(forKey: movie.url.path)
                removalCounts.movies += 1
                return true
            }

            episodes.removeAll { episode in
                let normalizedEpisodePath = Self.normalizedPath(for: episode.url)
                guard Self.shouldRemovePath(
                    normalizedEpisodePath,
                    whenRemovingFolderPath: removedFolderPath,
                    remainingFolderPaths: remainingFolderPaths
                ) else { return false }
                episodesByPath.removeValue(forKey: episode.url.path)
                scanSignaturesByPath.removeValue(forKey: episode.url.path)
                removalCounts.episodes += 1
                return true
            }
        }

        guard didMutateWatchFolders else { return }

        NSLog("MediaLibrary: Removed watch folder: %@ (removed entries: %d tracks, %d movies, %d episodes)",
              removedFolderPath, removalCounts.tracks, removalCounts.movies, removalCounts.episodes)
        store.deleteWatchFolder(removedFolderPath)

        if removeEntries,
           (removalCounts.tracks > 0 || removalCounts.movies > 0 || removalCounts.episodes > 0) {
            notifyChange()
        }
    }
    
    /// Adds individual video files to the library (movies or episodes based on classification).
    func addVideoFiles(urls: [URL]) {
        for url in urls {
            scanVideoFile(at: url, signature: signatureFromFileSystem(url: url))
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: nil)
        }
    }

    /// Scan a folder incrementally using discover -> diff -> process.
    func scanFolder(_ url: URL, recursive: Bool = true) {
        let normalized = Self.normalizedWatchFolderURL(url)
        importMedia(
            urls: [normalized],
            recursiveDirectories: recursive,
            includeVideo: true,
            isLibraryScan: true,
            cleanMissingFolderPaths: [Self.normalizedPath(for: normalized)]
        )
    }
    
    /// Rescan one watch folder.
    func rescanWatchFolder(_ url: URL, cleanMissing: Bool = true) {
        let normalized = Self.normalizedWatchFolderURL(url)
        let cleanPaths = cleanMissing ? [Self.normalizedPath(for: normalized)] : []
        importMedia(
            urls: [normalized],
            recursiveDirectories: true,
            includeVideo: true,
            isLibraryScan: true,
            cleanMissingFolderPaths: cleanPaths
        )
    }

    /// Rescan all watch folders.
    func rescanWatchFolders(cleanMissing: Bool = true) {
        let folders = watchFoldersSnapshot.map { Self.normalizedWatchFolderURL($0) }
        guard !folders.isEmpty else { return }
        let cleanPaths = cleanMissing ? folders.map { Self.normalizedPath(for: $0) } : []
        importMedia(
            urls: folders,
            recursiveDirectories: true,
            includeVideo: true,
            isLibraryScan: true,
            cleanMissingFolderPaths: cleanPaths
        )
    }

    /// Cancels an in-flight library scan by resetting isScanning and notifying observers.
    /// Must be called on the main thread after incrementing scanGeneration.
    private func cancelScanIfActive() {
        guard isScanning else { return }
        isScanning = false
        scanProgress = 0
        NotificationCenter.default.post(name: Self.scanProgressNotification, object: 0.0)
    }

    private func importMedia(
        urls: [URL],
        recursiveDirectories: Bool,
        includeVideo: Bool,
        isLibraryScan: Bool,
        cleanMissingFolderPaths: [String]
    ) {
        guard !urls.isEmpty else { return }
        if isLibraryScan, isScanning { return }

        let generation = scanGeneration
        if isLibraryScan {
            NSLog("MediaLibrary: Starting library scan of %d folder(s)", urls.count)
            scanProgressStateQueue.sync {
                lastScanProgressEmitTime = 0
                lastScanProgressValue = 0
            }
            DispatchQueue.main.async {
                self.isScanning = true
                self.scanProgress = 0
                NotificationCenter.default.post(name: Self.scanProgressNotification, object: 0.0)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if isLibraryScan, self.scanGeneration != generation { return }

            var audioMetadataTasks: [LocalDiscoveredMediaFile] = []
            var videoRescanTasks: [LocalDiscoveredMediaFile] = []
            var skippedCount = 0
            var didQuickMutate = false
            var cleanedTrackPaths: [String] = []
            var cleanedMoviePaths: [String] = []
            var cleanedEpisodePaths: [String] = []
            var quickAddedTracks: [(track: LibraryTrack, sig: FileScanSignature?)] = []
            var discoveredPaths = Set<String>()

            // Stream discovery: process audio in 500-file batches as the enumerator yields them.
            // Tracks appear in the library immediately rather than waiting for full enumeration.
            let discovery = LocalFileDiscovery.discoverMediaStreaming(
                from: urls,
                recursiveDirectories: recursiveDirectories,
                includeVideo: includeVideo,
                includeLegacyWMA: isLibraryScan,
                audioBatchSize: 500
            ) { audioBatch in
                if isLibraryScan, self.scanGeneration != generation { return }
                discoveredPaths.formUnion(audioBatch.map(\.path))

                var batchAdded: [(track: LibraryTrack, sig: FileScanSignature?)] = []
                self.dataQueue.sync {
                    for file in audioBatch {
                        let signature = self.signature(for: file)
                        if self.tracksByPath[file.path] == nil {
                            let track = self.makeFastTrack(from: file)
                            self.tracks.append(track)
                            self.tracksByPath[file.path] = track
                            self.scanSignaturesByPath[file.path] = signature
                            audioMetadataTasks.append(file)
                            batchAdded.append((track: track, sig: nil))
                        } else if self.scanSignaturesByPath[file.path] == signature {
                            skippedCount += 1
                        } else {
                            if let idx = self.tracks.firstIndex(where: { $0.url.path == file.path }) {
                                var existing = self.tracks[idx]
                                existing.fileSize = file.fileSize
                                self.tracks[idx] = existing
                                self.tracksByPath[file.path] = existing
                            }
                            self.scanSignaturesByPath[file.path] = signature
                            audioMetadataTasks.append(file)
                        }
                    }
                }

                if !batchAdded.isEmpty {
                    quickAddedTracks.append(contentsOf: batchAdded)
                    self.store.upsertTracks(batchAdded)
                    didQuickMutate = true
                    self.notifyChangeCoalesced()
                }
            }

            NSLog("MediaLibrary: Discovery complete — %d audio, %d video files found", discovery.audioFiles.count, discovery.videoFiles.count)
            discoveredPaths.formUnion(discovery.videoFiles.map(\.path))
            let cleanFolderPathSet = Set(cleanMissingFolderPaths)
            let cleanFolderPaths = Array(cleanFolderPathSet)

            // Safety guard: if discovery found nothing at all but folders previously had content,
            // the volume is likely unreachable (NAS offline, SMB mount stale, etc.). Skip cleanup
            // to avoid wiping the entire library on a transient network failure.
            let existingCountInFolders: Int = self.dataQueue.sync {
                guard !cleanFolderPaths.isEmpty else { return 0 }
                let trackCount = self.tracks.filter { Self.isPath(Self.normalizedPath(for: $0.url), insideAnyFolderPaths: cleanFolderPaths) }.count
                let movieCount = self.movies.filter { Self.isPath(Self.normalizedPath(for: $0.url), insideAnyFolderPaths: cleanFolderPaths) }.count
                let episodeCount = self.episodes.filter { Self.isPath(Self.normalizedPath(for: $0.url), insideAnyFolderPaths: cleanFolderPaths) }.count
                return trackCount + movieCount + episodeCount
            }
            if discoveredPaths.isEmpty && existingCountInFolders > 0 {
                NSLog("MediaLibrary: Scan returned 0 files but folders had %d existing entries — skipping cleanup (volume may be unreachable)", existingCountInFolders)
                // Still need to finish scan bookkeeping below, just without removing anything.
            }
            let skipCleanup = discoveredPaths.isEmpty && existingCountInFolders > 0

            // Cleanup pass: remove stale files from watched folders (runs after full discovery
            // so discoveredPaths is complete). New tracks already visible from streaming above.
            self.dataQueue.sync {
                if !cleanFolderPathSet.isEmpty && !skipCleanup {
                    self.tracks.removeAll { track in
                        let normalizedTrackPath = Self.normalizedPath(for: track.url)
                        guard Self.isPath(normalizedTrackPath, insideAnyFolderPaths: cleanFolderPaths),
                              !discoveredPaths.contains(track.url.path) else { return false }
                        self.tracksByPath.removeValue(forKey: track.url.path)
                        self.scanSignaturesByPath.removeValue(forKey: track.url.path)
                        cleanedTrackPaths.append(track.url.path)
                        didQuickMutate = true
                        return true
                    }
                    self.movies.removeAll { movie in
                        let normalizedMoviePath = Self.normalizedPath(for: movie.url)
                        guard Self.isPath(normalizedMoviePath, insideAnyFolderPaths: cleanFolderPaths),
                              !discoveredPaths.contains(movie.url.path) else { return false }
                        self.moviesByPath.removeValue(forKey: movie.url.path)
                        self.scanSignaturesByPath.removeValue(forKey: movie.url.path)
                        cleanedMoviePaths.append(movie.url.path)
                        didQuickMutate = true
                        return true
                    }
                    self.episodes.removeAll { episode in
                        let normalizedEpisodePath = Self.normalizedPath(for: episode.url)
                        guard Self.isPath(normalizedEpisodePath, insideAnyFolderPaths: cleanFolderPaths),
                              !discoveredPaths.contains(episode.url.path) else { return false }
                        self.episodesByPath.removeValue(forKey: episode.url.path)
                        self.scanSignaturesByPath.removeValue(forKey: episode.url.path)
                        cleanedEpisodePaths.append(episode.url.path)
                        didQuickMutate = true
                        return true
                    }
                }

                for file in discovery.videoFiles {
                    let signature = self.signature(for: file)
                    let hasVideoEntry = self.moviesByPath[file.path] != nil || self.episodesByPath[file.path] != nil
                    if hasVideoEntry && self.scanSignaturesByPath[file.path] == signature {
                        skippedCount += 1
                        continue
                    }

                    if hasVideoEntry {
                        self.movies.removeAll { $0.url.path == file.path }
                        self.moviesByPath.removeValue(forKey: file.path)
                        self.episodes.removeAll { $0.url.path == file.path }
                        self.episodesByPath.removeValue(forKey: file.path)
                        cleanedMoviePaths.append(file.path)
                        cleanedEpisodePaths.append(file.path)
                        didQuickMutate = true
                    }

                    self.scanSignaturesByPath[file.path] = signature
                    videoRescanTasks.append(file)
                }
            }

            // Persist cleanup removals to DB and notify
            if !cleanedTrackPaths.isEmpty || !cleanedMoviePaths.isEmpty || !cleanedEpisodePaths.isEmpty {
                for path in cleanedTrackPaths { self.store.deleteTrackByPath(path) }
                for path in cleanedMoviePaths { self.store.deleteMovieByPath(path) }
                for path in cleanedEpisodePaths { self.store.deleteEpisodeByPath(path) }
                self.notifyChangeCoalesced()
            }

            if didQuickMutate {
                NSLog("MediaLibrary: Quick pass — added %d tracks, removed %d tracks/%d movies/%d episodes",
                      quickAddedTracks.count, cleanedTrackPaths.count, cleanedMoviePaths.count, cleanedEpisodePaths.count)
            }

            let totalDiscovered = max(discovery.audioFiles.count + discovery.videoFiles.count, 1)
            let progressCounterQueue = DispatchQueue(label: "NullPlayer.MediaLibrary.importProgress")
            var processedCount = skippedCount
            let markProcessed: (Int) -> Void = { delta in
                progressCounterQueue.sync {
                    processedCount += delta
                    if isLibraryScan {
                        self.emitScanProgress(generation: generation, processed: processedCount, total: totalDiscovered, force: false)
                    }
                }
            }

            if isLibraryScan {
                self.emitScanProgress(generation: generation, processed: processedCount, total: totalDiscovered, force: true)
            }

            var didVideoMutate = false
            for file in videoRescanTasks {
                if isLibraryScan, self.scanGeneration != generation { break }
                self.scanVideoFile(at: file.url, signature: self.signature(for: file))
                didVideoMutate = true
                markProcessed(1)
            }

            let metadataWorkerCount = self.metadataWorkerCount(for: urls)
            let metadataSemaphore = DispatchSemaphore(value: metadataWorkerCount)
            let metadataGroup = DispatchGroup()
            let metadataResultsQueue = DispatchQueue(label: "NullPlayer.MediaLibrary.metadataResults")
            var pendingMetadata: [(track: LibraryTrack, signature: FileScanSignature)] = []
            let metadataFlushBatchSize = 500
            var didMetadataMutate = false

            // Must be called on metadataResultsQueue (serial queue) to avoid races on pendingMetadata
            let flushPendingMetadata: () -> Void = {
                let batch = pendingMetadata
                pendingMetadata.removeAll(keepingCapacity: true)
                guard !batch.isEmpty, !isLibraryScan || self.scanGeneration == generation else { return }
                didMetadataMutate = true
                // Update dict (O(1) per track) — skip the O(N) firstIndex array scan here.
                // The tracks array is synced in a single O(N) pass after metadataGroup.wait().
                self.dataQueue.sync {
                    for result in batch {
                        let path = result.track.url.path
                        self.tracksByPath[path] = result.track
                        self.scanSignaturesByPath[path] = result.signature
                    }
                }
                let dbBatch = batch.map { (track: $0.track, sig: Optional($0.signature)) }
                self.store.upsertTracks(dbBatch)
                NSLog("MediaLibrary: Flushed %d enriched tracks to DB", batch.count)
                self.notifyChangeCoalesced()
            }

            for file in audioMetadataTasks {
                metadataGroup.enter()
                metadataSemaphore.wait()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        metadataSemaphore.signal()
                        markProcessed(1)
                        metadataGroup.leave()
                    }
                    if isLibraryScan, self.scanGeneration != generation { return }
                    var track = self.dataQueue.sync {
                        self.tracksByPath[file.path] ?? self.makeFastTrack(from: file)
                    }
                    track.fileSize = file.fileSize
                    autoreleasepool {
                        self.parseMetadata(for: &track)
                    }
                    let signature = self.signature(for: file)
                    metadataResultsQueue.sync {
                        pendingMetadata.append((track: track, signature: signature))
                        if pendingMetadata.count >= metadataFlushBatchSize {
                            flushPendingMetadata()
                        }
                    }
                }
            }

            metadataGroup.wait()

            // Flush any remaining tracks not yet written
            metadataResultsQueue.sync {
                flushPendingMetadata()
            }

            // Sync tracks array from tracksByPath in one O(N) pass.
            // flushPendingMetadata updated only the dict (O(1) per track) to avoid the
            // O(N) firstIndex scan per flush that made this O(N²) overall for large libraries.
            if didMetadataMutate {
                self.dataQueue.sync {
                    for i in 0..<self.tracks.count {
                        let path = self.tracks[i].url.path
                        if let enriched = self.tracksByPath[path] {
                            self.tracks[i] = enriched
                        }
                    }
                }
            }
            NSLog("MediaLibrary: Metadata enrichment complete — all tracks flushed")

            if didVideoMutate || didMetadataMutate {
                self.notifyChangeCoalesced()
            }

            let didMutate = didQuickMutate || didVideoMutate || didMetadataMutate
            if didMutate {
                self.notifyChange()
            }

            if isLibraryScan {
                let totalTracks = self.dataQueue.sync { self.tracks.count }
                NSLog("MediaLibrary: Scan complete — %d total tracks in library (skipped %d unchanged)", totalTracks, skippedCount)
                self.emitScanProgress(generation: generation, processed: totalDiscovered, total: totalDiscovered, force: true)
                DispatchQueue.main.async {
                    guard self.scanGeneration == generation else { return }
                    self.isScanning = false
                    self.scanProgress = 1
                    NotificationCenter.default.post(name: Self.scanProgressNotification, object: 1.0)
                }
            }
        }
    }
    
    // MARK: - Querying
    
    /// Get all unique artists
    func allArtists() -> [Artist] {
        var artistDict: [String: [LibraryTrack]] = [:]
        for track in tracksSnapshot {
            let albumArtistNames = track.artists
                .filter { $0.role == .albumArtist }
                .map { $0.name }
            // Fallback to raw albumArtist/artist if artists not yet populated (e.g. quick-add pass)
            let effectiveNames = albumArtistNames.isEmpty
                ? [track.albumArtist ?? track.artist ?? "Unknown Artist"]
                : albumArtistNames
            for name in effectiveNames {
                artistDict[name, default: []].append(track)
            }
        }
        return artistDict.map { name, tracks in
            let albums = albumsForTracks(tracks)
            return Artist(id: name, name: name, albums: albums)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Get all unique albums
    func allAlbums() -> [Album] {
        var albumDict: [String: [LibraryTrack]] = [:]
        for track in tracksSnapshot {
            let albumName = track.album ?? "Unknown Album"
            let artistName = track.albumArtist ?? track.artist ?? "Unknown Artist"
            let key = "\(artistName)|\(albumName)"
            albumDict[key, default: []].append(track)
        }
        
        return albumDict.map { key, tracks in
            let firstTrack = tracks.first
            return Album(
                id: key,
                name: firstTrack?.album ?? "Unknown Album",
                artist: firstTrack?.albumArtist ?? firstTrack?.artist,
                year: firstTrack?.year,
                tracks: tracks.sorted {
                    // Sort by disc number first, then track number
                    let disc0 = $0.discNumber ?? 1
                    let disc1 = $1.discNumber ?? 1
                    if disc0 != disc1 { return disc0 < disc1 }
                    return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0)
                }
            )
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    /// Get all unique genres
    func allGenres() -> [String] {
        let genres = Set(tracksSnapshot.compactMap { $0.genre })
        return genres.sorted()
    }
    
    /// Search tracks
    func search(query: String) -> [LibraryTrack] {
        let snapshot = tracksSnapshot
        guard !query.isEmpty else { return snapshot }
        
        let lowercaseQuery = query.lowercased()
        return snapshot.filter { track in
            track.title.lowercased().contains(lowercaseQuery) ||
            (track.artist?.lowercased().contains(lowercaseQuery) ?? false) ||
            (track.album?.lowercased().contains(lowercaseQuery) ?? false)
        }
    }
    
    /// Filter and sort tracks
    func filteredTracks(filter: LibraryFilter, sortBy: LibrarySortOption, ascending: Bool = true) -> [LibraryTrack] {
        var result = tracksSnapshot
        
        // Apply search filter
        if !filter.searchText.isEmpty {
            let query = filter.searchText.lowercased()
            result = result.filter { track in
                track.title.lowercased().contains(query) ||
                (track.artist?.lowercased().contains(query) ?? false) ||
                (track.album?.lowercased().contains(query) ?? false)
            }
        }
        
        // Apply artist filter
        if !filter.artists.isEmpty {
            result = result.filter { track in
                let albumArtistNames = track.artists.filter { $0.role == .albumArtist }.map { $0.name }
                if albumArtistNames.isEmpty {
                    // Fallback for tracks loaded before backfill completes
                    guard let name = track.albumArtist ?? track.artist else { return false }
                    return filter.artists.contains(name)
                }
                return albumArtistNames.contains { filter.artists.contains($0) }
            }
        }
        
        // Apply album filter
        if !filter.albums.isEmpty {
            result = result.filter { track in
                guard let album = track.album else { return false }
                return filter.albums.contains(album)
            }
        }
        
        // Apply genre filter
        if !filter.genres.isEmpty {
            result = result.filter { track in
                guard let genre = track.genre else { return false }
                return filter.genres.contains(genre)
            }
        }
        
        // Apply year filter
        if let yearRange = filter.yearRange {
            result = result.filter { track in
                guard let year = track.year else { return false }
                return yearRange.contains(year)
            }
        }
        
        // Sort
        result.sort { a, b in
            let comparison: ComparisonResult
            switch sortBy {
            case .title:
                comparison = a.title.localizedCaseInsensitiveCompare(b.title)
            case .artist:
                comparison = (a.artist ?? "").localizedCaseInsensitiveCompare(b.artist ?? "")
            case .album:
                comparison = (a.album ?? "").localizedCaseInsensitiveCompare(b.album ?? "")
            case .dateAdded:
                comparison = a.dateAdded.compare(b.dateAdded)
            case .duration:
                comparison = a.duration < b.duration ? .orderedAscending : (a.duration > b.duration ? .orderedDescending : .orderedSame)
            case .playCount:
                comparison = a.playCount < b.playCount ? .orderedAscending : (a.playCount > b.playCount ? .orderedDescending : .orderedSame)
            }
            return ascending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
        }
        
        return result
    }
    
    // MARK: - Video File Scanning

    /// Scan a single video file, classify it as a movie or TV episode, and add it to the library.
    /// Classification priority: iTunes TV atoms → SxxExx filename pattern → parent "Season N" folder → movie.
    private func scanVideoFile(at url: URL, signature: FileScanSignature? = nil) {
        let path = url.path

        // Skip already-indexed files
        guard dataQueue.sync(execute: { moviesByPath[path] == nil && episodesByPath[path] == nil }) else { return }

        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        let fileSize = signature?.fileSize
            ?? (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
            ?? 0

        var titleFromMetadata: String? = nil
        var yearFromMetadata: Int? = nil
        var tvShowName: String? = nil
        var tvSeasonNumber: Int? = nil
        var tvEpisodeNumber: Int? = nil

        // Common metadata for title and year (works across MP4, MOV, MKV, etc.)
        for format in asset.availableMetadataFormats {
            for item in asset.metadata(forFormat: format) {
                guard let commonKey = item.commonKey else { continue }
                switch commonKey {
                case .commonKeyTitle:
                    if let val = item.stringValue, !val.isEmpty, titleFromMetadata == nil {
                        titleFromMetadata = val
                    }
                case .commonKeyCreationDate:
                    if let yearStr = item.stringValue, let year = Int(yearStr.prefix(4)), yearFromMetadata == nil {
                        yearFromMetadata = year
                    }
                default: break
                }
            }
        }

        // iTunes TV atoms: tvsh (show), tvsn (season), tves (episode number), tven (episode title)
        for item in asset.metadata(forFormat: .iTunesMetadata) {
            guard let key = item.key as? String else { continue }
            switch key {
            case "tvsh": tvShowName = item.stringValue
            case "tvsn": tvSeasonNumber = item.numberValue?.intValue
            case "tves": tvEpisodeNumber = item.numberValue?.intValue
            case "tven": if titleFromMetadata == nil { titleFromMetadata = item.stringValue }
            default: break
            }
        }

        let filename = url.deletingPathExtension().lastPathComponent

        // Filename pattern: "Show Name S01E02", "Show.Name.S01E02", "Show_Name_s1e3", etc.
        if tvShowName == nil {
            let sePattern = #"^(.+?)[.\s_\-]+[Ss](\d{1,2})[Ee](\d{1,2})"#
            if let regex = try? NSRegularExpression(pattern: sePattern),
               let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
               let showRange = Range(match.range(at: 1), in: filename),
               let sRange   = Range(match.range(at: 2), in: filename),
               let eRange   = Range(match.range(at: 3), in: filename) {
                tvShowName = String(filename[showRange])
                    .replacingOccurrences(of: ".", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                tvSeasonNumber = Int(filename[sRange])
                tvEpisodeNumber = Int(filename[eRange])
            }
        }

        // Folder structure: parent is "Season 1" / "S01" → grandparent is the show name
        if tvShowName == nil {
            let parentName = url.deletingLastPathComponent().lastPathComponent
            let grandparentName = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            let seasonPattern = #"^[Ss]eason\s*(\d+)$|^[Ss](\d{1,2})$"#
            if let regex = try? NSRegularExpression(pattern: seasonPattern),
               let match = regex.firstMatch(in: parentName, range: NSRange(parentName.startIndex..., in: parentName)),
               !grandparentName.isEmpty {
                if let r = Range(match.range(at: 1), in: parentName), !parentName[r].isEmpty {
                    tvSeasonNumber = Int(parentName[r]) ?? 1
                } else if let r = Range(match.range(at: 2), in: parentName) {
                    tvSeasonNumber = Int(parentName[r]) ?? 1
                } else {
                    tvSeasonNumber = 1
                }
                tvShowName = grandparentName
            }
        }

        // Classify and store
        if let showTitle = tvShowName, !showTitle.isEmpty {
            var episode = LocalEpisode(url: url, showTitle: showTitle,
                                       seasonNumber: tvSeasonNumber ?? 1,
                                       episodeNumber: tvEpisodeNumber)
            episode.title = titleFromMetadata ?? filename
            episode.duration = duration
            episode.fileSize = fileSize
            var resolvedSig: FileScanSignature?
            var didAdd = false
            dataQueue.sync {
                guard episodesByPath[path] == nil else { return }
                let sig = signature ?? signatureFromFileSystem(url: url, fallbackFileSize: fileSize)
                resolvedSig = sig
                episodes.append(episode)
                episodesByPath[path] = episode
                scanSignaturesByPath[path] = sig ?? FileScanSignature(fileSize: fileSize, contentModificationDate: nil)
                didAdd = true
            }
            if didAdd { store.upsertEpisode(episode, sig: resolvedSig) }
        } else {
            var movie = LocalVideo(url: url)
            movie.title = titleFromMetadata ?? filename
            movie.year = yearFromMetadata
            movie.duration = duration
            movie.fileSize = fileSize
            var resolvedSig: FileScanSignature?
            var didAdd = false
            dataQueue.sync {
                guard moviesByPath[path] == nil else { return }
                let sig = signature ?? signatureFromFileSystem(url: url, fallbackFileSize: fileSize)
                resolvedSig = sig
                movies.append(movie)
                moviesByPath[path] = movie
                scanSignaturesByPath[path] = sig ?? FileScanSignature(fileSize: fileSize, contentModificationDate: nil)
                didAdd = true
            }
            if didAdd { store.upsertMovie(movie, sig: resolvedSig) }
        }
    }

    // MARK: - Metadata Parsing

    /// Parse metadata for a track using AVFoundation
    private func parseMetadata(for track: inout LibraryTrack) {
        let asset = AVAsset(url: track.url)
        
        // Get duration
        track.duration = CMTimeGetSeconds(asset.duration)
        
        // Get file size if not already set by discovery.
        if track.fileSize <= 0,
           let attributes = try? FileManager.default.attributesOfItem(atPath: track.url.path) {
            track.fileSize = attributes[.size] as? Int64 ?? 0
        }
        
        // Parse common metadata
        for format in asset.availableMetadataFormats {
            let metadata = asset.metadata(forFormat: format)
            
            for item in metadata {
                guard let key = item.commonKey?.rawValue else { continue }
                
                switch key {
                case AVMetadataKey.commonKeyTitle.rawValue:
                    if let title = item.stringValue, !title.isEmpty {
                        track.title = title
                    }
                case AVMetadataKey.commonKeyArtist.rawValue:
                    track.artist = item.stringValue
                case AVMetadataKey.commonKeyAlbumName.rawValue:
                    track.album = item.stringValue
                case AVMetadataKey.commonKeyCreationDate.rawValue:
                    if let yearString = item.stringValue, let year = Int(yearString.prefix(4)) {
                        track.year = year
                    }
                default:
                    break
                }
            }
        }
        
        // Parse ID3 specific metadata
        let id3Metadata = asset.metadata(forFormat: .id3Metadata)
        for item in id3Metadata {
            if let key = item.key as? String {
                switch key {
                case "TCON":  // Genre
                    track.genre = item.stringValue
                case "TIT1":  // Content group / grouping
                    track.grouping = item.stringValue
                case "TCOM":  // Composer
                    track.composer = item.stringValue
                case "COMM":  // Comment
                    track.comment = item.stringValue
                case "TBPM":  // BPM
                    if let bpmString = item.stringValue {
                        track.bpm = Int(bpmString)
                    }
                case "TKEY":  // Musical key
                    track.musicalKey = item.stringValue
                case "TCOP":  // Copyright
                    track.copyright = item.stringValue
                case "TSRC":  // ISRC
                    track.isrc = item.stringValue
                case "TRCK":  // Track number
                    if let trackStr = item.stringValue {
                        // Handle "1/10" format
                        let parts = trackStr.split(separator: "/")
                        if let first = parts.first, let num = Int(first) {
                            track.trackNumber = num
                        }
                    }
                case "TPOS":  // Disc number
                    if let discStr = item.stringValue {
                        let parts = discStr.split(separator: "/")
                        if let first = parts.first, let num = Int(first) {
                            track.discNumber = num
                        }
                    }
                case "TPE2":  // Album artist
                    track.albumArtist = item.stringValue
                default:
                    break
                }
            }
        }
        
        // Get audio format info
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            if let formatDescriptions = audioTrack.formatDescriptions as? [CMFormatDescription],
               let formatDesc = formatDescriptions.first {
                let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let desc = audioDesc?.pointee {
                    track.sampleRate = Int(desc.mSampleRate)
                    track.channels = Int(desc.mChannelsPerFrame)
                }
            }
            
            // Estimate bitrate
            if track.duration > 0 {
                track.bitrate = Int(Double(track.fileSize * 8) / track.duration / 1000)
            }
        }

        track.rebuildArtistRoles()
    }
    
    // MARK: - Persistence (SQLite-backed — individual mutations are persisted immediately via store)

    private func loadLibrary() {
        let rawTracks = store.allTracks()
        let trackURLStrings = rawTracks.map { $0.url.absoluteString }
        let artistsByURL = store.artistsForURLs(trackURLStrings)
        let loadedTracks = rawTracks.map { track -> LibraryTrack in
            var t = track
            t.artists = artistsByURL[t.url.absoluteString] ?? []
            return t
        }
        let loadedMovies = store.allMovies()
        let loadedEpisodes = store.allEpisodes()
        let loadedWatchFolders = store.allWatchFolders()
        let loadedAlbumRatings = store.albumRatings()
        let loadedArtistRatings = store.artistRatings()
        let loadedSignatures = store.allSignatures()

        let normalizedWatchFolders = Self.normalizedUniqueWatchFolderURLs(loadedWatchFolders)
        ratingsQueue.sync {
            albumRatings = loadedAlbumRatings
            artistRatings = loadedArtistRatings
        }
        dataQueue.sync {
            tracks = loadedTracks
            watchFolders = normalizedWatchFolders
            movies = loadedMovies
            episodes = loadedEpisodes
            scanSignaturesByPath = loadedSignatures

            // Rebuild indices
            tracksByPath.removeAll()
            for track in tracks { tracksByPath[track.url.path] = track }
            moviesByPath.removeAll()
            for movie in movies { moviesByPath[movie.url.path] = movie }
            episodesByPath.removeAll()
            for episode in episodes { episodesByPath[episode.url.path] = episode }
            scanSignaturesByPath = scanSignaturesByPath.filter { path, _ in
                tracksByPath[path] != nil || moviesByPath[path] != nil || episodesByPath[path] != nil
            }
        }
    }
    
    // MARK: - Backup & Restore
    
    /// Get the library directory URL
    var libraryDirectory: URL {
        libraryURL.deletingLastPathComponent()
    }
    
    /// Get the backups directory URL
    var backupsDirectory: URL {
        libraryDirectory.appendingPathComponent("Backups", isDirectory: true)
    }
    
    /// Create a backup of the library file
    /// - Parameter customName: Optional custom name for the backup (without extension)
    /// - Returns: URL of the created backup file
    @discardableResult
    func backupLibrary(customName: String? = nil) throws -> URL {
        let fileManager = FileManager.default

        // Ensure backups directory exists
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        // Generate backup filename with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let backupName: String
        if let custom = customName, !custom.isEmpty {
            backupName = "\(custom)_\(timestamp).db"
        } else {
            backupName = "library_backup_\(timestamp).db"
        }

        let backupURL = backupsDirectory.appendingPathComponent(backupName)

        guard fileManager.fileExists(atPath: libraryURL.path) else {
            throw LibraryError.noLibraryFile
        }

        // Checkpoint WAL into main DB file so the backup contains all committed data.
        store.checkpoint()
        try fileManager.copyItem(at: libraryURL, to: backupURL)
        NSLog("MediaLibrary: Library backed up to: %@", backupURL.path)

        return backupURL
    }
    
    /// Restore library from a backup file (.db format)
    /// - Parameter backupURL: URL of the backup file to restore
    func restoreLibrary(from backupURL: URL) throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw LibraryError.backupNotFound
        }

        // Validate: try to open the backup as a SQLite DB
        do {
            _ = try Connection(backupURL.path)
        } catch {
            throw LibraryError.invalidBackupFile
        }

        // Create auto-backup of current library before restoring
        if fileManager.fileExists(atPath: libraryURL.path) {
            _ = try? backupLibrary(customName: "pre_restore_auto_backup")
        }

        // Close DB, replace file, reopen
        store.close()

        if fileManager.fileExists(atPath: libraryURL.path) {
            try fileManager.removeItem(at: libraryURL)
        }
        try fileManager.copyItem(at: backupURL, to: libraryURL)

        store.open()
        loadLibrary()

        notifyChange()
        NSLog("MediaLibrary: Library restored from: %@", backupURL.path)
    }
    
    /// List available backup files
    /// - Returns: Array of backup file URLs sorted by date (newest first)
    func listBackups() -> [URL] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: backupsDirectory.path) else {
            return []
        }

        do {
            let contents = try fileManager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey])
            return contents
                .filter { $0.pathExtension == "db" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            NSLog("MediaLibrary: Failed to list backups: %@", error.localizedDescription)
            return []
        }
    }
    
    /// Delete a backup file
    func deleteBackup(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
    
    /// Show the library directory in Finder
    func showLibraryInFinder() {
        NSWorkspace.shared.selectFile(libraryURL.path, inFileViewerRootedAtPath: libraryDirectory.path)
    }
    
    /// Show the backups directory in Finder
    func showBackupsInFinder() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsDirectory.path)
    }
    
    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: nil)
        }
    }

    private func notifyChangeCoalesced(delay: TimeInterval = 0.25) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: nil)
        }
    }

    private func emitScanProgress(generation: Int, processed: Int, total: Int, force: Bool) {
        guard scanGeneration == generation, total > 0 else { return }
        let normalized = min(1.0, max(0.0, Double(processed) / Double(total)))
        let now = CFAbsoluteTimeGetCurrent()

        var shouldEmit = force
        scanProgressStateQueue.sync {
            if !shouldEmit {
                let progressDelta = abs(normalized - lastScanProgressValue)
                let timeDelta = now - lastScanProgressEmitTime
                shouldEmit = progressDelta >= 0.02 || timeDelta >= 0.20
            }
            if shouldEmit {
                lastScanProgressValue = normalized
                lastScanProgressEmitTime = now
            }
        }
        guard shouldEmit else { return }

        DispatchQueue.main.async {
            self.scanProgress = normalized
            NotificationCenter.default.post(name: Self.scanProgressNotification, object: normalized)
        }
    }

    private func makeFastTrack(from file: LocalDiscoveredMediaFile) -> LibraryTrack {
        var track = LibraryTrack(url: file.url)
        track.title = file.url.deletingPathExtension().lastPathComponent
        track.fileSize = file.fileSize
        return track
    }

    private func signature(for file: LocalDiscoveredMediaFile) -> FileScanSignature {
        FileScanSignature(fileSize: file.fileSize, contentModificationDate: file.contentModificationDate)
    }

    private func signatureFromFileSystem(url: URL, fallbackFileSize: Int64 = 0) -> FileScanSignature? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let discoveredSize = values?.fileSize.map(Int64.init) ?? 0
        let fileSize = discoveredSize > 0 ? discoveredSize : fallbackFileSize
        let modificationDate = values?.contentModificationDate
        return FileScanSignature(fileSize: fileSize, contentModificationDate: modificationDate)
    }

    private func metadataWorkerCount(for roots: [URL]) -> Int {
        let hasNonLocalVolume = roots.contains { root in
            let values = try? root.resourceValues(forKeys: [.volumeIsLocalKey])
            return values?.volumeIsLocal == false
        }

        if hasNonLocalVolume {
            return 2
        }

        let suggested = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        return min(8, suggested)
    }

    // MARK: - Helpers
    
    // MARK: - Local Radio

    func createLocalLibraryRadio(limit: Int = 100) -> [Track] {
        let pool = tracksSnapshot.shuffled()
        let tracks = pool.map { $0.toTrack() }
        let historyFiltered = LocalRadioHistory.shared.filterOutHistoryTracks(tracks)
        return filterLocalForArtistVariety(historyFiltered, limit: limit)
    }

    func createLocalGenreRadio(genre: String, limit: Int = 100) -> [Track] {
        var filter = LibraryFilter()
        filter.genres = Set([genre])
        let pool = filteredTracks(filter: filter, sortBy: .title, ascending: true).shuffled()
        let tracks = pool.map { $0.toTrack() }
        let historyFiltered = LocalRadioHistory.shared.filterOutHistoryTracks(tracks)
        return filterLocalForArtistVariety(historyFiltered, limit: limit)
    }

    func createLocalGenreRadioSimilar(seedTrack: Track?, genre: String, limit: Int = 100) -> [Track] {
        return createLocalGenreRadio(genre: genre, limit: limit)
    }

    func createLocalDecadeRadio(start: Int, end: Int, limit: Int = 100) -> [Track] {
        var filter = LibraryFilter()
        filter.yearRange = start...end
        let pool = filteredTracks(filter: filter, sortBy: .title, ascending: true).shuffled()
        let tracks = pool.map { $0.toTrack() }
        let historyFiltered = LocalRadioHistory.shared.filterOutHistoryTracks(tracks)
        return filterLocalForArtistVariety(historyFiltered, limit: limit)
    }

    func createLocalDecadeRadioSimilar(start: Int, end: Int, seedTrack: Track?, limit: Int = 100) -> [Track] {
        return createLocalDecadeRadio(start: start, end: end, limit: limit)
    }

    func createLocalArtistRadio(artist: String, limit: Int = 100) -> [Track] {
        let pool = tracksSnapshot
            .filter { track in
                // Match via track.artists (populated) or fall back to raw field for pre-backfill tracks
                let albumArtistNames = track.artists.filter { $0.role == .albumArtist }.map { $0.name }
                if albumArtistNames.isEmpty {
                    return (track.albumArtist ?? track.artist ?? "").localizedCaseInsensitiveCompare(artist) == .orderedSame
                }
                return albumArtistNames.contains { $0.localizedCaseInsensitiveCompare(artist) == .orderedSame }
            }
            .shuffled()
        let tracks = pool.map { $0.toTrack() }
        let filtered = LocalRadioHistory.shared.filterOutHistoryTracks(tracks)
        return Array(filtered.prefix(limit))
    }

    private func filterLocalForArtistVariety(_ tracks: [Track], limit: Int, maxPerArtist: Int = RadioPlaybackOptions.maxTracksPerArtist) -> [Track] {
        if maxPerArtist <= RadioPlaybackOptions.unlimitedMaxTracksPerArtist {
            return Array(tracks.prefix(limit))
        }
        var result: [Track] = []
        var artistCounts: [String: Int] = [:]
        for track in tracks {
            let artist = track.artist ?? ""
            let count = artistCounts[artist] ?? 0
            if count < maxPerArtist {
                result.append(track)
                artistCounts[artist] = count + 1
            }
            if result.count >= limit { break }
        }
        return result
    }

    private func albumsForTracks(_ tracks: [LibraryTrack]) -> [Album] {
        var albumDict: [String: [LibraryTrack]] = [:]
        
        for track in tracks {
            let albumName = track.album ?? "Unknown Album"
            albumDict[albumName, default: []].append(track)
        }
        
        return albumDict.map { name, tracks in
            let firstTrack = tracks.first
            return Album(
                id: "\(firstTrack?.artist ?? "")|\(name)",
                name: name,
                artist: firstTrack?.albumArtist ?? firstTrack?.artist,
                year: firstTrack?.year,
                tracks: tracks.sorted {
                    // Sort by disc number first, then track number
                    let disc0 = $0.discNumber ?? 1
                    let disc1 = $1.discNumber ?? 1
                    if disc0 != disc1 { return disc0 < disc1 }
                    return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0)
                }
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func normalizedUniqueWatchFolderURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let normalized = normalizedWatchFolderURL(url)
            let path = normalized.path
            if seen.insert(path).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    @discardableResult
    private func removeMissingItemsInWatchedFolders(_ folders: [URL]) -> (tracks: Int, movies: Int, episodes: Int) {
        let folderPaths = Array(Set(folders.map { Self.normalizedPath(for: $0) }))
        guard !folderPaths.isEmpty else { return (0, 0, 0) }

        let fileManager = FileManager.default
        var counts = (tracks: 0, movies: 0, episodes: 0)
        var removedTrackPaths: [String] = []
        var removedMoviePaths: [String] = []
        var removedEpisodePaths: [String] = []

        dataQueue.sync {
            tracks.removeAll { track in
                let normalizedTrackPath = Self.normalizedPath(for: track.url)
                guard Self.isPath(normalizedTrackPath, insideAnyFolderPaths: folderPaths) else { return false }
                guard !fileManager.fileExists(atPath: track.url.path) else { return false }
                tracksByPath.removeValue(forKey: track.url.path)
                scanSignaturesByPath.removeValue(forKey: track.url.path)
                removedTrackPaths.append(track.url.path)
                counts.tracks += 1
                return true
            }

            movies.removeAll { movie in
                let normalizedMoviePath = Self.normalizedPath(for: movie.url)
                guard Self.isPath(normalizedMoviePath, insideAnyFolderPaths: folderPaths) else { return false }
                guard !fileManager.fileExists(atPath: movie.url.path) else { return false }
                moviesByPath.removeValue(forKey: movie.url.path)
                scanSignaturesByPath.removeValue(forKey: movie.url.path)
                removedMoviePaths.append(movie.url.path)
                counts.movies += 1
                return true
            }

            episodes.removeAll { episode in
                let normalizedEpisodePath = Self.normalizedPath(for: episode.url)
                guard Self.isPath(normalizedEpisodePath, insideAnyFolderPaths: folderPaths) else { return false }
                guard !fileManager.fileExists(atPath: episode.url.path) else { return false }
                episodesByPath.removeValue(forKey: episode.url.path)
                scanSignaturesByPath.removeValue(forKey: episode.url.path)
                removedEpisodePaths.append(episode.url.path)
                counts.episodes += 1
                return true
            }
        }

        if counts.tracks > 0 || counts.movies > 0 || counts.episodes > 0 {
            for path in removedTrackPaths { store.deleteTrackByPath(path) }
            for path in removedMoviePaths { store.deleteMovieByPath(path) }
            for path in removedEpisodePaths { store.deleteEpisodeByPath(path) }
            notifyChange()
        }

        return counts
    }
}

// MARK: - Persistence Data Structure

private struct LibraryData: Codable {
    let tracks: [LibraryTrack]
    let watchFolders: [URL]
    let movies: [LocalVideo]
    let episodes: [LocalEpisode]
    let albumRatings: [String: Int]
    let artistRatings: [String: Int]
    let scanSignaturesByPath: [String: FileScanSignature]

    init(tracks: [LibraryTrack], watchFolders: [URL], movies: [LocalVideo],
         episodes: [LocalEpisode], albumRatings: [String: Int], artistRatings: [String: Int],
         scanSignaturesByPath: [String: FileScanSignature]) {
        self.tracks = tracks; self.watchFolders = watchFolders
        self.movies = movies; self.episodes = episodes
        self.albumRatings = albumRatings; self.artistRatings = artistRatings
        self.scanSignaturesByPath = scanSignaturesByPath
    }

    // Backwards-compatible: existing library.json files may lack newer keys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decode([LibraryTrack].self, forKey: .tracks)
        watchFolders = try container.decode([URL].self, forKey: .watchFolders)
        movies = try container.decodeIfPresent([LocalVideo].self, forKey: .movies) ?? []
        episodes = try container.decodeIfPresent([LocalEpisode].self, forKey: .episodes) ?? []
        albumRatings = try container.decodeIfPresent([String: Int].self, forKey: .albumRatings) ?? [:]
        artistRatings = try container.decodeIfPresent([String: Int].self, forKey: .artistRatings) ?? [:]
        scanSignaturesByPath = try container.decodeIfPresent([String: FileScanSignature].self, forKey: .scanSignaturesByPath) ?? [:]
    }
}

// MARK: - Library Errors

enum LibraryError: LocalizedError {
    case noLibraryFile
    case backupNotFound
    case invalidBackupFile
    
    var errorDescription: String? {
        switch self {
        case .noLibraryFile:
            return "No library file exists to backup."
        case .backupNotFound:
            return "The backup file was not found."
        case .invalidBackupFile:
            return "The backup file is invalid or corrupted."
        }
    }
}
