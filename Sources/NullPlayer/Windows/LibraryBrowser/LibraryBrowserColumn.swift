import Foundation
import NullPlayerCore

/// A column of the library browser's list, shared by the classic and modern views.
struct LibraryBrowserColumn {
    /// A column's identity. The raw value is what the visible-column, width and sort settings save.
    enum ID: String {
        case trackNum, title, artist, album, albumArtist, year, genre, duration, bitrate, sampleRate
        case channels, size, rating, plays, albums, discNum, dateAdded, lastPlayed, youtubeDate
        case thumbnail, path
    }

    let id: ID
    let title: String
    let minWidth: CGFloat

    static let trackNumber = LibraryBrowserColumn(id: .trackNum, title: "#", minWidth: 30)
    static let title = LibraryBrowserColumn(id: .title, title: "Title", minWidth: 120)
    static let artist = LibraryBrowserColumn(id: .artist, title: "Artist", minWidth: 100)
    static let album = LibraryBrowserColumn(id: .album, title: "Album", minWidth: 100)
    static let year = LibraryBrowserColumn(id: .year, title: "Year", minWidth: 45)
    static let genre = LibraryBrowserColumn(id: .genre, title: "Genre", minWidth: 80)
    static let duration = LibraryBrowserColumn(id: .duration, title: "Time", minWidth: 50)
    static let bitrate = LibraryBrowserColumn(id: .bitrate, title: "Bitrate", minWidth: 55)
    static let size = LibraryBrowserColumn(id: .size, title: "Size", minWidth: 55)
    static let rating = LibraryBrowserColumn(id: .rating, title: "Rating", minWidth: 70)
    static let playCount = LibraryBrowserColumn(id: .plays, title: "Plays", minWidth: 45)
    static let albums = LibraryBrowserColumn(id: .albums, title: "Albums", minWidth: 55)
    static let discNumber = LibraryBrowserColumn(id: .discNum, title: "Disc", minWidth: 35)
    static let albumArtist = LibraryBrowserColumn(id: .albumArtist, title: "Album Artist", minWidth: 100)
    static let sampleRate = LibraryBrowserColumn(id: .sampleRate, title: "Sample Rate", minWidth: 60)
    static let channels = LibraryBrowserColumn(id: .channels, title: "Channels", minWidth: 50)
    static let dateAdded = LibraryBrowserColumn(id: .dateAdded, title: "Date Added", minWidth: 80)
    static let lastPlayed = LibraryBrowserColumn(id: .lastPlayed, title: "Last Played", minWidth: 80)
    static let youtubeDate = LibraryBrowserColumn(id: .youtubeDate, title: "Date", minWidth: 70)
    /// Square video thumbnail, drawn as an image rather than text (`drawColumnRow`).
    static let thumbnail = LibraryBrowserColumn(id: .thumbnail, title: "Art", minWidth: 28)
    static let filePath = LibraryBrowserColumn(id: .path, title: "Path", minWidth: 150)

    static let allTrackColumns: [LibraryBrowserColumn] = [
        .trackNumber, .title, .artist, .album, .albumArtist, .year, .genre, .duration,
        .bitrate, .sampleRate, .channels, .size, .rating, .playCount, .discNumber,
        .dateAdded, .lastPlayed, .filePath
    ]
    static let allAlbumColumns: [LibraryBrowserColumn] = [.title, .year, .genre, .duration, .rating]
    static let allArtistColumns: [LibraryBrowserColumn] = [.title, .rating, .albums, .genre]

    static let defaultTrackColumnIds: [String] = [ID.trackNum, .title, .artist, .album, .rating, .year, .genre, .duration, .bitrate, .size, .plays].map(\.rawValue)
    static let defaultAlbumColumnIds: [String] = [ID.title, .year, .genre, .duration, .rating].map(\.rawValue)
    static let defaultArtistColumnIds: [String] = [ID.title, .rating, .albums, .genre].map(\.rawValue)

    /// Fixed columns shown for the Internet Radio source.
    static let internetRadioColumns: [LibraryBrowserColumn] = [.title, .genre, .rating]

    /// Fixed columns shown for YouTube channel uploads (not user-hideable).
    static let youtubeColumns: [LibraryBrowserColumn] = [.thumbnail, .title, .youtubeDate, .duration]
    static let defaultYouTubeColumnIds: [String] = [ID.thumbnail, .title, .youtubeDate, .duration].map(\.rawValue)

    static func all(for group: LibraryColumnVisibilityGroup) -> [LibraryBrowserColumn] {
        switch group {
        case .artist: return allArtistColumns
        case .album: return allAlbumColumns
        case .track: return allTrackColumns
        case .youtube: return youtubeColumns
        }
    }

