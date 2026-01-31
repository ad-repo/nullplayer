import Foundation
import AVFoundation
import AppKit

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
         playCount: Int = 0) {
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

/// The main media library manager
class MediaLibrary {
    
    // MARK: - Singleton
    
    static let shared = MediaLibrary()
    
    // MARK: - Properties
    
    /// Serial queue to guard library state
    private let dataQueue = DispatchQueue(label: "AdAmp.MediaLibrary.data")
    
    /// All tracks in the library (guarded by dataQueue)
    private var tracks: [LibraryTrack] = []
    
    /// Indexed by URL path for quick lookup (guarded by dataQueue)
    private var tracksByPath: [String: LibraryTrack] = [:]
    
    /// Watch folders for automatic scanning (guarded by dataQueue)
    private var watchFolders: [URL] = []
    
    /// Library file location
    private let libraryURL: URL
    
    /// Whether the library is currently scanning (main thread only)
    private(set) var isScanning = false
    
    /// Scan progress (0.0 - 1.0) (main thread only)
    private(set) var scanProgress: Double = 0
    
    /// Notification names
    static let libraryDidChangeNotification = Notification.Name("MediaLibraryDidChange")
    static let scanProgressNotification = Notification.Name("MediaLibraryScanProgress")
    
    // MARK: - Initialization
    
    private init() {
        // Create library directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let libraryDir = appSupport.appendingPathComponent("AdAmp", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        
        libraryURL = libraryDir.appendingPathComponent("library.json")
        
        loadLibrary()
    }

    // MARK: - Thread-Safe Accessors
    
    var tracksSnapshot: [LibraryTrack] {
        dataQueue.sync { tracks }
    }
    
    var watchFoldersSnapshot: [URL] {
        dataQueue.sync { watchFolders }
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
        
        var didAdd = false
        var result: LibraryTrack?
        
        dataQueue.sync {
            if let existing = tracksByPath[path] {
                result = existing
                return
            }
            
            tracks.append(track)
            tracksByPath[path] = track
            result = track
            didAdd = true
        }
        
        if didAdd {
            notifyChange()
        }
        
        return result
    }
    
    /// Add multiple tracks to the library (quick validates all files first)
    func addTracks(urls: [URL]) {
        // Quick validate all files first (existence + extension - fast)
        let validation = AudioFileValidator.quickValidate(urls: urls)
        
        // Notify about invalid files
        if validation.hasInvalidFiles {
            AudioFileValidator.notifyInvalidFiles(validation.invalidFiles)
        }
        
        // Add valid files (skip validation since we just did it)
        for url in validation.validURLs {
            addTrack(url: url, skipValidation: true)
        }
        saveLibrary()
    }
    
    /// Remove a track from the library
    func removeTrack(_ track: LibraryTrack) {
        dataQueue.sync {
            tracks.removeAll { $0.id == track.id }
            tracksByPath.removeValue(forKey: track.url.path)
        }
        notifyChange()
        saveLibrary()
    }
    
    /// Remove tracks by URL
    func removeTracks(urls: [URL]) {
        dataQueue.sync {
            for url in urls {
                let path = url.path
                tracks.removeAll { $0.url.path == path }
                tracksByPath.removeValue(forKey: path)
            }
        }
        notifyChange()
        saveLibrary()
    }
    
    /// Clear the entire library
    func clearLibrary() {
        dataQueue.sync {
            tracks.removeAll()
            tracksByPath.removeAll()
        }
        notifyChange()
        saveLibrary()
    }
    
    /// Update play statistics for a track
    func recordPlay(for track: LibraryTrack) {
        var didUpdate = false
        dataQueue.sync {
            guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
            
            tracks[index].playCount += 1
            tracks[index].lastPlayed = Date()
            tracksByPath[track.url.path] = tracks[index]
            didUpdate = true
        }
        
        if didUpdate {
            saveLibrary()
        }
    }
    
    // MARK: - Folder Scanning
    
    /// Add a watch folder
    func addWatchFolder(_ url: URL) {
        var didAdd = false
        dataQueue.sync {
            if !watchFolders.contains(url) {
                watchFolders.append(url)
                didAdd = true
            }
        }
        if didAdd {
            saveLibrary()
        }
    }
    
    /// Remove a watch folder
    func removeWatchFolder(_ url: URL) {
        dataQueue.sync {
            watchFolders.removeAll { $0 == url }
        }
        saveLibrary()
    }
    
    /// Scan a folder for audio files
    func scanFolder(_ url: URL, recursive: Bool = true) {
        guard !isScanning else { return }
        
        DispatchQueue.main.async {
            self.isScanning = true
            self.scanProgress = 0
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            let audioExtensions = Set(["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac", "wma"])
            
            var urls: [URL] = []
            
            if recursive {
                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                            urls.append(fileURL)
                        }
                    }
                }
            } else {
                if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    urls = contents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                }
            }
            
            let total = urls.count
            for (index, fileURL) in urls.enumerated() {
                self.addTrack(url: fileURL)
                
                let progress = Double(index + 1) / Double(total)
                DispatchQueue.main.async {
                    self.scanProgress = progress
                    NotificationCenter.default.post(name: Self.scanProgressNotification, object: progress)
                }
            }
            
            DispatchQueue.main.async {
                self.isScanning = false
                self.scanProgress = 1.0
                NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: nil)
            }
            
            self.saveLibrary()
        }
    }
    
    /// Rescan all watch folders
    func rescanWatchFolders() {
        for folder in watchFoldersSnapshot {
            scanFolder(folder)
        }
    }
    
    // MARK: - Querying
    
    /// Get all unique artists
    func allArtists() -> [Artist] {
        var artistDict: [String: [LibraryTrack]] = [:]
        for track in tracksSnapshot {
            let artistName = track.artist ?? "Unknown Artist"
            artistDict[artistName, default: []].append(track)
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
                tracks: tracks.sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
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
                guard let artist = track.artist else { return false }
                return filter.artists.contains(artist)
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
    
    // MARK: - Metadata Parsing
    
    /// Parse metadata for a track using AVFoundation
    private func parseMetadata(for track: inout LibraryTrack) {
        let asset = AVAsset(url: track.url)
        
        // Get duration
        track.duration = CMTimeGetSeconds(asset.duration)
        
        // Get file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: track.url.path) {
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
                case "TCON", "TIT1":  // Genre
                    track.genre = item.stringValue
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
    }
    
    // MARK: - Persistence
    
    private func saveLibrary() {
        let data = dataQueue.sync { LibraryData(tracks: tracks, watchFolders: watchFolders) }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: libraryURL)
        } catch {
            print("Failed to save library: \(error)")
        }
    }
    
    private func loadLibrary() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: libraryURL)
            let decoder = JSONDecoder()
            let libraryData = try decoder.decode(LibraryData.self, from: data)
            dataQueue.sync {
                tracks = libraryData.tracks
                watchFolders = libraryData.watchFolders
                
                // Rebuild index
                tracksByPath.removeAll()
                for track in tracks {
                    tracksByPath[track.url.path] = track
                }
            }
        } catch {
            print("Failed to load library: \(error)")
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
            backupName = "\(custom)_\(timestamp).json"
        } else {
            backupName = "library_backup_\(timestamp).json"
        }
        
        let backupURL = backupsDirectory.appendingPathComponent(backupName)
        
        // Copy the current library file - ensure it exists first
        if !fileManager.fileExists(atPath: libraryURL.path) {
            // If no library file exists, save current state first
            saveLibrary()
        }
        
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            throw LibraryError.noLibraryFile
        }
        
        try fileManager.copyItem(at: libraryURL, to: backupURL)
        print("Library backed up to: \(backupURL.path)")
        
        return backupURL
    }
    
    /// Restore library from a backup file
    /// - Parameter backupURL: URL of the backup file to restore
    func restoreLibrary(from backupURL: URL) throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw LibraryError.backupNotFound
        }
        
        // Validate the backup file is valid JSON
        let data = try Data(contentsOf: backupURL)
        let decoder = JSONDecoder()
        let libraryData = try decoder.decode(LibraryData.self, from: data)
        
        // Create auto-backup of current library before restoring
        if fileManager.fileExists(atPath: libraryURL.path) {
            _ = try? backupLibrary(customName: "pre_restore_auto_backup")
        }
        
        // Replace current library
        if fileManager.fileExists(atPath: libraryURL.path) {
            try fileManager.removeItem(at: libraryURL)
        }
        try fileManager.copyItem(at: backupURL, to: libraryURL)
        
        // Reload the library
        dataQueue.sync {
            tracks = libraryData.tracks
            watchFolders = libraryData.watchFolders
            
            // Rebuild index
            tracksByPath.removeAll()
            for track in tracks {
                tracksByPath[track.url.path] = track
            }
        }
        
        notifyChange()
        print("Library restored from: \(backupURL.path)")
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
                .filter { $0.pathExtension == "json" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            print("Failed to list backups: \(error)")
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
    
    // MARK: - Helpers
    
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
                tracks: tracks.sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Persistence Data Structure

private struct LibraryData: Codable {
    let tracks: [LibraryTrack]
    let watchFolders: [URL]
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