    static func defaultIds(for group: LibraryColumnVisibilityGroup) -> [String] {
        switch group {
        case .artist: return defaultArtistColumnIds
        case .album: return defaultAlbumColumnIds
        case .track: return defaultTrackColumnIds
        case .youtube: return defaultYouTubeColumnIds
        }
    }

    /// Find a column by ID across all column types
    static func findColumn(id: ID) -> LibraryBrowserColumn? {
        for columns in [allTrackColumns, allAlbumColumns, allArtistColumns, internetRadioColumns, youtubeColumns] {
            if let column = columns.first(where: { $0.id == id }) { return column }
        }
        return nil
    }
}

// MARK: - Column Value Extraction

extension LibraryBrowserItem {

    /// The text a row shows in a column.
    func columnValue(for column: LibraryBrowserColumn) -> String {
        // Title column always uses the display item's title (already set correctly on creation)
        if column.id == .title { return title }

        switch type {
        case .track(let track): return Self.plexTrackValue(track, for: column)
        case .subsonicTrack(let song): return Self.subsonicTrackValue(song, for: column)
        case .localTrack(let track): return Self.localTrackValue(track, for: column)
        case .jellyfinTrack(let song): return Self.jellyfinTrackValue(song, for: column)
        case .embyTrack(let song): return Self.embyTrackValue(song, for: column)
        case .album(let album): return Self.plexAlbumValue(album, for: column)
        case .subsonicAlbum(let album): return Self.subsonicAlbumValue(album, for: column)
        case .localAlbum(let album): return Self.localAlbumValue(album, for: column)
        case .jellyfinAlbum(let album): return Self.jellyfinAlbumValue(album, for: column)
        case .embyAlbum(let album): return Self.embyAlbumValue(album, for: column)
        case .artist(let artist):
            if column.id == .albums, let count = infoCount { return String(count) }
            switch column.id {
            case .albums: return String(artist.albumCount)
            case .genre: return artist.genre ?? ""
            default: return ""
            }
        case .subsonicArtist(let artist):
            return Self.serverArtistValue(albumCount: artist.albumCount, genre: nil,
                                          isFavorite: artist.starred != nil, for: column)
        case .jellyfinArtist(let artist):
            return Self.serverArtistValue(albumCount: artist.albumCount, genre: artist.genre,
                                          isFavorite: artist.isFavorite, for: column)
        case .embyArtist(let artist):
            return Self.serverArtistValue(albumCount: artist.albumCount, genre: artist.genre,
                                          isFavorite: artist.isFavorite, for: column)
        case .localArtist(let artist):
            switch column.id {
            // The row's artist is a stub without albums; its count is in the info text.
            case .albums: return artist.albums.isEmpty ? infoCount.map(String.init) ?? "" : String(artist.albums.count)
            case .rating: return Self.formatTenPointRating(MediaLibrary.shared.artistRating(for: artist.id))
            default: return ""
            }
        case .radioStation(let station):
            switch column.id {
            case .genre: return RadioManager.shared.normalizedGenre(for: station)
            case .rating: return Self.formatStarRating(RadioManager.shared.rating(for: station))
            default: return ""
            }
        case .youtubeVideo(let video):
            switch column.id {
            case .duration: return video.formattedDuration ?? ""
            case .youtubeDate: return video.formattedDate ?? ""
            default: return ""
            }
        default:
            return ""
        }
    }

    /// Returns the raw sortable date for a column, if applicable
    func columnDateValue(for column: LibraryBrowserColumn) -> Date? {
        switch column.id {
        case .dateAdded:
            switch type {
            case .localTrack(let t): return t.dateAdded
            case .track(let t): return t.addedAt
            case .subsonicTrack(let s): return s.created
            case .jellyfinTrack(let s): return s.created
            case .embyTrack(let s): return s.created
            default: return nil
            }
        case .lastPlayed:
            if case .localTrack(let t) = type { return t.lastPlayed }
            return nil
        case .youtubeDate:
            if case .youtubeVideo(let video) = type { return video.publishedAt }
            return nil
        default:
            return nil
        }
    }

    /// The leading number of the info text ("12 albums").
    private var infoCount: Int? {
        info?.split(separator: " ").first.flatMap { Int($0) }
    }

    // MARK: - Tracks

    private static func plexTrackValue(_ track: PlexTrack, for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .trackNum: return trackNumber(disc: track.parentIndex, track: track.index)
        case .artist: return track.grandparentTitle ?? ""
        case .album: return track.parentTitle ?? ""
        case .albumArtist: return track.grandparentTitle ?? ""
        case .year: return track.parentYear.map { String($0) } ?? ""
        case .genre: return track.genre ?? ""
        case .duration: return track.formattedDuration
        case .bitrate: return track.media.first?.bitrate.map { "\($0)k" } ?? ""
        case .sampleRate: return track.media.first?.audioSampleRate.map { formatSampleRate($0) } ?? ""
        case .channels: return track.media.first?.audioChannels.map { formatChannels($0) } ?? ""
        case .size: return formatFileSize(track.media.first?.parts.first?.size)
        case .rating: return formatRating(track.userRating)
        case .plays: return track.ratingCount.map { String($0) } ?? ""
        case .discNum: return track.parentIndex.map { String($0) } ?? ""
        case .dateAdded: return track.addedAt.map { formatDate($0) } ?? ""
        case .path: return track.media.first?.parts.first?.file ?? ""
        default: return ""
        }
    }

    private static func subsonicTrackValue(_ song: SubsonicSong, for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .trackNum: return trackNumber(disc: song.discNumber, track: song.track)
        case .artist: return song.artist ?? ""
        case .album: return song.album ?? ""
        case .albumArtist: return song.albumArtist ?? song.artist ?? ""
        case .year: return song.year.map { String($0) } ?? ""
        case .genre: return song.genre ?? ""
        case .duration: return song.formattedDuration
        case .bitrate: return song.bitRate.map { "\($0)k" } ?? ""
        case .sampleRate: return song.samplingRate.map { formatSampleRate($0) } ?? ""
        case .size: return formatFileSize(song.size)
        case .rating:
            if let userRating = song.userRating, userRating > 0 { return formatRating(Double(userRating * 2)) }
            return song.starred != nil ? favoriteGlyph : formatRating(nil)
        case .plays: return song.playCount.map { String($0) } ?? ""
        case .discNum: return song.discNumber.map { String($0) } ?? ""
        case .dateAdded: return song.created.map { formatDate($0) } ?? ""
        case .path: return song.path ?? ""
        default: return ""
        }
    }

    private static func localTrackValue(_ track: LibraryTrack, for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .trackNum: return trackNumber(disc: track.discNumber, track: track.trackNumber)
        case .artist: return track.artist ?? ""
        case .album: return track.album ?? ""
        case .albumArtist: return track.albumArtist ?? track.artist ?? ""
        case .year: return track.year.map { String($0) } ?? ""
        case .genre: return track.genre ?? ""
        case .duration: return track.formattedDuration
        case .bitrate: return track.bitrate.map { "\($0)k" } ?? ""
        case .sampleRate: return track.sampleRate.map { formatSampleRate($0) } ?? ""
        case .channels: return track.channels.map { formatChannels($0) } ?? ""
        case .size: return formatFileSize(track.fileSize)
        case .rating: return formatRating(track.rating.map { Double($0) })
        case .plays: return track.playCount > 0 ? String(track.playCount) : ""
        case .discNum: return track.discNumber.map { String($0) } ?? ""
        case .dateAdded: return formatDate(track.dateAdded)
        case .lastPlayed: return track.lastPlayed.map { formatDate($0) } ?? ""
        case .path: return track.url.path
        default: return ""
        }
    }

    private static func jellyfinTrackValue(_ song: JellyfinSong, for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .trackNum: return trackNumber(disc: song.discNumber, track: song.track)
        case .artist: return song.artist ?? ""
        case .album: return song.album ?? ""
        case .albumArtist: return song.albumArtist ?? song.artist ?? ""
        case .year: return song.year.map { String($0) } ?? ""
        case .genre: return song.genre ?? ""
        case .duration: return formatDuration(TimeInterval(song.duration))
        case .bitrate: return song.bitRate.map { "\($0)k" } ?? ""
        case .sampleRate: return song.sampleRate.map { formatSampleRate($0) } ?? ""
        case .channels: return song.channels.map { formatChannels($0) } ?? ""
        case .size: return formatFileSize(song.size)
        case .rating: return percentRating(song.userRating, isFavorite: song.isFavorite)
        case .plays: return song.playCount.map { String($0) } ?? ""
        case .discNum: return song.discNumber.map { String($0) } ?? ""
        case .dateAdded: return song.created.map { formatDate($0) } ?? ""
        case .path: return song.path ?? ""
        default: return ""
        }
    }

    private static func embyTrackValue(_ song: EmbySong, for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .trackNum: return trackNumber(disc: song.discNumber, track: song.track)
        case .artist: return song.artist ?? ""
        case .album: return song.album ?? ""
        case .albumArtist: return song.albumArtist ?? song.artist ?? ""
        case .year: return song.year.map { String($0) } ?? ""
        case .genre: return song.genre ?? ""
        case .duration: return song.formattedDuration
        case .bitrate: return song.bitRate.map { "\($0)k" } ?? ""
        case .sampleRate: return song.sampleRate.map { formatSampleRate($0) } ?? ""
        case .channels: return song.channels.map { formatChannels($0) } ?? ""
        case .size: return formatFileSize(song.size)
        case .rating: return percentRating(song.userRating, isFavorite: song.isFavorite)
        case .plays: return song.playCount.map { String($0) } ?? ""
        case .discNum: return song.discNumber.map { String($0) } ?? ""
        case .dateAdded: return song.created.map { formatDate($0) } ?? ""
        case .path: return song.path ?? ""
        default: return ""
        }
    }

    // MARK: - Albums

    private static func plexAlbumValue(_ album: PlexAlbum, for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .year: return album.year.map { String($0) } ?? ""
        case .genre: return album.genre ?? ""
        case .duration: return album.formattedDuration
        default: return ""
        }
    }

    private static func subsonicAlbumValue(_ album: SubsonicAlbum, for column: LibraryBrowserColumn) -> String {
        serverAlbumValue(year: album.year, genre: album.genre, duration: album.formattedDuration,
                         isFavorite: album.starred != nil, for: column)
    }

    private static func jellyfinAlbumValue(_ album: JellyfinAlbum, for column: LibraryBrowserColumn) -> String {
        serverAlbumValue(year: album.year, genre: album.genre, duration: album.formattedDuration,
                         isFavorite: album.isFavorite, for: column)
    }

    private static func embyAlbumValue(_ album: EmbyAlbum, for column: LibraryBrowserColumn) -> String {
        serverAlbumValue(year: album.year, genre: album.genre, duration: album.formattedDuration,
                         isFavorite: album.isFavorite, for: column)
    }

    /// A Subsonic, Jellyfin or Emby album: a starred or favourite album shows five stars.
    private static func serverAlbumValue(year: Int?, genre: String?, duration: String, isFavorite: Bool,
                                         for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .year: return year.map { String($0) } ?? ""
        case .genre: return genre ?? ""
        case .duration: return duration
        case .rating: return isFavorite ? "★★★★★" : ""
        default: return ""
        }
    }

    private static func localAlbumValue(_ album: Album, for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .year: return album.year.map { String($0) } ?? ""
        case .duration: return album.formattedDuration
        case .rating: return formatTenPointRating(MediaLibrary.shared.albumRating(for: album.id))
        default: return ""
        }
    }

    // MARK: - Artists

    /// A Subsonic, Jellyfin or Emby artist. A starred or favourite artist has no rating of its own,
    /// so it shows the favourite glyph rather than a five-star rating.
    private static func serverArtistValue(albumCount: Int, genre: String?, isFavorite: Bool,
                                          for column: LibraryBrowserColumn) -> String {
        switch column.id {
        case .albums: return String(albumCount)
        case .genre: return genre ?? ""
        case .rating: return isFavorite ? favoriteGlyph : ""
        default: return ""
        }
    }

    // MARK: - Formatting

    /// A favourite or starred item that has no rating.
    private static let favoriteGlyph = "★"

    /// "disc-track" for a multi-disc album ("2-5"), otherwise the track number.
    private static func trackNumber(disc: Int?, track: Int?) -> String {
        if let disc, disc > 1, let track { return "\(disc)-\(track)" }
        return track.map { String($0) } ?? ""
    }

    /// Jellyfin and Emby rate out of 100.
    private static func percentRating(_ userRating: Int?, isFavorite: Bool) -> String {
        if let userRating, userRating > 0 { return formatRating(Double(userRating) / 10.0) }
        return isFavorite ? favoriteGlyph : ""
    }

    /// A local album or artist rating out of 10, blank when unrated.
    private static func formatTenPointRating(_ rating: Int?) -> String {
        guard let rating, rating > 0 else { return "" }
        return formatStarRating(rating / 2)
    }

    private static func formatFileSize(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "" }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1000 { return String(format: "%.1fG", mb / 1024.0) }
        return String(format: "%.1fM", mb)
    }

    /// "m:ss", or "h:mm:ss" past an hour.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        let hours = mins / 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, mins % 60, secs) }
        return String(format: "%d:%02d", mins, secs)
    }

    /// A rating out of 10 as five stars.
    private static func formatRating(_ rating: Double?) -> String {
        formatStarRating(rating.map { Int($0 / 2.0) } ?? 0)
    }

    private static func formatStarRating(_ rating: Int) -> String {
        let clamped = min(5, max(0, rating))
        return String(repeating: "★", count: clamped) + String(repeating: "☆", count: 5 - clamped)
    }

    private static func formatSampleRate(_ hz: Int) -> String {
        let khz = Double(hz) / 1000.0
        if khz == Double(Int(khz)) { return "\(Int(khz))k" }
        return String(format: "%.1fk", khz)
    }

    private static func formatChannels(_ count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(count)ch"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
